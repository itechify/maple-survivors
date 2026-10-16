extends Node
## Ticket #70 visual probe. Uses an evidence-only save, captures both creation genders, three slots, history,
## deletion confirmation and a one-off round in a chosen look. Writes fresh weapon snapshots for smoke tooling.
## Run with ISOLATE=t70 and the private cache: godot --path <mirror> res://scenes/debug/character_driver.tscn
## -- --shots=<absolute evidence/t70 path>. No proprietary assets or screenshots belong in git.
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
	flow.goto_character_select()
	await _shot("empty_slots")
	flow.current.show_creation()
	await _shot("creation_male")
	var creation: Control = flow.current.creation
	creation.name_edit.text = "bad!"
	creation.create_button.pressed.emit()
	await _shot("invalid_name")
	creation.cycle_option("gender", 1)
	for field: String in ["face", "hair", "hair_colour", "skin", "top", "bottom", "shoes", "weapon"]:
		# Exercise every runtime option once to detect missing imported parts, not just the default preview.
		for _i in creation.model.options(1, field).size():
			creation.cycle_option(field, 1)
		creation.cycle_option(field, -1)
	creation.name_edit.text = "MapleGirl"
	await _shot("creation_female")
	missing.append_array(creation.avatar.missing)
	creation.cancelled.emit()
	var data := DataRepo.load_all()
	var base := RunWorld.new({"data": data}).character_snapshot()
	var model := CharacterCreation.new(Assets.img(CharacterCreation.IMG).root)
	for i in 3:
		var character := base.duplicate(true)
		character.look = model.look(i % 2, {"face": i, "hair": i, "hair_colour": i,
			"skin": i, "top": i, "bottom": i, "shoes": i})
		character.beginner_weapon = model.options(0, "weapon")[i]
		_write("weapon_%d.json" % int(character.beginner_weapon), character)
		var wrapper := {"name": ["Fallen70", "Victor70", "Retired70"][i], "character": character,
			"created": "2026-10-16T12:00:00", "tier": i, "phase": "map_select",
			"rounds_played": i + 1, "tiers_cleared": i}
		flow.save.create_slot(wrapper)
		flow.save.end_run(0, ["died", "victory", "deleted"][i], "2026-10-16T13:00:00")
	for i in 3:
		var character := base.duplicate(true)
		character.look = model.look(i % 2, {"face": i, "hair": i, "hair_colour": i,
			"skin": i, "top": i, "bottom": i, "shoes": i})
		character.beginner_weapon = model.options(0, "weapon")[i]
		if i > 0:
			character.job_id = 200 if i == 1 else 220
			character.level = 10 if i == 1 else 35
		flow.save.create_slot({"name": ["SwordMaple", "MapleGirl", "AxeMaple"][i], "character": character,
			"created": "2026-10-16T12:00:00", "tier": 0, "phase": "map_select",
			"rounds_played": i, "tiers_cleared": 0})
	flow.goto_character_select()
	await _shot("three_characters")
	for avatar: AvatarRenderer in flow.current.avatars:
		missing.append_array(avatar.missing)
	flow.current._confirm_delete(2)
	await _shot("delete_confirmation")
	flow.current.delete_dialog.hide()
	flow.goto_history()
	await _shot("history")
	var selected: Dictionary = DataRepo.load_json(shots.path_join("weapon_1322005.json"))
	flow.start_run("henesys_hg1", 70, {"character": selected, "use_flow": false})
	await _shot("round_chosen_look")
	var run := flow.current as RunScene
	missing.append_array(run.setup_missing)
	missing.append_array(run.avatar.missing)
	missing.append_array(Assets.missing)
	_write("summary.json", {"missing": missing, "slots": flow.save.slots.size(), "history": flow.save.history.size()})
	print("character_driver missing=", missing)
	get_tree().quit(0 if missing.is_empty() else 1)


func _shot(name: String) -> void:
	await get_tree().create_timer(0.5).timeout
	RenderingServer.force_draw()
	var error := get_viewport().get_texture().get_image().save_png(shots.path_join(name + ".png"))
	print("character_driver shot ", name, " error=", error)


func _write(name: String, value: Dictionary) -> void:
	var file := FileAccess.open(shots.path_join(name), FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t"))
