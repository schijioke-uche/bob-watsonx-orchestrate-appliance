#!/usr/bin/env bash
# BOB2-42 production view: the following printf menu is from the ORIGINAL appliance.
# The Bob v2 command adapter is separate from presentation; no v1 CLI is invoked here.
APPLIANCE_NAME="${APPLIANCE_NAME:-IBM Bob watsonx Orchestrate Agent (WXA)}"
bob2_ui_init() {
  BOLD=""; RESET=""; BLUE=""; CYAN=""; GREEN=""; YELLOW=""; MAGENTA=""; RED=""
  if [[ -t 1 && -n "${TERM:-}" && "${TERM}" != "dumb" ]] && command -v tput >/dev/null 2>&1; then
    BOLD="$(tput bold 2>/dev/null || true)"; RESET="$(tput sgr0 2>/dev/null || true)"
    BLUE="$(tput setaf 4 2>/dev/null || true)"; CYAN="$(tput setaf 6 2>/dev/null || true)"
    GREEN="$(tput setaf 2 2>/dev/null || true)"; YELLOW="$(tput setaf 3 2>/dev/null || true)"
    MAGENTA="$(tput setaf 5 2>/dev/null || true)"; RED="$(tput setaf 1 2>/dev/null || true)"
  fi
  export BOLD RESET BLUE CYAN GREEN YELLOW MAGENTA RED
}

bob2_ui_menu() {
printf '%b\n' "${CYAN}+------------------------------------------------------------------------------+${RESET}"
printf '%b|%b %b%-76s%b %b|%b\n' "${CYAN}" "${RESET}" "${BOLD}${BLUE}" "IBM Bob watsonx Orchestrate Agent (WXA)" "${RESET}" "${CYAN}" "${RESET}"
printf '%b|%b %b%-76s%b %b|%b\n' "${CYAN}" "${RESET}" "${BOLD}${MAGENTA}" "This is IBM Bob, Designed with watsonx Orchestrate Intelligence" "${RESET}" "${CYAN}" "${RESET}"
printf '%b\n' "${CYAN}+------------------------------------------------------------------------------+${RESET}"
printf '%b|%b %-5s %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "No." "${CYAN}" "${RESET}" "Action" "${CYAN}" "${RESET}" "Skill ID" "${CYAN}" "${RESET}"
printf '%b\n' "${CYAN}+------------------------------------------------------------------------------+${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${GREEN}${BOLD}" "1" "${RESET}" "${CYAN}" "${RESET}" "Start Interactive WXA Session" "${CYAN}" "${RESET}" "User Interactive" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${GREEN}${BOLD}" "2" "${RESET}" "${CYAN}" "${RESET}" "Ask watsonx Orchestrate Question" "${CYAN}" "${RESET}" "WXO Assist" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${GREEN}${BOLD}" "3" "${RESET}" "${CYAN}" "${RESET}" "watsonx Orchestrate Agent Build Assist" "${CYAN}" "${RESET}" "WXO Code" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${GREEN}${BOLD}" "4" "${RESET}" "${CYAN}" "${RESET}" "Advanced WXO Agent Architecture Design" "${CYAN}" "${RESET}" "WXO Agent Architect" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${YELLOW}${BOLD}" "5" "${RESET}" "${CYAN}" "${RESET}" "Resume WXA Session (Picks: 1, 2, 3, or 4)" "${CYAN}" "${RESET}" "Resume latest" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${RED}${BOLD}" "0" "${RESET}" "${CYAN}" "${RESET}" "Quit" "${CYAN}" "${RESET}" "Exit" "${CYAN}" "${RESET}"
printf '%b\n' "${CYAN}+------------------------------------------------------------------------------+${RESET}"
}
bob2_ui_authenticating() { printf '%b\n' "${CYAN}Authenticating Bob Shell...${RESET}"; }
bob2_ui_time() { printf '%b\n' "${CYAN}Bob Time: $(TZ='America/New_York' date '+%Y-%m-%d %H:%M:%S %Z')${RESET}"; }
bob2_ui_select() { printf '%bSelect menu option (0-5):%b ' "${BOLD}${YELLOW}" "${RESET}"; }
bob2_ui_prompt() {
  case "${1:-}" in
    2) printf '%bEnter IBM watsonx Orchestrate question prompt:%b ' "${YELLOW}" "${RESET}" ;;
    3) printf '%bEnter watsonx Orchestrate agent/tool/workflow build prompt:%b ' "${YELLOW}" "${RESET}" ;;
    4) printf '%bEnter advanced WXO Agent Architect prompt:%b ' "${YELLOW}" "${RESET}" ;;
    *) return 2 ;;
  esac
}
bob2_ui_goodbye() { printf '%bIBM Bob watsonx Orchestrate Agent (WXA), Goodbye!%b\n' "${GREEN}" "${RESET}"; }
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  set -Eeuo pipefail
  bob2_ui_init
  case "${1:-menu}" in
    menu)
      if [[ -t 1 && "${TERM:-dumb}" != "dumb" ]] && command -v clear >/dev/null 2>&1; then clear || true; fi
      bob2_ui_menu ;;
    preview) bob2_ui_menu ;;
    authenticating) bob2_ui_authenticating ;;
    time) bob2_ui_time ;;
    select) bob2_ui_select ;;
    prompt) bob2_ui_prompt "${2:-}" ;;
    goodbye) bob2_ui_goodbye ;;
    *) printf '%s\n' 'ERROR: Unknown UI action.' >&2; exit 2 ;;
  esac
fi
