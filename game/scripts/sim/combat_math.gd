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
## - Touch damage to the player: max(1, round(PAD x 0.55 x rand[0.85, 1] x stage mult - PDD x 0.6)) (tier C).
## - Magic Guard: floor(damage x x%) moves to MP while MP lasts, the rest (and any overflow) hits HP
##   (the split Cosmic applies, docs/research/cosmic-data.md section 5).

## tier C: the k of MDD / (MDD + k).
const MAGIC_DEFENSE_K := 150.0
## tier C: touch damage constants (docs/GAME_DESIGN.md 6.2).
const TOUCH_SCALE := 0.55
const TOUCH_ROLL_MIN := 0.85
const TOUCH_ROLL_MAX := 1.0
const TOUCH_PDD_FACTOR := 0.6


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


## Touch damage for a mob with `pad` against a player with `player_pdd`, given a roll in [0, 1) that is mapped onto
## [roll_min, roll_max]. Always >= 1.
static func touch_damage(pad: float, roll: float, stage_mult: float, player_pdd: float, scale: float = TOUCH_SCALE,
		roll_min: float = TOUCH_ROLL_MIN, roll_max: float = TOUCH_ROLL_MAX,
		pdd_factor: float = TOUCH_PDD_FACTOR) -> int:
	var r := lerpf(roll_min, roll_max, clampf(roll, 0.0, 1.0))
	return maxi(1, roundi(pad * scale * r * stage_mult - player_pdd * pdd_factor))


## Magic Guard split of `damage` with x% to MP while `mp` lasts: Vector2i(hp_loss, mp_loss).
static func magic_guard_split(damage: int, x_pct: float, mp: int) -> Vector2i:
	if x_pct <= 0.0 or damage <= 0:
		return Vector2i(maxi(damage, 0), 0)
	var to_mp := floori(damage * x_pct / 100.0)
	var mp_loss := mini(to_mp, maxi(mp, 0))
	return Vector2i(damage - mp_loss, mp_loss)


## Shared monster-hit calculation. Defense holds pdd/mdd and optional resistance by element; the legacy tuning
## remains intact until the combat overhaul replaces the formula.
static func monster_hit(attack: float, magic: bool, element: String, defense: Dictionary,
		rng: RandomNumberGenerator, multiplier: float = 1.0, tuning: Dictionary = {}) -> int:
	var def := float(defense.get("mdd" if magic else "pdd", 0.0))
	var damage := touch_damage(attack, rng.randf(), multiplier, def,
		float(tuning.get("scale", TOUCH_SCALE)), float(tuning.get("roll_min", TOUCH_ROLL_MIN)),
		float(tuning.get("roll_max", TOUCH_ROLL_MAX)), float(tuning.get("pdd_factor", TOUCH_PDD_FACTOR)))
	var resistance := float(defense.get("resistance", {}).get(element, 0.0)) if element != "" else 0.0
	return maxi(1, roundi(damage * (1.0 - resistance / 100.0)))
