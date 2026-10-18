# Physical combat: weapon-gated skills, endless auto-upgrading ammo, and no MISS

The Warrior, Bowman, Thief and Pirate lines are added up to second job. They are built on one shared physical-combat
foundation, so the four class specs can run in parallel. Three rules in that foundation go beyond "behave like
v83". The owner decided them in the 2026-10-17 grilling:

- **Skills follow the weapon you hold.** A skill with a Skill.wz `weapon` requirement (tier A) only casts while a
  matching weapon is held. Survivor overrides cover the skills v83 leaves untagged (tier C). Level-up cards are offered
  for the weapon held when the draw rolls. A weapon swapped in the Equip window turns the mismatched skills off.
  - Thief and Pirate pick a **weapon path** at first job: Thief Claw/Dagger, Pirate Knuckle/Gun. The path hands the
    character that weapon.
  - Second job grants the branch weapon only when the held one can't be used by the branch.
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
  behaviour cards for parity with Magician first job's two attacks.
- **Free swapping:** a character carrying a spare weapon can learn both paths' skills by swapping between draws, but
  only the held weapon's skills cast. The bot never swaps by hand.
- **Masteries:** they apply only while their family is held. Drops stay in the wielded family, so they never switch a
  mastery off.
- **Crit for Magicians:** Magicians now roll crits from their accuracy (Bless's ACC finally does something), so their
  seeded records change once.
- **Balance:** the accuracy coefficient and the ammo levels are survivor data, owned by the balance pass.
