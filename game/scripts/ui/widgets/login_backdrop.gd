class_name LoginBackdrop
extends Node2D
## The v83 login scene as a menu backdrop: UI.wz/MapLogin.img drawn by MapRenderer (it is map-structured: backs from
## Map.wz/Back/login.img, layer objs from Map.wz/Obj/login.img, BGM BgmUI/Title), seen through the classic book frame
## UI.wz/Login.img/Common/frame (800x600, centred; the rest of a wider view is black, like the 800x600 client).
##
## Sections of the login map (camera centres, measured from the map's backs and objs): the title with the logo at
## (28, -11) (TITLE), the world select at (0, -600) (WORLD_SELECT), the character select at (28, -1208) (CHAR_SELECT).
## The camera is not clamped: MapBounds of this map (its miniMap rect) would push the title section off-centre.
##
## The title logo (Obj login.img/Title/logo/0) fades in over its first frame (8 s, a0 0 -> 255); its second frame has
## a0 255 and no a1, which our tier-C alpha rule turns into a fade-out, so the looped animation would blink the logo
## every 8.1 s. `pin_logo()` holds it at full alpha once the fade-in has played (the v83 title keeps it shown).

const MAP_IMG := "UI.wz/MapLogin.img"
const FRAME := "UI.wz/Login.img/Common/frame"
const BGM := "Sound.wz/BgmUI.img/Title"
const BGM_SELECT := "Sound.wz/BgmUI.img/WCSelect"
const TITLE := Vector2(28, -11) # tier A: original tree/mushrooms register exactly to title_1.png; private spec32/v83-login-refs (localized v62).
const WORLD_SELECT := Vector2(0, -600) # tier C: MapLogin section inference; same layout.md, World/channel.
## tier A: original signboard/bridge/house register to charselect_1.png at this camera; private spec32/v83-login-refs/wz-layout-notes.md.
const CHAR_SELECT := Vector2(28, -1208)
## tier B: mushroom cap / branch registration to period newchar_1.png; private spec32/v83-login-refs, not stored camera data.
const NEW_CHAR := Vector2(37, -3007)
const LOGO := "Title/logo"

## The map renderer (null until _ready).
var map: MapRenderer
var camera: Camera2D
## The frame overlay layer (draws Common/frame and the side bars).
var overlay: CanvasLayer
## Camera centre in login-map pixels.
var center := TITLE:
	set(v):
		center = v
		if camera != null:
			camera.position = v
## BGM played on _ready ("" = leave the music alone): BgmUI/Title on the title, BgmUI/WCSelect on the selects.
var bgm := BGM
## Hold the logo once it has faded in (see the class doc).
var hold_logo := true
## Draw the book frame and black side bars.
var show_frame := true

var _logo_runs: Array[MapDrawList] = []
var _frame_node: Node2D


func _init(p_center: Vector2 = TITLE) -> void:
	center = p_center


func _ready() -> void:
	map = MapRenderer.new()
	map.name = "LoginMap"
	map.show_portals = false
	add_child(map)
	if not map.load_map_path(MAP_IMG):
		push_warning("LoginBackdrop: %s is not in the asset cache" % MAP_IMG)
	camera = Camera2D.new()
	camera.name = "Camera"
	camera.position = center
	add_child(camera)
	camera.make_current()
	map.camera = camera
	_logo_runs = find_runs(LOGO)
	if show_frame:
		overlay = CanvasLayer.new()
		overlay.name = "FrameLayer"
		overlay.layer = 1
		add_child(overlay)
		_frame_node = Node2D.new()
		overlay.add_child(_frame_node)
		_frame_node.draw.connect(_draw_frame)
		get_viewport().size_changed.connect(_frame_node.queue_redraw)
	if bgm != "":
		var sfx := get_node_or_null("/root/Sfx") as AudioService
		if sfx != null:
			sfx.play_bgm(bgm)


func _process(_delta: float) -> void:
	if hold_logo:
		pin_logo()


## Holds the logo's animation at full alpha after its fade-in.
func pin_logo() -> void:
	for r in _logo_runs:
		if r.items.is_empty():
			continue
		var a: SpriteAnim = r.items[0].anim
		if a.frame_count() >= 2 and r.time >= a.frames[1].start:
			r.time = a.frames[1].start
			r.animated = false
			r.items[0] = {"anim": _single(a.frames[1]), "pos": r.items[0].pos, "flip": r.items[0].flip}
			r.queue_redraw()


## Map draw runs whose sprite path contains `part` (e.g. "Title/signboard").
func find_runs(part: String) -> Array[MapDrawList]:
	var out: Array[MapDrawList] = []
	if map == null:
		return out
	for layer in map.get_children():
		for n in layer.get_children():
			if n is MapDrawList:
				for it: Dictionary in (n as MapDrawList).items:
					var a: SpriteAnim = it.anim
					if a != null and part in a.path:
						out.append(n)
						break
	return out


## Hides the map sprites whose path contains `part` (only those: a static run may hold several sprites).
func hide_objs(part: String) -> void:
	for r in find_runs(part):
		var keep: Array = []
		for it: Dictionary in r.items:
			var a: SpriteAnim = it.anim
			if a == null or not (part in a.path):
				keep.append(it)
		r.items = keep
		r.visible = not keep.is_empty()
		r.queue_redraw()


## Top-left of the 800x600 book frame in view coordinates.
func frame_origin() -> Vector2:
	var view := get_viewport_rect().size
	return ((view - Vector2(GameSettings.BASE_VIEW)) * 0.5).floor()


func _draw_frame() -> void:
	var view := _frame_node.get_viewport_rect().size
	var o := frame_origin()
	var black := Color(0, 0, 0)
	if o.x > 0.0:
		_frame_node.draw_rect(Rect2(0, 0, o.x, view.y), black)
		_frame_node.draw_rect(Rect2(o.x + 800.0, 0, view.x - o.x - 800.0, view.y), black)
	if o.y > 0.0:
		_frame_node.draw_rect(Rect2(0, 0, view.x, o.y), black)
		_frame_node.draw_rect(Rect2(0, o.y + 600.0, view.x, view.y - o.y - 600.0), black)
	var f := UiArt.frame(FRAME)
	if f != null:
		UiArt.blit(_frame_node, f, o)


static func _single(f: SpriteFrame) -> SpriteAnim:
	var s := SpriteAnim.new()
	s.frames.append(f)
	s.total = f.delay_s
	return s
