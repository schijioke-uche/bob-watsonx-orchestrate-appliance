#!/usr/bin/env bash
#===============================================================================
# @Author: Dr. Jeffrey Chijioke-Uche, IBM
# @Description: Bob Shell 2.x authentication, ported from the working v2x benchmark
# BOB2-42: benchmark SHA256 8ff7659eba23a5286f50e83d82d3a96a1ac1039f159a189d1de30c8b161729e4
# @Authentication: Browserless API-key authentication from the appliance .env
#===============================================================================

set -Eeuo pipefail
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TLS_CONTROL_FILE="${SCRIPT_DIR}/tls-control.sh"
ENV_FILE="${SCRIPT_DIR}/.env"
BOB_BIN="${BOB_BIN:-bob}"

log_info() {
  printf '%s\n' "[bob-auth] INFO: $*" >&2
}

fail() {
  printf '%s\n' "[bob-auth] ERROR: $*" >&2
  exit 1
}

# Load this appliance's trusted environment ONCE, then apply the benchmark TLS
# policy. Loading TLS after .env makes enterprise CA settings effective even
# when this helper is executed directly rather than sourced by the launchpad.
[[ -f "${SCRIPT_DIR}/.bob/runtime/bob-v2/load-env.sh" ]] || fail "Patch 42 environment loader is missing"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/.bob/runtime/bob-v2/load-env.sh"
bob2_load_environment "${SCRIPT_DIR}"
unset BOB_AUTH_VALIDATED || true

# Load the appliance TLS policy before invoking Bob.
[[ -f "${TLS_CONTROL_FILE}" ]] || fail "Missing TLS control file: ${TLS_CONTROL_FILE}"
# shellcheck source=/dev/null
source "${TLS_CONTROL_FILE}"

# BOB2-42-PROJECT-ENV-LOAD-GUARD:BEGIN
# bob-auth.sh is sourced into the launcher shell. Do not re-source .env after
# the launcher has resolved its Bob 2.x mode defaults, because the intentionally
# empty BOB2_*_MODE override assignments would erase those values.
[[ -f "${ENV_FILE}" ]] || fail "Missing .env file: ${ENV_FILE}"
if [[ "${BOB2_PROJECT_ENV_LOADED:-0}" != "1" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "${ENV_FILE}"
  set +a
  BOB2_PROJECT_ENV_LOADED=1
  export BOB2_PROJECT_ENV_LOADED
fi
# BOB2-42-PROJECT-ENV-LOAD-GUARD:END

BOB_BIN="${BOB_BIN:-bob}"
command -v "${BOB_BIN}" >/dev/null 2>&1 || \
  fail "Bob CLI command not found: ${BOB_BIN}"

# Detect the installed Bob Shell version from the CLI itself.
BOB_VERSION_RAW="$("${BOB_BIN}" --version 2>&1 || true)"
BOB_VERSION_DETECTED="$(
  printf '%s\n' "${BOB_VERSION_RAW}" |
    tr -d '\r' |
    grep -Eo '[0-9]+([.][0-9]+){1,3}([-.][A-Za-z0-9]+)?' |
    head -n 1 || true
)"
[[ -n "${BOB_VERSION_DETECTED}" ]] || \
  fail "Unable to determine Bob Shell version from: ${BOB_VERSION_RAW:-<empty>}"

BOB_VERSION="${BOB_VERSION_DETECTED}"
BOB_MAJOR_VERSION="${BOB_VERSION%%.*}"
export BOB_VERSION

case "${BOB_MAJOR_VERSION}" in
  2)
    # Bob Shell 2.x+ API-key contract:
    #   - Use BOB_API_KEY directly.
    #   - Do not manufacture legacy token.json/config.json files.
    #   - Do not require or export Bob 1.x endpoint/auth/region overrides.
    : "${BOB_API_KEY:?ERROR: BOB_API_KEY is required in .env for Bob Shell 2.x}"

    # Reject malformed multiline/CRLF secrets before they reach the backend.
    case "${BOB_API_KEY}" in
      *$'\r'*|*$'\n'*) fail "BOB_API_KEY contains a carriage return or newline" ;;
    esac

    export BOB_API_KEY

    # A stale BOBSHELL_API_KEY from Bob 1.x wrappers can select the wrong secret.
    # Bob Shell 2.x officially uses BOB_API_KEY, so remove only the stale alias.
    unset BOBSHELL_API_KEY || true

    # Bob Shell 2.x does not document the 1.x endpoint/auth/region variables for
    # API-key authentication. Prevent stale 1.x values from overriding the 2.x
    # backend unless the operator explicitly opts in.
    if [[ "${BOB2_PRESERVE_LEGACY_ENDPOINT_OVERRIDES:-0}" != "1" ]]; then
      unset BOB_ENDPOINT BOB_AUTH_ENDPOINT BOB_REGION || true
    fi

    # BOB2-42-AUTH-PROBE-ISOLATION:BEGIN
    # Run the Bob 2.x backend probe in an isolated temporary workspace so the
    # probe cannot become the latest task in this appliance workspace.
    PROBE_TIMEOUT_SECONDS="${BOB_AUTH_PROBE_TIMEOUT_SECONDS:-90}"
    [[ "${PROBE_TIMEOUT_SECONDS}" =~ ^[0-9]{1,4}$ ]] && (( 10#${PROBE_TIMEOUT_SECONDS} >= 1 && 10#${PROBE_TIMEOUT_SECONDS} <= 3600 )) || \
      fail "BOB_AUTH_PROBE_TIMEOUT_SECONDS must be an integer from 1 to 3600"

    PROBE_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/bob-auth-v2.XXXXXX")"
    BOB2_AUTH_PROBE_WORKSPACE="$(mktemp -d "${TMPDIR:-/tmp}/bob2-auth-probe-workspace.XXXXXX")"
    chmod 700 "${BOB2_AUTH_PROBE_WORKSPACE}"

    PROBE_ARGS=(
      run
      --mode ask
      --format json
      --max-turns 1
      --disable-mcp
      --disable-subagents
      --workspace "${BOB2_AUTH_PROBE_WORKSPACE}"
      --trust
      --accept-license
    )

    # General-scope API keys require a team context; inference-scope keys do not.
    if [[ -n "${BOB_TEAM_ID:-}" ]]; then
      PROBE_ARGS+=(--team-id "${BOB_TEAM_ID}")
    fi

    PROBE_PROMPT="${BOB_AUTH_PROBE_PROMPT:-BOB2_AUTH_PROBE: Return exactly BOB_AUTH_OK and nothing else.}"

    set +e
    if command -v timeout >/dev/null 2>&1; then
      timeout "${PROBE_TIMEOUT_SECONDS}s" \
        "${BOB_BIN}" "${PROBE_ARGS[@]}" "${PROBE_PROMPT}" \
        >"${PROBE_OUTPUT}" 2>&1
      PROBE_STATUS=$?
    else
      python3 "${SCRIPT_DIR}/.bob/runtime/bob-v2/auth-timeout.py" \
        "${PROBE_TIMEOUT_SECONDS}" "${BOB_BIN}" "${PROBE_ARGS[@]}" "${PROBE_PROMPT}" \
        >"${PROBE_OUTPUT}" 2>&1
      PROBE_STATUS=$?
    fi
    set -e

    rm -rf "${BOB2_AUTH_PROBE_WORKSPACE}"
    unset BOB2_AUTH_PROBE_WORKSPACE
    # BOB2-42-AUTH-PROBE-ISOLATION:END

    if (( PROBE_STATUS == 0 )); then
      rm -f "${PROBE_OUTPUT}"
      printf '%b\n' "${CYAN:-}Bob Shell ${BOB_VERSION} Backend Authentication Validated Successfully!${RESET:-}"
      export BOB_AUTH_VALIDATED=1
    else
      # Print useful diagnostics while masking the active API key. The backend
      # response is retained only in the terminal and not written to the project.
      SAFE_DIAGNOSTIC="$(python3 - "${PROBE_OUTPUT}" <<'PY_MASK'
import os
import pathlib
import sys

text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace")
for name in ("BOB_API_KEY", "BOBSHELL_API_KEY"):
    value = os.environ.get(name, "")
    if value:
        text = text.replace(value, "***REDACTED***")
print(text[-8000:], end="")
PY_MASK
)"
      rm -f "${PROBE_OUTPUT}"

      printf '%s\n' "Bob Shell ${BOB_VERSION} Authentication Failed: Bob CLI could not reach or authenticate with Bob's backend service." >&2
      if (( PROBE_STATUS == 124 )); then
        printf '%s\n' "The Bob backend probe timed out after ${PROBE_TIMEOUT_SECONDS} seconds." >&2
      fi
      if [[ -n "${SAFE_DIAGNOSTIC}" ]]; then
        printf '%s\n' "--- Bob Shell diagnostic (credentials redacted) ---" >&2
        printf '%s\n' "${SAFE_DIAGNOSTIC}" >&2
        printf '%s\n' "--- End diagnostic ---" >&2
      fi
      if [[ -z "${BOB_TEAM_ID:-}" ]]; then
        printf '%s\n' "If this is a general-scope API key, set BOB_TEAM_ID in .env. Inference-scope keys do not require it." >&2
      fi
      printf '%s\n' "Verify BOB_API_KEY, proxy/TLS trust, and Bob service availability. Bob Shell 2.x does not require the legacy BOB_ENDPOINT, BOB_AUTH_ENDPOINT, or BOB_REGION variables for its documented API-key flow." >&2
      exit "${PROBE_STATUS}"
    fi
    ;;

  *)
    fail "Unsupported Bob Shell major version: ${BOB_VERSION}"
    ;;
esac

unset BOB_VERSION_RAW BOB_VERSION_DETECTED BOB_MAJOR_VERSION

# BOB2-42: Domain modes, skills and tools remain owned by this appliance.
