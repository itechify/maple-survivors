extends TestCase
## The Key Config draft (KeyBindings, no scene): a key holds one action, an action may hold several keys, fixed keys
## (movement, Esc, the card keys 1-3) cannot be bound, Default restores the project defaults, Cancel (dropping the
## draft) leaves the saved bindings alone, and OK round-trips through Settings' save / load.

var cfg_path := TestCase.test_dir("key_config_test.cfg")
var _saved_map: Dictionary = {}


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	# Settings writes the global InputMap that the live Settings autoload also uses: restored after every test.
	_saved_map = {}
	for a: StringName in InputMap.get_actions():
		_saved_map[a] = InputMap.action_get_events(a).duplicate()


func after_each() -> void:
	for a: StringName in _saved_map:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
			for e: InputEvent in _saved_map[a]:
				InputMap.action_add_event(a, e)


func _defaults() -> KeyBindings:
	var kb := KeyBindings.new({}, "arrows")
	kb.reset_defaults()
	return kb


func test_binding_a_key_replaces_its_previous_action() -> void:
	var kb := _defaults()
	assert_eq(kb.action_on(KEY_Q), "drink_hp", "default: Q drinks an HP potion")
	assert_true(kb.bind("teleport", KEY_Q))
	assert_eq(kb.action_on(KEY_Q), "teleport", "Q now teleports")
	assert_eq(kb.keys_of("drink_hp"), PackedInt32Array([KEY_DELETE]), "the HP potion lost Q, kept Del")
	assert_eq(kb.keys_of("teleport"), PackedInt32Array([KEY_X, KEY_Q]))


func test_an_action_can_sit_on_several_keys() -> void:
	var kb := _defaults()
	assert_true(kb.bind("jump", KEY_F))
	assert_true(kb.bind("jump", KEY_G))
	assert_eq(kb.keys_of("jump"), PackedInt32Array([KEY_ALT, KEY_SPACE, KEY_C, KEY_F, KEY_G]))
	assert_eq(kb.action_on(KEY_SPACE), "jump", "the old keys stay")
	assert_eq(kb.unbind(KEY_SPACE), "jump")
	assert_eq(kb.action_on(KEY_SPACE), "", "Space unbound")
	assert_eq(kb.unbind(KEY_SPACE), "", "unbinding a free key does nothing")


func test_fixed_keys_cannot_be_bound() -> void:
	var kb := _defaults()
	for k: int in [KEY_ESCAPE, KEY_1, KEY_2, KEY_3, KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN]:
		assert_true(kb.is_fixed(k), OS.get_keycode_string(k))
		assert_false(kb.bind("jump", k), "%s refused" % OS.get_keycode_string(k))
		assert_eq(kb.action_on(k), "")
	assert_false(kb.is_fixed(KEY_W), "Arrows: W is free")
	assert_false(kb.bind("move_left", KEY_F), "movement itself is not bindable")
	assert_false(kb.bind("pause", KEY_F))
	assert_eq(kb.fixed_label(KEY_ESCAPE), "Menu")
	assert_eq(kb.fixed_label(KEY_2), "Card 2")
	assert_eq(kb.fixed_label(KEY_LEFT), "Move")
	assert_eq(kb.fixed_label(KEY_F), "", "not fixed")
	var wasd := KeyBindings.new({}, "wasd")
	wasd.reset_defaults()
	for k: int in [KEY_W, KEY_A, KEY_S, KEY_D]:
		assert_true(wasd.is_fixed(k), "WASD: %s is movement" % OS.get_keycode_string(k))
		assert_false(wasd.bind("jump", k))
	assert_false(wasd.is_fixed(KEY_LEFT), "WASD: the arrows are free to bind")
	assert_true(wasd.bind("jump", KEY_UP))


func test_default_restores_the_project_keys_less_the_movement_set() -> void:
	var kb := _defaults()
	kb.bind("teleport", KEY_Q)
	kb.unbind(KEY_SPACE)
	kb.bind("stat_window", KEY_F)
	kb.reset_defaults()
	assert_eq(kb.keys_of("jump"), PackedInt32Array([KEY_ALT, KEY_SPACE, KEY_C]))
	assert_eq(kb.keys_of("drink_hp"), PackedInt32Array([KEY_DELETE, KEY_Q]))
	assert_eq(kb.keys_of("drink_mp"), PackedInt32Array([KEY_END, KEY_E]))
	assert_eq(kb.keys_of("teleport"), PackedInt32Array([KEY_X]))
	assert_eq(kb.keys_of("stat_window"), PackedInt32Array([KEY_S]))
	assert_eq(kb.keys_of("skill_window"), PackedInt32Array([KEY_K]))
	var wasd := KeyBindings.new({}, "wasd")
	wasd.reset_defaults()
	assert_eq(wasd.keys_of("stat_window"), PackedInt32Array(), "WASD: S is movement, so Stat has no default key")
	assert_eq(wasd.keys_of("skill_window"), PackedInt32Array([KEY_K]))


func test_ok_saves_and_applies_and_round_trips_through_settings() -> void:
	var s := GameSettings.new(cfg_path)
	var kb := KeyBindings.from_settings(s)
	assert_eq(kb.keys_of("jump"), PackedInt32Array([KEY_ALT, KEY_SPACE, KEY_C]), "no saved bindings: the defaults")
	kb.unbind(KEY_SPACE)
	kb.bind("jump", KEY_F)
	kb.bind("drink_mp", KEY_Q)
	kb.apply_to(s)
	assert_eq(s.binding_keys("jump"), PackedInt32Array([KEY_ALT, KEY_C, KEY_F]), "applied to the InputMap at once")
	assert_eq(s.binding_keys("drink_hp"), PackedInt32Array([KEY_DELETE]))
	assert_eq(s.binding_keys("drink_mp"), PackedInt32Array([KEY_END, KEY_E, KEY_Q]))
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(cfg_path), OK, "saved")
	assert_false(cfg.has_section_key("input", "teleport"), "unchanged actions are not written")
	var t := GameSettings.new(cfg_path)
	var loaded := KeyBindings.from_settings(t)
	for a: String in KeyBindings.BINDABLE:
		assert_eq(loaded.keys_of(a), kb.keys_of(a), "%s round-trips" % a)
	t.free()
	s.free()


func test_cancel_leaves_the_saved_bindings_unchanged() -> void:
	var s := GameSettings.new(cfg_path)
	s.set_binding("jump", PackedInt32Array([KEY_F]))
	var before := FileAccess.get_file_as_string(cfg_path)
	var kb := KeyBindings.from_settings(s)
	assert_eq(kb.keys_of("jump"), PackedInt32Array([KEY_F]), "the draft starts from the saved bindings")
	kb.bind("jump", KEY_G)
	kb.reset_defaults()
	kb = null # Cancel: the draft is dropped
	assert_eq(FileAccess.get_file_as_string(cfg_path), before, "the file is untouched")
	assert_eq(s.binding_keys("jump"), PackedInt32Array([KEY_F]), "the InputMap is untouched")
	s.free()


func test_default_puts_s_back_on_stat_after_wasd_and_back() -> void:
	var s := GameSettings.new(cfg_path)
	s.set_movement_keys("wasd")
	assert_eq(s.binding_keys("stat_window"), PackedInt32Array(), "WASD took S off Stat")
	s.set_movement_keys("arrows")
	var kb := KeyBindings.from_settings(s)
	assert_eq(kb.keys_of("stat_window"), PackedInt32Array(), "switching back did not rebind it")
	kb.reset_defaults()
	kb.apply_to(s)
	assert_eq(s.binding_keys("stat_window"), PackedInt32Array([KEY_S]), "Default + OK: S opens Stat again")
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	assert_false(cfg.has_section("input"), "every action is back on its default: no overrides saved")
	s.free()


func test_ok_never_saves_a_fixed_key() -> void:
	var s := GameSettings.new(cfg_path)
	var kb := KeyBindings.from_settings(s)
	kb.bind("jump", KEY_W)
	s.set_movement_keys("wasd") # Options switched movement while the Key Config draft was open
	kb.apply_to(s)
	assert_false(KEY_W in s.binding_keys("jump"), "W is movement now")
	assert_eq(s.binding_keys("move_up"), PackedInt32Array([KEY_W]))
	s.free()


func test_hud_key_labels_read_the_live_bindings() -> void:
	assert_eq(KeyBindings.key_name(KEY_DELETE), "Del")
	assert_eq(KeyBindings.key_name(KEY_END), "End")
	assert_eq(KeyBindings.key_name(KEY_PAGEDOWN), "PgDn")
	assert_eq(KeyBindings.key_name(KEY_Q), "Q")
	var s := GameSettings.new(cfg_path)
	s.set_bindings({"drink_hp": PackedInt32Array([KEY_DELETE, KEY_Q])})
	assert_eq(KeyBindings.action_label("drink_hp"), "Del / Q")
	s.set_bindings({"drink_hp": PackedInt32Array([KEY_F]), "drink_mp": PackedInt32Array()})
	assert_eq(KeyBindings.action_label("drink_hp"), "F", "rebinding changes the label")
	assert_eq(KeyBindings.action_label("drink_mp"), "-", "an unbound action")
	var slot := HudPotionQuickslot.new()
	slot.update({"potions": {"hp": {"item_id": 0, "count": 3}, "mp": {"item_id": 0, "count": 0}}}, {})
	assert_eq(slot.displayed("hp").key_label, "F", "the HUD potion quickslot shows the rebound key")
	assert_eq(slot.displayed("mp").key_label, "-")
	slot.free()
	s.free()
