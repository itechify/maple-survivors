extends TestCase
## DamageNumbers layout (v95 overlap rule, centring) and timing as pure functions; stacking on the synthetic cache.

const AF := preload("res://tests/fixtures/asset_fixtures.gd")


func _frame(w: float, h: float, ox: float, oy: float) -> SpriteFrame:
	var f := SpriteFrame.new()
	f.region = Rect2(0, 0, w, h)
	f.origin = Vector2(ox, oy)
	return f


func test_v95_overlap_rule() -> void:
	# NoRed1 "1" (25 wide, origin x 12), NoRed0 "2" (29, 14), NoRed0 "3" (28, 14), by hand:
	# d0: relX = 0 + 25 - 0 = 25; acc = 12; prev = 3 (12 - 25) / 5 = -7.8
	# d1: relX = 12 + 29 + 7.8 = 48.8; acc = 12 + 7.8 + 14 = 33.8; prev = -9
	# d2: relX = 33.8 + 28 + 9 = 70.8
	var xs := DamageNumbers.layout([Vector2(25, 12), Vector2(29, 14), Vector2(28, 14)])
	assert_eq(xs.size(), 3)
	assert_near(xs[0], 25.0, 1e-4)
	assert_near(xs[1], 48.8, 1e-4)
	assert_near(xs[2], 70.8, 1e-4)
	assert_eq(DamageNumbers.layout([]).size(), 0)


func test_advance_matches_v83_digit_spacing() -> void:
	# Equal small digits (31 wide, origin 15): advance = origin - prev = 15 + 0.6 (31 - 15) = 24.6 px, i.e. 6.4 px of
	# outline overlap per pair, in line with HeavenClient's independent ~22-24 px fixed advances.
	var g := Vector2(31, 15)
	var xs := DamageNumbers.layout([g, g, g, g])
	for i in range(1, 4):
		assert_near(xs[i] - xs[i - 1], 24.6, 1e-4, "advance %d" % i)


func test_layout_number_centres_and_uses_large_first_digit() -> void:
	var large := {}
	var small := {}
	for d in 10:
		large[str(d)] = _frame(36, 38, 18, 37)
		small[str(d)] = _frame(30, 33, 15, 32)
	small["Miss"] = _frame(98, 38, 49, 37)
	var placed := DamageNumbers.layout_number("120", large, small)
	assert_eq(placed.size(), 3)
	assert_true(placed[0].frame == large["1"], "first digit from the large set")
	assert_true(placed[1].frame == small["2"] and placed[2].frame == small["0"], "rest from the small set")
	var lo := INF
	var hi := -INF
	for p: Dictionary in placed:
		var f: SpriteFrame = p.frame
		lo = minf(lo, p.pos.x - f.origin.x)
		hi = maxf(hi, p.pos.x - f.origin.x + f.region.size.x)
		assert_eq(p.pos.y, 0.0, "origins on the baseline")
		assert_eq(p.pos, p.pos.floor(), "whole pixels")
	assert_between((lo + hi) * 0.5, -1.0, 1.0, "centred on x = 0")
	var miss := DamageNumbers.layout_number("Miss", large, small)
	assert_eq(miss.size(), 1, "Miss is one glyph")
	assert_true(miss[0].frame == small["Miss"], "Miss falls back to the small set")
	assert_eq(DamageNumbers.layout_number("7x", large, small).size(), 0, "unknown glyph -> nothing")


func test_timing_hold_fade_rise() -> void:
	assert_eq(DamageNumbers.fade_at(0.0), Vector2(1, 0))
	assert_eq(DamageNumbers.fade_at(0.4), Vector2(1, 0), "400 ms hold")
	var mid := DamageNumbers.fade_at(0.7)
	assert_near(mid.x, 0.5, 1e-5, "half faded")
	assert_near(mid.y, 15.0, 1e-4, "half risen")
	assert_true(DamageNumbers.fade_at(1.0).x < 0.0, "done after 1 s")
	assert_eq(DamageNumbers.HOLD + DamageNumbers.FADE, 1.0)
	assert_eq(DamageNumbers.RISE, 30.0)
	assert_eq(DamageNumbers.LINE_PX, 30.0)



func test_stacking_clears_taller_critical_lines() -> void:
	var lib := AssetLibrary.new()
	lib.open(AF.write_cache())
	var dn := DamageNumbers.new()
	dn.library = lib
	var p := Vector2(100, 200)
	var a := dn.spawn(9, p, DamageNumbers.DEALT, 7)
	var b := dn.spawn(31, p, DamageNumbers.CRIT, 7)
	var c := dn.spawn(5, p, DamageNumbers.DEALT, 7)
	var d := dn.spawn(6, p, DamageNumbers.DEALT, 7)
	var other := dn.spawn(4, p, DamageNumbers.CRIT, 8)
	var base: PackedVector2Array = dn.get("_base")
	assert_eq(base[a], p, "first number on its baseline")
	assert_eq(base[b], p - Vector2(0, 30), "one line above a normal number: 30 px")
	assert_eq(base[c], p - Vector2(0, 66), "above a critical number: 36 px more")
	assert_eq(base[d], p - Vector2(0, 96))
	assert_eq(base[other], p, "other keys stack on their own")
	dn.advance(DamageNumbers.STACK_WINDOW + 0.01)
	var e := dn.spawn(1, p, DamageNumbers.DEALT, 7)
	assert_eq((dn.get("_base") as PackedVector2Array)[e], p, "after the window it starts at the bottom again")
	for i in DamageNumbers.MAX_LINES - 1:
		dn.spawn(1, p, DamageNumbers.DEALT, 7)
	var w := dn.spawn(1, p, DamageNumbers.DEALT, 7)
	assert_eq((dn.get("_base") as PackedVector2Array)[w], p, "wraps after MAX_LINES lines")
	dn.free()
	lib.free()
