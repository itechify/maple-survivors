extends TestCase
## AssetLibrary on a synthetic cache: index, img/node/anim caching, missing-lookup recording, sounds, String.wz names.

const AF := preload("res://tests/fixtures/asset_fixtures.gd")

var lib: AssetLibrary


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open(AF.write_cache())


func after_each() -> void:
	lib.free()


func test_has_cache_and_split() -> void:
	assert_true(lib.has_cache())
	var other := AssetLibrary.new()
	assert_false(other.open("user://_test_cache/does_not_exist"), "no cache.json")
	other.free()
	assert_eq(AssetLibrary.split_path("Mob.wz/0100100.img/move/0"), PackedStringArray(["Mob.wz/0100100.img", "move/0"]))
	assert_eq(AssetLibrary.split_path("Mob.wz/0100100.img"), PackedStringArray(["Mob.wz/0100100.img", ""]))


func test_img_node_anim() -> void:
	var w := lib.img("Test.wz/Sprite.img")
	assert_true(w != null)
	assert_true(lib.img("Test.wz/Sprite.img") == w, "img cached")
	assert_eq(lib.node("Test.wz/Sprite.img/info/speed"), -65.0)
	assert_eq(WzImg.region(lib.node("Test.wz/Sprite.img/group/ref")), Rect2(10, 0, 4, 4), "UOL through the library")
	var a := lib.anim("Test.wz/Sprite.img/anim")
	assert_eq(a.frame_count(), 3)
	assert_true(lib.anim("Test.wz/Sprite.img/anim") == a, "anim cached")
	assert_true(a.frames[0].page == a.frames[2].page, "frames share the page texture")
	assert_eq(lib.pages_loaded(), 1)
	var f := lib.frame("Test.wz/Sprite.img/single")
	assert_true(f != null and f.region == Rect2(15, 0, 4, 4))
	assert_eq(lib.missing.size(), 0, "no misses so far: %s" % [lib.missing])


func test_missing_lookups_recorded() -> void:
	assert_eq(lib.node("Test.wz/Sprite.img/nope"), null)
	assert_eq(lib.img("Nope.wz/Nothing.img"), null)
	assert_true(lib.anim("Test.wz/Sprite.img/info").is_empty())
	assert_eq(lib.find("Test.wz/Sprite.img/nope2"), null, "find() does not record")
	assert_eq(lib.find_anim("Test.wz/Sprite.img/nope3"), null)
	assert_has(lib.missing, "Test.wz/Sprite.img/nope")
	assert_has(lib.missing, "Nope.wz/Nothing.img")
	assert_has(lib.missing, "Test.wz/Sprite.img/info")
	assert_false("Test.wz/Sprite.img/nope2" in lib.missing)
	assert_eq(lib.missing.size(), 3)
	lib.clear_missing()
	assert_eq(lib.missing.size(), 0)


func test_sound_wav() -> void:
	var s := lib.sound("Sound.wz/Test.img/beep")
	assert_true(s is AudioStreamWAV, "WAV loaded from buffer")
	if s != null:
		assert_near(s.get_length(), 200.0 / 22050.0, 1e-3)
	assert_true(lib.sound("Sound.wz/Test.img/beep") == s, "cached")
	assert_eq(lib.sound("Sound.wz/Test.img/none"), null)
	assert_has(lib.missing, "Sound.wz/Test.img/none")


func test_string_lookups() -> void:
	assert_eq(lib.string_name("Mob", 100100), "Snail", "Mob keys are unpadded")
	assert_eq(lib.string_name("Skill", 1000), "Three Snails", "Skill keys are 7-digit")
	assert_eq(lib.string_name("Book", 200), "Intro. to Magic")
	assert_eq(lib.string_name("Map", 104040000), "Henesys Hunting Ground I", "Map ids grouped by region")
	assert_eq(lib.string_name("Street", 104040000), "Victoria Road")
	assert_eq(lib.string_name("Mob", 999), "", "unknown -> empty")


func test_path_helpers() -> void:
	assert_eq(AssetLibrary.map_img_path(104040000), "Map.wz/Map/Map1/104040000.img")
	assert_eq(AssetLibrary.map_img_path(10000), "Map.wz/Map/Map0/000010000.img")
	assert_eq(AssetLibrary.mob_img_path(100100), "Mob.wz/0100100.img")
	assert_eq(AssetLibrary.item_icon_path(4000019), "Item.wz/Etc/0400.img/04000019/info/iconRaw")
	assert_eq(AssetLibrary.item_icon_path(2000000, false), "Item.wz/Consume/0200.img/02000000/info/icon")
	assert_eq(AssetLibrary.bgm_path("Bgm01/CavaBien"), "Sound.wz/Bgm01.img/CavaBien")


func test_mob_link_followed_keeping_own_info() -> void:
	assert_eq(lib.mob_anim_img_path(100101), "Mob.wz/0100100.img", "animations come from the link target")
	assert_eq(lib.mob_anim_img_path(100100), "Mob.wz/0100100.img")
	var r := lib.mob_root(100101)
	assert_eq(r.info.maxHP, 99.0, "own stats kept")
	assert_eq(r.info.link, "0100100")
	assert_true(r.has("stand") and r.has("die1"), "stances copied from the target")
	assert_false(r.has("$pages"), "no page list: copied canvases index the target's pages")
	var own := lib.mob_root(100100)
	assert_eq(own.info.maxHP, 8.0)
	assert_eq(lib.mob_root(4242), {}, "unknown mob")
	assert_true(lib.img("Mob.wz/0100100.img").root.has("$pages"), "cached tree keeps its pages")
