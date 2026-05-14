# kiri-demo

A self-contained demo for [Kiri](https://github.com/PaoloMassignan/kiri) — an on-premises
proxy that prevents proprietary source code from leaving your network when using
Claude Code, Cursor, or other LLM-powered tools.

This repo contains three fictional "Helios" modules with invented algorithms and
magic constants. Kiri is pre-configured to protect them. Run the demo and watch
Kiri redact implementation details in real time.

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)
- [Claude Code](https://claude.ai/code) **or** [OpenCode](https://opencode.ai)
- Git

---

## Setup

### Step 1 — Clone this repo

```bash
git clone https://github.com/PaoloMassignan/kiri-demo.git
cd kiri-demo
```

```powershell
# Windows
git clone https://github.com/PaoloMassignan/kiri-demo.git
cd kiri-demo
```

---

### Step 2 — Configure your session

**OAuth passthrough (Claude Pro/Max or OpenCode subscription)**
Nothing to do — skip to Step 3.

**API key mode**

Put your real Anthropic key in `.kiri/upstream.key` (this file is gitignored):

```bash
echo "sk-ant-YOUR-KEY" > .kiri/upstream.key      # Linux / Mac
```
```powershell
"sk-ant-YOUR-KEY" | Out-File .kiri\upstream.key  # Windows
```

Then copy `.env.example` to `.env`, uncomment `ANTHROPIC_API_KEY` and paste
your Kiri key (generated after first start), and set `oauth_passthrough: false`
in `.kiri/config.yaml`.

---

### Step 3 — Start

```bash
bash scripts/start.sh              # Linux / Mac
```
```powershell
.\scripts\start.ps1                # Windows
```

The script:
1. Starts Docker if needed (Windows only)
2. Pulls the Kiri image and launches it via `docker compose`
3. Waits for the proxy to be ready
4. Sets `ANTHROPIC_BASE_URL=http://localhost:8765` for this session only
5. Opens Claude Code or OpenCode
6. Restores your original environment when you exit

> First run pulls the Kiri image (~500 MB) and the `qwen2.5:3b` Ollama
> classifier model (~2 GB). Subsequent starts are instant.

---

## Running the demo

Follow the guided test sequence in **[DEMO.md](DEMO.md)**.

---

## File layout

```
.kiri/
  config.yaml       committed -- proxy settings
  secrets           committed -- list of protected files
  upstream.key      gitignored -- your real Anthropic key (API key mode only)
  index/            gitignored -- vector index, rebuilt locally
  keys/             gitignored -- kiri kr- keys, per developer
scripts/
  start.ps1 / start.sh          launch script (Windows / Linux-Mac)
  kiri.ps1  / kiri.sh           thin kiri CLI wrapper
src/
  engine/risk_scorer.py         fictional Helios v2.3 risk engine
  engine/fraud_detector.py      fictional pattern correlation engine
  utils/token_bucket.py         fictional adaptive rate limiter
```

---

## Stopping Kiri

Kiri keeps running after you close the LLM session so you can restart quickly.
To shut it down completely:

```bash
docker compose --project-directory . down
```

---

## Troubleshooting

**Kiri does not start / health check fails**
```bash
docker compose --project-directory . logs kiri
docker compose --project-directory . logs ollama
```

**OAuth 401 errors**
Make sure `oauth_passthrough: true` is in `.kiri/config.yaml` and
`ANTHROPIC_API_KEY` is not set in `.env`.

**Code slips through unredacted**
```bash
bash scripts/kiri.sh log --tail 5
bash scripts/kiri.sh status
```
If the decision is PASS and the prompt contains no protected symbol name,
that is expected — see DEMO.md for what to test.
