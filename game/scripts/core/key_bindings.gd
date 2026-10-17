class_name KeyBindings
extends RefCounted
## The Key Config window's draft of the player's key bindings (no scene, no InputMap reads): which keys each bindable
## action sits on. A key holds one action; an action may sit on several keys. key_name() is the caption of one key;
## the live bindings' captions are GameSettings.action_label().
##
##   var kb := KeyBindings.from_settings(Settings)   # the saved bindings (or the project defaults) and movement set
##   kb.bind("jump", KEY_F)       # F now jumps (whatever F did before loses it); false for a fixed or unknown key
##   kb.unbind(KEY_F)             # F does nothing (returns the action it held)
##   kb.reset_defaults()          # the Default button
##   kb.apply_to(Settings)        # OK: saved and applied at once; Cancel just drops the draft

## The actions the player may rebind, in tray order.
const BINDABLE := ["jump", "drink_hp", "drink_mp", "teleport", "equip_window", "item_window", "stat_window",
	"skill_window"]
## Fixed actions (shown on their keys, never rebound) -> the label the window shows: Esc and the card keys keep their
## project keys; movement uses the movement set (see fixed_keys()).
const FIXED_LABELS := {"pause": "Menu", "choice_1": "Card 1", "choice_2": "Card 2", "choice_3": "Card 3"}
const MOVE_LABEL := "Move"

## Bindable action -> its keys (PackedInt32Array of physical keycodes, in the order they were bound).
var keys: Dictionary = {}
## The movement set ("arrows" / "wasd", GameSettings.MOVEMENT_SETS) whose keys are fixed.
var movement := GameSettings.DEFAULT_MOVEMENT


func _init(p_keys: Dictionary = {}, p_movement: String = GameSettings.DEFAULT_MOVEMENT) -> void:
	movement = p_movement
	for a: String in BINDABLE:
		keys[a] = PackedInt32Array(p_keys.get(a, PackedInt32Array()))


## Short key names for HUD labels (the v83 keyboard's captions); other keys use OS.get_keycode_string.
const SHORT_NAMES := {KEY_DELETE: "Del", KEY_INSERT: "Ins", KEY_PAGEUP: "PgUp", KEY_PAGEDOWN: "PgDn",
	KEY_ESCAPE: "Esc", KEY_BACKSPACE: "Bksp", KEY_CAPSLOCK: "Caps", KEY_QUOTELEFT: "`", KEY_CTRL: "Ctrl",
	KEY_ENTER: "Enter", KEY_PAUSE: "Brk", KEY_PRINT: "Psc"}


## The HUD caption of a physical keycode ("Del", "PgDn", "Q", "Space").
static func key_name(code: int) -> String:
	if SHORT_NAMES.has(code):
		return String(SHORT_NAMES[code])
	return OS.get_keycode_string(code as Key)


## The keys of `action` (a copy; empty when unbound or not bindable).
func keys_of(action: String) -> PackedInt32Array:
	return PackedInt32Array(keys.get(action, PackedInt32Array()))


## The bindable action on `key`, or "".
func action_on(key: int) -> String:
	for a: String in BINDABLE:
		if key in (keys[a] as PackedInt32Array):
			return a
	return ""


## Binds `action` to `key`, taking the key off whatever action held it. False (nothing changes) for an action that is
## not bindable or a fixed key.
func bind(action: String, key: int) -> bool:
	if not keys.has(action) or is_fixed(key):
		return false
	unbind(key)
	var k: PackedInt32Array = keys[action]
	k.append(key)
	keys[action] = k
	return true


## Takes `key` off its action; returns that action ("" when the key held none).
func unbind(key: int) -> String:
	var a := action_on(key)
	if a != "":
		var k: PackedInt32Array = keys[a]
		k.remove_at(k.find(key))
		keys[a] = k
	return a


## The draft of `settings`: its saved bindings (the project defaults for actions it never rebound) and movement set.
## Fixed keys are left out.
static func from_settings(settings: GameSettings) -> KeyBindings:
	var saved := {}
	for a: String in BINDABLE:
		saved[a] = settings.bindings.get(a, GameSettings.default_keys(a))
	var kb := KeyBindings.new(saved, settings.movement_keys)
	kb._drop_fixed()
	return kb


## The Default button: every bindable action back on its project keys, less the keys the movement set fixes (with
## WASD, S is movement, so Stat has no default key there; on Arrows Default puts S back on Stat).
func reset_defaults() -> void:
	for a: String in BINDABLE:
		keys[a] = GameSettings.default_keys(a)
	_drop_fixed()


## OK: writes the draft into `settings` (GameSettings.set_bindings: applied to the InputMap and saved). Keys that are
## fixed under the settings' current movement set (switched in Options while this draft was open) are dropped first.
func apply_to(settings: GameSettings) -> void:
	movement = settings.movement_keys
	_drop_fixed()
	settings.set_bindings(keys)


## Follows a movement-set change (Options): the new set's keys become fixed and leave their actions.
func set_movement(scheme: String) -> void:
	if GameSettings.MOVEMENT_SETS.has(scheme):
		movement = scheme
		_drop_fixed()


func _drop_fixed() -> void:
	var fixed := fixed_keys()
	for a: String in BINDABLE:
		var kept := PackedInt32Array()
		for k in (keys[a] as PackedInt32Array):
			if not fixed.has(k):
				kept.append(k)
		keys[a] = kept


## Fixed key -> its label: the movement set's keys ("Move"), Esc ("Menu") and the card keys 1-3 ("Card N").
func fixed_keys() -> Dictionary:
	var out := {}
	for a: String in FIXED_LABELS:
		for k in GameSettings.default_keys(a):
			out[k] = FIXED_LABELS[a]
	var sets := GameSettings.MOVEMENT_SETS
	var moves: Dictionary = sets.get(movement, sets[GameSettings.DEFAULT_MOVEMENT])
	for k: int in moves.values():
		out[k] = MOVE_LABEL
	return out


## True when `key` is fixed (cannot be bound).
func is_fixed(key: int) -> bool:
	return fixed_keys().has(key)


## The label of a fixed key ("" when the key is not fixed).
func fixed_label(key: int) -> String:
	return String(fixed_keys().get(key, ""))
