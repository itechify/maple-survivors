extends Control
## Import screen (docs/ARCHITECTURE.md 3 and 4.1, docs/ASSET_PIPELINE.md 2): shown when the asset cache is missing
## (and from the title's "Re-import" link). The player points it at their own MapleStory v83 folder; the screen checks
## that the .wz files are there, runs the local importer (tools/wzimport) as a child process with OS.execute_with_pipe,
## streams its output into the log and, on success, saves the folder in Settings, reloads Assets and opens the title.
## Fully offline: a local process reading local files; no browser, no network.
##
## Web build (WebProfile; docs/ARCHITECTURE.md 10 "Web profile"): the importer is not a child process there. The folder
## field, Browse and the log are hidden and the one button writes the re-import request marker and quits to the web
## shell (WebHandoff), which runs the importer in the page and restarts the game; start_import() never reaches
## OS.execute_with_pipe.
##
## The screen cannot rely on WZ art (there may be no cache yet), so it is drawn with plain controls in the v83 notice
## colours (blue plate, grey strip) and the Maple system font.
##
## Importer location: next to the game executable (exported builds: <exe dir>/wzimport(.exe)), else the dev build
## <repo>/tools/wzimport/target/release/wzimport(.exe) (resolved from res://). The manifest is copied from
## res://data/asset_manifest.json merged with its res://data/asset_manifest.d/*.json fragments (AssetManifest) to
## user://import/asset_manifest.json first (inside a .pck it is not a real file).

## The .wz files the import needs (docs/ASSET_PIPELINE.md section 1).
const REQUIRED := ["Base.wz", "Character.wz", "Effect.wz", "Etc.wz", "Item.wz", "Map.wz", "Mob.wz", "Npc.wz",
	"Skill.wz", "Sound.wz", "String.wz", "UI.wz"]
const MANIFEST := "res://data/asset_manifest.json"
const MANIFEST_COPY := "user://import/asset_manifest.json"
const PANEL_SIZE := Vector2(620, 470)
const BLUE := Color8(68, 136, 187)
const BLUE_DARK := Color8(17, 85, 153)
const GREY := Color8(221, 221, 221)
const OK_GREEN := Color8(120, 255, 120)
const BAD_RED := Color8(255, 136, 120)

var path_edit: LineEdit
var browse_button: Button
var import_button: Button
var back_button: Button
var status_label: Label
var log_box: RichTextLabel
## "idle", "running", "done", "failed".
var state := "idle"

var _panel: Control
var _pid := -1
var _stdio: FileAccess
var _stderr: FileAccess
var _partial := ["", ""]
var _dialog: FileDialog
var _web := false

## Web: what the Import button calls with a WebHandoff kind (marker + quit to the shell). Tests replace it.
var web_request: Callable = Callable()


func _ready() -> void:
	_web = WebProfile.is_web()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color8(12, 20, 32)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	_panel = Control.new()
	_panel.name = "Panel"
	_panel.size = PANEL_SIZE
	add_child(_panel)
	_panel.draw.connect(_draw_panel)
	_build()
	path_edit.text = AssetCachePaths.resolve_wz_root()
	_validate_now()
	resized.connect(_layout)
	get_viewport().size_changed.connect(_fit_view)
	_fit_view()


## Checks a folder for the required .wz files: {"ok": bool, "missing": PackedStringArray, "message": String}.
static func validate_wz_folder(folder: String) -> Dictionary:
	var missing := PackedStringArray()
	var p := folder.strip_edges().replace("\\", "/").rstrip("/")
	if p == "":
		return {"ok": false, "missing": PackedStringArray(REQUIRED), "message": "Choose your MapleStory v83 folder."}
	if not DirAccess.dir_exists_absolute(p):
		return {"ok": false, "missing": PackedStringArray(REQUIRED), "message": "That folder does not exist."}
	for f: String in REQUIRED:
		if not FileAccess.file_exists(p.path_join(f)):
			missing.append(f)
	if missing.is_empty():
		return {"ok": true, "missing": missing, "message": "All %d .wz files found." % REQUIRED.size()}
	if missing.size() == REQUIRED.size():
		return {"ok": false, "missing": missing,
			"message": "No .wz files here. Pick the folder that holds Map.wz, Mob.wz, Character.wz ..."}
	return {"ok": false, "missing": missing, "message": "Missing: " + ", ".join(missing)}


## Where the importer executable may be, in the order tried.
static func importer_candidates() -> PackedStringArray:
	var exe := "wzimport.exe" if OS.get_name() == "Windows" else "wzimport"
	var out := PackedStringArray()
	out.append(OS.get_executable_path().get_base_dir().path_join(exe))
	var res := ProjectSettings.globalize_path("res://")
	if res != "":
		out.append(res.path_join("../tools/wzimport/target/release").simplify_path().path_join(exe))
	return out


## The first importer that exists ("" when none).
static func find_importer() -> String:
	for c in importer_candidates():
		if FileAccess.file_exists(c):
			return c
	return ""


## Importer arguments for a WZ folder, manifest and cache root.
static func importer_args(wz: String, manifest: String, out: String) -> PackedStringArray:
	return PackedStringArray(["import", "--wz", wz, "--manifest", manifest, "--out", out])


## Starts the import (after validation). Returns false (with the reason in the status line) when it cannot start.
func start_import() -> bool:
	if state == "running":
		return false
	if _web:
		return _hand_over_to_shell()
	var folder := path_edit.text.strip_edges().replace("\\", "/").rstrip("/")
	var v := validate_wz_folder(folder)
	_show_validation(v)
	if not v.ok:
		return false
	var exe := find_importer()
	if exe == "":
		_status("The importer (wzimport) was not found. Build it with: cargo build --release in tools/wzimport",
			BAD_RED)
		_log("Looked for: " + ", ".join(importer_candidates()))
		return false
	var manifest := _copy_manifest()
	if manifest == "":
		_status("Cannot copy the asset manifest to the user folder.", BAD_RED)
		return false
	var out := AssetCachePaths.resolve_cache_root()
	DirAccess.make_dir_recursive_absolute(out)
	var args := importer_args(folder, manifest, out)
	_log("> wzimport " + " ".join(args))
	var info := OS.execute_with_pipe(exe, args, false)
	if info.is_empty():
		_status("The importer could not be started.", BAD_RED)
		return false
	_pid = int(info.pid)
	_stdio = info.stdio
	_stderr = info.stderr
	_partial = ["", ""]
	state = "running"
	_status("Importing... this takes a minute.", MapleText.YELLOW)
	_set_busy(true)
	return true


## Web: writes the re-import marker and quits so the shell can take over; false (with the reason shown) on failure.
func _hand_over_to_shell() -> bool:
	var err := WebHandoff.hand_over(get_tree(), WebHandoff.REIMPORT, web_request)
	if err != OK:
		_status("Could not hand over to the importer (%s)." % error_string(err), BAD_RED)
		return false
	_status("Leaving the game for the importer...", MapleText.YELLOW)
	return true


func _process(_delta: float) -> void:
	if state != "running":
		return
	_drain(_stdio, 0)
	_drain(_stderr, 1)
	if OS.is_process_running(_pid):
		return
	_drain(_stdio, 0)
	_drain(_stderr, 1)
	for i in 2:
		if _partial[i] != "":
			_log(_partial[i])
			_partial[i] = ""
	var code := OS.get_process_exit_code(_pid)
	_pid = -1
	_set_busy(false)
	if code == 0:
		state = "done"
		_finish_success()
	else:
		state = "failed"
		_status("The import failed (exit code %d). See the log above." % code, BAD_RED)


func _finish_success() -> void:
	var settings := get_node_or_null("/root/Settings") as GameSettings
	var folder := path_edit.text.strip_edges().replace("\\", "/").rstrip("/")
	if settings != null and OS.get_environment(AssetCachePaths.WZ_ENV) == "":
		settings.set_wz_root(folder)
	var assets := get_node_or_null("/root/Assets") as AssetLibrary
	var ok := assets.open() if assets != null else false
	if not ok:
		state = "failed"
		_status("The importer finished but the cache cannot be read at %s." % AssetCachePaths.resolve_cache_root(),
			BAD_RED)
		return
	_status("Import complete!", OK_GREEN)
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		get_tree().create_timer(0.8).timeout.connect(flow.goto_title)


func _drain(f: FileAccess, which: int) -> void:
	if f == null:
		return
	while true:
		var chunk := f.get_buffer(4096)
		if chunk.is_empty():
			break
		var text: String = _partial[which] + chunk.get_string_from_utf8()
		var lines := text.split("\n")
		_partial[which] = lines[lines.size() - 1]
		for i in lines.size() - 1:
			_log(lines[i].strip_edges(false, true), which == 1)


func _copy_manifest() -> String:
	# The importer gets one file here (the .pck holds no folder beside it), so the fragments are merged into it.
	var merged := AssetManifest.load_merged(MANIFEST)
	var text := AssetManifest.to_json(merged) if not merged.is_empty() else ""
	if text == "":
		return ""
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(MANIFEST_COPY.get_base_dir()))
	var f := FileAccess.open(MANIFEST_COPY, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(text)
	f.close()
	return ProjectSettings.globalize_path(MANIFEST_COPY)


func _build() -> void:
	var title := MapleText.new("Maple Survivors", 18, MapleText.YELLOW, true)
	title.name = "Title"
	title.position = Vector2(20, 12)
	_panel.add_child(title)
	var sub := MapleText.new("Import your MapleStory v83 data", MapleText.SIZE, MapleText.WHITE, true)
	sub.position = Vector2(22, 38)
	_panel.add_child(sub)
	var body_text := (
		"Maple Survivors draws every sprite, map and sound from your own copy of MapleStory v83 (GMS). Nothing is "
		+ "downloaded and nothing is bundled with the game.\n\nChoose the folder of your v83 installation, the one "
		+ "with Map.wz, Mob.wz, Character.wz and the other .wz files. The importer reads them once and writes a local "
		+ "asset cache to:\n" + AssetCachePaths.resolve_cache_root())
	if _web:
		body_text = (
			"Maple Survivors draws every sprite, map and sound from your own copy of MapleStory v83 (GMS). Nothing "
			+ "is bundled with the game.\n\nThe importer runs next to the game in this page. Press the button to "
			+ "leave the game for it: it asks for your v83 files (Map.wz, Mob.wz, Character.wz and the other .wz "
			+ "files), builds the asset cache in this browser's storage and brings you back here.")
	var body := MapleText.new(body_text, MapleText.SIZE, MapleText.BLACK)
	body.name = "Body"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.position = Vector2(20, 72)
	body.size = Vector2(PANEL_SIZE.x - 40, 110)
	_panel.add_child(body)
	path_edit = LineEdit.new()
	path_edit.name = "Path"
	path_edit.placeholder_text = "C:/Nexon/MapleStory"
	path_edit.position = Vector2(20, 196)
	path_edit.size = Vector2(PANEL_SIZE.x - 40 - 96, 24)
	_style_edit(path_edit)
	path_edit.text_changed.connect(func(_t: String) -> void: _validate_now())
	path_edit.text_submitted.connect(func(_t: String) -> void: start_import())
	_panel.add_child(path_edit)
	browse_button = _make_button("Browse...", Vector2(PANEL_SIZE.x - 20 - 90, 196), Vector2(90, 24))
	browse_button.pressed.connect(_on_browse)
	status_label = MapleText.new("", MapleText.SMALL, MapleText.WHITE, true)
	status_label.name = "Status"
	status_label.position = Vector2(22, 226)
	status_label.size = Vector2(PANEL_SIZE.x - 44, 16)
	status_label.clip_text = true
	_panel.add_child(status_label)
	log_box = RichTextLabel.new()
	log_box.name = "Log"
	log_box.position = Vector2(20, 248)
	log_box.size = Vector2(PANEL_SIZE.x - 40, 150)
	log_box.scroll_following = true
	log_box.selection_enabled = true
	log_box.add_theme_font_override("normal_font", MapleText.font())
	log_box.add_theme_font_size_override("normal_font_size", MapleText.SMALL)
	log_box.add_theme_color_override("default_color", Color8(220, 230, 240))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(16, 32, 48)
	sb.border_color = BLUE_DARK
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	log_box.add_theme_stylebox_override("normal", sb)
	_panel.add_child(log_box)
	import_button = _make_button("Import", Vector2(PANEL_SIZE.x - 20 - 100, PANEL_SIZE.y - 40), Vector2(100, 26))
	import_button.pressed.connect(start_import)
	if _web:
		path_edit.visible = false
		browse_button.visible = false
		for line: String in ["1. The game closes and the importer opens in this page.",
				"2. You pick your MapleStory v83 files.",
				"3. The asset cache is built and kept in this browser's storage.",
				"4. The game starts again with it."]:
			_log(line)
		var w := 150.0
		import_button.text = "Import WZ data"
		import_button.position.x = PANEL_SIZE.x - 20 - w
		import_button.size.x = w
	back_button = _make_button("Back to title", Vector2(20, PANEL_SIZE.y - 40), Vector2(110, 26))
	back_button.pressed.connect(_on_back)
	var assets := get_node_or_null("/root/Assets") as AssetLibrary
	back_button.visible = assets != null and assets.has_cache()


func _make_button(text: String, pos: Vector2, sz: Vector2) -> Button:
	var b := Button.new()
	b.text = text
	b.position = pos
	b.size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", MapleText.font(true))
	b.add_theme_font_size_override("font_size", MapleText.SMALL)
	for state_name: String in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = {"normal": Color8(238, 136, 51), "hover": Color8(255, 170, 68), "pressed": Color8(204, 102, 34),
			"disabled": Color8(150, 150, 150)}[state_name]
		sb.border_color = Color8(120, 60, 20)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(3)
		b.add_theme_stylebox_override(state_name, sb)
	b.add_theme_color_override("font_color", MapleText.WHITE)
	b.add_theme_color_override("font_hover_color", MapleText.WHITE)
	b.add_theme_color_override("font_disabled_color", Color8(220, 220, 220))
	b.pressed.connect(func() -> void: UiArt.play_sound(UiArt.SND_CLICK))
	_panel.add_child(b)
	return b


func _style_edit(e: LineEdit) -> void:
	e.add_theme_font_override("font", MapleText.font())
	e.add_theme_font_size_override("font_size", MapleText.SIZE)
	e.add_theme_color_override("font_color", MapleText.BLACK)
	e.add_theme_color_override("caret_color", MapleText.BLACK)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color8(255, 255, 255)
	sb.border_color = BLUE_DARK
	sb.set_border_width_all(1)
	sb.set_content_margin_all(4)
	e.add_theme_stylebox_override("normal", sb)
	e.add_theme_stylebox_override("focus", sb)


## Fills the view (the screen is a child of main's plain Node, so anchors alone do not size it).
func _fit_view() -> void:
	if not (get_parent() is Control):
		if anchor_right != 0.0 or anchor_bottom != 0.0:
			set_anchors_preset(Control.PRESET_TOP_LEFT)
		position = Vector2.ZERO
		size = get_viewport_rect().size
	_layout()


func _layout() -> void:
	_panel.position = ((size - PANEL_SIZE) * 0.5).floor()


func _draw_panel() -> void:
	var r := Rect2(Vector2.ZERO, PANEL_SIZE)
	# v83 notice colours: white rim, blue plate, grey strip for the buttons.
	_panel.draw_rect(r, Color8(255, 255, 255))
	_panel.draw_rect(r.grow(-1), Color8(85, 119, 153))
	_panel.draw_rect(Rect2(3, 3, PANEL_SIZE.x - 6, 60), BLUE)
	_panel.draw_rect(Rect2(3, 63, PANEL_SIZE.x - 6, PANEL_SIZE.y - 63 - 52), Color8(238, 238, 238))
	_panel.draw_rect(Rect2(3, PANEL_SIZE.y - 52, PANEL_SIZE.x - 6, 49), GREY)
	_panel.draw_rect(Rect2(10, 188, PANEL_SIZE.x - 20, 218), BLUE)
	_panel.draw_line(Vector2(3, 63), Vector2(PANEL_SIZE.x - 3, 63), BLUE_DARK)


func _validate_now() -> void:
	if _web:
		_status("Ready: the importer asks for your files.", OK_GREEN)
		import_button.disabled = state == "running"
		return
	_show_validation(validate_wz_folder(path_edit.text))


func _show_validation(v: Dictionary) -> void:
	_status(String(v.message), OK_GREEN if v.ok else BAD_RED)
	import_button.disabled = not v.ok or state == "running"


func _status(text: String, col: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", col)


func _log(line: String, is_err: bool = false) -> void:
	if is_err:
		log_box.push_color(BAD_RED)
		log_box.add_text(line + "\n")
		log_box.pop()
	else:
		log_box.add_text(line + "\n")


func _set_busy(busy: bool) -> void:
	import_button.disabled = busy
	browse_button.disabled = busy
	path_edit.editable = not busy
	back_button.disabled = busy


func _on_browse() -> void:
	if _dialog == null:
		_dialog = FileDialog.new()
		_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_dialog.use_native_dialog = true
		_dialog.title = "Choose your MapleStory v83 folder"
		_dialog.dir_selected.connect(func(d: String) -> void:
			path_edit.text = d.replace("\\", "/")
			_validate_now())
		add_child(_dialog)
	if path_edit.text.strip_edges() != "" and DirAccess.dir_exists_absolute(path_edit.text.strip_edges()):
		_dialog.current_dir = path_edit.text.strip_edges()
	_dialog.popup_centered(Vector2i(640, 420))


func _on_back() -> void:
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.goto_title()


func _exit_tree() -> void:
	if _pid > 0 and OS.is_process_running(_pid):
		OS.kill(_pid)
