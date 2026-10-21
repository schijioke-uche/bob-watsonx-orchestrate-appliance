#!/usr/bin/env bash
#===============================================================================
# @Script: deploy-pa-mcp-server.sh
# @Description: Production deployment, key generation, registration, and
#               connectivity verification for IBM Planning Analytics SaaS MCP Server.
# @Location: bob-watsonx-orchestrate-store/deploy-pa-mcp-server.sh
# @Compliance: Follows appliance design/store separation and security policies.
#===============================================================================

set -Eeuo pipefail
umask 077

# -----------------------------------------------------------------------------
# Directory & Environment Resolution
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
MCP_SERVER_DIR="${SCRIPT_DIR}/planning-analytics-mcp"
BOB_DIR="${PROJECT_ROOT}/.bob"
MCP_CONFIG_FILE="${BOB_DIR}/mcp.json"

# Resolve .env file location
if [[ -n "${ENV_FILE:-}" && -f "${ENV_FILE}" ]]; then
  TARGET_ENV_FILE="${ENV_FILE}"
elif [[ -f "${PROJECT_ROOT}/.env" ]]; then
  TARGET_ENV_FILE="${PROJECT_ROOT}/.env"
elif [[ -f "${SCRIPT_DIR}/.env" ]]; then
  TARGET_ENV_FILE="${SCRIPT_DIR}/.env"
else
  TARGET_ENV_FILE="${PROJECT_ROOT}/.env"
fi

# -----------------------------------------------------------------------------
# Logging and Output Helpers
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

if [[ ! -t 1 ]]; then
  RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' NC=''
fi

log_info() {
  printf '%b[PA-MCP] [INFO]%b %s\n' "${BLUE}" "${NC}" "$*" >&2
}

log_success() {
  printf '%b[PA-MCP] [SUCCESS]%b %s\n' "${GREEN}" "${NC}" "$*" >&2
}

log_warn() {
  printf '%b[PA-MCP] [WARN]%b %s\n' "${YELLOW}" "${NC}" "$*" >&2
}

log_error() {
  printf '%b[PA-MCP] [ERROR]%b %s\n' "${RED}" "${NC}" "$*" >&2
}

fail() {
  log_error "$*"
  exit 1
}

# -----------------------------------------------------------------------------
# Secure Temporary File Management
# -----------------------------------------------------------------------------
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/pa-mcp.XXXXXX")"
chmod 700 "${TMP_DIR}"

cleanup() {
  local exit_code=$?
  if [[ -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
  exit "${exit_code}"
}
trap cleanup EXIT INT TERM

# -----------------------------------------------------------------------------
# Load Environment Variables
# -----------------------------------------------------------------------------
log_info "Loading environment configuration from: ${TARGET_ENV_FILE}"
if [[ ! -f "${TARGET_ENV_FILE}" ]]; then
  log_warn "Environment file not found at ${TARGET_ENV_FILE}."
  if [[ -f "${PROJECT_ROOT}/.env.example" ]]; then
    log_info "Creating ${TARGET_ENV_FILE} from .env.example template..."
    cp "${PROJECT_ROOT}/.env.example" "${TARGET_ENV_FILE}"
    chmod 600 "${TARGET_ENV_FILE}"
  fi
fi

if [[ -f "${TARGET_ENV_FILE}" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${TARGET_ENV_FILE}"
  set +a
fi

# -----------------------------------------------------------------------------
# Configuration Binding
# -----------------------------------------------------------------------------
REGION="${PA_SAAS_REGION:-${PLANNING_ANALYTICS_REGION:-us-east-1}}"
TENANT_ID="${PLANNING_ANALYTICS_TENANT_ID:-I6LGK60NC25B}"
PA_API_ROOT="${PA_TM1_API_ROOT:-https://${REGION}.planninganalytics.saas.ibm.com/api/${TENANT_ID}/v0}"
PA_API_ROOT="${PA_API_ROOT%/}"
IAM_TOKEN_URL="https://${REGION}.aws.data.ibm.com/api/rest/mcsp/apikeys/token"
PA_KEY="${PA_API_KEY:-${PLANNING_ANALYTICS_API_KEY:-}}"
TIMEOUT_SECONDS="${PA_CURL_TIMEOUT:-${WXO_TIMEOUT_SECONDS:-30}}"

# -----------------------------------------------------------------------------
# Step 1: Manage Inbound MCP API Key (WXO_MCP_CONN_API_KEY / PA_MCP_SERVER_API_KEY)
# -----------------------------------------------------------------------------
generate_and_save_mcp_key() {
  local force="${1:-false}"
  local current_key="${WXO_MCP_CONN_API_KEY:-${PA_MCP_SERVER_API_KEY:-}}"

  if [[ -n "${current_key}" && "${force}" != "true" ]]; then
    log_info "Reusing existing inbound MCP API key from environment."
    MCP_KEY="${current_key}"
  else
    log_info "Generating a new cryptographically secure WXO_MCP_CONN_API_KEY..."
    MCP_KEY="$(python3 -c "import secrets; print('pa_mcp_live_' + secrets.token_urlsafe(32))")"
    
    # Save/update in .env file
    if [[ -f "${TARGET_ENV_FILE}" ]]; then
      if grep -q "^export WXO_MCP_CONN_API_KEY=" "${TARGET_ENV_FILE}"; then
        sed -i "s|^export WXO_MCP_CONN_API_KEY=.*|export WXO_MCP_CONN_API_KEY=\"${MCP_KEY}\"|" "${TARGET_ENV_FILE}"
      elif grep -q "^WXO_MCP_CONN_API_KEY=" "${TARGET_ENV_FILE}"; then
        sed -i "s|^WXO_MCP_CONN_API_KEY=.*|WXO_MCP_CONN_API_KEY=\"${MCP_KEY}\"|" "${TARGET_ENV_FILE}"
      elif grep -q "^export PA_MCP_SERVER_API_KEY=" "${TARGET_ENV_FILE}"; then
        sed -i "s|^export PA_MCP_SERVER_API_KEY=.*|export PA_MCP_SERVER_API_KEY=\"${MCP_KEY}\"|" "${TARGET_ENV_FILE}"
      else
        printf '\nexport WXO_MCP_CONN_API_KEY="%s"\nexport PA_MCP_SERVER_API_KEY="%s"\n' "${MCP_KEY}" "${MCP_KEY}" >> "${TARGET_ENV_FILE}"
      fi
      log_success "Saved generated MCP API key to ${TARGET_ENV_FILE}"
    fi
  fi

  export WXO_MCP_CONN_API_KEY="${MCP_KEY}"
  export PA_MCP_SERVER_API_KEY="${MCP_KEY}"
  
  # Display MCP API key securely
  printf '\n%b========================================================================%b\n' "${BOLD}" "${NC}"
  printf '%b IBM Planning Analytics MCP Server Inbound Key%b\n' "${BOLD}${CYAN}" "${NC}"
  printf '%b========================================================================%b\n' "${BOLD}" "${NC}"
  printf '  MCP Server Route      : %s/mcp-v0\n' "${PA_API_ROOT}"
  printf '  Inbound API Key       : %b%s%b\n' "${GREEN}${BOLD}" "${MCP_KEY}" "${NC}"
  printf '  Key Status            : Stored in %s (Ready for reuse)\n' "${TARGET_ENV_FILE}"
  printf '%b========================================================================%b\n\n' "${BOLD}" "${NC}"
}

# -----------------------------------------------------------------------------
# Step 2: Validate Planning Analytics SaaS Outbound Connectivity
# -----------------------------------------------------------------------------
verify_pa_connectivity() {
  log_info "Testing connection to IBM Planning Analytics SaaS on AWS..."
  log_info "Region       : ${REGION}"
  log_info "PA API Root  : ${PA_API_ROOT}"
  log_info "IAM Token URL: ${IAM_TOKEN_URL}"

  if [[ -z "${PA_KEY}" ]]; then
    log_warn "PA_API_KEY is not set in ${TARGET_ENV_FILE}."
    log_warn "Add your PA Server API key to ${TARGET_ENV_FILE} to enable live backend requests."
    return 0
  fi

  local iam_body="${TMP_DIR}/iam_resp.json"
  local iam_header="${TMP_DIR}/iam_headers.txt"

  # Step A: Perform AWS MCSP IAM Token Exchange
  log_info "Step A: Requesting IAM Bearer Token from ${IAM_TOKEN_URL}..."
  local iam_code
  iam_code="$(printf '%s' "${PA_KEY}" | python3 -c '
import json, sys
key = sys.stdin.read().strip()
print(json.dumps({"apikey": key}))
' | curl --silent --show-error --max-time "${TIMEOUT_SECONDS}" \
    -X POST "${IAM_TOKEN_URL}" \
    -H "Content-Type: application/json" \
    -H "Accept: application/json" \
    -d @- \
    -D "${iam_header}" \
    -o "${iam_body}" \
    -w "%{http_code}" || true)"

  if [[ ! "${iam_code}" =~ ^(200|201)$ ]]; then
    log_error "IAM token request failed with HTTP status: ${iam_code}"
    if [[ -f "${iam_body}" && -s "${iam_body}" ]]; then
      python3 -c 'import json, sys; d=json.load(open(sys.argv[1])); print("IAM Error:", d.get("error") or d.get("message") or d)' "${iam_body}" >&2 || true
    fi
    fail "MCSP IAM authentication failed. Please verify PA_API_KEY in ${TARGET_ENV_FILE}."
  fi

  BEARER_TOKEN="$(python3 -c '
import json, sys
data = json.load(open(sys.argv[1]))
token = data.get("token") or data.get("access_token", "")
if not token:
    sys.exit(1)
print(token)
' "${iam_body}")"

  if [[ -z "${BEARER_TOKEN}" ]]; then
    fail "Unable to extract bearer token from MCSP IAM response."
  fi
  log_success "IAM Token Exchange Successful (HTTP ${iam_code})!"

  # Step B: Probe Planning Analytics Identity Endpoint
  local probe_url="${PA_API_ROOT}/rolemgmt/v1/users/me"
  log_info "Step B: Querying Planning Analytics user identity at ${probe_url}..."

  local pa_body="${TMP_DIR}/pa_resp.json"
  local pa_header="${TMP_DIR}/pa_headers.txt"

  local pa_code
  pa_code="$(curl --silent --show-error --max-time "${TIMEOUT_SECONDS}" \
    -X GET "${probe_url}" \
    -H "Accept: application/json" \
    -H "Authorization: Bearer ${BEARER_TOKEN}" \
    -D "${pa_header}" \
    -o "${pa_body}" \
    -w "%{http_code}" || true)"

  if [[ "${pa_code}" =~ ^(200|201)$ ]]; then
    log_success "Planning Analytics SaaS connectivity verified (HTTP ${pa_code})!"
    if [[ -f "${pa_body}" && -s "${pa_body}" ]]; then
      python3 -c "
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    user_name = d.get('displayName') or d.get('name') or d.get('email') or d.get('id') or 'Connected'
    roles = d.get('roles', [])
    print('  Authenticated User :', user_name)
    if roles:
        print('  User Roles         :', roles)
except Exception:
    pass
" "${pa_body}" >&2 || true
    fi
  elif [[ "${pa_code}" == "401" || "${pa_code}" == "403" ]]; then
    log_error "Planning Analytics authentication failed (HTTP ${pa_code})."
    log_error "Please verify user permissions and PA_TM1_API_ROOT."
    fail "Planning Analytics verification failed."
  else
    log_warn "Planning Analytics endpoint responded with HTTP ${pa_code}."
  fi
}

# -----------------------------------------------------------------------------
# Step 3: Register MCP Server in .bob/mcp.json
# -----------------------------------------------------------------------------
register_mcp_config() {
  log_info "Registering Planning Analytics MCP Server in ${MCP_CONFIG_FILE}..."
  mkdir -p "${BOB_DIR}"

  python3 - "${MCP_CONFIG_FILE}" "${MCP_SERVER_DIR}" "${TARGET_ENV_FILE}" <<'PY_REG'
import json
import os
import sys

config_file = sys.argv[1]
server_dir = sys.argv[2]
env_file = sys.argv[3]

config = {}
if os.path.exists(config_file):
    try:
        with open(config_file, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception:
        config = {}

if "mcpServers" not in config:
    config["mcpServers"] = {}

config["mcpServers"]["planning-analytics"] = {
    "command": "python3",
    "args": [os.path.join(server_dir, "pa_mcp_server.py")],
    "env": {
        "ENV_FILE": env_file
    }
}

with open(config_file, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)

print(f"[PA-MCP] [SUCCESS] Registered 'planning-analytics' MCP server in {config_file}", file=sys.stderr)
PY_REG
}

# -----------------------------------------------------------------------------
# Step 4: Start Server
# -----------------------------------------------------------------------------
start_server() {
  log_info "Starting IBM Planning Analytics MCP Server over stdio..."
  export PYTHONPATH="${MCP_SERVER_DIR}:${PYTHONPATH:-}"
  exec python3 "${MCP_SERVER_DIR}/pa_mcp_server.py"
}

# -----------------------------------------------------------------------------
# CLI Entrypoint
# -----------------------------------------------------------------------------
ACTION="${1:---all}"

case "${ACTION}" in
  --generate-key)
    generate_and_save_mcp_key "true"
    ;;
  --verify)
    verify_pa_connectivity
    ;;
  --register)
    register_mcp_config
    ;;
  --start)
    generate_and_save_mcp_key "false"
    start_server
    ;;
  --all)
    generate_and_save_mcp_key "false"
    verify_pa_connectivity
    register_mcp_config
    log_success "Planning Analytics MCP server setup complete."
    printf '\nTo start the MCP Server in stdio mode, run:\n'
    printf '  %s/deploy-pa-mcp-server.sh --start\n\n' "${SCRIPT_DIR}"
    ;;
  --help|-h)
    printf 'Usage: %s [--all | --verify | --generate-key | --register | --start]\n' "$0"
    ;;
  *)
    fail "Unknown action: ${ACTION}. Use --help for options."
    ;;
esac
