extends TestCase
## The playtest tactic controller (game/tools/playtest/tactic_controller.gd, spec #91 ticket #95): each tactic turns a
## constructed situation into the expected MoveInput, and `kite` is BotInput.decide unchanged.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CONTROLLER := preload("res://tools/playtest/tactic_controller.gd")
const DT := 1.0 / 60.0


## Ground 0..2000 at y 200 with two low platforms a hop above it: B (100..400) on the left, C (1600..1900) on the
## right. The player stands in the middle.
func _two_ledges() -> RunWorld:
	var s := RF.setup("quiet", 31, RF.quiet_data())
	s.map_img = RF.map_from_segments([
		{"x1": 0, "y1": 200, "x2": 2000, "y2": 200},
		{"x1": 100, "y1": 150, "x2": 400, "y2": 150},
		{"x1": 1600, "y1": 150, "x2": 1900, "y2": 150},
	], [Vector2(1000, 180)])
	var w := RunWorld.new(s)
	RF.place_player(w, 1000.0)
	w.drain_events()
	return w


func _platform_at(w: RunWorld, x: float, y: float) -> int:
	return w.fhm.platform_of(w.fhm.find_below(x, y))


func _moving(mi: MoveInput) -> bool:
	return mi.left or mi.right or mi.up or mi.down or mi.jump_pressed or mi.jump_held


func test_kite_is_bot_input_unchanged() -> void:
	var a := RF.quiet_world(400.0, 21)
	var b := RF.quiet_world(400.0, 21)
	for w: RunWorld in [a, b]:
		RF.put_mob(w, 100100, 520.0)
		w.pickups.spawn(Vector2(100.0, 195.0), 3, 0)
	var memo_a := {}
	var memo_b := {}
	var controller := CONTROLLER.new()
	for i in 240:
		var want := BotInput.decide(a, memo_a)
		var got: MoveInput = controller.input(b, "kite", memo_b)
		assert_eq([got.left, got.right, got.up, got.down, got.jump_pressed, got.drink_hp, got.teleport_pressed],
			[want.left, want.right, want.up, want.down, want.jump_pressed, want.drink_hp, want.teleport_pressed],
			"tick %d" % i)
		a.step(DT, want)
		b.step(DT, got)
	assert_eq(b.player.pos, a.player.pos, "the same inputs played the same ticks")
	assert_eq(memo_b, memo_a, "kite keeps BotInput's memo exactly")


func test_aggressive_closes_on_a_lone_mob() -> void:
	var w := RF.quiet_world(400.0, 22)
	RF.put_mob(w, 100100, 620.0)
	var mi: MoveInput = CONTROLLER.new().input(w, "aggressive", {})
	assert_true(mi.right and not mi.left, "walks right toward the mob 220 px away")
	var w2 := RF.quiet_world(400.0, 22)
	RF.put_mob(w2, 100100, 180.0)
	mi = CONTROLLER.new().input(w2, "aggressive", {})
	assert_true(mi.left and not mi.right, "walks left toward the mob")


func test_aggressive_kites_instead_while_hp_is_low() -> void:
	var w := RF.quiet_world(400.0, 22)
	RF.put_mob(w, 100100, 470.0)
	w.player_state.hp = int(w.player_state.max_hp * 0.3)
	var mi: MoveInput = CONTROLLER.new().input(w, "aggressive", {})
	assert_true(mi.left and not mi.right, "low HP: flees from the mob like the kiting bot")


func test_defensive_moves_away_from_a_mob_the_kiting_bot_ignores() -> void:
	var w := RF.quiet_world(600.0, 23)
	RF.put_mob(w, 100100, 850.0)
	var kite := BotInput.decide(w, {})
	assert_true(kite.right, "fixture: the kiting bot walks right to the map's middle; the mob is beyond its flee range")
	var mi: MoveInput = CONTROLLER.new().input(w, "defensive", {})
	assert_true(mi.left and not mi.right, "defensive keeps a wider berth: walks away from the mob 250 px to the right")


func test_defensive_skips_a_drop_next_to_a_mob() -> void:
	var w := RF.quiet_world(800.0, 24)
	w.pickups.spawn(Vector2(1300.0, 195.0), 3, 0)
	RF.put_mob(w, 100100, 1450.0)
	var mi: MoveInput = CONTROLLER.new().input(w, "defensive", {})
	assert_false(mi.right, "does not walk to a drop with a mob beside it")
	var w2 := RF.quiet_world(800.0, 24)
	w2.pickups.spawn(Vector2(1300.0, 195.0), 3, 0)
	mi = CONTROLLER.new().input(w2, "defensive", {})
	assert_true(mi.right, "walks to the same drop once no mob is near it")


func test_explore_heads_to_the_least_visited_platform() -> void:
	for case: Array in [["left", 250.0, 1750.0], ["right", 1750.0, 250.0]]:
		var w := _two_ledges()
		var goal := _platform_at(w, float(case[1]), 140.0)
		var visited := _platform_at(w, float(case[2]), 140.0)
		var controller := CONTROLLER.new()
		controller.visits[w.player_platform()] = 5
		controller.visits[visited] = 2
		var memo := {}
		for i in 60 * 10:
			w.step(DT, controller.input(w, "explore", memo))
			if w.player_platform() == goal and w.player.fh >= 0:
				break
		assert_eq(w.player_platform(), goal, "explore reached the unvisited %s ledge" % case[0])
		assert_true(w.player.fh >= 0, "standing on it")
		controller.input(w, "explore", memo) # the controller sees the arrival on its next tick
		assert_eq(int(controller.visits.get(goal, 0)), 1, "the arrival is counted as a visit")


func test_collect_climbs_to_a_drop_on_a_platform_above() -> void:
	var at_rope := RF.quiet_world(1200.0, 25)
	at_rope.pickups.spawn(Vector2(1280.0, 60.0), 7, 0)
	assert_false(BotInput.decide(at_rope, {}).up, "fixture: one drop above is not worth a climb for the kiting bot")
	assert_true(CONTROLLER.new().input(at_rope, "collect", {}).up, "collect grabs the rope under the drop")
	var w := RF.quiet_world(1700.0, 25)
	w.pickups.spawn(Vector2(1280.0, 60.0), 7, 0)
	var controller := CONTROLLER.new()
	var memo := {}
	for i in 60 * 12:
		w.step(DT, controller.input(w, "collect", memo))
		w.drain_events()
		if w.pickups.collected_exp > 0:
			break
	assert_eq(w.pickups.collected_exp, 7, "collect walked to the rope, climbed and swept the drop")


## Henesys seed 2 at 1:05 (#96's stuck finding), rebuilt: the player stands on a floor that rises to the right (M,
## 0..620). Drop A lies on a lower ledge to the right (L, reached by walking off M's right end); drop B lies on a high
## platform (H) whose only way up is a rope at M's left end. Walking right toward A makes B the cheaper drop by the
## travel cost and walking left toward B's rope makes A cheaper again, so a controller that re-picks the cheapest drop
## every tick dithers in a ~12 px band on M and collects neither.
func test_collect_commits_to_one_drop_instead_of_dithering_between_two() -> void:
	var s := RF.setup("quiet", 32, RF.quiet_data())
	s.map_img = RF.map_from_segments([
		{"x1": 0, "y1": 300, "x2": 620, "y2": 269},
		{"x1": 550, "y1": 340, "x2": 1100, "y2": 340},
		{"x1": 0, "y1": 120, "x2": 800, "y2": 120},
		{"x1": 0, "y1": 400, "x2": 1200, "y2": 400},
	], [Vector2(450, 260)])
	s.map_img["ladderRope"] = {"1": {"l": 0.0, "uf": 1.0, "x": 100.0, "y1": 125.0, "y2": 293.0, "page": 1.0}}
	var w := RunWorld.new(s)
	RF.place_player(w, 450.0, 250.0)
	w.drain_events()
	w.pickups.spawn(Vector2(900.0, 335.0), 3, 0)
	w.pickups.spawn(Vector2(700.0, 115.0), 7, 0)
	var controller := CONTROLLER.new()
	var memo := {}
	for i in 60 * 15:
		w.step(DT, controller.input(w, "collect", memo))
		w.drain_events()
		if w.pickups.collected_exp > 0:
			break
	assert_true(w.pickups.collected_exp > 0, "collect swept one of the two drops within 15 s (player ended at x %.1f)"
		% w.player.pos.x)


func test_collect_walks_to_a_drop_on_its_floor() -> void:
	var w := RF.quiet_world(800.0, 26)
	w.pickups.spawn(Vector2(300.0, 195.0), 3, 0)
	var mi: MoveInput = CONTROLLER.new().input(w, "collect", {})
	assert_true(mi.left and not mi.right)


func test_hold_presses_no_movement_key() -> void:
	var w := RF.quiet_world(400.0, 27)
	RF.put_mob(w, 100100, 450.0)
	w.pickups.spawn(Vector2(300.0, 195.0), 3, 0)
	var mi: MoveInput = CONTROLLER.new().input(w, "hold", {})
	assert_false(_moving(mi), "hold stays put")


func test_unknown_tactic_kites() -> void:
	var w := RF.quiet_world(400.0, 28)
	RF.put_mob(w, 100100, 470.0)
	var want := BotInput.decide(w, {})
	var got: MoveInput = CONTROLLER.new().input(w, "no_such_tactic", {})
	assert_eq([got.left, got.right], [want.left, want.right])
