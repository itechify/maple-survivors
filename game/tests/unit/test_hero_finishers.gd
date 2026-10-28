extends TestCase
## Hero Combo finishers (H8 #304): Panic and Coma through seeded fixed-tick casts, the orb multiplier, boss priority,
## the Threaten cut, HP cost, stun by rank, weapon-variant art keyed by orbs spent, and what every rarity bonus changes.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEYS := ["panic", "coma"]
const SWORD := 1302000
const TWO_HAND_AXE := 1412000

## Synthetic book 111: endpoints follow the v83 shape. Panic's prop is 100 so its status never rolls; Coma's prop is 0 at
## level 4 (rank 1) and 100 from level 19 (rank 5), so rank decides the stun with no RNG involved.
func _imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	var panic := {}
	var coma := {}
	for lv in range(1, 31):
		panic[str(lv)] = {"damage": 150 + (lv - 1) * 7, "prop": 100, "time": 3 + lv / 5}
		coma[str(lv)] = {"damage": 84 + (lv - 1) * 4, "prop": 0 if lv < 19 else 100, "time": 2 + lv / 15,
			"hpCon": 10 + lv / 3, "range": 130 + lv / 2, "mobCount": 6}
	imgs["111"] = {"skill": {"1111003": {"level": panic}, "1111005": {"level": coma}}}
	return imgs

func _world(weapon := SWORD) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"].playable = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 304, data))
	setup.skill_imgs = _imgs()
	var w := RunWorld.new(setup)
	w.set_job(112)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.equipment.worn.weapon = Equipment.create(weapon, {"incPAD": 17})
	w.refresh_player_stats()
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	return w

func _mob(w: RunWorld, px: float, hp := 100000) -> int:
	var m := RF.put_mob(w, 1110100, px, 190, 10000)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func _orbs(w: RunWorld, n: int) -> void:
	w.meter.value = 0
	for i in n:
		w.meter.gain("cast_landed", w.events)

func _on_cooldown(w: RunWorld, key: String) -> bool:
	return float(w.runner.cooldowns.get(key, 0.0)) > 0.0

func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")

func _step(w: RunWorld) -> Array:
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()

# --- catalog -----------------------------------------------------------------------------------------------------

func test_catalog_two_finishers_with_eight_ranks_no_weapon_gate_and_the_spec_meter_block() -> void:
	var book := SkillBook.from_data(DataRepo.load_all().skills, _imgs())
	for key: String in KEYS:
		assert_true(book.has(key), key)
		assert_eq(book.max_rank(key), 8, key)
		assert_eq(book.slot(key), "active")
		assert_true(book.weapon_families(key).is_empty(), key)
		var meter: Dictionary = book.def(key).meter
		assert_eq([meter.role, int(meter.min), meter.spend, meter.damage_per_unit], ["finisher", 5, "all", 0.10])
		assert_eq(book.def(key).action, "weapon", "the first swing stance of the held weapon")
	assert_eq(book.skill_id("panic"), 1111003)
	assert_eq(book.skill_id("coma"), 1111005)
	assert_eq(book.art_skill_id("panic", "axe"), 1111004)
	assert_eq(book.art_skill_id("coma", "axe"), 1111006)

# --- the orb multiplier ------------------------------------------------------------------------------------------

func test_orb_multiplier_is_1_5_at_five_orbs_and_2_0_at_ten_on_top_of_the_held_bonus() -> void:
	for key: String in KEYS:
		for pair: Array in [[5, 1.5], [10, 2.0]]:
			var w := _world()
			w.learn_skill(key)
			_orbs(w, int(pair[0]))
			var base := w.runner.stats_of(w, key)
			var cast := w.meter.begin_cast(w, key, base)
			var held := 1.0 + int(pair[0]) * 0.02
			assert_near(float(cast.damage_max) / float(base.damage_max), held * float(pair[1]), 0.001, key)
			assert_eq(cast.meter_spent, int(pair[0]))
			assert_eq(w.meter.value, 0, "spend all")

func test_finishers_wait_below_five_orbs_and_a_landed_finisher_earns_no_orb() -> void:
	var w := _world()
	w.learn_skill("panic")
	_mob(w, 440)
	_orbs(w, 4)
	_step(w)
	assert_eq(w.runner.casts, 0)
	assert_eq(w.meter.value, 4)
	_orbs(w, 5)
	var events := _step(w)
	assert_eq(w.runner.casts, 1)
	assert_eq(_hits(events).size(), 1)
	assert_eq(w.meter.value, 0, "all five spent and the landing gave none back")
	assert_true(float(w.runner.cooldowns.panic) >= 1.0, "meter-gated one second floor")

# --- Panic -------------------------------------------------------------------------------------------------------

func test_panic_strikes_a_scheduled_boss_before_a_nearer_mob_within_250_and_ignores_farther_ones() -> void:
	var w := _world()
	w.learn_skill("panic")
	var near := _mob(w, 430)
	var boss := _mob(w, 600)
	var far := _mob(w, 700)
	w.mob_boss[boss] = 0
	_orbs(w, 5)
	var hits := _hits(_step(w))
	assert_eq(hits.size(), 1, "single target")
	assert_eq(hits[0].mob, boss)
	assert_eq(w.swarm.hp[near], w.swarm.max_hp[near])
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far])
	# Without a boss: the nearest mob in range, and nothing beyond 250 px.
	var w2 := _world()
	w2.learn_skill("panic")
	var nearest := _mob(w2, 430)
	_mob(w2, 480)
	_orbs(w2, 5)
	assert_eq(_hits(_step(w2))[0].mob, nearest)
	var w3 := _world()
	w3.learn_skill("panic")
	_mob(w3, 400 + 262)
	_orbs(w3, 5)
	_step(w3)
	assert_eq(w3.runner.casts, 0, "beyond 250 px nothing casts and no orb is spent")
	assert_eq(w3.meter.value, 5)

func test_panic_threatened_cut_is_the_skill_level_capped_at_twenty() -> void:
	for pair: Array in [[1, 4], [3, 12], [5, 19], [8, 20]]:
		var w := _world()
		w.learn_skill("panic")
		w.loadout.set_rank("panic", int(pair[0]))
		var level := w.book.canonical_level("panic", int(pair[0]))
		var m := _mob(w, 430)
		_orbs(w, 5)
		var events := _step(w)
		var applied := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied")
		assert_eq(applied.size(), 1, "rank %d" % pair[0])
		assert_eq(applied[0].status, "threatened")
		assert_near(float(applied[0].duration), w.book.canonical("panic", level, "time"))
		assert_near(w.swarm.threat_pad[m], float(mini(level, 20)), 0.001, "attack cut at level %d" % level)
		assert_near(w.swarm.threat_pdd[m], float(mini(level, 20)), 0.001, "defence cut")
		assert_eq(int(pair[1]), mini(level, 20))
		assert_near(w.swarm.threatened_pad(m, 100.0), 100.0 - mini(level, 20))
		assert_near(w.swarm.threatened_pdd(m, 5.0), maxf(0.0, 5.0 - mini(level, 20)))

# --- Coma --------------------------------------------------------------------------------------------------------

func test_coma_needs_three_mobs_in_range_then_hits_up_to_six_and_spends_the_orbs() -> void:
	var w := _world()
	w.learn_skill("coma")
	_mob(w, 440)
	_mob(w, 450)
	_orbs(w, 10)
	_step(w)
	assert_eq(w.runner.casts, 0, "two mobs are not a crowd")
	assert_eq(w.meter.value, 10, "refused: nothing spent")
	for i in 6:
		_mob(w, 420 + i * 6.0)
	var hits := _hits(_step(w))
	assert_eq(w.runner.casts, 1)
	assert_eq(hits.size(), 6, "mobCount 6 of the eight in range")
	assert_eq(w.meter.value, 0)

func test_coma_hp_cost_is_paid_and_never_lethal() -> void:
	var w := _world()
	w.learn_skill("coma")
	for i in 3:
		_mob(w, 430 + i * 8.0)
	var cost := int(w.runner.stats_of(w, "coma").hp_cost)
	assert_true(cost > 0)
	w._hp = float(cost)
	_orbs(w, 5)
	_step(w)
	assert_eq(w.runner.casts, 0, "paying it would leave 0 HP")
	assert_eq(w.meter.value, 5, "nothing spent")
	w._hp = float(cost + 1)
	_step(w)
	assert_eq(w.runner.casts, 1)
	assert_near(w._hp, 1.0, 0.001, "left with 1 HP, never 0")

func test_coma_stun_chance_and_time_follow_the_rank() -> void:
	var low := _world()
	low.learn_skill("coma")
	var m_low := _mob(low, 430)
	_mob(low, 440)
	_mob(low, 450)
	_orbs(low, 5)
	var events := _step(low)
	assert_eq(low.runner.casts, 1)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied").size(), 0,
		"rank 1 reads level 4: prop 0")
	assert_near(low.swarm.status_left[m_low * MobSwarm.STATUS_COUNT + MobSwarm.STUN], 0.0)
	var high := _world()
	high.learn_skill("coma")
	high.loadout.set_rank("coma", 8)
	var m_high := _mob(high, 430)
	_mob(high, 440)
	_mob(high, 450)
	_orbs(high, 5)
	events = _step(high)
	var stuns := events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied" and e.status == "stun")
	assert_eq(stuns.size(), 3)
	assert_near(float(stuns[0].duration), high.book.canonical("coma", 30, "time"))
	assert_true(high.swarm.status_left[m_high * MobSwarm.STATUS_COUNT + MobSwarm.STUN] > 0.0)

# --- both ready --------------------------------------------------------------------------------------------------

func test_both_ready_the_target_count_rule_picks_coma_for_a_crowd_and_panic_for_a_boss() -> void:
	var w := _world()
	w.learn_skill("panic")
	w.learn_skill("coma")
	for i in 4:
		_mob(w, 430 + i * 8.0)
	_orbs(w, 10)
	_step(w)
	assert_true(_on_cooldown(w, "coma") and not _on_cooldown(w, "panic"), "crowd: Coma")
	assert_eq(w.meter.value, 0)
	var b := _world()
	b.learn_skill("panic")
	b.learn_skill("coma")
	var boss := _mob(b, 430)
	for i in 3:
		_mob(b, 440 + i * 8.0)
	b.mob_boss[boss] = 0
	_orbs(b, 10)
	_step(b)
	assert_true(_on_cooldown(b, "panic") and not _on_cooldown(b, "coma"), "boss in range: Panic")
	var alone := _world()
	alone.learn_skill("panic")
	_mob(alone, 430)
	_orbs(alone, 5)
	_step(alone)
	assert_true(_on_cooldown(alone, "panic"), "owning one finisher it casts alone")

# --- weapon-variant art ------------------------------------------------------------------------------------------

func test_art_skill_id_returns_the_axe_twin_only_for_an_axe() -> void:
	var book := SkillBook.from_data(DataRepo.load_all().skills, _imgs())
	assert_eq(book.art_skill_id("panic", "axe"), 1111004)
	assert_eq(book.art_skill_id("coma", "axe"), 1111006)
	for family: String in ["sword", "", "mace", "spear"]:
		assert_eq(book.art_skill_id("panic", family), 1111003, family)
		assert_eq(book.art_skill_id("coma", family), 1111005, family)
	assert_eq(book.art_skill_id("brandish", "axe"), 1121008, "a skill without art_by_family keeps its own id")
	assert_eq(book.art_path("panic", "Skill.wz/111.img/skill/1111003/finish/5", "axe"),
		"Skill.wz/111.img/skill/1111004/finish/5")
	assert_eq(book.art_path("panic", "Skill.wz/111.img/skill/1111003/finish/5", "sword"),
		"Skill.wz/111.img/skill/1111003/finish/5")
	assert_eq(book.art_path("panic", "", "axe"), "")

func test_the_cast_plays_finish_art_keyed_by_orbs_spent_with_the_axe_twin_for_an_axe() -> void:
	for pair: Array in [[SWORD, 1111005], [TWO_HAND_AXE, 1111006], [1312004, 1111006]]:
		for spent in [5, 7, 10]:
			var w := _world(int(pair[0]))
			w.learn_skill("coma")
			for i in 3:
				_mob(w, 430 + i * 8.0)
			_orbs(w, spent)
			var cast: Dictionary = _step(w).filter(func(e: Dictionary) -> bool: return e.type == "cast")[0]
			assert_eq(cast.effect, "Skill.wz/111.img/skill/%d/finish/%d" % [pair[1], spent])

func test_panic_plays_its_finish_on_the_target_and_hit_set_changes_above_five_orbs() -> void:
	for pair: Array in [[5, "0"], [6, "1"], [10, "1"]]:
		var w := _world(TWO_HAND_AXE)
		w.learn_skill("panic")
		var m := _mob(w, 430)
		_orbs(w, int(pair[0]))
		var events := _step(w)
		var fx := events.filter(func(e: Dictionary) -> bool: return e.type == "skill_mob_effect")
		assert_eq(fx.size(), 1)
		assert_eq(fx[0].mob, m)
		assert_eq(fx[0].effect, "Skill.wz/111.img/skill/1111004/finish/%d" % int(pair[0]))
		assert_eq(_hits(events)[0].hit_visual, "Skill.wz/111.img/skill/1111004/hit/" + String(pair[1]))

# --- rarity bonuses: every one changes the resolved cast ----------------------------------------------------------

func _with_card(key: String, tier: String) -> RunWorld:
	var w := _world()
	w.learn_skill(key)
	w.upgrades.apply(key + "_rank", w, tier)
	return w

func test_every_finisher_has_four_rarity_lists_and_a_card_adds_one_rank() -> void:
	for key: String in KEYS:
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			var w := _world()
			var id := key + "_new"
			assert_false(w.upgrades.choice_card(id, w, tier).get("rarity_bonus", {}).is_empty(), key + tier)
			w.upgrades.apply(id, w, tier)
			assert_eq(w.loadout.rank(key), 1)
			w.upgrades.apply(key + "_rank", w, tier)
			assert_eq(w.loadout.rank(key), 2, key + tier)

func test_mastery_rare_raises_the_resolved_damage_and_the_hit_that_lands() -> void:
	for key: String in KEYS:
		var plain := _world()
		plain.learn_skill(key)
		plain.loadout.set_rank(key, 2)
		var carded := _world()
		carded.learn_skill(key)
		carded.upgrades.apply(key + "_rank", carded, "rare")
		assert_eq(carded.loadout.rank(key), 2)
		assert_near(carded.loadout.skill_stat(key, "damage", 1.0), 1.2)
		var a := plain.runner.stats_of(plain, key)
		var b := carded.runner.stats_of(carded, key)
		assert_near(float(b.damage_max) / float(a.damage_max), 1.2, 0.001, key)
		var damage := []
		for w: RunWorld in [plain, carded]:
			for i in 3:
				_mob(w, 430 + i * 8.0)
			_orbs(w, 5)
			var hits := _hits(_step(w))
			assert_false(hits.is_empty())
			damage.append(hits.map(func(h: Dictionary) -> int: return int(h.damage)).max())
		assert_true(int(damage[1]) > int(damage[0]), "%s hit %s" % [key, damage])

func test_panic_booster_shortens_the_resolved_cooldown_above_the_one_second_floor() -> void:
	var plain := _world()
	plain.learn_skill("panic")
	plain.loadout.set_rank("panic", 2)
	var carded := _with_card("panic", "epic")
	var a := plain.runner.stats_of(plain, "panic")
	var b := carded.runner.stats_of(carded, "panic")
	assert_near(float(b.cooldown), float(a.cooldown) * 0.88, 0.001)
	assert_true(float(b.cooldown) > 1.0, "the booster is not swallowed by the meter floor")
	assert_true(SkillRunner.restart_cooldown(b) < SkillRunner.restart_cooldown(a))
	_mob(carded, 430)
	_orbs(carded, 5)
	_step(carded)
	assert_near(float(carded.runner.cooldowns.panic), float(b.cooldown), 0.02, "the cast restarts the shortened cooldown")
	assert_true(float(carded.runner.cooldowns.panic) < float(a.cooldown))

func test_coma_reach_rare_epic_widens_the_nova_to_a_mob_that_was_out_of_range() -> void:
	var w := _with_card("coma", "epic")
	var st := w.runner.stats_of(w, "coma")
	var base_range := float(st.range) / 1.2
	assert_near(w.loadout.skill_stat("coma", "area", 1.0), 1.2)
	# Two mobs close, the third just past the un-widened reach and inside the widened one.
	_mob(w, 400 + 30)
	_mob(w, 400 + 40)
	var edge := _mob(w, 400 + base_range + 8.0)
	_orbs(w, 5)
	var hits := _hits(_step(w))
	assert_eq(w.runner.casts, 1)
	assert_true(hits.any(func(h: Dictionary) -> bool: return h.mob == edge), "Wide reach hit the edge mob")
	var plain := _world()
	plain.learn_skill("coma")
	plain.loadout.set_rank("coma", 2)
	_mob(plain, 400 + 30)
	_mob(plain, 400 + 40)
	var out := _mob(plain, 400 + base_range + 8.0)
	_orbs(plain, 5)
	var plain_hits := _hits(_step(plain))
	assert_false(plain_hits.any(func(h: Dictionary) -> bool: return h.mob == out), "without the card it stays out of reach")

func test_advanced_combo_unique_and_legendary_leave_two_orbs_and_trim_the_multiplier() -> void:
	for key: String in KEYS:
		for tier: String in ["unique", "legendary"]:
			var w := _with_card(key, tier)
			assert_eq(w.runner.stats_of(w, key).meter_keep, 2)
			for i in 3:
				_mob(w, 430 + i * 8.0)
			_orbs(w, 5)
			var base := w.runner.stats_of(w, key)
			var cast := w.meter.begin_cast(w, key, base)
			assert_eq(cast.meter_spent, 3, "5 held, 2 kept")
			assert_eq(w.meter.value, 2, key + tier)
			var held := 1.0 + 5 * 0.02
			var damage_card := 1.2 if tier == "legendary" else 1.0
			# base already carries the card's damage multiplier; only the orb factors are applied by begin_cast.
			assert_near(float(cast.damage_max) / float(base.damage_max), held * (1.0 + 3 * 0.10), 0.001)
			assert_near(w.loadout.skill_stat(key, "damage", 1.0), damage_card, 0.001)

func test_advanced_combo_keep_lets_the_finisher_chain_after_three_more_orbs() -> void:
	var w := _with_card("coma", "unique")
	for i in 3:
		_mob(w, 430 + i * 8.0)
	_orbs(w, 5)
	_step(w)
	assert_eq(w.meter.value, 2)
	w.runner.cooldowns.coma = 0.0
	for i in 2:
		w.meter.gain("cast_landed", w.events)
	_step(w)
	assert_eq(w.runner.casts, 1, "four orbs held: not yet")
	w.meter.gain("cast_landed", w.events)
	_step(w)
	assert_eq(w.runner.casts, 2, "five orbs again")
	assert_eq(w.meter.value, 2)

func test_keep_previews_in_the_card_and_the_skill_text() -> void:
	for key: String in KEYS:
		var w := _world()
		w.learn_skill(key)
		var card := w.upgrades.choice_card(key + "_rank", w, "unique")
		assert_true("Keeps 2 orbs" in String(card.desc), String(card.desc))
		assert_eq(card.skill_mod_changes.meter_keep, {"before": 0, "after": 2})
		w.upgrades.apply(card.id, w, "unique")
		var line := SkillText.new(w.book).level_line(key, w.loadout.rank(key), w.loadout.stats(key))
		assert_true("Needs 5 orbs" in line and "Keeps 2 orbs" in line, line)
		var legendary := w.upgrades.choice_card(key + "_rank", w, "legendary")
		w.upgrades.apply(legendary.id, w, "legendary")
		assert_eq(int(w.loadout.card_ranks["bonus:%s:advanced_combo" % key]), 2, "Legendary shares the Unique's counter")
		assert_eq(w.loadout.stats(key).meter_keep, 4, "two Advanced Combo cards keep four")

# --- real cache ----------------------------------------------------------------------------------------------------

func test_real_cache_mapped_levels_for_all_eight_ranks_and_both_twins_have_their_nodes() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/111.img")
	assert_true(img != null, "book 111 imported (the shared cache needs the 111/112 books)")
	if img == null:
		library.free()
		return
	var root: Dictionary = img.root
	var b := SkillBook.from_data(DataRepo.load_all().skills, {"111": root})
	var table := [4, 8, 12, 15, 19, 23, 27, 30]
	for key: String in KEYS:
		assert_eq(b.rank_table(key).map(func(v: Variant) -> int: return int(v)), table)
		var lo := Loadout.new(b)
		lo.add_skill(key)
		for rank in range(1, 9):
			var lv: int = table[rank - 1]
			assert_eq(b.canonical_level(key, rank), lv)
			var row: Dictionary = root.skill[str(b.skill_id(key))].level[str(lv)]
			var st := lo.stats(key, rank)
			assert_near(st.damage_pct, float(row.damage) / 100.0, 0.0001, "%s rank %d" % [key, rank])
			assert_eq(st.mob_count, int(row.get("mobCount", 1)))
			assert_eq(st.hp_cost, int(row.get("hpCon", 0)))
			assert_near(b.canonical(key, lv, "prop"), float(row.prop))
			assert_near(b.canonical(key, lv, "time"), float(row.time))
			if key == "coma":
				assert_near(float(st.range), float(row.range), 0.001)
	assert_near(Loadout.new(b).stats("panic", 1).damage_pct, 1.94, 0.0001)
	assert_near(Loadout.new(b).stats("coma", 1).damage_pct, 0.96, 0.0001)
	for id in [1111003, 1111004, 1111005, 1111006]:
		var node: Dictionary = root.skill[str(id)]
		for n in range(1, 11):
			assert_true(node.finish.has(str(n)), "%d finish/%d" % [id, n])
		assert_true(node.hit.has("0") and node.hit.has("1"), "%d hit/0 and hit/1" % id)
		assert_true(node.has("icon"))
	for id in [1111005, 1111006]:
		assert_true(root.skill[str(id)].has("mob"), "%d stun stars" % id)
	library.free()
