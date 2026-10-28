extends TestCase
## ADR 0006 (spec #282 ticket #285): there is no MP and no level gap. Skills are gated by their cooldown only, and a
## monster's level relative to the character changes neither the damage it takes nor the damage it deals.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


## A quiet world with only Energy Bolt learned (no job MP grants) and one stationary, unkillable target.
func _bolt_world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	var world := RunWorld.new(RF.setup("quiet", 9, data))
	RF.place_player(world, 1200)
	world.learn_skill("energy_bolt")
	var kind: MobKind = world.mob_kinds[int(world.kind_of_id[1110100])]
	kind.move_speed = 0
	RF.put_mob(world, 1110100, 1350, 190, 100000.0)
	world.god = true
	world.drain_events()
	return world


func test_a_skill_casts_on_its_cooldown_with_no_mp() -> void:
	var world := _bolt_world()
	var times: Array[float] = []
	var types := {}
	for tick in 60 * 9:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			types[event.type] = true
			if event.type == "cast" and String(event.skill) == "energy_bolt":
				times.append(world.time)
	# Energy Bolt's survivor cooldown is 0.9 s: about ten casts in nine seconds, each one cooldown after the last.
	assert_true(times.size() >= 10, "Energy Bolt fires on every cooldown with a 0-MP pool: %d casts" % times.size())
	for i in range(1, times.size()):
		assert_near(times[i] - times[i - 1], 0.9, DT + 1e-6, "cast %d follows the cooldown" % i)
	assert_false(types.has("mp_short"), "no MP shortage exists")
	for key: String in ["mp", "max_mp", "mp_short"]:
		assert_false(world.player_state.has(key), "player_state has no %s" % key)


func test_skill_stats_carry_no_mp_cost() -> void:
	var world := _bolt_world()
	assert_false(world.loadout.stats("energy_bolt").has("mp_cost"), "resolved stats have no MP cost")


## Two identical worlds whose target is the character's level or 50 levels above it.
func _gap_worlds() -> Array[RunWorld]:
	var out: Array[RunWorld] = []
	for gap: int in [0, 50]:
		var data := RF.quiet_data()
		data.balance.player.hp = 100000
		var world := RunWorld.new(RF.setup("quiet", 31, data))
		RF.place_player(world, 1200)
		var kind: MobKind = world.mob_kinds[int(world.kind_of_id[1110100])]
		kind.move_speed = 0
		kind.level = world.progression.level + gap
		kind.pdd = 0
		kind.mdd = 0
		RF.put_mob(world, 1110100, 1300, 190, 100000.0)
		world.drain_events()
		out.append(world)
	return out


func test_physical_damage_to_a_mob_fifty_levels_above_equals_same_level() -> void:
	var worlds := _gap_worlds()
	var dealt: Array = []
	for world: RunWorld in worlds:
		var st := {"damage_min": 100.0, "damage_max": 200.0, "damage_type": "physical", "crit": 0.0,
			"crit_mult": 1.0, "skill": "probe"}
		var hits: Array = []
		for i in 20:
			world.hit_mob(0, st, -1)
			for event: Dictionary in world.drain_events():
				if event.type == "mob_hit":
					hits.append(int(event.damage))
		dealt.append(hits)
	assert_eq((dealt[0] as Array).size(), 20, "every probe hit lands")
	assert_eq(dealt[1], dealt[0], "a 50-level gap changes no physical hit")


func test_magic_damage_to_a_mob_fifty_levels_above_equals_same_level() -> void:
	var worlds := _gap_worlds()
	var dealt: Array = []
	for world: RunWorld in worlds:
		var hits: Array = []
		for i in 20:
			world.hit_mob(0, {"damage_min": 100.0, "damage_max": 200.0, "magic": true, "crit": 0.0,
				"crit_mult": 1.0, "skill": "probe"}, -1)
			for event: Dictionary in world.drain_events():
				if event.type == "mob_hit":
					hits.append(int(event.damage))
		dealt.append(hits)
	assert_eq((dealt[0] as Array).size(), 20, "every probe hit lands")
	assert_eq(dealt[1], dealt[0], "a 50-level gap changes no magic hit")


func test_damage_from_a_mob_fifty_levels_above_equals_same_level() -> void:
	var worlds := _gap_worlds()
	var taken: Array = []
	for world: RunWorld in worlds:
		var kind: MobKind = world.mob_kinds[int(world.kind_of_id[1110100])]
		var hits: Array = []
		for i in 20:
			world.upkeep.invincible_t = 0.0
			hits.append(world.take_hit(60.0, i % 2 == 1, "", Vector2(1300, 190),
				{"mob": 0, "mob_id": 1110100, "accuracy": float(kind.acc), "source_kind": "touch"}))
		taken.append(hits)
	assert_true((taken[0] as Array).max() > 0, "the probe hits land")
	assert_eq(taken[1], taken[0], "a 50-level gap changes neither hit chance nor damage taken")
