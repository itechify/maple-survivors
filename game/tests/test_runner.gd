class_name TestRunner
extends Node
## Headless unit test runner. Discovers res://tests/unit/test_*.gd (TestCase subclasses) and runs every test_* method.
##
##   bash scripts/test.sh                  # import + run everything
##   bash scripts/test.sh combat footholds # only files whose name contains one of the filters
##
## Exit code 0 = all passed, 1 = failures. Output: one line per failing assertion, one per skipped test, a summary.
## A failed file/discovery or empty selection counts as one failed check; failed + skipped never exceeds total.

const UNIT_DIR := "res://tests/unit"


func _ready() -> void:
	var filters: PackedStringArray = []
	for a in OS.get_cmdline_user_args():
		filters.append(a)
	get_tree().quit(run(filters))


func run(filters: PackedStringArray) -> int:
	var files := _discover(filters)
	_reset_global_settings()
	var t0 := Time.get_ticks_msec()
	var total := 0
	var failed := 0
	var skipped := 0
	var guard := ScriptErrorGuard.new()
	guard.attach()
	if files.is_empty():
		print("FAIL no test files selected in %s (filters: %s)" % [UNIT_DIR, filters])
		failed += 1
		total += 1
	for path in files:
		guard.clear()
		var script: GDScript = load(path) if ResourceLoader.exists(path) else null
		if script == null or not script.can_instantiate() or not guard.errors().is_empty():
			print("FAIL %s: script failed to load or compile: %s" % [path, guard.errors()])
			failed += 1
			total += 1
			continue
		var methods := _discover_methods(script)
		if methods.is_empty() or not guard.errors().is_empty():
			print("FAIL %s: test discovery failed or no non-static test_* methods found" % path)
			failed += 1
			total += 1
			continue
		for m in methods:
			# Count before invoking user code. An aborted invocation must never erase its test.
			total += 1
			guard.clear()
			var result := _run_test(script, m)
			var errors := guard.errors()
			if result.is_empty() or not errors.is_empty():
				failed += 1
				print("FAIL %s::%s: aborted test or script error: %s" % [path, m, errors])
			elif not result.failures.is_empty():
				failed += 1
			elif result.skipped != "":
				skipped += 1
				print("SKIP %s::%s: %s" % [path.get_file().get_basename(), m, result.skipped])
			for f in result.get("failures", []):
				print("FAIL " + f)
	guard.detach()
	TestCase.remove_tree(TestCase.test_dir())
	print("\n%d tests, %d failed, %d skipped, %d files (%d ms)" % [total, failed, skipped, files.size(),
		Time.get_ticks_msec() - t0])
	print("TESTS_PASSED" if failed == 0 else "TESTS_FAILED")
	return 0 if failed == 0 else 1


## Isolates construction and hooks too: a runtime error can abort this function, returning an empty result.
func _run_test(script: GDScript, method: StringName) -> Dictionary:
	var tc := script.new() as TestCase
	if tc == null:
		return {}
	tc.current_test = "%s::%s" % [script.resource_path.get_file().get_basename(), method]
	tc.before_each()
	tc.call(method)
	tc.after_each()
	return {"failures": tc.failures, "skipped": tc.skipped}


## The test_* methods of `script` and of the scripts it extends (a file may run another file's set for a second job, #312).
static func _discover_methods(script: GDScript) -> Array:
	var methods: Array = []
	var s: Script = script
	while s != null:
		for m in s.get_script_method_list():
			if String(m.name).begins_with("test_") and not (int(m.flags) & METHOD_FLAG_STATIC) \
					and not (m.name in methods):
				methods.append(m.name)
		s = s.get_base_script()
	methods.sort()
	return methods


## The Settings autoload already applied the developer's user://settings.cfg (rebinds, volumes): restart it from a
## scratch file, so tests see the defaults and never save over the real one (which AssetCachePaths still reads).
func _reset_global_settings() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TestCase.test_dir()))
	var settings := get_node_or_null("/root/Settings") as GameSettings
	if settings != null:
		settings.reload_from(TestCase.test_dir("settings.cfg"))


func _discover(filters: PackedStringArray) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		f = f.trim_suffix(".remap")
		if not (f.begins_with("test_") and f.get_extension() == "gd"):
			continue
		if not filters.is_empty():
			var keep := false
			for flt in filters:
				if flt in f:
					keep = true
			if not keep:
				continue
		out.append(UNIT_DIR.path_join(f))
	out.sort()
	return out
