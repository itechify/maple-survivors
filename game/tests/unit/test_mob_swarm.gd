extends TestCase
## MobKind.from_wz and MobSwarm movement/lifecycle on synthetic maps (fixed 1/60 s ticks, deterministic).

const WF := preload("res://tests/fixtures/world_fixtures.gd")
const DT := 1.0 / 60.0

## Kind indices used by these tests: 0 = fast walker (snail x4 speed), 1 = fast jumper (slime x2 speed).
var kinds: Array = []


func before_each() -> void:
	kinds = [
		MobKind.from_wz(WF.mob_img(false), 100100, {"speed_mult": 4.0}),
		MobKind.from_wz(WF.mob_img(true), 210100, {"speed_mult": 2.0}),
	]


func _ctx(m: FootholdMap, target: Vector2, target_fh: int) -> Dictionary:
	return {
		"fhm": m,
		"nav": NavGraph.build(m, {"can_jump": false}),
		"nav_jump": NavGraph.build(m, {"can_jump": true}),
		"bounds": MapBounds.from_map({}, m),
		"target": target,
		"target_fh": target_fh,
	}


func test_mob_kind_from_wz() -> void:
	var snail := MobKind.from_wz(WF.mob_img(false), 100100)
	assert_eq(snail.id, 100100)
	assert_eq(snail.level, 1)
	assert_eq(snail.max_hp, 8)
	assert_eq(snail.exp, 3)
	assert_eq(snail.pad, 12)
	assert_eq(snail.speed_stat, -65)
	assert_near(snail.move_speed, 21.875, 1e-6, "(speed + 100) x 0.625")
	assert_false(snail.can_jump, "no jump stance")
	assert_false(snail.flies)
	assert_eq(snail.hitbox, Rect2(-18, -26, 37, 26), "move/0 lt/rb")
	assert_near(snail.die_time, 8 * 0.12 + 0.3, 1e-6, "sum of die1 delays")
	assert_near(snail.hit_time, 0.24, 1e-9)
	assert_eq(snail.pushed, 1)
	assert_true(snail.body_attack)
	assert_eq(snail.hitbox_at(100, 50, -1), Rect2(82, 24, 37, 26), "facing left: as in WZ")
	assert_eq(snail.hitbox_at(100, 50, 1), Rect2(81, 24, 37, 26), "facing right: mirrored")
	var slime := MobKind.from_wz(WF.mob_img(true), 210100, {"name": "Slime", "hp_mult": 1.5, "speed_mult": 2.0,
		"exp_item": 4000010.0})
	assert_true(slime.can_jump, "jump stance")
	assert_eq(slime.name, "Slime")
	assert_eq(slime.max_hp, 75, "hp_mult")
	assert_near(slime.move_speed, 100.0, 1e-6, "(-20 + 100) x 0.625 x 2")
	assert_eq(slime.elem_attr, "L3")
	assert_eq(slime.exp_item, 4000010)
	var grounded := MobKind.from_wz(WF.mob_img(true), 210100, {"can_jump": false})
	assert_false(grounded.can_jump, "override")
	var img := WF.mob_img(false)
	img.die1["3"].erase("delay")
	assert_near(MobKind.from_wz(img, 1).die_time, 7 * 0.12 + 0.1 + 0.3, 1e-6, "missing delay = 100 ms")
	var flyer := WF.mob_img(false)
	flyer["fly"] = {"0": flyer.move["0"]}
	flyer.info["flySpeed"] = 20.0
	var fk := MobKind.from_wz(flyer, 2)
	assert_true(fk.flies)
	assert_near(fk.move_speed, 75.0, 1e-6, "flySpeed for flyers")
	var bare := MobKind.from_wz({}, 3)
	assert_eq(bare.hitbox, MobKind.DEFAULT_HITBOX)
	assert_near(bare.die_time, MobKind.DEFAULT_DIE_TIME)


func test_spawn_regen_fade_and_capacity_growth() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var s := MobSwarm.new(4, kinds)
	var ctx := _ctx(m, Vector2(600, 0), 0)
	var first := s.spawn(0, 1000.0, -50.0, 1)
	assert_eq(first, 0, "lowest slot first")
	s.step(DT, ctx)
	assert_near(s.y[first], 0.0, 1e-6, "snapped onto its foothold")
	assert_eq(s.platform[first], m.platform_of(1))
	assert_eq(s.hp[first], 8)
	assert_eq(s.max_hp[first], 8)
	assert_near(s.alpha[first], DT / 0.3, 1e-5, "regen fade-in starts at 0")
	for t in 8:
		s.step(DT, ctx)
	assert_between(s.alpha[first], 0.49, 0.51)
	assert_near(s.x[first], 1000.0, 1e-6, "stands still while fading in")
	for t in 12:
		s.step(DT, ctx)
	assert_near(s.alpha[first], 1.0, 1e-6)
	for i in 9:
		s.spawn(i % 2, 100.0 + i * 10.0, 0.0, 0, 20)
	assert_eq(s.alive_count(), 10)
	assert_true(s.capacity() >= 10, "grew past the initial capacity")
	assert_eq(s.hp[5], 20, "explicit hp")
	for i in s.capacity():
		if s.state[i] != MobSwarm.FREE:
			assert_eq(s.active[i], 1)


func test_mobs_approach_player_on_same_platform() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var s := MobSwarm.new(8, kinds)
	var ctx := _ctx(m, Vector2(300, 0), 0)
	for i in 5:
		s.spawn(0, 900.0 + i * 50.0, 0.0, 1)
	s.step(DT, ctx)
	var x0 := s.x[0]
	for t in 60:
		s.step(DT, ctx)
	# 1 s: 0.3 s regen, then 87.5 px/s.
	assert_between(x0 - s.x[0], 87.5 * 0.70, 87.5 * 0.74, "walks at move_speed")
	assert_eq(s.facing[0], -1, "faces its movement")
	assert_eq(s.state[0], MobSwarm.MOVE)
	for t in 900:
		s.step(DT, ctx)
	for i in 5:
		assert_near(s.x[i], 300.0, 2.0 + 1e-3, "reached the player")
		assert_eq(s.state[i], MobSwarm.STAND)
		assert_eq(s.fh[i], 0, "followed the chain onto the left ground foothold")


func test_walker_drops_to_lower_platform() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var s := MobSwarm.new(8, kinds)
	var ctx := _ctx(m, Vector2(200, 0), 0)
	var i := s.spawn(0, 550.0, -120.0, 4)
	var g := m.platform_of(0)
	var seen_air := false
	for t in 1200:
		s.step(DT, ctx)
		if s.fh[i] < 0:
			seen_air = true
			assert_eq(s.state[i], MobSwarm.JUMP)
		if s.platform[i] == g and absf(s.x[i] - 200.0) <= 2.0:
			break
	assert_true(seen_air, "fell")
	assert_eq(s.platform[i], g, "reached the ground platform by dropping")
	assert_near(s.x[i], 200.0, 2.0 + 1e-3, "then walked to the player")
	assert_eq(s.lost_count, 0)


func test_jumper_climbs_and_walker_wanders() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var s := MobSwarm.new(8, kinds)
	var ctx := _ctx(m, Vector2(550, -120), 4)
	var top := m.platform_of(4)
	var ground := m.platform_of(0)
	var jumper := s.spawn(1, 1100.0, 0.0, 1)
	var walker := s.spawn(0, 1100.0, 0.0, 1)
	var jumped := false
	var walker_dirs := {}
	var walker_min_x := INF
	var walker_max_x := -INF
	for t in 1800:
		s.step(DT, ctx)
		if s.state[jumper] == MobSwarm.JUMP and s.vy[jumper] < 0.0:
			jumped = true
		assert_eq(s.platform[walker], ground, "a walker never leaves the ground for a higher platform")
		walker_dirs[s.facing[walker]] = true
		walker_min_x = minf(walker_min_x, s.x[walker])
		walker_max_x = maxf(walker_max_x, s.x[walker])
	assert_true(jumped, "the jumper hopped")
	assert_eq(s.platform[jumper], top, "jumper reached the top platform")
	assert_near(s.x[jumper], 550.0, 2.0 + 1e-3)
	assert_eq(walker_dirs.size(), 2, "the unreachable walker patrols both ways")
	assert_true(walker_max_x - walker_min_x > 500.0, "and covers its platform (%s..%s)" % [walker_min_x, walker_max_x])


func test_invariants_with_many_mobs() -> void:
	for map_name: String in ["tiers", "cliff", "block"]:
		var segs: Array = WF.tiers_segments() if map_name == "tiers" else (WF.cliff_segments() if map_name == "cliff" 			else WF.block_segments())
		var m := FootholdMap.from_segments(segs)
		var ctx := _ctx(m, Vector2.ZERO, -1)
		var bounds: Rect2 = ctx.bounds
		var s := MobSwarm.new(16, kinds)
		var rng := RandomNumberGenerator.new()
		rng.seed = 12345
		var floors: Array = []
		for f in m.count():
			if m.is_floor(f):
				floors.append(f)
		for n in 80:
			var f: int = floors[rng.randi_range(0, floors.size() - 1)]
			s.spawn(n % 2, rng.randf_range(m.x1[f], m.x2[f]), 0.0, f)
		s.step(DT, ctx)  # snaps the spawns (given y 0) onto their footholds: not motion, so not checked
		var px := PackedFloat32Array()
		var py := PackedFloat32Array()
		var alive_before := PackedByteArray()
		for t in 1800:
			if t % 120 == 0:
				var f: int = floors[rng.randi_range(0, floors.size() - 1)]
				var tx := rng.randf_range(m.x1[f], m.x2[f])
				ctx.target = Vector2(tx, m.y_at(f, tx))
				ctx.target_fh = f
			if t % 97 == 0:
				var victim := rng.randi_range(0, s.capacity() - 1)
				if s.apply_hit(victim, 3, 1 if rng.randf() < 0.5 else -1):
					s.spawn(victim % 2, m.x1[floors[0]] + 5.0, 0.0, floors[0])
			px = s.x.duplicate()
			py = s.y.duplicate()
			alive_before = s.active.duplicate()
			s.step(DT, ctx)
			for v in WF.swarm_violations(s, m, bounds, px, py, alive_before, "%s tick %d" % [map_name, t]):
				fail(v)
		assert_eq(s.lost_count, 0, "%s: nobody fell out of the world" % map_name)
		assert_true(s.alive_count() > 70, "%s: hits only killed a few" % map_name)


func test_cliff_jumper_hops_over_the_wall() -> void:
	var m := FootholdMap.from_segments(WF.cliff_segments())
	var s := MobSwarm.new(4, kinds)
	var ctx := _ctx(m, Vector2(400, -50), 2)
	var j := s.spawn(1, 50.0, 0.0, 0)
	var w := s.spawn(0, 60.0, 0.0, 0)
	for t in 900:
		s.step(DT, ctx)
		assert_true(s.x[w] < 200.0, "the walker stays below the cliff")
	assert_eq(s.platform[j], m.platform_of(2), "the jumper is on the upper floor")
	assert_near(s.x[j], 400.0, 2.0 + 1e-3)


func test_drop_onto_narrow_ledge_never_overshoots_into_void() -> void:
	# A high floor whose right end overhangs a 10 px ledge with nothing else below; ground far to the left and a
	# floor high up on the right, so the map's horizontal limit is not what stops the mob.
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": -200.0, "x2": 200.0, "y2": -200.0},
		{"x1": 204.0, "y1": -100.0, "x2": 214.0, "y2": -100.0},
		{"x1": -600.0, "y1": 0.0, "x2": -100.0, "y2": 0.0},
		{"x1": 400.0, "y1": -300.0, "x2": 600.0, "y2": -300.0},
	])
	var ledge := m.platform_of(1)
	var s := MobSwarm.new(4, kinds)
	var ctx := _ctx(m, Vector2(210, -100), 1)
	var i := s.spawn(1, 150.0, -200.0, 0)
	for t in 600:
		s.step(DT, ctx)
	assert_eq(s.lost_count, 0)
	assert_eq(s.state[i] != MobSwarm.FREE, true)
	assert_eq(s.platform[i], ledge, "landed on the narrow ledge despite 100 px/s of walk speed")


func test_death_frees_slot_after_die_time() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var s := MobSwarm.new(4, kinds)
	var ctx := _ctx(m, Vector2(600, 0), 0)
	var a := s.spawn(0, 500.0, 0.0, 0)
	var b := s.spawn(0, 520.0, 0.0, 0)
	s.step(DT, ctx)
	assert_eq(s.alive_count(), 2)
	assert_false(s.apply_hit(a, 3, 1), "8 hp survives 3")
	assert_eq(s.hp[a], 5)
	assert_true(s.apply_hit(a, 10, 1), "killing blow")
	assert_eq(s.hp[a], 0)
	assert_eq(s.state[a], MobSwarm.DIE)
	assert_eq(s.active[a], 0)
	assert_eq(s.alive_count(), 1)
	assert_false(s.apply_hit(a, 10, 1), "dying mobs ignore hits")
	var die_time: float = kinds[0].die_time
	var ticks := int(floor(die_time / DT)) - 1
	for t in ticks:
		s.step(DT, ctx)
	assert_eq(s.state[a], MobSwarm.DIE, "still dying before die_time")
	for t in 3:
		s.step(DT, ctx)
	assert_eq(s.state[a], MobSwarm.FREE, "freed after die_time")
	assert_eq(s.spawn(1, 300.0, 0.0, 0), a, "slot reused")
	assert_eq(s.alive_count(), 2)
	assert_eq(s.state[b], MobSwarm.MOVE if absf(s.x[b] - 600.0) > 2.0 else MobSwarm.STAND)


func test_hit_stun_and_push() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var s := MobSwarm.new(4, kinds)
	var ctx := _ctx(m, Vector2(500, 0), 0)
	var i := s.spawn(0, 500.0, 0.0, 0)
	for t in 30:
		s.step(DT, ctx)
	assert_eq(s.state[i], MobSwarm.STAND)
	assert_false(s.apply_hit(i, 1, 1))
	assert_eq(s.state[i], MobSwarm.HIT)
	assert_eq(s.facing[i], -1, "turns toward the blow")
	for t in 14:  # 0.233 s < 0.24 s stun
		s.step(DT, ctx)
	assert_eq(s.state[i], MobSwarm.HIT, "stunned")
	assert_near(s.x[i] - 500.0, 12.0 * 14.0 / 60.0 / 0.24, 0.05, "pushed along the floor")
	s.step(DT, ctx)
	assert_ne(s.state[i], MobSwarm.HIT, "stun over after 0.24 s")
	assert_between(s.x[i] - 500.0, 11.0, 12.5, "about 12 px in total")
	# Below `pushed` there is a stun but no push.
	var tough: Array = [MobKind.from_wz(WF.mob_img(false), 1)]
	tough[0].pushed = 50
	var s2 := MobSwarm.new(2, tough)
	var j := s2.spawn(0, 500.0, 0.0, 0)
	for t in 30:
		s2.step(DT, ctx)
	s2.apply_hit(j, 5, -1)
	for t in 10:
		s2.step(DT, ctx)
	assert_eq(s2.state[j], MobSwarm.HIT)
	assert_near(s2.x[j], 500.0, 1e-4, "no push below the pushed threshold")


func test_flying_mob_heads_for_player() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var img := WF.mob_img(false)
	img["fly"] = {"0": img.move["0"]}
	var s := MobSwarm.new(2, [MobKind.from_wz(img, 9, {"speed_mult": 4.0})])
	var ctx := _ctx(m, Vector2(100, -100), -1)
	var i := s.spawn(0, 800.0, -300.0, -1)
	for t in 1200:
		s.step(DT, ctx)
	assert_near(Vector2(s.x[i], s.y[i]).distance_to(Vector2(100, -100)), 0.0, 2.5, "flew to the player")
	assert_eq(s.fh[i], -1)


## Runs one mob of kind k[0] at `smult` x its speed from x0 on platform from_p toward (tx on platform to_p) and
## returns the platform of its first landing after leaving the ground (-1 = never left or never landed).
func _first_landing(m: FootholdMap, k: Array, from_p: int, x0: float, to_p: int, tx: float, smult: float) -> int:
	var s := MobSwarm.new(2, k)
	var tf := m.platform_fh_at(to_p, tx)
	var ctx := _ctx(m, Vector2(tx, m.y_at(tf, tx)), tf)
	ctx["speed_mult"] = smult
	var i := s.spawn(0, x0, 0.0, m.platform_fh_at(from_p, x0))
	var left := false
	for t in 3600:
		s.step(DT, ctx)
		if s.fh[i] < 0:
			left = true
		elif left:
			return s.platform[i]
		if s.state[i] == MobSwarm.FREE:
			return -1
	return -1


func test_drops_land_where_the_graph_says_at_any_speed() -> void:
	# The lower floor starts 3 px past the upper end: before the fix a slow mob, keeping its walk speed while
	# falling, missed it. Now the step-off is the same for every mob, so every speed lands on it.
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 200.0, "y2": 0.0},
		{"x1": 203.0, "y1": 10.0, "x2": 400.0, "y2": 10.0},
		{"x1": -200.0, "y1": 300.0, "x2": 800.0, "y2": 300.0},
	])
	var low := m.platform_of(1)
	var k: Array = [MobKind.from_wz(WF.mob_img(false), 100100)]  # Snail, 21.875 px/s
	for smult: float in [0.25, 1.0, 3.0, 12.0]:
		assert_eq(_first_landing(m, k, m.platform_of(0), 150.0, low, 350.0, smult), low,
			"speed x%s lands on the ledge" % smult)
	# Every drop edge of the tier map, for walkers of very different speeds.
	var tm := FootholdMap.from_segments(WF.tiers_segments())
	var nav := NavGraph.build(tm, {"can_jump": false})
	for e in nav.edge_count():
		var d := nav.edge(e)
		var sp := tm.platform_span(d.from_p)
		var x0: float = clampf(d.x_from - signf(d.vx) * 20.0, sp.x + 1.0, sp.y - 1.0)
		var tsp := tm.platform_span(d.to_p)
		for smult: float in [0.25, 1.0, 12.0]:
			assert_eq(_first_landing(tm, k, d.from_p, x0, d.to_p, (tsp.x + tsp.y) * 0.5, smult), d.to_p,
				"edge %s at speed x%s" % [d, smult])


func test_free_standing_wall_blocks_walking_and_pushes() -> void:
	# One floor foothold with a wall standing across it (not linked into the chain).
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 400.0, "y2": 0.0, "prev": -1, "next": -1},
		{"x1": 200.0, "y1": -60.0, "x2": 200.0, "y2": 10.0, "prev": -1, "next": -1},
	])
	assert_eq(m.floor_wall[0], 1, "the floor is flagged")
	assert_eq(m.platform_count(), 1)
	var s := MobSwarm.new(4, kinds)
	var ctx := _ctx(m, Vector2(350, 0), 0)
	var i := s.spawn(0, 150.0, 0.0, 0)
	for t in 300:
		s.step(DT, ctx)
		assert_true(s.x[i] < 200.0, "the walker never passes the wall")
	assert_near(s.x[i], 200.0, 0.05, "pushes against it")
	# A hit pushing it into the wall stops there too.
	s.apply_hit(i, 1, 1)
	for t in 20:
		s.step(DT, ctx)
	assert_true(s.x[i] < 200.0, "the push stops at the wall")
	# A patrolling mob (target unreachable) turns around at the wall.
	var flat := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 400.0, "y2": 0.0, "prev": -1, "next": -1},
		{"x1": 200.0, "y1": -60.0, "x2": 200.0, "y2": 10.0, "prev": -1, "next": -1},
		{"x1": 600.0, "y1": -200.0, "x2": 700.0, "y2": -200.0, "prev": -1, "next": -1},
	])
	var s2 := MobSwarm.new(4, kinds)
	var ctx2 := _ctx(flat, Vector2(650, -200), 2)
	var j := s2.spawn(0, 100.0, 0.0, 0)
	var dirs := {}
	for t in 900:
		s2.step(DT, ctx2)
		assert_true(s2.x[j] < 200.0, "the patrol stays left of the wall")
		if s2.state[j] == MobSwarm.MOVE:
			dirs[s2.facing[j]] = true
	assert_eq(dirs.size(), 2, "and turns at it")


func test_kind_edits_apply_on_the_next_step() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var k: Array = [MobKind.from_wz(WF.mob_img(false), 100100)]
	var s := MobSwarm.new(2, k)
	var ctx := _ctx(m, Vector2(100, 0), 0)
	var i := s.spawn(0, 1000.0, 0.0, 1)
	for t in 30:
		s.step(DT, ctx)
	var x0 := s.x[i]
	s.step(DT, ctx)
	assert_near(x0 - s.x[i], 21.875 / 60.0, 1e-4, "base speed")
	k[0].move_speed = 100.0
	x0 = s.x[i]
	s.step(DT, ctx)
	assert_near(x0 - s.x[i], 100.0 / 60.0, 1e-4, "edited speed used at once")
	var fast := MobKind.from_wz(WF.mob_img(false), 100100, {"speed_mult": 2.0})
	k[0] = fast
	x0 = s.x[i]
	s.step(DT, ctx)
	assert_near(x0 - s.x[i], 43.75 / 60.0, 1e-4, "replaced kind used at once")
	fast.pushed = 99
	var hx := s.x[i]
	s.apply_hit(i, 5, 1)
	for t in 5:
		s.step(DT, ctx)
	assert_near(s.x[i], hx, 1e-4, "edited pushed threshold applies to the next hit")


func test_swarm_is_deterministic() -> void:
	var m := FootholdMap.from_segments(WF.tiers_segments())
	var runs: Array = []
	for r in 2:
		var s := MobSwarm.new(8, kinds)
		var ctx := _ctx(m, Vector2(550, -120), 4)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for n in 40:
			var f := rng.randi_range(0, 4)
			s.spawn(n % 2, rng.randf_range(m.x1[f], m.x2[f]), 0.0, f)
		for t in 900:
			if t % 150 == 0:
				var f := rng.randi_range(0, 4)
				var tx := rng.randf_range(m.x1[f], m.x2[f])
				ctx.target = Vector2(tx, m.y_at(f, tx))
				ctx.target_fh = f
			if t % 61 == 0:
				s.apply_hit(rng.randi_range(0, s.capacity() - 1), 3, 1)
			s.step(DT, ctx)
		runs.append([s.x, s.y, s.state, s.fh, s.hp])
	for a in 5:
		assert_eq(runs[0][a], runs[1][a], "array %d identical" % a)


func test_jumper_hops_onto_a_solid_block_from_beside_it() -> void:
	var m := FootholdMap.from_segments(WF.block_segments())
	var s := MobSwarm.new(4, kinds)
	var ctx := _ctx(m, Vector2(300, -60), 1)
	var bounds: Rect2 = ctx.bounds
	var j := s.spawn(1, 300.0, 0.0, 0)  # under the block
	for t in 900:
		var px := s.x.duplicate()
		var py := s.y.duplicate()
		var was := s.active.duplicate()
		s.step(DT, ctx)
		for v in WF.swarm_violations(s, m, bounds, px, py, was, "block tick %d" % t):
			fail(v)
		if s.x[j] > 200.0 and s.x[j] < 400.0 and s.y[j] > -60.0 + 0.05 and s.y[j] < -40.0 - 0.05:
			fail("inside the block at (%s, %s)" % [s.x[j], s.y[j]])
	assert_eq(s.platform[j], m.platform_of(1), "on the block top")
	assert_near(s.x[j], 300.0, 2.0 + 1e-3)
	# A mob launched upward under the block bumps into its underside and falls back to the ground.
	var b := s.spawn(0, 300.0, -1.0, -1)
	s.vy[b] = -555.0
	var top := 0.0
	for t in 120:
		s.step(DT, ctx)
		top = minf(top, s.y[b])
	assert_between(top, -40.0, -39.9, "stopped at the underside (y -40)")
	assert_eq(s.platform[b], m.platform_of(0), "back on the ground")
