#!/usr/bin/env bash
#===============================================================================
# @Script: wxo-authenticate-instance.sh
# @Author: Dr. Jeffrey Chijioke-Uche
# @Version: 2.1.0
# @Description:
#   IBM Cloud IAM API-key authentication and Orchestrate agent-list verification.
#   Based on the supplied replacement script, with colored verification output.
# @Location: bob-watsonx-orchestrate-store/wxo-authenticate-instance.sh
#
# Usage:
#   ./wxo-authenticate-instance.sh
#   ENV_FILE=/absolute/path/to/.env ./wxo-authenticate-instance.sh
#   ./wxo-authenticate-instance.sh /absolute/path/to/.env
#
# Environment discovery: explicit path, PROJECT_ROOT/.env, then SCRIPT_DIR/.env.
# The .env is SOURCED AS BASH, as FORENSIC. Use only a trusted local file.
# Existing key, instance-URL and region overrides take precedence over .env.
# No mandatory chmod-600 gate is added; protect credentials with chmod 600.
#
# Requirements: Bash 3.2+, curl 7.55+, Python 3.8+, standard shell utilities.
# Output: colored diagnostics on stderr; stdout is empty (NO bearer-token output).
# Exit: 0 = IAM + agent-list API check passed; 1 = configuration/local error;
#       2 = IAM request failed; 3 = invalid token; 4 = no valid instance response;
#       130/143 = interrupted/terminated.
#
# Deliberate corrections to the supplied source:
#   - Repair Markdown escapes, NBSP indentation, and shell continuations.
#   - A failed HTTP response can NEVER become a successful authentication result.
#   - Validate tokens and JSON responses; do not accept HTML login/error pages.
#   - Use only GET /v1/orchestrate/agents; never probe the bare instance root
#     or the unsupported /v1/agents and /v1/skills shortcuts.
#   - Pass secrets in private files, not curl's argument list; hide entire keys.
#   - WXO_VERIFY_TLS=false/0 is retained, but displays an AMBER unverified-TLS box.
#   - Detect ADK only; never configure or activate it automatically.
#
# Read-only instance probe: no agents, tools or skills are run or modified.
# Requires HTTP 200 and a JSON array of agent records (empty array is valid).
# This verifies list access only, not every service permission or an ADK login.
# API reference: https://developer.watson-orchestrate.ibm.com/apis/agents/list-registered-agents
# No assertion of IBM policy approval/certification is made by this script.
#===============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
    printf 'ERROR: Run this script with Bash, not sh.\n' >&2
    exit 1
fi
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf 'ERROR: Execute this script; do not source it.\n' >&2
    return 1
fi
# Stop tracing before handling credentials, including when called with bash -x.
set +x
set +v
set +a
set -Eeuo pipefail
umask 077

RED='' GREEN='' YELLOW='' CYAN='' BLUE='' BOLD='' NC=''
TMP_DIR=''

configure_colors() {
    RED='' GREEN='' YELLOW='' CYAN='' BLUE='' BOLD='' NC=''
    case "${WXO_COLOR:-auto}" in
        auto) [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-}" != dumb ]] || return 0 ;;
        always) ;;
        never) return 0 ;;
        *) printf 'ERROR: WXO_COLOR must be auto, always, or never.\n' >&2; exit 1 ;;
    esac
    RED=$'\033[1;31m' GREEN=$'\033[1;32m' YELLOW=$'\033[1;33m'
    CYAN=$'\033[1;36m' BLUE=$'\033[1;34m' BOLD=$'\033[1m' NC=$'\033[0m'
}
box() {
    local color="$1" line border
    shift
    printf -v border '%*s' 74 ''
    border="${border// /-}"
    printf '%s+%s+%s\n' "$color" "$border" "$NC" >&2
    for line in "$@"; do
        while (( ${#line} > 72 )); do
            printf '%s| %-72s |%s\n' "$color" "${line:0:72}" "$NC" >&2
            line="${line:72}"
        done
        printf '%s| %-72s |%s\n' "$color" "$line" "$NC" >&2
    done
    printf '%s+%s+%s\n' "$color" "$border" "$NC" >&2
}
log_info()    { printf '%s[WXO-AUTH] [CHECK]%s %s\n' "$CYAN" "$NC" "$*" >&2; }
log_success() { printf '%s[WXO-AUTH] [PASS ]%s %s\n' "$GREEN" "$NC" "$*" >&2; }
log_warn()    { printf '%s[WXO-AUTH] [WARN ]%s %s\n' "$YELLOW" "$NC" "$*" >&2; }
log_error()   { printf '%s[WXO-AUTH] [ERROR]%s %s\n' "$RED" "$NC" "$*" >&2; }
fail() {
    local code="$1"
    shift
    box "$RED" 'AUTHENTICATION / INSTANCE CHECK NOT COMPLETE' "$*" \
        'No successful instance connection is claimed.'
    exit "$code"
}
cleanup() {
    local code=$?
    trap - EXIT ERR
    unset API_KEY PRE_API_KEY ACCESS_TOKEN IBM_CLOUD_API_KEY WXO_API_KEY APIKEY
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR" || printf 'WARNING: Temporary-file cleanup failed.\n' >&2
    fi
    exit "$code"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'trap - ERR; fail 1 "Unexpected local failure at line $LINENO; command contents withheld."' ERR
configure_colors

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    cat <<'HELP'
Usage: wxo-authenticate-instance.sh [path/to/.env]

Config discovery: positional path or ENV_FILE, then ../.env, then ./.env
(relative to this script, not the current working directory).
Only source a trusted Bash-compatible .env. It is executed as shell code.

API-key aliases: IBM_CLOUD_API_KEY, WXO_API_KEY, APIKEY (in that order).
Instance aliases: WXO_IBM_CLOUD_URL, WXO_SERVICE_URL.
Region aliases: WXO_REGION, IBM_CLOUD_REGION.
Optional: WXO_IBM_CLOUD_SERVICE_INSTANCE_ID, IBM_CLOUD_IAM_URL,
          WXO_TIMEOUT_SECONDS=60, WXO_VERIFY_TLS=true,
          WXO_CA_CERT_FILE (or BOB_NODE_EXTRA_CA_CERTS), WXO_COLOR=auto,
          WXO_ENVIRONMENT_NAME=dev, WXO_TARGET=ibm-cloud-saas.

Color: auto | always | never. NO_COLOR disables auto color.
No API key or token is printed. Do not capture this script as TOKEN=$(...).
All diagnostics go to stderr. Check the exit status instead.
The instance URL must end at /instances/<ID>; the script appends
/v1/orchestrate/agents. No base-URL or legacy-route probes are performed.
TLS-disabled checks retain an amber warning even if the requests succeed.
HELP
    exit 0
fi
(( $# <= 1 )) || fail 1 'Supply at most one .env path.'
for tool in curl python3 dirname mktemp chmod rm date; do
    command -v "$tool" >/dev/null 2>&1 || fail 1 "Required executable is missing: $tool"
done

# -----------------------------------------------------------------------------
# Directory & Environment Resolution - supplied appliance layout preserved
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd -P)"
if [[ -n "${1:-${ENV_FILE:-}}" ]]; then
    TARGET_ENV_FILE="${1:-$ENV_FILE}"
elif [[ -f "${PROJECT_ROOT}/.env" ]]; then
    TARGET_ENV_FILE="${PROJECT_ROOT}/.env"
elif [[ -f "${SCRIPT_DIR}/.env" ]]; then
    TARGET_ENV_FILE="${SCRIPT_DIR}/.env"
else
    TARGET_ENV_FILE="${PROJECT_ROOT}/.env"
fi
[[ -f "$TARGET_ENV_FILE" && -r "$TARGET_ENV_FILE" ]] ||
    fail 1 'Configuration is missing or unreadable; set ENV_FILE to the trusted .env file.'
# Make the source path explicit even when called with a relative filename.
TARGET_ENV_FILE="$(cd -- "$(dirname -- "$TARGET_ENV_FILE")" && pwd -P)/${TARGET_ENV_FILE##*/}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/wxo-auth.XXXXXX")"
readonly TMP_DIR
chmod 700 "$TMP_DIR"

# Preserve the caller override priorities from the supplied code.
PRE_API_KEY="${IBM_CLOUD_API_KEY:-${WXO_API_KEY:-${APIKEY:-}}}"
PRE_INSTANCE_URL="${WXO_IBM_CLOUD_URL:-${WXO_SERVICE_URL:-}}"
PRE_REGION="${WXO_REGION:-${IBM_CLOUD_REGION:-}}"
PRE_COLOR="${WXO_COLOR:-}"

log_info 'Loading trusted Bash environment configuration...'
# Source compatibility is intentional. Capture diagnostics to avoid logging
# a secret from a malformed assignment; no untrusted .env may be used here.
set -a
# shellcheck source=/dev/null
if source "$TARGET_ENV_FILE" >"$TMP_DIR/env-output" 2>"$TMP_DIR/env-error"; then
    set +x
    set +v
    set +a
else
    set +x
    set +v
    set +a
    fail 1 'The .env file failed to load. Check its Bash syntax locally; details were not logged.'
fi
set -Eeuo pipefail
umask 077
WXO_COLOR="${PRE_COLOR:-${WXO_COLOR:-auto}}"
configure_colors

# -----------------------------------------------------------------------------
# Configuration Validation & Defaults - supplied names and aliases preserved
# -----------------------------------------------------------------------------
DEFAULT_INSTANCE_URL='https://api.ca-tor.watson-orchestrate.cloud.ibm.com/instances/1794e376-2b61-419c-9999-64d8ea2e5dae'
DEFAULT_REGION='ca-tor'
DEFAULT_IAM_URL='https://iam.cloud.ibm.com'
WXO_INSTANCE_URL="${PRE_INSTANCE_URL:-${WXO_IBM_CLOUD_URL:-${WXO_SERVICE_URL:-$DEFAULT_INSTANCE_URL}}}"
WXO_INSTANCE_URL="${WXO_INSTANCE_URL%/}"
WXO_INSTANCE_ID="${WXO_IBM_CLOUD_SERVICE_INSTANCE_ID:-${WXO_INSTANCE_URL##*/}}"
IAM_ENDPOINT="${IBM_CLOUD_IAM_URL:-$DEFAULT_IAM_URL}"
IAM_ENDPOINT="${IAM_ENDPOINT%/}"
REGION="${PRE_REGION:-${WXO_REGION:-${IBM_CLOUD_REGION:-$DEFAULT_REGION}}}"
TIMEOUT_SECONDS="${WXO_TIMEOUT_SECONDS:-60}"
VERIFY_TLS="${WXO_VERIFY_TLS:-true}"
CA_CERT_FILE="${WXO_CA_CERT_FILE:-${BOB_NODE_EXTRA_CA_CERTS:-}}"
API_KEY="${PRE_API_KEY:-${IBM_CLOUD_API_KEY:-${WXO_API_KEY:-${APIKEY:-}}}}"
[[ -n "$API_KEY" ]] || fail 1 'Set IBM_CLOUD_API_KEY, WXO_API_KEY, or APIKEY in the .env file.'
case "$API_KEY" in
    *$'\r'*|*$'\n'*) fail 1 'API key contains an illegal carriage return or newline.' ;;
esac
case "$VERIFY_TLS" in
    true|1) VERIFY_TLS=true ;;
    false|0) VERIFY_TLS=false ;;
    *) fail 1 'WXO_VERIFY_TLS must be true/1 or false/0.' ;;
esac
[[ "$TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ && ${#TIMEOUT_SECONDS} -le 4 ]] ||
    fail 1 'WXO_TIMEOUT_SECONDS must be an integer from 1 to 3600.'
(( TIMEOUT_SECONDS <= 3600 )) || fail 1 'WXO_TIMEOUT_SECONDS must not exceed 3600.'

# Prevent transport secrets inherited through the supported aliases from being
# automatically exported to curl, Python, or optional ADK processes.
export -n API_KEY PRE_API_KEY IBM_CLOUD_API_KEY WXO_API_KEY APIKEY ACCESS_TOKEN 2>/dev/null || true

# Validate supplied endpoints without guessing or changing the selected host.
if ! python3 - "$WXO_INSTANCE_URL" "$IAM_ENDPOINT" "$WXO_INSTANCE_ID" "$REGION" \
    "${WXO_ENVIRONMENT_NAME:-dev}" "${WXO_TARGET:-ibm-cloud-saas}" <<'PY_URL'
import sys
from urllib.parse import urlsplit
try:
    for value in sys.argv[1:]:
        if any(ord(c) < 32 or ord(c) == 127 for c in value):
            raise ValueError()
    instance, iam, instance_id = sys.argv[1:4]
    for value in (instance, iam):
        u = urlsplit(value)
        if (u.scheme != 'https' or not u.hostname or u.username is not None
                or u.password is not None or u.query or u.fragment
                or any(c.isspace() for c in value) or '\\' in value):
            raise ValueError()
        _ = u.port
    if not urlsplit(instance).path.endswith('/instances/' + instance_id):
        raise ValueError()
except (ValueError, TypeError):
    sys.exit(1)
PY_URL
then
    fail 1 'Use HTTPS URLs without credentials/query/fragment; the instance URL must end in /instances/<matching-ID>.'
fi
if [[ -n "$CA_CERT_FILE" && ( ! -f "$CA_CERT_FILE" || ! -r "$CA_CERT_FILE" ) ]]; then
    fail 1 'The configured CA certificate file is missing or unreadable.'
fi

box "$CYAN" 'IBM watsonx Orchestrate | Instance Authentication' \
    'Author: Dr. Jeffrey Chijioke-Uche' \
    'IBM Cloud IAM API Key -> Bearer token -> Read-only HTTP verification'
log_info "Configuration: $TARGET_ENV_FILE"
printf '  %-22s : %s\n' \
    'Target environment' "${WXO_ENVIRONMENT_NAME:-dev}" \
    'Deployment target' "${WXO_TARGET:-ibm-cloud-saas}" \
    'Region' "$REGION" \
    'IAM endpoint' "$IAM_ENDPOINT" \
    'Instance service URL' "$WXO_INSTANCE_URL" \
    'Instance ID' "$WXO_INSTANCE_ID" \
    'API key configured' 'Yes (entire value hidden)' \
    'TLS verification' "$VERIFY_TLS" >&2
printf '\n' >&2

# -----------------------------------------------------------------------------
# Curl transport: no redirects/curlrc, no API keys or tokens in argument lists
# -----------------------------------------------------------------------------
CURL_OPTS=(--silent --show-error --proto '=https' --max-time "$TIMEOUT_SECONDS")
TLS_SUMMARY='Certificate verification enabled'
if [[ "$VERIFY_TLS" == false ]]; then
    CURL_OPTS+=(--insecure)
    TLS_SUMMARY='DISABLED - server identity was not verified'
    log_warn 'TLS verification is disabled by WXO_VERIFY_TLS. Use an approved CA instead.'
elif [[ -n "$CA_CERT_FILE" ]]; then
    CURL_OPTS+=(--cacert "$CA_CERT_FILE")
    log_info 'Using the configured CA certificate file.'
fi

# curl's error output is retained privately, not echoed with possible secrets.
request() {
    local method="$1" url="$2" body="$3" headers="$4"
    shift 4
    if HTTP_STATUS="$(curl --disable "${CURL_OPTS[@]}" \
        --request "$method" --url "$url" \
        --header 'Accept: application/json' \
        --dump-header "$headers" --output "$body" \
        --write-out '%{http_code}' "$@" 2>"$TMP_DIR/curl-error")"; then
        CURL_EXIT=0
    else
        CURL_EXIT=$?
    fi
    [[ "$HTTP_STATUS" =~ ^[0-9]{3}$ ]] || HTTP_STATUS='000'
    return 0
}

# -----------------------------------------------------------------------------
# Step 1: IBM Cloud IAM API key -> OAuth access token
# -----------------------------------------------------------------------------
log_info 'Step 1/2: Requesting an IBM Cloud IAM bearer access token...'
printf '%s' "$API_KEY" >"$TMP_DIR/api-key"
request POST "$IAM_ENDPOINT/identity/token" "$TMP_DIR/iam_response.json" "$TMP_DIR/iam_headers.txt" \
    --header 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode 'grant_type=urn:ibm:params:oauth:grant-type:apikey' \
    --data-urlencode "apikey@$TMP_DIR/api-key"
if (( CURL_EXIT != 0 )); then
    fail 2 "IAM transport failed (curl exit $CURL_EXIT). Check TLS, proxy, DNS and connectivity."
fi
[[ "$HTTP_STATUS" == 200 ]] || fail 2 "IAM token request returned HTTP $HTTP_STATUS; no access token accepted."

if ! python3 - "$TMP_DIR" <<'PY_AUTH'
import json
from pathlib import Path
import re
import sys
import time
try:
    root = Path(sys.argv[1])
    data = json.loads((root / 'iam_response.json').read_text(encoding='utf-8'))
    if not isinstance(data, dict) or any(data.get(k) for k in ('error', 'errors', 'errorMessage', 'error_description')):
        raise ValueError()
    token = data.get('access_token')
    if not isinstance(token, str) or not re.fullmatch(r'[A-Za-z0-9._~+/-]+=*', token):
        raise ValueError()
    token_type = data.get('token_type', 'Bearer')
    if not isinstance(token_type, str) or token_type.lower() != 'bearer':
        raise ValueError()
    def number(key):
        value = data.get(key)
        if value is None:
            return None
        if isinstance(value, bool) or not re.fullmatch(r'[0-9]+', str(value)):
            raise ValueError()
        value = int(value)
        if value <= 0 or value > 999999999999:
            raise ValueError()
        return value
    ttl, expiration = number('expires_in'), number('expiration')
    if expiration is not None and expiration <= time.time():
        raise ValueError()
    (root / 'auth_parsed.json').write_text(json.dumps({
        'access_token': token, 'token_type': 'Bearer',
        'expires_in': ttl, 'expiration': expiration}), encoding='utf-8')
    (root / 'authorization-header').write_text('Authorization: Bearer ' + token + '\n', encoding='utf-8')
    lifetime = 'Not reported by IAM' if ttl is None else '{} seconds (~{} minutes)'.format(ttl, ttl // 60)
    (root / 'lifetime').write_text(lifetime + '\n', encoding='utf-8')
except (ValueError, TypeError, OSError, OverflowError):
    sys.exit(1)
PY_AUTH
then
    fail 3 'IAM returned invalid JSON, an invalid/missing bearer token, or invalid/expired token metadata.'
fi
IFS= read -r LIFETIME <"$TMP_DIR/lifetime"
rm -f -- "$TMP_DIR/api-key"
unset API_KEY PRE_API_KEY IBM_CLOUD_API_KEY WXO_API_KEY APIKEY
log_success 'IAM token request accepted; bearer token validated (value hidden).'
log_info "Token lifetime: $LIFETIME"

# -----------------------------------------------------------------------------
# Step 2: Verify the documented read-only List Registered Agents endpoint
#
# Keep WXO_IBM_CLOUD_URL / WXO_SERVICE_URL at the instance base URL.
# The API path is appended here, once. Do not use the instance root as a health
# endpoint or try the unsupported /v1/agents and /v1/skills shortcuts.
# A real HTTP or transport failure on this route remains an explicit failure.
# -----------------------------------------------------------------------------
TARGET_URL="${WXO_INSTANCE_URL}/v1/orchestrate/agents"
log_info 'Step 2/2: Verifying watsonx Orchestrate agent-list access...'
log_info "Testing: $TARGET_URL"
request GET "$TARGET_URL" "$TMP_DIR/probe_resp.json" "$TMP_DIR/probe_headers.txt" \
    --header "@$TMP_DIR/authorization-header"

if (( CURL_EXIT != 0 )); then
    fail 4 "Instance transport failed (curl exit $CURL_EXIT). Check TLS, proxy, DNS and connectivity."
fi
log_info "Endpoint returned HTTP $HTTP_STATUS."
case "$HTTP_STATUS" in
    200) ;;
    401)
        fail 4 'HTTP 401: the instance rejected the bearer token. Check the IAM identity and selected instance.'
        ;;
    403)
        fail 4 'HTTP 403: agent-list access was denied. Review IAM permissions for this instance.'
        ;;
    404)
        fail 4 'HTTP 404 on /v1/orchestrate/agents. Confirm the service instance URL in Orchestrate API details and access to that instance.'
        ;;
    429)
        fail 4 'HTTP 429: request rate limited. Wait according to the service policy before retrying.'
        ;;
    5??)
        fail 4 "HTTP $HTTP_STATUS on the documented API route. The service or an intermediary failed; retry later or contact IBM support if it persists."
        ;;
    3??)
        fail 4 "HTTP $HTTP_STATUS: redirect not followed. Confirm the API service URL, not a browser login URL."
        ;;
    *)
        fail 4 "HTTP $HTTP_STATUS is not accepted for List Registered Agents; HTTP 200 is required."
        ;;
esac

# Verify the documented array response without displaying agent data.
# An empty list is valid. Each returned item must have a non-empty string ID.
# Preserve error-object rejection rather than accepting a successful HTTP code
# containing an application-level failure.
if ! python3 - "$TMP_DIR/probe_resp.json" <<'PY_PROBE'
import json
from pathlib import Path
import sys
try:
    data = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
    if not isinstance(data, list):
        raise ValueError()
    for agent in data:
        if (not isinstance(agent, dict) or not isinstance(agent.get('id'), str)
                or not agent['id'].strip()):
            raise ValueError()
        if any(agent.get(k) for k in ('error', 'errors', 'errorMessage', 'error_description')):
            raise ValueError()
        if agent.get('success') is False or str(agent.get('status', '')).lower() in ('error', 'failed', 'failure'):
            raise ValueError()
        for key in ('status', 'status_code', 'statusCode', 'code'):
            value = agent.get(key)
            if isinstance(value, (str, int)) and str(value).isdigit() and 400 <= int(value) <= 599:
                raise ValueError()
except (ValueError, TypeError, OSError):
    sys.exit(1)
PY_PROBE
then
    fail 4 'HTTP 200 was returned, but the response is not a valid agent list. HTML, malformed JSON, missing IDs and error responses are not accepted.'
fi
PROBE_DETAILS='HTTP 200; agent-list JSON verified'
log_success 'Instance API access verified; agent-list JSON validated (contents hidden).'

# -----------------------------------------------------------------------------
# Summary & ADK presence check
# -----------------------------------------------------------------------------
CHECKED_AT="$(date '+%Y-%m-%d %H:%M:%S %Z')"
SCOPE='Agent-list response validated; no agents were invoked or changed.'
printf '\n' >&2
if [[ "$VERIFY_TLS" == true ]]; then
    box "$GREEN" 'IAM AUTHENTICATION AND INSTANCE API CHECK PASSED' \
        'IBM watsonx Orchestrate | IBM Cloud' '' \
        "Region       : $REGION" "Instance ID  : $WXO_INSTANCE_ID" \
        'IAM          : HTTP 200; bearer token obtained' \
        "Instance API : $PROBE_DETAILS" "Verified URL : $TARGET_URL" \
        "Token TTL    : $LIFETIME" "TLS          : $TLS_SUMMARY" \
        "Checked at   : $CHECKED_AT" '' "$SCOPE" \
        'This does not validate every service permission or ADK login.'
else
    box "$YELLOW" 'REQUESTS PASSED - TLS SERVER IDENTITY NOT VERIFIED' \
        'WXO_VERIFY_TLS=false was explicitly configured.' \
        "Instance ID  : $WXO_INSTANCE_ID" "Instance API : $PROBE_DETAILS" \
        "Verified URL : $TARGET_URL" \
        'Use WXO_VERIFY_TLS=true with an approved CA bundle for secure checks.'
fi
if command -v orchestrate >/dev/null 2>&1; then
    log_info 'The orchestrate CLI is present; no ADK environment was changed or activated.'
    log_info 'Check supported environment commands with: orchestrate env --help'
fi
log_info 'Verification finished. No API key or bearer token was printed or persisted as a login.'
exit 0
