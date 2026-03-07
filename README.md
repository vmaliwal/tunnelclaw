
```
 ████████╗██╗   ██╗███╗   ██╗███╗   ██╗███████╗██╗      ██████╗██╗      █████╗ ██╗    ██╗
    ██╔══╝██║   ██║████╗  ██║████╗  ██║██╔════╝██║     ██╔════╝██║     ██╔══██╗██║    ██║
    ██║   ██║   ██║██╔██╗ ██║██╔██╗ ██║█████╗  ██║     ██║     ██║     ███████║██║ █╗ ██║
    ██║   ██║   ██║██║╚██╗██║██║╚██╗██║██╔══╝  ██║     ██║     ██║     ██╔══██║██║███╗██║
    ██║   ╚██████╔╝██║ ╚████║██║ ╚████║███████╗███████╗╚██████╗███████╗██║  ██║╚███╔███╔╝
    ╚═╝    ╚═════╝ ╚═╝  ╚═══╝╚═╝  ╚═══╝╚══════╝╚══════╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝
```

<div align="center">

```
          ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
        ╔══════════════════════════════════════╗
        ║  ▓▓▓  MAC CHROME  ▓▓▓  ≋≋≋ SSH ≋≋≋  ║══╗
        ║                                      ║  ║
        ║       ·  ·  ·  ≋≋≋≋≋≋≋≋≋≋  ·  ·    ║  ║  🦀
        ╚══════════════════════════════════════╝  ╚══>
          ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
                               ↑ a tunnel with a claw
```

**Give remote agents a real browser. Real IP. Real fingerprint. Real sessions.**

---

[![Works with Pi](https://img.shields.io/badge/Works%20with-Pi-blueviolet?style=flat-square)](https://github.com/mariozechner/pi)
[![Works with Claude Code](https://img.shields.io/badge/Works%20with-Claude%20Code-orange?style=flat-square)](https://claude.ai/code)
[![Works with Codex](https://img.shields.io/badge/Works%20with-OpenAI%20Codex-412991?style=flat-square)](https://openai.com/codex)
[![Works with Cursor](https://img.shields.io/badge/Works%20with-Cursor-1a1a2e?style=flat-square)](https://cursor.sh)
[![macOS](https://img.shields.io/badge/macOS-12%2B-lightgrey?style=flat-square&logo=apple)](https://apple.com)
[![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

</div>

---

## 🧠 What is Tunnelclaw?

Tunnelclaw is a Pi skill (and standalone bash installer) that **tunnels Chrome DevTools Protocol (CDP) from your Mac to any remote server** — so an AI agent running on a VPS can drive _your real Mac Chrome_ as if it were local.

Your remote agent gets:
- 🌍 **Your real IP address** — no data-center fingerprint
- 🍪 **Your existing browser sessions** — already logged in to everything
- 🖥️ **Your real browser fingerprint** — canvas, WebGL, fonts, timezone
- 🔄 **Persistent profiles** — sessions survive Chrome and tunnel restarts

Two `launchd` agents keep everything alive: one manages Chrome, one keeps the SSH tunnel up. Both auto-restart on crash or Mac reboot.

---

## ⚡ Quick Start

```bash
bash skills/chrome-cdp-relay/install.sh \
  --host myserver.com \
  --user root \
  --key ~/.ssh/id_ed25519 \
  --local-port 9222 \
  --remote-port 9223 \
  --profile myprofile
```

That's it. The script checks prerequisites, creates the Chrome profile, generates all scripts, installs launchd agents, and verifies CDP is reachable from your remote server.

---

## 🏗️ How It Works

```
╔══════════════════════════════════════════════════════════════╗
║                         Your Mac                            ║
║                                                             ║
║  ┌────────────────┐    CDP :9222    ┌──────────────────┐   ║
║  │  launchd       │ ──────────────► │  Google Chrome   │   ║
║  │  chrome-debug  │                 │  debug profile   │   ║
║  └────────────────┘                 └──────────────────┘   ║
║           │                                  ▲             ║
║  ┌────────┴───────┐     SSH reverse tunnel   │             ║
║  │  launchd       │ ─────────────────────────┘             ║
║  │  chrome-tunnel │   autossh -R 9223:127.0.0.1:9222       ║
║  └────────────────┘                                        ║
╚══════════════════════════════════════════════════════════════╝
                         │ encrypted SSH
                         ▼
╔══════════════════════════════════════════════════════════════╗
║                    Remote Server / VPS                      ║
║                                                             ║
║  Agent code ──► Playwright / Puppeteer / raw CDP            ║
║                         │                                   ║
║                         ▼                                   ║
║             http://127.0.0.1:9223  ◄────────────────────   ║
║             (forwarded from Mac :9222)                      ║
╚══════════════════════════════════════════════════════════════╝
```

**Both launchd agents have `KeepAlive=true`** — Chrome and the tunnel restart automatically. Your remote agent's CDP connection is self-healing.

---

## 📋 Parameters

| Parameter | Flag | Default | Description |
|-----------|------|---------|-------------|
| Remote host | `--host` | *(required)* | Hostname or IP of remote server |
| Remote user | `--user` | *(required)* | SSH username |
| SSH key | `--key` | `~/.ssh/id_ed25519` | Path to SSH private key |
| Local CDP port | `--local-port` | `9222` | Chrome debug port on Mac |
| Remote CDP port | `--remote-port` | `9223` | Port exposed on remote server |
| Profile name | `--profile` | `default` | Slug for Chrome profile & launchd labels |

---

## 📦 Prerequisites

- **macOS** 12+ (Monterey or later)
- **Google Chrome** installed at `/Applications/Google Chrome.app/`
- **autossh**: `brew install autossh`
- **SSH key** with access to the remote server
- **Remote sshd** with `GatewayPorts yes` in `/etc/ssh/sshd_config`
- **Remote sshd keepalive** — ensure `/etc/ssh/sshd_config` has:
  ```
  ClientAliveInterval 15
  ClientAliveCountMax 3
  ```
  Without this, dead SSH sessions hold the forwarded port for 15+ minutes, blocking reconnection. After adding, run `systemctl reload ssh`.

---

## 🔌 Connecting from the Remote Agent

After install, CDP is available at `http://127.0.0.1:{REMOTE_CDP_PORT}` on your remote server.

**Playwright (Node.js)**
```js
const { chromium } = require('playwright');
const browser = await chromium.connectOverCDP('http://127.0.0.1:9223');
const [page] = browser.contexts()[0].pages();
await page.goto('https://example.com');
```

**Puppeteer**
```js
const puppeteer = require('puppeteer-core');
const browser = await puppeteer.connect({
  browserURL: 'http://127.0.0.1:9223'
});
```

**Raw CDP / Python**
```python
import requests
targets = requests.get('http://127.0.0.1:9223/json').json()
print(targets[0]['webSocketDebuggerUrl'])
```

**Verify it's working**
```bash
curl http://127.0.0.1:9223/json/version
# → {"Browser": "Chrome/124.0.0.0", "Protocol-Version": "1.3", ...}
```

---

## ⚠️ Concurrent CDP Connections

Chrome's DevTools Protocol handles one active debugging session well, but **multiple simultaneous Playwright/Puppeteer connections can crash Chrome** or cause `Target page, context or browser has been closed` errors.

If your agent runs frequent automated tasks (e.g., multiple times per hour), use this pattern:

**Serial Queue + New Tab per Task + Close Tab After**

- Only ONE Playwright `connectOverCDP` connection at a time
- Each task gets a fresh tab (`context.newPage()`), closed after completion
- Chrome stays running — no restart overhead
- Concurrent triggers wait in a queue instead of all connecting simultaneously

Reference implementation:

```js
// cdp-queue.mjs — Serial CDP connection queue
import { chromium } from 'playwright';

const CDP_ENDPOINT = 'http://127.0.0.1:{REMOTE_CDP_PORT}';
const queue = [];
let running = false;

export async function withBrowser(fn) {
  return new Promise((resolve, reject) => {
    queue.push({ fn, resolve, reject });
    processQueue();
  });
}

async function processQueue() {
  if (running || queue.length === 0) return;
  running = true;
  const { fn, resolve, reject } = queue.shift();
  let browser;
  try {
    browser = await chromium.connectOverCDP(CDP_ENDPOINT, { timeout: 15000 });
    const context = browser.contexts()[0];
    const page = await context.newPage();
    try {
      const result = await fn(page);
      resolve(result);
    } finally {
      await page.close().catch(() => {});
    }
  } catch (err) {
    reject(err);
  } finally {
    if (browser) await browser.close().catch(() => {});
    running = false;
    processQueue();
  }
}
```

Usage:
```js
import { withBrowser } from './cdp-queue.mjs';

const result = await withBrowser(async (page) => {
  await page.goto('https://example.com');
  // ... interact with page ...
  return extractedData;
});
```

> **Important:** `browser.close()` after `connectOverCDP` only disconnects the Playwright WebSocket — it does NOT kill Chrome. Chrome stays running for the next queued task.

---

## 🤖 Using as an Agent Skill

Load the skill in your agent context:

```
skills/chrome-cdp-relay/SKILL.md
```

The skill works with any LLM agent — Pi, Claude Code, Codex, Cursor, or anything else that can read instructions and run bash. It walks through parameter collection, prereq checks, script generation, launchd installation, and end-to-end verification.

---

## 🧹 Teardown

**Via installer (recommended)**
```bash
bash install.sh --uninstall --profile myprofile
```

**Manual**
```bash
launchctl unload ~/Library/LaunchAgents/com.openclaw.chrome-debug-myprofile.plist
launchctl unload ~/Library/LaunchAgents/com.openclaw.chrome-tunnel-myprofile.plist
rm ~/Library/LaunchAgents/com.openclaw.chrome-debug-myprofile.plist
rm ~/Library/LaunchAgents/com.openclaw.chrome-tunnel-myprofile.plist
rm ~/Library/Scripts/openclaw/chrome-managed-myprofile.sh
# Optionally (removes cookies/sessions!):
rm -rf ~/.openclaw/myprofile-chrome-profile
```

---

## 🌙 Keep Mac Awake (Optional)

If your Mac sleeps, Chrome closes and the tunnel drops. If you have the **mac-sleep-guard** skill:

```
Condition URL: http://127.0.0.1:9222/json/version
Reason: "Tunnelclaw CDP relay active"
```

Sleep guard prevents macOS sleep whenever Chrome is running.

---

## 🛠️ Troubleshooting

| Symptom | Fix |
|---------|-----|
| Local curl returns nothing | `tail /tmp/openclaw-chrome-debug-{profile}.err.log` |
| Remote curl refused | `tail /tmp/openclaw-autossh-{profile}.err.log` |
| Remote curl hangs | Add `GatewayPorts yes` to remote `/etc/ssh/sshd_config`, restart sshd |
| Chrome crashes on start | `lsof -i :9222` — kill conflicting process |
| SSH key rejected | `chmod 600 ~/.ssh/id_ed25519` |
| `remote port forwarding failed for listen port XXXX` | Set `ClientAliveInterval 15` + `ClientAliveCountMax 3` in remote `/etc/ssh/sshd_config` and `systemctl reload ssh`. Immediate fix: `ssh remote 'sudo fuser -k XXXX/tcp'` |
| Multiple concurrent Playwright connections crash Chrome | Use a serial queue — see ⚠️ Concurrent CDP Connections section below |

---

## 📁 Files

```
skills/chrome-cdp-relay/
├── SKILL.md                          ← Agent instructions (load this)
├── install.sh                        ← Standalone one-command installer
├── README.md                         ← This file
└── templates/
    ├── chrome-managed.sh.tmpl        ← Chrome launcher template
    ├── launchd-chrome.plist.tmpl     ← Chrome launchd plist template
    └── launchd-tunnel.plist.tmpl     ← autossh launchd plist template
```

---

<div align="center">

*A tunnel. A claw. A real browser for your remote agent.*

</div>
