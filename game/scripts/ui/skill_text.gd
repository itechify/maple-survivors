class_name SkillText
extends RefCounted
## The one source of player-visible skill text: a skill's description and its line for one level, as v83 shows them in
## the skill window, adjusted to how the skill works in this game. The level-up cards (dress) and the Skill window
## tooltips (SkillWindowModel.skill_tooltip) use it.
##
##   var text := SkillText.new(world.book, library.find("String.wz/Skill.img"))
##   text.desc("thunder_bolt")                                       # "Attacks surrounding monsters ..."
##   text.level_line(key, lo.level(key), lo.stats(key))              # the owned level: "... up to 8 monsters"
##   var r := lo.rank(key) + 1                                       # the next level (rank r = canonical level r)
##   text.level_line(key, lo.book.canonical_level(key, r), lo.stats(key, r))
##   level_up_window.open(text.dress(cards, lo), level)              # level-up cards with their skill text
##
## Sources, per skill (survivor key of skills.json):
## - desc: the survivor override `text.desc` in skills.json (plain text), else String.wz/Skill.img/<7-digit id>/desc.
## - level line: the override template `text.h`, else the WZ line the level node names (`hs`, else "h<level>").
## WZ text is cleaned: its literal "\n" / "\r\n" escapes become line breaks; the "[Master Level : N]" line and the
## "Required Skill : ..." lines go (tier C: the level text shows the cap, and WZ prerequisites are ignored, #31).
##
## Templates (override `h` only): `{name}` is replaced by a number, `{name|monster|monsters}` by the number and
## the singular or plural word. Names resolve, in order, from the effective `stats` passed in (Loadout.stats: count,
## mob_count, pierce, mp_cost, cooldown, duration, level, ... including behaviour cards), then the canonical fields of
## that level node (mad, x, time, prop, ...; so `speed` and `range` mean the effective projectile values), then
## `mastery_pct` (canonical mastery as the percent v83 shows) and `passive_pct` (a survivor passive's value in %).
## An unknown name stays as written, so tests catch it.
##
## The returned text keeps the v83 markup `#c...#` (orange) and "\n" breaks: draw it with MapleText.draw_markup /
## MapleText.wrap (MapleText.plain strips it). Presentation only: the sim never sees these strings.

var book: SkillBook
var strings: Dictionary

static var _master_re: RegEx
static var _token_re: RegEx


## `p_book`: the run's SkillBook (skills.json defs with their `text` overrides, and the canonical level tables).
## `p_strings`: the String.wz/Skill.img tree (7-digit id -> {name, desc, h1, ...}); {} when the cache has none.
func _init(p_book: SkillBook, p_strings: Variant = {}) -> void:
	book = p_book
	strings = p_strings if p_strings is Dictionary else {}


## The description of skill `key` (override, else cleaned WZ desc); "" when it has neither.
func desc(key: String) -> String:
	var over: Variant = _overrides(key).get("desc")
	if over is String:
		return clean(String(over))
	return clean(String(_wz(key).get("desc", "")))


## The line of skill `key` at canonical `level`, filled from `stats` (the effective numbers of that level, as
## Loadout.stats(key, rank) returns them); "" when there is neither an override nor a WZ line.
func level_line(key: String, level: int, stats: Dictionary) -> String:
	var over: Variant = _overrides(key).get("h")
	if over is String:
		return fill(clean(String(over)), _vars(key, level, stats))
	var node := book.level_node(key, level)
	var hs := String(node.get("hs", "h%d" % level))
	return clean(String(_wz(key).get(hs, "")))


## Copies of the cards of a choice_pending event with this skill text at the offered level, using the effective
## numbers of `lo` (the run's Loadout): a learn card's `desc` becomes the skill's description and its `detail` the line
## of its starting level; a rank card's `desc` becomes the next level's line (its before -> after values stay). Mod
## cards keep their own effect text (their numbers are in skill_mod_changes), other cards are unchanged, and a card
## keeps its data text wherever there is no skill text (no String.wz in the cache).
func dress(cards: Array, lo: Loadout) -> Array:
	var out: Array = []
	for c: Variant in cards:
		var card: Dictionary = (c as Dictionary).duplicate(true) if c is Dictionary else {}
		var skill := String(card.get("skill", ""))
		var kind := String(card.get("kind", ""))
		if skill != "" and lo.book.has(skill):
			var magnitude := maxi(1, int(card.get("magnitude", 1)))
			if kind == "skill_new":
				var d := desc(skill)
				if d != "":
					card["desc"] = d
				card["detail"] = level_line(skill, lo.book.canonical_level(skill, magnitude), lo.stats(skill, magnitude))
			elif kind == "skill_rank" and lo.has(skill):
				var r := lo.rank(skill) + magnitude
				var line := level_line(skill, lo.book.canonical_level(skill, r), lo.stats(skill, r))
				if line != "":
					card["desc"] = line
		out.append(card)
	return out


## `s` with WZ escapes turned into line breaks, the Master Level and Required Skill lines removed, and each line
## trimmed at its end.
static func clean(s: String) -> String:
	if _master_re == null:
		_master_re = RegEx.create_from_string("^\\[?Master Level\\s*:\\s*\\d+\\]\\s*")
	s = s.replace("\\r", "").replace("\r", "").replace("\\n", "\n")
	var out := PackedStringArray()
	for line in s.split("\n"):
		line = _master_re.sub(line, "")
		if line.strip_edges().begins_with("Required Skill"):
			continue
		out.append(line.strip_edges(false, true))
	var joined := "\n".join(out).strip_edges()
	while joined.contains("\n\n"):
		joined = joined.replace("\n\n", "\n")
	return joined


## Replaces every `{name}` / `{name|singular|plural}` in `template` with the number `vars[name]`.
static func fill(template: String, vars: Dictionary) -> String:
	if _token_re == null:
		_token_re = RegEx.create_from_string("\\{([a-z_]+)(?:\\|([^|{}]*)\\|([^|{}]*))?\\}")
	var out := ""
	var at := 0
	for m in _token_re.search_all(template):
		out += template.substr(at, m.get_start() - at)
		at = m.get_end()
		var name := m.get_string(1)
		if not vars.has(name):
			out += m.get_string()
			continue
		var v := float(vars[name])
		out += number(v)
		if m.get_string(2) != "" or m.get_string(3) != "":
			out += " " + (m.get_string(2) if is_equal_approx(v, 1.0) else m.get_string(3))
	return out + template.substr(at)


## A number as v83 text: whole values without decimals, others to at most two decimals.
static func number(v: float) -> String:
	var r := snappedf(v, 0.01)
	if is_equal_approx(r, roundf(r)):
		return str(int(roundf(r)))
	return String.num(r, 2).rstrip("0").rstrip(".")


func _vars(key: String, level: int, stats: Dictionary) -> Dictionary:
	var vars := {}
	for k: String in book.level_node(key, level):
		var v: Variant = book.level_node(key, level)[k]
		if typeof(v) in [TYPE_INT, TYPE_FLOAT]:
			vars[k] = float(v)
	for k: String in stats:
		if typeof(stats[k]) in [TYPE_INT, TYPE_FLOAT]:
			vars[k] = float(stats[k])
	if vars.has("mastery") and not stats.has("mastery"):
		vars["mastery_pct"] = roundf(CombatMath.mastery_fraction(int(vars.mastery)) * 100.0)
	if stats.has("passive_value"):
		vars["passive_pct"] = snappedf(float(stats.passive_value) * 100.0, 0.01)
	return vars


func _overrides(key: String) -> Dictionary:
	var t: Variant = book.def(key).get("text")
	return t if t is Dictionary else {}


func _wz(key: String) -> Dictionary:
	var id := book.skill_id(key)
	if id <= 0:
		return {}
	var node: Variant = strings.get("%07d" % id)
	return node if node is Dictionary else {}
