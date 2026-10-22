extends TestCase
## Spec #226 bot choices: every multi-family advancement draws on the world's job stream, unless its path is forced.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const HARNESS := preload("res://tools/balance_run.gd")


func test_each_multi_family_advancement_draws_an_offered_path_on_job_stream_8() -> void:
	var w := RF.quiet_world(400, 1)
	for row: Array in [[0, 10, 100], [0, 10, 300], [0, 10, 400], [0, 10, 500],
		[100, 30, 110], [100, 30, 120], [100, 30, 130]]:
		var options := w.jobs.advancements(row[0], row[1])
		var seen := {}
		for draw in 60:
			var pick := BotInput.pick_choice(options, w.job_rng, row[2], w.jobs)
			assert_eq(pick.job_id, row[2])
			assert_true(w.jobs.paths_of(row[2]).any(func(p: Dictionary) -> bool: return p.id == pick.path),
				"a multi-family choice returns an explicit offered path")
			seen[pick.path] = true
		assert_eq(seen.size(), w.jobs.paths_of(row[2]).size(), "all offered families are reachable")
	var replay := RF.quiet_world(400, 1)
	for draw in 420:
		replay.job_rng.randi_range(0, 2 if draw < 60 else 1)
	assert_eq(w.job_rng.state, replay.job_rng.state, "one uniform path draw per advancement; no forced-job draw")


func test_forced_path_is_used_only_when_the_current_advancement_offers_it() -> void:
	var w := RF.quiet_world(400, 1)
	var first := w.jobs.advancements(0, 10)
	var before := w.job_rng.state
	assert_eq(BotInput.pick_choice(first, w.job_rng, 100, w.jobs, "spear"), {"job_id": 100, "path": "spear"})
	assert_eq(w.job_rng.state, before, "an offered forced path consumes no RNG")
	var pick := BotInput.pick_choice(first, w.job_rng, 110, w.jobs, "axe")
	assert_eq(pick.job_id, 100, "the forced Fighter first takes Warrior")
	assert_true(pick.path in ["sword", "spear", "blunt"], "axe is not offered at Lv10: draw a Warrior path")
	assert_true(w.job_rng.state != before)
	before = w.job_rng.state
	assert_eq(BotInput.pick_choice(w.jobs.advancements(100, 30), w.job_rng, 110, w.jobs, "axe"),
		{"job_id": 110, "path": "axe"})
	assert_eq(w.job_rng.state, before, "Lv30 offers the forced family")
	assert_eq(BotInput.pick_choice(w.jobs.advancements(300, 30), w.job_rng, 320, w.jobs, "bow"),
		{"job_id": 320, "path": ""}, "a single-family branch uses its own default grant")
	assert_eq(w.job_rng.state, before, "zero/one-path choices consume no path RNG")


func test_a_forced_single_family_branch_without_a_path_takes_its_own_family_at_the_first_advancement() -> void:
	var w := RF.quiet_world(400, 1)
	var before := w.job_rng.state
	for row: Array in [[300, 310, "bow"], [300, 320, "crossbow"], [400, 410, "claw"], [400, 420, "dagger"],
		[500, 510, "knuckle"], [500, 520, "gun"]]:
		var first: int = row[0]
		var options := w.jobs.advancements(0, 10)
		for draw in 20:
			assert_eq(BotInput.pick_choice(options, w.job_rng, row[1], w.jobs), {"job_id": first, "path": row[2]})
	assert_eq(w.job_rng.state, before, "no draw: the branch decides the family")
	var drawn := {}
	for draw in 40:
		drawn[BotInput.pick_choice(w.jobs.advancements(0, 10), w.job_rng, 110, w.jobs).path] = true
	assert_eq(drawn.size(), 3, "a forced multi-family branch (Fighter) still draws its Warrior family at Lv10")


func test_pathless_and_rngless_callers_keep_the_default_and_ignore_locked_jobs() -> void:
	var w := RF.quiet_world()
	assert_eq(BotInput.pick_choice(w.jobs.advancements(0, 10), null, 100, w.jobs), {"job_id": 100, "path": ""})
	var before := w.job_rng.state
	assert_eq(BotInput.pick_choice(w.jobs.advancements(0, 10), w.job_rng, 200, w.jobs), {"job_id": 200, "path": ""})
	assert_eq(w.job_rng.state, before)
	assert_eq(BotInput.pick_choice([{"job_id": 100, "available": false, "paths": [{"id": "sword"}]}], w.job_rng),
		{"job_id": -1, "path": ""})


func test_new_forced_paths_reach_the_requested_job_and_weapon_through_run_and_balance_callers() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	var previous_path := HARNESS.forced_path
	for job in [100, 300, 110, 120, 130]:
		for path: Dictionary in jobs.paths_of(job):
			var flag := "%d:%s" % [job, path.id]
			var parsed := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--job=" + flag]))
			assert_eq(SceneFlow.forced_job_error(parsed.options, data), "", flag)
			assert_eq(RunLauncher.options_from_args({"job": flag}).job_path, path.id)
			var w := RunWorld.new(RF.setup("quiet", 1, data))
			RF.place_player(w, 400)
			HARNESS.forced_path = String(parsed.options.job_path)
			for level in [10, 30] if job >= 110 and job <= 130 else [10]:
				w.pickups.spawn(w.player.pos, w.progression.curve.total_to(level)
					- w.progression.curve.total_to(w.progression.level) - w.progression.exp, 4000019)
				for tick in 120:
					w.step(1.0 / 60.0, MoveInput.new())
					if w.state == RunWorld.CHOOSING_JOB:
						break
					if w.state == RunWorld.CHOOSING_UPGRADE:
						w.apply_choice(String(w.pending_cards[0].id))
				assert_eq(w.state, RunWorld.CHOOSING_JOB, flag)
				HARNESS.choose(w, "bot", w.job_rng, [], int(parsed.options.job))
			assert_eq(w.progression.job_id, job, flag)
			assert_eq(w.weapon_path, path.id, flag)
			assert_eq(w.weapon_id(), int(path.item_id), flag)
	HARNESS.forced_path = previous_path


func test_all_historical_fixtures_migrate_without_rewriting_their_equipment_or_explicit_paths() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	var paths := {"lv11_warrior_1st": "spear", "lv34_fighter_2nd": "sword", "lv34_page_2nd": "blunt",
		"lv34_spearman_2nd": "spear", "hunter_2nd": "bow", "crossbowman_2nd": "bow",
		"assassin_2nd": "claw", "bandit_2nd": "dagger", "lv37_brawler_2nd": "knuckle",
		"lv36_gunslinger_2nd": "gun", "lv35_magician_2nd": ""}
	for fixture: String in paths:
		var old: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(
			"res://tests/fixtures/characters/" + fixture + ".json"))
		var migrated := CharacterSnapshot.migrate(old, jobs, {})
		assert_eq(String(migrated.get("weapon_path", "")), paths[fixture], fixture)
		assert_eq(migrated.equipment, old.equipment, "historical spare weapons are retained: " + fixture)
		assert_eq(migrated._doc, old._doc, "retain the original generation provenance")
		assert_eq(CharacterSnapshot.migrate(migrated, jobs, {}), migrated, "idempotent: " + fixture)
