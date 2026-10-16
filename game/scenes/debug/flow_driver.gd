extends Node
## Plays the real game (main.tscn under this node: the Flow autoload, every screen and the RunScene) by injecting
## keyboard and mouse events through Input.parse_input_event, exactly like a player, and saves a screenshot of every
## step. A smoke test of the whole flow and the evidence for docs/IMPLEMENTATION_PLAN.md acceptance checks.
##
##   bash scripts/godot.sh --path game res://scenes/debug/flow_driver.tscn -- --scenario=full --shots=C:/abs/dir
##
## Scenarios (--scenario=):
##   rounds  creates two characters through the v83 signboard/form, clears tier 1 (fixed-tick warp), walks to
##           Free Market out00, saves/reloads map select, starts tier 2, quits/reloads the same boundary/seed,
##           plays to death, deletes the spare character and checks both history entries. --diagnostic-victory=1
##           makes ONLY tier 2 invulnerable and applies diagnostic lethal boss hits after 15:00 to inspect victory;
##           this is presentation evidence, not balance evidence. Bosses/rewards still finish through RunWorld.
##   full    title -> character select -> Explorer creation -> tier-1 map select -> keyboard-steered round -> job/cards ->
##           pause/resume -> death -> results -> character select -> new character -> Quit round confirmation ->
##           continue the saved round/seed -> Quit round -> history -> characters -> title -> quit.
##           Slots/history go only to shots_dir/driver_save.json. Delete that file for a fresh repeat.
##   clear   --run tool one-off: waits for clear -> results -> character select -> title -> quit; never saves.
##   title   the title screen only: waits for it, saves the shot, quits (e.g. to check an exported build:
##           MapleSurvivors.exe res://scenes/debug/flow_driver.tscn -- --scenario=title --shots=<dir>).
##   import  for a cache-less start (point MAPLE_SURVIVORS_CACHE / APPDATA at an empty folder): the import screen,
##           types --wz=<folder> into the path field, clicks Import, waits for the importer and the title.
## Other flags: --shots=<abs dir> (required), --time-scale=<k> (default 3: the run plays k times faster, windows and
## effects too), --stop-at=<run s> (full: 300), --seed=<n> (full: 1), --wz=<folder> (import).
##
## Screenshots are named NN_<step>.png; the driver prints one "flow_driver:" line per step and quits with exit code 1
## when a step times out or the full scenario misses the Magician / pause-resume path. Full also writes summary.json
## from RunScene's public snapshot, including the seed, potion totals, tier counts and missing assets.
## tier C: diagnostic names, seed 1, 1800s combat cap, 600-tick yields, 100s progress logs,
## 30s/8px exit-walk guard and UI waits/timeouts are automation choices, never survivor tuning.

const MAIN := "res://scenes/main.tscn"
## Keys the steering sends (project.godot defaults: arrows, Space jump and Q/E potions).
const KEYS := {"left": KEY_LEFT, "right": KEY_RIGHT, "up": KEY_UP, "down": KEY_DOWN, "jump": KEY_SPACE,
	"drink_hp": KEY_Q, "drink_mp": KEY_E}

var args := {}
var shots_dir := ""
var flow: SceneFlow
var _n := 0
var _steer := false
var _held := {}
var _memo := {}
var _failed := false
var _missing := PackedStringArray()
var _rounds: Array[Dictionary] = []


func _ready() -> void:
	args = SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots_dir = String(args.get("shots", "")).replace("\\", "/")
	if shots_dir == "":
		push_error("flow_driver: --shots=<abs dir> is required")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots_dir)
	flow = get_node_or_null("/root/Flow") as SceneFlow
	# The scripted UI creates/deletes real slots, always in ignored evidence, never the player's save.
	flow.save = SaveData.new(shots_dir.path_join("driver_save.json"))
	add_child((load(MAIN) as PackedScene).instantiate())
	match String(args.get("scenario", "full")):
		"rounds":
			_scenario_rounds()
		"clear":
			_scenario_clear()
		"import":
			_scenario_import()
		"title":
			_scenario_title()
		"full":
			_scenario_full()
		_:
			_fail("unknown scenario: " + String(args.get("scenario")))


func _process(_delta: float) -> void:
	if _steer:
		_steer_run()


# --- scenarios ---------------------------------------------------------------------------------------------------

func _scenario_rounds() -> void:
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _key(KEY_ENTER)
	if not await _create_character("Spare75"):
		return
	await _click(flow.current.get("back_button") as Control)
	if not await _create_character("Rounds75"):
		return
	await _sleep(2.0)
	await _shot("map_select_tier1")
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "tier 1"):
		return
	await _shot("tier1_start")
	if not await _warp_round():
		return
	if not await _until(func() -> bool: return flow.current_name == "free_market", 15.0, "Free Market after real clear"):
		return
	var boundary := flow.save.slot(flow.active_slot)
	if not _expect(boundary.phase == "free_market" and int(boundary.tier) == 1
			and int(boundary.rounds_played) == 1, "tier-1 clear did not save the next boundary"):
		return
	await _sleep(0.5)
	await _shot("free_market_arrival")
	# Also check hub Save & quit and disk reload, through the real pause controls.
	await _key(KEY_ESCAPE)
	await _shot("free_market_save_quit")
	await _key(KEY_2)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "saved hub"):
		return
	_reload_save()
	# Mouse selects the spare, Right selects the carried character; Start is the shared v83 signboard button.
	await _click(flow.current.slot_buttons[0])
	if not _expect(flow.current.selected == 0, "mouse character selection failed"):
		return
	await _key(KEY_RIGHT)
	if not _expect(flow.current.selected == 1, "keyboard character selection failed"):
		return
	await _shot("selected_carried_character")
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "free_market", 10.0, "continued hub"):
		return
	var hub := flow.current as FreeMarket
	var exit_pos := Vector2.ZERO
	for portal: Dictionary in hub.motion.portals.links:
		if portal.name == "out00":
			exit_pos = portal.pos
	# No teleport or direct scene call: hold arrows from the canonical arrival to the real exit.
	var t0 := Time.get_ticks_msec()
	while absf(hub.motion.player.pos.x - exit_pos.x) > 8.0:
		if Time.get_ticks_msec() - t0 > 30000:
			_fail("walking to out00 timed out")
			return
		_set_key("left", hub.motion.player.pos.x > exit_pos.x)
		_set_key("right", hub.motion.player.pos.x < exit_pos.x)
		await get_tree().process_frame
	_release_all()
	await _shot("free_market_out00")
	_collect_missing(hub)
	await _key(KEY_UP)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "tier-2 map select via out00"):
		return
	await _sleep(2.0)
	if not _expect(flow.current.stages.size() == 1 and flow.current.stages[0].key == "dark_cave",
			"tier 2 offered a stage outside Dark Cave"):
		return
	await _shot("map_select_tier2")
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "saved map select"):
		return
	_reload_save()
	await _click(flow.current.slot_buttons[1])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "continued map select"):
		return
	await _sleep(2.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "tier 2"):
		return
	var saved := flow.save.slot(flow.active_slot)
	var bytes := FileAccess.get_file_as_bytes(shots_dir.path_join("driver_save.json"))
	await _sleep(1.0)
	await _shot("dark_cave_start")
	await _quit_round_ui()
	if _failed:
		return
	if not _expect(FileAccess.get_file_as_bytes(shots_dir.path_join("driver_save.json")) == bytes,
			"Quit round changed the boundary file"):
		return
	_reload_save()
	await _click(flow.current.slot_buttons[1])
	await _click(flow.current.select_button)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "continued tier 2"):
		return
	var run := flow.current as RunScene
	# Disk JSON turns numeric fields into floats; compare both snapshots in the same representation.
	var normalized: Dictionary = JSON.parse_string(JSON.stringify(saved))
	var resumed: Dictionary = JSON.parse_string(JSON.stringify(flow.save.slot(flow.active_slot)))
	if resumed != normalized:
		print("flow_driver: boundary before ", JSON.stringify(normalized))
		print("flow_driver: boundary resumed ", JSON.stringify(resumed))
	print("flow_driver: resumed level %s / saved %s" % [run.world.player_state.level, saved.character.level])
	if not _expect(run.run_seed == int(saved.round_seed) and run.stage_key == saved.stage,
			"Continue changed stage or round seed"):
		return
	if not _expect(run.world.player_state.level == int(saved.character.level)
			and resumed == normalized,
			"Continue changed the boundary character"):
		return
	await _shot("dark_cave_replayed")
	if String(args.get("diagnostic-victory", "0")) == "1":
		run.world.god = true
	if not await _warp_round():
		return
	if not await _until(func() -> bool: return flow.current_name == "results", 15.0, "run ending"):
		return
	await _sleep(1.0)
	var ending := "victory" if String(args.get("diagnostic-victory", "0")) == "1" else "died"
	if not _expect(flow.last_summary.ending == ending, "unexpected run ending"):
		return
	await _shot("results_" + ending)
	await _click(flow.current.back_button)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "ended character removed"):
		return
	if not _expect(flow.save.slot(1).is_empty(), "ended run still occupies a slot"):
		return
	await _click(flow.current.slot_buttons[0])
	await _click(flow.current.delete_button)
	await _shot("delete_confirmation")
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	if not _expect(not flow.save.slot(0).is_empty(), "cancel deleted the spare"):
		return
	await _click(flow.current.delete_button)
	await _sleep(0.3) # Respect the same modal input guard when reopening after Cancel.
	await _key(KEY_ENTER)
	if not await _until(func() -> bool: return flow.save.slot(0).is_empty(), 10.0, "confirmed deletion"):
		return
	await _sleep(0.5)
	await _click(flow.current.find_child("RunHistory", true, false) as Control)
	if not await _until(func() -> bool: return flow.current_name == "history", 10.0, "History entry"):
		return
	await _sleep(1.0)
	await _shot("history_" + ending)
	var history := flow.save.history
	if not _expect(history.size() == 2 and history[0].ending == ending
			and history[0].name == "Rounds75" and int(history[0].rounds_played) == 2
			and history[1].ending == "deleted" and history[1].name == "Spare75", "history did not archive both runs"):
		return
	_collect_missing(flow.current)
	if not _expect(_missing.is_empty(), "missing assets: %s" % _missing):
		return
	var report := {"scenario": "rounds", "diagnostic_victory": ending == "victory", "rounds": _rounds,
		"replayed_seed": saved.round_seed, "history": history, "missing": Array(_missing), "failures": []}
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	print("flow_driver: rounds PASSED ", JSON.stringify(report))
	get_tree().quit()


## Warps actual fixed ticks with the existing bot/choice policy; never fabricates a clear or character.
## UI navigation remains injected input. End events still go through RunScene's normal presentation/Flow path.
func _warp_round() -> bool:
	var run := flow.current as RunScene
	run.set_process(false)
	var memo := {}
	var ticks := 0
	while run.world.time < 1800.0 and run.world.state not in [RunWorld.DEAD, RunWorld.CLEARED]:
		BotInput.auto_choose(run.world)
		if run.world.state in [RunWorld.DEAD, RunWorld.CLEARED]:
			run.handle_events(run.world.drain_events())
			break
		if run.world.state != RunWorld.PLAYING:
			continue
		if run.world.god and run.stage_key == "dark_cave" and run.world.time >= run.world.duration:
			# tier C: supplemental victory-screen staging, not a naturally won round or a balance candidate.
			# Use the real damage/death/reward path; never fabricate a summary or bypass pending choices.
			for record: Dictionary in run.world.bosses.records:
				var slot := int(record.slot)
				if not bool(record.dead) and slot >= 0 and run.world.swarm.is_live(slot):
					run.world.hit_mob(slot, {"skill": "three_snails", "magic": true, "damage_min": 1e9,
						"damage_max": 1e9, "crit": 0.0, "crit_mult": 1.0}, -1)
		run.world.step(RunScene.DT, BotInput.decide(run.world, memo))
		var events := run.world.drain_events()
		if run.world.state in [RunWorld.DEAD, RunWorld.CLEARED]:
			run.handle_events(events)
		ticks += 1
		if ticks % 600 == 0:
			await get_tree().process_frame
		if ticks % 6000 == 0:
			print("flow_driver: warp %.0f s / Lv %d" % [run.world.time, run.world.player_state.level])
	if not _expect(run.world.state in [RunWorld.DEAD, RunWorld.CLEARED], "round timed out during warp"):
		return false
	run._apply_job_look(int(run.world.player_state.job_id))
	run._present(0.0)
	_collect_missing(run)
	_rounds.append(run.build_summary())
	if not _expect(run.world.warnings.is_empty(), "world warnings during warp"):
		return false
	await _shot("round_" + run.world.state_name().to_lower())
	run.set_process(true)
	return true


func _quit_round_ui() -> void:
	await _key(KEY_ESCAPE)
	await _sleep(0.3)
	await _key(KEY_2)
	await _shot("quit_round_warning")
	await _key(KEY_2)
	await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "Quit round")


func _reload_save() -> void:
	flow.save = SaveData.new(shots_dir.path_join("driver_save.json"))


func _expect(ok: bool, message: String) -> bool:
	if not ok:
		_fail(message)
	return ok

func _scenario_full() -> void:
	var ts := float(args.get("time-scale", "3"))
	var stop_at := float(args.get("stop-at", "300"))
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title"):
		return
	await _sleep(9.0)
	await _shot("title")
	await _key(KEY_ENTER)
	if not await _create_character("Flow69"):
		return
	await _sleep(3.0)
	await _shot("map_select")
	var sel: Node = flow.current
	await _start_selected(sel)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "run"):
		return
	var run := flow.current as RunScene
	await _sleep(2.0)
	await _shot("run_start")
	# A few seconds of plain keyboard play before the steering takes over.
	await _hold(KEY_RIGHT, 1.2)
	await _key(KEY_SPACE)
	await _sleep(0.25)
	await _shot("run_keyboard_jump")
	await _hold(KEY_LEFT, 0.8)
	Engine.time_scale = ts
	_steer = true
	var windows := 0
	var paused_once := false
	var resumed_once := false
	var job_seen := false
	while is_instance_valid(run) and run.world != null and run.world.state != RunWorld.DEAD:
		await get_tree().process_frame
		if run.world.time >= stop_at and _steer:
			_steer = false
			_release_all()
			print("flow_driver: hands off the keys at %.0f s (level %d)" % [run.world.time, run.world.player_state.level])
			await _shot("hands_off")
		if run.window is LevelUpWindow and (run.window as MapleWindow).is_open():
			_release_all()
			windows += 1
			await _sleep(0.5)
			if not is_instance_valid(run.window):
				continue
			var lw := run.window as LevelUpWindow
			if windows <= 3 or lw.level % 5 == 0:
				await _shot("levelup_%d" % lw.level)
			var pick := _card_index(run, lw.cards)
			if windows == 1:
				await _click_at(lw.card_rect(pick).get_center())
			else:
				await _key((KEY_1 + pick) as Key)
			await _sleep(0.3)
		elif run.window is JobAdvanceWindow and (run.window as MapleWindow).is_open():
			_release_all()
			job_seen = true
			await _sleep(0.6)
			await _shot("job_dialog")
			var jw := run.window as JobAdvanceWindow
			var idx := -1
			for i in jw.entries.size():
				if jw.entries[i].kind == "job" and jw.entries[i].available:
					idx = i
					break
			await _key((KEY_1 + maxi(0, idx)) as Key)
			await _sleep(0.4)
			await _shot("job_confirm")
			await _key(KEY_ENTER)
			await _sleep(0.9)
			await _shot("job_changed")
		elif not paused_once and job_seen and run.window == null and run.world.state == RunWorld.PLAYING:
			paused_once = true
			_release_all()
			await _key(KEY_ESCAPE)
			await _sleep(0.6)
			await _shot("pause_menu")
			await _key(KEY_ESCAPE)
			await _sleep(0.3)
			resumed_once = not run.paused
			print("flow_driver: resumed = %s" % resumed_once)
	_steer = false
	_release_all()
	print("flow_driver: the character died at %.0f s, level %d" % [run.world.time, run.world.player_state.level])
	var snapshot := run.perf_summary(run.build_summary())
	snapshot["flow"] = {"windows": windows, "job_seen": job_seen, "pause_seen": paused_once, "resumed": resumed_once}
	snapshot["card_tiers_offered"] = run.world.card_tiers_offered.duplicate()
	snapshot["card_tiers_picked"] = run.world.card_tiers_picked.duplicate()
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(snapshot, "\t"))
		file.close()
	print("flow_driver: snapshot %s" % JSON.stringify(snapshot))
	if not job_seen or int(snapshot.job_id) != 200 or not paused_once or not resumed_once:
		_failed = true
		push_error("flow_driver: full scenario did not complete the Magician and pause/resume path")
	await _sleep(1.0)
	await _shot("death_tombstone")
	if not await _until(func() -> bool: return flow.current_name == "results", 30.0, "results"):
		return
	Engine.time_scale = 1.0
	await _sleep(3.0)
	await _shot("results_death")
	await _click(flow.current.get("back_button") as Control)
	if not await _create_character("Quit69"):
		return
	await _sleep(3.0)
	await _start_selected(flow.current)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "new character round"):
		return
	await _sleep(3.0)
	var round_seed := (flow.current as RunScene).run_seed
	await _shot("new_round")
	await _key(KEY_ESCAPE)
	await _sleep(0.6)
	await _key(KEY_2)
	await _sleep(0.5)
	await _shot("quit_round_warning")
	await _key(KEY_2)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "characters after quit"):
		return
	await _sleep(1.0)
	await _shot("characters_after_quit")
	await _click(flow.current.get("select_button") as Control)
	if not await _until(func() -> bool: return flow.current_name == "run", 10.0, "continued round"):
		return
	if (flow.current as RunScene).run_seed != round_seed:
		_fail("Continue changed the saved round seed")
		return
	await _sleep(1.0)
	await _shot("continued_round")
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	await _key(KEY_2)
	await _key(KEY_2)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "characters"):
		return
	await _click(flow.current.find_child("RunHistory", true, false) as Control)
	await _sleep(1.0)
	await _shot("history")
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	await _key(KEY_ESCAPE)
	if not await _until(func() -> bool: return flow.current_name == "title", 10.0, "title (back)"):
		return
	await _sleep(2.0)
	await _shot("title_again")
	_collect_missing(flow.current)
	snapshot["missing"] = Array(_missing)
	file = FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(snapshot, "\t"))
		file.close()
	if not _expect(_missing.is_empty(), "full scenario missing assets: %s" % _missing):
		return
	print("flow_driver: done (%d level-up windows answered, job dialog %s)" % [windows, job_seen])
	await _key(KEY_ESCAPE)
	await _sleep(2.0)
	get_tree().quit(1 if _failed else 0)


func _scenario_clear() -> void:
	var save_path := shots_dir.path_join("driver_save.json")
	var before := FileAccess.get_file_as_bytes(save_path) if FileAccess.file_exists(save_path) else PackedByteArray()
	if not await _until(func() -> bool: return flow.current_name == "run", 20.0, "run"):
		return
	var run := flow.current as RunScene
	if not await _until(func() -> bool: return run.world != null and run.world.state == RunWorld.CLEARED, 1800.0,
			"stage clear"):
		return
	# Keep a detached result before any await can let Flow dispose of this accelerated one-off scene.
	var summary := run.build_summary()
	Engine.time_scale = 1.0
	await _sleep(0.8)
	await _shot("clear_notice")
	if not await _until(func() -> bool: return flow.current_name == "results", 30.0, "results"):
		return
	await _sleep(3.5)
	await _shot("results_clear")
	await _click(flow.current.get("back_button") as Control)
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select"):
		return
	await _sleep(1.0)
	await _shot("characters_after_one_off_clear")
	var after := FileAccess.get_file_as_bytes(save_path) if FileAccess.file_exists(save_path) else PackedByteArray()
	if not _expect(before == after and flow.save.history.is_empty(), "one-off clear wrote persistent progress"):
		return
	if not _expect(_missing.is_empty(), "clear scenario missing assets: %s" % _missing):
		return
	summary["missing"] = Array(_missing)
	var file := FileAccess.open(shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	await _key(KEY_ESCAPE)
	await _until(func() -> bool: return flow.current_name == "title", 10.0, "title")
	await _sleep(2.0)
	await _key(KEY_ESCAPE)
	await _sleep(2.0)
	get_tree().quit(1 if _failed else 0)


## Keeps the real Start click while fixing only the boundary seed for reproducible keyboard steering.
func _start_selected(screen: Node) -> void:
	var button: WzButton = screen.get("start_button")
	button.pressed.disconnect(screen.start_selected)
	button.pressed.connect(func() -> void:
		# tier C: diagnostic training seed; --seed overrides it. Production map select still randomizes.
		flow.start_round(String(screen.stages[screen.selected].key), int(args.get("seed", "1"))))
	await _click(button)


func _create_character(character_name: String) -> bool:
	if not await _until(func() -> bool: return flow.current_name == "character_select", 10.0, "character select"):
		return false
	await _sleep(0.5)
	await _shot("character_select")
	await _click(flow.current.get("create_button") as Control)
	await _sleep(0.5)
	var creation: Control = flow.current.get("creation")
	await _shot("creation_gender")
	await _click(creation.get("create_button") as Control)
	await _shot("creation_name")
	await _click(creation.get("name_edit") as Control)
	await _type(character_name)
	await _click(creation.get("create_button") as Control)
	await _shot("creation_look")
	await _click(creation.get("create_button") as Control)
	return await _until(func() -> bool: return flow.current_name == "stage_select", 10.0, "map select")


func _scenario_title() -> void:
	if not await _until(func() -> bool: return flow.current_name == "title", 30.0, "title"):
		return
	await _sleep(9.0)
	await _shot("title")
	await _key(KEY_ESCAPE)
	await _sleep(2.0)
	get_tree().quit(1 if _failed else 0)


func _scenario_import() -> void:
	if not await _until(func() -> bool: return flow.current_name == "import", 20.0, "import screen"):
		return
	await _sleep(1.0)
	await _shot("import_screen")
	var wz := String(args.get("wz", ""))
	if wz == "":
		print("flow_driver: no --wz folder; import screen only")
		get_tree().quit(1 if _failed else 0)
		return
	var screen: Node = flow.current
	var edit := screen.get("path_edit") as LineEdit
	await _click(edit)
	edit.select_all()
	await _type(wz)
	await _sleep(0.3)
	await _shot("import_folder_typed")
	await _click(screen.get("import_button") as Control)
	await _sleep(0.5)
	await _shot("import_running")
	# The screen opens the title 0.8 s after a successful import and is freed then.
	var finished := func() -> bool: return not is_instance_valid(screen) or String(screen.get("state")) in ["done", "failed"]
	if not await _until(finished, 900.0, "importer"):
		return
	if is_instance_valid(screen):
		await _shot("import_" + String(screen.get("state")))
	if not await _until(func() -> bool: return flow.current_name == "title", 20.0, "title after import"):
		return
	await _sleep(9.0)
	await _shot("title_after_import")
	get_tree().quit(1 if _failed else 0)


# --- steering: BotInput's decision sent as key presses -----------------------------------------------------------

func _steer_run() -> void:
	var run := flow.current as RunScene
	if run == null or run.world == null or run.window != null or run.paused or run.world.state != RunWorld.PLAYING:
		return
	var mi := BotInput.decide(run.world, _memo)
	_set_key("left", mi.left)
	_set_key("right", mi.right)
	_set_key("up", mi.up)
	_set_key("down", mi.down)
	_set_key("jump", mi.jump_pressed)
	_set_key("drink_hp", mi.drink_hp)
	_set_key("drink_mp", mi.drink_mp)


func _set_key(action: String, down: bool) -> void:
	if bool(_held.get(action, false)) == down:
		return
	_held[action] = down
	_send_key(KEYS[action], down)


func _release_all() -> void:
	for a: String in KEYS:
		_set_key(a, false)


## The index of the card BotInput.pick_card_for would take.
func _card_index(run: RunScene, cards: Array) -> int:
	var id := BotInput.pick_card_for(run.world, cards)
	for i in cards.size():
		if String(cards[i].get("id", "")) == id:
			return i
	return 0


# --- input and capture helpers -----------------------------------------------------------------------------------

func _send_key(k: Key, down: bool, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.unicode = unicode
	e.pressed = down
	Input.parse_input_event(e)


func _key(k: Key) -> void:
	_send_key(k, true)
	await get_tree().process_frame
	await get_tree().process_frame
	_send_key(k, false)
	await get_tree().process_frame


func _hold(k: Key, seconds: float) -> void:
	_send_key(k, true)
	await _sleep(seconds)
	_send_key(k, false)
	await get_tree().process_frame


## Types `text` as key presses with unicode characters (into the focused LineEdit).
func _type(text: String) -> void:
	for i in text.length():
		var c := text.unicode_at(i)
		_send_key(KEY_NONE, true, c)
		await get_tree().process_frame
		_send_key(KEY_NONE, false, c)


## A left click at the centre of control `c` (moving the mouse there first).
func _click(c: Control) -> void:
	if c == null:
		_fail("click target missing")
		return
	await _click_at(c.get_global_rect().get_center())


## A left click at logical (viewport) position `p`; events carry window coordinates (the stretch transform applied).
func _click_at(p: Vector2) -> void:
	var w := get_tree().root.get_final_transform() * p
	var m := InputEventMouseMotion.new()
	m.position = w
	m.global_position = w
	Input.parse_input_event(m)
	await get_tree().process_frame
	await get_tree().process_frame
	for down: bool in [true, false]:
		var b := InputEventMouseButton.new()
		b.button_index = MOUSE_BUTTON_LEFT
		b.pressed = down
		b.position = w
		b.global_position = w
		Input.parse_input_event(b)
		await get_tree().process_frame


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _until(cond: Callable, timeout: float, what: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while not cond.call():
		if Time.get_ticks_msec() - t0 > int(timeout * 1000.0):
			_fail("timed out waiting for %s (current: %s)" % [what, flow.current_name])
			return false
		await get_tree().process_frame
	print("flow_driver: %s (%.1f s)" % [what, (Time.get_ticks_msec() - t0) / 1000.0])
	return true


func _shot(step: String) -> void:
	# The collaborative desktop may occlude the window; explicitly render this evidence frame.
	# tier C: let the existing modal input guard and 0.15s open transition finish before the next input/capture.
	await _sleep(0.35)
	await get_tree().process_frame
	RenderingServer.force_draw()
	_collect_missing(flow.current)
	_n += 1
	var path := shots_dir.path_join("%02d_%s.png" % [_n, step])
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path) if img != null else ERR_CANT_CREATE
	print("flow_driver: shot %s %s err=%d" % [path.get_file(), img.get_size() if img != null else Vector2i.ZERO, err])
	if err != OK:
		_failed = true
		push_error("flow_driver: could not save screenshot " + path)


## Retains misses before scene disposal, including renderer/UI lookups outside AssetLibrary.missing.
func _collect_missing(node: Node) -> void:
	if node == null:
		return
	if node is RunScene:
		for path: String in node.setup_missing:
			if not path in _missing:
				_missing.append(path)
	if node is WzImage and not node.has_art() and not node.path in _missing:
		_missing.append(node.path)
	if node is WzButton and not node.has_art() and not node.base_path in _missing:
		_missing.append(node.base_path)
	if node.has_method("missing_paths"):
		for path: String in node.call("missing_paths"):
			if not path in _missing:
				_missing.append(path)
	for property: Dictionary in node.get_property_list():
		if property.name == "missing":
			for item: Variant in node.get("missing"):
				var path := "Mob.wz/%07d.img" % int(item) if node is MobRenderer else String(item)
				if not path in _missing:
					_missing.append(path)
	for child: Node in node.get_children():
		_collect_missing(child)
	for path: String in AssetLibrary.get_default().missing:
		if not path in _missing:
			_missing.append(path)


func _fail(msg: String) -> void:
	_failed = true
	push_error("flow_driver: " + msg)
	print("flow_driver: FAILED " + msg)
	await _shot("failed")
	get_tree().quit(1)
