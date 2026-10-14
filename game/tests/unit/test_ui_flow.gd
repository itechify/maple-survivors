extends TestCase
## SaveData (round trip, best-result rule), SceneFlow (command-line run options, finish_run -> results screen with the
## summary and the new-best flag, error screen) and the results screen's data helpers. Saves go to
## TestCase.test_dir(), never the real user://save.json.

var save_path := TestCase.test_dir("ui_flow_save.json")
const RESULTS := preload("res://scenes/ui/results_screen.gd")
const STAGE_SELECT := preload("res://scenes/ui/stage_select.gd")

var _nodes: Array[Node] = []


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	if FileAccess.file_exists(save_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))


static func summary(cleared: bool, time: float, level: int, kills: int, stage: String = "henesys_hg1") -> Dictionary:
	return {"stage": stage, "map_id": 104040000, "map_name": "Henesys Hunting Ground I", "street_name": "Victoria Road",
		"time": time, "duration": 900.0, "cleared": cleared, "level": level, "job_id": 200, "job_name": "Magician",
		"kills": kills, "damage_dealt": kills * 40, "seed": 7,
		"skills": [{"key": "three_snails", "name": "Three Snails", "icon": "Skill.wz/000.img/skill/0001000/icon",
			"rank": 2}]}


# --- SaveData ----------------------------------------------------------------------------------------------------

func test_stage_select_ignores_retired_save_records() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"format": 1,
		"best": {"retired_stage": summary(true, 900, 40, 9000),
			"henesys_hg1": summary(false, 300, 12, 400)},
		"runs": {"retired_stage": 8, "henesys_hg1": 1}}))
	f.close()
	var s := SaveData.new(save_path)
	assert_true(s.best_for("retired_stage").is_empty(), "retired best record is ignored")
	assert_eq(s.runs_for("retired_stage"), 0, "retired run count is ignored")
	assert_eq(int(s.best_for("henesys_hg1").kills), 400, "playable best remains")
	assert_eq(s.runs_for("henesys_hg1"), 1)
	var offered := STAGE_SELECT.load_stages(DataRepo.load_all())
	assert_eq(offered.size(), 2)
	assert_eq(String(offered[0].key), "henesys_hg1")
	assert_eq(String(offered[1].key), "tree_that_grew_1")
	assert_eq(STAGE_SELECT.best_text(s.best_for(String(offered[0].key))),
		"Best: Survived 05:00, Lv. 12, 400 kills")


func test_stage_select_objective_matches_the_clear_rule() -> void:
	var offered := STAGE_SELECT.load_stages(DataRepo.load_all())
	assert_eq(offered[0].objective, "Defeat all 3 bosses to clear.")
	assert_eq(offered[1].objective, "Defeat the boss to clear.")
	var fallback := DataRepo.load_all()
	fallback.stages.stages.tree_that_grew_1.erase("bosses")
	assert_eq(STAGE_SELECT.load_stages(fallback)[1].objective, "Survive 15:00 to clear the stage.")
	assert_false(2220000 in offered[0].mobs, "bosses do not enlarge the ordinary monster roster grid")


func test_save_data_round_trip() -> void:
	var s := SaveData.new(save_path)
	assert_true(s.best.is_empty(), "missing file -> empty save")
	assert_false(FileAccess.file_exists(save_path), "loading never writes")
	assert_true(s.record(summary(false, 300.0, 12, 400)), "first run is a best")
	assert_true(FileAccess.file_exists(save_path))
	var t := SaveData.new(save_path)
	var b := t.best_for("henesys_hg1")
	assert_eq(float(b.time), 300.0)
	assert_eq(int(b.level), 12)
	assert_eq(int(b.kills), 400)
	assert_eq(String(b.job_name), "Magician")
	assert_false(b.has("skills"), "only the record keys are kept")
	assert_eq(t.runs_for("henesys_hg1"), 1)
	assert_eq(t.runs_for("tree_that_grew_1"), 0)
	assert_true(t.best_for("tree_that_grew_1").is_empty())


func test_save_data_best_rule() -> void:
	var s := SaveData.new(save_path)
	s.record(summary(false, 300.0, 12, 400))
	assert_false(s.record(summary(false, 200.0, 20, 900)), "shorter survival is not better")
	assert_true(s.record(summary(false, 300.0, 13, 100)), "same time, higher level")
	assert_true(s.record(summary(true, 900.0, 25, 50)), "a clear beats any death")
	assert_false(s.record(summary(false, 899.0, 40, 9000)), "a death never beats a clear")
	assert_true(s.record(summary(true, 900.0, 25, 60)), "clear vs clear: kills break the level tie")
	assert_eq(int(s.best_for("henesys_hg1").kills), 60)
	assert_eq(s.runs_for("henesys_hg1"), 6)
	assert_eq(int(SaveData.new(save_path).best_for("henesys_hg1").kills), 60, "saved")
	assert_true(SaveData.is_better({"time": 1.0}, {}), "anything beats no record")
	assert_false(SaveData.is_better(summary(true, 900, 25, 60), summary(true, 900, 25, 60)), "a tie is not better")
	assert_false(s.record({"time": 5.0}), "a summary without a stage is ignored")


func test_save_data_broken_file_and_describe() -> void:
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var s := SaveData.new(save_path)
	assert_true(s.best.is_empty(), "a broken file reads as empty")
	assert_eq(SaveData.describe({}), "")
	assert_eq(SaveData.describe(summary(true, 900.0, 31, 3120)), "Cleared, Lv. 31, 3,120 kills")
	assert_eq(SaveData.describe(summary(false, 512.9, 17, 1342)), "Survived 08:32, Lv. 17, 1,342 kills")


# --- SceneFlow ---------------------------------------------------------------------------------------------------

func test_parse_run_args() -> void:
	assert_true(SceneFlow.parse_run_args(PackedStringArray(["--window=title"])).is_empty(), "no --run")
	var r := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys_hg1", "--seed=42", "--autoplay", "--autopick",
		"--speed=4", "--shots=C:/tmp/shots", "--shot-every=5", "--quit-after=60.5", "--perf", "--fill"]))
	assert_eq(String(r.run), "henesys_hg1")
	assert_eq(int(r.seed), 42)
	var o: Dictionary = r.options
	assert_eq(o.autoplay, true)
	assert_eq(o.autopick, true)
	assert_eq(typeof(o.speed), TYPE_INT)
	assert_eq(o.speed, 4)
	assert_eq(o.shots_dir, "C:/tmp/shots")
	assert_eq(typeof(o.shot_every), TYPE_FLOAT)
	assert_near(float(o.shot_every), 5.0)
	assert_near(float(o.quit_after), 60.5)
	assert_eq(o.perf, true)
	assert_eq(o.fill, "1", "other flags pass through")
	var r2 := SceneFlow.parse_run_args(PackedStringArray(["--run=tree_that_grew_1", "--perf=600", "--autoplay=0"]))
	assert_eq(int(r2.seed), -1, "no seed -> random")
	assert_eq(r2.options.perf, 600)
	assert_eq(r2.options.autoplay, false)
	assert_true(SceneFlow.make_seed() >= 0)


func test_finish_run_shows_results_and_records_best() -> void:
	var flow := SceneFlow.new()
	_nodes.append(flow)
	flow.deferred_swaps = false
	flow.save = SaveData.new(save_path)
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_nodes.append(host)
	flow.host = host
	var s := summary(false, 512.0, 17, 1342)
	flow.finish_run(s)
	assert_eq(flow.current_name, "results")
	assert_eq(host.get_child_count(), 1, "one screen under the host")
	var res: Node = host.get_child(0)
	assert_eq(res.get_script(), RESULTS, "the results screen")
	assert_eq(res.summary, s, "the summary reaches the results screen")
	assert_true(res.new_best, "first run on the stage is a new best")
	assert_true(res.previous_best.is_empty())
	assert_true(flow.last_new_best)
	assert_eq(flow.last_stage, "henesys_hg1")
	assert_eq(int(flow.save.best_for("henesys_hg1").kills), 1342)
	flow.finish_run(summary(false, 100.0, 5, 10))
	assert_eq(host.get_child_count(), 1, "the old screen was replaced")
	var res2: Node = host.get_child(0)
	assert_false(res2.new_best, "a worse run is not a new best")
	assert_eq(int(res2.previous_best.kills), 1342, "the previous best is shown")
	assert_eq(int(SaveData.new(save_path).best_for("henesys_hg1").kills), 1342, "best kept on disk")


func test_error_screen_and_goto_without_host() -> void:
	var e := SceneFlow.error_screen("The run scene is missing (x).")
	_nodes.append(e)
	assert_true(e is Control)
	assert_true(String(e.message).contains("missing"))
	var label := e.get_node("Message") as Label
	assert_true(label.text.contains("Esc"), "says how to get back")


func test_results_helpers() -> void:
	assert_eq(RESULTS.headline({"cleared": true}), "Stage Clear!")
	assert_eq(RESULTS.headline({"cleared": false}), "You died...")
	var rows: Array = RESULTS.stat_rows(summary(false, 512.4, 17, 1342))
	assert_eq(rows[0], ["Time", "08:32 / 15:00"])
	assert_eq(rows[1], ["Level", "17"])
	assert_eq(rows[2], ["Job", "Magician"])
	assert_eq(rows[3], ["Kills", "1,342"])
	assert_eq(rows[4], ["Damage dealt", "53,680"])
	assert_eq(RESULTS.group_digits(1234567), "1,234,567")
	assert_eq(RESULTS.group_digits(999), "999")
	assert_eq(RESULTS.group_digits(-1000), "-1,000")
