class_name ShopWindow
extends InventoryWindow
## The v83 NPC shop window (#111): UI.wz/UIWindow.img/Shop `backgrnd`, two panels side by side. Left: the NPC (its
## `stand` animation, name, the Buy and Exit buttons) and its stock, five rows at a time (the scroll's icon, name and
## price). Right: the character (its look) with the meso total and the Sell button, and the inventory with the Item
## window's tabs (Equip, Use, Set-up, Etc, Cash) in five rows at a time. Both lists scroll with the wheel or the
## scrollbar's arrows. A row is selected with a click; Buy / Sell (or a double-click on a row) act on the selection.
##
##   ShopWindow.new(world, 1032103)   # world: the RunWorld whose character trades; npc_id: shops.json npcs[].id
##
## Buying asks "How many are you willing to buy?" (ShopQuantity), then RunWorld.buy_scroll; selling asks the quantity
## for scroll stacks and "Are you sure you want to sell it?" for equipment, then RunWorld.sell_scrolls / sell_item. A
## refusal opens a ShopNotice with the message and changes nothing. The Use tab lists the scroll stacks only (potions
## are never sold: tier C); worn equipment is never listed (it cannot be sold until it is taken off). Esc or Exit
## closes the window. Hovering a row shows the item's tooltip. Without the cache the window keeps its layout and draws
## plain panels. Tab shapes (#219): TabBuy / TabSell hold only the glyphs; the grey / pink shapes behind them are the
## Basic.img/Tab5 set drawn by TabStrip (see ItemWindow), the Buy panel's one tab always shown.

const ART := "UI.wz/UIWindow.img/Shop/"
const VSCR := "UI.wz/Basic.img/VScr5/"
## v83 Shop backgrnd size.
const WINDOW_SIZE := Vector2(463, 339)
## tier C (ours, measured on the v83 backgrnd): the right panel sits this far right of the left one.
const PANEL_DX := 230.0
const ROWS := 5
## tier C (measured): the first row, the step between rows, the icon slot, the text box (what `select` covers).
const ROW_Y := 127.0
const ROW_STEP := 40.0
const ICON_AT := Vector2(8, 1)
const BOX := Rect2(43, 0, 162, 35)
## tier C (measured): the row, including its icon slot.
const ROW := Rect2(6, 0, 199, 35)
## tier C (measured): the grey strip under the portrait box (the pink Buy label left, the tabs right).
const STRIP := Rect2(4, 91, 223, 25)
## tier C (ours): the tab shapes sit on the strip's bottom (19 rows over the red rule, Tab5's red base on backgrnd's):
## the right panel's five equal tabs span the whole pill (x 235-456), the Buy panel's one tab x 5-41.
const TAB_TOP := 97.0
const TAB_H := 19.0
const TAB_BOUNDS := [235.0, 279.0, 324.0, 368.0, 412.0, 457.0]
const BUY_TAB_BOUNDS := [5.0, 41.0]
const TABS := ["equip", "use", "setup", "etc", "cash"]
const TAB_NAMES := ["Equip", "Use", "Set-up", "Etc", "Cash"]
## tier C (ours, measured on the portrait boxes): where the NPC and the character stand (the shadows in the art), the
## buttons' recesses, the name lines and the meso field.
const NPC_FEET := Vector2(54, 76)
const CHAR_FEET := Vector2(285, 76)
const BUY_POS := Vector2(126, 32)
const EXIT_POS := Vector2(126, 56)
const SELL_POS := Vector2(356, 32)
const NAME_Y := 12.0
const NAME_X := Rect2(110, 0, 112, 0)
const MESO_FIELD := Rect2(361, 63, 90, 15)
## tier C (ours): the scrollbar sits in the white column right of the rows.
const SCROLL_AT := Vector2(208, 127)
const SCROLL_H := 195.0
## tier C (ours): the NPC's and the shop's default stack limit for one purchase (scrolls without slotMax).
const DEFAULT_SLOT_MAX := Scrolls.DEFAULT_SLOT_MAX
## tier C (ours): the success rate's colour on a scroll row.
const RATE_COLOR := Color8(51, 85, 136)
const BUY_QUESTION := "How many are you willing to buy?"
const SELL_QUESTION := "How many are you willing to sell?"
const SELL_CONFIRM := "Are you sure you want to sell it?"

## The NPC whose stock is shown (shops.json id).
var npc_id := 0
## The NPC's player-visible name (String.wz/Npc.img), the character's name above the right panel.
var npc_name := ""
var player_name := ""
## What the NPC sells this character (RunWorld.shop_stock).
var stock: Array = []
## The sell panel's shown tab (index into TABS).
var tab := 0
## Selected rows: an index into stock / into sell_cells() (-1 = none).
var buy_selected := -1
var sell_selected := -1
## First visible row of each list.
var buy_offset := 0
var sell_offset := 0
## The last refusal message shown (tests and the hub's notices read it).
var last_notice := ""

var _bt_buy: WzButton
var _bt_sell: WzButton
var _bt_exit: WzButton
var _npc_sprite: MapDrawList
var _avatar: AvatarRenderer
var _worn_shown := []


func _init(p_world: RunWorld = null, p_npc_id: int = 0) -> void:
	super._init(p_world)
	name = "ShopWindow"
	window_id = "shop"
	size = WINDOW_SIZE
	npc_id = p_npc_id
	npc_name = UiArt.text("String.wz/Npc.img/%d/name" % npc_id)
	if world != null:
		stock = world.shop_stock(npc_id)
	_bt_buy = _button("Buy", "BtBuy", "Buy", BUY_POS, begin_buy)
	_bt_exit = _button("Exit", "BtExit", "Exit", EXIT_POS, request_close)
	_bt_sell = _button("Sell", "BtSell", "Sell", SELL_POS, begin_sell)
	_build_actors()
	move_child(_tip, -1)
	_sync_buttons()


func _button(p_name: String, art: String, fallback: String, at: Vector2, action: Callable) -> WzButton:
	var b := WzButton.new(ART + art)
	b.name = p_name
	b.fallback_size = Vector2(80, 18)
	b.label = "" if b.has_art() else fallback
	b.position = at
	b.pressed.connect(action)
	add_child(b)
	return b


## The NPC's stand animation (facing the character) and the character's look standing on the shadows of the portraits.
func _build_actors() -> void:
	var anim := UiArt.anim("Npc.wz/%07d.img/stand" % npc_id)
	if anim != null and not anim.is_empty():
		_npc_sprite = MapDrawList.new()
		_npc_sprite.name = "Npc"
		_npc_sprite.animated = true
		_npc_sprite.position = NPC_FEET
		_npc_sprite.add(anim, Vector2.ZERO, true)
		add_child(_npc_sprite)
	if world != null:
		_avatar = AvatarRenderer.new()
		_avatar.name = "Character"
		_avatar.library = UiArt.lib()
		_avatar.set_look(_look())
		_avatar.position = CHAR_FEET
		_avatar.set_facing(-1)
		add_child(_avatar)
		_avatar.play("stand1")
		_worn_shown = Equipment.worn_ids(world.equipment.worn)


func _look() -> Dictionary:
	var look := AvatarRenderer.DEFAULT_LOOK.duplicate(true)
	look.merge(world.character_look, true)
	look.equips = Equipment.worn_ids(world.equipment.worn)
	return look


func _process(delta: float) -> void:
	if _npc_sprite != null:
		_npc_sprite.advance(delta)
	if _avatar != null:
		var worn := Equipment.worn_ids(world.equipment.worn)
		if worn != _worn_shown:
			_worn_shown = worn
			_avatar.set_look(_look())
		_avatar.advance(delta)


# --- lists -----------------------------------------------------------------------------------------------------------

## What the sell panel's shown tab holds, in slot order: Equip tab the spare equipment (never the worn items),
## Use tab the scroll stacks, nothing on the other tabs.
func sell_cells() -> Array:
	if world == null:
		return []
	match tab:
		0:
			var out := []
			for i in world.equipment.inventory.size():
				out.append({"kind": "inventory", "index": i, "id": int(world.equipment.inventory[i].id)})
			return out
		1:
			return InventoryModel.use_cells(world.scrolls)
	return []


## The stock row `i` as a payload ({} past the end).
func stock_cell(i: int) -> Dictionary:
	if i < 0 or i >= stock.size():
		return {}
	return {"kind": "stock", "index": i, "id": int(stock[i].id)}


## The sell cell `i` of the shown tab ({} past the end).
func sell_cell(i: int) -> Dictionary:
	var all := sell_cells()
	return all[i] if i >= 0 and i < all.size() else {}


## What a row shows first: the item's name, as the v83 shop lists it.
func row_name(payload: Dictionary) -> String:
	return item_name(int(payload.get("id", 0)))


## A scroll row's success rate ("100%"), shown right of its price because many v83 scroll names do not carry it ("" for
## equipment, and when the name already holds a percentage).
func row_rate(payload: Dictionary) -> String:
	var id := int(payload.get("id", 0))
	if not String(payload.get("kind", "")) in ["stock", "scroll"] or world == null or "%" in item_name(id):
		return ""
	var rate := int(world.scroll_info(id).get("success", 0))
	return "%d%%" % rate if rate > 0 else ""


## The mesos a row costs (stock) or pays (sell cells; per scroll for a stack).
func row_price(payload: Dictionary) -> int:
	var id := int(payload.get("id", 0))
	match String(payload.get("kind", "")):
		"stock":
			return int(stock[int(payload.index)].price)
		"inventory":
			return Shop.sale_price(info_of(id))
		"scroll":
			return Shop.sale_price(world.scroll_info(id) if world != null else {})
	return 0


## Selects the sell panel's tab `i` (clamped); the selection and scroll start over.
func select_tab(i: int) -> void:
	tab = clampi(i, 0, TABS.size() - 1)
	sell_selected = -1
	sell_offset = 0
	_hover = {}
	_place_tip()
	_sync_buttons()
	queue_redraw()


## The largest first-visible-row of a list of `count` rows.
static func max_offset(count: int) -> int:
	return maxi(0, count - ROWS)


## Scrolls panel 0 (stock) or 1 (inventory) by `delta` rows.
func scroll_panel(panel: int, delta: int) -> void:
	if panel == 0:
		buy_offset = clampi(buy_offset + delta, 0, max_offset(stock.size()))
	else:
		sell_offset = clampi(sell_offset + delta, 0, max_offset(sell_cells().size()))
	_hover = {}
	_place_tip()
	queue_redraw()


## The local rect of visible row `i` (0-4) of panel 0 or 1.
func row_rect(panel: int, i: int) -> Rect2:
	return Rect2(Vector2(ROW.position.x + PANEL_DX * panel, ROW_Y + ROW_STEP * i), ROW.size)


## The local rect of the scrollbar of panel 0 or 1.
func scrollbar_rect(panel: int) -> Rect2:
	return Rect2(SCROLL_AT + Vector2(PANEL_DX * panel, 0), Vector2(15, SCROLL_H))


## The local rect of sell tab `i`.
func tab_rect(i: int) -> Rect2:
	return TabStrip.tab_rect_at(TabStrip.bounds_of(TAB_BOUNDS), i, TAB_TOP, TAB_H)


## Which row is under local point `p`: [panel, absolute index], or [] for none.
func row_at(p: Vector2) -> Array:
	for panel in 2:
		for i in ROWS:
			if row_rect(panel, i).has_point(p):
				return [panel, (buy_offset if panel == 0 else sell_offset) + i]
	return []


func payload_at(p: Vector2) -> Dictionary:
	var hit := row_at(p)
	if hit.is_empty():
		return {}
	return stock_cell(int(hit[1])) if int(hit[0]) == 0 else sell_cell(int(hit[1]))


## The selected stock row ({} for none) and the selected inventory row.
func selected_stock() -> Dictionary:
	return stock_cell(buy_selected)


func selected_sale() -> Dictionary:
	return sell_cell(sell_selected)


# --- actions ---------------------------------------------------------------------------------------------------------

## A double-click on a row: buys from the stock, sells from the inventory.
func activate(payload: Dictionary) -> void:
	if String(payload.get("kind", "")) == "stock":
		buy_selected = int(payload.index)
		begin_buy()
	else:
		sell_selected = _sell_index_of(payload)
		begin_sell()


## Buy: asks how many of the selected scroll (nothing happens without a selection).
func begin_buy() -> void:
	var row := selected_stock()
	if row.is_empty() or world == null:
		return
	var slot_max := int(world.scroll_info(int(row.id)).get("slotMax", 0))
	_open_quantity(BUY_QUESTION, slot_max if slot_max > 0 else DEFAULT_SLOT_MAX, func(n: int) -> void:
		buy(int(row.index), n))


## Sell: a scroll stack asks how many, equipment asks "Are you sure you want to sell it?".
func begin_sell() -> void:
	var cell := selected_sale()
	if cell.is_empty() or world == null:
		return
	if String(cell.kind) == "scroll":
		_open_quantity(SELL_QUESTION, int(world.scrolls.get(str(int(cell.id)), 0)), func(n: int) -> void:
			sell_scrolls(int(cell.id), n))
		return
	var stack := get_parent() as WindowStack
	if stack == null:
		return
	var index := int(cell.index)
	if index < 0 or index >= world.equipment.inventory.size():
		return
	# The confirmation is not modal: remember the exact instance asked about, so a swapped-in copy is never sold.
	var confirm := DropConfirm.new(SELL_CONFIRM)
	confirm.confirmed.connect(sell_item.bind(index, world.equipment.inventory[index].duplicate(true)))
	stack.open(confirm)


## Buys `count` of stock row `index` (RunWorld.buy_scroll); "" or the refusal, whose message opens a notice.
func buy(index: int, count: int) -> String:
	if world == null or index < 0 or index >= stock.size():
		return "no_item"
	return _done("buy", world.buy_scroll(npc_id, int(stock[index].id), count))


## Sells the spare equipment at inventory `index` when it still equals `instance` (the confirmation is not modal).
func sell_item(index: int, instance: Dictionary) -> String:
	if world == null or index < 0 or index >= world.equipment.inventory.size() \
			or world.equipment.inventory[index] != instance:
		return "no_item"
	return _done("sell", world.sell_item(index))


## Sells `count` scrolls `id`.
func sell_scrolls(id: int, count: int) -> String:
	if world == null:
		return "no_item"
	return _done("sell", world.sell_scrolls(id, count))


## Reports a change: "" tells the host (item_action) and tidies the selection, a reason opens its message.
func _done(action: String, reason: String) -> String:
	if reason == "":
		apply(action, "")
		var cells := sell_cells().size()
		sell_offset = clampi(sell_offset, 0, max_offset(cells))
		if sell_selected >= cells:
			sell_selected = -1
		_sync_buttons()
	else:
		var text := message_for(reason)
		if text != "":
			show_notice(text)
	return reason


## Opens a ShopNotice with `text` over the window (the message of a refusal).
func show_notice(text: String) -> void:
	last_notice = text
	var stack := get_parent() as WindowStack
	if stack != null:
		stack.open(ShopNotice.new(text))


func _open_quantity(question: String, max_count: int, on_confirm: Callable) -> void:
	var stack := get_parent() as WindowStack
	if stack == null or max_count <= 0:
		return
	var q := ShopQuantity.new(question, max_count)
	q.confirmed.connect(on_confirm)
	stack.open(q)


func _sell_index_of(payload: Dictionary) -> int:
	var all := sell_cells()
	for i in all.size():
		if all[i] == payload:
			return i
	return -1


func _sync_buttons() -> void:
	if _bt_buy != null:
		_bt_buy.disabled = buy_selected < 0
		_bt_sell.disabled = sell_selected < 0


func tooltip_for(payload: Dictionary) -> Dictionary:
	match String(payload.get("kind", "")):
		"inventory":
			var index := int(payload.index)
			if world == null or index < 0 or index >= world.equipment.inventory.size():
				return {}
			return equip_tooltip(world.equipment.inventory[index])
		"stock", "scroll":
			return use_tooltip(int(payload.id))
	return {}


## The meso line's text.
func meso_text() -> String:
	return InventoryModel.meso_text(world.mesos if world != null else 0)


# --- mouse -----------------------------------------------------------------------------------------------------------

func _window_gui_input(event: InputEvent, local: Vector2) -> void:
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		var panel := 0 if local.x < PANEL_DX else 1
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_panel(panel, -1)
			return
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_panel(panel, 1)
			return
		if mb.button_index == MOUSE_BUTTON_LEFT and _left_press(local):
			return
	super._window_gui_input(event, local)
	# A shop has no drags (a scroll dragged onto an open Equip window would be read): the base's press is forgotten.
	_pressed = {}


## A left press on a tab, a scrollbar arrow or a row (selects it; the double-click still reaches the base). True when
## a tab or the scrollbar took it.
func _left_press(local: Vector2) -> bool:
	for i in TABS.size():
		if tab_rect(i).has_point(local):
			if i != tab:
				UiArt.play_sound(UiArt.SND_CLICK)
			select_tab(i)
			return true
	for panel in 2:
		var bar := scrollbar_rect(panel)
		if bar.has_point(local):
			scroll_panel(panel, -1 if local.y < bar.position.y + bar.size.y * 0.5 else 1)
			return true
	var hit := row_at(local)
	if not hit.is_empty():
		if int(hit[0]) == 0:
			buy_selected = int(hit[1]) if int(hit[1]) < stock.size() else buy_selected
		elif int(hit[1]) < sell_cells().size():
			sell_selected = int(hit[1])
		_sync_buttons()
		queue_redraw()
	return false


# --- drawing ---------------------------------------------------------------------------------------------------------

func _draw() -> void:
	var bg := UiArt.frame(ART + "backgrnd")
	if bg != null:
		UiArt.blit(self, bg, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(220, 228, 240))
		PixelDraw.outline(self, Rect2(Vector2.ZERO, size), Color8(99, 147, 183))
		draw_rect(Rect2(PANEL_DX - 2.0, 0, 2, size.y), Color8(99, 147, 183))
		for panel in 2:
			draw_rect(Rect2(STRIP.position + Vector2(PANEL_DX * panel, 0), STRIP.size), Color8(200, 204, 212))
			for i in ROWS:
				var r := row_rect(panel, i)
				draw_rect(Rect2(r.position + ICON_AT - Vector2(2, 1), Vector2(36, 35)), Color8(222, 218, 204))
				draw_rect(Rect2(r.position + Vector2(BOX.position.x - ROW.position.x, 0), BOX.size), Color8(210, 222, 236))
		draw_rect(MESO_FIELD, Color.WHITE)
	_draw_header()
	_draw_rows(0, stock.size(), buy_offset, buy_selected, stock_cell)
	_draw_rows(1, sell_cells().size(), sell_offset, sell_selected, sell_cell)
	_draw_scrollbar(0, buy_offset, stock.size())
	_draw_scrollbar(1, sell_offset, sell_cells().size())


## Names, the Buy label and the tabs on the strips, the meso total.
func _draw_header() -> void:
	var buy_bounds := TabStrip.bounds_of(BUY_TAB_BOUNDS)
	TabStrip.draw_or_fallback(self, TabStrip.RED_BASE_SET, TAB_TOP, TAB_H, buy_bounds, 0)
	TabStrip.draw_or_fallback(self, TabStrip.RED_BASE_SET, TAB_TOP, TAB_H, TabStrip.bounds_of(TAB_BOUNDS), tab)
	var label := UiArt.frame(ART + "TabBuy/enabled/3")
	var buy_tab := TabStrip.tab_rect_at(buy_bounds, 0, TAB_TOP, TAB_H)
	if not TabStrip.blit_centred(self, label, buy_tab):
		MapleText.draw_centered(self, buy_tab.position.x, buy_tab.position.y + 3.0, buy_tab.size.x, "Buy", MapleText.BLACK,
			MapleText.SMALL, true)
	for i in TABS.size():
		var on := i == tab
		var glyph := UiArt.frame(ART + "TabSell/%s/%d" % ["enabled" if on else "disabled", i])
		var r := tab_rect(i)
		if not TabStrip.blit_centred(self, glyph, r):
			MapleText.draw_centered(self, r.position.x, r.position.y + 5.0, r.size.x, String(TAB_NAMES[i]),
				MapleText.BLACK if on else MapleText.GREY, MapleText.SMALL, on)
	MapleText.draw_centered(self, NAME_X.position.x, NAME_Y, NAME_X.size.x, npc_name, MapleText.BLACK, MapleText.SMALL, true)
	MapleText.draw_centered(self, NAME_X.position.x + PANEL_DX, NAME_Y, NAME_X.size.x, player_name, MapleText.BLACK,
		MapleText.SMALL, true)
	var text := meso_text()
	MapleText.draw(self, Vector2(MESO_FIELD.end.x - 3.0 - MapleText.width(text, MapleText.SMALL), MESO_FIELD.position.y + 1.0),
		text, MapleText.BLACK, MapleText.SMALL)


func _draw_rows(panel: int, count: int, offset: int, selected: int, cell_of: Callable) -> void:
	var select := UiArt.frame(ART + "select")
	var coin := UiArt.frame(ART + "meso")
	for i in ROWS:
		var index := offset + i
		if index >= count:
			break
		var payload: Dictionary = cell_of.call(index)
		if payload.is_empty():
			continue
		var r := row_rect(panel, i)
		var box := Vector2(r.position.x + BOX.position.x - ROW.position.x, r.position.y)
		if index == selected and select != null:
			UiArt.blit(self, select, box)
		elif index == selected:
			draw_rect(Rect2(box, BOX.size), Color(0.45, 0.62, 0.85, 0.5))
		UiArt.blit_icon(self, UiArt.icon_or_fallback(InventoryModel.icon_path(int(payload.id))),
			r.position + ICON_AT - Vector2(0, 1), ICON_SLOT)
		if payload.has("count"):
			_draw_count(r.position + ICON_AT + Vector2(1, 20), int(payload.count))
		var text := MapleText.ellipsize(row_name(payload), BOX.size.x - 12.0, MapleText.SMALL)
		MapleText.draw(self, box + Vector2(6, 2), text, MapleText.BLACK, MapleText.SMALL)
		var price := row_price(payload)
		var affordable := panel == 1 or (world != null and world.mesos >= price)
		if coin != null:
			UiArt.blit(self, coin, box + Vector2(6, 21))
		MapleText.draw(self, box + Vector2(22, 20), InventoryModel.meso_text(price),
			MapleText.BLACK if affordable else MapleText.NPC_RED, MapleText.SMALL)
		var rate := row_rate(payload)
		if rate != "":
			MapleText.draw(self, box + Vector2(BOX.size.x - 6.0 - MapleText.width(rate, MapleText.SMALL), 20), rate,
				RATE_COLOR, MapleText.SMALL)


func _draw_scrollbar(panel: int, offset: int, count: int) -> void:
	var base := UiArt.frame(VSCR + "enabled/base")
	var top := max_offset(count)
	var prev := UiArt.frame(VSCR + ("enabled/prev0" if offset > 0 else "disabled/prev"))
	var next := UiArt.frame(VSCR + ("enabled/next0" if offset < top else "disabled/next"))
	var thumb := UiArt.frame(VSCR + "enabled/thumb0")
	if base == null or prev == null or next == null:
		return
	var at := scrollbar_rect(panel).position
	var y := at.y + prev.region.size.y
	var bottom := at.y + SCROLL_H - next.region.size.y
	UiArt.blit_part(self, base, Rect2(Vector2.ZERO, base.region.size), Vector2(at.x, y),
		Vector2(base.region.size.x, bottom - y))
	UiArt.blit(self, prev, at)
	UiArt.blit(self, next, Vector2(at.x, bottom))
	if thumb != null and top > 0:
		var span := bottom - y - thumb.region.size.y
		UiArt.blit(self, thumb, Vector2(at.x, y + roundf(span * offset / float(top))))
