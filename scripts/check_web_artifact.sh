#!/usr/bin/env bash
# Guard for the web build (scripts/export.sh --web, .github/workflows/pages.yml): the folder that becomes the GitHub
# Pages site must hold the game and the web shell only. No MapleStory data and nothing shaped like the asset cache may
# be in it. Exits 1 and lists every offender, or when a file the site needs is missing.
#
#   bash scripts/check_web_artifact.sh game/export/web
#
# Rejected (case-insensitive): *.wz, *.img (files or folders), *.img.json, atlas pages *.<N>.png, *.mp3, *.wav,
# cache.json, an asset_cache folder, and any file that begins with the WZ magic bytes "PKG1" whatever its name.
# Only the exact top-level files emitted by export.sh --web / Godot 4.7.2 may ship. This checks loose files and
# signatures, not the contents/provenance of the Godot PCK or approved branding files.
# Tested by web/dev/test/artifact_check.test.mjs (planted files of each shape).
set -euo pipefail
DIR="${1:-}"
[[ -n "$DIR" && -d "$DIR" ]] || { echo "[check_web_artifact] usage: $0 <web export folder> (not a folder: '$DIR')" >&2; exit 2; }

BAD=0
fail() { echo "[check_web_artifact] FORBIDDEN: $1" >&2; BAD=1; }

# Keep this explicit: extension globs would let renamed decoded art or archive backups through.
ALLOWED=(index.html index.js index.wasm index.pck index.png index.icon.png index.apple-touch-icon.png
  index.audio.worklet.js index.audio.position.worklet.js shell.js shell.css lib.js idbfs.js import_worker.js
  title.jpg favicon.ico favicon-16x16.png favicon-32x32.png apple-touch-icon.png android-chrome-192x192.png
  android-chrome-512x512.png site.webmanifest wzimport.js wzimport_bg.wasm asset_manifest.json
  GODOT_LICENSES.txt WZIMPORT_LICENSES.txt THIRD_PARTY_NOTICES.md ARIMO_OFL.txt)
while IFS= read -r -d '' f; do
  relative="${f#"$DIR"/}"
  allowed=0
  for name in "${ALLOWED[@]}"; do [[ "$relative" != "$name" ]] || { allowed=1; break; }; done
  if [[ "$allowed" == 0 || ! -f "$f" || -L "$f" ]]; then fail "$relative (not an approved shipping file)"; fi
done < <(find "$DIR" -mindepth 1 -print0)

while IFS= read -r f; do
  fail "${f#"$DIR"/}"
done < <(find "$DIR" \( -iname '*.wz' -o -iname '*.img' -o -iname '*.img.json' -o -iname '*.mp3' -o -iname '*.wav' \
  -o -iname 'cache.json' -o -iname 'asset_cache' -o -iregex '.*\.[0-9]+\.png' \) | sort)

# WZ archives start with the ASCII bytes "PKG1"; a renamed one must not slip through.
while IFS= read -r f; do
  magic="$(od -An -tx1 -N6 "$f")"
  magic="${magic//[[:space:]]/}"
  case "$magic" in
    504b4731*) fail "${f#"$DIR"/} (starts with the WZ signature PKG1)" ;;
    504b0304*|504b0506*|504b0708*|1f8b*|377abcaf271c*|52617221*) fail "${f#"$DIR"/} (archive signature)" ;;
  esac
done < <(find "$DIR" -type f | sort)

for need in index.html index.js index.wasm index.pck shell.js shell.css lib.js idbfs.js import_worker.js title.jpg \
  favicon.ico site.webmanifest \
  wzimport.js wzimport_bg.wasm asset_manifest.json GODOT_LICENSES.txt WZIMPORT_LICENSES.txt THIRD_PARTY_NOTICES.md ARIMO_OFL.txt; do
  [[ -s "$DIR/$need" ]] || { echo "[check_web_artifact] MISSING: $need" >&2; BAD=1; }
done

[[ "$BAD" == "0" ]] || { echo "[check_web_artifact] FAILED for $DIR" >&2; exit 1; }
echo "[check_web_artifact] ok: $DIR ($(find "$DIR" -type f | wc -l | tr -d ' ') files, no WZ data or cache-shaped files)" >&2
