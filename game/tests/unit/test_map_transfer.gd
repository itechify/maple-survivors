extends TestCase
## Fixed-tick seeded map boundaries through RunWorld's transfer, choice and event APIs.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MF := preload("res://tests/fixtures/mano_fixtures.gd")
const PF := preload("res://tests/fixtures/pet_fixtures.gd")
const CAMPER := preload("res://tools/camper_input.gd")
const MAPS := preload("res://tests/fixtures/map_transfer_fixtures.gd")
const DT := 1.0 / 60.0


func _setup(seconds := 300.0) -> Dictionary:
	return MAPS.setup(seconds)


func test_map_clock_starts_at_the_scheduled_curve_offset() -> void:
	var w := RunWorld.new(_setup())
	assert_true(w.has_method("curve_time"), "the binding curve clock exists")
	assert_true(w.has_method("current_map_id"), "the binding map identity exists")
	if not w.has_method("curve_time") or not w.has_method("current_map_id"):
		return
	assert_eq(w.call("current_map_id"), 100000000)
	assert_eq(w.call("curve_time"), 0.0)
	w.time = 420.0
	w.set("map_index", 1)
	w.set("map_entered_at", 410.0)
	assert_eq(w.call("curve_time"), 310.0, "slow kills do not push the next map's curve ahead")


func _ticks(w: RunWorld, count: int) -> void:
	for tick in count:
		w.step(DT, MoveInput.new())


func _kill(w: RunWorld) -> void:
	var record: Dictionary = w.bosses.records[w.map_index]
	assert_true(int(record.slot) >= 0, "the current map's boss arrived")
	# Twice: a boss with a final form (King Clang, #452) dies as its shell first and then as its form.
	for i in 2:
		if int(record.slot) < 0 or bool(record.dead):
			break
		w.hit_mob(int(record.slot), {"damage_min": 1e9, "damage_max": 1e9, "magic": false,
			"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)


func test_next_boss_waits_three_hundred_seconds_from_entry_after_fast_or_slow_kill() -> void:
	for kill_at in [310, 420]:
		var w := RunWorld.new(_setup())
		w.god = true
		assert_eq(w.bosses.records.size(), 3)
		if w.bosses.records.size() != 3:
			continue
		_ticks(w, kill_at * 60)
		assert_eq(w.bosses.live_count(), 1, "future maps do not arm bosses")
		_kill(w)
		w.step(DT, MoveInput.new())
		assert_true(w.transfer_pending)
		assert_near(w.time, float(kill_at), 1e-6, "the kill admits no extra combat tick")
		w.advance_map()
		assert_eq(w.map_index, 1)
		assert_eq(w.current_map_id(), 100000001)
		assert_near(w.curve_time(), 300.0, 1e-6)
		assert_near(float(w.bosses.records[1].arrival), float(kill_at + 300), 1e-6)
		_ticks(w, 300 * 60 - 1)
		assert_eq(w.bosses.live_count(), 0)
		w.step(DT, MoveInput.new())
		assert_near(float(w.bosses.records[1].spawn_time), float(kill_at + 300), 1e-6)
		assert_eq(w.bosses.records[1].map_index, 1)
		assert_eq(w.bosses.records[1].map_id, 100000001)


func test_boss_kill_freezes_both_directions_and_sweeps_before_choices_once() -> void:
	var setup := _setup(0.1)
	setup.data.stages.stages.quiet.maps[0].boss.rewards = {"bonus_choices": 1, "exp_mult": 2.0}
	var w := RunWorld.new(setup)
	w.god = true
	_ticks(w, 60)
	w.god = false
	var ordinary := RF.put_mob(w, 100100, w.player.pos.x)
	w.swarm.alpha[ordinary] = 1.0
	var hp := w.swarm.hp[ordinary]
	w.pickups.spawn(Vector2(1300, -500), 2, 4000000, w.player.pos)
	w.spawn_meso(Vector2(1300, -500), 123)
	var item := Equipment.create(1002001, {"reqLevel": 200})
	w.spawn_equipment(Vector2(1300, -500), item)
	w.progression.level = 9
	w.refresh_player_stats(false)
	w.pickups.spawn(Vector2(1400, -500), w.progression.exp_to_next(), 4000000, w.player.pos)
	var before_hp: int = w.player_state.hp
	_kill(w)
	assert_eq(w.take_hit(100000.0, false, "", w.player.pos, {"source_kind": "boss_attack"}), 0)
	w.hit_mob(ordinary, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	assert_eq(w.swarm.hp[ordinary], hp, "later same-tick attack lines cannot damage mobs")
	var t := w.time
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	assert_false(w.transfer_pending)
	w.advance_map()
	assert_eq(w.map_index, 0, "the boss reward must be answered before transfer")
	assert_eq(w.mesos, 123)

	assert_eq(w.equips_collected, 1)
	assert_eq(w.pickups.active_count(), 0, "the sweep precedes every choice")
	var swept := w.pickups.collected_exp
	assert_true(swept > 2, "includes the boss shower")
	assert_true(w.apply_choice(String(w.pending_cards[0].id)))
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the swept EXP's level-up card follows (no job window, #284)")
	BotInput.auto_choose(w)
	assert_true(w.transfer_pending)
	assert_eq(w.time, t)
	assert_eq(w.kills, 1, "ordinary mobs vanish without kill credit")
	assert_eq(w.swarm.alive_count(), 0)
	assert_eq(w.pickups.collected_exp, swept)
	assert_true(int(w.player_state.hp) >= before_hp, "only progression may refill HP")
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "map_cleared").size(), 1)
	for tick in 120:
		w.step(DT, MoveInput.new())
	assert_eq(w.time, t)
	assert_eq(w.drain_events(), [])
	assert_eq(w.pickups.collected_exp, swept)
	assert_eq(w.mesos, 123)


func test_projectile_boss_kill_stops_piercing_blasts_and_later_shots_in_the_same_tick() -> void:
	for blast in [false, true]:
		var w := RunWorld.new(_setup(0.1))
		w.god = true
		_ticks(w, 60)
		var boss := int(w.bosses.records[0].slot)
		w.swarm.x[boss] = 0.0
		w.swarm.y[boss] = 0.0
		var ordinary := RF.put_mob(w, 100100, 70.0, -10.0)
		w.swarm.alpha[ordinary] = 1.0
		var spec := {"x": -20.0, "y": -10.0, "vx": 6000.0, "range": 500.0,
			"dmg_min": 1000000.0, "dmg_max": 1000000.0, "pierce": 3}
		if blast:
			spec.impact_blast = {"box": Rect2(-200, -100, 400, 200), "count": 6, "visual": ""}
		w.projectiles.spawn(spec)
		w.projectiles.spawn(spec)
		w.drain_events()
		w.step(DT, MoveInput.new())
		var events := w.drain_events()
		assert_true(w.transfer_pending)
		assert_eq(w.kills, 1)
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit").size(), 1,
			"the killing line is the last damaging event, including a shell's secondary blast targets")


func test_full_equip_tab_blocks_once_without_stalling_then_discards_the_uncollected_item() -> void:
	var w := RunWorld.new(_setup(0.1))
	w.god = true
	_ticks(w, 60)
	while w.equipment.inventory.size() < w.inventory_slots():
		w.equipment.inventory.append(Equipment.create(1002001, {}))
	var drop := w.spawn_equipment(Vector2(1300, -500), Equipment.create(1002002, {}))
	w.spawn_meso(Vector2(1300, -500), 17)
	w.drain_events()
	_kill(w)
	w.step(DT, MoveInput.new())
	assert_true(w.transfer_pending)
	assert_eq(w.pickups.active[drop], 1, "same blocked-on-ground rule as the finale")
	assert_eq(w.mesos, 17)
	assert_eq(w.equips_collected, 0)
	_ticks(w, 10)
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "pickup_blocked").size(), 1)
	w.advance_map()
	assert_eq(w.pickups.active_count(), 0, "uncollected full-tab equipment belongs to the previous map")
	assert_eq(w.equipment.inventory.size(), w.inventory_slots())
	assert_eq(w.equips_collected, 0)


func test_transfer_keeps_character_timers_and_pools_clears_statuses_and_rehomes_the_pet() -> void:
	var setup := _setup(0.1)
	var mano := MF.setup([126])
	setup.mob_imgs[100100] = mano.mob_imgs[2220000]
	setup.mob_skill_img = mano.mob_skill_img
	setup.data.balance.mob_skills.enabled_ids = [100100]
	setup.character = RunWorld.new(setup).character_snapshot()
	setup.character.pet = PF.KITTY
	setup.account = {"owned": [PF.KITTY]}
	var w := RunWorld.new(setup)
	w.god = true
	_ticks(w, 16 * 60)
	assert_false(w.mob_skills.slow_state(w.time).is_empty(), "the canonical synthetic boss cast Slow")
	w.spend_hp(7)
	w.learn_skill("dark_sight")
	# SH11 #436: Dark Sight is a Hidden Form now; a running Form keeps its Hidden window across the transfer like any buff.
	w.runner.forms.start(w, "dark_sight", w.runner.stats_of(w, "dark_sight"))
	w.runner.cooldowns.dark_sight = 12.0
	w._teleport_left = 0.6
	w.potions.consume("hp")
	w.projectiles.spawn({"x": 1700, "y": -100, "vx": 1.0, "range": 500.0})
	w.mob_projectiles.spawn({"pos": Vector2(1700, -100), "velocity": Vector2(1, 0), "range": 500.0,
		"visual": 0, "mob": -1, "mob_id": 100100, "damage": 10.0, "multiplier": 1.0,
		"accuracy": 100.0, "magic": false, "element": "", "hit": "", "source_pos": Vector2.ZERO})
	w.spawn_offspring(int(w.bosses.records[0].slot), 0.0, [100100], 0)
	_kill(w)
	w.step(DT, MoveInput.new())
	assert_true(w.transfer_pending)
	var hp: int = w.player_state.hp
	var buffs := w.buffs.snapshot()
	var forms := w.runner.forms.snapshot()
	var potion := w.potions.cooldown_left.duplicate()
	var character := w.character_snapshot()
	var nav := w.nav
	var fhm := w.fhm
	var t := w.time
	_ticks(w, 60)
	w.advance_map()
	assert_eq(w.time, t)
	assert_eq(w.map_entered_at, t)
	assert_eq(w.player_state.hp, hp)
	assert_eq(w.buffs.snapshot(), buffs)
	assert_eq(w.runner.forms.snapshot().size(), forms.size(), "the Dark Sight Form survives the transfer")
	assert_true(w.is_hidden())
	assert_eq(w.skill_readiness("dark_sight").left, 12.0)
	assert_eq(w._teleport_left, 0.6)
	assert_eq(w.potions.cooldown_left, potion)
	assert_eq(w.character_snapshot(), character)
	assert_eq(w.kills, 1)
	assert_eq(w.projectiles.active_count(), 0)
	assert_eq(w.mob_projectiles.active_count(), 0)
	assert_eq(w.pickups.active_count(), 0)
	assert_eq(w.swarm.alive_count(), 0)
	assert_eq(w.mob_skills.slow_state(w.time), {})
	assert_true(w.nav != nav and w.fhm != fhm)
	assert_eq(w.swarm.fhm, w.fhm)
	assert_eq(w.player.pos.y, 200.0)
	assert_true(w.player.pos.x in [-500.0, 500.0])
	assert_true(w.pet_system != null)
	if w.pet_system != null:
		assert_true(w.pet_system.motion.pos.distance_to(w.player.pos) < 100.0)
		w.step(DT, MoveInput.new())
		assert_eq(w.pet_state().species, PF.KITTY)


func test_a_grenade_thrown_before_transfer_never_lands_or_damages_the_next_map() -> void:
	var setup := _setup(0.1)
	# Overlapping map geometry makes the old landing point dangerous to a new map's mob too.
	setup.map_imgs[1] = setup.map_imgs[0].duplicate(true)
	var w := RunWorld.new(setup)
	w.god = true
	_ticks(w, 60)
	w.player.place(Vector2.ZERO, w.fhm)
	var boss := int(w.bosses.records[0].slot)
	w.swarm.x[boss] = 300.0
	w.swarm.y[boss] = 0.0
	for kind: MobKind in w.mob_kinds:
		kind.move_speed = 0.0
	RF.as_job(w, 520)
	assert_true(w.learn_skill("grenade"))
	w.drain_events()
	w.step(DT, MoveInput.new())
	var thrown := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "skill_thrown")
	assert_eq(thrown.size(), 1, "a real cast queues a flight before map 0 clears")
	if thrown.size() != 1:
		return
	var cooldowns := w.skill_readiness("grenade")
	_kill(w)
	w.step(DT, MoveInput.new())
	assert_true(w.transfer_pending)
	w.advance_map()
	assert_eq(w.skill_readiness("grenade"), cooldowns, "transfer keeps the auto-cast timer and HUD total")
	var victim := RF.put_mob(w, 1110100, 300.0, -5.0, 100000.0)
	var hp := w.swarm.hp[victim]
	w.drain_events()
	# Advance beyond this flight's arrival, staying inside the preserved cooldown (no replacement throw).
	_ticks(w, ceili(float(thrown[0].seconds) / DT) + 2)
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "skill_thrown").size(), 0)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "skill_landed").size(), 0,
		"the old map's flight never emits its landing on map 1")
	assert_eq(w.swarm.hp[victim], hp, "the old blast cannot strike a new map's mob at its former coordinates")


func test_later_maps_replay_their_scheduled_bursts_and_elites_after_a_slow_boss() -> void:
	var setup := _setup(0.1)
	var stage: Dictionary = setup.data.stages.stages.quiet
	stage.bursts = {"first": 30.0, "every": 30.0, "count_min": 0, "count_max": 0}
	stage.elites = {"first": 30.0, "every": 30.0}
	var w := RunWorld.new(setup)
	w.god = true
	_ticks(w, 420 * 60)
	_kill(w)
	w.step(DT, MoveInput.new())
	w.advance_map()
	w.drain_events()
	_ticks(w, 30 * 60 + 1)
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "burst").size(), 1,
		"map 2's curve 330 burst is not skipped because map 1's fight reached 420")
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "mob_spawned" and bool(e.elite)))


func test_bot_and_campers_forget_old_map_routes_after_navigation_rebuild() -> void:
	var w := RunWorld.new(_setup(0.1))
	w.god = true
	_ticks(w, 60)
	var memo := {"map_index": 0, "portal_x": -500.0, "climb_x": -500.0, "climb_t": 30}
	_kill(w)
	w.step(DT, MoveInput.new())
	w.advance_map()
	BotInput.decide(w, memo)
	assert_false(memo.has("portal_x"))
	assert_false(memo.has("climb_x"))
	for policy: String in CAMPER.STAGES:
		var camper := {"started_time": 0.0, "reached": true, "bot": {}}
		var expected := BotInput.decide(w, {})
		var actual := CAMPER.decide(w, policy, camper, 0.0)
		assert_eq([actual.left, actual.right, actual.up, actual.jump_pressed],
			[expected.left, expected.right, expected.up, expected.jump_pressed],
			"a camper uses the sensible bot after map 0")


func _replay() -> Dictionary:
	var w := RunWorld.new(_setup(0.1))
	w.god = true
	var events: Array = w.drain_events()
	for index in 3:
		assert_eq(w.map_index, index)
		_ticks(w, 90)
		_kill(w)
		w.step(DT, MoveInput.new())
		BotInput.auto_choose(w)
		events.append_array(w.drain_events())
		if index < 2:
			assert_eq(w.state, RunWorld.PLAYING)
			assert_true(w.transfer_pending)
			assert_false(w.can_clear())
			w.advance_map()
			w.advance_map() # idempotent: a caller cannot skip a map
			events.append_array(w.drain_events())
		else:
			assert_eq(w.state, RunWorld.CLEARED)
			assert_false(w.transfer_pending)
	return {"events": events, "bosses": w.bosses.records, "player": w.player_state,
		"spawn_rng": w.spawn_rng.state, "kills": w.kills, "time": w.time}


func test_only_the_final_map_clears_and_the_same_seed_replays_identical_event_bytes() -> void:
	var first := _replay()
	var second := _replay()
	assert_eq(var_to_bytes(first), var_to_bytes(second))
	assert_eq(first.kills, 3)
	assert_eq(first.events.filter(func(e: Dictionary) -> bool: return e.type == "map_cleared").size(), 2)
	assert_eq(first.events.filter(func(e: Dictionary) -> bool: return e.type == "map_entered").size(), 2)
	assert_eq(first.events.filter(func(e: Dictionary) -> bool: return e.type == "stage_cleared").size(), 1)


func test_legacy_setups_without_maps_or_map_imgs_keep_the_single_map_schedule() -> void:
	for remove: String in ["maps", "map_imgs"]:
		var setup := _setup(0.1)
		if remove == "maps":
			setup.data.stages.stages.quiet.erase("maps")
			setup.data.stages.stages.quiet.bosses = [{"time": 0.1, "mob_id": 100100,
				"rewards": {"exp_mult": 0.0, "bonus_choices": 0}}]
		else:
			setup.erase("map_imgs")
		var w := RunWorld.new(setup)
		w.god = true
		assert_false(w.map_sequence_enabled())
		_ticks(w, 60)
		_kill(w)
		w.step(DT, MoveInput.new())
		BotInput.auto_choose(w)
		assert_false(w.transfer_pending)
		assert_eq(w.map_index, 0)
		assert_eq(w.state, RunWorld.CLEARED if remove == "maps" else RunWorld.PLAYING)


func test_missing_current_boss_retains_the_existing_skip_rule_without_stranding_the_round() -> void:
	var setup := _setup(0.1)
	setup.data.stages.stages.quiet.maps[0].boss.mob_id = 9999999
	var w := RunWorld.new(setup)
	w.god = true
	_ticks(w, 6)
	assert_true(bool(w.bosses.records[0].skipped))
	assert_true(w.transfer_pending, "the existing missing-boss rule also completes an intermediate map")
	w.advance_map()
	assert_eq(w.map_index, 1)


func test_a_later_maps_boss_is_loaded_even_when_no_keyframe_pool_names_it() -> void:
	var setup := _setup(0.1)
	setup.mob_imgs[2220000] = MF.setup().mob_imgs[2220000]
	setup.data.stages.stages.quiet.maps[1].boss.mob_id = 2220000
	for frame: Dictionary in setup.data.stages.stages.quiet.keyframes:
		frame.pool.erase("2220000")
	var w := RunWorld.new(setup)
	w.god = true
	assert_true(w.kind_of_id.has(2220000), "the whole map boss roster is available before the first transfer")
	_ticks(w, 60)
	_kill(w)
	w.step(DT, MoveInput.new())
	w.advance_map()
	_ticks(w, 60)
	assert_false(bool(w.bosses.records[1].skipped))
	assert_eq(w.bosses.live_count(), 1)


func test_transfer_selects_the_next_maps_pool_for_its_first_ordinary_spawn() -> void:
	var setup := _setup(0.1)
	var stage: Dictionary = setup.data.stages.stages.quiet
	stage.keyframes[0].rate = 60.0
	stage.keyframes[0].max_alive = 1
	stage.keyframes[0].pool = {"100100": 1.0}
	stage.maps[1].pool = {"1110100": 1.0}
	var w := RunWorld.new(setup)
	w.god = true
	_ticks(w, 60)
	_kill(w)
	w.step(DT, MoveInput.new())
	w.advance_map()
	w.drain_events()
	w.step(DT, MoveInput.new())
	var spawns := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_spawned")
	assert_eq(spawns.size(), 1)
	if spawns.size() == 1:
		assert_eq(spawns[0].mob_id, 1110100, "the first spawn already uses map 1's preserved pool")
		assert_eq(spawns[0].pos.y, 200.0, "placement uses the rebuilt footholds")


func test_real_cache_transfers_through_each_regions_maps_with_valid_arrivals() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var library := AssetLibrary.new()
	library.open()
	var map_lists := {}
	for key: String in data.stages.stages:
		var stage: Dictionary = data.stages.stages[key]
		map_lists[key] = DataRepo.stage_maps(data, key)
		assert_eq(map_lists[key].size(), 3)
		for entry: Dictionary in map_lists[key]:
			if library.img(DataRepo.map_img_path(int(entry.map_id))) == null:
				library.free()
				skip("cache lacks map %d; new-map transfer is unverified" % int(entry.map_id))
				return
	for key: String in data.stages.stages:
		var missing := PackedStringArray()
		var setup := DataRepo.build_setup(data, key, 244, Vector2(800, 600),
			func(path: String) -> Dictionary:
				var img := library.img(path)
				return img.root if img != null else {},
			func(id: int) -> Dictionary: return library.mob_root(id), missing)
		assert_eq(missing.size(), 0, "complete real-cache setup for " + key)
		var stage: Dictionary = data.stages.stages[key]
		var w := RunWorld.new(setup)
		w.god = true
		for index in 3:
			assert_eq(w.map_index, index)
			assert_eq(w.current_map_id(), int(w.stage.maps[index].map_id))
			assert_true(w.fhm.count() > 0 and w.player.fh >= 0, "arrival has a floor on " + key)
			var arrival := w.director.pick_player_platform(w, 0.0, 250.0, true)
			assert_true(arrival.z >= 0.0, "a boss arrival exists on " + key)
			w.time = w.map_entered_at + 300.0 - DT
			w.step(DT, MoveInput.new())
			_kill(w)
			w.step(DT, MoveInput.new())
			BotInput.auto_choose(w)
			if index < 2:
				assert_true(w.transfer_pending)
				w.advance_map()
		assert_eq(w.state, RunWorld.CLEARED)
		assert_eq(w.warnings.size(), 0)
	library.free()
