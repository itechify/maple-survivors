#!/usr/bin/env bash
# Export the Windows build: game/export/MapleSurvivors.exe (pck embedded, game/export_presets.cfg "Windows Desktop")
# plus the release wzimport.exe next to it (the import screen looks for the importer beside the game executable) and
# the licence notices that must ship with them: THIRD_PARTY_NOTICES.md, GODOT_LICENSES.txt (the engine's MIT licence
# and its bundled components, written by game/tools/write_licenses.gd from the engine itself) and WZIMPORT_LICENSES.txt
# (the licence files of every crate in tools/wzimport/Cargo.lock, found through `cargo metadata --offline`) and
# ARIMO_OFL.txt (the licence of the bundled fallback font).
# game/export/ is gitignored; nothing from the player's WZ files is bundled (the build reads the asset cache at
# %APPDATA%/MapleSurvivors/asset_cache/v83, or runs the bundled importer from its import screen).
#
#   bash scripts/export.sh                  # release export
#   bash scripts/export.sh --debug          # debug export (prints script errors)
#   ISOLATE=<name> bash scripts/export.sh   # import/export from a private mirror (_scratch/godot_runs/<name>/game)
#   EXPORT_DIR=<abs dir> bash scripts/export.sh   # write the build somewhere else than game/export
#
# The script fails when Godot's export fails: the previous exe is deleted first and Godot's exit status is checked.
# Needs the Godot export templates for the pinned version (%APPDATA%/Godot/export_templates/<version>.stable on
# Windows; install them from the Godot editor or the official templates archive) and Rust/cargo for wzimport.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"
OUT_DIR="${EXPORT_DIR:-$REPO/game/export}"
MODE="--export-release"
[[ "${1:-}" == "--debug" ]] && MODE="--export-debug"
FILTER='^(Godot Engine v|WARNING: .*leaked|   at: |Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: .* resources still in use)'

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
TEMPLATES="${APPDATA:-$HOME/.local/share}/Godot/export_templates/${GODOT_VERSION}.stable"
TEMPLATES="$(cygpath -u "$TEMPLATES" 2>/dev/null || echo "$TEMPLATES")"
if [[ ! -f "$TEMPLATES/windows_release_x86_64.exe" ]]; then
  echo "[export] Godot export templates not found in $TEMPLATES" >&2
  exit 2
fi

if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE/game"
  mkdir -p "$DEST"
  rm -rf "$DEST/export"
  (cd "$PROJECT" && tar --exclude=./.godot --exclude=./export -cf - .) | (cd "$DEST" && tar -xf -)
  PROJECT="$DEST"
fi

mkdir -p "$OUT_DIR"
# A stale exe from an earlier export must not pass for this one.
rm -f "$OUT_DIR/MapleSurvivors.exe" "$OUT_DIR/MapleSurvivors.console.exe" "$OUT_DIR/MapleSurvivors.pck"
OUT_EXE="$(cygpath -m "$OUT_DIR/MapleSurvivors.exe" 2>/dev/null || echo "$OUT_DIR/MapleSurvivors.exe")"
GODOT_CMD=(bash "$REPO/scripts/godot.sh")
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
echo "[export] $MODE \"Windows Desktop\" -> $OUT_EXE" >&2
set +e
"${GODOT_CMD[@]}" --headless --path "$PROJECT" "$MODE" "Windows Desktop" "$OUT_EXE" 2>&1 | { grep -vE "$FILTER" || true; }
RC="${PIPESTATUS[0]}"
set -e
[[ "$RC" == "0" ]] || { echo "[export] Godot's export failed (exit $RC)" >&2; exit 1; }
[[ -f "$OUT_DIR/MapleSurvivors.exe" ]] || { echo "[export] the export produced no exe" >&2; exit 1; }

# Licence notices for the engine.
cp "$REPO/THIRD_PARTY_NOTICES.md" "$OUT_DIR/"
# The bundled Arimo font is inside the exe's pck; its licence (SIL OFL 1.1) travels beside it.
cp "$PROJECT/assets/fonts/arimo/OFL.txt" "$OUT_DIR/ARIMO_OFL.txt"
GODOT_LIC="$OUT_DIR/GODOT_LICENSES.txt"
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --script res://tools/write_licenses.gd -- \
  "$(cygpath -m "$GODOT_LIC" 2>/dev/null || echo "$GODOT_LIC")" >/dev/null 2>&1 || true
[[ -s "$GODOT_LIC" ]] || { echo "[export] could not write $GODOT_LIC" >&2; exit 1; }

(cd "$REPO/tools/wzimport" && cargo build --release --quiet)
BIN="$REPO/tools/wzimport/target/release/wzimport"
[[ -f "$BIN.exe" ]] && BIN="$BIN.exe"
cp "$BIN" "$OUT_DIR/"

# Licence notices for the importer's crates: every LICENSE*/COPYING* file of every package in the lock file.
CRATE_LIC="$OUT_DIR/WZIMPORT_LICENSES.txt"
{
  echo "Licence files of the Rust crates in tools/wzimport/Cargo.lock (compiled into wzimport.exe; see THIRD_PARTY_NOTICES.md)."
  (cd "$REPO/tools/wzimport" && cargo metadata --format-version 1 --offline 2>/dev/null) \
    | grep -o '"manifest_path":"[^"]*"' | sed -e 's/^"manifest_path":"//' -e 's/"$//' -e 's#\\\\#/#g' \
    | while read -r manifest; do
        dir="$(dirname "$manifest")"
        [[ "$dir" == */tools/wzimport ]] && continue
        for f in "$dir"/LICENSE* "$dir"/LICENCE* "$dir"/COPYING* "$dir"/UNLICENSE*; do
          [[ -f "$f" ]] || continue
          printf '\n===== %s: %s =====\n\n' "$(basename "$dir")" "$(basename "$f")"
          cat "$f"
        done
      done
} > "$CRATE_LIC"
grep -q '^=====' "$CRATE_LIC" || { echo "[export] found no crate licence files for $CRATE_LIC" >&2; exit 1; }
echo "[export] done:" >&2
ls -l "$OUT_DIR" >&2
