extends TestCase
## Readiness ordering, regeneration pulses and level-up HP through seeded RunWorld ticks. There is no MP (ADR 0006):
## skills are gated by their cooldown only.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _mage(skill: String = "") -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	var world := RunWorld.new(RF.setup("quiet", 9, data))
	RF.place_player(world, 1200)
	if skill != "":
		world.learn_skill(skill)
	RF.put_mob(world, 1110100, 1350, 190, 100)
	world.mob_kinds[int(world.kind_of_id[1110100])].move_speed = 0
	world.god = true
	world.drain_events()
	return world


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


func test_regeneration_arrives_as_ten_second_hp_pulses() -> void:
	var world := _mage()
	world.god = false
	world.take_hit(20, false, "", world.player.pos + Vector2(100, 0))
	var hp: int = world.player_state.hp
	world.god = true
	for tick in 599:
		world.step(DT, MoveInput.new())
	assert_eq(world.player_state.hp, hp, "HP does not trickle between pulses")
	world.step(DT, MoveInput.new())
	assert_eq(world.player_state.hp, mini(hp + 10, int(world.player_state.max_hp)), "10 HP at 10 seconds")


## Collects one EXP pickup worth the next `levels` level-ups (one EXP gain), stopping at the level-up window.
func _collect_levels(world: RunWorld, levels: int) -> void:
	var amount := 0
	for k in levels:
		amount += world.progression.curve.exp_to_next(world.progression.level + k)
	world.pickups.spawn(world.player.pos, amount, 4000019)
	for tick in 120:
		world.step(DT, MoveInput.new())
		if world.state != RunWorld.PLAYING:
			break


func test_level_up_raises_max_hp_and_leaves_hp() -> void:
	var world := _mage()
	var hp: int = world.player_state.hp
	var max_hp: int = world.player_state.max_hp
	_collect_levels(world, 1)
	assert_eq(world.player_state.level, 2, "the pickup causes a real level-up")
	assert_true(int(world.player_state.max_hp) > max_hp, "level growth raises the maximum")
	assert_eq(world.player_state.hp, hp, "no HP is added by either refill or maximum growth")


func test_recovery_healing_and_base_regeneration_have_separate_pulse_clocks() -> void:
	var world := _mage()
	world.god = false
	world.take_hit(30, false, "", world.player.pos + Vector2(100, 0))
	world.god = true
	var hp: int = world.player_state.hp
	world.learn_skill("recovery") # #284: no Recovery card (the Beginner cards are gone)
	for tick in 600:
		world.step(DT, MoveInput.new())
	assert_eq(world.hp_regen, 0.0, "Recovery no longer modifies permanent regeneration")
	assert_eq(world.player_state.hp, mini(hp + 14, int(world.player_state.max_hp)),
		"at 10 s: base regen 10 plus Recovery's first 4 HP pulse; its second is at cast-time + 10 s")
