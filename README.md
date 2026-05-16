# kiri-demo

A self-contained demo for [Kiri](https://github.com/PaoloMassignan/kiri) — an on-premises
proxy that prevents proprietary source code from leaving your network when using
Claude Code, Cursor, or other LLM-powered tools.

This repo contains three fictional "Helios" modules with invented algorithms and
magic constants. Kiri is pre-configured to protect them. Run the demo and watch
Kiri redact implementation details in real time.

---

## Prerequisites

- [Claude Code](https://claude.ai/code) **or** [OpenCode](https://opencode.ai)
- Git

---

## Quick start — Native mode ★ Recommended

No Docker, no Ollama. A single binary is all you need.

### Step 1 — Download Kiri

Grab the binary for your platform from the
[latest release](https://github.com/PaoloMassignan/kiri/releases/latest)
and put it in your PATH.

### Step 2 — Clone the demo

```bash
git clone https://github.com/PaoloMassignan/kiri-demo.git
cd kiri-demo
```

### Step 3 — Choose your auth mode

#### Option A — OAuth (Claude Pro/Max or OpenCode subscription)

Nothing to configure — skip to Step 4.

#### Option B — Anthropic API key

```bash
echo "sk-ant-YOUR-KEY" > .kiri/upstream.key      # Linux / Mac
"sk-ant-YOUR-KEY" | Out-File .kiri\upstream.key  # Windows (PowerShell)
```

### Step 4 — Start

```bash
bash scripts/start.sh              # Linux / macOS
```
```powershell
.\scripts\start.ps1               # Windows
```

The script:
1. Detects whether a GGUF model is available (`kiri install` downloads it once)
2. Generates a runtime config in `.kiri/config.native.local`
3. Starts `kiri serve` as a background process
4. Waits for the proxy to be ready
5. Sets `ANTHROPIC_BASE_URL=http://localhost:8765` for this session only
6. Opens Claude Code or OpenCode
7. Stops Kiri and restores your environment when you exit

> **L3 classifier (local LLM):** enabled automatically if you previously ran
> `sudo kiri install` (Linux/macOS) or `kiri install` as Administrator (Windows).
> If the model is not present, L3 fails-open — L1 (vector similarity) and
> L2 (symbol matching) remain fully active.

---

## Alternative — Docker mode

Requires [Docker Desktop](https://www.docker.com/products/docker-desktop/).
Use this if you can't install the native binary, or to roll back instantly.

### Step 3 (Docker) — Choose your auth mode

#### Option A — OAuth passthrough

Nothing to configure — skip to Step 4.

#### Option B — Anthropic API key

```bash
echo "sk-ant-YOUR-KEY" > .kiri/upstream.key
```

Then:
1. Set `oauth_passthrough: false` in `.kiri/config.yaml`
2. Start Kiri (Step 4), then generate a `kr-` key: `bash scripts/kiri.sh key create`
3. Copy `.env.example` to `.env`, uncomment `ANTHROPIC_API_KEY`, and paste the `kr-` key

#### Option C — Free local mode (no cloud account)

Nothing to configure. Start with the `local` flag (Step 4) and the demo
runs entirely on your machine using Ollama. Requires
[OpenCode](https://opencode.ai).

> First run downloads the LiteLLM image (~1 GB).

### Step 4 (Docker) — Start

```bash
bash scripts/start-docker.sh              # Linux / macOS  (cloud mode)
bash scripts/start-docker.sh local        # Linux / macOS  (local Ollama mode)
```
```powershell
.\scripts\start-docker.ps1                # Windows (cloud mode)
.\scripts\start-docker.ps1 -Local         # Windows (local Ollama mode)
```

> First run pulls the Kiri image (~500 MB) and the `qwen2.5:3b` model
> (~2 GB). Subsequent starts are instant.

### Stopping Docker services

```bash
docker compose --project-directory . down
```

---

## Running the demo

Follow the guided test sequence in **[DEMO.md](DEMO.md)**.

---

## Mode comparison

| | Native ★ | Docker |
|---|---|---|
| **Dependencies** | `kiri` binary only | Docker Desktop |
| **L3 classifier** | `llama-cpp-python` (in-process) | Ollama sidecar |
| **Startup time** | ~3 s | ~30 s (image pull on first run) |
| **Rollback** | `bash scripts/start-docker.sh` | — |

---

## File layout

```
.kiri/
  config.yaml            committed — Docker proxy settings
  config.native.yaml     committed — native proxy settings template
  config.native.local    gitignored — generated at runtime by start.sh
  secrets                committed — list of protected files
  upstream.key           gitignored — your real Anthropic key (API key mode only)
  index/                 gitignored — vector index, rebuilt locally
  keys/                  gitignored — kiri kr- keys, per developer
scripts/
  start.sh / .ps1              ★ native start (Linux-Mac / Windows)
  start-docker.sh / .ps1       Docker start (Linux-Mac / Windows)
  kiri.sh   / .ps1          kiri CLI wrapper — auto-detects native vs Docker
src/
  engine/risk_scorer.py    fictional Helios v2.3 risk engine
  engine/fraud_detector.py fictional pattern correlation engine
  utils/token_bucket.py    fictional adaptive rate limiter
```

---

## Troubleshooting

### Native mode

**Port 8765 already in use**

Another kiri process may be running. Find and stop it:
```bash
lsof -ti :8765 | xargs kill   # Linux / macOS
netstat -ano | findstr :8765   # Windows — note the PID, then: taskkill /PID <pid> /F
```

**L3 classifier disabled (model not found)**

Run `sudo kiri install` to download the GGUF model. You can also pass
`--model-path /path/to/model.gguf` to use a pre-downloaded file (air-gapped).

### Docker mode

**Kiri does not start / health check fails**
```bash
docker compose --project-directory . logs kiri
docker compose --project-directory . logs ollama
docker compose --project-directory . logs litellm   # local mode only
```

**OAuth 401 errors**
Make sure `oauth_passthrough: true` is in `.kiri/config.yaml` and
`ANTHROPIC_API_KEY` is not set in `.env`.

**Code slips through unredacted**
```bash
bash scripts/kiri.sh log --tail 5
bash scripts/kiri.sh status
```
