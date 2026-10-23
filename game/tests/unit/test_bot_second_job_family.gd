extends TestCase
## Bug #261: at an unforced second advancement the sensible bot keeps the weapon family it holds. It draws on job stream
## 8 only among the branches that offer that family (no draw when one does) and keeps the family on the weapon page;
## with no compatible branch, and for forced jobs, the old choice stands.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


## A first-job character (`first`, weapon path `path`, so it holds that family) on the quiet map, seed `p_seed`.
func _first_job(first: int, path: String, p_seed := 1) -> RunWorld:
	var w := RF.quiet_world(400, p_seed)
	w.god = true
	w.change_job(first, path)
	assert_eq(w.held_weapon_family(), path, "job %d holds its %s" % [first, path])
	return w


## Opens the Lv 30 advancement window.
func _open_lv30(w: RunWorld) -> void:
	w.progression.level = 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "the Lv 30 advancement window is open")
	w.drain_events()


func test_a_family_only_one_branch_offers_always_takes_that_branch_without_a_draw() -> void:
	for row: Array in [[500, "knuckle", 510], [500, "gun", 520], [400, "claw", 410], [400, "dagger", 420],
		[300, "bow", 310], [300, "crossbow", 320]]:
		for p_seed in [1, 2, 3, 4, 5, 6, 2026]:
			var w := _first_job(row[0], row[1], p_seed)
			_open_lv30(w)
			var before := w.job_rng.state
			BotInput.auto_choose(w)
			assert_eq(int(w.player_state.job_id), row[2], "a %s %d advances to %d (seed %d)" % [row[1], row[0], row[2],
				p_seed])
			assert_eq(w.held_weapon_family(), row[1], "it keeps its %s" % row[1])
			assert_eq(w.job_rng.state, before, "one compatible branch: no job-stream draw")


func test_a_sword_warrior_draws_only_among_the_sword_branches_and_keeps_the_sword() -> void:
	var seen := {}
	for p_seed in 24:
		var w := _first_job(100, "sword", p_seed)
		_open_lv30(w)
		var pick := BotInput.pick_choice(w.pending_jobs, w.job_rng, 0, w.jobs, "", w.held_weapon_family())
		assert_true(pick.job_id in [110, 120], "Fighter or Page, never Spearman (seed %d)" % p_seed)
		assert_eq(pick.path, "sword", "the sword stays on the weapon page")
		seen[pick.job_id] = true
	assert_eq(seen.size(), 2, "both sword branches come up over seeds")
	var w := _first_job(100, "sword", 1)
	_open_lv30(w)
	var replay := RandomNumberGenerator.new()
	replay.seed = w.job_rng.seed
	replay.state = w.job_rng.state
	var expected: int = [110, 120][replay.randi_range(0, 1)]
	BotInput.auto_choose(w)
	assert_eq(int(w.player_state.job_id), expected, "one uniform draw between the two sword branches")
	assert_eq(w.job_rng.state, replay.state, "and no weapon-page draw")
	assert_eq(w.held_weapon_family(), "sword")


func test_a_spear_or_blunt_warrior_takes_its_one_branch() -> void:
	for row: Array in [["spear", 130], ["blunt", 120]]:
		for p_seed in 8:
			var w := _first_job(100, row[0], p_seed)
			_open_lv30(w)
			BotInput.auto_choose(w)
			assert_eq(int(w.player_state.job_id), row[1], "a %s Warrior advances to %d" % row)
			assert_eq(w.held_weapon_family(), row[0])
			assert_eq(w.weapon_path, row[0], "the page keeps the %s" % row[0])


func test_with_no_compatible_branch_the_old_draw_stands() -> void:
	var w := _first_job(500, "knuckle")
	_open_lv30(w)
	for family in ["", "sword", "wand"]:
		var seen := {}
		for p_seed in 24:
			var a := RandomNumberGenerator.new()
			a.seed = p_seed
			var b := RandomNumberGenerator.new()
			b.seed = p_seed
			var pick := BotInput.pick_choice(w.pending_jobs, a, 0, w.jobs, "", family)
			assert_eq(pick, BotInput.pick_choice(w.pending_jobs, b, 0, w.jobs, ""), "held '%s': the old choice" % family)
			assert_eq(a.state, b.state, "and the same job-stream use")
			seen[pick.job_id] = true
		assert_eq(seen.size(), 2, "held '%s': both Pirate branches come up" % family)


func test_the_first_advancement_ignores_the_held_family() -> void:
	var w := RF.quiet_world(400, 1)
	var options := w.jobs.advancements(0, 10)
	var seen := {}
	for p_seed in 60:
		var a := RandomNumberGenerator.new()
		a.seed = p_seed
		var b := RandomNumberGenerator.new()
		b.seed = p_seed
		var pick := BotInput.pick_choice(options, a, 0, w.jobs, "", "sword")
		assert_eq(pick, BotInput.pick_choice(options, b, 0, w.jobs, ""), "a Beginner's sword does not steer Lv10")
		seen[pick.job_id] = true
	assert_eq(seen.size(), 5, "every first job still comes up at Lv10")


func test_forced_jobs_are_unchanged() -> void:
	var w := _first_job(500, "knuckle")
	_open_lv30(w)
	BotInput.auto_choose(w, false, 520)
	assert_eq(int(w.player_state.job_id), 520, "--job=520 still takes Gunslinger from a Knuckle Pirate")
	w = _first_job(100, "sword")
	_open_lv30(w)
	BotInput.auto_choose(w, false, 110, "axe")
	assert_eq(int(w.player_state.job_id), 110)
	assert_eq(w.weapon_path, "axe", "--job=110:axe still forces the Axe")
	w = _first_job(100, "sword")
	_open_lv30(w)
	BotInput.auto_choose(w, false, 130)
	assert_eq(int(w.player_state.job_id), 130, "--job=130 still takes Spearman from a Sword Warrior")
	w = _first_job(400, "claw")
	_open_lv30(w)
	BotInput.auto_choose(w, false, 420)
	assert_eq(int(w.player_state.job_id), 420, "--job=420 still takes Bandit from a Claw Thief")
