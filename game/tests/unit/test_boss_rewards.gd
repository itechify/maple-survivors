extends TestCase
## Seeded boss death rewards and bonus-before-clear ordering through RunWorld's public tick/card/pickup seams.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0,
		"rewards": {"exp_mult": 5, "exp_drops": 13, "spread": 100, "potions": {"hp": 2, "mp": 3}, "bonus_choices": 1}}])
	var w := RunWorld.new(RF.setup("quiet", 20, data))
	RF.place_player(w, 400)
	w.god = true
	for i in 6:
		w.step(DT, MoveInput.new())
	w.drain_events()
	return w


func _kill(w: RunWorld) -> void:
	w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)


func test_boss_shower_conserves_configured_exp_and_never_drops_potions() -> void:
	var w := _world()
	w.progression.level = 25
	w.apply_potion_schedule(25, false) # White Potions and Mana Elixirs by the level schedule
	w.balance.potions.drops = {"normal": {"hp": 1.0, "mp": 1.0}, "elite": {"hp": 1.0, "mp": 1.0}}
	w.drain_events()
	_kill(w)
	var total := 0
	var drops := 0
	var bundles := {}
	for i in w.pickups.capacity():
		if w.pickups.active[i] == 0:
			continue
		if w.pickups.kind[i] == PickupSystem.EXP:
			total += w.pickups.exp[i]
			drops += 1
		elif w.pickups.kind[i] != PickupSystem.MESO and w.pickups.kind[i] != PickupSystem.EQUIP:
			bundles[int(w.pickups.item_id[i])] = true
	assert_eq(total, 600, "canonical Mano EXP 120 × survivor reward multiplier 5, with no extra ordinary drop")
	assert_eq(drops, 13, "the split preserves the total despite a remainder")
	assert_eq(bundles, {}, "even legacy drop tuning cannot create potion pickups")


func test_final_boss_bonus_choice_precedes_clear_and_does_not_consume_a_queued_level() -> void:
	var w := _world()
	w.progression.add_exp(w.progression.exp_to_next())
	w.refresh_player_stats()
	var level := w.progression.level
	var queue := w.progression.queue.duplicate()
	_kill(w)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "final death opens its bonus instead of clearing")
	var events := w.drain_events()
	var choices := events.filter(func(e: Dictionary) -> bool: return e.type == "choice_pending")
	assert_eq(choices.size(), 1)
	if not choices.is_empty():
		assert_true(bool(choices[0].get("bonus", false)))
	assert_true(events.filter(func(e: Dictionary) -> bool: return e.type == "stage_cleared").is_empty())
	assert_eq(w.progression.level, level, "bonus grants no level")
	if w.pending_cards.is_empty():
		return
	assert_true(w.apply_choice(String(w.pending_cards[0].id)))
	assert_eq(w.progression.queue, queue, "bonus does not consume the queued normal level")
	assert_eq(w.progression.level, level)
	var normal := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "choice_pending")
	assert_eq(normal.size(), 1)
	if not normal.is_empty():
		assert_false(bool(normal[0].get("bonus", true)))
	assert_true(w.apply_choice(String(w.pending_cards[0].id)))
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the loose boss EXP now queues its own level rewards")
	RF.auto_choose(w)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CLEARED)


func test_exhausted_boss_and_level_rewards_each_offer_elixir_before_clear() -> void:
	var w := _world()
	var data: Dictionary = DataRepo.load_all().upgrades
	data.cards = []
	w.upgrades = UpgradePool.from_data(data)
	w.progression.add_exp(w.progression.exp_to_next())
	w.refresh_player_stats()
	var queue := w.progression.queue.duplicate()
	_kill(w)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "an exhausted boss reward must still open")
	assert_true(w.choice_bonus)
	assert_eq(w.pending_cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	assert_true(w.apply_choice("elixir"))
	assert_eq(w.progression.queue, queue, "the bonus consumes no queued level")
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the normal level still opens its own reward")
	assert_false(w.choice_bonus)
	assert_eq(w.pending_cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	assert_true(w.apply_choice("elixir"))
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "swept boss EXP also needs its fallback choices")
	RF.auto_choose(w)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CLEARED, "clear waits for boss, queued and swept-EXP rewards")
