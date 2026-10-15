extends TestCase
## Potion tier cards through seeded RunWorld/card seams: gates, stock conversion, future drops and sparse draws.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BALANCE := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0


func test_potion_cards_follow_level_gates_and_require_the_previous_item() -> void:
	var w := RF.quiet_world(400, 11)
	for example: Array in [[9, []], [10, ["orange_potion"]], [19, ["orange_potion"]],
			[20, ["orange_potion", "mana_elixir"]], [25, ["orange_potion", "mana_elixir"]]]:
		w.progression.level = example[0]
		var eligible := w.upgrades.eligible(w)
		for id: String in ["orange_potion", "white_potion", "mana_elixir"]:
			assert_eq(id in eligible, id in example[1], "%s eligibility at Lv %d" % [id, example[0]])
	assert_eq(w.player_state.potions.hp.item_id, 2000000)
	assert_eq(w.player_state.potions.mp.item_id, 2000003)


func test_tier_cards_preserve_stock_follow_the_ladder_and_change_future_kill_drops() -> void:
	var w := RF.quiet_world(400, 111)
	w.spawn_potion("mp", w.player.pos - Vector2(0, 25), 4)
	w.step(DT, MoveInput.new())
	w.drain_events()
	w.progression.level = 10
	assert_eq(w.upgrades.apply("orange_potion", w), 1)
	assert_eq(w.player_state.potions.hp, {"item_id": 2000001, "count": 5})
	assert_false("orange_potion" in w.upgrades.eligible(w), "tier cards are one-time")
	assert_false("white_potion" in w.upgrades.eligible(w), "White still needs Lv 25")
	w.progression.level = 24
	assert_false("white_potion" in w.upgrades.eligible(w))
	w.progression.level = 25
	assert_has(w.upgrades.eligible(w), "white_potion")
	assert_eq(w.upgrades.apply("white_potion", w), 1)
	assert_eq(w.player_state.potions.hp, {"item_id": 2000002, "count": 5})
	assert_eq(w.upgrades.apply("mana_elixir", w), 1)
	assert_eq(w.player_state.potions.mp, {"item_id": 2000006, "count": 4})
	var events := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "potion_tier_up")
	assert_eq(events.size(), 3)
	if events.size() == 3:
		assert_eq(events[0], {"type": "potion_tier_up", "kind": "hp", "from_item_id": 2000000, "item_id": 2000001, "count": 5})
		assert_eq(events[1].from_item_id, 2000001)
		assert_eq(events[1].item_id, 2000002)
		assert_eq(events[2].kind, "mp")
	for id: String in ["orange_potion", "white_potion", "mana_elixir"]:
		assert_false(id in w.upgrades.eligible(w))
		assert_eq(w.upgrades.apply(id, w), 0, "taking a tier twice does nothing")
	w.balance.potions.drops.normal = {"hp": 1.0, "mp": 1.0}
	var slot := RF.put_mob(w, 100100, 800)
	w.hit_mob(slot, {"damage_min": 1000.0, "damage_max": 1000.0, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)
	var drops := w.drain_events().filter(func(e: Dictionary) -> bool:
		return e.type == "pickup_spawned" and e.get("kind") == "potion")
	assert_eq(drops.size(), 2)
	var ids := drops.map(func(e: Dictionary) -> int: return int(e.item_id))
	assert_has(ids, 2000002)
	assert_has(ids, 2000006)


func test_sparse_draws_offer_only_available_cards_and_empty_levelups_continue() -> void:
	for n in 3:
		var data := RF.quiet_data()
		var keep: Array = ["orange_potion", "mana_elixir"].slice(0, n)
		data.upgrades.cards = data.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.id in keep)
		var w := RunWorld.new(RF.setup("quiet", 11 + n, data))
		w.change_job(200)
		RF.place_player(w, 400)
		w.progression.level = 20
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var drawn := w.upgrades.roll_choices(w, rng, 3)
		assert_eq(drawn.size(), n, "no substitute cards in a %d-card draw" % n)
		for card: Dictionary in drawn:
			assert_true(card.id in keep)
		w.drain_events()
		w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
		w.step(DT, MoveInput.new())
		assert_eq(w.player_state.level, 21)
		if n == 0:
			assert_eq(w.state, RunWorld.PLAYING, "levelup continues when there is no eligible card")
			assert_false(w.progression.has_pending())
			assert_true(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "choice_pending").is_empty())
		else:
			assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
			assert_eq(w.pending_cards.size(), n)
			assert_true(w.apply_choice(String(w.pending_cards[0].id)))
			assert_eq(w.state, RunWorld.PLAYING)


func test_bot_values_potion_tiers_above_general_defence_cards() -> void:
	var w := RF.quiet_world(400, 11)
	w.progression.level = 25
	for id: String in ["orange_potion", "mana_elixir"]:
		var cards := [w.upgrades.choice_card("max_hp", w), w.upgrades.choice_card(id, w)]
		assert_eq(BotInput.pick_card_for(w, cards), id)
		assert_true(BotInput.card_score(w, cards[1]) > BotInput.card_score(w, cards[0]))


func test_bot_potion_tier_priority_uses_survivor_data_with_legacy_fallback() -> void:
	var w := RF.quiet_world(400, 27)
	RF.change_job_bare(w, 200)
	w.loadout.add_skill("energy_bolt")
	w.progression.level = 10
	var cards := [w.upgrades.choice_card("energy_bolt_rank", w), w.upgrades.choice_card("orange_potion", w)]
	w.balance.potions.bot.erase("tier_score")
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "missing tuning preserves the legacy policy")
	w.balance.potions.bot["tier_score"] = 90.0
	assert_eq(BotInput.pick_card_for(w, cards), "orange_potion", "design data can prioritize permanent potion supply")


func test_first_and_random_balance_policies_can_take_both_potion_tiers() -> void:
	for policy: String in ["first", "random"]:
		var taken := {"orange_potion": 0, "mana_elixir": 0}
		for seed_value in range(1, 21):
			var data := RF.quiet_data()
			data.upgrades.cards = data.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.kind == "potion_tier")
			var w := RunWorld.new(RF.setup("quiet", seed_value, data))
			w.change_job(200)
			RF.place_player(w, 400)
			w.progression.level = 20
			w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
			w.step(DT, MoveInput.new())
			assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			BALANCE.choose(w, policy, rng, [])
			assert_eq(w.state, RunWorld.PLAYING)
			for id: String in taken:
				taken[id] += int(w.loadout.card_ranks.get(id, 0))
		assert_true(int(taken.orange_potion) > 0, "%s takes Orange" % policy)
		assert_true(int(taken.mana_elixir) > 0, "%s takes Mana Elixir" % policy)
