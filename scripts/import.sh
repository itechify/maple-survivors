#!/usr/bin/env bash
# Build the asset cache from your own MapleStory v83 install (offline, local files only).
#
#   bash scripts/import.sh "C:/Nexon/MapleStory"           # or set MAPLE_WZ_ROOT
#   bash scripts/import.sh "C:/Nexon/MapleStory" --force   # rewrite every img
#
# Output: $MAPLE_SURVIVORS_CACHE, default %APPDATA%/MapleSurvivors/asset_cache/v83 (the game's user data folder).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
WZ="${1:-${MAPLE_WZ_ROOT:-}}"
shift || true
if [[ -z "$WZ" ]]; then
  echo "usage: bash scripts/import.sh <folder containing Map.wz, Mob.wz, ...> [--force]" >&2
  exit 2
fi

if [[ -n "${MAPLE_SURVIVORS_CACHE:-}" ]]; then
  OUT="$MAPLE_SURVIVORS_CACHE"
elif [[ -n "${APPDATA:-}" ]]; then
  OUT="$(cygpath -m "$APPDATA" 2>/dev/null || echo "$APPDATA")/MapleSurvivors/asset_cache/v83"
else
  OUT="${XDG_DATA_HOME:-$HOME/.local/share}/godot/app_userdata/MapleSurvivors/asset_cache/v83"
fi

(cd "$REPO/tools/wzimport" && cargo build --release --quiet)
BIN="$REPO/tools/wzimport/target/release/wzimport"
[[ -x "$BIN" || -x "$BIN.exe" ]] || { echo "wzimport build failed" >&2; exit 1; }
"$BIN" import --wz "$WZ" --manifest "$REPO/game/data/asset_manifest.json" --out "$OUT" "$@"
