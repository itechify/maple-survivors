extends TestCase
## Boss Stun (MobSkill 123, #456) through seeded synthetic RunWorld ticks, independent of the asset cache.
const MF := preload("res://tests/fixtures/mano_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const DT := 1.0 / 60.0


## A world with a boss whose only skill is a synthetic Stun level (King Clang's L8 shape: interval 15, time 2, box
## (-200,-120)-(200,20), tier A from v83 MobSkill.img/123/level/8; `prop`, `interval` and `time` can be varied).
func _world(prop := 100.0, interval := 15.0, seed_value := 22, time := 2.0, rules := {}) -> RunWorld:
	var setup := MF.setup([126], seed_value)
	setup.mob_imgs[2220000].info.skill = {"0": {"skill": 123.0, "level": 8.0, "action": 1.0}}
	setup.mob_skill_img = {"123": {"level": {"8": {"interval": interval, "time": time, "prop": prop,
		"lt": {"$v": [-200.0, -120.0]}, "rb": {"$v": [200.0, 20.0]}, "affected": {"repeat": 1.0}}}}}
	# A short skill stance, so back-to-back casts of the lockout tests are not paced by the boss's own animation.
	setup.mob_imgs[2220000].skill1 = {"0": {"delay": 10.0}}
	setup.data.balance.mob_skills.merge(rules, true)
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


func _stunned(w: RunWorld) -> bool:
	return not w.player_state.get("stun", {}).is_empty()


func _casts(events: Array) -> int:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "boss_skill" and int(e.skill_id) == 123).size()


## The canonical interval and `time` in ticks: stunned from the cast tick for exactly 120 ticks.
func test_canonical_interval_and_two_second_expiry() -> void:
	var w := _world()
	_ticks(w, 899)
	assert_false(_stunned(w), "no stun before 15 s")
	_ticks(w, 1)
	assert_true(_stunned(w), "stun at 15 s")
	assert_false(w.can_cast(), "no casting during stun")
	w.swarm.despawn(int(w.bosses.records[0].slot))
	_ticks(w, 119)
	assert_false(w.can_cast(), "still stunned one tick before expiry")
	assert_true(_stunned(w))
	_ticks(w, 1)
	assert_true(w.can_cast(), "casting resumes exactly two seconds after the cast")
	assert_false(_stunned(w))


## Outside the mirrored box, with a 0% roll or while Hidden, nothing stuns.
func test_area_hidden_and_zero_chance_never_stun() -> void:
	for offset in [Vector2(-201, 0), Vector2(201, 0), Vector2(0, -121), Vector2(0, 21)]:
		var w := _world()
		_ticks(w, 899)
		w.player.place(Vector2(600, 200) + offset, w.fhm)
		_ticks(w, 1)
		assert_false(_stunned(w), "outside the canonical box: %s" % offset)
	var inside := _world()
	_ticks(inside, 899)
	inside.player.place(Vector2(600, 200) + Vector2(-199, 0), inside.fhm)
	_ticks(inside, 1)
	assert_true(_stunned(inside), "control: inside the box")
	var zero := _world(0.0)
	_ticks(zero, 900)
	assert_false(_stunned(zero), "zero chance fails")
	var hidden := _world()
	hidden.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 40.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
	_ticks(hidden, 1800)
	assert_false(_stunned(hidden), "Hidden skips Stun")
	assert_eq(_casts(hidden.drain_events()), 0, "and the boss does not cast it")


## A stunned character reads an empty input: no walking, jumping, portals, dashes or air steering; gravity runs.
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
	_ticks(w, 120)
	assert_false(_stunned(w))
	var free := MoveInput.make(false, true)
	var before := w.player.pos.x
	_ticks(w, 10, free)
	assert_true(w.player.pos.x > before, "control: after the stun the same input walks")


## Damage and knockback still apply, and HP potions stay usable (tier C).
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
	var low := int(w.player_state.hp)
	var drink := MoveInput.new()
	drink.drink_hp = true
	_ticks(w, 1, drink)
	assert_true(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "potion_used"),
		"the potion key works while stunned")
	assert_true(int(w.player_state.hp) > low)
	assert_true(_stunned(w), "drinking does not cure the stun")
	assert_false(w.can_cast())


## A 60% roll succeeds and fails across casts, repeats for a seed, and leaves the other streams alone (stream 19).
func test_sixty_percent_rolls_repeat_for_same_seed_and_use_stream_19() -> void:
	var results: Array = []
	for run in 2:
		var w := _world(60.0)
		var combat := w.rng.state
		var ground := w.ground_rng.state
		var banish := w.banish_rng.state
		var status := w.mob_status_rng.state
		var successes: Array = []
		for cast in 20:
			_ticks(w, 900)
			successes.append(_stunned(w))
		assert_eq(w.rng.state, combat, "status rolls leave stream 1 alone")
		assert_eq(w.ground_rng.state, ground, "and stream 18 (ground_rng)")
		assert_eq(w.banish_rng.state, banish, "and stream 17")
		assert_ne(w.mob_status_rng.state, status, "the rolls are stream 19's")
		assert_true(true in successes and false in successes, "canonical prop admits successes and failures")
		results.append(successes)
	assert_eq(results[0], results[1], "same seed, same status outcomes")


## A failed roll still spends the interval: the boss casts every 15 s and never retries sooner.
func test_failed_roll_spends_the_interval() -> void:
	var w := _world(0.0)
	var casts := 0
	var times: Array = []
	for tick in 46 * 60:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_skill" and int(e.skill_id) == 123:
				casts += 1
				times.append(snappedf(w.time, 0.1))
	assert_eq(casts, 3, "casts at 15, 30 and 45 s with a 0% roll")
	assert_eq(times, [15.0, 30.0, 45.0])


## 330 ordinary mobs cannot raise the stun rate: the boss rolls once per interval.
func test_three_hundred_thirty_mobs_cannot_increase_the_boss_stun_rate() -> void:
	var w := _world()
	for mob in 330:
		RF.put_mob(w, 100100, 1000.0)
	var stunned_ticks := 0
	var casts := 0
	for tick in 62 * 60:
		w.step(DT, MoveInput.new())
		if _stunned(w):
			stunned_ticks += 1
		casts += _casts(w.drain_events())
	assert_eq(casts, 4, "15, 30, 45 and 60 seconds despite 330 ordinary mobs")
	assert_eq(stunned_ticks, 480, "four successes occupy eight seconds")


## The lockout floor: Papulatus's Stun L4 shape (interval 1, time 3, prop 100) stuns 3 s, then is refused for
## max(4, 3) = 4 s after it ends, and the cast still spends its interval.
func test_lockout_floor_stops_a_chain_stun() -> void:
	var w := _world(100.0, 1.0, 22, 3.0)
	var windows: Array = []
	var was := false
	for tick in 20 * 60:
		w.step(DT, MoveInput.new())
		var now := _stunned(w)
		if now != was:
			windows.append(snappedf(w.time, 0.05))
			was = now
	# stun at 1 s .. 4 s, immune 4 s .. 8 s, stun again 8 s .. 11 s, immune .. 15 s, stun 15 s .. 18 s
	assert_eq(windows, [1.0, 4.0, 8.0, 11.0, 15.0, 18.0])


## balance.mob_skills.status_lockout overrides the floor per status and by default; the status's own time wins when longer.
func test_status_lockout_is_configurable() -> void:
	var long := _world(100.0, 1.0, 22, 3.0, {"status_lockout": {"default": 4, "123": 10}})
	var first := -1.0
	var again := -1.0
	var was := false
	for tick in 30 * 60:
		long.step(DT, MoveInput.new())
		var now := _stunned(long)
		if now and not was:
			if first < 0.0:
				first = long.time
			elif again < 0.0:
				again = long.time
		was = now
	assert_near(first, 1.0, 0.05)
	assert_near(again - first, 3.0 + 10.0, 0.05, "3 s stun, then 10 s immunity")
	var longer := _world(100.0, 1.0, 22, 6.0)
	var starts: Array = []
	was = false
	for tick in 20 * 60:
		longer.step(DT, MoveInput.new())
		var now := _stunned(longer)
		if now and not was:
			starts.append(snappedf(longer.time, 0.05))
		was = now
	assert_eq(starts, [1.0, 13.0], "a 6 s stun is followed by 6 s of immunity, not 4")


## A locked-out cast draws no roll, so refused casts never shift stream 19; once the lockout ends the rolls resume.
func test_a_locked_out_cast_draws_no_roll() -> void:
	var w := _world(60.0, 1.0, 22, 3.0)
	w.mob_skills.statuses.apply(MobSkillRunner.SKILL_STUN, w.time, 3.0, {"visual": ""})
	var state := w.mob_status_rng.state
	_ticks(w, 6 * 60 + 30)
	assert_eq(w.mob_status_rng.state, state, "casts during the stun and its immunity (until 7 s) draw nothing")
	_ticks(w, 120)
	assert_ne(w.mob_status_rng.state, state, "after the lockout the rolls resume")


## A queued Final Attack is lost while stunned, and none is queued afterwards until the stun ends.
func test_projectile_hits_cannot_trigger_new_final_attacks_while_stunned() -> void:
	for stunned in [false, true]:
		var w := CF.ranged_final(1452000, 312)
		var m := RF.put_mob(w, 1110100, 380, 190, 100)
		w.mob_kinds[w.swarm.kind[m]].move_speed = 0
		if stunned:
			w.mob_skills.statuses.apply(MobSkillRunner.SKILL_STUN, w.time, 2.0, {"visual": ""})
		w.hit_mob(m, {"skill": "trigger", "damage_type": "physical", "damage_min": 1,
			"damage_max": 1, "crit": 0, "crit_mult": 1.5}, -1)
		w.step(DT, MoveInput.new())
		var followups := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "final_attack")
		if stunned:
			assert_true(followups.is_empty(), "no follow-up attack during stun")
		else:
			assert_false(followups.is_empty(), "control: the Final Attack works without stun")


## The stun does not touch Slow: both can be active, each with its own state.
func test_stun_and_slow_are_independent() -> void:
	var w := _world()
	w.mob_skills.statuses.apply(MobSkillRunner.SKILL_SLOW, w.time, 20.0, {"multiplier": 0.8, "visual": "x"}, false)
	_ticks(w, 900)
	assert_true(_stunned(w))
	assert_eq(w.player_state.slow.skill_id, 126)
	assert_near(w.mob_skills.speed_multiplier(w.time), 0.8, 1e-6)
