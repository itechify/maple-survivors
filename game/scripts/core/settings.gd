class_name GameSettings
extends Node
## Player settings stored in user://settings.cfg (autoload "Settings"; docs/ARCHITECTURE.md 4.2).
##
## Sections/keys: [assets] wz_root, cache_dir (read by AssetCachePaths too); [audio] master, bgm, sfx (linear 0..1);
## [display] window_scale (0 = project default 1600x1200), fill_window (bool), max_fps (0 = the display's refresh rate,
## -1 = uncapped, N = at most N frames/s; see apply_frame_cap); [controls] movement ("arrows" default or "wasd", see
## apply_movement); [input] <action> = physical keycodes
## (only rebound actions; the rest keep the project's input map). Loading never writes the file: it is saved only when
## a setter is called, so a missing file keeps every default (and never pins a cache_dir for other tools).
##
## Movement keys: only the chosen set (MOVEMENT_SETS) drives move_*, so the other set is free to bind (S opens the
## Stat window on Arrows). Applying a set also takes its keys off every other action (saved as bindings), so with WASD
## nothing else sits on W/A/S/D; switching back does not rebind them (the Key Config window's Default button does).
## Key Config / Options (later tickets) call set_binding / reset_binding / set_movement_keys.
##
## View (docs/ARCHITECTURE.md 4.5): by default the project's own stretch applies - 800x600 grown to the window's
## aspect ("expand", e.g. 1066x600 on 16:9), whole-pixel integer scale, black bars around the rest (1920x1080: 1x with
## 427/240 px bars; 3440x1440: 1433x600 at 2x). With fill_window on, the view instead grows to window / s (fit_size), so
## the window is filled at the same integer scale (3440x1440 -> 1720x720 at 2x, 1920x1080 -> 1920x1080 at 1x); this
## shows much more of the map, so it is opt-in. In both modes a window smaller than 800x600 on either axis is scaled
## down (fractional stretch) instead of cropped (Godot's integer stretch keeps 1x there and cuts the right and bottom,
## i.e. the status bar). The run must read the live view size (get_viewport().get_visible_rect().size).

## Emitted after any value changes.
signal changed

const PATH := "user://settings.cfg"
## The logical view the game is designed for (v83's 800x600; the project viewport size).
const BASE_VIEW := Vector2i(800, 600)
## Frame cap when the display's refresh rate is unknown, and the lowest cap a setting may ask for. The sim ticks at
## 60 Hz whatever the frame rate; frames past the refresh rate are never shown, they only heat the machine.
const FALLBACK_FPS := 144
const MIN_FPS := 30
## Movement key sets: scheme -> move action -> physical keycode. tier A: the v83 client moves with the arrows; WASD is
## our option (tier C).
const MOVEMENT_SETS := {
	"arrows": {"move_left": KEY_LEFT, "move_right": KEY_RIGHT, "move_up": KEY_UP, "move_down": KEY_DOWN},
	"wasd": {"move_left": KEY_A, "move_right": KEY_D, "move_up": KEY_W, "move_down": KEY_S},
}
const DEFAULT_MOVEMENT := "arrows"

var wz_root := ""
var cache_dir := ""
var master_volume := 1.0
var bgm_volume := 0.8
var sfx_volume := 0.9
var window_scale := 0
## Fill the window with more map instead of black bars (see the class doc; off = docs/ARCHITECTURE.md 4.5).
var fill_window := false
## Frame-rate cap: 0 = the display's refresh rate (FALLBACK_FPS when unknown), -1 = uncapped, N = N frames/s.
var max_fps := 0
## Movement key set: a MOVEMENT_SETS key ("arrows" or "wasd").
var movement_keys := DEFAULT_MOVEMENT
## Rebound actions: action name -> PackedInt32Array of physical keycodes (absent = the project's input map).
var bindings: Dictionary = {}

var _path := PATH
## Events an action had before this object first rebound it (for actions without a project-settings entry).
var _default_events: Dictionary = {}


func _init(p_path: String = PATH) -> void:
	_path = p_path
	load_settings()


func _ready() -> void:
	apply_bindings()
	apply_movement()
	apply_window_scale()
	apply_frame_cap(max_fps)
	var root := get_tree().root
	# Deferred: applying a new content size from inside the size_changed emission gets overwritten by the rest of
	# Godot's own viewport update for the resize (the blit rect stays at the old size, a non-integer stretch).
	root.size_changed.connect(fit_viewport, CONNECT_DEFERRED)
	fit_viewport()


## The view Godot's aspect "expand" makes of `base` for a window: the base grown along the window's wider axis
## (truncated like Godot: 1920x1080 -> 1066x600, 1600x1200 -> 800x600, 600x800 -> 800x1066).
static func expand_size(window: Vector2i, base: Vector2i = BASE_VIEW) -> Vector2i:
	if window.x <= 0 or window.y <= 0:
		return base
	if window.x * base.y >= window.y * base.x:
		return Vector2i(int(float(base.y) * window.x / window.y), base.y)
	return Vector2i(base.x, int(float(base.x) * window.y / window.x))


## Fill-window view size: s = floor(min(W / 800, H / 600)), view = floor(window / s). 1600x1200 -> 800x600,
## 3440x1440 -> 1720x720, 2560x1440 -> 1280x720, 1920x1080 -> 1920x1080. A window smaller than the base on either axis
## gets expand_size() (scaled down, see fit_viewport()).
@warning_ignore("integer_division")
static func fit_size(window: Vector2i, base: Vector2i = BASE_VIEW) -> Vector2i:
	if needs_downscale(window, base):
		return expand_size(window, base)
	var s := mini(window.x / base.x, window.y / base.y)
	return Vector2i(window.x / s, window.y / s)


## True when the window is smaller than the base view on either axis (then the view is scaled down, not cropped).
static func needs_downscale(window: Vector2i, base: Vector2i = BASE_VIEW) -> bool:
	return window.x < base.x or window.y < base.y


## Applies the view mode to the root viewport: content size BASE_VIEW (project stretch) or fit_size() with
## fill_window; fractional stretch only below the base size (no-op headless).
func fit_viewport() -> void:
	if DisplayServer.get_name() == "headless" or not is_inside_tree():
		return
	var root := get_tree().root
	var stretch := Window.CONTENT_SCALE_STRETCH_INTEGER
	if needs_downscale(root.size):
		stretch = Window.CONTENT_SCALE_STRETCH_FRACTIONAL
	if root.content_scale_stretch != stretch:
		root.content_scale_stretch = stretch
	var want := fit_size(root.size) if fill_window else BASE_VIEW
	if root.content_scale_size != want:
		root.content_scale_size = want


## Re-reads the file (keeps defaults for absent keys).
func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(_path) != OK:
		return
	wz_root = String(cfg.get_value("assets", "wz_root", wz_root))
	cache_dir = String(cfg.get_value("assets", "cache_dir", cache_dir))
	master_volume = clampf(float(cfg.get_value("audio", "master", master_volume)), 0.0, 1.0)
	bgm_volume = clampf(float(cfg.get_value("audio", "bgm", bgm_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cfg.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)
	window_scale = maxi(0, int(cfg.get_value("display", "window_scale", window_scale)))
	fill_window = bool(cfg.get_value("display", "fill_window", fill_window))
	max_fps = int(cfg.get_value("display", "max_fps", max_fps))
	var scheme := String(cfg.get_value("controls", "movement", movement_keys))
	movement_keys = scheme if MOVEMENT_SETS.has(scheme) else DEFAULT_MOVEMENT
	bindings = {}
	if cfg.has_section("input"):
		for action in cfg.get_section_keys("input"):
			var v: Variant = cfg.get_value("input", action)
			if v is Array or v is PackedInt32Array:
				var keys := PackedInt32Array()
				for k: Variant in v:
					keys.append(int(k))
				bindings[action] = keys


## Writes only the keys that differ from the defaults, merged into the existing file (other sections are kept).
func save_settings() -> Error:
	var cfg := ConfigFile.new()
	cfg.load(_path)
	_put(cfg, "assets", "wz_root", wz_root, "")
	_put(cfg, "assets", "cache_dir", cache_dir, "")
	_put(cfg, "audio", "master", master_volume, 1.0)
	_put(cfg, "audio", "bgm", bgm_volume, 0.8)
	_put(cfg, "audio", "sfx", sfx_volume, 0.9)
	_put(cfg, "display", "window_scale", window_scale, 0)
	_put(cfg, "display", "fill_window", fill_window, false)
	_put(cfg, "display", "max_fps", max_fps, 0)
	_put(cfg, "controls", "movement", movement_keys, DEFAULT_MOVEMENT)
	if cfg.has_section("input"):
		cfg.erase_section("input")
	for action: String in bindings:
		cfg.set_value("input", action, Array(bindings[action]))
	return cfg.save(_path)


## Sets a volume ("master", "bgm" or "sfx", linear 0..1) and saves.
func set_volume(which: String, v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	match which:
		"master":
			master_volume = v
		"bgm":
			bgm_volume = v
		"sfx":
			sfx_volume = v
		_:
			return
	save_settings()
	changed.emit()


## Sets the WZ folder and saves.
func set_wz_root(p: String) -> void:
	wz_root = p
	save_settings()
	changed.emit()


## Sets the integer window scale (0 = default) and saves.
func set_window_scale(s: int) -> void:
	window_scale = maxi(0, s)
	save_settings()
	changed.emit()


## Turns the fill-window view on or off, saves and re-fits the view.
func set_fill_window(on: bool) -> void:
	fill_window = on
	save_settings()
	fit_viewport()
	changed.emit()


## Sets the frame-rate cap (0 = refresh rate, -1 = uncapped, N), applies it and saves.
func set_max_fps(n: int) -> void:
	max_fps = maxi(-1, n)
	apply_frame_cap(max_fps)
	save_settings()
	changed.emit()


## Engine.max_fps for a max_fps setting: 0 = the display's refresh rate rounded up (FALLBACK_FPS when it is unknown,
## i.e. <= 0), -1 (any negative) = 0 (uncapped), else the setting (at least MIN_FPS).
static func frame_cap(setting: int, refresh_rate: float) -> int:
	if setting < 0:
		return 0
	if setting > 0:
		return maxi(MIN_FPS, setting)
	return ceili(refresh_rate) if refresh_rate >= float(MIN_FPS) else FALLBACK_FPS


## Turns vsync on and caps the frame rate at frame_cap(setting, the current screen's refresh rate) - the cap holds even
## where the driver ignores the swap interval (seen with GL Compatibility on Windows: 300-1300 fps with vsync "on").
## `uncapped` (--vsync=off perf runs, setting -1) turns vsync off and removes the cap. No-op headless.
static func apply_frame_cap(setting: int, uncapped: bool = false) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if uncapped or setting < 0:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	var screen := DisplayServer.window_get_current_screen()
	Engine.max_fps = frame_cap(setting, DisplayServer.screen_get_refresh_rate(screen))


## Rebinds an action to physical keycodes (e.g. [KEY_ALT, KEY_SPACE]), applies it to the InputMap and saves.
func set_binding(action: String, keys: PackedInt32Array) -> void:
	bindings[action] = keys.duplicate()
	apply_bindings()
	save_settings()
	changed.emit()


## Picks the movement key set ("arrows" or "wasd"; others are ignored), applies it and saves.
func set_movement_keys(scheme: String) -> void:
	if not MOVEMENT_SETS.has(scheme):
		return
	movement_keys = scheme
	apply_movement()
	save_settings()
	changed.emit()


## Binds move_* to the movement_keys set only and takes those keys off every other action (Godot's ui_* excepted);
## the stripped actions are recorded in `bindings` (saved by the next save_settings).
func apply_movement() -> void:
	var moves: Dictionary = MOVEMENT_SETS.get(movement_keys, MOVEMENT_SETS[DEFAULT_MOVEMENT])
	var taken := PackedInt32Array()
	for code: int in moves.values():
		taken.append(code)
	var stripped := false
	for action: StringName in InputMap.get_actions():
		var a := String(action)
		if moves.has(a) or a.begins_with("ui_"):
			continue
		var keys := binding_keys(a)
		var kept := PackedInt32Array()
		for k in keys:
			if not (k in taken):
				kept.append(k)
		if kept.size() != keys.size():
			bindings[a] = kept
			stripped = true
	if stripped:
		apply_bindings()
	for a: String in moves:
		if not InputMap.has_action(a):
			continue
		InputMap.action_erase_events(a)
		var ev := InputEventKey.new()
		ev.physical_keycode = moves[a] as Key
		InputMap.action_add_event(a, ev)


## Restores an action's project default keys and saves.
func reset_binding(action: String) -> void:
	if not bindings.has(action):
		return
	bindings.erase(action)
	_restore_default(action)
	save_settings()
	changed.emit()


## The physical keycodes an action currently has in the InputMap (empty for an unknown action).
func binding_keys(action: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	if not InputMap.has_action(action):
		return out
	for e in InputMap.action_get_events(action):
		if e is InputEventKey:
			var k := e as InputEventKey
			out.append(k.physical_keycode if k.physical_keycode != KEY_NONE else k.keycode)
	return out


## Writes every rebound action into the InputMap (actions the project does not define are ignored, but kept in the
## file). Other actions keep their project events.
func apply_bindings() -> void:
	for action: String in bindings:
		if not InputMap.has_action(action):
			continue
		if not _default_events.has(action):
			_default_events[action] = InputMap.action_get_events(action)
		InputMap.action_erase_events(action)
		for code in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code as Key
			InputMap.action_add_event(action, ev)


func _restore_default(action: String) -> void:
	if not InputMap.has_action(action):
		return
	var events: Array = []
	var proj: Variant = ProjectSettings.get_setting("input/" + action, null)
	if proj is Dictionary and (proj as Dictionary).get("events") is Array:
		events = proj.events
	elif _default_events.has(action):
		events = _default_events[action]
	else:
		return
	InputMap.action_erase_events(action)
	for e: InputEvent in events:
		InputMap.action_add_event(action, e)


## Applies window_scale to the main window (800x600 x scale, centred); no-op headless or when 0.
func apply_window_scale() -> void:
	if window_scale <= 0 or DisplayServer.get_name() == "headless":
		return
	var size := Vector2i(800, 600) * window_scale
	DisplayServer.window_set_size(size)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


static func _put(cfg: ConfigFile, section: String, key: String, value: Variant, default: Variant) -> void:
	if value == default:
		if cfg.has_section_key(section, key):
			cfg.erase_section_key(section, key)
	else:
		cfg.set_value(section, key, value)
