extends TestCase
## Corsair Dash (spec #384 C3 #387, CS-2, CS-3): the shared Pirate-book `dash` (WZ 5001005) as 522's `mobility_skill`. The definition
## stays in `skills/pirate.json` and is Buccaneer's too, so it is not edited here (it was made `slot: mobility` by B5 #417 and keeps
## its ten explicit `ranks`: rank N reads WZ level N, GAME_DESIGN 7.120.15); these tests run it on a job-522 world. Seeded synthetic
## worlds, fixed 1/60 ticks; the last test reads the real asset cache and SKIPs without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const GUN := 1492000
## Skill.wz/500.img skill 5001005 levels 1-10 as [speed x, jump y, time].
const TABLE := [[12, 1, 4], [14, 2, 4], [16, 3, 8], [18, 4, 8], [20, 5, 12], [22, 6, 12], [24, 7, 16], [26, 8, 16], [28, 9, 20], [30, 10, 20]]
## [round level, rank]: the shared balance.mobility_rank_levels rule (rank N at Lv 2N, rank 1 at Lv1), clamped to the ten ranks.
const BY_LEVEL := [[1, 1], [4, 2], [6, 3], [8, 4], [10, 5], [12, 6], [14, 7], [16, 8], [18, 9], [20, 10], [40, 10]]


## A Corsair (522, playable in the data copy) with a gun on a flat map at x = 400; Double Shot in slot 1 and Dash on its key.
func _world(p_seed := 387) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["522"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({GUN: {"incPAD": 13, "attackSpeed": 5, "tuc": 7}}, true)
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 2000, "y2": 0}])
	setup["job"] = 522
	var w := RunWorld.new(setup)
	RF.place_player(w, 400, 0)
	w.drain_events()
	return w


## Gains levels, then answers each queued level-up window the way a player would (the sim holds while one is open).
func _level_to(w: RunWorld, level: int) -> void:
	while int(w.player_state.level) < level:
		w._gain_exp(w.progression.exp_to_next())
	for i in 64:
		if w.state == RunWorld.CHOOSING_UPGRADE:
			RF.auto_choose(w)
		elif w.progression.has_pending():
			w.step(DT, MoveInput.new())
		else:
			break


func _press(w: RunWorld) -> void:
	var input := MoveInput.new()
	input.press_skill("dash")
	w.step(DT, input)


func _set_hp(w: RunWorld, fraction: float) -> void:
	w._hp = w._max_hp * fraction
	w._write_player_state(0.0)


func _types(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return e.type)


# --- Data -------------------------------------------------------------------------------------------------------

func test_dash_is_the_corsairs_mobility_skill_and_stays_in_the_pirate_file() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	assert_eq(jobs.mobility_skill(522), "dash")
	assert_eq(jobs.mobility_skill(512), "dash", "Buccaneer shares the one definition")
	var holders: Array = []
	for line: String in DataRepo.lines():
		var f: Variant = data.get("skills_" + line)
		if f is Dictionary and (f.get("skills", {}) as Dictionary).has("dash"):
			holders.append(line)
	assert_eq(holders.size() + (1 if data.skills.skills.has("dash") else 0), 1, "defined once (a duplicate key is a load error)")
	assert_eq(String(data.skills.skills.dash.slot), "mobility")
	assert_eq(String(data.skills.skills.dash.cast.rule), "manual")


func test_rank_levels_for_ten_level_skills_exists_exactly_once() -> void:
	var text := FileAccess.get_file_as_string("res://data/survivor/skills.json")
	assert_eq(text.count("\"rank_levels\""), 1, "one rank_levels table in the shared defaults")
	var table: Dictionary = DataRepo.load_all().skills.rank_levels
	assert_eq((table["10"] as Array).map(func(v: Variant) -> int: return int(v)), [2, 3, 4, 5, 7, 8, 9, 10])
	var tens := 0
	for key: String in table:
		tens += 1 if key == "10" else 0
	assert_eq(tens, 1)
	for line: String in DataRepo.lines():
		var raw := FileAccess.get_file_as_string("res://data/survivor/skills/%s.json" % line)
		assert_false(raw.contains("\"rank_levels\": {"), "%s.json adds no rank_levels table of its own" % line)


func test_dash_has_no_card_in_any_card_file_and_is_never_eligible() -> void:
	var data := DataRepo.load_all()
	var cards: Array = data.upgrades.cards.filter(func(c: Dictionary) -> bool: return String(c.get("skill", "")) == "dash")
	assert_eq(cards, [], "a mobility skill is never a card")
	assert_false(data.upgrades.cards.any(func(c: Dictionary) -> bool: return String(c.id).begins_with("dash_")))


# --- Behaviour on a Corsair ---------------------------------------------------------------------------------------

func test_a_corsair_learns_dash_at_start_on_the_mobility_slot_and_not_an_active_one() -> void:
	var w := _world()
	assert_eq(w.book.slot("dash"), "mobility")
	assert_true(w.loadout.has("dash"), "learned at round start from the job's mobility_skill")
	assert_eq(String(w.loadout.order[0]), "double_shot", "slot 1 is Double Shot")
	assert_eq(w.loadout.slot_count("active"), 1, "Dash takes none of the six active slots")
	assert_eq(w.loadout.slot_count("passive"), 0)
	assert_eq(w.loadout.slot_limit("mobility"), 0, "mobility has no track to fill")
	assert_eq(Array(w.jobs.start_skills(522)), ["double_shot", "dash"])


func test_a_corsair_round_never_offers_dash_as_a_card_or_learns_it_twice() -> void:
	var w := _world()
	for level in range(1, 21):
		_level_to(w, level)
		for id: String in w.upgrades.eligible(w):
			assert_ne(String(w.upgrades.card(id).get("skill", "")), "dash", "no Dash card offered at Lv%d (%s)" % [level, id])
	assert_eq(w.loadout.order.count("dash"), 1)
	assert_false(w.learn_skill("dash"), "owned: a second learn is refused")
	assert_false(w.loadout.order.filter(func(k: String) -> bool: return w.book.slot(k) == "active").has("dash"))


func test_dash_is_never_in_the_corsair_pool() -> void:
	var data := DataRepo.load_all()
	assert_false((data.jobs_survivor.jobs["522"].skill_pool as Array).has("dash"))


func test_dash_ranks_with_the_round_level_through_the_shared_mobility_rule() -> void:
	var w := _world()
	for row: Array in BY_LEVEL:
		_level_to(w, int(row[0]))
		var rank := int(row[1])
		assert_eq(w.loadout.rank("dash"), rank, "Lv%d rank" % int(row[0]))
		var want: Array = TABLE[rank - 1]
		var st := w.loadout.stats("dash", rank)
		assert_eq(st.buff_effects.speed, float(want[0]), "Lv%d speed" % int(row[0]))
		assert_eq(st.buff_effects.jump, float(want[1]), "Lv%d jump" % int(row[0]))
		assert_eq(st.duration, float(want[2]), "Lv%d duration" % int(row[0]))


func test_the_rank_table_is_the_shared_balance_rule_with_no_corsair_row() -> void:
	var w := _world()
	var rule: Dictionary = w.balance.mobility_rank_levels
	assert_eq(int(rule["1"]), 1)
	assert_eq(int(rule["4"]), 2)
	assert_eq(int(rule["16"]), 8)
	assert_false(DataRepo.load_all().balance.has("mobility_rank_levels_522"))
	assert_eq(w.book.max_rank("dash"), 10, "clamped to the shared definition's ten ranks")


func test_the_other_mobility_skills_rank_as_before() -> void:
	var f_p := RF.quiet_world()
	assert_eq(f_p.jobs.mobility_skill(f_p.job_id()), "teleport_fp")
	assert_false(f_p.loadout.has("dash"), "F/P learns Teleport, never Dash")
	_level_to(f_p, 16)
	assert_eq(f_p.loadout.rank("teleport_fp"), 8, "Teleport: Lv16 -> rank 8, unchanged")


func test_a_corsair_presses_dash_on_its_key_and_the_buff_blocks_a_recast_until_it_ends() -> void:
	var w := _world()
	_press(w)
	assert_true(w.buffs.has("dash"), "the key casts it from Lv1")
	assert_near(float(w.runner.cooldown_totals.dash), 4.0, 1e-6, "the cooldown is the 4 s duration")
	_press(w)
	assert_eq(_types(w.drain_events()).count("buff_cast"), 1, "a press while it runs casts nothing")
	var ticks := 2
	while w.buffs.has("dash") and ticks < 600:
		w.step(DT, MoveInput.new())
		ticks += 1
	assert_true(ticks >= 239 and ticks <= 242, "4 s at rank 1: %d ticks" % ticks)
	_press(w)
	assert_true(w.buffs.has("dash"), "ready again once it ended")


func test_a_corsair_dash_moves_speed_and_jump_within_the_caps_and_returns_after() -> void:
	var w := _world()
	_level_to(w, 20)
	w._equipment_speed = 25.0
	w._equipment_jump = 20.0
	_press(w)
	assert_eq(w.player.speed_stat, 140, "100 + 25 + 30 is capped at the v83 140")
	assert_eq(w.player.jump_stat, 123, "100 + 20 + 10 is capped at the v83 123")
	for i in 1300:
		w.step(DT, MoveInput.new())
	assert_false(w.buffs.has("dash"))
	assert_eq(w.player.speed_stat, 125, "back to the equipment's speed")
	assert_eq(w.player.jump_stat, 120, "back to the equipment's jump")


func test_a_corsair_dash_shows_its_key_caption_and_countdown_and_is_listed_in_key_config() -> void:
	var scene := RunScene.new()
	scene.world = _world()
	assert_eq(scene.world.manual_skill_keys().map(func(k: Dictionary) -> String: return String(k.action)), ["dash"],
		"Key Config lists Dash and nothing else")
	var row: Dictionary = scene.run_info().skills.back()
	assert_eq(row.key_label, "X")
	_press(scene.world)
	row = scene.run_info().skills.back()
	assert_near(row.cooldown_left, 4.0, 0.05, "the icon counts the buff down")
	assert_eq(scene.run_info().movement_skill.action, "dash", "the quick slot's movement skill")
	scene.free()


func test_the_corsair_bot_presses_dash_when_surrounded_or_hurt_with_a_mob_close() -> void:
	var w := _world()
	RF.put_mob(w, 100100, 400 + 100, 0, 100000)
	RF.put_mob(w, 100100, 400 + 60, 0, 100000)
	RF.put_mob(w, 100100, 400 - 100, 0, 100000)
	assert_true(BotInput.decide(w, {}).skill_pressed("dash"), "three mobs within 120 px surround it")
	var hurt := _world()
	_set_hp(hurt, 0.4)
	assert_false(BotInput.decide(hurt, {}).skill_pressed("dash"), "hurt but nothing near: no dash")
	RF.put_mob(hurt, 100100, 400 + 100, 0, 100000)
	assert_true(BotInput.decide(hurt, {}).skill_pressed("dash"), "hurt with a mob inside the flee distance")
	var healthy := _world()
	RF.put_mob(healthy, 100100, 400 + 100, 0, 100000)
	assert_false(BotInput.decide(healthy, {}).skill_pressed("dash"), "healthy with one mob close: no dash")


func test_the_buccaneer_dash_is_unchanged_by_the_corsair_job() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	var setup := RF.setup("quiet", 387, data)
	setup["job"] = 512
	var b := RunWorld.new(setup)
	_level_to(b, 8)
	assert_eq(b.loadout.rank("dash"), 4, "Lv8 -> rank 4 (+18, +4, 8 s) exactly as B5 pinned")
	var c := _world()
	_level_to(c, 8)
	assert_eq(c.loadout.rank("dash"), b.loadout.rank("dash"), "the same rule and the same definition for both jobs")


# --- Real cache ---------------------------------------------------------------------------------------------------

func test_real_cache_a_corsair_dash_ranks_through_the_round_level_to_each_wz_row_with_art_and_sound() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/500.img")
	assert_true(img != null, "the Pirate manifest fragment is imported")
	if img == null:
		lib.free()
		return
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["522"]["playable"] = true
	var setup := RF.setup("quiet", 387, data)
	setup.skill_imgs["500"] = img.root
	setup["job"] = 522
	var w := RunWorld.new(setup)
	for row: Array in BY_LEVEL:
		_level_to(w, int(row[0]))
		var rank := int(row[1])
		assert_eq(w.loadout.rank("dash"), rank, "Lv%d rank" % int(row[0]))
		var want: Array = TABLE[rank - 1]
		var st := w.loadout.stats("dash", rank)
		assert_eq(st.buff_effects.speed, float(want[0]), "rank %d speed" % rank)
		assert_eq(st.buff_effects.jump, float(want[1]), "rank %d jump" % rank)
		assert_eq(st.duration, float(want[2]), "rank %d duration" % rank)
	assert_eq(w.book.slot("dash"), "mobility")
	assert_false(lib.anim("Skill.wz/500.img/skill/5001005/effect").is_empty(), "the cast effect art")
	assert_true(lib.sound(w.book.def("dash").sounds.use) != null, "the use sound")
	assert_eq(Array(lib.missing), [])
	lib.free()
