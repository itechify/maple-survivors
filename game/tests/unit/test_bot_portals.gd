extends TestCase
## Portal-aware autoplay through the seeded RunWorld seam. Synthetic drops and monsters exercise routing decisions;
## the cache-required Tree I test verifies the original portal chain within a fixed tick budget.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0


func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = "" # the portal bot is skill-less (#284 start skills)
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


## A two-way hidden pair like West Street Corner of Perion's hide00/tohide00 (102010000): lower entrance at x 300,
## upper entrance at x 800 on a ledge walled at both ends. The floors are joined only by the portals.
func _two_way_world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = "" # the portal bot is skill-less (#284 start skills)
	var s := RF.setup("quiet", 18, data)
	s.map_img = RF.map_from_segments([
		{"x1": 0, "y1": 200, "x2": 1200, "y2": 200},
		{"x1": 600, "y1": -500, "x2": 600, "y2": -200},
		{"x1": 600, "y1": -200, "x2": 1000, "y2": -200},
		{"x1": 1000, "y1": -200, "x2": 1000, "y2": -500},
	])
	s.map_img.portal = {
		"0": {"pn": "hide00", "pt": 1, "x": 300, "y": 200, "tm": 999999999, "tn": "tohide00"},
		"1": {"pn": "tohide00", "pt": 1, "x": 800, "y": -200, "tm": 999999999, "tn": "hide00"},
	}
	var w := RunWorld.new(s)
	w.player.place(Vector2(300, 200), w.fhm)
	w.drain_events()
	return w


## #257: Perion seed 1 died at 1:02, Lv1, bouncing hide00 <-> tohide00 every portal cooldown (0.384 s): the escape
## took it up, then the drop route took the reverse link straight back into the crowd it fled.
func test_bot_does_not_take_the_reverse_link_straight_back_into_the_crowd_it_escaped() -> void:
	var w := _two_way_world()
	RF.put_mob(w, 1110100, 270, 200)
	RF.put_mob(w, 1110100, 330, 200)
	w.pickups.spawn(Vector2(420, 200), 1, 4000019)
	var memo := {}
	var used := []
	for i in 60 * 3:
		w.step(DT, BotInput.decide(w, memo))
		for e: Dictionary in w.drain_events():
			if e.type == "portal_used":
				used.append(e.portal)
	assert_eq(used, ["hide00"], "one escape up; the reverse link stays closed while the crowd it fled is below")
	assert_eq(w.player_platform(), 1, "still on the upper floor")


func test_bot_takes_the_reverse_link_for_a_drop_once_the_hold_is_over() -> void:
	var w := _two_way_world()
	RF.put_mob(w, 1110100, 270, 200)
	RF.put_mob(w, 1110100, 330, 200)
	var memo := {}
	var used := []
	for i in 60 * 12:
		if used == ["hide00"] and w.swarm.alive_count() > 0:
			# The crowd below is gone and a drop waits there: the trip down is worth taking again.
			for m in w.swarm.capacity():
				if w.swarm.active[m] != 0:
					w.swarm.despawn(m)
			w.pickups.spawn(Vector2(420, 200), 1, 4000019)
		w.step(DT, BotInput.decide(w, memo))
		for e: Dictionary in w.drain_events():
			if e.type == "portal_used":
				used.append(e.portal)
	assert_eq(used, ["hide00", "tohide00"], "the hold only delays the reverse link")
	assert_eq(w.pickups.collected_exp, 1)


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
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = "" # the portal bot is skill-less (#284 start skills)
	data.stages.stages.quiet.maps[0].map_id = 101010100
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


func test_bot_and_camper_approach_the_same_portal_ledge_with_identical_inputs() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = "" # the portal bot is skill-less (#284 start skills)
	var setup := RF.setup("quiet", 18, data)
	setup.map_img = RF.map_from_segments([
		{"x1": 0, "y1": 200, "x2": 1200, "y2": 200},
		{"x1": 300, "y1": 140, "x2": 360, "y2": 140},
		{"x1": 600, "y1": -200, "x2": 1000, "y2": -200},
	])
	setup.map_img.portal = {
		"0": {"pn": "up00", "pt": 1, "x": 330, "y": 140, "tm": 999999999, "tn": "up01"},
		"1": {"pn": "up01", "pt": 1, "x": 800, "y": -200, "tm": 999999999, "tn": ""},
	}
	var bot := RunWorld.new(setup)
	var camper := RunWorld.new(setup)
	for w: RunWorld in [bot, camper]:
		w.player.place(Vector2(500, 200), w.fhm)
		w.pickups.spawn(Vector2(900, -200), 1, 4000019)
	var bot_memo := {}
	var camper_memo := {}
	var used := []
	var hopped := false
	for tick in 60 * 8:
		var bot_input := BotInput.decide(bot, bot_memo)
		var camper_input: MoveInput = BR.movement(camper, "camper_tree_top", camper_memo, 0.0)
		assert_eq([bot_input.left, bot_input.right, bot_input.up, bot_input.jump_pressed, bot_input.jump_held],
			[camper_input.left, camper_input.right, camper_input.up, camper_input.jump_pressed, camper_input.jump_held],
			"different policies share the same entrance approach when their goal matches")
		hopped = hopped or bot_input.jump_pressed
		bot.step(DT, bot_input)
		camper.step(DT, camper_input)
		for event: Dictionary in bot.drain_events():
			if event.type == "portal_used":
				used.append(event.portal)
		if not used.is_empty():
			break
	assert_true(hopped, "the entrance ledge requires the shared takeoff decision")
	assert_eq(used, ["up00"])
	assert_eq(bot.player.pos, camper.player.pos)
