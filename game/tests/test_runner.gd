class_name TestRunner
extends Node
## Headless unit test runner. Discovers res://tests/unit/test_*.gd (TestCase subclasses) and runs every test_* method.
##
##   bash scripts/test.sh                  # import + run everything
##   bash scripts/test.sh combat footholds # only files whose name contains one of the filters
##
## Exit code 0 = all passed, 1 = failures. Output: one line per failing assertion, one per skipped test, a summary.

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
	for path in files:
		var script: GDScript = load(path) if ResourceLoader.exists(path) else null
		if script == null or not script.can_instantiate():
			print("FAIL %s: script failed to load or compile" % path)
			failed += 1
			total += 1
			continue
		var methods: Array = []
		for m in script.get_script_method_list():
			if String(m.name).begins_with("test_") and not (m.name in methods):
				methods.append(m.name)
		methods.sort()
		for m in methods:
			var tc: TestCase = script.new()
			tc.current_test = "%s::%s" % [path.get_file().get_basename(), m]
			guard.clear()
			tc.before_each()
			tc.call(m)
			tc.after_each()
			total += 1
			for e in guard.errors():
				tc.fail("script error: " + e)
			if not tc.failures.is_empty():
				failed += 1
				for f in tc.failures:
					print("FAIL " + f)
			elif tc.skipped != "":
				skipped += 1
				print("SKIP %s: %s" % [tc.current_test, tc.skipped])
	guard.detach()
	TestCase.remove_tree(TestCase.test_dir())
	print("\n%d tests, %d failed, %d skipped, %d files (%d ms)" % [total, failed, skipped, files.size(),
		Time.get_ticks_msec() - t0])
	print("TESTS_PASSED" if failed == 0 else "TESTS_FAILED")
	return 0 if failed == 0 else 1


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
