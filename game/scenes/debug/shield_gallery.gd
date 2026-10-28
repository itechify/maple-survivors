extends Node2D
## Debug evidence shots of the shield slot (spec #151 #158): the real Henesys round with the Equip window open over the
## carried Lv38 fixture character, once with a one-handed sword and a shield, once with a two-handed sword and no shield,
## plus an avatar close-up of each (standing and walking).
##
##   MAPLE_SURVIVORS_CACHE=<cache with asset_manifest.d/warrior.json> bash scripts/godot.sh --path game
##       res://scenes/debug/shield_gallery.tscn -- --shots=C:/abs/dir [--shield=1092003] [--sword=1302000] [--two=1402000]
##
## Writes equip_sword_shield.png, equip_two_handed.png, avatar_sword_shield.png and avatar_two_handed.png. The Equip
## window shows the weapon and shield cells; the character is a snapshot edit (no requirement check), so a Magician
## fixture can wear the any-job shield 1092003.

const FIXTURE := "res://tests/fixtures/characters/fp_arch_mage.json"
const FRAMES := 30

var _shots := ""
var _shield := 1092003
var _sword := 1302000
var _two := 1402000


func _ready() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	_shots = String(args.get("shots", OS.get_user_data_dir().path_join("_test_cache")))
	_shield = int(args.get("shield", _shield))
	_sword = int(args.get("sword", _sword))
	_two = int(args.get("two", _two))
	DirAccess.make_dir_recursive_absolute(_shots)
	await _equip_shot("equip_sword_shield", _sword, _shield)
	await _equip_shot("equip_two_handed", _two, 0)
	await _avatar_shot("avatar_sword_shield", _sword, _shield)
	await _avatar_shot("avatar_two_handed", _two, 0)
	get_tree().quit()


## The fixture character wearing `weapon` and (when > 0) `shield` instead of what it wore.
func _character(weapon: int, shield: int) -> Dictionary:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(FIXTURE, errors)
	character.equipment.worn.weapon = _instance(weapon)
	character.equipment.worn.erase("shield")
	if shield > 0:
		character.equipment.worn["shield"] = _instance(shield)
	return character


func _instance(id: int) -> Dictionary:
	var img := AssetLibrary.get_default().img(AvatarRenderer.part_img_path(id))
	return Equipment.create(id, img.root.get("info", {}) if img != null else {})


func _equip_shot(file_name: String, weapon: int, shield: int) -> void:
	var scene: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	scene.configure("henesys", 2026, {"use_flow": false, "character": _character(weapon, shield)})
	add_child(scene)
	for _i in FRAMES:
		await get_tree().process_frame
	scene.toggle_window("equip")
	for _i in FRAMES:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(file_name + ".png"))
	print("shield_gallery: %s weapon=%d shield=%d worn=%s" % [file_name, weapon, shield,
		Equipment.worn_ids(scene.world.equipment.worn)])
	scene.queue_free()
	await get_tree().process_frame


func _avatar_shot(file_name: String, weapon: int, shield: int) -> void:
	RenderingServer.set_default_clear_color(Color(0.35, 0.45, 0.55))
	var holder := Node2D.new()
	add_child(holder)
	var look := DataRepo.character_look(_character(weapon, shield), {})
	var poses := [["stand1", -1, 0.0], ["stand1", 1, 0.0], ["walk1", -1, 0.25], ["walk1", 1, 0.25]]
	for i in poses.size():
		var a := AvatarRenderer.new()
		a.position = Vector2(190.0 * (i + 0.5), 250)
		a.scale = Vector2(3, 3)
		holder.add_child(a)
		a.set_look(look)
		a.play(poses[i][0], true)
		a.set_facing(poses[i][1])
		a.advance(poses[i][2])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	GameSettings.capture_logical(get_viewport(), img, Rect2(0, 0, 760, 300)).save_png(_shots.path_join(file_name + ".png"))
	var missing := PackedStringArray()
	for a in holder.get_children():
		for m in (a as AvatarRenderer).missing:
			if not m in missing:
				missing.append(m)
	print("shield_gallery: %s equips=%s missing=%s" % [file_name, look.equips, missing])
	holder.queue_free()
	await get_tree().process_frame
