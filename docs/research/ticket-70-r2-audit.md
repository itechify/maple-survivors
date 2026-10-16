# Ticket #70 rework audit (spec #32)

Contract: `gh issue view 70`, owner decisions in `gh issue view 32 --comments`, and the local
spec32 implementer brief/decisions. Baseline audited at merged #70 `c00562f`; #71 integration `d4eaf94`
was merged during this rework. No earlier report was accepted as proof: ran the baseline windowed
character driver, read the consumers/tests/manifest/importer, dumped original MakeCharInfo, then
exercised the rebuilt UI and created character with the private real cache.

## Criterion audit

| Criterion | Result | Evidence |
|---|---|---|
| Three living slots, original CharSelect art, standing carried looks, names/level/job | Fixed | Baseline had repeated actions and invented headings. Rebuilt map/signboard, WZ tags, selected details; `empty_slots`, `one_character`, `three_characters`, `selection_changed`; UI flow selection test |
| One shared Start/New/Delete, proper disabled states; click and Left/Right select | Fixed | Empty screen disables Start/Delete, three slots disable New; slot click changes selected metadata/avatar stance; UI regression tests and driver |
| WZ empty-slot, character and selection animations, pageL/pageR, scroll, icon/job | Fixed | Real silhouettes/ground, selected effects/walk, unselected stand, WZ scroll and class badge; arrows inert for the single three-slot page |
| charInfo job/LV/STR/DEX/INT/LUK, fame and world rank | Fixed | One panel reads selected CharacterSnapshot attributes; fame/rank0; original cells and canvas, selection test |
| Create and continue keep SceneFlow seams | Met | `create_character(name,look,weapon)`, `continue_character(index)`, saved-round replay and full flow tests; no persistence logic duplicated in UI |
| Delete confirmation and history `deleted` | Fixed | Replaced native ConfirmationDialog with Basic/YesNo3, matching pause notices; cancel byte-preservation and confirm history test; screenshot |
| Runtime options exactly Info/CharMale and Info/CharFemale; exclude premium | Met | CharacterCreation sorts numeric keys from cached original WZ; synthetic fixture tests plus original `makechar_original.txt`; no second hard-coded option table |
| Gender | Met / presentation fixed | Gender prompt and final v83 GENDER row; changing gender resets indices and loads the other gender's options |
| Faces | Met | Male20000..20002/female21000..21002 from WZ; every UI option changes avatar.look; male/female screenshots |
| Hair | Met | All three WZ bases per gender, runtime; cross-product of base hairs and allowed colours drawn by driver |
| Hair colour | Met | WZ suffixes0/7/3/2 produce actual different Character.wz hair assets; black/brown preview captures for both genders; every option exercised |
| Skin | Met | All WZ0..3 choices select body2000+skin/head12000+skin; all variants checked in cache and preview |
| Top | Met | All three male and four female tops loaded from their own columns; female preview uses female clothing |
| Bottom | Met | Both options per gender from their own WZ columns; preview and cache checks |
| Shoes | Met | All four WZ choices; real arrow cycling updates preview equipment |
| Weapon creation choice | Met | Three WZ weapon IDs, live equipped preview, separate beginner_weapon save field |
| No stat dice, no job choice, new Beginner | Met | NewChar uses its nine authored option rows, no dice/statTb, SceneFlow creates ordinary fresh RunWorld snapshot |
| Chosen weapon's canonical stats/speed drive basic attack; Magician replaces it | Met, unchanged | BasicAttack snapshots info.incPAD and converts info.attackSpeed; fixed-seed test covers Sword17/speed4/0.72s, Club19/5/0.75s, Axe17/5/0.75s and advancement to Wand1372005; cache info checked independently |
| Look at select, in rounds and Free Market | Met | All use DataRepo.character_look, authoritative snapshot.look plus resolved weapon. Driver actually creates through form, then captures select/round and supplies a completed boundary for hub capture |
| Run history name/job/level/tiers/rounds/ending/date | Met / entry fixed | Existing scrollable history retained, small History[H] entry moved off copyright; died/victory/deleted rows and dates captured |
| Name length4..12, ASCII letters/digits, living duplicate rejected with message | Met | SaveData.name_error and case-insensitive living-name tests; actual invalid-name screenshot; rejected names do not create slots |
| Manifest: Etc, Login sections, all face/hair colours/skins/clothes/weapons | Met | Full Login.img, scoped MakeCharInfo, every requested Character ID present; real-cache variant test checks each; generic WzRoot/importer supports Etc and synthetic archive test passes |
| Rebuilt cache from local original WZ; missing empty | Met | Re-imported merged manifest to existing private cache-t70:157imgs,12written,145current,13636canvases,163pages,164sounds; zero unresolved UOL/warnings/errors. No shared-cache writes |
| Screenshots inspected by eye, both genders/three characters/history | Met | Evidence under evidence/t70r2/, including baseline and final review_fix captures; each named required image inspected. UI probe explicitly checks optional-art widgets too, rather than trusting AssetLibrary.missing alone |
| Weapon balance smoke acceptance | Prior implementation; not rerun | The rework changes no weapon/gameplay code. Owner explicitly says no smoke in that case; retained #70 weapon-smoke record in GAME_DESIGN4.2, no new tuning or held-out seeds |

## Source boundaries and limitations

WZ values/origins/delays and creation options are tier A. Local
`research/prior-art/SYJourney_JourneyClient/IO/UITypes/UICharcreation.cpp` gives NewChar screen facts;
`UICharSelect.cpp` and the MortalClient counterpart give selected walk/stand behavior. Later-client
`lastbattle_Harepacker-resurrected/HaCreator/MapSimulator/UI/Windows/AvatarPreviewCarouselWindow.cs`
and `CharacterSelectWindow.cs` provide reference facts about name tags, roster stride and effect families.
These AGPL/MPL sources were read for facts only. No implementation code was copied.
They do not establish an exact v83 layout. The v83 map, canvas origins and measured cells govern this
implementation; inferred slot/action/details/gender placement is tier C, recorded beside constants and in
GAME_DESIGN11. Pixel-exact coordinates and behavior against the original v83 executable are **not verified**.

The Free Market screenshot is a boundary presentation probe using a supplied completed summary, not a claim
that the created Lv1 character played and cleared Henesys. The normal run screenshot is a real launched round.

Private cache: `C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t70`.
Validation totals and final review evidence are recorded in GAME_DESIGN4.2. The finish reviewer scored
all four requested corrections resolved (class badge, keyboard focus/activation, weapon text contrast and
provenance documentation); its final disposition was ship, limited to that correction list. The documentation
finish check confirmed the existing architecture and asset seams, with no new identity/design system.

Final validation: full Godot suite **732 tests, 0 failed, 0 skipped, 81 files** (336.368 s).
Rust **47 tests pass**, including all **17 real-WZ integration tests** executed with MAPLE_WZ_ROOT set.
Full injected flow passed; final 19-state visual probe and flow summary both have `missing=[]`.
No weapon/balance smoke rerun because this rework changes no gameplay code, as explicitly requested.
