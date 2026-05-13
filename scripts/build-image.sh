#!/usr/bin/env bash
# Builds the kiri-local Docker image from the kiri source repository.
#
# Usage: bash scripts/build-image.sh [/path/to/kiri-repo]
#   If the path is omitted, looks for the repo next to kiri-demo (../kiri or ../AI-Layer/kiri).

set -euo pipefail

KIRI_REPO="${1:-}"

if [[ -z "$KIRI_REPO" ]]; then
    DEMO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    for candidate in "$DEMO_DIR/../kiri" "$DEMO_DIR/../AI-Layer/kiri"; do
        if [[ -f "$candidate/Dockerfile" ]]; then
            KIRI_REPO="$(cd "$candidate" && pwd)"
            break
        fi
    done
fi

if [[ -z "$KIRI_REPO" || ! -f "$KIRI_REPO/Dockerfile" ]]; then
    PARENT="$(cd "$DEMO_DIR/.." && pwd)"
    echo "Could not find the kiri repository next to kiri-demo." >&2
    echo "Clone it first:" >&2
    echo "  cd $PARENT" >&2
    echo "  git clone https://github.com/PaoloMassignan/kiri.git" >&2
    echo "Then re-run this script from kiri-demo." >&2
    echo "" >&2
    echo "Or point to an existing clone:" >&2
    echo "  bash scripts/build-image.sh /path/to/kiri" >&2
    exit 1
fi

echo "Building kiri-local from: $KIRI_REPO"
docker build -t kiri-local "$KIRI_REPO"
echo "Done. Image tagged as kiri-local."
