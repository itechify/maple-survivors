extends TestCase
## The Key Config draft (KeyBindings, no scene): a key holds one action, an action may hold several keys, fixed keys
## (movement, Esc, the card keys 1-3) cannot be bound, Default restores the project defaults, Cancel (dropping the
## draft) leaves the saved bindings alone, and OK round-trips through Settings' save / load. The HUD's key labels read
## the live bindings and follow OK at once.

const RF := preload("res://tests/fixtures/run_fixtures.gd")

var cfg_path := TestCase.test_dir("key_config_test.cfg")
var _saved_map: Dictionary = {}


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(cfg_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path + suffix))
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
	var kb := KeyBindings.new({}, "arrows", ["teleport"])
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
	assert_eq(kb.keys_of("jump"), PackedInt32Array([KEY_ALT, KEY_C, KEY_F, KEY_G]))
	assert_eq(kb.action_on(KEY_C), "jump", "the old keys stay")
	assert_eq(kb.unbind(KEY_C), "jump")
	assert_eq(kb.action_on(KEY_C), "", "C unbound")
	assert_eq(kb.unbind(KEY_C), "", "unbinding a free key does nothing")


func test_space_is_npc_chat_and_can_be_rebound() -> void:
	var kb := _defaults()
	assert_eq(kb.action_on(KEY_SPACE), "npc_chat", "v83: Space is NPC Chat, not jump (#111)")
	assert_false(KEY_SPACE in kb.keys_of("jump"))
	assert_true("npc_chat" in KeyBindings.BINDABLE)
	assert_true(kb.bind("npc_chat", KEY_N), "NPC Chat can be rebound")
	assert_eq(kb.keys_of("npc_chat"), PackedInt32Array([KEY_SPACE, KEY_N]))
	assert_true(kb.bind("jump", KEY_SPACE), "and Space can be given to another action")
	assert_eq(kb.keys_of("npc_chat"), PackedInt32Array([KEY_N]))
	var s := GameSettings.new(cfg_path)
	var draft := KeyBindings.from_settings(s)
	draft.unbind(KEY_SPACE)
	draft.bind("npc_chat", KEY_N)
	draft.apply_to(s)
	assert_eq(s.binding_keys("npc_chat"), PackedInt32Array([KEY_N]), "applied to the InputMap at once")
	var t := GameSettings.new(cfg_path)
	assert_eq(KeyBindings.from_settings(t).keys_of("npc_chat"), PackedInt32Array([KEY_N]), "saved and loaded")
	t.free()
	s.free()


func test_a_settings_file_that_still_holds_space_on_jump_keeps_it_there() -> void:
	# Saved before NPC Chat took Space: jump still holds it, so Space must not also talk to NPCs.
	var cfg := ConfigFile.new()
	cfg.set_value("input", "jump", [KEY_ALT, KEY_SPACE, KEY_C])
	cfg.save(cfg_path)
	var s := GameSettings.new(cfg_path)
	assert_eq(s.bindings.get("npc_chat"), PackedInt32Array(), "NPC Chat yields Space to the action that was rebound to it")
	s.apply_bindings()
	assert_eq(s.binding_keys("npc_chat"), PackedInt32Array())
	assert_eq(s.binding_keys("jump"), PackedInt32Array([KEY_ALT, KEY_SPACE, KEY_C]))
	assert_eq(KeyBindings.from_settings(s).action_on(KEY_SPACE), "jump")
	s.free()


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


func test_f3_is_reserved_for_performance_and_old_saved_bindings_lose_it() -> void:
	var kb := _defaults()
	assert_true(kb.is_fixed(KEY_F3), "F3 belongs to the performance overlay")
	assert_eq(kb.fixed_label(KEY_F3), "Perf", "Key Config explains the reserved key")
	for action: String in kb.actions():
		assert_false(kb.bind(action, KEY_F3), "%s cannot take F3" % action)
	var cfg := ConfigFile.new()
	cfg.set_value("input", "stat_window", [KEY_S, KEY_F3])
	cfg.set_value("input", "drink_hp", [KEY_F3])
	cfg.save(cfg_path)
	var s := GameSettings.new(cfg_path)
	s.apply_bindings()
	assert_eq(s.binding_keys("stat_window"), PackedInt32Array([KEY_S]), "legacy bindings keep their other keys")
	assert_eq(s.binding_keys("drink_hp"), PackedInt32Array(), "F3 cannot also latch a potion")
	assert_eq(GameSettings.action_label("stat_window"), "S", "live labels no longer advertise F3")
	s.free()


func test_default_restores_the_project_keys_less_the_movement_set() -> void:
	var kb := _defaults()
	kb.bind("teleport", KEY_Q)
	kb.unbind(KEY_SPACE)
	kb.bind("stat_window", KEY_F)
	kb.reset_defaults()
	assert_eq(kb.keys_of("jump"), PackedInt32Array([KEY_ALT, KEY_C]), "v83: Alt jumps, Space is NPC Chat")
	assert_eq(kb.keys_of("npc_chat"), PackedInt32Array([KEY_SPACE]), "v83: Space is the NPC Chat key (#111)")
	assert_eq(kb.keys_of("drink_hp"), PackedInt32Array([KEY_DELETE, KEY_Q]))
	assert_eq(kb.action_on(KEY_END), "", "no MP potion action (no MP, #285): End is free")
	assert_false("drink_mp" in kb.actions(), "the MP potion is not bindable")
	assert_eq(kb.keys_of("teleport"), PackedInt32Array([KEY_X]))
	assert_eq(kb.keys_of("stat_window"), PackedInt32Array([KEY_S]))
	assert_eq(kb.keys_of("skill_window"), PackedInt32Array([KEY_K]))
	assert_eq(kb.keys_of("equip_window"), PackedInt32Array([KEY_E]), "v83: E opens the Equip window")
	assert_eq(kb.keys_of("item_window"), PackedInt32Array([KEY_I]), "v83: I opens the Item window")
	assert_true(kb.bind("item_window", KEY_F), "the window keys can be rebound")
	assert_eq(kb.keys_of("item_window"), PackedInt32Array([KEY_I, KEY_F]))
	var wasd := KeyBindings.new({}, "wasd")
	wasd.reset_defaults()
	assert_eq(wasd.keys_of("stat_window"), PackedInt32Array(), "WASD: S is movement, so Stat has no default key")
	assert_eq(wasd.keys_of("skill_window"), PackedInt32Array([KEY_K]))


func test_ok_saves_and_applies_and_round_trips_through_settings() -> void:
	var s := GameSettings.new(cfg_path)
	var kb := KeyBindings.from_settings(s)
	assert_eq(kb.keys_of("jump"), PackedInt32Array([KEY_ALT, KEY_C]), "no saved bindings: the defaults")
	kb.unbind(KEY_SPACE)
	kb.bind("jump", KEY_F)
	kb.bind("item_window", KEY_Q)
	kb.apply_to(s)
	assert_eq(s.binding_keys("jump"), PackedInt32Array([KEY_ALT, KEY_C, KEY_F]), "applied to the InputMap at once")
	assert_eq(s.binding_keys("drink_hp"), PackedInt32Array([KEY_DELETE]))
	assert_eq(s.binding_keys("item_window"), PackedInt32Array([KEY_I, KEY_Q]))
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


## reload_from is how the test runner drops the developer's own settings.cfg (#103): every field, the InputMap and the
## save path end up as a fresh GameSettings on that path, and `changed` tells listeners (audio volumes) to re-read.
func test_reload_from_a_missing_file_restores_every_default_and_the_project_keys() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("assets", "wz_root", "C:/wz")
	cfg.set_value("assets", "cache_dir", "C:/cache")
	cfg.set_value("audio", "master", 0.5)
	cfg.set_value("audio", "bgm", 0.1)
	cfg.set_value("audio", "sfx", 0.2)
	cfg.set_value("display", "window_scale", 2)
	cfg.set_value("display", "fill_window", true)
	cfg.set_value("display", "max_fps", 60)
	cfg.set_value("controls", "movement", "wasd")
	cfg.set_value("input", "jump", [KEY_Z])
	cfg.set_value("input", "teleport", [KEY_SPACE])
	cfg.save(cfg_path)
	var s := GameSettings.new(cfg_path)
	s.apply_bindings()
	s.apply_movement()
	assert_eq(s.binding_keys("teleport"), PackedInt32Array([KEY_SPACE]), "the file's rebinds are live")
	var emitted := [0]
	s.changed.connect(func() -> void: emitted[0] += 1)
	var missing := TestCase.test_dir("no_such_settings.cfg")
	s.reload_from(missing)
	assert_eq(emitted[0], 1, "changed emitted once")
	var fresh := GameSettings.new(missing)
	for p: Dictionary in s.get_script().get_script_property_list():
		if p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			assert_eq(s.get(p.name), fresh.get(p.name), "%s back to its default" % p.name)
	for action in ["jump", "teleport", "move_left", "move_up"]:
		assert_eq(s.binding_keys(action), GameSettings.default_keys(action), "%s has its project keys" % action)
	assert_false(FileAccess.file_exists(missing), "reloading never writes")
	s.free()
	fresh.free()


func test_hud_key_labels_read_the_live_bindings() -> void:
	assert_eq(KeyBindings.key_name(KEY_DELETE), "Del")
	assert_eq(KeyBindings.key_name(KEY_END), "End")
	assert_eq(KeyBindings.key_name(KEY_PAGEDOWN), "PgDn")
	assert_eq(KeyBindings.key_name(KEY_Q), "Q")
	var s := GameSettings.new(cfg_path)
	s.set_bindings({"drink_hp": PackedInt32Array([KEY_DELETE, KEY_Q])})
	assert_eq(GameSettings.action_label("drink_hp"), "Del / Q")
	s.set_bindings({"drink_hp": PackedInt32Array([KEY_F]), "item_window": PackedInt32Array()})
	assert_eq(GameSettings.action_label("drink_hp"), "F", "rebinding changes the label")
	assert_eq(GameSettings.action_label("item_window"), "-", "an unbound action")
	assert_eq(GameSettings.first_key_label("item_window"), "", "the quick slot shows no caption for it")
	var slot := HudQuickSlot.new()
	slot.update({"potions": {"hp": {"item_id": 0, "count": 3}}}, {})
	assert_eq(slot.displayed("hp").key_label, "F", "the HUD potion quickslot shows the rebound key")
	assert_eq(slot.cell("item_window").caption, "")
	slot.free()
	s.free()


## A run world that owns Teleport (its first manual key is the caption of its HUD skill icon).
static func _teleport_world() -> RunWorld:
	var setup := RF.setup("quiet", 60, RF.quiet_data())
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	setup.skill_imgs["210"] = {"skill": {"2101002": {"level": {"1": {"mpCon": 60, "range": 130}}}}}
	var w := RunWorld.new(setup)
	w.change_job(210)
	w.loadout.add_skill("teleport_fp")
	w.player.place(Vector2(400, 0), w.fhm)
	return w


func test_hud_key_labels_follow_key_config_ok_at_once_over_the_paused_run() -> void:
	var s := GameSettings.new(cfg_path)
	var scene := RunScene.new()
	scene.world = _teleport_world()
	scene.hud = Hud.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(scene.hud)
	scene.watch_settings(s)
	assert_eq(String(scene.hud.skills.displayed().back().key_label), "X", "Teleport's default key on its icon")
	scene.paused = true # Key Config opens over the pause menu: no frame refreshes the HUD while it is open
	var kb := KeyBindings.from_settings(s, ["teleport"])
	kb.unbind(KEY_X)
	kb.bind("teleport", KEY_C)
	kb.unbind(KEY_DELETE)
	kb.unbind(KEY_Q)
	kb.bind("drink_hp", KEY_F)
	kb.apply_to(s) # OK
	assert_eq(String(scene.hud.skills.displayed().back().key_label), "C", "the Teleport icon shows the new key")
	assert_eq(String(scene.run_info().skills.back().key_label), "C", "and so does the run's HUD snapshot")
	var hp := String(scene.hud.quick_slot.displayed("hp").key_label)
	assert_eq(hp, "F", "the HP quick slot shows the new key")
	scene.hud.free()
	scene.free()
	s.free()


# --- Skill keys (#188) -----------------------------------------------------------------------------------------

func test_key_config_lists_only_the_learned_manual_skills() -> void:
	var s := GameSettings.new(cfg_path)
	var none := KeyBindings.from_settings(s)
	assert_eq(none.skill_keys.size(), 0, "no manual skill learned: no skill key")
	assert_false(none.actions().has("teleport"), "Teleport is not listed")
	assert_false(none.actions().has("dash"), "Dash is not listed")
	assert_false(none.bind("dash", KEY_F), "an unlearned skill key cannot be bound")
	var pirate := KeyBindings.from_settings(s, ["dash"])
	assert_eq(pirate.actions().back(), "dash", "a learned manual skill follows the fixed actions")
	assert_false(pirate.actions().has("teleport"), "only the learned one")
	var mage := KeyBindings.from_settings(s, ["teleport"])
	assert_true(mage.actions().has("teleport"))
	assert_false(mage.actions().has("dash"))
	assert_eq(KeyBindings.from_settings(s, ["no_such_skill"]).skill_keys.size(), 0, "an unknown id is dropped")
	s.free()


func test_teleport_and_dash_default_to_x() -> void:
	assert_eq(GameSettings.default_keys("teleport"), PackedInt32Array([KEY_X]))
	assert_eq(GameSettings.default_keys("dash"), PackedInt32Array([KEY_X]))
	var s := GameSettings.new(cfg_path)
	assert_eq(KeyBindings.from_settings(s, ["dash"]).keys_of("dash"), PackedInt32Array([KEY_X]), "a Pirate dashes on X")
	assert_eq(KeyBindings.from_settings(s, ["teleport"]).keys_of("teleport"), PackedInt32Array([KEY_X]))
	s.free()


func test_a_saved_teleport_binding_is_teleports_skill_key() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "teleport", [KEY_F])
	cfg.save(cfg_path)
	var s := GameSettings.new(cfg_path)
	s.apply_bindings()
	var kb := KeyBindings.from_settings(s, ["teleport"])
	assert_eq(kb.keys_of("teleport"), PackedInt32Array([KEY_F]), "the saved binding loads on the skill key")
	assert_eq(kb.action_on(KEY_F), "teleport")
	assert_eq(s.binding_keys("teleport"), PackedInt32Array([KEY_F]), "and is live in the InputMap")
	assert_eq(KeyBindings.from_settings(s, ["dash"]).keys_of("dash"), PackedInt32Array([KEY_X]),
		"a Teleport rebind does not move Dash")
	s.free()


func test_a_skill_key_round_trips_through_ok() -> void:
	var s := GameSettings.new(cfg_path)
	var kb := KeyBindings.from_settings(s, ["dash"])
	kb.unbind(KEY_X)
	assert_true(kb.bind("dash", KEY_F))
	kb.apply_to(s)
	assert_eq(s.binding_keys("dash"), PackedInt32Array([KEY_F]), "applied to the InputMap at once")
	var t := GameSettings.new(cfg_path)
	assert_eq(KeyBindings.from_settings(t, ["dash"]).keys_of("dash"), PackedInt32Array([KEY_F]), "saved and loaded")
	kb.reset_defaults()
	assert_eq(kb.keys_of("dash"), PackedInt32Array([KEY_X]), "Default puts the skill key back on X")
	t.free()
	s.free()


## A key holds one action across every skill key, learned or not (review of #188): a character without Dash rebinds X,
## and the next character who knows Dash (same session or after a restart) must not find X on two actions.
func _holders(s: GameSettings, key: int) -> Array:
	var out: Array = []
	for a: StringName in InputMap.get_actions():
		if String(a).begins_with("ui_"):
			continue
		if key in s.binding_keys(String(a)):
			out.append(String(a))
	return out


func test_rebinding_x_takes_it_off_the_unlisted_skill_keys() -> void:
	var s := GameSettings.new(cfg_path) # character A: no manual skill, so Key Config lists neither Teleport nor Dash
	var a := KeyBindings.from_settings(s)
	a.unbind(KEY_X)
	assert_true(a.bind("jump", KEY_X))
	a.apply_to(s)
	assert_eq(_holders(s, KEY_X), ["jump"], "live: X is on jump only, Dash and Teleport lost it")
	var b := KeyBindings.from_settings(s, ["dash"]) # character B knows Dash, same session
	assert_eq(b.action_on(KEY_X), "jump")
	assert_eq(b.keys_of("dash"), PackedInt32Array(), "Dash has no key until rebound")
	var t := GameSettings.new(cfg_path) # after a restart
	t.apply_bindings()
	assert_eq(_holders(t, KEY_X), ["jump"], "saved: still one holder")
	assert_eq(KeyBindings.from_settings(t, ["dash"]).keys_of("dash"), PackedInt32Array())
	assert_eq(KeyBindings.from_settings(t, ["teleport"]).keys_of("teleport"), PackedInt32Array())
	t.free()
	s.free()


func test_binding_a_rebound_skill_keys_key_takes_it_off_that_skill_key() -> void:
	var s := GameSettings.new(cfg_path)
	var dasher := KeyBindings.from_settings(s, ["dash"]) # a Pirate moves Dash to F
	dasher.unbind(KEY_X)
	assert_true(dasher.bind("dash", KEY_F))
	dasher.apply_to(s)
	var a := KeyBindings.from_settings(s) # a character without Dash puts a potion on F
	a.unbind(KEY_F)
	assert_true(a.bind("drink_hp", KEY_F))
	a.apply_to(s)
	assert_eq(_holders(s, KEY_F), ["drink_hp"], "F left the unlisted Dash")
	var t := GameSettings.new(cfg_path)
	t.apply_bindings()
	assert_eq(_holders(t, KEY_F), ["drink_hp"], "saved")
	assert_eq(KeyBindings.from_settings(t, ["dash"]).action_on(KEY_F), "drink_hp")
	t.free()
	s.free()


func test_loading_a_file_with_one_key_on_a_skill_key_and_another_action_keeps_one_holder() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "jump", [KEY_X])
	cfg.set_value("input", "dash", [KEY_X])
	cfg.save(cfg_path)
	var s := GameSettings.new(cfg_path)
	s.apply_bindings()
	assert_eq(_holders(s, KEY_X), ["jump"], "a skill key yields to the fixed actions")
	s.free()
