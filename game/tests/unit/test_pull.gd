extends TestCase
## The shared `pull` skill block (#300, docs/GAME_DESIGN.md 7.35): synthetic skill tables, hand-built platforms, seeded
## worlds and fixed 1/60 s ticks. The mirror of the knockback tests in test_combat_mechanics.

const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const BOSS := 2220000
const FLYER := 9300063
const CASTER_X := 1000.0

## A flat floor wide enough that nothing walks off it.
const FLAT := [{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}]


## A world on `segments` with the caster at x 1000. Rank 1 of the synthetic skill has mobCount 3, prop 100 and x 72 (used
## as a 72% chance field); rank 2 has mobCount 4 and prop 0. `pull` is merged over the default block.
func _world(segments: Array = FLAT, pull: Dictionary = {}, extra: Dictionary = {}) -> RunWorld:
	var block := {"chance_field": "prop", "range_field": "range", "min_gap": 60}
	block.merge(pull, true)
	var def := {"pull": block, "range": 600.0}
	def.merge(extra, true)
	var w := CF.world(def)
	w.bounds = Rect2(0, -500, 2000, 1000)
	w.fhm = FootholdMap.from_segments(segments)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	return w


func _pull(w: RunWorld) -> int:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var st := w.loadout.stats("synthetic")
	return w.runner.apply_pull(w, "synthetic", st, w.cast_origin())


func test_pulls_toward_the_caster_from_both_sides_and_stops_min_gap_away() -> void:
	var w := _world()
	var right := RF.put_mob(w, MOB, 1400)
	var left := RF.put_mob(w, MOB, 500)
	w.swarm.apply_status(right, "stun", {"time": 3}, w.events)
	assert_eq(_pull(w), 2)
	assert_near(w.swarm.x[right], CASTER_X + 60.0, 0.01)
	assert_near(w.swarm.x[left], CASTER_X - 60.0, 0.01)
	assert_near(w.swarm.status_time(right, MobSwarm.STUN), 3, 0.001, "statuses survive")
	var pulled := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_pulled")
	assert_eq(pulled.size(), 2)
	assert_eq(pulled[0].mob, left, "farthest first")


func test_min_gap_is_honoured_and_never_overshoots_the_caster() -> void:
	var w := _world(FLAT, {"min_gap": 200})
	var far := RF.put_mob(w, MOB, 1400)
	var inside := RF.put_mob(w, MOB, 1150)
	assert_eq(_pull(w), 1, "a mob already inside the gap is rolled but not moved")
	assert_near(w.swarm.x[far], CASTER_X + 200.0, 0.01)
	assert_near(w.swarm.x[inside], 1150)
	var w0 := _world(FLAT, {"min_gap": 0})
	var m := RF.put_mob(w0, MOB, 1400)
	_pull(w0)
	assert_near(w0.swarm.x[m], CASTER_X, 0.01, "a zero gap lands on the caster, never past")


func test_stops_at_the_platform_edge() -> void:
	# The caster stands on the left floor; the mob stands on a separate floor to the right with a drop between them.
	var w := _world([{"x1": 0, "y1": 200, "x2": 1100, "y2": 200}, {"x1": 1300, "y1": 200, "x2": 1500, "y2": 200}])
	var m := RF.put_mob(w, MOB, 1450)
	assert_eq(w.swarm.fh[m], 1)
	assert_eq(_pull(w), 1)
	assert_near(w.swarm.x[m], 1300, 0.01, "slides to the end of its own platform and no further")
	assert_eq(w.swarm.fh[m], 1)


func test_follows_slopes_across_linked_footholds() -> void:
	# Flat floor under the caster, a slope up to a higher flat floor where the mob stands.
	var w := _world([{"x1": 0, "y1": 200, "x2": 1100, "y2": 200}, {"x1": 1100, "y1": 200, "x2": 1300, "y2": 100},
		{"x1": 1300, "y1": 100, "x2": 1800, "y2": 100}])
	var m := RF.put_mob(w, MOB, 1500, 90)
	assert_eq(w.swarm.fh[m], 2)
	assert_eq(_pull(w), 1)
	assert_eq(w.swarm.pos(m), Vector2(CASTER_X + 60.0, 200), "down the slope onto the caster's floor")
	assert_eq(w.swarm.fh[m], 0)


func test_stops_at_a_wall() -> void:
	var w := _world([{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}, {"x1": 1300, "y1": 200, "x2": 1300, "y2": 100}])
	var m := RF.put_mob(w, MOB, 1500)
	assert_eq(_pull(w), 1)
	assert_near(w.swarm.x[m], 1300 + FootholdMap.EPS, 0.001)


func test_skips_bosses_and_flyers_without_spending_target_slots() -> void:
	var w := _world()
	var boss := RF.put_mob(w, BOSS, 1500)
	var scheduled := RF.put_mob(w, MOB, 1480)
	w.swarm.steady[scheduled] = 1
	var flyer := RF.put_mob(w, FLYER, 1460)
	w.swarm.fh[flyer] = -1
	var a := RF.put_mob(w, MOB, 1200)
	var b := RF.put_mob(w, MOB, 1250)
	var c := RF.put_mob(w, MOB, 1300)
	var before_boss := w.swarm.pos(boss)
	var before_sched := w.swarm.pos(scheduled)
	var before_fly := w.swarm.pos(flyer)
	assert_eq(_pull(w), 3, "the three-mob cap is filled by the ordinary mobs behind the skipped ones")
	assert_eq(w.swarm.pos(boss), before_boss)
	assert_eq(w.swarm.pos(scheduled), before_sched)
	assert_eq(w.swarm.pos(flyer), before_fly)
	for m in [a, b, c]:
		assert_near(w.swarm.x[m], CASTER_X + 60.0, 0.01)


func test_selection_is_farthest_first_with_a_120_px_floor_and_the_mob_count_cap() -> void:
	var w := _world()
	var near := RF.put_mob(w, MOB, CASTER_X + 100)
	var edge := RF.put_mob(w, MOB, CASTER_X - 119)
	var x200 := RF.put_mob(w, MOB, CASTER_X + 200)
	var x300 := RF.put_mob(w, MOB, CASTER_X - 300)
	var x400 := RF.put_mob(w, MOB, CASTER_X + 400)
	var x500 := RF.put_mob(w, MOB, CASTER_X - 500)
	assert_eq(_pull(w), 3, "mobCount 3 at rank 1")
	assert_near(w.swarm.x[x500], CASTER_X - 60.0, 0.01)
	assert_near(w.swarm.x[x400], CASTER_X + 60.0, 0.01)
	assert_near(w.swarm.x[x300], CASTER_X - 60.0, 0.01)
	assert_near(w.swarm.x[x200], CASTER_X + 200, 0.01, "fourth farthest is over the cap")
	assert_near(w.swarm.x[near], CASTER_X + 100, 0.01, "under the 120 px floor")
	assert_near(w.swarm.x[edge], CASTER_X - 119, 0.01, "under the 120 px floor")
	w.loadout.set_rank("synthetic", 2)
	assert_eq(w.loadout.stats("synthetic").mob_count, 4)


func test_equal_distance_ties_resolve_by_slot_and_the_floor_is_inclusive() -> void:
	var w := _world(FLAT, {}, {})
	var first := RF.put_mob(w, MOB, CASTER_X + 300)
	var second := RF.put_mob(w, MOB, CASTER_X - 300)
	var third := RF.put_mob(w, MOB, CASTER_X + 300)
	var fourth := RF.put_mob(w, MOB, CASTER_X - 120)
	var fifth := RF.put_mob(w, MOB, CASTER_X + 300)
	assert_eq(_pull(w), 3)
	for m in [first, second, third]:
		assert_near(absf(w.swarm.x[m] - CASTER_X), 60.0, 0.01)
	assert_near(w.swarm.x[fifth], CASTER_X + 300, 0.01, "lower slots win the tie")
	assert_near(w.swarm.x[fourth], CASTER_X - 120, 0.01, "exactly 120 px is eligible but ranks last here")


func test_range_field_bounds_the_candidates_and_the_floor_is_overridable() -> void:
	var w := _world(FLAT, {}, {"range": 350})
	var inside := RF.put_mob(w, MOB, CASTER_X + 340)
	var outside := RF.put_mob(w, MOB, CASTER_X + 380)
	assert_eq(_pull(w), 1)
	assert_near(w.swarm.x[inside], CASTER_X + 60.0, 0.01)
	assert_near(w.swarm.x[outside], CASTER_X + 380, 0.01)
	var w2 := _world(FLAT, {"min_distance": 300})
	var m := RF.put_mob(w2, MOB, CASTER_X + 250)
	assert_eq(_pull(w2), 0)
	assert_near(w2.swarm.x[m], CASTER_X + 250, 0.01)


func test_a_partial_chance_draws_one_value_per_candidate_on_the_main_stream() -> void:
	var w := _world(FLAT, {"chance_field": "x"})  # rank 1: 72%
	var control := _world(FLAT, {"chance_field": "x"})
	var mobs: Array[int] = []
	for k in 5:
		mobs.append(RF.put_mob(w, MOB, CASTER_X + 200 + k * 50))
	var rolls: Array[float] = []
	for k in 3:
		rolls.append(control.rng.randf() * 100.0)
	_pull(w)
	assert_eq(w.rng.state, control.rng.state, "exactly three draws: one per candidate (mobCount), none for the rest")
	# Candidates are the three farthest, in farthest-first order; each pulled iff its own draw was under 72.
	for k in 3:
		var slot := mobs[4 - k]
		var pulled := absf(w.swarm.x[slot] - CASTER_X) < 100.0
		assert_eq(pulled, rolls[k] < 72.0, "candidate %d follows draw %d" % [k, k])
	for stream: String in ["final_rng", "spawn_rng", "drop_rng", "card_rng", "potion_rng", "meso_rng", "equip_rng",
			"scroll_rng", "reward_rng", "pirate_rng"]:
		assert_eq((w.get(stream) as RandomNumberGenerator).state, (control.get(stream) as RandomNumberGenerator).state,
			stream)


func test_a_miss_costs_a_draw_and_moves_nothing() -> void:
	var w := _world(FLAT, {"chance_field": "x"}, {"ranks": [2, 1]})  # rank 1 reads level 2: x 130 is >= 100
	var m := RF.put_mob(w, MOB, CASTER_X + 300)
	assert_eq(_pull(w), 1)
	var w0 := _world(FLAT, {"chance_field": "prop"}, {"ranks": [2, 1]})  # level 2: prop 0
	var z := RF.put_mob(w0, MOB, CASTER_X + 300)
	var control := _world(FLAT, {"chance_field": "prop"}, {"ranks": [2, 1]})
	control.rng.randf()
	assert_eq(_pull(w0), 0, "0% never pulls")
	assert_near(w0.swarm.x[z], CASTER_X + 300, 0.01)
	assert_eq(w0.rng.state, control.rng.state, "but still spends its one draw")
	assert_near(w.swarm.x[m], CASTER_X + 60.0, 0.01)


func test_a_certain_chance_draws_nothing() -> void:
	var w := _world()  # prop 100
	var control := _world()
	for k in 4:
		RF.put_mob(w, MOB, CASTER_X + 200 + k * 60)
	assert_eq(_pull(w), 3)
	assert_eq(w.rng.state, control.rng.state, "no draw at 100%")
	var no_field := _world(FLAT, {"chance_field": ""})
	var untouched := _world(FLAT, {"chance_field": ""})
	RF.put_mob(no_field, MOB, CASTER_X + 300)
	assert_eq(_pull(no_field), 1, "no chance field means always")
	assert_eq(no_field.rng.state, untouched.rng.state)


func test_pull_is_a_pure_function_of_the_seed() -> void:
	var digests: Array[String] = []
	for run in 2:
		var w := _world(FLAT, {"chance_field": "x"})
		for k in 8:
			RF.put_mob(w, MOB, CASTER_X + (k - 4) * 90 + 45)
		for cast in 3:
			_pull(w)
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(var_to_bytes(w.events))
		digest.update(var_to_bytes(w.rng.state))
		digests.append(digest.finish().hex_encode())
	assert_eq(digests[0], digests[1])


## A skill with a pull block and no damage pulls from a normal auto-cast; a skill without the block never calls it.
func test_an_auto_cast_with_a_pull_block_pulls_and_deals_no_damage() -> void:
	var w := _world(FLAT, {}, {"damage": "none", "cast": {"rule": "range_around"}, "cooldown": 10.0})
	var m := RF.put_mob(w, MOB, CASTER_X + 400)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.cast_ready(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(w.swarm.x[m], CASTER_X + 60.0, 0.01)
	var types := w.events.map(func(e: Dictionary) -> String: return e.type)
	assert_true(types.has("cast"))
	assert_true(types.has("mob_pulled"))
	assert_false(types.has("mob_hit"), "pull alone deals no damage")
	var plain := CF.world({"range": 600.0, "cast": {"rule": "range_around"}})
	var p := RF.put_mob(plain, MOB, 600)
	plain.mob_grid.rebuild(plain.swarm.x, plain.swarm.y, plain.swarm.active)
	plain.drain_events()
	plain.runner.cast_ready(DT, plain)
	assert_near(plain.swarm.x[p], 600, 0.01, "no pull block, no pull")
	assert_false(plain.events.any(func(e: Dictionary) -> bool: return e.type == "mob_pulled"))


func test_loadout_exposes_the_pull_numbers_and_a_skill_without_the_block_reports_none() -> void:
	var w := _world(FLAT, {"chance_field": "x", "min_gap": 80})
	var st := w.loadout.stats("synthetic")
	assert_near(float(st.pull_chance), 72.0)
	assert_near(float(st.pull_gap), 80.0)
	var plain := CF.world()
	assert_near(float(plain.loadout.stats("synthetic").pull_chance), 0.0)


func test_pull_waits_until_three_pullable_targets_are_present() -> void:
	var w := _world(FLAT, {}, {"damage": "none", "cast": {"rule": "range_around", "min_targets": 3}, "cooldown": 10.0})
	for dx in [10, 30, 50]:
		RF.put_mob(w, MOB, CASTER_X + dx)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "adjacent mobs cannot spend the pull cooldown")
	for dx in [200, 300, 400]:
		RF.put_mob(w, MOB, CASTER_X + dx)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)


func test_pull_admission_keeps_the_damage_targets_of_a_combined_skill() -> void:
	var w := _world(FLAT, {}, {"cast": {"rule": "range_around"}})
	RF.put_mob(w, MOB, CASTER_X + 300)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	assert_true(w.events.any(func(e: Dictionary) -> bool: return e.type == "mob_hit"),
		"pull admission must retain the normal damaging cast plan")
