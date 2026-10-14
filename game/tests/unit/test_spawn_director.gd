extends TestCase
## SpawnDirector (docs/GAME_DESIGN.md 4, 4.1): keyframe interpolation, pools, bursts, elites, spawn positions (never
## inside the view or out of bounds, never near the player, reachable platforms preferred) and recycling.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


## Left floor 300..1300 (y 0) ending at a 400 px wall; right floor 1300..3000 (y -10) behind it. Neither side can
## reach the other.
func _walled_world(left_x1 := 300.0, left_x2 := 1300.0) -> RunWorld:
	var segs := [
		{"x1": left_x1, "y1": 0.0, "x2": left_x2, "y2": 0.0},
		{"x1": 1300.0, "y1": 0.0, "x2": 1300.0, "y2": -400.0},
		{"x1": 1300.0, "y1": -10.0, "x2": 3000.0, "y2": -10.0},
		{"x1": 0.0, "y1": 60.0, "x2": 1.0, "y2": 60.0},
	]
	var s := RF.setup("quiet", 3, RF.quiet_data())
	s.map_img = RF.map_from_segments(segs)
	var w := RunWorld.new(s)
	RF.place_player(w, 800.0, -5.0)
	return w


func test_pacing_keyframes() -> void:
	var w := RunWorld.new(RF.setup("henesys_hg1"))
	var d := w.director
	assert_near(d.rate_at(0.0), 0.7, 1e-6)
	assert_near(d.rate_at(60.0), 1.35, 1e-6, "halfway to the 2:00 keyframe")
	assert_near(d.rate_at(120.0), 2.0, 1e-6)
	assert_eq(d.max_alive_at(0.0), 15)
	assert_eq(d.max_alive_at(60.0), 28, "round(27.5)")
	assert_near(d.value_at("hp", 180.0), 1.225, 1e-6, "halfway between 1.15 and 1.3")
	assert_near(d.value_at("speed", 900.0), 1.4, 1e-6)
	assert_near(d.rate_at(2000.0), 20.0, 1e-6, "held after the last keyframe")
	var early: PackedInt32Array = d.pool_at(60.0).kinds
	var snail := int(w.kind_of_id[100100])
	var blue := int(w.kind_of_id[100101])
	assert_eq(early.size(), 2, "Snail and Blue Snail only")
	assert_true(snail in early and blue in early)
	var two: PackedInt32Array = d.pool_at(130.0).kinds
	assert_true(int(w.kind_of_id[130101]) in two and int(w.kind_of_id[120100]) in two, "+ Red Snail, Shroom")
	assert_false(snail in d.pool_at(400.0).kinds, "Snails phase out at 6:00")
	assert_eq(d.burst_count_at(0.0), 10)
	assert_eq(d.burst_count_at(450.0), 25, "halfway from 10 to 40")
	assert_eq(d.burst_count_at(900.0), 40)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var n := {snail: 0, blue: 0}
	for i in 700:
		var k := d.pick_kind(10.0, rng)
		n[k] += 1
	assert_between(float(n[snail]) / 700.0, 0.51, 0.63, "weights 4:3")


func test_spawns_outside_view_inside_bounds_and_ramping() -> void:
	var w := RunWorld.new(RF.setup("henesys_hg1", 99))
	w.god = true
	var memo := {}
	var per_minute := PackedInt32Array()
	per_minute.resize(7)
	var alive_max := PackedInt32Array()
	alive_max.resize(7)
	var bursts: Array = []
	var elites := 0
	var checked := 0
	for t in 60 * 360:
		RF.auto_choose(w)
		w.step(DT, RF.bot_input(w, memo))
		var minute := mini(int(w.time / 60.0), 6)
		alive_max[minute] = maxi(alive_max[minute], w.swarm.alive_count())
		if w.time < 75.0 and w.swarm.alive_count() > w.director.max_alive_at(w.time):
			fail("alive %d over max_alive %d at %s" % [w.swarm.alive_count(), w.director.max_alive_at(w.time), w.time])
		for e: Dictionary in w.drain_events():
			if e.type == "burst":
				bursts.append([w.time, e.count])
			elif e.type == "mob_spawned":
				checked += 1
				per_minute[minute] += 1
				var pos: Vector2 = e.pos
				if w.view.grow(48.0).has_point(pos):
					fail("spawned inside the view at %s (view %s)" % [pos, w.view])
				if not w.bounds.has_point(pos):
					fail("spawned out of bounds at %s" % pos)
				if pos.distance_to(w.player.pos) < 200.0:
					fail("spawned %s px from the player" % pos.distance_to(w.player.pos))
				var f: int = w.swarm.fh[e.mob]
				assert_true(f >= 0 and absf(w.fhm.y_at(f, pos.x) - pos.y) < 0.01, "standing on a floor")
				if e.elite:
					elites += 1
					var mk: MobKind = w.mob_kinds[w.swarm.kind[e.mob]]
					assert_eq(w.swarm.max_hp[e.mob], roundi(mk.max_hp * w.director.value_at("hp", w.time) * 8.0),
						"elite x8 HP")
	assert_true(checked > 300, "plenty of spawns checked (%d)" % checked)
	assert_true(per_minute[5] > per_minute[0] * 2, "spawning ramps up: %s" % [per_minute])
	# The alive count is what the (god-mode) bot leaves alive, so it depends on its kill rate; the director's own ramp
	# is what must grow.
	assert_true(alive_max[5] > alive_max[0], "a bigger crowd in minute 6 than in minute 1: %s" % [alive_max])
	for m in 6:
		assert_true(w.director.max_alive_at(60.0 * (m + 1)) > w.director.max_alive_at(60.0 * m),
			"max_alive grows every minute (%d)" % m)
		assert_true(w.director.rate_at(60.0 * (m + 1)) > w.director.rate_at(60.0 * m), "spawn rate grows (%d)" % m)
	assert_eq(bursts.size(), 4, "bursts at 1:30, 3:00, 4:30, 6:00: %s" % [bursts])
	if bursts.size() == 4:
		assert_near(bursts[0][0], 90.0, DT * 1.5)
		assert_between(bursts[0][1], 10, 40)
	assert_eq(elites, 5, "elites at 1:15, 2:15, 3:15, 4:15, 5:15")


func test_prefers_platforms_that_reach_the_player() -> void:
	var w := _walled_world()
	var snail := int(w.kind_of_id[100100])
	var slime := int(w.kind_of_id[210100])
	var target := w.player_platform()
	assert_true(target >= 0)
	var inner := w.view.grow(48.0)
	for i in 100:
		for k: int in [snail, slime]:
			var p := w.director.pick_spawn(w, k)
			assert_true(p.z >= 0, "found a spot")
			var nav := w.nav_jump if k == slime else w.nav
			assert_true(nav.reachable(w.fhm.platform_of(int(p.z)), target),
				"spawned on a platform that reaches the player: %s" % p)
			assert_false(inner.has_point(Vector2(p.x, p.y)))


func test_falls_back_to_unreachable_when_nothing_else() -> void:
	# The player's floor lies entirely inside the view: only the far side of the wall is left.
	var w := _walled_world(420.0, 1300.0)
	RF.place_player(w, 860.0, -5.0)
	var inner := w.view.grow(48.0)
	assert_true(inner.has_point(Vector2(421, 0)) and inner.has_point(Vector2(1299, 0)), "setup: the floor is on screen")
	var p := w.director.pick_spawn(w, int(w.kind_of_id[100100]))
	assert_true(p.z >= 0, "still spawns")
	assert_false(inner.has_point(Vector2(p.x, p.y)), "outside the view")
	assert_near(p.y, -10.0, 1e-3, "on the far floor")


func test_recycles_unreachable_off_screen_and_far_mobs() -> void:
	var w := _walled_world()
	var stuck := RF.put_mob(w, 100100, 2400.0, -20.0)
	var near := RF.put_mob(w, 100100, 1200.0, -5.0, 100.0)
	var elite := RF.put_mob(w, 100100, 2600.0, -20.0, 1.0, true)
	for t in 60 * 4:
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.state[stuck], MobSwarm.FREE, "unreachable and off-screen: recycled")
	assert_true(w.swarm.active[near] != 0, "a mob that can reach the player stays")
	assert_true(w.swarm.active[elite] != 0, "elites are never recycled")
	assert_eq(w.director.recycled, 1)
	var big := RF.quiet_world(-900.0)
	var far := RF.put_mob(big, 100101, 2950.0)
	for t in 60 * 4:
		big.step(DT, MoveInput.new())
	assert_eq(big.swarm.state[far], MobSwarm.FREE, "3800 px away: recycled")


func test_prefer_hops_brings_spawns_near_and_stages_override_it() -> void:
	# Stage "spawn" overrides balance.json "spawn".
	var d := SpawnDirector.create({"spawn": {"prefer_hops": 0}}, {}, {"prefer_hops": 1, "band": 100.0})
	assert_eq(int(d.params.prefer_hops), 0, "the stage's own value wins")
	assert_eq(float(d.params.band), 100.0, "balance values the stage does not set stay")
	# On the big synthetic multi-platform map (every platform is at most one edge from the start platform, so the test
	# uses prefer_hops 0): spawns land on the player's own platform more often than with any reachable platform.
	var share := {}
	for prefer: int in [-1, 0]:
		var w := RunWorld.new(RF.setup("henesys_hg1", 31))
		w.director.params["prefer_hops"] = prefer
		var near := 0
		var total := 0
		for i in 300:
			var k := w.director.pick_kind(60.0, w.spawn_rng)
			var p := w.director.pick_spawn(w, k)
			if p.z < 0:
				continue
			total += 1
			var mk: MobKind = w.mob_kinds[k]
			var nav := w.nav_jump if mk.can_jump else w.nav
			var h := nav.hops(w.fhm.platform_of(int(p.z)), w.player_platform())
			if h == 0:
				near += 1
		share[prefer] = float(near) / maxf(1.0, total)
	print("prefer_hops share on the player's platform: any %.2f, prefer 0 %.2f" % [share[-1], share[0]])
	assert_true(float(share[0]) > float(share[-1]), "more spawns on the player's platform with prefer_hops 0 (%s)" % [share])


func test_stage_exp_mult_scales_drops() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet["exp_mult"] = 2.0
	var w := RunWorld.new(RF.setup("quiet", 7, data))
	RF.place_player(w, 400.0)
	var m := RF.put_mob(w, 100100, 430.0)
	var got_exp := 0
	for t in 240:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "mob_died" and int(e.mob) == m:
				got_exp = int(e.exp)
		if got_exp > 0:
			break
	assert_eq(got_exp, 2 * roundi(w.mob_kinds[w.kind_of_id[100100]].exp), "the stage's exp_mult doubles the Snail's EXP")
