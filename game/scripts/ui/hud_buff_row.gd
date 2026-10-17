class_name HudBuffRow
extends HudWidget
## Canonical v83 skill icons and remaining-time labels for the active player buff snapshot, then statuses on the
## character (Seal, `player_state.seal`, #76) with their countdown.

## tier C: compact 32 px icons, 4 px gaps, labels below the icons.
const SLOT_STEP := 36.0
var _slots: Array[Dictionary] = []


## Builds the icon/countdown data drawn from player_state.buffs and player_state.seal.
func update(ps: Dictionary, info: Dictionary) -> void:
	super.update(ps, info)
	_slots.clear()
	for buff: Dictionary in ps.get("buffs", []):
		_slots.append({"skill": String(buff.skill), "skill_id": int(buff.skill_id), "icon": _frame(buff.icon, true),
			"remaining_seconds": ceili(float(buff.remaining)), "status": false})
	var seal: Dictionary = ps.get("seal", {})
	if not seal.is_empty():
		# tier C: v83 has no Seal status icon (UI.wz/BuffIcon.img lists buffs only; MobSkill 120 has no icon), so the
		# first frame of its canonical affected animation stands in, fitted into the 32 px slot.
		_slots.append({"skill": "seal", "skill_id": int(seal.skill_id), "icon": _frame(String(seal.icon), true),
			"remaining_seconds": ceili(float(seal.remaining)), "status": true})


## Exactly the icon/countdown model used by drawing.
func displayed() -> Array:
	return _slots.duplicate()


func _draw() -> void:
	if font == null:
		return
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		var x := i * SLOT_STEP
		if bool(slot.status):
			_blit_fit(slot.icon, Rect2(x, 0, SKILL_ICON, SKILL_ICON))
		else:
			_blit(slot.icon, Vector2(x, 0))
		var label := format_time(float(slot.remaining_seconds))
		_text(Vector2(x + (32 - font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) * 0.5, 42), label,
			Color.WHITE, 10)


## Draws a canvas scaled down (never up) to fit `box`, keeping its aspect, centred.
func _blit_fit(f: SpriteFrame, box: Rect2) -> void:
	if f == null or f.page == null:
		return
	var size := f.region.size
	var scale := minf(1.0, minf(box.size.x / size.x, box.size.y / size.y))
	var drawn := (size * scale).floor()
	_blit_rect(f, Rect2((box.position + (box.size - drawn) * 0.5).floor(), drawn))
