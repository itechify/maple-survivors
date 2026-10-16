# Cleric Heal evidence (#57, 2026-10-15)

Only facts and formula descriptions were used. No reference implementation was copied. The original GMS v83
client remains packed (see `rea-client.md`); this investigation did not unpack it. **The exact v83 self-recovery
amount is not established by the available evidence.** The implementation uses the historical fit below, with
that limitation exposed here and in the skill data. The ticket's requirement for verified v83 recovery remains open.

## Canonical data (tier A)

The existing, shared original-v83 cache contains `Skill.wz/230.img/skill/2301002`. There are 30 level nodes.
The `hp` field is 10 at level 1 and 300 at level 30; `mpCon` is 12 and 24 respectively. The box is
`(-250,-150)..(250,150)` at level 1 and `(-300,-200)..(300,200)` at level 30, relative to the feet.
`mobCount` is 6. `action/0` is `alert2`; `effect`, `hit/0`, icons and `Sound.wz/Skill.img/2301002/Use`
are present. Heal has no `mad`, `mastery`, `elemAttr`, or canonical cooldown.

Holy Arrow is `2301005`, has 30 levels, and `elemAttr=h`. Its level 1 / 30 values are
`mad=22/80`, `mastery=1/10`, `mpCon=12/24`; `action/0=shoot1`. Its `ball`, `effect`, `hit/0`, icons
and `Sound.wz/Skill.img/2301005/Use` are present. Runtime values continue to come from the cache.

## Undead attack (tier B)

The local pre-Big-Bang compilation in
`C:/Users/itech/Coding/maple-survivors-refs/research/v83-mechanics/web/exoot.txt:124-141` records the
special Heal damage bounds and target multiplier. Its underlying primary RE discussion is
[Southperry, posts 685–692, May 2010](https://www.southperry.net/showthread.php?page=35&tid=1033).
ZakumSlaYers identifies the disassembly as Brazil MapleStory v8 (roughly GMS v55–58), and Russt checks the
algebra against the observed formula. This is pre-BB client RE, **not direct v83 binary verification**.

With `I=INT`, `L=LUK`, `M=INT + equipment magic attack`, `P=canonical hp / 100`, and `N` targets including
the caster, use `T=1.5 + 5/N`. Before the existing defense/element processing, the lower bound is
`(0.3*I + L)*M/1000*P*T`, the upper bound `(1.2*I + L)*M/1000*P*T`. This is distinct from the ordinary
`mad`-based spell formula. For I=100, L=4, M=123, P=.7 and N=2 the bounds are 11.7096 and 42.7056.

The contemporary [Cleric guide by Ayumilove](https://ayumilovemaple.wordpress.com/maplestory-characters/maplestory-magician-page/)
describes the Cleric's holy element. Heal's node lacks an element letter; using `h` for its attack is tier B.
The shared `hit_mob` path retains the project's existing defense, critical, element and hit-listener behavior;
this ticket does not replace the global defense formula with the RE post's subtractive MDEF rule.

The ticket explicitly requires every undead inside the box, so the implementation does not cap at canonical
`mobCount=6` (tier C survivor override). `N` is eligible undead plus the caster, including the full-HP caster.
No current stage adds undead. The synthetic tests exercise this path, including more than six targets.

## Self recovery: evidence gap

The same local compilation labels Nekonecat's recovery expression **old** and leaves its replacement unknown.
It is an empirical fit, not confirmed v83 RE. With coefficient
`a(L)=1.132682429e-7*L² + 3.368846366e-6*L + 1.97124794e-3`, the provisional single-target upper bound is
`a(L)*M*I*(canonical hp/10)` and the lower bound is 80% of it. The canonical field supplies the level scaling;
no survivor rank or hardcoded level table supplies power. Coefficients are weak tier B; choosing this fit and
using a single-target multiplier of 1 are **tier C pending verification**. Self recovery stays single-target
even when the same cast attacks undead. A seeded uniform roll is truncated to integer HP, then capped through
`restore_player` (tier C rounding/RNG convention).

This interpretation approximately fits the original investigator's observations at INT=136, LUK=7, M=157:
the fit gives about 34–42 HP at level 1, while the author observed 34–41. Those observations are in
[Russt's original Heal investigation, post 1](https://www.southperry.net/showthread.php?tid=1034).
They support a stat-based amount, not a percentage of maximum HP, but do not validate the fit exactly.
[Stereo's later measurements, posts 456–459](https://www.southperry.net/showthread.php?page=23&tid=1033)
explicitly question the recovery formula. Applying the attack multiplier 6.5 to this single-target fit would
contradict those observed magnitudes; it is not applied.

Cosmic `server/StatEffect.java:1402-1420` instead restores a fraction of max HP divided among affected players.
That contradicts the requested INT/LUK/magic-based behavior and is an emulator assumption, so it is not used.
The Harepacker simulator's `SkillManager.ApplyHeal` likewise does not supply verified v83 recovery arithmetic.
No copyleft source code was ported.

## Survivor constants (tier C; no tuning)

Heal admits strictly below 50% max HP or with at least one boxed undead. Its `heal` block sets a 2 s recast delay.
Holy Arrow copies existing Fire Arrow's 1 s cooldown, 480 px range, 520 px/s flight, 12 px radius, one projectile,
zero pierce and 0.8 s stance. Heal also holds its stance for 0.8 s. Holy Arrow cards add one projectile up to
three steps, one pierce up to two steps, or multiply cooldown by .88 up to three steps. Learn/rank weights are
4/3 and behavior weights 2, matching first-job attacks. Heal gets only learn/rank cards. All require job 230.
Existing projectile/instant bot scoring applies to both skills; no scoring override is added.
