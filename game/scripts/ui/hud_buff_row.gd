class_name HudBuffRow
extends HudReservedSlot
## Canonical v83 skill icons and remaining-time labels for the active player buff snapshot.

## tier C: compact 32 px icons, 4 px gaps, labels below the icons.
const SLOT_STEP := 36.0
var library: AssetLibrary
var _slots: Array[Dictionary] = []
var _font: SystemFont


func _ready() -> void:
	_font = HudWidget.make_font()


## Builds the icon/countdown data drawn from player_state.buffs.
func update(ps: Dictionary, info: Dictionary) -> void:
	super.update(ps, info)
	_slots.clear()
	var lib := library if library != null else AssetLibrary.get_default()
	for buff: Dictionary in ps.get("buffs", []):
		var icon: SpriteFrame = lib.frame(buff.icon) if lib != null else null
		_slots.append({"skill": String(buff.skill), "skill_id": int(buff.skill_id), "icon": icon,
			"remaining_seconds": ceili(float(buff.remaining))})


## Exactly the icon/countdown model used by drawing.
func displayed() -> Array:
	return _slots.duplicate()


func _draw() -> void:
	if _font == null:
		return
	for i in _slots.size():
		var slot: Dictionary = _slots[i]
		var x := i * SLOT_STEP
		var icon: SpriteFrame = slot.icon
		if icon != null:
			draw_texture_rect_region(icon.page, Rect2(Vector2(x, 0), icon.region.size), icon.region)
		var label := Hud.format_time(float(slot.remaining_seconds))
		var pos := Vector2(x + (32 - _font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x) * 0.5, 42)
		draw_string_outline(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, 2, Color(0, 0, 0, 0.9))
		draw_string(_font, pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color.WHITE)
