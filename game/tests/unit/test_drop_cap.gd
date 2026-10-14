extends TestCase
## A capped seeded RunWorld still drops EXP at new kills, absorbs the drop farthest from the player, and lets the
## player collect all of that EXP. Observations use pickup state and run events, not private pool bookkeeping.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_capped_drops_move_farthest_exp_to_the_new_kill_and_are_collected() -> void:
	var w := RF.quiet_world(120, 15)
	w.pickups.tuning.max_active = 2
	w.pickups.spawn(Vector2(100, 200), 10, 4000019)
	w.pickups.spawn(Vector2(1000, 200), 20, 4000019)
	var mob := RF.put_mob(w, 100100, 110, 200)
	w.drain_events()
	w.hit_mob(mob, {"damage_min": 1000.0, "damage_max": 1000.0, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)
	var spawned := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
	assert_eq(spawned.size(), 1, "a new drop event is emitted even at the cap")
	if not spawned.is_empty():
		assert_eq(spawned[0].pos, Vector2(110, 200))
	var values := {}
	var total := 0
	for i in w.pickups.capacity():
		if w.pickups.active[i] != 0:
			values[Vector2(w.pickups.x[i], w.pickups.y[i])] = w.pickups.exp[i]
			total += w.pickups.exp[i]
	assert_eq(values, {Vector2(100, 200): 10, Vector2(110, 200): 23}, "far drop's 20 EXP joins the snail's 3")
	assert_eq(total, 33, "all old EXP plus the new kill is preserved")
	assert_eq(w.pickups.active_count(), 2, "drop count stays capped")
	for i in 15:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
	assert_eq(w.pickups.collected_exp, 33, "EXP now lies within collection reach")
	assert_eq(w.pickups.active_count(), 0)


func test_farthest_is_measured_from_the_player_instead_of_the_new_drop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 15
	var pk := PickupSystem.new(2, {"max_active": 2}, rng)
	pk.spawn(Vector2(100, 0), 10, 4000019)
	var near_player := pk.spawn(Vector2(900, 0), 20, 4000019)
	var fresh := pk.spawn(Vector2(0, 0), 23, 4000011, Vector2(1000, 0))
	assert_eq(pk.exp[near_player], 20, "the old drop near the player remains intact")
	assert_eq(pk.exp[fresh], 33, "the farther old drop is absorbed")
	assert_eq(Vector2(pk.x[fresh], pk.y[fresh]), Vector2.ZERO)
	assert_eq(pk.item_id[fresh], 4000011, "the fresh drop uses the new monster's icon")
