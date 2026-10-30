extends TestCase
## Flash Jump (spec #383 NL6 #405, M14, WZ 4111006, Night Lord): the manual air jump on the `flash_jump` skill key.
## Synthetic worlds with the real skill data and a Skill.wz-shaped node (only `mpCon` per level, like the real one); the
## real node is asserted in the real-cache test at the end.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "flash_jump"


## Skill.wz/411.img/skill/4111006 in the shape the book reads: 20 levels holding only `mpCon`, like the real node.
func _flash_img() -> Dictionary:
	var levels := {}
	for lv in range(1, 21):
		levels[str(lv)] = {"mpCon": float(60 - 3 * (lv - 1))}
	return {"icon": RF._canvas(32, 32), "level": levels}


## The quiet test data with Night Lord (412) playable (it ships unplayable until NL12).
static func _data() -> Dictionary:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["412"]["playable"] = true
	return data


## A Night Lord on a flat map 0..1000 (or `segments`) standing on the floor at x = `x`.
func _world(x := 400.0, segments: Array = []) -> RunWorld:
	var setup := RF.setup("quiet", 405, _data())
	setup.map_img = RF.map_from_segments(segments if not segments.is_empty()
		else [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	setup.skill_imgs["411"] = {"skill": {"4111006": _flash_img()}}
	setup["job"] = 412
	var w := RunWorld.new(setup)
	w.player.place(Vector2(x, 0), w.fhm)
	w.drain_events()
	return w


## Puts the character in the air above the floor with no velocity.
func _lift(w: RunWorld, x := 400.0, y := -200.0) -> void:
	w.player.place(Vector2(x, y), w.fhm)
	w.drain_events()


func _press(w: RunWorld, left := false, right := false, up := false, down := false) -> Array:
	var input := MoveInput.new()
	input.press_skill("flash_jump")
	input.left = left
	input.right = right
	input.up = up
	input.down = down
	w.step(DT, input)
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "flash_jump")


func _idle(w: RunWorld, ticks: int) -> void:
	for i in ticks:
		w.step(DT, MoveInput.new())
	w.drain_events()


# --- FlashJump arithmetic ----------------------------------------------------------------------------------------------

func test_distance_is_linear_from_the_first_to_the_last_rank() -> void:
	var table := [140.0, 280.0]
	assert_near(FlashJump.distance(table, 1, 20), 140.0, 1e-9)
	assert_near(FlashJump.distance(table, 20, 20), 280.0, 1e-9)
	assert_near(FlashJump.distance(table, 10, 20), 140.0 + 140.0 * 9.0 / 19.0, 1e-9)
	assert_near(FlashJump.distance(table, 0, 20), 140.0, 1e-9, "below rank 1 clamps")
	assert_near(FlashJump.distance(table, 99, 20), 280.0, 1e-9, "past the top rank clamps")
	assert_near(FlashJump.distance([200.0], 7, 20), 200.0, 1e-9, "one entry is constant")
	assert_near(FlashJump.distance(table, 3, 1), 140.0, 1e-9, "a one-rank skill reads the first entry")
	assert_eq(FlashJump.distance([], 5, 20), 0.0)


func test_side_is_the_held_arrow_else_the_facing() -> void:
	assert_eq(FlashJump.side(-1, 1), -1)
	assert_eq(FlashJump.side(1, -1), 1)
	assert_eq(FlashJump.side(0, -1), -1)
	assert_eq(FlashJump.side(0, 1), 1)


func test_admits_needs_a_free_character_and_no_repeat_delay() -> void:
	assert_true(FlashJump.admits(true, 0.0))
	assert_false(FlashJump.admits(false, 0.0))
	assert_false(FlashJump.admits(true, 0.1))


func test_the_trail_is_three_ghosts_from_the_start_never_on_the_arrival() -> void:
	var ghosts := FlashJump.trail(Vector2(100, -50), Vector2(400, -50))
	assert_eq(ghosts.size(), 3)
	assert_eq(ghosts[0].pos, Vector2(100, -50), "the first ghost stays where the flash began")
	assert_eq(ghosts[1].pos, Vector2(200, -50))
	assert_eq(ghosts[2].pos, Vector2(300, -50))
	assert_true(float(ghosts[0].alpha) > float(ghosts[1].alpha) and float(ghosts[1].alpha) > float(ghosts[2].alpha),
		"the older the brighter")


# --- Definition and learning -------------------------------------------------------------------------------------------

func test_learned_at_round_start_on_the_mobility_slot_outside_the_pool() -> void:
	var w := _world()
	assert_true(w.loadout.has(KEY), "Flash Jump is a start skill of the job")
	assert_eq(w.book.slot(KEY), "mobility")
	assert_eq(w.jobs.mobility_skill(412), KEY)
	assert_false(KEY in w.jobs.skill_pool(412), "never in the pool, so never offered as a card")
	assert_eq(w.loadout.rank(KEY), 1)
	assert_eq(w.skill_key_of(KEY), "flash_jump")
	assert_eq(w.flash_jump_skill(), KEY)
	assert_eq(w.book.skill_id(KEY), 4111006)


func test_the_card_draw_never_offers_flash_jump() -> void:
	var w := _world()
	for i in 60:
		for card: Dictionary in w.upgrades.roll_choices(w, w.card_rng, 3):
			assert_ne(String(card.get("skill", "")), KEY)


func test_a_job_without_flash_jump_ignores_the_key() -> void:
	var w := RF.quiet_world(400, 7)
	_lift(w)
	assert_eq(w.flash_jump_skill(), "")
	assert_true(_press(w, false, true).is_empty())
	assert_near(w.player.pos.x, 400.0, 1.0)


# --- The press: where it is allowed ------------------------------------------------------------------------------------

func test_refused_on_the_ground_with_nothing_spent() -> void:
	var w := _world()
	assert_true(_press(w).is_empty(), "no event on a floor")
	assert_eq(w.player.pos, Vector2(400, 0))
	assert_true(_press(w, false, true).is_empty(), "nor with an arrow held")
	assert_true(w.player.pos.x < 405.0, "the arrow only walks: %s" % w.player.pos)
	assert_eq(float(w.skill_readiness(KEY).left), 0.0, "no repeat delay was started")
	assert_false(w.player.flash_spent)


func test_refused_on_a_ladder_or_rope() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 400.0, "y2": 0.0},
		{"x1": 150.0, "y1": -120.0, "x2": 350.0, "y2": -120.0},
	])
	var l := LadderSet.from_list([{"x": 200.0, "y1": -118.0, "y2": -10.0, "l": 1.0, "uf": 1.0}])
	var p := PlayerMotion.new(PhysicsConstants.v83_defaults())
	p.place(Vector2(200, -60), m)
	p.step(DT, MoveInput.make(false, false, true), m, l, Rect2())
	assert_true(p.ladder >= 0, "Up beside the rope grabs it in the air")
	assert_true(p.flash_destination(1, 140.0, m, Rect2()).is_empty(), "climbing: refused")
	assert_false(p.flash_spent)
	# The world also refuses while the climbing state holds (can_cast is false on a ladder).
	var w := _world()
	_lift(w)
	w.player.state = PlayerMotion.ST_LADDER
	assert_true(_press(w, false, true).is_empty())


func test_in_the_air_it_slides_the_rank_1_distance_toward_the_pressed_arrow() -> void:
	var w := _world()
	_lift(w)
	var events := _press(w, false, true)
	assert_eq(events.size(), 1)
	assert_eq(events[0].skill, KEY)
	assert_eq(events[0].from, Vector2(400, -200))
	assert_eq(events[0].to, Vector2(540, -200), "140 px at rank 1, the height kept")
	assert_eq(w.player.facing, 1)
	assert_true(w.player.flash_spent)
	var left := _world()
	_lift(left)
	var events_left := _press(left, true, false)
	assert_eq(events_left[0].to, Vector2(260, -200))
	assert_eq(left.player.facing, -1)


func test_without_an_arrow_it_follows_the_facing_and_opposing_arrows_cancel() -> void:
	var w := _world()
	_lift(w)
	w.player.facing = -1
	assert_eq(_press(w)[0].to, Vector2(260, -200), "facing left, no arrow")
	var both := _world()
	_lift(both)
	both.player.facing = 1
	assert_eq(_press(both, true, true)[0].to, Vector2(540, -200), "left + right cancel into the facing")


func test_up_and_down_arrows_do_not_change_the_direction() -> void:
	var up := _world()
	_lift(up)
	up.player.facing = 1
	assert_eq(_press(up, false, false, true, false)[0].to, Vector2(540, -200))
	var down := _world()
	_lift(down)
	down.player.facing = -1
	assert_eq(_press(down, false, false, false, true)[0].to, Vector2(260, -200))


func test_the_fall_goes_on_and_no_height_is_gained() -> void:
	var w := _world()
	_lift(w)
	_press(w, false, true)
	var y := w.player.pos.y
	_idle(w, 10)
	assert_true(w.player.pos.y > y, "still falling")
	var peak := _world()
	_lift(peak)
	peak.player.vel = Vector2(0, 150)
	_press(peak, false, true)
	assert_true(peak.player.vel.y >= 150.0, "the vertical speed is kept: %s" % peak.player.vel)


func test_no_flash_while_dead_or_choosing_a_card() -> void:
	var w := _world()
	_lift(w)
	w.state = RunWorld.CHOOSING_UPGRADE
	assert_true(_press(w, false, true).is_empty())
	var dead := _world()
	_lift(dead)
	dead._dead = true
	assert_true(_press(dead, false, true).is_empty())
	assert_near(dead.player.pos.x, 400.0, 1.0)


# --- Once per airborne period and the repeat delay ----------------------------------------------------------------------

func test_one_flash_per_airborne_period() -> void:
	var w := _world()
	_lift(w, 400.0, -900.0)
	assert_eq(_press(w, false, true).size(), 1)
	_idle(w, 30)
	assert_true(_press(w, false, true).is_empty(), "past the repeat delay, still the same jump: refused")
	assert_true(w.player.flash_spent)


func test_landing_resets_the_flag() -> void:
	var w := _world()
	_lift(w, 400.0, -30.0)
	_press(w, false, true)
	for i in 120:
		w.step(DT, MoveInput.new())
	assert_eq(w.player.fh, 0, "landed")
	assert_false(w.player.flash_spent, "a landing clears the flag")
	w.drain_events()
	# The next jump may flash again.
	var jump := MoveInput.make(false, false, false, false, true, true)
	w.step(DT, jump)
	_idle(w, 10)
	assert_true(w.player.fh < 0, "in the air again")
	assert_eq(_press(w, false, true).size(), 1)


func test_grabbing_a_ladder_a_portal_or_a_new_map_resets_the_flag() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 400.0, "y2": 0.0},
		{"x1": 150.0, "y1": -120.0, "x2": 350.0, "y2": -120.0},
	])
	var l := LadderSet.from_list([{"x": 200.0, "y1": -118.0, "y2": -10.0, "l": 1.0, "uf": 1.0}])
	var p := PlayerMotion.new(PhysicsConstants.v83_defaults())
	p.place(Vector2(200, -60), m)
	p.flash_to({"x": 200.0, "y": -60.0, "fh": -1})
	assert_true(p.flash_spent)
	p.step(DT, MoveInput.make(false, false, true), m, l, Rect2())
	assert_true(p.ladder >= 0, "Up beside the rope grabs it in the air")
	assert_false(p.flash_spent, "the grab clears the flag")
	p.flash_to({"x": 230.0, "y": -60.0, "fh": -1})
	p.place(Vector2(100, -300), m)
	assert_false(p.flash_spent, "place() (a portal, a map transfer, Banish) clears the flag")


func test_the_repeat_delay_blocks_a_second_press_until_it_runs_out() -> void:
	var w := _world()
	_lift(w)
	_press(w, false, true)
	var ready := w.skill_readiness(KEY)
	assert_near(float(ready.total), 0.3, 1e-9)
	assert_near(float(ready.left), 0.3, 1e-9)
	# A new airborne period at once (a portal's place()): the delay still refuses.
	_lift(w, 600.0)
	w.player.flash_spent = false
	assert_true(_press(w, false, true).is_empty(), "within 0.3 s")
	_idle(w, 18)
	_lift(w, 600.0)
	assert_eq(_press(w, false, true).size(), 1, "after 0.3 s")


func test_holding_the_key_flashes_once_per_jump() -> void:
	var w := _world()
	_lift(w)
	var held := MoveInput.new()
	held.hold_skill("flash_jump")
	held.right = true
	var flashes := 0
	for i in 40:
		w.step(DT, held)
	for e: Dictionary in w.drain_events():
		if e.type == "flash_jump":
			flashes += 1
	assert_eq(flashes, 1)


# --- Rank and distance -------------------------------------------------------------------------------------------------

func test_the_rank_follows_the_round_level_never_a_card() -> void:
	var w := _world()
	for pair: Array in [[1, 1, 140.0], [20, 10, 140.0 + 140.0 * 9.0 / 19.0], [40, 20, 280.0], [60, 20, 280.0]]:
		w._level_ranks(int(pair[0]))
		assert_eq(w.loadout.rank(KEY), int(pair[1]), "rank at Lv%d" % pair[0])
		assert_near(w.flash_jump_distance(KEY), float(pair[2]), 1e-6, "distance at Lv%d" % pair[0])
	assert_eq(w.book.max_rank(KEY), 20, "twenty ranks, one per WZ level")
	for card: Dictionary in w.data.upgrades.cards:
		assert_ne(String(card.get("skill", "")), KEY, "no card names Flash Jump")


func test_a_higher_rank_flashes_farther() -> void:
	var w := _world(300.0)
	w._level_ranks(40)
	_lift(w, 300.0)
	assert_eq(_press(w, false, true)[0].to, Vector2(580, -200), "280 px at rank 20")


# --- Stops -------------------------------------------------------------------------------------------------------------

func test_a_wall_stops_the_flash_short() -> void:
	var w := _world(400.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}, {"x1": 480, "y1": 0, "x2": 480, "y2": -400}])
	_lift(w, 400.0, -100.0)
	var events := _press(w, false, true)
	assert_eq(events.size(), 1)
	assert_true(events[0].to.x > 400.0 and events[0].to.x < 480.0, "stops before the wall at 480: %s" % events[0].to)
	assert_eq(events[0].to.y, -100.0)


func test_the_map_limit_stops_the_flash() -> void:
	var w := _world(60.0)
	_lift(w, 60.0)
	var events := _press(w, true, false)
	assert_eq(events.size(), 1)
	assert_true(events[0].to.x >= w.bounds.position.x, "never past the map's left limit")
	assert_true(events[0].to.x < 60.0)


func test_a_blocked_flash_is_refused_and_spends_nothing() -> void:
	var w := _world(400.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}, {"x1": 401, "y1": 0, "x2": 401, "y2": -400}])
	_lift(w, 400.5, -100.0)
	w.player.pos.x = 400.9999
	var events := _press(w, false, true)
	if events.is_empty():
		assert_false(w.player.flash_spent, "nothing spent")
		assert_eq(float(w.skill_readiness(KEY).left), 0.0)
	else:
		assert_true(events[0].to.x - events[0].from.x < 1.0, "pressed against the wall: no real move")


# --- No damage, no meter, no cast ----------------------------------------------------------------------------------------

func test_it_deals_no_damage_earns_no_meter_and_is_no_cast() -> void:
	var w := _world()
	var mob := RF.put_mob(w, 1110100, 460, 190, 1000)
	var hp := w.swarm.hp[mob]
	var meter := w.meter.value
	_lift(w)
	var events := _press(w, false, true)
	assert_eq(events.size(), 1)
	_idle(w, 5)
	assert_eq(w.swarm.hp[mob], hp, "the mob is untouched")
	assert_eq(w.meter.value, meter, "no meter")
	var casts := w.runner.casts
	_idle(w, 1)
	assert_eq(w.runner.casts, casts, "the flash itself casts nothing")
	var cast_skills := {}
	for e: Dictionary in w.drain_events():
		if e.type == "cast":
			cast_skills[e.skill] = true
	assert_false(cast_skills.has(KEY), "Flash Jump emits no cast event")


func test_other_oracle_events_are_untouched_without_the_key() -> void:
	var a := RF.quiet_world(400, 31)
	var b := RF.quiet_world(400, 31)
	for i in 120:
		a.step(DT, MoveInput.new())
		var press := MoveInput.new()
		press.press_skill("flash_jump") # a job without the skill: the press is ignored
		b.step(DT, press)
	assert_eq(a.drain_events(), b.drain_events())
	assert_eq(a.player.pos, b.player.pos)


# --- Key Config and the HUD --------------------------------------------------------------------------------------------

func test_flash_jump_is_a_skill_key_bound_to_x_like_the_other_mobility_skills() -> void:
	assert_true("flash_jump" in KeyBindings.SKILL_KEYS)
	assert_true(InputMap.has_action("flash_jump"), "the project defines the action")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_X
	key.pressed = true
	assert_true(key.is_action_pressed("flash_jump"), "X is the default, shared with Teleport, Dash and Rush")


func test_key_config_lists_exactly_the_flash_jump_key_for_the_job() -> void:
	var w := _world()
	var keys := w.manual_skill_keys()
	assert_eq(keys.size(), 1, "one skill key row: Lucky Seven is not a manual skill")
	assert_eq(keys[0].action, "flash_jump")
	assert_eq(keys[0].name, "Flash Jump")
	assert_eq(keys[0].icon, "Skill.wz/411.img/skill/4111006/icon")
	var draft := KeyBindings.from_settings(GameSettings.new(), ["flash_jump"])
	assert_eq(draft.skill_keys, ["flash_jump"])
	assert_true(draft.keys.has("flash_jump"), "the draft binds it")
	assert_eq(HudQuickSlot.movement_skill_of(keys).get("action", ""), "flash_jump", "the quick slot shows it")


func test_the_hud_row_carries_the_flash_jump_key_and_its_repeat_delay() -> void:
	var scene := RunScene.new()
	scene.world = _world()
	var row: Dictionary = scene.run_info().skills.back()
	assert_eq(row.key_label, "X")
	assert_eq(row.cooldown_left, 0.0)
	_lift(scene.world)
	_press(scene.world, false, true)
	row = scene.run_info().skills.back()
	assert_near(float(row.cooldown_total), 0.3, 1e-6)
	assert_true(float(row.cooldown_left) > 0.2)
	scene.free()


func test_the_trail_node_keeps_its_ghosts_for_the_fade_time() -> void:
	var trail := FlashTrail.new()
	trail.spawn([], 1, Vector2(0, 0), Vector2(300, 0))
	assert_eq(trail.count(), FlashJump.TRAIL_COPIES)
	trail._process(FlashJump.TRAIL_TIME * 0.5)
	assert_eq(trail.count(), FlashJump.TRAIL_COPIES, "still fading")
	trail._process(FlashJump.TRAIL_TIME)
	assert_eq(trail.count(), 0, "gone after the fade time")
	trail.free()


# --- The bot -----------------------------------------------------------------------------------------------------------

func _mob(w: RunWorld, x: float, y := 0.0) -> int:
	return RF.put_mob(w, 1110100, x, y, 1000)


func test_the_bot_never_flashes_on_the_ground() -> void:
	var w := _world()
	_mob(w, 430)
	assert_false(BotInput.decide(w, {}).skill_pressed("flash_jump"), "a mob 30 px away, but the bot stands on the floor")


func test_the_bot_flashes_away_from_a_close_threat_while_airborne() -> void:
	var w := _world()
	var mob := _mob(w, 440)
	_lift(w)
	w.player.pos.y = -30.0
	w.swarm.y[mob] = -30.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	var input := BotInput.decide(w, {})
	assert_true(input.skill_pressed("flash_jump"), "a mob 40 px to the right at the same height")
	assert_true(input.left and not input.right, "away from it")
	w.swarm.x[mob] = 360.0
	input = BotInput.decide(w, {})
	assert_true(input.skill_pressed("flash_jump") and input.right and not input.left, "the other way for a mob on the left")


func test_the_bot_ignores_far_or_high_or_low_mobs_and_a_spent_flash() -> void:
	var w := _world()
	var mob := _mob(w, 520)
	_lift(w)
	w.player.pos.y = -30.0
	w.swarm.y[mob] = -30.0
	assert_false(BotInput.decide(w, {}).skill_pressed("flash_jump"), "120 px away is no emergency")
	w.swarm.x[mob] = 440.0
	w.swarm.y[mob] = 100.0
	assert_false(BotInput.decide(w, {}).skill_pressed("flash_jump"), "130 px below is not on its level")
	w.swarm.y[mob] = -30.0
	w.player.flash_spent = true
	assert_false(BotInput.decide(w, {}).skill_pressed("flash_jump"), "already flashed in this jump")


func test_the_bot_needs_half_the_distance_of_free_lane_and_waits_three_seconds() -> void:
	# Walls 20 px to the left and 40 px to the right: neither lane covers half of 140 px, so no press.
	var edge := _world(40.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}, {"x1": 20, "y1": 0, "x2": 20, "y2": -400},
		{"x1": 80, "y1": 0, "x2": 80, "y2": -400}])
	var mob := _mob(edge, 60)
	_lift(edge, 40.0, -30.0)
	edge.swarm.y[mob] = -30.0
	assert_false(BotInput.decide(edge, {}).skill_pressed("flash_jump"), "no room to flee")
	var w := _world()
	var m2 := _mob(w, 440)
	_lift(w)
	w.player.pos.y = -30.0
	w.swarm.y[m2] = -30.0
	var memo := {}
	assert_true(BotInput.decide(w, memo).skill_pressed("flash_jump"))
	w.player.flash_spent = false
	w.time += 2.0
	assert_false(BotInput.decide(w, memo).skill_pressed("flash_jump"), "two seconds after the last flash")
	w.time += 1.1
	assert_true(BotInput.decide(w, memo).skill_pressed("flash_jump"), "three seconds after")


func test_a_bot_world_flashes_through_the_real_tick_loop() -> void:
	var w := _world()
	var mob := _mob(w, 440)
	w.god = true
	_lift(w)
	w.player.pos.y = -30.0
	w.swarm.y[mob] = -30.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	w.step(DT, BotInput.decide(w, {}))
	var flashes := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "flash_jump")
	assert_eq(flashes.size(), 1)
	assert_true(flashes[0].to.x < flashes[0].from.x, "left, away from the mob on the right")


# --- Real cache ---------------------------------------------------------------------------------------------------------

func test_real_cache_the_node_has_twenty_levels_and_neither_range_nor_x() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var node: Dictionary = lib.img("Skill.wz/411.img").root.skill["4111006"]
	var levels: Dictionary = node.level
	assert_eq(levels.size(), 20, "twenty WZ levels")
	for lv: String in levels:
		var level: Dictionary = levels[lv]
		assert_false(level.has("range") or level.has("x") or level.has("damage"), "level %s holds no distance field" % lv)
		assert_true(level.has("mpCon"))
	assert_false(node.has("effect") or node.has("ball") or node.has("hit"), "the node has no art")
	assert_true(node.has("icon"))
	lib.free()
	var data := DataRepo.load_all()
	var book := SkillBook.from_data(data.skills, {"411": null})
	assert_eq(int(book.def(KEY).skill_id), 4111006)
	assert_eq(FileAccess.file_exists(AssetCachePaths.resolve_cache_root().path_join("Sound.wz/Skill.img/4111006/Use.mp3")), true,
		"the Use sound is in the cache")
