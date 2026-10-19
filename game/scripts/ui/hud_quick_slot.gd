class_name HudQuickSlot
extends HudWidget
## The v83 quick slot: UI.wz/StatusBar.img/base/quickSlot (151 x 80, a 4 x 2 grid of blank cells) above the right end of
## the status bar, showing in a fixed order the HP potion, the MP potion, the learned movement skill (Teleport or Dash,
## empty until learned) and Jump on the top row, and the Equip, Item, Stat and Skill windows on the bottom row. Each cell
## holds the icon Key Config uses for its action (KeyActionArt) and a small caption of the first key it is bound to,
## wherever that is; the potions show their current item's icon and the stock in the ItemNo digits.
##
## Display only: the widget takes no mouse (the collapse button is a Hud sibling) and nothing is clickable or draggable;
## rebinding stays in Key Config. The model (`cells`) is pure; captions are re-read from the live bindings on
## refresh_key_labels() (RunScene calls it on Settings.changed). Text goes through MapleText.

## The panel art and its size.
const FRAME := HudWidget.SB + "base/quickSlot"
const PANEL_SIZE := Vector2(151, 80)
## Cells per row, and the order of the 8 cells (the movement slot is filled with the learned skill key).
const COLUMNS := 4
const MOVEMENT := "movement"
const ORDER := ["drink_hp", "drink_mp", MOVEMENT, "jump", "equip_window", "item_window", "stat_window", "skill_window"]
## Potion cell -> its stock kind.
const POTION_KINDS := {"drink_hp": "hp", "drink_mp": "mp"}
## tier C (measured on the v83 quickSlot canvas): the first cell's white interior and the pitch from cell to cell; the
## 32 px icon box that centres an icon on a cell's bevelled tile.
const CELL_INTERIOR := Rect2(10, 9, 27, 25)
const CELL_PITCH := Vector2(35, 34)
const ICON_POS := Vector2(7, 6)
const ICON_BOX := Vector2(32, 32)
## tier C (ours): key captions are 9 px (the Key Config keycap size), white with a 1 px dark outline, at a cell's
## top-left; a potion's stock stands at its bottom-left (as in the v83 quick slot).
const CAPTION_SIZE := 9
const CAPTION_COLOR := Color8(255, 255, 255)
const CAPTION_OUTLINE := Color8(40, 59, 76)
## A caption wider than this (a cell's interior) is shortened with "..".
const CAPTION_MAX_W := 29.0

## The folded-away state (Hud.set_quick_slot_collapsed hides the widget with it).
var collapsed := false
var _potions: Dictionary = {}
var _movement: Dictionary = {}
var _cells: Array[Dictionary] = []


func _init() -> void:
	super._init()
	refresh_key_labels()


## The 8 cell models in ORDER: [{action, icon_path, caption, count, item_id}]. `captions` maps an action to its key
## caption ("" or absent = unbound), `potions` is the snapshot's {hp, mp: {item_id, count}} and `movement_skill` the
## learned skill key `{action, name, icon}` ({} = none learned). `count` is -1 for a cell without stock. Pure.
static func cells(captions: Dictionary, potions: Dictionary, movement_skill: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for slot: String in ORDER:
		var cell := {"action": slot, "icon_path": "", "caption": "", "count": -1, "item_id": 0}
		if slot == MOVEMENT:
			if movement_skill.is_empty():
				cell.action = ""
			else:
				cell.action = String(movement_skill.action)
				cell.icon_path = KeyActionArt.icon_path(cell.action, movement_skill)
		else:
			cell.icon_path = KeyActionArt.icon_path(slot)
		if POTION_KINDS.has(slot):
			var stock: Dictionary = potions.get(POTION_KINDS[slot], {})
			cell.item_id = int(stock.get("item_id", 0))
			cell.count = int(stock.get("count", 0))
			if cell.item_id > 0:
				cell.icon_path = AssetLibrary.item_icon_path(cell.item_id, false)
		cell.caption = String(captions.get(cell.action, ""))
		out.append(cell)
	return out


## The key captions of the quick slot's actions from the live bindings: action -> first key name ("" when unbound).
static func captions_now(movement_skill: Dictionary = {}) -> Dictionary:
	var out := {}
	for slot: String in ORDER:
		var action := String(movement_skill.get("action", "")) if slot == MOVEMENT else slot
		if action != "":
			out[action] = GameSettings.first_key_label(action)
	return out


## The learned movement skill of the run: the first entry of RunWorld.manual_skill_keys() ({} when none is learned).
static func movement_skill_of(skill_keys: Array) -> Dictionary:
	for info: Variant in skill_keys:
		if info is Dictionary and String((info as Dictionary).get("action", "")) in KeyBindings.SKILL_KEYS:
			return info
	return {}


## Rect of cell `i` (0..7) in widget coordinates: its white interior.
@warning_ignore("integer_division")
static func cell_rect(i: int) -> Rect2:
	return Rect2(CELL_INTERIOR.position + CELL_PITCH * Vector2(i % COLUMNS, i / COLUMNS), CELL_INTERIOR.size)


## Receives the potion snapshot and the learned movement skill (info.movement_skill) and rebuilds the cells.
func update(ps: Dictionary, info: Dictionary) -> void:
	super.update(ps, info)
	_potions = ps.get("potions", {})
	_movement = info.get("movement_skill", {})
	_rebuild()


## Re-reads the key captions from the live bindings and redraws with them.
func refresh_key_labels() -> void:
	_rebuild()


## Folds the panel away or shows it again.
func set_collapsed(value: bool) -> void:
	collapsed = value
	visible = not value


## The cells as drawn now (see cells()).
func cells_now() -> Array[Dictionary]:
	return _cells.duplicate(true)


## The displayed cell of `action` ("teleport", "drink_hp", ...), or {} when the panel has no such cell.
func cell(action: String) -> Dictionary:
	for c: Dictionary in _cells:
		if c.action == action:
			return c.duplicate()
	return {}


## The potion cell of `kind` ("hp" / "mp") as {kind, item_id, count, key_label, icon: SpriteFrame}, or {} for an
## unknown kind: the same snapshot and art _draw uses.
func displayed(kind: String) -> Dictionary:
	for action: String in POTION_KINDS:
		if POTION_KINDS[action] == kind:
			var c := cell(action)
			return {"kind": kind, "item_id": c.item_id, "count": c.count, "key_label": c.caption,
				"icon": _icon_of(c, true)}
	return {}


func _rebuild() -> void:
	_cells = cells(captions_now(_movement), _potions, _movement)
	queue_redraw()


## The cell's icon frame (null without the art). A potion item's icon must exist (a miss is recorded).
func _icon_of(c: Dictionary, report_missing: bool = false) -> SpriteFrame:
	return _frame(String(c.icon_path), report_missing and int(c.item_id) > 0)


@warning_ignore("integer_division")
func _draw() -> void:
	var panel := _frame(FRAME)
	if panel != null:
		_blit(panel, Vector2.ZERO)
	else:
		draw_rect(Rect2(Vector2.ZERO, PANEL_SIZE), Color8(31, 56, 80, 210))
	for i in _cells.size():
		var c: Dictionary = _cells[i]
		var inner := cell_rect(i)
		if panel == null:
			draw_rect(inner, Color8(99, 147, 183))
		var icon := _icon_of(c, true)
		if icon != null:
			_blit(icon, ICON_POS + CELL_PITCH * Vector2(i % COLUMNS, i / COLUMNS)
				+ ((ICON_BOX - icon.region.size) * 0.5).floor())
		if int(c.count) >= 0:
			_rank(Vector2(inner.position.x, inner.end.y), int(c.count), true, true)
		var caption := String(c.caption)
		if caption != "":
			caption = MapleText.ellipsize(caption, CAPTION_MAX_W, CAPTION_SIZE)
			MapleText.draw(self, inner.position + Vector2(1, -1), caption, CAPTION_COLOR, CAPTION_SIZE, false, 1,
				CAPTION_OUTLINE)
