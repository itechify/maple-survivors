# Game design

Maple Survivors: survive a chain of classic MapleStory maps while an ever-growing swarm of familiar monsters closes in. You
move, jump, climb and drop through the real v83 terrain; your skills fire on their own; you pick a card at every level
(a new skill, a rank, a rarity bonus, a passive) and build a character that keeps only its job, equipment, scrolls and
mesos between rounds. This build ships Hero (112) and Arch Mage (Fire, Poison, 212); section 0 says what ADR 0006 changed.

All tuning numbers below live in `game/data/survivor/*.json`; this document explains them. Canonical MapleStory values
(mob stats, skill tables, frame timings, Physics.img) come from the player's WZ data and are never edited.

## 0. The redesign (ADR 0006): what the F/P slice built

On the `redesign` branch, **ADR 0006** replaced v83 progression with survivor-genre progression. The F/P Arch Mage slice
(spec #282, tickets #283-#294) built it end to end for one job; this section is the summary and the owner of any
conflict: where a later section still describes a removed system, this section wins. The slice rewrote sections 1, 5,
6.1.1, 7.5, 8 and 9. Sections 7.6-7.30 and 6.1.2 describe mechanics of the other job lines (Warrior, Bowman, Thief, Pirate,
I/L, Cleric): their data and tests stay on `redesign` and are unplayable until each line is ported, so read them as the
specification for that port, not as the live game; advancement, weapon paths, weapon-gated skills and standalone
behaviour cards mentioned in them are gone. Target design:

| Area | Target | Replaces |
|---|---|---|
| Character | One 4th job, chosen at creation (twelve v83 4th jobs; Beginner not playable). Name, look, slot as today. | 1, 9 |
| Round | Standalone: Free Market -> map select (the character's unlocked tiers) -> 3 maps, 3 bosses (spec #241, unchanged) -> Free Market. Death ends only the round, and loot is kept. | 1 |
| Tiers | Clearing any stage of tier N unlocks tier N+1 for that character. Cleared tiers can be replayed. The slice keeps the two existing tiers. | 1, 4.1 |
| Level | Lv1 every round. First-pass EXP curve for picks ≈ levels + boss draws (about 50–60 per round), all 6 actives by about 5:00, end level about 45-55 (tier C). | 5 |
| Skills | Job skill pool (lineage actives, all auto-cast; summons are timed allies in a slot; no buffs). Starting skill in slot 1. 6 active + 6 passive skill slots. | 7, 9 |
| Ranks | Actives 1-8, mapped to WZ levels by a survivor table. +1 rank per card, plus a rarity bonus (Fortune applies). Mastery cards after rank 8. | 7, 8 |
| Passives | 9 common passives, Maple-named: Maple Warrior (Might), Hyper Body (Max HP), Haste (Speed), Recovery (Regen), Booster (Cooldown), Area, Holy Symbol (EXP), Iron Body (Armor), Sharp Eyes (Crit). Rank 1-5, no rarity. Starting values follow the reference (tier C). | 7.6, 8 |
| Cards | 3 per draw, weights 1.2 owned active or Mastery / 1.0 new active / 0.8 passive rank / 0.5 new passive. Boss bonus draw kept. No reroll, banish or skip. Power Elixir fallback. | 8 |
| Combat | Maple formula plus auto-AP in one stat row per job. No MP (cooldowns only). No level-gap penalties. No MISS (ADR 0005). | 5, 6, 7 |
| Mobility | Teleport, Flash Jump, Dash or Rush on a skill key from Lv1, outside the slots. | 2, 7.15, 7.33 |
| Equipment | Job-class requirement only. `reqLevel` is the tier's drop band. Allowed weapon families per job; skills not weapon-gated. Equipment, inventory and mesos stay with the character. v83 scrolls; shops sell scrolls and buy equipment. | 8.3, 9 |
| Account | NX, Cash Shop, pets unchanged. Cash equipment adds Fortune. | 8.4 |

Order: the F/P Arch Mage slice, then Hero, then the other ten jobs, a tier rework (fewer starting choices), and last
the frozen balance pass (seeds 701-730). Until that pass, specs may set first-pass pacing (tier C) but don't tune.

**Landed in the F/P slice (spec #282):**

- **#283 (T1): assets.** The Magician manifest fragment imports `Skill.wz/211.img` and `212.img`, their `Sound.wz`
  entries and the nine common-passive icons (borrowed from the same-art skills of other books, `common.json`). The F/P
  summon 2121005 is **Elquines** (an ice summon), not Ifrit (the I/L Arch Mage's 2221005): String.wz says so.
- **#284 (T2): one fixed job.** `survivor/jobs.json` marks only 212 playable. A character's job never changes: there is
  no job advancement, job window, advancement draw, weapon path, job weapon grant or carried attack, and the Beginner
  is gone. `RunWorld.set_job` is the only writer of the job (`progression.job_id`): a restored character's `job_id`,
  else `setup.job` (the tools' `--job=<id>`, only a playable job), else `JobTree.default_job()`. The separate basic
  attack is gone (`WeaponReach` keeps only the weapon's swing reach, which `weapon_reach` skills and Final Attack spread
  measure). Weapons gate no skill, card or passive. Auto-AP reads one `balance.player.ap` row per job (212: INT primary,
  LUK secondary). The other lines' skill data and cards stay, unplayable until ported.
- **#285 (T3): no MP, no level gap.** Skills are gated by their cooldown only; MP potions, Magic Guard, MP Eater, the
  pet's MP pouch and the MP ALERT are gone, and the HUD's v83 MP gauge is drawn empty. The monster's level relative to
  the character changes neither the damage it takes nor the damage it deals (`CombatMath.physical_defense` lost its
  `1 - 0.01 x gap` term; the other paths never had one). No attack misses (ADR 0005).
- **#286 (T4): save format 3 and the standalone round loop.** A character is saved as `{name, created, rounds_played,
  character}` and keeps only its job, look, worn equipment and inventory, scrolls, mesos, cash, pet and
  `tiers_unlocked` (`CharacterSnapshot`, the one list of what it keeps). It has no level, EXP, skills, cards, AP or HP:
  every round starts at Lv1, and `RunWorld.character_snapshot()` hands the character back after a clear, a death or a
  Quit round alike, with everything the round picked up. Creation is name, look, then a Job page listing the playable
  jobs (Hero 112 and Arch Mage 212), whose `creation_weapon` (1372005) is the weapon worn; the look page's weapon row is no longer chosen.
  Flow: character select opens the Free Market (home); Up at out00 opens map select, which lists every stage of every
  tier (a locked tier greyed, not startable); `start_round` writes nothing; every round ends in `finish_run` (one
  `SaveData.finish_round` write: character, best, run count, NX, one history entry) and the results screen returns to
  the hub. Clearing any stage of tier N unlocks tier N+1 for that character (`CharacterSnapshot.unlocked_after_round`);
  tier 1 is always open; cleared tiers can be replayed. There is no permadeath: death ends the round, never the
  character, and only deletion frees a slot. Quit round is a death in every respect (its history ending is `quit`).
  A format-1 or format-2 save moves its characters to the history (`retired`) on load, unmigrated; bests, counts, the
  account and old history carry over. Tool files (`--character`, `--hub`, fixtures) of format 1 and 2 still load, reduced
  to format 3. The scroll roll seed is `created` + `rounds_played` + a hash of the character's belongings.
- **#287 (T5): skill pools, slots and draws.** `survivor/jobs/magician.json` owns each job's `skill_pool`,
  `starting_skill` and `mobility_skill` (Teleport, outside the slots). Six active and six passive slots
  (`skills.slot_limits`); actives have ranks 1-8 mapped onto WZ levels by `SkillBook.rank_table`; every card is exactly
  +1 rank; the draw is three distinct cards weighted 1.2 / 1.0 / 0.8 / 0.5 (section 8).
- **#288 (T6): rarity bonuses and Mastery.** Rarity no longer multiplies ranks: Rare and better attach a data-driven bonus
  to the +1 rank (`rarity_bonuses` per skill), and a skill at rank 8 turns its rank card into a Mastery card (section 8).
- **#289 (T7): the nine common passives** (section 8.5).
- **#290 and #291 (T8, T9): the twelve-skill F/P pool.** Explosion, Poison Mist, Element Composition, Fire Demon, Paralyze,
  Meteor Shower, Big Bang (7.31) and the generic player-summon seam with Elquines (7.32).
- **#292 (T10): equipment without level or stat requirements, tier drop bands, job weapon families.**
  `Equipment.requirement_error` checks only `reqJob`; `reqLevel` and `reqSTR/DEX/INT/LUK` are ignored by equipping, the
  pickup auto-wear (#222) and the bot shop, and the Equip/Item tooltip has no REQ rows (its job row stays).
  `stages.json` `drop_bands[i]` is the `reqLevel` band of tier i ([0, 30], [30, 60]); `RunWorld.drop_band()` gives the
  band of the current stage's tier and `EquipmentDrops` picks inside it (uniform for ordinary drops, the top third
  `boss_floor` for bosses, `equipment_drops.boss_top_parts` 3). The character's level and the held weapon no longer
  matter. `survivor/jobs/<line>.json` lists each job's `weapon_families` (`JobTree.weapon_families`; 212: wand, staff); a
  weapon drops only from them, armour and shields by job class alone. Mesos, worn equipment, the Equip tab and scrolls
  travel with the format-3 snapshot (`test_equipment_persistence` covers a death, a clear and a Quit round).
- **#293 (T11): first-pass pacing** (4.1, section 11): EXP `round(4 + 8 L^2)`, F/P cooldowns x0.4, three defensive passive
  values, NX 2 per gained level, and a bot that ranks global passives after three actives.
- **#307 (T11b): an opening ramp per tier** (4.1, section 11): `stages.json` `opening_ramp` scales monster HP (at spawn) and
  contact/`attackN` damage (at impact) from a start to an end value over round time, so a Lv1 character can play every
  tier: tier 1 is neutral (1 -> 1), Sleepywood opens at HP 0.3 / damage 0.4 on map 1 and 0.02 / 0.08 on maps 2 and 3,
  all reaching 1 at 20:00. Bosses capture the ramp at their arrival. WZ stats are never edited.
- **#294 (T12): QA and docs.** The `redesign` flow scenario (`flow_driver.tscn --scenario=redesign`), the retired
  scenarios and debug drivers removed, the one F/P fixture, the playtests and the regression smoke of 4.2, and the rewrites
  of sections 1, 5, 6.1.1, 7.5, 8 and 9 and of AGENTS.md.

**Landed in the Hero spec (#296, H1–H10 #297–#306):** Hero (112) is selectable alongside F/P, which remains the default (212). Hero starts with Power Strike and manual Rush, seven pool actives, a ten-orb Combo meter, Panic/Coma finishers and Monster Magnet's shared pull. H1 verified the books, sounds and weapon actions; H2 added the class line/AP/drop families; H3/H4 built the deterministic meter/pull boundaries; H5–H8 supplied skills and rarity effects; H9/H10 supplied two-job creation/tooling, the diagnostic `hero_t2.json`, the independent Hero replay oracle and QA. Sections 7.33–7.35 and the provenance rows own the mechanics. No balance tuning was done; melee survivability remains a balance-pass concern.

### Known design gaps (open after the slice)

These are findings of the QA pass, #293 and #307, recorded as gaps, not as met targets. Nothing here was tuned in #294.

- **Picks per round.** The original "about 75 picks" target could not be met by the levers #293 had: a round gives one pick
  per gained level plus three boss draws, so a clear at Lv45-55 yields about 48-58 picks, and 75 would need Lv73 or more
  draws. The revised target (#307) is picks about equal to levels plus boss draws, about 50-60. Tier 1 meets it (Henesys
  clears at Lv47-58). Sleepywood does not: the paired kit runs of #307 cleared at Lv72-78 with 74-80 picks, above the
  revised target, because the ramp-adjusted tier-2 monsters pay EXP at full WZ value.
- **The gear gate is soft.** After the ramp a Lv1 character with the tier-1 kit reaches map 2 in 3/3 training runs and clears
  2/3, while the starter wand alone dies in 11-12 s on seeds 1 and 2 but clears on seed 2026 (#307's table in 4.2); a
  small paired sample, not a measured equipment wall.
- **Mastery is rare for the bot.** After three actives the bot ranks passives first (#293: +20 on global passives), so
  across the Henesys smoke it seldom takes the seven rank-ups one skill needs for rank 8. The `redesign` scenario
  therefore ranks the highest-ranked owned active once the slots are full (a diagnostic policy, recorded in the driver) to
  show a Mastery card: the seed-1 round offered its first at Lv23 (7:40) and 14 in the round. No balance claim follows.
- **Meso income.** A Henesys clear leaves a character with about 0.9-1.0 million mesos (drop x14 survivor multiplier,
  `balance.mesos`), enough to buy every shop scroll many times over. Section 8.3 prices were set for the old run; no
  sink or income retune was done.
- **Skill window tooltips.** The tooltip's "Upgrades" list shows only standalone behaviour cards (`skill_mod`), which the
  ported skills no longer have, so a rarity bonus taken in a round is not listed in the Skill window; the card text and
  the resolved stats show it.
- **Ellinia (The Tree That Grew)** still dies early; the owner's rework is pending (record only).

## 1. The run

1. **Create or continue.** Character select shows three slots. Creating a character is name, look (the v83 Explorer
   face, hair and outfit options) and a Job page listing the playable jobs (Hero and Arch Mage (Fire, Poison), with the latter selected by default);
   the character is that 4th job from Lv1 and keeps it for good. Selecting a living character opens its **Free Market**.
2. **Free Market (home).** The v83 Entrance 910000000 with Bgm00/FloralLife. Walking, jumping, its two ladders and the
   existing same-map portal links work; no combat, spawning, drops or round timer run there. The Equip (E) and Item (I)
   windows, the four scroll NPCs (shops) and the Cash Shop button are here. Room entrances in01-in22 and Fredrick,
   Scrooge, Maple TV and Inkwell are drawn but inert. Up at the scripted `out00` portal opens **map select**; Esc offers
   Resume / Save & quit. The hub draws the character's look and worn equipment; moving never changes the save.
3. **Map select** lists every stage of every unlocked tier: Henesys, Ellinia, Perion and Kerning City (tier 1, always
   open) and Sleepywood (tier 2). A locked card is greyed, its details say "Locked. Clear any stage of Tier 1 to unlock
   Tier 2." and Start does nothing. Each stage contains three ordered maps (4.1). Back returns to the Free Market.
4. **Start.** Every round starts at Lv1 at a random spawn portal (`pn=sp`), with the job's starting skill (Energy Bolt for F/P, Power Strike for Hero,
   active slot 1) and its mobility skill (Teleport or Rush) on its key, full HP, no buffs, no cooldowns. The map's own BGM plays.
5. **Survive** the growing swarms. Each map's boss arrives 300 seconds after entering it. Defeat it, collect all
   drops and finish every pending choice with combat frozen, then transfer automatically to the next map. HP, Hidden,
   cooldowns, kills and damage carry; map entities and boss-inflicted statuses clear. Only map 3 clears the round. Slow
   boss fights extend total round time; reaching a timer alone never clears a map or stage.
6. **Level up** by collecting EXP drops. Each level pauses the game and offers three cards (section 8); the first six
   active skills fill the active slots, common passives fill the passive slots, ranks and Mastery follow. Each boss kill
   gives one extra draw.
7. **End.** Death (HP 0) shows the tombstone falling, then the results; Quit round (pause menu) ends the round the same
   way. A clear requires all three bosses dead and all mandatory choices answered; the last answer settles the clear
   without another combat tick, and the remaining map drops are collected once, subject to the Equip tab's size. Results show
   the time, level, job, kills, damage dealt, NX earned, the owned skills and the stage's best; Back returns to the Free Market.

**What persists** is exactly `CharacterSnapshot` (section 0, #286): job, look, worn equipment, the Equip tab, scrolls,
mesos, cash items, the pet and `tiers_unlocked`. Level, EXP, skills, ranks, card modifiers, AP and HP are round state
and never saved. What a round picked up (mesos, equipment, scrolls bought earlier) is kept whether it ended in a clear, a
death or Quit round; the unlock of tier N+1 needs a clear of a tier-N stage and is never taken back. There is no saved
round and no resume: closing the game mid-round loses it (its loot too), and Continue only opens the hub. Saves happen in
the hub (Save & quit, an inventory action) and when a round ends (one write: character, the stage's best, the run count,
NX and one history entry). Map transfers never save. Only confirmed deletion frees a slot; every round and each deletion
adds a history entry (character, job, stage, level reached, ending: cleared, died, quit, deleted, or retired for a
character of an old save). The account (NX, Cash Shop items, pets) is shared by every character
([ADR 0001](adr/0001-run-of-rounds-with-one-character.md), amended by ADR 0006).

## 2. Controls

| Action | Keys (MapleStory defaults first) |
|---|---|
| Move | Left / Right arrows (the movement setting switches to W / A / S / D; only one set moves) |
| Jump | Left Alt (also C; Space is NPC Chat, as in v83) |
| Climb ladder/rope | Up / Down near a ladder |
| Use a same-map portal | Hold Up in its entrance |
| Down-jump through a platform | Down + Jump |
| Prone | Down (on the ground) |
| Skill key of a learned manual skill | Teleport: X + direction; no direction uses facing; hold X to repeat. Dash: X starts its timed buff (hold X to cast it again when it ends). Rush (Hero): X + direction dashes that way, damaging and shoving mobs (7.33; hold X to repeat after its 2 s cooldown). Each manual skill has its own key in Key Config (see 7.15) |
| Pick an upgrade | Mouse, or 1 / 2 / 3, or arrows + Enter |
| Stat window | S (also Menu -> Stat) |
| Skill window | K (also Menu -> Skill); inside it Up / Down select a skill, Left / Right or 1-n switch tabs |
| Equip window | E (also Menu -> Equip; in the Free Market too): double-click a worn item to take it off, drag it onto the Item window likewise. The Cash and PET EQUIP. buttons in its bottom strip open the Cash tab (double-click an owned cash item to wear it, a worn one to take it off) and the Pet page (double-click an owned pet to bring it out or put it away) |
| Item window | I (also Menu -> Item; in the Free Market too): tabs Equip / Use / Set-up / Etc / Cash; double-click an item or drag it onto the Equip window to wear it; drag it off the windows to discard it (asks first) |
| NPC Chat | Space (as in v83; rebindable in Key Config): in the Free Market, next to a scroll NPC, opens its shop; so does a double-click on the NPC |
| HP potion | Del (also Q) (E opens the Equip window, as in v83; there is no MP potion, #285) |
| Menu | the status bar's Menu button: Equip, Item, Stat, Skill, Key Config, Options (entries without a window yet are disabled) |
| Pause | Esc (closes the front window first; pauses only when none is open). Pause menu: 1 Resume, 2 Key Config, 3 Options, 4 Quit round (asks to confirm; 4 again quits). In the Free Market: 1 Resume, 2 Save & quit |
| Key Config / Options | Menu -> Key Config / Options, or the pause menu (they open over it; Esc returns to it) |

There is no attack key: attacks cast automatically. Manual skills (Teleport, Dash, Rush) are cast on their own skill keys, all X by default.

Movement keys are a setting (`Settings` `[controls] movement`: `arrows`, the default, or `wasd`). Only the chosen set
drives `move_*`, so the other set is free to bind; switching to WASD takes W/A/S/D off every other action (S stops
opening Stat until it is rebound). The Options window (#87) exposes the toggle.

Key Config (#87) is the v83 keyboard window: drag an action's icon from the tray (or from a key) onto a key to bind
it; the key's previous action loses it. An action may sit on several keys. Bindable: jump, HP potion,
Equip, Item, Stat, Skill, NPC Chat and the **skill key** of each manual skill the character has learned (#188: Teleport
or Dash, never listed before it is learned; both default to X, and a character never learns both); fixed (tinted,
refuse drops): the movement set, Esc, F3 (Perf overlay) and the card keys 1-3. Previously saved F3 bindings lose F3 and
keep their other keys. Dragging an icon off
the keyboard unbinds it; Clear All (v83's BtDelete) unbinds every action. Default puts every action back on its
default keys (less the movement set: on WASD, S stays movement, so Stat has no key until bound); OK saves and applies
at once, Cancel / Esc discard. Bindings are global (`user://settings.cfg`, not per save). Options holds BGM / SFX
volume (sliders and MUTE), the frame cap and the movement setting; each change applies and saves at once. Every HUD
key label (the quick slot's captions, the manual skills' icons) shows the current binding.

Space and jump (#111): as in v83, **Space is the NPC Chat key** and jump defaults to **Left Alt and C** (Space was jump's
second key before the shops). A settings file saved earlier is not rewritten: if one of its rebound actions already
holds Space (jump rebound to Space, say), that action keeps the key and **NPC Chat has no key until it is rebound** in
Key Config (a key holds one action; Default gives Space back to NPC Chat). Double-clicking a shop NPC works either way.
A file that never rebound anything simply gains the new defaults.

In-run windows (Stat, the Menu popup, later Skill / Key Config / Options) are draggable by their title bar and
stack (a click brings one to the front). The run is paused while any is open, as with the pause menu. Stat and Skill
also open over a level-up choice; they draw above it, and the choice ignores input until they are
closed. The Stat window is the v83 one (`UIWindow.img/Stat` with its detail panel), read-only: AP is spent
automatically, so there are no +AP buttons, and stats the game does not model (guild, fame, hands) show "-".

The Equip and Item windows (#108) are the v83 ones (`UIWindow.img/Equip`, `UIWindow.img/Item`) and open in a round
(pausing it like the other in-run windows) and in the Free Market, which hosts the same window stack. The Equip
window shows each worn item's icon in its v83 slot (CAP, CLOTHES for a top or an overall, PANTS, SHOES, GLOVES,
WEAPON); a double-click takes an item off into the inventory, as does dragging it onto the Item window. The Item
window has the v83 tabs: Equip holds the 24 slots of spare equipment (a double-click, or a drag onto the Equip
window, wears an item, swapping out what was in its slot; an item of another job class shows a message and changes
nothing: only the job is a requirement, #292), Use holds only scroll stacks in all 24 slots (potions live only in the quick slot), Set-up / Etc / Cash
are empty, and the meso line shows the character's mesos. Dragging equipment or a scroll
stack off the windows asks v83's YesNo question and then destroys the item (it is not dropped on the ground, the
magnet would take it straight back; worn items have to be taken off first). Hovering
an item shows the v83 tooltip (name with "(+N)" after N successful scrolls, icon, REQ LEV / STR / DEX / INT / LUK
with the unmet ones in red, the job row, CATEGORY, ATTACK SPEED, the stats, NUMBER OF UPGRADES AVAILABLE, the
String.wz description). Every change goes through the character's RunWorld, so the derived stats, the drawn look
(hat, top, bottom, overall, shoes, gloves, weapon, on character select too) and, in the hub, the save slot follow at
once.

Tab shapes (#219): the tabs of the Item, Skill, Shop (sell side and the Buy label) and Equip windows (its Equip / Cash
tabs in the bottom strip) are drawn like the v83 client's tab control, a grey tab for each hidden tab and a pink one
for the shown tab, with the white glyphs of `<window>/Tab/enabled|disabled` centred on top. The shapes are the
`Basic.img/Tab5` piece set (19 rows plus the 2 red rows that continue the red rule under the strip; the Equip window's
blue strip has no rule and uses `Tab3`, whose base is grey), laid out by `TabStrip` (`scripts/ui/widgets/tab_strip.gd`).
The click areas are the drawn tabs. Item tabs: five equal tabs over the strip (tier C widths, from the 34 px
`Item/New/Tab0` flash sprites); Skill: 28 px per tab from x 8; Shop: five equal tabs over the sell panel's strip and
one Buy tab; Equip: 32 + 29 px between the CLOSE and PET EQUIP. buttons (the v83 Equip window has no such tabs; ours
are an invention, tier C). The Skill window's star tab is still code-drawn on its tab shape. Without the asset cache the
shown tab is a flat pink box and the glyphs are text. Findings: `docs/research/wz-inventory.md` "Tab backgrounds".

Scrolling (#110): dragging a scroll stack from the Use tab onto a **worn** item in the Equip window reads it (any
time the windows are open, so a round is held meanwhile; spare items in the inventory cannot be scrolled). The scroll
must be for that kind of item and the item needs an upgrade slot, else a message shows and the scroll is kept. The
scroll is rolled on the run's seeded scroll stream: success adds its stats and counts one more scroll, failure only
spends the slot, and a failed **dark** scroll destroys the item at its `cursed` rate (50%). Either way one upgrade slot
and the scroll are used up. A destroyed weapon leaves the character bare-handed. Success plays
`Effect.wz/BasicEff.img/Enchant/Success` with `Sound.wz/Game.img/EnchantSuccess` over the character, failure and
destruction `Enchant/Failure` with `EnchantFailure`; the tooltip then shows the new upgrade slots and "(+N)". Which
scrolls exist is `game/data/survivor/scrolls.json` plus `scrolls/<line>.json` (below); they are bought in the Free Market's scroll shops (#111,
next) and never dropped (`RunWorld.grant_scrolls` stays as a test hook).

Hand-testing tool (tool-only, not part of the game): `bash scripts/run.sh -- --hub [--character=<abs JSON>] [--mesos=N]`
opens the Free Market straight away with the Lv38 F/P fixture plus a test kit (500,000 mesos, ten of each rate of the
wand / hat / top / gloves scrolls, four spare equipment items; `HubTestKit`, tier C: ours), in a throwaway save that
never touches the player's save.

Scroll shops (#111): four NPCs stand on the Free Market floor, drawn from `Npc.wz` with their `String.wz` names: El Moth
1032103 sells the 100% scrolls, Barun 2022002 the 60%, Tulcus 1052104 the 10% and Vega 2041016 the dark 70% and 30%
(`game/data/survivor/shops.json`). Standing next to one (within 100 px) and pressing **NPC Chat** (Space, v83's default;
rebindable in Key Config), or double-clicking it, opens its shop and holds the hub like any window; Esc or Exit closes
it. The window is the v83 one (`UIWindow.img/Shop`): the NPC, its name and the Buy / Exit buttons above its stock
(five rows, scrollable: icon, name, price and success rate), the character, the meso total and the Sell button above the
inventory with the Item window's tabs. Every NPC sells its rate(s) of every scroll family whose equipment can drop for
the character's job (the Beginner sees only hat, top, bottom and shoes scrolls, a Magician also overall, gloves, wand
and staff), unlimited and the same at every tier. A scroll costs 35,000 mesos (armour) or 70,000 (wand, staff) at every
rate. Buy asks "How many are you willing to buy?"; with too few mesos or no room in the Use tab a notice says so and
nothing changes. Sell: any shop buys spare equipment at its `info/price` (after "Are you sure you want to sell it?") and
scrolls at their `info/price` (1 mesos each, asking how many); worn equipment is never listed, so it cannot be sold until
it is taken off. Every purchase and sale is saved into the character slot at once. The logic is the pure `Shop` module
(stock, buy, sell over a plain character state) that RunWorld wraps (`shop_stock`, `buy_scroll`, `sell_item`,
`sell_scrolls`) and the bot planner (#112) reuses.

The Skill window (#86) is the v83 one (`UIWindow.img/Skill`), read-only (no SP, no level buttons). It has a tab per
job on the character's path (Beginner, 1st job, the 2nd-job branch once reached, with the v83 tab glyphs) listing
every skill of that job a card can offer, by skill id: icon, name and level / max, unlearned skills greyed at 0 / max.
There is no star tab: since spec #225 every card is a skill of a job, and the one-off Elixir is used, not learned.
Hovering a row, or selecting it with the keyboard, shows a v83-style tooltip: icon, name,
the SkillText desc, the current and next level lines (effective values), cooldown and HP cost (none for passives),
and an orange "Upgrades" list of the behaviour cards taken for the skill with their steps ("Twin Claw ×2: +2
targets"). The cooldown is the one the auto-cast uses: a buff's is the longer of its duration and its canonical
cooldown.

## 3. Movement (MapleStory physics)

Constants come from `Map.wz/Physics.img` (tier A). The integration model follows the closest documented model of the
client's `CVecCtrl` (NoLifeStory `physics.cpp` description, tier B), re-implemented from prose:

- **Ground:** holding a direction accelerates at `walkForce/100` = 1400 px/s² up to `walkSpeed` = 125 px/s × speed%/100;
  releasing decelerates at `walkDrag/100` = 800 px/s² (drag clamped by min/maxFriction). Velocity follows the foothold
  slope; steeper than |sin| 0.9 slips (slipForce/slipSpeed).
- **Jump:** take-off `jumpSpeed` = 555 px/s × jump%/100; a held direction sets vx into [0.8, 1.0] × max walk speed.
  Gravity 2000 px/s², terminal fall 670 px/s. Apex ≈ 77 px.
- **Air control:** almost none (≤ ~9 px/s change at 200 px/s²), as in v83: you commit to a jump.
- **Down-jump:** Down + Jump on a foothold without `cantThrough`/`forbidFallDown` with a floor below: vy = -196 px/s,
  the current foothold is ignored until landing.
- **Landing:** vy clamped to 162.5 px/s on contact; walking off an edge falls; vertical footholds are walls. A fall
  whose sub-step crosses a floor inside its span but ends past the floor's end (into the corner where a wall rises
  from that end) lands on the floor, EPS (0.01 px) inside it (#260, tier C).
- **Fell out:** below the MapBounds bottom the player stands on the floor point nearest to (x, bottom), EPS inside
  the floor's span so a wall rising from that end still blocks (tier C).
- **Ladders/ropes:** Up/Down within 10 px of a ladder's x grabs it; climb speed 100 px/s (tier C); Jump + direction
  leaves it; `uf=1` lets you climb off the top.
- **Same-map portals:** hold Up with the feet inside x ±25, y −100…+25 around the canonical portal point. The player
  arrives instantly and silently 30 px above the target and falls to its floor; velocity resets and the camera snaps.
  A global 384 ms cooldown prevents repeated warps. These values are tier C and live in `balance.json.portals`.
  Links resolve the source's `tn` to a destination `pn` when `tm` is this map's id or 999999999. Other-map exits stay
  drawn and inert; Up still grabs ladders when no portal activates. Monsters do not use portals.
  The Tree That Grew I's left hollows go up00 → up01 → up02 → up03 (floors P3, P4, P7); its right hollows go
  dw00 → dw01 → dw02 → dw03 (P4, P3, then the right ground chain P2). The left ground chain is P1. These platform
  indices describe the imported v83 geometry used by the real-map test. up03 exits to Tree II and is inert.
  Type-10 hidden portals loop the original MapHelper `ph/default/portalContinue` sparkle art; type-1 portals remain
  visually marked only by map hollows.
- **Map edges:** the player cannot leave the foothold span horizontally (walls at the outermost foothold x).
- **Fixed step:** the sim ticks at 60 Hz; the player integrates in 2 sub-steps per tick (≈8.3 ms).

## 4. Monsters and swarms

Each monster is the original mob: its WZ animations (`stand`, `move`, `jump`, `hit1`, `die1`), its stats from
`Mob.wz/<id>.img/info`, its sounds (`Sound.wz/Mob.img/<id>/Damage`, `Die`) and its name from `String.wz`.

- **Speed:** move speed px/s = (speed stat + 100) × 0.625 (tier C, HeavenClient's terminal speed) × the stage's speed
  multiplier. Snail 21.9, Blue Snail 31.3, Shroom 43.8, Slime 50, Orange Mushroom/Pig 62.5 px/s, so the player
  (125 px/s) can outrun early mobs; late-stage multipliers close the gap.
- **Pursuit:** ground mobs walk along footholds. A mob on the player's platform walks toward the player; otherwise it
  follows the **shortest way** through the platform graph (`NavGraph`): walking off an edge onto a lower platform
  ("drop"), or, for mobs with a `jump` animation (Slime, Pig, Orange Mushroom), jumping up to a platform within reach.
  "Shortest" is the walk in px (each drop or hop counts 40 px, about a fall's time) to the player's x, not the number
  of edges: on 104040000 the 1518 px platform above the ground drops onto the ground only at its left end and onto a
  step at its right end, and a mob above the player's right half now takes the near right end instead of crossing the
  whole platform. A mob keeps the way it chose until another is 96 px shorter (no turning back and forth under a
  player who paces), and a straight-up hop takes off where the way goes on. A walker below a player standing on a low
  step (at most 40 px up, within touch) walks under the player; jumpers hop onto the step. Mobs never teleport
  visibly or float. A mob that cannot reach the player wanders on its platform.
- **Player-platform spawns:** 35% of ground spawn attempts target the player's platform (`spawn.platform_share`),
  at least 150 px away (`spawn.platform_min_dist`). If the whole platform fits in view, these mobs can appear visibly
  with the existing 0.3 s regen fade and remain harmless until fully opaque. If it extends past the view, placements
  stay on its off-screen portions. When that platform has no valid point, the ordinary rings serve instead.
- **Other spawning:** at points on floors outside the camera view (+48 px margin, and 32 px more on the side a moving
  player runs away from, where the camera lags behind it) but inside the map bounds, first on the floors beside the
  view (within 160 px of its sides and 48 px of its height), so the crowd walks in from the screen edges; preferring
  points whose way to the player is no longer than the walk in from 160 px beyond the view's side
  (`spawn.prefer_route`; a platform above qualifies near the end that drops next to the player), then any point that
  can reach the player; never within 200 px of the player, never where a wall crossing a platform stands anywhere on
  the way to the player (a wall of the platform's own structure, `FootholdMap.wall_applies`). New mobs fade in (regen)
  over 0.3 s (tier C).
- **Relocation:** an off-screen mob that has not come closer by its own walking for 3 s (left behind by a player who
  runs off, on a way that keeps getting longer, or stopped at a wall; the player walking up to it does not count),
  that is 1300 px away, or that cannot reach the player is moved silently to a fresh spawn point ahead of the player
  (on the side it is moving toward), keeping its HP; it fades in there like a new mob. Never a mob on screen (it must be
  80 px outside the view, since the camera can lag on either side), never an elite; a mob standing still on screen
  (at a wall) keeps counting and is moved as soon as it leaves the screen. The player can still climb away for a
  while: the mobs below stay where they are while on screen, and the swarm re-forms around the new platform as the
  off-screen ones are moved.
- **Contact:** touching a mob with `bodyAttack=1` deals touch damage (section 6), unless the player is inside the hit window (#88: shrinking while hits keep landing). A landed hit knocks the player back at most once per knockback guard (#223: the first window length, 1.5 s; section 6).
- **Mob attacks (#76):** an ordinary mob whose Mob.wz img lists `attackN` (Tauromacis 7130100 `attack1`, Taurospear
  7130101 `attack1`/`attack2`: type 0 magic) uses them exactly like a boss attack (4.3): the canonical windup stance,
  the hit at `attackAfter` in the canonical range box mirrored by facing, magic attacks with MADamage against M.DEF
  and `elemAttr` as for bosses, the `hit` art and the `Sound.wz/Mob.img/<id>/AttackN` sound. Damage is unscaled like
  contact damage, times `balance.mob_attacks.mobs[id].dmg_mult` (1.0) and, for an elite, `elites.damage_mult`. A mob
  attacks only grounded, fully faded in, not frozen, with its feet on screen and the character in a range; it tries its
  attacks in canonical order. Its wait counts only that on-screen time: the first is 50-100% of its interval (by spawn
  identity, so a wave spawned together does not attack in unison), the next the full interval (5 s for both Tauros).
  Hits are `source_kind` `mob_attack` and share the shrinking hit window with contact damage (#88, section 11); an
  attack the window turns away shows no hit art either (#144, tier C); boss
  `attack`/`projectile` hits ignore it. All cadence values are tier C.
- **Mob skills (#76):** ordinary mobs cast none. Character statuses (Slow and the like) come only from bosses (owner,
  #76); Jr. Boogie 3230300 lists Seal (120) and Curse (124) in Mob.wz but deals contact damage only, and both are skipped
  like any other unsupported mob skill.
- **Hit reaction:** only a hit reaching the monster's canonical `pushed` value plays `hit1`, stuns for 0.24 s and
  pushes it 12 px away from the source (tier C timings/distance, tier A threshold). Weaker hits leave its movement
  and animation state unchanged.
- **Flyers:** mobs with a `fly` stance steer directly toward the player through footholds, walls and ceilings,
  inside the map bounds. Speed = (`flySpeed` + 100) × `mob_speed_factor` × the stage speed multiplier (tier C
  conversion, canonical `flySpeed` unchanged). A 2 px bob over 1.2 s (`balance.mob_motion`) is independent of the
  pursuit and never accumulates drift. Flyers fade in before moving or hurting the player and spawn at off-screen
  air points without needing a floor or a route. They use their own canonical contact attack, never ranged attacks,
  and their canonical HP receives the same stage HP multiplier as ground mobs. `fly`, `hit1`, and `die1` use the
  original WZ frames; dying flyers stay in the air until their animation ends.
  Henesys map 1 adds PQ Stirge 9300063 (Lv 6) at 3:00, weight 1. Later curve pools retain historical flyer
  additions as data, but no longer select mobs (#241); later maps use their life pools. The Tree That Grew I
  has no flyers; The Forest of Evil I brings Malady from its own life list.
- **Death:** `die1` plays with its WZ delays and alpha fades (`a0/a1`), the death sound plays, and the mob drops EXP.
- **Elites:** periodically one mob of the current pool spawns with ×8 HP, ×5 EXP and an explicit ×1.5 mitigated
  hit multiplier (`elites.damage_mult`), drawn with a name tag. All three multipliers are survivor data (tier C).

### Monster statuses and elements (#54)

`MobSwarm.apply_status(slot, status, params, events)` is the shared sim entry point for sibling skills. `status`
is `slow`, `poison`, `freeze`, `threatened` or `stun` (`MobSwarm.STATUS_NAMES`, indices 0-4; `STATUS_COUNT = 5`); parameters contain the canonical `time` in seconds, signed
`x` for Slow, or the applying canonical skill `level` for poison (plus an optional survivor `skill` key for damage
events), and optionally the applying skill's canonical `element`. Each status is a row of one packed per-slot status
table, refreshes without stacking, and clears on death, release or relocation. Application and natural expiry emit
`mob_status_applied` / `mob_status_expired`. Removal clears silently. A rejected status emits nothing.

- Slow uses `(100 + x) / 100` of walking/flying pursuit speed: canonical x -40 means 40% slower; a positive x is
  clamped away (tier C). Ballistic jump/drop trajectories retain the navigation graph's physics. Refreshing is the #54
  Survivor policy; the original Slow text also describes a consecutive-use limit that this interface does not impose.
- Poison snapshots `min(32767, ceil(slot max HP / (70 - canonical skill level)))` damage per second, first at 1 s,
  with a final pulse when due exactly at expiry. Reapplication restarts the pulse clock and duration. HP never drops
  below 1; pulses do not stun or push. Actual lost HP contributes to player damage, and the eventual ordinary final
  hit awards the normal kill/EXP. This is a **tier C v83 server-reference fallback**, not verified v83 client RE.
- Freeze holds walking, facing, state/animation clocks and the monster attack/skill gate until expiry. Nonlethal
  hits do not restart frozen art or stun/push; lethal hits start the normal death animation. Movement/new-attack/
  new-skill suppression has **tier B evidence from a later v95 client reconstruction**, extrapolated to v83. Owner
  choices (**tier C**): a frozen monster deals **no touch damage**, a monster frozen mid-air still falls straight down
  and lands, and a fading-in monster keeps fading in.
- **Stun** (#187, spec #168) is a generic status for player skills (Pirate Backspin Blow, Double Uppercut, Blank Shot;
  later Bowman's Arrow Bomb). A stunned monster stands where it is (a flyer hovers without its bob), starts no
  attack or mob skill and deals **no touch damage** (the frozen rule: `MobSwarm.can_act` also reads it, and
  `MobAttacks` skips it), but still takes damage, can be killed and keeps its animation clocks. It does not flinch or
  slide from hits while stunned, and one stunned mid-air or mid-jump falls straight down and lands. A new stun on a
  stunned monster keeps the **longer** of the remaining and the new time (the shorter one changes nothing, the art
  clock included). Stun has no element: elemental resistance never rejects it, whatever element the applying skill
  passes. A skill requests it through `on_hit: {"status": "stun", "chance_field": "prop", "duration_field": "time"}`
  (Skill.wz `prop` and `time`, tier A; a missing `chance_field` always lands, e.g. a 1 s Backspin Blow); the roll is
  the same combat stream as the other `on_hit` statuses. The movement hold, the no-flinch rule, the longer-duration
  refresh and the elementless rule are **tier C** choices; stun on the player is out of scope.
- **Threatened** (#183, spec #165) lowers weapon attack and weapon defence by the flat signed canonical `x` / `y`
  (floored at zero), refreshes without stacking and coexists with every other status (7.11).
- **Bosses reject every status**: scheduled bosses (`steady`) and canonical `info/boss` monsters refuse Slow, Poison,
  Freeze, Threaten and Stun, matching the inspected v83 server reference (**tier C**, Cosmic `Monster.applyStatus` boss gate; owner
  decision replacing #54's boss-poison permission).
- **Elemental status immunity**: a status fails on a monster whose Mob.wz digit for its element is 1 (immune), 2
  (strong) or 4 (neutral), as in the same reference (**tier C**; digit 4 still takes ×1 hit damage). Poison
  carries `S` and Freeze `I` (Poison Breath `elemAttr=s`, Cold Beam `i`, tier A); Slow is elementless. An applying
  skill may pass its own canonical `element` instead. Weak and unlisted elements accept the status.
- Player skill hits read Skill.wz `elemAttr`, case-insensitively match the target's parsed Mob.wz letter/digit pairs,
  and apply immune 1 → ×0, strong 2 → ×0.5, weak 3 → ×1.5 before final rounding. Unlisted/elementless hits are neutral.
  Instant and projectile impacts share this resolution; immune hits display zero and cannot stun/push. `MobKind.undead`
  exposes the original flag for skill code; it does not imply an automatic element weakness.

Presentation reads the status table. Slow plays its cached 2101003/mob animation once and retains an amber tint;
Poison loops cached 2101005/mob. Threaten loops cached 1201006/mob at the body top (7.11).
Stun loops the three-frame stars every v83 stunning skill shares as its `mob` node
(cached from Hero's Shout 1111008, `Skill.wz/111.img/skill/1111008/mob`, anchored at the body top like Poison; a
yellow tint stands in when it is absent). Cold Beam has no persistent mob overlay, so Freeze uses a cyan tint. A violet
poison tint is the fallback when its cached cue is absent. Anchors and tints are tier C; original art/timings are A.
The formulas, source limitations, pinned citations and the performance/visual validation record are in
[the status research](research/monster-status-effects.md). The applying Slow/Poison Breath/Cold Beam skill
implementations remain sibling work.

### 4.1 Pacing (`stages.json`)

**#293 first-pass pacing (ADR 0006, training only).** The current 212 round aims for six actives by about
5:00 and a clear around Lv45–55. The selected survivor EXP curve is `round(4 + 8 L²)` (minimum 1),
F/P pool cooldowns are 40% of the T8/T9 first-pass values, and Hyper Body / Recovery / Iron Body grant
+40% Max HP / 2% Max HP per second / -6 damage per hit per rank. Other passive values, rarity bonuses
and Mastery repeat factor remain unchanged. NX per gained level is 2 (was 5); boss/clear awards stay unchanged.
This is a first pass, not the frozen balance pass. #293 kept canonical WZ numbers and spawn/boss/drop rules
unchanged; #307 adds only the opening scales described below.

The revised slice target (#307) is picks ≈ levels + boss draws (about 50–60), with one pick per gained
level and three boss draws: Lv45–55 yields 47–57 picks. Reward cadence stays unchanged. Regression guards cover six actives within
360 s (60 s offer/route slack), clear levels 40–60 and 42–62 picks, and at least one Henesys clear in the
three fixed training seeds with the tier-1 kit. Swarm engagement floor is 0.15 over 6:00–12:00; a growing leftover crowd and
mandatory late damage are not pacing targets. The oracle now exercises actual map transfers rather than
flattening three maps into the historical one-map curve. Ellinia remains informational.

**#307 opening strength.** Every stage declares `opening_ramp` in survivor data. Its whole-round clock
uses `p = clamp(round_time / seconds, 0, 1)^power` (default power 1), then interpolates each HP/damage
start/end pair. A map may replace its stage ramp with its own complete `opening_ramp` object, to account
for the large jumps between canonical map rosters. Map transfers do not reset the round clock. HP stacks with the existing spawn/elite HP scales and is
captured at spawn; ordinary contact and physical/magic `attackN` damage use current progress at impact,
after defense, stacking with existing source/elite scales. WZ stats are never edited. Bosses capture HP and
both contact/attack multipliers at their actual arrival time (not warning time), on top of their own scales;
those values stay fixed throughout that fight, including projectiles. Boss summons/revives use ordinary rules.
Tier 1 is neutral (1 -> 1 over 900 s), deliberately retaining #293's pacing envelope. Sleepywood uses
map 1 HP 0.3 -> 1 / damage 0.4 -> 1 with power 6; map 2/3 HP 0.02 -> 1 / damage 0.08 -> 1
with power 3. All use 1,200 s of whole-round time. At 600 s the map2/3 added scales are
HP 0.1425 / damage 0.195; at 1,200 s all scales reach 1, on top of existing stage scales. This deliberately
allows a typical three-map round to end before the full ramp; longer rounds reach full strength at 20:00.
Paired kit/starter measurements are recorded below. All ramp choices are tier C first-pass tuning.



Stages use region keys `henesys`, `ellinia`, `perion`, `kerning` and `sleepywood`, with `region` and `continent`
labels (tier C owner choice). Tools accept the former keys `henesys_hg1`, `tree_that_grew_1` and `dark_cave` as
aliases; living slots, bests, history and run snapshots migrate on load. The tier list is
`[[henesys, ellinia, perion, kerning], [sleepywood]]` (Perion and Kerning City added by spec #253).

| Stage key | Map 1 | Map 2 | Map 3 | Boss order |
|---|---|---|---|---|
| `henesys` | Henesys Hunting Ground I (104040000) | The Pig Beach (104010001) | The Blue Mushroom Forest (100030001) | Mano / Mushmom / Blue Mushmom |
| `ellinia` | The Tree That Grew I (101010100) | The Forest of Wisdom (100040100) | The Forest of Evil I (100040105) | Stumpy / King Slime / Dyle |
| `perion` | West Street Corner of Perion (102010000) | East Rocky Mountain V (101030404) | The Burnt Land I (106000101) | Mano / Stumpy / Iron Hook |
| `kerning` | Kerning City Construction Site (103010000) | Line 1 <Area 1> (103000101) | The Swamp of Despair I (107000000) | King Slime / Shade / Dyle |
| `sleepywood` | Dark Cave (105050400) | Drake Area (105090310) | The Cursed Sanctuary (105090900) | Zombie Mushmom / Snack Bar / Jr. Balrog |

All are on Victoria Island. Map select lists each region's three maps and bosses in `tiers` order; its objective is
"Defeat 3 bosses across 3 maps". Four cards per tier is the most the parchment fits above the Start button
(`stage_select.gd` `MAX_CARDS`); a fifth region would need a scrolling list. Results show the region and ending map. The opening title shows continent above region; transfer
arrivals show the destination's v83 street and map name. Summaries retain region/continent and the ending WZ names.

Round time includes all combat on every map. The pacing clock is `curve_time = (N - 1) * 300 + time_on_map` for
one-based map N, resetting to 300 / 600 on transfers regardless of the previous fight's duration. Rate, alive cap,
HP/speed multipliers, bursts, elites and post-duration slopes use that clock. Boss waits use time since entry instead.

Map 1's ordinary pool follows the last keyframe at or before curve time among keyframes with `t < 300`; later
keyframes change numeric pacing only. Maps 2 and 3 use their own v83 `life` mob counts as weights, excluding hidden
event entries and each map's `exclude` list. Pig Beach excludes timed Iron Hook 4090000. The Cursed Sanctuary uses
Sanctuary Entrance IV's ordinary pool: Cold Eye 4230100 x5, Tauromacis 7130100 x2, Taurospear 7130101 x5. Bursts and
elites use the same current pool. `stages.json` declares `pool: "curve"`, `pool_from_life: true` (optional `exclude`),
or an explicit weighted `pool` per map; these are tier C owner choices, not changes to canonical WZ stats.

Perion and Kerning City (spec #253) copy Henesys's numeric curve exactly: keyframe rate, alive cap, HP and speed
(including #241's opening), bursts, elites, 2.5x stage EXP, the hard cap and the post-duration slope. Their extra
210 s keyframe is Henesys's curve interpolated at 3:30 (rate 0.875, cap 17.5, speed 1.0375), so it changes no number;
it only carries the 3:30 pool. Keyframes from 300 s carry no pool, so the 3:30 pool (repeated at 4:00, Blue Snail
included) stays for the rest of map 1. Map 1 uses the map's own v83 life mobs plus one
weaker neighbour, Blue Snail 100101, which opens alone like Henesys's snails (the owner's Q4 weaker-neighbour clause,
invoked after the first-pass pools' T1 seed-1 bot deaths at 0:15 and 2:15, Lv1; native to Perion Street Corner
101040000 next door, tier C for Kerning City). Weights tier C:

| Curve time | Perion (West Street Corner of Perion) | Kerning City (Construction Site) |
|---|---|---|
| 0:00 | Blue Snail 100101:1 | Blue Snail 100101:1 |
| 2:00 | Blue Snail 2, Stump 130100:3, Red Snail 130101:2 | Blue Snail 2, Red Snail 130101:3, Slime 210100:3 |
| 3:00 | + Dark Stump 1110101:1 | + Orange Mushroom 1210102:3 |
| 3:30 | Dark Stump 3, Stump 2, Red Snail 1, Blue Snail 1 | + Octopus 1120100:1, Blue Snail 1 |

Maps 2 and 3 use their life lists with no exclusions; v83 lists no timed or hidden entries there: East Rocky
Mountain V Axe Stump x12 / Dark Axe Stump x21, The Burnt Land I Wild Boar x11 / Fire Boar x20, Line 1 <Area 1>
Bubbling x64, The Swamp of Despair I Ligator x32 / Jr. Necki x4. The opening mobs hit much harder than Henesys's
snails (Red Snail PAD 27, Slime 32, Stump 30 against Snail 12); these starting pools are untuned and the balance
pass #77 owns them.

Balance records and playtest `summary.json` carry `map_times` (reached-map entry seconds from round start, starting
with 0) and `ended_map: {index, id}` (zero-based index, original v83 id). `boss_fights` retains `map_index`/`map_id`.
SUMMARY reports deaths by map and map-2/map-3 entry medians with observation counts; an unreached map contributes
no observation. Camper policies park only on their own first map; later maps use the sensible bot. Prior seeded
records change with this map progression. The regression smoke belongs to #249; #248 only checks seed 1 Henesys
for the new record fields and uses diagnostic flow evidence, without tuning.

Sleepywood's first map is Dark Cave (105050400, Dungeon), in tier 2.
Its first-pass data targets an arriving Lv35–43 second-job character and is frozen before the report-only smoke;
the 30–40% clear / Lv60–69 targets are deferred to #77. Canonical mob HP, defence, EXP, levels and elements remain
unchanged in the cache. Stage EXP is 1x; no new per-mob stat multipliers are applied. Tauromacis and Taurospear use
their canonical magic attacks (#76, section 4 "Mob attacks"); Jr. Boogie deals contact damage only and no ordinary mob
casts a mob skill. Cross-map exits west00/east00 and NPC
9201133 use the existing drawn, inert handling. The original spawn list is 9 Horny Mushrooms, 7 Zombie Mushrooms
and 35 Stirges (tier A, original Map.wz).

| Curve time | Rate/s | Max alive | Pool (mob ID:weight) | HP × | Speed × |
|---|---|---|---|---|---|
| 0:00 | 3 | 50 | 2110200:4, 2230101:4, 2300100:1 | 1 | 1 |
| 2:00 | 4.5 | 80 | 2110200:3, 2230101:3, 2300100:1, 2230100:3 | 1 | 1.05 |
| 5:00 | 7 | 130 | 2110200:2, 2230101:2, 2300100:1, 2230100:3, 3230100:3, 3230300:1 | 1.15 | 1.1 |
| 8:00 | 10 | 180 | 2230101:2, 2300100:1, 2230100:3, 3230100:4, 3230300:2 | 1.3 | 1.15 |
| 10:00 | 12 | 220 | 2230101:1, 2300100:1, 2230100:2, 3230100:4, 3230300:2, 7130100:2 | 1.4 | 1.2 |
| 13:00 | 15 | 280 | 2300100:1, 3230100:3, 3230300:2, 7130100:3, 7130101:2 | 1.5 | 1.25 |
| 15:00 | 18 | 330 | 2300100:1, 3230100:3, 3230300:2, 7130100:3, 7130101:3 | 1.6 | 1.3 |

The table retains curve pool columns for reference; only rows before 5:00 select the first map's pool.
All curve values/weights are tier C. The hard cap is 400; bursts start at 90 s, repeat every 90 s and grow from
10 to 40 mobs; elites start at 75 s, repeat every 60 s and use HP/EXP/contact multipliers 8/5/1.5 (tier C,
existing stage conventions). All three bosses and every reward choice must finish
before the round clears (#73). These values are not a balance calibration.

The director keeps spawning until `alive >= max_alive(t)`, at `spawn_rate(t)` mobs/s, choosing from the current
map's pool by weight. Values interpolate linearly between keyframes. Henesys Hunting Ground I (104040000) uses
the coarse #30 C46 numeric curve (2026-10-15), with the owner's #241 opening-density changes. Later pool
selection follows the per-map rules above; further tuning waits for the dedicated balance pass (section 4.2).

| Curve time | Rate (mobs/s) | Max alive | Pool additions | HP × | Speed × |
|---|---|---|---|---|---|
| 0:00 | 0.25 | 6 | Snail 4, Blue Snail 3 | 1 | 1 |
| 2:00 | 0.55 | 11 | Red Snail, Shroom | 1 | 1 |
| 3:00 | 0.75 | 15 | PQ Stirge | 1 | 1.025 |
| 4:00 | 1 | 20 | Slime | 1 | 1.05 |
| 5:00 | 2.5 | 50 | Flyeye | 1.25 | 1.075 |
| 6:00 | 4.5 | 85 | Pig, Orange Mushroom | 1.75 | 1.1 |
| 8:00 | 8.2667 | 143.3333 | Goblin Fire | 3.84 | 1.1533 |
| 9:00 | 9.4 | 165 | Green Mushroom | 3.9 | 1.18 |
| 11:00 | 12.1333 | 215 | Stirge | 4.7 | 1.2467 |
| 12:00 | 13.5 | 240 | full pool | 6.375 | 1.28 |
| 13:00 | 15.6667 | 270 | full pool | 7.6875 | 1.32 |
| 15:00 | 20 | 330 | full pool | 8.25 | 1.4 |

Pool additions at 5:00 and later in the table are retained data, not active pool changes (#241).
The Beginner phase is sword-paced: a v83 Beginner (5 MP, one Three Snails shell at canonical 3 MP) kills mostly with
the basic attack, so until 4:00 only a few mobs are alive, no
elite appears before 4:00 and no burst before 5:00, and ordinary kills pay 2.5x EXP so Magician arrives near 4:40.
Density and HP then ramp from 5:00 into the calibrated mid/late curve. Canonical mob HP and skill damage/costs remain
unchanged. Ellinia keeps its numeric curve while using the same three-map clock and pool rules.

The changed 8:00 mob HP endpoint interpolates from the unchanged 6:00 point. Ordinary/elite HP continues after 15:00 at
0.25 × (8.25−7.6875)/120 = 0.001171875 per second; other pacing fields retain their existing quarter-slope
extrapolation. Potion availability follows the per-kind cooldowns in section 5 on every stage (spec #237).
Stage EXP remains a constant 2.5; the rejected optional EXP-keyframe experiment is removed.

The earlier difficulty overhaul removed the time-based touch-damage column and the hidden 0.55 attack scale. Section 6.2
defines current monster damage. The tuning history below and section 4.2 describe the former damage model;
the overhaul's tuning and independent acceptance results are recorded separately below. The older tables remain
historical evidence, including the removed Hill stage; they do not describe the current hit model.

Two levers do different jobs: `max_alive` is the crowd a struggling player faces (the cap binds when kills fall
behind), `rate` is what pressures a strong build (it only matters while the player kills faster than the cap refills),
so a strong build still ends up surrounded by 200-300 mobs late in the run. The first 2026-10-14 pass lowered
`max_alive` at 4:00-9:00 (weak builds were overrun there; strong builds never meet the cap) and raised the early
`rate`. The swarm pass (section 4 Pursuit / Spawning / Relocation) made the crowd actually reach the player: mobs
that used to idle on far platforms or trail a running player now arrive and die, so the same numbers gave a thin
mid-game crowd and fast levels, and the crowd that did gather hit far more often. So it raised the mid/late HP
(x1.3) and the 6:00-12:00 rate a little (mobs live long enough near the player to form a crowd), lowered the early rate
(Lv 8 stays at ~2:40) and halved touch damage over the whole run (after 8:00 the kiting bot now takes ~120 touches
instead of ~20; with the old damage most runs died). That left Lv 30 at ~11:15, before the ~12:00-15:00 target, so the
follow-up made the EXP curve steeper (section 5; Lv 30 needs 22% more EXP, Lv 8 4% more) and, because a build that
levels slower is weaker against the same crowd (the steeper curve alone killed 45 of 48 tuning runs), took touch
damage down to 0.7 of the swarm pass's values (0.35 of the original 1.0-1.5). The pool also sets the EXP income: the 6:00 pool's Pigs and
Orange Mushrooms give 15 EXP against 8 for a Red Snail, and a variant that kept the older mobs longer to spare weak
builds starved the strong ones of levels (14 of 24 tuned-bot runs died instead of 3), so change pools and the EXP
curve together. Bursts every 90 s spawn a ring of 10-40 mobs around the view (growing over the stage). The roster
deliberately goes beyond the map's own `life` list (Snail, Slime and Orange Mushroom are the classic trio); the
original spawn list is shown in the stage info. Stage select offers Henesys Hunting Ground I and The Tree That Grew I.
The Hill East of Henesys was removed in the difficulty overhaul because its gameplay was too similar to Henesys
Hunting Ground I. Its map and unused Ribbon Pig assets are no longer selected for import; old save records for
retired stages are ignored.

The Tree That Grew I retains its own ground-only pool: Snails until 2:00, then the existing Slimes and mushrooms.
Its ordinary kills yield 0.90x EXP, and it uses the same rate/crowd caps with HP multipliers 0.8/1.0/1.5 at 2/4/6 minutes, then
3.25/4.25/6.875 at 9/12/15 minutes. The early HP curve supports weak builds without changing canonical
monster HP or redesigning the roster. It has no flyers, and its portals connect the playable branches.

### 4.1.1 New-system measurements

The balance harness records completed boss spawn-to-death times per encounter, HP/MP potions used,
MP-short waiting seconds, and whole boss-hit damage divided by max HP at the hit (before Magic Guard's split).
Aggregates report completed fight samples separately from unfinished, unspawned or skipped encounters, print the
completed/spawned count beside each median and a censored median over all spawned fights (an unfinished fight counts
as at least its elapsed seconds; `>=` marks a lower bound), and retain the boss-hit source kind. A cap ends the measurement as TIMEOUT; reaching 15:00 alone cannot clear a run.
The per-policy `SYSTEMS` report sums player `potions_used` for HP (no MP since #285). `potion_uses` retains each player's drink
time, level, kind, item ID, restored amount and capacity waste; `pet.potions_used` counts pet drinks separately.

The #42 harness also reports `ordinary_kill_hits_by_min` for the first five run minutes: each bucket contains
landed lifetime damage-line hits, ordinary kills and their ratio (null without kills). The death minute receives
all hits on that mob, including earlier-minute hits; a death exactly on a minute boundary belongs to the preceding
minute. Relocation preserves a lifetime's count and fresh slot reuse resets it. Elites, scheduled bosses and
canonical boss kinds are excluded; ordinary summons/offspring are included. Magic Claw counts each landed line,
basic attacks count, and immune contacts do not. Aggregation divides summed hits by summed kills.
The MP-wait fields (`mp_short_seconds`, `late_mp_short_seconds`, `late_observed_seconds` and their summary counts)
were removed with MP (#285). `outcomes` keeps timeouts separate
from clears and deaths, and `death_seconds` samples deaths alone. Run records retain simulation warnings.
Boss diagnostic snapshots use JSON null for an unobserved/nonfinite `best_distance`; the live simulation retains
its infinity sentinel. The report reader normalizes that field in preserved legacy `1e99999` records before parsing,
logs every normalization and leaves raw files and measured values unchanged.

Since the buff-timeline diagnostic, `buff_casts` also records each observed cast tick, skill ID, canonical level,
duration and active effect stat/value. This exposes the real cast snapshot, unlike a final rank or an absorbed
hit fraction. It changes no gameplay or RNG. Old records without the field cannot
prove zero casts. It supports diagnosis; aggregate Guard coverage and offensive cast counts remain unrecorded.
The legacy `cards_taken` prefix is the queued level at `progression.front()`, not the character level or a bonus
flag. A bonus pick can carry a positive prefix while normal levels are queued; −1 is not an exhaustive bonus
marker. These strings cannot isolate normal-choice timing or replace the actual cast snapshots.
Three harness-only camper policies use sensible cards and potions, then park after a normal 60 s warmup:
Henesys highest platform, Henesys ground rope, and Tree's highest playable branch reached through the real
up00/up01/up02 chain. Henesys placement is a one-time controlled setup; Tree uses movement inputs. Arrival
success and portal use are recorded, and displaced campers are not placed back. The 60 s warmup, placement
choice and navigation cost/jump tolerance are tier C measurement policy, not MapleStory facts or gameplay tuning.
CLI, record fields, aggregate semantics and seed separation are documented in AGENTS.md. Ticket #26 adds the
core measurements without changing balance data; #27 adds the cast snapshot trace. Training and held-out results
remain separate.

Spec #29 replaces #1/#27's “most runs clear” target (including the historical 22/30 result) with **40–50% sensible
clears and 5–15% careless clears** in Henesys. Death-only median time should fall between the first and third boss
arrivals, **300–900 s**. Potion usage now measures the cooldown model (#237); its starting values await the owner's
playtesting and the dedicated balance pass. (The old "careless runs observe MP waiting after 8:00" target went with
MP, #285.)
First-five-minute ordinary lifetime hits/kill and their denominators report whether early durability is meaningful;
mid-game mobs should typically need 2–3 hits.

The full-run regression uses predetermined training seeds 1/2/2026 on both stages, separate from population
acceptance. Henesys retains Mage/Lv10 median **180–330 s**, individual 150–360 s. The coarse owner-review pass
(sword-paced v83 Beginner, 2.5x stage EXP) moves Lv30 to median 540–720 s when reached, individual 480–1080 s, and
Lv8 to median 210–270 s, individual 180–300 s; Lv30 near 10:00 is earlier than the original 12:00–15:00 aspiration; the owner accepts the current
progression for now and will revisit it after more features. The regression windows remain unchanged. At least one of the three regression runs must reach Lv30 under the 40–50% clear target.
These windows apply only to reached milestones, with at least two of the three fixed runs reaching
Lv8/Lv10/Magician and every reach count printed. Occasional early deaths remain valid outcomes under the new population target; they are never filtered.
Spawning each minute (including after 15:00), crowd growth, EXP/kill/event consistency, all-boss finale, no lost mobs,
the inherited 30% engagement floor and late 200+ density remain active in Henesys. Runs observed for at least a full
minute after 8:00 must include at least five ordinary nonmiss hits; boss hits and misses cannot satisfy that check.

Tree outcomes and clear rate are recorded without judging pacing or difficulty. Its regression still checks
required cache data, no simulation warnings, EXP/kill/level event consistency, no lost mobs, correct deaths and
all scheduled bosses dead before a clear. A living Tree run at the cap is a timeout, never a clear. Earlier Tree
pacing tables and guards below are historical information. Freeze candidate data and guards before the full suite
and any fresh held-out assessment. **601–630 is consumed** by #30's frozen assessment below. Reserve fresh
**701–730** for the dedicated balance pass after its data and guards freeze. Spent or retired
101–130/201–212/301–330/401–430/501–530/601–630 are never reused for tuning or fresh evidence.

#### #346 Hero first-pass melee survivability

Tier C, training only: Hero starts at 600 HP (`balance.player.ap.112.hp`) and gains 65 HP/level
(`balance.growth.112.hp`). An absent AP-row `hp` preserves the shared baseline. Five pool cooldowns
are x0.4: Power Strike .4, Slash Blast .64, Brandish .56, Shout 4.8, Monster Magnet 4 seconds.
Panic stays 2 seconds and Coma 1 second with their shared one-second meter floor. Each held Combo
orb adds 5% damage; finishers add 20% per orb spent. These supersede #296/H3/H8 first-pass values.
No HP-cost, stun-duration, Rush, stage/ramp or F/P tuning changed; no opening multiplier was needed.
Targets: fresh Henesys boss 1/map 2 in >=2/3; kit Henesys >=1/12 clears; kit Sleepywood >=1/3 map 2.

## 4.2 Tuning record (`scripts/balance.sh`)

**#296 review fixes / H12, after integrating #346 (2026-10-28).** No balance values changed by the
review fixes: incoming AP HP 600, growth 65, orb 0.05, cooldowns and finisher coefficients are preserved exactly;
Hero AP/growth/score rows now live in `jobs/hero.json`'s `balance` block. Read-only cache, `ISOLATE=296fix`,
`JOBS=3`, seeds 1/2/2026; all four tier-1 stages bot/random for both jobs, Sleepywood bot starter/own fixture.
All **60 completed records** have no world warnings, missing assets or TIMEOUTs. A combined shell received
SIGTERM during kit startup after 27 records; only unfinished batches were resumed, with no source/config changes.
Complete records and console summaries: `_scratch/296-review/smoke/` and `_scratch/296-review/smoke.log`.

| Job | Clears / 30 | Henesys bot six slots | Henesys bot map 2 / 3 | Sleepywood kit map 2 / 3; clears / 3 |
|---|---|---|---|---|
| F/P 212 | 1/30 | 3/3; 136.7–205.3 s | 2/3 | 2/3; 1/3 |
| Hero 112 | 5/30 | 3/3; 139.9–249.2 s | 1/3 | 3/3; 2/3 |

F/P's 30 records reproduce the earlier smoke outcomes and times.
Hero's total matches H11's 5/30 clears, but its mix changes: random Henesys/Ellinia/Perion 1/3 each,
Sleepywood kit 2/3, all other configurations 0/3. All three fresh Henesys bot runs reach boss 1, but
**map 2 reach falls from H11's 3/3 to 1/3**, below #346's>=2/3 target. Sleepywood kit map 2 improves 2/3 -> 3/3.
These combined casting/admission changes need a later balance follow-up; no tuning or extra/held-out seeds were run.
Ellinia remains recorded rather than tuned. Hero bot death ranges: Henesys 327.7–688.2, Ellinia 221.0–646.5,
Perion 288.9–493.0, Kerning 326.8–568.7 seconds.

Merged-source full suites: **2151 passed / 0 failed / 0 skipped** cached; **1926 passed / 0 failed /
225 skipped** without cache (skips prove no asset behavior). Both F/P goldens and the repaired Hero golden
`409dba0d1bdffc32ba72644e326f99561e6ed9c0270feda39ace2573b0727cb3` match integration 3e37ec1 unchanged.
The change from the original H10 Hero hash came from #346's synthetic weapon-reach/cast assertion and
initial-state coverage repair, not a review-fix rebaseline. No tests deleted. Rush visual evidence remains
`evidence/296-review-uncapped/`; the 120-second, 7200-tick capture had missing assets `[]`.

**#296 review fixes / H12, before merging #346 (2026-10-28).** Regression smoke only; no balance tuning. Read-only default
cache, `ISOLATE=296fix`, `JOBS=3`, seeds 1/2/2026: every tier-1 stage with bot/random for 212 and 112,
plus Sleepywood bot with starter equipment and each job’s fixture. All **60 records** finished without
crashes, world warnings, missing assets or TIMEOUTs. Full reports remain in `_scratch/296-review/pre-346-smoke/`.
Compared with H10 below, F/P’s outcomes and recorded stage ranges reproduce; Hero remains 0/30 clears
with no scheduled boss defeated. Henesys boss-reach counts and bot six-slot coverage are unchanged;
Hero bot now also reaches Kerning’s first boss in 1/3. Hero death seconds shift after the casting/admission
fixes (Henesys bot 278.8–321.9, random 302.8–316.3); its known weak survival is left to #346.

| Job | Tier-1 clears (bot + random) | Henesys bot six actives | Henesys first boss, bot / random | Sleepywood clears, starter / kit |
|---|---|---|---|---|
| F/P 212 | 0/24 | 3/3; 136.7–205.3 s | 3/3 / 3/3 | 0/3 / 1/3 |
| Hero 112 | 0/24 | 3/3; 142.4–254.4 s | 2/3 / 3/3 | 0/3 / 0/3 |

Full suites: cached **2148 passed / 0 failed / 0 skipped**; without cache **1923 passed / 0 failed /
225 skipped** (skips prove no asset behavior). Both F/P goldens and the Hero golden remain unchanged.
A 120-second Hero visual playtest (seed2026, x4, vsync off) completed 7200 ticks with missing assets `[]`;
Rush’s streak/hit capture was inspected in `evidence/296-review-uncapped/`. No tests were deleted.

**#306 / H10 Hero enablement and H9 completion (2026-10-28).** No balance tuning. Read-only real cache,
`ISOLATE=306`, `JOBS=3`, training seeds 1/2/2026 only. All four tier-1 stages, bot/random, both jobs;
Sleepywood bot with starter equipment and each job's fixture (`hero_t2.json`, `fp_arch_mage.json`).
All **60 records** finished without crashes, world warnings or missing assets; no TIMEOUTs.
Records, complete console reports and machine summaries remain under `_scratch/306-smoke/<job>/<stage>/<policy-or-kit>/`.
Cells are **clears / 3; death-second range (deaths only); end-level range**.

| Stage / equipment | Hero bot | Hero random | F/P bot | F/P random |
|---|---|---|---|---|
| Henesys | 0/3; 259.2–322.3; 8–11 | 0/3; 302.8–326.8; 10–11 | 0/3; 305.0–651.7; 11–36 | 0/3; 308.3–309.9; 10–11 |
| Ellinia | 0/3; 144.5–156.3; 5–6 | 0/3; 155.5–163.6; 5–6 | 0/3; 629.1–644.2; 21–23 | 0/3; 328.4–660.2; 12–23 |
| Perion | 0/3; 229.8–251.1; 8–8 | 0/3; 201.8–256.4; 7–8 | 0/3; 305.7–456.3; 10–19 | 0/3; 308.7–421.5; 13–19 |
| Kerning | 0/3; 221.1–267.0; 8–10 | 0/3; 232.1–252.1; 9–10 | 0/3; 307.9–315.0; 12–13 | 0/3; 306.0–317.3; 12–13 |
| Sleepywood starter | 0/3; 7.2–7.6; 1–1 | — | 0/3; 10.6–12.0; 1–1 | — |
| Sleepywood kit | 0/3; 7.8–10.1; 1–3 | — | 1/3; 23.8–826.2; 8–72 | — |

**Melee survivability remains unresolved.** Hero cleared 0/30, defeated no scheduled boss, and reached the first
Henesys boss in 2/3 bot and 3/3 random runs; every other Hero run died before its first boss. Hero Henesys bot filled
six active slots at 134.1–253.2 s (3/3). Sleepywood's diagnostic equipment fixture did not make the opening survivable.
Per the owner's H10 instruction, QA continues and reports this to the orchestrator rather than tuning or stopping.
The later balance pass owns Rush cooldown/rank/knock-back, Slash Blast/Coma HP costs, Shout stun and the orb bonus.

F/P Henesys bot still fills six slots (136.7–205.3 s, 3/3) and reaches the first boss (3/3). The older H5 smoke above
had 1/3 Henesys and 2/3 kit Sleepywood clears, compared with 0/3 and 1/3 here; do not call those outcomes unchanged.
A paired seed-1 Henesys F/P control with Hero disabled produces a **byte-identical full record** to Hero enabled
(`_scratch/306-fp-disabled-control/henesys_bot_1.json`); this Henesys seed-1 difference from H5 is already present on the
integration tree, not introduced by Hero's playability flip. Other smoke differences are recorded without a cause
attribution. Ellinia is recorded only, pending the owner's rework.

Both real `redesign --job=112` and `--job=212` scenarios pass: creation, full-slot/Mastery/boss windows, three real
clear/fade/arrival transitions, kept equipment/mesos and unlocked tier, Sleepywood death, save/quit, deletion and history.
These are diagnostic invulnerable flows with post-timer boss hits, not survival evidence. The driver now drains stale
choice requests and waits for the window's input delay before injecting a number key (under load a visible window
could still reject that key). Screenshots in `evidence/h10/redesign_112/` and `redesign_212/` were inspected.
Ordinary Hero playtests (`--job=112 --speed=8 --vsync=off`) ended DEAD on Henesys seed 2026 at 304.9 s, Lv11,
and Sleepywood seed 1 with `hero_t2.json` at 8.3 s, Lv1; both `missing: []`. Art-only probes supply stationary,
durable targets and injected orbs for sword/axe finishers; no diagnostic probe code or art is committed.
The Mastery screenshot also exposes a pre-existing design gap: Monster Magnet's Normal Mastery advertises +5% damage
although the skill deals none. Its rarity bonuses work; #346 resolves this with cooldown x0.95, the same repeat counter and diminishing returns.

Hero's separate synthetic replay oracle hashes 7,200 fixed ticks twice (seed 1, explicit job 112, bot, invulnerable):
`9adb0cee8138e1bf1aa6f91a2656e1cd4ad29f8552913269dbe08ec0cb841661`. The two F/P oracle expectations are untouched.
Cached full suite: **2,137 tests, 0 failed, 0 skipped** (219 files); both existing F/P oracles and the Hero oracle pass.
No-cache full suite: **2,137 total, 1,912 executed passes, 0 failed, 225 SKIPs**; SKIPs prove no art behavior.
Every skipped test is named as `SKIP` in `_scratch/306-qa/no-cache-skips.log`. Final cached fixture/driver checks:
21 tests, 0 failed, 0 skipped.
Rust tests: 70 passed; web shell: 62 passed. Web export and artifact gate were **not run**: the pinned web templates
are absent (`godot_templates.sh dir`); merge readiness therefore carries this explicit unverified gate.


**#301 / H5 core melee regression smoke (training seeds 1/2/2026).** No balance tuning.
Shared real cache, `ISOLATE=301`; four tier-1 stages with bot/random, Sleepywood with bot,
with and without the tier-1 `fp_arch_mage.json` kit. All 30 runs finished without crashes,
world warnings or missing assets. Records and summaries are `_scratch/balance301/` (Sleepywood
in separate `starter/` and `kit/` folders because the script reuses its output names).

| Stage / equipment | Bot: clears; death seconds; end levels | Random: clears; death seconds; end levels |
|---|---|---|
| Henesys | 1/3; 449.9–711.5; 22–56 | 0/3; 308.0–615.4; 10–31 |
| Ellinia | 0/3; 625.4–650.9; 22–23 | 0/3; 321.8–688.0; 12–23 |
| Perion | 0/3; 430.6–668.6; 25–42 | 0/3; 277.3–574.8; 10–32 |
| Kerning | 0/3; 306.2–749.1; 12–42 | 0/3; 308.3–442.2; 13–23 |
| Sleepywood starter | 0/3; 10.6–12.0; 1 | — |
| Sleepywood tier-1 kit | 2/3; 792.2 (one death); 71–78 | — |

Henesys bot fills six active slots at 137.5–183.6 s and reaches the first boss in all three runs;
seed 2026 clears at 909.5 s. Henesys outcomes/times match the preceding #307 smoke.
Kit Sleepywood outcomes/times also match #307. The starter seed-2026 death differs from that older
record: running the unchanged integration code at 4419535 produces an **identical complete record**
(DEAD 12.0 s, Lv1), so this is not an H5 regression. Ellinia is recorded only, with no tuning.
The diagnostic Hero run (playable flipped, invulnerable, three core skills learned in a throwaway mirror)
ends PLAYING at 60.13 s, job 112, 18 kills, missing []; each `cast_<skill>` shot and the four-weapon,
seven-frame Brandish sheet were inspected in `evidence/h5-301/`. Full suite: **2028 tests, 0 failed,
0 skipped**, 210 files, 1598.1 s; F/P oracle expectations unchanged. The live shots draw at about 1 FPS;
they are cast/hit evidence, not performance evidence. The paused sheet verifies the body/weapon poses.

**#282 review fixes (2026-10-28).** Targeted regression requested for this review task:
Henesys, bot, training seed 1, real cache, no balance tuning or held-out seeds. Correct passive rarity RNG,
independent ground procs, poison refresh and mobility progression deliberately change seeded trajectories.
Both records have no warnings, missing assets or crashes; six active slots fill and two bosses die.

| Henesys seed 1 equipment | Outcome / time / level | Six actives | Map 2 / 3 entry |
|---|---|---|---|
| Starter wand | DEAD / 651.7 s / Lv36; 37 picks, 2,706 kills | 136.7 s | 312.7 / 616.6 s |
| Tier-1 F/P fixture (full-run guard check) | DEAD / 781.8 s / Lv47; 48 picks, 4,518 kills | 135.1 s | 308.2 / 611.3 s |

The previous #294 three-seed Henesys starter bot sample cleared 1/3; this task repeats only seed 1,
so it does not remeasure that whole cohort. The separate corrected full-run fixture sample
(1/2/2026) clears 0/3, with deaths at approximately 782/660/643 s.
This is a changed training baseline, not a balance claim. The feature regression retains six-slot, engagement,
event/finale and warning checks, and requires at least one third-map arrival (two defeated bosses), replacing
the old fixed-seed natural-clear quota. Natural-clear rate remains for the dedicated balance pass.
The redesign flow passed with 31 screenshots, no missing assets or failures; the windows flow passed with
10 screenshots. HUD and Stat MP masks were inspected by eye in `evidence/282fix/`.
Final verification: `ISOLATE=282fix bash scripts/test.sh`: **1,992 tests, 0 failed, 0 skipped**,
207 files; web shell: **62 passed, 0 failed, 0 skipped**.


**#307 / T11b opening ramp (training seeds 1/2/2026 only).** All candidates used absolute `PATCH=` files;
raw local records are `_scratch/307/`, not committed. Low starts (.001–.02 HP, .08 damage) made both
starter and kit viable, erasing the equipment gate. Raising only damage killed both builds on map 3.
A .3 HP / .4 damage opening separates starting weapons, but applying it to later maps made every kit
die just after map 2 arrival. Selected: that opening with power 6, plus map 2/3 overrides .02 HP / .08 damage
with power 3, all ending at 1 over 1,200 s of whole-round time. This is first-pass evidence, not a frozen assessment.

Paired Sleepywood smoke (seed order 1/2/2026; all start Lv1, no cash/pet):

| Starting equipment | Seed 1 | Seed 2 | Seed 2026 | Map 2 reached / clears |
|---|---|---|---|---|
| Unscrolled tier-1 kit (#307 called it `tier1_fp.json`; it is `fp_arch_mage.json` since #294) | DEAD, 792.2 s, Lv71 | CLEAR, 931.6 s, Lv72 | CLEAR, 921.6 s, Lv78 | 3/3; 2/3 |
| Starter wand only | DEAD, 11.4 s, Lv1 | DEAD, 11.9 s, Lv3 | CLEAR, 917.0 s, Lv77 | 1/3; 1/3 |
| Old `fp_arch_mage.json` (starter wand and clothes; replaced in #294) | DEAD, 11.4 s, Lv1 | DEAD, 11.9 s, Lv3 | CLEAR, 914.9 s, Lv77 | 1/3; 1/3 |

At #307 the committed `fp_arch_mage.json` was starter wand and clothes after the format-3 migration, and #293's
synthetic `tier1_fp.json` supplied the kit; both were checked explicitly. #294 merged them into the single committed
fixture, which is that kit with tier 2 unlocked (`game/tests/fixtures/characters/README.md`); the starter-wand case is a run
with no `--character`. Equipment enables the opening on seeds 1/2; seed 2026 escapes the starter gate and later
drops narrow the gap. This small paired sample does not establish a universal equipment wall.
All kit runs reach map 3 and six actives by 12.7–22.3 s. Clear picks 74/80 and levels 72/78 exceed the nominal
slice targets; this ticket changes no EXP/reward cadence and guards the requested Henesys envelope.
Kit completed boss fights: Zombie Mushmom median 6.23 s (3/3 spawned), Snack Bar 2.67 s (3/3), Jr. Balrog 18.29 s
(2/2); no unfinished or skipped fights, final boss not spawned on seed 1. The censored medians equal those
completed medians. All nine final Sleepywood records have warnings=[] / missing=[] and no crashes.
Henesys smoke with committed data (same training seeds, no character fixture): bot 1/3 clear,
449.9–909.5 s, Lv22–56; random 0/3 clear, 308.0–615.4 s, Lv10–31. These match #293's envelope.
All 15 final smoke records have warnings=[] / missing=[] and no crashes.
Final validation: `ISOLATE=307 bash scripts/test.sh` with the real cache: **1992 tests, 0 failed,
0 skipped**, 207 files, 1038.6 s. Seven deterministic ramp tests added; none deleted. Existing corrupt-settings
recovery diagnostics and two dummy TextureStorage RID shutdown diagnostics remain. The final integration
fetch/merge was already up to date (5cd40ea); no gameplay changes after validation. Final focused rerun: 7/7 passed.

**#299 / H3 meter infrastructure regression smoke (2026-10-28).** Job 212, real v83 cache,
training seeds 1/2/2026, bot/random on every tier-1 region and bot Sleepywood with/without the tier-1 kit.
No tuning or held-out seeds. All 30 records have empty warnings/missing lists, no crashes or timeouts.
All 30 records after merging H1/H2/H4 are byte-identical to the preserved pre-merge meter-runtime records.
Historical H7 results reproduce the preceding #294 smoke; Hero was then unplayable (before H9/H10), so Combo is exercised by
seeded synthetic tests and the diagnostic HUD probe rather than claimed as Hero survival evidence.

| Stage / kit | Bot clear / dead; time range; end level | Random clear / dead; time range; end level |
|---|---|---|
| Henesys | 1 / 2; 449.9–909.5 s; Lv22–56 | 0 / 3; 308.0–615.4 s; Lv10–31 |
| Ellinia | 0 / 3; 625.4–650.9 s; Lv22–23 | 0 / 3; 321.8–688.0 s; Lv12–23 |
| Perion | 0 / 3; 430.6–668.6 s; Lv25–42 | 0 / 3; 277.3–574.8 s; Lv10–32 |
| Kerning | 0 / 3; 306.2–749.1 s; Lv12–42 | 0 / 3; 308.3–442.2 s; Lv13–23 |
| Sleepywood, tier-1 kit | 2 / 1; 792.2–931.6 s; Lv71–78 | not sampled |
| Sleepywood, no character file (default sword) | 0 / 3; 10.6–12.0 s; Lv1 | not sampled |

Henesys bot fills six actives at 137.5/183.6/139.2 s and all three runs defeat Mano; the no-character
Sleepywood command still uses the tool's default sword, not the creation wand (same distinction as #294).
The tier-1 kit reaches map 3 on all seeds; seeds 2/2026 clear. Ellinia remains record-only, unchanged.
Raw records and exact configuration logs are retained under ignored _scratch/299-smoke and /tmp/299-*.log.

**#294 / T12, slice QA (2026-10-28).** The F/P slice after #307 (merged into the QA branch), real v83 cache, training seeds
1/2/2026 and no held-out seeds; nothing was tuned and no balance data changed. Raw records, consoles and screenshots live in the
ignored `_scratch/balance294/` and `evidence/` of the QA worktree.

*Flow scenario.* `flow_driver.tscn --scenario=redesign --seed=1` passed (exit 0, `missing: []`, 31 screenshots checked by eye;
about 6 minutes). Created an Arch Mage through name, look and the Job page; Sleepywood showed locked and its Start was
refused; the invulnerable Henesys round (diagnostic, bot steering, post-timer boss hits) ended Lv47, 3,697 kills, 900 s, with
49 picks (46 level-ups and three boss draws): first level-up at Lv2 (0:16), all six active slots full at Lv7 (3:00), the first
boss bonus draw at Lv12 (5:00), the first Mastery offer at Lv23 (7:40) under the scenario's own policy (it ranks the
highest-ranked owned active once the slots are full; the bot's policy does not reach rank 8 in this sample, section 0). The
offers: 14 Mastery, 8 new-active, 68 owned-active, 49 new-passive and 8 passive-rank cards, rarities 119 Normal / 22 Rare / 5 Epic /
1 Unique; 12 Mastery, 5 new-active, 28 owned-active, 3 new-passive and 1 passive-rank taken. The clear unlocked tier 2 and kept
the loot (991,759 mesos after the Sleepywood death); a reqLevel-30 shoe drop was worn at Lv1 by a double-click in the Item window (no REQ rows
in the tooltip); the Sleepywood round picked up 475 mesos on the ground and a diagnostic lethal hit ended it at Lv1; back in
the Free Market the mesos, the worn shoes and tier 2 were intact; after Save & quit the character was deleted and the
history listed cleared (Henesys, Lv47), died (Sleepywood, Lv1) and deleted. Every other kept scenario (`title`, `import`,
`windows`, `skill`, `keys`, `inventory`, `scrolls`, `shops`, `botshop`, `cash_shop`, `cash_equip`, `account`) also exits 0 (each
checks its own asset lookups); `clear` passes with `--run=henesys --seed=2026 --autoplay --autopick --speed=8`. The
`maps`, `rounds`, `full` and `economy` scenarios were deleted, as were the debug drivers of the unported lines (AGENTS.md).

*Playtests* (`playtest.sh --job=212`, windowed, screenshots checked by eye, `missing: []` in every summary):

| Run | Result |
|---|---|
| Henesys seed 2026, x4, `--window-autopick=1` | CLEARED at 913.5 s (15:13), Lv56, 6,306 kills, 330 mobs at most, 58 level-up windows (55 level-ups and 3 boss draws), map entries at 0 / 308.5 / 611.1 s |
| Henesys seed 2026, `--warp=600 --minutes=13 --speed=1 --vsync=off --require-window --min-frames-100=120 --min-frames-200=60` | QUALIFIED: warped to 600 s, 10,800 ticks, 31,039 frames with 100+ mobs and 23,302 with 200+; alive at 13:00, Lv44, 4,168 kills, 272 mobs at most |
| Sleepywood seed 2, tier-1 kit (`fp_arch_mage.json`), x4, `--window-autopick=1` | CLEARED at 933.4 s, Lv72, 6,074 kills; Lv13 and 187 kills at 1:00; map entries at 0 / 307.1 / 612.4 s |
| Sleepywood seed 2, starter wand only (no `--character`), x4 | DEAD at 12.1 s, Lv1, 0 kills, on map 1 |

*Frame time* (the Henesys warp run above, `--vsync=off`, past 10:00 with 200+ mobs): frames over the whole 600-780 s window
p50 3.36 ms, p95 6.72 ms, p99 7.64 ms, max 47.2 ms (average 3.80 ms); frames with 200+ mobs p50 3.72 ms, p95 7.03 ms, p99
7.97 ms; `frame_work_us` average 1,940 / p50 1,654 / p95 4,110; `sim_us_per_tick` 1,355. Conditions: an Intel UHD (CML GT2)
through Mesa's GL Compatibility driver, 12 logical cores, load average about 1.2-1.5; `pgrep -c godot` read 1 at the start
(another worktree's headless balance job) and 0 at the end, besides the measured window itself. This is a throughput
check of the slice, not a frame budget. Earlier tickets saw about 1 FPS in windowed runs with many agents running Godot; here a
vsync-on window also measured 1 FPS with one to three other Godot processes alive, while the same scene ran at 750+ FPS with
`--vsync=off`, so that was the window's frame pacing under vsync, not load. The flow driver therefore runs uncapped.

*Regression smoke* (`balance.sh 1 2 2026`, bot and random on every tier-1 stage; Sleepywood with the kit and with the starter
wand and with no `--character`; 33 records, no warnings, no missing assets, no crashes). Tier 1 reproduces #293's smoke exactly (the tier-1 ramp is neutral);
Sleepywood reproduces #307's paired table:

| Stage / starting equipment | Bot | Random |
|---|---|---|
| henesys | 1/3 clear; 449.9-909.5 s; Lv22-56; six actives at 138-184 s | 0/3 clear; 308.0-615.4 s; Lv10-31 |
| ellinia | 0/3 clear; 625.4-650.9 s; Lv22-23 | 0/3 clear; 321.8-688.0 s; Lv12-23 |
| perion | 0/3 clear; 430.6-668.6 s; Lv25-42 | 0/3 clear; 277.3-574.8 s; Lv10-32 |
| kerning | 0/3 clear; 306.2-749.1 s; Lv12-42 | 0/3 clear; 308.3-442.2 s; Lv13-23 |
| sleepywood, tier-1 kit | 2/3 clear (seeds 2, 2026); seed 1 dies on map 3 at 792.2 s; 792.2-931.6 s; Lv71-78; picks 72-80; six actives at 13-22 s | not sampled |
| sleepywood, starter wand | 1/3 clear (seed 2026, 914.9 s, Lv77); seeds 1 and 2 die at 11.4 s (Lv1) and 11.9 s (Lv3) | not sampled |
| sleepywood, no `--character` (default sword, no MAD) | 0/3 clear; 10.6-12.0 s; Lv1; 0 kills | not sampled |

Henesys random fills six slots at 306/323 s on two seeds and dies before filling them on the third; Ellinia remains early
death and is record only. Sleepywood kit boss fights: Zombie Mushmom median 6.23 s (3/3 completed), Snack Bar 2.67 s
(3/3), Jr. Balrog 18.29 s (2/2 spawned; the final boss never spawned on seed 1's map-3 death). The kit reaches map 3 in 3/3
runs, against 1/3 for the starter wand, so equipment does matter; the gap is not a wall, because the starter wand
clears on seed 2026 (section 0 gaps). The smoke raises no new finding of the kind that stops a feature ticket (no stage where
every run dies before the first boss, none where every run clears without a death).

Final validation (#294): `ISOLATE=294u bash scripts/test.sh` with the real cache: **1992 tests, 0 failed, 0 skipped**, 207 files,
1,016.9 s (the merged tree, #307 included; no test file deleted, one fixture test replaced, three fixture-dependent tests
updated); `cargo test` 70 passed, 0 failed; `node --test web/dev/test/*.test.mjs` 62 passed, 0 failed.

**#293 / T11, first-pass candidate selection.** Training seeds 1/2/2026 only; no held-out or 701–730 seeds.
All candidates used absolute `PATCH=` files before committing selected data. With the bot fix in every probe:
EXP `(4,6,0.5)` cleared Henesys 3/3 but ended Lv137–142; `(64,-60,8)` died 3/3 at Lv15–22 and was rejected
(the minimum clamp also makes its opening uneven); `(4,0,8)` died 3/3 at Lv10–17. Adding cooldown x0.4
cleared 1/3 fresh runs (Lv56), but the unscrolled tier-1 kit died 3/3 at Lv36–41. The selected candidate adds
the three defensive passive values above: kit clears 2/3, Lv51/58 at 908.8/905.6 s, with 53/60 picks;
seed1 dies on map3 at 652.3 s, Lv36. All kit runs fill six actives at 131–167 s. Local raw records/logs live
under `_scratch/293/`, not in git. This narrow sample establishes plausibility, not clear probability.

**Bot behaviour fix:** after three actives, common-passive base scores gain 20 points: useful global boosts
can beat an ordinary rank, while new actives still win. Mastery scores its actual diminished effect at 100 points
per unit (e.g. 5% = 5, +1 hit = 100), instead of 6 per unit; repeat decay therefore lowers its priority.
Random choice, draw weights and eligibility are unchanged. This fixes the old bot's starvation of all passives.

Final smoke, seeds 1/2/2026 (seconds include the whole round; ranges include deaths and clears):

| Stage / starting equipment | Bot | Random |
|---|---|---|
| henesys | 1/3 clear; 449.9–909.5 s; Lv22–56 | 0/3 clear; 308.0–615.4 s; Lv10–31 |
| ellinia | 0/3 clear; 625.4–650.9 s; Lv22–23 | 0/3 clear; 321.8–688.0 s; Lv12–23 |
| perion | 0/3 clear; 430.6–668.6 s; Lv25–42 | 0/3 clear; 277.3–574.8 s; Lv10–32 |
| kerning | 0/3 clear; 306.2–749.1 s; Lv12–42 | 0/3 clear; 308.3–442.2 s; Lv13–23 |
| Henesys, tier-1 kit | 2/3 clear; 652.3–908.8 s; Lv36–58 | not sampled |
| Sleepywood, starter / tier-1 kit | both 0/3 clear; 7.0–8.1 s; Lv1 | not sampled |

All 24 tier-1 records and six paired Sleepywood records have no warnings/missing assets or crashes.
Henesys kit boss completed fight medians: Mano 5.27 s (3/3 spawned), Mushmom 1.95 s (3/3),
Blue Mushmom 1.10 s (2/2); no unfinished fights. The last boss was not spawned on the map-3 death.
Sleepywood is **not yet viable**: both the historical starter fixture and the unscrolled tier-1 kit die on
map1 at Lv1 with zero kills, before any pick/passive/rarity can help. This does not demonstrate a working
gear ladder. The tier-2 opening needs a separate starting-power or opening mob/spawn review; those rules
were not changed here. No chain assessment was substituted for standalone Lv1 rounds. Random Henesys fills
six slots at 306/323 s on two seeds and dies before filling them on the third; the ~5:00 target is established
for the sensible bot, not every careless build. Clear levels 56/58 exceed the nominal 55 upper target slightly;
recorded within the documented 40–60 regression envelope, not claimed to meet every target.

Final validation (#293): `ISOLATE=293 bash scripts/test.sh` with the real cache: **1985 tests, 0 failed,
0 skipped**, 206 files, 1002.5 s. No tests deleted; contact/relocation/schema fixtures isolate the mechanic
from faster starting spells, and the EXP/cooldown-dependent replay baselines were refreshed.



**#291 summon regression smoke (2026-10-28).** Seeds 1/2/2026, every tier-1 stage, bot/random,
read-only T1 cache, no patches or tuning. All 24 records ended DEAD, warnings=[] and missing=[]; no crashes.
Ellinia's known early deaths remain. Henesys seed-1 bot now dies at 378.5 s, Lv16, map 2, compared with
#290's 307.8 s, Lv12, map 1. Mano completes in 39.40 s for that seed; across Henesys bot, completed 3/3 spawned,
completed median 28.40 s and censored median 28.40 s (0 unfinished); later bosses never spawned.
No held-out seeds used. Full console reports and records are local `_scratch/balance291/`.

| Stage | Bot death seconds (min–max), end levels | Random death seconds (min–max), end levels |
|---|---|---|
| Henesys | 350.9–395.4, Lv16–19 | 307.0–371.3, Lv12–17 |
| Ellinia | 35.2–76.4, Lv1–2 | 35.2–76.4, Lv1–2 |
| Perion | 308.4–424.6, Lv13–20 | 306.7–340.6, Lv13–14 |
| Kerning | 304.8–307.1, Lv14 | 306.9–311.7, Lv14–15 |


Pacing is measured with `bash scripts/balance.sh [seeds | a..b] [--policy=...]` (whole headless runs on the real map,
`game/tools/balance_run.gd`). Movement is always the autoplay bot (`BotInput`): it kites on the ground, walks to EXP drops
and climbs a ladder or rope to drops left on a platform above; the character is always the default job (Arch Mage, 212; the
bot draws no job, ADR 0006). Card policies: `bot` uses `BotInput.pick_card_for` (learning a pool skill 100, ranking 74, the
common passives after three actives, Mastery by the value of its diminished bonus; section 5), each plus
`bot.gain_step_score` per step an offer grants beyond its first (#63); `random` is a careless player who takes a random
card of the three (the old `--first-card` policy is no longer a careless proxy: it always takes the
guaranteed card, which UpgradePool puts first). `--idle-after=300` takes the hands off the keys at 5:00. Older records below
quote the bot's former job draws, basic-attack duels and Guard scores: they describe the game of their date.

#### #346 candidate comparison

Absolute `PATCH=` variants, `ISOLATE=346`, `JOBS=3`, training seeds 1/2/2026 (kit Henesys 1..12).
A: growth65, five cooldowns x.4, orb .05 / finisher .20; B adds HP300; C adds HP1000;
D selects HP600. A missed both three-seed targets. B met fresh Henesys but missed Sleepywood.
C cleared kit Sleepywood3/3; reduced the baseline and stopped its unfinished batches before D.
B's unfinished kit batch and C's unfinished fresh/kit batches are not target evidence.
D's fresh Henesys: clear966.7 / dead674.0 / dead447.0, all map2; kit Sleepywood:
dead656.5 / dead223.9 / clear906.9, two map3. No claim of frozen balance or F/P parity beyond these targets.
Raw records and logs stay in `_scratch/346/`; no held-out seeds used.

The complete 30-run Hero regression smoke (tier-1 bot/random seeds1/2/2026, Sleepywood starter/kit bot)
has 5 clears / 25 deaths / 0 timeouts, warnings=[] and missing=[] throughout; no crashes. Compared with
H10's 0/30 Hero clears, tier-1 clears are Henesys bot1/3, random1/3, Perion random1/3 and Kerning random1/3;
all other tier-1 configurations remain0/3. Ellinia remains record-only (deaths224.2–935.8s).
Sleepywood starter remains0/3 (deaths16.4–20.2s); kit1/3 with2/3map2. Henesys bot six slots fill at
130.6–253.0s (all3), with first boss defeated3/3. These samples meet H11 targets without claiming all-stage viability.
The paired seed1 Henesys F/P record is byte-identical before/after (SHA-256 `a5a9901ca32b43059550b9de45a731ebf5dc1959785a8a76374679fc8cb4c942`);
both F/P oracle files are unchanged. Hero's old replay cast nothing because its synthetic weapon lacked afterimages;
H11 adds existing synthetic swing reach, a cast-coverage assertion and initial-player-state digest, then recaptures
`409dba0d1bdffc32ba72644e326f99561e6ed9c0270feda39ace2573b0727cb3` with independent repeat equality.


| Configuration | Before | Chosen D |
|---|---|---|
| Henesys fresh bot, 1/2/2026 | boss1/map2 0/3; clears0/3 | boss1/map2 3/3; clears1/3 |
| Henesys Hero kit bot, 1..12 | clears1/12 (seed3) | clears4/12 (seeds1/3/5/7) |
| Sleepywood Hero kit bot, 1/2/2026 | map2 0/3; deaths7.8–10.1s | map2 2/3; clears1/3; deaths223.9/656.5s |

### Spec #282 / #288: rarity and Mastery regression smoke (2026-10-28)

`ISOLATE=288`, real cache, seeds 1/2/2026 on all tier-1 stages, bot and random, no PATCH or tuning/held-out seeds.
All 24 records: no crashes, warnings or missing assets; all DEAD, no clears/timeouts. This remains the incomplete
four-active build before common passives/new attacks/pacing. Henesys seed 1 bot dies at 307.70 s / Lv12, versus
#287's 309.90 s / Lv12: both spawn Mano at 300 s, neither finishes it (current completed 0/1, censored >=7.65 s).
Job is already 212; the obsolete "reach Magician" advancement check no longer applies. Ellinia still dies early,
recorded without tuning. Values below are death seconds min/median/max, three observations per cell.

| Stage | Bot deaths (s), n=3 | Random deaths (s), n=3 |
|---|---|---|
| Henesys | 306.0 / 307.7 / 309.1 | 306.8 / 308.3 / 336.9 |
| Ellinia | 35.2 / 39.2 / 76.4 | 35.2 / 39.2 / 126.3 |
| Perion | 277.5 / 294.4 / 429.7 | 294.8 / 303.5 / 305.3 |
| Kerning | 304.3 / 311.4 / 315.2 | 305.5 / 306.6 / 309.1 |

Raw records/summary logs stay in ignored `_scratch/balance288/`. Short graphical Henesys seed-1 x8 playtest
ends PLAYING at 60.10 s, Lv3, 13 kills, missing []; screenshot inspected (no performance claim: about 1 FPS here).

#### Spec #282 (#285): no MP and no level gap: regression smoke (2026-10-28)

Branch `t/285-remove-mp` off `spec/282-fp-slice`, real v83 cache, isolate `285s`, seeds 1 / 2 / 2026, `bot` and
`random`, all four tier-1 regions; no PATCH, tuning or held-out seeds. Every command exits 0; every record has
`warnings: []`, `missing: []` and no MP field (`mp_short_seconds`, `late_mp_*`, `mp_absorbed`, `potions_used.mp` are
gone). C = CLEARED, D = DEAD, `@N` the one-based ending map, `jN` the final job:

| Region / policy | Seed 1 | Seed 2 | Seed 2026 |
|---|---|---|---|
| Henesys bot | D 653.3@3 Lv44 j210 | C 973.5@3 Lv56 j230 | D 652.4@3 Lv44 j130 |
| Henesys random | D 422.7@2 Lv23 j200 | D 408.6@2 Lv22 j200 | D 306.5@1 Lv11 j100 |
| Ellinia bot | D 638.1@2 Lv26 j200 | D 651.5@3 Lv28 j200 | D 312.3@1 Lv11 j100 |
| Ellinia random | D 628.6@2 Lv24 j200 | D 304.3@1 Lv13 j200 | D 309.1@1 Lv13 j100 |
| Perion bot | D 466.6@2 Lv26 j200 | C 939.9@3 Lv44 j230 | D 456.9@2 Lv26 j100 |
| Perion random | D 341.9@2 Lv16 j200 | D 327.9@1 Lv15 j200 | D 328.6@1 Lv15 j100 |
| Kerning bot | D 310.3@1 Lv14 j200 | C 931.4@3 Lv47 j230 | D 420.1@2 Lv27 j100 |
| Kerning random | D 308.0@1 Lv14 j200 | D 304.8@1 Lv14 j200 | D 339.4@2 Lv19 j100 |

Skills casting on every cooldown makes runs stronger than the #257 / Kerning-walls records below (there every Kerning
run died near 308 s on map 1 at Lv14-15): 3 of 12 bot runs clear and several reach Lv44-56, while every random run
still dies, most around the first boss. That is a pacing signal for #293, not a breakage. `test_full_run`'s Henesys
engagement floor dropped from 0.3 to 0.2 (seeds 1 and 2026 now measure 0.26 and 0.24: the casting mage clears its
surroundings); #293 owns the bound.

#### Walls stop only their own structure: Kerning's invisible walls (2026-10-24)

Owner report: on Kerning City Construction Site (103010000) the brick stairs left of the x -630 landing, and a flat
stretch of the lower ground, had invisible walls. Cause: `FootholdMap.wall_hit` tested every wall of the map, and
the layer-0 building's faces (group 3: x -710, y 1206-1590; x 350, y 1326-1650) and two layer-1 faces (x -595, 505)
stand across the layer-1 stairs (foothold 181) and the layer-2 ground (y 1386, 1506). New rule ("Wall scope" in 11,
tier B): a wall stops a body only when it belongs to the body's platform (same group, linked, group 0 or cantThrough).
On the 16 in-use maps it removes exactly 9 floor/wall crossings, all on 103010000, opens no platform end and leaves
no platform closed on both ends by its own walls taller than the 77 px jump apex (no new side-entry pocket). The
#259 "pocket" between x 350 and x 505 was these walls; the bot's wall memory stays (it still serves real walls).
Smoke, `caches/s253`, seeds 1 / 2 / 2026, bot and random: Henesys and Perion records byte-identical; Ellinia 5 of 6
identical, bot seed 1 diverges from 620 s on map 2 (100040100, where every wall is a 22 px skirt under a floating
platform end: airborne bodies and mob jump arcs no longer bump other platforms' skirts) and dies at 630.8 s instead
of 632.7 s, same EXP by minute. Kerning, death @ map and level:

| Policy | Before | After |
|---|---|---|
| bot | 308.2@1 Lv15 / 310.8@1 Lv15 / 306.9@1 Lv14 | 307.7@1 Lv14 / 307.8@1 Lv14 / 318.6@1 Lv15 |
| random | 304.5@1 Lv14 / 309.1@1 Lv14 / 305.2@1 Lv14 | 306.6@1 Lv14 / 314.5@1 Lv15 / 308.7@1 Lv14 |

Every Kerning run still dies a few seconds into King Slime's fight (balance signal for #77). All records
`warnings: []`, `missing: []`. The complete suite on `caches/s253` passes **2,213 tests, 0 failed, 0 skipped**
(214 files, 780.238 s), with the usual two dummy texture RID allocations at shutdown; the swarm invariant
(`WF.swarm_violations`) now checks each mob's own walls (`WF.swarm_wall_platforms`).

#### Spec #253 (#261): the bot keeps its weapon family at the second advancement (2026-10-23)

Integration tip `bac7a1e` plus this fix, cache `caches/s253`, isolate `t261`, no tuning ("Bot second-job family" in
11). **Bot records, seeds 1 / 2 / 2026, all four tier-1 regions: identical before and after** (state, time, kills,
level, job, map_times, ended_map, hits/level/EXP by minute, job_times, boss_fights, potions, cards; `warnings: []`,
`missing: []`): no run reaches Lv30 on the untuned data, so no second advancement happens. `--job=500:knuckle` on Perion
seeds 1..6 is also identical (all die by 7:11, Lv11-22). On the #77 C05 patch (`t77/C05.json`, diagnostic only, not a
candidate), Perion `500:knuckle` seeds 1..6 go from 3/6 clears (seeds 1, 4, 5 drew Gunslinger; 5 died at 1088.5 s
Lv30) to 4/6, and every record now equals the `510:knuckle` cohort's field for field (seeds 1/2/4/5 clear, seed 3 dies
at 1059.6 s Lv30, seed 6 at 316.8 s Lv12).

#### Spec #253 (#260): Kerning floor/wall corner leak and boss-arrival bound (2026-10-23)

Integration base `d50443a`, isolates `t260*`, cache `caches/s253`, no PATCH or tuning. **Root cause:** the air
sub-step only tested landing on the floor under its end x. Held against the x 3185 wall of Line 1 <Area 1>
(103000101) and steering into it, a fall crosses the y 323 floor line inside the floor while the sub-step ends 0.004 px
past the end x; the 1 px wall probe at the crossing x is already below the wall's foot, so neither caught it (10 of 40
sub-pixel start heights in `test_player_motion`). Recovery then stood the player exactly on the end point, which a
wall line does not block, so it walked off again. Fixes in section 3 and section 11 (corner landing, recovery inset,
`arrival_fallback` 15 s). **Not windowed-only:** both paths run the same fixed 1/60 s ticks with an 800 x 600 view
(measured in the window), and at `d50443a` the headless `balance_run` Lv38 fixture Kerning seed 1 shows the same stall:
TIMEOUT at 1800 s on map 2, Shade `not_spawned`, Lv85. After the fix it is **CLEARED at 922.1 s, Lv59** (map entries
0 / 307.0 / 613.2 s, bosses dead at 303.0 / 607.0 / 913.2 s; Shade arrives on schedule, no fallback needed). Seed-1 bot
records of Henesys, Ellinia, Perion, Kerning and the Sleepywood Lv38 F/P fixture are **identical field for field** to
`d50443a`. A boss record gains `postponed_since` / `relocate_since` / `fallback` only once a postponement or failed
relocation happens. The windowed playtest (`playtest.sh --stage=kerning --seed=1 --character=<fp_arch_mage.json>`,
x4) clears all three maps in 923.5 s at Lv59, `missing: []`. Screenshots, checked by eye: the character standing
against the x 3185 wall at 8:00, Shade's arrival at 10:07, map 2 CLEAR at 10:13 and the final CLEAR at 15:23
(`evidence/spec253/t260/kerning_fixture_s1_x4/`). The complete suite on `caches/s253` passes **2,198 tests, 0 failed, 0 skipped** (212 files).

#### Spec #253 (#257): Perion and Kerning City QA smoke (2026-10-23)

Integration base `ded803a` (T1-T3 merged) plus this ticket's bot fix, Git Bash, isolates `t257*`, cache
`caches/s253`. Seeds **1 / 2 / 2026**, `bot` and `random`, on Perion and Kerning, both regions' `--tier=2` chains, and
the unchanged-check reruns of Henesys, Ellinia, the Henesys chains and the Sleepywood Lv38 F/P fixture: 48 started
rounds, every command exit 0, every record `warnings: []` / `missing: []`. No PATCH, tuning or held-out seeds.
D = DEAD; `@N` is the one-based ending map; times in seconds; unobserved entries are absent, never zero.

| Region / policy | Death s @ map (1 / 2 / 2026) | Map-2 entry s | Lv10 / first job s (id) | Map-1 boss fight s | Compared with T1 (#254) bot smoke / #249 |
|---|---|---|---|---|---|
| Perion / bot | 423.7@2 / 382.4@2 / 306.8@1 | 342.0 / 318.3 / absent | 248.6 (200) / 260.3 (200) / 255.5 (100) | Mano 42.0 / 18.2 / unfinished >= 6.8 | T1 62@1 / 383@2 / 432@2: seed 1 is the fixed bot bug below; 2026 shifts with it |
| Perion / random | 383.5@2 / 460.2@2 / 389.5@2 | 318.4 / 438.0 / 342.8 | 240.5 (200) / 295.5 (200) / 241.4 (100) | Mano 18.3 / 138.0 / 42.8 | new |
| Kerning / bot | 237.5@1 / 308.7@1 / 311.7@1 | absent x3 | absent / 234.3 (200) / absent | King Slime not spawned / >= 8.7 / >= 2.7 | T1 238 / 309 / 312, all @1: same |
| Kerning / random | 237.5@1 / 307.6@1 / 302.8@1 | absent x3 | absent / 253.6 (200) / absent | not spawned / >= 7.5 / >= 2.8 | new |
| Henesys, Ellinia (bot, random), Henesys chains, Sleepywood fixture | as #249 | as #249 | as #249 | as #249 | identical on state, time, kills, level, job, map_times, ended_map, hits/taken/level by minute, potions, reach, job_times, boss_fights, warnings, missing |

Of the **12 fresh Perion/Kerning runs, 5 reach map 2 (all Perion) and 0 reach map 3**; every Perion map-2 entrant dies
there before Stumpy's arrival (`not_spawned`), and every Kerning run dies on map 1, four of six within 12 s of King
Slime's 300 s arrival. All four chains stop in tier 1 with zero tier-2 feeds; their tier-1 rounds equal the plain
rows. Ellinia's Dyle (110 casts since #255) is unobserved: no Ellinia run reaches map 3. Iron Hook, Shade and Dyle never
spawn in a fresh smoke run. This is a record for #77, not authority to tune.

**Perion seed 1 (bot), 62 s at Lv1: a bot bug, fixed.** West Street Corner of Perion (102010000) has four two-way
hidden portal pairs (hide00..03 <-> tohide00..03). From 55.8 s the bot escaped a Blue Snail crowd through hide00, then
its drop route took tohide00 straight back down into that crowd on the next 0.384 s portal cooldown, and so on: 14
portal uses (`camper.portals`), relocations 192% of spawns, 7 hits in 6 s under the shrinking hit window. Spawn
placement, slopes, ropes and falling were ruled out by the frame trace and screenshots. `BotInput` now keeps the
reverse link closed for 5 s after a warp (`REVERSE_PORTAL_HOLD`, tier C; test_bot_portals). Seed 1 then lives to
423.7 s @2; seed 2026 also changes (432@2 to 306.8@1), as any Perion seed may. Henesys, Kerning and Sleepywood maps have
no same-map links, and Ellinia's records are unchanged, so the hold is gated by the identical old-region rows above.

**Kerning seeds 1/2026: a bot stall on map 1, not balance signal (to file).** On Kerning City Construction Site
(103010000) the bot drops off the start ledge within 5 s into a pocket of the layer-2 floor (y 1506) between a wall at
x 350 (y 1326-1650) and the 30 px step at x 505 (wall y 1476-1620), then walks into the x 350 wall toward the map
centre (or the walled-off ladder at x 215), flips for 0.75 s, and repeats. Signature: `exp_by_min` flat (50, 50, 75)
while `drops_by_min` climbs (4, 25, 58), no hits until death, `reach {}`; seed 1 dies at Lv3 to two Octopus touches
(68, 76), seed 2026 stalls partially (EXP 50/50/255/255). Its jump apex (~77 px) clears the step, so a player walks
out. No bot target checks `walk_blocked` and the stuck handler jumps backwards; that is bot work for its own ticket.

**#259: the pocket stall, fixed.** Root cause, from a frame trace of seed 1: the drops past the step (y 1416, 90 px up)
exceed the walkable reach (0.7 × magnet 90 = 63 px) and count as "above", so the bot heads for the x 215 ladder, which
starts on the same layer-2 floor chain behind the x 350 wall (or for the map centre, also beyond it). The stuck rule
flipped it for 45 ticks with a backward jump from both walls, so at the step it turned back into the pocket. Now a
stall at a wall low enough to clear jumps on, and a stall at a taller wall is remembered for 30 s: goals beyond it are
skipped, the centre beyond it sends the bot away, and the wall bounds the kiting room like the map edge ("Autoplay
walls" in 11; test_bot_walls). Bot records, seeds 1 / 2 / 2026 on `caches/s253`, death seconds @ map and level:

| Region | Before | After |
|---|---|---|
| Kerning | 237.5@1 Lv3 / 308.7@1 Lv14 / 311.7@1 Lv7 | 308.2@1 Lv15 / 310.8@1 Lv15 / 306.9@1 Lv14 |
| Henesys | 308.3@1 Lv12 / 451.8@2 Lv25 / 310.0@1 Lv12 | 308.3@1 / 435.4@2 Lv24 / 310.0@1 (seed 2: same EXP through minute 5, same 24.6 s map-1 boss fight and 324.6 s map-2 entry; EXP differs from minute 6) |
| Ellinia | 632.7@2 / 39.1@1 / 34.7@1 | unchanged |
| Perion | 423.7@2 / 382.4@2 / 306.8@1 | unchanged |

Kerning `exp_by_min` now climbs on every seed (seed 1: 80, 400, 1085, 2337, 5433; was 50, 50, 75), Lv10 at 219-231 s,
and all three die on map 1 a few seconds into King Slime's fight (300 s arrival), like Henesys seeds 1/2026: balance
signal for #77, not a stall. All records `warnings: []`, `missing: []`. A first cut that treated 58 px as the clearable
height (0.75 of the apex) left the synthetic test map's 60 px pit walls "tall": the bot bounced inside the pit and the
`test_full_run` synthetic run died at 43 s; at 0.85 it jumps out and that run lasts 439 s to Lv21 (was 305 s, Lv8).
The synthetic bot digests (`test_bot_melee`, `test_character_baseline`) are re-captured; with the wall rule disabled
they reproduce the old values exactly.

**Kerning map 2: a corner leak that blocks Shade (to file).** In the windowed Lv38 fixture seed 1 run the character,
grounded at the end of Line 1 <Area 1>'s y 323 floor (x 2880-3185) where the x 3185 wall (y -360 to 323) rises, is
knocked airborne at x 3184.99 and next frame is at (3185.87, 386): the landing on y 323 is missed while x crosses the
wall line below its end. Below lies a floorless void (x 3185-3475, VRBottom 570); fall-out recovery snaps back to that
same floor end and the loop repeats. With no foothold, every Shade arrival is postponed ("Shade will appear in 3
seconds!" from 607 s to the 1800 s cap, `boss_warning_1` without `boss_arrival_1`, PLAYING at 1800). Reproduced three
times windowed (`kerning_fixture_s1_x4`, `_probe_`, `_void_`; frame log under `VOID entered`); headless `balance_run`
with the same seed does not hit it (Shade dies at 613 s). Candidate fixes: a swept corner check in the air substep, a
recovery that never lands on a floor end flush with a wall, and an `sp` fallback after repeated boss postponements.
A headless run caught there reports TIMEOUT, a measurement artefact.

Windowed evidence, checked by eye, all `missing: []`: fresh x4 playtests (seed 2026) die at 306.8 / 311.7 s on map 1
(Kerning's shows the pocket stall). The Lv38 fixture seed 1 dies on Perion map 3 (664.1 s, Lv53) and on Kerning stalls
as above. **Invulnerable diagnostic** captures (real attacks, no lethal injection) clear Perion and Kerning from the
fixture (913.9 / 934.1 s, Lv57/61) and from a fresh Beginner (1067.8 / 1029.7 s, Lv29/35). They show every map with
its own mobs (Perion: Blue/Red Snails and Stumps, Dark Axe Stumps, Fire Boars and Wild Boars; Kerning: snails, Slimes,
Orange Mushrooms, Octopus, Bubblings, Ligators) and each boss arrival, Shade's Banish (notice "As the Pentacle swayed
in the shadows, you were thrown elsewhere in the Subway." and the `affected` art on the character, Line 1 <Area 1>),
Dyle's Attack Up (the 110 area art across the Ligators, then the buff glow on Dyle) and Iron Hook's Attack Up cast
burst. Iron Hook dies before his first 40 s interval in every natural or diagnostic fight, so that capture adds a
**x20 HP diagnostic tank** and holds the camera on him (harness-only presentation aid, never data). Every map entry
reports BGM playback matching `info/bgm` (Perion Nightmare, Nightmare continuing, HighlandStar; Kerning BadGuys,
Subway, JungleBook). The map select shows four cards in `tiers` order; with Perion or Kerning City selected the detail
lists `West Street Corner of Perion -> Mano`, `East Rocky Mountain V -> Stumpy`, `The Burnt Land I -> Iron Hook` and
`Kerning City Construction Site -> King Slime`, `Line 1 <Area 1> -> Shade`, `The Swamp of Despair I -> Dyle`; the
angle brackets render literally, in the arrival banner too. Evidence: `C:/Users/itech/.t3/projects/maple-survivors/.claude/worktrees/agent-ab003e6a203a7ede5/evidence/spec253/t257/`
(harness, probes and scripts in `diagnostic-sources/`).

The `maps` flow driver gains `--stage=<tier-1 key>` (default henesys): `perion`, `kerning` and `henesys` all PASS
(`failures: []`, `missing: []`), with real CLEAR/fade/arrival shots on each map, the map-2 Save & quit leaving the
boundary bytes unchanged, Continue replaying map 1 with seed 1, entries 300.000 / 600.017 s (Kerning 312.000 /
612.017 s: King Slime arrives at 303 s, one postponed arrival) and the Free Market boundary. The new `maps_stage_select` shot renumbers later Henesys shots by one. The complete suite on `caches/s253`
passes **2,192 tests, 0 failed, 0 skipped** (212 files, 769.859 s), with the usual two dummy texture RID allocations
at shutdown.

#### Spec #241 (#249): integrated three-map QA smoke (2026-10-22)

Integration base `9dd41de`, Git Bash, private `t249` isolates and cache `caches/s241`. Ran seeds **1 / 2 / 2026**
on Henesys and Ellinia with bot/random, both Henesys tier-2 chains and both Sleepywood Lv38 F/P fixture policies:
24 started rounds, all commands exit 0, all records `warnings: []` / `missing: []`. No PATCH, tuning or held-out
seeds. D = DEAD; `@N` is the one-based ending map. Times are seconds; unobserved entries are absent, never zero.

| Region / policy | Death seconds @ map (seeds 1 / 2 / 2026) | Map-2 entry seconds | Lv10 / first job seconds (id) | Map-1 completed boss seconds | Compared with #246 integrated smoke |
|---|---|---|---|---|---|
| Henesys / bot | 308.3@1 / 451.8@2 / 310.0@1 | absent / 324.6 / absent | 255.4 (200) / 260.6 (200) / 258.5 (100) | none / 24.6 / none | Same outcomes, levels, kills and timings |
| Henesys / random | 435.4@2 / 383.9@2 / 413.3@2 | 344.9 / 320.8 / 323.8 | 260.7 (200) / 260.2 (200) / 256.8 (100) | 44.9 / 20.7 / 23.8 | Same |
| Ellinia / bot | 632.7@2 / 39.1@1 / 34.7@1 | 321.6 / absent / absent | 209.2 (200) / absent / absent | 21.6 / none / none | Same |
| Ellinia / random | 697.5@2 / 39.1@1 / 34.7@1 | 364.1 / absent / absent | 208.0 (200) / absent / absent | 64.1 / none / none | Same |
| Sleepywood fixture / bot | 314.7@1 / 365.9@1 / 222.3@1 | absent / absent / absent | starts Lv38, job210; no advancement | none / none / none | Same |
| Sleepywood fixture / random | 215.7@1 / 327.0@1 / 224.9@1 | absent / absent / absent | starts Lv38, job210; no advancement | none / none / none | Same |

No run enters map 3. Of the **12 distinct fresh tier-1 runs, 6 reach map 2 and 0 reach map 3** (Henesys 4/6;
Ellinia 2/6). Counting the six chain replays gives 10/18 fresh attempts reaching map 2, still 0/18 reaching map 3;
those replays are not independent observations. All chains stop in tier 1, with zero tier-2 feeds. Their first-round
metrics match the corresponding Henesys rows. No fresh clear or natural Forest of Evil/Sanctuary survival is proved.
Every observed map-2 entrant dies there; this small smoke is an owner playtesting concern, not authority to tune.
Sleepywood's six map-1 deaths also match the preceding smoke; no claim about its later-map balance follows.

Completed fights: Henesys Mano 4/6 spawned (24.6 / 44.9 / 20.7 / 23.8 s); Ellinia Stumpy 2/2 spawned
(21.6 / 64.1 s). Unfinished Mano fights are at least 8.2 / 10.0 s (bot seeds 1/2026). Ellinia map-2 King Slime
fights are unfinished at 11.1 / 33.3 s (bot/random seed 1); every other map-2 boss and every map-3 boss is
`not_spawned`. Sleepywood Zombie Mushmom has 0/3 spawned fights completed: bot seeds 1/2 are unfinished at
14.7 / 65.9 s, random seed 2 at 27.0 s; the other three are not spawned. There are no skipped bosses. No
completed-only median is used for these censored observations. Lv10 equals the listed first-job time; no fresh
run reaches a second job. Raw records, exact SYSTEMS summaries and the prior-smoke comparison stay in ignored
`evidence/spec241/t249/smoke/` in the integration worktree (`t3-f6b9fd92`).

The initial complete suite passes **2,153 tests, 0 failed, 0 skipped** (209 files, 842.748 s, exit 0): all
real-cache checks ran. Its intentional corrupt-settings recovery test prints two ConfigFile parse errors; the
two RendererDummy texture RID allocations at shutdown match the preceding full-suite baseline.

QA found a capture-only hitch exposed by Drake Area's Ice Drakes: each `mob_projectile_spawned` queued another
`mob_projectile.png`. In the uncapped seed-1 Lv38 F/P diagnostic reproduction (`--warp=370`, stop at 410 s),
506 copies were encoded; one frame wrote the same PNG 56 times in **5.564 s**, of which readback was only 7.6 ms.
Phase probes place the delay in `_capture` after drawing, outside RunScene simulation work, with no transfer or
cold asset load. Capture the first projectile once per round, like the existing first ordinary windup/hit evidence.
The seeded event-burst regression first fails (64 requests instead of one); after the fix the native reproduction
encodes one projectile PNG and has no gap over 1 s. Its largest capture is 834 ms for seven distinct startup images
after the warp. Gameplay, projectile visuals and tuning are unchanged. Probe code and raw timings remain ignored
in `evidence/spec241/t249/{perf_capture_repro,perf_capture_fixed,diagnostic-sources}/`.

Windowed playtests used x8, `--vsync=off`, 1600x1200 and the same cache. Fresh seed-2026 Henesys/Ellinia die
at 310.033 / 34.700 s on map 1; the unassisted Sleepywood Lv38 fixture seed 1 dies at 314.733 s on map 1.
Supplemental Lv38 fixture Henesys seed 1 clears naturally at 930.667 s, Lv66; the Ellinia fixture reaches map 3
but dies at 624.433 s, Lv43. Separate **invulnerable diagnostic** Ellinia/Sleepywood captures clear at
928.717 / 1583.000 s, Lv45/Lv61, using real attacks and no diagnostic lethal hits. Those clears prove presentation,
not fresh-character survival. All these summaries have `missing: []`; native logs have no unexpected engine/script
diagnostics. Screenshots were opened and checked by eye, including every intermediate CLEAR, fade, black frame,
destination name/arrival and final-map CLEAR:

- Henesys: Hunting Ground I and Mano; Pig Beach with Pigs/Ribbon Pigs and Mushmom; Blue Mushroom Forest with Blue
  Mushrooms/Horny Mushrooms and Blue Mushmom. Both arrivals are framed without old-map mobs; all three clear notices
  render. Evidence: `henesys_carried_s1_x8/`.
- Ellinia: Tree That Grew I and Stumpy; Forest of Wisdom's Slimes and King Slime; Forest of Evil I's Zombie Lupins/
  Maladies and Dyle. The unassisted fixture's map-3 death remains visible evidence of pressure; the diagnostic
  capture checks Dyle and the finale. Evidence: `ellinia_carried_s1_x8/`, `ellinia_diagnostic_s1_x8/`.
- Sleepywood: Dark Cave and Zombie Mushmom; Drake Area's Drakes/Ice Drakes/Cold Eyes and Snack Bar; Cursed
  Sanctuary's Cold Eyes/Tauromacis/Taurospears and Jr. Balrog. Destination art, foothold layers, both transitions
  and Sanctuary's final CLEAR render correctly. Evidence: `sleepywood_carried_s1_x8/`,
  `sleepywood_diagnostic_fixed_s1_x8/`; the initial partial diagnostic capture is retained separately.

`arrival-bgm-checks.json` matches all nine native entry positions to a WZ `sp` portal's x, alongside the real-cache
floor/arrival tests. Every entry reports successful BGM playback matching `info/bgm`: Henesys changes CavaBien ->
AboveTheTreetops -> RestNPeace; Ellinia correctly keeps MoonlightShadow on all three maps; Dark Cave/Drake Area
share AncientMove, then Sanctuary changes to EvilEyes. BGM checks are log evidence, not a listening assessment.
All paths in these paragraphs are below `C:/Users/itech/.t3/worktrees/maple-survivors/t3-f6b9fd92/evidence/spec241/t249/`.

The post-fix complete suite passes **2,154 tests, 0 failed, 0 skipped** (210 files, 830.101 s, exit 0), with the
same expected settings-recovery diagnostics and two dummy texture RID shutdown allocations. The focused
RunScene/transfer/capture recheck passes **66 tests, 0 failed, 0 skipped**. The three requested windowed flow drivers
pass on the new keys: `maps` verifies map-2 Quit round leaves the boundary bytes unchanged, Continue replays map 1
with seed 1/Lv1, then entries 300.000/600.017 s and the 900.050 s finale save into Free Market; `rounds` verifies
Warrior/Sword, the carried Free Market boundary, tier-2 map select, Save & quit, same-seed replay, death/results,
deletion and history; `economy` verifies drops/equip, buy/sell, both scroll outcomes and restored equipment,
inventory, scrolls and 986,331 mesos. Maps/rounds summaries have `failures: []`, `missing: []`; economy ends with
its passed/missing-empty log. Key screenshots of all three flows were checked by eye under `flow_{maps,rounds,economy}/`.

The synthetic old-key `migration/driver_save.json` check passes 13 assertions: living round, bests, run counts and
history load under canonical keys; migration is idempotent; real Continue retains seed 1 and the Lv38/job210
character and starts Henesys map 1 at 00:00. The screenshot was checked by eye. Historical fixture `_doc` provenance
is intentionally retained, so the disk-key assertion checks operational data rather than rewriting that history.

The original #246 **4,079.620 ms** minute-14 outlier remains non-reproduced. Three uncapped seed-1 Lv38 F/P
Henesys traversals match its ending exactly (930.667 s, Lv66, 4,281 kills, three bosses dead, `missing: []`).
The normal capture's max is 112.371 ms. Two further runs suppress all event/periodic PNG encoding and retain
process/draw phase markers: p95/p99/max are 10.112/16.320/69.336 ms and 10.280/17.139/75.588 ms, with
4,230/4,161 drawn 200+ mob frames. Both pass the 120-frame 100+ / 60-frame 200+ workload qualification.
Neither has a phase gap over 1 s; their largest gaps (128/130 ms) follow final.png encoding after the clear.
The historical trace covers transfers only and cannot attribute the old frame's work. Its cause is tracked in
[#252](https://github.com/itechify/maple-survivors/issues/252); the confirmed Ice Drake PNG fix is **not** proof of
that no-capture outlier's cause. No speculative runtime fix or steady-60-FPS claim is made for x8. Evidence:
`outlier-repeats.json`, `perf_no_shots_s1_x8_{1,2}/`, `diagnostic-sources/` under the same ignored QA directory.

Before handoff, merged integration review tip `e532412` as `8395b96`. Repeated all eight smoke commands on the
combined branch (`t249-smoke-merged`, cache `s241`): **all 24 complete JSON records are deeply identical** to the
pre-merge matrix above, including map entries, per-map boss timings, advancement, warnings and missing lists.
Raw records and console/SYSTEMS summaries are in `smoke-merged/`; `pre-merge-comparison.json` records the comparison.
The final merged full suite passes **2,155 tests, 0 failed, 0 skipped** (210 files, 792.948 s, exit 0), with the
same intentional corrupt-settings diagnostics and two baseline dummy texture RID shutdown allocations.
All three native flow drivers pass again under `flow_merged_{maps,rounds,economy}/`; the fresh synthetic old-key
Continue check again passes all 13 assertions under `migration-merged/`. Their key frames were checked by eye,
including the review's compact map-select rows. No tuning or speculative fix for #252 was made.

#### Spec #241 (#248): tooling and diagnostic map flow (2026-10-22)

Cache `s241`, Git Bash, separate `t248` isolates. This ticket ran only the permitted seed-1 Henesys bot record
check, not the regression smoke assigned to #249, and changed no balance data. The record has `map_times: [0]`,
`ended_map: {index: 0, id: 104040000}`, and each of the three boss fights retains its map index/id (future bosses
are `not_spawned`). No world warnings or missing setup assets. SUMMARY reports deaths by map `1:1 2:0 3:0`,
with map-2/map-3 entry times `none (n=0)` rather than invented zero observations.

| Evidence | Outcome | Map-2 entry (round s) | Map-3 entry (round s) | Ending map |
|---|---|---|---|---|
| Henesys bot, seed 1, no diagnostic aids | DEAD 308.3 s, Lv12; Mano alive | unobserved | unobserved | 1 / 104040000 |
| `flow_driver --scenario=maps`, seed 1, diagnostic replay | CLEARED 900.05 s, Lv62; three bosses dead; Free Market | 300.000 | 600.017 | 3 / 100030001 |

The flow uses invulnerability, real EXP pickups for the Warrior/Sword windows and diagnostic lethal hits only
after each map's 300 s timer. On its first Pig Beach arrival it uses the existing Quit round / Save & quit warning,
checks the boundary file is byte-identical, reloads disk and Continues on map 1 with the same seed and Lv1 boundary
character. It then plays the complete three-map sequence into one saved Free Market round. This is flow evidence,
not natural survival or a pacing calibration; natural later-map progression remains for #249.

Opened the PNGs in `evidence/spec241/t248/maps/` in the integration worktree (`t3-f6b9fd92`): the CLEAR art is
visible on every map, intermediate fades dim the old map, Pig Beach and Blue Mushroom Forest arrivals show the
correct destination title and framed avatar with no stale mobs, Continue shows Henesys at Lv1 / 00:00 / zero kills,
and the Free Market shows the carried Spearman and +525 NX. The driver drains its long warp frame before starting
clear effects so the screenshot captures their real hold. Summary has no missing assets or failed checks.

Confirmed test seams: balance records/SUMMARY through `run_one`/`aggregate`/`describe_metrics`, public camper
movement on a synthetic transferred world, RunScene summary/performance JSON producers, canonical/legacy CLI
chains and character one-offs, and the executed maps scenario. The post-#247-merge affected suite passed
118 tests, 0 failed, 0 skipped. The full suite before the #247 merge passed 2151 tests, 0 failed, 0 skipped
(207 files, 906 s); the affected suite above rechecked the merged code. The full process exited 0 but Godot
reported two RendererDummy texture RID allocations leaked at exit; their source was not investigated here.

#### Spec #241 review fixes: transfer state and regression smoke (2026-10-22)

Cache `s241`, explicit Git Bash, `trev*` isolates; seeds 1 / 2 / 2026, unforced jobs, no PATCH or balance edits.
All 12 tier-1 bot/random runs have `warnings: []` and `missing: []`. Death times and ending maps match the #246
integrated smoke below to the recorded 0.1 s precision. Henesys still reaches the Lv10 jobs and Mano; Ellinia's
early seed-2/2026 deaths remain recorded for the owner, with no tuning.

| Region / policy | Death seconds (seeds 1 / 2 / 2026) | Ending map number |
|---|---|---|
| Henesys / bot | 308.3 / 451.8 / 310.0 | 1 / 2 / 1 |
| Henesys / random | 435.4 / 383.9 / 413.3 | 2 / 2 / 2 |
| Ellinia / bot | 632.7 / 39.1 / 34.7 | 2 / 1 / 1 |
| Ellinia / random | 697.5 / 39.1 / 34.7 | 2 / 1 / 1 |

The transfer/metrics baseline passed 40 tests; the refactor checks passed 72 (both 0 failed / 0 skipped).
A new fixed-tick transfer test first reproduced a grenade landing and damaging a new map's mob, then passed with
the queued flight cleared and cooldowns retained (40 transfer/Gunslinger tests, 0 failed / 0 skipped).
Audited Final Attack queues, basic windups, summons, mob attacks/projectiles, delayed boss heals/statuses, pet fetch
targets and bot routes: their existing transfer resets already discard map-space state; player poison mists and
persistent damage zones are not implemented. A seeded three-map event/state replay has identical byte hashes
before/after the refactors (`9dd41de` versus the review branch, two runs each).

Removed all interim missing-asset exemptions. Against incomplete `s237`, balance/profile/character tools now exit 1
and name missing later-map imgs; an existing real-cache assertion fails on those paths. Against `s241`, each region's
setup, profiler and character fixture run cleanly. The diagnostic maps scenario again PASSED with no missing assets
or failed checks, replaying map 1 after quitting map 2 and then clearing into the Free Market.
Opened all three compact map-select cards under `evidence/spec241/review/cards/` in the integration worktree:
every map/boss name fits, row groups are close together, and no text overlaps. These are diagnostic UI/flow checks.
The full `ISOLATE=trev` suite passed 2,154 tests, 0 failed / 0 skipped (209 files, 803.465 s, timeout 3000 s).
It still reports two RendererDummy texture RID allocations leaked at exit, as #248 did; their source remains
uninvestigated. The corrupt-settings parse diagnostics are intentional safety-test fixtures.

#### Spec #241 (#246): integrated presentation smoke (2026-10-21)

After merging `e49f66a` (#243) as `0aca215`, repeated the same 24 seed/configuration invocations with `caches/s241`.
All 24 started rounds have `warnings: []`, `missing: []`; all eight commands exit zero with no crash or engine/script warning.
No balance data, PATCH or held-out seeds. D = dead; columns are seeds 1 / 2 / 2026; ending maps follow the completed
boss records (headless transfer is immediate):

| Region / policy | Death seconds | Ending map number |
|---|---|---|
| Henesys / bot | 308.3 / 451.8 / 310.0 | 1 / 2 / 1 |
| Henesys / random | 435.4 / 383.9 / 413.3 | 2 / 2 / 2 |
| Ellinia / bot | 632.7 / 39.1 / 34.7 | 2 / 1 / 1 |
| Ellinia / random | 697.5 / 39.1 / 34.7 | 2 / 1 / 1 |

All six chains stop in tier 1 (zero tier-2 feeds). The Lv38 F/P fixture in Sleepywood dies on map 1 at
314.7 / 365.9 / 222.3 s (bot) and 215.7 / 327.0 / 224.9 s (random), with no boss killed. These schema/opening/pool
changes differ from the legacy baseline below; Henesys bot seed 1 exactly matches #243's integrated alias smoke.
Fresh starts have no clears in this small sample; record for the owner's #249 playtests, without tuning.
Raw records and console/SYSTEMS summaries remain ignored in `_scratch/t246-smoke-integrated/`.

Integrated validation: full suite **2,147 tests, 0 failed, 0 skipped** (207 files, 864 s), Git Bash,
`ISOLATE=t246`, `TEST_TIMEOUT_S=3000`, cache `s241`; scene/schema/transfer/clock checks pass **74 tests, 0 failed,
0 skipped**. The two dummy-renderer texture RID shutdown warnings match #243's baseline; focused transfer tests
and native captures remain clean. The requested fresh-character
windowed Henesys seed-2026 x8 run dies on map 1 at 310.033 s. A supplemental seed-1 x8 run with the existing Lv38
F/P fixture clears all three real maps at 930.667 s, Lv66, all three bosses dead, `missing: []`, without invulnerability
or diagnostic hits. Both clear/fade/black/arrival sequences and the final CLEAR were checked by eye under
`evidence/spec241/t246/carried_s1_x8/` in the integration checkout: original CLEAR art, destination art/names, correctly
framed avatar and native destination mobs, no old-map mobs on arrival. The ending summary names map 100030001,
The Blue Mushroom Forest, Hidden Street, region Henesys.

Uncapped transfer evidence uses the same fixture/seed at x1 with `--warp=290 --minutes=5.2` and
`--warp=590 --minutes=10.3`, plus an x8 full traversal. An ignored performance mirror buffers per-frame phase/time/
work samples to `transfer_frames.json` at the end and suppresses event screenshot encoding (final.png remains).
The two x1 fade-ins have 274 / 200 samples: p95 1.596 / 2.173 ms, p99 1.900 / 2.591 ms, max 49.920 / 67.251 ms,
exactly one interval above 16.7 ms in each fade-in. There are additional isolated notice/arrival outliers:
26.383 ms during map 1's notice, 43.682 ms during map 2's notice, and 33.840 ms 1.53 sim seconds after map 3 entry.
Thus one main reload hitch per boundary is observed, but a strict no-other-spike claim for the entire sequence is
not verified. Raw frames, configuration and final captures remain under `evidence/spec241/t246/perf_buffered_transfer{1,2}_x1/`.
The uncapped x8 traversal matches the captured run's ending time/level/kills/bosses; its whole-run p95/p99 is
13.602 / 27.390 ms, with an unexplained 4,079.620 ms outlier in minute 14, outside the transfer windows.
No overall steady-60-FPS claim is made at x8; a full headless suite was active on this shared machine.

#### Spec #241 (#246): presentation regression before the stage schema (2026-10-21)

Presentation `2b54d5c` on integration `9ba2025`, cache `caches/s241`, private `ISOLATE=t246_*` mirrors.
`balance.sh 1 2 2026` ran both legacy tier-1 stages and bot/random (12 runs), both Henesys tier-2 chains (6 chains),
and both Dark Cave fixture policies (6 runs, `fp_arch_mage.json`). No tuning, PATCH or held-out seeds.
All 26 started rounds have `warnings: []`, `missing: []`; all eight commands exited zero, with no crash or engine/script warning.
Tier-1 outcomes and end times match the preceding #237 smoke exactly. C/D = cleared/dead; columns are seeds 1 / 2 / 2026:

| Legacy stage / policy | Outcome and end seconds | Ending levels |
|---|---|---|
| Henesys / bot | C 936.8 / D 309.4 / D 306.5 | 49 / 11 / 11 |
| Henesys / random | D 917.4 / D 423.4 / C 951.3 | 44 / 19 / 51 |
| Tree / bot | D 491.1 / D 39.1 / D 34.7 | 22 / 1 / 1 |
| Tree / random | D 443.5 / D 39.1 / D 34.7 | 19 / 1 / 1 |

One chain per policy feeds tier 2: bot seed 1 (derived seed 2260174940) dies at 620.4 s, random seed 2026
(1823073557) at 616.8 s; both Lv67 with one boss killed. The other four chains stop in tier 1.
The Dark Cave fixture dies at 316.0 / 337.1 / 222.3 s (bot) and 215.7 / 326.7 / 224.9 s (random), all before a boss kill;
these are recorded without tuning. Raw records and console/SYSTEMS summaries remain ignored in `_scratch/t246-smoke-legacy/`.
This smoke predates #243: the real stage data still has no `maps`, so it proves no three-map pacing or balance.
The cache-backed RunScene tests use an explicit adapted three-map setup instead; synthetic windowed captures of
both transfers were checked by eye in `evidence/spec241/t246/synthetic/` in the integration checkout.
Validation before #243: full suite **2,140 passed, 0 failed, 0 skipped**; focused RunScene/transfer/clock suite
**68 passed, 0 failed, 0 skipped**. The full runner logs two dummy-texture RID allocations at shutdown; focused
transfer and asset/UI/render/font checks and native transfer captures do not reproduce that diagnostic.

#### Spec #241 (#243): schema and legacy-key smoke (2026-10-21)

The isolated #243 runtime played the first map with all three bosses at absolute 300/600/900 seconds;
map transfer and pool selection are supplied separately by #244/#245. The owner's three Henesys opening keyframes are the only
balance edits. Requested alias check: `bash scripts/balance.sh 1 --stage=henesys_hg1`, Git Bash,
`ISOLATE=t243-alias`, cache `C:/Users/itech/Coding/maple-survivors-refs/caches/s237`, base `1808305`.
The record uses canonical `stage: henesys`, with `warnings: []` and `missing: []`; no crash or script error.

| Stage / policy / seed | End | First job | Boss reached |
|---|---|---|---|
| Henesys / bot / 1 | DEAD 307.9 s, Lv12, 253 kills | Magician 255.4 s | Mano 300 s, alive at death |

Compared with #237's seed-1 bot clear at 936.8 s and Magician at 279.8 s, the opening changes the seeded choices
and this outcome. This single alias smoke is not a population balance assessment; the full spec regression matrix
belongs to #249. No tuning candidates or held-out seeds were used. The six new map imgs and Cold Eye are absent
from `s237`: setup keeps aligned `{}` map entries plus missing paths, and affected cache checks tolerate later-map
assets or explicitly SKIP. Those skips do not verify the new maps. Raw alias output stays in ignored `_scratch/`.

Regression tests retain the existing historical event digest by freezing its pre-#241 opening; this requires the
schema/key migration to preserve every other event byte. Live pacing guards account for the approved density:
Lv8 and Lv30 sample lower bounds use the existing individual floors (180 s / 480 s), with their upper bounds
unchanged; tier-1 ending level stays below third-job level 70 instead of the pre-#241 guard below 50. These are
test expectations, not balance-data edits or a tuning pass. Historical fixture `_doc.stage` provenance remains
unchanged and resolves through the alias API when tests compare its region.

Isolated #243 validation: **2,114 tests, 0 failed, 2 skipped** (2,112 passed), Git Bash with `ISOLATE=t243`,
the `s237` cache and `TEST_TIMEOUT_S=3000`. The pre-#241 event golden matches unchanged. Missing later-map
preloads produce expected warnings; Godot's dummy renderer also reports two texture RID allocations at shutdown.
The repeated alias smoke reproduces its complete record byte for byte.

Integration snapshot `fa5beac` adds #242/#245. Its focused run covered 196 tests (eight new-asset SKIPs); its one
failure was the inherited whole-round pressure guard applied to #245's retained map-1 pool. The historical
whole-round pacing oracle now supplies its original full-curve director and remains single-map, preserving those
pressure assertions; its recheck passes **4/4**. Map-local pool behavior is tested separately by #245. The merged
old-key smoke exits successfully: canonical `henesys`, DEAD 308.3 s, Lv12, 255 kills, `warnings: []`, `missing: []`.

The subsequently fetched `9ba2025` integration tip includes #244. Merge validation passes **102 tests, 0 failed,
9 skipped** (93 passed): schema, DataRepo/StagePools, saves, synthetic map transfers, boss lifecycle and spawning.
The nine SKIPs cover missing new-map art/mobs, real-cache transfers and six map pools in `s237`; they verify none
of those assets. The full 2,114-test run above predates these integration merges; after merging, the affected
checks were rerun. SpawnDirector and StagePools implementation matches the incoming integration tip unchanged.

Fix-up validation on the integrated `fa99ded` runtime uses Git Bash, `ISOLATE=t243b` and cache `s241`.
The five reported RunScene failures reproduce in 48 tests (5 failed, 0 skipped). All were obsolete fixture
assumptions: the roster expectation omitted map-life pools (Ribbon Pig 1210101, Dark Axe Stump 2110200 and Blue
Mushroom 2220100 account for 15 versus 18); the four injected boss schedules lacked map indices and were therefore
not armed by the region director. The roster check now supplies every loaded map and the canonical summon/revive
inputs, and checks each id's cache image, preload and sim kind. The HP-bar, simultaneous-icon/colour, King Slime
split and bonus-before-finale tests explicitly retain a legacy single-map schedule, preserving all original
assertions. Intermediate-map settlement and final-map-only clears remain covered by `test_map_transfer.gd`.
The RunScene recheck passes **48 tests, 0 failed, 0 skipped**; no runtime or balance data changed.
The full recheck passes **2,146 tests, 0 failed, 0 skipped** (207 files, 1,057 s, exit 0;
`TEST_TIMEOUT_S=3000`), including real-cache traversal through all three maps of each region. The pre-existing
two dummy-renderer texture RID shutdown warnings remain. The final fetch still finds integration at `9ba2025`,
already included; no further merge is needed.

The requested alias smoke (`balance.sh 1 --stage=henesys_hg1`, `ISOLATE=t243b-balance`, cache `s241`) exits 0,
records canonical `henesys`, and has `warnings: []` / `missing: []` with no crash or script error.

| Stage / policy / seed | End | Map progression |
|---|---|---|
| Henesys / bot / 1 | DEAD 308.3 s, Lv12, 255 kills | Mano arrived at 300 s and remained alive; maps 2/3 not entered |

This reproduces the previous integrated alias smoke. Living beyond 5:00 alone does not transfer: the map boss
must die and its rewards must finish. This natural seed therefore does not verify later-map traversal; the
real-cache transfer test covers that path. The full regression matrix remains #249's scope; no tuning was done.

#### Spec #237 (#240): potion cooldowns: regression smoke (2026-10-21)

Feature smoke only: `bash scripts/balance.sh 1 2 2026 --stage=<key> --policy=<policy>` for `henesys_hg1` and
`tree_that_grew_1`, `bot` and `random` (12 runs), harness `f924b1e` on sim base `521c0ef`. Every Godot command
used `ISOLATE=t240` and `MAPLE_SURVIVORS_CACHE=C:/Users/itech/Coding/maple-survivors-refs/caches/s237`.
No PATCH, balance-data edits, tuning candidates or held-out seeds. All records have `warnings: []` and `missing: []`;
logs contain no crash, script error or engine warning. C = CLEARED, D = DEAD; values are seeds **1 / 2 / 2026**,
times in seconds, drinks as **(HP, MP)** per run:

| Stage / policy | Outcome and end seconds | First job seconds (id) | Potions used (HP, MP) |
|---|---|---|---|
| Henesys / bot | C 936.8 / D 309.4 / D 306.5 | 279.8 (200) / 277.2 (200) / 266.6 (100) | (17, 78) / (1, 18) / (1, 18) |
| Henesys / random | D 917.4 / D 423.4 / C 951.3 | 267.1 (200) / 278.8 (200) / 278.8 (100) | (22, 73) / (1, 28) / (31, 78) |
| Tree / bot | D 491.1 / D 39.1 / D 34.7 | 209.2 (200) / — / — | (5, 42) / (1, 0) / (1, 0) |
| Tree / random | D 443.5 / D 39.1 / D 34.7 | 208.0 (200) / — / — | (5, 37) / (1, 0) / (1, 0) |

Lv10 times equal the listed first-job times except Henesys random seed 1: Lv10 at 267.0, Magician at 267.1.
Second jobs: Henesys bot seed 1 becomes F/P (210) at 595.8; random seed 1 becomes F/P at 581.0 and seed 2026
becomes Page (120) at 562.8. Every Henesys run reaches Mano; both Tree seed-1 runs kill Stumpy. Neither stop
condition is met: there are both deaths and clears, and first bosses are reached and killed.

Compared with the preceding audit smoke (`66a798e`, below), Henesys bot retains 1/3 clears, with seed 1 clearing
at 15:36 (Lv49) instead of 15:58 (Lv50); seeds 2/2026 now survive to 5:09/5:06 instead of 4:34/4:19.
Henesys random changes from 0/3 to 1/3 clears (seed 2026); its seed-1/2 deaths move from 9:16/10:02 to 15:17/7:03.
Tree remains 0/3 clears for each policy: bot deaths change from 9:04/16:10/0:48 to 8:11/0:39/0:34, random from
9:29/2:56/0:48 to 7:23/0:39/0:34. These seeded shifts are expected from #237's changed potion availability and
two-item boss rewards; they are recorded without tuning or a population-balance claim. Raw records and console/
SYSTEMS summaries remain ignored under `_scratch/t240/smoke/`.

Validation: **2,104 tests, 0 failed, 0 skipped** in the full suite; focused `balance_metrics`: **23, 0, 0**.
The requested default-seed Henesys playtest used an 8-minute cap and died naturally at 306.517 s after Mano's
arrival (`missing: []`). Occlusion prevented the first launch's screenshots. Always-on-top/window-position flags
and a capture retry with `--warp=290` produced Mano arrival, combat and death frames; the natural and warped runs
match on state, job, kills, potion uses, end time and maximum crowd. A supplemental seed-1 capture with the same
warp reached the 8-minute cap, Lv23, with Mano dead and `missing: []`. Opening/2-minute, boss/death and post-boss
6-minute screenshots were checked by eye: avatar/map layering, monsters, spells, notices, boss bar, tombstone and
potion icons render correctly, with no potion quantities. Evidence stays ignored under `evidence/t240/`;
render-window flags and the diagnostic warp change no gameplay data. This does not assess #239's pending sweep UI.

#### Audit follow-up (MS-04..MS-42): regression smoke (2026-10-21)

Feature smoke only, no tuning or data changes: `bash scripts/balance.sh 1 2 2026` on both tier-1 stages and both
`bot` / `random` policies (12 runs), integrated branch `66a798e`, private read-only cache imported from the current
manifest. Baseline: the same command on `a68e74f` during the audit (`docs/audits/maple-survivors-skill-audit.md`
4.2). All 12 runs: `warnings: []`, `missing: []`, no crash or script error. Death times, levels at death and boss
counts are **identical** to the baseline on every seed. The one difference is the intended MS-08 clear sweep: Henesys
bot seed 1 still CLEARS at 15:58, but ends at **Lv50 instead of Lv44**, because the remaining EXP drops on the map are
now collected at the clear and their level-ups are resolved before the carry. MS-05/MS-32 (MP growth) and MS-07 did
not move any seeded outcome here. D = death time, final level (seeds 1 / 2 / 2026):

| Stage / policy | Baseline `a68e74f` | After `66a798e` |
|---|---|---|
| Henesys / bot | CLEARED 15:58 Lv44 / D 4:34 Lv8 / D 4:19 Lv7 | CLEARED 15:58 **Lv50** / D 4:34 Lv8 / D 4:19 Lv7 |
| Henesys / random | D 9:16 Lv27 / D 10:02 Lv25 / D 4:56 Lv9 | the same |
| Tree / bot | D 9:04 Lv21 / D 16:10 Lv29 / D 0:48 Lv1 | the same |
| Tree / random | D 9:29 Lv18 / D 2:56 Lv6 / D 0:48 Lv1 | the same |

#### Spec #226 weapon specialization: regression smoke (#232, 2026-10-18)

`bash scripts/balance.sh 1 2 2026` on both tier-1 stages and both `bot` / `random` policies, plus one seed-1 Henesys
bot run per new `--job` family flag (11): **23 runs, all DEAD as before**, with no crashes, world warnings, missing
assets or skipped bosses. Private read-only cache, no PATCH, tuning or held-out seeds. Unforced rows match #204's smoke;
the forced runs reach Lv11 and Mano and die at 331-342 s (they prove startup acceptance, not second-job attainment).
Seeds 1 / 2 / 2026:

| Stage / policy | Death seconds | Final levels | First jobs |
|---|---|---|---|
| Henesys / bot | 339.6 / 455.4 / 323.4 | 11 / 13 / 11 | 200 / 200 / 100 |
| Henesys / random | 450.6 / 325.4 / 316.3 | 19 / 11 / 12 | 200 / 200 / 100 |
| Tree / bot and random | 128.9 / 63.6 / 51.5 | 3 / 2 / 2 | none |

**Seeded records intentionally change** where a multi-family advancement draws a family on job stream 8 (a forced
single-family branch without a path takes its own family and draws nothing); the 72,000-tick seed-1 synthetic event
golden was `b4b22cfe...` after #230 and is `bd2a2328...` after merging main (#225, playtest-3), re-captured once
more. Historical character fixtures stay valid saves (migration; rationale in
`game/tests/fixtures/characters/README.md`).

**Scenario QA: 14/14 passed** (`warrior`, `warrior2 --job=110/120/130`, `bowman --branch=310/320`,
`thief --path=claw/dagger`, `pirate --path=knuckle/gun`, `full`, `rounds`, `account`, `economy`), screenshots checked by
eye under `evidence/s226/t232/`. `rounds`, `account` and `economy` use **diagnostic staging** (invulnerability and
diagnostic boss hits after the stage timer, through the real boss death and reward choices) because their old natural
staging already fails on `main` (d1cdb16): `rounds` seed 4 dies at about 200 s (Lv6) before a first job, and the Lv38
F/P `economy` fixture dies in its warp. That baseline was re-run for this review. This is flow QA, not natural clears or
balance evidence. Cargo: 46 synthetic tests run; the 18 real-WZ tests return early without `MAPLE_WZ_ROOT` (no real-WZ
validation).

#### Spec #225 (#228): no job-neutral cards, automatic potion tiers: regression smoke (2026-10-18)

Feature smoke only, no tuning (AGENTS.md): `bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1>
--policy=<bot|random>` (4 invocations, 12 runs), default job pick, before = `8e417fb` (the spec integration branch, which
is main `d1cdb16` plus a research doc) in a detached worktree, after = this branch, both with the read-only cache
`caches/s167-main` and the same `BALANCE_OUT` layout. **Seeded records change by design**: Magnet and the three
potion-tier cards are no longer offered, so every level-up draw, and everything after it, differs (events gain
`potion_tier_up` at Lv 10 / 20 / 25). All 12 runs ended DEAD, with `warnings: []` and `missing: []` and no crash or
script error; no run was cleared before or after. The latest earlier smoke (#215's default-pick row, Henesys bot D 8:15
Lv24 / 5:32 Lv12 / 5:14 Lv11) predates the Bowman merge into main, so its stream-8 job draws differ (that smoke drew
Gun Pirate / Warrior / Dagger Thief; the `8e417fb` baseline draws Bowman / Crossbowman / Gun Pirate), hence the fresh
baseline here. D = death time, then final level (seeds 1 / 2 / 2026):

| Stage, policy | before | after |
|---|---|---|
| Henesys bot | D 5:39 Lv11 / 10:19 Lv32 / 5:13 Lv11 | D 5:36 Lv11 / 6:42 Lv14 / 5:05 Lv10 |
| Henesys random | D 7:20 Lv19 / 5:29 Lv10 / 5:05 Lv11 | D 7:42 Lv23 / 5:58 Lv13 / 5:06 Lv12 |
| Tree bot, random | D 2:08 / 1:03 / 0:51, Lv3 / Lv2 / Lv2 | the same (seeds 1 and 2026 byte-identical; seed 2's record differs, outcome the same) |

The Henesys rounds still reach the first job (Lv 10 at 4:25-4:34 before, 4:26-4:42 after) and meet Mano at 5:00, with no
clear before or after; the Tree stays record-only. The one large move, bot seed 2 (a Crossbowman reaching Lv 32 before, a
Lv14 Bowman after), comes from different cards in the same seeded draw (n = 3 per cell); it is a record, not a finding.
Raw records: ignored `_scratch/smoke_base/` and `_scratch/smoke_after/`.

**Goldens recaptured by this ticket** (the draws changed, nothing else): `test_character_baseline` (`GOLDEN`, 20-minute
bot event bytes, seed 1) and `test_tick_cost_identity` (`GOLDEN` and `TOTALS`, seed 146: exp 5133 -> 4196, kills 276 ->
208, casts 249 -> 183, level 14 -> 13).

#### Spec #225 (#229): researched potion steps: regression smoke (2026-10-18)

Feature smoke only, no tuning (AGENTS.md): `bash scripts/balance.sh 1 2 2026 --tier=2 --policy=<bot|random>` (default
job pick, 6 chains), private cache `s225-t229` (imported with the new manifest). **No chain reached tier 2**: every
tier-1 Henesys round ended DEAD (4:41-7:45, Lv 9-19), so no tier-2 run started and **no run reached Lv 40 or Lv 60**; the chain smoke
alone cannot show the new steps fire. All six: `warnings: []`, `missing: []`, no crash. D = death time, final level
(seeds 1 / 2 / 2026), against the #228 smoke above:

| Policy | #228 smoke (Henesys) | #229 chain (tier-1 round) |
|---|---|---|
| bot | D 5:36 Lv11 / 6:42 Lv14 / 5:05 Lv10 | D 5:21 Lv11 / 4:41 Lv9 / 5:05 Lv10 |
| random | D 7:42 Lv23 / 5:58 Lv13 / 5:06 Lv12 | D 7:45 Lv19 / 5:50 Lv11 / 5:06 Lv12 |

The records differ a little from #228 (bot seeds 1 and 2, random seeds 1 and 2) because the bot waste guard now caps
the restore at the pool (it only changes a drink when a potion restores more than the pool holds); the new steps start
at Lv 40 and cannot touch these rounds, and a plain `--stage=henesys_hg1 --policy=bot` run gives the same records as the
chain's tier-1 round. n = 3 per cell, a record not a finding. Goldens recaptured by this ticket: `test_character_baseline`
`GOLDEN` only (with `potions.bot.pool_floor` 1.0, the old guard, the #228 hash is reproduced exactly). To show the steps fire, the committed Lv 38
Magician fixture (`fp_arch_mage.json`) was copied to ignored `_scratch/` files with `level` 39 and `exp` just below
the next level (a diagnostic copy, Red/Blue potions held, 30 of each) and run on `--stage=dark_cave --policy=bot --cap=600`
(seeds 1 and 2): both TIMED OUT at 10:00 at Lv 72 / 70 with no warnings and nothing missing; the character is Lv 60
within the first minute (Dark Cave pays a lot of EXP), so Unagi / Pure Water (Lv 40) and Ice Cream Pop / Red Bean
Sundae (Lv 60) were all applied in turn, and the bot drank Red Bean Sundae (MP, seed 1 first at 0:20) and Ice Cream Pop
(HP, seed 1 at 5:13, Lv 63). A playtest of the same copy (`evidence/spec225/t229/lv39_unagi/`) shows the four notices
("Your White Potions are now Unagis." ... "Your Pure Waters are now Red Bean Sundaes.") and the quick slots with the
new icons. A second copy at Lv 59 ended at Lv 101-ish (Dark Cave EXP is huge) and drank Red Bean Sundae; it is not evidence of pacing.

#### Spec #225 merged with playtest-3 (#235): `test_full_run` guard relaxed (2026-10-19)

Merging main (#223's knockback guard, #222's auto-equip) into spec #225 moved `test_full_run`'s Henesys seeds 2 and
2026 to Beginner deaths at 4:34 / 4:19 (Lv 8 / Lv 7), a few seconds before Lv 10, so the guard "Lv 8, Lv 10 and
Magician on 2/3 predetermined runs" failed (each side alone passed it). Diagnosis on training seeds only,
`balance.sh 1..24 --policy=bot --job=200 --cap=420`, same cache: main `0e8b216` vs the merge `8047007` both reach Lv 10
21/24 (median 4:33 / 4:35) and Magician at 267-300 s / 266-290 s; deaths before 7:00 are 4 / 8 (mostly after Lv 10, at
Mano) and potions collected HP 354 / 304, MP 464 / 414 (no Magnet card). Early pacing is unchanged; the failure is a
reshuffle. The owner relaxed the guard until the balance pass (#77): Lv 8 on 2/3, Lv 10 / Magician on 1/3.

#### #223 knockback guard regression smoke (2026-10-18)

`bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, default job pick, read-only
cache `s167-main` (complete through spec #167, tier-1 data), no PATCH or tuning, 12 runs per side. "Before" is main
`d1cdb16` run from a clean worktree on the same cache; "now" adds the knockback guard (section 6, tier C owner). All 24 runs
ended DEAD with `warnings: []` and `missing: []`; no crash or script error, no clear. The records are not byte-identical to
main, as the issue expects: a player pushed less often takes another path, so from the first guarded hit every later field
moves (`time`, `kills`, `spawned`, `mesos_*`, `exp_collected`, `boss_hits`, ...; `hits_by_min`, `cards`, `level_*` and
`job_times` when the run lasts longer or shorter). The `hit_window` fields themselves are untouched. D = death time, then final
level; the previous smoke's Tree row (D 2:09 / 1:04 / 0:52) matches the "before" column.

| Stage, policy | Seeds 1 / 2 / 2026 before | Seeds 1 / 2 / 2026 now |
|---|---|---|
| Henesys, bot | D 5:40 Lv11 / 10:19 Lv32 / 5:14 Lv11 | D 5:43 Lv11 / 6:24 Lv12 / 5:08 Lv11 |
| Henesys, random | D 7:20 Lv19 / 5:30 Lv10 / 5:05 Lv11 | D 5:53 Lv12 / 5:36 Lv11 / 4:50 Lv9 |
| Tree, bot | D 2:09 Lv3 / 1:04 Lv2 / 0:52 Lv2 | D 9:53 Lv23 / 1:34 Lv3 / 0:48 Lv1 |
| Tree, random | D 2:09 Lv3 / 1:04 Lv2 / 0:52 Lv2 | D 5:36 Lv13 / 1:34 Lv2 / 0:48 Lv1 |

Henesys still reaches its first job at the same time in every run that had one (265.7-274.0 s; random seed 2026 now dies
at 4:50 before advancing) and five of six runs still take Mano hits (random seed 2026 dies first; before: five of six too, random seed 1 had none). No Henesys run reaches the second boss now (before: bot seed 2 died at 10:19 after Mushmom spawned). Henesys bot seed 2 no longer reaches the
second job (before: Crossbowman at 577.7 s, Lv32); that run, and Tree bot / random seed 1 (now past the first job at
203.6 s / 215.0 s), are single-seed outcomes of a different position history, not a measured effect of the guard (n=3 per
cell). Tree stays record-only. No smoke exists for main `d1cdb16` itself (the #215 rows above ran on integration `628223f` with cache `s167-int`), so the "before" column is a fresh baseline: Tree matches #215, Henesys differs from it for that reason, not because of the guard. Raw records: ignored `_scratch/p3-223/{base,new}` (outside the repo).

#### #222 auto-equip on pickup: regression smoke (2026-10-18)

`bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>` (12 runs) on
`t3/playtest3-222` against the same 12 runs on its base `main` (`d1cdb16`), same private cache
(`caches/p3-main`, the current manifest), no PATCH, no tuning, no held-out seeds. No crash, script error, world warning or
missing asset; every run dies, as in the previous smoke (#204, 2026-10-18, below). **All 12 records are byte-identical to
main's** (outcome, times, hits, levels, drops, `equipment_worn`): the bot already wore an eligible drop on the tick it was
picked up (`BotShop.equip_after` runs right after each step), so the sim now doing it first changes nothing the bots can
see. The only difference the rule can show is the bookkeeping: `equips_worn` ("put on mid-round") now also counts the
sim's `auto_equip` events (`balance_run.gd`), so the metric keeps its meaning; without that, bot seed 2 read 3 instead of
4 and random seed 1 read 0 instead of 1 (the wears moved from the bot to the sim). A record changes where a drop is worn
earlier than the bot would have worn it (a drop picked up with a free slot that the bot scores at 0 or defers); none of
these seeds has one. Death seconds (final level), seeds 1 / 2 / 2026:

| Stage, policy | this branch = main control | #204 default-pick row (earlier revision) |
|---|---|---|
| Henesys, bot | 339.5 / 619.3 / 313.8 (11 / 32 / 11) | 339.6 / 455.4 / 323.4 (11 / 13 / 11) |
| Henesys, random | 440.0 / 329.5 / 305.0 (19 / 10 / 11) | 450.6 / 325.4 / 316.3 (19 / 11 / 12) |
| Tree, bot and random | 128.9 / 63.6 / 51.5 (3 / 2 / 2) | 128.9 / 63.6 / 51.5 (3 / 2 / 2) |

The Henesys rows differ from #204's by the unforced job pick, which reshuffled when Thief joined main (#204 notes the
same; its forced-`320` bot row reads 339.5 / 619.3 / 360.0, matching seeds 1 and 2 here). Tree is unchanged and record-only.
Bot equipment per run (seeds 1 / 2 / 2026): dropped 0 / 5 / 1, picked up 0 / 4 / 1, put on 0 / 4 / 1.

#### Spec #166 Bowman (#199-#203): QA regression smoke and fixtures (#204, 2026-10-18)

`bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, unforced and
with `--job=300`, `310`, `320`: **48 runs**, integration `730467c` plus QA-only changes, private cache `s166-int`,
no PATCH, balance edits or held-out seeds. Another **21 Henesys controls** force `100`, `510`, `520` under both
policies and `210` under bot. All 69 runs die, with no crashes, script errors, world warnings, missing assets or
skipped bosses. Raw seed records, exact console/SYSTEMS output and aggregates remain ignored in
`_scratch/t204-smoke/<job>/<stage>/<policy>/`; `_scratch/t204-audit.json` preserves the configuration/outcome audit.
Death seconds and final levels below are in seed order **1 / 2 / 2026**; no timeout or clear is implied.

| Stage / forced job | bot: death seconds (final levels) | random: death seconds (final levels) |
|---|---|---|
| Henesys, default pick | 339.6 / 455.4 / 323.4 (11 / 13 / 11) | 450.6 / 325.4 / 316.3 (19 / 11 / 12) |
| Henesys, `300` or `310` | 339.5 / 610.0 / 360.0 (11 / 32 / 13) | 440.0 / 329.5 / 342.8 (19 / 10 / 12) |
| Henesys, `320` | 339.5 / 619.3 / 360.0 (11 / 32 / 13) | 440.0 / 329.5 / 342.8 (19 / 10 / 12) |
| Tree, every job choice above | 128.9 / 63.6 / 51.5 (3 / 2 / 2) | same |

The unforced picks reshuffled (Magician / Magician / Warrior), so historical comparisons use forced controls:
Warrior `100` matches #185's `110/120/130`, Pirates `510/520` match #195, and Magician `210` bot matches the
spec #151 forced record, all to the earlier tables' whole-second precision. The forced `210` controls reach Magician
and spawn Mano in 3/3; Tree remains unchanged and record-only, dying before any job. Bowman advances at
265.7-274.0 s in all six runs per forced configuration. Mano dies in 2/6 (bot seed 2, random seed 1); only bot
seed 2 reaches second job, at 577.7 s (Hunter for `300/310`, Crossbowman for `320`). It dies shortly after Mushmom
spawns. MP-short totals are 104.617 / 118.100 / 136.950 s (bot), 117.850 / 86.717 / 96.367 s (random), identical
across the three forced configurations. These deaths resemble the existing physical-line bot weakness, without
the before-first-boss failure pattern or any code error that would justify stopping for a bug. No tuning followed.

The two committed fixtures, `hunter_2nd.json` (Lv30) and `crossbowman_2nd.json` (Lv31), reproduce byte for byte with
`tools/character_fixture.gd --job=<310|320> --seed=1 --god --seconds=600 --label=spec166/ticket-204
--revision=730467c36fb3312637733d722a009aa1512d8998 --out=<abs JSON>` on that revision and cache. These are real
headless Henesys bot rounds, capped alive with invulnerability, natural EXP and no EXP multiplier; every aid and
provenance field is in `_doc`. `test_bowman_fixtures` checks loading, branch skills, weapon family, restoration of
ranks and Bronze arrows, and 600 fixed ticks on the real map without warnings.

`flow_driver --scenario=bowman --branch=310|320` passes both branches: real Lv10/Lv30 windows, bow worn and spare
crossbow in Equip, crossbow worn by input at Lv12, branch advancement weapon, Bronze notice, Save & quit/Continue
with identical job, level, path, equipment, skills and cards plus the same derived arrow tier. Its invulnerability,
EXP-drop climb and Free Market boundary shortcut are diagnostic, not survival evidence. It holds the branch's
family before advancement because #155 intentionally keeps family swaps silent. Fresh passing evidence is in
`C:/Users/itech/.t3/worktrees/maple-survivors/t3-3420113e/evidence/s166/t204/flow-310-verified/` and `flow-320-retry/`.
The same root's `bowman/`, `hunter/` and `crossbowman/` shots were checked by eye: both first-job weapon poses,
Power Knock-Back's swing and displacement, Arrow Bomb's blast then three visibly stunned mobs, Iron Arrow piercing
six of seven lined-up targets, and Bronze/Steel upgrade notices (Steel arrow visible in flight). All driver
missing-asset lists are empty. GLOSSARY's Knock-back entry agrees with the shipped chance-based push and boss immunity;
7.21-7.24 now describe the merged consumers rather than pending tickets. No golden was re-captured.

Final full Godot suite: **2,030 passed / 0 failed / 0 skipped**, 172 files, 659927 ms, exit 0, with
`MAPLE_SURVIVORS_CACHE=C:/Users/itech/Coding/maple-survivors-refs/caches/s166-int ISOLATE=s166-t204
TEST_TIMEOUT_S=3000`; integration was fetched/merged before validation and remained at `730467c`.
The same two previously recorded RendererDummy texture RID shutdown leaks remain. Rust: **64 passed / 0 failed /
0 ignored**, including all 18 real-data tests with `MAPLE_WZ_ROOT`. Web shell: **51 passed / 0 failed / 0 skipped**.
The evidence root also preserves `smoke/` raw records and `logs/` verification output, including the full suite.

#### Spec #168 integration with main's spec #165 (2026-10-18)

Merged main `4ec2f0d` (PR #197) into Pirate tip `0352877`: Threaten retains status index 3, stun moves to 4,
and both use the five-status table. Warrior sections retain 7.9-7.12; Pirate sections are 7.13-7.20.
The fixture tool uses `--god` for both lines, with `--job=<id>[:<path>]` and `--exp-mult` retained; fixture state was not regenerated.
Private cache `s168-mainmerge`: 731 imgs, 22 unresolved original-data UOL warnings, zero import errors.
Full Godot suite: **1,974 passed / 0 failed / 0 skipped** (166 files, real private cache), including a new seeded
stun/Threaten coexistence and independent-expiry regression across slots. Rust: **64 passed / 0 failed / 0 ignored**
with `MAPLE_WZ_ROOT`; manifest golden regenerated and plain `cargo test` also passed. Web shell: **51 passed / 0 failed / 0 skipped**.
`flow_driver --scenario=pirate` (knuckle -> Brawler) and `--scenario=keys` passed; Pirate missing assets `[]`, both restored settings.
Screenshots of the job windows, weapons, Dash, Continue, keys/options and stun expiry were checked by eye under
`evidence/s168/mainmerge/`. The full suite still reports the previously recorded DummyTexture RID leak at shutdown (exit 0).
No balance tuning, new balance smoke or fixture-data changes; both historical smoke records below are retained.

#### Spec #167 Thief (#207-#214): QA regression smoke and fixtures (#215, 2026-10-18)

`bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, default job pick
and `--job=400:claw`, `--job=400:dagger`, `--job=410`, `--job=420`: 20 invocations / 60 runs on integration
`628223f` with QA tools only, read-only cache `caches/s167-int`, absolute `BALANCE_OUT`, no PATCH or tuning.
All 60 ended DEAD with `warnings: []` and `missing: []`; no crashes or script errors. Six additional Henesys
`--job=200` control runs use the same seeds/policies, since the new default draws do not sample Magician.
Those six also have empty warnings/missing. D = death time (nearest second), then final level; seeds 1 / 2 / 2026.
The comparison is the preceding #168 QA smoke, retained below.

| Henesys (seeds 1 / 2 / 2026) | bot | random |
|---|---|---|
| before, default pick (#195) | D 5:40 Lv11 / 5:32 Lv12 / 7:54 Lv21 | D 7:31 Lv19 / 8:40 Lv27 / 5:43 Lv13 |
| now, default pick | D 8:15 Lv24 / 5:32 Lv12 / 5:14 Lv11 | D 7:41 Lv20 / 8:40 Lv27 / 5:34 Lv13 |
| `--job=400:claw` and `--job=410` (same outcomes) | D 5:41 Lv11 / 6:14 Lv12 / 5:47 Lv13 | D 17:44 Lv24 / 5:24 Lv10 / 5:12 Lv11 |
| `--job=400:dagger` | D 5:19 Lv11 / 12:23 Lv31 (Assassin) / 5:14 Lv11 | D 15:10 Lv21 / 5:17 Lv10 / 5:34 Lv13 |
| `--job=420` | D 5:19 Lv11 / 11:11 Lv31 (Bandit) / 5:14 Lv11 | D 15:10 Lv21 / 5:17 Lv10 / 5:34 Lv13 |
| Magician control, `--job=200` | D 5:40 Lv11 / 7:35 Lv13 / 5:11 Lv11 | D 7:31 Lv19 / 5:25 Lv11 / 5:44 Lv12 |

The unforced pool now includes both Thief paths: default seed 1 draws Gun Pirate, seed 2 Warrior, seed 2026 Dagger
Thief in both policies. Warrior seed 2 matches the previous smoke; Gun Pirate seed 1 matches #195's forced-gun row.
Magician control seed 1 matches #195's default Magician (5:40 bot / 7:31 random); all six controls reach job200,
and Mano dies in bot seed 2 and random seed 1. Every Tree cell still dies before first job, D 2:09 / 1:04 / 0:52,
Lv3 / Lv2 / Lv2, matching the previous smoke; Tree remains record-only.

Thief first job arrives at 265.7-274.0 s. Of the 12 distinct first-job path/policy/seed cases, only Dagger bot seed 2
reaches Lv30 (546.2 s); forcing 400 leaves the second-job draw random, so it becomes Assassin and receives its claw.
Forcing 420 instead makes it Bandit at the same time. Claw never reaches Lv30; `--job=410` repeats its first-job
outcomes. Mano dies in three of those 12 cases (random seed 1 on each path, Dagger bot seed 2); there are no clears.
Claw MP-wait is 73.6-124.5 s/run; Dagger 67.5-87.8 s/run. These are observations of the existing bot, not a balance
assessment or a blocker (owner, #215); no bot or balance data was changed.

Fixtures `tests/fixtures/characters/assassin_2nd.json` (Lv49, job410, claw) and `bandit_2nd.json` (Lv50, job420,
dagger) are real headless bot rounds, seed1, Henesys, generated at `6a350f8d1d926460cf82e5c3ea5b64d304b8c25b`:
`tools/character_fixture.gd --out=<absolute JSON> --revision=<that SHA> --label=spec167/ticket-215
--job=410:claw|420:dagger --god --exp-mult=3 --seconds=600`. Each `_doc` records seed, policy, path, revision,
time cap and both diagnostic aids. Both were independently regenerated byte for byte. The aids accelerate diagnostic
coverage and prove no natural clear. `test_thief_fixtures.gd` checks provenance, job/path/weapon, learned branch attack,
casting order/rank/modifier restoration (six-decimal fixture tolerance), and 600 fixed ticks on the real map.

`flow_driver --scenario=thief --path=claw|dagger [--branch=410|420]` passes for both default branches: real Lv10
window with both paths, both gifts checked through Equip/Item UI, durable-target first-job combat, invulnerable EXP-drop
climb through the real Lv30 window, exact advancement weapon worn, original path and both gifts retained, and Free Market
Save & quit / disk reload / Continue preserving job, path, equipment, skills and mesos. Like the Pirate template, the
Free Market boundary itself is diagnostic setup, not a claimed natural clear. Both flows report missing `[]`.

All 71 final screenshots (plus the 14 superseded combat-probe frames) were checked by eye under
`C:/Users/itech/.t3/worktrees/maple-survivors/t3-e820a09f/evidence/s167/t215/`: `flow-claw/`, `flow-dagger/`,
`combat-final/`, `dark-sight/`, `disorder/`, `bandit/`, `playtest-assassin/` and `playtest-bandit/`.
The new `thief_combat_driver` checks actual flight paths for starter stars, Wolbi, Mokbi and Ilbi; Lucky Seven and
Drain use the current star, and the Lv35/Lv55 upgrades emit the proper notices. Hidden standing/walking is visibly
see-through (alpha0.5), recovery opaque; Disorder's green mob art, six-hit Savage Blow and a successful Steal with one
extra drop from a living mob are visible. `playtest.sh --job=410|420 --character=<matching fixture> --minutes=0.3
--speed=1` both report missing `[]`; these are 18-second branch rendering probes, not fresh-character progression evidence.

**UI findings, left for follow-up:** the shared first-available-instructor policy retains Dances with Balrog's portrait
and name on both Lv10 Thief confirmations (`flow-{claw,dagger}/06_thief_lv10_job_confirm.png`), rather than Dark Lord;
the Lv30 Assassin confirmation says "a Assassin" (`flow-claw/11_thief_lv30_job_confirm.png`). Both are existing shared
dialog behavior, not missing assets. No missing sprites, incorrect upgraded star sprites, opaque Hidden avatar or
missing Disorder art were found. Rust `cargo test`: 64 passed / 0 failed / 0 ignored, including all 18 real-data tests
with `MAPLE_WZ_ROOT`. Full Godot suites before/after integration sync: **2,057 passed / 0 failed / 0 skipped** each,
176 files, 590571 / 531423 ms, exit0, `ISOLATE=s167-t215` / `s167-t215-final`, `TEST_TIMEOUT_S=3000`.
Existing character/event and tick-cost goldens pass unchanged. Both runs have the previously documented two
DummyTexture RID allocations warning at shutdown. No acceptance criteria were dropped; no golden was recaptured.

#### Spec #168 Pirate (#186-#194): QA regression smoke and fixtures (#195, 2026-10-18)

`bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>` with the default job
pick and with `--job=500:knuckle`, `--job=500:gun`, `--job=510` and `--job=520` (20 invocations, 60 runs), a private real
cache built from the integration manifest, on `24183ee` (every #168 ticket) plus #195's tool changes, no PATCH or tuning.
No crashes, script errors or world warnings: all 60 records have `warnings: []` and `missing: []`. "Before" is the
spec #151 physical-combat foundation smoke below (`b3599ba`, default pick), the historical comparison used by this Pirate smoke.
D = death time, then level at the end; Lv 30 = the Lv 30 advancement was reached.

| Henesys (seeds 1 / 2 / 2026) | bot | random |
|---|---|---|
| before, default pick | D 5:40 / 5:36 / 5:11 | D 7:31 / 5:16 / 5:44 |
| now, default pick | D 5:40 Lv11 / 5:32 Lv12 / 7:54 Lv21 | D 7:31 Lv19 / 8:40 Lv27 / 5:43 Lv13 |
| `--job=500:knuckle` and `--job=510` (identical) | D 5:28 Lv11 / 5:35 Lv12 / 5:14 Lv11 | D 7:16 Lv21 / 5:14 Lv10 / 5:05 Lv11 |
| `--job=500:gun` | D 8:15 Lv24 / 10:15 Lv32 (Brawler at Lv 30) / 7:54 Lv21 | D 7:41 Lv20 / 5:29 Lv10 / 5:43 Lv13 |
| `--job=520` | D 8:15 Lv24 / 10:05 Lv31 (Gunslinger) / 7:54 Lv21 | D 7:41 Lv20 / 5:29 Lv10 / 5:43 Lv13 |

- **Non-Pirate runs are not worse.** Default-pick seed 1 is a Magician (200) and seed 2 a Warrior (100) in both policies,
  and they match "before" or beat it (Magician bot 5:40 and random 7:31 unchanged; Warrior bot 5:32 against 5:36, random
  8:40 against 5:16, the Warrior second-job work being in this branch). Default seed 2026 now draws a Gun Pirate
  (the unforced pool includes Pirate), which is why it moved. Tree is byte-identical to before in every cell
  (D 2:09 / 1:04 / 0:52, Lv 2-3, no job reached, both policies): it dies before Lv 10, so the Pirate never exists
  there. Tree stays record-only.
- **How far Pirates get.** The first job always arrives at 4:25-4:34. The knuckle bot never reaches Lv 30
  (0 of the 6 distinct runs; best D 7:16 at Lv 21, Mano killed in 1 of 6). The gun bot reaches it in 1 of 6 distinct runs:
  bot seed 2 (a Brawler in `--job=500:gun`, because a forced first job takes a seeded branch at Lv 30, a Gunslinger in
  `--job=520`). Gun runs kill Mano in 4 of 6 and always die between 5:29 and 10:15. `--job=510` with no path names
  the knuckle path, so it repeats `--job=500:knuckle` exactly; `--job=520` repeats `--job=500:gun` apart from the
  Lv 30 choice. The two known early deaths reproduce: `--job=510` D 5:14 at Lv 11 (seed 2026), `--job=520` D 7:54 at Lv 21
  (seed 2026) and D 8:15 at Lv 24 (seed 1).
- **Likely cause, recorded not fixed.** The deaths read like the Warrior's: damage is too low for what the swarm becomes
  and the pool is small (326 HP at Lv 11). Knuckle runs die to Mano's touch (about 26 % of max HP per hit, 3 to 4
  hits) before enough levels; the gun runs that pass Mano die at 7:54-8:15 (seeds 2026 and 1) under 40-110 live mobs, taking 500-850
  damage a minute while the bot kites a short-ranged character (mp-short 65-120 s per run; Flash Fist and Double Shot starve the pool). The bot
  does take and rank the Pirate attacks (Double Shot 4-6, Somersault Kick 9-12 in the gun runs) and no skill walks it
  into mobs, so no bot change was made. It never takes Dash or Bullet Time under the `bot` card policy (only
  `random` does). Pirate tuning and bot work belong to the balance pass.
- **A god-mode probe shows the knuckle line is slow, not broken.** The same bot made invulnerable on knuckles (the
  fixture tool's `--god`, 45 sim minutes) is still Lv 18: Mano takes 392 s to kill and the second boss is never
  killed, so it never levels again; the Gunslinger kills all three bosses by 1412 s and is Lv 42.
- Death times are of single seeds: the 3-seed smoke is bimodal per seed (see the Warrior record) and cannot judge pacing.
- **Fixtures.** `tests/fixtures/characters/lv37_brawler_2nd.json` and `lv36_gunslinger_2nd.json` come from the character
  fixture tool (`ISOLATE=<name> bash scripts/godot.sh --headless --path _scratch/godot_runs/<name>/game --script
  res://tools/character_fixture.gd -- --out=<abs> --revision=<sha> --label=spec168/ticket-195 --job=510:knuckle
  --god --exp-mult=3 --seconds=480` and `--job=520:gun --god --seconds=780`; seed 1, bot, `henesys_hg1`). Because the
  bot cannot reach Lv 30 by itself, the tool got two documented aids (tier C, diagnostic only): `--god` (invulnerable)
  and `--exp-mult` (EXP multiplier, used only for the knuckle line). Both are written into each `_doc`
  (`diagnostic`, `exp_mult`, `forced_path`). The Brawler is Lv 37 (Brawler from 412.9 s), the Gunslinger Lv 36 (520
  from 636.8 s, natural EXP).
- `flow_driver --scenario=pirate [--path=knuckle|gun] [--branch=510|520]` (injected input; debug setup: invulnerable EXP-drop warp
  to Lv 30, the Dash card applied) passes for both paths: the Lv 10 window offers both Pirate paths, the chosen path's
  weapon is worn and the other path's weapon and the creation weapon are in the Equip tab, the Lv 30 window offers
  both second jobs and the Lv 30 weapon (Prime Hands / Cold Mind) is worn, Dash on X raises speed and spends MP, and
  Save & quit then Continue keeps job, path, equipment, skills and mesos.
- Screenshots (evidence, not committed) were taken with `flow_driver --scenario=pirate` (job windows, Equip tab with both weapons, Dash,
  Save & quit / Continue), the new `scenes/debug/pirate_combat_driver.tscn` (both first-job paths, Brawler attacks, basic /
  Split / Mighty bullets: summary.json records ammo 2330000 / 2330001 / 2330002) and the earlier drivers `dash_driver`,
  `morph_driver --job=510` (Oak Barrel), `stun_driver` and `gunslinger_driver`; each was looked at.
- Full suite 1891 tests, 0 failed, 0 skipped (real private cache, merged tip `65992b4`); `cargo test` 64 passed with the real-data tests on (`MAPLE_WZ_ROOT`). The feature-ticket rule held: no balance data changed.

#### Spec #165 Warrior second job (#180-#184, QA #185): regression smoke (2026-10-18)

`bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, unforced and with
`--job=110`, `--job=120` and `--job=130`, real cache, no PATCH, no tuning, training seeds only, at the integration tip
`bf6c42b` (every ticket #180-#184) plus #185's tooling. "Before" is `b6af314`, main as it stood before this spec, rerun with
the same commands (`--job=100` for the forced rows: the first job a Warrior takes). No crash, script error, world warning
or `missing` entry in any of the 72 records (16 smoke, 6 fixture and 2 chain configurations, three seeds each).

| Deaths (m:ss, seeds 1 / 2 / 2026) | Henesys bot | Henesys random | Tree bot | Tree random |
|---|---|---|---|---|
| before, default pick | D 5:39 / 5:31 / 5:11 | D 7:30 / 8:39 / 5:43 | D 2:08 / 1:03 / 0:51 | same |
| after, default pick | D 5:39 / 5:31 / 5:11 | D 7:30 / 8:39 / 5:43 | D 2:08 / 1:03 / 0:51 | same |
| after, `--job=110` = `120` = `130` | D 5:39 / 5:31 / 5:23 | D 5:21 / 8:39 / 5:16 | D 2:08 / 1:03 / 0:51 | same |

- **Nothing moved.** Every one of the 12 default-pick records and the 36 forced ones (`--job=110`, `120`, `130`) is byte-identical to the "before"
  rerun (the forced `--job=110/120/130` records equal the `--job=100` ones once the `forced_branch` field is masked), so the
  spec changes no Magician, Beginner or first-job Warrior seeded record, as the decisions require. The older rows of
  4.2 (spec #151's smoke, `b3599ba`) reproduce at `b3599ba` with this cache (rerun `--job=100`: bot D 5:29 / 5:36 / 5:27,
  random D 5:41 / 5:15 / 5:15 by truncated seconds) and differ from this "before" by the content `b6af314` gained from
  main when #176 was squash-merged (#173 Legendary ranks, #177, #175); that was not bisected further, and this smoke's own
  `b6af314` rerun is the comparison.
- **The smoke cannot reach the second job.** A forced Warrior is Lv 11-12 when it dies at the first boss (Mano, 5:11-5:40;
  the bot never kills it, as in spec #151's record); the one exception is the careless `random` policy's seed 2 (Lv 27, dies
  at 8:39 after killing Mano). No run reaches Lv 30, so `--job=110/120/130` only forces the first job (every Warrior takes job
  100 at 4:25-4:34) and these rows do not exercise the second-job code. Henesys: 0 clears, every run dies; Mano is killed in
  2 of 6 default-pick runs and 1 of 6 forced ones (all unchanged from "before"). The Tree That Grew dies before the first job
  in every run (record only, as the owner's rework is pending).
- **`--tier=2` chain** (seeds 1 2 2026, default pick and `--job=110`): no tier-1 clear exists to feed it (0/3 and 0/3), so
  tier 2 never starts. The chain code is covered by `test_balance_chain.gd`; there is no real clear-fed Warrior chain to record.
- **Branch fixtures on `--stage=dark_cave`** (`--character=`, 3 seeds, bot and random). These do run second-job code:
  the fixtures carry the Final Attack, Booster and Mastery cards the bot took in the advancement draw and later levels
  (the other second-job skills are exercised by the playtests below, not by these records):

| Fixture (Lv 34) | Dark Cave bot, deaths | Dark Cave random, deaths | first boss (6300005) killed |
|---|---|---|---|
| `lv34_fighter_2nd.json` (110) | D 5:27 / 5:19 / 3:51 | D 5:15 / 5:19 / 3:24 | 0 of 4 spawned fights |
| `lv34_page_2nd.json` (120) | D 5:10 / 6:41 / 5:07 | D 5:19 / 5:28 / 3:28 | 1 of 5 |
| `lv34_spearman_2nd.json` (130) | D 10:03 / 10:12 / 3:54 | D 5:20 / 9:27 / 3:46 | 3 of 4 (the second boss spawns, not killed) |

  No clears; every run dies (seed 2026 before the first boss in five of its six runs). The two longest
  Dark Cave runs are the bot Spearman seeds 1 and 2 (10 minutes, Lv 59-60). Recorded for the balance pass, not tuned; no
  run clears without a death and not every run dies before the first boss, so the stop-and-ask conditions do not apply.
- **Fixtures.** `lv34_fighter_2nd.json`, `lv34_page_2nd.json`, `lv34_spearman_2nd.json`: real headless Henesys bot rounds,
  seed 1, policy `bot`, `--job=<110|120|130> --god --seconds=600` (`tools/character_fixture.gd`, revision in each `_doc`).
  `--god` is new and the fixtures need it: a Warrior bot dies at the first boss near Lv 12, so only an invulnerable round
  reaches the Lv 30 advancement (Mano is killed at 6:07 by the invulnerable Fighter; Lv 34 at 10:00; `_doc.invulnerable`
  says so). Regenerating each one twice with the same revision reproduces it byte for byte.
- **Flow driver** `--scenario=warrior2 --job=110|120|130` (invulnerable climb through the real Lv 10 and Lv 30 job windows,
  advancement weapons, a real advancement-draw skill, the Skill window with the unheld family greyed, Save & quit, Continue)
  passes for all three branches; see its header in `flow_driver.gd`. Playtest evidence shots are
  `<final attack key>_followup.png` and `reflect_first.png` (RunScene, `_shots_dir` only). The in-action shots (Final Attack follow-up, Rage, Power Guard, Threaten, Hyper Body)
  come from three-minute `playtest.sh --stage=dark_cave --character=` runs of evidence-only copies of the fixtures with
  every branch skill at rank 10 (not committed); on Henesys a Lv 34 Warrior one-shots everything, so no follow-up fires there.
- **Full suite** (cache `spec165`): 1752 tests, 0 failed, 0 skipped, 154 files; the tests that need the cache ran, none SKIPped.
  The three fixtures were regenerated from the committed code with their recorded revision and are byte-identical to the
  committed files.

#### Spec #151 physical combat foundation and Warrior first job: regression smoke (2026-10-18)

`bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, once with the default
job pick and once with `--job=100`, real cache, no PATCH or tuning. "Before" is `82cf212` (the #152 tip plus the
WeaponInfo family prefactor; identical to the #152 record above); "after" is the integration tip `b3599ba` (every ticket,
the review fixes and #164). No crashes, script errors, world warnings or `missing` entries in any record.

| | Henesys bot | Henesys random | Tree bot | Tree random |
|---|---|---|---|---|
| before, seeds 1 / 2 / 2026 | D 14:10 / 15:07 / 4:48 | D 8:22 / 5:39 / 5:21 | D 9:34 / 1:17 / 0:48 | D 5:39 / 1:24 / 0:48 |
| after, default pick | D 5:40 / 5:36 / 5:11 | D 7:31 / 5:16 / 5:44 | D 2:09 / 1:04 / 0:52 | D 2:09 / 1:04 / 0:52 |
| after, `--job=100` | D 5:30 / 5:36 / 5:27 | D 5:42 / 5:16 / 5:16 | D 2:09 / 1:04 / 0:52 | D 2:09 / 1:04 / 0:52 |

- **First job.** The unforced bot now draws Warrior or Magician on the job stream (8): seed 2 takes Warrior (100) in
  both Henesys policies, the others Magician (200). Every Henesys run reaches its first job at 4:26-4:34 (Magician
  265.7-274.0 s); Mano (5:00) is killed in 1 of 6 default runs (before: 3 of 6) and no run reaches the second boss.
- **Why the Magician seeds moved: random-stream reshuffles, not a damage change.** The whole shift arrives with #153
  (a per-merge bisect: every earlier merge is byte-identical to "before", every later one to #153, apart from #163's
  seeded first-job draw). Two intended changes consume random numbers differently: hits now roll a crit once the chance
  is above 0 (ACC x `crit.per_acc`, every job and damage type, owner decision), and basic-attack damage and crits roll
  on the basic-attack stream (5), which also picks the swing stance. Reverting only those two on `92307b7` gives runs
  bit-identical to before (Tree seed 1 for 120 s; Henesys seeds 1, 2 and 4 for 600 s, including the Magician
  advancement), so the damage formulas are unchanged. A headless probe (refs `research/spec151/diag/`, not
  `balance.sh` records) over Henesys bot seeds 1..24 to 600 s finds the old and new builds equal (10 vs 9 alive at 600 s, mean end 477 vs 476 s): seeds 1 and 2 were two of the long survivors before and
  land on a short branch now. The 3-seed smoke is bimodal per seed and cannot judge pacing on its own.
- **Beginner deltas (expected).** Crit rolls (above) and #159's drop rule: a Beginner holding the creation sword no
  longer draws the any-job Wooden Wand (only the held family drops).
- **Warrior (`--job=100`, untuned tracer).** Every forced Henesys run takes Warrior at 4:26-4:34 and dies at the first
  boss (5:16-5:42). Over Henesys bot seeds 1..24: 24 of 24 die (4:38-10:05), Mano is killed in 6 of 22 spawned
  fights, the second boss spawns once. The playtests show the bot MP-starved (0-4 of 100 MP at 5:14), never ranking a
  Warrior skill and never learning Iron Body; ACC is about 6 (all AP in STR), so crits add about 0.3%. Recorded for
  the balance pass and the Warrior second-job spec, not tuned.
- **The Tree That Grew:** recorded only (seed 1 now dies at 2:09 before the first job).
- **One forced-Warrior seed moved after the review fixes:** Henesys random seed 1 with `--job=100` was D 7:13 (Mano
  killed) at `f86ea37` and is D 5:42 at `b3599ba`. Of the review fixes only the Warrior facing change (Power Strike and
  Slash Blast turn to the nearest mob in every movement state) changes a Warrior run without Final Attack, a weapon grant
  or Teleport; every other fix left the records and goldens unchanged.
- `--job=210` (Henesys bot): D 5:40 / 7:35 / 5:11, Magician at 4:26-4:29, matching the default-pick Magician seeds.
- Full suite 1623 tests, 0 failed, 0 skipped; `cargo test` and the web dev tests pass. `test_character_baseline`'s
  Windows golden was re-captured twice (#153 crits and stream 5; #163 the Warrior option in the Lv 10 window and the
  seeded first-job draw).

#### #160 weapon attack speed and Boosters: timing deltas (spec #151)

No smoke was run for this ticket (the lead runs the spec's smokes). The deltas follow from the design in 7.7: every
timing is computed relative to the held weapon's own speed step, and only an active, family-matching Booster moves it.
- **Beginner and Magician (wand, staff): none.** There is no Booster in any shipped skill, so
  `WeaponInfo.speed_factor(base, 0)` is exactly 1.0 and the swing interval, impact time, stance length, skill cooldowns
  and action times are byte-identical to before. The 20-minute event digest of `test_character_baseline` is unchanged.
- **Why weapon speed does not rescale skills (decision to confirm).** Skill action times and cooldowns are not scaled by
  the weapon's speed *relative to the normal step 6*. In the real data the Wooden Wand is 6 but the staves are mostly
  8 (slow) and the starter Sword is 4: that reading would have slowed every Staff Magician's skills by 1.125x and sped up
  the Beginner's Three Snails by 0.875x, deltas in every record that nothing in the spec asks the balance owner to accept.
  The weapon's own speed still sets its swing interval (6.1.1), as before; the tier C skill numbers (0.8 s stance, the
  cooldowns) are read as "at the held weapon's speed". If the owner wants weapon speed to matter to skills, it is a
  small change (`Loadout.stats` and `BasicAttack._spec` take `WeaponInfo.NORMAL_SPEED` as the reference step instead of
  the weapon's own) and the Beginner/Staff records and the baseline digest must be re-captured.

#### #173 fixed Legendary magnitudes regression smoke (2026-10-18)

`ISOLATE=s173_smoke bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
real cache, on `b1e18d3` plus #173, no PATCH or tuning. All 12 runs finish without crashes, script errors or world
warnings; every record has `missing: []` and `warnings: []`. Every outcome and end time matches the latest combined
#142/#143/#144/#146/#148 smoke below. All are deaths (0/3 clears per row); Henesys still reaches Magician in 5/6
runs at 265.0–281.8 s and spawns bosses in those five. Bot seed 2026 still dies at Lv9 before Magician, as before.
Tree remains record-only. Death times are in seed order 1 / 2 / 2026; boss counts include every spawned encounter.
Legendary counts are displayed tiers after equal-gain relabelling, rather than raw Legendary rolls.

| Stage / policy | Death seconds (unchanged) | Magician reached | Bosses dead / spawned | Legendary offered / picked |
|---|---|---|---|---|
| Henesys bot | 849.7 / 906.6 / 287.9 | 2/3 | 4/5 | 1/1 |
| Henesys random | 501.7 / 339.4 / 321.4 | 3/3 | 1/3 | 1/0 |
| Tree bot | 574.3 / 76.6 / 47.9 | 1/3 | 1/1 | 0/0 |
| Tree random | 339.3 / 84.3 / 47.9 | 1/3 | 0/1 | 0/0 |

The synthetic character-event and tick-cost digests also retain their existing goldens. The new seam tests cover
Legendary +8 ranks, clamping to six ranks, +5 stacking steps (including unlimited cards), equal-gain Epic +3,
and the actual descriptions, previews, applied gains and bot scores. No balance values beyond #173's specified
Legendary magnitudes changed. Raw smoke records and logs are in the ignored `_scratch/s173_balance/` directory.
Full suite: 1,417 tests, 0 failed, 0 skipped; Godot reports two DummyTexture RID leaks at shutdown after TESTS_PASSED.

#### #142 / #143 / #144 / #146 / #148 combined regression smoke (2026-10-18)

`ISOLATE=lead_bal bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>` on
#177's merged branch (`b1e18d3`, before spec #151; all five tickets plus their review fixes), real cache, no PATCH or tuning. All 12 runs finish with no
crashes, script errors or world warnings; every record has `missing: []` and `warnings: []`. Every outcome and end time
agrees to the second with the #152 smoke on `39276ef` below (which rounds to whole seconds; here to 0.1 s): Henesys
bot D 849.7 / 906.6 / 287.9 s, random D 501.7 / 339.4 / 321.4 s; Tree bot D 574.3 / 76.6 / 47.9 s, random D 339.3 / 84.3 / 47.9 s. Magician is reached at
265.0-281.8 s in the same five Henesys runs, and bot seed 2026 still dies at Lv 9 before advancing. #146's tick-cost work
is output-identical by construction (`test_tick_cost_identity.gd`), and #144 only withholds the `hit` art of attacks
the hit window already turned away, so no change was expected. MP-short seconds per run (SYSTEMS line): Henesys bot
83.1 / 90.7 / 150.5, random 68.7 / 86.4 / 112.8.

The spec #151 merge of #177 re-captured the binary goldens on Windows against the unoptimised integration tip
`19ca0a8`, then matched them on the merged code: character baseline `b4526877...`, busy-round identity `cb554e31...`.
Their differences from #177's goldens are the accepted spec #151 crit RNG, physical combat, Warrior choice and
player-state changes. The character baseline now uses `var_to_bytes` on every platform, without the Linux guard.
The busy-round comparison includes all events, per-tick player state, drop pools and totals; bulk defense oracle
coverage includes live PDD as well as MDD, and Warrior admission is checked on both facing sides. No new balance
smoke or tuning was run for this merge.
Validation: `ISOLATE=s151mm TEST_TIMEOUT_S=3000 bash scripts/test.sh` with the shared cache: 1647 tests, 0 failed,
0 skipped. `cargo test`: 63 reported passes (17 real-WZ cases returned early without `MAPLE_WZ_ROOT`, so those prove
nothing); web dev tests: 51 passed, 0 failed. The manifest did not change, so no import was run.

#### #152 job-generic prefactor regression smoke (2026-10-17)

`ISOLATE=final bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, plus
`--job=210` and `--branch=210` (Henesys bot), no PATCH or tuning. #152 first regroups `upgrades.json` cards by job line
(common, beginner, magician: the per-line merge order; owner choice) in a data-only commit, `11664d2`. The roll walks
the pool in array order, so that commit alone changes which cards a seed draws. The same smoke on `main` (`bb6eee9`)
equals the web audio smoke below; on `11664d2` it gives:

| | Henesys bot | Henesys random | Tree bot | Tree random |
|---|---|---|---|---|
| seeds 1 / 2 / 2026 | C 16:16 / T 30:00 / D 18:07 | D 13:09 / 6:40 / 11:18 | D 16:32 / 12:52 / 2:08 | D 8:52 / 3:10 / 2:15 |

(Henesys bot seed 2 kills two bosses and is still fighting the third at the 30:00 cap; Magician 265.0–290.1 s.) Every
later #152 commit (per-line data files, manifest fragments, job-generic plumbing, `--job`) gives per-seed records
byte-identical to `11664d2` apart from the new `job_times` key, `job_t` equals `job_times["200"]` in every record, and
`--job=210` equals `--branch=210`. No crashes, script errors or world warnings. Full suite 1379 tests, 0 failed,
0 skipped; `cargo test` and the web dev tests pass.

After merging `main` with spec #88 (`39276ef`), the same smoke on the merge equals `39276ef` plus the regroup commit
record for record (again apart from `job_times`; `--job=210` equals `--branch=210`): Henesys bot D 14:10 / 15:07 / 4:48,
random D 8:22 / 5:39 / 5:21; Tree bot D 9:34 / 1:17 / 0:48, random D 5:39 / 1:24 / 0:48. Bot seed 2026 now dies at Lv 9
before advancing, so the #88 guard that every Henesys seed reaches Magician no longer holds. The owner chose
(2026-10-17) to relax it to the 2/3 early-milestone majority until the balance pass. The other five Henesys runs reach
Magician at 265.0–281.8 s.

#### Spec #88 hit-window pressure regression smoke (2026-10-17)

`bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
real cache, no PATCH or tuning. "Before" is `main` at `bb6eee9`; "after" is `7d1d2c9` (Spec #88, the shrinking hit
window). The owner decided on 2026-10-17 to ship #88 as specced despite this smoke; the Henesys pacing regression is
recorded here for the dedicated balance pass to tune, not fixed by this ticket. All 12 runs finish with no crashes,
script errors or world warnings, and every record has `missing: []` and `warnings: []`.

Henesys clears fall from 2/6 to 0/6 (bot and random seed 1 cleared before). All six Henesys runs now die between 5:12
and 9:24; three of them die while the first boss, Mano (spawned at 5:00), is still alive. Every recorded boss hit is a
body touch, so the shrinking contact window drives these deaths, not the boss-attack bypass. The bypass is not measured
by this smoke at all: Mano only touches (baseline too), and the first Henesys boss with a skill attack, Mushmom 6130101
at 10:00, is never reached (baseline: 9 Henesys `attack` hits from 6130101 / 9400205). Magician is reached at the
same times as before in all six Henesys runs. Tree stays 0/6 clears and record-only: five of six runs die before 2:30
(baseline two).

| Stage, policy, seed | Outcome, end | Magician reach | Hits before 6:00 | Hits after 8:00 | Boss hits |
|---|---|---|---|---|---|
| Henesys, bot, 1 | C 15:29 -> D 8:31 | 4:41 -> 4:41 | 2 -> 2 | 202 -> 0 | 10 -> 2 |
| Henesys, bot, 2 | D 23:44 -> D 5:40 | 4:31 -> 4:31 | 31 -> 1 | 449 -> 0 | 37 -> 10 |
| Henesys, bot, 2026 | D 21:08 -> D 9:24 | 4:25 -> 4:25 | 4 -> 4 | 387 -> 141 | 20 -> 1 |
| Henesys, random, 1 | C 16:28 -> D 8:31 | 4:34 -> 4:34 | 0 -> 0 | 243 -> 0 | 8 -> 0 |
| Henesys, random, 2 | D 7:42 -> D 5:12 | 4:28 -> 4:28 | 31 -> 1 | 0 -> 0 | 9 -> 18 |
| Henesys, random, 2026 | D 10:59 -> D 5:36 | 4:20 -> 4:20 | 16 -> 3 | 58 -> 0 | 5 -> 4 |
| Tree, bot, 1 | D 11:18 -> D 2:24 | 3:39 -> never | 28 -> 23 | 74 -> 0 | 11 -> 0 |
| Tree, bot, 2 | D 2:36 -> D 1:17 | never -> never | 21 -> 17 | 0 -> 0 | 0 -> 0 |
| Tree, bot, 2026 | D 2:08 -> D 0:47 | never -> never | 27 -> 0 | 0 -> 0 | 0 -> 0 |
| Tree, random, 1 | D 20:23 -> D 9:05 | 3:34 -> 3:27 | 18 -> 28 | 273 -> 125 | 28 -> 1 |
| Tree, random, 2 | D 2:38 -> D 1:17 | never -> never | 21 -> 17 | 0 -> 0 | 0 -> 0 |
| Tree, random, 2026 | D 1:28 -> D 0:47 | never -> never | 10 -> 0 | 0 -> 0 | 0 -> 0 |

Cells are before -> after. "C" is CLEARED, "D" is DEAD, and "never" means no job change to Magician before the run
ended. Magician reach is the record's `job_t`; the hit columns come from `hits_by_min`, which omits the partial last
minute of each run (a death at 5:40 counts minutes 0-4 only). Tree rows are record only.

#### Web audio fix regression smoke (2026-10-17)

`ISOLATE=webaudio_bal bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
real cache re-imported for the current manifest, no PATCH or tuning, on `fix/web-audio` (`main` at `c0a4877` plus
`game/default_bus_layout.tres` and an `AudioService` fallback counter; nothing in the sim). All 12 runs finish with no
crashes, script errors or world warnings, and every record equals the Spec #130 review fixes smoke below: Henesys bot
C 15:29 / D 23:44 / D 21:08 (Magician 265.9–281.3 s), random 1 clear (16:28) then deaths 7:42 / 10:59; Tree bot
D 11:18 / 2:36 / 2:08, random D 20:23 / 2:38 / 1:28 (Tree stays record-only). Full suite 1342 tests, 0 failed, 0 skipped.

#### #131 web build spike regression smoke (2026-10-17)

`ISOLATE=s130t131 bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
real cache, no PATCH or tuning. The ticket adds only the "Web" export preset (no game code). All 12 runs finish with
no crashes or world warnings. Every end time equals the #79 combined smoke: Henesys bot 0/3 (780.4/791.1/907.5 s),
random 1/3 (clear on seed 1, then 437.8/624.0 s); Tree bot 0/3 (652.3/677.4/128.3 s), random 0/3
(617.5/165.0/88.4 s). Henesys reaches Magician 3/3 (bot). The web build replays seed 2026 bit-identically to the
desktop exe (`docs/ARCHITECTURE.md` 10.1).

#### #134 web profile regression smoke (2026-10-17)

`ISOLATE=s130t134b bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
real cache, no PATCH or tuning, after merging #132 into the ticket branch. The ticket changes only presentation and
platform code (fonts, title/import/options/key-config UI, display settings, a web hand-off helper), nothing in the sim.
All 12 runs finish with no crashes, script errors or world warnings and every end time equals the #131 smoke above:
Henesys bot 0/3 (780.4/791.1/907.5 s, Magician at 266.1/269.5/274.7 s), random 1/3 (clear on seed 1, then
437.8/624.0 s); Tree bot 0/3 (128.3/652.3/677.4 s), random 0/3 (88.4/165.0/617.5 s; Tree stays record-only). Full suite
853 tests, 6 failed (the known #103 family: `test_key_config` 1, `test_key_config_window` 2, `test_run_scene` potion keys
2, `test_teleport` key binding 1, all reading the developer's own `settings.cfg`), 0 skipped. The desktop flow driver
`--scenario=full` finishes (12 level-up windows answered, job dialog true, no FAILED) with the title and pause menu
unchanged by eye.

#### #63 sensible bot values card tiers: regression smoke (2026-10-17)

`ISOLATE=<tag> bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>` plus
`bash scripts/balance.sh 1 2 2026 --tier=2 --policy=bot`, shared real cache, unforced branches, default cap, no PATCH
or tuning. "Before" ran on a detached copy of `ff71af2`; "after" adds `bot.gain_step_score` 6 (card score = base +
6 x (magnitude - 1)). No balance data changed. All runs finish with no crashes, script errors or world warnings.
`random` never calls `card_score`, and its rows are identical before and after (Henesys 1/2 with deaths at 7:42/10:59;
Tree 0/3 with deaths at 20:23/2:38/1:28). Raw records are outside the repo.

| Stage / policy | Clear/dead before -> after | End (seed order 1/2/2026) before -> after | Final Lv | Non-Normal cards picked / offered |
|---|---|---|---|---|
| Henesys bot | 0/3 -> 1/2 | D 20:14 / D 14:40 / D 22:16 -> C 15:29 / D 23:44 / D 21:08 | 34/27/33 -> 43/41/35 | 24/92 (Epic 0/12, Legendary 0/2) -> 41/109 (Epic 8/17, Legendary 1/1) |
| Tree bot | 0/3 -> 0/3 | D 10:26 / 2:36 / 2:08 -> D 11:18 / 2:36 / 2:08 | 24/4/3 -> 25/4/3 | 4/25 -> 5/25 |
| Henesys random / Tree random | unchanged | unchanged | unchanged | not scored by the bot |

Henesys bot: all 3 runs still reach Magician (265.9–281.3 s) and Mano (3/3 completed). The third boss (9400205) completes
1/3 (before: 0/2 spawned, 1 never spawned). Tier-2 chain (bot): before, no tier-1 clear fed Dark Cave (0/3). After, seed 1
feeds 1/3, and that Dark Cave round dies at 13:57 (Lv 43 -> 55, Zombie Mushmom killed, Snack Bar alive, Jr. Balrog not
spawned). Every sensible-policy number before this entry comes from a bot that ignored card tiers. #77 tunes tier 2
against this bot.

#### Spec #130 review fixes regression smoke (2026-10-17)

`ISOLATE=s130rf bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, shared real
cache, no PATCH or tuning, on `spec130/review-fixes` (the integration tip `ada5f31` plus the review fixes). The fixes
touch the web shell, the wasm importer's unused zip scratch code, docs, a Key Config font constant, a shared fullscreen
mode test and a `WebHandoff.hand_over` helper; nothing in the sim. All 12 runs finish with no crashes, script errors or
world warnings, and every record equals the #63 smoke above: Henesys bot C 15:29 / D 23:44 / D 21:08 (1 clear), random
1 clear then deaths 7:42 / 10:59; Tree bot D 11:18 / 2:36 / 2:08, random D 20:23 / 2:38 / 1:28 (Tree stays record-only).
Full suite 1323 tests, 0 failed, 0 skipped.

#### Spec #33 / #105 worn equipment regression smoke (2026-10-16)

`ISOLATE=s33t105 bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
private real cache (spec #33 copy plus the `barehands` weapon sound), unforced branches, 1,800 s cap, no PATCH or
tuning, on the ticket branch (base `db1c5cb`, before #106). The fixed `balance.player.equipment` outfit is gone: a
fresh Beginner now wears the first MakeCharInfo outfit as worn equipment (1040002 / 1060002 / 1072001 / 1302000),
which has exactly the old outfit's stats, and Magician advancement grants the same Wooden Wand the old weapon rule
used. So every outcome, end time, Magician time and potion total equals the #79 combined smoke below; the only new
simulation output is one `equipment_changed` event at the wand grant (the `test_character_baseline` stream hash
changes by that event alone: filtering it out reproduces the old hash). All 12 runs finish with no crashes, script
errors or world warnings. Raw records: ignored `_scratch/t105_smoke/`.

| Stage / policy | Clear/dead #79 -> #105 | End seconds (seed order 1/2/2026) | MP collected/used | Magician s |
|---|---|---|---|---|
| Henesys bot | 0/3 -> 0/3 | 780.4/791.1/907.5 (unchanged) | 158/158 (unchanged) | 266.1–274.7 |
| Henesys random | 1/2 -> 1/2 | C/437.8/624.0 (unchanged) | 168/168 (unchanged) | 265.4–271.6 |
| Tree bot | 0/3 -> 0/3 | 652.3/677.4/128.3 (unchanged) | 136/136 (unchanged) | 224.5–249.6 (2 runs) |
| Tree random | 0/3 -> 0/3 | 617.5/165.0/88.4 (unchanged) | 80/77 (unchanged) | 217.8 (1 run) |

Henesys reaches Magician and Mano in 3/3 per policy; Mano completes 3/3 (bot) and 2/3 (random). Tree is record-only.
No stop-and-ask gate. Characters created with other clothes or weapons now get those items' own stats (every
creation top/bottom/shoes is W.DEF 3/2/2 in v83, so only the Beginner weapon choice differs, as before).

#### #34 / #115 NX award regression smoke (2026-10-16)

`ISOLATE=s34-115 bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, real
cache, unforced branches, no PATCH or tuning, on the #115 branch against the integration base (`db1c5cb`) run from a
frozen copy. All 12 records are byte-identical once the three new keys (`nx_awarded`, `bosses_killed`,
`levels_gained`) are removed, so the feature changes no simulation: Henesys bot 0/3 clears (deaths 13:00 / 13:11 /
15:07), Henesys random 1/3 (seed 1 clears), Tree 0/3 in both policies, as in the #80 / #32 smokes above. No crash,
script error or world warning; the player's `user://save.json` was untouched (tools never open SaveData). The
placeholder award (`nx_award` in `balance.json`: clear bonus 100 / 250, 5 per level, 40 per boss) gives, per run in seed
order 1/2/2026 (bosses killed, levels gained in parentheses):

| Stage / policy | NX awarded per run |
|---|---|
| Henesys bot | 240 (2, 32) / 160 (1, 24) / 240 (2, 32) |
| Henesys random | 435 clear (3, 43) / 50 (0, 10) / 170 (1, 26) |
| Tree bot | 160 (1, 24) / 145 (1, 21) / 10 (0, 2) |
| Tree random | 155 (1, 23) / 15 (0, 3) / 10 (0, 2) |

The table and `SUMMARY` of `balance.sh` gain an NX column and an "NX awarded per run (recorded, never credited)"
min-median-max line; `SYSTEMS` repeats it from the aggregate. Raw records: ignored `_scratch/{base,new}/`.

#### #34 / #119 pet in the round: regression smoke and a full-account record (2026-10-16)

`ISOLATE=... bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random|first>`, real
cache, no PATCH or tuning, empty account, against a `git archive` of the integration base (`662733c`). All 18
`BALANCE` records (2 stages x 3 policies x seeds 1/2/2026) are byte-identical (`cmp`), so a round without a pet changes
nothing: Henesys bot 0/3 clears, random 1/3, Tree 0/3 as before; no crash, script error or world warning. The pet adds
no key to a record unless one is out (`pet`: species, abilities, `pickups`, `potions_used` of the pet, `alert`).

One-off with the full account (`--account=game/tests/fixtures/accounts/full_pet.json`: Brown Kitty, Auto HP/MP, Wing
Boots, Binocular, VAC, ALERT 50 % / 30 %; bot unchanged), seeds 1/2/2026, no warnings. The pet takes the drops and
refills MP for the bot; the player's own `potions_used` stay separate from the pet's:

| Stage / policy | Outcomes (end time) | Level | Pet pickups (seeds 1/2/2026) | Pet drinks HP / MP (1/2/2026) |
|---|---|---|---|---|
| Henesys bot | 0/3 clears; died 18:05 / 19:37 / 15:29 (empty account: 13:00 / 13:11 / 15:07) | 38 / 41 / 35 | 2479 / 2963 / 2003 | 0 / 3, 0 / 4, 0 / 1 |
| Henesys random | 1/3 (seed 1 clears 16:34; empty account clears 16:07); others died 7:07 / 9:04 | 46 / 11 / 18 | 2728 / 208 / 529 | 1 / 3, 0 / 4, 0 / 1 |
| Tree bot | 0/3; died 11:24 / 13:49 / 10:45 (empty: 10:52 / 11:17 / 2:08) | 26 / 25 / 24 | 2434 / 2435 / 1930 | 0 / 6, 3 / 7, 0 / 1 |

Observations only, no tuning: the pet seldom drinks HP (0-3 drinks a run) because the bot already drinks at its own
threshold, which is above the 50 % ALERT; VAC makes the pet collect most EXP (the `drop8` column falls to 1-2 drops on
the map). Raw records: ignored `_scratch/out_{base,new,acct}/`.

#### #32 merged with main after #79 (2026-10-16)

Regression smoke on the merge (`ISOLATE=sm79`, seeds 1/2/2026, both stages, bot/random, no PATCH or tuning): every
outcome and end time equals the #79 combined smoke below (Henesys bot 0/3, random 1/3 on seed 1; Tree 0/3), so #32
adds no simulation change to a fresh Beginner. The fresh-character event-stream hash in `test_character_baseline` was
re-captured on main `3f7e4b7` and matches the merge. Chains: bot feeds tier 2 in 0/3; random 1/3 (Lv 44 -> 63, died).
The #32/#75 numbers below are from before #79. Seed 1 no longer gives a bot Henesys clear, so the flow driver's
`rounds` scenario defaults to training seed 4 (bot clears: 4, 5, 6, 13 of 3..14); it passes with `missing=[]`.

#### #32 / #75 whole-flow QA and regression smoke (2026-10-16)

Implementation `89de7fa`, integration `dba59a9`; `ISOLATE=t75`, existing cache-t70 reused read-only, no import.
Training seeds 1/2/2026, bot/random, default branches, 1800s cap per round; no PATCH, tuning or held-out seeds.
All **24 seed records / 26 rounds** finish without crashes, script/engine errors or world warnings, with
`missing=[]`. Outcomes, end times, levels and tier-1 MP-wait means match #71/#74 below exactly. Every Henesys
round reaches Magician and Mano; Tree's early deaths remain record-only. Tier-2 outcomes remain first-pass data for #77.

| Group / policy | Clear / dead / timeout | End seconds (1 / 2 / 2026; C = clear) | Start → end levels |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8 / 812.3 / 322.7 | 1 → 41 / 28 / 10 |
| Henesys random | 1 / 2 / 0 | C974.6 / 714.8 / 329.0 | 1 → 43 / 27 / 11 |
| Tree bot | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 1 → 3 / 3 / 2 |
| Tree random | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 1 → 3 / 3 / 2 |
| Chain tier 2 bot | 0 / 1 / 0 | 685.2 / — / — | 41 → 52 |
| Chain tier 2 random | 0 / 1 / 0 | 1240.1 / — / — | 43 → 64 |
| Dark Cave fixture bot | 0 / 3 / 0 | 789.3 / 780.7 / 807.8 | 38 → 58 / 61 / 60 |
| Dark Cave fixture random | 0 / 3 / 0 | 609.5 / 595.6 / 754.0 | 38 → 51 / 50 / 55 |

Each chain policy feeds tier 2 from **1/3** tier-1 clears (seed 1 only), starts/clears **1/0**, Lv70 **0/1**;
fixture Lv70 **0/3** per policy. Chain Zombie Mushmom completes in 121.75s bot / 51.68s random, each **1/1
completed/spawned**, censored median the same (n=1, no unfinished fights). Snack Bar completes none (n=0),
**0/1 spawned** per policy, censored medians **>=85.20s / >=640.12s** (n=1, one unfinished each).
Jr. Balrog bot has **0/0 spawned**, no completed or censored observation (n=0), one not spawned;
random has **0/1 spawned**, none completed (n=0), censored median **>=340.12s** (n=1, one unfinished).
No bosses are skipped. Fixture boss metrics reproduce #73/#74; full console/SYSTEMS output and seed/configuration
records stay ignored under `evidence/t75/smoke/`.

The injected `rounds` scenario creates two characters through the v83 controls, really clears Henesys at
967.817s/Lv41, resumes the hub from disk, walks to out00, saves/resumes map select, quits/replays Dark Cave
seed 1 without changing the boundary bytes, dies at 841.583s/Lv58, cancels then confirms the spare's deletion,
and checks both history rows. Its tier-2 seed is deliberately the driver's seed 1, not the chain harness seed.
This verifies flow, not balance. Evidence, limitations and QA defects are in
[ticket-75-audit.md](research/ticket-75-audit.md).
The full suite after the final integration fetch/merge passes **732 tests, 0 failed, 0 skipped, 81 files**
(365.466s). Final natural/staged-victory rounds, full flow and one-off clear have `missing=[]`; all seven boss
attack probes also have empty missing/warnings. Import is checked in screen-only mode, without re-importing assets.

#### #32 / #71 Free Market regression smoke (2026-10-16)

Revision `96cb046`; training seeds 1/2/2026, both original stages, bot/random, default branches and 1800 s cap,
no PATCH or tuning. Every Godot run uses `ISOLATE=t71` and private cache
`C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t71` (copied once, then imported with #71's
manifest; 108 imgs, 12 written, zero warnings/errors). All 12 finish without crashes, script errors or world
warnings. Outcomes, levels, times and MP-wait means match #69 exactly; all six Henesys runs reach Magician
and spawn Mano. Tree's known early deaths remain record-only.

| Stage / policy | Clear / dead / timeout | End seconds (1 / 2 / 2026; C = clear) | Final levels | Mean MP-wait s/run |
|---|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8 / 812.3 / 322.7 | 41 / 28 / 10 | 205.133 |
| Henesys random | 1 / 2 / 0 | C974.6 / 714.8 / 329.0 | 43 / 27 / 11 | 178.455 |
| Tree bot | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 | 98.956 |
| Tree random | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 | 98.956 |

After merging #74 (`0c72c68`), reran its chain and Dark Cave fixture modes on seeds 1/2/2026, bot/random,
under the same private cache/isolation and no tuning. These 12 additional seed records / 14 rounds also match
#74 exactly: only seed 1 feeds tier 2 (1/3 per policy), bot Lv41 -> 52 dying at 685.2 s, random Lv43 -> 64
dying at 1240.1 s; neither clears or reaches Lv70. The Lv38 F/P fixture dies at 789.3 / 780.7 / 807.8 s
(bot, final Lv58/61/60) and 609.5 / 595.6 / 754.0 s (random, Lv51/50/55), no clears/Lv70. All 14 added rounds
report `warnings=[]`, `missing=[]`; no smoke log has a script/engine error. Combined: 24 seed records / 26 rounds.
The tier-2 deaths are unchanged first-pass evidence, not a reason to tune in this feature ticket. Exact records
and console/SYSTEMS output are ignored under `evidence/t71/chain_fixture/`.

Exact seed records, console/SYSTEMS output and aggregates are ignored under `evidence/t71/smoke/`.
The real-map `free_market_driver` supplies a completed-round summary with the committed Lv38 F/P fixture,
then verifies autosaved arrival, Esc pause, Save & quit, disk reload/Continue, inert room entry, fixed-tick
walking right to the real out00, keyboard Up and tier-2-only map select. This is a boundary probe, not a full
two-round playtest. Checked `evidence/t71/hub/01_arrival.png`, `02_npcs.png`, `03_save_quit.png`,
`04_continue.png`, `05_rooms.png`, `06_out00.png`, `07_next_tier.png` by eye: canonical map/room art, all four NPCs,
the character's outfit/weapon, full HP/MP status, readable instruction plate and boundary pause. Report:
`failures=[]`, `missing=[]`. Focused tests pass 23/23 with zero failures/skips; coverage includes all 22 room
portals, the two real ladders, normal jump/climb/same-map portal behavior, snapshot immutability, look/weapon
resolution, pool agreement with RunWorld, pause holding motion, clear/resume/exit saves and final-tier victory.

After the final fetch/merge of integration `0c72c68` and correction of the old stage-only manifest assertion,
the full `ISOLATE=t71 bash scripts/test.sh` passes **721 tests, 0 failed, 0 skipped, 80 files** (326.337 s).
All real-cache checks execute; none is skipped. Log: ignored `evidence/t71/full_suite_final.log`.
Final focused data/hub/flow checks pass **41 tests, 0 failed, 0 skipped** (`evidence/t71/focused_final.log`).
The #70/#71 integration replaces the temporary `FreeMarket.character_look(character, data)` resolution with
`DataRepo.character_look`. It reads only CharacterSnapshot.look and resolves the job weapon (nonzero
beginner_weapon for a Beginner, otherwise weapon_by_job), without changing the snapshot.

#### #32 / #70 rework audit and visual verification (2026-10-16)

Rework code `0cdfc7e` / `8c1a0b2`, merged #71 integration `d4eaf94` via `44ce69d`. Audited every desired behavior
and acceptance criterion from the current ticket against source and a fresh baseline windowed run; the full table
is [ticket-70-r2-audit.md](research/ticket-70-r2-audit.md). Runtime MakeCharInfo options, variant imports, name rules,
authoritative look carry and canonical Beginner weapon behavior were already correct. Fixed the invented roster
composition, shared-action/selection behavior, v83 option-row presentation, phased Gender/name/appearance surfaces,
delete notice, history entry placement, class badge mapping and keyboard focus overlay. No sim/balance changes.

`ISOLATE=t70`, private cache `C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t70`. The merged manifest
was imported from the local original v83 install: 157 imgs (12 written, 145 current), 13636 canvases, 163 pages,
164 sounds; zero unresolved UOLs, warnings or errors. Shared cache untouched. **No balance smoke rerun**, per the
owner's rework instruction because weapon/gameplay code is unchanged; the original #70 smoke remains below.

| Verification | Result |
|---|---|
| Full Godot suite after integration merge | 732 tests, 0 failed, 0 skipped, 81 files (336.368 s); every real-cache test executed |
| Focused UI/creation/basic attack/hub/widgets | 53 tests, 0 failed, 0 skipped |
| Rust importer | 47 tests pass; all 17 real-data integration tests separately execute with MAPLE_WZ_ROOT set (0 failures/skips) |
| Visual character driver | 19 required states, missing=[]; real Right key changes selection while Start holds focus |
| Full injected keyboard/mouse flow | Pass: creation, Magician/cards, pause/resume, death/results, confirmed Quit round, same-seed Continue, history, title; missing=[] |

Checked the screenshots under `evidence/t70r2/review_fix/` by eye: empty/one/three slots, changed selection and keyboard
focus, deletion confirmation, history entry/list, Gender and name steps, invalid name, default and changed male/female
previews (black -> brown hair, face, skin, clothes, shoes, weapon), created look in an actual launched round, and the same
look in the Free Market. The hub capture supplies a completed boundary for presentation, not a claim of a Lv1 clear.
The probe cycles every option for each gender and every hair/colour pair, and explicitly requires every WzImage and
WzButton's art because UiArt normally tolerates absent optional art. Final `summary.json` has missing=[].

The full flow's training seed 1 at x3 reaches Magician, answers 14 level windows, resumes from pause, and dies at
379.5 s / Lv13 before checking replay/history. This is a flow check, not pacing evidence. Exact console/summary and 25
flow captures are ignored under `evidence/t70r2/flow/` and `flow.log`.
The independent finish reviewer scored all four corrections resolved (badges, keyboard focus, weapon readability,
provenance docs), disposition ship at that fix-list scope. Documentation finish check preserves the existing v83
identity. Full-suite console output is `evidence/t70r2/full_suite.log`; all checks used `ISOLATE=t70`.
Exact v83-executable screen positions remain unverified; tier A/B/C boundaries are recorded in section11.

#### #32 / #70 character creation and weapon regression smoke (2026-10-16)

Creation/weapon code `72f2dfd`, followed by #74 harness integration `bb933f1`; `ISOLATE=t70`, private cache
`C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t70`. Report-only training seeds 1/2/2026,
1800 s cap, default branches, no PATCH, tuning or held-out seeds. Each weapon uses an otherwise identical fresh
Beginner snapshot with an empty look (the default outfit); the extra standard matrix uses fresh one-off rounds.
All 21 rounds finish without crashes, script errors or world warnings. All nine weapon runs and all six standard
Henesys runs reach Magician and spawn Mano. The standard matrix's outcomes, end times and levels exactly match
the preceding #69 smoke; Tree's early deaths remain record-only. Sword's carried snapshot reproduces the fresh
Beginner baseline. Club and Axe change the deterministic journey as expected; no data was tuned.

| Stage / policy / weapon | Lv10 seconds (1 / 2 / 2026) | End seconds (C = clear, D = died; 1 / 2 / 2026) | Final levels |
|---|---|---|---|
| Henesys bot / Sword 1302000 | 279.9 / 283.2 / 270.6 | C967.8 / D812.3 / D322.7 | 41 / 28 / 10 |
| Henesys bot / Club 1322005 | 281.5 / 274.7 / 273.9 | C987.0 / D851.1 / C961.8 | 38 / 28 / 39 |
| Henesys bot / Axe 1312004 | 271.3 / 279.6 / 271.3 | C1024.8 / D960.6 / C938.9 | 39 / 32 / 38 |
| Henesys bot / default | 279.9 / 283.2 / 270.6 | C967.8 / D812.3 / D322.7 | 41 / 28 / 10 |
| Henesys random / default | 263.2 / 278.3 / 276.0 | C974.6 / D714.8 / D329.0 | 43 / 27 / 11 |
| Tree bot / default | not reached | D141.9 / D141.0 / D77.4 | 3 / 3 / 2 |
| Tree random / default | not reached | D141.9 / D141.0 / D77.4 | 3 / 3 / 2 |

Ignored evidence: `evidence/t70/smoke/` preserves per-seed configuration/records, exact console output and SYSTEMS
aggregates; the identical fresh weapon snapshots are in `_scratch/t70/weapon_<id>.json`. The private import writes
148 imgs (49 new/changed), with zero errors/warnings/unresolved UOLs. Rust passes 47 tests (including all 17
real-data tests with MAPLE_WZ_ROOT set). Checked `three_characters.png`, both `creation_*.png`, `invalid_name.png`,
`delete_confirmation.png`, `history.png` and `round_chosen_look.png` under `evidence/t70/` by eye. They show three
distinct carried appearances with job weapons, gender-specific choices and live preview, recoverable validation,
deletion confirmation, dated endings, and the chosen look/Club in a round. `character_driver` reports `missing=[]`.
The updated injected keyboard/mouse `flow_driver --scenario=full --seed=1 --stop-at=330` also passes: new creation,
map select, Magician and 16 card windows, pause/resume, death/results, another creation, confirmed Quit round,
same-seed Continue, history and return to title. It dies at 387.5 s / Lv15; its summary has `missing=[]`.
Screenshots, summary and exact log are under `evidence/t70/flow/` and `evidence/t70/flow.log`.

After merging #74, the added spec-32 chain/fixture matrix runs the same seeds and both policies: **12 more seed
records / 14 rounds**, giving **33 records / 35 rounds** overall, with zero crashes, script errors, world warnings
or missing setup assets. Each chain has only seed 1 feeding tier 2 (1/3); bot dies at 685.2 s / Lv52 and random
at 1240.1 s / Lv64. Dark Cave fixture deaths are bot 789.3 / 780.7 / 807.8 s (Lv58/61/60) and random
609.5 / 595.6 / 754.0 s (Lv51/50/55). These exactly match #74; no chain or fixture reaches Lv70, and the small
conditional tier-2 sample is not a balance assessment. Exact records/console/SYSTEMS output remain in
`evidence/t70/smoke/chain/` and `fixture/`.

After the integration merge, code `ca02312` passes the full `ISOLATE=t70 bash scripts/test.sh`: **722 tests,
0 failed, 0 skipped, 80 files** (366.672 s), including every real-cache test. Log: `evidence/t70/full_suite.log`.
Creation/persistence focused checks also pass 22/0/0; the reloaded-look assertion accounts for JSON numbers
becoming floats. No skipped check is being treated as evidence.

#### #32 / #74 headless chain and fixture regression smoke (2026-10-16)

Revision `8ef2fb0`, based on integration `eca037d`; `ISOLATE=t74`, training seeds **1/2/2026**, bot/random,
default branches, 1800 s cap **per round**, no PATCH, tuning or held-out seeds. The existing Lv38 F/P fixture
(`fp_arch_mage.json`, #67 seed-1 forced-F/P Henesys clear) is reused unchanged. Cache
`C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t73` is reused read-only; no import or new cache.
All **24 seed records / 26 rounds** finish with no crashes, engine/script errors or world warnings;
every round's validated setup reports `missing=[]` (headless, not a rendering lookup trace).
Original-stage and fixture outcomes/end times match #73 below exactly. Henesys reaches Magician and Mano
in all six one-off rounds; Tree's early deaths and fixture deaths before Jr. Balrog remain record-only.

| Round group / policy | Clear / dead / timeout | End seconds (seed 1 / 2 / 2026; C = clear) | Start → end levels |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8 / 812.3 / 322.7 | 1 → 41 / 28 / 10 |
| Henesys random | 1 / 2 / 0 | C974.6 / 714.8 / 329.0 | 1 → 43 / 27 / 11 |
| Tree bot | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 1 → 3 / 3 / 2 |
| Tree random | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 1 → 3 / 3 / 2 |
| Chain tier 2 bot | 0 / 1 / 0 | 685.2 / — / — | 41 → 52 |
| Chain tier 2 random | 0 / 1 / 0 | 1240.1 / — / — | 43 → 64 |
| Dark Cave fixture bot | 0 / 3 / 0 | 789.3 / 780.7 / 807.8 | 38 → 58 / 61 / 60 |
| Dark Cave fixture random | 0 / 3 / 0 | 609.5 / 595.6 / 754.0 | 38 → 51 / 50 / 55 |

**Conditional chain sample:** each policy has **1/3 tier-1 clears feeding tier 2**, seed 1 only, with a Cleric
(job230); seeds 2/2026 die in tier 1 and contribute no tier-2 death or boss observations. All six chain tier-1
records exactly equal their one-off counterparts, including choices and combat metrics. Seed 1's second-round
seed is **2260174940**, derived independently from earlier RNG consumption. Tier 2 starts/clears are **1/0** per
policy. **Lv70 reached: 0/1** per chain policy and **0/3** per fixture policy. These small conditional samples do
not assess the deferred #77 clear-rate or end-level targets. No balance changes follow the smoke.

Chain Zombie Mushmom completes in **121.75 s bot / 51.68 s random**, each **1/1 completed/spawned**, censored
median the same (**n=1, 0 unfinished**). Snack Bar has **none completed (n=0), 0/1 spawned** per policy,
censored median **>=85.20 s bot / >=640.12 s random** (**n=1, 1 unfinished** each). Jr. Balrog bot has
**none completed (n=0), 0/0 spawned**, censored median **none (n=0)** and 1 not spawned; random has
**none completed (n=0), 0/1 spawned**, censored median **>=340.12 s (n=1, 1 unfinished)**. No bosses are skipped.
Fixture boss-fight counts, completed durations and censored medians reproduce the #73 record below; none of
those six fixture rounds reaches Jr. Balrog. Exact console output, seed records and per-tier SYSTEMS JSON/logs
remain ignored under `evidence/t74/smoke/`. No visual criteria or presentation changes: screenshots are not applicable.

After fetching and merging `origin/t3/issue-32-implementation` (`eca037d`, already current), the full
`ISOLATE=t74 bash scripts/test.sh` passes **708 tests, 0 failed, 0 skipped, 79 files** (408.674 s).
All real-cache checks execute; final log: ignored `_scratch/t74-full-final.log`. Focused chain/metrics/fixture
checks pass **33 tests, 0 failed, 0 skipped**. They exercise deterministic seeded records and round seeds,
clear-only carry versus timeout, conditional/empty tier-2 samples, Lv70 reporting, selectable first stage,
the actual CLI replay and invalid flag combinations, plus fixture starting level/job/ordered loadout/mods.

#### #32 / #69 persistent-flow regression smoke (2026-10-16)

Revision `babd8ec`, including integration `eca037d` (#67/#68/#72/#73); `ISOLATE=t69`, training seeds
1/2/2026, both original stages and bot/random, 1800 s cap, default branches, no PATCH or tuning. Read #73's
completed cache `C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t73` without importing or writing it.
All 12 finish without crashes, script errors or world warnings. Outcomes, times, levels and MP-wait means exactly
match the #68 baseline below: all six Henesys runs reach Magician and spawn Mano; Tree remains record-only.

| Stage / policy | Clear / dead / timeout | End seconds (1 / 2 / 2026; C = clear) | Final levels | Mean MP-wait s/run |
|---|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8 / 812.3 / 322.7 | 41 / 28 / 10 | 205.133 |
| Henesys random | 1 / 2 / 0 | C974.6 / 714.8 / 329.0 | 43 / 27 / 11 | 178.455 |
| Tree bot | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 | 98.956 |
| Tree random | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 | 98.956 |

Ignored evidence: `evidence/t69/smoke/` holds exact console/SYSTEMS output, aggregate JSON and seed records.
The real `full` flow driver (training seed 1, default x3, hands off at 330 s) passes creation, map select,
Magician/cards, pause/resume, death (390.9 s, Lv15), results, confirmed Quit round, same-seed Continue, history
and return to title, with `missing=[]`. Checked the screenshots under `evidence/t69/full_pass/` by eye, including
the fully wrapped warning and the occupied slot after quitting. The driver fixes its diagnostic seed and forces
screenshot draws so desktop occlusion cannot hang the capture; production map selection still randomizes its seed.
The `clear` one-off scenario (seed 1, warp 900, x4) clears at 967.8 s / Lv41 Cleric and creates no driver save;
checked `clear/01_clear_notice.png` and `02_results_clear.png`. The cache-less `import` screen probe passes without
running an import. A local boundary presentation probe supplies completed summaries (not a two-round playtest),
checking tier-2-only map select, victory with two tiers, delete confirmation and victory/deleted history under
`evidence/t69/boundaries/`; its collected `missing=[]`. The full two-round scenario remains #75's work.
After the integration merge, the full `ISOLATE=t69 bash scripts/test.sh` passes **707 tests, 0 failed, 0 skipped,
78 files** (417.280 s), including every real-cache check. Log: `evidence/t69/full_suite.log`. Flow tests cover
boundary carry/refill, death/victory/history, tier filtering, Save & quit, deletion, a real first-minute fixed-tick
same-seed replay after Quit round, and save-byte preservation for fresh and supplied-character one-off rounds.

#### #32 / #68 save-model regression smoke (2026-10-16)

Revision `f55e89e`, based on integration `2b139cd`; `ISOLATE=t68`, training seeds 1/2/2026,
both existing stages and bot/random, shared real cache (read only), default branches, 1,800 s cap, no PATCH or tuning.
All 12 finish with no crashes, script errors or world warnings. Henesys reaches Magician and spawns Mano in all
six runs. Outcomes/end times, final levels, potion totals and MP-wait means exactly match the #67 smoke below;
Tree's early deaths remain record-only. No gameplay or asset changes. Exact console output, seed records and
SYSTEMS reports are ignored under `evidence/t68/smoke/`; no private cache or import was needed.

| Stage / policy | Clear / dead / timeout | End seconds (1 / 2 / 2026; C = clear) | Final levels | Mean MP-wait s/run |
|---|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8 / 812.3 / 322.7 | 41 / 28 / 10 | 205.133 |
| Henesys random | 1 / 2 / 0 | C974.6 / 714.8 / 329.0 | 43 / 27 / 11 | 178.455 |
| Tree bot | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 | 98.956 |
| Tree random | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 | 98.956 |

After fetching and merging `origin/t3/issue-32-implementation` (`2b139cd`, already current), the full
`ISOLATE=t68 bash scripts/test.sh` passes **693 tests, 0 failed, 0 skipped, 77 files** (362.055 s).
All real-cache checks execute. The 11 new save tests cover conversion, corrupt-file preservation, slot/seed
round trips, all endings/history, capacity, validation, combined round/best writes, failed-write rollback and
missing-primary recovery. Final log: ignored `_scratch/t68-full-final.log`. No visual criteria or renderer changes:
no screenshots or rendering `missing` collection were needed; balance setup reports no missing-asset errors.

#### #32 / #67 carried-character regression smoke (2026-10-16)

Revision `8a7dae5` simulation, fixture/tests `8826fe3`; `ISOLATE=t67`, training seeds 1/2/2026,
both existing stages and bot/random, real shared cache, unforced branches, 1,800 s cap, no PATCH or tuning.
All 12 finish without crashes, script errors or world warnings. Henesys reaches Magician and spawns Mano
in all six runs; outcomes/end times match the post-Teleport-rule smoke. Tree's early deaths remain unchanged
and record-only. End times below use seed order; C marks a clear, all other times are deaths.

| Stage / policy | Clear / dead / timeout | End seconds (1 / 2 / 2026) | MP collected / used | Mean MP-wait s/run |
|---|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8 / 812.3 / 322.7 | 380 / 359 | 205.133 |
| Henesys random | 1 / 2 / 0 | C974.6 / 714.8 / 329.0 | 428 / 300 | 178.455 |
| Tree bot | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 7 / 0 | 98.956 |
| Tree random | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 7 / 0 | 98.956 |

Raw records/console/system reports: ignored `evidence/t67/smoke/`. The committed fixture
`tests/fixtures/characters/fp_arch_mage.json` is actually Lv38, job210, from the seed-1 forced-F/P bot
clear at 930.1 s (all bosses dead, all choices resolved); `_doc` records the generation revision and policy.
`tools/character_fixture.gd` reproduces it without balance edits. A 15 s seed-2 one-off using that fixture,
`--character=<absolute path>`, reports `missing: []`; inspected `evidence/t67/fixture-playtest/t5.png` and
`final.png` show the character, eight skill icons, Wizard label, full HP, potion tiers/stock and new buff timers.
A separate one-second `scripts/balance.sh` flag check with spaces in the path starts at Lv38/job210,
HP stock9/MP stock19, no warnings, and correctly reports TIMEOUT. The 20-minute synthetic seed-1 event-byte
digest matches pre-change integration `bf26c5d`; resumed JSON/direct snapshots replay identically for three minutes.
After fetching/merging `origin/t3/issue-32-implementation` (already current at `bf26c5d`), the full
`ISOLATE=t67 bash scripts/test.sh` passes **676 tests, 0 failed, 0 skipped, 75 files** (313.720 s).
Real-cache checks execute; final log: ignored `_scratch/t67-full-final.log`.

#### Spec #32 / #73 bosses and #72 pending fixture checks (2026-10-16)

Report-only regression after `c50d511` merged integration `2b139cd` (#67 and #72), `ISOLATE=t73`, private cache
`C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t73`. Seeds **1/2/2026**, bot/random, 1800 s cap,
default branch choices, no PATCH, tuning candidates or held-out seeds. Original stages start fresh; Dark Cave
uses committed `fp_arch_mage.json` (its actual character is **Lv38 F/P**, job210). Encounter data was frozen
before measurement: HP x0.8/1/3; contact/attack x0.8/1/1.25; canonical attacks with 8 s per-attack cadence.
All **18 rounds** finish without crashes, script errors or world warnings. Henesys still reaches Magician and
Mano in 3/3 per policy; both original stages reproduce #72's previous smoke exactly. Tree deaths remain record-only.

| Stage / policy | Clear / dead / timeout | End seconds (seed 1 / 2 / 2026; C = clear) | Final levels |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8 / 812.3 / 322.7 | 41 / 28 / 10 |
| Henesys random | 1 / 2 / 0 | C974.6 / 714.8 / 329.0 | 43 / 27 / 11 |
| Tree bot | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 |
| Tree random | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 |
| Dark Cave fixture bot | 0 / 3 / 0 | 789.3 / 780.7 / 807.8 | 58 / 61 / 60 |
| Dark Cave fixture random | 0 / 3 / 0 | 609.5 / 595.6 / 754.0 | 51 / 50 / 55 |

Dark Cave boss fights, seconds as **min / median / max**, completed observations always shown with spawned count:
bot Zombie Mushmom **31.02 / 39.63 / 48.43 (3/3 completed/spawned)**, censored median **39.63 (n=3, 0 unfinished)**;
random **64.27 / 117.12 / 128.53 (3/3)**, censored median **117.12 (n=3, 0 unfinished)**.
Snack Bar bot completed **none (n=0), 0/3 spawned**, censored median **>=189.28 (n=3, 3 unfinished)**;
random completed **none (n=0), 0/2 spawned**, censored median **>=81.75 (n=2, 2 unfinished)**, 1 not spawned.
Jr. Balrog completed **none (n=0), 0/0 spawned**, censored median **none (n=0)**; 3 not spawned per policy.
No bosses were skipped. None of these six rounds cleared or reached the final boss, so the smoke cannot measure
Jr. Balrog's fight difficulty; its final-boss strength is the explicit highest scales/effective HP, not a tuning claim.
Dark Cave bot/random MP collected/used is **1.039 / 0.993**; MP-wait seconds/run min/median/max are
**0 / 1.67 / 7.95** and **0 / 0 / 37.20** (n=3 each). Exact console output, per-seed records and SYSTEMS aggregates
remain ignored under `evidence/t73/smoke/`; no balance adjustments followed these measurements.

**#72 pending items:** the ordinary one-off `--run=dark_cave --character=<fixture>` at seed1, x16, reaches death
at **789.283 s (13:09.3), Lv58**, with **missing=[]** and no game/world warnings. Checked by eye:
`evidence/t73/fixture-round/t60.png` (Horny/Zombie Mushrooms, flying Stirges, carried Magician and cave ladders),
`t780.png` (Tauros, Eyes/Jr. Boogies and Snack Bar) and `death_land.png`. The fixture smoke is folded into the
table above, completing the stage ticket's previously unmeasured carried-character check. An additional normal-damage
seed2026 fixture playtest fast-forwards without drawing to 780 s, then runs at x1 to death at **807.817 s, Lv60**,
missing=[] and no warnings. Checked `evidence/t73/fixture-late/t795.png` / `t805.png` by eye: both Tauromacis
and Taurospear, mixed Eyes/Boogies/Stirges and Snack Bar's beam are visible. The fast-forward does not skip sim ticks.

**#73 visuals:** checked all fourteen `<id>_<attack>_windup.png` / `_impact.png` images under
`evidence/t73/boss-attacks/`: Zombie Mushmom's slam, Snack Bar's physical hit/fire/long beam, and Jr. Balrog's
targeted fire strike, ball and slash. Separate `evidence/t73/balrog-ball/` flight/contact images show the moving
fireball and canonical hit effect. All seven probe records and the ball repeat have **missing=[]**, warnings=[];
the private import reports 0 warnings/errors. The committed debug driver uses real fixture/map/cache and attack
events, with normal waves suppressed, skill cooldowns held and god mode solely to show every attack; it is not
survival evidence. Seeded tests cover damage, admission/escape/jump/death, delayed effects, arrivals and clear
only after all bosses/reward picks finish. Type-1 targeting remains an explicit **tier-C interpretation**, not
verified v83 RE; the lead must flag that caveat on #73 (the implementer brief forbids issue comments).

After the final integration fetch/merge check (`2b139cd`, already up to date), the full isolated suite passes
**690 tests, 0 failed, 0 skipped, 77 files**; all real-cache checks execute. Output is preserved in ignored
`evidence/t73/final-full-suite.log`. The focused boss attack tests previously pass **16 tests, 0 failed, 0 skipped**.

#### Spec #32 / #72 Dark Cave stage data (2026-10-16)

The pending carried-character checks below are completed by the #73 follow-up immediately above this record.

Report-only regression started at `1d69662` (the subsequent `8a46f7d` only restores catalog order and updates tests;
no pacing or sim values change), private cache
`C:/Users/itech/Coding/maple-survivors-refs/research/spec32/cache-t72`, `ISOLATE=t72`, seeds **1/2/2026**,
both existing stages and bot/random, default branch selection, 1,800 s cap, no PATCH or tuning candidates.
All 12 runs finish without crashes, script errors or world warnings. Henesys reaches Magician and Mano in 3/3
per policy; seed 1 advances to Cleric. Results exactly match the prior post-Teleport-fix Cleric smoke recorded below
(including 967.8/974.6 s clears); Tree's existing early deaths are unchanged and record-only. No new stop gate.
Exact console output, seed records and SYSTEMS aggregates are ignored under `evidence/t72/smoke/`.

| Stage / policy | Clear / dead / timeout | End seconds (seed 1 / 2 / 2026; C = clear) | Final levels |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8 / 812.3 / 322.7 | 41 / 28 / 10 |
| Henesys random | 1 / 2 / 0 | C974.6 / 714.8 / 329.0 | 43 / 27 / 11 |
| Tree bot | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 |
| Tree random | 0 / 3 / 0 | 141.9 / 141.0 / 77.4 | 3 / 3 / 2 |

**Pending #67:** the fetched integration branch still lacks the fixture, `--character` consumer and sim snapshot
input. Therefore the carried-character Dark Cave one-off round, its early/late screenshots and the requested
Dark Cave bot/random fixture smoke are not measured. No parallel snapshot mechanism or balance substitute was
introduced. First-pass stage data remains frozen for the eventual smoke; tier-2 tuning belongs to #77.

Supplemental rendering only: an ignored debug harness uses a fresh Beginner with damage disabled, not a carried
character. It reaches the interim bossless clear at **900.0 s**, max alive **336**, `missing: []`, with no warnings.
Checked `evidence/t72/visual-probe/t60.png` by eye (cave terrain/ladders, Horny/Zombie Mushrooms, flying Stirges).
The window stopped drawing after 7:00, so a separate late-wave probe starts its clock at 13:00 and captures
`evidence/t72/late-probe.png` at 13:30: both Tauros, Curse Eyes, Jr. Boogies and Stirges render correctly;
its `missing` is also empty. These diagnostic images do not satisfy the carried-character acceptance check.

After the final integration merge check (`bf26c5d`, already up to date), the full isolated suite passes
**669 tests, 0 failed, 0 skipped, 73 files**; all real-cache checks execute. Focused stage/data/UI coverage:
**34 tests, 0 failed, 0 skipped**. Final suite output remains in `evidence/t72/final-full-suite.log`.

#### #79 combined smoke (UI tickets #82, #85, #86, #87, after review fixes) (2026-10-16)

`ISOLATE=fix79 bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`, real
cache, unforced branches, 1,800 s cap, no PATCH or tuning, on the integration tree with every #79 ticket merged plus
the review fixes. All 12 runs finish with no crashes, script errors or world warnings; the one clear has all three
scheduled bosses dead. The four `<stage>_<policy>_summary.json` files are byte-identical to the same smoke on the
integration head before the review fixes (`d13cfff`), so the fixes change no simulation. Against the #80 record
("after" column, measured before #83/#84 merged) the differences come from the gameplay merges, not the UI tickets.
Raw records: ignored `_scratch/fix79_smoke/`.

| Stage / policy | Clear/dead #80 -> now | End seconds (seed order 1/2/2026) #80 -> now | MP collected/used #80 -> now | MP-short s, mean/run #80 -> now |
|---|---|---|---|---|
| Henesys bot | 0/3 -> 0/3 | 972.8/809.1/692.8 -> 780.4/791.1/907.5 | 181/181 -> 158/158 | 154.8 -> 220.9 |
| Henesys random | 1/2 -> 1/2 | C965/468.6/538.8 -> C967.5/437.8/624.0 | 147/147 -> 168/168 | 112.8 -> 100.3 |
| Tree bot | 0/3 -> 0/3 | 639.2/638.4/128.3 -> 652.3/677.4/128.3 | 119/119 -> 136/136 | 121.5 -> 136.0 |
| Tree random | 0/3 -> 0/3 | 762.7/165.0/88.4 -> 617.5/165.0/88.4 | 116/97 -> 80/77 | 93.5 -> 93.5 |

Henesys reaches Magician in 3/3 per policy (265.4–274.7 s) and spawns Mano in 3/3; Mano completes 3/3 (bot) and
2/3 (random). Tree (record-only): 3/6 runs reach Magician (217.8–249.6 s) and Stumpy (3220000) completes in every
spawned fight (3/3); the rest die before 3:00. No stop-and-ask gate. Full isolated suite: **747 tests, 0 failed,
0 skipped, 80 files**; real-cache tests execute.

#### #80 level-up MP refill / normal MP 3% flat regression smoke (2026-10-16)

`ISOLATE=t80after3 bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
real cache, unforced branches, 1,800 s cap, game code and data at `69b8485`: level-ups refill MP to the new maximum
(HP unchanged), and normal-mob MP drops are 3% flat on every stage (owner, 2026-10-16: no per-map values; Henesys's
10% -> 4% `normal_mp_drop_chance` curve is removed). Before = `bee5ad8` with `PATCH` restoring `level_up_refill`
{hp 0, mp 0} and global normal MP 0.1, with the Henesys MP curve still in place, which behaves like base `bf26c5d`
(it reproduces the earlier records' 812.3 / 322.7 / 714.8 / 329.0 s deaths). No tuning, no held-out seeds. All 24
runs finish with no crashes, script errors or world warnings; every clear has all three scheduled bosses dead, and
none is untouched. Raw records: ignored `_scratch/t80/{before,after3}/`. An interim 5%-global measurement (Henesys
curve still active) is superseded and not reported.

| Stage / policy | Clear/dead before -> after | End seconds (seed order 1/2/2026) before -> after | MP collected/used before -> after | HP collected/used before -> after | MP-short s, mean/run before -> after |
|---|---|---|---|---|---|
| Henesys bot | 1/2 -> 0/3 | C967/812.3/322.7 -> 972.8/809.1/692.8 | 380/359 -> 181/181 | 67/76 -> 80/95 | 205.1 -> 154.8 |
| Henesys random | 1/2 -> 1/2 | C974/714.8/329.0 -> C965/468.6/538.8 | 428/300 -> 147/147 | 80/83 -> 75/77 | 178.5 -> 112.8 |
| Tree bot | 0/3 -> 0/3 | 141.9/141.0/77.4 -> 639.2/638.4/128.3 | 7/0 -> 119/119 | 4/19 -> 47/62 | 99.0 -> 121.5 |
| Tree random | 0/3 -> 0/3 | 141.9/141.0/77.4 -> 762.7/165.0/88.4 | 7/0 -> 116/97 | 4/19 -> 28/43 | 99.0 -> 93.5 |

Henesys reaches Magician (before 263.2–283.2 s, after 265.4–274.7 s) and Mano in 3/3 per policy; Mano completes
3/3 (bot) and 2/3 (random), was 2/3 each. MP potions collected roughly halve (bot) or fall to a third (random), and
every Henesys run now drinks every Blue it picks up (collected = used); the full pool at each level-up still cuts
MP-short time by a quarter (bot) to a third (random). Seed 2026 no longer dies at 5:22–5:29 just after Mano (now
11:32 / 8:58), but random seed 2 dies earlier (7:48, was 11:54) and seed-1 bot dies at 16:12 instead of clearing.
Tree (record-only, awaiting the owner's rework): the refill keeps the Beginner's Three Snails firing, so 3/6 runs
now reach Magician (217.8–249.6 s) and fight Stumpy (3220000; 2/3 spawned fights completed), dying at 10:38–12:42;
the rest still die before 3:00. No stop-and-ask gate: no group dies entirely before its first boss or clears
untouched. The Henesys sensible clear rate falling 1/3 -> 0/3 is input for the balance pass, not tuned here.
Measured on the ticket branch before #83 (boss priority) and #84 (Forking Storm) merged; neither is in these runs.
After merging integration (with #83/#84) the full isolated suite passes **672 tests, 0 failed, 0 skipped, 73 files**;
real-cache tests execute.

#### #84 Forking Storm regression smoke (2026-10-16)

`ISOLATE=t84 bash scripts/balance.sh 1 2 2026`, both stages, `bot` and `random`, unforced branches, real cache,
1,800 s cap, no PATCH or tuning. All 12 runs finish with no crashes, script errors or world warnings. Outcomes and
end times match the #56 smoke and the post-Teleport-fix rows: no unforced run picks 220 (seed 1 goes 230, seeds
2/2026 die before second job), so the unforced smoke cannot see the new card. Henesys reaches Magician and Mano
in 3/3 per policy; Tree's early deaths are unchanged and record-only.

| #84 stage / policy | Clear / dead / timeout | End seconds (seed order 1/2/2026; C = clear) | Magician / first-boss reaches |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | C967.8, 812.3, 322.7 | 3/3 / 3/3 |
| Henesys random | 1 / 2 / 0 | C974.6, 714.8, 329.0 | 3/3 / 3/3 |
| Tree bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 / 0/3 |
| Tree random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 / 0/3 |

Supplementary Henesys `--branch=220` (same seeds, both policies), compared with the post-Teleport-fix 220 rows:
bot 0/3 clears, 1079.7/812.3/322.7 s (before 1081.9/812.3/322.7), seed 1 took Forking Storm 3/3 steps and
blinked 69 times (before 68); random 1/3 clears, C1003.0/714.8/329.0 (before C1003.4), seed 1 took 1 step.
Only seed 1 reaches second job, so this is n=1 per policy and not balance evidence. No stop-and-ask gate. Raw
records stay ignored under `_scratch/smoke84/`. Full isolated suite: **665 tests, 0 failed, 0 skipped, 72 files**;
real-cache tests execute.

#### #83 boss target priority regression smoke (2026-10-16)

`ISOLATE=t83 bash scripts/balance.sh 1 2 2026`, both stages, `bot`/`random`, real cache, unforced branches, 1,800 s
cap, no PATCH or tuning. "Before" is the same command on integration base `bf26c5d` (`ISOLATE=t83base`); its
Henesys end times reproduce the 230 rows of the post-Teleport-fix smoke below (seed 1 takes branch 230). All 24 runs finish without crashes,
script errors or world warnings. Records/console output are ignored under `_scratch/t83_smoke/{base,after}/`.

| Henesys policy | Outcome by seed 1/2/2026, before -> after | Completed fight seconds Mano 2220000 / 6130101 / 9400205, before -> after |
|---|---|---|
| bot | C16:07/D13:32/D5:22 -> C15:57/D15:13/D5:48 | 47.5, 27.6 / 31.1 / 67.8 -> 36.9, 31.5 / 36.7 / 57.7 |
| random | C16:14/D11:54/D5:29 -> C15:35/D10:38/D5:29 | 24.2, 43.2 / 20.9 / 74.6 -> 24.9, 61.7 / 39.0 / 35.7 |

Completed counts are unchanged (Mano 2/3 spawned; 6130101 1/2; 9400205 bot 1/1 -> 1/2 because seed 2 now lives
past 15:00, random 1/1); medians on n <= 2 are noise-level and mixed in direction (bot Mano 37.55 -> 34.18 s,
random 33.69 -> 43.28 s; the final boss is faster in both seed-1 clears). Clears stay 1/3 per policy, each with
every scheduled boss dead and hits taken; Henesys reaches Magician in 6/6 (unchanged 263-283 s) and spawns Mano.
Tree is identical before/after (deaths 2:21/2:21/1:17, no boss spawned; record-only). Boss-free play is unchanged:
Henesys Lv8/Lv10/Magician times match in all 6 pairs and Tree runs match in deaths, kills, potions and MP-short;
runs diverge only after the first boss spawns. No stop gate.

#### #31 / #61 second-job QA (2026-10-15)

Report only on integration `34c04e1`: `ISOLATE=t61 bash scripts/balance.sh 1 2 2026`, forced branches
210/220/230, both stages and bot/random, rarity active, real cache, 800x600, 1,800 s cap, no patches/tuning.
All 36 runs finish without crashes, script errors or world warnings. Per-seed records, exact console output,
systems reports and screenshots remain ignored under `evidence/spec31_qa/<branch>/`. Detailed milestones,
completed/censored boss durations and counts, potions, MP waits and cards by job/tier are in the draft
`research/spec31/qa-61.md`; the separate follow-up draft is `qa-61-defects.md` (external spec31 research folder).

| Henesys branch / policy | Clear / dead / timeout | Death seconds (seed order) | Lv at 15:00 (observed n) | HP collected/used; MP collected/used | MP-short seconds, mean/run |
|---|---|---|---|---|---|
| 210 bot | 0 / 3 / 0 | 949.7, 812.3, 322.7 | 35 (n=1) | 58/73; 360/360 | 260.5 |
| 210 random | 1 / 2 / 0 | 714.8, 329.0 | 43 (n=1) | 79/81; 435/335 | 178.5 |
| 220 bot | 0 / 3 / 0 | 926.5, 812.3, 322.7 | 35 (n=1) | 57/72; 359/359 | 252.6 |
| 220 random | 1 / 2 / 0 | 714.8, 329.0 | 42 (n=1) | 80/83; 433/310 | 178.5 |
| 230 bot | 0 / 3 / 0 | 920.2, 812.3, 322.7 | 35 (n=1) | 57/72; 363/363 | 246.1 |
| 230 random | 1 / 2 / 0 | 714.8, 329.0 | 42 (n=1) | 80/83; 428/300 | 178.5 |

Henesys reaches Magician/Mano in 3/3 per group. Lv10: bot 270.6–283.2 s, random 263.2–278.3 s (n=3);
only seed 1 reaches Lv30, at 614.9 / 557.8 s (n=1). Completed Mano medians: 37.55 / 33.69 s (2/3 spawned;
censored >=27.62 / >=29.00 s, n=3). Final boss: bot none (0/1 spawned each); random 37.70/103.35/74.55 s
for 210/220/230 (1/1 spawned each). Earlier deaths and missing 15:00 samples are not zero observations.

| Tree branch / policy | Clear / dead / timeout | Death seconds (seed order) | Lv at 15:00 (observed n) | HP collected/used; MP collected/used | MP-short seconds, mean/run |
|---|---|---|---|---|---|
| 210 bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 210 random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 220 bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 220 random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 230 bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |
| 230 random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | none (n=0) | 4/19; 7/0 | 99.0 |

Tree matches the prior smoke: no Magician/Lv10/Lv30 reaches or bosses (completed durations none, n=0).
Henesys picked tiers N/R/E/U/L, branch order: bot 60/16/0/1/0, 62/14/0/1/0, 61/15/0/1/0; random
60/21/6/0/0, 59/21/6/0/0, 59/21/6/0/0. Tree: 4/1/0/0/0 per group. Counts mean picks, not rank steps.

**Teleport MP starvation:** seed-1 bots learn rank-1 Teleport at 614.93 s and use it 257/263/298 times;
MP-short totals are 310.733/286.950/267.550 s, with 49.6%/45.7%/40.3% of post-learning ticks short.
Non-learners (seeds 2/2026) use zero and wait 276.450/194.383 s over shorter lives. Observer-only replays
exactly match the official seed-1 outcomes/cards/skills/milestones/potions/fights. Separate matched diagnostics
suppress only Teleport input: F/P/Cleric clear at 989.4/971.9 s with zero post-learning MP shortage; I/L dies
later at 1163.8 s with fewer shortages. These are diagnostic policies, not extra smoke observations or tuning.
The #60 bot-clear drift persists (0/3 per branch versus earlier 1/3); autoplay MP use is a drafted follow-up.

**Owner stop-and-ask gate:** no Henesys branch dies entirely before its first boss or clears untouched.
Tree's all-before-first-boss pattern is present in all 18 runs, but unchanged, before second job, and remains
AGENTS.md's explicit record-only owner rework; flagged in the draft comment. No new feature-induced gate.
Close probes check every branch skill, real advancement cards, stacked buffs, Teleport endpoints/grey X icon,
and all 15 HUD icons fitting two rows at 800x600; all report `missing: []`. No confirmed blocking defect.
All configured Use sounds load; audible identity/mix needs human listening, so audio acceptance is unverified.
Full isolated suite: **656 tests, 0 failed, 0 skipped, 71 files** (299.020 s); real-cache tests execute.
Normal seed-1 playtests (`--warp=540 --speed=8 --window-autopick=1`, 18-minute absolute cap) reach real
advancement windows and die at 949.733/926.483/920.233 s (210/220/230), Lv35 each, all `missing: []`;
checked advancement cards, the final-boss/MP views and final tombstones under each branch’s `playtest/`.

**After the bot Teleport rule fix (#60 follow-up, 2026-10-15):** one Henesys-only 18-run smoke on `574da80`,
`ISOLATE=bott bash scripts/balance.sh 1 2 2026 --stage=henesys_hg1 --branch=<210|220|230> --policy=<bot|random>`,
real cache, rarity active, 1,800 s cap, no PATCH. The reserve (max of 25% max MP and two most-expensive learned
auto-attack costs), 5 s interval and tighter same-height emergency rule were chosen and committed before measurement;
no values were iterated. Player Teleport, costs and all game data are unchanged. Tree was excluded by the follow-up
brief because no smoke run reaches second job there. Records, exact console output and systems summaries remain
ignored under `evidence/bot_teleport/<branch>/<policy>/`; `teleports` counts successful arrival events, once per blink.

Below, before is QA #61 above; lists use seed order 1/2/2026. C = clear (time shown for new bot clears), other end
times are deaths; no timeouts. MP-short is the whole-run mean, so different lifetimes remain a comparison limit.

| Henesys branch / policy | Clear/dead before -> after | End seconds before -> after | MP-short seconds, mean/run before -> after | Teleports before -> after |
|---|---|---|---|---|
| 210 bot | 0/3 -> 1/2 | 949.7/812.3/322.7 -> C930.1/812.3/322.7 | 260.5 -> 205.1 | 257/0/0 -> 58/0/0 |
| 210 random | 1/2 -> 1/2 | C/714.8/329.0 -> C/714.8/329.0 | 178.5 -> 178.5 | unmeasured -> 0/0/0 |
| 220 bot | 0/3 -> 0/3 | 926.5/812.3/322.7 -> 1081.9/812.3/322.7 | 252.6 -> 231.5 | 263/0/0 -> 68/0/0 |
| 220 random | 1/2 -> 1/2 | C/714.8/329.0 -> C/714.8/329.0 | 178.5 -> 178.5 | unmeasured -> 0/0/0 |
| 230 bot | 0/3 -> 1/2 | 920.2/812.3/322.7 -> C967.8/812.3/322.7 | 246.1 -> 205.1 | 298/0/0 -> 66/0/0 |
| 230 random | 1/2 -> 1/2 | C/714.8/329.0 -> C/714.8/329.0 | 178.5 -> 178.5 | unmeasured -> 0/0/0 |

Bot seed-1 MP-short totals: 310.733/286.950/267.550 -> 144.567/223.583/144.567 s (branch order 210/220/230).
Bot seeds 2/2026 remain 276.450/194.383 s; all random groups remain 155.733/179.050/200.583 s in seed order
(QA's rounded 155.7/179.1/200.6). Random seed-1 clears occur at 937.7/1003.4/974.6 s by branch.
All 18 runs reach Magician and spawn Mano, all clears have every scheduled boss dead, and none clears untouched.
No crashes, script errors or world warnings; no new stop gate. The bot still uses Teleport, with far fewer blinks
and less total MP wait on the three learners; I/L still dies. This is fixed-seed regression evidence, not balance
tuning. Pre-merge isolated suite: **661 tests, 0 failed, 0 skipped, 72 files**; real-cache tests execute.
After merging integration `84d1782` (review-fix ownership refactors; both records preserved), the full
`ISOLATE=bott bash scripts/test.sh` suite passes **663 tests, 0 failed, 0 skipped, 72 files**. The smoke above
remains the single measurement on `574da80`; no additional smoke or outcome-driven changes followed the merge.

#### Spec #31 review-fix equivalence (2026-10-15)

Behaviour-preserving ownership refactors, baseline `34c04e1`: Slow history/admission/application and relocation
live in MobSwarm; box/nearest instant casts share their capped line resolver; MP Eater reads `absorb_mp` definitions
in learned order (section 7). No tuning. Ran `ISOLATE=rfix bash scripts/balance.sh 1 2 2026
--stage=henesys_hg1 --policy=bot --branch=<210|220|230>` before and after, with separate absolute `BALANCE_OUT`
directories under `_scratch/spec31-review-fixes/{before,after}/<branch>`. All nine complete JSON records were
byte-identical, including outcomes, end times, levels, kills and every boss spawn/death/duration/elapsed field;
no crashes or world warnings. Values below are identical before/after: outcome / end seconds / level / kills.

| Forced branch | Seed 1 | Seed 2 | Seed 2026 |
|---|---|---|---|
| 210 | DEAD / 949.7 / 35 / 2204 | DEAD / 812.3 / 28 / 1399 | DEAD / 322.7 / 10 / 153 |
| 220 | DEAD / 926.5 / 35 / 2138 | DEAD / 812.3 / 28 / 1399 | DEAD / 322.7 / 10 / 153 |
| 230 | DEAD / 920.2 / 35 / 2220 | DEAD / 812.3 / 28 / 1399 | DEAD / 322.7 / 10 / 153 |

Only seed 1 reaches the forced second job; seeds 2/2026 end as Magician. These card picks do not learn Slow or
MP Eater. Focused seeded support/skill-foundation/MP Eater tests cover Slow's consecutive-use history across
relocation and fresh spawns, lethal-line hit order/RNG, and live-rank absorption with configured fields/learned
order: 43 passed, 0 failed, 0 SKIP. The full `ISOLATE=rfix bash scripts/test.sh` suite passed: 658 passed,
0 failed, 0 SKIP across 71 files. Raw records/logs and the field-by-field comparison remain in ignored scratch.

#### #30 / #45: rarity tiers, coarse C46 stage data (2026-10-15)

Rarity tiers were calibrated on training seeds 1–60 and 2026 to the C46 profile: card weights 86/8/3.5/1.7/0.8,
the older 1/1/2/3/max stacking and 1/1/2/3/5 new-skill ladders, and the Henesys late HP multipliers, HP support and
ordinary MP taper in the 4.1 table. The owner accepted that state for the current features, then restored the spec
weights **75/18/5/1.7/0.3** and a ladder in which every tier gives more than the one below (section 8.1). The stage
data stays C46 and is **not re-tuned** for those changes: feature tickets now run a regression smoke only, and tuning
waits for the dedicated balance pass (AGENTS.md "Balance"). The C46 figures below therefore describe the measured
C46 weights, not the shipped odds.

| C46 (86/8/3.5/1.7/0.8 weights) | Sensible clears | Sensible death median | Careless clears | MP collected / used |
|---|---|---|---|---|
| Training 1–60 + 2026 | 32/61 (52.46%) | 902.3 s (29 deaths) | 4/61 (6.56%) | 1.21 sensible / 1.25 careless |
| Held-out 601–630 (consumed) | 19/30 (63.33%) | 943 s (11 deaths) | 4/30 (13.33%) | 1.30 sensible / 1.36 careless |

Sensible clears exceed the 40–50% band (slightly in training, clearly held out); the careless late MP-wait requirement was observed in 7/41 training
and 0/16 held-out runs. These are known deviations for the balance pass. A short summary of the C46 search and how
to reproduce it is in [research/spec30-rarity-balance.md](research/spec30-rarity-balance.md).

Regression smoke after the owner's changes (spec odds, new ladder, untouched C46 stage data), 2026-10-15, seeds
1/2/2026, compared with the same seeds on the C46 PR head. No crashes or world warnings. Full suite on the final head: 571 tests, 0 failed, 0 skipped.

| Stage / policy | Clears (now) | Deaths (now) | Clears (C46) | Deaths (C46) |
|---|---|---|---|---|
| Henesys sensible | 1/3 | 5:28, 15:31 | 1/3 | 12:36, 15:36 |
| Henesys careless | 2/3 | 12:25 | 0/3 | 10:28, 12:03, 12:19 |
| Tree, either policy | 0/3 | 1:17, 2:21, 2:21 | 0/3 | 1:17, 2:10, 2:21 |

Henesys still reaches Magician at 4:23–4:43 and Lv 30 near 9–10:30; MP collected/used 1.17 sensible, 1.40 careless.
Tiers offered (Normal/Rare/Epic/Unique/Legendary) over three runs: sensible 182/63/12/1/0, careless 289/72/9/3/2.
Careless play is easier than under C46, as expected from the restored odds; this is input for the balance pass,
not a tuning target. Tree deaths before 2:30 are unchanged from C46 (Tree awaits the owner's rework).

#### #31 / #58 support regression smoke (2026-10-15)

`ISOLATE=t58 bash scripts/balance.sh 1 2 2026`, both stages and `bot`/`random`, real cache, unforced branches,
1,800 s cap, no patches/tuning. All 12 runs finish without crashes, script errors or world warnings. Outcomes and
death times match #56 below; Henesys reaches Magician and spawns its first boss in all six runs. Tree is unchanged
and record-only. Raw records and exact console output are ignored under `_scratch/t58-balance/` and
`_scratch/t58-balance-*.log`. The full second-job branch smoke remains #61's responsibility.

| #58 stage / policy | Clear / dead / timeout | Death seconds | MP collected / used | Mean MP-wait seconds/run |
|---|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | 812.3, 322.7 | 376 / 317 (1.186) | 205.1 |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 425 / 269 (1.580) | 178.5 |
| Tree bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 7 / 0 (undefined) | 99.0 |
| Tree random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 7 / 0 (undefined) | 99.0 |

Visible seed-1 playtests on branches 210/220/230 use `--warp=840 --speed=8 --minutes=16`, saved under
`evidence/t58/branch_<id>/`; all report `missing: []` and remain PLAYING at the cap (no clear claimed).
Checked by eye: `branch_210/t890.png` (late-game rendering), `branch_230/t950.png` (Invincible buff row).
Temporary real-cache RunScene probes learn only this ticket's support skills at rank 20. Inspected
`focus_210/support_8.png` and `focus_220/support_25.png` show Meditation's icon/cast art; each probe records six
slowed mobs at speed factor 0.6. Closer `close_210/support_115.png` and `close_220/support_100.png` show Slow's
white monster rings without damage numbers; `focus_230/support_25.png` shows Bless and Invincible icons with
separate timers and canonical cast art. Probe summaries also report `missing: []`. No cache nodes are missing.
`evidence/t58/cards/cards.png` was checked for readable, fitting Bless/Invincible/Slow rank previews and the
accuracy-without-combat-effect label. After merging integration at `f8af37b`, the full isolated suite passes
**610 tests, 0 failed, 0 skipped, 67 files** (300.672 s); the real-cache tests execute. Focused support,
advancement and data checks pass **36 tests, 0 failed, 0 skipped**. No held-out seeds or tuning were used.

#### #60 Teleport regression smoke (2026-10-15)

No tuning: ISOLATE=t60, training seeds 1/2/2026, both stages and bot/random, 800 x 600, 1,800 s cap,
unforced branches, no patch. All 12 records completed without crashes, script errors or world warnings. Henesys
reaches Magician and spawns Mano in 3/3 for each policy. Compared with Foundations, sensible clears fall 1/3 to 0/3
(seed 1 now dies at 955.3 s with Cleric Teleport rank 13); random remains 1/3. Earlier deaths and Tree outcomes
are unchanged. This is feature drift for #61, not a tuning pass; no held-out seeds were used.

| Stage / policy (3 runs each) | Clear / dead / timeout | Death seconds | Magician reaches | MP collected / used | MP-wait median (n=3) |
|---|---|---|---|---|---|
| Henesys bot | 0 / 3 / 0 | 955.3, 812.3, 322.7 | 3/3 | 365/365 (1.000) | 225.200 s |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 3/3 | 419/419 (1.000) | 179.050 s |
| Tree bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 | 7/0 (undefined) | 117.217 s |
| Tree random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 | 7/0 (undefined) | 117.217 s |

Raw records and regenerated absolute-path systems reports: ignored _scratch/t60_balance/; console output:
_scratch/t60-smoke-*.log. The initial relative BALANCE_OUT reached all runs but the supplemental reporter could
not locate those paths from its project directory; reports were regenerated from the same records, without reruns.
The branch-210 seed-1 playtest (warp 480, speed 8, cap 780 s) reaches Lv35, remains PLAYING, and reports missing: [].
Its inspected evidence/t60/playtest_fp_seed1/t780.png shows the late run; this bot did not learn Teleport.
The close driver learns Teleport through its card and injects X. Inspected evidence/t60/close_fp/teleport.png
and teleport_no_mp.png show the X icon and affordability tint. Its missing list contains only
Effect.wz/BasicEff.img/Teleport: that canonical subtree is absent from the shared cache. The manifest now requests
it, but #60 did not run the prohibited import. The effect-frame test explicitly SKIPs while this prerequisite is
missing; that SKIP does not verify the effect. Canonical effect visual acceptance remains unverified pending import.
This smoke was recorded before the #56 merge; its unforced second advancements are Cleric, so it does not assess
I/L branch pacing. After merging #56 and preserving both sets of fixtures/data, the final full suite reports
**612 tests: 611 passed, 0 failed, 1 skipped (67 files)**. The only SKIP is
`test_teleport::test_real_cache_teleport_effect_frames`, for that missing canonical art. Final log:
`_scratch/t60-full-merged-final.log`; focused Teleport/advancement/I-L/data checks: 48 tests, 0 failed, 1 same SKIP.

**#60 effect-import follow-up (2026-10-15):** the owner authorized one import. A fresh original-v83
dump confirms `Effect.wz/BasicEff.img/Teleport`, four 80 ms frames (tier A; dimensions/origins recorded
in `docs/research/wz-inventory.md` section 7). The ticket manifest already selected that subtree.
The incremental import reports 84 imgs: 1 written, 83 up to date; 10,800 canvases (+4), 87 pages,
131 sounds, 112,434,965 bytes; 0 warnings, errors or unresolved UOLs. All 84 prior img entries and
prior BasicEff subtrees remain present; only `Teleport` was added. Of 319 prior cache files, only
BasicEff JSON/atlas and cache.json changed; none were removed. Evidence: `evidence/t60/import.log`
and `cache-*-comparison.json`.

The close real-map driver learns `teleport_fp` through its card and injects X: departure
(1200, 37.6531), arrival (1330, 95). Inspected `evidence/t60/close_fp_imported/teleport.png` shows
both blue endpoint effects and the X skill label; `teleport_no_mp.png` shows the grey unaffordable
icon at 0 MP. Its summary reports `missing: []`, resolving the earlier visual-acceptance gap.
The additional normal autoplay playtest (Henesys, seed 1, branch 230, warp 930, speed 8, cap 990 s)
ends DEAD at 955.35 s, level 36, Teleport rank 13, `missing: []`; records are in
`evidence/t60/playtest_cleric_imported/`. No gameplay or balance data changed, so the prior smoke
was not repeated. The real-cache effect test now fails rather than SKIPs when a present cache lacks
this required animation; focused Teleport checks pass 16/16, with no failures or SKIPs.
After `git merge origin/t3/issue-31-implementation` (already up to date), the full
`ISOLATE=t60 bash scripts/test.sh` passes **612/612 tests, 0 failed, 0 skipped, 67 files**
in 279.597 s. Log: `_scratch/t60-full-imported.log`.

#### #31 / #56 Ice/Lightning regression smoke (2026-10-15)

`ISOLATE=t56`, training seeds 1/2/2026, both stages and `bot`/`random`, unforced branches, real cache,
1,800 s cap, no patches or tuning. All 12 runs finish without crashes, script errors or world warnings.
Outcomes and death times match the Foundations/#53 smoke below. Henesys reaches Magician and spawns its first
boss in all six runs; Tree's early deaths remain record-only. The two second advancements in this fixed sample
choose 230, so this is an existing-run regression check; #61 owns the full second-job branch smoke.
Raw records and exact console output remain ignored under `_scratch/t56_smoke/` and `_scratch/t56_smoke_*.log`.

| #56 stage / policy | Clear / dead / timeout | Death seconds | Magician / first-boss reaches |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | 812.3, 322.7 | 3/3 / 3/3 |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 3/3 / 3/3 |
| Tree bot | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 / 0/3 |
| Tree random | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0/3 / 0/3 |

A separate visible Henesys run uses `--branch=220 --seed=1 --warp=480 --speed=8 --minutes=20 --shot-every=1`.
It clears at 996.567 s, Lv39, with Cold Beam and Thunder Bolt both at rank 9 and `missing: []`.
Checked by eye: `evidence/t56/branch220/t700.png` (Cold Beam's ice impact) and `t740.png` (Thunder Bolt's
lightning columns on both sides, with ice impacts also visible). Both skills' cached use sounds and art load
in the real-cache test, and the normal RunScene cast path plays those sounds; no missing cache nodes found.
After merging the current integration branch, the full suite passes **599 tests, 0 failed, 0 skipped, 66 files**
(312.975 s). Focused Ice/Lightning, advancement and data-file validation passes **32 tests, 0 failed, 0 skipped**;
the real-cache test executes, so no SKIP is counted as coverage. No shared simulation or presentation paths change.

#### #55 Fire/Poison attack regression smoke (2026-10-15)

`ISOLATE=t55 bash scripts/balance.sh 1 2 2026`, both stages and `bot`/`random`, unforced branches,
no patches or tuning: all 12 records completed with no crashes, script errors or world warnings. Outcomes,
death times and potion totals match the preceding #53/foundations smoke. Henesys reaches Magician and the first
boss in 3/3 runs per policy. Each policy's surviving seed 1 selects Cleric (230); the other seeds die before
second job, so this smoke establishes regression safety, not Fire/Poison balance. Tree remains record-only.
Exact console output and JSON records stay in ignored `_scratch/t55/balance/` and `evidence/t55/`.
After fetching/merging the integration branch (already up to date), the final full suite passes **599 tests,
0 failed, 0 skipped, 66 files**; focused F/P, data-file and upgrade checks pass **42 tests, 0 failed, 0 skipped**.
The shared synthetic book now includes a separate Poison Breath fixture; the existing pity regression exhausts
all current-job power cards instead of assuming Fire Arrow's rank cap exhausts the whole F/P attack pool.

| #55 stage / policy | Clear / dead / timeout | Death seconds | MP collected / used |
|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | 812.3, 322.7 | 376/315 (1.194) |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 426/268 (1.590) |
| Tree bot / random (each) | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 7/0 (undefined) |

The separate forced-210 seed-1 visual run (warp 480 s, speed 8) clears at 919.933 s with Fire Arrow rank 14,
Poison Breath rank 9 and `missing: []`. `evidence/t55/playtest_210_s1/t646.png` shows Fire Arrow's projectile
and caster effect. A temporary real Flow/RunScene driver stages each attack alone against a durable stationary
mob for closer inspection; its screenshots and sound/asset counters stay in `evidence/t55/focused_visuals/`.
Checked by eye: `poison_breath_03.png` (green orb and caster effect), `poison_breath_05.png` (expanding green hit
cloud on the pig), and `fire_arrow_03.png` (caster bow/fire effect and impact). Both staged summaries have empty
missing lists and successful sound calls; the cached Use/Hit streams also decode in the focused test.
This is visual evidence only, not a balance run. The initial occluded playtest attempt produced no screenshots;
the successful run uses Godot's always-on-top window option. No importer or shared cache changes were needed.

#### Spec #31 foundations smoke

Foundations for spec #31 regression smoke (2026-10-15), `ISOLATE=found`, training seeds 1/2/2026,
both stages and `bot`/`random`, no patches/tuning, repeated after merging #53 at `a248aba`. All 12 final records
completed without crashes or world warnings; outcomes and death times match #53's smoke below. Henesys reaches
Magician in all six runs and spawns its first boss in all six; Tree's unchanged early deaths remain recorded only.
Foundations adds no second-job skill/card data. Final raw records/console output remain under ignored
`_scratch/foundations_balance_merged/`; the preliminary pre-#53 smoke in `_scratch/foundations_balance/`
matched the preceding current-odds results. Full merged suite: **592 tests, 0 failed, 0 skipped** (65 files).

| Foundations stage / policy | Clears | Deaths | Magician reaches | MP collected / used |
|---|---|---|---|---|
| Henesys bot | 1/3 | 5:22, 13:32 | 3/3 (4:30–4:43) | 376/315 (1.194) |
| Henesys random | 1/3 | 5:29, 11:54 | 3/3 (4:23–4:38) | 426/268 (1.590) |
| Tree bot / random (each) | 0/3 | 1:17, 2:21, 2:21 | 0/3 | 7/0 (undefined) |

Restoration presentation was triggered through the real Flow/RunScene with a temporary evidence driver;
`evidence/foundations/gain_numbers.png` was checked by eye (HP/MP digits, placement and stacking; missing assets
empty). Synthetic seam and cached gain-number tests: 15 tests, 0 failed, 0 skipped.
The existing all-event schema test needed one new restoration scenario (and `stat` String validation) because it
requires every `EVENT_FIELDS` entry to be exercised. Its previous assertions and scenarios are unchanged.

#### #31 / #59 MP Eater regression smoke (2026-10-15)

No tuning: `ISOLATE=t59 bash scripts/balance.sh 1 2 2026`, both stages and `bot`/`random`, real cache,
unforced seeded branches, no patch, 1,800 s cap. Feature head `24ff1be` includes Foundations `e51d6b7`;
this smoke precedes later sibling-ticket integration. All 12 runs completed without crashes, script errors or
world warnings. Outcomes and death times match the Foundations smoke: Henesys reaches Magician and the first
boss in all six runs (Magician 263.2–283.2 s). Tree remains record-only and unchanged. No held-out seeds were used.

| MP Eater stage / policy | Clear / dead / timeout | Death seconds | MP collected / used | Foundations MP collected / used |
|---|---|---|---|---|
| Henesys bot | 1 / 2 / 0 | 812.3, 322.7 | 378/314 (1.204) | 376/315 (1.194) |
| Henesys random | 1 / 2 / 0 | 714.8, 329.0 | 430/214 (2.009) | 426/268 (1.590) |
| Tree bot / random (each) | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 7/0 (undefined) | 7/0 (undefined) |

Each surviving Henesys seed-1 run advances to Cleric and learns MP Eater; the other seeds die before second job.
Bot seed 1 clears at 1087.7 s and random seed 1 at 998.2 s. The changed MP collection/use ratio is feature
evidence for #61 and the later balance pass, not a tuning result. Raw records and console output stay in ignored
`_scratch/t59_balance/` and `_scratch/t59-smoke-*.log`. Windowed playtests forced 210 and 230 (seed 1, warp 480,
speed 8); both have `missing=[]`. F/P clears at 995.2 s without learning MP Eater; Cleric owns rank 17 and is
still PLAYING at the 18-minute cap (not a clear). Checked-by-eye evidence: `evidence/t59/branch230/mp_eater.png`
and the focused real-hit captures `evidence/t59/focused/mp_eater_{fp,il,cleric}.png`: canonical absorb art and cyan
14-MP gain numbers for every branch, all `missing=[]`. v83 has no MP Eater sound entry; no required cache data is missing.
After merging integration `f8af37b` (I/L attacks) and retaining both tickets' data/fixtures, the final
`ISOLATE=t59 bash scripts/test.sh` passes **616 tests, 0 failed, 0 skipped** (67 files); no cache checks skipped.

#### #31 / #53 advancement regression smoke (2026-10-15)

No balance tuning. `ISOLATE=t53 bash scripts/balance.sh 1 2 2026` ran on both stages with both policies,
with the real cache, 800 x 600 view, 1,800 s cap, no patch and unforced seeded branches. No crashes, script errors
or world warnings. Henesys reaches Magician and the first boss in 3/3 for each policy; Lv30 in 1/3 for each.
Compared with the preceding current-odds smoke, sensible clears remain 1/3 and careless clears fall from 2/3 to 1/3.
Tree is record-only and unchanged. Branch 0 means no second advancement yet.

| Stage / policy | Clear / dead / timeout | Death seconds | Branch counts | Previous clears |
|---|---|---|---|---|
| Henesys sensible | 1 / 2 / 0 | 812.3, 322.7 | 230: 1; 0: 2 | 1/3 |
| Henesys careless | 1 / 2 / 0 | 714.8, 329.0 | 230: 1; 0: 2 | 2/3 |
| Tree sensible | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0: 3 | 0/3 |
| Tree careless | 0 / 3 / 0 | 141.9, 141.0, 77.4 | 0: 3 | 0/3 |

The requested Henesys drift sample (training 1-6 and 2026) clears 5/7 sensible and 1/7 careless; Lv10 medians
270.7 s (7/7) and 277.6 s (5/7), conditional Lv30 medians 574.6 s (5/7) and 561.55 s (2/7). The owner-requested
external `drift-53.md` preserves per-seed results and comparisons with #42's published frozen C21 training and
held-out figures; the superseded opening, rarity changes and different cohorts prevent attributing that historical
difference to #53 alone. No held-out seeds were run and no data were retuned. A visible seed-1 run forced 210,
cleared with `missing: []`, and its inspected `evidence/t53/job_window/window_job_30.png` shows all three branches selectable.

#### #31 / #57 Cleric attacks regression smoke (2026-10-15)

No tuning. Seeds 1/2/2026, both stages, bot/random policies, real cache, 800 × 600, 1,800 s cap,
unforced seeded branches, `ISOLATE=t57`, no patch. All 12 records have empty world warnings; no crashes or
script errors. Henesys reaches Magician and the first boss in 3/3 per policy, and Cleric in 1/3 per policy.
Clear counts and death times match the preceding #53 smoke; Tree remains record-only.
After merging #56's integration changes and retaining both skill families, the full `ISOLATE=t57` suite passed
**608 tests, 0 failed, 0 skipped, 67 files** in 297.667 s. No SKIP is counted as coverage.

| Stage / policy | Clear / dead / timeout | Death seconds | Cleric clear / skill ranks |
|---|---|---|---|
| Henesys sensible | 1 / 2 / 0 | 812.3, 322.7 | 1008.5 s; Holy Arrow 8, Heal 14 |
| Henesys careless | 1 / 2 / 0 | 714.8, 329.0 | 962.7 s; Holy Arrow 8, Heal 8 |
| Tree sensible | 0 / 3 / 0 | 141.9, 141.0, 77.4 | no second advancement |
| Tree careless | 0 / 3 / 0 | 141.9, 141.0, 77.4 | no second advancement |

Logs/records and systems aggregates are ignored under `_scratch/t57_smoke/`. The first sensible report invocation
used relative record paths and failed to open them; the report was rerun successfully with absolute paths, without
replaying or changing the runs. The visible seed-1 forced-230 playtest cleared at 1008.5 s, `missing: []`.
Inspected `evidence/t57/cleric_s1/t700.png` and `t938.png` show Holy Arrow; the focused controlled RunScene captures
`evidence/t57/focused/heal_gain.png` and `holy_arrow_flight.png` expose Heal's rising art/blue HP gain and the arrow
without crowd occlusion. Both use the actual cache and sounds; the focused summary also has no missing assets.
The seed-2026 attempt ended before its 480 s warp target and the existing warp path did not finish the dead run;
it was stopped and replaced by seed 1. Exact v83 recovery remains unverified, as detailed in the #57 research note.

#### Owner review of #51: vanilla skills and the v83 opening (historical coarse pass)


The owner rejected the C21 profile's survivor projectile coverage and opening pool: every skill starts as its vanilla
v83 form (one Three Snails shell, one Energy Bolt; more only from cards, later rarity) and the opening pool stays the
v83 Beginner's 5 MP with no starter Blues. With canonical MP costs a Beginner then casts Three Snails about once per
10 s regeneration pulse, so C21's data killed all twelve 1..12 sensible runs before 1:40, and lighter waves alone
still died before 4:00: the bot fled every nearby mob (its sword only swings while standing) and drained potions
that mostly overflowed the small pools. The owner chose a sword-paced opening, a bot sword duel (a lone ordinary mob
while no attack skill can fire) and a potion waste guard (drink only when half of one restore fits) instead of raw
80% / 30% thresholds; final tuning waits until later specs change the game again, so this is a coarse pass with no
held-out report. At that historical pass, 601–630 remained reserved and unused; #30's later assessment above
consumes that range.

Levers, training seeds only: the 0:00–6:00 keyframes (table in 4.1) with HP drops 8% → 3% before 4:00, Henesys
elites from 4:00 and bursts from 5:00, Henesys ordinary EXP 2.5x, and MP drops 10% normal / 60% elite. Each policy ran
all **61 training seeds, 1–60 and 2026**, unpatched, 800 × 600 view, 1,800 s cap:

| Policy | Clear / dead / timeout | Clear rate | Death-only median (deaths) | Magician median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Sensible | 27 / 34 / 0 | **44.26%** | **760.4 s** (34) | 276.7 s (61/61) | 600 s (56/61) |
| Random | 2 / 59 / 0 | **3.28%** | **329.4 s** (59) | 281.3 s (42/61) | 574 s (8/61) |

| Policy | MP collected / used | Ratio of totals | MP stock median | Late MP-wait runs / observed |
|---|---|---|---|---|
| Sensible | 15,652 / 9,971 | **1.570** | 84 | 0 / 59 |
| Random | 4,466 / 3,458 | 1.291 | 3 | **2 / 24** |

| Run minute | Sensible mean hits/ordinary kill (hits / kills) | Random mean (hits / kills) |
|---|---|---|
| 1 | 1.667 (732 / 439) | 1.706 (701 / 411) |
| 2 | 1.362 (1,282 / 941) | 1.454 (1,147 / 789) |
| 3 | 1.413 (1,837 / 1,300) | 1.515 (1,353 / 893) |
| 4 | 1.171 (3,465 / 2,960) | 1.308 (2,345 / 1,793) |
| 5 | 1.433 (8,682 / 6,057) | 1.441 (6,265 / 4,349) |

Sensible clears and both death medians are inside the 4.1.1 bands. Known coarse deviations, left for the final pass:
careless clears 3.28% (band 5–15%), sensible MP ratio 1.57 (band 1.2–1.5), Lv30 near 10:00 (goal 12:00–15:00; the
2.5x EXP applies all run), and early ordinary kills averaging 1.2–1.7 hits rather than two by minute five. The
regression seeds 1/2/2026 give Henesys one clear and two deaths with Lv8/Lv10/Magician 3/3 and Lv30 2/3.

#### Spec #29 / #42 Henesys rebalance: chosen training profile (superseded by the owner review above)

C21, gameplay/data commit `cec3fe8`, meets every new training target in 4.1.1. Each policy includes all **61 seeds,
1–60 and 2026**, an 800 × 600 view and a 1,800 s safety cap. No held-out results informed selection. Sensible runs
were freshly run on committed, unpatched data; random contains nine same-profile mechanism records plus 52
remaining runs, included once each. The exact patch matches every shipped tuning leaf. Data Git tree:
`e585c58d2728212ecc2d10b5c55c4c55dd6ea371`; pacing-guard blob:
`837c5f2639820d8149f46809ae625f55f598fac4`. The sealed freeze manifest records the commit and all 122 record hashes.

| Policy | Clear / dead / timeout | Clear rate | Death-only median (deaths) | Magician median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Sensible | 30 / 31 / 0 | **49.18%** | **886.7 s** (31) | 201.9 s (60/61) | 748.3 s (53/61) |
| Random | 4 / 57 / 0 | **6.56%** | **660.6 s** (57) | 200.8 s (59/61) | 708.55 s (14/61) |

The random Lv30 median is conditional on its fourteen reaches, not a progression target. Legitimate early deaths
remain in these counts, including sensible seed 2026 at 204.7 s. All 122 records have empty simulation warnings.

| Policy | MP collected / used | Ratio of totals | MP stock median / empty runs | Late MP-wait runs / observed | Wait / observed seconds after 8:00 |
|---|---|---|---|---|---|
| Sensible | 9,646 / 7,271 | **1.32664** | **50 / 8 of 61** | 10 / 60 | 697.568 / 27,638.619 |
| Random | 6,443 / 5,776 | 1.11548 | 2 / 28 of 61 | **21 / 54** | 1,484.218 / 12,682.881 |

Sensible stock is 57% below the former median 117. Normal/elite/boss MP supply is 4% / 30% / three, compared with
the original 6% / 65% / six. Canonical restoration, damage, MP costs and ranks are unchanged. The finite 30-MP pool
and five Blue starters reduce opening capacity waste; the first five uses occur around the opening minute and
still clip about 60% of their canonical restoration, measured separately from collected supply.

| Run minute | Sensible mean hits/ordinary kill (hits / kills) | Random mean (hits / kills) |
|---|---|---|
| 1 | 1.149 (5,277 / 4,591) | 1.149 (5,263 / 4,581) |
| 2 | 1.000 (8,346 / 8,346) | 1.000 (8,281 / 8,279) |
| 3 | 1.217 (12,190 / 10,014) | 1.219 (12,025 / 9,866) |
| 4 | 1.560 (21,370 / 13,701) | 1.563 (20,784 / 13,295) |
| 5 | **2.187** (40,532 / 18,530) | **2.195** (37,069 / 16,888) |

Density rises before durability: HP stays at ×1 through 2:00, then increases so ordinary kills average roughly
two landed hits by minute five. Means pool lifetime hits over kills; they are not per-cast counts or averages of
per-run means. [The detailed balance record](research/spec29-henesys-balance.md) preserves completed/spawned boss
counts, censoring, rejected cohorts, resource measurements and exact reproduction/provenance.

Freeze commit `81afb94` seals the candidate and conditional Henesys pacing guards. The complete suite passed
**536 tests, zero failures, zero skips** (60 files), including fixed seeds 1/2/2026 on both stages. Henesys recorded
one clear/two deaths and reaches Lv8/Lv10/Magician 2/3, Lv30 1/3; Tree recorded one clear/two deaths and reaches
2/3 for each milestone. All event, EXP, kill, finale, cache and meaningful conditional pacing guards passed.
Three separate actual headless Tree RunScene checks ended in death with **`missing: []` and no script errors**;
their 0/3 clear rate is informational. The detailed report keeps their outcomes separate from the simulation fixtures.

The inspected **306-second x1** Henesys opening at `f6637da` passes final visual acceptance by independently
verified prefix equivalence: the only subsequent runtime/data differences are four Henesys HP-drop keyframe
leaves at 540/660/780/900 s; interpolation first changes behavior after 480 s. All scripts and other data are
unchanged. All five minute screenshots and the final image were inspected, with no missing assets or log errors
(`evidence/spec29/x1/c14_s1/QA.md`). Fresh held-out **501–530** runs were executed once per policy after these
QA gates and are reported separately below, without tuning on their outcomes.

The initially reserved 401–430 range was retired before execution: the historical "Review-fix pass 3" below
already reports 401–406 for both policies. The untouched replacement 501–530 was audited against repository
reports/history before release. This reservation correction changes no gameplay, data, pacing guard or training
record; the original unexecuted freeze manifest is preserved beside the amended one.

#### Frozen held-out report (501–530; consumed)

Both policies ran once on the unchanged frozen profile. All **60 unique records** validate with empty world
warnings and no script/error/warning log lines. This fresh cohort **does not reproduce the training clear-rate
bands**: sensible is above 50%, random below 5%. It is reported without retuning, reruns or pooling it with training.

| Policy | Clear / dead / timeout | Clear rate | Death median (deaths) | Magician median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Sensible | 16 / 14 / 0 | **53.33%** | 770.0 s (14) | 200.15 s (30/30) | 740.3 s (23/30) |
| Random | 1 / 29 / 0 | **3.33%** | 654.2 s (29) | 201.6 s (30/30) | 701.5 s (6/30) |

| Policy | MP collected / used | Ratio | MP stock median / empty runs | Late wait runs / observed | Wait / observed seconds after 8:00 |
|---|---|---|---|---|---|
| Sensible | 4,760 / 3,530 | 1.34844 | 44.5 / 3 of 30 | 5 / 30 | 490.700 / 13,010.118 |
| Random | 2,854 / 2,648 | 1.07779 | 0 / 18 of 30 | 12 / 23 | 770.768 / 5,806.333 |

| Run minute | Sensible mean hits/ordinary kill (hits / kills) | Random mean (hits / kills) |
|---|---|---|
| 1 | 1.162 (2,604 / 2,241) | 1.159 (2,616 / 2,257) |
| 2 | 1.000 (4,113 / 4,113) | 1.000 (4,104 / 4,104) |
| 3 | 1.211 (6,150 / 5,078) | 1.210 (5,882 / 4,862) |
| 4 | 1.565 (10,632 / 6,793) | 1.562 (10,136 / 6,488) |
| 5 | 2.192 (20,434 / 9,321) | 2.161 (16,990 / 7,862) |

Completed/spawned boss counts, censored medians, hit fractions, timestamps and all raw-record hashes are retained
in [the detailed record](research/spec29-henesys-balance.md) and `evidence/spec29/balance/issue42/final/heldout/`.
The amended freeze manifest SHA256 is `6d12b85a5c86b4b107571ff77df7ca2958495030addeaf8c7b4936d7d960767b`.
At this historical #29 assessment, the next reserved range was **601–630**; #30 later consumes it above.
None of these results may be used as fresh tuning evidence.

The pre-#29 cohorts below are historical. Their statements about passing or final acceptance refer to the
earlier targets, which #29 replaces as specified in 4.1.1. Historical Tree pacing is informational.

#### Magician at Lv10 (#40)

The only gameplay data change in this pass is Magician's survivor advancement level, 8 → 10. The sensible bot's
actual `job_changed` time of every job id is reported as `job_seconds` (per job id: min/median/max/count; record key `job_times`, the Magician's also stays `job_t`) in the balance aggregate and
as "Job <id> seconds" in its console report. Missing or negative times are excluded, with no observations
reported as `none (n=0)`. This measures advancement rather than assuming a level milestone is a job change.

Training seeds **1–6 and 2026**, both stages, `--policy=bot --cap=420`, no patches:

| Stage | Time to Magician min / median / max, seconds | Reached | Outcome at 7:00 cap |
|---|---|---|---|
| Henesys Hunting Ground I | 234.3 / **235.9** / 250.2 | 7/7 | 7 TIMEOUT |
| The Tree That Grew I | 202.0 / **208.2** / 213.7 | 7/7 | 7 TIMEOUT |

Both medians fit the revised 180–330 s target in 4.1.1. These capped probes measure early advancement only;
they are not clears or a new population balance acceptance. No held-out seeds were run for this change.
Reproduce with `BALANCE_OUT=evidence/issue40/henesys bash scripts/balance.sh 1..6 2026 --cap=420` and
`BALANCE_OUT=evidence/issue40/tree bash scripts/balance.sh 1..6 2026 --stage=tree_that_grew_1 --cap=420`.
Each directory preserves the per-seed JSON/logs, aggregate JSON/log and the captured full `console.log`.
The full-run regression also exercised fixed training seeds **1/2/2026** on both stages: Henesys cleared 3/3,
Tree cleared 2/3 with seed 1 dying at 987 s. All six reached Lv30; stage median Lv30 times were approximately
775 / 812 s, within the unchanged 720–900 s bounds. These small regression samples do not replace population
acceptance. Output is preserved in `evidence/issue40/full-suite.log` and `full-run-recheck.log`.
Validation ran all 491 tests with zero skips. Three test failures exposed two stale Lv8 stat fixtures and a
floating-point tolerance at the harness's next-tick job-event observation. After correcting only those tests,
the affected progression/player-stat files passed 19 tests and the full-run file passed 5 tests, all with zero
failures/skips. The optional five-minute windowed probe recorded job 200 and no missing assets, but generated
no PNGs and waited for a rendered frame after saving its summary; it was stopped and is not visual verification.
The earlier cohorts below used Lv8 advancement and remain historical evidence.

#### Historical difficulty-overhaul training

The frozen data are v28, gameplay commit `db9ef80`, with the pooled-projectile identity fix. The actual pacing
regression passes 5 tests with zero failures/skips, including the unchanged fixed stage guards. No held-out runs
had been consumed at freeze. Training uses **1–60 and 2026**, 61 runs per
stage/policy, with a 1,800 s cap. Henesys records retain their original v27 / `e8197d7` provenance: v28 changes
only Tree King HP ×0.8→×1.1 (6,400→8,800). Selected Henesys stage data are identical, and predetermined sensible
controls 1/2/2026 match the full v27 records byte-for-byte. Tree's 122 records were freshly run on v28. The profile
diff, source hashes, controls, commands and every rejected comparison remain in local `evidence/acceptance/`.

“Most” means a majority of all runs clear, with at least one non-clear. “Careless dies mostly at 9–12 minutes”
means a majority of recorded deaths fall in 540–720 s, inclusive; clears and timeouts remain separate.
Milestone medians include only reaches, whose counts are explicit. Conditional random Lv30 medians are not
progression acceptance: only 4/61 and 6/61 reach it. Sensible progression has majority reach counts.
| Stage / policy | Clear / dead / timeout | Deaths early / 9-12 / late | Window share of deaths | Mage median (reaches) | Lv30 median (reaches) | Clears below Lv30 |
|---|---|---|---|---|---|---|
| Henesys sensible | 40 / 21 / 0 | 0 / 11 / 10 | 11/21 = 52.38% | 178.6 s (61) | 777.4 s (45) | 1 |
| Henesys random | 2 / 59 / 0 | 16 / 38 / 5 | 38/59 = 64.41% | 178 s (61) | 776.8 s (4) | 0 |
| Tree sensible | 38 / 23 / 0 | 0 / 5 / 18 | 5/23 = 21.74% | 163.6 s (61) | 784.7 s (50) | 0 |
| Tree random | 0 / 60 / 1 | 9 / 36 / 15 | 36/60 = 60% | 164.9 s (59) | 845 s (6) | 0 |

| Sensible boss, in arrival order | Completed / unfinished / unspawned | Completed duration median [min-max], s | Whole-hit HP median [min-max] | Source medians (landed hit count) |
|---|---|---|---|---|
| Mano | 61 / 0 / 0 | 30.6 [11.53-62.27] | 45.92% [41.2%-50%] | touch 45.92% (130) |
| Mushmom | 52 / 7 / 2 | 51.67 [12.07-163.15] | 44.82% [35.66%-57.86%] | attack 44.12% (61), touch 45.09% (228) |
| Blue Mushmom | 40 / 2 / 19 | 71.49 [27.33-176.67] | 44.46% [35.38%-53%] | attack 43.12% (25), touch 44.59% (183) |
| Stumpy | 61 / 0 / 0 | 22.85 [9.55-269.68] | 42.27% [27.8%-74.17%] | attack 42.31% (88), projectile 43.27% (38), touch 40.87% (47) |
| King Slime | 55 / 6 / 0 | 67.32 [20.93-197.93] | 45.6% [35.75%-59.59%] | attack 45.88% (88), touch 45.59% (403) |
| Dyle | 38 / 12 / 11 | 56.91 [6.62-337.88] | 45.05% [35.77%-54.12%] | touch 45.05% (588) |

| Stage / policy | Mean HP collected / used | HP stock median / empty runs | Mean inferred HP stock | Mean MP collected / used | MP stock median / empty runs | MP-wait runs / maximum |
|---|---|---|---|---|---|---|
| Henesys sensible | 32.1 / 33.3 | 0 / 35 | 3.8 | 235.5 / 113.8 | 121 / 0 | 0/61 / 0 s |
| Henesys random | 22.1 / 27 | 0 / 60 | 0.1 | 128 / 54 | 74 / 0 | 0/61 / 0 s |
| Tree sensible | 35.4 / 32.1 | 4 / 26 | 8.3 | 244.7 / 119.6 | 117 / 1 | 1/61 / 77.63 s |
| Tree random | 26.3 / 31.1 | 0 / 60 | 0.2 | 139.6 / 72.4 | 71 / 1 | 1/61 / 34.58 s |

The sensible clear rates are 65.6% / 62.3%; careless window-death shares are 64.4% / 60.0%. Tree random seed
2026 times out at 1,800 s with Dyle alive for 900 s, at Lv36 and zero MP wait. It is neither a clear nor a
completed finale. No unfinished fight is assigned a completed duration. Dyle's sensible 56.91 s median is
within 45–135 s but lower than the nominal 90 s; all encounter ranges and censoring remain visible.

Boss whole damage is measured before Guard splits it between HP and MP, not actual clamped HP loss.
Per-source medians describe typical landed hits, rather than requiring every hit to lie in 40–50%.
Canonical stats, costs, timings, heal bounds and attack boxes remain unchanged. Separate survivor contact and
attack multipliers account for actual build HP at impact. Ordinary late nonmiss hits over completed minute
buckets have sensible medians 211 / 150 and minima 28 / 43; all 61 sensible runs per stage live beyond 8:00.

Stock is inferred exactly as starter stock plus collected minus used (HP starts at 5, MP at 0); rounded means
may not sum exactly. Drop chances are the explicit curves in §5, including no ordinary HP from 9–12 minutes,
elite HP 15% and current-tier boss bundles. HP scarcity is supported by actual collection/use and exhaustion,
not only comparison with MP. The Tree sensible mean HP bank of 8.3 and median 4 remain explicit; scarcity is
not universal exhaustion. MP-wait medians are zero; rare waits and depleted-stock runs remain recorded.
The harness lacks potion source/tier totals, depletion timestamps and healed-HP totals, so these counts do not
establish source-specific supply or exact healing. Guard cast snapshots are separately traced, without exact
offer timestamps or damage-weighted absorption.

The fixed regression sample stays **1/2/2026 on both stages**, with the unchanged 720–900 s stage-median Lv30
guard and at least two reaches. V28 medians are Henesys 805.15 s (2/3) and Tree 890.0 s (3/3), Mage 179.0 /
163.7 s. V26 population gates passed but its fixed Tree median 909.2 s failed; it was not frozen. V27 reshaped
survivor EXP to 4+15L+3.8L² while preserving exact Mage cost 980. Its full Tree careless timing was only 30/59
(50.8%), so the King-only comparison was selected from training, not held-out evidence. Guard final scores
110/109, tier score 112, offer weights 8/8 and HP-drink threshold 0.8 remain in survivor data; random choices
remain uniform. Earlier v22 versus v24 sensible results change both rank weight and threshold and cannot
isolate either. Independent HP-only probe results are kept separate, not pooled with selected training.
#### Historical frozen held-out assessment: Henesys-first acceptance scope

All **120 fresh runs** on seeds **101–130**, both stages and both card policies, use freeze milestone `b230305`
(gameplay `db9ef80`), actual data without patch overrides and the same 1,800 s cap. Every expected identity is
verified. The later `ab5d7fa` change only makes a scene-test fixture use the public EXP threshold; it does not
change gameplay, design data, the pacing guard or the already-running held-out mirror. No tuning followed these
results.

**Tree careless timing fails the original two-stage target:** only **12/29 deaths (41.4%)** fall in 540–720 s, versus a required
majority. Its 717.3 s death median alone would conceal 14 later deaths. The training share of 36/60 (60%) did not
reproduce on this reserved sample. This fails the original two-stage target. The user then clarified that this
pass should gate on Henesys ("Mainly henesys"); Tree careless timing is deferred and informational, with no
further tuning or replacement held-out sample. Both stages remain implemented and playable. Both sensible groups
meet their progression, clear-rate, late-hit and typical boss timing/source-hit gates; Henesys random meets the
careless timing gate. No run times out in the held-out matrix.

The actual frozen pacing run passed 5 tests with no failures or skips. `ab5d7fa` corrected the stale scene-test
EXP fixture through the public progression API. `2805a24` then made the optional canonical recipient-burst path
explicit without changing recipients, RNG or gameplay. That pre-review runtime full suite passed **485 tests, 0 failed,
0 skipped, 59 files** in 590.147 s. The survivor data and pacing guard remained unchanged.

| Stage / policy | Clear / dead / timeout | Deaths early / 9-12 / late | Window share of deaths | Mage median (reaches) | Lv30 median (reaches) | Clears below Lv30 |
|---|---|---|---|---|---|---|
| Henesys sensible | 18 / 12 / 0 | 0 / 5 / 7 | 5/12 = 41.67% | 178.3 s (30) | 794.4 s (23) | 0 |
| Henesys random | 2 / 28 / 0 | 4 / 21 / 3 | 21/28 = 75% | 177.8 s (29) | 810.3 s (3) | 0 |
| Tree sensible | 24 / 6 / 0 | 0 / 4 / 2 | 4/6 = 66.67% | 163.6 s (30) | 812.7 s (24) | 1 |
| Tree random | 1 / 29 / 0 | 3 / 12 / 14 | 12/29 = 41.38% | 162.4 s (27) | 814.7 s (8) | 0 |

| Sensible boss, in arrival order | Completed / unfinished / unspawned | Completed duration median [min-max], s | Whole-hit HP median [min-max] | Source medians (landed hit count) |
|---|---|---|---|---|
| Mano | 30 / 0 / 0 | 31.37 [11.23-48.45] | 47.45% [42.35%-52.17%] | touch 47.45% (72) |
| Mushmom | 28 / 1 / 1 | 74.15 [34.63-128.73] | 44.89% [38.74%-51.27%] | attack 44.32% (27), touch 45% (136) |
| Blue Mushmom | 18 / 4 / 8 | 71.42 [35.88-143.28] | 45.54% [34.77%-51.46%] | attack 44.72% (9), touch 45.59% (76) |
| Stumpy | 29 / 1 / 0 | 22.93 [8.87-78.33] | 42.5% [32.46%-65.67%] | attack 42.79% (43), projectile 41.83% (17), touch 41.82% (30) |
| King Slime | 25 / 4 / 1 | 80.3 [26.67-148.67] | 45.59% [39.36%-60.82%] | attack 45.81% (46), touch 45.47% (210) |
| Dyle | 24 / 1 / 5 | 68.62 [8.45-237.68] | 45.75% [35.83%-53%] | touch 45.75% (247) |

| Stage / policy | Mean HP collected / used | HP stock median / empty runs | Mean inferred HP stock | Mean MP collected / used | MP stock median / empty runs | MP-wait runs / maximum |
|---|---|---|---|---|---|---|
| Henesys sensible | 32 / 34 | 0 / 19 | 3 | 241.5 / 109.5 | 119 / 1 | 1/30 / 81.5 s |
| Henesys random | 25 / 29.8 | 0 / 29 | 0.2 | 144.9 / 55.5 | 99 / 0 | 0/30 / 0 s |
| Tree sensible | 34.6 / 30.9 | 4 / 9 | 8.7 | 239.2 / 106.7 | 132.5 / 1 | 1/30 / 2.32 s |
| Tree random | 27.8 / 32.6 | 0 / 29 | 0.2 | 160.6 / 70.3 | 89.5 / 1 | 1/30 / 20.4 s |

Sensible clear rates are 60% / 80%. Ordinary late nonmiss hit medians are 219 / 145, minima 25 / 29; every
sensible run lives beyond 8:00. HP stock medians 0 / 4 and exhaustion 19/30 / 9/30 show scarcity is uneven;
mean inferred banks are 3.0 / 8.7. MP waiting occurs in one run per sensible stage (81.5 s / 2.317 s), with zero
wait medians and stock medians 119 / 132.5. These remain measured counts, not a claim that every build has
ample MP or exhausts HP. Tree has one clear below Lv30, retained explicitly rather than excluding it.

Random-policy encounter/source observations remain in the raw audit, including small and censored finale
samples: Henesys Blue Mushmom has only 2 completed fights, 1 unfinished and 27 unspawned, with a whole-hit
median 39.43% across 8 landed hits. Tree Dyle has 1 completed fight (422.27 s), 8 unfinished and 21 unspawned.
They are not substituted for the sensible-policy boss medians. All durations, source counts, stock inference
and missing harness measurements follow the definitions above. The frozen data remain unchanged after this
failed assessment; these seeds must not become another tuning input.

#### Historical corrected-runtime training and Henesys assessment

Final review corrected the unequal-afterimage reach gate: swing selection remains uniform while the chosen
stance keeps its own impact box. It also replaced steady boss-action buffer allocation with a reusable borrowed
view and shared the bot/camper portal-entrance approach without changing their goal policies. These fixes are
runtime `a25697e`; **all survivor data, canonical values and pacing guards remain unchanged** from the v28 freeze.
The corrected full suite passed **489 tests, 0 failed, 0 skipped, 59 files** in 695.839 s, including the unchanged
fixed pacing sample on both stages and real-cache tests. No skip is counted as coverage.

The corrected-runtime 101–130 Henesys audit did not pass every gate: sensible clears were **15/30**, exactly
half, failing “most but not all”; careless timing passed at **21/29 deaths** in 540–720 s. These results remain
preserved in `evidence/acceptance/post_review_hg/`, separate from both the original 120 and the final assessment.
They were not used to choose data changes. The original Tree careless **12/29** timing failure remains deferred
under the owner's Henesys-first scope; no Tree tuning or replacement Tree validation was performed.

Before further training, the corrected-runtime baseline cohort was declared as **1–24 plus 2026**, both policies.
Its sensible 12/25 clears prompted a sensible-only expansion through training seeds 25–60; careless already met
its timing target at 14/25 deaths in-window. The resulting **61 sensible / 25 careless** training records supported
selecting the data unchanged: sensible 38/61 clears, Mage median 178.6 s (61 reaches), Lv30 789.0 s (43 reaches),
boss duration medians 30.60/65.17/74.12 s (61/51/38 completed), and every sensible boss/source hit median in-band.
Ordinary late hits have median 209/minimum 25. Sensible HP stock median is 1 (29/61 empty); MP stock median 118,
with no MP-wait ticks. Careless HP stock is zero in all 25 runs. Full ranges and censoring are preserved in
`evidence/acceptance/final-review/training-assessment.md` and its machine-readable metrics; cohorts are not pooled.

Ticket #27's final reserved range was explicitly amended to **301–330** before any of those runs, because 101–130
was consumed and historical 201–212 was also consumed. Substantive targets stayed unchanged. Selection of unchanged
`a25697e` was sealed at **2026-10-15 03:46:14 UTC**, before the first held-out log at **03:46:48 UTC**. The initial
PowerShell manifest construction failed and left an empty file; its metadata was rebuilt at **03:48:21 UTC**,
after launch, from the sealed decision and unchanged commit/data. The runner's recorded account says completed-result
existence was checked during repair, no outcome values were read, and no tuning or selection changed. Independent
audit verified the sealed decision, hashes and timestamps; absence of outcome reads is the runner's account.
The preserved manifest discloses this repair, all 86 training-record hashes, six unchanged data hashes and the
unchanged pacing-guard hash.

All **60 final Henesys runs** use `a25697e`, actual data without patches, and the 1,800 s cap. This final amended
assessment passes the Henesys targets; it neither replaces the earlier failed audit nor claims Tree timing passed.

| Final 301–330 policy | Clear / dead / timeout | Deaths early / 9–12 / late | Window share of deaths | Mage median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Sensible | 22 / 8 / 0 | 0 / 6 / 2 | 6/8 = 75% | 177.45 s (30/30) | 774.4 s (23/30) |
| Careless | 1 / 29 / 0 | 4 / 23 / 2 | 23/29 = 79.31% | 175.7 s (30/30) | 838.6 s (1/30) |

Sensible clears are **73.33%**, most but not all; careless timing has a majority of deaths in 9–12 minutes.
No clear occurs below Lv30. The careless single Lv30 reach is an observation, not a progression acceptance sample.
Sensible ordinary late nonmiss hits have median **218.5**, minimum **58**, using completed minute buckets after
8:00. Boss hits and misses do not satisfy that ordinary-hit observation.

| Final sensible boss | Completed / unfinished / unspawned | Completed-fight duration median [min–max], s | Whole-hit HP median [min–max] | Source medians (landed hits) |
|---|---|---|---|---|
| Mano | 30 / 0 / 0 | 27.29 [11.13–73.40] | 45.92% [41.84–50.00%] | touch 45.92% (75) |
| Mushmom | 25 / 5 / 0 | 57.23 [20.85–161.92] | 45.00% [39.20–50.30%] | attack 44.31% (20), touch 45.06% (126) |
| Blue Mushmom | 22 / 0 / 8 | 73.44 [22.80–131.77] | 44.95% [38.46–51.46%] | attack 43.09% (12), touch 45.63% (73) |

These duration medians cover completed fights only (Mushmom 25 of 30 spawned); unfinished fights are censored, not
missing. The harness now prints `completed n/spawned` beside the median and a censored median that counts each
unfinished fight as at least its elapsed seconds (`>=` when that makes it a lower bound); pass 3 re-measures with it.
All sensible completed-duration medians fit 15–45 / 30–90 / 45–135 s, and all whole/source-hit medians fit 40–50%.
Ranges show that individual fights and damage rolls can fall outside those typical bands. Fractions precede
Magic Guard's split. Unfinished fights are not completed observations or zero durations. Careless boss samples
remain separate: Mano 28/2/0, Mushmom 4/15/11, Blue Mushmom 1/0/29 completed/unfinished/unspawned.

| Final policy | Mean HP collected / used | HP stock median / empty runs | Mean inferred HP stock | Mean MP collected / used | MP stock median / empty runs | MP-wait runs / maximum |
|---|---|---|---|---|---|---|
| Sensible | 33.13 / 33.80 | 2 / 11 of 30 | 4.33 | 238.87 / 112.13 | 117 / 0 of 30 | 0/30 / 0 s |
| Careless | 24.03 / 28.70 | 0 / 29 of 30 | 0.33 | 129.03 / 55.23 | 67.5 / 0 of 30 | 0/30 / 0 s |

HP scarcity is uneven, not universal exhaustion; MP supply supports the recorded builds without waiting. Stock
remains starter plus collected minus used. Exact potion-source/tier counts, depletion timestamps and healed-HP
totals remain unmeasured. Final records, console reports, audit and repair disclosure are retained in
`evidence/acceptance/final_301_330/`. No further tuning followed this assessment.

The final corrected-runtime density capture uses `a25697e`, Henesys seed 2026, speed 1, vsync off, warp 600 and an
absolute 780 s cap. It remains PLAYING at that deliberate cap, not cleared. After all owned heavy jobs ended,
**74,953 frames with 200+ mobs have p95 3.070 ms**, p99 3.662 ms and max 25.346 ms; max 274 mobs, `missing: []`.
Work p95 is 1.806 ms and sim cost 0.865 ms/tick. The final screenshot was checked by eye. The PowerShell wrapper
exited 1 after treating the expected stderr status line as an error; the game completed and wrote valid summary,
screenshots and engine log. The late after-process sample and wrapper issue are disclosed in
`evidence/acceptance/density_hg_final/completion-context.json`; full hardware/background context is in the
Implementation Plan. Earlier visual/performance evidence remains separate below.

#### Historical #37 initial MP scarcity pass (2026-10-14)

Issue #37's initial MP scarcity pass uses normal/elite MP chances 2%/30% and boss MP bundles of 3,
with HP supply unchanged (tier C). Before integrating the subsequent #48/#49/#50 changes, HG training seeds 1..12
showed sensible collected/used falling from
1.917 to 1.064 and median leftover from 85 to 0; random falls from 2.275 to 1.034, with median leftover
59.5 to 0. Sensible clears fall from 4/12 to 0/12; random remains 0/12. Median MP-short seconds become
116.884 (sensible) and 54.367 (random), from zero. This overshoots the 1.2-1.5 target; final calibration
belongs to the balance pass. No held-out seeds were run. Configuration and exact training output:
[issue37-mp-drops.md](research/issue37-mp-drops.md). Superseded by spec #237's cooldown model.

#### Historical review-fix pass 3: Henesys 9:00 HP trickle (2026-10-15)

Giving potion drop rolls their own RNG stream 7 (they had shared stream 5 with basic-attack stance rolls) reshuffled
seeded outcomes, and fixed regression seed 1 on Henesys then died at 592 s, failing the `test_full_run` guard
"a death comes late in the run" (>= 600 s); with the shared stream it had died at 950 s. The stream fix and the guard
stay. **Change (tier C, survivor data only):** the Henesys keyframe at 9:00 (`t` 540) gets `normal_hp_drop_chance`
0.002 instead of 0, so the 0.2% ordinary HP chance of 8:00 holds to 9:00 and trickles to 0% at 11:00 instead of
reaching 0% at 9:00. Rationale: it is the smallest supply change that clears the guard. Runs are bit-identical before
8:00; from 8:00 to 9:00 the same stream-7 rolls are drawn against a flat 0.2% instead of one falling to 0%; after
9:00 the HP rolls that were skipped at 0% are drawn, which also shifts the later MP rolls on stream 7. The extra supply
is about one Red Potion per run (HP potions collected on 1–60: sensible 1909 -> 1979, careless 1414 -> 1438 in
total), and Tree data are untouched.

Selection used only training seeds (1, 2, 2026 as a gate, then 1–60). Rejected: raising the 8:00
keyframe to 1.2% (holding the 6:00 value) or 1.6% also passed, but raised sensible clears from 37 to 45 and 48 of
60, an easing that belongs to the planned Henesys rebalance (#42); 0.4–1.0% at 8:00 and Mano's HP bundle 6 -> 7
left seed 1 dying before 600 s or within 2 s of it. In the test harness seed 1 now dies at 610 s, a thin 10 s
margin over the guard; seeds 2 and 2026 clear (Lv30 at 828 s and 770 s). Before = HEAD before this change, after =
with it; Tree 1–30 rerun on the committed data is identical row for row.

| Training seeds, policy | Clear / dead / timeout | Deaths early / 9–12 / late | Death median | Mage median (reaches) | Lv30 median (reaches) |
|---|---|---|---|---|---|
| Henesys 1–60 sensible, before | 37 / 23 / 0 | 0 / 11 / 12 | 12:22 | 2:58 (60) | 13:01 (44) |
| Henesys 1–60 sensible, after | 39 / 21 / 0 | 0 / 9 / 12 | 12:37 | 2:58 (60) | 13:07 (45) |
| Henesys 1–60 careless, before | 2 / 58 / 0 | 16 / 35 / 7 | 10:07 | 2:56 (59) | 14:12 (4) |
| Henesys 1–60 careless, after | 2 / 58 / 0 | 15 / 35 / 8 | 10:08 | 2:56 (59) | 13:34 (4) |
| Tree 1–30 sensible, before = after | 11 / 19 / 0 | 0 / 4 / 15 | 16:51 | 2:43 (30) | 13:50 (22) |

Four sensible seeds changed outcome (33 cleared -> died; 39, 59, 60 died -> cleared) and two careless seeds (19, 54)
swapped; the earliest sensible death stays 9:15. Fresh held-out smoke, Henesys 401–406, report only and never tuned
on: sensible 3/6 cleared (deaths 11:22, 12:27, 13:07; Mage median 2:59; Lv30 median 12:25, 4 reaches), careless 0/6
(deaths 5:05, 5:09, 9:56, 10:49, 12:15, 12:25). Records: `_scratch/p3/` (local, uncommitted).

#### Historical informational camper samples

On the same v28 data, seeds **1–6 and 2026**, `--camp-after=60 --cap=1800`, all 21 runs reached their requested
camping position. These observations are informational and did not select or tune the profile.

| Policy | Clear / dead / timeout | Death median [min–max], s |
|---|---|---|
| Henesys top platform | 0 / 7 / 0 | 300.3 [300.3–301.6] |
| Henesys rope | 0 / 7 / 0 | 207.2 [205.9–294.4] |
| Tree top platform | 0 / 7 / 0 | 321.0 [310.5–403.5] |

Raw records, requested-position flags and commands are preserved in `evidence/acceptance/campers/`.

Pre-review visual evidence preserves the original full composites and the corrected Tree replay: both stages actually
clear beyond 15:00, and corrected summaries have `missing: []`. Optional Dyle recipient art is selected from the
canonical field rather than assumed. The separate Henesys speed1 uncapped 10:00–13:00 measurement records
62,580 frames with 200+ live mobs at p95 **3.912 ms**, max274 mobs, no missing assets. It stops PLAYING at its
deliberate 13:00 measurement cap, not a clear. Hardware, background load and timing detail are in the
Implementation Plan performance log; screenshots were checked by eye. This completed the pre-review implementation evidence
for the user-amended Henesys-first scope, with Tree careless timing still deferred.
#### Historical Phase 1 records

**Historical seeds.** The earlier 2026-10-14 pass was tuned on seeds 1-24 (variants compared on both policies) and is reported on the
held-out seeds 101-130, which were never used for tuning; the earlier record (seeds 1-23 + 2026) had been tuned and
reported on the same seeds, and it did not hold on fresh seeds (a review found 6 of 18 deaths on seeds 31-48). Keep
tuning on 1-60 and reporting on 101-130. The earlier regression consumed seeds 101/102; the new-system regression
uses fixed training seeds 1/2/2026 on both stages as described in 4.1.1.

Targets: Lv 8 (Magician) at 2:30-3:45, Lv 10 at 3:00-5:30, Lv 30 at ~12:00-15:00, a crowd of 200+ alive in the last
minutes, hits taken regularly after 8:00, deaths of the sensible player late and on a minority of seeds; a careless
player should reach the job advancement and usually get past 8:00.

| henesys_hg1, held-out seeds 101-130 | Before (data of 2026-10-13) | After (this data) |
|---|---|---|
| Sensible player (`bot`): outcome | 22/30 cleared; deaths 9:33-14:12, 3 before 12:00 | 20/30 cleared; deaths 8:57-14:39, 4 before 12:00 (8:57, 10:19, 10:48, 11:33) |
| Lv 8 / Lv 10 / Lv 30 (median) | 2:28-4:50 (2:59) / 3:52 / 10:23-13:31 (11:53), 24 reach Lv 30 | 2:26-4:54 (2:45) / 3:48 / 11:22-13:03 (12:03), 25 reach Lv 30 |
| Level at 15:00 or death | 20-41, median 35 | 17-39, median 35.5 |
| Alive at 4/8/12/14 min (median of the minute's mean) | 42 / 155 / 232 / 289 | 24 / 74 / 123 / 220 (max 156-330, median 311) |
| Mobs near the player (300 x 150 px) at 4/8/12 min | 0.9 / 10.8 / 18.7 | 0.5 / 7.1 / 15.3 |
| Hits before 6:00 / after 8:00 (median) | 2 (26 of 30 runs hit) / 18 | 1 (16 of 30 runs hit) / 23 |
| EXP drops lying on the map at 4/8/12 min | 82 / 316 / 512 | 52 / 77 / 135 (14% of the EXP expires) |
| Careless player (`random`) | 0/30 cleared; median death 7:31; 24/30 reach Lv 8; 13/30 live past 8:00; 9 die before 6:00 | 2/30 cleared; median death 8:57; 27/30 reach Lv 8; 18/30 live past 8:00; 3 die before 6:00 |
| Hands off the keys from 5:00 (`bot` cards, seeds 101-112) | 1/12 survive; deaths 6:30-13:39, median 11:54 | 0/12 survive; deaths 6:34-12:28, median 9:40 |

What changed (all data toggles, see sections 5, 7, 8, 9 and 11): Three Snails levels with the character
(`level_ranks`), Energy Bolt comes with the Magician job (`grants.skills`), a power card is guaranteed after a draw
without one (`pity.draws`), spawns prefer the player's platform and its neighbours (`spawn.prefer_hops`), drops expire
(`pickup.lifetime`), the EXP curve is steeper (c 2.25 -> 3), and the keyframes of section 4.1 (lower `max_alive` at
4:00-9:00, gentler HP growth, smaller early bursts, a faster early spawn rate).

Reading: careless builds now usually reach the Magician and survive past 8:00, a build left alone from 5:00 dies about
two minutes sooner (play matters more than before), and the sensible player's outcome is about the same as before
(20 vs 22 clears of 30 is within the seed-to-seed spread). The price is a thinner mid-game
crowd for a strong build (74 alive at 8:00 instead of 155); a larger share of it is near the player (10% and 12% of
the alive mobs at 8:00 and 12:00, against 7% and 8%), the strong build takes more hits after 8:00, and the crowd still
reaches 200-330 in the last minutes. Not reached: early pressure on a
strong build. The kiting bot takes about one hit before 6:00 (14 of 30 runs none at all), fewer than before, because
Three Snails is stronger early; a variant with higher 6:00-12:00 spawn rates (5.5/10/15) gave a bigger mid-game crowd
(88 / 139 alive at 8 / 12 min on seeds 1-24) but more deaths (18 instead of 21 clears of 24) and Lv 30 at ~11:20, and
was not taken. The bounds of a human player lie between the kiting bot and the hands-off run; how punishing the
careless and early game should be is a design decision for the lead.

Other stages (held-out seeds 101-112, `bot`), not tuned as carefully (their stage cards say so): The Tree That Grew I
(henesys numbers with its own pools, no opening Slimes, `prefer_hops` -1 because spawning next to the player on its
small platforms killed runs in the first minutes) clears 8/12, Lv 8 at ~2:36 and Lv 30 at ~10:47 (too fast), deaths
at ~10:00 and one at 2:51. The Hill East of Henesys (gentler numbers, `prefer_hops` -1, `exp_mult` 1.2) clears 6/12,
Lv 8 at ~3:06, Lv 30 reached on 5/12 (slow), deaths 10:41-14:58.

#### Swarm pass (2026-10-14, later the same day)

**Problem.** In a playtest (seed 555) the mid-game crowd (6:00-12:00) stood in long rows on the platform above the
ground of 104040000 and never reached the player on the ground; only a handful of mobs were near it.

**Engagement metric** (`balance_run.gd` `eng_by_min`, `scripts/balance.sh` column `eng6/9/12`): the share of the live
mobs within 400 px horizontally and 200 px vertically of the player's feet, as the ratio of sums (engaged mob-ticks /
live mob-ticks) over every tick of the minute centred on m:00 ([m:00 - 30 s, m:00 + 30 s)); the tables give the median
over the seeds. **Stale** (`stale_by_min`): over the same windows, the share of live mobs that have been outside that
box for 20 s or more in a row (since their spawn or their last time in it; a relocated mob keeps its time,
`mob_spawned.relocated_from`; until the follow-up below a relocation restarted it, so the first version's 0% could not
show mobs idling off-screen until they were relocated).

**Diagnosis** (an instrumented headless run of the kiting bot, seeds 1-12, 5:00-12:00, the data and code before this
pass; every second each live mob that had been outside the box for 15 s or more was classified by platform, state,
NavGraph route and edge kind, whether it moved, whether its route flipped, and why it spawned where it did):

- Only 8% of the live mob-seconds were such long-idle mobs. Of those, 72% were on the ground platform itself, walking
  after a player who kites at 125 px/s from mobs walking at 22-80 px/s; 22% were on the long platform above the ground
  (1518 px, 300 px up) walking to its drop, half of them *away* from the player: the route was the fewest edges, and
  that platform drops straight onto the ground only at its left end (its right end drops onto a step one edge
  further), so every mob on it walked to the left end, then all the way back on the ground. Airborne, no route and
  route flipping were about 1% each. Nothing was stuck: no mob waited at a takeoff it could not use, none pushed a wall
  (104040000 has no wall inside a platform), no jump edge failed (`test_real_every_edge_lands_where_the_graph_says`).
- The cause of the rows was spawning: `prefer_hops` 1 counted that long platform as one edge from the ground, so 33% of
  the spawns after 5:00 landed on it (and 24% on the two small platforms above its left end) against 40% on the ground.
  At 6:00, 18% of the live mobs were within 400 px horizontally of the player but 300+ px above it (the visible rows),
  69% were 400-1300 px away (on their way, or trailing), 8% were engaged.
- 7% of the spawns (5-32% on seeds 101-112) were recycled silently, 79% of them for falling 1300 px behind.
- The bot kills 85% of the mobs inside the box ~10 s after they spawn, so engagement is capped by how long a mob takes
  to arrive (every spawn is 448+ px out, outside the view + 48 px) against how long it survives once there.

**Changes, first version** (sections 4, 4.1 and 11; `NavGraph`, `MobSwarm`, `SpawnDirector`, `RunWorld`,
`FootholdMap`, `balance.json` `spawn`, `stages.json`): mobs steer by the shortest walk to the player's x (a travel-cost
field) with 96 px of hysteresis; straight-up hops take off where the route goes on; walkers under a player on a low
step walk under it; the first spawn ring is the floors beside the view (160 px out, 48 px above/below), and a point is
preferred when its way in is no longer than the walk in from that ring's outer edge; no spawns on floor buried behind a
wall; off-screen mobs that stop closing in for 3 s, or are far or cannot reach the player, are moved ahead of the
player instead of being removed; the keyframes of section 4.1 (HP x1.3 from 6:00, 6:00-12:00 rate +10-20%, early rate
-15%, touch damage halved); The Tree That Grew I and The Hill East of Henesys take the same numbers (Hill `exp_mult`
1.2 -> 1.1).

**Follow-up** (after an independent verification of the first version). The first version's record was taken on the
held-out seeds 101-112 only, which happened to draw the high-crowd outcome (alive at 9:00: 149.5 there against 57.5 on
the other 30 seeds of the verification), so its "55-60% engaged at 9:00 / 12:00" did not hold on the rest (46% / 50% on
101-130, 35% / 39% on the fresh seeds 201-212), and it brought Lv 30 to ~11:15 on every stage, before the
~12:00-15:00 target. The follow-up changed:

- The stall rule counts only the mob's own progress: its way left must shrink *and* the mob must have moved 1 px since
  it last came closer (the player walking up to a mob stopped at a wall shortened its way, so such mobs were never
  relocated); a mob standing still on screen keeps counting and is moved as soon as it is off screen; and a mob is
  only moved from 80 px outside the view (48 + 32 on every side: right after the player turns, the camera still lags
  on the other side).
- Spawning and relocation reject a point when a wall across a platform stands anywhere on its way to the player
  (followed edge by edge onto the player's platform), not only on its first platform: on 100010000 mobs that dropped
  onto the ground outside the hill's faces walked into them while the player stood between the faces (found before
  walls were scoped to their own structure; those faces are another group's and no longer stop the ground's walkers).
- Spawns stay 32 px further out on the side a moving player runs away from (`spawn.trail_margin`; the camera lags
  ~29 px behind a running player, so mobs faded in there with up to 23 px of their body on screen).
- The EXP curve is steeper (section 5: 22% more EXP to Lv 30, 4% more to Lv 8), and touch damage is 0.7 of the first
  version's (0.35-0.525; the steeper curve alone killed 45 of 48 tuning runs: a build that levels slower is weaker
  against the same crowd). The Hill takes 1.0x EXP and touch damage 0.25-0.375, the Tree 0.85x EXP in that historical model.
- `balance_run.gd`'s stale share follows a mob across relocations (`mob_spawned.relocated_from`).

**Seeds.** Tuned on seeds 1-48 (henesys) and 1-24 (the other stages). The record below is the whole held-out range
101-130 plus the fresh seeds 201-212 that the verification added (42 seeds, never used for tuning), each run once with
the final data and code. The 209be82 and first-version columns are the verification's runs with the same
`balance_run.gd` (its stale share then restarted at relocations).

| henesys_hg1, held-out seeds 101-130 + 201-212 (42), `bot` | 209be82 | First version | After the follow-up |
|---|---|---|---|
| Engagement (400 x 200 px) at 6:00 / 9:00 / 12:00, median of 42 (range) | 8.5% (4-21) / 15% (5-42) / 21% (11-39) | 32% (18-54) / 41.5% (20-63) / 44% (26-70) | 34.5% (19-60) / 52% (21-61) / 58% (24-78) |
| The same on 101-130; on 201-212 | 9 / 17 / 20; 7.5 / 11 / 23 | 34.5 / 46 / 50; 26 / 35 / 39 | 36 / 53.5 / 58; 32 / 43.5 / 54 |
| Near the player (300 x 150 px) / alive, minutes 8-12 (medians) | 5-12% | 23-36% | 31.5-43% |
| Stale (20 s+ outside the box) at 6:00 / 9:00 / 12:00 | 3% / 4% / 3% | 0% / 0% / 0% (could not show off-screen idling) | 0% / 0% / 0% (relocated mobs keep their time) |
| Spawns recycled / relocated per spawn (median) | 9.5% / - | 0% / 32.5% | 0% / 34.5% |
| Alive at 4 / 6 / 8 / 9 / 12 / 14 min (median of the minute's mean) | 24 / 33 / 67.5 / 67 / 112.5 / 220 | 11 / 20 / 97 / 107.5 / 158 / 280.5 | 10 / 19 / 122 / 138 / 222.5 / 284 |
| Outcome | 27/42 cleared; deaths 8:57-14:40, 4 before 12:00 | 32/42 cleared; deaths 10:44-14:54, 3 before 12:00 | 29/42 cleared; deaths 10:27-14:42, 2 before 12:00 (10:27, 11:37) |
| Lv 8 / Lv 10 (median) | 2:46 (39/42 in 2:30-3:45) / 3:49 | 2:40 (41/42) / 3:34 | 2:42 (41/42) / 3:42 |
| Lv 30 (median of the runs reaching it) | 11:47; 36 reach it, 15 at 12:00 or later | 11:16; 38 reach it, 5 at 12:00 or later | 12:09 (11:30-14:19); 33 reach it, 22 at 12:00 or later |
| Lv 30 on 101-130; on 201-212 | 12:04; 11:42 | 11:19; 11:11 | 12:17; 12:07 |
| Level at 15:00 or death (median) | 35.5 | 38 | 34 |
| Hits before 6:00 / after 8:00 (median) | 1 / 27 | 0 / 100.5 | 0 / 146 |
| EXP lost to expired drops (median) | 13% | 7.5% | 5.5% |
| Careless player (`random`), seeds 201-212 | 1/12 cleared; deaths 5:47-13:15 | 2/12 cleared; deaths 7:12-14:17 | 3/12 cleared; deaths 9:39-13:11; Lv 8 median 2:53 (12/12 reach it) |

On the tuning seeds 1-48 the final data gives 35/48 clears (13 deaths, 4 before 12:00), Lv 8 at 2:44, Lv 30 at 12:14
(22 of 34 at 12:00 or later), engagement 34% / 50.5% / 64% (the first version's data with the follow-up's sim changes:
32/48 clears, Lv 30 at 11:22, 4 of 39 at 12:00 or later, engagement 37% / 44% / 55%).

Other stages, seeds 201-212, `bot` (209be82 -> first version -> after the follow-up): The Tree That Grew I 10 -> 12 ->
9 of 12 cleared (deaths after the follow-up 12:02, 14:11, 14:40), Lv 8 2:32 (9 in the window) -> 2:28 (3) -> 2:38
(12), Lv 30 10:35 -> 10:06 -> 11:49 (10 reach it, 3 at 12:00 or later), engagement 4.5% / 6% / 12% -> 24.5% / 27% /
32.5% -> 31.5% / 40.5% / 57%. The Hill East of Henesys 9 -> 11 -> 10 of 12 cleared (deaths 12:19, 14:38), Lv 8 3:05
(12 in the window) -> 3:00 (11) -> 3:11 (9; 2:45-4:46), Lv 30 12:32 (3 reach it) -> 10:41 (11) -> 11:43 (10, 2 at
12:00 or later), engagement 9.5% / 9.5% / 28% -> 40.5% / 55.5% / 58% -> 39.5% / 60.5% / 76.5%, EXP lost to expiry 57.5%
-> 12.5% -> 7%, hits after 8:00 10.5 -> 110 -> 206.5.

**On screen** (a headless probe that replays CameraRig: smoothing 6/s, 8 px dead zone, feet at 58%, x4 frames; the
verification's seeds 777, 113, 117, 201-206 on henesys and 201-203 on the other two; first version -> after the
follow-up): spawns fading in with part of the body on screen 49-102 -> 0-1 per henesys run (26-33 at 209be82), 141-196
-> 0 per Tree run, 30-123 -> 1-9 per Hill run; relocations landing partly on screen 2-12 -> 0-3 (henesys), 19-32 -> 0-2
(Tree), 11-26 -> 0-1 (Hill); relocations starting with any of the body on screen 0 -> 0; no mob airborne for 2.5 s.
Mobs standing at a wall across the Hill's ground (mob-seconds standing still for 5 s+ away from the player) on seeds
201 / 202 / 203: 22903 / 73777 / 48783 at 209be82, 8382 / 3766 / 0 in the first version (2680 / 1531 / 0 of them on
screen; 5087 off screen on 201 alone), 45 / 484 / 1006 after (43 / 405 / 864 on screen); on the tuning seeds 1-12 the
sim changes alone took the first version's 43645 such mob-seconds (21216 on screen) to 583 (149 on screen).

Reading: the crowd presses the player: about a third of it is within reach at 6:00 and over half from 9:00 on the 42
held-out seeds, against 8-21% before the swarm pass; nothing idles off-screen (stale 0% with relocated mobs keeping
their time), nothing is lost (relocation instead of recycling) and no mob appears or vanishes on screen. Engagement at
6:00 stays just under the 35-50% target (34.5% median; 32% on the fresh seeds 201-212): a strong build kills mobs as
they arrive, so before 6:00 the crowd is thin (10-19 alive, against 24-33 before the swarm pass, when mobs idled
off-screen) and the bot takes no hits; from 6:00 the crowd builds quickly (122 at 8:00). Lv 30 is back in the
~12:00-15:00 window on henesys (12:09 median, 22 of 33 runs at 12:00 or later); on the Hill (11:43) and the Tree
(11:49) it is 10-20 s short of its low edge. The price of the steeper curve is lighter touches: the kiting bot is
touched ~146 times after 8:00 (~27 before the swarm pass, ~100 in its first version), each for 0.7 of the first
version's damage; on the Hill ~200 times. The survival numbers are partly the bot's: about one run in ten starts
slowly (seed 101: the bot pinned against the map's right end with the swarm on one side, Lv 8 at 3:54), and late
deaths often come with the bot pinned at a map end. Seen in windowed playtests (`evidence/swarm2/s777_x4`, henesys
seed 777, CLEARED Lv 36, the same run as headless; `evidence/swarm2/hill_s202_x4`): at 6:00 a thin crowd (17 alive)
on the ground beside the player; from 8:00 the ground is packed on both sides; at 11:00 and 12:00 the bot stands at the
map's right end with a dense wall pressing from the left; at 14:00 it is surrounded (300 alive). Moving rows on the
long platform above the ground (mobs walking to its near drop, one mid-fall at 11:00) still show at 9:00, 11:00, 12:00
and 14:00; they are on their way in, not queueing. On the Hill the crowd presses the player along its own floor from
5:00 (a row of snails on a small platform above, mobs dropping in at the screen edge).

#### #106 automatic LUK for Magicians regression smoke (2026-10-16)

No tuning: `ISOLATE=s33t106 MAPLE_SURVIVORS_CACHE=<spec33 cache-t106> bash scripts/balance.sh 1 2 2026`, both stages and
`bot`/`random`, real cache, no patch. Baseline is the same smoke on db1c5cb (pre-change main, extracted to `_scratch`).
All 12 runs completed with exit 0, no script errors, no world warnings. Henesys still reaches Magician (about 4:30 Lv10,
266-275 s Magician seconds) and the first boss in every run; Tree remains record-only. No held-out seeds were used.

| Stage / policy | Clear / dead | Death seconds, after (before) | Lv27-35 end level, after (before) | MP-short s, after (before) |
|---|---|---|---|---|
| Henesys bot | 0 / 3 | 14:46, 13:52, 15:58 (13:00, 13:11, 15:07) | 27, 34, 35 (25, 33, 33) | 142, 220, 246 (117, 260, 287) |
| Henesys random | 1 / 2 | 7:46, 9:39 (7:17, 10:24) | 11, 24, 42 (11, 27, 44) | 56, 99, 202 (54, 71, 176) |
| Tree bot | 0 / 3 | 10:42, 11:06, 2:08 (10:52, 11:17, 2:08) | 3, 22, 24 (3, 22, 25) | 92, 125, 196 (92, 114, 202) |
| Tree random | 0 / 3 | 10:47, 2:45, 1:28 (10:17, 2:45, 1:28) | 3, 4, 25 (3, 4, 24) | 58, 100, 123 (58, 100, 123) |

Magician seconds are identical in every row. Henesys bot fight times for the first boss (2220000) are unchanged except one seed at 19.4 s -> 19.6 s; the
second boss (6130101) completed-fight range moved from 51-64 s to 30-65 s (n=2 completed each, one unfinished each), so
its timing is recorded here as changed, not tuned. The expected effect is visible only in Magician
stats: at Lv10 LUK is 12 (was 4) and INT 41 (was 49), and at Lv70 INT is 281 instead of 349. Those are the
recorded trade-off, not a tuning result. Raw records stay in `_scratch/t106_smoke/` and `_scratch/t106_smoke_base/`.

#### Spec #33 / #107 meso drops regression smoke (2026-10-17)

No tuning: `ISOLATE=s33t107<a-d> bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
private real cache, no held-out seeds, on the ticket branch (base: the #105 + #106 integration branch). "Before" is the
same code with `PATCH={"balance":{"mesos":{"chance":0,"boss_drops":0}}}`, which reproduces the pre-#107 event stream
byte for byte (`test_character_baseline` hash `6ff18c3e...`), and its numbers equal the #106 smoke above. All 12 runs
completed with exit 0, no script errors and no world warnings. Henesys still reaches Magician (4:30-4:45) and Mano in
every bot run; Tree remains record-only.

| Stage / policy | Clear / dead before -> after | End seconds seed 1/2/2026, before -> after | Mesos earned per round (seed 1/2/2026) |
|---|---|---|---|
| Henesys bot | 0/3 -> 0/3 | 887/833/959 -> 859/778/899 | 210,406 / 83,846 / 209,566 |
| Henesys random | 1/2 -> 1/2 | C 1003/466/580 -> C 995/462/346 | 321,062 / 18,298 / 11,452 |
| Tree bot | 0/3 -> 0/3 | 643/666/128 -> 622/157/128 | 208,404 / 3,108 / 1,680 |
| Tree random | 0/3 -> 0/3 | 648/165/88 -> 747/158/88 | 289,758 / 2,520 / 1,218 |

The runs diverge slightly from "before" because mesos change the drop-pop RNG draws and the sensible bot now walks to
coins like any other drop (its drop-chasing code is unchanged and covers every pickup kind); two seeds die earlier
(Henesys random 2026, 9:40 -> 5:46, before Mano; Tree bot seed 2, 11:06 -> 2:37), none die later by more than that
chaos allows, and bosses killed per run match "before" except those two runs and Tree random seed 1 (one more). That is
recorded as changed, not tuned.

Meso calibration (set once, no loop): the multiplier `balance.mesos.mult` is 14. At multiplier 1 the only Henesys
clear in the smoke (random policy, seed 1, 3,259 kills, all three bosses) earned 22.9k mesos, and the sensible bot
earned about 15k by its 14:19 and 14:59 deaths, so 14 puts that clear at 321k, inside the owner's 300-350k target
for a clear (the later equipment sales are not in this number). The multiplier is a data value; NX upgrades (#34) may
raise it. Because the coin sprite follows the final amount, a x14 Snail drop (56-84) already shows the gold coin.
Raw records: ignored `_scratch/t107_smoke/` and `_scratch/t107_base/`.

#### Spec #33 / #109 equipment drops regression smoke (2026-10-17)

No tuning: `ISOLATE=s33t109 bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`,
private real cache, no held-out seeds, on the ticket branch (base: the #107 integration branch). "Before" is the #107
smoke above. All 12 runs finished with no script errors and no world warnings. Henesys still reaches Magician
(4:20-4:41) and Mano in every bot run, and its random policy clears one of three; Tree remains record-only.

| Stage / policy | Clear / dead before -> after | End seconds seed 1/2/2026, before -> after | Equipment dropped per round (seed 1/2/2026) |
|---|---|---|---|
| Henesys bot | 0/3 -> 0/3 | 859/778/899 -> 834/784/917 | 5 / 5 / 7 |
| Henesys random | 1/2 -> 1/2 | C 995/462/346 -> C 980/462/543 | 7 / 0 / 4 |
| Tree bot | 0/3 -> 0/3 | 622/157/128 -> 622/156/128 | 2 / 0 / 0 |
| Tree random | 0/3 -> 0/3 | 747/158/88 -> 729/158/88 | 5 / 0 / 0 |

Every dropped item was picked up (`equips_collected` equals `equips_dropped` in all 12 records; the Equip tab never filled).
The runs diverge slightly from "before" because equipment drops use the shared drop-pop RNG stream and the sensible bot
walks to them like any other drop; the one Henesys random run that moved a lot (seed 2026) now dies at 9:03 instead of
5:46, after Mano. That is recorded as changed, not tuned.

Items per round: the chance (`equipment_drops.chance` 0.002 per ordinary kill) was sized once from an estimate, a full
Henesys clear being about 3,300 kills: 6.6 ordinary drops plus the 3 boss drops is about 9.6 items. The only Henesys clear
in the smoke (random seed 1, 3,069 kills, all three bosses) dropped 7 (3 boss + 4 ordinary), below the 8-12 target but
inside the Poisson spread of about 6; the sensible bot's deaths at 13-15 minutes (1,300-1,900 kills, two bosses) dropped 5,
5 and 7. The value is data (`game/data/survivor/equipment_drops.json`) and is not tuned further here; the dedicated
balance pass owns it. The character baseline golden changed only by the new equipment pickup events: with `chance` and
`boss_drops` set to 0 the #107 hash `08f7edf3...` is reproduced exactly. Raw records: ignored
`research/spec33/t109/balance/` (outside the repo).

#### Spec #33 / #112 bot shopping regression smoke (2026-10-17)

No tuning: `ISOLATE=s33t112 bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1> --policy=<bot|random>`
plus `--tier=2 --policy=<bot|random>` chains, private real cache, no held-out seeds, on the ticket branch (base: the #111
integration branch). "Before" is the #109 smoke above. All 14 runs finished with no script errors and no world warnings.
What changed for the bots: they now wear the best item they own at each equipment pickup, level-up and job change
(`BotShop.auto_equip`, weights in `balance.bot.equipment_weights`), ignore equipment drops while their Equip tab is full,
and visit the shops between tiers of a chain. Henesys still reaches Magician (4:20-4:41) and Mano in every bot run; Tree
remains record-only.

| Stage / policy | Clear / dead before -> after | End m:ss seed 1/2/2026, before -> after | Items put on mid-round (seed 1/2/2026) |
|---|---|---|---|
| Henesys bot | 0/3 -> 0/3 | 13:54/13:04/15:17 -> 20:14/14:40/22:16 | 4 / 4 / 4 |
| Henesys random | 1/2 -> 1/2 | C 16:20/7:42/9:03 -> C 16:28/7:42/10:59 | 7 / 0 / 3 |
| Tree bot | 0/3 -> 0/3 | 10:22/2:36/2:08 -> 10:26/2:36/2:08 | 2 / 0 / 0 |
| Tree random | 0/3 -> 0/3 | 12:09/2:38/1:28 -> 20:23/2:38/1:28 | 5 / 0 / 0 |

Wearing what drops is the only gameplay change inside a round, and it moves the long runs a lot: the Henesys sensible
bot now dies 2-7 minutes later in all three seeds (every run still dies, after the second or third boss; two reach the
third), and the Tree random seed 1 run, which wore five items, survives to 20:23 instead of 12:09. Runs that never found
equipment (Tree seeds 2 and 2026, Henesys random seed 2) are unchanged. This is recorded as changed, not tuned; the
balance pass owns the effect (#77).

Chains (`--tier=2`, seeds 1/2/2026, Henesys then Dark Cave): bot 0/3 tier-1 clears (deaths 20:14, 14:40, 22:16), so no
shop visit; random 1/3 (seed 1 clears at 16:28, Lv 41). Seed 1's Free Market visit: 323,932 mesos earned, nothing to
sell, 9 scrolls bought for 315,000 (8,932 left) and all 9 read (3 succeeded, 6 failed, 0 items destroyed); tier 2 starts at Lv 41
and dies at 22:04 at Lv 62 after 1,397,158 more mesos and 2 more items put on. The record keys are `equips_worn`,
`equipment_worn`, `scrolls_on_worn` per round and `shop` on the round that precedes a visit (see the `scripts/balance.sh`
header); the summary adds "shop ... per visit" lines. Only one visit happened in the smoke, so the small-sample caveat
of the tier-2 feed applies. `BotShop` has seeded unit tests for the plans, the visit bookkeeping (a careless visit with dark
scrolls keeps its books across 12 seeds) and a two-tier chain (`test_bot_shop`, `test_balance_chain`). Full suite: 1041 tests,
4 failures, all the known #103 key-config tests that read the developer's own `settings.cfg` (unrelated).
Raw records: ignored `research/spec33/t112_balance/` and `t112_smoke.log` (outside the repo).

#### Spec #33 / #113 combined regression smoke for the whole spec (2026-10-17)

No tuning, no held-out seeds: `ISOLATE=s33t113smoke bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1>
--policy=<bot|random>` plus `--tier=2 --policy=<bot|random>` chains, private real cache, on the #113 branch (base: the
integration branch with #105-#112 merged). This covers the UI tickets that skipped their own smoke (#108 windows,
#110 scrolls, #111 shops); "before" is the #112 smoke above. All 14 runs finished with no script errors and no world
warnings. The results are **identical to #112 run for run** (same end times, same mesos and equipment counts): #108,
#110, #111 and #113 change no sim rule a bot run exercises (the windows are held-run UI, scroll and shop rules run
only when a bot or the player visits a shop), so a different number would have been a bug. Henesys bots still reach
Magician (4:20-4:41, 6/6 runs); Tree remains record-only.

| Stage / policy | Clear / dead | End m:ss seed 1/2/2026 (same as #112) | Mesos earned per round (seed 1/2/2026) | Equipment dropped (seed 1/2/2026) |
|---|---|---|---|---|
| Henesys bot | 0/3 | 20:14 / 14:40 / 22:16 | 211,036 / 101,766 / 206,066 | 5 / 5 / 7 |
| Henesys random | 1/2 | C 16:28 / 7:42 / 10:59 | 323,932 / 18,298 / 72,898 | 9 / 0 / 4 |
| Tree bot | 0/3 | 10:26 / 2:36 / 2:08 | 208,558 / 3,108 / 1,680 | 2 / 0 / 0 |
| Tree random | 0/3 | 20:23 / 2:38 / 1:28 | 433,930 / 2,520 / 1,218 | 5 / 0 / 0 |

Every dropped item was picked up except one (Henesys random seed 1 dropped 9 and picked up 8: one was still lying
on the ground when the round ended). Items per round: the Henesys bot runs, which last 14-22 minutes and kill 1,300-2,100 monsters, dropped
5-7 against the 8-12 target for a clear, and the one real clear (Henesys random seed 1, 3 bosses) dropped 9, inside
it. Recorded, not tuned (#77 owns `equipment_drops.chance`). Mesos per round on Henesys: 100-210k for a bot dying at
14-22 minutes, 324k for the clear (the owner's 300-350k target for a clear).

Scrolls (only the chain's one Free Market visit, Henesys random seed 1): 323,932 mesos earned, nothing to sell, 9
scrolls bought for 315,000 (8,932 left) and all 9 read: 3 succeeded, 6 failed, 0 items destroyed (the careless plan
reads dark scrolls too, none destroyed this time). Tier 2 then started at Lv 41 and died at 22:04 at Lv 62 after
1,397,158 more mesos, 5 items dropped and 2 more worn. The sensible bot never cleared tier 1, so no sensible shop visit
happened in the smoke (`test_bot_shop` covers it with seeded tests). Chains: bot 0/3 tier-1 clears, random 1/3.

Full suite on the branch: 1,042 tests, 4 failures: the known #103 key-config tests (`test_key_config`,
`test_key_config_window` x2, `test_teleport`) that read the developer's own `settings.cfg` (their Teleport key
shows "Space" there); nothing else, 0 SKIP with the real cache. Raw records: ignored `research/spec33/t113_balance/`
and `t113_smoke.log` (outside the repo).

#### Spec #33 / #113 whole-loop flow-driver run (2026-10-17)

`--scenario=economy` (AGENTS.md; header of `flow_driver.gd`) drives the loop with injected input on the real cache and
checks it at every step: the picked-up mesos and items, the Item window and tooltips, the hat worn by double-click,
a real tier-1 Henesys clear by the bot's fixed-tick warp (the Lv38 F/P fixture, seed 1) into the Free Market with the
worn hat, the spare item and the mesos in the saved boundary, the four scroll NPCs, Space at El Moth (buy a 100% hat
INT scroll, sell the spare Dark Calas for 90,000) and at Tulcus (three 10% scrolls), the scrolls dragged onto the worn
hat (success, then a failure), and Save & quit -> Continue restoring mesos, equipment, inventory and scrolls from the
saved snapshot (550,461 mesos at the clear, 500,461 after shopping, all equal after Continue). The 25 screenshots were
looked at and the run reported `missing` empty (not committed: `evidence/spec33/t113/economy2/`).

#### #34 / #126 NX and Cash Shop QA: regression smoke and a full-account record (2026-10-17)

No tuning, no held-out seeds: `ISOLATE=... bash scripts/balance.sh 1 2 2026 --stage=<henesys_hg1|tree_that_grew_1>
--policy=<bot|random>` (private real cache), 12 runs per row set, on the #34 integration branch (all of #115-#122, with
B2's #105-#108 merged in). "Base" is the same smoke on `1d453b1`, the B2 integration tip without any #34 code, from a
`git archive`. **Empty account:** all 12 records are identical to the base's (every key compared; only `nx_awarded`,
`bosses_killed` and `levels_gained` exist only on the new side), and every end time equals the latest earlier smoke
(#107 above), so B3 adds nothing to a round without a pet or worn cash equipment; the #105-#108 gameplay difference to the
older NX / pet smokes is therefore B2's (mesos and the drop-chasing bot, #106 LUK), not B3's. No crash, script error,
world warning or missing asset in any of the 24 runs.

**Full account** (`--account=game/tests/fixtures/accounts/full_pet.json`: Brown Kitty, Auto HP/MP, Wing Boots, Binocular, VAC,
ALERT 50 % / 30 %; record only). Seeds 1 / 2 / 2026, the same bot, `pickups` = drops the pet collected:

| Stage / policy | Empty account (end time; Henesys random seed 1 clears) | Full pet account (end time, level) | Pet pickups | NX per run (empty / full pet) |
|---|---|---|---|---|
| Henesys bot | 14:19 / 12:57 / 14:59 | 17:55 / 20:19 / 16:15 (Lv 37 / 41 / 33) | 3235 / 4065 / 2292 | 245, 160, 245 / 260, 280, 240 |
| Henesys random | **clear 16:35** / 7:42 / 5:45 | 17:47 / 6:37 / 10:45 (Lv 38 / 12 / 17) | 3440 / 345 / 635 | 420, 65, 50 / 265, 55, 120 |
| Tree bot | 10:21 / 2:36 / 2:08 | 11:01 / 12:25 / 10:13 (Lv 24 / 23 / 23) | 3043 / 2883 / 2572 | 155, 15, 10 / 155, 150, 150 |
| Tree random | 12:27 / 2:38 / 1:28 | 15:24 / 5:05 / 4:54 (Lv 30 / 10 / 4) | 4634 / 486 / 81 | 220, 15, 10 / 225, 45, 15 |

Henesys still reaches Magician (257-283 s) and the first boss in every run, with and without the account; Tree stays
record-only. With the pet 10 of 12 runs live longer than without; the exceptions are Henesys random seed 2 (6:37 against
7:42) and seed 1, which no longer clears (it dies at 17:47 after two bosses; it did not clear on the integration tip
`25826a6` with this account either: 0/3 clears, deaths between 10:03 and 19:35, so that change is B2's, not this ticket's
pet placement fix). Chaotic, recorded, not tuned. The pet
drinks little (0-10 MP, 0-1 HP drinks a run) because the bot drinks first, as in the #119 record. Raw records: ignored
`_scratch/s126/{base,new,acct,int}/`.

**Flow-driver `account` scenario** (injected input only, 29 shots in ignored `evidence/spec34/126/account_flow/`): 11,000 NX
-> hat 4,000 + pet 4,900 bought at map select -> round 1 Equip window wears the hat and brings the pet out -> warp clear
(+430 NX, notice "You have gained 430 NX.", 2,530 NX saved) -> pet upgrade (Auto HP, 1,800) bought in the Free Market ->
Save & quit, Continue (still dressed, pet out) -> tier-2 map select shows 730 NX -> death (+30 NX, results row) -> slot freed,
account holds 760 NX and all three items -> a new character's shop lists everything as owned and its round's Equip window
wears the hat and brings the pet with Auto HP out. Round 1 is invulnerable (tier C): with the hat and pet the bot no longer
clears Henesys on seeds 1 / 2 / 2026 / 7 either (it has 0/3 clears there anyway), so a natural clear is not available
for the scenario; `--natural-clear=1` plays it as is.

**Real-game playtest** (`scripts/playtest.sh --account=game/tests/fixtures/accounts/full_cash_pet.json --speed=1 --minutes=2
--seed=2026`, ignored `evidence/spec34/126/playtest/`): a Beginner wearing a cash item in all 11 slots with Brown Kitty out and
every upgrade; no missing assets, 60 FPS, and the screenshots show the worn hat, outfit and accessories and the pet trailing
the character. Eye checks of the Cash Shop (equip and pet tabs, owned items in the Cash Inventory), the Equip window's
Cash tab and Pet page, the "+N NX" notice, the results row and the pet beside the character are the `account_flow/` shots.
**Two QA fixes** came out of this ticket: the CpH5 headband hair rule (section 11, "Cap hair cover") and the pet
standing on top of the character (section 11, "Pet in the round").

**After merging main (B2 #109-#113, 2026-10-17).** The same empty-account smoke (seeds 1 / 2 / 2026, both stages, bot and
random) on the merged branch and on main `3217429`: all 12 records identical on every key but the three #34 adds (end
seconds Henesys bot 1214.7 / 880.3 / 1336.6, random 988.8 / 462.0 / 659.3; Tree bot 626.9 / 156.6 / 128.3, random
1223.9 / 158.3 / 88.4), no world warnings. The merge makes a full Equip tab stop the pet too: it neither picks up,
VAC-pulls nor fetches equipment it has no room for (`test_pet_pickup`).

#### #76 ordinary mob attacks regression smoke (2026-10-17)

Feature smoke only, no tuning (AGENTS.md): `ISOLATE=t76*`, seeds **1/2/2026**, Henesys and Tree one-off rounds (bot,
random), the `--tier=2` chain (bot, random) and the Dark Cave Lv38 F/P fixture (`fp_arch_mage.json`, bot,
random); baseline = `6519b73` (a detached worktree), after = this branch. The only balance data added is the
`mob_attacks` block (tier C, section 11). Owner decision (2026-10-17): statuses on the character come only from bosses,
so ordinary mobs cast nothing and Jr. Boogie deals contact damage only; the earlier Seal implementation is gone, which
leaves the Tauromacis/Taurospear attacks as the only behaviour change. **Every Henesys, Tree and chain-tier-1 record and
summary is byte-identical (sha256) to the baseline, and so is every Dark Cave record in which no Tauro attack landed**
(fixture bot seed 1, fixture random seeds 1 and 2, chain bot, chain random seeds 2 and 2026). Records that differ all
have `mob_attack_hits` > 0 and first diverge in the 10:00 engagement window (`eng_by_min[9]`, centred on 10:00); the
first Tauro attack starts at 606-612 s in each of them (Tauros enter the pool at 10:00). No crashes, script errors,
world warnings or `missing` entries. Records gain `mob_attack_hits` only when nonzero (other rounds keep their bytes).

| Round group | End seconds before → after (seed 1 / 2 / 2026) | Zombie Mushmom (6300005) killed before → after | End level before → after | Landed Tauro hits after |
|---|---|---|---|---|
| Henesys, Tree (bot, random) | identical bytes | identical | identical | none |
| Chain tier 2 bot | no tier-1 clear, identical | — | identical | 0 |
| Chain tier 2 random (seed 1 only tier-1 clear) | 1259.9 → 1325.0 (seeds 2, 2026 identical) | 1/1 (388.9 s) → 1/1 (388.9 s) | 61 → 62 | 91 |
| Dark Cave fixture bot | 464.8 / 777.4 / 768.8 → 464.8 / 704.7 / 747.4 | 2/3 → 2/3 (405.5 s, 422.5 s) | 46 / 56 / 54 → 46 / 55 / 54 | 0 / 12 / 7 |
| Dark Cave fixture random | 343.5 / 430.2 / 895.4 → 343.5 / 430.2 / 859.4 | 1/3 → 1/3 (365.2 s) | 44 / 45 / 55 → 44 / 45 / 55 | 0 / 0 / 25 |

Every fixture round still dies, as before this ticket. Same fixture, bot, the other training seeds 3..14 (evidence only):
Zombie Mushmom killed **7/15 before and 7/15 after** over all 15 seeds (1, 2, 2026, 3..14); the eight runs that die before
the Tauros arrive are byte-identical, and the seven that meet them end 73 s earlier to 16 s later (seed 2 -72.7, 11 -52.4,
2026 -21.4, 12 -15.4, 3 -7.1, 7 +6.9, 10 +16.4) with 6-15 landed Tauro hits each. The two Tauros are a small difficulty
step for the Lv38 F/P fixture, well inside the noise of the 10:00+ phase; `mob_attacks` intervals and `dmg_mult` are the
levers for #77. Raw records: ignored `_scratch/t76/{baseline,rm,rm2,seedsearch_base,seedsearch_rm}/`.

**Playtest evidence** (ignored `evidence/t76/playtest_rm/`: `scripts/playtest.sh --stage=dark_cave --character=<the chain
seed-1 tier-2 start character> --seed=2260174940 --speed=1 --warp=590 --minutes=13.5 --shot-every=20`; the Lv38 fixture
bot reaches the Tauros in only some rounds, so the stronger chain character is used): the character
survives to 13:30 (Lv58) with up to 292 mobs alive. `mob_attack_windup.png` (10:07) shows Tauromacis with its crescent staff
raised (attack1) beside the character, `mob_attack_hit.png` the canonical lightning hit art over the character,
`t620.png` Jr. Boogies standing among Evil Eyes and Tauros with no cast animation, and the buff row shows only the
character's own Cleric buff icons in `t620.png`/`t780.png`: no status icon, no padlock anywhere. `summary.json` `missing`
is `[]`. A pre-existing tool issue: when the character dies during `--warp`, the warp drops the death event and
`--quit-after` counts run time, so the window never quits (use a character that survives, or no warp past its death).

**Performance** under load: Dark Cave, the chain tier-2 character (Lv41 Cleric), seed 2260174940, god mode so both
versions reach 13:00 with 200+ mobs, **Tauros included** (HEAD: 142 Tauromacis/Taurospears alive at 13:50, 771 attack
starts in the measured window). Old = `6519b73`, HEAD = this branch, runs interleaved on the same machine with other
agents' Godot processes running (so ±20% run-to-run noise). Headless probe: the sim warped to 13:00 with BotInput, then
3000 ticks (50 s) timed. "HEAD, attacks off" sets `MobAttacks._any = false`, which leaves the game state identical to
the old code (296 mean / 312 max alive, Lv58, same kills), so it isolates code overhead from game-state differences.

| Whole `RunWorld.step`, µs per tick (mean of 3000 ticks) | Run 1 | Run 2 | Run 3 | Run 4 |
|---|---|---|---|---|
| Old `6519b73` (296 alive) | 3139 | 3193 | 3812 | 2921 |
| Old, second batch (interleaved with the inlined HEAD) | 3457 | 3581 | 3619 | |
| HEAD, attacks off (same state as old) | 3623 | 4359 | 3599 | |
| HEAD, before the inlining (290 alive, 142 Tauros) | 2470 | 2685 | 2383 | 3055 |
| HEAD (290 alive, 142 Tauros; `MobAttacks.step` inlined) | 2596 | 2742 | 2945 | |

| `MobAttacks.step` alone, µs per tick | Run 1 | Run 2 | Run 3 | Run 4 |
|---|---|---|---|---|
| HEAD before inlining `can_act` and the view test | 200 | 219 | 190 | 246 |
| HEAD after (`perf(sim): inline ...`) | 121 | 132 | 139 | |

Reading: same-state HEAD costs the old code's step within noise (3.6-4.4 ms against 3.5-3.6 ms; the loop returns
at once when no mob has an attack). With the attacks on, the world differs (HEAD ends with 142 Tauros alive against 103; the cheaper
2.6-2.9 ms step is probably mobs held in their attack stance, not measured) and the attack loop itself costs **121-139 µs per tick, 4-5% of the step** at 142
attackers on screen (it was 190-246 µs, about 8%, before `can_act`, `is_live` and `Rect2.has_point` were inlined; the loop
output is unchanged, all 12 Dark Cave and chain-random records are byte-identical before and after). The same-state
HEAD readings (3599-4359) sit within the spread of the old code across batches (2921-3812) plus one slow reading, so
the code overhead is not distinguishable from run-to-run noise; no measurement shows the attack feature costing more
than the attack loop's own 4-5%. Windowed (`--vsync=off`, `--warp=720 --minutes=15`, so 720-900 s drawn, a
scratch-worktree-only `world.god` switch), same seed and character:

| Windowed, 12:00-15:00 (max alive 331 in all four) | `frame_work_us` avg / p95 | `sim_us_per_tick` | `frame_ms_200plus` p95 (frames) |
|---|---|---|---|
| Old, run 1 | 1966 / 5152 | 2618 | 7.03 ms (48315) |
| Old, run 2 | 1616 / 4216 | 2183 | 5.59 ms (57586) |
| HEAD, run 1 | 1872 / 4623 | 2226 | 6.20 ms (51481) |
| HEAD, run 2 | 1844 / 4600 | 2179 | 6.15 ms (51921) |

The two versions overlap (old 1616-1966 µs against HEAD 1844-1872 µs average frame work); `missing` is `[]` in all four.
Raw: ignored `evidence/t76/perf3/`, `_scratch/t76/perf_probe_runs*.txt`, probe `_scratch/t76/probe/perf_load.gd`.

**Regression smoke, merge of #288/#290 with #289/#291/#292 (`merge/288f`).** Henesys seeds 1/2/2026, no crash, no warnings,
`missing` empty; no tuning, no held-out seeds. Bot: 3 DEAD on map 2 at 6:39 / 6:17 / 6:18, Lv 22 / 17 / 19. Random: 3 DEAD on map 1
at 5:07 / 5:10 / 5:08, Lv 11 / 11 / 12. No clears or timeouts.

### 4.3 Boss encounter lifecycle (difficulty overhaul)

Each map schedules one boss 300 seconds after that map's entry, with the order in section 4.1: Mano (2220000),
Mushmom (6130101), Blue Mushmom (9400205) in Henesys; Stumpy, King Slime, Dyle in Ellinia; Mano, Stumpy, Iron Hook
(4090000) in Perion; King Slime, Shade (5090000), Dyle in Kerning City; Zombie Mushmom, Snack Bar, Jr. Balrog in
Sleepywood. Only the current map's boss is armed. If map 2 starts at round time 420 s, its boss is due
at 720 s. Encounters retain canonical movement, contact attack, art and enabled skill kits; mushrooms retain the slam.
Each boss gives a 3 s warning, then arrives with the normal regen fade on the player's reachable platform, preferably
250 px away. A narrow floor may require a closer point. If no arrival point exists at all on the arrival tick, the
arrival slips by 3 s behind a fresh warning (tier C). Slipping is bounded (#260): once arrivals have failed for
`balance.bosses.arrival_fallback` = 15 s (five slips), the floor point nearest the player stands in for the player
(its platform, the same 250/150 px rule, else that point itself), still 3 s after the last warning; a stalled-pursuit
fade relocation that finds no point uses the same bound (tier C). A boss whose mob img is missing from the asset cache is skipped
with a run warning at its arrival time and never blocks the clear. Scheduled bosses never flinch or receive push,
whatever their WZ `info/boss` flag (tier C survivor rule; the tier A flag and the `no_flinch` override still apply to
their kinds), and ordinary relocation never removes them. Bosses the player runs away from remain until killed.

Survivor settings (tier C; canonical stats and attack timings/boxes remain unchanged):

| Boss | Canonical HP | Survivor HP | HP multiplier | Touch multiplier | Attack multiplier |
|---|---|---|---|---|---|
| Mano | 2,000 | 3,600 | 1.8 | 1.15 | — |
| Mushmom | 20,000 | 4,800 | 0.24 | 0.85 | 0.55 |
| Blue Mushmom | 200,000 | 7,000 | 0.035 | 0.48 | 0.72 |
| Stumpy | 7,000 | 3,150 | 0.45 | 0.83 | 0.77 |
| King Slime | 8,000 | 8,800 | 1.1 | 1.36 | 1.06 |
| Dyle | 31,000 | 8,060 | 0.26 | 1.14 | — |
| Perion: Mano | 2,000 | 3,600 | 1.8 | 1.15 | — |
| Perion: Stumpy | 7,000 | 4,800 | 0.6857 | 1.38 | 1.25 |
| Perion: Iron Hook | 2,200 | 7,000 | 3.1818 | 2.38 | — |
| Kerning City: King Slime | 8,000 | 3,600 | 0.45 | 0.78 | 0.61 |
| Kerning City: Shade | 4,800 | 4,800 | 1.0 | 1.04 | — |
| Kerning City: Dyle | 31,000 | 7,000 | 0.2258 | 1.15 | — |

The Perion and Kerning City entries (spec #253, starting values, untuned) are separate entries, so the Henesys and
Ellinia fights are unchanged. Each matches the Henesys boss of its map slot (Mano, Mushmom, Blue Mushmom) at that
slot's `typical_hp`/`typical_pdd`: the same survivor HP and, at 0.01 multiplier steps, touch and attack roll ranges
within 1 HP of the slot's (King Slime's slam matches Mano's touch, since Mano has no attack). Iron Hook and Shade
fight by touch only. Canonical boss defence, level and undead flags are not normalized (Iron Hook PDD 400 and Shade
undead against Blue Mushmom's 810 and Mushmom's 320). Shade's entry carries `skill_intervals: {"129": 15}`: one
Banish per 15 s instead of the canonical 3 s.

Calibration uses measured training builds rather than the former assumed HP300/550/800 and full Armor defense.
`stage.maps[].boss` stores the multipliers; `typical_hp/pdd` are illustrative inputs only, never adaptive runtime scaling.
The target is typical whole-hit source medians of 40–50%, with individual-hit/build variation reported separately.
At the documented `typical_hp`/`typical_pdd` the whole roll range of every contact hit and selected attack (85% and
100% of PAD after defense, rounded) lies in 40–50% (`test_boss_hit_bands`). The 2026-10-14 review pass moved six
multipliers by the smallest 0.01 step that does this (Blue Mushmom slam 0.70→0.72, Stumpy touch 0.8→0.83 and
attacks 0.74→0.77, King Slime touch 1.4→1.36 and slam 1.1→1.06, Dyle touch 1.15→1.14; medians moved at most 1.8
points); the measured results in 4.2 predate this change.
Completed fights target 30/60/90 seconds, each ±50%; unfinished encounters are not zero-duration observations.
`balance.bosses` stores warning time, placement and spawn reduction. The mobs a boss summons (MobSkill 200 at the
levels its `info/skill` lists) and its `info/revive` list are read from the canonical data at load time (`StageRoster`)
and loaded with the stage; `stages.json` never repeats these v83 lists.

While any boss lives, normal spawns run at half rate (spec). Bursts count as normal spawns, so both the steady spawn
rate and each burst's count halve (`balance.bosses.normal_spawn_mult` 0.5, burst count rounded; tier C reading of
the spec); elite scheduling stays independent.
Stages continue the last rate/max-alive/HP/speed keyframe slopes at quarter pace after curve time 15:00
(`post_duration_slope`), with ordinary mobs still capped by `hard_cap`. Burst size keeps its 10→40 slope over the
stage at the same quarter pace past 15:00, and the elite interval shrinks in proportion to the extrapolated spawn rate
(`every × rate(15:00) / rate(t)`), so elites stay the same share of the growing stream until the clear (tier C). Clearing requires every scheduled boss dead;
stages without a boss list retain their duration clear. Stage select states the applicable objective.

If a living boss has no route or makes no progress toward the player for 5 s, it fades out over 300 ms, then
relocates about 250 px away on the player's platform using the same placement policy. HP is preserved; it stands
still and cannot touch during fade-out or the normal 300 ms arrival fade. Progress means closing the route distance
by at least 1 px through its own movement; a boss already at the player does not relocate.

Boss deaths replace ordinary drops with a shower totaling rounded canonical boss EXP × survivor reward multiplier
(×5), split into 12 drops with no remainder lost, spread ±120 px. Every scheduled boss also drops exactly two
equipment items (`equipment_drops.boss_drops`, tier C, owner 2026-10-21, spec #237), selected from the top third of the
tier's drop band (`boss_top_parts`, #292) on stream 10. Boss rewards contain no potions. Each death
also grants one bonus upgrade pick, before any queued normal level pick, with no level gain or queued-level
consumption. Each map clear waits for the choices to finish. On maps 1 and 2, combat freezes on the boss death, all pickups
are swept once using the finale rules below, and leftover mobs vanish without drops or kill credit. After every
choice is answered the clear notice and fade lead to the next map; no damaging tick runs in between.
The third map settles the final clear. The bonus window reads "Boss Reward" and has no gained-level
header. All reward and relocation values are tier C in `balance.bosses`; a schedule entry's `rewards` may override
reward defaults for tuning.

Finale settlement (MS-07/MS-08, tier C owner choices, 2026-10-21): **clear wins** once every scheduled boss is dead
and all mandatory choices are answered. No subsequent monster, projectile or contact-damage tick runs. Death in
the active tick that kills a boss still wins, including a kill that queues an unanswered reward; ordinary earlier
deaths are unchanged. **Collect everything** then sweeps every remaining map pickup, ordinary and boss alike,
independently of distance, height or current attraction: EXP, mesos and equipment (the complete
set of current pickup kinds). They use ordinary pickup accounting and equipment auto-wear, exactly once. Swept EXP
opens the normal level/job/advancement/card queue; combat and simulation time remain frozen through those answers.
Only then does the clear complete and produce the outgoing CharacterSnapshot. Job grants can spill equipment;
settlement retries the remaining pickups after the resulting choices too. No live map or settlement state is saved.

The existing full Equip tab rule remains the capacity exception: a blocked equipment instance stays on the ground,
emits the usual `pickup_blocked` / `inventory_full` notice and is left behind when the clear finishes. Settlement
does not overflow the tab, sell or replace equipment, or wait indefinitely for space. Other drops are still credited.
EXP cap absorption continues to conserve the full value; settlement collects the merged value without expiry.
Quit round during a settlement choice retains the original round-boundary character and seed; Continue replays
that start. A completed non-final clear saves the fully settled character in the hub, so Continue never pays it twice.

Presentation uses the original `UIWindow.img/MobGage` icon frame, gauge borders and colour strips, centred below
the timer; multiple surviving bosses keep separate rows. Names come from `String.wz`, HP comes from the swarm,
and colour indices come from canonical `info/hpTagColor` and `info/hpTagBgcolor`. Blue Mushmom lacks a v83 icon and
colour tags, so survivor `mobs.json.boss_ui` borrows Mushmom's icon and 1/5 colours (tier C). King Slime keeps its
canonical icon but receives the missing 1/5 colour tags (tier C). No WZ metadata is modified.
Warnings say "<name> will appear in 3 seconds!"; arrival replaces the warning with yellow "<name> has appeared!"
and the original `BasicEff.img/Summoned` effect at the boss. Selecting this effect and positioning the notices is
tier C; the effect frames, origins and 80 ms delays are tier A. Keyed notices sit above EXP and low-MP messages,
expire after the warning lead or 4 s after arrival, and cannot be evicted by EXP pickup traffic.

Mushmom and Blue Mushmom select their canonical `attack1` type-0 jumping attack: attack-local PADamage 300,
500×150 range (-250,-150) through (250,0), impact at `attackAfter = 1050 ms`, and `effectAfter = 0`. The boss holds
its captured ground anchor/facing during the 1.85 s stance (tier C anchoring); the apparent jump comes from the
original frame origins. The range mirrors with facing. A player body inside the captured area at impact takes the
physical hit through `take_hit`; when `jumpAttack` is set, being airborne at that moment avoids it (lore, tier C).
Leaving the area during the windup also avoids it. A boss killed before impact cannot finish the attack.
An intentional attack/skill stance resets pursuit stall rather than causing a teleport; a fading boss cannot
begin another action (tier C action/teleport coordination).
Windup art, sound and effect use original timings. The effect's ground-wave frames begin at 1.10 s, 50 ms after
the damage impact; neither timeline is retimed to conceal this canonical difference. Selected attacks repeat at
an initial 8 s start-to-start interval when in range and the shared action gate is free (tier C; WZ has no interval).

Slam scaling is separate from touch scaling because both mushrooms' slam attack is 300 while their contact attack
is 200 / 450. Mushmom and Blue Mushmom use separate attack scales 0.55/0.72 and contact scales 0.85/0.48,
calibrated against actual training HP pools. No attack-local canonical value is changed to achieve those fractions.
The `player_hit.source_kind` field distinguishes contact (`touch`) from these attack (`attack`) hits for metrics.
The handler is reusable for later Stumpy and King Slime type-0 attacks selected in their stage data.

Ellinia schedules Stumpy (3220000) in The Tree That Grew I, King Slime (9300003) in The Forest of Wisdom and
Dyle (6220000) in The Forest of Evil I, each 300 s after entering its map. Earlier fights extend total round time.
Stumpy uses HP ×0.45 (3,150), touch ×0.83 and attack ×0.77. Its selected attacks share an 8 s start-to-start cadence. The type-0 slam
keeps the 543×172 box and 1,500 ms attackAfter, including the same airborne dodge.
The type-2 ball keeps attack135, bulletSpeed140, range/r200, muzzle(6,-60) and 1,320 ms attackAfter. We adopt
`r ×600/bulletSpeed` ms maximum flight (857.14 ms), hence 233.33 px/s over 200 px. This conversion and using r
for acquisition/travel are tier C, inspired by the prose CMob comment in the later-client reference
`HaCreator/MapSimulator/Combat/MobAttackSystem.cs: ResolveProjectileTravelTimeMs`; that comment alone is not
verified v83 RE. Aim is at the current player body centre on launch; flight is straight, ignores terrain and
hits a swept body box grown by 8 px (tier C, survivor data). A ball is consumed on contact even if damage is
blocked or misses. Animation frames, origins, delays and sound remain canonical.
Stumpy's heal114/15 uses canonical HP gate80%, interval30 s and effectAfter1,500 ms. Following the spec ("restoring
the canonical amount"), each living mob in the canonical area regains exactly the canonical x (700), clamped to its
max HP; there is no random roll. The canonical y (200) is unused: its role in the v83 client is unverified (tier C;
an earlier build rolled uniformly between y and x after a later-client reference resolver). The original
mob0 effect retains its 1,100 ms blank lead-in; it plays from cast, while HP restores at the application delay.
The heal notice reports actual restored HP, and the boss bar follows it immediately. No reference source code
was copied. Encounter scaling is survivor data; all heal bounds, gates, intervals and effect timing stay canonical.

King Slime keeps canonical maxHP 8,000, touch 130 and slam 165. Survivor HP ×1.1 gives 8,800; touch ×1.36
and slam ×1.06 are separate training-calibrated scales. Its type 0 slam
uses canonical attackAfter 900 ms, effectAfter 300 ms, 500×150 area and jumpAttack 1; grounded players in the area
are hit only at impact, airborne players can dodge. Skill 200/2 waits 50 s, HP ≤50%, summons the original three
210100 Slimes with summonEffect 3, and caps living encounter-owned summons at 15. Its eleven-entry info/revive
list spawns eleven ordinary canonical Slimes on death, independently of that cast limit. Relocations preserve
ownership and fresh slots reset it. King Slime lacks info/boss and hpTag colours in v83: the survivor no_flinch
override and existing 1/5 MobGage colour override supply scheduled-boss behavior without modifying WZ facts.
Dyle retains canonical maxHP 31,000 (survivor ×0.26=8,060) and touch 190 (survivor ×1.14).
Heal 114/17 uses HP ≤90%, interval 20 s and effectAfter 0: restoration occurs on the casting tick. Each cast
restores the canonical x 5,000 (y 500 unused; tier C, the same rule as Stumpy), clamped at max HP.
Immunity 140/8 uses HP ≤80%, interval 30 s and duration 5 s. We interpret this as self
weapon immunity (tier C): basic swings and Three Snails shells are blocked at live impact time; magic remains
effective. A blocked shell consumes a contact/pierce hit without damage or crit RNG consumption (tier C).
The original repeat 1/pos 2 34×34 icon with origin (17,44) stays above Dyle's body and follows relocations;
body-top anchor mapping is tier C, art/origins are tier A. Status stops at expiration or death, never leaks
into a reused pool slot. Dyle's canonical 112/113 defense skills reuse the existing handlers; since #255 his 110/2 Attack Up (interval 35 s,
30 s, ×1.15 weapon attack in its area) casts too, listed before 112/113 in his skill list.
Death offspring use survivor summon_spacing 24 px on the death platform, with no new per-entity Nodes.
Source facts are the owner's original Mob.wz/9300003.img, Mob.wz/6220000.img and Skill.wz/MobSkill.img;
Local reference summaries: research/stage-bosses/out/bosses_3220000_5220002_9300003.json (King Slime),
bosses_5220000_6220000_8130100_3300008_3300005_9500326_9300187.json (Dyle), and the context mob-skills.txt.
Dyle's Tree Branch EXP icon is a tier-C existing stage icon, not a claim about its original drop table.

The balance harness continues until death/clear or `balance.run_time_cap` (initially 30:00, CLI `--cap` override).
An unfinished capped run is `TIMEOUT`, separately counted from deaths. Records include each boss's spawn/death
times and landed boss hits with whole damage, HP at impact and the damage/HP fraction. No survival/pacing claim
follows from the calibration table alone.

#### Additions beyond the spec (kept)

The spec (issue #1, tickets #3-#27) does not ask for these; each is kept and recorded here with its reason.

- **Per-boss `attack_interval`, `attack_dmg_mult` and `rewards` overrides** (tier C): WZ attack nodes carry no
  interval, so the 8 s cadence is ours; a slam's PAD differs from the contact PAD (300 against 200/450), so it needs
  its own scale to land in the 40-50% band; reward overrides can change EXP and its shower geometry.
- **`balance.bot.card_scores`** (tier C): the sensible bot learns and ranks Magic Guard before another attack (scores
  110/109), as a sensible player facing 40-50% boss hits would; the careless policy stays uniform. Since #63 the
  override replaces only the base score: the sensible bot adds `bot.gain_step_score` per step an offered card grants beyond
  its first, still with no job bonus.
- **Retuned survivor EXP curve** `4 + 15L + 3.8L²` (tier C): V27 kept the Magician's exact 980 EXP cost (Mage near
  3:00) while the quadratic term carries the late game toward Lv 30 at 12:00-15:00 (section 5, 4.2).
- **Boss defense buffs reach ordinary mobs** (tier A area and values, tier C arithmetic): MobSkill 112/113 are v83
  area buffs (`lt`/`rb`), so Mano's, Stumpy's and Dyle's casts give their flat PDD/MDD to every living mob inside the
  canonical area for the canonical time, boss or not.
- **Extra events** (`boss_attack`, `mob_projectile_spawned`/`_hit`, `mob_healed`, `mob_revives_spawned`,
  `boss_teleported`, `potion_tier_up`, `mp_short`, `buff_cast`/`_expired`/`_pulse`): presentation and metrics seams of
  the specced systems with no gameplay effect of their own (schema in ARCHITECTURE.md 4.4.3).
- **Playtest default length 30:00** (tier C tooling): `scripts/playtest.sh` allows time for the three entry-relative
  boss waits and their fights, ending at death, clear or the cap; documented in AGENTS.md and the script header.

## 5. Experience and levels

**There is no MP (ADR 0006, #285).** Skills are gated by their cooldown only: no MP pool, costs, MP-short state, MP
potions, Magic Guard, MP Eater, MP Recovery, the pet's Auto MP Potion Pouch or the MP ALERT. The HUD's v83 MP gauge is
drawn empty, and the Stat window's baked MP row stays blank.

Potions are unlimited (spec #237): Delete/Q drinks HP by default, instantly even on a rope. The HP potion has a
cooldown shared by the player and pet: `balance.potions.cooldown: {"hp": 20}` seconds (tier C, owner starting value,
2026-10-21). Presses while cooling down do nothing and emit nothing. Windows pause the sim and freeze cooldowns; tier upgrades
keep the remaining time. No potion pickups or starter stock exist; RNG stream 7 stays reserved. Canonical
spec.hp restoration and the level schedule are unchanged. Cooldowns are never saved: each round,
including Continue, starts ready. Legacy snapshot potion stock is ignored, without a format bump.
Both card policies drink a potion only when the missing HP is at least half of one
current potion's canonical restore, capped at the max HP pool (`balance.potions.bot.min_restore_fraction`, tier C;
the cap is #229). The restore counts as at least `balance.potions.bot.pool_floor` (0.25, tier C) of the potion, so a
small pool never wastes a big potion; above that floor a sip may overflow a small pool by up to the guard's slack
(a drink must restore at least half of the lesser of the potion and the pool, or of the floor share).

**Automatic potion tiers (spec #225, #228).** No card changes the potion any more. `balance.potions.schedule` lists
`{level, kind, item}` steps (tier C, ours; sorted by level): HP Red (2000000) → Orange (2000001) at Lv 10, HP Orange → White (2000002) at Lv 25
(the MP steps went with MP, #285). When the character reaches a
level (level-up, including several levels in one tick), every step of that kind at or below it that the character
does not hold yet is applied in order through `PotionInventory.upgrade`: the remaining cooldown is kept, the current item drives canonical restoration and the HUD icon, a step never downgrades, and
an item without a restore spec is skipped. Nothing is stored: each level-up and each snapshot load re-scans the steps up
to the level, so a Lv 38 character derives White **silently** on
load, and legacy potion counts are ignored. Each applied level-up step emits the existing `potion_tier_up` event and the
HUD shows the v83 item names from String.wz, e.g. "Your Red Potions are now Orange Potions." (name + "s";
`balance.potions.plural_names`, `{"<item id>": plural}`, tier C, overrides it for names that are their own plural:
Unagi 2022003). The Power Elixir is not a
potion tier (it is the card filler, section 8).

**Researched steps (#229).** The schedule continues with the table of `docs/research/v83-potion-progression.md`
section 6 (tier C: items and recovery are tier A from the v83 `Item.wz`, the levels are our own reading of thin
sources): HP Unagi (2022003, 1000 HP) at Lv 40, then HP Ice Cream Pop (2001001, 2000 HP) at Lv 60 (the MP Pure Water
and Red Bean Sundae steps went with MP, #285). The Lv 60 step has no source for its level; it is an extrapolation
the spec lead accepted. Melting Cheese, Reindeer Milk, Sunrise Dew, Sunset Dew, the Elixirs and the dual-pool foods stay out. The
recovery of each item is read from its canonical `spec` (`Consume/0200.img`, `0202.img`; `DataRepo.potion_img_path`
picks the img from the id) and is never typed into survivor data; the items, icons, String.wz names and `Use` sounds
come through `asset_manifest.d/common.json` (Pure Water's sound is a canonical link to `02012002/Use`, resolved by the
importer). The current item drives the next drink, including when upgraded during a cooldown.
A cache imported before #229 has none of the four items: the sim skips an unresolvable step, so such a character
stops at White (no error, no notice; `build_setup` lists the absent entries in `missing`, so
re-run `scripts/import.sh` or the web re-import). The 1000 and 2000 point steps exceed most pools at their levels
(research section 6, "How the restores compare"), so the overheal is wasted by design; the bot's waste guard compares the
missing share with the restore **capped at the max HP pool** (`BotInput.worth_drinking`, tier C), otherwise a 2000-point
potion would never be worth drinking and the bot would never request a drink. The capped amount never counts as less than
`potions.bot.pool_floor` (0.25) of the potion, so a small pool never wastes a big potion (`test_bot_input`); setting `pool_floor` to 1.0 gives the pre-#229 guard back exactly.

The opening pool is the v83 Beginner's 50 HP (owner decision), the same for every job and every round. A level-up adds no HP (tier C). Every skill casts on its
cooldown from the first second (#285). Real-run sip restoration/waste is recorded
per event.

**The autoplay bot's card scores** (`balance.bot.card_scores` and `BotInput.card_score`, tier C; only the sensible policy uses
them, the careless policy chooses uniformly among the offered cards): learning a pool skill 100, ranking an owned one 74
(plus `gain_step_score` for the ranks beyond the first); the nine common passives score 66 (Might) down to 50 (EXP) for a
new one and 4 less for a rank, and once three actives are owned every global passive gets +20 so Might, Max HP and the
rest beat an ordinary rank (#293); a Mastery card is valued by the diminished effect of its rarity bonus at 100 points per
unit of effect; the Power Elixir scores its own filler value. These are the sensible player's priorities, not balance.
- Mobs drop their **signature Etc item** as an EXP pickup (icon from `Item.wz/Etc/0400.img/<id>/info/iconRaw`), with
  the classic drop pop (`Sound.wz/Game.img/DropItem`). Snail -> Snail Shell 4000019, Blue Snail -> Blue Snail Shell
  4000000, Red Snail -> Red Snail Shell 4000016, Shroom -> Mushroom Spore 4000011, Slime -> Slime Bubble 4000010,
  Pig -> Pig's Head 4000017, Orange Mushroom -> Orange Mushroom Cap 4000001, Green Mushroom -> Green Mushroom Cap
  4000012.
- Flyer EXP icons: Stirges use Stirge Wing 4000042, Flyeye uses Fly-Eye Wing 4000076, and Goblin Fire uses
  Firebomb Flame 4000081 as a tier C visual choice (not a claim about a canonical drop table).
- EXP value = the mob's canonical `exp` × 1.0 (× 5 for elites). Pickups within the magnet radius (90 px) fly to the
  player; collecting plays `Game.img/PickUpItem` and shows "+N EXP" in MapleStory's yellow system-message style.
- **Drops never expire** (owner decision 2026-10-14; `pickup.lifetime` = 0). At `pickup.max_active` (600), the EXP drop
  farthest from the player is absorbed into the new drop at the monster's death position. The combined EXP pops
  there with a fresh age, keeping the pool bounded and collection near recent kills; no EXP is lost.
- **Survivor EXP curve (#293, tier C):** `exp_to_next(L) = round(4 + 8 L^2)`, minimum 1 (`balance.json` `exp_curve` a=4,
  b=0, c=8: L1 = 12, L7 = 396, L49 = 19,212). The faster opening and steeper late cost are a first pass for six actives by
  about 5:00 and a clear at about Lv45-55 (4.1), not the frozen balance. The canonical v83 table
  (`data/canonical/exp_table.json`) is kept for reference and display only; historical curves and their measurements remain
  in section 4.2. Every round starts at Lv1 with 0 EXP.
- **Level up:** the game pauses, `Effect.wz/BasicEff.img/LevelUp` plays on the character with `Game.img/LevelUp`, then
  the upgrade window opens. Several level-ups in a row queue their windows.
- **Attributes and AP** (tier C, survivor choices): every round starts at STR 12, DEX 5, INT 4, LUK 4 with 5 automatic AP
  per level (`AutoAp`, `balance.player.ap_per_level`). The job's one AP row (`balance.player.ap.<job>`, nearest lineage
  row, section 9) names a primary stat and an optional secondary with a target curve: earned AP fills the secondary up to
  its target for the level, the rest goes to the primary (212: LUK target about level + 2, so INT is lower by the points
  moved to LUK). The split is recomputed from the AP earned and the level, so nothing about it is saved (the snapshot has no
  AP). A multi-level EXP award uses each intermediate level for its split; collection grouping does not change growth.
- **Stats per level** (tier C): the job's `balance.growth` row through its lineage adds Max HP per level (Magician line +12;
  there is no MP growth, #285). Level-ups raise max HP but add no current HP (`level_up_refill.hp` = 0, tier C owner choice
  for difficulty); equipment refreshes only clamp current HP to the computed maximum and never restore it. Magic skill
  damage uses the resulting INT. Per-job tables (`ap`, `growth`, the bot's equipment weights) resolve through the job's
  lineage, so a new job line is data rows only (planned v83 midpoints, tier B: Warrior +26 HP, Bowman and Thief +22,
  Pirate +25; rows are added when the line becomes playable).
- **Defense and avoid**: W.DEF and M.DEF sum the worn equipment's `incPDD` and `incMDD`, plus active defense
  modifiers. The default creation outfit is W.DEF 7 (3 + 2 + 2), M.DEF 0 (tier A, v83 Character.wz).
  Avoidability is DEX × 0.25 + LUK × 0.5 + equipment `incEVA` (tier B, pre-Big-Bang formula compilations).
- **Worn equipment (spec #33, #105)**: one equipment instance per equip slot (hat, top, bottom, overall, shoes,
  gloves, weapon, shield; an overall fills top and bottom; the shield, spec #151 #158, is described below). Every worn `inc*` stat counts: main stats add to the base (the
  Stat window shows "total (base+bonus)"), W.ATT is `incPAD` summed over every worn item, M.ATT adds `incMAD`,
  accuracy `incACC` (shown, and it raises the critical chance, 6.1; no player attack ever misses), max HP `incMHP` (flat, after card
  modifiers, tier C; an item's `incMMP` does nothing and is not shown, #285), speed `incSpeed` and jump `incJump` capped at 140 / 123 (tier B).
  Equipping checks only `reqJob` (bit mask 1 Warrior, 2 Magician, 4 Bowman, 8 Thief, 16 Pirate; 0 all): `reqLevel` and
  `reqSTR/DEX/INT/LUK` are ignored (#292, ADR 0006), and a failure changes nothing. The creation top, bottom, shoes and
  weapon are the first worn equipment with plain WZ stats; a character without a snapshot wears the first creation
  options (`Equipment.DEFAULT_OUTFIT`, tier A), and creation wears the job's `creation_weapon` (212: the Wooden Wand
  1372005, tier C). No weapon is needed to cast; a bare-handed character casts the same skills (6.1.1).
- **Shield slot (spec #151, #158)**: `shield` is the last of `Equipment.SLOTS`, filled from Character.wz `Shield`
  (109xxxx) with the same requirement check as any equipment (`reqJob` only), and its `inc*` stats
  (mostly `incPDD`/`incMDD`) count like any worn item. A two-handed weapon (`WeaponInfo.is_two_handed`: every weapon
  type from 140) never shares the hands with a shield: wearing one moves the worn shield to the Equip tab, wearing a
  shield moves a held two-handed weapon (`Equipment.displaced_slots`). When
  the Equip tab has no room for what moves, the change is refused with `inventory_full`, the v83 notice "You can't get
  anymore items." shows, and nothing changes. The Equip window shows the shield in its v83 SHIELD cell (right of
  WEAPON); the avatar draws the shield layers of the worn item. The snapshot gains no key beyond a `shield` entry in
  `equipment.worn` (a snapshot saved without one loads unchanged; a two-handed weapon beside a shield is invalid). The autoplay bot treats the shield as a slot: it wears a shield when its score beats what the change
  moves off (a two-handed weapon must beat the one-handed weapon plus the shield it displaces), and may scroll it last.
  Shield drops and scrolls are #159.
- **Scrolls (spec #33, #110)**: `Scrolls` (pure) applies a scroll to the item worn in an equip slot. Fit: `(scroll id
  / 100) % 100 == (item id / 10000) % 100` (tier A, the v83 id convention) and at least one upgrade slot. Roll 0-99
  below `info/success` adds every `inc*` of the scroll to the instance (`scrolls` + 1); success or not, `slots` - 1;
  a failed scroll with `info/cursed` (the dark ones: 50) rolls 0-99 below `cursed` and destroys the item. Rates, stats
  and `cursed` are the WZ values unchanged. In the game: 100%, 60%, 10% and the dark 70% / 30% scrolls of the families
  below; event 65% / 15%, 50%, the "strong" 100%, Balrog's, Chaos, Clean Slate, White and other classes' weapon
  scrolls are out. Scroll stacks live in the character's `scrolls` map ({"<id>": count}); a stack holds at most
  `info/slotMax` (100 when WZ names none, as for every 0204 scroll) and the Use tab has 24 slots, all for scroll
  stacks (#239; potions occupy none). RunWorld adds `use_scroll(scroll_id, slot)` (the scroll is used up
  whenever it was read, `scroll_used` carries the result), `grant_scrolls` and uses RNG stream 11; stats and drawn
  look refresh through `equipment_changed` (action `scroll`).

  | Slot | Families (each: 100%, 60%, 10%, dark 70%, dark 30%) |
  |---|---|
  | Hat | DEF, HP, INT, DEX, ACC (2040016 is the 10% ACC scroll: its WZ `success` is the string "10", cast by the loader) |
  | Top | DEF, STR, HP, LUK, LUK (the newer series) |
  | Bottom | DEF, Jump, HP, DEX, DEX (the newer series) |
  | Overall | INT, DEX, DEF, LUK, STR |
  | Shoes | DEX, Jump, Speed, ATT (no dark ATT) |
  | Gloves | DEX, ATT, HP, Magic Att. |
  | Wand, Staff | Magic Att. |

- **Scroll shops (spec #33, #111)**: `Shop` (pure, static) works on a plain character state (`mesos`, `scrolls`,
  `equipment`: the keys of a CharacterSnapshot) and returns "" or a reason, changing nothing on a reason.
  `Shop.stock(npc, rules, scrolls.json, drop list, item info, job)`: the NPC's rates (shops.json) of every family whose
  item category (`(item id / 10000) % 100`, the scroll's `(id / 100) % 100`) some drop-list item the job can wear
  (`Equipment.job_allows`) belongs to, in file order, each priced by its slot. `buy` is all-or-nothing: `count` (below
  1), `mesos`, `use_full` (a stack stops at slotMax, the tab holds 24 scroll stacks; checked before
  any mesos are taken). `sell_equipment` / `sell_scrolls` pay `info/price` (`unsellable` without one, `no_item` for a bad
  index or too few scrolls); `sell_worn` is the refusal for a worn item (`worn`). RunWorld adds `shop_stock(npc_id)`,
  `buy_scroll(npc_id, scroll_id, count)` (also `not_sold` for a scroll outside the stock), `sell_item(index)` and
  `sell_scrolls(scroll_id, count)`, each success emitting `equipment_changed` (action `buy` / `sell`). The shop window
  (`ShopWindow`, with `ShopQuantity` and `ShopNotice`) and the Free Market's NPC placement are described in section 2.

## 6. Combat

### 6.1 Player damage

- **Fixed-damage skills** (Three Snails) deal the canonical `fixdamage` of their skill level (10 / 25 / 40) × survivor
  damage multipliers.
- **Magic skills** use the classic community formula (tier C; the v83 client formula is in packed code):
  `MAX = ((MAG²/1000 + MAG)/30 + INT/200) × spellAttack`, `MIN = ((MAG²/1000 + MAG×mastery×0.9)/30 + INT/200) ×
  spellAttack`, where `MAG = INT + magic attack`, `spellAttack` = the skill's canonical `mad`, `mastery` =
  (10 + 5×`mastery` field)%. Rolled uniformly.
- **Physical skills** use weapon bounds (tier B, SouthPerry/HS.net):
  `MAX = (mult × primary + secondary) × W.Att / 100`,
  `MIN = (mult × primary × 0.9 × mastery + secondary) × W.Att / 100`.
  Mastery defaults to 10%; a canonical mastery field N means (10 + 5N)%.
  Survivor skill and player damage multipliers scale these bounds. At impact apply `MAX - 0.5PDD` and
  `MIN - 0.6PDD`, each at least 1; roll uniformly, multiply by the canonical
  Skill.wz `damage` / 100, apply crit, element, then round once. Live PDD includes monster defence buffs.
  **No level gap (ADR 0006, #285):** the monster's level relative to the character changes neither the damage it
  takes nor the damage it deals, in either direction, nor any hit chance (the v83 `1 - 0.01 × (mobLevel -
  playerLevel)` factor is gone). No player attack misses (ADR 0005).
  `attackCount` gives the number of instant hit lines. Per-skill `physical_formula` overrides select primary,
  secondary, max/min multipliers and whether to ignore mastery: Lucky Seven is
  `{"primary":"luk","max_mult":5.0,"min_mult":2.5,"secondary":"","ignore_mastery":true}` (tier B).
- **Critical hits (#153):** every job can crit on fixed, magic and physical skill hits (owner decision, spec #151). Chance is
  `balance.crit.chance + ACC × balance.crit.per_acc + crit_bonus`, plus existing survivor crit modifiers.
  The untuned tier C coefficient is 0.0005 (+0.05 percentage points per ACC); base chance stays 0, multiplier 1.5.
  With a passive `crit_damage_bonus > 0`, its skill-percentage points add to the skill multiplier instead
  (`150% + 100 = 250%`, tier B Critical Shot/Throw); otherwise crit multiplies the hit by `crit_mult`.
  Skill crits use combat stream 1 (stream 5, the old basic-attack stream, is reserved). Crits use the `NoCri` digits and
  the `NoCri1/effect` burst. The Sharp Eyes common passive adds crit chance (8.5).
- Mob defence: magic damage × (1 - MDD/(MDD+150)) (tier C, keeps early mobs readable).
- **Player accuracy:** job base (tier B) plus equipment `incACC` and active buff `acc`, stored in `player_state.acc`
  and consumed by crit chance. The nearest listed job ancestor supplies coefficients: Beginner/Warrior/Magician
  DEX×0.8 + LUK×0.5; Bowman/Thief/Pirate DEX×0.6 + LUK×0.3; Brawler 510 DEX×0.9 + LUK×0.3.
  Player attacks never MISS (ADR 0005). Monster attacks still roll against player avoid (6.2).

### 6.1.1 No basic weapon attack, and weapons on the avatar

**The basic weapon attack is removed** (ADR 0006, #284): no swing, stab or shot fires on its own, `BasicAttack`, the basic
RNG stream (5, now reserved) and the ranged basic shot are gone, and a character with no skill ready does nothing. The job's
starting skill replaces it: Energy Bolt is in active slot 1 from the first frame and casts on its cooldown like every other
skill (section 7). The weapon a character holds matters for three things only: its canonical `incPAD`/`incMAD` and stats
(section 5), the way the avatar stands, walks and is drawn (below), and the reach envelope that `weapon_reach` skills of the
unported lines measure (`WeaponReach`, 7.8). `WeaponInfo.PHYSICAL` keeps the v83 weapon multipliers that a physical skill
of an unported line reads (6.1); they are no longer used by any playable job:

| Weapon | Swing / stab multiplier | Primary / secondary |
|---|---|---|
| 1H sword | 4.0 / 4.0 | STR / DEX |
| 1H axe, blunt | 4.4 / 3.2 | STR / DEX |
| 2H sword | 4.6 / 4.6 | STR / DEX |
| 2H axe, blunt | 4.8 / 3.4 | STR / DEX |
| Spear | 3.0 / 5.0 | STR / DEX |
| Polearm | 5.0 / 3.0 | STR / DEX |
| Bow | 3.4 / 3.4 | DEX / STR |
| Crossbow, gun | 3.6 / 3.6 | DEX / STR |
| Claw, Thief dagger | 3.6 / 3.6 | LUK / STR+DEX |
| Other dagger | 4.0 / 4.0 | STR / DEX |
| Knuckle | 4.8 / 4.8 | STR / DEX |
| Wand, staff, bare hands | 4.4 / 3.2 | STR / DEX |

A magic skill (every F/P skill) reads the wand's or staff's `incMAD` through the worn-equipment sum, never a weapon
multiplier (6.1). No weapon is required to cast: a bare-handed Arch Mage casts the same skills.

**Weapons on the avatar (#154).** The held weapon decides how the character is drawn, all from `WeaponInfo`:

- **Stances.** The character stands in `stand<info/stand>` and walks in `walk<info/walk>` of the weapon item
  (`stand_stance`, `walk_stance`; tier A). Most two-handed weapons have `stand2`/`walk2`; the two-handed swords stand with
  `stand2` but walk with `walk1`, so the two numbers are read separately. `PlayerMotion.stand_stance`/`walk_stance` hold
  them (`RunWorld._refresh_caster` refreshes them whenever the weapon changes), and `AvatarRenderer.play` turns the generic
  `stand1`/`walk1` into the worn weapon's variant for every screen that has no `PlayerMotion` (slots, shop, Free Market).
  Alert, jump, prone and the ladders are shared by every weapon.
- **Cast stances.** A skill plays its WZ `action` (or a tier C fallback) on the avatar; a wand or staff has `swingO1-O3`
  and `stabO1/O2` item layers that other casts reuse (`WeaponInfo.BASIC_ACTIONS` lists the stances per family, tier C: the
  item imgs list many more; `test_weapon_assets` checks each against the real cache).
- **Effects.** The afterimage name, the sound (`info/sfx`) and the impact timing come from the weapon item and its
  afterimage (tier A) wherever a skill of an unported line swings a weapon.

`scenes/debug/weapon_gallery.tscn` (tool-only; `bash scripts/run.sh res://scenes/debug/weapon_gallery.tscn --
--shots=<abs dir>`, `--mode=cash` a cash weapon cover over a two-handed sword and a claw) draws one sheet per family: stand and
walk facing both ways, and every stance frozen on its impact frame with the afterimage, spark and swing box.

#### 6.1.2 Ranged ammo (unported lines)

A bow, crossbow, claw or gun (`WeaponInfo.RANGED_FAMILIES`) fires ammo for the skills of the unported Bowman, Thief and
Pirate lines through `ProjectileSystem`: the shot carries the skill's physical damage, ends after the family's reach plus
`overshoot` (`survivor/ammo.json`), and **ammo is endless** (never consumed, stocked, carded, dropped or saved: the current
ammo is derived from the held weapon family, the job and the character level, `Ammo.item_for`). The current ammo's Item.wz
`incPAD` adds to W.Att for ranged attacks (`weapon_attack(true)`): Throwing Stars +15..+27, Bullet +10..+14, arrows +0..+4.
Starting ammo (tier A ids): claw Throwing Stars 2070015 (+15), bow Arrow for Bow 2060000 (+0), crossbow Arrow for Crossbow
2061000 (+0), gun Bullet 2330000 (+10). The upgrade schedules per branch (tier C levels, Gunslinger tier A) and how ammo
steps without branches are open until the first ranged job is ported (out of scope of #282); `Ammo.item_for` and
`weapon_gallery.tscn --mode=ammo [--branch=<id> --level=<n>]` keep working on the old tables.

### 6.2 Damage to the player

- **Monster hits** (tier C, the owner's chosen formula, unverified for v83): roll uniformly from 85% to 100% of
  the source monster's PAD (MAD for magic attacks), then subtract `floor(0.75 × player defense)` (W.DEF for physical,
  M.DEF for magic). Apply `(1 − elemental resistance/100)`, then explicit elite/boss damage multipliers, round once
  to the nearest integer and enforce minimum 1. There is no hidden scale or time-based damage multiplier.
  Ordinary mob attacks (#76) use this formula with the attack's canonical PADamage/MADamage (Tauromacis 320,
  Taurospear 390 MADamage) and `source_kind` `mob_attack`; contact is `touch`, boss attacks `attack`/`projectile`.
  Orange Mushroom PAD 42 versus W.DEF 7 yields 31–37; Green Mushroom PAD 82 yields 65–77, or 35–47 at W.DEF 47.
- **Avoid** (tier B, weakly sourced: a single owner-provided private-server wiki page, not corroborated): miss
  probability is `clamp(21.6 × player avoid / monster accuracy / 100, 0, 1)`; zero/missing accuracy disables the
  roll for synthetic data. A miss emits `player_hit` with `miss=true` and zero damage, draws the original violet MISS, and causes no knockback, invincibility or hurt expression.
- On a landed hit: `NoViolet` digits over the player, knockback 187.5 px/s away and a small hop (tier C), 0.3 s of no input,
  invincibility with blinking for the current hit window, 1.5 s for a lone hit and shrinking to 0.4 s in a swarm
  (#88, tier C; section 11).
- **Knockback guard (#223, tier C owner).** A hit that knocks the player back starts a guard of the first hit-window
  length (`balance.hit_window.lengths[0]`, 1.5 s; no new constant). Hits that land inside the guard (the shrinking
  window can end sooner) do their damage as usual (avoid roll, Power Guard, `player_hit`, damage number,
  window chain step) but call no knockback: no shove, no input lock, no new alert stance, and they do not restart the
  guard, which is counted from the last knockback, so a swarm pushes the player at most once per 1.5 s. A boss skill
  attack or ball (the hits that bypass the window) always knocks back and restarts the guard. A MISS changes nothing.
  The timer lives in `PlayerUpkeep` (`knockback_guard_t`, per round, not saved); `RunWorld.take_hit` asks it.
- There is no MP, so no Magic Guard split (#285): every landed hit's whole damage comes off HP.
- Regeneration is a 10 s pulse (tier B, the v83 cadence): +10 HP (tier C, owner choice), capped at the maximum.
  Interval and amount live in `balance.regen`. Recovery's separate timed HoT replaces the old passive
  regen card. Pulses continue on ropes and ladders; paused ticks do not
  advance the timer, and partial pulse intervals survive skill/card changes.

### 6.3 Damage numbers

`Effect.wz/BasicEff.img`: dealt = `NoRed1` first digit + `NoRed0` rest; crit = `NoCri1`/`NoCri0`; taken = `NoViolet`.
Digit advance overlaps per v95 RE (tier B); 400 ms hold, then 600 ms fade while rising 30 px. Multiple hits on one mob
stack upward one line per number: 30 px above a normal number, 36 px above a (taller) critical one.

### 6.4 Mano's canonical kit

Mano 2220000 reads its original info/skill list and MobSkill levels, with no copied canonical tuning in survivor data.
The first use waits one full interval after spawn. HP above the canonical hp percentage holds a ready skill until the
first eligible tick; an omitted hp means 100% (tier C default). Respawn fade blocks new skills until fully visible.
One skill at a time plays skill1 for its canonical 1.5 seconds, holding its grounded position/facing through the shared
BossDirector action gate (tier C scheduling). Colliding readiness uses the original info/skill order. effectAfter is
zero for all four Mano entries, so statuses apply when the action starts. WZ intervals, durations, bounds and frames
are tier A; the interpretations below are tier C where stated.

| Skill / level | Interval | HP gate | Effect |
|---|---|---|---|
| Slow 126 / 7 | 15 s | omitted → 100% | 15 s; rectangle (-300,-120)..(300,120) from boss feet; x80 retains 80% upgraded speed (tier C owner choice), refreshes rather than stacks |
| Summon 200 / 78 | 10 s | 90% | 2 Snails 100100, 2 Blue Snails 100101, 2 Red Snails 130101; at most 30 living summons belonging to that encounter |
| Weapon defense 112 / 1 | 10 s | omitted → 100% | 30 s; rectangle (-300,-200)..(300,200); x85 adds 85 W.DEF to living mob feet inside, including Mano (tier C arithmetic) |
| Magic defense 113 / 1 | 10 s | omitted → 100% | Same area/duration; x85 adds 85 M.DEF (tier C arithmetic) |

Defense refreshes without stacking; Mano's canonical PDD20/MDD30 stay unchanged in the shared kind. Basic attacks,
instant magic and in-flight projectiles all use the slot's current defense at impact. Status survives relocation and
is reset when a new mob reuses a slot. Summon ownership uses the stable encounter index, survives ordinary relocation,
and counts only living slots, so dying/recycled summons free capacity and an unrelated slot occupant cannot count.
Full lists use the canonical order; a nearly full limit takes only remaining places. Summons use their unscaled canonical
HP and fade in normally. Survivor spacing is 24 px symmetrically on Mano's platform, clamped to its span (tier C).

Slow affected art is repeat-marked in WZ and loops while its sim status is active. Defense uses the original effect/mob0
art, and each summoned snail plays Effect.wz/Summon.img/1 selected by summonEffect1. Choosing that effect family and
placing pos1 at the player body top / pos3 at a mob's body center are tier C interpretations; art, origins and delays
remain canonical. No Summon.img sound1 exists, so summons use Mano's canonical Skill1 sound. All effects use pooled
canvas items. Evidence facts: original v83 Mob.wz/2220000 and Skill.wz/MobSkill.img; local research/stage-bosses/out/
bosses_2220000.json confirms the same fields. The real-import test checks the canonical rows and the summon art.

### Spec #282 / #287 interim regression smoke (2026-10-28)

Pool/slot/rank plumbing only; the eight new attacks, rarity bonuses, common passives and pacing are not landed.
Seed 1, Henesys, bot, real cache (`ISOLATE=287 bash scripts/balance.sh 1 --stage=henesys`): no crash, no warnings,
no missing assets. The previous #284 smoke died on map 2 at 9:17 / Lv32 with 1,422 kills; this pool-only build is
weaker before the successor features. No balance data was tuned. The complete regional smoke belongs to slice QA (#294).

| Seed / policy | End | Level | Kills | Boss observation |
|---|---|---|---|---|
| 1 / bot | DEAD map 1, 309.90 s | 12 | 239 | Mano spawned at 300 s, alive at death; 0/1 completed, censored fight >=9.87 s |
| 1 / bot, #289 (common passives landed) | DEAD map 1, 328.20 s | 13 | 259 | Mano spawned at 300 s, alive at death; 0/1 completed, censored fight >=28.17 s |

#289 smoke (`ISOLATE=289 bash scripts/balance.sh 1 --stage=henesys`, seed 1 only): no crash, no warnings, no missing assets. The
bot took no passive in this run (a pool attack was on offer at every level-up, and passives score below attacks), so the
run differs from #287 only through the extra offers the seeded draw spends on passive cards. No balance data tuned.

### Spec #282 / #290 interim regression smoke (2026-10-28)

Training seeds 1/2/2026, every tier-1 stage, bot/random, real T1 private cache: 24 runs, no crashes, warnings or
missing assets. No tuning or held-out seeds. Henesys seed-1 bot: DEAD 307.8 s, Lv12, 233 kills, first boss alive
(0/1 completed, censored >=7.82 s); previous #287: DEAD 309.9 s, Lv12, 239 kills. Six Henesys runs reached the
first boss; two reached map 2. The Tree That Grew retains its known early deaths. No balance files changed.

| Stage | Bot deaths (seconds), seeds 1/2/2026 | Random deaths (seconds), seeds 1/2/2026 | Map-2 arrivals, bot/random |
|---|---|---|---|
| Henesys | 307.8 / 306 / 366 | 306 / 308 / 361 | 1/3, 1/3 |
| Ellinia | 39 / 35 / 76 | 39 / 35 / 76 | 0/3, 0/3 |
| Perion | 308 / 308 / 411 | 388 / 324 / 309 | 1/3, 1/3 |
| Kerning | 306 / 316 / 306 | 306 / 310 / 319 | 0/3, 0/3 |

Mist consumes skill/global damage modifiers as a survivor multiplier on the existing capped, nonlethal canonical
poison pulse (tier C); its area modifier scales the canonical box. All other high-job actives consume existing
damage/count/attack-count/area/cooldown modifiers at cast time. #288 owns rarity selection and Mastery stacking.

#292 (equipment bands and families, `ISOLATE=292 bash scripts/balance.sh 1 --stage=henesys`): identical end (DEAD map 1,
309.90 s, Lv12, no warnings, no missing assets); 11,788 mesos, no equipment drop in that short run (0.2% x 239 kills).
Same pool-only interim build, no balance data touched.

## 7. Skills (auto-cast and manual)

**Which of this section is live.** The F/P slice plays the skills of 7.31 and 7.32 and the common passives of 8.5, through
the shared seams of the paragraphs below (cast rules, statuses, ground areas, summons). 7.6-7.30 document the other lines'
mechanics (Warrior, Pirate, Thief, Bowman, the Magician line's old buffs): their skill data and tests stay and run, but no
playable job owns them, so read them as the specification for each line's port. Where they mention job advancement, weapon
requirements, branch cards, the basic attack or MP, those systems are removed (section 0).

**ADR 0006 / #287 supersedes the old rank and pool rules below.** Job 212's exact pool and starting skill live in
`survivor/jobs/magician.json`, merged through DataRepo's normal per-line loader. Energy Bolt starts at rank 1 in
active slot one; Teleport is the separate `mobility_skill`, outside both tracks. The twelve declared pool keys
include the eight forthcoming skills; only definitions implemented in SkillBook are offered. New implementations
get standard new/rank cards automatically (explicit upgrade data can supply their text).

`Loadout` owns slot occupancy, capacity checks and display text; capacities are `skills.json.slot_limits` (6/6).
`SkillBook.rank_table` owns rank limits and WZ mapping: per-skill `ranks` overrides `skills.json.rank_levels`, keyed
by WZ maxLevel. Eight active ranks map by ceil(r × maxLevel / 8): 20 -> [3,5,8,10,13,15,18,20],
30 -> [4,8,12,15,19,23,27,30]. WZ numbers and visual levels are read at the mapped level.


**No MP (ADR 0006, #285).** Skills are gated by their cooldown (and an HP cost, Slash Blast and the Boosters) only.
Canonical `mpCon` values quoted in this section and its tables are Skill.wz facts kept for reference; nothing pays
them. Magic Guard, MP Eater (all three branches), Improved MP Recovery, Improved MaxMP Increase and the Brawler's MP
Recovery (7.16) are removed with their cards; Hyper Body raises only Max HP.

Shared skill-definition seams for spec #31 (no second-job content is enabled by these fields):

- Optional `cast: {"rule": "nearest"|"box"|"manual", "min_targets": 1}` (also `crowd`, `hp_or_undead`, the Warrior's
  `weapon_reach` and `range_around`, 7.8; the `self` rule of 7.16 is removed) resolves to
  `Loadout.stats().cast_rule` (empty when absent) and `cast_params` (the whole block). Absent/`nearest` keeps
  nearest-in-range attacks and `can_start_buff` admission. `manual` never auto-casts; unknown rules wait too.
  `box` admits at `min_targets` (tier C default 1), then hits up to `mob_count` targets once per `attack_count` line;
  `range_around` honours `min_targets` the same way (Monster Magnet, 7.33).
  Admission prepares targets before the cooldown/cast; later rules extend the same
  `SkillRunner._admit_cast` / `_resolve_cast` dispatches with their own admission/resolution functions.
- Optional `displacement: {"direction", "when", "field" | "distances" | "distance"}` makes an attack move the character
  (7.13); it resolves to `Loadout.stats().displacement` (`{}` when absent).
- Canonical level `lt`/`rb` resolve to `has_box` and `box: Rect2`; `area` starts at 1.0 and scales both offsets.
  `skill_mod` effects with `stat: "area", op: "mul"` multiply that scale (the planned ×1.2 card step is tier C).
  `mob_count` reads canonical `mobCount` then applies existing `count` modifiers; legacy `count` stays unchanged.
  `RunWorld.skill_box_targets(box, filter = Callable())` anchors at player feet, mirrors canonical left-facing x
  offsets when facing right, broad-phases through the spatial hash and intersects live bodies. It returns all
  matches with scheduled bosses first (#83), then by body-centre distance from the cast origin, then slot. Minimum
  edges include touching bodies;
  maximum edges exclude them. Optional `filter(slot) -> bool` runs before sorting/capping.
- Optional `on_hit: {"status": "poison"|"freeze"|"slow"|"stun", "chance_field": "prop", "duration_field": "time"}`
  reads canonical fields at the cast level (missing `chance_field`: guaranteed attempt; signed Slow `x` stays
  canonical). Projectiles retain that level in a packed array. Both impact paths call `RunWorld._on_player_hit`
  once per damaging line, apply the status through `MobSwarm.apply_status`, then invoke registered
  `add_hit_listener(callable)` listeners with `(slot, {skill, level, magic, damage, element})`, before HP/kill
  resolution. Damage is after elements; physical hits participate, poison ticks and zero-damage immunity do not.
  Existing zero-damage `mob_hit` events for elemental immunity are retained for compatibility with the existing
  tests/presentation; the hook is suppressed regardless of that legacy event.
  Listeners must consume RNG only when their effect can apply.
- (The `absorb_mp` field, MP Eater's monster-MP absorption, is removed with MP, #285; monsters keep no MP pool.)
- `RunWorld.restore_player(stat: String, amount: int, skill: String) -> int` caps a positive HP gain, updates
  the pool and emits `player_restored: {stat, amount, skill, pos}` only for an actual positive integer pool
  change (any other stat restores nothing). The returned amount matches the displayed gain (HP rounds up). Recovery
  and potions retain their existing paths. `DamageNumbers.HP_GAIN` uses cached `BasicEff/NoBlue1` then `NoBlue0`.
  These digit sets exist in the v83 cache (tier A); assigning Blue to HP
  recovery remains tier C because the cache does not prove usage. Without Blue, tinted Violet is the tier C
  fallback. RunScene draws restoration events above the player's head using the existing number pool/timing.

Survivor behaviour is in `data/survivor/skills.json` (base) and `skills/<line>.json` (the skills); the canonical numbers per skill level come from `Skill.wz`.
A skill's **rank equals its canonical skill level**: every rank table covers levels 1 through the v83 maximum,
without skips. Learning starts at level 1 and each rank card adds one level. Energy Bolt, Magic Claw and Magic Armor
have 20 levels, Fire Arrow has 30, and the Beginner skills have 3.
The smaller per-card steps are intentional; canonical skill values remain untouched.
No skill pays MP (#285): a skill is ready when its cooldown is over. Each tick auto-casts at most one skill,
oldest-ready first; learned order breaks a tie. A ready skill without a target waits without restarting its
cooldown. There is no `mp_short` event, `player_state.mp_short` or "Not enough MP" cue.

While hanging on a rope or ladder, no new auto-action casts: skills, basic attacks and buff casting share
`RunWorld.can_cast()`. Cooldowns continue, so a ready skill fires on the first eligible tick after leaving the
rope or ladder. Already-launched projectiles, active buffs and passives keep applying. This is the owner-selected
climbing rule; tier C. The seeded camper probe parks on a rope at 1:00 and reports new casts and skill kills after
existing shots finish separately from carry-over projectile kills.

| Skill (id) | Job | Behaviour | Rank -> canonical level | Upgrades |
|---|---|---|---|---|
| Three Snails (1000) | Beginner | Throws one shell (`level/N/ball`) within 420 px every 1.1 s; 400 px/s; `level/N/hit/0` on impact; one canonical MP cost per cast | ranks 1-3 = levels 1-3: green -> blue -> red shell, 10 -> 25 -> 40 damage; the skill reaches level 2 at character Lv 3 and level 3 at Lv 6 on its own (`level_ranks`: the SP a v83 Beginner puts into it); there is no card for it (owner decision 2026-10-14: a card that only buys what Lv 6 gives for free is a wasted pick) | Additional Shell (+1 shell, ×4), Faster Snails (-12% cooldown, ×4), Piercing Shells (+1 pierce, ×3), Rapid Snails (+25% speed, ×3) |
| Recovery (1001) | Beginner | Auto-cast below the data HP threshold; heals `x` every 5 s for canonical duration, with canonical MP cost/cooldown | ranks 1–3 = canonical levels 1–3: 5/10/15 MP, 4/8/12 HP per pulse, 30 s duration, 120 s cooldown | learn, then two rank cards |
| Nimble Feet (1002) | Beginner | Targetless speed buff; canonical speed +10/+15/+20 for 4/8/12 s, costing 4/7/10 MP; 60 s cooldown from cast | ranks 1–3 = levels 1–3 | learn/rank |
| Energy Bolt (2001004) | Magician | One `ball` projectile every 0.9 s; 450 px/s; `hit/0`; one canonical MP cost per cast | ranks 1–20 = levels 1–20 | learn/rank; Extra Bolt (+1, ×3), Bolt Pierce (+1, ×2), Overcharge (+20% damage, ×3) |
| Magic Claw (2001005) | Magician | Instant 2-hit claw (`attackCount` 2) on the nearest mob within 260 px every 1.25 s; `effect` on caster, `hit/0` on target (`CharLevel` variant by level) | ranks 1–20 = levels 1–20 | learn/rank; Twin Claw (+1 target, ×2), Quick Claw (-12% cooldown, ×3) |
| Magic Armor (2001003) | Magician | Timed PDD (`pdd`) | ranks 1–20 = levels 1–20 | learn/rank |
| Holy Arrow (2301005) | Cleric | Holy projectile at nearest mob: canonical mad/mastery/mpCon and element h; 1 s recast, 480 px reach, 520 px/s, radius 12 | ranks 1–30 = levels 1–30 | learn/rank; +1 projectile (3 steps), +1 pierce (2), cooldown ×0.88 (3); job 230 only |
| Heal (2301002) | Cleric | Instant self recovery below 50% HP OR holy damage to every undead intersecting canonical lt/rb; 2 s recast, canonical mpCon/hp; provisional historical stat-based recovery fit, exact v83 amount unresolved ([evidence](research/cleric-heal.md)) | ranks 1–30 = levels 1–30 | learn/rank only; job 230 only |
| Fire Arrow (2101004) | F/P Wizard | Nearest-target fire (`elemAttr f`) projectile every 0.4 s within 480 px, 520 px/s, radius 12 px, `shoot1` stance 0.8 s; canonical `mad`/`mastery`, ball/hit/effect and Use sound | ranks 1–8 map to WZ levels 4, 8, 12, 15, 19, 23, 27, 30 | new/rank and post-cap Mastery with per-rarity bonuses (8.2); no standalone modifier cards |
| Poison Breath (2101005) | F/P Wizard | Nearest-target poison (`elemAttr s`) projectile every 0.5 s within 450 px, 400 px/s, radius 14 px, `swingO3` stance 0.8 s; canonical `mad`/`mastery`; `on_hit` applies poison with canonical `prop`% for `time`; cached ball/hit/effect and Use/Hit sounds | ranks 1–8 map to WZ levels 4, 8, 12, 15, 19, 23, 27, 30 | new/rank and post-cap Mastery with per-rarity bonuses (8.2); no standalone modifier cards |
| Meditation (2101001 / 2201001) | F/P / I/L Wizard | Self-only timed canonical `mad` -> magic attack; invalidates cached attack ranges on start/expiry | ranks 1–20 = levels 1–20 | branch-specific learn/rank only |
| Bless (2301004) | Cleric | One timed buff: canonical `pdd`, `mdd`, `acc`, `eva` -> weapon/magic defence, accuracy, avoid; accuracy joins the player's ACC and raises the critical chance (6.1) | ranks 1–20 = levels 1–20 | learn/rank only |
| Invincible (2301003) | Cleric | Canonical `x`% reduction of physical/touch damage before Magic Guard; magic damage unaffected | ranks 1–20 = levels 1–20 | learn/rank only |
| Slow (2101003 / 2201003) | F/P / I/L Wizard | At least 3 eligible unslowed mobs in canonical `lt`/`rb`; nearest-first up to `mobCount`, signed canonical `x` for `time`, 1 s recast delay | ranks 1–20 = levels 1–20 | branch-specific learn/rank only |

| Teleport (2101002 / 2201002 / 2301001; `teleport_fp` / `teleport_il` / `teleport_cleric`) | F/P / I/L / Cleric | Manual X: arrow direction, otherwise facing. Horizontal blink lands on a floor up to canonical range, stopped by walls/map limits; vertical blink needs a floor strictly above/below within range. Ground/air allowed; climbing blocks it. Successful blinks pay canonical MP and emit fixed departure/arrival effects and Use sound. Hold repeats every 0.3 s (tier C); invalid destinations and short MP spend nothing. HUD shows X and dims when unaffordable. | ranks 1-20 = levels 1-20; `mpCon` 60 to 13, `range` 130 to 150 px (tier A, all three books) | branch-specific learn and rank cards only; no grant or slot cap |
| Cold Beam (2201004) | I/L Wizard | Instant ice hit on the nearest target within 300 px every 1.25 s; canonical `mad`/`mastery`/`mpCon`; guaranteed freeze attempt for canonical `time` (1–2 s), rejected by bosses and ice-status immunity; real `effect` and `hit/0`, no `ball` | ranks 1–30 = levels 1–30 | learn/rank; Spreading Frost (+1 target, 3 steps), Quick Frost (cooldown ×0.88, 3 steps) |
| Thunder Bolt (2201005) | I/L Wizard | Instant lightning hits when at least one monster intersects the canonical `lt`/`rb` box around the player's feet; up to canonical `mobCount` (6), nearest first, every 1.5 s; canonical damage/mastery/MP; real `effect` and `hit/0` | ranks 1–30 = levels 1–30 | learn/rank; Wider Storm (box offsets ×1.2, 3 steps), Forking Storm (+2 targets, 3 steps; tier C), Quick Storm (cooldown ×0.88, 3 steps) |

Ice/Lightning attack cards require exactly job 220 and all eight learn/rank/behaviour cards are power cards.
Behaviour steps share the first-job Potential magnitudes and remaining-headroom clamp. Cold Beam uses the existing
`count` modifier (up to four distinct targets); Thunder Bolt uses `cast: {"rule": "box"}` and the shared `area`
modifier (up to ×1.728 on both canonical offsets). Cold Beam's `on_hit` block omits `chance_field`: every v83 level
has `x = -100` and `time`, with no `prop`. Freeze duration is canonical, and no separate proc or box path is added.
Both cached skills have no `action` node; selecting `swingO1` for a 0.8 s cast stance is tier C.

Fire/Poison attack cards require current job 210. Both learn/rank cards and all five behaviour cards are power
cards. Behaviour caps count modifier steps, so three Extra Fire Arrow steps produce four shots. Poison Breath
uses the shared on-hit status block and its projectile's cast-level snapshot; poison ticks, immunity and boss
rejection retain the status system's existing rules (section 3). Canonical poison duration is used unchanged,
including level 29's 58 seconds (level 30 has 40). Both attacks use their canonical skill-node elements, never a
survivor element override. Existing bot scores classify these projectile attacks and their cards automatically.

Targeting: nearest living mob within range (spatial hash query) of the body, excluding mobs already targeted this cast
when a skill fires several projectiles.
**Boss priority (#83):** in every targeting rule (nearest, box, crowd, Heal's undead box and the basic attack) a
scheduled boss (a BossDirector encounter; not elites or boss offspring) that qualifies takes target slots first;
the remaining slots fill nearest-first as before. The order is boss, then distance, then slot
(`RunWorld.targets_before`). Projectiles aim at the chosen targets, so the first shot flies at the boss, but still
hit whatever they cross first. Slow still rejects scheduled bosses (status immunity), so it never spends a slot on one. A shot starts at the throwing hand: 22 px in front of the body toward its
target (`player.cast_forward`), level with the cast origin, so the shell never covers the face. Projectiles fly straight toward the target's position at cast time and expire at their range.
Projectile speeds and ranges are tier C (no `speed` key exists in v83 `ball` nodes).
A piercing projectile can hit each logical mob once. Moving that mob through relocation does not grant a second
hit; a fresh mob using the same pool slot can still be hit. Run-local packed 64-bit spawn identities implement
this bookkeeping rule without changing canonical mob IDs, damage, pierce counts or flight tuning (tier C).

Casting does not stop movement. When standing still the character plays the skill's `action` stance (or `swingO1`)
for its frame time; while moving it keeps walking.

Magic Armor auto-casts only when inactive and lasts canonical `time` seconds at the cast's skill level (L1: 54 s at
+2 PDD). It recasts on expiry. Its timer and effect continue while climbing; no cast starts there.
Effects are snapshots of the cast rank, so a rank upgrade changes the next cast. Active Armor adds its canonical PDD
through the hit-defense hook. The HUD shows v83 skill icons and countdowns.
Rank cards preview duration and defense. It is a passive-category skill without slot caps and share the one-cast-per-tick
readiness ordering with attacks. The alert2 stance comes from v83 skill action data; its 800 ms hold is tier C.

Second-job support (#58): `buff.effects` accepts multiple canonical stat/field pairs alongside legacy scalar
`stat`/`field`; every skill retains one timer/icon and snapshots all effects at cast rank. Meditation, Bless and
Invincible use their canonical `alert2`, effect and Use sound. Their self-only auto-cast, expiry, affordable recast
and climbing gate follow Guard/Armor. Bless's active avoid feeds each miss roll; active PDD/MDD feed hit defence.
Invincible scales the already-resolved whole weapon hit, rounds to nearest and keeps minimum 1 before Guard.
Bless's `acc` joins the player's ACC (`player_state.acc`), which raises the critical chance (6.1, #153; before #153 it
had no combat effect).

Slow uses the shared box query with a status-eligible, unslowed filter. Canonical or scheduled
bosses cannot count toward the crowd. It applies through `MobSwarm.apply_status`, deals no hit damage and does not
invoke damaging-hit listeners. Tier A String.wz text limits consecutive uses on the same monsters to two; our
tier C auto-cast reading counts consecutive **successful Slow casts affecting each logical mob**, shared across
the two branch copies. A third consecutive application is ineligible until a successful Slow cast excludes that
mob. Time, other skill casts and failed admission do not break that sequence. Relocation preserves
the history; fresh spawns reset it. The status interface itself still allows refresh for other callers.
Crowd threshold 3, cooldown 1 s, stance hold 0.8 s and card learn/rank weights 3/2 are untuned survivor choices.
All six skills retain the existing support bot scores (learn 50, rank 42 + current/ancestor job bonus 12), below
damaging attack cards. No behaviour cards are added.

### 7.5 Weapons gate no skill (removed, ADR 0006, #284)

Weapon-gated skills (#156) are gone: `SkillBook.usable_with`, the `weapon_families` requirement checks in casting, cards,
manual skills, passives and Boosters, the `blocked` HUD state and the Skill window's "Weapon :" tooltip row no longer exist.
A skill casts whatever the character holds, including bare hands, and a card is never refused for a weapon. Two data facts
remain: `SkillBook.weapon_families(key)` still returns the families a skill definition names (data only; the ranged-range
passive of the unported lines reads it, so Keen Eyes-style range now also extends any held weapon), and the
`jobs/<line>.json` `weapon_families` list is a different thing, the weapons a job's equipment drops come from (section 9).
The tables that listed each line's weapon requirements (Thief, Bowman, Hunter, Crossbowman and Pirate first jobs) were
deleted with the rule; a class spec that wants a weapon-flavoured skill states it in the skill's own definition.

### 7.6 Shared passives, W.Att buffs and Final Attack (#161)

These are the consumers every job line's passives use; the class specs only add data. All of them are skipped while the
held weapon family fails the skill's `weapon_families` (7.5), and none of them changes a record until such a skill is owned.

| Passive `stat` | Skill.wz field | Effect |
|---|---|---|
| `mastery` | `mastery` N | replaces the untrained 10% with (10 + 5N)%, raising the minimum damage of every physical line; the best owned value counts |
| `acc` | `x` (a Mastery's second effect) | added to ACC, so also to crit chance (`balance.crit.per_acc`) and the Stat window's ACC |
| `crit_chance` | `prop` | percent chance added to the crit chance of every damage type and the basic attack |
| `crit_damage` | `damage` | the critical hit's total percent: on a crit the skill multiplier gains `damage - 100` points (additive, 7.5/6.1) instead of x`crit_mult`; best owned value counts |
| `max_hp_per_level` | `x` | Max HP gained at every level-up after learning, at the skill's rank at that moment; never retroactive |

A skill declares them in skills.json as `passive: {"stat": "mastery", "field": "mastery", "effects": [{"stat": "acc",
"field": "x"}]}`: the first stat as before, the rest in the optional `effects` list. **Buffs.** `watk` (Rage's `pad`) adds to
W.Att while active, refreshing the physical bounds the tick it starts or ends; a buff `effects` entry takes an optional
`scale` (default 1). The real Rage needs none: Skill.wz already stores its `pdd` negative (-3 to -12), so the entry is
`{"stat": "pdd", "field": "pdd"}` and lowers `hit_defense().pdd` while it lasts (7.10).

**Final Attack.** A passive skill with `final_attack: {"chance_field": "prop"}`, `damage: "physical"` (the canonical
`damage` is the follow-up's skill percent) and an `action` (the stance whose swing/stab/shoot kind picks the bounds).
After a damaging physical line (basic attack, instant skill or shot) while a matching family is held, it rolls `prop`
percent on RNG stream 12; on a hit it queues one follow-up on the same mob, played at the end of that tick's attacks
(`final_attack` event, then a normal `mob_hit` of the skill with live PDD and crits, all rolled on stream 12; no level gap, #285).
Magic and fixed lines never trigger it, a follow-up never triggers another, and a target the trigger killed gets none.
Stream 12 is only drawn when a Final Attack is owned and a line lands, so other records are unchanged. Tier B: mastery
encoding, additive crit damage, Mastery ACC, Improved MaxHP per level-up without retroactive HP. Tier C: one proc roll
per damaging line, deferral to the end of the tick, no follow-up on a killed target, stream 12, the `scale` and
`effects` data shape.

### 7.7 Attack speed and Boosters (#160)

**Speed step.** The held weapon's Item.wz `info/attackSpeed` (tier A) is the character's attack speed step: 2 is the
fastest, 6 normal (bare hands, `WeaponInfo.NORMAL_SPEED`), 9 the slowest. A Booster adds steps (see below); the step
in effect is `WeaponInfo.effective_speed(base, boost)` = base - boost, never faster than 2 (a weapon already faster
keeps its own) nor slower than 9. The v83 speed table (tier B, `WeaponInfo.SPEED_DELAY_MS`) gives each step's action
time, 800 x (10 + step) / 16 ms: 2 = 600, 3 = 650, 4 = 700, 5 = 750, 6 = 800, 7 = 850, 8 = 900, 9 = 950 ms.

**What it shortens.** `WeaponInfo.speed_factor(base, boost)` is the ratio of the table delays at the step in effect and
at the weapon's own step: exactly 1.0 without a Booster, 700/800 for a Wand (6) under a Booster, 600/700 for a Sword (4).
- Basic attack: the swing interval uses the step in effect (`attack_interval(info, boost)`, quantized upward to 30 ms);
  the impact time (`hit_after`), the stance length (`action_time`) and the avatar's frame speed
  (`player_state.action_scale`, `BasicAttack.action_spec(..., boost)`'s `scale`) shrink by the factor.
- Attack skills (active kind, damaging; not buffs, passives or damage-none casts such as Teleport or Heal): the data's
  `action_time` and `cooldown` (tier C numbers, read as "at the held weapon's speed") are multiplied by the factor in
  `Loadout.stats()` (`speed_factor`), so the auto-cast gate, the stance and the cooldown sweep all follow. A card's
  cooldown modifier applies first. Buffs are timed by their duration and keep it.
- Weapon speed itself keeps setting the swing interval as in 6.1.1, and does not rescale skills: see 4.2 "#160" for why
  and what changing that would move.

**Booster buff.** A buff declares `{"stat": "attack_speed", "field": "x"}` in its `buff.effects` (7.6): the effect is the
number of steps *faster* (positive; the v83 Boosters are 2). Skill.wz stores `x` as -2 (a smaller speed number is faster),
so the real Boosters declare `scale: -1` (7.9). It is an ordinary auto-cast buff: cast when inactive, ready and
affordable, recast the tick after it expires (its cooldown is its duration), with the duration from Skill.wz `time`. It is
gated like a passive: `RunWorld.attack_speed_boost()` counts a running Booster only while the held weapon family fits
the skill's `weapon_families` (`SkillBook.usable_with`, 7.5). A weapon swap does not cancel the buff, it just stops
counting (a Sword Booster does nothing to a Wand) until a sword is held again. `Loadout.weapon_speed` and
`Loadout.speed_steps` are the two caster inputs, assembled in `RunWorld._refresh_caster` (a buff starting, expiring or a
weapon change refreshes them and the cached skill stats). `test_attack_speed.gd` tests the consumer with a synthetic
Booster; the six Warrior second-job Boosters are the first real ones (7.9).

### 7.8 Warrior first job (100, #163)

Five v83 skills from `Skill.wz/100.img` (book 100; canonical level counts, MP/HP costs, icons, effects and sounds), all in
`skills/warrior.json`. Rank equals canonical level as everywhere (7); WZ prerequisites are ignored (tier C, #31). Endure
1000002 is not in the build: the owner dropped it after spec #151 (it only healed on ropes and ladders), so it has no
entry, cards or rope-regeneration clock.

**Weapons at the advancement** (*amended 2026-10-18, #226*). Warrior 100 chooses Sword 1302077,
Spear 1432000 or Steel Pipe 1322006 (Blunt Weapon); only that weapon is granted and worn without requirements.
The sword is the v83 instructor gift (tier B); the spear and pipe are the existing plain early shop choices
(tier C; item stats tier A). The displaced weapon joins the Equip tab or spills at the feet when full. The recorded
path also keeps the bot's equipment planner in the recorded family. Magician advancement is unchanged. Details: section 9.

| Skill | Kind | Behaviour | Tiers |
|---|---|---|---|
| Power Strike 1001004 (20) | attack | auto-casts at the nearest mob inside the held weapon's swing envelope; hits `mob_count` mobs (1; only the Cleaving Strike card adds); damage 165-260 % of the physical weapon damage | A: damage %, mpCon 4-12, attackCount 1, art, sound; B: damage formula; C: Warrior melee families only (sword, axe, blunt, spear, polearm), 1.0 s cooldown, 0.6 s stance |
| Slash Blast 1001005 (20) | attack | auto-casts when a mob's body centre is within `range` (130, 150 from level 16) of the body; hits up to `mobCount` 6 nearest, bosses first, both sides; pays hpCon 8-16 and mpCon 6-14; never casts when the HP cost would leave 0 HP (and then pays nothing) | A: damage 72-130 %, range, mobCount, hpCon, mpCon; C: weapon families, 1.6 s cooldown, 0.6 s stance, wider range / more targets only from cards |
| Iron Body 1001003 (20) | buff | auto-cast, recast on expiry; adds canonical pdd (2-40) to weapon defence for 75-300 s | A: pdd, time, mpCon, action alert2 (no effect art in the WZ node); C: auto-cast, 0.8 s stance |
| Improved HP Recovery 1000000 (16) | passive | adds canonical `hp` (3-50) to every regeneration pulse (`regen: {pool: hp, field: hp}`, `Loadout.regen_bonus`) | A: hp; C: v83 only while standing still, here always (HP regeneration is always on) |
| Improved MaxHP Increase 1000001 (10) | passive | `max_hp_per_level` (canonical `x`, 4-40) at every later level-up (7.6) | B: Cosmic level-up rule |

- **Cast rules.** `weapon_reach` and `range_around` are `SkillRunner` rules beside `nearest`/`box`/`crowd`. `weapon_reach`
  uses `BasicAttack.envelope(world)`, the union of the held weapon's afterimage boxes (its far edge is the basic
  attack's `reach`, tier A), so Power Strike strikes exactly where a swing can. `range_around` reads the canonical `range`
  of the level (`Loadout.stats().range`, which the Wider Blast card scales). Both are instant, use `mob_count` as the
  target cap (`SkillRunner.strike_count`) and their `attackCount` lines per target. `SkillRunner.reach_of` returns the
  weapon reach and the range, so the bot engages them.
- **Stance.** The data says `"action": "weapon"`: the cast stance, and so the swing/stab multiplier of the physical
  formula, is the held weapon's first basic-attack action (`WeaponInfo.skill_action`: swingO1 for a one-handed sword, stabT1
  for a spear, swingP1 for a polearm, swingT1 for a two-handed sword). Tier C: the WZ nodes have no action.
- **HP cost.** `Loadout.stats().hp_cost` is the canonical `hpCon`. `SkillRunner.cast_ready` skips a skill whose HP cost
  `RunWorld.can_pay_hp` refuses (HP must stay above 0; nothing paid), then pays the HP
  (`RunWorld.spend_hp`). The bot counts a skill ready only when its HP cost is payable.
- **Facing.** Both attacks turn the character toward the target before the cast in every movement state (Power Strike
  toward the side with the nearer first target inside the envelope, ties keep the facing; Slash Blast toward its first
  target). A held direction sets a walking or airborne character's facing again on the next motion step, so the turn lasts
  for the cast only (tier C). The `cast` event carries the new facing.
- **Weapon gating** (7.5). Power Strike and Slash Blast list the five Warrior melee families (`weapon_families`, tier C: the
  WZ nodes name no weapon and the String text says a sword). With a wand, a bare hand or any other family they are not
  cast, their cards are not offered, the bot ignores them (`BotInput._reach_profile`, `_can_duel` and the teleport reserve
  skip a skill `SkillBook.usable_with` refuses), and the Skill window greys them. Iron Body and the passives need no weapon.
- **Cards** (`upgrades/warrior.json`, all `requires.jobs: [100]`, shared rarity): a learn and a rank card per skill, plus
  Power Strike: Cleaving Strike (+1 target, 3 steps), Crushing Strike (+20 % damage), Quick Strike (-12 % cooldown); Slash
  Blast: Whirling Blast (+2 targets, 3 steps, 6 to 12), Wider Blast (range x1.2, 3 steps), Quick Blast. Tier C weights and
  steps. Attack cards are `power: true`, so the advancement draw (every eligible power `skill_new` card of the job, then
  other new skills) offers Power Strike and Slash Blast. The bot needs no Warrior card scores; whether a card is never
  taken is a smoke finding, not tuned here.
- **Previews.** Rank cards show `damage` (percent) and `hpCon` beside the existing fields; the two passives show their
  own number (Max HP per level-up, HP per pulse) instead of the canonical field name
  (`UpgradePool.PASSIVE_*`). The skill tooltip adds "HP cost" for an HP-paying skill.
- **Fixture.** `tests/fixtures/characters/lv11_warrior_1st.json`: a real headless Henesys bot round, forced job 100, seed 1,
  stopped at 295 s, just before the first boss (`tools/character_fixture.gd --job=100 --seconds=295 --label=spec151/owner-warrior`, re-captured when the Warrior advancement began to grant the sword 1302077 and the Spear and Steel Pipe in the Equip tab; capped rounds of
  seeds 1 and 2 that ran past 5:00 ended with the Warrior bot dead to that boss's touch hits; recorded for the balance
  pass, not tuned).

### 7.9 Warrior second job: Masteries, Boosters and Final Attack (#181)

Eighteen v83 skills from `Skill.wz/110.img`, `120.img` and `130.img` (canonical level counts and numbers, icons, effect
and hit art, Booster sounds), all appended to `skills/warrior.json` and `upgrades/warrior.json` (spec #165). A second job
gets no attack skill of its own (7.8, `requires.carry_jobs`): the Final Attack is the branch's *attack skill*
(GLOSSARY), the Mastery and Booster support it, and Power Strike and Slash Blast stay on offer.

| Branch | Mastery (20) | Final Attack (30) | Booster (20) |
|---|---|---|---|
| Fighter 110 | `sword_mastery_fighter` 1100000, `axe_mastery` 1100001 | `final_attack_sword_fighter` 1100002, `final_attack_axe` 1100003 | `sword_booster_fighter` 1101004, `axe_booster` 1101005 |
| Page 120 | `sword_mastery_page` 1200000, `bw_mastery` 1200001 | `final_attack_sword_page` 1200002, `final_attack_bw` 1200003 | `sword_booster_page` 1201004, `bw_booster` 1201005 |
| Spearman 130 | `spear_mastery` 1300000, `polearm_mastery` 1300001 | `final_attack_spear` 1300002, `final_attack_polearm` 1300003 | `spear_booster` 1301004, `polearm_booster` 1301005 |

A name two branches share takes the branch suffix; a unique name stays plain. Each skill works only while its own family
is held: sword, axe and blunt cover the one- and two-handed weapons, spear and polearm are separate families
(`weapon_families`, 7.5). The WZ nodes carry no `weapon` field, so every entry lists its family (tier C, v83-facts 3).

- **Mastery** (`passive: {stat: mastery, field: mastery, effects: [{stat: acc, field: x}]}`, 7.6). Skill.wz `mastery` is a
  step 1..10 (`ceil(level / 2)`: levels 1 and 2 are both step 1), shown as (10 + 5N)% = 15% to 60%; the accuracy is `x`
  (+1 to +20 at level N), there is no `acc` key. Raises the minimum damage of every physical line and ACC only while its
  family is held.
- **Booster** (kind `buff`, auto-cast, recast on expiry, `time` 10 s per level up to 200 s, 7.7). The WZ `x` is -2 at every
  level (v83 speed steps: negative is faster), so the entry reads it with `scale: -1` and the consumer gets +2 steps.
  It pays canonical `hpCon` and `mpCon` together (29 at level 1 down to 10 at 20), and is not cast when the HP cost would
  leave 0 HP (7.8). A swap to another family stops the speed-up without cancelling the buff.
- **Final Attack** (`final_attack: {chance_field: prop}`, 7.6): `prop` = 2% per level (2 to 60%), follow-up damage
  `damage` = 100 + 5 x level percent (105 to 250%). The WZ node has no follow-up action and no sound, so the follow-up
  plays the held weapon's attack stance (`action: "weapon"`, 7.8; 0.6 s, tier C) and uses the `hit/0` art. Only a hit
  with its own family triggers it; the Fighter holding an axe never rolls the sword Final Attack. RNG stream 12 as in 7.6.
- **Spread** (one `skill_mod` card per Final Attack, `<final attack key>_spread`, name "Spreading Blow"; effect
  `count` +1, three steps, a power card, weight 2). "The follow-up also strikes +N monsters next to the target": after the
  follow-up hits the original target, up to N other live monsters whose body centre is within the held weapon's swing
  reach (`BasicAttack.reach`, the far edge of its afterimage envelope, tier A) of the *struck target's* body centre are hit
  by the same follow-up (the same stats, one `mob_hit` each). Candidates are ordered like every player targeting rule
  (`RunWorld.targets_before`): a scheduled boss first, then the nearest to the target, then the lower slot. Spread
  uses no RNG: the proc roll stays on stream 12 and the extra hits roll their damage and crits on it as the primary
  follow-up does. Extra hits never trigger another Final Attack. This is also the hit-more-mobs card of the Final Attack
  (the #84 rule in `test_data_files`), which is why only these six need it; Masteries and Boosters are damage-less passives.

**Cards** (`upgrades/warrior.json`; each skill has a learn and a rank card, rank cards cap at the canonical level count;
every card lists only its own branch in `requires.jobs`; weights are tier C): Final Attack and Booster learn and rank
cards and the Spread cards are `power: true`; Masteries are not. A card is offered only while the held weapon family is
the skill's (7.5), so a sword-holding Fighter sees Sword Mastery, Sword Booster and Final Attack: Sword cards and never the
axe's, and after wielding the axe the reverse. Because the Final Attack and Booster learn cards are power cards listing the
new job, the advancement draw (7.8, section 8) offers the held family's Final Attack and Booster. A Mastery appears
among the other new skills of that draw.

**Bot.** `balance.json` `bot.card_scores` scores the new and rank cards of all eighteen skills as attack cards: learn 100
(the `SCORE_NEW_ATTACK`), rank 74 (`SCORE_RANK_ATTACK` 62 plus the current-job bonus 12), because the generic scoring
treats a buff or a passive as non-attack. Spread scores as a targets card (75 plus the job bonus). No cast rules: the
Booster is an ordinary auto-cast buff.

**Presentation.** Skill and level text is the v83 String.wz text (no overrides: none of these strings says "party" or
"canonical"; the Blunt Booster says "mace", as v83 does). The rank cards preview `Accuracy` for a Mastery (its `x`) and
`Success rate` (`prop`) beside `Damage` for a Final Attack (`UpgradePool.PREVIEW_FIELDS`, `LevelUpWindow`).

**Tests.** `tests/unit/test_warrior2_weapon_skills.gd` (RF skill fixtures carry the exact v83 level formulas; one test
reads the real Skill.wz and SKIPs without the cache): every Mastery's minimum damage and ACC only for its family,
every Booster's cost, speed steps, family gate and recast, every Final Attack's proc rate per family, Spread's
count, reach, order and determinism, the cards by held family, the advancement draw and the bot scores.

### 7.10 Rage and Power Guard (#182)

Three buffs from `Skill.wz/110.img` and `120.img` (spec #165): **Rage** 1101006 (Fighter, 20 levels, key `rage`) and
**Power Guard** 1101007 (Fighter, `power_guard_fighter`) / 1201007 (Page, `power_guard_page`), 30 levels each. All three
are ordinary self-only auto-cast buffs (cast when inactive and affordable, recast the tick after expiry, effects
snapshot at the cast, 0.8 s `alert2` stance, canonical `mpCon`, `time`, effect art and `Use` sound). The cards are
not `power`: `rage_new`/`rage_rank` (Fighter, 110), `power_guard_fighter_*` (110) and `power_guard_page_*` (Page, 120),
weights 3 and 2.

- **Rage.** W.Att +`pad` (3 to 12) and weapon defence +`pdd` (the WZ number is already negative, -3 to -12; no `scale`),
  46 to 160 s. Any held weapon. The WZ node is a party buff: here it affects you only, and its text says so (the
  `text.desc` override, 8.2). The WZ `affected` art (what party members see) is not used.
- **Power Guard.** While active, **contact damage** (glossary: a monster's body touching you; `source_kind` "touch")
  is reflected. Mob attacks, boss attacks, projectiles and magic never are. The reflect is
  `floor(damage x x% / 100)` (x = 11 to 40, the buff's snapshot), halved against a boss (tier C: `MobKind.boss`, the canonical info/boss flag, or a scheduled boss slot,
  so an unscheduled boss kind also gets the half rate), and at most `floor(10% of that monster's Max HP)`. The same amount comes off the damage the character
  receives. No RNG.
- **Where it sits.** `RunWorld.take_hit`: hit window and god/dead guard, then avoid (a miss reflects nothing), then the
  defence formula, then the Invincible reduction, then **Power Guard** (`_power_guard_reflect`), then HP, the
  `player_hit` event (its damage is the reduced hit), the window and the reflect (`_apply_reflect`). The hit window
  still allows one touch per window, hence one reflect per window. The knockback guard (#223, section 6) is decided
  after the damage and events and changes none of this. The step is a pure no-op without the buff:
  no RNG, no event, so every earlier record stays byte-identical.
- **The reflect is the character's damage.** It emits a `mob_hit` (the Power Guard key as `skill`, no hit art, never a
  crit), counts in `damage_dealt`, and a kill goes through `_on_kill` (EXP, drops, boss rewards, kill count) like
  any player kill. It does not go through the hit listeners: no Final Attack, no on-hit status.
  Frozen or immune monsters are not special-cased (the reflect ignores physical immunity). A non-boss is staggered and
  pushed by it like by any player hit (`MobSwarm.apply_hit`). It resolves before the player's death check, so a lethal
  touch still reflects and its `mob_hit` / `mob_died` come before `player_died`.
- **Not done.** Prerequisite skills in the WZ `req` nodes (Power Guard needs Rage 3 / Threaten 3) are ignored (#31).
  Both Power Guards feed the one `power_guard` stat; branch exclusivity means a run owns one.
- **Bot.** `balance.json` `bot.card_scores`: `rage_new` 100 and `rage_rank` 74 (what an attack card scores), so Rage is
  picked like an attack. Power Guard has no entry: it scores as the other defensive buffs without one (Iron Body), 50
  for the learn card and 42 plus the current-job bonus for the rank card. Tests: `test_power_guard.gd`.

### 7.11 Threaten (#183)

Page (120) learns Threaten 1201006 (20 levels, `skills/warrior.json` `threaten`): it puts the **threatened** status on
the monsters around the player, lowering their weapon attack and weapon defence by flat amounts for a while. It is the
player-inflicted monster status beside slow, poison, freeze and stun (`MobSwarm.THREATENED = 3`, same flattened table, same
refresh-without-stacking and boss rules) and it coexists with all three.

- **Numbers (tier A, Skill.wz/120.img).** `x` is the weapon-attack change and `y` the weapon-defence change, both flat and
  negative (-1 at level 1 to -20 at level 20, always equal); `time` 44 s to 120 s (+4 s per level); `mpCon` 12 (levels
  1-10) or 20; `mobCount` 6; the box `lt`/`rb` (-250,-150)/(250,150), widening to (-300,-200)/(300,200) at level 11. The
  node has **no `prop`**: every target takes it, nothing is rolled and Threaten draws no random number (RNG stream 13 stays
  reserved for this spec and unused). The alert2 action, the cast effect, the `mob` overlay (eight frames, pos 2, repeat 1:
  it repeats above a threatened monster's head like the poison cue) and the `Use` sound are the WZ art.
- **Cast (tier C).** The `crowd` rule with `cast.status: "threatened"` (`SkillRunner.crowd_status`; "slow" when a crowd
  skill names none, so Slow is unchanged): auto-cast when at least 3 monsters in the box can take it (live, not a boss, not
  resisting statuses, not threatened yet), 1 s cooldown, pays the canonical MP once, targets the nearest `mobCount` of them.
  Slow's "two consecutive casts per monster" history is Slow's own; a Threaten cast does not touch it, and a slowed monster
  is still a Threaten target (and the reverse).
- **Effect.** While threatened a monster's weapon attack falls by `-x` and its weapon defence by `-y`, each floored at 0
  (`MobSwarm.threatened_pad` / `threatened_pdd`; a reapplication replaces the cut and restarts the clock, it never adds up).
  Weapon attack is lowered where a monster's PAD becomes damage, in `RunWorld.mob_weapon_attack` (before Attack Up's
  multiplier): contact damage and physical ordinary attacks and their balls (`MobAttacks._impact`), before the stage's damage multipliers and the player's defence;
  magic attack is untouched. Weapon defence is lowered in `RunWorld.mob_defense` and in the bulk projectile fill
  (`MobSwarm.lower_threatened_pdd`), so the player's physical hits, shots and Final Attacks all see it; magic defence is
  untouched. Death, release and relocation end the status silently, as for the other statuses.
- **Cards and bot.** `threaten_new` / `threaten_rank` (`requires.jobs: [120]`, not power cards, weights 3 / 2); the rank
  preview shows `x` as "Monster weapon ATT / DEF". The bot scores them by default, like Iron Body
  (no `balance.bot.card_scores` entry: the crowd rule is not an attack, tier C) and needs no cast rule (every skill auto-casts).

### 7.12 Iron Will and Hyper Body (#184)

The Spearman's (130) two buffs, `skills/warrior.json` keys `iron_will` (1301006, 20 levels) and `hyper_body` (1301007, 30
levels). Both are `buff` skills in the passive slot like Iron Body: auto-cast while inactive and affordable, recast on
expiry, 0.8 s `alert2` stance, effect art and the `Use` sound, effects snapshot at cast. The WZ skills are party buffs;
here they affect the character only and the text says so (`text.desc` overrides, never "party").

| Skill | Effect | Source |
|---|---|---|
| Iron Will | WDEF `pdd` +1..+20 and MDEF `mdd` +1..+20 for 15..300 s (15 s per level), MP 12 (Lv 1-10) / 24 (Lv 11-20) | A: Skill.wz 130.img |
| Hyper Body | Max HP `x` +2..+60 % for 10..300 s (10 s per level); the WZ Max MP `y` is unused (no MP, #285) | A: Skill.wz 130.img |

- **Iron Will** uses the existing buff consumers only: `pdd` and `mdd` go through `RunWorld.hit_defense()`, so contact
  hits, ordinary mob attacks and balls lose `floor(0.75 x defence)` (`CombatMath.monster_damage`) physically and, for
  magic attacks, by the M.DEF side.
- **Hyper Body** adds the buff stat `max_hp_pct` (field `x`, `RunWorld.MAX_HP_PCT`), folded into
  `refresh_player_stats`: `Max HP = round((player_stat(max_hp) + worn incMHP) x (1 + x/100))`, so the percentage covers
  base, level growth (Improved MaxHP Increase), passives and worn equipment (tier B, v83). With no buff the factor is
  exactly 1.0. Hyper Body leaves current HP unchanged at cast (nothing is granted, only the maximum rises), and when it
  ends HP above the normal maximum drops to it (`refresh_player_stats` clamps); HP below it is untouched. Its Max MP
  half (`y`) went with MP (#285).
- **Refresh.** `RunWorld._refresh_max_buffs()` compares the active percentage with the one already inside `_max_hp`
  (`_max_buff_applied`) on every cast (`start_buff`) and every timer tick, so a cast, an expiry (also the same
  tick a recast follows) and any later `refresh_player_stats` agree. `player_state.max_hp` carries the raised
  maximum, so the HUD bar and the Stat window show it while active.
- **Cards** (`upgrades/warrior.json`): learn and rank cards per skill, `requires.jobs: [130]`, not `power`; weights 3 (learn)
  and 2 (rank), tier C. The WZ prerequisites (Hyper Body needs Iron Will Lv 3) are ignored, as for every skill (owner #31).
  The bot scores them like Iron Body (default BotInput scoring, no `card_scores` entries; lead decision, tier C, not
  tuned).
- **Tests.** `tests/unit/test_hyper_body.gd`: defence on both consumers and the seeded damage difference (physical and
  magic), the percent per level, unchanged current HP at cast, expiry clamping, stacking with Improved MaxHP Increase
  and worn equipment HP, recast, the card/text rules; one test compares the real cache's 130.img with
  the synthetic level tables (SKIPs without the cache). The synthetic tables are in `RF.skill_imgs()` too.

### 7.13 Moving attacks (generic, #190, spec #168)

An auto-cast attack may move the character: away from the mob it faces (Backspin Blow, Recoil Shot) or toward it (a
Corkscrew Blow charge). The mechanism is generic and data-driven; Backspin Blow and Corkscrew Blow (7.19, #191) use it, and
#192 adds the Gunslinger's Recoil Shot. Owner rules (#168 grilling, tier C): the character moves along the footholds of its current platform,
stops at the platform's edge or at a wall, never walks off and never passes a wall; the cast never fails because of
terrain, it only moves less; while airborne (and on a rope, where nothing casts) the attack casts without moving.

**The `displacement` block** (optional, in the skill's definition in `skills/<line>.json`, any cast rule, any non-buff
kind):

```json
"displacement": {
  "direction": "away" | "toward" | "input",   // default "away"; relative to the mob the cast faces; "input" (a manual
  // dash, 7.33 Rush) is chosen by the caster: the pressed arrow key, else the facing
  "when": "before" | "after" | "during",   // default "after"
  "field": "x"                         // the distance in px: a canonical Skill.wz level field of this rank's level
  // ("lt.x" is the box reach |lt.x|, Rush), or
  // "distances": [60, 90, 120]        // survivor px per rank (rank r uses entry r, the last one repeats), or
  // "distance": 80                    // one survivor px value. Precedence: field, distances, distance.
}
```

`Loadout.stats(key)` resolves it to `displacement`: `{}` for a skill without the block, otherwise
`{"direction", "when", "distance"}` with `distance` in px, never negative. A distance of 0 means no move.

- **Direction.** The reference mob is the first admitted target (bosses first, then nearest: the order every rule
  uses); with no target, or one within 0.5 px of the character's x, the character's facing stands in for it. `toward` is
  the side of that mob, `away` the opposite side. A moving attack turns the character toward its reference mob in every
  movement state (like Power Strike), so `away` backs off while still facing the mob and `toward` charges at it.
- **Distance** is horizontal px (the way ground walking integrates), not path length along a slope.
- **Terrain** (`FootholdMap.slide_along`, called through `PlayerMotion.displace` and `RunWorld.displace_player`): follows
  the platform's chain of floors, so slopes carry the feet up and down; stops at the end of the chain (the platform
  edge), 0.01 px (`FootholdMap.EPS`) short of a wall standing across the surface on the way (a wall hanging below the
  surface is walked past, as on foot), and inside the map's horizontal limits. A blocked move is simply shorter or zero.
- **Result.** The move is instant (the character is placed, at rest on its foothold); input, knockback, the hit window and
  the pet follow as after any attack, from the next tick. Presentation that wants a glide reads the `cast` event's `pos`
  (where the cast began, before any displacement, for every `when`) and the player's position afterwards; no extra event.
- **`when`.** HP and the cooldown are paid first, and the targets are chosen at the start position. `after`: the
  hits (or shots) resolve, then the character moves. `before`: the character moves, then the hits resolve on the same
  targets (they are not re-chosen after the move, so a `before` melee hit does not miss because it moved), and shots leave
  from the moved position. `during` (a charge): the character moves, then strikes up to the skill's `mob_count` mobs
  inside the swept path instead of the admitted targets. On a projectile skill `during` acts as `before`.
- **The swept path** of a charge is the skill's attack box (the canonical `lt`/`rb` scaled by `area`, mirrored for the
  facing; the player's body box when the level has none) at the start and at the end of the move, and everything between,
  so a mob that triggered the cast is still struck when the charge stops short of it. Hits go to the mobs in it ordered
  scheduled bosses first, then nearest to where the charge began; each takes `attackCount` lines. A cast admitted by a
  mob outside the path strikes nothing (tier C: the admission rule and the path belong to the skill's data).
- **Determinism.** No new RNG stream and no new events; the same seed gives the same run
  (`tests/unit/test_moving_attacks.gd`: slides on synthetic footholds, then whole casts with a synthetic skill).

### 7.14 Pirate first job (#186)

All four skills have their 20 original Skill.wz levels; the runtime reads canonical numbers rather than copying
them into survivor balance. The Pirate owns `skills/pirate.json`, `upgrades/pirate.json`,
`equipment_drops/pirate.json`, `scrolls/pirate.json` and `shops/pirate.json`. Dash arrived with #188 (7.15); the second
jobs open in 7.17 (#189). Wings is never offered.

| Skill | Cast / effect | Canonical L1 → L20 | Survivor behavior (tier C) |
|---|---|---|---|
| Bullet Time 5000000 | passive ACC / avoid | +1 → +20 each | ACC feeds the shared crit coefficient |
| Flash Fist 5001001 | front box, one mob | damage 156→270%; MP 6→14; box (-74,-30)..(-20,10) | knuckle only; 0.9 s cooldown; 0.6 s action hold |
| Somersault Kick 5001002 | surrounding box, 3→6 mobs | damage 114→190%; MP 8→16; box (-81,-71)..(-5,0) | any weapon; `cast.around` mirrors far reach to ±81; 1.6 s cooldown; 0.6 s hold |
| Double Shot 5001003 | nearest targets, two bullets | damage 61→80%; MP 4→7; range 215→350 | 1 s cooldown; 0.6 s hold; 600 px/s; radius 8; no base pierce |

Actions (`straight`, `somersault`, `doublefire`), CharLevel art at levels 10/15/20/25 and use sounds come from WZ
(tier A). Box reach/height, target caps, costs and shot range retain canonical values. `cast.around` fills the
horizontal span between the mirrored far edges to meet the surrounding-kick behavior. Cards follow the weapon held
at the draw: each skill has learn/rank cards; Flash Fist and Somersault Kick have +1 target, Double Shot +1 pierce.
Modifier cards allow three steps. Attack learn/rank weights are 4/3, Bullet Time 2/2, behavior 2; shared Potential
magnitudes apply. These are initial tier-C choices, with no balance tuning in #186.

Equipment drops use the regular Lv10–70 knuckle/gun progression (1482000–9 / 1492000–9), only in the held family.
Scroll rosters use ordinary 100/60/10 and dark 70/30: knuckle ATT and ACC, gun ATT (tier A ids/rates/stats;
tier C selection). Free Market uses existing weapon pricing for both slots.

Verification (#186, 2026-10-18, private cache, integration #187/#190 included): full Godot suite 1,699 passed,
0 failed, 0 skipped; Rust 63 passed, 0 failed, 0 ignored, including the real-data importer checks and manifest golden.
The 18 Pirate tests also pass after freeing their temporary asset-library node. Both forced-path playtests report
`missing: []`; the real Lv10 job window and both paths fighting were checked by eye. Existing event and Magician
pacing regressions retain their pre-Pirate job pool and unchanged goldens/bounds. No balance smoke or tuning here;
#195 owns that pass.

### 7.15 Skill keys and Dash (#188, spec #168)

**Skill key** (GLOSSARY): the Key Config binding of one manual skill the character has learned. A manual skill
(`cast.rule: "manual"`, never auto-cast) names its key in a `skill_key` field of its definition; the id is also the
input action (`project.godot` has `teleport`, `dash` and `rush`, all X) and is listed in `KeyBindings.SKILL_KEYS`. A new
manual skill adds its id there, an action in `project.godot` and a `skill_key` in its skill file. The three Teleports
share `teleport`, so an existing `settings.cfg` `[input] teleport` binding is simply Teleport's skill key and
Teleport behaves exactly as before.

- **Key Config lists only learned manual skills.** `RunWorld.manual_skill_keys()` returns one
  `{action, name, icon, skill}` per learned skill key; `KeyConfigWindow` takes it when it opens and ends its tray with
  those icons (the skill's own icon and name, not the F/P Teleport icon for everyone). `KeyBindings` drafts the fixed
  actions plus those ids; an unlearned skill key cannot be bound. Teleport, Dash and Rush all default to X; no character
  learns two of them (different job lines). Saved bindings are global, so a key rebound for one skill key stays for that id.
- **Input.** `MoveInput.skills_pressed` / `skills_held` (id -> true; `press_skill`, `hold_skill`) replace the old
  `teleport_pressed` / `teleport_held`. `RunScene` latches presses of learned skill keys (a held key requests repeats).
  `RunWorld.manual_skill(id)` finds the learned skill (weapon-gated like any skill). Teleport keeps its handler
  (`_try_teleport`); a manual buff goes through `_try_manual_buffs` -> `SkillRunner.cast_manual_buff`, which casts only
  when casting is free, the buff is not running, its cooldown (the buff's duration, as for an auto-cast buff) is over and
  any HP cost can be paid; otherwise the press does nothing: no event. The HUD icon shows the key caption and the buff
  countdown as its cooldown sweep (there is no MP tint, #285).
- **Dash 5001005** (Pirate first job, ranks 1-10 = Skill.wz levels 1-10): pressing its key starts a buff with canonical
  speed `x` +12 -> +30 and jump `y` +1 -> +10 for `time` 4 -> 20 s (tier A; its canonical `mpCon` is unused, #285). It replaces
  v83's double-tap (tier C, owner), works with any weapon, has no cast hold (the character keeps moving) and plays the
  canonical cast effect and Use sound. Speed is added to the speed stat before the existing cap (140); jump is added to
  the jump stat (`100 + incJump + buff`) before the existing cap (123), so Dash obeys the same movement limits as
  equipment. Cards: `dash_new`, `dash_rank` (max rank 10), weight 2 each, Pirate line only, no modifier.
- **Bot.** Dash's `manual` block holds the flee rule (survivor data, tier C): `bot_flee_hp` 0.5, `bot_surround_count` 3,
  `bot_surround_distance` 120 px. `BotInput` presses the key when HP is below that fraction of its maximum with a mob
  inside the existing 160 px flee distance, or when that many mobs on its level (the duel band, feet +/-40 px) are within
  the surround distance, and the skill is ready, usable and its HP cost affordable. It never presses while the buff runs
  (the old MP reserve, `BotInput._keeps_mp_reserve`, went with MP, #285).

Evidence (#188): `dash_driver.tscn` (`scenes/debug`) on the real Henesys map, rank 10: `key_config_dash.png` (Dash on X
and at the end of the tray), `dash_cast.png` (the buff icon with its countdown, MP 42 -> 37, speed 100 -> 130, jump
100 -> 110) and `dash_run.png`; the real X key and arrow key drive it.

### 7.16 HP-to-MP conversion (removed, #285)

The `self` cast rule, its `mp_below` / `hp_at_least` conditions, the `convert` block and the Brawler's MP Recovery
5101005 that used them were removed with MP (ADR 0006). `RunWorld.conversion_hp`, `self_cast_ready` and
`convert_hp_to_mp` are gone.

### 7.17 Brawler and Gunslinger: advancement, passives and boosters (#189)

Brawler 510 and Gunslinger 520 are playable at the canonical Lv 30, from either first-job path (the window lists both
for a knuckle-path and a gun-path Pirate alike). Advancing adds +325 Max HP and +175 Max MP (tier B: fixed midpoints of
the v83 second-job ranges +300-350 and +150-200; the Magician second jobs keep +475 Max MP). Growth stays the Pirate's
25 HP / 20.5 MP per level. Each branch hands **one** advancement weapon (section 9, "Second-job grants"; tier C
choices): Brawler Prime Hands 1482004 (Lv 30 knuckle, PAD 34, STR 60 / DEX 30) and Gunslinger Cold Mind 1492004 (Lv 30
gun, PAD 31, DEX 70 / STR 30). A branch has one family, so the grant is always worn, even when the other family was
held; the previous weapon goes to the Equip tab or to the feet when it is full. As for every grant, the advancement does
not check the weapon's requirements; the auto-AP rows below meet them at Lv 30.

**Auto-AP.** `balance.json` `ap_stat` / `ap_secondary` carry plain `510` and `520` rows that copy the first-job
path rows of their weapon (Brawler = `500:knuckle`: STR primary, DEX secondary at the level; Gunslinger = `500:gun`: DEX
primary, STR secondary at the level), and a branch row wins over a path row. The AP therefore follows the branch, not the
recorded path: a knuckle-path Gunslinger switches to DEX with an STR secondary when it advances (tier C; only earned
AP move).

**Ammo.** The Gunslinger's schedule (6.1.2: Split Bullet 2330001 at Lv 30, Mighty Bullet 2330002 at Lv 50) applies to job
520 once it is playable: advancing at Lv 30 shows the one `ammo_upgraded` notice, advancing past Lv 50 goes straight to
Mighty Bullet. A Brawler holding a gun keeps the basic Bullet 2330000.

| Skill | Kind | Weapon | Canonical L1 → top | Survivor behaviour |
|---|---|---|---|---|
| Improve MaxHP 5100000 | passive `max_hp_per_level` | any | 10 levels; x +3 → +30 Max HP per level-up | the shared 7.6 consumer: the rank at the level-up counts, never retroactive; the AP half (`y`) has no meaning |
| Knuckler Mastery 5100001 | passive `mastery` + ACC | knuckle | 20 levels; mastery N 1 → 10 = 15% → 60%; x ACC +1 → +20 | the shared 7.6 consumer, only while a knuckle is held |
| Gun Mastery 5200000 | passive `mastery` + ACC | gun | same; `y` (bullets per recharge, +10 → +200) is not used: ammo is endless | only while a gun is held; its level text omits the bullet count |
| Knuckler Booster 5101006 | buff `attack_speed` | knuckle | 20 levels; x = -2 (two steps faster, `scale` -1); time 10 → 200 s; hpCon and mpCon 29 → 10 | the 7.7 Booster: auto-cast when inactive, ready and affordable (it pays **both** HP and MP, tier A, and never casts if the HP would leave 0), counted only while a knuckle is held |
| Gun Booster 5201003 | buff `attack_speed` | gun | same | the same, gun |

The v83 prerequisites (the Booster needs Mastery level 5) are ignored as everywhere (tier C, owner choice #31). Each skill
has learn and rank cards that require the exact branch (Improve MaxHP and the knuckle cards the Brawler, the gun cards
the Gunslinger) and, through the skill, the matching held weapon (Improve MaxHP is weapon-free). They are not power
cards; weights 2/2 (tier C, untuned). The first-job Pirate cards now list `requires.jobs` [500] with
`requires.carry_jobs` [510, 520] (the section 8, rule 1 shape of the Warrior's Power Strike): they stay on offer to both
branches but a second job's advancement draw offers that branch's own skills rather than Flash Fist, Somersault Kick or
Double Shot. The Brawler's attacks are 7.19 (#191); the Gunslinger's are 7.20 (#192), MP Recovery with #193 and Oak Barrel with
#194.

### 7.18 Hidden state and Oak Barrel (#194, spec #168)

**Hidden** is a generic player state (GLOSSARY): an active buff whose definition sets `"hidden": true` in its `buff`
block makes `RunWorld.is_hidden()` true until the buff ends, at its duration or earlier when its source says so.
Oak Barrel uses it now; Thief Dark Sight (#167) will reuse it. While Hidden (owner rules, #168 grilling):

- **Monsters, bosses included, ignore the character.** `MobSwarm.step` gets `ctx.hidden` and no target: ground mobs
  patrol their platform the way a mob with no route does (they walk the way they face and turn at walls and platform
  ends), flyers hover where they are (tier C). Scheduled bosses neither stall nor teleport to the character
  (`BossDirector`), and `SpawnDirector` does not recycle mobs as "gone" or "stalled".
- **No hit of any kind lands:** contact damage (`_touch`), ordinary and boss attacks (`MobAttacks.plan` starts nothing;
  a windup already under way plays its phases but lands nothing and launches no ball), mob skills aimed at the character
  (Slow), and balls (they pass through; the ball is not used up and ends at its range). `take_hit` also returns 0 for
  any source as the safety net.
- **The character cannot attack:** `SkillRunner.cast_ready` skips every attack skill (active, not a buff, not manual,
  damage type other than none; the cooldown keeps running), and `BasicAttack` starts no swing and drops one in its
  windup. Buffs, potions, pickups, movement and manual movement skills (Teleport, Dash) still work. Shots already in
  flight keep flying.
- **Presentation:** `player_state.hidden` and `player_state.morph`.
- **Edge cases (tier C):** a boss already fading out for a pursuit teleport when Hidden begins still finishes that teleport;
  Cleric Heal still heals below its HP threshold but never strikes undead (it is an attack in this rule even though its
  `damage` is `none`).

**The buff block.** `buff`: `hidden` (bool), `morph_field` (the level number holding the Morph.wz id), `fail_field` (the
level number holding the failure chance in percent), `end_hp_above` (an HP fraction above which the buff ends early),
`cooldown_from_cast` (the cooldown is exactly the cooldown field from the cast, instead of at least the duration; the
active buff alone blocks a recast). A cast with a failure chance rolls once on the Pirate stream 16 (`pirate_rng`,
`randf() < fail_chance`); a failed cast pays MP, starts the cooldown, plays no effect and emits `buff_failed` instead
of `buff_cast`. A skill's `cast` block may set `mob_within` (px): a buff with it needs a living mob within that distance of
the cast origin (the same reach test as nearest-rule attacks).

**Oak Barrel 5101007** (Brawler 510, ranks 1–10 = Skill.wz levels, no weapon requirement, `skills/pirate.json` entry
`oak_barrel`, slot "passive" like the other buffs):

| | rank 1 | rank 10 | source |
|---|---|---|---|
| MP | 11 | 20 | tier A `mpCon` |
| Barrel time | 12 s | 30 s | tier A `time` |
| Failure chance | 37% | 10% | tier A `prop` (read as the failure chance, as the #194 brief states) |
| Cooldown | 35 s | 15 s | tier A `cooltime` |
| Morph | 1002 | 1002 | tier A `morph` |

It auto-casts when HP is below 30% of Max HP (`buff.hp_threshold` 0.3, tier C), a mob is within 250 px
(`cast.mob_within`, tier C) and the cooldown is ready; the barrel ends early once HP is above 60% (`end_hp_above` 0.6,
tier C). Cards (`upgrades/pirate.json`, `requires.jobs: [510]`, so only Brawlers are offered them): `oak_barrel_new`
(weight 3) and `oak_barrel_rank` (max rank 10, weight 2), neither a power card (tier C, untuned).

**The morph.** While `player_state.morph` is set, `AvatarRenderer` draws `Morph.wz/<id>.img` instead of the avatar: the
`stand` action for standing and for any attack or cast stance, `walk`, `jump`, `prone`, `ladder`, `rope`, `sit` and `fly` for
their stances, one canvas on the feet, mirrored for facing. Morph 1002 is the v83 oak barrel. A morph missing from the cache
keeps the avatar and lists the path in `missing`. The morph's `info` speed and jump (100) are not applied (the character
keeps its own movement). Tests: `tests/unit/test_hidden.gd` (the generic state with a synthetic buff),
`test_oak_barrel.gd` (the shipped definition: conditions, stream-16 failure, duration, early end, cards),
`test_morph_render.gd` (synthetic and real barrel frames), Rust `real_import_of_the_oak_barrel_morph`; evidence from
`scenes/debug/morph_driver.tscn`.

### 7.19 Brawler attacks: Backspin Blow, Double Uppercut, Corkscrew Blow (#191, spec #168)

Three knuckle attacks in `skills/pirate.json` (book 510, job 510, between the Knuckler Booster and the Gun Booster), each
with a learn card, a rank card (20 ranks, canonical level = rank) and a "hits +1 more monster" card (`count`, at most 3
steps) in `upgrades/pirate.json`: `<skill>_new`, `<skill>_rank`, `<skill>_targets`. The cards are `"power": true`
(the advancement draw offers power cards first, so a new Brawler is offered all three attacks) and `requires.jobs: [510]`
(exact branch); through the skill's `weapon_families: ["knuckle"]` they are offered, and the skills cast, only while a
knuckle is held (a Brawler wielding a gun casts none of them and sees none of their cards). Learn weight 4, rank weight 3,
targets weight 2: tier C, untuned like every Pirate card.

| Skill | Canonical L1 -> L20 (Skill.wz 510.img) | Survivor behaviour |
|---|---|---|
| Backspin Blow 5101002 | damage 88 -> 240% (+8 per level), mpCon 12 -> 30 (+2 every 2 levels), mobCount 3, stun `time` 1 s, box (0,-50)..(140,0), `backspin` action | cast rule `box` with `cast.around`: any mobs within 140 px on either side admit it, the 3 nearest (bosses first) are struck once each; the character turns to the nearest one and slides 100 px **away** from it after the hits (7.13, `when: after`, tier C distance), stopping at platform edges and walls; every landed hit stuns for 1 s |
| Double Uppercut 5101003 | damage 100 -> 290% (+10 per level), `attackCount` 2, mpCon 15 -> 30 (+5 every 5 levels), stun `time` 1 s, no box, no mobCount, `doubleupper` action | cast rule `weapon_reach` (the Power Strike rule, 7.8): one mob inside the held knuckle's swing envelope is struck twice; more mobs only from cards; no movement; every landed line stuns for 1 s (two stuns keep the one second) |
| Corkscrew Blow 5101004 | damage 135 -> 420% (+15 per level), mpCon 20 -> 36 (+4 every 4 levels), mobCount 3, box (-100..-200, -50)..(0,0), `screw` action | cast rule `box` (the facing side only, canonical): a mob within the reach starts a full charge **toward** it (`when: during`, 7.13) of the same 100 -> 200 px as the box reach, striking up to 3 mobs along the swept path; stops at platform edges and walls; no stun |

**Stun.** Skill.wz gives Backspin Blow and Double Uppercut no `prop`, so `on_hit: {"status": "stun", "duration_field": "time"}`
has no `chance_field` and every damaging line stuns (the ticket's "at its Skill.wz chance" is therefore 100%, tier A by
absence). The status is the generic stun of "Monster statuses and elements" (bosses and steady bosses resist; the mob
`mob` stars play over stunned mobs). A hit that does 0 damage does not stun.

**Choices that are ours (tier C).** All three need a knuckle (the WZ nodes name no weapon). Backspin Blow's canonical box
(0..140 on the positive side) lies **behind** the facing in the left-facing convention, while the owner's rule is that it
slides away from "the faced mob": `cast.around` mirrors the reach to both sides (the Somersault Kick approach), so it
fires when any mob is within 140 px, faces the nearest and backs off from it, and its hits include mobs on both sides.
Corkscrew Blow's charge distance has no scalar Skill.wz field (the reach is the box's `lt.x`), so
`displacement.distances` copies -`lt.x` per level and a private-cache test checks all 20 against Skill.wz. The charge is
the full distance at once (no `prepare`/`keydown` wind-up, no Loop sound, the `dash` prepare action is not played), and
its sweep never passes a wall: when a wall stops the charge, the swept hit box ends at that wall, so a mob just past it
is not struck even where the end-of-charge box would reach it.
Cooldowns 1.5 s (Backspin), 1.2 s (Double Uppercut), 2.0 s (Corkscrew); cast stance holds 0.8 s, 1.0 s, 0.8 s.
Presentation: the skills' `effect`, `hit/0`, Use and Hit sounds and the body actions `backspin`, `doubleupper`,
`screw` (Character.wz/00002000.img) play as for Flash Fist; the second effect layer `effect0` of Backspin Blow, the
second hit variants (`hit/1..`) and Corkscrew's `keydown` aura are not drawn. MP Recovery is 7.16 and Oak Barrel 7.18.
with #194.

### 7.20 Gunslinger attacks (#192, spec #168)

Four auto-cast attacks join the Gunslinger's book (`skills/pirate.json`, book 520, job 520, 20 canonical levels each; ranks equal
levels). Owner rules (#168 grilling): Grenade is thrown as if fully charged with no wind-up; Wings is dropped. Costs, damage %,
mob counts, boxes, stun chance and time and the hop distance are tier A Skill.wz 520.img values (WZ wins over String text where
they disagree: Invisible Shot's MP is 10 to 25, Grenade's 15 to 27). Damage is the ordinary physical formula of the held
weapon (gun formula with a gun, the weapon's own with anything else for Grenade); ammo is endless, so `bulletConsume` is unused.

| Skill | Weapon | Cast | Canonical L1 → L20 | Survivor behaviour (tier C unless stated) |
|---|---|---|---|---|
| Invisible Shot 5201001 | gun (A) | `box`, `around` | damage 75 → 170%; MP 10 → 25; up to 3 mobs; box (-250,-80)..(-10,40) mirrored to both sides | strikes in front **and** behind; no bullet is drawn (the WZ has no ball); 1 s cooldown; held gun's first stance, 0.6 s; WZ Hit sound as its cast sound (it has no Use) |
| Blank Shot 5201004 | gun (A) | `box` (front only) | damage 63 → 120%; MP 10 → 25; 3 mobs; box (-250,-80)..(-20,30); stun `prop` 43 → 100% for `time` 1 → 4 s | `on_hit` stun (#187: scheduled and canonical bosses resist; one roll per struck mob on the main stream, none when `prop` is 100); `fake` action (A); 1.4 s cooldown; 0.6 s |
| Grenade 5201002 | any (C) | `cluster` | damage 45 → 140%; MP 15 → 27; 3 → 6 mobs; blast box (-50,-50)..(50,20) | see below; 2 s cooldown; the held weapon's first stance, 0.6 s |
| Recoil Shot 5201006 | gun (A) | `nearest`, projectile | damage 70 → 260%; MP 14 → 26; `range` (recoil) 115 → 250 px | one bullet at the nearest mob, then `displacement` `away` / `after` with `field: "range"` (7.13): an instant hop away from the mob, cut short at platform edges and walls, none in the air; the bullet is the current ammo's own sprite (`ammo_shot`: `Ammo.bullet_path(ammo_id())`, so Split and Mighty Bullets show) at 1000 px/s, radius 6, rotating, reach 300 px, no base pierce; `backstep` action (A); 1.8 s cooldown; 0.6 s |

**The `cluster` cast rule** (new, generic; Grenade is its only user). `cast: {"rule": "cluster"}` plus the skill's `range`
(the throw range, 400 px) and `speed` (the ball, 600 px/s); the level needs a canonical `lt`/`rb` box, the blast.

- *Admission and target.* The skill casts when any live mob is within `range` of the cast origin (`has_target` is the cheap
  `_any_target`). Among the `CLUSTER_CANDIDATES` (12) nearest mobs in range, scheduled bosses first, the target is the first
  whose blast box, centred on its feet, would strike the most mobs (up to `mob_count`); a scheduled boss in reach is the target
  outright. A lone mob therefore draws the throw only when nothing better is in reach, and ties go to the nearest.
- *No wind-up.* The cast tick pays MP, starts the cooldown, turns a standing character to the target, plays the stance and emits
  `cast` and `skill_thrown` (ARCHITECTURE 4.4.3: `from` the hand, `to` the target's body centre, `seconds`, `ball`, `burst`).
  The WZ `prepare` (`dash`) and `keydown` nodes are not used.
- *Landing.* The ball flies `max(0.1 s, distance / speed)`; when it arrives the blast strikes up to `mob_count` live mobs whose
  bodies intersect the blast box around the landing point (the target's feet at the cast), scheduled bosses first, then nearest to
  the aim point, `attackCount` lines each, through the ordinary `hit_mob` path (listeners, Final Attack and `on_hit` apply). The
  stats are the cast's snapshot; the blast ignores where the target moved to. Flights are `SkillRunner` state and count down
  with the tick (also while casting is blocked, e.g. on a rope); they do not survive a restart of the round.
- *Presentation.* `RunScene` loops the ball art along a short arc (`THROW_ARC` 40 px) for the flight, then plays the WZ `special`
  blast art at `to`; each struck mob plays `hit/0` as usual. Sounds: the WZ `Use2` on the throw.
- *Cards and reach.* `count` cards add targets to `mob_count`; the bot's approach/kiting reads `range` (`SkillRunner.reach_of`).

**Cards** (`upgrades/pirate.json`; all `power`, `requires.jobs [520]` exactly, so the Lv 30 advancement draw, which offers every
eligible new power skill of the job, shows all four): `<skill>_new` weight 4, `<skill>_rank` weight 3 (max rank 20), and one
hit-more-mobs card with weight 2, three steps: `invisible_shot_targets`, `blank_shot_targets`, `grenade_targets` (+1 target) and
`recoil_shot_pierce` (+1 pierce). Cards follow the weapon held at the draw (the skill's gun tag): with a knuckle in hand the three
gun skills' cards are not offered, Grenade's are. Tests: `tests/unit/test_gunslinger_attacks.gd` (seeded, fixed ticks; the numbers
by rank, behind and in front, stun chance and time, throw without wind-up and landing, cluster choice, knuckle, hop distance and
edge/wall/air stops, the cards and the draw, and the original v83 tables, boxes, art and sounds in the private cache).

Evidence (#192): `scenes/debug/gunslinger_driver.tscn -- --shots=<dir>` casts each attack once on the flat part of the real Henesys map with the real
cache (`invisible_shot_a/b.png`, `blank_shot_a/b.png` with three stunned snails, `grenade_a/b.png` the ball in flight then the blast on the cluster,
`recoil_shot_a/b.png` the hop) and writes `summary.json`; all four were looked at. `scripts/playtest.sh --job=520:gun` also runs them, but the
Pirate bots die at about Lv 21-24 (tier 1, balance is #195's), before the Lv 30 branch.

### 7.21 Thief first job (#207)

The Thief owns the five `thief.json` survivor line files (skills, upgrades, equipment drops, scrolls, shops).
Canonical costs and damage come from Skill.wz, with one survivor rank per canonical level:

| Key / skill | Kind / cast | Levels | Canonical effect and cost (L1 → L20) |
|---|---|---|---|
| `nimble_body` 4000000 | passive, any weapon | 20 | ACC/avoid +1 → +20; ACC feeds existing crit chance |
| `double_stab` 4001334 | instant, weapon_reach; dagger | 20 | 2 hits, 98 → 140%, MP 8 → 14 |
| `lucky_seven` 4001344 | projectile, nearest; claw | 20 | 2 stars, 58 → 150%, MP 8 → 16 |

Lucky Seven uses LUK×5.0/2.5×PAD/100, ignoring mastery (tier B, v83-facts §5). It has no canonical ball;
`ammo_shot: true` selects the current star's Item.wz bullet, including the Assassin schedule after a later advancement.
Its initial survivor reach is the basic claw's 250px, cooldown 1s, speed 600px/s, radius 8px, no pierce;
Double Stab uses the dagger's swing envelope, one base target, cooldown 1.2s. Both hold their action for 0.6s
(tier C untuned; Double Stab's stabO1 is canonical, Lucky Seven's shoot1 is our choice). Only Use sounds exist.

Cards: `<key>_new` / `<key>_rank`, plus the parity lines below (#208). Each weapon path has **13 behaviour steps
across five lines**, including the tracer's star/target line. Attack learn/rank weights 4/3, Nimble Body 2/2,
behaviour weight 2 (tier C, untuned, shared Potential magnitudes). Attack cards require jobs [400] and
carry_jobs [410,420]; Nimble Body requires jobs [400] only. Cards follow the held family at draw time and behaviour
cards never enter an advancement draw; carried learn cards also stay out of branch advancement draws.

| Skill | Behaviour card suffix | Effect per step | Maximum steps |
|---|---|---|---|
| Lucky Seven | `_count` | +1 star | 3 |
| Lucky Seven | `_pierce` | +1 monster pierced per star | 2 |
| Lucky Seven | `_damage` | damage ×1.2 | 3 |
| Lucky Seven | `_cooldown` | cooldown ×0.88 | 3 |
| Lucky Seven | `_range` | range ×1.2 | 2 |
| Double Stab | `_targets` | +1 target | 3 |
| Double Stab | `_hits` | +1 damage line per target (`attack_count`) | 2 |
| Double Stab | `_damage` | damage ×1.2 | 3 |
| Double Stab | `_cooldown` | cooldown ×0.88 | 3 |
| Double Stab | `_reach` | skill swing envelope ×1.2 on both axes (`area`) | 2 |

`attack_count` modifiers add to the canonical `attackCount`, independently of target count. The extra-hit card
previews Hits before/after. A weapon-reach skill applies its own `area` modifier to a copy of the held weapon's
feet-relative swing envelope; target admission, the short-MP probe and the bot's reach all use that scale.
The basic attack and other skills keep their own envelope. Multipliers compound per step; rarity grants steps
through the shared headroom/clamping rules, never exceeding a line's cap. These are tier C survivor choices,
matching existing behaviour-card magnitudes; canonical v83 levels, counts and weapon data remain unchanged.

**Keen Eyes (#209):** `keen_eyes` 4000001 is a passive with eight canonical ranks. Skill.wz's `range` adds
+25/+50/+75/+100/+125/+150/+175/+200px (tier A), only while holding a claw (tier C family tag, following the v83
description). It reuses #199's generic `Loadout.RANGE` passive unchanged: the ranged basic attack extends its target
search and shot travel; weapon-gated ranged attack skills add the passive to their resolved range. Lucky Seven thus
grows from 250px to 450px at rank 8; Drain will use the same path when added. The basic attack's cached base boxes
remain unchanged; only the far horizontal edge grows, preserving vertical and point-blank reach (tier C, #199).
Swapping to a dagger or any other family disables the bonus immediately, including skill range. Magic is unaffected.
The `keen_eyes_new` / `keen_eyes_rank` cards require exact job [400], no carry, a claw held, and stop at rank 8.
Learn/rank weights are 2/2 and `power:false` (tier C, untuned, matching Nimble Body). A learned Keen Eyes remains
effective in either second-job branch while a claw is held. Cards and the Skill window show the canonical pixel bonus.

Drops are a curated ordinary Lv10–70 roster of Thief-bit claws/daggers, armour by tier/gender and Lv22 shields
(tier C selection; canonical stats unchanged). Weapon drops followed the held family and Thief shields required a dagger (`shield_families`); #292 removed
both rules: a job lists its `weapon_families` and shields go by job class alone. Claw/dagger ordinary and dark ATT scrolls and Free Market weapon slots use existing pricing.
The export's existing `data/survivor/*/*.json` include filter covers these files.

`RunWorld.thief_rng` registers stream 15 without drawing from it; only Steal's success roll (#214) will use it.
Adding the two Thief window entries intentionally changes unforced bot records. The inherited event/pacing tests freeze
their old job pool; existing combat and player-state goldens are retained. Full smoke belongs to #215; no balance tuning.

### 7.22 Disorder (#210)

`disorder` (4001002) is a status-only instant skill, usable with any weapon. It applies the existing **Threatened**
status: signed canonical x/y lower PAD and WDEF by 1..20, floored at zero, for the canonical 7..60 seconds, costing
5..10 MP across 20 ranks (tier A). The real table is stepwise; it is read as-is, without interpolation.

It uses Threaten's crowd admission: at least three live ordinary mobs that accept the status and are not already
threatened. Skill.wz gives Disorder no box or count, so `cast.box` supplies (-250,-150)..(250,150) and `cast.mob_count`
supplies six, nearest first (tier C). Loadout uses these only as fallbacks when canonical lt/rb or mobCount are absent.
The 1 s cooldown and 0.8 s alert2 stance are tier C survivor choices; v83 provides no action or player effect here.
Disorder's canonical `mob` art plays once on each recipient, alongside the shared Threatened cue and its Use sound.

`cast.interrupt: true` cancels a successfully affected mob's pending pre-impact ordinary attack and releases its
authored stance. The next-attack wait keeps running on its original schedule. No stun is applied; movement and
future attacks remain available. An attack already at impact or a projectile already launched is not undone
(tier C interpretation of the v83 attack-interruption text). Threaten omits the flag and keeps its previous behavior
and records. Neither skill rolls RNG. Bosses and already-threatened mobs cannot receive Disorder.

Only `disorder_new` and `disorder_rank` cards exist, not power cards, with jobs [400] and no carry_jobs or behavior
cards. Learn/rank weights 3/2 match Threaten (tier C). Deterministic tests cover crowd admission, nearest cap, canonical
cuts/costs/durations and expiry, boss/duplicate exclusion, weapon freedom, attack interruption and the next attack's
original schedule; paired Threaten coverage protects its unchanged behavior. A real-cache test checks all 20 levels.
The `thief --disorder=1` flow-driver probe captures a real cast on an evidence-only prepared crowd.

### 7.23 Dark Sight (#211, spec #167)

`dark_sight` (4001003, book 400, ranks 1–20, any weapon) reuses the Hidden state in 7.18. It auto-casts below
30% MaxHP with a living mob within 250 px (the same reach as Oak Barrel), when affordable and ready. It never fails
and draws no failure RNG. Hidden blocks contact, mob and boss attacks and the character's attacks; movement, buffs,
potions and pickups still work. It ends after the canonical duration or early above 60% MaxHP. The fixed 30-second
cooldown starts at the cast; an active buff blocks recasting even after that cooldown finishes (tier C owner rules).

Canonical Skill.wz/400.img values are MP 24→5, duration 10→200 seconds and speed −30→0. The speed table steps by two
through rank 12 (−8), then by one through rank 20; no interpolation is used in play. The speed penalty is a normal
buff contribution and disappears with Hidden. `buff.cooldown` optionally supplies a literal survivor cooldown;
without it buffs retain their canonical `cooldown_field` (or `time`). This adds no state or snapshot fields.

The renderer uses the existing avatar CanvasGroup at 50% opacity while Hidden without a morph; its invincibility
blink can dim it further. Morph artwork keeps its own appearance. The canonical cast action `darksight`, effect and
Use sound are retained; the action hold is 0.6 seconds (tier C). Learn/rank cards require job 400 only, with no carry,
weights 3/2 and a 20-rank cap; neither is a power card (tier C weights, tier A cap).

Seeded tests in `test_dark_sight.gd` cover conditions, costs, canonical speed, duration, early recovery, cooldown,
ordinary/boss attacks, contact, attack suppression and card gates. Cache tests compare all 20 levels and cast art;
`test_dark_sight_render.gd` checks transparency/recovery. `scenes/debug/dark_sight_driver.tscn` captures a real Thief
among Henesys mobs before/while Hidden and after recovery, without save writes. No balance tuning; #215 owns smoke.

### 7.24 Assassin and Bandit: passives, buffs and recovery (#212)

Both Thief branches advance at canonical Lv30. They keep the Thief's growth and LUK/DEX auto-AP policy.
Each adds +325 MaxHP / +175 MaxMP (tier B midpoints) and wears its advancement weapon without requirement checks:
Assassin 410 gets Steel Guards 1472008 (claw, PAD18), Bandit 420 gets Reef Claw 1332012 (dagger, PAD45).
The displaced weapon joins Equip, overflowing at the feet through the existing grant machinery (tier C weapon choices).

All values below come from the branch's original Skill.wz book (tier A); ranks equal canonical levels.

| Key / skill | Branch / weapon | Levels | Effect, first to last level |
|---|---|---|---|
| `claw_mastery` 4100000 | 410 / claw | 20 | mastery 15–60%, ACC +1–20; endless stars ignore recharge capacity |
| `critical_throw` 4100001 | 410 / claw | 30 | crit chance 21–50%, total critical damage 113–200% |
| `endure_assassin` 4100002 | 410 / any | 20 | HP +3–60 and MP +1–20 every 29–10 seconds |
| `claw_booster` 4101003 | 410 / claw | 20 | attack speed +2; HP/MP cost 29–10 each, duration 10–200 seconds |
| `haste_assassin` 4101004 | 410 / any | 20 | speed +2–40, jump +1–20, duration 10–200 seconds, MP15/30 |
| `dagger_mastery` 4200000 | 420 / dagger | 20 | mastery 15–60%, ACC +1–20 |
| `endure_bandit` 4200001 | 420 / any | 20 | same Endure recovery |
| `dagger_booster` 4201002 | 420 / dagger | 20 | same Booster costs, duration and speed |
| `haste_bandit` 4201003 | 420 / any | 20 | same Haste movement, duration and cost |

Mastery, Critical Throw and Booster family tags follow the v83 descriptions (tier C tags; those nodes omit `weapon`).
Boosters invert canonical x=-2 with scale=-1. Buffs auto-cast while inactive and affordable, without a target, holding
alert2 for 0.8 seconds (tier C, existing Booster convention). Haste is self-only and respects speed140 / jump123 caps.
Its text reads `buff_speed` / `buff_jump`, avoiding the projectile `speed` field of resolved skill stats.

Endure heals anywhere, including while moving, with any weapon (owner #167). The additive skill definition is
`periodic_recovery: {interval_field: "time", hp_field: "hp", mp_field: "mp"}`. PlayerUpkeep owns each skill's clock;
RunWorld applies both pools, clamped to their maxima, independently of the shared regeneration pulse. The first pulse
waits one full interval after learning, rank changes retain elapsed seconds, paused/dead worlds do not advance it,
and a round boundary resets it (tier C clock lifecycle). Existing `regen` skills keep their shared-pulse semantics.

Every skill has learn/rank cards, weight2, requiring its exact branch and held weapon through the skill (tier C).
Lucky Seven and Double Stab remain carried attacks for both branches, gated by held weapon and excluded from the
advancement draw. Assassin stars upgrade through Wolbi/Mokbi/Kumbi/Tobi/Steely/Ilbi at 30/35/40/45/50/55, with
the existing notice and current-star sprite. A Bandit holding a claw keeps 2070015. Forced tools accept 410/420 and
the bot draws the first-job family unless an offered family is explicitly forced (`410:claw`, `420:dagger`).
Drain, Savage Blow and Steal are described below; no tuning here.

### 7.25 Drain: the Assassin's healing star (#213)

`drain` (4101005, book410) is a claw-only projectile attack with 30 canonical ranks. Skill.wz supplies damage
102–160%, healing x=16–45%, and MP12 at ranks1–15 / MP24 at ranks16–30 (tier A). It auto-casts one star at the
nearest target through the ordinary nearest/range path. `ammo_shot: true` draws the current Assassin star.
The initial survivor values match Lucky Seven's delivery: range250px, cooldown1s, speed600px/s, radius8px,
no base pierce and shoot1 held0.6s (tier C, untuned). Drain has a canonical effect and lowercase `use` sound,
but no ball, hit animation or action node; the action choice is ours. It uses the normal claw damage formula,
including mastery and Critical Throw, rather than Lucky Seven's special formula.

The additive definition `damage_heal: {percent_field: "x", max_hp_fraction: 0.5, target_max_hp: true}` uses the
shared resolved-hit listener. Every damaging impact restores x% of that line's post-defence/critical damage,
capped separately at the character's MaxHP/2 and that target slot's MaxHP (tier A v83 description / owner #167).
Healing truncates to whole points (tier C), uses the projectile's launch rank and includes lethal hits; current
monster HP does not replace MaxHP. `restore_player` also clamps to missing HP and emits the existing
`player_restored` event only for a positive actual gain. No new RNG, snapshot fields or event schema are needed.

Only Assassin410 gets `drain_new` / `drain_rank` / `drain_pierce`, all power cards and held-weapon gated.
Learn/rank weights4/3, pierce weight2 and +1 pierce per step up to three steps use the shared Potential magnitudes
(tier C; owner behavior budget). A piercing star heals once for each struck monster. Keen Eyes (#209) can extend
the skill through normal range resolution; Drain adds no special range path. No balance tuning is part of #213.

### 7.26 Bandit attacks (#214, spec #167)

Savage Blow 4201005 and Steal 4201004 have 30 ranks, each mapping directly to its canonical Skill.wz level (tier A).
Savage Blow requires a dagger (weapon33), auto-casts in the held weapon's swing envelope, and strikes each target
4 times at ranks1-10, 5 at11-20 and 6 at21-30. Damage follows the original stepped table (40% at1, 80% at30),
including the lower per-line damage at each extra-hit threshold; MP is15/18/27 by those bands. It uses the canonical
`savage` action, effect, hit art and Use/Hit sounds. Its cooldown1.2s, action hold1s and one base target are tier C.

Steal has no weapon requirement, uses canonical `swingO2`, effect and Use sound, and makes one physical melee hit:
42-100% damage, MP12 at ranks1-15 and24 at16-30 (tier A). The tier-C auto-cast uses the existing range-around rule
within100px, one base target, cooldown1.2s and action hold0.6s. Each damaging Steal line on a mob not yet Stolen
rolls canonical `prop`11-40% on `RunWorld.thief_rng` stream15. A failure leaves it eligible. A success immediately
drops exactly one extra item and marks it Stolen before damage/kill resolution, so lethal hits work too. Bosses
can be stolen from: this is a packed per-mob flag, independent of status immunity. Relocation preserves the flag;
a fresh logical spawn, including a reused slot, resets it. Ordinary attacks and other skills never roll for Steal.

`RunWorld.drop_mob_loot(m, single)` is shared by ordinary deaths and living-mob Steal. The normal path retains its
meso-then-equipment rolls, probabilities and stream order. The tier-C single-item interpretation uses the ordinary
equipment chance and job/level/held-family pool on stream10; if that produces no equipment, it guarantees one normal
meso bundle on stream9. It grants no EXP, potions, boss reward shower or kill credit. Only the success roll draws
stream15; a run without Steal retains its previous event/player-state bytes. No canonical drop tables are introduced.

Each attack appends exact-job420 power cards: learn weight4, rank weight3 with30 levels, and targets +1 three times
at weight2 (tier C, existing Potential magnitudes; untuned). Other jobs cannot draw these cards. #215 owns balance
smokes and tuning; #214 performs deterministic mechanics, cache, replay and presentation checks only.

### 7.27 Opt-in combat mechanics (#200, spec #166)

These additive skill-definition keys are generic; this ticket adds no Bowman skill data. Skills without the keys keep
their existing damage, RNG draws and seeded records. Tests use synthetic skill tables, seeded worlds and fixed 1/60 s ticks.

- **`knockback: {"chance_field": "prop", "distance": <px>}`.** Every damaging line on a non-boss rolls once on
  stream 1, including at 0% and 100%; the named canonical level field is a percent. Success slides the mob `distance`
  horizontal px away from the character, following its current foothold chain over slopes and stopping at platform
  edges, walls and map bounds through `FootholdMap.slide_along` (7.13). This is separate from ordinary threshold hit
  push. Statuses survive. Canonical and scheduled bosses neither roll nor move. Airborne mobs and flyers have no
  supporting foothold, so the roll has no displacement (tier C). The distance is survivor tuning (tier C); this ticket
  ships no default distance. A synthetic fixture uses 120 px, not a balance choice for Power Knock-Back.
- **`impact_blast: {"damage_field": "damage", "visual": "hit"}`.** A projectile explodes at its first mob contact,
  consuming the projectile even if it has pierce. The struck mob takes one slot of the canonical `mobCount` cap;
  remaining slots hit live mobs whose bodies intersect the canonical `lt`/`rb` box translated to the primary's feet.
  The geometry is Grenade's shared `SkillRunner.blast_rect`, without facing mirroring. Splash is nearest to the
  primary's body, then slot; selection and the anchor are captured before damage, deaths or knock-back. Each hit
  independently resolves live defence, damage, crit, element, `on_hit` and knock-back through the ordinary callback.
  Immunity still consumes the primary's cap slot. Blasts never recursively create blasts. `damage_field` selects the
  canonical physical skill percent for primary and splash alike; Arrow Bomb must use `"x"` (72 to 130), as it has
  no `damage`. `visual` selects a SkillBook visual (`hit` by default, `effect` also supported), resolved at cast time.
  `skill_impact` plays this art once at the captured impact feet; ordinary per-target hit art also plays. The choice
  of art/anchor, first-contact consumption and target order are tier C; box, cap and selected level values are tier A.
- **`pierce_falloff: <fraction>`.** The n-th direct contact deals `max(floor, 1 - fraction * (n - 1))` of its fully
  resolved damage, including crit bonuses, before final rounding. `balance.combat.pierce_floor` supplies the floor
  to projectiles and skill previews (default 0.1). The schedule and 10% default floor are tier C: WZ has no
  fall-off number. A fraction of 0.1 gives 100/90/80/70/60/50% across six mobs. An immune contact consumes a contact
  index, as it already consumes pierce. Missing or zero means full damage on every mob. The value is captured at
  launch; slot reuse resets it. Impact blasts consume the shot before piercing, so their splash has no fall-off.
- **Ranged Final Attack.** With bow, crossbow, claw or gun held, every follow-up also emits `ammo_shot`, a visual
  flight of the current ammo's `bullet` art from the hand to the same mob's captured body centre. It uses that
  family's existing ammo speed and rotation and a straight line; it draws no RNG and causes no delayed damage.
  The original hit timing, stream-12 rolls, crit and damage are unchanged (tier C presentation). If Spread is
  available, it uses the greater of `BasicAttack.reach` and the family's ranged base reach around the primary.
  Each extra target gets its own visual. Hunter and Crossbowman supply ranged Spread cards (7.29-7.30).

**Previews and cards.** Loadout exposes `knockback_chance` (percent), `knockback_distance` (px), `blast_targets`,
`pierce_falloff` and `pierce_floor` (fractions). SkillText automatically appends these mechanics to rank/learn cards and current/next
Skill-window lines. Rank previews include changing knock-back chance and blast targets. A `skill_mod` effect with
`stat: "blast_targets"` adds splash targets without adding projectiles; projectile `count` still means shots.
`pierce_falloff` modifiers preview percentage points per later mob, and `blast_targets` modifiers preview targets.
Existing `pierce` cards still increase contacts, independently of the fall-off fraction. Hunter and Crossbowman
consume these keys in 7.29-7.30; the combined regression smoke is recorded in 4.2 (#204).

### 7.28 Bowman first job (300, #199, spec #166)

Bowman is playable at Lv 10 (tier C survivor override). The `bow` path wears the instructor's Beginner Bowman's bow
1452051 (tier B gift, tier A stats), moves the creation weapon to Equip and adds Crossbow 1462001 (tier C: the plain
early shop crossbow, Lv 12 / PAD 29 / no stat requirement). Full Equip tabs spill these items at the feet, following
the existing advancement rule. The job grants +125 MaxHP / +37 MaxMP (tier B midpoints, MP truncated), and subsequent
levels give 22 HP / 15 MP (tier B fixed midpoints). Tier-C automatic AP goes to DEX after filling STR to level + 5
through Lv 30, holds STR 35 through Lv 34, then reaches STR 40 at Lv 35 and level + 5 through Lv 70 / STR 75
(held thereafter). The original Lv 1/30 keyframes and allocation through Lv 34 stay unchanged, preserving the #204
Lv 30/31 fixtures. Hunter and Crossbowman inherit this row. A cache-backed seeded level-up test checks all 22 shipped
bows/crossbows against their canonical reqSTR/reqDEX at reqLevel, without equipment bonuses. Bot equipment weights
prefer PAD, then DEX, then STR; other weights follow the existing physical baseline (tier C, untuned).

`skills/bowman.json` and `upgrades/bowman.json` hold the first-job entries. Ranks map one-to-one to every canonical
level (tier A); canonical prerequisite skills are ignored (tier C, shared rule). All values below come from Skill.wz:

| Skill | Ranks | Behaviour |
|---|---|---|
| The Blessing of Amazon 3000000 | 16 | ACC +1..16; ACC also feeds the shared crit coefficient |
| Critical Shot 3000001 | 20 | 12..40% critical chance, 105..200% total critical damage; shared additive critical bonus |
| The Eye of Amazon 3000002 | 8 | +15..120 px range for bows/crossbows (tier C interpretation below) |
| Focus 3001003 | 20 | Self buff: ACC/avoid +1..20, 70..300 s, MP 8..16; auto-cast and recast on expiry (tier C), 0.8 s hold |
| Arrow Blow 3001004 | 20 | Nearest monster, one current-ammo arrow, 190..260%, MP 7..14 |
| Double Shot 3001005 (`bow_double_shot`) | 20 | Two current-ammo arrows via canonical `bulletCount`, 92..130% each, MP 10..16 |

Blessing and Focus allow any weapon, as the ticket's explicit skill table specifies; Critical Shot and Eye apply
only with a bow or crossbow. Both attacks require those families and use the held weapon's shooting stance (tier C).
Attacks use a 300 px base range (neither has canonical `range`), 1 s cooldown, 600 px/s projectiles, 8 px radius,
no base pierce and 0.6 s hold (tier C placeholders, untuned). Double Shot splits over different nearest targets,
reusing them when necessary, like Pirate Double Shot (tier C; original v83 puts both on one mob). Collinear shots
can collide with the nearer monster. Ammo is endless and uses each held family's current arrow sprite.

The generic passive stat `range` adds pixels to ranged basic reach (target box and projectile travel) and to the
resolved range of attack skills explicitly gated to the held ranged family (tier C). The existing passive weapon
gate controls which skills contribute. Melee boxes and untagged Magician skills stay unchanged. Cached basic boxes
keep their base size; the bonus is read live, so rank changes and weapon swaps cannot leave stale reach. Ordinary
skill `range` modifiers apply to the base first, then the passive adds pixels. Stream 14 remains reserved, unregistered;
this feature adds no roll. The unforced job pool gains Bowman on stream 8. Spec #226 subsequently changes
the pool to one entry per job with paths carried separately (section 9).

Each skill has a learn card and a rank card capped at its canonical level count. Each attack also has a +1-shot
behaviour card (up to three steps). Tier-C weights: attacks learn/rank 4/3, other learn/rank 2/2, behaviour 2;
shared Potential rarity magnitudes apply, and cards follow the weapon held when drawn. First-job cards carry into
310/320 through `carry_jobs`; their future advancement draws remain branch-only. Choosing Bowman offers both attacks.

The manifest fragment exports Skill.wz 300/310/320, existing active skill sounds, the two grants, representative
bow/crossbow weapons and all eight arrows moved out of common. CharLevel hit art uses 10/15/20/25 (tier A).
Sound.wz has no 3001005 node, and 3001004 has only Use: Double Shot reuses Arrow Blow's Use sound (tier C fallback),
and neither requests a missing Hit sound. Soul Arrow 3101004/3201004 is never added: endless ammo makes it redundant
(owner decision, tier C). Hunter and Crossbowman are described in 7.29-7.30, equipment in 8.3 and generic impact mechanics in 7.27.

### 7.29 Hunter (310, #202, spec #166)

Hunter is playable at canonical Lv 30. Its one-family grant wears **Ryden 1452005** (Lv 30, PAD 45, STR 35 / DEX 95)
and moves the old bow or crossbow to the Equip tab (overflow drops at the feet). The +325 MaxHP / +175 MaxMP grants
are tier-B second-job midpoints; choosing the plain shop bow is tier C, owner #166. Growth/AP stay Bowman's.

Five bow-only skills in `skills/bowman.json`, book 310, sit before Crossbowman entries. Rank equals every canonical
level; prerequisites remain ignored (tier C, owner #31). WZ numbers, icons, art and sounds are used as-is.

| Skill | Levels | Canonical effect | Survivor behaviour |
|---|---|---|---|
| Bow Mastery 3100000 | 20 | mastery N 1..10, ACC x 1..20 | shared mastery 15..60% and ACC, bow only |
| Final Attack: Bow 3100001 | 30 | prop 2..60%, damage 105..250% | shared stream 12 follow-up; current arrow visibly flies to the same mob (#200); weapon stance held 0.6 s |
| Bow Booster 3101002 | 20 | x=-2, hpCon/mpCon 29..10, time 10..200 s | self-only auto-cast/recast, both costs paid once, HP must remain above zero; alert2 held 0.8 s; only a held bow gets its two speed steps |
| Power Knock-Back 3101003 | 20 | range 130..150, mobCount 2..6, damage 105..200%, prop 13..70%, mpCon 8..15 | `range_around`, faces the nearest admitted mob, 1s cooldown, swingT1 held 0.6 s; non-bosses roll stream 1 to move 120 px away, clamped to platform/wall edges |
| Arrow Bomb: Bow 3101005 | 30 | x 72..130% (no damage field), mpCon 14..28, mobCount 6, box(-130,-100)..(130,100) to(-150,-100)..(150,100), prop 31..60%, time 2..6 s | nearest projectile, own WZ ball; first mob contact consumes the shot, blasts the canonical box around it including the primary; each hit can stun through shared on_hit; bosses resist |

Power Knock-Back uses the tier-B pre-BB bounds: max `(DEX*3.4+STR)*W.Att/150`, min
`(DEX*3.4*0.9*0.1+STR)*W.Att/150`, then canonical damage%, normal PDD/level/crit processing. Bow Mastery
does not raise this swing's fixed 10% mastery. Generic optional `physical_formula` keys `divisor` (default 100)
and `mastery` (default live mastery) express it; its entry sets primary dex, secondary str, max_mult 3.4,
divisor 150, mastery 0.1. The same shape supports Crossbowman's Power Knock-Back. No WZ action exists: swingT1 is
selected from the skill's canonical afterimage actions (tier C). Its afterimage frame is canonically 1x1; it is
played as-is through `effect: .../afterimage/bow/swingT1/2`, with no invented visible trail.

Arrow Bomb uses `impact_blast: {damage_field:"x",visual:"hit"}` and
`on_hit: {status:"stun",chance_field:"prop",duration_field:"time"}`. Its impact plays canonical Hit sound.
Untuned tier-C defaults match first-job arrows: 1s cooldown, 300px base reach, 600px/s, radius 8, no base pierce,
0.6s held weapon stance. Eye of Amazon contributes its shared range passive to both attacks under #199's rule.

The Hunter cards require exact job 310 and a bow, with learn/rank cards for all five skills and no survivor rank compression.
Only the two attacks are power cards, so choosing Hunter guarantees Power Knock-Back and Arrow Bomb in its advancement
draw (plus one seeded passive/Booster). Attack learn/rank weights 4/3; passives/Booster 2/2. Behaviour cards add +1 target
to PKB (`count`), +1 arrow to Bomb (`count`), +1 blast target (`blast_targets`), or +1 nearby Final Attack target
(`final_attack_bow_spread`, `count`), each max 3, weight 2, power. Spread uses the shared ranged Final Attack reach.
Standard Potential rarity magnitudes apply; no vanilla extra counts are added outside cards. First-job Bowman carry
cards remain eligible after advancement per binding #199/#180, outside the branch's advancement draw; this supersedes
#202's stale first-job-card sentence. Crossbow held: all five Hunter skills grey in Skill window, passives/Booster
stop contributing, attacks stop casting and Hunter cards disappear. The existing running buff can survive the swap.
Soul Arrow 3101004 is deliberately absent from skills and cards: endless ammo makes it redundant (owner #166).

The existing Hunter ammo schedule supplies Bronze2060001 at 30, Steel 2060002 at 40 and Red 2060003 at 50, including
the highest reached tier when advancing late. Each upgrade changes the current arrow sprite and emits its notice.
Tool `--job=310` follows Bowman at 10 and Hunter at 30. The combined untuned regression smoke is in 4.2 (#204).
Deterministic tests: `test_hunter.gd`; real-cache diagnostic evidence: `scenes/debug/hunter_driver.tscn`.

### 7.30 Crossbowman (320, #203, spec #166)

Crossbowman opens at the canonical Lv 30 from Bowman. Advancement adds +325 MaxHP and +175 MaxMP (tier B fixed
midpoints), wears Mountain Crossbow 1462000 even when a crossbow is already held, and moves the displaced weapon
to Equip (overflow drops at the feet, ADR 0005). The weapon choice is tier C, the plain Lv 30-class shop crossbow;
its Lv 28 requirement, PAD 44, STR 28 / DEX 80 are canonical. Growth and automatic AP inherit Bowman.

Every skill below needs a held crossbow. A bow disables its casting/passive contribution, greys its Skill window
row and removes its cards from new draws. Skill.wz 320 supplies all canonical level tables, icons and art.

| Skill / survivor key | Levels | Behaviour |
|---|---|---|
| Crossbow Mastery 3200000 / `crossbow_mastery` | 20 | Mastery 15..60%, accuracy `x` +1..20 (accuracy also raises crit chance) |
| Final Attack: Crossbow 3200001 / `final_attack_crossbow` | 30 | Physical hit follow-up, canonical `prop` 2..60% and `damage` 105..250%; stream 12, immediate damage and current-ammo arrow presentation (7.27) |
| Crossbow Booster 3201002 / `crossbow_booster` | 20 | Self auto-cast, recast on expiry; canonical `x` -2 becomes two faster speed steps, `time` 10..200s, `hpCon`/`mpCon` 29..10; refuses lethal HP payment |
| Power Knock-Back 3201003 / `power_knockback_crossbow` | 20 | `range_around` with canonical range 130..150, 2..6 mobs, damage 105..200%, MP 8..15; canonical `prop` 13..70% pushes non-bosses 120px away on stream 1, clamped at walls/platform edges (7.27) |
| Iron Arrow: Crossbow 3201005 / `iron_arrow` | 30 | Nearest-target projectile using its own canonical `ball`, `effect` and `hit`; MP 23..28, damage 122..180%, canonical `mobCount` 6 represented by pierce 5; one base arrow |

Power Knock-Back mirrors Hunter's data shape: `knockback: {chance_field: "prop", distance: 120}` and
`physical_formula: {primary: "dex", secondary: "str", max_mult: 3.4, divisor: 150, mastery: 0.1}` (tier B formula,
fixed mastery; shared implementation #202). It uses a tier C 1s cooldown, 0.6s `swingT1` hold (no canonical action)
and canonical `afterimage/crossBow/swingT1/2` art, whose v83 canvas is transparent 1x1. Iron Arrow uses tier C
`pierce_falloff: 0.1`: contacts take 100/90/80/70/60/50%, continuing linearly to the generic 10% floor past six.
Its tier C defaults are 1s cooldown, 300px reach, 600px/s flight, 8px collision radius and 0.6s held-weapon shooting
hold. Booster's hold is 0.8s. All three active skills have a canonical Use sound and no Hit sound.

The Bowman upgrades file appends these five skills after Hunter's entries. Each has learn/rank cards requiring
exact job 320. Attack learn/rank weights are 4/3; the passive/buff cards use 2/2. Behaviour cards add one target
to Power Knock-Back (`count`), one piercing contact to Iron Arrow (`pierce`), or one Iron Arrow (`count`), max three
steps, weight two, shared Potential rarities. Final Attack also has the shared Spreading Arrow card (+1 nearby
target per step, max three, weight two), drawing a current-ammo follow-up arrow for each target (7.27); this keeps
every damaging skill eligible for a hit-more-mobs card. Extra counts come only from cards; pierce fall-off continues
after the sixth target. The advancement draw includes Power Knock-Back and Iron Arrow; inherited first-job Bowman
cards remain available in ordinary draws through `carry_jobs`, outside the advancement draw.

Soul Arrow: Crossbow 3201004 is deliberately absent, with no skill or card: endless ammo makes it redundant
(owner #166, same decision as Hunter's Soul Arrow). Endless arrows upgrade to Bronze 2061001 at Lv 30, Steel
2061002 at Lv 40 and Blue 2061003 at Lv 50, changing the projectile and emitting the existing upgrade notice.
The tool flag `--job=320` forces Bowman then Crossbowman. These defaults are untuned; the regression smoke is in 4.2 (#204).

### 7.31 F/P high-job pool actives (#290)

All seven skills occupy an active skill slot, auto-cast and use the default eight-rank mapping to WZ levels.
Damage (`mad`/mastery), attack count, mob count, boxes, status chance and status duration come from those levels.
No MP is spent. Bosses take damage but reject every status. Elquines belongs to #291.

| Skill / key | Behavior | First-pass cooldown (tier C) |
|---|---|---|
| Explosion 2111002 / `explosion` | Fire damage in the canonical box around the character, canonical mob count | 1.6 s |
| Poison Mist 2111003 / `poison_mist` | Fixed ground box lasting canonical `time`; checks occupants each second with canonical `prop`, applies existing nonlethal poison, including later arrivals; no direct damage | 3.2 s |
| Element Composition 2111006 / `element_composition` | 500 px/s projectile, 450 px acquisition, one target; fire/poison attributes averaged equally; canonical `prop`/`time` poison uses poison resistance | 0.8 s |
| Fire Demon 2121003 / `fire_demon` | Fire in its canonical forward box; survivors become ice-weak (x1.5) for canonical `time`; other attributes unchanged | 2.0 s |
| Paralyze 2121006 / `paralyze` | Nearest target within 450 px, poison-element damage and existing stun for canonical `time`/`prop` | 1.2 s |
| Meteor Shower 2121007 / `meteor_shower` | Fixed canonical 800×600 box; falling WZ tiles at canonical 180 px spacing; damage after canonical `hitAfter` 1800 ms, targets queried at impact | 4.8 s |
| Big Bang 2121001 / `big_bang` | WZ keydown charge for one 18×60 ms loop, then full `mad` damage with canonical mob count around the current character position | 2.8 s |

Pending areas/releases snapshot cast stats, query live targets, and clear on map transfer. Mist pieces are anchored
to cast feet and expire with the area. Big Bang's survivor box is (-250,-180)..(250,100); its charge is automatic,
without a manual key or partial-charge damage. Element Composition's equal elemental split is tier C (the WZ node
has no `elemAttr`); Fire Demon's ice vulnerability follows its WZ description (tier A). Other targeting/timings
are first-pass survivor interpretations, not balance tuning. Recasts refresh the existing status without stacking.

### 7.32 Player summons (#291)

`kind: "summon"`, `slot: "active"`, `cast: {"rule":"summon"}` uses the same pool, eight mapped ranks,
auto-cast cooldown, damage formula and rarity modifier seam as other active skills. A summon casts without a mob
present. Each cast replaces that skill's previous group; different summon skills coexist. Map transfer removes all
allies (including windups and death art), preserving cooldowns. A later recast restores them. No ally persists in a
character snapshot. Hidden/dead characters' allies cannot attack.

Definition shape for later classes (Phoenix, Frostprey, Bahamut, Octopus, Puppet, Silver Hawk, Golden Eagle):

```json
{"kind":"summon", "slot":"active", "cast":{"rule":"summon"},
 "cooldown":12, "damage":"magic", "element":"i",
 "summon":{"path":"Skill.wz/212.img/skill/2121005/summon", "attack":"attack1",
   "follow_speed":180, "follow_distance":60, "teleport_distance":600, "attack_interval":2.4}}
```

The ordinary skill fields supply WZ book/id, rank table, hit art, Use sound and caster stance. `summon.path` is
presentation's animation root; sim reads the matching skill node's `summon`. `summon.attack` chooses the animation
and its `info`: `range.lt/rb` is the left-facing feet-relative attack rectangle, `mobCount` the target cap, and
`attackAfter` the hit delay in milliseconds. `level.time` supplies lifetime, `level.mad/mastery` damage. Frames under
`summoned/stand/move/<attack>/die` supply animation durations. These are tier A, never balance copies.

Packed arrays store active/position/lifetime/facing/action/age/windup state; cast-time stats and per-group resolved
metadata are cold dictionaries. One SpritePool renders every ally, with no per-entity Nodes. After the summoned
animation, allies follow toward a point behind the character in two dimensions, snap after a large separation,
and seek on both sides of their own position. Attacks face the scheduled boss first, otherwise nearest target
(slot breaks ties). Impact queries current bodies in the facing box; it never remembers recyclable target slots.
Attack timing pauses follow motion. Hits use `RunWorld.hit_mob`, including defence, crit, damage modifiers, element
immunity and Fire Demon's per-mob ice weakness. No additional freeze is inferred from ice damage.

Elquines (2121005, F/P; Ifrit is 2221005) is the first instance. Tier C first-pass choices are its 12 s recast,
180 px/s follow, 60 px trailing offset, 1 px stand/move deadzone, 600 px snap distance and 2.4 s minimum attack cycle (never shorter than the
WZ animation or hit delay). A zero follow speed stops incremental following (distance snapping still applies); future stationary, taunt, projectile,
ground-navigation or pet-like targeting behaviours must extend this seam with their own tests, not special-case IDs.
`damage`, `area`, `count` (attack targets), `attack_count`, `cooldown` consume existing modifiers; `duration` and
`summon_count` are generic summon-specific modifiers (default one ally). Cast snapshots hold damage/area/lines;
new casts pick up rank changes. Rarity lists ship in the skill definition.

### 7.33 Hero pool and Rush (spec #296)

#### Core melee: Power Strike, Slash Blast, Brandish (H5, #301)


Hero remains unselectable until the selection ticket. Its core attacks live in `skills/hero.json`;
Power Strike and Slash Blast were moved from `warrior.json`, with no duplicate keys or weapon gates.
All three use eight ranks: 20-level skills map to 3/5/8/10/13/15/18/20, Brandish to
4/8/12/15/19/23/27/30. WZ damage, HP costs, target counts and boxes are unchanged (tier A).

| Skill | Auto-cast and cooldown (tier C) | Canonical behavior (tier A) |
|---|---|---|
| Power Strike 1001004 | Nearest mob in the weapon swing envelope; 1.0 s, weapon action held 0.6 s | 175% at rank 1, 260% at rank 8; one target |
| Slash Blast 1001005 | Nearest mobs around the caster; 1.6 s, weapon action held 0.6 s; refuses a lethal HP cost | 78% to 130%, six targets, range 130–150 px, hpCon from the mapped level |
| Brandish 1121008 | Forward box, at least one target; 1.4 s | (-150,-110)..(-10,0), two lines, 150% to 260% per line, one to three targets |

Brandish plays **one** body action per cast, `brandish1` for one-handed swords/axes and `brandish2`
for two-handed swords/axes, with `effect/0` or `effect/1` respectively. This is the orchestrator's
ruling over the spec's two-action sequence: the opposite-handed action loses the weapon (H1).
The 0.84 s action hold is the sum of the seven absolute 120 ms body frame delays (tier A).
Use and Hit sounds and hit/0 art come from 1121008. Loadout resolves optional
`action_by_handedness` / `effect_by_handedness` maps; definitions without them behave as before.

Rarity bonuses (tier C) follow the shared card schema: Rare Sword Mastery damage x1.2 for all three;
Epic Power Strike Booster cooldown x0.88, Slash Blast Wide Slash area x1.2 (including radial reach),
Brandish Sweep +1 target. Unique Final Attack adds one damage line; Legendary uses the same
`final_attack` counter and adds damage x1.2. Cards grant exactly one rank; at rank 8 Mastery repeats
shrink by x0.8, including repeats taken before the cap. No standalone behavior cards remain for these skills.

#### Crowd control: Shout and Monster Magnet (H7, #303)

Both are auto-cast pool actives in `skills/hero.json` (books 111 and 112), eight ranks, no MP, no weapon gate, with
`rarity_bonuses` (section 8). Their cooldowns, admission thresholds and action holds are tier C; every number that is a
Skill.wz level field is tier A.

| Skill / key | Cast | Behaviour | Cooldown |
|---|---|---|---|
| Shout 1111008 / `shout` | `box`, `min_targets 3` | Physical damage 14 -> 30 % to the `mobCount` 6 nearest mobs inside the centred WZ box (+-110..200 x +-82..150, scaled by `area`); each struck mob rolls the level's `prop` for a stun of `time` seconds (5 -> 10) through the shared `on_hit` status (bosses and scheduled bosses reject it). Stance `alert3`, 0.6 s hold. | 12 s |
| Monster Magnet 1121001 / `monster_magnet` | `range_around`, `min_targets 3` | No damage. The shared `pull` block (7.35): up to `mobCount` 6 mobs 120 px or more away and within `range` (200 -> 400 px, scaled by `range` modifiers) each roll `prop` (48 -> 95 %) and slide to 60 px from the caster. Stance `alert2` (WZ's `dash` makes a two-handed axe vanish, H1), 0.6 s hold. | 10 s |

- **Shout's rank table (D4).** `ranks` is `[5, 8, 12, 15, 19, 23, 27, 30]`. WZ level 4 has no `prop`: the node stores
  `"58": 38`, a corrupted `prop` (String.wz says 58 %, and the series runs 52, 54, 56, 58, 60), so the standard 30-level
  table (rank 1 = level 4) would give a stun that never lands. Rank 1 reads level 5 (60 %) instead; the other seven ranks
  equal the standard table. A real-cache test asserts that level 4 still lacks `prop`, so a fixed WZ is noticed.
- **`min_targets` on `range_around`.** The cast block's `min_targets` N (default 1, so every existing skill is unchanged)
  admits the cast only when N mobs are inside `range`; the target list is still the nearest `mobCount`. Magnet's admission
  counts every mob in range, including those under the 120 px pull floor that cannot be moved (tier C: simple and readable;
  a cast that moves nothing still starts its cooldown).
- **Bot reach.** `SkillRunner.reach_of` returns 0 for damage "none", so Monster Magnet adds nothing to the melee bot's
  engage reach: it never holds the bot back from walking up to a mob, and a pull never draws it away from one.
- **Rarity** (section 8 schema; Legendary shares the Unique's id and repeat counter): Shout Rare Area x1.2, Epic Booster
  cooldown x0.88, Unique Echo Shout cooldown x0.75, Legendary Echo Shout plus area x1.2. Monster Magnet Rare Reach range
  x1.2 (the spec table says `area`; at H7 `range_around` read only `range`. H5 then made a radial range scale with `area` too, so
  either modifier works; `range` stays), Epic Bigger Grab
  +2 targets (`count`), Unique Booster cooldown x0.75, Legendary Booster plus +2 targets.
- **Bonus audit (merge of #301 and #303).** `test_rarity_bonus_effects` casts every rarity effect of every Hero and F/P skill,
  with and without it, in a seeded world and asserts that the resolved cast changes: damage dealt, casts per 66 s, hit events,
  mobs affected (`count`, `pierce`), allies (`summon_count`), or a mob just beyond the base reach hit only with `area` / `range`.
  Every shipped bonus passes; a negative test shows the probe fails a modifier the rule never reads (`range` on a box, `pierce`
  on Brandish). No bonus was swapped: Slash Blast's Epic `area` works since H5 scales a `range_around` radius by `area`.
- **Text.** `SkillText.level_line` adds "Pulls up to N monsters from R px" for any skill with a `pull` block (the effective
  `mob_count` and `range`, so Bigger Grab and Reach show), after the data's own line ("P% chance for each monster pulled").

#### Rush (1121006, `rush_hero`, #302 H6)

Hero's `mobility_skill` (spec #296 D1): a manual directional dash on the skill key that damages and shoves mobs along its
path. It is the first mobility skill that deals damage; Paladin and Dark Knight get their own Rush the same way. Rush is
learned at round start next to Power Strike (`JobTree.start_skills`), consumes neither slot track, is not in the pool and
is never offered as a card (`UpgradePool` only draws pool skills).

- **Definition.** `skills/hero.json`: `slot "mobility"`, `kind "instant"`, `damage "physical"`, `cast {"rule": "manual"}`,
  `skill_key "rush"`, `displacement {direction "input", when "during", field "lt.x"}`, `knockback {distance 80, direction
  "dash"}` (no chance field), `rush {bot_threat_distance 60}`, action `rush2` (0.6 s), effect `effect` (frame 0 is a blank
  1x1 that delays the streak 100 ms), the dust `effect0` as a `cast_visuals` entry, the `Use` sound. No `ranks` override: the
  level-30 table gives rank 1 = WZ level 4.
- **Input.** `rush` is a skill key (`KeyBindings.SKILL_KEYS`, an action in `project.godot`, X by default like Teleport and
  Dash; a Hero never owns two). Press it with Left or Right to dash that way, otherwise the facing (Up and Down are
  ignored; opposing arrows cancel). Holding repeats once the cooldown is over. Key Config lists it and the HUD quick slot
  shows it with its cooldown sweep (`HudQuickSlot.movement_skill_of`).
- **Movement** (`SkillRunner.cast_dash`, `PlayerMotion.dash_destination` / `dash_to`). Instant, like every displacement
  (7.13): the distance is the box reach `|lt.x|` of the owned level (170 px at rank 1). Grounded it slides along the
  platform (slopes, platform edge, walls, map limits: never off a ledge). Airborne it keeps its height and stops at the
  walls of the platform last stood on and the map limits. It cannot start while climbing. A dash that could not move
  at all is refused with nothing spent: no event, no cooldown. `rush2` plays for its action time. The `cast` event's
  `pos` is where the dash began.
- **Hits.** The swept box of 7.13 (`lt (-170,-50) rb (0,0)`, mirrored by the facing) at the start and at the end of the
  move, and everything between: each mob in it is hit once per dash (one physical line, 78%), up to `mobCount` 15,
  scheduled bosses first. Bosses are damaged and never shoved.
- **Knock-back.** A `knockback` block **without a `chance_field` always applies and draws no random number** (this
  ticket; every earlier block names one). `direction "dash"` shoves each hit mob 80 px along the dash that hit it
  (the `hit.push_side` of the cast), not away from where the character stopped, so mobs the character ran past are pushed on
  ahead of it instead of back toward where it started. `MobSwarm.knockback` takes the optional `force_side`.
- **Cooldown.** 2.0 s (tier C, the balance lever for melee survivability), started by the cast; the HUD reads
  `runner.cooldowns`.
- **Rank.** The job's mobility skill follows the shared `balance.mobility_rank_levels` rule (`RunWorld._level_ranks`, tier C):
  rank 1 at Lv1, rank N at Lv 2N, clamped to the skill's rank cap. Rush has no `ranks` override, so it takes the level-30
  table (eight ranks, WZ levels 4, 8, 12, 15, 19, 23, 27, 30): 78% damage and a 170 px dash at Lv1, 130% and 250 px
  (the box reach) from Lv16. `mobCount` stays 15. No card ever raises it (it is outside the pool). To fix it at rank 1
  instead, give it `"ranks": [4]`. (Spec #296 first said "fixed rank 1"; the shared rule landed while this was built and the
  owner's instruction was to use it.)
- **No orbs.** Rush gives no Combo orb and takes no orb bonus: both belong to pool skills only (the meter reads the pool).
- **Bot** (`BotInput`). Like Teleport: when a mob within 60 px stands on its level (|dy| <= 40) and Rush is ready, it
  dashes **away** from the more dangerous side if that lane lets the dash cover at least half its reach, else **through**
  the crowd the other way if that lane is free; no lane either way, no press. At most once per 3 s
  (`BotInput.RUSH_MIN_INTERVAL`). It never presses Rush with no mob within 60 px, so it never uses it to approach.

#### Combo finishers: Panic and Coma (H8, #304)

Both are meter finishers (7.34: `meter {role finisher, min 5, spend all, damage_per_unit 0.10}`), auto-cast pool actives in
`skills/hero.json` (book 111), eight ranks mapped to levels 4/8/12/15/19/23/27/30, no weapon gate, action `weapon` (the
first swing stance of the held weapon, held 0.6 s). A cast spends every held orb except `meter_keep` and multiplies damage by
`(1 + 0.02 * held) * (1 + 0.10 * spent)` (x1.5 at 5 orbs, x2.0 at 10, before the held bonus); finishers never earn an orb.

| Skill | Cast (tier C) | Canonical behaviour (tier A) |
|---|---|---|
| Panic : Sword 1111003 | `nearest` rule, one target within 250 px, scheduled bosses first (the shared target order), 2.0 s cooldown | 194% (rank 1) to 350%, `prop` 38 to 90%, `time` 5 to 9 s |
| Coma : Sword 1111005 | `range_around`, needs 3 mobs in range, 1.0 s cooldown (the meter floor), HP cost never lethal (can_pay_hp) | 96% (rank 1) to 200%, six mobs, range 130 to 150, `hpCon` 15 to 25, stun `prop` 38 to 90%, `time` 2 to 4 s |

- **Threaten cut (Panic).** `on_hit` `threatened` carries `cut {stat level, cap 20}`: the mob loses `min(skill level, 20)` weapon
  attack and weapon defence (flat, tier C; Panic's node has no such field). Like every status it is refused by bosses
  (MobSwarm.accepts_status), so Panic on a boss deals the damage but never weakens it.
- **Which finisher.** Admission goes through `PlayerMeter.preferred` (7.34): Coma wins with the larger crowd, Panic when a
  scheduled boss is in its range; one owned finisher casts alone.
- **Cooldown (decision).** The spec gives both a "1.0 s floor". Panic's Epic is Booster (cooldown x0.88), which a 1.0 s base would
  hide completely under the 1.0 s meter floor (`SkillRunner.restart_cooldown`), so Panic's base cooldown is 2.0 s and the
  Booster takes it to 1.76 s. Coma keeps 1.0 s: it has no cooldown bonus. The meter, not the clock, paces both in normal play.
- **Weapon-variant art.** `art_by_family {"axe": 1111004 | 1111006}`; `SkillBook.art_skill_id(key, family)` returns the twin id
  for an axe and the skill's own id otherwise, `art_path` re-points a Skill.wz/Sound.wz path at it. Loadout applies it to the
  skill's `effect` and `hit`, the finisher block below to its finish art, and the presentation to the Use sound. Sim numbers are
  shared (the twins are identical in the WZ; only the icon differs).
- **Finish art by orbs spent (tier C reading, no source states it).** A `finish` block `{effect "…/finish/{n}", at, max_n 10,
  advanced_above 5, hit_advanced "…/hit/1"}`: the cast plays `finish/N` for N orbs spent (1..10, so 5..10 for a plain cast and
  fewer with Advanced Combo keeping orbs) and the hit art is `hit/1` above 5 orbs spent, else `hit/0`. Coma's finish plays on the
  caster (the cast event's effect); Panic's plays on its target (a `skill_mob_effect`). Coma's `mob` stun stars are the same art
  the mob renderer already draws for Shout.
- **Rarity (tier C, section 8; repeat scale 0.8).** Panic: Rare Sword Mastery damage x1.2, Epic Booster cooldown x0.88, Unique
  Advanced Combo `meter_keep` +2, Legendary Advanced Combo plus damage x1.2. Coma: Rare Sword Mastery, Epic Wide Reach area x1.2
  (`range_around` scales its radius by `area`), Unique and Legendary as Panic's. Legendary shares the Unique's id and repeat
  counter. Each bonus changes the resolved cast and has its own test (`test_hero_finishers`): damage, cooldown, reach and kept orbs.
  The shared audit (`test_rarity_bonus_effects`) also covers both: its probe tops the meter up for a finisher and adds `meter_keep`
  (orbs left after one cast) to the stats it checks.

### 7.34 Combo meter (#299, Hero H3)

`PlayerMeter` is the round-owned, deterministic M1 counter. Hero's data (H2) supplies:

```json
{"meter":{"id":"combo","max":10,"gain":{"event":"cast_landed","amount":1,"exclude":"finisher"},
 "per_unit":{"stat":"damage","value":0.02},"art":"Skill.wz/111.img/skill/1111002/state"}}
```

A round starts at zero; map transfers preserve it. Each non-finisher pool cast earns one orb on its first
positive damage line, including a delayed impact. Multi-target, multi-line and multi-projectile casts share a receipt;
a missed cast earns nothing. Mobility is outside the pool, so Rush neither earns orbs nor receives their bonus.
The held-unit bonus multiplies the cast's resolved damage bounds and status damage multiplier, preserving its
snapshot through delayed impacts. There is no expiry, timer or RNG. Jobs without a meter keep their old stats/events.

Finisher definitions (H8) add:

```json
{"meter":{"role":"finisher","min":5,"spend":"all","damage_per_unit":0.10}}
```

Admission requires the minimum, normal cooldown, prepared targets and payable HP. At admission, snapshot the held-orb
bonus, retain `round(meter_keep)` units (clamped to 0..held), and multiply damage by `1 + spent * damage_per_unit`.
Finishers cannot earn Combo. Their repeat cooldown has a 1 s floor, even with cooldown modifiers.
When multiple finishers are ready, compare their ordinary target plans: a single-target scheduled-boss attack wins,
otherwise the larger eligible target count wins (capped to strike count); cooldown/learned order breaks ties.
Finisher admission enforces the prepared plan's min_targets, including range_around casts.
H8 supplies Coma's three-target threshold and Panic's range/target rules. No job or skill IDs enter the meter runtime.
The cast snapshot carries meter_spent for H8's finish-art selection; no-meter cast events stay unchanged.
Other auto-skills keep their oldest-ready order.

`meter_keep` is an ordinary skill modifier, available to rarity bonuses and Mastery; previews say “Keeps N orbs”.
SkillText appends “Needs N orbs” and the retained count to card/Skill-window descriptions.
Each actual value change appends `meter_changed {id, value, max}`. HudMeter receives those events, draws max pips
beside the skill icons, and lights value pips. Combo uses the verified orb art at `state/1` (43x42 in v83);
unavailable art uses drawn pips. Jobs without a meter display nothing.

Later jobs can configure `gain.event` to `hit_taken` or `meso_picked` and call `gain(event, events)` at their
event source; H3 wires landed casts only. M23 owns meso pickup coupling; energy/form rules belong to Buccaneer's spec.
The current `per_unit.stat` contract is `damage`; additional stat semantics need an explicit extension.
Paladin uses M2 forms, not M1. Meter state is absent from CharacterSnapshot: a new round always starts empty.

### 7.35 Pull (#300, spec #296)

The mirror of `knockback` (7.27): a generic skill block that drags mobs toward the caster along their foothold chain.
Monster Magnet (1121001, 1221001, 1321001) is the first user; Paladin, Dark Knight and Buccaneer (Snatch) reuse it.
No shipped skill carries the block yet, so no existing record changes.

```json
"pull": {"chance_field": "prop", "range_field": "range", "min_gap": 60}
```

- **Keys.** `chance_field`: the canonical level field read as a percent (empty or absent means always). `range_field`:
  the reach in px (`"range"` reads the resolved `range` stat, so area/reach modifiers apply; any other name reads that
  canonical field). `min_gap`: the closest a pulled mob ends from the caster, in px. Optional `min_distance` overrides
  the 120 px floor below. The cap is the resolved `mob_count` (canonical `mobCount` plus count modifiers).
- **When.** `SkillRunner.apply_pull` runs once per cast of any non-buff skill with the block, right after the `cast`
  event (before the damage lines of a skill that also hits, as Snatch will). It scans the live mobs itself; it does not use
  the cast rule's target list.
- **Selection (tier C).** Candidates are live, grounded, non-boss mobs whose body centre is within `range` of the cast
  origin and whose feet are at least 120 px away horizontally. Scheduled bosses, canonical bosses, airborne mobs and
  flyers are never candidates and never spend a slot. The `mob_count` farthest candidates are taken, farthest first
  (horizontal distance; the lower slot breaks ties). Mobs under 120 px are left alone: they are already in the pile.
- **Roll.** One draw per taken candidate, in that order, on the main stream (`world.rng`, stream 1): pulled when
  `draw * 100 < chance`. No draw at a chance of 100 or without a `chance_field`. A 0% chance still draws (as knockback does).
  A miss keeps its slot; selection happens before the rolls.
- **Move.** `MobSwarm.pull` slides the mob toward the caster's x with `FootholdMap.slide_along` by
  `max(0, |dx| - min_gap)` px, so it never crosses the caster. It follows slopes and linked footholds and stops at the
  platform's end, at a wall (EPS short of it) and at the map bounds. A mob already inside the gap is rolled and not moved.
  Statuses survive. Each mob that moved emits `mob_pulled {mob, from, pos}`.
- **Pull-only skills.** A skill with `damage: "none"`, a `pull` block and a `box`, `weapon_reach` or `range_around` rule
  deals no damage lines (`_resolve_cast` skips the instant strike); casting admission stays the cast rule's
  (`range_around` admits on one mob in range unless the cast block says `min_targets`: Magnet's 3, 7.33).
- **Loadout.** `stats()` carries `pull_chance` (percent, 100 for no field, 0 without a block) and `pull_gap` (px) for card
  and Skill-window text (H7).

### 7.71 HP-risk skills (#351, spec #348, roster M17)

Four small data-driven behaviours in one stateless file, `game/scripts/sim/hp_risk.gd` (`HpRisk`): a percentage HP cost, an
HP gate, recoil as a share of the damage a cast dealt, and a low-HP damage bonus. Dark Knight (Dragon Roar, Sacrifice,
Berserk) is the first user; Bishop, Buccaneer and any later job reuse the blocks unchanged. No skill ships a block yet, so no
existing record changes. No RNG is drawn.

```json
"hp_cost":     {"field": "x", "of": "max_hp"}
"hp_gate":     {"above": 0.5}
"self_damage": {"field": "x", "of": "damage_dealt", "cap_max_hp": 0.10}
```

- **`hp_cost`** (`of`: `"flat"` is the default and today's `hpCon` rule, `"max_hp"` is a percentage). The cost is
  `floor(field / 100 x max HP)` for a percentage, the canonical field as it is for flat (`field` defaults to `hpCon`), then
  scaled by the `hp_cost` modifier and floored. It resolves into the same `hp_cost` stat every consumer already reads
  (admission, `RunWorld.can_pay_hp`/`spend_hp`, the bot, `PlayerMeter.preferred`, the Skill window), against the max HP
  `RunWorld` keeps in `Loadout.max_hp`; the stat is resolved again when max HP changes. A cast never pays the last HP
  (`can_pay_hp`): it waits, spends nothing and takes no cooldown.
- **`hp_gate`.** Admission also needs current HP strictly above `above` x max HP, read at the moment of the cast from the
  exact (fractional) HP. A refused cast waits like an unpayable one. After a costly cast the gate usually closes, which
  blocks the next cast until potions, Aura or regeneration refill HP: that loop is the identity of Dragon Roar.
- **`self_damage`.** After the cast's instant lines resolve, the caster loses `floor(field / 100 x damage applied)`, where
  damage applied is the growth of `RunWorld.damage_dealt` over the cast (every line on every target, after Berserk), at most
  `floor(cap_max_hp x max HP)` and never the last HP (`floor(HP - 1)` at most). 0 when the cast dealt nothing. It pays
  through `RunWorld.spend_hp`; there is no admission, the cast already happened. Shots and ground areas that land after
  `_resolve_cast` returns are not counted (tier C; no shipped HP-risk skill uses one).
- **`low_hp_damage`** (a modifier stat, a rarity bonus): `HpRisk.begin_cast`, after `PlayerMeter.begin_cast`, scales the
  cast's `damage_min`, `damage_max` and `status_damage_mult` by `1 + bonus` while HP is at or below `HpRisk.BERSERK_BELOW`
  (0.5) of max HP, read before the cost is paid. The bonus adds (`+0.5` is x1.5).
- **Modifier stats** (rarity bonuses, `Loadout` skill mods, card previews, `SkillText`): `hp_cost` (mul: scales a flat or a
  percentage cost), `self_damage` (mul: scales the recoil percentage; the cap does not move) and `low_hp_damage` (add). The
  card text names them "HP cost", "Recoil" and "Low-HP damage"; `LevelUpWindow` shows before -> after for each.
- **Event.** `hp_spent {skill, skill_id, amount, kind}`, `kind` `cost` or `recoil`, only when `amount > 0` and `amount` is what
  was actually paid. A flat `hpCon` skill (Slash Blast, Coma) emits it too, with `kind: cost`, before its `cast` event; a
  recoil follows the cast's hits. `RunScene` shows it as a red number at the player through the damage-number pool (`HP_SPENT`).
- **Text.** The Skill window and tooltips add "Needs more than 50% HP", "Recoil: 20% of damage dealt (at most 10% of max
  HP)" and "+50% damage at 50% HP or less" to a skill's line; the cost is the ordinary HP cost fact.

## 8. Upgrades

**ADR 0006 / #287 supersedes the old draw rules below.** Every new/rank card gives exactly +1 rank regardless of
rarity; active rarity still rolls with Fortune and the existing odds, with #288 bonuses documented below. Standalone behaviour
cards and job-specific buffs/passives are excluded from draws. `UpgradePool.card_kind` classifies owned_active,
new_active, passive_rank, new_passive and mastery. The per-card weights in `upgrades.json.draw_weights`
are 1.2/1.0/0.8/0.5 respectively (mastery reserves 1.2). Slots stop new skills of their kind at six; owned rank
cards remain eligible until the skill's cap. Common passive definitions opt in with `common_passive: true`, use
`slot: passive`, carry their own rank table, and get Normal-only cards. The nine common passives ship in #289 (8.5).
Draws sample three distinct cards without replacement. Sparse draws add one Power Elixir alternative. Pity is gone.
Each boss retains its separate bonus draw; random/first policies still choose from the same offers. The sensible
bot scores every declared pool skill (new 100, rank 74); these are existing attack priorities, not balance tuning.


**#288 rarity bonuses and Mastery (supersedes rarity multipliers below).** Each active card grants one rank,
then its rarity bonus. At rank 8 the same `<skill>_rank` id becomes `card_kind: mastery`, grants zero ranks,
and stays eligible at weight 1.2. A Normal Mastery grants +5% damage on that skill, or cooldown x0.95
when its `damage` is `none` (#346). Both use repeat id `mastery_damage`, shared by every Normal Mastery
of the skill, so the 0.8^n diminishing returns apply. These are tier C owner decisions (#288/#346): Normal
Mastery is never a dead pick. The damage default comes from `upgrades.json` `mastery_bonus`.
A Rare+ Mastery gives its rarity bonus instead. The literal `damage:none` rule also applies to Poison Mist
(its poison damage is secondary), as well as Monster Magnet; the paired F/P records do not exercise that post-cap choice.
Boss draws retain their Rare floor. Common passives remain Normal and stop at their own cap. Standalone behaviour cards for
the four ported skills are deleted; unported lines retain their inert legacy definitions for direct mechanics tests.

Bonus schema for #290/#291 and later classes: add `rarity_bonuses` to the skill definition in `skills/<line>.json`:

```json
"rarity_bonuses": {
  "rare": [{"id": "damage", "text": "Damage", "effects": [{"stat": "damage", "op": "mul", "value": 1.2}]}],
  "epic": [{"id": "pierce", "text": "Pierce", "effects": [{"stat": "pierce", "op": "add", "value": 1}]}],
  "unique": [{"id": "extra", "text": "Extra projectile", "effects": [{"stat": "count", "op": "add", "value": 1}]}],
  "legendary": [{"id": "extra", "text": "Extra projectile and damage", "effects": [{"stat": "count", "op": "add", "value": 1}, {"stat": "damage", "op": "mul", "value": 1.2}]}]
}
```

No Normal entry. Each tier list cycles in authored order, using the sum of its entries' repeat counts modulo list
length; no extra RNG is consumed. Every effect in the selected entry applies to that skill through
`Loadout.add_skill_mod`. Supported existing stats include damage, cooldown, count (projectiles or targets by kind),
attack_count, pierce, area, range, speed and crit; a new mechanic must first be implemented by its skill runtime.
Use `slot: active` for ground/summon definitions and implement their consumption of these modifiers in #290/#291.
`id` is stable within the skill: sharing an id across tiers shares repeats. Repeats include pre-Mastery awards.
Repeat n scales additive effects by `0.8^n` and multipliers by `1 + (value - 1) * 0.8^n` (first award n=0).
Counters use `loadout.card_ranks["bonus:<skill>:<id>"]`, round-local; no new save schema. Integer mechanics accumulate
fractional modifiers and use the existing round-to-nearest conversion in resolved skill stats (some repeats give no
immediate extra projectile). Preview uses the same effects without mutating the world. Cards show survivor rank step,
bonus magnitude and effective before/after values. Bot bonus score uses actual diminished effects and gain_step_score;
Mastery has no rank base score. All schema selection rules, sizes and scoring are tier C, provisional until T11.

First-pass lists: all four have Rare damage x1.2. Epic Energy Bolt/Fire Arrow +1 pierce, Magic Claw/Poison Breath
cooldown x0.88. Unique +1 projectile (Magic Claw +1 hit); Legendary the same signature plus damage x1.2.

First-pass lists for the seven #290 actives (tier C; each tier has one entry, Legendary shares the Unique's id and adds
damage x1.2, so their repeats are shared; Rare is `power`, damage x1.2, for all):

| Skill | Epic | Unique / Legendary signature |
|---|---|---|
| Explosion | area x1.2 (`area`) | +1 hit (`echo`) |
| Poison Mist | area x1.2 (`area`) | cooldown x0.8 (`linger`) |
| Element Composition | +1 pierce (`pierce`) | +1 projectile (`twin`) |
| Fire Demon | area x1.2 (`area`) | +1 target (`crowd`) |
| Paralyze | cooldown x0.88 (`haste`) | +1 hit (`echo`) |
| Meteor Shower | area x1.2 (`area`) | +1 hit (`echo`) |
| Big Bang | area x1.2 (`area`) | +1 hit (`echo`) |
| Elquines (#291) | area x1.2 (`reach`) | +1 ally (`twin`, stat `summon_count`) |


**Cards and the draw (current rules).** `data/survivor/upgrades.json` (base: draw weights, the rarity weights and magnitudes,
the Mastery bonus, the Power Elixir fallback) and `upgrades/<line>.json` hold the cards; `UpgradePool.add_pool_skills`
adds a standard `<key>_new` and `<key>_rank` for every implemented pool skill without an explicit card. A card has `id`,
`kind` (`skill_new`, `skill_rank`, or `filler` for the fallback), `skill`, `icon`, `name`, `desc`, `max_rank`, `requires`
and `effects`; a `weight` on a card is present but unused, because the weight comes from the card's draw category.
Standalone behaviour cards (`skill_mod`), stat cards, job-buff cards and per-job passives are not drawn.

1. **Eligible** (`UpgradePool.is_eligible`): the card's rank is below its `max_rank` and its `requires` hold (owned skills,
   minimum ranks, minimum level), and
   - an **active** skill's card needs the skill in the job's `skill_pool` and an implemented definition; `skill_new` also needs
     the skill not owned and a free active slot, `skill_rank` an owned skill (a capped active stays eligible: its rank card
     becomes its Mastery card);
   - a **passive** card needs a common passive (`common_passive: true`); `skill_new` needs a free passive slot, `skill_rank` an
     owned passive below rank 5.
   When a slot kind is full, new skills of that kind stop being offered. There is no weapon, level or job-advancement test.
2. **Weights** by `UpgradePool.card_kind`, from `upgrades.draw_weights`: owned active (rank card) or Mastery 1.2, new active
   1.0, passive rank 0.8, new passive 0.5. Three distinct cards are drawn without replacement with the run's card RNG
   (stream 3); Fortune changes rarity only. There is no pity, reroll, banish or skip.
3. **Rarity** (8.1) is rolled per card after the identities are drawn: active cards roll it, common passives and the Power
   Elixir are always Normal. Every skill card gives exactly **+1 rank** whatever its rarity (a new skill starts at rank 1).
4. **Fallback.** With fewer than three eligible cards the draw offers those plus one **Power Elixir** (item 2000005); with no
   eligible card it offers the Elixir alone, and a pool with no card at all consumes the level instead of opening an
   unanswerable window. This applies to level-ups and boss rewards alike, and the Elixir is always accepted. It fully
   restores HP when chosen, and has its own filler score for the bot. The item identity, name, icon and the 100% restoration
   are tier A; the reward rule is tier C.
5. **Applying** a card takes effect at once: the new rank (its WZ level through the rank table), then the rarity bonus
   through `Loadout.add_skill_mod`. The level-up window keeps the "You've gained a Level!" header and mascots, shows
   `Active n/6   Passive n/6` under the level and a row per card: its rarity label, the rank change ("Rank 4 -> 5" or
   "NEW Skill Lv. 1"), the bonus text and the changed canonical numbers (Magic ATT, mastery percent, duration), read at the
   mapped WZ level without survivor modifiers (tier A) except the rarity bonus's own effect (tier C).
6. **Boss bonus draw.** Each boss kill adds one draw after the reward shower, with the Rare floor of 8.1; it keeps the
   same eligibility, and the level-up window's heading reads as a boss reward (`choice_pending.bonus`).

**The hit-more-mobs rule (#84) and its test were replaced** by the rarity-bonus lists: every pool skill defines all four
rarity lists with effects (`test_data_files` requires it), and the Unique and Legendary entries are where a skill gains
projectiles, hits or targets. Support and movement skills (Teleport) have no cards.

### 8.1 Fortune and card rarity (#30 / #43, reworked by #287-#289)

Fortune is a survivor run stat in `player_state.fortune`, separate from canonical LUK. Its base is
`balance.player.fortune` (0) plus (spec #34) the live Fortune of the character's filled cash slots
(`player_state.fortune` = own Fortune + `RunWorld.cash_fortune`). Only cash items the account owns count; anything
else worn is ignored with a world warning. The cash part is never written into the CharacterSnapshot, so it cannot
compound across rounds; values per slot are in section 11. It changes only card rarity, leaving drop and critical rolls
untouched. Every offered **active-skill card** (new, rank, Mastery) rolls a rarity using the card RNG stream 3 after the
card identities are selected; a common passive card and the Power Elixir are always Normal. A choice retains its final
`tier` while pending, and selecting its id applies +1 rank and that rarity's bonus (section 8; the bonus lists and
their repeat shrinking are above).

| Rarity | Normal | Rare | Epic | Unique | Legendary |
|---|---|---|---|---|---|
| Base weight at Fortune 0 | 75 | 18 | 5 | 1.7 | 0.3 |
| Bonus (tier C first pass, per skill in `rarity_bonuses`) | none (a Mastery gives +5% damage) | small: damage x1.2 | mid: area x1.2, pierce or cooldown | the skill's signature: +1 projectile, hit, target or ally | the Unique signature plus damage x1.2 |

The weights are the spec #30 values (`upgrades.rarity.weights`; the owner restored them on 2026-10-15; tuning waits for the
balance pass). Every non-Normal weight is multiplied by `1 + max(0, Fortune) x upgrades.rarity.fortune_scale` (0.02), then
weights normalize together: at Fortune 100 the weights total 150, i.e. 50/36/10/3.4/0.6%. Rarity no longer multiplies the
rank gain: the old per-tier rank tables, the headroom downgrade, the new-skill starting rank by rarity and the stacking
steps are gone (#287, #288). A rank card at rank 8 is a Mastery card (8): it adds no rank, only the rarity bonus.

Boss bonus rolls promote Normal to Rare (the floor), so a boss draw's active cards carry at least a Rare bonus; the Power
Elixir stays Normal and is the fallback. Tier C.

The balance record has `card_tiers_offered` and `card_tiers_picked` per run (displayed rarity, one count per card); the
SYSTEMS summary sums them. From #293 the record also has `picks` (cards taken) and `six_actives_at` (the time the sixth
active slot filled, null if it never did).

Level-up and boss-reward cards keep the v83 skill-row art and show the rarity with a 2 px frame and a label band
tinted with the rarity colour: Normal white, Rare blue, Epic purple, Unique gold, Legendary green
(`#FFFFFF / #77BBFF / #CC99FF / #FFCC44 / #77DD88` over `#17344F` at 30%; tier C). The label carries the meaning
independently of colour. New skills show their starting level in the rank line (`NEW  Skill Lv. 1`, plus `MAX` when
that is the cap). Unchanged canonical values are omitted from the preview. Dense windows shorten prose first and
keep the panel 128 px shorter than the view so the mascots and HUD stay clear (tier C layout).

A window with a Unique or Legendary offer plays `Sound.wz/Game.img/mCardGet` once when it opens (owner-approved by
ear on 2026-10-15). Automated picks without a window are silent. The debug gallery shows the rarities with
`--window=levelup_tiers|levelup_high|levelup_dense|levelup_mastery` (`--bonus` for the boss heading); screenshots stay in
ignored `evidence/`.

The Magnet card (+25% pickup radius) was removed in spec #225: the radius stays at `magnet_radius` and the pet's VAC and
Binocular upgrades are the only pickup-range upgrades. The Beginner cards (Nimble Feet, Recovery), the Magician's MP cards
(Improved MaxMP Increase, Improved MP Recovery) and every per-job buff or passive card are removed with the Beginner,
advancement and MP (#284, #285); Recovery survives only as the common Regen passive (8.5).

Research for the potion ladder and its Lv 1-70 schedule: `docs/research/v83-potion-progression.md` (spec #225, #227).
Potion tiers are no longer cards (spec #225, #228): they follow the level schedule of section 5 (HP Red -> Orange at
Lv 10 -> White at Lv 25 -> Unagi at Lv 40 -> Ice Cream Pop at Lv 60; #229), keep the remaining cooldown; stock and potion
drops are gone (#237). No canonical item value is changed, and the bot has no potion-card scoring.

Skill prerequisites (`Skill.wz` `req`) are ignored (tier C owner decision #31). A rank card still requires its skill owned.

### 8.2 Skill and card text (#81)

Player-visible skill text comes from one presentation source, `SkillText` (`game/scripts/ui/skill_text.gd`): a
skill's v83 `String.wz/Skill.img` `desc` and its line for a level (`hN`, named by the level node's `hs`). A survivor
override in `skills.json` (`text.desc`, `text.h`) replaces either one where this game behaves differently. A level-line
override is a template filled from the skill's **effective** stats (`Loadout.stats(key, rank)`, so behaviour cards
count: a +2 targets card on Thunder Bolt makes the line say 8), then the canonical fields of that level. The level-up
window and the Skill window tooltips (#86) use it.

- **Learn card:** the skill's desc and the line of its starting level (level 1 for Normal, higher for rarer tiers);
  the line is never shortened.
- **Rank card:** the next level's line, above the before → after values it already showed.
- **Mod card:** its own effect text from `upgrades.json`, plus the effective value it changes, e.g. "Targets: 1 → 2",
  "Cooldown: 1.1 s → 0.97 s" (`choice_pending` card `skill_mod_changes`, measured on a scratch loadout).
- Cards keep their `upgrades.json` text where the cache has no String.wz (and for stat and Elixir cards).
- `#c…#` is drawn in the skill-window orange and `\n` breaks the line; other `#` codes are dropped, never drawn.
- WZ descs lose their "[Master Level : N]" line (the level text already shows the cap) and their "Required Skill"
  lines (WZ prerequisites are ignored, #31). No player-visible text says "canonical".

Overridden skills (everything else shows the WZ text unchanged: Nimble Feet, Magic Guard, Magic Armor, the three
MP Eaters, Invincible and both Slows):

| Skill | Overrides | Why |
|---|---|---|
| Recovery (1001) | desc, h | WZ text says MP 10 and 10 min between uses; v83 data is `mpCon` 5 and `cooltime` 120, and here it fires below half HP, healing `x` HP every 5 s |
| Three Snails (1000) | h | adds the shells per throw (Additional Shell cards) |
| Energy Bolt (2001004) | desc, h | "one enemy": Extra Bolt cards fire more bolts |
| Magic Claw (2001005) | desc, h | Twin Claw cards strike more monsters |
| Fire Arrow (2101004), Holy Arrow (2301005) | desc, h | "a single monster": extra-arrow and pierce cards |
| Poison Breath (2101005) | desc | "a single monster": pierce cards |
| Cold Beam (2201004) | desc, h | Spreading Frost cards freeze more monsters |
| Thunder Bolt (2201005) | desc, h | "all monsters in the range": it hits up to its mob count (canonical 6 plus cards) |
| Heal (2301002) | desc | party healing: here it heals you below half HP and strikes every undead in its box |
| Meditation (2101001, 2201001) | desc, h | "party members": self-only |
| Bless (2301004) | desc | "party members", "cannot be combined": self-only; its accuracy raises the critical chance (6.1) |
| Teleport (2101002, 2201002, 2301001) | desc | "arrow keys": the Teleport key plus a direction, hold to repeat |
| Rage (1101006) | desc | "everyone in the party around the area": it affects you only |
| Power Guard (1101007, 1201007) | desc | the WZ text says "damage received" and "enemy": here only monster contact damage is returned, half against bosses (7.10) |

### 8.3 Mesos, equipment drops, scrolls and shops (spec #33)

Bowman equipment (#166/#201) lives in its own `equipment_drops`, `scrolls` and `shops` line files. The curated
regular progression has 12 bows (1452000-1452011), 10 crossbows (1462000-1462009) and 202 reqJob-4 armour items
through Lv70: hats, tops, bottoms, overalls, shoes and gloves, with no shields. Selection is tier C; each item's
canonical requirements, stats, icons and animation remain tier A. Cash, restricted, event/Maple and instructor-only
variants are excluded. A Bowman's weapon drops come from its job's weapon families (bow and crossbow are separate families).
Both ATT scroll families stock ordinary 100/60/10 and dark 70/30 at the existing rate NPCs for the existing
70,000-meso weapon price. The shop's job filter admits both families for Bowmen; applying a scroll still requires
its matching held family. This adds no drop-rate, band, meso or price tuning. The regression smoke is in 4.2 (#204).

The economy loop, in the order a character meets it (terms: `GLOSSARY.md` "Mesos and equipment"; decisions: ADR 0002;
every constant, with its tier, is in section 11 under the tables named below):

1. **Mesos** drop from kills (40% per kill from the mob's v83 meso range, x14 survivor multiplier) and 4 bundles from
   each boss, with the v83 coin sprites; the magnet collects them like EXP. They are carried across rounds with the
   character and lost with the run. ("Meso rule", section 11.)
2. **Equipment** drops from kills (0.2% per ordinary kill, two guaranteed from each boss): a v83 hat, top, bottom,
   overall, shoes, gloves, shield or weapon that the character's job class can wear, with v83's random stat rolls. Since
   #292 a drop never depends on the character's level or the weapon it holds: the stage's tier fixes a `reqLevel` band
   (`stages.json` `drop_bands`: tier 1 [0, 30], tier 2 [30, 60]) that an ordinary drop lies in (uniform among the
   eligible items) and a boss drop lies in the top third of (tier 1: Lv 20-30, tier 2: Lv 50-60). A weapon drops only
   when it belongs to one of the job's weapon families (`survivor/jobs/<line>.json` `weapon_families`; 212: wand and
   staff). Equipment has no level or stat requirement to wear; only the item's job class (`reqJob`) is checked, by the
   Equip and Item windows, the auto-wear and the bot shop alike. It goes to the
   Equip tab (24 slots; a full tab leaves the item on the ground). ("Equipment drop rule".) If its slot is empty and the
   job class admits it, it is worn at once instead, with an "Equipped <name>" notice (#222, "Auto-equip rule").
   It still waits in the tab when the slot is occupied (an item is never replaced, even by a better one), its job class
   is another, it is a shield beside a two-handed weapon, or it is a top or
   bottom beside an overall or an overall beside a top or bottom.
3. The **Equip** (E) and **Item** (I) windows wear, take off and discard it, in a round (the run is held while they are
   open) and in the Free Market; worn equipment adds to the character's stats and is what is drawn. (Controls above.)
4. In the **Free Market**, four NPCs sell scrolls only, one per success rate (100%, 60%, 10%, dark 70% / 30%), at 35,000
   mesos (armour, shield) or 70,000 (a weapon: wand, staff, sword, axe, blunt weapon, spear, polearm); any shop buys spare equipment and scrolls back at their v83 sell price. NPC
   Chat (Space) or a double-click opens a shop. ("Scroll NPCs", "Shop stock", "Sell rule" and the other #111 rows.)
5. A **scroll** is dragged from the Use tab onto a worn item: it succeeds at its rate (adding its v83 stats and one to
   the "(+N)" count) or fails; either way it spends one upgrade slot, and a failed dark scroll can destroy the item.
   ("Scroll rules", "Scroll effect" and the other #110 rows.)
6. Mesos, worn equipment, the Equip tab and scrolls stay with the character (ADR 0006, #292): `CharacterSnapshot` hands
   them back after a clear, a death or a Quit round with whatever the round picked up, and the save file keeps them
   (format 3). A round always starts at Lv1, so the gear it wears is whatever the character already owns.
7. Bots follow the same rules (`BotShop`): they wear the best item they own and visit the shops between tiers of a
   `balance.sh --tier=N` chain. ("Bot shopping rule".)

Verified by the `shops`, `scrolls`, `botshop` and `redesign` flow scenarios (AGENTS.md; the old `economy` scenario was retired in #294) and by the combined regression smoke in 4.2
"Spec #33 / #113". The numbers above are first-pass and are not tuned: equipment per round measured 5-7 against the
8-12 target (4.2 #109, #113), and the dedicated balance pass (#77) owns them.


### 8.4 NX, the Cash Shop, cash equipment and the pet (spec #34)

Terms: `GLOSSARY.md` "Account and NX"; decision record: ADR 0003. Every number below is tier C unless section 11 says
otherwise; the dedicated balance pass sets them.

**NX and the account.** A run keeps nothing but records, so every round pays **NX** into the **account**, the part of
the save file that outlives characters (`account: {nx, owned}`; no account block = 0 NX and nothing owned). A clear pays
`clear_bonus[tier] + 5 x levels gained + 40 x bosses killed` in that round (clear bonus 100 / 250 by tier), a death the
same without the bonus; deletion, Quit round and tool rounds pay nothing. The NX is written in the same atomic save as
the clear's Free Market boundary or the death's run archive, so it is spendable at once. It shows as the "NX earned" row
of the results screen, as a six-second "You have gained N NX." notice on arriving in the Free Market, and as the balance
at the end of the map-select heading.

**Cash Shop.** The SHOP button (map select, every tier, and the Free Market status bar) opens the v83 `CashShop.img`
screen as the current character, so a brand-new character can shop before its first round. Only the EQUIP. and PET tabs
exist; prices are the real Commodity prices. An item is bought once per account (it leaves the list, nothing is sold
back), never expires and works for every character at the same time. Pet upgrades need a pet; VAC (survivor-only) needs
Wing Boots, Binocular and a pet.

**Cash equipment and Fortune.** Eleven cash slots (hat, face, eye, earrings, top, bottom, shoes, gloves, cape, weapon,
shield) are worn from the **Cash tab** of the Equip window (E, in rounds and in the Free Market) by double-click; the
item is drawn instead of the regular equip of its slot. Each filled slot adds a fixed **Fortune** (10 / 8 / 8 / 6 / 10 /
10 / 9 / 9 / 10 / 12 / 8, sum 100; an overall fills top and bottom, a two-handed weapon cover weapon and shield). Which
item fills a slot only changes the look. Fortune is computed live from what is worn and owned, never written into the
character (no compounding), and changes card rarity only (section 8.1). Cash items have no other stats.

**Pet.** The Pet page of the Equip window (PET EQUIP.) brings one owned pet out (Brown Kitty, Brown Puppy or Pink Bunny).
It follows the character on the same platforms, teleports when left behind, and picks up every drop kind near it (Item
Pouch and Meso Magnet are built in); it has no hunger, lifetime or commands. Upgrades belong to the account and apply to
whichever pet is out: Auto HP / MP Potion Pouch drink below the HP / MP ALERT levels as soon as the character's shared
per-kind cooldown is ready (spec #237). A pet drink starts the same timer as a manual drink, adding convenience without
extra healing. The ALERT levels are set in
Options (defaults 30 % / 20 %), Wing Boots fetch resting drops, Binocular doubles the pickup radius, and VAC pulls every
drop on the map to the pet. Since spec #225 these are the only pickup-range upgrades (no card raises the radius).

**Tools.** Tool rounds (balance, playtests, `--run`) start with an empty account; `--account=<json>` supplies owned items,
worn cash equipment, a pet and ALERT levels (`game/tests/fixtures/accounts/full_pet.json` is the full set) and the round
record gains `nx_awarded`, which is never credited. With an empty account every record is byte-identical to a build
without this feature (regression smoke, section 4.2).

### 8.5 Common passives (#289, spec #282)

Nine job-neutral passives fill the six passive slots. Each is a skill definition in `skills/common.json`
(`common_passive: true`, `slot: passive`, `ranks: [1..5]`, so rank r is level r and the cap is five) with a `skill_new`
and a `skill_rank` card in `upgrades/common.json`. They never roll rarity and always give +1 rank; they join the draw at
the passive weights (0.5 new, 0.8 rank), and `new` cards stop being offered once six passives are held. The effect per
rank is `passive.per_level` in the unit of its stat; the totals add across ranks (rank 5 is five times rank 1).

| Passive (display name, icon art) | Stat | Per rank | Where it applies |
|---|---|---|---|
| Might (Maple Warrior) | `damage_pct` | +10% damage | `Loadout.stats`: every damaging skill's damage range, with cards |
| Max HP (Hyper Body) | `max_hp_pct` | +20% Max HP | `RunWorld.refresh_player_stats`: scales base+growth+equipment, then the Hyper Body buff; the new HP is granted |
| Speed (Haste) | `speed_pct` | +10% move speed | `RunWorld.player_speed_stat`, after the v83 140 cap (rank 5 = 150%); the Stat window shows it |
| Regen (Recovery) | `regen_pct` | +1% of Max HP per second | continuous, every tick, beside the 10 s pulse and Recovery-type skills |
| Cooldown (Spell Booster) | `cast_speed_pct` | +8% cast speed | active skills' cooldown x (1 - cast speed), the whole cooldown factor floored at x0.35 of the base; Teleport is untouched |
| Area (Dragon Roar art) | `area_pct` | +10% skill area | `Loadout.stats().area`: box skills' box and every reach that reads it |
| EXP (Holy Symbol) | `exp_pct` | +8% EXP | `RunWorld._gain_exp`: every EXP gained (orbs, boss EXP); the fraction below one point carries over |
| Armor (Iron Body) | `armor_flat` | -2 damage per hit | `RunWorld.take_hit`: after defence and Invincible, physical and magic, never below 1 |
| Crit (Sharp Eyes) | `crit_chance` | +5% crit chance | the existing passive crit stat (`Loadout.CRIT_CHANCE`, percent) |

Pickup radius is not a passive, so the pet's Binocular and VAC keep that job. The Skill window has a first **Common**
tab (the Beginner tab glyph, nobody is a Beginner now) listing all nine with `level / 5`, unlearned ones greyed; its
tooltip shows the effect line at the current and next rank. The Stat window shows a **PASSIVES n/6** panel in its free
top-right corner. The level-up card shows the effect line at the offered rank ("Damage +30%"), the rank
("Skill Lv. 2 → 3") and `MAX` at rank 5. The sensible bot scores new passives 66 Might, 64 Booster, 62 Sharp Eyes,
60 Max HP, 58 Area, 56 Armor, 54 Regen, 52 Haste, 50 EXP and each rank card 4 less, all below any pool attack
(`balance.bot.card_scores`). Every number above is tier C; ticket #293 (first-pass pacing) adjusts them.

## 9. Jobs

`data/canonical/jobs.json` holds the Explorer tree with canonical ids (Beginner 0; Warrior 100, Magician 200,
Bowman 300, Thief 400, Pirate 500; second jobs 110-130 / 210-230 / 310-320 / 410-420 / 510-520; third and fourth
jobs) and stays untouched; `JobTree` reads it for names, tiers, books and lineage (`lineage(id)` is the job and its
ancestors, which per-job tables resolve through).

**A character has one job, chosen at creation, and it never changes** (ADR 0006, #284). There is no job advancement:
no job window, advancement draw, `Not now`, level-10 or level-30 milestone, weapon page or path, job weapon grant,
per-job HP or MP bonus, branch draw by the bot, or `weapon_path` in the snapshot. The Beginner is not playable. The
tools' `--job=<id>` names the character's job for a fresh character (`JobTree.parse_job`; a `<id>:<family>` spec is
refused); only a playable job is accepted, anything else fails at startup, and a `--character` file's own job wins
(a disagreement fails).

Where a job's data lives (one seam per fact, all tier C unless noted):

| What | Where | 212 today |
|---|---|---|
| Playable | `survivor/jobs.json` `jobs.<id>.playable`, set by the line file | true; `JobTree.playable_jobs()`; `default_job()` = `survivor/jobs.json` `default_job` (212, tier C, #298) while that job is playable, else the first playable job |
| Starting skill, key skill, pool | `survivor/jobs/<line>.json` `starting_skill`, `mobility_skill`, `skill_pool` | Energy Bolt; Teleport (F/P, outside the slots); twelve keys (section 8) |
| Creation weapon | same file, `creation_weapon` | Wooden Wand 1372005 (the Magician line's v83 starting wand; wearing it checks only the job class) |
| Weapon families of drops | same file, `weapon_families` | wand, staff (a job without a list drops no weapons) |
| AP rows | `balance.player.ap.<job>` `{primary, secondary, keyframes}`; the lineage fallback | INT primary, LUK secondary (one row, no redistribution) |
| HP growth | `balance.growth.<job>` through the lineage | Magician +12 HP per level; level-ups add no current HP (`level_up_refill.hp` 0) |

`DataRepo` merges the per-line job files the same way as skills, upgrades and equipment drops, so a class spec adds its
own `jobs/<line>.json` (plus its skills, cards, drops and AP rows) and flips `playable`; the sim reads jobs through `JobTree`
(`docs/ARCHITECTURE.md` 4.4.4). The title shown from Lv1 is the job's canonical name ("Arch Mage (Fire, Poison)").
`RunWorld.set_job` is the only writer of the job; every round learns the job's starting skill and its key skill at rank 1.

Hard rules that replaced the old advancement text: skill prerequisites (`Skill.wz` `req`) are ignored (owner decision #31);
a card is on offer only when its skill is in the job's `skill_pool` or is a common passive (section 8); a skill never needs
a held weapon. The jobs of the other lines keep their canonical rows, their skill data and tests, and stay unplayable.

**Melee-aware movement (#162).** The bot reads the reach of its attacks through `SkillRunner.reach_of(stats, world)` (a
projectile or nearest-rule skill its range, a box skill its far edge with area modifiers, 0 for buffs, manual, status
and heal casts). When the longest attack it owns reaches under `bot.engage.kite_reach` (220 px) it stops kiting: it walks
to 0.8 x the reach of its longest ready attack from the nearest on-level mob within 300 px and stands facing it. Below 35%
HP, or while a boss attack winds up, it kites as before. Every F/P attack reaches 260+ px, so the F/P bot kites and the
melee branch is exercised only by the unported lines' tests (`test_bot_melee.gd`). Constants: `bot.engage` in
`balance.json`, tier C (section 11).

## 10. Presentation

- 800x600 logical view (wider windows show more map at the same pixel scale), integer scaling, nearest filtering. An
  opt-in "fill window" setting fills large windows with more map instead of black bars (see View fit below).
- HUD: independent status-bar, counter, skill-icon and message widgets receive state from RunScene. The original
  gauges, level, job name, timer, kill count and skill icons keep their layout. Decorative controls on the bar's
  right side are removed, except the Menu button at the bar's right end and the quick slot's collapse button above it; the **v83 quick slot** (#220,
  `StatusBar.img/base/quickSlot`, 151 × 80, a 4 × 2 grid) stands above the bar's right end, display only. Its 8 cells are, in a fixed order, top row
  **HP potion, MP potion, movement skill, Jump** and bottom row **Equip, Item, Stat, Skill**; each shows the icon Key Config uses for that
  action (`KeyActionArt`) and a small caption of the **first key it is bound to** (nothing when unbound; web-reserved keys such as F11 are
  captioned too); the potions show their current item's icon without a stock number and share the skill icons' dark
  clockwise cooldown sweep (`CooldownSweep`, 1/96 steps, redraw only when a step changes); the movement cell shows Teleport
  or Dash, whichever the character has learned, and stays empty until then. The v83 `QuickSlotD` arrow button (the `QuickSlot` up arrow while
  folded) hides and shows the panel; the state is kept in `settings.cfg` `[hud] quick_slot_collapsed` (default shown). Captions update at
  once after Key Config OK. Separate buff and boss widgets reserve space below the kill count and timer. Full-run pacing and structural checks cover progression, EXP collection, Magician
  advancement, boss-only completion, late ordinary hits and no lost mobs (4.1.1).
- Text uses the system's Arial (Tahoma, Dotum) at MapleStory sizes, or the bundled Arimo (SIL OFL, metric compatible
  with Arial) where the system has none, as in browsers. Since #224 (2026-10-18) the window draws canvas items at its
  own pixel size, so text is rasterised at the window's resolution (sharp at 2x/3x, in fill-window and below 800x600)
  with the same logical size, line height and position; sprites, maps, UI art and WZ bitmap digits keep their
  pixel-scaled look. Antialiasing is one constant, `MapleFonts.ANTIALIASED` (tier C; false by default, crisp hinted,
  closest to v83; the owner chose crisp from the A/B screenshots, PR #235, 2026-10-19).
- Stage region and continent (`stages.json`, #221) on the stage card, the results screen and at run start; the WZ map and street names are not shown.
- Death: `Effect.wz/Tomb.img` tombstone falls on the character with `Game.img/Tombstone`.
- Results: the login book's Back banner returns to character select; death/victory frees the ended character's slot.
- Frame rate: vsync on and capped at the display's refresh rate (`Settings` `[display] max_fps`; 0 = refresh rate,
  -1 = uncapped); `--vsync=off` uncaps it for perf runs.

## 11. Constants and provenance


### Review #282: constants and provenance

| Rule | Value / source | Tier |
|---|---|---|
| Bot passive policy | balance.bot: after 3 actives, +20 passive score; Mastery effect score ×100; authorized bot behaviour fix | C |
| Mobility rank progression | balance.mobility_rank_levels: rank 1 at Lv1, then rank N at Lv2N through rank 20 at Lv40, clamped to each mobility skill cap; shared across jobs | C |
| Summon ordinal spread | summon.ordinal_spread: 36 px on x for each additional ally, at spawn and follow destination | C |
| Ground status RNG / refresh | stream 18; ground data names status, element and chance field; refresh preserves pending poison pulse while updating duration and damage, direct hits retain restart policy | C |
| Capture delay | skill.capture_delay: Paralyze 0.3 s, Big Bang 1.38 s | C |
| Frame timing fallback | WeaponInfo.frame_times uses 100 ms for missing or zero frame delay | C |


### #346 Hero survivability (tier C)

HP600 at round startup from job AP row, HP65/level; five ungated pool cooldowns x.4;
Combo per-unit damage .05, both finishers damage_per_unit .20. Owner-authorized first-pass
training under #346 (section4.2), superseding original Hero values in sections7.33/7.34.
Normal Mastery for `damage:none`: cooldown x.95 with the same mastery_damage counter and .8^n
diminishing; preview and bot use the resolved bonus. Shared default/F/P values are unchanged.

### #307 opening ramp (tier C)

Whole-round interpolation, clamped progress raised to optional `power` (default 1), HP at spawn,
ordinary damage after defense at impact, boss HP/contact/attack scale frozen at actual arrival:
all are our survivor design. Tier 1 HP/damage 1 -> 1 over 900 s. Sleepywood map 1 HP .3 -> 1 / damage .4 -> 1
(power 6), map 2/3 HP .02 -> 1 / damage .08 -> 1 (power 3), all over 1,200 s on the whole-round clock;
trained only on 1/2/2026. The 20:00 endpoint intentionally extends past the nominal 15:00 schedule.
No ordinary rate/cap/pool, boss encounter scale, canonical stat, EXP/cooldown/passive/drop value changed.
Revised slice target: picks ≈ levels + boss draws (~50–60).

### #293 first-pass pacing (tier C)

All new values are our survivor tuning, trained only on seeds 1/2/2026: EXP `(a,b,c)=(4,0,8)`;
F/P pool cooldowns x0.4 (Bolt .36, Claw .5, Arrow .4, Breath .5, Explosion 1.6, Mist 3.2,
Composition .8, Demon 2, Elquines 12, Paralyze 1.2, Meteor 4.8, Big Bang 2.8 seconds);
Hyper Body 40%/rank, Recovery 2% Max HP/s/rank, Iron Body 6/hit/rank; NX 2/gained level.
Bot: three-actives threshold, passive preference +20, Mastery 100 points/unit of diminished effect.
Regression bounds: six slots 0–360 s, clear Lv40–60 / 42–62 picks, engagement >=0.15, >=1/3 Henesys clear.
These replace older first-pass/inherited pacing statements where they conflict. No frozen assessment performed.


| #290 constant / interpretation | Value | Tier / source |
|---|---|---|
| High-job cooldowns, targeting | Table 7.31; 450 px nearest acquisition; projectile speed 500 px/s, radius 10; cast stance 0.8 s | C: first-pass survivor data, #282/#290 |
| Mist ground occupancy | 1 s checks, no direct hit; canonical poison chance/time; all occupants; tile strips 80 px apart | C: survivor ground-area interpretation; A: WZ box, prop/time, existing poison formula |
| Composition elements | Mean of fire and poison multipliers; poison status checks poison alone | C: equal fire/poison interpretation of the skill's description; no WZ elemAttr |
| Fire Demon ice weakness | Timed x1.5 ice, replaces ice resistance/immunity; bosses reject it | A: WZ description/time; C: existing boss status exclusion |
| Meteor delay / tile spacing | 1.8 s / 180 px | A: WZ hit/0/hitAfter and tile/effectDistance |
| Big Bang full-charge release | 1.08 s; box (-250,-180)..(250,100), follows caster until release | A: 18 keydown frames × 60 ms, full-charge mad; C: one-loop automatic release and box |


| Rule | Value | Tier | Source |
|---|---|---|---|
| Normal Mastery #288/#346 | +5% damage, or cooldown x0.95 for `damage:none`; shared repeat id `mastery_damage`, x0.8^n repeats; bot scores the resolved effect (5, then 4 points) | C | owner decisions #288/#346 |
| #290 rarity bonuses | Rare damage x1.2; Epic area x1.2 (Composition +1 pierce, Paralyze cooldown x0.88); Unique/Legendary +1 hit (Composition +1 projectile, Fire Demon +1 target, Poison Mist cooldown x0.8); Legendary adds damage x1.2; section 8 | C | ours; first pass, T11 tunes |
| #291 Elquines rarity bonuses | Rare damage x1.2; Epic area x1.2; Unique +1 ally (`summon_count`); Legendary adds damage x1.2 and shares the Unique's repeats; every pool skill now has all four lists (`test_data_files`); common passives (#289) never roll rarity, get a bonus or Mastery; section 8 | C | ours; first pass, T11 tunes (T9 proposed haste for Unique and +1 ally for Legendary: changed to the Unique/Legendary convention above) |
| Rarity/Mastery #288 | Rare damage x1.2; Epic +1 pierce or cooldown x0.88; Unique +1 projectile/hit; Legendary signature plus damage x1.2; repeats x0.8 (multiplier distance from 1), authored-list cycling and actual-effect bot scores | C | ours; ADR 0006, first pass, section 8 |

Rows added by #286 (save format 3 and the round loop): the Arch Mage's creation weapon is 1372005, the Wooden Wand
(`jobs.json` `creation_weapon`, tier C: the Magician line's v83 starting wand; its item id and stats are tier A);
tier unlocks follow "clearing a stage of tier N unlocks tier N+1, tier 1 always open" (tier C, owner, ADR 0006); a
death or Quit round keeps the round's pickups and unlocks nothing (tier C, owner); the Quit round warning text, the
history labels (cleared / died / quit / retired / deleted), the greyed locked-tier cards on map select and the Job page
layout (one row per job inside the charSet panel) are ours (tier C).

| #287 survivor rule | Tier / source |
|---|---|
| 6 active + 6 passive slots; mobility outside slots | C: owner ADR 0006, reference survivor loop |
| Curated 212 pool, Energy Bolt start, Teleport mobility | C: owner spec #282; original numeric skill IDs remain in definitions |
| Eight ranks; ceil(r × WZ maxLevel / 8), per-skill table overrides | C: owner #282/#287; WZ levels themselves unchanged (A) |
| Per-card draw weights 1.2 owned / 1 new / 0.8 passive rank / 0.5 new passive; reserved mastery 1.2 | C: owner #282 |
| Bot pool new/rank scores 100/74 | C: existing attack priorities applied to declared pool, #287 |
| Common passive per-rank values (#289): Might +10% damage, Max HP +20%, Haste +10% speed, Cooldown +8% cast speed, Area +10%, EXP +8%, Crit +5% | spec #282 table; the reference survivor loop; ticket #293 adjusts | C | Owner #282 / #289 |
| Regen +1% of Max HP per second per rank (the reference's +0.5 HP/s on its 100 HP, here on our 50 HP start) | `skills/common.json` `regen_pct` | C | #289 |
| Armor -2 flat damage per hit per rank, minimum hit 1 (the reference's 1 per rank scaled to our damage: Henesys mobs hit for tens) | `armor_flat` | C | #289 |
| Cooldown factor floor x0.35 of the base cooldown (`Loadout.COOLDOWN_FLOOR`), applied to the product of cards and cast speed | the reference | C | #289 |
| Haste applies after the v83 140 speed cap; Max HP passive scales before the Hyper Body buff; EXP bonus carries the sub-point fraction | design choice, parity untouched | C | #289 |
| Common passive icons: the identical-art Adventurer skill's book (Maple Warrior 2112, Hyper Body/Haste/Holy Symbol/Dragon Roar art 910, Recovery 1000, Iron Body 1100, Spell Booster 1210, Sharp Eyes 312) | `asset_manifest.d/common.json` | A | #283 |
| Common passive bot scores 66/64/62/60/58/56/54/52/50 new, 4 less per rank card, below pool attacks | `balance.bot.card_scores` | C | #289 |


| Constant / choice | Value | Tier | Source |
|---|---|---|---|
| Playable jobs and start skills (#284) | `survivor/jobs.json`: 112 and 212 are playable (spec #296); 212 is the default (`default_job`) for a fresh character and the tools; every round of 212 learns Energy Bolt and Teleport (2101002) at rank 1 (`start_skills`), Teleport on its key from Lv1 | C | Owner, ADR 0006 / spec #282 (Energy Bolt stands in until #287) |
| Auto-AP rows (#284) | `balance.player.ap`: one `{primary, secondary, keyframes}` row per job, nearest ancestor's row otherwise, all AP to STR without a row. 212: INT primary, LUK secondary at the old Magician keyframes (Lv1 3 -> Lv200 202); the 200/100/300/400/510/520 rows keep the unported lines' old single rows | C | Owner, spec #282 (212); the rest the earlier tier C rows without weapon paths |
| Hero playability and QA fixture (#306) | Playable 112 and 212; default 212. `hero_t2.json`: seed 1, bot, invulnerable Henesys clear, tier 2 unlocked; all equipment from the tier-1 drop band. Diagnostic equipment fixture, never survival evidence | C | Spec #296; fixture `_doc` |
| Hero AP row (#298, spec #296) | `balance.player.ap["112"]`: STR primary, DEX secondary, keyframes Lv1 -> 4, Lv200 -> 204 (the secondary DEX target tracks the level plus about 4, the v83 Warrior gear pattern). HP growth is not re-listed: 112 inherits the Warrior row (100: 26 per level) through the lineage | C | Spec #296 |
| Hero creation weapon (#298, spec #296) | `survivor/jobs/hero.json` `creation_weapon` 1302000, the plain Sword (reqJob 0, so wearing it checks no class); `weapon_families` `["sword", "axe"]` filters the existing Warrior drop list (one- and two-handed), armour and shields drop by the Warrior class bit; the weapon item id and stats are tier A | C | Spec #296 |
| `default_job` pin (#298, spec #296) | `survivor/jobs.json` `default_job` 212: the job of a fresh character and of every tool run, test and oracle that names none, so Hero never changes it by becoming playable; Hero is always chosen explicitly (`--job=112`, the creation Job page). The owner can flip it with this one line | C | Spec #296, risk found while checking the slice |
| Hero bot card scores (#305, spec #296) | `jobs/hero.json` balance.bot.card_scores: `<key>_new` 100 and `<key>_rank` 74 for each of the seven Hero pool skills (power_strike, slash_blast, brandish, shout, monster_magnet, panic, coma), the same numbers every F/P pool skill has (the default attack scoring, 100 and 62 + 12 job bonus), set explicitly so the meter-gated finishers and the pull, which the default scorer would not take for attacks, are taken whatever their cast rule | C | Spec #296 |
| Hero hub kit (#305, spec #296) | `HubTestKit.HERO_KIT_SCROLLS` (every rate of the ATT scrolls of the sword, two-handed sword, axe and two-handed axe, 20 stacks of 10) and `HERO_KIT_EQUIPMENT` (1002001 hat, 1402000 two-handed sword, 1082002 gloves, 1040010 top), used for a character of job 112; `--hub --job=112` opens `hero_t2.json`; 500,000 mesos as for F/P | C | Ours, a test aid |
| Job page rows (#305) | rows are left-aligned, and the chosen row keeps its plate in every Button state (hover and pressed too), so it stays highlighted under the mouse; the Job blurb repeats the weapon box (creation weapon name, WATK, swing time) | C | Ours, layout |
| Rush 2.0 s cooldown, always-on 80 px knock-back along the dash, hold-to-repeat, refused while climbing, airborne dash keeps its height (#302, spec #296) | `skills/hero.json` `rush_hero` (`cooldown`, `knockback`); damage 78%, `mobCount` 15, box reach 170 px (the dash distance) and `rush2` are Skill.wz level 4 (tier A) | C | Spec #296 D1; v83 Rush is a dash with a hit box |
| Rush ranks with the round level through `balance.mobility_rank_levels` (rank 1 = WZ level 4 at Lv1, rank 8 = level 30 from Lv16) (#302) | the shared mobility rule; Rush has the level-30 rank table and no card | C | Spec #296, #282 review fixes |
| Rush bot rule: dash from a mob within 60 px (on the bot's level), away when the lane covers half the reach else through the crowd, at most every 3 s (#302) | `skills/hero.json` `rush.bot_threat_distance` 60; `BotInput.RUSH_MIN_INTERVAL` 3.0, `RUSH_LANE_FRACTION` 0.5 | C | Spec #296 |
| Cards on the job line (#284) | A card is eligible when one of its `requires.jobs` is the character's job or an ancestor (`UpgradePool.on_line`); no `carry_jobs`, no advancement draw, no weapon check; Beginner and Teleport cards deleted | C | Stopgap until the skill pool (#287) |
| Removed RNG streams (#284) | Streams 5 (the basic attack) and 8 (bot job draws) are reserved and never drawn; no other stream is renumbered | C | Keeps every other stream's seeded sequence |
| Region cards and ending-map results (#241, #247) | Map 1's mapMark beside the region; three ordered `map name → boss name` rows in the existing v83 parchment, each wrapping as needed with a 6 px gap between rows. Objective: "Defeat 3 bosses across 3 maps". Results keep region/continent and add the ending map's WZ name and mapMark, with a 6 px gap before stats | C layout/text; A map/boss names and marks | Owner #241 / #247; String.wz and each map's `info/mapMark`. Summary identity comes from `RunWorld.current_map_id()` |
| Region map order and pool declarations (#241, #243) | Henesys: 104040000 / 104010001 / 100030001; Ellinia: 101010100 / 100040100 / 100040105; Sleepywood: 105050400 / 105090310 / 105090900. Map 1 declares `pool: "curve"`; later maps declare life-list pools, except Sanctuary's explicit Cold Eye 4230100 ×5, Tauromacis 7130100 ×2, Taurospear 7130101 ×5; Pig Beach excludes Iron Hook 4090000 | C | Owner #241 Implementation Decisions; owner pool policy; StagePools resolves canonical life lists |
| Map boss delay and curve offset (#241) | `map_seconds = 300`; boss relative `time = 300`; curve time = zero-based map index x 300 + time since entry. Entry uses spawn stream 2; existing streams, including reserved 7, retain their numbers | C | Owner #241; deterministic map transfer |
| Map-1 pool cutoff (#241) | Last curve pool at or before curve time, considering only keyframes with `t < 300`; life pools count ordinary entries, skip hidden/event variants; exclusions and Sanctuary override are in the map-order row | C | Owner #241; no other pool tuning |
| Map transfer carry and settlement (#241) | Freeze on map boss death; sweep all pickups once, resolve choices, discard ordinary mobs without drops/kills; preserve HP, buffs, Hidden, cooldowns, kills and damage; clear boss statuses; random destination `sp` on stream 2; no mid-round save | C | Owner #241 |
| Camper map ownership (#241, #248) | Henesys top/rope park only on map 1 id 104040000; Tree top only on Ellinia map 1 id 101010100. Later maps use the sensible bot; camper activation/arrival/portal metrics refer to map 1 | C policy, A map ids | Owner #241; no placement rescue after knockback |
| Maps flow diagnostic (#248) | Training seed 1, invulnerability (the Lv10 Warrior/Sword page probe went with advancement, #284), diagnostic lethal boss hits only after each map's 300 s timer; fixed-tick warp with 600-tick yields and 1800 s cap | C | Tool-only flow evidence; no survival/balance claim |
| Henesys opening (#241, #243) | t0 rate 0.25 / alive cap 6; t120 0.55 / 11; t180 0.75 / 15; t240 onward and all keyframe pools unchanged | C | Owner #241; the spec's only balance change |
| Potion model (#237, #238) | Unlimited HP potions (no MP, #285); no stock, starter quantities or drops; old snapshot counts ignored without a format bump; tiers derive from starter items plus level; every round including Continue starts ready, cooldowns never saved | C | Owner 2026-10-21, spec #237 |
| Potion cooldowns (#237, #238) | HP 20 s (`balance.potions.cooldown`) in fixed sim time; paused windows freeze the timers, tier-ups preserve them, presses during cooldown silently do nothing | C | Owner 2026-10-21, spec #237 starting values; no tuning |
| Pet pouches (#238) | Below the HP ALERT and ready: share the player's cooldown, without a separate delay | C | Owner 2026-10-21, spec #237 convenience rule |
| Desktop save lease (MS-02) | Renew every 5 real seconds and on successful writes; takeover after 30 seconds without renewal; lost owners refuse writes until a fresh committed-state reload | C | Persistence safety policy, not gameplay tuning; `SaveData.WriterLock`, `SceneFlow`, ARCHITECTURE 4.2 |
| Reserved performance key (MS-10) | F3 is fixed on desktop and web, captioned Perf in Key Config; old saved action bindings drop F3 and retain their other keys | C | Existing RunScene diagnostic shortcut; `KeyBindings.RESERVED` |
| Finale precedence (MS-07) | Last mandatory answer after all scheduled bosses die settles without another damaging tick; active-tick death still wins | C | Owner decision, 2026-10-21 |
| Finale collection (MS-08) | Sweep all remaining pickup kinds once using normal pickup accounting; resolve resulting level/job/card choices with combat frozen before carry. Full-tab equipment retains the existing blocked-on-ground rule and is left behind at clear | C | Owner decision, 2026-10-21; existing Equip pickup capacity rule |
| Bot weapon choices (#232) | Uniform job-stream-8 family draw at each multi-family advancement unless that advancement offers the forced family; no implicit branch preference (an unforced second job keeps the held family since #261). BotShop upgrades the recorded family | C | Owner #226; binding decision 7 |
| Weapon path migration and AP (#230) | Pathless saves use the held family at the deepest multi-path ancestor, else its first path; keep inventory. AP lookup falls back from job:path to plain job at each ancestor and re-splits earned AP on advancement | C | Owner #226 and binding implementation decisions |
| Banish destination (MobSkill 129, #256) | A random `sp` portal of the current map dropped onto the floor below it (`PortalSet.start_point_away_from`, the map-arrival rule; the widest platform's middle on a map without `sp`), drawn uniformly on the dedicated stream 17 `banish_rng` so no other stream shifts. With two or more `sp` portals the one nearest the character is left out ("thrown elsewhere"); a single `sp` is used even if the character stands by it. The placement clears velocity, ladder and foothold, and an out pet is put beside the character like a map arrival (`pet_teleported`). 103000101 has two, (-258, 138) and (1115, 66), both landing on the y 198 platform, so a Banish there always lands at the other one | C (adaptation, nearest-portal exclusion: lead #256 review), B (destination: a random portal, Cosmic's server) | Owner #253; v83 `info/ban/banMap` sends the character to 103000100 Subway Ticketing Booth, outside the round |
| Shade's arrival on 103000101 relative to the `sp` portals (measured, #253 review) | Seed 1, Lv38 F/P fixture `fp_arch_mage.json`, `bot` policy, Kerning City (headless `boss_spawned` pos, cache with the #253 manifest): Shade arrives at 604.47 s at (653.9, 198), 250 px (`spawn_distance`) left of the character at (903.9, 198) on the y 198 platform. Its Banish box there spans x 453.9..853.9, y 48..248, so neither `sp` portal, (-258, 138) nor (1115, 66) (nor their y 198 landing points), lies inside it at arrival; the nearer, (1115, 66), is 261 px past the box's right edge. The arrival point follows the character (the boss arrival rule), so other seeds and builds land elsewhere | Measurement, not a constant | Seed-1 headless record, #253 review |
| Banish cooldown and cast rule (#256) | A boss entry's `skill_intervals` (`{"<skill id>": seconds}`) replaces that skill's WZ interval for both the first use after arrival and each recast; Shade's entry carries `{"129": 15}` (WZ 3 s). Banish is cast only with the character inside its canonical area lt(-200,-150) rb(200,50) around Shade's feet (prop 100: no roll; the one character whatever `count` 5 says), so a miss spends no cooldown; not cast while Hidden; Shade plays `skill1` | C (15 s; in-area gating, v83-like, accepted in the lead #256 review), A (area, prop, WZ interval) | Owner #253; v83 MobSkill.img/129/level/5 |
| Banish message and art (#256) | System notice "As the Pentacle swayed in the shadows, you were thrown elsewhere in the Subway." (Shade's survivor `mobs.json` `banish_message`, reworded from v83 banMsg "... you were brought to the Subway Ticketing Booth."); `MobSkill.img/129/level/5/affected` plays once at the character's feet (pos 0); the camera snaps to the arrival. Not reproduced: Shade's eva 999 (the sim reads no mob avoid), the lamp NPC 1052107, `removeAfter` | C (text, anchor), A (art, original text) | Owner #253; Mob.wz/5090000.img/info/ban |

Drain (#213) additions:

| Constant / choice | Value | Provenance |
|---|---|---|
| Drain canonical values | 30 ranks; damage102–160%, x16–45%, MP12/24 stepping at rank16, claw47, effect and lowercase use sound | A Skill.wz410.img/4101005 and Sound.wz |
| Drain healing caps | each hit: at most character MaxHP/2 and target MaxHP | A v83 String.wz description; owner #167 |
| Drain integer healing | truncate fractional HP after resolved damage, clamp to missing HP; launch rank applies | C integer interpretation and existing projectile/restore seams |
| Drain cast | nearest, one star, range250px, cooldown1s, speed600px/s, radius8px, pierce0, shoot1 hold0.6s | C initial untuned Lucky Seven delivery convention; current ammo sprite via ammo_shot |
| Drain cards | learn/rank weights4/3, exact410, power; pierce +1 ×3, weight2 | C owner #167 behavior budget and existing attack-card convention; A rank cap30 |

| Bandit attacks (#214) | Values | Tier / source |
|---|---|---|
| Savage Blow | weapon33; ranks1-30, stepped damage40-80%, attackCount4/5/6, MP15/18/27, savage/action/effect/hit/sounds | A: Skill.wz/420.img/skill/4201005 and Sound.wz |
| Steal | ranks1-30, damage42-100%, prop11-40%, MP12/24, swingO2/effect/Use, no weapon field | A: Skill.wz/420.img/skill/4201004 and Sound.wz |
| Bandit auto-cast | Savage Blow weapon_reach, action hold1s; Steal range_around100px, hold0.6s; both cooldown1.2s, one base target | C: initial survivor choices, untuned |
| Steal loot/lifecycle | stream15 once per damaging line until success, including lethal hits/bosses; one equipment roll on10 then meso fallback on9; preserve Stolen on relocation, reset on fresh spawn | C: owner #167 success/lifecycle, guaranteed-single-loot interpretation reuses ordinary content rules |
| Bandit cards | exact job420, power, learn/rank weights4/3, target weight2, +1 target x3 | C: owner #167 target budget, existing card conventions/Potential |

Disorder (#210) additions:

| System | Values / rule | Tier and source |
|---|---|---|
| Disorder 4001002 | 20 levels; MP 5..10, signed PAD/WDEF x/y -1..-20, time 7..60 s; any weapon, mob art and Use sound | A: Skill.wz/400.img and Sound.wz/Skill.img/4001002; no canonical box/count/action/effect |
| Disorder crowd | at least 3 eligible ordinary mobs; nearest 6 in (-250,-150)..(250,150); 1 s cooldown, alert2 held 0.8 s | C: survivor adaptation, matching low-rank Threaten's reach; untuned |
| Disorder interrupt | cancel a recipient's pending pre-impact attack and stance, retain its existing next-attack wait; no stun, no undo of impacts or launched balls | C: our interpretation of v83 text "stunting the ongoing attacks"; Threaten remains unchanged |
| Disorder presentation/cards | own mob animation once at recipient centre, shared Threatened cue while active; learn/rank weights 3/2, job400 only, no behavior cards | C: presentation and card choices; A: mob art and rank cap20 |

Thief second job (#212) additions:

| Constant / choice | Value | Provenance |
|---|---|---|
| Assassin / Bandit advancement | Lv30; +325 MaxHP / +175 MaxMP | A canonical level; B v83-facts section4 fixed midpoints |
| Advancement weapons | Steel Guards1472008 / Reef Claw1332012 | C owner #167 selection, unconditional wear and existing Equip overflow; A item stats |
| Branch passives / buffs | Table in7.24; Booster x=-2 scaled by -1 | A Skill.wz410/420 values; C family tags from descriptions where WZ omits weapon |
| Branch buff casting | self auto-cast, 0.8s alert2 hold, Haste within existing caps | C existing Booster convention and owner self-only Haste |
| Endure recovery lifecycle | skill clock starts at learning, retains elapsed seconds on rank change, resets per round | C fixed-tick timer lifecycle; A HP/MP/time, owner recovery anywhere |
| Branch learn/rank cards | weight2, exact branch, weapon gated, caps20 (Critical Throw30) | C initial untuned weights/gates; A rank caps |

Thief tracer (#207) additions:

| Constant / choice | Value | Tier / source |
|---|---|---|
| First-job Thief | Lv10; +125 MaxHP / +37 MaxMP | C survivor level; B v83-facts section 4 midpoints, MP truncated |
| Thief growth | 22 HP / 15 MP per level | B v83-facts section 4 midpoints; existing total rounding |
| Thief AP | LUK primary, DEX target max(25, level) | C survivor policy; existing earned-AP redistribution, no new stat reset |
| Thief equipment weights | PAD 10, LUK 6, DEX 3; other weights match Beginner | C initial selection, untuned |
| Thief weapons | chosen 1472061/1332063 worn, opposite in Equip or overflow pickup; stars 2070015 | B Dark Lord gifts (v83-facts section 4); A item IDs/stats; C path/overflow presentation |
| Thief RNG | stream 15, thief_rng, reserved for Steal success | C independent stream; existing streams unchanged |
| Dark Sight values (#211) | 20 ranks; MP 24→5, duration 10→200 s, speed −30→0, any weapon, no failure, darksight action/effect/Use sound | A Skill.wz/400.img/skill/4001003 |
| Dark Sight escape (#211) | casts below 30% HP with a mob within 250 px; ends above 60%; fixed 30 s cooldown from cast; action hold 0.6 s | C owner escape/cooldown rules; reach matches Oak Barrel; action hold ours, untuned |
| Dark Sight cards and appearance (#211) | learn/rank weights 3/2, job 400 only, no carry; Hidden non-morph avatar opacity 0.5 (blink can dim further) | C survivor card/presentation choices; A rank cap 20 |
| Thief attacks | Lucky Seven: 250px, 1s cooldown, 600px/s, radius8, pierce0; Double Stab: weapon reach, one target, 1.2s cooldown; both action0.6s | C initial untuned cast choices; A counts/costs/damage/action art; B LUK formula |
| Thief cards | attack learn/rank 4/3, Nimble Body 2/2, behavior weight2/max3, +1 star/target; attacks carry to 410/420 | C initial untuned choices; A rank cap20 |
| Thief roster | ordinary Lv10–70 Thief-bit gear; shields only for dagger; ordinary/dark ATT scrolls | C curated selection/filter; A IDs and WZ requirements/stats/rates |
| Thief parity (#208) | Each attack: 13 steps / 5 lines, weight 2, all power cards, jobs [400], carry_jobs [410,420]. Lucky Seven: count +1 ×3, pierce +1 ×2, damage ×1.2 ×3, cooldown ×0.88 ×3, range ×1.2 ×2. Double Stab: targets +1 ×3, hits +1 ×2, damage ×1.2 ×3, cooldown ×0.88 ×3, reach ×1.2 ×2 | C owner step budgets; existing untuned card magnitudes and Potential scaling |
| Skill-only melee reach (#208) | `area` scales both feet-relative swing-envelope axes and the bot reach; basic attack unchanged. `attack_count` adds damage lines per target, minimum 1 | C generic survivor card effects; A base attackCount retained |
| Keen Eyes (#209) | 4000001; 8 ranks; +25/+50/+75/+100/+125/+150/+175/+200px | A Skill.wz/400.img range; C claw family tag follows the v83 description |
| Generic range passive (#199, ported unchanged for #209) | `Loadout.RANGE`: additive pixels on ranged basics and weapon-gated ranged attacks; extends only the basic box's far horizontal edge | C shared consumer rule; no change to cached base boxes or unrelated ranges |
| Keen Eyes cards (#209) | learn/rank weights 2/2; power false; exact jobs [400], no carry | C untuned, matching Nimble Body; A rank cap8 |


Bowman (#166), QA #204:

| Constant / choice | Value / rule | Tier | Source |
|---|---|---|---|
| Second-job Bowman fixtures | Hunter Lv30 / Crossbowman Lv31, Henesys seed1 bot, invulnerable, natural EXP, 600 s cap | C | `tools/character_fixture.gd --job=<310|320> --god --seconds=600 --label=spec166/ticket-204`; `_doc` and 4.2 |
| Bowman flow staging (#226 amendment) | `Bowman204`, invulnerable EXP-drop climb through Lv10/30, chosen Bow/Crossbow only via injected input, held family matches the branch for its Bronze notice, diagnostic Free Market boundary | C | `flow_driver --scenario=bowman --branch=310|320`; ammo family swaps remain silent per #155 |
| Weapon-page flow QA (#232) | Shared keyboard job selection, mouse family selection, Enter confirmation and exact equipment-delta check. `full`, `rounds`, `account`, `economy` probe Warrior/Sword; Warrior branches choose Axe/Blunt/Polearm. Rounds/account/economy invulnerable warps apply diagnostic boss hits after the stage timer; economy restores its historical fixture before the economy loop | C | #232 QA staging only; no survival/balance claim |

Bowman (#166), equipment #201:

| Constant / rule | Value | Tier | Source |
|---|---|---|---|
| Drop roster | `equipment_drops/bowman.json`: regular bows 1452000-11, crossbows 1462000-9, and 202 reqJob-4 armour items, Lv10-70; no cash, restricted/event variants or shields | C (curated selection), A (ids, requirements, stats) | Original v83 Character.wz and String.wz; regular progression selected like the Pirate line |
| Scroll roster and shops | Bow ATT 2044500/01/02/04/05; crossbow ATT 2044600/01/02/04/05, ordinary 100/60/10 and dark 70/30; slots `bow`/`crossbow` use the existing weapon price and rate NPCs | C (roster), A (ids, rates, effects) | Original v83 Item.wz/Consume/0204.img; no separate ACC family; strong 100%, event and item-specific variants excluded |

Bowman (#166), Crossbowman #203:

| Constant | Value | Tier | Source / reason |
|---|---|---|---|
| Advancement | Lv30, +325 HP / +175 MP | A level / B grants | canonical job tree; v83 +300..350 HP / +150..200 MP midpoints |
| Advancement weapon | Mountain Crossbow 1462000 | C choice / A stats | owner #166, plain shop crossbow; Lv28, PAD44, STR28 / DEX80; ADR 0005 always grants/wears |
| Skill caps / base counts | 20/30/20/20/30; PKB 2..6, Iron Arrow six contacts / one shot | A | Skill.wz 320; no extra base counts |
| Power Knock-Back formula | (DEX*3.4+STR)*PAD/150, mastery0.1 | B | v83-facts section 5; shared `physical_formula` keys #202 |
| Power Knock-Back behaviour | range_around, 120px push, 1s cooldown, 0.6s swingT1 | C | owner #166 rule / shared Hunter shape #202, untuned; range/prop from WZ |
| Iron Arrow flight / cast | nearest, 300px, 600px/s, radius8px, 1s cooldown, 0.6s weapon hold | C | first-job arrow defaults, own WZ ball/effect/hit; untuned |
| Iron Arrow fall-off | 0.1 per later contact, floor0.1; sixth50% | C | owner #166 default, generic #200; no canonical field |
| Family tags / buff policy | crossbow only; Booster auto-recasts, 0.8s hold | C | String.wz restrictions on Mastery/Final Attack/Booster; WZ weapon46 on attacks (A) |
| Cards | learn/rank4/3 attacks, 2/2 passive/buff; behaviours +1, max3, weight2 | C | exact job320, shared Potential rarities; no tuning |
| Soul Arrow / sound omissions | no3201004 skill/cards; active Hit sound empty | C owner / A absence | endless ammo; Sound.wz contains only Use for3201002/3/5 |

Bowman (#166), generic mechanics (#200):

| Constant / rule | Value | Tier | Source |
|---|---|---|---|
| Skill knock-back distance | Per-skill `knockback.distance` in px; no shipped default in #200 (synthetic test: 120 px); follows the platform and clamps at walls/edges; airborne/flying mobs stay put, statuses stay | C | Survivor rule, owner #166; shared moving-attack slide |
| Hero core melee (#301) | Power Strike 1.0 s, Slash Blast 1.6 s, both weapon action held 0.6 s; Brandish 1.4 s, forward admission at one target; eight survivor ranks; rarity values in 7.33 | C | ours, spec #296 |
| Hero core WZ fields (#301) | 1001004/1001005/1121008 mapped level fields, Brandish box, two hits, 1–3 targets, Use/Hit, body action 7 x 120 ms = 0.84 s | A | original v83 Skill.wz, Character.wz |
| Brandish handedness (#301) | One action per cast: brandish1 + effect/0 for one-handed, brandish2 + effect/1 for two-handed | C (selection), A (aliases/art) | orchestrator ruling; H1 weapon visibility findings |
| Hero finishers (#304) | Panic nearest within 250 px, 2.0 s cooldown; Coma range_around, `min_targets` 3, 1.0 s; both `meter` min 5 / spend all / +10% per orb spent, first swing stance held 0.6 s | C | ours, spec #296 |
| Panic Threaten cut (#304) | Flat `min(level, 20)` weapon attack and defence while threatened; bosses refuse the status | C | ours, spec #296 |
| Hero finisher WZ fields (#304) | 1111003/1111005 mapped level `damage`, `prop`, `time`, Coma `range`/`mobCount`/`hpCon`; finish/1..10, hit/0|1, Use sounds; axe twins 1111004/1111006 identical | A | original v83 Skill.wz |
| Finish art by orbs spent (#304) | `finish/N` for N orbs spent, `hit/1` above 5 orbs, axe twin for an axe | C (layout reading and keying) | H1 notes |
| Pull selection (#300) | Up to `mobCount` candidates, farthest first (horizontal; slot breaks ties), only live grounded non-boss mobs at least 120 px from the caster (block key `min_distance` overrides) and within `range`; bosses and flyers never candidates (7.35) | C | ours, spec #296 |
| Pull gap and slide (#300) | Per-skill `pull.min_gap` px (Monster Magnet ships 60, H7); the mob slides `max(0, dx - gap)` px toward the caster along its foothold chain, stopping at platform edges, walls and map bounds; never crosses the caster | C | ours, spec #296; shared slide |
| Pull chance rolls (#300) | One main-stream draw per taken candidate, none at 100% or without a chance field; a 0% chance still draws; selection before rolls | C | ours (mirrors the knockback roll rule) |
| Shout rank table (#303, spec #296 D4) | `ranks` `[5, 8, 12, 15, 19, 23, 27, 30]`: the standard 30-level table except rank 1 = level 5, because level 4 stores its `prop` under the stray key `58` (7.33) | A (levels, numbers), C (override) | Skill.wz 111.img, String.wz agrees with 58 % |
| Shout and Monster Magnet timing (#303) | Cooldowns 12 s and 10 s, action holds 0.6 s, stances `alert3` / `alert2` (Magnet's node names none; WZ's `prepare` dash hides a two-handed axe), admission at 3 mobs (`cast.min_targets`) | C | ours, spec #296 |
| Shout and Monster Magnet rarity bonuses (#303) | Shout: Area x1.2, Booster cooldown x0.88, Echo Shout cooldown x0.75, Legendary Echo Shout plus area x1.2. Magnet: Reach `range` x1.2, Bigger Grab +2 targets, Booster cooldown x0.75, Legendary Booster plus +2 targets; repeats shrink x0.8 | C | ours, spec #296 (first pass; the balance pass owns final sizes) |
| Knock-back roll | One stream-1 roll per damaging line on a non-boss, even at 0/100%; canonical `chance_field` percent; canonical/scheduled bosses do not roll or move | A (canonical chance), C (stream, per-line rule, boss policy) | Skill.wz; #166 binding decisions |
| Pierce fall-off schedule | Linear `max(floor, 1 - fraction * (n - 1))`; `balance.json/combat.pierce_floor` defaults to 0.1; 0.1 per mob means the sixth takes 50%; includes crit, rounded once | C | #166 binding decisions; WZ has no fall-off value; survivor data owns the floor |
| Impact blast policy | First mob consumes shot; primary counts toward cap; box translated to primary feet, selected before hits; nearest body then slot; one `hit` animation at impact by default (`visual: "effect"` supported) | A (canonical box/cap/damage field), C (consumption, anchor/order/art choice) | Skill.wz; #200 |
| Ranged Final Attack visual | Current ammo's art/speed/rotation, straight hand-to-target flight; no delayed damage, no RNG; ranged Spread uses at least the family's existing ranged reach | A (ammo art), C (presentation, Spread) | Current ammo data; #200 |

Bowman (#166), Hunter #202:

| Constant | Value | Tier | Source |
|---|---|---|---|
| Hunter advancement | canonical Lv 30; HP+325, MP+175 | A level, B grants | v83-facts 4 second-job midpoints |
| Hunter weapon | Ryden 1452005, always worn; old weapon stored/overflow dropped | C selection, A stats | owner #166, Character.wz PAD 45/STR 35 / DEX 95 |
| Hunter skill ranks and numbers | 20/30/20/20/30; mastery, ACC, costs, speed, durations, damage, chance, range, box/count | A | Skill.wz 310, tested at endpoints against private cache |
| PKB formula | DEX3.4+STR; divisor 150; fixed mastery 0.1 (minimum has ordinary0.9 factor) | B | #202 pre-BB formula; optional divisor/mastery data keys retain default 100/live mastery |
| PKB auto-cast / push | range_around, 1s cooldown, 0.6s swingT1, distance120px; stream1; bosses resist | C | untuned defaults; action selected from canonical afterimage, art itself A (1x1 frame) |
| Arrow Bomb flight / stun | nearest, 1s cooldown/300px/600px per second/radius 8/no pierce/0.6s weapon action; impact_blast x/hit, on_hit prop/time | C scheduling/shape, A fields/art/sounds | first-job flight defaults; generic #200 blast and #187 stun |
| Hunter passive/Booster presentation | bow-only tags, Final Attack 0.6 s weapon stance/current ammo, Booster auto-cast/recast 0.8 s alert2, scale -1 | C scheduling/tags, A Booster action/art | shared 7.6/7.7 consumers; never lethal HP cost |
| Hunter cards | attacks power4/3, others2/2; +1 count/blast_targets max 3 weight 2 power; exact job 310 | C | untuned, shared rarity magnitudes; first-job carry preserved per binding notes |
| Hunter Soul Arrow | 3101004 absent | C | owner #166: endless ammo makes it redundant |

Bowman (#166), first job #199:

| Constant / rule | Value | Tier | Source |
|---|---|---|---|
| Advancement / gifts | Lv 10; wear 1452051, spare 1462001; HP +125 / MP +37 | C level/spare, B bow and pool midpoints, A item stats | owner #166, v83-facts 4 |
| Level growth | 22 HP / 15 MP | B | v83-facts 4 midpoints |
| Automatic AP | DEX primary; STR level + 5 through Lv 30, 35 through Lv 34, 40 at Lv 35, then level + 5 through Lv 70 / 75 STR (held thereafter); `balance.player.ap_secondary.300`, inherited by 310/320 | C | equipment requirement policy; all 22 shipped bows/crossbows checked against canonical reqSTR/reqDEX; early allocation/QA fixtures retained |
| Equipment weights | PAD 10, DEX 6, STR 3; PDD 1.5, MDD 1, ACC/EVA .3, HP/MP .03, speed .5, jump .3 | C | existing physical baseline with Bowman primary; untuned |
| Skill levels and effects | 16/20/8/20/20/20; canonical costs, damage, prop, range, time, ACC/eva | A | Skill.wz/300.img, string Focus acc cast by SkillBook |
| Eye range interpretation | Add canonical +15..120 px to ranged basic targeting/travel and family-gated attack-skill range; melee and Magician unchanged | C | owner #166 and binding NOTES |
| Weapon gates | Critical Shot, Eye and attacks bow/crossbow; Blessing/Focus any | C tags, A no canonical restriction on Blessing/Focus | #199 skill table and String.wz descriptions |
| Arrow targeting / movement | nearest; base range 300 px, speed 600 px/s, radius 8 px, cooldown 1 s, hold .6 s, pierce 0 | C | survivor placeholders; split Double Shot targets as Pirate, current ammo sprite |
| Focus casting | automatic, recast on expiry, .8 s hold | C | existing buff rule |
| Double Shot sound | reuse Arrow Blow Use; no Hit sound | C reuse, A node absence | Sound.wz/Skill.img lacks 3001005; 3001004 has only Use |
| Cards | learn/rank attack weights 4/3, other 2/2; behaviour +1 shot, cap 3, weight 2; shared rarity gains | C | survivor placeholders, no tuning |
| RNG | 14 reserved, unregistered; job choices on 8 | C | owner #166; no new random roll |
| Soul Arrow omission | never add 3101004/3201004 | C | owner #166, endless ammo |

Pirate tracer (#186) additions:

| Constant / rule | Value | Tier / source |
|---|---|---|
| First-job level / grants | Lv10; +125 HP, +37 MP | C level override; B v83-facts §4 reward midpoints (MP truncated) |
| Pirate growth | 25 HP / 20.5 MP per level | B v83-facts §4 midpoints; existing accumulated-total rounding |
| Per-path AP | knuckle STR + DEX target level; gun DEX + STR target level | C owner choice; `ap_stat` / `ap_secondary` keys `500:knuckle`, `500:gun`; nearer branch wins |
| Pirate weapon gifts (#226 amendment) | only chosen 1482000/1492000 worn; displaced equipment to Equip or feet | B v83-facts section 4 Kyrin item choices; C chosen-only rule |
| First-job skill values | 20 levels, original costs / damage / counts / boxes / range / ACC / avoid | A Skill.wz 500.img; canonical `bulletCount`/`range` fallback |
| Flash Fist / kick weapon overrides | knuckle / any | C owner choice |
| Kick surrounding box | ±canonical far edge, original vertical bounds | C `cast.around`, owner surrounding-kick behavior |
| Attack timing | fist 0.9 s, kick 1.6 s, shot 1 s cooldown; each 0.6 s action hold | C initial untuned survivor values |
| Double Shot flight | 600 px/s, radius 8 px, base pierce 0 | C initial untuned survivor values |
| Pirate cards | attack learn/rank weight 4/3; Bullet Time 2/2; behavior weight 2, +1 target/pierce, max 3 steps | C initial untuned choices; A rank cap 20 |
| Pirate drop / scroll rosters | regular Lv10–70 knuckles/guns; ordinary and dark scrolls | C curated selection; A item ids, requirements, rates and stats |
| Pirate RNG | stream 16, `pirate_rng`; 13 Threaten (unused without prop), 14 reserved, 15 Thief | C independent owner; drawn by Oak Barrel's failure roll (#194, `buff.fail_field`); a future non-Pirate failure chance needs its own stream |
| Brawler / Gunslinger advancement (#189) | the canonical Lv 30; +325 Max HP and +175 Max MP (`jobs.json` `grants`); Pirate growth unchanged | B v83-facts §4 midpoints (+300-350, +150-200); C level (canonical stays) |
| Backspin Blow (#191, 7.19) | Skill.wz damage 88-240%, mpCon 12-30, mobCount 3, stun time 1 s, box 140 px / 50 px high; no `prop` so every landed hit stuns; knuckle only; `cast.around` (both sides), cooldown 1.5 s, action hold 0.8 s; slides 100 px away from the nearest struck mob after the hits | A tables / C weapon, around, cooldown, hold, distance | Skill.wz 510.img 5101002; owner (#168): moves away from the faced mob and stops at edges and walls |
| Double Uppercut (#191, 7.19) | Skill.wz damage 100-290%, attackCount 2, mpCon 15-30, stun time 1 s, no prop (every landed line stuns, longer time kept); knuckle only; `weapon_reach` rule (one mob in the knuckle's envelope), cooldown 1.2 s, action hold 1.0 s | A tables / C weapon, rule, cooldown, hold | Skill.wz 510.img 5101003 (no box or mobCount: Power Strike's rule, 7.8) |
| Corkscrew Blow (#191, 7.19) | Skill.wz damage 135-420%, mpCon 20-36, mobCount 3, reach 100-200 px = charge distance (`distances` copy of -lt.x); full charge at once, no wind-up; knuckle only; cooldown 2.0 s, action hold 0.8 s; the swept hit box ends at the wall that stops the charge (nothing past it is struck) | A tables, reach / C weapon, no wind-up, cooldown, hold | Skill.wz 510.img 5101004; owner (#168): charges its full distance toward the faced mob |
| Brawler attack cards (#191) | learn 4, rank 3 (20 ranks), +1 target weight 2 (max 3 steps); power cards, exact branch 510 | C | same shape as the Flash Fist cards (7.14) |
| Pirate advancement weapons | Brawler Prime Hands 1482004 (PAD 34), Gunslinger Cold Mind 1492004 (PAD 31), one `paths` entry each; always worn | C owner choice (ADR 0005 as amended); A item stats |
| Branch AP rows | plain `510` / `520` rows in `ap_stat` / `ap_secondary` copy `500:knuckle` / `500:gun` (secondary target = level) | C owner choice; the branch row wins over the recorded path |
| Second-job passives and boosters | Improve MaxHP x +3..+30 per level-up; Masteries N and x ACC; Boosters x -2 (`scale` -1), time, hpCon and mpCon, all per level | A Skill.wz 510/520; B mastery encoding and Max HP per level-up (7.6); C weapon-family tags |
| Gun Mastery recharge | `y` unused, text omits it | C: ammo is endless |
| Second-job cards | learn/rank weights 2/2, not power, exact branch job; first-job cards `requires.jobs` [500] + `carry_jobs` [510, 520] | C initial untuned choices |
| Path bot equipment (#226 amendment) | auto-equip upgrades only the recorded weapon family (shared drop families allowed), including after swaps or destruction; a candidate must still improve the worn score | C owner rule: bot loyalty follows the recorded path; no RNG |
| Gunslinger attack numbers (#192, 7.20) | costs, damage %, mob counts, boxes, stun prop/time, recoil range per level 1-20 | A Skill.wz 520.img (WZ over String text) |
| Gunslinger attack weapons | Invisible Shot, Blank Shot, Recoil Shot: gun; Grenade: any | A WZ weapon 49 for the three; C Grenade (owner) |
| Invisible Shot both sides | `cast.around` mirrors the box's far edge (250 px) across the player; no bullet drawn | C owner behaviour |
| Gunslinger timing | cooldowns Invisible 1 s, Blank 1.4 s, Grenade 2 s, Recoil 1.8 s; each 0.6 s action hold; Invisible Shot plays the WZ Hit sound as its cast sound | C initial untuned survivor values |
| Grenade throw (`cluster`) | thrown with no wind-up; range 400 px; ball 600 px/s, flight at least 0.1 s; blast on arrival at the target's feet; target = the first of the 12 nearest mobs in range (bosses first) with the largest blast, a scheduled boss outright | C owner (no wind-up, nearest cluster) + ours (range, speed, candidates) |
| Minimum grenade flight | `SkillRunner.MIN_FLIGHT` 0.1 s: the shortest time a thrown grenade is in the air, so a point-blank throw still shows the ball before the blast | C ours (#192) |
| Stun tint | `MobRenderer.STUN_TINT` (1.0, 0.95, 0.55), a pale yellow modulate on a stunned mob when the cached stun stars (`Skill.wz/111.img/skill/1111008/mob`) are absent; presentation only | C ours (#187) |
| Grenade arc | presentation only: 40 px mid-flight arc, ball art loops | C ours |
| Recoil Shot shot | current ammo bullet sprite, 1000 px/s, radius 6, rotating, reach 300 px, no base pierce | C ours; A ammo ids (6.1.2) |
| Recoil Shot hop | the canonical `range` 115 to 250 px away from the faced mob after the shot; edge/wall stops and no air hop per 7.13 | A distance; C owner rule |
| Gunslinger attack cards | learn weight 4, rank weight 3 (max 20), hit-more weight 2 (+1 target or pierce, 3 steps); power cards, job 520 exactly | C initial untuned choices |

| Physical combat rule (#153) | Value / behavior | Tier | Source |
|---|---|---|---|
| Weapon formulas | `WeaponInfo.PHYSICAL`, Thief dagger row; multipliers and stats in 6.1.1 | B | SouthPerry/HS.net pre-Big-Bang compilation; Cosmic WeaponType corroborates max bounds; refs `class-specs/v83-facts.md` §5 |
| Wand/staff and bare formula | Retain 4.4 swing / 3.2 stab, STR/DEX, equipment-only PAD for bare hands | C | Existing game behavior; no verified wand/staff physical row in §5 |
| Physical mastery | Default 0.10; canonical N → (10+5N)% | B | SouthPerry compilation, WZ mastery/String corroboration |
| Physical defence | max−0.5PDD/min−0.6PDD, each at least 1; no level-gap factor (ADR 0006, #285: the monster's level never changes damage or hit chance) | B | AGF/Stereo formula, refs §5; the level gap removed by the owner, ADR 0006 |
| Skill text MP cost (#285) | `SkillText.strip_mp_cost` drops the v83 MP-cost wordings (`MP -10, `, `HP -12, MP -8;` keeps the HP part, `Use 20 MP, `, `Consumes 10 MP, `, ...) from WZ level lines; a rarer wording stays as written | C | ours (`SkillText.MP_COST_PATTERNS`, measured on the v83 `String.wz/Skill.img` h lines); no MP, ADR 0006 |
| Lucky Seven override | LUK×5 max / LUK×2.5 min, no secondary/mastery | B | SouthPerry compilation; WZ String says independent of Claw Mastery |
| Job base accuracy | `CombatMath.ACCURACY_FACTORS`: DEX/LUK .8/.5, .6/.3, Brawler .9/.3, nearest ancestor | B | SouthPerry/HS.net, refs §5 |
| Accuracy → crit | Base 0, +0.0005 per ACC, default ×1.5; all jobs and damage types including basic | C | Owner spec #151 / ADR 0005; small placeholder, no tuning |
| Passive crit damage | Add `crit_damage_bonus` skill-% points when positive, otherwise ×`crit_mult` | B | SouthPerry Critical Shot/Throw additive rule |

| Weapon family rule (#154, #156, #158) | Value / behavior | Tier | Source |
|---|---|---|---|
| Family display names | `WeaponInfo.FAMILY_LABELS`: Sword, Axe, Blunt weapon, Dagger, Wand, Staff, Spear, Pole Arm, Bow, Crossbow, Claw, Knuckle, Gun; "Bare hands" for none. The Skill window and its tooltip name the weapon a skill needs with them | C | ours; the wording follows the v83 item names |
| Two-handed weapons | `WeaponInfo.FIRST_TWO_HANDED_TYPE` 140: every weapon type from 140 (two-handed swords, axes, blunt weapons, spears, polearms, bows, crossbows, claws, knuckles, guns) blocks the shield slot | B | Cosmic `isTwoHanded` (server reimplementation; facts only) |
| Basic-attack stance table | `WeaponInfo.ACTIONS_ONE_HANDED`, `ACTIONS_TWO_HANDED` and `BASIC_ACTIONS` (the table under "Weapons on the avatar"): every listed stance exists in the type's representative weapon item, the body and (melee) the afterimage; which of them a family uses for the automatic attack, and their order (the basic-attack stream indexes it), is our choice | A (the stances exist), C (the selection and order), B (the five one-handed stances) | `Character.wz/Weapon` and `Afterimage`; ours; pre-Big-Bang client descriptions |

| Free Market rule | Value / behavior | Tier | Source |
|---|---|---|---|
| Hub tick and catch-up | 1/60 s, at most 4 ticks/frame, matching RunScene | C | Existing engine scheduling rule |
| Hub arrival | PortalSet.start_point with RNG seed 0; position is not saved | C | Ours; stable boundary arrival |
| Hub exit / rooms / NPCs | out00 type 7 opens map select on Up using existing portal reach/cooldown; room portals inert; all four NPCs drawn, including hidden Maple TV | C (policy), A (IDs/positions/type) | Owner #32/#71; original v83 map/life nodes |
| Hub identity / pause | Existing status bar only (full pools, EXP, level/job/name), instruction inset (12,12); existing pause with Resume / Save & quit and no loss warning | C | Ours / owner #32 boundary flow |

Character creation (#70) reads the Explorer male/female options and their hair/colour/skin names from
`Etc.wz/MakeCharInfo.img` at runtime. Its eight numeric columns, gender-specific option lists and hair-colour suffix
are tier A, checked in the original v83 files. Sword 1302000 has WATK 17 / speed 4; Wooden Club 1322005 WATK 19 /
speed 5; Hand Axe 1312004 WATK 17 / speed 5 (tier A). Existing canonical interval conversion yields 0.72 / 0.75 /
0.75 seconds. No new balance values are introduced. Clothing choices change the drawing; the existing survivor
starter-equipment stat rule is unchanged. The selected weapon's actual WATK, speed, type, sound and afterimage feed
the basic attack until advancement replaces it with the job weapon (tier C: owner #32 rule).

Spec #33 (#105) replaces that rule: the creation outfit and weapon are worn equipment instances in
CharacterSnapshot format 2, and Magician advancement grants the Wooden Wand (the previous weapon goes to the
inventory). `DataRepo.character_look(character, data)` supplies AvatarRenderer with the carried look, its default
when empty, and the worn equipment. Slots, rounds and #71's Free Market use this shared presentation helper.
Only `CharacterSnapshot.look` is authoritative. New run wrappers omit their duplicate `look`; old format-2 wrappers
with that field still load and the duplicate is ignored (lead #70/#71 decision, superseding the earlier wrapper
shape). Format-1 characters keep loading: their look equips plus the frozen #32 weapon rule (`beginner_weapon` for a
Beginner, otherwise 1302000 / 1372005 by job line) become worn instances when they migrate.

| Equipment rule (spec #33) | Value / behavior | Tier | Source |
|---|---|---|---|
| Equip slots | Item category: Cap 100 hat, Coat 104 top, Longcoat 105 overall, Pants 106 bottom, Shoes 107, Glove 108, Shield 109, Weapon 130-169; an overall fills top and bottom (`Equipment.CATEGORY_SLOTS`) | A | v83 Character.wz folders |
| Shield and two-handed weapons | Weapon types from 140 block the shield slot; wearing either moves the other to the Equip tab (`Equipment.displaced_slots`, `WeaponInfo.FIRST_TWO_HANDED_TYPE`) | B | Cosmic `isTwoHanded` |
| Shield swap refusal message | "You can't get anymore items." when the Equip tab cannot hold what moves (`InventoryWindow.MESSAGES.equip_full`) | B | Cosmic `InventoryManipulator.equip` (overall, shield and two-handed cases) sends the inventory-full status 0xff, the pickup notice's string; it also applies to an overall over a top and bottom |
| Equip window SHIELD cell | (137, 134) on the 175x304 `backgrnd`, right of WEAPON (`EquipWindow.SLOT_POS`); tooltip category art `ToolTip/Equip/ItemCategory/10` (SHIELD) | C / A | measured on the v83 art / v83 UI.wz |
| Fresh instance | Every non-zero `info/inc*` value; upgrade slots `info/tuc` | A | v83 Character.wz |
| `reqJob` bits | 0 all jobs, 1 Warrior, 2 Magician, 4 Bowman, 8 Thief, 16 Pirate (`Equipment.JOB_BITS`) | A | v83 Character.wz |
| Speed / jump caps | 140 / 123 (`Equipment.SPEED_CAP`, `JUMP_CAP`), after equipment, cards and buffs; the area slow applies after the cap | B | v83 client/server movement limits (emulator RE) |
| Default outfit | 1040002, 1060002, 1072001, 1302000: the first MakeCharInfo CharMale options (`Equipment.DEFAULT_OUTFIT`) | A | v83 Etc.wz/MakeCharInfo.img |
| Equip tab | 24 slots (`balance.player.inventory_slots`) | A | v83 new character |
| Magician weapon grant | Advancing to 200 wears the Wooden Wand 1372005; the previous weapon moves to the inventory; when the inventory is full it is dropped at the player's feet as a normal pickup (#157; it was a skipped grant with a `grant_blocked` notice before) and nothing is ever destroyed (`balance.player.weapon_grants`; review fix of #33) | C | Owner #33 triage; #157 |
| Weapon path grants (#226 amendment) | Only the chosen family item is worn without requirements; paths exist at multi-family first and second jobs. >=2 paths records `weapon_path`, 0/1 preserves it | B (instructor item choices), C (selection, data shape, defaults) | Owner spec #226; jobs.json |
| Branch weapon grant (#226 amendment) | One chosen item, from `paths`; tier-2 page order puts held family first. Single-family grants stay worn; displaced equipment goes to Equip or feet | C | Owner spec #226; ADR 0005 |
| Warrior advancement weapons | Fighter 110: Gladius 1302008 (sword), Fireman's Axe 1312005 (axe); Page 120: Gladius, War Hammer 1322014 (blunt); Spearman 130: Forked Spear 1432002 (spear), Mithril Pole Arm 1442001 (polearm); plain Lv 30 weapons, stat needs STR 95-100 (#180) | C | Ours |
| Warrior second-job advancement | Fighter, Page and Spearman at the canonical Lv 30, +325 Max HP (`jobs.json` `grants.max_hp`), growth 26 HP / 5 MP per level unchanged (#180) | B (HP midpoint of +300-350), A (Lv 30) | Cosmic changeJob, v83-facts 4 |
| Power Strike / Slash Blast after second job | Their ten cards list `requires.carry_jobs` [110, 120, 130]: eligible, still `power`, never in the advancement draw; Iron Body and the HP passives stop at Lv 30 (#180) | C | Owner decision, spec #165 |
| Equipment max HP | Flat, added after card modifiers (an active Hyper Body then scales the whole total, 7.12); `incMMP` does nothing (no MP, #285) | C | Ours |
| Bare hands | Punch with the five one-handed actions, attack speed 6, reach box (-55,-55) 50x50, impact on the action's last frame, no afterimage; W.ATT from other worn items only (minimum damage 1) (`BasicAttack.BARE_HANDS`) | C (A: `Sound.wz/Weapon.img/barehands`) | Ours |
| Format-1 weapon rule | Migration only: Beginner `beginner_weapon`, else the job line's `format1_weapon` from `data/survivor/jobs.json` (1302000 for the Beginner, 1372005 for the Magician line; nearest ancestor via `JobTree.lineage_value`) | C | Frozen spec #32 rule |
| Regen passive field | A skill with `"regen": {"pool": "hp", "field": "hp"}` adds that canonical level number to each HP regeneration pulse (`Loadout.regen_bonus`; Improved HP Recovery); the MP `divisor` form went with Improved MP Recovery (#285) | A (values); C (field shape) | Skill.wz; ours |
| Job `grants.max_hp` | Advancing adds it to base Max HP (`_base_hp`, saved as the snapshot's `base_hp`, so no format change) alongside `grants.max_mp` (`_job_mp`); data rows only for playable jobs | C | Ours; Warrior rows come with #163 |
| Rage (#182) | W.Att +`pad` 3-12, weapon defence +`pdd` -3 to -12 (negative in the WZ, no `scale`), 46-160 s, `mpCon` 12/20; self only; auto-cast, recast on expiry, any weapon | A (values); C (self only, auto-cast) | Skill.wz/110.img/skill/1101006 |
| Power Guard values (#182) | reflect `x` 11-40 %, `time` 3-90 s, `mpCon` 15/30; the Page node is the same table | A | Skill.wz/110.img 1101007, 120.img 1201007 |
| Power Guard rule (#182) | contact damage only, half the rate against a boss, capped at 10 % of the monster's Max HP, the same amount subtracted from the damage taken | B | third-party v83 server reimplementation; the cap is only in the String desc (no WZ field) |
| Power Guard details (#182) | amounts floored (a cap that floors to 0 reflects nothing and does not reduce the hit); applied after Invincible; boss = canonical boss kind or scheduled slot; the reflect is the character's own damage (damage number, a kill gives EXP and drops, `damage_dealt`), never a crit, no Final Attack or on-hit status; ignores physical immunity; one reflect per hit window; no RNG | C | ours |
| Rage / Power Guard cards and bot (#182) | `rage_*`, `power_guard_fighter_*`, `power_guard_page_*` learn/rank cards, not power, weights 3/2; `bot.card_scores` `rage_new` 100, `rage_rank` 74 (attack-like), Power Guard unscored (defensive-buff default) | C | ours, untuned |

| Meso rule (spec #33, #107) | Value / behavior | Tier | Source |
|---|---|---|---|
| Coin sprites | Amount < 50 bronze 09000000, 50-99 gold 09000001, 100-999 bundle 09000002, 1000+ bag 09000003 (`MesoDrops.BRACKETS`) | B | Two third-party client reimplementations |
| Coin art and frames | `Item.wz/Special/0900.img/<id>/iconRaw/0..3` (no `info` node, no `delay`); item type 9 = `Special` in the importer and `AssetLibrary` | A | v83 Item.wz |
| Frame time | 100 ms per coin frame | C | Ours (WZ has no delay) |
| Per-mob amount | `mobs.json` `mesos` [min, max): uniform integer in [min, max); every mob of the three rosters and their bosses except the four 9300xxx event mobs (King Slime 9300003, 9300062-9300064) | B | v83 server drop data (Cosmic `drop_data` rows with itemid 0), used as facts |
| Fallback amount | Mobs with no v83 range roll around 4 + 1.5 x level, x0.8 to x1.2 (`balance.mesos.fallback`) | C | Ours, fitted to the early-roster ranges |
| Drop chance | `balance.mesos.chance` 0.4 per kill (elites too) | B | v83 server reference: 40% at rate 1 |
| Multiplier | `balance.mesos.mult`, one number scaling every amount, set once from an estimate (see 4.2 #107; 14) | C | Owner: about 300-350k mesos per sensible-bot Henesys clear; NX upgrades (#34) may raise it |
| Boss drops | `balance.mesos.boss_drops` (4) bundles per scheduled boss death, each rolled from its range, no chance roll | C | Ours |
| Lifetime | Mesos never expire during a round, never merge, never count toward the EXP-drop cap; magnet and collect radius like EXP drops | C | Owner #33 |
| Pickup sound | `Sound.wz/Game.img/PickUpItem` (v83 Game.img has no separate meso sound; DropItem plays on the drop) | A | v83 Sound.wz |
| Pickup notice | "You have gained mesos (+N)" in the system-message queue, one sum per frame | B | v83 client string pool 0x12F (open client reimplementations) |
| Carry | `CharacterSnapshot.mesos` carries across rounds and is lost with the run; the HUD shows no meso total | C | Owner #33 |

| Equipment drop rule (spec #33, #109) | Value / behavior | Tier | Source |
|---|---|---|---|
| Eligible list | `survivor/equipment_drops/<line>.json` `items`, ids only (reqLevel, reqJob, stats stay in the Character.wz info of the asset cache): v83 caps, coats, longcoats, pants, shoes, gloves, wands (137xxxx) and staves (138xxxx), not cash, reqLevel 0-70, reqJob 0 or a Magician bit, that a regular v83 server gave out: dropped by an ordinary mob (id 100000-7999999) or sold by a regular NPC shop (shop id below 9000000, not 1337). That keeps quest, event, GM and boss-only items out | B | Cosmic `drop_data` and `shopitems` rows used as facts; reqLevel/reqJob/cash read from v83 Character.wz (A) |
| Warrior list (#159) | `equipment_drops/warrior.json`: the same selection for the sword (130xxxx, 140xxxx), axe (131, 141), blunt (132, 142), spear (143) and polearm (144) weapons and the shields (109xxxx) whose reqJob has the Warrior bit (88 weapons, 17 shields; some weapons are shared with Thieves and Bowmen). reqJob 0 weapons and shields are left out on purpose: a Beginner and a Magician would otherwise draw them, and their drops stay as they were | B (selection rule), C (the reqJob 0 exclusion) | Cosmic `drop_data` / `shopitems`; v83 Character.wz |
| Weapon family rule (#159, #292) | A weapon is eligible only when its family (`WeaponInfo.family`) is one of the job's `weapon_families` (`JobTree.weapon_families`, `survivor/jobs/<line>.json`; 212: `["wand", "staff"]`, tier C), read per drop for ordinary and boss drops alike and independent of the weapon worn; one- and two-handed swords, axes and blunt weapons share a family; a job with no list gets no weapon; armour and shields do not depend on it (`EquipmentDrops.family_allows`). #292 replaces the held-family rule of #159 and its `shared_families` / `shield_families` data | C (ours; the ticket's rule) | Ticket #292 |
| Job filter | Only items whose `reqJob` is 0 or has the bit of the character's job branch (`Equipment.job_allows`); a job-0 test character only gets all-job items, every Magician job gets Magician and all-job items. It is also the only wear requirement (#292) | A | v83 `reqJob` bits (owner #33: current job only) |
| Drop band (#292) | `stages.json` `drop_bands[tier]` = [min, max] `reqLevel` (tier 1 [0, 30], tier 2 [30, 60], inclusive); an item drops only when its `reqLevel` is inside the band of the current stage's tier (`NxAward.tier_of`; a stage outside the tiers counts as tier 1). The character's level is not read (a round starts at Lv1). Replaces the [level - 10, level + 5] window | C | Owner 2026-10-27 (ADR 0006, #292) |
| Weighting | Uniform among the eligible items of the band (the 1 / (1 + 0.25 x distance) falloff of #109 is gone with the level) | C | Ours (#292) |
| Drop chance | 0.002 per ordinary kill (`equipment_drops.chance`), unchanged by #237's two-item boss rewards; originally sized from an estimate of about 3,300 kills in a full Henesys round. v83 mobs gave equipment on about 0.7-2% of kills | C | Ours (ticket #109) |
| Boss drop | Each scheduled boss death drops exactly 2 items (`equipment_drops.boss_drops`), no chance roll, uniform among the eligible items with `reqLevel` in the top third of the band (`EquipmentDrops.boss_floor`: `max - (max - min) / boss_top_parts`, 3, so tier 1 Lv 20-30, tier 2 Lv 50-60); the highest `reqLevel` in the band when none is that high, the job-eligible item nearest the band when it is empty | C | Owner 2026-10-21, spec #237 (count); owner #292 (top third); ours #109 (fallbacks) |
| Random stats | Every non-zero `inc*` stat of a drop varies by a whole number up to 10% of its base (rounded up) either side, capped at 5 for STR DEX INT LUK PAD MAD ACC EVA Speed Jump and at 10 for PDD MDD MHP MMP, uniform, never below 0; upgrade slots (`tuc`) never vary; other `inc*` keys keep their base (`Equipment.create_drop`) | B | The v83 server rule as the ticket #109 states it (implemented from that prose) |
| RNG | Chance, item pick, stat rolls and boss scatter use RNG stream 10 (`equip_rng`), so no other stream moves; the pop of the drop uses stream 4 like every drop | C | Ours |
| Lifetime and pickup | Equipment never expires, merges or counts toward the EXP-drop cap; magnet and collect radius like EXP drops; with a full Equip tab (`balance.player.inventory_slots`) it is not magnetised, stays on the ground, and is picked up once there is room | C | Owner #33 |
| Notices | "You have gained an item (Name)" on pickup (name from String.wz/Eqp.img) and "You can't get anymore items." when a full tab refuses a drop, in the system-message queue | B | v83 client string pool (open client reimplementations) |
| Auto-equip rule (#222; `Equipment.auto_wear_error`, `RunWorld._step_pickups`) | A collected equipment drop is worn at once when wearing it displaces nothing (its slot is empty; no overall beside a top or bottom, no top or bottom beside an overall, no shield beside a two-handed weapon) and the character passes `Equipment.requirement_error` (the item's job class only since #292; level and stat requirements are ignored), through the same `Equipment.equip` as the Item window. The world emits `equipment_changed` "pickup" and then "auto_equip" (slot, item), the stats refresh and the HUD shows "Equipped <name>". Otherwise it stays in the Equip tab. A weapon qualifies only for an empty weapon slot (never past Lv10); cash equipment is out of scope. Runs in the sim, so bots and headless runs get it; `BotShop.auto_equip` keeps its upgrade logic for occupied slots. No RNG | C | Owner brief (playtest 3 grilling, 2026-10-18); the "Equipped <name>" wording is ours |

| Bot shopping rule (spec #33, #112; `BotShop`, bots only, never the player) | Value / behavior | Tier | Source |
|---|---|---|---|
| Equipment value | An instance scores the sum of weight x value over its `inc*` stats (`balance.bot.equipment_weights`, keyed by job id, `"0"` Beginner and `"200"` Magician; a job uses its nearest ancestor's entry through `JobTree.lineage`). Magician: M.ATT 10, INT 6, M.DEF 2, W.DEF 1.5, LUK 1, Speed 0.5, then ACC/EVA/Jump/pools; Beginner: W.ATT 10, STR 6, DEX 3, W.DEF 1.5. Scrolls already read are part of the stats | C | Owner brief (#112: Magicians want M.ATT, INT, then defences); the numbers are ours |
| Equip rule | At each equipment pickup, level-up and job change a bot wears, repeatedly, the highest-gain inventory item that scores above what it replaces (an overall against the top and bottom it displaces; an empty slot against 0) and that the item's job class and the Equip tab's room allow. Not a decision point, no RNG | C | Owner brief (#112); the job-change trigger is ours (a new job unlocks items) |
| Pickups it cannot take | Bots ignore equipment drops while the Equip tab is full (no walking to them, no camping on them); EXP and meso drops are unchanged | C | Follow-up of #109 (lead) |
| Sensible plan | At a Free Market visit: sell the spare equipment it will not wear (everything except a better item its job class admits); then for each worn item with upgrade slots in the order weapon, overall, gloves, hat, top, bottom, shoes, read the 100% or 60% scroll of its item type with the best expected score (success chance x stat score; the 60% INT/M.ATT scrolls beat the 100% ones at equal price), using held scrolls first and buying one per upgrade slot while mesos (plus the sales) last. Never dark scrolls | C | Owner brief (#112 baseline); expected-value choice between 100% and 60% is ours |
| Careless plan | Sells nothing; while a worn item has an upgrade slot and an affordable scroll of its type exists (any rate, dark ones included) it picks a random (item, scroll) pair, buys and reads it. Its stream: `hash("careless-shop-<run seed>-<tier index>")` | C | Owner brief (#112) |
| Plan application | Only through `RunWorld.sell_item`, `buy_scroll`, `use_scroll`; a dark scroll that destroys an item ends the pass and the plan is redone from the live state (at most 8 passes). Scroll rolls use the next round's `scroll_rng` (stream 11) | C | Ours |
| Where it runs | `scripts/balance.sh --tier=N` chains between tiers (the next round's world is built from the boundary snapshot and visits before it plays), mid-round equipping in every balance run and in RunScene's autoplay, and `FreeMarket.bot_shop` for a hub driver. With `--autoplay` on a menu-started character (`SceneFlow.autoplay`, set from the flag in `main.gd`) the Free Market runs the sensible visit once on entry (`FreeMarket.shop_visit`) and resumed rounds autoplay; `playtest.sh --run` is a tool one-off with no Free Market | C | Ours |

| Review-fix rule (spec #33) | Value / behavior | Tier | Source |
|---|---|---|---|
| Discard / sell confirmation | The non-modal YesNo box remembers the exact instance it asked about and acts only when the same Equip-tab index still holds an equal instance (id, stats, slots, scrolls); a swapped-in copy of the same id is neither destroyed nor sold | C | Review of #108 / #111 |
| Weapon grant with a full tab | If the previous weapon has no room in the Equip tab it is dropped at the player's feet as a normal equipment pickup (`pickup_blocked` shows "You can't get anymore items." until a slot frees); the grant itself always happens and nothing is ever destroyed (#157; before it the Magician wand grant was skipped) | C | Lead decision, review; #157 |
| Numeric-string scroll info | `DataRepo.scroll_info` casts numeric strings (hat Accuracy 10% 2040016 stores `success` as `"10"`) | A (WZ data), C (cast) | v83 Item.wz/Consume/0204.img |
| Hub scroll seed | The Free Market's scroll rolls are seeded by `FreeMarket.scroll_seed(snapshot)`: the saved run seed `round_seed` x 1000003 plus a hash of the character's equipment, scrolls and mesos, re-applied after every change; the same save always rolls the same, every scroll changes the next seed, quitting cannot reroll. `bot_shop(policy, seed)` rolls its scrolls from its own stream `hash("scrolls-shop-hub-<seed>")` | C | Lead decision, review |
| Autoplay in the hub | With the `autoplay` option the Free Market runs `bot_shop("bot", round_seed)` once on entry | C | Ticket #112 text |
| Player accuracy | The job base (above) plus worn `incACC`, active buff `acc` and passive ACC is stored in `player_state.acc`, shown in the Stat window, and feeds the crit chance (row "Accuracy → crit"). The player's attacks never roll a hit chance (no v83 player-hit roll is modelled), so accuracy has no other combat effect | C | Lead decision, review of #105; owner spec #151 |

The 4-12 ASCII letters/digits and living-name uniqueness rule is tier C, owner #32; matching is case-insensitive.
Character select (#70 rework) keeps the v83 MapLogin character-select area and signboard. It has three
clickable slots, one selected-character details scroll, and the signboard's single Start/Create/Delete set.
`CharSelect/character/0` supplies the ground animation and `character/1` the empty silhouette; nameTag/0 and /1
supply the unselected/selected three-piece tags. Selected characters walk in place, others stand. Both page arrows
are visible at full opacity but inert because this mode has only three slots. History reuses the left-edge
View All Characters plaque at (0,375), relabelled Run history,
with H as a shortcut; its list retains name/job/level, tiers, rounds, ending and UTC date. Deletion uses the existing
Basic/YesNo3 notice family and requires confirmation before calling SceneFlow.delete_character.

| Character UI fact / decision | Tier | Evidence / value |
|---|---|---|
| Login book, signboard, option-row labels, character/empty art, nameTag pieces, details cells, animation origins/delays | A | Original v83 Login.img, MapLogin.img and Map.wz/Obj/login.img; runtime lookups, no exported art committed |
| Character-select camera / signboard | C | Camera (28,-1208), signboard anchor (625,250), canvas TL(559,131), matched to v0.83 charselect_1.png in private spec32/v83-login-refs/wz-layout-notes.md; no stored WZ camera table |
| Explorer creation camera | C | (37,-3007), matched to period 2009 newchar_1.png mushroom cap/branch; compressed/rescaled capture, approximate |
| NewChar layout | C | Matched to period newchar_1.png: settings(470,95), rows(481,198), pitch19, arrows539/667, OK(508,425), Cancel(582,425), roughly +/-2px. Name canvas(480,95), input(510,198,140,24), OK/Cancel(508,273)/(582,273), matched to newchar_name_1.png +/-2-3px. Preview feet(398,335) eyeballed; option value box x556,width109 authored. Sources: private v83-login-refs/layout.md and wz-layout-notes.md |
| Selection stance / tags | C | walk1/stand1 selection integration and tags starting at feet y370 matched to charselect_1.png; width58 minimum / padding18 are reimplementation choices |
| Roster / action anchors | C | Adventure lamps at(252,370)/(377,370)/(502,370), shared by characters, shadows and tags; Create(576,185), Delete(576,234), Select(576,149), matched to charselect_1.png (Select wording differs) |
| Selected details / light | C (placement/policy), A (canvas/origin) | Scroll follows feet+(-108,-235), label inset(17,20), value cells and unavailable ranking matched to period charselect_2.png. Light/sparkle anchor feet-(0,337) uses WZ beam height but unverified effect registration. Fame0 and unavailable online ranking are offline policy |
| Page arrows / left navigation | C (placement/copy), A (art) | pageL(155,330), pageR(604,331), Back(0,425), history(0,375), Step(0,33) and Tab hint(270,40,220,40) matched to charselect_1.png. Back has zero sampled channel error; that remains screenshot inference. Select step Common/step/2 and creation /3 identities are verified in WZ. ViewAllChar/BtVAC frame/arrow are original art; patch vertices(10,17)/(102,8)/(104,30)/(12,39), label(12,19), angle-0.10,width88, colours, hint copy and pale-blue alpha0.8/4px corners are authored |
| Creation flow / gender placement | C | Name -> name OK validation -> appearance; name Cancel closes creation back to character select, appearance Cancel returns to name (spec #218, 2026-10-18: the separate Gender step and its Login.img Gender/* art are no longer drawn; creation opens on Name). Gender is chosen only on the appearance Gender row and defaults to Male; changing it resets the other looks. AP automatic, Beginner only. The earlier Gender parchment layout (219,174)/(245,198)/(355,346)/(430,346) with a native dropdown over the baked field was tier C and is retired |
| Creation advisory / weapon / feedback | C | Advisory rectangle(120,160,195,200) matched to period newchar_1.png; offline facts, 8px padding and pale-blue alpha0.8 plate are authored. Weapon strip(120,380,195,45), feedback(475,365,215,45) avoid preview/settings/buttons |
| Title screen | C | Ours, replacing the v83 login title: the Maple Survivors key art (`game/assets/branding/title.png`, 1672x941, logo baked in; also the boot splash) scaled to cover the view and resized with Lanczos to its on-screen size (`KeyArt`); BGM BgmUI/Title kept. `TitleButton`s drawn from code in the art's palette (gold bevel, red PRIMARY / dark stone SECONDARY fill, bold cream label 17/13 px): Start 168x34 at 8 px under the logo's tip (art y 785), then one row of 24 px buttons 8 px lower, 6 px apart, centred; both rows move up to stay 10 px above the view's bottom |
| Map-select roster names (#90, #32r) | C | 2px inner gutter per 58px cell, two lines; wrap only at spaces, ellipsize words wider than the cell. Survivor-only screen, no canonical stats/name changes |
| Results skill grid (#32r) | C | 232px column above a 6px gap before NEW BEST; up to eight skills retain 58px named cells, larger loadouts use at least six columns and compact icons/ranks, scaling to the available 150px height |
| Terminal death history (#32r) | C | Death requires no outgoing CharacterSnapshot; RunScene supplies none, so history retains the last saved boundary character's level/job. Results and the best-score record retain actual round-end summary stats; the slot is freed regardless of pending rewards/jobs/cards |
| Keyboard focus | A/C | Login keyFocused pointer overlays normal button art (A: Login.img button canvases/origins); focus/activation retained, roster arrows consumed before Godot focus navigation (C integration). The compact period details variant has no extra class badge |
| Shared notice / labels | A (art/width), C (placement/copy) | YesNo3 pieces, Basic OK/Cancel and 266px canvas width are WZ data. Text inset(20,17), buttons 14px from right / 31px from bottom / 4px apart reuse survivor PauseMenu placement. Deletion wording, shortcuts, compact weapon description and error ink153/34/0 are C |

Provenance follows AGENTS.md: A = verified in v83 data; B = third-party reverse engineering of an official
client; C = reimplementation inference or our own tuning. A placement matched to a screenshot is C,
even when the original WZ art registers exactly; only values actually read from WZ are A.
The private references are at `C:/Users/itech/Coding/maple-survivors-refs/research/spec32/v83-login-refs/`;
their research A/B confidence notation is distinct from our provenance tiers. Compressed period measurements
remain approximate. This is an original implementation using v83 assets, not a claim of verified pixel-for-pixel
v83 executable behavior. The local source
inventory and full criterion audit are in [ticket-70-r2-audit.md](research/ticket-70-r2-audit.md).
The character_driver's synthetic names, dates, levels/jobs, option indices and 0.5s screenshot settling delay are
tier C diagnostic staging only; it writes an evidence-local save and never the player's save. Its Free Market
capture supplies a completed boundary to SceneFlow (a visual carry check, not a played stage clear).

The #75 flow driver's diagnostic names, seed 1, 1800s combat cap, 600-tick yields, 100s progress logs,
30s/8px exit-walk guard, 0.35s capture settling and other UI waits/timeouts are tier C automation choices.
Its optional tier-2 victory path uses invulnerability and 1e9 neutral magic boss hits after 15:00, through the real
death/reward/clear path. This is presentation staging only; shipped data and smoke outcomes stay unchanged.

The #74 balance harness uses tier C measurement rules: tier 1 retains the run seed; each later round uses
Godot's `hash("balance-round-<run seed>-<zero-based tier>")`, independently of earlier draws. Chain selection uses
the first stage of each later `stages.json` tier; `--stage` overrides tier 1. Lv70 reach is a diagnostic from
the monotonically increasing level, never a clear condition or a calibrated target. Only a cleared round after
all reward/job choices exports a character into the next tier; no sample is imputed for an unstarted round.

The #69 flow uses the ordered `stages.json` tiers, with no hard-coded tier count (tier C, owner #32).
Creation is a fresh Beginner from the simulation defaults. A boundary is saved at map select and, before a round,
with its stage and seed; Quit round confirms that progress will be lost and preserves those bytes. Continue replays
the round from its start. Death and final-tier victory end the run in history; other clears carry the character
through the single `SceneFlow._after_round_cleared` seam. Tool-only `--run` rounds never write slots/history/bests.
The #70 character screen replaces #69's temporary plain slot/name/history presentation. Map select keeps
the existing parchment, adds the character/tier heading at y=32 and labels Back as Save & quit (tier C, layout).
The exact Quit round confirmation is owner #32 copy: "You'll lose this round's progress. Continue later to restart
the round from its beginning." Victory results show the tiers cleared and return to character select (tier C).

| Dark Cave bosses (#73) | Values | Tier | Evidence / rationale |
|---|---|---|---|
| Schedule / first-pass HP | Each boss arrives 300 s after entering its map: Zombie Mushmom 6300005 in Dark Cave, HP x0.8 (28000); Snack Bar 8220009 in Drake Area, HP x1 (110000); Jr. Balrog 8130100 in The Cursed Sanctuary, HP x3 (150000) | C | Owner schedule; scales chosen before measuring, no tuning; final boss has greatest multiplier and effective HP |
| Contact / attack scales, cadence, rewards | Contact and attack x0.8 / x1 / x1.25; each attack 8 s start-to-start; each death 3 HP / 3 MP plus existing global EXP and choice rewards | C | First-pass survivor encounter data in stages.json; final boss has greatest damage multipliers |
| Boss canonical facts | HP 35000 / 110000 / 50000; all seven attacks and delays/ranges/damage/element flags; no mob skills; Balrog S1H3 | A | Original v83 Mob.wz; [field inventory](research/dark-cave-boss-attacks.md), real-cache tests |
| Type-1 targeted direct rule | Admit body centre within r250 of mirrored sp(-28,-69); locked character takes magic hit at 1300 ms even after moving/jumping; effect at caster 700 ms, hit art at character; death/fade cancels | C | Later-client HaCreator targeted-direct description; **not verified v83 RE**, lead must flag this caveat on #73; research note above |
| Missing ball speed | 320 px/s only for absent/nonpositive bulletSpeed; positive authored values retain x1000/600 conversion | C | balance.mob_projectiles.default_speed; reference-inspired fallback for Balrog attack2; finite swept flight/range |
| Magic and delayed effects | magic=1 uses mob MADamage unless attack overrides it; effectAfter remains independent of attackAfter (Balrog attack3 500/400 ms); direct hit art at character impact | A fields/timings; C resolution/presentation | WZ field inventory and seeded tests; canonical values remain untouched |
| Boss icons and EXP pickups | Snack Bar borrows Zombie Mushmom icon and colours 1/5; EXP icons 4000008 / 4000011 / 4000028 | C | Original Snack Bar lacks gauge icon/colours; reuse imported signature art, not a drop-table claim |
| Attack evidence capture | Per-attack windup at min(0.85 s, half windup), at least one fixed tick; per-attack impact +0.12 s | C | Capture short ball windup before launch and keep seven distinct attack images |
| Debug encounter probe | Arrival 0.5 s, 8 s ceiling, 60 s skill wait, no ordinary spawns, god mode; offsets 100 px (200 ball / 300 beam); fixed 1/60 ticks; windup halfway capped 0.85 s, contact +0.12 s, ball flight launch +0.2 s | C | Diagnostic visual staging only, dark_cave_boss_driver; no shipped gameplay data is changed |

The spec #32 save contract (#68, tier C owner decision) uses save format 2 and three living character slots.
Run wrappers use the three phases `free_market` / `map_select` / `round` and zero-based next-tier indexes;
history endings are `died` / `victory` / `deleted`. Names use the owner's 4-12 ASCII letters/digits rule;
living names compare without case (our interpretation of uniqueness). Dates and round seeds come from callers.
These are persistence/creation rules, with no balance or canonical-data changes.

The spec #32 round-boundary contract (#67, tier C owner decision) carries character progression and permanent
growth/modifiers, ordered skills/card limits, Fortune and creation fields; potion tiers derive from level (#237). HP and MP
refill to computed maxima; all buffs, cooldowns (including manual Teleport), auto-cast/action/regen clocks,
player statuses and map entities restart. Format 1 is a serialization version, not balance tuning. Fixture float
fields round to six decimal places for readable committed JSON; generation never changes the survivor data.
Spec #34 adds the optional snapshot keys `cash` ({cash slot: item id}) and `pet` (species id) without a format bump;
a file without them wears nothing and has no pet, and the snapshot writes them only when set. The account (owned cash
items) reaches a round as the setup key `account`, never inside the character.

| Dark Cave addition (#72) | Values | Tier | Evidence / rationale |
|---|---|---|---|
| Run tier list | `[[henesys_hg1, tree_that_grew_1], [dark_cave]]`, index 0 = tier 1 | C | Owner #32 decision; binding spec32 decisions section 3 |
| Map and original spawns | 105050400; Horny 2110200 ×9, Zombie 2230101 ×7, Stirge 2300100 ×35; 14 ladders; NPC 9201133; exits 105050300/105060000 | A | Original v83 Map.wz/Map/Map1/105050400.img; loaded through the normal cache |
| Stage roster/order | Horny/Zombie/Stirge → Evil Eye 2230100 → Curse Eye 3230100/Jr. Boogie 3230300 → Tauromacis 7130100 → Taurospear 7130101 | C | Owner #72 roster; Tauro attacks from #76 (table below); Jr. Boogie contact only |
| First-pass pacing | 900 s; keyframes at 0/120/300/480/600/780/900 s, rates 3/4.5/7/10/12/15/18, caps 50/80/130/180/220/280/330, HP 1/1/1.15/1.3/1.4/1.5/1.6, speed 1/1.05/1.1/1.15/1.2/1.25/1.3; pool weights in 4.1 | C | Chosen before measurement for second-job arrivals; no tuning candidates |
| Supplies / elites / bursts / ending | Stage EXP 1x, shared per-kind potion cooldowns; hard cap 400; bursts first/every 90/90 s, size 10–40; elites first/every 75/60 s, HP/EXP/contact 8/5/1.5x; bosses and rewards gate clear | C | Existing stage conventions; #73 supplies the final-fight lifecycle; owner #237 cooldown model |
| Signature EXP pickups | Horny 4000015, Zombie 4000008, Stirge 4000042, Evil Eye 4000007, Curse Eye 4000013, Jr. Boogie 4000067, Tauromacis 4000028, Taurospear 4000046 | A IDs/names; C association | Original v83 String.wz/Etc.img names and Item.wz art; signature icon association is survivor data, not a WZ drop-table claim |
| Three-map signature EXP pickups (#242) | Ribbon Pig 4000002, Blue Mushroom 4000009, Zombie Lupin 4000031, Malady 4000041, Cold Eye 4000023, Drake 4000014, Ice Drake 4000030 | A IDs/names; C association | Original v83 String.wz/Etc.img names and Item.wz art; signature items are EXP icons in survivor mode |
| Three-map meso ranges (#242) | Ribbon Pig [20,30), Blue Mushroom [36,54), Zombie Lupin [104,156), Malady [251,359), Cold Eye [96,144), Drake [200,300), Ice Drake [324,486) | B | Cosmic v83 server `152-drop-data.sql`, `drop_data` rows with itemid 0; existing half-open range convention |

| Ordinary mob attacks (#76) | Value / behavior | Tier | Source |
|---|---|---|---|
| Tauro attacks | Tauromacis `attack1` type 0 magic L, MADamage 320, lt(-320,-240) rb(84,-1), attackAfter 480 ms; Taurospear `attack1` lt(-209,-225) rb(0,0) and `attack2` lt(-250,-60) rb(0,0), type 0 magic, attackAfter 420 ms, MADamage 390; `hit` art (Taurospear's are 1x1 placeholders), `Sound.wz/Mob.img/<id>/Attack1/2` | A | v83 Mob.wz / Sound.wz, read from the cache |
| Which mobs attack | every non-boss mob whose img lists `attackN` with type 0/1/2 uses the shared boss attack code; scheduled-boss kinds and boss slots never take this path; attacks tried in canonical order, the first admitted fires | C | ours; owner #76 decision 5 |
| Attack interval | `balance.mob_attacks`: 5 s for 7130100 and 7130101, `default_interval` 5 s (code fallback `MobAttacks.DEFAULT_INTERVAL`); per mob slot, start to start | C | ours; first pass before measurement, not tuned (#77) |
| Attack damage scale | canonical attack damage unscaled, times per-mob `dmg_mult` 1.0; elites also take `elites.damage_mult` (as for contact) | C | owner #76 decision 4; ours (elite) |
| Attack gate | grounded, fully faded in and not frozen (`MobSwarm.can_act`), feet inside the player-centred view, not inside another stance; the wait counts only while faded in, unfrozen and on screen | C | ours ("the boss rule" plus on screen) |
| First readiness | first wait = interval x (0.5 + 0.5 x frac(identity x 0.618034)), identity = the swarm's monotonic spawn identity (kept through relocation); same-tick spawns spread evenly over half the interval (distinct values; a burst of more than ~interval x 30 mobs shares fixed ticks) | C | ours; `MobAttacks.first_wait` |
| Slot lifecycle | a new mob in a slot starts unset (no wait, windup or stance); a relocation keeps waits, cancels a windup and clears the stance | C | ours |
| Mob skills of ordinary mobs | none cast: Jr. Boogie's Seal (120) and Curse (124) are skipped like any unsupported mob skill; character statuses come only from bosses, and no current boss lists MobSkill 120 | C | owner #76 decision (2026-10-17), replacing the brief's Seal |

| Constant | Value | Tier | Source |
|---|---|---|---|
| Teleport costs, range, effect and sound | canonical `mpCon`/`range` at owned rank; BasicEff/Teleport four 80 ms frames; branch Skill Use sound | A | local v83 cache and `docs/research/wz-inventory.md` section 7 |
| Teleport repeat and destination policy | 0.3 s between successful blinks; vertical input wins diagonals, opposite directions cancel to facing; horizontal chooses furthest supported point, snaps at most one canonical range vertically, closest height breaks ties; stops EPS (0.01 px) before walls; landing resets velocity | C | ours; `skills.json.teleport`, FootholdMap and RunWorld |
| Moving attacks (#190, 7.13) | A skill's `displacement` block (`direction` away/toward the faced mob, `when` before/after/during, `field`/`distances`/`distance` in horizontal px) moves the grounded character along its platform: instant placement, stops at the platform edge, 0.01 px (`FootholdMap.EPS`) short of a wall, inside the map limits; the cast never fails for terrain; no move while airborne; `during` (a charge) strikes up to `mob_count` bosses-first/nearest mobs in the swept attack box (start to end; the body box without a skill box); `before`/`after` keep the targets admitted at the start; the character turns to the mob first; `cast` event `pos` is the pre-move position | C | owner decisions (#168 grilling) + ours; `FootholdMap.slide_along`, `PlayerMotion.displace`, `SkillRunner._resolve_cast` |
| Teleport autoplay and HUD | same-height threats (existing duel band, feet +/-40 px): blink within 60 px, or when mobs block both sides within existing 160 px flee distance. An edge within 60 px plus a threat within 60 px on the interior side escapes toward the interior; otherwise choose the safer side. Requires learned skill, reserve, interval and a destination. HUD: the shared blue waiting-for-MP tint (#82; was 0.35 grey); 80 ms evidence capture delay | C | ours; BotInput, HudSkills, RunScene |
| HUD skill and potion cooldown sweep | a cooling skill icon is covered by a black 60% overlay wedge of (left / total set at the last cast) x 360 degrees ending at 12 o'clock, so it clears clockwise, moving in 1/96 steps of the cooldown (one per pixel of a 24 px icon's edge; the widget redraws only when a step or tint changes); not drawn below 0.2%; Teleport uses its repeat timer; no MP wait tint (no MP, #285); no seconds text | C | ours (#82, #239); CooldownSweep (SWEEP_STEPS), HudSkills, HudQuickSlot; RunWorld.skill_readiness / read_skill_cooldowns |
| Bot Teleport interval | at least 5 simulation seconds between valid-destination escape requests, recorded in bot memo | C | a priori policy: allow several auto-cast cycles and ordinary kiting before another emergency blink; independent of the player's 0.3 s repeat; `BotInput.TELEPORT_MIN_INTERVAL` |
| Teleport card weights | new/rank weight 2, max rank 20; no behaviour modifiers | C | ours; upgrades.json |
| Skill keys (#188) | a manual skill's `skill_key` is its input action; Key Config lists only learned ones after the fixed actions; Teleport and Dash both default to X (a character never learns both); the three Teleports share `teleport`, so a saved `teleport` binding is Teleport's skill key; a press that cannot pay (MP) does nothing | C | ours (owner); `KeyBindings.SKILL_KEYS`, `RunWorld.manual_skill_keys`, `project.godot` |
| Dash (#188) | canonical mpCon 14-5, speed x 12-30, jump y 1-10, time 4-20 s over ranks 1-10 (tier A); manual on its skill key instead of the v83 double-tap, any weapon, no cast hold, no cooldown beyond the running buff, speed and jump under the existing 140 / 123 caps, card weights 2/2 | A (numbers), C (manual key, no hold, weights) | Skill.wz 500.img 5001005; owner decision on #168; `skills/pirate.json`, `upgrades/pirate.json` |
| Bot Dash flee rule (#188) | press when HP < 50% with a mob within 160 px, or when 3+ same-level mobs are within 120 px; requires ready, usable and an affordable HP cost | C | ours; `skills/pirate.json` `dash.manual` (`bot_flee_hp`, `bot_surround_count`, `bot_surround_distance`); `BotInput._flee_buff` |
| Physics.img values | see `docs/research/wz-inventory.md` §2 | A | v83 Map.wz |
| Potion restore amounts and icons | Red 50 HP, Orange 150 HP, White 300 HP | A | Item.wz/Consume/0200.img, unchanged spec/info |
| Quick slot cell geometry (#220) | white cell interiors 27 × 25 at (10, 9) of the 151 × 80 `base/quickSlot` canvas, pitch (35, 34); 32 px icon box at (7, 6); 9 px key caption at the cell's top-left, potion cooldown sweep over the icon (#239) | C (measured on the art) | ours; HudQuickSlot |
| Walk/jump/air/down-jump/landing model | §3 | B | NoLifeStory physics description |
| Player sub-step | 2 per 1/60 s tick | C | ours |
| Vertical air drag | none (apex 555²/4000 = 77 px) | C | ours; NoLifeStory's 100 px/s² vertical float drag would give ~73 px |
| Climb speed | 100 px/s | C | ours (HeavenClient uses 125) |
| Ladder grab/exit | Up: hands 50 px above the feet within 10 px of x; Down: 10 px below the feet; 0.25 s re-grab delay; exit jump vx = max walk speed, vy = jumpSpeed/1.5; `uf=1` top exit onto a floor within 24 px above / 4 px below the top | C | ours / HeavenClient exit jump |
| Same-map portal activation and arrival | feet x ±25, y −100…+25; arrive 30 px above target with zero velocity; global cooldown 384 ms; camera snaps, no sound or transition | C | owner choice; `balance.json.portals` |
| Autoplay portal choice | approach a same-map entrance when its walk plus arrival-to-drop distance is less than going directly (horizontal distance + 2 × vertical); with a mob within 160 px, an entrance within 250 px can instead lead to less nearby mob danger. Reach entrance ledges through existing jump-graph edges; hold Up in the activation box and during the entrance hop | C | ours; uses the bot's existing drop, danger and alignment rules |
| Autoplay reverse-portal hold (#257) | After a same-map warp, the link from its target straight back to its source is not chosen for 5 s (`BotInput.REVERSE_PORTAL_HOLD`, bot memo, cleared on map change); other links stay open | C | ours: Perion 102010000 seed 1 (bot) died at 62 s bouncing hide00/tohide00 every 0.384 s cooldown, escape up then drop route straight back into the crowd. Maps without two-way pairs (Henesys, Kerning, Sleepywood) never reach it; Ellinia smoke records are unchanged |
| Autoplay walls (#259) | Stuck (no x progress for 15 ticks, `BotInput.STUCK_TICKS`) at a wall: if no wall stands 0.85 × the jump apex (~65 px, `STEP_CLEAR_FRACTION`; apex jumpSpeed²/2·gravityAcc) above the feet within 4 px ahead (`WALL_PROBE_AHEAD`), the bot jumps on in its direction; otherwise it turns back for 45 ticks as before and remembers the wall for 30 s (`WALL_HOLD`, renewed at each stall, bot memo, cleared on map change). While remembered and the bot is on its near side within 140 px of that height (`WALL_BAND`): drops, ladders and the map centre beyond it are not goals, with the centre beyond it the bot walks away until 300 px off (`WALL_CLEAR`), and the wall bounds the kiting room like the map edge | C | ours: Kerning 103010000 seeds 1/2026 (bot) walked into the x 350 wall for minutes from a pocket whose other side is a 30 px step at x 505; the old stuck rule jumped backwards from both walls (test_bot_walls) |
| Down-jump reach | a floor within 600 px below | C | HeavenClient |
| Player knockback hop, alert stance | 200 px/s up, 2 s | C | ours |
| Player placement | `PlayerMotion.place()` snaps onto a floor at most 1 px below, else the player falls | C | ours |
| Falling out of the world | below the MapBounds bottom the player is put back on the nearest floor (`EV_FELL_OUT`) | C | ours |
| Wall probe | a wall blocks where it covers the point 1 px above the feet (a wall hanging below a platform end can be walked off) | C | ours |
| Wall scope | a wall stops a body (player, pet, mob, the bot's probes, NavGraph drops and jump arcs) only when it belongs to the body's platform, the one stood on or last stood on while airborne: same foothold group number as one of the platform's floors (layer ignored), linked to one of its floors through prev/next, group 0, or cantThrough (`FootholdMap.wall_applies`); a body with no platform yet meets every wall | B | NoLifeStory physics.cpp (prior-art.md 1b): air collisions only with footholds of the group last landed on, group 0 or cantThrough; on the ground only the linked wall stops. Ours: one rule for ground and air, by platform. 103010000's layer-0 building faces (x -710, 350) stood across the layer-1 stairs and the layer-2 ground as invisible walls (also the #259 pocket) |
| Ceilings (x1 > x2) | stop upward motion at the feet (head bump), never landed on; mobs never hop straight up through one | B | NoLifeStory description (prior-art.md §1b) |
| Map bounds without VR | miniMap rect (-centerX, -centerY, width, height), else foothold box with top -300 / bottom +100 | C | ours / HeavenClient border rule |
| Mob nav (`NavGraph`) | hop 555 px/s, jump height ≤ 70 px, takeoff ≤ 90 px from landing, land 8 px inside; a drop steps off the end at 120 px/s for 4 px, then falls straight down (the same for every mob, so the graph predicts its landing exactly) | C | ours |
| Mob way (travel-cost field) | mobs take the way of least walking to the player's x, a drop or hop counting 40 px (`edge_cost`, about a fall's time; not the fewest edges); the field is rebuilt when the player moves 16 px (`target_step`); a mob keeps its way until another is 96 px shorter (`route_hysteresis`); a straight-up hop takes off at the point of its range nearest to where the way goes on | C | ours |
| Low step | a walker on a floor at most 40 px below the player's feet (`reach_y`, about a mob's height: it can touch the player from there) walks under the player instead of having no way; jumpers hop onto the step | C | ours |
| Mob stop distance | a mob on the player's platform stops 2 px from the player's x | C | ours |
| Mob regen fade | 0.3 s, standing still meanwhile | C | ours |
| Mob fallbacks | die time 0.5 s without `die1`; hitbox (-20,-40)-(20,0) without `lt/rb` | C | ours |
| Mob speed | (speed+100) × 0.625 px/s | C | HeavenClient terminal speed |
| Mob hit stun / push | 0.24 s / 12 px | C | HeavenClient / ours |
| Mob Slow magnitude/duration | signed canonical x; speed × clamp((100+x)/100,0,1); canonical time | A fields / C steering integration | original Skill.wz/210.img/2101003; [status research](research/monster-status-effects.md) |
| Mob status refresh/lifecycle | independent statuses; refresh duration without stacking; poison restarts pulse; clear silently on death/release/relocation; natural expiry event; pause holds timers | C | #54 interface policy; double timers expire at fixed-tick boundaries (1e-9 s numerical tolerance) |
| Mob poison HP rule | min(32767, ceil(slot max HP/(70-skill level))); 1 HP floor; no stun/push; actual player damage credit | C | Cosmic v83 server reference, not native-client RE; [pinned sources and limits](research/monster-status-effects.md) |
| Mob poison cadence | 1 s; first after 1 s, final pulse at expiry when due | B v95 display / C sim boundary policy | native-derived v95 CMob::Update; Cosmic schedules 1 s; [status research](research/monster-status-effects.md) |
| Mob Freeze behavior | no walking, facing changes, attacks, skills, stun/push or animation advance; lethal hits still die; an airborne monster still falls straight down and a fading-in one keeps fading in | B v95 extrapolation / C animation-hit integration and owner fall/fade choice | native-derived IsImmovable, TryDoingSkill, DoAttack; [status research](research/monster-status-effects.md) |
| Frozen touch damage | a frozen monster deals no touch damage (MobSwarm.can_act gates touch) | C | owner decision; no native v83 contact gate verified either way; [status research](research/monster-status-effects.md) |
| Boss status immunity | scheduled steady or canonical boss: reject Slow, Poison, Freeze and Stun | C | v83 server reference (Cosmic Monster.applyStatus boss gate), owner decision replacing #54's boss-poison permission |
| Elemental status immunity | a status fails on Mob elemAttr digit 1 (immune), 2 (strong) or 4 (neutral) for its element: Poison S, Freeze I (or the applying skill's element); Slow elementless | A element letters / C rejection rule | Poison Breath elemAttr s and Cold Beam i in Skill.wz; rejection per Cosmic Monster.applyStatus; [status research](research/monster-status-effects.md) |
| Player elemental hits / undead | Mob elemAttr digit1 ×0, digit2 ×0.5, digit3 ×1.5; absent/elementless ×1; final rounding; undead exposed independently | A factors/flags; C rounding integration | original Cold Beam String.wz text and Mob.wz; [status research](research/monster-status-effects.md) |
| Mob Stun behavior | no walking, route/jump/flyer pursuit, new attacks or mob skills, touch damage or hit flinch/push while stunned; animation clocks and damage continue; an airborne mob still falls straight down; a new stun keeps the longer remaining time; elementless (never rejected by an element); `on_hit` `prop`/`time` from Skill.wz | C | #187 owner brief; the stunned look and the `prop`/`time` fields are Skill.wz (tier A) |
| Hidden state (#194, 7.18) | while a `hidden` buff is active: mobs and bosses neither chase nor attack (ground mobs patrol, flyers hover, bosses do not pursue-teleport), no contact damage, no mob attack, mob skill aimed at the character or ball hits it (balls pass through; a windup in progress lands nothing), and the character starts no attack or auto-cast (buffs, potions, pickups, movement and manual movement skills still work) | C | owner decisions (#168 grilling); the patrol/hover choice and the director rules are ours |
| Oak Barrel values (#194) | MP 11-20, time 12-30 s, failure chance 37-10% (`prop`), cooldown 35-15 s, morph 1002; the cooldown counts from the cast even when the barrel outlasts it | A | Skill.wz/510.img/skill/5101007 (`prop` read as the failure chance per the #194 brief) |
| Oak Barrel conditions (#194) | casts below 30% HP with a mob within 250 px and the cooldown ready; the barrel ends early above 60% HP; a failed cast still starts the cooldown, rolled once per cast on stream 16; cards: learn weight 3, rank weight 2, max rank 10, Brawlers only | C | owner decisions (30%, 60%, mob near, stream 16) + ours (250 px, card weights) |
| Morph rendering (#194) | the avatar is replaced by one `Morph.wz` canvas per frame, feet on the origin; attack and cast stances show `stand`; the morph's `info` speed/jump are not applied | A art / C mapping | Morph.wz/1002.img; stance-to-action mapping is ours |
| Mob Stun cue | the v83 stun stars (`mob` node of Backspin Blow, Shout, Blank Shot ...: 3 frames, 100 ms, repeat), looped over the body top (pos2); yellow (1,.95,.55) tint fallback | A art / C anchor and fallback tint | Skill.wz 111.img skill 1111008 mob (identical to 5101002/5101003/5201004); manifest entry in asset_manifest.json |
| Mob status cues | Slow one-shot cached mob art, Poison repeat art; pos3 centre/pos2 top; Slow amber (1,.72,.40), Freeze cyan (.45,.80,1), fallback Poison violet (.72,.45,.90) | A art / C anchors and tint choices | original Skill.wz/210.img, Cold Beam has no mob overlay; [status research](research/monster-status-effects.md) |
| Default frame delay | 100 ms | C | HeavenClient |
| Background scroll | rx × 5 px/s | B | 3 reimplementations agree |
| Damage number timing | 400 ms hold + 600 ms fade, 30 px rise | B | v95 RE (Harepacker docs) |
| Player knockback | 187.5 px/s, 0.3 s lock | C | HeavenClient |
| Hit window lengths (#88) | `balance.hit_window.lengths` 1.5 / 1.0 / 0.6 / 0.4 s: the grace after the 1st, 2nd, 3rd, 4th+ chained landed hit from contact damage or an ordinary mob attack (a lone mob always gives the full 1.5 s) | C | ours; replaces the old fixed `invincible_time` 1.5 |
| Hit window chain gap (#88) | `balance.hit_window.chain_gap` 2.5 s: a landed hit this soon after the previous landed hit steps to the next shorter window; between 2.5 s and the reset the step holds | C | ours |
| Hit window reset (#88) | `balance.hit_window.reset_after` 3.0 s without a landed hit restores the full window (and starts the chain over) | C | ours |
| Boss skill attacks ignore the hit window (#88) | A boss skill attack (`source_kind` `attack`, `projectile` from a scheduled boss) lands during the window, hits at most once per attack instance (a ball is used up only when it hits), starts the full `lengths[0]` window without advancing the chain and counts as a landed hit for the reset. Boss body touch and every ordinary mob attack respect the window; an ordinary ball that the window turns away flies on, with no hit and no hit art, and can land once the window ends (also from inside the body box). Misses give no window and do not touch the chain; god and death still block everything | C | ours |
| Ordinary mob attacks and the hit window (#144) | An ordinary mob's area or targeted (type 0/1) attack that the hit window turns away at impact does nothing: no damage, no `player_hit`, no `hit` phase and no hit art, as an ordinary ball already behaves (#88). A rolled MISS is not blocked: it emits the MISS `player_hit` and keeps its hit art. Boss attacks bypass the window as before; dead and god-mode attacks are still no-ops for damage and keep their hit art, as before. No v83 evidence settles the window rule: Cosmic does no invincibility check (the client decides hits), the HeavenClient-family clients skip collisions while invincible but have no mob-attack hit art, and Harepacker's later-client simulator draws hit art regardless (weak evidence) | C | ours; owner decision 2026-10-17 |
| Knockback guard (#223) | A hit that knocks the player back starts a guard of `balance.hit_window.lengths[0]` (1.5 s today, read from the data, no new constant), ticked by `PlayerUpkeep`. Landed hits inside it (after the shrinking damage window) do damage, Power Guard/Magic Guard, `player_hit`, damage number and chain stepping as usual but no `PlayerMotion.knockback` (no shove, input lock or alert stance) and do not restart the guard. Boss skill attacks/balls (window bypass) still knock back and restart it. Misses change nothing; the timer is per round and not in the `CharacterSnapshot` | C | ours; owner decision 2026-10-18 playtest grilling |
| Mano slow / defense interpretation | x80 retains 80% speed; x85 adds flat PDD/MDD, refreshed without stacking | C | owner-selected slow; explicit defense arithmetic interpretation, not verified client code |
| Boss skill first use | every enabled boss skill (all six bosses) first becomes ready one canonical `interval` after the boss arrives, then one interval after each cast; never on the arrival tick | C (timing rule), A (intervals) | ours; MobSkillRunner; original v83 MobSkill.img intervals |
| Boss defense buff recipients | MobSkill 112/113 give their flat PDD/MDD to every living mob inside the canonical area (ordinary mobs included) for the canonical time | A (area, x, time), C (flat arithmetic) | v83 MobSkill.img area buffs; MobSkillRunner |
| Mano skill scheduling / summons | first use after interval, one canonical stance at a time; omitted hp100%; 24 px symmetric spawn spacing | C (policy/spacing), A (intervals/list/limit/art) | ours; original v83 WZ |
| MobSkill effect anchors / summon family | affected pos1 at body top, effect pos3 at mob center; summonEffect1 selects Effect.wz/Summon.img/1 | C (mapping/placement), A (art/origins/delays) | ours; original v83 WZ |
| Basic physical damage / interval | §6.1.1; Sword k4, Wand swing4.4/stab3.2, mastery0.1; quantized speed interval | B | owner-provided pre-Big-Bang mechanics |
| Starter afterimage / sparks | variant0 for every weapon (`WeaponInfo.AFTERIMAGE_VARIANT`); sword* afterimages use the sword spark, the rest the mace spark; spark1 swing / spark2 stab | C (selection), A (art/bounds/delays) | ours; original v83 WZ |
| Weapon stances / actions (#154) | `stand<info/stand>`, `walk<info/walk>`; `WeaponInfo.BASIC_ACTIONS` per weapon type; `basic_kind` (ranged families shoot) | A (stance numbers, stances in the items), C (which stances a family attacks with) | v83 `Character.wz/Weapon`; ours |
| Ranged basic-attack reach (#154) | `WeaponInfo.RANGED_REACH` bow/crossbow 300, claw/gun 250 px, box 65 px tall: when the attack starts; the shot flies this plus `overshoot` | C | ours |
| Ammo ids, incPAD and names (#155) | starting ammo per family (2070015, 2060000, 2061000, 2330000) and every scheduled item; incPAD from Item.wz, names from String.wz | A | v83 `Item.wz/Consume` 0206/0207/0233 (refs `class-specs/v83-facts.md` 1) |
| Ammo upgrade levels (#155) | Assassin 30/35/40/45/50/55, Hunter 30/40/50, Crossbowman 30/40/50 (`survivor/ammo.json`) | C | ours; the Gunslinger's 30/50 are the items' v83 `reqLevel` (A) |
| Endless ammo (#155) | never consumed, never an item, derived from family/job/level; v83 consumes `bulletCount` per attack | C | owner spec #151 |
| Ammo projectile numbers (#155) | speed 800 (claw), 900 (bow), 1000 (crossbow), 1200 (gun) px/s; radius 8/6/6/5 px; range = reach + 80 px; arrows and bullets rotate | C | ours; `survivor/ammo.json` |
| Ammo W.Att on ranged attacks (#155) | the current ammo's incPAD adds to W.Att | B | Cosmic Character.recalcLocalStats / RangedAttackHandler (v83-facts 1) |
| Magic damage formula | §6.1 | C | community formula |
| Monster-to-player damage | attack × uniform[0.85,1] − floor(0.75 × defense), elemental resistance, explicit source multipliers, rounded, minimum 1 (§6.2) | C | owner's choice; not verified in the v83 client |
| Monster miss chance | 21.6 × player avoid / mob accuracy percent, clamped 0–100% | B | weak: a single private-server wiki page describing pre-Big-Bang RE (owner-provided), not corroborated by a second source |
| Elite damage | ×1.5 after defense/resistance, before final rounding | C | survivor choice in stage elites.damage_mult |
| Boss arrivals and scaling | both stages at 5/10/15 min; HP/contact/attack multipliers in §4.3 | C | survivor data calibrated on training runs; canonical base stats unchanged |
| Normal spawns during a boss | while any boss lives the steady spawn rate and every burst's count are ×0.5 (bursts are normal spawns; count rounded); elites unchanged | C | spec "normal spawns run at half rate", our reading that bursts are normal spawns; balance.bosses.normal_spawn_mult |
| Boss warning / placement / pressure | 3 s lead; no arrival point on the arrival tick: slip 3 s behind a fresh warning; missing mob img: skipped with a run warning; preferred 250 px, minimum 150 px (closer fallback on narrow floors); ordinary rate/bursts ×0.5 while a boss lives | C | survivor choices in balance.bosses |
| Boss relocation | no route/progress for 5 s; progress requires 1 px of own movement and route gain; 300 ms fade-out, ~250 px platform arrival with ordinary harmless regen | C | owner rule; balance.bosses |
| Boss rewards | canonical EXP ×5 in 12 drops, spread ±120 px; current-tier HP3/MP3 bundles (Mano HP6, second bosses HP1; MP3 throughout) at ±30 px; one bonus upgrade before clear, preserving level queue | C (multipliers/design); A (base EXP) | survivor reward data; v83 Mob.wz |
| Bonus choice layout | first row at 52 px below reward title/instruction, canonical card rows and panel fill | C | ours; LevelUpWindow |
| Boss stun and push immunity | every scheduled boss: no stun/push, regardless of pushed or info/boss; kinds with info/boss or `no_flinch` also never flinch | A flag / C behavior | v83 info/boss, survivor encounter rule (`MobSwarm.steady`) |
| Mushroom slam cadence / scaling / dodge | 8 s; separate attack ×0.55 / ×0.72; airborne at impact dodges jumpAttack; captured ground anchor/facing | C | survivor choice and lore; canonical attack300, range, attackAfter1050ms, frames and effectAfter0 are A |
| Stumpy HP/contact/attack | ×0.45 / ×0.83 / ×0.77; attacks every 8 s when eligible; Tree Branch EXP icon | C | training calibration; canonical stats/art A |
| King Slime / Dyle HP and hit scaling | HP ×1.1/×0.26; King touch×1.36/slam×1.06, Dyle touch×1.14; King8s cadence | C | training calibration; canonical stats and attack delays A |
| King Slime stance / death list | no_flinch override;24px offspring spacing, unconditional canonical eleven-entry revive list | C (stance/placement), A (list/IDs) | ours; original v83 info/boss absent, info/revive untouched |
| Dyle heal / weapon immunity | canonical x 5,000 heal (y unused); timed self physical immunity, consumed blocked shell; pos2 body-top anchor; Tree Branch EXP icon | C (interpretations), A (bounds/gates/durations/art) | ours; original Skill114/17 and140/8; spec "canonical amount" |
| Monster ball flight / collision | bulletSpeed×1000/600 px/s, range/r lifetime, straight aimed launch;8 px contact radius | C | later-client reference comment inspires interpretation; original v83 values A |
| Mob heal arithmetic / timing / art anchor | each mob in the canonical area regains exactly canonical x, clamped to max HP; y unused; no RNG; effectAfter application; mob0 starts at cast, pos0 at feet | C (interpretation/anchor), A (fields/art) | spec "canonical amount"; original v83 WZ |
| Slam evidence screenshots | windup at 0.85 s; ground wave 0.12 s after impact | C | presentation capture timings only |
| Post-duration ramp / harness cap | final keyframe slopes ×0.25 after curve time 15:00; burst size slope ×0.25 past the curve duration; elite interval × rate(last keyframe) / rate(t); 30:00 total-round cap reported as timeout | C | survivor stage/balance data |
| First MISS screenshot | 0.05 presentation seconds after the first miss, only when screenshots are enabled | C | evidence capture timing |
| Projectile speeds/ranges | §7 | C | ours |
| Projectile hit exclusion identity | packed 64-bit run-local spawn identity; fresh spawns differ, relocation preserves it | C | our pool bookkeeping; no canonical or balance values changed |
| Camera smoothing | exponential, 6/s, 8 px dead zone, player at 58% height | C | ours |
| Player start | 50 HP (v83 Beginner, owner decision; no MP, #285), STR 12 / DEX 5 / INT 4 / LUK 4, Three Snails rank 1; Magician magic attack 23 (Wooden Wand 1372005 incMAD) | C (A for the wand) | ours |
| Automatic AP and advancement reset | 5 AP per level, Beginner → STR, Magician → INT; only earned AP is redistributed on advancement | C | survivor rule, emulator-style reset |
| Magician secondary AP (LUK) | earned AP fills LUK until base LUK = level + 2 (keyframes 1 → 3, 200 → 202), the rest to INT; Beginner none | C | v83 Character.wz reqLUK pattern (15 at Lv13 ... 70 at Lv68), ticket #106 |
| Player avoidability | DEX × 0.25 + LUK × 0.5 + worn equipment incEVA | B (A for equipment) | Exoot 2009 formula compilation / v83 Character.wz |
| Player body (touch box) / cast origin | (-14,-58)-(14,0) from the feet / 30 px above the feet; shots start 22 px further toward their target (the hand) | C | ours |
| Cast stance | the skill's `action` (swingO1) for 0.8 s (its WZ frames 300+150+350 ms) while standing still | C | ours |
| Climbing cast gate | no new skills, basic attacks or buffs while on a rope/ladder; cooldowns and existing effects continue | C | owner choice |
| Magic Armor values and durations | canonical time/pdd at cast skill level; L1 Armor 54 s/+2 PDD (Magic Guard removed, #285) | A | Skill.wz/200.img |
| Player buff lifecycle and row | cast while inactive, expire/recast if affordable; snapshot cast rank, passive slots; 32 px icons with 4 px gaps and countdown labels; alert2 stance held 800 ms | C (lifecycle/layout/timing), A (icons/action) | owner choice; ours; v83 Skill.wz |
| Flyer speed / bob / arrivals | (`flySpeed` + 100) × `mob_speed_factor` × stage speed; bob 2 px / 1.2 s (`balance.mob_motion`); Henesys arrival keyframes 180 / 300 / 480 / 660 s, weights 1 | C (conversion and tuning); A (stats and frames) | ours; original v83 WZ |
| Goblin Fire EXP icon | Firebomb Flame 4000081 stands in for a signature EXP drop | C | ours (item art A) |
| Skill cooldown/range/speed/count/pierce, shot radius | `skills.json` (12-14 px radius); shots ignore terrain and die at their range or 200 px outside the bounds | C | ours |
| I/L attacks (#56) | Cold Beam nearest-target auto-cast: 300 px, 1 target, 1.25 s cooldown; Thunder Bolt box auto-cast: at least 1 target, 1.5 s cooldown; both use swingO1 for 0.8 s | C | survivor skill definitions; v83 has no action node for either skill |
| I/L canonical attack facts (#56) | ranks 1–30, elements i/l, mad/mastery/mpCon; Cold Beam x=-100/time=1–2 with no prop; Thunder Bolt mobCount=6 and lt/rb; effect/hit art and Use sounds, no ball | A | original v83 Skill.wz/220.img and Sound.wz/Skill.img/2201004–2201005, real-cache tests |
| I/L cards (#56) | Cold Beam +1 target; Thunder Bolt box offsets ×1.2; both cooldown ×0.88; 3 modifier steps each; learn/rank/modifier weights 4/3/2, all power, exact job 220; shared rarity magnitudes | C | owner #31/#56 behaviour choices; existing count/area/cooldown and Potential seams |
| Thunder Bolt target card (#84) | Forking Storm: `count` +2 per step, max 3 steps (canonical `mobCount` 6 → 12), weight 2, power, exact job 220; bot scores it as a `count` mod (75 + job bonus 12) | C (placeholder until the balance pass) | #84 hit-more-mobs rule; upgrades.json `thunder_bolt_targets` |
| Shots with fewer targets than projectiles | the extra shots reuse targets, aimed 8 px apart | C | ours |
| Pity / power cards | after 1 draw without a power card the next draw starts with one | C | ours |
| Potion schedule (#225, #228) | `balance.potions.schedule`: HP Orange @ Lv 10, HP White @ Lv 25 (the MP step removed, #285); applied at level-up with a notice and silently on snapshot load, cooldown kept, never downgrades; replaces the potion-tier cards | C | owner choice (the old card gates); balance.json |
| Researched potion steps (#229) | `balance.potions.schedule`: HP Unagi 2022003 @ Lv 40, HP Ice Cream Pop 2001001 @ Lv 60 (items, recovery, names: tier A from v83 `Item.wz`/`String.wz`; shop stock tier B/C; levels tier C, the Lv 60 step an extrapolation; the MP steps removed, #285) | C | `docs/research/v83-potion-progression.md` section 6; balance.json |
| Potion notice plurals (#225 review) | `balance.potions.plural_names`: `{"2022003": "Unagi"}`; any other scheduled item reads String.wz name + "s" | C | our own wording; balance.json |
| Bot waste guard cap (#229) | `BotInput.worth_drinking`: the potion's restore counts up to the max HP pool, and at least `potions.bot.pool_floor` = 0.25 of the potion (drink when missing >= `min_restore_fraction` x max(min(restore, pool), 0.25 x restore)) | C | our own policy so the 1000-2000 point steps stay drinkable |
| Sparse draws | 3 choices when full; otherwise eligible cards plus one Elixir, alone at 0 | C | owner choice; upgrades.json |
| Current-job cards and Elixir reward | strict job equality, Beginner cards require 0; learned earlier-job skills retained; one Power Elixir alternative below 3 eligible cards, alone at 0; fully restores both pools | C (reward/pool rule), A (2000005 identity/art/restoration) | owner choice, #38; upgrades.json fallback |
| Bot potion waste guard | drink when missing HP >= 0.5 x one current potion's canonical restore (`min_restore_fraction`) | C | owner review of #29; BotInput, shared by sensible and random card policies |
| Bot sword duel | a lone ordinary mob within 160 px and 40 px of the feet while no attack skill is ready and affordable: stand facing it so the basic attack swings; flee from two or more | C | owner review of #29; BotInput, shared by every movement policy that uses it |
| Bot Guard preference / offers | base-score overrides learn 110, rank 109 (the #63 gain term is added on top); no job bonus added; learn/rank offer weights 8/8 | C | balance.bot.card_scores; upgrades.json; random choices uniform |
| Bot card gain step (#63) | sensible bot card score = base + `gain_step_score` x (offered `magnitude` - 1); `gain_step_score` 6 (coded default `BotInput.SCORE_GAIN_STEP` 6 when absent); missing or <= 0 magnitude counts as 1; potion-tier and Elixir cards ignore the gain; no tier name or `max` is special-cased; first/random policies unaffected | C | owner #63 triage 2026-10-17; survivor balance.bot.gain_step_score |
| Three Snails auto levels | skill level 2 at Lv 3, 3 at Lv 6 (`level_ranks`) | C | ours, after the v83 Beginner's SP |
| Advancement draws / skill counts | no skill grants; extra new-job attack-first draw with rarity before the normal level draw; no skill slot caps | C | owner decisions #31 / #53; sections 8?9 |
| Second-job Max MP | unused since #285 (no MP): the `jobs.json` `grants.max_mp` values (+475 for 210/220/230, first-job +120) are ignored | C | server reimplementation, unverified against GMS; [research](research/cosmic-data.md), local `Character.java:1204` |
| Bot branches / owned-skill HUD | independent seeded stream 8; optional forced branch; eight 24 px icons per row, 4 px gaps | C | #53 harness and presentation |
| Upgrade prerequisites | canonical `req` and previous survivor skill prerequisites ignored; exact job gates and owned-skill rank/modifier requirements retained | C | owner decision #31 |
| EXP curve, pacing keyframes | sections 4.1, 5 (`balance.json` `exp_curve`, `stages.json`), tuned with `scripts/balance.sh` | C | ours |
| Skill rank tables | every rank equals its canonical level; Beginner skills 3, first-job attacks/buffs 20, Fire Arrow 30 | A (level counts); C (tier gain per card) | v83 Skill.wz level tables; owner choices #39 / #30 |
| Fortune and card odds | base 0; Normal/Rare/Epic/Unique/Legendary weights 75/18/5/1.7/0.3; non-Normal weights ×(1 + max(0, Fortune) ×0.02), normalized | C | spec #30 weights (owner restored them over C46 on 2026-10-15; untuned); upgrades.rarity and balance.player.fortune; cards only, not canonical LUK/drops/crits |
| Cash slot Fortune | 11 cash slots (hat, face, eye, earrings, top, bottom, shoes, gloves, cape, weapon, shield); each filled slot adds hat 10, face 8, eye 8, earrings 6, top 10, bottom 10, shoes 9, gloves 9, cape 10, weapon 12, shield 8 (sum 100); overall = top + bottom, two-handed cover = weapon + shield; computed live, never stored in the character | C | spec #34 / #116, ADR 0003; placeholders in `cash_items.json` `slot_fortune`, set by the balance pass |
| Cash slot from item id | id / 10000: 100 hat, 101 face, 102 eye, 103 earrings, 104 top, 105 overall, 106 bottom, 107 shoes, 108 gloves, 109 shield, 110 cape, 170 weapon cover | A | v83 item id categories (spec #34 research) |
| Pet and pet upgrade prices | Brown Kitty 5000000, Brown Puppy 5000001, Pink Bunny 5000002: 4,900 NX; Auto HP Pouch 1812002, Wing Boots 1812004, Binocular 1812005: 1,800 NX (the Auto MP Pouch 1812003 is no longer sold, #285) | A | Etc.wz/Commodity.img OnSale listings (`cash_items.json`, with the SN) |
| Cash equipment catalog | 116 curated items: hat 10, face 10, eye 10, earrings 10, top 10, overall 10, bottom 10, shoes 10, gloves 10, shield 6 (all that qualify), cape 10, weapon cover 10 | A (price, SN) / C (selection) | OnSale=1 `Etc.wz/Commodity.img` rows, price and SN as listed; a cache-backed test checks each entry. Filters (tier C): unisex id (thousands digit >= 2; the Commodity `Gender` field is unreliable), `info/cash` = 1, no `reqLevel`, real canvas art, covers need 37 and 38 art; rings and the "Transparent" items have no sprite and are out |
| Two-handed weapon cover | `two_handed: true` on 1702004, 1702042, 1702078: the covers whose `info/vslot` is WpSi (they occupy the shield slot too) | C | inferred from the vslot; WZ has no two-handed flag on covers |
| Weapon cover type | the cover draws the `<type>/<stance>` art of the real weapon's type, type = weapon id / 10000 - 100 (30 sword, 37 wand, 38 staff, ...); no art for the type or stance leaves the real weapon, no real weapon draws no cover | B | third-party RE of the official client for the type selection; the fallback is ours (C) |
| Cash replaces regular equipment | a worn cash item draws instead of the regular equip of its slot, and also of any regular equip whose whole `info/vslot` it holds (a MaPn vest replaces the pants, an overall both) | C | v83 shows the cash item in place of the regular one; the vslot-subset rule is ours |
| vslot hiding | a layer is hidden when one other drawn item's `info/vslot` codes cover every code of the layer's `Base.wz/smap.img` entry (hat CpH1H5 hides hairOverHead, a full-head hat the head, hair and accessories); face accessories follow the face expression; hats, eye accessories and earrings use their `default` frame for stances they lack | C | codes are tier A (smap.img, `info/vslot`); the all-codes-of-one-item reading is ours (any-code or pooled readings hide the sleeves, pants and shoes wrongly) |
| VAC | survivor-only pet upgrade, id 9990000 (reserved), placeholder price 20,000 NX, needs Wing Boots + Binocular and a pet: every drop on the map that is outside the player's magnet radius flies to the pet at the drop magnet's speed and acceleration (#119); with the Magnet card removed (#225) VAC and Binocular are the only pickup-range upgrades | C | spec #34, ADR 0003; our design |
| Pet in the round (#119) | `PetSystem`, only with an owned pet out (`character.pet` + `account.owned`); none otherwise and the round is byte-identical to before. Moves with the player's own physics (a second `PlayerMotion`) driven by a follow controller: walks toward the player (stops within `follow_gap` 40 px, walks at 1.1x the player's speed), hops up when the player's feet are 20-70 px above and within 80 px sideways, drops through the floor when the player is 20+ px below and within 60 px, jumps after 0.3 s pressed against a wall, hangs on the player's rope (action `hang`) while the player climbs. Teleports to the player when farther than 600 px, or farther than 280 px for 3 s (`pet_teleported` event). A pet brought out (round start, the Pet page, the Free Market) stands `beside_offset` 30 px behind the way the player faces, else in front, on the same flat floor, else on the player (#126: on the player it was hidden behind or over the avatar while the player stood still; a teleport still lands on the player and the pet walks off) Three more constants live in the same `pet` block rather than in code: `speed_stat_floor` 100 (the pet's speed stat is the player's but never below the 100 % base), `stuck_move_px` 0.2 (it counts as pushing against a wall when it moved less than this in a tick) and `floor_tolerance` 2 px (a floor within this of the player's feet is the same floor, for standing beside). `cash_items.json` `pet` is the only place the numbers live; `PetSystem` has no defaults. The pet upgrade item ids in `PetSystem` are tier A (1812002-1812005 are v83 items) except VAC 9990000 (tier C, survivor-only). A drop flying to the pet when it is dismissed falls and lands as an ordinary drop. State for drawing and telemetry: `RunWorld.pet_state()` = {species, pos (feet), facing, action stand/move/jump/hang, fetching, abilities} | C | ours; the numbers are in `cash_items.json` `pet` |
| Pet pickup (#119) | the base pet (Item Pouch and Meso Magnet included) collects every drop kind (EXP, mesos, equipment) within `pickup_radius` 60 px of its centre (15 px above its feet), on top of the player's magnet; Binocular x2 (120 px). What it collects is credited exactly as the player's, and `pickup_collected.collector` is `pet`. Wing Boots: it runs (1.5x) to the nearest resting drop within 220 px sideways and 80 px vertically of the player, walks to within 6 px of it, gives up after 2.5 s on one drop (then 2 s without fetching), and comes back | C | ours; v83 `PetEquip` flags (`pickupItem`, `pickupMeso`, `sweepForDrop`, `longRange`) are the idea only |
| Pet auto potions (#119, #237) | Auto HP Potion Pouch: strictly below the HP ALERT fraction (0 disables; round setup `alert`), drink the current potion when its shared cooldown is ready; pet and player start the same timer, with no additional pet delay. Counted in `potions.pet_used`, record `pet.potions_used` and `pet_potion_used`, separately from player `potions_used`/`potion_used`. The bot's waste guard is unchanged | C | Owner 2026-10-21, spec #237; ALERT sliders are v83 Options |
| Pet drawing (#120) | `PetRenderer` draws `RunWorld.pet_state()` (and the Free Market's `FreeMarketMotion.pet_state()`, the same `PetSystem` follower with no drops) from `Item.wz/Pet/<species>.img` (`stand0 stand1 move jump hang fly` and `info/icon`, `info/iconRaw` in the manifest; no `Pet.wz` in v83) at the real frame delays and origins; the art faces left so facing right mirrors; no name tag or chat balloon. Action to animation: stand -> `stand0`, move -> `move`, jump -> `jump`, hang -> `hang` (tier A: the WZ names); a pet running to a drop in the air (Wing Boots, `fetching` and `jump`) uses `fly`, and a hanging pet is drawn 22 px beside the climber instead of exactly behind (C: ours, the sim keeps it on the player's position). Drawn in the actor layer of the foothold it stands on, just behind the avatar when that is the avatar's layer. `stand1` is imported but not used | A (animations) / C (mapping, offset) | v83 `Item.wz/Pet`; ours |
| HP ALERT default (#121) | HP ALERT 30 % of max (`Settings` `[alert]` hp; an old `mp` key is ignored, #285; 0 = do not alert; 5 % steps on the Options slider). A persistent round takes it from the settings at launch and follows changes at once; tool rounds ignore the settings and take `--account`'s `alert` (default 0) | C | ours, low enough to be safe and on so a new pouch works at once; the v83 SysOpt rows are the slider style |
| Card tier magnitudes | rank +1/+2/+3/+5/+8; stacking +1/+2/+3/+4/+5; new skill 1/2/3/4/5; per-card overrides; Legendary clamps to ranks/steps left | C | spec #30, each tier above the last (owner 2026-10-15); upgrades.magnitudes; fixed Legendary gains and data-driven clamp: owner decision #173, 2026-10-18 |
| Card honesty / boss floor | highest fitting tier except configured clamped tiers (Legendary); a gain equal to a lower tier wears the lowest such label; boss promotes Normal to Rare and omits scalable cards unable to retain Rare; potion/Elixir always Normal | C | spec #30 / #43 / #173; headroom interpretation and exceptions in §8.1 |
| Tier text precision / telemetry | compounded percentages rounded to 0.01 for text; application full precision; offered/picked count each displayed card once; legacy records are unobserved | C | ours; choice_card, RunWorld counters, balance report |
| Tier reward presentation | white/blue/purple/gold/green accents `#FFFFFF/#77BBFF/#CC99FF/#FFCC44/#77DD88`, dark `#17344F` 16px label band tinted 30% with the tier colour and a 2px frame; rows start at 140px in blanked notice, 4px gaps, target view height minus 128px; prose compacts before changed values | C | #30 / #44; Potential ladder semantics on original v83 window art |
| High-tier offer cue | one `Sound.wz/Game.img/mCardGet` per displayed Unique/Legendary level-up or boss-reward window; prewarmed; no cue for invisible autopicks or focus/pick | A (v83 2664ms audio), C (reward use) | implementation selection after owner reserved EnchantSuccess for future scrolling; existing whole Game.img manifest; actual WASAPI playback verified by agent, fit auditioned and approved by owner on 2026-10-15 |
| Upgrade card values | `upgrades.json`: Recovery/Nimble Feet ranks 1–3 (the MP Recovery and MaxMP Increase cards removed, #285); Magnet ×1.25 removed in #225; old Max HP/flat-speed/flat-MP cards removed | C (card tuning); A (canonical levels) | ours; original WZ |
| Mastery passive | WZ `mastery` N gives (10 + 5N)% (the same encoding as magic masteries); the best owned Mastery of the held family replaces the 10% base; its `x` adds ACC | B | Cosmic and String.wz agree (v83-facts section 3); #161 |
| Crit passives | `crit_chance` = `prop` percent added to the crit chance; `crit_damage` = `damage` total percent, so a crit adds `damage - 100` points to the skill % instead of multiplying | B (additive rule), C (data shape) | SouthPerry Critical Shot/Throw (v83-facts section 5); #161 |
| Improved MaxHP per level-up | `max_hp_per_level` adds the skill's `x` HP at each level-up after learning, never retroactively; persists through `base_hp` | B | v83 Cosmic level-up HP rule (v83-facts section 3); #161 |
| Final Attack proc | canonical `prop`% chance after a damaging physical line of a matching family, follow-up at canonical `damage`% on the same mob, RNG stream 12, played at the end of the tick, none on a killed target or after a follow-up | A (prop, damage), C (per-line roll, timing, stream, no chains) | v83 Skill.wz; #161 |
| Attack speed table (#160) | speed step 2..9 (lower is faster) takes 800 x (10 + step) / 16 ms (600..950); normal step 6 = 800 ms; the swing interval is that rounded up to 30 ms (`WeaponInfo.SPEED_DELAY_MS`, `attack_interval`) | B | v83 weapon-speed words and delays, emulator RE; same formula as before #160 |
| Booster steps (#160) | buff effect `attack_speed` = steps faster (v83 Boosters: 2), clamped to speed 2..9; counted only while the skill's weapon family is held; skill cooldowns/action times and basic-attack impact/stance scale by the table ratio to the weapon's own step | A (+2 steps, duration: Skill.wz), C (relative-to-own-step scaling, skill cooldown scaling, gating) | v83-facts section 3; ours |
| Buff `scale` | a buff effect entry may multiply its canonical number (the Boosters' negative speed steps use `-1`; Rage's WZ pdd is already negative and takes none) | C | data shape; #161 |
| Warrior advancement (#163) | job 100 at Lv 10, +225 Max HP (`jobs.json` grants), growth 26 HP / 5 MP per level, all earned AP into STR | B (HP grant midpoint of +200-250 and the growth midpoints: Cosmic changeJob / levelUp); C (Lv 10, no DEX row) | v83-facts 4; owner choice (spec #151) |
| Warrior weapon grants (#226 amendment) | Choose Sword 1302077, Spear 1432000 or Steel Pipe 1322006; only chosen item is worn; displaced equipment to Equip or feet | B (sword gift), A (item stats), C (spear/pipe choices, chosen-only rule) | v83-facts 4; owner #226 2026-10-18 |
| Warrior melee families (#163) | Power Strike and Slash Blast need sword, axe, blunt, spear or polearm (`skills/warrior.json` `weapon_families`) | C | the WZ nodes name no weapon; String text says "sword"; v83-facts 2 |
| Weapon-reach and range-around casts (#163) | `weapon_reach`: nearest mob inside `BasicAttack.envelope` (the union of the held weapon's afterimage boxes, far edge = `reach`); `range_around`: body centres within the level's canonical `range` of the body, `mobCount` cap | A (afterimage boxes, `range`, `mobCount`); C (the rules, auto-cast) | Skill.wz 100.img; ours |
| Skill stance `"action": "weapon"` (#163) | the held weapon's first basic-attack action (`WeaponInfo.skill_action`), so a spear stabs and a polearm swings | C | the Warrior nodes have no `action` |
| Power Strike / Slash Blast pacing (#163) | cooldowns 1.0 s / 1.6 s, 0.6 s cast stance | C | ours, untuned until the balance pass |
| HP cost (#163) | Slash Blast pays canonical `hpCon`; never cast when HP would not stay above 0, then nothing is paid | A (hpCon); C (the refusal rule) | Skill.wz; ours |
| Improved HP Recovery (#163) | adds canonical `hp` (3-50) to every regeneration pulse, always (not only standing still) | A (hp); C (always) | Skill.wz; String text says "while standing still" |
| Iron Body (#163) | auto-cast buff, recast on expiry, canonical pdd/time/mpCon, 0.8 s stance | A (values); C (auto-cast) | Skill.wz |
| Warrior cards (#163) | learn/rank cards for all five; Cleaving Strike +1 target x3, Crushing Strike x1.2 damage x3, Quick Strike -12 % x3, Whirling Blast +2 targets x3, Wider Blast range x1.2 x3, Quick Blast -12 % x3; weights 1-4 | C | ours, untuned |
| Warrior bot fixture (#163) | `lv11_warrior_1st.json`: forced job 100, seed 1, stopped at 295 s | C | `tools/character_fixture.gd --job=100 --seconds=295 --label=spec151/owner-warrior` |
| Pirate second-job fixtures (#195) | `lv37_brawler_2nd.json` (510 knuckle, seed 1, 480 s cap, `--god --exp-mult=3`) and `lv36_gunslinger_2nd.json` (520 gun, seed 1, 780 s cap, `--god`); the aids are diagnostic and recorded in each `_doc` | C | `tools/character_fixture.gd --label=spec168/ticket-195` (GAME_DESIGN 4.2) |
| Thief QA fixtures and evidence (#215) | Seed1 bot, Henesys, job410:claw / 420:dagger, `--god --exp-mult=3 --seconds=600`; combat probe seed215, fixed1/60 ticks, rank10 attacks, stationary mobs at 45/180px with HP multiplier10000; flow uses invulnerable EXP drops and a diagnostic Free Market boundary | C | `character_fixture.gd`, `thief_combat_driver.gd`, `flow_driver.gd`; aids only, no balance data changes (4.2) |
| Second-job weapon skill families (#181) | each of the 18 Masteries, Boosters and Final Attacks lists its one family in `weapon_families` (sword, axe, blunt, spear, polearm; sword/axe/blunt cover one- and two-handed) | C | the Skill.wz nodes have no `weapon` field; String text and v83-facts 3 |
| Second-job Mastery (#181) | `mastery` step 1..10 (15-60%, levels 1 and 2 both 15%) and ACC `x` 1..20, only while the family is held | A (numbers), B (the (10 + 5N)% encoding) | Skill.wz 110/120/130; v83-facts 3 |
| Second-job Booster (#181) | WZ `x` -2 read with `scale: -1` as +2 speed steps; `hpCon` = `mpCon` 29 down to 10, `time` 10 s per level (10-200 s); auto-cast, recast on expiry, 0.8 s stance | A (numbers), C (the sign convention, auto-cast, stance) | Skill.wz; ours |
| Second-job Final Attack (#181) | `prop` 2 x level percent, `damage` 100 + 5 x level percent, follow-up in the held weapon's attack stance for 0.6 s, no sound, `hit/0` art | A (prop, damage, art), C (stance and action time: the node has no action) | Skill.wz; ours |
| Spread (#181) | `skill_mod` `count` +1 per step, 3 steps: the follow-up also hits up to N other live monsters whose body centre is within `BasicAttack.reach` (a circle) of the struck target's, bosses first, then nearest to the target, then slot; no RNG | C | ours (owner decision 1 of spec #165) |
| Weapon-skill cards (#181) | learn weights Mastery 3 / Final Attack 4 / Booster 3, rank weights 2 / 3 / 2, Spread 2; Final Attack, Booster and Spread are `power`, Masteries are not | C | ours, untuned |
| Weapon-skill bot scores (#181) | `bot.card_scores`: learn 100, rank 74 for the 18 skills (attack-card values); Spread scores through `SCORE_MOD.count` | C | ours, untuned |
| Iron Will (#184) | auto-cast self buff, recast on expiry; canonical pdd and mdd (1-20), time (15-300 s), mpCon, 0.8 s stance; the WZ party effect is self only | A (values); C (auto-cast, self only) | Skill.wz 130.img |
| Hyper Body (#184) | auto-cast self buff, recast on expiry; Max HP +x % (2-60) of the whole maximum (base, growth, passives, equipment), time 10-300 s; current HP unchanged at cast, clamped to the normal maximum on expiry; a buff stat of its own (the Max MP `y` half removed, #285) | A (values); B (percent of the whole maximum, current HP unchanged at cast, clamp on expiry: v83 behaviour); C (auto-cast, self only) | Skill.wz 130.img; v83-facts 3 |
| Iron Will / Hyper Body cards and bot scores (#184) | learn weight 3, rank weight 2, Spearman only, not power; bot default scoring like Iron Body (no card_scores entries) | C | ours, untuned |
| Second-job Warrior fixtures (#185) | `lv34_fighter_2nd.json`, `lv34_page_2nd.json`, `lv34_spearman_2nd.json`: Henesys, seed 1, bot, forced 110 / 120 / 130, invulnerable, stopped at 600 s (Lv 34) | C | `tools/character_fixture.gd --job=<id> --god --seconds=600 --label=spec165/ticket-185`; `--god` (RunWorld.god) because a Warrior bot never reaches Lv 30 otherwise; `_doc.invulnerable` |
| Playtest evidence shots (#185) | `<final attack key>_followup.png` 0.12 s after its first follow-up, `reflect_first.png` 0.1 s after the first Power Guard reflect | C | presentation only, written only with a shots directory |
| Nimble Feet values and lifecycle | speed +10/15/20 for 4/8/12 s; cooldown 60 s from cast; auto-cast when inactive/ready, passive slot, no new cast while climbing | A (values), C (auto-cast/slot/lifecycle) | v83 Skill.wz/000.img/skill/0001002; owner casting rule |
| Recovery HoT | canonical levels 1–3 heal x=4/8/12, last 30 s, cooldown 120 s from cast; trigger below 50% HP, six 5 s pulses including the expiry tick | A (values); C (trigger/pulse interpretation) | v83 Skill.wz/000.img; survivor skill buff rules |
| Regeneration | 10 s pulses, always 10 HP; `balance.regen` (no MP, #285) | B (cadence); C (HP choice) | v83 recovery cadence; owner choice |
| Level-up HP / casting order | no level-up healing (`level_up_refill.hp` 0.0) or implicit HP gain from maximum growth; oldest-ready skill, one per tick (no MP cost or low-MP cue, #285) | C | owner choices; ours |
| EXP drop motion | pop 260 px/s up, ±40 px/s sideways, Physics.img gravity onto floors; magnet 220 px/s + 1400 px/s²; collected within 24 px of the body centre (25 px above the feet); at 600 drops the farthest from the player is absorbed into a fresh drop at the new kill | C | ours |
| EXP drop lifetime | never expires (`pickup.lifetime` 0); capped absorption resets the new drop's age and conserves EXP | C | owner decision 2026-10-14 |
| Player-platform spawns | 35% of ground placements, at least 150 px away; visible only when the whole platform fits in view, otherwise on off-screen portions; normal regen fade and harmlessness | C | owner choice, `balance.json.spawn` |
| Spawn rings | first the floors beside the view (within 160 px of its sides, `band`, and 48 px of its height, `band_y`), then within 480 px of the view, then the map within 1170 px of the player; 12 samples per ring, looking first for a point whose way to the player is at most half the view width + 48 + 160 px (`prefer_route`, 608 px on an 800 px view: no longer than the walk in from the ring's outer edge), then for any point that reaches the player, before an unreachable spot; never where a wall that crosses a platform stands anywhere on the way to the player (followed edge by edge onto the player's platform) | C | ours |
| Spawn trail margin | spawns stay 32 px further out (`trail_margin`) on the side a moving player (horizontal speed > 1 px/s) runs away from: the camera lags about 125 / 6 + 8 = 29 px behind a running player (smoothing 6/s, 8 px dead zone) | C | ours |
| Mob relocation | silent, never on screen (only from outside the view + 48 + 32 px on every side: the camera can lag either way) and never elites: a mob that has not come 1 px closer along its way while itself moving 1 px for 3 s (`stall_time`, `stall_progress`; a mob standing still on screen keeps counting and is moved once off screen), or that is farther than 1300 px or cannot reach the player 160 px off-screen for 3 s, is moved to a fresh spawn point, preferring the side the player is moving toward (its horizontal speed > 1 px/s), with its HP; only when no point is found is it recycled (removed) | C | ours |
| Bursts / elites | bursts may exceed max_alive up to `hard_cap` 400; first elite at 1:15 (Henesys 4:00), then every 60 s; first burst at 1:30 (Henesys 5:00), then every 90 s | C | ours; the Henesys delays keep them out of the sword-paced Beginner phase |
| Henesys stage EXP | 2.5x canonical mob EXP for ordinary kills (`stages.henesys_hg1.exp_mult`) | C | coarse #29 pass so a sword-paced Beginner reaches Magician near 4:40 |
| Job window | at every queued level while an option is available; once at the tier's first level when none is | C | ours |
| Job window pages (#226, #231) | page 1: generic intro, one entry per job, no portrait when the options span several lines; weapon page for jobs with 2+ families, spoken by the chosen job's instructor; Cancel (Esc, Prev) returns to page 1 | C | ours; `job_advance_window.gd` |
| Magician advancement level | survivor level 10; canonical level 8 and INT 20 stay unchanged | C | owner choice, #40; `data/survivor/jobs.json` |
| Background auto-scroll axis | types 4-7: no camera term on the scrolling axis (screen x = x + rx·5·t + W/2), parallax on the other | C | ours (reading of "auto-scroll X, parallax Y") |
| Negative frame delay | used by magnitude (`magic1/0` = -900 ms) | C | ours |
| a0/a1 with one key | the other is 255 minus it | C | HeavenClient |
| Damage number stacking | same mob within 0.5 s goes one line up: 30 px above a normal number, 36 px above a critical one (8 lines, then wraps) | C | HeavenClient row heights 30/36; window and wrap ours |
| Boss target priority (#83) | every targeting rule (nearest, box, crowd, Heal undead, basic attack) orders qualifying targets scheduled boss first, then distance, then slot; elites get no priority | C | ours; spec #79 owner decision (`RunWorld.targets_before`) |
| Skill box admission / area scoring | minimum 1 target unless `cast.min_targets` overrides; base area 1.0, future area-card multiplier ×1.2; bot `area` score 58 plus existing job bonus | C | spec #31 binding foundations decisions; no skill/card entries added |
| Holy Arrow flight / cards (#57) | 1 s recast, 480 px range, 520 px/s, 12 px radius, count 1, pierce 0, 0.8 s stance; count +1 ×3, pierce +1 ×2, cooldown ×0.88 ×3; learn/rank weights 4/3, modifiers 2; standard attack bot scores | C (tuning), A (skill fields/art/sound/action) | copied existing Fire Arrow/first-job survivor steps; [Cleric evidence](research/cleric-heal.md) |
| Heal trigger / recast / targets (#57) | strictly below half HP OR one boxed undead; 2 s recast in heal block; 0.8 s stance; every boxed undead once, overriding canonical mobCount=6; target multiplier counts undead plus caster | C (trigger/delay/cap override), A (box/cost/hp/action/art/sound) | ticket #57; [Cleric evidence](research/cleric-heal.md) |
| Heal undead formula (#57) | bounds `(0.3×INT+LUK)` / `(1.2×INT+LUK)` × `(INT+matk)/1000` × `hp/100` × `(1.5+5/N)`; holy h; existing hit/defense/element path | B (pre-BB client RE, not directly v83) | Southperry #1033 posts 685–692; [derivation and worked example](research/cleric-heal.md) |
| Heal recovery approximation (#57; unresolved verification) | historical LUK polynomial × `(INT+matk)` × INT × `hp/10`, lower bound ×0.8; single-target multiplier 1, uniform seeded roll truncated to HP, capped by restore_player; learn/rank weights 4/3 | B weak (historical coefficients); C (selecting this unverified fit, multiplier, RNG/rounding, weights) | [evidence gap and original observations](research/cleric-heal.md); exact v83 recovery acceptance criterion remains open |
| Fire/Poison attacks (#55) | Fire Arrow: cooldown 1 s, range 480 px, speed 520 px/s, count 1, pierce 0, radius 12 px, stance 0.8 s, rotates; Poison Breath: 1.25 s, 450 px, 400 px/s, count 1, pierce 0, radius 14 px, stance 0.8 s, no rotation; both target nearest | C | survivor skills.fire_arrow / poison_breath; untuned; canonical elements, level numbers, actions and assets remain tier A |
| Fire/Poison cards (#55) | Fire Arrow +1 shot ×3, +1 pierce ×2, cooldown ×0.88 ×3; Poison Breath +1 pierce ×3, cooldown ×0.88 ×3; weights learn/rank/mod 4/3/2; exact job 210, all power; existing bot scores learn 100, rank 62, count 75, pierce 58, cooldown 54 plus 12 job bonus on rank/mod | C | issue #55 / owner #31; first-job modifier steps and score defaults; no rarity overrides or tuning |
| Second-job support values and casts | Meditation mad/time/mpCon; Bless pdd/mdd/acc/eva/time/mpCon; Invincible x/time/mpCon; Slow signed x/time/mobCount/lt/rb; alert2, effect, Use sounds, 20 levels each | A | original v83 Skill.wz/210.img, 220.img, 230.img; cache checked at levels 1/20 |
| Support auto-casts / hit integration | self only, one snapshot timer/icon; 0.8 s stance; Meditation invalidates caster stats, Bless live avoid/defence and ACC (crit chance, #153); Invincible whole physical hit ×(1−x/100), nearest rounding/minimum 1 before Guard | C lifecycle/arithmetic, A effects | #58; section 7; existing timed-buff rules |
| Slow crowd / consecutive uses | at least 3 eligible unslowed mobs, 1 s cooldown; 2 consecutive successful Slow casts per logical mob, reset by a successful cast excluding it; preserve across relocation, reset on fresh spawn | A text, C interpretation/trigger/cooldown | original String.wz/Skill.img Slow description; #58; survivor cast data and section 7 |
| Support cards / bot | learn/rank only, weights 3/2; learn 50, rank 42 + job bonus 12 (including Slow); below attacks | C | #58 survivor cards; existing support score defaults |
| Restoration gain digits | HP NoBlue1/0; absent Blue falls back to Violet (tint 0.55,1,0.55) | A (cached digit art), C (selection/tints/fallback) | original v83 BasicEff cache; HP-use inference remains unverified (prior-art.md); existing number timing/stacking reused |
| Critical burst | `NoCri1/effect` behind the first digit (origin on the digit's anchor) from 250 ms; the v95 "y-30" and "+30 px leading space" are not applied (the prose leaves their axis/reference open) | B/C | v95 RE timing; placement ours |
| Face blink | `blink` every 2-5 s (seeded) | C | ours |
| Tombstone drop | `Tomb.img/fall` from 300 px above over its own duration (ease-in), then `land`, stays | C | ours |
| Pickup drawing | iconRaw centred on x, bottom on the drop point; bob 2 px over 1.2 s | C | ours |
| BGM fade / volumes | 0.8 s cross-fade; defaults master 1.0, BGM 0.8, SFX 0.9; 16 SFX voices (oldest stolen) | C | ours |
| HUD layout | gauge at (216, 37) of the 800×71 bar, fills measured from `gauge/bar`; button/key positions and top timer/kills/skills layout | A (measured art) / C (buttons, top HUD) | ours |
| Reserved HUD areas | buffs 212×44 at (view width −224, 42); boss bars 300 px wide centred at y=42 with 42 px row pitch (37 px canonical icon frame) | C (layout), A (art size) | ours, difficulty overhaul |
| Starter equipment selection | Coat 1040002, Pants 1060002, Shoes 1072001; Sword 1302000 and Wooden Wand 1372005 loaded for job weapon selection | C (selection), A (info) | existing avatar look and v83 Character.wz |
| Elite name tag | mob name (String.wz) in the white 12 px system font on a black 60% box, 3 px padding, 15 px high, 2 px below the feet; hidden while dying | C | ours (v83 draws the default tag in code; `UI.wz/NameTag.img` holds only cash styles 3-28) |
| System messages | "+N EXP" in yellow (#FFFF00) with a black outline above the left end of the status bar, newest at the bottom; 4 s each (last 0.5 s fading), at most 6 lines | C | ours |
| Boss notices / respawn effect | keyed yellow notices above EXP; warning lead / 4 s lifetime; BasicEff/Summoned at boss feet | C (selection/layout), A (art/timing) | ours; original v83 WZ |
| Missing boss UI metadata | Blue Mushmom uses Mushmom icon and 1/5 colour tags; King Slime uses 1/5 tags with its own icon | C (override), A (borrowed art) | survivor mobs.json.boss_ui |
| Mob draw layer | the foothold layer of the mob's current foothold, kept while it is airborne | C | ours |
| View fit | default: Godot's 800×600 expand + integer scale (1920×1080 → 1066×600 at 1× with bars); opt-in `fill_window`: s = ⌊min(W/800, H/600)⌋, view = window / s (3440×1440 → 1720×720 at 2×, 1920×1080 → 1920×1080 at 1×); windows below 800×600 are scaled down, not cropped | C | ours |
| Level-up window delay | the `LevelUp` effect plays 1.2 s (about its pillar's peak) on the character before the upgrade window opens; after a job advancement the next window waits for the whole `JobChanged` effect (~1.3 s; 1.3 s without the animation). Presentation only; the sim is already paused | C | ours |
| Frame cap | vsync on, `Engine.max_fps` = the display's refresh rate rounded up (144 when unknown, at least 30) | C | ours |
| Run end holds | results 2 s after the tombstone has landed; on a clear the party-quest `CLEAR` field effect (`Map.wz/Effect.img/quest/party/clear`, `Sound.wz/Field.img/Party1/Clear`) at the screen centre for 3.5 s | C | ours (art/sound A) |
| Map transfer presentation (#246) | Reuse the cached party-quest CLEAR effect/sound for intermediate clears: 3 s hold, 0.4 s fade out, one black frame, advance/reload, 0.4 s fade in; arrival street/map name uses the existing 3.5 s title style. Plain "Map cleared!" fallback when the effect is absent | C (reuse, timing, text), A (art/sound) | `Map.wz/Effect.img/quest/party/clear`: five original frames, delays 100/100/100/100/2000 ms, confirmed in caches/s241; no manifest addition |
| Windows during map transfer (#246) | Pause and in-run windows hold the notice/fade clock; Resume continues the same phase, including at full black. Combat stays frozen until fade-in finishes; sweep/choice windows retain their existing behavior | C | Presentation policy, no change to RunWorld's deterministic transfer boundary or round-boundary saves |
| Invincibility blink, hit face | the whole character (one CanvasGroup) alternates alpha 1.0 / 0.4 every 0.08 s while invincible; face `hit` for 1 s after a hit | C | ours |
| Drop draw order | EXP drops are drawn after the mobs and the character of the character's foothold layer (never hidden in a crowd) | C | ours |
| Run start title | continent (small) above the region (`stages.json`, #221) under the timer for 3.5 s, the last 1 s fading | C | ours |
| Sound throttle | each sound path plays at most once per frame (a piercing shell through 20 mobs is one Damage sound) | C | ours |
| Character name tag | the character name under the feet in the elite name-tag style | C | ours |
| UI windows (level-up, job, pause) | open: 0.15 s fade-in while dropping 10 px; close: 0.12 s fade-out; keys ignored for 0.2 s after opening; the job dialog's confirmation line stays 1.8 s (any key/click skips) before `job_chosen` | C | ours (art A: UI.wz SkillUp, Skill rows, UtilDlgEx, Basic.img YesNo3) |
| In-run windows (#85) | stacked above the modal windows (CanvasLayer 11); 20 px title strip drags; 40 px of a window always stay in the view; first open centred above the status bar, then reopened where it was dragged; sim held while any is open | C | ours |
| Stat window layout (#85) | detail panel (`Stat/backgrnd2`) on the main panel's right edge with bottoms aligned, (175, 144); value text 61 px (main) / 80 px (detail) into the fields; BtDetail (120, 324) and BtUIClose (10, 325) in the bottom strip; attack = held weapon `incPAD`, magic = INT + magic attack, accuracy = buff accuracy only, speed/jump as v83 percentages, AP 0 | C (layout, stat mapping), A (art) | ours; `UIWindow.img/Stat` |
| Quick slot position and collapse button (#220) | the 151 × 80 `base/quickSlot` panel at (649, −76) of the 800 px bar (flush with its right end, 76 px above its top, overlapping the bar by 4 px); `QuickSlotD` (shown) / `QuickSlot` (folded) button at (765, 8); state in `[hud] quick_slot_collapsed` | C (position derived from a third-party v83-era fan client that places the panel at (875, 622) on a 1024 × 768 screen whose bar is at y 698 and the button at x 765, y 8 of the bar, right-aligned to 800 px; not verified against the official client), A (art) | ours; Elem8100 GM client layout (facts only) |
| Menu button and popup (#85) | `StatusBar.img/BtMenu` at (744, 36) of the 800 px bar (moved down from y 20 by #220 so the quick slot's collapse button sits above it; v83 keeps Menu on the bar's lower half), popup in the `UIWindow.img/ContextMenu` style (`t`, a `c` row per entry, `s`; entries on BtInfo plates widened past the dot, our labels) right-aligned above the button | C (layout), A (art) | ours (the cache has no art for v83's Menu list) |
| Skill window layout (#86) | tab cells 27x17 from (8, 24), 28 px apart, the selected one a white plate; skill book icon at (9, 53), book name at (47, 64); rows (`skill1` learned, `skill0` not) from (11, 95), 40 px apart, 4 shown, `Basic.img/VScr5` scrollbar at (155, 95); SP box shows 0; BtUIClose at (134, 266); the selected / hovered row gets an orange outline; no star tab (removed in #225); tooltip a drawn dark box 290 px wide (v83 `UIToolTip.img` is not imported) placed beside the cursor or the selected row and kept above the status bar | C (layout, tooltip), A (art) | ours; `UIWindow.img/Skill` |
| Movement keys (#85) | Arrows by default (v83), WASD as an option; the chosen set's keys are taken off every other action | A (Arrows) / C (WASD option) | v83 client defaults; ours |
| Key Config window (#87) | bindable: jump, HP potion (the MP potion action removed, #285), Stat, Skill, plus (#188) one skill key per learned manual skill at the end of the tray, with the skill's own icon (Teleport, Dash) (#108: Equip E and Item I too, with KeyConfig `icon/0` EQUIPMENT and `icon/1` ITEMS; E left the MP potion); fixed: the movement set, Esc, 1-3; a key holds one action, an action may sit on several keys; Default = project keys less the movement set (WASD leaves Stat without a key); key rects measured on `KeyConfig/backgrnd`, tray slots (8 + 34i, 267 + 34r); Tab / Scroll Lock / Win / Menu are no drop targets; Default, Delete left and OK, Cancel right in the strip at y 237, BtClose (611, 6); icons: KeyConfig `icon/53` JUMP, `icon/2` ABILITY (Stat), `icon/3` SKILL, Red Potion, the learned skill's icon | C (rules, layout), A (art, JUMP / ABILITY / SKILL icons) | ours; `UIWindow.img/KeyConfig` |
| Options window (#87) | `SysOpt/backgrnd` title, BGM and SOUND rows and bottom strip, two blank rows relabelled FRAME CAP and MOVE KEYS; slider track x 93-209 between the baked SOFT / LOUD; MUTE box (243, 9) restores the volume it had (else the default); frame caps: screen refresh, 60, 144, off | C (layout, choices), A (art) | ours; `UIWindow.img/SysOpt`, `Basic.img/Slider`, `Basic.img/CheckBox` |
| UI text colours | NPC dialog black text, options #0000FF (#b), unavailable grey #888888, system yellow #FFFF00; Arial/Tahoma/Dotum at 11-12 px, antialiasing per `MapleFonts.ANTIALIASED` (#224) | C | ours, matched to v83 screenshots |
| Sharp text (#224, 2026-10-18) | the window draws canvas items at its own pixels (`window/stretch/mode="canvas_items"`, integer scale, nearest, 2D snapping kept); glyphs rasterised at window pixels, metrics in logical px unchanged; `MapleFonts.ANTIALIASED = false` (crisp hinted, no AA, closest to v83; the owner chose crisp from the A/B screenshots, PR #235, 2026-10-19); 1 px outlines drawn as the 800x600 render lit them (`PixelDraw.outline`: top row above, left column outside, right/bottom inside) and downscaled HUD skill icons copy the texels it picked (`PixelDraw.blit_scaled`, texel floor((i + 0.5) * src / dst)) | C (AA choice: owner) / A (outline and texel footprints measured on GL compatibility) | ours; docs/ARCHITECTURE.md 4.5 "Fonts and sharp text" |
| Tab strip geometry (#219) | `TabStrip` cuts a row at n + 1 x bounds over 19-row shapes: Item `TAB_BOUNDS` 4 / 37 / 71 / 104 / 137 / 171 at y 23 (five equal 33-34 px tabs over the baked pill); Shop sell `TAB_BOUNDS` 235 / 279 / 324 / 368 / 412 / 457 and `BUY_TAB_BOUNDS` 5 / 41 at `TAB_TOP` 97, `TAB_H` 19; Skill tabs 28 px wide from (8, 23); Equip `TAB_BOUNDS` 42 / 74 / 103 at `TAB_TOP` −24 from the art's bottom, `TAB_H` 19 (Tab3 grey base; Item, Skill and Shop use Tab5's red base); glyphs centred in each tab (no-cache text too); `TabStrip.FALLBACK_SHOWN` (236, 112, 144) fills the shown tab without the cache | C (bounds measured on the v83 backgrounds; the Item tab width matches the 34 px `Item/New/Tab0` sprites), A (shapes: `Basic.img/Tab3`, `Tab5`) | ours |
| Stage region and continent (#221) | `stages.json` `region` / `continent` per stage: henesys Henesys / Victoria Island, ellinia Ellinia / Victoria Island, sleepywood Sleepywood / Victoria Island; a summary without them falls back to the stage's old `name` and the map and street name it was saved with (`DataRepo.stage_labels`, `summary_stage_lines`) | C | owner choice (playtest 3); not WZ strings |
| Quick slot captions (#220) | key captions at size 9 (`CAPTION_SIZE`), white (`CAPTION_COLOR` 255, 255, 255) with a dark blue-grey outline (`CAPTION_OUTLINE` 40, 59, 76), shortened with ".." beyond `CAPTION_MAX_W` 29 px (a cell's interior) | C | ours, matched to v83 screenshots |
| "Equipped <name>" notice (#222) | `HudMessages` pushes "Equipped <item name>" ("Equipped an item" when the name is empty) as a system line in the usual yellow | C | ours |
| Web profile UI (#134) | title: Fullscreen / Export save / Import save lead the second button row (before Re-import WZ data) where desktop has Quit; Options: a FULLSCREEN check box in the FRAME CAP row; F11 and F12 not bindable on web (browser fullscreen / developer tools), Ctrl+W/T/N noted in the Key Config strip; text in the bundled Arimo (Arial metrics) because browsers have no system fonts | C | ours; docs/ARCHITECTURE.md 10 "Web profile" |
| Skill and card text | v83 String.wz `desc`/`hN` (A); survivor `skills.json` `text` overrides, the dropped Master Level / Required Skill lines, mod-card value labels and the rewritten card texts (C) | A / C | §8.2; SkillText (dress for level-up cards), LevelUpWindow |
| Best result per stage | a clear beats a death, then longer survival, then higher level, more kills, more damage (`user://save.json`) | C | ours |
| NX award per round (#115, spec #34) | a clear pays `clear_bonus[tier] + per_level x levels gained in the round + per_boss x scheduled bosses killed in the round`; a death pays the same without the clear bonus (bosses killed before dying count); the final tier's clear pays its normal clear award; deletion, Quit round and tool/one-off rounds pay nothing. Placeholders in `balance.json` `nx_award`: `clear_bonus` [100, 250] by 0-based tier (later tiers reuse the last), `per_level` 5, `per_boss` 40. The balance pass sets the numbers | C | ours; owner #34 triage (ADR 0003) |
| NX crediting and account block (#115) | the award is added to `account.nx` inside the same atomic write as the clear's round-boundary snapshot (so it is spendable in the Free Market at once) or the death/victory run archive; an optional top-level save key `account: {nx, owned}` (absent = 0 NX, nothing owned), `SaveData.FORMAT` stays 2; tool rounds record `nx_awarded` / `bosses_killed` / `levels_gained` and never write a save | C | ours; seams.md (no format bump) |
| NX display (#115) | results screen row "NX earned: +N NX" (persistent endings only); Free Market arrival notice "You have gained N NX." for 6 s under the instruction line; map select heading ends with the account balance | C | ours |
| Cash Shop screen (#118, spec #34) | `scenes/ui/cash_shop.gd`: the v83 `UI.wz/CashShop.img` screen, 800x600 centred, EQUIP. (Hat, Face, Eye, Overall, Top, Bottom, Shoes, Glove, Weapon, Cape) and PET (Pet, Pet Equip.) tabs, ten cards per page. Items are filed by Commodity SN (`CashShop.listing`: category 2 equipment, 6 pets; earrings under Face and shields under Weapon as in v83; VAC, which has no SN, last under Pet Equip.). Card art positions and the buy dialog are WZ/capture-measured (tier A/B, `CashShop` constants); other tabs, GIFT/RESERVE, Search Item, Best Item contents, Charge/Check Cash/Code, the family tabs and ON toggle, the Item Inventory tabs and slot buttons are not drawn (out of scope). Click = try on (`CashShop.try_on`), BUY = confirm dialog (NX CREDIT line checked, the only currency) then `CashShop.buy`, which deducts, adds, saves in one write and removes the item from the list; locked cards show "Needs a pet." / "Needs Wing Boots, Binocular and a pet." instead of BUY; too little NX shows the notice "You don't have enough NX."; BUY EQUIPPED ITEM is disabled (one purchase per card), RETURN TO DEFAULT / REMOVE ALL reset / strip the preview; the Cash Inventory lists owned items read-only. SHOP buttons: map select (every tier, the v83 `StatusBar.img/BtShop` beside Save & quit, centred on its plank) and the Free Market status bar (`StatusBar.img/BtShop` at bar +(688, 20)); Leave = EXIT or Esc, back to where it was opened | A for art and prices; B/C for positions, wording, SHOP button placement | cashshop-refs/layout.md (private), v83 WZ; owner rule: match the real client layout |
| Equip window layout (#108) | `UIWindow.img/Equip/backgrnd` 175x304; 32 px slot cells hat (38, 35), top / overall (38, 134), bottom (38, 167), shoes (71, 200), gloves (5, 167), weapon (104, 134); BtUIClose at (10, 281); opens left of the view's centre, the Item window right of it | C (measured on the v83 art; the cells cross-checked B against JourneyClient's slot offsets), A (art) | ours; `UIWindow.img/Equip` |
| Equip window Cash tab and Pet page (#122, spec #34) | the Equip window gains pages (`EquipWindow.set_page`): Equip (unchanged), Cash and Pet. v83's `UIWindow.img/Equip` has no Cash tab art, so the Cash page re-uses the `backgrnd` grid with the 11 cash slots in the cells their baked labels name (hat CAP (38, 35), face FOREHEAD (38, 68), eye EYE ACC (71, 101), earrings EAR ACC (104, 101), top CLOTHES (38, 134), bottom PANTS (38, 167), shoes (71, 200), gloves (5, 167), cape MANTLE (5, 134), weapon (104, 134), shield (137, 134)); an overall shows in CLOTHES and dimmed in PANTS, a two-handed cover in WEAPON and dimmed in SHIELD. The page switch is the Equip / Cash glyphs of `Item/Tab` at (46, strip) / (76, strip) and the v83 `Equip/BtPetEquipShow` ("PET EQUIP.") button at (104, strip), in the art's bottom strip. The Pet page is `Equip/pet` (177x181): owned upgrades sit read-only in HP POC (1812002), MP POC (1812003), ITEM POC (1812001, base pet), MESO MAG (1812000, base pet), POS (Binocular 1812005), PET EQUIP (VAC 9990000) and MOVE UP (Wing Boots 1812004), the character's own HP / MP potion shows in PET HP / PET MP when the matching pouch is owned. A drawn panel (152 px wide, 4 columns of 36 px, wheel or arrows page it) beside the page lists the account's owned cash equipment (slot order) or pets; a double-click wears / takes off / brings out / puts away. `RunWorld.wear_cash` / `take_off_cash` / `set_pet` apply it (`CashCatalog.wear`: an overall clears top and bottom, wearing a top or bottom takes it off, a two-handed cover takes weapon and shield); the world's Fortune follows at once, so the next card draw uses it. Persistent rounds now receive the saved account (`SceneFlow._resume_round` sets `options.account`), so the owned list and worn items count in a round | C (the page layout, the panel, the upgrade-to-label mapping and the glyph tabs are ours; the art and cells are A / measured on the v83 images) | ours; `UIWindow.img/Equip`, `UIWindow.img/Item/Tab` |
| Item window layout (#108) | `UIWindow.img/Item/backgrnd` 175x289; tab glyphs (`Tab/enabled` shown, `Tab/disabled` the rest) centred in the five tabs of the 19 px strip at y 23 (see Tab strip geometry); slots 4 x 6 from (8, 50), 36 px apart horizontally and 34 vertically; stack counts in `Basic.img/ItemNo` digits at the slot's (1, 21); mesos right-aligned in the field (25, 267, 113x14) beside the baked MESOS; `BtCoin` shown disabled (mesos are never dropped) | C (measured on the v83 art), A (art) | ours; `UIWindow.img/Item` |
| Inventory mouse protocol (#108) | a double-click wears / takes off; a press that moves 4 px starts a drag drawn under the cursor; the release resolves against the window stack (another inventory window takes the drop, no window = discard after the YesNo box, anything else nothing); a drop anywhere on the Equip window wears the item in its own slot | C (ours; v83 drags onto the exact slot) | ours |
| Item tooltip (#108) | drawn dark box 262 px wide (v83 UI.wz has no UIToolTip.img); `ToolTip/Equip/Can` / `Cannot` label and digit art for REQ LEV / STR / DEX / INT / LUK (three digits, 6 px cells) and the job words; `Property` labels 3 CATEGORY, 4 ATTACK SPEED, 6-11 and 13-14 the attack / defence / accuracy / avoid / speed / jump lines, 16 NUMBER OF UPGRADES AVAILABLE; `ItemCategory` 1 HAT, 5 TOP, 6 BOTTOM, 7 SHOES, 8 GLOVE, 21 LONGCOAT; `WeaponCategory` by item id / 10000 - 100; `Speed` 0-6 FASTEST..SLOWEST from attackSpeed 2, 3, 4-5, 6, 7, 8, 9; STR / DEX / INT / LUK / MaxHP / MaxMP as text; "(+N)" after the name for N successful scrolls | A (art, read), B (speed words, scroll count: RE clients), C (layout, mapping) | ours; `UIWindow.img/ToolTip` |
| Inventory messages (#108) | "You do not meet the requirements to equip this item." / "Your inventory is full. Make room before taking an item off." as HUD notices; the YesNo box asks "Are you sure you want to drop this item?" | C (the v83 client's wording is unverified) | ours |
| Cap hair cover (#108, corrected in #126) | `hairOverHead` is `Base.wz/smap.img` code H1, so it is hidden exactly by a cap whose `info/vslot` holds H1 (CpH1H5 half-cover, the full-head covers); a CpH5 headband (68 real caps) leaves it drawn over the band (the bangs fall over the headband: `zmap` puts `hairOverHead` in front of `cap`). Without a cap the `*BelowCap` hair layers are not drawn. #108 had it the other way round (CpH5 hid hairOverHead); `AvatarRenderer.hair_layers_skipped` and the smap hiding above now agree. Evidence: `hair_cap_probe.tscn` sheets on hairs 30000 / 30002 / 30020 with the CpH5 caps 1002067 and 1002317 and the CpH1H5 cap 1002001 (the old rule strips the bangs and leaves the headband on a bare forehead); the ladder stances show no difference (the hair covers the cap from behind) | A (smap codes, cap vslot, zmap order) / B (agreement) | `Base.wz/smap.img` + `zmap.img`, `Character.wz/Cap/*/info/vslot`; the v83 clients in the prior-art clones map CpH1H5 to half-cover (overhead hair not drawn) and CpH5 to headband (overhead hair drawn over the cap), re-implemented from prose |
| Scroll rules (#110) | a scroll fits when `(scroll id / 100) % 100 == (item id / 10000) % 100` and the worn item has an upgrade slot; roll 0-99 below `info/success` adds the scroll's `inc*`, counts one scroll; every use spends one slot and the scroll; a failed scroll with `info/cursed` destroys the item at a 0-99 roll below it; only worn items can be scrolled, never inventory items | A (id convention, `success` / `cursed` / stats read from `Item.wz/Consume/0204.img`), C (roll order, nothing else) | v83 data; ticket #110 |
| Scroll roster (#110) | `game/data/survivor/scrolls/<line>.json` (common = armour slots, magician = wand and staff): slot -> family -> `100` / `60` / `10` / `dark70` / `dark30` ids; the strong 100%, event 65% / 15%, 50% and other classes' scrolls are out; 2040016 (hat ACC 10%, WZ `success` is the string "10", cast by `DataRepo.scroll_info`) is in; two DEX / LUK series for hat, top and bottom are listed as separate families | C (selection), A (every id and its stats) | ours; `Item.wz/Consume/0204.img` |
| Scroll RNG stream (#110) | RunWorld stream 11 (`scroll_rng`) rolls success and curse; the Free Market derives its seed from the saved round seed, equipment, scrolls and mesos, normalizing JSON numbers before hashing; construction and each saved inventory action use the same stream derivation, so Continue or Cash Shop return preserves the next roll | C | ours |
| Scroll stacks (#110) | a stack holds `info/slotMax` scrolls (100 when WZ names none: all of 0204 do); the Use tab has 24 slots, all for scroll stacks; potions occupy none (#239) | A (24 Use slots, 100 stack), C (scrolls only) | v83 inventory; ours |
| Scroll effect (#110) | `EnchantFx` plays `BasicEff.img/Enchant/Success` (success) or `Enchant/Failure` (failure, destruction) anchored at the character's feet in a screen-space layer 12 above the in-run windows (the held world is frozen), with `Game.img/EnchantSuccess` / `EnchantFailure`; `EnchantSuccess_Delay` / `EnchantFailure_Delay` are unused | A (art, sounds), C (layer, anchor) | ours; `Effect.wz/BasicEff.img/Enchant`, `Sound.wz/Game.img` |
| Scroll messages (#110) | "This scroll cannot be used on that item." / "That item has no upgrade slots left." as HUD notices; a drop on an empty cell or empty space of the Equip window does nothing | C (the v83 client's wording is unverified) | ours |
| Scroll NPCs (#111) | El Moth 1032103 (100%), Barun 2022002 (60%), Tulcus 1052104 (10%), Vega 2041016 (dark 70% / 30%), standing on the Free Market floor at x -380, -280, -180 and 40 (`shops.json`); all four have art in v83 `Npc.wz`, so none is replaced; names from `String.wz/Npc.img` | A (ids, art, names; they are v83's own scroll sellers), C (which NPC sells which rate, the positions) | Owner #33; `Npc.wz`, `String.wz/Npc.img` |
| Warrior scroll roster (#159) | `scrolls/warrior.json`: slots `sword`, `axe`, `blunt` (2043xxx), `two_handed_sword`, `two_handed_axe`, `two_handed_blunt`, `spear`, `polearm` (2044xxx), each with families ATT (x000-x005) and ACC (accuracy), and `shield` (2040900-2040933) with DEF, STR, HP, LUK and ATT (no 100% ATT in v83), by rate like the others; the strong 100%, 65% / 15%, 50%, anniversary, King Pepe's and Magic Att. scrolls are out. A slot is tied to its items by the scroll category (`(id / 100) % 100` equals `(item / 10000) % 100`: 30 sword, 31 axe, 32 blunt, 40-42 their two-handed kinds, 43 spear, 44 polearm, 9 shield); stock follows the shop rule below, so a Warrior sees all nine slots and a Magician or Beginner none | C (selection), A (ids, stats, rates) | ours; `Item.wz/Consume/0204.img` |
| Scroll prices (#111) | 35,000 mesos for an armour scroll, 70,000 for a weapon scroll (`shops.json` `prices`; the weapon-priced slots are the `weapon_slots` of the line files: wand, staff, and the eight Warrior weapon kinds, #159), the shield priced as armour, at every rate | B (100% scrolls: v83 NPC prices, checked for the sword, axe, blunt, two-handed, spear, polearm and shield scrolls), C (applied to the 60%, 10% and dark rates) | Owner #33; v83 server shop data |
| Shop stock (#111) | each NPC sells its rates of every scroll family whose equipment (a drop-list item) the character's job can wear; unlimited, fixed, the same at every tier; no filter tabs, no random stock | C | Owner #33 |
| Sell rule (#111) | any shop buys spare equipment at its `info/price` and scrolls at their `info/price` (1 meso); worn equipment cannot be sold; potions are not bought (the Use tab lists scrolls only) | B (price = sell price), C (potions) | v83 sell rule (server reimplementations); ours |
| Shop messages (#111) | "You do not have enough mesos." / "Please check if your inventory is full or not." / "You can't sell it anymore.", "How many are you willing to buy?" / "...sell?", "Are you sure you want to sell it?" | B (GMS v95 client string pool; the v83 wording is unverified) | open client reimplementations' string pool dump |
| NPC Chat key (#111) | Space, a bindable `npc_chat` action shown in Key Config (icon `KeyConfig/icon/54` NPC CHAT). Space was jump's second key: jump keeps Left Alt and C, as in v83 (Alt jump, Space NPC chat). An existing settings.cfg whose rebound action holds Space keeps it: NPC Chat then has no key until rebound | B (v83's default NPC Chat key), C (the migration) | v83 default key layout; ours |
| Shop talk reach (#111) | within 100 px horizontally and 90 px vertically of an NPC's feet (`shops.json` `talk_range`); a double-click on an NPC opens its shop from any distance | C | ours |
| Shop window layout (#111) | `UIWindow.img/Shop/backgrnd` 463x339, two panels 230 px apart: five rows at y 127 + 40 x n (icon slot x 6, `select` 162x35 at x 43), the strip at y 91 (pink Buy label left, `TabSell` Equip / Use / Set-up / Etc / Cash glyphs right, 44 px each), NPC feet (54, 76), character feet (285, 76), Buy (126, 32), Exit (126, 56), Sell (356, 32), meso text right-aligned in the baked field (361, 63, 90x15), scrollbar `Basic.img/VScr5` at x 208; the `TabBuy` All / Must filter tabs are not drawn | C (measured on the v83 art; art and origins A) | ours |
| Shop dialogs (#111) | quantity box = `Basic.img/YesNo` with a typed number (1 to 100, or the stack), refusal box = `Basic.img/Notice` with BtOK, sale confirmation = the YesNo box | C | ours |
| Skill weapon requirement (#156) | Skill.wz `weapon` (type - 100) read as a weapon family; the key `"weapon "` with a trailing space (5001003 only) is read too | A | original v83 Skill.wz |
| `weapon_families` override (#156) | survivor skills.json array of family names or `["any"]`, wins over the canonical field; untagged skills (Somersault Kick, Grenade: any; Flash Fist, Brawler: knuckle; Masteries, Boosters, Final Attacks: their family) are tagged by the class specs | C | ours (v83-facts.md section 2: no WZ field for these) |
| Gated skill behaviour (#156) | an unusable owned skill does not auto-cast and its cooldown keeps running; running buffs are not cancelled by a swap; its cards are not offered; the Skill window greys it with `iconDisabled` and the tooltip adds "Weapon : X" | C | ours |

| Bot engage kite_reach (#162) | `balance.bot.engage.kite_reach` 220 px: a build whose longest attack reaches less walks up to mobs instead of kiting; below every Magician attack (shortest Magic Claw 260) and above one-handed swings | C | ours |
| Bot engage distance (#162) | `reach_fraction` 0.8 of the longest ready attack's reach (`SkillRunner.reach_of`, `BasicAttack.reach`), `chase_range` 300 px on the bot's level; stands facing the mob; `deadzone` 6 px (keeps its facing when closer) | C | ours |
| Bot engage retreat (#162) | `retreat_hp` 0.35 of max HP, or a boss attack winding up (`BossAttacks.telegraph_up`): the melee bot kites like any other | C | ours |
| Threaten numbers (#183) | canonical `x`/`y` (-1..-20 flat weapon attack / weapon defence), `time` 44..120 s, `mpCon`, `mobCount` 6, `lt`/`rb`, action, effect, `mob` overlay, sound | A | Skill.wz/120.img/skill/1201006 and Sound.wz/Skill.img/1201006 |
| Threaten success chance (#183) | the node has no `prop`: always succeeds, no roll, no RNG (RNG stream 13 stays reserved for this spec, never drawn); a run without Threaten is byte-identical | A (absence) | Skill.wz/120.img level nodes; owner decision 5 of spec #165 |
| Threaten cast (#183) | `crowd` rule with `cast.status: threatened`: at least 3 eligible (live, non-boss, not already threatened) monsters in the box, nearest `mobCount` first, 1 s cooldown, 0.8 s alert2 stance; Slow's two-consecutive-cast history stays Slow-only | C | ours |
| Threatened status (#183) | flat PAD and PDD cut floored at 0 on contact damage, physical ordinary attacks (and their balls) and the player's physical hits; refreshes without stacking; bosses and status-resistant kinds never take it; coexists with slow, poison and freeze; magic attack and defence untouched | C | ours; the v83 text only says weapon attack and weapon def. fall |
| Threaten cards (#183) | learn weight 3, rank weight 2, `requires.jobs` [120], not power; no bot score entry (default scoring, like Iron Body) | C | ours |
| Perion and Kerning City regions (#253, #254) | `perion`: 102010000 / 101030404 / 106000101 (Mano / Stumpy / Iron Hook); `kerning`: 103010000 / 103000101 / 107000000 (King Slime / Shade / Dyle); `region` Perion / Kerning City, continent Victoria Island, notes "Home of the Warriors/Thieves" (no class link); tiers `[[henesys, ellinia, perion, kerning], [sleepywood]]` | C choice, A map/mob ids | Owner, spec #253 |
| Perion and Kerning City pools (#253, #254) | Henesys's numeric curve copied exactly (keyframes, bursts, elites, `exp_mult` 2.5, `hard_cap` 400, `post_duration_slope` 0.25) plus a 210 s keyframe interpolated from it (rate 0.875, cap 17.5, speed 1.0375) that only carries the 3:30 pool. Map 1 opens with Blue Snail 100101 only (owner Q4 weaker-neighbour clause, invoked after T1 seed-1 deaths at 0:15/2:15 (Lv1)); from 2:00 Perion Blue Snail 2 / Stump 3 / Red Snail 2, +Dark Stump 1 at 3:00, Dark Stump 3 / Stump 2 / Red Snail 1 / Blue Snail 1 at 3:30; Kerning Blue Snail 2 / Red Snail 3 / Slime 3, +Orange Mushroom 3 at 3:00, +Octopus 1 and Blue Snail 1 at 3:30. Keyframes from 300 s carry no pool. Maps 2 and 3: their v83 life lists, no exclusions (no timed or hidden entries) | C weights, A life lists | Owner, spec #253 |
| Perion and Kerning City boss multipliers (#253, #254) | Each boss matches the Henesys boss of its map slot at that slot's `typical_hp`/`typical_pdd`: same survivor HP (round(maxHP × hp_mult)) and the 0.01 multiplier steps whose 85–100% roll range is closest to the slot's (within 1 HP). Perion: Mano as in Henesys; Stumpy 0.6857 / touch 1.38 / attacks 1.25; Iron Hook 3.1818 / 2.38 (touch only). Kerning: King Slime 0.45 / 0.78 / slam 0.61 (matches Mano's touch: Mano has no attack); Shade 1.0 / 1.04 (touch only); Dyle 0.2258 / 1.15. Attacks every 8 s. Canonical PDD/MDD, levels and undead flags are not normalized | C | Starting values, untuned (#77 tunes) |
| Boss skill interval override (#253) | A `stages.json` boss entry may carry `skill_intervals` {"<mob skill id>": seconds > 0} replacing that skill's WZ interval for that boss on that map; `DataRepo.stage_map_errors` rejects other shapes. Shade's Kerning entry: `{"129": 15}` (one Banish per 15 s instead of the canonical 3 s) | C | Owner, spec #253; read by #256 |
| Map-select card limit (#253) | At most four region cards per tier (`stage_select.gd` `MAX_CARDS`): 46 px rows from y 154 end at the Start button's top (y 336); a fifth region needs a scrolling list | C | Layout measurement, spec #253 |
| Perion and Kerning City mob metadata (#253, #254) | Mesos: v83 server `drop_data` itemid 0 ranges; EXP pickup: the most likely Etc drop (Dark Axe Stump uses Axe 4000215 of the two equal ones; Shade Someone's Hat 4000413). Iron Hook has no server drops: level-fallback mesos and the Wild Boar Tooth icon. Boss bars borrow MobGage icons for Iron Hook (Zeno 6220001) and Shade (Riche 6090000) with hpTag 1/5; both are enabled boss kits (`mob_skills.enabled_ids`) | B mesos/items, C icons/associations | Cosmic drop data (facts only); owner #253 |
| Mobs without v83 sounds (#253) | A mob with no `Sound.wz/Mob.img/<id>` entry (Iron Hook 4090000) plays no hit, death or skill sound and records nothing missing, as in the client | A (absence) | v83 Sound.wz |
| Mob Attack Up 100/110 (#255) | a timed ×1.15 (`balance.mob_skills.attack_up_mult`, `MobSkillRunner.DEFAULT_ATTACK_UP_MULT`) on the weapon attack of touch damage and physical `attackN` impacts (balls capture it at launch); applied after a Threaten cut, before boss `dmg_mult`/`attack_dmg_mult` and elite scaling, so the final hit is not exactly ×1.15 after defence; magic attacks unchanged; the v83 `x` 115 is not read (flat or percent is unverified); 100 buffs the caster, 110 every living mob in its facing-mirrored box (ordinary mobs included); a recast refreshes the end time, never stacks; cast on the WZ `interval`/`time` like the other boss skills (no mob MP, so `mpCon` unmodelled); casts while the character is Hidden, like 112/113; the end time is per slot and resets on spawn, moves on relocation | C (multiplier, application), A (interval, time, area, art) | owner, spec #253; original v83 MobSkill.img 100/1 and 110/2 |
| Floor/wall corner landing (#260) | An air sub-step whose path crosses a floor line inside the floor's span while its end x lies past the floor's end lands on that floor at the end x pulled EPS = 0.01 px inside (`FootholdMap.find_corner_landing`); player only, mobs/pickups/NavGraph keep `find_landing` | C | ours: the 1 px wall probe at the crossing x was already below a wall rising from the floor end, so neither landing nor wall caught it (Kerning 103000101, x 3185) |
| Fall-out recovery inset (#260) | The nearest floor point to (x, MapBounds bottom) is clamped EPS = 0.01 px inside the floor's span (`FootholdMap.nearest_floor_point`): a point exactly on a wall line is not blocked by it, so recovering onto the end point let the player walk off into the void again | C | ours |
| Boss arrival fallback (#260) | `balance.bosses.arrival_fallback` = 15 s: arrivals (and a stalled-pursuit fade relocation) failing that long for want of a point on the player's platform use the platform of the floor point nearest the player (same 250/150 px rule, then the point itself); the 3 s warning lead still holds; `boss_spawned.fallback` marks it | C | ours, keeps BossDirector's placement/relocation rules; a player over no floor no longer postpones a boss forever |
| Bot second-job family (#261) | At an unforced second advancement (no forced second job; a forced first job such as `500:knuckle` counts as unforced at Lv30) the bot keeps the worn weapon's family (`RunWorld.held_weapon_family`): it draws uniformly on job stream 8 only among the available tier-2 branches whose paths offer that family, takes a single one without a draw, and keeps that family on the weapon page (no path draw). Knuckle -> 510, Gun -> 520, Claw -> 410, Dagger -> 420, Bow -> 310, Crossbow -> 320, Spear -> 130, Blunt -> 120, Sword -> 110 or 120 (axe and polearm come only from a forced path). No branch offering the family (Magician, bare hands): the old uniform draw. Forced second jobs, forced paths and the Lv10 window unchanged | C | ours; #77 found the old independent draw cost a Knuckle Pirate its ranked family skills (`SkillBook.usable_with`): Perion seeds 1..6 on the C05 patch, `500:knuckle` 3/6 clears vs `510:knuckle` 4/6 |

## 12. Later phases

Remaining second-job skills and behavior arrive in spec #31 sibling tickets; #53 enables all three branches and the existing Fire Arrow. Later: more maps (Henesys Hunting Ground II), more mobs.
The Tree That Grew I and the six stage bosses are already playable. Phase 3: other Explorer paths, 3rd/4th job,
additional bosses, elite waves with modifiers, passive items, skill evolutions, run modifiers, persistent unlocks.

#291 tier C provenance: summon auto-admission, replacement groups, nearest/boss-first two-sided acquisition,
current-body impact selection, follow/snap model and the numeric first-pass Elquines settings are in 7.32.
Missing/zero summon frame delays use the existing 100 ms presentation default (tier C); WZ delays are otherwise unchanged.

### Hero H3 meter constants (#299)

| Constant / rule | Value | Provenance |
|---|---|---|
| Combo capacity, gain | 10; +1 per landed non-finisher pool cast | tier C survivor adaptation; tier A source: Combo Attack/Advanced Combo counter descriptions |
| Held-unit damage bonus | +2% per orb | tier C, #296; H2 job data |
| Finisher gate / spend multiplier | 5; all minus meter_keep; +10% per spent orb | tier C, #296; H8 skill data |
| Finisher repeat floor / arbitration | 1 s; single-target scheduled boss, else most targets | tier C, #296; shared admission |
| Meter HUD geometry | origin (244,20), 12 px pitch, 4 px radius, 10 px orb image, 1 px border | tier C presentation layout; original orb pixels tier A |

Review #296 clarification: finisher cooldowns have a strict 1.0-second floor after tick overshoot (tier C,
spec #296); ordinary meter gates use normal cooldown and cast order. `meter.spend` accepts `"all"` or an integer,
and gain exclusion compares the skill’s declared role. Rush explicitly presents its action while walking or airborne
without changing movement physics. Pull admission counts only grounded non-boss targets outside its configured floor.
Warrior bot equipment weights now explicitly name ancestor 100 with the same values formerly inherited from 0
(tier C: existing physical baseline, unchanged). Hero AP and bot score values live in jobs/hero.json’s balance block.

### HP-risk constants (#351)

| Constant / rule | Value | Provenance |
|---|---|---|
| Percentage cost, recoil rounding | floor(field / 100 x max HP), floor(field / 100 x damage dealt) | tier C: ours; the percentages themselves are WZ `x` fields (Dragon Roar, Sacrifice), tier A |
| Never lethal | a cost waits at HP <= cost; a recoil stops at 1 HP | tier C: the existing `hpCon` rule generalised (Slash Blast) |
| HP gate comparison | strictly above `above` x max HP, exact HP | tier C; the 50% threshold itself is Dragon Roar's description text, tier A |
| `HpRisk.BERSERK_BELOW` | 0.5 of max HP, inclusive | tier A: Berserk (1320006) level 30 `x` 50 |
| Low-HP bonus form | adds to the damage multiplier, read before the cost | tier C; the value of a bonus is data (DK-3) |
| Recoil counts | instant lines resolved inside the cast call; not shots in flight | tier C |
| `self_damage` modifier | multiplies the recoil percentage, never the cap | tier C |
| `hp_spent` | emitted for every paid cost (flat too) and recoil, never at 0 | tier C: presentation event |
| Red `hp_spent` number | NoRed digit set tinted (HP_SPENT) | tier C: presentation assignment |
