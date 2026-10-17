class_name EquipWindow
extends InventoryWindow
## The v83 Equip window (hotkey E, or Menu -> Equip; #108): UI.wz/UIWindow.img/Equip `backgrnd` (EQUIPMENT INVENTORY,
## the slot grid with the character outline) with each worn item's icon in its v83 slot: CAP, CLOTHES (a top or an
## overall), PANTS, SHOES, GLOVES and WEAPON; the other slots of the art have no equipment in this game. BtUIClose in
## the bottom strip closes the window.
##
##   EquipWindow.new(world)   # world: the RunWorld whose character is shown and changed
##
## A double-click on a worn item takes it off into the inventory (RunWorld.unequip_item), so does dragging it onto
## the Item window; an inventory item dragged from the Item window onto this window is worn (RunWorld.equip_item,
## v83 requirements enforced). Worn items cannot be discarded: a drag off the windows does nothing. Hovering a worn
## item shows its v83 tooltip. Without the cache the window keeps its size and draws plain slots.

const ART := "UI.wz/UIWindow.img/Equip/"
const CLOSE := "UI.wz/UIWindow.img/BtUIClose"
## v83 Equip backgrnd size.
const WINDOW_SIZE := Vector2(175, 304)
## tier C (ours, measured on the v83 backgrnd; cross-checked tier B against JourneyClient's slot offsets): the 32 px
## slot cells of the equip slots this game has. The top and the overall share the CLOTHES cell.
const SLOT_POS := {"hat": Vector2(38, 35), "top": Vector2(38, 134), "overall": Vector2(38, 134),
	"bottom": Vector2(38, 167), "shoes": Vector2(71, 200), "gloves": Vector2(5, 167), "weapon": Vector2(104, 134)}
## The cells in hit-test order (the CLOTHES cell answers "top" or "overall", see slot_at).
const CELLS := ["hat", "top", "bottom", "shoes", "gloves", "weapon"]
## tier C (ours): the close button in the bottom strip.
const CLOSE_BUTTON_POS := Vector2(10, 281)
## tier C (ours): the slot labels drawn without the cache.
const LABELS := {"hat": "CAP", "top": "CLOTHES", "bottom": "PANTS", "shoes": "SHOES", "gloves": "GLOVES",
	"weapon": "WEAPON"}

var _bt_close: WzButton


func _init(p_world: RunWorld = null) -> void:
	super._init(p_world)
	name = "EquipWindow"
	window_id = "equip"
	size = WINDOW_SIZE
	_bt_close = WzButton.new(CLOSE)
	_bt_close.name = "Close"
	_bt_close.fallback_size = Vector2(32, 15)
	_bt_close.label = "" if _bt_close.has_art() else "X"
	_bt_close.position = CLOSE_BUTTON_POS
	_bt_close.pressed.connect(request_close)
	add_child(_bt_close)


## The local rect of an equip slot's cell.
func slot_rect(slot: String) -> Rect2:
	return Rect2(SLOT_POS.get(slot, Vector2(-100, -100)), ICON_SLOT)


## The equip slot whose cell holds local point `p` ("" outside the cells); the CLOTHES cell is "overall" while an
## overall is worn, else "top".
func slot_at(p: Vector2) -> String:
	for slot: String in CELLS:
		if slot_rect(slot).has_point(p):
			if slot == "top" and world != null and world.equipment.worn.has("overall"):
				return "overall"
			return slot
	return ""


## The item id worn in `slot` (0 for none).
func worn_id(slot: String) -> int:
	if world == null or not world.equipment.worn.has(slot):
		return 0
	return int(world.equipment.worn[slot].id)


## Takes the item worn in `slot` off into the inventory; "" or the RunWorld reason (its message is emitted).
func take_off(slot: String) -> String:
	return apply("unequip", world.unequip_item(slot))


## tier C (ours): the Equip window opens left of the view's centre so the Item window fits beside it.
func default_position(view: Vector2) -> Vector2:
	var p := super.default_position(view)
	return Vector2(maxf(0.0, floorf(view.x * 0.5) - size.x - 4.0), p.y)


func payload_at(p: Vector2) -> Dictionary:
	var slot := slot_at(p)
	if slot == "" or worn_id(slot) == 0:
		return {}
	return {"kind": "worn", "slot": slot, "id": worn_id(slot)}


func activate(payload: Dictionary) -> void:
	if String(payload.get("kind", "")) == "worn":
		take_off(String(payload.slot))


func receive_drop(payload: Dictionary) -> bool:
	if String(payload.get("kind", "")) != "inventory":
		return false
	return apply("equip", world.equip_item(int(payload.index))) == ""


func tooltip_for(payload: Dictionary) -> Dictionary:
	var slot := String(payload.get("slot", ""))
	if String(payload.get("kind", "")) != "worn" or world == null or not world.equipment.worn.has(slot):
		return {}
	return equip_tooltip(world.equipment.worn[slot])


func _draw() -> void:
	var bg := UiArt.frame(ART + "backgrnd")
	if bg != null:
		UiArt.blit(self, bg, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(220, 228, 240))
		draw_rect(Rect2(Vector2.ZERO, size), Color8(99, 147, 183), false)
		MapleText.draw(self, Vector2(8, 4), "EQUIPMENT INVENTORY", MapleText.BLACK, MapleText.SMALL, true)
		for slot: String in CELLS:
			var r := slot_rect(slot)
			draw_rect(r, Color8(176, 196, 222))
			MapleText.draw(self, r.position + Vector2(1, 0), String(LABELS[slot]), Color8(90, 110, 140), 8)
	if world != null:
		for slot: String in Equipment.SLOTS:
			var id := worn_id(slot)
			if id == 0:
				continue
			var dim := _is_dragged({"kind": "worn", "slot": slot, "id": id})
			UiArt.blit_icon(self, UiArt.icon_or_fallback(InventoryModel.icon_path(id)), slot_rect(slot).position,
				ICON_SLOT, Color(1, 1, 1, 0.35) if dim else Color.WHITE)
	_draw_drag()
