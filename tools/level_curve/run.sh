#!/usr/bin/env bash
# Regenerates game/data/survivor/level_curve.json from the owner's v83 Mob.wz.
#   bash tools/level_curve/run.sh "<the owner's v83 folder>" [YYYY-MM-DD]
# Needs Rust (builds tools/wzimport) and Node. The folder is never written anywhere; only numbers reach the output.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
wz="${1:-${MAPLE_WZ_ROOT:-}}"
date="${2:-}"
if [[ -z "$wz" ]]; then
	echo "usage: tools/level_curve/run.sh <v83 folder> [YYYY-MM-DD]" >&2
	exit 2
fi
export PATH="$HOME/.cargo/bin:$PATH"
(cd "$root/tools/wzimport" && cargo build --release --quiet)
dump="$(mktemp)"
trap 'rm -f "$dump"' EXIT
"$root/tools/wzimport/target/release/wzimport" dump --wz "$wz" Mob.wz --imgs 2 > "$dump"
args=(--dump="$dump" --out="$root/game/data/survivor/level_curve.json")
[[ -n "$date" ]] && args+=(--date="$date")
node "$here/generate.mjs" "${args[@]}"
