extends TestCase
## AvatarRenderer anchor math and z ordering on synthetic parts (values from v83 stand1 frame 0, written by hand).


func _parts() -> Array:
	return [
		{"name": "body", "map": {"neck": Vector2(-4, -32), "navel": Vector2(-8, -21)}, "z": "body"},
		{"name": "arm", "map": {"navel": Vector2(-13, -1), "hand": Vector2(-1, 5)}, "z": "arm"},
		{"name": "face", "map": {"brow": Vector2(-1, -12)}, "z": "face"},
		{"name": "head", "map": {"neck": Vector2(0, 15), "brow": Vector2(-4, -5)}, "z": "head"},
		{"name": "hair", "map": {"brow": Vector2(0, 0)}, "z": "hair"},
		{"name": "weapon", "map": {"hand": Vector2(6, -5)}, "z": "weapon"},
		{"name": "mail", "map": {"navel": Vector2(-8, 1)}, "z": "mailChest"},
		{"name": "loose", "map": {"tail": Vector2(3, 3)}, "z": "nothing"},
		{"name": "nomap", "map": {}, "z": "body"},
	]


func test_layout_parts_anchor_chain() -> void:
	var pos := AvatarRenderer.layout_parts(_parts())
	assert_eq(pos[0], Vector2(0, 0), "body origin on the character origin")
	assert_eq(pos[1], Vector2(5, -20), "arm: body.navel - arm.navel")
	assert_eq(pos[3], Vector2(-4, -47), "head: body.neck - head.neck")
	assert_eq(pos[2], Vector2(-7, -40), "face: head brow (-8,-52) - face.brow (listed before the head: resolved later)")
	assert_eq(pos[4], Vector2(-8, -52), "hair on the brow")
	assert_eq(pos[5], Vector2(-2, -10), "weapon: arm hand (4,-15) - weapon.hand")
	assert_eq(pos[6], Vector2(0, -22), "coat by navel")
	assert_eq(pos[7], Vector2(0, 0), "no common anchor: stays at the origin")
	assert_eq(pos[8], Vector2(0, 0), "no map: at the origin")


func test_first_existing_anchor_wins_and_new_ones_added() -> void:
	var parts := [
		{"map": {"navel": Vector2(0, -10)}},
		{"map": {"hand": Vector2(1, 1), "navel": Vector2(2, 2)}},
		{"map": {"hand": Vector2(0, 0)}},
	]
	var pos := AvatarRenderer.layout_parts(parts)
	assert_eq(pos[1], Vector2(-2, -12), "hand unknown yet, attaches by navel")
	assert_eq(pos[2], Vector2(-1, -11), "the hand anchor added by part 1")


func test_sort_by_z_back_to_front() -> void:
	var zorder := {"face": 0, "hair": 1, "weapon": 2, "head": 3, "arm": 4, "mailChest": 5, "body": 6}
	var sorted := AvatarRenderer.sort_by_z(_parts(), zorder)
	var names: PackedStringArray = []
	for p: Dictionary in sorted:
		names.append(p.name)
	assert_eq(names, PackedStringArray(["loose", "body", "nomap", "mail", "arm", "head", "weapon", "hair", "face"]),
		"zmap lists front-most first; unknown names at the very back; ties keep order")


func test_frame_timing() -> void:
	var d := PackedFloat32Array([0.18, 0.18, 0.18, 0.18])
	assert_eq(AvatarRenderer.frame_at(d, 0.0, true), 0)
	assert_eq(AvatarRenderer.frame_at(d, 0.19, true), 1)
	assert_eq(AvatarRenderer.frame_at(d, 0.73, true), 0, "loops after 0.72 s")
	assert_eq(AvatarRenderer.frame_at(d, 5.0, false), 3, "one-shot holds the last frame")
	assert_eq(AvatarRenderer.frame_at(PackedFloat32Array([0.5]), 3.0, true), 0)


func test_part_paths() -> void:
	assert_eq(AvatarRenderer.part_img_path(2000), "Character.wz/00002000.img")
	assert_eq(AvatarRenderer.part_img_path(12000), "Character.wz/00012000.img")
	assert_eq(AvatarRenderer.part_img_path(20000), "Character.wz/Face/00020000.img")
	assert_eq(AvatarRenderer.part_img_path(30030), "Character.wz/Hair/00030030.img")
	assert_eq(AvatarRenderer.part_img_path(1040002), "Character.wz/Coat/01040002.img")
	assert_eq(AvatarRenderer.part_img_path(1060002), "Character.wz/Pants/01060002.img")
	assert_eq(AvatarRenderer.part_img_path(1072001), "Character.wz/Shoes/01072001.img")
	assert_eq(AvatarRenderer.part_img_path(1302000), "Character.wz/Weapon/01302000.img")
	assert_eq(AvatarRenderer.part_img_path(1372005), "Character.wz/Weapon/01372005.img")
	assert_eq(AvatarRenderer.part_img_path(1002140), "Character.wz/Cap/01002140.img")


func test_default_look_is_game_design_section_1() -> void:
	# MakeCharInfo male default: face 20000, hair 30030, 1040002, 1060002, 1072001, and no weapon.
	assert_eq(AvatarRenderer.DEFAULT_LOOK, {"skin": 0, "face": 20000, "hair": 30030,
		"equips": [1040002, 1060002, 1072001]})
