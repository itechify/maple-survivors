class_name BurnStatus
extends RefCounted
## The pure arithmetic of the burn status (spec #332 B5, GAME_DESIGN 7.43): how big a cast makes its burning pulse and how
## much of a pulse a monster can take. MobSwarm owns the timers and the pulse clock (beside poison's), Loadout.stats calls
## pulse() once per cast, and nothing here touches a node, the clock or an RNG stream.

## tier C: a skill's `x` is the burn's share of the cast's base damage per second, as a percent (Inferno 21 -> 50; the
## field is undocumented in String.wz). The base damage is the cast's resolved bounds before skill%, so it scales with
## DEX/STR/W.Att and every `damage` modifier and ignores monster defence, as poison does.


## Whole damage per pulse: mean(damage_min, damage_max) x share_percent / 100 x burn_mult, rounded; never negative.
static func pulse(damage_min: float, damage_max: float, share_percent: float, burn_mult: float) -> int:
	return maxi(0, roundi((damage_min + damage_max) * 0.5 * share_percent / 100.0 * maxf(0.0, burn_mult)))


## The damage a pulse of `pulse_damage` really deals to a monster with `hp`: never below 1 HP left.
static func tick_damage(pulse_damage: int, hp: int) -> int:
	# tier C: like v83's server poison, a burn leaves at least 1 HP and never stuns or pushes.
	return mini(pulse_damage, maxi(0, hp - 1))
