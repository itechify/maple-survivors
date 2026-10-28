extends TestCase
## Boss schedules, touch-only encounters and clear rules through fixed-tick seeded run simulation.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BALANCE_RUN := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0


func _setup(times: Array = [3.5]) -> Dictionary:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	var stage: Dictionary = data.stages.stages.quiet
	stage.duration = 5.0
	var entries: Array = []
	for at: float in times:
		entries.append({"time": at, "mob_id": 2220000, "hp_mult": 2.0, "dmg_mult": 1.75})
	RF.set_bosses(stage, entries)
	var setup := RF.setup("quiet", 1901, data)
	var img: Dictionary = setup.mob_imgs[100100].duplicate(true)
	img.info = {"maxHP": 2000.0, "PADamage": 90.0, "acc": 60.0, "boss": 1.0,
		"pushed": 1.0, "bodyAttack": 1.0, "exp": 120.0, "speed": -40.0}
	setup.mob_imgs[2220000] = img
	return setup


func test_warning_precedes_reachable_spawn_by_three_seconds() -> void:
	var w := RunWorld.new(_setup())
	w.god = true
	var warning := {}
	var spawned := {}
	for tick in 220:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_warning":
				warning = e
			elif e.type == "boss_spawned":
				spawned = e
	assert_false(warning.is_empty(), "warning was emitted")
	assert_false(spawned.is_empty(), "boss arrived")
	if warning.is_empty() or spawned.is_empty():
		return
	assert_eq(spawned.mob_id, 2220000)
	assert_near(float(spawned.time) - float(warning.time), 3.0, DT)
	var slot := int(spawned.mob)
	assert_eq(w.fhm.platform_of(w.swarm.fh[slot]), w.player_platform(), "spawn is reachable on the player's floor")
	assert_near(Vector2(w.swarm.x[slot], w.swarm.y[slot]).distance_to(w.player.pos), 250.0, 1.0)
	assert_eq(w.swarm.max_hp[slot], 4000, "canonical HP times the explicit boss multiplier")


func _kill(w: RunWorld, slot: int) -> void:
	w.hit_mob(slot, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)


func test_clear_waits_for_every_boss_death() -> void:
	var setup := _setup([0.5, 1.0, 1.5])
	setup.data.stages.stages.quiet.duration = 1.5
	var w := RunWorld.new(setup)
	w.god = true
	for tick in 120:
		w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.PLAYING, "the timer cannot clear a boss stage")
	assert_eq(w.bosses.live_count(), 3)
	for index in 2:
		_kill(w, int(w.bosses.records[index].slot))
		w.step(DT, MoveInput.new())
		RF.auto_choose(w)
		assert_eq(w.state, RunWorld.PLAYING, "a remaining boss blocks clear")
	_kill(w, int(w.bosses.records[2].slot))
	for tick in 120:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
		if w.state == RunWorld.CLEARED:
			break
	assert_eq(w.state, RunWorld.CLEARED)
	assert_true(w.bosses.all_dead())
	var deaths := 0
	var cleared := 0
	for e: Dictionary in w.drain_events():
		if e.type == "boss_died":
			deaths += 1
		elif e.type == "stage_cleared":
			cleared += 1
	assert_eq(deaths, 3)
	assert_eq(cleared, 1)


func test_no_boss_stage_keeps_duration_clear() -> void:
	var w := RF.quiet_world(400.0, 1902)
	w.duration = 1.0
	for tick in 61:
		w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CLEARED)
	assert_near(w.time, 1.0, DT)


func test_scheduled_boss_arrives_on_time_even_when_ordinary_swarm_is_capped() -> void:
	var setup := _setup([0.5])
	setup.data.stages.stages.quiet.hard_cap = 2
	var w := RunWorld.new(setup)
	w.god = true
	for i in 2:
		w.spawn_mob(int(w.kind_of_id[100100]), Vector2(-500.0 - i * 50.0, 0.0), -1, 1.0, false)
	assert_eq(w.swarm.alive_count(), w.director.hard_cap)
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(w.bosses.live_count(), 1, "scheduled arrivals bypass the ordinary crowd cap")
	assert_near(float(w.bosses.records[0].spawn_time), 0.5, DT)
	assert_eq(w.swarm.alive_count(), 3, "ordinary cap never consumes the scheduled boss slot")


func test_boss_takes_damage_without_stun_or_push() -> void:
	var w := RunWorld.new(_setup([0.5]))
	w.god = true
	for tick in 60:
		w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	var state := w.swarm.state[slot]
	var velocity := w.swarm.vx[slot]
	var hp := w.swarm.hp[slot]
	w.hit_mob(slot, {"damage_min": 100.0, "damage_max": 100.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	assert_eq(w.swarm.hp[slot], hp - 100)
	assert_eq(w.swarm.state[slot], state, "boss attack never changes its movement into HIT")
	assert_eq(w.swarm.vx[slot], velocity, "boss ignores the knockback direction")


func test_arrival_without_a_point_rewarns_and_keeps_the_three_second_lead() -> void:
	var setup := _setup([3.5])
	setup.data.stages.stages.quiet.duration = 1.0
	setup.map_img = RF.map_from_segments([{"x1": -2000, "y1": 0, "x2": -100, "y2": 0},
		{"x1": 100, "y1": 0, "x2": 2000, "y2": 0}], [Vector2(-600, -10)])
	var w := RunWorld.new(setup)
	w.god = true
	var warnings: Array[float] = []
	var spawned := -1.0
	for tick in 9 * 60:
		if w.time >= 3.3 and w.time < 4.0:
			# The player hangs over the gap between the floors: no player platform, so no arrival point.
			w.player.pos = Vector2(0, -300)
			w.player.vel = Vector2.ZERO
			w.player.fh = -1
		elif w.time >= 4.0 and w.time < 4.0 + DT:
			RF.place_player(w, -600.0, -10.0)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_warning":
				warnings.append(float(e.time))
			elif e.type == "boss_spawned":
				spawned = float(e.time)
	assert_eq(warnings.size(), 2, "the original warning plus a fresh one when the arrival slips")
	assert_true(spawned > 0.0, "the boss arrives once a point exists")
	if warnings.size() != 2 or spawned < 0.0:
		return
	assert_near(warnings[0], 0.5, DT)
	assert_near(warnings[1], 3.5, DT, "the fresh warning fires on the failed arrival tick")
	assert_near(spawned - warnings[1], 3.0, DT, "arrival keeps the 3 s warning lead")
	assert_eq(w.state, RunWorld.PLAYING, "no clear while the delayed boss is alive")


## Holds the player in the air over the gap between the two floors of _gap_map (no floor below: no player platform).
func _strand(w: RunWorld) -> void:
	w.player.pos = Vector2(0, -300)
	w.player.vel = Vector2.ZERO
	w.player.fh = -1


func _gap_map() -> Dictionary:
	return RF.map_from_segments([{"x1": -2000, "y1": 0, "x2": -100, "y2": 0},
		{"x1": 100, "y1": 0, "x2": 2000, "y2": 0}], [Vector2(-600, -10)])


func test_arrival_postponed_past_the_fallback_bound_lands_near_the_player() -> void:
	# #260: a player that never stands over a floor again (a void under the map) postponed the boss forever. After
	# bosses.arrival_fallback s of postponing, it arrives on the floor nearest to the player, still 3 s after a warning.
	var setup := _setup([3.5])
	setup.data.stages.stages.quiet.duration = 1.0
	setup.map_img = _gap_map()
	var w := RunWorld.new(setup)
	w.god = true
	var bound := float(w.bosses.rules.arrival_fallback)
	assert_between(bound, 3.0, 60.0, "a bounded fallback is configured (balance.json bosses)")
	var warnings: Array[float] = []
	var spawned := {}
	for tick in int((3.5 + bound + 8.0) * 60.0):
		if w.time >= 3.3:
			_strand(w)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_warning":
				warnings.append(float(e.time))
			elif e.type == "boss_spawned":
				spawned = e
		if not spawned.is_empty():
			break
	assert_false(spawned.is_empty(), "the boss arrives although the player never has a platform")
	if spawned.is_empty():
		return
	assert_true(float(spawned.time) <= 3.5 + bound + 3.0 + DT, "within the bound plus one warning lead (%.2f)" % float(spawned.time))
	assert_true(float(spawned.time) >= 3.5 + bound - DT, "not before the bound (%.2f)" % float(spawned.time))
	assert_near(float(spawned.time) - warnings[warnings.size() - 1], 3.0, DT, "the 3 s warning lead still holds")
	assert_true(bool(spawned.get("fallback", false)), "boss_spawned marks the fallback arrival")
	var slot := int(spawned.mob)
	assert_true(w.swarm.fh[slot] >= 0, "standing on a floor")
	assert_true(absf(w.swarm.x[slot]) >= 100.0, "on one of the floors, not over the gap")


func test_arrival_postponed_once_keeps_the_normal_rule() -> void:
	var setup := _setup([3.5])
	setup.data.stages.stages.quiet.duration = 1.0
	setup.map_img = _gap_map()
	var w := RunWorld.new(setup)
	w.god = true
	var spawned := {}
	for tick in 12 * 60:
		if w.time >= 3.3 and w.time < 4.0:
			_strand(w)
		elif w.time >= 4.0 and w.time < 4.0 + DT:
			RF.place_player(w, -600.0, -10.0)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_spawned":
				spawned = e
		if not spawned.is_empty():
			break
	assert_false(spawned.is_empty(), "arrived")
	if spawned.is_empty():
		return
	assert_near(float(spawned.time), 6.5, DT, "one postponement: 3 s after the fresh warning")
	assert_false(bool(spawned.get("fallback", false)), "an ordinary postponed arrival is not a fallback")
	assert_near(Vector2(spawned.pos).distance_to(w.player.pos), 250.0, 1.0,
		"the usual spawn distance on the player's platform")


func test_pursuit_teleport_without_a_point_falls_back_after_the_bound() -> void:
	# A spawned boss that fades out to follow a player who then has no platform must not stay faded forever.
	var setup := _setup([0.5])
	setup.data.stages.stages.quiet.duration = 1.0
	setup.map_img = _gap_map()
	var w := RunWorld.new(setup)
	w.god = true
	var bound := float(w.bosses.rules.arrival_fallback)
	var spawned_at := -1.0
	var teleported := {}
	for tick in int((4.0 + float(w.bosses.rules.teleport_stall) + bound + 6.0) * 60.0):
		if spawned_at >= 0.0:
			_strand(w)
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_spawned":
				spawned_at = float(e.time)
			elif e.type == "boss_teleported":
				teleported = e
		if not teleported.is_empty():
			break
	assert_true(spawned_at >= 0.0, "spawned while the player stood on a floor")
	assert_false(teleported.is_empty(), "the faded boss reappears although the player has no platform")
	if teleported.is_empty():
		return
	assert_true(float(teleported.time) <= spawned_at + float(w.bosses.rules.teleport_stall) + 1.0 + bound,
		"within the stall, the fade and the bound (%.2f)" % float(teleported.time))
	var slot := int(teleported.mob)
	assert_true(w.swarm.fh[slot] >= 0, "on a floor")
	assert_false(bool(w.bosses.records[0].fading), "no longer fading: visible again")


func test_boss_without_a_mob_img_is_skipped_with_a_warning_and_never_blocks_the_clear() -> void:
	var setup := _setup([0.5, 1.5])
	setup.data.stages.stages.quiet.duration = 1.0
	setup.data.stages.stages.quiet.maps[1].boss.mob_id = 2229999
	var w := RunWorld.new(setup)
	w.god = true
	var warned_ids: Array[int] = []
	for tick in 120:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_warning":
				warned_ids.append(int(e.mob_id))
	assert_eq(warned_ids, [2220000] as Array[int], "a boss that cannot arrive is never announced")
	assert_true(bool(w.bosses.records[1].skipped), "the missing boss is skipped at its arrival time")
	assert_true(Array(w.warnings).any(func(s: String) -> bool: return s.contains("2229999")),
		"the run reports the skipped boss")
	assert_eq(w.state, RunWorld.PLAYING, "the present boss still has to die")
	_kill(w, int(w.bosses.records[0].slot))
	for tick in 120:
		RF.auto_choose(w)
		w.step(DT, MoveInput.new())
		if w.state == RunWorld.CLEARED:
			break
	assert_eq(w.state, RunWorld.CLEARED, "the skipped boss does not block the clear")
	assert_eq(BALANCE_RUN.fight_records(w)[1].status, "skipped")


func test_scheduled_boss_without_wz_boss_flag_or_override_never_flinches() -> void:
	var setup := _setup([0.5])
	setup.mob_imgs[2220000].info.erase("boss")
	setup.mob_imgs[2220000].info.pushed = 1.0
	var w := RunWorld.new(setup)
	w.god = true
	var kind: MobKind = w.mob_kinds[int(w.kind_of_id[2220000])]
	assert_false(kind.boss or kind.no_flinch, "the synthetic kind has neither info/boss nor no_flinch")
	var loose := w.spawn_mob(int(w.kind_of_id[2220000]), w.player.pos + Vector2(-400, 0), w.player.fh, 1.0, false)
	for tick in 60:
		w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	assert_true(slot >= 0 and slot != loose, "the scheduled boss arrived in its own slot")
	var state := w.swarm.state[slot]
	var velocity := w.swarm.vx[slot]
	w.hit_mob(slot, {"damage_min": 100.0, "damage_max": 100.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	assert_eq(w.swarm.state[slot], state, "scheduled boss never enters HIT without the WZ flag")
	assert_eq(w.swarm.vx[slot], velocity, "scheduled boss is never pushed without the WZ flag")
	var moved := w.relocate_mob(slot, w.player.pos + Vector2(250, 0), w.player.fh)
	assert_eq(w.swarm.steady[moved], 1, "relocation keeps the scheduled boss steady")
	w.hit_mob(loose, {"damage_min": 100.0, "damage_max": 100.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	assert_eq(w.swarm.state[loose], MobSwarm.HIT, "the same kind spawned as an ordinary mob still flinches")


func test_normal_spawn_rate_halves_during_boss_encounter() -> void:
	var setup := _setup([0.5])
	var stage: Dictionary = setup.data.stages.stages.quiet
	stage.keyframes[0].rate = 4.0
	stage.keyframes[0].max_alive = 100.0
	stage.keyframes[0].pool = {"100100": 1.0}
	var w := RunWorld.new(setup)
	w.god = true
	assert_eq(w.director.effective_rate(w), 4.0)
	for tick in 60:
		w.step(DT, MoveInput.new())
	assert_eq(w.director.effective_rate(w), 2.0)
	var before := w.director.spawned
	for tick in 120:
		w.step(DT, MoveInput.new())
	assert_between(w.director.spawned - before, 3, 4, "two ordinary mobs per second while the boss lives")
	_kill(w, int(w.bosses.records[0].slot))
	assert_eq(w.director.effective_rate(w), 4.0, "normal rate returns after death")


func test_normal_burst_count_halves_during_boss_encounter() -> void:
	var setup := _setup([0.5])
	setup.data.stages.stages.quiet.bursts = {"first": 1.0, "every": 100.0, "count_min": 10, "count_max": 10}
	var w := RunWorld.new(setup)
	w.god = true
	for tick in 61:
		w.step(DT, MoveInput.new())
	var count := -1
	for e: Dictionary in w.drain_events():
		if e.type == "burst":
			count = int(e.count)
	assert_eq(count, 5, "normal wave pressure is also halved while a boss lives")


func test_spawn_keyframes_keep_ramping_after_final_arrival() -> void:
	var setup := _setup([900.0])
	var stage: Dictionary = setup.data.stages.stages.quiet
	stage.post_duration_slope = 0.25
	stage.keyframes = [
		{"t": 720.0, "rate": 13.5, "max_alive": 240.0, "hp": 3.4, "speed": 1.28, "pool": {"100100": 1.0}},
		{"t": 900.0, "rate": 20.0, "max_alive": 330.0, "hp": 5.5, "speed": 1.4, "pool": {"100100": 1.0}},
	]
	var w := RunWorld.new(setup)
	assert_near(w.director.rate_at(1080.0), 21.625, 1e-6, "quarter of the preceding rate slope")
	assert_near(w.director.value_at("hp", 1080.0), 6.025, 1e-6)
	assert_true(w.director.max_alive_at(1080.0) > 330)


func test_bursts_and_elites_keep_ramping_after_the_last_keyframe() -> void:
	var setup := _setup([900.0])
	var stage: Dictionary = setup.data.stages.stages.quiet
	stage.duration = 900.0
	stage.post_duration_slope = 0.25
	stage.bursts = {"first": 90.0, "every": 90.0, "count_min": 10.0, "count_max": 40.0}
	stage.elites = {"first": 75.0, "every": 60.0, "hp_mult": 8.0, "exp_mult": 5.0, "damage_mult": 1.5}
	stage.keyframes = [
		{"t": 720.0, "rate": 13.5, "max_alive": 240.0, "hp": 3.4, "speed": 1.28, "pool": {"100100": 1.0}},
		{"t": 900.0, "rate": 20.0, "max_alive": 330.0, "hp": 5.5, "speed": 1.4, "pool": {"100100": 1.0}},
	]
	var w := RunWorld.new(setup)
	assert_eq(w.director.burst_count_at(450.0), 25, "bursts still grow linearly over the stage")
	assert_eq(w.director.burst_count_at(900.0), 40)
	# 40 + (40 - 10) / 900 s x 180 s x 0.25 = 41.5
	assert_eq(w.director.burst_count_at(1080.0), 42, "burst size keeps its slope at quarter pace")
	assert_true(w.director.burst_count_at(1800.0) > w.director.burst_count_at(1080.0))
	assert_near(w.director.elite_interval_at(600.0), 60.0, 1e-9, "elite cadence is fixed before the last keyframe")
	assert_near(w.director.elite_interval_at(900.0), 60.0, 1e-9)
	assert_near(w.director.elite_interval_at(1080.0), 60.0 * 20.0 / 21.625, 1e-6,
		"elites stay the same share of the extrapolated steady rate")
	assert_true(w.director.elite_interval_at(1800.0) < w.director.elite_interval_at(1080.0))
	stage.post_duration_slope = 0.0
	var flat := RunWorld.new(setup)
	assert_eq(flat.director.burst_count_at(1080.0), 40, "no slope: bursts hold their final size")
	assert_near(flat.director.elite_interval_at(1080.0), 60.0, 1e-9, "no slope: elite cadence holds")


func test_elite_schedule_uses_the_ramped_interval_after_the_last_keyframe() -> void:
	var setup := _setup([5000.0])
	var stage: Dictionary = setup.data.stages.stages.quiet
	stage.duration = 2.0
	stage.post_duration_slope = 1.0
	stage.elites = {"first": 3.0, "every": 2.0, "hp_mult": 1.0, "exp_mult": 1.0, "damage_mult": 1.0}
	stage.keyframes = [
		{"t": 0.0, "rate": 1.0, "max_alive": 50.0, "hp": 1.0, "speed": 1.0, "pool": {"100100": 1.0}},
		{"t": 2.0, "rate": 2.0, "max_alive": 50.0, "hp": 1.0, "speed": 1.0, "pool": {"100100": 1.0}},
	]
	var w := RunWorld.new(setup)
	w.god = true
	var elite_times: Array[float] = []
	for tick in 8 * 60:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "mob_spawned" and bool(e.elite) and int(e.relocated_from) < 0:
				elite_times.append(w.time)
	assert_true(elite_times.size() >= 3, "elites keep coming after the last keyframe")
	if elite_times.size() < 3:
		return
	# rate(3) = 2 + 0.5 x 1 x 1 = 2.5 -> next interval 2 x 2 / 2.5 = 1.6 s; rate(4.6) = 3.3 -> 2 x 2 / 3.3 s.
	assert_near(elite_times[0], 3.0, 2 * DT)
	assert_near(elite_times[1] - elite_times[0], 1.6, 2 * DT)
	assert_near(elite_times[2] - elite_times[1], 4.0 / 3.3, 2 * DT)


func test_boss_touch_uses_explicit_multiplier_and_hit_source_identity() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var examples: Array = DataRepo.stage_bosses(stages.henesys) + DataRepo.stage_bosses(stages.ellinia)
	# Canonical v83 contact PADamage (checked against the real cache in test_boss_hit_bands).
	var attacks := {2220000: 90.0, 6130101: 200.0, 9400205: 450.0, 3220000: 125.0, 9300003: 130.0, 6220000: 190.0}
	for entry: Dictionary in examples:
		var setup := _setup([0.5])
		RF.set_bosses(setup.data.stages.stages.quiet, [entry.duplicate(true)])
		# Contact only: the synthetic img has no attack nodes.
		setup.data.stages.stages.quiet.maps[0].boss.erase("attacks")
		setup.data.stages.stages.quiet.maps[0].boss.time = 0.5
		setup.data.balance.player.hp = float(entry.typical_hp)
		setup.data.balance.player.stats.dex = 0
		setup.data.balance.player.stats.luk = 0
		setup.equipment_info = {1040002: {"incPDD": float(entry.typical_pdd)}}
		var id := int(entry.mob_id)
		var img: Dictionary = setup.mob_imgs[2220000].duplicate(true)
		img.info.PADamage = attacks[id]
		setup.mob_imgs[id] = img
		var w := RunWorld.new(setup)
		for tick in 60:
			w.step(DT, MoveInput.new())
		var slot := int(w.bosses.records[0].slot)
		w.player.place(Vector2(w.swarm.x[slot], w.swarm.y[slot]), w.fhm)
		w.drain_events()
		w.step(DT, MoveInput.new())
		var hit := {}
		for e: Dictionary in w.drain_events():
			if e.type == "player_hit":
				hit = e
		assert_false(hit.is_empty(), "the scheduled boss landed a touch hit")
		if hit.is_empty():
			continue
		assert_eq(hit.boss, true)
		assert_eq(hit.source_kind, "touch")
		assert_eq(hit.mob, slot)
		assert_eq(hit.mob_id, id)
		assert_eq(hit.max_hp, int(entry.typical_hp), "HP pool is captured at hit time")
		assert_true(int(hit.damage) > 0, "the identified touch inflicts damage")
		assert_between(float(hit.damage) / float(entry.typical_hp), 0.4, 0.5, "the landed touch is in the band")
		# The whole roll range, not just a typical roll: 85% and 100% of PAD after defense, at the shipped multiplier.
		var low := CombatMath.monster_damage(attacks[id], 0.0, float(entry.typical_pdd), 0.0, float(entry.dmg_mult))
		var high := CombatMath.monster_damage(attacks[id], 1.0, float(entry.typical_pdd), 0.0, float(entry.dmg_mult))
		assert_between(int(hit.damage), low, high, "the landed touch is one roll of that range")
		assert_true(float(low) / float(entry.typical_hp) >= 0.4 and float(high) / float(entry.typical_hp) <= 0.5,
			"%d touch %d..%d of %d HP lies in 40-50%%" % [id, low, high, int(entry.typical_hp)])


func test_balance_harness_reports_timeout_and_boss_lifecycle_record() -> void:
	var setup := _setup([0.5])
	setup.data.stages.stages.quiet.duration = 1.0
	setup.data.balance.run_time_cap = 2.0
	var w := RunWorld.new(setup)
	w.god = true
	var record: Dictionary = BALANCE_RUN.run_one(w, "bot", 1904)
	assert_eq(record.state, "TIMEOUT", "a live boss can continue beyond the stage duration")
	assert_eq(record.timeout, true)
	assert_near(float(record.time), 2.0, DT)
	assert_eq(record.bosses.size(), 1)
	assert_near(float(record.bosses[0].spawn_time), 0.5, DT)
	assert_eq(record.bosses[0].death_time, -1.0)
