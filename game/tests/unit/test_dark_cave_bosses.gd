extends TestCase
## Dark Cave encounters through shipped stage data and the seeded fixed-tick round boundary.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const TF := preload("res://tests/fixtures/tree_boss_fixtures.gd")
const DT := 1.0 / 60.0


func test_shipped_schedule_arrives_at_five_ten_and_fifteen_minutes_and_waits_for_rewards() -> void:
	var data := RF.quiet_data()
	var stage: Dictionary = data.stages.stages.sleepywood.duplicate(true)
	var entries: Array = DataRepo.stage_bosses(stage)
	assert_eq(entries.map(func(e: Dictionary) -> int: return int(e.mob_id)), [6300005, 8220009, 8130100])
	assert_eq(entries.map(func(e: Dictionary) -> int: return int(e.time)), [300, 600, 900])
	if entries.size() != 3:
		return
	assert_true(float(entries[2].hp_mult) > maxf(float(entries[0].hp_mult), float(entries[1].hp_mult)))
	assert_true(float(entries[2].dmg_mult) > maxf(float(entries[0].dmg_mult), float(entries[1].dmg_mult)))
	assert_true(float(entries[2].attack_dmg_mult) > maxf(float(entries[0].attack_dmg_mult), float(entries[1].attack_dmg_mult)))
	# Keep the actual schedule/rewards on a synthetic, quiet map so only the lifecycle is under test.
	stage.keyframes = data.stages.stages.quiet.keyframes
	stage.bursts = {}
	stage.elites = {}
	data.stages.stages.quiet = stage
	data.balance.player.skills = []
	var setup := RF.setup("quiet", 73, data)
	setup.map_img = RF.map_from_segments([{"x1": -2000, "y1": 0, "x2": 2000, "y2": 0}], [Vector2.ZERO])
	for id in [6300005, 8220009, 8130100, 7130100, 7130101]:
		setup.mob_imgs[id] = RF.mob_img(100100)
	var w := RunWorld.new(setup)
	w.god = true
	for index in 3:
		w.time = float(entries[index].time) - DT
		w.step(DT, MoveInput.new())
		assert_near(float(w.bosses.records[index].spawn_time), float(entries[index].time), DT)
		assert_eq(w.state, RunWorld.PLAYING, "time alone cannot clear")
		var slot := int(w.bosses.records[index].slot)
		w.hit_mob(slot, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false,
			"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
		w.step(DT, MoveInput.new())
		assert_ne(w.state, RunWorld.CLEARED, "even the final death must wait for reward choices")
		assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "each boss offers a reward")
		for tick in 120:
			RF.auto_choose(w)
			w.step(DT, MoveInput.new())
			if w.state in [RunWorld.PLAYING, RunWorld.CLEARED]:
				break
	assert_eq(w.state, RunWorld.CLEARED)
	assert_true(w.bosses.all_dead())
	assert_true(w.warnings.is_empty(), str(w.warnings))


func _attack_setup(type: int = 1) -> Dictionary:
	var setup := TF.setup(8130100, [], ["attack1"], 73)
	setup.data.balance.player.hp = 2000
	setup.data.stages.stages.quiet.maps[0].boss.attack_dmg_mult = 1.0
	# Invented damage, timings and geometry; canonical facts are checked only by the cache-gated test below.
	setup.mob_imgs[8130100].info.MADamage = 907.0
	setup.mob_imgs[8130100].info.PADamage = 211.0
	setup.mob_imgs[8130100].attack1.info = {"type": float(type), "magic": 1.0,
		"attackAfter": 1150.0, "effectAfter": 350.0, "elemAttr": "F",
		"range": {"sp": {"$v": [-37, -53]}, "r": 310.0},
		"hit": {"0": {"delay": 100}}, "effect": {"0": {"delay": 100}}}
	return setup


func _start(w: RunWorld) -> Dictionary:
	for tick in 180:
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "boss_attack" and event.phase == "start":
				return event
	fail("in-range Jr. Balrog begins its selected attack")
	return {}


func test_type_one_locks_an_admitted_target_and_hits_after_1150ms_even_after_leaving_range() -> void:
	var w := RunWorld.new(_attack_setup())
	var start := _start(w)
	if start.is_empty():
		return
	assert_near(float(start.impact_time) - float(start.time), 1.15, 1e-6)
	var hp := int(w.player_state.hp)
	RF.place_player(w, 1200.0, 0.0)
	for tick in 68:
		w.step(DT, MoveInput.new())
		assert_eq(int(w.player_state.hp), hp, "no damage before attackAfter")
	w.step(DT, MoveInput.new())
	var events := w.drain_events()
	var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
	assert_eq(hits.size(), 1, "targeted strike follows the admitted character, without a second range check")
	if hits.size() == 1:
		assert_eq(hits[0].source_kind, "attack")
		assert_eq(hits[0].mob_id, 8130100)
		assert_true(int(hits[0].damage) > 600, "magic flag uses synthetic MADamage907, not PADamage211")
	assert_eq(w.mob_projectiles.active_count(), 0, "type 1 has no travelling ball")
	var impacts := events.filter(func(e: Dictionary) -> bool: return e.type == "boss_attack" and e.phase == "hit")
	assert_eq(impacts.size(), 1, "hit art is emitted at the character")
	if impacts.size() == 1:
		assert_eq(impacts[0].pos, w.player.pos)
		assert_eq(impacts[0].effect, "Mob.wz/8130100.img/attack1/info/hit")


func test_type_one_needs_range_admission_but_does_not_require_ground_at_impact() -> void:
	var w := RunWorld.new(_attack_setup())
	# Spawn but never admit: put the character far away before the boss becomes fully visible.
	for tick in 30:
		w.step(DT, MoveInput.new())
	RF.place_player(w, 1200.0, 0.0)
	w.drain_events()
	for tick in 60:
		w.step(DT, MoveInput.new())
	assert_false(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "boss_attack"), "outside r cannot start")
	var slot := int(w.bosses.records[0].slot)
	RF.place_player(w, w.swarm.x[slot] - 180.0, 0.0)
	var start := _start(w)
	if start.is_empty():
		return
	for tick in 51:
		w.step(DT, MoveInput.new())
	w.step(DT, MoveInput.make(false, false, false, false, true, true))
	for tick in 17:
		w.step(DT, MoveInput.make(false, false, false, false, false, true))
	assert_true(w.player.fh < 0, "character is airborne at impact")
	assert_true(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "player_hit"), "targeted strike still lands")


func test_dead_boss_cancels_a_locked_type_one_hit() -> void:
	var setup := _attack_setup()
	RF.set_bosses(setup.data.stages.stages.quiet, DataRepo.stage_bosses(setup.data.stages.stages.quiet) + [{"time": 0.5, "mob_id": 2220000}])
	var w := RunWorld.new(setup)
	var start := _start(w)
	if start.is_empty():
		return
	w.hit_mob(int(start.mob), {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": true,
		"crit": 0.0, "crit_mult": 1.5, "skill": "energy_bolt"}, -1)
	w.drain_events()
	for tick in 80:
		w.step(DT, MoveInput.new())
	assert_false(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "boss_attack" and e.phase == "impact"))


func test_effect_after_impact_is_preserved_without_repeating_damage() -> void:
	var setup := _attack_setup(0)
	var info: Dictionary = setup.mob_imgs[8130100].attack1.info
	info.range = {"lt": {"$v": [-287, -145]}, "rb": {"$v": [119, 12]}}
	info.attackAfter = 450.0
	info.effectAfter = 650.0
	var w := RunWorld.new(setup)
	var start := _start(w)
	if start.is_empty():
		return
	for tick in 45:
		w.step(DT, MoveInput.new())
	var events := w.drain_events()
	var impacts := events.filter(func(e: Dictionary) -> bool: return e.type == "boss_attack" and e.phase == "impact")
	var effects := events.filter(func(e: Dictionary) -> bool: return e.type == "boss_attack" and e.phase == "effect")
	assert_eq(impacts.size(), 1)
	assert_eq(effects.size(), 1, "a later effect survives the earlier damage impact")
	if effects.size() == 1:
		assert_near(float(effects[0].time) - float(start.time), 0.65, DT)


func test_type_two_without_bullet_speed_launches_a_finite_magic_ball_and_hits() -> void:
	var setup := _attack_setup(2)
	setup.mob_imgs[8130100].attack1.info.attackAfter = 450.0
	setup.mob_imgs[8130100].attack1.info.effectAfter = 150.0
	var w := RunWorld.new(setup)
	var start := _start(w)
	if start.is_empty():
		return
	for tick in 100:
		w.step(DT, MoveInput.new())
	var events := w.drain_events()
	var launched := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_projectile_spawned")
	assert_eq(launched.size(), 1)
	if launched.size() == 1:
		assert_near(float(launched[0].speed), 320.0, 1e-6, "tier C missing-speed fallback, not a stationary immortal ball")
	var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit" and e.source_kind == "projectile")
	assert_eq(hits.size(), 1, "swept body collision from the synthetic muzzle")
	if hits.size() == 1:
		assert_true(int(hits[0].damage) > 600, "ball uses synthetic magic907, not physical211")
	assert_eq(w.mob_projectiles.active_count(), 0, "ball is consumed")


func test_real_bosses_keep_canonical_attacks_elements_and_scaled_encounter_hp() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var data := DataRepo.load_all()
	var expected := [[6300005, 35000, [0], [1050]], [8220009, 110000, [0, 0, 0], [1520, 2000, 2100]],
		[8130100, 50000, [1, 2, 0], [1300, 400, 400]]]
	var effective_hp: Array[int] = []
	for index in expected.size():
		var row: Array = expected[index]
		var id := int(row[0])
		var img := lib.mob_root(id)
		assert_eq(int(img.info.maxHP), row[1])
		assert_true((img.info.get("skill", {}) as Dictionary).is_empty(), "these bosses have no v83 mob skills")
		var entry: Dictionary = data.stages.stages.sleepywood.maps[index].boss
		assert_eq(entry.attacks.size(), row[2].size(), "every canonical attack is scheduled")
		effective_hp.append(roundi(float(row[1]) * float(entry.hp_mult)))
		for attack_index in entry.attacks.size():
			var attack: String = entry.attacks[attack_index]
			var info: Dictionary = img[attack].info
			assert_eq(int(info.type), row[2][attack_index])
			assert_eq(int(info.attackAfter), row[3][attack_index])
			assert_false(lib.anim("Mob.wz/%07d.img/%s" % [id, attack]).is_empty(), "canonical windup art")
	# tier C: #77 C24 encounter HP; canonical WZ HP/attack/element checks remain above and below.
	assert_eq(effective_hp, [45500, 88000, 300000], "Jr. Balrog has greatest effective HP despite Snack Bar's canonical HP")
	assert_eq(lib.mob_root(8130100).info.elemAttr, "S1H3", "canonical poison immunity and holy weakness")
	assert_eq(int(lib.mob_root(8220009).attack2.info.magic), 1)
	assert_eq(int(lib.mob_root(8130100).attack1.info.magic), 1)
	assert_true(lib.missing.is_empty())
	lib.free()
