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
## WZ text is cleaned: its literal "\n" / "\r\n" escapes become line breaks; a WZ level line drops its MP cost ("MP -10, ",
## "Use 20 MP, ", ...: there is no MP, ADR 0006; strip_mp_cost); the "[Master Level : N]" line and the
## "Required Skill : ..." lines go (tier C: the level text shows the cap, and WZ prerequisites are ignored, #31).
##
## Templates (override `h` only): `{name}` is replaced by a number, `{name|monster|monsters}` by the number and
## the singular or plural word. Names resolve, in order, from the effective `stats` passed in (Loadout.stats: count,
## mob_count, pierce, hp_cost, cooldown, duration, level, ... including behaviour cards), then the canonical fields of
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
static var _mp_cost_res: Array[RegEx] = []
## tier C (ours): the v83 String.wz wordings of a level's MP cost that strip_mp_cost removes, in order (measured on
## the v83 Skill.img h lines; a rarer wording stays as written).
const MP_COST_PATTERNS := ["(?<=HP)(\\s*-\\s*\\d+)\\s*,\\s*MP\\s*-\\s*\\d+", "-?\\bMP\\s*-?\\s*\\d+\\s*(consume)?\\s*[,;]\\s*",
	"\\bUse\\s+\\d+%?\\s*MP\\s*[,;]\\s*", "\\bUse\\s+MP\\s*\\d+\\s*[,;]\\s*", "\\bConsumes\\s+\\d+\\s*MP\\s*[,.;]\\s*",
	",\\s*\\d+\\s*MP\\b(?!\\s*[+%])", "(?<=HP \\d)(\\d*),\\s*MP\\s*\\d+"]


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
	var line := ""
	if over is String:
		line = fill(clean(String(over)), _vars(key, level, stats))
	else:
		var node := book.level_node(key, level)
		var hs := String(node.get("hs", "h%d" % level))
		line = strip_mp_cost(clean(String(_wz(key).get(hs, ""))))
	var mechanics := PackedStringArray()
	var def := book.def(key)
	if def.has("meter"):
		mechanics.append("Needs %d orbs" % int(def.meter.get("min", 0)))
		var keep := int(stats.get("meter_keep", 0))
		if str(def.meter.get("spend", "")) == "all":
			mechanics.append("Spends all orbs" if keep <= 0 else "Spends all but %d orbs; Keeps %d orbs" % [keep, keep])
		elif def.meter.has("spend"):
			mechanics.append("Spends %d orbs" % int(def.meter.spend))
	if def.has("knockback"):
		mechanics.append("Knock-back: %s%% / %s px" % [number(float(stats.get("knockback_chance", 0.0))),
			number(float(stats.get("knockback_distance", 0.0)))])
	if def.has("pull"):
		var pulled := int(stats.get("mob_count", 1))
		mechanics.append("Pulls up to %d %s from %s px" % [pulled, "monster" if pulled == 1 else "monsters",
			number(float(stats.get("range", 0.0)))])
	if int(stats.get("blast_targets", 0)) > 0:
		var targets := int(stats.blast_targets)
		mechanics.append("Blast: %d %s" % [targets, "target" if targets == 1 else "targets"])
	if String(stats.get("cast_rule", "")) == "chain":
		var links := int(stats.get("mob_count", 1))
		mechanics.append("Jumps to up to %d %s within %s px" % [links, "monster" if links == 1 else "monsters",
			number(ChainCast.hop_of(stats))])
	if def.has("pierce_falloff"):
		mechanics.append("Pierce fall-off: %s%% per target (minimum %s%%)" % [
			number(float(stats.get("pierce_falloff", 0.0)) * 100.0), number(float(stats.get("pierce_floor", 0.0)) * 100.0)])
	if stats.get("revive") is Dictionary:
		var revive: Dictionary = stats.revive
		# tier C (ours, BS8): the second-life line, the numbers of the plan PlayerRevive resolves.
		mechanics.append("When a hit would kill you: return at %s%% HP, %s s guard; recharge %s" % [
			number(float(revive.hp) * 100.0), number(float(revive.guard)), clock(SkillRunner.restart_cooldown(stats))])
	if not mechanics.is_empty():
		line += ("\n" if line != "" else "") + "; ".join(mechanics)
	return line


## `seconds` as M:SS (rounded to the whole second).
static func clock(seconds: float) -> String:
	var whole := maxi(0, roundi(seconds))
	return "%d:%02d" % [whole / 60, whole % 60]


## The notice a second life shows: the skill's name and when it works again.
static func revive_notice(recharge: float) -> String:
	return "Resurrection! Ready again in %s" % clock(recharge)


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
		if lo.book.def(skill).has("rarity_bonuses"):
			card["desc"] = c.get("desc", "") # preserve rank/bonus wording after dressing the learn detail
		out.append(card)
	return out


## `s` with WZ escapes turned into line breaks, the Master Level and Required Skill lines removed, and each line
## trimmed at its end.
## `line` without its v83 MP-cost wording (MP_COST_PATTERNS), its first letter capitalised when a cost led it.
static func strip_mp_cost(line: String) -> String:
	if _mp_cost_res.is_empty():
		for pattern: String in MP_COST_PATTERNS:
			_mp_cost_res.append(RegEx.create_from_string(pattern))
	var out := line
	for i in _mp_cost_res.size():
		# The HP-cost patterns keep their HP number (group 1); the rest are dropped whole.
		out = _mp_cost_res[i].sub(out, "$1" if i == 0 or i == _mp_cost_res.size() - 1 else "", true)
	if out != line and out != "":
		out = out.substr(0, 1).to_upper() + out.substr(1)
	return out


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
	# Buff movement values must not collide with projectile speed/range in the resolved stats.
	for k: String in stats.get("buff_effects", {}):
		vars["buff_" + k] = float(stats.buff_effects[k])
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
