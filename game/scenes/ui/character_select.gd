extends Control
## v83 login-map character roster. Selection owns one details scroll and one action set;
## persistence and navigation stay at the SceneFlow seams.

const CREATE := preload("res://scenes/ui/character_create.gd")
const CONFIRM := preload("res://scripts/ui/windows/character_delete_notice.gd")
const HISTORY_BUTTON := preload("res://scripts/ui/widgets/login_history_button.gd")
const LOGIN := "UI.wz/Login.img/"
const BOOK := Vector2(800, 600) # tier A: Login/Common/frame canvas size.
## tier C: matched to charselect_1.png adventure/0 lamps; private spec32/v83-login-refs/wz-layout-notes.md.
const SLOT_X := [252, 377, 502]
const FEET_Y := 370
## tier C: matched to charselect_1.png buttons (Select wording differs); same differences.md.
const ACTION_AT := [Vector2(576, 149), Vector2(576, 185), Vector2(576, 234)]
## tier C: matched to period charselect_2.png compact scroll above slot 3 (about 400,135); same layout.md.
const INFO_FROM_FEET := Vector2(-108, -235)
## tier C: 337px final beam canvas reaches the feet; exact anchor unresolved in the same layout.md.
const LIGHT_HEIGHT := 337
## tier C: matched to charselect_1.png pageL/pageR canvases; same wz-layout-notes.md.
const PAGE_AT := [Vector2(155, 330), Vector2(604, 331)]
## tier C: matched to charselect_1.png / charselect_2.png step; same layout.md (no world/channel plaque offline).
const STEP_AT := Vector2(0, 33)
## tier C: matched to charselect_1.png BtStart/BtVAC; supersedes layout.md's approximate y450/400.
const BACK_AT := Vector2(0, 425)
const HISTORY_AT := Vector2(0, 375)
## tier C: hint region matched to charselect_1.png; offline keyboard copy/tint, private spec32/v83-login-refs/layout.md.
const TAB_HINT := Rect2(270, 40, 220, 40)
const INK := Color8(85, 51, 17) # tier C: existing Maple login text palette.

var flow: SceneFlow
var history_mode := false
var selected := -1
var create_button: WzButton
var select_button: WzButton
var delete_button: WzButton
var message: Label
var delete_dialog: MapleWindow
var creation: Control
var backdrop: LoginBackdrop
var avatars: Array[AvatarRenderer] = []
var slot_buttons: Array[Button] = []
var selected_info := {}
var _avatar_by_slot := {}
var _tags: Array[Control] = []
var _effect: WzImage
var _sparkle: WzImage
var _info: Control
var _ui: Control
var _surface: Control
var _delete_slot := -1


## Binds the owning flow before entering the tree; history shares login navigation.
func configure(p_flow: SceneFlow, p_history: bool = false) -> void:
	flow = p_flow
	history_mode = p_history


func _ready() -> void:
	backdrop = LoginBackdrop.new(LoginBackdrop.CHAR_SELECT)
	backdrop.bgm = LoginBackdrop.BGM_SELECT
	add_child(backdrop)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_ui = Control.new()
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.size = BOOK
	layer.add_child(_ui)
	_surface = Control.new()
	_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_surface.size = BOOK
	_ui.add_child(_surface)
	get_viewport().size_changed.connect(_layout)
	_layout()
	if history_mode:
		_history()
	else:
		_slots()


func _layout() -> void:
	_ui.position = ((get_viewport_rect().size - BOOK) * 0.5).floor()


func _slots() -> void:
	_image(_surface, "Common/step/2", STEP_AT)
	var hint := _label(_surface, "Use Tab to select a menu.", TAB_HINT.position, TAB_HINT.size)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", MapleText.BLACK)
	var hint_plate := StyleBoxFlat.new()
	hint_plate.bg_color = Color(0.8, 0.87, 1.0, 0.8) # tier C: pale-blue reference hint, charselect_1.png.
	hint_plate.set_corner_radius_all(4) # tier C: screenshot-estimated hint corners, same reference.
	hint.add_theme_stylebox_override("normal", hint_plate)
	_effect = _image(_surface, "CharSelect/effect/1", Vector2.ZERO)
	_effect.anchor = Vector2.ZERO
	for i in SaveData.SLOT_COUNT:
		var feet := Vector2(SLOT_X[i], FEET_Y)
		var slot := flow.save_data().slot(i)
		var ground := _image(_surface, "CharSelect/character/0", feet)
		ground.anchor = Vector2.ZERO
		if slot.is_empty():
			var empty := _image(_surface, "CharSelect/character/1", feet)
			empty.anchor = Vector2.ZERO
		else:
			var lantern := _image(_surface, "CharSelect/adventure", feet)
			lantern.anchor = Vector2.ZERO # tier A: honor the WZ lamp origin at the registered feet.
			var avatar := AvatarRenderer.new()
			avatar.position = feet
			_surface.add_child(avatar)
			var data := DataRepo.load_all()
			avatar.set_look(DataRepo.character_look(slot.character, data,
				DataRepo.worn_cash(slot.character, data, flow.save_data().account.owned)))
			avatars.append(avatar)
			_avatar_by_slot[i] = avatar
		var tag := Control.new()
		tag.position = feet # tier C: matched to charselect_1.png tag top at feet; private spec32/v83-login-refs/layout.md.
		tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag.draw.connect(func() -> void: _draw_tag(tag, i))
		_surface.add_child(tag)
		_tags.append(tag)
		var hit := Button.new()
		hit.name = "CharacterSlot%d" % i
		hit.flat = true
		hit.focus_mode = Control.FOCUS_NONE
		hit.position = feet - Vector2(45, 80) # tier C: body and name click region, excluding nearby slots.
		hit.size = Vector2(90, 106)
		hit.disabled = slot.is_empty()
		for state: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			hit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		hit.pressed.connect(func() -> void: select_slot(i))
		_surface.add_child(hit)
		slot_buttons.append(hit)
	_sparkle = _image(_surface, "CharSelect/effect/0", Vector2.ZERO)
	_sparkle.anchor = Vector2.ZERO
	_info = Control.new()
	_info.name = "CharacterInfo"
	_info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_info.draw.connect(_draw_info)
	_surface.add_child(_info)
	select_button = _button(_surface, "CharSelect/BtSelect", "Continue", ACTION_AT[0], continue_selected)
	select_button.name = "SelectCharacter"
	create_button = _button(_surface, "CharSelect/BtNew", "Create", ACTION_AT[1], show_creation)
	create_button.name = "NewCharacter"
	create_button.disabled = not flow.save_data().slots.has(null)
	delete_button = _button(_surface, "CharSelect/BtDelete", "Delete", ACTION_AT[2], confirm_delete)
	delete_button.name = "DeleteCharacter"
	# tier A: these nodes have numbered normal/hover animations, not WZ button-state nodes.
	# tier C: one page for our three slots; inert, with original full opacity (charselect_1.png).
	for side: String in ["L", "R"]:
		var page := _image(_surface, "CharSelect/page%s/0" % side, PAGE_AT[0 if side == "L" else 1])
		page.anchor = Vector2.ZERO
	_button(_surface, "Common/BtStart", "Back", BACK_AT, flow.goto_title)
	var history := HISTORY_BUTTON.new()
	history.position = HISTORY_AT
	history.name = "RunHistory"
	history.pressed.connect(flow.goto_history)
	_surface.add_child(history)
	message = _label(_surface, "", Vector2(185, 472), Vector2(390, 18))
	# tier C: keep keyboard instructions legible when the selected beam crosses the hint's screen region.
	_surface.move_child(hint, _surface.get_child_count() - 1)
	delete_dialog = CONFIRM.new()
	delete_dialog.confirmed.connect(_delete_confirmed)
	_ui.add_child(delete_dialog)
	for i in SaveData.SLOT_COUNT:
		if not flow.save_data().slot(i).is_empty():
			select_slot(i)
			return
	select_slot(-1)


## Selects a living slot; empty slots clear the shared actions rather than starting a run.
func select_slot(index: int) -> void:
	selected = index if index >= 0 and index < SaveData.SLOT_COUNT and not flow.save_data().slot(index).is_empty() else -1
	selected_info = {}
	for i: int in _avatar_by_slot:
		(_avatar_by_slot[i] as AvatarRenderer).play("walk1" if i == selected else "stand1")
	for tag in _tags:
		tag.queue_redraw()
	select_button.disabled = selected < 0
	delete_button.disabled = selected < 0
	_effect.visible = selected >= 0
	_sparkle.visible = selected >= 0
	_info.visible = selected >= 0
	if selected < 0:
		return
	var slot := flow.save_data().slot(selected)
	var jobs := JobTree.from_data(DataRepo.load_all().jobs, DataRepo.load_all().jobs_survivor)
	selected_info = {"name": slot.name, "level": int(slot.character.level), "job": jobs.name_of(int(slot.character.job_id)),
		"job_id": int(slot.character.job_id), "attributes": slot.character.attributes.duplicate(), "fame": 0, "world_ranking": 0}
	_effect.position = Vector2(SLOT_X[selected], FEET_Y - LIGHT_HEIGHT)
	_sparkle.position = _effect.position
	_info.position = Vector2(SLOT_X[selected], FEET_Y) + INFO_FROM_FEET
	_info.tooltip_text = "%s / Lv. %d %s" % [selected_info.name, selected_info.level, selected_info.job]
	_info.queue_redraw()


## Continues the selected character through the unchanged saved-boundary flow.
func continue_selected() -> void:
	if selected >= 0:
		flow.continue_character(selected)


## Opens the v83 notice before any deletion; Cancel never writes.
func confirm_delete() -> void:
	if selected < 0:
		return
	_delete_slot = selected
	delete_dialog.open(flow.save_data().slot(selected).name)


func _delete_confirmed() -> void:
	if not flow.delete_character(_delete_slot):
		message.text = flow.action_error


func _draw_tag(ci: Control, index: int) -> void:
	var slot := flow.save_data().slot(index)
	if slot.is_empty():
		return
	var base := LOGIN + "CharSelect/nameTag/%d/" % (1 if index == selected else 0)
	var left := UiArt.frame(base + "0")
	var middle := UiArt.frame(base + "1")
	var right := UiArt.frame(base + "2")
	var width := maxf(58, ceilf(MapleText.width(slot.name)) + 18) # tier C: retained tag minimum/padding, unverified original-client fit.
	var x := -floorf(width * 0.5)
	if left != null and middle != null and right != null:
		UiArt.blit(ci, left, Vector2(x, 0))
		var fill := width - left.region.size.x - right.region.size.x
		UiArt.blit_part(ci, middle, Rect2(Vector2.ZERO, middle.region.size), Vector2(x + left.region.size.x, 0),
			Vector2(fill, middle.region.size.y))
		UiArt.blit(ci, right, Vector2(x + width - right.region.size.x, 0))
	MapleText.draw_centered(ci, x, 2, width, slot.name, MapleText.WHITE if index == selected else MapleText.GREY)


func _draw_info() -> void:
	if selected_info.is_empty():
		return
	# tier A: Login.img last compact unroll canvas and charInfo's own origin/canvas size.
	var scroll := UiArt.anim(LOGIN + "CharSelect/scroll/0")
	if scroll != null and not scroll.is_empty():
		UiArt.blit(_info, scroll.frames[-1], Vector2.ZERO)
	var frame := UiArt.frame(LOGIN + "CharSelect/charInfo")
	if frame != null:
		UiArt.blit_origin(_info, frame, Vector2(17, 20) + frame.origin) # tier C: inset matched to charselect_2.png.
	# tier C: value placements matched to charselect_2.png label cells; private v83-login-refs/layout.md.
	var values := [[selected_info.job, Vector2(53, 20), 144], [str(selected_info.level), Vector2(53, 38), 54],
		["0", Vector2(143, 38), 54], [str(int(selected_info.attributes.str)), Vector2(53, 57), 54],
		[str(int(selected_info.attributes.dex)), Vector2(53, 75), 54],
		[str(int(selected_info.attributes.int)), Vector2(143, 57), 54],
		[str(int(selected_info.attributes.luk)), Vector2(143, 75), 54], ["Ranking Not Available", Vector2(17, 118), 183]]
	for row: Array in values:
		var text := String(row[0])
		# tier C: long second-job names compact to the job family here; full job remains on hover and in history.
		if MapleText.width(text, MapleText.SMALL) > float(row[2]):
			text = "Magician" if int(selected_info.job_id) in range(200, 233) else text.left(20)
		MapleText.draw_centered(_info, row[1].x, row[1].y, row[2], text, INK, MapleText.SMALL)
	# tier C: compact Ranking Not Available variant matched to period charselect_2.png, without a badge below.


## Opens creation without changing the saved slots.
func show_creation() -> void:
	if create_button.disabled or creation != null:
		return
	_surface.hide()
	backdrop.center = LoginBackdrop.NEW_CHAR
	creation = CREATE.new()
	creation.configure(flow)
	creation.cancelled.connect(_cancel_creation)
	_ui.add_child(creation)


func _cancel_creation() -> void:
	creation.queue_free()
	creation = null
	backdrop.center = LoginBackdrop.CHAR_SELECT
	_surface.show()


func _history() -> void:
	var parchment := ParchmentScroll.new()
	parchment.position = Vector2(144, 67)
	_surface.add_child(parchment)
	parchment.unroll(true)
	_label(parchment.content, "Run history", Vector2(40, 148), Vector2(432, 24), 18, true)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(43, 178)
	scroll.size = Vector2(428, 198)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parchment.content.add_child(scroll)
	var entries := VBoxContainer.new()
	entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entries.add_theme_constant_override("separation", 12)
	scroll.add_child(entries)
	if flow.save_data().history.is_empty():
		_history_line(entries, "No ended runs yet. Your characters' journeys will appear here.")
	var history := flow.save_data().history.duplicate(true)
	history.reverse()
	for entry: Dictionary in history:
		_history_line(entries, "%s   ·   Lv. %d %s" % [entry.name, int(entry.level), entry.job_name], true)
		var ending: String = {"died": "Died", "victory": "Victory", "deleted": "Deleted"}.get(entry.ending, entry.ending)
		_history_line(entries, "%s   ·   %d tiers cleared   ·   %d rounds\n%s" % [ending,
			int(entry.tiers_cleared), int(entry.rounds_played), String(entry.date).replace("T", "  ")])
	_button(_surface, "Common/BtStart", "Back", BACK_AT, flow.goto_character_select)


func _history_line(parent: Node, text: String, bold: bool = false) -> void:
	var label := MapleText.new(text, MapleText.SIZE, INK, bold)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)


func _process(dt: float) -> void:
	for avatar in avatars:
		avatar.advance(dt)


func _input(event: InputEvent) -> void:
	# Consume roster arrows before Godot's focused-button navigation can take them.
	if creation == null and not history_mode and not delete_dialog.is_open() and (
			MapleWindow.key_pressed(event, KEY_LEFT) or MapleWindow.key_pressed(event, KEY_RIGHT)):
		_unhandled_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if creation != null or (delete_dialog != null and delete_dialog.is_open()):
		return
	if MapleWindow.key_pressed(event, KEY_ESCAPE):
		if history_mode:
			flow.goto_character_select()
		else:
			flow.goto_title()
	elif not history_mode and MapleWindow.key_pressed(event, KEY_H):
		flow.goto_history()
	elif not history_mode and MapleWindow.is_confirm(event):
		continue_selected()
	elif not history_mode and (MapleWindow.key_pressed(event, KEY_LEFT) or MapleWindow.key_pressed(event, KEY_RIGHT)):
		var step := -1 if MapleWindow.key_pressed(event, KEY_LEFT) else 1
		for offset in SaveData.SLOT_COUNT:
			var index := posmod(selected + step * (offset + 1), SaveData.SLOT_COUNT)
			if not flow.save_data().slot(index).is_empty():
				select_slot(index)
				break
	else:
		return
	get_viewport().set_input_as_handled()


static func _label(parent: Node, text: String, at: Vector2, box: Vector2, font_size: int = 12, bold: bool = false) -> Label:
	var label := MapleText.new(text, font_size, INK, bold)
	label.position = at
	label.size = box
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


static func _image(parent: Node, path: String, at: Vector2) -> WzImage:
	var art := WzImage.new(LOGIN + path)
	art.position = at
	parent.add_child(art)
	return art


static func _button(parent: Node, path: String, fallback: String, at: Vector2, action: Callable) -> WzButton:
	var button := WzButton.for_action(LOGIN + path if path != "" else LOGIN + "Title/BtLoginIDLost",
		fallback, Vector2(110, 24), action, path.begins_with("CharSelect/Bt"))
	if path.is_empty():
		button.set_plate(110, 5)
		button.label = fallback
	button.position = at
	parent.add_child(button)
	return button
