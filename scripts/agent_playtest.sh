#!/usr/bin/env bash
# Agent playtest (spec #91): plays a real round headless (game/tools/playtest/playtest_driver.gd on the real map and
# asset cache) with a brain answering card and job decisions over the stdio decision protocol, and writes a run
# directory with a report (evidence/agent-playtest/<stage>_s<seed>_<time>/report.md). Needs the asset cache and Node 24.
#
#   bash scripts/agent_playtest.sh --stage=henesys_hg1 --seed=2026 --minutes=3
#   bash scripts/agent_playtest.sh --brain=jev                # Jev (TypeSafe) decides cards and jobs; exit 2 without a key
#   bash scripts/agent_playtest.sh --brain=fallback           # deterministic fallback, no network (default auto: Jev if a
#                                                             # TYPESAFE_API_KEY resolves, incl. the Windows user env)
#   bash scripts/agent_playtest.sh --brain=builtin            # the driver answers itself (no pipe)
#   bash scripts/agent_playtest.sh --inject-finding=stuck     # test only: one fake finding at 0:10 (exit code 1)
#   bash scripts/agent_playtest.sh --help                     # every flag
#   ISOLATE=<name> bash scripts/agent_playtest.sh ...         # private project mirror (_scratch/godot_runs/<name>/game)
#
# Installs tools/playtest dependencies on first use (npm ci). Exit code: 0 clean, 1 deterministic problems found
# (invariant findings in findings.jsonl, SCRIPT ERROR / ERROR: lines in game.log), 2 infrastructure error (Godot
# missing, cache missing, no end message, no output for --liveness-s seconds). timeline.jsonl: one row per run second.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TOOL="$REPO/tools/playtest"

if [[ ! -d "$TOOL/node_modules" || "$TOOL/package-lock.json" -nt "$TOOL/node_modules" ]]; then
  echo "[agent_playtest] installing tools/playtest dependencies (npm ci)" >&2
  (cd "$TOOL" && npm ci --no-audit --no-fund --loglevel=error >&2)
  touch "$TOOL/node_modules"
fi
exec node "$TOOL/src/cli.ts" "$@"
