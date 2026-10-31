extends TestCase
## Meso drops (spec #33, #107): sprite brackets, per-mob amount ranges, the pickup kind, kill drops, collection into
## the character's mesos, and the carry through a CharacterSnapshot. Seeded RNG, fixed 1/60 s ticks, synthetic map.

const WF := preload("res://tests/fixtures/world_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _floor() -> FootholdMap:
	return FootholdMap.from_segments(WF.tiers_segments())


# --- sprite brackets (tier B) ---

func test_sprite_brackets_at_the_boundaries() -> void:
	assert_eq(MesoDrops.sprite_item(1), 9000000, "1 = bronze")
	assert_eq(MesoDrops.sprite_item(49), 9000000, "49 = bronze")
	assert_eq(MesoDrops.sprite_item(50), 9000001, "50 = gold")
	assert_eq(MesoDrops.sprite_item(99), 9000001, "99 = gold")
	assert_eq(MesoDrops.sprite_item(100), 9000002, "100 = bundle")
	assert_eq(MesoDrops.sprite_item(999), 9000002, "999 = bundle")
	assert_eq(MesoDrops.sprite_item(1000), 9000003, "1000 = bag")
	assert_eq(MesoDrops.sprite_item(123456), 9000003, "huge = bag")


# --- amounts ---

func test_listed_range_wins_and_fallback_follows_the_level() -> void:
	assert_eq(MesoDrops.amount_range(1, [4, 6], {}), Vector2i(4, 6))
	var fb := {"base": 4.0, "per_level": 1.5, "low": 0.8, "high": 1.2}
	# level 1: centre 5.5 -> 4..7 (the v83 Snail drops 4-6)
	var r := MesoDrops.amount_range(1, [], fb)
	assert_eq(r, Vector2i(4, 7))
	var r50 := MesoDrops.amount_range(50, [], fb)
	assert_true(r50.x > r.x and r50.y > r.y, "higher level, more mesos")
	assert_true(r50.y > r50.x, "never an empty range")


func test_roll_is_uniform_in_min_inclusive_max_exclusive_and_scaled() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var seen := {}
	for i in 400:
		seen[MesoDrops.roll(rng, Vector2i(4, 6), 1.0)] = true
	assert_eq(seen.keys().size(), 2, "only 4 and 5")
	assert_true(seen.has(4) and seen.has(5), "both ends of [4, 6) occur")
	assert_eq(MesoDrops.roll(rng, Vector2i(10, 11), 2.5), 25, "multiplier applies to the rolled amount")
	assert_eq(MesoDrops.roll(rng, Vector2i(3, 3), 1.0), 3, "a degenerate range returns its minimum")
	assert_eq(MesoDrops.roll(rng, Vector2i(1, 2), 0.1), 1, "never below 1")


# --- PickupSystem MESO kind ---

func test_meso_pickup_is_magnetised_and_collected_with_its_amount() -> void:
	var pk := PickupSystem.new(8, {"spread": 0.0})
	var fhm := _floor()
	var ev: Array = []
	var i := pk.spawn_meso(Vector2(500, 0), 120)
	assert_eq(pk.kind[i], PickupSystem.MESO)
	assert_eq(pk.item_id[i], 9000002, "sprite chosen from the amount")
	assert_eq(pk.exp_count(), 0, "mesos are not EXP drops")
	for t in 30:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev)
	var got_exp := 0
	for t in 120:
		got_exp += pk.step(DT, Vector2(570, 0), 90.0, fhm, ev)
	assert_eq(got_exp, 0, "no EXP from a meso")
	assert_eq(pk.collected_mesos, 120)
	assert_eq(pk.active_count(), 0)
	assert_eq(ev.size(), 1)
	if ev.size() == 1:
		assert_eq(ev[0].type, "pickup_collected")
		assert_eq(ev[0].kind, "meso")
		assert_eq(ev[0].count, 120)
		assert_eq(ev[0].item_id, 9000002)
		assert_eq(ev[0].exp, 0)


func test_step_mesos_report_this_tick_only() -> void:
	var pk := PickupSystem.new(8, {"spread": 0.0})
	var fhm := _floor()
	var ev: Array = []
	pk.spawn_meso(Vector2(570, 0), 7)
	var total := 0
	for t in 120:
		pk.step(DT, Vector2(570, 0), 90.0, fhm, ev)
		total += pk.step_mesos
	assert_eq(total, 7)
	assert_eq(pk.step_mesos, 0, "reset every step")


func test_mesos_never_expire_merge_or_count_toward_the_exp_cap() -> void:
	var pk := PickupSystem.new(8, {"spread": 0.0, "lifetime": 1.0, "fade": 0.5, "max_active": 1})
	var fhm := _floor()
	var ev: Array = []
	var m := pk.spawn_meso(Vector2(500, 0), 30)
	pk.spawn(Vector2(100, 0), 5, 4000019, Vector2(2000, 0))
	var b :=pk.spawn(Vector2(120, 0), 6, 4000019, Vector2(2000, 0))
	assert_true(pk.merged, "the second EXP drop hits the cap of one and absorbs the first")
	assert_eq(pk.active[m], 1, "the meso is not the absorbed drop")
	for t in 600:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev)
	assert_eq(pk.active[m], 1, "10 s past a 1 s lifetime and still there")
	assert_eq(pk.alpha(m), 1.0, "never fades")
	assert_eq(pk.expired, 1, "only the EXP drop expired")
	assert_eq(pk.active[b], 0)


# --- RunWorld: kills drop mesos, the magnet collects them, the character carries them ---

func _world(chance: float, mult: float = 1.0, p_seed: int = 15) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.mesos.chance = chance
	data.balance.mesos.mult = mult
	data.balance.mesos.boss_drops = 3
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	var w := RunWorld.new(RF.setup("quiet", p_seed, data))
	RF.place_player(w, 400)
	w.god = true
	return w


func _kill_at(w: RunWorld, mob_id: int, x: float) -> void:
	var slot := RF.put_mob(w, mob_id, x)
	w.hit_mob(slot, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)


func _meso_spawns(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned" and e.kind == "meso")


func test_a_kill_drops_a_listed_range_meso_with_its_sprite_and_the_magnet_collects_it() -> void:
	var w := _world(1.0)
	w.drain_events()
	_kill_at(w, 100100, 405)  # Snail: v83 4-6 mesos, uniform in [4, 6)
	var spawned := _meso_spawns(w.drain_events())
	assert_eq(spawned.size(), 1, "chance 1.0 always drops")
	if spawned.is_empty():
		return
	var amount: int = spawned[0].count
	assert_true(amount == 4 or amount == 5, "Snail drops 4 or 5, not %d" % amount)
	assert_eq(spawned[0].item_id, 9000000, "a Snail's coins are bronze")
	var collected := 0
	for i in 120:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "pickup_collected" and e.kind == "meso":
				collected += int(e.count)
	assert_eq(collected, amount, "the magnet collected the drop")
	assert_eq(w.mesos, amount, "the character's mesos rose by exactly the collected sum")
	assert_eq(w.pickups.collected_mesos, amount)


func test_chance_zero_drops_nothing_and_the_multiplier_scales_amounts() -> void:
	var none := _world(0.0)
	none.drain_events()
	for i in 20:
		_kill_at(none, 100100, 405)
	assert_eq(_meso_spawns(none.drain_events()).size(), 0)
	var scaled := _world(1.0, 3.0)
	scaled.drain_events()
	_kill_at(scaled, 100100, 405)
	var s := _meso_spawns(scaled.drain_events())
	assert_eq(s.size(), 1)
	if s.size() == 1:
		assert_true(int(s[0].count) in [12, 15], "3 x (4 or 5)")


func test_the_configured_chance_is_the_drop_rate() -> void:
	var w := _world(0.4)
	w.drain_events()
	var drops := 0
	var kills := 500
	for i in kills:
		_kill_at(w, 100100, 405)
		drops += _meso_spawns(w.drain_events()).size()
		for p in w.pickups.capacity():
			w.pickups.despawn(p)
	# Binomial(500, 0.4): mean 200, sd 11; the seeded run must sit within four sd.
	assert_between(float(drops), 156.0, 244.0, "about 40% of kills drop mesos")


func test_collected_mesos_equal_the_sum_of_every_drop_across_mob_kinds() -> void:
	var w := _world(1.0)
	w.drain_events()
	var dropped := 0
	for id: int in [100100, 1110100, 2220000, 1110100, 100100]:
		_kill_at(w, id, 400)
		for e: Dictionary in _meso_spawns(w.drain_events()):
			dropped += int(e.count)
	assert_true(dropped > 0)
	for i in 240:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
	assert_eq(w.mesos, dropped, "every dropped meso reached the character")


func test_meso_drops_do_not_count_toward_the_exp_drop_cap() -> void:
	var w := _world(1.0)
	w.pickups.tuning.max_active = 1
	w.drain_events()
	_kill_at(w, 100100, 405)
	_kill_at(w, 100100, 405)
	assert_eq(w.pickups.exp_count(), 1, "EXP capped at one drop; mesos are separate")
	var mesos := 0
	for i in w.pickups.capacity():
		if w.pickups.active[i] != 0 and w.pickups.kind[i] == PickupSystem.MESO:
			mesos += 1
	assert_eq(mesos, 2, "both kills' mesos lie on the ground")


func test_a_boss_drops_its_configured_number_of_range_rolled_bundles() -> void:
	var data := RF.quiet_data()
	data.balance.mesos.mult = 1.0
	data.balance.mesos.boss_drops = 3
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0,
		"rewards": {"exp_mult": 5, "exp_drops": 2, "spread": 100, "potions": {"hp": 1, "mp": 1}, "bonus_choices": 1}}])
	var w := RunWorld.new(RF.setup("quiet", 20, data))
	RF.place_player(w, 400)
	w.god = true
	for i in 6:
		w.step(DT, MoveInput.new())
	w.drain_events()
	w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	var spawned := _meso_spawns(w.drain_events())
	assert_eq(spawned.size(), 3, "boss_drops bundles")
	for e: Dictionary in spawned:
		assert_between(float(e.count), 30.0, 69.0, "Mano's v83 range is 30-70 mesos, [30, 70)")


func test_mesos_carry_through_a_snapshot_into_the_next_round_and_a_json_round_trip() -> void:
	var w := _world(1.0)
	w.mesos = 4321
	var snapshot := w.character_snapshot()
	assert_eq(snapshot.mesos, 4321)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	var setup := RF.setup("quiet", 99, RF.quiet_data())
	setup.character = parsed
	var next := RunWorld.new(setup)
	assert_eq(next.mesos, 4321, "carried into the next round")
	assert_eq(next.character_snapshot().mesos, 4321)


# --- survivor data ---

func test_data_lists_the_v83_ranges_for_every_roster_mob_and_boss() -> void:
	var data := DataRepo.load_all()
	var mobs: Dictionary = data.mobs.mobs
	# Facts from the ticket's v83 server drop data (min, max).
	var expected := {100100: [4, 6], 1110100: [28, 42], 2300100: [32, 48], 3230100: [60, 90], 3230300: [94, 144],
		7130100: [340, 500], 2220000: [30, 70], 6130101: [800, 1196], 6300005: [765, 3770], 8220009: [1479, 7280],
		8130100: [1621, 2387]}
	for id: int in expected:
		var listed: Array = mobs[str(id)].get("mesos", [])
		assert_eq([int(listed[0]), int(listed[1])] if listed.size() == 2 else [], expected[id], "mesos of %d" % id)
	var no_range := [9300003, 9300062, 9300063, 9300064, 4090000, 3300008, 3300005, 5220002, 5220001,
		4130103, 9300012, 5220003, 4240000, 5120100, 6220001, 6090001, 6090000, 8220001, 6090003, 7130401, 7220001, 3220001, 8110300, 8220002, 9400120, 9400121, 9400014, 8180000, 8180001, 8220003, 5220004, 7220000, 7220002]
	# ... no v83 drop row (#452 bosses: none used): the level fallback applies
	var stages: Dictionary = data.stages.stages
	var ids := {}
	for key: String in stages:
		var st: Dictionary = stages[key]
		for id: Variant in st.get("original_life", {}):
			ids[int(id)] = true
		for kf: Dictionary in st.keyframes:
			for id: Variant in kf.get("pool", {}):
				ids[int(id)] = true
		for b: Dictionary in DataRepo.stage_bosses(st):
			ids[int(b.mob_id)] = true
	for id: int in ids:
		var listed: Array = mobs.get(str(id), {}).get("mesos", [])
		if id in no_range:
			assert_eq(listed.size(), 0, "%d uses the fallback" % id)
		else:
			assert_eq(listed.size(), 2, "%d lists a v83 meso range" % id)
			if listed.size() == 2:
				assert_true(int(listed[0]) < int(listed[1]), "%d range is non-empty" % id)
