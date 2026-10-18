extends TestCase
## #158 against the real v83 asset cache (SKIP without it): every Warrior shield of asset_manifest.d/warrior.json is
## imported with its canonical info and drawing layers, and the avatar draws a worn shield in the stances a swordsman
## stands and walks in. A SKIP proves nothing about the art; the synthetic layer tests are in test_avatar_cash_layers.

const FRAGMENT := "res://data/asset_manifest.d/warrior.json"
const SHIELD := 1092005 # reqJob 1, Lv 10, DEF 10
const OUTFIT := [1040002, 1060002, 1072001, 1302000]

var lib: AssetLibrary
var avatar: AvatarRenderer


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	if avatar != null and is_instance_valid(avatar):
		avatar.free()
	avatar = null
	lib.free()


func _shield_ids() -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FRAGMENT))
	assert_true(parsed is Dictionary, "the fragment parses")
	return (parsed as Dictionary).get("character", []).filter(
		func(id: Variant) -> bool: return Equipment.slot_of(int(id)) == "shield")


func test_every_listed_warrior_shield_is_imported_with_its_info_and_stand_layers() -> void:
	if not require_cache():
		return
	var ids := _shield_ids()
	assert_true(ids.size() > 30, "the fragment lists the Warrior shields")
	for raw: Variant in ids:
		var id := int(raw)
		var img := lib.img(AvatarRenderer.part_img_path(id))
		assert_true(img != null, "%d imported" % id)
		if img == null:
			continue
		var info: Dictionary = img.root.get("info", {})
		assert_true(int(info.get("reqJob", -1)) in [0, 1], "%d: Warrior or any-job" % id)
		assert_eq(int(info.get("cash", 0)), 0, "%d is not cash" % id)
		assert_true(info.has("incPDD") and (info.has("icon") or info.has("iconRaw")), "%d has defence and an icon" % id)
		assert_true(AvatarLayers.has_art(img, "stand1"), "%d draws while standing" % id)
		assert_true(AvatarLayers.has_art(img, "walk1"), "%d draws while walking" % id)


func test_the_avatar_draws_the_worn_shield_in_stand_and_walk() -> void:
	if not require_cache():
		return
	avatar = AvatarRenderer.new()
	avatar.library = lib
	avatar.set_look({"equips": OUTFIT + [SHIELD]})
	for stance in ["stand1", "walk1"]:
		var parts := avatar.compose(stance, 0, "default", 0.0)
		var owned := parts.filter(func(p: Dictionary) -> bool: return int(p.get("owner", 0)) == SHIELD)
		assert_true(owned.size() >= 1, "%s: a shield layer is drawn" % stance)
	assert_eq(avatar.missing, PackedStringArray(), "nothing failed to load")
