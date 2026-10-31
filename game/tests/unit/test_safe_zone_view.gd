extends TestCase
## SafeZoneView (spec #425 SH4): the layout and timing rules of the cloud and its "Guard" word, from data alone (no scene, no
## asset cache). The look itself is judged on the probe's screenshot (scenes/debug/safe_zone_probe.tscn).


func _anim() -> SpriteAnim:
	var f := SpriteFrame.new()
	f.region = Rect2(0, 0, 8, 8)
	var anim := SpriteAnim.new()
	anim.frames.append(f)
	anim.total = 0.1
	return anim


func test_puffs_stand_on_the_floor_line_across_the_box() -> void:
	var rect := Rect2(250, 277, 300, 226)
	var puffs := SafeZoneView.puff_positions(rect, 420.0)
	assert_eq(puffs.size(), 5, "300 px / 64 px")
	assert_near(puffs[0].x, 280.0, 1e-6)
	assert_near(puffs[4].x, 520.0, 1e-6)
	assert_eq(puffs[0].y, 420.0)
	assert_eq(puffs[1].y, 420.0 - SafeZoneView.PUFF_LIFT, "every second puff is lifted")
	for p in puffs:
		assert_true(p.x > rect.position.x and p.x < rect.end.x)
	assert_eq(SafeZoneView.puff_positions(Rect2(0, 0, 10, 10), 0.0).size(), 1, "at least one")
	assert_eq(SafeZoneView.puff_positions(Rect2(0, 0, 9000, 10), 0.0).size(), SafeZoneView.MAX_PUFFS, "at most the cap")


func test_the_cloud_fades_in_and_out() -> void:
	assert_eq(SafeZoneView.fade_at(0.0, 6.0), 0.0)
	assert_near(SafeZoneView.fade_at(0.2, 6.0), 0.5, 1e-6)
	assert_eq(SafeZoneView.fade_at(3.0, 3.0), 1.0)
	assert_near(SafeZoneView.fade_at(5.8, 0.2), 0.5, 1e-6)
	assert_eq(SafeZoneView.fade_at(6.0, 0.0), 0.0)


func test_guard_words_are_spaced() -> void:
	assert_true(SafeZoneView.guard_allowed(-INF, 0.0))
	assert_false(SafeZoneView.guard_allowed(1.0, 1.0 + SafeZoneView.GUARD_GAP - 0.01))
	assert_true(SafeZoneView.guard_allowed(1.0, 1.5))


func test_a_zone_lives_its_life_and_a_replacement_drops_the_old_one() -> void:
	var view := SafeZoneView.new()
	view.begin("cloud", Rect2(0, 0, 200, 100), 1.0, 90.0, _anim())
	assert_eq(view.zone_count(), 1)
	view.advance(0.5)
	assert_eq(view.puff_count(), 3, "200 px / 64 px of puffs drawn")
	view.begin("cloud", Rect2(0, 0, 200, 100), 1.0, 90.0, null)
	assert_eq(view.zone_count(), 1, "one zone per skill")
	view.advance(0.5)
	assert_eq(view.puff_count(), 0, "a cloud without art draws only the box")
	view.advance(0.6)
	assert_eq(view.zone_count(), 0, "it is gone when its life is")
	view.begin("cloud", Rect2(0, 0, 200, 100), 5.0, 90.0, null)
	view.finish("cloud")
	view.advance(SafeZoneView.FADE + 0.01)
	assert_eq(view.zone_count(), 0, "an ended cloud fades out and goes")
	view.begin("cloud", Rect2(0, 0, 200, 100), 5.0, 90.0, null)
	view.finish("cloud", true)
	assert_eq(view.zone_count(), 0, "or goes at once")
	view.free()


func test_the_guard_word_needs_a_label_container_and_is_rate_limited() -> void:
	var view := SafeZoneView.new()
	var top := Node2D.new()
	view.attach_labels(top)
	view.guard(Vector2(10, 10))
	view.guard(Vector2(10, 10))
	assert_eq(view.guard_count(), 1, "the second word is inside the gap")
	view.advance(SafeZoneView.GUARD_GAP + 0.01)
	view.guard(Vector2(10, 10))
	assert_eq(view.guard_count(), 2)
	view.advance(SafeZoneView.GUARD_LIFE)
	assert_eq(view.guard_count(), 0, "words end")
	view.free()
	top.free()
	var bare := SafeZoneView.new()
	bare.guard(Vector2.ZERO)
	assert_eq(bare.guard_count(), 0, "without a container nothing is drawn")
	bare.free()
