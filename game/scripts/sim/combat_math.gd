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
## tier B: pre-Big-Bang SouthPerry/HS.net accuracy coefficients (DEX, LUK); nearest job ancestor wins.
const ACCURACY_FACTORS := {
	0: Vector2(0.8, 0.5), 100: Vector2(0.8, 0.5), 200: Vector2(0.8, 0.5),
	300: Vector2(0.6, 0.3), 400: Vector2(0.6, 0.3), 500: Vector2(0.6, 0.3), 510: Vector2(0.9, 0.3),
}


## Damage kinds of a hit line, as the byte a pooled array stores (DAMAGE_TYPE_NAMES is the string a hit dictionary carries).
const DAMAGE_FIXED := 0
const DAMAGE_MAGIC := 1
const DAMAGE_PHYSICAL := 2
const DAMAGE_TYPE_NAMES := ["fixed", "magic", "physical"]


## The damage type of a hit line: the explicit `damage_type` when set, else the legacy `magic` flag picks magic or fixed
## (the one place that default lives; callers with a spec dictionary pass its two keys).
static func damage_type_of(damage_type: String, is_magic: bool) -> String:
	return damage_type if damage_type != "" else "magic" if is_magic else "fixed"


## The DAMAGE_* byte of a damage type name (an unknown name, e.g. "none", counts as fixed).
static func damage_type_code(damage_type: String) -> int:
	return maxi(DAMAGE_FIXED, DAMAGE_TYPE_NAMES.find(damage_type))


## Mastery fraction for a canonical `mastery` field value: (10 + 5 x m) / 100 (Energy Bolt L1 m=1 -> 0.15).
static func mastery_fraction(mastery_field: int) -> float:
	return (10.0 + 5.0 * mastery_field) / 100.0


## Job-base accuracy from a JobTree lineage (nearest first), before equipment and skills.
static func base_accuracy(dex_stat: float, luk_stat: float, lineage: PackedInt32Array) -> float:
	var factors: Vector2 = ACCURACY_FACTORS[0]
	for job: int in lineage:
		if ACCURACY_FACTORS.has(job):
			factors = ACCURACY_FACTORS[job]
			break
	return dex_stat * factors.x + luk_stat * factors.y


## Vector2(min, max) magic damage before defence. `mastery` is the fraction (0.15 = 15%).
static func magic_damage_range(int_stat: float, matk: float, spell_attack: float, mastery: float) -> Vector2:
	var mag := int_stat + matk
	var sq := mag * mag / 1000.0
	var hi := ((sq + mag) / 30.0 + int_stat / 200.0) * spell_attack
	var lo := ((sq + mag * mastery * 0.9) / 30.0 + int_stat / 200.0) * spell_attack
	return Vector2(minf(lo, hi), hi)


## Single-target Heal recovery bounds; historical tier B fit, NOT verified v83 RE (research/cleric-heal.md).
static func heal_recovery_range(int_stat: float, luk: float, matk: float, recovery_pct: float) -> Vector2:
	# tier B (weak): Nekonecat's pre-BB single-target fit; hp is 10 per level in canonical Heal.
	# tier C: provisional choice of this unverified fit with single-target multiplier 1 (cleric-heal.md).
	var coefficient := 1.132682429e-7 * luk * luk + 3.368846366e-6 * luk + 1.97124794e-3
	var hi := coefficient * (int_stat + matk) * int_stat * recovery_pct / 10.0
	return Vector2(hi * 0.8, hi)


## Heal's special undead damage bounds, before the shared defense/element path (tier B: pre-BB client RE).
static func heal_damage_range(int_stat: float, luk: float, matk: float, recovery_pct: float, targets: int) -> Vector2:
	# tier B: Russt / ZakumSlaYers, Southperry #1033 posts 685-692; targets includes the caster.
	var factor := (int_stat + matk) / 1000.0 * recovery_pct / 100.0 * (1.5 + 5.0 / maxi(1, targets))
	return Vector2((int_stat * 0.3 + luk) * factor, (int_stat * 1.2 + luk) * factor)


## Pre-defence weapon bounds (tier B: SouthPerry/HS.net). Formula overrides are survivor skill data.
static func physical_damage_range(str_stat: float, dex_stat: float, luk_stat: float, watk: float,
		weapon_id: int, attack_kind: String, job_id: int = 0, mastery: float = 0.10,
		formula: Dictionary = {}) -> Vector2:
	var row := WeaponInfo.physical_formula(weapon_id, job_id)
	var mult := float(row[1] if attack_kind == "stab" else row[0])
	var values := {"str": str_stat, "dex": dex_stat, "luk": luk_stat, "str+dex": str_stat + dex_stat, "": 0.0}
	var primary := float(values.get(String(formula.get("primary", row[2])), 0.0))
	var secondary := float(values.get(String(formula.get("secondary", row[3])), 0.0))
	var max_mult := float(formula.get("max_mult", mult))
	var min_mult := float(formula.get("min_mult", max_mult))
	# tier B: Power Knock-Back uses fixed 10% mastery and divides by 150 (ticket #202, pre-BB formula).
	# Optional overrides keep the ordinary /100 and live mastery for every existing physical attack.
	var minimum_mastery := 1.0 if bool(formula.get("ignore_mastery", false)) else 0.9 * float(formula.get("mastery", mastery))
	var divisor := float(formula.get("divisor", 100.0))
	var hi := (max_mult * primary + secondary) * watk / divisor
	var lo := (min_mult * primary * minimum_mastery + secondary) * watk / divisor
	return Vector2(minf(lo, hi), hi)


## Physical bounds after live PDD (tier B: AGF/Stereo), each floored at 1 before rolling. No level-gap term: the
## monster's level never changes damage (ADR 0006).
static func physical_defense(bounds: Vector2, pdd: float) -> Vector2:
	var hi := maxf(1.0, bounds.y - 0.5 * pdd)
	var lo := maxf(1.0, bounds.x - 0.6 * pdd)
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


## True with probability `chance` (0..1). Never consumes a roll when chance <= 0.
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
