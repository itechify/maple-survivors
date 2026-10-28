extends TestCase
## How SceneFlow credits and shows the NX a round pays (#115, #286): every round (a clear, a death, Quit round) credits it
## in the save that ends the round, shows "+N NX" on the results screen and announces it in the Free Market on arrival;
## deletion and one-off rounds credit nothing; map select shows the balance.

const UI_FLOW := preload("res://tests/unit/test_ui_flow.gd")
const RESULTS := preload("res://scenes/ui/results_screen.gd")

var save_path := TestCase.test_dir("nx_flow/save.json")
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
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_nodes.append(host)
	flow.host = host
	return flow


func _summary(cleared: bool, nx: int) -> Dictionary:
	var s := UI_FLOW.summary(cleared, 900.0 if cleared else 512.0, 20, 1000)
	s["bosses_killed"] = 1
	s["levels_gained"] = 4
	s["nx_awarded"] = nx
	return s


func test_a_clear_credits_nx_in_the_round_save_and_the_free_market_announces_it() -> void:
	var flow := _flow()
	flow.create_character("Clear115")
	var character: Dictionary = flow.save.slot(0).character
	flow.finish_run(_summary(true, 140), character)
	assert_eq(flow.current_name, "results")
	var reloaded := SaveData.new(save_path)
	assert_eq(reloaded.account.nx, 140, "spendable straight away, credited by the save that ends the round")
	assert_eq(int(reloaded.slot(0).rounds_played), 1)
	assert_true(RESULTS.stat_rows(flow.last_summary).has(["NX earned", "+140 NX"]))
	flow.current.to_hub()
	assert_eq(flow.current_name, "free_market")
	assert_eq((flow.current as FreeMarket).notice, "You have gained 140 NX.")
	flow.save_and_quit()
	flow.save = SaveData.new(save_path)
	flow.continue_character(0)
	assert_eq(flow.current_name, "free_market")
	assert_eq((flow.current as FreeMarket).notice, "", "Continue is not an arrival from a round")
	assert_eq(SaveData.new(save_path).account.nx, 140, "never paid twice")


func test_a_death_credits_nx_too_and_results_show_it() -> void:
	var flow := _flow()
	flow.create_character("Death115")
	flow.save.set_account({"nx": 25, "owned": []})
	flow.finish_run(_summary(false, 60), flow.save.slot(0).character)
	assert_eq(flow.current_name, "results")
	var reloaded := SaveData.new(save_path)
	assert_eq(reloaded.account.nx, 85)
	assert_eq(reloaded.history.size(), 1)
	assert_eq(reloaded.slot(0).name, "Death115", "the character lives on")
	assert_true(RESULTS.stat_rows(flow.last_summary).has(["NX earned", "+60 NX"]))


func test_every_clear_credits_nx_there_is_no_final_tier_to_end_a_character() -> void:
	var flow := _flow()
	flow.create_character("Win115")
	var character: Dictionary = flow.save.slot(0).character
	var total := 0
	for round_index in 3:
		flow.finish_run(_summary(true, 100 + round_index), character)
		total += 100 + round_index
	assert_eq(flow.current_name, "results")
	assert_eq(SaveData.new(save_path).account.nx, total)
	assert_eq(flow.last_summary.ending, "cleared")
	assert_eq(SaveData.new(save_path).slot(0).name, "Win115", "victory archives nothing")
	assert_true(RESULTS.stat_rows(flow.last_summary).has(["NX earned", "+102 NX"]))


func test_deleting_a_character_credits_nothing() -> void:
	var flow := _flow()
	flow.create_character("Delete115")
	flow.save.set_account({"nx": 30, "owned": []})
	assert_true(flow.delete_character(0))
	assert_eq(SaveData.new(save_path).account.nx, 30)


func test_quit_round_pays_its_nx_like_a_death() -> void:
	var flow := _flow()
	flow.create_character("Quit115")
	flow.finish_run(_summary(false, 40), flow.save.slot(0).character, "quit")
	assert_eq(SaveData.new(save_path).account.nx, 40)
	assert_eq(flow.save.history[0].ending, "quit")


func test_one_off_round_credits_nothing_and_writes_no_save() -> void:
	var flow := _flow()
	flow.finish_run(_summary(true, 500))
	assert_eq(flow.current_name, "results")
	assert_eq(flow.save.account.nx, 0)
	assert_false(FileAccess.file_exists(save_path))
	assert_false(RESULTS.stat_rows(flow.last_summary).any(func(row: Array) -> bool: return row[0] == "NX earned"),
		"a tool round never shows an award it did not credit")


func test_map_select_shows_the_account_balance() -> void:
	var flow := _flow()
	flow.save.set_account({"nx": 12345, "owned": []})
	flow.create_character("Select115")
	flow.goto_stage_select()
	assert_eq(flow.current_name, "stage_select")
	assert_true(flow.current.character_label.text.contains("12,345 NX"), flow.current.character_label.text)
