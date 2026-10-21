#!/usr/bin/env bash
#===============================================================================
# @Author: Dr. Jeffrey Chijioke-Uche
# @Version: 1.1.0
# @Name: pa-saas-auth.sh
# @Purpose:
#   Preserve the supplied API-key -> AWS SaaS IAM bearer-token -> Planning
#   Analytics self-identity probe flow, with validated, color-coded reporting.
#
# IMPORTANT AUTHENTICATION SCOPE
#   The token endpoint below is documented by IBM for watsonx on AWS. Its use
#   with a Planning Analytics tenant is the supplied design, NOT a universal
#   Planning Analytics authentication guarantee. IBM's PA MCSP examples instead
#   document Basic apikey:<key> and paSession. No automatic fallback is made.
#
# Usage:
#   TOKEN=$(./pa-saas-auth.sh /absolute/path/to/.env)
#   TOKEN=$(./pa-saas-auth.sh)
#   ./pa-saas-auth-.sh --help
#
# Default .env: TWO levels above this script's directory, as in the supplied
# implementation. An explicit first argument overrides that location.
# Required: PA_SAAS_REGION, PA_TM1_API_ROOT, PA_API_KEY.
# Optional: PA_SKIP_PROBE=false, PA_CURL_TIMEOUT=30.
# Display/TLS additions: PA_COLOR=auto|always|never, PA_CA_BUNDLE=/path/to/ca.pem.
# Existing caller variables take precedence over .env, including empty values.
#
# Requirements: Bash 4+, curl, jq, dirname, stat, mktemp, chmod, rm, date.
# Output: token ONLY on stdout after FORENSIC checks pass. All UI is stderr.
# Exit: 0 success, 1 setup, 2 token request, 3 token response, 4 identity probe.
#
# Safety:
#   - Execute, do not source. No tokens/API keys in diagnostics or command args.
#   - .env must be a readable regular file owned by you with mode exactly 600.
#     Exception: PA_ALLOW_OPEN_ENV_MODE=true in the CALLER'S SHELL (never read
#     from .env) downgrades the mode check to a warning; ownership is still
#     enforced. Default stays strict.
#   - Only the seven named settings are read; .env is NEVER sourced/evaluated.
#   - No shell/variable expansion in .env; use literal, single-line values.
#   - TLS validation stays enabled; redirects are not followed; one attempt
#     per request. No Basic-auth fallback, AWS signing, or database mutation.
#   - Success verifies the control-plane identity endpoint, NOT a TM1 database.
#   - PA_SKIP_PROBE=true outputs a token but displays an AMBER unverified box.
#   - Keep .env and any captured token out of version control and shared logs.
#
# References:
# https://www.ibm.com/docs/en/watsonx/saas?topic=resources-credentials-programmatic-access
# https://www.ibm.com/support/pages/how-retrieve-and-cancel-jobs-running-planning-analytics-service-database-using-rest-api
# https://curl.se/docs/manpage.html
#===============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
    printf 'ERROR: Run this script with Bash, not sh.\n' >&2
    exit 1
fi
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf 'ERROR: Execute this file; do not source it.\n' >&2
    return 1
fi
# Disable tracing and automatic exporting before handling credentials.
set +x
set +v
set +a
set -Eeuo pipefail
umask 077
export LC_ALL=C
export -n PA_API_KEY 2>/dev/null || true
unset BEARER_TOKEN

RESET='' CYAN='' GREEN='' YELLOW='' RED=''
WORK_DIR=''

# All display, including the success box, goes to stderr.
box() {
    local color="$1" line border
    shift
    printf -v border '%*s' 70 ''
    border="${border// /-}"
    printf '%s+%s+%s\n' "$color" "$border" "$RESET" >&2
    for line in "$@"; do
        while (( ${#line} > 68 )); do
            printf '%s| %-68s |%s\n' "$color" "${line:0:68}" "$RESET" >&2
            line="${line:68}"
        done
        printf '%s| %-68s |%s\n' "$color" "$line" "$RESET" >&2
    done
    printf '%s+%s+%s\n' "$color" "$border" "$RESET" >&2
}
info() { printf '%s[CHECK]%s %s\n' "$CYAN" "$RESET" "$*" >&2; }
ok()   { printf '%s[PASS ]%s %s\n' "$GREEN" "$RESET" "$*" >&2; }
warn() { printf '%s[WARN ]%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
fail() {
    local code="$1"
    shift
    box "$RED" 'FORENSIC VERIFICATION NOT COMPLETE' "$*" \
        'No bearer token was written to stdout.'
    exit "$code"
}
cleanup() {
    local rc=$?
    trap - EXIT ERR
    unset PA_API_KEY BEARER_TOKEN
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR" || printf 'WARNING: Temporary-file cleanup failed.\n' >&2
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'trap - ERR; fail 1 "Unexpected local failure at line $LINENO. No command or secret was logged."' ERR

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    cat <<'HELP'
Usage: pa-saas-auth.sh [path/to/.env]

Default .env: two directories above the script directory, NOT the current folder.
Use an explicit path for a standalone installation. The file must be mode 600
and owned by the executing user. Requires Bash 4+, curl and jq.

Required: PA_SAAS_REGION, PA_TM1_API_ROOT, PA_API_KEY
Optional: PA_SKIP_PROBE=false, PA_CURL_TIMEOUT=30
Optional: PA_CA_BUNDLE (approved PEM CA bundle), PA_COLOR=auto|always|never
NO_COLOR, when set, disables color. Color detection uses STDERR's terminal.

PA_TM1_API_ROOT is the TENANT control-plane root, despite its retained name:
https://<PA-host>/api/<tenant-id>/v0

Capture the token without printing it: TOKEN=$(./pa-saas-auth.sh /path/to/.env)
Do NOT combine stderr with stdout using 2>&1 when capturing the token.
A direct run prints the token to the terminal. No token is emitted on failure.
PA_SKIP_PROBE=true means token issued only; PA connectivity is NOT confirmed.

The preserved AWS IAM exchange is documented for watsonx, not confirmed here
for all Planning Analytics tenants. This script does not change auth methods.
HELP
    exit 0
fi
(( $# <= 1 )) || fail 1 'Supply at most one .env path; see --help.'

#-------------------------------------------------------------------------------
# 0. Dependencies
#-------------------------------------------------------------------------------
(( BASH_VERSINFO[0] >= 4 )) || fail 1 'Bash 4 or newer is required.'
for cmd in curl jq dirname stat mktemp chmod rm date; do
    command -v "$cmd" >/dev/null 2>&1 || fail 1 "Required command not found: $cmd"
done

#-------------------------------------------------------------------------------
# 1. Locate and safely read the .env file (never execute its contents)
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ENV_FILE="${1:-${SCRIPT_DIR}/../../.env}"
[[ -f "$ENV_FILE" && -r "$ENV_FILE" ]] ||
    fail 1 'Configuration file is missing or unreadable. Pass its .env path explicitly.'

# GNU stat on Linux; BSD stat on macOS with an installed Bash 4+.
if file_info="$(stat -Lc '%a %u' -- "$ENV_FILE" 2>/dev/null)"; then
    :
else
    file_info="$(stat -Lf '%Lp %u' "$ENV_FILE" 2>/dev/null)" ||
        fail 1 'Cannot inspect .env permissions and ownership.'
fi
read -r env_mode env_owner <<< "$file_info"
if [[ "$env_mode" != 600 ]]; then
    if [[ "${PA_ALLOW_OPEN_ENV_MODE-}" == true ]]; then
        warn ".env mode is $env_mode, not 600: accepted only because PA_ALLOW_OPEN_ENV_MODE=true. Other local users may read the keys."
    else
        fail 1 '.env permissions must be exactly 600. Run chmod 600 on your .env file (or set PA_ALLOW_OPEN_ENV_MODE=true in the shell to accept a 0777 policy tree).'
    fi
fi
[[ "$env_owner" == "$EUID" ]] || fail 1 '.env must be owned by the user executing this script.'

trim() {
    REPLY="${1#"${1%%[![:space:]]*}"}"
    REPLY="${REPLY%"${REPLY##*[![:space:]]}"}"
}
# Quotes are literal delimiters. No shell escaping, interpolation or eval.
parse_value() {
    local value="$1" number="$2" pattern
    trim "$value"
    value="$REPLY"
    case "${value:0:1}" in
        '"') pattern='^"([^"]*)"[[:space:]]*(#.*)?$' ;;
        "'") pattern="^'([^']*)'[[:space:]]*(#.*)?$" ;;
        *)
            pattern='^(.*[^[:space:]])?[[:space:]]+#.*$'
            if [[ "$value" =~ $pattern ]]; then value="${BASH_REMATCH[1]:-}"; fi
            trim "$value"
            return 0
            ;;
    esac
    [[ "$value" =~ $pattern ]] || fail 1 "Malformed quoted .env value at line $number (value withheld)."
    REPLY="${BASH_REMATCH[1]}"
}
line_number=0
assignment='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$'
while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    line="${line%$'\r'}"  # Accept Windows CRLF configuration files.
    if (( line_number == 1 )); then line="${line#$'\357\273\277'}"; fi
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    if [[ "$line" =~ $assignment ]]; then
        key="${BASH_REMATCH[2]}"
        raw_value="${BASH_REMATCH[3]}"
        case "$key" in
            PA_SAAS_REGION|PA_TM1_API_ROOT|PA_API_KEY|PA_SKIP_PROBE|PA_CURL_TIMEOUT|PA_COLOR|PA_CA_BUNDLE) ;;
            *) continue ;;  # Ignore unrelated appliance settings safely.
        esac
        if [[ -z "${!key+x}" ]]; then
            parse_value "$raw_value" "$line_number"
            printf -v "$key" '%s' "$REPLY"
        fi
    elif [[ "$line" =~ ^[[:space:]]*(export[[:space:]]+)?PA_ ]]; then
        fail 1 "Malformed PA configuration at line $line_number (contents withheld)."
    fi
done < "$ENV_FILE"
unset line key raw_value REPLY assignment file_info

#-------------------------------------------------------------------------------
# 2. Bind configuration (existing caller values retain precedence)
#-------------------------------------------------------------------------------
PA_SAAS_REGION="${PA_SAAS_REGION-}"
PA_TM1_API_ROOT="${PA_TM1_API_ROOT-}"
PA_API_KEY="${PA_API_KEY-}"
PA_SKIP_PROBE="${PA_SKIP_PROBE-false}"
PA_CURL_TIMEOUT="${PA_CURL_TIMEOUT-30}"
PA_COLOR="${PA_COLOR-auto}"
PA_CA_BUNDLE="${PA_CA_BUNDLE-}"
export -n PA_API_KEY

case "$PA_COLOR" in
    always) use_color=1 ;;
    never) use_color=0 ;;
    auto)
        use_color=0
        if [[ -t 2 && "${TERM:-dumb}" != dumb ]]; then use_color=1; fi
        ;;
    *) fail 1 'PA_COLOR must be auto, always, or never.' ;;
esac
[[ -z "${NO_COLOR+x}" ]] || use_color=0
if (( use_color )); then
    RESET=$'\033[0m'; CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'
fi
box "$CYAN" 'IBM PLANNING ANALYTICS | FORENSIC AWS BEARER FLOW' \
    'API-KEY EXCHANGE & READ-ONLY IDENTITY VERIFICATION' \
    'Author: Dr. Jeffrey Chijioke-Uche | Version 1.1.0'
ok 'Dependencies available; protected configuration loaded.'

#-------------------------------------------------------------------------------
# 3. Validate inputs before sending any credentials
#-------------------------------------------------------------------------------
[[ "$PA_SAAS_REGION" =~ ^[a-z]{2}(-[a-z0-9]+)+-[0-9]+$ ]] ||
    fail 1 'PA_SAAS_REGION must be a region slug such as us-east-1.'
PA_TM1_API_ROOT="${PA_TM1_API_ROOT%/}"
root_pattern='^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?/api/([A-Za-z0-9][A-Za-z0-9._~-]*)/v0$'
[[ "$PA_TM1_API_ROOT" =~ $root_pattern ]] ||
    fail 1 'PA_TM1_API_ROOT must be https://<host>/api/<tenant-id>/v0, without credentials, query, or fragment.'
[[ -n "$PA_API_KEY" && "$PA_API_KEY" != *[[:space:][:cntrl:]]* ]] ||
    fail 1 'PA_API_KEY must be a non-empty raw key without whitespace or control characters.'
[[ "$PA_API_KEY" != REPLACE_* && "$PA_API_KEY" != '<'* && "$PA_API_KEY" != '{'* ]] ||
    fail 1 'Replace the API-key placeholder with the raw key, not a JSON document.'
case "$PA_SKIP_PROBE" in true|false) ;; *) fail 1 'PA_SKIP_PROBE must be true or false.' ;; esac
[[ "$PA_CURL_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] && (( PA_CURL_TIMEOUT <= 300 )) ||
    fail 1 'PA_CURL_TIMEOUT must be an integer from 1 to 300 seconds.'
if [[ -n "$PA_CA_BUNDLE" ]]; then
    [[ -f "$PA_CA_BUNDLE" && -r "$PA_CA_BUNDLE" ]] || fail 1 'PA_CA_BUNDLE must be a readable PEM CA bundle.'
fi
ok 'Region, HTTPS tenant root, raw key, and optional settings validated.'

# Private response files may contain tokens or identity data; never print them.
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pa-saas-bearer.XXXXXXXX")"
chmod 700 "$WORK_DIR"
CURL_OPTIONS=(
    --silent --show-error --globoff --proto '=https' --tlsv1.2
    --connect-timeout "$PA_CURL_TIMEOUT" --max-time "$PA_CURL_TIMEOUT"
    --max-redirs 0 --max-filesize 1048576 --header 'Accept: application/json'
    --output "$WORK_DIR/response.json" --write-out '%{http_code}'
)
if [[ -n "$PA_CA_BUNDLE" ]]; then CURL_OPTIONS+=(--cacert "$PA_CA_BUNDLE"); fi

network_failure() {
    local stage="$1" code="$2" curl_rc="$3" advice
    case "$curl_rc" in
        5|6) advice='DNS or proxy-name resolution failed.' ;;
        7) advice='Could not connect to the endpoint or configured proxy.' ;;
        28) advice='Request timed out; check connectivity and timeout settings.' ;;
        35|51|60) advice='TLS validation/handshake failed. Use an approved CA bundle; do not disable verification.' ;;
        58|77) advice='Client/CA certificate configuration could not be read.' ;;
        63) advice='Response exceeded the configured size limit.' ;;
        *) advice='Network or local request failure; no raw server response was logged.' ;;
    esac
    fail "$code" "$stage failed (curl $curl_rc). $advice"
}

#-------------------------------------------------------------------------------
# 4-5. Exchange API key for bearer token using the supplied AWS IAM endpoint
#-------------------------------------------------------------------------------
IAM_TOKEN_URL="https://${PA_SAAS_REGION}.aws.data.ibm.com/api/rest/mcsp/apikeys/token"
info "POST $IAM_TOKEN_URL"
# JSON is encoded by jq. The key travels through stdin, NOT process arguments.
# --disable is curl's FIRST option, preventing ~/.curlrc from changing security.
if IAM_HTTP_STATUS="$(
    printf '%s' "$PA_API_KEY" | jq -Rs '{apikey: .}' |
        curl --disable "${CURL_OPTIONS[@]}" --request POST \
            --url "$IAM_TOKEN_URL" --header 'Content-Type: application/json' \
            --data-binary @- 2> "$WORK_DIR/curl-error"
)"; then
    :
else
    request_rc=$?
    unset PA_API_KEY
    network_failure 'IAM token request' 2 "$request_rc"
fi
unset PA_API_KEY
case "$IAM_HTTP_STATUS" in
    2[0-9][0-9]) ;;
    401|403) fail 2 "IAM returned HTTP $IAM_HTTP_STATUS. Check key validity, region, account access, and this flow's applicability." ;;
    3[0-9][0-9]) fail 2 "IAM returned HTTP $IAM_HTTP_STATUS. Redirect was not followed." ;;
    *) fail 2 "IAM returned HTTP $IAM_HTTP_STATUS. Token exchange failed; check service availability and the configured region." ;;
esac

#-------------------------------------------------------------------------------
# 6. Validate a single JSON token response (same token/access_token precedence)
#-------------------------------------------------------------------------------
if ! BEARER_TOKEN="$(jq -ers '
    if length != 1 then error("Expected one JSON response") else .[0] end
    | select(type == "object" and .error? == null and .errors? == null)
    | (.token // .access_token // empty)
    | select(type == "string" and length > 0)
    | select(test("^[A-Za-z0-9._~+/-]+=*$"))
' "$WORK_DIR/response.json" 2>/dev/null)"; then
    fail 3 'IAM response is not one valid JSON token object, or token/access_token is missing or invalid.'
fi
export -n BEARER_TOKEN
ok "IAM HTTP $IAM_HTTP_STATUS; non-empty bearer token extracted (not displayed)."

#-------------------------------------------------------------------------------
# 7. Optional control-plane probe; this is NOT TM1 OData metadata
#-------------------------------------------------------------------------------
if [[ "$PA_SKIP_PROBE" == false ]]; then
    PROBE_URL="${PA_TM1_API_ROOT}/rolemgmt/v1/users/me"
    info "GET $PROBE_URL"
    # The validated bearer token is passed in curl's stdin configuration.
    if PROBE_HTTP_STATUS="$(
        printf 'header = "Authorization: Bearer %s"\n' "$BEARER_TOKEN" |
            curl --disable --config - "${CURL_OPTIONS[@]}" \
                --request GET --url "$PROBE_URL" 2> "$WORK_DIR/curl-error"
    )"; then
        :
    else
        network_failure 'Planning Analytics identity request' 4 "$?"
    fi
    case "$PROBE_HTTP_STATUS" in
        200) ;;
        401) fail 4 'PA returned HTTP 401. Check token validity, expiry, audience, and whether this tenant accepts this bearer flow.' ;;
        403) fail 4 'PA returned HTTP 403. Verify the user has the required tenant/environment permissions.' ;;
        404) fail 4 'PA returned HTTP 404. Verify the host, tenant ID, and root ending in /v0.' ;;
        3[0-9][0-9]) fail 4 "PA returned HTTP $PROBE_HTTP_STATUS. Redirect was not followed; connectivity is not verified." ;;
        *) fail 4 "PA identity probe returned unexpected HTTP $PROBE_HTTP_STATUS." ;;
    esac
    # Fail closed on HTML, empty/error JSON and unrecognized identity payloads.
    # Presence/shape verification is not a claim about a role or DB permission.
    if ! jq -es '
        if length != 1 then false else
            .[0] | type == "object" and .error? == null and .errors? == null
            and any([.id?, .userId?, .user_id?, .uid?, .username?, .userName?, .email?][];
                if type == "string" then test("[^\\s]")
                elif type == "number" then . >= 0
                else false end)
        end
    ' "$WORK_DIR/response.json" >/dev/null 2>&1; then
        fail 4 'PA HTTP 200 did not contain a recognized JSON identity. No connection success is claimed.'
    fi
    ok 'PA HTTP 200; recognized identity present; no model data was changed.'
    box "$GREEN" 'AUTHENTICATION AND CONNECTION VERIFIED' \
        'IBM Planning Analytics | FORENSIC AWS SaaS bearer flow' '' \
        "Region       : $PA_SAAS_REGION" \
        "API root     : $PA_TM1_API_ROOT" \
        "IAM token    : HTTP $IAM_HTTP_STATUS; valid response; token withheld from logs" \
        'PA identity  : HTTP 200; JSON identity verified' \
        'TM1 database : Not tested (control-plane check only)' \
        'TLS          : Certificate verification enabled' \
        "Checked at   : $(date '+%Y-%m-%d %H:%M:%S %Z')" '' \
        'Bearer token is returned on stdout for the calling program.'
else
    warn 'PA_SKIP_PROBE=true: Planning Analytics access has NOT been verified.'
    box "$YELLOW" 'TOKEN OBTAINED - PLANNING ANALYTICS PROBE SKIPPED' \
        "IAM token    : HTTP $IAM_HTTP_STATUS; valid response" \
        'PA identity  : NOT verified' \
        'TM1 database : NOT tested' \
        'No Planning Analytics connection-success claim is made.'
fi

#-------------------------------------------------------------------------------
# 8. Preserve the supplied token-only stdout contract
#-------------------------------------------------------------------------------
printf '%s\n' "$BEARER_TOKEN"
