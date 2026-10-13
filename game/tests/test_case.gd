class_name TestCase
extends RefCounted
## Base class for unit tests (see tests/test_runner.gd).
##
## A test file is res://tests/unit/test_<topic>.gd extending TestCase; every method named test_* runs once on a fresh
## instance. Assertions record failures and keep going so one run reports everything. Tests must be deterministic:
## seed every RNG, never depend on autoload state, wall-clock time or the network.
##
## Tests that need the imported v83 asset cache call `require_cache()` first and return early when it is absent; the
## runner reports them as SKIP (they pass, but prove nothing without the cache).

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
