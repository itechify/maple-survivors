extends Node2D
## Title screen (docs/ARCHITECTURE.md 4.1): the Maple Survivors key art (KeyArt: logo baked in; also the boot splash,
## so start-up runs straight into it) covering the view, BGM BgmUI/Title, and TitleButtons in the art's red and gold
## under the logo: Start goes to character select; a second row holds "Re-import WZ data" (re-runs the WZ import) and
## Quit. Keys: Enter = Start, Esc = Quit.
## Web build (WebProfile; docs/ARCHITECTURE.md 10 "Web profile"): no Quit and Esc does nothing here; the second row
## carries Fullscreen, Export save and Import save before Re-import WZ data. Re-import WZ data, Export save and
## Import save write a request marker for the web shell and quit (WebHandoff); the shell does the work and restarts.

## The y of the logo's bottom tip in the source art (KeyArt.SIZE).
const LOGO_BOTTOM := 785.0 # tier C: ours, measured on the key art.
## Gaps (view px): logo to the Start row, between rows, between buttons in a row, and the minimum bottom margin.
const LOGO_GAP := 8.0 # tier C: ours.
const ROW_GAP := 8.0 # tier C: ours.
const BUTTON_GAP := 6.0 # tier C: ours.
const BOTTOM_MARGIN := 10.0 # tier C: ours.
const START_WIDTH := 168.0 # tier C: ours.
## Buttons fade in over this many seconds once the art is shown.
const FADE_IN := 0.4 # tier C: ours.

var ui: CanvasLayer
## The key art, covering the view.
var art: KeyArt
var start_button: TitleButton
var quit_button: TitleButton
var reimport: TitleButton

## Web build only (null on desktop): Fullscreen / Export save / Import save on the second row, where desktop has Quit.
var fullscreen_button: TitleButton
var export_save_button: TitleButton
var import_save_button: TitleButton
## What Quit and Esc call (desktop; tests replace it).
var quit_fn: Callable = Callable()
## What the web entries call with a WebHandoff kind (Re-import WZ data, Export save, Import save): write the marker and
## quit to the shell. Tests replace it.
var web_request: Callable = Callable()
## What the Fullscreen button calls (must run inside the click on web). Tests replace it.
var fullscreen_toggle: Callable = GameSettings.toggle_fullscreen

var _root: Control
var _buttons: Control
var _web := false


func _ready() -> void:
	_web = WebProfile.is_web()
	ui = CanvasLayer.new()
	ui.layer = 2
	add_child(ui)
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	art = KeyArt.new()
	_root.add_child(art)
	_buttons = Control.new()
	_buttons.name = "Buttons"
	_buttons.set_anchors_preset(Control.PRESET_FULL_RECT)
	_buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_buttons)
	start_button = _button("Start", "Start", TitleButton.Style.PRIMARY, START_WIDTH)
	start_button.pressed.connect(_on_start)
	if _web:
		# Docs/ARCHITECTURE.md 10 "Web profile": no Quit in a browser tab; Fullscreen, Export save and Import save
		# lead the second row instead.
		fullscreen_button = _button("Fullscreen", "Fullscreen")
		fullscreen_button.pressed.connect(func() -> void: fullscreen_toggle.call())
		export_save_button = _button("ExportSave", "Export save")
		export_save_button.pressed.connect(func() -> void: _request_shell(WebHandoff.EXPORT_SAVE))
		import_save_button = _button("ImportSave", "Import save")
		import_save_button.pressed.connect(func() -> void: _request_shell(WebHandoff.IMPORT_SAVE))
	reimport = _button("Reimport", "Re-import WZ data")
	reimport.pressed.connect(_on_reimport)
	quit_button = _button("Quit", "Quit")
	quit_button.pressed.connect(_on_quit)
	quit_button.visible = not _web
	get_viewport().size_changed.connect(_layout)
	_layout(true)
	_buttons.modulate.a = 0.0
	create_tween().tween_property(_buttons, "modulate:a", 1.0, FADE_IN)
	var sfx := get_node_or_null("/root/Sfx") as AudioService
	if sfx != null:
		sfx.play_bgm(LoginBackdrop.BGM)


func _button(node_name: String, text: String, style := TitleButton.Style.SECONDARY,
		min_width := 0.0) -> TitleButton:
	var b := TitleButton.new(text, style, min_width)
	b.name = node_name
	_buttons.add_child(b)
	return b


## Places the art and the buttons; `sharp_now` rebuilds the sharp art at once (first layout).
func _layout(sharp_now := false) -> void:
	var view := get_viewport_rect().size
	art.fit(view, sharp_now)
	var r := Rect2(art.position, art.size)
	var rows: Array = [[start_button], _second_row()]
	var heights: Array[float] = []
	var total := 0.0
	for row: Array in rows:
		var h := 0.0
		for b: TitleButton in row:
			h = maxf(h, b.size.y)
		heights.append(h)
		total += h
	total += ROW_GAP * (rows.size() - 1)
	# Under the logo's tip, but never off the bottom of the view or the art.
	var logo_bottom := art.art_to_view(Vector2(0, LOGO_BOTTOM)).y
	var floor_y := minf(view.y, r.end.y) - BOTTOM_MARGIN
	var y := minf(logo_bottom + LOGO_GAP, floor_y - total)
	for i in rows.size():
		_center_row(rows[i], y, view.x)
		y += heights[i] + ROW_GAP


## The visible buttons of the second row, left to right.
func _second_row() -> Array:
	var row: Array = []
	for b: TitleButton in [fullscreen_button, export_save_button, import_save_button, reimport, quit_button]:
		if b != null and b.visible:
			row.append(b)
	return row


func _center_row(row: Array, y: float, view_w: float) -> void:
	var w := BUTTON_GAP * (row.size() - 1)
	for b: TitleButton in row:
		w += b.size.x
	var x := floorf((view_w - w) * 0.5)
	for b: TitleButton in row:
		b.position = Vector2(x, floorf(y))
		x += b.size.x + BUTTON_GAP


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
	var err := WebHandoff.hand_over(get_tree(), kind, web_request)
	if err != OK:
		push_warning("title: could not write the web request marker (%s)" % error_string(err))


func _on_reimport() -> void:
	if _web:
		_request_shell(WebHandoff.REIMPORT)
		return
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.goto_import()
