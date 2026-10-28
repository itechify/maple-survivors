extends TestCase
## The v83 Skill window (#86): SkillWindowModel's tabs (one per job on the character's line below the Beginner, no star
## tab, spec #225, and no Beginner tab, #284),
## rows (every implemented skill of the job with its level / max, unlearned ones at 0), the tooltips (SkillText lines,
## cooldown, MP cost, the Upgrades list of behaviour cards); then SkillWindow's
## keyboard navigation. All data is synthetic (no cache): a two-branch job tree, a few skills, a few cards.

## Synthetic String.wz/Skill.img: book names and skill lines.
const STRINGS := {
	"000": {"bookName": "Beginner's Basics"},
	"200": {"bookName": "Intro. to Magic"},
	"220": {"bookName": "Ice & Lightning Basics"},
	"0001000": {"name": "Three Snails", "desc": "Throws snail shells.", "h1": "MP -3, damage 10",
		"h2": "MP -3, damage 25"},
	"2001005": {"name": "Magic Claw", "desc": "Use MP to attack an enemy twice.", "h1": "MP -10, basic attack 11",
		"h2": "MP -10, basic attack 12"},
	"2001004": {"name": "Energy Bolt", "desc": "Use MP to attack one enemy.", "h1": "MP -6, basic attack 20"},
	"2000001": {"name": "Improved MP Recovery", "desc": "Recovers more MP.", "h1": "MP recovery +3"},
}


func _jobs() -> JobTree:
	return JobTree.from_data({"jobs": [
		{"id": 0, "name": "Beginner", "parent": -1, "tier": 0, "level": 1, "book": "000"},
		{"id": 200, "name": "Magician", "parent": 0, "tier": 1, "level": 8, "book": "200"},
		{"id": 210, "name": "Wizard (Fire, Poison)", "parent": 200, "tier": 2, "level": 30, "book": "210"},
		{"id": 220, "name": "Wizard (Ice, Lightning)", "parent": 200, "tier": 2, "level": 30, "book": "220"},
	]}, {})


func _book() -> SkillBook:
	var skills := {
		"three_snails": {"skill_id": 1000, "book": "000", "job": 0, "kind": "projectile", "damage": "fixed",
			"name": "Three Snails", "icon": "Skill.wz/000.img/skill/0001000/icon", "cooldown": 1.1, "count": 1,
			"ranks": [1, 2]},
		"magic_claw": {"skill_id": 2001005, "book": "200", "job": 200, "kind": "instant", "damage": "magic",
			"name": "Magic Claw", "icon": "Skill.wz/200.img/skill/2001005/icon", "cooldown": 1.25, "count": 1,
			"ranks": [1, 2]},
		"energy_bolt": {"skill_id": 2001004, "book": "200", "job": 200, "kind": "projectile", "damage": "magic",
			"name": "Energy Bolt", "icon": "Skill.wz/200.img/skill/2001004/icon", "cooldown": 0.9, "count": 1,
			"ranks": [1]},
		"improved_mp_recovery": {"skill_id": 2000001, "book": "200", "job": 200, "kind": "passive",
			"damage": "none", "name": "Improved MP Recovery", "icon": "Skill.wz/200.img/skill/2000001/icon",
			"ranks": [1]},
		"thunder_bolt": {"skill_id": 2201005, "book": "220", "job": 220, "kind": "instant", "damage": "magic",
			"name": "Thunder Bolt", "icon": "Skill.wz/220.img/skill/2201005/icon", "ranks": [1]},
		"fire_arrow": {"skill_id": 2101004, "book": "210", "job": 210, "kind": "projectile", "damage": "magic",
			"name": "Fire Arrow", "icon": "Skill.wz/210.img/skill/2101004/icon", "ranks": [1]},
		"unused_skill": {"skill_id": 2001009, "book": "200", "job": 200, "kind": "instant", "damage": "magic",
			"name": "No Card", "ranks": [1]},
	}
	var imgs := {
		"000": {"skill": {"0001000": {"level": {"1": {"hs": "h1", "mpCon": 3.0, "fixdamage": 10.0},
			"2": {"hs": "h2", "mpCon": 3.0, "fixdamage": 25.0}}}}},
		"200": {"skill": {
			"2001005": {"level": {"1": {"hs": "h1", "mpCon": 10.0, "mad": 11.0, "mastery": 1.0},
				"2": {"hs": "h2", "mpCon": 10.0, "mad": 12.0, "mastery": 1.0}}},
			"2001004": {"level": {"1": {"hs": "h1", "mpCon": 6.0, "mad": 20.0, "mastery": 1.0}}},
			"2000001": {"level": {"1": {"hs": "h1", "x": 3.0}}}}},
	}
	return SkillBook.from_data({"skills": skills}, imgs)


func _pool() -> UpgradePool:
	return UpgradePool.from_data({
		"cards": [
			{"id": "three_snails_count", "kind": "skill_mod", "skill": "three_snails", "name": "Additional Shell",
				"desc": "Three Snails throws +{value} shell.", "value": 1, "max_rank": 4,
				"effects": [{"stat": "count", "op": "add", "value": 1}]},
			{"id": "energy_bolt_new", "kind": "skill_new", "skill": "energy_bolt", "name": "Energy Bolt",
				"max_rank": 1, "effects": []},
			{"id": "magic_claw_new", "kind": "skill_new", "skill": "magic_claw", "name": "Magic Claw",
				"max_rank": 1, "effects": []},
			{"id": "magic_claw_rank", "kind": "skill_rank", "skill": "magic_claw", "name": "Magic Claw",
				"max_rank": 20, "effects": [{"stat": "rank", "op": "add", "value": 1}]},
			{"id": "magic_claw_targets", "kind": "skill_mod", "skill": "magic_claw", "name": "Twin Claw",
				"desc": "Magic Claw strikes +{value} more monster.", "value": 1, "max_rank": 2,
				"effects": [{"stat": "count", "op": "add", "value": 1}]},
			{"id": "magic_claw_cooldown", "kind": "skill_mod", "skill": "magic_claw", "name": "Quick Claw",
				"desc": "Magic Claw cooldown -{value}%.", "max_rank": 3,
				"effects": [{"stat": "cooldown", "op": "mul", "value": 0.88}]},
			{"id": "improved_mp_recovery", "kind": "skill_new", "skill": "improved_mp_recovery",
				"name": "Improved MP Recovery", "max_rank": 1, "effects": []},
			{"id": "thunder_bolt_new", "kind": "skill_new", "skill": "thunder_bolt", "name": "Thunder Bolt",
				"max_rank": 1, "effects": []},
			{"id": "fire_arrow_new", "kind": "skill_new", "skill": "fire_arrow", "name": "Fire Arrow",
				"max_rank": 1, "effects": []},
		],
		"fallback": {"id": "elixir", "kind": "filler", "skill": "", "name": "Power Elixir",
			"desc": "Fully restores HP and MP.", "max_rank": 0, "effects": []},
	})


## A Magician (200) who has Three Snails rank 2 with one Additional Shell, Magic Claw rank 1 with Twin Claw x2 and
## Quick Claw x1, and took the Elixir fallback.
func _magician_loadout(book: SkillBook) -> Loadout:
	var lo := Loadout.new(book)
	lo.add_skill("three_snails")
	lo.set_rank("three_snails", 2)
	lo.add_skill_mod("three_snails", "count", "add", 1.0)
	lo.add_skill("magic_claw")
	lo.add_skill_mod("magic_claw", "count", "add", 2.0)
	lo.add_skill_mod("magic_claw", "cooldown", "mul", 0.88)
	lo.card_ranks = {"three_snails_count": 1, "magic_claw_new": 1, "magic_claw_targets": 2,
		"magic_claw_cooldown": 1, "elixir": 1}
	return lo


func _model(job_id: int, lo: Loadout = null) -> SkillWindowModel:
	var book := lo.book if lo != null else _book()
	if lo == null:
		lo = Loadout.new(book)
	return SkillWindowModel.new(book, _pool(), lo, _jobs(), job_id, SkillText.new(book, STRINGS))


static func _tab_names(m: SkillWindowModel) -> Array:
	var out := []
	for t: Dictionary in m.tabs:
		out.append(String(t.name))
	return out


func test_tabs_follow_the_job_line_without_beginner_or_star_tab() -> void:
	assert_eq(_tab_names(_model(0)), [], "the Beginner is no longer playable: no Beginner tab (#284)")
	assert_eq(_tab_names(_model(200)), ["Magician"], "1st job has its tab")
	var m := _model(220)
	assert_eq(_tab_names(m), ["Magician", "Wizard (Ice, Lightning)"],
		"the 2nd-job branch of the line, not the other branch")
	assert_eq(m.tabs[0].tier, 1, "the 1st job tab uses glyph I")
	assert_eq(m.tabs[1].tier, 2, "the 2nd job tab uses glyph II")
	assert_eq(m.tabs[0].book_name, "Intro. to Magic", "the job's v83 book name")
	assert_eq(m.tabs[0].book_icon, "Skill.wz/200.img/info/icon")


static func _row_keys(tab: Dictionary) -> Array:
	var out := []
	for r: Dictionary in tab.rows:
		out.append(String(r.get("key", r.get("id", ""))))
	return out


func test_each_job_tab_lists_the_jobs_implemented_skills_with_learned_ranks_and_greyed_unlearned_ones() -> void:
	var m := _model(200, _magician_loadout(_book()))
	assert_eq(m.tabs.size(), 1)
	assert_eq(_row_keys(m.tabs[0]), ["improved_mp_recovery", "energy_bolt", "magic_claw"],
		"every Magician skill a card can offer, in v83 skill id order; a skill no card offers is not listed")
	var claw: Dictionary = m.tabs[0].rows[2]
	assert_eq([claw.name, claw.level, claw.max_level, claw.learned], ["Magic Claw", 1, 2, true],
		"a learned skill shows its level / max")
	assert_eq(claw.icon, "Skill.wz/200.img/skill/2001005/icon")
	var bolt: Dictionary = m.tabs[0].rows[1]
	assert_eq([bolt.level, bolt.max_level, bolt.learned], [0, 1, false], "an unlearned skill is greyed at 0 / max")
	assert_eq(bolt.icon_disabled, "Skill.wz/200.img/skill/2001004/iconDisabled", "drawn with its v83 disabled icon")
	assert_eq(_row_keys(_model(220).tabs[1]), ["thunder_bolt"], "the 2nd-job tab lists that branch's skills")


func test_a_taken_elixir_is_never_listed_as_a_learned_skill() -> void:
	var m := _model(200, _magician_loadout(_book()))
	for t: Dictionary in m.tabs:
		assert_false("elixir" in _row_keys(t), "the Elixir is used, not learned")
	assert_false(m.has_method("card_tooltip"), "no job-neutral card tooltips remain")


func test_the_skill_tooltip_lists_each_behaviour_card_taken_with_its_steps() -> void:
	var m := _model(200, _magician_loadout(_book()))
	var tip := m.skill_tooltip("magic_claw")
	assert_eq(tip.upgrades.size(), 2, "the two Magic Claw behaviour cards taken; rank and learn cards are not listed")
	assert_eq([tip.upgrades[0].name, tip.upgrades[0].steps, tip.upgrades[0].effect], ["Twin Claw", 2, "+2 targets"])
	assert_eq(tip.upgrades[0].text, "Twin Claw ×2: +2 targets")
	assert_eq(tip.upgrades[1].text, "Quick Claw ×1: -12% cooldown", "a multiplier shows as its percentage")
	assert_eq(m.skill_tooltip("three_snails").upgrades[0].text, "Additional Shell ×1: +1 shot",
		"a projectile skill's count is shots")
	assert_eq(m.skill_tooltip("energy_bolt").upgrades, [], "no cards taken, no Upgrades")


func test_the_skill_tooltip_has_the_skill_text_cooldown_and_mp_cost() -> void:
	var m := _model(200, _magician_loadout(_book()))
	var tip := m.skill_tooltip("magic_claw")
	assert_eq([tip.name, tip.icon], ["Magic Claw", "Skill.wz/200.img/skill/2001005/icon"])
	assert_eq(tip.desc, "Use MP to attack an enemy twice.")
	assert_eq([tip.level, tip.current], [1, "MP -10, basic attack 11"], "the owned level's line")
	assert_eq([tip.next_level, tip.next], [2, "MP -10, basic attack 12"], "the next level's line")
	assert_near(tip.cooldown, 1.1, 1e-6, "the effective cooldown: 1.25 s with one Quick Claw step (x0.88)")
	assert_eq(tip.mp_cost, 10)
	var maxed := m.skill_tooltip("three_snails")
	assert_eq([maxed.level, maxed.current, maxed.next_level, maxed.next], [2, "MP -3, damage 25", 0, ""],
		"no next level at the cap")
	var unlearned := m.skill_tooltip("energy_bolt")
	assert_eq([unlearned.level, unlearned.current, unlearned.next_level, unlearned.next],
		[0, "", 1, "MP -6, basic attack 20"], "an unlearned skill shows what level 1 does")
	var passive := m.skill_tooltip("improved_mp_recovery")
	assert_eq([passive.cooldown, passive.mp_cost], [-1.0, -1], "a passive has neither")


static func _key(code: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.pressed = true
	return e


func test_the_keyboard_switches_tabs_and_moves_the_selection_with_its_tooltip() -> void:
	var w := SkillWindow.new(_model(220, _magician_loadout(_book())))
	assert_eq(w.window_id, "skill")
	assert_eq(w.tab, 1, "opens on the current job's tab")
	assert_eq(w.tooltip(), {}, "no tooltip before anything is selected")
	assert_true(w.handle_key(_key(KEY_LEFT)), "Left used")
	assert_eq(w.tab, 0, "Left: the previous tab")
	assert_true(w.handle_key(_key(KEY_DOWN)))
	assert_eq(w.selected, 0, "Down selects the first row")
	assert_eq(w.tooltip().get("key"), "improved_mp_recovery", "and shows its tooltip")
	w.handle_key(_key(KEY_DOWN))
	w.handle_key(_key(KEY_DOWN))
	w.handle_key(_key(KEY_DOWN))
	assert_eq(w.selected, 2, "Down stops at the last row")
	assert_eq(w.tooltip().get("key"), "magic_claw")
	assert_eq(w.tooltip().upgrades.size(), 2, "the tooltip carries the Upgrades list")
	w.handle_key(_key(KEY_UP))
	assert_eq(w.selected, 1)
	w.handle_key(_key(KEY_2))
	assert_eq(w.tab, 1, "2: the second tab (the 2nd job)")
	assert_eq(w.selected, -1, "a new tab starts without a selection")
	w.handle_key(_key(KEY_DOWN))
	assert_eq(w.tooltip().get("key"), "thunder_bolt")
	w.handle_key(_key(KEY_RIGHT))
	assert_eq(w.tab, 1, "Right stops at the last tab")
	assert_false(w.handle_key(_key(KEY_3)), "no third tab (no Beginner or star tab): the key is not used")
	w.handle_key(_key(KEY_1))
	assert_eq(w.tab, 0, "1: the Magician tab")
	assert_false(w.handle_key(_key(KEY_9)), "no ninth tab: the key is not used")
	assert_false(w.handle_key(_key(KEY_Q)), "other keys are left to the run")
	w.free()


func test_the_tooltip_draws_an_orange_upgrades_section() -> void:
	var m := _model(200, _magician_loadout(_book()))
	var shown := []
	var orange := []
	for l: Array in SkillTooltip.layout(m.skill_tooltip("magic_claw")):
		shown.append(String(l[1]))
		if l[2] == MapleText.ORANGE:
			orange.append(String(l[1]))
	assert_true("[Current Level : 1]" in shown and "[Next Level : 2]" in shown, "both level headings")
	assert_true("Cooldown 1.1 sec.   MP cost 10" in shown, "cooldown and MP cost")
	assert_eq(orange, ["Upgrades", "Twin Claw ×2: +2 targets", "Quick Claw ×1: -12% cooldown"])


func test_a_long_tab_scrolls_to_keep_the_selection_visible() -> void:
	var book := _book()
	var skills := book.defs.duplicate(true)
	var cards: Array = _pool().cards.duplicate(true)
	for i in 6:
		var key := "extra_%d" % i
		skills[key] = {"skill_id": 2001100 + i, "book": "200", "job": 200, "kind": "passive", "damage": "none",
			"name": "Extra %d" % i, "ranks": [1]}
		cards.append({"id": key + "_new", "kind": "skill_new", "skill": key, "name": key, "max_rank": 1})
	book = SkillBook.from_data({"skills": skills}, book.skill_imgs)
	var pool := UpgradePool.from_data({"cards": cards})
	var m := SkillWindowModel.new(book, pool, Loadout.new(book), _jobs(), 200, SkillText.new(book, STRINGS))
	var w := SkillWindow.new(m)
	assert_eq(m.tabs[0].rows.size(), 9)
	assert_eq(w.scroll, 0)
	for i in 8:
		w.handle_key(_key(KEY_DOWN))
	assert_eq(w.selected, 7)
	assert_eq(w.scroll, 7 - SkillWindow.VISIBLE_ROWS + 1, "scrolled so the selected row is the last one shown")
	for i in 7:
		w.handle_key(_key(KEY_UP))
	assert_eq(w.selected, 0)
	assert_eq(w.scroll, 0, "scrolled back up")
	w.free()


func test_the_tab_cells_touch_and_a_click_anywhere_in_one_picks_it() -> void:
	var w := SkillWindow.new(_model(220, _magician_loadout(_book())))
	# Spec #225 and #284: I / II, no Beginner or star tab.
	assert_eq(w.model.tabs.size(), 2, "two job tabs")
	for i in 2:
		var r := w.tab_rect(i)
		if i > 0:
			assert_eq(r.position.x, w.tab_rect(i - 1).end.x, "tab %d starts where tab %d ends (the drawn shapes)" % [i, i - 1])
		assert_eq(r.position.y, 23.0, "the shapes start at the strip's top row")
		for at: Vector2 in [r.position + Vector2(0.5, 0.5), r.get_center(), r.end - Vector2(0.5, 0.5)]:
			w.select_tab((i + 1) % 2)
			var click := InputEventMouseButton.new()
			click.button_index = MOUSE_BUTTON_LEFT
			click.pressed = true
			click.position = at
			w._window_gui_input(click, at)
			assert_eq(w.tab, i, "a click at %s picks tab %d" % [at, i])
	w.free()
