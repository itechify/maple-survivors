extends TestCase
## Spec #225 / #228: no job-neutral cards but the Power Elixir filler, and potions that upgrade by character level from
## the balance.potions.schedule through RunWorld's level-up and snapshot-load seams (seeded RNG, fixed dt).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const REMOVED := ["magnet", "orange_potion", "white_potion", "mana_elixir"]


## Earns exactly one level at a time through a real EXP pickup and answers every window (Magician line).
func _level_up_once(w: RunWorld) -> void:
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	BotInput.auto_choose(w, false, 210)


func _tier_events(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "potion_tier_up")


func _loaded(character: Dictionary, p_seed := 5) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, RF.quiet_data())
	setup.character = character
	return RunWorld.new(setup)


func _snapshot_at(level: int) -> Dictionary:
	var w := RF.quiet_world(400.0, 3)
	var s := w.character_snapshot()
	s.level = level
	s.exp = 0
	return s


func test_schedule_data_ships_the_three_card_gates() -> void:
	var balance: Dictionary = DataRepo.load_all().balance
	var potions: Dictionary = balance.potions
	assert_eq((potions.schedule as Array).size(), 3, "exactly the three old card gates")
	assert_eq(PotionSchedule.steps(balance), [{"level": 10, "kind": "hp", "item": 2000001},
		{"level": 20, "kind": "mp", "item": 2000006}, {"level": 25, "kind": "hp", "item": 2000002}])
	assert_has(potions, "_schedule")


func test_schedule_fires_at_exactly_levels_10_20_and_25_keeping_the_stock() -> void:
	var w := RF.quiet_world(400.0, 111)
	w.potions.add("mp", 4)
	w.drain_events()
	var expected := {10: ["hp", 2000000, 2000001, 5], 20: ["mp", 2000003, 2000006, 4], 25: ["hp", 2000001, 2000002, 5]}
	while w.progression.level < 26:
		_level_up_once(w)
		var level := w.progression.level
		var events := _tier_events(w)
		if expected.has(level):
			assert_eq(events.size(), 1, "one notice event at Lv %d" % level)
			if events.size() == 1:
				var want: Array = expected[level]
				assert_eq(events[0], {"type": "potion_tier_up", "kind": want[0], "from_item_id": want[1],
					"item_id": want[2], "count": want[3]}, "step at Lv %d" % level)
		else:
			assert_eq(events.size(), 0, "no event at Lv %d" % level)
		var hp_item := 2000002 if level >= 25 else (2000001 if level >= 10 else 2000000)
		assert_eq(w.player_state.potions.hp.item_id, hp_item, "HP item at Lv %d" % level)
		assert_eq(w.player_state.potions.mp.item_id, 2000006 if level >= 20 else 2000003, "MP item at Lv %d" % level)
		assert_eq(w.player_state.potions.hp.count, 5)
		assert_eq(w.player_state.potions.mp.count, 4)


func test_several_levels_in_one_tick_apply_every_due_step_in_level_order() -> void:
	var w := RF.quiet_world(400.0, 12)
	w.drain_events()
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.curve.total_to(26) + 1, 4000019)
	w.step(DT, MoveInput.new())
	var events := _tier_events(w)
	assert_eq(events.map(func(e: Dictionary) -> int: return int(e.item_id)), [2000001, 2000006, 2000002])
	assert_eq(w.player_state.potions.hp.item_id, 2000002)
	assert_eq(w.player_state.potions.mp.item_id, 2000006)


func test_new_potion_item_is_what_drops_afterwards() -> void:
	var w := RF.quiet_world(400.0, 13)
	while w.progression.level < 25:
		_level_up_once(w)
	w.drain_events()
	w.balance.potions.drops.normal = {"hp": 1.0, "mp": 1.0}
	var slot := RF.put_mob(w, 100100, 800)
	w.hit_mob(slot, {"damage_min": 1000.0, "damage_max": 1000.0, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)
	var ids := w.drain_events().filter(func(e: Dictionary) -> bool:
		return e.type == "pickup_spawned" and e.get("kind") == "potion").map(func(e: Dictionary) -> int: return int(e.item_id))
	ids.sort()
	assert_eq(ids, [2000002, 2000006])


func test_lv38_fixture_loads_with_white_and_mana_elixir_without_notices() -> void:
	var text := FileAccess.get_file_as_string("res://tests/fixtures/characters/lv35_magician_2nd.json")
	var character: Dictionary = JSON.parse_string(text)
	assert_eq(int(character.level), 38)
	character.potions.hp.item_id = 2000000
	character.potions.mp.item_id = 2000003
	var w := _loaded(character)
	assert_eq(w.player_state.potions.hp, {"item_id": 2000002, "count": int(character.potions.hp.count)})
	assert_eq(w.player_state.potions.mp, {"item_id": 2000006, "count": int(character.potions.mp.count)})
	assert_eq(_tier_events(w).size(), 0, "a load catches up silently")
	var untouched: Dictionary = JSON.parse_string(text)
	var v := _loaded(untouched)
	assert_eq(v.player_state.potions.hp.item_id, 2000002)
	assert_eq(v.player_state.potions.mp.item_id, 2000006)


func test_snapshot_catch_up_applies_only_steps_up_to_its_level_and_never_downgrades() -> void:
	for example: Array in [[9, 2000000, 2000003], [10, 2000001, 2000003], [19, 2000001, 2000003],
			[20, 2000001, 2000006], [24, 2000001, 2000006], [25, 2000002, 2000006], [60, 2000002, 2000006]]:
		var w := _loaded(_snapshot_at(example[0]))
		assert_eq(w.player_state.potions.hp.item_id, example[1], "HP at Lv %d" % example[0])
		assert_eq(w.player_state.potions.mp.item_id, example[2], "MP at Lv %d" % example[0])
	var white := _snapshot_at(12)
	white.potions.hp.item_id = 2000002
	assert_eq(_loaded(white).player_state.potions.hp.item_id, 2000002, "White at Lv 12 is never downgraded to Orange")
	var counted := _snapshot_at(30)
	counted.potions.hp.count = 17
	assert_eq(_loaded(counted).player_state.potions.hp.count, 17, "catch-up keeps the stock")


func test_no_draw_contains_a_removed_card() -> void:
	var data := DataRepo.load_all()
	for c: Dictionary in data.upgrades.cards:
		assert_false(String(c.id) in REMOVED, "%s is gone from the data" % c.id)
		assert_ne(String(c.kind), "potion_tier")
	for job in [0, 200, 210]:
		for seed_value in range(1, 9):
			var w := RF.quiet_world(400.0, seed_value)
			RF.change_job_bare(w, job)
			w.progression.level = 30
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var draws: Array = []
			draws.append_array(w.upgrades.roll_choices(w, rng, 3))
			w.choice_bonus = true
			draws.append_array(w.upgrades.roll_choices(w, rng, 3))
			w.choice_bonus = false
			draws.append_array(w.upgrades.roll_advancement_choices(w, rng, 3))
			for offered: Dictionary in draws:
				assert_false(String(offered.id) in REMOVED, "job %d seed %d offered %s" % [job, seed_value, offered.id])
			assert_false(w.upgrades.eligible(w).any(func(id: String) -> bool: return id in REMOVED))


func test_exhausted_job_pool_offers_the_power_elixir_alone_and_the_run_continues() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	var w := RunWorld.new(RF.setup("quiet", 21, data))
	RF.place_player(w, 400)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	assert_eq(w.upgrades.roll_choices(w, rng, 3).map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	w.choice_bonus = true
	assert_eq(w.upgrades.roll_choices(w, rng, 3).map(func(c: Dictionary) -> String: return c.id), ["elixir"], "boss reward")
	w.choice_bonus = false
	assert_eq(w.upgrades.roll_advancement_choices(w, rng, 3).map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	w.drain_events()
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	assert_eq(w.pending_cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	assert_true(w.apply_choice("elixir"))
	assert_eq(w.state, RunWorld.PLAYING)
	assert_false(w.progression.has_pending())
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the next level-up opens again")


func test_a_pool_without_any_card_never_opens_an_unanswerable_window() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	data.upgrades.erase("fallback")
	var w := RunWorld.new(RF.setup("quiet", 22, data))
	RF.place_player(w, 400)
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.PLAYING, "nothing to offer: the level-up is consumed instead of soft-locking")
	assert_false(w.progression.has_pending())


func test_snapshot_with_magnet_ranks_loads_with_the_base_radius() -> void:
	var character := _snapshot_at(20)
	character.card_ranks["magnet"] = 3
	character.card_ranks["improved_max_mp"] = 2
	character.player_mods["magnet"] = [0.0, 1.953125]
	var w := _loaded(character)
	assert_eq(w.magnet_r, float(w.balance.magnet_radius))
	assert_false(w.loadout.card_ranks.has("magnet"))
	assert_false(w.loadout.player_mods.has("magnet"))
	assert_eq(int(w.loadout.card_ranks.get("improved_max_mp", 0)), 2, "other ranks are kept")
	assert_false(w.character_snapshot().card_ranks.has("magnet"))
	var migrated := CharacterSnapshot.migrate(character, w.jobs, {})
	assert_false(migrated.card_ranks.has("magnet"))
	assert_false(migrated.player_mods.has("magnet"))
	assert_true(character.card_ranks.has("magnet"), "the source is not mutated")


func test_notice_text_uses_v83_item_names_with_a_plural_s() -> void:
	assert_eq(PotionSchedule.notice_text("Red Potion", "Orange Potion"), "Your Red Potions are now Orange Potions.")
	assert_eq(PotionSchedule.notice_text("Blue Potion", "Mana Elixir"), "Your Blue Potions are now Mana Elixirs.")
