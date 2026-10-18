#!/usr/bin/env bash
# Build the sequential worker importer + ES module glue; generated output is never committed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/_scratch/wasm}"
if [[ $# -gt 1 ]]; then echo "Usage: $0 [output-directory]" >&2; exit 2; fi
MANIFEST="$ROOT/tools/wzimport/Cargo.toml"
VERSION="$(awk '/^name = "wasm-bindgen"$/ { found=1; next } found && /^version = / { gsub(/"/, "", $3); print $3; exit }' "$ROOT/tools/wzimport/Cargo.lock")"
if ! rustup target list --installed | grep -qx wasm32-unknown-unknown; then
  echo 'Install the wasm target: rustup target add wasm32-unknown-unknown' >&2; exit 1
fi
if ! command -v wasm-bindgen >/dev/null || [[ "$(wasm-bindgen --version)" != "wasm-bindgen $VERSION" ]]; then
  echo "Install matching glue tooling: cargo install wasm-bindgen-cli --version $VERSION --locked" >&2; exit 1
fi
TARGET="${CARGO_TARGET_DIR:-$ROOT/tools/wzimport/target}"
cargo build --locked --manifest-path "$MANIFEST" --target-dir "$TARGET" --release --lib --target wasm32-unknown-unknown --no-default-features
mkdir -p "$OUT"
wasm-bindgen "$TARGET/wasm32-unknown-unknown/release/wzimport.wasm" --target web --out-name wzimport --out-dir "$OUT"
echo "Wasm importer: $OUT/wzimport.js (+ wzimport_bg.wasm and TypeScript declarations)"
