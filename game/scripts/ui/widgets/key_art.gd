class_name KeyArt
extends TextureRect
## The Maple Survivors key art (game/assets/branding/title.png, the logo baked in; also the boot splash) scaled to
## cover a view, centred. Used by the title and import screens.
##
## The project filters canvas textures with nearest and *.import settings are not committed, so a plain downscale of
## the 1672x941 source would shimmer. `fit(view)` places the rect and, after a short delay (the old texture is
## stretched meanwhile, so dragging a window edge does not resample every frame), swaps in a copy resized to the exact
## on-screen size with Lanczos, drawn 1:1. When the renderer cannot read the texture back (headless) the source
## texture is stretched instead.

const PATH := "res://assets/branding/title.png"
## Source art size.
const SIZE := Vector2(1672, 941)
## Seconds a resized view waits before the sharp copy is rebuilt.
const RESCALE_DELAY := 0.12

var _source: Image
var _scaled_size := Vector2i.ZERO
var _timer: Timer


func _init() -> void:
	name = "KeyArt"
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tex := load(PATH) as Texture2D
	if tex == null:
		push_warning("KeyArt: %s is missing" % PATH)
		return
	texture = tex
	_source = tex.get_image()
	if _source != null and _source.is_empty():
		_source = null
	if _source != null and _source.is_compressed():
		_source.decompress()


func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.wait_time = RESCALE_DELAY
	_timer.timeout.connect(sharpen)
	add_child(_timer)


## The art's rect in a view of size `view`: scaled to cover it, centred.
static func cover_rect(view: Vector2) -> Rect2:
	var s := maxf(view.x / SIZE.x, view.y / SIZE.y)
	var sz := (SIZE * s).ceil()
	return Rect2(((view - sz) * 0.5).floor(), sz)


## Covers a view of size `view`; `now` rebuilds the sharp copy at once instead of after RESCALE_DELAY.
func fit(view: Vector2, now := false) -> void:
	var r := cover_rect(view)
	position = r.position
	size = r.size
	if now or _timer == null:
		sharpen()
	else:
		_timer.start()


## Maps a point of the source art to this rect's parent coordinates.
func art_to_view(p: Vector2) -> Vector2:
	return position + p * size / SIZE


## Replaces the texture with a copy resized to the on-screen size (drawn 1:1).
func sharpen() -> void:
	var target := Vector2i(size)
	if _source == null or target == _scaled_size or target.x <= 0 or target.y <= 0:
		return
	var img := _source.duplicate() as Image
	img.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	texture = ImageTexture.create_from_image(img)
	_scaled_size = target
