#!/usr/bin/env bash
# load-env.sh - shared loader for IBM Bob credentials/settings used by every script
# in bob-parking-lot/. SOURCE it (do not execute):   source "$SCRIPT_DIR/../load-env.sh"
#
# Credentials are NEVER stored in these scripts or docs. They are read from the
# PROJECT's .env file, which is git-ignored:
#   1. $BOB_ENV_FILE                          (explicit override)
#   2. <repo-root>/.env
#   3. <repo-root>/use-cases/<project>/.env   (first match), then bob-parking-lot/configuration/.env
#
# Safety properties:
#   - the file is PARSED, never executed/sourced
#   - only an allow-list of Bob variables is imported (other secrets stay untouched)
#   - variables already set in the environment are never overridden
#   - nothing is printed, so no secret can reach logs or terminals

__bob_env_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
__bob_env_allowed=" BOB_API_KEY BOBSHELL_API_KEY BOB_ENDPOINT BOB_AUTH_ENDPOINT BOB_REGION BOB_TEAM_ID BOB_INSTANCE_ID BOB_BIN BOB_NODE_EXTRA_CA_CERTS "
__bob_env_file=""

if [ -n "${BOB_ENV_FILE:-}" ]; then
  __bob_env_file="$BOB_ENV_FILE"
elif [ -f "$__bob_env_root/.env" ]; then
  __bob_env_file="$__bob_env_root/.env"
else
  for __f in "$__bob_env_root"/use-cases/*/.env "$__bob_env_root"/bob-parking-lot/configuration/.env; do
    if [ -f "$__f" ]; then __bob_env_file="$__f"; break; fi
  done
fi

if [ -n "$__bob_env_file" ] && [ -r "$__bob_env_file" ]; then
  __re_line='^[[:space:]]*(export[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)=(.*)$'
  __re_dq='^"([^"]*)"'
  __re_sq="^'([^']*)'"
  while IFS= read -r __l || [ -n "$__l" ]; do
    __l="${__l%$'\r'}"
    [[ "$__l" =~ $__re_line ]] || continue
    __k="${BASH_REMATCH[2]}"
    __v="${BASH_REMATCH[3]}"
    case "$__bob_env_allowed" in *" $__k "*) ;; *) continue ;; esac
    if [[ "$__v" =~ $__re_dq ]]; then
      __v="${BASH_REMATCH[1]}"
    elif [[ "$__v" =~ $__re_sq ]]; then
      __v="${BASH_REMATCH[1]}"
    else
      __v="${__v%%[[:space:]]#*}"            # drop trailing " # comment"
      __v="${__v%"${__v##*[![:space:]]}"}"   # trim trailing whitespace
    fi
    [ -n "$__v" ] || continue
    if [ -z "${!__k:-}" ]; then export "$__k=$__v"; fi
  done < "$__bob_env_file"
  export BOB_ENV_FILE_LOADED="$__bob_env_file"
fi

unset __bob_env_root __bob_env_allowed __bob_env_file __f __re_line __re_dq __re_sq __l __k __v
return 0 2>/dev/null || true
