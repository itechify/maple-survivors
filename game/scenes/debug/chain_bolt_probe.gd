extends Node2D
## Debug probe for the chain cast rule's bolt art (spec #319 I4): a synthetic arrangement (a caster and five monsters as
## discs, a bolt through four of them) drawn by ChainBoltRenderer with synthetic ball strips, three variants. Evidence
## only. `--real` draws Chain Lightning's own ball art (`chain.ball` of the definition, from the asset cache) instead.
##   bash scripts/godot.sh --path game res://scenes/debug/chain_bolt_probe.tscn -- --shots=C:/abs/dir [--real]
const POINTS := [Vector2(110, 300), Vector2(260, 260), Vector2(380, 330), Vector2(540, 250), Vector2(690, 330)]
const BYSTANDER := Vector2(420, 180)
const COLORS := [Color(0.6, 0.85, 1.0), Color(1.0, 0.95, 0.5), Color(0.85, 0.7, 1.0)]

var _bolts: ChainBoltRenderer


## A 64x20 strip of a jagged bolt in `color`, bright core and soft edge, as one frame of a ball animation.
func _strip(color: Color, frame: int) -> SpriteAnim:
	var img := Image.create_empty(64, 20, false, Image.FORMAT_RGBA8)
	for x in 64:
		var y := 10 + int(round(sin(x * 0.45 + frame * 1.7) * 4.0))
		for dy in range(-3, 4):
			var a := clampf(1.0 - absf(dy) / 3.5, 0.0, 1.0)
			img.set_pixel(x, clampi(y + dy, 0, 19), Color(color.r, color.g, color.b, a))
		img.set_pixel(x, clampi(y, 0, 19), Color.WHITE)
	var f := SpriteFrame.new()
	f.page = ImageTexture.create_from_image(img)
	f.region = Rect2(0, 0, 64, 20)
	f.delay_s = 0.1
	var anim := SpriteAnim.new()
	anim.frames.append(f)
	return anim


func _variant(color: Color) -> SpriteAnim:
	var anim := SpriteAnim.new()
	for i in 5:
		var one := _strip(color, i)
		one.frames[0].start = i * 0.1
		anim.frames.append(one.frames[0])
	anim.total = 0.5
	return anim


func _draw() -> void:
	draw_circle(POINTS[0], 14.0, Color(0.3, 0.9, 0.4))
	for i in range(1, POINTS.size()):
		draw_circle(POINTS[i], 18.0, Color(0.9, 0.35, 0.3))
	draw_circle(BYSTANDER, 18.0, Color(0.5, 0.5, 0.5))


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.12, 0.14, 0.2))
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var shots := String(args.get("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(shots)
	queue_redraw()
	_bolts = ChainBoltRenderer.new()
	add_child(_bolts)
	var anims: Array = []
	if args.has("real"):
		var library := AssetLibrary.get_default()
		for path: String in DataRepo.load_all().skills.skills.chain_lightning.chain.ball:
			anims.append(library.anim(path))
	else:
		for color: Color in COLORS:
			anims.append(_variant(color))
	_bolts.play(PackedVector2Array(POINTS), anims)
	_bolts.advance(0.12)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(shots.path_join("chain_bolt.png"))
	print("segments drawn: ", _bolts.active_count())
	get_tree().quit()
