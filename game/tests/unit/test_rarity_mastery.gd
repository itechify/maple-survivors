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
	assert_near(w.loadout.skill_stat("energy_bolt", "damage", 1.0), before * 1.05, 0.00001, "Normal Mastery is +5% damage")

func test_normal_mastery_is_never_a_dead_pick_and_repeats_diminish() -> void:
	var w := RF.quiet_world()
	w.loadout.set_rank("energy_bolt", 8)
	var c := w.upgrades.choice_card("energy_bolt_rank", w, "normal")
	assert_eq(c.card_kind, "mastery")
	assert_eq(c.magnitude, 0)
	assert_eq(c.rarity_bonus.id, "mastery_damage")
	assert_true("Mastery" in String(c.desc) and "1.05" in String(c.desc), "text names the bonus: %s" % c.desc)
	assert_false(c.skill_mod_changes.is_empty(), "the preview shows the damage change")
	assert_true(BotInput.card_score(w, c) > 0.0, "the bot scores a Normal Mastery above nothing")
	# Preview does not spend the bonus; each application shrinks the next one by 0.8.
	assert_eq(c, w.upgrades.choice_card("energy_bolt_rank", w, "normal"))
	var expected := 1.0
	for n in 4:
		w.upgrades.apply("energy_bolt_rank", w, "normal")
		expected *= 1.0 + 0.05 * pow(0.8, n)
		assert_near(w.loadout.skill_stat("energy_bolt", "damage", 1.0), expected, 0.00001, "repeat %d" % n)
	assert_eq(w.loadout.rank("energy_bolt"), 8, "Mastery never raises the rank")
	assert_eq(int(w.loadout.card_ranks["bonus:energy_bolt:mastery_damage"]), 4)
	# Another skill keeps its own counter: its first Normal Mastery is the full +5%.
	w.upgrades.apply("magic_claw_new", w, "normal")
	w.loadout.set_rank("magic_claw", 8)
	w.upgrades.apply("magic_claw_rank", w, "normal")
	assert_near(w.loadout.skill_stat("magic_claw", "damage", 1.0), 1.05, 0.00001)
	# A below-cap Normal rank card still gets no bonus.
	var low := RF.quiet_world()
	assert_true(low.upgrades.choice_card("energy_bolt_rank", low, "normal").rarity_bonus.is_empty())

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
	assert_near(w.loadout.stats("energy_bolt").cooldown, 0.18)
	w.upgrades.apply(first.id, w, "epic")
	assert_near(w.loadout.stats("energy_bolt").area, 2.1, 0.00001)
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.loadout.rank("energy_bolt"), 8)


## #290 skills: {key: [epic stat, epic op, unique stat, unique op]}; Rare is damage x1.2, Legendary is Unique plus damage.
const HIGH := {
	"explosion": ["area", "attack_count"],
	"poison_mist": ["area", "cooldown"],
	"element_composition": ["pierce", "count"],
	"fire_demon": ["area", "count"],
	"paralyze": ["cooldown", "attack_count"],
	"meteor_shower": ["area", "attack_count"],
	"big_bang": ["area", "attack_count"],
}

func test_high_job_actives_declare_all_four_rarity_lists() -> void:
	var w := RF.quiet_world()
	for key: String in HIGH:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		for tier in ["rare", "epic", "unique", "legendary"]:
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			assert_false(bonuses[tier][0].effects.is_empty())
		assert_eq(bonuses.rare[0].effects[0].stat, "damage")
		assert_eq(bonuses.epic[0].effects[0].stat, HIGH[key][0], key)
		assert_eq(bonuses.unique[0].effects[0].stat, HIGH[key][1], key)
		assert_eq(bonuses.legendary[0].id, bonuses.unique[0].id, "%s legendary shares the unique repeats" % key)
		assert_eq(bonuses.legendary[0].effects.size(), 2)
		assert_eq(bonuses.legendary[0].effects[1].stat, "damage")
		assert_false(w.upgrades.card(key + "_new").is_empty(), "%s has a pool card" % key)

func test_high_job_actives_apply_each_rarity_deterministically() -> void:
	for key: String in HIGH:
		for tier in ["rare", "epic", "unique", "legendary"]:
			var a := RF.quiet_world()
			var b := RF.quiet_world()
			var c := a.upgrades.choice_card(key + "_new", a, tier)
			assert_false(c.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			assert_eq(c, a.upgrades.choice_card(key + "_new", a, tier), "preview is stable")
			a.upgrades.apply(key + "_new", a, tier)
			b.upgrades.apply(key + "_new", b, tier)
			assert_eq(a.loadout.rank(key), 1, "%s %s: exactly one rank" % [key, tier])
			assert_eq(a.loadout.skill_mods.get(key, {}), b.loadout.skill_mods.get(key, {}), "same bonus both runs")
			var mods: Dictionary = a.loadout.skill_mods.get(key, {})
			match tier:
				"rare": assert_near(a.loadout.skill_stat(key, "damage", 1.0), 1.2)
				"epic": assert_true(mods.has(HIGH[key][0]), "%s epic changes %s" % [key, HIGH[key][0]])
				"unique": assert_true(mods.has(HIGH[key][1]), "%s unique changes %s" % [key, HIGH[key][1]])
				"legendary":
					assert_true(mods.has(HIGH[key][1]) and mods.has("damage"), "%s legendary has both" % key)
					assert_near(a.loadout.skill_stat(key, "damage", 1.0), 1.2)

func test_high_job_bonus_values_resolve_in_loadout_stats_and_repeat_diminishes() -> void:
	var w := RF.quiet_world()
	var base := RF.quiet_world()
	base.upgrades.apply("explosion_new", base, "normal")
	w.upgrades.apply("explosion_new", w, "unique")
	assert_eq(w.loadout.stats("explosion").attack_count, base.loadout.stats("explosion").attack_count + 1, "Explosion unique: +1 hit")
	w.upgrades.apply("explosion_rank", w, "epic")
	assert_near(w.loadout.stats("explosion").area, 1.2, 0.00001)
	w.upgrades.apply("explosion_rank", w, "epic")
	assert_near(w.loadout.stats("explosion").area, 1.2 * 1.16, 0.00001, "second Epic area repeat is x1.16")
	var p := RF.quiet_world()
	p.upgrades.apply("paralyze_new", p, "epic")
	assert_near(p.loadout.stats("paralyze").cooldown, 1.2 * 0.88, 0.00001)
	var e := RF.quiet_world()
	e.upgrades.apply("element_composition_new", e, "unique")
	assert_eq(e.loadout.stats("element_composition").count, 2)
	e.upgrades.apply("element_composition_rank", e, "epic")
	assert_eq(e.loadout.stats("element_composition").pierce, 1)

func test_high_job_mastery_scores_above_normal_for_rare_and_normal_mastery_scores_above_nothing() -> void:
	for key: String in HIGH:
		var w := RF.quiet_world()
		w.upgrades.apply(key + "_new", w, "normal")
		w.loadout.set_rank(key, 8)
		var normal := w.upgrades.choice_card(key + "_rank", w)
		var rare := w.upgrades.choice_card(key + "_rank", w, "rare")
		assert_eq(normal.card_kind, "mastery")
		assert_true(BotInput.card_score(w, normal) > 0.0, "%s Normal Mastery is not dead" % key)
		assert_true(BotInput.card_score(w, rare) > BotInput.card_score(w, normal), key)


## #291 Elquines: Rare damage x1.2, Epic area x1.2, Unique +1 ally, Legendary the Unique plus damage x1.2.
func test_elquines_declares_all_four_rarity_lists_and_every_pool_skill_has_bonuses() -> void:
	var w := RF.quiet_world()
	var b: Dictionary = w.book.def("elquines").rarity_bonuses
	for tier in ["rare", "epic", "unique", "legendary"]:
		assert_eq(b[tier].size(), 1, tier)
		assert_false(b[tier][0].effects.is_empty())
	assert_eq(b.rare[0].effects[0].stat, "damage")
	assert_eq(b.epic[0].effects[0].stat, "area")
	assert_eq(b.unique[0].effects[0].stat, "summon_count")
	assert_eq(b.legendary[0].id, b.unique[0].id, "legendary shares the unique repeats")
	assert_eq(b.legendary[0].effects[1].stat, "damage")
	for key: String in w.jobs.skill_pool(w.job_id()):
		assert_true(w.book.def(key).has("rarity_bonuses"), "%s has rarity bonuses" % key)

func test_elquines_applies_each_rarity_with_one_rank_and_repeats_diminish() -> void:
	for tier in ["rare", "epic", "unique", "legendary"]:
		var a := RF.quiet_world()
		var b := RF.quiet_world()
		var c := a.upgrades.choice_card("elquines_new", a, tier)
		assert_false(c.get("rarity_bonus", {}).is_empty(), tier)
		assert_eq(c, a.upgrades.choice_card("elquines_new", a, tier), "preview is stable")
		a.upgrades.apply("elquines_new", a, tier)
		b.upgrades.apply("elquines_new", b, tier)
		assert_eq(a.loadout.rank("elquines"), 1, "%s: exactly one rank" % tier)
		assert_eq(a.loadout.skill_mods.get("elquines", {}), b.loadout.skill_mods.get("elquines", {}))
		var lo: Loadout = a.loadout
		match tier:
			"rare": assert_near(lo.skill_stat("elquines", "damage", 1.0), 1.2)
			"epic": assert_near(lo.stats("elquines").area, 1.2)
			"unique": assert_near(lo.skill_stat("elquines", "summon_count", 1.0), 2.0)
			"legendary":
				assert_near(lo.skill_stat("elquines", "summon_count", 1.0), 2.0)
				assert_near(lo.skill_stat("elquines", "damage", 1.0), 1.2)
	var w := RF.quiet_world()
	w.upgrades.apply("elquines_new", w, "epic")
	w.upgrades.apply("elquines_rank", w, "epic")
	assert_near(w.loadout.stats("elquines").area, 1.2 * 1.16, 0.00001, "second Epic area repeat is x1.16")
	w.upgrades.apply("elquines_rank", w, "unique")
	w.upgrades.apply("elquines_rank", w, "legendary")
	assert_near(w.loadout.skill_stat("elquines", "summon_count", 1.0), 1.0 + 1.0 + 0.8, 0.00001, "Unique and Legendary share the twin counter")

func test_elquines_unique_summons_an_extra_ally_and_mastery_scores() -> void:
	var w := RF.quiet_world()
	w.upgrades.apply("elquines_new", w, "normal")
	w.loadout.set_rank("elquines", 8)
	var normal := w.upgrades.choice_card("elquines_rank", w)
	var rare := w.upgrades.choice_card("elquines_rank", w, "rare")
	assert_eq(normal.card_kind, "mastery")
	assert_true(BotInput.card_score(w, normal) > 0.0, "Normal Mastery is not dead")
	assert_true(BotInput.card_score(w, rare) > BotInput.card_score(w, normal))

## #289 interaction: common passives never roll rarity, never get a bonus or Mastery; their cards stay +1 rank, Normal.
func test_common_passives_never_get_rarity_bonuses_or_mastery() -> void:
	var w := RF.quiet_world()
	var passives: Array[String] = []
	for key: String in w.book.defs:
		if bool(w.book.def(key).get("common_passive", false)):
			passives.append(key)
	assert_eq(passives.size(), 9)
	for key in passives:
		assert_false(w.book.def(key).has("rarity_bonuses"), key)
		for tier in UpgradePool.TIERS:
			var c := w.upgrades.choice_card(key + "_new", w, tier)
			assert_eq(c.tier, "normal", "%s %s stays Normal" % [key, tier])
			assert_true(c.rarity_bonus.is_empty())
			assert_eq(c.card_kind, "new_passive")
			assert_eq(c.magnitude, 1)
	w.upgrades.apply("passive_might_new", w, "legendary")
	w.loadout.set_rank("passive_might", 5)
	var capped := w.upgrades.choice_card("passive_might_rank", w, "legendary")
	assert_eq(capped.tier, "normal")
	assert_ne(capped.card_kind, "mastery")
	assert_true(capped.rarity_bonus.is_empty())
	var rng := RandomNumberGenerator.new()
	rng.seed = 289
	for i in 400:
		for c: Dictionary in w.upgrades.roll_choices(w, rng, 3):
			if String(c.skill).begins_with("passive_"):
				assert_eq(c.tier, "normal")
				assert_true(c.rarity_bonus.is_empty())
				assert_ne(c.card_kind, "mastery")
