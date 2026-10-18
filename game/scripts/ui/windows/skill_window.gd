class_name SkillWindow
extends UiWindow
## The v83 Skill window (hotkey K, or Menu -> Skill; #86): UI.wz/UIWindow.img/Skill `backgrnd` (SKILL INVENTORY) with
## one tab per job on the character's path (the v83 tab glyphs: the Beginner mark, I, II) and a star tab of job-neutral
## cards, the job's skill book (icon and v83 book name), and the skill rows (`skill1` learned / `skill0` not, icon or
## `iconDisabled`, name, level / max), four at a time with a `Basic.img/VScr5` scrollbar. Read-only: there is no SP
## to spend, so BtSpUp is never shown. All content comes from a SkillWindowModel.
##
##   SkillWindow.new(model)   # model: SkillWindowModel (RunScene.skill_window_model())
##
## Tooltips (SkillTooltip) show the hovered row's skill, or the row selected with the keyboard. Keys (RunScene routes
## them here through handle_key while the window is on top): Up / Down move the selection, Left / Right switch tabs,
## 1-n pick tab n. The mouse picks tabs, hovers rows and scrolls with the wheel or the scrollbar arrows. Without the
## cache the window keeps its size and draws plain panels.

const ART := "UI.wz/UIWindow.img/Skill/"
const CLOSE := "UI.wz/UIWindow.img/BtUIClose"
const VSCR := "UI.wz/Basic.img/VScr5/"
## v83 Skill backgrnd size.
const WINDOW_SIZE := Vector2(175, 289)
## tier C (ours, measured on the v83 art): the tab strip cells, the skill book box (icon slot, banner text), the rows
## (top-left of the first, the step between rows, how many fit), the scrollbar, the SP box and the close button.
const TAB_ORIGIN := Vector2(8, 24)
const TAB_SIZE := Vector2(27, 17)
const TAB_STEP := 28.0
const BOOK_ICON := Vector2(9, 53)
const BOOK_TEXT := Vector2(47, 64)
const BOOK_TEXT_W := 118.0
const ROW_ORIGIN := Vector2(11, 95)
const ROW_SIZE := Vector2(141, 35)
const ROW_STEP := 40.0
const VISIBLE_ROWS := 4
const SCROLL_POS := Vector2(155, 95)
const SCROLL_H := 155.0
const SP_BOX := Rect2(83, 265, 30, 15)
const CLOSE_BUTTON_POS := Vector2(134, 266)
## tier C (ours): the star tab's glyph colours (v83 has no such tab).
const STAR_ON := Color8(255, 204, 0)
const STAR_OFF := Color8(170, 160, 120)

## What the window shows.
var model: SkillWindowModel
## The shown tab (index into model.tabs).
var tab := 0
## The keyboard-selected row of the shown tab (-1: none).
var selected := -1
## The first row shown.
var scroll := 0

var _hover := -1
var _seen_family := ""
var _mouse := Vector2.ZERO
var _tip: SkillTooltip
var _bt_close: WzButton


func _init(p_model: SkillWindowModel = null) -> void:
	super._init()
	name = "SkillWindow"
	window_id = "skill"
	size = WINDOW_SIZE
	model = p_model
	# Opens on the current job's tab (the last job tab).
	tab = maxi(0, _tabs().size() - 2)
	_tip = SkillTooltip.new()
	add_child(_tip)
	_bt_close = WzButton.new(CLOSE)
	_bt_close.name = "Close"
	_bt_close.fallback_size = Vector2(32, 15)
	_bt_close.label = "" if _bt_close.has_art() else "X"
	_bt_close.position = CLOSE_BUTTON_POS
	_bt_close.pressed.connect(request_close)
	add_child(_bt_close)


## Shows tab `i` (clamped), without a selection and scrolled to the top.
func select_tab(i: int) -> void:
	tab = clampi(i, 0, maxi(0, _tabs().size() - 1))
	selected = -1
	_hover = -1
	scroll = 0
	_refresh()


## The rows of the shown tab.
func rows() -> Array:
	var t := _tabs()
	return t[tab].rows if tab < t.size() else []


## The tooltip data shown now: the hovered row's, else the keyboard-selected row's; {} when none.
func tooltip() -> Dictionary:
	var i := _hover if _hover >= 0 else selected
	var list := rows()
	if i < 0 or i >= list.size() or model == null:
		return {}
	var row: Dictionary = list[i]
	return model.skill_tooltip(String(row.key)) if row.has("key") else model.card_tooltip(String(row.id))


## Keyboard navigation (see the class doc); true when the key was used.
func handle_key(event: InputEvent) -> bool:
	var k := event as InputEventKey
	if k == null or not k.pressed:
		return false
	var code := k.keycode if k.keycode != KEY_NONE else k.physical_keycode
	match code:
		KEY_LEFT:
			if tab > 0:
				select_tab(tab - 1)
			return true
		KEY_RIGHT:
			if tab < _tabs().size() - 1:
				select_tab(tab + 1)
			return true
		KEY_UP, KEY_DOWN:
			var n := rows().size()
			_hover = -1
			if n > 0:
				selected = 0 if selected < 0 else clampi(selected + (1 if code == KEY_DOWN else -1), 0, n - 1)
				scroll = clampi(scroll, selected - VISIBLE_ROWS + 1, selected)
			_refresh()
			return true
	if code >= KEY_1 and code <= KEY_9:
		var i := int(code - KEY_1)
		if i >= _tabs().size():
			return false
		select_tab(i)
		return true
	return false


## The local rect of tab `i` in the tab strip.
func tab_rect(i: int) -> Rect2:
	return Rect2(TAB_ORIGIN + Vector2(TAB_STEP * i, 0), TAB_SIZE)


## The local rect of shown row `i` (0 = the top row on screen).
func row_rect(i: int) -> Rect2:
	return Rect2(ROW_ORIGIN + Vector2(0, ROW_STEP * i), ROW_SIZE)


func _tabs() -> Array[Dictionary]:
	return model.tabs if model != null else ([] as Array[Dictionary])


func _max_scroll() -> int:
	return maxi(0, rows().size() - VISIBLE_ROWS)


func _scroll_by(d: int) -> void:
	scroll = clampi(scroll + d, 0, _max_scroll())
	_hover = -1
	_refresh()


func _window_gui_input(event: InputEvent, local: Vector2) -> void:
	_mouse = local
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed:
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_by(-1)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_by(1)
				return
			MOUSE_BUTTON_LEFT:
				for i in _tabs().size():
					if tab_rect(i).has_point(local):
						select_tab(i)
						return
				if Rect2(SCROLL_POS, Vector2(15, 13)).has_point(local):
					_scroll_by(-1)
					return
				if Rect2(SCROLL_POS + Vector2(0, SCROLL_H - 13.0), Vector2(15, 13)).has_point(local):
					_scroll_by(1)
					return
	if event is InputEventMouseMotion or mb != null:
		var h := -1
		for i in VISIBLE_ROWS:
			if row_rect(i).has_point(local) and scroll + i < rows().size():
				h = scroll + i
		if h != _hover:
			_hover = h
			_refresh()
		elif _hover >= 0:
			_place_tip()


func _process(_delta: float) -> void:
	# The held weapon can change while the window is open (Equip window): redraw the greyed rows.
	if model != null and model.held_family.is_valid():
		var family := String(model.held_family.call())
		if family != _seen_family:
			_seen_family = family
			_refresh()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hover >= 0:
		_hover = -1
		_refresh()


func _refresh() -> void:
	_place_tip()
	queue_redraw()


func _place_tip() -> void:
	if _tip == null:
		return
	var d := tooltip()
	if d.is_empty():
		_tip.show_data({}, Vector2.ZERO)
		return
	# The tooltip stays above the status bar.
	var view := _view_size() - Vector2(0, HudWidget.BAR_H)
	var anchor: Vector2
	if _hover >= 0:
		anchor = position + _mouse + Vector2(18, 14)
	else:
		var r := row_rect(selected - scroll)
		anchor = position + Vector2(size.x + 4.0, r.position.y)
		if anchor.x + SkillTooltip.WIDTH > view.x:
			anchor.x = position.x - SkillTooltip.WIDTH - 4.0
	_tip.show_data(d, anchor, view)


func _draw() -> void:
	var bg := UiArt.frame(ART + "backgrnd")
	if bg != null:
		UiArt.blit(self, bg, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(220, 228, 240))
		draw_rect(Rect2(Vector2.ZERO, size), Color8(99, 147, 183), false)
		MapleText.draw(self, Vector2(8, 4), "SKILL INVENTORY", MapleText.BLACK, MapleText.SMALL, true)
	_draw_tabs()
	_draw_book()
	_draw_rows()
	_draw_scrollbar()
	MapleText.draw_centered(self, SP_BOX.position.x, SP_BOX.position.y + 1.0, SP_BOX.size.x, "0", MapleText.BLACK,
		MapleText.SMALL)


func _draw_tabs() -> void:
	var tabs := _tabs()
	for i in tabs.size():
		var r := tab_rect(i)
		var on := i == tab
		if on:
			draw_rect(r, Color(1, 1, 1))
			draw_rect(r, Color8(153, 153, 153), false)
		if String(tabs[i].kind) == SkillWindowModel.STAR:
			_draw_star(r.get_center(), 6.5, STAR_ON if on else STAR_OFF)
			continue
		var glyph := UiArt.frame(ART + "Tab/%s/%d" % ["enabled" if on else "disabled", int(tabs[i].tier)])
		if glyph != null:
			UiArt.blit(self, glyph, (r.get_center() - glyph.region.size * 0.5).floor())
		else:
			MapleText.draw_centered(self, r.position.x, r.position.y + 2.0, r.size.x, str(int(tabs[i].tier)),
				MapleText.BLACK, MapleText.SMALL, on)


## A five-pointed star (the star tab's glyph and book icon).
func _draw_star(c: Vector2, radius: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var a := -PI * 0.5 + PI * k / 5.0
		pts.append(c + Vector2(cos(a), sin(a)) * (radius if k % 2 == 0 else radius * 0.45))
	draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, col.darkened(0.45), 1.0)


func _draw_book() -> void:
	var tabs := _tabs()
	if tab >= tabs.size():
		return
	var t: Dictionary = tabs[tab]
	var slot := Rect2(BOOK_ICON, Vector2(32, 32))
	if String(t.kind) == SkillWindowModel.STAR:
		draw_rect(slot, Color8(238, 238, 238))
		_draw_star(slot.get_center(), 13.0, STAR_ON)
	else:
		var icon := UiArt.frame(String(t.book_icon))
		if icon != null:
			draw_rect(slot, Color8(238, 238, 238))
			UiArt.blit_icon(self, icon, BOOK_ICON)
	var title := String(t.book_name) if String(t.book_name) != "" else String(t.name)
	MapleText.draw(self, BOOK_TEXT, MapleText.ellipsize(title, BOOK_TEXT_W, MapleText.SMALL, true), MapleText.WHITE,
		MapleText.SMALL, true)


func _draw_rows() -> void:
	var list := rows()
	var line := UiArt.frame(ART + "line")
	for i in VISIBLE_ROWS:
		var idx := scroll + i
		if idx >= list.size():
			break
		var row: Dictionary = list[idx]
		var r := row_rect(i)
		# A skill the held weapon cannot use (#156) is drawn like an unlearned one: the v83 skill0 plate, iconDisabled.
		var learned := bool(row.get("learned", true)) and (not row.has("key") or model.usable(String(row.key)))
		var plate := UiArt.frame(ART + ("skill1" if learned else "skill0"))
		if plate != null:
			UiArt.blit(self, plate, r.position)
		else:
			draw_rect(r, Color8(204, 221, 238) if learned else Color8(238, 238, 238))
		if idx == selected or idx == _hover:
			# tier C (ours): v83 marks no row; the keyboard needs a visible selection.
			draw_rect(Rect2(r.position + Vector2(36, 0), r.size - Vector2(36, 0)), Color(1.0, 0.6, 0.0, 0.18))
			draw_rect(r.grow(-0.5), Color8(255, 153, 0), false, 1.0)
		# An unlearned skill uses its v83 iconDisabled; without one its icon is greyed.
		var icon: SpriteFrame = null if learned else UiArt.frame(String(row.get("icon_disabled", "")))
		var tint := Color.WHITE
		if icon == null:
			icon = UiArt.icon_or_fallback(String(row.get("icon", "")))
			tint = Color.WHITE if learned else Color(0.55, 0.55, 0.55)
		UiArt.blit_icon(self, icon, r.position + Vector2(2, 2), Vector2(32, 32), tint)
		var ink := MapleText.BLACK if learned else MapleText.GREY
		var tx := r.position.x + 40.0
		MapleText.draw(self, Vector2(tx, r.position.y + 3.0),
			MapleText.ellipsize(String(row.name), ROW_SIZE.x - 44.0, MapleText.SMALL), ink, MapleText.SMALL)
		var lv := "%d / %d" % [int(row.level), int(row.max_level)] if row.has("level") \
			else "%d / %d" % [int(row.rank), int(row.max_rank)]
		MapleText.draw(self, Vector2(tx, r.position.y + 20.0), lv, ink, MapleText.SMALL)
		if line != null and i < VISIBLE_ROWS - 1 and idx < list.size() - 1:
			UiArt.blit(self, line, r.position + Vector2(0, ROW_STEP - 3.0))


func _draw_scrollbar() -> void:
	var base := UiArt.frame(VSCR + "enabled/base")
	var prev := UiArt.frame(VSCR + ("enabled/prev0" if scroll > 0 else "disabled/prev"))
	var next := UiArt.frame(VSCR + ("enabled/next0" if scroll < _max_scroll() else "disabled/next"))
	var thumb := UiArt.frame(VSCR + "enabled/thumb0")
	if base == null or prev == null or next == null:
		return
	var y := SCROLL_POS.y + prev.region.size.y
	var bottom := SCROLL_POS.y + SCROLL_H - next.region.size.y
	UiArt.blit_part(self, base, Rect2(Vector2.ZERO, base.region.size), Vector2(SCROLL_POS.x, y),
		Vector2(base.region.size.x, bottom - y))
	UiArt.blit(self, prev, SCROLL_POS)
	UiArt.blit(self, next, Vector2(SCROLL_POS.x, bottom))
	if thumb != null and _max_scroll() > 0:
		var span := bottom - y - thumb.region.size.y
		UiArt.blit(self, thumb, Vector2(SCROLL_POS.x, y + roundf(span * scroll / float(_max_scroll()))))
