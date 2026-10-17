extends Control
## The v83 Cash Shop (spec #34 #118; UI.wz/CashShop.img, an 800x600 screen centred in the view) for the current
## character: Preview + character box on the left, the Cash Inventory (owned items, read-only) below it, the
## EQUIP./PET tabs with their sub-tab strip and a page of ten item cards in the middle, the NX balance and EXIT at the
## bottom. Layout numbers are measured from original v83 art and 2009 captures (private research: cashshop-refs/layout.md);
## "tier A" below means a WZ canvas position, "tier B" a measurement from period captures (+-3 px).
##
## Left out on purpose (out of scope of #118): MAIN/EVENT/USE/SET-UP/ETC./PACKAGE/WISH LIST tabs (drawn inert), GIFT and
## RESERVE, Search Item, Best Item contents, Charge/Check Cash/Code, the Item Inventory (drawn empty) and extra slots.
## BUY EQUIPPED ITEM stays disabled: items are bought one card at a time through the confirm dialog.
##
## Flow (SceneFlow.goto_cash_shop) supplies the character snapshot and the origin screen; Leave (EXIT or Esc) returns
## there. Buying is CashShop.buy on the flow's SaveData: confirm dialog, then NX deducted, item owned, saved at once.
## Public surface for tests and the flow driver: select_tab, select_sub, select_page, page_ids, listing_ids, owned_ids,
## preview/reset_preview/strip_preview, request_buy/confirm_buy/cancel_buy, dismiss_notice, lock_text, leave.

const CS := "UI.wz/CashShop.img/"
const STAGE := Vector2(800, 600) # tier A: Base/backgrnd canvas size.
const NAVY := Color8(0, 34, 85) # tier A: the colour outside the silver panels of Base/backgrnd.
## Tab strip image (508x78 per selected tab) and the click rectangles of the two live tabs (tier B).
const TAB_AT := Vector2(274, 17)
const TAB_FILES := {"equip": 3, "pet": 7}
const TAB_RECTS := {"equip": Rect2(382, 30, 46, 36), "pet": Rect2(602, 30, 50, 36)}
## Sub-tab strip text (tier B): first item left edge, text top, band height and separator.
const SUB_X := 281.0
const SUB_Y := 75.0
const SUB_BAND := Rect2(275, 73, 505, 20)
const SUB_GAP := 5.0
## Item cards: 2 columns x 5 rows of CSList/Base (tier A: 200x80, positions from the background's card edges).
const CARD_ORIGIN := Vector2(277, 97)
const CARD_PITCH := Vector2(206, 81)
const CARD_SIZE := Vector2(200, 80)
const PAGE_SIZE := 10
const ICON_WELL := Vector2(5, 5) # tier A: the white 64x64 well in the card.
const NAME_AT := Vector2(78, 9) # tier B
const PRICE_AT := Vector2(78, 33) # tier B
const BUY_AT := Vector2(78, 53) # tier B
const LOCK_AT := Vector2(78, 50) # tier C: the reason replaces the BUY button of a locked card.
const PAGES_Y := 507.0 # tier B
const PAGES_CENTER := 480.0
## Left column.
const PREVIEW_BOX := Rect2(22, 38, 218, 168) # tier A (white area of the background)
const PREVIEW_FEET := Vector2(100, 150) # tier C: where the avatar stands inside the box
const AVATAR_BUTTONS := {"buy": Vector2(17, 237), "default": Vector2(103, 237), "takeoff": Vector2(188, 237)} # tier A
const ID_VALUE_AT := Vector2(122, 270) # tier B
const INV_ORIGIN := Vector2(18, 347) # tier A: Cash Inventory slots 6 x 2, pitch 35 x 36
const INV_PITCH := Vector2(35, 36)
const INV_COLS := 6
const INV_ROWS := 2
const INV_SCROLL := Rect2(228, 347, 13, 70) # tier A: the scrollbar column of the background
## Bottom: NX balance (right edge of the number) and EXIT.
const NX_RIGHT := 475.0
const NX_Y := 542.0
const EXIT_AT := Vector2(632, 537) # tier B
## Buy dialog (CSNotice/4: 266x189 stacked from five parts) centred on the stage (tier B).
const DIALOG_PARTS := [21, 40, 5, 19, 104]
const DIALOG_AT := Vector2(267, 211)
const NOTICE_AT := Vector2(268, 234)

## Colours (tier C, matched to the captures): card text black, sub-tab text white / pale.
const INK := Color(0, 0, 0)
const SUB_ON := Color(1, 1, 1)
const SUB_OFF := Color8(255, 232, 214)
const LOCK_RED := Color8(204, 0, 0)

## The character shopping (Flow's saved snapshot) and the screen Leave returns to.
var snapshot: Dictionary = {}
var flow: SceneFlow
var origin := "stage_select"
## Current tab ("equip" | "pet"), sub-tab name and 0-based page.
var tab_key := "equip"
var sub := "Hat"
var page := 0
## The preview avatar's cash equipment ({slot: id}); the character's own worn cash until something is tried on.
var preview_cash: Dictionary = {}
## Item awaiting confirmation (0 = no dialog) and the notice text shown ("" = none).
var pending_id := 0
var notice_text := ""
var stage: Control
var avatar: AvatarRenderer
var exit_button: WzButton
var default_button: WzButton
var takeoff_button: WzButton
var buy_avatar_button: WzButton
var buy_buttons: Array[WzButton] = []
var ok_button: WzButton
var cancel_button: WzButton
var notice_ok_button: WzButton

var _data: Dictionary = {}
var _catalog: CashCatalog
var _lib: AssetLibrary
var _preview_box: Control
var _tip: Control
var _dialog: Control
var _notice: Control
var _hover := -1
var _inv_row := 0
var _worn_cash: Dictionary = {}
var _names: Dictionary = {}


## Sets the shopping character, the owning flow and the screen Leave returns to, before entering the tree.
func configure(p_snapshot: Dictionary, p_flow: SceneFlow, p_origin: String = "stage_select") -> void:
	snapshot = p_snapshot.duplicate(true)
	flow = p_flow
	origin = p_origin


func _ready() -> void:
	if flow == null:
		flow = get_node_or_null("/root/Flow") as SceneFlow
	_data = DataRepo.load_all()
	_catalog = CashCatalog.from_data(_data)
	_lib = UiArt.lib()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var navy := ColorRect.new()
	navy.color = NAVY
	navy.set_anchors_preset(Control.PRESET_FULL_RECT)
	navy.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(navy)
	stage = Control.new()
	stage.name = "Stage"
	stage.size = STAGE
	stage.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.draw.connect(_draw_stage)
	stage.gui_input.connect(_on_stage_input)
	stage.mouse_exited.connect(_on_stage_exit)
	add_child(stage)
	_build_preview()
	_build_buttons()
	_build_overlays()
	_worn_cash = DataRepo.worn_cash(snapshot.get("character", {}), _data, _owned())
	preview_cash = _worn_cash.duplicate()
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()
	var sfx := get_node_or_null("/root/Sfx") as AudioService
	if sfx != null:
		sfx.play_bgm("Sound.wz/BgmUI.img/WCSelect") # tier C: the shop shares the menu music


# --- public surface -------------------------------------------------------------------------------

## Switches to a tab ("equip" or "pet") on its first sub-tab and page.
func select_tab(key: String) -> void:
	for tab: Dictionary in CashShop.tabs():
		if tab.key == key:
			tab_key = key
			sub = String(tab.subs[0])
			page = 0
			_refresh()
			return


## Shows a sub-tab of the current tab (first page); unknown names are ignored.
func select_sub(name_: String) -> void:
	if name_ in _subs():
		sub = name_
		page = 0
		_refresh()


## Shows page `n` (0-based, clamped) of the current listing.
func select_page(n: int) -> void:
	page = clampi(n, 0, page_count() - 1)
	_refresh()


## Every unowned item on the current sub-tab.
func listing_ids() -> Array:
	return CashShop.listing(_catalog, _owned(), tab_key, sub)


## The (up to ten) items of the current page, in card order.
func page_ids() -> Array:
	var all := listing_ids()
	var from := page * PAGE_SIZE
	return all.slice(from, mini(all.size(), from + PAGE_SIZE))


## Number of pages of the current listing (at least 1).
func page_count() -> int:
	return maxi(1, ceili(float(listing_ids().size()) / PAGE_SIZE))


## The account's owned item ids in purchase order (the read-only Cash Inventory).
func owned_ids() -> Array:
	return _owned()


## The NX balance.
func nx() -> int:
	return int(_account().nx)


## Why `id` is locked, as one line ("Needs Wing Boots, Binocular and a pet."); "" when it can be bought.
func lock_text(id: int) -> String:
	var reasons := CashShop.lock_reasons(_catalog, _owned(), id, _name_of)
	if reasons.is_empty():
		return ""
	var needs := PackedStringArray()
	for reason in reasons:
		needs.append(reason.trim_prefix("Needs ").trim_suffix("."))
	if needs.size() == 1:
		return "Needs %s." % needs[0]
	return "Needs %s and %s." % [", ".join(needs.slice(0, needs.size() - 1)), needs[needs.size() - 1]]


## Tries an equipment item on the preview avatar (nothing is worn or bought).
func preview(id: int) -> void:
	preview_cash = CashShop.try_on(_catalog, preview_cash, id)
	_update_avatar()


## RETURN TO DEFAULT: the preview wears only what the character wears.
func reset_preview() -> void:
	preview_cash = _worn_cash.duplicate()
	_update_avatar()


## REMOVE ALL: the preview shows the character without any cash equipment.
func strip_preview() -> void:
	preview_cash = {}
	_update_avatar()


## BUY: opens the confirm dialog for `id`, or the notice when it can't be bought (locked, owned).
func request_buy(id: int) -> void:
	if pending_id != 0 or notice_text != "":
		return
	var reason := CashShop.refusal(_account(), _catalog, id)
	if reason == "locked":
		return # the card already says why, and its BUY button is not shown
	if reason != "":
		_show_notice(CashShop.message(reason))
		_refresh()
		return
	pending_id = id
	_refresh()


## OK in the dialog: buys the item (saved at once); a refusal shows its notice instead.
func confirm_buy() -> void:
	if pending_id == 0 or flow == null:
		return
	var id := pending_id
	pending_id = 0
	var reason := CashShop.buy(flow.save_data(), _catalog, id)
	if reason != "":
		_show_notice(CashShop.message(reason))
	_refresh()


## CANCEL in the dialog.
func cancel_buy() -> void:
	pending_id = 0
	_refresh()


## OK on a notice.
func dismiss_notice() -> void:
	notice_text = ""
	_refresh()


## EXIT: returns to the screen the shop was opened from.
func leave() -> void:
	if flow != null:
		flow.leave_cash_shop(origin)


## Card index (0-9) under a stage point, or -1.
func card_at(p: Vector2) -> int:
	var count := page_ids().size()
	for i in count:
		if card_rect(i).has_point(p):
			return i
	return -1


## Stage-space rectangle of card `i`.
func card_rect(i: int) -> Rect2:
	return Rect2(CARD_ORIGIN + Vector2(i % 2 * CARD_PITCH.x, int(i / 2) * CARD_PITCH.y), CARD_SIZE)


## Stage-space click rectangles of the current sub-tab strip, in order.
func sub_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var x := SUB_X
	for name_: String in _subs():
		var w := MapleText.width(name_, MapleText.SMALL, true)
		out.append(Rect2(x - 2.0, SUB_BAND.position.y, w + 4.0, SUB_BAND.size.y))
		x += w + SUB_GAP * 2.0 + MapleText.width("|", MapleText.SMALL)
	return out


## Stage-space click rectangles of the page numbers.
func page_rects() -> Array[Rect2]:
	var widths := PackedFloat32Array()
	var total := 0.0
	for n in page_count():
		widths.append(MapleText.width(str(n + 1), MapleText.SMALL, true))
		total += widths[n] + 8.0
	var out: Array[Rect2] = []
	var x := PAGES_CENTER - (total - 8.0) * 0.5
	for n in page_count():
		out.append(Rect2(x - 3.0, PAGES_Y - 2.0, widths[n] + 6.0, 16.0))
		x += widths[n] + 8.0
	return out


# --- construction ---------------------------------------------------------------------------------

func _build_preview() -> void:
	_preview_box = Control.new()
	_preview_box.name = "Preview"
	_preview_box.position = PREVIEW_BOX.position
	_preview_box.size = PREVIEW_BOX.size
	_preview_box.clip_contents = true
	_preview_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_preview_box.draw.connect(_draw_preview_box)
	stage.add_child(_preview_box)
	avatar = AvatarRenderer.new()
	avatar.library = _lib
	avatar.set_look(_look())
	avatar.position = PREVIEW_FEET
	_preview_box.add_child(avatar)
	avatar.set_facing(-1)
	avatar.play("stand1")


func _build_buttons() -> void:
	exit_button = _button(CS + "CSStatus/BtExit", EXIT_AT, Vector2(168, 49), "Exit")
	exit_button.pressed.connect(leave)
	buy_avatar_button = _button(CS + "CSChar/BtBuyAvatar", AVATAR_BUTTONS.buy, Vector2(83, 19), "Buy equipped item")
	buy_avatar_button.disabled = true
	default_button = _button(CS + "CSChar/BtDefaultAvatar", AVATAR_BUTTONS.default, Vector2(84, 19), "Return to default")
	default_button.pressed.connect(reset_preview)
	takeoff_button = _button(CS + "CSChar/BtTakeoffAvatar", AVATAR_BUTTONS.takeoff, Vector2(55, 19), "Remove all")
	takeoff_button.pressed.connect(strip_preview)
	for i in PAGE_SIZE:
		var b := _button(CS + "CSList/BtBuy", card_rect(i).position + BUY_AT, Vector2(37, 19), "Buy")
		b.name = "Buy%d" % i
		b.pressed.connect(_on_buy_pressed.bind(i))
		buy_buttons.append(b)


func _build_overlays() -> void:
	_tip = Control.new()
	_tip.name = "Tooltip"
	_tip.size = STAGE
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tip.draw.connect(_draw_tooltip)
	stage.add_child(_tip)
	_dialog = _overlay("BuyDialog", _draw_dialog)
	ok_button = _button(_basic("BtOK2"), DIALOG_AT + Vector2(104, 160), Vector2(47, 18), "OK", _dialog)
	ok_button.pressed.connect(confirm_buy)
	cancel_button = _button(_basic("BtCancel2"), DIALOG_AT + Vector2(156, 160), Vector2(47, 18), "Cancel", _dialog)
	cancel_button.pressed.connect(cancel_buy)
	_notice = _overlay("Notice", _draw_notice)
	notice_ok_button = _button(_basic("BtOK"), NOTICE_AT + Vector2(100, 92), Vector2(65, 24), "OK", _notice)
	notice_ok_button.pressed.connect(dismiss_notice)


static func _basic(name_: String) -> String:
	return "UI.wz/Basic.img/" + name_


func _overlay(node_name: String, drawer: Callable) -> Control:
	var c := Control.new()
	c.name = node_name
	c.size = STAGE
	c.mouse_filter = Control.MOUSE_FILTER_STOP # modal: nothing below reacts while it is up
	c.visible = false
	c.draw.connect(func() -> void: drawer.call(c))
	stage.add_child(c)
	return c


func _button(path: String, at: Vector2, fallback: Vector2, label: String, parent: Control = null) -> WzButton:
	var b := WzButton.new(path)
	b.fallback_size = fallback
	if not b.has_art():
		b.label = label
	b.position = at
	(parent if parent != null else stage).add_child(b)
	return b


func _layout() -> void:
	var view := get_viewport_rect().size
	stage.position = ((view - STAGE) * 0.5).floor()


# --- state ----------------------------------------------------------------------------------------

func _account() -> Dictionary:
	return flow.save_data().account if flow != null else Account.empty()


func _owned() -> Array:
	return _account().owned


func _subs() -> Array:
	for tab: Dictionary in CashShop.tabs():
		if tab.key == tab_key:
			return tab.subs
	return []


func _look() -> Dictionary:
	return DataRepo.character_look(snapshot.get("character", {}), _data, preview_cash)


func _update_avatar() -> void:
	if avatar != null:
		avatar.set_look(_look())
		avatar.play("stand1", true)
	if _preview_box != null:
		_preview_box.queue_redraw()


## The display name of an item (cached).
func _name_of(id: int) -> String:
	if not _names.has(id):
		var n := CashShop.item_name(_lib, _catalog, id)
		_names[id] = n if n != "" else str(id)
	return _names[id]


func _show_notice(text: String) -> void:
	notice_text = text


## Updates every widget that depends on the state, then redraws.
func _refresh() -> void:
	page = clampi(page, 0, page_count() - 1)
	var ids := page_ids()
	var owned := _owned()
	for i in PAGE_SIZE:
		buy_buttons[i].visible = i < ids.size() and _catalog.prerequisites_met(ids[i], owned)
	_dialog.visible = pending_id != 0
	_notice.visible = notice_text != ""
	_hover = -1
	stage.queue_redraw()
	_tip.queue_redraw()
	_dialog.queue_redraw()
	_notice.queue_redraw()
	_preview_box.queue_redraw()


# --- input ----------------------------------------------------------------------------------------

func _on_buy_pressed(i: int) -> void:
	var ids := page_ids()
	if i < ids.size():
		request_buy(ids[i])


func _on_stage_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var hover := card_at((event as InputEventMouseMotion).position)
		if hover != _hover:
			_hover = hover
			_tip.queue_redraw()
		_tip.set_meta("mouse", (event as InputEventMouseMotion).position)
		if _hover >= 0:
			_tip.queue_redraw()
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_on_click(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and INV_SCROLL.grow(60).has_point(mb.position):
			_scroll_inventory(-1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and INV_SCROLL.grow(60).has_point(mb.position):
			_scroll_inventory(1)


func _on_click(p: Vector2) -> void:
	for key: String in TAB_RECTS:
		if (TAB_RECTS[key] as Rect2).has_point(p):
			if key != tab_key:
				UiArt.play_sound(UiArt.SND_CLICK)
				select_tab(key)
			return
	var rects := sub_rects()
	for i in rects.size():
		if rects[i].has_point(p):
			UiArt.play_sound(UiArt.SND_CLICK)
			select_sub(String(_subs()[i]))
			return
	var pages := page_rects()
	for n in pages.size():
		if pages[n].has_point(p):
			UiArt.play_sound(UiArt.SND_CLICK)
			select_page(n)
			return
	var card := card_at(p)
	if card >= 0:
		preview(int(page_ids()[card]))


func _scroll_inventory(step: int) -> void:
	var rows := ceili(float(_owned().size()) / INV_COLS)
	_inv_row = clampi(_inv_row + step, 0, maxi(0, rows - INV_ROWS))
	stage.queue_redraw()


func _on_stage_exit() -> void:
	_hover = -1
	_tip.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	var used := true
	if notice_text != "":
		if MapleWindow.is_confirm(event) or MapleWindow.is_cancel(event):
			dismiss_notice()
		else:
			used = false
	elif pending_id != 0:
		if MapleWindow.is_confirm(event):
			confirm_buy()
		elif MapleWindow.is_cancel(event):
			cancel_buy()
		else:
			used = false
	elif MapleWindow.is_cancel(event):
		leave()
	else:
		used = false
	if used:
		get_viewport().set_input_as_handled()


# --- drawing --------------------------------------------------------------------------------------

func _draw_stage() -> void:
	UiArt.blit(stage, UiArt.frame(CS + "Base/backgrnd"), Vector2.ZERO)
	UiArt.blit(stage, UiArt.frame("%sCSTab/Tab/%d" % [CS, TAB_FILES[tab_key]]), TAB_AT)
	_draw_sub_strip()
	var ids := page_ids()
	for i in ids.size(): # empty slots stay bare background cards, as in the client's half-loaded EVENT frame
		_draw_card(i, int(ids[i]))
	_draw_pages()
	_draw_left_column()
	_draw_status()


func _draw_sub_strip() -> void:
	var x := SUB_X
	var subs := _subs()
	for i in subs.size():
		var name_: String = subs[i]
		var on := name_ == sub
		MapleText.draw(stage, Vector2(x, SUB_Y), name_, SUB_ON if on else SUB_OFF, MapleText.SMALL, on)
		x += MapleText.width(name_, MapleText.SMALL, true) + SUB_GAP
		if i < subs.size() - 1:
			MapleText.draw(stage, Vector2(x, SUB_Y), "|", SUB_OFF, MapleText.SMALL)
			x += MapleText.width("|", MapleText.SMALL) + SUB_GAP


func _draw_card(i: int, id: int) -> void:
	var r := card_rect(i)
	UiArt.blit(stage, UiArt.frame(CS + "CSList/Base"), r.position)
	_draw_icon(stage, id, r.position + ICON_WELL, 2.0)
	var text_w := r.size.x - NAME_AT.x - 6.0
	MapleText.draw(stage, r.position + NAME_AT, MapleText.ellipsize(_name_of(id), text_w, MapleText.SMALL),
		INK, MapleText.SMALL)
	MapleText.draw(stage, r.position + PRICE_AT, "%s NX" % SaveData._group(_catalog.price_of(id)), INK, MapleText.SMALL)
	var lock := lock_text(id)
	if lock != "":
		var y := LOCK_AT.y
		for line in MapleText.wrap(lock, text_w, MapleText.SMALL, true).slice(0, 2):
			MapleText.draw(stage, r.position + Vector2(LOCK_AT.x, y), line, LOCK_RED, MapleText.SMALL, true)
			y += MapleText.LINE_SMALL - 1.0


## Draws a catalog icon (32x32) with its top-left at `at`, enlarged by `scale` and centred in a 32*scale box.
func _draw_icon(ci: CanvasItem, id: int, at: Vector2, scale: float) -> void:
	var f := UiArt.icon_or_fallback(CashShop.icon_path(_catalog, id))
	if f == null:
		return
	var box := Vector2(32, 32) * scale
	var size := f.region.size * scale
	ci.draw_texture_rect_region(f.page, Rect2((at + ((box - size) * 0.5)).floor(), size), f.region)


func _draw_pages() -> void:
	var rects := page_rects()
	for n in rects.size():
		var on := n == page
		MapleText.draw(stage, Vector2(rects[n].position.x + 3.0, PAGES_Y), str(n + 1),
			SUB_ON if on else Color8(200, 215, 240), MapleText.SMALL, on)


func _draw_left_column() -> void:
	MapleText.draw(stage, ID_VALUE_AT, MapleText.ellipsize(String(snapshot.get("name", "")), 112.0, MapleText.SMALL),
		INK, MapleText.SMALL)
	var owned := _owned()
	var start := _inv_row * INV_COLS
	for slot in INV_COLS * INV_ROWS:
		var k := start + slot
		if k >= owned.size():
			break
		var at := INV_ORIGIN + Vector2(slot % INV_COLS * INV_PITCH.x, int(slot / INV_COLS) * INV_PITCH.y)
		UiArt.blit_icon(stage, UiArt.icon_or_fallback(CashShop.icon_path(_catalog, int(owned[k]))), at, Vector2(33, 33))
	var rows := ceili(float(owned.size()) / INV_COLS)
	if rows > INV_ROWS:
		var h := INV_SCROLL.size.y * INV_ROWS / rows
		var y := INV_SCROLL.position.y + (INV_SCROLL.size.y - h) * _inv_row / float(rows - INV_ROWS)
		stage.draw_rect(Rect2(INV_SCROLL.position.x + 2.0, y, INV_SCROLL.size.x - 4.0, h), Color8(120, 150, 200))


func _draw_status() -> void:
	var text := SaveData._group(nx())
	MapleText.draw(stage, Vector2(NX_RIGHT - MapleText.width(text, MapleText.SMALL, true), NX_Y), text, INK,
		MapleText.SMALL, true)


func _draw_preview_box() -> void:
	UiArt.blit(_preview_box, UiArt.frame(CS + "Base/Preview/0"), Vector2(2, 2))
	var name_text := String(snapshot.get("name", ""))
	var w := MapleText.width(name_text, NameTags.FONT_SIZE - 1)
	var box := Rect2(PREVIEW_FEET + Vector2(-floorf((w + 6.0) * 0.5), 3), Vector2(w + 6.0, 14))
	_preview_box.draw_rect(box, NameTags.BOX_COLOR)
	MapleText.draw(_preview_box, box.position + Vector2(3, 0), name_text, Color(1, 1, 1), NameTags.FONT_SIZE - 1)


func _draw_tooltip() -> void:
	if _hover < 0 or pending_id != 0 or notice_text != "":
		return
	var ids := page_ids()
	if _hover >= ids.size():
		return
	var id := int(ids[_hover])
	var lines: Array = [[_name_of(id), SUB_ON, true]]
	for line in MapleText.wrap(CashShop.item_desc(_lib, _catalog, id), 170.0, MapleText.SMALL):
		if line != "":
			lines.append([line, Color8(220, 230, 255), false])
	var lock := lock_text(id)
	if lock != "":
		lines.append([lock, Color8(255, 170, 170), true])
	lines.append(["%s NX" % SaveData._group(_catalog.price_of(id)), MapleText.YELLOW, true])
	var size := Vector2(184, 8.0 + lines.size() * MapleText.LINE_SMALL)
	var mouse: Vector2 = _tip.get_meta("mouse", card_rect(_hover).position)
	var at := (mouse + Vector2(14, 14)).clamp(Vector2.ZERO, STAGE - size)
	_tip.draw_rect(Rect2(at, size), Color8(10, 20, 70, 235))
	_tip.draw_rect(Rect2(at, size), Color8(120, 150, 220), false)
	for i in lines.size():
		MapleText.draw(_tip, at + Vector2(7, 4 + i * MapleText.LINE_SMALL), lines[i][0], lines[i][1], MapleText.SMALL,
			lines[i][2])


func _draw_dialog(ci: Control) -> void:
	var y := 0.0
	for i in DIALOG_PARTS.size():
		var f := UiArt.frame("%sCSNotice/4/%d" % [CS, i])
		UiArt.blit(ci, f, DIALOG_AT + Vector2(0, y))
		y += float(DIALOG_PARTS[i])
	if pending_id == 0:
		return
	# Item plate, name and price on the blue block, then the question; the three payment lines are part of the art.
	_draw_icon(ci, pending_id, DIALOG_AT + Vector2(17, 22), 1.0)
	MapleText.draw(ci, DIALOG_AT + Vector2(62, 24), MapleText.ellipsize(_name_of(pending_id), 190.0), SUB_ON,
		MapleText.SIZE, true)
	MapleText.draw(ci, DIALOG_AT + Vector2(62, 41), "%s NX" % SaveData._group(_catalog.price_of(pending_id)), SUB_ON,
		MapleText.SIZE)
	MapleText.draw(ci, DIALOG_AT + Vector2(16, 78), "Are you sure you want to buy this item?", SUB_ON, MapleText.SMALL)
	var tick := DIALOG_AT + Vector2(36, 136) # tier B: the red check of the NX CREDIT line (the only currency the game has)
	ci.draw_polyline(PackedVector2Array([tick + Vector2(0, 3), tick + Vector2(3, 6), tick + Vector2(8, -1)]),
		Color8(204, 0, 51), 2.0)


func _draw_notice(ci: Control) -> void:
	UiArt.blit(ci, UiArt.frame(_basic("Notice/backgrnd")), NOTICE_AT)
	var lines := MapleText.wrap(notice_text, 220.0, MapleText.SIZE, false)
	for i in lines.size():
		MapleText.draw_centered(ci, NOTICE_AT.x, NOTICE_AT.y + 30.0 + i * MapleText.LINE, 264.0, lines[i], INK,
			MapleText.SIZE)
