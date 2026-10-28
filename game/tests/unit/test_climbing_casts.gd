extends TestCase
## Casting through seeded RunWorld ticks: ropes/ladders block new casts while ready cooldowns keep counting.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _cast_events(world: RunWorld) -> Array:
	var casts := []
	for event: Dictionary in world.drain_events():
		if event.type == "cast":
			casts.append(event)
	return casts


func test_rope_and_ladder_block_casts_without_pausing_cooldowns() -> void:
	for is_ladder in [0, 1]:
		var data := RF.quiet_data()
		# One auto-cast skill set up directly (#284: a fresh 212 starts with Energy Bolt and Teleport).
		data.jobs_survivor.jobs["212"]["starting_skill"] = "three_snails"
		var world := RunWorld.new(RF.setup("quiet", 8, data))
		RF.place_player(world, 400)
		world.god = true
		var climb := -1
		for i in world.ladders.count():
			if world.ladders.is_ladder[i] == is_ladder:
				climb = i
		assert_true(climb >= 0)
		var x: float = world.ladders.x[climb]
		RF.place_player(world, x)
		RF.put_mob(world, 1110100, x + 200.0, 190.0, 100.0)
		world.mob_kinds[int(world.kind_of_id[1110100])].move_speed = 0.0
		world.step(DT, MoveInput.new())
		assert_eq(_cast_events(world).size(), 1, "a ground cast starts the normal cooldown")
		var up := MoveInput.new()
		up.up = true
		world.step(DT, up)
		assert_eq(world.player.ladder, climb, "Up grabs the rope/ladder")
		assert_false(world.can_cast(), "the shared action gate rejects climbing")
		var blocked := _cast_events(world).size()
		for tick in 90:
			world.step(DT, MoveInput.new())
			blocked += _cast_events(world).size()
		assert_eq(blocked, 0, "no new cast during 1.5 seconds of hanging")
		var jump := MoveInput.new()
		jump.left = true
		jump.jump_pressed = true
		jump.jump_held = true
		world.step(DT, jump)
		assert_eq(world.player.ladder, -1, "jumping away leaves the rope/ladder")
		assert_true(world.can_cast(), "airborne casting is allowed")
		var resumed := _cast_events(world)
		assert_eq(resumed.size(), 1, "the cooldown became ready while hanging and fires on the first eligible tick")
		if not resumed.is_empty():
			assert_eq(resumed[0].skill, "three_snails", "the ready skill resumes")


func test_seeded_run_parked_mid_rope_from_one_minute_has_no_new_skill_kills() -> void:
	var world := RunWorld.new(RF.setup("henesys", 8))
	# This tests the climbing cast gate, independently of balance changes killing the warmup/camper.
	world.god = true
	var memo := {}
	for tick in 60 * 60:
		RF.auto_choose(world)
		if world.state != RunWorld.PLAYING:
			break
		world.step(DT, RF.bot_input(world, memo))
		world.drain_events()
	assert_near(world.time, 60.0, DT, "bounded warmup reaches the climbing setup")
	if world.time < 60.0 - DT:
		return
	var rope := -1
	for i in world.ladders.count():
		if world.ladders.is_ladder[i] == 0:
			rope = i
	assert_true(rope >= 0)
	var up := MoveInput.new()
	up.up = true
	# A level-up window or a hit in progress at 1:00 can delay the grab a few ticks; retry from the rope's middle.
	for attempt in 60:
		if world.player.ladder == rope:
			break
		RF.auto_choose(world)
		world.player.pos = Vector2(world.ladders.x[rope], (world.ladders.y1[rope] + world.ladders.y2[rope]) * 0.5)
		world.player.fh = -1
		world.player.vel = Vector2.ZERO
		world.step(DT, up)
	assert_eq(world.player.ladder, rope, "the run parks on the rope at 1:00")
	var hanging_casts := 0
	var hanging_kills := 0
	var previous_shot_kills := 0
	# Shots launched before grabbing the rope finish normally. Only new casting is blocked.
	var previous_shots_finished := world.projectiles.active_count() == 0
	var ticks := 0
	while world.time < 360.0 - DT * 0.5 and world.state != RunWorld.DEAD:
		for event: Dictionary in world.drain_events():
			if event.type == "cast":
				hanging_casts += 1
			elif event.type == "mob_died":
				if previous_shots_finished:
					hanging_kills += 1
				else:
					previous_shot_kills += 1
		if world.projectiles.active_count() == 0:
			previous_shots_finished = true
		RF.auto_choose(world)
		world.step(DT, MoveInput.new())
		ticks += 1
		if world.state != RunWorld.DEAD:
			assert_eq(world.player.ladder, rope, "the camper keeps hanging")
	print("rope camper seed 8: parked at 1:00, %.1f s hanging, %d casts, %d skill kills after existing shots finish, %d carry-over shot kills, %s" % [
		ticks * DT, hanging_casts, hanging_kills, previous_shot_kills, world.state_name()])
	assert_true(ticks > 60 * 60, "the parked run covers at least a minute")
	assert_eq(hanging_casts, 0, "no new skills while hanging")
	assert_true(previous_shots_finished, "the already-launched shots finish")
	assert_eq(hanging_kills, 0, "no skill kills after already-launched shots finish")
