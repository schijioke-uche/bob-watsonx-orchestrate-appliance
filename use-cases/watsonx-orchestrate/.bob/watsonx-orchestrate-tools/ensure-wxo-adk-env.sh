#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLIANCE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [[ -f "$APPLIANCE_ROOT/bob-version.sh" ]]; then
  # shellcheck source=/dev/null
  source "$APPLIANCE_ROOT/bob-version.sh"
fi

if [[ -f "$APPLIANCE_ROOT/.env" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$APPLIANCE_ROOT/.env"
  set +a
fi

ADK_ENV_NAME="${WXO_ADK_ENV_NAME:-wxo-adk-env}"
ADK_ENV_DIR="${WXO_ADK_ENV_DIR:-$APPLIANCE_ROOT/$ADK_ENV_NAME}"
PYTHON_BIN="${WXO_ADK_PYTHON_BIN:-python3}"
ADK_PACKAGE="${WXO_ADK_PACKAGE:-ibm-watsonx-orchestrate}"
MIN_PYTHON="${WXO_ADK_MIN_PYTHON:-3.11}"

if ! command -v "$PYTHON_BIN" >/dev/null 2>&1; then
  echo "ERROR: Python executable not found: $PYTHON_BIN" >&2
  echo "Install Python ${MIN_PYTHON}+ before building watsonx Orchestrate artifacts." >&2
  exit 1
fi

"$PYTHON_BIN" - <<PY
import sys
required = tuple(int(x) for x in "${MIN_PYTHON}".split(".")[:2])
current = sys.version_info[:2]
if current < required:
    raise SystemExit(f"Python {required[0]}.{required[1]}+ is required; found {current[0]}.{current[1]}")
PY

if [[ ! -d "$ADK_ENV_DIR" ]]; then
  "$PYTHON_BIN" -m venv "$ADK_ENV_DIR"
fi
# shellcheck source=/dev/null
source "$ADK_ENV_DIR/bin/activate"
python -m pip install --upgrade pip >/dev/null
if [[ "${WXO_ADK_UPGRADE:-true}" == "true" ]]; then
  python -m pip install --upgrade "$ADK_PACKAGE"
else
  python -m pip install "$ADK_PACKAGE"
fi

if ! command -v orchestrate >/dev/null 2>&1; then
  echo "ERROR: orchestrate CLI was not found after installing $ADK_PACKAGE" >&2
  exit 1
fi

printf '[WXA ADK] BOB_VERSION=%s\n' "${BOB_VERSION:-1.0.5}"
printf '[WXA ADK] ADK environment: %s\n' "$ADK_ENV_DIR"
printf '[WXA ADK] Python: %s\n' "$(command -v python)"
printf '[WXA ADK] Orchestrate CLI: %s\n' "$(command -v orchestrate)"
orchestrate --help >/dev/null 2>&1 || true
