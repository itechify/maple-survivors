#!/usr/bin/env bash
# Agent playtest (spec #91): plays a real round headless (game/tools/playtest/playtest_driver.gd on the real map and
# asset cache) with a brain answering card and job decisions over the stdio decision protocol, and writes a run
# directory with a report (evidence/agent-playtest/<scenario>_<stage>_<personality>_s<seed>_<time>/report.md). Needs the asset cache and Node 24.
#
#   bash scripts/agent_playtest.sh --stage=henesys_hg1 --seed=2026 --minutes=3
#   bash scripts/agent_playtest.sh --brain=jev                # Jev (TypeSafe) decides cards and jobs; exit 2 without a key
#   bash scripts/agent_playtest.sh --brain=fallback           # deterministic fallback, no network: evaluations off too
#                                                             # unless --evaluations=true (default auto: Jev if a
#                                                             # TYPESAFE_API_KEY resolves, incl. the Windows user env)
#   bash scripts/agent_playtest.sh --brain=builtin            # the driver answers itself (no pipe; evaluations off too)
#   bash scripts/agent_playtest.sh --inject-finding=stuck     # test only: one fake finding at 0:10 (exit code 1)
#   bash scripts/agent_playtest.sh --scenario=matrix          # tools/playtest/scenarios/<name>.json (default smoke);
#                                                             # explicit flags override its fields; several cells run in
#                                                             # parallel (ISOLATE slot mirrors) + summary.md/summary.json
#   bash scripts/agent_playtest.sh --scenario=tier_chain      # --tier=2 chain; fixture_dark_cave: --character fixture
#   bash scripts/agent_playtest.sh --replay=<run dir>         # exact re-run from decisions.jsonl (no Jev, no key);
#                                                             # a fingerprint mismatch is replay_divergence (exit 1)
#   bash scripts/agent_playtest.sh --replay=<run dir> --windowed --shots-at=412.5,600 [--speed=4] [--skip-to=<s>]
#                                                             # the same replay in the game window (keep it visible:
#                                                             # an occluded window draws no frames); screenshots at
#                                                             # those times and at every recorded finding, in
#                                                             # <run dir>_windowed_<time>/shots/ (report.md lists them)
#   bash scripts/agent_playtest.sh --strict-eval              # Jev-flagged evaluations count toward exit code 1
#   bash scripts/agent_playtest.sh --summarize=<matrix dir>   # rewrite a matrix's summary.md from its cells (no runs)
#   bash scripts/agent_playtest.sh --help                     # every flag
#
# report.md starts with a verdict and the next command. Problems lists deterministic failures, then Jev-flagged
# evaluations, then ones that need human review (evaluations.json: death fairness, minute pacing, movement, card
# offers; skipped without a TypeSafe key, on a replay, and by default with --brain=fallback or builtin). The brain and
# the evaluations share one --jev-max-requests cap per run. A matrix summary.md adds death-cluster patterns.
# Every flag: --help and docs/PLAYTESTING.md "Flags".
#   ISOLATE=<name> bash scripts/agent_playtest.sh ...         # private project mirror (_scratch/godot_runs/<name>/game)
#
# Installs tools/playtest dependencies on first use (npm ci). Exit code: 0 clean, 1 deterministic problems found
# (invariant findings in findings.jsonl, missing_asset included; SCRIPT ERROR / ERROR: lines in game.log), 2
# infrastructure error (Godot missing, no asset cache or no map, no end message, no output for --liveness-s seconds). timeline.jsonl: one row per run second.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REPO/tools/playtest"

if [[ ! -d "$TOOL/node_modules" || "$TOOL/package-lock.json" -nt "$TOOL/node_modules" ]]; then
  echo "[agent_playtest] installing tools/playtest dependencies (npm ci)" >&2
  (cd "$TOOL" && npm ci --no-audit --no-fund --loglevel=error >&2)
  touch "$TOOL/node_modules"
fi
exec node "$TOOL/src/cli.ts" "$@"
