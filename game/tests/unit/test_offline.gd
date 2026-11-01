extends TestCase
## The game must run fully offline (docs/ARCHITECTURE.md section 7): no script may use a networking API, and no scene,
## resource, config or project setting may contain a networking node, class or setting.

const NETWORK_TOKENS := [
	"HTTPRequest", "HTTPClient", "StreamPeerTCP", "StreamPeerTLS", "TCPServer", "PacketPeerUDP", "UDPServer",
	"WebSocketPeer", "WebSocketMultiplayerPeer", "ENetConnection", "ENetMultiplayerPeer", "MultiplayerAPI",
	"MultiplayerPeer", "MultiplayerSpawner", "MultiplayerSynchronizer", "SceneMultiplayer", "WebRTCPeerConnection",
	"WebRTCMultiplayerPeer", "PacketPeerDTLS", "DTLSServer", "IP.resolve_hostname", "OS.shell_open", "JavaScriptBridge",
]
## Tokens that only matter in project settings / configs (e.g. a [network] section or remote-debug settings).
const SETTING_TOKENS := ["[network]", "network/"]
## File types scanned: scripts, scenes, resources, configs (export presets) and the project file.
const EXTENSIONS := ["gd", "tscn", "tres", "cfg", "godot"]
## Files allowed to mention the tokens (this test itself).
const ALLOWED := ["res://tests/unit/test_offline.gd"]
## Exact local subprocess sites only. Additional calls in these files still fail the scan.
const PROCESS_TOKENS := ["OS.execute", "OS.create_process", "OS.create_instance"]
const IMPORTER_CALL := "var info := OS.execute_with_pipe(exe, args, false)"
const SELF_TEST_CALL := "var status := OS.execute(OS.get_executable_path(), [\"--headless\", \"--path\","

const SELF_TEST_FILES := [
	"res://tests/unit/test_account_flag.gd", "res://tests/unit/test_balance_chain.gd",
	"res://tests/unit/test_character_snapshot.gd", "res://tests/unit/test_character_tools.gd",
	"res://tests/unit/test_hero_selection.gd",
	"res://tests/unit/test_corsair_selection.gd",
	"res://tests/unit/test_dark_knight_selection.gd",
	"res://tests/unit/test_bowmaster_selection.gd",
	"res://tests/unit/test_marksman_selection.gd",
	"res://tests/unit/test_warrior2_fixtures.gd",
	"res://tests/unit/test_il_selection.gd", "res://tests/unit/test_buccaneer_selection.gd",
	"res://tests/unit/test_paladin_selection.gd",
	"res://tests/unit/test_bishop_selection.gd", "res://tests/unit/test_night_lord_selection.gd",
]


func test_no_file_uses_networking() -> void:
	var files := _files("res://")
	var kinds := {}
	for path in files:
		kinds[path.get_extension()] = int(kinds.get(path.get_extension(), 0)) + 1
	assert_true(int(kinds.get("gd", 0)) > 0, "found no scripts to scan (%s)" % [kinds])
	assert_true(int(kinds.get("tscn", 0)) > 0, "found no scenes to scan (%s)" % [kinds])
	assert_true("res://project.godot" in files, "project.godot is scanned")
	for path in files:
		if path in ALLOWED:
			continue
		var src := FileAccess.get_file_as_string(path)
		for line: String in _process_violations(path, src):
			fail("%s uses an unapproved subprocess API: %s" % [path, line])
		for token: String in NETWORK_TOKENS:
			if src.contains(token):
				fail("%s uses networking API %s" % [path, token])
		if path.get_extension() in ["cfg", "godot"]:
			for token: String in SETTING_TOKENS:
				if src.contains(token):
					fail("%s has a network setting (%s)" % [path, token])


func test_subprocess_scan_rejects_planted_calls() -> void:
	for call: String in ["OS.execute(\"curl\", [])", "OS.execute_with_pipe(\"curl\", [])",
			"OS.create_process(\"curl\", [])", "OS.create_instance([])"]:
		assert_eq(_process_violations("res://scripts/planted.gd", call).size(), 1, call)
		assert_eq(_process_violations("res://scenes/ui/import_screen.gd", call).size(), 1, call)
	assert_eq(_process_violations("res://scenes/ui/import_screen.gd", IMPORTER_CALL).size(), 0)
	assert_eq(_process_violations("res://scripts/planted.gd", IMPORTER_CALL).size(), 1)
	assert_eq(_process_violations(SELF_TEST_FILES[0], SELF_TEST_CALL).size(), 0)
	assert_eq(_process_violations(SELF_TEST_FILES[0], "OS.execute(\"curl\", [])").size(), 1)


func _process_violations(path: String, src: String) -> PackedStringArray:
	var bad: PackedStringArray = []
	for raw: String in src.split("\n"):
		var line := raw.strip_edges()
		if line.begins_with("#"):
			continue
		if path == "res://scenes/ui/import_screen.gd" and line == IMPORTER_CALL:
			continue
		if path in SELF_TEST_FILES and line == SELF_TEST_CALL:
			continue
		for token: String in PROCESS_TOKENS:
			if line.contains(token):
				bad.append(line)
				break
	return bad


func _files(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() in EXTENSIONS:
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		if d.begins_with(".") or d == "export":
			continue
		out.append_array(_files(dir_path.path_join(d)))
	return out
