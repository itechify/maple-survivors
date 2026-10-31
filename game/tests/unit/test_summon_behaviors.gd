extends TestCase
## Summon behaviours (spec #384 M9, GAME_DESIGN 7.121): the `summon.behavior` dispatch of PlayerSummons with SummonTurret and
## SummonKamikaze, on a synthetic Octopus (turret) and Gaviota (kamikaze) with made-up skill ids and synthetic art, the
## template later jobs copy. No Corsair definition and no asset cache needed.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const SB := preload("res://tests/fixtures/summon_behavior_fixtures.gd")
const OCTOPUS := SB.OCTOPUS
const GAVIOTA := SB.GAVIOTA
const SNAIL := 1110100
const RADIUS := SB.RADIUS
const SPEED := SB.SPEED
const SP := SB.SP

## Casts the skill (one auto-cast) and lets the summon-in play; drains the events.
func _cast(w: RunWorld) -> void:
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_run(w, 14)
	w.drain_events()

func _run(w: RunWorld, ticks: int) -> void:
	w.loadout.order.clear()
	for t in ticks:
		w.runner.tick_cooldowns(DT, w)

func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, SNAIL, px, 195, 100000.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func _move_mob(w: RunWorld, m: int, px: float) -> void:
	w.swarm.x[m] = px
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)

## Puts a monster whose body box's right-hand near edge is exactly `d` px from the turret's circle centre.
func _mob_at_edge(w: RunWorld, c: Vector2, d: float) -> int:
	var m := _mob(w, 0.0)
	var body := w.swarm.mob_kind(m).hitbox_at(w.swarm.x[m], w.swarm.y[m], w.swarm.facing[m])
	_move_mob(w, m, c.x + d - body.position.x + w.swarm.x[m])
	body = w.swarm.mob_kind(m).hitbox_at(w.swarm.x[m], w.swarm.y[m], w.swarm.facing[m])
	assert_near(body.position.x, c.x + d, 0.01, "the helper placed the body's near edge")
	assert_true(c.y >= body.position.y and c.y <= body.end.y, "the circle centre is level with the body")
	return m

## The most balls in the air at once over the next `ticks` ticks.
func _peak_balls(w: RunWorld, ticks: int) -> int:
	var peak := 0
	for t in ticks:
		w.runner.tick_cooldowns(DT, w)
		peak = maxi(peak, _balls(w))
	return peak

func _balls(w: RunWorld) -> int:
	return w.runner.summons.turret.ball_count()

func _hits(w: RunWorld) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")

func _hp_lost(w: RunWorld, m: int) -> bool:
	return w.swarm.hp[m] < w.swarm.max_hp[m]

# ---------------------------------------------------------------- dispatch

func test_a_definition_without_a_behavior_is_the_trailing_ally() -> void:
	var def := SB.octopus_def()
	def.summon.erase("behavior")
	def.summon.merge({"follow_speed": 180.0, "follow_distance": 60.0, "teleport_distance": 600.0}, true)
	var w := SB.octopus_world(30.0, 480.0, 1.0, def)
	w.runner.step(DT, w)
	_run(w, 14)
	var start_x := w.runner.summons.x[0]
	w.player.pos.x += 300.0
	_run(w, 120)
	assert_true(w.runner.summons.x[0] > start_x + 100.0, "no behavior key: it follows the owner")
	assert_eq(w.runner.summons.turret.ball_count(), 0)

func test_the_dispatch_names_no_job_skill_or_id_and_unknown_behaviors_trail() -> void:
	var def := SB.octopus_def()
	def.summon["behavior"] = "no_such_behavior"
	var w := SB.octopus_world(30.0, 480.0, 1.0, def)
	w.runner.step(DT, w)
	_run(w, 14)
	w.player.pos.x += 300.0
	_run(w, 120)
	assert_true(w.runner.summons.x[0] > 250.0, "an unknown behavior string is the trailing ally")

# ---------------------------------------------------------------- turret

func test_the_turret_never_follows_or_teleports_however_far_the_owner_walks() -> void:
	var w := SB.octopus_world()
	w.runner.step(DT, w)
	_run(w, 14)
	var s := w.runner.summons
	var spawn_x := s.x[0]
	var spawn_y := s.y[0]
	for step in 8:
		w.player.pos.x += 250.0 # 2000 px in all
		_run(w, 30)
	assert_near(w.player.pos.x, 2200.0, 0.1)
	assert_eq(s.x[0], spawn_x)
	assert_eq(s.y[0], spawn_y)
	assert_eq(s.living_count(), 1)
	assert_ne(s.action[0], "move", "it never plays a move node")

func test_a_turret_called_by_an_airborne_caster_is_planted_on_the_floor_below() -> void:
	var w := SB.octopus_world()
	var ground := w.player.pos.y
	w.player.pos.y -= 120.0 # a cast while jumping: the caster is allowed to cast in the air
	w.runner.step(DT, w)
	_run(w, 14)
	var s := w.runner.summons
	assert_eq(s.living_count(), 1)
	assert_near(s.y[0], ground, 0.01, "planted on the floor under the caster, not hanging at the jump height")
	var c := SummonTurret.centre(s, 0)
	assert_near(c.y, ground + SP.y, 0.01, "so its circle is where a grounded call would put it")
	var m := _mob(w, s.x[0] - 200.0)
	w.player.pos.y = ground
	_run(w, 240)
	assert_true(_hp_lost(w, m), "a ground monster inside the radius is hit")

func test_the_circle_edge_is_inclusive_of_r_minus_one_and_excludes_r_plus_one() -> void:
	for case: Array in [[RADIUS - 1.0, true], [RADIUS + 1.0, false]]:
		var w := SB.octopus_world()
		w.runner.step(DT, w)
		var c := SummonTurret.centre(w.runner.summons, 0)
		var m := _mob_at_edge(w, c, float(case[0]))
		_run(w, 14)
		var targets := w.runner.summons.turret.targets_in_circle(w.runner.summons, 0, w)
		assert_eq(targets.has(m), bool(case[1]), "a body %f px from the centre" % float(case[0]))
		_run(w, 200)
		assert_eq(_hp_lost(w, m), bool(case[1]), "and it %s hit" % ("is" if bool(case[1]) else "is not"))

func test_the_sp_offset_mirrors_with_the_facing() -> void:
	for facing: int in [-1, 1]:
		var w := SB.octopus_world()
		w.player.facing = facing
		w.runner.step(DT, w)
		var s := w.runner.summons
		assert_eq(s.facing[0], facing)
		var c := SummonTurret.centre(s, 0)
		assert_near(c.x, s.x[0] + SP.x * -facing, 0.001, "left-facing art is the WZ native")
		assert_near(c.y, s.y[0] + SP.y, 0.001)
	# A monster 290 px right of the ally: inside the right-facing circle (centre +23), outside the left-facing one (centre -23).
	var lit: Array = []
	for facing: int in [-1, 1]:
		var w := SB.octopus_world()
		w.player.facing = facing
		w.runner.step(DT, w)
		var s := w.runner.summons
		var m := _mob_at_edge(w, Vector2(s.x[0], s.y[0] + SP.y), 290.0)
		lit.append(s.turret.targets_in_circle(s, 0, w).has(m))
	assert_eq(lit, [false, true])

func test_area_scales_the_radius() -> void:
	for area: float in [1.0, 1.5]:
		var w := SB.octopus_world()
		w.loadout.skill_mods["test_octopus"] = {"area": Vector2(0.0, area)}
		w.runner.step(DT, w)
		var s := w.runner.summons
		assert_near(SummonTurret.radius(s, 0), RADIUS * area, 0.001)
		var m := _mob_at_edge(w, SummonTurret.centre(s, 0), RADIUS + 50.0)
		assert_eq(s.turret.targets_in_circle(s, 0, w).has(m), area > 1.2, "a body 50 px past the base circle, area %f" % area)

func test_the_nearest_monster_is_the_target() -> void:
	var w := SB.octopus_world()
	w.runner.step(DT, w)
	var c := SummonTurret.centre(w.runner.summons, 0)
	var far := _mob_at_edge(w, c, 200.0)
	var near := _mob_at_edge(w, c, 60.0)
	_run(w, 14)
	_run(w, 40) # past attackAfter: the ball is in the air
	assert_eq(_balls(w), 1)
	assert_eq(w.runner.summons.turret.target[0], near)
	_run(w, 120)
	assert_true(_hp_lost(w, near))
	assert_false(_hp_lost(w, far), "mobCount 1 fires at the nearest only")

func test_mob_count_and_count_modifiers_set_the_number_of_balls() -> void:
	for case: Array in [[1.0, 0.0, 1], [2.0, 0.0, 2], [2.0, 1.0, 3], [2.0, 5.0, 4]]:
		var w := SB.octopus_world(30.0, 480.0, float(case[0]))
		w.loadout.skill_mods["test_octopus"] = {"count": Vector2(float(case[1]), 1.0)}
		w.runner.step(DT, w)
		var c := SummonTurret.centre(w.runner.summons, 0)
		for k in 4:
			_mob_at_edge(w, c, 40.0 + 40.0 * k)
		_run(w, 14)
		assert_eq(_peak_balls(w, 80), int(case[2]), "mobCount %f plus count %f" % [float(case[0]), float(case[1])])

func test_attack_after_then_flight_then_the_hit_on_arrival_to_the_tick() -> void:
	var w := SB.octopus_world()
	w.runner.step(DT, w)
	var s := w.runner.summons
	var c := SummonTurret.centre(s, 0)
	var m := _mob_at_edge(w, c, 100.0)
	var flight := w.mob_center(m).distance_to(c) / SPEED
	var frac := fmod(flight / DT, 1.0)
	assert_true(frac > 0.05 and frac < 0.95, "the fixture avoids a whole-tick flight: %f" % frac)
	w.drain_events()
	var launched := -1
	var landed := -1
	var attacked := -1
	for tick in 1 + 60 * 4:
		w.runner.tick_cooldowns(DT, w)
		if attacked < 0 and not w.events.filter(func(e: Dictionary) -> bool: return e.type == "summon_attack").is_empty():
			attacked = tick
		if launched < 0 and _balls(w) > 0:
			launched = tick
		if landed < 0 and _hp_lost(w, m):
			landed = tick
			break
	assert_true(attacked > 0 and launched >= attacked, "the attack starts, then the ball leaves")
	assert_eq(launched - attacked, ceili(0.48 / DT - 1e-6), "attackAfter 480 ms after the attack starts")
	assert_eq(landed - launched, ceili(flight / DT - 1e-6), "flight time = distance / bulletSpeed, to the tick")
	assert_eq(_balls(w), 0, "the ball is gone after it lands")
	assert_eq(_hits(w).size(), 1)

func test_the_ball_flies_at_bullet_speed_toward_the_target_centre() -> void:
	var w := SB.octopus_world()
	w.runner.step(DT, w)
	var s := w.runner.summons
	var c := SummonTurret.centre(s, 0)
	var m := _mob_at_edge(w, c, 100.0)
	_run(w, 14)
	for tick in 120:
		w.runner.tick_cooldowns(DT, w)
		if _balls(w) > 0:
			break
	var t := s.turret
	assert_near(Vector2(t.vx[0], t.vy[0]).length(), SPEED, 0.01)
	assert_near(Vector2(t.vx[0], t.vy[0]).angle(), (w.mob_center(m) - c).angle(), 0.001)
	var before := Vector2(t.x[0], t.y[0])
	_run(w, 3)
	assert_near(Vector2(t.x[0], t.y[0]).distance_to(before), SPEED * DT * 3.0, 0.01)
	assert_eq(t.rotate[0], 1)
	assert_ne(t.visual[0], -1)
	assert_eq(w.visual_paths[t.visual[0]], "Skill.wz/212.img/skill/%d/summon/attack1/info/ball" % OCTOPUS)

func test_a_target_that_dies_in_flight_is_skipped() -> void:
	var w := SB.octopus_world()
	w.runner.step(DT, w)
	var c := SummonTurret.centre(w.runner.summons, 0)
	var m := _mob_at_edge(w, c, 250.0)
	_run(w, 14)
	for tick in 120:
		w.runner.tick_cooldowns(DT, w)
		if _balls(w) > 0:
			break
	assert_eq(_balls(w), 1)
	w.drain_events()
	w.swarm.despawn(m)
	_run(w, 90)
	assert_eq(_hits(w).size(), 0, "no hit on a dead target")
	assert_eq(_balls(w), 0, "and the ball is spent")
	# Its slot reused by a fresh monster: a different identity, still skipped.
	var again := SB.octopus_world()
	again.runner.step(DT, again)
	var c2 := SummonTurret.centre(again.runner.summons, 0)
	var m2 := _mob_at_edge(again, c2, 250.0)
	_run(again, 14)
	for tick in 120:
		again.runner.tick_cooldowns(DT, again)
		if _balls(again) > 0:
			break
	again.swarm.despawn(m2)
	var m3 := _mob_at_edge(again, c2, 400.0) # outside the circle, but it takes the freed slot
	assert_eq(m3, m2)
	again.drain_events()
	_run(again, 90)
	assert_true(_hits(again).is_empty(), "the ball does not hit the slot's new occupant")

func test_balls_are_cleared_on_map_transfer_hidden_and_a_dead_caster() -> void:
	for case: String in ["transfer", "hidden", "dead"]:
		var w := SB.octopus_world()
		w.runner.step(DT, w)
		var c := SummonTurret.centre(w.runner.summons, 0)
		var m := _mob_at_edge(w, c, 250.0)
		_run(w, 14)
		for tick in 120:
			w.runner.tick_cooldowns(DT, w)
			if _balls(w) > 0:
				break
		assert_eq(_balls(w), 1, case)
		match case:
			"transfer":
				w.transfer_pending = true
				w.advance_map()
			"hidden":
				w.buffs._hidden = true
			"dead":
				w.player_state.dead = true
		_run(w, 2)
		assert_eq(_balls(w), 0, "%s clears the ball" % case)
		w.drain_events()
		_run(w, 90)
		assert_false(_hp_lost(w, m), "%s: nothing lands" % case)

func test_no_ball_is_launched_while_hidden_or_dead_and_launching_resumes_after() -> void:
	for case: String in ["hidden", "dead"]:
		var w := SB.octopus_world()
		w.runner.step(DT, w)
		var c := SummonTurret.centre(w.runner.summons, 0)
		var m := _mob_at_edge(w, c, 100.0)
		_run(w, 14)
		if case == "hidden":
			w.buffs._hidden = true
		else:
			w.player_state.dead = true
		_run(w, 120)
		assert_eq(_balls(w), 0, case)
		assert_false(_hp_lost(w, m), case)
		assert_eq(w.runner.summons.turret.ball_count(), 0)
		w.buffs._hidden = false
		w.player_state.dead = false
		_run(w, 120)
		assert_true(_hp_lost(w, m), "%s: it fires again once the caster is back" % case)

func test_the_ball_cap_is_32() -> void:
	var w := SB.octopus_world(30.0, 480.0, 40.0)
	w.runner.step(DT, w)
	var c := SummonTurret.centre(w.runner.summons, 0)
	for k in 40:
		_mob_at_edge(w, c, 10.0 + 5.0 * k)
	_run(w, 14)
	assert_eq(_peak_balls(w, 60), SummonTurret.MAX_BALLS)
	assert_eq(w.runner.summons.turret.active.size(), SummonTurret.MAX_BALLS)

func test_summon_count_spaces_the_turrets_and_each_fires_and_a_recast_replaces() -> void:
	var w := SB.octopus_world()
	w.loadout.skill_mods["test_octopus"] = {"summon_count": Vector2(1.0, 1.0)}
	w.runner.step(DT, w)
	var s := w.runner.summons
	assert_eq(s.living_count(), 2)
	assert_near(s.x[1] - s.x[0], 36.0, 0.001, "ordinal_spread apart")
	var c := SummonTurret.centre(s, 0)
	_mob_at_edge(w, c, 100.0)
	_run(w, 14)
	assert_eq(_peak_balls(w, 80), 2, "both turrets fired at the one monster")
	w.runner.cooldowns["test_octopus"] = 0.0
	w.runner.step(DT, w)
	assert_eq(s.living_count(), 2, "a recast replaces the group instead of stacking")

func test_both_behaviors_run_side_by_side_in_one_world() -> void:
	var w := SB.both_world()
	w.runner.step(DT, w)
	w.runner.step(DT, w) # one cast per step
	assert_eq(w.runner.summons.living_count(), 2)
	var slot := 0 if w.runner.summons.stats[0].skill == "test_octopus" else 1
	var c := SummonTurret.centre(w.runner.summons, slot)
	var near := _mob_at_edge(w, c, 80.0)
	_run(w, 360)
	var by_skill := {}
	for e: Dictionary in _hits(w):
		by_skill[e.skill] = int(by_skill.get(e.skill, 0)) + 1
	assert_true(_hp_lost(w, near))
	assert_true(int(by_skill.get("test_octopus", 0)) >= 1, "the turret's ball landed")
	assert_eq(by_skill.get("test_gaviota", 0), 1, "and the bird struck once")

func test_the_card_text_lists_the_radius_the_ball_and_the_single_use() -> void:
	var w := SB.both_world()
	var text := SkillText.new(w.book, {str(OCTOPUS): {"name": "Test Octopus", "desc": "x", "h1": "Fires."},
		str(GAVIOTA): {"name": "Test Gaviota", "desc": "x", "h1": "Dives."}})
	var octopus := text.level_line("test_octopus", 1, w.loadout.stats("test_octopus"))
	assert_true(octopus.contains("fires a ball at monsters within 300 px"), octopus)
	w.loadout.skill_mods["test_octopus"] = {"area": Vector2(0.0, 1.5)}
	assert_true(text.level_line("test_octopus", 1, w.loadout.stats("test_octopus")).contains("within 450 px"), "area scales it")
	var gaviota := text.level_line("test_gaviota", 1, w.loadout.stats("test_gaviota"))
	assert_true(gaviota.contains("Dives once at a monster within 400 px of you, hitting up to 3, then is spent"), gaviota)
	assert_true(gaviota.contains("waiting up to 30 s for a target"), "the level time is the wait limit: " + gaviota)
	w.loadout.add_skill_mod("test_gaviota", "count", "add", 2.0)
	assert_true(text.level_line("test_gaviota", 1, w.loadout.stats("test_gaviota")).contains("hitting up to 5"), "count modifiers add strikes")

func test_the_turret_expires_at_the_level_time() -> void:
	var w := SB.octopus_world(3.0)
	w.runner.step(DT, w)
	_run(w, 60 * 3 + 5)
	assert_eq(w.runner.summons.living_count(), 0)
	_run(w, 30)
	assert_eq(w.runner.summons.active[0], 0, "the die animation ends and the slot is free")

func test_turret_events_reuse_summon_spawn_and_summon_attack() -> void:
	var w := SB.octopus_world()
	w.runner.step(DT, w)
	var c := SummonTurret.centre(w.runner.summons, 0)
	_mob_at_edge(w, c, 100.0)
	_run(w, 60)
	var types := {}
	for e: Dictionary in w.events:
		types[e.type] = true
	assert_true(types.has("summon_spawn") and types.has("summon_attack"))
	assert_false(types.has("turret_ball"), "the renderer reads the arrays instead of an event")

func test_no_monsters_in_range_draws_no_random_values() -> void:
	var twin := SB.octopus_world() # never cast: the same stream, stepped the same number of ticks
	var w := SB.octopus_world()
	w.runner.step(DT, w)
	_run(w, 200)
	_run(twin, 201)
	assert_eq(w.runner.summons.living_count(), 1)
	assert_eq(w.rng.state, twin.rng.state, "the turret itself draws nothing")

# ---------------------------------------------------------------- kamikaze

func _bird_target(w: RunWorld, i: int) -> int:
	return w.runner.summons.kamikaze.target[i]

func test_the_kamikaze_seeks_the_kth_nearest_by_ordinal() -> void:
	var w := SB.gaviota_world()
	w.loadout.skill_mods["test_gaviota"] = {"summon_count": Vector2(2.0, 1.0)}
	w.runner.step(DT, w)
	var far := _mob(w, 480.0)
	var mid := _mob(w, 350.0)
	var near := _mob(w, 300.0)
	_run(w, 20)
	assert_eq(w.runner.summons.living_count(), 3)
	assert_eq([_bird_target(w, 0), _bird_target(w, 1), _bird_target(w, 2)], [near, mid, far])

func test_an_ordinal_past_the_crowd_takes_the_farthest_in_reach() -> void:
	var w := SB.gaviota_world()
	w.loadout.skill_mods["test_gaviota"] = {"summon_count": Vector2(2.0, 1.0)}
	w.runner.step(DT, w)
	var only := _mob(w, 300.0)
	_run(w, 20)
	assert_eq([_bird_target(w, 0), _bird_target(w, 1), _bird_target(w, 2)], [only, only, only])

func test_bosses_come_before_nearer_monsters() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	var near := _mob(w, 300.0)
	var boss := _mob(w, 500.0)
	w.mob_boss[boss] = 0
	w.swarm.steady[boss] = 1
	_run(w, 20)
	assert_eq(_bird_target(w, 0), boss)
	assert_ne(_bird_target(w, 0), near)

func test_reach_is_measured_from_the_caster_not_the_bird() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	var out := _mob(w, 200.0 + 400.0 + 60.0) # r = 400 from the caster at x = 200
	var inside := _mob(w, 200.0 + 380.0)
	_run(w, 20)
	assert_eq(_bird_target(w, 0), inside)
	assert_ne(_bird_target(w, 0), out)

func test_the_bird_flies_at_follow_speed_hovering_above_its_target() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	var m := _mob(w, 480.0)
	_run(w, 20)
	var s := w.runner.summons
	var before := Vector2(s.x[0], s.y[0])
	_run(w, 10)
	var after := Vector2(s.x[0], s.y[0])
	assert_near(before.distance_to(after), 300.0 * DT * 10.0, 0.01, "follow_speed px/s toward the target")
	assert_eq(s.action[0], "fly")
	assert_eq(s.facing[0], 1, "it faces the monster")
	# Arrives: 30 px above the monster's feet.
	_run(w, 40)
	assert_near(s.x[0], w.swarm.x[m], 0.01)
	assert_near(s.y[0], w.swarm.y[m] - 30.0, 0.01)

func test_the_strike_starts_at_the_boxs_half_width_and_hits_once_at_attack_after() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	var m := _mob(w, 480.0)
	_run(w, 14)
	w.drain_events()
	var s := w.runner.summons
	var started := -1
	var hit_tick := -1
	for tick in 240:
		w.runner.tick_cooldowns(DT, w)
		if started < 0 and s.action[0] == "attack1":
			started = tick
			assert_true(Vector2(s.x[0], s.y[0]).distance_to(Vector2(w.swarm.x[m], w.swarm.y[m] - 30.0)) <= 80.0 + 300.0 * DT,
				"it dives once within the box's half-width (80 px)")
		if hit_tick < 0 and _hp_lost(w, m):
			hit_tick = tick
			break
	assert_true(started > 0 and hit_tick > started)
	assert_eq(hit_tick - started, ceili(0.4 / DT - 1e-6), "the hit lands at attackAfter")

func test_single_hit_then_die_and_the_slot_is_freed() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	var m := _mob(w, 330.0)
	_run(w, 14)
	w.drain_events()
	_run(w, 200)
	assert_eq(_hits(w).size(), 1, "one monster, struck exactly once")
	assert_eq(w.runner.summons.living_count(), 0, "single use: nothing left able to attack")
	assert_eq(w.runner.summons.action[0], "die")
	_run(w, 30)
	assert_eq(w.runner.summons.active[0], 0, "the slot is free after the die animation")
	_run(w, 200)
	assert_eq(_hits(w).size(), 1, "and it never strikes again")
	assert_true(_hp_lost(w, m))

func test_the_strike_hits_up_to_mob_count_monsters_in_the_box() -> void:
	var w := SB.gaviota_world(30.0, 400.0, 3.0)
	w.runner.step(DT, w)
	var cluster: Array[int] = []
	for k in 5:
		cluster.append(_mob(w, 330.0 + 6.0 * k))
	_run(w, 14)
	w.drain_events()
	_run(w, 200)
	assert_eq(_hits(w).size(), 3, "mobCount 3 of five in the box")
	var lost := 0
	for m in cluster:
		lost += 1 if _hp_lost(w, m) else 0
	assert_eq(lost, 3)

func test_the_unspent_bird_waits_by_the_caster_and_expires_with_no_hit() -> void:
	var w := SB.gaviota_world(3.0)
	w.runner.step(DT, w)
	var far := _mob(w, 200.0 + 400.0 + 80.0) # out of reach
	_run(w, 20)
	var s := w.runner.summons
	assert_eq(_bird_target(w, 0), -1)
	w.drain_events()
	w.player.pos.x -= 150.0
	_run(w, 120)
	assert_true(absf(s.x[0] - (w.player.pos.x + 60.0)) < 1.0, "it trails the caster: %f vs %f" % [s.x[0], w.player.pos.x])
	_run(w, 60)
	assert_eq(s.living_count(), 0, "the level time is over")
	_run(w, 30)
	assert_eq(s.active[0], 0)
	assert_eq(_hits(w).size(), 0, "expired unspent: no hit and no refund")
	assert_false(_hp_lost(w, far))

func test_a_bird_that_has_locked_a_target_outlives_the_wait_limit_and_strikes() -> void:
	var w := SB.gaviota_world(1.0)
	w.runner.step(DT, w)
	_run(w, 50) # 0.83 s of the 1 s wait with nothing in reach
	var m := _mob(w, 200.0 + 380.0) # about 1.3 s of flight at 300 px/s: the level time ends mid-flight
	_run(w, 5)
	assert_eq(_bird_target(w, 0), m)
	w.drain_events()
	_run(w, 200)
	assert_true(_hp_lost(w, m), "the dive lands although the level time ran out on the way")
	assert_eq(_hits(w).size(), 1)
	_run(w, 40)
	assert_eq(w.runner.summons.living_count(), 0)
	assert_eq(w.runner.summons.active[0], 0, "and the spent bird still frees its slot")

func test_the_wait_limit_still_ends_a_bird_whose_target_died() -> void:
	var w := SB.gaviota_world(2.0)
	w.runner.step(DT, w)
	var m := _mob(w, 200.0 + 380.0)
	_run(w, 20)
	assert_eq(_bird_target(w, 0), m)
	w.swarm.despawn(m)
	_run(w, 200)
	assert_eq(w.runner.summons.living_count(), 0, "nothing left to hunt: the level time ends it")
	assert_eq(_hits(w).size(), 0)

func test_a_monster_reachable_from_the_cast_origin_is_in_the_birds_reach() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w) # admission measures from the cast origin (body height), so the bird must too
	var cast := w.cast_origin()
	var m := _mob(w, cast.x + 380.0)
	w.swarm.y[m] -= (w.mob_center(m).y - cast.y) + sqrt(399.0 * 399.0 - 380.0 * 380.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	assert_near(w.mob_center(m).distance_to(cast), 399.0, 1.0)
	assert_true(w.mob_center(m).distance_to(w.player.pos) > 400.0, "measured from the feet it would be out")
	_run(w, 20)
	assert_eq(_bird_target(w, 0), m)

func test_a_monster_that_comes_into_reach_later_is_hunted() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	var m := _mob(w, 200.0 + 500.0)
	_run(w, 30)
	assert_eq(_bird_target(w, 0), -1)
	_move_mob(w, m, 200.0 + 350.0)
	_run(w, 300)
	assert_true(_hp_lost(w, m))
	assert_eq(w.runner.summons.living_count(), 0)

func test_a_monster_that_dies_before_the_dive_gets_the_bird_a_new_target() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	var first := _mob(w, 450.0)
	var second := _mob(w, 480.0)
	_run(w, 20)
	assert_eq(_bird_target(w, 0), first)
	w.swarm.despawn(first)
	_run(w, 2)
	assert_eq(_bird_target(w, 0), second)

func test_a_map_transfer_clears_the_kamikaze() -> void:
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	_mob(w, 400.0)
	_run(w, 30)
	assert_eq(w.runner.summons.living_count(), 1)
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.summons.living_count(), 0)

func test_the_kamikaze_with_nothing_in_reach_draws_no_random_values() -> void:
	var twin := SB.gaviota_world()
	var w := SB.gaviota_world()
	w.runner.step(DT, w)
	_run(w, 200)
	_run(twin, 201)
	assert_eq(w.runner.summons.living_count(), 1)
	assert_eq(w.rng.state, twin.rng.state)
