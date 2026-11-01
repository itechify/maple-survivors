extends Node2D
## Debug contact sheet of a mount under the avatar (spec #384 C12 #396), for evidence screenshots. Tool-only.
##
##   bash scripts/godot.sh --path game res://scenes/debug/mount_gallery.tscn -- --shots=C:/abs/dir [--mount=1932000] [--weapon=1492000]
##       [--requests=cannon,torpedo] [--scale=3]
##
## One PNG (mount_<id>.png): a column per avatar stance request (what RunScene asks of AvatarRenderer: standing, walking,
## jumping, prone, the idle alert, an attack action, the four named casts and climbing), each shown facing left (the WZ
## default) and right, the rider with a pistol on the mount, a ground line at the feet. Every cell is frozen
## `CAST_AT` of the way through its mount stance. Labels name the request, the mount stance it chose and the rider's. Prints
## every missing asset. Needs an asset cache holding the mount (the ship is in asset_manifest.d/corsair.json).

## The avatar stance requests, in column order.
const ALL_REQUESTS := ["stand1", "walk1", "jump", "prone", "alert", "shoot1", "cannon", "torpedo", "fireburner", "coolingeffect",
	"ladder"]
const OUTFIT := [1040002, 1060002, 1072001]
## Unscaled sheet units: a cell, and the feet position inside it.
const CELL := Vector2(170.0, 190.0)
const FEET := Vector2(85.0, 150.0)
## How far into its stance a cell is frozen.
const CAST_AT := 0.45

var _lib: AssetLibrary
var _requests: Array = ALL_REQUESTS
var _scale := 1.6


func _ready() -> void:
	var args := _args()
	var shots := String(args.get("shots", OS.get_user_data_dir().path_join("_test_cache")))
	DirAccess.make_dir_recursive_absolute(shots)
	_lib = AssetLibrary.get_default()
	_scale = float(args.get("scale", 1.6))
	if args.has("requests"):
		_requests = Array(String(args.requests).split(","))
	var mount := int(args.get("mount", 1932000))
	await _sheet(mount, int(args.get("weapon", 1492000)), shots.path_join("mount_%d.png" % mount))
	get_tree().quit()


func _sheet(mount: int, weapon: int, file: String) -> void:
	var art := MountArt.load_mount(_lib, mount)
	print("mount_gallery: mount %d stances=%s" % [mount, art.stance_names()])
	var size := Vector2(CELL.x * _requests.size(), CELL.y * 2.0) * _scale
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var root := Node2D.new()
	viewport.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.45, 0.55)
	bg.size = size
	root.add_child(bg)
	var content := Node2D.new()
	content.scale = Vector2(_scale, _scale)
	root.add_child(content)
	var look := {"skin": 0, "face": 20000, "hair": 30030, "equips": OUTFIT + [weapon]}
	var missing := PackedStringArray()
	for row in 2:
		for col in _requests.size():
			var request: String = _requests[col]
			var origin := Vector2(CELL.x * col, CELL.y * row) + FEET
			var line := ColorRect.new()
			line.color = Color(0.1, 0.1, 0.1)
			line.position = origin + Vector2(-70, 0)
			line.size = Vector2(140, 1)
			content.add_child(line)
			var a := AvatarRenderer.new()
			a.library = _lib
			a.position = origin
			content.add_child(a)
			a.set_look(look)
			a.set_mount(mount)
			a.set_facing(1 if row == 1 else -1)
			a.play(request, true, false)
			var layers := a.mount_layers()
			var ship := layers.stance if layers != null else ""
			if layers != null and ship != "":
				a.advance(art.duration(ship) * CAST_AT if request in MountLayers.CAST_STANCES else 0.25)
			_label(root, Vector2(CELL.x * col + 2.0, CELL.y * row + 2.0), "%s -> %s / %s" % [request,
				ship if ship != "" else "hidden", a.stance])
			print("mount_gallery: %s facing %s ship=%s rider=%s frame=%d" % [request, "R" if row == 1 else "L", ship, a.stance,
				a.mount_layers().index_of_frame() if layers != null else -1])
			missing.append_array(a.missing)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(file)
	print("mount_gallery: wrote %s missing=%s" % [file, missing])
	viewport.queue_free()


func _label(parent: Node, at: Vector2, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = at * _scale
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	parent.add_child(label)


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
