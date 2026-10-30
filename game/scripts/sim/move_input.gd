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
## Manual skill presses (skill key id -> true) consumed once, and the skill keys still held (a held key requests
## repeats: Teleport after its survivor delay, a manual buff when it is ready again). See press_skill / hold_skill.
var skills_pressed := {}
var skills_held := {}


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


## Marks the skill key `id` ("teleport", "dash", "rush", "flash_jump") as pressed on this tick.
func press_skill(id: String) -> void:
	skills_pressed[id] = true


## Marks the skill key `id` as held down on this tick.
func hold_skill(id: String) -> void:
	skills_held[id] = true


## True when skill key `id` went down on this tick.
func skill_pressed(id: String) -> bool:
	return skills_pressed.has(id)


## True when skill key `id` is held down on this tick.
func skill_held(id: String) -> bool:
	return skills_held.has(id)


## True when skill key `id` is pressed or held.
func skill_requested(id: String) -> bool:
	return skills_pressed.has(id) or skills_held.has(id)


## Horizontal direction: -1 left, 1 right, 0 none or both.
func dir() -> int:
	return (1 if right else 0) - (1 if left else 0)
