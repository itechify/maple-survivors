#!/usr/bin/env bash
# Headless pacing report: whole runs on the real map with the kiting autoplay bot and a card policy (default: the
# sensible picks of BotInput.pick_card_for; --policy=random: a careless player who takes a random card of the three),
# the first available job, one Godot process per seed in parallel (game/tools/balance_run.gd). Needs the asset cache.
#
#   bash scripts/balance.sh                                # henesys_hg1, the held-out seeds 101..106
#   bash scripts/balance.sh 7 11 13                        # these seeds
#   bash scripts/balance.sh 101..130                       # a seed range (inclusive)
#   bash scripts/balance.sh --policy=random 101..112       # the careless player (random cards)
#   bash scripts/balance.sh --idle-after=300 101..106      # hands off the keys from 5:00 (cards still chosen)
#   bash scripts/balance.sh --stage=hill_east_henesys 1 2  # another stage
#   ISOLATE=<name> bash scripts/balance.sh                 # private mirror (_scratch/godot_runs/<name>/game), like test.sh
#   PATCH=/abs/variant.json bash scripts/balance.sh         # deep-merge a JSON patch into the data first (try a tuning
#                                                          # variant without editing game/data; see balance_run.gd)
#   BALANCE_OUT=<dir>                                      # where the per-seed logs/records go (default _scratch/balance)
#   JOBS=<n>                                               # at most n Godot processes at once (default 12)
#
# Seeds: the pacing in docs/GAME_DESIGN.md 4.2 was tuned on seeds 1..60 and 2026 and is reported on the held-out
# seeds 101..130, never used for tuning; keep it that way (tune on 1..60, check on 101..130).
#
# Prints a table (time of Lv 8/10/20/30, level at 4/8/12 min, alive mobs at 4/8/12 min, mobs near the player at
# 4/8/12 min, hits taken before 6:00 and after 8:00, EXP drops on the map at 8 min, how the run ended) and a summary
# line, and writes every run's full record to $BALANCE_OUT/<stage>_<policy>_<seed>.json.
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"

STAGE="henesys_hg1"
POLICY="bot"
EXTRA_IDLE=""
SEEDS=()
for a in "$@"; do
  case "$a" in
    --stage=*) STAGE="${a#--stage=}" ;;
    --policy=*) POLICY="${a#--policy=}" ;;
    --first-card) POLICY="first" ;;
    --idle-after=*) EXTRA_IDLE="$a" ;;
    *..*) for ((s = ${a%%..*}; s <= ${a##*..}; s++)); do SEEDS+=("$s"); done ;;
    *) SEEDS+=("$a") ;;
  esac
done
[[ ${#SEEDS[@]} -gt 0 ]] || SEEDS=(101 102 103 104 105 106)

if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE/game"
  mkdir -p "$DEST"
  rm -rf "$DEST/export"  # the exported build (~110 MB) is never needed in a mirror
  (cd "$PROJECT" && tar --exclude=./.godot --exclude=./export -cf - .) | (cd "$DEST" && tar -xf -)
  (cd "$DEST" && find . -type f ! -path './.godot/*' | while read -r f; do [[ -e "$PROJECT/$f" ]] || rm -f "$f"; done)
  PROJECT="$DEST"
fi

GODOT_CMD=(bash "$REPO/scripts/godot.sh")
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true

OUT="${BALANCE_OUT:-$REPO/_scratch/balance}"
mkdir -p "$OUT"
EXTRA=()
[[ -n "${PATCH:-}" ]] && EXTRA+=(--patch="$(cygpath -m "$PATCH" 2>/dev/null || echo "$PATCH")")
[[ -n "$EXTRA_IDLE" ]] && EXTRA+=("$EXTRA_IDLE")
MAXJ="${JOBS:-12}"
PIDS=()
for s in "${SEEDS[@]}"; do
  while [[ "$(jobs -rp | wc -l)" -ge "$MAXJ" ]]; do wait -n; done
  "${GODOT_CMD[@]}" --headless --path "$PROJECT" --script res://tools/balance_run.gd -- --stage="$STAGE" --seed="$s" \
    --policy="$POLICY" ${EXTRA[@]+"${EXTRA[@]}"} > "$OUT/${STAGE}_${POLICY}_${s}.log" 2>&1 &
  PIDS+=($!)
done
STATUS=0
wait
for s in "${SEEDS[@]}"; do
  grep -h '^BALANCE ' "$OUT/${STAGE}_${POLICY}_${s}.log" | sed 's/^BALANCE //' > "$OUT/${STAGE}_${POLICY}_${s}.json" || {
    echo "seed $s: no result (see $OUT/${STAGE}_${POLICY}_${s}.log)"; STATUS=1; }
done

# Tabulate with awk on the JSON fields that matter (no Python/Node needed).
echo "stage $STAGE, policy $POLICY${PATCH:+, patch $PATCH}"
printf '%-5s %-5s %-5s %-5s %-5s %-9s %-11s %-10s %-6s %-6s %-6s %-6s %-5s %s\n' seed Lv8 Lv10 Lv20 Lv30 "lv@4/8/12" \
  "alive4/8/12" "near4/8/12" "hit<6" "hit8+" "drop8" kills level end
for s in "${SEEDS[@]}"; do
  f="$OUT/${STAGE}_${POLICY}_${s}.json"
  [[ -s "$f" ]] || continue
  awk -v seed="$s" '
    function field(name,   m) { if (match($0, "\"" name "\":[^,}\\]]*")) { m = substr($0, RSTART, RLENGTH); sub(/^[^:]*:/, "", m); gsub(/"/, "", m); return m } return "" }
    function arr(name,   m) { if (match($0, "\"" name "\":\\[[^\\]]*\\]")) { m = substr($0, RSTART, RLENGTH); sub(/^[^\[]*\[/, "", m); sub(/\]$/, "", m); return m } return "" }
    function reach(lv,   m) { if (match($0, "\"" lv "\":[0-9.]+")) { m = substr($0, RSTART, RLENGTH); sub(/^[^:]*:/, "", m); return mmss(m) } return "--:--" }
    function mmss(t) { t = int(t); return sprintf("%d:%02d", int(t / 60), t % 60) }
    function r0(x) { return (x == "") ? "-" : sprintf("%d", x + 0.5) }
    function v(x) { return (x == "") ? "-" : x }
    {
      split(arr("level_by_min"), L, ","); split(arr("alive_by_min"), A, ","); k = split(arr("hits_by_min"), H, ",")
      split(arr("near_by_min"), N, ","); split(arr("drops_by_min"), D, ",")
      h = 0; for (i = 9; i <= k; i++) h += H[i]
      e = 0; for (i = 1; i <= 6 && i <= k; i++) e += H[i]
      printf "%-5s %-5s %-5s %-5s %-5s %-9s %-11s %-10s %-6s %-6s %-6s %-6s %-5s %s %s\n", seed, reach(8), reach(10), reach(20),
        reach(30), L[4] "/" L[8] "/" L[12], A[4] "/" A[8] "/" A[12], r0(N[4]) "/" r0(N[8]) "/" r0(N[12]), e, h, v(D[8]),
        field("kills"), field("level"), field("state"), mmss(field("time"))
    }' "$f"
done | tee "$OUT/.table"
# Summary: runs, clears, deaths (times), and min / median / max of the milestone times and the final level.
awk '
  function sec(s,   p) { if (s == "--:--" || s == "") return -1; split(s, p, ":"); return p[1] * 60 + p[2] }
  function mmss(t) { t = int(t); return sprintf("%d:%02d", int(t / 60), t % 60) }
  function stat(arr, n,   i, j, t, med) {
    if (n == 0) return "none"
    for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (arr[j] < arr[i]) { t = arr[i]; arr[i] = arr[j]; arr[j] = t }
    med = (n % 2) ? arr[(n + 1) / 2] : (arr[n / 2] + arr[n / 2 + 1]) / 2
    return sprintf("%s-%s (median %s, %d runs)", mmss(arr[1]), mmss(arr[n]), mmss(med), n)
  }
  {
    runs++
    if ($14 == "CLEARED") cleared++; else { died++; deaths = deaths " " $15 }
    if ((t = sec($2)) >= 0) { a8[++n8] = t; if (t >= 150 && t <= 225) in8++ }
    if ((t = sec($3)) >= 0) a10[++n10] = t
    if ((t = sec($5)) >= 0) { a30[++n30] = t; if (t >= 720) in30++ }
    lv[++nl] = $13
  }
  END {
    if (runs == 0) exit
    for (i = 1; i <= nl; i++) for (j = i + 1; j <= nl; j++) if (lv[j] < lv[i]) { t = lv[i]; lv[i] = lv[j]; lv[j] = t }
    printf "SUMMARY %d runs: %d cleared, %d died%s\n", runs, cleared, died, (died ? " (at" deaths ")" : "")
    printf "  Lv 8 %s, %d in 2:30-3:45\n", stat(a8, n8), in8
    printf "  Lv 10 %s\n", stat(a10, n10)
    printf "  Lv 30 %s, %d at 12:00 or later\n", stat(a30, n30), in30
    printf "  final level %d-%d (median %s)\n", lv[1], lv[nl], (nl % 2) ? lv[(nl + 1) / 2] : (lv[nl / 2] + lv[nl / 2 + 1]) / 2
  }' "$OUT/.table"
exit "$STATUS"
