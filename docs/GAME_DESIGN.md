# Game design

Maple Survivors: survive a classic MapleStory map while an ever-growing swarm of familiar monsters closes in. You move,
jump, climb and drop through the real v83 terrain; your skills fire on their own; you pick upgrades as you level, and
you advance jobs at the classic milestones.

All tuning numbers below live in `game/data/survivor/*.json`; this document explains them. Canonical MapleStory values
(mob stats, skill tables, frame timings, Physics.img) come from the player's WZ data and are never edited.

## 1. The run

1. **Create or continue.** Select one of three living characters, or create a named Beginner with the v83 Explorer
   look and weapon choices. Map select offers one stage from the next tier: Henesys Hunting Ground I or The Tree
   That Grew I in tier 1, then Dark Cave in tier 2.
2. **Start.** A new character is a level 1 Beginner with the chosen MakeCharInfo look and weapon, standing at a
   random spawn portal (`pn=sp`). Empty carried looks use AvatarRenderer.DEFAULT_LOOK (face 20000, hair 30030,
   White Undershirt 1040002, Blue Jean Shorts 1060002, Red Rubber Boots 1072001). Later rounds restore the carried
   character with full HP/MP. The map's own BGM plays.
3. **Survive** the growing swarms and defeat the three bosses arriving at 5:00, 10:00 and 15:00. The final fight can
   continue past 15:00; reaching the timer alone does not clear a stage.
4. **Level up** by collecting EXP drops. An eligible upgrade choice pauses the game and offers up to three cards;
   an empty pool opens no window.
5. **Advance** to Magician at level 10 (survivor override). Further Explorer jobs are planned (section 9).
6. **End.** Death (HP 0) shows the tombstone falling, then the results. A clear requires all three bosses dead and
   their bonus reward choices answered. A non-final clear enters the Free Market; the final tier shows victory
   results. Results show time, level, job, kills, damage dealt and owned skills, then return to character select.

Runs carry one named character through one stage per tier ([ADR 0001](adr/0001-run-of-rounds-with-one-character.md)).
Level, partial EXP, job/branch, AP, skill ranks/mods, potions, Fortune, look and weapon carry; HP/MP refill and
buffs, cooldowns, auto-cast timers, statuses and map entities reset. Saves are at round boundaries only.
Quit round leaves the stored stage, seed and starting character unchanged; Continue replays that round.
Death, victory and confirmed deletion end the run, free its slot and enter history; results have no Retry.
A non-final clear autosaves the carried
character and next tier in the Free Market (`phase=free_market`). The final tier goes directly to victory results.
The Free Market uses v83 Entrance 910000000 and Bgm00/FloralLife. Normal walking, jumping, its two ladders and
existing same-map portal links work; no combat, spawning, drops or round timer run there. Room entrances in01-in22
and Fredrick, Scrooge, Maple TV and Inkwell are drawn but inert. Up at scripted out00 opens and autosaves the next
tier's map select. Esc offers Resume / Save & quit; Continue restores the hub boundary with full HP/MP.
The hub draws only CharacterSnapshot.look (empty means AvatarRenderer.DEFAULT_LOOK's face and hair) with the
character's worn equipment (spec #33, #105). Hub movement never changes the saved character.

## 2. Controls

| Action | Keys (MapleStory defaults first) |
|---|---|
| Move | Left / Right arrows (the movement setting switches to W / A / S / D; only one set moves) |
| Jump | Left Alt (also C; Space is NPC Chat, as in v83) |
| Climb ladder/rope | Up / Down near a ladder |
| Use a same-map portal | Hold Up in its entrance |
| Down-jump through a platform | Down + Jump |
| Prone | Down (on the ground) |
| Teleport (after learning it) | X + direction; no direction uses facing; hold X to repeat |
| Pick an upgrade | Mouse, or 1 / 2 / 3, or arrows + Enter |
| Stat window | S (also Menu -> Stat) |
| Skill window | K (also Menu -> Skill); inside it Up / Down select a skill, Left / Right or 1-n switch tabs |
| Equip window | E (also Menu -> Equip; in the Free Market too): double-click a worn item to take it off, drag it onto the Item window likewise. The Cash and PET EQUIP. buttons in its bottom strip open the Cash tab (double-click an owned cash item to wear it, a worn one to take it off) and the Pet page (double-click an owned pet to bring it out or put it away) |
| Item window | I (also Menu -> Item; in the Free Market too): tabs Equip / Use / Set-up / Etc / Cash; double-click an item or drag it onto the Equip window to wear it; drag it off the windows to discard it (asks first) |
| NPC Chat | Space (as in v83; rebindable in Key Config): in the Free Market, next to a scroll NPC, opens its shop; so does a double-click on the NPC |
| HP / MP potion | Del (also Q) / End (E opens the Equip window, as in v83) |
| Menu | the status bar's Menu button: Equip, Item, Stat, Skill, Key Config, Options (entries without a window yet are disabled) |
| Pause | Esc (closes the front window first; pauses only when none is open). Pause menu: 1 Resume, 2 Key Config, 3 Options, 4 Quit round (asks to confirm; 4 again quits). In the Free Market: 1 Resume, 2 Save & quit |
| Key Config / Options | Menu -> Key Config / Options, or the pause menu (they open over it; Esc returns to it) |

There is no attack key: attacks cast automatically. Teleport is manual on X.

Movement keys are a setting (`Settings` `[controls] movement`: `arrows`, the default, or `wasd`). Only the chosen set
drives `move_*`, so the other set is free to bind; switching to WASD takes W/A/S/D off every other action (S stops
opening Stat until it is rebound). The Options window (#87) exposes the toggle.

Key Config (#87) is the v83 keyboard window: drag an action's icon from the tray (or from a key) onto a key to bind
it; the key's previous action loses it. An action may sit on several keys. Bindable: jump, HP potion, MP potion,
Teleport, Equip, Item, Stat, Skill; fixed (tinted, refuse drops): the movement set, Esc and the card keys 1-3. Dragging an icon off
the keyboard unbinds it; Clear All (v83's BtDelete) unbinds every action. Default puts every action back on its
default keys (less the movement set: on WASD, S stays movement, so Stat has no key until bound); OK saves and applies
at once, Cancel / Esc discard. Bindings are global (`user://settings.cfg`, not per save). Options holds BGM / SFX
volume (sliders and MUTE), the frame cap and the movement setting; each change applies and saves at once. Every HUD
key label (potion quickslots, Teleport) shows the current binding.

Space and jump (#111): as in v83, **Space is the NPC Chat key** and jump defaults to **Left Alt and C** (Space was jump's
second key before the shops). A settings file saved earlier is not rewritten: if one of its rebound actions already
holds Space (jump rebound to Space, say), that action keeps the key and **NPC Chat has no key until it is rebound** in
Key Config (a key holds one action; Default gives Space back to NPC Chat). Double-clicking a shop NPC works either way.
A file that never rebound anything simply gains the new defaults.

In-run windows (Stat, the Menu popup, later Skill / Key Config / Options) are draggable by their title bar and
stack (a click brings one to the front). The run is paused while any is open, as with the pause menu. Stat and Skill
also open over a level-up, job or advancement choice; they draw above it, and the choice ignores input until they are
closed. The Stat window is the v83 one (`UIWindow.img/Stat` with its detail panel), read-only: AP is spent
automatically, so there are no +AP buttons, and stats the game does not model (guild, fame, hands) show "-".

The Equip and Item windows (#108) are the v83 ones (`UIWindow.img/Equip`, `UIWindow.img/Item`) and open in a round
(pausing it like the other in-run windows) and in the Free Market, which hosts the same window stack. The Equip
window shows each worn item's icon in its v83 slot (CAP, CLOTHES for a top or an overall, PANTS, SHOES, GLOVES,
WEAPON); a double-click takes an item off into the inventory, as does dragging it onto the Item window. The Item
window has the v83 tabs: Equip holds the 24 slots of spare equipment (a double-click, or a drag onto the Equip
window, wears an item, swapping out what was in its slot; a refused v83 requirement shows a message and changes
nothing), Use holds the HP and MP potion stacks (read-only, the potions keep their quickslot keys) and the scroll
stacks, Set-up / Etc / Cash are empty, and the meso line shows the character's mesos. Dragging equipment or a scroll
stack off the windows asks v83's YesNo question and then destroys the item (it is not dropped on the ground, the
magnet would take it straight back; worn items have to be taken off first, potions are never discarded). Hovering
an item shows the v83 tooltip (name with "(+N)" after N successful scrolls, icon, REQ LEV / STR / DEX / INT / LUK
with the unmet ones in red, the job row, CATEGORY, ATTACK SPEED, the stats, NUMBER OF UPGRADES AVAILABLE, the
String.wz description). Every change goes through the character's RunWorld, so the derived stats, the drawn look
(hat, top, bottom, overall, shoes, gloves, weapon, on character select too) and, in the hub, the save slot follow at
once.

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
A last tab with a star lists the job-neutral cards taken (Magnet, potion tiers, later Fortune) with their rank; the
one-off Elixir is not listed. Hovering a row, or selecting it with the keyboard, shows a v83-style tooltip: icon, name,
the SkillText desc, the current and next level lines (effective values), cooldown and MP cost (none for passives),
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
- **Landing:** vy clamped to 162.5 px/s on contact; walking off an edge falls; vertical footholds are walls.
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
  the way to the player (100010000's hill faces cross its ground). New mobs fade in (regen) over 0.3 s (tier C).
- **Relocation:** an off-screen mob that has not come closer by its own walking for 3 s (left behind by a player who
  runs off, on a way that keeps getting longer, or stopped at a wall; the player walking up to it does not count),
  that is 1300 px away, or that cannot reach the player is moved silently to a fresh spawn point ahead of the player
  (on the side it is moving toward), keeping its HP; it fades in there like a new mob. Never a mob on screen (it must be
  80 px outside the view, since the camera can lag on either side), never an elite; a mob standing still on screen
  (at a wall) keeps counting and is moved as soon as it leaves the screen. The player can still climb away for a
  while: the mobs below stay where they are while on screen, and the swarm re-forms around the new platform as the
  off-screen ones are moved.
- **Contact:** touching a mob with `bodyAttack=1` deals touch damage (section 6), unless the player is inside the hit window (#88: shrinking while hits keep landing).
- **Mob attacks (#76):** an ordinary mob whose Mob.wz img lists `attackN` (Tauromacis 7130100 `attack1`, Taurospear
  7130101 `attack1`/`attack2`: type 0 magic) uses them exactly like a boss attack (4.3): the canonical windup stance,
  the hit at `attackAfter` in the canonical range box mirrored by facing, magic attacks with MADamage against M.DEF
  and `elemAttr` as for bosses, the `hit` art and the `Sound.wz/Mob.img/<id>/AttackN` sound. Damage is unscaled like
  contact damage, times `balance.mob_attacks.mobs[id].dmg_mult` (1.0) and, for an elite, `elites.damage_mult`. A mob
  attacks only grounded, fully faded in, not frozen, with its feet on screen and the character in a range; it tries its
  attacks in canonical order. Its wait counts only that on-screen time: the first is 50-100% of its interval (by spawn
  identity, so a wave spawned together does not attack in unison), the next the full interval (5 s for both Tauros).
  Hits are `source_kind` `mob_attack` and share the shrinking hit window with contact damage (#88, section 11); boss
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
  Henesys Hunting Ground I adds PQ Stirge 9300063 (Lv 6) at 3:00, Flyeye 9300062 (Lv 8) at 5:00, Goblin Fire 9300064
  (Lv 11) at 8:00, and regular Stirge 2300100 (Lv 20) at 11:00, each at weight 1; earlier flyers remain in the pool.
  The added arrival keyframes interpolate the existing pacing values. The Tree That Grew I has no flyers.
- **Death:** `die1` plays with its WZ delays and alpha fades (`a0/a1`), the death sound plays, and the mob drops EXP.
- **Elites:** periodically one mob of the current pool spawns with ×8 HP, ×5 EXP and an explicit ×1.5 mitigated
  hit multiplier (`elites.damage_mult`), drawn with a name tag. All three multipliers are survivor data (tier C).

### Monster statuses and elements (#54)

`MobSwarm.apply_status(slot, status, params, events)` is the shared sim entry point for sibling skills. `status`
is `slow`, `poison` or `freeze` (`MobSwarm.STATUS_NAMES`); parameters contain the canonical `time` in seconds, signed
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
- **Bosses reject every status**: scheduled bosses (`steady`) and canonical `info/boss` monsters refuse Slow, Poison
  and Freeze, matching the inspected v83 server reference (**tier C**, Cosmic `Monster.applyStatus` boss gate; owner
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
Poison loops cached 2101005/mob. Cold Beam has no persistent mob overlay, so Freeze uses a cyan tint. A violet
poison tint is the fallback when its cached cue is absent. Anchors and tints are tier C; original art/timings are A.
The formulas, source limitations, pinned citations and the performance/visual validation record are in
[the status research](research/monster-status-effects.md). The applying Slow/Poison Breath/Cold Beam skill
implementations remain sibling work.

### 4.1 Pacing (`stages.json`)

Dark Cave (`dark_cave`, v83 105050400, Dungeon) is tier 2 in the zero-based run tier list:
`[[henesys_hg1, tree_that_grew_1], [dark_cave]]` (tier C, owner choice, #32/#72).
Its first-pass data targets an arriving Lv35–43 second-job character and is frozen before the report-only smoke;
the 30–40% clear / Lv60–69 targets are deferred to #77. Canonical mob HP, defence, EXP, levels and elements remain
unchanged in the cache. Stage EXP is 1x; no new per-mob stat multipliers are applied. Tauromacis and Taurospear use
their canonical magic attacks (#76, section 4 "Mob attacks"); Jr. Boogie deals contact damage only and no ordinary mob
casts a mob skill. Cross-map exits west00/east00 and NPC
9201133 use the existing drawn, inert handling. The original spawn list is 9 Horny Mushrooms, 7 Zombie Mushrooms
and 35 Stirges (tier A, original Map.wz).

| Time | Rate/s | Max alive | Pool (mob ID:weight) | HP × | Speed × |
|---|---|---|---|---|---|
| 0:00 | 3 | 50 | 2110200:4, 2230101:4, 2300100:1 | 1 | 1 |
| 2:00 | 4.5 | 80 | 2110200:3, 2230101:3, 2300100:1, 2230100:3 | 1 | 1.05 |
| 5:00 | 7 | 130 | 2110200:2, 2230101:2, 2300100:1, 2230100:3, 3230100:3, 3230300:1 | 1.15 | 1.1 |
| 8:00 | 10 | 180 | 2230101:2, 2300100:1, 2230100:3, 3230100:4, 3230300:2 | 1.3 | 1.15 |
| 10:00 | 12 | 220 | 2230101:1, 2300100:1, 2230100:2, 3230100:4, 3230300:2, 7130100:2 | 1.4 | 1.2 |
| 13:00 | 15 | 280 | 2300100:1, 3230100:3, 3230300:2, 7130100:3, 7130101:2 | 1.5 | 1.25 |
| 15:00 | 18 | 330 | 2300100:1, 3230100:3, 3230300:2, 7130100:3, 7130101:3 | 1.6 | 1.3 |

All curve values/weights are tier C. The hard cap is 400; bursts start at 90 s, repeat every 90 s and grow from
10 to 40 mobs; elites start at 75 s, repeat every 60 s and use HP/EXP/contact multipliers 8/5/1.5 (tier C,
existing stage conventions). Global potion chances apply. All three bosses and every reward choice must finish
before the round clears (#73). These values are not a balance calibration.

The director keeps spawning until `alive >= max_alive(t)`, at `spawn_rate(t)` mobs/s, choosing from the pool active at
time t by weight. Values interpolate linearly between keyframes. Henesys Hunting Ground I (104040000) uses
the coarse #30 C46 stage data (2026-10-15). It preserves the spec #29
tuning waits for the dedicated balance pass (section 4.2).
for now; balance will be revisited after more features (section 4.2).

| Time | Rate (mobs/s) | Max alive | Pool additions | HP × | Speed × | Normal HP chance |
|---|---|---|---|---|---|---|
| 0:00 | 0.15 | 3 | Snail 4, Blue Snail 3 | 1 | 1 | 8% |
| 2:00 | 0.4 | 8 | Red Snail, Shroom | 1 | 1 | 5% |
| 3:00 | 0.6 | 12 | PQ Stirge | 1 | 1.025 | 4% |
| 4:00 | 1 | 20 | Slime | 1 | 1.05 | 3% |
| 5:00 | 2.5 | 50 | Flyeye | 1.25 | 1.075 | 1.2% |
| 6:00 | 4.5 | 85 | Pig, Orange Mushroom | 1.75 | 1.1 | 0.8% |
| 8:00 | 8.2667 | 143.3333 | Goblin Fire | 3.84 | 1.1533 | 0.8% |
| 9:00 | 9.4 | 165 | Green Mushroom | 3.9 | 1.18 | 0.7% |
| 11:00 | 12.1333 | 215 | Stirge | 4.7 | 1.2467 | 0.7% |
| 12:00 | 13.5 | 240 | full pool | 6.375 | 1.28 | 0.805% |
| 13:00 | 15.6667 | 270 | full pool | 7.6875 | 1.32 | 1.035% |
| 15:00 | 20 | 330 | final boss | 8.25 | 1.4 | 1.2075% |

The Beginner phase is sword-paced: a v83 Beginner (5 MP, one Three Snails shell at canonical 3 MP) kills mostly with
the basic attack, so until 4:00 only a few mobs are alive, ordinary HP drops are generous (8% falling to 3%), no
elite appears before 4:00 and no burst before 5:00, and ordinary kills pay 2.5x EXP so Magician arrives near 4:40.
Density and HP then ramp from 5:00 into the calibrated mid/late curve. Canonical mob HP and skill damage/costs remain
unchanged. Tree stage data are unchanged.

The changed 8:00 HP endpoint interpolates from the unchanged 6:00 point; the extra late HP support begins after
11:00. The HP potion curve holds after 15:00, independent of the spawn ramp. Ordinary/elite HP continues after 15:00 at
0.25 × (8.25−7.6875)/120 = 0.001171875 per second; other pacing fields retain their existing quarter-slope
extrapolation. Normal-mob MP is 3% flat on every stage, with no per-map values (owner, 2026-10-16, #80; Henesys's
earlier 10% -> 4% curve is removed). Elite MP stays 60%, and elite HP/boss bundles are
unchanged. Stage EXP remains a constant 2.5; the rejected optional EXP-keyframe experiment is removed.

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

The balance harness records completed boss spawn-to-death times per encounter, HP/MP potion collection and use,
MP-short waiting seconds, and whole boss-hit damage divided by max HP at the hit (before Magic Guard's split).
Aggregates report completed fight samples separately from unfinished, unspawned or skipped encounters, print the
completed/spawned count beside each median and a censored median over all spawned fights (an unfinished fight counts
as at least its elapsed seconds; `>=` marks a lower bound), and retain the boss-hit source kind. A cap ends the measurement as TIMEOUT; reaching 15:00 alone cannot clear a run.
The per-policy `SYSTEMS` report also divides total MP potions collected by total MP potions used (not a mean of
per-run ratios). `mp_collected_used_ratio` is JSON null, printed as `undefined (no MP used)`, when use totals zero.

The #42 harness also reports `ordinary_kill_hits_by_min` for the first five run minutes: each bucket contains
landed lifetime damage-line hits, ordinary kills and their ratio (null without kills). The death minute receives
all hits on that mob, including earlier-minute hits; a death exactly on a minute boundary belongs to the preceding
minute. Relocation preserves a lifetime's count and fresh slot reuse resets it. Elites, scheduled bosses and
canonical boss kinds are excluded; ordinary summons/offspring are included. Magic Claw counts each landed line,
basic attacks count, and immune contacts do not. Aggregation divides summed hits by summed kills.
`late_mp_short_seconds` measures ticks after 8:00 when an eligible ready skill fails affordability during the cast
scan; a later affordable skill or basic attack may still act. `late_observed_seconds` and reached/waiting run counts
distinguish unobserved late time from observed zero shortage. Final `potions_left` includes starting stock,
recorded separately in `potions_start`; collection totals exclude starters. `outcomes` keeps timeouts separate
from clears and deaths, and `death_seconds` samples deaths alone. Run records retain simulation warnings.
Boss diagnostic snapshots use JSON null for an unobserved/nonfinite `best_distance`; the live simulation retains
its infinity sentinel. The report reader normalizes that field in preserved legacy `1e99999` records before parsing,
logs every normalization and leaves raw files and measured values unchanged.

Since the buff-timeline diagnostic, `buff_casts` also records each observed cast tick, skill ID, canonical level,
duration and active effect stat/value. This exposes the real cast snapshot, unlike a final rank or an absorbed
hit fraction (which available MP may clip). It changes no gameplay or RNG. Old records without the field cannot
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

Issue #37's initial MP scarcity pass uses normal/elite MP chances 2%/30% and boss MP bundles of 3,
with HP supply unchanged (tier C). Before integrating the subsequent #48/#49/#50 changes, HG training seeds 1..12
showed sensible collected/used falling from
1.917 to 1.064 and median leftover from 85 to 0; random falls from 2.275 to 1.034, with median leftover
59.5 to 0. Sensible clears fall from 4/12 to 0/12; random remains 0/12. Median MP-short seconds become
116.884 (sensible) and 54.367 (random), from zero. This overshoots the 1.2-1.5 target; final calibration
belongs to the balance pass. No held-out seeds were run. Configuration and exact training output:
[issue37-mp-drops.md](research/issue37-mp-drops.md).

Spec #29 replaces #1/#27's “most runs clear” target (including the historical 22/30 result) with **40–50% sensible
clears and 5–15% careless clears** in Henesys. Death-only median time should fall between the first and third boss
arrivals, **300–900 s**. Sensible MP collection/use should be **1.2–1.5**, with final stock far below the former 117;
careless runs must actually observe some MP waiting after 8:00. First-five-minute ordinary lifetime hits/kill and
their denominators report whether early durability is meaningful; mid-game mobs should typically need 2–3 hits.

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

### 4.2 Tuning record (`scripts/balance.sh`)

Pacing is measured with `bash scripts/balance.sh [seeds | a..b] [--policy=...]` (whole headless runs on the real map,
`game/tools/balance_run.gd`). Movement is always the autoplay bot (`BotInput`): it kites on the ground (dueling a
lone ordinary mob with the basic attack while no attack skill can fire), walks to EXP drops and climbs a ladder or
rope to drops left on a platform above, and picks a seeded-random available branch (override with `--job=<first or second job id>`; `--branch` is the deprecated alias). Card
policies: `bot` uses `BotInput.pick_card_for`, prioritizing eligible potion tiers, then Guard learning/ranks through
survivor score overrides, then the existing attack, shot, damage, pierce and defence scores, each plus
`bot.gain_step_score` per step an offer grants beyond its first (#63); `random` is a careless player who takes a random
card of the three (the old `--first-card` policy is no longer a careless proxy: it always takes the
guaranteed card, which UpgradePool puts first). `--idle-after=300` takes the hands off the keys at 5:00.

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
(`lv35_magician_2nd.json`, #67 seed-1 forced-F/P Henesys clear) is reused unchanged. Cache
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
`tests/fixtures/characters/lv35_magician_2nd.json` is actually Lv38, job210, from the seed-1 forced-F/P bot
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
uses committed `lv35_magician_2nd.json` (its actual character is **Lv38 F/P**, job210). Encounter data was frozen
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
  onto the ground outside the hill's faces walked into them while the player stood between the faces.
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
random), the `--tier=2` chain (bot, random) and the Dark Cave Lv38 F/P fixture (`lv35_magician_2nd.json`, bot,
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

### 4.3 Boss encounter lifecycle (difficulty overhaul)

Henesys Hunting Ground I schedules Mano (2220000) at 5:00, Mushmom (6130101) at 10:00 and Blue Mushmom (9400205) at
15:00. The encounters use canonical movement, contact attack, art and enabled skill kits; the mushroom family
also uses its jump slam. The Tree schedules Stumpy, King Slime and Dyle at the same arrival times.
Each boss gives a 3 s warning, then arrives with the normal regen fade on the player's reachable platform, preferably
250 px away. A narrow floor may require a closer point. If no arrival point exists at all on the arrival tick, the
arrival slips by 3 s behind a fresh warning (tier C). A boss whose mob img is missing from the asset cache is skipped
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

Calibration uses measured training builds rather than the former assumed HP300/550/800 and full Armor defense.
`stage.bosses` stores the multipliers; `typical_hp/pdd` are illustrative inputs only, never adaptive runtime scaling.
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
Both stages continue the last rate/max-alive/HP/speed keyframe slopes at quarter pace after 15:00
(`post_duration_slope`), with ordinary mobs still capped by `hard_cap`. Burst size keeps its 10→40 slope over the
stage at the same quarter pace past 15:00, and the elite interval shrinks in proportion to the extrapolated spawn rate
(`every × rate(15:00) / rate(t)`), so elites stay the same share of the growing stream until the clear (tier C). Clearing requires every scheduled boss dead;
stages without a boss list retain their duration clear. Stage select states the applicable objective.

If a living boss has no route or makes no progress toward the player for 5 s, it fades out over 300 ms, then
relocates about 250 px away on the player's platform using the same placement policy. HP is preserved; it stands
still and cannot touch during fade-out or the normal 300 ms arrival fade. Progress means closing the route distance
by at least 1 px through its own movement; a boss already at the player does not relocate.

Boss deaths replace ordinary drops with a shower totaling rounded canonical boss EXP × survivor reward multiplier
(×5), split into 12 drops with no remainder lost, spread ±120 px. Default HP/MP bundles hold 3/3 potions of the
stock's current tier, separated by ±30 px. Mano overrides these to 6 HP/3 MP; Stumpy keeps 3 HP/3 MP, supporting
early builds. Both second bosses give 1 HP/3 MP, limiting later stock while ordinary HP supply stays scarce. The nested override includes
MP explicitly; EXP and reward geometry retain the global defaults. Ordinary potion rolls do not add to bundles. Each death
also grants one bonus upgrade pick, before any queued normal level pick, with no level gain or queued-level
consumption. Final clear waits for the choices to finish. The bonus window reads "Boss Reward" and has no gained-level
header. All reward and relocation values are tier C in `balance.bosses`; a schedule entry's `rewards` may override
reward defaults for tuning.

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

The Tree That Grew I adds Stumpy (3220000) at 5:00, King Slime (9300003) at 10:00 and Dyle (6220000) at 15:00.
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
into a reused pool slot. Dyle's canonical 112/113 defense skills reuse the existing handlers; 110 is not enabled.
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

- **Time-varying ordinary HP potion chance** (`normal_hp_drop_chance` keyframes, tier C): early supply bridges weak
  Red-potion builds and late scarcity limits banking (section 5).
- **Per-boss `attack_interval`, `attack_dmg_mult` and `rewards` overrides** (tier C): WZ attack nodes carry no
  interval, so the 8 s cadence is ours; a slam's PAD differs from the contact PAD (300 against 200/450), so it needs
  its own scale to land in the 40-50% band; reward overrides support early builds (Mano 6 HP / 6 MP, Stumpy 3 HP / 6 MP) and
  limit later stock (second bosses 1 HP).
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
- **Playtest default length 30:00** (tier C tooling): `scripts/playtest.sh` runs through the post-15:00 finale until a
  death or clear; documented in AGENTS.md and the script header.

## 5. Experience and levels

Potions are separate persistent pickups, pulled in by the same magnet as EXP. Stock is unlimited and a run starts
with five Red Potions (2000000) and no Blue Potions (2000003). Delete/Q drinks HP,
End/E drinks MP, once per press, instantly and without a cooldown even on a rope. Empty stock does nothing.
Restoration comes unchanged from canonical item `spec.hp`/`spec.mp` (Red 50 HP, Blue 100 MP), clamped to max.
Normal kills use a global fallback of HP 1.2% and a flat MP 3% independently (MP: owner, 2026-10-16, 3% flat, no
per-map values; #80, was 10%). Elites roll HP 15% and MP 60%. With every
skill in its single-shot vanilla form at canonical MP, Blue Potions are the main MP income once regeneration (3 MP per
10 s) runs out; boss bundles stay 3 rather than 6. These choices and starter stock
are tier C data in `balance.potions`; potion rolls use a separate seeded stream. Potions never expire or enter the
EXP cap/absorption path. Both card policies drink a potion only when the missing HP or MP is at least half of one
current potion's canonical restore (`balance.potions.bot.min_restore_fraction`, tier C), so a sip never mostly
overflows the pool; a five-MP Beginner never drinks a 100-MP Blue.

The opening pool is the v83 Beginner's 50 HP / 5 MP (owner decision). Each level-up refills MP to the new maximum
(#80, tier B) but adds no HP (tier C). Between level-ups, Three
Snails at its canonical 3 MP casts about once per 10 s regeneration pulse, and the Beginner phase is
sword-paced: the basic attack does most of the killing until Magician. Real-run sip restoration/waste is recorded
per event.
The optional stage-keyframe `normal_hp_drop_chance` field is tier C survivor supply tuning: clamp each endpoint to
[0, 1], interpolate linearly, hold the nearest endpoint outside the range, and substitute the global normal HP chance
for missing endpoints. Elite rolls and fixed boss bundles keep their existing settings, and the curve is independent
of card policy. Normal MP has no stage field (owner, 2026-10-16, #80: 3% flat, no per-map values; the earlier
`normal_mp_drop_chance` curve and its reader are removed). Changing the global MP chance also changes which ground
pickups the bot approaches during the opening.

Potion-tier score 112 prioritizes a useful permanent supply upgrade above Guard and attack cards. Learning a new
attack remains score 100; attack ranks/modifiers have maximum 87. The fallback 52 preserves callers without this field.
Only sensible choices use these scores; careless choices use their separate seeded card RNG.
Optional final card-score overrides set Guard learning to 110 and ranks to 109, without adding a job bonus. Missing
entries preserve legacy scoring. Guard learn/rank offer weights 8/8 improve availability; Orange/White offer
weights 30 make their eligible upgrades likely to appear. Snail count/cooldown/pierce weights 12/8/8 support the
Beginner; these are survivor choices, and the random policy still chooses uniformly among offered cards.
Current Henesys normal HP supply follows the C46 endpoint table in section 4.1; the curve interpolates and holds.
Normal MP is 3% flat on every stage (owner, 2026-10-16, #80), elite MP 60%, with scheduled boss bundles unchanged. Tree's HP curve retains its earlier 3% through 4:00, 0.6% at 6:00, 0% at 9:00/12:00,
0.6% at 13:00 and 0.8% at 15:00. These ordinary-drop
chances do not suppress elite or boss-bundle HP drops. Elite chances remain
global. Early supply bridges weak Red-potion builds; later scarcity limits banking without policy adaptation.
The quickslot shows each kind's current icon, stock count and keys; balance/perf records report collected and used
quantities per kind.

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
- **Survivor EXP curve:** `exp_to_next(L) = round(4 + 15·L + 3.8·L²)` (L1 = 23, L7 = 295,
  L9 = 447, L29 = 3635; 980 EXP to reach Lv 8, 1794 to Lv 10, 39150 to Lv 30). Historical curves and their
  measurements remain in section 4.2. The quadratic term carries the late game: a strong build that levels
  fast meets steeper levels, which keeps the spread between builds small. Measured
  pace: section 4.2. The canonical v83 table (`data/canonical/exp_table.json`) is kept for reference and display
  only.
- **Level up:** the game pauses, `Effect.wz/BasicEff.img/LevelUp` plays on the character with `Game.img/LevelUp`, then
  the upgrade window opens. Several level-ups in a row queue their windows.
- **Attributes and AP** (tier C, survivor choices): start at STR 12, DEX 5, INT 4, LUK 4, with 5 AP per level.
  Beginners assign AP to STR. On advancement the AP earned above those base stats moves to the new job's primary
  stat (INT for Magician); subsequent AP goes there too. The job's nearest configured ancestor supplies the rule.
  A job line may name a secondary stat (`balance.json/player.ap_secondary`, #106): earned AP fills it first, up to
  its base value's target for the character's level, and the rest goes to the primary stat. The Magician's LUK target
  is about level + 2 (tier C; v83 reqLUK 15 at Lv13 ... 70 at Lv68), so a Magician meets the Lv68 equipment LUK and
  its INT is lower by exactly the points moved to LUK (Lv70: INT 281 instead of 349). The split is recomputed from
  earned AP and the level, so existing snapshots need no format change.
  All starting values, AP gains and primary-stat choices are in `balance.json/player`.
- **Stats per level** (tier C for HP/MP base growth): Beginner +14 HP / +10 MP; Magician +12 HP / +22 MP, plus
  `floor(INT/10)` MP using INT before that level's AP (tier B). Magic skill damage uses the resulting INT.
  Every per-job table (`ap_stat`, `ap_secondary`, `growth`, the bot's equipment weights) resolves through the job's lineage, so a new job line is data rows only. Planned rows use the v83 midpoints (tier B): Warrior +26 HP / +5 MP, Bowman and Thief +22 HP / +15 MP, Pirate +25 HP / +20.5 MP (rounded like the Magician's); rows are added only when the job becomes playable (Warrior with #163).
  Level-ups raise the maxima, then refill MP to the new maximum (`level_up_refill.mp` = 1, tier B: v83 servers
  refill both pools, Cosmic `Character.levelUp` calls `changeHpMp(maxhp, maxmp)`) but add no HP
  (`level_up_refill.hp` = 0, tier C owner choice for difficulty). Several level-ups from one EXP gain leave MP at
  the final maximum. The owned Improved MaxMP Increase passive preserves current MP's fraction of the maximum when
  Max MP grows outside a level-up (job grants). It never restores HP.
- **Defense and avoid**: W.DEF and M.DEF sum the worn equipment's `incPDD` and `incMDD`, plus active defense
  modifiers. The default creation outfit is W.DEF 7 (3 + 2 + 2), M.DEF 0 (tier A, v83 Character.wz).
  Avoidability is DEX × 0.25 + LUK × 0.5 + equipment `incEVA` (tier B, pre-Big-Bang formula compilations).
- **Worn equipment (spec #33, #105)**: one equipment instance per equip slot (hat, top, bottom, overall, shoes,
  gloves, weapon, shield; an overall fills top and bottom; the shield, spec #151 #158, is described below). Every worn `inc*` stat counts: main stats add to the base (the
  Stat window shows "total (base+bonus)"), W.ATT is `incPAD` summed over every worn item, M.ATT adds `incMAD`,
  accuracy `incACC` (shown, and it raises the critical chance, 6.1; no player attack ever misses), max HP/MP `incMHP`/`incMMP` (flat, after card
  modifiers and the MaxMP passive, tier C), speed `incSpeed` and jump `incJump` capped at 140 / 123 (tier B).
  Equipping checks v83 `reqLevel`, `reqJob` (bit mask 1 Warrior, 2 Magician, 4 Bowman, 8 Thief, 16 Pirate; 0 all)
  and `reqSTR/DEX/INT/LUK` against total stats; a failure changes nothing. The creation top, bottom, shoes and
  weapon are the first worn equipment with plain WZ stats; a character without a snapshot wears the first creation
  options (`Equipment.DEFAULT_OUTFIT`, tier A). Advancing to Magician grants and wears the Wooden Wand 1372005 and
  moves the previous weapon to the inventory (`balance.player.weapon_grants`, tier C); with a full inventory the grant is skipped and nothing is destroyed. Without a weapon the basic
  attack is a bare-handed punch (`BasicAttack.BARE_HANDS`: v83 `barehands` sound, tier C speed 6, reach box and
  impact on the action's last frame); with no W.ATT it deals the swing formula's minimum, 1.
- **Shield slot (spec #151, #158)**: `shield` is the last of `Equipment.SLOTS`, filled from Character.wz `Shield`
  (109xxxx) with the same requirement check as any equipment (`reqJob`, `reqLevel`, `reqSTR`...), and its `inc*` stats
  (mostly `incPDD`/`incMDD`) count like any worn item. A two-handed weapon (`WeaponInfo.is_two_handed`: every weapon
  type from 140) never shares the hands with a shield: wearing one moves the worn shield to the Equip tab, wearing a
  shield moves a held two-handed weapon (`Equipment.displaced_slots`; the job-weapon grant follows the same rule). When
  the Equip tab has no room for what moves, the change is refused with `inventory_full`, the v83 notice "You can't get
  anymore items." shows, and nothing changes. The Equip window shows the shield in its v83 SHIELD cell (right of
  WEAPON); the avatar draws the shield layers of the worn item. The snapshot gains no key beyond a `shield` entry in
  `equipment.worn` (format stays 2; a snapshot saved without one loads unchanged; a two-handed weapon beside a shield
  is invalid). The autoplay bot treats the shield as a slot: it wears a shield when its score beats what the change
  moves off (a two-handed weapon must beat the one-handed weapon plus the shield it displaces), and may scroll it last.
  Shield drops and scrolls are #159.
- **Scrolls (spec #33, #110)**: `Scrolls` (pure) applies a scroll to the item worn in an equip slot. Fit: `(scroll id
  / 100) % 100 == (item id / 10000) % 100` (tier A, the v83 id convention) and at least one upgrade slot. Roll 0-99
  below `info/success` adds every `inc*` of the scroll to the instance (`scrolls` + 1); success or not, `slots` - 1;
  a failed scroll with `info/cursed` (the dark ones: 50) rolls 0-99 below `cursed` and destroys the item. Rates, stats
  and `cursed` are the WZ values unchanged. In the game: 100%, 60%, 10% and the dark 70% / 30% scrolls of the families
  below; event 65% / 15%, 50%, the "strong" 100%, Balrog's, Chaos, Clean Slate, White and other classes' weapon
  scrolls are out. Scroll stacks live in the character's `scrolls` map ({"<id>": count}); a stack holds at most
  `info/slotMax` (100 when WZ names none, as for every 0204 scroll) and the Use tab has 24 slots, two of them the
  potion stacks (tier A), so 22 scroll stacks. RunWorld adds `use_scroll(scroll_id, slot)` (the scroll is used up
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
  `equipment`, `potions`: the keys of a CharacterSnapshot) and returns "" or a reason, changing nothing on a reason.
  `Shop.stock(npc, rules, scrolls.json, drop list, item info, job)`: the NPC's rates (shops.json) of every family whose
  item category (`(item id / 10000) % 100`, the scroll's `(id / 100) % 100`) some drop-list item the job can wear
  (`Equipment.job_allows`) belongs to, in file order, each priced by its slot. `buy` is all-or-nothing: `count` (below
  1), `mesos`, `use_full` (a stack stops at slotMax, the tab holds 22 scroll stacks beside the potions; checked before
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
  Survivor skill and player damage multipliers scale these bounds. At impact, with
  `D = max(0, mobLevel - playerLevel)`, apply `MAX × (1 - 0.01D) - 0.5PDD` and
  `MIN × (1 - 0.01D) - 0.6PDD`, each at least 1; roll uniformly, multiply by the canonical
  Skill.wz `damage` / 100, apply crit, element, then round once. Live PDD includes monster defence buffs.
  `attackCount` gives the number of instant hit lines. Per-skill `physical_formula` overrides select primary,
  secondary, max/min multipliers and whether to ignore mastery: Lucky Seven is
  `{"primary":"luk","max_mult":5.0,"min_mult":2.5,"secondary":"","ignore_mastery":true}` (tier B).
- **Critical hits (#153):** every job, including Beginner, can crit on fixed, magic, physical and basic attacks
  (owner decision, spec #151; overrides the old Beginner-phase equivalence criterion). Chance is
  `balance.crit.chance + ACC × balance.crit.per_acc + crit_bonus`, plus existing survivor crit modifiers.
  The untuned tier C coefficient is 0.0005 (+0.05 percentage points per ACC); base chance stays 0, multiplier 1.5.
  With a passive `crit_damage_bonus > 0`, its skill-percentage points add to the skill multiplier instead
  (`150% + 100 = 250%`, tier B Critical Shot/Throw); otherwise crit multiplies the hit by `crit_mult`.
  Skill crits use combat stream 1; basic damage/crit rolls use basic stream 5. Crits use the `NoCri` digits and
  the `NoCri1/effect` burst. The lead records the Beginner/Magician smoke deltas in 4.2; no balance tuning here.
- Mob defence: magic damage × (1 - MDD/(MDD+150)) (tier C, keeps early mobs readable).
- **Player accuracy:** job base (tier B) plus equipment `incACC` and active buff `acc`, stored in `player_state.acc`
  and consumed by crit chance. The nearest listed job ancestor supplies coefficients: Beginner/Warrior/Magician
  DEX×0.8 + LUK×0.5; Bowman/Thief/Pirate DEX×0.6 + LUK×0.3; Brawler 510 DEX×0.9 + LUK×0.3.
  Player attacks never MISS (ADR 0005). Monster attacks still roll against player avoid (6.2).

### 6.1.1 Basic weapon attacks

The Beginner holds Sword 1302000 from the first frame; Magician holds Wooden Wand 1372005. Canonical equipment
info supplies Sword W.ATT17/speed4 and Wand W.ATT15/M.ATT23/speed6. Magic attack sums the worn equipment's
`incMAD`; survivor data only selects the weapon, never duplicates its canonical attack value.

After skill priority, a standing or airborne player automatically attacks when a monster intersects any of its
five facing stance afterimage boxes. Walking, climbing, a skill fired this tick or no reachable target prevents a new swing.
There is no movement lock. Each swing chooses uniformly among the held weapon family's actions (`WeaponInfo.basic_actions`,
below; swingO1/O2/O3 and stabO1/O2 for every one-handed melee weapon, the Beginner's and Magician's included) on its own
seeded stream.
The chosen stance retains its own impact box: a shorter stance can miss an outer-range target. One live monster in
that box is hit: a scheduled boss first (#83), otherwise the nearest; a moving target may leave before impact. The interval is
`ceil(800 * (10 + attackSpeed) / 16 / 30) * 30 ms`: Sword720ms, Wand810ms (tier B); an active Booster lowers the
`attackSpeed` step used (7.7). The first numbered afterimage
body frame supplies impact timing, summing earlier canonical body delays (tier A): Sword swingO1 frame2 starts at
450ms; stabO2 frame1 starts at350ms. Body delays remain canonical. Pending swings finish without locking motion.

Basic attacks use the same physical bounds, live PDD and crit rule as physical skills (6.1), with skill multiplier 1.
W.Att sums every worn item's `incPAD` plus active `watk` buffs; `weapon_attack(ranged)` adds the current ammo's `incPAD`
for a ranged attack (6.1.2).
The action prefix chooses swing/stab/shoot; weapon facts are `WeaponInfo.PHYSICAL` (tier B, except the preserved
wand/staff and bare-hands fallback, tier C):

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

The three creation weapons and bare hands keep their old non-critical bounds. Bare hands still use equipment-only
PAD (usually zero, so defence floors the hit to 1); the Pirate unarmed formula is outside this ticket.
Starting STR12/DEX5 reaches STR22/DEX5 at Beginner Lv3 without balance changes;
Sword bounds then are 2.1964..15.81, so rounding to at least the unscaled Snail's 8HP has about61% probability.
The fixed-seed 1000-swing test checks at least50%. Variant0 for every weapon, and normal sword/mace
spark family1 for swings / family2 for stabs, are tier C selections. Bounds, canvases, origins, alpha and sound
come directly from the imported v83 afterimage and Weapon images (tier A). Effects use the existing pooled renderer.

**Weapons on the avatar (#154).** The held weapon decides three things, all from `WeaponInfo`:

- **Stances.** The character stands in `stand<info/stand>` and walks in `walk<info/walk>` of the weapon item
  (`stand_stance`, `walk_stance`; tier A). Most two-handed weapons have `stand2`/`walk2`; the two-handed swords stand with
  `stand2` but walk with `walk1`, so the two numbers are read separately. `PlayerMotion.stand_stance`/`walk_stance` hold
  them (`RunWorld._refresh_caster` refreshes them whenever the weapon changes), and `AvatarRenderer.play` turns the generic
  `stand1`/`walk1` into the worn weapon's variant for every screen that has no `PlayerMotion` (slots, shop, Free Market).
  Alert, jump, prone and the ladders are shared by every weapon.
- **Actions.** `WeaponInfo.BASIC_ACTIONS` lists the stances of each weapon type, in selection order; each action must also
  exist in the weapon item, the body and (melee) the afterimage, which `test_weapon_assets` checks against the real cache:

  | Family | Actions | Kind |
  |---|---|---|
  | one-handed sword, axe, blunt, dagger, wand, staff | swingO1/O2/O3, stabO1/O2 | swing / stab |
  | two-handed sword, axe, blunt | swingT1/T2/T3, stabO1/O2 | swing / stab |
  | spear | stabT1, stabT2, swingP1 | stab / swing |
  | polearm | swingP1, swingP2, swingT2 | swing |
  | knuckle | stabO1, stabO2 | stab |
  | bow / crossbow | shoot1 / shoot2 | shoot |
  | claw | swingO1/O2/O3 | shoot |
  | gun | shoot1 | shoot |

  Which stances a family uses is tier C (the item imgs list many more). `WeaponInfo.basic_kind(weapon, action)` is what the
  damage model (#153) reads: a ranged family always `shoot` (a claw throws with a swing stance, and `weapon_attack(true)`
  adds the ammo W.Att, 6.1.2), any other weapon the prefix of the action (`swing`, `stab`; `attack_kind`, which also
  maps the Gun's own `shot` stance to `shoot`). `BasicAttack.last_action` / `last_kind` expose the latest swing.
- **Effects.** The afterimage name, the sound (`info/sfx`) and the impact timing come from the weapon item and its
  afterimage (tier A); the hit spark is the sword family for every `sword*` afterimage and the mace family for all the others
  (tier C: `hit.img` has only those two). A melee weapon swings into its afterimage's `lt`/`rb` box. A ranged family has no
  such box: it starts when a target is inside `WeaponInfo.ranged_box` (bow, crossbow 300 px, claw, gun 250 px, tier C) and
  fires an ammo projectile (6.1.2), releases it on the afterimage's first frame when it has one (the Bow's and Crossbow's
  draw frame, else the body's last frame) and shows that frame as its trail only when it is not a melee box (a claw's `swordOL` trail
  and the Gun, which has no `shoot1` node, show none).

`scenes/debug/weapon_gallery.tscn` (tool-only; `bash scripts/run.sh res://scenes/debug/weapon_gallery.tscn -- --shots=<abs dir>`,
`--mode=cash` for a cash weapon cover over a two-handed sword and a claw) draws one sheet per family: stand and walk
facing both ways, and every basic-attack action frozen on its impact frame with the afterimage, spark and swing box.
`--mode=ammo` fires real ammo projectiles (6.1.2).

#### 6.1.2 Ranged basic attack and endless ammo (#155)

A bow, crossbow, claw or gun (`WeaponInfo.RANGED_FAMILIES`) starts its basic attack when a target is inside the family's
reach (6.1.1) and, at the release frame, spawns **one** projectile through `ProjectileSystem` at the nearest target
(a scheduled boss first, as for every basic attack). The shot carries the swing's physical damage (6.1), rolls on the
basic-attack stream 5 (`alt_rng`), is aimed at the target's centre at release, and ends after the family's reach plus
`overshoot` (`survivor/ammo.json`). A target that left the box before release gets no shot; the attack is not refunded
or consumed either way.

- **Ammo is endless.** It is never consumed, never an inventory stack, a card or a drop, and it is not saved: the
  current ammo is derived from the held weapon family, the job and the character level (`Ammo.item_for`).
- **W.Att.** The current ammo's Item.wz `incPAD` adds to W.Att for ranged attacks (`weapon_attack(true)`): Throwing Stars
  +15..+27, Bullet +10..+14, arrows +0..+4. A melee attack never adds it.
- **Starting ammo** (tier A ids): claw A Beginner Thief's Throwing Stars 2070015 (+15), bow Arrow for Bow 2060000 (+0),
  crossbow Arrow for Crossbow 2061000 (+0), gun Bullet 2330000 (+10).
- **Upgrade schedules** (the specialist branch and its advancements; a different branch, a first job, or a weapon of another
  family keeps the starting ammo; the highest step reached applies, also when the character advances into the branch past it,
  so Lv 37 straight into the Assassin is Mokbi):

  | Branch | level -> ammo |
  |---|---|
  | Assassin 410 | 30 Wolbi 2070001, 35 Mokbi 2070002, 40 Kumbi 2070003, 45 Tobi 2070004, 50 Steely 2070005, 55 Ilbi 2070006 (tier C levels) |
  | Hunter 310 | 30 Bronze 2060001, 40 Steel 2060002, 50 Red 2060003 (tier C) |
  | Crossbowman 320 | 30 Bronze 2061001, 40 Steel 2061002, 50 Blue 2061003 (tier C) |
  | Gunslinger 520 | 30 Split Bullet 2330001, 50 Mighty Bullet 2330002 (v83 `reqLevel`, tier A) |

- **Event and notice.** Reaching a higher tier with the same weapon family emits `ammo_upgraded` (ARCHITECTURE 4.4.3); a
  weapon swap is silent. `RunScene` shows the one-line system notice "Your throwing stars are now Ilbi Throwing-Stars"
  (the v83 String.wz item name).
- **Presentation.** The projectile sprite is the ammo item's own `Item.wz/Consume/<0206|0207|0233>.img/<id>/bullet`
  animation (arrows and bullets turn to their direction, stars spin in their frames). The Equip and Item windows' weapon
  tooltip has an `AMMO` line with the current ammo and its W.Att, e.g. "Kumbi Throwing-Stars (+21)".
- **Tool.** `weapon_gallery.tscn --mode=ammo` draws one sheet per family with a cell per tier (the avatar at release, the
  real projectile 0.1 s later, the sprite at 3x); `--branch=<job id> --level=<n>` shows the single ammo that job and
  level would fire. `ui_gallery.tscn --window=ammo` shows the upgrade notice and the Equip tooltip.

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
  roll for synthetic data. A miss emits `player_hit` with `miss=true`, zero damage and zero
  MP absorption, draws the original violet MISS, and causes no knockback, invincibility or hurt expression.
- On a landed hit: `NoViolet` digits over the player, knockback 187.5 px/s away and a small hop (tier C), 0.3 s of no input,
  invincibility with blinking for the current hit window, 1.5 s for a lone hit and shrinking to 0.4 s in a swarm
  (#88, tier C; section 11).
- **Active Magic Guard** moves `x`% (canonical 11-80% by level) of damage to MP while MP lasts.
- Regeneration is a 10 s pulse: +10 HP (tier C, owner choice) and +3 MP (tier B, v83 recovery rule), capped at each
  maximum. Improved MP Recovery 2000000 adds `floor(character level × canonical skill level / 10)` MP (tier B).
  Interval, amounts and divisor live in `balance.regen`. Recovery's separate timed HoT replaces the old passive
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

## 7. Skills (auto-cast and manual)

Shared skill-definition seams for spec #31 (no second-job content is enabled by these fields):

- Optional `cast: {"rule": "nearest"|"box"|"manual", "min_targets": 1}` (also `crowd`, `hp_or_undead`, and the Warrior's
  `weapon_reach` and `range_around`, 7.8) resolves to
  `Loadout.stats().cast_rule` (empty when absent) and `cast_params` (the whole block). Absent/`nearest` keeps
  nearest-in-range attacks and `can_start_buff` admission. `manual` never auto-casts; unknown rules wait too.
  `box` admits at `min_targets` (tier C default 1), then hits up to `mob_count` targets once per `attack_count` line.
  Admission prepares targets before the existing single MP payment/cooldown/cast; later rules extend the same
  `SkillRunner._admit_cast` / `_resolve_cast` dispatches with their own admission/resolution functions.
- Canonical level `lt`/`rb` resolve to `has_box` and `box: Rect2`; `area` starts at 1.0 and scales both offsets.
  `skill_mod` effects with `stat: "area", op: "mul"` multiply that scale (the planned ×1.2 card step is tier C).
  `mob_count` reads canonical `mobCount` then applies existing `count` modifiers; legacy `count` stays unchanged.
  `RunWorld.skill_box_targets(box, filter = Callable())` anchors at player feet, mirrors canonical left-facing x
  offsets when facing right, broad-phases through the spatial hash and intersects live bodies. It returns all
  matches with scheduled bosses first (#83), then by body-centre distance from the cast origin, then slot. Minimum
  edges include touching bodies;
  maximum edges exclude them. Optional `filter(slot) -> bool` runs before sorting/capping.
- Optional `on_hit: {"status": "poison"|"freeze"|"slow", "chance_field": "prop", "duration_field": "time"}`
  reads canonical fields at the cast level (missing `chance_field`: guaranteed attempt; signed Slow `x` stays
  canonical). Projectiles retain that level in a packed array. Both impact paths call `RunWorld._on_player_hit`
  once per damaging line, apply the status through `MobSwarm.apply_status`, then invoke registered
  `add_hit_listener(callable)` listeners with `(slot, {skill, level, magic, damage, element})`, before HP/kill
  resolution. Damage is after elements; physical hits participate, poison ticks and zero-damage immunity do not.
  Existing zero-damage `mob_hit` events for elemental immunity are retained for compatibility with the existing
  tests/presentation; the hook is suppressed regardless of that legacy event.
  Listeners must consume RNG only when their effect can apply.
- Optional `absorb_mp: {"chance_field": "prop", "percent_field": "x"}` enables monster MP absorption on
  damaging magic hits. The listener visits owned skills in loadout (learned) order and reads these canonical
  fields at each passive's current level: chance in percent, transfer as a percent of the monster's maximum MP.
  It truncates to whole MP, caps at remaining monster MP and consumes no proc RNG unless a positive transfer
  is possible. Branch-exclusive MP Eater learn cards allow only one copy per normal run, so this order matches
  the previous fixed F/P, I/L, Cleric key scan after unowned skills were skipped. Synthetic multi-passive loadouts
  follow learned order. Canonical values, restoration and absorb events are unchanged.
- `RunWorld.restore_player(stat: String, amount: int, skill: String) -> int` caps positive HP/MP gains, updates
  public pools and emits `player_restored: {stat, amount, skill, pos}` only for an actual positive integer pool
  change. The returned amount matches the displayed pool gain (HP rounds up, MP down, as elsewhere). Recovery
  and potions retain their existing paths. `DamageNumbers.HP_GAIN` uses cached `BasicEff/NoBlue1` then `NoBlue0`;
  `MP_GAIN` uses the same art tinted cyan. These digit sets exist in the v83 cache (tier A); assigning Blue to HP
  recovery remains tier C because the cache does not prove usage. Without Blue, tinted Violet is the tier C
  fallback. RunScene draws restoration events above the player's head using the existing number pool/timing.

Survivor behaviour is in `data/survivor/skills.json` (base) and `skills/<line>.json` (the skills); the canonical numbers per skill level come from `Skill.wz`.
A skill's **rank equals its canonical skill level**: every rank table covers levels 1 through the v83 maximum,
without skips. Learning starts at level 1 and each rank card adds one level. Energy Bolt, Magic Claw, Magic Guard
and Magic Armor have 20 levels, Improved MP Recovery has 16, Fire Arrow has 30, and the Beginner skills have 3.
The smaller per-card steps are intentional; canonical skill values remain untouched.
All skills pay the canonical `mpCon` of their current skill level on each successful cast (tier A). Three Snails
costs 3 / 5 / 7 MP at skill levels 1 / 2 / 3 (`Skill.wz/000.img/skill/0001000/level/N/mpCon`). Each tick auto-casts at most
one skill, oldest-ready first; learned order breaks a tie. A ready skill without a target or sufficient MP waits
without restarting its cooldown. An unaffordable skill permits a later affordable skill to fire. A waiting skill emits `mp_short` once
per waiting episode, while `player_state.mp_short` keeps the warm-red "Not enough MP" HUD cue visible until casting
can resume (tier C presentation). No MP is charged while climbing or when no target exists.

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
| Magic Guard (2001002) | Magician | Timed damage-to-MP split (`x`%) | ranks 1–20 = levels 1–20 | learn/rank |
| Magic Armor (2001003) | Magician | Timed PDD (`pdd`) | ranks 1–20 = levels 1–20 | learn/rank |
| Improved MP Recovery (2000000) | Magician | Adds `floor(character level × skill level / 10)` MP to each 10 s pulse | ranks 1–16 = levels 1–16 | learn/rank |
| Improved MaxMP Increase (2000001) | Magician | Passive: computed Max MP × `(1 + 0.02 × skill level)`, preserving current MP ratio on growth (tier C reinterpretation) | ranks 1–10 = levels 1–10 | learn/rank |
| Holy Arrow (2301005) | Cleric | Holy projectile at nearest mob: canonical mad/mastery/mpCon and element h; 1 s recast, 480 px reach, 520 px/s, radius 12 | ranks 1–30 = levels 1–30 | learn/rank; +1 projectile (3 steps), +1 pierce (2), cooldown ×0.88 (3); job 230 only |
| Heal (2301002) | Cleric | Instant self recovery below 50% HP OR holy damage to every undead intersecting canonical lt/rb; 2 s recast, canonical mpCon/hp; provisional historical stat-based recovery fit, exact v83 amount unresolved ([evidence](research/cleric-heal.md)) | ranks 1–30 = levels 1–30 | learn/rank only; job 230 only |
| Fire Arrow (2101004) | F/P Wizard | Nearest-target fire (`elemAttr f`) projectile every 1 s within 480 px, 520 px/s, radius 12 px, `shoot1` stance 0.8 s; canonical `mad`/`mastery`/`mpCon`, ball/hit/effect and Use sound | ranks 1–30 = levels 1–30 | learn/rank; Extra Fire Arrow (+1 shot, ×3), Fire Arrow Pierce (+1 pierce, ×2), Quick Fire Arrow (cooldown ×0.88, ×3) |
| Poison Breath (2101005) | F/P Wizard | Nearest-target poison (`elemAttr s`) projectile every 1.25 s within 450 px, 400 px/s, radius 14 px, `swingO3` stance 0.8 s; canonical `mad`/`mastery`/`mpCon`; `on_hit` applies poison with canonical `prop`% for `time`; cached ball/hit/effect and Use/Hit sounds | ranks 1–30 = levels 1–30 | learn/rank; Poison Breath Pierce (+1 pierce, ×3), Quick Poison Breath (cooldown ×0.88, ×3) |
| Meditation (2101001 / 2201001) | F/P / I/L Wizard | Self-only timed canonical `mad` -> magic attack; invalidates cached attack ranges on start/expiry | ranks 1–20 = levels 1–20 | branch-specific learn/rank only |
| Bless (2301004) | Cleric | One timed buff: canonical `pdd`, `mdd`, `acc`, `eva` -> weapon/magic defence, accuracy, avoid; accuracy joins the player's ACC and raises the critical chance (6.1) | ranks 1–20 = levels 1–20 | learn/rank only |
| Invincible (2301003) | Cleric | Canonical `x`% reduction of physical/touch damage before Magic Guard; magic damage unaffected | ranks 1–20 = levels 1–20 | learn/rank only |
| Slow (2101003 / 2201003) | F/P / I/L Wizard | At least 3 eligible unslowed mobs in canonical `lt`/`rb`; nearest-first up to `mobCount`, signed canonical `x` for `time`, 1 s recast delay | ranks 1–20 = levels 1–20 | branch-specific learn/rank only |

| Teleport (2101002 / 2201002 / 2301001; `teleport_fp` / `teleport_il` / `teleport_cleric`) | F/P / I/L / Cleric | Manual X: arrow direction, otherwise facing. Horizontal blink lands on a floor up to canonical range, stopped by walls/map limits; vertical blink needs a floor strictly above/below within range. Ground/air allowed; climbing blocks it. Successful blinks pay canonical MP and emit fixed departure/arrival effects and Use sound. Hold repeats every 0.3 s (tier C); invalid destinations and short MP spend nothing. HUD shows X and dims when unaffordable. | ranks 1-20 = levels 1-20; `mpCon` 60 to 13, `range` 130 to 150 px (tier A, all three books) | branch-specific learn and rank cards only; no grant or slot cap |
| MP Eater (2100000 / 2200000 / 2300000) | F/P Wizard / I/L Wizard / Cleric | Passive: each resolved magic hit may absorb canonical `x`% of the monster's max MP with canonical `prop`% chance; remaining monster MP and player Max MP cap the transfer | ranks 1–20 = levels 1–20, separate branch copies | learn/rank only |
| Cold Beam (2201004) | I/L Wizard | Instant ice hit on the nearest target within 300 px every 1.25 s; canonical `mad`/`mastery`/`mpCon`; guaranteed freeze attempt for canonical `time` (1–2 s), rejected by bosses and ice-status immunity; real `effect` and `hit/0`, no `ball` | ranks 1–30 = levels 1–30 | learn/rank; Spreading Frost (+1 target, 3 steps), Quick Frost (cooldown ×0.88, 3 steps) |
| Thunder Bolt (2201005) | I/L Wizard | Instant lightning hits when at least one monster intersects the canonical `lt`/`rb` box around the player's feet; up to canonical `mobCount` (6), nearest first, every 1.5 s; canonical damage/mastery/MP; real `effect` and `hit/0` | ranks 1–30 = levels 1–30 | learn/rank; Wider Storm (box offsets ×1.2, 3 steps), Forking Storm (+2 targets, 3 steps; tier C), Quick Storm (cooldown ×0.88, 3 steps) |

MP Eater registers on the shared player-hit listener, after on-hit statuses and before lethal damage/kill handling.
It reads the passive's current canonical level at impact; physical basic attacks, Three Snails, poison pulses and
elementally immune hits cannot absorb. It consumes no proc RNG when unlearned, depleted, or unable to absorb even
one whole MP. Absorb truncates `maxMP × x / 100` to whole points (tier C integer interpretation), caps at remaining
monster MP, and drains that pool even when player MP is full. `restore_player` supplies the actual capped gain and
the shared `player_restored` MP number. A separate `mp_eater_absorbed: {mob, amount, skill, pos}` event shows the
canonical 700 ms effect on every absorb, including zero player gain; it does not duplicate the restoration event.
The cache has all three effects and icons. Original v83 Sound.wz has no MP Eater entry, so presentation quietly
probes for an optional use sound and otherwise stays silent without a missing-asset lookup.

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

Guard and Armor auto-cast only when inactive, pay canonical MP cost, and last canonical `time` seconds at the
cast's skill level. L1 Guard costs 6 MP for 111 s at 11% absorption; L1 Armor costs 8 MP for 54 s at +2 PDD.
They recast on expiry when affordable. Their timers and effects continue while climbing; no cast starts there.
Effects are snapshots of the cast rank, so a rank upgrade changes the next cast. Active Guard alone splits damage;
active Armor alone adds its canonical PDD through the hit-defense hook. The HUD shows v83 skill icons and countdowns.
Rank cards preview duration, absorption/defense and MP cost. Both are passive-category skills without slot caps and share the one-cast-per-tick
readiness ordering with attacks. The alert2 stance comes from v83 skill action data; its 800 ms hold is tier C.

Second-job support (#58): `buff.effects` accepts multiple canonical stat/field pairs alongside legacy scalar
`stat`/`field`; every skill retains one timer/icon and snapshots all effects at cast rank. Meditation, Bless and
Invincible use their canonical `alert2`, effect and Use sound. Their self-only auto-cast, expiry, affordable recast
and climbing gate follow Guard/Armor. Bless's active avoid feeds each miss roll; active PDD/MDD feed hit defence.
Invincible scales the already-resolved whole weapon hit, rounds to nearest and keeps minimum 1 before Guard.
Bless's `acc` joins the player's ACC (`player_state.acc`), which raises the critical chance (6.1, #153; before #153 it
had no combat effect).

Slow uses the shared box query with a status-eligible, unslowed filter before charging MP. Canonical or scheduled
bosses cannot count toward the crowd. It applies through `MobSwarm.apply_status`, deals no hit damage and does not
invoke damaging-hit listeners. Tier A String.wz text limits consecutive uses on the same monsters to two; our
tier C auto-cast reading counts consecutive **successful Slow casts affecting each logical mob**, shared across
the two branch copies. A third consecutive application is ineligible until a successful Slow cast excludes that
mob. Time, other skill casts, insufficient MP and failed admission do not break that sequence. Relocation preserves
the history; fresh spawns reset it. The status interface itself still allows refresh for other callers.
Crowd threshold 3, cooldown 1 s, stance hold 0.8 s and card learn/rank weights 3/2 are untuned survivor choices.
All six skills retain the existing support bot scores (learn 50, rank 42 + current/ancestor job bonus 12), below
damaging attack cards. No behaviour cards are added.

### 7.5 Weapon-gated skills (#156)

A skill may need a weapon family (`WeaponInfo.FAMILIES`: sword, axe, blunt, dagger, wand, staff, spear, polearm, bow,
crossbow, claw, knuckle, gun; `""` = bare hands). `SkillBook.weapon_families(key)` returns the families that can use it
(empty = any weapon, bare hands included) and `SkillBook.usable_with(key, family)` answers for the held family
(`RunWorld.held_weapon_family()`). The requirement comes from, in order:

1. Survivor `skills.json` `weapon_families` (tier C): an array of family names, or `["any"]` for a skill that is
   explicitly any weapon. It overrides the canonical value, so a class spec tags untagged skills (Somersault Kick and
   Grenade: `["any"]`; Flash Fist and the Brawler attacks: `["knuckle"]`; Masteries, Boosters and Final Attacks: their
   named family) and can retag a canonical one.
2. The Skill.wz `weapon` code (tier A), mapped with `WeaponInfo.family_of_skill_code` (type - 100: 30 and 40 are both
   "sword", 47 is "claw"). The reader also accepts the key `"weapon "` with a trailing space (tier A: the WZ typo that
   only 5001003 Pirate Double Shot has). A missing field or an unknown code means no requirement.

Where it applies (all read the same two functions, never a second rule):

- **Casting.** `SkillRunner.cast_ready` skips an owned active skill the held weapon cannot use: no MP is spent, no
  shortage is signalled, and the cooldown keeps running, so the skill casts on the first tick a matching weapon is held
  again. A manual skill is refused the same way (no manual cast exists yet). Buffs already running keep running
  (tier C). A passive's weapon check is done where its effect is read (`Loadout.passive_total`, see 7.6).
- **Cards.** `UpgradePool.is_eligible` rejects every card with a `skill` (learn, rank and behaviour cards) while the
  weapon held when the draw rolls cannot use that skill; the advancement draw reads the same eligibility. Taking a card
  does not re-check it.
- **Skill window.** A skill the held weapon cannot use is drawn like an unlearned one (the v83 `skill0` plate, its own
  `iconDisabled`, grey text), and its tooltip adds "Weapon : Claw" (red "(not held)" while unusable; tier C text).
  `SkillWindowModel.usable(key)` is read live, so swapping weapons with the Equip window open updates it.
- **Swapping** weapons by hand in the Equip window takes effect at once (nothing caches the family). The bot never
  swaps weapons by hand.

No shipping Magician or Beginner skill has a requirement (wand and staff skills are untagged), so their records are
unchanged. Tier C summary: the `weapon_families` override and its `"any"` marker, the "buffs keep running" rule and the
tooltip wording; tier A: the `weapon` field and its typo key.

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
`scale` (default 1), so Rage's weapon-defence penalty is `{"stat": "pdd", "field": "pdd", "scale": -1}` (check the sign
Skill.wz stores when the Warrior spec lands) and lowers `hit_defense().pdd` while it lasts.

**Final Attack.** A passive skill with `final_attack: {"chance_field": "prop"}`, `damage: "physical"` (the canonical
`damage` is the follow-up's skill percent) and an `action` (the stance whose swing/stab/shoot kind picks the bounds).
After a damaging physical line (basic attack, instant skill or shot) while a matching family is held, it rolls `prop`
percent on RNG stream 12; on a hit it queues one follow-up on the same mob, played at the end of that tick's attacks
(`final_attack` event, then a normal `mob_hit` of the skill with live PDD, level gap and crits, all rolled on stream 12).
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
number of steps *faster* (positive; the v83 Boosters are 2; a real Booster entry must check the sign Skill.wz stores for `x`
and use `scale` if it is negative, as for Rage's WDEF). It is an ordinary auto-cast buff: cast when inactive, ready and
affordable, recast the tick after it expires (its cooldown is its duration), with the duration from Skill.wz `time`. It is
gated like a passive: `RunWorld.attack_speed_boost()` counts a running Booster only while the held weapon family fits
the skill's `weapon_families` (`SkillBook.usable_with`, 7.5). A weapon swap does not cancel the buff, it just stops
counting (a Sword Booster does nothing to a Wand) until a sword is held again. `Loadout.weapon_speed` and
`Loadout.speed_steps` are the two caster inputs, assembled in `RunWorld._refresh_caster` (a buff starting, expiring or a
weapon change refreshes them and the cached skill stats). Only synthetic Boosters exist today (`test_attack_speed.gd`);
the real ones come with the class specs.

### 7.8 Warrior first job (100, #163)

Six v83 skills from `Skill.wz/100.img` (book 100; canonical level counts, MP/HP costs, icons, effects and sounds), all in
`skills/warrior.json`. Rank equals canonical level as everywhere (7); WZ prerequisites are ignored (tier C, #31).

| Skill | Kind | Behaviour | Tiers |
|---|---|---|---|
| Power Strike 1001004 (20) | attack | auto-casts at the nearest mob inside the held weapon's swing envelope; hits `mob_count` mobs (1; only the Cleaving Strike card adds); damage 165-260 % of the physical weapon damage | A: damage %, mpCon 4-12, attackCount 1, art, sound; B: damage formula; C: Warrior melee families only (sword, axe, blunt, spear, polearm), 1.0 s cooldown, 0.6 s stance |
| Slash Blast 1001005 (20) | attack | auto-casts when a mob's body centre is within `range` (130, 150 from level 16) of the body; hits up to `mobCount` 6 nearest, bosses first, both sides; pays hpCon 8-16 and mpCon 6-14; never casts when the HP cost would leave 0 HP (and then pays nothing) | A: damage 72-130 %, range, mobCount, hpCon, mpCon; C: weapon families, 1.6 s cooldown, 0.6 s stance, wider range / more targets only from cards |
| Iron Body 1001003 (20) | buff | auto-cast, recast on expiry; adds canonical pdd (2-40) to weapon defence for 75-300 s | A: pdd, time, mpCon, action alert2 (no effect art in the WZ node); C: auto-cast, 0.8 s stance |
| Improved HP Recovery 1000000 (16) | passive | adds canonical `hp` (3-50) to every regeneration pulse (`regen: {pool: hp, field: hp}`, `Loadout.regen_bonus`) | A: hp; C: v83 only while standing still, here always (HP regeneration is always on) |
| Improved MaxHP Increase 1000001 (10) | passive | `max_hp_per_level` (canonical `x`, 4-40) at every later level-up (7.6) | B: Cosmic level-up rule |
| Endure 1000002 (8) | passive | its own clock heals one base regeneration pulse (`balance.regen.hp` + `hp_regen`) every canonical `time` (31 s down to 10 s) while hanging on a rope or ladder (the clock counts only climbing seconds and keeps its value when the character lets go; `climb_regen`, emits `player_restored` with skill `endure`) | A: time; C: the amount and the on-top-of-regeneration reading of v83's rope recovery |

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
  `RunWorld.can_pay_hp` refuses (HP must stay above 0; no `mp_short`, nothing paid), then pays MP and HP together
  (`RunWorld.spend_hp`). The bot counts a skill ready only when both costs are payable.
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
- **Previews.** Rank cards show `damage` (percent) and `hpCon` beside the existing fields; the three passives show their
  own number (Max HP per level-up, HP per pulse, seconds between recoveries) instead of the canonical field name
  (`UpgradePool.PASSIVE_*`). The skill tooltip adds "HP cost" for an HP-paying skill.
- **Fixture.** `tests/fixtures/characters/lv11_warrior_1st.json`: a real headless Henesys bot round, forced job 100, seed 1,
  stopped at 295 s, just before the first boss (`tools/character_fixture.gd --job=100 --seconds=295 --label=spec151/ticket-163`; capped rounds of
  seeds 1 and 2 that ran past 5:00 ended with the Warrior bot dead to that boss's touch hits; recorded for the balance
  pass, not tuned).

## 8. Upgrades

`data/survivor/upgrades.json` (base) and `upgrades/<line>.json` (the cards). Each upgrade card has: `id`, `kind` (`skill_new`, `skill_rank`, `skill_mod`, `passive`,
`stat`, `potion_tier`, `filler` for the separate fallback), `skill` (for skill cards), `icon` (a WZ path, e.g. `Skill.wz/000.img/skill/0001000/icon`), `name`,
`desc` (with `{value}` placeholders), `max_rank`, `weight`, `requires` (job ids, owned skills, min skill rank, min
level), `effects` (`{"stat": "count", "op": "add", "value": 1}`).

Draw rules:

1. Eligible = requirements met and rank < max, and the held weapon can use the card's skill (section 7, weapon-gated
   skills). `requires.jobs` matches the **exact current job id**, never its
   ancestors or descendants. Beginner skill cards (Three Snails changes, Recovery and Nimble Feet) require job 0;
   Magician skill cards require job 200. Earlier-job skills stay learned and keep casting at their retained rank,
   but their cards stop appearing. Job-neutral magnet and potion-tier cards omit `requires.jobs`.
   `skill_new` needs an unowned skill. Active and passive skill counts have no caps; only job eligibility and each skill's maximum rank bound the pool.
2. Three distinct cards are drawn by weight with the run's seeded RNG.
   **Pity:** cards that raise an attack skill's damage output carry `"power": true` (a new attack skill, its rank,
   more shots or targets, damage, cooldown). When a draw offered no power card, the next draw starts with one
   (`pity.draws` = 1), so a run's damage cannot stall on unlucky offers (a reviewed seed never saw an attack card
   before Lv 8 and fell behind for good). Both pity and the advancement draw select only eligible cards
   from the current pool; if no eligible power card exists, pity adds none.
3. With fewer than three eligible cards, offer those cards plus **one Power Elixir** alternative (item 2000005).
   With no eligible cards, offer Power Elixir alone. This applies to normal level-ups and boss rewards; every
   reward opens a window. `upgrades.fallback` holds the job-neutral Elixir definition outside the weighted pool,
   so it never displaces a normal card in a full draw. It uses the canonical Power Elixir name and icon and fully
   restores HP and MP immediately when chosen, without changing carried potion stock. This reward rule is tier C;
   the item identity, art and 100% restoration are tier A.
4. Applying a card takes effect immediately.
   Rank cards declare `max_rank` as the canonical skill cap; eligibility also checks the owned skill level.
   A skill learned at level 1 therefore needs N−1 **Normal** rank-card picks to reach level N; higher tiers grant
   several levels. The window marks the final skill level `MAX`, independently of consumed card steps.
5. The level-up window keeps the "You've gained a Level!" header and mascots, masks the baked-in skill-raising
   sentence for every card, and reads "LEVEL n". Rank cards show the canonical level change ("Skill Lv. 2 → 3")
   and before → after Magic ATT, mastery percent, MP cost and fixed damage when those fields exist in the skill's
   WZ level data. These previews use canonical values without survivor modifiers (tier A); mastery is converted
   with the combat formula in section 6.1.

**Hit-more-mobs rule (#84).** Every attack skill has at least one `skill_mod` card that raises how many monsters it
can hit: more shots or targets (`count`) or `pierce`. This holds for future jobs too. Support and movement skills
are exempt and listed by name in `test_data_files.gd` (`HIT_MORE_EXEMPT`): Heal, both Slows and the three Teleports.
`test_every_attack_skill_has_a_hit_more_mobs_card` fails for any damaging or active skill that is neither covered
nor exempt.

| Skill | Hit-more-mobs card(s) |
|---|---|
| Three Snails | Additional Shell (`three_snails_count`), `three_snails_pierce` |
| Energy Bolt | `energy_bolt_count`, `energy_bolt_pierce` |
| Magic Claw | `magic_claw_targets` |
| Fire Arrow | `fire_arrow_count`, `fire_arrow_pierce` |
| Poison Breath | `poison_breath_pierce` |
| Cold Beam | Spreading Frost (`cold_beam_targets`) |
| Thunder Bolt | Forking Storm (`thunder_bolt_targets`): +2 targets per step, 3 steps (canonical `mobCount` 6 → 8 → 10 → 12), weight 2; tier C placeholder until the balance pass |
| Holy Arrow | `holy_arrow_count`, `holy_arrow_pierce` |

### 8.1 Fortune and Potential tiers (#30 / #43)

Fortune is a survivor run stat in `player_state.fortune`, separate from canonical LUK. Its base is
`balance.player.fortune` (0) plus card modifiers, plus (spec #34) the live Fortune of the character's filled cash slots
(`player_state.fortune` = own Fortune + `RunWorld.cash_fortune`). Only cash items the account owns count; anything
else worn is ignored with a world warning. The cash part is never written into the CharacterSnapshot (`base_fortune`
and `fortune` stay the character's own), so it cannot compound across rounds; values per slot are in section 11. It changes only card rarity, leaving
drop and critical rolls untouched. Every scalable offered card, including every advancement-draw skill, rolls a tier
using the existing seeded card RNG stream 3 after card identities are selected. A choice retains its final `tier`
and `magnitude` while pending; selecting its id applies that tier's ranks/steps.

| Potential tier | Normal | Rare | Epic | Unique | Legendary |
|---|---|---|---|---|---|
| Base weight at Fortune 0 | 75 | 18 | 5 | 1.7 | 0.3 |
| Skill rank gain | +1 | +2 | +3 | +5 | all remaining ranks |
| Stacking steps (`skill_mod`, `stat`, `passive`) | +1 | +2 | +3 | +4 | all remaining steps |
| New skill starting rank | 1 | 2 | 3 | 4 | 5 |

All numbers and rules in this table are tier C survivor choices. `upgrades.rarity.weights` stores the spec #30
weights (the owner restored them on 2026-10-15 after the C46 calibration had used 86/8/3.5/1.7/0.8; tuning waits for
the balance pass). Every non-Normal weight is multiplied by `1 + max(0, Fortune) × upgrades.rarity.fortune_scale`
(0.02), then weights normalize together: at Fortune 100 the weights total 150, i.e. 50/36/10/3.4/0.6%.
`upgrades.magnitudes` holds the per-kind tables; every default tier gives more than the one below it (owner,
2026-10-15). An individual card's `magnitudes` can override any tier, with unspecified tiers retaining their kind
defaults. Legendary can max a 20-rank attack or buff in one pick.

A card whose requested magnitude exceeds remaining headroom drops to the highest fitting tier, and any tier whose
gain equals a lower tier's (Legendary's `max` spending the last steps, or an equal per-card entry) wears the lowest
such label, so a label never overstates the card: a rank card at 17/20 rolling Legendary shows Epic (+3), at 15/20
Unique (+5), at 16/20 Legendary (+4); an Epic at 18/20 shows Rare (+2). Stacking cards cap at 2–4 steps, so a fresh
cap-2 card shows at most Rare, a cap-4 card at most Unique, and no current stacking card can show Legendary.
Nimble Feet and Recovery (3 ranks) learn at most at Epic. An unlimited stacking card downgrades a `max` roll to
its highest finite tier. All tier C.

Boss bonus rolls promote Normal to Rare before clamping. Scalable cards that cannot retain at least Rare are
omitted from boss draws (e.g. a skill rank card with only one rank remaining). Potion-tier cards and Power Elixir
are always Normal, including at bosses; sparse or exhausted rewards still offer the Elixir. Tier C.

Stacking magnitudes consume several card steps, preserving the card cap. Additive effects add their value once per
step; multiplicative effects compound (four cooldown ×0.88 steps reduce cooldown by 40.03%). Card text shows
compounded percentages to two decimals; application keeps full precision. `choice_card` previews the final skill
level and canonical before/after values at the complete gain; `rank_before/rank` show consumed card steps.

The balance record has `card_tiers_offered` and `card_tiers_picked` per run (displayed tier after clamping, one
count per card); the SYSTEMS summary sums them.

Level-up and boss-reward cards keep the v83 skill-row art and show the tier with a 2 px frame and a label band
tinted with the tier colour: Normal white, Rare blue, Epic purple, Unique gold, Legendary green
(`#FFFFFF / #77BBFF / #CC99FF / #FFCC44 / #77DD88` over `#17344F` at 30%; tier C). The label carries the meaning
independently of colour. New skills show their starting level in the rank line (`NEW  Skill Lv. 5`, plus `MAX` when
that is the cap). Unchanged canonical values are omitted from the preview. Dense windows shorten prose first and
keep the panel 128 px shorter than the view so the mascots and HUD stay clear (tier C layout).

A window with a Unique or Legendary offer plays `Sound.wz/Game.img/mCardGet` once when it opens (owner-approved by
ear on 2026-10-15; `EnchantSuccess` was reserved for scrolling and is now played by it, #110). Automated picks without a window are silent.
The debug gallery shows the tiers with `--window=levelup_tiers|levelup_high|levelup_dense` (`--bonus` for the boss
heading); screenshots stay in ignored `evidence/spec30/ui/`.

Beginner cards include Nimble Feet (1002) and Recovery (1001) learn/rank cards. Nimble Feet occupies a passive slot
and auto-casts when inactive, off its canonical cooldown and affordable. It keeps the cast level's canonical speed
bonus for the canonical duration, shows the v83 buff icon/countdown, and pays canonical MP. The 60-second cooldown
starts on cast: expiry after 4/8/12 seconds leaves 56/52/48 seconds before it is ready again. No cast starts while
climbing; its active effect and cooldown keep advancing there. Its original effect/sound/icon are used; no stance
is imposed because v83 provides no action node. Auto-casting and slot/lifecycle rules are tier C; the skill values
and assets are tier A. The former flat +6 speed card and Max HP +10% card are removed.

Magnet's Normal step is +25% radius and stays job-neutral. Magicians learn Improved MaxMP Increase (2000001) at
their card's starting rank and rank it through level 10 with the tier gains above. Its tier C, owner-selected reinterpretation multiplies the computed Max MP
(level growth, Magician INT/10 growth and job grant included) by `1 + 0.02 × skill level`, rounded once to whole MP.
This is +2% through +20%, recalculated from the base on every recompute rather than compounded or granted once.
Current MP keeps its ratio when the maximum grows from learning/ranking, level growth or a job grant. The canonical
skill instead raises MP gained per level; no canonical values are edited. The old flat +25 Max MP card is removed.
Rank previews show the survivor Max MP percentage rather than the canonical per-level gain.

Improved MP Recovery (2000000) is an owned canonical passive skill, learned/ranked by the tier tables through level 16,
adding the level-scaled pulse bonus in section 6.2.

Recovery casts only below 50% HP and when off cooldown, paying canonical MP. Its duration is 30 seconds, with
six pulses at 5/10/15/20/25/30 seconds; the last heals before expiry. The 5-second interval and `x × 6` reading are
tier C interpretation, recorded with the threshold in `skills.recovery.buff`; MP cost, `time`, `x` and `cooltime`
are unchanged v83 values. The 120-second cooldown starts at cast, so the inactive wait after the HoT is 90 seconds.
No cast starts on a rope, while an existing Recovery continues healing and expires there. Its original cast effect,
sound and icon are used; rank previews show duration, HP per pulse, cooldown and MP cost. Learning/ranking Recovery
never adds permanent HP regeneration, and the skill remains available after advancement.

Potion tiers are one-time cards: HP Red (2000000) → Orange (2000001) from Lv 10 → White (2000002) from Lv 25;
MP Blue (2000003) → Mana Elixir (2000006) from Lv 20. Each requires its previous item, preserves the entire stock
count and changes all future drops of that kind. The current item drives canonical restoration and the HUD icon.
The ladders, level gates and weights are tier C entries in `upgrades.json` (`potion_kind`, `item_id`,
`requires.potions`, `requires.min_level`); no canonical item value is changed. The sensible bot scores tier cards at
the configured `potions.bot.tier_score` (currently 112), with fallback 52 when absent; first/random policies can
offer and take them normally.

Skill prerequisites (`Skill.wz` `req`) are ignored (tier C owner decision #31). Cards retain their exact
job requirement and rank/modifier cards still require the skill they upgrade. Skills learned in an earlier job keep
working after advancement; their job-restricted cards leave the pool.

Accepting any job opens an **advancement draw** before the normal level draw, without consuming the queued level.
It offers every eligible new attack (`skill_new`, `power: true`, `requires.jobs` containing the new job), even if there
are more than three. If fewer than three attacks exist, seeded weighted draws fill the remaining places with that
job's other eligible new skills. Sparse draws include one Power Elixir; an exhausted job pool offers it alone.
Each scalable card rolls the usual rarity tier and contributes to offered/picked tier telemetry. No skill is granted.
`choice_pending.advancement` identifies this draw independently of `bonus`; the window reads "Job Advancement".
"Not now" goes directly to the normal level draw.

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
- Cards keep their `upgrades.json` text where the cache has no String.wz (and for stat, potion and Elixir cards).
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
| Improved MaxMP Increase (2000001) | desc, h | survivor reinterpretation: +2% Max MP per level, not MP per level-up / AP (its WZ desc is also malformed) |
| Improved MP Recovery (2000000) | h | the WZ line has no number; states the floor(character level × skill level / 10) MP every 10 s |
| Heal (2301002) | desc | party healing: here it heals you below half HP and strikes every undead in its box |
| Meditation (2101001, 2201001) | desc, h | "party members": self-only |
| Bless (2301004) | desc | "party members", "cannot be combined": self-only; its accuracy raises the critical chance (6.1) |
| Teleport (2101002, 2201002, 2301001) | desc | "arrow keys": the Teleport key plus a direction, hold to repeat |

### 8.3 Mesos, equipment drops, scrolls and shops (spec #33)

The economy loop, in the order a character meets it (terms: `GLOSSARY.md` "Mesos and equipment"; decisions: ADR 0002;
every constant, with its tier, is in section 11 under the tables named below):

1. **Mesos** drop from kills (40% per kill from the mob's v83 meso range, x14 survivor multiplier) and 4 bundles from
   each boss, with the v83 coin sprites; the magnet collects them like EXP. They are carried across rounds with the
   character and lost with the run. ("Meso rule", section 11.)
2. **Equipment** drops from kills (0.2% per ordinary kill, one guaranteed from each boss): a v83 hat, top, bottom,
   overall, shoes, gloves, shield or weapon that the character's current job can wear, near its level, with v83's random
   stat rolls. A weapon drops only from the family of the weapon held when the drop rolls (a sword holder gets one- and
   two-handed swords, an axe holder axes, ...; bare hands get no weapon; a Magician holding a wand or a staff gets both),
   so a Warrior's weapon drops are of the one family it holds (sword, axe, blunt weapon, spear or polearm) and its armour
   drops include Warrior shields (#159). It goes to the
   Equip tab (24 slots; a full tab leaves the item on the ground). ("Equipment drop rule".)
3. The **Equip** (E) and **Item** (I) windows wear, take off and discard it, in a round (the run is held while they are
   open) and in the Free Market; worn equipment adds to the character's stats and is what is drawn. (Controls above.)
4. In the **Free Market**, four NPCs sell scrolls only, one per success rate (100%, 60%, 10%, dark 70% / 30%), at 35,000
   mesos (armour, shield) or 70,000 (a weapon: wand, staff, sword, axe, blunt weapon, spear, polearm); any shop buys spare equipment and scrolls back at their v83 sell price. NPC
   Chat (Space) or a double-click opens a shop. ("Scroll NPCs", "Shop stock", "Sell rule" and the other #111 rows.)
5. A **scroll** is dragged from the Use tab onto a worn item: it succeeds at its rate (adding its v83 stats and one to
   the "(+N)" count) or fails; either way it spends one upgrade slot, and a failed dark scroll can destroy the item.
   ("Scroll rules", "Scroll effect" and the other #110 rows.)
6. Everything is saved with the character at each boundary, so Save & quit -> Continue restores mesos, worn equipment,
   inventory and scrolls. Quitting a round and continuing replays it from its boundary, so what changed mid-round is
   lost (ADR 0001, amended).
7. Bots follow the same rules (`BotShop`): they wear the best item they own and visit the shops between tiers of a
   `balance.sh --tier=N` chain. ("Bot shopping rule".)

Verified end to end by `flow_driver --scenario=economy` (AGENTS.md) and by the combined regression smoke in 4.2
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
whichever pet is out: Auto HP / MP Potion Pouch drink from the character's stock below the HP / MP ALERT levels set in
Options (defaults 30 % / 20 %), Wing Boots fetch resting drops, Binocular doubles the pickup radius, and VAC pulls every
drop on the map to the pet while the Magnet card is no longer offered.

**Tools.** Tool rounds (balance, playtests, `--run`) start with an empty account; `--account=<json>` supplies owned items,
worn cash equipment, a pet and ALERT levels (`game/tests/fixtures/accounts/full_pet.json` is the full set) and the round
record gains `nx_awarded`, which is never credited. With an empty account every record is byte-identical to a build
without this feature (regression smoke, section 4.2).

## 9. Jobs

`data/canonical/jobs.json` holds the Explorer tree with canonical ids (Beginner 0; Warrior 100, Magician 200,
Bowman 300, Thief 400, Pirate 500; second jobs 110-130 / 210-230 / 310-320 / 410-420 / 510-520; third and fourth
jobs). `data/survivor/jobs.json` marks which are playable in this build and what advancing grants. Its optional
`level` overrides the advancement level for survivor mode. Magician uses 10 (tier C, owner choice, #40);
the canonical record keeps level 8 and INT 20. Existing INT handling is unchanged: advancement redistributes
earned AP to INT rather than adding a stat eligibility gate.

At an advancement level the level-up window is preceded by the **Job Advancement** window (UI.wz window frame, job
book name from `String.wz/Skill.img/<job>/bookName`, `BasicEff.img/JobChanged` + `Game.img/JobChanged` on accept):

- Levels 8–9: ordinary upgrade choices; no job window.
- Level 10: Magician and Warrior (Dances with Balrog, #163) are playable; Bowman, Thief and Pirate are shown as "not in this build".
  "Not now" keeps you a Beginner and asks again next level.
- Advancing to Warrior changes job to 100 and adds +225 Max HP (tier B: the v83 first-job +200-250, midpoint); it
  teaches no skill and gives no weapon (the creation sword, axe or club stays). Earned AP go to STR (the Warrior has no
  secondary stat row: no Warrior weapon or shield in the cache needs DEX), growth is 26 HP / 5 MP per level (tier B,
  Cosmic), and the extra advancement draw offers Power Strike and Slash Blast plus one other new Warrior skill.
  The Warrior's second jobs (Fighter, Page, Spearman) stay "Not in this build".
- An **unforced bot** (no `--job`) picks a seeded random available first job on the job stream (8), so with the Warrior
  and the Magician both open it takes either (spec #151, `BotInput.pick_choice` as #157 left it); `--job=100` /
  `--job=200` force one. Unforced Lv 10 runs and records therefore differ from before the Warrior existed.
- Advancing to Magician changes job to 200 and keeps the existing +120 Max MP bonus; it teaches no skill.
  The extra advancement draw includes Energy Bolt, Magic Claw and one other new Magician skill before the normal draw.
- The JobChanged pillar and sound play on the character first; the advancement draw opens once the effect has
  played (~1.3 s), then the level's normal draw follows. A level-up window opens 1.2 s into the LevelUp effect.
- Level 30: Wizard (Fire, Poison) 210, Wizard (Ice, Lightning) 220 and Cleric 230 are all selectable at their canonical
  level. Each adds +475 Max MP and teaches no skill. This fixed tier C bonus is the midpoint of the 450-500 range
  in the v83 server reimplementation reference, **unverified against GMS** ([research](research/cosmic-data.md),
  job-change rewards, `client/Character.java:1204` in the local reference). It does not claim a tier B native-client fact.
- The bot uses its independent seeded branch stream (8), leaving card and combat streams separate; a single available
  job consumes no branch roll. `balance.sh`, `playtest.sh` and `--run` take `--job=<id>` (any first or second job the build offers: a second job takes its first job at the first window and itself at the second; one that is not playable fails at startup; `--branch=<id>` is the deprecated alias). Run records
  store `branch` (0 before second job), and balance summaries group outcomes by branch; legacy records are unobserved.
- Skill counts have no caps. The owned-skill HUD uses eight 24 px icons per row, 4 px gaps, so about fifteen icons
  fit left of the timer and boss bars at the minimum 800 px view (tier C layout).

### Weapon paths and weapon grants (#157, spec #151)

A first job can carry **weapon paths** (survivor `jobs.json` `paths`: `[{id, label, item_id, family}]`). The Job
Advancement window lists each path of a playable job as its own entry (the label is the entry text; both Thief paths
are job 400); a job without paths, and a locked job ("Not in this build"), keeps its single entry. Taking a path records its id on the character (`RunWorld.weapon_path`,
snapshot key `weapon_path`, an additive optional key written only when set) and **grants** its item: the weapon is
worn without requirement checks, so a Lv 10 Beginner whose AP is all STR still wears the Bowman's bow (DEX 25).
A grant never fails. The previous weapon moves to the Equip inventory; when the tab is full it is dropped at the
player's feet as a normal equipment pickup (`pickup_spawned`, then `pickup_blocked` until a slot is free). This
replaces the earlier rule that skipped the Magician's wand grant on a full tab (the `grant_blocked` event is gone).

| Path | Weapon (tier B: the v83 Beginner weapons the instructors give) | Family |
|---|---|---|
| Bowman | Beginner Bowman's bow 1452051 | bow |
| Thief - Claw | Beginner Thief Wrist Guard 1472061 | claw |
| Thief - Dagger | Beginner Thief's short sword 1332063 | dagger |
| Pirate - Knuckle | Steel Knuckler 1482000 | knuckle |
| Pirate - Gun | Pistol 1492000 | gun |

Warrior has no grant and keeps its creation weapon (owner choice); the Magician keeps its Wooden Wand
(`balance.player.weapon_grants`, unchanged). Bowman, Thief and Pirate stay `playable: false` ("Not in this build")
until their class specs; only the data shape and these rows land with #157. The items of a playable job's paths and
grants join `DataRepo.starter_equipment_ids`, so their canonical stats load once the class spec makes the job playable
(and adds their imgs to the manifest).

**Second-job grants.** A second job lists the weapon families it can use (`weapon_families`) and optionally a
`grant_item`. On advancing, when the held weapon's family (`RunWorld.held_weapon_family()`) is not in the list, the
grant item is worn (tier C); a fitting weapon is kept and nothing is granted. The grant item ids are chosen by the class
specs (basic weapons at the branch's level), so a row without one grants nothing today.

| Branch | Families it can use |
|---|---|
| Fighter 110 | sword, axe |
| Page 120 | sword, blunt |
| Spearman 130 | spear, polearm |
| Hunter 310 | bow |
| Crossbowman 320 | crossbow |
| Assassin 410 | claw |
| Bandit 420 | dagger |
| Brawler 510 | knuckle |
| Gunslinger 520 | gun |

**Bot and tools.** `BotInput.pick_choice` returns `{job_id, path}`. With no path
named, the bot draws one of a first job's paths from the job stream (8); a forced second job takes the path whose weapon
family the branch can use. `--job=<id>[:<path>]` (`--job=400:claw`; `balance.sh`, `playtest.sh`, `--run`) names the path;
a path the line does not have fails at startup.

**Melee-aware movement (#162).** The bot reads the reach of its attacks through `SkillRunner.reach_of(stats, world)`
(a projectile or nearest-rule skill its range, a box skill its far edge with area cards, 0 for buffs, manual, status and
heal casts) and `BasicAttack.reach(world)` (the farthest afterimage box edge of the held weapon's five stances, or the
punch). When the longest attack it owns reaches under `bot.engage.kite_reach` (220 px; Beginner skills such as Three
Snails only count while it owns no attack of its own job line) it stops kiting: it walks to 0.8 x the reach of its
longest ready attack (off cooldown, affordable; the swing always counts) from the nearest on-level mob within 300 px and
stands facing it. Below 35% HP, or while a boss attack winds up, it kites as before. Every Magician attack reaches
260+ px, so Magician and Beginner inputs are unchanged (`test_bot_melee.gd` holds digests captured on main). The
random policy shares the movement and the camper policies still override it after their warmup. Constants:
`bot.engage` in `balance.json`, tier C (section 11).

## 10. Presentation

- 800x600 logical view (wider windows show more map at the same pixel scale), integer scaling, nearest filtering. An
  opt-in "fill window" setting fills large windows with more map instead of black bars (see View fit below).
- HUD: independent status-bar, counter, skill-icon and message widgets receive state from RunScene. The original
  gauges, level, job name, timer, kill count and skill icons keep their layout. Decorative controls on the bar's
  right side are removed to reserve a potion quickslot, except the Menu button at the bar's right end; separate buff and boss widgets reserve space below the
  kill count and timer. Full-run pacing and structural checks cover progression, EXP collection, Magician
  advancement, boss-only completion, late ordinary hits and no lost mobs (4.1.1).
- Text uses the system's Arial-like font without antialiasing at MapleStory sizes (no fonts are shipped).
- Map name and street name from `String.wz/Map.img` on the stage card and at run start.
- Death: `Effect.wz/Tomb.img` tombstone falls on the character with `Game.img/Tombstone`.
- Results: the login book's Back banner returns to character select; death/victory frees the ended character's slot.
- Frame rate: vsync on and capped at the display's refresh rate (`Settings` `[display] max_fps`; 0 = refresh rate,
  -1 = uncapped); `--vsync=off` uncaps it for perf runs.

## 11. Constants and provenance

| Physical combat rule (#153) | Value / behavior | Tier | Source |
|---|---|---|---|
| Weapon formulas | `WeaponInfo.PHYSICAL`, Thief dagger row; multipliers and stats in 6.1.1 | B | SouthPerry/HS.net pre-Big-Bang compilation; Cosmic WeaponType corroborates max bounds; refs `class-specs/v83-facts.md` §5 |
| Wand/staff and bare formula | Retain 4.4 swing / 3.2 stab, STR/DEX, equipment-only PAD for bare hands | C | Existing game behavior; no verified wand/staff physical row in §5 |
| Physical mastery | Default 0.10; canonical N → (10+5N)% | B | SouthPerry compilation, WZ mastery/String corroboration |
| Physical defence | Level factor 1−0.01×positive level gap, max−0.5PDD/min−0.6PDD, each at least 1 | B | AGF/Stereo formula, refs §5; existing basic-attack rule |
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
| Weapon path grants | Each first-job weapon path wears its item (the v83 Beginner weapons above) without requirement checks and records `weapon_path`; Warrior has none (`jobs.json` `paths`, #157) | B (items), C (shape) | Cosmic job-instructor NPC scripts (v83-facts 4); the two Pirate weapons are ordinary shop weapons, v83 has no Beginner pirate weapon |
| Branch weapon grant | A second job wears its `grant_item` only when the held weapon family is not in its `weapon_families` (`jobs.json`, #157; item ids come with the class specs) | C | Ticket #157 |
| Equipment max HP/MP | Flat, added after card modifiers and the MaxMP passive | C | Ours |
| Bare hands | Punch with the five one-handed actions, attack speed 6, reach box (-55,-55) 50x50, impact on the action's last frame, no afterimage; W.ATT from other worn items only (minimum damage 1) (`BasicAttack.BARE_HANDS`) | C (A: `Sound.wz/Weapon.img/barehands`) | Ours |
| Format-1 weapon rule | Migration only: Beginner `beginner_weapon`, else the job line's `format1_weapon` from `data/survivor/jobs.json` (1302000 for the Beginner, 1372005 for the Magician line; nearest ancestor via `JobTree.lineage_value`) | C | Frozen spec #32 rule |
| Regen passive field | A skill with `"regen": {"pool": "hp" or "mp", "divisor": n}` adds `floor(character level x skill level / n)` to each regeneration pulse of that pool (`Loadout.regen_bonus`); Improved MP Recovery is `{"pool": "mp", "divisor": 10}`, Improved HP Recovery will be data only | B | Pre-Big-Bang Improved MP / HP Recovery rule (formula compilations, refs/research/v83-mechanics); the field shape is ours |
| Job `grants.max_hp` | Advancing adds it to base Max HP (`_base_hp`, saved as the snapshot's `base_hp`, so no format change) alongside `grants.max_mp` (`_job_mp`); data rows only for playable jobs | C | Ours; Warrior rows come with #163 |

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
| Weapon family rule (#159) | A weapon is eligible only when its family (`WeaponInfo.family`) is the family of the weapon held when the drop rolls (`RunWorld.held_weapon_family`, read per drop, ordinary and boss): one- and two-handed swords, axes and blunt weapons share a family; bare hands get no weapon; armour and shields do not depend on the held weapon (`EquipmentDrops.family_allows`). `equipment_drops.shared_families` `[["wand", "staff"]]` lets a Magician holding either see both, so Magician drops stay as before; a Beginner holding the creation sword no longer sees the reqJob 0 wands | C (ours; the ticket's rule, with the wand/staff group) | Ticket #159 |
| Job filter | Only items whose `reqJob` is 0 or has the bit of the character's current job branch (`Equipment.job_allows`); a Beginner only gets all-job items, every playable Magician job gets Magician and all-job items | A | v83 `reqJob` bits (owner #33: current job only) |
| Level window | reqLevel in [level - 10, level + 5] (`equipment_drops.below`, `above`) | C | Owner #33 |
| Weighting | Weight 1 / (1 + 0.25 x abs(reqLevel - level)), so items nearer the character's level drop more often (`equipment_drops.falloff`) | C | Ours |
| Drop chance | 0.002 per ordinary kill (`equipment_drops.chance`), sized once from an estimate: about 3,300 kills in a full Henesys round and about 8-12 items a round including the 3 boss drops. v83 mobs gave equipment on about 0.7-2% of kills | C | Ours (ticket #109) |
| Boss drop | Each scheduled boss death drops exactly 1 item (`equipment_drops.boss_drops`), no chance roll, uniform among the window's items with reqLevel in [level + 5 - 5, level + 5] (`boss_top`); the highest reqLevel in the window when none is that high, the nearest-level job-eligible item when the window is empty | C | Ours (ticket #109) |
| Random stats | Every non-zero `inc*` stat of a drop varies by a whole number up to 10% of its base (rounded up) either side, capped at 5 for STR DEX INT LUK PAD MAD ACC EVA Speed Jump and at 10 for PDD MDD MHP MMP, uniform, never below 0; upgrade slots (`tuc`) never vary; other `inc*` keys keep their base (`Equipment.create_drop`) | B | The v83 server rule as the ticket #109 states it (implemented from that prose) |
| RNG | Chance, item pick, stat rolls and boss scatter use RNG stream 10 (`equip_rng`), so no other stream moves; the pop of the drop uses stream 4 like every drop | C | Ours |
| Lifetime and pickup | Equipment never expires, merges or counts toward the EXP-drop cap; magnet and collect radius like EXP drops; with a full Equip tab (`balance.player.inventory_slots`) it is not magnetised, stays on the ground, and is picked up once there is room | C | Owner #33 |
| Notices | "You have gained an item (Name)" on pickup (name from String.wz/Eqp.img) and "You can't get anymore items." when a full tab refuses a drop, in the system-message queue | B | v83 client string pool (open client reimplementations) |

| Bot shopping rule (spec #33, #112; `BotShop`, bots only, never the player) | Value / behavior | Tier | Source |
|---|---|---|---|
| Equipment value | An instance scores the sum of weight x value over its `inc*` stats (`balance.bot.equipment_weights`, keyed by job id, `"0"` Beginner and `"200"` Magician; a job uses its nearest ancestor's entry through `JobTree.lineage`). Magician: M.ATT 10, INT 6, M.DEF 2, W.DEF 1.5, LUK 1, Speed 0.5, then ACC/EVA/Jump/pools; Beginner: W.ATT 10, STR 6, DEX 3, W.DEF 1.5. Scrolls already read are part of the stats | C | Owner brief (#112: Magicians want M.ATT, INT, then defences); the numbers are ours |
| Equip rule | At each equipment pickup, level-up and job change a bot wears, repeatedly, the highest-gain inventory item that scores above what it replaces (an overall against the top and bottom it displaces; an empty slot against 0) and that the v83 requirements and the Equip tab's room allow. Not a decision point, no RNG | C | Owner brief (#112); the job-change trigger is ours (a new job unlocks items) |
| Pickups it cannot take | Bots ignore equipment drops while the Equip tab is full (no walking to them, no camping on them); EXP, potion and meso drops are unchanged | C | Follow-up of #109 (lead) |
| Sensible plan | At a Free Market visit: sell the spare equipment it will not wear (everything except a better item that only fails the level requirement); then for each worn item with upgrade slots in the order weapon, overall, gloves, hat, top, bottom, shoes, read the 100% or 60% scroll of its item type with the best expected score (success chance x stat score; the 60% INT/M.ATT scrolls beat the 100% ones at equal price), using held scrolls first and buying one per upgrade slot while mesos (plus the sales) last. Never dark scrolls | C | Owner brief (#112 baseline); expected-value choice between 100% and 60% is ours |
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
| Creation flow / gender placement | C | Gender -> name OK validation -> appearance; name Cancel returns to gender, appearance Cancel to name. Centered Gender parchment(219,174), text(245,198), native dropdown over baked field(378,270,48,19), OK/Cancel(355,346)/(430,346). WZ text field is at local(133,72); no trustworthy period gender capture, so absolute placement and native OptionButton interaction remain C. Appearance Gender row still changes it; AP automatic, Beginner only |
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
| Schedule / first-pass HP | Zombie Mushmom 6300005 at 300 s, HP x0.8 (28000); Snack Bar 8220009 at 600 s, HP x1 (110000); Jr. Balrog 8130100 at 900 s, HP x3 (150000) | C | Owner schedule; scales chosen before measuring, no tuning; final boss has greatest multiplier and effective HP |
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
growth/modifiers, ordered skills/card limits, potion counts and tier IDs, Fortune and creation fields. HP and MP
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
| Supplies / elites / bursts / ending | Stage EXP 1x, global potions; hard cap 400; bursts first/every 90/90 s, size 10–40; elites first/every 75/60 s, HP/EXP/contact 8/5/1.5x; bosses and rewards gate clear | C | Existing stage conventions; #73 supplies the final-fight lifecycle |
| Signature EXP pickups | Horny 4000015, Zombie 4000008, Stirge 4000042, Evil Eye 4000007, Curse Eye 4000013, Jr. Boogie 4000067, Tauromacis 4000028, Taurospear 4000046 | A IDs/names; C association | Original v83 String.wz/Etc.img names and Item.wz art; signature icon association is survivor data, not a WZ drop-table claim |

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
| Teleport autoplay and HUD | same-height threats (existing duel band, feet +/-40 px): blink within 60 px, or when mobs block both sides within existing 160 px flee distance. An edge within 60 px plus a threat within 60 px on the interior side escapes toward the interior; otherwise choose the safer side. Requires learned skill, reserve, interval and a destination. HUD: the shared blue waiting-for-MP tint (#82; was 0.35 grey); 80 ms evidence capture delay | C | ours; BotInput, HudSkills, RunScene |
| HUD skill cooldown sweep and MP wait tint | a cooling skill icon is covered by a black 60% overlay wedge of (left / total set at the last cast) x 360 degrees ending at 12 o'clock, so it clears clockwise, moving in 1/96 steps of the cooldown (one per pixel of a 24 px icon's edge; the widget redraws only when a step or tint changes); not drawn below 0.2%; Teleport uses its repeat timer; a ready skill that would cast but lacks MP is modulated blue (0.35, 0.5, 1.0); no seconds text | C | ours (#82); HudSkills (SWEEP_STEPS), RunWorld.skill_readiness / read_skill_cooldowns |
| Bot Teleport MP reserve | after canonical cost, retain max(25% max MP, 2 x highest MP cost among learned automatic attacks); buffs, passives and manual skills excluded | C | a priori policy: preserve one attack plus an equal combat margin; the quarter-pool floor leaves MP for Magic Guard even with cheap attacks; `BotInput.TELEPORT_MP_RESERVE_FRACTION` / `TELEPORT_ATTACK_RESERVE_CASTS` |
| Bot Teleport interval | at least 5 simulation seconds between valid-destination escape requests, recorded in bot memo | C | a priori policy: allow several auto-cast cycles and ordinary kiting before another emergency blink; independent of the player's 0.3 s repeat; `BotInput.TELEPORT_MIN_INTERVAL` |
| Teleport card weights | new/rank weight 2, max rank 20; no behaviour modifiers | C | ours; upgrades.json |
| Physics.img values | see `docs/research/wz-inventory.md` §2 | A | v83 Map.wz |
| Potion restore amounts and icons | Red 50 HP, Orange 150 HP, White 300 HP, Blue 100 MP, Mana Elixir 300 MP | A | Item.wz/Consume/0200.img, unchanged spec/info |
| Potion stock, drop chances and bot drinking | start 5 Red/0 Blue; normal HP .012 fallback (stage curve in §5)/MP .03 flat, no per-map values (owner, 2026-10-16, #80; was .10), elite HP .15/MP .60; the bot drinks only when the missing amount is at least half of one current potion's restore; persistent drops, unlimited stock, no drink cooldown | C | ours; balance.potions |
| Ordinary HP supply curve | Optional stage-keyframe chance, endpoint clamping, linear interpolation, global fallback per missing endpoint and endpoint holding outside the range | C | ours; SpawnDirector.normal_hp_drop_chance_at |
| Ordinary MP supply | 3% flat on every stage, no per-map values; the #30 stage MP curve and its reader are removed; elite rolls and boss bundles unchanged | C | owner, 2026-10-16, 3% flat, no per-map values; balance.potions.drops.normal.mp; #80 |
| Potion quickslot geometry | two slots, 104 px apart within the 221 × 59 area | C | ours; HudPotionQuickslot |
| Walk/jump/air/down-jump/landing model | §3 | B | NoLifeStory physics description |
| Player sub-step | 2 per 1/60 s tick | C | ours |
| Vertical air drag | none (apex 555²/4000 = 77 px) | C | ours; NoLifeStory's 100 px/s² vertical float drag would give ~73 px |
| Climb speed | 100 px/s | C | ours (HeavenClient uses 125) |
| Ladder grab/exit | Up: hands 50 px above the feet within 10 px of x; Down: 10 px below the feet; 0.25 s re-grab delay; exit jump vx = max walk speed, vy = jumpSpeed/1.5; `uf=1` top exit onto a floor within 24 px above / 4 px below the top | C | ours / HeavenClient exit jump |
| Same-map portal activation and arrival | feet x ±25, y −100…+25; arrive 30 px above target with zero velocity; global cooldown 384 ms; camera snaps, no sound or transition | C | owner choice; `balance.json.portals` |
| Autoplay portal choice | approach a same-map entrance when its walk plus arrival-to-drop distance is less than going directly (horizontal distance + 2 × vertical); with a mob within 160 px, an entrance within 250 px can instead lead to less nearby mob danger. Reach entrance ledges through existing jump-graph edges; hold Up in the activation box and during the entrance hop | C | ours; uses the bot's existing drop, danger and alignment rules |
| Down-jump reach | a floor within 600 px below | C | HeavenClient |
| Player knockback hop, alert stance | 200 px/s up, 2 s | C | ours |
| Player placement | `PlayerMotion.place()` snaps onto a floor at most 1 px below, else the player falls | C | ours |
| Falling out of the world | below the MapBounds bottom the player is put back on the nearest floor (`EV_FELL_OUT`) | C | ours |
| Wall probe | a wall blocks where it covers the point 1 px above the feet (a wall hanging below a platform end can be walked off) | C | ours |
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
| Boss status immunity | scheduled steady or canonical boss: reject Slow, Poison and Freeze | C | v83 server reference (Cosmic Monster.applyStatus boss gate), owner decision replacing #54's boss-poison permission |
| Elemental status immunity | a status fails on Mob elemAttr digit 1 (immune), 2 (strong) or 4 (neutral) for its element: Poison S, Freeze I (or the applying skill's element); Slow elementless | A element letters / C rejection rule | Poison Breath elemAttr s and Cold Beam i in Skill.wz; rejection per Cosmic Monster.applyStatus; [status research](research/monster-status-effects.md) |
| Player elemental hits / undead | Mob elemAttr digit1 ×0, digit2 ×0.5, digit3 ×1.5; absent/elementless ×1; final rounding; undead exposed independently | A factors/flags; C rounding integration | original Cold Beam String.wz text and Mob.wz; [status research](research/monster-status-effects.md) |
| Mob status cues | Slow one-shot cached mob art, Poison repeat art; pos3 centre/pos2 top; Slow amber (1,.72,.40), Freeze cyan (.45,.80,1), fallback Poison violet (.72,.45,.90) | A art / C anchors and tint choices | original Skill.wz/210.img, Cold Beam has no mob overlay; [status research](research/monster-status-effects.md) |
| Default frame delay | 100 ms | C | HeavenClient |
| Background scroll | rx × 5 px/s | B | 3 reimplementations agree |
| Damage number timing | 400 ms hold + 600 ms fade, 30 px rise | B | v95 RE (Harepacker docs) |
| Player knockback | 187.5 px/s, 0.3 s lock | C | HeavenClient |
| Hit window lengths (#88) | `balance.hit_window.lengths` 1.5 / 1.0 / 0.6 / 0.4 s: the grace after the 1st, 2nd, 3rd, 4th+ chained landed hit from contact damage or an ordinary mob attack (a lone mob always gives the full 1.5 s) | C | ours; replaces the old fixed `invincible_time` 1.5 |
| Hit window chain gap (#88) | `balance.hit_window.chain_gap` 2.5 s: a landed hit this soon after the previous landed hit steps to the next shorter window; between 2.5 s and the reset the step holds | C | ours |
| Hit window reset (#88) | `balance.hit_window.reset_after` 3.0 s without a landed hit restores the full window (and starts the chain over) | C | ours |
| Boss skill attacks ignore the hit window (#88) | A boss skill attack (`source_kind` `attack`, `projectile` from a scheduled boss) lands during the window, hits at most once per attack instance (a ball is used up only when it hits), starts the full `lengths[0]` window without advancing the chain and counts as a landed hit for the reset. Boss body touch and every ordinary mob attack respect the window; an ordinary ball that the window turns away flies on, with no hit and no hit art, and can land once the window ends (also from inside the body box). Misses give no window and do not touch the chain; god and death still block everything | C | ours |
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
| Post-finale ramp / harness cap | final keyframe slopes ×0.25 after 15:00; burst size slope ×0.25 past the duration; elite interval × rate(last keyframe) / rate(t); 30:00 cap reported as timeout | C | survivor stage/balance data |
| First MISS screenshot | 0.05 presentation seconds after the first miss, only when screenshots are enabled | C | evidence capture timing |
| Projectile speeds/ranges | §7 | C | ours |
| Projectile hit exclusion identity | packed 64-bit run-local spawn identity; fresh spawns differ, relocation preserves it | C | our pool bookkeeping; no canonical or balance values changed |
| Camera smoothing | exponential, 6/s, 8 px dead zone, player at 58% height | C | ours |
| Player start | 50 HP, 5 MP (v83 Beginner, owner decision), STR 12 / DEX 5 / INT 4 / LUK 4, Three Snails rank 1; Magician magic attack 23 (Wooden Wand 1372005 incMAD) | C (A for the wand) | ours |
| Automatic AP and advancement reset | 5 AP per level, Beginner → STR, Magician → INT; only earned AP is redistributed on advancement | C | survivor rule, emulator-style reset |
| Magician secondary AP (LUK) | earned AP fills LUK until base LUK = level + 2 (keyframes 1 → 3, 200 → 202), the rest to INT; Beginner none | C | v83 Character.wz reqLUK pattern (15 at Lv13 ... 70 at Lv68), ticket #106 |
| INT MP growth | Magician adds floor(INT / 10) to base growth, before assigning the new level's AP | B | pre-Big-Bang formula compilations, refs/research/v83-mechanics |
| Player avoidability | DEX × 0.25 + LUK × 0.5 + worn equipment incEVA | B (A for equipment) | Exoot 2009 formula compilation / v83 Character.wz |
| Player body (touch box) / cast origin | (-14,-58)-(14,0) from the feet / 30 px above the feet; shots start 22 px further toward their target (the hand) | C | ours |
| Cast stance | the skill's `action` (swingO1) for 0.8 s (its WZ frames 300+150+350 ms) while standing still | C | ours |
| Climbing cast gate | no new skills, basic attacks or buffs while on a rope/ladder; cooldowns and existing effects continue | C | owner choice |
| Guard/Armor values and durations | canonical mpCon/time/x/pdd at cast skill level; L1 Guard 6 MP/111 s/11%, Armor 8 MP/54 s/+2 PDD | A | Skill.wz/200.img |
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
| Potion tier gates and sparse draws | HP Orange from Lv 10, White from Lv 25 after Orange; MP Mana Elixir from Lv 20; one-time cards, preserve stock, future drops current tier; 3 choices when full; otherwise eligible cards plus one Elixir | C | owner choice; upgrades.json |
| Current-job cards and Elixir reward | strict job equality, Beginner cards require 0; learned earlier-job skills retained; one Power Elixir alternative below 3 eligible cards, alone at 0; fully restores both pools | C (reward/pool rule), A (2000005 identity/art/restoration) | owner choice, #38; upgrades.json fallback |
| Bot potion tier score | 112 (above Guard and attack cards); fallback 52 when absent | C | survivor balance.potions.bot.tier_score; random card policy unaffected |
| Bot potion waste guard | drink when missing HP/MP >= 0.5 x one current potion's canonical restore (`min_restore_fraction`) | C | owner review of #29; BotInput, shared by sensible and random card policies |
| Bot sword duel | a lone ordinary mob within 160 px and 40 px of the feet while no attack skill is ready and affordable: stand facing it so the basic attack swings; flee from two or more | C | owner review of #29; BotInput, shared by every movement policy that uses it |
| Bot Guard preference / offers | base-score overrides learn 110, rank 109 (the #63 gain term is added on top); no job bonus added; learn/rank offer weights 8/8 | C | balance.bot.card_scores; upgrades.json; random choices uniform |
| Bot card gain step (#63) | sensible bot card score = base + `gain_step_score` x (offered `magnitude` - 1); `gain_step_score` 6 (coded default `BotInput.SCORE_GAIN_STEP` 6 when absent); missing or <= 0 magnitude counts as 1; potion-tier and Elixir cards ignore the gain; no tier name or `max` is special-cased; first/random policies unaffected | C | owner #63 triage 2026-10-17; survivor balance.bot.gain_step_score |
| Three Snails auto levels | skill level 2 at Lv 3, 3 at Lv 6 (`level_ranks`) | C | ours, after the v83 Beginner's SP |
| Three Snails MP cost | 3 / 5 / 7 MP at skill levels 1 / 2 / 3, with the normal insufficient-MP wait and cue | A (costs), C (auto-cast wait/cue) | v83 Skill.wz/000.img/skill/0001000/level/N/mpCon; survivor casting rules |
| Advancement draws / skill counts | no skill grants; extra new-job attack-first draw with rarity before the normal level draw; no skill slot caps | C | owner decisions #31 / #53; sections 8?9 |
| Second-job Max MP | +475 for 210/220/230, fixed midpoint of the reference 450-500 mage range; existing first-job +120 retained | C | server reimplementation, unverified against GMS; [research](research/cosmic-data.md), local `Character.java:1204` |
| Bot branches / owned-skill HUD | independent seeded stream 8; optional forced branch; eight 24 px icons per row, 4 px gaps | C | #53 harness and presentation |
| Upgrade prerequisites | canonical `req` and previous survivor skill prerequisites ignored; exact job gates and owned-skill rank/modifier requirements retained | C | owner decision #31 |
| EXP curve, pacing keyframes | sections 4.1, 5 (`balance.json` `exp_curve`, `stages.json`), tuned with `scripts/balance.sh` | C | ours |
| Skill rank tables | every rank equals its canonical level; Beginner skills 3, first-job attacks/buffs 20, MP Recovery 16, Fire Arrow 30 | A (level counts); C (tier gain per card) | v83 Skill.wz level tables; owner choices #39 / #30 |
| Fortune and card odds | base 0; Normal/Rare/Epic/Unique/Legendary weights 75/18/5/1.7/0.3; non-Normal weights ×(1 + max(0, Fortune) ×0.02), normalized | C | spec #30 weights (owner restored them over C46 on 2026-10-15; untuned); upgrades.rarity and balance.player.fortune; cards only, not canonical LUK/drops/crits |
| Cash slot Fortune | 11 cash slots (hat, face, eye, earrings, top, bottom, shoes, gloves, cape, weapon, shield); each filled slot adds hat 10, face 8, eye 8, earrings 6, top 10, bottom 10, shoes 9, gloves 9, cape 10, weapon 12, shield 8 (sum 100); overall = top + bottom, two-handed cover = weapon + shield; computed live, never stored in the character | C | spec #34 / #116, ADR 0003; placeholders in `cash_items.json` `slot_fortune`, set by the balance pass |
| Cash slot from item id | id / 10000: 100 hat, 101 face, 102 eye, 103 earrings, 104 top, 105 overall, 106 bottom, 107 shoes, 108 gloves, 109 shield, 110 cape, 170 weapon cover | A | v83 item id categories (spec #34 research) |
| Pet and pet upgrade prices | Brown Kitty 5000000, Brown Puppy 5000001, Pink Bunny 5000002: 4,900 NX; Auto HP Pouch 1812002, Auto MP Pouch 1812003, Wing Boots 1812004, Binocular 1812005: 1,800 NX | A | Etc.wz/Commodity.img OnSale listings (`cash_items.json`, with the SN) |
| Cash equipment catalog | 116 curated items: hat 10, face 10, eye 10, earrings 10, top 10, overall 10, bottom 10, shoes 10, gloves 10, shield 6 (all that qualify), cape 10, weapon cover 10 | A (price, SN) / C (selection) | OnSale=1 `Etc.wz/Commodity.img` rows, price and SN as listed; a cache-backed test checks each entry. Filters (tier C): unisex id (thousands digit >= 2; the Commodity `Gender` field is unreliable), `info/cash` = 1, no `reqLevel`, real canvas art, covers need 37 and 38 art; rings and the "Transparent" items have no sprite and are out |
| Two-handed weapon cover | `two_handed: true` on 1702004, 1702042, 1702078: the covers whose `info/vslot` is WpSi (they occupy the shield slot too) | C | inferred from the vslot; WZ has no two-handed flag on covers |
| Weapon cover type | the cover draws the `<type>/<stance>` art of the real weapon's type, type = weapon id / 10000 - 100 (30 sword, 37 wand, 38 staff, ...); no art for the type or stance leaves the real weapon, no real weapon draws no cover | B | third-party RE of the official client for the type selection; the fallback is ours (C) |
| Cash replaces regular equipment | a worn cash item draws instead of the regular equip of its slot, and also of any regular equip whose whole `info/vslot` it holds (a MaPn vest replaces the pants, an overall both) | C | v83 shows the cash item in place of the regular one; the vslot-subset rule is ours |
| vslot hiding | a layer is hidden when one other drawn item's `info/vslot` codes cover every code of the layer's `Base.wz/smap.img` entry (hat CpH1H5 hides hairOverHead, a full-head hat the head, hair and accessories); face accessories follow the face expression; hats, eye accessories and earrings use their `default` frame for stances they lack | C | codes are tier A (smap.img, `info/vslot`); the all-codes-of-one-item reading is ours (any-code or pooled readings hide the sleeves, pants and shoes wrongly) |
| VAC | survivor-only pet upgrade, id 9990000 (reserved), placeholder price 20,000 NX, needs Wing Boots + Binocular and a pet: every drop on the map that is outside the player's magnet radius flies to the pet at the drop magnet's speed and acceleration (#119); while a pet with VAC is out the Magnet card (any card raising the `magnet` stat) is never offered, in normal, boss and advancement draws | C | spec #34, ADR 0003; our design |
| Pet in the round (#119) | `PetSystem`, only with an owned pet out (`character.pet` + `account.owned`); none otherwise and the round is byte-identical to before. Moves with the player's own physics (a second `PlayerMotion`) driven by a follow controller: walks toward the player (stops within `follow_gap` 40 px, walks at 1.1x the player's speed), hops up when the player's feet are 20-70 px above and within 80 px sideways, drops through the floor when the player is 20+ px below and within 60 px, jumps after 0.3 s pressed against a wall, hangs on the player's rope (action `hang`) while the player climbs. Teleports to the player when farther than 600 px, or farther than 280 px for 3 s (`pet_teleported` event). A pet brought out (round start, the Pet page, the Free Market) stands `beside_offset` 30 px behind the way the player faces, else in front, on the same flat floor, else on the player (#126: on the player it was hidden behind or over the avatar while the player stood still; a teleport still lands on the player and the pet walks off) Three more constants live in the same `pet` block rather than in code: `speed_stat_floor` 100 (the pet's speed stat is the player's but never below the 100 % base), `stuck_move_px` 0.2 (it counts as pushing against a wall when it moved less than this in a tick) and `floor_tolerance` 2 px (a floor within this of the player's feet is the same floor, for standing beside). `cash_items.json` `pet` is the only place the numbers live; `PetSystem` has no defaults. The pet upgrade item ids in `PetSystem` are tier A (1812002-1812005 are v83 items) except VAC 9990000 (tier C, survivor-only). A drop flying to the pet when it is dismissed falls and lands as an ordinary drop. State for drawing and telemetry: `RunWorld.pet_state()` = {species, pos (feet), facing, action stand/move/jump/hang, fetching, abilities} | C | ours; the numbers are in `cash_items.json` `pet` |
| Pet pickup (#119) | the base pet (Item Pouch and Meso Magnet included) collects every drop kind (EXP, potions; mesos with B2) within `pickup_radius` 60 px of its centre (15 px above its feet), on top of the player's magnet; Binocular x2 (120 px). What it collects is credited exactly as the player's, and `pickup_collected.collector` is `pet`. Wing Boots: it runs (1.5x) to the nearest resting drop within 220 px sideways and 80 px vertically of the player, walks to within 6 px of it, gives up after 2.5 s on one drop (then 2 s without fetching), and comes back | C | ours; v83 `PetEquip` flags (`pickupItem`, `pickupMeso`, `sweepForDrop`, `longRange`) are the idea only |
| Pet auto potions (#119) | Auto HP / Auto MP Potion Pouch: below the HP / MP ALERT fraction (strictly below; 0 = do not alert; the round setup's `alert`) the pet drinks the character's current potion of that kind from the shared stock, at most once per kind per 1.0 s, never with an empty stock. Counted in `potions.pet_used` and the `pet_potion_used` event, not in `potions_used`/`potion_used`. The bot's own drinking rule is unchanged | C | ours; the ALERT sliders are v83 Options |
| Pet drawing (#120) | `PetRenderer` draws `RunWorld.pet_state()` (and the Free Market's `FreeMarketMotion.pet_state()`, the same `PetSystem` follower with no drops) from `Item.wz/Pet/<species>.img` (`stand0 stand1 move jump hang fly` and `info/icon`, `info/iconRaw` in the manifest; no `Pet.wz` in v83) at the real frame delays and origins; the art faces left so facing right mirrors; no name tag or chat balloon. Action to animation: stand -> `stand0`, move -> `move`, jump -> `jump`, hang -> `hang` (tier A: the WZ names); a pet running to a drop in the air (Wing Boots, `fetching` and `jump`) uses `fly`, and a hanging pet is drawn 22 px beside the climber instead of exactly behind (C: ours, the sim keeps it on the player's position). Drawn in the actor layer of the foothold it stands on, just behind the avatar when that is the avatar's layer. `stand1` is imported but not used | A (animations) / C (mapping, offset) | v83 `Item.wz/Pet`; ours |
| HP / MP ALERT defaults (#121) | HP ALERT 30 %, MP ALERT 20 % of max (`Settings` `[alert]` hp/mp; 0 = do not alert; 5 % steps on the Options sliders). A persistent round takes them from the settings at launch and follows changes at once; tool rounds ignore the settings and take `--account`'s `alert` (default 0) | C | ours, low enough to be safe and on so a new pouch works at once; the v83 SysOpt rows are the slider style |
| Card tier magnitudes | rank +1/+2/+3/+5/max; stacking +1/+2/+3/+4/max; new skill 1/2/3/4/5; per-card overrides | C | spec #30, each tier above the last (owner 2026-10-15); upgrades.magnitudes; Legendary deliberately maxes even 20-rank skills |
| Card honesty / boss floor | highest fitting tier; a gain equal to a lower tier wears the lowest such label; boss promotes Normal to Rare and omits scalable cards unable to retain Rare; potion/Elixir always Normal | C | spec #30 / #43; headroom interpretation and exceptions in §8.1 |
| Tier text precision / telemetry | compounded percentages rounded to 0.01 for text; application full precision; offered/picked count each displayed card once; legacy records are unobserved | C | ours; choice_card, RunWorld counters, balance report |
| Tier reward presentation | white/blue/purple/gold/green accents `#FFFFFF/#77BBFF/#CC99FF/#FFCC44/#77DD88`, dark `#17344F` 16px label band tinted 30% with the tier colour and a 2px frame; rows start at 140px in blanked notice, 4px gaps, target view height minus 128px; prose compacts before changed values | C | #30 / #44; Potential ladder semantics on original v83 window art |
| High-tier offer cue | one `Sound.wz/Game.img/mCardGet` per displayed Unique/Legendary level-up or boss-reward window; prewarmed; no cue for invisible autopicks or focus/pick | A (v83 2664ms audio), C (reward use) | implementation selection after owner reserved EnchantSuccess for future scrolling; existing whole Game.img manifest; actual WASAPI playback verified by agent, fit auditioned and approved by owner on 2026-10-15 |
| Upgrade card values | `upgrades.json`: Recovery/Nimble Feet ranks 1–3, MP Recovery ranks 1–16, MaxMP Increase ranks 1–10, Magnet ×1.25; old Max HP/flat-speed/flat-MP cards removed | C (card tuning); A (canonical levels) | ours; original WZ |
| Improved MaxMP Increase percentage | computed Max MP (level/INT growth + job grant) × (1 + .02 × skill level), rounded once; +2–20% across 10 levels; preserve current MP ratio whenever this maximum grows, including later levels/jobs | C | owner reinterpretation; skills.improved_max_mp.passive; canonical 2000001 instead improves MP gained per level |
| MP Eater monster pools and level values | canonical `Mob.wz/info/maxMP`, never HP-scaled; spawn full, relocation preserves depletion, fresh reuse refills; `prop` 11–30%, `x` 21–40% over levels 1–20 for all three IDs; depleted monsters give no MP | A (data and exhaustion), C (survivor slot lifecycle) | original v83 Mob.wz, Skill.wz and String.wz; #59 |
| MP Eater cards and bot priority | learn/rank weights 2/2, no behaviour cards; existing passive bot scores learn 50, current-job rank 42 + 12 = 54, below attacks and above Magnet | C | survivor integration, existing BotInput defaults; #59 |
| MP Eater hit and presentation rules | whole-MP truncation; current passive level at impact, proc only on damaging magic lines; full player MP still drains monster MP, effect accompanies every absorb, gain number uses actual capped restoration; evidence shot at 0.12 s | C (integer interpretation and survivor integration), A (700 ms effect art/timing) | #59; shared Foundations hook/restoration, original v83 Skill.wz effects |
| Mastery passive | WZ `mastery` N gives (10 + 5N)% (the same encoding as magic masteries); the best owned Mastery of the held family replaces the 10% base; its `x` adds ACC | B | Cosmic and String.wz agree (v83-facts section 3); #161 |
| Crit passives | `crit_chance` = `prop` percent added to the crit chance; `crit_damage` = `damage` total percent, so a crit adds `damage - 100` points to the skill % instead of multiplying | B (additive rule), C (data shape) | SouthPerry Critical Shot/Throw (v83-facts section 5); #161 |
| Improved MaxHP per level-up | `max_hp_per_level` adds the skill's `x` HP at each level-up after learning, never retroactively; persists through `base_hp` | B | v83 Cosmic level-up HP rule (v83-facts section 3); #161 |
| Final Attack proc | canonical `prop`% chance after a damaging physical line of a matching family, follow-up at canonical `damage`% on the same mob, RNG stream 12, played at the end of the tick, none on a killed target or after a follow-up | A (prop, damage), C (per-line roll, timing, stream, no chains) | v83 Skill.wz; #161 |
| Attack speed table (#160) | speed step 2..9 (lower is faster) takes 800 x (10 + step) / 16 ms (600..950); normal step 6 = 800 ms; the swing interval is that rounded up to 30 ms (`WeaponInfo.SPEED_DELAY_MS`, `attack_interval`) | B | v83 weapon-speed words and delays, emulator RE; same formula as before #160 |
| Booster steps (#160) | buff effect `attack_speed` = steps faster (v83 Boosters: 2), clamped to speed 2..9; counted only while the skill's weapon family is held; skill cooldowns/action times and basic-attack impact/stance scale by the table ratio to the weapon's own step | A (+2 steps, duration: Skill.wz), C (relative-to-own-step scaling, skill cooldown scaling, gating) | v83-facts section 3; ours |
| Buff `scale` | a buff effect entry may multiply its canonical number (Rage's WDEF penalty is `-1`) | C | data shape; #161 |
| Warrior advancement (#163) | job 100 at Lv 10, +225 Max HP (`jobs.json` grants), growth 26 HP / 5 MP per level, all earned AP into STR, no weapon grant | B (HP grant midpoint of +200-250 and the growth midpoints: Cosmic changeJob / levelUp); C (Lv 10, no DEX row) | v83-facts 4; owner choice (spec #151) |
| Warrior melee families (#163) | Power Strike and Slash Blast need sword, axe, blunt, spear or polearm (`skills/warrior.json` `weapon_families`) | C | the WZ nodes name no weapon; String text says "sword"; v83-facts 2 |
| Weapon-reach and range-around casts (#163) | `weapon_reach`: nearest mob inside `BasicAttack.envelope` (the union of the held weapon's afterimage boxes, far edge = `reach`); `range_around`: body centres within the level's canonical `range` of the body, `mobCount` cap | A (afterimage boxes, `range`, `mobCount`); C (the rules, auto-cast) | Skill.wz 100.img; ours |
| Skill stance `"action": "weapon"` (#163) | the held weapon's first basic-attack action (`WeaponInfo.skill_action`), so a spear stabs and a polearm swings | C | the Warrior nodes have no `action` |
| Power Strike / Slash Blast pacing (#163) | cooldowns 1.0 s / 1.6 s, 0.6 s cast stance | C | ours, untuned until the balance pass |
| HP cost (#163) | Slash Blast pays canonical `hpCon`; never cast when HP would not stay above 0, then nothing is paid and no MP shortage is signalled | A (hpCon); C (the refusal rule) | Skill.wz; ours |
| Improved HP Recovery (#163) | adds canonical `hp` (3-50) to every regeneration pulse, always (not only standing still) | A (hp); C (always) | Skill.wz; String text says "while standing still" |
| Endure (#163) | one base regeneration pulse (`balance.regen.hp` + `hp_regen`) every canonical `time` (31-10 s) while on a rope or ladder, `player_restored` skill `endure` | A (time); C (amount, on top of regeneration) | Skill.wz; v83's amount is not in the WZ |
| Iron Body (#163) | auto-cast buff, recast on expiry, canonical pdd/time/mpCon, 0.8 s stance | A (values); C (auto-cast) | Skill.wz |
| Warrior cards (#163) | learn/rank cards for all six; Cleaving Strike +1 target x3, Crushing Strike x1.2 damage x3, Quick Strike -12 % x3, Whirling Blast +2 targets x3, Wider Blast range x1.2 x3, Quick Blast -12 % x3; weights 1-4 | C | ours, untuned |
| Warrior bot fixture (#163) | `lv11_warrior_1st.json`: forced job 100, seed 1, stopped at 295 s | C | `tools/character_fixture.gd --job=100 --seconds=295 --label=spec151/ticket-163` |
| Nimble Feet values and lifecycle | speed +10/15/20 for 4/8/12 s, costs 4/7/10 MP; cooldown 60 s from cast; auto-cast when inactive/ready/affordable, passive slot, no new cast while climbing | A (values), C (auto-cast/slot/lifecycle) | v83 Skill.wz/000.img/skill/0001002; owner casting rule |
| Recovery HoT | canonical levels 1–3 cost 5/10/15 MP, heal x=4/8/12, last 30 s, cooldown 120 s from cast; trigger below 50% HP, six 5 s pulses including the expiry tick | A (values); C (trigger/pulse interpretation) | v83 Skill.wz/000.img; survivor skill buff rules |
| Regeneration | 10 s pulses, base 3 MP + floor(character level × MP Recovery skill level / 10); always 10 HP; `balance.regen` | B (MP rule); C (HP choice) | pre-Big-Bang formula compilation; owner choice |
| Level-up MP refill | each level-up refills MP to the new maximum after growth (`level_up_refill.mp` 1.0) | B | Cosmic `Character.levelUp` calls `changeHpMp(maxhp, maxmp)` (v83 server RE); #80 |
| Level-up HP / casting order / low-MP cue | no level-up healing (`level_up_refill.hp` 0.0) or implicit HP gain from maximum growth; oldest-ready affordable skill, one per tick; warm-red persistent cue above EXP messages | C | owner choices; ours |
| EXP drop motion | pop 260 px/s up, ±40 px/s sideways, Physics.img gravity onto floors; magnet 220 px/s + 1400 px/s²; collected within 24 px of the body centre (25 px above the feet); at 600 drops the farthest from the player is absorbed into a fresh drop at the new kill | C | ours |
| EXP drop lifetime | never expires (`pickup.lifetime` 0); capped absorption resets the new drop's age and conserves EXP | C | owner decision 2026-10-14 |
| Player-platform spawns | 35% of ground placements, at least 150 px away; visible only when the whole platform fits in view, otherwise on off-screen portions; normal regen fade and harmlessness | C | owner choice, `balance.json.spawn` |
| Spawn rings | first the floors beside the view (within 160 px of its sides, `band`, and 48 px of its height, `band_y`), then within 480 px of the view, then the map within 1170 px of the player; 12 samples per ring, looking first for a point whose way to the player is at most half the view width + 48 + 160 px (`prefer_route`, 608 px on an 800 px view: no longer than the walk in from the ring's outer edge), then for any point that reaches the player, before an unreachable spot; never where a wall that crosses a platform stands anywhere on the way to the player (followed edge by edge onto the player's platform) | C | ours |
| Spawn trail margin | spawns stay 32 px further out (`trail_margin`) on the side a moving player (horizontal speed > 1 px/s) runs away from: the camera lags about 125 / 6 + 8 = 29 px behind a running player (smoothing 6/s, 8 px dead zone) | C | ours |
| Mob relocation | silent, never on screen (only from outside the view + 48 + 32 px on every side: the camera can lag either way) and never elites: a mob that has not come 1 px closer along its way while itself moving 1 px for 3 s (`stall_time`, `stall_progress`; a mob standing still on screen keeps counting and is moved once off screen), or that is farther than 1300 px or cannot reach the player 160 px off-screen for 3 s, is moved to a fresh spawn point, preferring the side the player is moving toward (its horizontal speed > 1 px/s), with its HP; only when no point is found is it recycled (removed) | C | ours |
| Bursts / elites | bursts may exceed max_alive up to `hard_cap` 400; first elite at 1:15 (Henesys 4:00), then every 60 s; first burst at 1:30 (Henesys 5:00), then every 90 s | C | ours; the Henesys delays keep them out of the sword-paced Beginner phase |
| Henesys stage EXP | 2.5x canonical mob EXP for ordinary kills (`stages.henesys_hg1.exp_mult`) | C | coarse #29 pass so a sword-paced Beginner reaches Magician near 4:40 |
| Job window | at every queued level while an option is available; once at the tier's first level when none is | C | ours |
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
| Restoration gain digits | HP NoBlue1/0; MP same art tinted RGB (0.65,1,1); absent Blue falls back to Violet (HP tint 0.55,1,0.55; MP cyan) | A (cached digit art), C (selection/tints/fallback) | original v83 BasicEff cache; HP-use inference remains unverified (prior-art.md); existing number timing/stacking reused |
| Critical burst | `NoCri1/effect` behind the first digit (origin on the digit's anchor) from 250 ms; the v95 "y-30" and "+30 px leading space" are not applied (the prose leaves their axis/reference open) | B/C | v95 RE timing; placement ours |
| Face blink | `blink` every 2-5 s (seeded) | C | ours |
| Tombstone drop | `Tomb.img/fall` from 300 px above over its own duration (ease-in), then `land`, stays | C | ours |
| Pickup drawing | iconRaw centred on x, bottom on the drop point; bob 2 px over 1.2 s | C | ours |
| BGM fade / volumes | 0.8 s cross-fade; defaults master 1.0, BGM 0.8, SFX 0.9; 16 SFX voices (oldest stolen) | C | ours |
| HUD layout | gauge at (216, 37) of the 800×71 bar, fills measured from `gauge/bar`; button/key positions and top timer/kills/skills layout | A (measured art) / C (buttons, top HUD) | ours |
| Reserved HUD areas | quickslot (571, 8), 221×59 inside the bar; buffs 212×44 at (view width −224, 42); boss bars 300 px wide centred at y=42 with 42 px row pitch (37 px canonical icon frame) | C (layout), A (art size) | ours, difficulty overhaul |
| Starter equipment selection | Coat 1040002, Pants 1060002, Shoes 1072001; Sword 1302000 and Wooden Wand 1372005 loaded for job weapon selection | C (selection), A (info) | existing avatar look and v83 Character.wz |
| Elite name tag | mob name (String.wz) in the white 12 px system font on a black 60% box, 3 px padding, 15 px high, 2 px below the feet; hidden while dying | C | ours (v83 draws the default tag in code; `UI.wz/NameTag.img` holds only cash styles 3-28) |
| System messages | "+N EXP" in yellow (#FFFF00) with a black outline above the left end of the status bar, newest at the bottom; 4 s each (last 0.5 s fading), at most 6 lines | C | ours |
| Boss notices / respawn effect | keyed yellow notices above EXP and low-MP; warning lead / 4 s lifetime; BasicEff/Summoned at boss feet | C (selection/layout), A (art/timing) | ours; original v83 WZ |
| Missing boss UI metadata | Blue Mushmom uses Mushmom icon and 1/5 colour tags; King Slime uses 1/5 tags with its own icon | C (override), A (borrowed art) | survivor mobs.json.boss_ui |
| Mob draw layer | the foothold layer of the mob's current foothold, kept while it is airborne | C | ours |
| View fit | default: Godot's 800×600 expand + integer scale (1920×1080 → 1066×600 at 1× with bars); opt-in `fill_window`: s = ⌊min(W/800, H/600)⌋, view = window / s (3440×1440 → 1720×720 at 2×, 1920×1080 → 1920×1080 at 1×); windows below 800×600 are scaled down, not cropped | C | ours |
| Level-up window delay | the `LevelUp` effect plays 1.2 s (about its pillar's peak) on the character before the upgrade window opens; after a job advancement the next window waits for the whole `JobChanged` effect (~1.3 s; 1.3 s without the animation). Presentation only; the sim is already paused | C | ours |
| Frame cap | vsync on, `Engine.max_fps` = the display's refresh rate rounded up (144 when unknown, at least 30) | C | ours |
| Run end holds | results 2 s after the tombstone has landed; on a clear the party-quest `CLEAR` field effect (`Map.wz/Effect.img/quest/party/clear`, `Sound.wz/Field.img/Party1/Clear`) at the screen centre for 3.5 s | C | ours (art/sound A) |
| Invincibility blink, hit face | the whole character (one CanvasGroup) alternates alpha 1.0 / 0.4 every 0.08 s while invincible; face `hit` for 1 s after a hit | C | ours |
| Drop draw order | EXP drops are drawn after the mobs and the character of the character's foothold layer (never hidden in a crowd) | C | ours |
| Run start title | street name + map name (String.wz) under the timer for 3.5 s, the last 1 s fading | C | ours |
| Sound throttle | each sound path plays at most once per frame (a piercing shell through 20 mobs is one Damage sound) | C | ours |
| Character name tag | the character name under the feet in the elite name-tag style | C | ours |
| UI windows (level-up, job, pause) | open: 0.15 s fade-in while dropping 10 px; close: 0.12 s fade-out; keys ignored for 0.2 s after opening; the job dialog's confirmation line stays 1.8 s (any key/click skips) before `job_chosen` | C | ours (art A: UI.wz SkillUp, Skill rows, UtilDlgEx, Basic.img YesNo3) |
| In-run windows (#85) | stacked above the modal windows (CanvasLayer 11); 20 px title strip drags; 40 px of a window always stay in the view; first open centred above the status bar, then reopened where it was dragged; sim held while any is open | C | ours |
| Stat window layout (#85) | detail panel (`Stat/backgrnd2`) on the main panel's right edge with bottoms aligned, (175, 144); value text 61 px (main) / 80 px (detail) into the fields; BtDetail (120, 324) and BtUIClose (10, 325) in the bottom strip; attack = held weapon `incPAD`, magic = INT + magic attack, accuracy = buff accuracy only, speed/jump as v83 percentages, AP 0 | C (layout, stat mapping), A (art) | ours; `UIWindow.img/Stat` |
| Menu button and popup (#85) | `StatusBar.img/BtMenu` at (744, 20) of the 800 px bar, past the potion quickslot labels; popup in the `UIWindow.img/ContextMenu` style (`t`, a `c` row per entry, `s`; entries on BtInfo plates widened past the dot, our labels) right-aligned above the button | C (layout), A (art) | ours (the cache has no art for v83's Menu list) |
| Skill window layout (#86) | tab cells 27x17 from (8, 24), 28 px apart, the selected one a white plate; skill book icon at (9, 53), book name at (47, 64); rows (`skill1` learned, `skill0` not) from (11, 95), 40 px apart, 4 shown, `Basic.img/VScr5` scrollbar at (155, 95); SP box shows 0; BtUIClose at (134, 266); the selected / hovered row gets an orange outline; star tab: a drawn five-point star, banner "Job-neutral Cards"; tooltip a drawn dark box 290 px wide (v83 `UIToolTip.img` is not imported) placed beside the cursor or the selected row and kept above the status bar | C (layout, star, tooltip), A (art) | ours; `UIWindow.img/Skill` |
| Movement keys (#85) | Arrows by default (v83), WASD as an option; the chosen set's keys are taken off every other action | A (Arrows) / C (WASD option) | v83 client defaults; ours |
| Key Config window (#87) | bindable: jump, HP / MP potion, Teleport, Stat, Skill (#108: Equip E and Item I too, with KeyConfig `icon/0` EQUIPMENT and `icon/1` ITEMS; E left the MP potion); fixed: the movement set, Esc, 1-3; a key holds one action, an action may sit on several keys; Default = project keys less the movement set (WASD leaves Stat without a key); key rects measured on `KeyConfig/backgrnd`, tray slots (8 + 34i, 267 + 34r); Tab / Scroll Lock / Win / Menu are no drop targets; Default, Delete left and OK, Cancel right in the strip at y 237, BtClose (611, 6); icons: KeyConfig `icon/53` JUMP, `icon/2` ABILITY (Stat), `icon/3` SKILL, Red / Blue Potion, F/P Teleport | C (rules, layout), A (art, JUMP / ABILITY / SKILL icons) | ours; `UIWindow.img/KeyConfig` |
| Options window (#87) | `SysOpt/backgrnd` title, BGM and SOUND rows and bottom strip, two blank rows relabelled FRAME CAP and MOVE KEYS; slider track x 93-209 between the baked SOFT / LOUD; MUTE box (243, 9) restores the volume it had (else the default); frame caps: screen refresh, 60, 144, off | C (layout, choices), A (art) | ours; `UIWindow.img/SysOpt`, `Basic.img/Slider`, `Basic.img/CheckBox` |
| UI text colours | NPC dialog black text, options #0000FF (#b), unavailable grey #888888, system yellow #FFFF00; Arial/Tahoma/Dotum without antialiasing at 11-12 px | C | ours, matched to v83 screenshots |
| Web profile UI (#134) | title: Fullscreen / Export save / Import save lead the second button row (before Re-import WZ data) where desktop has Quit; Options: a FULLSCREEN check box in the FRAME CAP row; F11 and F12 not bindable on web (browser fullscreen / developer tools), Ctrl+W/T/N noted in the Key Config strip; text in the bundled Arimo (Arial metrics) because browsers have no system fonts | C | ours; docs/ARCHITECTURE.md 10 "Web profile" |
| Skill and card text | v83 String.wz `desc`/`hN` (A); survivor `skills.json` `text` overrides, the dropped Master Level / Required Skill lines, mod-card value labels and the rewritten card texts (C) | A / C | §8.2; SkillText (dress for level-up cards), LevelUpWindow |
| Best result per stage | a clear beats a death, then longer survival, then higher level, more kills, more damage (`user://save.json`) | C | ours |
| NX award per round (#115, spec #34) | a clear pays `clear_bonus[tier] + per_level x levels gained in the round + per_boss x scheduled bosses killed in the round`; a death pays the same without the clear bonus (bosses killed before dying count); the final tier's clear pays its normal clear award; deletion, Quit round and tool/one-off rounds pay nothing. Placeholders in `balance.json` `nx_award`: `clear_bonus` [100, 250] by 0-based tier (later tiers reuse the last), `per_level` 5, `per_boss` 40. The balance pass sets the numbers | C | ours; owner #34 triage (ADR 0003) |
| NX crediting and account block (#115) | the award is added to `account.nx` inside the same atomic write as the clear's round-boundary snapshot (so it is spendable in the Free Market at once) or the death/victory run archive; an optional top-level save key `account: {nx, owned}` (absent = 0 NX, nothing owned), `SaveData.FORMAT` stays 2; tool rounds record `nx_awarded` / `bosses_killed` / `levels_gained` and never write a save | C | ours; seams.md (no format bump) |
| NX display (#115) | results screen row "NX earned: +N NX" (persistent endings only); Free Market arrival notice "You have gained N NX." for 6 s under the instruction line; map select heading ends with the account balance | C | ours |
| Cash Shop screen (#118, spec #34) | `scenes/ui/cash_shop.gd`: the v83 `UI.wz/CashShop.img` screen, 800x600 centred, EQUIP. (Hat, Face, Eye, Overall, Top, Bottom, Shoes, Glove, Weapon, Cape) and PET (Pet, Pet Equip.) tabs, ten cards per page. Items are filed by Commodity SN (`CashShop.listing`: category 2 equipment, 6 pets; earrings under Face and shields under Weapon as in v83; VAC, which has no SN, last under Pet Equip.). Card art positions and the buy dialog are WZ/capture-measured (tier A/B, `CashShop` constants); other tabs, GIFT/RESERVE, Search Item, Best Item contents, Charge/Check Cash/Code, the family tabs and ON toggle, the Item Inventory tabs and slot buttons are not drawn (out of scope). Click = try on (`CashShop.try_on`), BUY = confirm dialog (NX CREDIT line checked, the only currency) then `CashShop.buy`, which deducts, adds, saves in one write and removes the item from the list; locked cards show "Needs a pet." / "Needs Wing Boots, Binocular and a pet." instead of BUY; too little NX shows the notice "You don't have enough NX."; BUY EQUIPPED ITEM is disabled (one purchase per card), RETURN TO DEFAULT / REMOVE ALL reset / strip the preview; the Cash Inventory lists owned items read-only. SHOP buttons: map select (every tier, the v83 `StatusBar.img/BtShop` beside Save & quit, centred on its plank) and the Free Market status bar (`StatusBar.img/BtShop` at bar +(688, 20)); Leave = EXIT or Esc, back to where it was opened | A for art and prices; B/C for positions, wording, SHOP button placement | cashshop-refs/layout.md (private), v83 WZ; owner rule: match the real client layout |
| Equip window layout (#108) | `UIWindow.img/Equip/backgrnd` 175x304; 32 px slot cells hat (38, 35), top / overall (38, 134), bottom (38, 167), shoes (71, 200), gloves (5, 167), weapon (104, 134); BtUIClose at (10, 281); opens left of the view's centre, the Item window right of it | C (measured on the v83 art; the cells cross-checked B against JourneyClient's slot offsets), A (art) | ours; `UIWindow.img/Equip` |
| Equip window Cash tab and Pet page (#122, spec #34) | the Equip window gains pages (`EquipWindow.set_page`): Equip (unchanged), Cash and Pet. v83's `UIWindow.img/Equip` has no Cash tab art, so the Cash page re-uses the `backgrnd` grid with the 11 cash slots in the cells their baked labels name (hat CAP (38, 35), face FOREHEAD (38, 68), eye EYE ACC (71, 101), earrings EAR ACC (104, 101), top CLOTHES (38, 134), bottom PANTS (38, 167), shoes (71, 200), gloves (5, 167), cape MANTLE (5, 134), weapon (104, 134), shield (137, 134)); an overall shows in CLOTHES and dimmed in PANTS, a two-handed cover in WEAPON and dimmed in SHIELD. The page switch is the Equip / Cash glyphs of `Item/Tab` at (46, strip) / (76, strip) and the v83 `Equip/BtPetEquipShow` ("PET EQUIP.") button at (104, strip), in the art's bottom strip. The Pet page is `Equip/pet` (177x181): owned upgrades sit read-only in HP POC (1812002), MP POC (1812003), ITEM POC (1812001, base pet), MESO MAG (1812000, base pet), POS (Binocular 1812005), PET EQUIP (VAC 9990000) and MOVE UP (Wing Boots 1812004), the character's own HP / MP potion shows in PET HP / PET MP when the matching pouch is owned. A drawn panel (152 px wide, 4 columns of 36 px, wheel or arrows page it) beside the page lists the account's owned cash equipment (slot order) or pets; a double-click wears / takes off / brings out / puts away. `RunWorld.wear_cash` / `take_off_cash` / `set_pet` apply it (`CashCatalog.wear`: an overall clears top and bottom, wearing a top or bottom takes it off, a two-handed cover takes weapon and shield); the world's Fortune follows at once, so the next card draw uses it. Persistent rounds now receive the saved account (`SceneFlow._resume_round` sets `options.account`), so the owned list and worn items count in a round | C (the page layout, the panel, the upgrade-to-label mapping and the glyph tabs are ours; the art and cells are A / measured on the v83 images) | ours; `UIWindow.img/Equip`, `UIWindow.img/Item/Tab` |
| Item window layout (#108) | `UIWindow.img/Item/backgrnd` 175x289; tab glyphs (`Tab/enabled` shown, `Tab/disabled` the rest) at x 10 / 42 / 74 / 108 / 139 in the 19 px strip at y 23; slots 4 x 6 from (8, 50), 36 px apart horizontally and 34 vertically; stack counts in `Basic.img/ItemNo` digits at the slot's (1, 21); mesos right-aligned in the field (25, 267, 113x14) beside the baked MESOS; `BtCoin` shown disabled (mesos are never dropped) | C (measured on the v83 art; tab offsets B from JourneyClient), A (art) | ours; `UIWindow.img/Item` |
| Inventory mouse protocol (#108) | a double-click wears / takes off; a press that moves 4 px starts a drag drawn under the cursor; the release resolves against the window stack (another inventory window takes the drop, no window = discard after the YesNo box, anything else nothing); a drop anywhere on the Equip window wears the item in its own slot | C (ours; v83 drags onto the exact slot) | ours |
| Item tooltip (#108) | drawn dark box 262 px wide (v83 UI.wz has no UIToolTip.img); `ToolTip/Equip/Can` / `Cannot` label and digit art for REQ LEV / STR / DEX / INT / LUK (three digits, 6 px cells) and the job words; `Property` labels 3 CATEGORY, 4 ATTACK SPEED, 6-11 and 13-14 the attack / defence / accuracy / avoid / speed / jump lines, 16 NUMBER OF UPGRADES AVAILABLE; `ItemCategory` 1 HAT, 5 TOP, 6 BOTTOM, 7 SHOES, 8 GLOVE, 21 LONGCOAT; `WeaponCategory` by item id / 10000 - 100; `Speed` 0-6 FASTEST..SLOWEST from attackSpeed 2, 3, 4-5, 6, 7, 8, 9; STR / DEX / INT / LUK / MaxHP / MaxMP as text; "(+N)" after the name for N successful scrolls | A (art, read), B (speed words, scroll count: RE clients), C (layout, mapping) | ours; `UIWindow.img/ToolTip` |
| Inventory messages (#108) | "You do not meet the requirements to equip this item." / "Your inventory is full. Make room before taking an item off." as HUD notices; the YesNo box asks "Are you sure you want to drop this item?" | C (the v83 client's wording is unverified) | ours |
| Cap hair cover (#108, corrected in #126) | `hairOverHead` is `Base.wz/smap.img` code H1, so it is hidden exactly by a cap whose `info/vslot` holds H1 (CpH1H5 half-cover, the full-head covers); a CpH5 headband (68 real caps) leaves it drawn over the band (the bangs fall over the headband: `zmap` puts `hairOverHead` in front of `cap`). Without a cap the `*BelowCap` hair layers are not drawn. #108 had it the other way round (CpH5 hid hairOverHead); `AvatarRenderer.hair_layers_skipped` and the smap hiding above now agree. Evidence: `hair_cap_probe.tscn` sheets on hairs 30000 / 30002 / 30020 with the CpH5 caps 1002067 and 1002317 and the CpH1H5 cap 1002001 (the old rule strips the bangs and leaves the headband on a bare forehead); the ladder stances show no difference (the hair covers the cap from behind) | A (smap codes, cap vslot, zmap order) / B (agreement) | `Base.wz/smap.img` + `zmap.img`, `Character.wz/Cap/*/info/vslot`; the v83 clients in the prior-art clones map CpH1H5 to half-cover (overhead hair not drawn) and CpH5 to headband (overhead hair drawn over the cap), re-implemented from prose |
| Scroll rules (#110) | a scroll fits when `(scroll id / 100) % 100 == (item id / 10000) % 100` and the worn item has an upgrade slot; roll 0-99 below `info/success` adds the scroll's `inc*`, counts one scroll; every use spends one slot and the scroll; a failed scroll with `info/cursed` destroys the item at a 0-99 roll below it; only worn items can be scrolled, never inventory items | A (id convention, `success` / `cursed` / stats read from `Item.wz/Consume/0204.img`), C (roll order, nothing else) | v83 data; ticket #110 |
| Scroll roster (#110) | `game/data/survivor/scrolls/<line>.json` (common = armour slots, magician = wand and staff): slot -> family -> `100` / `60` / `10` / `dark70` / `dark30` ids; the strong 100%, event 65% / 15%, 50% and other classes' scrolls are out; 2040016 (hat ACC 10%, WZ `success` is the string "10", cast by `DataRepo.scroll_info`) is in; two DEX / LUK series for hat, top and bottom are listed as separate families | C (selection), A (every id and its stats) | ours; `Item.wz/Consume/0204.img` |
| Scroll RNG stream (#110) | RunWorld stream 11 (`scroll_rng`) rolls success and curse; the Free Market world is seeded per visit with `randi()` and saves after every scroll so a reload cannot redo a roll | C | ours |
| Scroll stacks (#110) | a stack holds `info/slotMax` scrolls (100 when WZ names none: all of 0204 do); the Use tab has 24 slots, two taken by the potion stacks, so 22 scroll stacks | A (24 Use slots, 100 stack), C (potions occupying two) | v83 inventory; ours |
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

## 12. Later phases

Remaining second-job skills and behavior arrive in spec #31 sibling tickets; #53 enables all three branches and the existing Fire Arrow. Later: more maps (Henesys Hunting Ground II), more mobs.
The Tree That Grew I and the six stage bosses are already playable. Phase 3: other Explorer paths, 3rd/4th job,
additional bosses, elite waves with modifiers, passive items, skill evolutions, run modifiers, persistent unlocks.
