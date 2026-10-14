extends TestCase
## NavGraph: drop and jump edges and next-hop routes on synthetic maps.

const WF := preload("res://tests/fixtures/world_fixtures.gd")

var m: FootholdMap
var g_: int
var m1: int
var m2: int
var t_: int


func before_each() -> void:
	m = FootholdMap.from_segments(WF.tiers_segments())
	g_ = m.platform_of(0)
	m1 = m.platform_of(2)
	m2 = m.platform_of(3)
	t_ = m.platform_of(4)


func test_three_tier_drop_edges() -> void:
	assert_eq(m.platform_count(), 4)
	assert_eq(m.platform_of(1), g_, "the two ground footholds form one platform")
	var nav := NavGraph.build(m, {"can_jump": false})
	assert_eq(nav.node_count, 4)
	var drops := {}
	for e in nav.edge_count():
		var d := nav.edge(e)
		assert_eq(d.kind, "drop", "walkers only get drops")
		drops["%d>%d@%d" % [d.from_p, d.to_p, int(d.x_from)]] = true
	assert_has(drops, "%d>%d@100" % [m1, g_], "M1 left end")
	assert_has(drops, "%d>%d@400" % [m1, g_], "M1 right end")
	assert_has(drops, "%d>%d@700" % [m2, g_])
	assert_has(drops, "%d>%d@1000" % [m2, g_])
	assert_has(drops, "%d>%d@350" % [t_, m1], "T left end lands on M1")
	assert_has(drops, "%d>%d@750" % [t_, m2], "T right end lands on M2")
	assert_eq(nav.edge_count(), 6, "the ground's outer ends have nothing below")


func test_walker_routes_down_but_not_up() -> void:
	var nav := NavGraph.build(m, {"can_jump": false})
	var e := nav.route(t_, g_)
	assert_true(e >= 0, "top reaches ground")
	var d := nav.edge(e)
	assert_eq(d.kind, "drop")
	assert_eq(d.from_p, t_)
	assert_true(d.to_p == m1 or d.to_p == m2)
	assert_eq(nav.route(g_, t_), -1, "no way up without jumping")
	assert_false(nav.reachable(g_, m1))
	assert_false(nav.reachable(g_, t_))
	assert_true(nav.reachable(m1, g_))
	assert_true(nav.reachable(t_, g_))
	assert_true(nav.reachable(g_, g_))
	assert_eq(nav.route(g_, g_), -1, "same platform has no edge")
	assert_eq(nav.route(-1, g_), -1)


func test_jumper_routes_up_through_middle_tier() -> void:
	var nav := NavGraph.build(m, {"can_jump": true})
	var e := nav.route(g_, t_)
	assert_true(e >= 0, "ground reaches top")
	var d := nav.edge(e)
	assert_eq(d.kind, "jump")
	assert_true(d.to_p == m1 or d.to_p == m2, "via a middle platform")
	var e2 := nav.route(d.to_p, t_)
	assert_true(e2 >= 0)
	var d2 := nav.edge(e2)
	assert_eq(d2.kind, "jump")
	assert_eq(d2.to_p, t_)
	# Overlapping platforms give a straight-up takeoff range inside both spans with the margin.
	var up := nav.edge(nav.route(m1, t_))
	assert_between(up.lo, 358.0, 392.0, "takeoff range inside the M1/T overlap")
	assert_between(up.hi, 358.0, 392.0)
	assert_near(up.vx, 0.0)
	var gm1 := nav.edge(nav.route(g_, m1))
	assert_between(gm1.lo, 108.0, 120.0, "the whole M1 span (minus margin) is a takeoff range")
	assert_between(gm1.hi, 380.0, 392.0)
	assert_near(gm1.x_from, gm1.x_to, 1e-4)
	for p in 4:
		for q in 4:
			assert_true(nav.reachable(p, q), "jumper reaches every platform (%d -> %d)" % [p, q])


func test_route_near_prefers_the_nearer_parallel_edge() -> void:
	var nav := NavGraph.build(m, {"can_jump": false})
	assert_near(nav.edge(nav.route_near(m1, g_, 120.0)).x_from, 100.0, 1e-4, "left end is nearer")
	assert_near(nav.edge(nav.route_near(m1, g_, 380.0)).x_from, 400.0, 1e-4, "right end is nearer")


func test_jump_limits() -> void:
	# A platform 100 px up is out of reach; a 30 px step over a 50 px gap is a hop with horizontal speed;
	# a 200 px gap is too far.
	var mm := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 100.0, "y2": 0.0},
		{"x1": 20.0, "y1": -100.0, "x2": 80.0, "y2": -100.0},
		{"x1": 150.0, "y1": -30.0, "x2": 250.0, "y2": -30.0},
		{"x1": 450.0, "y1": -30.0, "x2": 550.0, "y2": -30.0},
	])
	var nav := NavGraph.build(mm, {"can_jump": true})
	var a := mm.platform_of(0)
	for e: int in nav.edges_from(a):
		assert_ne(nav.e_to[e], mm.platform_of(1), "no direct hop: 100 px is above the 70 px jump height")
	var e := nav.route(a, mm.platform_of(2))
	assert_true(e >= 0, "gap hop")
	var d := nav.edge(e)
	assert_eq(d.kind, "jump")
	assert_near(d.x_to, 158.0, 1e-4, "lands margin px inside the target")
	assert_true(d.vx > 0.0)
	assert_true(d.x_to - d.x_from <= 90.0)
	assert_eq(nav.route(mm.platform_of(2), mm.platform_of(3)), -1, "200 px gap is out of reach")
	var tall := NavGraph.build(mm, {"can_jump": true, "jump_height": 110.0, "jump_speed": 700.0})
	var direct := tall.route(a, mm.platform_of(1))
	assert_true(direct >= 0 and tall.e_from[direct] == a and tall.e_to[direct] == mm.platform_of(1),
		"opts raise the jump height: direct hop")


func test_cliff_jump_clears_the_wall() -> void:
	var cm := FootholdMap.from_segments(WF.cliff_segments())
	var low := cm.platform_of(0)
	var high := cm.platform_of(2)
	var walk := NavGraph.build(cm, {"can_jump": false})
	assert_eq(walk.route(low, high), -1)
	var down := walk.edge(walk.route(high, low))
	assert_eq(down.kind, "drop")
	assert_near(down.x_from, 200.0, 1e-4, "walk off the top of the cliff")
	var jump := NavGraph.build(cm, {"can_jump": true})
	var e := jump.route(low, high)
	assert_true(e >= 0, "hop up the 50 px cliff")
	var d := jump.edge(e)
	assert_true(d.x_from < 200.0)
	assert_near(d.x_to, 208.0, 1e-4)
	# Replay the arc: it must pass above the wall top (y -50) where it crosses x = 200.
	var v := 555.0
	var t_cross: float = (200.0 - d.x_from) / d.vx
	var y_cross: float = -v * t_cross + 1000.0 * t_cross * t_cross
	assert_true(y_cross < -51.0, "arc is above the wall top at x=200 (y=%s)" % y_cross)


func test_drop_target_is_where_the_step_off_lands() -> void:
	# A lower floor starting 3 px past the upper end is inside the 4 px drift: the drop lands on it. One starting 6 px
	# past the end is not: the drop falls past it onto the ground, and the graph says so.
	for start: float in [203.0, 206.0]:
		var mm := FootholdMap.from_segments([
			{"x1": 0.0, "y1": 0.0, "x2": 200.0, "y2": 0.0},
			{"x1": start, "y1": 10.0, "x2": 400.0, "y2": 10.0},
			{"x1": -200.0, "y1": 300.0, "x2": 800.0, "y2": 300.0},
		])
		var up := mm.platform_of(0)
		var low := mm.platform_of(1)
		var ground := mm.platform_of(2)
		var nav := NavGraph.build(mm, {"can_jump": false})
		var right := -1
		for e: int in nav.edges_from(up):
			if nav.e_x_from[e] == 200.0:
				right = e
		assert_true(right >= 0, "right end of the upper floor has a drop edge (start %s)" % start)
		if right < 0:
			continue
		var d := nav.edge(right)
		assert_eq(d.kind, "drop")
		assert_near(d.vx, 120.0, 1e-4, "drift speed")
		assert_eq(d.to_p, low if start < 204.0 else ground, "landing platform (start %s)" % start)
		assert_near(d.x_to, 204.0, 1e-4, "falls straight down drop_probe px past the end")
		var land := NavGraph.drop_landing(mm, 200.0, 0.0, 1)
		assert_eq(mm.platform_of(int(land.z)), d.to_p)
		assert_near(land.y, 10.0 if start < 204.0 else 300.0, 1e-4)
	# An end with nothing below (or only its own platform, at the map edge) gets no edge.
	var lone := FootholdMap.from_segments([{"x1": 0.0, "y1": 0.0, "x2": 100.0, "y2": 0.0}])
	assert_eq(NavGraph.build(lone, {"can_jump": false}).edge_count(), 0)
	assert_eq(int(NavGraph.drop_landing(lone, 100.0, 0.0, 1).z), 0, "the map edge clamps the drift: lands on itself")


func test_ceiling_blocks_straight_up_hops() -> void:
	var bm := FootholdMap.from_segments(WF.block_segments())
	var ground := bm.platform_of(0)
	var top := bm.platform_of(1)
	var nav := NavGraph.build(bm, {"can_jump": true})
	var e := nav.route(ground, top)
	assert_true(e >= 0, "the block top is reachable")
	var d := nav.edge(e)
	assert_eq(d.kind, "jump")
	assert_true(absf(d.vx) > 0.0, "by a hop from beside the block, not straight up through its underside")
	assert_true(d.x_from < 200.0 or d.x_from > 400.0, "takeoff outside the block (%s)" % d.x_from)
	# Without the underside (and its side walls) the same platforms get a straight-up takeoff range.
	var open := FootholdMap.from_segments(WF.block_segments().slice(0, 2))
	var d2 := NavGraph.build(open, {"can_jump": true}).edge(NavGraph.build(open, {"can_jump": true}).route(0, 1))
	assert_near(d2.vx, 0.0)
	assert_true(d2.hi > d2.lo)
