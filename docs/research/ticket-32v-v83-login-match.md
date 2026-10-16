# Spec 32 visual-fidelity pass

Branch: `spec32/v83-login-match`, based on integration `5651835`. Implementation commits:
`9985f68` (layout and #90) and `d68cbb7` (keyboard hint above the selected beam).
The final report commit follows these. No PR, issue comment or issue closure was created.

Character select now uses the registered camera, roster/shadow/name-tag anchors, Explorer lanterns,
independent signboard buttons and opaque page arrows. Its compact details scroll follows selection;
the beam is registered against the new feet. Original left-edge step, Back and View All Characters art
restore the book composition, with the latter relabelled Run history. The offline keyboard hint stays
above the beam. No world/channel plaque or invented server text is shown.

NewChar uses the period settings/name boards, option arrows, preview feet and separate OK/Cancel pairs.
Name OK validates before appearance; Cancel returns to the preceding phase, and creation still commits
only through SceneFlow. A bounded advisory and the survivor weapon strip sit to the left of the preview.
The gender picker occupies the dropdown baked into Gender/text/0, removing the detached empty frame
and redundant appearance arrows. Title uses the registered forest/sign and puts offline Start in the
Login region, Re-import on the middle plank and Quit at the lower right. #90 names fit inside their
roster cells, including balanced Tauro/macis and Tauro/spear lines.

Changed modules: `character_select.gd`, `character_create.gd`, `title_screen.gd`, `stage_select.gd`,
`login_backdrop.gd`, new `login_history_button.gd`, `character_driver.gd`, and `test_ui_flow.gd`.
No survivor/canonical data keys, manifest, importer, simulation or SceneFlow seams changed.
Changed constants and provenance are recorded in GAME_DESIGN section 11.

All references remain outside the repository at
`C:/Users/itech/Coding/maple-survivors-refs/research/spec32/v83-login-refs/`.
The original reference files were not copied into the repository. Derived side-by-side comparisons
and game captures are local, gitignored evidence only.

The following captures and comparisons were inspected by eye. Every comparison is **ours | reference**.
Paths in the last column are relative to `evidence/t32v/compare/`; matching standalone captures are
in `evidence/t32v/screens/`.

| Screen/state | Reference matched | Remaining differences / reason | Comparison PNGs |
|---|---|---|---|
| Character select, 0/1/3 | Primary v0.83 `charselect_1.png` | Different character names/looks and enabled states; empty silhouettes use original WZ art. Selected details/light are absent from that reference state. Offline plaques/hint copy replace online concepts; original GMS Start art differs from Royals wording. Animation phase differs. | `empty_slots.png`, `one_character.png`, `three_characters.png` |
| Selection changes, keyboard focus | Period 2009 v0.73 `charselect_2.png` | Same selected-relative compact scroll; exact v83 selected-scroll anchor remains unverified. Native v83 scroll width is retained. This combines period selected-state evidence with primary v83 button/camera/lantern registration; v0.73 lacks those lanterns. No online ranking; zero fame. Beam anchor remains tier C. | `selection_changed.png`, `selection_third.png`, `keyboard_focus.png` |
| Delete confirmation | Primary roster plus original Basic/YesNo3 | No period deletion-popup capture supplied. Existing survivor confirmation wording and notice family retained. | `delete_confirmation.png` |
| History entry / list | `charselect_1.png` View All Characters site | Original angled frame/arrow retained; inner label patch is tier C. Run history itself has no original-client counterpart and retains the existing parchment/list. | `history_entry.png`, `history.png` |
| Creation, male and female | Period `newchar_1.png`; original v83 charSet, rows and buttons | Offline advisory facts and weapon strip are additions. Canonical option names, selected looks, animation/cloud phase and video compression differ. Preview estimate and backdrop registration have a few pixels of uncertainty. No world plaque. | `creation_male_default.png`, `creation_female_default.png`, `creation_male_hair_colour_changed.png`, `creation_female_hair_colour_changed.png`, `creation_male_weapon_changed.png`, `creation_female_weapon_changed.png` |
| Name / invalid name | Period `newchar_name_1.png` | Same short board, input and OK/Cancel composition. Name requirements/errors are offline additions; preview look, clouds and compression differ. | `creation_name.png`, `invalid_name.png` |
| Gender, male/female | Original WZ Gender art; comparison against `ours_gender.png` is explicitly prior implementation only | No trustworthy period capture. Centered parchment, text, buttons and native picker over the baked field are a tier C choice, not claimed original absolute coordinates. | `gender.png`, `gender_female.png` |
| Title | `title_1.png` geometry, `title_2.png` English composition | Original shared forest pixels register almost exactly. Localized footer/version differ. No account fields; offline Start placement and three-action adaptation remain tier C. | `title.png` |
| Tier-2 map select, #90 | Prior #75 `14_map_select_tier2.png` | Survivor-only screen: no period-client equivalent. Diagnostic character/tier heading differs; original canonical names remain complete inside separate cells. | `map_select_tier2.png` |

Fresh registration corrected two approximations in the supplied research: Back is `(0,425)`
(zero sampled channel error against original WZ art), View All Characters `(0,375)`, rather than
approximately y450/400. The select plaque is Common/step/2; /3 is creation. Fresh name-board matching
gave `(480,95)`, rather than the earlier `(475,95)` estimate. Title forest registration gave camera
`(28,-11)` with mean sampled channel error 0.004; creation cap/branch gave `(37,-3007)` approximately.
These corrections preserve the reference intent and are documented next to the constants.

Verification uses `ISOLATE=t32v`, with independent scratch project mirrors for concurrent checks.
The asset manifest already imports all Login.img art, so no private cache or import was needed.
All cache reads used `C:/Users/itech/AppData/Roaming/MapleSurvivors/asset_cache/v83`; the shared cache
was not modified. The import-screen probe points at an empty evidence cache and never invokes the importer.
No balance smoke was run, as explicitly requested; no gameplay/balance claims are made.

Final verification:

- Red checks reproduced the original roster anchor and fixed-scroll defects, then the absent bounded-name seam.
  Focused UI tests passed after implementation: 22 passed, 0 failed, 0 skipped.
- After fetching and merging the latest integration (already up to date), the final full suite passed:
  **733 passed, 0 failed, 0 skipped, 81 files, 312130 ms**. No cache-dependent test was skipped.
  Log: `evidence/t32v/full-tests-final.log`. An earlier full run also passed 733/0/0.
- Final character probe: exit 0, **23 captures**, `missing=[]`; log `evidence/t32v/character-final.log`,
  summary `evidence/t32v/screens/summary.json`. All requested screen/state comparisons were inspected by eye,
  including both genders' changed hair/weapon previews and the corrected hint layer. There are **21 composites**.
- `full`: exit 0, 10 level-up windows, Magician and pause/resume checks true, `missing=[]`;
  log `evidence/t32v/flow_full.log`, summary in `flow_full/summary.json`.
- `rounds`: exit 0, boundary replay, carry, mouse/keyboard selection, delete and history checks passed;
  `failures=[]`, `missing=[]`. Log `evidence/t32v/flow_rounds.log`; actual carried-character tier-2 capture
  `evidence/t32v/flow_rounds/16_map_select_tier2.png` also inspected for #90.
- `clear`: exit 0 at 8x, clear notice/results/character-select/title path and unchanged one-off save checks passed;
  `cleared=true`, `missing=[]`. Log `evidence/t32v/flow_clear_x8.log`; summary in `flow_clear_x8/summary.json`.
  An exploratory 32x uncapped attempt missed the short end-state observation and the existing driver polled a
  freed RunScene. It was stopped and repeated successfully at 8x; no simulation or flow code was changed for it.
- `import`: exit 0, empty-cache import screen only, intentionally no `--wz` and no import/reimport.
  Log `evidence/t32v/flow_import.log`, capture `flow_import/01_import_screen.png`.
- `git diff --check` passed. Rust tests were not needed: importer and asset loading are unchanged.

No acceptance item is left unimplemented. The evidence limitations and deliberate offline differences are
listed per screen above; gender, offline title controls and the exact selected-effect registration remain
explicit tier C choices. There is no new private cache path and no balance smoke.
