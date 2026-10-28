extends Node
## Bowman equipment evidence (#201): seeded regular bow drop, real pickup/equip, then a bow scroll in El Moth's shop.
## Diagnostic staging uses fixed ticks and a private cache; no saves or balance data are changed.
## ISOLATE=s166-t201-visual MAPLE_SURVIVORS_CACHE=<private cache> bash scripts/run.sh \
##   res://scenes/debug/bowman_equipment_driver.tscn -- --shots=<absolute evidence directory>

const RF := preload("res://tests/fixtures/run_fixtures.gd")

var shots := ""


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	shots = String(SceneFlow.parse_flags(OS.get_cmdline_user_args()).get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var run := (load(RunScene.SCENE_PATH) as PackedScene).instantiate() as RunScene
	run.configure("henesys", 201, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.god = true
	w.progression.level = 10
	RF.as_job(w, 300, "bow")
	# tier C: diagnostic placement clear of the west portal beam, on the same floor as the drop.
	var floor_id := w.fhm.find_below(-150.0, 100.0)
	w.player.place(Vector2(-150.0, w.fhm.y_at(floor_id, -150.0)), w.fhm)
	w.update_view()
	run.handle_events(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type != "job_changed"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 201
	var id := 0
	for attempt in 1000:
		var picked := EquipmentDrops.pick(w.data.equipment_drops.items, w.setup.equipment_info, 300, 10,
			w.data.equipment_drops, rng, "bow")
		# Drops may be up to five levels ahead; this probe wears one the current character already qualifies for.
		if WeaponInfo.family(picked) == "bow" and int(Equipment.info_of(w.setup.equipment_info, picked).reqLevel) <= 10:
			id = picked
			break
	assert(id > 0, "seeded drop roster must contain a bow")
	var dropped := Equipment.create_drop(id, Equipment.info_of(w.setup.equipment_info, id), rng)
	w.spawn_equipment(w.player.pos + Vector2(20, -20), dropped)
	for tick in 180:
		run.advance_frame(1.0 / 60.0)
	var index: int = w.equipment.inventory.find(dropped)
	assert(index >= 0, "the real pickup must collect the dropped bow")
	assert(w.equip_item(index) == "", "the dropped Lv10 bow must be wearable")
	run.handle_events(w.drain_events())
	run.toggle_window("equip")
	await get_tree().create_timer(0.3).timeout
	var equip := run.ui_windows.find_window("equip") as EquipWindow
	_hover(equip, EquipWindow.SLOT_POS.weapon + Vector2(16, 16))
	await get_tree().create_timer(0.3).timeout
	await _shot("dropped_bow_equip.png")
	var summary := {"drop_id": id, "collected": w.equips_collected, "worn": w.weapon_id(),
		"run_missing": run.perf_summary().get("missing", [])}
	var character := w.character_snapshot()
	character.mesos = 100000
	run.queue_free()
	await get_tree().process_frame
	var hub := (load("res://scenes/run/free_market.tscn") as PackedScene).instantiate() as FreeMarket
	hub.configure({"character": character, "round_seed": 201, "name": "Bowman201", "tier": 2}, null,
		{"spawn_x": -320.0})
	add_child(hub)
	assert(hub.open_shop(1032103), "El Moth's real shop opens")
	var shop := hub.ui_windows.find_window("shop") as ShopWindow
	var stock_index := shop.stock.map(func(row: Dictionary) -> int: return int(row.id)).find(2044500)
	assert(stock_index >= 0, "bow ATT 100% is stocked")
	shop.scroll_panel(0, stock_index)
	shop.buy_selected = stock_index
	shop.queue_redraw()
	await get_tree().create_timer(0.3).timeout
	_hover(shop, shop.row_rect(0, stock_index - shop.buy_offset).get_center())
	await get_tree().create_timer(0.3).timeout
	await _shot("bow_scroll_shop.png")
	summary["scroll"] = int(shop.stock[stock_index].id)
	summary["price"] = int(shop.stock[stock_index].price)
	summary["hub_missing"] = Array(hub.missing_paths())
	summary["missing"] = Array(AssetLibrary.get_default().missing)
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _hover(window: UiWindow, at: Vector2) -> void:
	get_viewport().warp_mouse(window.global_position + at)
	var event := InputEventMouseMotion.new()
	event.position = at
	window._gui_input(event)


func _shot(filename: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(filename))
