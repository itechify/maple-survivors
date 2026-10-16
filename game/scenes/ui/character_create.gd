extends Control
## v83 Explorer creation with live composited preview; every allowed value comes from MakeCharInfo.

signal cancelled()

const LOGIN := "UI.wz/Login.img/"
## tier A: Login.img/avatarSel/0..8 labels/order; row pitch registered in period newchar_1.png, private v83-login-refs.
const FIELDS := ["face", "hair", "hair_colour", "skin", "top", "bottom", "shoes", "weapon", "gender"]
const INK := Color8(85, 51, 17) # tier C: existing login text palette.
const ERROR_INK := Color8(153, 34, 0) # tier C: existing validation-error palette.
## tier A/B: original v83 charSet/buttons/arrows registered in period newchar_1.png (about +/-2px).
## Source for this block: private spec32/v83-login-refs/layout.md and wz-layout-notes.md, NewChar.
const SETTINGS_AT := Vector2(470, 95)
const ROW_AT := Vector2(481, 198)
const ROW_PITCH := 19
const ARROW_X := Vector2(539, 667)
const LOOK_BUTTON_AT := [Vector2(508, 425), Vector2(582, 425)]
## tier B: period newchar_name_1.png estimates (+/-3px), same source; native WZ support determines button y.
const NAME_AT := Vector2(480, 95) # tier A/B: fresh WZ charName registration in newchar_name_1.png, +/-2px.
const NAME_INPUT := Rect2(510, 198, 140, 24)
const NAME_BUTTON_AT := [Vector2(508, 273), Vector2(582, 273)]
const PREVIEW_FEET := Vector2(398, 335)
## tier C: name-value area between registered WZ arrows, not later-client coordinates; same layout.md.
const VALUE_X := 556
const VALUE_SIZE := Vector2(109, 17)
## tier C: centered native Gender parchment and authored text/dropdown geometry; no period capture exists.
## Source: private spec32/v83-login-refs/wz-layout-notes.md, Gender; field is baked at text+(133,72).
const GENDER_AT := Vector2(219, 174)
const GENDER_TEXT_AT := Vector2(245, 198)
const GENDER_INPUT := Rect2(378, 270, 48, 19)
const GENDER_BUTTON_AT := [Vector2(355, 346), Vector2(430, 346)]
## tier B (advisory rectangle), C (offline copy, weapon strip below it, messages): period newchar_1.png / owner additions.
const ADVISORY := Rect2(120, 160, 195, 200)
const WEAPON_BOX := Rect2(120, 380, 195, 45)
const MESSAGE_BOX := Rect2(475, 365, 215, 45)

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
var _gender_pick: OptionButton
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
	_image_on(self, "Common/step/3", Vector2(0, 33)) # tier B: period newchar_1.png left step plaque.
	_button_on(self, "Common/BtStart", "Back", Vector2(0, 425), func() -> void: cancelled.emit()) # tier A/B: BtStart registered in charselect_1/newchar_1.
	var history := preload("res://scripts/ui/widgets/login_history_button.gd").new()
	history.position = Vector2(0, 375) # tier A/B: BtVAC registered in charselect_1/newchar_1, offline history action.
	history.pressed.connect(flow.goto_history)
	add_child(history)
	_image_on(_gender_surface, "Gender/backgrnd/0", GENDER_AT)
	_image_on(_gender_surface, "Gender/text/0", GENDER_TEXT_AT)
	_gender_pick = OptionButton.new()
	_gender_pick.name = "GenderValue"
	_gender_pick.position = GENDER_INPUT.position
	_gender_pick.size = GENDER_INPUT.size
	_gender_pick.add_item("Male")
	_gender_pick.add_item("Female")
	_gender_pick.add_theme_font_override("font", MapleText.font())
	_gender_pick.add_theme_font_size_override("font_size", MapleText.SMALL)
	_gender_pick.add_theme_color_override("font_color", INK)
	_gender_pick.add_theme_icon_override("arrow", ImageTexture.create_from_image(Image.create_empty(1, 1, false, Image.FORMAT_RGBA8)))
	for state: String in ["normal", "hover", "pressed", "focus"]:
		_gender_pick.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_gender_pick.item_selected.connect(func(index: int) -> void: cycle_option("gender", index - gender))
	_gender_surface.add_child(_gender_pick)
	_gender_ok = _button_on(_gender_surface, "Gender/BtYes", "OK", GENDER_BUTTON_AT[0], _advance_gender)
	_button_on(_gender_surface, "Gender/BtNo", "Cancel", GENDER_BUTTON_AT[1], func() -> void: cancelled.emit())
	_image_on(_name_surface, "NewChar/charName", NAME_AT)
	name_edit = LineEdit.new()
	name_edit.name = "CharacterName"
	name_edit.position = NAME_INPUT.position
	name_edit.size = NAME_INPUT.size
	name_edit.add_theme_font_override("font", MapleText.font())
	name_edit.add_theme_font_size_override("font_size", MapleText.SIZE)
	name_edit.add_theme_color_override("font_color", MapleText.WHITE)
	for state: String in ["normal", "focus"]:
		name_edit.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	_name_surface.add_child(name_edit)
	name_edit.tooltip_text = "4-12 letters A-Z and digits 0-9, unique among living characters"
	name_button = _button_on(_name_surface, "NewChar/BtYes", "OK", NAME_BUTTON_AT[0], _check_name)
	_button_on(_name_surface, "NewChar/BtNo", "Cancel", NAME_BUTTON_AT[1], _return_gender)
	_image_on(_look_surface, "NewChar/charSet", SETTINGS_AT)
	for i in FIELDS.size():
		var field: String = FIELDS[i]
		var y := ROW_AT.y + i * ROW_PITCH
		_image_on(_look_surface, "NewChar/avatarSel/%d/normal" % i, Vector2(ROW_AT.x, y))
		var previous := _button_on(_look_surface, "NewChar/BtLeft", "<", Vector2(ARROW_X.x, y), func() -> void: cycle_option(field, -1))
		previous.name = "Previous_" + field
		var label := _label_on(_look_surface, "", Vector2(VALUE_X, y), VALUE_SIZE)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		option_labels[field] = label
		var next := _button_on(_look_surface, "NewChar/BtRight", ">", Vector2(ARROW_X.y, y), func() -> void: cycle_option(field, 1))
		next.name = "Next_" + field
	avatar = AvatarRenderer.new()
	avatar.position = PREVIEW_FEET
	avatar.facing = 1
	add_child(avatar)
	_weapon_label = _label_on(_look_surface, "", WEAPON_BOX.position, WEAPON_BOX.size)
	_weapon_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# tier C: existing character-name treatment keeps canonical weapon details readable over foliage.
	_weapon_label.add_theme_color_override("font_color", NameTags.TEXT_COLOR)
	var plate := StyleBoxFlat.new()
	plate.bg_color = NameTags.BOX_COLOR
	_weapon_label.add_theme_stylebox_override("normal", plate)
	_look_ok = _button_on(_look_surface, "NewChar/BtYes", "Create", LOOK_BUTTON_AT[0], _create)
	_look_ok.name = "CreateCharacter"
	_look_ok.disabled = not model.available()
	_button_on(_look_surface, "NewChar/BtNo", "Cancel", LOOK_BUTTON_AT[1], _return_name)
	message = _label_on(self, "", MESSAGE_BOX.position, MESSAGE_BOX.size)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for surface: Control in [_name_surface, _look_surface]:
		var advisory := MapleText.new("", MapleText.SIZE, MapleText.BLACK)
		advisory.name = "CreationAdvisory"
		advisory.position = ADVISORY.position
		advisory.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		advisory.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var advisory_plate := StyleBoxFlat.new()
		advisory_plate.bg_color = Color(0.8, 0.87, 1.0, 0.8) # tier C: period newchar_1.png advisory tint.
		advisory_plate.set_content_margin_all(8) # tier C: offline advisory padding, same reference.
		advisory.add_theme_stylebox_override("normal", advisory_plate)
		advisory.size = ADVISORY.size
		surface.add_child(advisory)
		# Configure wrapping before assigning copy; Label otherwise retains its old unwrapped minimum width.
		advisory.text = "Begin as a Beginner. Your attacks fire automatically.\n\nChoose your job as you level up during a round.\n\nYour starting weapon uses its original WATK and attack speed.\n\nYour character continues into harder maps after each clear."
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
	message.position = MESSAGE_BOX.position
	message.size = MESSAGE_BOX.size
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
	_gender_pick.select(gender)
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
