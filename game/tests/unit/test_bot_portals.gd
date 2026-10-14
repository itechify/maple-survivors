extends TestCase
## Portal-aware autoplay through the seeded RunWorld seam. Synthetic drops and monsters exercise routing decisions;
## the cache-required Tree I test verifies the original portal chain within a fixed tick budget.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world() -> RunWorld:
	var data := RF.quiet_data()
	var s := RF.setup("quiet", 18, data)
	s.map_img = RF.map_from_segments([
		{"x1": 0, "y1": 200, "x2": 1200, "y2": 200},
		{"x1": 600, "y1": -200, "x2": 1000, "y2": -200},
	])
	s.map_img.portal = {
		"0": {"pn": "up00", "pt": 1, "x": 300, "y": 200, "tm": 999999999, "tn": "up01"},
		"1": {"pn": "up01", "pt": 1, "x": 800, "y": -200, "tm": 999999999, "tn": ""},
	}
	var w := RunWorld.new(s)
	w.player.place(Vector2(500, 200), w.fhm)
	w.drain_events()
	return w


func test_bot_walks_to_portal_and_collects_a_drop_on_the_upper_floor() -> void:
	var w := _world()
	w.pickups.spawn(Vector2(900, -200), 1, 4000019)
	var memo := {}
	var used := []
	for i in 60 * 8:
		w.step(DT, BotInput.decide(w, memo))
		for e: Dictionary in w.drain_events():
			if e.type == "portal_used":
				used.append(e.portal)
	assert_eq(used, ["up00"], "bot approaches a useful portal and holds Up")
	assert_eq(w.pickups.collected_exp, 1, "drop on the upper floor collected")
	assert_eq(w.player_platform(), 1, "bot reached the upper floor")


func test_bot_uses_a_nearby_portal_to_leave_a_dangerous_floor() -> void:
	var w := _world()
	w.player.place(Vector2(300, 200), w.fhm)
	RF.put_mob(w, 1110100, 270, 200)
	RF.put_mob(w, 1110100, 330, 200)
	w.step(DT, BotInput.decide(w, {}))
	var warps := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "portal_used")
	assert_eq(warps.size(), 1, "a nearby portal leads to a safer floor without needing a drop")
	assert_eq(w.player.pos, Vector2(800, -230))


func test_bot_does_not_take_a_portal_that_moves_away_from_nearby_drops() -> void:
	var w := _world()
	w.player.place(Vector2(300, 200), w.fhm)
	w.pickups.spawn(Vector2(450, 200), 1, 4000019)
	var memo := {}
	var used := []
	for i in 60 * 3:
		w.step(DT, BotInput.decide(w, memo))
		for e: Dictionary in w.drain_events():
			if e.type == "portal_used":
				used.append(e.portal)
	assert_true(used.is_empty(), "the portal would add unnecessary vertical travel")
	assert_eq(w.pickups.collected_exp, 1)
	assert_eq(w.player_platform(), 0)


func test_bot_reaches_top_of_real_tree_through_the_portal_chain() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var img := lib.img(DataRepo.map_img_path(101010100))
	assert_true(img != null)
	if img == null:
		lib.free()
		return
	var data := RF.quiet_data()
	data.stages.stages.quiet.map_id = 101010100
	var s := RF.setup("quiet", 18, data)
	s.map_img = img.root
	var w := RunWorld.new(s)
	w.pickups.spawn(Vector2(-1300, 810), 1, 4000019)
	var memo := {}
	var used := []
	var reached := -1.0
	for i in 60 * 30:
		w.step(DT, BotInput.decide(w, memo))
		for e: Dictionary in w.drain_events():
			if e.type == "portal_used":
				used.append(e.portal)
		if w.player_platform() == 7:
			reached = w.time
			break
	print("  Tree I autoplay seed 18: portals %s, platform %d at %.2f s, feet %s" %
		[used, w.player_platform(), w.time, w.player.pos])
	assert_eq(used, ["up00", "up01", "up02"])
	assert_between(reached, 0.0, 30.0, "bot reaches P7 through portals within 30 s")
	lib.free()
