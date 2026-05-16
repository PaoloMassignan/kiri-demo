#!/usr/bin/env bash
# Starts Kiri and launches Claude Code or OpenCode with the proxy configured.
# Restores the original environment on exit.
#
# Usage:
#   bash scripts/start-docker.sh               # OAuth or API key mode (Anthropic/Claude cloud)
#   bash scripts/start-docker.sh local         # Local Ollama mode (no cloud account needed)
#   bash scripts/start-docker.sh local claude  # Force a specific tool in local mode
#   bash scripts/start-docker.sh claude        # Force a specific tool in cloud mode

set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DEMO_DIR"

# ── Parse args ─────────────────────────────────────────────────────────────────
LOCAL=false
TOOL=""
for arg in "$@"; do
    case "$arg" in
        local) LOCAL=true ;;
        claude|opencode) TOOL="$arg" ;;
    esac
done

# ── Docker check ───────────────────────────────────────────────────────────────
if ! docker ps >/dev/null 2>&1; then
    echo "Docker is not running. Please start Docker Desktop and retry." >&2
    exit 1
fi

# ── Mode setup ─────────────────────────────────────────────────────────────────
COMPOSE_PROFILE_ARGS=()

if [[ "$LOCAL" == "true" ]]; then
    echo "Mode: Local LLM (Ollama/qwen2.5:3b via LiteLLM — no cloud account needed)"
    mkdir -p .kiri
    if [[ ! -f .kiri/upstream.key ]]; then
        echo -n "local-mode-placeholder" > .kiri/upstream.key
    fi
    export KIRI_UPSTREAM_URL="http://litellm:4000"
    COMPOSE_PROFILE_ARGS=("--profile" "local")
    TOOL_API_KEY="sk-ant-local-demo"
else
    # ── Load .env ───────────────────────────────────────────────────────────────
    if [[ -f .env ]]; then
        set -a
        # shellcheck disable=SC1091
        source .env
        set +a
    fi

    ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

    if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        echo "Mode: OAuth passthrough"
        mkdir -p .kiri
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
    TOOL_API_KEY="$ANTHROPIC_API_KEY"
fi

# ── Start / update services ────────────────────────────────────────────────────
# Always run 'up -d': docker compose recreates kiri if ANTHROPIC_BASE_URL
# changed (e.g. switching between cloud and local mode), and is a no-op otherwise.
echo "Starting Kiri..."
export WORKSPACE_HOST="$DEMO_DIR"
docker compose "${COMPOSE_PROFILE_ARGS[@]}" --project-directory "$DEMO_DIR" up -d

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
    echo "Check logs: docker compose --project-directory '$DEMO_DIR' logs kiri" >&2
    exit 1
fi

# ── Pick tool ──────────────────────────────────────────────────────────────────
if [[ -z "$TOOL" ]]; then
    if [[ "$LOCAL" == "true" ]]; then
        # Local mode: prefer OpenCode (Claude Code needs a real Anthropic session)
        if command -v opencode >/dev/null 2>&1; then TOOL=opencode
        elif command -v claude >/dev/null 2>&1;   then TOOL=claude
        fi
    else
        if command -v claude >/dev/null 2>&1;     then TOOL=claude
        elif command -v opencode >/dev/null 2>&1; then TOOL=opencode
        fi
    fi
    if [[ -z "$TOOL" ]]; then
        echo "Error: neither 'claude' nor 'opencode' found in PATH." >&2
        echo "Install one and retry, or pass the tool explicitly: bash scripts/start-docker.sh local opencode" >&2
        exit 1
    fi
fi
echo "Launching $TOOL through Kiri..."

# ── Set env, launch, restore ───────────────────────────────────────────────────
_PREV_BASE_URL="${ANTHROPIC_BASE_URL:-}"
_PREV_API_KEY="${ANTHROPIC_API_KEY:-}"

export ANTHROPIC_BASE_URL="http://localhost:8765"
if [[ -z "$TOOL_API_KEY" ]]; then
    unset ANTHROPIC_API_KEY 2>/dev/null || true
else
    export ANTHROPIC_API_KEY="$TOOL_API_KEY"
fi

"$TOOL" || true

# Restore
if [[ -n "$_PREV_BASE_URL" ]]; then
    export ANTHROPIC_BASE_URL="$_PREV_BASE_URL"
else
    unset ANTHROPIC_BASE_URL 2>/dev/null || true
fi
if [[ -n "$_PREV_API_KEY" ]]; then
    export ANTHROPIC_API_KEY="$_PREV_API_KEY"
else
    unset ANTHROPIC_API_KEY 2>/dev/null || true
fi
if [[ "$LOCAL" == "true" ]]; then
    unset KIRI_UPSTREAM_URL 2>/dev/null || true
fi

echo "Session ended. Kiri is still running (stop with: docker compose --project-directory '$DEMO_DIR' down)"
