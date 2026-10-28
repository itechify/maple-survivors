extends TestCase
## Thief first-job tracer (#207): shipping data through public RunWorld combat, cards and AP, with the job set directly
## (#284 removed advancement and weapon paths; the line is unplayable until ported, its skills stay).
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
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	# The common passives (#289, Max HP above all) would move the HP growth this test measures.
	data.upgrades.cards = data.upgrades.cards.filter(func(c: Dictionary) -> bool: return not String(c.get("skill", "")).begins_with("passive_"))
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


func _level(w: RunWorld, target: int) -> void:
	var needed := w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level) - w.progression.exp
	w.pickups.spawn(w.player.pos, needed, 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.state != RunWorld.PLAYING:
			BotInput.auto_choose(w, false)
		if w.progression.level == target:
			break
	assert_eq(w.progression.level, target)


func _inventory(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func test_seeded_bot_has_luk_eighty_and_dex_twenty_five_by_thirty_on_both_branches() -> void:
	for path: String in WEAPONS:
		var w := _world()
		w.god = true
		RF.as_job(w, 410 if path == "claw" else 420)
		for level in range(2, 31):
			_level(w, level)
		assert_eq(w.progression.job_id, 410 if path == "claw" else 420)
		assert_true(int(w.player_state.luk) >= 80, "LUK first, no stat reset")
		assert_true(int(w.player_state.dex) >= 25, "v83 first-job DEX minimum")
		var hp: int = w.player_state.max_hp
		_level(w, 31)
		assert_eq(w.player_state.max_hp - hp, 22)
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
	for property: String in ["rng", "spawn_rng", "card_rng", "drop_rng", "reward_rng", "potion_rng",
			"meso_rng", "equip_rng", "scroll_rng", "final_rng", "pirate_rng"]:
		var left: RandomNumberGenerator = a.get(property)
		var right: RandomNumberGenerator = b.get(property)
		assert_eq(left.state, right.state, property + " retains its state")
		assert_eq(left.randi(), right.randi(), property + " retains its next draw")


func test_nimble_body_adds_canonical_accuracy_crit_and_avoid_with_either_weapon() -> void:
	for path: String in WEAPONS:
		var w := _world()
		RF.as_job(w, 400, path)
		assert_true(w.learn_skill("lucky_seven"))
		var acc: float = w.player_state.acc
		var avoid: float = w.player_state.avoid
		var crit: float = w.loadout.stats("lucky_seven").crit
		assert_true(w.learn_skill("nimble_body"))
		assert_near(w.player_state.acc, acc + 1)
		assert_near(w.player_state.avoid, avoid + 1)
		assert_near(w.loadout.stats("lucky_seven").crit, crit + w.loadout.crit_per_acc)
		w.loadout.set_rank("nimble_body", 20)
		w.refresh_player_stats()
		assert_near(w.player_state.acc, acc + 20)
		assert_near(w.player_state.avoid, avoid + 20)
		assert_false(w.book.is_active("nimble_body"))


func _combat(path: String, key: String, rank_value := 1) -> RunWorld:
	var w := _world()
	RF.as_job(w, 400, path)
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



func test_lucky_seven_fires_two_stars_at_nearest_with_luk_formula_and_any_weapon() -> void:
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
			var events := _cast(w, [100.0])
			# Weapons gate no skill (#284): a dagger throws the stars too.
			assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1, path)
			assert_eq(w.projectiles.active_count(), 2)
			for tick in 30:
				w.step(DT, MoveInput.new())
			var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "lucky_seven")
			assert_eq(hits.size(), 2, path)
	var too_far := _combat("claw", "lucky_seven")
	assert_true(_cast(too_far, [260.0]).is_empty(), "outside base claw reach waits")

func test_double_stab_hits_twice_in_the_dagger_reach() -> void:
	for path: String in ["dagger"]:
		for rank_value in [1, 20]:
			var w := _combat(path, "double_stab", rank_value)
			var st := w.loadout.stats("double_stab")
			assert_eq(st.cast_rule, "weapon_reach")
			assert_eq(st.attack_count, 2)
			assert_near(st.damage_pct, 0.98 if rank_value == 1 else 1.40)
			var events := _cast(w, [35.0, 45.0, 300.0])
			var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "double_stab")
			assert_eq(hits.size(), 2)
			for hit: Dictionary in hits:
				assert_near(hit.pos.x, w.player.pos.x + 35)
	var too_far := _combat("dagger", "double_stab")
	assert_true(_cast(too_far, [300.0]).is_empty(), "outside melee reach waits")
	# Weapons gate no skill (#284): with a claw it still casts, inside the claw's own reach.
	var claw := _combat("claw", "double_stab")
	assert_eq(_cast(claw, [35.0]).filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1)


func test_cards_are_on_offer_whatever_weapon_is_held_and_on_both_branches() -> void:
	for path: String in WEAPONS:
		var w := _world()
		RF.as_job(w, 400, path)
		var eligible := w.upgrades.eligible(w)
		for key: String in ["nimble_body", "lucky_seven", "double_stab"]:
			assert_false(key + "_new" in eligible, "#287: unported skills have no pool offers")
			w.learn_skill(key)
		eligible = w.upgrades.eligible(w)
		for key: String in ["nimble_body", "lucky_seven", "double_stab"]:
			assert_false(key + "_rank" in eligible, "#287: unported skills have no pool offers")
			assert_eq(int(w.upgrades.card(key + "_rank").get("max_rank", 0)), 20)
			if key == "nimble_body":
				continue
			var id := key + ("_count" if key == "lucky_seven" else "_targets")
			assert_false(id in eligible, "#287: unported skills have no pool offers")
			var before := w.loadout.stats(key)
			assert_true(w.upgrades.apply(id, w))
			var after := w.loadout.stats(key)
			assert_eq(after.count if key == "lucky_seven" else after.mob_count,
				(before.count if key == "lucky_seven" else before.mob_count) + 1)
		for branch in [410, 420]:
			RF.as_job(w, branch)
			eligible = w.upgrades.eligible(w)
			# A first-job card is on the line of both branches (UpgradePool.on_line, #284).
			for key: String in ["nimble_body", "lucky_seven", "double_stab"]:
				assert_false(key + "_rank" in eligible, "#287: unported skills have no pool offers")
				assert_false(w.upgrades.card(key + "_new").requires.has("carry_jobs"))

func test_lucky_seven_uses_the_current_star_sprite_when_the_ammo_tier_changes() -> void:
	for branch in [400, 410]:
		var w := _combat("claw", "lucky_seven")
		RF.as_job(w, branch)
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
