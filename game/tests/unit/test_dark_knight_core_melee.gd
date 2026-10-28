extends TestCase
## Dark Knight shares Hero's Power Strike and Slash Blast (spec #348 DK-13, ticket D5 #353): the same definitions, rank
## tables, rarity lists and hit lines, with the reach and the body stance of a held Spear or Pole Arm; and Hero's Combo
## meter does nothing for a Dark Knight. Synthetic boxes make the spear's and the pole arm's reach differ.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const SPEAR := 1432000
const POLE_ARM := 1442000
const SHARED := ["power_strike", "slash_blast"]
## Afterimage boxes [lt, rb] of the stances WeaponInfo.basic_actions lists for each weapon type (feet-relative, facing left).
const SPEAR_BOXES := {"stabT1": [[-110, -30], [-10, 10]], "stabT2": [[-120, -30], [-10, 10]], "swingP1": [[-150, -50], [-10, 10]]}
const POLE_BOXES := {"swingP1": [[-200, -60], [-20, 10]], "swingP2": [[-190, -60], [-20, 10]], "swingT2": [[-210, -60], [-20, 10]]}


func _images(boxes: Dictionary) -> Dictionary:
	var out := {"0": {}}
	for action: String in boxes:
		out["0"][action] = {"lt": {"$v": boxes[action][0]}, "rb": {"$v": boxes[action][1]},
			"2": {"0": {"$canvas": [0, 0, 0, 40, 30], "delay": 200.0}}}
	return out


func _world(weapon: int, job := 132) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["132"].playable = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 353, data))
	setup.equipment_info[SPEAR] = {"reqJob": 13, "incPAD": 32.0, "attackSpeed": 8.0, "afterImage": "spear", "sfx": "spear"}
	setup.equipment_info[POLE_ARM] = {"reqJob": 13, "incPAD": 34.0, "attackSpeed": 6.0, "afterImage": "poleArm", "sfx": "poleArm"}
	for action: String in ["stabT1", "stabT2", "swingP1", "swingP2", "swingT2"]:
		setup.body_img[action] = {"0": {"delay": 300.0}, "1": {"delay": 150.0}, "2": {"delay": 350.0}}
	setup.afterimage_imgs["spear"] = _images(SPEAR_BOXES)
	setup.afterimage_imgs["poleArm"] = _images(POLE_BOXES)
	var w := RunWorld.new(setup)
	w.set_job(job)
	if weapon > 0:
		w.equipment.worn.weapon = Equipment.create(weapon, {"incPAD": 32})
	w.refresh_player_stats()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.player.facing = -1
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	return w


func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(1.0 / 60.0, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_dark_knight_resolves_heros_definitions_not_its_own() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var hero_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivor/skills/hero.json")).skills
	var dk_file: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivor/skills/dark_knight.json")).skills
	var book := SkillBook.from_data(DataRepo.load_all().skills, RF.skill_imgs())
	for key: String in SHARED:
		assert_true(hero_file.has(key), key + " is Hero's")
		assert_false(dk_file.has(key), key + " is never redefined for Dark Knight (DK-13)")
		assert_true(key in DataRepo.load_all().jobs_survivor.jobs["132"].skill_pool, key + " is in the pool")
		assert_eq(skills[key].rarity_bonuses, hero_file[key].rarity_bonuses, key + ": Hero's rarity lists")
		assert_eq(book.max_rank(key), 8)
		assert_eq(book.rank_table(key).map(func(v: Variant) -> int: return int(v)), [3, 5, 8, 10, 13, 15, 18, 20], key)


func test_rarity_cards_work_for_a_dark_knight_holding_a_spear_or_a_pole_arm() -> void:
	for weapon: int in [SPEAR, POLE_ARM]:
		for key: String in SHARED:
			for tier: String in ["rare", "epic", "unique", "legendary"]:
				var w := _world(weapon)
				w.learn_skill(key)
				var card := w.upgrades.choice_card(key + "_rank", w, tier)
				assert_false(card.get("rarity_bonus", {}).is_empty(), "%s %s" % [key, tier])
				w.upgrades.apply(key + "_rank", w, tier)
				assert_eq(w.loadout.rank(key), 2, "%s %s: one rank" % [key, tier])
				match tier:
					"rare": assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2)
					"epic": assert_near(w.loadout.skill_stat(key, "cooldown" if key == "power_strike" else "area", 1.0),
						0.88 if key == "power_strike" else 1.2)
					_: assert_near(w.loadout.skill_stat(key, "attack_count", 0.0), 1.0)


func test_power_strike_takes_the_stance_and_reach_of_the_held_weapon() -> void:
	for case: Array in [[SPEAR, "stabT1", 150.0, 140.0], [POLE_ARM, "swingP1", 210.0, 200.0]]:
		var w := _world(int(case[0]))
		w.learn_skill("power_strike")
		assert_near(SkillRunner.reach_of(w.loadout.stats("power_strike"), w), float(case[2]), 0.01, "reach of %d" % case[0])
		var near := RF.put_mob(w, 1110100, 400 - 60, 190, 100000)
		RF.put_mob(w, 1110100, 400 - 90, 190, 100000)
		var events := _cast(w)
		assert_eq(_of(events, "cast").size(), 1)
		assert_eq(_of(events, "cast")[0].action, case[1])
		var hits := _of(events, "mob_hit")
		assert_eq(hits.size(), 1, "one line on the nearest mob")
		assert_eq(hits[0].mob, near)
		w = _world(int(case[0]))
		w.learn_skill("power_strike")
		var inside := RF.put_mob(w, 1110100, 400 - float(case[3]), 190, 100000)
		assert_eq(_of(_cast(w), "mob_hit").size(), 1, "a mob at %d px is inside the %s reach" % [case[3], case[1]])
		assert_true(w.swarm.hp[inside] < w.swarm.max_hp[inside])
	# Reach separates the two weapons: a mob 190 px away is only inside the pole arm's envelope.
	var hits_at_190 := []
	for weapon: int in [SPEAR, POLE_ARM]:
		var w := _world(weapon)
		w.learn_skill("power_strike")
		RF.put_mob(w, 1110100, 400 - 190, 190, 100000)
		hits_at_190.append(_of(_cast(w), "mob_hit").size())
	assert_eq(hits_at_190, [0, 1])


func test_slash_blast_hits_every_mob_around_with_either_weapon_and_the_matching_stance() -> void:
	for pair: Array in [[SPEAR, "stabT1"], [POLE_ARM, "swingP1"]]:
		var w := _world(int(pair[0]))
		w.learn_skill("slash_blast")
		w.player.facing = 1
		var around := [RF.put_mob(w, 1110100, 400 - 60, 190, 100000), RF.put_mob(w, 1110100, 400 + 80, 190, 100000)]
		RF.put_mob(w, 1110100, 400 - 400, 190, 100000)
		var events := _cast(w)
		assert_eq(_of(events, "cast")[0].action, pair[1])
		var struck := {}
		for hit: Dictionary in _of(events, "mob_hit"):
			struck[int(hit.mob)] = true
		assert_eq(struck.size(), 2, "both mobs in range, in front and behind")
		for slot: int in around:
			assert_true(struck.has(slot))
		assert_true(_of(events, "hp_spent").size() <= 1)


func test_the_combo_meter_does_nothing_for_a_dark_knight() -> void:
	var dk := _world(SPEAR)
	dk.learn_skill("power_strike")
	assert_true(dk.meter.config.is_empty(), "no meter config for job 132")
	assert_eq(dk.meter.snapshot(), {})
	var st := dk.loadout.stats("power_strike")
	assert_true(is_same(dk.meter.begin_cast(dk, "power_strike", st), st), "the cast stats pass through untouched")
	RF.put_mob(dk, 1110100, 400 - 60, 190, 1000000)
	var meter_events := 0
	for i in 40:
		dk.runner.cooldowns.erase("power_strike")
		meter_events += _of(_cast(dk), "meter_changed").size()
	assert_true(dk.runner.casts >= 10, "many landed casts: %d" % dk.runner.casts)
	assert_eq(meter_events, 0)
	assert_eq(dk.meter.value, 0)
	# The same loop does move Hero's meter, so the check above can fail.
	var data := RF.quiet_data()
	var setup := RF.with_basic_attack(RF.setup("quiet", 353, data))
	var hero := RunWorld.new(setup)
	hero.set_job(112)
	hero.loadout.ranks.clear()
	hero.loadout.order.clear()
	hero.learn_skill("power_strike")
	RF.place_player(hero, 400)
	hero.player.facing = -1
	hero.god = true
	for mk: MobKind in hero.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	RF.put_mob(hero, 1110100, 400 - 60, 190, 1000000)
	var hero_events := 0
	for i in 40:
		hero.runner.cooldowns.erase("power_strike")
		hero_events += _of(_cast(hero), "meter_changed").size()
	assert_true(hero_events > 0, "Hero's Combo orbs do change")
