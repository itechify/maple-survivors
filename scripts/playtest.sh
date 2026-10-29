#!/usr/bin/env bash
# Scripted playtest: launches the game windowed straight into a run played by the autoplay bot (BotInput moves,
# climbs and picks cards; no windows open), saves screenshots + summary.json into an evidence folder, quits, and prints
# the summary (outcome, levels per minute, frame-time percentiles, max alive mobs, missing assets).
#
#   bash scripts/playtest.sh                                  # henesys, seed 2026, speed 4, through the boss finale
#   bash scripts/playtest.sh --seed=7 --speed=1 --minutes=3   # 3 minutes in real time
#   bash scripts/playtest.sh --warp=600 --minutes=13 --speed=1 --vsync=off   # fast-forward to 10:00 (nothing drawn),
#                                                             # then 3 real-time minutes with 200+ mobs, uncapped FPS
#   bash scripts/playtest.sh --stage=ellinia --out=evidence/mytest
#   bash scripts/playtest.sh --warp=600 --minutes=13 --require-window --min-frames-100=120 --min-frames-200=60
#
# Options (all optional): --stage=<key> (stages.json, default henesys), --seed=<n> (2026), --speed=<k> sim ticks
# per 60 Hz frame (4), --minutes=<m> absolute run time to stop at (30; a death or clear ends earlier), --shot-every=<s> run
# seconds between screenshots (60), --out=<dir> (default evidence/playtest/<stage>_s<seed>_x<speed>_<time>), --warp=<s>,
# --job=<id> (the character's job, e.g. 212, 112 for Hero, 222 for the I/L Arch Mage or 312 for the Bowmaster (give it a bow: --character=game/tests/fixtures/characters/bowmaster_t2.json); the game refuses one this build cannot offer; --branch=<id> is the deprecated alias), --vsync=off, --name=<character name>, --window-autopick=<s> (windows open and answer themselves instead of autopick).
# --account=<abs JSON> (an account for the round, spec #34: owned cash items, worn cash equipment, pet, ALERT levels; see
# scripts/balance.sh and game/scripts/core/account_file.gd; summary.json names the file).
# Map fields: summary.json root and nested summary carry map_times (reached-map entry seconds, starting [0]) and
# ended_map {index, id} (zero-based index, original v83 id). Intermediate transfers take map_N_cleared/fade/black
# and map_N_enter PNGs; N is one-based, and the final map also gets map_3_cleared. See AGENTS.md for all shot names.
# Keys henesys/ellinia/sleepywood accept henesys_hg1/tree_that_grew_1/dark_cave aliases; --character works with either.
# --require-window opts into workload qualification: the requested --warp (default 0) must be reached, ticks must be
# positive, and --min-frames-100=<N> / --min-frames-200=<N> frames must have 100+/200+ mobs (defaults 1 each).
# A zero minimum disables that density check; at least one must be positive. Failure exits non-zero with UNQUALIFIED.
# This checks coverage, not performance budgets; ordinary death playtests keep their existing success behavior.
# Anything else is passed to the game unchanged. Screenshots of the running game stay in evidence/ (gitignored).
#
# Frame times: the game caps the frame rate at the display's refresh rate (Settings / GameSettings.apply_frame_cap), so
# frame_ms without --vsync=off is the cap (16.7 ms at 60 Hz); pass --vsync=off for performance measurements.
# Output files: t<s>.png every --shot-every, levelup_N / cast_<skill> (each skill's first cast) / hit_first / death_* / clear / final.png, summary.json
# (RunScene.perf_summary: frame_ms p50/p95/p99/max, frame_work_us, sim_us_per_tick, max_alive, level_by_minute, ...).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

STAGE="henesys"
SEED="2026"
SPEED="4"
MINUTES="30"
SHOT_EVERY="60"
OUT=""
AUTOPICK="--autopick"
REQUIRE_WINDOW=0
WARP="0"
MIN_FRAMES_100="1"
MIN_FRAMES_200="1"
EXTRA=()
for a in "$@"; do
  case "$a" in
    --job=*|--branch=*)
      [[ "$a" == --branch=* ]] && echo "playtest.sh: --branch is deprecated: use --job=<id>" >&2
      JOB_ID="${a#--*=}"
      [[ "$JOB_ID" =~ ^[0-9]+$ ]] || { echo "--job must be a job id (e.g. 212)" >&2; exit 2; }
      EXTRA+=("--job=$JOB_ID") ;;
    --stage=*) STAGE="${a#--stage=}" ;;
    --seed=*) SEED="${a#--seed=}" ;;
    --speed=*) SPEED="${a#--speed=}" ;;
    --minutes=*) MINUTES="${a#--minutes=}" ;;
    --shot-every=*) SHOT_EVERY="${a#--shot-every=}" ;;
    --out=*) OUT="${a#--out=}" ;;
    --warp=*) WARP="${a#--warp=}"; EXTRA+=("$a") ;;
    --require-window) REQUIRE_WINDOW=1 ;;
    --min-frames-100=*) MIN_FRAMES_100="${a#--min-frames-100=}" ;;
    --min-frames-200=*) MIN_FRAMES_200="${a#--min-frames-200=}" ;;
    --window-autopick=*) AUTOPICK=""; EXTRA+=("$a") ;;
    *) EXTRA+=("$a") ;;
  esac
done
if [[ "$REQUIRE_WINDOW" == 1 ]]; then
  [[ "$MIN_FRAMES_100" =~ ^[0-9]+$ && "$MIN_FRAMES_200" =~ ^[0-9]+$ && "$WARP" =~ ^[0-9]+([.][0-9]+)?$ ]] || {
    echo "[playtest] qualification needs non-negative integer frame minima and a non-negative numeric warp" >&2; exit 2;
  }
  [[ "$MIN_FRAMES_100" =~ [1-9] || "$MIN_FRAMES_200" =~ [1-9] ]] || {
    echo "[playtest] qualification needs at least one positive density minimum" >&2; exit 2;
  }
fi
if [[ -z "$OUT" ]]; then
  OUT="$REPO/evidence/playtest/${STAGE}_s${SEED}_x${SPEED}_$(date +%Y%m%d_%H%M%S)"
elif [[ "$OUT" != /* && "$OUT" != ?:* ]]; then
  OUT="$REPO/$OUT"
fi
mkdir -p "$OUT"
OUT_ABS="$(cygpath -m "$OUT" 2>/dev/null || echo "$OUT")"
QUIT_AFTER="$(awk -v m="$MINUTES" 'BEGIN { printf "%g", m * 60 }')"

echo "[playtest] $STAGE seed $SEED speed x$SPEED until $QUIT_AFTER s -> $OUT_ABS" >&2
rm -f "$OUT/summary.json"
set +e
bash "$REPO/scripts/run.sh" -- --run="$STAGE" --seed="$SEED" --autoplay $AUTOPICK --speed="$SPEED" \
  --shots="$OUT_ABS" --shot-every="$SHOT_EVERY" --quit-after="$QUIT_AFTER" --perf ${EXTRA[@]+"${EXTRA[@]}"} \
  > "$OUT/game.log" 2>&1
RC=$?
set -e
if [[ ! -s "$OUT/summary.json" ]]; then
  echo "[playtest] no summary.json (exit $RC); last log lines:" >&2
  tail -20 "$OUT/game.log" >&2
  exit 1
fi
cat "$OUT/summary.json"
echo
if [[ "$REQUIRE_WINDOW" == 1 ]]; then
  if [[ "$RC" != 0 ]]; then
    echo "[playtest] UNQUALIFIED: game exited $RC" >&2
    exit 1
  fi
  bash "$REPO/scripts/run.sh" --headless --script res://tools/qualify_playtest.gd -- \
    --summary="$OUT_ABS/summary.json" --warp="$WARP" \
    --min-frames-100="$MIN_FRAMES_100" --min-frames-200="$MIN_FRAMES_200"
fi
# One-line digest (no JSON tool needed).
awk 'BEGIN { RS = "\0" } {
  gsub(/[\r\n\t ]+/, " ")
  st = $0; sub(/.*"state": "/, "", st); sub(/".*/, "", st)
  lv = $0; sub(/.*"summary": \{/, "", lv); sub(/.*"level": /, "", lv); sub(/[,}].*/, "", lv)
  fm = $0; sub(/.*"frame_ms": \{/, "", fm); sub(/\}.*/, "", fm)
  ma = $0; sub(/.*"max_alive": /, "", ma); sub(/[,}].*/, "", ma)
  print "[playtest] state " st ", level " lv ", max alive " ma ", frame_ms {" fm "}"
}' "$OUT/summary.json" >&2
echo "[playtest] screenshots and summary: $OUT_ABS" >&2
