#!/usr/bin/env bash
# Starts Kiri in native mode (no Docker, no Ollama) and launches Claude Code
# or OpenCode with the proxy configured.  Restores the original environment
# on exit and stops the kiri process.
#
# Usage:
#   bash scripts/start.sh              # OAuth or API key mode
#   bash scripts/start.sh claude       # Force Claude Code
#   bash scripts/start.sh opencode     # Force OpenCode
#
# Prerequisites:
#   kiri binary in PATH (download from https://github.com/PaoloMassignan/kiri/releases)
#   For L3 classifier: run "sudo kiri install" first to download the GGUF model.
#
# Fallback to Docker: bash scripts/start-docker.sh

set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DEMO_DIR"

# ── Check kiri binary ─────────────────────────────────────────────────────────
if ! command -v kiri >/dev/null 2>&1; then
    echo "Error: 'kiri' not found in PATH." >&2
    echo ""
    echo "Install the native binary:" >&2
    echo "  https://github.com/PaoloMassignan/kiri/releases/latest" >&2
    echo ""
    echo "Or fall back to Docker mode:" >&2
    echo "  bash scripts/start.sh" >&2
    exit 1
fi

# ── Parse args ────────────────────────────────────────────────────────────────
TOOL=""
for arg in "$@"; do
    case "$arg" in
        claude|opencode) TOOL="$arg" ;;
    esac
done

# ── Key setup ─────────────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    set -a; source .env; set +a
fi
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

if [[ -z "$ANTHROPIC_API_KEY" ]]; then
    echo "Mode: OAuth passthrough"
    mkdir -p .kiri
    # upstream.key must exist for docker-compose secrets — not needed for native,
    # but write a placeholder so docker fallback keeps working too.
    if [[ ! -f .kiri/upstream.key ]]; then
        echo -n "oauth-passthrough-placeholder" > .kiri/upstream.key
    fi
else
    echo "Mode: API key (${ANTHROPIC_API_KEY:0:8}...)"
    if [[ ! -f .kiri/upstream.key ]]; then
        echo "Error: .kiri/upstream.key not found." >&2
        echo "Create it with: echo 'sk-ant-YOUR-KEY' > .kiri/upstream.key" >&2
        exit 1
    fi
fi

# ── Detect GGUF model ─────────────────────────────────────────────────────────
_MODEL_FILENAME="qwen2.5-3b-q4.gguf"
case "$(uname -s 2>/dev/null || echo Windows)" in
    Darwin|Linux) _MODEL_PATH="/var/lib/kiri/models/$_MODEL_FILENAME" ;;
    *)            _MODEL_PATH="C:/ProgramData/Kiri/models/$_MODEL_FILENAME" ;;
esac

if [[ -f "$_MODEL_PATH" ]]; then
    _LLM_BACKEND="llama_cpp"
    _MODEL_LINE="llm_model_path: $_MODEL_PATH"
    echo "Local AI: enabled ($_LLM_BACKEND, $(basename "$_MODEL_PATH"))"
else
    _LLM_BACKEND="ollama"
    _MODEL_LINE=""
    echo "Local AI: disabled (model not found at $_MODEL_PATH)"
    echo "  L3 classifier will fail-open — L1 and L2 remain fully active."
    echo "  To enable L3: sudo kiri install"
fi

# ── Generate runtime config ───────────────────────────────────────────────────
cat > .kiri/config.native.local <<EOF
oauth_passthrough: $(if [[ -z "$ANTHROPIC_API_KEY" ]]; then echo "true"; else echo "false"; fi)
similarity_threshold: 0.75
hard_block_threshold: 0.90
action: sanitize
proxy_port: 8765
embedding_model: all-MiniLM-L6-v2
llm_backend: $_LLM_BACKEND
$(if [[ -n "$_MODEL_LINE" ]]; then echo "$_MODEL_LINE"; fi)
EOF

# ── Set mode sentinel ─────────────────────────────────────────────────────────
echo "native" > .kiri/.mode

# ── Start kiri serve in background ───────────────────────────────────────────
echo "Starting Kiri (native)..."
export KIRI_CONFIG="$DEMO_DIR/.kiri/config.native.local"
export WORKSPACE="$DEMO_DIR"
[[ -f .kiri/upstream.key ]] && export KIRI_UPSTREAM_KEY_FILE="$DEMO_DIR/.kiri/upstream.key"

kiri serve >.kiri/kiri-serve.log 2>&1 &
KIRI_PID=$!

# ── Health check ──────────────────────────────────────────────────────────────
echo -n "Waiting for Kiri to be ready"
STARTED=false
for i in $(seq 1 30); do
    if curl -sf http://localhost:8765/health >/dev/null 2>&1; then
        echo " ready."
        STARTED=true
        break
    fi
    echo -n "."
    sleep 2
done
if [[ "$STARTED" == "false" ]]; then
    echo ""
    echo "Kiri did not become ready in 60 s." >&2
    echo "Check the log:  cat .kiri/kiri-serve.log" >&2
    echo "Or check port:  lsof -ti :8765" >&2
    kill "$KIRI_PID" 2>/dev/null || true
    rm -f .kiri/.mode
    exit 1
fi

# ── Pick tool ─────────────────────────────────────────────────────────────────
if [[ -z "$TOOL" ]]; then
    if   command -v claude    >/dev/null 2>&1; then TOOL=claude
    elif command -v opencode  >/dev/null 2>&1; then TOOL=opencode
    fi
    if [[ -z "$TOOL" ]]; then
        echo "Error: neither 'claude' nor 'opencode' found in PATH." >&2
        echo "Install one, or pass it explicitly: bash scripts/start.sh opencode" >&2
        kill "$KIRI_PID" 2>/dev/null || true
        rm -f .kiri/.mode
        exit 1
    fi
fi
echo "Launching $TOOL through Kiri..."

# ── Set env, launch, restore ──────────────────────────────────────────────────
_PREV_BASE_URL="${ANTHROPIC_BASE_URL:-}"
_PREV_API_KEY="${ANTHROPIC_API_KEY:-}"

export ANTHROPIC_BASE_URL="http://localhost:8765"
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
    unset ANTHROPIC_API_KEY 2>/dev/null || true
fi

cleanup() {
    # Restore env
    if [[ -n "$_PREV_BASE_URL" ]]; then export ANTHROPIC_BASE_URL="$_PREV_BASE_URL"
    else unset ANTHROPIC_BASE_URL 2>/dev/null || true; fi
    if [[ -n "$_PREV_API_KEY" ]]; then export ANTHROPIC_API_KEY="$_PREV_API_KEY"
    else unset ANTHROPIC_API_KEY 2>/dev/null || true; fi
    # Stop kiri and clear mode sentinel
    kill "$KIRI_PID" 2>/dev/null || true
    rm -f "$DEMO_DIR/.kiri/.mode"
    unset KIRI_CONFIG WORKSPACE KIRI_UPSTREAM_KEY_FILE 2>/dev/null || true
    echo "Session ended. Kiri stopped."
}
trap cleanup EXIT

"$TOOL" || true
