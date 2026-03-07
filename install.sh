#!/usr/bin/env bash
# ╔══════════════════════════════════════════════════════╗
# ║   🦀 Tunnelclaw — chrome-cdp-relay installer        ║
# ║   Gives remote agents a claw into your Mac Chrome   ║
# ╚══════════════════════════════════════════════════════╝
#
# Usage:
#   bash install.sh --host myserver.com --user root [OPTIONS]
#   bash install.sh --uninstall --profile myprofile
#
# Options:
#   --host            Remote server hostname or IP  (required unless --uninstall)
#   --user            SSH username on remote server (required unless --uninstall)
#   --key             Path to SSH private key       (default: ~/.ssh/id_ed25519)
#   --local-port      Local CDP port                (default: 9222)
#   --remote-port     Remote CDP port               (default: 9223)
#   --profile         Profile name slug             (default: default)
#   --uninstall       Remove all installed components for --profile

set -euo pipefail

# ─── colours ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[tunnelclaw]${RESET} $*"; }
success() { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()    { echo -e "${YELLOW}[!]${RESET} $*"; }
die()     { echo -e "${RED}[✘]${RESET} $*" >&2; exit 1; }

# ─── defaults ─────────────────────────────────────────────────────────────────
REMOTE_HOST=""
REMOTE_USER=""
SSH_KEY="${HOME}/.ssh/id_ed25519"
LOCAL_CDP_PORT="9222"
REMOTE_CDP_PORT="9223"
PROFILE_NAME="default"
UNINSTALL=false

# ─── parse args ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)         REMOTE_HOST="$2";    shift 2 ;;
    --user)         REMOTE_USER="$2";   shift 2 ;;
    --key)          SSH_KEY="$2";       shift 2 ;;
    --local-port)   LOCAL_CDP_PORT="$2"; shift 2 ;;
    --remote-port)  REMOTE_CDP_PORT="$2"; shift 2 ;;
    --profile)      PROFILE_NAME="$2";  shift 2 ;;
    --uninstall)    UNINSTALL=true;     shift   ;;
    *) die "Unknown option: $1. Run with --help equivalent for usage." ;;
  esac
done

# ─── derived paths ────────────────────────────────────────────────────────────
SCRIPTS_DIR="${HOME}/Library/Scripts/openclaw"
PROFILE_DIR="${HOME}/.openclaw/${PROFILE_NAME}-chrome-profile"
LAUNCH_AGENTS_DIR="${HOME}/Library/LaunchAgents"
CHROME_PLIST_LABEL="com.openclaw.chrome-debug-${PROFILE_NAME}"
TUNNEL_PLIST_LABEL="com.openclaw.chrome-tunnel-${PROFILE_NAME}"
CHROME_PLIST="${LAUNCH_AGENTS_DIR}/${CHROME_PLIST_LABEL}.plist"
TUNNEL_PLIST="${LAUNCH_AGENTS_DIR}/${TUNNEL_PLIST_LABEL}.plist"
CHROME_SCRIPT="${SCRIPTS_DIR}/chrome-managed-${PROFILE_NAME}.sh"

# ─── uninstall ────────────────────────────────────────────────────────────────
if $UNINSTALL; then
  info "Uninstalling Tunnelclaw profile: ${PROFILE_NAME}"

  for label in "$CHROME_PLIST_LABEL" "$TUNNEL_PLIST_LABEL"; do
    if launchctl list "$label" &>/dev/null; then
      launchctl unload "${LAUNCH_AGENTS_DIR}/${label}.plist" 2>/dev/null || true
      success "Unloaded $label"
    fi
  done

  for f in "$CHROME_PLIST" "$TUNNEL_PLIST" "$CHROME_SCRIPT"; do
    [[ -f "$f" ]] && rm -f "$f" && success "Removed $f"
  done

  if [[ -d "$PROFILE_DIR" ]]; then
    warn "Chrome profile data left intact at: $PROFILE_DIR"
    warn "Remove manually if you want: rm -rf \"${PROFILE_DIR}\""
  fi

  success "Tunnelclaw uninstalled for profile '${PROFILE_NAME}'."
  exit 0
fi

# ─── validate required args ───────────────────────────────────────────────────
[[ -z "$REMOTE_HOST" ]] && die "--host is required"
[[ -z "$REMOTE_USER" ]] && die "--user is required"

# ─── prerequisites ────────────────────────────────────────────────────────────
info "Checking prerequisites..."

CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
[[ -f "$CHROME_BIN" ]] || die "Google Chrome not found at: ${CHROME_BIN}"
success "Google Chrome found"

if ! command -v autossh &>/dev/null; then
  die "autossh not found. Install with: brew install autossh"
fi
success "autossh found at $(command -v autossh)"

[[ -f "$SSH_KEY" ]] || die "SSH key not found at: ${SSH_KEY}. Use --key to specify path."
success "SSH key found: ${SSH_KEY}"

# ─── create directories ───────────────────────────────────────────────────────
info "Creating directories..."
mkdir -p "$SCRIPTS_DIR" "$PROFILE_DIR" "$LAUNCH_AGENTS_DIR"
success "Created ${PROFILE_DIR}"
success "Created ${SCRIPTS_DIR}"

# ─── generate chrome-managed.sh ───────────────────────────────────────────────
info "Generating Chrome launcher script: ${CHROME_SCRIPT}"
cat > "$CHROME_SCRIPT" <<CHROME_SCRIPT_EOF
#!/usr/bin/env bash
set -euo pipefail

# Tunnelclaw — Managed Chrome debug launcher (profile: ${PROFILE_NAME})
CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
PROFILE_DIR="${PROFILE_DIR}"
DEBUG_PORT="${LOCAL_CDP_PORT}"

mkdir -p "\$PROFILE_DIR"

# If debug endpoint is already alive, do nothing.
if curl -fsS "http://127.0.0.1:\${DEBUG_PORT}/json/version" >/dev/null 2>&1; then
  exit 0
fi

# Kill stale Chrome processes using this profile/port.
pkill -f "Google Chrome.*--remote-debugging-port=\${DEBUG_PORT}.*\${PROFILE_DIR}" || true
sleep 1

exec "\$CHROME_BIN" \\
  --remote-debugging-address=127.0.0.1 \\
  --remote-debugging-port="\$DEBUG_PORT" \\
  --user-data-dir="\$PROFILE_DIR" \\
  --no-first-run \\
  --no-default-browser-check \\
  --disable-background-networking
CHROME_SCRIPT_EOF
chmod +x "$CHROME_SCRIPT"
success "Chrome launcher script written"

# ─── generate Chrome launchd plist ────────────────────────────────────────────
info "Writing Chrome launchd plist: ${CHROME_PLIST}"
cat > "$CHROME_PLIST" <<CHROME_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${CHROME_PLIST_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${CHROME_SCRIPT}</string>
  </array>

  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>

  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>${HOME}</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>

  <key>StandardOutPath</key><string>/tmp/openclaw-chrome-debug-${PROFILE_NAME}.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/openclaw-chrome-debug-${PROFILE_NAME}.err.log</string>
</dict>
</plist>
CHROME_PLIST_EOF
success "Chrome plist written"

# ─── generate autossh tunnel launchd plist ────────────────────────────────────
AUTOSSH_BIN="$(command -v autossh)"
info "Writing tunnel launchd plist: ${TUNNEL_PLIST}"
cat > "$TUNNEL_PLIST" <<TUNNEL_PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${TUNNEL_PLIST_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${AUTOSSH_BIN}</string>
    <string>-M</string><string>0</string>
    <string>-N</string>
    <string>-i</string><string>${SSH_KEY}</string>
    <string>-o</string><string>ExitOnForwardFailure=yes</string>
    <string>-o</string><string>ServerAliveInterval=30</string>
    <string>-o</string><string>ServerAliveCountMax=3</string>
    <string>-o</string><string>StrictHostKeyChecking=accept-new</string>
    <string>-R</string><string>127.0.0.1:${REMOTE_CDP_PORT}:127.0.0.1:${LOCAL_CDP_PORT}</string>
    <string>${REMOTE_USER}@${REMOTE_HOST}</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>${HOME}</string>
    <key>AUTOSSH_GATETIME</key><string>0</string>
    <key>AUTOSSH_POLL</key><string>30</string>
    <key>AUTOSSH_FIRST_POLL</key><string>10</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>

  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>

  <key>StandardOutPath</key><string>/tmp/openclaw-autossh-${PROFILE_NAME}.out.log</string>
  <key>StandardErrorPath</key><string>/tmp/openclaw-autossh-${PROFILE_NAME}.err.log</string>
</dict>
</plist>
TUNNEL_PLIST_EOF
success "Tunnel plist written"

# ─── load launchd agents ──────────────────────────────────────────────────────
info "Loading launchd agents..."

# Unload first if already loaded (idempotent reinstall)
launchctl unload "$CHROME_PLIST" 2>/dev/null || true
launchctl unload "$TUNNEL_PLIST" 2>/dev/null || true

launchctl load "$CHROME_PLIST"
success "Loaded ${CHROME_PLIST_LABEL}"

launchctl load "$TUNNEL_PLIST"
success "Loaded ${TUNNEL_PLIST_LABEL}"

# ─── verify: local CDP ────────────────────────────────────────────────────────
info "Waiting for Chrome to start (up to 15s)..."
LOCAL_OK=false
for i in $(seq 1 15); do
  if curl -fsS "http://127.0.0.1:${LOCAL_CDP_PORT}/json/version" >/dev/null 2>&1; then
    LOCAL_OK=true
    break
  fi
  sleep 1
done

if $LOCAL_OK; then
  CHROME_VER=$(curl -fsS "http://127.0.0.1:${LOCAL_CDP_PORT}/json/version" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Browser','?'))" 2>/dev/null || echo "unknown")
  success "Local CDP responding: ${CHROME_VER}"
else
  die "Local Chrome CDP not responding on port ${LOCAL_CDP_PORT} after 15s. Check: tail /tmp/openclaw-chrome-debug-${PROFILE_NAME}.err.log"
fi

# ─── verify: remote CDP ───────────────────────────────────────────────────────
info "Waiting for SSH tunnel to establish (up to 20s)..."
REMOTE_OK=false
for i in $(seq 1 10); do
  if ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
       "${REMOTE_USER}@${REMOTE_HOST}" \
       "curl -fsS http://127.0.0.1:${REMOTE_CDP_PORT}/json/version >/dev/null 2>&1" 2>/dev/null; then
    REMOTE_OK=true
    break
  fi
  sleep 2
done

if $REMOTE_OK; then
  REMOTE_VER=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 \
    "${REMOTE_USER}@${REMOTE_HOST}" \
    "curl -fsS http://127.0.0.1:${REMOTE_CDP_PORT}/json/version" 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('Browser','?'))" 2>/dev/null || echo "unknown")
  success "Remote CDP responding via tunnel: ${REMOTE_VER}"
else
  warn "Remote CDP not yet reachable on ${REMOTE_HOST}:${REMOTE_CDP_PORT}"
  warn "Tunnel may still be connecting. Try manually:"
  warn "  ssh ${REMOTE_USER}@${REMOTE_HOST} 'curl http://127.0.0.1:${REMOTE_CDP_PORT}/json/version'"
  warn "Also ensure GatewayPorts is not blocking on the remote sshd."
fi

# ─── remote sshd hints ────────────────────────────────────────────────────────
info "Tip: if remote curl fails, ensure /etc/ssh/sshd_config on ${REMOTE_HOST} has:"
echo "       GatewayPorts yes   (or: GatewayPorts clientspecified)"

# ─── remote sshd keepalive check ─────────────────────────────────────────────
info "Checking remote sshd keepalive settings on ${REMOTE_HOST}..."
KEEPALIVE_OK=true
REMOTE_SSHD_CFG=$(ssh -i "$SSH_KEY" -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
  "${REMOTE_USER}@${REMOTE_HOST}" "cat /etc/ssh/sshd_config" 2>/dev/null) || REMOTE_SSHD_CFG=""

if [[ -n "$REMOTE_SSHD_CFG" ]]; then
  # Check ClientAliveInterval (uncommented, non-zero)
  CAI=$(echo "$REMOTE_SSHD_CFG" | grep -E '^\s*ClientAliveInterval\s+[1-9]' || true)
  CAC=$(echo "$REMOTE_SSHD_CFG" | grep -E '^\s*ClientAliveCountMax\s+[1-9]' || true)

  if [[ -z "$CAI" ]] || [[ -z "$CAC" ]]; then
    KEEPALIVE_OK=false
    warn "Remote sshd missing keepalive settings — dead SSH sessions will hold"
    warn "the forwarded port for 15+ minutes, causing 'remote port forwarding failed'."
    echo ""
    echo -e "  ${BOLD}Add to /etc/ssh/sshd_config on ${REMOTE_HOST}:${RESET}"
    echo "    ClientAliveInterval 15"
    echo "    ClientAliveCountMax 3"
    echo ""
    read -rp "  Configure these automatically? [y/N] " CONFIGURE_KEEPALIVE
    if [[ "${CONFIGURE_KEEPALIVE,,}" == "y" ]]; then
      ssh -i "$SSH_KEY" -o ConnectTimeout=5 "${REMOTE_USER}@${REMOTE_HOST}" bash -s <<'REMOTE_KEEPALIVE_EOF'
        # Remove any existing (possibly commented) lines
        sudo sed -i '/^\s*#\?\s*ClientAliveInterval/d' /etc/ssh/sshd_config
        sudo sed -i '/^\s*#\?\s*ClientAliveCountMax/d' /etc/ssh/sshd_config
        # Append correct values
        echo "ClientAliveInterval 15" | sudo tee -a /etc/ssh/sshd_config >/dev/null
        echo "ClientAliveCountMax 3" | sudo tee -a /etc/ssh/sshd_config >/dev/null
        sudo systemctl reload ssh 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
REMOTE_KEEPALIVE_EOF
      success "Remote sshd keepalive configured and reloaded"
    else
      warn "Skipped. You may see 'remote port forwarding failed' errors on reconnection."
    fi
  else
    success "Remote sshd keepalive: ClientAliveInterval and ClientAliveCountMax set"
  fi
else
  warn "Could not read remote sshd_config — check keepalive settings manually"
fi

# ─── sleep guard hint ─────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Optional:${RESET} If you have the mac-sleep-guard skill available, keep your Mac awake"
echo "  while the tunnel is active by configuring it with condition:"
echo "    url: http://127.0.0.1:${LOCAL_CDP_PORT}/json/version"

# ─── summary ─────────────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║  🦀 Tunnelclaw installed — profile: ${PROFILE_NAME}${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  Local CDP  : ${GREEN}http://127.0.0.1:${LOCAL_CDP_PORT}/json/version${RESET}"
echo -e "  Remote CDP : ${GREEN}http://127.0.0.1:${REMOTE_CDP_PORT}/json/version${RESET}  (on ${REMOTE_HOST})"
echo -e "  Profile dir: ${CYAN}${PROFILE_DIR}${RESET}"
echo -e "  Logs       : ${CYAN}/tmp/openclaw-*.log${RESET}"
echo ""
echo -e "  To uninstall:"
echo -e "    bash install.sh --uninstall --profile ${PROFILE_NAME}"
echo ""
