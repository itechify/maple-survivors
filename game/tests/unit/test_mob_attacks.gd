extends TestCase
## Ordinary-mob canonical attacks (#76) through the seeded fixed-tick RunWorld seam: windup and hit at attackAfter,
## magic damage, range/airborne/off-screen gates, the survivor interval, staggered first readiness and slot reuse.

const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BF := preload("res://tests/fixtures/boss_attack_fixtures.gd")
const DT := 1.0 / 60.0


## Steps until `pred(event)` matches an event (returns it, with "tick" added) or `limit` ticks pass ({}).
func _until(w: RunWorld, limit: int, pred: Callable) -> Dictionary:
	for tick in limit:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if pred.call(e):
				e["tick"] = tick
				return e
	return {}


func _is_start(e: Dictionary) -> bool:
	return e.type == "mob_attack" and e.phase == "start"


func _starts(w: RunWorld, ticks: int) -> Array:
	var out: Array = []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if _is_start(e):
				e["tick"] = tick
				out.append(e)
	return out


func test_in_range_tauro_winds_up_then_hits_at_attack_after_with_its_magic_damage() -> void:
	var w := MF.world()
	var slot := RF.put_mob(w, MF.TAURO, 600)
	var start := _until(w, 600, _is_start)
	assert_false(start.is_empty(), "an ordinary mob with attack1 and the character in its box attacks")
	if start.is_empty():
		return
	assert_eq(int(start.mob), slot)
	assert_eq(int(start.mob_id), MF.TAURO)
	assert_eq(String(start.attack), "attack1")
	assert_eq(int(start.facing), -1, "the character is to its left")
	assert_eq(start.area, Rect2(600 + MF.TAURO_LT.x, 200 + MF.TAURO_LT.y, MF.TAURO_RB.x - MF.TAURO_LT.x,
		MF.TAURO_RB.y - MF.TAURO_LT.y), "the canonical box around the feet")
	assert_near(float(start.impact_time) - float(start.time), MF.TAURO_AFTER_MS / 1000.0, 1e-6)
	assert_eq(String(start.sound), "Sound.wz/Mob.img/7130100/Attack1")
	assert_eq(w.mob_action_view().actions[slot], "attack1", "the windup holds the canonical attack stance")
	var hp := int(w.player_state.hp)
	var ticks_to_impact := roundi(MF.TAURO_AFTER_MS / 1000.0 / DT)
	for tick in ticks_to_impact - 1:
		w.step(DT, MoveInput.new())
		assert_eq(int(w.player_state.hp), hp, "no damage before attackAfter")
	w.step(DT, MoveInput.new())
	var hit := {}
	var phases: Array = []
	for e: Dictionary in w.drain_events():
		if e.type == "player_hit":
			hit = e
		elif e.type == "mob_attack":
			phases.append(String(e.phase))
	assert_false(hit.is_empty(), "the hit lands at attackAfter")
	if hit.is_empty():
		return
	assert_true("impact" in phases and "hit" in phases, "impact and the canonical hit effect are reported")
	assert_eq(hit.source_kind, "mob_attack", "ordinary attacks are told apart from boss attacks")
	assert_false(bool(hit.boss))
	assert_eq(int(hit.mob_id), MF.TAURO)
	# Canonical MADamage x dmg_mult 0.5 through the magic-defence path (85-100% roll minus 0.75 M.DEF).
	var mdd := float(w.hit_defense().mdd)
	var lo := roundi((MF.TAURO_MAD * 0.85 - floorf(0.75 * mdd)) * 0.5)
	var hi := roundi((MF.TAURO_MAD - floorf(0.75 * mdd)) * 0.5)
	assert_between(float(hit.damage), lo, hi, "MADamage %d x 0.5 against M.DEF %d" % [MF.TAURO_MAD, mdd])
	assert_eq(int(w.player_state.hp), hp - int(hit.damage))


func test_out_of_range_never_attacks() -> void:
	var w := MF.world()
	RF.put_mob(w, MF.TAURO, 750)
	assert_true(_starts(w, 900).is_empty(), "the character outside the canonical box is never attacked")


func test_off_screen_never_attacks() -> void:
	# A 300 px view puts the mob at x 600 outside it while the character stays inside the 404 px box.
	var w := MF.world(76, {}, {}, 100.0, [120, 124], Vector2(300, 600))
	RF.put_mob(w, MF.TAURO, 600)
	assert_false(w.view.has_point(Vector2(600, 200)), "fixture: the mob stands outside the view")
	assert_true(_starts(w, 900).is_empty(), "an off-screen mob never attacks")


func test_airborne_mob_waits_for_the_ground() -> void:
	var w := MF.world()
	w.god = true
	var slot := RF.put_mob(w, MF.TAURO, 600)
	var first := _until(w, 600, _is_start)
	assert_false(first.is_empty())
	# Lift it into the air with the character still inside its box; it may not start a windup until it lands.
	_until(w, roundi(3.0 / DT) - 1, func(e: Dictionary) -> bool: return false)
	w.swarm.y[slot] = 150.0
	w.swarm.fh[slot] = -1
	w.swarm.state[slot] = MobSwarm.JUMP
	var airborne_starts := 0
	var landed_start := false
	for tick in 120:
		var was_airborne := w.swarm.fh[slot] < 0
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if _is_start(e):
				if was_airborne and w.swarm.fh[slot] < 0:
					airborne_starts += 1
				else:
					landed_start = true
	assert_eq(airborne_starts, 0, "an airborne mob never starts an attack")
	assert_true(landed_start, "it attacks once grounded again")


func test_consecutive_attacks_respect_the_survivor_interval() -> void:
	var w := MF.world()
	w.god = true
	RF.put_mob(w, MF.TAURO, 600)
	var starts := _starts(w, roundi(12.0 / DT))
	assert_true(starts.size() >= 3, "several attacks in 12 s")
	for i in range(1, starts.size()):
		assert_eq(int(starts[i].tick) - int(starts[i - 1].tick), roundi(3.0 / DT), "interval 3 s from balance data")


func test_default_interval_applies_without_a_per_mob_entry() -> void:
	var w := MF.world(76, {"mobs": {}})
	w.god = true
	RF.put_mob(w, MF.TAURO, 600)
	var starts := _starts(w, roundi(16.0 / DT))
	assert_true(starts.size() >= 2)
	for i in range(1, starts.size()):
		assert_eq(int(starts[i].tick) - int(starts[i - 1].tick), roundi(5.0 / DT), "default_interval 5 s")


func test_same_tick_spawns_do_not_first_attack_together() -> void:
	var w := MF.world()
	w.god = true
	var a := RF.put_mob(w, MF.TAURO, 600)
	var b := RF.put_mob(w, MF.TAURO, 610)
	var c := RF.put_mob(w, MF.TAURO, 590)
	var first := {}
	for e: Dictionary in _starts(w, roundi(6.0 / DT)):
		if not first.has(int(e.mob)):
			first[int(e.mob)] = int(e.tick)
	assert_eq(first.size(), 3, "every mob attacks within two intervals")
	assert_ne(first.get(a), first.get(b))
	assert_ne(first.get(b), first.get(c))
	assert_ne(first.get(a), first.get(c))
	for slot: int in first:
		# tier C rule: the first wait is 50-100% of the interval of visible time after the mob is fully faded in.
		assert_true(int(first[slot]) >= roundi(1.5 / DT), "no attack before half an interval")


func test_reused_slot_does_not_inherit_a_ready_attack_or_a_pending_windup() -> void:
	var w := MF.world()
	w.god = true
	var slot := RF.put_mob(w, MF.TAURO, 600)
	var start := _until(w, 600, _is_start)
	assert_false(start.is_empty())
	# Mid-windup: the mob is removed and a new Tauro takes the same slot.
	w.swarm.despawn(slot)
	var again := RF.put_mob(w, MF.TAURO, 600)
	assert_eq(again, slot, "fixture: the swarm reuses the freed slot")
	var events: Array = []
	for tick in roundi(1.0 / DT):
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	assert_false(events.any(func(e: Dictionary) -> bool: return e.type == "mob_attack"),
		"the old windup never lands and the new mob is not ready at once")
	assert_eq(w.mob_action_view().actions[slot] if slot < w.mob_action_view().actions.size() else "", "",
		"no inherited attack stance")


func test_reused_slot_starts_its_own_first_wait() -> void:
	var w := MF.world()
	w.god = true
	# Out of range but on screen: the wait runs out and the mob stays ready, waiting for the character.
	var slot := RF.put_mob(w, MF.TAURO, 750)
	assert_true(_starts(w, roundi(6.0 / DT)).is_empty())
	assert_near(w.mob_attacks.wait_left(slot), 0.0, 1e-9, "fixture: the old mob is ready")
	w.swarm.despawn(slot)
	assert_eq(RF.put_mob(w, MF.TAURO, 600), slot, "fixture: the swarm reuses the freed slot")
	assert_true(is_nan(w.mob_attacks.wait_left(slot)), "the new mob's wait is unset until it can act")
	var settle := 0
	while not w.swarm.can_act(slot) and settle < 600:
		w.step(DT, MoveInput.new())
		settle += 1
	w.drain_events()
	# tier C first wait: at least half of the 3 s interval of visible time.
	assert_true(_starts(w, roundi(1.4 / DT)).is_empty(), "a ready timer is not inherited by the slot's next mob")
	assert_false(_starts(w, roundi(1.7 / DT)).is_empty(), "it attacks after its own first wait")


func test_relocation_cancels_a_windup_and_keeps_the_mob_waiting() -> void:
	var w := MF.world()
	w.god = true
	var slot := RF.put_mob(w, MF.TAURO, 600)
	var start := _until(w, 600, _is_start)
	assert_false(start.is_empty())
	var moved := w.relocate_mob(slot, Vector2(620, 200), w.fhm.find_below(620, 190))
	var events: Array = []
	for tick in roundi(1.0 / DT):
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	assert_false(events.any(func(e: Dictionary) -> bool: return e.type == "mob_attack" and e.phase == "impact"),
		"a relocated mob's windup is cancelled")
	assert_true(moved >= 0)


func test_scheduled_boss_keeps_boss_attack_events_only() -> void:
	var w := RunWorld.new(BF.setup())
	var kinds := {}
	for tick in 600:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if String(e.type) in ["boss_attack", "mob_attack"]:
				kinds[String(e.type)] = true
	assert_true(kinds.has("boss_attack"))
	assert_false(kinds.has("mob_attack"), "a scheduled boss never goes through the ordinary path")
