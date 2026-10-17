extends TestCase
## Jr. Boogie's Seal (MobSkill 120, #76) through the seeded fixed-tick RunWorld seam: the prop roll on its own stream,
## the canonical box, half-speed skill cooldowns (Teleport included, the basic attack not), expiry, recast extension,
## Curse (124) skipped, slot reuse, and the buff row's Seal icon.

const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _ticks(w: RunWorld, n: int) -> Array:
	var out: Array = []
	for tick in n:
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


## Steps until the first `type` event; returns it with "tick" (or {} after `limit` ticks).
func _until(w: RunWorld, type: String, limit: int = 1800) -> Dictionary:
	for tick in limit:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == type:
				e["tick"] = tick
				return e
	return {}


func _sealed_world(seal: Dictionary = {}, prop := 100.0) -> RunWorld:
	var w := MF.world(76, {}, seal, prop)
	w.god = true
	RF.put_mob(w, MF.BOOGIE, 600)
	return w


func test_a_winning_roll_seals_the_character_in_the_box() -> void:
	var w := _sealed_world()
	var cast := _until(w, "mob_skill")
	assert_false(cast.is_empty(), "Jr. Boogie casts within its first wait")
	if cast.is_empty():
		return
	assert_eq(int(cast.skill_id), 120)
	assert_eq(int(cast.mob_id), MF.BOOGIE)
	assert_eq(String(cast.action), "skill1", "the canonical action stance")
	assert_eq(String(cast.effect), "Skill.wz/MobSkill.img/120/level/1/effect")
	assert_true(bool(cast.applied))
	assert_eq(w.mob_action_view().actions[int(cast.mob)], "skill1")
	var seal: Dictionary = w.player_state.seal
	assert_false(seal.is_empty(), "the character is sealed")
	assert_eq(int(seal.skill_id), 120)
	assert_near(float(seal.remaining), 30.0, DT, "canonical time 30 s")
	assert_near(float(seal.multiplier), 2.0, 1e-9)
	assert_eq(String(seal.visual), "Skill.wz/MobSkill.img/120/level/1/affected")
	assert_eq(String(seal.icon), "Skill.wz/MobSkill.img/120/level/1/affected/0", "tier C: v83 has no Seal icon")
	assert_near(w.skill_cooldown_rate(), 0.5, 1e-12)


func test_the_status_event_carries_the_skill_remaining_time_and_source() -> void:
	var w := _sealed_world()
	var applied := _until(w, "player_status_applied")
	assert_false(applied.is_empty())
	if applied.is_empty():
		return
	assert_eq(String(applied.status), "seal")
	assert_eq(int(applied.skill_id), 120)
	assert_eq(int(applied.mob_id), MF.BOOGIE)
	assert_near(float(applied.remaining), 30.0, 1e-6)
	assert_eq(String(applied.visual), "Skill.wz/MobSkill.img/120/level/1/affected")


func test_a_losing_roll_casts_without_sealing() -> void:
	var w := _sealed_world({}, 0.0)
	var events := _ticks(w, roundi(25.0 / DT))
	var casts := _of(events, "mob_skill")
	assert_true(casts.size() >= 2, "the cast still happens on its interval")
	assert_false(casts.any(func(e: Dictionary) -> bool: return bool(e.applied)))
	assert_true(_of(events, "player_status_applied").is_empty())
	assert_true((w.player_state.seal as Dictionary).is_empty())
	assert_eq(w.skill_cooldown_rate(), 1.0)


func test_outside_the_box_there_is_no_cast_and_no_roll() -> void:
	var w := MF.world()
	w.god = true
	# Within view but 320 px away: outside lt/rb (-300..300).
	RF.put_mob(w, MF.BOOGIE, 720)
	var before := w.mob_skill_rng.state
	var events := _ticks(w, roundi(25.0 / DT))
	assert_true(_of(events, "mob_skill").is_empty())
	assert_eq(w.mob_skill_rng.state, before, "the prop roll happens only when a cast is attempted")


func test_the_roll_uses_its_own_new_stream_once_per_cast() -> void:
	var w := _sealed_world({}, 50.0)
	var probe := RandomNumberGenerator.new()
	probe.seed = 76 * 1000003 + 12 * 7919
	assert_eq(w.mob_skill_rng.state, probe.state, "stream 12 of the run seed, untouched before the first cast")
	var cast := _until(w, "mob_skill")
	assert_false(cast.is_empty())
	probe.randf()
	assert_eq(w.mob_skill_rng.state, probe.state, "exactly one roll for the cast")
	# The same run with a Jr. Boogie that lists only Curse never casts: every existing stream must match it.
	var quiet := MF.world(76, {}, {}, 50.0, [124])
	quiet.god = true
	RF.put_mob(quiet, MF.BOOGIE, 600)
	_ticks(quiet, int(cast.tick) + 1)
	assert_eq(_streams(w), _streams(quiet), "no existing stream shifts when a cast is rolled")
	assert_ne(w.mob_skill_rng.state, quiet.mob_skill_rng.state)


## The states of every stream that existed before #76 (RunWorld header, streams 1-11).
func _streams(w: RunWorld) -> Array:
	return [w.rng.state, w.spawn_rng.state, w.card_rng.state, w.drop_rng.state, w.potion_rng.state,
		w.reward_rng.state, w.job_rng.state, w.meso_rng.state, w.equip_rng.state, w.scroll_rng.state, w.basic_rng.state]


func test_sealed_cooldowns_take_twice_as_long_and_teleport_too() -> void:
	var w := _sealed_world()
	w.learn_skill("energy_bolt")
	var cast := _until(w, "player_status_applied")
	assert_false(cast.is_empty())
	# No target is left, so nothing casts; the cooldown just counts down.
	for slot in w.swarm.capacity():
		w.swarm.despawn(slot)
	w.runner.cooldowns["energy_bolt"] = 3.0
	w._teleport_left = 1.0
	_ticks(w, roundi(5.9 / DT))
	assert_true(w.skill_readiness("energy_bolt").left > 0.0, "3 s left is not ready after 5.9 s sealed")
	assert_near(w._teleport_left, 0.0, 1e-9, "1 s of Teleport repeat delay took 2 s")
	_ticks(w, roundi(0.1 / DT))
	assert_near(w.skill_readiness("energy_bolt").left, 0.0, 1e-9, "ready after 2 x 3 s")
	assert_near(float(w.runner.cooldowns["energy_bolt"]), 0.0, 1e-6)


func test_the_basic_attack_interval_is_unchanged_while_sealed() -> void:
	var sealed_w := RunWorld.new(RF.with_basic_attack(MF.setup(76, {}, {}, 100.0)))
	var clear_w := RunWorld.new(RF.with_basic_attack(MF.setup(76, {}, {}, 0.0)))
	var gaps := []
	for w: RunWorld in [sealed_w, clear_w]:
		RF.place_player(w, 400)
		w.god = true
		RF.put_mob(w, MF.BOOGIE, 600)
		RF.put_mob(w, MF.TAURO, 440)
		assert_false(_until(w, "mob_skill").is_empty())
		var starts: Array = []
		for e: Dictionary in _ticks(w, roundi(6.0 / DT)):
			if e.type == "basic_attack" and e.phase == "start":
				starts.append(float(e.interval))
		gaps.append(starts)
	assert_false((sealed_w.player_state.seal as Dictionary).is_empty())
	assert_true((clear_w.player_state.seal as Dictionary).is_empty())
	assert_false((gaps[0] as Array).is_empty(), "the basic attack swings while sealed")
	assert_eq(gaps[0], gaps[1], "same swing intervals sealed or not")


func test_seal_expires_after_time_times_duration_mult() -> void:
	var w := _sealed_world({"duration_mult": 0.5, "interval_mult": 10.0})
	var applied := _until(w, "player_status_applied", 18000)
	assert_false(applied.is_empty())
	assert_near(float(applied.remaining), 15.0, 1e-6, "30 s x 0.5")
	_ticks(w, roundi(15.0 / DT) - 1)
	assert_false((w.player_state.seal as Dictionary).is_empty(), "still sealed just before 15 s")
	_ticks(w, 1)
	assert_true((w.player_state.seal as Dictionary).is_empty(), "expired at 15 s")
	assert_eq(w.skill_cooldown_rate(), 1.0, "full speed again")


func test_a_recast_extends_to_the_later_end_without_stacking() -> void:
	var w := _sealed_world()
	var first := _until(w, "player_status_applied")
	assert_false(first.is_empty())
	var second := _until(w, "player_status_applied")
	assert_false(second.is_empty(), "recast after the canonical 10 s interval")
	if second.is_empty():
		return
	assert_eq(int(second.tick), roundi(10.0 / DT) - 1, "10 s after the first cast")
	assert_near(float(second.remaining), 30.0, 1e-6, "extended to now + 30 s, not 20 + 30 s")
	assert_near(float(w.player_state.seal.remaining), 30.0, 1e-6)
	assert_near(w.skill_cooldown_rate(), 0.5, 1e-12, "the multiplier does not stack")


func test_a_curse_only_mob_never_applies_anything() -> void:
	var w := MF.world(76, {}, {}, 100.0, [124])
	w.god = true
	RF.put_mob(w, MF.BOOGIE, 600)
	var before := w.mob_skill_rng.state
	var events := _ticks(w, roundi(40.0 / DT))
	assert_true(_of(events, "mob_skill").is_empty(), "MobSkill 124 is skipped")
	assert_true(_of(events, "player_status_applied").is_empty())
	assert_true((w.player_state.seal as Dictionary).is_empty())
	assert_eq(w.mob_skill_rng.state, before)
	assert_eq(w.skill_cooldown_rate(), 1.0)


func test_a_reused_slot_does_not_inherit_a_ready_cast() -> void:
	var w := MF.world()
	w.god = true
	var slot := RF.put_mob(w, MF.BOOGIE, 720)
	_ticks(w, roundi(15.0 / DT))
	w.swarm.despawn(slot)
	assert_eq(RF.put_mob(w, MF.BOOGIE, 600), slot, "fixture: the slot is reused")
	var settle := 0
	while not w.swarm.can_act(slot) and settle < 600:
		w.step(DT, MoveInput.new())
		settle += 1
	w.drain_events()
	assert_true(_of(_ticks(w, roundi(4.9 / DT)), "mob_skill").is_empty(), "the new mob waits >= half of 10 s")


func test_seal_ends_on_death() -> void:
	var w := _sealed_world()
	assert_false(_until(w, "player_status_applied").is_empty())
	w.god = false
	w.take_hit(1000000.0, false, "", Vector2(600, 200), {"source_kind": "other"})
	assert_eq(w.state, RunWorld.DEAD)
	assert_true((w.player_state.seal as Dictionary).is_empty())


func test_buff_row_shows_the_seal_icon_and_countdown() -> void:
	var row := HudBuffRow.new()
	var seal := {"skill_id": 120, "level": 1, "remaining": 12.3, "multiplier": 2.0,
		"visual": "Skill.wz/MobSkill.img/120/level/1/affected", "icon": "Skill.wz/MobSkill.img/120/level/1/affected/0"}
	row.update({"buffs": [], "seal": seal}, {})
	var slots := row.displayed()
	assert_eq(slots.size(), 1)
	if not slots.is_empty():
		assert_eq(int(slots[0].skill_id), 120)
		assert_eq(String(slots[0].skill), "seal")
		assert_eq(int(slots[0].remaining_seconds), 13)
		assert_true(bool(slots[0].status), "drawn as a status on the character, not a buff")
	row.update({"buffs": [], "seal": {}}, {})
	assert_true(row.displayed().is_empty(), "no icon once the seal ends")
	row.free()
