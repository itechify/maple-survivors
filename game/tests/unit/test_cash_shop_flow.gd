extends TestCase
## The Cash Shop as a Flow destination (#118): opened as the current character from map select (every tier, so a new
## character can shop before tier 1) and from the Free Market; Leave returns where it was opened; buying goes through the
## screen's confirm dialog and the saved account; there is no shop without a living character.

const UI_FLOW := preload("res://tests/unit/test_ui_flow.gd")

var save_path := TestCase.test_dir("cash_shop_flow/save.json")
var _nodes: Array[Node] = []


func after_each() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()
	TestCase.remove_tree(save_path.get_base_dir())


func _flow(nx: int = 0) -> SceneFlow:
	var flow := SceneFlow.new()
	_nodes.append(flow)
	flow.deferred_swaps = false
	flow.save = SaveData.new(save_path)
	flow.save.set_account({"nx": nx, "owned": []})
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_nodes.append(host)
	flow.host = host
	return flow


func _clear_into_free_market(flow: SceneFlow) -> void:
	var summary := UI_FLOW.summary(true, 900.0, 20, 1000)
	summary["nx_awarded"] = 0
	flow.finish_run(summary, flow.save.slot(0).character)


func test_a_new_character_can_open_the_shop_from_map_select_and_leave_back_to_it() -> void:
	var flow := _flow()
	flow.create_character("Shopper118")
	assert_eq(flow.current_name, "stage_select")
	flow.current.shop_button.pressed.emit()
	assert_eq(flow.current_name, "cash_shop")
	assert_eq(flow.current.snapshot.name, "Shopper118", "you enter as the current character")
	flow.current.leave()
	assert_eq(flow.current_name, "stage_select")
	assert_eq(flow.current.snapshot.name, "Shopper118")
	assert_eq(flow.save.slot(0).phase, "map_select")


func test_the_shop_opens_at_every_tier_of_map_select() -> void:
	var flow := _flow()
	flow.create_character("Tiers118")
	var snapshot := flow.save.slot(0)
	snapshot.tier = 1
	flow.save.update_slot(0, snapshot)
	flow.goto_stage_select()
	flow.current.shop_button.pressed.emit()
	assert_eq(flow.current_name, "cash_shop")
	assert_eq(int(flow.current.snapshot.tier), 1)
	flow.current.leave()
	assert_eq(flow.current_name, "stage_select")
	assert_eq(int(flow.current.snapshot.tier), 1)


func test_the_free_market_shop_returns_to_the_free_market() -> void:
	if not require_cache():
		return
	var flow := _flow()
	flow.create_character("Market118")
	_clear_into_free_market(flow)
	assert_eq(flow.current_name, "free_market")
	assert_true((flow.current as FreeMarket).shop_button != null)
	(flow.current as FreeMarket).shop_button.pressed.emit()
	assert_eq(flow.current_name, "cash_shop")
	flow.current.leave()
	assert_eq(flow.current_name, "free_market")
	assert_eq(flow.save.slot(0).phase, "free_market", "shopping does not move the round boundary")


func test_continue_after_closing_in_the_shop_resumes_the_boundary_it_was_opened_from() -> void:
	var flow := _flow()
	flow.create_character("Resume118")
	flow.goto_cash_shop("stage_select")
	flow.save = SaveData.new(save_path)
	flow.continue_character(0)
	assert_eq(flow.current_name, "stage_select")


func test_there_is_no_shop_without_a_living_character() -> void:
	var flow := _flow()
	flow.goto_cash_shop("stage_select")
	assert_eq(flow.current_name, "")
	flow.goto_character_select()
	assert_eq(flow.current_name, "character_select")
	assert_eq(flow.current.get("shop_button"), null, "no shop button on character select")


func test_buying_through_the_dialog_deducts_adds_saves_and_hides_the_item() -> void:
	var flow := _flow(10000)
	flow.create_character("Buyer118")
	flow.goto_cash_shop("stage_select")
	var shop = flow.current
	shop.select_tab("equip")
	shop.select_sub("Hat")
	assert_true(shop.page_ids().has(1002279))
	shop.request_buy(1002279)
	assert_eq(shop.pending_id, 1002279)
	assert_eq(flow.save.account.nx, 10000, "nothing is spent before OK")
	shop.cancel_buy()
	assert_eq(shop.pending_id, 0)
	assert_eq(flow.save.account.nx, 10000)
	shop.request_buy(1002279)
	shop.confirm_buy()
	assert_eq(SaveData.new(save_path).account, {"nx": 6300, "owned": [1002279]})
	assert_eq(shop.pending_id, 0)
	assert_false(shop.listing_ids().has(1002279), "a bought item leaves the list")
	assert_eq(shop.owned_ids(), [1002279], "and shows in the read-only owned panel")
	assert_eq(shop.notice_text, "")


func test_an_unaffordable_item_shows_the_not_enough_nx_notice_and_changes_nothing() -> void:
	var flow := _flow(100)
	flow.create_character("Poor118")
	flow.goto_cash_shop("stage_select")
	var shop = flow.current
	shop.select_sub("Hat")
	shop.request_buy(1002279)
	assert_eq(shop.pending_id, 0, "no confirm dialog for a purchase that cannot happen")
	shop.confirm_buy()
	assert_eq(shop.notice_text, "You don't have enough NX.")
	assert_eq(SaveData.new(save_path).account, {"nx": 100, "owned": []})
	shop.dismiss_notice()
	assert_eq(shop.notice_text, "")


func test_a_locked_pet_upgrade_cannot_be_requested_and_says_why() -> void:
	var flow := _flow(99999)
	flow.create_character("Locked118")
	flow.goto_cash_shop("stage_select")
	var shop = flow.current
	shop.select_tab("pet")
	shop.select_sub("Pet Equip.")
	assert_eq(shop.lock_text(1812002), "Needs a pet.")
	assert_true(shop.lock_text(9990000).begins_with("Needs "))
	shop.request_buy(1812002)
	assert_eq(shop.pending_id, 0, "no dialog for a locked item")
	assert_eq(SaveData.new(save_path).account.owned, [])
	shop.select_sub("Pet")
	assert_eq(shop.lock_text(5000000), "")


func test_trying_on_an_item_previews_it_without_wearing_or_owning_it() -> void:
	var flow := _flow(0)
	flow.create_character("Preview118")
	flow.goto_cash_shop("stage_select")
	var shop = flow.current
	shop.select_sub("Hat")
	shop.preview(1002279)
	assert_eq(shop.preview_cash, {"hat": 1002279})
	assert_eq(flow.save.slot(0).character.get("cash", {}), {}, "not worn")
	assert_eq(flow.save.account.owned, [], "not owned")
	shop.reset_preview()
	assert_eq(shop.preview_cash, {})
	shop.preview(1002279)
	shop.strip_preview()
	assert_eq(shop.preview_cash, {})
	shop.preview(5000000)
	assert_eq(shop.preview_cash, {}, "a pet is not worn")
