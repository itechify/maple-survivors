extends TestCase
## Area-warning boss attacks (`attackN/info/type` 3 and 4, #460): the column layout from start/areaCount and facing, the
## seeded picks (the character's column always among them), one hit per attack at attackAfter, and the events.

const BF := preload("res://tests/fixtures/boss_attack_fixtures.gd")
const DT := 1.0 / 60.0
## A Lyka-shaped strip: 80 px wide columns from index -7, 15 of them, 7 struck.
const RANGE := BF.AREA_RANGE


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


func test_columns_are_box_wide_from_start_and_centred_on_the_boss() -> void:
	var columns := MobAttacks.area_columns(RANGE, Vector2(1000, 200), -1)
	assert_eq(columns.size(), 15)
	assert_eq(columns[0], Rect2(1000 - 7 * 80 - 40, 0, 80, 200), "index -7 is the leftmost column")
	assert_eq(columns[7], Rect2(960, 0, 80, 200), "index 0 is the box itself, centred on the boss")
	assert_eq(columns[14], Rect2(1000 + 7 * 80 - 40, 0, 80, 200))
	for i in 14:
		assert_near(columns[i].end.x, columns[i + 1].position.x, 1e-6, "columns sit side by side")


func test_an_off_centre_strip_mirrors_with_facing() -> void:
	# Thanatos: 77 px boxes from -33 to 44, start -5, nine columns (indices -5..3).
	var thanatos := {"lt": {"$v": [-33.0, -109.0]}, "rb": {"$v": [44.0, 4.0]}, "start": -5.0, "areaCount": 9.0,
		"attackCount": 5.0}
	var left := MobAttacks.area_columns(thanatos, Vector2.ZERO, -1)
	var right := MobAttacks.area_columns(thanatos, Vector2.ZERO, 1)
	assert_eq(left.size(), 9)
	assert_eq(left[0], Rect2(-33 - 5 * 77, -109, 77, 113))
	assert_eq(left[8], Rect2(-33 + 3 * 77, -109, 77, 113))
	for i in 9:
		assert_eq(right[i].position.x, -left[i].end.x, "facing right mirrors every column")
		assert_eq(right[i].size, left[i].size)
		assert_eq(right[i].position.y, left[i].position.y)


func test_a_box_with_no_area_has_no_columns() -> void:
	assert_true(MobAttacks.area_columns({"lt": {"$v": [0.0, 0.0]}, "rb": {"$v": [0.0, 0.0]}, "areaCount": 5.0},
		Vector2.ZERO, -1).is_empty())
	assert_true(MobAttacks.area_columns(RANGE.merged({"areaCount": 0.0}, true), Vector2.ZERO, -1).is_empty())


func test_the_character_column_is_always_picked_and_picks_are_distinct() -> void:
	var columns := MobAttacks.area_columns(RANGE, Vector2.ZERO, -1)
	for p_seed in 40:
		var rng := _rng(p_seed)
		var target := -500.0 + float(p_seed) * 25.0
		var picked := MobAttacks.pick_columns(rng, columns, 7, target)
		assert_eq(picked.size(), 7)
		var under := -1
		for i in columns.size():
			if target >= columns[i].position.x and target < columns[i].end.x:
				under = i
		assert_true(under >= 0, "the sweep stays inside the strip")
		assert_true(picked.has(under), "seed %d picks the column under x=%s" % [p_seed, target])
		for i in picked.size() - 1:
			assert_true(picked[i] < picked[i + 1], "ascending and distinct")


func test_a_character_outside_the_strip_gets_a_pure_draw() -> void:
	var columns := MobAttacks.area_columns(RANGE, Vector2.ZERO, -1)
	var picked := MobAttacks.pick_columns(_rng(3), columns, 7, 99999.0)
	assert_eq(picked.size(), 7)
	assert_eq(MobAttacks.pick_columns(_rng(3), columns, 99, 0.0).size(), 15, "the count is clamped to the strip")


func test_same_seed_same_columns_and_other_seeds_differ() -> void:
	var columns := MobAttacks.area_columns(RANGE, Vector2.ZERO, -1)
	var a := MobAttacks.pick_columns(_rng(11), columns, 7, 0.0)
	assert_eq(a, MobAttacks.pick_columns(_rng(11), columns, 7, 0.0))
	var differs := false
	for p_seed in range(12, 30):
		differs = differs or MobAttacks.pick_columns(_rng(p_seed), columns, 7, 0.0) != a
	assert_true(differs, "the picks follow the seed")


func _start(w: RunWorld) -> Dictionary:
	for tick in 240:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "area_attack" and e.phase == "warning":
				e["tick"] = tick
				return e
	fail("the boss should start its area attack")
	return {}


func test_the_warning_marks_the_picked_columns_at_attack_start() -> void:
	for type in [3, 4]:
		var w := RunWorld.new(BF.area_setup(type))
		var warning := _start(w)
		if warning.is_empty():
			return
		assert_eq((warning.anchors as PackedVector2Array).size(), 7, "attackCount columns, type %d" % type)
		assert_eq(warning.size, Vector2(80, 200))
		assert_eq(String(warning.art), "Mob.wz/6130101.img/attack1/info/areaWarning")
		assert_near(float(warning.impact_time) - float(warning.time), 1.2, 1e-6)
		var feet: float = w.swarm.y[int(warning.mob)]
		for anchor in warning.anchors as PackedVector2Array:
			assert_near(anchor.y, feet, 1e-6, "anchored at the column's foot")


func test_damage_lands_once_at_attack_after_and_only_in_a_struck_column() -> void:
	var w := RunWorld.new(BF.area_setup(3))
	var warning := _start(w)
	if warning.is_empty():
		return
	var hp := int(w.player_state.hp)
	var hits := 0
	var strike := {}
	var impact_tick := roundi(1.2 / DT)
	for tick in impact_tick + 30:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "player_hit":
				hits += 1
				assert_true(tick >= impact_tick - 3, "nothing lands before attackAfter (tick %d)" % tick)
			elif e.type == "area_attack" and e.phase == "strike":
				strike = e
		if tick < impact_tick - 3:
			assert_eq(int(w.player_state.hp), hp, "the warning itself is harmless")
	assert_eq(hits, 1, "the character's column is always struck, and it is hit once per attack")
	assert_false(strike.is_empty())
	assert_eq(strike.anchors, warning.anchors, "the hit art plays on the warned columns")
	assert_eq(String(strike.art), "Mob.wz/6130101.img/attack1/info/hit")
	assert_true(int(w.player_state.hp) < hp)


func test_leaving_the_picked_columns_dodges_the_strike() -> void:
	var w := RunWorld.new(BF.area_setup(4, RANGE.merged({"attackCount": 1.0}, true)))
	var warning := _start(w)
	if warning.is_empty():
		return
	var hp := int(w.player_state.hp)
	# One column of 80 px is warned, under the character: walk well out of the strip before it lands.
	var boss_x: float = w.swarm.x[int(warning.mob)]
	var left := w.player.pos.x < boss_x
	for tick in roundi(1.2 / DT) + 10:
		w.step(DT, MoveInput.make(left, not left))
	assert_eq(int(w.player_state.hp), hp)
	assert_true(absf(w.player.pos.x - (warning.anchors as PackedVector2Array)[0].x) > 80.0 + w.body.size.x)


func test_one_attack_is_one_hit_even_when_the_body_spans_two_struck_columns() -> void:
	var w := RunWorld.new(BF.area_setup(3, RANGE.merged({"attackCount": 15.0}, true)))
	var warning := _start(w)
	if warning.is_empty():
		return
	var hits := 0
	for tick in roundi(1.2 / DT) + 10:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			hits += 1 if e.type == "player_hit" else 0
	assert_eq(hits, 1, "every column struck, still one hit")


func test_same_seed_same_columns() -> void:
	var a := _start(RunWorld.new(BF.area_setup(3)))
	var b := _start(RunWorld.new(BF.area_setup(3)))
	assert_eq(a.anchors, b.anchors)
	assert_eq(a.tick, b.tick)


func test_a_character_beyond_the_strip_is_not_attacked() -> void:
	var w := RunWorld.new(BF.area_setup(3, RANGE.merged({"areaCount": 1.0, "start": 40.0}, true)))
	for tick in 240:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			assert_ne(e.type, "area_attack", "a strip nowhere near the character is not admitted")


func test_the_column_pick_uses_stream_20_only() -> void:
	var a := RunWorld.new(BF.area_setup(3))
	var b := RunWorld.new(BF.area_setup(3))
	assert_eq(a.area_rng.state, b.area_rng.state)
	_start(a)
	_start(b)
	assert_ne(a.area_rng.state, RunWorld.new(BF.area_setup(3)).area_rng.state, "the picks advance the area stream")
	assert_eq(a.ground_rng.state, RunWorld.new(BF.area_setup(3)).ground_rng.state, "no other stream is spent")
