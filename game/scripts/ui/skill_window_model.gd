class_name SkillWindowModel
extends RefCounted
## What the v83 Skill window (SkillWindow, #86) shows, built from plain run data so it can be tested without nodes or
## the cache: one tab per job on the character's line below the Beginner (1st job up to the character's own job; #284:
## the Beginner is no longer playable), each listing every skill of that job the game implements (spec #225: there are no job-neutral cards, so no star tab). Read-only:
## it never changes the loadout.
##
##   var m := SkillWindowModel.new(world.book, world.upgrades, world.loadout, world.jobs, job_id, run.skill_text)
##   m.tabs        # [{name, job_id, tier, book_name, book_icon, rows: [...]}]
##
## Tabs: `tier` picks the v83 tab glyph (UIWindow.img/Skill/Tab/<state>/<tier>: the Beginner mark, I, II, ...);
## `book_name` is String.wz/Skill.img/<book>/bookName ("" without it), `book_icon` Skill.wz/<book>.img/info/icon.

var book: SkillBook
var pool: UpgradePool
var loadout: Loadout
var jobs: JobTree
var job_id := 0
var text: SkillText
## The tabs, left to right (see the class doc).
var tabs: Array[Dictionary] = []


func _init(p_book: SkillBook, p_pool: UpgradePool, p_loadout: Loadout, p_jobs: JobTree, p_job_id: int,
		p_text: SkillText) -> void:
	book = p_book
	pool = p_pool
	loadout = p_loadout
	jobs = p_jobs
	job_id = p_job_id
	text = p_text
	var path := jobs.lineage(job_id)
	path.reverse()
	for id in path:
		var j := jobs.job(id)
		if int(j.get("tier", 0)) == 0:
			continue
		var bk := String(j.get("book", ""))
		var names: Variant = text.strings.get(bk, {}) if text != null else {}
		tabs.append({"name":String(j.get("name", str(id))), "job_id": id, "tier": int(j.get("tier", 0)),
			"book_name": String(names.get("bookName", "")) if names is Dictionary else "",
			"book_icon": "Skill.wz/%s.img/info/icon" % bk if bk != "" else "", "rows": _skill_rows(id)})


## The tooltip of skill `key`: {name, icon, desc, level (0 when unlearned), current (the owned level's line, "" when
## unlearned), next_level (0 at the cap), next (that level's line), cooldown (s between casts:
## SkillRunner.restart_cooldown; -1 for a passive), mp_cost (-1 for a passive), hp_cost (only for an active skill that
## pays HP, Slash Blast), upgrades: [{id, name, steps, effect, text}] (every behaviour
## card taken for the skill, in card order: "Twin Claw ×2: +2 targets")}. Lines come from SkillText filled with the
## effective stats, so cards show in the numbers.
func skill_tooltip(key: String) -> Dictionary:
	var d := book.def(key)
	var r := loadout.rank(key)
	var st := loadout.stats(key)
	var kind := book.kind(key)
	var tip := {"key": key, "name": String(d.get("name", key)), "icon": String(d.get("icon", "")),
		"desc": text.desc(key), "level": loadout.level(key), "current": "", "next_level": 0, "next": "",
		"cooldown": -1.0, "mp_cost": -1, "upgrades": []}
	if r > 0:
		tip.current = text.level_line(key, loadout.level(key), st)
	if r < book.max_rank(key):
		tip.next_level = book.canonical_level(key, r + 1)
		tip.next = text.level_line(key, tip.next_level, loadout.stats(key, r + 1))
	if kind != "passive":
		tip.mp_cost = int(st.mp_cost)
		tip.hp_cost = int(st.hp_cost)
		tip.cooldown = SkillRunner.restart_cooldown(st)
	var upgrades: Array[Dictionary] = []
	for c: Dictionary in pool.cards:
		var id := String(c.get("id", ""))
		var steps := int(loadout.card_ranks.get(id, 0))
		if String(c.get("kind", "")) != "skill_mod" or String(c.get("skill", "")) != key or steps <= 0:
			continue
		var effect := mod_effect(c, steps, kind)
		var cname := String(c.get("name", id))
		upgrades.append({"id": id, "name": cname, "steps": steps, "effect": effect,
			"text": "%s ×%d: %s" % [cname, steps, effect]})
	tip.upgrades = upgrades
	return tip


## The total effect of `steps` steps of skill_mod card `c` on a skill of `skill_kind`, stacked as UpgradePool.apply
## stacks them: "+2 targets", "+1 shot", "-12% cooldown", "+56.25% speed"; effects joined with ", ".
static func mod_effect(c: Dictionary, steps: int, skill_kind: String) -> String:
	var parts := PackedStringArray()
	for e: Dictionary in c.get("effects", []):
		var stat := String(e.get("stat", ""))
		var value := float(e.get("value", 0.0))
		if stat == "rank" or stat == "":
			continue
		if String(e.get("op", "add")) == "mul":
			var pct := (pow(value, steps) - 1.0) * 100.0
			parts.append("%s%s%% %s" % ["+" if pct >= 0.0 else "-", SkillText.number(absf(pct)), stat])
			continue
		var total := value * steps
		var sign := "+" if total >= 0.0 else "-"
		match stat:
			"count":
				var noun := SkillRunner.count_meaning(skill_kind).trim_suffix("s")
				parts.append("%s%s %s%s" % [sign, SkillText.number(absf(total)), noun,
					"" if is_equal_approx(absf(total), 1.0) else "s"])
			"crit":
				parts.append("%s%s%% crit" % [sign, SkillText.number(absf(total) * 100.0)])
			_:
				parts.append("%s%s %s" % [sign, SkillText.number(absf(total)), stat])
	return ", ".join(parts)


## The rows of job `id`: every skills.json skill of that job that a card offers or the run owns, by skill id.
func _skill_rows(id: int) -> Array[Dictionary]:
	var offered := {}
	for c: Dictionary in pool.cards:
		offered[String(c.get("skill", ""))] = true
	var keys: Array = []
	for key: String in book.defs:
		if int(book.def(key).get("job", -1)) == id and (offered.has(key) or loadout.has(key)):
			keys.append(key)
	keys.sort_custom(func(a: String, b: String) -> bool: return book.skill_id(a) < book.skill_id(b))
	var rows: Array[Dictionary] = []
	for key: String in keys:
		var d := book.def(key)
		var icon := String(d.get("icon", ""))
		rows.append({"key": key, "skill_id": book.skill_id(key), "name": String(d.get("name", key)), "icon": icon,
			"icon_disabled": icon.trim_suffix("icon") + "iconDisabled" if icon.ends_with("/icon") else "",
			"level": loadout.level(key), "max_level": book.canonical_level(key, book.max_rank(key)),
			"learned": loadout.has(key)})
	return rows
