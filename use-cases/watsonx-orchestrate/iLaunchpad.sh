#!/usr/bin/env bash
set -Eeuo pipefail
# BOB2-41 MANAGED ENTRYPOINT - @Author: Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
_BOB2_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=/dev/null
source "${_BOB2_ROOT}/.bob/runtime/bob-v2/load-env.sh"
bob2_load_environment "${_BOB2_ROOT}"
_BOB2_LAUNCHER="$(python3 - "$_BOB2_ROOT" <<'PY_LAUNCH'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); config=json.loads((root/'.bob/runtime/bob-v2/appliance.json').read_text())
pattern=re.compile(r'^bob-'+re.escape(config['stem'])+r'-v[0-9].*\.sh$')
files=[p for p in root.iterdir() if pattern.fullmatch(p.name) and p.is_file() and not p.is_symlink()]
if len(files)!=1:
    sys.exit('ERROR: Expected exactly one managed versioned appliance launcher.')
print(files[0])
PY_LAUNCH
)"
exec bash "$_BOB2_LAUNCHER" "$@"
