extends Node2D
## Title screen (docs/ARCHITECTURE.md 4.1): the v83 login scene (LoginBackdrop at the title section, BGM
## BgmUI/Title, the book frame) with the game's buttons on the wooden login signboard: Start (Login.img/CharSelect/
## BtSelect, the wooden "Start") goes to character select, Quit (Login.img/Title/BtQuit) exits. "Re-import WZ data" on
## the middle plank re-runs the WZ import: a small wooden plate of the same signboard (Login.img/Title/BtLoginIDLost,
## "Find login ID", widened from its text-free left columns so it carries our label instead; its own mouseOver and
## pressed art). Keys: Enter = Start, Esc = Quit.
## Web build (WebProfile; docs/ARCHITECTURE.md 10 "Web profile"): no Quit and Esc does nothing here; the bottom plank
## carries three more plates instead: Fullscreen, Export save and Import save. Re-import WZ data, Export save and
## Import save write a request marker for the web shell and quit (WebHandoff); the shell does the work and restarts.
##
## There is no login here, so the signboard's "Login ID" / "Password" fields are covered with wood from the blank
## right end of the same plank (columns 266-357, repeated), drawn right after the map run that holds the sign.

const BT_START := "UI.wz/Login.img/CharSelect/BtSelect"
const BT_QUIT := "UI.wz/Login.img/Title/BtQuit"
## The small signboard plate behind the re-import label, and its text-free left columns (measured: the words start at
## column 7 of the 82 px plate in every state).
const BT_PLATE := "UI.wz/Login.img/Title/BtLoginIDLost"
const PLATE_LEFT := 5.0 # tier C: text-free Title/BtLoginIDLost columns, existing offline plate treatment.
const PLATE_PAD := 9.0 # tier C: offline Re-import label padding, same art.
const PLATE_TEXT := Color8(255, 238, 204)
const PLATE_OUTLINE := Color8(68, 34, 0)
## The login signboard (Map.wz/Obj/login.img/Title/signboard/0, placed at (137, 21) by MapLogin.img, 368x236 with its
## origin at the centre). Start goes on the (covered) top plank, the re-import link on the middle plank, Quit on the
## big bottom plank; plank centres in sign-local px.
const SIGN_CENTER := Vector2(137, 21) # tier A: MapLogin.img Title/signboard object position.
const SIGN := "Map.wz/Obj/login.img/Title/signboard/0/0"
## Sign-local rects: the labels and fields to cover, and the blank wood used to cover them.
const SIGN_FIELDS := Rect2(60, 7, 206, 77) # tier C: remove account ink from original Title/signboard.
const SIGN_WOOD := Rect2(266, 7, 92, 77) # tier C: blank original sign wood used for the offline patch.
const SIGN_SIZE := Vector2(368, 236) # tier A: Title/signboard canvas.
## tier C: offline Start in the original Login region (TL590,243), Re-import on the middle plank,
## Quit at TL590,354. Private spec32/v83-login-refs/layout.md Title, title_1.png / title_2.png;
## localized/undated captures do not establish exact GMS v83 placement.
const PLANK_TOP := Vector2(315, 44)
const PLANK_MID := Vector2(183, 106)
const PLANK_LOW := Vector2(307, 159)
## Web only: gap between the three plates that stand in for Quit on the bottom plank.
const WEB_PLATE_GAP := 4.0 # tier C: ours.

var backdrop: LoginBackdrop
var ui: CanvasLayer
var start_button: WzButton
var quit_button: WzButton
var reimport: WzButton

## Web build only (null on desktop): the Fullscreen / Export save / Import save plates on the big bottom plank, where
## desktop has Quit.
var fullscreen_button: WzButton
var export_save_button: WzButton
var import_save_button: WzButton
## What Quit and Esc call (desktop; tests replace it).
var quit_fn: Callable = Callable()
## What the web entries call with a WebHandoff kind (Re-import WZ data, Export save, Import save): write the marker and
## quit to the shell. Tests replace it.
var web_request: Callable = Callable()
## What the Fullscreen plate calls (must run inside the click on web). Tests replace it.
var fullscreen_toggle: Callable = GameSettings.toggle_fullscreen

var _root: Control
var _web := false


func _ready() -> void:
	backdrop = LoginBackdrop.new(LoginBackdrop.TITLE)
	add_child(backdrop)
	_cover_sign_fields()
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_root)
	start_button = WzButton.new(BT_START)
	start_button.name = "Start"
	start_button.fallback_size = Vector2(101, 30)
	start_button.label = "" if start_button.has_art() else "Start"
	start_button.pressed.connect(_on_start)
	_root.add_child(start_button)
	quit_button = WzButton.new(BT_QUIT)
	quit_button.name = "Quit"
	quit_button.fallback_size = Vector2(84, 38)
	quit_button.label = "" if quit_button.has_art() else "Quit"
	quit_button.pressed.connect(_on_quit)
	_root.add_child(quit_button)
	reimport = _plate("Reimport", "Re-import WZ data")
	reimport.pressed.connect(_on_reimport)
	_web = WebProfile.is_web()
	if _web:
		# Docs/ARCHITECTURE.md 10 "Web profile": no Quit in a browser tab; Fullscreen, Export save and Import save sit
		# in its place on the bottom plank.
		quit_button.visible = false
		fullscreen_button = _plate("Fullscreen", "Fullscreen")
		fullscreen_button.pressed.connect(func() -> void: fullscreen_toggle.call())
		export_save_button = _plate("ExportSave", "Export save")
		export_save_button.pressed.connect(func() -> void: _request_shell(WebHandoff.EXPORT_SAVE))
		import_save_button = _plate("ImportSave", "Import save")
		import_save_button.pressed.connect(func() -> void: _request_shell(WebHandoff.IMPORT_SAVE))
	get_viewport().size_changed.connect(_layout)
	_layout()


## A small wooden plate button (the re-import treatment) carrying our own label.
func _plate(node_name: String, text: String) -> WzButton:
	var b := WzButton.new(BT_PLATE, text)
	b.name = node_name
	b.label_color = PLATE_TEXT
	b.label_outline = 1
	b.label_outline_color = PLATE_OUTLINE
	b.fallback_size = Vector2(MapleText.width(text, MapleText.SMALL, true) + 2.0 * PLATE_PAD, 23)
	b.set_plate(ceilf(MapleText.width(text, MapleText.SMALL, true) + 2.0 * PLATE_PAD), PLATE_LEFT)
	_root.add_child(b)
	return b


## Covers the signboard's login fields: a node drawn right after the map run that holds the sign.
func _cover_sign_fields() -> void:
	var runs := backdrop.find_runs("Title/signboard")
	var f := UiArt.frame(SIGN)
	if runs.is_empty() or f == null:
		return
	var run := runs[0]
	var sign := Node2D.new()
	sign.name = "SignPatch"
	run.get_parent().add_child(sign)
	run.get_parent().move_child(sign, run.get_index() + 1)
	sign.position = SIGN_CENTER - f.origin
	sign.draw.connect(func() -> void:
		var x := SIGN_FIELDS.position.x
		while x < SIGN_FIELDS.end.x:
			var w := minf(SIGN_WOOD.size.x, SIGN_FIELDS.end.x - x)
			UiArt.blit_part(sign, f, Rect2(SIGN_WOOD.position, Vector2(w, SIGN_WOOD.size.y)),
				Vector2(x, SIGN_FIELDS.position.y))
			x += w)
	sign.queue_redraw()


func _layout() -> void:
	var view := get_viewport_rect().size
	var sign_tl := view * 0.5 + SIGN_CENTER - LoginBackdrop.TITLE - SIGN_SIZE * 0.5
	start_button.position = (sign_tl + PLANK_TOP - start_button.size * 0.5).floor()
	quit_button.position = (sign_tl + PLANK_LOW - quit_button.size * 0.5).floor()
	reimport.position = (sign_tl + PLANK_MID - reimport.size * 0.5).floor()
	if _web:
		# One row of three plates, centred on the bottom plank.
		var row: Array[WzButton] = [fullscreen_button, export_save_button, import_save_button]
		var total := WEB_PLATE_GAP * (row.size() - 1)
		for b in row:
			total += b.size.x
		var x := sign_tl.x + PLANK_LOW.x - total * 0.5
		for b in row:
			b.position = Vector2(floorf(x), floorf(sign_tl.y + PLANK_LOW.y - b.size.y * 0.5))
			x += b.size.x + WEB_PLATE_GAP


func _unhandled_input(event: InputEvent) -> void:
	if MapleWindow.is_confirm(event):
		start_button.pressed.emit()
		get_viewport().set_input_as_handled()
	elif MapleWindow.key_pressed(event, KEY_ESCAPE) and not _web:
		quit_button.pressed.emit()
		get_viewport().set_input_as_handled()


func _on_start() -> void:
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.goto_character_select()


func _on_quit() -> void:
	if _web:
		return # a browser tab has no Quit; the button is hidden and Esc leaves fullscreen
	if quit_fn.is_valid():
		quit_fn.call()
	else:
		get_tree().quit()


## Web: hands `kind` (a WebHandoff kind) to the shell: marker, audio off, quit; the shell restarts the engine.
func _request_shell(kind: String) -> void:
	if web_request.is_valid():
		web_request.call(kind)
	else:
		var err := WebHandoff.quit_to_shell(get_tree(), kind)
		if err != OK:
			push_warning("title: could not write the web request marker (%s)" % error_string(err))


func _on_reimport() -> void:
	if _web:
		_request_shell(WebHandoff.REIMPORT)
		return
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.goto_import()
