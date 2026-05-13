#!/usr/bin/env bash
# Starts Kiri and launches Claude Code or OpenCode with the proxy configured.
# Restores the original environment on exit.
#
# Usage: bash scripts/start.sh [claude|opencode]
#   Omit the argument to auto-detect which tool is installed.

set -euo pipefail
DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DEMO_DIR"

# ── Load .env ──────────────────────────────────────────────────────────────────
if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

ANTHROPIC_BASE_URL="${ANTHROPIC_BASE_URL:-http://localhost:8765}"
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

# ── OAuth vs API key mode ──────────────────────────────────────────────────────
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
    echo "Mode: OAuth passthrough"
    mkdir -p .kiri
    if [[ ! -f .kiri/upstream.key ]]; then
        echo "oauth-passthrough-placeholder" > .kiri/upstream.key
    fi
else
    echo "Mode: API key (${ANTHROPIC_API_KEY:0:8}...)"
    if [[ ! -f .kiri/upstream.key ]]; then
        echo "Error: .kiri/upstream.key not found." >&2
        echo "Create it with: echo 'sk-ant-YOUR-KEY' > .kiri/upstream.key" >&2
        exit 1
    fi
fi

# ── Docker check ───────────────────────────────────────────────────────────────
if ! docker ps >/dev/null 2>&1; then
    echo "Docker is not running. Please start Docker Desktop and retry." >&2
    exit 1
fi

# ── Start Kiri if not running ──────────────────────────────────────────────────
STARTED=false
RUNNING=$(docker compose --project-directory "$DEMO_DIR" ps --services --filter status=running 2>/dev/null | grep -c "^kiri$" || true)
if [[ "$RUNNING" -eq 0 ]]; then
    echo "Starting Kiri..."
    export WORKSPACE_HOST="$DEMO_DIR"
    docker compose --project-directory "$DEMO_DIR" up -d

    echo -n "Waiting for Kiri to be ready"
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
else
    echo "Kiri already running."
fi

# ── Pick tool ──────────────────────────────────────────────────────────────────
TOOL="${1:-}"
if [[ -z "$TOOL" ]]; then
    if command -v claude >/dev/null 2>&1; then
        TOOL=claude
    elif command -v opencode >/dev/null 2>&1; then
        TOOL=opencode
    else
        echo "Error: neither 'claude' nor 'opencode' found in PATH." >&2
        echo "Install one and retry, or set the tool explicitly: bash scripts/start.sh claude" >&2
        exit 1
    fi
fi
echo "Launching $TOOL through Kiri..."

# ── Set env, launch, restore ───────────────────────────────────────────────────
_PREV_BASE_URL="${ANTHROPIC_BASE_URL:-}"
_PREV_API_KEY="${ANTHROPIC_API_KEY:-}"

export ANTHROPIC_BASE_URL="http://localhost:8765"
if [[ -z "$ANTHROPIC_API_KEY" ]]; then
    unset ANTHROPIC_API_KEY
fi

"$TOOL" || true

# Restore
if [[ -n "$_PREV_BASE_URL" ]]; then
    export ANTHROPIC_BASE_URL="$_PREV_BASE_URL"
else
    unset ANTHROPIC_BASE_URL
fi
if [[ -n "$_PREV_API_KEY" ]]; then
    export ANTHROPIC_API_KEY="$_PREV_API_KEY"
else
    unset ANTHROPIC_API_KEY 2>/dev/null || true
fi

echo "Session ended. Kiri is still running (stop with: docker compose --project-directory '$DEMO_DIR' down)"
