extends TestCase
## Drain (#213): seeded resolved hits, projectile casts, healing limits and Assassin cards.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.stats = {"str": 4, "dex": 30, "int": 4, "luk": 100}
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 213, data))
	setup.equipment_info[1472008] = {"incPAD": 18, "attackSpeed": 4, "tuc": 7}
	setup.equipment_info[1332063] = {"incPAD": 28, "attackSpeed": 3, "tuc": 7}
	var w := RunWorld.new(setup)
	w.change_job(400, "claw")
	w.progression.level = 30
	w.change_job(410)
	RF.place_player(w, 400)
	w.god = true
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	w.heal_fraction("hp", 1)
	w.spend_hp(int(w.player_state.hp) - 1)
	w.drain_events()
	return w


func _hit(w: RunWorld, slot: int, damage: int, level: int, key := "drain") -> void:
	w.hit_mob(slot, {"skill": key, "level": level, "damage_type": "fixed", "damage_min": damage,
		"damage_max": damage, "crit": 0.0, "crit_mult": 1.5}, -1)


func test_each_drain_hit_restores_its_canonical_fraction_of_resolved_damage() -> void:
	for example: Array in [[1, 100, 16], [30, 100, 45], [1, 99, 15]]:
		var w := _world()
		assert_true(w.learn_skill("drain"))
		if not w.book.has("drain"):
			return
		var target := RF.put_mob(w, 1110100, 500, 190, 1000)
		_hit(w, target, example[1], example[0])
		assert_eq(w.player_state.hp, 1 + example[2])
		var gains := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_restored")
		assert_eq(gains.size(), 1)
		assert_eq(gains[0].stat, "hp")
		assert_eq(gains[0].amount, example[2])
		assert_eq(gains[0].skill, "drain")


func test_healing_caps_each_hit_at_half_character_max_hp_and_target_max_hp() -> void:
	var w := _world()
	w.learn_skill("drain")
	var target := RF.put_mob(w, 1110100, 500, 190, 1000)
	var half := floori(float(w.player_state.max_hp) / 2.0)
	_hit(w, target, 10000, 30)
	assert_eq(w.player_state.hp, 1 + half, "character MaxHP/2 cap")
	w.spend_hp(int(w.player_state.hp) - 1)
	var small := RF.put_mob(w, 1110100, 550)
	w.swarm.max_hp[small] = 37
	w.swarm.hp[small] = 2
	_hit(w, small, 10000, 30)
	assert_eq(w.player_state.hp, 38, "target MaxHP, even on an overkill; current HP does not set the cap")
	w.heal_fraction("hp", 1)
	w.spend_hp(3)
	_hit(w, target, 100, 30)
	assert_eq(w.player_state.hp, w.player_state.max_hp, "restore clamps at missing HP")


func test_other_skills_do_not_heal() -> void:
	var w := _world()
	w.learn_skill("drain")
	var target := RF.put_mob(w, 1110100, 500, 190, 1000)
	_hit(w, target, 100, 1, "lucky_seven")
	assert_eq(w.player_state.hp, 1)


func test_assassin_cards_learn_rank_and_add_three_pierce_steps() -> void:
	var w := _world()
	assert_has(w.upgrades.eligible(w), "drain_new")
	w.upgrades.apply("drain_new", w)
	assert_eq(w.loadout.rank("drain"), 1)
	w.upgrades.apply("drain_rank", w)
	assert_eq(w.loadout.level("drain"), 2)
	for step in range(1, 4):
		assert_has(w.upgrades.eligible(w), "drain_pierce")
		w.upgrades.apply("drain_pierce", w)
		assert_eq(w.loadout.stats("drain").pierce, step)
	assert_false("drain_pierce" in w.upgrades.eligible(w))
	w.loadout.set_rank("drain", 30)
	assert_false("drain_rank" in w.upgrades.eligible(w))
	for job in [400, 420]:
		w = _world()
		w.progression.job_id = job
		assert_false(w.upgrades.is_eligible(w.upgrades.card("drain_new"), w))
		w.learn_skill("drain")
		for id in ["drain_rank", "drain_pierce"]:
			assert_false(w.upgrades.is_eligible(w.upgrades.card(id), w))


func test_drain_needs_a_claw_and_uses_the_current_star_at_every_assassin_tier() -> void:
	for tier in range(6):
		var w := _world()
		w.progression.level = 30 + 5 * tier
		w.refresh_player_stats(false)
		w.learn_skill("drain")
		RF.put_mob(w, 1110100, 500, 190, 1000)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.equipment.inventory.append(Equipment.create(1332063, w.setup.equipment_info[1332063]))
		var dagger: int = w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id)).find(1332063)
		assert_eq(w.equip_item(dagger), "")
		var mp: int = w.player_state.mp
		w.runner.step(DT, w)
		assert_eq(w.projectiles.active_count(), 0)
		assert_eq(w.player_state.mp, mp)
		assert_false("drain_new" in w.upgrades.eligible(w))
		var claw: int = w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id)).find(1472008)
		assert_eq(w.equip_item(claw), "")
		w.runner.step(DT, w)
		assert_eq(w.projectiles.active_count(), 1)
		assert_eq(w.player_state.mp, mp - 12)
		for i in w.projectiles.capacity():
			if w.projectiles.active[i] != 0:
				assert_eq(w.projectiles.paths[w.projectiles.visual[i]],
					"Item.wz/Consume/0207.img/%08d/bullet" % (2070001 + tier))


func test_one_piercing_star_heals_per_impact_using_launch_rank_and_resolved_physical_damage() -> void:
	var w := _world()
	w.learn_skill("drain")
	w.loadout.set_rank("drain", 30)
	for step in 3:
		w.upgrades.apply("drain_pierce", w)
	w.basic.cooldown = 60
	for x in [480, 495, 510, 525]:
		var target := RF.put_mob(w, 1110100, x, 190, 1000)
		w.mob_kinds[w.swarm.kind[target]].pdd = 20
	w.step(DT, MoveInput.new())
	assert_eq(w.projectiles.active_count(), 1)
	w.loadout.set_rank("drain", 1) # the flying star retains rank30
	w.runner.cooldowns.drain = 60
	for tick in 30:
		w.step(DT, MoveInput.new())
	var events := w.drain_events()
	var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == "drain")
	var gains := events.filter(func(e: Dictionary) -> bool: return e.type == "player_restored" and e.skill == "drain")
	assert_eq(hits.size(), 4, "three pierce steps reach four monsters")
	assert_eq(gains.size(), 4, "each impact heals")
	var total := 0
	for i in mini(hits.size(), gains.size()):
		var heal := floori(float(hits[i].damage) * 0.45)
		assert_true(heal > 0)
		assert_eq(gains[i].amount, heal, "45% of the actual post-defence/crit hit, not the pre-defence range")
		total += heal
	assert_eq(w.player_state.hp, 1 + total)


func test_original_drain_tables_art_sound_and_tooltip_resolve_from_the_read_only_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"410": lib.img("Skill.wz/410.img").root})
	var synthetic := SkillBook.from_data(DataRepo.load_all().skills, RF.skill_imgs())
	assert_eq(book.max_level("drain"), 30)
	assert_eq(book.weapon_families("drain"), PackedStringArray(["claw"]))
	for lv in range(1, 31):
		for field in ["damage", "mpCon", "x"]:
			assert_eq(synthetic.canonical("drain", lv, field), book.canonical("drain", lv, field), "%s rank%d" % [field, lv])
	assert_true(lib.node(String(book.def("drain").icon)) != null)
	assert_false(lib.anim(String(book.def("drain").effect)).is_empty())
	assert_true(lib.sound(String(book.def("drain").sounds.use)) != null)
	var lo := Loadout.new(book)
	assert_eq(SkillText.new(book, {}).level_line("drain", 30, lo.stats("drain", 30)),
		"MP -24; Damage 160%, absorb 45% of damage as HP.")
	assert_eq(Array(lib.missing), [])
	lib.free()
