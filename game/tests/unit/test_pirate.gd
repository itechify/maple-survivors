extends TestCase
## Pirate first-job tracer (#186): shipping data through public RunWorld advancement, combat, cards and snapshots.
## Seeded synthetic worlds use fixed ticks; real-cache checks verify the original v83 facts separately.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const WEAPONS := {"knuckle": 1482000, "gun": 1492000}
const INFO := {
	1482000: {"incPAD": 18, "attackSpeed": 5, "tuc": 7},
	1492000: {"incPAD": 13, "attackSpeed": 5, "tuc": 7},
}


func _world(free := 24) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var setup := RF.with_basic_attack(RF.setup("quiet", 186, data))
	setup.equipment_info.merge(INFO, true)
	if free < 24:
		var character := RunWorld.new(setup).character_snapshot()
		for i in 24 - free:
			character.equipment.inventory.append(Equipment.create(1040002, {"incPDD": 3, "tuc": 7}))
		setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


func _level(w: RunWorld, target: int, path := "knuckle") -> void:
	var needed := w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level) - w.progression.exp
	w.pickups.spawn(w.player.pos, needed, 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.state != RunWorld.PLAYING:
			BotInput.auto_choose(w, false, 500, path)
		if w.progression.level == target:
			break
	assert_eq(w.progression.level, target)


func _open(w: RunWorld) -> void:
	w.progression.level = 9
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB)


func _inventory(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func test_both_paths_are_offered_at_ten_and_grant_both_weapons() -> void:
	for path: String in WEAPONS:
		var w := _world()
		_open(w)
		var options := w.pending_jobs.filter(func(o: Dictionary) -> bool: return int(o.job_id) == 500)
		assert_eq(options.map(func(o: Dictionary) -> String: return o.get("path", "")), ["knuckle", "gun"])
		assert_eq(options.map(func(o: Dictionary) -> String: return o.name), ["Pirate - Knuckle", "Pirate - Gun"])
		assert_true(options.all(func(o: Dictionary) -> bool: return o.available))
		assert_true(w.jobs.advancements(0, 9).filter(func(o: Dictionary) -> bool: return int(o.job_id) == 500).all(
			func(o: Dictionary) -> bool: return not o.available and o.reason == "Lv. 10"))
		var hp: int = w.player_state.max_hp
		var mp: int = w.player_state.max_mp
		assert_true(w.apply_job(500, path))
		assert_eq(w.weapon_id(), WEAPONS[path])
		assert_eq(w.weapon_path, path)
		assert_eq(w.player_state.max_hp, hp + 125)
		assert_eq(w.player_state.max_mp, mp + 37)
		assert_eq(_inventory(w), [1302000, WEAPONS["gun" if path == "knuckle" else "knuckle"]])


func test_full_equip_tab_spills_old_and_extra_weapons_at_the_feet() -> void:
	for path: String in WEAPONS:
		var w := _world(0)
		_open(w)
		w.drain_events()
		assert_true(w.apply_job(500, path))
		assert_eq(w.weapon_id(), WEAPONS[path])
		assert_eq(w.equipment.inventory.size(), 24)
		var drops := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
		assert_eq(drops.size(), 2)
		assert_true(drops.all(func(e: Dictionary) -> bool: return e.pos == w.player.pos and e.kind == "equip"))
		assert_eq(drops.map(func(e: Dictionary) -> int: return int(e.item_id)),
			[1302000, WEAPONS["gun" if path == "knuckle" else "knuckle"]])


func test_seeded_bot_meets_level_thirty_weapon_requirements_on_both_paths() -> void:
	for path: String in WEAPONS:
		var w := _world()
		w.god = true
		for level in range(2, 31):
			_level(w, level, path)
		assert_eq(w.progression.job_id, 500, "second jobs stay locked until #189")
		assert_eq(w.weapon_path, path)
		var requirements := {"reqLevel": 30, "reqJob": 16, "reqSTR": 60, "reqDEX": 30} if path == "knuckle" \
			else {"reqLevel": 30, "reqJob": 16, "reqSTR": 30, "reqDEX": 70}
		assert_eq(Equipment.requirement_error(requirements, w.player_state), "", "Prime Hands / Cold Mind")
		assert_eq(w.player_state.dex if path == "knuckle" else w.player_state.str, 30)
		var hp: int = w.player_state.max_hp
		var mp: int = w.player_state.max_mp
		_level(w, 31, path)
		assert_eq(w.player_state.max_hp, hp + 25)
		assert_between(w.player_state.max_mp - mp, 20, 21, "20.5 MP accumulates before rounding")


func test_snapshot_keeps_the_chosen_path_and_both_weapons() -> void:
	for path: String in WEAPONS:
		var w := _world()
		_open(w)
		w.apply_job(500, path)
		BotInput.auto_choose(w, false, 500, path)
		var snapshot := w.character_snapshot()
		assert_eq(CharacterSnapshot.validation_error(snapshot), "")
		var setup := w.setup.duplicate(true)
		setup.character = JSON.parse_string(JSON.stringify(snapshot))
		var restored := RunWorld.new(setup)
		assert_eq(restored.character_snapshot(), snapshot)
		assert_eq(restored.weapon_path, path)
		assert_eq(restored.weapon_id(), WEAPONS[path])
		assert_has(_inventory(restored), WEAPONS["gun" if path == "knuckle" else "knuckle"])


func test_bullet_time_adds_canonical_accuracy_crit_and_avoid_with_either_weapon() -> void:
	for path: String in WEAPONS:
		var w := _world()
		w.change_job(500, path)
		var acc: float = w.player_state.acc
		var avoid: float = w.player_state.avoid
		var crit: float = w.loadout.stats("three_snails").crit
		assert_true(w.learn_skill("bullet_time"))
		assert_near(w.player_state.acc, acc + 1)
		assert_near(w.player_state.avoid, avoid + 1)
		assert_near(w.loadout.stats("three_snails").crit, crit + w.loadout.crit_per_acc)
		w.loadout.set_rank("bullet_time", 20)
		w.refresh_player_stats()
		assert_near(w.player_state.acc, acc + 20)
		assert_near(w.player_state.avoid, avoid + 20)
		assert_false(w.book.is_active("bullet_time"))


func _combat(path: String, key: String, rank_value := 1) -> RunWorld:
	var w := _world()
	w.change_job(500, path)
	w.heal_fraction("mp", 1.0)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
	w.player.facing = 1
	assert_true(w.learn_skill(key))
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _cast(w: RunWorld, positions: Array) -> Array:
	for dx: float in positions:
		RF.put_mob(w, 1110100, w.player.pos.x + dx, 190, 10000)
	w.drain_events()
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	return w.drain_events()


func test_flash_fist_uses_front_box_cost_and_one_target_and_needs_a_knuckle() -> void:
	for path: String in WEAPONS:
		var w := _combat(path, "flash_fist")
		var mp: int = w.player_state.mp
		var events := _cast(w, [35.0, 45.0, -35.0, 200.0])
		var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "flash_fist")
		assert_eq(hits.size(), 1 if path == "knuckle" else 0)
		assert_eq(w.player_state.mp, mp - (6 if path == "knuckle" else 0))
		if not hits.is_empty():
			assert_near(hits[0].pos.x, w.player.pos.x + 35)
			assert_true(int(hits[0].damage) > 0)
	var out_of_reach := _combat("knuckle", "flash_fist")
	assert_true(_cast(out_of_reach, [-35.0, 200.0]).is_empty(), "no front target means no cast or cost")


func test_somersault_kick_strikes_around_with_either_weapon_at_canonical_caps_and_costs() -> void:
	for path: String in WEAPONS:
		for rank_value in [1, 20]:
			var w := _combat(path, "somersault_kick", rank_value)
			var mp: int = w.player_state.mp
			var events := _cast(w, [-60.0, -50.0, -40.0, 30.0, 40.0, 50.0, 60.0, 300.0])
			var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "somersault_kick")
			assert_eq(hits.size(), 3 if rank_value == 1 else 6)
			assert_eq(w.player_state.mp, mp - (8 if rank_value == 1 else 16))
			assert_true(hits.any(func(e: Dictionary) -> bool: return e.pos.x < w.player.pos.x))
			assert_true(hits.any(func(e: Dictionary) -> bool: return e.pos.x > w.player.pos.x))


func test_double_shot_uses_two_bullets_canonical_range_and_cost_and_requires_a_gun() -> void:
	for path: String in WEAPONS:
		for rank_value in [1, 20]:
			var w := _combat(path, "double_shot", rank_value)
			var st := w.loadout.stats("double_shot")
			assert_eq(st.count, 2)
			assert_eq(st.range, 215.0 if rank_value == 1 else 350.0)
			var mp: int = w.player_state.mp
			var events := _cast(w, [100.0])
			assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1 if path == "gun" else 0)
			assert_eq(w.player_state.mp, mp - ((4 if rank_value == 1 else 7) if path == "gun" else 0))
			assert_eq(w.projectiles.active_count(), 2 if path == "gun" else 0)
			if path == "gun":
				for tick in 30:
					w.step(DT, MoveInput.new())
				var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "double_shot")
				assert_eq(hits.size(), 2)
	var too_far := _combat("gun", "double_shot")
	assert_true(_cast(too_far, [360.0]).is_empty(), "outside canonical range: waits")


func test_pirate_cards_follow_the_weapon_held_when_drawn_and_attacks_can_hit_more_mobs() -> void:
	for path: String in WEAPONS:
		var w := _world()
		w.change_job(500, path)
		var eligible := w.upgrades.eligible(w)
		assert_has(eligible, "bullet_time_new")
		assert_has(eligible, "somersault_kick_new")
		assert_eq("flash_fist_new" in eligible, path == "knuckle")
		assert_eq("double_shot_new" in eligible, path == "gun")
		for key: String in ["bullet_time", "flash_fist", "somersault_kick", "double_shot"]:
			w.learn_skill(key)
		eligible = w.upgrades.eligible(w)
		for key: String in ["bullet_time", "flash_fist", "somersault_kick", "double_shot"]:
			var usable := w.book.usable_with(key, path)
			assert_eq(key + "_rank" in eligible, usable)
			assert_eq(int(w.upgrades.card(key + "_rank").get("max_rank", 0)), 20)
			if key == "bullet_time":
				continue
			var id := key + ("_pierce" if key == "double_shot" else "_targets")
			assert_eq(id in eligible, usable)
			if usable:
				var before := w.loadout.stats(key)
				assert_true(w.upgrades.apply(id, w))
				var after := w.loadout.stats(key)
				assert_eq(after.pierce if key == "double_shot" else after.mob_count,
					(before.pierce if key == "double_shot" else before.mob_count) + 1)
		# Manual weapon swaps change cards immediately, without changing the recorded AP path.
		var other := int(WEAPONS["gun" if path == "knuckle" else "knuckle"])
		assert_eq(w.equip_item(_inventory(w).find(other)), "")
		eligible = w.upgrades.eligible(w)
		assert_eq("flash_fist_rank" in eligible, path == "gun")
		assert_eq("double_shot_rank" in eligible, path == "knuckle")


func test_pirate_drop_scroll_and_shop_rosters_follow_the_held_family() -> void:
	var data := DataRepo.load_all()
	var ids: Array = data.equipment_drops.items.map(func(id: Variant) -> int: return int(id))
	for id in [1482000, 1482004, 1482009, 1492000, 1492004, 1492009]:
		assert_has(ids, id)
	for path: String in WEAPONS:
		assert_has(data.shops.weapon_slots, path)
		assert_has(data.scrolls.families, path)
		var own: int = WEAPONS[path]
		var other: int = WEAPONS["gun" if path == "knuckle" else "knuckle"]
		assert_true(EquipmentDrops.family_allows(own, path, data.equipment_drops))
		assert_false(EquipmentDrops.family_allows(other, path, data.equipment_drops))
	var info_ids := DataRepo.starter_equipment_ids(data)
	assert_has(info_ids, 1482004)
	assert_has(info_ids, 1492004)


func test_pirate_rng_is_stream_sixteen_and_does_not_shift_existing_streams() -> void:
	var a := _world()
	var b := _world()
	var properties := a.get_property_list().map(func(p: Dictionary) -> String: return p.name)
	assert_has(properties, "pirate_rng")
	if not "pirate_rng" in properties:
		return
	var pirate: RandomNumberGenerator = a.get("pirate_rng")
	var expected := RandomNumberGenerator.new()
	expected.seed = 186 * 1000003 + 16 * 7919
	assert_eq(pirate.randi(), expected.randi(), "registered id 16")
	for i in 100:
		pirate.randi()
	for property: String in ["rng", "spawn_rng", "card_rng", "drop_rng", "basic_rng", "reward_rng", "potion_rng",
			"job_rng", "meso_rng", "equip_rng", "scroll_rng", "final_rng"]:
		var left: RandomNumberGenerator = a.get(property)
		var right: RandomNumberGenerator = b.get(property)
		assert_eq(left.state, right.state, property + " retains its state")
		assert_eq(left.randi(), right.randi(), property + " retains its next draw")


func test_attacks_wait_without_spending_when_mp_is_short() -> void:
	for key: String in ["flash_fist", "somersault_kick", "double_shot"]:
		var w := _combat("gun" if key == "double_shot" else "knuckle", key)
		assert_true(w.spend_mp(int(w.player_state.mp)))
		var events := _cast(w, [40.0])
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 0)
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mp_short").size(), 1)
		assert_eq(w.player_state.mp, 0)


func test_path_ap_survives_swaps_and_a_branch_row_takes_precedence() -> void:
	var w := _world()
	w.god = true
	for level in range(2, 31):
		_level(w, level, "gun")
	var str_before: int = w.player_state.str
	var dex_before: int = w.player_state.dex
	assert_eq(w.equip_item(_inventory(w).find(1482000)), "")
	assert_eq(w.weapon_path, "gun")
	assert_eq(w.player_state.str, str_before)
	assert_eq(w.player_state.dex, dex_before)
	# Synthetic branch rows model #189's additive plain-job override; not shipping second-job gameplay.
	w.balance.player.ap_stat["520"] = "luk"
	w.balance.player.ap_secondary["520"] = {"stat": "str", "keyframes": [{"level": 30, "target": 40}]}
	w.change_job(520)
	assert_eq(w.player_state.str, 40)
	assert_eq(w.player_state.dex, 5)
	assert_true(w.player_state.luk > 100)


func test_extra_path_items_load_their_info_even_when_no_other_roster_names_them() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["500"].paths[0].extra_items = [1092003]
	data.equipment_drops.items = []
	assert_has(DataRepo.starter_equipment_ids(data), 1092003)


func test_forced_pirate_path_flags_are_accepted_by_run_and_launcher() -> void:
	var data := DataRepo.load_all()
	for path: String in WEAPONS:
		var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys_hg1", "--job=500:" + path]))
		assert_eq(parsed.options.job, 500)
		assert_eq(parsed.options.job_path, path)
		assert_eq(SceneFlow.forced_job_error(parsed.options, data), "")
		assert_eq(RunLauncher.options_from_args({"job": "500:" + path}).job_path, path)


func test_bot_keeps_the_wielded_path_when_the_other_gift_scores_higher() -> void:
	var w := _world()
	_open(w)
	BotInput.auto_choose(w, false, 500, "gun")
	var events := w.drain_events()
	assert_true(BotShop.item_score(w.equipment.inventory[-1], BotShop.weights_for(w.balance, 500, w.jobs)) >
		BotShop.item_score(w.equipment.worn.weapon, BotShop.weights_for(w.balance, 500, w.jobs)))
	BotShop.equip_after(w, events)
	assert_eq(w.weapon_id(), 1492000, "the bot must not replace its gun with Kyrin's higher-PAD knuckle")
	assert_eq(w.weapon_path, "gun")
	# A manual swap is still allowed; bot upgrades follow the held family rather than forcing the recorded AP path.
	assert_eq(w.equip_item(_inventory(w).find(1482000)), "")
	BotShop.auto_equip(w)
	assert_eq(w.weapon_id(), 1482000)


func test_original_pirate_tables_art_actions_and_sounds_resolve_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/500.img")
	assert_true(img != null, "import the Pirate manifest fragment")
	if img == null:
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"500": img.root})
	var loadout := Loadout.new(book)
	var facts := {
		"flash_fist": [6, 14, 1.56, 2.70],
		"somersault_kick": [8, 16, 1.14, 1.90],
		"double_shot": [4, 7, 0.61, 0.80],
	}
	for key: String in facts:
		assert_eq(book.max_level(key), 20)
		for rank_value in [1, 20]:
			var st := loadout.stats(key, rank_value)
			assert_eq(st.mp_cost, facts[key][0 if rank_value == 1 else 1])
			assert_near(st.damage_pct, facts[key][2 if rank_value == 1 else 3])
			if key == "double_shot":
				assert_eq(st.count, 2)
				assert_eq(st.range, 215.0 if rank_value == 1 else 350.0)
			else:
				assert_eq(st.mob_count, (3 if rank_value == 1 else 6) if key == "somersault_kick" else 1)
		for level in [1, 10, 15, 20, 25]:
			for field: String in ["effect", "hit", "ball"]:
				var path := book.visual(key, field, 1, level)
				if path != "":
					assert_false(lib.anim(path).is_empty(), path)
		assert_true(lib.sound(book.def(key).sounds.use) != null, key + " use sound")
		assert_true(lib.node("Character.wz/00002000.img/" + String(book.def(key).action)) is Dictionary)
	assert_eq(book.weapon_families("double_shot"), PackedStringArray(["gun"]))
	loadout.add_skill("bullet_time")
	loadout.set_rank("bullet_time", 20)
	assert_eq(loadout.passive_total("acc"), 20.0)
	assert_eq(loadout.passive_total("avoid"), 20.0)
	assert_true(lib.img("Skill.wz/510.img") != null)
	assert_true(lib.img("Skill.wz/520.img") != null)
	assert_false(lib.anim("Npc.wz/1090000.img/stand").is_empty())
	assert_eq(Array(lib.missing), [])
