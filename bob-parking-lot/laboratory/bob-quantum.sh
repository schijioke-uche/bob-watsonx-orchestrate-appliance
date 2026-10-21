#!/usr/bin/env bash
set -Eeuo pipefail

#===============================================================================
# @Author: Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
# @Description: Launchpad for interacting with IBM Bob Quantum Computing Agent (QCA)
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/tls-control.sh"
source "$SCRIPT_DIR/../load-env.sh"   # BOB_API_KEY etc. from the project .env

#====================================================================================
# This script provides a launchpad menu for interacting with IBM Bob.
#====================================================================================

BOB_BIN="${BOB_BIN:-bob}"
INITIAL_PROMPT="${*:-What quantum computing code should I write?}"
BOB_INSTANCE_ID="Quantum Computing Agent (QCA)"
BOB_INCLUDED_DIRECTORY="$HOME/IBM-SOFTWARE/ibm-bob-operations/use-cases/bob-codes"
mkdir -p "$BOB_INCLUDED_DIRECTORY"
chmod -R 777 "$BOB_INCLUDED_DIRECTORY"
chown -R "$USER":"$USER" "$BOB_INCLUDED_DIRECTORY"
export BOB_INSTANCE_ID 
export BOB_BIN
export BOB_INCLUDED_DIRECTORY

# Color-only presentation layer. Application flow and Bob command behavior are unchanged.
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
  BOLD="$(tput bold)"
  RESET="$(tput sgr0)"
  BLUE="$(tput setaf 4)"
  CYAN="$(tput setaf 6)"
  GREEN="$(tput setaf 2)"
  YELLOW="$(tput setaf 3)"
  MAGENTA="$(tput setaf 5)"
  RED="$(tput setaf 1)"
else
  BOLD=""
  RESET=""
  BLUE=""
  CYAN=""
  GREEN=""
  YELLOW=""
  MAGENTA=""
  RED=""
fi

clear

printf '%b\n' "${CYAN}+------------------------------------------------------------------------------+${RESET}"
printf '%b|%b %b%-76s%b %b|%b\n' "${CYAN}" "${RESET}" "${BOLD}${BLUE}" "IBM Bob Quantum Computing Agent (QCA)" "${RESET}" "${CYAN}" "${RESET}"
printf '%b|%b %b%-76s%b %b|%b\n' "${CYAN}" "${RESET}" "${BOLD}${MAGENTA}" "This is IBM Bob Designed with Quantum Computing Intelligence" "${RESET}" "${CYAN}" "${RESET}"
printf '%b\n' "${CYAN}+------------------------------------------------------------------------------+${RESET}"
printf '%b|%b %-5s %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "No." "${CYAN}" "${RESET}" "Action" "${CYAN}" "${RESET}" "Mode" "${CYAN}" "${RESET}"
printf '%b\n' "${CYAN}+------------------------------------------------------------------------------+${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${GREEN}${BOLD}" "1" "${RESET}" "${CYAN}" "${RESET}" "Start interactive session for quantum coding" "${CYAN}" "${RESET}" "Interactive" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${GREEN}${BOLD}" "2" "${RESET}" "${CYAN}" "${RESET}" "Ask quantum computing question" "${CYAN}" "${RESET}" "Ask" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${GREEN}${BOLD}" "3" "${RESET}" "${CYAN}" "${RESET}" "Quantum computing code assist" "${CYAN}" "${RESET}" "Code" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${GREEN}${BOLD}" "4" "${RESET}" "${CYAN}" "${RESET}" "Advanced quantum computing circuit design" "${CYAN}" "${RESET}" "Advanced" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${YELLOW}${BOLD}" "5" "${RESET}" "${CYAN}" "${RESET}" "Resume latest QCA session" "${CYAN}" "${RESET}" "Resume latest" "${CYAN}" "${RESET}"
printf '%b|%b %b%-5s%b %b|%b %-45s %b|%b %-20s %b|%b\n' "${CYAN}" "${RESET}" "${RED}${BOLD}" "0" "${RESET}" "${CYAN}" "${RESET}" "Quit" "${CYAN}" "${RESET}" "Exit" "${CYAN}" "${RESET}"
printf '%b\n' "${CYAN}+------------------------------------------------------------------------------+${RESET}"

printf '%b✨ Select option:%b ' "${BOLD}${YELLOW}" "${RESET}"
read -r choice

case "$choice" in
  1)
  "$BOB_BIN" \
    --chat-mode code \
    --accept-license true \
    --instance-id "$BOB_INSTANCE_ID" \
    --include-directories "$BOB_INCLUDED_DIRECTORY" \
    --hide-intermediary-output \
    --prompt-interactive "$INITIAL_PROMPT"
    ;;
  2)
    printf '%bEnter quantum computing question prompt:%b ' "${YELLOW}" "${RESET}"
    read -r prompt
    "$BOB_BIN" "${prompt}" \
      --chat-mode ask \
      --accept-license true \
      --instance-id "$BOB_INSTANCE_ID" \
      --include-directories "$BOB_INCLUDED_DIRECTORY" \
      --hide-intermediary-output
    ;;
  3)
    printf '%bEnter quantum computing code assist prompt:%b ' "${YELLOW}" "${RESET}"
    read -r prompt
    "$BOB_BIN" "${prompt}" \
      --chat-mode code \
      --accept-license true \
      --trust \
      --instance-id "$BOB_INSTANCE_ID" \
      --include-directories "$BOB_INCLUDED_DIRECTORY" \
      --hide-intermediary-output
    ;;
  4)
    printf '%bEnter advanced quantum computing circuit design prompt:%b ' "${YELLOW}" "${RESET}"
    read -r prompt
    "$BOB_BIN" "${prompt}" \
      --chat-mode advanced \
      --accept-license true \
      --trust \
      --instance-id "$BOB_INSTANCE_ID" \
      --include-directories "$BOB_INCLUDED_DIRECTORY" \
      --hide-intermediary-output
    ;;
  5)
    "$BOB_BIN" --resume latest \
      --instance-id "$BOB_INSTANCE_ID" \
      --include-directories "$BOB_INCLUDED_DIRECTORY" \
      --hide-intermediary-output
    ;;
  0)
    printf '%b🤖 IBM Bob Quantum Computing Agent, Goodbye!%b\n' "${GREEN}" "${RESET}"
    exit 0
    ;;
  *)
    printf '%bInvalid option.%b\n' "${RED}" "${RESET}"
    exit 1
    ;;
esac
