class_name HudPotionQuickslot
extends HudReservedSlot
## HP/MP potion icons, current unlimited stock counts and drink keys in the status bar's reserved quickslot area.

## tier C: two readable slots within the status bar's 221 x 59 reserved region.
const SLOT_STEP := 104.0
const KEY_LABELS := {"hp": "Del / Q", "mp": "End / E"}

var library: AssetLibrary
var slots: Array[Dictionary] = []
var _font: SystemFont


func _ready() -> void:
	_font = HudWidget.make_font()


## Receives the potion snapshot and builds exactly the slot data used by drawing.
func update(ps: Dictionary, info: Dictionary) -> void:
	super.update(ps, info)
	slots = []
	for kind: String in ["hp", "mp"]:
		var stock: Dictionary = ps.get("potions", {}).get(kind, {})
		var id := int(stock.get("item_id", 0))
		var icon: SpriteFrame = null
		var lib := library if library != null else AssetLibrary.get_default()
		if lib != null and id > 0:
			icon = lib.frame(AssetLibrary.item_icon_path(id, false))
		slots.append({"kind": kind, "item_id": id, "count": int(stock.get("count", 0)),
			"key_label": KEY_LABELS[kind], "icon": icon})


## The currently displayed slot (same snapshot and icon used by _draw), or {} for an unknown kind.
func displayed(kind: String) -> Dictionary:
	for slot: Dictionary in slots:
		if slot.kind == kind:
			return slot.duplicate()
	return {}


func _draw() -> void:
	if _font == null:
		return
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var x := 5.0 + i * SLOT_STEP
		var box := Rect2(x, 0, 36, 36)
		draw_rect(box, Color8(31, 56, 80, 210))
		draw_rect(box, Color8(99, 147, 183), false)
		var icon: SpriteFrame = slot.icon
		if icon != null:
			var top := box.position + ((box.size - icon.region.size) * 0.5).floor()
			draw_texture_rect_region(icon.page, Rect2(top, icon.region.size), icon.region)
		_text(Vector2(x + 42, 23), str(slot.count), Color.WHITE)
		_text(Vector2(x, 51), "%s %s" % [String(slot.kind).to_upper(), slot.key_label], Color8(40, 59, 76), 10)


func _text(pos: Vector2, text: String, color: Color, font_size: int = 12) -> void:
	draw_string_outline(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 2,
		Color(0, 0, 0, 0.8) if color == Color.WHITE else Color(1, 1, 1, 0.8))
	draw_string(_font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
