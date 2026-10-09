#!/usr/bin/env bash
set -Eeuo pipefail

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