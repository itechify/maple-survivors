extends Control
## v83 Explorer creation with live composited preview; every allowed value comes from MakeCharInfo.

signal cancelled()

const LOGIN := "UI.wz/Login.img/"
## tier C: original 800x600 book layout; 19px rows fit the charSet parchment without stat dice.
const FIELDS := ["gender", "face", "hair", "hair_colour", "skin", "top", "bottom", "shoes", "weapon"]
const LABELS := ["Gender", "Face", "Hair", "Hair colour", "Skin", "Top", "Bottom", "Shoes", "Weapon"]
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


## Binds the owning coordinator; no save is written until Create is accepted.
func configure(p_flow: SceneFlow) -> void:
	flow = p_flow


func _ready() -> void:
	size = Vector2(800, 600)
	var library := UiArt.lib()
	var img := library.img(CharacterCreation.IMG) if library != null else null
	model = CharacterCreation.new(img.root if img != null else {})
	_image("NewChar/charName", Vector2(110, 65))
	_image("Gender/backgrnd/0", Vector2(60, 295))
	_image("NewChar/charSet", Vector2(470, 70))
	name_edit = LineEdit.new()
	name_edit.name = "CharacterName"
	name_edit.position = Vector2(139, 170)
	name_edit.size = Vector2(144, 25)
	name_edit.placeholder_text = "Character name"
	name_edit.add_theme_font_override("font", MapleText.font())
	name_edit.add_theme_font_size_override("font_size", MapleText.SIZE)
	add_child(name_edit)
	name_edit.tooltip_text = "4-12 letters A-Z and digits 0-9, unique among living characters"
	_button("NewChar/BtCheck", "Check name", Vector2(178, 249), _check_name)
	for i in FIELDS.size():
		var field: String = FIELDS[i]
		var y := 172.0 + i * 19.0
		var caption := _label(LABELS[i], Vector2(487, y), Vector2(66, 18))
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		_button("NewChar/BtLeft", "<", Vector2(553, y), func() -> void: cycle_option(field, -1))
		var label := _label("", Vector2(569, y), Vector2(92, 18))
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		option_labels[field] = label
		_button("NewChar/BtRight", ">", Vector2(669, y), func() -> void: cycle_option(field, 1))
	avatar = AvatarRenderer.new()
	avatar.position = Vector2(242, 451)
	add_child(avatar)
	_weapon_label = _label("", Vector2(91, 473), Vector2(298, 18))
	create_button = _button("NewChar/BtYes", "Create", Vector2(528, 413), _create)
	create_button.name = "CreateCharacter"
	create_button.disabled = not model.available()
	_button("NewChar/BtNo", "Cancel", Vector2(611, 413), func() -> void: cancelled.emit())
	message = _label("", Vector2(174, 322), Vector2(204, 58))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text = "Beginner · Automatic AP\nName: 4-12 letters and digits."
	if not model.available():
		_error("Creation options are missing. Re-import your v83 WZ data from the title screen.")
	else:
		_refresh()
	name_edit.text_submitted.connect(func(_name: String) -> void: _create())
	name_edit.grab_focus()


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
	message.text = "This name is available." if error.is_empty() else error


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


func _image(path: String, at: Vector2) -> void:
	var art := WzImage.new(LOGIN + path)
	art.position = at
	add_child(art)


func _label(text: String, at: Vector2, box: Vector2) -> Label:
	var label := MapleText.new(text, MapleText.SMALL, INK)
	label.position = at
	label.size = box
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(label)
	return label


func _button(path: String, fallback: String, at: Vector2, action: Callable) -> WzButton:
	var button := WzButton.new(LOGIN + path)
	button.fallback_size = Vector2(16, 18) if path.contains("Left") or path.contains("Right") else Vector2(60, 24)
	if not button.has_art():
		button.label = fallback
	button.position = at
	button.focus_mode = Control.FOCUS_ALL
	button.focus_entered.connect(func() -> void: button.key_focused = true)
	button.focus_exited.connect(func() -> void: button.key_focused = false)
	button.pressed.connect(action)
	add_child(button)
	return button
