extends TestCase
## Cash equipment and the pet chosen in the Free Market through the Equip window survive Save & quit and Continue and
## reach the next round (spec #34, ticket #122). Needs the asset cache (the hub map and the pet art).

const UI_FLOW := preload("res://tests/unit/test_ui_flow.gd")
const IW := preload("res://tests/unit/test_inventory_windows.gd")
const HAT := 1002279
const PET := 5000001

var save_path := TestCase.test_dir("equip_cash_flow/save.json")
var _nodes: Array[Node] = []


func after_each() -> void:
	for node: Node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	TestCase.remove_tree(save_path.get_base_dir())


func _flow() -> SceneFlow:
	var flow := SceneFlow.new()
	_nodes.append(flow)
	flow.deferred_swaps = false
	flow.save = SaveData.new(save_path)
	flow.save.set_account({"nx": 0, "owned": [HAT, PET, 1812004]})
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_nodes.append(host)
	flow.host = host
	return flow


func _clear_into_free_market(flow: SceneFlow) -> void:
	var summary := UI_FLOW.summary(true, 900.0, 20, 1000)
	summary["nx_awarded"] = 0
	flow.finish_run(summary, flow.save.slot(0).character)


func test_cash_and_pet_chosen_in_the_free_market_are_saved_continue_and_reach_the_next_round() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Dress122")
	_clear_into_free_market(flow)
	assert_eq(flow.current_name, "free_market")
	var hub := flow.current as FreeMarket
	hub.ui_windows.toggle("equip")
	var ew := hub.ui_windows.find_window("equip") as EquipWindow
	ew.set_page("cash")
	assert_eq(ew.owned_items(), [HAT], "the account's owned cash equipment is on the Cash tab")
	IW.double_click(ew, ew.panel_cell(0).get_center())
	assert_eq(flow.save.slot(0).character.cash, {"hat": HAT}, "wearing it is saved with the run snapshot at once")
	assert_eq(hub.avatar.look.get("cash", {}), {"hat": HAT}, "and the avatar wears it at once")
	ew.set_page("pet")
	assert_eq(ew.owned_items(), [PET])
	IW.double_click(ew, ew.panel_cell(0).get_center())
	assert_eq(int(flow.save.slot(0).character.pet), PET)
	assert_true(hub.pet_renderer != null and hub.motion.pet.species == PET, "the pet appears beside the character at once")
	assert_eq(interim_missing(hub.missing_paths(), DataRepo.load_all()), PackedStringArray(), "no asset lookup failed")
	# Save & quit, then Continue from a freshly loaded file.
	flow.save_and_quit()
	flow.save = SaveData.new(save_path)
	flow.continue_character(0)
	assert_eq(flow.current_name, "free_market")
	hub = flow.current as FreeMarket
	assert_eq(CharacterSnapshot.integers(hub.snapshot.character.cash), {"hat": HAT})
	assert_true(hub.pet_renderer != null and hub.motion.pet.species == PET, "the pet is out again after Continue")
	# The next round plays with them.
	flow.goto_stage_select()
	flow.start_round(String(SceneFlow.tiers()[1][0]), 7)
	var run := flow.current as RunScene
	assert_true(run != null, "the next round is running")
	if run == null:
		return
	_nodes.append(run)
	assert_eq(run.world.account_owned, [HAT, PET, 1812004], "a persistent round gets the saved account")
	assert_eq(run.world.worn_cash, {"hat": HAT}, "the character wears the hat in the round")
	assert_eq(run.world.pet, PET)
	assert_true(run.world.pet_has("wing_boots"), "with its owned upgrades")
	assert_true(run.world.player_state.fortune > 0.0, "and the hat's Fortune")
	assert_eq(interim_warnings(run.world.warnings, run.world.data, run.world.stage_key).size(), 0)


func test_putting_the_pet_away_in_a_round_is_carried_to_the_next_boundary() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Away122")
	var snapshot := flow.save.slot(0)
	snapshot.character.pet = PET
	flow.save.update_slot(0, snapshot)
	flow.start_round("henesys", 7)
	var run := flow.current as RunScene
	assert_true(run != null and run.pet_renderer != null, "the round starts with the pet out")
	if run == null:
		return
	_nodes.append(run)
	run.ui_windows.toggle("equip")
	var ew := run.ui_windows.find_window("equip") as EquipWindow
	ew.set_page("pet")
	IW.double_click(ew, ew.panel_cell(0).get_center())
	assert_eq(run.world.pet, 0, "put away mid-round")
	assert_true(run.pet_renderer == null, "the pet is gone from the scene")
	assert_false(run.world.character_snapshot().has("pet"), "the next round boundary carries no pet")
	IW.double_click(ew, ew.panel_cell(0).get_center())
	assert_true(run.pet_renderer != null and run.world.pet == PET, "and it can be brought out again mid-round")
