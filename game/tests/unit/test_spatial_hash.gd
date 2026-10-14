extends TestCase
## SpatialHash queries must match brute force exactly (seeded random points, rectangles and circles).


func _points(rng: RandomNumberGenerator, n: int, area: Rect2) -> Array:
	var xs := PackedFloat32Array()
	var ys := PackedFloat32Array()
	var act := PackedByteArray()
	xs.resize(n)
	ys.resize(n)
	act.resize(n)
	for i in n:
		xs[i] = rng.randf_range(area.position.x, area.end.x)
		ys[i] = rng.randf_range(area.position.y, area.end.y)
		act[i] = 1 if rng.randf() < 0.8 else 0
	# A few points exactly on cell borders.
	for i in mini(n, 10):
		xs[i] = 64.0 * float(i)
		ys[i] = -64.0 * float(i)
	return [xs, ys, act]


func _sorted(arr: PackedInt32Array, n: int) -> Array:
	var out: Array = []
	for k in n:
		out.append(arr[k])
	out.sort()
	return out


func _check(h: SpatialHash, xs: PackedFloat32Array, ys: PackedFloat32Array, act: PackedByteArray,
		rng: RandomNumberGenerator, area: Rect2, label: String) -> void:
	var out := PackedInt32Array()
	for q in 150:
		var r := Rect2(rng.randf_range(area.position.x - 100, area.end.x), rng.randf_range(area.position.y - 100,
			area.end.y), rng.randf_range(0, 400), rng.randf_range(0, 300))
		if q % 10 == 0:
			r = Rect2(64 * (q / 10), -64 * (q / 10), 64, 64)  # cell-aligned edges
		var n := h.query_rect(r, out)
		var expect: Array = []
		for i in xs.size():
			if act[i] != 0 and r.has_point(Vector2(xs[i], ys[i])):
				expect.append(i)
		assert_eq(_sorted(out, n), expect, "%s rect %s" % [label, r])
		var c := Vector2(rng.randf_range(area.position.x - 50, area.end.x + 50),
			rng.randf_range(area.position.y - 50, area.end.y + 50))
		var rad := rng.randf_range(0, 250)
		n = h.query_radius(c, rad, out)
		expect = []
		for i in xs.size():
			var dx := xs[i] - c.x
			var dy := ys[i] - c.y
			if act[i] != 0 and dx * dx + dy * dy <= rad * rad:
				expect.append(i)
		assert_eq(_sorted(out, n), expect, "%s circle %s r=%s" % [label, c, rad])


func test_matches_brute_force_fitted_grid() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261013
	var area := Rect2(-500, -1100, 2300, 1600)
	var p := _points(rng, 700, area)
	var h := SpatialHash.new(64.0)
	h.rebuild(p[0], p[1], p[2])
	var active := 0
	for a: int in p[2]:
		active += a
	assert_eq(h.size(), active)
	_check(h, p[0], p[1], p[2], rng, area, "fitted")


func test_matches_brute_force_fixed_world_with_outliers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	var area := Rect2(-500, -1100, 2300, 1600)
	var p := _points(rng, 500, area.grow(300.0))  # some points outside the world rect
	var h := SpatialHash.new(64.0, area)
	h.rebuild(p[0], p[1], p[2])
	_check(h, p[0], p[1], p[2], rng, area.grow(300.0), "fixed")


func test_rebuild_reuses_and_out_grows() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var area := Rect2(0, 0, 1000, 800)
	var h := SpatialHash.new(64.0)
	for round_i in 5:
		var p := _points(rng, 50 + round_i * 200, area)
		h.rebuild(p[0], p[1], p[2])
		_check(h, p[0], p[1], p[2], rng, area, "round %d" % round_i)
	var out := PackedInt32Array()
	var xs := PackedFloat32Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
	var ys := PackedFloat32Array()
	ys.resize(20)
	var act := PackedByteArray()
	act.resize(20)
	act.fill(1)
	h.rebuild(xs, ys, act)
	assert_eq(h.query_radius(Vector2.ZERO, 100.0, out), 20)
	assert_true(out.size() >= 20, "the caller's array grew")
	assert_eq(h.query_rect(Rect2(5, -1, 5, 2), out), 5, "x in [5, 10)")
	var empty := SpatialHash.new()
	act.fill(0)
	empty.rebuild(xs, ys, act)
	assert_eq(empty.query_radius(Vector2.ZERO, 1000.0, out), 0)
	assert_eq(empty.size(), 0)
