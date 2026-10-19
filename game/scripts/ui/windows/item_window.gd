class_name ItemWindow
extends InventoryWindow
## The v83 Item window (hotkey I, or Menu -> Item; #108): UI.wz/UIWindow.img/Item `backgrnd` (ITEM INVENTORY) with
## the v83 tabs Equip, Use, Set-up, Etc and Cash (`Tab/enabled` for the shown one, `Tab/disabled` for the rest), the
## 4 x 6 = 24 slots and the meso line (BtCoin and the mesos in the field beside the baked MESOS).
##
##   ItemWindow.new(world)   # world: the RunWorld whose character is shown and changed
##
## Equip tab: the spare equipment (RunWorld.equipment.inventory) in order; a double-click wears an item, so does
## dragging it onto the Equip window (RunWorld.equip_item: v83 requirements enforced, a refusal shows its message
## and changes nothing); a worn item dragged here from the Equip window is taken off. Dragging an item off the
## windows asks the v83 YesNo question (DropConfirm) and then destroys it (RunWorld.discard_item; it is not dropped
## on the ground, the magnet would take it straight back: tier C). Use tab: the HP and MP potion stacks (read-only,
## the potions keep their quickslot keys) and the scroll stacks (Basic.img/ItemNo counts); scrolls can be discarded
## the same way, potions never. Set-up, Etc and Cash are empty. Hovering a slot shows the item's tooltip. Without the
## cache the window keeps its layout and draws plain tabs and slots.

const ART := "UI.wz/UIWindow.img/Item/"
## v83 Item backgrnd size.
const WINDOW_SIZE := Vector2(175, 289)
## The tabs in v83 order (Tab/<state>/0..4 glyphs).
const TABS := ["equip", "use", "setup", "etc", "cash"]
const TAB_NAMES := ["Equip", "Use", "Set-up", "Etc", "Cash"]
## tier C (ours, measured on the v83 backgrnd; the tab x offsets cross-checked tier B against JourneyClient): the
## tab strip, where each tab glyph starts, the first slot, the slot pitch and the meso field.
const TAB_STRIP := Rect2(3, 23, 169, 19)
const TAB_X := [10, 42, 74, 108, 139]
const SLOT_ORIGIN := Vector2(8, 50)
const SLOT_PITCH := Vector2(36, 34)
const COLS := 4
const ROWS := 6
const MESO_FIELD := Rect2(25, 267, 113, 14)
const COIN_POS := Vector2(8, 267)
## tier C (ours): the stack count's place in a slot (Basic.img/ItemNo digits are 11 px tall).
const COUNT_AT := Vector2(1, 21)

## The shown tab (index into TABS).
var tab := 0

var _bt_coin: WzButton


func _init(p_world: RunWorld = null) -> void:
	super._init(p_world)
	name = "ItemWindow"
	window_id = "item"
	size = WINDOW_SIZE
	# v83's BtCoin opens the meso-drop dialog; mesos are never dropped here, so it only shows its disabled art.
	_bt_coin = WzButton.new(ART + "BtCoin")
	_bt_coin.name = "Coin"
	_bt_coin.fallback_size = Vector2(14, 14)
	_bt_coin.position = COIN_POS
	_bt_coin.disabled = true
	_bt_coin.sounds = false
	add_child(_bt_coin)


## Shows tab `i` (clamped).
func select_tab(i: int) -> void:
	tab = clampi(i, 0, TABS.size() - 1)
	_hover = {}
	_place_tip()
	queue_redraw()


## The local rect of tab `i` in the tab strip.
func tab_rect(i: int) -> Rect2:
	var x0 := float(TAB_X[i]) - 5.0
	var x1 := float(TAB_X[i + 1]) - 5.0 if i + 1 < TAB_X.size() else TAB_STRIP.end.x
	return Rect2(x0, TAB_STRIP.position.y, x1 - x0, TAB_STRIP.size.y)


## The local rect of slot `i` (0-23, row-major).
@warning_ignore("integer_division")
func slot_rect(i: int) -> Rect2:
	return Rect2(SLOT_ORIGIN + Vector2(SLOT_PITCH.x * (i % COLS), SLOT_PITCH.y * (i / COLS)), ICON_SLOT)


## The slot under local point `p` (-1 for none).
func slot_at(p: Vector2) -> int:
	for i in COLS * ROWS:
		if slot_rect(i).has_point(p):
			return i
	return -1


## What the shown tab's slots hold, in slot order: Equip tab {"kind": "inventory", "index", "id"}, Use tab
## InventoryModel.use_cells (potions, then scrolls), nothing on the other tabs.
func cells() -> Array:
	if world == null:
		return []
	match tab:
		0:
			var out := []
			for i in world.equipment.inventory.size():
				out.append({"kind": "inventory", "index": i, "id": int(world.equipment.inventory[i].id)})
			return out
		1:
			return InventoryModel.use_cells(world.potions.snapshot(), world.scrolls)
	return []


## The item in slot `i` of the shown tab ({} when empty).
func cell(i: int) -> Dictionary:
	var all := cells()
	return all[i] if i >= 0 and i < all.size() else {}


## Wears inventory item `index`; "" or the RunWorld reason (its message is emitted, nothing changes).
func wear(index: int) -> String:
	return apply("equip", world.equip_item(index))


## The meso line's text.
func meso_text() -> String:
	return InventoryModel.meso_text(world.mesos if world != null else 0)


## tier C (ours): the Item window opens right of the view's centre, beside the Equip window.
func default_position(view: Vector2) -> Vector2:
	var p := super.default_position(view)
	return Vector2(minf(view.x - size.x, floorf(view.x * 0.5) + 4.0), p.y)


func payload_at(p: Vector2) -> Dictionary:
	return cell(slot_at(p))


func activate(payload: Dictionary) -> void:
	if String(payload.get("kind", "")) == "inventory":
		wear(int(payload.index))


func receive_drop(payload: Dictionary) -> bool:
	if String(payload.get("kind", "")) != "worn":
		return false
	return apply("unequip", world.unequip_item(String(payload.slot))) == ""


## Equipment and scrolls dragged off the windows ask the v83 question first; potions are never discarded.
func drop_outside(payload: Dictionary) -> void:
	if not String(payload.get("kind", "")) in ["inventory", "scroll"]:
		return
	var stack := get_parent() as WindowStack
	if stack == null:
		return
	# The confirmation is not modal: remember the exact instance asked about, so a swapped-in copy is never destroyed.
	var instance := {}
	if String(payload.kind) == "inventory":
		var index := int(payload.index)
		if world == null or index < 0 or index >= world.equipment.inventory.size():
			return
		instance = world.equipment.inventory[index].duplicate(true)
	var confirm := DropConfirm.new(DropConfirm.DROP_QUESTION)
	confirm.confirmed.connect(_discard.bind(payload, instance))
	stack.open(confirm)


func _discard(payload: Dictionary, instance: Dictionary) -> void:
	if world == null:
		return
	if String(payload.kind) == "scroll":
		apply("discard", world.discard_scrolls(int(payload.id)))
		return
	var index := int(payload.index)
	if index < 0 or index >= world.equipment.inventory.size() or world.equipment.inventory[index] != instance:
		return
	apply("discard", world.discard_item(index))


func tooltip_for(payload: Dictionary) -> Dictionary:
	match String(payload.get("kind", "")):
		"inventory":
			var index := int(payload.index)
			if world == null or index < 0 or index >= world.equipment.inventory.size():
				return {}
			return equip_tooltip(world.equipment.inventory[index])
		"potion", "scroll":
			return use_tooltip(int(payload.id))
	return {}


func _window_gui_input(event: InputEvent, local: Vector2) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and TAB_STRIP.has_point(local):
		for i in TABS.size():
			if tab_rect(i).has_point(local):
				if i != tab:
					UiArt.play_sound(UiArt.SND_CLICK)
				select_tab(i)
				return
	super._window_gui_input(event, local)


func _draw() -> void:
	var bg := UiArt.frame(ART + "backgrnd")
	if bg != null:
		UiArt.blit(self, bg, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(220, 228, 240))
		PixelDraw.outline(self, Rect2(Vector2.ZERO, size), Color8(99, 147, 183))
		MapleText.draw(self, Vector2(8, 4), "ITEM INVENTORY", MapleText.BLACK, MapleText.SMALL, true)
		draw_rect(TAB_STRIP, Color8(200, 204, 212))
		for i in COLS * ROWS:
			draw_rect(slot_rect(i), Color8(222, 218, 204))
		draw_rect(MESO_FIELD, Color.WHITE)
	_draw_tabs()
	var all := cells()
	for i in mini(all.size(), COLS * ROWS):
		var c: Dictionary = all[i]
		var r := slot_rect(i)
		var dim := _is_dragged(c)
		UiArt.blit_icon(self, UiArt.icon_or_fallback(InventoryModel.icon_path(int(c.id))), r.position, ICON_SLOT,
			Color(1, 1, 1, 0.35) if dim else Color.WHITE)
		if c.has("count"):
			_draw_count(r.position + COUNT_AT, int(c.count))
	var text := meso_text()
	MapleText.draw(self, Vector2(MESO_FIELD.end.x - 3.0 - MapleText.width(text, MapleText.SMALL), MESO_FIELD.position.y),
		text, MapleText.BLACK, MapleText.SMALL)
	_draw_drag()


func _draw_tabs() -> void:
	for i in TABS.size():
		var on := i == tab
		var glyph := UiArt.frame(ART + "Tab/%s/%d" % ["enabled" if on else "disabled", i])
		var r := tab_rect(i)
		if glyph != null:
			UiArt.blit(self, glyph, Vector2(float(TAB_X[i]), r.position.y + floorf((r.size.y - glyph.region.size.y) * 0.5)))
		else:
			MapleText.draw(self, Vector2(float(TAB_X[i]), r.position.y + 3.0), String(TAB_NAMES[i]),
				MapleText.BLACK if on else MapleText.GREY, 9, on)
