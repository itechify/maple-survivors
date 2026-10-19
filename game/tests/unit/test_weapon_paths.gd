extends TestCase
## Chosen-only job weapon grants, inventory overflow, snapshots and forced-path compatibility (#226).
## Synthetic path rows keep these generic tests independent of shipped class grants.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Synthetic Character.wz info nodes; the bow keeps the real DEX 25 requirement that a STR Beginner cannot meet.
const INFO := {
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7},
	1040002: {"incPDD": 3, "tuc": 7},
	1092000: {"incPDD": 5, "tuc": 7},
	1452051: {"reqLevel": 10, "reqDEX": 25, "incPAD": 15, "attackSpeed": 6, "tuc": 7},
	1472061: {"reqLevel": 10, "reqDEX": 25, "reqLUK": 25, "incPAD": 15, "attackSpeed": 4, "tuc": 7},
	1332063: {"reqLevel": 10, "reqDEX": 25, "incPAD": 15, "attackSpeed": 4, "tuc": 7},
	1482000: {"reqLevel": 10, "reqSTR": 40, "incPAD": 15, "attackSpeed": 4, "tuc": 7},
	1492000: {"reqLevel": 10, "reqDEX": 20, "incPAD": 15, "attackSpeed": 5, "tuc": 7},
}


## Real data plus playable Bowman (one path), Thief (claw and dagger) and Pirate rows and two playable Thief branches.
func _data() -> Dictionary:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	var jobs: Dictionary = data.jobs_survivor.jobs
	jobs["300"] = {"playable": true, "paths": [{"id": "bow", "label": "Bowman", "item_id": 1452051, "family": "bow"}]}
	jobs["400"] = {"playable": true, "paths": [
		{"id": "claw", "label": "Thief - Claw", "item_id": 1472061, "family": "claw"},
		{"id": "dagger", "label": "Thief - Dagger", "item_id": 1332063, "family": "dagger"}]}
	jobs["500"] = {"playable": true, "paths": [
		{"id": "knuckle", "label": "Pirate - Knuckle", "item_id": 1482000, "family": "knuckle"},
		{"id": "gun", "label": "Pirate - Gun", "item_id": 1492000, "family": "gun"}]}
	jobs["410"] = {"playable": true, "paths": [{"id": "claw", "family": "claw", "item_id": 1472061}]}
	jobs["420"] = {"playable": true, "paths": [{"id": "dagger", "family": "dagger", "item_id": 1332063}]}
	jobs["310"] = {} # Synthetic no-grant row, independent of shipping Hunter (#202).
	return data


func _world(p_seed := 7, change: Callable = Callable()) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, _data())
	setup.equipment_info = INFO.duplicate(true)
	if change.is_valid():
		var character := RunWorld.new(setup).character_snapshot()
		change.call(character)
		setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


## Levels the Beginner to `level` and opens the advancement window.
func _open_window(w: RunWorld, level: int) -> void:
	w.progression.level = level - 1
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "the advancement window is open")


func _inventory_ids(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))


func _events(w: RunWorld, type: String) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == type)


# --- the window lists every path ---------------------------------------------------------------------------------

func test_the_window_lists_one_thief_entry_carrying_its_paths() -> void:
	var w := _world()
	_open_window(w, 10)
	var thief: Array = w.pending_jobs.filter(func(o: Dictionary) -> bool: return int(o.job_id) == 400)
	assert_eq(thief.size(), 1)
	assert_eq(thief[0].paths.map(func(p: Dictionary) -> String: return p.id), ["claw", "dagger"])
	assert_eq(thief.map(func(o: Dictionary) -> String: return o.name), ["Thief"])
	assert_true(thief.all(func(o: Dictionary) -> bool: return o.available))
	var magician: Array = w.pending_jobs.filter(func(o: Dictionary) -> bool: return int(o.job_id) == 200)
	assert_eq(magician.size(), 1)
	assert_false(magician[0].has("path"), "a job without paths has the old entry shape")


func test_shipping_data_offers_bowman_and_both_thief_and_pirate_paths() -> void:
	var jobs := JobTree.from_data(DataRepo.load_all().jobs, DataRepo.load_all().jobs_survivor)
	for id in [300, 400]:
		assert_true(bool(jobs.job(id).playable), "%d is playable since specs #166/#167" % id)
	assert_eq(jobs.paths_of(300).map(func(p: Dictionary) -> int: return p.item_id), [1452051, 1462001])
	assert_eq(jobs.paths_of(400).map(func(p: Dictionary) -> int: return p.item_id), [1472061, 1332063])
	assert_eq(jobs.paths_of(500).map(func(p: Dictionary) -> int: return p.item_id), [1482000, 1492000])
	assert_eq(jobs.paths_of(400).map(func(p: Dictionary) -> String: return p.family), ["claw", "dagger"])
	var window := jobs.advancements(0, 10)
	assert_eq(window.map(func(o: Dictionary) -> int: return o.job_id), [100, 200, 300, 400, 500])
	assert_true(window.all(func(o: Dictionary) -> bool: return not o.has("path")))
	assert_eq(jobs.paths_of(100).map(func(p: Dictionary) -> String: return p.id), ["sword", "spear", "blunt"])
	assert_eq(jobs.paths_of(200), [], "the Magician grant is balance.player.weapon_grants")
	var families := {110: ["sword", "axe"], 120: ["sword", "blunt"], 130: ["spear", "polearm"], 310: ["bow"],
		320: ["crossbow"], 410: ["claw"], 420: ["dagger"], 510: ["knuckle"], 520: ["gun"]}
	var shipped: Dictionary = DataRepo.load_all().jobs_survivor.jobs
	for id: int in families:
		assert_eq(jobs.weapon_families(id), families[id], "branch %d" % id)


func test_choosing_a_path_grants_and_wears_its_weapon_and_records_it() -> void:
	var w := _world()
	_open_window(w, 10)
	assert_false(w.apply_job(400, "gun"), "a path the window does not list")
	assert_true(w.apply_job(400, "dagger"))
	assert_eq(w.progression.job_id, 400)
	assert_eq(w.weapon_id(), 1332063)
	assert_eq(w.held_weapon_family(), "dagger")
	assert_eq(w.weapon_path, "dagger")
	assert_eq(_inventory_ids(w), [1302000], "the creation sword moves to the inventory")


func test_a_path_grant_ignores_requirements_for_a_strength_beginner() -> void:
	var w := _world()
	_open_window(w, 10)
	var who := {"level": 10, "job_id": 0, "str": w.player_state.str, "dex": w.player_state.dex,
		"int": w.player_state.int, "luk": w.player_state.luk}
	assert_true(int(who.dex) < 25 and int(who.str) > int(who.dex), "the Beginner's AP is in STR")
	assert_eq(Equipment.requirement_error(INFO[1452051], who), "reqDEX", "worn normally, the bow would be refused")
	assert_true(w.apply_job(300, "bow"))
	assert_eq(w.weapon_id(), 1452051, "a grant is not a requirement check")
	assert_eq(w.weapon_path, "", "a synthetic single-path job does not record a choice")


func test_a_job_without_paths_records_none_and_the_magician_is_unchanged() -> void:
	var w := _world()
	_open_window(w, 10)
	assert_true(w.apply_job(200))
	assert_eq(w.weapon_id(), 1372005, "balance.player.weapon_grants still gives the Wooden Wand")
	assert_eq(w.weapon_path, "")
	RF.auto_choose(w)
	assert_false(w.character_snapshot().has("weapon_path"), "the key is written only when set")


# --- the old weapon -------------------------------------------------------------------------------------------------

func test_a_full_inventory_drops_the_old_weapon_at_the_players_feet() -> void:
	var w := _world(7, func(c: Dictionary) -> void:
		for i in 24:
			c.equipment.inventory.append(Equipment.create(1040002, INFO[1040002])))
	_open_window(w, 10)
	w.drain_events()
	assert_true(w.apply_job(400, "claw"))
	assert_eq(w.weapon_id(), 1472061, "advancing never fails")
	assert_eq(w.equipment.inventory.size(), 24, "the inventory is unchanged")
	var spawned := _events(w, "pickup_spawned")
	assert_eq(spawned.size(), 1)
	assert_eq(int(spawned[0].item_id), 1302000, "the old weapon lies on the ground")
	assert_eq(spawned[0].kind, "equip")
	assert_eq(spawned[0].pos, w.player.pos, "at the player's feet")
	RF.auto_choose(w) # the advancement skill draw
	w.drain_events()
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(w.equipment.inventory.size(), 24, "it is a normal pickup: it waits for a free slot")
	var blocked := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_blocked")
	assert_true(blocked.size() > 0, "and says so while the tab is full")
	w.discard_item(0)
	for tick in 60:
		w.step(DT, MoveInput.new())
	assert_true(1302000 in _inventory_ids(w), "freeing a slot lets the magnet collect the old weapon")


func test_a_full_inventory_drops_the_shield_too_when_a_two_handed_grant_displaces_it() -> void:
	var w := _world(7, func(c: Dictionary) -> void:
		c.equipment.worn["shield"] = Equipment.create(1092000, INFO[1092000])
		for i in 24:
			c.equipment.inventory.append(Equipment.create(1040002, INFO[1040002])))
	_open_window(w, 10)
	w.drain_events()
	assert_true(w.apply_job(400, "claw"))
	assert_eq(w.weapon_id(), 1472061, "the two-handed grant is worn")
	assert_false(w.equipment.worn.has("shield"), "the shield it displaces is off")
	assert_eq(w.equipment.inventory.size(), 24, "the inventory is unchanged")
	var dropped: Array = _events(w, "pickup_spawned").map(func(e: Dictionary) -> int: return int(e.item_id))
	dropped.sort()
	assert_eq(dropped, [1092000, 1302000], "the old weapon and the shield both lie at the player's feet")


func test_a_two_handed_grant_sends_both_displaced_items_to_the_inventory_when_there_is_room() -> void:
	var w := _world(7, func(c: Dictionary) -> void:
		c.equipment.worn["shield"] = Equipment.create(1092000, INFO[1092000]))
	_open_window(w, 10)
	w.drain_events()
	assert_true(w.apply_job(400, "claw"))
	assert_eq(_inventory_ids(w), [1302000, 1092000], "weapon then shield")
	assert_eq(_events(w, "pickup_spawned").size(), 0)


func test_one_free_slot_keeps_one_displaced_item_and_drops_the_other() -> void:
	var w := _world(7, func(c: Dictionary) -> void:
		c.equipment.worn["shield"] = Equipment.create(1092000, INFO[1092000])
		for i in 23:
			c.equipment.inventory.append(Equipment.create(1040002, INFO[1040002])))
	_open_window(w, 10)
	w.drain_events()
	assert_true(w.apply_job(400, "claw"))
	assert_eq(w.equipment.inventory.size(), 24, "the one free slot is used")
	assert_eq(_events(w, "pickup_spawned").size(), 1, "the other lies on the ground")


# --- second-job branch grants ----------------------------------------------------------------------------------------

func test_a_branch_hands_its_advancement_weapon_of_the_held_family_or_its_first_family() -> void:
	var w := _world()
	_open_window(w, 10)
	assert_true(w.apply_job(400, "claw"))
	assert_eq(w.weapon_id(), 1472061)
	var held := _inventory_ids(w)
	w.change_job(410)
	assert_eq(w.weapon_id(), 1472061, "spec #165: every advancement hands its weapon, the Assassin's claw too")
	assert_eq(_inventory_ids(w), held + [1472061], "the claw it held moves to the inventory")
	w.change_job(420)
	assert_eq(w.weapon_id(), 1332063, "a claw does not fit the Bandit: its first (only) family's dagger is worn")
	assert_eq(_inventory_ids(w), held + [1472061, 1472061], "and the claw moves to the inventory")
	assert_eq(w.weapon_path, "claw", "the path stays what the first job recorded")


func test_a_bare_handed_character_gets_the_branch_weapon_and_a_branch_without_data_grants_nothing() -> void:
	var w := _world()
	w.unequip_item("weapon")
	assert_eq(w.held_weapon_family(), "")
	w.change_job(420)
	assert_eq(w.weapon_id(), 1332063)
	var plain := _world()
	plain.change_job(210)
	assert_eq(plain.weapon_id(), 1302000, "no weapon_families on the row: no grant")
	var unfinished := _world()
	unfinished.change_job(310) # synthetic families-only row
	assert_eq(unfinished.weapon_id(), 1302000, "a branch with families but no grant items grants nothing")


func test_a_playable_jobs_grant_items_load_their_info_and_an_unplayable_jobs_do_not() -> void:
	var shipped := DataRepo.starter_equipment_ids(DataRepo.load_all())
	for id in [1452051, 1462001, 1472061, 1332063, 1482000, 1492000]:
		assert_true(id in shipped, "Bowman/Thief/Pirate grants load since their class specs")
	var playable := DataRepo.starter_equipment_ids(_data())
	for id in [1452051, 1472061, 1332063, 1482000, 1492000]:
		assert_true(id in playable, str(id))
	assert_true(1372005 in playable and 1302000 in playable)


# --- the snapshot ----------------------------------------------------------------------------------------------------

func test_the_path_round_trips_through_the_snapshot() -> void:
	var w := _world()
	_open_window(w, 10)
	w.apply_job(400, "claw")
	RF.auto_choose(w)
	var snapshot := w.character_snapshot()
	assert_eq(snapshot.weapon_path, "claw")
	assert_eq(CharacterSnapshot.validation_error(snapshot), "")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(snapshot))
	var setup := RF.setup("quiet", 9, _data())
	setup.equipment_info = INFO.duplicate(true)
	setup.character = parsed
	var restored := RunWorld.new(setup)
	assert_eq(restored.weapon_path, "claw")
	assert_eq(restored.character_snapshot(), snapshot)
	snapshot.weapon_path = 5
	assert_eq(CharacterSnapshot.validation_error(snapshot), "invalid weapon_path")
	snapshot.erase("weapon_path")
	assert_eq(CharacterSnapshot.validation_error(snapshot), "", "old snapshots have no path")


# --- the bot and --job=<id>:<path> -----------------------------------------------------------------------------------

func test_parse_forced_splits_the_job_and_its_path() -> void:
	assert_eq(JobTree.parse_forced("400:claw"), {"job": 400, "path": "claw"})
	assert_eq(JobTree.parse_forced("210"), {"job": 210, "path": ""})
	assert_eq(JobTree.parse_forced("410:dagger"), {"job": 410, "path": "dagger"})
	var r := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys_hg1", "--job=400:claw"]))
	assert_eq(r.options.job, 400)
	assert_eq(r.options.job_path, "claw")
	var plain := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys_hg1", "--job=220"]))
	assert_eq(plain.options.job, 220)
	assert_false(plain.options.has("job_path"))
	var alias := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys_hg1", "--branch=230"]))
	assert_eq(alias.options.job, 230)
	assert_eq(RunLauncher.options_from_args({"job": "400:claw"}).job_path, "claw")
	assert_eq(RunLauncher.options_from_args({"job": "400:claw"}).job, 400)


func test_forcing_a_path_needs_a_playable_line_that_has_it() -> void:
	var data := _data()
	assert_eq(SceneFlow.forced_job_error({"job": 400, "job_path": "claw"}, data), "")
	assert_eq(SceneFlow.forced_job_error({"job": 410, "job_path": "claw"}, data), "", "a branch names its first job's path")
	assert_true("no weapon path" in SceneFlow.forced_job_error({"job": 400, "job_path": "gun"}, data))
	assert_true("no weapon path" in SceneFlow.forced_job_error({"job": 200, "job_path": "claw"}, data))
	data.jobs_survivor.jobs["400"].playable = false
	assert_true("not playable" in SceneFlow.forced_job_error({"job": 400, "job_path": "claw"}, data))


func test_pick_choice_takes_an_offered_forced_path_else_defaults() -> void:
	var jobs := JobTree.from_data(_data().jobs, _data().jobs_survivor)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var options := jobs.advancements(0, 10)
	var pick := BotInput.pick_choice(options, rng, 400, jobs, "dagger")
	assert_eq(pick, {"job_id": 400, "path": "dagger"})
	assert_eq(RF.pick_job(options, rng, 400, jobs, "claw"), 400)
	assert_eq(BotInput.pick_choice(options, rng, 410, jobs, "claw"), {"job_id": 400, "path": "claw"},
		"a forced branch takes its first job with the named path")
	assert_eq(BotInput.pick_choice(options, rng, 420, jobs, ""), {"job_id": 400, "path": ""},
		"compatibility default until #232 adds path draws")
	var unnamed := BotInput.pick_choice(options, rng, 400, jobs, "")
	assert_eq(unnamed.job_id, 400)
	assert_eq(unnamed.path, "", "no path named: use the page default until #232")
	var unforced := BotInput.pick_choice(options, rng, 0, jobs, "")
	assert_true(unforced.job_id in [100, 200, 300, 400, 500])
	assert_eq(BotInput.pick_choice([{"job_id": 400, "path": "claw", "available": false}], rng, 400, jobs, "claw"),
		{"job_id": -1, "path": ""})


func test_pick_choice_default_is_deterministic() -> void:
	var jobs := JobTree.from_data(_data().jobs, _data().jobs_survivor)
	var options := jobs.advancements(0, 10).filter(func(o: Dictionary) -> bool: return int(o.job_id) == 400)
	var seen := {}
	for s in 12:
		var a := RandomNumberGenerator.new()
		a.seed = s
		var b := RandomNumberGenerator.new()
		b.seed = s
		var first := BotInput.pick_choice(options, a, 400, jobs, "")
		assert_eq(BotInput.pick_choice(options, b, 400, jobs, ""), first, "the same stream state, the same path")
		seen[first.path] = true
	assert_eq(seen.keys(), [""], "compatibility callers use default paths; #232 adds path draws")


func test_auto_choose_forces_the_path_in_a_run() -> void:
	var w := _world(11)
	_open_window(w, 10)
	BotInput.auto_choose(w, false, 400, "claw")
	assert_eq(w.progression.job_id, 400)
	assert_eq(w.weapon_path, "claw")
	assert_eq(w.weapon_id(), 1472061)
	var d := _world(12)
	_open_window(d, 10)
	BotInput.auto_choose(d, false, 400, "dagger")
	assert_eq(d.weapon_id(), 1332063)
