#!/usr/bin/env bash
# Where Godot's export templates live, and a one-command install of the two the web build needs.
#
#   bash scripts/godot_templates.sh dir          # print the templates folder for the pinned version
#   bash scripts/godot_templates.sh install-web  # download the official templates archive (1.2 GB), check its SHA-512
#                                                # against the release's SHA512-SUMS.txt and unpack web_nothreads_debug.zip
#                                                # and web_nothreads_release.zip (+ version.txt) into that folder
#
# The folder is %APPDATA%/Godot/export_templates/<version>.stable on Windows, ~/.local/share/godot/export_templates/...
# on Linux ($XDG_DATA_HOME honoured) and ~/Library/Application Support/Godot/export_templates/... on macOS: where the
# editor looks. scripts/export.sh --web calls `dir`; .github/workflows/pages.yml calls `install-web` (cached by version).
# The archive comes from the official Godot release page, the same pinned source as scripts/godot.sh (developer tooling;
# nothing in game/ or the shipped web build reaches the network for this).
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"

templates_dir() {
  case "$(uname -s)" in
    Linux) echo "${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/${GODOT_VERSION}.stable" ;;
    Darwin) echo "$HOME/Library/Application Support/Godot/export_templates/${GODOT_VERSION}.stable" ;;
    *)
      local base="${APPDATA:-$HOME/AppData/Roaming}"
      echo "$(cygpath -u "$base" 2>/dev/null || echo "$base")/Godot/export_templates/${GODOT_VERSION}.stable"
      ;;
  esac
}

install_web() {
  local dir tmp tpz base want got
  dir="$(templates_dir)"
  if [[ -s "$dir/web_nothreads_debug.zip" && -s "$dir/web_nothreads_release.zip" ]]; then
    echo "[templates] web templates already in $dir" >&2
    return 0
  fi
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN
  tpz="Godot_v${GODOT_VERSION}-stable_export_templates.tpz"
  base="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"
  echo "[templates] downloading $tpz (about 1.2 GB) ..." >&2
  curl -sSfL --retry 3 -o "$tmp/$tpz" "$base/$tpz"
  curl -sSfL --retry 3 -o "$tmp/SHA512-SUMS.txt" "$base/SHA512-SUMS.txt"
  want="$(grep -F " $tpz" "$tmp/SHA512-SUMS.txt" | awk '{print $1}')"
  [[ -n "$want" ]] || { echo "[templates] no checksum for $tpz in SHA512-SUMS.txt" >&2; return 1; }
  got="$(sha512sum "$tmp/$tpz" | awk '{print $1}')"
  [[ "$got" == "$want" ]] || { echo "[templates] SHA-512 mismatch for $tpz" >&2; return 1; }
  mkdir -p "$dir"
  unzip -o -j -q "$tmp/$tpz" templates/web_nothreads_debug.zip templates/web_nothreads_release.zip templates/version.txt -d "$dir"
  echo "[templates] installed web_nothreads_{debug,release}.zip in $dir" >&2
}

case "${1:-}" in
  dir) templates_dir ;;
  install-web) install_web ;;
  *) echo "usage: $0 dir | install-web" >&2; exit 2 ;;
esac
