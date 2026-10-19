extends TestCase
## Spec #226: job entries, chosen-only grants, path migration and AP re-splitting through public sim interfaces.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
# Spec #226 owner table; test expectations are independent of jobs.json.
const GRANTS := {
	100: {"sword": 1302077, "spear": 1432000, "blunt": 1322006},
	300: {"bow": 1452051, "crossbow": 1462001},
	400: {"claw": 1472061, "dagger": 1332063},
	500: {"knuckle": 1482000, "gun": 1492000},
	110: {"sword": 1302008, "axe": 1312005},
	120: {"sword": 1302008, "blunt": 1322014},
	130: {"spear": 1432002, "polearm": 1442001},
	310: {"bow": 1452005}, 320: {"crossbow": 1462000},
	410: {"claw": 1472008}, 420: {"dagger": 1332012},
	510: {"knuckle": 1482004}, 520: {"gun": 1492004},
}


func _world(parent: int, full := false, held := 1302000) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	var setup := RF.setup("quiet", 226, data)
	var character := RunWorld.new(setup).character_snapshot()
	character.job_id = parent
	character.equipment.worn.weapon = Equipment.create(held, {})
	if parent != 0:
		character.weapon_path = "original"
	if full:
		for i in 24:
			character.equipment.inventory.append(Equipment.create(1040002, {}))
	setup.character = character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.progression.level = 9 if parent == 0 else 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB)
	w.drain_events()
	return w


func test_every_path_wears_only_its_grant_and_stores_or_spills_the_displaced_weapon() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in GRANTS:
		var parent := int(jobs.job(job).parent)
		for path: String in GRANTS[job]:
			for full: bool in [false, true]:
				var w := _world(parent, full)
				assert_true(w.apply_job(job, path), "%d:%s offered" % [job, path])
				assert_eq(w.weapon_id(), GRANTS[job][path])
				assert_eq(w.weapon_path, path if GRANTS[job].size() >= 2 else "original")
				var spilled := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "pickup_spawned")
				if full:
					assert_eq(w.equipment.inventory.size(), 24)
					assert_eq(spilled.map(func(e: Dictionary) -> int: return int(e.item_id)), [1302000])
					if not spilled.is_empty():
						assert_eq(spilled[0].pos, w.player.pos)
				else:
					assert_eq(w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id)), [1302000])
					assert_eq(spilled, [])


func test_apply_job_rejects_unknown_paths_and_defaults_to_first_page_path() -> void:
	var w := _world(100, false, 1312004)
	var before := w.equipment.duplicate(true)
	assert_false(w.apply_job(110, "blunt"))
	assert_false(w.apply_job(200))
	assert_eq(w.equipment, before)
	assert_eq(w.progression.job_id, 100)
	assert_eq(w.state, RunWorld.CHOOSING_JOB)
	assert_true(w.apply_job(110))
	assert_eq(w.weapon_id(), 1312005, "held axe goes first on Fighter page")
	assert_eq(w.weapon_path, "axe")
	var first := _world(0, false, 1322000)
	assert_true(first.apply_job(100))
	assert_eq(first.weapon_id(), 1302077, "creation club does not reorder first-job page")
	assert_eq(first.weapon_path, "sword")


func test_advancements_list_each_job_once_with_page_ordered_paths() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	var first := jobs.advancements(0, 10)
	assert_eq(first.map(func(o: Dictionary) -> int: return o.job_id), [100, 200, 300, 400, 500])
	assert_eq(first.map(func(o: Dictionary) -> String: return o.name), ["Warrior", "Magician", "Bowman", "Thief", "Pirate"])
	assert_true(first.all(func(o: Dictionary) -> bool: return not o.has("path") and o.has("paths")))
	assert_eq(first[0].get("paths", []).map(func(p: Dictionary) -> String: return p.id), ["sword", "spear", "blunt"])
	assert_eq(first[1].get("paths", []), [])


func test_page_order_uses_held_family_only_at_second_job() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	for row: Array in [[100, "blunt", ["sword", "spear", "blunt"]], [300, "crossbow", ["bow", "crossbow"]],
		[110, "axe", ["axe", "sword"]], [120, "blunt", ["blunt", "sword"]],
		[130, "polearm", ["polearm", "spear"]], [110, "spear", ["sword", "axe"]], [200, "wand", []]]:
		assert_eq(jobs.page_paths(row[0], row[1]).map(func(p: Dictionary) -> String: return p.id), row[2])
	assert_eq(jobs.advancements(100, 30, "blunt")[1].paths[0].id, "blunt")
	assert_eq(jobs.paths_of(120)[0].id, "sword", "page order never mutates data order")
	data.jobs_survivor.jobs["100"].playable = false
	var locked: Dictionary = JobTree.from_data(data.jobs, data.jobs_survivor).advancements(0, 10)[0]
	assert_false(locked.available)
	assert_eq(locked.paths, [])


func test_forced_paths_validate_the_jobs_own_multi_path_row_else_its_first_job() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in GRANTS:
		for path: String in GRANTS[job]:
			var spec := "%d:%s" % [job, path]
			assert_eq(JobTree.parse_forced(spec), {"job": job, "path": path})
			assert_eq(jobs.forced_job_error(job, path), "", spec)
		assert_true("no weapon path" in jobs.forced_job_error(job, "unknown"))
	assert_true("no weapon path" in jobs.forced_job_error(110, "spear"), "Fighter cannot force an ancestor-only family")
	assert_true("no weapon path" in jobs.forced_job_error(130, "sword"))
	assert_eq(jobs.forced_job_error(410, "dagger"), "", "single-family branches retain first-job path flags")
	assert_eq(jobs.forced_job_error(320, "bow"), "")
	data.jobs_survivor.jobs["999"] = {"playable": true,
		"paths": [{"id": "axe", "family": "axe", "label": "Axe", "item_id": 1312999}]}
	assert_true(1312999 in DataRepo.starter_equipment_ids(data), "preload follows paths even for new branches")


func test_pathless_snapshots_use_the_deepest_multi_path_job_and_keep_inventory() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	var source := RF.quiet_world().character_snapshot()
	for row: Array in [[100, 1432000, "spear"], [100, 1322006, "blunt"], [300, 1462001, "crossbow"],
		[110, 1312005, "axe"], [120, 1322014, "blunt"], [130, 1442001, "polearm"],
		[110, 1432000, "sword"], [130, 0, "spear"], [320, 1462000, "crossbow"]]:
		var old := source.duplicate(true)
		old.job_id = row[0]
		old.equipment.worn.weapon = Equipment.create(row[1], {})
		old.equipment.inventory = [Equipment.create(1432000, {}), Equipment.create(1322006, {})]
		var expected := old.duplicate(true)
		expected.weapon_path = row[2]
		assert_eq(CharacterSnapshot.migrate(old, jobs, {}), expected)
		assert_false(old.has("weapon_path"), "migration detaches its result")
		old.weapon_path = "kept"
		assert_eq(CharacterSnapshot.migrate(old, jobs, {}), old, "explicit paths are kept")
	# Committed old branch fixtures exercise the same load path, without re-generating their characters.
	for file: String in ["lv34_fighter_2nd", "lv34_page_2nd", "lv34_spearman_2nd", "hunter_2nd", "crossbowman_2nd"]:
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/characters/" + file + ".json"))
		old.erase("weapon_path")
		var migrated := CharacterSnapshot.migrate(old, jobs, {})
		assert_eq(migrated.weapon_path, "spear" if file == "lv34_spearman_2nd" else "blunt" if file == "lv34_page_2nd" else "crossbow" if file == "crossbowman_2nd" else "bow" if file == "hunter_2nd" else "sword", file)
		assert_eq(migrated.equipment, old.equipment, "old spare weapons are retained")
		assert_eq(migrated, CharacterSnapshot.migrate(migrated, jobs, {}), "migration is idempotent")
		var setup := RF.setup("quiet", 226)
		setup.character = old
		assert_eq(RunWorld.new(setup).weapon_path, migrated.weapon_path, "RunWorld load migrates too")
	var legacy := source.duplicate(true)
	legacy.format = 1
	legacy.job_id = 100
	legacy.beginner_weapon = 1302000
	legacy.erase("equipment")
	assert_eq(CharacterSnapshot.migrate(legacy, jobs, {}).weapon_path, "sword", "format 1 receives a path after equipment migration")


func _earn_to_window(w: RunWorld, level: int) -> void:
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(level) - w.progression.curve.total_to(w.progression.level)
		- w.progression.exp, 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.state == RunWorld.CHOOSING_JOB:
			break
		if w.state == RunWorld.CHOOSING_UPGRADE:
			w.apply_choice(String(w.pending_cards[0].id))
	assert_eq(w.progression.level, level)
	assert_eq(w.state, RunWorld.CHOOSING_JOB)


func test_all_earned_ap_is_resplit_at_first_and_second_advancements() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	var w := RunWorld.new(RF.setup("quiet", 226, data))
	RF.place_player(w, 400)
	_earn_to_window(w, 10)
	assert_eq(w.player_state.str, 57, "Lv10 Beginner: all 45 earned AP in STR")
	assert_eq(w.player_state.dex, 5)
	assert_true(w.apply_job(500, "gun"))
	assert_eq(w.player_state.str, 12, "creation STR is unchanged; earned AP moves out")
	assert_eq(w.player_state.dex, 50, "all 45 AP is now in the gun path primary stat")
	BotInput.auto_choose(w)
	_earn_to_window(w, 30)
	assert_eq(w.player_state.str, 30)
	assert_eq(w.player_state.dex, 132)
	assert_true(w.apply_job(510))
	assert_eq(w.weapon_path, "gun", "single-family Brawler preserves the first-job path")
	assert_eq(w.player_state.str, 132, "Brawler plain row wins over ancestor gun path")
	assert_eq(w.player_state.dex, 30, "all 145 AP is re-split at second advancement")
	assert_eq(w.player_state.int, 4)
	assert_eq(w.player_state.luk, 4)


func test_recorded_warrior_and_bowman_paths_fall_back_to_plain_ap_rows() -> void:
	for row: Array in [[100, "spear", 57, 5], [300, "crossbow", 15, 47]]:
		var data := RF.quiet_data()
		data.upgrades.cards = []
		var w := RunWorld.new(RF.setup("quiet", 226, data))
		RF.place_player(w, 400)
		_earn_to_window(w, 10)
		assert_true(w.apply_job(row[0], row[1]))
		assert_eq(w.weapon_path, row[1])
		assert_eq(w.player_state.str, row[2])
		assert_eq(w.player_state.dex, row[3])
		BotInput.auto_choose(w)
		if row[0] == 100:
			_earn_to_window(w, 30)
			assert_true(w.apply_job(110, "axe"))
			assert_eq(w.weapon_path, "axe")
			assert_eq(w.player_state.str, 157, "110:axe and 110 absent: use plain ancestor 100")
			assert_eq(w.player_state.dex, 5)
