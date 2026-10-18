class_name Loadout
extends RefCounted
## The skills a run owns, their survivor ranks and the modifiers upgrade cards stacked on them, plus the player-wide
## modifiers of general cards (docs/ARCHITECTURE.md 4.4, docs/GAME_DESIGN.md sections 7, 8). Skill ids are the survivor
## keys of skills.json.
##
## Modifiers are kept as (add, mul) per stat: the resolved value is (base + add) x mul, where `add` sums every "add"
## effect and `mul` multiplies every "mul" effect (so Faster Snails x0.88 compounds per rank). stats(key) resolves a
## skill completely: its canonical level from the rank, the canonical numbers of that level from Skill.wz, the survivor
## base numbers with the modifiers, the damage range for the current INT / magic attack, and the visual paths.
## `version` increments on every change so callers can cache stats().

## Passive stat of Improved MaxMP Increase: a fraction of the computed Max MP (tier C survivor reinterpretation).
const MAX_MP_PERCENT := "max_mp_percent"
## Passive stats of the shared physical passives (docs/GAME_DESIGN.md 7.6). mastery: the canonical Mastery skill value N
## (the mastery fraction is (10 + 5N)%); acc: skill ACC; crit_chance: percent chance (Skill.wz `prop`); crit_damage: the
## critical hit's total percent (Skill.wz `damage`; the bonus is that minus 100); max_hp_per_level: Max HP gained at each
## level-up after learning.
const MASTERY := "mastery"
const ACC := "acc"
const CRIT_CHANCE := "crit_chance"
const CRIT_DAMAGE := "crit_damage"
const MAX_HP_PER_LEVEL := "max_hp_per_level"
## tier C (#199): additive pixels of reach for ranged basic attacks and weapon-gated ranged attack skills.
const RANGE := "range"
## tier B: untrained physical mastery is 10% (SouthPerry/HS.net).
const BASE_MASTERY := 0.10

var book: SkillBook
## Owned skill key -> survivor rank (>= 1).
var ranks := {}
## Owned skill keys in the order they were learned.
var order: Array = []
## skill key -> {stat: Vector2(add, mul)}.
var skill_mods := {}
## stat -> Vector2(add, mul) for player-wide stats (max_hp, max_mp, speed, magnet, hp_regen, mp_regen, pdd, damage,
## crit).
var player_mods := {}
## Upgrade card id -> consumed rank/modifier steps (one per learn or potion card), respecting its maximum.
var card_ranks := {}
## Inputs of the damage formula and the CharLevel visuals, kept current by RunWorld.
var int_stat := 4.0
var matk := 0.0
var char_level := 1
## Physical caster inputs; RunWorld._refresh_caster assembles these. Setters invalidate cached stats on change.
var str_stat := 4.0:
	set(value):
		if value != str_stat:
			str_stat = value
			version += 1
var dex_stat := 4.0:
	set(value):
		if value != dex_stat:
			dex_stat = value
			version += 1
var luk_stat := 4.0:
	set(value):
		if value != luk_stat:
			luk_stat = value
			version += 1
var watk := 0.0:
	set(value):
		if value != watk:
			watk = value
			version += 1
var acc := 0.0:
	set(value):
		if value != acc:
			acc = value
			version += 1
var weapon_id := 0:
	set(value):
		if value != weapon_id:
			weapon_id = value
			version += 1
var weapon_family := "":
	set(value):
		if value != weapon_family:
			weapon_family = value
			version += 1
var job_id := 0:
	set(value):
		if value != job_id:
			job_id = value
			version += 1
var mastery := BASE_MASTERY:
	set(value):
		if value != mastery:
			mastery = value
			version += 1
var crit_bonus := 0.0:
	set(value):
		if value != crit_bonus:
			crit_bonus = value
			version += 1
## Passive bonus in skill-percentage points (100 adds 1.0 to the skill multiplier on a critical hit).
var crit_damage_bonus := 0.0:
	set(value):
		if value != crit_damage_bonus:
			crit_damage_bonus = value
			version += 1
## Attack speed (spec #151, #160): the held weapon's step (Item.wz attackSpeed; WeaponInfo.NORMAL_SPEED bare-handed) and
## the Booster steps in effect (positive = faster, only while the Booster's weapon family is held).
var weapon_speed := WeaponInfo.NORMAL_SPEED:
	set(value):
		if value != weapon_speed:
			weapon_speed = value
			version += 1
var speed_steps := 0:
	set(value):
		if value != speed_steps:
			speed_steps = value
			version += 1
## Survivor balance.crit.per_acc; accuracy converts to crit chance for every damage type.
var crit_per_acc := 0.0:
	set(value):
		if value != crit_per_acc:
			crit_per_acc = value
			version += 1
## Base crit chance and multiplier (balance.json `crit`).
var crit_chance := 0.0
var crit_mult := 1.5
var version := 0


func _init(p_book: SkillBook = null) -> void:
	book = p_book if p_book != null else SkillBook.new()


## An independent copy of every field (the same SkillBook): changing the copy never changes this loadout. Previews
## stack a card's steps on a clone.
func clone() -> Loadout:
	var c := Loadout.new(book)
	c.ranks = ranks.duplicate()
	c.order = order.duplicate()
	c.skill_mods = skill_mods.duplicate(true)
	c.player_mods = player_mods.duplicate(true)
	c.card_ranks = card_ranks.duplicate()
	c.int_stat = int_stat
	c.matk = matk
	c.char_level = char_level
	for field: String in ["str_stat", "dex_stat", "luk_stat", "watk", "acc", "weapon_id", "weapon_family",
			"job_id", "mastery", "crit_bonus", "crit_damage_bonus", "crit_per_acc", "weapon_speed", "speed_steps"]:
		c.set(field, get(field))
	c.crit_chance = crit_chance
	c.crit_mult = crit_mult
	c.version = version
	return c


## Learns `key` at rank 1. False when unknown or already owned.
func add_skill(key: String) -> bool:
	if not book.has(key) or ranks.has(key):
		return false
	ranks[key] = 1
	order.append(key)
	version += 1
	return true


## True when the skill is owned.
func has(key: String) -> bool:
	return ranks.has(key)


## Survivor rank of `key` (0 when not owned).
func rank(key: String) -> int:
	return int(ranks.get(key, 0))


## Sets the rank (clamped to 1..max rank); false when not owned.
func set_rank(key: String, r: int) -> bool:
	if not ranks.has(key):
		return false
	ranks[key] = clampi(r, 1, book.max_rank(key))
	version += 1
	return true


## Canonical skill level of an owned skill (0 when not owned).
func level(key: String) -> int:
	return book.canonical_level(key, rank(key)) if ranks.has(key) else 0


## Owned skills that occupy slot `slot_name` ("active" / "passive").
func slot_count(slot_name: String) -> int:
	var n := 0
	for k: String in order:
		if book.slot(k) == slot_name:
			n += 1
	return n


## Stacks one effect on skill `key` (op "add" or "mul").
func add_skill_mod(key: String, stat: String, op: String, value: float) -> void:
	if not skill_mods.has(key):
		skill_mods[key] = {}
	skill_mods[key][stat] = _stack(skill_mods[key].get(stat, Vector2(0.0, 1.0)), op, value)
	version += 1


## Stacks one effect on a player-wide stat (op "add" or "mul").
func add_player_mod(stat: String, op: String, value: float) -> void:
	player_mods[stat] = _stack(player_mods.get(stat, Vector2(0.0, 1.0)), op, value)
	version += 1


## (base + add) x mul of a player-wide stat.
func player_stat(stat: String, base: float) -> float:
	var m: Vector2 = player_mods.get(stat, Vector2(0.0, 1.0))
	return (base + m.x) * m.y


## (base + add) x mul of a skill stat.
func skill_stat(key: String, stat: String, base: float) -> float:
	var m: Vector2 = skill_mods.get(key, {}).get(stat, Vector2(0.0, 1.0))
	return (base + m.x) * m.y


## Sets the formula inputs (bumps `version` only when something changed).
func set_caster(p_int: float, p_matk: float, p_char_level: int) -> void:
	if p_int == int_stat and p_matk == matk and p_char_level == char_level:
		return
	int_stat = p_int
	matk = p_matk
	char_level = p_char_level
	version += 1


## Fully resolved numbers of skill `key` at its owned rank, or at `at_rank` when > 0 (a preview of another rank with
## the same modifiers; an unowned skill resolves at rank 1):
## skill, skill_id, kind, slot, rank, level, damage_type (fixed/magic/physical/none), attack_kind (swing/stab/shoot/""),
## defense (pdd/mdd/none), damage_pct (physical skill% / 100, otherwise 1), damage_min/max (before mob defence,
## after survivor multipliers; physical bounds are also before skill%), magic (bool), element, attack_count,
## crit, crit_mult, speed_factor (attack speed: the fraction of the data's cooldown and action time left), cooldown, range, cast_rule (empty means legacy), cast_params (the cast block),
## has_box, box (canonical left-facing feet offsets scaled by area), area, mob_count (canonical plus count mods),
## mp_cost (canonical mpCon unless overridden by survivor data), hp_cost (canonical hpCon, 0 for most skills; Slash Blast),
## speed, count, pierce, radius, ball, hit, effect
## (WZ paths), action, action_time, rotate, passive_stat,
## passive_value, icon, displacement ({} or the moving-attack block, _displacement), duration (canonical time), legacy buff_stat/buff_value, buff_effects (stat -> canonical value),
## and for a Hidden buff (docs/GAME_DESIGN.md 7.18): hidden, morph (Morph.wz id from the `morph_field` level number, 0 = none),
## fail_chance (0..1, the `fail_field` level number as a percentage), end_hp_above (HP fraction that ends it early) and
## cooldown_from_cast (the cooldown is exactly buff_cooldown from the cast, however long or short the buff lasts).
func stats(key: String, at_rank: int = 0) -> Dictionary:
	var d := book.def(key)
	var r := clampi(at_rank, 1, book.max_rank(key)) if at_rank > 0 else maxi(1, rank(key))
	var lv := book.canonical_level(key, r)
	var dtype := String(d.get("damage", "none"))
	var action := String(d.get("action", ""))
	if action == "weapon":
		# tier C: the stance (and so the swing/stab multiplier) of the held weapon's first basic-attack action.
		action = WeaponInfo.skill_action(weapon_id)
	var attack_kind := WeaponInfo.attack_kind(action)
	var dmg_mult := skill_stat(key, "damage", 1.0) * player_stat("damage", 1.0)
	var lo := 0.0
	var hi := 0.0
	if dtype == "fixed":
		lo = book.canonical(key, lv, "fixdamage", 0.0) * dmg_mult
		hi = lo
	elif dtype == "magic":
		var mad := book.canonical(key, lv, "mad", 0.0)
		var mastery := CombatMath.mastery_fraction(int(book.canonical(key, lv, "mastery", 0.0)))
		var rng := CombatMath.magic_damage_range(int_stat, matk, mad, mastery)
		lo = rng.x * dmg_mult
		hi = rng.y * dmg_mult
	elif dtype == "physical":
		var bounds := CombatMath.physical_damage_range(str_stat, dex_stat, luk_stat, watk, weapon_id,
			attack_kind, job_id, mastery, d.get("physical_formula", {}))
		lo = bounds.x * dmg_mult
		hi = bounds.y * dmg_mult
	# Attack speed (#160): an attack skill's action time and cooldown shrink with the Booster steps in effect, relative
	# to the held weapon's own speed (1.0 without a Booster, so existing timing is untouched). Buffs, passives and
	# non-damaging casts keep their data.
	var attacks := book.is_active(key) and book.kind(key) != "buff" and dtype != "none"
	var speed_factor := WeaponInfo.speed_factor(weapon_speed, speed_steps) if attacks else 1.0
	var passive: Dictionary = d.get("passive", {})
	var buff: Dictionary = d.get("buff", {})
	var heal: Dictionary = d.get("heal", {})
	var cast: Dictionary = d.get("cast", {})
	var node := book.level_node(key, lv)
	var has_box := node.get("lt") is Dictionary and node.get("rb") is Dictionary
	var area := skill_stat(key, "area", 1.0)
	var box := Rect2()
	if has_box:
		var lt: Array = node.lt.get("$v", [0.0, 0.0])
		var rb: Array = node.rb.get("$v", [0.0, 0.0])
		var start := Vector2(float(lt[0]), float(lt[1])) * area
		box = Rect2(start, Vector2(float(rb[0]), float(rb[1])) * area - start)
		if bool(cast.get("around", false)):
			# tier C: surround attacks retain canonical reach/height on both sides of the player (Pirate kick).
			var extent := maxf(absf(box.position.x), absf(box.end.x))
			box = Rect2(-extent, box.position.y, extent * 2.0, box.size.y)
	return {
		"skill": key,
		"skill_id": book.skill_id(key),
		"kind": book.kind(key),
		"slot": book.slot(key),
		"rank": r,
		"level": lv,
		"cast_rule": String(cast.get("rule", "")),
		"cast_params": cast.duplicate(true),
		"has_box": has_box,
		"area": area,
		"box": box,
		"mob_count": maxi(1, roundi(skill_stat(key, "count", book.canonical(key, lv, "mobCount", 1.0)))),
		"mp_cost": maxi(0, int(d.get("mp_cost_override", book.canonical(key, lv, "mpCon", 0.0)))),
		"hp_cost": maxi(0, int(book.canonical(key, lv, "hpCon", 0.0))),
		"teleport_range": book.canonical(key, lv, "range", 0.0) if d.has("teleport") else 0.0,
		"repeat_delay": float(d.get("teleport", {}).get("repeat_delay", 0.0)),
		"damage_type": dtype,
		"attack_kind": attack_kind,
		"defense": "pdd" if dtype == "physical" else "mdd" if dtype == "magic" else "none",
		"damage_pct": book.canonical(key, lv, "damage", 100.0) / 100.0 if dtype == "physical" else 1.0,
		"player_level": char_level,
		"damage_min": lo,
		"damage_max": hi,
		"magic": dtype == "magic",
		"element": String(book.skill_node(key).get("elemAttr", "")),
		"attack_count": maxi(1, int(book.canonical(key, lv, "attackCount", 1.0))),
		"crit": skill_stat(key, "crit", 0.0) + player_stat("crit", crit_chance + acc * crit_per_acc + crit_bonus),
		"crit_mult": crit_mult,
		"crit_damage_bonus": crit_damage_bonus,
		"speed_factor": speed_factor,
		"cooldown": maxf(0.05, skill_stat(key, "cooldown", _base_cooldown(key, d, heal, lv)) * speed_factor),
		"range": skill_stat(key, "range", float(d.get("range", book.canonical(key, lv, "range", 0.0))))
			+ (passive_total(RANGE) if attacks and weapon_family in WeaponInfo.RANGED_FAMILIES
				and weapon_family in book.weapon_families(key) else 0.0),
		"speed": skill_stat(key, "speed", float(d.get("speed", 0.0))),
		"count": maxi(1, roundi(skill_stat(key, "count", float(d.get("count", book.canonical(key, lv, "bulletCount", 1.0)))))),
		"pierce": maxi(0, roundi(skill_stat(key, "pierce", float(d.get("pierce", 0))))),
		"radius": float(d.get("radius", 10.0)),
		"ball": book.visual(key, "ball", lv, char_level),
		"hit": book.visual(key, "hit", lv, char_level),
		"effect": book.visual(key, "effect", lv, char_level),
		"action": action,
		"action_time": float(d.get("action_time", 0.0)) * speed_factor,
		"rotate": bool(d.get("rotate", false)),
		"passive_stat": String(passive.get("stat", "")),
		"passive_value": passive_value(key, lv, passive),
		"icon": String(d.get("icon", "")),
		"duration": book.canonical(key, lv, String(buff.get("duration_field", "time")), 0.0),
		"buff_stat": String(buff.get("stat", "")),
		"buff_value": book.canonical(key, lv, String(buff.get("field", "")), 0.0) if not buff.is_empty() else 0.0,
		"buff_effects": _buff_effects(key, lv, buff),
		"buff_cooldown": book.canonical(key, lv, String(buff.get("cooldown_field", "time")), 0.0),
		"pulse_interval": float(buff.get("pulse_interval", 0.0)),
		"hp_threshold": float(buff.get("hp_threshold", 0.0)),
		"hidden": bool(buff.get("hidden", false)),
		"morph": int(book.canonical(key, lv, String(buff.morph_field), 0.0)) if buff.has("morph_field") else 0,
		# The roll draws the Pirate stream 16 (RunWorld.start_buff): a future non-Pirate failure chance needs its own stream.
		"fail_chance": clampf(book.canonical(key, lv, String(buff.fail_field), 0.0) / 100.0, 0.0, 1.0)
			if buff.has("fail_field") else 0.0,
		"end_hp_above": float(buff.get("end_hp_above", 0.0)),
		"cooldown_from_cast": bool(buff.get("cooldown_from_cast", false)),
		"displacement": _displacement(key, d, r, lv),
		"conversion": _conversion(key, d, lv),
	}


## The seconds between casts before cards and attack speed: the definition's `cooldown_field` (a canonical level number,
## MP Recovery's `cooltime`) when it names one, else the Heal `recast_delay`, else the survivor `cooldown`, else 1.
func _base_cooldown(key: String, d: Dictionary, heal: Dictionary, lv: int) -> float:
	var fallback := float(heal.get("recast_delay", d.get("cooldown", 1.0)))
	if d.has("cooldown_field"):
		return book.canonical(key, lv, String(d.cooldown_field), fallback)
	return fallback


## The resolved HP-to-MP conversion of `key` ({} for a skill that has none): {pay, gain} as fractions, `pay` the share of
## MaxHP paid and `gain` the share of the HP paid that comes back as MP. The definition's `convert` block names the
## canonical level fields (percent numbers) as `pay_field` and `gain_field` (docs/GAME_DESIGN.md 7.16).
func _conversion(key: String, d: Dictionary, lv: int) -> Dictionary:
	var block: Variant = d.get("convert", {})
	if not (block is Dictionary) or (block as Dictionary).is_empty():
		return {}
	return {"pay": maxf(0.0, book.canonical(key, lv, String(block.get("pay_field", "x"))) / 100.0),
		"gain": maxf(0.0, book.canonical(key, lv, String(block.get("gain_field", "y"))) / 100.0)}


## The resolved moving-attack block of `key` ({} for a skill that does not move): {direction "away" | "toward", when
## "before" | "after" | "during", distance px >= 0}. The definition's `displacement` gives the distance as `field` (a
## canonical level field of this rank's level), `distances` (survivor values per rank, the last one repeating) or a
## plain `distance`, in that order (docs/GAME_DESIGN.md 7.13).
func _displacement(key: String, d: Dictionary, rank: int, lv: int) -> Dictionary:
	var block: Variant = d.get("displacement", {})
	if not (block is Dictionary) or (block as Dictionary).is_empty():
		return {}
	var distance := 0.0
	if block.has("field"):
		distance = book.canonical(key, lv, String(block.field), 0.0)
	elif block.has("distances") and not (block.distances as Array).is_empty():
		var list: Array = block.distances
		distance = float(list[clampi(rank - 1, 0, list.size() - 1)])
	else:
		distance = float(block.get("distance", 0.0))
	return {"direction": String(block.get("direction", "away")), "when": String(block.get("when", "after")),
		"distance": maxf(0.0, distance)}


func _buff_effects(key: String, lv: int, buff: Dictionary) -> Dictionary:
	var effects := {}
	if buff.has("stat"):
		effects[String(buff.stat)] = book.canonical(key, lv, String(buff.get("field", "")), 0.0)
	for effect: Dictionary in buff.get("effects", []):
		var stat := String(effect.stat)
		# `scale` (optional, default 1) flips a WZ sign (the Boosters' negative speed steps use -1; Rage's pdd is already negative in the WZ and takes no scale).
		effects[stat] = float(effects.get(stat, 0.0)) \
			+ book.canonical(key, lv, String(effect.field), 0.0) * float(effect.get("scale", 1.0))
	return effects


## Every effect of owned skill `key`'s `passive`: the legacy single `stat` (with `field` or `per_level`) first, then the
## optional `effects` list of {stat, field | per_level} entries (a Mastery skill adds mastery and ACC, Critical Shot adds
## chance and damage).
func passive_effects(key: String) -> Array:
	var p: Dictionary = book.def(key).get("passive", {})
	var out: Array = []
	if p.has("stat"):
		out.append(p)
	out.append_array(p.get("effects", []))
	return out


## Sum of owned passive effects of `passive_stat`: canonical fields or survivor per-level values from skills.json. A skill
## whose weapon requirement the held family fails (SkillBook.usable_with with `weapon_family`) contributes nothing.
func passive_total(passive_stat: String) -> float:
	var t := 0.0
	for k: String in order:
		if not book.usable_with(k, weapon_family):
			continue
		for effect: Dictionary in passive_effects(k):
			if String(effect.get("stat", "")) == passive_stat:
				t += passive_value(k, level(k), effect)
	return t


## The largest single owned effect of `passive_stat` (same weapon gating as passive_total); 0 when none. For stats that
## do not stack across skills (mastery, crit damage).
func passive_best(passive_stat: String) -> float:
	var best := 0.0
	for k: String in order:
		if not book.usable_with(k, weapon_family):
			continue
		for effect: Dictionary in passive_effects(k):
			if String(effect.get("stat", "")) == passive_stat:
				best = maxf(best, passive_value(k, level(k), effect))
	return best


## Extra HP or MP (`pool` "hp" / "mp") that the owned skills with a `regen` field add to one regeneration pulse at
## `char_level`. A skill declares `"regen": {"pool": "mp", "divisor": 10}`; its bonus is floor(character level x skill
## level / divisor), whole points. tier B: the pre-Big-Bang Improved MP Recovery rule. A `"field"` instead of a divisor
## (`{"pool": "hp", "field": "hp"}`, Improved HP Recovery) adds that canonical level number as it is (tier A: +3 to +50).
func regen_bonus(pool: String, char_level: int) -> float:
	var t := 0.0
	for k: String in order:
		var r: Variant = book.def(k).get("regen")
		if r is Dictionary and String(r.get("pool", "")) == pool:
			if r.has("field"):
				t += book.canonical(k, level(k), String(r.field))
			else:
				t += floorf(float(char_level * level(k)) / maxf(1.0, float(r.get("divisor", 1.0))))
	return t


## Effect of skill `key`'s `passive` at canonical `skill_level`: its survivor `per_level` value times the level, else
## the canonical `field` of that level (0 without a passive).
func passive_value(key: String, skill_level: int, passive: Dictionary) -> float:
	if passive.has("per_level"):
		return float(passive.per_level) * skill_level
	return book.canonical(key, skill_level, String(passive.get("field", "")), 0.0) if not passive.is_empty() else 0.0


static func _stack(m: Vector2, op: String, value: float) -> Vector2:
	if op == "mul":
		return Vector2(m.x, m.y * value)
	return Vector2(m.x + value, m.y)
