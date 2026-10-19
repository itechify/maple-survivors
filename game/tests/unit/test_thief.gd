extends TestCase
## Thief first-job tracer (#207): shipping data through public RunWorld advancement, combat, cards and snapshots.
## Seeded synthetic worlds use fixed ticks; real-cache checks verify the original v83 facts separately.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const WEAPONS := {"claw": 1472061, "dagger": 1332063}
const INFO := {
	1472061: {"incPAD": 11, "attackSpeed": 5, "tuc": 7},
	1332063: {"incPAD": 28, "afterImage": "swordOL", "attackSpeed": 3, "tuc": 7},
}


func _world(free := 24) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var setup := RF.with_basic_attack(RF.setup("quiet", 207, data))
	setup.equipment_info.merge(INFO, true)
	if free < 24:
		var character := RunWorld.new(setup).character_snapshot()
		for i in 24 - free:
			character.equipment.inventory.append(Equipment.create(1040002, {"incPDD": 3, "tuc": 7}))
		setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


func _level(w: RunWorld, target: int, path := "claw", forced := 400) -> void:
	var needed := w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level) - w.progression.exp
	w.pickups.spawn(w.player.pos, needed, 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.state != RunWorld.PLAYING:
			BotInput.auto_choose(w, false, forced, path)
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
		var options := w.pending_jobs.filter(func(o: Dictionary) -> bool: return int(o.job_id) == 400)
		assert_eq(options.map(func(o: Dictionary) -> String: return o.get("path", "")), ["claw", "dagger"])
		assert_eq(options.map(func(o: Dictionary) -> String: return o.name), ["Thief - Claw", "Thief - Dagger"])
		assert_true(options.all(func(o: Dictionary) -> bool: return o.available))
		assert_true(w.jobs.advancements(0, 9).filter(func(o: Dictionary) -> bool: return int(o.job_id) == 400).all(
			func(o: Dictionary) -> bool: return not o.available and o.reason == "Lv. 10"))
		var hp: int = w.player_state.max_hp
		var mp: int = w.player_state.max_mp
		assert_true(w.apply_job(400, path))
		assert_eq(w.weapon_id(), WEAPONS[path])
		assert_eq(w.weapon_path, path)
		assert_eq(w.player_state.max_hp, hp + 125)
		assert_eq(w.player_state.max_mp, mp + 37)
		assert_eq(_inventory(w), [1302000, WEAPONS["dagger" if path == "claw" else "claw"]])


func test_full_equip_tab_spills_old_and_extra_weapons_at_the_feet() -> void:
	for path: String in WEAPONS:
		var w := _world(0)
		_open(w)
		w.drain_events()
		assert_true(w.apply_job(400, path))
		assert_eq(w.weapon_id(), WEAPONS[path])
		assert_eq(w.equipment.inventory.size(), 24)
		var drops := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
		assert_eq(drops.size(), 2)
		assert_true(drops.all(func(e: Dictionary) -> bool: return e.pos == w.player.pos and e.kind == "equip"))
		assert_eq(drops.map(func(e: Dictionary) -> int: return int(e.item_id)),
			[1302000, WEAPONS["dagger" if path == "claw" else "claw"]])


func test_snapshot_keeps_the_chosen_path_and_both_weapons() -> void:
	for path: String in WEAPONS:
		var w := _world()
		_open(w)
		w.apply_job(400, path)
		BotInput.auto_choose(w, false, 400, path)
		w.apply_potion_schedule(w.progression.level, false) # the test sets the level directly: no level-up ran the schedule
		var snapshot := w.character_snapshot()
		assert_eq(CharacterSnapshot.validation_error(snapshot), "")
		var setup := w.setup.duplicate(true)
		setup.character = JSON.parse_string(JSON.stringify(snapshot))
		var restored := RunWorld.new(setup)
		assert_eq(restored.character_snapshot(), snapshot)
		assert_eq(restored.weapon_path, path)
		assert_eq(restored.weapon_id(), WEAPONS[path])
		assert_has(_inventory(restored), WEAPONS["dagger" if path == "claw" else "claw"])



func test_seeded_bot_has_luk_eighty_and_dex_twenty_five_by_thirty_on_both_paths() -> void:
	for path: String in WEAPONS:
		var w := _world()
		w.god = true
		for level in range(2, 31):
			_level(w, level, path, 410 if path == "claw" else 420)
		assert_eq(w.progression.job_id, 410 if path == "claw" else 420)
		assert_eq(w.weapon_path, path)
		assert_true(int(w.player_state.luk) >= 80, "LUK first, no stat reset")
		assert_true(int(w.player_state.dex) >= 25, "v83 first-job DEX minimum")
		var hp: int = w.player_state.max_hp
		var mp: int = w.player_state.max_mp
		_level(w, 31, path, 410 if path == "claw" else 420)
		assert_eq(w.player_state.max_hp - hp, 22)
		assert_eq(w.player_state.max_mp - mp, 15)
		var weights := BotShop.weights_for(w.balance, 400, w.jobs)
		assert_true(float(weights.get("incLUK", 0)) > float(weights.get("incDEX", 0)), "LUK equipment first")

func test_thief_rng_is_stream_fifteen_and_does_not_shift_existing_streams() -> void:
	var a := _world()
	var b := _world()
	var properties := a.get_property_list().map(func(p: Dictionary) -> String: return p.name)
	assert_has(properties, "thief_rng")
	if not "thief_rng" in properties:
		return
	var thief: RandomNumberGenerator = a.get("thief_rng")
	var expected := RandomNumberGenerator.new()
	expected.seed = 207 * 1000003 + 15 * 7919
	assert_eq(thief.randi(), expected.randi(), "registered id 15")
	for i in 100:
		thief.randi()
	for property: String in ["rng", "spawn_rng", "card_rng", "drop_rng", "basic_rng", "reward_rng", "potion_rng",
			"job_rng", "meso_rng", "equip_rng", "scroll_rng", "final_rng", "pirate_rng"]:
		var left: RandomNumberGenerator = a.get(property)
		var right: RandomNumberGenerator = b.get(property)
		assert_eq(left.state, right.state, property + " retains its state")
		assert_eq(left.randi(), right.randi(), property + " retains its next draw")


func test_nimble_body_adds_canonical_accuracy_crit_and_avoid_with_either_weapon() -> void:
	for path: String in WEAPONS:
		var w := _world()
		w.change_job(400, path)
		var acc: float = w.player_state.acc
		var avoid: float = w.player_state.avoid
		var crit: float = w.loadout.stats("three_snails").crit
		assert_true(w.learn_skill("nimble_body"))
		assert_near(w.player_state.acc, acc + 1)
		assert_near(w.player_state.avoid, avoid + 1)
		assert_near(w.loadout.stats("three_snails").crit, crit + w.loadout.crit_per_acc)
		w.loadout.set_rank("nimble_body", 20)
		w.refresh_player_stats()
		assert_near(w.player_state.acc, acc + 20)
		assert_near(w.player_state.avoid, avoid + 20)
		assert_false(w.book.is_active("nimble_body"))


func _combat(path: String, key: String, rank_value := 1) -> RunWorld:
	var w := _world()
	w.change_job(400, path)
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



func test_lucky_seven_fires_two_stars_at_nearest_with_luk_formula_and_claw_gate() -> void:
	for path: String in WEAPONS:
		for rank_value in [1, 20]:
			var w := _combat(path, "lucky_seven", rank_value)
			var st := w.loadout.stats("lucky_seven")
			assert_eq(st.count, 2)
			assert_eq(st.cast_rule, "nearest")
			assert_near(st.damage_pct, 0.58 if rank_value == 1 else 1.50)
			# Worked formula example from v83-facts section 5, independent of the generic weapon formula.
			w.loadout.luk_stat = 100
			w.loadout.watk = 50
			w.loadout.mastery = 0.6
			var bounds := w.loadout.stats("lucky_seven")
			assert_eq(bounds.damage_min, 125.0)
			assert_eq(bounds.damage_max, 250.0)
			var mp: int = w.player_state.mp
			var events := _cast(w, [100.0])
			assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1 if path == "claw" else 0)
			assert_eq(w.player_state.mp, mp - ((8 if rank_value == 1 else 16) if path == "claw" else 0))
			assert_eq(w.projectiles.active_count(), 2 if path == "claw" else 0)
			if path == "claw":
				for tick in 30:
					w.step(DT, MoveInput.new())
				var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "lucky_seven")
				assert_eq(hits.size(), 2)
	var too_far := _combat("claw", "lucky_seven")
	assert_true(_cast(too_far, [260.0]).is_empty(), "outside base claw reach waits")

func test_double_stab_hits_twice_in_weapon_reach_with_dagger_gate_and_canonical_cost() -> void:
	for path: String in WEAPONS:
		for rank_value in [1, 20]:
			var w := _combat(path, "double_stab", rank_value)
			var st := w.loadout.stats("double_stab")
			assert_eq(st.cast_rule, "weapon_reach")
			assert_eq(st.attack_count, 2)
			assert_near(st.damage_pct, 0.98 if rank_value == 1 else 1.40)
			var mp: int = w.player_state.mp
			var events := _cast(w, [35.0, 45.0, 300.0])
			var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "double_stab")
			assert_eq(hits.size(), 2 if path == "dagger" else 0)
			assert_eq(w.player_state.mp, mp - ((8 if rank_value == 1 else 14) if path == "dagger" else 0))
			for hit: Dictionary in hits:
				assert_near(hit.pos.x, w.player.pos.x + 35)
	var too_far := _combat("dagger", "double_stab")
	assert_true(_cast(too_far, [300.0]).is_empty(), "outside melee reach waits")


func test_cards_follow_the_held_weapon_and_attack_cards_carry_to_both_branches() -> void:
	for path: String in WEAPONS:
		var w := _world()
		w.change_job(400, path)
		var eligible := w.upgrades.eligible(w)
		assert_has(eligible, "nimble_body_new")
		assert_eq("lucky_seven_new" in eligible, path == "claw")
		assert_eq("double_stab_new" in eligible, path == "dagger")
		for key: String in ["nimble_body", "lucky_seven", "double_stab"]:
			w.learn_skill(key)
		eligible = w.upgrades.eligible(w)
		for key: String in ["nimble_body", "lucky_seven", "double_stab"]:
			var usable := w.book.usable_with(key, path)
			assert_eq(key + "_rank" in eligible, usable)
			assert_eq(int(w.upgrades.card(key + "_rank").get("max_rank", 0)), 20)
			if key == "nimble_body":
				continue
			var id := key + ("_count" if key == "lucky_seven" else "_targets")
			assert_eq(id in eligible, usable)
			if usable:
				var before := w.loadout.stats(key)
				assert_true(w.upgrades.apply(id, w))
				var after := w.loadout.stats(key)
				assert_eq(after.count if key == "lucky_seven" else after.mob_count,
					(before.count if key == "lucky_seven" else before.mob_count) + 1)
		var other: int = WEAPONS["dagger" if path == "claw" else "claw"]
		assert_eq(w.equip_item(_inventory(w).find(other)), "")
		eligible = w.upgrades.eligible(w)
		assert_eq("lucky_seven_rank" in eligible, path == "dagger")
		assert_eq("double_stab_rank" in eligible, path == "claw")
		for branch in [410, 420]:
			w.change_job(branch)
			eligible = w.upgrades.eligible(w)
			assert_false("nimble_body_rank" in eligible)
			for key: String in ["lucky_seven", "double_stab"]:
				assert_eq(key + "_rank" in eligible, w.book.usable_with(key, w.held_weapon_family()))
				assert_eq(w.upgrades.card(key + "_new").requires.carry_jobs, [410.0, 420.0])

func test_lucky_seven_uses_the_current_star_sprite_when_the_ammo_tier_changes() -> void:
	for branch in [400, 410]:
		var w := _combat("claw", "lucky_seven")
		w.change_job(branch)
		w.progression.level = 30 if branch == 410 else 10
		w.refresh_player_stats()
		w._sync_ammo()
		var expected := 2070001 if branch == 410 else 2070015
		assert_eq(w.ammo_id(), expected)
		_cast(w, [100.0])
		assert_eq(w.projectiles.active_count(), 2)
		for i in w.projectiles.capacity():
			if w.projectiles.active[i] != 0:
				assert_eq(w.projectiles.paths[w.projectiles.visual[i]], Ammo.bullet_path(expected))

func test_attacks_wait_without_cost_when_mp_is_short() -> void:
	for key: String in ["lucky_seven", "double_stab"]:
		var w := _combat("claw" if key == "lucky_seven" else "dagger", key)
		w.spend_mp(int(w.player_state.mp))
		var events := _cast(w, [40.0])
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 0)
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mp_short").size(), 1)
		assert_eq(w.player_state.mp, 0)

func test_forced_thief_paths_are_accepted_by_run_and_launcher() -> void:
	var data := DataRepo.load_all()
	for path: String in WEAPONS:
		var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys_hg1", "--job=400:" + path]))
		assert_eq(parsed.options.job, 400)
		assert_eq(parsed.options.job_path, path)
		assert_eq(SceneFlow.forced_job_error(parsed.options, data), "")
		assert_eq(RunLauncher.options_from_args({"job": "400:" + path}).job_path, path)


func test_drop_scroll_and_shop_rosters_follow_the_held_family() -> void:
	var data := DataRepo.load_all()
	for id in [1332000, 1332012, 1472000, 1472008, 1002122, 1040031, 1060021, 1072070, 1082029, 1092018]:
		assert_has(data.equipment_drops.items, float(id))
	for path: String in WEAPONS:
		assert_has(data.shops.weapon_slots, path)
		assert_has(data.scrolls.families, path)
		assert_true(EquipmentDrops.family_allows(WEAPONS[path], path, data.equipment_drops))
		assert_false(EquipmentDrops.family_allows(WEAPONS["dagger" if path == "claw" else "claw"], path, data.equipment_drops))
	var shield_info := {1092018: {"reqJob": 8, "reqLevel": 22}}
	assert_eq(EquipmentDrops.eligible([1092018], shield_info, 400, 22, data.equipment_drops, "dagger"), [1092018])
	assert_eq(EquipmentDrops.eligible([1092018], shield_info, 400, 22, data.equipment_drops, "claw"), [], "Thief shields are for the one-handed dagger")
	var rng := RandomNumberGenerator.new()
	rng.seed = 207
	assert_eq(EquipmentDrops.pick_boss([1092018], shield_info, 400, 70, data.equipment_drops, rng, "claw"), 0,
		"the boss fallback respects the same shield filter outside the level window")
	assert_eq(EquipmentDrops.pick_boss([1092018], shield_info, 400, 70, data.equipment_drops, rng, "dagger"), 1092018)
	var manifest := AssetManifest.load_merged("res://data/asset_manifest.json")
	for id in data.equipment_drops.items:
		assert_has(manifest.character, id)


func test_original_thief_values_art_sounds_and_equipment_resolve_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/400.img")
	assert_true(img != null, "import the Thief manifest fragment")
	if img == null:
		lib.free()
		return
	var data := DataRepo.load_all()
	var book := SkillBook.from_data(data.skills, {"400": img.root})
	var loadout := Loadout.new(book)
	for key: String in ["lucky_seven", "double_stab"]:
		assert_eq(book.max_level(key), 20)
		for rank_value in [1, 20]:
			var st := loadout.stats(key, rank_value)
			assert_eq(st.mp_cost, (8 if rank_value == 1 else 16) if key == "lucky_seven" else (8 if rank_value == 1 else 14))
			assert_near(st.damage_pct, (0.58 if rank_value == 1 else 1.50) if key == "lucky_seven" else (0.98 if rank_value == 1 else 1.40))
			assert_eq(st.count if key == "lucky_seven" else st.attack_count, 2)
		for level in [1, 10, 15, 20, 25]:
			for field: String in ["effect", "hit"]:
				var path := book.visual(key, field, 1, level)
				if path != "":
					assert_false(lib.anim(path).is_empty(), path)
		for path: String in book.def(key).sounds.values():
			if path != "":
				assert_true(lib.sound(path) != null, path)
		assert_true(lib.node("Character.wz/00002000.img/" + String(book.def(key).action)) is Dictionary)
	assert_eq(book.weapon_families("lucky_seven"), PackedStringArray(["claw"]))
	assert_eq(book.weapon_families("double_stab"), PackedStringArray(["dagger"]))
	loadout.add_skill("nimble_body")
	loadout.set_rank("nimble_body", 20)
	assert_eq(loadout.passive_total("acc"), 20.0)
	assert_eq(loadout.passive_total("avoid"), 20.0)
	for id in [2070015, 2070001, 2070006]:
		assert_false(lib.anim(Ammo.bullet_path(id)).is_empty())
	for book_id in [410, 420]:
		assert_true(lib.img("Skill.wz/%d.img" % book_id) != null)
	assert_false(lib.anim("Npc.wz/1052001.img/stand").is_empty())
	var fragment: Dictionary = DataRepo.load_json("res://data/survivor/equipment_drops/thief.json")
	for raw in fragment.items:
		var info: Dictionary = lib.img(AvatarRenderer.part_img_path(int(raw))).root.info
		assert_true(int(info.get("reqJob", 0)) & 8 != 0, str(raw) + " has the Thief bit")
		assert_between(int(info.get("reqLevel", -1)), 0, 70)
	assert_eq(Array(lib.missing), [])
	lib.free()
