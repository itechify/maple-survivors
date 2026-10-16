# Ticket #75: run-of-rounds QA

Audited integration `dba59a9` and implementation `89de7fa` against #32's owner triage decisions, #67–#75,
the binding spec32 decisions and the #70 rework audit. Read the merged consumers as well as running them;
earlier screenshots and reports were not treated as new evidence. No gameplay, canonical data, manifest or
balance values changed. `GLOSSARY.md` already defines every term used here, so it needs no additions.

## Flow and contract checks

| Contract | Fresh evidence |
|---|---|
| #67 carry/reset | Created Beginner really clears Henesys at 967.817s/Lv41 Cleric; hub shows full HP/MP and carried EXP/look; tier 2 starts from that boundary. Deterministic snapshot/reset tests remain in the full suite |
| #68 saves | Evidence-only format-2 file, disk reload at hub/map select/round, byte-identical file after Quit round, unchanged stage/seed/character after Continue; died/victory/deleted history and freed slots |
| #69 flow | Non-final clear enters hub; final clear enters results directly; natural death frees the character; Back returns to slots, no Retry; one-off clear leaves save bytes/history untouched |
| #70 v83 controls | Injected mouse clicks on shared signboard Create/Start/Delete, all three creation phases, character-slot click, Right selection, deletion Cancel/confirm and the actual History entry; selected metadata shows carried level/job |
| #71 hub | Real arrival, Esc/Save & quit, disk reload/Start, ordinary injected arrow-key walk from arrival to canonical out00, Up to tier-2 map select; full pools and own outfit. No relocation or direct exit call |
| #72 stage | Tier 1 offers the two original stages; tier 2 offers only Dark Cave. Roster/map IDs, contact-only ordinary mobs, inert external exits/NPC and deferred #76 behavior checked against code/data/tests |
| #73 bosses | Fresh captures of all three bosses and all seven canonical attack windups/impacts, including Balrog's ball in flight; real attack events, no missing assets or world warnings. Type-1's existing tier-C caveat remains documented |
| #74 tooling | Seeds 1/2/2026, both policies: original stages, conditional chains and Lv38 F/P fixture; 24 records/26 rounds, matching prior outcomes. No tuning or held-out seeds |
| #75 docs | Architecture flow/save model/ADR link, run structure and provenance, AGENTS Running/Playtests/Balance guidance checked; stale single-stage and Retry prose corrected |

The `rounds` driver warps actual 1/60s simulation ticks with the existing bot and choices, without fabricating
clears or outgoing characters. UI navigation uses `Input.parse_input_event`. The existing map-start click fixes
only the diagnostic seed. On replay the saved JSON numbers are normalized on both sides before comparing.
The natural second round uses seed 1 (distinct from the chain harness's derived seed), dies at 841.583s/Lv58,
and archives one cleared tier/two rounds. Cancel leaves the spare alive; confirmed deletion archives it too.

## Visual evidence checked by eye

All files below are local, ignored under `evidence/t75/`; none is committed or uploaded.

- `rounds_pass/01_character_select.png`, `02_creation_gender.png`, `03_creation_name.png`,
  `04_creation_look.png`, `14_selected_carried_character.png`: v83 book/signboard, disabled empty actions,
  staged creation, selected Cleric details and carried outfit.
- `rounds_pass/09_map_select_tier1.png`, `12_free_market_arrival.png`, `15_free_market_out00.png`,
  `16_map_select_tier2.png`, `18_quit_round_warning.png`: correct tier offerings, walkable hub/exit,
  full boundary pools and readable loss warning. The roster-name defect below is visible in tier 2.
- `rounds_pass/21_results_died.png`, `22_delete_confirmation.png`, `23_history_died.png`: natural death,
  correct identity/level/tier/round counts, deletion warning and died/deleted history.
- `bosses/6300005_attack1_{windup,impact}.png`, `8220009_attack{1,2,3}_{windup,impact}.png`,
  `8130100_attack{1,2,3}_{windup,impact}.png` and `8130100_attack2_flight.png`: all bosses, their stance/effect
  changes and Balrog's projectile. Existing diagnostic boss driver suppresses ordinary spawns/damage and
  positions the encounter; these are attack-presentation probes, not natural fight durations.
- `victory_staged/21_results_victory.png`, `23_history_victory.png`: Victory, two cleared tiers/two rounds,
  freed character slot and victory/deleted history. This supplementary path uses tier-2 invulnerability and
  diagnostic lethal boss hits after 15:00, then real death/reward/clear handling. It is **not a natural clear**.
- `full_final/` exercises keyboard movement, manual job/card choices, pause/resume, death, saved-round Continue,
  history and return to title; `19_death_tombstone.png` now visibly shows the tomb before results.
  `clear_pass/01_clear_notice.png` and `02_results_clear.png` show one-off clear
  and results without persistent progress; `title/01_title.png` and `import/01_import_screen.png` cover boot UI.

`rounds_pass`, `victory_staged`, `full_final` and `clear_pass` summaries report `missing=[]`;
the driver retains misses from disposed scenes and checks renderers and optional-art widgets too.
All seven boss records have `missing=[]`, `warnings=[]` and both captures present.
Import ran the supported screen-only scenario with an empty evidence-local cache; no WZ import was rerun,
as the implementer brief forbids importing when the manifest is unchanged. An actual import round trip is not
new evidence from this ticket. Reused cache, read-only: `C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t70`.

## Findings and limits

- **Filed [#90](https://github.com/itechify/maple-survivors/issues/90)** (`bug`, `needs-triage`): Dark Cave's long
  map-select roster names overflow their 58px cells and run together. Checked the screenshot and the
  word-wrap/centering consumer; visual layout work is outside this QA/docs ticket.
- **Fixed here:** driver modal timing (hub Save & quit and reopened deletion confirmation), JSON numeric
  comparison, complete missing-asset collection and screenshot write failures. Accelerated `clear` could read
  a disposed RunScene after awaiting a screenshot; copy its summary before yielding and return the clear
  presentation to normal speed. Likewise the full driver's accelerated `death_tombstone` shot had already
  reached results; return the end sequence to normal speed before capturing it. Final runs pass these paths.
- **Fixed here:** stale Running/Playtests instructions, single-stage terminology and obsolete Retry description;
  document the scenario, persistence contract and diagnostic limits. No new glossary term or ADR is needed.
- **Known owner fix-up, untouched:** stray dropdown frame in the creation gender prompt, visible in the new capture.
- **Known deferred behavior, unchanged:** ordinary mob attacks/Seal/Curse (#76), tier-2 balance (#77), and
  the existing type-1 attack interpretation caveat. Tree's early deaths and low tier-2 clear sample reproduce
  the prior smoke; they are not newly introduced defects or grounds to tune this feature ticket.
- Invulnerability alone timed out in the initial supplementary victory probes. Those failed staging attempts
  are retained in ignored logs and are not clear-rate evidence; the final explicit terminal probe is labeled
  `diagnostic_victory=true`. Natural flow QA uses the successful death scenario instead.

The regression table and conditional boss observations are in GAME_DESIGN 4.2; exact console/SYSTEMS output,
seed/configuration context and JSON records remain in `evidence/t75/smoke/`.

## Validation

`ISOLATE=t75` for every Godot invocation. The full suite runs after the required final fetch/merge of
`origin/t3/issue-32-implementation` (`dba59a9`, already current): **732 tests, 0 failed, 0 skipped,
81 files, 365.466s**. Every real-cache check executed; there is no SKIP to count as evidence.
Final committed-code log: `evidence/t75/full_suite_head.log` (the earlier full pass is `full_suite_final.log`).
No importer code/assets changed, so Rust tests and WZ import were not rerun.
The natural `rounds`, supplementary staged victory, `full`, one-off `clear`, `title`, screen-only `import`
and seven-attack boss probe all exit 0 on their final executions. All required screen families were checked by eye.
