extends TestCase
## Player-platform spawns through a fixed-tick seeded RunWorld: configured share, visible placement distance,
## harmless regen, off-screen placement on long platforms, and an informational real-map top-platform camper run.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(half_width := 300.0, share := 0.35) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.spawn["platform_share"] = share
	data.balance.spawn["platform_min_dist"] = 150.0
	data.balance.spawn.recycle_dist = 5000.0
	data.balance.spawn.stall_time = 0.0
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 60, "max_alive": 2000, "hp": 1,
		"speed": 0, "damage": 1, "pool": {"100100": 1}}]
	var s := RF.setup("quiet", 15, data)
	s.map_img = RF.map_from_segments([
		{"x1": -1500, "y1": 400, "x2": 1500, "y2": 400},
		{"x1": -half_width, "y1": 0, "x2": half_width, "y2": 0},
	])
	var w := RunWorld.new(s)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.player.place(Vector2.ZERO, w.fhm)
	w.god = true
	w.update_view()
	w.drain_events()
	return w


func test_seeded_spawns_match_the_configured_player_platform_share() -> void:
	var w := _world()
	var total := 0
	var on_platform := 0
	for i in 1000:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "mob_spawned" and int(e.relocated_from) < 0:
				total += 1
				if e.pos.y == 0:
					on_platform += 1
	assert_eq(total, 1000, "every configured spawn fits")
	assert_between(float(on_platform) / total, 0.31, 0.39, "data requests a 35 percent player-platform share")
	print("  Player-platform spawns seed 15: %d/%d (%.3f), requested 0.35" %
		[on_platform, total, float(on_platform) / total])


func test_fully_visible_platform_spawns_are_separated_and_harmless_until_faded_in() -> void:
	var w := _world(300, 1.0)
	for i in 60:
		w.step(DT, MoveInput.new())
		var spawned := w.drain_events().filter(func(e: Dictionary) -> bool:
			return e.type == "mob_spawned" and int(e.relocated_from) < 0)
		assert_eq(spawned.size(), 1)
		if spawned.is_empty():
			continue
		var e: Dictionary = spawned[0]
		assert_true(w.view.has_point(e.pos), "short platform fits entirely in view")
		assert_true(e.pos.distance_to(w.player.pos) >= 150.0, "minimum visible-spawn separation")
		assert_eq(w.swarm.alpha[e.mob], 0.0, "new spawn starts transparent")
	# Stand inside the last visible spawn's body while it fades; real world touch handling must remain harmless.
	var mob := w.swarm.capacity() - 1
	for i in w.swarm.capacity():
		if w.swarm.active[i] != 0 and w.swarm.alpha[i] == 0.0:
			mob = i
			break
	for i in w.swarm.capacity():
		if i != mob:
			w.swarm.despawn(i)
	w.god = false
	w.director.keyframes[0].rate = 0.0
	w.player.place(Vector2(w.swarm.x[mob], w.swarm.y[mob]), w.fhm)
	var before := int(w.player_state.hp)
	for i in 16:
		w.step(DT, MoveInput.new())
		assert_eq(int(w.player_state.hp), before, "transparent mobs cannot touch the player")
	assert_true(w.swarm.alpha[mob] < 1.0)
	for i in 5:
		w.step(DT, MoveInput.new())
	assert_true(int(w.player_state.hp) < before, "touch becomes active when fully faded in")


func test_long_platform_spawns_stay_offscreen() -> void:
	var w := _world(1400, 1.0)
	for i in 100:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type != "mob_spawned" or int(e.relocated_from) >= 0:
				continue
			assert_eq(e.pos.y, 0.0, "spawn stays on the player's long platform")
			assert_false(w.director.screen_rect(w).has_point(e.pos), "long platform supplies an off-screen entrance")
	assert_eq(w.director.spawned, 100)


func test_a_partly_visible_platform_does_not_allow_visible_placement() -> void:
	var w := _world(300, 1.0)
	w.view = Rect2(-200, -300, 800, 600)
	for i in 100:
		var point := w.director.pick_player_platform(w)
		assert_true(point.z >= 0, "off-screen part of the same floor is available")
		assert_false(w.director.screen_rect(w).has_point(Vector2(point.x, point.y)))


func test_platform_placement_supports_a_boss_distance_and_visible_override() -> void:
	var w := _world(1400, 1.0)
	for side: int in [-1, 1]:
		var point := w.director.pick_player_platform(w, 150.0, 250.0, true, side)
		assert_eq(point, Vector3(side * 250, 0, 1), "boss relocation uses the preferred point on its requested side")
		assert_true(w.view.has_point(Vector2(point.x, point.y)))


func test_real_top_platform_camper_reports_hits_for_information() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys_hg1", 15, Vector2(800, 600),
		func(path: String) -> Dictionary:
			var img := lib.img(path)
			return img.root if img != null else {},
		lib.mob_root)
	var w := RunWorld.new(setup)
	var top := -1
	var highest := INF
	for f in w.fhm.count():
		if w.fhm.is_floor(f) and w.fhm.y1[f] < highest:
			top = f
			highest = w.fhm.y1[f]
	assert_true(top >= 0)
	if top < 0:
		lib.free()
		return
	var x := (w.fhm.x1[top] + w.fhm.x2[top]) * 0.5
	w.player.place(Vector2(x, w.fhm.y_at(top, x)), w.fhm)
	w.update_view()
	var hits := 0
	for i in 60 * 240:
		RF.auto_choose(w)
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "player_hit" and not bool(e.get("miss", false)):
				hits += 1
	print("  Henesys top-platform camper seed 15 (informational): %.1f s, %d hits, %s, Lv %d, HP %d, final platform %d" %
		[w.time, hits, w.state_name(), int(w.player_state.level), int(w.player_state.hp), w.player_platform()])
	assert_true(w.time > 0.0, "seeded informational run advanced")
	lib.free()
