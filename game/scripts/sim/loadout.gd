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
## Base crit chance and multiplier (balance.json `crit`).
var crit_chance := 0.0
var crit_mult := 1.5
var version := 0


func _init(p_book: SkillBook = null) -> void:
	book = p_book if p_book != null else SkillBook.new()


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


## Fully resolved numbers of skill `key` (owned or not; an unowned skill resolves at rank 1):
## skill, skill_id, kind, slot, rank, level, damage_type ("fixed"/"magic"/"none"), damage_min, damage_max (before mob
## defence, after damage multipliers), magic (bool: mob MDD applies), element (canonical elemAttr), attack_count,
## crit, crit_mult, cooldown, range, cast_rule (empty means legacy), cast_params (the cast block),
## has_box, box (canonical left-facing feet offsets scaled by area), area, mob_count (canonical plus count mods),
## mp_cost (canonical mpCon unless overridden by survivor data), speed, count, pierce, radius, ball, hit, effect
## (WZ paths), action, action_time, rotate, passive_stat,
## passive_value, icon, duration (canonical time), buff_stat and buff_value (canonical x / pdd at this cast level).
func stats(key: String) -> Dictionary:
	var d := book.def(key)
	var r := maxi(1, rank(key))
	var lv := book.canonical_level(key, r)
	var dtype := String(d.get("damage", "none"))
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
		"damage_type": dtype,
		"damage_min": lo,
		"damage_max": hi,
		"magic": dtype == "magic",
		"element": String(book.skill_node(key).get("elemAttr", "")),
		"attack_count": maxi(1, int(book.canonical(key, lv, "attackCount", 1.0))),
		"crit": skill_stat(key, "crit", 0.0) + player_stat("crit", crit_chance),
		"crit_mult": crit_mult,
		"cooldown": maxf(0.05, skill_stat(key, "cooldown", float(heal.get("recast_delay", d.get("cooldown", 1.0))))),
		"range": skill_stat(key, "range", float(d.get("range", 0.0))),
		"speed": skill_stat(key, "speed", float(d.get("speed", 0.0))),
		"count": maxi(1, roundi(skill_stat(key, "count", float(d.get("count", 1))))),
		"pierce": maxi(0, roundi(skill_stat(key, "pierce", float(d.get("pierce", 0))))),
		"radius": float(d.get("radius", 10.0)),
		"ball": book.visual(key, "ball", lv, char_level),
		"hit": book.visual(key, "hit", lv, char_level),
		"effect": book.visual(key, "effect", lv, char_level),
		"action": String(d.get("action", "")),
		"action_time": float(d.get("action_time", 0.0)),
		"rotate": bool(d.get("rotate", false)),
		"passive_stat": String(passive.get("stat", "")),
		"passive_value": passive_value(key, lv, passive),
		"icon": String(d.get("icon", "")),
		"duration": book.canonical(key, lv, String(buff.get("duration_field", "time")), 0.0),
		"buff_stat": String(buff.get("stat", "")),
		"buff_value": book.canonical(key, lv, String(buff.get("field", "")), 0.0) if not buff.is_empty() else 0.0,
		"buff_cooldown": book.canonical(key, lv, String(buff.get("cooldown_field", "time")), 0.0),
		"pulse_interval": float(buff.get("pulse_interval", 0.0)),
		"hp_threshold": float(buff.get("hp_threshold", 0.0)),
	}


## Sum of owned passive effects: canonical fields or survivor per-level values from skills.json.
func passive_total(passive_stat: String) -> float:
	var t := 0.0
	for k: String in order:
		var p: Dictionary = book.def(k).get("passive", {})
		if String(p.get("stat", "")) == passive_stat:
			t += passive_value(k, level(k), p)
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
