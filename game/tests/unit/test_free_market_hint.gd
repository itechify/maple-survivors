extends TestCase
## The real hub's instruction plate follows live movement/chat keys. InputMap and settings are restored; no saves.

var _saved_map: Dictionary = {}
var _settings: GameSettings
var _movement: String
var _bindings: Dictionary


func before_each() -> void:
	_settings = (Engine.get_main_loop() as SceneTree).root.get_node("Settings") as GameSettings
	_movement = _settings.movement_keys
	_bindings = _settings.bindings.duplicate(true)
	for action: StringName in InputMap.get_actions():
		_saved_map[action] = InputMap.action_get_events(action).duplicate()


func after_each() -> void:
	_settings.movement_keys = _movement
	_settings.bindings = _bindings
	for action: StringName in _saved_map:
		InputMap.action_erase_events(action)
		for event: InputEvent in _saved_map[action]:
			InputMap.action_add_event(action, event)
	_saved_map.clear()


func test_hint_refreshes_on_settings_changes_and_explains_unbound_chat() -> void:
	if not require_cache():
		return
	InputMap.load_from_project_settings()
	_settings.movement_keys = "arrows"
	_settings.apply_movement()
	var hub := FreeMarket.new()
	var character := DataRepo.load_json("res://tests/fixtures/characters/fp_arch_mage.json") as Dictionary
	hub.configure({"name": "Hint", "character": character}, null)
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(hub)
	hub.set_process(false)
	var hint: MapleText
	for label: Node in hub.find_children("*", "Label", true, false):
		if label is MapleText and (label as MapleText).text.begins_with("Free Market  /"):
			hint = label as MapleText
	assert_true(hint != null)
	if hint != null:
		assert_eq(hint.text, "Free Market  /  Up at the exit: next map  /  Space: talk to a scroll NPC  /  Esc: Save & quit")
		assert_eq(hint.position, Vector2(12, 12), "the default plate keeps its inset")
		_settings.movement_keys = "wasd"
		_settings.apply_movement()
		_settings.changed.emit() # same signal as Options, without writing any settings file
		assert_true("W at the exit" in hint.text, "Options changes the displayed exit key immediately")
		InputMap.action_erase_events("npc_chat")
		var key := InputEventKey.new()
		key.physical_keycode = KEY_F
		InputMap.action_add_event("npc_chat", key)
		_settings.changed.emit()
		assert_true("F: talk to a scroll NPC" in hint.text, "a rebind refreshes without rebuilding the hub")
		assert_false("Space:" in hint.text)
		InputMap.action_erase_events("npc_chat")
		_settings.changed.emit()
		assert_true("NPC Chat unbound" in hint.text, "a missing key is explicit")
		assert_true("double-click" in hint.text, "the working mouse alternative is explained")
		assert_false("Space:" in hint.text)
		_settings.movement_keys = "arrows"
		_settings.apply_movement()
		_settings.changed.emit()
		assert_true("Up at the exit" in hint.text, "the hint follows a second movement change too")
	hub.free()
