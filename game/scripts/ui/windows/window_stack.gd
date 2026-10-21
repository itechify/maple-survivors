class_name WindowStack
extends Control
## The in-run window system: hosts the non-modal UiWindows (Stat, Skill, Key Config, Options and the status bar's
## Menu popup), keeps them stacked and lets them be dragged and brought to the front. RunScene puts one in its own
## CanvasLayer above the modal windows (level-up / job / pause) and holds the sim while `has_windows()`.
##
## Interface:
##   stack.register("stat", func() -> UiWindow: return StatWindow.new(...))   # once per window kind (RunScene setup)
##   stack.toggle("stat")    # hotkey / Menu entry: opens a new window from the factory, or closes the open one
##   stack.close_top()       # Esc: closes the front window; false when none is open (then Esc opens the pause menu)
##   stack.open(window)      # open a window that is not registered (the Menu popup); an id already open is replaced
##   stack.close("stat"), stack.find_window("stat"), stack.top(), stack.ids(), stack.has_windows(), stack.can_open(id)
## `changed` is emitted after every open, close and reorder (RunScene re-syncs the pause and the modal's input then).
##
## Order: the children's order is the stacking order (the last child is drawn on top and is `top()`); a left press in
## a window brings it to the front. A closed window's position is remembered per id, so it reopens where it was
## dragged (v83 windows do the same). The stack itself never takes the mouse (MOUSE_FILTER_IGNORE): clicks outside
## the windows reach whatever is below (the HUD's Menu button, a level-up window).

## Emitted after a window opened, closed or moved to the front.
signal changed()

var _factories: Dictionary = {}
var _positions: Dictionary = {}


func _init() -> void:
	name = "WindowStack"
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	resized.connect(_clamp_windows)


## Registers the factory that makes window `id` (a Callable returning a UiWindow).
func register(id: String, factory: Callable) -> void:
	_factories[id] = factory


## True when a window is registered under `id` (the Menu popup disables the entries that are not).
func can_open(id: String) -> bool:
	return _factories.has(id)


## Opens `w` on top (an open window with the same id is closed first) and returns it.
func open(w: UiWindow) -> UiWindow:
	if w.window_id != "" and find_window(w.window_id) != null:
		_remove(find_window(w.window_id))
	if w.auto_place:
		w.position = _positions.get(w.window_id, w.default_position(_view_size()))
	add_child(w)
	w.position = w.clamp_to_view(w.position)
	w.raised.connect(bring_to_front.bind(w))
	w.close_requested.connect(_close_window.bind(w))
	changed.emit()
	return w


## Opens registered window `id` when it is closed (true), closes it when open (false). False for unknown ids.
func toggle(id: String) -> bool:
	if find_window(id) != null:
		close(id)
		return false
	if not can_open(id):
		return false
	var w: UiWindow = (_factories[id] as Callable).call()
	if w == null:
		return false
	w.window_id = id
	open(w)
	return true


## Closes window `id`; false when it is not open.
func close(id: String) -> bool:
	var w := find_window(id)
	if w == null:
		return false
	_remove(w)
	changed.emit()
	return true


## Closes the front window (Esc); false when none is open.
func close_top() -> bool:
	var w := top()
	if w == null:
		return false
	_remove(w)
	changed.emit()
	return true


## Closes every window (end of the run).
func close_all() -> void:
	var any := false
	for w in windows():
		_remove(w)
		any = true
	if any:
		changed.emit()


## Moves `w` to the front (no-op when it already is).
func bring_to_front(w: UiWindow) -> void:
	if w.get_parent() != self or top() == w:
		return
	move_child(w, -1)
	changed.emit()


## The open window with this id, or null.
func find_window(id: String) -> UiWindow:
	for w in windows():
		if w.window_id == id:
			return w
	return null


## The front window, or null.
func top() -> UiWindow:
	var all := windows()
	return all[all.size() - 1] if not all.is_empty() else null


## The open windows, bottom to top.
func windows() -> Array[UiWindow]:
	var out: Array[UiWindow] = []
	for c in get_children():
		if c is UiWindow and not c.is_queued_for_deletion():
			out.append(c)
	return out


## The open windows' ids, bottom to top.
func ids() -> PackedStringArray:
	var out := PackedStringArray()
	for w in windows():
		out.append(w.window_id)
	return out


## True while any window is open (the run holds its sim).
func has_windows() -> bool:
	return not windows().is_empty()


func _close_window(w: UiWindow) -> void:
	if is_instance_valid(w) and w.get_parent() == self:
		_remove(w)
		changed.emit()


func _remove(w: UiWindow) -> void:
	if w.window_id != "" and w.auto_place:
		_positions[w.window_id] = w.position
	remove_child(w)
	w.queue_free()


func _clamp_windows() -> void:
	for w in windows():
		w.position = w.clamp_to_view(w.position)


func _view_size() -> Vector2:
	if size != Vector2.ZERO:
		return size
	return get_viewport_rect().size if is_inside_tree() else Vector2(GameSettings.BASE_VIEW)
