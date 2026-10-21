#!/usr/bin/env bash
#===============================================================================
# @Name: pa-auth-mcp-v0.sh
# @Version: 1.0.0
# @Purpose:
#   Test authentication against the Planning Analytics SaaS MCP server route
#   (<PA_TM1_API_ROOT>/mcp-v0) using the generated API key, with a READ-ONLY
#   MCP handshake: initialize -> notifications/initialized -> tools/list.
#   No tools/call is ever made, so no model data can be read or changed.
#
# Credential styles tested (each is an explicit, independently reported test):
#   bearer     Authorization: Bearer <generated MCP key>
#              (WXO_MCP_CONN_API_KEY, else PA_MCP_SERVER_API_KEY)
#   x-api-key  X-API-Key: <generated MCP key>
#   iam        Authorization: Bearer <token from AWS MCSP exchange of PA_API_KEY>
#              (same flow as pa-saas-auth-v2.sh)
#   pa-basic   Authorization: Basic apikey:<PA_API_KEY> (IBM PA MCSP style)
#
# Usage:
#   ./pa-auth-mcp-v0.sh                       # test every style that has inputs
#   ./pa-auth-mcp-v0.sh --mode iam            # test one style
#   ./pa-auth-mcp-v0.sh --env /path/.env      # explicit configuration file
#   printf '%s' "$KEY" | ./pa-auth-mcp-v0.sh --key-stdin --mode bearer
#   ./pa-auth-mcp-v0.sh --help
#
# Settings (.env or caller shell; caller values win, .env is NEVER sourced):
#   PA_SAAS_REGION, PA_TM1_API_ROOT, PA_API_KEY,
#   WXO_MCP_CONN_API_KEY | PA_MCP_SERVER_API_KEY,
#   optional: PA_MCP_URL, PA_MCP_PROTOCOL_VERSION (2025-03-26),
#             PA_CURL_TIMEOUT (30), PA_CA_BUNDLE, PA_COLOR=auto|always|never
#   PA_ALLOW_OPEN_ENV_MODE=true (caller shell only) downgrades the .env
#   mode-600 requirement to a warning; ownership is still enforced.
#
# Output: UI on stderr. stdout = name of the first passing style (only on pass).
# Exit:   0 at least one style authenticated, 1 setup, 2 IAM exchange (explicit
#         --mode iam), 5 no tested style authenticated.
#
# Safety: keys/tokens never appear in arguments, logs or reports; they travel
#   through curl's stdin config. TLS verification stays on, redirects are not
#   followed, one attempt per request, no database or model mutation.
#===============================================================================

if [ -z "${BASH_VERSION:-}" ]; then
    printf 'ERROR: Run this script with Bash, not sh.\n' >&2
    exit 1
fi
if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    printf 'ERROR: Execute this file; do not source it.\n' >&2
    return 1
fi
set +x +v +a
set -Eeuo pipefail
umask 077
export LC_ALL=C
unset BEARER_TOKEN IAM_TOKEN

RESET='' CYAN='' GREEN='' YELLOW='' RED=''
WORK_DIR=''

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
bad()  { printf '%s[FAIL ]%s %s\n' "$RED" "$RESET" "$*" >&2; }
fail() {
    local code="$1"
    shift
    box "$RED" 'MCP AUTHENTICATION TEST NOT COMPLETE' "$*" 'No secret was written to stdout.'
    exit "$code"
}
cleanup() {
    local rc=$?
    trap - EXIT ERR
    unset PA_API_KEY MCP_KEY IAM_TOKEN WXO_MCP_CONN_API_KEY PA_MCP_SERVER_API_KEY
    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf -- "$WORK_DIR" || printf 'WARNING: Temporary-file cleanup failed.\n' >&2
    fi
    exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'trap - ERR; fail 1 "Unexpected local failure at line $LINENO. No command or secret was logged."' ERR

usage() {
    cat <<'HELP'
Usage: pa-auth-mcp-v0.sh [--env PATH] [--mode all|bearer|x-api-key|iam|pa-basic]
                         [--key-stdin] [--help]

Tests authentication to <PA_TM1_API_ROOT>/mcp-v0 (or PA_MCP_URL) with a
read-only MCP handshake (initialize, initialized, tools/list). No tools are
called. The generated key is WXO_MCP_CONN_API_KEY (or PA_MCP_SERVER_API_KEY),
created by deploy-pa-mcp-server.sh --generate-key.

  bearer     generated MCP key as Authorization: Bearer
  x-api-key  generated MCP key as X-API-Key
  iam        PA_API_KEY exchanged for an AWS MCSP bearer token, then Bearer
  pa-basic   PA_API_KEY as Basic apikey:<key>

Default --mode all: runs every style whose inputs exist and reports each one.
.env search order: --env, $ENV_FILE, ./.env, <script dir>/.env,
<script dir>/../.env, <script dir>/../../.env. Must be owned by you, mode 600
(or PA_ALLOW_OPEN_ENV_MODE=true in the shell).
HELP
}

#-------------------------------------------------------------------------------
# 0. Arguments and dependencies
#-------------------------------------------------------------------------------
OPT_ENV='' OPT_MODE='all' OPT_KEY_STDIN=false
while (( $# )); do
    case "$1" in
        --help|-h) usage; exit 0 ;;
        --env) (( $# >= 2 )) || fail 1 '--env needs a path.'; OPT_ENV="$2"; shift 2 ;;
        --mode) (( $# >= 2 )) || fail 1 '--mode needs a value.'; OPT_MODE="$2"; shift 2 ;;
        --key-stdin) OPT_KEY_STDIN=true; shift ;;
        *) fail 1 "Unknown argument: $1 (see --help)." ;;
    esac
done
case "$OPT_MODE" in all|bearer|x-api-key|iam|pa-basic) ;; *) fail 1 'Invalid --mode; see --help.' ;; esac

(( BASH_VERSINFO[0] >= 4 )) || fail 1 'Bash 4 or newer is required.'
for cmd in curl jq dirname stat mktemp chmod rm date base64 sed grep tr head; do
    command -v "$cmd" >/dev/null 2>&1 || fail 1 "Required command not found: $cmd"
done

# Read the generated key from stdin before anything else touches stdin.
STDIN_KEY=''
if [[ "$OPT_KEY_STDIN" == true ]]; then
    IFS= read -r STDIN_KEY || true
    STDIN_KEY="${STDIN_KEY%$'\r'}"
fi

#-------------------------------------------------------------------------------
# 1. Locate and safely read the .env file (never sourced)
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
CALLER_ENV_FILE="${ENV_FILE-}"
ENV_FILE=''
if [[ -n "$OPT_ENV" ]]; then
    ENV_FILE="$OPT_ENV"
else
    for candidate in "$CALLER_ENV_FILE" "$PWD/.env" \
        "$SCRIPT_DIR/.env" "$SCRIPT_DIR/../.env" "$SCRIPT_DIR/../../.env"; do
        if [[ -n "$candidate" && -f "$candidate" ]]; then ENV_FILE="$candidate"; break; fi
    done
fi
[[ -n "$ENV_FILE" && -f "$ENV_FILE" && -r "$ENV_FILE" ]] ||
    fail 1 'Configuration file not found or unreadable. Use --env /path/to/.env.'

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
        fail 1 '.env permissions must be exactly 600 (chmod 600), or set PA_ALLOW_OPEN_ENV_MODE=true in the shell.'
    fi
fi
[[ "$env_owner" == "$EUID" ]] || fail 1 '.env must be owned by the user executing this script.'

trim() {
    REPLY="${1#"${1%%[![:space:]]*}"}"
    REPLY="${REPLY%"${REPLY##*[![:space:]]}"}"
}
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
    line="${line%$'\r'}"
    if (( line_number == 1 )); then line="${line#$'\357\273\277'}"; fi
    [[ "$line" =~ ^[[:space:]]*(#.*)?$ ]] && continue
    if [[ "$line" =~ $assignment ]]; then
        key="${BASH_REMATCH[2]}"
        raw_value="${BASH_REMATCH[3]}"
        case "$key" in
            PA_SAAS_REGION|PA_TM1_API_ROOT|PA_API_KEY|PA_MCP_URL|PA_MCP_PROTOCOL_VERSION|\
            WXO_MCP_CONN_API_KEY|PA_MCP_SERVER_API_KEY|PA_CURL_TIMEOUT|PA_COLOR|PA_CA_BUNDLE) ;;
            *) continue ;;
        esac
        if [[ -z "${!key+x}" ]]; then
            parse_value "$raw_value" "$line_number"
            printf -v "$key" '%s' "$REPLY"
        fi
    fi
done < "$ENV_FILE"
unset line key raw_value REPLY assignment file_info

#-------------------------------------------------------------------------------
# 2. Bind and validate configuration
#-------------------------------------------------------------------------------
PA_SAAS_REGION="${PA_SAAS_REGION-}"
PA_TM1_API_ROOT="${PA_TM1_API_ROOT-}"
PA_API_KEY="${PA_API_KEY-}"
PA_MCP_URL="${PA_MCP_URL-}"
PA_MCP_PROTOCOL_VERSION="${PA_MCP_PROTOCOL_VERSION-2025-03-26}"
PA_CURL_TIMEOUT="${PA_CURL_TIMEOUT-30}"
PA_COLOR="${PA_COLOR-auto}"
PA_CA_BUNDLE="${PA_CA_BUNDLE-}"
MCP_KEY="${STDIN_KEY:-${WXO_MCP_CONN_API_KEY:-${PA_MCP_SERVER_API_KEY:-}}}"
unset STDIN_KEY
export -n PA_API_KEY MCP_KEY 2>/dev/null || true

case "$PA_COLOR" in
    always) use_color=1 ;;
    never) use_color=0 ;;
    auto) use_color=0; if [[ -t 2 && "${TERM:-dumb}" != dumb ]]; then use_color=1; fi ;;
    *) fail 1 'PA_COLOR must be auto, always, or never.' ;;
esac
[[ -z "${NO_COLOR+x}" ]] || use_color=0
if (( use_color )); then
    RESET=$'\033[0m'; CYAN=$'\033[1;36m'; GREEN=$'\033[1;32m'
    YELLOW=$'\033[1;33m'; RED=$'\033[1;31m'
fi
box "$CYAN" 'IBM PLANNING ANALYTICS | MCP SERVER AUTHENTICATION TEST' \
    'READ-ONLY: initialize + tools/list (no tools are called)' \
    'Script: pa-auth-mcp-v0.sh | Version 1.0.0'

valid_secret() {
    case "$1" in ''|*[[:space:][:cntrl:]'"'\\]*) return 1 ;; esac
    return 0
}

PA_TM1_API_ROOT="${PA_TM1_API_ROOT%/}"
root_pattern='^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?/api/[A-Za-z0-9][A-Za-z0-9._~-]*/v0$'
if [[ -z "$PA_MCP_URL" ]]; then
    [[ "$PA_TM1_API_ROOT" =~ $root_pattern ]] ||
        fail 1 'PA_TM1_API_ROOT must be https://<host>/api/<tenant-id>/v0 (or set PA_MCP_URL).'
    PA_MCP_URL="${PA_TM1_API_ROOT}/mcp-v0"
fi
[[ "$PA_MCP_URL" =~ ^https://[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?(/[A-Za-z0-9._~/-]*)?$ ]] ||
    fail 1 'MCP URL must be https, without credentials, query or fragment.'
[[ "$PA_MCP_PROTOCOL_VERSION" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] ||
    fail 1 'PA_MCP_PROTOCOL_VERSION must look like 2025-03-26.'
[[ "$PA_CURL_TIMEOUT" =~ ^[1-9][0-9]{0,2}$ ]] && (( PA_CURL_TIMEOUT <= 300 )) ||
    fail 1 'PA_CURL_TIMEOUT must be an integer from 1 to 300 seconds.'
if [[ -n "$PA_CA_BUNDLE" ]]; then
    [[ -f "$PA_CA_BUNDLE" && -r "$PA_CA_BUNDLE" ]] || fail 1 'PA_CA_BUNDLE must be a readable PEM CA bundle.'
fi
[[ -z "$MCP_KEY" ]] || valid_secret "$MCP_KEY" ||
    fail 1 'Generated MCP key contains whitespace, control characters, quotes or backslashes.'
[[ -z "$PA_API_KEY" ]] || valid_secret "$PA_API_KEY" ||
    fail 1 'PA_API_KEY contains whitespace, control characters, quotes or backslashes.'
if [[ -n "$PA_API_KEY" && ( "$PA_API_KEY" == REPLACE_* || "$PA_API_KEY" == '<'* || "$PA_API_KEY" == '{'* ) ]]; then
    fail 1 'Replace the PA_API_KEY placeholder with the raw key.'
fi
if [[ "$PA_MCP_URL" == "${PA_TM1_API_ROOT}/mcp-v0" || -n "$PA_TM1_API_ROOT" ]]; then
    [[ "$PA_SAAS_REGION" =~ ^[a-z]{2}(-[a-z0-9]+)+-[0-9]+$ || -z "$PA_API_KEY" ]] ||
        fail 1 'PA_SAAS_REGION must be a region slug such as us-east-1.'
fi
ok "Configuration loaded and validated. MCP endpoint: $PA_MCP_URL"

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pa-auth-mcp.XXXXXXXX")"
chmod 700 "$WORK_DIR"
CURL_OPTIONS=(
    --silent --show-error --globoff --proto '=https' --tlsv1.2
    --connect-timeout "$PA_CURL_TIMEOUT" --max-time "$PA_CURL_TIMEOUT"
    --max-redirs 0 --max-filesize 4194304
    --output "$WORK_DIR/response.txt" --dump-header "$WORK_DIR/headers.txt"
    --write-out '%{http_code}'
)
if [[ -n "$PA_CA_BUNDLE" ]]; then CURL_OPTIONS+=(--cacert "$PA_CA_BUNDLE"); fi

curl_advice() {
    case "$1" in
        5|6) printf 'DNS or proxy-name resolution failed.' ;;
        7) printf 'Could not connect to the endpoint or proxy.' ;;
        28) printf 'Request timed out.' ;;
        35|51|60) printf 'TLS validation failed; use an approved CA bundle, never disable verification.' ;;
        63) printf 'Response exceeded the size limit.' ;;
        *) printf 'Network or local request failure.' ;;
    esac
}

#-------------------------------------------------------------------------------
# 3. MCP request helpers
#-------------------------------------------------------------------------------
# $1 kind (bearer|xapikey|basic) $2 secret $3 JSON body $4 session-id $5 version
# Prints the HTTP status on stdout. Secret goes only through curl stdin config.
mcp_post() {
    local kind="$1" secret="$2" body="$3" session="${4-}" proto="${5-}" rc=0
    printf '%s' "$body" > "$WORK_DIR/request.json"
    : > "$WORK_DIR/response.txt"
    {
        printf 'header = "Content-Type: application/json"\n'
        printf 'header = "Accept: application/json, text/event-stream"\n'
        [[ -z "$session" ]] || printf 'header = "Mcp-Session-Id: %s"\n' "$session"
        [[ -z "$proto" ]] || printf 'header = "MCP-Protocol-Version: %s"\n' "$proto"
        case "$kind" in
            bearer) printf 'header = "Authorization: Bearer %s"\n' "$secret" ;;
            xapikey) printf 'header = "X-API-Key: %s"\n' "$secret" ;;
            basic) printf 'user = "apikey:%s"\nbasic\n' "$secret" ;;
        esac
    } | curl --disable --config - "${CURL_OPTIONS[@]}" --request POST \
        --url "$PA_MCP_URL" --data-binary @"$WORK_DIR/request.json" \
        2> "$WORK_DIR/curl-error" || rc=$?
    return "$rc"
}

# Print the JSON-RPC message with the given id from a JSON or SSE response.
rpc_message() {
    local id="$1" file="$WORK_DIR/response.txt"
    if grep -q '^data:' "$file"; then
        sed -n 's/^data: \{0,1\}//p' "$file" | tr -d '\r'
    else
        cat "$file"
    fi | jq -es --argjson id "$id" '
        [.[] | select(type == "object" and .id == $id)] | first | select(. != null)' 2>/dev/null
}

http_reason() {
    case "$1" in
        401) printf 'HTTP 401: credentials missing, invalid or not accepted by this style.' ;;
        403) printf 'HTTP 403: authenticated but not permitted on the MCP route.' ;;
        404) printf 'HTTP 404: MCP route not found; check host, tenant id or PA_MCP_URL.' ;;
        405|406|415) printf 'HTTP %s: endpoint rejected the MCP request format/transport.' "$1" ;;
        3[0-9][0-9]) printf 'HTTP %s: redirect was not followed.' "$1" ;;
        *) printf 'HTTP %s: unexpected response.' "$1" ;;
    esac
}

MODE_REASON=''
# $1 label $2 kind $3 secret ; returns 0 when initialize AND tools/list succeed.
test_style() {
    local label="$1" kind="$2" secret="$3" code rc msg session='' proto tools
    MODE_REASON=''
    info "[$label] POST initialize"
    if code="$(mcp_post "$kind" "$secret" "$(jq -nc --arg v "$PA_MCP_PROTOCOL_VERSION" '
        {jsonrpc: "2.0", id: 1, method: "initialize", params: {protocolVersion: $v,
         capabilities: {}, clientInfo: {name: "pa-auth-mcp-v0", version: "1.0.0"}}}')")"; then
        :
    else
        rc=$?
        MODE_REASON="initialize failed (curl $rc). $(curl_advice "$rc")"
        return 1
    fi
    if [[ "$code" != 200 ]]; then
        MODE_REASON="initialize: $(http_reason "$code")"
        return 1
    fi
    if ! msg="$(rpc_message 1)" || ! jq -e '.error == null and (.result.protocolVersion | type == "string")' \
        <<< "$msg" >/dev/null 2>&1; then
        MODE_REASON='initialize: HTTP 200 but no valid MCP initialize result (not an MCP response).'
        return 1
    fi
    proto="$(jq -r '.result.protocolVersion' <<< "$msg")"
    ok "[$label] initialize accepted; server $(jq -r '(.result.serverInfo.name // "unknown") + " " + (.result.serverInfo.version // "")' <<< "$msg"), protocol $proto"
    session="$(sed -n 's/^[Mm][Cc][Pp]-[Ss]ession-[Ii][Dd]:[[:space:]]*//p' "$WORK_DIR/headers.txt" | tr -d '\r' | head -n 1)"
    [[ "$session" =~ ^[[:graph:]]*$ && "$session" != *'"'* ]] || session=''

    info "[$label] POST notifications/initialized"
    if code="$(mcp_post "$kind" "$secret" '{"jsonrpc":"2.0","method":"notifications/initialized"}' "$session" "$proto")" &&
        [[ "$code" =~ ^(200|202|204)$ ]]; then
        ok "[$label] initialized notification accepted (HTTP $code)"
    else
        warn "[$label] initialized notification not confirmed (HTTP ${code:-n/a}); continuing."
    fi

    info "[$label] POST tools/list"
    if code="$(mcp_post "$kind" "$secret" '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' "$session" "$proto")"; then
        :
    else
        rc=$?
        MODE_REASON="tools/list failed (curl $rc). $(curl_advice "$rc")"
        return 1
    fi
    if [[ "$code" != 200 ]]; then
        MODE_REASON="tools/list: $(http_reason "$code")"
        return 1
    fi
    if ! msg="$(rpc_message 2)" || ! jq -e '.error == null and (.result.tools | type == "array")' \
        <<< "$msg" >/dev/null 2>&1; then
        MODE_REASON='tools/list: HTTP 200 but no valid tools array.'
        return 1
    fi
    tools="$(jq -r '[.result.tools[].name] | .[0:12] | join(", ")' <<< "$msg")"
    ok "[$label] tools/list returned $(jq -r '.result.tools | length' <<< "$msg") tool(s): ${tools:-none}"
    return 0
}

# AWS MCSP exchange of PA_API_KEY (same endpoint as pa-saas-auth-v2.sh).
get_iam_token() {
    local url="https://${PA_SAAS_REGION}.aws.data.ibm.com/api/rest/mcsp/apikeys/token" code rc=0
    info "[iam] POST $url"
    : > "$WORK_DIR/response.txt"
    code="$(printf '%s' "$PA_API_KEY" | jq -Rs '{apikey: .}' |
        curl --disable "${CURL_OPTIONS[@]}" --request POST --url "$url" \
            --header 'Content-Type: application/json' --header 'Accept: application/json' \
            --data-binary @- 2> "$WORK_DIR/curl-error")" || rc=$?
    if (( rc )); then
        MODE_REASON="IAM token request failed (curl $rc). $(curl_advice "$rc")"
        return 1
    fi
    if [[ ! "$code" =~ ^2[0-9][0-9]$ ]]; then
        MODE_REASON="IAM token exchange returned HTTP $code."
        return 1
    fi
    if ! IAM_TOKEN="$(jq -ers '
        if length != 1 then error("one") else .[0] end
        | select(type == "object" and .error? == null and .errors? == null)
        | (.token // .access_token // empty)
        | select(type == "string" and length > 0 and test("^[A-Za-z0-9._~+/-]+=*$"))
        ' "$WORK_DIR/response.txt" 2>/dev/null)"; then
        MODE_REASON='IAM response had no valid token/access_token.'
        return 1
    fi
    export -n IAM_TOKEN
    ok "[iam] bearer token extracted (not displayed)"
}

#-------------------------------------------------------------------------------
# 4. Run the selected styles
#-------------------------------------------------------------------------------
if [[ "$OPT_MODE" == all ]]; then
    MODES=(bearer x-api-key iam pa-basic)
else
    MODES=("$OPT_MODE")
fi
RESULTS=() PASSED=() FIRST_PASS=''

for style in "${MODES[@]}"; do
    case "$style" in
        bearer|x-api-key) needs=MCP_KEY; have="$MCP_KEY" ;;
        iam|pa-basic) needs=PA_API_KEY; have="$PA_API_KEY" ;;
    esac
    if [[ -z "$have" ]]; then
        if [[ "$OPT_MODE" == all ]]; then
            warn "[$style] skipped: $needs is not set."
            RESULTS+=("$style: SKIPPED ($needs not set)")
            continue
        fi
        fail 1 "Style '$style' needs $needs (set it, or use --key-stdin for the MCP key)."
    fi
    passed=false
    case "$style" in
        bearer)    test_style bearer bearer "$MCP_KEY" && passed=true ;;
        x-api-key) test_style x-api-key xapikey "$MCP_KEY" && passed=true ;;
        pa-basic)  test_style pa-basic basic "$PA_API_KEY" && passed=true ;;
        iam)
            if get_iam_token; then
                test_style iam bearer "$IAM_TOKEN" && passed=true
                unset IAM_TOKEN
            elif [[ "$OPT_MODE" == iam ]]; then
                fail 2 "$MODE_REASON"
            fi
            ;;
    esac
    if [[ "$passed" == true ]]; then
        RESULTS+=("$style: AUTHENTICATED")
        PASSED+=("$style")
        [[ -n "$FIRST_PASS" ]] || FIRST_PASS="$style"
    else
        bad "[$style] $MODE_REASON"
        RESULTS+=("$style: REJECTED - ${MODE_REASON:0:48}")
    fi
done

#-------------------------------------------------------------------------------
# 5. Verdict
#-------------------------------------------------------------------------------
if (( ${#PASSED[@]} )); then
    box "$GREEN" 'MCP SERVER AUTHENTICATION VERIFIED' \
        "Endpoint : $PA_MCP_URL" \
        "Accepted : ${PASSED[*]}" '' "${RESULTS[@]}" '' \
        'Scope    : MCP initialize + tools/list only; no tool was called' \
        'TLS      : Certificate verification enabled' \
        "Checked   : $(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf '%s\n' "$FIRST_PASS"
    exit 0
fi
box "$RED" 'MCP SERVER AUTHENTICATION NOT VERIFIED' \
    "Endpoint : $PA_MCP_URL" '' "${RESULTS[@]}" '' \
    'No tested credential style authenticated.' \
    'The generated MCP key is an inbound key for the local' \
    'pa_mcp_server; the hosted SaaS route may only accept' \
    'IBM-issued credentials (iam / pa-basic). Confirm the' \
    'required style with IBM; nothing was changed.'
exit 5
