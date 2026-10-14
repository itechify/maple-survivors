class_name SceneFlow
extends Node
## Scene flow between the menus and the run (autoload "Flow"; docs/ARCHITECTURE.md 4.1):
## main -> ImportScreen (no cache) -> TitleScreen -> StageSelect -> RunScene -> ResultsScreen -> StageSelect / retry.
##
## The flow swaps the single child of its `host` (main.tscn's root registers itself); without a host it swaps the
## tree's current scene. Swaps are deferred by default so a screen may call the flow from its own button callback.
##
##   Flow.goto_title()  Flow.goto_stage_select()  Flow.goto_import()
##   Flow.start_run("henesys_hg1")                # seed -1 = a random seed; options -> RunScene.configure()
##   Flow.finish_run(summary)                     # called by the RunScene: records the best result, shows results
##
## Summary (from the RunScene): {stage, map_id, map_name, street_name, time, duration, cleared, level, job_id,
## job_name, kills, damage_dealt, skills: [{key, name, icon, rank}], seed}.
##
## Command line (main.gd): `--run=<stage>` starts that stage straight away; `--seed=N --autoplay --autopick --speed=N
## --shots=<dir> --shot-every=<s> --quit-after=<s> --perf[=N] --warp=<s> --window-autopick=<s>` (and any other
## `--key[=value]`) become the run options (RunScene.configure).
## The autoload does nothing on its own: `_ready` is empty, so test runs and other scenes are unaffected.

## Emitted after a scene was swapped in ("title", "stage_select", "run", "results", "import", "error").
signal scene_changed(scene_name: String)

const TITLE := "res://scenes/ui/title_screen.tscn"
const STAGE_SELECT := "res://scenes/ui/stage_select.tscn"
const RESULTS := "res://scenes/ui/results_screen.tscn"
const IMPORT := "res://scenes/ui/import_screen.tscn"
const RUN := "res://scenes/run/run_scene.tscn"
## Run option names for the command-line flags (others pass through with "-" -> "_").
const FLAG_OPTIONS := {"shots": "shots_dir", "shot-every": "shot_every", "quit-after": "quit_after"}
const BOOL_OPTIONS := ["autoplay", "autopick"]
const INT_OPTIONS := ["speed"]
const FLOAT_OPTIONS := ["shot_every", "quit_after", "warp", "window_autopick"]

## Node whose single child is the current screen (main.tscn); null = the tree's current scene.
var host: Node
## The screen shown now.
var current: Node
## Name of the screen shown now.
var current_name := ""
## Swap on the next idle frame (true) or at once (tests).
var deferred_swaps := true
## Best results; created on first use (tests may assign their own).
var save: SaveData
## Last run: its stage key and summary, and whether it was a new best.
var last_stage := ""
var last_summary: Dictionary = {}
var last_new_best := false


## Shows the title screen.
func goto_title() -> void:
	_swap_to(_instance(TITLE), "title")


## Shows the stage select.
func goto_stage_select() -> void:
	_swap_to(_instance(STAGE_SELECT), "stage_select")


## Shows the importer screen.
func goto_import() -> void:
	_swap_to(_instance(IMPORT), "import")


## Starts a run of `stage_key` (seed -1 = random). The RunScene gets configure(stage_key, seed, options) before it
## enters the tree. Without the run scene an error screen is shown instead.
func start_run(stage_key: String, p_seed: int = -1, options: Dictionary = {}) -> void:
	last_stage = stage_key
	if p_seed < 0:
		p_seed = make_seed()
	if not ResourceLoader.exists(RUN):
		_swap_to(error_screen("The run scene is missing (%s)." % RUN), "error")
		return
	var packed := load(RUN) as PackedScene
	var run: Node = packed.instantiate() if packed != null else null
	if run == null:
		_swap_to(error_screen("The run scene could not be loaded (%s)." % RUN), "error")
		return
	if run.has_method("configure"):
		run.configure(stage_key, p_seed, options)
	_swap_to(run, "run")


## Ends a run: records it (SaveData best result) and shows the results.
func finish_run(summary: Dictionary) -> void:
	last_summary = summary.duplicate(true)
	last_stage = String(summary.get("stage", last_stage))
	var sd := save_data()
	var before := sd.best_for(last_stage).duplicate()
	last_new_best = sd.record(summary)
	var results := _instance(RESULTS)
	if results != null and results.has_method("configure"):
		results.configure(last_summary, last_new_best, before)
	_swap_to(results, "results")


## The save file (user://save.json unless a test assigned another).
func save_data() -> SaveData:
	if save == null:
		save = SaveData.new()
	return save


## A random run seed (0..2^31-1).
static func make_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randi() & 0x7FFFFFFF


## "--key=value" / "--flag" user args as a Dictionary (flags map to "1").
static func parse_flags(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if not a.begins_with("--"):
			continue
		var s := a.substr(2)
		var i := s.find("=")
		if i < 0:
			out[s] = "1"
		else:
			out[s.substr(0, i)] = s.substr(i + 1)
	return out


## The run request in the command line: {} without `--run`, else {"run": stage, "seed": int (-1 = random),
## "options": {autoplay, autopick, speed, shots_dir, shot_every, quit_after, perf, ...}}.
static func parse_run_args(list: PackedStringArray) -> Dictionary:
	var flags := parse_flags(list)
	if not flags.has("run") or String(flags.run) == "" or String(flags.run) == "1":
		return {}
	var seed_v := -1
	if flags.has("seed") and String(flags.seed).is_valid_int():
		seed_v = int(flags.seed)
	var options := {}
	for k: String in flags:
		if k == "run" or k == "seed":
			continue
		var key: String = FLAG_OPTIONS.get(k, k.replace("-", "_"))
		var v: String = flags[k]
		if key in BOOL_OPTIONS:
			options[key] = v != "0" and v.to_lower() != "false"
		elif key in INT_OPTIONS:
			options[key] = int(v)
		elif key in FLOAT_OPTIONS:
			options[key] = float(v)
		elif key == "perf":
			options[key] = int(v) if v.is_valid_int() and v != "1" else true
		else:
			options[key] = v
	return {"run": String(flags.run), "seed": seed_v, "options": options}


## A minimal screen with an error message and a way back to the title (used when the run scene is missing).
static func error_screen(message: String) -> Control:
	return ErrorScreen.new(message)


## Black screen with a centred message; Esc or a click returns to the title.
class ErrorScreen extends Control:
	var message := ""

	func _init(p_message: String = "") -> void:
		message = p_message
		name = "FlowError"
		set_anchors_preset(Control.PRESET_FULL_RECT)
		var bg := ColorRect.new()
		bg.color = Color(0, 0, 0)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		var label := MapleText.new(message + "

Press Esc or click to return to the title.", MapleText.SIZE,
			MapleText.WHITE, true)
		label.name = "Message"
		label.set_anchors_preset(Control.PRESET_FULL_RECT)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD
		add_child(label)

	func _gui_input(e: InputEvent) -> void:
		if e is InputEventMouseButton and (e as InputEventMouseButton).pressed:
			_back()

	func _unhandled_input(e: InputEvent) -> void:
		if MapleWindow.is_cancel(e):
			_back()

	func _back() -> void:
		var flow := get_node_or_null("/root/Flow") as SceneFlow
		if flow != null:
			flow.goto_title()


func _instance(path: String) -> Node:
	if not ResourceLoader.exists(path):
		return error_screen("Missing scene %s." % path)
	var packed := load(path) as PackedScene
	return packed.instantiate() if packed != null else error_screen("Cannot load %s." % path)


func _swap_to(scene: Node, scene_name: String) -> void:
	if scene == null:
		return
	if deferred_swaps:
		_swap_now.call_deferred(scene, scene_name)
	else:
		_swap_now(scene, scene_name)


func _swap_now(scene: Node, scene_name: String) -> void:
	var parent: Node = host
	var tree := get_tree() if is_inside_tree() else (Engine.get_main_loop() as SceneTree)
	if parent == null or not is_instance_valid(parent):
		parent = tree.root if tree != null else null
	if parent == null:
		scene.free()
		return
	var old: Node = current
	if host == null and tree != null and tree.current_scene != null:
		old = tree.current_scene
	if old != null and is_instance_valid(old) and old != scene:
		if old.get_parent() != null:
			old.get_parent().remove_child(old)
		old.queue_free()
	current = scene
	current_name = scene_name
	parent.add_child(scene)
	if host == null and tree != null:
		tree.current_scene = scene
	scene_changed.emit(scene_name)
