extends TestCase
## Opening strength is survivor data layered over canonical kinds, through seeded RunWorld spawns and hits.

const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world() -> RunWorld:
	var setup := MF.setup(1)
	setup.data.stages.stages.quiet["opening_ramp"] = {
		"seconds": 120, "hp": {"start": 0.2, "end": 1.0}, "damage": {"start": 0.1, "end": 1.0}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


func test_spawn_hp_ramps_on_round_clock_without_mutating_canonical_input() -> void:
	var w := _world()
	var k := int(w.kind_of_id[MF.TAURO])
	var canonical: int = w.mob_kinds[k].max_hp
	var a := w.spawn_mob(k, Vector2(750, 200), 0, 2.0, false)
	assert_eq(w.swarm.max_hp[a], 400000, "opening x0.2 stacks with existing x2 spawn scale")
	w.god = true
	for tick in 3600:
		w.step(DT, MoveInput.new())
	var b := w.spawn_mob(k, Vector2(750, 200), 0, 2.0, false)
	assert_eq(w.swarm.max_hp[b], 1200000, "midpoint x0.6")
	for tick in 3600:
		w.step(DT, MoveInput.new())
	var c := w.spawn_mob(k, Vector2(750, 200), 0, 2.0, false)
	assert_eq(w.swarm.max_hp[c], 2000000, "end x1")
	assert_eq(w.swarm.max_hp[a], 400000, "living monsters retain their spawn HP")
	assert_eq(w.mob_kinds[k].max_hp, canonical, "canonical kind is unchanged")
	assert_eq(int(MF.tauro_img().info.maxHP), canonical)


func test_touch_and_attack_n_damage_stack_with_source_scale_at_all_ramp_points() -> void:
	for seconds: float in [0.0, 60.0, 120.0, 180.0]:
		for attackN: bool in [false, true]:
			var w := _world()
			var baseline := _world()
			baseline.stage.erase("opening_ramp")
			w.time = seconds
			baseline.time = seconds
			var source := {"accuracy": 0, "dmg_mult": 0.5,
				"source_kind": "mob_attack" if attackN else "touch"}
			var full := baseline.take_hit(320.0, attackN, "", Vector2.ZERO, source)
			var scaled := w.take_hit(320.0, attackN, "", Vector2.ZERO, source)
			var expected := 0.1 if seconds == 0.0 else (0.55 if seconds == 60.0 else 1.0)
			assert_between(scaled, maxi(1, roundi(full * expected) - 1), roundi(full * expected) + 1,
				"same seed, same roll, after-defense opening damage at %s" % seconds)
			assert_eq(w.mob_kinds[int(w.kind_of_id[MF.TAURO])].mad, 320, "canonical attack unchanged")


func test_ordinary_attack_n_impact_uses_opening_damage() -> void:
	var w := _world()
	RF.put_mob(w, MF.TAURO, 600)
	for tick in 600:
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "player_hit" and event.source_kind == "mob_attack":
				assert_between(event.damage, 10, 25, "canonical MAD 320 x ordinary 0.5 x early opening ~0.1")
				return
	assert_true(false, "attackN must actually land")


func test_boss_captures_opening_scales_at_spawn_and_legacy_stages_stay_neutral() -> void:
	var config := MF.setup(1)
	config.data.stages.stages.quiet["opening_ramp"] = {
		"seconds": 120, "hp": {"start": 0.2, "end": 1.0}, "damage": {"start": 0.1, "end": 1.0}}
	RF.set_bosses(config.data.stages.stages.quiet, [{"time": 0, "mob_id": MF.TAURO,
		"hp_mult": 2.0, "dmg_mult": 0.8, "attack_dmg_mult": 0.5}])
	var originals: Dictionary = config.mob_imgs.duplicate(true)
	var w := RunWorld.new(config)
	RF.place_player(w, 400)
	w.god = true
	for tick in 240:
		w.step(DT, MoveInput.new())
	var record: Dictionary = w.bosses.records[0]
	assert_true(int(record.slot) >= 0, "boss really spawned")
	if int(record.slot) < 0:
		return
	assert_between(w.swarm.max_hp[int(record.slot)], 400000, 450000, "boss HP includes opening scale")
	var damage := w.bosses.damage_multiplier(0)
	assert_between(damage, 0.08, 0.10, "touch captures spawn-time damage")
	assert_between(float(w.bosses.entries[0].attack_dmg_mult), 0.05, 0.065, "attackN also captures it")
	w.time = 180.0
	assert_near(w.bosses.damage_multiplier(0), damage, 0.00001, "boss scaling freezes at arrival")
	assert_eq(config.mob_imgs, originals, "canonical input remains byte-for-byte equivalent")
	assert_near(float(config.data.stages.stages.quiet.maps[0].boss.dmg_mult), 0.8, 0.00001,
		"stage's original boss entry is detached")
	w.stage.erase("opening_ramp")
	assert_near(w.opening_multiplier("hp"), 1.0, 0.00001)
	assert_near(w.hit_source_multiplier({}), 1.0, 0.00001)


func test_touch_collision_uses_opening_damage() -> void:
	var w := _world()
	RF.put_mob(w, MF.BOOGIE, 410)
	for tick in 120:
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "player_hit":
				assert_eq(event.source_kind, "touch")
				assert_between(event.damage, 4, 6, "canonical PAD 50 x early opening ~0.1")
				return
	assert_true(false, "contact collision must land")


func test_backloaded_ramp_still_reaches_full_strength_by_its_end() -> void:
	var w := _world()
	w.stage.opening_ramp["power"] = 3.0
	w.time = 60.0
	assert_near(w.opening_multiplier("hp"), 0.3, 0.00001, "cubic progress is 1/8 at halfway")
	w.time = 120.0
	assert_near(w.opening_multiplier("hp"), 1.0, 0.00001)


func test_map_override_uses_round_clock_and_scales_spawn_hp() -> void:
	var w := _world()
	w.stage.maps.append({"map_id": 1, "boss": {}, "opening_ramp": {
		"seconds": 120, "hp": {"start": 0.6, "end": 1.0}, "damage": {"start": 0.4, "end": 1.0}}})
	w.map_index = 1
	w.time = 60.0
	var slot := w.spawn_mob(int(w.kind_of_id[MF.TAURO]), Vector2(750, 200), 0, 1.0, false)
	assert_eq(w.swarm.max_hp[slot], 800000, "map override uses round midpoint, not time since entry")
	assert_near(w.hit_source_multiplier({}), 0.7, 0.00001)
