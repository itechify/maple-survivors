extends TestCase
## King Clang Stun through seeded synthetic RunWorld ticks, independent of the asset cache.
const MF := preload("res://tests/fixtures/mano_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

func _world(prop := 100.0, interval := 15.0, seed_value := 22, basic := false) -> RunWorld:
	var setup := MF.setup([126], seed_value)
	setup.mob_imgs[2220000].info.skill = {"0": {"skill": 123.0, "level": 8.0, "action": 1.0}}
	# tier A values: original v83 MobSkill.img/123/level/8; prop can be synthetic for boundary tests.
	setup.mob_skill_img = {"123": {"level": {"8": {"interval": interval, "time": 2.0, "prop": prop,
		"lt": {"$v": [-200.0, -120.0]}, "rb": {"$v": [200.0, 20.0]}, "affected": {"repeat": 1.0}}}}}
	if basic:
		setup = RF.with_basic_attack(setup)
	var w := RunWorld.new(setup)
	w.god = true
	RF.place_player(w, 450)
	w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot, Vector2(600, 200), w.fhm.find_below(600, 190))
	w.drain_events()
	return w

func _ticks(w: RunWorld, n: int, input: MoveInput = null) -> void:
	for tick in n:
		w.step(DT, input if input != null else MoveInput.new())

func test_canonical_interval_and_two_second_expiry() -> void:
	var w := _world()
	_ticks(w, 899)
	assert_true(w.player_state.get("stun", {}).is_empty(), "no stun before 15 s")
	_ticks(w, 1)
	assert_false(w.player_state.get("stun", {}).is_empty(), "stun at 15 s")
	assert_false(w.can_cast(), "no casting during stun")
	w.swarm.despawn(int(w.bosses.records[0].slot))
	_ticks(w, 119)
	assert_false(w.can_cast(), "still stunned one tick before expiry")
	_ticks(w, 1)
	assert_true(w.can_cast(), "casting resumes exactly two seconds after cast")
	assert_true(w.player_state.get("stun", {}).is_empty())

func test_stun_cancels_a_basic_swing_already_in_windup() -> void:
	var w := _world(100.0, 0.4, 22, true)
	w.basic.clear_pending()
	w.basic.cooldown = 0.0
	RF.place_player(w, 570)
	_ticks(w, 20)
	var starts := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "basic_attack")
	assert_false(starts.is_empty(), "control: swing starts before the stun")
	_ticks(w, 50)
	assert_false(w.player_state.get("stun", {}).is_empty())
	var impacts := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "basic_attack" and e.phase == "impact")
	assert_true(impacts.is_empty(), "stun cancels the pending impact")

func test_area_hidden_and_zero_chance_never_stun() -> void:
	for offset in [Vector2(-201, 0), Vector2(201, 0), Vector2(0, -121), Vector2(0, 21)]:
		var w := _world()
		_ticks(w, 899)
		w.player.place(Vector2(600, 200) + offset, w.fhm)
		_ticks(w, 1)
		assert_true(w.player_state.stun.is_empty(), "outside canonical box: %s" % offset)
	var zero := _world(0.0)
	_ticks(zero, 900)
	assert_true(zero.player_state.stun.is_empty(), "zero chance fails")
	var hidden := _world()
	hidden.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 40.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
	_ticks(hidden, 1800)
	assert_true(hidden.player_state.stun.is_empty(), "Hidden skips Stun")
	assert_true(hidden.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "boss_skill").is_empty())

func test_stunned_input_cannot_move_jump_or_use_portals_but_gravity_runs() -> void:
	var w := _world()
	_ticks(w, 900)
	var pos := w.player.pos
	var input := MoveInput.make(false, true, true, false, true, true)
	input.press_skill("teleport")
	input.press_skill("dash")
	_ticks(w, 30, input)
	assert_eq(w.player.pos, pos, "no walk or jump")
	w.player.place(Vector2(450, 150), w.fhm)
	_ticks(w, 5, input)
	assert_true(w.player.pos.y > 150, "gravity still integrates")
	assert_near(w.player.pos.x, 450.0, 0.001, "no air steering")
	assert_true(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type in ["player_jump", "skill_cast"]).is_empty())

func test_damage_knockback_and_potions_remain_usable() -> void:
	var w := _world()
	_ticks(w, 900)
	w.god = false
	var before := int(w.player_state.hp)
	var hit := w.take_hit(10.0, false, "", w.player.pos - Vector2(10, 0), {"accuracy": 10000.0})
	assert_true(hit > 0, "stun does not grant damage immunity")
	var pos := w.player.pos
	_ticks(w, 1, MoveInput.make(true))
	assert_true(w.player.pos.x > pos.x, "knockback overrides held left")
	assert_true(int(w.player_state.hp) < before)
	assert_true(w.drink_potion("hp"), "tier C fallback: HP potion usable")
	assert_false(w.can_cast(), "drinking does not cure stun")

func test_sixty_percent_rolls_repeat_for_same_seed_and_do_not_shift_combat_rng() -> void:
	var results: Array = []
	for run in 2:
		var w := _world(60.0)
		var rng_state := w.rng.state
		var successes: Array = []
		for cast in 20:
			_ticks(w, 900)
			successes.append(not w.player_state.stun.is_empty())
		assert_eq(w.rng.state, rng_state, "status rolls use their own stream")
		assert_true(true in successes and false in successes, "canonical prop admits successes and failures")
		results.append(successes)
	assert_eq(results[0], results[1], "same seed, same status outcomes")
