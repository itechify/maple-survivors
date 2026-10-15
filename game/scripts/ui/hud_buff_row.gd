class_name HudBuffRow
extends HudWidget
## Canonical v83 skill icons and remaining-time labels for the active player buff snapshot.

## tier C: compact 32 px icons, 4 px gaps, labels below the icons.
const SLOT_STEP := 36.0
var _slots: Array[Dictionary] = []


## Builds the icon/countdown data drawn from player_state.buffs.
func update(ps: Dictionary, info: Dictionary) -> void:
	super.update(ps, info)
	_slots.clear()
	for buff: Dictionary in ps.get("buffs", []):
		_slots.append({"skill": String(buff.skill), "skill_id": int(buff.skill_id), "icon": _frame(buff.icon, true),
			"remaining_seconds": ceili(float(buff.remaining))})


## Exactly the icon/countdown model used by drawing.
func displayed() -> Array:
	return _slots.duplicate()


func _draw() -> void:
	if font == null:
		return
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		var x := i * SLOT_STEP
		_blit(slot.icon, Vector2(x, 0))
		var label := format_time(float(slot.remaining_seconds))
		_text(Vector2(x + (32 - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) * 0.5, 42), label,
			Color.WHITE, 10)
