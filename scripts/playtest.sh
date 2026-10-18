#!/usr/bin/env bash
# Scripted playtest: launches the game windowed straight into a run played by the autoplay bot (BotInput moves,
# climbs and picks cards; no windows open), saves screenshots + summary.json into an evidence folder, quits, and prints
# the summary (outcome, levels per minute, frame-time percentiles, max alive mobs, missing assets).
#
#   bash scripts/playtest.sh                                  # henesys_hg1, seed 2026, speed 4, through the boss finale
#   bash scripts/playtest.sh --seed=7 --speed=1 --minutes=3   # 3 minutes in real time
#   bash scripts/playtest.sh --warp=600 --minutes=13 --speed=1 --vsync=off   # fast-forward to 10:00 (nothing drawn),
#                                                             # then 3 real-time minutes with 200+ mobs, uncapped FPS
#   bash scripts/playtest.sh --stage=tree_that_grew_1 --out=evidence/mytest
#
# Options (all optional): --stage=<key> (stages.json, default henesys_hg1), --seed=<n> (2026), --speed=<k> sim ticks
# per 60 Hz frame (4), --minutes=<m> absolute run time to stop at (30; a death or clear ends earlier), --shot-every=<s> run
# seconds between screenshots (60), --out=<dir> (default evidence/playtest/<stage>_s<seed>_x<speed>_<time>), --warp=<s>,
# --job=<id> (force a first or second job, e.g. 210; the game refuses one this build cannot offer; --branch=<id> is the deprecated alias), --vsync=off, --name=<character name>, --window-autopick=<s> (windows open and answer themselves instead of autopick).
# --account=<abs JSON> (an account for the round, spec #34: owned cash items, worn cash equipment, pet, ALERT levels; see
# scripts/balance.sh and game/scripts/core/account_file.gd; summary.json names the file).
# Anything else is passed to the game unchanged. Screenshots of the running game stay in evidence/ (gitignored).
#
# Frame times: the game caps the frame rate at the display's refresh rate (Settings / GameSettings.apply_frame_cap), so
# frame_ms without --vsync=off is the cap (16.7 ms at 60 Hz); pass --vsync=off for performance measurements.
# Output files: t<s>.png every --shot-every, levelup_N / job_N / hit_first / death_* / clear / final.png, summary.json
# (RunScene.perf_summary: frame_ms p50/p95/p99/max, frame_work_us, sim_us_per_tick, max_alive, level_by_minute, ...).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"

STAGE="henesys_hg1"
SEED="2026"
SPEED="4"
MINUTES="30"
SHOT_EVERY="60"
OUT=""
AUTOPICK="--autopick"
EXTRA=()
for a in "$@"; do
  case "$a" in
    --job=*|--branch=*)
      [[ "$a" == --branch=* ]] && echo "playtest.sh: --branch is deprecated: use --job=<id>" >&2
      JOB_ID="${a#--*=}"
      [[ "$JOB_ID" =~ ^[0-9]+$ ]] || { echo "--job must be a job id (e.g. 200, 210)" >&2; exit 2; }
      EXTRA+=("--job=$JOB_ID") ;;
    --stage=*) STAGE="${a#--stage=}" ;;
    --seed=*) SEED="${a#--seed=}" ;;
    --speed=*) SPEED="${a#--speed=}" ;;
    --minutes=*) MINUTES="${a#--minutes=}" ;;
    --shot-every=*) SHOT_EVERY="${a#--shot-every=}" ;;
    --out=*) OUT="${a#--out=}" ;;
    --window-autopick=*) AUTOPICK=""; EXTRA+=("$a") ;;
    *) EXTRA+=("$a") ;;
  esac
done
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
