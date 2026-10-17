class_name EquipWindow
extends InventoryWindow
## The v83 Equip window (hotkey E, or Menu -> Equip; #108) with the Cash tab and the Pet page (spec #34, #122).
##
## Equip page: UI.wz/UIWindow.img/Equip `backgrnd` (EQUIPMENT INVENTORY, the slot grid with the character outline) with
## each worn item's icon in its v83 slot: CAP, CLOTHES (a top or an overall), PANTS, SHOES, GLOVES and WEAPON; the other
## slots of the art have no equipment in this game. BtUIClose in the bottom strip closes the window.
##
## The bottom strip also switches the page (`set_page`): the Equip and Cash glyphs of the Item window's tab art, and the
## v83 BtPetEquipShow ("PET EQUIP.") button for the Pet page.
##
## Cash page (tier C: v83's Equip art has no cash tab, so the page reuses the `backgrnd` grid): the character's 11 cash
## slots in the cells their labels name (CAP hat, FOREHEAD face, EYE ACC eye, EAR ACC earrings, CLOTHES top, PANTS
## bottom, SHOES, GLOVES, MANTLE cape, WEAPON, SHIELD); an overall shows in CLOTHES and, dimmed, in PANTS, a two-handed
## cover in WEAPON and, dimmed, in SHIELD. Beside it a panel lists the account's owned cash equipment (the same panel
## style as the slot cells; mouse wheel or the arrows turn its pages). A double-click on an owned item wears it
## (RunWorld.wear_cash: it replaces what was in its slots), a double-click on a worn item takes it off
## (RunWorld.take_off_cash). Every character can wear every owned item; nothing is used up or moved.
##
## Pet page (v83 `Equip/pet` art, labels HP POC / PET HP / MP POC / PET MP / ITEM POC / MESO MAG / PICK UP / POS /
## PET EQUIP / ITEM IGNORE / MOVE UP / PET RING baked in): the owned pet upgrades sit read-only in their cells and the
## panel beside it lists the owned pets; a double-click on a pet brings it out (RunWorld.set_pet), on the pet that is
## out puts it away. Upgrades belong to the account and always apply, so they cannot be taken off. tier C mapping of
## the upgrades to the baked labels: Auto HP / Auto MP pouch -> HP POC / MP POC (the character's own potion shows in
## PET HP / PET MP), Binocular -> POS, VAC -> PET EQUIP, Wing Boots -> MOVE UP; the base pet's Item Pouch and Meso
## Magnet fill ITEM POC and MESO MAG while a pet is out.
##
##   EquipWindow.new(world)   # world: the RunWorld whose character is shown and changed
##
## A double-click on a worn item takes it off into the inventory (RunWorld.unequip_item), so does dragging it onto
## the Item window; an inventory item dragged from the Item window onto this window is worn (RunWorld.equip_item,
## v83 requirements enforced). Worn items cannot be discarded: a drag off the windows does nothing. Hovering an item
## shows its tooltip. Without the cache the window keeps its size and draws plain slots.

const ART := "UI.wz/UIWindow.img/Equip/"
const CLOSE := "UI.wz/UIWindow.img/BtUIClose"
const PET_BUTTON := "UI.wz/UIWindow.img/Equip/BtPetEquipShow"
const TAB_ART := "UI.wz/UIWindow.img/Item/Tab/"
## v83 Equip backgrnd size.
const WINDOW_SIZE := Vector2(175, 304)
## v83 Equip/pet size.
const PET_SIZE := Vector2(177, 181)
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

## The pages (`page`).
const PAGES := ["equip", "cash", "pet"]
## tier C (ours, measured on the v83 backgrnd): the cell of each of the 11 cash slots, named by the label baked there.
const CASH_POS := {"hat": Vector2(38, 35), "face": Vector2(38, 68), "eye": Vector2(71, 101),
	"earrings": Vector2(104, 101), "top": Vector2(38, 134), "bottom": Vector2(38, 167), "shoes": Vector2(71, 200),
	"gloves": Vector2(5, 167), "cape": Vector2(5, 134), "weapon": Vector2(104, 134), "shield": Vector2(137, 134)}
const CASH_LABELS := {"hat": "CAP", "face": "FOREHEAD", "eye": "EYE ACC", "earrings": "EAR ACC", "top": "CLOTHES",
	"bottom": "PANTS", "shoes": "SHOES", "gloves": "GLOVES", "cape": "MANTLE", "weapon": "WEAPON", "shield": "SHIELD"}
## tier C (ours, measured on Equip/pet): the pet upgrade cells (item id -> cell) and the two potion cells.
const PET_CELLS := {1812002: Vector2(13, 11), 1812003: Vector2(79, 11), 1812001: Vector2(13, 44),
	1812000: Vector2(46, 44), 1812005: Vector2(79, 77), 9990000: Vector2(112, 77), 1812004: Vector2(13, 110)}
const PET_POTION_CELLS := {"hp": Vector2(46, 11), "mp": Vector2(112, 11)}
## The base pet's pouch and magnet, shown while a pet is out (not sold, so never owned).
const BASE_PET_ITEMS := [1812000, 1812001]
## tier C (ours): the owned-items panel beside the cash and pet pages: gap to the art, width, slot pitch, columns, the
## header height above and the pager/hint height below the slots.
const PANEL_GAP := 4.0
const PANEL_W := 152.0
const PANEL_PITCH := Vector2(36, 36)
const PANEL_COLS := 4
const PANEL_TOP := 24.0
const PANEL_BOTTOM := 42.0
const PANEL_FILL := Color8(220, 228, 240)
const PANEL_EDGE := Color8(99, 147, 183)
const CELL_FILL := Color8(176, 196, 222)
const WORN_EDGE := Color8(255, 170, 0)
## tier C (ours): the strip's controls, relative to the art's bottom edge.
const TAB_EQUIP := Rect2(46, -23, 28, 17)
const TAB_CASH := Rect2(76, -23, 24, 17)
const PET_BUTTON_POS := Vector2(104, -22)

## The page shown ("equip", "cash" or "pet").
var page := "equip"
## The owned-items panel's page (0-based).
var owned_page := 0

var _bt_close: WzButton
var _bt_pet: WzButton
var _catalog: CashCatalog


func _init(p_world: RunWorld = null) -> void:
	super._init(p_world)
	name = "EquipWindow"
	window_id = "equip"
	size = WINDOW_SIZE
	_bt_close = WzButton.new(CLOSE)
	_bt_close.name = "Close"
	_bt_close.fallback_size = Vector2(32, 15)
	_bt_close.label = "" if _bt_close.has_art() else "X"
	_bt_close.pressed.connect(request_close)
	add_child(_bt_close)
	_bt_pet = WzButton.new(PET_BUTTON)
	_bt_pet.name = "PetPage"
	_bt_pet.fallback_size = Vector2(54, 18)
	_bt_pet.label = "" if _bt_pet.has_art() else "PET"
	_bt_pet.pressed.connect(set_page.bind("pet"))
	add_child(_bt_pet)
	_layout()


# --- pages -------------------------------------------------------------------------------------------------------------

## Shows page `p` ("equip", "cash" or "pet"; anything else is ignored): the window takes the page's art size, plus the
## owned-items panel on the cash and pet pages.
func set_page(p: String) -> void:
	if not p in PAGES or p == page:
		return
	page = p
	owned_page = 0
	_hover = {}
	_pressed = {}
	_drag = {}
	_layout()
	_place_tip()
	queue_redraw()


## The local size of the page's art (the window is wider by the panel on the cash and pet pages).
func art_size() -> Vector2:
	return PET_SIZE if page == "pet" else WINDOW_SIZE


## The local rect of the owned-items panel (a zero rect on the equip page).
func panel_rect() -> Rect2:
	if page == "equip":
		return Rect2()
	return Rect2(art_size().x + PANEL_GAP, 0.0, PANEL_W, art_size().y)


## The strip controls' local rects: "equip" and "cash" tabs.
func tab_rect(which: String) -> Rect2:
	var r: Rect2 = TAB_EQUIP if which == "equip" else TAB_CASH
	return Rect2(r.position + Vector2(0, art_size().y), r.size)


func _layout() -> void:
	var art := art_size()
	size = art if page == "equip" else Vector2(art.x + PANEL_GAP + PANEL_W, art.y)
	_bt_close.position = Vector2(CLOSE_BUTTON_POS.x, art.y - (WINDOW_SIZE.y - CLOSE_BUTTON_POS.y))
	_bt_pet.position = PET_BUTTON_POS + Vector2(0, art.y)
	_bt_pet.disabled = page == "pet"


# --- equip page ----------------------------------------------------------------------------------------------------------

## The local rect of an equip slot's cell.
func slot_rect(slot: String) -> Rect2:
	return Rect2(SLOT_POS.get(slot, Vector2(-100, -100)), ICON_SLOT)


## The equip slot whose cell holds local point `p` ("" outside the cells); the CLOTHES cell is "overall" while an
## overall is worn, else "top".
func slot_at(p: Vector2) -> String:
	if page != "equip":
		return ""
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


# --- cash page -------------------------------------------------------------------------------------------------------------

## The local rect of a cash slot's cell.
func cash_rect(slot: String) -> Rect2:
	return Rect2(CASH_POS.get(slot, Vector2(-100, -100)), ICON_SLOT)


## The cash slot whose cell holds local point `p` ("" outside the cells or off the cash page).
func cash_slot_at(p: Vector2) -> String:
	if page != "cash":
		return ""
	for slot: String in CashCatalog.SLOTS:
		if cash_rect(slot).has_point(p):
			return slot
	return ""


## The cash item worn in `slot` (0 for none or without a world).
func cash_id(slot: String) -> int:
	return int(world.worn_cash.get(slot, 0)) if world != null else 0


## Wears owned cash equipment `id`; "" or the RunWorld reason (nothing changes).
func wear_cash(id: int) -> String:
	return apply("wear_cash", world.wear_cash(id))


## Takes off the cash item in `slot`; "" or the RunWorld reason.
func take_off_cash(slot: String) -> String:
	return apply("take_off_cash", world.take_off_cash(slot))


## Brings the owned pet `species` out, or puts it away when it already is out; "" or the RunWorld reason.
func toggle_pet(species: int) -> String:
	return apply("pet", world.set_pet(0 if world.pet == species else species))


# --- owned panel ---------------------------------------------------------------------------------------------------------

## The account's owned items the panel lists on this page: cash equipment (in slot order) on the cash page, pets on the
## pet page; empty on the equip page.
func owned_items() -> Array:
	if world == null or page == "equip":
		return []
	var catalog := _cash_catalog()
	var want := "equip" if page == "cash" else "pet"
	var ids: Array = []
	for id: Variant in world.account_owned:
		if catalog.kind_of(int(id)) == want:
			ids.append(int(id))
	ids.sort_custom(func(a: int, b: int) -> bool:
		var sa := _slot_order(catalog, a)
		var sb := _slot_order(catalog, b)
		return a < b if sa == sb else sa < sb)
	return ids


## How many panel cells fit on a page.
func panel_capacity() -> int:
	var rows := maxi(1, int(floorf((art_size().y - PANEL_TOP - PANEL_BOTTOM) / PANEL_PITCH.y)))
	return rows * PANEL_COLS


## How many panel pages the owned items fill (at least 1).
func owned_pages() -> int:
	return maxi(1, ceili(float(owned_items().size()) / float(panel_capacity())))


## Shows panel page `i` (clamped).
func select_owned_page(i: int) -> void:
	owned_page = clampi(i, 0, owned_pages() - 1)
	_hover = {}
	_place_tip()
	queue_redraw()


## The local rect of panel cell `i` of the shown panel page.
@warning_ignore("integer_division")
func panel_cell(i: int) -> Rect2:
	var p := panel_rect()
	return Rect2(p.position + Vector2(8, PANEL_TOP) + Vector2(PANEL_PITCH.x * (i % PANEL_COLS),
		PANEL_PITCH.y * (i / PANEL_COLS)), ICON_SLOT)


## The owned item shown in panel cell `i` of the shown page (0 for an empty cell).
func panel_item(i: int) -> int:
	var all := owned_items()
	var k := owned_page * panel_capacity() + i
	return int(all[k]) if i >= 0 and k < all.size() else 0


## The panel cell holding local point `p` (-1 for none).
func panel_cell_at(p: Vector2) -> int:
	if page == "equip" or not panel_rect().has_point(p):
		return -1
	for i in panel_capacity():
		if panel_cell(i).has_point(p):
			return i
	return -1


## The local rects of the panel's "previous page" and "next page" arrows.
func pager_rects() -> Array[Rect2]:
	var p := panel_rect()
	var y := p.end.y - PANEL_BOTTOM + 3.0
	return [Rect2(p.position.x + 8.0, y, 16, 14), Rect2(p.end.x - 24.0, y, 16, 14)]


# --- pet page --------------------------------------------------------------------------------------------------------------

## The pet-page cells in hit-test order: [{"cell": Vector2, "payload": {...}}] for every upgrade and potion shown.
func pet_cells() -> Array:
	var out: Array = []
	if world == null:
		return out
	for id: int in PET_CELLS:
		if (BASE_PET_ITEMS.has(id) and world.pet > 0) or (not BASE_PET_ITEMS.has(id) and world.account_owned.has(id)):
			out.append({"cell": PET_CELLS[id], "payload": {"kind": "pet_upgrade", "id": id}})
	for kind: String in PET_POTION_CELLS:
		var pouch := PetSystem.UPGRADE_AUTO_HP if kind == "hp" else PetSystem.UPGRADE_AUTO_MP
		var stock: Dictionary = world.potions.snapshot().get(kind, {})
		if world.account_owned.has(pouch) and int(stock.get("item_id", 0)) > 0:
			out.append({"cell": PET_POTION_CELLS[kind], "payload": {"kind": "potion", "potion": kind,
				"id": int(stock.item_id)}})
	return out


# --- window protocol -----------------------------------------------------------------------------------------------------

## tier C (ours): the Equip window opens left of the view's centre so the Item window fits beside it.
func default_position(view: Vector2) -> Vector2:
	var p := super.default_position(view)
	return Vector2(maxf(0.0, floorf(view.x * 0.5) - size.x - 4.0), p.y)


func payload_at(p: Vector2) -> Dictionary:
	match page:
		"equip":
			var slot := slot_at(p)
			if slot == "" or worn_id(slot) == 0:
				return {}
			return {"kind": "worn", "slot": slot, "id": worn_id(slot)}
		"cash":
			var cash_slot := cash_slot_at(p)
			if cash_slot != "" and cash_id(cash_slot) != 0:
				return {"kind": "cash_worn", "slot": cash_slot, "id": cash_id(cash_slot)}
			return _owned_payload_at(p, "cash_owned")
		"pet":
			for c: Dictionary in pet_cells():
				if Rect2(c.cell, ICON_SLOT).has_point(p):
					return c.payload
			return _owned_payload_at(p, "pet_owned")
	return {}


func _owned_payload_at(p: Vector2, kind: String) -> Dictionary:
	var id := panel_item(panel_cell_at(p))
	return {} if id == 0 else {"kind": kind, "id": id}


func activate(payload: Dictionary) -> void:
	match String(payload.get("kind", "")):
		"worn":
			take_off(String(payload.slot))
		"cash_worn":
			take_off_cash(String(payload.slot))
		"cash_owned":
			wear_cash(int(payload.id))
		"pet_owned":
			toggle_pet(int(payload.id))


func receive_drop(payload: Dictionary) -> bool:
	if page != "equip" or String(payload.get("kind", "")) != "inventory":
		return false
	return apply("equip", world.equip_item(int(payload.index))) == ""


func tooltip_for(payload: Dictionary) -> Dictionary:
	var kind := String(payload.get("kind", ""))
	var slot := String(payload.get("slot", ""))
	match kind:
		"worn":
			if world == null or not world.equipment.worn.has(slot):
				return {}
			return equip_tooltip(world.equipment.worn[slot])
		"cash_worn", "cash_owned", "pet_owned", "pet_upgrade":
			return _cash_tooltip(int(payload.id))
		"potion":
			return use_tooltip(int(payload.id))
	return {}


## The name, description and icon of a cash item, pet or pet upgrade (String.wz, or the catalog for survivor-only ones).
func _cash_tooltip(id: int) -> Dictionary:
	var lib := AssetLibrary.get_default()
	var catalog := _cash_catalog()
	var name := CashShop.item_name(lib, catalog, id)
	return {"name": name if name != "" else "Item %d" % id, "desc": CashShop.item_desc(lib, catalog, id).replace("\\n", "\n"),
		"icon": CashShop.icon_path(catalog, id)}


func _cash_catalog() -> CashCatalog:
	if _catalog == null:
		_catalog = CashCatalog.from_data(world.data if world != null else {})
	return _catalog


static func _slot_order(catalog: CashCatalog, id: int) -> int:
	var slots := catalog.slots_for(id)
	return CashCatalog.SLOTS.find(slots[0]) if not slots.is_empty() else CashCatalog.SLOTS.size()


# --- mouse -----------------------------------------------------------------------------------------------------------------

func _window_gui_input(event: InputEvent, local: Vector2) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if panel_rect().has_point(local):
				select_owned_page(owned_page + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1))
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			for which: String in ["equip", "cash"]:
				if tab_rect(which).has_point(local):
					if page != which:
						UiArt.play_sound(UiArt.SND_CLICK)
					set_page(which)
					return
			if page != "equip":
				var arrows := pager_rects()
				for i in 2:
					if arrows[i].has_point(local) and owned_pages() > 1:
						UiArt.play_sound(UiArt.SND_CLICK)
						select_owned_page(owned_page + (1 if i == 1 else -1))
						return
	super._window_gui_input(event, local)


# --- drawing ---------------------------------------------------------------------------------------------------------------

func _draw() -> void:
	var bg := UiArt.frame(ART + ("pet" if page == "pet" else "backgrnd"))
	if bg != null:
		UiArt.blit(self, bg, Vector2.ZERO)
	else:
		_draw_plain_background()
	_draw_tabs()
	match page:
		"equip":
			_draw_worn()
		"cash":
			_draw_cash()
		"pet":
			_draw_pet()
	if page != "equip":
		_draw_panel()
	_draw_drag()


func _draw_plain_background() -> void:
	var art := art_size()
	draw_rect(Rect2(Vector2.ZERO, art), Color8(220, 228, 240))
	draw_rect(Rect2(Vector2.ZERO, art), Color8(99, 147, 183), false)
	MapleText.draw(self, Vector2(8, 4), "EQUIPMENT INVENTORY", MapleText.BLACK, MapleText.SMALL, true)
	match page:
		"equip":
			for slot: String in CELLS:
				var r := slot_rect(slot)
				draw_rect(r, CELL_FILL)
				MapleText.draw(self, r.position + Vector2(1, 0), String(LABELS[slot]), Color8(90, 110, 140), 8)
		"cash":
			for slot: String in CashCatalog.SLOTS:
				var r := cash_rect(slot)
				draw_rect(r, CELL_FILL)
				MapleText.draw(self, r.position + Vector2(1, 0), String(CASH_LABELS[slot]), Color8(90, 110, 140), 8)
		"pet":
			for id: int in PET_CELLS:
				draw_rect(Rect2(PET_CELLS[id], ICON_SLOT), CELL_FILL)
			for kind: String in PET_POTION_CELLS:
				draw_rect(Rect2(PET_POTION_CELLS[kind], ICON_SLOT), CELL_FILL)


## The Equip and Cash glyphs (the Item window's tab art; lit for the shown page); the PET EQUIP. button is a child.
func _draw_tabs() -> void:
	for which: String in ["equip", "cash"]:
		var on := page == which
		var glyph := UiArt.frame(TAB_ART + "%s/%d" % ["enabled" if on else "disabled", 0 if which == "equip" else 4])
		var r := tab_rect(which)
		if glyph != null:
			UiArt.blit(self, glyph, r.position + Vector2(3, floorf((r.size.y - glyph.region.size.y) * 0.5)))
		else:
			MapleText.draw(self, r.position + Vector2(1, 3), "Equip" if which == "equip" else "Cash",
				MapleText.BLACK if on else MapleText.GREY, 9, on)


func _draw_worn() -> void:
	if world == null:
		return
	for slot: String in Equipment.SLOTS:
		var id := worn_id(slot)
		if id == 0:
			continue
		var dim := _is_dragged({"kind": "worn", "slot": slot, "id": id})
		UiArt.blit_icon(self, UiArt.icon_or_fallback(InventoryModel.icon_path(id)), slot_rect(slot).position,
			ICON_SLOT, Color(1, 1, 1, 0.35) if dim else Color.WHITE)


func _draw_cash() -> void:
	if world == null:
		return
	var catalog := _cash_catalog()
	for slot: String in CashCatalog.SLOTS:
		var id := cash_id(slot)
		if id == 0:
			continue
		# The first slot an item fills shows it plainly, the other(s) of an overall or two-handed cover dimmed.
		var first := catalog.slots_for(id)[0] == slot
		var dim := _is_dragged({"kind": "cash_worn", "slot": slot, "id": id})
		var alpha := 1.0 if first else 0.4
		UiArt.blit_icon(self, UiArt.icon_or_fallback(CashShop.icon_path(catalog, id)), cash_rect(slot).position,
			ICON_SLOT, Color(1, 1, 1, alpha * (0.35 if dim else 1.0)))


func _draw_pet() -> void:
	if world == null:
		return
	var catalog := _cash_catalog()
	for c: Dictionary in pet_cells():
		var id := int(c.payload.id)
		var path := InventoryModel.icon_path(id) if String(c.payload.kind) == "potion" else CashShop.icon_path(catalog, id)
		UiArt.blit_icon(self, UiArt.icon_or_fallback(path), c.cell, ICON_SLOT)


## The owned-items panel: header, the page's items (outlined while worn / out), the pager and the hint.
func _draw_panel() -> void:
	var p := panel_rect()
	draw_rect(p, PANEL_FILL)
	draw_rect(p, PANEL_EDGE, false)
	var title := "Cash equipment" if page == "cash" else "Pets"
	MapleText.draw(self, p.position + Vector2(8, 5), title, MapleText.BLACK, MapleText.SMALL, true)
	var catalog := _cash_catalog()
	var shown := owned_items()
	var wearing: Array = world.worn_cash.values() if world != null else []
	for i in panel_capacity():
		var r := panel_cell(i)
		draw_rect(r, CELL_FILL)
		var id := panel_item(i)
		if id == 0:
			continue
		var on := (wearing.has(id) if page == "cash" else world.pet == id)
		UiArt.blit_icon(self, UiArt.icon_or_fallback(CashShop.icon_path(catalog, id)), r.position, ICON_SLOT)
		if on:
			draw_rect(r.grow(1.0), WORN_EDGE, false, 2.0)
	var hint := "Double-click to wear or take off" if page == "cash" else "Double-click: bring out / put away"
	if shown.is_empty():
		hint = "You own none yet. Buy some in the Cash Shop." if page == "cash" else "You own no pet yet."
	var lines := MapleText.wrap(hint, PANEL_W - 12.0, 8)
	for k in lines.size():
		MapleText.draw(self, Vector2(p.position.x + 6.0, p.end.y - 26.0 + 10.0 * k), lines[k], Color8(90, 110, 140), 8)
	if owned_pages() > 1:
		var arrows := pager_rects()
		MapleText.draw(self, arrows[0].position + Vector2(4, 0), "<", MapleText.BLACK if owned_page > 0 else MapleText.GREY, 9, true)
		MapleText.draw(self, arrows[1].position + Vector2(4, 0), ">",
			MapleText.BLACK if owned_page < owned_pages() - 1 else MapleText.GREY, 9, true)
		MapleText.draw_centered(self, p.position.x + 24.0, arrows[0].position.y, PANEL_W - 48.0,
			"%d / %d" % [owned_page + 1, owned_pages()], MapleText.BLACK, 9)
