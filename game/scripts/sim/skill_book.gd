class_name SkillBook
extends RefCounted
## Survivor skill definitions (`data/survivor/skills.json`) joined with the canonical per-level tables of Skill.wz
## (`setup.skill_imgs[book].skill[<7-digit id>].level[<level>]`, docs/ARCHITECTURE.md 4.4.1). Keys are the survivor
## skill keys ("three_snails"); `skill_id` is the original MapleStory id (1000).
##
## A skill's survivor rank r maps to canonical level `ranks[r - 1]` (clamped to the levels the WZ img has), so a rank-up
## changes exactly what the original level-up changed (damage, mastery, the projectile art). Visual paths are
## templates: `{level}` becomes the canonical level, `{cl}` the CharLevel variant for the character's level.

const ACTIVE_KINDS := ["projectile", "instant", "buff", "summon"]
## Skill.wz keys holding a weapon requirement code; the second has a trailing space (tier A: only 5001003 spells it so).
const WEAPON_FIELDS := ["weapon", "weapon "]

var rank_levels := {}
var slot_limits := {}
var defs := {}
var skill_imgs := {}

var _by_id := {}
## weapon_families cache: key -> [signature of the definition's own value, the resolved PackedStringArray].
var _families := {}


## Builds the book from the skills.json root and setup.skill_imgs.
static func from_data(skills_root: Dictionary, p_skill_imgs: Dictionary) -> SkillBook:
	var b := SkillBook.new()
	var d: Variant = skills_root.get("skills", {})
	if d is Dictionary:
		b.defs = d
	b.rank_levels = skills_root.get("rank_levels", {})
	b.slot_limits = skills_root.get("slot_limits", {})
	b.skill_imgs = p_skill_imgs
	for key: String in b.defs:
		b._by_id[int(b.defs[key].get("skill_id", 0))] = key
	return b


## True when `key` is defined in skills.json.
func has(key: String) -> bool:
	return defs.has(key)


## The skills.json definition of `key` ({} when unknown).
func def(key: String) -> Dictionary:
	return defs.get(key, {})


## Survivor key of an original skill id ("" when none).
func key_for_id(skill_id: int) -> String:
	return _by_id.get(skill_id, "")


## Original MapleStory skill id of `key` (0 when unknown).
func skill_id(key: String) -> int:
	return int(def(key).get("skill_id", 0))


## Skill id whose art (effect, hit, finish nodes and Use sound) a cast of `key` shows with a weapon of `family`: the
## `art_by_family` twin (Panic : Axe for Panic) for that family, else the skill's own id. Numbers are never taken from it.
func art_skill_id(key: String, family: String) -> int:
	return int(def(key).get("art_by_family", {}).get(family, skill_id(key)))


## The optional meter gate, spending and role policy for a skill.
func meter_rule(key: String) -> Dictionary:
	return def(key).get("meter", {})


## `path` (a Skill.wz or Sound.wz path naming this skill's id) re-pointed at the art twin for `family`; unchanged when
## there is no twin, no path, or the path does not name the skill.
func art_path(key: String, path: String, family: String) -> String:
	var own := skill_id(key)
	var twin := art_skill_id(key, family)
	if path == "" or twin == own:
		return path
	return path.replace("/%07d/" % own, "/%07d/" % twin)


## "projectile", "instant", "buff" or "passive".
func kind(key: String) -> String:
	return String(def(key).get("kind", ""))


## True for auto-cast skills (projectile / instant).
func is_active(key: String) -> bool:
	return kind(key) in ACTIVE_KINDS


## Slot the skill occupies ("active" / "passive").
func slot(key: String) -> String:
	return String(def(key).get("slot", "active" if is_active(key) else "passive"))


## Survivor rank mapping: explicit per-skill override, else the table for the WZ maximum level.
func rank_table(key: String) -> Array:
	var d := def(key)
	if d.has("ranks"):
		return d.ranks
	return rank_levels.get(str(max_level(key)), [1])


## Highest survivor rank (the length of `ranks`, at least 1).
func max_rank(key: String) -> int:
	return maxi(1, rank_table(key).size())


## Canonical skill level for survivor rank `rank` (clamped to 1..max_rank and to the img's level count).
func canonical_level(key: String, rank: int) -> int:
	var ranks := rank_table(key)
	if ranks.is_empty():
		return 1
	var lv := int(ranks[clampi(rank, 1, ranks.size()) - 1])
	var top := max_level(key)
	return clampi(lv, 1, top) if top > 0 else maxi(1, lv)


## WZ path of the skill node: "Skill.wz/000.img/skill/0001000".
func wz_path(key: String) -> String:
	return "Skill.wz/%s.img/skill/%07d" % [String(def(key).get("book", "")), skill_id(key)]


## The skill's node in its Skill.wz img ({} when the img or the skill is absent).
func skill_node(key: String) -> Dictionary:
	var img: Variant = skill_imgs.get(String(def(key).get("book", "")))
	if not (img is Dictionary):
		return {}
	var sk: Variant = img.get("skill")
	if not (sk is Dictionary):
		return {}
	var node: Variant = sk.get("%07d" % skill_id(key))
	return node if node is Dictionary else {}


## Weapon families a skill's data names (WeaponInfo.FAMILIES values; weapons gate no skill since #284, so this only says
## which weapons a skill was made for: a ranged skill's passive range bonus). Empty = any weapon. Source, in
## order: survivor skills.json `weapon_families` (tier C: an array of family names, or ["any"] for explicitly any weapon;
## it overrides the canonical value), then the Skill.wz `weapon` code (tier A: weapon type - 100, see
## WeaponInfo.family_of_skill_code), read from `weapon` and from `"weapon "` with a trailing space (tier A: the WZ typo on
## 5001003 Pirate Double Shot). No field or an unknown code means no requirement.
## Cached per key (the casting scan asks every tick): the entry is re-read when the definition's own `weapon_families`
## value changed (tests edit definitions in place); the Skill.wz img is static once the book is built.
func weapon_families(key: String) -> PackedStringArray:
	var raw: Variant = null
	var d: Variant = defs.get(key)
	if d is Dictionary:
		raw = (d as Dictionary).get("weapon_families")
	var signature := hash(raw)
	var cached: Variant = _families.get(key)
	if cached is Array and int(cached[0]) == signature:
		return cached[1]
	var out := _read_weapon_families(key)
	_families[key] = [signature, out]
	return out


func _read_weapon_families(key: String) -> PackedStringArray:
	var out := PackedStringArray()
	var d := def(key)
	if d.has("weapon_families"):
		var listed: Variant = d.weapon_families
		if listed is Array:
			for f: Variant in listed:
				if String(f) != "any" and not String(f) in out:
					out.append(String(f))
			if "any" in listed:
				out.clear()
		return out
	var node := skill_node(key)
	for field: String in WEAPON_FIELDS:
		var code: Variant = node.get(field)
		if (typeof(code) == TYPE_STRING and String(code).is_valid_int()) or typeof(code) == TYPE_INT \
				or typeof(code) == TYPE_FLOAT:
			var family := WeaponInfo.family_of_skill_code(int(code))
			if family != "":
				out.append(family)
				break
	return out


## Number of canonical levels in the img (0 when the img is absent).
func max_level(key: String) -> int:
	var lv: Variant = skill_node(key).get("level")
	if not (lv is Dictionary):
		return 0
	var top := 0
	for k: String in lv:
		if k.is_valid_int():
			top = maxi(top, int(k))
	return top


## The canonical level node `level/<level>` ({} when absent).
func level_node(key: String, level: int) -> Dictionary:
	var lv: Variant = skill_node(key).get("level")
	if not (lv is Dictionary):
		return {}
	var n: Variant = lv.get(str(level))
	return n if n is Dictionary else {}


## A canonical number of `key` at `level` (e.g. "fixdamage", "mad", "mastery", "attackCount", "x", "pdd").
func canonical(key: String, level: int, field: String, default: float = 0.0) -> float:
	var v: Variant = level_node(key, level).get(field)
	if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
		return float(v)
	if typeof(v) == TYPE_STRING and String(v).is_valid_float():
		return float(v)
	return default


## Fills a path template: {level} -> canonical level, {cl} -> CharLevel variant.
static func fill_path(template: String, level: int, char_variant: int = 0) -> String:
	return template.replace("{level}", str(level)).replace("{cl}", str(char_variant))


## Visual path `field` ("ball", "hit", "effect") of `key` at canonical `level` for a character of `char_level`:
## the `char_level` variant when the skill has one and the character reached a threshold, else the base template.
func visual(key: String, field: String, level: int, char_level: int) -> String:
	var d := def(key)
	var cl: Variant = d.get("char_level")
	if cl is Dictionary and cl.has(field):
		var best := 0
		for th: Variant in cl.get("thresholds", []):
			if char_level >= int(th):
				best = maxi(best, int(th))
		if best > 0:
			return fill_path(String(cl[field]), level, best)
	return fill_path(String(d.get(field, "")), level)
