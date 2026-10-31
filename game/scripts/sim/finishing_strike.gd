class_name FinishingStrike
extends RefCounted
## The finishing strike (`finish_strike`, spec #425 SH5, GAME_DESIGN 7.133): the last damage line of a multi-line cast gets its
## own crit chance and crit bonus, read from the skill's canonical level fields. `{"finish_strike": {"chance_field": "prop",
## "bonus_field": "criticalDamage"}}` makes Loadout.stats add `finish_chance` (percent) and `finish_bonus` (skill-percent
## points, the Critical Throw convention of ProjectileSystem.roll_damage); a skill without the block gains neither key, so its
## stats are unchanged. Generic: Assassinate (4221001) uses it today and there is no skill ID in this file.
##
## This script holds only the pure arithmetic (which line is the last, the stats of that line) and the data checks.
## SkillRunner._resolve_target hands each line `line_stats`, so the existing per-line crit roll (ProjectileSystem.roll_damage:
## one roll per line, in line order) simply uses the higher chance on the last line. It draws no random numbers of its own.

## Block keys. tier C: ours (SH-7); `prop` / `criticalDamage` are the WZ level fields of 4221001 the block names.
const CHANCE_KEY := "finish_chance"
const BONUS_KEY := "finish_bonus"


## Whether a skill definition has a `finish_strike` block.
static func has_block(definition: Dictionary) -> bool:
	return definition.has("finish_strike")


## Whether the stats of a resolved skill carry a finishing strike.
static func is_active(st: Dictionary) -> bool:
	return st.has(CHANCE_KEY)


## The two keys Loadout.stats adds for a skill with the block: `finish_chance` (percent) and `finish_bonus` (skill-percent points)
## read from the named canonical fields of one level node. {} for a definition without the block.
static func resolve(definition: Dictionary, level_node: Dictionary) -> Dictionary:
	if not has_block(definition) or not definition.finish_strike is Dictionary:
		return {}
	var block: Dictionary = definition.finish_strike
	return {
		CHANCE_KEY: maxf(0.0, _number(level_node.get(String(block.get("chance_field", "")), 0.0))),
		BONUS_KEY: maxf(0.0, _number(level_node.get(String(block.get("bonus_field", "")), 0.0))),
	}


## Whether line `line` (0-based) of a cast of `lines` lines is the finishing one. A one-line cast treats its only line as the last.
static func is_last(line: int, lines: int) -> bool:
	return line >= maxi(1, lines) - 1


## The stats the damage roll of line `line` of `lines` uses: `st` itself for a skill without a finishing strike and for every line
## but the last (no copy), otherwise a shallow copy whose `crit` (a 0..1 chance) is raised by `finish_chance` percent, capped at 1,
## and whose `crit_damage_bonus` gains `finish_bonus` points.
static func line_stats(st: Dictionary, line: int, lines: int) -> Dictionary:
	if not is_active(st) or not is_last(line, lines):
		return st
	var out := st.duplicate()
	out["crit"] = minf(1.0, float(st.get("crit", 0.0)) + float(st[CHANCE_KEY]) / 100.0)
	out["crit_damage_bonus"] = float(st.get("crit_damage_bonus", 0.0)) + float(st.get(BONUS_KEY, 0.0))
	return out


## The data-file errors of every `finish_strike` block in a merged skills file: an object naming a non-empty `chance_field` and
## `bonus_field` string.
static func errors(skills_file: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	var skills: Variant = skills_file.get("skills")
	if not skills is Dictionary:
		return out
	for key: Variant in skills:
		var definition: Variant = skills[key]
		if not definition is Dictionary or not has_block(definition):
			continue
		if not definition.finish_strike is Dictionary:
			out.append("skill '%s': finish_strike must be an object" % key)
			continue
		for field in ["chance_field", "bonus_field"]:
			var named: Variant = definition.finish_strike.get(field)
			if not named is String or String(named) == "":
				out.append("skill '%s': finish_strike.%s must name a canonical level field" % [key, field])
	return out


## The errors of `finish_strike` blocks against the canonical data: every level of every rank of the skill must hold both named
## fields as numbers (the data names a field the skill has). Needs the skill's WZ node, so the unit test with the real cache and
## synthetic books call it; the structural check at load is `errors`.
static func level_errors(book: SkillBook) -> PackedStringArray:
	var out := PackedStringArray()
	for key: String in book.defs:
		var definition: Dictionary = book.defs[key]
		if not has_block(definition) or not definition.finish_strike is Dictionary:
			continue
		for rank in range(1, book.max_rank(key) + 1):
			var node := book.level_node(key, book.canonical_level(key, rank))
			for field in ["chance_field", "bonus_field"]:
				var named := String(definition.finish_strike.get(field, ""))
				if named == "" or not _is_number(node.get(named)):
					out.append("skill '%s': finish_strike.%s '%s' is not a number at rank %d" % [key, field, named, rank])
	return out


static func _is_number(v: Variant) -> bool:
	return typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT or (typeof(v) == TYPE_STRING and String(v).is_valid_float())


static func _number(v: Variant) -> float:
	return float(v) if _is_number(v) else 0.0
