extends Node
## Character UI visual probe. Uses an evidence-only save, captures both creation genders, three slots, history,
## deletion confirmation and a one-off round in a chosen look. Writes fresh weapon snapshots for smoke tooling.
## Run with ISOLATE=t32v: godot --path <mirror> res://scenes/debug/character_driver.tscn
## -- --shots=<absolute evidence/t32v path>. No proprietary assets or screenshots belong in git.
## tier C: synthetic names, levels/jobs and option indices stage the UI evidence; they are not gameplay tuning.

var flow: SceneFlow
var shots := ""
var missing := PackedStringArray()


func _ready() -> void:
	var flags := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(flags.get("shots", ""))
	if shots.is_empty():
		push_error("character_driver requires --shots=<absolute evidence path>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var save_path := shots.path_join("driver_save.json")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix):
			DirAccess.remove_absolute(save_path + suffix)
	flow = SceneFlow.new()
	flow.save = SaveData.new(save_path)
	flow.host = Node.new()
	add_child(flow.host)
	add_child(flow)
	flow.goto_title()
	await get_tree().create_timer(9.0).timeout # tier C: wait for WZ's 8s logo fade before visual comparison.
	await _shot("title")
	flow.goto_character_select()
	await _shot("empty_slots")
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	await _shot("creation_name")
	creation.name_edit.text = "bad!"
	creation.create_button.pressed.emit()
	await _shot("invalid_name")
	creation.name_edit.text = "MapleBoy"
	creation.create_button.pressed.emit()
	for gender in 2:
		await _shot("creation_%s_default" % ("male" if gender == 0 else "female"))
		for field: String in CharacterCreation.FIELDS:
			# Draw every allowed option for each gender; hair colours cross every base hair too.
			for _i in creation.model.options(gender, field).size():
				creation.find_child("Next_" + field, true, false).pressed.emit()
				RenderingServer.force_draw()
				if field == "hair":
					for _c in creation.model.options(gender, "hair_colour").size():
						creation.find_child("Next_hair_colour", true, false).pressed.emit()
						RenderingServer.force_draw()
			creation.find_child("Next_" + field, true, false).pressed.emit()
			if field in ["hair_colour", "weapon"]:
				await _shot("creation_%s_%s_changed" % ["male" if gender == 0 else "female", field])
		missing.append_array(creation.avatar.missing)
		if gender == 0:
			creation.find_child("Next_gender", true, false).pressed.emit()
	creation.name_edit.text = "MapleGirl"
	# Actually create through the form, then render the persisted look at select and in a round.
	creation.create_button.pressed.emit()
	await get_tree().process_frame
	var created: Dictionary = flow.save.slot(0).character.duplicate(true)
	flow.save_and_quit()
	await _shot("one_character")
	for avatar: AvatarRenderer in flow.current.avatars:
		missing.append_array(avatar.missing)
	flow.start_run("henesys_hg1", 70, {"character": created, "use_flow": false})
	await _shot("round_created_look")
	var run := flow.current as RunScene
	_collect_run(run)
	# Supply a completed boundary through SceneFlow to verify the same created look in the merged hub.
	flow.active_slot = 0
	flow.finish_run({"stage": "henesys_hg1", "cleared": true, "time": 960.0, "level": 1,
		"job_id": 0, "job_name": "Beginner", "kills": 0, "damage_dealt": 0, "seed": 70}, created)
	await _shot("free_market_created_look")
	var hub := flow.current as FreeMarket
	missing.append_array(hub.missing_paths())
	flow.save.end_run(0, "deleted", "2026-10-16T12:00:00")
	var model := CharacterCreation.new(Assets.img(CharacterCreation.IMG).root)
	var loader := SceneFlow.equipment_info_loader()
	for i in 3:
		var weapon: int = model.options(0, "weapon")[i]
		var character := SceneFlow.new_character(model.look(i % 2, {"face": i, "hair": i, "hair_colour": i,
			"skin": i, "top": i, "bottom": i, "shoes": i}), weapon, loader)
		_write("weapon_%d.json" % weapon, character)
		var wrapper := {"name": ["Fallen70", "Victor70", "Retired70"][i], "character": character,
			"created": "2026-10-16T12:00:00", "tier": i, "phase": "map_select",
			"rounds_played": i + 1, "tiers_cleared": i}
		flow.save.create_slot(wrapper)
		flow.save.end_run(0, ["died", "victory", "deleted"][i], "2026-10-16T13:00:00")
	for i in 3:
		var character := SceneFlow.new_character(model.look(i % 2, {"face": i, "hair": i, "hair_colour": i,
			"skin": i, "top": i, "bottom": i, "shoes": i}), model.options(0, "weapon")[i], loader)
		if i > 0:
			character.job_id = 200 if i == 1 else 220
			character.level = 10 if i == 1 else 35
			# As after the Magician advancement: the granted Wooden Wand is worn, the creation weapon kept.
			var wand: Dictionary = SceneFlow.new_character({}, 1372005, loader).equipment.worn.weapon
			Equipment.grant(character.equipment, wand, 24)
		flow.save.create_slot({"name": ["SwordMaple", "MapleGirl", "AxeMaple"][i], "character": character,
			"created": "2026-10-16T12:00:00", "tier": 0, "phase": "map_select",
			"rounds_played": i, "tiers_cleared": 0})
	flow.goto_character_select()
	await _shot("three_characters")
	for avatar: AvatarRenderer in flow.current.avatars:
		missing.append_array(avatar.missing)
	flow.current.select_button.grab_focus()
	await _key(KEY_RIGHT)
	if flow.current.selected != 1:
		push_error("character_driver: Right did not select while Start had keyboard focus")
		get_tree().quit(1)
		return
	await _shot("selection_changed")
	await _key(KEY_RIGHT)
	await _shot("selection_third")
	await _key(KEY_LEFT)
	await _shot("keyboard_focus")
	flow.current.delete_button.pressed.emit()
	await _shot("delete_confirmation")
	flow.current.delete_dialog.cancel()
	await _shot("history_entry")
	flow.current.find_child("RunHistory", true, false).pressed.emit()
	await _shot("history")
	# tier C: staged tier-2 boundary for the #90 visual check; no gameplay or clear claim.
	var tier_two := flow.save.slot(0)
	tier_two.tier = 1
	tier_two.phase = "map_select"
	flow.save.update_slot(0, tier_two)
	flow.continue_character(0)
	await get_tree().create_timer(2.0).timeout
	await _shot("map_select_tier2")
	missing.append_array(Assets.missing)
	_write("summary.json", {"missing": missing, "slots": flow.save.slots.size(), "history": flow.save.history.size()})
	print("character_driver missing=", missing)
	get_tree().quit(0 if missing.is_empty() else 1)


func _collect_run(run: RunScene) -> void:
	missing.append_array(run.setup_missing)
	missing.append_array(run.map.missing)
	missing.append_array(run.avatar.missing)
	for renderer: MobRenderer in run.mob_renderers:
		for id in renderer.missing:
			missing.append("Mob.wz/%07d.img" % id)


func _shot(name: String) -> void:
	await get_tree().create_timer(0.5).timeout
	if flow.current.get("backdrop") != null:
		missing.append_array(flow.current.backdrop.map.missing)
	_collect_ui(flow.current)
	RenderingServer.force_draw()
	var error := get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	print("character_driver shot ", name, " error=", error)


func _key(key: Key) -> void:
	for down: bool in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = down
		Input.parse_input_event(event)
		await get_tree().process_frame


func _collect_ui(node: Node) -> void:
	# UiArt treats missing art as optional; the evidence probe makes every displayed control mandatory.
	if node is WzImage and not node.has_art():
		missing.append(node.path)
	elif node is WzButton and not node.has_art():
		missing.append(node.base_path)
	for child: Node in node.get_children():
		_collect_ui(child)


func _write(name: String, value: Dictionary) -> void:
	var file := FileAccess.open(shots.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
