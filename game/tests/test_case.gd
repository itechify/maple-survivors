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
	if absf(actual - expected) > eps:
		fail("%s expected %s +/- %s got %s" % [msg, expected, eps, actual])


func assert_between(actual: float, lo: float, hi: float, msg: String = "") -> void:
	if actual < lo or actual > hi:
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
