class_name MapleWindow
extends Control
## Base of the modal MapleStory windows (LevelUpWindow, JobAdvanceWindow, PauseMenu).
##
## The window is a full-view Control (anchors on the viewport, so it works under a CanvasLayer at any logical view
## size, e.g. 1066x600) that blocks the mouse while open. Its art is drawn by `panel`, a child Control of
## `panel_size` centred in the view (re-centred when the view changes); subclasses draw in `_draw_panel()` and put
## their buttons under `panel`. Opening fades the panel in while it drops `SLIDE` px into place; closing fades it out.
##
## Input: keys are read in `_input()` while open (and consumed), after `input_delay` seconds (so a key held in the run
## does not pick something by accident), and handed to `handle_input()`; mouse events reach `_gui_input()`.
## Subclasses override `handle_input(event) -> bool` and `_panel_gui_input(event, local_pos)`.
## `process_mode` is ALWAYS so the windows keep working if the tree is paused.
##
## In-run windows (WindowStack) can sit above a modal window: while `input_blocked` is set (RunScene sets it whenever
## a stack window is open) the window ignores keys (they go on to the run) and eats mouse presses without acting.
## With `window_hotkeys` (the level-up and job windows) the Stat / Skill window hotkeys (HOTKEY_ACTIONS) are never
## consumed, so they reach RunScene while the choice is up.
##
## Tests: set `transition_seconds = 0` and `input_delay = 0`, add the window to the tree and call `handle_input()` /
## `_gui_input()` with synthetic events (no frames are needed).

## Panel drop distance of the open transition (px). tier C: ours.
const SLIDE := 10.0
## Input actions of the in-run windows that pass through windows with `window_hotkeys`.
const HOTKEY_ACTIONS := ["stat_window", "skill_window"]

## Open/close transition length (s); 0 = instant. tier C: ours.
var transition_seconds := 0.15
## Keys are ignored for this long after open() (s). tier C: ours.
var input_delay := 0.2
## True while an in-run window (WindowStack) is above this one: keys pass on, mouse presses do nothing.
var input_blocked := false
## Let the in-run window hotkeys (HOTKEY_ACTIONS) through (level-up / job choices).
var window_hotkeys := false
## The drawn window, centred in the view.
var panel: Control
## Size of the panel art.
var panel_size := Vector2(200, 100):
	set(v):
		panel_size = v
		_relayout()

var _open := false
var _since_open := 0.0
var _slide := 0.0
var _tween: Tween


func _init() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	panel = Control.new()
	panel.name = "Panel"
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	panel.draw.connect(func() -> void: _draw_panel(panel))
	resized.connect(_relayout)


## True between open and the start of the close.
func is_open() -> bool:
	return _open


## Top-left of the panel in window coordinates (without the transition offset).
func panel_origin() -> Vector2:
	var view := size
	if view == Vector2.ZERO:
		view = get_viewport_rect().size if is_inside_tree() else Vector2(GameSettings.BASE_VIEW)
	return ((view - panel_size) * 0.5).floor()


func _enter_tree() -> void:
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_relayout):
		vp.size_changed.connect(_relayout)
	_relayout()


func _exit_tree() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_relayout):
		vp.size_changed.disconnect(_relayout)


## Shows the window (subclasses call this from their open()).
func _show_window() -> void:
	_kill_tween()
	_open = true
	_since_open = 0.0
	visible = true
	_relayout()
	panel.queue_redraw()
	if transition_seconds <= 0.0 or not is_inside_tree():
		_slide = 0.0
		panel.modulate.a = 1.0
		_relayout()
		return
	_slide = -SLIDE
	panel.modulate.a = 0.0
	_relayout()
	_tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(panel, "modulate:a", 1.0, transition_seconds)
	_tween.tween_method(_set_slide, -SLIDE, 0.0, transition_seconds)


## Hides the window (fade out); `then` runs once it is hidden.
func _hide_window(then: Callable = Callable()) -> void:
	_kill_tween()
	_open = false
	if transition_seconds <= 0.0 or not is_inside_tree() or not visible:
		visible = false
		if then.is_valid():
			then.call()
		return
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_tween.tween_property(panel, "modulate:a", 0.0, transition_seconds * 0.8)
	_tween.tween_callback(func() -> void:
		visible = false
		if then.is_valid():
			then.call())


## Handles one input event while open; returns true when it was used. Subclasses override.
func handle_input(_event: InputEvent) -> bool:
	return false


## Mouse events inside the window, `local` = position relative to the panel's top-left. Subclasses override.
func _panel_gui_input(_event: InputEvent, _local: Vector2) -> void:
	pass


## Draws the window art into `ci` (the panel). Subclasses override.
func _draw_panel(_ci: Control) -> void:
	pass


func _process(delta: float) -> void:
	if _open:
		_since_open += delta


## True when `event` is an in-run window hotkey this window lets through (`window_hotkeys`).
func passes_hotkey(event: InputEvent) -> bool:
	if not window_hotkeys:
		return false
	for action: String in HOTKEY_ACTIONS:
		if _action(event, action):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not _open or not visible or input_blocked:
		return
	if not (event is InputEventKey or event is InputEventJoypadButton):
		return
	if passes_hotkey(event):
		return
	if _since_open < input_delay:
		if event.is_pressed():
			get_viewport().set_input_as_handled()
		return
	if handle_input(event):
		get_viewport().set_input_as_handled()


func _gui_input(event: InputEvent) -> void:
	if not _open:
		return
	if input_blocked:
		accept_event()
		return
	if event is InputEventMouse:
		_panel_gui_input(event, (event as InputEventMouse).position - panel.position)
	accept_event()


func _relayout() -> void:
	if panel == null:
		return
	panel.size = panel_size
	panel.position = panel_origin() + Vector2(0, roundf(_slide))
	_layout_children()


## Positions child controls of the panel after a resize or content change. Subclasses override.
func _layout_children() -> void:
	pass


func _set_slide(v: float) -> void:
	_slide = v
	_relayout()


func _kill_tween() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = null


# --- key helpers -----------------------------------------------------------------------------------------------

## True for a fresh (not echo) key press of `key` (physical or logical keycode).
static func key_pressed(event: InputEvent, key: Key) -> bool:
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	if not k.pressed or k.echo:
		return false
	return k.physical_keycode == key or k.keycode == key


## Enter or keypad Enter (not ui_accept: that includes Space, the jump key).
static func is_confirm(event: InputEvent) -> bool:
	return key_pressed(event, KEY_ENTER) or key_pressed(event, KEY_KP_ENTER)


## Esc (or the rebindable "pause" action).
static func is_cancel(event: InputEvent) -> bool:
	return key_pressed(event, KEY_ESCAPE) or _action(event, "pause")


## -1 for Up, +1 for Down (arrows or the move_up/move_down actions), else 0.
static func vertical_step(event: InputEvent) -> int:
	if key_pressed(event, KEY_UP) or _action(event, "move_up"):
		return -1
	if key_pressed(event, KEY_DOWN) or _action(event, "move_down"):
		return 1
	return 0


## 1-9 for the digit keys (choice_1..choice_3 actions first, then the plain digits), else 0.
static func digit_of(event: InputEvent) -> int:
	for i in 3:
		if _action(event, "choice_%d" % (i + 1)):
			return i + 1
	for d in range(1, 10):
		if key_pressed(event, (KEY_0 + d) as Key) or key_pressed(event, (KEY_KP_0 + d) as Key):
			return d
	return 0


static func _action(event: InputEvent, action: String) -> bool:
	if not InputMap.has_action(action):
		return false
	if event is InputEventKey and (event as InputEventKey).echo:
		return false
	return event.is_action_pressed(action, false, true)
