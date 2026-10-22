extends TestCase
## Spec #237: unlimited potions at the seeded, fixed-tick RunWorld boundary.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_drink_starts_independent_cooldowns_and_repeated_press_is_silent() -> void:
	var w := RF.quiet_world(400.0, 238)
	w.spend_mp(int(w.player_state.mp))
	assert_true(w.drink_potion("hp"))
	w.drain_events()
	assert_false(w.drink_potion("hp"), "a second press must wait for the HP cooldown")
	assert_true(w.drain_events().is_empty(), "a rejected drink emits nothing")
	assert_true(w.drink_potion("mp"), "HP does not block MP; neither kind needs stock")
	assert_eq(w.potions.snapshot().hp.get("cooldown_left"), 20.0)
	assert_eq(w.potions.snapshot().mp.get("cooldown_left"), 10.0)
	for tick in 60:
		w.step(DT, MoveInput.new())
	assert_near(float(w.potions.snapshot().hp.get("cooldown_left", -1)), 19.0, 0.0001)


func test_legacy_stock_is_ignored_and_rounds_start_ready_at_the_scheduled_tier() -> void:
	var character := RF.quiet_world(400.0, 238).character_snapshot()
	character.level = 25
	character.potions = {"hp": {"item_id": 2001001, "count": 900}, "mp": {"item_id": 2000003, "count": 0}}
	assert_eq(CharacterSnapshot.validation_error(character), "")
	var setup := RF.setup("quiet", 238)
	setup.character = character
	var w := RunWorld.new(setup)
	assert_eq(w.potions.snapshot().hp.item_id, 2000002, "legacy item and count do not override the schedule")
	assert_eq(w.potions.snapshot().mp.item_id, 2000006)
	assert_eq(w.potions.snapshot().hp.get("cooldown_left"), 0.0)
	assert_true(w.drink_potion("hp"))
	assert_false(w.character_snapshot().has("potions"), "neither stock nor cooldowns are saved")
	assert_false(CharacterSnapshot.migrate(character, w.jobs, {}).has("potions"))


func test_tier_upgrade_keeps_remaining_cooldown_and_next_drink_uses_the_new_spec() -> void:
	var w := RF.quiet_world(400.0, 238)
	assert_true(w.drink_potion("hp"))
	for tick in 300:
		w.step(DT, MoveInput.new())
	w.apply_potion_schedule(10, true)
	assert_eq(w.potions.item_id("hp"), 2000001)
	assert_near(float(w.potions.cooldown_left.hp), 15.0, 0.0001)
	assert_false(w.drink_potion("hp"))
	for tick in 901:
		w.step(DT, MoveInput.new())
	assert_true(w.potions.is_ready("hp"))
	w.drain_events()
	assert_true(w.drink_potion("hp"))
	var event: Dictionary = w.drain_events()[0]
	assert_eq(event.item_id, 2000001)
	assert_false(event.has("count"))
	assert_eq(w.potions.used.hp, 2)


func test_choice_pause_freezes_cooldown_until_fixed_ticks_resume() -> void:
	var w := RF.quiet_world(400.0, 238)
	assert_true(w.drink_potion("hp"))
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	var before := float(w.potions.cooldown_left.hp)
	var before_time := w.time
	for tick in 1200:
		w.step(DT, MoveInput.new())
	assert_eq(w.time, before_time)
	assert_eq(w.potions.cooldown_left.hp, before)
	assert_false(w.drink_potion("hp"))
	RF.auto_choose(w)
	w.step(DT, MoveInput.new())
	assert_near(float(w.potions.cooldown_left.hp), before - DT, 0.0001)


func test_unlimited_drinks_resume_after_exactly_the_configured_fixed_ticks() -> void:
	var w := RF.quiet_world(400.0, 238)
	for cycle in 3:
		assert_true(w.drink_potion("hp"))
		assert_true(w.drink_potion("mp"))
		for tick in 600:
			w.step(DT, MoveInput.new())
		assert_eq(w.potions.cooldown_left.mp, 0.0, "MP ready after exactly ten seconds")
		assert_true(w.potions.is_ready("mp"))
		assert_false(w.potions.is_ready("hp"))
		for tick in 600:
			w.step(DT, MoveInput.new())
		assert_eq(w.potions.cooldown_left.hp, 0.0, "HP ready after exactly twenty seconds")
	assert_eq(w.potions.used, {"hp": 3, "mp": 3})
