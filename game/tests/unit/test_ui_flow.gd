extends TestCase
## SaveData (round trip, best-result rule), SceneFlow (command-line run options, finish_run -> results screen with the
## summary and the new-best flag, error screen) and the results screen's data helpers. Saves go to
## TestCase.test_dir(), never the real user://save.json.

var save_path := TestCase.test_dir("ui_flow/save.json")
const RESULTS := preload("res://scenes/ui/results_screen.gd")
const STAGE_SELECT := preload("res://scenes/ui/stage_select.gd")

var _nodes: Array[Node] = []


func test_results_skills_fit_above_new_best_at_every_loadout_size() -> void:
	for count in range(1, 257):
		var layout := RESULTS.skill_layout(count)
		assert_eq(layout.cells.size(), count, "every learned skill is shown")
		for cell: Rect2 in layout.cells:
			assert_true(layout.area.encloses(cell), "%d skills fit their reserved area" % count)
			assert_true(cell.end.y <= 324.0, "six pixels separate skills from NEW BEST at y330")
		if not failures.is_empty():
			return


func test_map_select_roster_keeps_long_names_readable_inside_each_cell() -> void:
	for name: String in ["Curse Eye", "Jr. Boogie", "Tauromacis", "Taurospear"]:
		var lines: PackedStringArray = STAGE_SELECT.roster_name_lines(name, 54)
		assert_true(lines.size() <= 2)
		if not "".join(lines).contains("..."):
			assert_eq("".join(lines).replace(" ", ""), name.replace(" ", ""), "wrapped names stay complete")
		for line: String in lines:
			assert_true(MapleText.width(line, MapleText.SMALL) <= 54, "%s fits its roster cell" % line)
			assert_true(line.ends_with("...") or line in name.split(" ") or line == name,
				"roster names wrap only at word boundaries, or ellipsize a long word: " + line)


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


func test_character_select_empty_selection_disables_shared_actions_and_can_create() -> void:
	var flow := _flow()
	flow.goto_character_select()
	var select := flow.current.find_child("SelectCharacter", true, false) as BaseButton
	assert_true(select != null, "one shared Start control belongs to the selected slot")
	if select == null:
		return
	var delete := flow.current.find_child("DeleteCharacter", true, false) as BaseButton
	assert_true(select.disabled)
	assert_true(delete.disabled)
	assert_false(flow.current.create_button.disabled)
	flow.current.create_button.pressed.emit()
	assert_true(flow.current.creation != null)
	flow.current.creation.cancelled.emit()
	assert_eq(flow.current.creation, null)


func test_creation_arrows_change_every_live_preview_field_for_both_genders() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	assert_true(creation.find_child("Next_hair_colour", true, false) != null, "real arrow controls drive the preview")
	if creation.find_child("Next_hair_colour", true, false) == null:
		return
	# Move through the Gender and name surfaces using their visible controls.
	creation.create_button.pressed.emit()
	creation.name_edit.text = "Preview70"
	creation.create_button.pressed.emit()
	for gender in 2:
		for field: String in CharacterCreation.FIELDS:
			var values: Array = creation.model.options(gender, field)
			for option in values.size():
				var before: Dictionary = creation.avatar.look.duplicate(true)
				(creation.find_child("Next_" + field, true, false) as BaseButton).pressed.emit()
				var after: Dictionary = creation.avatar.look
				assert_ne(after, before, "%s gender %d option %d really changes the rendered look" % [field, gender, option])
				assert_eq(after, DataRepo.character_look({"job_id": 0, "look": creation.model.look(gender, creation.choices),
					"beginner_weapon": creation.model.weapon(gender, creation.choices)}, DataRepo.load_all()))
		(creation.find_child("Next_gender", true, false) as BaseButton).pressed.emit()


func test_character_selection_click_keys_details_delete_cancel_and_history() -> void:
	var flow := _flow()
	for i in 3:
		assert_eq(flow.create_character("Select70%d" % i), i)
	flow.goto_character_select()
	var screen: Control = flow.current
	assert_true(screen.create_button.disabled, "three slots disable New")
	assert_eq(screen.select_button.focus_mode, Control.FOCUS_ALL, "shared actions keep keyboard activation")
	assert_eq(screen.selected, 0)
	# Registered original WZ canvases in charselect_1.png; period charselect_2 confirms the scroll follows selection.
	assert_eq(screen.avatars[0].position, Vector2(252, 370))
	var first_info: Vector2 = screen.find_child("CharacterInfo", true, false).position
	(screen.find_child("CharacterSlot2", true, false) as BaseButton).pressed.emit()
	assert_eq(screen.selected, 2)
	assert_eq(screen.find_child("CharacterInfo", true, false).position, first_info + Vector2(250, 0))
	assert_eq(screen.selected_info.name, "Select702")
	assert_eq(screen.selected_info.level, 1)
	assert_eq(screen.selected_info.attributes, flow.save.slot(2).character.attributes)
	if require_cache():
		assert_eq(screen.avatars[2].stance, "walk1")
		assert_eq(screen.avatars[0].stance, "stand1")
	var left := InputEventKey.new()
	left.keycode = KEY_LEFT
	left.pressed = true
	screen._unhandled_input(left)
	assert_eq(screen.selected, 1)
	var saved := FileAccess.get_file_as_string(save_path)
	screen.delete_button.pressed.emit()
	assert_true(screen.delete_dialog is MapleWindow, "deletion uses v83 notice art")
	assert_true(screen.delete_dialog.is_open())
	screen.delete_dialog.transition_seconds = 0
	screen.delete_dialog.cancel()
	assert_eq(FileAccess.get_file_as_string(save_path), saved, "cancel writes nothing")
	screen.delete_button.pressed.emit()
	screen.delete_dialog.accept()
	assert_eq(flow.current_name, "character_select")
	assert_true(flow.save.slot(1).is_empty())
	assert_eq(flow.save.history[0].name, "Select701")
	assert_eq(flow.save.history[0].ending, "deleted")
	(flow.current.find_child("RunHistory", true, false) as BaseButton).pressed.emit()
	assert_eq(flow.current_name, "history")


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


func test_creation_persists_one_authoritative_look_and_the_beginner_weapon() -> void:
	var flow := _flow()
	var look := {"skin": 3, "face": 21002, "hair": 31057, "equips": [1041011, 1061008, 1072038]}
	assert_eq(flow.create_character("Maple70", look, 1322005), 0)
	var saved := SaveData.new(save_path).slot(0)
	assert_eq(saved.character.look, JSON.parse_string(JSON.stringify(look)), "look survives JSON's numeric conversion")
	assert_eq(int(saved.character.beginner_weapon), 1322005)
	assert_false(saved.has("look"), "new run wrappers never duplicate the character's look")
	flow.save_and_quit()
	flow.current.show_creation()
	var bytes := FileAccess.get_file_as_string(save_path)
	flow.current.creation.name_edit.text = "Other70"
	flow.current.creation.cancelled.emit()
	assert_eq(FileAccess.get_file_as_string(save_path), bytes, "cancelling creation writes nothing")


func test_clear_carries_character_to_next_tier_and_refills_pools() -> void:
	var flow := _flow()
	flow.create_character("Carry69")
	var character: Dictionary = flow.save.slot(0).character
	character.level = 35
	character.exp = 17
	character.job_id = 210
	character.potions.hp.count = 9
	flow.finish_run(summary(true, 900, 35, 3000), character)
	assert_eq(flow.current_name, "free_market")
	var boundary := SaveData.new(save_path).slot(0)
	assert_eq(boundary.phase, "free_market", "arrival autosaves the hub boundary")
	assert_eq(int(boundary.tier), 1)
	assert_eq(int(boundary.tiers_cleared), 1)
	assert_eq(int(boundary.rounds_played), 1)
	assert_eq(boundary.character, JSON.parse_string(JSON.stringify(character)))
	flow.save_and_quit()
	assert_eq(flow.current_name, "character_select")
	flow.save = SaveData.new(save_path)
	flow.continue_character(0)
	assert_eq(flow.current_name, "free_market", "Continue returns to the saved hub")
	flow.goto_stage_select()
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


func test_free_market_walk_to_scripted_exit_saves_next_map_select() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Market71")
	flow.finish_run(summary(true, 900, 35, 3000), flow.save.slot(0).character)
	var hub := flow.current as FreeMarket
	assert_true(hub.has_method("step_input"), "the hub accepts the normal fixed-tick movement input")
	if not hub.has_method("step_input"):
		return
	hub.set_process(false)
	hub.motion.player.place(Vector2(-650, 34), hub.motion.fhm)
	for tick in 65:
		hub.step_input(1.0 / 60.0, MoveInput.make(false, true))
	hub.step_input(1.0 / 60.0, MoveInput.make(false, false, true))
	assert_eq(flow.current_name, "stage_select")
	assert_eq(SaveData.new(save_path).slot(0).phase, "map_select")
	assert_eq(flow.current.stages[0].key, "dark_cave")



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


func test_same_tick_boss_projectile_kill_and_contact_death_ends_run_with_last_valid_character() -> void:
	var rf := preload("res://tests/fixtures/run_fixtures.gd")
	var data := rf.quiet_data()
	data.balance.player.skills = []
	data.stages.stages.quiet.bosses = [{"time": 0.1, "mob_id": 2220000,
		"rewards": {"bonus_choices": 1, "exp_mult": 0}}]
	var world := RunWorld.new(rf.setup("quiet", 32, data))
	world.progression.level = 17
	world.refresh_player_stats()
	rf.place_player(world, 400)
	for tick in 6:
		world.step(1.0 / 60.0, MoveInput.new())
	var boss := int(world.bosses.records[0].slot)
	world.swarm.x[boss] = 600
	world.swarm.y[boss] = 190
	world.mob_kinds[world.swarm.kind[boss]].move_speed = 0
	world.projectiles.spawn({"x": 600, "y": 170, "vx": 1, "dmg_min": 1000000,
		"dmg_max": 1000000, "skill": "three_snails"})
	var contact := rf.put_mob(world, 100100, 400, 190, 100)
	world.swarm.state[contact] = MobSwarm.STAND
	world.swarm.alpha[contact] = 1.0
	world.mob_kinds[world.swarm.kind[contact]].pad = 100000
	world.mob_kinds[world.swarm.kind[contact]].acc = 100000
	world.mob_kinds[world.swarm.kind[contact]].move_speed = 0
	world.drain_events()
	world.step(1.0 / 60.0, MoveInput.new())
	var events := world.drain_events()
	assert_eq(world.state, RunWorld.DEAD)
	assert_eq(world.pending_bonus_choices, 1, "the same tick queued an unanswerable boss reward")
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "boss_died"))
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "player_hit" and e.source_kind == "touch"))
	var flow := _flow()
	flow.create_character("Dead32")
	var saved: Dictionary = flow.save.slot(0).character
	flow.finish_run(summary(false, world.time, world.progression.level, world.kills))
	assert_eq(flow.current_name, "results", "terminal death needs no clear-grade snapshot")
	assert_eq(int(flow.last_summary.level), 17, "results retain actual round-end progress")
	var disk := SaveData.new(save_path)
	assert_true(disk.slot(0).is_empty(), "death frees the living slot on disk")
	assert_eq(disk.history.size(), 1)
	if disk.history.size() == 1:
		assert_eq(disk.history[0].ending, "died")
		assert_eq(int(disk.history[0].level), int(saved.level), "history retains the last valid boundary character")
	assert_eq(flow.active_slot, -1)


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
