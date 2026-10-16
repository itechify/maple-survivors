# Dark Cave boss attacks (#73)

Checked 2026-10-16 against the owner's original v83 install using `wzimport dump` (tier A).
No reference implementation code was copied.

| Mob / attack | Type | attackAfter / effectAfter (ms) | Damage source | Range |
|---|---|---|---|---|
| 6300005 / attack1 | 0 | 1050 / 0 | local PADamage 300, jumpAttack 1 | lt(-250,-150), rb(250,0) |
| 8220009 / attack1 | 0 | 1520 / absent | local PADamage 500, jumpAttack 1 | lt(-303,-68), rb(255,6) |
| 8220009 / attack2 | 0 | 2000 / absent | magic 1, mob MADamage 520, F | lt(-136,-139), rb(146,6) |
| 8220009 / attack3 | 0 | 2100 / absent | magic 1, mob MADamage 520 | lt(-1122,-175), rb(-23,-45) |
| 8130100 / attack1 | 1 | 1300 / 700 | magic 1, mob MADamage 605, F | sp(-28,-69), r250 |
| 8130100 / attack2 | 2 | 400 / 100 | magic 1, mob MADamage 605, F | sp(-28,-69), r250; bulletSpeed absent |
| 8130100 / attack3 | 0 | 400 / 500 | magic 1, mob MADamage 605 | lt(-330,-160), rb(105,0) |

All three have no `info/skill`. Jr. Balrog's `info/elemAttr` is `S1H3`; canonical maxHP is
35000 / 110000 / 50000. Snack Bar lacks hpTag colours and a MobGage icon; survivor presentation supplies
colours 1/5 and borrows Zombie Mushmom's icon. Its actual sprite and String.wz name remain Snack Bar's.

## Type 1: adopted reading, tier C

The later-client reference [HaCreator MobAttackSystem](https://github.com/lastbattle/Harepacker-resurrected/blob/master/HaCreator/MapSimulator/Combat/MobAttackSystem.cs)
describes a locked-target direct attack separately from area attacks and travelling balls. Its
`CanQueueLockedTargetAttack` admits by range from the attack's source, `UsesLockedTargetResolution` selects
type 1, and `TryApplyLockedTargetImpact` strikes the admitted player without another area/range test.
Those descriptions are useful evidence, **not verified v83 RE**. The v83-targeting behavior could not be pinned
down sufficiently for tier B. HeavenClient/NoLifeStory references did not establish this path.

Our explicit rule: mirror `range/sp` with the captured facing; admit the one character when its body centre is
within `range/r` of that point; lock the character, not a world position; at `attackAfter`, call normal magic
damage against the character's current state/position, even if it has moved or jumped. Death or pursuit fade
cancels an unfinished attack. Normal avoid, defence, invincibility and Magic Guard still apply. Play `effect`
at the caster at `effectAfter` and `hit` at the character at impact. There is no projectile, travel delay,
extra collision rectangle, terrain obstruction or artificial grounded gate for type 1. These geometry/target
choices are tier C and covered through seeded fixed-tick RunWorld tests, including escape, jump and death.

For type 2, retain the existing positive bulletSpeed conversion. The absent/nonpositive-speed fallback is
320 px/s (tier C, `balance.mob_projectiles.default_speed`), inspired by the same reference's fallback, rather
than leaving an immortal stationary ball. It does not claim a canonical v83 default. Original WZ timing,
origins, art and fields are unmodified. `effectAfter` remains independent even when it follows `attackAfter`.

This uncertainty is flagged here and in GAME_DESIGN section 11; the implementer brief forbids issue comments,
so the lead must carry the tier-C type-1 caveat into the #73 acceptance report.
