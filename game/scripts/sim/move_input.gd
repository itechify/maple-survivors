class_name MoveInput
extends RefCounted
## One tick of player movement intent, filled by the presentation from the keyboard (or by tests/bots).
## `jump_pressed` is true only on the tick the jump key went down; `jump_held` while it stays down.

var left := false
var right := false
var up := false
var down := false
var jump_pressed := false
var jump_held := false
## Potion presses are consumed once by a sim tick; holding the key does not repeatedly drink.
var drink_hp := false
var drink_mp := false
## Manual skill press consumed once; held intent requests repeats after the survivor delay.
var teleport_pressed := false
var teleport_held := false


## Convenience constructor.
static func make(p_left := false, p_right := false, p_up := false, p_down := false, p_jump_pressed := false,
		p_jump_held := false) -> MoveInput:
	var m := MoveInput.new()
	m.left = p_left
	m.right = p_right
	m.up = p_up
	m.down = p_down
	m.jump_pressed = p_jump_pressed
	m.jump_held = p_jump_held
	return m


## Horizontal direction: -1 left, 1 right, 0 none or both.
func dir() -> int:
	return (1 if right else 0) - (1 if left else 0)
