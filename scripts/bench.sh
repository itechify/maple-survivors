#!/usr/bin/env bash
# Headless sim benchmarks, microseconds per 1/60 s tick:
#   world: MobSwarm + SpatialHash + targeting queries (game/tools/bench_world.gd)
#   run:   a whole RunWorld.step with projectiles, drops, spawning and skills (game/tools/bench_run.gd)
#
#   bash scripts/bench.sh                   # both, at 100 300 600 1000 mobs; synthetic map + 104040000 with the cache
#   bash scripts/bench.sh run               # only the RunWorld benchmark
#   bash scripts/bench.sh world 300 2000    # one benchmark, custom mob counts
#   bash scripts/bench.sh 300 2000          # both, custom mob counts
#   ISOLATE=<name> bash scripts/bench.sh    # run in a private mirror (_scratch/godot_runs/<name>/game), like test.sh
#
# Results belong in docs/IMPLEMENTATION_PLAN.md "Performance log".
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"

MODE="all"
if [[ "${1:-}" == "world" || "${1:-}" == "run" ]]; then
  MODE="$1"
  shift
fi

if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE/game"
  mkdir -p "$DEST"
  (cd "$PROJECT" && tar --exclude=./.godot -cf - .) | (cd "$DEST" && tar -xf -)
  (cd "$DEST" && find . -type f ! -path './.godot/*' | while read -r f; do [[ -e "$PROJECT/$f" ]] || rm -f "$f"; done)
  PROJECT="$DEST"
fi

GODOT_CMD=(bash "$REPO/scripts/godot.sh")
# An import pass registers the class_name scripts the benchmarks use.
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true

STATUS=0
run_tool() {
  "${GODOT_CMD[@]}" --headless --path "$PROJECT" --script "res://tools/$1.gd" -- "${@:2}" 2>&1 \
    | grep -vE '^(Godot Engine v|WARNING: .*leaked|   at: |Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: .* resources still in use)'
  local rc="${PIPESTATUS[0]}"
  [[ "$rc" == "0" ]] || STATUS="$rc"
}

if [[ "$MODE" == "all" || "$MODE" == "world" ]]; then
  run_tool bench_world "$@"
fi
if [[ "$MODE" == "all" || "$MODE" == "run" ]]; then
  run_tool bench_run "$@"
fi
exit "$STATUS"
