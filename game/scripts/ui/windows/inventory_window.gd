class_name InventoryWindow
extends UiWindow
## Shared base of the v83 Equip and Item windows (#108). Both show the live character of a RunWorld and change it
## only through RunWorld's methods (equip_item, unequip_item, discard_item, discard_scrolls); the window never edits
## the equipment state itself. What the base gives the two windows:
##   - the mouse protocol of v83 inventories: a double-click activates the item under the mouse (wear / take off), a
##     press that moves DRAG_START px starts a drag of that item, drawn under the cursor; the release resolves the drop
##     against the window stack: another inventory window gets `receive_drop(payload)`, no window at all means
##     `drop_outside(payload)` (the Item window asks to discard), anything else is nothing;
##   - hover tooltips (ItemTooltip) of the item under the mouse, placed beside the cursor and kept above the bar;
##   - `apply(action, reason)`: emits `item_action` after a change, or `notice` with the message for a refusal.
## Subclasses implement payload_at(), activate(), receive_drop(), drop_outside() and tooltip_for(); a payload is the
## plain item description of one slot: {"kind": "worn", "slot"} / {"kind": "inventory", "index"} / {"kind": "potion" |
## "scroll"} plus "id" and, for stacks, "count".

## Emitted after the world changed the character ("equip", "unequip", "discard"); the host refreshes the drawn look
## and its other windows.
signal item_action(action: String)
## Emitted with a player-visible message (a refused requirement, a full inventory).
signal notice(text: String)

## tier C (ours; the v83 client's wording is unverified): the messages for a refused change.
const MESSAGES := {"requirement": "You do not meet the requirements to equip this item.",
	"inventory_full": "Your inventory is full. Make room before taking an item off."}
## tier C (ours): a press that moves this far starts a drag; a shorter press is a click.
const DRAG_START := 4.0
## The v83 inventory slot (icons are 27-32 px, centred in it).
const ICON_SLOT := Vector2(32, 32)

## The live character.
var world: RunWorld

var _tip: ItemTooltip
var _mouse := Vector2.ZERO
var _hover := {}
var _drag := {}
var _pressed := {}
var _press_at := Vector2.ZERO


func _init(p_world: RunWorld = null) -> void:
	super._init()
	world = p_world
	_tip = ItemTooltip.new()
	add_child(_tip)


# --- subclass interface ----------------------------------------------------------------------------------------------

## The item under local point `p` ({} for an empty slot or no slot).
func payload_at(_p: Vector2) -> Dictionary:
	return {}


## A double-click on `payload`.
func activate(_payload: Dictionary) -> void:
	pass


## A drop of another window's `payload` on this window; true when it was taken.
func receive_drop(_payload: Dictionary) -> bool:
	return false


## A drop of this window's `payload` outside every window.
func drop_outside(_payload: Dictionary) -> void:
	pass


## The tooltip data of `payload` (ItemTooltip.show_data), {} for none.
func tooltip_for(_payload: Dictionary) -> Dictionary:
	return {}


# --- shared state ----------------------------------------------------------------------------------------------------

## The tooltip shown now (the hovered item's, none while dragging).
func tooltip() -> Dictionary:
	return tooltip_for(_hover) if not _hover.is_empty() and _drag.is_empty() else {}


## True while an item is dragged from this window.
func is_dragging_item() -> bool:
	return not _drag.is_empty()


## The dragged item's payload ({} when none).
func dragged() -> Dictionary:
	return _drag


## The character's totals the v83 requirements are checked against (RunWorld.player_state).
func character_totals() -> Dictionary:
	var ps := world.player_state if world != null else {}
	return {"level": int(ps.get("level", 1)), "job_id": int(ps.get("job_id", 0)), "str": int(ps.get("str", 0)),
		"dex": int(ps.get("dex", 0)), "int": int(ps.get("int", 0)), "luk": int(ps.get("luk", 0))}


## The canonical info node of an equipment id (setup.equipment_info; {} when the setup lacks it).
func info_of(id: int) -> Dictionary:
	return Equipment.info_of(world.setup.get("equipment_info", {}), id) if world != null else {}


## The player-visible name of an item (String.wz; "Item <id>" without one).
func item_name(id: int) -> String:
	var n := UiArt.text(InventoryModel.name_path(id))
	return n if n != "" else "Item %d" % id


## The tooltip data of an equipment instance.
func equip_tooltip(instance: Dictionary) -> Dictionary:
	var id := int(instance.get("id", 0))
	var tip := InventoryModel.tooltip(instance, info_of(id), character_totals(), item_name(id))
	tip["icon"] = InventoryModel.icon_path(id)
	tip["desc"] = UiArt.text(InventoryModel.desc_path(id)).replace("\\n", "\n")
	return tip


## The tooltip data of a Use item (potion, scroll): name, description, icon.
func use_tooltip(id: int) -> Dictionary:
	return {"name": item_name(id), "desc": UiArt.text(InventoryModel.desc_path(id)).replace("\\n", "\n"),
		"icon": InventoryModel.icon_path(id)}


## Reports the outcome of a RunWorld change: "" emits item_action(action) and redraws, a reason emits its message.
## Returns `reason`.
func apply(action: String, reason: String) -> String:
	if reason == "":
		_hover = {}
		queue_redraw()
		item_action.emit(action)
	else:
		var text := message_for(reason)
		if text != "":
			notice.emit(text)
	return reason


## The player-visible message of an Equipment reason ("" for reasons with no message).
static func message_for(reason: String) -> String:
	if reason.begins_with("req"):
		return String(MESSAGES.requirement)
	if reason == "inventory_full":
		return String(MESSAGES.inventory_full)
	return ""


# --- mouse -------------------------------------------------------------------------------------------------------------

func _window_gui_input(event: InputEvent, local: Vector2) -> void:
	_mouse = local
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if mb.double_click:
				_pressed = {}
				var p := payload_at(local)
				if not p.is_empty():
					activate(p)
			else:
				_pressed = payload_at(local)
				_press_at = local
		else:
			if not _drag.is_empty():
				_drop(local)
			_pressed = {}
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if not _pressed.is_empty() and _drag.is_empty() and (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 \
				and (local - _press_at).length() >= DRAG_START:
			_drag = _pressed
			_pressed = {}
	_update_hover(local)
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _drag.is_empty() and not _hover.is_empty():
		_hover = {}
		_place_tip()
		queue_redraw()


func _update_hover(local: Vector2) -> void:
	var h := payload_at(local)
	if h != _hover:
		_hover = h
	_place_tip()


func _place_tip() -> void:
	if _tip == null:
		return
	var d := tooltip()
	if d.is_empty():
		_tip.show_data({}, Vector2.ZERO)
		return
	_tip.show_data(d, position + _mouse + Vector2(18, 14), _view_size() - Vector2(0, HudWidget.BAR_H))


func _drop(local: Vector2) -> void:
	var payload := _drag
	_drag = {}
	var target := _target_at(get_global_position() + local)
	if target == null:
		drop_outside(payload)
	elif target != self and target is InventoryWindow:
		(target as InventoryWindow).receive_drop(payload)
	_place_tip()


## The front window of the stack under a global point (null when none).
func _target_at(global_point: Vector2) -> UiWindow:
	var stack := get_parent() as WindowStack
	if stack == null:
		return null
	var all := stack.windows()
	for i in range(all.size() - 1, -1, -1):
		if all[i].get_global_rect().has_point(global_point):
			return all[i]
	return null


## True when `payload` is the item being dragged (its slot draws dimmed).
func _is_dragged(payload: Dictionary) -> bool:
	return not _drag.is_empty() and _drag == payload


## The dragged item's icon under the cursor (drawn last).
func _draw_drag() -> void:
	if _drag.is_empty():
		return
	UiArt.blit_icon(self, UiArt.icon_or_fallback(InventoryModel.icon_path(int(_drag.get("id", 0)))),
		_mouse - ICON_SLOT * 0.5, ICON_SLOT, Color(1, 1, 1, 0.8))
