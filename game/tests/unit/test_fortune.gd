extends TestCase
## Seeded Fortune offers and their public RunWorld/choice_card behavior (spec #30, ticket #43).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const TIERS := ["normal", "rare", "epic", "unique", "legendary"]


func _world(fortune: float = 0.0) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player["fortune"] = fortune
	# A roomy stacking card preserves every rolled tier, so headroom cannot skew the odds measurement.
	data.upgrades.cards = [{"id": "roomy", "kind": "skill_mod", "skill": "three_snails", "max_rank": 100,
		"effects": [{"stat": "count", "op": "add", "value": 1}]}]
	data.upgrades.pity.draws = 0
	return RunWorld.new(RF.setup("quiet", 43, data))


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _counts(w: RunWorld, seed_value: int, draws: int) -> Dictionary:
	var counts := {"normal": 0, "rare": 0, "epic": 0, "unique": 0, "legendary": 0}
	var rng := _rng(seed_value)
	for draw in draws:
		var c: Dictionary = w.upgrades.roll_choices(w, rng, 1)[0]
		var tier := String(c.get("tier", "missing"))
		if not counts.has(tier):
			assert_true(false, "every offer carries a known tier")
			return counts
		counts[tier] += 1
	return counts


func test_seeded_fortune_distribution_and_base_run_stat() -> void:
	var zero := _world()
	var lucky := _world(100.0)
	assert_eq(float(zero.player_state.get("fortune", -1)), 0.0)
	assert_eq(float(lucky.player_state.get("fortune", -1)), 100.0, "Fortune comes from survivor balance")
	var counts := _counts(zero, 43, 20000)
	# Literal bands follow the spec #30 design table, independently of the configured data under test.
	var bounds := {"normal": [0.73, 0.77], "rare": [0.165, 0.195], "epic": [0.042, 0.058],
		"unique": [0.013, 0.021], "legendary": [0.0015, 0.0047]}
	for tier: String in TIERS:
		var frequency := float(counts[tier]) / 20000.0
		assert_true(frequency >= float(bounds[tier][0]) and frequency <= float(bounds[tier][1]),
			"Fortune 0 %s frequency %.4f matches 75/18/5/1.7/0.3%%" % [tier, frequency])
	var higher := _counts(lucky, 43, 20000)
	# At Fortune 100 the documented normalized shares are 50/36/10/3.4/0.6%.
	var high_bounds := {"normal": [0.48, 0.52], "rare": [0.34, 0.38], "epic": [0.09, 0.11],
		"unique": [0.029, 0.039], "legendary": [0.004, 0.0082]}
	for tier: String in TIERS:
		var frequency := float(higher[tier]) / 20000.0
		assert_true(frequency >= float(high_bounds[tier][0]) and frequency <= float(high_bounds[tier][1]),
			"Fortune 100 %s frequency %.4f matches the documented normalized shares" % [tier, frequency])
	assert_true(int(higher.normal) < int(counts.normal) - 3500, "Fortune 100 measurably raises non-Normal offers")
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		assert_true(int(higher[tier]) > int(counts[tier]), "%s grows with Fortune" % tier)


func _tier_world(tier: String, id: String) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades.rarity.weights = {tier: 1.0}
	data.upgrades.cards = data.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.id == id)
	var w := RunWorld.new(RF.setup("quiet", 43, data))
	RF.place_player(w, 400)
	return w


func _open_level(w: RunWorld) -> void:
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)


func test_rank_tiers_apply_the_previewed_magnitude_through_run_choices() -> void:
	var expected := [5, 6, 7, 9, 12]
	for i in TIERS.size():
		var w := _tier_world(TIERS[i], "energy_bolt_rank")
		RF.change_job_bare(w, 200)
		w.learn_skill("energy_bolt")
		w.loadout.set_rank("energy_bolt", 4)
		_open_level(w)
		var c: Dictionary = w.pending_cards[0]
		assert_eq(String(c.get("tier", "")), TIERS[i])
		assert_eq(int(c.get("magnitude", 0)), expected[i] - 4)
		assert_eq(int(c.skill_level), 4)
		assert_eq(int(c.skill_level_next), expected[i], "preview the complete tier's level gain")
		assert_true(String(c.desc).contains("+%d rank" % (expected[i] - 4)), "text reflects the actual rank gain")
		assert_true(w.apply_choice("energy_bolt_rank"))
		assert_eq(w.loadout.level("energy_bolt"), expected[i], "the offered tier survives picking by id")


func test_legendary_rank_grants_eight_or_the_remaining_ranks() -> void:
	for example: Array in [[1, 8, 9, 116.0], [14, 6, 20, 104.0]]:
		var w := _tier_world("legendary", "energy_bolt_rank")
		RF.change_job_bare(w, 200)
		w.learn_skill("energy_bolt")
		w.loadout.set_rank("energy_bolt", example[0])
		_open_level(w)
		var c: Dictionary = w.pending_cards[0]
		assert_eq(String(c.tier), "legendary")
		assert_eq(int(c.magnitude), example[1])
		assert_eq(int(c.skill_level_next), example[2])
		assert_eq(BotInput.card_score(w, c), example[3], "bot scores the granted ranks")
		assert_true(String(c.desc).contains("+%d rank" % example[1]), "text shows the granted ranks")
		assert_true(LevelUpWindow.rank_text(c).contains("%d → %d" % [example[0], example[2]]),
			"the rank preview shows the granted level change")
		assert_true(w.apply_choice("energy_bolt_rank"))
		assert_eq(w.loadout.level("energy_bolt"), example[2], "applying grants exactly the previewed ranks")


func test_stacking_tiers_apply_steps_and_compound_the_displayed_value() -> void:
	var expected := [2, 3, 4, 5, 5]
	for i in TIERS.size():
		var w := _tier_world(TIERS[i], "three_snails_count")
		_open_level(w)
		assert_eq(int(w.pending_cards[0].get("magnitude", 0)), expected[i] - 1)
		assert_eq(int(w.pending_cards[0].rank), expected[i] - 1, "card stack count consumes every granted step")
		assert_true(String(w.pending_cards[0].desc).contains("+%d shell" % (expected[i] - 1)))
		assert_true(w.apply_choice("three_snails_count"))
		assert_eq(w.loadout.stats("three_snails").count, expected[i])
		assert_eq(w.loadout.card_ranks.three_snails_count, expected[i] - 1)
	var cooldown := _tier_world("unique", "three_snails_cooldown")
	var before: float = cooldown.loadout.stats("three_snails").cooldown
	_open_level(cooldown)
	assert_true(String(cooldown.pending_cards[0].desc).contains("40.03%"), "four x0.88 steps reduce cooldown 40.030464%")
	assert_true(cooldown.apply_choice("three_snails_cooldown"))
	assert_near(cooldown.loadout.stats("three_snails").cooldown, before * 0.59969536, 1e-6)
	# Spec #225 removed the Magnet card; a synthetic stat card keeps the player-stat stacking path covered.
	var data := RF.quiet_data()
	data.upgrades.rarity.weights = {"unique": 1.0}
	data.upgrades.cards = [{"id": "test_radius", "kind": "stat", "skill": "", "name": "Test radius",
		"desc": "Pick-up radius +{value}%.", "value": 25, "max_rank": 4, "weight": 1, "requires": {},
		"effects": [{"stat": "magnet", "op": "mul", "value": 1.25}]}]
	var magnet := RunWorld.new(RF.setup("quiet", 43, data))
	RF.place_player(magnet, 400)
	var radius := magnet.magnet_r
	_open_level(magnet)
	assert_true(String(magnet.pending_cards[0].desc).contains("144.14%"), "four x1.25 steps give +144.140625%")
	assert_true(magnet.apply_choice("test_radius"))
	assert_near(magnet.magnet_r, radius * 2.44140625, 1e-6, "player-stat stacking scales too")


func test_legendary_stacking_grants_five_clamps_and_supports_unlimited_cards() -> void:
	for example: Array in [[8, 0, 5, "legendary", 111.0], [8, 5, 3, "epic", 99.0], [0, 0, 5, "legendary", 111.0]]:
		var data := RF.quiet_data()
		data.upgrades.rarity.weights = {"legendary": 1.0}
		data.upgrades.cards = [{"id": "roomy", "kind": "skill_mod", "skill": "three_snails", "max_rank": example[0],
			"desc": "+{magnitude} shells.", "effects": [{"stat": "count", "op": "add", "value": 1}]}]
		var w := RunWorld.new(RF.setup("quiet", 43, data))
		RF.place_player(w, 400)
		for step in int(example[1]):
			w.upgrades.apply("roomy", w)
		var before := int(w.loadout.stats("three_snails").count)
		_open_level(w)
		var c: Dictionary = w.pending_cards[0]
		assert_eq(int(c.magnitude), example[2])
		assert_eq(String(c.tier), example[3])
		assert_eq(c.desc, "+%d shells." % example[2])
		assert_eq(BotInput.card_score(w, c), example[4], "bot scores the granted steps")
		assert_eq(c.skill_mod_changes.shots, {"before": before, "after": before + int(example[2])})
		assert_true(w.apply_choice("roomy"))
		assert_eq(w.loadout.stats("three_snails").count, before + int(example[2]))
		assert_eq(w.loadout.card_ranks.roomy, int(example[1]) + int(example[2]))


func test_new_skill_tiers_start_at_the_offered_rank() -> void:
	var expected := [1, 2, 3, 4, 5]
	for i in TIERS.size():
		var w := _tier_world(TIERS[i], "energy_bolt_new")
		RF.change_job_bare(w, 200)
		_open_level(w)
		var c: Dictionary = w.pending_cards[0]
		assert_eq(int(c.get("magnitude", 0)), expected[i])
		assert_eq(int(c.skill_level_next), expected[i])
		assert_eq(LevelUpWindow.rank_text(c), "NEW  Skill Lv. %d" % expected[i], "the rank line names the starting level")
		assert_true(w.apply_choice("energy_bolt_new"))
		assert_eq(w.loadout.level("energy_bolt"), expected[i])
		assert_false("energy_bolt_new" in w.upgrades.eligible(w), "a boosted learn still consumes its one-time card")


func test_headroom_downgrades_to_the_highest_fitting_distinct_tier() -> void:
	for example: Array in [["epic", 18, "rare", 20], ["unique", 18, "rare", 20],
			["legendary", 17, "epic", 20], ["legendary", 15, "unique", 20], ["legendary", 16, "legendary", 20]]:
		var w := _tier_world(example[0], "energy_bolt_rank")
		RF.change_job_bare(w, 200)
		w.learn_skill("energy_bolt")
		w.loadout.set_rank("energy_bolt", example[1])
		var preview := w.upgrades.choice_card("energy_bolt_rank", w, example[0])
		assert_eq(String(preview.get("tier", "")), example[2], "preview uses the honest tier")
		_open_level(w)
		assert_eq(String(w.pending_cards[0].get("tier", "")), example[2], "draw preserves the downgrade")
		assert_true(w.apply_choice("energy_bolt_rank"))
		assert_eq(w.loadout.level("energy_bolt"), example[3])
	var stacking := _tier_world("legendary", "three_snails_count")
	stacking.upgrades.apply("three_snails_count", stacking)
	stacking.upgrades.apply("three_snails_count", stacking)
	_open_level(stacking)
	assert_eq(String(stacking.pending_cards[0].get("tier", "")), "rare", "Legendary's last two steps equal Rare")
	assert_true(stacking.apply_choice("three_snails_count"))
	assert_eq(stacking.loadout.stats("three_snails").count, 5)
	var beginner := _tier_world("legendary", "nimble_feet")
	_open_level(beginner)
	assert_eq(String(beginner.pending_cards[0].get("tier", "")), "epic", "three-rank skills cannot learn at rank five or four")
	assert_eq(LevelUpWindow.rank_text(beginner.pending_cards[0]), "NEW  Skill Lv. 3  MAX", "a learn at the cap says so")
	assert_true(beginner.apply_choice("nimble_feet"))
	assert_eq(beginner.loadout.level("nimble_feet"), 3)


func test_boss_floor_filters_nearly_maxed_rank_cards_and_keeps_normal_exceptions() -> void:
	for seed_value in range(1, 21):
		var w := _world()
		w.card_rng.seed = seed_value
		w.pending_bonus_choices = 1
		w.step(1.0 / 60.0, MoveInput.new())
		assert_true(w.choice_bonus)
		for c: Dictionary in w.pending_cards:
			if c.kind != "filler":
				assert_ne(String(c.get("tier", "normal")), "normal", "a scalable boss offer keeps at least Rare")
	var capped := _tier_world("legendary", "energy_bolt_rank")
	RF.change_job_bare(capped, 200)
	capped.learn_skill("energy_bolt")
	capped.loadout.set_rank("energy_bolt", 19)
	capped.pending_bonus_choices = 1
	capped.step(1.0 / 60.0, MoveInput.new())
	assert_eq(capped.pending_cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"],
		"one remaining skill rank cannot meet the Rare floor; the fallback still opens a reward")
	assert_eq(String(capped.pending_cards[0].get("tier", "")), "normal")
	var plain := _tier_world("legendary", "elixir")
	RF.change_job_bare(plain, 200)
	plain.progression.level = 25
	plain.pending_bonus_choices = 1
	plain.step(1.0 / 60.0, MoveInput.new())
	assert_eq(plain.pending_cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	for c: Dictionary in plain.pending_cards:
		assert_eq(String(c.get("tier", "")), "normal", "the Elixir never scales, even at bosses")


func test_max_mp_passive_text_and_before_after_use_the_full_tier_gain() -> void:
	var w := _tier_world("unique", "improved_max_mp_rank")
	RF.change_job_bare(w, 200)
	w.learn_skill("improved_max_mp")
	w.loadout.set_rank("improved_max_mp", 4)
	w.refresh_player_stats()
	_open_level(w)
	var c: Dictionary = w.pending_cards[0]
	assert_eq(c.skill_changes, {"max_mp_percent": {"before": 8, "after": 18}})
	assert_true(String(c.desc).contains("+5 skill level"))
	assert_true(String(c.desc).contains("10%"), "five levels add ten percentage points, not two")
	assert_true(w.apply_choice("improved_max_mp_rank"))
	assert_eq(w.loadout.level("improved_max_mp"), 9)
	var learning := _tier_world("legendary", "improved_max_mp")
	RF.change_job_bare(learning, 200)
	_open_level(learning)
	assert_true(String(learning.pending_cards[0].desc).contains("+10%"), "learning at rank five grants ten percent")
	assert_true(learning.apply_choice("improved_max_mp"))
	assert_eq(learning.loadout.level("improved_max_mp"), 5)


func test_same_seed_produces_same_tiers_and_per_card_magnitudes_override_defaults() -> void:
	var first := _world()
	var second := _world()
	for draw in 64:
		first.rng.randf()  # Combat rolls have a separate stream from tier rolls.
		assert_eq(first.upgrades.roll_choices(first, first.card_rng, 1),
			second.upgrades.roll_choices(second, second.card_rng, 1), "same card seed, same complete choices")
	var data := RF.quiet_data()
	data.upgrades.rarity.weights = {"epic": 1.0}
	data.upgrades.cards = [{"id": "custom_rank", "kind": "skill_rank", "skill": "energy_bolt", "max_rank": 20,
		"magnitudes": {"epic": 4}, "desc": "+{magnitude} ranks.", "effects": [{"stat": "rank", "value": 1}]}]
	var custom := RunWorld.new(RF.setup("quiet", 43, data))
	RF.place_player(custom, 400)
	RF.change_job_bare(custom, 200)
	custom.learn_skill("energy_bolt")
	_open_level(custom)
	assert_eq(int(custom.pending_cards[0].skill_level_next), 5)
	assert_true(String(custom.pending_cards[0].desc).contains("+4 ranks"))
	assert_true(custom.apply_choice("custom_rank"))
	assert_eq(custom.loadout.level("energy_bolt"), 5)


func test_every_default_tier_gives_more_and_equal_gains_wear_the_lowest_label() -> void:
	var magnitudes: Dictionary = RF.quiet_data().upgrades.magnitudes
	for kind: String in ["skill_rank", "stacking", "skill_new"]:
		var last := 0
		for tier: String in TIERS:
			var value: Variant = magnitudes[kind][tier]
			# JSON numbers parse as floats; require an integer value rather than a string sentinel.
			assert_true((value is int or value is float) and value == int(value), "%s %s is an integer magnitude" % [kind, tier])
			assert_true(int(value) > last, "%s %s gives more than the tier below" % [kind, tier])
			last = int(value)
	var data := RF.quiet_data()
	data.upgrades.rarity.weights = {"epic": 1.0}
	data.upgrades.cards = [{"id": "flat", "kind": "skill_mod", "skill": "three_snails", "max_rank": 10,
		"magnitudes": {"rare": 2, "epic": 2}, "desc": "+{magnitude}.", "effects": [{"stat": "count", "op": "add", "value": 1}]}]
	var flat := RunWorld.new(RF.setup("quiet", 43, data))
	RF.place_player(flat, 400)
	_open_level(flat)
	assert_eq(String(flat.pending_cards[0].tier), "rare", "an Epic equal to Rare is labelled Rare")
	assert_eq(int(flat.pending_cards[0].magnitude), 2)
