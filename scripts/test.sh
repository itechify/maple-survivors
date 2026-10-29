#!/usr/bin/env bash
# Run the headless GDScript unit tests.
#
#   bash scripts/test.sh                    # every test file
#   bash scripts/test.sh footholds combat   # only test files whose name contains one of the filters
#   ISOLATE=<name> bash scripts/test.sh     # run in a private mirror (_scratch/godot_runs/<name>/game) so several
#                                           # agents/processes can test at once without sharing game/.godot/
#
# Tests that need the imported asset cache print SKIP and pass when it is absent (see AGENTS.md).
# Prints TESTS_PASSED / TESTS_FAILED and exits non-zero on failure.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$REPO/game"

if [[ -n "${ISOLATE:-}" ]]; then
  DEST="$REPO/_scratch/godot_runs/$ISOLATE/game"
  mkdir -p "$DEST"
  rm -rf "$DEST/export"  # the exported build (~110 MB) is never needed in a mirror
  (cd "$PROJECT" && tar --exclude=./.godot --exclude=./export -cf - .) | (cd "$DEST" && tar -xf -)
  (cd "$DEST" && find . -type f ! -path './.godot/*' | while read -r f; do [[ -e "$PROJECT/$f" ]] || rm -f "$f"; done)
  PROJECT="$DEST"
fi

GODOT_CMD=(bash "$REPO/scripts/godot.sh")
# Keep raw diagnostics: Godot can return zero after a script error or an early quit.
LOG="$(mktemp)"
IMPORT_LOG="$(mktemp)"
trap 'rm -f "$LOG" "$IMPORT_LOG"' EXIT
# An import pass registers class_name scripts. A failed import is itself a failed run.
IMPORT_STATUS=0
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >"$IMPORT_LOG" 2>&1 || IMPORT_STATUS=$?
# Never suppress the runner's diagnostics before checking the completion contract.
# Stream filtered output live (a full run takes ~30 min) while the raw log feeds the checks below.
set +e
timeout --kill-after=10 "${TEST_TIMEOUT_S:-1800}" "${GODOT_CMD[@]}" --headless --path "$PROJECT" \
  res://tests/test_runner.tscn -- "$@" 2>&1 | tee "$LOG" \
  | sed -uE '/^(Godot Engine v|WARNING: .*leaked|   at: |Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: .* resources still in use|TESTS_(PASS|FAIL)ED$)/d'
RUN_STATUS=${PIPESTATUS[0]}
set -e
# The shell owns the public verdict. Only publish PASSED after all guards agree.
if [[ "$IMPORT_STATUS" != 0 ]] || grep -qE '(^FAIL([ :]|$)|SCRIPT ERROR|^ERROR:)' "$IMPORT_LOG"; then
  cat "$IMPORT_LOG"
  echo "FAIL test harness: project import failed"
  RUN_STATUS=1
fi
if [[ "$RUN_STATUS" != 0 ]] || grep -qE '(^FAIL([ :]|$)|SCRIPT ERROR)' "$LOG" \
    || [[ "$(grep -cx TESTS_PASSED "$LOG")" != 1 ]] \
    || grep -qx TESTS_FAILED "$LOG" \
    || [[ "$(grep -Ec '^[0-9]+ tests, 0 failed, [0-9]+ skipped, [0-9]+ files \([0-9]+ ms\)$' "$LOG")" != 1 ]]; then
  echo "FAIL test harness: process status $RUN_STATUS or diagnostics/completion check failed"
  echo "1 harness checks, 1 failed (test counts above may be incomplete)"
  echo "TESTS_FAILED"
  exit 1
fi
echo "TESTS_PASSED"
