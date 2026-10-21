# W1a: test runner and repository hygiene

Base: `7019db5`. Worktree: `C:/Users/itech/.t3/worktrees/maple-survivors/t3-628154f0`.
Branch: `t3/fix-test-runner-parse-errors`. All Godot invocations were headless, using pinned
`4.7.2.stable.official.ed1daf0bf`. No balance, importer, web, or asset-manifest changes.

Read and applied `godot-gdscript-headless-testing` (explicit exit status and failure counting),
`godot-gdscript` (explicit Dictionary typing and scene lifecycle), and `godot-resources`
(load script resources without instantiating tools; let the editor generate UIDs).

## Changes and red/green evidence

- **MS-13:** exclude methods with `METHOD_FLAG_STATIC`, including inherited `TestCase.test_dir`.
  Keep the scratch-path helper and every caller unchanged. Record discovery failures for no selected files
  and selected files without instance test methods. `scripts/test.sh` is unchanged.
  A deterministic discovery regression uses three instance methods plus a static helper. Before the fix it
  discovered five methods, including `test_dir`; after the fix it discovers exactly three.
  The test commit extracts discovery into a helper without changing its behavior to expose this seam.
- **MS-37:** reject non-finite operands/bounds/tolerances, negative tolerances, and reversed intervals.
  Six focused tests check NaN, positive/negative infinity, invalid tolerances, inclusive finite endpoints,
  equal bounds, exact zero tolerance, and finite misses. Before the fix three methods failed; after it all six pass.
- **MS-41:** attach the viewport under `SceneTree.current_scene` and assert `is_inside_tree()`.
  Before the fix the new assertion failed and the busy-parent ERROR was logged; the focused green run has neither.
  This changes test fixture setup only; no player-facing visual change or screenshot is needed.
- **MS-42:** explicitly type the granted wand as `Dictionary`. Two census tests recursively load all 35 `.gd`
  files under `res://scenes/debug/` and `res://tools/` and require `can_instantiate()`, without instantiating them.
  The original `character_driver.gd:100` parse error failed the new debug test before the fix.
  A planted scratch debug script also failed it; removal restored both census tests to green.
- **MS-31:** the real-worktree import generated 34 sidecars: the 31 audited omissions and three new test sidecars.
  `git status --short` showed only those untracked `.gd.uid` files. No tracked file changed, so no revert was needed.
  The UID commit contains only those sidecars and no `.godot/` files. This editor-generation task has one commit;
  there is no useful failing behavioral test for missing identity metadata.

The four code findings each have a failing-test commit followed by a fix commit. No test golden was changed.
The initial numeric/parser run reported `10 tests, 4 failed, 0 skipped, 2 files` (including two unwanted helpers).
The discovery/viewport red run reported `13 tests, 2 failed, 0 skipped, 2 files` (including two unwanted helpers).
The final focused run reported `19 tests, 0 failed, 0 skipped, 4 files (2288 ms)` and `TESTS_PASSED`, exit 0.

## Commands and process-level regression checks

Run these through `C:/Program Files/Git/bin/bash.exe -lc` from PowerShell, never WSL's plain `bash`.
All commands below were run from the worktree above with:

```bash
export MAPLE_SURVIVORS_CACHE=C:/Users/itech/AppData/Roaming/MapleSurvivors/cache-skill-audit
ISOLATE=W1a bash scripts/test.sh test_test_case test_tool_scripts test_test_runner test_sharp_text
ISOLATE=W1a bash scripts/test.sh zz_no_such_filter
```

The unmatched-filter command returned 1, printed
`FAIL no test files selected in res://tests/unit (filters: ["zz_no_such_filter"])`, and ended with
`0 tests, 1 failed, 0 skipped, 0 files (6 ms)` / `TESTS_FAILED`.

For the remaining process checks, use the prepared mirror, avoiding recursive runners within the suite
(which would reset settings, clear fixtures, and nest error loggers in the parent test process):

```bash
PROJECT="$PWD/_scratch/godot_runs/W1a/game"
runner() {
  bash scripts/godot.sh --headless --path "$PROJECT" res://tests/test_runner.tscn -- "$@"
}
FIXTURE="$PROJECT/tests/unit/test_w1a_probe.gd"
```

Write each of the following bodies to `$FIXTURE`, then execute `runner test_w1a_probe; echo $?`:

```gdscript
# Three tests: exit 0, "3 tests, 0 failed, 0 skipped, 1 files (4 ms)".
extends TestCase
func test_a() -> void:
	assert_true(true)
func test_b() -> void:
	assert_true(true)
func test_c() -> void:
	assert_true(true)
static func test_helper() -> void:
	pass
```

```gdscript
# Zero methods: exit 1, "0 tests, 1 failed, 0 skipped, 1 files (4 ms)".
# Clear diagnostic: "FAIL res://tests/unit/test_w1a_probe.gd: no non-static test_* methods found".
extends TestCase
static func test_helper() -> void:
	pass
```

```gdscript
# Assertion failure: exit 1, "1 tests, 1 failed, 0 skipped, 1 files (17 ms)".
extends TestCase
func test_failure() -> void:
	assert_true(false, "planted assertion failure")
```

```gdscript
# Runtime failure: exit 1, "1 tests, 1 failed, 0 skipped, 1 files (7 ms)".
extends TestCase
func test_failure() -> void:
	var data: Dictionary = {}
	var _value: Variant = data["planted_missing_key"]
```

```gdscript
# Parse failure: exit 1, "1 tests, 1 failed, 0 skipped, 1 files (7 ms)".
extends TestCase
func test_failure( -> void:
	pass
```

Missing-directory check (scratch runner only):

```bash
rm -f "$FIXTURE"
sed -i 's|const UNIT_DIR := "res://tests/unit"|const UNIT_DIR := "res://tests/w1a_missing_directory"|' "$PROJECT/tests/test_runner.gd"
runner; echo $? # 1; "0 tests, 1 failed, 0 skipped, 0 files (1 ms)"; directory named in FAIL diagnostic.
cp game/tests/test_runner.gd "$PROJECT/tests/test_runner.gd"
```

Planted-error check (scratch debug script only):

```bash
printf 'extends Node\nfunc planted_error( -> void:\n\tpass\n' > "$PROJECT/scenes/debug/w1a_planted_parse_error.gd"
runner test_tool_scripts; echo $? # 1; "2 tests, 1 failed, 0 skipped, 1 files (1493 ms)".
rm -f "$PROJECT/scenes/debug/w1a_planted_parse_error.gd"
runner test_tool_scripts; echo $? # 0; "2 tests, 0 failed, 0 skipped, 1 files (1245 ms)".
```

The exact executed script and individual stdout/stderr logs are preserved locally in
`evidence/skill-audit/W1a/probes.sh`, `probe-summary.log`, and the named probe `.log` files.
They are ignored evidence, not committed game assets. All planted files were removed and the scratch runner restored.

## UID generation and inventory

The one authorized real-project import (exit 0):

```bash
bash scripts/godot.sh --headless --path game --import > evidence/skill-audit/W1a/real-import.log 2>&1
git status --short
```

Committed generated files:

```text
game/scenes/debug/bowman_driver.gd.uid
game/scenes/debug/bowman_equipment_driver.gd.uid
game/scenes/debug/combat_mechanics_driver.gd.uid
game/scenes/debug/crossbowman_driver.gd.uid
game/scenes/debug/dark_sight_driver.gd.uid
game/scenes/debug/hunter_driver.gd.uid
game/scenes/debug/thief_combat_driver.gd.uid
game/scripts/sim/potion_schedule.gd.uid
game/tests/fixtures/combat_mechanics_fixtures.gd.uid
game/tests/unit/test_bandit_attacks.gd.uid
game/tests/unit/test_bowman.gd.uid
game/tests/unit/test_bowman_equipment.gd.uid
game/tests/unit/test_bowman_fixtures.gd.uid
game/tests/unit/test_brawler_attacks.gd.uid
game/tests/unit/test_combat_mechanics.gd.uid
game/tests/unit/test_crossbowman.gd.uid
game/tests/unit/test_dark_sight.gd.uid
game/tests/unit/test_dark_sight_render.gd.uid
game/tests/unit/test_gunslinger_attacks.gd.uid
game/tests/unit/test_hunter.gd.uid
game/tests/unit/test_hyper_body.gd.uid
game/tests/unit/test_keen_eyes.gd.uid
game/tests/unit/test_moving_attacks.gd.uid
game/tests/unit/test_mp_recovery.gd.uid
game/tests/unit/test_pirate_fixtures.gd.uid
game/tests/unit/test_pirate_second_job.gd.uid
game/tests/unit/test_potion_schedule.gd.uid
game/tests/unit/test_test_case.gd.uid
game/tests/unit/test_test_runner.gd.uid
game/tests/unit/test_thief_fixtures.gd.uid
game/tests/unit/test_threaten.gd.uid
game/tests/unit/test_tool_scripts.gd.uid
game/tests/unit/test_warrior2_fixtures.gd.uid
game/tests/unit/test_warrior2_weapon_skills.gd.uid
```

## Full suite

```bash
TEST_TIMEOUT_S=1800 ISOLATE=W1a bash scripts/test.sh > evidence/skill-audit/W1a/full-suite.log 2>&1
```

The first attempt with the default 900-second cap timed out (timeout status 124), without a final summary or a
reported test failure. Its output is preserved in `full-suite-timeout.log`; a native static-string teardown error
appeared when that process was terminated. This attempt is not a passing full-suite result. The retry raises only
the process time limit to 1,800 seconds; no tests or code were changed between the runs.

The retry passed, exit **0**, with the exact summary and success marker:

```text
2045 tests, 0 failed, 0 skipped, 192 files (856806 ms)
TESTS_PASSED
```

All **2,045 passed**, none skipped. Accounting: baseline 2,225 minus 189 inherited helper invocations plus nine new
methods (six assertion tests, one discovery test, two parse census tests) = **2,045 tests in 192 files**, a net drop
of 180 reported tests. The three new files account for the increase from 189 to 192 files.

The full log contains **zero** `SCRIPT ERROR`, `FAIL`, `SKIP`, or busy-parent records. It still ends with the known
native shutdown error `ERROR: 2 RID allocations of type 'PN13RendererDummy14TextureStorage12DummyTextureE' were
leaked at exit.` The original audit also recorded two leaked texture RIDs; this workstream does not claim an
error-free native log or fix that separate leak. Deprecated `--branch` notices remain informational.

Rust and Node are not required for this workstream because no `tools/` or `web/` file changed.
No game windows were opened; no screenshots were inspected or requested for these test/tooling-only changes.
