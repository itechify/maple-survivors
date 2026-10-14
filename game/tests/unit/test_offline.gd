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
		for token: String in NETWORK_TOKENS:
			if src.contains(token):
				fail("%s uses networking API %s" % [path, token])
		if path.get_extension() in ["cfg", "godot"]:
			for token: String in SETTING_TOKENS:
				if src.contains(token):
					fail("%s has a network setting (%s)" % [path, token])


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
