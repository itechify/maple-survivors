extends TestCase
## Web handoff (spec #130, docs/ARCHITECTURE.md 10 "Web profile"): the request marker file the web shell reads after the
## engine exits, and the quit sequence that makes Godot's web teardown reach `onExit`. Both run without a web build:
## the marker path and the final quit are injected.

var _marker := TestCase.test_dir("web_marker").path_join("web_request.json")
var _nodes: Array[Node] = []


func before_each() -> void:
	TestCase.remove_tree(TestCase.test_dir("web_marker"))


func after_each() -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	TestCase.remove_tree(TestCase.test_dir("web_marker"))
	WebProfile.forced = -1


func _read_marker() -> Variant:
	var f := FileAccess.open(_marker, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	return JSON.parse_string(text)


# --- marker ----------------------------------------------------------------------------------------------------------

func test_marker_contract_constants() -> void:
	# Fixed by the shell contract (docs/ARCHITECTURE.md 10.2 "Request marker"); the shell reads exactly this file.
	assert_eq(WebHandoff.MARKER_PATH, "user://web_request.json")
	assert_eq(WebHandoff.FORMAT, 1)
	assert_eq(WebHandoff.KINDS, ["reimport", "export_save", "import_save"])


func test_write_marker_for_every_kind() -> void:
	for kind: String in ["reimport", "export_save", "import_save"]:
		assert_eq(WebHandoff.write_marker(kind, _marker), OK, kind)
		var data: Variant = _read_marker()
		assert_true(data is Dictionary, "%s: marker is a JSON object" % kind)
		assert_eq(data.size(), 2, "%s: exactly format and request" % kind)
		assert_eq(data.request, kind)
		assert_eq(data.format, 1.0, "format 1")


func test_marker_text_has_integer_format() -> void:
	WebHandoff.write_marker("reimport", _marker)
	var text := FileAccess.get_file_as_string(_marker)
	assert_true(text.contains("\"format\":1") or text.contains("\"format\": 1"), "format is the integer 1: %s" % text)
	assert_false(text.contains("1.0"), "not 1.0: %s" % text)


func test_unknown_kind_writes_nothing() -> void:
	assert_ne(WebHandoff.write_marker("format_disk", _marker), OK)
	assert_false(FileAccess.file_exists(_marker), "no marker for an unknown kind")


func test_write_marker_replaces_an_older_one() -> void:
	WebHandoff.write_marker("export_save", _marker)
	WebHandoff.write_marker("reimport", _marker)
	assert_eq(_read_marker().request, "reimport")


# --- quit sequence ---------------------------------------------------------------------------------------------------

func _tree_with_players(n: int) -> Array[AudioStreamPlayer]:
	var out: Array[AudioStreamPlayer] = []
	var holder := Node.new()
	var sub := Node.new()
	holder.add_child(sub)
	var tree := Engine.get_main_loop() as SceneTree
	tree.current_scene.add_child(holder)
	_nodes.append(holder)
	for i in n:
		var p := AudioStreamPlayer.new()
		p.stream = AudioStreamWAV.new()
		# Players below the root, nested too: the Sfx autoload's players sit under an autoload, not the scene.
		(sub if i % 2 == 0 else holder).add_child(p)
		p.play()
		out.append(p)
	return out


func test_quit_to_shell_order_and_effects() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var players := _tree_with_players(3)
	var seen := {}
	var fake_quit := func() -> void:
		seen.marker = _read_marker()
		seen.paused = tree.paused
		seen.playing = players.filter(func(p: AudioStreamPlayer) -> bool: return p.playing).size()
		seen.calls = int(seen.get("calls", 0)) + 1
	var err := WebHandoff.quit_to_shell(tree, "export_save", fake_quit, _marker)
	var paused_after := tree.paused
	tree.paused = false
	assert_eq(err, OK)
	assert_eq(seen.get("calls", 0), 1, "quit called exactly once")
	assert_eq(seen.marker.request, "export_save", "marker was written and closed before the quit")
	assert_true(seen.paused, "tree paused before the quit")
	assert_true(paused_after)
	assert_eq(seen.playing, 0, "every AudioStreamPlayer stopped before the quit")


func test_hand_over_uses_the_override_instead_of_quitting() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var seen: Array[String] = []
	var override := func(kind: String) -> void: seen.append(kind)
	assert_eq(WebHandoff.hand_over(tree, WebHandoff.EXPORT_SAVE, override), OK)
	assert_eq(seen, ["export_save"], "the override got the kind")
	assert_false(FileAccess.file_exists(_marker), "no marker is written when the override handles it")
	assert_false(tree.paused, "the tree is not paused by an override")


func test_hand_over_without_an_override_is_quit_to_shell() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	assert_eq(WebHandoff.hand_over(tree, "bogus"), ERR_INVALID_PARAMETER, "unknown kind: error, nothing quit")
	assert_false(tree.paused)


func test_quit_to_shell_with_bad_kind_does_not_quit() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var calls := [0]
	var err := WebHandoff.quit_to_shell(tree, "nope", func() -> void: calls[0] += 1, _marker)
	assert_ne(err, OK)
	assert_eq(calls[0], 0, "no quit without a marker")
	assert_false(tree.paused, "tree untouched")
	assert_false(FileAccess.file_exists(_marker))


func test_quit_to_shell_save_kinds_flush_the_save() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var save_path := TestCase.test_dir("web_marker").path_join("save.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
	var save := SaveData.new(save_path)
	assert_eq(save.save_file(), OK)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	assert_false(FileAccess.file_exists(save_path))
	WebHandoff.quit_to_shell(tree, "reimport", func() -> void: pass, _marker, save)
	tree.paused = false
	assert_false(FileAccess.file_exists(save_path), "reimport does not touch the save")
	WebHandoff.quit_to_shell(tree, "export_save", func() -> void: pass, _marker, save)
	tree.paused = false
	assert_true(FileAccess.file_exists(save_path), "export_save rewrites save.json before quitting")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	WebHandoff.quit_to_shell(tree, "import_save", func() -> void: pass, _marker, save)
	tree.paused = false
	assert_true(FileAccess.file_exists(save_path), "import_save flushes too")


func test_quit_without_marker_stops_audio_and_pauses() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var players := _tree_with_players(2)
	var calls := [0]
	WebHandoff.quit(tree, func() -> void: calls[0] += 1)
	var paused := tree.paused
	tree.paused = false
	assert_eq(calls[0], 1)
	assert_true(paused)
	for p in players:
		assert_false(p.playing)


# --- web profile switch ----------------------------------------------------------------------------------------------

func test_web_profile_forced_override() -> void:
	assert_false(WebProfile.is_web(), "desktop test runs are not web")
	WebProfile.forced = 1
	assert_true(WebProfile.is_web())
	WebProfile.forced = 0
	assert_false(WebProfile.is_web())
