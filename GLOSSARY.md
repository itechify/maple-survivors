# Maple Survivors

A single-player, offline survivor game played on MapleStory v83 maps: one character fights swarms of the original
monsters through a series of increasingly hard maps.

## Runs and rounds

**Run**:
One character's whole journey, from creation until it dies, clears the last tier or is deleted.
_Avoid_: Game, save, playthrough

**Character**:
The named, persistent hero a run belongs to: level, EXP, job, AP stats, skills, potions and look.
_Avoid_: Player (the person), avatar (the drawing), hero

**Character slot**:
One of the places a living character is kept between sessions; a character occupies a slot until its run ends.
_Avoid_: Save file, profile

**Round**:
One full stage played by a character: survive the stage's time and defeat its bosses to clear it.
_Avoid_: Level, wave, run (a run is many rounds)

**Stage**:
A playable map with its own monster roster, pacing and bosses; a round is one play of a stage.
_Avoid_: Level, map (a map is the v83 art and layout a stage is played on)

**Tier**:
A difficulty step of the run, holding one or more stages; a character plays one stage from each tier in order.
_Avoid_: Act, world, chapter; not to be confused with a job tier or a card's rarity

**Round boundary**:
The moment between two rounds, where the character is carried over and HP and MP refill.

**Run snapshot**:
The character as it stood at the last round boundary, together with the next round's stage and seed; resuming a run
always starts from it.
_Avoid_: Mid-round save, checkpoint

**Free Market**:
The walkable hub (v83 Free Market Entrance) a character visits after every cleared round, before map select.
_Avoid_: Town, lobby, shop (shops live inside it)

**Map select**:
The screen where a character picks the next tier's stage.
_Avoid_: Stage select (the old single-stage screen)

**Victory**:
The end of a run that clears the last tier there is.

**Run history**:
The list of ended runs and how each ended: died, victory or deleted.
_Avoid_: Graveyard, hall of fame

**Best result**:
The best round ever played on a stage, kept per stage across all runs.
_Avoid_: High score

**One-off round**:
A single round with a fresh or supplied character that belongs to no run and is never saved; only tools start one.
_Avoid_: Quick play, practice run

## Account and NX

**Account**:
Everything the player keeps across runs: NX, cash items, run history and best results.
_Avoid_: Profile, meta save, meta progression

**NX**:
The account's currency, earned at the end of every round and spent in the Cash Shop.
_Avoid_: Cash, gems, meta currency; not mesos (mesos belong to one run)

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
job 0 and common for job-neutral data. Survivor data and the asset manifest keep one file per line
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
Barrel's barrel (Morph 1002); the game's movement and stats are unchanged.
_Avoid_: transformation, disguise

**Skill key**:
The Key Config binding of one manual skill the character has learned.
_Avoid_: hotkey, quickslot

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

## Monsters

**Status effect**:
A timed condition a skill puts on a monster: slowed, poisoned, frozen, threatened (weaker attacks and defence) or
stunned (neither moving nor attacking). Bosses take none.
_Avoid_: debuff, ailment

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
scrolls back), carried between rounds with the character, and lost when the run ends.
_Avoid_: Gold, coins, money; not to be confused with NX, which outlives runs

**Equipment**:
The v83 items a character can wear, each with its real stats and its level, job and stat requirements. Equipment
comes only from monster drops (plus the weapon a job advancement hands over), never from shops.
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
an item stack. The class starts on its basic ammo, and the specialist branch moves up the tiers by itself at fixed
levels, changing the projectile you see.
_Avoid_: ammo card, ammo stack, projectile (that is the shot on screen)

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
