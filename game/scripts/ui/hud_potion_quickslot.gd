class_name HudPotionQuickslot
extends HudWidget
## HP/MP potion icons, current unlimited stock counts and drink keys (the live bindings: GameSettings.action_label) in the
## status bar's reserved quickslot area.

## tier C: two readable slots within the status bar's 221 x 59 reserved region.
const SLOT_STEP := 104.0
## Potion kind -> its drink action.
const ACTIONS := {"hp": "drink_hp", "mp": "drink_mp"}

var slots: Array[Dictionary] = []


## Receives the potion snapshot and builds exactly the slot data used by drawing.
func update(ps: Dictionary, info: Dictionary) -> void:
	super.update(ps, info)
	slots = []
	for kind: String in ["hp", "mp"]:
		var stock: Dictionary = ps.get("potions", {}).get(kind, {})
		var id := int(stock.get("item_id", 0))
		var icon: SpriteFrame = _frame(AssetLibrary.item_icon_path(id, false), true) if id > 0 else null
		slots.append({"kind": kind, "item_id": id, "count": int(stock.get("count", 0)),
			"key_label": GameSettings.action_label(ACTIONS[kind]), "icon": icon})


## The currently displayed slot (same snapshot and icon used by _draw), or {} for an unknown kind.
func displayed(kind: String) -> Dictionary:
	for slot: Dictionary in slots:
		if slot.kind == kind:
			return slot.duplicate()
	return {}


func _draw() -> void:
	if font == null:
		return
	for i in slots.size():
		var slot: Dictionary = slots[i]
		var x := 5.0 + i * SLOT_STEP
		var box := Rect2(x, 0, 36, 36)
		draw_rect(box, Color8(31, 56, 80, 210))
		draw_rect(box, Color8(99, 147, 183), false)
		var icon: SpriteFrame = slot.icon
		if icon != null:
			_blit(icon, box.position + ((box.size - icon.region.size) * 0.5).floor())
		_text(Vector2(x + 42, 23), str(slot.count), Color.WHITE, FONT_SIZE, null, 1.0, Color(0, 0, 0, 0.8))
		_text(Vector2(x, 51), "%s %s" % [String(slot.kind).to_upper(), slot.key_label], Color8(40, 59, 76), 10, null,
			1.0, Color(1, 1, 1, 0.8))
