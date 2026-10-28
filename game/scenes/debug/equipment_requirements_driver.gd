extends Node
## Visual probe for #292: the Lv1 Free Market (the real `--hub` kit with the Lv38 F/P fixture's gear) with the Equip and Item
## windows open and a hovered item tooltip, then a scroll shop, to check by eye that no REQ LEV / STR / DEX / INT / LUK row
## is drawn and that gear above Lv1 can be worn. Run: ISOLATE=292 bash scripts/run.sh
## res://scenes/debug/equipment_requirements_driver.tscn -- --shots=<absolute evidence path>. Needs the asset cache; no
## proprietary screenshot belongs in git.

var flow: SceneFlow
var shots := ""
var _n := 0


func _ready() -> void:
	var flags := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(flags.get("shots", ""))
	if shots.is_empty():
		push_error("equipment_requirements_driver requires --shots=<absolute evidence path>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	flow = SceneFlow.new()
	flow.host = Node.new()
	add_child(flow.host)
	add_child(flow)
	flow.start_hub({}, shots.path_join("driver_hub_save.json"))
	await _sleep(2.0)
	var hub: Node = flow.current
	print("equipment_requirements_driver: screen=%s level=%d" % [flow.current_name, hub.inventory.progression.level])
	await _shot("hub")
	hub.ui_windows.toggle("equip")
	hub.ui_windows.toggle("item")
	await _sleep(0.6)
	await _shot("equip_and_item_windows")
	# hover the first spare item of the Item window: its tooltip has the job row and the facts, no requirement rows
	var item_window: Control = hub.ui_windows.find_window("item")
	if item_window != null and item_window.has_method("slot_rect"):
		var motion := InputEventMouseMotion.new()
		motion.position = item_window.slot_rect(1).get_center()
		item_window._gui_input(motion)
		await _sleep(0.3)
		await _shot("item_tooltip")
	# double-click the Arc Staff (reqLevel 45, reqINT 138, reqLUK 48) in the Item window at Lv1: the real UI path wears it
	for step: Array in [[true, false], [false, false], [true, true], [false, false]]: # [pressed, double_click]
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.pressed = step[0]
		click.double_click = step[1]
		click.position = item_window.slot_rect(1).get_center()
		item_window._gui_input(click)
	print("equipment_requirements_driver: Arc Staff double-clicked at Lv%d, weapon now %d" % [
		hub.inventory.progression.level, hub.inventory.weapon_id()])
	await _sleep(0.4)
	await _shot("staff_worn_at_level_one")
	hub.ui_windows.close_top()
	hub.ui_windows.close_top()
	await _sleep(0.3)
	hub.open_shop(int(hub.shop_npcs[0].id))
	await _sleep(0.8)
	await _shot("shop")
	var equip_before: int = hub.inventory.equipment.inventory.size()
	var worn: String = JSON.stringify(Equipment.worn_ids(hub.inventory.equipment.worn))
	print("equipment_requirements_driver: spare=%d worn=%s mesos=%d" % [equip_before, worn, hub.inventory.mesos])
	get_tree().quit()


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(step: String) -> void:
	await _sleep(0.4)
	await get_tree().process_frame
	RenderingServer.force_draw()
	_n += 1
	var path := shots.path_join("%02d_%s.png" % [_n, step])
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path) if img != null else ERR_UNAVAILABLE
	print("equipment_requirements_driver: shot %s err=%d screen=%s" % [path.get_file(), err, flow.current_name])
