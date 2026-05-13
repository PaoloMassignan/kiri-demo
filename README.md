# kiri-demo

A self-contained demo for [Kiri](https://github.com/kiri-ai/kiri) — an on-premises
proxy that prevents proprietary source code from leaving your network when using
Claude Code, Cursor, or other LLM-powered tools.

This repo contains three fictional "Helios" modules with invented algorithms and
magic constants. Kiri is pre-configured to protect them.  Run the demo and watch
Kiri redact implementation details in real time.

---

## Prerequisites

- [Docker Desktop](https://www.docker.com/products/docker-desktop/) (running)
- [Claude Code](https://claude.ai/code) **or** [OpenCode](https://opencode.ai)
- The `kiri-local` Docker image (build once — see step 1)

---

## Setup

### Step 1 — Build the Kiri image

Clone the Kiri source repo anywhere you like, then build the image:

```bash
git clone https://github.com/kiri-ai/kiri
scripts/build-image.sh /path/to/kiri        # Linux / Mac
scripts\build-image.ps1 -KiriRepo C:\path\to\kiri   # Windows
```

> If `kiri/` and `kiri-demo/` share the same parent directory the build
> scripts find the source automatically — no argument needed.

---

### Step 2 — Configure your session

```bash
cp .env.example .env
```

**OAuth passthrough (Claude Pro/Max or OpenCode subscription)**
No changes needed — leave `ANTHROPIC_API_KEY` commented out.

**API key mode**
```bash
# Put your real Anthropic key inside the container secret (never committed):
echo "sk-ant-YOUR-KEY" > .kiri/upstream.key      # Linux/Mac
"sk-ant-YOUR-KEY" | Out-File .kiri\upstream.key  # Windows PS

# Generate a kiri key after starting (step 3), then add it to .env:
# ANTHROPIC_API_KEY=kr-your-kiri-key-here
# Also set oauth_passthrough: false in .kiri/config.yaml
```

---

### Step 3 — Start

**Windows**
```powershell
.\scripts\start.ps1
```

**Linux / Mac**
```bash
bash scripts/start.sh
```

The script:
1. Starts Docker if needed
2. Launches Kiri (proxy + Ollama classifier) via `docker compose`
3. Sets `ANTHROPIC_BASE_URL=http://localhost:8765` for the session only
4. Opens Claude Code or OpenCode
5. Restores your original environment on exit

> First run takes a few minutes while Ollama downloads the `qwen2.5:3b` model
> (~2 GB).  Subsequent starts are instant.

---

## Running the demo

Follow the guided test sequence in **[DEMO.md](DEMO.md)**.

---

## File layout

```
.kiri/
  config.yaml       committed — proxy settings
  secrets           committed — list of protected files
  upstream.key      gitignored — your real Anthropic key (API key mode only)
  index/            gitignored — vector index, rebuilt locally
  keys/             gitignored — kiri kr- keys, per developer
scripts/
  start.ps1 / start.sh          launch script (Windows / Linux-Mac)
  kiri.ps1  / kiri.sh           thin CLI wrapper
  build-image.ps1 / build-image.sh   one-time image build
src/
  engine/risk_scorer.py         fictional Helios v2.3 risk engine
  engine/fraud_detector.py      fictional pattern correlation engine
  utils/token_bucket.py         fictional adaptive rate limiter
```

---

## Stopping Kiri

Kiri keeps running after you close the LLM session (so you can restart quickly).
To shut it down completely:

```bash
docker compose down
```

---

## Troubleshooting

**Kiri does not start / health check fails**
```bash
docker compose logs kiri
docker compose logs ollama
```

**`kiri-local` image not found**
Run `scripts/build-image.sh` (or `.ps1`) first.

**OAuth 401 errors**
Make sure `oauth_passthrough: true` is set in `.kiri/config.yaml` and
`ANTHROPIC_API_KEY` is absent from the environment.

**Code slips through unredacted**
Run `bash scripts/kiri.sh log --tail 5` and check the decision column.
If PASS: the prompt may not contain any protected symbol — check
`bash scripts/kiri.sh status` to confirm all files are indexed.
