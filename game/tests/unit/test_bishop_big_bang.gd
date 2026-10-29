extends TestCase
## Bishop Big Bang (spec #372, BS6 #378, I5's skill template): `big_bang_bishop` is exactly the three-line template over F/P's
## `big_bang`. The resolved definition equals the parent's except its identity and the rewritten paths, a 232 cast resolves like
## the F/P cast on identical data, its WZ numbers come from book 232, the rarity lists are inherited and it never depends on
## `big_bang_il`. Synthetic casts at the RunWorld boundary; the real-cache half is in test_bishop_genesis_cache.gd.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BG := preload("res://tests/fixtures/bishop_genesis_fixtures.gd")
const IlBigBang := preload("res://tests/unit/test_il_big_bang.gd")
const DT := 1.0 / 60.0


## A world with a 212 book and a 232 book; `mad`/`attack_count` apply to both unless `fp_mad` differs (book 212 keeps 120, one line).
func _world(key: String, bishop_mad: float = 120.0, bishop_attack_count: float = 1.0) -> RunWorld:
	var setup := RF.setup("quiet", 378, RF.quiet_data())
	setup.skill_imgs["212"] = {"skill": {"2121001": {"level": IlBigBang.levels(120.0, 1.0)}}}
	setup.skill_imgs["232"] = {"skill": {"2321001": {"level": IlBigBang.levels(bishop_mad, bishop_attack_count)}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_caster(100.0, 0.0, 30)
	return w


func _mob(w: RunWorld, x: float) -> int:
	var m := RF.put_mob(w, 1110100, x, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.swarm.mob_kind(m).move_speed = 0.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


## Casts, runs the 2.5 s charge and release; returns the mob_hit events.
func _release(w: RunWorld) -> Array:
	w.runner.step(DT, w)
	w.loadout.order.clear()
	for tick in 150:
		w.runner.tick_cooldowns(DT, w)
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func test_the_resolved_child_equals_the_parent_except_identity_and_rewritten_paths() -> void:
	var book := SkillBook.from_data(DataRepo.load_all().skills, {})
	var parent := book.def("big_bang")
	var child := book.def("big_bang_bishop")
	assert_eq(int(child.skill_id), 2321001)
	assert_eq(String(child.book), "232")
	assert_eq(int(child.job), 232)
	# The expected child, derived independently: the parent as text with the two path prefixes replaced.
	var text := JSON.stringify(parent)
	text = text.replace("Skill.wz/212.img/skill/2121001", "Skill.wz/232.img/skill/2321001")
	text = text.replace("Sound.wz/Skill.img/2121001", "Sound.wz/Skill.img/2321001")
	var expected: Dictionary = JSON.parse_string(text)
	var actual := child.duplicate(true)
	for k: String in ["skill_id", "book", "job", "extends"]:
		expected.erase(k)
		actual.erase(k)
	for d: Dictionary in [actual, expected]:
		for k: String in d.keys():
			if k.begins_with("_"):
				d.erase(k)
	# JSON round trips turn vectors/ints into floats; compare as text.
	assert_eq(JSON.stringify(actual), JSON.stringify(expected))
	assert_eq(String(child.effect), "Skill.wz/232.img/skill/2321001/keydown")
	assert_eq(child.release_visuals, ["Skill.wz/232.img/skill/2321001/special/0"])
	assert_eq(String(child.pending.effect), "Skill.wz/232.img/skill/2321001/effect")
	assert_eq(String(child.sounds.use), "Sound.wz/Skill.img/2321001/Use")
	assert_eq(String(child.sounds.loop), "Sound.wz/Skill.img/2321001/Loop")
	assert_eq(String(child.icon), "Skill.wz/232.img/skill/2321001/icon")
	assert_false(JSON.stringify(actual).contains("212.img") or JSON.stringify(actual).contains("2121001"), "no F/P path is left")


func test_the_shipped_definition_is_exactly_the_three_line_template_over_the_parent() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var raw: Dictionary = skills.big_bang_bishop
	var keys := raw.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))
	keys.sort()
	assert_eq(keys, ["book", "extends", "job", "skill_id"])
	assert_eq(raw["extends"], "big_bang", "the parent, never big_bang_il")
	assert_eq(int(raw.skill_id), 2321001)
	assert_eq(String(raw.book), "232")
	assert_eq(int(raw.job), 232)
	assert_false(skills.big_bang.has("extends"), "F/P's Big Bang is the parent, untouched")
	assert_eq(SkillBook.from_data(DataRepo.load_all().skills, {}).def("big_bang").skill_id, 2121001)


func test_the_bishop_and_il_children_share_no_dependency() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var without_il := skills.duplicate()
	without_il.erase("big_bang_il")
	var errors := PackedStringArray()
	var resolved := SkillTemplate.resolve(without_il, errors)
	assert_true(resolved.has("big_bang_bishop"), "it resolves with the I/L child absent: %s" % [errors])
	var without_bishop := skills.duplicate()
	without_bishop.erase("big_bang_bishop")
	assert_true(SkillTemplate.resolve(without_bishop).has("big_bang_il"))


func test_a_232_cast_resolves_the_same_hits_as_the_f_p_cast_on_identical_data() -> void:
	var results: Array = []
	for key: String in ["big_bang", "big_bang_bishop"]:
		var w := _world(key)
		_mob(w, 150)
		_mob(w, 260)
		var damage := []
		for e: Dictionary in _release(w):
			damage.append([int(e.mob), int(e.damage)])
		results.append(damage)
	assert_eq(results[0].size(), 2, "one line on each of the two mobs")
	assert_eq(results[1], results[0])


func test_it_charges_for_the_inherited_1_08_seconds_and_strikes_the_inherited_box() -> void:
	var w := _world("big_bang_bishop")
	var inside := _mob(w, 420)  # 220 px right of the caster: inside (-250,-180)..(250,100)
	var outside := _mob(w, 480)  # 280 px: beyond the 250 px half-width
	w.runner.step(DT, w)
	w.loadout.order.clear()
	for tick in 60:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.swarm.hp[inside], 100000, "still charging at 1 s")
	for tick in 12:
		w.runner.tick_cooldowns(DT, w)
	assert_true(w.swarm.hp[inside] < 100000, "released after the one-loop charge")
	assert_eq(w.swarm.hp[outside], 100000)
	var d := w.book.def("big_bang_bishop")
	assert_near(float(d.cooldown), 2.8)
	assert_eq(String(d.action), String(w.book.def("big_bang").action), "the stance is inherited")


func test_its_numbers_come_from_book_232_not_from_the_parent_book() -> void:
	var fp := _world("big_bang")
	var bishop := _world("big_bang_bishop", 360.0, 3.0)  # book 232 differs: triple lines, 3x the magic attack
	_mob(fp, 150)
	_mob(bishop, 150)
	var fp_hits := _release(fp)
	var bishop_hits := _release(bishop)
	assert_eq(fp_hits.size(), 1)
	assert_eq(bishop_hits.size(), 3, "attackCount 3 comes from 232.img")
	var fp_total := 0
	for e: Dictionary in fp_hits:
		fp_total += int(e.damage)
	var bishop_total := 0
	for e: Dictionary in bishop_hits:
		bishop_total += int(e.damage)
	assert_true(bishop_total > fp_total * 6, "mad 360 over three lines against mad 120 over one: %d vs %d" % [bishop_total, fp_total])


func test_the_inherited_rarity_lists_resolve_for_job_232() -> void:
	var w := BG.world("big_bang_bishop")
	var bonuses: Dictionary = w.book.def("big_bang_bishop").rarity_bonuses
	var wanted := {"rare": "power", "epic": "area", "unique": "echo", "legendary": "echo"}
	for tier: String in wanted:
		assert_eq(bonuses[tier].size(), 1, tier)
		assert_eq(String(bonuses[tier][0].id), wanted[tier], tier)
	assert_eq(bonuses, w.book.def("big_bang").rarity_bonuses, "the same lists as F/P's")

