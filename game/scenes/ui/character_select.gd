extends Control
## Plain character slots and history for #69. #70 replaces this presentation; all actions go through SceneFlow.

## tier C: temporary plain-screen dimensions and typography for #69; #70 replaces the screen.
const COLUMN_WIDTH := 560.0
const ROW_GAP := 14
const HEADING_SIZE := 24
const HISTORY_HEIGHT := 300.0

var flow: SceneFlow
var history_mode := false
var name_edit: LineEdit
var create_button: Button
var message: Label
var delete_dialog: ConfirmationDialog
var _delete_slot := -1


## Binds the owning flow before entering the tree; history uses the same plain list surface.
func configure(p_flow: SceneFlow, p_history: bool = false) -> void:
	flow = p_flow
	history_mode = p_history


func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color8(25, 44, 58) # tier C: temporary plain-screen palette, #69.
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = COLUMN_WIDTH
	column.add_theme_constant_override("separation", ROW_GAP)
	center.add_child(column)
	var heading := Label.new()
	heading.text = "Run history" if history_mode else "Character select"
	heading.add_theme_font_size_override("font_size", HEADING_SIZE)
	column.add_child(heading)
	if history_mode:
		var scroll := ScrollContainer.new()
		scroll.custom_minimum_size.y = HISTORY_HEIGHT
		column.add_child(scroll)
		var entries := VBoxContainer.new()
		scroll.add_child(entries)
		if flow.save_data().history.is_empty():
			_add_label(entries, "No ended runs yet.")
		for entry: Dictionary in flow.save_data().history:
			_add_label(entries, "%s / Lv. %d %s / %s / %d tiers" % [entry.name, int(entry.level),
				entry.job_name, entry.ending, int(entry.tiers_cleared)])
		_button(column, "Back", flow.goto_character_select)
		return
	for i in SaveData.SLOT_COUNT:
		var row := HBoxContainer.new()
		column.add_child(row)
		var slot := flow.save_data().slot(i)
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = "%d. Empty" % (i + 1) if slot.is_empty() else "%d. %s / Lv. %d %s" % [i + 1,
			slot.name, int(slot.character.level), JobTree.from_data(DataRepo.load_all().jobs, {}).name_of(int(slot.character.job_id))]
		row.add_child(label)
		if not slot.is_empty():
			var resume_button := _button(row, "Continue", func() -> void: flow.continue_character(i))
			resume_button.name = "Continue%d" % i
			_button(row, "Delete", func() -> void: _confirm_delete(i))
	name_edit = LineEdit.new()
	name_edit.name = "CharacterName"
	name_edit.placeholder_text = "Name: 4-12 letters and digits"
	name_edit.max_length = 12
	column.add_child(name_edit)
	create_button = _button(column, "Create character", _create)
	create_button.disabled = not flow.save_data().slots.has(null)
	name_edit.text_submitted.connect(func(_text: String) -> void: _create())
	message = Label.new()
	message.custom_minimum_size.x = COLUMN_WIDTH
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	_button(column, "Run history", flow.goto_history)
	_button(column, "Back to title", flow.goto_title)
	delete_dialog = ConfirmationDialog.new()
	delete_dialog.title = "Delete character?"
	delete_dialog.confirmed.connect(func() -> void: flow.delete_character(_delete_slot))
	add_child(delete_dialog)
	name_edit.grab_focus()


func _create() -> void:
	if not create_button.disabled and flow.create_character(name_edit.text) < 0:
		message.text = flow.action_error


func _confirm_delete(index: int) -> void:
	_delete_slot = index
	delete_dialog.dialog_text = "Delete %s? This ends the run and adds it to run history." % flow.save_data().slot(index).name
	delete_dialog.popup_centered()


func _input(event: InputEvent) -> void:
	if delete_dialog != null and delete_dialog.visible:
		return
	if MapleWindow.key_pressed(event, KEY_ESCAPE):
		if history_mode:
			flow.goto_character_select()
		else:
			flow.goto_title()
		get_viewport().set_input_as_handled()


func _add_label(parent: Node, text: String) -> void:
	var label := Label.new()
	label.text = text
	parent.add_child(label)


func _button(parent: Node, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	parent.add_child(button)
	return button
