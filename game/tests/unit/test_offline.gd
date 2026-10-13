extends TestCase
## The game must run fully offline (docs/ARCHITECTURE.md section 7): no script may use a networking API.

const NETWORK_TOKENS := [
	"HTTPRequest", "HTTPClient", "StreamPeerTCP", "StreamPeerTLS", "TCPServer", "PacketPeerUDP", "UDPServer",
	"WebSocketPeer", "WebSocketMultiplayerPeer", "ENetConnection", "ENetMultiplayerPeer", "MultiplayerAPI",
	"WebRTCPeerConnection", "PacketPeerDTLS", "DTLSServer", "IP.resolve_hostname", "OS.shell_open",
]
## Files allowed to mention the tokens (this test itself).
const ALLOWED := ["res://tests/unit/test_offline.gd"]


func test_no_script_uses_networking() -> void:
	var files := _scripts("res://")
	assert_true(files.size() > 0, "found no scripts to scan")
	for path in files:
		if path in ALLOWED:
			continue
		var src := FileAccess.get_file_as_string(path)
		for token in NETWORK_TOKENS:
			if src.contains(token):
				fail("%s uses networking API %s" % [path, token])


func _scripts(dir_path: String) -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.get_extension() == "gd":
			out.append(dir_path.path_join(f))
	for d in dir.get_directories():
		if d.begins_with("."):
			continue
		out.append_array(_scripts(dir_path.path_join(d)))
	return out
