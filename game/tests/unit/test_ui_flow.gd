extends TestCase
## SaveData (round trip, best-result rule), SceneFlow (command-line run options, finish_run -> results screen with the
## summary and the new-best flag, error screen) and the results screen's data helpers. Saves go to
## TestCase.test_dir(), never the real user://save.json.

var save_path := TestCase.test_dir("ui_flow/save.json")
const RESULTS := preload("res://scenes/ui/results_screen.gd")
const STAGE_SELECT := preload("res://scenes/ui/stage_select.gd")

var _nodes: Array[Node] = []


func before_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	TestCase.remove_tree(save_path.get_base_dir())


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
	assert_eq(offered.size(), 3)
	assert_eq(String(offered[0].key), "henesys_hg1")
	assert_eq(String(offered[1].key), "tree_that_grew_1")
	assert_eq(String(offered[2].key), "dark_cave")
	assert_eq(STAGE_SELECT.best_text(s.best_for(String(offered[0].key))),
		"Best: Survived 05:00, Lv. 12, 400 kills")


func test_stage_select_objective_matches_the_clear_rule() -> void:
	var offered := STAGE_SELECT.load_stages(DataRepo.load_all())
	assert_eq(offered[0].objective, "Defeat all 3 bosses to clear.")
	assert_eq(offered[1].objective, "Defeat all 3 bosses to clear.")
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
		"--branch=220", "--speed=4", "--shots=C:/tmp/shots", "--shot-every=5", "--quit-after=60.5", "--perf", "--fill"]))
	assert_eq(String(r.run), "henesys_hg1")
	assert_eq(int(r.seed), 42)
	var o: Dictionary = r.options
	assert_eq(o.autoplay, true)
	assert_eq(o.autopick, true)
	assert_eq(typeof(o.speed), TYPE_INT)
	assert_eq(o.speed, 4)
	assert_eq(int(o.branch), 220, "branch flag reaches RunScene options")
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


func test_one_off_finish_shows_results_without_touching_save() -> void:
	var flow := _flow()
	var s := summary(false, 512.0, 17, 1342)
	flow.finish_run(s)
	assert_eq(flow.current_name, "results")
	assert_eq(flow.current.summary, s)
	assert_false(flow.last_new_best)
	assert_true(flow.save.best.is_empty())
	assert_true(flow.save.history.is_empty())
	assert_false(FileAccess.file_exists(save_path), "tool-only rounds never write a save")


func _flow() -> SceneFlow:
	var flow := SceneFlow.new()
	_nodes.append(flow)
	flow.deferred_swaps = false
	flow.save = SaveData.new(save_path)
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_nodes.append(host)
	flow.host = host
	return flow


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


func test_create_character_enters_saved_tier_one_map_select() -> void:
	var flow := _flow()
	assert_eq(flow.create_character("Maple69"), 0)
	assert_eq(flow.current_name, "stage_select")
	var saved := SaveData.new(save_path).slot(0)
	assert_eq(saved.name, "Maple69")
	assert_eq(int(saved.tier), 0)
	assert_eq(saved.phase, "map_select")
	assert_eq(int(saved.character.level), 1)
	assert_eq(int(saved.character.job_id), 0)
	assert_eq(flow.current.stages.size(), 2)
	assert_eq(flow.current.stages[0].key, "henesys_hg1")
	assert_eq(flow.current.stages[1].key, "tree_that_grew_1")
	assert_eq(flow.create_character("maple69"), -1, "living names are unique ignoring case")
	assert_eq(flow.create_character("no!"), -1)


func test_clear_carries_character_to_next_tier_and_refills_pools() -> void:
	var flow := _flow()
	flow.create_character("Carry69")
	var character: Dictionary = flow.save.slot(0).character
	character.level = 35
	character.exp = 17
	character.job_id = 210
	character.potions.hp.count = 9
	flow.finish_run(summary(true, 900, 35, 3000), character)
	assert_eq(flow.current_name, "stage_select")
	var boundary := SaveData.new(save_path).slot(0)
	assert_eq(int(boundary.tier), 1)
	assert_eq(int(boundary.tiers_cleared), 1)
	assert_eq(int(boundary.rounds_played), 1)
	assert_eq(boundary.character, JSON.parse_string(JSON.stringify(character)))
	assert_eq(flow.current.stages.size(), 1, "single-stage tiers still show map select")
	assert_eq(flow.current.stages[0].key, "dark_cave")
	var setup := preload("res://tests/fixtures/run_fixtures.gd").setup("henesys_hg1", 7)
	setup.character = boundary.character
	var next := RunWorld.new(setup)
	assert_eq(next.player_state.hp, next.player_state.max_hp)
	assert_eq(next.player_state.mp, next.player_state.max_mp)
	assert_eq(next.progression.exp, 17)
	assert_eq(next.potions.snapshot().hp.count, 9)
	assert_eq(flow.save.runs_for("henesys_hg1"), 1)



func test_death_and_final_clear_end_run_and_results_return_to_characters() -> void:
	var flow := _flow()
	flow.create_character("Dead69")
	var character: Dictionary = flow.save.slot(0).character
	character.level = 17
	flow.finish_run(summary(false, 512, 17, 1342), character)
	assert_eq(flow.current_name, "results")
	assert_true(flow.save.slot(0).is_empty())
	assert_eq(flow.save.history[0].ending, "died")
	assert_eq(int(flow.save.history[0].level), 17)
	assert_true(flow.last_new_best)
	flow.current.to_character_select()
	assert_eq(flow.current_name, "character_select")
	flow.create_character("Win69")
	character = flow.save.slot(0).character
	for tier in SceneFlow.tiers().size():
		flow.finish_run(summary(true, 900, 35, 3000), character)
	assert_eq(flow.current_name, "results")
	assert_eq(flow.save.history[1].ending, "victory")
	assert_eq(int(flow.save.history[1].tiers_cleared), 2)
	assert_eq(RESULTS.headline(flow.last_summary), "Victory!")
	assert_true(RESULTS.stat_rows(flow.last_summary).has(["Tiers cleared", "2"]))
	flow.current.to_character_select()
	assert_eq(flow.current_name, "character_select")


func test_quit_round_then_continue_replays_saved_first_minute() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Replay69")
	flow.start_round("henesys_hg1", 2026)
	var first := flow.current as RunScene
	assert_true(first != null and first.world != null)
	var bytes := FileAccess.get_file_as_string(save_path)
	var events := _first_minute(first.world)
	flow.quit_round()
	assert_eq(flow.current_name, "character_select")
	assert_eq(FileAccess.get_file_as_string(save_path), bytes, "Quit round never changes the boundary")
	flow.save = SaveData.new(save_path)
	flow.continue_character(0)
	var replay := flow.current as RunScene
	assert_eq(replay.stage_key, "henesys_hg1")
	assert_eq(replay.run_seed, 2026)
	assert_eq(_first_minute(replay.world), events)
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)


func _first_minute(world: RunWorld) -> String:
	var events := ""
	var memo := {}
	for tick in 3600:
		BotInput.auto_choose(world)
		world.step(1.0 / 60.0, BotInput.decide(world, memo))
		events += JSON.stringify(world.drain_events(), "", false, true)
	return events


func test_save_and_quit_continue_map_select_and_delete_history() -> void:
	var flow := _flow()
	flow.create_character("Slots69")
	flow.start_round("dark_cave", 7)
	assert_eq(flow.current_name, "stage_select", "a later tier cannot be selected early")
	flow.save_and_quit()
	assert_eq(flow.current_name, "character_select")
	flow.continue_character(0)
	assert_eq(flow.current_name, "stage_select")
	assert_eq(flow.current.snapshot.name, "Slots69")
	assert_true(flow.delete_character(0))
	assert_eq(flow.current_name, "character_select")
	assert_true(SaveData.new(save_path).slot(0).is_empty())
	assert_eq(flow.save.history[0].ending, "deleted")
	flow.goto_history()
	assert_eq(flow.current_name, "history")


func test_one_off_character_round_leaves_existing_save_bytes_unchanged() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Tool69")
	var bytes := FileAccess.get_file_as_string(save_path)
	var path := ProjectSettings.globalize_path("res://tests/fixtures/characters/lv35_magician_2nd.json")
	flow.start_run("henesys_hg1", 7, {"character": path})
	var run := flow.current as RunScene
	assert_eq(int(run.world.player_state.level), 38)
	assert_eq(flow.active_slot, -1)
	flow.finish_run(summary(true, 900, 35, 3000))
	assert_eq(flow.current_name, "results")
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	assert_eq(flow.save.runs_for("henesys_hg1"), 0)
	assert_eq(flow.save.history.size(), 0)
