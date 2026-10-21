extends TestCase
## Compile debug and developer scripts without instantiating them or starting their tool workflows.


func test_debug_scripts_parse() -> void:
	_assert_scripts_parse("res://scenes/debug")


func test_tool_scripts_parse() -> void:
	_assert_scripts_parse("res://tools")


func _assert_scripts_parse(root: String) -> void:
	var paths := PackedStringArray()
	_collect_scripts(root, paths)
	assert_true(not paths.is_empty(), "script census must not be empty: " + root)
	paths.sort()
	for path: String in paths:
		var script := load(path) as GDScript
		assert_true(script != null and script.can_instantiate(), "script must compile: " + path)


func _collect_scripts(path: String, paths: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	assert_true(dir != null, "script directory must exist: " + path)
	if dir == null:
		return
	for name: String in dir.get_files():
		if name.get_extension() == "gd":
			paths.append(path.path_join(name))
	for name: String in dir.get_directories():
		_collect_scripts(path.path_join(name), paths)
