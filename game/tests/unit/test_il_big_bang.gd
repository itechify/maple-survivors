extends TestCase
## I/L Big Bang (spec #319 I10 #329, M19): `big_bang_il` is the three-line template over F/P's `big_bang`. The resolved
## definition equals the parent's except its identity and the rewritten paths, a 222 cast resolves like the F/P cast on
## identical data, and its WZ numbers come from book 222 (a synthetic book that differs from 212 proves the child reads its
## own). Synthetic casts at the RunWorld boundary; the real-cache half is in test_il_blizzard_big_bang_cache.gd.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


static func levels(mad: float, attack_count: float) -> Dictionary:
	var out := {}
	for lv in range(1, 31):
		out[str(lv)] = {"mad": mad, "mobCount": 6.0, "attackCount": attack_count, "mastery": 10.0}  # no lt/rb, as in the WZ: the survivor box applies
	return out


## A world with a 212 book and a 222 book; `mad`/`attack_count` apply to book 222 (212 keeps 120 and one line).
func _world(key: String, il_mad: float = 120.0, il_attack_count: float = 1.0) -> RunWorld:
	var setup := RF.setup("quiet", 329, RF.quiet_data())
	setup.skill_imgs["212"] = {"skill": {"2121001": {"level": levels(120.0, 1.0)}}}
	setup.skill_imgs["222"] = {"skill": {"2221001": {"level": levels(il_mad, il_attack_count)}}}
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
	var child := book.def("big_bang_il")
	assert_eq(int(child.skill_id), 2221001)
	assert_eq(String(child.book), "222")
	assert_eq(int(child.job), 222)
	# The expected child, derived independently: the parent as text with the two path prefixes replaced.
	var text := JSON.stringify(parent)
	text = text.replace("Skill.wz/212.img/skill/2121001", "Skill.wz/222.img/skill/2221001")
	text = text.replace("Sound.wz/Skill.img/2121001", "Sound.wz/Skill.img/2221001")
	var expected: Dictionary = JSON.parse_string(text)
	for k: String in ["skill_id", "book", "job"]:
		expected.erase(k)
	var actual := child.duplicate(true)
	for k: String in ["skill_id", "book", "job", "extends"]:
		actual.erase(k)
	for k: String in actual.keys():
		if k.begins_with("_"):
			actual.erase(k)
	for k: String in expected.keys():
		if k.begins_with("_"):
			expected.erase(k)
	# JSON round trips turn vectors/ints into floats; compare as text.
	assert_eq(JSON.stringify(actual), JSON.stringify(expected))
	assert_eq(String(child.effect), "Skill.wz/222.img/skill/2221001/keydown")
	assert_eq(child.release_visuals, ["Skill.wz/222.img/skill/2221001/special/0"])
	assert_eq(String(child.pending.effect), "Skill.wz/222.img/skill/2221001/effect")
	assert_eq(String(child.sounds.use), "Sound.wz/Skill.img/2221001/Use")
	assert_eq(String(child.sounds.loop), "Sound.wz/Skill.img/2221001/Loop")
	assert_eq(String(child.icon), "Skill.wz/222.img/skill/2221001/icon")


func test_the_shipped_definition_is_the_three_line_template_and_f_p_stays_unresolved_data() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var raw: Dictionary = skills.big_bang_il
	var keys := raw.keys().filter(func(k: String) -> bool: return not k.begins_with("_"))
	keys.sort()
	assert_eq(keys, ["book", "extends", "job", "skill_id"])
	assert_eq(raw["extends"], "big_bang")
	assert_false(skills.big_bang.has("extends"), "F/P's Big Bang is the parent, untouched")
	assert_eq(SkillBook.from_data(DataRepo.load_all().skills, {}).def("big_bang").skill_id, 2121001)


func test_a_222_cast_resolves_the_same_hits_as_the_f_p_cast_on_identical_data() -> void:
	var results: Array = []
	for key: String in ["big_bang", "big_bang_il"]:
		var w := _world(key)
		_mob(w, 150)
		_mob(w, 260)
		var hits := _release(w)
		var damage := []
		for e: Dictionary in hits:
			damage.append([int(e.mob), int(e.damage)])
		results.append(damage)
	assert_eq(results[0].size(), 2, "one line on each of the two mobs")
	assert_eq(results[1], results[0])


func test_it_charges_for_the_inherited_1_08_seconds_and_strikes_the_inherited_box() -> void:
	var w := _world("big_bang_il")
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
	assert_near(float(w.book.def("big_bang_il").cooldown), 2.8)


func test_its_numbers_come_from_book_222_not_from_the_parent_book() -> void:
	var fp := _world("big_bang")
	var il := _world("big_bang_il", 360.0, 3.0)  # book 222 differs: triple lines, 3x the magic attack
	_mob(fp, 150)
	_mob(il, 150)
	var fp_hits := _release(fp)
	var il_hits := _release(il)
	assert_eq(fp_hits.size(), 1)
	assert_eq(il_hits.size(), 3, "attackCount 3 comes from 222.img")
	var fp_total := 0
	for e: Dictionary in fp_hits:
		fp_total += int(e.damage)
	var il_total := 0
	for e: Dictionary in il_hits:
		il_total += int(e.damage)
	assert_true(il_total > fp_total * 6, "mad 360 over three lines against mad 120 over one: %d vs %d" % [il_total, fp_total])


func test_the_inherited_rarity_lists_resolve_for_job_222() -> void:
	var data := RF.quiet_data()
	var w := RunWorld.new(RF.setup("quiet", 329, data))
	w.set_job(222)
	var bonuses: Dictionary = w.book.def("big_bang_il").rarity_bonuses
	var wanted := {"rare": "power", "epic": "area", "unique": "echo", "legendary": "echo"}
	for tier: String in wanted:
		assert_eq(bonuses[tier].size(), 1, tier)
		assert_eq(String(bonuses[tier][0].id), wanted[tier], tier)
	assert_eq(String(bonuses.rare[0].effects[0].stat), "damage")
	assert_eq(String(bonuses.epic[0].effects[0].stat), "area")
	assert_eq(String(bonuses.unique[0].effects[0].stat), "attack_count")
	assert_eq(bonuses, w.book.def("big_bang").rarity_bonuses, "the same lists as F/P's")
