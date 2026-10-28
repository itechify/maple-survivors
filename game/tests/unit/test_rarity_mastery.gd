extends TestCase
## Rarity bonuses and post-cap Mastery through the public card/loadout seams (#288).
const RF := preload("res://tests/fixtures/run_fixtures.gd")

func test_rarity_adds_a_skill_bonus_but_always_only_one_rank() -> void:
	for tier in UpgradePool.TIERS:
		var w := RF.quiet_world()
		var c := w.upgrades.choice_card("energy_bolt_rank", w, tier)
		w.upgrades.apply("energy_bolt_rank", w, tier)
		assert_eq(w.loadout.rank("energy_bolt"), 2)
		match tier:
			"normal": assert_eq(w.loadout.skill_stat("energy_bolt", "damage", 1.0), 1.0)
			"rare": assert_near(w.loadout.skill_stat("energy_bolt", "damage", 1.0), 1.2)
			"epic": assert_eq(w.loadout.stats("energy_bolt").pierce, 1)
			"unique", "legendary": assert_eq(w.loadout.stats("energy_bolt").count, 2)
		if tier != "normal":
			assert_false(c.get("rarity_bonus", {}).is_empty())
			assert_false(c.skill_mod_changes.is_empty())

func test_mastery_stays_available_at_eight_and_repeats_shrink() -> void:
	var w := RF.quiet_world()
	w.loadout.set_rank("energy_bolt", 8)
	assert_has(w.upgrades.eligible(w), "energy_bolt_rank")
	var c := w.upgrades.choice_card("energy_bolt_rank", w, "rare")
	assert_eq(c.card_kind, "mastery")
	assert_eq(c.magnitude, 0)
	assert_eq(w.upgrades.draw_weight(w.upgrades.card(c.id), w), 1.2)
	assert_true("Mastery" in c.name)
	w.upgrades.apply(c.id, w, "rare")
	w.upgrades.apply(c.id, w, "rare")
	assert_eq(w.loadout.rank("energy_bolt"), 8)
	assert_near(w.loadout.skill_stat("energy_bolt", "damage", 1.0), 1.392, 0.00001)
	var before := w.loadout.skill_stat("energy_bolt", "damage", 1.0)
	w.upgrades.apply(c.id, w, "normal")
	assert_eq(w.loadout.rank("energy_bolt"), 8)
	assert_eq(w.loadout.skill_stat("energy_bolt", "damage", 1.0), before)

func test_all_four_skills_support_new_rank_and_mastery_bonuses_and_bot_scores() -> void:
	for key in ["energy_bolt", "magic_claw", "fire_arrow", "poison_breath"]:
		for tier in ["rare", "epic", "unique", "legendary"]:
			var w := RF.quiet_world()
			var id: String = key + ("_rank" if w.loadout.has(key) else "_new")
			var c := w.upgrades.choice_card(id, w, tier)
			assert_false(c.get("rarity_bonus", {}).is_empty())
			w.upgrades.apply(id, w, tier)
			assert_eq(w.loadout.rank(key), 2 if key == "energy_bolt" else 1)
			assert_false(w.loadout.skill_mods.get(key, {}).is_empty())
			w.loadout.set_rank(key, 8)
			var normal := w.upgrades.choice_card(key + "_rank", w)
			var rare := w.upgrades.choice_card(key + "_rank", w, "rare")
			assert_true(BotInput.card_score(w, rare) > BotInput.card_score(w, normal))

func test_seeded_fortune_shifts_active_rarity_without_standalone_mod_offers() -> void:
	var w := RF.quiet_world()
	for c in w.upgrades.cards:
		assert_false(String(c.get("skill", "")) in ["energy_bolt", "magic_claw", "fire_arrow", "poison_breath"] and c.kind == "skill_mod")
	var counts := []
	for fortune in [0.0, 500.0]:
		w.player_state.fortune = fortune
		var rng := RandomNumberGenerator.new()
		rng.seed = 288
		var high := 0
		for i in 2000:
			if w.upgrades.roll_choices(w, rng, 1)[0].tier != "normal":
				high += 1
		counts.append(high)
	assert_true(counts[1] > counts[0] + 500)

func test_bonus_lists_extend_by_data_and_preview_does_not_spend_the_bonus() -> void:
	var data := RF.quiet_data()
	data.skills.skills.energy_bolt.rarity_bonuses.epic = [
		{"id": "wide", "text": "Wide", "effects": [{"stat": "area", "op": "mul", "value": 1.5}]},
		{"id": "quick", "text": "Quick", "effects": [{"stat": "cooldown", "op": "mul", "value": 0.5}]}]
	var w := RunWorld.new(RF.setup("quiet", 288, data))
	w.loadout.set_rank("energy_bolt", 8)
	var first := w.upgrades.choice_card("energy_bolt_rank", w, "epic")
	assert_eq(first, w.upgrades.choice_card("energy_bolt_rank", w, "epic"))
	assert_eq(w.loadout.skill_stat("energy_bolt", "area", 1.0), 1.0)
	w.upgrades.apply(first.id, w, "epic")
	assert_near(w.loadout.stats("energy_bolt").area, 1.5)
	w.upgrades.apply(first.id, w, "epic")
	assert_near(w.loadout.stats("energy_bolt").cooldown, 0.45)
	w.upgrades.apply(first.id, w, "epic")
	assert_near(w.loadout.stats("energy_bolt").area, 2.1, 0.00001)
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.loadout.rank("energy_bolt"), 8)
