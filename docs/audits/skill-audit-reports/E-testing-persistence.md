# Domain E — testing, persistence and distribution

Commit `a68e74f13666fe20e4ae6898333966742fc85dc0`; audit date 2026-10-21. Source/data/settings remained read-only. Only this report and synthetic probes under `_scratch/audit-E/` were written. No standard suite was duplicated; no proprietary fixture was copied.

## 1. Skills read

Read each assigned file in full under `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/`:

- `godot-gdscript-headless-testing/SKILL.md`: meaningful failure accounting, import-before-test, exit codes and CI timeouts. Preserve the existing scene runner; replacing it with the skill's example runner adds no value.
- `save-systems/SKILL.md`: plain snapshots, validation, atomic writes, recovery and migration. Also read `save-systems/references/versioning-and-migration.md` in full.
- `godot-export/SKILL.md`: matching templates, non-resource filters, licences and target smoke tests. Also read `godot-export/references/presets-and-cli.md` in full.
- `godot-resources/SKILL.md`: applied only to persistent data/resource formats, shared-state ownership and writable paths. JSON is appropriate for runtime saves; converting them to Resource objects is not recommended. Threaded resource loading was outside scope.

Context: COMMON_BRIEF.md and AGENTS.md; relevant Architecture 4.1–4.3, 7–8 and 10; Asset Pipeline 2, 5 and 7; Research 6/licensing; glossary; ADRs 0001–0004. Checked the issue inventory (`gh issue list --state all --limit 300`), issue bodies #68/#132/#133/#135/#142, and #103's diagnosis/acceptance comment. #46/#77 are the only open issues.

## 2. Scope and verification

### Coverage census

The requested **357 files = 189 `test_*.gd` scripts + 168 `.uid` sidecars**. There are **2,036 declared test methods**. Inherited `TestCase.test_dir()` is also discovered once per test file (E-6), inflating expected reported total to **2,225**.

Static call-graph census: **195 cache-gated methods** (191 direct require_cache callers plus four `test_world_real_map` methods through `_map()`), spanning 82 scripts. Without WZ/cache, **1,841 declared methods are eligible (90.42%), 195 SKIP (9.58%)**. One `test_ui_flow` method performs useful checks before an optional require_cache branch marks the whole method skipped. Including inherited helpers, the expected no-cache report is 2,030 passed / 195 skipped if nothing else fails. This is a source census, **not an independently executed no-cache suite**. SKIPs prove nothing about cache-backed behavior.

| Area under game/scripts | Scripts | Existing coverage and limit |
|---|---:|---|
| sim | 51 | Extensive synthetic fixed-tick combat, motion, jobs, bosses, drops, snapshot and golden/event tests. Real canonical/map integration is additional and cache-gated. |
| assets | 6 | Synthetic cache/library/WzImg/SpriteAnim/manifest tests; real completeness needs imported data. |
| core | 12 | SaveData/account/settings/SceneFlow/cash shop/WebHandoff/WebProfile have direct tests. |
| render | 16 | Synthetic map/avatar/mob/damage/camera/back-math and real-cache integration. Headless state does not prove pixels. |
| run | 3 | RunScene: 46 explicit methods, 45 cache-gated. RunWindows: 15 methods, 12 cache-gated. Free Market has synthetic and real-cache checks. |
| ui | 48 | Window stack, Stat/Skill/Equip/Item/Key/Options/shop models, drag/drop and keys tested; leaf HUD drawing mostly through aggregate integration/screenshots. |
| audio | 1 | Voice selection/buses/settings; cache-backed sound integration. Actual browser playback/fade/teardown remains a target check. |
| main | 1 | Launch/flow seams; export boot is separate. |

126/138 scripts are directly named by class/path in unit tests. The other 12 are not demonstrably untested: PortalSet/PortalApproach through world/bot tests, MapBackLayer through MapRenderer, HUD leaves through RunScene, InventoryWiring through window integration. Do not equate a reference census with execution coverage. The weakest boundary is **actual browser shell/IDBFS/worker/Engine lifecycle**. WebHandoff has 12 and WebProfile 20 explicit methods; they prove injected desktop seams, not IndexedDB sync.

Every explicit test has an assertion/failure reachable through file-local helpers in a conservative source scan. No bare assert(), await, sleep, wall-clock timing or global RNG call was found in unit tests. One tautology is `test_run_scene.gd:235`, `messages().size() >= 0`; surrounding checks are meaningful, so this is not an entirely vacuous test.

### Targeted commands

All runtime probes ran after PERF_DONE. Godot/Rust commands used the designated private cache and ISOLATE=audit-E. Godot used a throwaway project copy with Settings/SaveData/TestCase default paths redirected to scratch. Durations are contended, not performance evidence.

| Check | Result |
|---|---|
| Assertion/runtime-error/parse-broken file injection | **Passed rejection test**, copied test.sh returned **1**; all three cases counted as failures. `_scratch/audit-E/runner_failure.log`. Initial WindowsApps/WSL launcher was stopped; authoritative run used Git Bash. |
| Persistence/method inventory probe | **Observation succeeded, rc 0**: concurrent stale writer loses character; invalid candidate erases good backup on next write; inherited helper discovered. `persistence_probe.log`. These are defect demonstrations, not correctness passes. |
| Empty filter | **False green, rc 0**: 0 tests / 0 files / TESTS_PASSED. `empty_selection.log`. |
| NaN assertions/offline escape | **Guard gaps confirmed, rc 0**: zero NaN failures; uncalled curl shell-out function passes scan. No command/network operation executed. `nan_offline_probe.log`. |
| Synthetic importer using existing testutil.rs | **Observation succeeded, rc 0**: missing MP3 not repaired; native v95 accepted; giant canvas capacity-overflow panic caught. `importer_probe.log`, `rust/src/main.rs`. No huge allocation attempted. |
| Artifact extras | **False acceptance, rc 0**: synthetic PNG plus valid ZIP containing synthetic PKG1/WZ entry accepted. `artifact_probe.log`; final direct rerun also rc 0. |
| Python census | **Not executed**, Python unavailable (rc 1); completed in Node (rc 0). |

Probe paths above are relative to `_scratch/audit-E/`. Some rg invocations needed corrected Windows glob/regex quoting; they were not treated as verification results. Original source/settings were never changed.

### Lead verification / export results

CHECKS_DONE exists (repeat run ended 08:23:33 PDT). Logs and balance records below were inspected after that sentinel. EXPORT_DONE remains pending. Waited approximately ten minutes for pending lead evidence (08:15–08:25 PDT), as bounded by the common brief.

| Lead check | Observed status |
|---|---|
| Full game suite, real private cache | **Passed gate, rc 0**. `logs/test_suite.log:42`: 2,225 reported tests, 0 failed, 0 skipped, 189 files; therefore 2,036 declared methods plus 189 utility invocations. 0 SCRIPT ERROR records. **One native test-setup ERROR** (sharp-text add_child, E-12), plus **one native exit-error record reporting two leaked texture RIDs**. These are not counted by the runner; do not describe the run as error-free. Duration is contended, not a performance claim. |
| Rust with MAPLE_WZ_ROOT set | **Passed, rc 0**: 44 unit + 1 dependency guard + 1 source guard + 18 real-data tests = **64 passed**, 0 failed, 0 ignored, 0 real-WZ SKIPs. Pipeline command explicitly sets MAPLE_WZ_ROOT and the log contains no SKIP; these 18 were executed, unlike ordinary public CI. Cargo emits a lib/bin PDB output-name collision warning; this did not fail the run. `logs/cargo_test_realwz.log`. |
| Node | Initial directory-argument invocation **failed, rc 1**, with no test evidence; pipeline explicitly records the harness mistake. Corrected documented glob **passed, rc 0: 51 passed, 0 failed, 0 skipped, 0 cancelled**. `logs/node_tests.log` contains corrected run, `pipeline.log` retains both statuses. Not a product regression. |
| Balance/determinism repeat | **Passed execution, all five commands rc 0** (four stage/policy groups + repeated Henesys bot; seeds 1/2/2026 only). All 12 unique and three repeated records have empty missing/warnings. **Determinism passed:** all three per-seed JSON records and summary JSON are byte-identical and canonically equal; no field exclusions needed (simulation time retained). `_scratch/audit-E/determinism_diff.json` records SHA-256 comparisons. Seed 1: CLEARED 958.4 s; seed 2: DEAD 274.1 s; 2026: DEAD 259.4 s, identically in both runs. This establishes this local repeat, not all platforms/seeds. |
| Windows/web exports, licence output, exported startup | **Not executed / pending lead** at report cutoff: no EXPORT_DONE, export directory or export_*.log was available. No Windows/web build, bundled-licence inspection or target startup pass is claimed. Export source/preset/checker review and synthetic checker probes were completed. |

The existing public CI intentionally has no WZ data: 195 GDScript cache checks SKIP and Rust real-data methods return early despite reporting ok. The lead's real-cache result does not establish what a no-cache runtime run passed; the source census above is explicit about this limit. No offline adapter-disabled test or browser IndexedDB-eviction/two-tab runtime test was executed by this auditor.

Balance smoke details (informational, no tuning):

| Stage / policy | Seed 1 / 2 / 2026 outcomes (seconds) | Clears | Missing/warnings |
|---|---|---:|---|
| Henesys / bot | CLEARED 958.4 / DEAD 274.1 / DEAD 259.4 | 1/3 | All empty |
| Henesys / random | DEAD 556.3 / DEAD 602.0 / DEAD 295.6 | 0/3 | All empty |
| Tree / bot | DEAD 544.4 / DEAD 969.8 / DEAD 47.5 | 0/3 | All empty |
| Tree / random | DEAD 569.2 / DEAD 176.2 / DEAD 47.5 | 0/3 | All empty |

Henesys seed-1 bot reaches job 210 and kills all three bosses; its CLEARED state is recorded after choices. Early Tree deaths are already owner-deferred, not a new tuning recommendation. Remaining FLOW_DONE/VISUAL_DONE phases were unavailable at this cutoff; existing source tests/scenarios were reviewed but no new flow-driver pass is claimed here.

### Determinism source review

No global randi/randf/randfn/range RNG/randomize/seed/shuffle/pick_random call found under sim. RunWorld injects separated streams (`run_world.gd:394`), each seeded with `seed_value * 1000003 + n * 7919` (line 1970). Hub arrival explicitly seeds 0. Pickup/projectile standalone fallbacks can create a default RNG; production RunWorld injects seeded instances.

WZ insertion order becomes foothold indices (`foothold_map.gd:77`); skill order is persisted and draws use ordered lists. This is deterministic for the same cache/input. Manual buffs iterate input Dictionary keys (`run_world.gd:809`), but no present competing playable buffs established a defect. #142 is fixed: `test_character_baseline.gd:64` identifies old JSON Vector2 rounding differences, not divergent gameplay; its 72,000-tick binary event golden now has no Windows-only gate.

## 3. Strengths worth preserving

- Runner explicitly rejects scripts that fail load/instantiate (`test_runner.gd:30`); ScriptErrorGuard captures GDScript errors; test.sh returns Godot's pipeline status and has a timeout. Failure injection confirmed assertion/runtime/parse rejection. Ignoring the import-pass status does not hide a broken test script when the runner loads it.
- #103 is fixed: runner reloads Settings from TestCase.test_dir and resets InputMap. Cache discovery deliberately still honors the developer's cache config, without reusing their bindings.
- SaveData validates detached plain data, flushes/closes .tmp, retains .bak, and commits memory only on successful write (`save_data.gd:332,354`). NX and terminal slot/history updates share one transaction.
- `test_save_data.gd:16,51,86,148,176,233` covers migration, failed writes, missing-primary Windows recovery, all endings, best/history updates and malformed shapes. CharacterSnapshot/worn-equipment/UI-flow tests cover format 1?2, idempotence and carry.
- SceneFlow persists stage/seed before launch and has one non-final clear route (`scene_flow.gd:246,379`). Tests cover hub, death/victory, deletion/history, Continue replay and one-off no-write behavior.
- Importer has ReadAt bounds, directory count/depth/read-window limits, synthetic malformed sound and ZIP/ZIP64 cases. ZIP helper unwraps are guarded by surrounding fixed-size checks; mutex unwraps alone are not an untrusted-input panic finding.
- CI runs on PRs, locks Cargo deps, matches wasm-bindgen CLI to Cargo.lock, pins Godot 4.7.2 and verifies template SHA-512. Single-threaded export appropriately avoids COOP/COEP needs on Pages.
- Export filters include nested survivor JSON/manifest fragments; stale output is removed; Godot/crate/wasm/Arimo notices are bundled. Existing artifact planted-file tests are useful; extend them rather than adding duplicate infrastructure.

## 4. Findings

### E-1 — Concurrent sessions overwrite each other's characters/account

- **Category/severity/type:** Persistence / **Critical** (lost progress) / Confirmed bug in shared-file sessions; browser manifestation Likely pending two-tab test.
- **Evidence:** SaveData retains a loaded snapshot and replaces the entire file without a lock/revision check (`game/scripts/core/save_data.gd:60,332,354`). One browser `/userfs` database is shared; IDBFS sync reconciles its in-memory tree (`web/idbfs.js:11,17,36`). `web/shell.js:478,493,791` guards ownership only within a page. `onblocked` concerns database upgrades, not ordinary same-version tabs. Synthetic A/B probe: A saves character TabOne; stale B commits an account change; disk slots become all null (`_scratch/audit-E/persistence_probe.log`).
- **Skills applied:** save-systems — authoritative snapshots, defensive stale-state handling and preserving last good state; godot-export — target-platform persistence verification.
- **Impact:** Two tabs or desktop instances can silently lose characters, NX purchases/history or imported saves. A stale browser engine can also interfere with another tab's cache import.
- **Recommendation:** One writer per user-data store before engine/import-worker mounting, with clear already-open handling and safe takeover; protect desktop too. Alternatively synchronize and reject stale revisions. Browser coordination belongs in web/, preserving the no-JavaScriptBridge rule.
- **Effort/confidence:** M / Confirmed native stale-write loss; Likely web manifestation.
- **Acceptance:** Synthetic two-session conflict preserves A or returns explicit conflict; disposable-origin two-tab test covers saves, import, owner exit and takeover without lost records.
- **False positive if:** an external single-instance guard exists. None found; public SaveData loss reproduced.
- **Known/intentional check:** #68/#133 and Architecture 4.2/10.2 assume one writer but do not authorize losing second-session progress. Account sharing across characters is separate.

### E-2 — Invalid save import can erase the only good backup

- **Category/severity/type:** Import/recovery / **Critical** (prior save and backup lost) / Confirmed bug in composed recovery behavior.
- **Evidence:** `web/lib.js:357` accepts `{"format":2,"best":{},"runs":{},"slots":[{},null,null],"history":[]}` as `{ok:true,slots:1}`. `web/shell.js:637,645` backs up the healthy save and installs it. SaveData falls back to .bak only for a missing primary (`save_data.gd:69`), preserves malformed input as .bad and starts empty (86–92). Its next write (376) copies the invalid primary over the good .bak. Probe: `backup_has_old=true` after failed candidate load, then `primary_has_old=false backup_has_old=false` after saving; .bad contains the invalid candidate, not the old character.
- **Skills applied:** save-systems/versioning reference — validate before commit and preserve/recover last good state; godot-resources — JSON is appropriate but requires a validated boundary.
- **Impact:** Damaged or edited JSON-valid backup replaces a healthy account; subsequent character creation or another normal save mutation can destroy its recovery copy.
- **Recommendation:** Stage import and obtain full game validation before promotion, or roll rejected candidates back to the retained healthy backup. Never rotate an invalid primary over the sole valid recovery copy. Avoid a second partial CharacterSnapshot validator that drifts.
- **Effort/confidence:** M / Confirmed JS acceptance plus native recovery sequence.
- **Acceptance:** Malformed nested slot/account/history and future-schema candidates leave prior primary/recovery bytes intact after restart and a subsequent successful save; valid synthetic saves round-trip.
- **False positive if:** a full validation handshake or independent immutable backup exists. Neither found.
- **Known/intentional check:** #133/Architecture 10.2 deliberately use shallow shell validation; #68 deliberately starts empty after preserving corruption. The defect is their destructive composition, not failure to implement either original checklist. Safer candidate promotion respects the offline/JSON architecture.

### E-3 — WZ canvas dimensions can panic instead of returning an import error

- **Category/severity/type:** Importer robustness / **Critical** (crafted invalid-input process crash) / Confirmed bug; not observed with owner's v83 data.
- **Evidence:** Parser checks dimensions are nonnegative, not bounded (`tools/wzimport/src/property.rs:260`). `canvas.rs:13` uses unchecked usize multiplication; lines 81/115 allocate those lengths. `export.rs:129` calls decoder without panic containment. Synthetic testutil.rs image with format 2, width/height i32::MAX successfully parses (GIANT_HEADER_PARSED=true), then the production decoder triggers `capacity overflow`; probe catches it and prints `GIANT_CANVAS_PANICKED=true`. A 65536² canvas requests 17,179,869,184 bytes on native; wasm32 additionally risks integer overflow. No huge allocation was attempted in the audit.
- **Skills applied:** godot-export — smoke-test the actual target, including import failure paths; headless-testing — error cases need testable error results, not process-level failures bypassing normal reporting.
- **Impact:** Damaged/malicious input can crash native importer or trap/abort a worker. Smaller unreasonable sizes can exhaust memory.
- **Recommendation:** Checked arithmetic and explicit per-canvas/img/aggregate budgets before allocation; fallible allocation where appropriate. Bound property nesting/work too (directory limits do not cover Property recursion). Return named WzError; preserve current cache on rejection.
- **Effort/confidence:** M / Confirmed native panic; wasm behavior needs target validation.
- **Acceptance:** Synthetic oversized/overflow/deep Property or Convex/huge-img cases return bounded errors on native/wasm without giant allocation; normal formats 1/2/513/517 remain byte-identical.
- **False positive if:** an earlier validator blocks the header. Selected-tree/export path checked; none does. This is not a blanket accusation against guarded ZIP unwraps.
- **Known/intentional check:** #132 requires bounded memory/errors. Existing directory limits and oversized atlas support do not justify unlimited decoded pixels. No matching open issue.

### E-4 — Native folder imports accept versions rejected by ZIP/wasm

- **Category/severity/type:** Import validation/parity / **Medium** / Confirmed bug against v83-only contract.
- **Evidence:** `tools/wzimport/src/wzroot.rs:189` uses Some(83) for injected/ZIP readers, but native folders call WzArchive::open, which auto-detects up to version 1000 (`archive.rs:74,119`). Synthetic native version-95 Sound.wz returns `NATIVE_V95_IMPORT=Ok(([], ["Sound.wz/Test.img"]))`. Existing `source_tests.rs:87` only proves forced-reader rejection.
- **Skills applied:** godot-export — common input contract across distributions; headless-testing — test both platform branches, not just the stricter helper.
- **Impact:** Wrong-version install can silently supply non-v83 canonical data on desktop; same content in ZIP/web fails. Incompatibilities surface later as broken/missing behavior.
- **Recommendation:** Enforce v83 at the import boundary for folders too; retain generic archive detection for diagnostic tools if useful.
- **Effort/confidence:** S/M / Confirmed.
- **Acceptance:** v95 fails folder, stored/deflated ZIP and injected imports before committed output; edited v83 still passes; generic archive detection tests retain their diagnostic behavior.
- **False positive if:** arbitrary native versions are explicitly supported. #132/ADR 0004 require v83 hash; no exception found.
- **Known/intentional check:** Generic archive auto-detection is intentional; unqualified use in the game import path is the mismatch. Checked #132/Asset Pipeline 2.1.

### E-5 — Normal re-import cannot repair missing audio

- **Category/severity/type:** Cache repair / **Medium** / Confirmed bug.
- **Evidence:** `tools/wzimport/src/import.rs:254` up-to-date checks cover source stamp, JSON and atlas pages, not audio. Existing `tests.rs:819` tests deleted PNG repair only. Synthetic import/delete-MP3/re-import: `written=[]`, `skipped=["Sound.wz/Test.img"]`, `sound_exists=false`, `errors=[]` (`importer_probe.log`). Web cache assessment also checks index/JSON/pages rather than sound records.
- **Skills applied:** godot-export — verify external runtime resource completeness; headless-testing — extend the existing incremental-import integration test for the omitted resource kind.
- **Impact:** BGM/effects remain silent after an apparently successful repair. --force fixes native output, but is not normal UI recovery. Web complete re-import is fresh, but boot will not detect sound loss.
- **Recommendation:** Record/check exported payload paths including MP3/WAV in completeness and up-to-date checks, sharing the index contract between native repair/web assessment.
- **Effort/confidence:** M (backward-compatible index addition) / Confirmed native failure and source-level web omission.
- **Acceptance:** Delete MP3 and WAV separately in existing synthetic test; normal re-import restores each, web assessment marks missing records incomplete; complete unchanged cache still skips.
- **False positive if:** all native re-imports force fresh export. Default public import path is incremental; reproduced directly.
- **Known/intentional check:** Cache contract and existing deleted-page test checked. Fresh web re-import is intentional but does not supply boot sound-completeness coverage.

### E-6 — Runner counts a utility as a test and passes empty selections

- **Category/severity/type:** Test accounting/discovery / **Medium** / Confirmed bug.
- **Evidence:** `game/tests/test_runner.gd:38` accepts every inherited test_* method, including static `TestCase.test_dir` (`test_case.gd:41`). Probe prints its discovery; three declared methods report four tests. Across 189 scripts this adds 189 assertion-free passes (8.49% of reported 2,225). `_discover` also returns empty for missing directory/unmatched filter, but run still returns success (`test_runner.gd:63,79`). Empty-filter probe returned 0, TESTS_PASSED, zero tests/files.
- **Skills applied:** headless-testing — meaningful counts and explicit exit codes CI can trust.
- **Impact:** Exaggerated test totals; broken discovery or typo can yield a green run with no behavioral checks.
- **Recommendation:** Exclude inherited/static utilities or rename utility outside test_*; fail clearly when no files/eligible methods selected. Retain explicit SKIPs.
- **Effort/confidence:** S / Confirmed.
- **Acceptance:** Three declared methods count three; unmatched filter/missing directory return non-zero; assertion/runtime/parse rejection remains correct.
- **False positive if:** test_dir intentionally tests behavior. It only returns a path, records no assertion; discovery confirmed.
- **Known/intentional check:** Runner comments promise behavioral test methods. #103 introduced private paths, not repeated utility tests. No matching open issue.

### E-7 — CI exports but never runs browser/Windows startup and persistence

- **Category/severity/type:** Distribution coverage / **Medium** / Proposed improvement; confirmed gap, not an observed broken build.
- **Evidence:** `.github/workflows/pages.yml:96–115` runs native Rust, pure Node, source-project headless GDScript and web export/artifact checks, no browser or Windows executable. Node tests cover lib/manifest/cache assessment/artifact checker, not shell.js/IDBFS/worker?Engine lifecycle. Handoff/Profile tests inject forced profile/quit callbacks. Without cache, 45/46 RunScene and 12/15 RunWindows methods SKIP. Existing flow_driver scenarios are not CI steps.
- **Skills applied:** godot-export — smoke-test exported build on target; headless-testing — CI gate should exercise its claimed runtime behavior.
- **Impact:** Worker/glue/IndexedDB restart defects, shell save loss and Windows importer-location/package failures can merge green. Source SceneFlow tests cannot prove exported user:// sync.
- **Recommendation:** Small no-WZ browser smoke on the existing exported artifact with synthetic IndexedDB/save data in web/dev/test tooling; Windows export/startup/importer-discovery smoke when practical. Reuse flow_driver locally for real-cache transitions; never put proprietary cache into public CI.
- **Effort/confidence:** M / Confirmed gap.
- **Acceptance:** CI boots shipped page to import UI and checks synthetic save/export/import/restart with lifecycle/console failures fatal; Windows smoke verifies importer/licences and startup. Log source tests/artifact checks/target execution separately.
- **False positive if:** another required workflow supplies these gates. Workflow inventory checked; pages.yml is the existing gate.
- **Known/intentional check:** #135 permits cache SKIPs; #136 documents manual Chrome/Firefox QA. This follow-up does not claim those tickets were unimplemented or request duplicate test infrastructure.

### E-8 — Artifact guard accepts unexpected ZIPs and renamed decoded images

- **Category/severity/type:** Distribution safeguards / **Medium** / Confirmed limitation, maintainability risk; no proprietary leak found.
- **Evidence:** `scripts/check_web_artifact.sh:23` rejects filename shapes and first-four-byte loose-file PKG1 signatures. Required-files list is not an allowed-files list. Synthetic extra unlisted.png and valid unlisted.zip containing a synthetic *.wz/PKG1 entry passed rc 0. PCK contents are outside that signature check. `.gitignore:3` covers *.wz/*.exe/*.dll and known evidence/cache folders, not arbitrary extracted PNGs elsewhere.
- **Skills applied:** godot-export — validate resource inclusion/exclusion and final shipped contents, not export exit status alone.
- **Impact:** Accidental asset ZIP, renamed decoded image or packed-in asset can evade a check described as assuring no WZ data. Current positive results prove only implemented shapes.
- **Recommendation:** Extend existing checker/tests with explicit shipping-file allowlist and unexpected archive rejection/inspection. Check packed export inventory against approved source asset paths; retain provenance review where signatures cannot distinguish original art from extracted art. Preserve legitimate branding/fonts.
- **Effort/confidence:** S/M / Confirmed loose-file acceptance; packed content is an inspection limitation, not observed contamination.
- **Acceptance:** Valid export passes, extra ZIP/unknown image rejected including renamed container; fixtures synthetic; docs distinguish signature checks from packed-content/provenance checks.
- **False positive if:** checker is intentionally only heuristic and not meant to assure data-free output. Its comments/workflow state the stronger purpose; this is hardening, not a legal violation allegation.
- **Known/intentional check:** #135 requires WZ/cache exclusion; existing planted-pattern tests are valuable. No copied/copyleft implementation or proprietary committed asset established here.

### E-9 — Offline scans miss network-capable subprocesses

- **Category/severity/type:** Offline regression safeguards / **Low** / Confirmed limitation, maintainability risk; no current violation.
- **Evidence:** `game/tests/unit/test_offline.gd:5` already bans OS.shell_open, but not OS.execute/execute_with_pipe/create_process. Scratch uncalled `OS.execute("curl", ["--version"])` passed the real scan. Rust `tests/no_network_src.rs:6` scans networking tokens, not std::process::Command; dependency denylist cannot stop shell-outs. No automatic request-origin assertion covers the actual web lifecycle.
- **Skills applied:** headless-testing — explicitly check the forbidden behavior a CI gate claims; godot-export — checks must cover distributed code.
- **Impact:** Future accidental command invocation or hard-coded web request could escape green offline scans.
- **Recommendation:** Narrow allowlist/check for legitimate local-importer launch sites and browser request destinations; keep token scans. Do not ban the importer or add game-side networking.
- **Effort/confidence:** S/M / Confirmed static subprocess escape; no command was executed.
- **Acceptance:** Synthetic forbidden command rejected without execution, legitimate importer remains allowed; web smoke fails on requests outside static bundle and user-named source.
- **False positive if:** scans are intended only as partial guardrails. That describes them accurately; no token scan secures against deliberately malicious authors. Stock ResourceLoader URL loading was not demonstrated as a network exploit and is not claimed here.
- **Known/intentional check:** Architecture 7/ADR 0004 permit local subprocess/import-source requests. Current examined code contains no proven prohibited network operation.

### E-10 — Numeric assertion helpers accept NaN

- **Category/severity/type:** Assertions / **Low** / Confirmed bug.
- **Evidence:** `game/tests/test_case.gd:92–99` fails only on abs(delta)>eps or ordered range comparisons. NaN makes both false. Probe assert_near(NAN,1.0), assert_between(NAN,0.0,1.0): NAN_ASSERTION_FAILURES=0, rc 0.
- **Skills applied:** headless-testing — invalid values must record failure and drive exit status.
- **Impact:** Numerical motion/combat/render regressions can pass approximate/range assertions. Other exact/digest checks may still catch them.
- **Recommendation:** Reject non-finite operands/bounds and invalid tolerance; use separate helpers for intentional infinities.
- **Effort/confidence:** S / Confirmed.
- **Acceptance:** NaN/inappropriate infinity fail, finite boundaries retain semantics; add focused helper tests to existing runner infrastructure.
- **False positive if:** NaN intentionally means near any value. No such contract; snapshot validation explicitly rejects non-finite numbers.
- **Known/intentional check:** TestCase promises recorded deterministic checks; no NaN exception/open issue found.

### E-11 — Settings are written in place and callers discard errors

- **Category/severity/type:** Settings durability / **Low** / Maintainability risk/proposed improvement.
- **Evidence:** `game/scripts/core/settings.gd:280,299` directly cfg.save(_path), no temp/backup recovery. Setters such as set_volume (303) mutate memory, call save_settings and emit changed without observing Error. Tests cover default/round-trip/key semantics, not interrupted or unwritable storage.
- **Skills applied:** save-systems — atomic writes/last-good recovery; godot-resources — correct user:// boundary still needs checked save errors.
- **Impact:** Crash or disk failure can lose bindings, volumes, alert/accessibility preferences and cache-path settings, or show a change as persisted when it is not. Character SaveData is unaffected.
- **Recommendation:** Apply temp/backup discipline to ConfigFile and surface UI persistence failures, preserving Settings/InputMap semantics and #103 isolation.
- **Effort/confidence:** S/M / Confirmed code path; crash-loss not fault-injected.
- **Acceptance:** Scratch unwritable/temp-failure case retains prior bytes and reports error; truncated primary recovers; binding/default tests pass without real config changes.
- **False positive if:** preference loss is explicitly accepted or ConfigFile supplies atomic recovery itself. No project guarantee/backup found; platform fault injection would further validate impact.
- **Known/intentional check:** #103 is isolation, not atomicity. Architecture separately promises stronger character-save durability; this is an improvement, not a reported incident.

### E-12 — Sharp-text test fails scene setup but still reports a pass

- **Category/severity/type:** Test fixture lifecycle / **Low** / Confirmed test bug.
- **Evidence:** `game/tests/unit/test_sharp_text.gd:159` adds its SubViewport directly to SceneTree.root while TestRunner is inside _ready and root is busy adding children. Lead `logs/test_suite.log:31` logs add_child failure with this exact test backtrace, then reports zero failed tests and exit 0. ScriptErrorGuard intentionally captures only GDScript errors, not native engine errors.
- **Skills applied:** headless-testing — respect scene-tree lifecycle and distinguish log errors from explicit recorded failures.
- **Impact:** Fixture setup is not what the test requests; a green suite is not an error-free suite. Its pure capture-size math can still pass without the viewport attached, so this does not establish a player capture defect.
- **Recommendation:** Parent under the current test scene (the pattern already used in RunScene tests), or remove unnecessary tree insertion if this is intentionally a pure geometry test. If attachment matters, assert is_inside_tree. Keep intentional engine-error tests separately allowlisted rather than blindly failing every expected engine log.
- **Effort/confidence:** S / Confirmed by lead run.
- **Acceptance:** Existing sharp-text geometry assertions pass with no busy-parent ERROR and any required viewport attachment explicitly verified.
- **False positive if:** failed attachment is deliberately the scenario. Test comment/body requests normal capture scaling; no negative attachment case is declared.
- **Known/intentional check:** ScriptErrorGuard's exclusion is documented and intentional; this finding targets the actual fixture error, not a claim that all engine errors should automatically fail all tests. #224 text/capture design is preserved.

## 5. Considered and rejected

- New test framework/SceneTree runner: unnecessary. Existing runner correctly rejects assertion/runtime/parse failures.
- UI/render/audio/SceneFlow/web-profile have no tests: false; target lifecycle gap is narrower (E-7).
- Entire suite is no-crash placeholders: unsupported; file-local helper scan reaches assertions for every declared test. One redundant nonnegative-size check is not representative.
- Reopening #103: reset/private Settings fix present; intentional cache discovery is not a binding regression.
- Counting ordinary CI's 18 real-WZ Rust 'ok' results as real-data passes: wrong; methods return early without MAPLE_WZ_ROOT. Lead's configured real-data run is distinguished above.
- OS.shell_open bypass: already banned. A remote load/ResourceLoader string alone was not demonstrated to fetch data in stock Godot.
- All unwraps unsafe: rejected after fixed-header bounds review. Canvas allocation is the concrete panic.
- Browser eviction as recoverable software defect: eviction can remove cache AND saves. Persistence request/status and export/import backup exist; re-import restores assets, not characters. An exported backup is the independent recovery. Two-tab stale writes are different.
- Web full-import queue and delete/write batches: documented trade-off, not new measured performance issue. Interrupted/quota-failed writes require cache re-import; save prefix is separate.
- No mid-round saves, same-seed Continue, last-boundary death history, one-off no-writes and account sharing: intentional ADR/spec decisions.
- Missing PotionSchedule .uid: sole missing sidecar under game/scripts, but no demonstrated failure. Uses class_name/path rather than missing UID references; clean scratch import registered it. Existing import-before-test/export rebuilds metadata. Sidecar addition is hygiene, not blocker.
- Licence/copyleft clearance: notices/permissive dependency declarations exist, but full provenance/history proof is outside this static audit; no copied copyleft code established. `git ls-files` found no tracked WZ/exe/DLL/MP3/WAV/img/img.json files. Final bundle inspection is reported separately.
- Rust stable/ubuntu-latest/hosted Node/action major tags can drift. Lower-priority reproducibility concern, not measured failure; Cargo.lock/Godot/wasm-bindgen matching already limit drift.

## 6. Unverified hypotheses

- Validate real browser two-tab IDBFS sync/cache interaction with disposable-origin synthetic records; native stale-write loss is already confirmed.
- Run oversized-header corpus in built wasm worker to distinguish recoverable error/trap/OOM without allocating gigabytes.
- Property recursion lacks directory-style depth guard; bounded corpus needed before claiming a particular stack-crash threshold.
- Reordered-but-semantically-equivalent input may change tie-breaks. That is distinct from same-input determinism; no current replay defect established.
- Export success does not prove playable target startup; never upgrade pending startup/flow checks to passed.

## 7. Independent backlog tasks

1. **Session writer ownership (E-1):** save-systems + godot-export; concurrent conflict/takeover tests, no game-side networking/JavaScriptBridge.
2. **Transactional import recovery (E-2):** save-systems + godot-resources + headless-testing; stage/full validation, prior primary/backup survive every rejection and next save.
3. **Malformed-input budgets (E-3):** godot-export + headless-testing; checked dimensions/allocations/parse work, native+wasm fixtures from existing testutil.rs, WzError without partial promotion.
4. **Uniform v83 import policy (E-4):** godot-export + headless-testing; folder/ZIP/injected rejection parity, generic diagnostic detector retained.
5. **Payload repair (E-5):** godot-export + headless-testing; existing incremental/cache tests delete MP3/WAV and verify repair/incomplete detection.
6. **Runner/assertion accuracy (E-6/E-10):** headless-testing; exclude helper, reject empty selection/non-finite values, retain parse/runtime failure gate.
7. **Target smokes (E-7):** godot-export + headless-testing; reuse existing web/dev tests and local flow_driver, no proprietary CI fixtures; browser synthetic persistence and Windows startup gates.
8. **Safeguard hardening (E-8/E-9):** godot-export + headless-testing; shipping allowlist, synthetic container/command rejection, explicit web request assertions.
9. **Atomic settings (E-11):** save-systems + godot-resources; fault-injected scratch writes preserve old prefs and binding semantics, UI reports failure.


10. **Sharp-text fixture lifecycle (E-12):** headless-testing; reuse current-scene attachment or omit it for pure geometry; existing assertions pass without the native setup error.





