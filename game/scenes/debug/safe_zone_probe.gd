extends Node2D
## Debug probe for the safe zone's look (spec #425 SH4): a synthetic arrangement (a floor, the character as a disc, three
## monsters as discs) with a SafeZoneView cloud over it, drawn from synthetic smoke puffs (a looping 8-frame animation), its
## outline, and a "Guard" word over the character. Evidence only; no WZ art. The real Smokescreen nodes are confirmed by SH12.
##   bash scripts/godot.sh --path game res://scenes/debug/safe_zone_probe.tscn -- --shots=C:/abs/dir
const FLOOR_Y := 420.0
const PLAYER := Vector2(400, 420)
const MOBS := [Vector2(270, 420), Vector2(560, 420), Vector2(640, 420)]
## The Smokescreen box at rank 4 (+-150 x +-113) centred on the character's body (30 px above the feet).
const ZONE := Rect2(250, 277, 300, 226)

var _view: SafeZoneView


## A soft grey puff of `radius` px, a different lobe pattern per frame, as one frame of a tile animation (origin: bottom centre).
func _puff(frame: int) -> SpriteFrame:
	var size := 110
	var img := Image.create_empty(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := 0.0
			for lobe in 4:
				var angle := float(lobe) * 1.57 + float(frame) * 0.3
				var centre := Vector2(size * 0.5, size * 0.58) + Vector2(cos(angle), sin(angle)) * 16.0
				d = maxf(d, 1.0 - Vector2(x, y).distance_to(centre) / 30.0)
			if d > 0.0:
				img.set_pixel(x, y, Color(0.82, 0.84, 0.9, clampf(d * 0.75, 0.0, 0.7)))
	var f := SpriteFrame.new()
	f.page = ImageTexture.create_from_image(img)
	f.region = Rect2(0, 0, size, size)
	f.origin = Vector2(size * 0.5, size - 8.0)
	f.delay_s = 0.12
	f.start = frame * 0.12
	return f


func _anim() -> SpriteAnim:
	var anim := SpriteAnim.new()
	for i in 8:
		anim.frames.append(_puff(i))
	anim.total = 8 * 0.12
	return anim


func _draw() -> void:
	draw_rect(Rect2(0, 0, 800, 600), Color(0.16, 0.2, 0.3))
	draw_rect(Rect2(0, FLOOR_Y, 800, 180), Color(0.32, 0.26, 0.2))
	draw_circle(PLAYER + Vector2(0, -29), 22.0, Color(0.3, 0.8, 0.4))
	for mob: Vector2 in MOBS:
		draw_circle(mob + Vector2(0, -20), 20.0, Color(0.85, 0.35, 0.3))


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var shots := String(args.get("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(shots)
	queue_redraw()
	_view = SafeZoneView.new()
	add_child(_view)
	_view.attach_labels(self)
	_view.begin("probe_cloud", ZONE, 6.0, FLOOR_Y, _anim())
	for i in 30:
		_view.advance(1.0 / 60.0) # the cloud has faded in
	_view.guard(PLAYER + Vector2(0, -78))
	_view.advance(0.25)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join("safe_zone.png"))
	print("zones: %d puffs: %d guard words: %d" % [_view.zone_count(), _view.puff_count(), _view.guard_count()])
	get_tree().quit()
