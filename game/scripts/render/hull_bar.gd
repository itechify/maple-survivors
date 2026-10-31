class_name HullBar
extends Node2D
## A thin blue bar over the character showing the ship's remaining hull (`hull_hp / hull_max`, spec #384 C11). Hidden while
## no hull runs. Presentation only: RunScene feeds it the fraction PlayerForms.hull_fraction() returns each frame; it redraws
## only when the drawn width changes.

## tier C: the bar's size in pixels and colours (a blue twin of the monsters' thin HP bars).
const WIDTH := 40.0
const HEIGHT := 5.0
const BACK := Color(0.05, 0.08, 0.16, 0.85)
const FILL := Color(0.25, 0.55, 1.0)
const EDGE := Color(0.75, 0.88, 1.0, 0.9)

var _fraction := -1.0


## Moves the bar to `at` (the point above the character's head, bar centre) and shows `fraction` (0..1; negative hides it).
func update(at: Vector2, fraction: float) -> void:
	position = at.round()
	var shown := fraction >= 0.0
	if visible != shown:
		visible = shown
	var width := roundf(clampf(fraction, 0.0, 1.0) * (WIDTH - 2.0))
	if width != roundf(clampf(_fraction, 0.0, 1.0) * (WIDTH - 2.0)) or (_fraction < 0.0) != (fraction < 0.0):
		_fraction = fraction
		queue_redraw()
	else:
		_fraction = fraction


func _draw() -> void:
	if _fraction < 0.0:
		return
	draw_rect(Rect2(-WIDTH * 0.5, 0.0, WIDTH, HEIGHT), BACK)
	draw_rect(Rect2(-WIDTH * 0.5 + 1.0, 1.0, roundf(clampf(_fraction, 0.0, 1.0) * (WIDTH - 2.0)), HEIGHT - 2.0), FILL)
	draw_rect(Rect2(-WIDTH * 0.5, 0.0, WIDTH, HEIGHT), EDGE, false)
