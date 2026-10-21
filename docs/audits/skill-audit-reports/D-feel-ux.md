# D — Game feel, visuals, audio and UX audit

Build reviewed: `a68e74f`; review date: 2026-10-21. Read-only audit. No source, assets, settings, saves or balance data changed. No generated art. Findings distinguish source-proven defects, observed readability concerns and unmeasured risks.

## 1. Skills read and application

All nine complete SKILL.md files were read from `C:/Users/itech/.t3/projects/maple-survivors/.agents/skills/`:

- `game-feel/SKILL.md`: discrete feedback hooks, importance hierarchy, noise versus useful feedback. Applied to hits, pickups, rewards and deaths; did not prescribe generic shake, hit-stop or squash/stretch over v83 sprites.
- `game-ui-ux/SKILL.md`: responsive layout, focus, screen flow and HUD update boundaries. Applied to windows, menus, HUD and browser shell.
- `godot-ui-control/SKILL.md`: Control focus/input, custom widgets and resize behavior. Art-sized v83 windows are appropriate here; converting them all to stock Containers is not recommended.
- `camera-systems/SKILL.md`: frame-independent follow, process ordering, bounds and low/high-refresh verification. Applied to CameraRig and its presentation target; motion quality remains unverified by stills.
- `audio-design/SKILL.md`: bounded polyphony, mix hierarchy, headroom and listening acceptance. Applied to event coalescing, SFX allocation and BGM transitions; no pitch randomization or adaptive soundtrack demanded for authentic WZ audio.
- `godot-audio/SKILL.md`: bus routing, crossfades, volume conversion and playback lifetime. Applied to AudioService and the shipped bus layout.
- `godot-animation/SKILL.md`: animation ownership, transient feedback lifecycle and UI tweens. Applied to the custom WZ animation clocks and window transitions; replacing those clocks with AnimationTree is inappropriate.
- `input-systems/SKILL.md`: action mapping, rebinding conflicts, live prompts, accessible keyboard operation. Applied to InputMap, KeyBindings, run/hub handlers and menus. Movement retuning, coyote time and controller/touch expansion were excluded.
- `create-game-assets/SKILL.md`: only inspect-before-inventing, cohesion, original/proprietary provenance and native-scale contextual validation. No scripts or generation were run.

Additional reference files read in full under that same skill root:

- `input-systems/references/buffering-and-accessibility.md` — prompt/remap/accessibility guidance only; movement suggestions rejected under the owner constraint.
- `create-game-assets/references/art-direction.md` — native-scale/context checks and preserving the existing family.
- `godot-audio/references/buses-and-effects.md` — bus graph, polyphony and effects options; runtime bus creation advice explicitly overridden by the documented Godot web issue.

## 2. Scope and verification record

Read the complete common brief first, repository AGENTS.md, GLOSSARY.md, ADRs 0001–0005, ARCHITECTURE presentation/sharp-text/web sections and sim/presentation contract, GAME_DESIGN controls/presentation and relevant combat/reward/economy/provenance sections, ASSET_PIPELINE audio/runtime consumption, RESEARCH §6 and IMPLEMENTATION_PLAN performance evidence. This is a focused domain read, not a claim to have read every historical balance table.

Source inspected: CameraRig; RunScene event mapping, player presentation, held-run behavior and input; FreeMarket; AvatarRenderer/FxRenderer/MobRenderer/ProjectileRenderer/DamageNumbers; AudioService and `default_bus_layout.tres`; Hud and its status/skills/messages/quickslot/buff/boss widgets; WindowStack/UiWindow/WzButton/TitleButton; choice/job/pause/Skill/KeyConfig/Options/Equip/Item/shop/tooltip paths; title/creation/map-select/results/Cash Shop; Settings/KeyBindings; project display/input configuration; README controls; web index/CSS/shell and the architecture's import protocol.

Commands/checks:

- **Passed (exit 0):** PowerShell `Get-Content`/`Get-ChildItem` and focused `rg` inspections; read-only `gh issue list --repo itechify/maple-survivors --state all --limit 300`, and issue views #85, #87, #118, #121, #218–#224, #231. No gh writes. Issue list showed only #46/#77 open.
- **Passed:** PNGs listed below opened using `view_image` and examined by eye. They were read in place, never copied or redistributed.
- **Non-product command failures:** early `rg` calls using Windows wildcard path arguments returned path errors (exit 2); corrected to directory searches. An interpolation search returned exit 1 (no matches). Three guessed older screenshot names were missing; the actual filenames were enumerated and opened. These are audit navigation errors, not game failures.
- **Not executed:** no Godot/cargo/node processes or additional playtests launched by this auditor. Central verification owns these checks; PERF_DONE was removed while the lead reran fixture density measurements, so the quiet-machine constraint was respected.
- **Not executed:** direct listening on headphones/speakers, actual keyboard-only/browser automation, 60 versus 164 Hz motion capture, resize reproduction and new synthetic repro tests. Static input/geometry findings below identify that limit explicitly.
- **Lead evidence:** first perf wrappers exited 0 but died before the requested density interval: Henesys 4:19/Lv7, Tree 0:47/Lv1. This is not a late-density pass. Lead `NOTE_PERF.md` acknowledges it. The replacement F/P fixture density run completed with exit 0 and produced real 10:00–13:00 frames; its character starts as the committed Lv38 fixture, not a fresh character. No balance inference is made from it.

Screenshot inventory examined (paths below use `M = C:/Users/itech/.t3/projects/maple-survivors/evidence`, `A = C:/Users/itech/.t3/worktrees/maple-survivors/t3-eb28f480/evidence/skill-audit`):

- **Current build, 2026-10-21:** `A/perf/density_hg_s2026/death_land.png`, `A/perf/density_tree_s2026/death_land.png`; `A/perf/density_hg_s2026_fixture_fp/{t720,t780,boss_windup_1_attack1,hit_first}.png`; `A/perf/density_hg_s2026_fixture_fighter/{t780,final_attack_sword_fighter_followup}.png`; `A/perf/finale_hg_s2026_fixture_fp/{t900,clear}.png` (1600×1200).
- **Earlier QA, 2026-10-18; corroboration only:** `M/playtest3/qa/full1/{01_title,04_creation_look,05_map_select,08_levelup_2,20_results_death}.png`; `M/playtest3/qa/keys1/{04_key_config,06_options}.png`; `M/playtest3/qa/shops1/06_shop_selected.png`; `M/playtest3/qa/inventory1/06_item_tooltip.png`; `M/playtest3/qa/web/web_import_screen.png`; `M/playtest3/t224/perf_after_2/t720.png`. Older screenshots are not used to assert current regressions in areas subsequently changed.

Fresh VISUAL_DONE/FLOW_DONE coverage and final pending status are recorded in the addendum at the end; do not treat an absent scenario as a pass.

## 3. Strengths worth preserving

- **Cohesive original presentation:** current Henesys/Tree stills preserve WZ silhouettes, map layering and pixel texture; older creation, shop, inventory and result screens demonstrate consistent v83 art and restrained typography. No restyle is warranted. Preserve the title as the project's own original branding and the WZ import boundary.
- **Actual event feedback exists:** RunScene maps hits, deaths, pickup audio/notices, rank effects, job pillars, boss arrival and clear feedback (`game/scripts/run/run_scene.gd:1045`, `:1329`, `:1382`). Damage numbers have hold/fade/stack behavior; mob animations honor WZ frame/alpha data. These systems should be refined rather than replaced.
- **Window pause/stack protocol is thoughtful:** choice windows can coexist with inspection windows; Esc closes the front inspection window before pause; world/HUD animation freezes with inspection (`game/scripts/run/run_scene.gd:436`, `:1579`). SkillWindow already has custom arrow/tab navigation (`game/scripts/ui/windows/skill_window.gd:100`), a useful model for other art-based windows.
- **Sharp-text work is present:** `project.godot` uses canvas_items/integer scaling and snapping. The 1600×1200 fresh shots show readable font text while sprite/digit edges remain pixel-based. The owner-selected crisp font is intentional (#224 / architecture sharp-text section); no AA toggle or font-size rewrite proposed.
- **Camera fundamentals are sound in source:** exponential `1-exp(-rate*dt)`, a dead zone, viewport-aware clamping, integer top-left alignment and processing after player movement (`game/scripts/render/camera_rig.gd:36`, `:86`, `:98`). No shake/hit-stop is preferable to introducing routine full-screen noise without an owner request.
- **Audio has bounded resources and a working platform strategy:** two BGM players crossfade, 16 pooled SFX voices prevent node churn, per-frame sound-path coalescing limits swarm duplication, settings use dB conversion and the static BGM/SFX bus layout preserves the web-audio fix (`game/scripts/audio/audio_service.gd:34`, `:56`, `:90`, `:143`; `game/scripts/run/run_scene.gd:1414`). Location music remains appropriate for v83; absence of adaptive stems or boss music is not a defect.
- **HUD state is meaningfully separated:** cooldown sweeps redraw only when their quantized state changes, bindings refresh through Settings.changed, boss warnings have a separate queue, and the requested v83 quickslot is implemented. Do not re-report #219 tabs, #220 quickslot, #221 region naming or #222 auto-equip as missing.

## 4. Findings

### D-1 — Dense damage-number columns compete with the combat silhouette

- **Category / severity / type:** combat readability; **Medium; UX concern**.
- **Evidence:** opened current `A/perf/density_hg_s2026_fixture_fp/t720.png` (239 mobs) and `t780.png` (270 mobs), plus `hit_first.png`. Multiple near-coincident orange/yellow stacks form tall opaque columns over the central/right combat area; the purple player-number channel and the character/nearby attacks compete with them. Fighter `A/perf/density_hg_s2026_fixture_fighter/t780.png` (219 mobs) and F/P finale `A/perf/finale_hg_s2026_fixture_fp/t900.png` (322 mobs) corroborate the same congestion. This is an observed still-image hierarchy problem, not a claim that the player is invisible throughout a moving run. `game/scripts/render/damage_numbers.gd:33`–`:39` keeps up to eight rows per target, and `:190` stacks by target key rather than screen-space congestion; RunScene adds numbers for every hit (`game/scripts/run/run_scene.gd:1316`) into the top world layer (`:667`–`:684`).
- **Skills applied:** game-feel — scale feedback to importance and avoid burying it in noise; create-game-assets — silhouettes must read at native size in real context; game-ui-ux — information hierarchy.
- **Impact:** damage output becomes the loudest visual channel during the exact moments when locating the character, a boss windup and damage taken matters most.
- **Recommendation:** prototype an optional reduced dealt-number density policy (presentation only), with player damage/recovery and boss attack cues protected. Keep original WZ digits, default timings and effects at ordinary density; evaluate a local overlap limit or fewer simultaneously displayed outgoing stacks rather than shrinking/repainting all art. No new proprietary asset distribution.
- **Effort / confidence:** M / **Confirmed concern in inspected frames**; effect on active play needs validation.
- **Acceptance:** compare identical 200–300-mob fixture segments at normal speed, with and without the presentation option. Character position, incoming damage and a mushroom windup must remain identifiable; ordinary 1–3-target combat keeps its v83 number appearance; sim event bytes remain identical.
- **False positive if:** the columns are fleeting and improve tracking in motion enough that players prefer the current policy. Stills confirm overlap; a controlled moving A/B was not performed.
- **Known/intentional check:** GAME_DESIGN §6.3 and architecture keep authentic digits/timings; #224 deliberately preserves bitmap digits. This finding does not dispute either choice or suggest a balance change.

### D-2 — F3 can be assigned to a window action which the run then intercepts

- **Category / severity / type:** rebinding correctness; **Medium; Confirmed bug (source-proven; runtime repro not executed)**.
- **Evidence:** KeyConfig draws an F3 drop target (`game/scripts/ui/windows/key_config_window.gd:34`); `KeyBindings.bind` accepts keys unless fixed (`game/scripts/core/key_bindings.gd:89`), but fixed keys (`:154`) exclude F3. RunScene `_unhandled_input` consumes F3 and returns before `handle_hotkey` (`game/scripts/run/run_scene.gd:424`–`:430`). Bind Stat/Skill/Equip/Item to F3, save, close windows, press F3 during a round: the perf overlay branch wins. This claim specifically concerns window actions; potion/skill latches run earlier and jump also has a polling path.
- **Skills applied:** input-systems — conflict detection must cover every input consumer; game-ui-ux — prompts and actions must agree.
- **Impact:** the UI/HUD advertises a saved key that cannot open its window in a round.
- **Recommendation:** make the performance action participate in the fixed-key contract, or move its shortcut so user binding takes precedence. Show its reserved role in Key Config if retained.
- **Effort / confidence:** S / **Confirmed by control flow**.
- **Acceptance:** a focused input test dispatches through `_unhandled_input` (not only `handle_hotkey`); F3 is either rejected/captioned as reserved or actually opens the selected window without an unwanted overlay. Verify desktop and web.
- **False positive if:** another pre-dispatch layer rejects F3 bindings. Checked KeyConfig/model/Settings paths; none does.
- **Known/intentional check:** README documents F3 perf; #87 and current GAME_DESIGN define fixed movement/Esc/card keys, but do not resolve the overlap. No duplicate issue found in the full issue-title inventory.

### D-3 — The Free Market instruction line ignores the chosen movement and NPC Chat bindings

- **Category / severity / type:** input discoverability; **Medium; Confirmed bug (source-proven)**.
- **Evidence:** `game/scripts/run/free_market.gd:317` hard-codes `Up at the exit` and `Space: talk to a scroll NPC`. Actual interaction uses the `npc_chat` action (`:204`) and movement uses the selected movement set. The older opened `M/playtest3/qa/shops1/06_shop_selected.png` shows that exact instruction line; current source still contains it. Rebind NPC Chat from Space to F, or switch movement to WASD: the hub still tells the player Space/Up. Legacy Space-as-jump settings intentionally leave NPC Chat unbound, making the hint particularly misleading.
- **Skills applied:** input-systems — prompts follow bindings/device state; game-ui-ux — discoverability.
- **Impact:** a player following the prominent hub help may fail to talk or leave; keyboard-only operation can appear broken despite a valid binding.
- **Recommendation:** compose those two prompts from the live action labels and refresh them on Settings.changed. For unbound NPC Chat, explicitly offer Key Config or the existing double-click alternative. Keep the same v83-style help plate.
- **Effort / confidence:** S / **Confirmed**.
- **Acceptance:** hub hint updates live after remapping NPC Chat and changing to WASD; unbound interaction is explained without displaying a nonfunctional Space prompt. Persistence behavior stays unchanged.
- **False positive if:** the line is only a literal-controls tutorial unrelated to actual controls. Checked: it is the live hub's only prominent instruction and conflicts with its action handlers.
- **Known/intentional check:** #85/#87 movement choices and #111/AGENTS legacy Space migration are intentional. This is a stale prompt, not a request to migrate existing bindings or restore Space automatically.

### D-4 — Window positions are not recovered when the logical view shrinks

- **Category / severity / type:** responsive window management; **Medium; Confirmed geometry defect in source; visible reproduction pending**.
- **Evidence:** `WindowStack.open` restores `_positions` verbatim (`game/scripts/ui/windows/window_stack.gd:45`–`:50`); `_remove` records coordinates (`:152`–`:155`). There is no resize handler in WindowStack. `UiWindow.clamp_to_view` only runs while dragging (`game/scripts/ui/windows/ui_window.gd:90`–`:105`). Example: in a 1066×600 logical wide view, move a 120 px window to x=1000, close it, resize to an 800×600 logical view and reopen; x stays 1000 and the entire window is outside the view. The same occurs for an already open window. Default expand mode can cause this; fill-window is not required.
- **Skills applied:** game-ui-ux — verify responsive layout across aspect changes; godot-ui-control — anchors alone do not fix restored manual offsets.
- **Impact:** an invisible inspection window can keep the run paused. Esc still closes it, so this is recoverable rather than a hard lock, but reopening restores the same unreachable position.
- **Recommendation:** clamp restored positions to the current view and re-clamp open windows on logical size changes, preserving at least the title-bar recovery area and the owner's per-window position memory.
- **Effort / confidence:** S / **Confirmed geometry path; screenshot/manual resize not executed**.
- **Acceptance:** a focused WindowStack test shrinks its logical bounds after closing/opening and while a window remains open; its title remains reachable. Verify 16:9→4:3 and portrait→landscape without changing sharp-text metrics.
- **False positive if:** an external host repositions all windows on resize. Searched WindowStack, UiWindow, RunScene and Settings; only shop-button/viewport fitting paths were present. Existing stack tests cover drag bounds and remembered positions, not shrinking bounds.
- **Known/intentional check:** #224 documents expand/fill/fractional policies; #85 intentionally remembers positions. Neither requires remembering an unreachable coordinate.

### D-5 — Keyboard operation is incomplete outside the choice and Skill windows

- **Category / severity / type:** keyboard accessibility; **Medium; proposed improvement**.
- **Evidence:** UiWindow defaults to FOCUS_NONE and a no-op `handle_key` (`game/scripts/ui/windows/ui_window.gd:46`, `:74`). Options and Key Config provide mouse/drag handlers but no keyboard override (`game/scripts/ui/windows/options_window.gd:194`, `game/scripts/ui/windows/key_config_window.gd:215`); inventory/shop selection likewise depends on mouse. WzButton defaults to FOCUS_NONE (`game/scripts/ui/widgets/wz_button.gd:60`), whereas SkillWindow explicitly implements arrows (`game/scripts/ui/windows/skill_window.gd:100`). TitleButton also disables focus (`game/scripts/ui/widgets/title_button.gd:43`), leaving existing web Export save/Import save/Fullscreen/Re-import controls mouse-only; title Enter only starts. Opened old keys/options/shop/inventory screenshots confirm the actual art-based surfaces, not a hypothetical standard Godot menu.
- **Skills applied:** game-ui-ux and godot-ui-control — visible initial focus and navigation; input-systems — accessibility and remapping as an operable workflow.
- **Impact:** players who can move, pick cards and pause on keyboard must still switch to a mouse to adjust volume, rebind a key, wear/sell an item or use web save backup.
- **Recommendation:** incremental custom focus handling that preserves all v83 art/drag behavior: first Options rows and KeyConfig action→key selection/OK/Cancel; then inventory/shop selection and existing title utility buttons. Use the SkillWindow/choice model rather than enabling global Space=accept over gameplay.
- **Effort / confidence:** M per surface / **Confirmed input limitation; improvement rather than broken stated mouse contract**.
- **Acceptance:** without a mouse, change volume, bind an action and confirm/cancel, inspect/equip an inventory item and complete a shop transaction; existing keyboard choices and jump do not double-activate UI. Existing web utility buttons can receive visible focus and activate.
- **False positive if:** keyboard-only support was deliberately rejected for these desktop surfaces. #87 explicitly excludes controller bindings, not keyboard operation; no general keyboard-only promise is claimed here. Mouse workflows are intentional and retained.
- **Known/intentional check:** #85/#87/#108/#118 define v83 mouse/drag workflows; this is additive access. The known deferred title Options entry in #87 is not reported as a new missing feature.

### D-6 — Important cues share an oldest-voice-stealing pool with routine swarm sounds

- **Category / severity / type:** audio feedback hierarchy; **Medium; maintainability risk**.
- **Evidence:** `game/scripts/audio/audio_service.gd:11`, `:90`–`:120` uses one 16-voice pool for all `play` requests and steals the oldest active voice regardless of role. UI sounds route to that service through UiArt; RunScene sends mob Damage/Die, pickup, potion, job, tombstone and clear sounds there (`game/scripts/run/run_scene.gd:1109`, `:1150`, `:1161`, `:1386`, `:1401`). Per-frame/path coalescing (`:1414`) limits duplicates but does not reserve a cue after it starts. Sixteen later requests can replace an important still-playing voice. No claim of actual clipping or observed inaudibility is made: this audit did not listen or measure active-voice contention.
- **Skills applied:** audio-design — importance hierarchy and bounded one-shots; godot-audio — polyphony and playback lifetime.
- **Impact:** future higher-variety swarms or rapid feedback can truncate meaningful potion/reward/UI cues even while the node count remains bounded.
- **Recommendation:** add a small priority/reservation policy within the existing bounded pool; routine hits should yield before job/death/reward/UI cues. Add stolen/dropped-by-role diagnostics before changing the mix. Keep WZ samples and static bus creation; do not introduce randomized pitch or more concurrent voices as the default fix.
- **Effort / confidence:** M / **Likely risk; audible severity needs validation**.
- **Acceptance:** synthetic priority-allocation test plus recorded/listened normal-speed dense fixture playback; important cues finish, routine repetition stays controlled, voice bound remains fixed, desktop/web buses still connect and volume/mute settings work.
- **False positive if:** measured real sessions never approach 16 active voices or important clips always finish before contention. Not checked; that is the first validation gate, and the risk can be closed without implementation if evidence supports it.
- **Known/intentional check:** the existing oldest-first allocator/test is deliberate, architecture §4.5/§10 documents bounded SFX and the web bus fix. This proposes importance-aware allocation, not replacement with unbounded players. #121 intentionally defers low-HP warning audio/flashing; it is not reported missing.

### D-7 — The low-MP action cue persists over the death presentation

- **Category / severity / type:** terminal-state feedback; **Low; Confirmed bug (observed)**.
- **Evidence:** exact current PNGs `A/perf/density_hg_s2026/death_land.png` and `A/perf/density_tree_s2026/death_land.png`: tombstone landed, HP zero, yet the red `Not enough MP` prompt remains. `HudMessages.low_mp_visible` checks only cached `mp_short` (`game/scripts/ui/hud_messages.gd:25`–`:26`); RunScene death mapping sets the tombstone/end sequence without suppressing this action cue (`game/scripts/run/run_scene.gd:1382`).
- **Skills applied:** game-feel — transient feedback must communicate the relevant event; game-ui-ux — state-appropriate information hierarchy.
- **Impact:** the death moment retains a combat-affordability instruction that cannot be acted on and competes with its terminal message.
- **Recommendation:** hide affordability cues for dead/cleared/ending states while preserving the ordinary living low-MP hint. Also verify a level-up MP refill refreshes the cue before showing a paused choice.
- **Effort / confidence:** S / **Confirmed**.
- **Acceptance:** screenshot/test for death while mp_short=true has no low-MP cue; a living ready unaffordable skill still shows it; refill behavior is checked separately rather than assumed.
- **False positive if:** the red line is a timed historical log entry. Checked: it is drawn as a persistent cue in `_draw`, independently of the message queue.
- **Known/intentional check:** #9/#82 intentionally show MP waiting; #144 fixes absorbed-hit art, a different issue. No owner decision requires an active MP warning after death.

### D-8 — README controls direct players to obsolete bindings and pause behavior

- **Category / severity / type:** onboarding documentation; **Low; Confirmed bug**.
- **Evidence:** README `:48` implies arrows and A/D both move, `:55` says MP potion is `End (or E)`, `:58` says pause quits to stage select; the table omits Stat/Skill/Equip/Item and Dash. Current `project.godot` binds E to Equip and only End to MP; Settings selects one movement set; GAME_DESIGN §2 documents the current stack and Quit round behavior. Existing KeyConfig/Options screenshots show those actual actions.
- **Skills applied:** input-systems — discoverability and prompt consistency; game-ui-ux — clear onboarding.
- **Impact:** a new player presses E expecting emergency MP and instead opens Equip/pauses, or tries inactive WASD. Basic inspection features are harder to discover.
- **Recommendation:** update the controls table to match GAME_DESIGN §2, including movement-mode qualification, window keys, learned skill keys, NPC Chat and the round-replay warning. No changes to bindings.
- **Effort / confidence:** S / **Confirmed**.
- **Acceptance:** compare every documented default against project InputMap/current Settings and pause/window behavior. Mention remapping; use current player terminology and never expose “canonical” in instructions.
- **False positive if:** README intentionally describes a legacy build. Checked: it presents itself as current setup/play instructions with no legacy qualifier.
- **Known/intentional check:** #85/#87/#108/#111/#188 and AGENTS controls explain the changes; no intentional reason found to keep contradictory instructions.

### D-9 — Web import accessibility semantics are incomplete despite clear visual copy

- **Category / severity / type:** browser accessibility; **Low; UX concern**.
- **Evidence:** `web/index.html:147` has an input-url field with only `placeholder="https://"`, no label/aria-label/aria-labelledby; nearby explanatory paragraphs are not programmatically associated. `run-bar` at `:161` is likewise unnamed. Source tabs use tab/tablist/tabpanel roles (`:123`–`:141`) but have no panel ID/aria-controls/aria-labelledby linkage; `selectTab` (`shell.js:178`) changes selection/visibility only. CSS provides good focus-visible outlines (`shell.css:219`), but `setScreen` (`shell.js:44`) hides the triggering screen without moving focus to the next one. The earlier actual import screenshot was opened; this is a source semantics concern, not a claim of visual breakage or an automated accessibility-test result.
- **Skills applied:** game-ui-ux — visible/logical focus and clear state transitions; input-systems — accessible keyboard interaction; godot-ui-control focus principles applied conceptually to the shell, without using Godot APIs in web code.
- **Impact:** assistive navigation gets weaker context than a sighted mouse user, and keyboard focus may be lost after starting/cancelling an import or entering an error screen.
- **Recommendation:** label the URL/progress controls, link tab/panel semantics, support the selected tab's keyboard navigation and place focus on the relevant heading/action after screen changes. Retain current colors/art/layout and local-only import protocol.
- **Effort / confidence:** S / **Confirmed markup omissions; focus behavior needs browser validation**.
- **Acceptance:** browser accessibility snapshot names the URL field and progress; keyboard can select all source tabs, start/cancel, recover from an error and return to the game with visible focus; no extra network requests or JavaScriptBridge added.
- **False positive if:** another script supplies these attributes/focus behavior at runtime. Searched index/shell; it does not. No screen-reader/browser focus session was executed.
- **Known/intentional check:** #133/#136/#148 cover import/storage/browser QA, not these semantics. The persistence prompt fix and accepted Esc/fullscreen/browser-reserved keys are explicitly not re-reported.

## 5. Considered and rejected

- No generic screen shake/hit-stop/squash/stretch request: preserving v83 movement/appearance and avoiding input stalls takes precedence over skill defaults.
- No movement/coyote/gravity/knockback retune: movement is owner-approved; #223 deliberately keeps the full knockback guard while allowing damage during it.
- No controller/touch backlog disguised as a defect: #87 excludes controller bindings and the web target is desktop browsers.
- No missing tab art, missing quickslot, redundant gender step, map-name wording or lack of auto-equip findings: #218–#222 are implemented; source and newer old QA corroborate them.
- No anti-aliasing, font-size, global Container rewrite or UI restyle recommendation: #224 metrics and the owner's crisp choice are intentional.
- No “missing low-HP warning” defect: #121 explicitly excludes warning sound/flashing. A small explanatory ALERT tooltip could be useful, but is lower value than the findings retained above.
- No “all player attacks should MISS,” stat cards, neutral cards, job-granted skills or weapon stock requests: ADR 0005 and #225/#226 settle these.
- No EXP despawn or smaller permanent swarm suggestion: forbidden by design; number-density changes must be presentation-only.
- No clipping/loudness/ducking/audio-quality assertion without listening/measurements; no requirement for adaptive boss music or randomized original samples.
- No late-density or finale performance pass inferred from the initial early-death perf runs; Tree's early deaths are a documented owner rework, not a new balance finding.
- No public copying of WZ sprites/sounds/screenshots. New visual work, if later requested, must be original project art or composed locally from the player's WZ at runtime.

## 6. Unverified hypotheses / validation gaps

- **60 Hz state versus 164 Hz display:** player positions use current rounded sim state (`game/scripts/run/run_scene.gd:1664`), swarm frames/positions use current tick arrays (`game/scripts/render/mob_renderer.gd:105`), and projectile transforms use current tick coordinates; the accumulator fraction is not presented as interpolation. Camera smooths each display frame, so stepped actor motion can coexist with a smoothly moving background. This establishes no-render-interpolation in the inspected path, not observed objectionable jitter. Validate a fixed-input normal-speed 60/164 Hz recording including a ladder stop, horizontal run, knockback, portal snap and map edge. If improvement is warranted, interpolate presentation snapshots only, reset across teleports/slot reuse and keep pixel snapping/fixed sim untouched. Do not retune physics.
- **Animation responsiveness:** source stops rope animation while stationary and distinguishes attack speed from movement clocks; stills cannot validate stance transitions/input latency. Need current moving Warrior/Hunter/Tree sequences, including hit recovery and held ladder.
- **Audio output:** listen on headphones/speakers through title→map→boss encounter→Free Market, mute changes and dense pickups. Measure output peaks/voice steals before deciding on a limiter or ducking. Existing web silence fix is already documented; it should be regression-checked, not reopened without evidence.
- **Crowd telegraphs:** dense current F/P screenshots establish number congestion, but not a missed boss attack due to it. Moving A/B and Hunter/Warrior examples are needed before changing effect priority or opacity. No full-screen masking/repainting of original art proposed.
- **Scaling:** source policy and prior #224 screenshots cover integer/fill/small-tab behavior. This auditor did not newly exercise fractional below-800×600, ultrawide or browser zoom, and does not certify those modes.

## 7. Small, independently implementable backlog

1. **Resolve F3 binding conflict (D-2).** Load input-systems + game-ui-ux. Acceptance: one dispatch-level regression and actual saved binding/reservation behavior agree.
2. **Make hub prompts follow bindings (D-3).** Load input-systems. Acceptance: live Arrows/WASD, rebound NPC Chat and unbound NPC Chat cases; existing plate remains unchanged in size/style at defaults.
3. **Recover windows after resize (D-4).** Load godot-ui-control + game-ui-ux. Acceptance: open and remembered positions stay title-reachable after logical aspect shrink.
4. **Prototype reduced number overlap (D-1).** Load game-feel + create-game-assets (validation only). Acceptance: same-seed presentation A/B at 200–300 mobs, unchanged sim, original digits and protected incoming feedback; keep only if the owner prefers it.
5. **Add keyboard access to Options/Key Config first (D-5).** Load input-systems + godot-ui-control. Acceptance: keyboard-only row changes/remap/save/cancel with clear focus; mouse drag unchanged. Inventory/shop and existing title utilities can be separate follow-ups.
6. **Instrument SFX contention, then prioritize only if warranted (D-6).** Load audio-design + godot-audio. Acceptance: role-aware steal counts and listening evidence; fixed voice cap/static buses retained.
7. **Suppress dead-state MP cue (D-7).** Load game-ui-ux + game-feel. Acceptance: death screenshot plus living MP-wait regression.
8. **Refresh README controls (D-8).** Load input-systems. Acceptance: table agrees with InputMap/Settings/GAME_DESIGN, including E=Equip and only one movement scheme at a time.
9. **Label/focus web import flow (D-9).** Load game-ui-ux + input-systems. Acceptance: named controls, coherent tabs, keyboard error/cancel recovery and no protocol/network expansion.

## Lead-evidence addendum

Final evidence check: **2026-10-21 08:13 PDT**, after approximately ten minutes of bounded waiting following the otherwise-complete draft.

- **PERF_DONE present.** Replacement density/finale artifacts were inspected as listed above. Lead summaries: F/P density `PLAYING` at 780 s, max 289 mobs, 32,950 frames with 200+ mobs; Fighter density `PLAYING` at 780 s, max 221 mobs, 5,162 frames with 200+; F/P finale `CLEARED` at 907.83 s, max 337 mobs, 16,279 frames with 200+. All three have `missing: []`. These are fixture runs, not fresh-character balance acceptance. Their wrappers exited 0. The clear PNG was checked by eye; the CLEAR graphic is clearly legible over the crowd.
- **VISUAL_DONE absent — not executed / pending lead.** The requested fresh x4 full-run/window set, Hunter 310 and Dark Cave captures were not available. Current Fighter stills above cover its dense combat presentation, not its entire advancement/window flow. Current Tree coverage is death only.
- **FLOW_DONE absent — not executed / pending lead.** Fresh full/rounds/economy results cannot be certified. The dated main-checkout QA captures remain corroboration of layouts and current-source issues only.
- **CHECKS_DONE absent.** Central Godot full suite was started at 08:05 and its log was still empty at final inspection; balance outputs were not yet available. No pass/failure inferred. Completed central importer log is passing (44 library tests, two single-test binaries and 18 real-WZ tests; no ignored tests). Central Node rerun with the documented glob passed 51/51, zero skips, exit 0; its earlier directory-argument invocation failed for invocation reasons and was replaced.
- **EXPORT_DONE absent — not executed / pending lead.** No current browser/export runtime pass claimed.
- **Audit integrity:** final tracked `git status --short` / `git diff --stat` were empty. The sole created/edited file is this gitignored report. No tests, runtime settings, save files, cache files, proprietary assets or screenshots were written by this auditor.

