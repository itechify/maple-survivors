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

## Jobs

**Job**:
A v83 Explorer job, referred to by its numeric id (0 Beginner, 200 Magician, 210 Wizard (Fire, Poison), ...).
_Avoid_: class (reserved for the five Explorer lines: Warrior, Magician, Bowman, Thief, Pirate)

**Job tier**:
How many advancements a job is from Beginner: 0 Beginner, 1 first job, 2 second job, and so on.

**Job advancement**:
The player's choice in the job window of a child job once the character level allows it. It grants no skills; the
new job's skills come only from cards.
_Avoid_: job change, promotion

**Branch**:
One of the second-job paths a first job splits into, e.g. the Magician's Fire/Poison (210), Ice/Lightning (220)
and Cleric (230).
_Avoid_: path, specialisation, subclass

## Skills

**Auto-cast skill**:
A skill the run casts for the player when its trigger holds and MP allows: attacks at targets in range, buffs when
inactive, heals below an HP threshold, Slow when enough monsters are near.

**Manual skill**:
A skill the player triggers with its own key, such as Teleport.

**Passive skill**:
A skill that is always in effect once learned and is never cast, such as MP Eater.

## Cards and rarity

**Rank**:
A skill's survivor level, equal to its canonical v83 skill level; each rank card adds one.
_Avoid_: skill level (in card text), tier

**Behaviour card**:
A card that changes how one owned skill behaves (more projectiles, pierce, targets, area, a shorter cooldown)
without adding a rank.
_Avoid_: stacking card, mod card, upgrade card (that means any card)

**Advancement draw**:
The extra card draw a job advancement opens before that level's normal draw: every new attack skill of the new job,
topped up with its other new skills.
_Avoid_: guaranteed card, job reward

**Fortune**:
The character's survivor stat that makes rarer cards more likely; unrelated to the v83 LUK stat.
_Avoid_: Luck, LUK

**Rarity**:
A card's Potential tier (Normal, Rare, Epic, Unique, Legendary), which sets how much the card gives.
_Avoid_: Quality, grade, card tier (tier is the run's difficulty step)

## Monsters

**Status effect**:
A timed condition a skill puts on a monster: slowed, poisoned or frozen.
_Avoid_: debuff, ailment

**Element attribute**:
A monster's canonical weakness (x1.5), resistance (x0.5) or immunity (x0) to an attack element: fire, ice,
lightning, poison or holy.

**Undead**:
A monster flagged undead in Mob.wz: Heal damages it and Holy Arrow is strong against it.

## Mesos and equipment

**Mesos**:
The run's money: dropped by monsters, spent and earned only in the Free Market shops, and lost when the run ends.
_Avoid_: Gold, coins, money; not to be confused with NX, which outlives runs

**Equipment**:
The v83 items a character can wear, each with its real stats and its level, job and stat requirements. Equipment
comes only from monster drops, never from shops.
_Avoid_: Gear (in player-visible text), armour, loot

**Equip slot**:
One place equipment is worn: hat, top, bottom, overall, shoes, gloves or weapon. An overall fills the top and
bottom slots together.
_Avoid_: Equipment slot, gear slot

**Worn equipment**:
The equipment currently in a character's equip slots; only worn equipment adds stats.
_Avoid_: Loadout (that is the character's skills and cards), outfit

**Inventory**:
The equipment and scrolls a character owns but is not wearing; it is carried between rounds with the character.
_Avoid_: Bag, stash

**Shop**:
An NPC's stock of scrolls in the Free Market, opened by talking to the NPC. Shops never sell equipment or potions.
_Avoid_: Store, vendor

**Scroll**:
A v83 item that, used on a piece of equipment, tries to add stats with its success rate (10%, 60%, 100% ...) and
uses up one of that equipment's upgrade slots.
_Avoid_: Enchant, upgrade (in player-visible text), rune

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
