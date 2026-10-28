class_name SceneFlow
extends Node
## Round coordinator (autoload Flow): title -> character_select -> the character's Free Market (home) -> Up at out00 ->
## map select -> round -> results -> the Free Market again (ADR 0006, #286). Every round is standalone: a clear, a death or
## a Quit round ends it, and nothing but the character (its pickups and unlocked tiers) carries to the next.
## host owns exactly one screen. Swaps are deferred so callbacks may replace their screen safely.
##
## #70 seam: character_select.gd/.tscn is a separate presentation. Use create_character(name, look, job),
## continue_character(slot), delete_character(slot) AFTER confirmation, and goto_history(). Creation returns its
## slot or -1 with action_error; it creates a Lv1-less character of a playable job (the sim's defaults) and opens its hub.
## Shared #70/#71 drawing: DataRepo.character_look(snapshot.character, DataRepo.load_all()) -> AvatarRenderer look,
## the carried look with the character's worn equipment. Creation turns the chosen outfit and the job's creation weapon
## into worn equipment (new_character). Only snapshot.character.look is authoritative.
##
## SaveData format 3 slots are {name, created, rounds_played, character}: no phase, tier cursor, stage or seed. The
## character is saved at the hub (the Free Market writes each change) and when a round ends; `start_round` writes nothing,
## so closing the game mid-round loses the round and there is nothing to resume.
## finish_run(summary, character, ending) is the ONE exit of a persistent round. RunScene hands over the character as the
## round left it (RunWorld.character_snapshot(): pickups kept, the next tier unlocked after a clear) for a clear, a death
## and a quit alike; `ending` "" means cleared/died by the summary, "quit" is Quit round, which ends the round exactly
## like a death. SaveData.finish_round writes slot, best, count, NX and one history entry together; the results screen
## then returns to the hub (to_hub).
##
## start_run(stage, seed, options) is ONLY a tool one-off (--run), clears active_slot and never reads/writes saves.
## options.character also accepts the existing --character=<absolute JSON path>. The CLI parser passes other
## --key[=value] flags to RunScene unchanged. finish_run shows one-off results without bests or history.
## Summary: {stage, map_id, region, continent (the display names, #221; older saves lack them), map_name, street_name, time, duration, cleared, level, job_id, job_name, kills,
## damage_dealt, skills: [{key, name, icon, rank}], seed, bosses_killed, levels_gained, nx_awarded}; persistent rounds
## add ending. nx_awarded (NxAward, tier C) is credited to the save's account only for persistent rounds, in the
## finish_round write. One-off rounds and deletion never credit it.
## Cash Shop (#118 seam for #122/#126): goto_cash_shop(origin) opens the v83 shop as the active character from the
## boundary screen it names ("stage_select" or "free_market"; no-op without a living character) and leave_cash_shop()
## returns to that origin. Purchases are CashShop.buy on save_data().
## start_hub(request) is the tool-only `--hub` (HubTestKit): a throwaway save, a test kit and the real Free Market.
## Tests may inject save/host and set deferred_swaps=false. The autoload does nothing until explicitly called.

## Emitted after a scene swap (title, character_select, history, free_market, stage_select, run, results, import, error).
signal scene_changed(scene_name: String)

const CHARACTER_SELECT := "res://scenes/ui/character_select.tscn"
const TITLE := "res://scenes/ui/title_screen.tscn"
const STAGE_SELECT := "res://scenes/ui/stage_select.tscn"
const RESULTS := "res://scenes/ui/results_screen.tscn"
const IMPORT := "res://scenes/ui/import_screen.tscn"
const RUN := "res://scenes/run/run_scene.tscn"
const FREE_MARKET := "res://scenes/run/free_market.tscn"
const CASH_SHOP := "res://scenes/ui/cash_shop.tscn"
## Run option names for the command-line flags (others pass through with "-" -> "_").
const FLAG_OPTIONS := {"shots": "shots_dir", "shot-every": "shot_every", "quit-after": "quit_after",
	"branch": "job"} # --branch is the deprecated alias of --job (parse_run_args prints a note)
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
## Local saves; created on first persistent/menu use (tests may assign their own).
var save: SaveData
## The Settings that persistent rounds take their HP ALERT level from and follow live (spec #34, #121); null =
## the Settings autoload when this node is in the tree (tests may assign their own).
var settings: GameSettings
## Living character slot, or -1 for tools and ended runs.
var active_slot := -1
## User-facing validation or persistence error from the last character action.
var action_error := ""
var last_stage := ""
## The `--autoplay` option of this session: persistent rounds resumed from the flow play with the bot, and the Free Market
## runs the bot's shop visit on entry (spec #33, #112).
var autoplay := false
## True in a tool-only `--hub` session: the Free Market puts the character beside the scroll NPCs (start_hub).
var hub_tool := false
var last_summary: Dictionary = {}
var last_new_best := false
var _lease_timer: Timer


func _ready() -> void:
	_lease_timer = Timer.new()
	_lease_timer.wait_time = SaveData.WriterLock.RENEW_SECONDS
	_lease_timer.ignore_time_scale = true
	_lease_timer.process_mode = Node.PROCESS_MODE_ALWAYS
	_lease_timer.timeout.connect(_renew_save_lease)
	add_child(_lease_timer)
	_lease_timer.start()


func _exit_tree() -> void:
	if save != null:
		save.release_writer()


func _renew_save_lease() -> void:
	if save != null and save.renew_writer() != OK and not current is SaveBusyScreen:
		active_slot = -1
		_show_save_busy()


func _show_save_busy() -> void:
	var message := "Save open in another window. Close it, or wait 30 seconds if it stopped, then try again."
	if save.writer_error != ERR_ALREADY_IN_USE:
		message = "Could not renew the save lock. Check your save folder, then try again."
	_swap_to(SaveBusyScreen.new(self, message), "error")


## Shows the title screen.
func goto_title() -> void:
	_swap_to(_instance(TITLE), "title")


## Shows the three living character slots. No round progress is saved here.
func goto_character_select() -> void:
	active_slot = -1
	# Retrying after closing the other window must load fresh state, never promote this session's stale view.
	if save != null and save.writer_error != OK:
		save = save.reopen()
	if save_data().writer_error != OK:
		_show_save_busy()
		return
	var screen := _instance(CHARACTER_SELECT)
	screen.configure(self)
	_swap_to(screen, "character_select")


## Opens ended-run history through a small replaceable character-screen entry point (#70).
func goto_history() -> void:
	var screen := _instance(CHARACTER_SELECT)
	screen.configure(self, true)
	_swap_to(screen, "history")


## Deletes a confirmed character, archiving it in the history as deleted.
func delete_character(index: int) -> bool:
	if save_data().delete_slot(index, _date()) != OK:
		action_error = "Could not delete the character. Check that the save folder is writable."
		return false
	goto_character_select()
	return true


## Creates a character of playable job `job` (0 = the default job) and opens its Free Market; -1 with action_error on
## failure. `look` is the creation look ({skin, face, hair, equips: [top, bottom, shoes]}).
func create_character(character_name: String, look: Dictionary = {}, job: int = 0) -> int:
	action_error = save_data().name_error(character_name)
	if not action_error.is_empty():
		return -1
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))
	var job_id := jobs.default_job() if job == 0 else job
	action_error = jobs.job_error(job_id)
	if not action_error.is_empty():
		return -1
	var character := new_character(look, job_id, equipment_info_loader())
	var snapshot := {"name": character_name, "created": _date(), "rounds_played": 0, "character": character}
	var index := save_data().create_slot(snapshot)
	action_error = "" if index >= 0 else "Use a unique name of 4-12 letters and digits and an empty slot. Check that the save folder is writable."
	if index >= 0:
		active_slot = index
		_open_free_market(snapshot)
	return index


## A fresh character of job `job_id` (the sim's defaults) wearing the creation choices: `look` {skin, face, hair, equips:
## [top, bottom, shoes]} and the job's creation weapon (JobTree.creation_weapon) become worn equipment with plain WZ stats
## from `img_loader` (path -> img root, {} when absent); an empty look wears Equipment.DEFAULT_OUTFIT. Tier 1 is unlocked.
static func new_character(look: Dictionary, job_id: int, img_loader: Callable) -> Dictionary:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))
	var ids: Array = look.get("equips", []).duplicate() if look.get("equips") is Array else []
	if ids.is_empty():
		ids = Equipment.DEFAULT_OUTFIT.filter(func(id: int) -> bool: return Equipment.slot_of(id) != "weapon")
	ids.append(jobs.creation_weapon(job_id))
	var infos := DataRepo.equipment_info(PackedInt32Array(ids), img_loader)
	var character := RunWorld.new({"data": data, "equipment_info": infos, "job": job_id}).character_snapshot()
	character.look = look.duplicate(true)
	character.look.erase("equips")
	character.equipment.worn = Equipment.worn_from_ids(ids, infos)
	return character


## A format-3 copy of a stored character, idempotent: older formats (tool files, fixtures) keep what format 3 keeps, with
## item info from `img_loader` for the items a format-1 file migrates (as new_character).
static func migrated_character(character: Dictionary, img_loader: Callable) -> Dictionary:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))
	if int(character.get("format", 0)) == CharacterSnapshot.FORMAT:
		return CharacterSnapshot.migrate(character, jobs, {})
	var ids := PackedInt32Array(CharacterSnapshot.held_item_ids(character, jobs))
	return CharacterSnapshot.migrate(character, jobs, DataRepo.equipment_info(ids, img_loader))


## An img loader over `lib` (default: the default asset library) for img roots such as item info (empty roots without
## a cache: items then carry no stats).
static func equipment_info_loader(lib: AssetLibrary = null) -> Callable:
	var library := lib if lib != null else AssetLibrary.get_default()
	return func(path: String) -> Dictionary:
		var img: WzImg = library.img(path) if library != null else null
		return img.root if img != null else {}


## Shows map select for the active character: every stage of the tiers it has unlocked (the next tier is shown locked).
func goto_stage_select() -> void:
	var snapshot := save_data().slot(active_slot)
	if snapshot.is_empty():
		return
	var screen := _instance(STAGE_SELECT)
	screen.configure(snapshot, self)
	_swap_to(screen, "stage_select")


## Opens the active character's Free Market (home), with an optional arrival notice.
func goto_free_market(notice: String = "") -> void:
	var snapshot := save_data().slot(active_slot)
	if snapshot.is_empty():
		goto_character_select()
		return
	_open_free_market(snapshot, notice)


## Opens the Cash Shop for the active character; `origin` ("stage_select" or "free_market") is where Leave returns.
func goto_cash_shop(origin: String) -> void:
	var snapshot := save_data().slot(active_slot)
	if snapshot.is_empty() or origin not in ["stage_select", "free_market"]:
		return
	var screen := _instance(CASH_SHOP)
	screen.configure(snapshot, self, origin)
	_swap_to(screen, "cash_shop")


## Leaves the Cash Shop for the screen it was opened from (map select unless it was opened from the Free Market).
func leave_cash_shop(origin: String) -> void:
	var snapshot := save_data().slot(active_slot)
	if snapshot.is_empty():
		goto_character_select()
	elif origin == "free_market":
		_open_free_market(snapshot)
	else:
		goto_stage_select()


## Ordered stage keys per tier, from survivor data; works for any number of tiers.
static func tiers() -> Array:
	return DataRepo.load_all().get("stages", {}).get("tiers", [])


## The stage keys a character with `tiers_unlocked` tiers may start, in tier order (tier 1 is always unlocked).
static func unlocked_stages(tiers_unlocked: int) -> Array:
	var out := []
	var ordered := tiers()
	for tier in mini(maxi(1, tiers_unlocked), ordered.size()):
		out.append_array(ordered[tier])
	return out


static func _date() -> String:
	return Time.get_datetime_string_from_system(true)


## Shows the importer screen.
func goto_import() -> void:
	_swap_to(_instance(IMPORT), "import")


## Starts a tool-only one-off round; does not read or write any save state.
func start_run(stage_key: String, p_seed: int = -1, options: Dictionary = {}) -> void:
	stage_key = DataRepo.canonical_stage_key(stage_key)
	active_slot = -1
	autoplay = RunScene.option_flag(options, "autoplay")
	_launch_round(stage_key, p_seed, options)


## Tool-only `--hub` (HubTestKit): opens the Free Market with a test character. `request` is HubTestKit.parse_args'
## {character, mesos}. The character (plus the test kit) goes into slot 0 of a throwaway save at `save_path`, recreated
## now, and is continued as in real play; user://save.json is never read or written.
func start_hub(request: Dictionary, save_path: String = HubTestKit.SAVE_PATH) -> void:
	var loaded := HubTestKit.load_character(String(request.get("character", HubTestKit.DEFAULT_CHARACTER)),
		equipment_info_loader())
	if not String(loaded.error).is_empty():
		_swap_to(error_screen("--hub: " + String(loaded.error)), "error")
		return
	hub_tool = true
	save = HubTestKit.fresh_save(save_path)
	var character := HubTestKit.apply(loaded.character, int(request.get("mesos", HubTestKit.DEFAULT_MESOS)),
		equipment_info_loader())
	var snapshot := {"name": HubTestKit.CHARACTER_NAME, "created": _date(), "character": character,
		"rounds_played": 1}
	var index := save.create_slot(snapshot)
	if index < 0:
		_swap_to(error_screen("--hub: the test character could not be saved to %s." % save_path), "error")
		return
	continue_character(index)


## Starts a persistent round of the active character on a stage of an unlocked tier. Writes nothing: the round exists only
## while it is played. Ignores a stage the character has not unlocked.
func start_round(stage_key: String, p_seed: int = -1) -> void:
	stage_key = DataRepo.canonical_stage_key(stage_key)
	var snapshot := save_data().slot(active_slot)
	if snapshot.is_empty() or stage_key not in unlocked_stages(int(snapshot.character.tiers_unlocked)):
		return
	var live := _live_settings()
	# The account's owned cash items decide which of the character's worn cash equipment and pet count (spec #34).
	var options := {"character": snapshot.character, "name": snapshot.name, "account": save_data().account}
	if live != null:
		options["settings_alert"] = live.alert_levels()
	if autoplay:
		options["autoplay"] = true
	_launch_round(stage_key, make_seed() if p_seed < 0 else p_seed, options, live)


## Opens a living character's Free Market: its home between rounds.
func continue_character(index: int) -> void:
	var snapshot := save_data().slot(index)
	if snapshot.is_empty():
		return
	active_slot = index
	_open_free_market(snapshot)


## Saves the character, then returns to the character slots (the hub's Save & quit).
func save_and_quit() -> void:
	var snapshot := save_data().slot(active_slot)
	if not snapshot.is_empty() and save_data().update_slot(active_slot, snapshot) != OK:
		_swap_to(error_screen("Could not save the character."), "error")
		return
	goto_character_select()


func _live_settings() -> GameSettings:
	if settings != null:
		return settings
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Settings") as GameSettings


func _launch_round(stage_key: String, p_seed: int, options: Dictionary, live: GameSettings = null) -> void:
	stage_key = DataRepo.canonical_stage_key(stage_key)
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
	if live != null and run is RunScene:
		(run as RunScene).settings = live
	_swap_to(run, "run")


## Ends a round. A persistent one (an active character) needs the character as the round left it (RunWorld.character_snapshot)
## and saves it with the round's result; `ending` is "" for cleared/died by the summary or "quit" (Quit round, handled
## exactly like a death). One-off rounds never access SaveData.
func finish_run(summary: Dictionary, character: Dictionary = {}, ending: String = "") -> void:
	last_summary = summary.duplicate(true)
	last_stage = DataRepo.canonical_stage_key(String(summary.get("stage", last_stage)))
	if last_summary.has("stage"):
		last_summary.stage = last_stage
	var before := {}
	last_new_best = false
	if active_slot >= 0:
		var sd := save_data()
		var snapshot := sd.slot(active_slot)
		if snapshot.is_empty() or not CharacterSnapshot.validation_error(character).is_empty():
			_swap_to(error_screen("Missing final character at the round boundary."), "error")
			return
		before = sd.best_for(last_stage).duplicate(true)
		snapshot.character = character.duplicate(true)
		snapshot.rounds_played = int(snapshot.rounds_played) + 1
		if ending.is_empty():
			ending = "cleared" if bool(summary.get("cleared", false)) else "died"
		if sd.finish_round(active_slot, snapshot, ending, _date(), last_summary) != OK:
			_swap_to(error_screen("Could not save the end of the round."), "error")
			return
		last_new_best = SaveData.is_better(SaveData.record_from(summary), before)
		last_summary["ending"] = ending
	var results := _instance(RESULTS)
	if results != null and results.has_method("configure"):
		results.configure(last_summary, last_new_best, before, self)
	_swap_to(results, "results")


## The Free Market arrival notice after a round: the NX it paid ("" when none).
static func nx_notice(summary: Dictionary) -> String:
	var nx := int(summary.get("nx_awarded", 0))
	return "You have gained %d NX." % nx if nx > 0 else ""


func _open_free_market(snapshot: Dictionary, notice: String = "") -> void:
	var screen := _instance(FREE_MARKET)
	var options := {"autoplay": autoplay}
	if hub_tool:
		options["spawn_x"] = HubTestKit.spawn_x(DataRepo.load_all().get("shops", {}))
	screen.configure(snapshot, self, options, notice)
	_swap_to(screen, "free_market")


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
	for key: String in ["stage", "run"]:
		if out.has(key):
			out[key] = DataRepo.canonical_stage_key(String(out[key]))
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
		if k == "branch":
			printerr("--branch is deprecated: use --job=<id>")
		if key in BOOL_OPTIONS:
			options[key] = v != "0" and v.to_lower() != "false"
		elif key in INT_OPTIONS:
			options[key] = int(v)
		elif key == "job":
			JobTree.put_job(options, v) # --job=<id>: the tool character's job (#284)
		elif key in FLOAT_OPTIONS:
			options[key] = float(v)
		elif key == "perf":
			options[key] = int(v) if v.is_valid_int() and v != "1" else true
		else:
			options[key] = v
	return {"run": String(flags.run), "seed": seed_v, "options": options}


## Why the run options' `--job=<id>` (the tool character's job, #284) cannot be played ("" when none is named or it
## can): not a whole job id (the old `<id>:<path>` form included), unknown, or not playable in this build.
static func forced_job_error(options: Dictionary, data: Dictionary) -> String:
	if not options.has("job"):
		return ""
	var job_id := int(options.job)
	if job_id < 0:
		return "'%s' is not a job id" % String(options.get("job_text", options.job))
	return JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {})).job_error(job_id)


## A minimal screen with an error message and a way back to the title (used when the run scene is missing).
static func error_screen(message: String) -> Control:
	return ErrorScreen.new(message)


## Persistent-save refusal uses the existing v83 Notice art and login backdrop; OK/Esc returns to the title.
class SaveBusyScreen extends Control:
	var message := ""
	var flow: SceneFlow
	var notice: ShopNotice

	func _init(p_flow: SceneFlow, p_message: String) -> void:
		flow = p_flow
		message = p_message
		name = "SaveBusy"
		set_anchors_preset(Control.PRESET_FULL_RECT)

	func _ready() -> void:
		add_child(LoginBackdrop.new(LoginBackdrop.CHAR_SELECT))
		notice = ShopNotice.new(message)
		notice.close_requested.connect(flow.goto_title)
		add_child(notice)
		resized.connect(_place_notice)
		_place_notice()

	func _place_notice() -> void:
		if notice != null:
			notice.position = ((size - notice.size) * 0.5).floor()

	func _unhandled_input(event: InputEvent) -> void:
		if MapleWindow.is_cancel(event) or MapleWindow.is_confirm(event):
			flow.goto_title()
			get_viewport().set_input_as_handled()


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
