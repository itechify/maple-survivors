extends TestCase
## Hero core melee: deterministic cast geometry, WZ rank mapping, and public rarity-card behavior.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const KEYS := ["power_strike", "slash_blast", "brandish"]

func test_core_catalog_has_eight_ranks_and_no_weapon_gate() -> void:
	var book := SkillBook.from_data(DataRepo.load_all().skills, _imgs())
	for key: String in KEYS:
		assert_true(book.has(key), key)
		assert_eq(book.max_rank(key), 8, key)
		assert_true(book.weapon_families(key).is_empty(), key)
		assert_eq(book.def(key).get("slot"), "active")

func test_rarity_cards_add_one_rank_and_mastery_shares_diminishing_final_attack() -> void:
	for key: String in KEYS:
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			var w := _world()
			w.set_job(112)
			var id := key + ("_rank" if w.loadout.has(key) else "_new")
			var before := w.loadout.rank(key)
			var c := w.upgrades.choice_card(id, w, tier)
			assert_false(c.get("rarity_bonus", {}).is_empty(), key + tier)
			w.upgrades.apply(id, w, tier)
			assert_eq(w.loadout.rank(key), before + 1)
			match tier:
				"rare": assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2)
				"epic":
					var stat: String = {"power_strike":"cooldown", "slash_blast":"area", "brandish":"count"}[key]
					assert_near(w.loadout.skill_stat(key, stat, 1.0), {"power_strike":0.88,"slash_blast":1.2,"brandish":2.0}[key])
				"unique", "legendary": assert_near(w.loadout.skill_stat(key, "attack_count", 0.0), 1.0)
		var w := _world()
		w.set_job(112)
		w.learn_skill(key)
		w.loadout.set_rank(key, 8)
		w.upgrades.apply(key + "_rank", w, "unique")
		var c := w.upgrades.choice_card(key + "_rank", w, "legendary")
		assert_eq(c.card_kind, "mastery")
		w.upgrades.apply(c.id, w, "legendary")
		assert_eq(w.loadout.rank(key), 8)
		assert_near(w.loadout.skill_stat(key, "attack_count", 0.0), 1.8)
		assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.16)
		assert_eq(int(w.loadout.card_ranks["bonus:%s:final_attack" % key]), 2)

## Synthetic Brandish endpoints and fixed geometry; real-cache test below checks every mapped WZ row.
func _imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 150, "attackCount": 2, "mobCount": 1,
			"lt": {"$v": [-150, -110]}, "rb": {"$v": [-10, 0]}}
	imgs["112"] = {"skill": {"1121008": {"level": levels}}}
	return imgs

func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"].playable = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 301, data))
	setup.skill_imgs = _imgs()
	var w := RunWorld.new(setup)
	w.set_job(112)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	return w

func test_brandish_forward_box_hits_two_lines_and_uses_held_handedness() -> void:
	for pair: Array in [[1302000, "brandish1", "0"], [1312004, "brandish1", "0"], [1402001, "brandish2", "1"], [1412000, "brandish2", "1"]]:
		for side in [-1, 1]:
			var w := _world()
			w.equipment.worn.weapon = Equipment.create(int(pair[0]), {"incPAD": 17})
			w.refresh_player_stats()
			w.learn_skill("brandish")
			w.player.facing = side
			var behind := RF.put_mob(w, 1110100, 400 - side * 50, 190, 10000)
			var beyond := RF.put_mob(w, 1110100, 400 + side * 180, 190, 10000)
			var near := RF.put_mob(w, 1110100, 400 + side * 50, 190, 10000)
			var extra := RF.put_mob(w, 1110100, 400 + side * 100, 190, 10000)
			w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
			w.drain_events()
			w.runner.step(1.0 / 60.0, w)
			var events := w.drain_events()
			var casts := events.filter(func(e: Dictionary) -> bool: return e.type == "cast")
			var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
			assert_eq(casts.size(), 1)
			assert_eq(casts[0].action, pair[1])
			assert_eq(casts[0].effect, "Skill.wz/112.img/skill/1121008/effect/" + pair[2])
			assert_eq(hits.size(), 2, "two damage lines, one target at rank 1")
			for hit: Dictionary in hits:
				assert_eq(hit.mob, near)
			for slot: int in [behind, beyond, extra]:
				assert_eq(w.swarm.hp[slot], w.swarm.max_hp[slot])

func test_real_cache_core_ranks_read_the_mapped_wz_rows() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var imgs := {}
	for book in ["100", "112"]:
		var img := library.img("Skill.wz/%s.img" % book)
		assert_true(img != null, book + " book imported")
		if img == null:
			library.free()
			return
		imgs[book] = img.root
	var b := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	for key: String in KEYS:
		var table := [4, 8, 12, 15, 19, 23, 27, 30] if key == "brandish" else [3, 5, 8, 10, 13, 15, 18, 20]
		assert_eq(b.rank_table(key).map(func(v: Variant) -> int: return int(v)), table)
		for rank in range(1, 9):
			var lv: int = table[rank - 1]
			assert_eq(b.canonical_level(key, rank), lv)
			var row: Dictionary = imgs[String(b.def(key).book)].skill[str(b.skill_id(key))].level[str(lv)]
			var lo := Loadout.new(b)
			lo.add_skill(key)
			var st := lo.stats(key, rank)
			assert_near(st.damage_pct, float(row.damage) / 100.0)
			assert_eq(st.attack_count, int(row.get("attackCount", 1)))
			assert_eq(st.mob_count, int(row.get("mobCount", 1)))
			assert_eq(st.hp_cost, int(row.get("hpCon", 0)))
		assert_near(Loadout.new(b).stats(key, 1).damage_pct, {"power_strike":1.75,"slash_blast":0.78,"brandish":1.5}[key])
	library.free()

func test_wide_slash_rarity_reaches_a_mob_beyond_the_base_nova() -> void:
	var w := _world()
	w.learn_skill("slash_blast")
	var m := RF.put_mob(w, 1110100, 550, 190, 1000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(1.0 / 60.0, w)
	assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
	w.upgrades.apply("slash_blast_rank", w, "epic")
	w.runner.step(1.0 / 60.0, w)
	assert_true(w.swarm.hp[m] < w.swarm.max_hp[m], "Wide Slash area enlarges its radial reach")
