extends TestCase
## Basic weapon attacks through fixed seeded RunWorld ticks with synthetic canonical weapon/body/afterimage data.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")
const ACTIONS := ["swingO1", "swingO2", "swingO3", "stabO1", "stabO2"]




func _target(world: RunWorld, x: float = 450.0) -> int:
	world.mob_kinds[int(world.kind_of_id[100100])].move_speed = 0
	return RF.put_mob(world, 100100, x, 190, 100)


func test_basic_swing_waits_for_the_canonical_afterimage_frame_to_hit() -> void:
	var world := BF.world()
	var mob := _target(world)
	world.step(DT, MoveInput.new())
	var started := {}
	for event: Dictionary in world.drain_events():
		if event.type == "basic_attack" and event.phase == "start":
			started = event
		assert_false(event.type == "mob_hit", "starting the swing deals no immediate damage")
	assert_false(started.is_empty(), "standing still within reach starts a basic swing")
	if started.is_empty():
		return
	assert_eq(started.weapon_id, 1302000)
	assert_near(float(started.hit_after), 0.45, 1e-9, "300 + 150 ms before afterimage frame 2")
	assert_near(float(started.interval), 0.72, 1e-9, "Sword canonical speed 4 gives 720 ms")
	var hp: int = world.swarm.hp[mob]
	for tick in 26:
		world.step(DT, MoveInput.new())
	assert_eq(world.swarm.hp[mob], hp, "no damage before the afterimage frame")
	world.step(DT, MoveInput.new())
	var hits := 0
	for event: Dictionary in world.drain_events():
		if event.type == "mob_hit":
			hits += 1
			assert_eq(event.skill, "basic_attack")
			assert_eq(event.mob, mob)
	assert_eq(hits, 1, "one hit on the afterimage tick")


func test_sword_and_wand_cadence_does_not_accumulate_fixed_tick_rounding() -> void:
	for job in [0, 200]:
		var world := BF.world()
		if job == 200:
			RF.change_job_bare(world, 200)
		var mob := _target(world)
		world.swarm.hp[mob] = 100000
		world.swarm.max_hp[mob] = 100000
		var times := []
		for tick in 1200:
			world.step(DT, MoveInput.new())
			for event: Dictionary in world.drain_events():
				if event.type == "basic_attack" and event.phase == "start":
					times.append(world.time)
			if times.size() >= 10:
				break
		assert_eq(times.size(), 10)
		if times.size() == 10:
			assert_near(float(times[9] - times[0]), 6.48 if job == 0 else 7.29, DT + 1e-6,
				"ten attacks retain the canonical 720/810 ms cadence")


func _starts(world: RunWorld) -> Array:
	var starts := []
	for event: Dictionary in world.drain_events():
		if event.type == "basic_attack" and event.phase == "start":
			starts.append(event)
	return starts


func test_walking_climbing_skills_and_out_of_reach_mobs_block_new_swings() -> void:
	var walking := BF.world()
	_target(walking)
	var right := MoveInput.new()
	right.right = true
	walking.step(DT, right)
	assert_eq(_starts(walking).size(), 0, "walking never starts a basic swing")
	var rope := BF.world()
	RF.place_player(rope, -100)
	_target(rope, -50)
	var up := MoveInput.new()
	up.up = true
	rope.step(DT, up)
	assert_true(rope.player.ladder >= 0)
	assert_eq(_starts(rope).size(), 0, "climbing never starts a basic swing")
	var casting := BF.world()
	_target(casting)
	casting.learn_skill("three_snails")
	casting.step(DT, MoveInput.new())
	assert_true(casting.runner.fired_this_tick)
	assert_eq(_starts(casting).size(), 0, "a skill takes priority over the basic attack")
	var far := BF.world()
	_target(far, 700)
	far.step(DT, MoveInput.new())
	assert_eq(_starts(far).size(), 0, "no monster in the afterimage box means no swing")
	var behind := BF.world()
	_target(behind, 350)
	behind.step(DT, MoveInput.new())
	assert_eq(_starts(behind).size(), 0, "a monster behind the facing box is out of reach")


func test_airborne_swing_has_an_attack_stance_without_changing_jump_motion() -> void:
	var world := BF.world()
	var control := BF.world()
	control.balance.player.weapon_by_job = {"0": 0}
	_target(world)
	var jump := MoveInput.new()
	jump.jump_pressed = true
	jump.jump_held = true
	world.step(DT, jump)
	control.step(DT, jump)
	assert_eq(_starts(world).size(), 1, "a target in reach allows an airborne swing")
	assert_true(String(world.player_state.action) in ACTIONS, "the airborne character shows its swing/stab stance")
	assert_eq(world.player.pos, control.player.pos, "attacking does not change the jump")
	assert_eq(world.player.vel, control.player.vel)


func test_swing_hits_the_single_nearest_target_and_mirrors_its_box() -> void:
	for facing in [-1, 1]:
		var world := BF.world()
		world.player.facing = facing
		var nearest := _target(world, 400 + facing * 50)
		var farther := _target(world, 400 + facing * 70)
		for tick in 28:
			world.step(DT, MoveInput.new())
		var hits := []
		for event: Dictionary in world.drain_events():
			if event.type == "mob_hit":
				hits.append(event.mob)
		assert_eq(hits, [nearest], "the facing afterimage hits only its nearest monster")
		assert_eq(world.swarm.hp[farther], world.swarm.max_hp[farther], "the farther monster is untouched")


func test_five_stances_are_uniform_and_level_three_stats_one_shot_snails() -> void:
	var world := BF.world(83)
	world.pickups.spawn(world.player.pos - Vector2(0, 20), world.progression.curve.total_to(3), 4000019)
	world.step(DT, MoveInput.new())
	assert_eq(world.player_state.level, 3)
	assert_eq(world.player_state.str, 22)
	assert_eq(world.player_state.dex, 5)
	RF.auto_choose(world)
	world.drain_events()
	var mob := _target(world)
	world.swarm.hp[mob] = 100000
	world.swarm.max_hp[mob] = 100000
	var counts := {}
	var hits := 0
	var one_shots := 0
	for tick in 60 * 725:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "basic_attack" and event.phase == "start":
				counts[event.action] = int(counts.get(event.action, 0)) + 1
			elif event.type == "mob_hit":
				hits += 1
				assert_true(event.damage >= 2 and event.damage <= 16, "STR22 DEX5 Sword rounds to 2..16")
				if int(event.damage) >= 8:
					one_shots += 1
		if hits >= 1000:
			break
	assert_eq(hits, 1000)
	for action: String in ACTIONS:
		assert_true(int(counts.get(action, 0)) >= 160 and int(counts.get(action, 0)) <= 240, "%s approximately one fifth: %s" % [action, counts])
	assert_true(one_shots >= 500, "level3 STR22 stats one-shot 8HP Snail in at least half: %d/1000" % one_shots)


func test_known_physical_bounds_include_weapon_stance_defense_and_level_difference() -> void:
	var sword := CombatMath.basic_damage_range(12, 4, 17, 1302000, "swingO1", 1, 1, 0)
	assert_near(sword.x, 1.4144, 0.00001)
	assert_near(sword.y, 8.84, 0.00001)
	var swing := CombatMath.basic_damage_range(12, 4, 15, 1372005, "swingO1", 1, 1, 0)
	assert_near(swing.x, 1.3128, 0.00001)
	assert_near(swing.y, 8.52, 0.00001)
	var stab := CombatMath.basic_damage_range(12, 4, 15, 1372005, "stabO1", 1, 1, 0)
	assert_near(stab.x, 1.1184, 0.00001)
	assert_near(stab.y, 6.36, 0.00001)
	var defended := CombatMath.basic_damage_range(12, 4, 17, 1302000, "swingO1", 1, 6, 5)
	assert_near(defended.x, 1.0, 0.00001)
	assert_near(defended.y, 5.898, 0.00001)


func test_weapon_info_reads_type_afterimage_interval_and_sound_from_the_canonical_node() -> void:
	assert_eq(WeaponInfo.type_of(1302000), 130)
	assert_eq(WeaponInfo.swing_k(1302000, "stabO1"), 4.0, "one-handed swords use k 4 for every stance")
	assert_eq(WeaponInfo.swing_k(1372005, "swingO2"), 4.4)
	assert_eq(WeaponInfo.swing_k(1372005, "stabO2"), 3.2)
	var sword := {"afterImage": "swordOL", "attackSpeed": 4, "sfx": "swordL"}
	var wand := {"afterImage": "mace", "attackSpeed": 6, "sfx": "mace"}
	assert_near(WeaponInfo.attack_interval(sword), 0.72, 1e-9, "Sword 720 ms")
	assert_near(WeaponInfo.attack_interval(wand), 0.81, 1e-9, "Wand 810 ms")
	assert_eq(WeaponInfo.afterimage_frame_path(WeaponInfo.afterimage_name(sword), "swingO1", 2),
		"Character.wz/Afterimage/swordOL.img/0/swingO1/2")
	assert_eq(WeaponInfo.hit_spark_path("swordOL", "stabO1"), "Character.wz/Afterimage/hit.img/sword2")
	assert_eq(WeaponInfo.hit_spark_path("mace", "swingO3"), "Character.wz/Afterimage/hit.img/mace1")
	assert_eq(WeaponInfo.sound_path(wand), "Sound.wz/Weapon.img/mace/Attack")


func test_unequal_stance_reach_does_not_bias_started_swings_or_expand_impact_boxes() -> void:
	var world := BF.world(83)
	# Synthetic unequal boxes model the v83 Sword's longer swingO3 outer reach.
	world.setup.afterimage_imgs.swordOL["0"].swingO3.lt["$v"][0] = -102.0
	var mob := _target(world, 496)
	world.mob_kinds[world.swarm.kind[mob]].hitbox = Rect2(-1, -20, 2, 20)
	world.swarm.hp[mob] = 100000
	world.swarm.max_hp[mob] = 100000
	var counts := {}
	var impacts := 0
	var hits := 0
	var last_action := ""
	for tick in 60 * 190:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "basic_attack" and event.phase == "start":
				counts[event.action] = int(counts.get(event.action, 0)) + 1
			elif event.type == "basic_attack" and event.phase == "impact":
				impacts += 1
				last_action = event.action
			elif event.type == "mob_hit":
				hits += 1
				assert_eq(last_action, "swingO3", "only the chosen stance's own box deals damage")
		if impacts >= 250:
			break
	assert_eq(impacts, 250, "a nearby target permits the canonical swing cadence")
	for action: String in ACTIONS:
		assert_between(int(counts.get(action, 0)), 30, 70, "%s stays about one fifth at outer reach: %s" % [action, counts])
	assert_between(hits, 30, 70, "shorter stances visibly swing but miss the outer target")
