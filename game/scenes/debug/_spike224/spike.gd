extends Node
## Spike #224: --mode=vp|ci  --out=<dir>  [--fill] [--aa]
var _n := 0
var _args := {}
var _node: Node2D

const GOLD := ["Hello, MapleStory!", "MP 12/25  HP 37/50", "Lv. 38 Fire/Poison Wizard", "+1,234 EXP", "Iiiil|llWWMMmm 0123456789",
	"A long tooltip sentence that has to wrap across lines in the item window.", "Req LEV : 30   STR 25 DEX 25"]

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		_args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var r := get_tree().root
	var scr := DisplayServer.get_primary_screen()
	print("screens ", DisplayServer.get_screen_count(), " primary ", scr, " ", DisplayServer.screen_get_usable_rect(scr))
	DisplayServer.window_set_size(Vector2i(int(_args.get("w", "1600")), int(_args.get("h", "1200"))))
	DisplayServer.window_set_position(DisplayServer.screen_get_usable_rect(scr).position + Vector2i(20, 30))
	if _args.get("mode", "vp") == "ci":
		r.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	if _args.has("fill"):
		r.content_scale_size = Vector2i(int(_args.get("w", "1600")) / 2, int(_args.get("h", "1200")) / 2)
	_node = Node2D.new()
	_node.set_script(load(_args.get("draw", "")))
	add_child(_node)

func _process(_d: float) -> void:
	_n += 1
	if _n == 30:
		set_process(false)
		await RenderingServer.frame_post_draw
		var dir := String(_args.get("out"))
		var tag := String(_args.get("mode")) + ("_fill" if _args.has("fill") else "")
		get_tree().root.get_texture().get_image().save_png(dir.path_join(tag + "_vp.png"))
		var wpos := DisplayServer.window_get_position(); var ws := DisplayServer.window_get_size()
		DisplayServer.screen_get_image_rect(Rect2i(wpos, ws)).save_png(dir.path_join(tag + "_win.png"))
		var lines := PackedStringArray()
		lines.append("oversampling=%s scale=%s size=%s visible=%s" % [get_tree().root.oversampling, get_tree().root.get_final_transform(), get_tree().root.size, get_tree().root.get_visible_rect().size])
		for s in GOLD:
			for sz in [12, 11]:
				for b in [false, true]:
					lines.append("%s|%d|%s|%s" % [s, sz, b, MapleText.width(s, sz, b)])
		lines.append("wrap=" + ",".join(MapleText.wrap(GOLD[5], 120)))
		lines.append("asc=%s %s" % [MapleText.ascent(12), MapleText.ascent(11)])
		FileAccess.open(dir.path_join(tag + "_metrics.txt"), FileAccess.WRITE).store_string("\n".join(lines))
		print("\n".join(lines))
		get_tree().quit()

