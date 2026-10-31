extends TestCase
## The per-region stage files (spec #449 C0, DataRepo.load_stages, docs/ARCHITECTURE.md 4.4.4): `survivor/stages.json`
## holds `progression` and the notes, `survivor/stages/<key>.json` one stage each. Merge rules are tested on synthetic
## fixture directories; the shipped split is proven lossless against the pre-split file (`fixtures/stages_presplit.json`).

const WORK := "stage_files"
const PRESPLIT := "res://tests/fixtures/stages_presplit.json"


func after_each() -> void:
	remove_tree(test_dir(WORK))


func _put(rel: String, value: Dictionary) -> String:
	var root := test_dir(WORK)
	var path := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "\t", false))
	file.close()
	return root


func test_region_files_merge_in_progression_order_then_by_name() -> void:
	var root := _put("survivor/stages.json", {"_doc": "x", "progression": ["b", "a"], "stages": {}})
	_put("survivor/stages/a.json", {"region": "A"})
	_put("survivor/stages/b.json", {"region": "B"})
	_put("survivor/stages/z_tool.json", {"region": "Z"})
	_put("survivor/stages/c_tool.json", {"region": "C"})
	var errors := PackedStringArray()
	var stages := DataRepo.load_stages(root, errors)
	assert_eq(Array(errors), [])
	assert_eq(stages.stages.keys(), ["b", "a", "c_tool", "z_tool"], "progression order, then the others by name")
	assert_eq(stages.stages.a, {"region": "A"})
	assert_eq(stages.progression, ["b", "a"])
	assert_eq(stages._doc, "x", "the base file's own keys survive")


func test_an_inline_entry_comes_first_and_a_duplicate_is_an_error() -> void:
	var root := _put("survivor/stages.json", {"progression": ["a"], "stages": {"inline": {"region": "I"}, "a": {"region": "base"}}})
	_put("survivor/stages/a.json", {"region": "file"})
	_put("survivor/stages/b.json", {"region": "B"})
	var errors := PackedStringArray()
	var stages := DataRepo.load_stages(root, errors)
	assert_eq(stages.stages.keys(), ["inline", "a", "b"])
	assert_eq(stages.stages.a.region, "base", "the first value is kept")
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("a.json") and errors[0].contains("duplicate stage 'a'"), errors[0])


func test_a_missing_folder_is_fine_and_a_bad_file_or_base_is_reported() -> void:
	var root := _put("survivor/stages.json", {"progression": [], "stages": {"only": {"region": "O"}}})
	var errors := PackedStringArray()
	assert_eq(DataRepo.load_stages(root, errors).stages.keys(), ["only"])
	assert_eq(errors.size(), 0)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("survivor/stages")))
	var file := FileAccess.open(root.path_join("survivor/stages/bad.json"), FileAccess.WRITE)
	file.store_string("{")
	file.close()
	DataRepo.load_stages(root, errors)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("cannot read") and errors[0].contains("bad.json"), errors[0])
	errors.clear()
	assert_eq(DataRepo.load_stages(test_dir("no_such_stage_files"), errors), {})
	assert_eq(errors.size(), 1)


func test_the_shipped_split_equals_the_pre_split_file() -> void:
	var before: Variant = DataRepo.load_json(PRESPLIT)
	assert_true(before is Dictionary, "the pre-split fixture reads")
	var errors := PackedStringArray()
	var merged := DataRepo.load_stages(DataRepo.DATA_ROOT, errors)
	assert_eq(Array(errors), [])
	var kept: Array = before.stages.keys()
	for key: String in kept:
		assert_true(merged.stages.has(key), "%s is a region file" % key)
		# Byte for byte: the same JSON text, key order and all (stringify without sorting keeps insertion order).
		assert_eq(JSON.stringify(merged.stages[key], "\t", false), JSON.stringify(before.stages[key], "\t", false),
			"%s is unchanged by the split" % key)
	assert_eq(merged.stages.keys().slice(0, kept.size()), kept, "the five regions keep their order")
	assert_eq(merged.progression.slice(0, kept.size()), before.progression, "progression starts as before")
	for key: String in ["_progression", "_drop_band"]:
		assert_eq(merged[key], before[key], key)


func test_every_stage_file_is_named_after_a_stage_key_and_in_the_progression() -> void:
	var dir := DirAccess.open("res://data/survivor/stages")
	assert_true(dir != null, "the stages folder exists")
	var data := DataRepo.load_stages()
	for file in dir.get_files():
		var key := file.trim_suffix(".json")
		assert_true(file.ends_with(".json"), "%s is JSON" % file)
		assert_true(data.progression.has(key), "%s is listed in progression (a tool-only stage needs a reason)" % key)
		assert_true(data.stages[key].has("maps"), "%s holds a stage object (no wrapper)" % key)
	for key: String in data.progression:
		assert_true(FileAccess.file_exists("res://data/survivor/stages/%s.json" % key), "%s has its file" % key)
	assert_eq(data.stages.keys().filter(func(k: String) -> bool: return not data.progression.has(k)), [],
		"no stage outside the progression ships")
