extends TestCase
## Boss schedules, touch-only encounters and clear rules through fixed-tick seeded run simulation.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BALANCE_RUN := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0


func _setup(times: Array = [3.5]) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var stage: Dictionary = data.stages.stages.quiet
	stage.duration = 5.0
	stage.bosses = []
	for at: float in times:
		stage.bosses.append({"time": at, "mob_id": 2220000, "hp_mult": 2.0, "dmg_mult": 1.75})
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


func test_boss_touch_uses_explicit_multiplier_and_hit_source_identity() -> void:
	var examples: Array = DataRepo.load_all().stages.stages.henesys_hg1.bosses
	var attacks := {2220000: 90.0, 6130101: 200.0, 9400205: 450.0}
	for entry: Dictionary in examples:
		var setup := _setup([0.5])
		setup.data.stages.stages.quiet.bosses = [entry.duplicate(true)]
		setup.data.stages.stages.quiet.bosses[0].time = 0.5
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
		assert_between(float(hit.damage) / float(hit.max_hp), 0.4, 0.5)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1903
		for roll in 1000:
			var damage := CombatMath.monster_hit(attacks[id], false, "", {"pdd": float(entry.typical_pdd)},
				rng, float(entry.dmg_mult))
			assert_between(float(damage) / float(entry.typical_hp), 0.4, 0.5, "all seeded hits stay in the initial band")


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
