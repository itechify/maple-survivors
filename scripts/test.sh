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
set -uo pipefail
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
# An import pass registers new class_name scripts before the runner loads them.
"${GODOT_CMD[@]}" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true
timeout --kill-after=10 "${TEST_TIMEOUT_S:-900}" "${GODOT_CMD[@]}" --headless --path "$PROJECT" \
  res://tests/test_runner.tscn -- "$@" 2>&1 \
  | grep -vE '^(Godot Engine v|WARNING: .*leaked|   at: |Leaked instance|ERROR: .*ObjectDB instances leaked|ERROR: .* resources still in use)'
exit "${PIPESTATUS[0]}"
