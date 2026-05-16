#!/usr/bin/env bash
# Thin wrapper: runs kiri CLI commands in whichever mode is active.
#
#   Native mode  — runs kiri directly against the demo workspace.
#                  Active when start.sh has written .kiri/.mode=native.
#   Docker mode  — forwards the command into the kiri container (original behaviour).
#                  Active when start.sh is used (default / rollback).
#
# Usage: bash scripts/kiri.sh <subcommand> [args...]
#   bash scripts/kiri.sh status
#   bash scripts/kiri.sh log --tail 10
#   bash scripts/kiri.sh explain --show-redacted

DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE_FILE="$DEMO_DIR/.kiri/.mode"

if [[ -f "$MODE_FILE" ]] && [[ "$(cat "$MODE_FILE")" == "native" ]]; then
    # Native mode: run kiri directly with the demo workspace
    KIRI_CONFIG="$DEMO_DIR/.kiri/config.native.local" \
    WORKSPACE="$DEMO_DIR" \
    kiri "$@"
else
    # Docker mode (original behaviour)
    exec docker compose --project-directory "$DEMO_DIR" exec kiri kiri "$@"
fi
