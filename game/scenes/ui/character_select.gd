extends Control
## Three living characters on the v83 login backdrop, Explorer creation and scrollable ended-run history.
## All persistent actions use SceneFlow; only CharacterSnapshot.look supplies a character's appearance.

const CREATE := preload("res://scenes/ui/character_create.gd")
const LOGIN := "UI.wz/Login.img/"
## tier C: 800x600 book layout, slot feet and controls fitted around the original art.
const BOOK := Vector2(800, 600)
const SLOT_X := [180, 400, 620]
const FEET_Y := 319
const INK := Color8(85, 51, 17)

var flow: SceneFlow
var history_mode := false
var create_button: WzButton
var message: Label
var delete_dialog: ConfirmationDialog
var creation: Control
var backdrop: LoginBackdrop
var avatars: Array[AvatarRenderer] = []
var _ui: Control
var _surface: Control
var _delete_slot := -1


## Binds the owning flow before entering the tree; history shares the book and navigation.
func configure(p_flow: SceneFlow, p_history: bool = false) -> void:
	flow = p_flow
	history_mode = p_history


func _ready() -> void:
	backdrop = LoginBackdrop.new(LoginBackdrop.CHAR_SELECT)
	backdrop.bgm = LoginBackdrop.BGM_SELECT
	add_child(backdrop)
	backdrop.hide_objs("CharSelect/signboard")
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
	_label(_surface, "Character select", Vector2(70, 79), Vector2(660, 26), 22, true)
	_label(_surface, "Choose a character to continue its run.", Vector2(70, 115), Vector2(660, 20))
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	for i in SaveData.SLOT_COUNT:
		var x := float(SLOT_X[i])
		var slot := flow.save_data().slot(i)
		if slot.is_empty():
			_slot_tag("Empty slot", x, 352)
			continue
		_image(_surface, "CharSelect/character/0", Vector2(x - 30, FEET_Y - 4))
		var avatar := AvatarRenderer.new()
		avatar.position = Vector2(x, FEET_Y)
		_surface.add_child(avatar)
		avatar.set_look(DataRepo.character_look(slot.character, data))
		avatars.append(avatar)
		_slot_tag(slot.name, x, 342, true)
		_slot_tag("Lv. %d  %s" % [int(slot.character.level), jobs.name_of(int(slot.character.job_id))], x, 368)
		var start := _button(_surface, "CharSelect/BtSelect", "Continue", Vector2(x - 50, 406),
			func() -> void: flow.continue_character(i))
		start.name = "Continue%d" % i
		_button(_surface, "CharSelect/BtDelete", "Delete", Vector2(x - 35, 449),
			func() -> void: _confirm_delete(i))
	create_button = _button(_surface, "CharSelect/BtNew", "Create character", Vector2(506, 502), show_creation)
	create_button.name = "NewCharacter"
	create_button.disabled = not flow.save_data().slots.has(null)
	_button(_surface, "", "Run history", Vector2(335, 504), flow.goto_history)
	_button(_surface, "Common/BtStart", "Back", Vector2(68, 502), flow.goto_title)
	message = _label(_surface, "All 3 slots are occupied. Delete a character to create another." if create_button.disabled else "",
		Vector2(100, 148), Vector2(600, 18))
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete character?"
	delete_dialog.confirmed.connect(_delete_confirmed)
	add_child(delete_dialog)


## Opens the v83 Explorer creation form without changing the saved character slots.
func show_creation() -> void:
	if create_button.disabled or creation != null:
		return
	_surface.hide()
	creation = CREATE.new()
	creation.configure(flow)
	creation.cancelled.connect(_cancel_creation)
	_ui.add_child(creation)


func _cancel_creation() -> void:
	creation.queue_free()
	creation = null
	_surface.show()
	create_button.grab_focus()


func _confirm_delete(index: int) -> void:
	_delete_slot = index
	delete_dialog.dialog_text = "Delete %s? This ends the run and adds it to run history." % flow.save_data().slot(index).name
	delete_dialog.popup_centered()


func _delete_confirmed() -> void:
	if not flow.delete_character(_delete_slot):
		message.text = flow.action_error


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
	_button(_surface, "Common/BtStart", "Back", Vector2(68, 502), flow.goto_character_select)


func _history_line(parent: Node, text: String, bold: bool = false) -> void:
	var label := MapleText.new(text, MapleText.SIZE, INK, bold)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(label)


func _slot_tag(text: String, x: float, y: float, bold: bool = false) -> void:
	# tier C: the existing v83-style NameTags treatment keeps names legible over the login bridge.
	var width := ceilf(MapleText.width(text, MapleText.SIZE, bold)) + 10.0
	var label := _label(_surface, text, Vector2(x - width * 0.5, y), Vector2(width, 20), MapleText.SIZE, bold)
	label.add_theme_color_override("font_color", NameTags.TEXT_COLOR)
	var box := StyleBoxFlat.new()
	box.bg_color = NameTags.BOX_COLOR
	label.add_theme_stylebox_override("normal", box)


func _process(dt: float) -> void:
	for avatar in avatars:
		avatar.advance(dt)


func _unhandled_input(event: InputEvent) -> void:
	if creation != null or (delete_dialog != null and delete_dialog.visible):
		return
	if MapleWindow.key_pressed(event, KEY_ESCAPE):
		if history_mode:
			flow.goto_character_select()
		else:
			flow.goto_title()
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
	var button := WzButton.new(LOGIN + path if path != "" else LOGIN + "Title/BtLoginIDLost")
	button.fallback_size = Vector2(110, 24)
	if path.is_empty():
		button.set_plate(110, 5)
		button.label = fallback
	elif not button.has_art():
		button.label = fallback
	button.position = at
	button.focus_mode = Control.FOCUS_ALL
	button.focus_entered.connect(func() -> void: button.key_focused = true)
	button.focus_exited.connect(func() -> void: button.key_focused = false)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
