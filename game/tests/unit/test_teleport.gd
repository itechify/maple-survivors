extends TestCase
## Teleport destination queries and manual casts on seeded synthetic worlds.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(key := "teleport_fp", job := 210, upper_y := -120) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 60, data)
	setup.map_img = RF.map_from_segments([
		{"x1": 0, "y1": 0, "x2": 1000, "y2": 0},
		{"x1": 0, "y1": upper_y, "x2": 1000, "y2": upper_y}])
	var id := 2301001 if job == 230 else job * 10000 + 1002
	setup.skill_imgs[str(job)] = {"skill": {str(id): {"level": {
		"1": {"mpCon": 60, "range": 130}, "2": {"mpCon": 57, "range": 131},
		"20": {"mpCon": 13, "range": 150}}}}}
	var w := RunWorld.new(setup)
	w.change_job(job)
	w.loadout.add_skill(key)
	w.player.place(Vector2(400, 0), w.fhm)
	w.drain_events()
	return w


func test_manual_horizontal_cast_emits_both_positions() -> void:
	var w := _world()
	var input := MoveInput.new()
	input.press_skill("teleport")
	w.step(DT, input)
	assert_eq(w.player.pos, Vector2(530, 0))
	var phases: Array = []
	for event: Dictionary in w.drain_events():
		if event.type == "teleport":
			phases.append([event.phase, event.pos])
	assert_eq(phases, [["departure", Vector2(400, 0)], ["arrival", Vector2(530, 0)]])


func test_key_binding_and_hud_cooldown_follow_the_world() -> void:
	var key := InputEventKey.new()
	key.physical_keycode = KEY_X
	key.pressed = true
	assert_true(key.is_action_pressed("teleport"), "X binds the manual skill")
	var scene := RunScene.new()
	scene.world = _world()
	var row: Dictionary = scene.run_info().skills.back()
	assert_eq(row.key_label, "X")
	assert_false(row.has("mp_short"), "no MP wait (no MP, #285)")
	assert_eq(row.cooldown_left, 0.0)
	var input := MoveInput.new()
	input.press_skill("teleport")
	scene.world.step(DT, input)
	row = scene.run_info().skills.back()
	assert_near(row.cooldown_left, 0.3, 1e-6, "the HUD reads Teleport's repeat timer")
	assert_near(row.cooldown_total, 0.3, 1e-6)
	scene.free()


func test_real_cache_teleport_cost_range_and_sound() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var imgs := {}
	for book: String in ["210", "220", "230"]:
		imgs[book] = library.img("Skill.wz/%s.img" % book).root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	for key: String in ["teleport_fp", "teleport_il", "teleport_cleric"]:
		assert_eq(book.max_level(key), 20)
		assert_eq(book.canonical(key, 1, "mpCon"), 60.0)
		assert_eq(book.canonical(key, 20, "mpCon"), 13.0)
		assert_eq(book.canonical(key, 1, "range"), 130.0)
		assert_eq(book.canonical(key, 20, "range"), 150.0)
		assert_true(library.sound(String(book.def(key).sounds.use)) != null)
	assert_true(library.missing.is_empty(), str(library.missing))
	library.free()


func test_real_cache_teleport_effect_frames() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var effect := library.anim("Effect.wz/BasicEff.img/Teleport")
	assert_true(effect != null and not effect.is_empty(), "canonical Teleport effect is imported")
	if effect != null and not effect.is_empty():
		assert_eq(effect.frames.size(), 4)
		assert_near(effect.total, 0.32)
	assert_true(library.missing.is_empty(), str(library.missing))
	library.free()


func test_rank_card_previews_canonical_range() -> void:
	var w := _world()
	var card := w.upgrades.choice_card("teleport_fp_rank", w)
	assert_eq(card.skill_changes.get("range", {}), {"before": 130, "after": 131})
	assert_false(card.skill_changes.has("mpCon"), "no MP cost to preview")


func test_manual_rule_never_auto_casts_or_scores_as_an_attack() -> void:
	var w := _world()
	w.loadout.add_skill_mod("teleport_fp", "range", "add", 500)
	RF.put_mob(w, 100100, 500, 0, 100)
	# The starter attack takes the first ready slot; the next tick must still exclude Teleport.
	for tick in 2:
		w.step(DT, MoveInput.new())
	for event: Dictionary in w.drain_events():
		assert_false(event.type == "cast" and event.skill == "teleport_fp", "manual skill excluded from automatic scan")
	assert_near(BotInput.card_score(w, w.upgrades.card("teleport_fp_rank")), BotInput.SCORE_RANK_PASSIVE + BotInput.SCORE_JOB_BONUS)


func test_airborne_left_blink_and_out_of_range_vertical_are_atomic() -> void:
	var w := _world("teleport_fp", 210, -160)
	var input := MoveInput.new()
	input.press_skill("teleport")
	input.up = true
	w.step(DT, input)
	assert_eq(w.player.pos, Vector2(400, 0))
	w.player.place(Vector2(400, -40), w.fhm)
	input.up = false
	input.left = true
	w.step(DT, input)
	assert_eq(w.player.pos, Vector2(270, 0), "airborne left blink lands on the floor")
	assert_eq(w.player.facing, -1)


func test_horizontal_destination_uses_range_and_lands_on_slope() -> void:
	var map := FootholdMap.from_segments([{"x1": 0, "y1": 0, "x2": 400, "y2": 40}])
	var p := PlayerMotion.new()
	p.place(Vector2(100, 10), map)
	var dest := p.teleport_destination(Vector2.RIGHT, 130.0, map, Rect2())
	assert_eq(dest.pos, Vector2(230, 23))
	assert_eq(dest.fh, 0)
	assert_eq(p.pos, Vector2(100, 10), "query does not move the player")


func test_direction_restrictions_and_repeat_delay() -> void:
	for pair: Array in [["teleport_fp", 210], ["teleport_il", 220], ["teleport_cleric", 230]]:
		var w := _world(pair[0], pair[1])
		w.loadout.set_rank(pair[0], 20)
		var input := MoveInput.new()
		input.press_skill("teleport")
		input.up = true
		w.step(DT, input)
		assert_eq(w.player.pos, Vector2(400, -120))
		input.skills_pressed.erase("teleport")
		input.hold_skill("teleport")
		input.up = false
		for tick in 17:
			w.step(DT, input)
		assert_eq(w.player.pos, Vector2(400, -120), "held repeat waits 0.3 seconds")
		w.step(DT, input)
		assert_eq(w.player.pos, Vector2(550, -120))
	var w := _world()
	var input := MoveInput.new()
	input.press_skill("teleport")
	input.up = true
	w.player.place(Vector2(400, -120), w.fhm)
	w.step(DT, input)
	input.up = false
	for tick in 30: # past the repeat delay
		w.step(DT, MoveInput.new())
	w.player.ladder = 0
	w.player.state = PlayerMotion.ST_LADDER
	w.ladders = LadderSet.from_list([{"x": 400, "y1": -200, "y2": 0}])
	var on_ladder := w.player.pos
	w.step(DT, input)
	assert_eq(w.player.pos.x, on_ladder.x, "climbing does not teleport")
	var unlearned := RF.quiet_world(400, 60)
	var at := unlearned.player.pos
	unlearned.step(DT, input)
	assert_eq(unlearned.player.pos, at, "unlearned key does nothing")


func test_bot_requests_teleport_when_cornered() -> void:
	var w := _world()
	w.player.place(Vector2(20, 0), w.fhm)
	RF.put_mob(w, 100100, 48, 0)
	var input := BotInput.decide(w, {})
	assert_true(input.skill_pressed("teleport"), "nearby threat and map edge prompt an escape")
	assert_true(input.right, "escape toward map interior")
	w.step(DT, input)
	assert_eq(w.player.pos, Vector2(150, 0))


func test_sloped_wall_stops_at_wall_instead_of_cancelling_blink() -> void:
	var map := FootholdMap.from_segments([
		{"x1": 0, "y1": 0, "x2": 400, "y2": 40},
		{"x1": 200, "y1": 14, "x2": 200, "y2": 30}])
	var dest := map.teleport_destination(Vector2(100, 10), Vector2.RIGHT, 130, Rect2())
	assert_false(dest.is_empty())
	if not dest.is_empty():
		assert_near(dest.pos.x, 199.99, 0.001)
		assert_near(dest.pos.y, 19.999, 0.001)


func test_vertical_platforms_edges_walls_and_air() -> void:
	var map := FootholdMap.from_segments([
		{"x1": 0, "y1": 0, "x2": 400, "y2": 0},
		{"x1": 0, "y1": -120, "x2": 400, "y2": -120},
		{"x1": 0, "y1": 160, "x2": 400, "y2": 160},
		{"x1": 240, "y1": -100, "x2": 240, "y2": 0}])
	assert_eq(map.teleport_destination(Vector2(100, 0), Vector2.UP, 130, Rect2()).pos, Vector2(100, -120))
	assert_true(map.teleport_destination(Vector2(100, 0), Vector2.DOWN, 130, Rect2()).is_empty())
	assert_eq(map.teleport_destination(Vector2(100, -120), Vector2.DOWN, 130, Rect2()).pos, Vector2(100, 0))
	var wall := map.teleport_destination(Vector2(200, 0), Vector2.RIGHT, 130, Rect2())
	assert_near(wall.pos.x, 239.99, 0.001)
	assert_eq(map.teleport_destination(Vector2(100, 0), Vector2.LEFT, 130, Rect2()).pos, Vector2(0, 0))
	assert_eq(map.teleport_destination(Vector2(100, 0), Vector2.LEFT, 130, Rect2(20, -200, 350, 500)).pos, Vector2(20, 0))
	assert_eq(map.teleport_destination(Vector2(100, -40), Vector2.RIGHT, 130, Rect2()).pos, Vector2(230, 0))
	var p := PlayerMotion.new()
	p.ladder = 0
	assert_true(p.teleport_destination(Vector2.RIGHT, 130, map, Rect2()).is_empty())
