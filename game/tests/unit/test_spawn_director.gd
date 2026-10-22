extends TestCase
## SpawnDirector (docs/GAME_DESIGN.md 4, 4.1): keyframe interpolation, pools, bursts, elites, spawn positions (never
## inside the view or out of bounds, never near the player, reachable platforms and short ways in preferred, never
## where a wall across a platform stands on the way, further out behind a moving player) and relocation of far,
## unreachable and stalled off-screen mobs (a mob stopped at a wall stalls even while the player walks up to it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const WF := preload("res://tests/fixtures/world_fixtures.gd")
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
	var w := RunWorld.new(RF.setup("henesys"))
	var d := w.director
	assert_near(d.rate_at(0.0), 0.25, 1e-6, "owner's #241 opening")
	assert_near(d.rate_at(60.0), 0.4, 1e-6, "halfway from 0.25 to 0.55 at the 2:00 keyframe")
	assert_near(d.rate_at(120.0), 0.55, 1e-6)
	assert_eq(d.max_alive_at(0.0), 6)
	assert_eq(d.max_alive_at(60.0), 9, "round((6+11)/2)")
	assert_near(d.value_at("hp", 120.0), 1.0, 1e-6, "opening HP stays flat before the ramp after 2:00")
	assert_near(d.value_at("hp", 270.0), 1.125, 1e-6, "halfway between 4:00 HP 1.0 and 5:00 HP 1.25")
	assert_near(d.value_at("speed", 900.0), 1.4, 1e-6)
	assert_true(d.rate_at(2000.0) > 20.0, "boss stages keep ramping after the final arrival")
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
	var w := RunWorld.new(RF.setup("henesys", 99))
	w.director.params.platform_share = 0.0  # This test exercises the off-screen ring rule; platform placement is separate.
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
				if w.mob_boss[int(e.mob)] >= 0:
					continue # Boss arrivals deliberately use the visible, near-player placement rule.
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
				var mob_kind: MobKind = w.mob_kinds[w.swarm.kind[e.mob]]
				if mob_kind.flies:
					assert_eq(f, -1, "flyers spawn in air")
				else:
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
	assert_eq(bursts.size(), 1, "Henesys bursts wait for 5:00, after the Beginner phase: %s" % [bursts])
	if bursts.size() == 1:
		assert_near(bursts[0][0], 300.0, DT * 1.5)
		assert_between(bursts[0][1], 10, 40)
	assert_eq(elites, 3, "Henesys elites at 4:00, 5:00, 6:00")


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


func test_relocates_unreachable_off_screen_and_far_mobs() -> void:
	var w := _walled_world()
	var stuck := RF.put_mob(w, 100100, 2400.0, -20.0)
	w.swarm.hp[stuck] = 5
	var near := RF.put_mob(w, 100100, 1200.0, -5.0, 100.0)
	var elite := RF.put_mob(w, 100100, 2600.0, -20.0, 1.0, true)
	w.drain_events()
	var moved: Array = []
	for t in 60 * 4:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "mob_spawned":
				moved.append(e)
	assert_eq(w.director.relocated, 1, "the unreachable off-screen mob was relocated")
	assert_eq(w.director.recycled, 0, "not recycled: there was a point to move it to")
	assert_eq(moved.size(), 1, "one mob_spawned for the relocation")
	if moved.size() == 1:
		assert_eq(int(moved[0].relocated_from), stuck, "mob_spawned.relocated_from is the old slot")
	if moved.size() == 1:
		var j: int = moved[0].mob
		var pos: Vector2 = moved[0].pos
		assert_eq(int(moved[0].mob_id), 100100, "the same kind")
		assert_false(moved[0].elite)
		assert_false(w.view.grow(48.0).has_point(pos), "never on screen (%s)" % pos)
		assert_true(w.nav.reachable(w.fhm.platform_of(w.swarm.fh[j]), w.player_platform()), "now it can reach the player")
		assert_eq(w.swarm.hp[j], 5, "keeps its HP")
		assert_eq(w.swarm.max_hp[j], roundi(w.mob_kinds[w.kind_of_id[100100]].max_hp), "and its max HP")
	assert_true(w.swarm.active[near] != 0, "a mob that can reach the player stays")
	assert_true(w.swarm.active[elite] != 0 and w.swarm.x[elite] > 2000.0, "elites are never moved")
	var big := RF.quiet_world(-900.0)
	var far := RF.put_mob(big, 100101, 2950.0)
	for t in 60 * 4:
		big.step(DT, MoveInput.new())
	assert_eq(big.director.relocated, 1, "3800 px away: relocated")
	assert_true(Vector2(big.swarm.x[far], big.swarm.y[far]).distance_to(big.player.pos) < 1300.0,
		"near the player now (%s, %s)" % [big.swarm.x[far], big.swarm.y[far]])


## A flat floor 0..6000 (y 0) with the player at x, stage "quiet" (no spawns of its own), god mode.
func _flat_world(x: float) -> RunWorld:
	var s := RF.setup("quiet", 5, RF.quiet_data())
	s.map_img = RF.map_from_segments([{"x1": 0.0, "y1": 0.0, "x2": 6000.0, "y2": 0.0}])
	var w := RunWorld.new(s)
	w.god = true
	RF.place_player(w, x, -5.0)
	return w


func test_relocates_mobs_left_behind_ahead_of_the_player() -> void:
	# A Snail (22 px/s) 600 px behind a player walking right (125 px/s) never closes in: after stall_time s it is
	# moved to a point ahead of the player, off-screen, with its HP. A mob that closes in is left alone.
	var w := _flat_world(1000.0)
	var stall := float(w.director.params.stall_time)
	assert_true(stall > 0.0, "stall relocation is on in balance.json")
	var slow := RF.put_mob(w, 100100, 400.0, -5.0)
	w.swarm.hp[slow] = 3
	w.drain_events()
	var walk := MoveInput.new()
	walk.right = true
	var first := {}
	var t_first := -1.0
	var px_first := 0.0
	var hp_first := -1
	for t in roundi(60 * (stall + 2.0)):
		w.step(DT, walk)
		for e: Dictionary in w.drain_events():
			if e.type == "mob_spawned" and first.is_empty():
				first = e
				t_first = w.time
				px_first = w.player.pos.x
				hp_first = w.swarm.hp[int(e.mob)]
	assert_false(first.is_empty(), "relocated")
	if first.is_empty():
		return
	assert_between(t_first, stall, stall + 1.0, "after stall_time s without closing in")
	var pos: Vector2 = first.pos
	assert_true(pos.x > px_first + 448.0, "ahead of the player walking right, off-screen (%s vs %s)" % [pos.x, px_first])
	assert_eq(hp_first, 3, "keeps its HP")
	assert_eq(w.director.spawned, 0, "a relocation is not a spawn")
	# Standing still, a mob walking in from off-screen keeps closing in and is never moved.
	var w2 := _flat_world(1000.0)
	RF.put_mob(w2, 1210100, 1700.0, -5.0)
	for t in 60 * 8:
		w2.step(DT, MoveInput.new())
	assert_eq(w2.director.relocated, 0, "a mob that comes closer stays")


func test_relocates_a_mob_stopped_at_a_wall_while_the_player_walks_up() -> void:
	# A Snail pressed against the left face of a block across the ground (walls at x 1000 and 1400) while the player
	# walks up to the block from the right: its way left shrinks with every step the player takes, but the mob itself
	# does not move, so it is relocated after stall_time s off-screen. Control: on open ground a mob walking toward a
	# player who walks toward it comes closer by itself and is left alone.
	var segs := [
		{"x1": 0.0, "y1": 0.0, "x2": 1000.0, "y2": 0.0},
		{"x1": 1000.0, "y1": 0.0, "x2": 1400.0, "y2": 0.0},
		{"x1": 1400.0, "y1": 0.0, "x2": 3000.0, "y2": 0.0},
		{"x1": 1000.0, "y1": -120.0, "x2": 1000.0, "y2": 40.0},
		{"x1": 1400.0, "y1": 40.0, "x2": 1400.0, "y2": -120.0},
		{"x1": 1000.0, "y1": -120.0, "x2": 1400.0, "y2": -120.0},
	]
	var s := RF.setup("quiet", 4, RF.quiet_data())
	s.map_img = RF.map_from_segments(segs)
	var w := RunWorld.new(s)
	w.god = true
	RF.place_player(w, 2200.0, -5.0)
	var stall := float(w.director.params.stall_time)
	var m := RF.put_mob(w, 100100, 985.0, -5.0)
	w.drain_events()
	var walk := MoveInput.new()
	walk.left = true
	var moved_at := -1.0
	var min_off := INF
	for t in roundi(60 * (stall + 2.0)):
		if moved_at < 0.0:
			# Measured before the step: after the relocating step slot m holds the moved mob.
			min_off = minf(min_off, w.view.grow(48.0 + float(w.director.params.trail_margin)).position.x - w.swarm.x[m])
		w.step(DT, walk)
		for e: Dictionary in w.drain_events():
			if e.type == "mob_spawned" and int(e.relocated_from) == m and moved_at < 0.0:
				moved_at = w.time
	assert_true(min_off > 0.0, "setup: the mob stays off-screen (%s px)" % min_off)
	assert_between(moved_at, stall, stall + 1.5, "relocated after stall_time s at the wall (at %s s)" % moved_at)
	var w2 := _flat_world(2200.0)
	RF.put_mob(w2, 100100, 1000.0, -5.0)
	for t in 60 * 4:
		w2.step(DT, walk)
	assert_eq(w2.director.relocated, 0, "a mob closing in by itself while the player walks up stays")


func test_trail_margin_keeps_spawns_off_the_lagging_camera_side() -> void:
	# The camera lags behind a running player, so the side it runs away from shows trail_margin px more: no spawn
	# there while the player moves; standing still, that strip is used.
	var trail := 0.0
	var hits := {}
	for vx: float in [125.0, 0.0]:
		var w := _flat_world(3000.0)
		trail = float(w.director.params.trail_margin)
		w.player.vel.x = vx
		var lo := w.view.position.x - 48.0 - trail
		var hi := w.view.position.x - 48.0
		hits[vx] = 0
		for i in 300:
			var p := w.director.pick_spawn(w, int(w.kind_of_id[100100]))
			assert_true(p.z >= 0)
			if p.x >= lo and p.x < hi:
				hits[vx] = int(hits[vx]) + 1
	assert_true(trail > 0.0, "trail_margin is on in balance.json")
	assert_eq(int(hits[125.0]), 0, "running right: nothing in the %s px behind the view + margin" % trail)
	assert_true(int(hits[0.0]) > 0, "standing: that strip is a spawn spot (%s)" % [hits])


func test_prefer_route_brings_spawns_in_on_short_ways() -> void:
	# Stage "spawn" overrides balance.json "spawn".
	var d := SpawnDirector.create({"spawn": {"prefer_route": -1}}, {}, {"prefer_route": 160, "band": 100.0})
	assert_eq(float(d.params.prefer_route), -1.0, "the stage's own value wins")
	assert_eq(float(d.params.band), 100.0, "balance values the stage does not set stay")
	# The long-platform map (WF.long_platform_segments): the player on the ground under the right part of a 1900 px
	# platform 300 px up. With prefer_route every spawn has a way in no longer than the walk in from beside the view +
	# prefer_route; without it, points on the long platform whose way in leads off to its far end also serve.
	var worst := {}
	for prefer: float in [-1.0, 160.0]:
		var s := RF.setup("quiet", 9, RF.quiet_data())
		s.map_img = RF.map_from_segments(WF.long_platform_segments())
		var w := RunWorld.new(s)
		RF.place_player(w, 1500.0, -5.0)
		w.director.params["prefer_route"] = prefer
		w.director.params["platform_share"] = 0.0
		w.director.params["band_y"] = -1.0
		var budget := w.view.size.x * 0.5 + 48.0 + 160.0
		worst[prefer] = 0.0
		for i in 200:
			var p := w.director.pick_spawn(w, int(w.kind_of_id[100100]))
			assert_true(p.z >= 0, "found a spot")
			w.nav.prepare_target(w.player_platform(), w.player.pos.x)
			var c := w.nav.route_cost(w.fhm.platform_of(int(p.z)), p.x)
			assert_true(c < INF, "reachable")
			worst[prefer] = maxf(float(worst[prefer]), c)
		if prefer > 0.0:
			assert_true(float(worst[prefer]) <= budget + 1e-3, "every way in within %s px (worst %s)" % [budget, worst[prefer]])
	assert_true(float(worst[-1.0]) > float(worst[160.0]), "without the preference some ways in are longer: %s" % [worst])


func test_never_spawns_behind_a_wall_across_the_platform() -> void:
	# The ground runs on under a solid block (walls at x 1000 and 1400 crossing it): no spawn inside it.
	var segs := [
		{"x1": 0.0, "y1": 0.0, "x2": 1000.0, "y2": 0.0},
		{"x1": 1000.0, "y1": 0.0, "x2": 1400.0, "y2": 0.0},
		{"x1": 1400.0, "y1": 0.0, "x2": 3000.0, "y2": 0.0},
		{"x1": 1000.0, "y1": -120.0, "x2": 1000.0, "y2": 40.0},
		{"x1": 1400.0, "y1": 40.0, "x2": 1400.0, "y2": -120.0},
		{"x1": 1000.0, "y1": -120.0, "x2": 1400.0, "y2": -120.0},
		{"x1": 300.0, "y1": -200.0, "x2": 800.0, "y2": -200.0},
	]
	var s := RF.setup("quiet", 4, RF.quiet_data())
	s.map_img = RF.map_from_segments(segs)
	var w := RunWorld.new(s)
	RF.place_player(w, 1700.0, -5.0)
	var ground := w.fhm.platform_of(w.fhm.find_below(1700.0, -5.0))
	# A platform above the buried side: its own walk to a drop is open, but it drops onto the ground behind the block,
	# so its whole way is walled (the check follows the way onto the player's platform).
	var upper := w.fhm.platform_of(w.fhm.find_below(500.0, -205.0))
	w.nav.prepare_target(ground, w.player.pos.x)
	assert_true(w.nav.route_cost(upper, 500.0) < INF, "setup: the graph routes the upper platform to the player")
	assert_true(w.director._walled(w, w.nav, upper, 500.0, ground), "its way ends at the block's face")
	assert_false(w.director._walled(w, w.nav, ground, 2500.0, ground), "open ground to the player")
	assert_eq(w.fhm.platform_of(w.fhm.find_below(1200.0, -5.0)), ground, "setup: one ground chain under the block")
	assert_true(w.fhm.walk_blocked(ground, 1200.0, 2000.0), "the block's face stops a walker")
	assert_false(w.fhm.walk_blocked(ground, 1500.0, 2900.0), "open ground")
	var inside := 0
	for i in 300:
		var p := w.director.pick_spawn(w, int(w.kind_of_id[100100]))
		assert_true(p.z >= 0)
		if (p.x > 1000.0 and p.x < 1400.0 and p.y > -1.0) or p.y < -150.0:
			inside += 1
	assert_eq(inside, 0, "no spawn inside the block or on the platform whose way ends at it")


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
