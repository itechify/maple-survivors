extends TestCase
## Fire/Poison attacks through real loadout, card and projectile interfaces, with local synthetic WZ nodes.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(element_attr: String = "") -> RunWorld:
	var data := RF.quiet_data()
	# Raw canonical behaviour probes use an explicit identity mapping, independent of survivor rank compression.
	data.skills.skills.poison_breath.ranks = range(1, 31)
	var setup := RF.setup("quiet", 55, data)
	# Synthetic boundary levels exercise changing MP, mastery, poison chance and duration without shared fixtures.
	setup.skill_imgs["210"].skill["2101005"] = {"elemAttr": "s", "level": {
		"1": {"mpCon": 10.0, "mad": 12.0, "mastery": 1.0, "prop": 31.0, "time": 4.0},
		"16": {"mpCon": 20.0, "mad": 42.0, "mastery": 6.0, "prop": 46.0, "time": 24.0},
		"29": {"mpCon": 20.0, "mad": 68.0, "mastery": 10.0, "prop": 59.0, "time": 58.0},
		"30": {"mpCon": 20.0, "mad": 70.0, "mastery": 10.0, "prop": 60.0, "time": 40.0},
	}}
	setup.mob_imgs[1110100].info.elemAttr = element_attr
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	RF.as_job(w, 210)
	w.loadout.set_caster(100.0, 0.0, 30)
	return w


func _target(w: RunWorld) -> int:
	var m := RF.put_mob(w, 1110100, 350, 195, 10000.0)
	w.swarm.mob_kind(m).move_speed = 0.0
	w.swarm.mob_kind(m).mdd = 0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _one_cast(w: RunWorld) -> Array:
	w.drain_events()
	w.runner.step(DT, w)
	# Let only that cast travel: fixed ticks, no further automatic casts or unrelated skill RNG.
	w.loadout.order.clear()
	for tick in 30:
		w.step(DT, MoveInput.new())
	return w.drain_events()


func test_poison_breath_rank_resolves_canonical_damage_at_projectile_impact() -> void:
	# Independently worked magic ranges with INT=100, MATK=0, at canonical boundary levels.
	for example: Array in [[1, 10, 15.4, 50.0], [16, 20, 85.4, 175.0],
			[29, 20, 179.0666667, 283.3333333], [30, 20, 184.3333333, 291.6666667]]:
		var w := _world()
		assert_true(w.learn_skill("poison_breath"), "Poison Breath is learnable")
		if not w.loadout.has("poison_breath"):
			return
		w.loadout.set_rank("poison_breath", example[0])
		w.loadout.set_caster(100.0, 0.0, 30)
		var st := w.loadout.stats("poison_breath")
		assert_eq(st.level, example[0])
		assert_eq(st.element, "s", "element comes from canonical skill node")
		assert_near(st.damage_min, example[2], 1e-4)
		assert_near(st.damage_max, example[3], 1e-4)
		var m := _target(w)
		var events := _one_cast(w)
		var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
		assert_eq(hits.size(), 1, "one projectile line")
		if hits.size() == 1:
			assert_eq(hits[0].mob, m)
			assert_eq(hits[0].skill, "poison_breath")
			assert_between(hits[0].damage, roundi(example[2]), roundi(example[3]))
		assert_true(w.warnings.is_empty())


func test_seeded_poison_proc_frequency_duration_and_projectile_cast_level() -> void:
	var observations: Array = []
	for example: Array in [[1, 4.0, 260, 360], [30, 40.0, 540, 660]]:
		for repeat in 2:
			var w := _world()
			w.learn_skill("poison_breath")
			w.loadout.set_rank("poison_breath", example[0])
			var st := w.loadout.stats("poison_breath")
			var m := _target(w)
			w.loadout.order.clear()
			# Impacts must retain their launch level even when the learned rank changes in flight.
			w.loadout.set_rank("poison_breath", 16)
			w.drain_events()
			for line in 1000:
				w.projectiles.spawn({"x": w.swarm.x[m], "y": w.mob_center(m).y,
					"dmg_min": st.damage_min, "dmg_max": st.damage_max, "magic": true,
					"element": st.element, "skill": "poison_breath", "level": st.level})
				w.step(DT, MoveInput.new())
			var applied := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied")
			assert_between(applied.size(), example[2], example[3], "canonical prop over 1000 seeded impacts")
			assert_true(w.swarm.status_time(m, MobSwarm.POISON) > float(example[1]) - 1.0)
			assert_true(w.swarm.status_time(m, MobSwarm.POISON) <= float(example[1]))
			observations.append(applied.size())
	assert_eq(observations[0], observations[1], "31% proc trace reproduces with the same seed")
	assert_eq(observations[2], observations[3], "60% proc trace reproduces with the same seed")


func test_seeded_fire_arrow_projectile_applies_canonical_fire_weakness() -> void:
	var damage: Array = []
	for attr: String in ["", "F3"]:
		var w := _world(attr)
		w.learn_skill("fire_arrow")
		w.loadout.set_caster(100.0, 0.0, 30)
		assert_eq(w.loadout.stats("fire_arrow").element, "f")
		_target(w)
		var hits := _one_cast(w).filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
		assert_eq(hits.size(), 1)
		if hits.size() == 1:
			damage.append(int(hits[0].damage))
	if damage.size() == 2:
		assert_near(float(damage[1]), float(damage[0]) * 1.5, 1.0, "same roll, weakness x1.5 before rounding")



func test_pool_cards_learning_rank_caps_power_flags_and_bot_scores() -> void:
	var w := _world()
	w.book.def("poison_breath").ranks = [4,8,12,15,19,23,27,30]
	w.set_job(212)
	for key: String in ["fire_arrow", "poison_breath"]:
		assert_has(w.upgrades.eligible(w), key + "_new")
		assert_eq(BotInput.card_score(w, {"id": key + "_new"}), 100.0)
		assert_eq(w.upgrades.apply(key + "_new", w, "legendary"), 1)
		assert_eq(w.loadout.rank(key), 1)
		for consumed in range(1, 8):
			assert_eq(w.upgrades.apply(key + "_rank", w, "legendary"), consumed)
		assert_eq(w.loadout.rank(key), 8)
		assert_eq(w.loadout.level(key), 30)
		assert_true(w.upgrades.is_eligible(w.upgrades.card(key + "_rank"), w), "Mastery")
		assert_false(w.upgrades.is_eligible(w.upgrades.card(key + "_new"), w))


func test_cached_fire_poison_levels_visuals_and_sounds() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"210": lib.img("Skill.wz/210.img").root})
	var lo := Loadout.new(book)
	lo.set_caster(100.0, 0.0, 30)
	for key: String in ["fire_arrow", "poison_breath"]:
		lo.add_skill(key)
		assert_eq(book.max_level(key), 30)
		for rank in range(1, 9):
			lo.set_rank(key, rank)
			var st := lo.stats(key)
			assert_eq(st.level, [4,8,12,15,19,23,27,30][rank - 1])
		for field: String in ["ball", "hit", "effect"]:
			assert_true(lib.anim(String(lo.stats(key)[field])).frames.size() > 0, key + " " + field)
		for path: String in book.def(key).sounds.values():
			if path != "":
				assert_true(lib.sound(path) != null, path)
	assert_eq(int(book.canonical("poison_breath", 1, "mad")), 12)
	assert_eq(int(book.canonical("poison_breath", 30, "mad")), 70)
	assert_eq(int(book.canonical("poison_breath", 29, "time")), 58, "unusual canonical value stays unchanged")
	assert_true(lib.missing.is_empty(), "cache has all F/P assets: %s" % [lib.missing])
	lib.free()
