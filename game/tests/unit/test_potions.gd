extends TestCase
## Potion behavior at seeded RunWorld seams: cooldowns, canonical restoration, no drop rolls, rope input and bot use. Synthetic canonical item nodes keep this suite independent of the owner's WZ files.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(seed_value := 10) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = 300
	var setup := RF.setup("quiet", seed_value, data)
	setup.item_info = {2000000: {"spec": {"hp": 50}}}
	return RunWorld.new(setup)


func test_normal_and_elite_kills_never_drop_potions_or_draw_reserved_stream_7() -> void:
	for elite: bool in [false, true]:
		var w := _world(238)
		w.balance.potions.drops = {"normal": {"hp": 1.0, "mp": 1.0}, "elite": {"hp": 1.0, "mp": 1.0}}
		var reserved_state := w.potion_rng.state
		for i in 100:
			var slot := RF.put_mob(w, 100100, -900)
			w.mob_elite[slot] = 1 if elite else 0
			w.hit_mob(slot, {"damage_min": 1000.0, "damage_max": 1000.0, "magic": false,
				"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
			w.step(DT, MoveInput.new())
			for e: Dictionary in w.drain_events():
				if e.type == "pickup_spawned":
					assert_true(e.kind in ["exp", "meso", "equip"], "no potion pickup, even with obsolete drop tuning")
		assert_eq(w.kills, 100)
		assert_eq(w.potion_rng.state, reserved_state, "stream 7 stays reserved without draws")


func test_drink_press_works_while_climbing_and_cooldown_press_does_nothing() -> void:
	var w := _world()
	w.player.place(Vector2(-100, 200), w.fhm)
	w.step(DT, MoveInput.make(false, false, true))
	assert_eq(w.player.state, PlayerMotion.ST_LADDER)
	w.take_hit(200.0, false, "", w.player.pos - Vector2(10, 0))
	var before := int(w.player_state.hp)
	var input := MoveInput.make(false, false, true)
	input.drink_hp = true
	w.step(DT, input)
	assert_eq(int(w.player_state.hp), before + 50)
	assert_eq(w.player.state, PlayerMotion.ST_LADDER)
	w.drain_events()
	var unchanged := w.player_state.duplicate(true)
	assert_false(w.drink_potion("hp"))
	assert_eq(w.player_state, unchanged)
	assert_true(w.drain_events().is_empty())
	assert_false(w.drink_potion("mp"), "there is no MP potion (#285)")


func test_bot_drinks_only_when_ready_and_most_of_a_potion_lands() -> void:
	var w := _world()
	w.take_hit(200.0, false, "", w.player.pos - Vector2(10, 0))
	var missing := float(w.player_state.max_hp) - float(w.player_state.hp)
	assert_true(BotInput.decide(w, {}).drink_hp)
	w.balance.potions.bot.min_restore_fraction = missing / 50.0 + 0.1
	assert_false(BotInput.decide(w, {}).drink_hp)
	w.balance.potions.bot.min_restore_fraction = 0.5
	assert_true(w.drink_potion("hp"))
	assert_false(BotInput.decide(w, {}).drink_hp, "a useful sip still waits for its cooldown")
	for tick in 1201:
		w.step(DT, MoveInput.new())
	assert_true(BotInput.decide(w, {}).drink_hp, "unlimited use resumes at cooldown expiry")


func test_bot_waste_guard_caps_the_restore_at_the_pool() -> void:
	# tier C (#229): a restore beyond the pool counts as the pool, so the 1000-2000 point steps stay drinkable, but never
	# as less than pool_floor (0.25) of the potion, so a tiny pool still never wastes a big one.
	var w := _world()
	w.potions.item_info[2022003] = {"spec": {"hp": 1000}}
	w.potions.item_info[2001001] = {"spec": {"hp": 2000}}
	var pool := float(w.player_state.max_hp)
	assert_eq(pool, 300.0, "the fixture pool")
	assert_true(w.potions.upgrade("hp", 2022003), "Unagi restores 1000 HP: more than the pool, its floor 250 is below it")
	assert_true(BotInput.worth_drinking(w, "hp", 150.0, 0.5), "half the pool missing is worth a potion that overflows it")
	assert_false(BotInput.worth_drinking(w, "hp", 149.0, 0.5))
	assert_true(w.potions.upgrade("hp", 2001001), "Ice Cream Pop restores 2000 HP: the 500 floor exceeds the pool")
	assert_true(BotInput.worth_drinking(w, "hp", 250.0, 0.5), "counted as at least a quarter of the potion")
	assert_false(BotInput.worth_drinking(w, "hp", 249.0, 0.5), "a small pool does not drink a huge potion for a sliver")
	w.potions.upgrade("hp", 2000000)
	assert_true(BotInput.worth_drinking(w, "hp", 25.0, 0.5), "a potion below the pool is unchanged: half of its restore")
	assert_false(BotInput.worth_drinking(w, "hp", 24.0, 0.5))
	# The same through the bot's decision: hit for most of the pool, Unagi held.
	assert_true(w.potions.upgrade("hp", 2022003))
	w.take_hit(pool * 0.8, false, "", w.player.pos - Vector2(10, 0))
	assert_true(pool - float(w.player_state.hp) >= 0.5 * pool, "the hit takes at least half the pool")
	assert_true(BotInput.decide(w, {}).drink_hp)
	w.drink_potion("hp")
	assert_eq(int(w.player_state.hp), int(pool), "the overheal is capped by the pool")
	assert_false(BotInput.decide(w, {}).drink_hp, "full HP drinks nothing")
