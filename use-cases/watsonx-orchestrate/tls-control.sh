#!/usr/bin/env bash
set -Eeuo pipefail

# Load persistent Bob Shell version for appliance version-aware paths.
if [[ -z "${BOB_VERSION:-}" ]]; then
  _BOB_VERSION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${_BOB_VERSION_SCRIPT_DIR}/bob-version.sh" ]]; then
    # shellcheck source=/dev/null
    source "${_BOB_VERSION_SCRIPT_DIR}/bob-version.sh"
  fi
  unset _BOB_VERSION_SCRIPT_DIR
fi

# Security: never allow Bob/Node to run with TLS verification disabled.
unset NODE_TLS_REJECT_UNAUTHORIZED


# Optional: use enterprise CA if provided.
if [[ -n "${BOB_NODE_EXTRA_CA_CERTS:-}" ]]; then
  [[ -f "$BOB_NODE_EXTRA_CA_CERTS" ]] || {
    echo "ERROR: BOB_NODE_EXTRA_CA_CERTS does not exist: $BOB_NODE_EXTRA_CA_CERTS" >&2
    exit 1
  }
  export NODE_EXTRA_CA_CERTS="$BOB_NODE_EXTRA_CA_CERTS"
fi

# BQCA-BOB-SHELL-V2-DNA:BEGIN
# In a trusted Bob Shell 2.x workspace, bind this component to AGENTS.md, the
# active central BQCA policy, exported menu context, current rules/skills/tools,
# and the offline knowledgebase without changing this component's core purpose.
# BQCA-BOB-SHELL-V2-DNA:END
