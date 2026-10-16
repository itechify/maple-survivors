class_name UiWindow
extends Control
## Base of the in-run, non-modal MapleStory windows (Stat; Skill, Key Config and Options build on it) that a
## WindowStack hosts. Unlike MapleWindow (the full-view modal level-up / job / pause windows) a UiWindow is exactly
## its art's size, sits at `position` inside the stack, and only takes the mouse inside its own rect.
##
## Subclass interface:
##   - set `window_id` (the stack's key for it; WindowStack.toggle sets it from the registered id) and `size`
##     (the art's size) in _init();
##   - draw the window in `_draw()` (local coordinates, (0, 0) = top-left); children (WzButtons) go under the window;
##   - mouse input arrives in `_window_gui_input(event, local)` after the base handled raise / drag;
##   - `draggable` (default true) and `title_height` (TITLE_H) make the top strip a drag handle;
##   - `auto_place` (default true): the stack centres the window above the status bar on its first open
##     (`default_position(view)`; override it for another spot) and then remembers where it was dragged;
##   - `request_close()` (e.g. from a close button) emits `close_requested`; the stack closes and frees the window.
## Keys are not read here: the host (RunScene) maps Esc / the window hotkeys to WindowStack calls.
##
## Signals: `raised` on any left press inside the window (the stack brings it to the front), `close_requested`.
## Tests: add a WindowStack to the tree, open a window and call `_gui_input()` with synthetic mouse events whose
## `position` is local to the window (no frames are needed).

## Emitted on a left press anywhere in the window.
signal raised()
## Emitted when the window asks to be closed (close button, a chosen menu entry).
signal close_requested()

## tier C (ours): height of the title strip that drags the window (v83 window art has a ~20 px title bar).
const TITLE_H := 20.0
## tier C (ours): px of the window that always stay inside the view while dragging, so it can be grabbed again.
const KEEP_VISIBLE := 40.0

## The stack's key for this window ("stat", "skill", "key_config", "options", "menu").
var window_id := ""
## Whether the title strip drags the window.
var draggable := true
## Height of the drag strip at the top.
var title_height := TITLE_H
## Let the stack place the window on its first open (see the class doc).
var auto_place := true

var _dragging := false
var _grab := Vector2.ZERO


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_NONE
	process_mode = Node.PROCESS_MODE_ALWAYS


## The local rect that drags the window (the title strip).
func title_rect() -> Rect2:
	return Rect2(0, 0, size.x, title_height)


## Where the window opens the first time in a view of `view` size: centred, above the status bar.
func default_position(view: Vector2) -> Vector2:
	var avail := Vector2(view.x, view.y - HudWidget.BAR_H)
	return ((avail - size) * 0.5).floor().max(Vector2.ZERO)


## True while the title strip is held.
func is_dragging() -> bool:
	return _dragging


## Asks the host stack to close this window.
func request_close() -> void:
	close_requested.emit()


## Mouse events after the base handled raise / drag; `local` = position in the window. Subclasses override.
func _window_gui_input(_event: InputEvent, _local: Vector2) -> void:
	pass


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			raised.emit()
			if draggable and title_rect().has_point(mb.position):
				_dragging = true
				_grab = mb.position
		else:
			_dragging = false
	var mm := event as InputEventMouseMotion
	if mm != null and _dragging:
		position = clamp_to_view(position + mm.position - _grab)
	if event is InputEventMouse:
		_window_gui_input(event, (event as InputEventMouse).position)
	if is_inside_tree():
		accept_event()


## `p` moved so the title strip stays in the view and KEEP_VISIBLE px of the window stay on screen horizontally.
func clamp_to_view(p: Vector2) -> Vector2:
	var view := _view_size()
	var keep := minf(KEEP_VISIBLE, size.x)
	return Vector2(clampf(p.x, keep - size.x, view.x - keep), clampf(p.y, 0.0, maxf(0.0, view.y - title_height))).round()


func _view_size() -> Vector2:
	var parent := get_parent() as Control
	if parent != null and parent.size != Vector2.ZERO:
		return parent.size
	return get_viewport_rect().size if is_inside_tree() else Vector2(GameSettings.BASE_VIEW)
