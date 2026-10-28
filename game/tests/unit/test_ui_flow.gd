extends TestCase
## SaveData (round trip, best-result rule), SceneFlow (command-line run options, finish_run -> results screen with the
## summary and the new-best flag, error screen) and the results screen's data helpers. Saves go to
## TestCase.test_dir(), never the real user://save.json.

const STAGE_FIXTURES := preload("res://tests/fixtures/run_fixtures.gd")

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


func before_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	TestCase.remove_tree(save_path.get_base_dir())


static func summary(cleared: bool, time: float, level: int, kills: int, stage: String = "henesys") -> Dictionary:
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
			"henesys": summary(false, 300, 12, 400)},
		"runs": {"retired_stage": 8, "henesys": 1}}))
	f.close()
	var s := SaveData.new(save_path)
	assert_true(s.best_for("retired_stage").is_empty(), "retired best record is ignored")
	assert_eq(s.runs_for("retired_stage"), 0, "retired run count is ignored")
	assert_eq(int(s.best_for("henesys").kills), 400, "playable best remains")
	assert_eq(s.runs_for("henesys"), 1)
	var offered := STAGE_SELECT.load_stages(DataRepo.load_all())
	assert_eq(offered.map(func(c: Dictionary) -> String: return String(c.key)),
		["henesys", "ellinia", "perion", "kerning", "sleepywood"])
	assert_eq(STAGE_SELECT.best_text(s.best_for(String(offered[0].key))),
		"Best: Survived 05:00, Lv. 12, 400 kills")


func test_stage_select_objective_matches_the_clear_rule() -> void:
	var offered := STAGE_SELECT.load_stages(DataRepo.load_all())
	assert_eq(offered[0].objective, "Defeat 3 bosses across 3 maps")
	assert_eq(offered[1].objective, "Defeat 3 bosses across 3 maps")
	var fallback := DataRepo.load_all()
	STAGE_FIXTURES.set_bosses(fallback.stages.stages.ellinia, [])
	assert_eq(STAGE_SELECT.load_stages(fallback)[1].objective, "Survive 15:00 to clear the stage.")


func test_save_data_round_trip() -> void:
	var s := SaveData.new(save_path)
	assert_true(s.best.is_empty(), "missing file -> empty save")
	assert_false(FileAccess.file_exists(save_path), "loading never writes")
	assert_true(s.record(summary(false, 300.0, 12, 400)), "first run is a best")
	assert_true(FileAccess.file_exists(save_path))
	var t := SaveData.new(save_path)
	var b := t.best_for("henesys")
	assert_eq(float(b.time), 300.0)
	assert_eq(int(b.level), 12)
	assert_eq(int(b.kills), 400)
	assert_eq(String(b.job_name), "Magician")
	assert_false(b.has("skills"), "only the record keys are kept")
	assert_eq(t.runs_for("henesys"), 1)
	assert_eq(t.runs_for("ellinia"), 0)
	assert_true(t.best_for("ellinia").is_empty())


func test_save_data_best_rule() -> void:
	var s := SaveData.new(save_path)
	s.record(summary(false, 300.0, 12, 400))
	assert_false(s.record(summary(false, 200.0, 20, 900)), "shorter survival is not better")
	assert_true(s.record(summary(false, 300.0, 13, 100)), "same time, higher level")
	assert_true(s.record(summary(true, 900.0, 25, 50)), "a clear beats any death")
	assert_false(s.record(summary(false, 899.0, 40, 9000)), "a death never beats a clear")
	assert_true(s.record(summary(true, 900.0, 25, 60)), "clear vs clear: kills break the level tie")
	assert_eq(int(s.best_for("henesys").kills), 60)
	assert_eq(s.runs_for("henesys"), 6)
	assert_eq(int(SaveData.new(save_path).best_for("henesys").kills), 60, "saved")
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
	var r := SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--seed=42", "--autoplay", "--autopick",
		"--job=220", "--speed=4", "--shots=C:/tmp/shots", "--shot-every=5", "--quit-after=60.5", "--perf", "--fill"]))
	assert_eq(String(r.run), "henesys")
	assert_eq(int(r.seed), 42)
	var o: Dictionary = r.options
	assert_eq(o.autoplay, true)
	assert_eq(o.autopick, true)
	assert_eq(typeof(o.speed), TYPE_INT)
	assert_eq(o.speed, 4)
	assert_eq(int(o.job), 220, "job flag reaches RunScene options")
	assert_eq(int(SceneFlow.parse_run_args(PackedStringArray(["--run=henesys", "--branch=230"])).options.job), 230,
		"the deprecated --branch is the same option")
	assert_eq(o.shots_dir, "C:/tmp/shots")
	assert_eq(typeof(o.shot_every), TYPE_FLOAT)
	assert_near(float(o.shot_every), 5.0)
	assert_near(float(o.quit_after), 60.5)
	assert_eq(o.perf, true)
	assert_eq(o.fill, "1", "other flags pass through")
	var r2 := SceneFlow.parse_run_args(PackedStringArray(["--run=ellinia", "--perf=600", "--autoplay=0"]))
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
	# Move through the name surface using its visible controls.
	creation.name_edit.text = "Preview70"
	creation.create_button.pressed.emit()
	for gender in 2:
		for field: String in CharacterCreation.FIELDS:
			if field == "weapon":
				continue # the job's creation weapon: shown on the Look step, not chosen (#286)
			var values: Array = creation.model.options(gender, field)
			for option in values.size():
				var before: Dictionary = creation.avatar.look.duplicate(true)
				(creation.find_child("Next_" + field, true, false) as BaseButton).pressed.emit()
				var after: Dictionary = creation.avatar.look
				assert_ne(after, before, "%s gender %d option %d really changes the rendered look" % [field, gender, option])
				assert_eq(after, DataRepo.character_look({"job_id": 0, "look": creation.model.look(gender, creation.choices),
					"beginner_weapon": 1372005}, DataRepo.load_all()))
		(creation.find_child("Next_gender", true, false) as BaseButton).pressed.emit()


func test_creation_opens_on_name_and_cancel_returns_one_step() -> void:
	var flow := _flow()
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	assert_eq(creation.phase, "name", "creation opens on Name; there is no separate Gender step")
	assert_true(creation.find_child("GenderValue", true, false) == null, "the Gender dropdown is gone")
	assert_eq(creation.create_button, creation.name_button)
	creation.name_edit.text = "Phase218"
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "look", "Name OK goes to Look")
	assert_eq(creation.create_button, creation._look_ok)
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "Look OK goes to the Job page")
	assert_eq(creation.create_button, creation._job_ok)
	assert_true(212 in creation.job_ids, "the Arch Mage is listed")
	assert_eq(creation.job_id, 212, "the default job is chosen")
	creation._return_look()
	assert_eq(creation.phase, "look", "Job Cancel goes back to Look")
	creation._return_name()
	assert_eq(creation.phase, "name", "Look Cancel goes back to Name")
	var closed := [false]
	creation.cancelled.connect(func() -> void: closed[0] = true)
	creation._cancel_name()
	assert_true(closed[0], "Name Cancel closes creation back to character select")


func test_creation_defaults_to_male_and_the_look_row_flips_to_female() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	assert_eq(creation.gender, 0, "gender defaults to Male")
	assert_eq(creation.option_labels.gender.text, "Male")
	assert_eq(creation.avatar.look, DataRepo.character_look({"job_id": 0, "look": creation.model.look(0, {}),
		"beginner_weapon": 1372005}, DataRepo.load_all()), "the preview starts as the Male look with the job's wand")
	creation.name_edit.text = "Boy21800"
	creation.create_button.pressed.emit()
	creation.create_button.pressed.emit()
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var male: Dictionary = flow.save.slot(0).character
	assert_eq(male.look.face, creation.model.look(0, {}).face, "untouched gender row creates a Male character")
	assert_eq(male.look.hair, creation.model.look(0, {}).hair)
	flow.goto_character_select()
	flow.current.show_creation()
	creation = flow.current.creation
	(creation.find_child("Next_gender", true, false) as BaseButton).pressed.emit()
	assert_eq(creation.option_labels.gender.text, "Female")
	creation.name_edit.text = "Girl21800"
	creation.create_button.pressed.emit()
	creation.create_button.pressed.emit()
	creation.create_button.pressed.emit()
	var female: Dictionary = flow.save.slot(1).character
	assert_eq(female.look.face, creation.model.look(1, {}).face, "flipping the Look row creates a Female character")
	assert_eq(female.look.hair, creation.model.look(1, {}).hair)
	assert_ne(female.look.face, male.look.face)


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
	assert_eq(screen.selected_info.level, 1, "a character has no level between rounds")
	assert_eq(screen.selected_info.job, "Arch Mage (Fire, Poison)")
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


func test_stage_select_lists_the_region_and_continent() -> void:
	var offered := STAGE_SELECT.load_stages(DataRepo.load_all())
	var want := [["Henesys", "Victoria Island"], ["Ellinia", "Victoria Island"], ["Perion", "Victoria Island"],
		["Kerning City", "Victoria Island"], ["Sleepywood", "Victoria Island"]]
	for i in want.size():
		assert_eq(String(offered[i].region), want[i][0], "stage %d region" % i)
		assert_eq(String(offered[i].continent), want[i][1], "stage %d continent" % i)
		assert_false(offered[i].has("name") or offered[i].has("street"), "the WZ map name is not the view data")
	var legacy := DataRepo.load_all()
	legacy.stages.stages.henesys.erase("region")
	legacy.stages.stages.henesys.erase("continent")
	var fallback: Dictionary = STAGE_SELECT.load_stages(legacy)[0]
	assert_eq(String(fallback.region), "Henesys Hunting Ground I", "a stage without a region falls back to its name")
	assert_eq(String(fallback.continent), "")


func test_results_name_the_region_and_continent() -> void:
	var s := summary(false, 512.4, 17, 1342)
	s.region = "Henesys"
	s.continent = "Victoria Island"
	assert_eq(DataRepo.summary_stage_lines(s), ["Henesys", "Victoria Island"])
	# A summary saved before the fields existed (map and street name only) reads the stage's region from stages.json.
	assert_false(summary(false, 1.0, 1, 1).has("region"))
	assert_eq(DataRepo.summary_stage_lines(summary(false, 1.0, 1, 1)), ["Henesys", "Victoria Island"])
	assert_eq(DataRepo.summary_stage_lines(summary(false, 1.0, 1, 1, "sleepywood")), ["Sleepywood", "Victoria Island"])
	# A retired stage key has no stages.json entry: the old names stay readable.
	assert_eq(DataRepo.summary_stage_lines(summary(false, 1.0, 1, 1, "retired_stage")), ["Henesys Hunting Ground I", "Victoria Road"])
	assert_eq(DataRepo.summary_stage_lines({"stage": "retired_stage"}), ["retired_stage", ""])


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


func test_creation_persists_one_authoritative_look_and_the_job_weapon() -> void:
	var flow := _flow()
	var look := {"skin": 3, "face": 21002, "hair": 31057, "equips": [1041011, 1061008, 1072038]}
	assert_eq(flow.create_character("Maple70", look, 212), 0)
	var saved := SaveData.new(save_path).slot(0)
	assert_eq(saved.character.look, JSON.parse_string(JSON.stringify({"skin": 3, "face": 21002, "hair": 31057})),
		"look survives JSON's numeric conversion; its equips are worn equipment now")
	assert_eq(Equipment.worn_ids(saved.character.equipment.worn), [1041011, 1061008, 1072038, 1372005],
		"the creation outfit and the job's weapon are the first worn equipment")
	assert_eq(int(saved.character.format), CharacterSnapshot.FORMAT)
	assert_false(saved.has("look"), "new run wrappers never duplicate the character's look")
	flow.save_and_quit()
	flow.current.show_creation()
	var bytes := FileAccess.get_file_as_string(save_path)
	flow.current.creation.name_edit.text = "Other70"
	flow.current.creation.cancelled.emit()
	assert_eq(FileAccess.get_file_as_string(save_path), bytes, "cancelling creation writes nothing")


func test_free_market_walk_to_scripted_exit_opens_map_select() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Market71")
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
	assert_eq(flow.current.stages[0].key, "henesys", "map select lists every tier, tier 1 first")



## The hub's Equip and Item windows (#108): E / I open them over the Free Market, movement holds while one is open,
func test_the_autoplay_option_reaches_the_hub_and_its_shop_visit() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Auto112")
	var character: Dictionary = flow.save.slot(0).character
	character.mesos = 200000
	var slot := flow.save.slot(0)
	slot.character = character
	flow.save.update_slot(0, slot)
	flow.autoplay = true
	flow.continue_character(0)
	var hub := flow.current as FreeMarket
	assert_true(hub != null and RunScene.option_flag(hub.options, "autoplay"), "the hub got the autoplay option")
	if hub != null:
		assert_true(not hub.shop_visit.is_empty(), "the bot shopped on entry")
		assert_eq(int(flow.save.slot(0).character.mesos), hub.inventory.mesos, "and the visit was saved")


## a change goes through the carried character's RunWorld into the drawn look and the saved slot at once, Esc closes
## the front window before the pause menu.
func test_free_market_equip_window_changes_the_saved_character_at_once() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Market108")
	var hub := flow.current as FreeMarket
	assert_true(hub != null and hub.ui_windows != null, "the hub hosts a window stack")
	if hub == null or hub.ui_windows == null:
		return
	hub.set_process(false)
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	key.keycode = KEY_E
	key.pressed = true
	assert_true(hub.handle_hotkey(key), "E opens the Equip window in the hub")
	var ew := hub.ui_windows.top() as EquipWindow
	assert_true(ew != null)
	if ew == null:
		return
	var x := hub.motion.player.pos.x
	for tick in 10:
		hub.step_input(1.0 / 60.0, MoveInput.make(false, true))
	assert_eq(hub.motion.player.pos.x, x, "movement holds while a window is open")
	assert_true(1372005 in hub.avatar.look.equips, "drawn with the creation wand")
	assert_eq(ew.take_off("weapon"), "")
	assert_false(1372005 in hub.avatar.look.equips, "the hub redraws the character bare-handed at once")
	var saved := SaveData.new(save_path).slot(0)
	assert_false(saved.character.equipment.worn.has("weapon"), "the slot's character was saved at once")
	assert_eq(saved.character.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id)), [1372005])
	key.physical_keycode = KEY_I
	key.keycode = KEY_I
	assert_true(hub.handle_hotkey(key), "I opens the Item window")
	var iw := hub.ui_windows.top() as ItemWindow
	assert_true(iw != null and iw.cell(0).get("id") == 1372005, "the Item window lists the wand")
	assert_eq(hub.ui_windows.ids(), PackedStringArray(["equip", "item"]))
	key.physical_keycode = KEY_ESCAPE
	key.keycode = KEY_ESCAPE
	assert_true(hub.handle_hotkey(key), "Esc closes the front window")
	assert_eq(hub.ui_windows.ids(), PackedStringArray(["equip"]))
	hub.handle_hotkey(key)
	assert_false(hub.ui_windows.has_windows())
	assert_false(hub.pause_menu.is_open(), "closing windows never opened the pause menu")
	for tick in 10:
		hub.step_input(1.0 / 60.0, MoveInput.make(false, true))
	assert_true(hub.motion.player.pos.x > x, "walking again")
	hub.handle_hotkey(key)
	assert_true(hub.pause_menu.is_open(), "with no window open Esc pauses")


func test_same_tick_boss_projectile_kill_and_contact_death_ends_run_with_last_valid_character() -> void:
	var rf := preload("res://tests/fixtures/run_fixtures.gd")
	var data := rf.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	STAGE_FIXTURES.set_bosses(data.stages.stages.quiet, [{"time": 0.1, "mob_id": 2220000,
		"rewards": {"bonus_choices": 1, "exp_mult": 0}}])
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
	flow.finish_run(summary(false, world.time, world.progression.level, world.kills), world.character_snapshot())
	assert_eq(flow.current_name, "results", "a death with an unanswered boss reward still ends the round")
	assert_eq(int(flow.last_summary.level), 17, "results retain actual round-end progress")
	var disk := SaveData.new(save_path)
	assert_eq(disk.slot(0).name, "Dead32", "death does not free the slot")
	assert_eq(disk.history.size(), 1)
	if disk.history.size() == 1:
		assert_eq(disk.history[0].ending, "died")
		assert_eq(int(disk.history[0].level), 17, "history keeps the level reached")
	assert_eq(flow.active_slot, 0)


func test_save_and_quit_continue_the_hub_and_delete_history() -> void:
	var flow := _flow()
	flow.create_character("Slots69")
	flow.start_round("sleepywood", 7)
	assert_eq(flow.current_name, "free_market", "a later tier cannot be started early")
	flow.save_and_quit()
	assert_eq(flow.current_name, "character_select")
	flow.continue_character(0)
	assert_eq(flow.current_name, "free_market", "Continue opens the hub")
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
	var path := ProjectSettings.globalize_path("res://tests/fixtures/characters/fp_arch_mage.json")
	flow.start_run("henesys", 7, {"character": path})
	var run := flow.current as RunScene
	assert_eq(int(run.world.player_state.level), 1, "a tool character also starts the round at Lv1")
	assert_eq(flow.active_slot, -1)
	flow.finish_run(summary(true, 900, 35, 3000))
	assert_eq(flow.current_name, "results")
	assert_eq(FileAccess.get_file_as_string(save_path), bytes)
	assert_eq(flow.save.runs_for("henesys"), 0)
	assert_eq(flow.save.history.size(), 0)
