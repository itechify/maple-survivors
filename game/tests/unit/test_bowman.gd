extends TestCase
## Bowman first-job contract (#199): seeded public advancement, combat, card and snapshot boundaries.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const WEAPONS := {"bow": 1452051, "crossbow": 1462001}


func _world(free := 24) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var setup := RF.with_basic_attack(RF.setup("quiet", 199, data))
	setup.equipment_info.merge({1452051: {"incPAD": 28, "attackSpeed": 6, "tuc": 7},
		1462001: {"incPAD": 29, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	if free < 24:
		var character := RunWorld.new(setup).character_snapshot()
		for i in 24 - free:
			character.equipment.inventory.append(Equipment.create(1040002, {"incPDD": 3, "tuc": 7}))
		setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


func _open(w: RunWorld) -> void:
	w.progression.level = 9
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB)


func _inventory(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func test_bowman_at_ten_grants_pools_bow_and_spare_crossbow_and_snapshot() -> void:
	var w := _world()
	_open(w)
	var options := w.pending_jobs.filter(func(o: Dictionary) -> bool: return int(o.job_id) == 300)
	assert_eq(options.size(), 1)
	if options.is_empty():
		return
	assert_eq(options[0].name, "Bowman")
	assert_true(options[0].available)
	assert_false(w.jobs.advancements(0, 9).filter(func(o: Dictionary) -> bool: return int(o.job_id) == 300)[0].available)
	var hp: int = w.player_state.max_hp
	var mp: int = w.player_state.max_mp
	assert_true(w.apply_job(300, "bow"))
	assert_eq(w.weapon_id(), 1452051)
	assert_eq(_inventory(w), [1302000, 1462001])
	assert_eq(w.player_state.max_hp, hp + 125)
	assert_eq(w.player_state.max_mp, mp + 37)
	BotInput.auto_choose(w, false, 300, "bow")
	var snapshot := w.character_snapshot()
	assert_eq(CharacterSnapshot.validation_error(snapshot), "")
	var setup := w.setup.duplicate(true)
	setup.character = JSON.parse_string(JSON.stringify(snapshot))
	assert_eq(RunWorld.new(setup).character_snapshot(), snapshot)


func test_full_equip_tab_spills_extra_crossbow_as_a_pickup() -> void:
	var w := _world(0)
	_open(w)
	w.drain_events()
	assert_true(w.apply_job(300, "bow"))
	var drops := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
	assert_eq(drops.map(func(e: Dictionary) -> int: return int(e.item_id)), [1302000, 1462001])
	assert_true(drops.all(func(e: Dictionary) -> bool: return e.pos == w.player.pos and e.kind == "equip"))
	assert_eq(w.equipment.inventory.size(), 24)


func test_seeded_bot_meets_both_advancement_weapons_at_thirty_and_grows_22_15() -> void:
	var w := _world()
	w.god = true
	for level in range(2, 32):
		var hp: int = w.player_state.max_hp
		var mp: int = w.player_state.max_mp
		w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		for tick in 120:
			w.step(DT, MoveInput.new())
			BotInput.auto_choose(w, false, 300, "bow")
			if w.progression.level == level:
				break
		assert_eq(w.progression.level, level)
		if level > 10:
			assert_eq(w.player_state.max_hp - hp, 22)
			assert_eq(w.player_state.max_mp - mp, 15)
		if level == 30:
			for req: Dictionary in [{"reqLevel": 30, "reqJob": 4, "reqSTR": 35, "reqDEX": 95},
					{"reqLevel": 28, "reqJob": 4, "reqSTR": 28, "reqDEX": 80}]:
				assert_eq(Equipment.requirement_error(req, w.player_state), "")
			assert_eq(w.player_state.str, 35)
	var weights := BotShop.weights_for(w.balance, 300, w.jobs)
	assert_true(float(weights.incDEX) > float(weights.incSTR))


func test_forced_bowman_is_valid_for_a_tool_run() -> void:
	var data := DataRepo.load_all()
	var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys_hg1", "--job=300"]))
	assert_eq(parsed.options.job, 300)
	assert_eq(SceneFlow.forced_job_error(parsed.options, data), "")
	assert_eq(RunLauncher.options_from_args({"job": "300"}).job, 300)


func _combat(family: String, key := "", rank_value := 1) -> RunWorld:
	var w := _world()
	w.change_job(300, "bow")
	if family == "crossbow":
		assert_eq(w.equip_item(_inventory(w).find(1462001)), "")
	elif family == "sword":
		assert_eq(w.equip_item(_inventory(w).find(1302000)), "")
	w.heal_fraction("mp", 1.0)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
	w.player.facing = 1
	if key != "":
		assert_true(w.learn_skill(key))
		w.loadout.set_rank(key, rank_value)
		w.refresh_player_stats()
	w.drain_events()
	return w


func _targets(w: RunWorld, offsets: Array) -> void:
	for dx: float in offsets:
		RF.put_mob(w, 1110100, w.player.pos.x + dx, 190, 10000)
	w.drain_events()
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)


func test_arrow_attacks_use_canonical_cost_damage_count_and_current_ammo() -> void:
	for family: String in ["bow", "crossbow", "sword"]:
		for key: String in ["arrow_blow", "bow_double_shot"]:
			for rank_value in [1, 20]:
				var w := _combat(family, key, rank_value)
				var st := w.loadout.stats(key)
				var double := key == "bow_double_shot"
				assert_eq(st.count, 2 if double else 1)
				assert_near(st.damage_pct, (0.92 if rank_value == 1 else 1.30) if double else (1.90 if rank_value == 1 else 2.60))
				var mp: int = w.player_state.mp
				_targets(w, [80.0, 140.0])
				# Separate shot lines: collinear arrows can both collide with the nearer monster.
				w.swarm.y[1] -= 65.0
				w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
				w.runner.step(DT, w)
				var can := family != "sword"
				assert_eq(w.projectiles.active_count(), (2 if double else 1) if can else 0)
				assert_eq(w.player_state.mp, mp - (((10 if rank_value == 1 else 16) if double else (7 if rank_value == 1 else 14)) if can else 0))
				if can:
					for i in w.projectiles.capacity():
						if w.projectiles.active[i] != 0:
							assert_eq(w.projectiles.visual[i], w.visual_index(Ammo.bullet_path(w.ammo_id())))
					for tick in 30:
						w.step(DT, MoveInput.new())
					var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)
					assert_eq(hits.size(), 2 if double else 1)
					if double:
						assert_true(hits[0].pos.x != hits[1].pos.x, "two arrows split over two targets")
	for key: String in ["arrow_blow", "bow_double_shot"]:
		var w := _combat("bow", key)
		_targets(w, [80.0])
		w.spend_mp(int(w.player_state.mp))
		w.runner.step(DT, w)
		assert_eq(w.projectiles.active_count(), 0, "unaffordable attack waits")
		assert_eq(w.player_state.mp, 0)


func test_eye_extends_basic_and_bow_skill_reach_and_projectile_lifetime() -> void:
	for family: String in ["bow", "crossbow"]:
		var w := _combat(family, "arrow_blow")
		var reach_before := w.basic.reach(w)
		var skill_before: float = w.loadout.stats("arrow_blow").range
		_targets(w, [380.0])
		w.runner.step(DT, w)
		w.basic.step(DT, w)
		assert_eq(w.projectiles.active_count(), 0)
		assert_eq(w.basic.last_action, "")
		assert_true(w.learn_skill("eye_of_amazon"))
		w.loadout.set_rank("eye_of_amazon", 8)
		w.refresh_player_stats()
		assert_near(w.basic.reach(w), reach_before + 120)
		assert_near(w.loadout.stats("arrow_blow").range, skill_before + 120)
		w.runner.step(DT, w)
		assert_eq(w.projectiles.active_count(), 1, "formerly distant target now casts")
		for tick in 50:
			w.step(DT, MoveInput.new())
		assert_true(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "arrow_blow"))
		var basic := _combat(family, "eye_of_amazon", 8)
		_targets(basic, [380.0])
		for tick in 60:
			basic.step(DT, MoveInput.new())
		assert_true(basic.basic.shots > 0)
		assert_true(basic.drain_events().any(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "basic_attack"))


func test_eye_and_critical_shot_switch_off_with_melee_and_leave_magic_ranges_unchanged() -> void:
	var w := _combat("bow", "eye_of_amazon", 8)
	var magic: float = w.loadout.stats("energy_bolt").range
	assert_true(w.learn_skill("critical_shot"))
	w.loadout.set_rank("critical_shot", 20)
	w.refresh_player_stats()
	assert_near(w.loadout.crit_bonus, 0.4)
	assert_near(w.loadout.crit_damage_bonus, 100.0)
	assert_eq(w.loadout.stats("energy_bolt").range, magic)
	assert_eq(w.equip_item(_inventory(w).find(1302000)), "")
	var before := w.basic.reach(w)
	w.loadout.set_rank("eye_of_amazon", 1)
	w.refresh_player_stats()
	assert_eq(w.basic.reach(w), before)
	assert_eq(w.loadout.passive_total("range"), 0.0)
	assert_eq(w.loadout.crit_bonus, 0.0)
	assert_eq(w.loadout.crit_damage_bonus, 0.0)
	assert_eq(w.equip_item(_inventory(w).find(1452051)), "")
	assert_eq(w.loadout.passive_total("range"), 15.0, "rank changes and swapping back update reach immediately")
	assert_near(w.basic.reach(w), 315)


func test_blessing_accuracy_and_focus_recast_with_string_acc_and_canonical_cost() -> void:
	var w := _combat("bow", "blessing_of_amazon", 16)
	assert_near(w.loadout.passive_total("acc"), 16)
	var acc: float = w.player_state.acc
	var avoid: float = w.player_state.avoid
	assert_true(w.learn_skill("focus"))
	w.loadout.set_rank("focus", 20)
	w.refresh_player_stats()
	var mp: int = w.player_state.mp
	w.runner.step(DT, w)
	assert_eq(w.player_state.mp, mp - 16)
	assert_near(w.player_state.acc, acc + 20)
	assert_near(w.player_state.avoid, avoid + 20)
	assert_true(w.buffs.has("focus"))
	w.runner.step(DT, w)
	assert_eq(w.player_state.mp, mp - 16, "no recast while active")
	# Fixed tick expiration with no targets or incoming damage.
	w.god = true
	for tick in 18002:
		w.step(DT, MoveInput.new())
	assert_true(w.runner.casts >= 2, "Focus recasts after its canonical 300 seconds")
	assert_near(w.player_state.acc, acc + 20, 0.001, "buff refresh never stacks")


func test_bowman_cards_follow_held_weapon_and_each_attack_can_hit_more_mobs() -> void:
	var w := _world()
	_open(w)
	w.apply_job(300, "bow")
	var offered := w.pending_cards.map(func(c: Dictionary) -> String: return c.id)
	assert_has(offered, "arrow_blow_new")
	assert_has(offered, "bow_double_shot_new")
	for family: String in ["bow", "crossbow", "sword"]:
		var combat := _combat(family)
		for key: String in ["arrow_blow", "bow_double_shot", "blessing_of_amazon", "critical_shot", "eye_of_amazon", "focus"]:
			if family != "sword":
				assert_has(combat.upgrades.eligible(combat), key + "_new")
			combat.learn_skill(key)
		for key: String in ["arrow_blow", "bow_double_shot"]:
			assert_eq(key + "_rank" in combat.upgrades.eligible(combat), family != "sword")
			assert_eq(key + "_shots" in combat.upgrades.eligible(combat), family != "sword")
			if family != "sword":
				var before: int = combat.loadout.stats(key).count
				assert_true(combat.upgrades.apply(key + "_shots", combat))
				assert_eq(combat.loadout.stats(key).count, before + 1)


func test_original_bowman_levels_stats_art_and_sounds_resolve_in_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/300.img")
	assert_true(img != null)
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"300": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "bow"
	for row: Array in [["blessing_of_amazon",16], ["critical_shot",20], ["eye_of_amazon",8],
			["focus",20], ["arrow_blow",20], ["bow_double_shot",20]]:
		var key: String = row[0]
		assert_eq(book.max_level(key), row[1])
		assert_eq(book.max_rank(key), row[1])
		for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
			assert_true(lib.frame(book.wz_path(key) + "/" + suffix) != null)
		for level in [1,10,15,20,25]:
			for field: String in ["hit", "effect"]:
				var path := book.visual(key, field, 1, level)
				if path != "":
					assert_false(lib.anim(path).is_empty(), path)
		var sound: String = book.def(key).sounds.use
		if sound != "":
			assert_true(lib.sound(sound) != null)
	for rank_value in [1,20]:
		assert_near(lo.stats("arrow_blow", rank_value).damage_pct, 1.90 if rank_value == 1 else 2.60)
		assert_eq(lo.stats("arrow_blow", rank_value).mp_cost, 7 if rank_value == 1 else 14)
		assert_near(lo.stats("bow_double_shot", rank_value).damage_pct, 0.92 if rank_value == 1 else 1.30)
		assert_eq(lo.stats("bow_double_shot", rank_value).mp_cost, 10 if rank_value == 1 else 16)
		assert_eq(lo.stats("bow_double_shot", rank_value).count, 2)
		var focus := lo.stats("focus", rank_value)
		assert_eq(focus.mp_cost, 8 if rank_value == 1 else 16)
		assert_eq(focus.duration, 70.0 if rank_value == 1 else 300.0)
		assert_eq(focus.buff_effects, {"acc": 1.0 if rank_value == 1 else 20.0, "avoid": 1.0 if rank_value == 1 else 20.0})
	for key: String in ["blessing_of_amazon", "critical_shot", "eye_of_amazon"]:
		lo.add_skill(key)
	assert_eq(lo.passive_total("acc"), 1.0)
	assert_eq(lo.passive_total("crit_chance"), 12.0)
	assert_eq(lo.passive_total("crit_damage"), 105.0)
	assert_eq(lo.passive_total("range"), 15.0)
	lo.set_rank("blessing_of_amazon", 16)
	lo.set_rank("critical_shot", 20)
	lo.set_rank("eye_of_amazon", 8)
	assert_eq(lo.passive_total("acc"), 16.0)
	assert_eq(lo.passive_total("crit_chance"), 40.0)
	assert_eq(lo.passive_total("crit_damage"), 200.0)
	assert_eq(lo.passive_total("range"), 120.0)
	for id in [1452051,1462001]:
		assert_true(lib.node("Character.wz/Weapon/%08d.img/info" % id) is Dictionary)
	for id in [2060000,2061000]:
		assert_false(lib.anim(Ammo.bullet_path(id)).is_empty())
	assert_true(lib.img("Skill.wz/310.img") != null)
	assert_true(lib.img("Skill.wz/320.img") != null)
	assert_eq(Array(lib.missing), [])
	lib.free()


func test_range_passive_is_reusable_by_a_gun_line() -> void:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.skills.skills["reach_training"] = data.skills.skills.eye_of_amazon.duplicate(true)
	data.skills.skills.reach_training.weapon_families = ["gun"]
	var setup := RF.with_basic_attack(RF.setup("quiet", 199, data))
	setup.equipment_info[1492000] = {"incPAD": 13, "attackSpeed": 5}
	setup.body_img["shoot1"] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	var w := RunWorld.new(setup)
	w.change_job(500, "gun")
	assert_near(w.basic.reach(w), 250)
	assert_near(w.loadout.stats("double_shot").range, 215)
	assert_true(w.learn_skill("reach_training"))
	assert_near(w.basic.reach(w), 265)
	assert_near(w.loadout.stats("double_shot").range, 230)
	var crit: float = w.loadout.stats("double_shot").crit
	assert_true(w.learn_skill("blessing_of_amazon"))
	w.refresh_player_stats()
	assert_near(w.loadout.stats("double_shot").crit, crit + w.loadout.crit_per_acc,
		0.001, "Blessing follows the ticket's explicit any-weapon row")
