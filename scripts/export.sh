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
#   bash scripts/export.sh --web            # the web build -> game/export/web/ (see below)
#   ISOLATE=<name> bash scripts/export.sh   # import/export from a private mirror (_scratch/godot_runs/<name>/game)
#   EXPORT_DIR=<abs dir> bash scripts/export.sh   # write the build somewhere else than game/export (game/export/web)
#
# --web exports the "Web" preset (single-threaded, GL Compatibility, shell web/index.html) and completes the site
# beside index.html: the rest of the web shell (shell.css, shell.js, lib.js, idbfs.js, import_worker.js, and the
# branding: title.jpg, the favicons and site.webmanifest; web/dev/ is never copied), asset_manifest.json, the wasm importer (wzimport.js + wzimport_bg.wasm, built by scripts/build_wasm.sh
# into WASM_DIR, default _scratch/wasm) and the licence files linked from the shell: GODOT_LICENSES.txt,
# WZIMPORT_LICENSES.txt (including the wasm-only crates), THIRD_PARTY_NOTICES.md and ARIMO_OFL.txt. It ends with
# scripts/check_web_artifact.sh, which fails the export if any WZ data or cache-shaped file is in the folder.
# Serve the result locally with `node web/dev/serve.mjs game/export/web` (http://127.0.0.1:8060/).
# --web needs the web_nothreads_* templates (`bash scripts/godot_templates.sh install-web`), Rust with the
# wasm32-unknown-unknown target and the matching wasm-bindgen-cli (docs/ASSET_PIPELINE.md 2.2).
#
# The script fails when Godot's export fails: the previous output is deleted first and Godot's exit status is checked.
# The Windows build needs the Godot export templates for the pinned version (see scripts/godot_templates.sh dir for
# where they go; install them from the Godot editor or the official templates archive) and Rust/cargo for wzimport.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"
WEB=0
MODE="--export-release"
for arg in "$@"; do
  case "$arg" in
    --web) WEB=1 ;;
    --debug) MODE="--export-debug" ;;
    *) echo "usage: $0 [--web] [--debug]" >&2; exit 2 ;;
  esac
done
if [[ "$WEB" == 1 ]]; then OUT_DIR="${EXPORT_DIR:-$REPO/game/export/web}"; else OUT_DIR="${EXPORT_DIR:-$REPO/game/export}"; fi
FILTER='^(\[ *[0-9]+% \]|Godot Engine v|WARNING: .*leaked|   at: |Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: .* resources still in use)'

TEMPLATES="$(bash "$REPO/scripts/godot_templates.sh" dir)"
if [[ "$WEB" == 1 ]]; then
  for t in web_nothreads_debug.zip web_nothreads_release.zip; do
    [[ -f "$TEMPLATES/$t" ]] || { echo "[export] missing Godot web template $TEMPLATES/$t (bash scripts/godot_templates.sh install-web)" >&2; exit 2; }
  done
elif [[ ! -f "$TEMPLATES/windows_release_x86_64.exe" ]]; then
  echo "[export] Godot export templates not found in $TEMPLATES" >&2
  exit 2
fi

if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE/game"
  mkdir -p "$DEST"
  rm -rf "$DEST/export"
  (cd "$PROJECT" && tar --exclude=./.godot --exclude=./export -cf - .) | (cd "$DEST" && tar -xf -)
  if [[ "$WEB" == 1 ]]; then
    # The Web preset's shell is res://../web/index.html, i.e. web/ beside game/ (also in the mirror).
    rm -rf "$DEST/../web"
    mkdir -p "$DEST/../web"
    (cd "$REPO/web" && tar --exclude=./dev -cf - .) | (cd "$DEST/../web" && tar -xf -)
  fi
  PROJECT="$DEST"
fi

GODOT_CMD=(bash "$REPO/scripts/godot.sh")

# Licence notices for the engine (written by the engine itself).
write_godot_licenses() {
  local out="$1"
  "${GODOT_CMD[@]}" --headless --path "$PROJECT" --script res://tools/write_licenses.gd -- \
    "$(cygpath -m "$out" 2>/dev/null || echo "$out")" >/dev/null 2>&1 || true
  [[ -s "$out" ]] || { echo "[export] could not write $out" >&2; exit 1; }
}

# Licence notices for the importer's crates: every LICENSE*/COPYING* file of every package in the lock file, for all
# targets (so the wasm-only crates are in it). $1 = output file, $2 = what the crates are compiled into.
write_crate_licenses() {
  local out="$1" into="$2"
  {
    echo "Licence files of the Rust crates in tools/wzimport/Cargo.lock (compiled into $into; see THIRD_PARTY_NOTICES.md)."
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
  } > "$out"
  grep -q '^=====' "$out" || { echo "[export] found no crate licence files for $out (cargo fetch --locked first?)" >&2; exit 1; }
}

if [[ "$WEB" == 1 ]]; then
  mkdir -p "$OUT_DIR"
  # A stale build must not pass for this one: clear Godot's files and everything this script copies in.
  rm -rf "$OUT_DIR"/index.* "$OUT_DIR"/shell.* "$OUT_DIR"/lib.js "$OUT_DIR"/idbfs.js "$OUT_DIR"/import_worker.js     "$OUT_DIR"/title.jpg "$OUT_DIR"/favicon* "$OUT_DIR"/apple-touch-icon.png "$OUT_DIR"/android-chrome-*     "$OUT_DIR"/site.webmanifest \
    "$OUT_DIR"/wzimport* "$OUT_DIR"/asset_manifest.json "$OUT_DIR"/*LICENSES.txt "$OUT_DIR"/ARIMO_OFL.txt \
    "$OUT_DIR"/THIRD_PARTY_NOTICES.md
  OUT_HTML="$(cygpath -m "$OUT_DIR/index.html" 2>/dev/null || echo "$OUT_DIR/index.html")"
  "${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
  echo "[export] $MODE \"Web\" -> $OUT_HTML" >&2
  set +e
  "${GODOT_CMD[@]}" --headless --path "$PROJECT" "$MODE" "Web" "$OUT_HTML" 2>&1 | { grep -vE "$FILTER" || true; }
  RC="${PIPESTATUS[0]}"
  set -e
  [[ "$RC" == "0" ]] || { echo "[export] Godot's export failed (exit $RC)" >&2; exit 1; }
  for f in index.html index.js index.wasm index.pck; do
    [[ -s "$OUT_DIR/$f" ]] || { echo "[export] the web export produced no $f" >&2; exit 1; }
  done

  # The rest of the web shell (Godot only processes index.html) and the same-origin manifest the shell checks.
  for f in shell.css shell.js lib.js idbfs.js import_worker.js title.jpg favicon.ico favicon-16x16.png     favicon-32x32.png apple-touch-icon.png android-chrome-192x192.png android-chrome-512x512.png site.webmanifest; do
    cp "$REPO/web/$f" "$OUT_DIR/$f"
  done
  cp "$REPO/game/data/asset_manifest.json" "$OUT_DIR/asset_manifest.json"

  # The wasm importer (never committed; built here).
  WASM_DIR="${WASM_DIR:-$REPO/_scratch/wasm}"
  rm -f "$WASM_DIR/wzimport.js" "$WASM_DIR/wzimport_bg.wasm"
  bash "$REPO/scripts/build_wasm.sh" "$WASM_DIR" >&2
  for f in wzimport.js wzimport_bg.wasm; do
    [[ -s "$WASM_DIR/$f" ]] || { echo "[export] the wasm build produced no $f" >&2; exit 1; }
    cp "$WASM_DIR/$f" "$OUT_DIR/$f"
  done

  # Licences, linked from the shell.
  cp "$REPO/THIRD_PARTY_NOTICES.md" "$OUT_DIR/"
  cp "$REPO/game/assets/fonts/arimo/OFL.txt" "$OUT_DIR/ARIMO_OFL.txt"
  write_godot_licenses "$OUT_DIR/GODOT_LICENSES.txt"
  write_crate_licenses "$OUT_DIR/WZIMPORT_LICENSES.txt" "wzimport_bg.wasm, the wasm importer; includes the wasm-only crates"
  grep -q '^===== wasm-bindgen-' "$OUT_DIR/WZIMPORT_LICENSES.txt" \
    || { echo "[export] WZIMPORT_LICENSES.txt lacks the wasm-only crates (wasm-bindgen)" >&2; exit 1; }

  bash "$REPO/scripts/check_web_artifact.sh" "$OUT_DIR"
  echo "[export] done:" >&2
  ls -l "$OUT_DIR" >&2
  exit 0
fi

mkdir -p "$OUT_DIR"
# A stale exe from an earlier export must not pass for this one.
rm -f "$OUT_DIR/MapleSurvivors.exe" "$OUT_DIR/MapleSurvivors.console.exe" "$OUT_DIR/MapleSurvivors.pck"
OUT_EXE="$(cygpath -m "$OUT_DIR/MapleSurvivors.exe" 2>/dev/null || echo "$OUT_DIR/MapleSurvivors.exe")"
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
echo "[export] $MODE \"Windows Desktop\" -> $OUT_EXE" >&2
set +e
"${GODOT_CMD[@]}" --headless --path "$PROJECT" "$MODE" "Windows Desktop" "$OUT_EXE" 2>&1 | { grep -vE "$FILTER" || true; }
RC="${PIPESTATUS[0]}"
set -e
[[ "$RC" == "0" ]] || { echo "[export] Godot's export failed (exit $RC)" >&2; exit 1; }
[[ -f "$OUT_DIR/MapleSurvivors.exe" ]] || { echo "[export] the export produced no exe" >&2; exit 1; }

cp "$REPO/THIRD_PARTY_NOTICES.md" "$OUT_DIR/"
# The bundled Arimo font is inside the exe's pck; its licence (SIL OFL 1.1) travels beside it.
cp "$PROJECT/assets/fonts/arimo/OFL.txt" "$OUT_DIR/ARIMO_OFL.txt"
write_godot_licenses "$OUT_DIR/GODOT_LICENSES.txt"

(cd "$REPO/tools/wzimport" && cargo build --release --quiet)
BIN="$REPO/tools/wzimport/target/release/wzimport"
[[ -f "$BIN.exe" ]] && BIN="$BIN.exe"
cp "$BIN" "$OUT_DIR/"
write_crate_licenses "$OUT_DIR/WZIMPORT_LICENSES.txt" "wzimport.exe"
echo "[export] done:" >&2
ls -l "$OUT_DIR" >&2
