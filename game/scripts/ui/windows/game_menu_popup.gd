class_name GameMenuPopup
extends UiWindow
## The list the status bar's Menu button opens: Stat, Skill, Key Config, Options. v83 has no art for this list in the
## cache, so it is drawn in the v83 context-menu style (UI.wz/UIWindow.img/ContextMenu: the `t` title plate, a `c`
## row per entry, the `s` bottom edge) with each entry on a ContextMenu button plate (BtInfo's normal / mouseOver /
## disabled art widened past its dot, its baked words left out) and our own label. Without the cache it keeps its
## size and draws plain boxes.
##
## Entries whose window is not registered in `stack` (WindowStack.can_open) are disabled (grey). Choosing an entry
## closes the popup and opens that window (or brings it to the front when it is already open); `entry_chosen` is
## emitted first. A left press outside the popup (and outside `ignore_rect`, the Menu button's global rect) closes
## it; Esc closes it as the stack's top window.

## Emitted with the chosen entry's id before its window opens.
signal entry_chosen(id: String)

## Entry ids (WindowStack ids) and labels, top to bottom.
const ENTRIES := [["stat", "Stat"], ["skill", "Skill"], ["key_config", "Key Config"], ["options", "Options"]]
const ART := "UI.wz/UIWindow.img/ContextMenu/"
const PLATE := "UI.wz/UIWindow.img/ContextMenu/BtInfo/"
## Context-menu piece sizes (v83 ContextMenu t 100x23, c 97x15, s 97x7; BtInfo 85x14).
const WIDTH := 100.0
const TOP_H := 23.0
const ROW_H := 15.0
const BOTTOM_H := 7.0
const PLATE_SIZE := Vector2(85, 14)
## tier C (ours): plate inset in a row, the plate's text-free left columns (the dot) and the label inset.
const PLATE_X := 6.0
const PLATE_LEFT := 11.0
const LABEL_X := 13.0

## The stack the entries open windows in.
var stack: WindowStack
## Global rect whose presses do not close the popup (the Menu button toggles it itself).
var ignore_rect := Rect2()
## Entry under the mouse (-1 = none).
var hover := -1


func _init() -> void:
	super._init()
	name = "GameMenuPopup"
	window_id = "menu"
	draggable = false
	auto_place = false
	size = Vector2(WIDTH, TOP_H + ENTRIES.size() * ROW_H + BOTTOM_H)


## The entry ids, top to bottom.
func entry_ids() -> PackedStringArray:
	var out := PackedStringArray()
	for e: Array in ENTRIES:
		out.append(String(e[0]))
	return out


## True when the entry's window exists (registered in the stack).
func is_enabled(id: String) -> bool:
	return stack != null and stack.can_open(id)


## Local rect of entry `id`'s plate (empty for an unknown id).
func entry_rect(id: String) -> Rect2:
	var i := entry_ids().find(id)
	if i < 0:
		return Rect2()
	return Rect2(Vector2(PLATE_X, TOP_H + i * ROW_H), PLATE_SIZE)


## Takes entry `id`: closes the popup and opens (or raises) its window. False when disabled or unknown.
func choose(id: String) -> bool:
	if not is_enabled(id):
		return false
	UiArt.play_sound(UiArt.SND_CLICK)
	entry_chosen.emit(id)
	var target := stack
	request_close()
	var open := target.find_window(id)
	if open != null:
		target.bring_to_front(open)
	else:
		target.toggle(id)
	return true


func _window_gui_input(event: InputEvent, local: Vector2) -> void:
	var hit := -1
	var ids := entry_ids()
	for i in ids.size():
		if entry_rect(ids[i]).has_point(local):
			hit = i
	if event is InputEventMouseMotion:
		if hit != hover:
			hover = hit
			if hit >= 0 and is_enabled(ids[hit]):
				UiArt.play_sound(UiArt.SND_OVER)
			queue_redraw()
	var mb := event as InputEventMouseButton
	if mb != null and mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed and hit >= 0:
		choose(ids[hit])


func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or not is_inside_tree():
		return
	var at := mb.position
	if get_global_rect().has_point(at) or ignore_rect.has_point(at):
		return
	request_close()


func _draw() -> void:
	var t := UiArt.frame(ART + "t")
	var c := UiArt.frame(ART + "c")
	var s := UiArt.frame(ART + "s")
	if t != null and c != null and s != null:
		UiArt.blit(self, t, Vector2.ZERO)
		for i in ENTRIES.size():
			UiArt.blit(self, c, Vector2(0, TOP_H + i * ROW_H))
		UiArt.blit(self, s, Vector2(0, TOP_H + ENTRIES.size() * ROW_H))
	else:
		draw_rect(Rect2(Vector2.ZERO, size), Color8(17, 34, 51, 230))
		draw_rect(Rect2(Vector2.ZERO, size), Color8(99, 147, 183), false)
	MapleText.draw(self, Vector2(12, 4), "MENU", MapleText.WHITE, MapleText.SMALL, true, 0, Color8(17, 85, 153), true)
	var ids := entry_ids()
	for i in ids.size():
		var r := entry_rect(ids[i])
		var enabled := is_enabled(ids[i])
		var state := "disabled" if not enabled else ("mouseOver" if i == hover else "normal")
		var plate := UiArt.frame(PLATE + state + "/0")
		if plate != null:
			TiledFrame.draw_h_slices(self, r.position, plate, PLATE_LEFT, PLATE_LEFT, r.size.x)
		else:
			draw_rect(r, Color8(68, 136, 187) if enabled else Color8(150, 150, 150))
		var col := MapleText.WHITE if enabled else Color8(220, 220, 220)
		MapleText.draw(self, r.position + Vector2(LABEL_X, -1), String(ENTRIES[i][1]), col, MapleText.SMALL, enabled)
