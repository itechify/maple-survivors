extends TestCase
## MP costs, waiting casts, readiness ordering, regeneration pulses and level-up pools through seeded RunWorld ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _mage(skill: String = "") -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var world := RunWorld.new(RF.setup("quiet", 9, data))
	RF.change_job_bare(world, 200)
	RF.place_player(world, 1200)
	if skill != "":
		world.learn_skill(skill)
	RF.put_mob(world, 1110100, 1350, 190, 100)
	world.mob_kinds[int(world.kind_of_id[1110100])].move_speed = 0
	world.god = true
	world.drain_events()
	return world


func test_three_snails_pays_each_canonical_levels_mp_cost() -> void:
	for example: Array in [[1, 3], [2, 5], [3, 7]]:
		var data := RF.quiet_data()
		data.balance.player.mp = 20
		var world := RunWorld.new(RF.setup("quiet", 9, data))
		RF.place_player(world, 1200)
		RF.put_mob(world, 1110100, 1350, 190, 100)
		world.loadout.set_rank("three_snails", int(example[0]))
		world.drain_events()
		world.step(DT, MoveInput.new())
		assert_eq(_casts(world), ["three_snails"], "a Beginner casts at skill level %d" % example[0])
		assert_eq(world.player_state.mp, 20 - int(example[1]), "canonical cost at skill level %d" % example[0])


func test_beginner_with_two_mp_waits_for_three_snails_and_signals_shortage() -> void:
	var world := RF.quiet_world(1200, 9)
	RF.put_mob(world, 1110100, 1350, 190, 100)
	world.spend_mp(3)
	world.drain_events()
	var casts := 0
	var shortages := 0
	for tick in 10:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "cast":
				casts += 1
			elif event.type == "mp_short":
				shortages += 1
				assert_eq(event.skill, "three_snails")
				assert_eq(event.skill_id, 1000)
				assert_eq(event.required_mp, 3)
				assert_eq(event.mp, 2)
	assert_eq(casts, 0, "2 MP cannot pay Three Snails' level-1 cost")
	assert_eq(shortages, 1, "one normal mp_short event for the waiting episode")
	assert_eq(world.player_state.mp, 2, "waiting does not spend MP")
	assert_true(bool(world.player_state.mp_short), "the normal persistent shortage cue stays on")
	world.heal_fraction("mp", 1.0)
	world.step(DT, MoveInput.new())
	assert_eq(_casts(world), ["three_snails"], "the skill remains ready and casts as soon as affordable")
	assert_eq(world.player_state.mp, 2, "the resumed cast pays 3 MP")
	assert_false(bool(world.player_state.mp_short), "the cue clears after casting")


func test_job_skills_pay_canonical_mp() -> void:
	for skill: String in ["energy_bolt", "magic_claw"]:
		var world := _mage(skill)
		var before: int = world.player_state.mp
		world.step(DT, MoveInput.new())
		var costs := {"energy_bolt": 6, "magic_claw": 10}
		assert_eq(world.player_state.mp, before - costs[skill], "%s pays its current canonical MP cost" % skill)
		var casts := 0
		for event: Dictionary in world.drain_events():
			if event.type == "cast":
				casts += 1
		assert_eq(casts, 1, "the cost is charged for a real cast")
	for example: Array in [["energy_bolt", 6, 14], ["magic_claw", 6, 20]]:
		var world := _mage(example[0])
		world.loadout.set_rank(example[0], example[1])
		var before: int = world.player_state.mp
		world.step(DT, MoveInput.new())
		assert_eq(world.player_state.mp, before - int(example[2]), "cost follows the current canonical level")


func test_short_mp_waits_signals_once_and_casts_when_mp_is_restored() -> void:
	var world := _mage("energy_bolt")
	world.spend_mp(int(world.player_state.mp) - 5)
	var shortages := 0
	var casts := 0
	for tick in 10:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "mp_short":
				shortages += 1
				assert_eq(event.skill, "energy_bolt")
				assert_eq(event.skill_id, 2001004)
				assert_eq(event.required_mp, 6)
				assert_eq(event.mp, 5)
			elif event.type == "cast":
				casts += 1
	assert_eq(casts, 0, "an unaffordable ready skill waits")
	assert_eq(shortages, 1, "one signal per waiting episode, not every tick")
	assert_true(bool(world.player_state.get("mp_short", false)), "the persistent cue stays on while waiting")
	world.heal_fraction("mp", 1.0)
	world.step(DT, MoveInput.new())
	for event: Dictionary in world.drain_events():
		if event.type == "cast":
			casts += 1
	assert_eq(casts, 1, "the still-ready skill fires on the first affordable tick")
	assert_false(bool(world.player_state.get("mp_short", true)), "the waiting cue clears after casting")


func _casts(world: RunWorld) -> Array:
	var skills := []
	for event: Dictionary in world.drain_events():
		if event.type == "cast":
			skills.append(event.skill)
	return skills


func test_first_ready_skill_fires_first_after_climbing_even_when_learned_later() -> void:
	var world := _mage()
	world.learn_skill("magic_claw")
	world.learn_skill("energy_bolt")
	world.step(DT, MoveInput.new())
	assert_eq(_casts(world), ["magic_claw"], "equal-ready skills use learned order, one cast per tick")
	world.step(DT, MoveInput.new())
	assert_eq(_casts(world), ["energy_bolt"])
	var up := MoveInput.new()
	up.up = true
	world.step(DT, up)
	assert_true(world.player.ladder >= 0)
	for tick in 90:
		world.step(DT, MoveInput.new())
	assert_eq(_casts(world), [], "neither skill starts a cast while hanging")
	var jump := MoveInput.new()
	jump.left = true
	jump.jump_pressed = true
	world.step(DT, jump)
	assert_eq(_casts(world), ["energy_bolt"], "0.9-second Bolt became ready before 1.25-second Claw")
	world.step(DT, MoveInput.new())
	assert_eq(_casts(world), ["magic_claw"], "the next waiting skill gets the following tick")


func test_regeneration_arrives_as_ten_second_hp_and_mp_pulses() -> void:
	var world := _mage()
	world.god = false
	world.spend_mp(30)
	world.take_hit(20, false, "", world.player.pos + Vector2(100, 0))
	var hp: int = world.player_state.hp
	var mp: int = world.player_state.mp
	world.god = true
	for tick in 599:
		world.step(DT, MoveInput.new())
	assert_eq(world.player_state.hp, hp, "HP does not trickle between pulses")
	assert_eq(world.player_state.mp, mp, "MP does not trickle between pulses")
	world.step(DT, MoveInput.new())
	assert_eq(world.player_state.hp, mini(hp + 10, int(world.player_state.max_hp)), "10 HP at 10 seconds")
	assert_eq(world.player_state.mp, mp + 3, "3 MP at 10 seconds")


func test_level_up_increases_maxima_without_restoring_current_pools() -> void:
	var world := _mage()
	world.spend_mp(30)
	var hp: int = world.player_state.hp
	var mp: int = world.player_state.mp
	var max_hp: int = world.player_state.max_hp
	var max_mp: int = world.player_state.max_mp
	world.pickups.spawn(world.player.pos, world.progression.exp_to_next(), 4000019)
	for tick in 120:
		world.step(DT, MoveInput.new())
		if world.state != RunWorld.PLAYING:
			break
	assert_eq(world.player_state.level, 2, "the pickup causes a real level-up")
	assert_true(int(world.player_state.max_hp) > max_hp and int(world.player_state.max_mp) > max_mp,
		"level growth raises both maxima")
	assert_eq(world.player_state.hp, hp, "no HP is added by either refill or maximum growth")
	assert_eq(world.player_state.mp, mp, "no MP is added by either refill or maximum growth")


func test_improved_mp_recovery_uses_its_canonical_skill_level_per_pulse() -> void:
	var world := _mage()
	world.progression.level = 20
	world.upgrades.apply("improved_mp_recovery", world)
	for rank in 4:
		world.upgrades.apply("improved_mp_recovery_rank", world)
	assert_eq(world.loadout.level("improved_mp_recovery"), 16, "five picks reach canonical skill level 16")
	world.spend_mp(int(world.player_state.mp) - 5)
	for tick in 600:
		world.step(DT, MoveInput.new())
	assert_eq(world.player_state.mp, 40, "5 + base 3 + level-20 skill-level-16 recovery bonus 32")


func test_unaffordable_skill_allows_a_later_affordable_skill_to_fire() -> void:
	var world := _mage("energy_bolt")
	world.learn_skill("three_snails")
	world.spend_mp(int(world.player_state.mp) - 3)
	world.step(DT, MoveInput.new())
	assert_eq(_casts(world), ["three_snails"], "the short-MP Bolt waits while the affordable fallback fires")
	assert_eq(world.player_state.mp, 0, "the fallback spends its canonical 3 MP")
	assert_true(bool(world.player_state.mp_short), "the unaffordable skill still needs MP")


func test_recovery_healing_and_base_regeneration_have_separate_pulse_clocks() -> void:
	var world := _mage()
	world.god = false
	world.take_hit(30, false, "", world.player.pos + Vector2(100, 0))
	world.god = true
	var hp: int = world.player_state.hp
	world.upgrades.apply("recovery", world)
	for tick in 600:
		world.step(DT, MoveInput.new())
	assert_eq(world.hp_regen, 0.0, "Recovery no longer modifies permanent regeneration")
	assert_eq(world.player_state.hp, mini(hp + 14, int(world.player_state.max_hp)),
		"at 10 s: base regen 10 plus Recovery's first 4 HP pulse; its second is at cast-time + 10 s")
