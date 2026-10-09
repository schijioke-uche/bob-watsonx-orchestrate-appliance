#!/usr/bin/env bash

# @Author: Dr. Jeffrey Chijioke-Uche, IBM
#==================================================================
# Bob Authentication Script - Production Version
# Authenticates Bob CLI using API key from .env without browser
#==================================================================

bob_shell (){

    echo -e "
                                               ────    IBM Bob watsonx Orchestrate Agent (WXA)    ───
                                               ───────────────────── Welcome to ─────────────────────

                                               ▀▀▀▀▀▀▀▀▀▀▀▀▀▀       ▀▀▀▀▀▀▀▀▀▀▀▀     ▀▀▀▀▀▀▀▀▀▀▀▀▀▀
                                               ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
                                                 ▀▀▀▀     ▀▀▀▀▀   ▀▀▀▀        ▀▀▀▀     ▀▀▀▀     ▀▀▀▀▀
                                                 ▀▀▀▀▀▀▀▀▀▀▀▀▘    ▀▀▀▀        ▀▀▀▀     ▀▀▀▀▀▀▀▀▀▀▀▀▘
                                                 ▀▀▀▀▀▀▀▀▀▀▀▀▘    ▀▀▀▀        ▀▀▀▀     ▀▀▀▀▀▀▀▀▀▀▀▀▘
                                                 ▀▀▀▀     ▀▀▀▀▀   ▀▀▀▀        ▀▀▀▀     ▀▀▀▀     ▀▀▀▀▀
                                               ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀    ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀
                                               ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀      ▀▀▀▀▀▀▀▀▀▀▀▀     ▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀

                                               ░░░░░░░░░█▀▀▀░░░░█░░█░░░░█▀▀▀░░░░█░░░░░░░█░░░░░░░░░░░░
                                               ░░░░░░░░░▀▀▀█░░░░█▀▀█░░░░█▀▀▀░░░░█░░░░░░░█░░░░░░░░░░░░
                                               ░░░░░░░░░▀▀▀▀░░░░▀░░▀░░░░▀▀▀▀░░░░▀▀▀▀░░░░▀▀▀▀░░░░░░░░░

                                                ─────────────────── Version ${BOB_VERSION} ───────────────────
    "
}

# Load persistent Bob Shell version for appliance version-aware paths.
if [[ -z "${BOB_VERSION:-}" ]]; then
  _BOB_VERSION_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "${_BOB_VERSION_SCRIPT_DIR}/bob-version.sh" ]]; then
    # shellcheck source=/dev/null
    source "${_BOB_VERSION_SCRIPT_DIR}/bob-version.sh"
  fi
  unset _BOB_VERSION_SCRIPT_DIR
fi
