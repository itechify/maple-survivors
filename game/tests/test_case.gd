class_name TestCase
extends RefCounted
## Base class for unit tests (see tests/test_runner.gd).
##
## A test file is res://tests/unit/test_<topic>.gd extending TestCase; every method named test_* runs once on a fresh
## instance. Assertions record failures and keep going so one run reports everything. Tests must be deterministic:
## seed every RNG, never depend on autoload state, wall-clock time or the network. The runner starts from the project's
## default key bindings and default Settings (scratch config), so tests never see the developer's settings.cfg.
##
## Tests that need the imported v83 asset cache call `require_cache()` first and return early when it is absent; the
## runner reports them as SKIP (they pass, but prove nothing without the cache).

## Root of the scratch files tests write to the user data dir.
const TEST_ROOT := "user://_test_cache"

var failures: PackedStringArray = []
var skipped := ""
var current_test := ""


func before_each() -> void:
	pass


func after_each() -> void:
	pass


func fail(msg: String) -> void:
	failures.append("%s: %s" % [current_test, msg])


## Marks the test as skipped (reported, not failed).
func skip(reason: String) -> void:
	skipped = reason


## A scratch path private to this Godot process: user://_test_cache/<pid>[/sub]. Every test run shares the user data
## dir (also isolated ISOLATE mirrors and other agents' runs), so fixtures never use a fixed path there; the runner
## deletes the folder when it finishes.
static func test_dir(sub: String = "") -> String:
	var d := TEST_ROOT.path_join(str(OS.get_process_id()))
	return d.path_join(sub) if sub != "" else d


## Deletes a folder of the user data dir with everything in it (test scratch cleanup).
static func remove_tree(path: String) -> void:
	var abs_path := ProjectSettings.globalize_path(path)
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	for d in dir.get_directories():
		remove_tree(abs_path.path_join(d))
	for f in dir.get_files():
		DirAccess.remove_absolute(abs_path.path_join(f))
	DirAccess.remove_absolute(abs_path)


## True when the asset cache is available; otherwise marks the test skipped. Usage:
##   if not require_cache(): return
func require_cache() -> bool:
	var root := AssetCachePaths.resolve_cache_root()
	if root == "" or not FileAccess.file_exists(root.path_join("cache.json")):
		skip("asset cache not imported (run scripts/import.sh)")
		return false
	return true


## Interim #243 runs map 0: tolerate only absent assets belonging to later maps until the #242 cache is imported.
static func interim_missing(missing: PackedStringArray, data: Dictionary, stage_key: String = "") -> PackedStringArray:
	if stage_key.is_empty():
		var across_stages := missing
		for key: String in data.get("stages", {}).get("stages", {}):
			across_stages = interim_missing(across_stages, data, key)
		return across_stages
	var later := PackedStringArray()
	var maps := DataRepo.stage_maps(data, stage_key)
	var stage: Dictionary = data.get("stages", {}).get("stages", {}).get(DataRepo.canonical_stage_key(stage_key), {})
	var active := PackedInt32Array()
	for frame: Dictionary in stage.get("keyframes", []):
		for id: Variant in frame.get("pool", {}):
			active.append(int(id))
	for boss: Dictionary in DataRepo.stage_bosses(stage):
		active.append(int(boss.get("mob_id", 0)))
	for i in range(1, maps.size()):
		later.append(DataRepo.map_img_path(int(maps[i].map_id)))
		if maps[i].get("pool") is Dictionary:
			for id: Variant in maps[i].pool:
				if not int(id) in active:
					later.append("Mob.wz/%07d.img" % int(id))
	var remaining := PackedStringArray()
	for path in missing:
		if not path in later:
			remaining.append(path)
	return remaining


## Unavailable future-only ordinary mobs may warn during interim preloading; active mobs and boss warnings stay strict.
static func interim_warnings(warnings: PackedStringArray, data: Dictionary, stage_key: String) -> PackedStringArray:
	var remaining := PackedStringArray()
	var pattern := RegEx.create_from_string("^no mob img for ([0-9]+): dropped from the pools$")
	for warning in warnings:
		var found := pattern.search(warning)
		if found != null and interim_missing(PackedStringArray(["Mob.wz/%07d.img" % int(found.get_string(1))]),
				data, stage_key).is_empty():
			continue
		remaining.append(warning)
	return remaining


func assert_true(cond: bool, msg: String = "expected true") -> void:
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "expected false") -> void:
	if cond:
		fail(msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	if typeof(actual) != typeof(expected) and not (_is_num(actual) and _is_num(expected)):
		fail("%s expected %s (%s) got %s (%s)" % [msg, var_to_str(expected), type_string(typeof(expected)),
			var_to_str(actual), type_string(typeof(actual))])
	elif actual != expected:
		fail("%s expected %s got %s" % [msg, var_to_str(expected), var_to_str(actual)])


func assert_ne(actual: Variant, unexpected: Variant, msg: String = "") -> void:
	if actual == unexpected:
		fail("%s expected anything but %s" % [msg, var_to_str(unexpected)])


func assert_near(actual: float, expected: float, eps: float = 1e-6, msg: String = "") -> void:
	if not is_finite(actual) or not is_finite(expected) or not is_finite(eps) or eps < 0.0 \
			or absf(actual - expected) > eps:
		fail("%s expected %s +/- %s got %s" % [msg, expected, eps, actual])


func assert_between(actual: float, lo: float, hi: float, msg: String = "") -> void:
	if not is_finite(actual) or not is_finite(lo) or not is_finite(hi) or lo > hi or actual < lo or actual > hi:
		fail("%s expected in [%s, %s] got %s" % [msg, lo, hi, actual])


func assert_has(container: Variant, key: Variant, msg: String = "") -> void:
	var ok := false
	if container is Dictionary:
		ok = container.has(key)
	elif container is Array or container is PackedStringArray or container is PackedInt32Array:
		ok = key in container
	if not ok:
		fail("%s missing %s" % [msg, var_to_str(key)])


func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
