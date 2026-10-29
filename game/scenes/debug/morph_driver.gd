extends Node2D
## Debug contact sheets of a Morph.wz figure in a list of stances (the morph stance rule, #415 of spec #412), for evidence
## screenshots. Tool-only; needs a cache whose manifest has the morph (Morph.wz/1000.img and 1001.img: asset_manifest.d/
## buccaneer.json; 1002 is the Oak Barrel in pirate.json).
##
##   MAPLE_SURVIVORS_CACHE=<cache> ISOLATE=<name> bash scripts/run.sh res://scenes/debug/morph_driver.tscn -- \
##       --shots=<abs evidence dir> [--morph=1001,1000,1002] [--stances=eburster,fist,...] [--cols=8]
##
## One PNG per morph and page (<id>_<page>.png): a row per stance, the stance's frames left to right (at most --cols,
## evenly spaced when it has more), each cell facing left with a hairline on the character origin (the feet) and the
## frame index, and the stance the avatar actually played (a stance the morph lacks shows its fallback). summary.json holds
## each stance's frame count and seconds and every missing asset (should be []).

## The stances asked for by default: every action a Buccaneer skill names, then the basics and two fallbacks.
const STANCES := ["eburster", "eorb", "edrain", "fist", "dragonstrike", "shockwave", "demolition", "snatch", "straight",
	"somersault", "backspin", "doubleupper", "screw", "stand1", "walk1", "jump", "prone", "ladder", "rope", "alert",
	"swingO1"]
const MORPHS := [1001, 1000, 1002]
const COLS := 8
const ROWS_PER_PAGE := 7
## Unscaled sheet units: one cell, and the feet inside it (Buccaneer figures reach about 120 px above the origin).
const CELL := Vector2(170.0, 150.0)
const FEET := Vector2(90.0, 128.0)
const SCALE := 1.0
const HAIRLINE := Color(1.0, 1.0, 0.2, 0.9)

var _shots_dir := ""
var _lib: AssetLibrary


func _ready() -> void:
	var args := _args()
	_shots_dir = String(args.get("shots", ""))
	if _shots_dir.is_empty():
		push_error("morph_driver requires --shots=<absolute evidence directory>")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	_lib = AssetLibrary.get_default()
	var stances: Array = STANCES
	if args.has("stances"):
		stances = Array(String(args.stances).split(","))
	var morphs: Array = MORPHS
	if args.has("morph"):
		morphs = Array(String(args.morph).split(",")).map(func(s: String) -> int: return int(s))
	var cols := maxi(2, int(args.get("cols", COLS)))
	var summary := {"morphs": {}, "missing": []}
	for id: int in morphs:
		var rows := {}
		var page := 0
		for start in range(0, stances.size(), ROWS_PER_PAGE):
			var chunk: Array = stances.slice(start, start + ROWS_PER_PAGE)
			var missing: PackedStringArray = await _sheet(id, chunk, cols, page, rows)
			for m in missing:
				if not (m in summary.missing):
					summary.missing.append(m)
			page += 1
		summary.morphs[str(id)] = rows
	var file := FileAccess.open(_shots_dir.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	file.close()
	print("morph_driver: missing=%s" % [summary.missing])
	get_tree().quit()


## Draws one page (a row per stance in `chunk`) into <id>_<page>.png and records each stance in `rows`; returns every
## asset the avatars could not find.
func _sheet(id: int, chunk: Array, cols: int, page: int, rows: Dictionary) -> PackedStringArray:
	var size := Vector2(CELL.x * cols, CELL.y * chunk.size()) * SCALE
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
	var missing := PackedStringArray()
	for r in chunk.size():
		var want := String(chunk[r])
		var probe := _avatar(root, id, Vector2.ZERO)
		probe.play(want, true, false)
		var played := probe.stance
		var delays := probe.stance_delays(played)
		var seconds := probe.stance_duration(played)
		missing.append_array(probe.missing)
		probe.queue_free()
		rows[want] = {"played": played, "frames": delays.size(), "seconds": snappedf(seconds, 0.001)}
		var shown := _frames_shown(delays.size(), cols)
		for c in shown.size():
			var cell := Vector2(CELL.x * c, CELL.y * r)
			var line := ColorRect.new()
			line.color = HAIRLINE
			line.position = (cell + Vector2(0.0, FEET.y)) * SCALE
			line.size = Vector2(CELL.x * SCALE, 1.0)
			root.add_child(line)
			var a := _avatar(root, id, (cell + FEET) * SCALE)
			a.play(want, true, false)
			var t := 0.001
			for k in int(shown[c]):
				t += delays[k]
			a.advance(t)
			missing.append_array(a.missing)
			_label(root, cell * SCALE + Vector2(2.0, 2.0), "%s%s %d/%d" % [want, "" if played == want else " -> " + played,
				int(shown[c]) + 1, delays.size()])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(_shots_dir.path_join("%d_%d.png" % [id, page]))
	viewport.queue_free()
	await get_tree().process_frame
	return missing


## The frame indices drawn for a stance with `n` frames in at most `cols` cells: all of them, else evenly spaced.
static func _frames_shown(n: int, cols: int) -> Array:
	var out: Array = []
	if n <= cols:
		for i in maxi(n, 1):
			out.append(i)
		return out
	for i in cols:
		out.append(roundi(float(i) * float(n - 1) / float(cols - 1)))
	return out


func _avatar(parent: Node2D, id: int, at: Vector2) -> AvatarRenderer:
	var a := AvatarRenderer.new()
	a.library = _lib
	a.position = at
	parent.add_child(a)
	a.set_look(AvatarRenderer.DEFAULT_LOOK)
	a.set_facing(-1)
	a.set_morph(id)
	return a


func _label(parent: Node, at: Vector2, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = at
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
