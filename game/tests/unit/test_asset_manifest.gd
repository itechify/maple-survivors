extends TestCase
## AssetManifest (docs/ASSET_PIPELINE.md 4.1): the asset manifest plus its asset_manifest.d/*.json include fragments are
## merged in file-name order, a key in two files is an error naming both, and the shipping manifest still names what the
## game's data needs. The Rust side (tools/wzimport, manifest.rs) has the golden test of the whole selection.

const MAIN := {"format": 1, "_doc": "x", "imgs": [{"img": "A.wz/a.img"}, {"img": "S.wz/s.img", "paths": ["1", "2"]}],
	"maps": [1.0], "mobs": [7.0], "character": [2000.0], "items": [4000000.0]}
const TMP := "user://asset_manifest_test"


func _frag(name: String, data: Dictionary) -> Dictionary:
	return {"name": name, "data": data}


func test_fragments_are_appended_after_the_main_file() -> void:
	var r := AssetManifest.merge("asset_manifest.json", MAIN, [
		_frag("a.json", {"_doc": "a", "imgs": [{"img": "S.wz/s.img", "paths": ["3"]}, {"img": "B.wz/b.img"}], "mobs": [8.0]}),
		_frag("b.json", {"format": 1, "maps": [2.0], "mapimgs": ["U.wz/m.img"], "character": [1372000.0], "items": [4000001.0]})])
	assert_eq(r.error, "")
	var m: Dictionary = r.manifest
	assert_eq(m.imgs.size(), 4)
	assert_eq(m.maps, [1.0, 2.0])
	assert_eq(m.mobs, [7.0, 8.0])
	assert_eq(m.character, [2000.0, 1372000.0])
	assert_eq(m.items, [4000000.0, 4000001.0])
	assert_eq(m.mapimgs, ["U.wz/m.img"])
	assert_eq(m.format, 1)


func test_a_key_in_two_files_is_an_error_naming_both() -> void:
	var cases := {
		"map 1": {"maps": [1.0]},
		"mob 7": {"mobs": [7.0]},
		"character 2000": {"character": [2000.0]},
		"item 4000000": {"items": [4000000.0]},
		"`img A.wz/a.img`": {"imgs": [{"img": "A.wz/a.img"}]},
		"path \"2\"": {"imgs": [{"img": "S.wz/s.img", "paths": ["2", "9"]}]},
		"`img A.wz/a.img` ": {"imgs": [{"img": "A.wz/a.img", "paths": ["x"]}]},
		"`img S.wz/s.img`": {"imgs": [{"img": "S.wz/s.img"}]},
	}
	for what: String in cases:
		var r := AssetManifest.merge("asset_manifest.json", MAIN, [_frag("wizard.json", cases[what])])
		assert_ne(r.error, "", "duplicate %s is an error" % what)
		assert_true(str(r.error).contains(what.strip_edges()), "%s named in: %s" % [what, r.error])
		assert_true(str(r.error).contains("asset_manifest.json") and str(r.error).contains("wizard.json"), str(r.error))
		assert_true(r.manifest.is_empty())
	var two := AssetManifest.merge("m.json", MAIN, [_frag("a.json", {"mobs": [9.0]}), _frag("b.json", {"mobs": [9.0]})])
	assert_true(str(two.error).contains("a.json") and str(two.error).contains("b.json"), str(two.error))
	assert_eq(AssetManifest.merge("m.json", MAIN, [_frag("a.json", {"mobs": [9.0, 9.0]})]).error, "", "repeat inside one file")
	assert_eq(AssetManifest.merge("m.json", MAIN, [_frag("a.json", {"imgs": [{"img": "S.wz/s.img", "paths": ["3"]}]})]).error, "",
		"other paths of the same img are fine")


func test_bad_fragments_are_rejected() -> void:
	for data: Dictionary in [{"mob": [1.0]}, {"format": 2}, {"mobs": "7"}, {"imgs": [{"paths": []}]}]:
		var r := AssetManifest.merge("m.json", MAIN, [_frag("bad.json", data)])
		assert_ne(r.error, "", "rejects %s" % [data])
		assert_true(str(r.error).contains("bad.json"), str(r.error))
	assert_ne(AssetManifest.merge("m.json", {"format": 2}, []).error, "", "main file format")


func test_region_fragments_hold_maps_mobs_and_items_without_overlap() -> void:
	var a := _frag("region_a.json", {"_doc": "region a", "maps": [220011000.0], "mobs": [3230101.0, 4130103.0], "items": [4000100.0]})
	var r := AssetManifest.merge("m.json", MAIN, [a, _frag("region_b.json", {"maps": [221040000.0], "mobs": [3230102.0], "items": [4000101.0]})])
	assert_eq(r.error, "")
	assert_eq([r.manifest.maps, r.manifest.mobs, r.manifest.items],
		[[1.0, 220011000.0, 221040000.0], [7.0, 3230101.0, 4130103.0, 3230102.0], [4000000.0, 4000100.0, 4000101.0]])
	for data: Dictionary in [{"mobs": [3230101.0]}, {"maps": [220011000.0]}, {"items": [4000100.0]}]:
		var e: Variant = AssetManifest.merge("m.json", MAIN, [a, _frag("region_c.json", data)]).error
		assert_true(str(e).contains("region_a.json") and str(e).contains("region_c.json"), "%s: %s" % [data, e])


func test_load_reads_the_sibling_folder_sorted_by_name() -> void:
	DirAccess.make_dir_recursive_absolute(TMP + "/asset_manifest.d")
	_write(TMP + "/asset_manifest.json", MAIN)
	assert_eq(AssetManifest.load_checked(TMP + "/asset_manifest.json").manifest.mobs, [7.0], "folder may hold nothing")
	_write(TMP + "/asset_manifest.d/b.json", {"mobs": [2.0]})
	_write(TMP + "/asset_manifest.d/a.json", {"mobs": [1.0]})
	var f := FileAccess.open(TMP + "/asset_manifest.d/notes.txt", FileAccess.WRITE)
	f.store_string("not json")
	f.close()
	assert_eq(AssetManifest.load_checked(TMP + "/asset_manifest.json").manifest.mobs, [7.0, 1.0, 2.0])
	_write(TMP + "/asset_manifest.d/c.json", {"mobs": [7.0]})
	var bad := AssetManifest.load_checked(TMP + "/asset_manifest.json")
	assert_true(str(bad.error).contains("asset_manifest.json") and str(bad.error).contains("c.json"), str(bad.error))
	assert_ne(AssetManifest.load_checked(TMP + "/missing.json").error, "")
	for name in ["asset_manifest.d/a.json", "asset_manifest.d/b.json", "asset_manifest.d/c.json", "asset_manifest.d/notes.txt",
			"asset_manifest.json"]:
		DirAccess.remove_absolute(TMP + "/" + name)
	DirAccess.remove_absolute(TMP + "/asset_manifest.d")
	DirAccess.remove_absolute(TMP)


func test_fragment_dir_is_named_after_the_manifest() -> void:
	assert_eq(AssetManifest.fragment_dir("res://data/asset_manifest.json"), "res://data/asset_manifest.d")


func test_to_json_writes_ids_as_integers_for_the_importer() -> void:
	var text := AssetManifest.to_json(MAIN)
	assert_true(text.contains("\"maps\":[1]") and text.contains("\"items\":[4000000]"), text)
	assert_false(text.contains(".0"), "no float ids: " + text)
	assert_eq(JSON.parse_string(text).imgs.size(), 2)


func test_shipping_manifest_merges_its_fragments() -> void:
	var m := AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_false(m.is_empty())
	var imgs := PackedStringArray()
	for row: Dictionary in m.imgs:
		imgs.append(row.img)
	for img in ["Skill.wz/000.img", "Skill.wz/200.img", "Skill.wz/230.img", "Sound.wz/Skill.img", "Map.wz/Physics.img"]:
		assert_true(img in imgs, "%s selected" % img)
	assert_true(1372000.0 in m.character, "wand from the Magician fragment")
	assert_true(2000.0 in m.character, "body from the shared file")
	assert_true(104040000.0 in m.maps)
	var sound_paths := PackedStringArray()
	for row: Dictionary in m.imgs:
		if row.img == "Sound.wz/Skill.img":
			sound_paths.append_array(PackedStringArray(row.paths))
	for p in ["0001000", "2001005", "2301005"]:
		assert_true(p in sound_paths, "Sound.wz/Skill.img/%s" % p)


func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
