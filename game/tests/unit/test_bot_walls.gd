extends TestCase
## The autoplay bot and walls across its floor (#259), through the seeded RunWorld seam on synthetic footholds: a
## pocket between a wall too tall to jump and a low step (the shape of Kerning City Construction Site's x 350 / x 505
## pocket). The bot must hop the step and stop walking back into the tall wall.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const TALL_WALL_X := 400.0
const STEP_X := 560.0


## Lower floor y 200 from `left` to 1200, crossed by a tall wall at x 400 (y 0..260) and by the 30 px step at x 560,
## whose upper floor (y 170) runs on to 1200. The bot stands in the pocket at x 480.
func _pocket_world(left := 0.0) -> RunWorld:
	var data := RF.quiet_data()
	var s := RF.setup("quiet", 18, data)
	s.map_img = RF.map_from_segments([
		{"x1": left, "y1": 200, "x2": 1200, "y2": 200},
		{"x1": TALL_WALL_X, "y1": 0, "x2": TALL_WALL_X, "y2": 260},
		{"x1": STEP_X, "y1": 260, "x2": STEP_X, "y2": 170},
		{"x1": STEP_X, "y1": 170, "x2": 1200, "y2": 170},
	])
	var w := RunWorld.new(s)
	RF.place_player(w, 480.0)
	w.drain_events()
	return w


func _run(w: RunWorld, seconds: float, memo: Dictionary) -> void:
	for t in int(seconds * 60.0):
		w.step(DT, BotInput.decide(w, memo))
		w.drain_events()


func test_the_fixture_models_a_walled_pocket() -> void:
	var w := _pocket_world()
	assert_eq(w.player.pos, Vector2(480, 200), "the bot stands in the pocket")
	assert_true(w.fhm.walk_blocked(w.player_platform(), 480.0, 200.0), "the tall wall crosses the pocket's floor")
	assert_true(w.fhm.walk_blocked(w.player_platform(), 480.0, 700.0), "so does the step")


func test_the_bot_hops_the_step_out_of_the_pocket_to_drops_it_can_reach() -> void:
	var w := _pocket_world()
	# The nearest drop lies behind the tall wall (unreachable); three more lie past the low step.
	w.pickups.spawn(Vector2(200, 200), 1, 4000019)
	for i in 3:
		w.pickups.spawn(Vector2(880.0 + i * 20.0, 170.0), 1, 4000019)
	_run(w, 12.0, {})
	assert_eq(w.pickups.collected_exp, 3, "the three drops past the step are collected")
	assert_true(w.player.pos.x > STEP_X and w.player.pos.y < 180.0,
		"the bot is on the upper floor past the step (%s)" % w.player.pos)


func test_a_wall_the_bot_got_stuck_at_is_a_dead_end_it_does_not_flee_into() -> void:
	var w := _pocket_world(-2400.0)
	var memo := {}
	_run(w, 4.0, memo) # walks to the centre, meets the tall wall, leaves over the step
	RF.place_player(w, 470.0)
	RF.put_mob(w, 1110100, 610, 180)
	RF.put_mob(w, 1110100, 630, 180)
	var mi := BotInput.decide(w, memo)
	assert_true(mi.right and not mi.left,
		"two mobs on the right and the remembered tall wall 70 px to the left: the bot turns toward the open side")
	var fresh := BotInput.decide(w, {})
	assert_true(fresh.left, "a bot that never met the wall still flees left, toward the far map edge")


func test_with_the_map_centre_behind_the_tall_wall_the_bot_leaves_the_pocket_and_stays_out() -> void:
	# No drops: the bot heads for the map centre, which lies far beyond the tall wall.
	var w := _pocket_world(-2400.0)
	assert_true(w.bounds.get_center().x < TALL_WALL_X - 200.0, "the map centre is behind the tall wall")
	var memo := {}
	_run(w, 6.0, memo)
	var in_pocket := 0
	for t in 60 * 20:
		w.step(DT, BotInput.decide(w, memo))
		w.drain_events()
		if w.player.pos.x < STEP_X and w.player.pos.y > 190.0:
			in_pocket += 1
	assert_true(in_pocket < 60, "after leaving, the bot spends under 1 s of 20 in the pocket (%d ticks)" % in_pocket)
