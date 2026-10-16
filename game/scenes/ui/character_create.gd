extends Control
## v83 Explorer creation with live composited preview; every allowed value comes from MakeCharInfo.

signal cancelled()

const LOGIN := "UI.wz/Login.img/"
## tier A: avatarSel/0..8 labels/order; tier B: 19px row pitch in the local NewChar client reference.
const FIELDS := ["face", "hair", "hair_colour", "skin", "top", "bottom", "shoes", "weapon", "gender"]
const INK := Color8(85, 51, 17)
const ERROR_INK := Color8(153, 34, 0)

var flow: SceneFlow
var model: CharacterCreation
var gender := 0
var choices := {}
var name_edit: LineEdit
var create_button: WzButton
var message: Label
var avatar: AvatarRenderer
var option_labels: Dictionary = {}
var _weapon_label: Label
var name_button: WzButton
var _gender_surface: Control
var _name_surface: Control
var _look_surface: Control
var _gender_label: Label
var _gender_ok: WzButton
var _look_ok: WzButton


## Binds the owning coordinator; no save is written until Create is accepted.
func configure(p_flow: SceneFlow) -> void:
	flow = p_flow


func _ready() -> void:
	size = Vector2(800, 600)
	var library := UiArt.lib()
	var img := library.img(CharacterCreation.IMG) if library != null else null
	model = CharacterCreation.new(img.root if img != null else {})
	_gender_surface = Control.new()
	_gender_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_gender_surface)
	_name_surface = Control.new()
	_name_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_surface)
	_look_surface = Control.new()
	_look_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_look_surface)
	_image_on(_gender_surface, "Gender/backgrnd/0", Vector2(219, 174))
	_image_on(_gender_surface, "Gender/text/0", Vector2(245, 198))
	_gender_label = _label_on(_gender_surface, "Male", Vector2(351, 278), Vector2(48, 18))
	_button_on(_gender_surface, "NewChar/BtLeft", "<", Vector2(330, 278), func() -> void: cycle_option("gender", -1))
	_button_on(_gender_surface, "NewChar/BtRight", ">", Vector2(401, 278), func() -> void: cycle_option("gender", 1))
	_gender_ok = _button_on(_gender_surface, "Gender/BtYes", "OK", Vector2(355, 346), _advance_gender)
	_button_on(_gender_surface, "Gender/BtNo", "Cancel", Vector2(430, 346), func() -> void: cancelled.emit())
	# tier B: local Journey NewChar name board (455,115), settings (450,115),
	# preview feet (360,348), 19px rows beginning at (461,217). Read for facts only.
	_image_on(_name_surface, "NewChar/charName", Vector2(455, 115))
	name_edit = LineEdit.new()
	name_edit.name = "CharacterName"
	name_edit.position = Vector2(486, 219)
	name_edit.size = Vector2(140, 24)
	name_edit.add_theme_font_override("font", MapleText.font())
	name_edit.add_theme_font_size_override("font_size", MapleText.SIZE)
	name_edit.add_theme_color_override("font_color", MapleText.WHITE)
	for state: String in ["normal", "focus"]:
		name_edit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_name_surface.add_child(name_edit)
	name_edit.tooltip_text = "4-12 letters A-Z and digits 0-9, unique among living characters"
	name_button = _button_on(_name_surface, "NewChar/BtCheck", "Check name", Vector2(530, 297), _check_name)
	_button_on(_name_surface, "Common/BtStart", "Back", Vector2(68, 502), _return_gender)
	_image_on(_look_surface, "NewChar/charSet", Vector2(450, 115))
	for i in FIELDS.size():
		var field: String = FIELDS[i]
		var y := 217.0 + i * 19.0
		_image_on(_look_surface, "NewChar/avatarSel/%d/normal" % i, Vector2(461, y))
		var previous := _button_on(_look_surface, "NewChar/BtLeft", "<", Vector2(521, y), func() -> void: cycle_option(field, -1))
		previous.name = "Previous_" + field
		var label := _label_on(_look_surface, "", Vector2(538, y), Vector2(105, 17))
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		option_labels[field] = label
		var next := _button_on(_look_surface, "NewChar/BtRight", ">", Vector2(645, y), func() -> void: cycle_option(field, 1))
		next.name = "Next_" + field
	avatar = AvatarRenderer.new()
	avatar.position = Vector2(360, 348)
	avatar.facing = 1
	add_child(avatar)
	_weapon_label = _label_on(_look_surface, "", Vector2(204, 399), Vector2(242, 36))
	_weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_look_ok = _button_on(_look_surface, "NewChar/BtYes", "Create", Vector2(486, 445), _create)
	_look_ok.name = "CreateCharacter"
	_look_ok.disabled = not model.available()
	_button_on(_look_surface, "NewChar/BtNo", "Cancel", Vector2(568, 445), _return_name)
	message = _label_on(self, "", Vector2(452, 360), Vector2(224, 50))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if not model.available():
		_error("Creation options are missing. Re-import your v83 WZ data from the title screen.")
	else:
		_refresh()
	name_edit.text_submitted.connect(func(_name: String) -> void: _check_name())
	_set_phase("gender")


func _set_phase(phase: String) -> void:
	_gender_surface.visible = phase == "gender"
	_name_surface.visible = phase == "name"
	_look_surface.visible = phase == "look"
	avatar.visible = phase != "gender"
	create_button = {"gender": _gender_ok, "name": name_button, "look": _look_ok}[phase]
	message.position = Vector2(452, 360) if phase == "name" else Vector2(210, 437)
	message.size = Vector2(224, 50)
	if phase == "name":
		name_edit.grab_focus()
	else:
		name_edit.release_focus()


func _advance_gender() -> void:
	message.text = "4-12 letters and digits."
	_set_phase("name")


func _return_gender() -> void:
	message.text = ""
	_set_phase("gender")


func _return_name() -> void:
	message.text = "4-12 letters and digits."
	_set_phase("name")


## Moves one option with wrapping; changing gender resets the other indices to valid defaults.
func cycle_option(field: String, direction: int) -> void:
	if not model.available():
		return
	if field == "gender":
		gender = posmod(gender + direction, CharacterCreation.GENDERS.size())
		choices.clear()
	else:
		choices[field] = posmod(int(choices.get(field, 0)) + direction, model.options(gender, field).size())
	_refresh()


func _refresh() -> void:
	option_labels.gender.text = "Male" if gender == 0 else "Female"
	_gender_label.text = option_labels.gender.text
	for field: String in CharacterCreation.FIELDS:
		var id := model.value(gender, field, choices)
		var text := model.option_name(gender, field, id)
		if text.is_empty() and UiArt.lib() != null:
			text = UiArt.lib().string_name("Eqp", id)
		if text.is_empty():
			text = str(id)
		option_labels[field].text = text
		option_labels[field].tooltip_text = "%s (%d)" % [text, id]
	avatar.set_look(DataRepo.character_look({"look": model.look(gender, choices),
		"beginner_weapon": model.weapon(gender, choices), "job_id": 0}, DataRepo.load_all()))
	var weapon := model.weapon(gender, choices)
	var info: Variant = UiArt.node(AvatarRenderer.part_img_path(weapon) + "/info")
	_weapon_label.text = "%s   ·   WATK %d   ·   %.2fs" % [option_labels.weapon.text,
		int(info.get("incPAD", 0)), WeaponInfo.attack_interval(info)] if info is Dictionary else ""


func _check_name() -> void:
	var error := flow.save_data().name_error(name_edit.text)
	message.add_theme_color_override("font_color", INK if error.is_empty() else ERROR_INK)
	message.text = error
	if error.is_empty():
		_set_phase("look")


func _create() -> void:
	if create_button.disabled:
		return
	if flow.create_character(name_edit.text, model.look(gender, choices), model.weapon(gender, choices)) < 0:
		_error(flow.action_error)
		name_edit.grab_focus()


func _error(text: String) -> void:
	message.text = text
	message.add_theme_color_override("font_color", ERROR_INK)


func _process(dt: float) -> void:
	if avatar != null:
		avatar.advance(dt)


func _input(event: InputEvent) -> void:
	if MapleWindow.key_pressed(event, KEY_ESCAPE):
		cancelled.emit()
		get_viewport().set_input_as_handled()


func _image_on(parent: Node, path: String, at: Vector2) -> void:
	var art := WzImage.new(LOGIN + path)
	art.position = at
	parent.add_child(art)


func _label_on(parent: Node, text: String, at: Vector2, box: Vector2) -> Label:
	var label := MapleText.new(text, MapleText.SMALL, INK)
	label.position = at
	label.size = box
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(label)
	return label


func _button_on(parent: Node, path: String, fallback: String, at: Vector2, action: Callable) -> WzButton:
	var button := WzButton.new(LOGIN + path)
	button.fallback_size = Vector2(16, 18) if path.contains("Left") or path.contains("Right") else Vector2(60, 24)
	if not button.has_art():
		button.label = fallback
	button.position = at
	button.focus_mode = Control.FOCUS_ALL
	button.focus_entered.connect(func() -> void: button.key_focused = true)
	button.focus_exited.connect(func() -> void: button.key_focused = false)
	button.pressed.connect(action)
	parent.add_child(button)
	return button
