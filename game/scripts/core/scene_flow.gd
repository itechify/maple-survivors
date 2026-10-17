class_name SceneFlow
extends Node
## Run-of-rounds coordinator (autoload Flow): title -> character_select -> tiered stage_select -> round.
## A non-final clear carries the character to the next tier; death/victory -> results -> character_select.
## host owns exactly one screen. Swaps are deferred so callbacks may replace their screen safely.
##
## #70 seam: character_select.gd/.tscn is a separate presentation. Use create_character(name, look, weapon),
## continue_character(slot), delete_character(slot) AFTER confirmation, and goto_history(). Creation returns its
## slot or -1 with action_error; it creates a Beginner via the same sim defaults as any fresh round.
## Shared #70/#71 drawing: DataRepo.character_look(snapshot.character, DataRepo.load_all()) -> AvatarRenderer look,
## the carried look with the character's worn equipment. Creation turns the chosen outfit and weapon into worn
## equipment (new_character); continue_character migrates a format-1 character once (migrated_character).
## Only snapshot.character.look is authoritative; the old wrapper look is accepted for compatibility and ignored.
## EVERY persistent non-final clear calls _after_round_cleared(snapshot), which saves free_market before arrival.
## Continue resumes that phase; the hub's out00 calls goto_stage_select(). No other clear route exists.
##
## SaveData format 2 slots hold the boundary character, tier (0-based), phase=free_market|map_select|round, stage and round_seed.
## start_round(stage) persists phase=round and a seed BEFORE launch; continue_character restarts it unchanged.
## quit_round never writes. save_and_quit returns the hub/map select to the slots. RunScene passes finish_run(summary,
## character) with an outgoing character only for persistent clears; deaths use the last saved boundary for history.
## A carried Dictionary reaches RunScene.configure via options.character.
##
## start_run(stage, seed, options) is ONLY a tool one-off (--run), clears active_slot and never reads/writes saves.
## options.character also accepts the existing --character=<absolute JSON path>. The CLI parser passes other
## --key[=value] flags to RunScene unchanged. finish_run shows one-off results without bests or history.
## Summary: {stage, map_id, map_name, street_name, time, duration, cleared, level, job_id, job_name, kills,
## damage_dealt, skills: [{key, name, icon, rank}], seed, bosses_killed, levels_gained, nx_awarded}; persistent endings
## add ending and tiers_cleared. nx_awarded (NxAward, tier C) is credited to the save's account only for persistent
## rounds: in the boundary write of a non-final clear, or the end_run write of a death/victory. One-off rounds,
## Quit round and deletion never credit it.
## Cash Shop (#118 seam for #122/#126): goto_cash_shop(origin) opens the v83 shop as the active character from the
## boundary screen it names ("stage_select" or "free_market"; no-op without a living character) and leave_cash_shop()
## returns to that origin. The saved boundary phase is untouched while shopping. Purchases are CashShop.buy on save_data().
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
## Local saves; created on first persistent/menu use (tests may assign their own).
var save: SaveData
## The Settings that persistent rounds take their HP / MP ALERT levels from and follow live (spec #34, #121); null =
## the Settings autoload when this node is in the tree (tests may assign their own).
var settings: GameSettings
## Living character slot, or -1 for tools and ended runs.
var active_slot := -1
## User-facing validation or persistence error from the last character action.
var action_error := ""
var last_stage := ""
var last_summary: Dictionary = {}
var last_new_best := false


## Shows the title screen.
func goto_title() -> void:
	_swap_to(_instance(TITLE), "title")


## Shows the three living character slots. No round progress is saved here.
func goto_character_select() -> void:
	active_slot = -1
	var screen := _instance(CHARACTER_SELECT)
	screen.configure(self)
	_swap_to(screen, "character_select")


## Opens ended-run history through a small replaceable character-screen entry point (#70).
func goto_history() -> void:
	var screen := _instance(CHARACTER_SELECT)
	screen.configure(self, true)
	_swap_to(screen, "history")


## Deletes a confirmed character, archiving its last boundary as deleted.
func delete_character(index: int) -> bool:
	if save_data().end_run(index, "deleted", _date()) != OK:
		action_error = "Could not delete the character. Check that the save folder is writable."
		return false
	goto_character_select()
	return true


## Creates a fresh Beginner and enters its first map select; -1 with action_error on failure.
## #70 supplies look/weapon here without changing the round flow.
func create_character(character_name: String, look: Dictionary = {}, beginner_weapon: int = 0) -> int:
	action_error = save_data().name_error(character_name)
	if not action_error.is_empty():
		return -1
	var character := new_character(look, beginner_weapon, equipment_info_loader())
	var snapshot := {"name": character_name, "created": _date(),
		"character": character, "tier": 0, "phase": "map_select", "rounds_played": 0, "tiers_cleared": 0}
	var index := save_data().create_slot(snapshot)
	action_error = "" if index >= 0 else "Use a unique name of 4-12 letters and digits and an empty slot. Check that the save folder is writable."
	if index >= 0:
		active_slot = index
		goto_stage_select()
	return index


## A fresh Beginner snapshot (the sim's defaults) wearing the creation choices: `look` {skin, face, hair, equips:
## [top, bottom, shoes]} and `weapon` (0 = the default creation weapon) become worn equipment with plain WZ stats from
## `img_loader` (path -> img root, {} when absent); an empty look wears Equipment.DEFAULT_OUTFIT.
static func new_character(look: Dictionary, weapon: int, img_loader: Callable) -> Dictionary:
	var data := DataRepo.load_all()
	var ids: Array = look.get("equips", []).duplicate() if look.get("equips") is Array else []
	if ids.is_empty():
		ids = Equipment.DEFAULT_OUTFIT.filter(func(id: int) -> bool: return Equipment.slot_of(id) != "weapon")
	ids.append(weapon if weapon > 0 else Equipment.DEFAULT_OUTFIT[-1])
	var infos := DataRepo.equipment_info(PackedInt32Array(ids), img_loader)
	var character := RunWorld.new({"data": data, "equipment_info": infos}).character_snapshot()
	character.look = look.duplicate(true)
	character.look.erase("equips")
	character.equipment.worn = Equipment.worn_from_ids(ids, infos)
	return character


## A format-2 copy of a stored character: format 1 migrates with item info from `img_loader` (as new_character).
static func migrated_character(character: Dictionary, img_loader: Callable) -> Dictionary:
	if int(character.get("format", 0)) == CharacterSnapshot.FORMAT:
		return character.duplicate(true)
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.get("jobs", {}), data.get("jobs_survivor", {}))
	var ids := PackedInt32Array(CharacterSnapshot.held_item_ids(character, jobs))
	return CharacterSnapshot.migrate(character, jobs, DataRepo.equipment_info(ids, img_loader))


## An img loader over the default asset library for item info (empty roots without a cache: items then carry no stats).
static func equipment_info_loader() -> Callable:
	var library := AssetLibrary.get_default()
	return func(path: String) -> Dictionary:
		var img: WzImg = library.img(path) if library != null else null
		return img.root if img != null else {}


## Shows map select for the active character and autosaves the boundary.
func goto_stage_select() -> void:
	var snapshot := save_data().slot(active_slot)
	if snapshot.is_empty():
		return
	snapshot.phase = "map_select"
	if save_data().update_slot(active_slot, snapshot) != OK:
		_swap_to(error_screen("Could not save the round boundary."), "error")
		return
	var screen := _instance(STAGE_SELECT)
	screen.configure(snapshot, self)
	_swap_to(screen, "stage_select")


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
	elif origin == "free_market" and snapshot.phase == "free_market":
		_open_free_market(snapshot)
	else:
		goto_stage_select()


## Ordered stage keys per tier, from survivor data; works for any number of tiers.
static func tiers() -> Array:
	return DataRepo.load_all().get("stages", {}).get("tiers", [])


static func _date() -> String:
	return Time.get_datetime_string_from_system(true)


## Shows the importer screen.
func goto_import() -> void:
	_swap_to(_instance(IMPORT), "import")


## Starts a tool-only one-off round; does not read or write any save state.
func start_run(stage_key: String, p_seed: int = -1, options: Dictionary = {}) -> void:
	active_slot = -1
	_launch_round(stage_key, p_seed, options)


## Saves the selected stage and seed before launching a persistent round. Rejects stages outside this tier.
func start_round(stage_key: String, p_seed: int = -1) -> void:
	var snapshot := save_data().slot(active_slot)
	if snapshot.is_empty() or snapshot.phase != "map_select":
		return
	var ordered := tiers()
	var tier := int(snapshot.tier)
	if tier >= ordered.size() or stage_key not in ordered[tier]:
		return
	snapshot.phase = "round"
	snapshot.stage = stage_key
	snapshot.round_seed = make_seed() if p_seed < 0 else p_seed
	if save_data().update_slot(active_slot, snapshot) != OK:
		_swap_to(error_screen("Could not save the round's stage and seed."), "error")
		return
	_resume_round(snapshot)


## Resumes a living character in the hub, at map select or at the beginning of its stored round.
func continue_character(index: int) -> void:
	var snapshot := save_data().slot(index)
	if snapshot.is_empty():
		return
	active_slot = index
	if int(snapshot.character.get("format", 0)) != CharacterSnapshot.FORMAT:
		# A format-1 (spec #32) character migrates once, so the hub and map select see worn equipment too.
		snapshot.character = migrated_character(snapshot.character, equipment_info_loader())
		if save_data().update_slot(index, snapshot) != OK:
			_swap_to(error_screen("Could not save the round boundary."), "error")
			return
	if snapshot.phase == "round":
		_resume_round(snapshot)
	elif snapshot.phase == "free_market":
		_open_free_market(snapshot)
	else:
		goto_stage_select()


## Leaves a round without altering its last saved boundary; Continue restarts that same stage/seed.
func quit_round() -> void:
	goto_character_select()


## Saves at a hub/map-select boundary, then returns to the character slots.
func save_and_quit() -> void:
	var snapshot := save_data().slot(active_slot)
	if not snapshot.is_empty() and save_data().update_slot(active_slot, snapshot) != OK:
		_swap_to(error_screen("Could not save the round boundary."), "error")
		return
	goto_character_select()


func _resume_round(snapshot: Dictionary) -> void:
	var live := _live_settings()
	# The account's owned cash items decide which of the character's worn cash equipment and pet count (spec #34).
	var options := {"character": snapshot.character, "name": snapshot.name, "account": save_data().account}
	if live != null:
		options["settings_alert"] = live.alert_levels()
	_launch_round(String(snapshot.stage), int(snapshot.round_seed), options, live)


## The Settings a persistent round follows: `settings`, else the Settings autoload (null outside the tree).
func _live_settings() -> GameSettings:
	if settings != null:
		return settings
	if not is_inside_tree():
		return null
	return get_node_or_null("/root/Settings") as GameSettings


func _launch_round(stage_key: String, p_seed: int, options: Dictionary, live: GameSettings = null) -> void:
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


## Ends a round. Persistent clears require a final CharacterSnapshot; deaths may retain the saved boundary character.
## Non-final clears have exactly one exit (_after_round_cleared); one-off rounds never access SaveData.
func finish_run(summary: Dictionary, character: Dictionary = {}) -> void:
	last_summary = summary.duplicate(true)
	last_stage = String(summary.get("stage", last_stage))
	var before := {}
	last_new_best = false
	if active_slot >= 0:
		var sd := save_data()
		var snapshot := sd.slot(active_slot)
		var cleared := bool(summary.get("cleared", false))
		var valid_character := CharacterSnapshot.validation_error(character).is_empty()
		if snapshot.is_empty() or (cleared and not valid_character):
			_swap_to(error_screen("Missing final character at the round boundary."), "error")
			return
		before = sd.best_for(last_stage).duplicate(true)
		# tier C: terminal history uses the last valid character when death leaves unanswerable rewards.
		if valid_character:
			snapshot.character = character.duplicate(true)
		snapshot.erase("look") # Legacy wrapper duplication; CharacterSnapshot is the single look source.
		snapshot.stage = last_stage
		snapshot.rounds_played = int(snapshot.rounds_played) + 1
		if cleared:
			snapshot.tier = int(snapshot.tier) + 1
			snapshot.tiers_cleared = int(snapshot.tiers_cleared) + 1
			if int(snapshot.tier) < tiers().size():
				_after_round_cleared(snapshot)
				return
		var ending := "victory" if cleared else "died"
		if sd.end_run(active_slot, ending, _date(), snapshot, summary) != OK:
			_swap_to(error_screen("Could not save the end of the run."), "error")
			return
		last_new_best = SaveData.is_better(SaveData.record_from(summary), before)
		last_summary["ending"] = ending
		last_summary["tiers_cleared"] = snapshot.tiers_cleared
		active_slot = -1
	var results := _instance(RESULTS)
	if results != null and results.has_method("configure"):
		results.configure(last_summary, last_new_best, before, self)
	_swap_to(results, "results")


## Saves the carried non-final boundary (and the round's NX, in the same write) before entering the Free Market.
func _after_round_cleared(snapshot: Dictionary) -> void:
	snapshot.phase = "free_market"
	if save_data().update_slot(active_slot, snapshot, last_summary) != OK:
		_swap_to(error_screen("Could not save the cleared round."), "error")
		return
	var nx := int(last_summary.get("nx_awarded", 0))
	_open_free_market(snapshot, "You have gained %d NX." % nx if nx > 0 else "")


func _open_free_market(snapshot: Dictionary, notice: String = "") -> void:
	var screen := _instance(FREE_MARKET)
	screen.configure(snapshot, self, notice)
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
