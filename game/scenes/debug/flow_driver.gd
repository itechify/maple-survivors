extends Node
## Plays the real game (main.tscn under this node: the Flow autoload, every screen and the RunScene) by injecting
## keyboard and mouse events through Input.parse_input_event, exactly like a player, and saves a screenshot of every
## step. A smoke test of the whole flow and the evidence for docs/IMPLEMENTATION_PLAN.md acceptance checks.
##
##   bash scripts/godot.sh --path game res://scenes/debug/flow_driver.tscn -- --scenario=full --shots=C:/abs/dir
##
## Scenarios (--scenario=):
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
		"clear":
			_scenario_clear()
		"import":
			_scenario_import()
		"title":
			_scenario_title()
		_:
			_scenario_full()


func _process(_delta: float) -> void:
	if _steer:
		_steer_run()


# --- scenarios ---------------------------------------------------------------------------------------------------

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
	await _click(flow.current.find_child("Continue0", true, false) as Control)
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
	flow.goto_history()
	await _sleep(1.0)
	await _shot("history")
	await _key(KEY_ESCAPE)
	await _sleep(0.5)
	await _key(KEY_ESCAPE)
	if not await _until(func() -> bool: return flow.current_name == "title", 10.0, "title (back)"):
		return
	await _sleep(2.0)
	await _shot("title_again")
	print("flow_driver: done (%d level-up windows answered, job dialog %s)" % [windows, job_seen])
	await _key(KEY_ESCAPE)
	await _sleep(2.0)
	get_tree().quit(1 if _failed else 0)


func _scenario_clear() -> void:
	if not await _until(func() -> bool: return flow.current_name == "run", 20.0, "run"):
		return
	var run := flow.current as RunScene
	if not await _until(func() -> bool: return run.world != null and run.world.state == RunWorld.CLEARED, 1800.0,
			"stage clear"):
		return
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
	await _click(creation.get("name_edit") as Control)
	await _type(character_name)
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
	await get_tree().process_frame
	RenderingServer.force_draw()
	_n += 1
	var path := shots_dir.path_join("%02d_%s.png" % [_n, step])
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path) if img != null else ERR_CANT_CREATE
	print("flow_driver: shot %s %s err=%d" % [path.get_file(), img.get_size() if img != null else Vector2i.ZERO, err])


func _fail(msg: String) -> void:
	_failed = true
	push_error("flow_driver: " + msg)
	print("flow_driver: FAILED " + msg)
	await _shot("failed")
	get_tree().quit(1)
