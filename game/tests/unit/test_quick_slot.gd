extends TestCase
## The HUD quick slot (#220): the eight cells' model (fixed order, the icon each action has in Key Config, the first
## bound key as caption, potion cooldown), the movement skill cell (empty, Teleport, Dash), captions following the live
## bindings (rebound, unbound, web-reserved keys), and the collapse state in settings.cfg. The model needs no asset cache;
## the widget and button tests that draw art SKIP without it.

var cfg_path := TestCase.test_dir("quick_slot_test.cfg")
var _saved_map: Dictionary = {}
var _nodes: Array[Node] = []

const POTIONS := {"hp": {"item_id": 2000000, "cooldown_left": 10.0, "cooldown_total": 20.0}}
const TELEPORT := {"action": "teleport", "name": "Teleport", "icon": "Skill.wz/200.img/skill/2001002/icon",
	"skill": "teleport_fp"}
const DASH := {"action": "dash", "name": "Dash", "icon": "Skill.wz/500.img/skill/5001005/icon", "skill": "dash"}


func before_each() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(cfg_path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path + suffix))
	# The live InputMap may hold the developer's rebinds: tests start from the project defaults and put it back.
	_saved_map = {}
	for a: StringName in InputMap.get_actions():
		_saved_map[a] = InputMap.action_get_events(a).duplicate()
	InputMap.load_from_project_settings()


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	for a: StringName in _saved_map:
		if InputMap.has_action(a):
			InputMap.action_erase_events(a)
			for e: InputEvent in _saved_map[a]:
				InputMap.action_add_event(a, e)


func _settings() -> GameSettings:
	var s := GameSettings.new(cfg_path)
	_nodes.append(s)
	return s


func _cells(movement: Dictionary = {}) -> Array[Dictionary]:
	return HudQuickSlot.cells(HudQuickSlot.captions_now(movement), POTIONS, movement)


func _cell(cells: Array[Dictionary], action: String) -> Dictionary:
	for c: Dictionary in cells:
		if c.action == action:
			return c
	return {}


func test_the_cells_are_in_the_fixed_order_with_key_config_icons_and_default_keys() -> void:
	var cells := _cells()
	var order: Array[String] = []
	for c: Dictionary in cells:
		order.append(c.action)
	assert_eq(order, ["drink_hp", "", "", "jump", "equip_window", "item_window", "stat_window", "skill_window"],
		"top row HP, a blank cell (no MP, #285), movement skill, Jump; bottom row Equip, Item, Stat, Skill")
	assert_eq(cells[1].icon_path, "", "the blank cell draws no icon")
	assert_eq(cells[1].caption, "", "and no caption")
	for action: String in ["jump", "equip_window", "item_window", "stat_window", "skill_window"]:
		assert_eq(_cell(cells, action).icon_path, KeyActionArt.icon_path(action), "%s uses the Key Config icon" % action)
	assert_eq(_cell(cells, "jump").caption, "Alt", "Jump: its first key (Alt, then C)")
	assert_eq(_cell(cells, "equip_window").caption, "E")
	assert_eq(_cell(cells, "item_window").caption, "I")
	assert_eq(_cell(cells, "stat_window").caption, "S")
	assert_eq(_cell(cells, "skill_window").caption, "K")
	assert_eq(_cell(cells, "drink_hp").caption, "Del", "the first key only (HP is on Del and Q)")


func test_potion_cells_show_the_current_item_icon_without_stock() -> void:
	var cells := _cells()
	var hp := _cell(cells, "drink_hp")
	assert_eq(hp.icon_path, AssetLibrary.item_icon_path(2000000, false), "the current Red Potion's icon")
	assert_false(hp.has("count"), "unlimited potions carry no stock number")
	assert_eq(hp.item_id, 2000000)
	for c: Dictionary in cells:
		assert_false(c.has("count"), "no quick-slot cell carries a count")
	var none := HudQuickSlot.cells({}, {"hp": {"item_id": 0, "count": 0}}, {})
	assert_eq(none[0].icon_path, KeyActionArt.icon_path("drink_hp"), "no item yet: the Key Config potion icon")
	assert_false(none[1].has("count"))


func test_rebound_potions_show_only_their_first_key() -> void:
	var s := _settings()
	s.set_bindings({"drink_hp": PackedInt32Array([KEY_Q])})
	assert_eq(_cell(_cells(), "drink_hp").caption, "Q", "HP on Q only")
	s.set_bindings({"drink_hp": PackedInt32Array([KEY_DELETE, KEY_Q])})
	assert_eq(_cell(_cells(), "drink_hp").caption, "Del", "the project default: Del first")
	s.set_bindings({"drink_hp": PackedInt32Array([KEY_Q, KEY_F])})
	assert_eq(_cell(_cells(), "drink_hp").caption, "Q", "the first bound key wins whatever its name")


func test_potion_sweeps_match_skills_and_redraw_only_when_the_step_changes() -> void:
	var w := HudQuickSlot.new()
	_nodes.append(w)
	w.update({"potions": POTIONS}, {})
	assert_eq(w.displayed("hp").sweep_step, 48, "half of the HP cooldown")
	assert_false(w.displayed("hp").has("count"))
	var left := PackedFloat32Array([10.0])
	var total := PackedFloat32Array([20.0])
	assert_false(w.set_cooldowns(left, total), "the snapshot already drew these steps")
	left[0] = 9.99
	assert_false(w.set_cooldowns(left, total), "same sweep step: no redraw")
	left[0] = 9.0
	assert_true(w.set_cooldowns(left, total), "HP advances")
	assert_eq(w.displayed("hp").sweep_step, HudSkills.sweep_step(9.0, 20.0))
	for seconds: float in [20.0, 15.0, 10.0, 5.0, 0.01, 0.0, -1.0, 30.0]:
		left[0] = seconds
		w.set_cooldowns(left, total)
		assert_eq(w.displayed("hp").sweep_step, HudSkills.sweep_step(seconds, 20.0), "same sweep as skills")
		assert_false(w.set_cooldowns(left, total), "unchanged input never redraws")
	left.fill(0.0)
	w.set_cooldowns(left, total)
	w.refresh_key_labels()
	assert_eq(w.displayed("hp").sweep_step, 0, "a caption refresh keeps the per-frame sweep")
	total.fill(0.0)
	left.fill(1.0)
	assert_false(w.set_cooldowns(left, total), "no cooldown total means ready")


func test_an_unbound_action_has_an_empty_caption_but_keeps_its_icon() -> void:
	var s := _settings()
	s.set_bindings({"stat_window": PackedInt32Array()})
	var stat := _cell(_cells(), "stat_window")
	assert_eq(stat.caption, "", "unbound: no caption")
	assert_eq(stat.icon_path, KeyActionArt.icon_path("stat_window"))


func test_web_reserved_keys_still_get_a_caption() -> void:
	var s := _settings()
	s.set_bindings({"item_window": PackedInt32Array([KEY_F11]), "skill_window": PackedInt32Array([KEY_F12])})
	var cells := _cells()
	assert_eq(_cell(cells, "item_window").caption, "F11", "the web build keeps F11 for the browser, the cell still names it")
	assert_eq(_cell(cells, "skill_window").caption, "F12")


func test_the_movement_cell_is_empty_then_teleport_then_dash() -> void:
	var cells := _cells()
	var empty: Dictionary = cells[2]
	assert_eq(empty.action, "")
	assert_eq(empty.icon_path, "", "no movement skill learned: an empty cell")
	assert_eq(empty.caption, "")
	var tp := _cells(TELEPORT)[2]
	assert_eq(tp.action, "teleport")
	assert_eq(tp.icon_path, TELEPORT.icon, "Teleport's own icon")
	assert_eq(tp.caption, "X", "Teleport's key")
	var dash := _cells(DASH)[2]
	assert_eq(dash.action, "dash")
	assert_eq(dash.icon_path, DASH.icon)
	assert_eq(dash.caption, "X", "Dash shares X by default")


func test_the_movement_cell_follows_a_rebound_skill_key() -> void:
	var s := _settings()
	s.set_bindings({"teleport": PackedInt32Array([KEY_SPACE])})
	assert_eq(_cells(TELEPORT)[2].caption, "Space")
	s.set_bindings({"teleport": PackedInt32Array()})
	assert_eq(_cells(TELEPORT)[2].caption, "", "unbound Teleport: icon without a caption")
	assert_eq(_cells(TELEPORT)[2].icon_path, TELEPORT.icon)


func test_the_movement_skill_is_the_first_learned_skill_key() -> void:
	assert_eq(HudQuickSlot.movement_skill_of([]), {}, "none learned")
	assert_eq(HudQuickSlot.movement_skill_of([TELEPORT]), TELEPORT)
	assert_eq(HudQuickSlot.movement_skill_of([DASH, TELEPORT]), DASH, "learning order")


func test_the_widget_follows_updates_and_key_config_ok() -> void:
	var s := _settings()
	var w := HudQuickSlot.new()
	_nodes.append(w)
	w.update({"potions": POTIONS}, {"movement_skill": TELEPORT})
	assert_eq(w.cell("teleport").caption, "X")
	assert_false(w.cell("drink_hp").has("count"))
	s.set_bindings({"drink_hp": PackedInt32Array([KEY_F]), "teleport": PackedInt32Array([KEY_SPACE])})
	w.refresh_key_labels()
	assert_eq(w.cell("drink_hp").caption, "F", "captions update at once")
	assert_eq(w.cell("teleport").caption, "Space")
	assert_eq(w.cells_now().size(), 8)
	w.update({"potions": POTIONS}, {})
	assert_eq(w.cell("teleport"), {}, "no movement skill: no teleport cell")
	assert_eq(w.displayed("hp").key_label, "F", "displayed(): the old per-potion view")


func test_collapse_state_round_trips_through_settings_cfg() -> void:
	var s := _settings()
	assert_false(s.quick_slot_collapsed, "shown by default")
	s.set_quick_slot_collapsed(true)
	assert_true(GameSettings.new(cfg_path).quick_slot_collapsed, "the next launch starts collapsed")
	var cfg := ConfigFile.new()
	cfg.load(cfg_path)
	assert_true(bool(cfg.get_value("hud", "quick_slot_collapsed")), "stored under [hud] quick_slot_collapsed")
	s.set_quick_slot_collapsed(false)
	var after := ConfigFile.new()
	after.load(cfg_path)
	assert_false(after.has_section_key("hud", "quick_slot_collapsed"), "the default is not written")
	assert_false(GameSettings.new(cfg_path).quick_slot_collapsed)


func test_reload_from_resets_the_collapse_state() -> void:
	var s := _settings()
	s.set_quick_slot_collapsed(true)
	s.reload_from(TestCase.test_dir("quick_slot_missing.cfg"))
	assert_false(s.quick_slot_collapsed, "a missing file means the default")


# --- Wired into a run -----------------------------------------------------------------------------------------

const RF := preload("res://tests/fixtures/run_fixtures.gd")


func _scene(learn_teleport: bool) -> RunScene:
	var setup := RF.setup("quiet", 60, RF.quiet_data())
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	setup.skill_imgs["210"] = {"skill": {"2101002": {"level": {"1": {"mpCon": 60, "range": 130}}}}}
	var w := RunWorld.new(setup)
	if learn_teleport:
		w.change_job(210)
		w.loadout.add_skill("teleport_fp")
	w.player.place(Vector2(400, 0), w.fhm)
	var scene := RunScene.new()
	scene.world = w
	scene.hud = Hud.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(scene.hud)
	_nodes.append(scene.hud)
	_nodes.append(scene)
	return scene


func test_a_run_feeds_the_learned_movement_skill_and_the_potions() -> void:
	var scene := _scene(false)
	var s := _settings()
	scene.watch_settings(s)
	assert_eq(scene.run_info().movement_skill, {}, "no movement skill before it is learned")
	assert_eq(scene.hud.quick_slot.cell("teleport"), {}, "the movement cell is empty")
	assert_eq(scene.hud.quick_slot.cell("drink_hp").caption, "Del")
	scene.world.loadout.add_skill("teleport_fp")
	scene.world.change_job(210)
	scene.watch_settings(s) # refreshes the HUD like the next frame's snapshot change does
	assert_eq(scene.run_info().movement_skill.action, "teleport")
	assert_eq(scene.hud.quick_slot.cell("teleport").caption, "X", "Teleport on its default key")


func test_the_collapse_button_folds_the_panel_and_remembers_it() -> void:
	var scene := _scene(true)
	var s := _settings()
	scene.watch_settings(s)
	assert_false(scene.hud.quick_slot.collapsed, "shown by default")
	assert_true(scene.hud.quick_slot.visible)
	assert_eq(scene.hud.quick_slot_button.base_path, Hud.QUICK_SLOT_SHOWN_ART, "the down arrow while shown")
	scene.toggle_quick_slot()
	assert_true(scene.hud.quick_slot.collapsed)
	assert_false(scene.hud.quick_slot.visible)
	assert_eq(scene.hud.quick_slot_button.base_path, Hud.QUICK_SLOT_FOLDED_ART, "the up arrow while folded")
	assert_true(s.quick_slot_collapsed, "kept in the settings")
	assert_true(GameSettings.new(cfg_path).quick_slot_collapsed, "and in settings.cfg")
	scene.toggle_quick_slot()
	assert_false(scene.hud.quick_slot.collapsed)
	assert_false(s.quick_slot_collapsed)


func test_a_collapsed_setting_starts_the_run_with_the_panel_folded() -> void:
	var s := _settings()
	s.set_quick_slot_collapsed(true)
	var scene := _scene(false)
	scene.watch_settings(s)
	assert_true(scene.hud.quick_slot.collapsed)
	assert_false(scene.hud.quick_slot.visible)
	s.set_quick_slot_collapsed(false)
	assert_false(scene.hud.quick_slot.collapsed, "the setting drives the panel")
