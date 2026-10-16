#!/usr/bin/env bash
# Play the game from source (windowed). Extra arguments after -- go to the game, e.g.
#   bash scripts/run.sh -- --stage=104040000 --seed=7
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"
# Keep the editor/import state private when playtesting alongside other agents.
if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE/game"
  mkdir -p "$DEST"
  (cd "$PROJECT" && tar --exclude=./.godot --exclude=./export -cf - .) | (cd "$DEST" && tar -xf -)
  (cd "$DEST" && find . -type f ! -path './.godot/*' | while read -r f; do [[ -e "$PROJECT/$f" ]] || rm -f "$f"; done)
  PROJECT="$DEST"
fi
bash "$REPO/scripts/godot.sh" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
exec bash "$REPO/scripts/godot.sh" --path "$PROJECT" "$@"
