extends TestCase
## Pirate first-job tracer (#186): shipping data through public RunWorld combat and cards, the Pirate stood directly
## (RF.as_job; #284 removed advancement, weapon paths and weapon gating).
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
	var setup := RF.with_basic_attack(RF.setup("quiet", 186, data))
	setup.equipment_info.merge(INFO, true)
	setup["job"] = 500 # no start skills
	if free < 24:
		var character := RunWorld.new(setup).character_snapshot()
		for i in 24 - free:
			character.equipment.inventory.append(Equipment.create(1040002, {"incPDD": 3, "tuc": 7}))
		setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


func test_bullet_time_adds_canonical_accuracy_crit_and_avoid_with_either_weapon() -> void:
	for path: String in WEAPONS:
		var w := _world()
		RF.as_job(w, 500, path)
		var acc: float = w.player_state.acc
		var avoid: float = w.player_state.avoid
		assert_true(w.learn_skill("somersault_kick"))
		var crit: float = w.loadout.stats("somersault_kick").crit
		assert_true(w.learn_skill("bullet_time"))
		assert_near(w.player_state.acc, acc + 1)
		assert_near(w.player_state.avoid, avoid + 1)
		assert_near(w.loadout.stats("somersault_kick").crit, crit + w.loadout.crit_per_acc)
		w.loadout.set_rank("bullet_time", 20)
		w.refresh_player_stats()
		assert_near(w.player_state.acc, acc + 20)
		assert_near(w.player_state.avoid, avoid + 20)
		assert_false(w.book.is_active("bullet_time"))


func _combat(path: String, key: String, rank_value := 1) -> RunWorld:
	var w := _world()
	RF.as_job(w, 500, path)
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


func test_flash_fist_uses_front_box_cost_and_one_target_with_either_weapon() -> void:
	for path: String in WEAPONS:
		var w := _combat(path, "flash_fist")
		var events := _cast(w, [35.0, 45.0, -35.0, 200.0])
		var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "flash_fist")
		assert_eq(hits.size(), 1, path)
		if not hits.is_empty():
			assert_near(hits[0].pos.x, w.player.pos.x + 35)
			assert_true(int(hits[0].damage) > 0)
	var out_of_reach := _combat("knuckle", "flash_fist")
	assert_true(_cast(out_of_reach, [-35.0, 200.0]).is_empty(), "no front target means no cast")


func test_somersault_kick_strikes_around_with_either_weapon_at_canonical_caps_and_costs() -> void:
	for path: String in WEAPONS:
		for rank_value in [1, 20]:
			var w := _combat(path, "somersault_kick", rank_value)
			var events := _cast(w, [-60.0, -50.0, -40.0, 30.0, 40.0, 50.0, 60.0, 300.0])
			var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "somersault_kick")
			assert_eq(hits.size(), 3 if rank_value == 1 else 6)
			assert_true(hits.any(func(e: Dictionary) -> bool: return e.pos.x < w.player.pos.x))
			assert_true(hits.any(func(e: Dictionary) -> bool: return e.pos.x > w.player.pos.x))


func test_double_shot_uses_two_bullets_canonical_range_and_cost_with_either_weapon() -> void:
	for path: String in WEAPONS:
		for rank_value in [1, 20]:
			var w := _combat(path, "double_shot", rank_value)
			var st := w.loadout.stats("double_shot")
			assert_eq(st.count, 2)
			assert_eq(st.range, 215.0 if rank_value == 1 else 350.0)
			var events := _cast(w, [100.0])
			assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1, path)
			assert_eq(w.projectiles.active_count(), 2, path)
			for tick in 30:
				w.step(DT, MoveInput.new())
			var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "double_shot")
			assert_eq(hits.size(), 2, path)
	var too_far := _combat("gun", "double_shot")
	assert_true(_cast(too_far, [360.0]).is_empty(), "outside canonical range: waits")


func test_pirate_cards_are_offered_with_either_weapon_and_attacks_can_hit_more_mobs() -> void:
	for path: String in WEAPONS:
		var w := _world()
		RF.as_job(w, 500, path)
		var eligible := w.upgrades.eligible(w)
		for key: String in ["bullet_time", "somersault_kick", "flash_fist", "double_shot"]:
			assert_false(key + "_new" in eligible, "#287: unported skills have no pool offers")
		for key: String in ["bullet_time", "flash_fist", "somersault_kick", "double_shot"]:
			w.learn_skill(key)
		eligible = w.upgrades.eligible(w)
		for key: String in ["bullet_time", "flash_fist", "somersault_kick", "double_shot"]:
			assert_false(key + "_rank" in eligible, "#287: unported skills have no pool offers")
			assert_eq(int(w.upgrades.card(key + "_rank").get("max_rank", 0)), 20)
			if key == "bullet_time":
				continue
			var id := key + ("_pierce" if key == "double_shot" else "_targets")
			assert_false(id in eligible, "#287: unported skills have no pool offers")
			var before := w.loadout.stats(key)
			assert_true(w.upgrades.apply(id, w))
			var after := w.loadout.stats(key)
			assert_eq(after.pierce if key == "double_shot" else after.mob_count,
				(before.pierce if key == "double_shot" else before.mob_count) + 1)


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
		assert_true(EquipmentDrops.family_allows(own, [path]))
		assert_false(EquipmentDrops.family_allows(other, [path]))


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
	for property: String in ["rng", "spawn_rng", "card_rng", "drop_rng", "reward_rng", "potion_rng",
			"meso_rng", "equip_rng", "scroll_rng", "final_rng"]:
		var left: RandomNumberGenerator = a.get(property)
		var right: RandomNumberGenerator = b.get(property)
		assert_eq(left.state, right.state, property + " retains its state")
		assert_eq(left.randi(), right.randi(), property + " retains its next draw")




func test_original_pirate_tables_art_actions_and_sounds_resolve_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/500.img")
	assert_true(img != null, "import the Pirate manifest fragment")
	if img == null:
		lib.free()
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
	lib.free()
