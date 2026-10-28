extends TestCase
## Keen Eyes (#209): seeded public combat, the claw passive's reach and its card boundaries. Since #284 weapons gate
## no passive or card: the range passive counts with any weapon, and only ranged weapons and their skills reach further.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(path := "claw") -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.with_basic_attack(RF.setup("quiet", 209, data))
	setup["job"] = 400 # no start skills
	setup.equipment_info.merge({
		1472061: {"incPAD": 17, "attackSpeed": 4},
		1332063: {"incPAD": 20, "attackSpeed": 4, "afterImage": "swordOS"},
		1452051: {"incPAD": 28, "attackSpeed": 6}, 1462001: {"incPAD": 29, "attackSpeed": 6},
		1492000: {"incPAD": 13, "attackSpeed": 5}}, true)
	setup.body_img["shoot1"] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.body_img["shoot2"] = setup.body_img.shoot1.duplicate(true)
	var w := RunWorld.new(setup)
	RF.as_job(w, 400, path)
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	w.heal_fraction("mp", 1.0)
	for kind: MobKind in w.mob_kinds:
		kind.hitbox = Rect2(-2, -10, 4, 10)
		kind.move_speed = 0
	w.drain_events()
	return w


func _target(w: RunWorld, distance := 440.0) -> void:
	RF.put_mob(w, 1110100, w.player.pos.x + distance, 190, 10000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()


func _ticks(w: RunWorld, count := 90) -> Array:
	for tick in count:
		w.step(DT, MoveInput.new())
	return w.drain_events()


func test_rank_eight_extends_the_claw_reach_by_200px() -> void:
	var w := _world()
	assert_near(w.weapon_reach.reach(w), 250)
	assert_true(w.learn_skill("keen_eyes"))
	w.loadout.set_rank("keen_eyes", 8)
	w.refresh_player_stats()
	assert_near(w.weapon_reach.reach(w), 450)
	assert_near(w.weapon_reach.envelope(w).position.x, -450)


func test_lucky_seven_gains_the_same_200px_and_hits_the_formerly_distant_target() -> void:
	var w := _world()
	assert_true(w.learn_skill("lucky_seven"))
	_target(w)
	assert_near(w.loadout.stats("lucky_seven").range, 250)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 0)
	assert_true(w.learn_skill("keen_eyes"))
	w.loadout.set_rank("keen_eyes", 8)
	w.refresh_player_stats()
	assert_near(w.loadout.stats("lucky_seven").range, 450)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 2)
	var hits := _ticks(w).filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "lucky_seven")
	assert_true(hits.size() >= 2, "Lucky Seven's extended target search and star travel both reach 440px")


func test_dagger_is_unchanged_and_swapping_back_uses_the_current_rank() -> void:
	var w := _world("dagger")
	var reach := w.weapon_reach.reach(w)
	var envelope := w.weapon_reach.envelope(w)
	var stab := w.loadout.stats("double_stab")
	assert_true(w.learn_skill("keen_eyes"))
	w.loadout.set_rank("keen_eyes", 8)
	w.refresh_player_stats()
	assert_eq(w.weapon_reach.reach(w), reach)
	assert_eq(w.weapon_reach.envelope(w), envelope)
	assert_eq(w.loadout.stats("double_stab"), stab)
	assert_eq(w.loadout.passive_total(Loadout.RANGE), 200.0, "the passive counts with any weapon (#284)")
	assert_near(w.loadout.stats("lucky_seven").range, 250)
	w.equipment.inventory.append(Equipment.create(1472061, w.setup.equipment_info[1472061]))
	var inventory: Array = w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))
	assert_eq(w.equip_item(inventory.find(1472061)), "")
	assert_near(w.weapon_reach.reach(w), 450)
	assert_near(w.weapon_reach.envelope(w).position.x, -450)
	w.loadout.set_rank("keen_eyes", 1)
	w.refresh_player_stats()
	assert_near(w.weapon_reach.reach(w), 275, 0.001, "cached base reach never retains an old passive value")
	assert_near(w.loadout.stats("lucky_seven").range, 275)


func test_cards_are_offered_on_the_thief_line_with_any_weapon_and_cap_at_eight() -> void:
	for path: String in ["claw", "dagger"]:
		var w := _world(path)
		var base_reach := w.weapon_reach.reach(w)
		assert_has(w.upgrades.eligible(w), "keen_eyes_new", "with a " + path)
		assert_true(w.upgrades.apply("keen_eyes_new", w))
		assert_has(w.upgrades.eligible(w), "keen_eyes_rank")
		assert_true(w.upgrades.apply("keen_eyes_rank", w))
		assert_eq(w.loadout.rank("keen_eyes"), 2)
		assert_near(w.weapon_reach.reach(w), 300.0 if path == "claw" else base_reach)
		for id: String in ["keen_eyes_new", "keen_eyes_rank"]:
			var card := w.upgrades.card(id)
			assert_eq(card.get("requires", {}).get("jobs", []), [400.0])
			assert_false(card.get("requires", {}).has("carry_jobs"))
		w.loadout.set_rank("keen_eyes", 8)
		assert_false("keen_eyes_rank" in w.upgrades.eligible(w), "capped at eight")
		w.loadout.set_rank("keen_eyes", 1)
		for branch in [410, 420]:
			w.set_job(branch)
			assert_has(w.upgrades.eligible(w), "keen_eyes_rank", "%d is on the Thief line" % branch)
			assert_near(w.weapon_reach.reach(w), 275 if path == "claw" else base_reach)


func test_melee_weapons_and_unrelated_skill_ranges_are_unchanged() -> void:
	for weapon in [1302000, 1372005]:
		var w := _world()
		w.equipment.inventory.append(Equipment.create(weapon, w.setup.equipment_info[weapon]))
		assert_eq(w.equip_item(w.equipment.inventory.size() - 1), "")
		var reach := w.weapon_reach.reach(w)
		var envelope := w.weapon_reach.envelope(w)
		var ranges := {}
		for key: String in w.book.defs:
			ranges[key] = w.loadout.stats(key).range
		assert_true(reach > 0)
		assert_true(w.learn_skill("keen_eyes"))
		w.loadout.set_rank("keen_eyes", 8)
		w.refresh_player_stats()
		assert_eq(w.weapon_reach.reach(w), reach)
		assert_eq(w.weapon_reach.envelope(w), envelope)
		for key: String in ranges:
			if key != "keen_eyes":
				assert_eq(w.loadout.stats(key).range, ranges[key], "%s with %s" % [key, WeaponInfo.family(weapon)])
	var claw := _world()
	var magic: float = claw.loadout.stats("energy_bolt").range
	assert_true(claw.learn_skill("keen_eyes"))
	claw.loadout.set_rank("keen_eyes", 8)
	assert_eq(claw.loadout.stats("energy_bolt").range, magic, "magic never receives the ranged passive")


func test_every_ranged_weapon_reaches_further_with_the_passive() -> void:
	# #284: weapons gate no passive, so the range passive extends every ranged weapon's reach.
	for weapon in [1452051, 1462001, 1492000]:
		var w := _world()
		w.equipment.inventory.append(Equipment.create(weapon, w.setup.equipment_info[weapon]))
		assert_eq(w.equip_item(w.equipment.inventory.size() - 1), "")
		var reach := w.weapon_reach.reach(w)
		assert_true(w.learn_skill("keen_eyes"))
		w.loadout.set_rank("keen_eyes", 8)
		w.refresh_player_stats()
		assert_near(w.weapon_reach.reach(w), reach + 200.0, 0.001, WeaponInfo.family(weapon))


func test_every_rank_and_card_and_skill_window_text_show_the_canonical_pixels() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	var learn: Dictionary = text.dress([w.upgrades.choice_card("keen_eyes_new", w)], w.loadout)[0]
	assert_eq(learn.detail, "Claw attack range: +25 px.")
	assert_true(w.learn_skill("keen_eyes"))
	var model := SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 400, text)
	var expected := [25, 50, 75, 100, 125, 150, 175, 200]
	assert_eq(w.book.max_rank("keen_eyes"), 8)
	assert_false(w.book.is_active("keen_eyes"))
	for i in expected.size():
		w.loadout.set_rank("keen_eyes", i + 1)
		var tip := model.skill_tooltip("keen_eyes")
		assert_near(w.loadout.passive_total(Loadout.RANGE), expected[i])
		assert_eq(tip.current, "Claw attack range: +%d px." % expected[i])
		if i < 7:
			var card: Dictionary = text.dress([w.upgrades.choice_card("keen_eyes_rank", w)], w.loadout)[0]
			assert_eq(card.desc, "Claw attack range: +%d px." % expected[i + 1])
	assert_eq(model.skill_tooltip("keen_eyes").next_level, 0)


func test_real_cache_confirms_all_eight_levels_and_passive_icons() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/400.img")
	assert_true(img != null)
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"400": img.root})
	var expected := [25, 50, 75, 100, 125, 150, 175, 200]
	assert_eq(book.max_level("keen_eyes"), 8)
	for i in expected.size():
		assert_near(book.canonical("keen_eyes", i + 1, "range"), expected[i])
	for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
		assert_true(lib.frame(book.wz_path("keen_eyes") + "/" + suffix) != null)
	assert_eq(Array(lib.missing), [])
	lib.free()
