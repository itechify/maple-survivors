class_name WebHandoff
extends RefCounted
## Hand-off from the game to the web shell (spec #130, docs/ARCHITECTURE.md 10 "Web profile"). The browser build cannot
## run the importer or move save files itself, so it writes a request marker, quits, and the shell (web/) reads the
## marker once the engine has exited, does the work and restarts the engine. Files and quitting only: no JavaScript.
##
## Marker: `user://web_request.json` = {"format": 1, "request": "reimport" | "export_save" | "import_save"}. On web
## `user://` is `/userfs/MapleSurvivors` (IDBFS); the engine syncs it to IndexedDB after any frame in which a file there
## was closed after writing, and once more on quit, which is why the marker must be written and closed in a normal
## frame and never from `_exit_tree` or other teardown code.
##
## Quit sequence (BINDING, decisions.md 6): write and close the marker, stop every AudioStreamPlayer under the root,
## pause the tree, then quit. Godot 4.7.2's web teardown throws on the already closed AudioContext when a player still
## holds a sample playback, and then `onExit` never fires; quit() only takes effect at the end of the frame, so audio
## must be stopped and the tree paused (no more scripts that could start sounds) first.
##
## Seams for tests: `marker_path`, the `quit` callable and the save are parameters.

const MARKER_PATH := "user://web_request.json"
const FORMAT := 1
const REIMPORT := "reimport"
const EXPORT_SAVE := "export_save"
const IMPORT_SAVE := "import_save"
const KINDS := [REIMPORT, EXPORT_SAVE, IMPORT_SAVE]


## Writes (and closes) the request marker; ERR_INVALID_PARAMETER for a kind the shell does not know, nothing written.
static func write_marker(kind: String, path: String = MARKER_PATH) -> Error:
	if not (kind in KINDS):
		return ERR_INVALID_PARAMETER
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	# Explicit text so the shell never sees "format": 1.0.
	f.store_string('{"format":%d,"request":%s}' % [FORMAT, JSON.stringify(kind)])
	var err := f.get_error()
	f.close()
	return err


## Stops every AudioStreamPlayer anywhere under the root (the Sfx autoload's players included).
static func stop_all_audio(tree: SceneTree) -> void:
	for node in tree.root.find_children("*", "AudioStreamPlayer", true, false):
		(node as AudioStreamPlayer).stop()


## The web quit: audio off, tree paused, then `quit_fn` (default SceneTree.quit). Desktop code calls SceneTree.quit()
## directly; use this wherever the web build quits so the shell sees `onExit`.
static func quit(tree: SceneTree, quit_fn: Callable = Callable()) -> void:
	stop_all_audio(tree)
	tree.paused = true
	if quit_fn.is_valid():
		quit_fn.call()
	else:
		tree.quit()


## Request `kind` from the shell and quit: flush the save (the save kinds), write the marker, then the web quit.
## Returns an error (and does not quit) when the marker could not be written. `save` defaults to the Flow's save.
static func quit_to_shell(tree: SceneTree, kind: String, quit_fn: Callable = Callable(),
		marker_path: String = MARKER_PATH, save: SaveData = null) -> Error:
	if not (kind in KINDS):
		return ERR_INVALID_PARAMETER
	if kind == EXPORT_SAVE or kind == IMPORT_SAVE:
		flush_save(tree, save)
	var err := write_marker(kind, marker_path)
	if err != OK:
		return err
	quit(tree, quit_fn)
	return OK


## Rewrites user://save.json from the loaded save (closing the file in this frame) so IndexedDB holds its latest state.
## No-op when no save was loaded (nothing in memory differs from the file) or the save has a persistence error.
static func flush_save(tree: SceneTree, save: SaveData = null) -> void:
	if save == null:
		var flow := tree.root.get_node_or_null("Flow") as SceneFlow
		save = flow.save if flow != null else null
	if save != null and save.last_error == OK:
		save.save_file()
