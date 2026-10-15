class_name CombatMath
extends RefCounted
## Damage formulas (docs/GAME_DESIGN.md section 6). Static and pure: random rolls come from the caller's seeded
## RandomNumberGenerator, so every result is reproducible.
##
## - Magic (tier C, the community formula; the v83 client's own is in packed code):
##   MAG = INT + magic attack; MAX = ((MAG^2/1000 + MAG)/30 + INT/200) x spellAttack;
##   MIN = ((MAG^2/1000 + MAG x mastery x 0.9)/30 + INT/200) x spellAttack; rolled uniformly. `spell_attack` is the
##   skill level's canonical `mad`, `mastery` the fraction (10 + 5 x the canonical `mastery` field) / 100.
## - Fixed damage (Three Snails): the canonical `fixdamage` x survivor multipliers, no defence.
## - Mob defence against magic: x (1 - MDD / (MDD + 150)) (tier C).
## - Monster damage to the player: roll 85-100% of attack, subtract floor(0.75 x defense), apply elemental
##   resistance and source multipliers, round once and enforce at least 1. Owner-selected formula (tier C).
## - Magic Guard: floor(damage x x%) moves to MP while MP lasts, the rest (and any overflow) hits HP
##   (the split Cosmic applies, docs/research/cosmic-data.md section 5).

## tier C: the k of MDD / (MDD + k).
const MAGIC_DEFENSE_K := 150.0
## tier C: owner-selected monster hit formula (docs/GAME_DESIGN.md 6.2).
const HIT_ROLL_MIN := 0.85
const HIT_ROLL_MAX := 1.0
const HIT_DEFENSE_FACTOR := 0.75
## tier B (weakly sourced): pre-Big-Bang avoid-versus-monster-accuracy percentage from a single private-server wiki
## page (owner-provided); no second RE source corroborates it.
const AVOID_PERCENT_FACTOR := 21.6


## Mastery fraction for a canonical `mastery` field value: (10 + 5 x m) / 100 (Energy Bolt L1 m=1 -> 0.15).
static func mastery_fraction(mastery_field: int) -> float:
	return (10.0 + 5.0 * mastery_field) / 100.0


## Vector2(min, max) magic damage before defence. `mastery` is the fraction (0.15 = 15%).
static func magic_damage_range(int_stat: float, matk: float, spell_attack: float, mastery: float) -> Vector2:
	var mag := int_stat + matk
	var sq := mag * mag / 1000.0
	var hi := ((sq + mag) / 30.0 + int_stat / 200.0) * spell_attack
	var lo := ((sq + mag * mastery * 0.9) / 30.0 + int_stat / 200.0) * spell_attack
	return Vector2(minf(lo, hi), hi)


## Physical swing bounds after level difference and PDD, minimum 1 (tier B: pre-Big-Bang formula compilation).
static func basic_damage_range(str_stat: int, dex_stat: int, watk: float, weapon_id: int, action: String,
		player_level: int, mob_level: int, pdd: float) -> Vector2:
	var k := 4.0 if weapon_id / 10000 == 130 else 3.2 if action.begins_with("stab") else 4.4
	var hi := (str_stat * k + dex_stat) * watk / 100.0
	var lo := (str_stat * k * 0.9 * 0.1 + dex_stat) * watk / 100.0
	var level_factor := 1.0 - 0.01 * maxi(0, mob_level - player_level)
	hi = maxf(1.0, hi * level_factor - 0.5 * pdd)
	lo = maxf(1.0, lo * level_factor - 0.6 * pdd)
	return Vector2(minf(lo, hi), hi)


## One uniform roll in [range.x, range.y].
static func roll_range(r: Vector2, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(r.x, r.y) if r.y > r.x else r.x


## Fixed damage: fixdamage x mult, rounded, at least 1.
static func fixed_damage(fixdamage: float, mult: float = 1.0) -> int:
	return maxi(1, roundi(fixdamage * mult))


## Magic damage after the mob's magic defence: dmg x (1 - mdd / (mdd + k)).
static func apply_defense(dmg: float, mdd: float, k: float = MAGIC_DEFENSE_K) -> float:
	if mdd <= 0.0:
		return dmg
	return dmg * (1.0 - mdd / (mdd + k))


## True with probability `chance` (0..1). Never consumes a roll when chance <= 0 (Beginner/Magician cannot crit).
static func roll_crit(chance: float, rng: RandomNumberGenerator) -> bool:
	if chance <= 0.0:
		return false
	return rng.randf() < chance


## Monster damage for a normalized roll: mitigation, elemental resistance and source scaling before rounding.
static func monster_damage(attack: float, roll: float, defense: float, resistance: float = 0.0,
		multiplier: float = 1.0) -> int:
	var r := lerpf(HIT_ROLL_MIN, HIT_ROLL_MAX, clampf(roll, 0.0, 1.0))
	var mitigated := attack * r - floorf(HIT_DEFENSE_FACTOR * maxf(defense, 0.0))
	var elemental := mitigated * (1.0 - clampf(resistance, 0.0, 100.0) / 100.0)
	return maxi(1, roundi(elemental * multiplier))


## Magic Guard split of `damage` with x% to MP while `mp` lasts: Vector2i(hp_loss, mp_loss).
static func magic_guard_split(damage: int, x_pct: float, mp: int) -> Vector2i:
	if x_pct <= 0.0 or damage <= 0:
		return Vector2i(maxi(damage, 0), 0)
	var to_mp := floori(damage * x_pct / 100.0)
	var mp_loss := mini(to_mp, maxi(mp, 0))
	return Vector2i(damage - mp_loss, mp_loss)


## Shared monster-hit calculation from attack, physical/magic defense and optional per-element resistance.
static func monster_hit(attack: float, magic: bool, element: String, defense: Dictionary,
		rng: RandomNumberGenerator, multiplier: float = 1.0) -> int:
	var def := float(defense.get("mdd" if magic else "pdd", 0.0))
	var resistance := float(defense.get("resistance", {}).get(element, 0.0)) if element != "" else 0.0
	return monster_damage(attack, rng.randf(), def, resistance, multiplier)


## Probability of a monster missing the player; zero when the source has no usable accuracy.
static func miss_chance(avoid: float, accuracy: float) -> float:
	if accuracy <= 0.0:
		return 0.0
	return clampf(AVOID_PERCENT_FACTOR * maxf(avoid, 0.0) / accuracy / 100.0, 0.0, 1.0)


## One seeded avoid roll; impossible misses consume no random number.
static func roll_miss(avoid: float, accuracy: float, rng: RandomNumberGenerator) -> bool:
	var chance := miss_chance(avoid, accuracy)
	return chance > 0.0 and rng.randf() < chance
