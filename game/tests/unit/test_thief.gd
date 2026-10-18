extends TestCase
## Thief first-job tracer (#207): shipping data through public RunWorld advancement, combat, cards and snapshots.
## Seeded synthetic worlds use fixed ticks; real-cache checks verify the original v83 facts separately.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const WEAPONS := {"claw": 1472061, "dagger": 1332063}
const INFO := {
	1472061: {"incPAD": 11, "attackSpeed": 5, "tuc": 7},
	1332063: {"incPAD": 28, "attackSpeed": 5, "tuc": 7},
}


func _world(free := 24) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var setup := RF.with_basic_attack(RF.setup("quiet", 207, data))
	setup.equipment_info.merge(INFO, true)
	if free < 24:
		var character := RunWorld.new(setup).character_snapshot()
		for i in 24 - free:
			character.equipment.inventory.append(Equipment.create(1040002, {"incPDD": 3, "tuc": 7}))
		setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


func _level(w: RunWorld, target: int, path := "claw", forced := 400) -> void:
	var needed := w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level) - w.progression.exp
	w.pickups.spawn(w.player.pos, needed, 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.state != RunWorld.PLAYING:
			BotInput.auto_choose(w, false, forced, path)
		if w.progression.level == target:
			break
	assert_eq(w.progression.level, target)


func _open(w: RunWorld) -> void:
	w.progression.level = 9
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB)


func _inventory(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func test_both_paths_are_offered_at_ten_and_grant_both_weapons() -> void:
	for path: String in WEAPONS:
		var w := _world()
		_open(w)
		var options := w.pending_jobs.filter(func(o: Dictionary) -> bool: return int(o.job_id) == 400)
		assert_eq(options.map(func(o: Dictionary) -> String: return o.get("path", "")), ["claw", "dagger"])
		assert_eq(options.map(func(o: Dictionary) -> String: return o.name), ["Thief - Claw", "Thief - Dagger"])
		assert_true(options.all(func(o: Dictionary) -> bool: return o.available))
		assert_true(w.jobs.advancements(0, 9).filter(func(o: Dictionary) -> bool: return int(o.job_id) == 400).all(
			func(o: Dictionary) -> bool: return not o.available and o.reason == "Lv. 10"))
		var hp: int = w.player_state.max_hp
		var mp: int = w.player_state.max_mp
		assert_true(w.apply_job(400, path))
		assert_eq(w.weapon_id(), WEAPONS[path])
		assert_eq(w.weapon_path, path)
		assert_eq(w.player_state.max_hp, hp + 125)
		assert_eq(w.player_state.max_mp, mp + 37)
		assert_eq(_inventory(w), [1302000, WEAPONS["dagger" if path == "claw" else "claw"]])


func test_full_equip_tab_spills_old_and_extra_weapons_at_the_feet() -> void:
	for path: String in WEAPONS:
		var w := _world(0)
		_open(w)
		w.drain_events()
		assert_true(w.apply_job(400, path))
		assert_eq(w.weapon_id(), WEAPONS[path])
		assert_eq(w.equipment.inventory.size(), 24)
		var drops := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
		assert_eq(drops.size(), 2)
		assert_true(drops.all(func(e: Dictionary) -> bool: return e.pos == w.player.pos and e.kind == "equip"))
		assert_eq(drops.map(func(e: Dictionary) -> int: return int(e.item_id)),
			[1302000, WEAPONS["dagger" if path == "claw" else "claw"]])


func test_snapshot_keeps_the_chosen_path_and_both_weapons() -> void:
	for path: String in WEAPONS:
		var w := _world()
		_open(w)
		w.apply_job(400, path)
		BotInput.auto_choose(w, false, 400, path)
		var snapshot := w.character_snapshot()
		assert_eq(CharacterSnapshot.validation_error(snapshot), "")
		var setup := w.setup.duplicate(true)
		setup.character = JSON.parse_string(JSON.stringify(snapshot))
		var restored := RunWorld.new(setup)
		assert_eq(restored.character_snapshot(), snapshot)
		assert_eq(restored.weapon_path, path)
		assert_eq(restored.weapon_id(), WEAPONS[path])
		assert_has(_inventory(restored), WEAPONS["dagger" if path == "claw" else "claw"])



func test_seeded_bot_has_luk_eighty_and_dex_twenty_five_by_thirty_on_both_paths() -> void:
	for path: String in WEAPONS:
		var w := _world()
		w.god = true
		for level in range(2, 31):
			_level(w, level, path)
		assert_eq(w.progression.job_id, 400)
		assert_eq(w.weapon_path, path)
		assert_true(int(w.player_state.luk) >= 80, "LUK first, no stat reset")
		assert_true(int(w.player_state.dex) >= 25, "v83 first-job DEX minimum")
		var hp: int = w.player_state.max_hp
		var mp: int = w.player_state.max_mp
		_level(w, 31, path)
		assert_eq(w.player_state.max_hp - hp, 22)
		assert_eq(w.player_state.max_mp - mp, 15)
		var weights := BotShop.weights_for(w.balance, 400, w.jobs)
		assert_true(float(weights.get("incLUK", 0)) > float(weights.get("incDEX", 0)), "LUK equipment first")

func test_thief_rng_is_stream_fifteen_and_does_not_shift_existing_streams() -> void:
	var a := _world()
	var b := _world()
	var properties := a.get_property_list().map(func(p: Dictionary) -> String: return p.name)
	assert_has(properties, "thief_rng")
	if not "thief_rng" in properties:
		return
	var thief: RandomNumberGenerator = a.get("thief_rng")
	var expected := RandomNumberGenerator.new()
	expected.seed = 207 * 1000003 + 15 * 7919
	assert_eq(thief.randi(), expected.randi(), "registered id 15")
	for i in 100:
		thief.randi()
	for property: String in ["rng", "spawn_rng", "card_rng", "drop_rng", "basic_rng", "reward_rng", "potion_rng",
			"job_rng", "meso_rng", "equip_rng", "scroll_rng", "final_rng", "pirate_rng"]:
		var left: RandomNumberGenerator = a.get(property)
		var right: RandomNumberGenerator = b.get(property)
		assert_eq(left.state, right.state, property + " retains its state")
		assert_eq(left.randi(), right.randi(), property + " retains its next draw")


