extends TestCase
## Dash 5001005 (#188): the Pirate's manual buff on its skill key. Seeded synthetic worlds with the Skill.wz table of
## Dash (level -> mpCon, speed x, jump y, time) copied out; one real-cache test checks that table against the
## imported Skill.wz/500.img. The bot's flee rule is tested on the same world.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Skill.wz/500.img skill 5001005 levels 1-10 as [mpCon, x (speed), y (jump), time].
const TABLE := [[14, 12, 1, 4], [13, 14, 2, 4], [12, 16, 3, 8], [11, 18, 4, 8], [10, 20, 5, 12], [9, 22, 6, 12],
	[8, 24, 7, 16], [7, 26, 8, 16], [6, 28, 9, 20], [5, 30, 10, 20]]
const INFO := {
	1482000: {"incPAD": 18, "attackSpeed": 5, "tuc": 7},
	1492000: {"incPAD": 13, "attackSpeed": 5, "tuc": 7},
}


func _world(mp := 200, skill := true) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = mp
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	var setup := RF.with_basic_attack(RF.setup("quiet", 188, data))
	setup.equipment_info.merge(INFO, true)
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 2000, "y2": 0}])
	var w := RunWorld.new(setup)
	RF.as_job(w, 500, "knuckle")
	w.heal_fraction("mp", 1.0)
	if skill:
		w.learn_skill("dash")
	RF.place_player(w, 400, 0)
	w.drain_events()
	return w


func _press(w: RunWorld) -> void:
	var input := MoveInput.new()
	input.press_skill("dash")
	w.step(DT, input)


func _types(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> String: return e.type)


func test_each_rank_resolves_the_skill_wz_speed_jump_duration_and_mp() -> void:
	var w := _world()
	assert_eq(w.book.max_rank("dash"), 10, "ten ranks, one per canonical level")
	assert_eq(w.book.max_level("dash"), 10)
	for rank in range(1, 11):
		var row: Array = TABLE[rank - 1]
		var st := w.loadout.stats("dash", rank)
		assert_eq(st.mp_cost, row[0], "rank %d MP" % rank)
		assert_eq(st.buff_effects.speed, float(row[1]), "rank %d speed" % rank)
		assert_eq(st.buff_effects.jump, float(row[2]), "rank %d jump" % rank)
		assert_eq(st.duration, float(row[3]), "rank %d duration" % rank)
		assert_eq(st.kind, "buff")
		assert_eq(st.cast_rule, "manual", "a manual skill: never auto-cast")


func test_pressing_the_key_starts_the_buff_pays_mp_and_raises_speed_and_jump() -> void:
	for rank in [1, 5, 10]:
		var w := _world()
		w.loadout.set_rank("dash", rank)
		var row: Array = TABLE[rank - 1]
		var before := int(w.player_state.mp)
		assert_eq(w.player.speed_stat, 100)
		_press(w)
		assert_true(w.buffs.has("dash"))
		assert_eq(int(w.player_state.mp), before - int(row[0]), "rank %d pays mpCon" % rank)
		assert_eq(w.player.speed_stat, 100 + int(row[1]), "rank %d speed" % rank)
		assert_eq(w.player.jump_stat, 100 + int(row[2]), "rank %d jump" % rank)
		assert_eq(w.buffs.active.dash.duration, float(row[3]))
		assert_eq(_types(w.drain_events()).filter(func(t: String) -> bool: return t in ["buff_cast", "cast"]),
			["buff_cast", "cast"], "one buff_cast and one cast event")


func test_the_buff_ends_after_its_time_and_the_key_casts_it_again() -> void:
	var w := _world()
	_press(w)
	var ticks := 0
	while w.buffs.has("dash") and ticks < 600:
		w.step(DT, MoveInput.new())
		ticks += 1
	assert_true(ticks >= 239 and ticks <= 242, "4 s at rank 1: %d ticks" % ticks)
	w.step(DT, MoveInput.new())
	assert_eq(w.player.speed_stat, 100, "speed is back")
	assert_eq(w.player.jump_stat, 100, "jump is back")
	var mp := int(w.player_state.mp)
	_press(w)
	assert_true(w.buffs.has("dash"), "the key casts it again once it ended")
	assert_true(int(w.player_state.mp) <= mp - 13, "paid again: %d -> %d" % [mp, int(w.player_state.mp)])


func test_pressing_without_enough_mp_does_nothing() -> void:
	var w := _world()
	w.spend_mp(int(w.player_state.mp) - 13) # rank 1 costs 14
	assert_eq(int(w.player_state.mp), 13)
	_press(w)
	assert_false(w.buffs.has("dash"))
	assert_eq(int(w.player_state.mp), 13, "nothing was spent")
	assert_eq(w.player.speed_stat, 100)
	assert_eq(_types(w.drain_events()).filter(func(t: String) -> bool: return t in ["buff_cast", "cast", "mp_short"]), [],
		"no cast and no event")
	var short := w.skill_readiness("dash")
	assert_true(short.mp_short, "the HUD shows it waiting for MP")
	w.heal_fraction("mp", 1.0)
	assert_false(w.skill_readiness("dash").mp_short)
	_press(w)
	assert_true(w.buffs.has("dash"), "enough MP: it casts")


func test_a_press_while_running_costs_nothing_and_the_buff_is_never_auto_cast() -> void:
	var w := _world()
	for i in 300:
		w.step(DT, MoveInput.new())
	assert_false(w.buffs.has("dash"), "no key press: no cast")
	_press(w)
	var mp := int(w.player_state.mp)
	for i in 20:
		_press(w)
	assert_eq(int(w.player_state.mp), mp, "pressing while it runs spends nothing")
	assert_eq(_types(w.drain_events()).count("buff_cast"), 1)


func test_holding_the_key_casts_again_when_the_buff_ends() -> void:
	var w := _world()
	var casts := 0
	for i in 600:
		var input := MoveInput.new()
		input.hold_skill("dash")
		w.step(DT, input)
		casts += _types(w.drain_events()).count("buff_cast")
	assert_eq(casts, 3, "a rank 1 Dash lasts 4 s: three casts in 10 s of holding the key")


func test_only_the_owner_of_a_skill_key_can_press_it() -> void:
	var plain := _world(200, false)
	_press(plain)
	assert_false(plain.buffs.has("dash"), "an unlearned Dash does nothing")
	var w := _world()
	var input := MoveInput.new()
	input.press_skill("teleport")
	w.step(DT, input)
	assert_eq(w.player.pos.x, 400.0, "a Pirate has no Teleport to press")
	assert_eq(plain.manual_skill_keys(), [])
	var keys := w.manual_skill_keys()
	assert_eq(keys.size(), 1)
	assert_eq(keys[0].action, "dash")
	assert_eq(keys[0].name, "Dash")
	assert_eq(keys[0].icon, "Skill.wz/500.img/skill/5001005/icon")


func test_speed_and_jump_follow_the_movement_caps() -> void:
	var w := _world()
	w.loadout.set_rank("dash", 10)
	w._equipment_speed = 25.0
	w._equipment_jump = 20.0
	_press(w)
	assert_eq(w.player.speed_stat, 140, "100 + 25 + 30 is capped at the v83 140")
	assert_eq(w.player.jump_stat, 123, "100 + 20 + 10 is capped at the v83 123")


func test_dash_makes_the_character_run_faster() -> void:
	var slow := _world()
	var fast := _world()
	fast.loadout.set_rank("dash", 10)
	_press(fast)
	for i in 60:
		var input := MoveInput.make(false, true)
		slow.step(DT, input)
		fast.step(DT, MoveInput.make(false, true))
	assert_true(fast.player.pos.x - 400.0 > (slow.player.pos.x - 400.0) * 1.2,
		"%.0f px against %.0f px in a second" % [fast.player.pos.x - 400.0, slow.player.pos.x - 400.0])


func test_the_hud_row_carries_the_skill_key_caption() -> void:
	var scene := RunScene.new()
	scene.world = _world()
	var row: Dictionary = scene.run_info().skills.back()
	assert_eq(row.key_label, "X", "Dash's default key on its icon")
	assert_false(row.mp_short)
	_press(scene.world)
	row = scene.run_info().skills.back()
	assert_near(row.cooldown_left, 4.0, 0.05, "the icon counts the buff down")
	scene.free()


# --- Bot -------------------------------------------------------------------------------------------------------

func _bot_world() -> RunWorld:
	var w := _world()
	w.drain_events()
	return w


func _set_hp(w: RunWorld, fraction: float) -> void:
	w._hp = w._max_hp * fraction
	w._write_player_state(0.0)


func test_the_bot_dashes_when_surrounded() -> void:
	var w := _bot_world()
	assert_false(BotInput.decide(w, {}).skill_pressed("dash"), "no mobs: no dash")
	RF.put_mob(w, 100100, 400 + 100, 0, 100000)
	RF.put_mob(w, 100100, 400 - 100, 0, 100000)
	assert_false(BotInput.decide(w, {}).skill_pressed("dash"), "two close mobs at full HP: not surrounded")
	RF.put_mob(w, 100100, 400 + 60, 0, 100000)
	var input := BotInput.decide(w, {})
	assert_true(input.skill_pressed("dash"), "three mobs within 120 px surround it")
	w.step(DT, input)
	assert_true(w.buffs.has("dash"), "and the press casts it")
	assert_false(BotInput.decide(w, {}).skill_pressed("dash"), "no second press while it runs")


func test_the_bot_dashes_when_hurt_with_a_mob_close_and_not_otherwise() -> void:
	var w := _bot_world()
	_set_hp(w, 0.4)
	assert_false(BotInput.decide(w, {}).skill_pressed("dash"), "hurt but nothing near: no dash")
	RF.put_mob(w, 100100, 400 + 100, 0, 100000)
	assert_true(BotInput.decide(w, {}).skill_pressed("dash"), "hurt with a mob inside the flee distance")
	_set_hp(w, 0.8)
	assert_false(BotInput.decide(w, {}).skill_pressed("dash"), "healthy with one mob close: no dash")
	_set_hp(w, 0.4)
	w.spend_mp(int(w.player_state.mp) - 13)
	assert_false(BotInput.decide(w, {}).skill_pressed("dash"), "it cannot pay")
	var far := _bot_world()
	_set_hp(far, 0.4)
	RF.put_mob(far, 100100, 400 + 400, 0, 100000)
	assert_false(BotInput.decide(far, {}).skill_pressed("dash"), "a mob far away is no reason to flee")


func test_the_bots_flee_rule_lives_in_the_skill_data() -> void:
	var manual: Dictionary = DataRepo.load_all().skills.skills.dash.manual
	assert_eq(manual.bot_flee_hp, 0.5)
	assert_eq(manual.bot_surround_count, 3)
	assert_eq(manual.bot_surround_distance, 120.0)
	var w := _bot_world()
	w.book.defs.dash.manual.bot_flee_hp = 0.9
	_set_hp(w, 0.8)
	RF.put_mob(w, 100100, 400 + 100, 0, 100000)
	assert_true(BotInput.decide(w, {}).skill_pressed("dash"), "the threshold is read from the data")


# --- Shipping data ---------------------------------------------------------------------------------------------

func test_the_shipping_data_defines_dash_and_its_cards() -> void:
	var data := DataRepo.load_all()
	var def: Dictionary = data.skills.skills.dash
	assert_eq(int(def.skill_id), 5001005)
	assert_eq(def.cast.rule, "manual")
	assert_eq(def.skill_key, "dash")
	assert_eq(def.kind, "buff")
	assert_eq((def.ranks as Array).size(), 10)
	assert_true(KeyBindings.SKILL_KEYS.has("dash"))
	for teleport: String in ["teleport_fp", "teleport_il", "teleport_cleric"]:
		assert_eq(data.skills.skills[teleport].skill_key, "teleport", teleport)
	assert_true(KeyBindings.SKILL_KEYS.has("teleport"))
	var cards: Array = data.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.get("skill", "") == "dash")
	assert_eq(cards.map(func(c: Dictionary) -> String: return c.id), ["dash_new", "dash_rank"])
	for card: Dictionary in cards:
		# A first-job skill: job 500, on offer to every job of the Pirate line (UpgradePool.on_line, #284).
		var jobs: Array = card.requires.jobs as Array
		assert_eq(jobs.map(func(j: Variant) -> int: return int(j)), [500], "the Pirate line only")
	assert_eq(cards[1].max_rank, 10)


func test_real_cache_dash_table_matches_skill_wz() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/500.img")
	assert_true(img != null, "import the Pirate manifest fragment")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"500": img.root})
	var loadout := Loadout.new(book)
	assert_eq(book.max_level("dash"), 10)
	for rank in range(1, 11):
		var row: Array = TABLE[rank - 1]
		var st := loadout.stats("dash", rank)
		assert_eq(st.mp_cost, row[0], "rank %d MP" % rank)
		assert_eq(st.buff_effects.speed, float(row[1]), "rank %d speed" % rank)
		assert_eq(st.buff_effects.jump, float(row[2]), "rank %d jump" % rank)
		assert_eq(st.duration, float(row[3]), "rank %d duration" % rank)
	assert_false(lib.anim("Skill.wz/500.img/skill/5001005/effect").is_empty(), "the cast effect art")
	assert_true(lib.sound(book.def("dash").sounds.use) != null, "the use sound")
	assert_eq(Array(lib.missing), [])
	lib.free()
