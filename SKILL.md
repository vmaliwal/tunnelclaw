---
name: chrome-cdp-relay
description: Sets up a Chrome remote debugging relay over SSH reverse tunnel to any remote server. Gives agents on remote servers CDP access to the user's real Mac Chrome — with real IP, fingerprint, cookies and sessions. Use when an agent on a VPS or remote machine needs to control a real browser on the user's Mac.
---

# Tunnelclaw 🦀 — Chrome CDP Relay Skill

> **What this does**: Keeps a real Google Chrome running on the user's Mac in a dedicated debug profile, then reverse-tunnels its Chrome DevTools Protocol (CDP) port to a remote server over SSH. Any agent on the remote server can connect to `http://127.0.0.1:{REMOTE_CDP_PORT}` and drive a real Mac browser — real IP, real fingerprint, persistent cookies, real sessions.

---

## Parameters

Collect these from the user before proceeding:

| Parameter | Description | Default |
|-----------|-------------|---------|
| `REMOTE_HOST` | Hostname or IP of the remote server | *(required)* |
| `REMOTE_USER` | SSH username on the remote server | *(required)* |
| `SSH_KEY_PATH` | Path to SSH private key on the Mac | `~/.ssh/id_ed25519` |
| `LOCAL_CDP_PORT` | Chrome debug port on localhost (Mac) | `9222` |
| `REMOTE_CDP_PORT` | Port exposed on the remote server | `9223` |
| `PROFILE_NAME` | Slug name for this Chrome profile | `default` |

---

## Prerequisites Check

Before running any setup steps, verify:

1. **Google Chrome** is installed at `/Applications/Google Chrome.app/`
   ```bash
   ls "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
   ```

2. **autossh** is installed (keeps the tunnel alive across disconnects):
   ```bash
   which autossh || brew install autossh
   ```

3. **SSH key** exists and has correct permissions:
   ```bash
   ls -la {SSH_KEY_PATH}   # should be -rw------- (600)
   ```

4. **Remote sshd** allows reverse port forwarding — on the remote server:
   ```bash
   grep -E 'GatewayPorts' /etc/ssh/sshd_config
   # Should be: GatewayPorts yes  (or: GatewayPorts clientspecified)
   # If missing or 'no', add it and: systemctl restart sshd
   ```

---

## Step-by-Step Setup

### Step 1 — Collect parameters from user

Ask the user for `REMOTE_HOST`, `REMOTE_USER`, and optionally the other parameters. Fill in defaults for anything not provided.

### Step 2 — Create Chrome profile directory

```bash
mkdir -p ~/.openclaw/{PROFILE_NAME}-chrome-profile
```

This directory is the Chrome `--user-data-dir`. It persists cookies, sessions, and logins across Chrome restarts. Keep it intact — deleting it resets all logged-in state.

### Step 3 — Generate the Chrome launcher script

Create `~/Library/Scripts/openclaw/chrome-managed-{PROFILE_NAME}.sh` from the template at `templates/chrome-managed.sh.tmpl`, substituting:
- `{{PROFILE_DIR}}` → `~/.openclaw/{PROFILE_NAME}-chrome-profile`
- `{{DEBUG_PORT}}` → `{LOCAL_CDP_PORT}`

Make it executable: `chmod +x ...`

**What it does**: Checks if Chrome is already listening on the debug port. If not, kills any stale Chrome processes using that port/profile, then starts Chrome with `--remote-debugging-port`. Designed to be called by launchd — safe to run repeatedly.

### Step 4 — Install launchd plists

Two launchd agents are needed:

#### 4a. Chrome launcher plist
Create `~/Library/LaunchAgents/com.openclaw.chrome-debug-{PROFILE_NAME}.plist` from `templates/launchd-chrome.plist.tmpl`, substituting:
- `{{PROFILE_NAME}}` → profile slug
- `{{SCRIPTS_DIR}}` → `~/Library/Scripts/openclaw`
- `{{HOME}}` → user's `$HOME`

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.openclaw.chrome-debug-{PROFILE_NAME}.plist
```

#### 4b. SSH tunnel plist
Create `~/Library/LaunchAgents/com.openclaw.chrome-tunnel-{PROFILE_NAME}.plist` from `templates/launchd-tunnel.plist.tmpl`, substituting:
- `{{SSH_KEY}}` → absolute path to SSH key
- `{{REMOTE_USER}}` → SSH username
- `{{REMOTE_HOST}}` → server hostname/IP
- `{{REMOTE_CDP_PORT}}` → port on remote
- `{{LOCAL_CDP_PORT}}` → port on Mac
- `{{PROFILE_NAME}}` → profile slug
- `{{HOME}}` → user's `$HOME`

Load it:
```bash
launchctl load ~/Library/LaunchAgents/com.openclaw.chrome-tunnel-{PROFILE_NAME}.plist
```

**What it does**: Runs `autossh` to establish a persistent SSH reverse tunnel. The tunnel forwards `remote:REMOTE_CDP_PORT → localhost:LOCAL_CDP_PORT`. `KeepAlive=true` in the plist means launchd restarts it if it dies.

### Step 5 — Verify end-to-end CDP reachability

#### Verify local Chrome (on Mac):
```bash
curl http://127.0.0.1:{LOCAL_CDP_PORT}/json/version
```
Should return JSON with Chrome version info, e.g.:
```json
{"Browser": "Chrome/124.0.6367.82", "Protocol-Version": "1.3", ...}
```

#### Verify remote CDP (from remote server):
```bash
ssh {REMOTE_USER}@{REMOTE_HOST} 'curl http://127.0.0.1:{REMOTE_CDP_PORT}/json/version'
```
Same JSON should appear. If it does, agents on that server can now connect to CDP at `http://127.0.0.1:{REMOTE_CDP_PORT}`.

---

## Using CDP from the Remote Agent

On the remote server, connect to Chrome via CDP at:
```
http://127.0.0.1:{REMOTE_CDP_PORT}
```

Example with Playwright (Node.js):
```js
const { chromium } = require('playwright');
const browser = await chromium.connectOverCDP('http://127.0.0.1:9223');
const [page] = browser.contexts()[0].pages();
await page.goto('https://example.com');
```

Example with Puppeteer:
```js
const puppeteer = require('puppeteer-core');
const browser = await puppeteer.connect({
  browserURL: 'http://127.0.0.1:9223'
});
```

Example with raw CDP (Python):
```python
import requests
targets = requests.get('http://127.0.0.1:9223/json').json()
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| Local curl returns nothing | Chrome not started | Check log: `tail /tmp/openclaw-chrome-debug-{PROFILE_NAME}.err.log` |
| Remote curl hangs/refused | Tunnel not up yet | Check: `tail /tmp/openclaw-autossh-{PROFILE_NAME}.err.log` |
| Remote curl: connection refused | `GatewayPorts` not set | Add `GatewayPorts yes` to remote `/etc/ssh/sshd_config`, restart sshd |
| Chrome crashes on start | Port already in use | `lsof -i :{LOCAL_CDP_PORT}` — kill the other process |
| SSH key rejected | Wrong key or permissions | `chmod 600 {SSH_KEY_PATH}` |
| autossh keeps restarting | SSH server not accepting keepalives | Verify `ServerAliveInterval` and remote sshd `TCPKeepAlive yes` |

---

## Mac Sleep Guard (Optional)

If the user's Mac goes to sleep, Chrome closes and the tunnel drops. If the `mac-sleep-guard` skill is available in this environment, offer to set it up:

```
Condition URL: http://127.0.0.1:{LOCAL_CDP_PORT}/json/version
Reason: "Tunnelclaw CDP relay active"
```

The sleep guard will prevent macOS sleep whenever Chrome is running and the CDP port is live.

---

## Teardown / Uninstall

To remove everything for a profile:

```bash
# Unload launchd agents
launchctl unload ~/Library/LaunchAgents/com.openclaw.chrome-debug-{PROFILE_NAME}.plist
launchctl unload ~/Library/LaunchAgents/com.openclaw.chrome-tunnel-{PROFILE_NAME}.plist

# Remove plist files
rm ~/Library/LaunchAgents/com.openclaw.chrome-debug-{PROFILE_NAME}.plist
rm ~/Library/LaunchAgents/com.openclaw.chrome-tunnel-{PROFILE_NAME}.plist

# Remove Chrome launcher script
rm ~/Library/Scripts/openclaw/chrome-managed-{PROFILE_NAME}.sh

# Optionally remove Chrome profile data (removes all cookies/sessions!)
rm -rf ~/.openclaw/{PROFILE_NAME}-chrome-profile
```

Or use the installer script:
```bash
bash install.sh --uninstall --profile {PROFILE_NAME}
```

---

## Quick Install (One Command)

Instead of manual steps, use the included installer:

```bash
bash skills/chrome-cdp-relay/install.sh \
  --host myserver.com \
  --user root \
  --key ~/.ssh/id_ed25519 \
  --local-port 9222 \
  --remote-port 9223 \
  --profile myprofile
```

The installer handles all steps above and verifies both local and remote CDP.

---

## How It Works

```
┌─────────────────────────────────────────────────────────────┐
│                        Mac (local)                          │
│                                                             │
│  launchd → chrome-managed.sh → Chrome :9222 (CDP)          │
│                                    │                        │
│  launchd → autossh ────────────────┘──────SSH tunnel──┐    │
└─────────────────────────────────────────────────────── │ ───┘
                                                         │
                                                   (reverse tunnel)
                                                         │
┌─────────────────────────────────────────────────────── │ ───┐
│                    Remote Server                        │    │
│                                                         ▼    │
│   Agent → Playwright/Puppeteer → CDP :9223 ──────────────   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

Both launchd agents have `KeepAlive=true` — Chrome and the tunnel restart automatically on crash or Mac reboot.
