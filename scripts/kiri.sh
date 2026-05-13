#!/usr/bin/env bash
# Thin wrapper: forwards all arguments to kiri inside the Docker container.
# Works from Claude Code (bash) on Windows, Linux, and Mac.
#
# Usage: bash scripts/kiri.sh <subcommand> [args...]
#   bash scripts/kiri.sh status
#   bash scripts/kiri.sh log --tail 10
#   bash scripts/kiri.sh explain --show-redacted

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec docker compose --project-directory "$DEMO_DIR" exec kiri kiri "$@"
