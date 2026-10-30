# Maple Survivors

A single-player, offline survivor game played on MapleStory v83 maps: one character fights swarms of the original
monsters through a series of increasingly hard maps.

## Runs and rounds

**Run**:
No longer a unit of play (ADR 0006): a character has no journey that ends. The word survives only in tool names
(`--run`, "run scene") for one round. Say character or round.
_Avoid_: Game, save, playthrough

**Character**:
The named, persistent hero a player creates: its name, look, 4th job (chosen at creation, never changed), worn
equipment and inventory, scrolls, mesos, cash equipment, pet and unlocked tiers. It has no level, EXP, skills or AP
between rounds: those belong to a round and start fresh at Lv1 (save format 3, #286).
_Avoid_: Player (the person), avatar (the drawing), hero

**Character slot**:
One of the three places a character is kept between sessions; a character occupies a slot until the player deletes it.
Dying never frees a slot.
_Avoid_: Save file, profile

**Round**:
One stage played by a character from Lv1, from its first map until all its maps are cleared, the character dies or the
player quits the round (Quit round counts as a death). Every round is standalone and ends back in the Free Market. A
round exists only while it is played: closing the game mid-round loses it.
_Avoid_: Level, wave, run

**Stage**:
A region's ordered maps with their monster rosters, pacing and bosses; a round is one play of a stage.
_Avoid_: Level, map (a map is one v83 location within a stage)

**Map clear**:
Defeating a map's scheduled boss and finishing the choices its collected drops and reward require.
_Avoid_: Round clear (only the last map clear clears the round)

**Map transfer**:
The automatic move after a map clear to the next map of the same round, carrying the character's current condition.
_Avoid_: Round boundary (a transfer stays inside the round), checkpoint

**Tier**:
A difficulty step, holding one or more stages. Tier 1 is always open; clearing any stage of tier N unlocks tier N+1 for
that character, and every unlocked tier can be replayed.
_Avoid_: Act, world, chapter; not to be confused with a job tier or a card's rarity

**Round boundary**:
The moment between two rounds. The character is saved with what the finished round gave it (mesos, equipment, scrolls,
and an unlocked tier after a clear).

**Character snapshot**:
The character as saved (format 3): what it keeps between rounds, listed under Character. There is no saved round to
resume: saves happen at the Free Market and when a round ends.
_Avoid_: Run snapshot, mid-round save, checkpoint

**Free Market**:
The walkable hub (v83 Free Market Entrance) that is a character's home: it starts there, returns there after every
round, and goes up at its exit to map select.
_Avoid_: Town, lobby, shop (shops live inside it)

**Map select**:
The screen where a character picks the stage of its next round, from every stage of every tier it has unlocked (a
locked tier is shown greyed).
_Avoid_: Stage select (the old single-stage screen)

**Round history**:
One entry per round (character, job, stage, level reached, how it ended: cleared, died or quit), plus one when a
character is deleted and one for each character of an old save (retired, format 2 files).
_Avoid_: Run history, graveyard, hall of fame

**Best result**:
The best round ever played on a stage, kept per stage across all characters.
_Avoid_: High score

**One-off round**:
A single round with a fresh or supplied character that belongs to no slot and is never saved; only tools start one.
_Avoid_: Quick play, practice run

## Account and NX

**Account**:
Everything the player keeps across characters: NX, cash items, round history and best results.
_Avoid_: Profile, meta save, meta progression

**NX**:
The account's currency, earned at the end of every round and spent in the Cash Shop.
_Avoid_: Cash, gems, meta currency; not mesos (mesos belong to one character)

**Cash item**:
Anything bought with NX: owned once by the account, never expires, and every character can use it.
_Avoid_: Meta upgrade

**Cash Shop**:
The v83-style screen where NX is spent on cash items.
_Avoid_: Store, meta shop (a shop is a Free Market NPC's scroll stock)

**Cash equipment**:
Cash items a character wears in its cash slots, drawn over its equipment; every filled cash slot adds Fortune.
_Avoid_: NX gear, cosmetics, outfit; not equipment (equipment drops from monsters and has stats)

**Cash slot**:
One place cash equipment is worn: hat, face accessory, eye accessory, earrings, top, bottom, shoes, gloves, cape,
weapon cover or shield. Cash slots are separate from equip slots; an overall fills the top and bottom cash slots.
_Avoid_: Slot (on its own), equip slot

**Pet**:
A cash item companion that follows the character and picks up drops near it; a character has at most one out.
_Avoid_: Familiar, companion

**Pet upgrade**:
A cash item that gives whichever pet is out an extra ability: auto HP or MP potion, Wing Boots, Binocular or VAC.
_Avoid_: Pet equip (an upgrade belongs to the account, not to one pet or character), pet skill

## Jobs

**Job**:
A v83 Explorer job, referred to by its numeric id (0 Beginner, 200 Magician, 210 Wizard (Fire, Poison), ...).
_Avoid_: class (reserved for the five Explorer lines: Warrior, Magician, Bowman, Thief, Pirate)

**Job tier**:
How many advancements a job is from Beginner: 0 Beginner, 1 first job, 2 second job, and so on.

**Job line**:
A first job and every job below it, named after it (warrior, magician, bowman, thief, pirate), plus beginner for
job 0 and common for job-neutral data. A class spec after the slice adds a *data line* named after the class
(`hero`, #296), discovered by `DataRepo.lines()` after the fixed Adventurer lines, sorted by name, so jobs of the same Adventurer line no longer share one file. Survivor data and the asset manifest keep one file per line
(`survivor/<name>/<line>.json`, `asset_manifest.d/<line>.json`), and a per-job table resolves a job through its
lineage to the nearest listed ancestor.
_Avoid_: class line, family (a weapon family is a kind of weapon)

**Job advancement**:
The player's choice in the job window of a child job once the character level allows it. It grants no skills; the
new job's skills come only from cards. An advancement grants and wears only the chosen weapon family's weapon.
_Avoid_: job change, promotion

**Advancement weapon**:
A weapon a job advancement hands the character for its chosen family; the previous weapon goes to the Equip tab
or lies at the character's feet when the tab is full.
_Avoid_: job reward, starter weapon

**Branch**:
One of the second-job paths a first job splits into, e.g. the Magician's Fire/Poison (210), Ice/Lightning (220)
and Cleric (230).
_Avoid_: path (on its own; a weapon path is a weapon-family choice), specialisation, subclass

**Weapon path**:
A weapon-family choice at a job advancement with more than one family: Warrior Sword/Spear/Blunt Weapon, Bowman
Bow/Crossbow, Thief Claw/Dagger, Pirate Knuckle/Gun, and the two-family Warrior branches at second job. It chooses
the advancement weapon; later weapon swaps still decide which skills and cards can be used.
_Avoid_: branch (that is the second-job choice), build, stance

## Skills

**Auto-cast skill**:
A skill the run casts for the player when its trigger holds and MP allows: attacks at targets in range, buffs when
inactive, heals below an HP threshold, Slow when enough monsters are near.

**Manual skill**:
A skill the player triggers with its own skill key, such as Teleport or Dash.

**Hidden**:
A timed state in which monsters, bosses included, neither chase nor attack the character, and the character cannot
attack; Oak Barrel and Dark Sight put the character in it.
_Avoid_: stealth, invisible, cloaked

**Morph**:
A buff that draws the character as a `Morph.wz` figure instead of its avatar for as long as it lasts, such as Oak
Barrel's barrel (Morph 1002); the game's movement and stats are unchanged unless the buff itself says so. A morph
draws its own action for a stance when the figure has one (the Buccaneer morphs attack), else it stands.
_Avoid_: transformation, disguise

**Morph form**:
A Form whose `buff` block carries a `morph_field`, so it also draws the character as a Morph and gives the buff's defence,
speed and jump while it lasts (Buccaneer's Transformation and Super Transformation). It needs no Form effect key.

**Reaction skill**:
A skill that nothing casts on a timer or a key: the world triggers it when something happens to the character. Resurrection
is the first: it catches a lethal hit (its cast rule is `reaction`, so the auto-caster and the bot never use it).
_Avoid_: trigger skill, passive (it takes an active slot)

**Second life**:
The save a reaction skill makes when a hit would kill the character: it returns at part of its max HP, guarded for a
moment, the monsters around it shoved away, then the skill recharges (its cooldown) before it can happen again.
_Avoid_: revive (which also names reviving a party member in v83), extra life (a stock)

**Guard**:
The short span after a second life in which no hit lands at all, including boss attacks and balls that ignore the hit
window.
_Avoid_: invincibility (the hit window and Invincible are other things), shield

**Skill key**:
The Key Config binding of one manual skill the character has learned.
_Avoid_: hotkey, quickslot

**Chain**:
A cast that hits its first target, then jumps from the previous target to the nearest unhit monster within its hop
radius, stopping at its target cap or when no neighbour is in reach. Chain Lightning draws a bolt along those links.
_Avoid_: splash, bounce (which can imply repeat hits)

**Skill template**:
A skill definition with `"extends": "<key>"`: it inherits another definition and rewrites its art and sound paths to
its own book and skill id (the I/L Big Bang extends F/P's; Bishop can reuse the same template). Resolved only by `SkillBook`.
_Avoid_: copy, clone, alias

**Passive skill**:
A skill that is always in effect once learned and is never cast, such as MP Eater.

**Attack skill**:
A skill whose cards raise the character's damage output: an auto-cast or manual attack, and a passive that strikes
on its own, such as Final Attack.

**Final Attack**:
A passive that sometimes follows one of the character's hits with an extra strike, only while its weapon family is
held. It is a Warrior branch's attack skill.
_Avoid_: follow-up skill, proc

**Party buff**:
A v83 buff that also covered party members (Rage, Iron Will, Hyper Body); here it affects the character only.

**Form**:
A timed active stance that changes the character's attacks and carries sub-skills. A running form survives
map transfer and ends on death. Its buff block carries Hidden or morph state; effect keys are for cast-stat or lifecycle behaviour (Buccaneer template: `spec/412`, `test_morph_form.gd`).

**Charge**:
A Paladin Form that temporarily gives its attacks an element and carries Charged Blow. Holy Charge also
carries Heaven's Hammer. Only one Charge runs at a time.

**Sub-skill**:
An attack carried by a Form, used automatically while the form lasts. It grows with its parent, occupies no
skill slot and is never offered as a card.

## Cards and rarity

**Rank**:
A skill's survivor level, equal to its canonical v83 skill level; each rank card adds one.
_Avoid_: skill level (in card text), tier

**Behaviour card**:
A card that changes how one owned skill behaves (more projectiles, pierce, targets, area, a shorter cooldown)
without adding a rank.
_Avoid_: stacking card, mod card, upgrade card (that means any card)

**Carried attack**:
A first-job attack skill of a physical class (Warrior, Bowman, Thief, Pirate) whose cards stay on offer after the
second job, though never in the advancement draw. A Magician's earlier-job cards stop at each advancement.
_Avoid_: legacy skill, kept skill

**Advancement draw**:
The extra card draw a job advancement opens before that level's normal draw: every new attack skill of the new job,
topped up with its other new skills.
_Avoid_: guaranteed card, job reward

**Fortune**:
The character's survivor stat that makes rarer cards more likely, mostly from cash equipment; unrelated to the v83
LUK stat.
_Avoid_: Luck, LUK

**Rarity**:
A card's Potential tier (Normal, Rare, Epic, Unique, Legendary), which sets how much the card gives.
_Avoid_: Quality, grade, card tier (tier is the run's difficulty step)

## Survivor progression (ADR 0006, `redesign` branch)

ADR 0006 replaces v83 progression. These terms come in with it. Run, run snapshot, victory, job advancement,
advancement draw, advancement weapon, branch, weapon path, carried attack and behaviour card go away as each job
moves to the new system. Rank, rarity, tier, character, mesos and equipment are redefined below or in ADR 0006.

**Skill pool**:
The hand-picked active skills a job's cards can offer, taken from its whole 1st-4th job lineage.
_Avoid_: skill tree, class skills, deck

**Starting skill**:
The one skill from its pool a job begins every round with, already in its first active skill slot.
_Avoid_: basic attack (removed), default skill

**Skill slot**:
One of a character's six active or six passive places in a round. A new skill takes a free slot of its kind, and
the cards stop offering new skills of that kind once all six are full.
_Avoid_: slot (on its own), weapon slot, equip slot

**Common passive**:
A job-neutral, Maple-named stat boost (Maple Warrior, Hyper Body, Haste, ...) that fills a passive skill slot. It
caps at rank 5 and never rolls rarity.
_Avoid_: talent, shared passive (the old cross-branch passives), passive skill (a job's own passives, no longer
offered)

**Rarity bonus**:
The behaviour change (more damage, pierce, area, projectiles, a shorter cooldown, a status) that a Rare or better
card for an active skill attaches to its rank. Each skill has its own bonus list per rarity.
_Avoid_: behaviour card (the old standalone card), mod

**Mastery card**:
A card for an active skill already at rank 8: it adds no rank, only a rarity bonus, with diminishing returns per
stack, so an active skill never fully maxes.
_Avoid_: overrank, limit break; not a weapon mastery skill (Sword Mastery and similar)

**Tier unlock**:
A character's permission to pick a tier's stages, earned by clearing any stage of the tier before it.
_Avoid_: level gate, progress

**Drop band**:
The `reqLevel` range of equipment a tier's monsters drop (tier 1 0-30, tier 2 30-60), with bosses rolling from its top
third. It replaces the character's level in the drop rule; `reqLevel` is no longer a requirement to wear the item.
_Avoid_: loot table, item level

## Monsters

**Status effect**:
A timed condition a skill puts on a monster: slowed, poisoned, frozen, threatened (weaker attacks and defence) or
stunned (neither moving nor attacking). Bosses take none.
_Avoid_: debuff, ailment

**Vulnerability**:
A status effect that makes a monster weak to one element for a time (x1.5 damage of that element, whatever the
monster's own attribute): Fire Demon's ice-weak and Ice Demon's fire-weak. A monster can carry several, and bosses take
none. A mixed-element hit (fire/poison, ice/lightning) is the mean of its parts, each counted with its live weakness.
_Avoid_: debuff, curse

**Mount**:
A taming-mob image (`Character.wz/TamingMob/<id>.img`) drawn under and over the avatar for the life of a form that names one
(`presentation.mount`): the rear canvas behind the rider, the front canvas in front, the rider seated at the mount's navel. Corsair's
Battleship is the only one. Presentation only: no mount speed, jump or hitbox.
_Avoid_: pet (a pet follows, a mount carries), vehicle

**Mark**:
A timed status (`all_weak`) that makes every hit on a monster deal x1.5 (x1.25 on a boss, which can be marked unlike the
other statuses), elemental or not, on top of any element multiplier; the player's nearest-rule shots, bursts and summons
also prefer a marked monster (after scheduled bosses). Corsair's Homing Beacon applies it; Bullseye raises it.
_Avoid_: debuff, curse, vulnerability (a vulnerability is one element only)

**Stolen**:
A monster a successful Steal has already taken an extra drop from; Steal can't take from it again. It is not a
status effect, so a boss can be stolen from.
_Avoid_: robbed, looted

**Element attribute**:
A monster's canonical weakness (x1.5), resistance (x0.5) or immunity (x0) to an attack element: fire, ice,
lightning, poison or holy.

**Undead**:
A monster flagged undead in Mob.wz: Heal damages it and Holy Arrow is strong against it.

**Contact damage**:
The damage a monster deals by touching the character, separate from its attacks.
_Avoid_: touch attack, body attack (in player-visible text)

**Mob attack**:
An ordinary monster's canonical Mob.wz attack (`attack1`, `attack2`, ...): a windup, then a hit in its range, as
Tauromacis and Taurospear have. A boss attack is the same thing used by a scheduled boss.
_Avoid_: monster skill (that is a mob skill)

**Mob skill**:
A canonical Skill.wz/MobSkill.img skill a boss casts, such as Slow or a summon. Ordinary monsters cast none, so
status effects on the character only ever come from bosses.

**Knock-back**:
A skill effect that pushes a struck monster away from the character, by a chance per hit. Bosses are never knocked
back. It is not the small push any hit gives a monster whose damage reaches its canonical `pushed` threshold.
_Avoid_: push-back, knockdown

**Pull**:
A skill effect that drags monsters toward the character along their platform, by a chance per monster, until they stand
a set gap away. It picks the farthest monsters first, up to the skill's monster count. Bosses and airborne monsters are
never pulled. It is the mirror of knock-back (Monster Magnet, Snatch).
_Avoid_: magnet, suck, vacuum

**Burn**:
A fire status that hurts a monster once a second for a few seconds, a little each time and never enough to kill it. The
size of every pulse is decided by the cast that set the monster alight, and setting it alight again refreshes the burn
without restarting or stacking it. Bosses and fire-proof monsters don't burn. It is the fire twin of poison (Inferno).
_Avoid_: ignite, fire damage-over-time

**Hit window**:
The short time after the character is hit during which it can't be hit again. It shrinks with repeated hits, and
boss attacks ignore it.
_Avoid_: i-frames, invincibility (Invincible is a skill)

**Alive cap**:
How many monsters a stage keeps alive at once at a given moment of the round. It rises over the round and keeps
rising slowly after the last boss arrives; bursts, elites and boss summons may go past it, up to the stage's hard
limit.
_Avoid_: mob cap, max mobs

## Mesos and equipment

**Mesos**:
The run's money: dropped by monsters, spent on scrolls in the Free Market shops (which also buy spare equipment and
scrolls back), and carried between rounds with the character; a death or a clear keeps them.
_Avoid_: Gold, coins, money; not to be confused with NX, which outlives runs

**Equipment**:
The v83 items a character can wear, each with its real stats. Its job class is the only requirement to wear it: its
`reqLevel` and stat requirements do not apply (they place it in a tier's drop band). Equipment comes only from monster
drops (plus the creation weapon of a new character), never from shops, and stays with the character between rounds.
_Avoid_: Gear (in player-visible text), armour, loot

**Equip slot**:
One place equipment is worn: hat, top, bottom, overall, shoes, gloves, weapon or shield. An overall fills the top and
bottom slots together; a two-handed weapon blocks the shield slot.
_Avoid_: Equipment slot, gear slot

**Weapon family**:
The weapon kind a mastery, booster or weapon-gated skill refers to: sword, axe, blunt weapon, spear, polearm, bow,
crossbow, claw, dagger, knuckle, gun, wand or staff; swords, axes and blunt weapons count their one- and two-handed
versions as one family. A skill that names a family casts, and its cards are offered, only while the weapon held belongs
to it (a skill that names none works with any weapon, bare hands included); weapon drops come only from the held
family (a wand and a staff count as one for drops).
_Avoid_: weapon type (in docs; that is the v83 item-id prefix), weapon class

**Ammo tier**:
The throwing stars, arrows or bullets a ranged character fires: one real v83 ammo item at a time, endless and never
an item stack. The weapon family starts on basic ammo; the exact job and round level select later tiers, changing
the projectile you see (each round starts at Lv1).
_Avoid_: ammo card, ammo stack, projectile (that is the shot on screen)

**Ammo schedule**:
The ammo milestones for one exact job and weapon family, reached at fixed levels within a round. A different
job or weapon family starts with its own basic ammo; milestones are not inherited from ancestor jobs.

**Worn equipment**:
The equipment currently in a character's equip slots; only worn equipment adds stats.
_Avoid_: Loadout (that is the character's skills and cards), outfit

**Inventory**:
The equipment and scrolls a character owns but is not wearing; it is carried between rounds with the character.
_Avoid_: Bag, stash

**Shop**:
An NPC's stock of scrolls in the Free Market, opened by talking to the NPC. Shops never sell equipment or potions.
_Avoid_: Store, vendor

**NPC Chat**:
The key (Space by default, as in v83, rebindable in Key Config) that opens the shop of the Free Market NPC the
character stands next to.
_Avoid_: Interact key, talk key

**Scroll**:
A v83 item that, used on a piece of equipment, tries to add stats with its success rate (10%, 60%, 100% ...) and
uses up one of that equipment's upgrade slots.
_Avoid_: Enchant, upgrade (in player-visible text), rune

**Dark scroll**:
A scroll (70% or 30%) whose failure can also destroy the equipment it was used on, at the scroll's own curse rate (50%).
Plain scrolls only ever spend the upgrade slot.

**Upgrade slot**:
One of a piece of equipment's limited chances to be scrolled; each scroll used on it spends one, pass or fail.
_Avoid_: Slot (on its own; that means an equip slot), tuc

## Interface

**Choice window**:
A modal window that holds the run until the player answers it: the level-up, job advancement and advancement card
choices, and the pause menu.
_Avoid_: dialog, popup

**In-run window**:
A draggable MapleStory window the player opens during a run (Stat, Skill, Equip, Item, Key Config, Options) or the
Menu list.
In-run windows stack, the run is paused while any is open, and Esc closes the front one first.
_Avoid_: panel, overlay

## Platforms

**Web build**:
The game exported to run in a desktop browser, from the same project as the desktop build; it plays on data the
player imports into the page.
_Avoid_: HTML5 version, online version (the game stays offline)

**Web shell**:
The web build's HTML/JS outside `game/`: the import screen, the importer worker and save backup. It is the only code
allowed to make requests, and only for the game bundle and the import source the player named.
_Avoid_: launcher, wrapper

**Import source**:
Where one import reads the player's v83 `.wz` files from: an install folder, a `.zip`, or (web build only) a URL the
player pastes.
_Avoid_: mirror (the project never names one), WZ root (that is the desktop folder setting)

**Summon**:
A timed player-owned ally cast by an active skill. It follows or waits at its own position and attacks monsters or pulses support effects;
its map-local lifetime ends on expiry or map transfer. It occupies its skill’s active slot, uses the original skill
id and WZ animations, and is separate from a cash pet or a monster summoned by a boss.

**Support summon**:
A summon whose definition carries `summon.support`: it follows its owner and pulses instead of attacking. Its pulses'
numbers come from sub-skills read through the summon's rank; the Beholder is the first.
_Avoid_: pet, attack summon (the ordinary summon), buff skill

**Pulse**:
One timed effect of a support summon (a heal or a buff on the owner), with its own countdown per summon, its own
animation and a `support_pulse` event. A pulse kind is an entry of `SupportSummons.KINDS`.
_Avoid_: tick, proc (a pulse is on a timer, never a chance)

**Meter**:
A round-owned integer counter, filled by configured events and spent by finishers. It survives map transfers,
starts at zero each round, and is shown as HUD pips. M1 is shared by Hero, Buccaneer and Shadower.
_Avoid_: mana, buff, form

**Combo orb**:
One unit of Hero's Combo meter. A landed non-finisher pool cast earns one; each held orb adds damage.
_Avoid_: Combo Attack card (Combo is intrinsic and takes no slot)

**Energy Charge**:
Buccaneer's meter (id `energy`, ten units). A landed non-finisher pool cast earns one energy; each held energy adds 3% damage to
every pool skill. The finishers Energy Drain and Energy Orb spend all of it. A full bar plays a one-shot cue (the `affected` ring and sound).
_Avoid_: the v83 Energy Charge stat window and Body Attack (not implemented); mana

**Finisher**:
A pool active whose meter block gates admission and spends units for extra damage. Panic and Coma are Hero's
finishers; Energy Drain and Energy Orb are Buccaneer's. Their meter_keep rarity modifier leaves units unspent.
_Avoid_: ultimate, proc

**Physical follower**:
A player summon (Silver Hawk, Phoenix, Golden Eagle, Frostprey) whose damage is physical and takes its W.Att from the skill level's `pad` instead of the worn weapon, optionally stunning on hit and flying above its trailing point. It is the Elquines seam (`PlayerSummons`) with data keys, not a separate system.
_Avoid_: pet (the Free Market pet is a cosmetic companion), minion

**Turret**:
A player summon with `summon.behavior: "turret"` (the Corsair Octopus): planted where it is called, it fires one visible ball per
target at monsters inside a circle around it and the hit lands when the ball arrives. `SummonTurret`.
_Avoid_: totem, tower

**Kamikaze**:
A player summon with `summon.behavior: "kamikaze"` (the Corsair Gaviota): it flies at one chosen monster, strikes once and is spent.
`SummonKamikaze`.
_Avoid_: bomber

**Burst**:
One automatic cast that schedules its resolved shot count over time, following the moving character's hand and a
live target. The cooldown begins on admission; unfinished shots belong to the current map (`BurstCast`, #336).

**HP risk**:
A skill that pays HP: a percentage of max HP as its cost, a gate that needs HP above a share of max HP, and recoil. It
never kills the caster. Dark Knight is the first user; Bishop and Buccaneer reuse the same blocks.
_Avoid_: life cost, blood magic

**Recoil**:
HP a skill takes from its caster after it hit, as a share of the damage the cast dealt, capped at a share of max HP and
never the last HP. Reported as `hp_spent` with kind `recoil`.
_Avoid_: backlash, self-damage (the data block is named `self_damage`)
