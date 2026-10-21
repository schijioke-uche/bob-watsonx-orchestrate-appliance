#!/usr/bin/env bash

# Author: Dr. Jeffrey Chijioke-Uche, Ph.D - IBM Computer Scientist

set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
for TREE in use-cases use-case; do
  if [[ -f "$ROOT/$TREE/watsonx-orchestrate/iLaunchpad.sh" ]]; then
    exec bash "$ROOT/$TREE/watsonx-orchestrate/iLaunchpad.sh" "$@"
  fi
done
printf '%s\n' 'IBM Bob WXO Appliance launchpad not found. Check the Use-Cases directory for iLaunchpad file.' >&2
exit 2
