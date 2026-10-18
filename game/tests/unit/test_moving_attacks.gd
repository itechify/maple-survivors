extends TestCase
## Moving attacks (spec #168 ticket #190, docs/GAME_DESIGN.md 7.9): a skill definition's `displacement` block moves the
## grounded character away from or toward the mob it faces, before, after or during the hit, along footholds and
## stopping at platform edges and walls. FootholdMap.slide_along on synthetic segments, then whole casts on seeded
## synthetic worlds with a synthetic skill (no Pirate data). Fixed ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const GROUND := {"x1": 0, "y1": 0, "x2": 1000, "y2": 0}


# --- FootholdMap.slide_along -----------------------------------------------------------------------------------------

func _slide(m: FootholdMap, x: float, side: int, distance: float, fh := 0, lo := -INF, hi := INF) -> Dictionary:
	return m.slide_along(fh, x, side, distance, lo, hi)


func test_slide_covers_the_full_distance_on_open_ground_both_ways() -> void:
	var m := FootholdMap.from_segments([GROUND])
	var right := _slide(m, 400.0, 1, 120.0)
	assert_near(right.x, 520.0)
	assert_near(right.moved, 120.0)
	assert_eq(right.fh, 0)
	var left := _slide(m, 400.0, -1, 120.0)
	assert_near(left.x, 280.0)
	assert_near(left.moved, 120.0)


func test_slide_stops_at_the_platform_edge_and_never_walks_off() -> void:
	var m := FootholdMap.from_segments([GROUND])
	var right := _slide(m, 950.0, 1, 200.0)
	assert_near(right.x, 1000.0)
	assert_near(right.moved, 50.0)
	var left := _slide(m, 30.0, -1, 200.0)
	assert_near(left.x, 0.0)
	assert_near(left.moved, 30.0)
	var at_edge := _slide(m, 1000.0, 1, 100.0)
	assert_near(at_edge.moved, 0.0, 1e-9, "already on the edge: nothing to move")
	# A gap between two floors ends the platform: the far floor is not reached.
	var gap := FootholdMap.from_segments([GROUND, {"x1": 1050, "y1": 0, "x2": 1500, "y2": 0}])
	assert_near(_slide(gap, 900.0, 1, 400.0).x, 1000.0)


func test_slide_follows_slopes_and_chained_floors() -> void:
	var m := FootholdMap.from_segments([
		{"x1": 0, "y1": 0, "x2": 500, "y2": 0},
		{"x1": 500, "y1": 0, "x2": 700, "y2": -100},
		{"x1": 700, "y1": -100, "x2": 1000, "y2": -100}])
	var up := _slide(m, 400.0, 1, 200.0)
	assert_near(up.x, 600.0)
	assert_near(up.y, -50.0, 1e-4, "on the middle of the slope")
	assert_eq(up.fh, 1)
	var over := _slide(m, 400.0, 1, 500.0)
	assert_near(over.x, 900.0)
	assert_near(over.y, -100.0)
	assert_eq(over.fh, 2, "crossed two joints")
	var down := _slide(m, 900.0, -1, 500.0, 2)
	assert_near(down.x, 400.0)
	assert_near(down.y, 0.0)
	assert_eq(down.fh, 0)


func test_slide_stops_just_short_of_a_wall_across_the_surface() -> void:
	var m := FootholdMap.from_segments([GROUND, {"x1": 700, "y1": 0, "x2": 700, "y2": -100}])
	var right := _slide(m, 400.0, 1, 500.0)
	assert_near(right.x, 700.0 - FootholdMap.EPS, 1e-6)
	assert_true(right.moved < 300.0)
	var left_wall := FootholdMap.from_segments([GROUND, {"x1": 300, "y1": 0, "x2": 300, "y2": -100}])
	assert_near(_slide(left_wall, 600.0, -1, 500.0).x, 300.0 + FootholdMap.EPS, 1e-6)
	var behind := _slide(m, 800.0, 1, 100.0)
	assert_near(behind.x, 900.0, 1e-6, "a wall behind the start does not stop the slide")
	# A wall hanging below the surface (a skirt) is walked past, as on foot.
	var skirt := FootholdMap.from_segments([GROUND, {"x1": 700, "y1": 0, "x2": 700, "y2": 60}])
	assert_near(_slide(skirt, 400.0, 1, 500.0).x, 900.0)


func test_slide_stays_inside_the_horizontal_limits_and_is_total() -> void:
	var m := FootholdMap.from_segments([GROUND])
	assert_near(_slide(m, 400.0, 1, 500.0, 0, 0.0, 600.0).x, 600.0)
	assert_near(_slide(m, 400.0, -1, 500.0, 0, 250.0, 1000.0).x, 250.0)
	for bad: Dictionary in [_slide(m, 400.0, 0, 100.0), _slide(m, 400.0, 1, 0.0), _slide(m, 400.0, 1, -5.0),
			_slide(m, 400.0, 1, 100.0, -1)]:
		assert_near(bad.moved, 0.0, 1e-9)
		assert_near(bad.x, 400.0)


# --- whole casts -----------------------------------------------------------------------------------------------------

## A world on a flat ground at y = 0 (override `segments`) with a synthetic instant (or projectile) skill that
## carries `displacement`, the player on the ground at `x`. Each canonical level has a left-facing box (-60..40 by
## 60 high) and mobCount 3.
func _world(displacement: Dictionary, x := 400.0, kind := "instant", segments: Array = [GROUND]) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = 100
	data.balance.magnet_radius = 0
	var def := {"skill_id": 9991000, "book": "999", "kind": kind, "damage": "fixed", "ranks": [1, 2, 3],
		"cooldown": 1.0, "range": 400.0, "speed": 400.0, "count": 1, "cast": {"rule": "nearest"}}
	if not displacement.is_empty():
		def["displacement"] = displacement
	data.skills.skills["synthetic"] = def
	var setup := RF.setup("quiet", 190, data)
	setup.map_img = RF.map_from_segments(segments)
	setup.skill_imgs["999"] = {"skill": {"9991000": {"level": {
		"1": {"lt": {"$v": [-60.0, -60.0]}, "rb": {"$v": [40.0, 0.0]}, "mobCount": 3.0, "fixdamage": 10.0,
			"mpCon": 7.0, "x": 60.0},
		"2": {"lt": {"$v": [-60.0, -60.0]}, "rb": {"$v": [40.0, 0.0]}, "mobCount": 3.0, "fixdamage": 10.0,
			"mpCon": 7.0, "x": 90.0},
		"3": {"lt": {"$v": [-60.0, -60.0]}, "rb": {"$v": [40.0, 0.0]}, "mobCount": 3.0, "fixdamage": 10.0,
			"mpCon": 7.0, "x": 120.0}}}}}
	var w := RunWorld.new(setup)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.player.place(Vector2(x, 0), w.fhm)
	w.update_view()
	w.god = true
	w.loadout.order.clear()
	w.learn_skill("synthetic")
	w.drain_events()
	return w


func _mob(w: RunWorld, x: float) -> int:
	return RF.put_mob(w, MOB, x, -5.0, 1000.0)


## One cast tick: rebuild the mob grid, run the skill runner once, return the events.
func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _hit_slots(events: Array) -> Array:
	return _of(events, "mob_hit").map(func(e: Dictionary) -> int: return int(e.mob))


func test_stats_resolve_the_block_from_a_field_a_rank_list_or_a_number() -> void:
	assert_eq(_world({}).loadout.stats("synthetic").displacement, {}, "no block, no displacement")
	var by_field := _world({"direction": "toward", "when": "during", "field": "x"})
	assert_eq(by_field.loadout.stats("synthetic").displacement, {"direction": "toward", "when": "during", "distance": 60.0})
	by_field.loadout.set_rank("synthetic", 2)
	assert_eq(by_field.loadout.stats("synthetic").displacement.distance, 90.0, "the field follows the canonical level")
	var by_list := _world({"direction": "away", "when": "before", "distances": [30.0, 50.0]})
	assert_eq(by_list.loadout.stats("synthetic", 1).displacement.distance, 30.0)
	assert_eq(by_list.loadout.stats("synthetic", 3).displacement.distance, 50.0, "the last value repeats")
	var plain := _world({"distance": 75})
	assert_eq(plain.loadout.stats("synthetic").displacement, {"direction": "away", "when": "after", "distance": 75.0},
		"direction defaults to away, when to after")
	assert_eq(_world({"distance": -20}).loadout.stats("synthetic").displacement.distance, 0.0)


func test_away_and_toward_cover_the_full_distance_on_open_ground() -> void:
	for case: Array in [["away", 1, 300.0, 700.0], ["away", -1, 300.0, 100.0], ["toward", 1, 300.0, 500.0],
			["toward", -1, 300.0, 300.0]]:
		var w := _world({"direction": case[0], "when": "after", "distance": 100.0})
		var mob_x: float = 500.0 if int(case[1]) > 0 else 300.0
		_mob(w, mob_x)
		var events := _cast(w)
		assert_eq(_of(events, "cast").size(), 1, "cast %s" % [case])
		assert_eq(_hit_slots(events).size(), 1, "the target is struck")
		var expect_x: float = 400.0 - 100.0 * int(case[1]) if case[0] == "away" else 400.0 + 100.0 * int(case[1])
		assert_near(w.player.pos.x, expect_x, 1e-6, "%s the mob on the %s" % [case[0], "right" if int(case[1]) > 0 else "left"])
		assert_eq(w.player.facing, int(case[1]), "the character keeps facing the mob (backs away or charges)")
		assert_true(w.player.fh >= 0, "still standing on the foothold")


func test_a_walking_character_turns_to_the_mob_before_moving() -> void:
	var w := _world({"direction": "away", "when": "after", "distance": 100.0})
	w.player.facing = -1
	w.player.state = PlayerMotion.ST_WALK
	_mob(w, 500.0)
	_cast(w)
	assert_eq(w.player.facing, 1)
	assert_near(w.player.pos.x, 300.0, 1e-6, "away from a mob on the right means left whatever the facing was")


func test_the_move_stops_at_a_platform_edge_and_the_cast_still_happens() -> void:
	var w := _world({"direction": "away", "when": "after", "distance": 100.0}, 960.0)
	_mob(w, 880.0)  # to the left: away is to the right, 40 px from the edge
	var events := _cast(w)
	assert_near(w.player.pos.x, 1000.0, 1e-6, "stopped at the edge instead of walking off")
	assert_true(w.player.fh >= 0)
	assert_eq(_of(events, "cast").size(), 1, "terrain never fails the cast")
	assert_eq(_hit_slots(events).size(), 1)
	assert_eq(w.player_state.mp, 93, "MP was paid once")
	# A character already on the edge casts without moving.
	var edge := _world({"direction": "away", "when": "after", "distance": 100.0}, 1000.0)
	_mob(edge, 920.0)
	assert_eq(_hit_slots(_cast(edge)).size(), 1)
	assert_near(edge.player.pos.x, 1000.0)


func test_the_move_stops_at_a_wall() -> void:
	var w := _world({"direction": "away", "when": "after", "distance": 200.0}, 400.0, "instant",
		[GROUND, {"x1": 520, "y1": 0, "x2": 520, "y2": -80}])
	_mob(w, 300.0)
	var events := _cast(w)
	assert_near(w.player.pos.x, 520.0 - FootholdMap.EPS, 1e-4, "stopped short of the wall")
	assert_eq(_hit_slots(events).size(), 1, "the cast still struck")


func test_the_move_follows_a_slope() -> void:
	var w := _world({"direction": "toward", "when": "after", "distance": 200.0}, 400.0, "instant", [
		{"x1": 0, "y1": 0, "x2": 500, "y2": 0}, {"x1": 500, "y1": 0, "x2": 700, "y2": -100},
		{"x1": 700, "y1": -100, "x2": 1000, "y2": -100}])
	_mob(w, 450.0)
	_cast(w)
	assert_near(w.player.pos.x, 600.0, 1e-6)
	assert_near(w.player.pos.y, -50.0, 1e-3, "the feet follow the slope")
	assert_eq(w.player.fh, 1)
	var steps := w.player.pos
	w.step(DT, MoveInput.new())
	assert_true(w.player.fh >= 0 and w.player.pos.distance_to(steps) < 2.0, "the next ordinary tick keeps standing on it")


func test_nothing_moves_while_airborne_but_the_attack_still_casts() -> void:
	var w := _world({"direction": "away", "when": "after", "distance": 100.0})
	w.player.place(Vector2(400, -60), w.fhm)
	assert_eq(w.player.fh, -1, "in the air")
	_mob(w, 480.0)
	var events := _cast(w)
	assert_eq(w.player.pos, Vector2(400, -60), "no displacement in the air")
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(_hit_slots(events).size(), 1)
	# Hanging on a rope does not cast at all (existing rule), so there is nothing to move either.
	var rope := _world({"direction": "away", "when": "after", "distance": 100.0})
	rope.player.state = PlayerMotion.ST_LADDER
	_mob(rope, 480.0)
	assert_eq(_of(_cast(rope), "cast").size(), 0)
	assert_eq(rope.player.pos.x, 400.0)


func test_when_orders_the_move_against_a_projectile_shot() -> void:
	for when: String in ["before", "after", "during"]:
		var w := _world({"direction": "away", "when": when, "distance": 100.0}, 400.0, "projectile")
		_mob(w, 600.0)
		_cast(w)
		assert_near(w.player.pos.x, 300.0, 1e-6, when)
		var shot := -1
		for i in w.projectiles.active.size():
			if w.projectiles.active[i] != 0:
				shot = i
		assert_true(shot >= 0, "a shot flew: " + when)
		var from_start: bool = when == "after"
		assert_between(w.projectiles.x[shot], 300.0 if not from_start else 400.0, 330.0 if not from_start else 430.0,
			"%s: the shot leaves from the %s position" % [when, "pre-move" if from_start else "moved"])


func test_the_cast_event_reports_where_the_cast_began() -> void:
	for when: String in ["before", "after", "during"]:
		var w := _world({"direction": "away", "when": when, "distance": 100.0})
		_mob(w, 500.0)
		var cast: Dictionary = _of(_cast(w), "cast")[0]
		assert_eq(cast.pos, Vector2(400, 0), when)
		assert_near(w.player.pos.x, 300.0, 1e-6, when)


func test_a_charge_hits_up_to_the_mob_count_along_its_path() -> void:
	var w := _world({"direction": "toward", "when": "during", "distance": 200.0})
	var behind := _mob(w, 300.0)
	var m1 := _mob(w, 460.0)
	var m2 := _mob(w, 520.0)
	var m3 := _mob(w, 580.0)
	var m4 := _mob(w, 640.0)
	var beyond := _mob(w, 800.0)
	var events := _cast(w)
	assert_near(w.player.pos.x, 600.0, 1e-6, "the full charge on open ground")
	assert_eq(_hit_slots(events), [m1, m2, m3], "the three nearest mobs in the path, in path order")
	assert_false(m4 in _hit_slots(events), "capped at the skill's mob count")
	assert_false(behind in _hit_slots(events) or beyond in _hit_slots(events), "outside the swept path")
	assert_eq(w.player_state.mp, 93)


func test_a_charge_that_stops_at_a_wall_only_sweeps_what_it_covered() -> void:
	var w := _world({"direction": "toward", "when": "during", "distance": 300.0}, 400.0, "instant",
		[GROUND, {"x1": 520, "y1": 0, "x2": 520, "y2": -80}])
	var near := _mob(w, 470.0)
	_mob(w, 700.0)  # beyond the wall, past the end of the path
	var events := _cast(w)
	assert_near(w.player.pos.x, 520.0 - FootholdMap.EPS, 1e-4)
	assert_eq(_hit_slots(events), [near], "the path ends at the wall")
	# At a platform edge the charge still hits the mobs on the stretch it covered.
	var edge := _world({"direction": "toward", "when": "during", "distance": 300.0}, 900.0)
	var close := _mob(edge, 960.0)
	events = _cast(edge)
	assert_near(edge.player.pos.x, 1000.0)
	assert_eq(_hit_slots(events), [close])


func test_a_charge_boxes_the_sweep_by_the_players_body_without_a_skill_box() -> void:
	var w := _world({"direction": "toward", "when": "during", "distance": 200.0})
	for level in ["1", "2", "3"]:
		w.setup.skill_imgs["999"].skill["9991000"].level[level].erase("lt")
		w.setup.skill_imgs["999"].skill["9991000"].level[level].erase("rb")
	assert_false(w.loadout.stats("synthetic").has_box)
	var on_path := _mob(w, 560.0)
	var events := _cast(w)
	assert_eq(_hit_slots(events), [on_path], "the body sweeps the path even without a skill box")


func test_a_skill_without_a_block_does_not_move_and_runs_are_deterministic() -> void:
	var still := _world({})
	_mob(still, 480.0)
	assert_eq(_hit_slots(_cast(still)).size(), 1)
	assert_eq(still.player.pos, Vector2(400, 0))
	var digests := []
	for run in 2:
		var w := _world({"direction": "toward", "when": "during", "distance": 150.0})
		for x in [450.0, 500.0, 550.0, 600.0]:
			_mob(w, x)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		for tick in 180:
			w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
			w.step(DT, MoveInput.new())
			for e: Dictionary in w.drain_events():
				ctx.update(var_to_str(e).to_utf8_buffer())
		ctx.update(var_to_str(w.player.pos).to_utf8_buffer())
		digests.append(ctx.finish().hex_encode())
	assert_eq(digests[0], digests[1], "same seed, same result")
