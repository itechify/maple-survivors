extends TestCase
## FootholdMap, MapBounds, LadderSet and PhysicsConstants on synthetic WZ-shaped data.

const WF := preload("res://tests/fixtures/world_fixtures.gd")


func test_physics_constants_from_wz_and_defaults() -> void:
	var d := PhysicsConstants.v83_defaults()
	assert_near(d.walk_force, 140000.0)
	assert_near(d.walk_speed, 125.0)
	assert_near(d.walk_drag, 80000.0)
	assert_near(d.gravity_acc, 2000.0)
	assert_near(d.fall_speed, 670.0)
	assert_near(d.jump_speed, 555.0)
	assert_near(d.fly_jump_dec, 0.35)
	assert_near(d.walk_acc(), 1400.0, 1e-6, "walkForce/mass")
	assert_near(d.walk_dec(), 800.0, 1e-6, "walkDrag/mass")
	var full := PhysicsConstants.from_wz(WF.physics_img_v83())
	for key: String in PhysicsConstants.WZ_KEYS:
		assert_near(full.get(PhysicsConstants.WZ_KEYS[key]), float(WF.physics_img_v83()[key]), 1e-9, key)
	var custom := PhysicsConstants.from_wz({"walkSpeed": 150.0, "jumpSpeed": 600.0, "gravityAcc": 2500.0,
		"minFriction": 0.2, "bogus": 1.0})
	assert_near(custom.walk_speed, 150.0)
	assert_near(custom.jump_speed, 600.0)
	assert_near(custom.gravity_acc, 2500.0)
	assert_near(custom.min_friction, 0.2)
	assert_near(custom.fall_speed, 670.0, 1e-9, "missing key keeps v83 value")
	assert_near(custom.walk_dec(), 800.0, 1e-9, "drag factor 1 inside [min, max] friction")


func test_from_wz_parses_layers_links_and_flags() -> void:
	var img := WF.tiers_map_img()
	img.foothold["2"] = {"0": {"9": {"x1": 2000.0, "y1": 50.0, "x2": 2100.0, "y2": 60.0, "prev": 0.0, "next": 0.0,
		"cantThrough": 1.0, "forbidFallDown": 1.0, "force": 30.0}}}
	img.foothold["$junk"] = {"x": 1.0}
	var m := FootholdMap.from_wz(img)
	assert_eq(m.count(), 6)
	var i1 := _by_id(m, 1)
	var i2 := _by_id(m, 2)
	assert_eq(m.next_of(i1), i2, "WZ next id -> index")
	assert_eq(m.prev_of(i2), i1, "WZ prev id -> index")
	assert_eq(m.prev_of(i1), -1, "0 = none")
	var i9 := _by_id(m, 9)
	assert_eq(m.layer[i9], 2)
	assert_eq(m.cant_through[i9], 1)
	assert_eq(m.forbid_fall_down[i9], 1)
	assert_near(m.force[i9], 30.0)
	assert_eq(m.cant_through[i1], 0)
	assert_near(m.y_at(i9, 2050.0), 55.0)
	assert_eq(m.bounds(), Rect2(0, -120, 2100, 180))


func test_wall_floor_ceiling_kinds() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 100.0, "y2": 0.0},
		{"x1": 100.0, "y1": 0.0, "x2": 100.0, "y2": -40.0},
		{"x1": 300.0, "y1": -10.0, "x2": 200.0, "y2": -10.0},
	])
	assert_true(m.is_floor(0) and not m.is_wall(0))
	assert_true(m.is_wall(1) and not m.is_floor(1))
	assert_false(m.is_floor(2) or m.is_wall(2), "x1 > x2 is a ceiling")
	assert_eq(m.platform_of(1), -1, "walls have no platform")
	assert_eq(m.platform_of(2), -1, "ceilings have no platform")
	assert_eq(m.find_below(250.0, -100.0), -1, "ceilings are never found below")


func test_find_below_on_overlapping_platforms() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": -100.0, "x2": 200.0, "y2": -100.0},
		{"x1": 50.0, "y1": -50.0, "x2": 300.0, "y2": -50.0},
		{"x1": -100.0, "y1": 0.0, "x2": 400.0, "y2": 0.0},
		{"x1": 400.0, "y1": 0.0, "x2": 600.0, "y2": -100.0},
	])
	assert_eq(m.find_below(100.0, -500.0), 0, "topmost first")
	assert_eq(m.find_below(100.0, -100.0), 0, "on the surface counts")
	assert_eq(m.find_below(100.0, -99.0), 1, "just below the top one")
	assert_eq(m.find_below(100.0, -20.0), 2)
	assert_eq(m.find_below(100.0, 1.0), -1, "nothing below the ground")
	assert_eq(m.find_below(25.0, -60.0), 2, "outside the middle platform's span")
	assert_eq(m.find_below(100.0, -500.0, 0), 1, "ignore a foothold")
	assert_eq(m.find_below(100.0, -500.0, -1, m.platform_of(0)), 1, "ignore a platform")
	assert_eq(m.find_below(500.0, -100.0), 3, "slope")
	assert_near(m.y_at(3, 500.0), -50.0)
	assert_eq(m.find_below(-200.0, -500.0), -1, "left of every foothold")
	assert_eq(m.find_below(5000.0, -500.0), -1, "right of every foothold")
	# Brute force agreement on a grid of probes.
	for xi in range(-150, 650, 7):
		for yi in range(-160, 40, 9):
			var px := float(xi) + 0.5
			var py := float(yi)
			var best := -1
			var best_y := INF
			for i in m.count():
				if m.is_floor(i) and px >= m.x1[i] and px <= m.x2[i]:
					var g := m.y_at(i, px)
					if g >= py - FootholdMap.EPS and g < best_y:
						best_y = g
						best = i
			assert_eq(m.find_below(px, py), best, "brute force at %s,%s" % [px, py])


func test_platform_chains() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 100.0, "y2": 0.0},  # 0 \
		{"x1": 100.0, "y1": 0.0, "x2": 200.0, "y2": -20.0},  # 1  > chain A (two floors and a slope)
		{"x1": 200.0, "y1": -20.0, "x2": 300.0, "y2": -20.0},  # 2 /
		{"x1": 300.0, "y1": -20.0, "x2": 300.0, "y2": 30.0},  # 3 wall down: ends A
		{"x1": 300.0, "y1": 30.0, "x2": 500.0, "y2": 30.0},  # 4 chain B
		{"x1": 600.0, "y1": -200.0, "x2": 700.0, "y2": -200.0},  # 5 lone floor C
	])
	assert_eq(m.platform_count(), 3)
	var a := m.platform_of(0)
	assert_eq(m.platform_of(1), a)
	assert_eq(m.platform_of(2), a)
	assert_ne(m.platform_of(4), a, "a wall splits chains")
	assert_ne(m.platform_of(5), m.platform_of(4))
	assert_eq(m.platform_span(a), Vector2(0, 300))
	assert_eq(m.platform_span(m.platform_of(4)), Vector2(300, 500))
	assert_eq(m.platform_end_fh(a, -1), 0)
	assert_eq(m.platform_end_fh(a, 1), 2)
	assert_true(m.platform_end_open(a, 1), "the wall hangs below A's right end")
	assert_false(m.platform_end_open(m.platform_of(4), -1), "the same wall rises above B's left end")
	assert_true(m.platform_end_open(m.platform_of(4), 1))
	assert_eq(m.platform_fh_at(a, 150.0), 1)
	assert_eq(m.platform_fh_at(a, 450.0), -1)


func test_asymmetric_links_still_chain() -> void:
	# next of 0 is 1 but prev of 1 points elsewhere (seen in real data): still one platform.
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 100.0, "y2": 0.0, "prev": -1, "next": 1},
		{"x1": 100.0, "y1": 0.0, "x2": 200.0, "y2": 0.0, "prev": 2, "next": -1},
		{"x1": 100.0, "y1": 50.0, "x2": 100.0, "y2": 0.0, "prev": -1, "next": 1},
	])
	assert_eq(m.platform_count(), 1)
	assert_eq(m.platform_of(0), m.platform_of(1))


func test_ceiling_hit() -> void:
	var m := FootholdMap.from_segments(WF.block_segments())
	assert_true(m.is_ceiling(3) and not m.is_floor(3) and not m.is_wall(3))
	assert_eq(m.platform_count(), 2, "ground and the block top")
	assert_eq(m.ceiling_hit(300.0, -30.0, 300.0, -50.0), 3, "rising through the underside")
	assert_eq(m.ceiling_hit(250.0, -30.0, 300.0, -50.0), 3, "rising diagonally")
	assert_eq(m.ceiling_hit(300.0, -40.0, 300.0, -50.0), 3, "starting on the line")
	assert_eq(m.ceiling_hit(300.0, -50.0, 300.0, -30.0), -1, "moving down")
	assert_eq(m.ceiling_hit(300.0, -45.0, 300.0, -70.0), -1, "already above it")
	assert_eq(m.ceiling_hit(150.0, -30.0, 150.0, -50.0), -1, "outside its span")
	assert_eq(m.ceiling_hit(300.0, 0.0, 300.0, -39.0), -1, "not reached yet")
	assert_eq(m.find_below(300.0, -45.0), 0, "never landed on")
	assert_eq(m.floor_wall[0], 0, "the block's walls stand above the ground's wall probe")
	var c := FootholdMap.from_segments(WF.cliff_segments())
	assert_eq(c.floor_wall[0], 1, "the rising cliff wall at the lower floor's end")
	assert_eq(c.floor_wall[2], 0, "the same wall hangs below the upper floor's end: a skirt, never hit")


func test_wall_hit() -> void:
	var m := FootholdMap.from_segments(WF.cliff_segments())
	assert_eq(m.wall_hit(150.0, 0.0, 250.0, 0.0), 1, "rising wall blocks at foot level")
	assert_eq(m.wall_hit(150.0, -60.0, 250.0, -60.0), -1, "above the wall top")
	assert_eq(m.wall_hit(250.0, -50.0, 150.0, -50.0), -1, "walking off the top: the wall hangs below")
	assert_eq(m.wall_hit(250.0, -20.0, 150.0, -20.0), 1, "falling past the wall face")
	assert_eq(m.wall_hit(199.99, 0.0, 250.0, 0.0), 1, "standing against it")
	assert_eq(m.wall_hit(199.99, 0.0, 100.0, 0.0), -1, "moving away")


func test_map_bounds_rules() -> void:
	var with_vr := WF.tiers_map_img(true, true)
	var m := FootholdMap.from_wz(with_vr)
	assert_eq(MapBounds.from_map(with_vr, m), Rect2(-100, -500, 1400, 700), "VR wins")
	var mini := WF.tiers_map_img(false, true)
	assert_eq(MapBounds.from_map(mini, m), Rect2(-200, -700, 1600, 900), "miniMap rect (-centerX, -centerY, w, h)")
	var partial := WF.tiers_map_img(false, true)
	partial.info["VRLeft"] = -50.0
	assert_eq(MapBounds.from_map(partial, m), Rect2(-200, -700, 1600, 900), "incomplete VR falls back to miniMap")
	var bare := WF.tiers_map_img()
	assert_eq(MapBounds.from_map(bare, m), Rect2(0, -420, 1200, 520), "foothold box, top -300, bottom +100")


func test_ladder_set() -> void:
	var l := LadderSet.from_wz(WF.tiers_map_img())
	assert_eq(l.count(), 1)
	assert_near(l.x[0], 380.0)
	assert_near(l.y1[0], -118.0)
	assert_near(l.y2[0], -62.0)
	assert_eq(l.is_ladder[0], 1)
	assert_eq(l.uf[0], 1)
	var s := LadderSet.from_list([
		{"x": 100.0, "y1": 0.0, "y2": 200.0, "l": 0.0, "uf": 0.0},
		{"x": 112.0, "y1": 50.0, "y2": 150.0, "l": 1.0, "uf": 1.0},
	])
	assert_eq(s.find_grab(104.0, 100.0, 10.0), 0, "nearest within reach")
	assert_eq(s.find_grab(108.0, 100.0, 10.0), 1)
	assert_eq(s.find_grab(108.0, 20.0, 10.0), 0, "only the first spans y=20")
	assert_eq(s.find_grab(130.0, 100.0, 10.0), -1, "out of reach")
	assert_eq(s.find_grab(100.0, 201.0, 10.0), -1, "below the bottom")
	assert_eq(s.is_ladder[0], 0)


func _by_id(m: FootholdMap, id: int) -> int:
	for i in m.count():
		if m.ids[i] == id:
			return i
	return -1
