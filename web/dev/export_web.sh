#!/usr/bin/env bash
# DEV ONLY (web build spike #131; `scripts/export.sh --web` from #135 replaces it). Exports the "Web" preset of
# game/export_presets.cfg (single-threaded, GL Compatibility, shell web/index.html) into a folder.
#
#   bash web/dev/export_web.sh                       # release export -> game/export/web/
#   bash web/dev/export_web.sh --debug               # debug export (prints script errors in the browser console)
#   EXPORT_DIR=<abs dir> bash web/dev/export_web.sh  # write the build somewhere else
#   ISOLATE=<name> bash web/dev/export_web.sh        # export from a private mirror (_scratch/godot_runs/<name>/game)
#   WASM_DIR=<dir> bash web/dev/export_web.sh        # wasm importer build to place beside index.html (default
#                                                    # _scratch/wasm/, made by `bash scripts/build_wasm.sh`)
#
# Besides Godot's own files this copies the rest of the web shell beside index.html (Godot only processes the HTML shell
# itself): web/{shell.css,shell.js,lib.js,idbfs.js,import_worker.js}, game/data/asset_manifest.json and the wasm importer
# (wzimport.js, wzimport_bg.wasm). `scripts/export.sh --web` (#135) will own this for releases; web/dev/ is not copied.
#
# Needs the official Godot web templates web_nothreads_debug.zip / web_nothreads_release.zip in
# %APPDATA%/Godot/export_templates/<version>.stable/ (see docs/ARCHITECTURE.md "Web build" for the install command).
# The preset's shell path is res://../web/index.html, i.e. web/index.html beside game/; a mirror gets a copy of web/
# beside its game/ for the same reason. Serve the result with `node web/dev/serve.mjs <export dir>`.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROJECT="$REPO/game"
OUT_DIR="${EXPORT_DIR:-$REPO/game/export/web}"
MODE="--export-release"
[[ "${1:-}" == "--debug" ]] && MODE="--export-debug"
FILTER='^(\[ *[0-9]+% \]|Godot Engine v|WARNING: .*leaked|   at: |Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: .* resources still in use)'

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
TEMPLATES="${APPDATA:-$HOME/.local/share}/Godot/export_templates/${GODOT_VERSION}.stable"
TEMPLATES="$(cygpath -u "$TEMPLATES" 2>/dev/null || echo "$TEMPLATES")"
for t in web_nothreads_debug.zip web_nothreads_release.zip; do
  [[ -f "$TEMPLATES/$t" ]] || { echo "[export_web] missing Godot web template $TEMPLATES/$t" >&2; exit 2; }
done

if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE/game"
  mkdir -p "$DEST" "$DEST/../web"
  rm -rf "$DEST/export"
  (cd "$PROJECT" && tar --exclude=./.godot --exclude=./export -cf - .) | (cd "$DEST" && tar -xf -)
  cp "$REPO/web/index.html" "$DEST/../web/index.html"
  PROJECT="$DEST"
fi

mkdir -p "$OUT_DIR"
# A stale build must not pass for this one.
rm -f "$OUT_DIR"/index.*
OUT_HTML="$(cygpath -m "$OUT_DIR/index.html" 2>/dev/null || echo "$OUT_DIR/index.html")"
GODOT_CMD=(bash "$REPO/scripts/godot.sh")
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
echo "[export_web] $MODE \"Web\" -> $OUT_HTML" >&2
set +e
"${GODOT_CMD[@]}" --headless --path "$PROJECT" "$MODE" "Web" "$OUT_HTML" 2>&1 | { grep -vE "$FILTER" || true; }
RC="${PIPESTATUS[0]}"
set -e
[[ "$RC" == "0" ]] || { echo "[export_web] Godot's export failed (exit $RC)" >&2; exit 1; }
for f in index.html index.js index.wasm index.pck; do
  [[ -s "$OUT_DIR/$f" ]] || { echo "[export_web] the export produced no $f" >&2; exit 1; }
done
# The rest of the shell (see the header). The wasm importer is optional here so a plain export still works.
for f in shell.css shell.js lib.js idbfs.js import_worker.js; do
  cp "$REPO/web/$f" "$OUT_DIR/$f"
done
cp "$REPO/game/data/asset_manifest.json" "$OUT_DIR/asset_manifest.json"
WASM_DIR="${WASM_DIR:-$REPO/_scratch/wasm}"
if [[ -f "$WASM_DIR/wzimport.js" && -f "$WASM_DIR/wzimport_bg.wasm" ]]; then
  cp "$WASM_DIR/wzimport.js" "$WASM_DIR/wzimport_bg.wasm" "$OUT_DIR/"
else
  echo "[export_web] no wasm importer in $WASM_DIR (run scripts/build_wasm.sh): the import screen will not work" >&2
fi
echo "[export_web] done:" >&2
ls -l "$OUT_DIR" >&2
