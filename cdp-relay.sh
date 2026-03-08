#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════╗
# ║   🦀 Tunnelclaw — CDP Relay start/stop/status       ║
# ╚══════════════════════════════════════════════════════╝
#
# Usage:
#   cdp-relay start    — Load launchd agents, start Chrome + tunnel
#   cdp-relay stop     — Unload agents, kill Chrome + tunnel
#   cdp-relay restart  — Stop then start
#   cdp-relay status   — Show running state + verify CDP

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

# ─── Auto-detect profile from installed plists ────────────────────────────────
LAUNCH_DIR="${HOME}/Library/LaunchAgents"

# Find chrome-debug plist (with or without profile suffix)
CHROME_PLIST=$(ls "${LAUNCH_DIR}"/com.openclaw.chrome-debug*.plist 2>/dev/null | head -1)
TUNNEL_PLIST=$(ls "${LAUNCH_DIR}"/com.openclaw.chrome-tunnel*.plist 2>/dev/null | head -1)

if [[ -z "$CHROME_PLIST" || -z "$TUNNEL_PLIST" ]]; then
  echo -e "${RED}[✘]${RESET} No CDP relay plists found in ${LAUNCH_DIR}"
  echo "  Run install.sh first to set up the relay."
  exit 1
fi

CHROME_LABEL=$(defaults read "$CHROME_PLIST" Label 2>/dev/null)
TUNNEL_LABEL=$(defaults read "$TUNNEL_PLIST" Label 2>/dev/null)

# Extract ports — check launcher script first, then plist, then defaults
CHROME_SCRIPT=$(grep 'chrome-managed' "$CHROME_PLIST" 2>/dev/null | sed 's/.*<string>//;s/<\/string>.*//' | xargs)
if [[ -n "$CHROME_SCRIPT" && -f "$CHROME_SCRIPT" ]]; then
  LOCAL_PORT=$(grep -o 'DEBUG_PORT="[0-9]*"' "$CHROME_SCRIPT" 2>/dev/null | grep -o '[0-9]*' | head -1)
fi
LOCAL_PORT="${LOCAL_PORT:-9222}"

# Parse tunnel plist: -R 127.0.0.1:REMOTE:127.0.0.1:LOCAL
TUNNEL_SPEC=$(grep -o '127\.0\.0\.1:[0-9]*:127\.0\.0\.1:[0-9]*' "$TUNNEL_PLIST" 2>/dev/null | head -1)
if [[ -n "$TUNNEL_SPEC" ]]; then
  REMOTE_PORT=$(echo "$TUNNEL_SPEC" | cut -d: -f2)
fi
REMOTE_PORT="${REMOTE_PORT:-9223}"
REMOTE_HOST=$(grep -oE '[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+' "$TUNNEL_PLIST" 2>/dev/null | head -1)

# ─── Helpers ──────────────────────────────────────────────────────────────────
chrome_running() { pgrep -f "remote-debugging-port=${LOCAL_PORT}" >/dev/null 2>&1; }
tunnel_running() { pgrep -f "autossh.*${REMOTE_PORT}" >/dev/null 2>&1; }

do_start() {
  echo -e "${CYAN}[tunnelclaw]${RESET} Starting CDP relay..."

  if chrome_running && tunnel_running; then
    echo -e "${YELLOW}[!]${RESET} Already running. Use 'restart' to bounce."
    return 0
  fi

  launchctl load "$CHROME_PLIST" 2>/dev/null || true
  launchctl load "$TUNNEL_PLIST" 2>/dev/null || true

  # Wait for Chrome to be ready
  echo -n "  Waiting for Chrome..."
  for i in $(seq 1 15); do
    if curl -s "http://127.0.0.1:${LOCAL_PORT}/json/version" >/dev/null 2>&1; then
      echo -e " ${GREEN}ready${RESET}"
      break
    fi
    sleep 1
    echo -n "."
  done

  if ! curl -s "http://127.0.0.1:${LOCAL_PORT}/json/version" >/dev/null 2>&1; then
    echo -e " ${RED}failed${RESET}"
    echo "  Check: tail /tmp/openclaw-chrome-debug-*.err.log"
    return 1
  fi

  echo -e "${GREEN}[✔]${RESET} Chrome on :${LOCAL_PORT}"
  echo -e "${GREEN}[✔]${RESET} Tunnel to ${REMOTE_HOST:-remote}:${REMOTE_PORT}"
  echo -e "${GREEN}[✔]${RESET} CDP relay active"
}

do_stop() {
  echo -e "${CYAN}[tunnelclaw]${RESET} Stopping CDP relay..."

  launchctl unload "$CHROME_PLIST" 2>/dev/null || true
  launchctl unload "$TUNNEL_PLIST" 2>/dev/null || true

  pkill -f "remote-debugging-port=${LOCAL_PORT}" 2>/dev/null || true
  pkill -f "autossh.*${REMOTE_PORT}" 2>/dev/null || true
  sleep 1

  if chrome_running || tunnel_running; then
    echo -e "${YELLOW}[!]${RESET} Force killing..."
    pkill -9 -f "remote-debugging-port=${LOCAL_PORT}" 2>/dev/null || true
    pkill -9 -f "autossh.*${REMOTE_PORT}" 2>/dev/null || true
    sleep 1
  fi

  echo -e "${GREEN}[✔]${RESET} Chrome stopped"
  echo -e "${GREEN}[✔]${RESET} Tunnel stopped"
  echo -e "${GREEN}[✔]${RESET} CDP relay down"
}

do_status() {
  echo -e "${BOLD}CDP Relay Status${RESET}"
  echo ""

  # Chrome
  if chrome_running; then
    local ver
    ver=$(curl -s "http://127.0.0.1:${LOCAL_PORT}/json/version" 2>/dev/null | grep -o '"Browser"[^,]*' | sed 's/.*: *"//;s/"//' || true)
    echo -e "  Chrome:  ${GREEN}● running${RESET}  :${LOCAL_PORT}  ${ver:-}"
  else
    echo -e "  Chrome:  ${RED}○ stopped${RESET}"
  fi

  # Tunnel
  if tunnel_running; then
    echo -e "  Tunnel:  ${GREEN}● running${RESET}  → ${REMOTE_HOST:-remote}:${REMOTE_PORT}"
  else
    echo -e "  Tunnel:  ${RED}○ stopped${RESET}"
  fi

  # Remote CDP check
  if chrome_running && tunnel_running; then
    echo ""
    echo -n "  Remote:  "
    if ssh "${REMOTE_HOST#*@}" "curl -s http://127.0.0.1:${REMOTE_PORT}/json/version" >/dev/null 2>&1; then
      echo -e "${GREEN}● reachable${RESET}"
    else
      echo -e "${RED}○ unreachable${RESET} (tunnel may still be connecting)"
    fi
  fi
  echo ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
case "${1:-}" in
  start)   do_start ;;
  stop)    do_stop ;;
  restart) do_stop; sleep 1; do_start ;;
  status)  do_status ;;
  *)
    echo "Usage: cdp-relay {start|stop|restart|status}"
    exit 1
    ;;
esac
