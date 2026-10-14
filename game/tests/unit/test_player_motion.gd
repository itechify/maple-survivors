extends TestCase
## PlayerMotion against GAME_DESIGN section 3 on synthetic maps (fixed 1/60 s ticks, deterministic).

const WF := preload("res://tests/fixtures/world_fixtures.gd")
const DT := 1.0 / 60.0

var _none := MoveInput.new()


func _flat(len := 4000.0) -> FootholdMap:
	return FootholdMap.from_segments([{"x1": -len, "y1": 0.0, "x2": len, "y2": 0.0}])


func _player(m: FootholdMap, at: Vector2) -> PlayerMotion:
	var p := PlayerMotion.new(PhysicsConstants.v83_defaults())
	p.place(at, m)
	return p


func _run(p: PlayerMotion, m: FootholdMap, input: MoveInput, ticks: int, ladders: LadderSet = null) -> int:
	var flags := 0
	for t in ticks:
		flags |= p.step(DT, input, m, ladders, Rect2())
	return flags


func test_place_snaps_only_when_on_the_floor() -> void:
	var m := _flat()
	var p := _player(m, Vector2(0, 0))
	assert_eq(p.fh, 0)
	assert_eq(p.stance(), "stand1")
	var q := _player(m, Vector2(0, -150))
	assert_eq(q.fh, -1, "150 px above the floor: falls")
	assert_eq(q.stance(), "jump")


func test_walk_accelerates_to_125_and_decelerates_at_800() -> void:
	var m := _flat()
	var p := _player(m, Vector2.ZERO)
	var right := MoveInput.make(false, true)
	_run(p, m, right, 3)  # 0.05 s at 1400 px/s^2
	assert_near(p.vel.x, 70.0, 0.01, "1400 px/s^2 acceleration")
	_run(p, m, right, 3)  # reaches the cap at 0.089 s
	assert_near(p.vel.x, 125.0, 1e-4, "walkSpeed cap")
	_run(p, m, right, 60)
	assert_near(p.vel.x, 125.0, 1e-4, "stays at the cap")
	assert_eq(p.stance(), "walk1")
	assert_eq(p.facing, 1)
	var x0 := p.pos.x
	_run(p, m, _none, 6)  # 0.1 s at 800 px/s^2
	assert_near(p.vel.x, 45.0, 1e-3, "800 px/s^2 deceleration")
	_run(p, m, _none, 60)
	assert_near(p.vel.x, 0.0, 1e-6, "stopped")
	assert_near(p.pos.x - x0, 125.0 * 125.0 / 1600.0, 0.6, "stopping distance v^2/(2*800)")
	assert_eq(p.stance(), "stand1")
	var speedy := _player(m, Vector2.ZERO)
	speedy.speed_stat = 140
	_run(speedy, m, MoveInput.make(true), 60)
	assert_near(speedy.vel.x, -175.0, 1e-3, "speed stat scales walkSpeed")


func test_jump_apex_air_time_and_vx_clamp() -> void:
	var m := _flat()
	var p := _player(m, Vector2.ZERO)
	var flags := p.step(DT, MoveInput.make(false, false, false, false, true, true), m, null, Rect2())
	assert_true(flags & PlayerMotion.EV_JUMP != 0, "EV_JUMP")
	var top := p.pos.y
	var ticks := 1
	var landed := false
	while ticks < 120:
		var f := p.step(DT, _none, m, null, Rect2())
		ticks += 1
		top = minf(top, p.pos.y)
		if f & PlayerMotion.EV_LAND:
			landed = true
			break
	assert_true(landed, "lands again")
	assert_between(-top, 75.0, 79.0, "apex ~77 px")
	assert_between(ticks * DT, 0.54, 0.58, "air time 2 x 555/2000")
	assert_near(p.pos.y, 0.0, 1e-4)
	# A held direction clamps vx into [0.8, 1] x 125 at take-off; then air control is ~9 px/s at most.
	var q := _player(m, Vector2.ZERO)
	q.step(DT, MoveInput.make(false, true, false, false, true, true), m, null, Rect2())
	assert_near(q.vel.x, 100.0, 1e-3, "standing jump with right held -> 0.8 x 125")
	var r := _player(m, Vector2.ZERO)
	r.step(DT, MoveInput.make(true, false, false, false, true, true), m, null, Rect2())
	assert_near(r.vel.x, -100.0, 1e-3)
	_run(r, m, MoveInput.make(false, true), 20)
	assert_near(r.vel.x, -100.0, 1e-3, "no air control above ~9 px/s")
	var s := _player(m, Vector2(0, -300))
	_run(s, m, MoveInput.make(false, true), 10)
	assert_between(s.vel.x, 8.0, 9.0, "air control caps at floatDrag2/1120")


func test_terminal_velocity_and_landing_clamp_on_slope() -> void:
	# Slope rising to the right: y = -x/2 over 0..2000 (|sin| 0.45, walkable).
	var m := FootholdMap.from_segments([{"x1": 0.0, "y1": 0.0, "x2": 2000.0, "y2": -1000.0}])
	var p := _player(m, Vector2(1000, -2500))
	_run(p, m, _none, 40)  # 0.67 s: at fall speed after 0.335 s
	assert_near(p.vel.y, 670.0, 1e-3, "fallSpeed")
	var landed := false
	for t in 300:
		if p.step(DT, _none, m, null, Rect2()) & PlayerMotion.EV_LAND:
			landed = true
			break
	assert_true(landed)
	assert_eq(p.fh, 0, "landed on the sloped foothold")
	assert_near(p.pos.y, m.y_at(0, p.pos.x), 1e-3, "on the slope surface")
	var tang := Vector2(2, -1).normalized()
	# 162.5 x |sin| along the slope at contact, less at most one sub-step of ground drag (800/120) after it.
	assert_between(absf(p.vel.dot(tang)), 162.5 * absf(tang.y) - 800.0 / 120.0 - 0.01, 162.5 * absf(tang.y) + 0.01,
		"vy clamped to 162.5 then projected (unclamped would be ~300)")
	assert_near(absf(p.vel.cross(tang)), 0.0, 1e-3, "velocity follows the slope")


func test_slope_walking_follows_surface() -> void:
	var m := FootholdMap.from_segments([
		{"x1": -500.0, "y1": 0.0, "x2": 0.0, "y2": 0.0},
		{"x1": 0.0, "y1": 0.0, "x2": 300.0, "y2": -100.0},
		{"x1": 300.0, "y1": -100.0, "x2": 900.0, "y2": -100.0},
	])
	var p := _player(m, Vector2(-50, 0))
	for t in 300:
		p.step(DT, MoveInput.make(false, true), m, null, Rect2())
		assert_true(p.fh >= 0, "never leaves the ground on a connected chain")
		if p.fh >= 0:
			assert_near(p.pos.y, m.y_at(p.fh, p.pos.x), 1e-3)
	assert_eq(p.fh, 2)
	assert_true(p.pos.x > 400.0)


func test_steep_foothold_slips() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 20.0, "y2": -100.0},
		{"x1": -500.0, "y1": 0.0, "x2": 0.0, "y2": 0.0, "next": 0, "prev": -1},
	])
	var p := _player(m, Vector2(10, -50))
	assert_eq(p.fh, 0)
	_run(p, m, MoveInput.make(false, true), 30)
	assert_true(p.pos.x < 10.0, "slides down a slope steeper than |sin| 0.9 even while pushing up")


func test_walking_off_an_edge_falls_to_the_floor_below() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 200.0, "y2": 0.0},
		{"x1": -100.0, "y1": 100.0, "x2": 600.0, "y2": 100.0},
	])
	var p := _player(m, Vector2(150, 0))
	var flags := _run(p, m, MoveInput.make(false, true), 30)
	assert_true(flags & PlayerMotion.EV_WALK_OFF != 0, "EV_WALK_OFF")
	_run(p, m, MoveInput.make(false, true), 60)
	assert_eq(p.fh, 1, "landed below")
	assert_near(p.pos.y, 100.0, 1e-4)


func test_walls_block_ground_and_air() -> void:
	var m := FootholdMap.from_segments(WF.cliff_segments())
	var p := _player(m, Vector2(100, 0))
	var flags := _run(p, m, MoveInput.make(false, true), 180)
	assert_true(flags & PlayerMotion.EV_WALL != 0, "EV_WALL")
	assert_true(p.pos.x <= 200.0, "stopped at the wall")
	assert_eq(p.fh, 0)
	# Jumping into the wall face from below does not pass through it below its top (it may hop onto the top).
	for t in 120:
		p.step(DT, MoveInput.make(false, true, false, false, true, true), m, null, Rect2())
		if p.fh == 2:
			break
		if p.pos.y > -49.0:
			assert_true(p.pos.x <= 200.0, "below the wall top the player stays left of it")
	# Walking off the top of the cliff to the left falls down past the wall.
	var q := _player(m, Vector2(260, -50))
	_run(q, m, MoveInput.make(true), 90)
	assert_eq(q.fh, 0, "dropped to the lower floor")


func test_map_horizontal_limits() -> void:
	var m := FootholdMap.from_segments([{"x1": 0.0, "y1": 0.0, "x2": 300.0, "y2": 0.0}])
	var p := _player(m, Vector2(250, 0))
	_run(p, m, MoveInput.make(false, true), 120)
	assert_near(p.pos.x, 300.0, 1e-4, "outermost foothold x is a wall")
	assert_eq(p.fh, 0)
	var q := _player(m, Vector2(50, 0))
	for t in 120:
		q.step(DT, MoveInput.make(true), m, null, Rect2(20, -400, 500, 500))
	assert_near(q.pos.x, 20.0, 1e-4, "MapBounds narrower than the footholds")


func test_down_jump_through_platform_but_not_cant_through() -> void:
	var segs := [
		{"x1": 0.0, "y1": -100.0, "x2": 400.0, "y2": -100.0},
		{"x1": -100.0, "y1": 0.0, "x2": 500.0, "y2": 0.0},
	]
	var m := FootholdMap.from_segments(segs)
	var p := _player(m, Vector2(200, -100))
	assert_eq(p.fh, 0)
	var flags := p.step(DT, MoveInput.make(false, false, false, true, true, true), m, null, Rect2())
	assert_true(flags & PlayerMotion.EV_DOWN_JUMP != 0, "EV_DOWN_JUMP")
	# Take-off -196.2 px/s in the first sub-step, then one 1/120 s sub-step of gravity.
	assert_near(p.vel.y, -555.0 * 0.35355339 + 2000.0 / 120.0, 1e-3, "-196 px/s take-off")
	assert_near(p.vel.x, 0.0)
	var landed := false
	for t in 120:
		if p.step(DT, MoveInput.make(false, false, false, true, false, true), m, null, Rect2()) \
				& PlayerMotion.EV_LAND:
			landed = true
			break
	assert_true(landed)
	assert_eq(p.fh, 1, "passed through the platform to the floor below")
	# cantThrough and forbidFallDown footholds refuse.
	for flag: String in ["cant_through", "forbid_fall_down"]:
		var s2: Array = segs.duplicate(true)
		s2[0][flag] = true
		var m2 := FootholdMap.from_segments(s2)
		var q := _player(m2, Vector2(200, -100))
		var f2 := _run(q, m2, MoveInput.make(false, false, false, true, true, true), 60)
		assert_eq(f2 & PlayerMotion.EV_DOWN_JUMP, 0, flag)
		assert_eq(q.fh, 0, "%s: still on the upper platform" % flag)
		assert_eq(q.stance(), "prone")
	# No floor below: nothing happens.
	var r := _player(m, Vector2(200, 0))
	assert_eq(_run(r, m, MoveInput.make(false, false, false, true, true, true), 30) & PlayerMotion.EV_DOWN_JUMP, 0)
	assert_eq(r.fh, 1)


func test_ladder_grab_climb_and_exit_top() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 400.0, "y2": 0.0},
		{"x1": 150.0, "y1": -120.0, "x2": 350.0, "y2": -120.0},
	])
	var l := LadderSet.from_list([{"x": 200.0, "y1": -118.0, "y2": -10.0, "l": 1.0, "uf": 1.0}])
	var p := _player(m, Vector2(206, 0))
	var up := MoveInput.make(false, false, true)
	var flags := p.step(DT, up, m, l, Rect2())
	assert_true(flags & PlayerMotion.EV_GRAB != 0, "Up within 10 px grabs")
	assert_eq(p.ladder, 0)
	assert_near(p.pos.x, 200.0)
	assert_eq(p.stance(), "ladder")
	var y0 := p.pos.y
	_run(p, m, up, 30, l)
	assert_near(y0 - p.pos.y, 50.0, 2.0, "climbs at 100 px/s")
	flags = _run(p, m, up, 120, l)
	assert_true(flags & PlayerMotion.EV_LADDER_EXIT != 0, "climbs off the top (uf=1)")
	assert_eq(p.ladder, -1)
	assert_eq(p.fh, 1, "standing on the upper floor")
	assert_near(p.pos.y, -120.0, 1e-4)
	# Down on the upper floor above the ladder grabs it again; climbing past the bottom lets go onto the ground.
	_run(p, m, _none, 30, l)
	var down := MoveInput.make(false, false, false, true)
	flags = _run(p, m, down, 3, l)
	assert_true(flags & PlayerMotion.EV_GRAB != 0, "Down from the top grabs")
	_run(p, m, down, 240, l)
	assert_eq(p.ladder, -1, "let go at the bottom")
	assert_eq(p.fh, 0, "and landed on the ground")


func test_ladder_jump_off_and_no_top_exit_without_uf() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 400.0, "y2": 0.0},
		{"x1": 150.0, "y1": -120.0, "x2": 350.0, "y2": -120.0},
	])
	var rope := LadderSet.from_list([{"x": 200.0, "y1": -118.0, "y2": -10.0, "l": 0.0, "uf": 0.0}])
	var p := _player(m, Vector2(195, 0))
	_run(p, m, MoveInput.make(false, false, true), 200, rope)
	assert_eq(p.ladder, 0, "uf=0: cannot climb off the top")
	assert_near(p.pos.y, -118.0, 1e-4)
	assert_eq(p.stance(), "rope")
	_run(p, m, MoveInput.make(false, false, false, true), 30, rope)
	var flags := p.step(DT, MoveInput.make(false, true, false, false, true, true), m, rope, Rect2())
	assert_true(flags & PlayerMotion.EV_LADDER_EXIT != 0, "Jump + direction leaves")
	assert_true(p.vel.x > 0.0 and p.vel.y < 0.0)
	_run(p, m, _none, 120, rope)
	assert_eq(p.fh, 0)
	assert_true(p.pos.x > 210.0)
	# Jump without a direction keeps climbing.
	var q := _player(m, Vector2(195, 0))
	_run(q, m, MoveInput.make(false, false, true), 10, rope)
	q.step(DT, MoveInput.make(false, false, false, false, true, true), m, rope, Rect2())
	assert_eq(q.ladder, 0)


func test_knockback_locks_input_and_shows_alert() -> void:
	var m := _flat()
	var p := _player(m, Vector2.ZERO)
	p.knockback(-1)
	assert_near(p.vel.x, -187.5)
	assert_true(p.vel.y < 0.0, "small hop")
	_run(p, m, MoveInput.make(false, true), 12)  # 0.2 s: input ignored
	assert_true(p.vel.x < 0.0, "input locked during knockback")
	_run(p, m, _none, 30)
	assert_true(p.fh >= 0)
	assert_eq(p.stance(), "alert", "alert after a hit")
	_run(p, m, _none, 120)
	assert_eq(p.stance(), "stand1")
	var before := p.pos.x
	_run(p, m, MoveInput.make(false, true), 30)
	assert_true(p.pos.x > before, "input works again")


func test_jump_held_repeats_and_prone_stance() -> void:
	var m := _flat()
	var p := _player(m, Vector2.ZERO)
	var jumps := 0
	for t in 240:
		if p.step(DT, MoveInput.make(false, false, false, false, t == 0, true), m, null, Rect2()) \
				& PlayerMotion.EV_JUMP:
			jumps += 1
	assert_true(jumps >= 4, "holding jump keeps jumping (%d)" % jumps)
	var q := _player(m, Vector2.ZERO)
	_run(q, m, MoveInput.make(false, true, false, true), 30)
	assert_eq(q.stance(), "prone")
	assert_near(q.pos.x, 0.0, 1e-4, "no walking while prone")


func test_falling_out_of_the_world_recovers_on_the_nearest_floor() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0.0, "y1": 0.0, "x2": 100.0, "y2": 0.0},
		{"x1": 400.0, "y1": -300.0, "x2": 500.0, "y2": -300.0},
	])
	var p := _player(m, Vector2(250, -50))
	assert_eq(p.fh, -1, "nothing below: falling")
	var bounds := Rect2(-100, -400, 700, 500)
	var flags := 0
	for t in 120:
		flags |= p.step(DT, _none, m, null, bounds)
	assert_true(flags & PlayerMotion.EV_FELL_OUT != 0, "EV_FELL_OUT")
	assert_eq(p.fh, 0, "back on the floor nearest to where it fell out")
	assert_near(p.pos.x, 100.0, 1e-4)
	assert_near(p.pos.y, 0.0, 1e-4)
	assert_eq(p.state, PlayerMotion.ST_STAND)
	assert_eq(p.vel, Vector2.ZERO)


func test_ceiling_stops_a_jump_from_below() -> void:
	var m := FootholdMap.from_segments(WF.block_segments())
	var p := _player(m, Vector2(300, 0))
	p.step(DT, MoveInput.make(false, false, false, false, true, false), m, null, Rect2())
	var top := p.pos.y
	var landed := false
	for t in 120:
		var f := p.step(DT, _none, m, null, Rect2())
		top = minf(top, p.pos.y)
		if f & PlayerMotion.EV_LAND:
			landed = true
			break
	assert_between(top, -40.0, -39.9, "the head bump stops it at the underside (y -40)")
	assert_true(landed, "falls back")
	assert_eq(p.fh, 0, "onto the ground under the block")
	# Jumping onto the block from beside it works (the arc passes above its side wall).
	var q := _player(m, Vector2(175, 0))
	var landed_on := -1
	for t in 120:
		var f := q.step(DT, MoveInput.make(false, true, false, false, t == 0, t == 0), m, null, Rect2())
		if f & PlayerMotion.EV_LAND:
			landed_on = q.fh
			break
	assert_eq(landed_on, 1, "hopped onto the block top from beside it")
