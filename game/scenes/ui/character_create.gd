extends Control
## v83 Explorer creation with live composited preview; every allowed value comes from MakeCharInfo. Three steps: Name,
## Look, then the Job page (#286) listing JobTree.playable_jobs() in canonical order (Hero above the Arch Mage, #296); the character shows its 4th-job title from Lv1. The Look step's weapon row is the chosen job's creation weapon and has no arrows.

signal cancelled()

const LOGIN := "UI.wz/Login.img/"
## tier A: Login.img/avatarSel/0..8 labels/order; layout below is tier C, private v83-login-refs.
const FIELDS := ["face", "hair", "hair_colour", "skin", "top", "bottom", "shoes", "weapon", "gender"]
const INK := Color8(85, 51, 17) # tier C: existing login text palette.
const ERROR_INK := Color8(153, 34, 0) # tier C: existing validation-error palette.
## tier C: original v83 charSet/buttons/arrows matched to period newchar_1.png (about +/-2px).
## Source for this block: private spec32/v83-login-refs/layout.md and wz-layout-notes.md, NewChar.
const SETTINGS_AT := Vector2(470, 95)
const ROW_AT := Vector2(481, 198)
const ROW_PITCH := 19
const ARROW_X := Vector2(539, 667)
const LOOK_BUTTON_AT := [Vector2(508, 425), Vector2(582, 425)]
## tier C: matched to period newchar_name_1.png (+/-3px), same source.
const NAME_AT := Vector2(480, 95) # tier C: WZ charName matched to newchar_name_1.png, +/-2px.
const NAME_INPUT := Rect2(510, 198, 140, 24)
const NAME_BUTTON_AT := [Vector2(508, 273), Vector2(582, 273)]
const PREVIEW_FEET := Vector2(398, 335)
## tier C: name-value area between registered WZ arrows, not later-client coordinates; same layout.md.
const VALUE_X := 556
const VALUE_SIZE := Vector2(109, 17)
## tier C: advisory rectangle matched to period newchar_1.png; offline copy, weapon strip and messages are ours.
const ADVISORY := Rect2(120, 160, 195, 200)
const WEAPON_BOX := Rect2(120, 380, 195, 45)
const MESSAGE_BOX := Rect2(475, 365, 215, 45)
## tier C: the Job step lists one job per row inside the same charSet panel, from the first Look row down.
const JOB_ROW_SIZE := Vector2(190, 19)
const JOB_SELECTED := Color8(255, 170, 68, 170)
## Every Button state a job row draws in: the chosen row keeps its plate under the mouse (hover/pressed) too.
const JOB_ROW_STATES := ["normal", "hover", "pressed", "focus", "hover_pressed"]
## tier C (NL11 #410): the Job step's rows must end above this y (the charSet panel's lower edge, level with the message strip).
## Up to eight rows keep the 21 px pitch (19 px rows 2 px apart); a longer list shrinks its pitch to fit (nine rows: 18 px, ten rows: 16 px, eleven rows: 15 px).
const JOB_LIST_BOTTOM := 366.0

var flow: SceneFlow
var model: CharacterCreation
var gender := 0 # tier C: Male by default; the Look step's gender row is the only place it changes.
var phase := ""
var choices := {}
var name_edit: LineEdit
var create_button: WzButton
var message: Label
var avatar: AvatarRenderer
var option_labels: Dictionary = {}
var _weapon_label: Label
var name_button: WzButton
var _name_surface: Control
var _look_surface: Control
var _look_ok: WzButton
var _job_surface: Control
var _job_ok: WzButton
var _job_rows: Array[Button] = []
var _job_blurb: Label
var _jobs: JobTree
## The playable jobs in creation order, and the chosen one.
var job_ids: Array[int] = []
var job_id := 0
## Distance in px between two job rows (JOB_ROW_SIZE.y + 2 unless the list is too long to fit above JOB_LIST_BOTTOM).
var job_pitch := JOB_ROW_SIZE.y + 2.0


## Binds the owning coordinator; no save is written until Create is accepted.
func configure(p_flow: SceneFlow) -> void:
	flow = p_flow


func _ready() -> void:
	size = Vector2(800, 600)
	var library := UiArt.lib()
	var img := library.img(CharacterCreation.IMG) if library != null else null
	model = CharacterCreation.new(img.root if img != null else {})
	var data := DataRepo.load_all()
	_jobs = DataRepo.jobs(data)
	job_ids = _jobs.playable_jobs()
	job_id = _jobs.default_job()
	_name_surface = Control.new()
	_name_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_surface)
	_look_surface = Control.new()
	_look_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_look_surface)
	_image_on(self, "Common/step/3", Vector2(0, 33)) # tier C: placement matched to period newchar_1.png.
	_button_on(self, "Common/BtStart", "Back", Vector2(0, 425), func() -> void: cancelled.emit()) # tier C: matched to charselect_1/newchar_1.
	var history := preload("res://scripts/ui/widgets/login_history_button.gd").new()
	history.position = Vector2(0, 375) # tier C: matched to charselect_1/newchar_1 BtVAC, offline history action.
	history.pressed.connect(flow.goto_history)
	add_child(history)
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
	_button_on(_name_surface, "NewChar/BtNo", "Cancel", NAME_BUTTON_AT[1], _cancel_name)
	_image_on(_look_surface, "NewChar/charSet", SETTINGS_AT)
	for i in FIELDS.size():
		var field: String = FIELDS[i]
		var y := ROW_AT.y + i * ROW_PITCH
		_image_on(_look_surface, "NewChar/avatarSel/%d/normal" % i, Vector2(ROW_AT.x, y))
		var label := _label_on(_look_surface, "", Vector2(VALUE_X, y), VALUE_SIZE)
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		label.mouse_filter = Control.MOUSE_FILTER_STOP
		option_labels[field] = label
		if field == "weapon":
			continue # the job's creation weapon: shown, not chosen (#286)
		var previous := _button_on(_look_surface, "NewChar/BtLeft", "<", Vector2(ARROW_X.x, y), func() -> void: cycle_option(field, -1))
		previous.name = "Previous_" + field
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
	_look_ok = _button_on(_look_surface, "NewChar/BtYes", "OK", LOOK_BUTTON_AT[0], _choose_job)
	_look_ok.name = "ChooseJob"
	_look_ok.disabled = not model.available()
	_button_on(_look_surface, "NewChar/BtNo", "Cancel", LOOK_BUTTON_AT[1], _return_name)
	_build_job_surface()
	message = _label_on(self, "", MESSAGE_BOX.position, MESSAGE_BOX.size)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for surface: Control in [_name_surface, _look_surface, _job_surface]:
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
		advisory.text = "Choose your name, your look and your job. You are a 4th-job adventurer from level 1.\n\nYour attacks fire automatically.\n\nEvery round starts at level 1. You keep your equipment, scrolls and mesos, and unlock harder maps by clearing the ones before."
	if not model.available():
		_error("Creation options are missing. Re-import your v83 WZ data from the title screen.")
	else:
		message.text = "4-12 letters and digits."
		_refresh()
	name_edit.text_submitted.connect(func(_name: String) -> void: _check_name())
	_set_phase("name")


func _set_phase(p_phase: String) -> void:
	phase = p_phase
	_name_surface.visible = phase == "name"
	_look_surface.visible = phase == "look"
	_job_surface.visible = phase == "job"
	create_button = {"name": name_button, "look": _look_ok, "job": _job_ok}[phase]
	message.position = MESSAGE_BOX.position
	message.size = MESSAGE_BOX.size
	if phase == "name":
		name_edit.grab_focus()
	else:
		name_edit.release_focus()


## Name Cancel closes creation and returns to character select.
func _cancel_name() -> void:
	cancelled.emit()


func _return_name() -> void:
	message.text = "4-12 letters and digits."
	_set_phase("name")


## The Job step: the playable jobs in the settings panel, one row each, the chosen one highlighted.
func _build_job_surface() -> void:
	_job_surface = Control.new()
	_job_surface.name = "JobPage"
	_job_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_job_surface)
	_image_on(_job_surface, "NewChar/charSet", SETTINGS_AT)
	job_pitch = minf(JOB_ROW_SIZE.y + 2.0, floorf((JOB_LIST_BOTTOM - ROW_AT.y) / maxi(1, job_ids.size())))
	for i in job_ids.size():
		var row := Button.new()
		row.name = "Job_%d" % job_ids[i]
		row.flat = false # a flat button draws no stylebox, and the chosen row is a plate
		row.focus_mode = Control.FOCUS_NONE
		row.text = _jobs.name_of(job_ids[i])
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT # tier C: names share a left edge whatever their length
		row.position = Vector2(ROW_AT.x - 4.0, ROW_AT.y + i * job_pitch)
		row.size = Vector2(JOB_ROW_SIZE.x, job_pitch - 2.0)
		row.add_theme_font_override("font", MapleText.font())
		row.add_theme_font_size_override("font_size", MapleText.SMALL)
		for color: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			row.add_theme_color_override(color, INK)
		for state: String in JOB_ROW_STATES:
			row.add_theme_stylebox_override(state, StyleBoxEmpty.new())
		var job := job_ids[i]
		row.pressed.connect(func() -> void: select_job(job))
		_job_surface.add_child(row)
		_job_rows.append(row)
	_job_blurb = _label_on(_job_surface, "", WEAPON_BOX.position, WEAPON_BOX.size)
	_job_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_job_blurb.add_theme_color_override("font_color", NameTags.TEXT_COLOR)
	var plate := StyleBoxFlat.new()
	plate.bg_color = NameTags.BOX_COLOR
	_job_blurb.add_theme_stylebox_override("normal", plate)
	_job_ok = _button_on(_job_surface, "NewChar/BtYes", "Create", LOOK_BUTTON_AT[0], _create)
	_job_ok.name = "CreateCharacter"
	_job_ok.disabled = job_ids.is_empty()
	_button_on(_job_surface, "NewChar/BtNo", "Cancel", LOOK_BUTTON_AT[1], _return_look)
	select_job(job_id)


func _choose_job() -> void:
	if _look_ok.disabled:
		return
	message.text = "Choose your job."
	_set_phase("job")


func _return_look() -> void:
	message.text = ""
	_set_phase("look")


## Chooses one of the playable jobs: highlights its row, names the title it has from Lv1 and previews its weapon.
func select_job(id: int) -> void:
	if id not in job_ids:
		return
	job_id = id
	for i in _job_rows.size():
		var on := job_ids[i] == id
		for state: String in JOB_ROW_STATES:
			_job_rows[i].add_theme_stylebox_override(state, _row_plate(on))
		for color: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
			_job_rows[i].add_theme_color_override(color, ERROR_INK if on else INK)
	_job_blurb.text = "%s   ·   Lv. 1" % _jobs.name_of(id)
	if model.available():
		_refresh()
		if not _weapon_label.text.is_empty():
			_job_blurb.text += "\n" + _weapon_label.text


static func _row_plate(on: bool) -> StyleBox:
	if not on:
		return StyleBoxEmpty.new()
	var plate := StyleBoxFlat.new()
	plate.bg_color = JOB_SELECTED
	plate.set_corner_radius_all(3)
	return plate


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
	var weapon := _jobs.creation_weapon(job_id)
	for field: String in CharacterCreation.FIELDS:
		var id := weapon if field == "weapon" else model.value(gender, field, choices)
		var text := "" if field == "weapon" else model.option_name(gender, field, id)
		if text.is_empty() and UiArt.lib() != null:
			text = UiArt.lib().string_name("Eqp", id)
		if text.is_empty():
			text = str(id)
		option_labels[field].text = text
		option_labels[field].tooltip_text = "%s (%d)" % [text, id]
	avatar.set_look(DataRepo.character_look({"look": model.look(gender, choices),
		"beginner_weapon": weapon, "job_id": 0}, DataRepo.load_all()))
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
	if flow.create_character(name_edit.text, model.look(gender, choices), job_id) < 0:
		_error(flow.action_error)


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
	elif phase == "job" and not job_ids.is_empty():
		var step := MapleWindow.vertical_step(event)
		if step != 0:
			select_job(job_ids[clampi(job_ids.find(job_id) + step, 0, job_ids.size() - 1)])
			get_viewport().set_input_as_handled()
		elif MapleWindow.is_confirm(event):
			_job_ok.pressed.emit()
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
	var box := Vector2(16, 18) if path.contains("Left") or path.contains("Right") else Vector2(60, 24)
	var button := WzButton.for_action(LOGIN + path, fallback, box, action)
	button.position = at
	parent.add_child(button)
	return button
