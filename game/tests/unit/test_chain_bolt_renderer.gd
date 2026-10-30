extends TestCase
## The chain bolt art: one stretched, rotated ball animation per segment of the skill_chain polyline (synthetic art).


func _anim(frames: int, delay := 0.1, size := Vector2(40, 12)) -> SpriteAnim:
	var a := SpriteAnim.new()
	var start := 0.0
	for i in frames:
		var f := SpriteFrame.new()
		f.region = Rect2(Vector2.ZERO, size)
		f.delay_s = delay
		f.start = start
		start += delay
		a.frames.append(f)
	a.total = start
	return a


func test_segments_follow_the_polyline_and_cycle_three_variants() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(100, 50), Vector2(100, 50), Vector2(0, 50),
		Vector2(0, 0)])
	var segs := ChainBoltRenderer.segments(pts, 3)
	assert_eq(segs.size(), 4, "the zero-length segment is dropped")
	assert_eq(segs.map(func(s: Dictionary) -> int: return s.variant), [0, 1, 2, 0])
	assert_eq(segs[0].length, 100.0)
	assert_eq(segs[0].angle, 0.0)
	assert_near(segs[1].angle, PI / 2.0)
	assert_near(segs[2].angle, PI)


func test_the_transform_stretches_the_frame_exactly_from_start_to_end() -> void:
	var from := Vector2(10, 20)
	var to := Vector2(10, 220)  # straight down, 200 px
	var t := ChainBoltRenderer.segment_transform(from, to, Vector2(40, 12))
	var start := t * Vector2(0, 0)
	var end := t * Vector2(40, 0)
	assert_near(start.x, from.x, 1e-3)
	assert_near(start.y, from.y, 1e-3)
	assert_near(end.x, to.x, 1e-3)
	assert_near(end.y, to.y, 1e-3)
	var side := t * Vector2(20, 6) - t * Vector2(20, -6)
	assert_near(side.length(), 12.0, 1e-4, "the bolt keeps its thickness")


func test_play_starts_one_item_per_segment_and_frees_them_when_the_animation_ends() -> void:
	var r := ChainBoltRenderer.new()
	var anims: Array = [_anim(5), _anim(5), _anim(5)]
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(180, 60)])
	assert_eq(r.play(pts, anims), 2)
	assert_eq(r.active_count(), 2)
	r.advance(0.3)
	assert_eq(r.active_count(), 2, "still playing")
	r.advance(0.3)
	assert_eq(r.active_count(), 0, "5 frames x 0.1 s")
	assert_eq(r.play(pts, anims), 2)
	assert_eq(r._items.size(), 2, "slots are reused")
	assert_eq(r.play(pts, []), 0, "no art, no bolt")
	r.clear()
	assert_eq(r.active_count(), 0)
	r.free()
