class_name ParchmentScroll
extends Control
## The v83 world-select scroll (UI.wz/Login.img/WorldSelect/scroll): `0` unrolls it (513x152 rolled -> 513x401 open,
## 250/50/50 ms), `1` rolls it up again. The open parchment's writable area is PARCHMENT (scroll-local px, measured
## from the canvas). Content is drawn by the owner from the `draw_content` signal (only while fully open), and child
## controls added under `content` are shown only while open.
##
##   var s := ParchmentScroll.new()
##   s.draw_content.connect(func(ci: Control) -> void: MapleText.draw(ci, s.PARCHMENT.position, "Hello"))
##   s.unroll()

## Emitted while drawing the open scroll: draw into `ci` (scroll-local coordinates).
signal draw_content(ci: Control)
## Emitted when the unroll (or roll-up) animation has finished.
signal opened()
signal closed()

const UNROLL := "UI.wz/Login.img/WorldSelect/scroll/0"
const ROLL_UP := "UI.wz/Login.img/WorldSelect/scroll/1"
const SIZE := Vector2(513, 416)
## Writable parchment area of the open scroll.
const PARCHMENT := Rect2(40, 148, 432, 238)
const SOUND := "Sound.wz/UI.img/RollDown"

## Container for controls shown on the open parchment.
var content: Control

var _anim: SpriteAnim
var _t := 0.0
var _state := "rolled"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	custom_minimum_size = SIZE
	size = SIZE
	content = Control.new()
	content.name = "Content"
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.size = SIZE
	content.visible = false
	add_child(content)


## Plays the unroll animation (instantly open with `instant`).
func unroll(instant: bool = false) -> void:
	_anim = UiArt.anim(UNROLL)
	_t = 0.0
	_state = "unrolling"
	UiArt.play_sound(SOUND)
	if instant or _anim == null or _anim.is_empty():
		_finish_open()
	queue_redraw()


## Plays the roll-up animation, then emits `closed`.
func roll_up() -> void:
	_anim = UiArt.anim(ROLL_UP)
	_t = 0.0
	_state = "rolling"
	content.visible = false
	if _anim == null or _anim.is_empty():
		_state = "rolled"
		closed.emit()
	queue_redraw()


## True when fully open.
func is_open() -> bool:
	return _state == "open"


func _process(delta: float) -> void:
	if _state != "unrolling" and _state != "rolling":
		return
	_t += delta
	queue_redraw()
	if _anim != null and _anim.finished(_t):
		if _state == "unrolling":
			_finish_open()
		else:
			_state = "rolled"
			closed.emit()


func _finish_open() -> void:
	_state = "open"
	content.visible = true
	queue_redraw()
	opened.emit()


func _draw() -> void:
	var f: SpriteFrame = null
	if _state == "open":
		var open := UiArt.anim(UNROLL)
		if open != null and not open.is_empty():
			f = open.frames[open.frame_count() - 1]
	elif _anim != null and not _anim.is_empty():
		f = _anim.frame_at(_t, false)
	if f != null:
		_blit_frame(f)
	elif _state == "open":
		draw_rect(_paper_area().grow(8), Color8(255, 221, 170))
	if _state == "open":
		draw_content.emit(self)


## Draws the selected animation frame; subclasses may extend only the paper treatment.
func _blit_frame(frame: SpriteFrame) -> void:
	UiArt.blit(self, frame, Vector2.ZERO)


## Writable paper bounds used when the scroll art is unavailable.
func _paper_area() -> Rect2:
	return PARCHMENT
