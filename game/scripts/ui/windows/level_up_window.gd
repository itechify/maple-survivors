class_name LevelUpWindow
extends MapleWindow
## The level-up upgrade choice (docs/ARCHITECTURE.md 4.4.2 `choice_pending`, GAME_DESIGN section 8).
##
## Art: the v83 skill-up notice UIWindow.img/SkillUp/backgrd ("You've gained a Level!" with the slime, snail and
## orange mushroom) is the window; its uniform rows 169-179 are repeated to grow the panel for the choices. The level
## goes into the notice's level box (Basic.img/LevelNo digits). When the focused card learns or levels a skill
## (skill_new, skill_rank) the skill's name goes into the "raised your ___ skill by a level." box; for any other card
## that sentence would be wrong, so its words ("BY REACHING", ", YOU HAVE" and the two lines below) are covered with
## the panel's own blank fill and the notice reads "LEVEL n". Each choice is a skill-window row (UIWindow.img/Skill/
## skill0, skill1 when focused, widened to the panel) with the card icon in the slot (UIWindow.img/IconBase/0 when the
## card has no icon or the icon is missing), the name, the rank (rank_text: "NEW", "Lv. 1 → 2", the skill's canonical
## level change "Skill Lv. 2 → 3" for skill_rank cards, "MAX" at the last rank), the key (Basic.img/ItemNo digit) and
## the description below.
##
## Input: 1/2/3 (choice_1..3) pick a card; Up/Down move the focus, Enter picks it; the mouse highlights and clicks.
## `card_chosen` is emitted at once when a card is picked (then the window fades out); a new open() during the fade
## (queued level-ups) restarts the window with the new cards.
##
##   win.open(cards, level)   # cards exactly as in the choice_pending event: {id, kind, name, desc, icon, rank,
##                            # max_rank, skill, skill_name, skill_level, skill_level_next}

## Emitted with the picked card's id.
signal card_chosen(card_id: String)

const ART := "UI.wz/UIWindow.img/SkillUp/backgrd"
const ROW := "UI.wz/UIWindow.img/Skill/skill0"
const ROW_FOCUS := "UI.wz/UIWindow.img/Skill/skill1"
const LEVEL_DIGITS := "UI.wz/Basic.img/LevelNo/"
const KEY_DIGITS := "UI.wz/Basic.img/ItemNo/"
## SkillUp/backgrd geometry (measured from the v83 canvas, 215x201): rows above TOP_H are the notice, rows
## [MID_Y, MID_Y + MID_H) are uniform and repeat, the rest is the bottom edge.
const ART_SIZE := Vector2(215, 201)
const TOP_H := 169.0
const MID_Y := 169.0
const MID_H := 11.0
const BOTTOM_H := 21.0
## The notice's level box and skill-name box.
const LEVEL_BOX := Rect2(116, 108, 27, 17)
const NAME_BOX := Rect2(85, 129, 98, 17)
## The notice sentence (measured from the v83 canvas): per band of art rows [y0, y1), the x ranges [x0, x1) covered
## when the focused card raises no skill - "BY REACHING " and ", YOU HAVE" around the level box, then the whole
## "RAISED YOUR [ ]" / "SKILL BY A LEVEL." lines. Column BLANK_X is plain panel fill in every one of those rows (the
## fill is a vertical gradient, so each covered row is painted with its own row's fill colour).
const SENTENCE_BANDS := [[105.0, 126.0, [Vector2(13, 82), Vector2(144, 202)]], [126.0, 164.0, [Vector2(13, 202)]]]
const BLANK_X := 14.0
## Card kinds whose skill the notice sentence names.
const SENTENCE_KINDS := ["skill_new", "skill_rank"]
## Choice rows inside the panel's inner fill (x 12..202).
const ROWS_TOP := 166.0
const ROW_X := 12.0
const ROW_W := 191.0
const ROW_H := 35.0
## skill0: icon slot width (incl. its 1 px gap) and a uniform column of the name area.
const ROW_SLOT_W := 36.0
const ROW_MID_X := 60.0
const DESC_LINE := 13.0
const DESC_MAX_LINES := 3
const BLOCK_GAP := 6.0

## The cards on offer.
var cards: Array = []
## The level shown in the notice.
var level := 0
## Index of the focused card (-1 = none).
var focus := -1

## Per card: {"row": Rect2 (panel-local row art), "block": Rect2 (row + description, the mouse target),
## "desc": PackedStringArray}.
var _blocks: Array[Dictionary] = []


func _init() -> void:
	super._init()
	name = "LevelUpWindow"
	panel_size = ART_SIZE


## Opens the window with the cards of a choice_pending event and the new level.
func open(p_cards: Array, p_level: int) -> void:
	cards = p_cards.duplicate(true)
	level = p_level
	focus = 0 if not cards.is_empty() else -1
	_build_layout()
	_show_window()


## Picks card `i`: emits card_chosen(id) and closes. False when closed or out of range.
func choose(i: int) -> bool:
	if not _open or i < 0 or i >= cards.size():
		return false
	var id := String((cards[i] as Dictionary).get("id", ""))
	focus = i
	panel.queue_redraw()
	UiArt.play_sound(UiArt.SND_CLICK)
	_hide_window()
	card_chosen.emit(id)
	return true


## Moves the focus to card `i` (clamped; plays the hover sound when it changes).
func set_focus(i: int) -> void:
	if cards.is_empty():
		return
	i = clampi(i, 0, cards.size() - 1)
	if i != focus:
		focus = i
		UiArt.play_sound(UiArt.SND_OVER)
		panel.queue_redraw()


## The mouse target of card `i` in window coordinates (empty when out of range).
func card_rect(i: int) -> Rect2:
	if i < 0 or i >= _blocks.size():
		return Rect2()
	var r: Rect2 = _blocks[i].block
	return Rect2(r.position + panel.position, r.size)


## Rank text of a card: a skill_rank card shows the skill's canonical level change ("Skill Lv. 2 → 3", from the card's
## skill_level / skill_level_next) since its own rank is not the level the skill reaches; other cards "NEW" for a
## first rank, "Lv. a → b" after; " MAX" at the card's last rank; "" for fillers.
static func rank_text(card: Dictionary) -> String:
	var kind := String(card.get("kind", ""))
	if kind == "filler":
		return ""
	var rank := int(card.get("rank", 1))
	var max_rank := int(card.get("max_rank", 0))
	var s := ""
	var lv := int(card.get("skill_level", 0))
	var lv_next := int(card.get("skill_level_next", 0))
	if kind == "skill_rank" and lv > 0 and lv_next > lv:
		s = "Skill Lv. %d → %d" % [lv, lv_next]
	elif rank <= 1:
		return "NEW"
	else:
		s = "Lv. %d → %d" % [rank - 1, rank]
	if max_rank > 1 and rank >= max_rank:
		s += "  MAX"
	return s


## True when the notice's "raised your ___ skill by a level." sentence fits card `card` (it learns or levels a skill).
static func names_a_skill(card: Dictionary) -> bool:
	return String(card.get("kind", "")) in SENTENCE_KINDS and String(card.get("skill", "")) != ""


## The name the notice's skill box shows for `card`: the skill's name (a rank card such as Energy Bolt +1 rank names Energy Bolt).
static func notice_name(card: Dictionary) -> String:
	var s := String(card.get("skill_name", ""))
	return s if s != "" else String(card.get("name", ""))


func handle_input(event: InputEvent) -> bool:
	if not _open:
		return false
	var d := MapleWindow.digit_of(event)
	if d >= 1 and d <= cards.size():
		choose(d - 1)
		return true
	var step := MapleWindow.vertical_step(event)
	if step != 0:
		set_focus((focus + step + cards.size()) % maxi(1, cards.size()) if focus >= 0 else 0)
		return true
	if MapleWindow.is_confirm(event):
		choose(focus)
		return true
	return event is InputEventKey and (event as InputEventKey).pressed


func _panel_gui_input(event: InputEvent, local: Vector2) -> void:
	var hit := -1
	for i in _blocks.size():
		if (_blocks[i].block as Rect2).has_point(local):
			hit = i
			break
	if event is InputEventMouseMotion:
		if hit >= 0:
			set_focus(hit)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and hit >= 0:
			choose(hit)


func _build_layout() -> void:
	_blocks.clear()
	var y := ROWS_TOP
	for c: Variant in cards:
		var card: Dictionary = c if c is Dictionary else {}
		var desc := MapleText.wrap(String(card.get("desc", "")), ROW_W - 4.0, MapleText.SMALL)
		if desc.size() > DESC_MAX_LINES:
			desc = desc.slice(0, DESC_MAX_LINES)
			desc[DESC_MAX_LINES - 1] = MapleText.ellipsize(desc[DESC_MAX_LINES - 1] + " ...", ROW_W - 4.0,
				MapleText.SMALL)
		var h := ROW_H + 3.0 + desc.size() * DESC_LINE
		_blocks.append({"row": Rect2(ROW_X, y, ROW_W, ROW_H), "block": Rect2(ROW_X, y, ROW_W, h), "desc": desc})
		y += h + BLOCK_GAP
	var height := maxf(ART_SIZE.y, y - BLOCK_GAP + 4.0 + BOTTOM_H - 8.0)
	panel_size = Vector2(ART_SIZE.x, ceilf(height))


func _draw_panel(ci: Control) -> void:
	var focused: Dictionary = cards[focus] if focus >= 0 and focus < cards.size() and cards[focus] is Dictionary else {}
	var sentence := not focused.is_empty() and names_a_skill(focused)
	if sentence or focused.is_empty():
		TiledFrame.draw_v_slices(ci, Vector2.ZERO, UiArt.frame(ART), TOP_H, MID_Y, MID_H, panel_size.y)
	else:
		_draw_art_without_sentence(ci, UiArt.frame(ART))
	_draw_level(ci)
	if sentence:
		var full := notice_name(focused)
		var bold := MapleText.width(full, MapleText.SMALL, true) <= NAME_BOX.size.x - 4.0
		var nm := MapleText.ellipsize(full, NAME_BOX.size.x - 4.0, MapleText.SMALL, bold)
		MapleText.draw_centered(ci, NAME_BOX.position.x, NAME_BOX.position.y + 2.0, NAME_BOX.size.x, nm,
			MapleText.WHITE, MapleText.SMALL, bold)
	var row0 := UiArt.frame(ROW)
	var row1 := UiArt.frame(ROW_FOCUS)
	for i in mini(cards.size(), _blocks.size()):
		_draw_card(ci, i, cards[i], row1 if i == focus else row0)


## The window art like TiledFrame.draw_v_slices, with the notice sentence's words (SENTENCE_BANDS) replaced by the
## blank fill column of their own rows (the art is translucent, so the words are left out rather than painted over).
func _draw_art_without_sentence(ci: Control, f: SpriteFrame) -> void:
	if f == null:
		return
	var w := f.region.size.x
	var y := 0.0
	for band: Array in SENTENCE_BANDS:
		var y0 := float(band[0])
		var h := float(band[1]) - y0
		if y0 > y:
			UiArt.blit_part(ci, f, Rect2(0, y, w, y0 - y), Vector2(0, y))
		var x := 0.0
		for c: Vector2 in band[2]:
			if c.x > x:
				UiArt.blit_part(ci, f, Rect2(x, y0, c.x - x, h), Vector2(x, y0))
			UiArt.blit_part(ci, f, Rect2(BLANK_X, y0, 1, h), Vector2(c.x, y0), Vector2(c.y - c.x, h))
			x = c.y
		UiArt.blit_part(ci, f, Rect2(x, y0, w - x, h), Vector2(x, y0))
		y = float(band[1])
	UiArt.blit_part(ci, f, Rect2(0, y, w, TOP_H - y), Vector2(0, y))
	# Mid rows and the bottom edge exactly as TiledFrame.draw_v_slices draws them below TOP_H.
	var bottom_y := MID_Y + MID_H
	var bottom_h := f.region.size.y - bottom_y
	var yy := TOP_H
	var end := maxf(TOP_H, panel_size.y - bottom_h)
	while yy < end:
		var hh := minf(MID_H, end - yy)
		UiArt.blit_part(ci, f, Rect2(0, MID_Y, w, hh), Vector2(0, yy))
		yy += hh
	UiArt.blit_part(ci, f, Rect2(0, bottom_y, w, bottom_h), Vector2(0, end))


func _draw_level(ci: Control) -> void:
	var s := str(level)
	var frames: Array[SpriteFrame] = []
	var w := 0.0
	for ch in s:
		var f := UiArt.frame(LEVEL_DIGITS + ch)
		if f == null:
			frames.clear()
			break
		frames.append(f)
		w += f.region.size.x
	if not frames.is_empty() and w <= LEVEL_BOX.size.x:
		var x := LEVEL_BOX.position.x + floorf((LEVEL_BOX.size.x - w) * 0.5)
		for f in frames:
			UiArt.blit(ci, f, Vector2(x, LEVEL_BOX.position.y + floorf((LEVEL_BOX.size.y - f.region.size.y) * 0.5)))
			x += f.region.size.x
	else:
		MapleText.draw_centered(ci, LEVEL_BOX.position.x, LEVEL_BOX.position.y + 2.0, LEVEL_BOX.size.x, s,
			MapleText.WHITE, MapleText.SIZE, true)


func _draw_card(ci: Control, i: int, card: Dictionary, row_art: SpriteFrame) -> void:
	var b: Dictionary = _blocks[i]
	var r: Rect2 = b.row
	var p := r.position
	if row_art != null:
		TiledFrame.draw_h_slices(ci, p, row_art, ROW_SLOT_W, ROW_MID_X, r.size.x)
	else:
		ci.draw_rect(r, Color8(238, 238, 238) if i != focus else Color8(204, 221, 238))
	UiArt.blit_icon(ci, UiArt.icon_or_fallback(String(card.get("icon", ""))), p + Vector2(1, 1))
	var key := UiArt.frame(KEY_DIGITS + str(i + 1))
	if key != null:
		UiArt.blit(ci, key, p + Vector2(2, 2))
	var tx := p.x + ROW_SLOT_W + 4.0
	var name_w := r.end.x - tx - 3.0
	var nm := String(card.get("name", ""))
	var name_size := MapleText.SIZE if MapleText.width(nm, MapleText.SIZE, true) <= name_w else MapleText.SMALL
	MapleText.draw(ci, Vector2(tx, p.y + 2.0), MapleText.ellipsize(nm, name_w, name_size, true), MapleText.BLACK,
		name_size, true)
	var rt := rank_text(card)
	var rank_col := MapleText.ORANGE if rt == "NEW" or rt.ends_with("MAX") else Color8(68, 68, 68)
	MapleText.draw(ci, Vector2(tx, p.y + 19.0), rt, rank_col, MapleText.SMALL, rt == "NEW")
	var y := r.end.y + 3.0
	for line: String in b.desc:
		MapleText.draw(ci, Vector2(p.x + 2.0, y), line, MapleText.WHITE, MapleText.SMALL, false, 0,
			MapleText.PANEL_SHADOW, true)
		y += DESC_LINE
