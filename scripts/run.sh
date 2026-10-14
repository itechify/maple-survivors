#!/usr/bin/env bash
# Play the game from source (windowed). Extra arguments after -- go to the game, e.g.
#   bash scripts/run.sh -- --stage=104040000 --seed=7
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
bash "$REPO/scripts/godot.sh" --headless --path "$REPO/game" --import >/dev/null 2>&1 || true
exec bash "$REPO/scripts/godot.sh" --path "$REPO/game" "$@"
