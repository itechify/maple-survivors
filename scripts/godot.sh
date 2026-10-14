#!/usr/bin/env bash
# Locate (and if needed download) the pinned Godot binary, then run it with the given arguments.
#
#   bash scripts/godot.sh --version
#   bash scripts/godot.sh --headless --path game res://tests/test_runner.tscn
#   bash scripts/godot.sh --gui --path game        # the windowed (non-console) exe on Windows
#
# Override the binary with GODOT=/path/to/godot. The binary lives outside the repo
# (Windows: %LOCALAPPDATA%/MapleSurvivors/godot/<version>/, Linux: ~/.local/share/MapleSurvivors/godot/<version>/).
# An existing copy of the same version from the sibling MisoStory project is reused instead of downloading again.
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GUI=0
if [[ "${1:-}" == "--gui" ]]; then GUI=1; shift; fi

case "$(uname -s)" in
  Linux)
    PLATFORM="linux.x86_64"
    ROOT="${XDG_DATA_HOME:-$HOME/.local/share}"
    ZIP="Godot_v${GODOT_VERSION}-stable_${PLATFORM}.zip"
    CONSOLE_NAME="Godot_v${GODOT_VERSION}-stable_${PLATFORM}"
    WINDOWED_NAME="$CONSOLE_NAME"
    ;;
  *)
    ROOT="${LOCALAPPDATA:-$HOME/AppData/Local}"
    ROOT="$(cygpath -u "$ROOT" 2>/dev/null || echo "$ROOT")"
    ZIP="Godot_v${GODOT_VERSION}-stable_win64.exe.zip"
    CONSOLE_NAME="Godot_v${GODOT_VERSION}-stable_win64_console.exe"
    WINDOWED_NAME="Godot_v${GODOT_VERSION}-stable_win64.exe"
    ;;
esac

if [[ -z "${GODOT:-}" ]]; then
  DIR=""
  for cand in "$ROOT/MapleSurvivors/godot/$GODOT_VERSION" "$ROOT/MisoStory/godot/$GODOT_VERSION"; do
    if [[ -x "$cand/$CONSOLE_NAME" ]]; then DIR="$cand"; break; fi
  done
  if [[ -z "$DIR" ]]; then
    DIR="$ROOT/MapleSurvivors/godot/$GODOT_VERSION"
    echo "[godot.sh] Godot $GODOT_VERSION not found; downloading to $DIR" >&2
    mkdir -p "$DIR"
    curl -sSfL -o "$DIR/godot.zip" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/$ZIP"
    (cd "$DIR" && unzip -o -q godot.zip && rm godot.zip)
    chmod +x "$DIR/$CONSOLE_NAME" "$DIR/$WINDOWED_NAME" 2>/dev/null || true
  fi
  if [[ "$GUI" == 1 ]]; then GODOT="$DIR/$WINDOWED_NAME"; else GODOT="$DIR/$CONSOLE_NAME"; fi
fi

exec "$GODOT" "$@"
