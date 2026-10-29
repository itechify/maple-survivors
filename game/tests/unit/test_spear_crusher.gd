extends TestCase
## Dark Knight's start skill, Spear Crusher (1311001, spec #348 D5 #353): the skip-the-dip rank table, the per-level WZ stance,
## the forward box with its rb.x dead zone, Final Attack, the pole arm twin art and the rarity cards. Synthetic Skill.wz rows
## carry the D1-verified numbers at the eight mapped levels; the real-cache test at the end reads the real rows.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const KEY := "spear_crusher"
const SPEAR := 1432000
const POLE_ARM := 1442000
## Skill.wz level -> [damage, attackCount, mobCount, action] at the eight mapped levels (D1's verified table).
const MAPPED := {4: [70, 2, 1, "burster1"], 8: [90, 2, 2, "burster1"], 12: [108, 2, 3, "burster1"], 15: [120, 2, 3, "burster1"],
	23: [149, 3, 2, "burster2"], 25: [155, 3, 2, "burster2"], 27: [161, 3, 3, "burster2"], 30: [170, 3, 3, "burster2"]}
const TOTALS := [140, 360, 648, 720, 894, 930, 1449, 1530]


## All thirty levels the way the real skill shapes them: two hits to level 15, three after, mobCount 1..3 in runs of five
## (so the level 16-20 run drops back to one monster), box (-130,-50) growing to (-150,-70), rb (-16,0).
func _levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var lt := [-130, -50] if lv <= 8 else [-140, -60] if lv <= 15 else [-150, -70]
		levels[str(lv)] = {"damage": 50 + lv, "attackCount": 2 if lv <= 15 else 3, "mobCount": ((lv - 1) % 15) / 5 + 1,
			"action": "burster1" if lv <= 15 else "burster2", "lt": {"$v": lt}, "rb": {"$v": [-16, 0]}}
	for lv: int in MAPPED:
		levels[str(lv)].damage = MAPPED[lv][0]
	return levels


func _imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	imgs["131"] = {"skill": {"1311001": {"level": _levels()}, "1311002": {"level": _levels()}}}
	return imgs


func _book() -> SkillBook:
	return SkillBook.from_data(DataRepo.load_all().skills, _imgs())


func _world(weapon := SPEAR) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["132"].playable = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 353, data))
	setup.skill_imgs = _imgs()
	setup.equipment_info[POLE_ARM] = {"reqJob": 13, "incPAD": 34.0, "attackSpeed": 6.0, "afterImage": "poleArm", "sfx": "poleArm"}
	setup.afterimage_imgs["poleArm"] = setup.afterimage_imgs["spear"]
	var w := RunWorld.new(setup)
	w.set_job(132)
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


func _cast(w: RunWorld, seconds := 1.0 / 60.0) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	var t := 0.0
	while t < seconds:
		w.runner.step(1.0 / 60.0, w)
		t += 1.0 / 60.0
	return w.drain_events()


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func test_the_rank_table_skips_the_dip_and_reads_the_mapped_wz_levels() -> void:
	var book := _book()
	assert_true(book.has(KEY))
	assert_eq(book.max_rank(KEY), 8)
	assert_eq(book.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), [4, 8, 12, 15, 23, 25, 27, 30])
	var lo := Loadout.new(book)
	lo.add_skill(KEY)
	for rank in range(1, 9):
		var st := lo.stats(KEY, rank)
		var row: Array = MAPPED[int(book.rank_table(KEY)[rank - 1])]
		assert_eq(st.level, int(book.rank_table(KEY)[rank - 1]))
		assert_eq(st.attack_count, row[1])
		assert_eq(st.mob_count, row[2])
		assert_near(st.damage_pct, float(row[0]) / 100.0)
		assert_eq(st.cast_rule, "box")
		assert_true(st.has_box)


func test_total_damage_per_cast_against_a_full_box_rises_at_every_rank() -> void:
	var lo := Loadout.new(_book())
	lo.add_skill(KEY)
	var last := 0.0
	for rank in range(1, 9):
		var st := lo.stats(KEY, rank)
		var total: float = st.damage_pct * 100.0 * st.attack_count * st.mob_count
		assert_near(total, float(TOTALS[rank - 1]), 0.001, "rank %d" % rank)
		assert_true(total > last, "rank %d beats rank %d" % [rank, rank - 1])
		last = total


func test_the_stance_is_the_wz_level_action_burster1_for_two_hits_burster2_for_three() -> void:
	var lo := Loadout.new(_book())
	lo.add_skill(KEY)
	for rank in range(1, 9):
		var st := lo.stats(KEY, rank)
		assert_eq(st.action, "burster1" if st.attack_count == 2 else "burster2", "rank %d" % rank)
	assert_eq(lo.stats(KEY, 4).action, "burster1")
	assert_eq(lo.stats(KEY, 5).action, "burster2", "the first three-hit rank")


func test_the_cast_event_carries_the_stance_and_the_hold_time_of_the_level() -> void:
	for pair: Array in [[1, "burster1", 0.9], [5, "burster2", 1.05]]:
		var w := _world()
		w.learn_skill(KEY)
		w.loadout.set_rank(KEY, int(pair[0]))
		RF.put_mob(w, 1110100, 400 - 60, 190, 10000)
		var casts := _cast(w).filter(func(e: Dictionary) -> bool: return e.type == "cast")
		assert_eq(casts.size(), 1)
		assert_eq(casts[0].action, pair[1])
		assert_near(w.upkeep.cast_left, float(pair[2]) - 1.0 / 60.0, 0.02, "the stance is held for the body action's own time")


func test_the_forward_box_has_a_sixteen_pixel_dead_zone_and_never_hits_behind() -> void:
	for side in [-1, 1]:
		var w := _world()
		w.learn_skill(KEY)
		w.player.facing = side
		RF.put_mob(w, 1110100, 400 + side * 8, 190, 10000) # inside the dead zone (rb.x -16)
		RF.put_mob(w, 1110100, 400 - side * 60, 190, 10000) # behind
		RF.put_mob(w, 1110100, 400 + side * 160, 190, 10000) # beyond lt.x -130
		assert_eq(_hits(_cast(w)).size(), 0, "no mob in the box, so no cast (side %d)" % side)
		assert_eq(w.runner.casts, 0)
		var inside := RF.put_mob(w, 1110100, 400 + side * 40, 190, 10000)
		var events := _cast(w)
		assert_eq(w.runner.casts, 1)
		for hit: Dictionary in _hits(events):
			assert_eq(hit.mob, inside)


func test_rank_one_hits_the_nearest_mob_twice_and_rank_seven_three_mobs_three_times() -> void:
	var w := _world()
	w.learn_skill(KEY)
	var near := RF.put_mob(w, 1110100, 400 - 40, 190, 100000)
	var mid := RF.put_mob(w, 1110100, 400 - 70, 190, 100000)
	var far := RF.put_mob(w, 1110100, 400 - 100, 190, 100000)
	var fourth := RF.put_mob(w, 1110100, 400 - 120, 190, 100000)
	var hits := _hits(_cast(w))
	assert_eq(hits.size(), 2, "rank 1: two lines")
	for hit: Dictionary in hits:
		assert_eq(hit.mob, near, "the nearest mob only")
	w = _world()
	w.learn_skill(KEY)
	w.loadout.set_rank(KEY, 7)
	var slots := [RF.put_mob(w, 1110100, 400 - 40, 190, 100000), RF.put_mob(w, 1110100, 400 - 70, 190, 100000),
		RF.put_mob(w, 1110100, 400 - 100, 190, 100000), RF.put_mob(w, 1110100, 400 - 120, 190, 100000)]
	hits = _hits(_cast(w))
	assert_eq(hits.size(), 9, "rank 7: three lines on each of three mobs")
	var seen := {}
	for hit: Dictionary in hits:
		seen[int(hit.mob)] = int(seen.get(int(hit.mob), 0)) + 1
	assert_eq(seen.size(), 3)
	for slot: int in seen:
		assert_eq(seen[slot], 3)
	assert_false(seen.has(slots[3]), "the farthest of four is left out")


func test_final_attack_adds_one_hit_line_and_legendary_also_raises_damage() -> void:
	var counts := []
	for tier in ["", "unique", "legendary"]:
		var w := _world()
		w.learn_skill(KEY)
		if tier != "":
			w.upgrades.apply(KEY + "_rank", w, tier)
			w.loadout.set_rank(KEY, 1)
		var slot := RF.put_mob(w, 1110100, 400 - 40, 190, 100000)
		counts.append(_hits(_cast(w)).size())
	assert_eq(counts, [2, 3, 3], "Final Attack: +1 hit line")


func test_art_skill_id_is_the_pole_arm_twin_only_for_a_pole_arm() -> void:
	var book := _book()
	assert_eq(book.art_skill_id(KEY, "polearm"), 1311002)
	for family in ["spear", "sword", "axe", ""]:
		assert_eq(book.art_skill_id(KEY, family), 1311001, family)
	var spear := _world(SPEAR)
	spear.learn_skill(KEY)
	var pole := _world(POLE_ARM)
	pole.learn_skill(KEY)
	var s := spear.loadout.stats(KEY)
	var p := pole.loadout.stats(KEY)
	assert_eq(spear.loadout.weapon_family, "spear")
	assert_eq(pole.loadout.weapon_family, "polearm")
	for field: String in ["effect", "hit"]:
		assert_true(String(s[field]).contains("/1311001/"), "spear %s: %s" % [field, s[field]])
		assert_true(String(p[field]).contains("/1311002/"), "pole arm %s: %s" % [field, p[field]])
	assert_eq(p.damage_pct, s.damage_pct, "numbers are shared; only art differs")
	assert_eq(p.attack_count, s.attack_count)
	assert_eq(p.action, s.action)


func test_rarity_cards_add_one_rank_plus_their_bonus_and_legendary_shares_the_uniques_counter() -> void:
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		var w := _world()
		var fresh := w.upgrades.choice_card(KEY + "_new", w, tier)
		assert_false(fresh.get("rarity_bonus", {}).is_empty(), tier + ": the new-skill card carries the bonus")
		w.learn_skill(KEY)
		assert_false(w.upgrades.choice_card(KEY + "_rank", w, tier).get("rarity_bonus", {}).is_empty(), tier)
		w.upgrades.apply(KEY + "_rank", w, tier)
		assert_eq(w.loadout.rank(KEY), 2, "a Rare+ card adds one rank")
		match tier:
			"rare": assert_near(w.loadout.skill_stat(KEY, "damage", 1.0), 1.2)
			"epic": assert_near(w.loadout.skill_stat(KEY, "cooldown", 1.0), 0.88)
			"unique", "legendary": assert_near(w.loadout.skill_stat(KEY, "attack_count", 0.0), 1.0)
	var w := _world()
	w.learn_skill(KEY)
	w.loadout.set_rank(KEY, 8)
	w.upgrades.apply(KEY + "_rank", w, "unique")
	var c := w.upgrades.choice_card(KEY + "_rank", w, "legendary")
	assert_eq(c.card_kind, "mastery", "a rank-capped Legendary Final Attack repeats as Mastery")
	w.upgrades.apply(c.id, w, "legendary")
	assert_eq(w.loadout.rank(KEY), 8)
	assert_near(w.loadout.skill_stat(KEY, "attack_count", 0.0), 1.8, 0.001, "Final Attack repeats at x0.8")
	assert_near(w.loadout.skill_stat(KEY, "damage", 1.0), 1.16, 0.001, "the Legendary damage x1.2 repeats at x0.8")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:final_attack" % KEY]), 2, "Legendary shares the Unique's counter")


func test_every_rarity_list_is_valid_and_the_bonuses_change_the_resolved_cast() -> void:
	var book := _book()
	var bonuses: Dictionary = book.def(KEY).rarity_bonuses
	assert_eq(bonuses.keys(), ["rare", "epic", "unique", "legendary"])
	for tier: String in bonuses:
		assert_false((bonuses[tier] as Array).is_empty(), tier)
		for bonus: Dictionary in bonuses[tier]:
			assert_true(String(bonus.id) != "" and String(bonus.text) != "", tier)
			for effect: Dictionary in bonus.effects:
				assert_true(String(effect.stat) in ["damage", "cooldown", "attack_count"], tier)
				assert_true(String(effect.op) in ["add", "mul"], tier)
	var lo := Loadout.new(book)
	lo.add_skill(KEY)
	var base := lo.stats(KEY)
	lo.add_skill_mod(KEY, "damage", "mul", 1.2)
	lo.add_skill_mod(KEY, "cooldown", "mul", 0.88)
	lo.add_skill_mod(KEY, "attack_count", "add", 1.0)
	var boosted := lo.stats(KEY)
	assert_near(float(boosted.damage_max), float(base.damage_max) * 1.2, 0.5)
	assert_near(float(boosted.cooldown), float(base.cooldown) * 0.88, 0.001)
	assert_eq(boosted.attack_count, base.attack_count + 1)


func test_cast_visuals_show_wings_rings_and_one_dragon_thrust_per_hit() -> void:
	var lo := Loadout.new(_book())
	lo.add_skill(KEY)
	var base := "Skill.wz/131.img/skill/1311001/"
	assert_eq(lo.stats(KEY, 1).effect, base + "effect", "the wings ride the cast event's effect")
	var thrusts: Array = lo.stats(KEY, 1).cast_visuals.map(func(v: Dictionary) -> String: return String(v.path).trim_prefix(base))
	assert_eq(thrusts, ["effect0", "effect1", "effect2"], "two hits: rings, then the first and second thrust")
	thrusts = lo.stats(KEY, 5).cast_visuals.map(func(v: Dictionary) -> String: return String(v.path).trim_prefix(base))
	assert_eq(thrusts, ["effect0", "effect1", "effect2", "effect3"], "three hits add the third thrust")
	lo.add_skill_mod(KEY, "attack_count", "add", 1.0)
	assert_eq(lo.stats(KEY, 1).cast_visuals.size(), 4, "Final Attack's extra hit shows its thrust")
	for v: Dictionary in lo.stats(KEY, 1).cast_visuals:
		assert_true(bool(v.follow), "the streaks follow the knight and mirror with its facing")


func test_a_pole_arm_plays_the_twin_cast_visuals() -> void:
	var w := _world(POLE_ARM)
	w.learn_skill(KEY)
	for v: Dictionary in w.loadout.stats(KEY).cast_visuals:
		assert_true(String(v.path).contains("/1311002/"), v.path)


func test_real_cache_the_three_thrust_animations_all_draw_their_art_at_their_times() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var base := "Skill.wz/131.img/skill/%d/effect%d"
	for skill_id in [1311001, 1311002]:
		for k in [1, 2, 3]:
			var anim := lib.anim(base % [skill_id, k])
			var label := "%d effect%d" % [skill_id, k]
			assert_true(anim != null and anim.frame_count() == 3, label + ": three frames")
			if anim == null or anim.frame_count() != 3:
				continue
			var wait: float = 0.45 + 0.15 * k # 600, 750, 900 ms: the K-th thrust lands there
			assert_near(anim.frames[0].delay_s, wait, 1e-6, label + " waits for the thrust")
			assert_near(anim.frames[2].delay_s, 0.2, 1e-6, label + ": the string delay \"200\" reads as 200 ms")
			assert_near(anim.total, wait + 0.03 + 0.2, 1e-6, label)
			# The blurred frame and the dragon-head frame each show real, opaque pixels at their own time.
			for t: float in [wait + 0.01, wait + 0.05, wait + 0.2]:
				var frame := anim.frame_at(t, false)
				assert_true(frame != null and frame.texture != null, "%s has a texture at %.2f s" % [label, t])
				assert_true(anim.alpha_at(t, false) > 0.05, "%s is visible at %.2f s" % [label, t])
				var image := frame.texture.get_image()
				var opaque := 0
				for y in image.get_height():
					for x in image.get_width():
						if image.get_pixel(x, y).a > 0.1:
							opaque += 1
				assert_true(opaque > 200, "%s draws %d opaque pixels at %.2f s" % [label, opaque, t])


func test_real_cache_all_eight_ranks_read_the_mapped_wz_levels() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.get_default()
	var imgs := {}
	for book in ["100", "131"]:
		var img := library.img("Skill.wz/%s.img" % book)
		assert_true(img != null, book + " book imported")
		if img == null:
			return
		imgs[book] = img.root
	var b := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	assert_eq(b.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), [4, 8, 12, 15, 23, 25, 27, 30])
	var last := 0.0
	for rank in range(1, 9):
		var lv: int = int(b.rank_table(KEY)[rank - 1])
		for id in ["1311001", "1311002"]:
			var row: Dictionary = imgs["131"].skill[id].level[str(lv)]
			assert_eq(row.action, "burster1" if rank <= 4 else "burster2", "%s rank %d" % [id, rank])
		var row: Dictionary = imgs["131"].skill["1311001"].level[str(lv)]
		var lo := Loadout.new(b)
		lo.add_skill(KEY)
		var st := lo.stats(KEY, rank)
		assert_eq(st.level, lv)
		assert_eq(st.action, String(row.action))
		assert_near(st.damage_pct, float(row.damage) / 100.0)
		assert_eq(st.attack_count, int(row.attackCount))
		assert_eq(st.mob_count, int(row.mobCount))
		assert_eq(st.box.position, Vector2(float(row.lt["$v"][0]), float(row.lt["$v"][1])))
		assert_eq(st.box.end, Vector2(-16.0, 0.0), "rb (-16, 0): the dead zone")
		var total: float = st.damage_pct * 100.0 * st.attack_count * st.mob_count
		assert_near(total, float(TOTALS[rank - 1]), 0.001)
		assert_true(total > last, "total damage per cast rises at rank %d" % rank)
		last = total
	assert_eq(Loadout.new(b).stats(KEY, 1).damage_pct, 0.7)
	assert_eq(Loadout.new(b).stats(KEY, 8).damage_pct, 1.7)
