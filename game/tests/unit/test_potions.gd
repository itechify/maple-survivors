extends TestCase
## Potion behavior at the seeded RunWorld and pickup seams: stock, canonical restoration, drop rolls, persistence,
## collection and bot use. Synthetic canonical item nodes keep this suite independent of the owner's WZ files.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(seed_value := 10) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = 300
	data.balance.player.mp = 300
	var setup := RF.setup("quiet", seed_value, data)
	setup.item_info = {2000000: {"spec": {"hp": 50}}, 2000003: {"spec": {"mp": 100}}}
	return RunWorld.new(setup)


func test_run_starts_with_five_red_potions_and_no_mp_potions() -> void:
	var w := _world()
	assert_eq(w.player_state.get("potions", {}), {
		"hp": {"item_id": 2000000, "count": 5}, "mp": {"item_id": 2000003, "count": 0}})


func test_hp_drinking_is_instant_uses_canonical_amount_and_has_no_cooldown() -> void:
	var w := _world()
	w.take_hit(200.0, false, "", w.player.pos - Vector2(10, 0))
	var before := int(w.player_state.hp)
	w.drain_events()
	for i in 3:
		assert_true(w.drink_potion("hp"))
	assert_eq(int(w.player_state.hp), before + 150, "three Red Potions restore exactly 3 x canonical 50")
	assert_eq(int(w.player_state.potions.hp.count), 2)
	assert_eq(w.potions.used.hp, 3)
	var events := w.drain_events()
	assert_eq(events.size(), 3)
	for e: Dictionary in events:
		assert_eq(e.type, "potion_used")
		assert_eq(e.kind, "hp")
		assert_eq(e.item_id, 2000000)
		assert_eq(e.restored, 50)
	assert_eq(w.time, 0.0, "drinking does not advance time or wait for a cooldown")


func test_potion_drops_persist_outside_the_exp_cap_then_magnet_into_unlimited_stock() -> void:
	var w := _world()
	w.player.place(Vector2(400, 200), w.fhm)
	w.pickups.tuning.max_active = 1
	w.pickups.tuning.lifetime = 0.1
	var potion := w.spawn_potion("mp", Vector2(800, 200), 10000)
	w.pickups.spawn(Vector2(1000, 200), 1, 4000019)
	w.pickups.spawn(Vector2(1100, 200), 2, 4000019)
	assert_eq(w.pickups.active_count(), 2, "one potion and one EXP drop coexist at EXP cap 1")
	for i in 60:
		w.step(DT, MoveInput.new())
	assert_eq(w.pickups.active[potion], 1, "potions never expire even when EXP has a finite lifetime")
	w.player.place(Vector2(760, 200), w.fhm)
	for i in 30:
		w.step(DT, MoveInput.new())
	assert_eq(int(w.player_state.potions.mp.count), 10000, "bundle adds to unlimited stock")
	assert_eq(w.potions.collected.mp, 10000)
	assert_eq(w.pickups.collected_exp, 0, "potions grant no EXP")
	var collected := w.drain_events().filter(func(e: Dictionary) -> bool:
		return e.type == "pickup_collected" and e.get("kind") == "potion")
	assert_eq(collected.size(), 1)
	assert_eq(collected[0].potion_kind, "mp")
	assert_eq(collected[0].count, 10000)


func test_seeded_normal_and_elite_kills_follow_potion_drop_chances() -> void:
	var measured := {}
	for elite: bool in [false, true]:
		var w := _world(1010 if elite else 10)
		w.balance.potions.drops = DataRepo.load_all().balance.potions.drops.duplicate(true)
		var counts := {"hp": 0, "mp": 0}
		var group := "elite" if elite else "normal"
		var chances: Dictionary = w.balance.potions.drops[group]
		assert_true(float(chances.mp) > float(chances.hp), "MP is more common for every group")
		for i in 500:
			var f := w.fhm.find_below(-900, 190)
			var slot := w.spawn_mob(int(w.kind_of_id[100100]), Vector2(-900, w.fhm.y_at(f, -900)), f, 1.0, elite)
			w.hit_mob(slot, {"damage_min": 1000.0, "damage_max": 1000.0, "magic": false, "crit": 0.0,
				"crit_mult": 1.5, "skill": "three_snails"}, -1)
			w.step(DT, MoveInput.new())
			for e: Dictionary in w.drain_events():
				if e.type == "pickup_spawned" and e.get("kind") == "potion":
					counts[e.potion_kind] += int(e.count)
		for kind: String in counts:
			assert_near(float(counts[kind]) / 500, float(chances[kind]), 0.02 if group == "normal" and kind == "hp" else 0.05,
				"seeded %s %s drop share" % [group, kind])
		measured[group] = counts
	assert_true(int(measured.elite.hp) > int(measured.normal.hp))
	assert_true(int(measured.elite.mp) > int(measured.normal.mp))
	print("  Potion drops / 500 kills: normal %s; elite %s" % [measured.normal, measured.elite])


func _drop_profile_world(frames: Array, global_hp: float = 0.0) -> RunWorld:
	var data := RF.quiet_data()
	data.stages.stages.quiet.keyframes = frames
	data.balance.potions.drops = {"normal": {"hp": global_hp, "mp": 1.0}, "elite": {"hp": 1.0, "mp": 1.0}}
	return RunWorld.new(RF.setup("quiet", 27, data))


func _kill_drop_counts(w: RunWorld, elite := false) -> Dictionary:
	var counts := {"hp": 0, "mp": 0}
	for i in 400:
		var f := w.fhm.find_below(-900, 190)
		var slot := w.spawn_mob(int(w.kind_of_id[100100]), Vector2(-900, w.fhm.y_at(f, -900)), f, 1.0, elite)
		w.hit_mob(slot, {"damage_min": 1000.0, "damage_max": 1000.0, "magic": false, "crit": 0.0,
			"crit_mult": 1.5, "skill": "three_snails"}, -1)
		for e: Dictionary in w.drain_events():
			if e.type == "pickup_spawned" and e.get("kind") == "potion":
				counts[e.potion_kind] += int(e.count)
	return counts


func test_stage_normal_hp_drop_chance_interpolates_without_changing_mp_or_elites() -> void:
	var frames := [{"t": 0, "pool": {"100100": 1}, "normal_hp_drop_chance": 0.0},
		{"t": 10, "pool": {"100100": 1}, "normal_hp_drop_chance": 1.0}]
	var start := _drop_profile_world(frames)
	assert_eq(_kill_drop_counts(start), {"hp": 0, "mp": 400})
	var middle := _drop_profile_world(frames)
	for tick in 300:
		middle.step(DT, MoveInput.new())
	var counts := _kill_drop_counts(middle)
	assert_near(float(counts.hp) / 400.0, 0.5, 0.06, "halfway between zero and one gives a half-share of normal HP drops")
	assert_eq(counts.mp, 400, "MP still uses its global normal chance")
	assert_eq(_kill_drop_counts(_drop_profile_world(frames), true), {"hp": 400, "mp": 400},
		"elite chances ignore the ordinary HP curve")


func test_missing_hp_curve_endpoints_use_global_chance_and_probabilities_hold_clamped() -> void:
	var missing := _drop_profile_world([{"t": 0, "pool": {"100100": 1}}], 0.35)
	assert_near(float(_kill_drop_counts(missing).hp) / 400.0, 0.35, 0.06,
		"an existing stage without the optional field retains its global HP chance")
	var partial := _drop_profile_world([
		{"t": 0, "pool": {"100100": 1}, "normal_hp_drop_chance": 0.0},
		{"t": 10, "pool": {"100100": 1}}], 1.0)
	for tick in 300:
		partial.step(DT, MoveInput.new())
	assert_near(float(_kill_drop_counts(partial).hp) / 400.0, 0.5, 0.06,
		"a missing individual endpoint falls back before interpolation")
	var clipped := _drop_profile_world([
		{"t": 0, "pool": {"100100": 1}, "normal_hp_drop_chance": 2.0},
		{"t": 10, "pool": {"100100": 1}, "normal_hp_drop_chance": -1.0}])
	assert_eq(_kill_drop_counts(clipped).hp, 400, "chance above one clips to one")
	for tick in 900:
		clipped.step(DT, MoveInput.new())
	assert_eq(_kill_drop_counts(clipped).hp, 0, "negative chance clips to zero and holds beyond the last frame")


func test_drink_press_works_while_climbing_and_empty_stock_does_nothing() -> void:
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
	assert_eq(w.player.state, PlayerMotion.ST_LADDER, "drink leaves the player attached to the rope")
	for i in 4:
		assert_true(w.drink_potion("hp"))
	w.drain_events()
	var unchanged := w.player_state.duplicate(true)
	assert_false(w.drink_potion("hp"))
	assert_false(w.drink_potion("mp"))
	assert_eq(w.player_state, unchanged, "no stock means no resource or inventory change")
	assert_true(w.drain_events().is_empty())


func test_bot_drink_threshold_comes_from_survivor_data() -> void:
	var w := _world()
	w.take_hit(200.0, false, "", w.player.pos - Vector2(10, 0))
	assert_true(BotInput.decide(w, {}).drink_hp, "hurt bot drinks below configured 50 percent HP")
	w.balance.potions.bot.hp_threshold = 0.2
	assert_false(BotInput.decide(w, {}).drink_hp, "a lower data threshold changes the decision")
	w.balance.potions.bot.hp_threshold = 0.5
	for i in 5:
		w.drink_potion("hp")
	assert_false(BotInput.decide(w, {}).drink_hp, "no stock means no drink request")


func test_mp_potion_restores_canonical_amount_before_the_waiting_skill_casts() -> void:
	var data := RF.quiet_data()
	data.balance.player.mp = 300
	data.balance.player.skills = []
	var w := RunWorld.new(RF.setup("quiet", 10, data))
	RF.change_job_bare(w, 200)
	RF.place_player(w, 400)
	w.learn_skill("energy_bolt")
	RF.put_mob(w, 1110100, 550, 190, 100)
	w.mob_kinds[int(w.kind_of_id[1110100])].move_speed = 0
	w.spend_mp(int(w.player_state.mp) - 5)
	w.spawn_potion("mp", w.player.pos - Vector2(0, 25), 2)
	w.step(DT, MoveInput.new())
	assert_true(w.player_state.mp_short)
	assert_eq(w.player_state.potions.mp.count, 2)
	assert_true(BotInput.decide(w, {}).drink_mp, "bot drinks below the configured MP threshold")
	w.balance.potions.bot.mp_threshold = 0.01
	assert_true(BotInput.decide(w, {}).drink_mp, "an observed affordability failure also prompts a sip")
	w.drain_events()
	assert_true(w.drink_potion("mp"))
	assert_eq(w.player_state.mp, 105, "Blue Potion restores exactly canonical 100 MP immediately")
	w.step(DT, MoveInput.new())
	var events := w.drain_events()
	var casts := events.filter(func(e: Dictionary) -> bool: return e.type == "cast")
	assert_eq(casts.size(), 1, "the waiting skill fires on the first tick after the drink")
	assert_eq(casts[0].skill, "energy_bolt")
	assert_eq(w.player_state.mp, 99, "100 restored, then canonical 6 spent")
	assert_false(w.player_state.mp_short)
	assert_false(BotInput.decide(w, {}).drink_mp, "without a shortage the lower MP threshold applies")
	w.balance.potions.bot.mp_threshold = 0.3
	assert_true(BotInput.decide(w, {}).drink_mp, "the configured fraction still applies before shortage")
	assert_eq(w.potions.used.mp, 1)
	assert_eq(events[0].type, "potion_used")
	assert_eq(events[0].restored, 100)
	# Input presses share the same restoration-before-casting ordering (instant even during a multi-tick frame).
	w.spend_mp(99)
	for i in 60:
		w.step(DT, MoveInput.new())
	w.drain_events()
	var input := MoveInput.new()
	input.drink_mp = true
	w.step(DT, input)
	assert_eq(w.player_state.mp, 94)
	assert_eq(w.player_state.potions.mp.count, 0)
	assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1)


func test_potion_rolls_have_their_own_stream_independent_of_basic_attack_stances() -> void:
	var a := _world(31)
	var b := _world(31)
	var streams: Array[RandomNumberGenerator] = [b.rng, b.spawn_rng, b.card_rng, b.drop_rng, b.basic_rng,
		b.reward_rng, b.potion_rng]
	var seeds := {}
	for s in streams:
		seeds[s.seed] = true
	assert_eq(seeds.size(), streams.size(), "every RunWorld RNG stream has its own seed")
	for i in 50:
		b.basic_rng.randi_range(0, 4)
	for i in 20:
		assert_eq(b.potion_rng.randf(), a.potion_rng.randf(), "basic swings never shift potion drop rolls")
