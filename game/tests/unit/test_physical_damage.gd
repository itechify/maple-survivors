extends TestCase
## Physical combat's public formula and hit seams, with worked v83 examples and seeded synthetic runs.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")
const DT := 1.0 / 60.0


func test_each_weapon_family_uses_its_stats_and_swing_or_stab_multiplier() -> void:
	# STR100 DEX50 LUK200, PAD100, mastery10%; literals worked from v83-facts §5.
	var cases := [
		[1302000, "swing", 86.0, 450.0], [1302000, "stab", 86.0, 450.0],
		[1312004, "swing", 89.6, 490.0], [1312004, "stab", 78.8, 370.0],
		[1322005, "swing", 89.6, 490.0], [1322005, "stab", 78.8, 370.0],
		[1402000, "swing", 91.4, 510.0], [1402000, "stab", 91.4, 510.0],
		[1412000, "swing", 93.2, 530.0], [1412000, "stab", 80.6, 390.0],
		[1422000, "swing", 93.2, 530.0], [1422000, "stab", 80.6, 390.0],
		[1432000, "swing", 77.0, 350.0], [1432000, "stab", 95.0, 550.0],
		[1442000, "swing", 95.0, 550.0], [1442000, "stab", 77.0, 350.0],
		[1452000, "shoot", 115.3, 270.0], [1462000, "shoot", 116.2, 280.0],
		[1472000, "shoot", 214.8, 870.0], [1332000, "stab", 214.8, 870.0],
		[1482000, "swing", 93.2, 530.0], [1492000, "shoot", 116.2, 280.0],
		[1372005, "swing", 89.6, 490.0], [1372005, "stab", 78.8, 370.0],
		[1382000, "swing", 89.6, 490.0], [1382000, "stab", 78.8, 370.0],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 153
	for c: Array in cases:
		var bounds := CombatMath.physical_damage_range(100, 50, 200, 100, c[0], c[1], 400)
		assert_near(bounds.x, c[2], 0.0001, str(c))
		assert_near(bounds.y, c[3], 0.0001, str(c))
		assert_between(CombatMath.roll_range(bounds, rng), c[2] - 0.0001, c[3] + 0.0001)
	var other_dagger := CombatMath.physical_damage_range(100, 50, 200, 100, 1332000, "stab", 200)
	assert_eq(other_dagger, Vector2(86, 450), "non-Thief daggers use STR/DEX and 4.0")


func test_physical_loadout_keeps_skill_percent_separate_and_copies_versioned_caster_inputs() -> void:
	var book := SkillBook.from_data({"skills": {"strike": {"skill_id": 1001004, "book": "100", "kind": "instant",
		"damage": "physical", "action": "stabT1", "ranks": [1]}}},
		{"100": {"skill": {"1001004": {"level": {"1": {"damage": 150, "attackCount": 2}}}}}})
	var loadout := Loadout.new(book)
	loadout.add_skill("strike")
	var fields := {"str_stat": 100.0, "dex_stat": 50.0, "luk_stat": 200.0, "watk": 100.0, "acc": 40.0,
		"weapon_id": 1432000, "weapon_family": "spear", "job_id": 100, "mastery": 0.6,
		"crit_bonus": 0.2, "crit_damage_bonus": 100.0}
	for field: String in fields:
		var before := loadout.version
		loadout.set(field, fields[field])
		assert_true(loadout.version > before, field + " invalidates resolved stats")
		before = loadout.version
		loadout.set(field, fields[field])
		assert_eq(loadout.version, before, "the same " + field + " does not invalidate stats")
	loadout.add_player_mod("damage", "mul", 2.0)
	var stats := loadout.stats("strike")
	assert_eq(stats.damage_type, "physical")
	assert_eq(stats.defense, "pdd")
	assert_eq(stats.attack_kind, "stab")
	assert_false(stats.magic)
	assert_eq(stats.attack_count, 2)
	assert_eq(stats.damage_pct, 1.5)
	assert_eq(stats.damage_min, 640.0, "mastery60% bounds x2 survivor mult, before skill150% or defence")
	assert_eq(stats.damage_max, 1100.0)
	var copied := loadout.clone()
	for field: String in fields:
		assert_eq(copied.get(field), fields[field], "clone preserves " + field)
	assert_eq(copied.stats("strike"), stats)
	copied.str_stat = 200
	assert_eq(loadout.str_stat, 100.0)


func test_mastery_and_lucky_seven_override_and_unchanged_creation_weapon_bounds() -> void:
	assert_eq(CombatMath.physical_damage_range(100, 50, 200, 100, 1302000, "swing", 100), Vector2(86, 450))
	assert_eq(CombatMath.physical_damage_range(100, 50, 200, 100, 1302000, "swing", 100,
		CombatMath.mastery_fraction(10)), Vector2(266, 450))
	var lucky := {"primary": "luk", "max_mult": 5.0, "min_mult": 2.5, "secondary": "", "ignore_mastery": true}
	for mastery: float in [0.1, 0.6]:
		assert_eq(CombatMath.physical_damage_range(100, 50, 200, 100, 1472000, "shoot", 410, mastery, lucky),
			Vector2(500, 1000), "Lucky Seven ignores mastery and secondary stats")
	# The original creation-weapon examples, STR12 DEX4 PAD17, before crit rolls.
	for c: Array in [[1302000, "swingO1", 1.4144, 8.84], [1302000, "stabO1", 1.4144, 8.84],
			[1312004, "swingO1", 1.48784, 9.656], [1312004, "stabO1", 1.26752, 7.208],
			[1322005, "swingO1", 1.48784, 9.656], [1322005, "stabO1", 1.26752, 7.208],
			[0, "swingO1", 1.0, 1.0], [0, "stabO1", 1.0, 1.0]]:
		var bounds := CombatMath.basic_damage_range(12, 4, 0 if c[0] == 0 else 17, c[0], c[1], 1, 1, 0)
		assert_near(bounds.x, c[2], 0.00001)
		assert_near(bounds.y, c[3], 0.00001)
	for c: Array in [["swingO3", "swing"], ["stabT2", "stab"], ["shoot1", "shoot"], ["throw1", "shoot"], ["alert2", ""]]:
		assert_eq(WeaponInfo.attack_kind(c[0]), c[1])


func test_instant_hits_choose_live_pdd_or_mdd_and_apply_skill_percent_after_defence() -> void:
	var world := RF.quiet_world(400, 153)
	var mob := RF.put_mob(world, 1110100, 550, 190, 100)
	var kind: MobKind = world.mob_kinds[world.swarm.kind[mob]]
	kind.level = 11
	kind.pdd = 40
	kind.mdd = 150
	var control := RandomNumberGenerator.new()
	control.state = world.rng.state
	var expected := roundi(control.randf_range(66, 70) * 2.0)
	world.drain_events()
	world.hit_mob(mob, {"skill": "fixture", "damage_type": "physical", "magic": false,
		"damage_min": 100.0, "damage_max": 100.0, "damage_pct": 2.0, "player_level": 1,
		"crit": 0.0, "crit_mult": 1.5}, -1)
	assert_eq(_hits(world)[0].damage, expected, "level gap10 and PDD40 act on bounds BEFORE skill200%")
	for c: Array in [["magic", true, 50], ["fixed", false, 100]]:
		world.hit_mob(mob, {"skill": "fixture", "damage_type": c[0], "magic": c[1],
			"damage_min": 100.0, "damage_max": 100.0, "crit": 0.0, "crit_mult": 1.5}, -1)
		assert_eq(_hits(world)[0].damage, c[2], str(c))


func test_physical_projectiles_use_target_level_and_pdd_at_impact() -> void:
	var world := RF.quiet_world(400, 153)
	world.loadout.order.clear()
	var mob := RF.put_mob(world, 1110100, 550, 190, 100)
	var kind: MobKind = world.mob_kinds[world.swarm.kind[mob]]
	kind.move_speed = 0
	kind.level = 11
	kind.pdd = 0
	kind.mdd = 150
	world.projectiles.spawn({"x": 500.0, "y": world.mob_center(mob).y, "vx": 400.0, "range": 500.0,
		"damage_type": "physical", "dmg_min": 100.0, "dmg_max": 100.0, "damage_pct": 2.0,
		"player_level": 1, "crit": 0.0, "skill": "fixture"})
	kind.pdd = 40 # Changed after launch: the impact must not retain the original defence.
	var hits := []
	for tick in 20:
		world.step(DT, MoveInput.new())
		hits.append_array(_hits(world))
	assert_eq(hits.size(), 1)
	if hits.size() == 1:
		assert_between(hits[0].damage, 132, 140, "live PDD40 and mobLv11, then skill200%")


func _hits(world: RunWorld) -> Array:
	return world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func test_job_accuracy_equipment_and_buffs_feed_crit_for_every_damage_type() -> void:
	var tree := JobTree.from_data(DataRepo.load_all().jobs, {})
	for c: Array in [[0, 90.0], [100, 90.0], [112, 90.0], [200, 90.0], [230, 90.0],
			[300, 66.0], [320, 66.0], [400, 66.0], [420, 66.0], [500, 66.0], [520, 66.0], [510, 96.0]]:
		assert_near(CombatMath.base_accuracy(100, 20, tree.lineage(c[0])), c[1], 0.00001, str(c))
	var data := RF.quiet_data()
	data.balance.crit = {"chance": 0.05, "per_acc": 0.001, "mult": 1.5}
	data.balance.player.stats.luk = 5
	# A 20% crit passive (#161: RunWorld._refresh_caster assembles crit_bonus from owned passives, so it is learned).
	data.skills.skills["crit_fixture"] = {"skill_id": 9991001, "book": "999", "kind": "passive", "slot": "passive",
		"damage": "none", "ranks": [1], "passive": {"stat": "crit_chance", "per_level": 20.0}}
	var setup := RF.setup("quiet", 153, data)
	setup.equipment_info[1302000].incACC = 7
	var world := RunWorld.new(setup)
	assert_near(world.player_state.acc, 13.5, 0.00001, "DEX5 LUK5 base6.5 plus equipment7")
	assert_near(world.loadout.acc, 13.5, 0.00001)
	world.learn_skill("crit_fixture")
	assert_near(world.loadout.crit_bonus, 0.2, 0.00001)
	for key: String in ["three_snails", "energy_bolt"]:
		assert_near(world.loadout.stats(key).crit, 0.2635, 0.00001, "base + ACC coefficient + passive, " + key)
	world.start_buff("fixture", {"duration": 0.05, "buff_effects": {"acc": 8, "watk": 10}, "skill_id": 0, "level": 1,
		"icon": "", "buff_stat": "acc", "buff_value": 8.0, "pulse_interval": 0.0})
	assert_near(world.player_state.acc, 21.5, 0.00001)
	assert_near(world.loadout.stats("three_snails").crit, 0.2715, 0.00001, "Bless accuracy raises crit immediately")
	assert_eq(world.weapon_attack(), 27.0, "equipment PAD17 plus buff10")
	assert_eq(world.weapon_attack(true), 27.0, "ranged hook returns the same PAD until #155 adds ammo")
	assert_eq(world.loadout.watk, 27.0)
	for tick in 4:
		world.step(DT, MoveInput.new())
	assert_near(world.loadout.acc, 13.5, 0.00001, "buff expiry removes its crit contribution before casting")
	assert_eq(world.loadout.watk, 17.0, "W.Att buff expiry refreshes physical bounds too")


func test_basic_attack_can_crit_on_stream_five_without_consuming_combat_rng() -> void:
	var world := BF.world(153)
	world.loadout.crit_bonus = 1.0
	var mob := RF.put_mob(world, 100100, 450, 190, 1000)
	world.mob_kinds[world.swarm.kind[mob]].move_speed = 0
	var combat_before := world.rng.state
	var hits := []
	for tick in 29:
		world.step(DT, MoveInput.new())
		hits.append_array(_hits(world))
	assert_eq(hits.size(), 1)
	if hits.size() == 1:
		assert_true(hits[0].crit, "Beginner's basic attack can crit")
	assert_eq(world.rng.state, combat_before, "basic damage and crit rolls both stay on stream5")


func test_passive_crit_adds_skill_percent_and_default_crit_multiplies_on_all_damage_types() -> void:
	var world := RF.quiet_world(400, 153)
	var mob := RF.put_mob(world, 100100, 550, 190, 10000)
	for dtype: String in ["physical", "magic", "fixed"]:
		for bonus: float in [0.0, 100.0]:
			world.hit_mob(mob, {"skill": "fixture", "damage_type": dtype, "magic": dtype == "magic",
				"damage_min": 100.0, "damage_max": 100.0, "damage_pct": 1.5,
				"crit": 1.0, "crit_mult": 1.5, "crit_damage_bonus": bonus}, -1)
			var hit: Dictionary = _hits(world)[0]
			assert_true(hit.crit, dtype + " can crit, including fixed Three Snails")
			assert_eq(hit.damage, 225 if bonus == 0 else 250, "passive100 adds to skill150%, otherwise x1.5")


func test_skill_runner_resolves_physical_lines_and_projectiles_from_canonical_damage() -> void:
	for kind: String in ["instant", "projectile"]:
		var data := RF.quiet_data()
		data.balance.player.skills = ["fixture"]
		data.balance.crit.per_acc = 0.0
		data.balance.player.stats = {"str": 100, "dex": 50, "int": 4, "luk": 200}
		data.skills.skills.fixture = {"skill_id": 1001004, "book": "100", "kind": kind,
			"damage": "physical", "action": "swingO1", "ranks": [1], "range": 400, "speed": 600,
			"cooldown": 10, "count": 1}
		var setup := RF.setup("quiet", 153, data)
		setup.equipment_info[1302000].incPAD = 100
		setup.skill_imgs["100"] = {"skill": {"1001004": {"level": {"1": {"damage": 200, "attackCount": 2}}}}}
		var world := RunWorld.new(setup)
		world.god = true
		RF.place_player(world, 400)
		var mob := RF.put_mob(world, 100100, 500, 190, 10000)
		world.mob_kinds[world.swarm.kind[mob]].move_speed = 0
		var hits := []
		for tick in 20:
			world.step(DT, MoveInput.new())
			hits.append_array(_hits(world))
		assert_eq(hits.size(), 2 if kind == "instant" else 1, "canonical attackCount instant lines / projectile count")
		for hit: Dictionary in hits:
			assert_between(hit.damage, 172, 900, "STR100 DEX50 PAD100 Sword, then canonical200%")
		# Lucky Seven's override must also be read through Loadout, not only the formula helper.
		world.book.defs.fixture.physical_formula = {"primary": "luk", "max_mult": 5.0, "min_mult": 2.5,
			"secondary": "", "ignore_mastery": true}
		world.loadout.mastery = 0.6
		var resolved := world.loadout.stats("fixture")
		assert_eq(resolved.damage_min, 500.0)
		assert_eq(resolved.damage_max, 1000.0)


func test_live_defence_buff_reduces_instant_and_airborne_physical_hits() -> void:
	const MF := preload("res://tests/fixtures/mano_fixtures.gd")
	for projectile: bool in [false, true]:
		var setup := MF.setup([112], 153)
		setup.mob_skill_img["112"].level["1"].interval = 0.05
		var world := RunWorld.new(setup)
		world.god = true
		RF.place_player(world, 400)
		for tick in 120: # Let the spawned boss finish fading in before its defence skill can act.
			world.step(DT, MoveInput.new())
		var mob := int(world.bosses.records[0].slot)
		assert_eq(world.mob_defense(mob, false), 105.0, "canonical20 plus live85")
		world.drain_events()
		if projectile:
			world.projectiles.spawn({"x": world.mob_center(mob).x, "y": world.mob_center(mob).y, "vx": 0.0,
				"range": 100, "damage_type": "physical", "dmg_min": 100.0, "dmg_max": 100.0,
				"player_level": 20, "damage_pct": 2.0, "skill": "fixture"})
			world.step(DT, MoveInput.new())
		else:
			world.hit_mob(mob, {"skill": "fixture", "damage_type": "physical", "magic": false,
				"damage_min": 100.0, "damage_max": 100.0, "player_level": 20, "damage_pct": 2.0,
				"crit": 0.0, "crit_mult": 1.5}, -1)
		var hits := _hits(world)
		assert_eq(hits.size(), 1)
		if hits.size() == 1:
			assert_between(hits[0].damage, 74, 95, "live105 PDD reduces to37..47.5, then skill200%")
		assert_eq(world.mob_kinds[world.swarm.kind[mob]].pdd, 20, "canonical PDD stays unchanged")
