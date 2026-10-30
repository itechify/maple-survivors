extends TestCase
## GroundStrike (spec #383, NL8 #407): the pure pulse arithmetic of a damaging ground zone and the data-file checks of the
## `ground.strike` and `knockback.distance_by_rank` blocks. The behaviour of the zone in a run is test_night_lord_crowd.gd.


func test_a_strike_zone_pulses_at_first_delay_then_every_interval() -> void:
	assert_eq(GroundStrike.strike_count(0.3, 1.0, 4.0), 4, "0.3, 1.3, 2.3, 3.3")
	assert_eq(GroundStrike.strike_count(0.3, 1.0, 8.0), 8)
	assert_eq(GroundStrike.strike_count(0.3, 1.0, 12.0), 12)
	assert_near(GroundStrike.strike_time(0.3, 1.0, 0), 0.3, 1e-9)
	assert_near(GroundStrike.strike_time(0.3, 1.0, 3), 3.3, 1e-9)


func test_the_last_strike_is_at_or_before_the_lifetime() -> void:
	assert_eq(GroundStrike.strike_count(1.0, 1.0, 4.0), 4, "a strike exactly at the end still lands")
	assert_eq(GroundStrike.strike_count(0.3, 1.0, 0.2), 0, "a zone that ends before its first strike never strikes")
	assert_eq(GroundStrike.strike_count(0.3, 1.0, 0.3), 1)
	assert_eq(GroundStrike.strike_count(0.0, 0.5, 2.0), 5, "first_delay 0 strikes on the cast tick")
	assert_eq(GroundStrike.strike_count(0.3, 1.0, 0.0), 0)


func test_the_block_defaults_and_reads() -> void:
	assert_eq(GroundStrike.spec({"strike": {"interval": 1.0, "first_delay": 0.3}}), {"interval": 1.0, "first_delay": 0.3})
	assert_eq(GroundStrike.spec({"strike": {}}), {"interval": 1.0, "first_delay": 0.3}, "tier C defaults")
	assert_eq(GroundStrike.spec({"strike": {"interval": 2.0}}), {"interval": 2.0, "first_delay": 0.3})
	assert_eq(GroundStrike.spec({"status": "poison", "interval": 1.0}), {}, "a status zone has no strike")
	assert_eq(GroundStrike.spec({}), {})
	assert_true(GroundStrike.is_strike({"strike": {}}))
	assert_false(GroundStrike.is_strike({"status": "poison"}))


func test_the_target_limit_is_the_resolved_monster_count() -> void:
	assert_eq(GroundStrike.target_limit({"mob_count": 6}), 6)
	assert_eq(GroundStrike.target_limit({"mob_count": 8}), 8, "an Ambush Squad card makes it 8")
	assert_eq(GroundStrike.target_limit({"mob_count": 0}), 1, "never less than one")
	assert_eq(GroundStrike.target_limit({}), 1)


func _errors(ground: Dictionary) -> PackedStringArray:
	return GroundStrike.errors({"skills": {"zone": {"ground": ground}}})


func test_status_and_strike_are_mutually_exclusive() -> void:
	assert_eq(_errors({"strike": {"interval": 1.0, "first_delay": 0.3}}), PackedStringArray())
	var both := _errors({"status": "poison", "interval": 1.0, "strike": {}})
	assert_eq(both.size(), 1)
	assert_true(both[0].contains("mutually exclusive"), both[0])
	assert_true(both[0].contains("zone"), "names the skill")
	assert_eq(_errors({"status": "poison", "chance_field": "prop", "interval": 1.0}), PackedStringArray(), "Poison Mist's shape is fine")
	var chance := _errors({"chance_field": "prop", "strike": {}})
	assert_eq(chance.size(), 1, "a strike has no chance roll")
	var no_status := _errors({"tile": "x/y", "strike": {}})
	assert_eq(no_status, PackedStringArray(), "a tile art key is allowed beside a strike")


func test_strike_numbers_must_be_usable() -> void:
	assert_eq(_errors({"strike": {"interval": 0.0}}).size(), 1, "an interval of 0 would loop forever")
	assert_eq(_errors({"strike": {"interval": -1.0}}).size(), 1)
	assert_eq(_errors({"strike": {"first_delay": -0.1}}).size(), 1)
	assert_eq(_errors({"strike": {"interval": "fast"}}).size(), 1)
	assert_eq(_errors({"strike": 3}).size(), 1, "strike must be an object")
	assert_eq(_errors({"strike": {"interval": 0.5, "first_delay": 0.0}}), PackedStringArray())


func test_a_skill_without_ground_is_not_checked() -> void:
	assert_eq(GroundStrike.errors({"skills": {"plain": {"damage": "physical"}}}), PackedStringArray())
	assert_eq(GroundStrike.errors({}), PackedStringArray())


func _kb(block: Dictionary) -> PackedStringArray:
	return DataRepo.knockback_errors({"skills": {"push": {"knockback": block}}})


func test_distance_by_rank_needs_exactly_eight_non_negative_numbers() -> void:
	assert_eq(_kb({"distance_by_rank": [100, 100, 200, 200, 200, 300, 300, 300]}), PackedStringArray())
	assert_eq(_kb({"distance": 180}), PackedStringArray(), "the scalar form is unchanged")
	assert_eq(_kb({"distance_by_rank": [100, 200]}).size(), 1, "eight values, one per rank")
	assert_eq(_kb({"distance_by_rank": [100, 100, 200, 200, 200, 300, 300, -1]}).size(), 1)
	assert_eq(_kb({"distance_by_rank": [100, 100, 200, 200, 200, 300, 300, "far"]}).size(), 1)
	assert_eq(_kb({"distance_by_rank": 100}).size(), 1, "an array, not a number")
	var both := _kb({"distance": 100, "distance_by_rank": [1, 2, 3, 4, 5, 6, 7, 8]})
	assert_eq(both.size(), 1, "distance_by_rank replaces distance: naming both is an error")
	assert_true(both[0].contains("distance_by_rank"), both[0])


func test_the_shipped_data_has_no_ground_or_knockback_errors() -> void:
	var data_errors := PackedStringArray()
	DataRepo.load_all(DataRepo.DATA_ROOT, data_errors)
	for e: String in data_errors:
		assert_false(e.contains("ground") or e.contains("distance_by_rank"), e)


func test_the_rank_lookup_clamps_and_falls_back_to_the_scalar() -> void:
	var by_rank := {"distance_by_rank": [100, 100, 200, 200, 200, 300, 300, 300]}
	assert_eq(Loadout.knockback_distance_at(by_rank, 1), 100.0)
	assert_eq(Loadout.knockback_distance_at(by_rank, 3), 200.0)
	assert_eq(Loadout.knockback_distance_at(by_rank, 8), 300.0)
	assert_eq(Loadout.knockback_distance_at(by_rank, 0), 100.0, "an unowned rank reads rank 1")
	assert_eq(Loadout.knockback_distance_at(by_rank, 20), 300.0, "past the table: the last value")
	assert_eq(Loadout.knockback_distance_at({"distance": 180}, 5), 180.0)
	assert_eq(Loadout.knockback_distance_at({}, 5), 0.0)
