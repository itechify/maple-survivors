# Physical combat: weapon-gated skills, endless auto-upgrading ammo, and no MISS

> **Partly superseded by ADR 0006** (2026-10-27): skills no longer follow the held weapon, and weapon paths and
> carried attacks go away. No MISS and endless ammo still hold.

The Warrior, Bowman, Thief and Pirate lines are added up to second job. They are built on one shared physical-combat
foundation, so the four class specs can run in parallel. Three rules in that foundation go beyond "behave like
v83". The owner decided them in the 2026-10-17 grilling:

- **Skills follow the weapon you hold.** A skill with a Skill.wz `weapon` requirement (tier A) only casts while a
  matching weapon is held. Survivor overrides cover the skills v83 leaves untagged (tier C). Level-up cards are offered
  for the weapon held when the draw rolls. A weapon swapped in the Equip window turns the mismatched skills off.
  - *Amended 2026-10-18 (#226):* every multi-family advancement asks for a **weapon path**: Warrior
    Sword/Spear/Blunt Weapon, Bowman Bow/Crossbow, Thief Claw/Dagger, Pirate Knuckle/Gun; at second job,
    Fighter Sword/Axe, Page Sword/Blunt Weapon and Spearman Spear/Polearm. Only the chosen family's weapon is
    granted and worn, without requirements. Displaced equipment goes to the Equip tab, spilling at the feet when full.
    Single-family branches keep their one worn grant; Magicians have no weapon question.
  - This replaces the other first-job path's spare weapon and the #165 rule granting one weapon per branch family.
    That rule made each family's Mastery, Booster and Final Attack reachable; choosing the family now provides that
    access directly. The recorded weapon path updates on a multi-family second-job choice; held-family skill/card
    gates remain live when the character swaps weapons. Page order at second job puts the held family first.
  - Weapon drops come only from the wielded weapon family.
- **Ammo is endless and upgrades itself.** Stars, arrows and bullets are never consumed, never an item stack and never
  a card.
  - Each class starts with its real basic ammo.
  - The specialist branch (Assassin, Hunter, Crossbowman, Gunslinger) moves up the real v83 ammo tiers at fixed levels.
  - The projectile sprite changes with each tier.
- **The player's attacks never MISS.** Accuracy becomes critical chance (ACC times a survivor coefficient, tier C), for
  every class, Magicians included.

## Considered options

- **Ammo as a consumable** (v83): rejected. Running dry in a horde isn't fun, and the Free Market only sells scrolls
  (ADR 0002).
- **Ammo upgrades as level-up cards:** rejected. They would be a new job-neutral card exception, and arrow tiers (+1, +2,
  +4 W.Att) would be weak cards next to skills.
- **Ignore weapon requirements** (every class skill with any class weapon): rejected as un-v83. Lucky Seven would throw
  stars from a dagger.
- **Canonical v83 MISS** (tier B formula, mob level gap times avoid): rejected.
  - Against ordinary mobs at the player's level it is about 100% hits, so accuracy cards would be wasted.
  - Against the scheduled bosses, which arrive 10–50 levels above the player, it falls to near 0%. Blue Mushmom would be
    unhittable for every physical class.
- **MISS against ordinary mobs only:** rejected for the same wasted-card reason.
- **Accuracy offsets a new level-gap damage penalty:** rejected. It would weaken every class against bosses and reopen
  boss balance.

## Consequences

- **Thief paths:** a first-job Thief has one attack per weapon path (Lucky Seven or Double Stab). Its class spec adds
  behaviour cards for parity with Magician first job's two attacks. *Settled 2026-10-18 (#167):* parity means the
  Magician's behaviour budget, 13 steps across 5 lines per path, not its total card count (that would put about 33
  near-duplicate behaviour steps on one skill).
- **Carried attacks** (*amended 2026-10-18, #167*; GLOSSARY): a physical class's first-job attack cards stay on offer
  after the second job, though never in the advancement draw; the weapon gate still decides which of them a character
  sees. It began as a Warrior-only exception (#165: Warrior branches have no attack skill of their own), the Pirate
  took the same shape (#168), and the Thief made it the rule: an Assassin's only second-job attack is Drain, and v83
  Assassins kept attacking with Lucky Seven until third job. Magicians keep the old rule (earlier-job cards stop at
  each advancement), because every Magician branch has attack skills of its own.
- **Free swapping:** a character carrying a spare weapon can learn both paths' skills by swapping between draws, but
  only the held weapon's skills cast. The bot never swaps by hand.
- **Masteries:** they apply only while their family is held. Drops stay in the wielded family, so they never switch a
  mastery off.
- **Crit for Magicians:** Magicians now roll crits from their accuracy (Bless's ACC finally does something), so their
  seeded records change once.
- **Balance:** the accuracy coefficient and the ammo levels are survivor data, owned by the balance pass.
