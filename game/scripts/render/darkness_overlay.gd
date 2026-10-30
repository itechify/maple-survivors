class_name DarknessOverlay
extends Node2D
## The screen of a character under Darkness 121 (#458): the view dims, except a soft lit circle round the avatar. Presentation
## only (the sim's effect is "no crits"); fed the avatar's screen position and whether the status is active each frame,
## it fades in and out and draws one gradient texture round the avatar plus four rects for the rest of the screen. Host it
## in a CanvasLayer above the world and below the HUD.

## tier C: v83 only says "dimmed screen" (the effect is client-side); radius of the fully lit circle, radius where the
## dimming is complete, and the dimming's opacity.
const LIT_RADIUS := 100.0
const DIM_RADIUS := 240.0
const DIM_ALPHA := 0.8
const DIM_COLOR := Color(0.0, 0.0, 0.04)
## tier C: how fast the dimming fades in and out, in whole-screen fractions per second.
const FADE_SPEED := 4.0
## Side of the gradient texture in pixels; it is drawn stretched over the 2 * DIM_RADIUS square.
const TEXTURE_SIZE := 128

## 0 (no dimming) to 1 (full); the overlay is hidden at 0.
var strength := 0.0
## The avatar's body centre in screen pixels.
var center := Vector2.ZERO
## Size of the screen it covers.
var view := Vector2(800, 600)

var _texture: ImageTexture


func _init() -> void:
	name = "Darkness"
	visible = false


## One frame: moves the strength toward `active` and re-aims the lit circle at `p_center` in a `p_view` sized screen.
func update(active: bool, p_center: Vector2, p_view: Vector2, delta: float) -> void:
	var target := 1.0 if active else 0.0
	var next := move_toward(strength, target, FADE_SPEED * delta)
	if next == strength and p_center == center and p_view == view:
		return
	strength = next
	center = p_center
	view = p_view
	visible = strength > 0.0
	self_modulate = Color(1, 1, 1, strength)
	queue_redraw()


## Opacity of the dimming at `distance` px from the lit circle's centre: 0 inside LIT_RADIUS, smoothly up to DIM_ALPHA at DIM_RADIUS.
static func alpha_at(distance: float) -> float:
	var t := clampf((distance - LIT_RADIUS) / (DIM_RADIUS - LIT_RADIUS), 0.0, 1.0)
	return DIM_ALPHA * t * t * (3.0 - 2.0 * t)


## The square the gradient covers, centred on `p_center` (it may reach beyond the screen).
static func lit_square(p_center: Vector2) -> Rect2:
	return Rect2(p_center - Vector2(DIM_RADIUS, DIM_RADIUS), Vector2(DIM_RADIUS, DIM_RADIUS) * 2.0)


## The flat-dimmed rects round the gradient square, clipped to the screen: together with the square they tile `p_view`.
static func flat_rects(p_view: Vector2, p_center: Vector2) -> Array[Rect2]:
	var screen := Rect2(Vector2.ZERO, p_view)
	var square := lit_square(p_center).intersection(screen)
	var out: Array[Rect2] = []
	if square.size.x <= 0.0 or square.size.y <= 0.0:
		out.append(screen)
		return out
	var parts := [
		Rect2(0, 0, p_view.x, square.position.y),
		Rect2(0, square.end.y, p_view.x, p_view.y - square.end.y),
		Rect2(0, square.position.y, square.position.x, square.size.y),
		Rect2(square.end.x, square.position.y, p_view.x - square.end.x, square.size.y)]
	for part: Rect2 in parts:
		if part.size.x > 0.0 and part.size.y > 0.0:
			out.append(part)
	return out


## The gradient image: opacity alpha_at(distance from the middle) in the dim colour, with the square's corners fully dimmed.
static func make_image() -> Image:
	var image := Image.create(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	var half := TEXTURE_SIZE * 0.5
	for y in TEXTURE_SIZE:
		for x in TEXTURE_SIZE:
			var distance := Vector2(x + 0.5 - half, y + 0.5 - half).length() / half * DIM_RADIUS
			image.set_pixel(x, y, Color(DIM_COLOR.r, DIM_COLOR.g, DIM_COLOR.b, alpha_at(distance)))
	return image


func _draw() -> void:
	if strength <= 0.0:
		return
	if _texture == null:
		_texture = ImageTexture.create_from_image(make_image())
	var flat := Color(DIM_COLOR.r, DIM_COLOR.g, DIM_COLOR.b, DIM_ALPHA)
	for rect in flat_rects(view, center):
		draw_rect(rect, flat)
	var square := lit_square(center)
	if square.intersects(Rect2(Vector2.ZERO, view)):
		draw_texture_rect(_texture, square, false)
