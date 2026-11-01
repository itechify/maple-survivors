extends TestCase
## The creation Job page with Shadower (spec #425, SH13 #438; playable since SH14 #439). The page is verified on the shipped
## eleven-row list, on the ten-row list an UNPLAYABLE patch (`DataRepo.patch`) gives, and on lists the patch reduces to two jobs
## (layout, selection, keyboard step, weapon box). Making Shadower unplayable after the selection drives the refusal test.
## The Job page needs the cache (Look OK stays disabled until the hair/face columns exist), so every test that opens it calls
## `require_cache()`; the data-level tests run in CI.

const CREATE := preload("res://scenes/ui/character_create.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
## Shadower off: the ten-row page of the jobs before SH14 (Night Lord, then Buccaneer).
const UNPLAYABLE := {"jobs_survivor": {"jobs": {"422": {"playable": false}}}}
## Every other playable job disabled: the page has the two rows 212 and 422.
const REDUCED := {"jobs_survivor": {"jobs": {"112": {"playable": false}, "122": {"playable": false}, "132": {"playable": false},
	"222": {"playable": false}, "232": {"playable": false}, "312": {"playable": false}, "412": {"playable": false}, "512": {"playable": false},
	"522": {"playable": false}, "422": {"playable": true}}}}
const SHADOWER_ROW := 8 ## zero-based row of 422 on the eleven-row page: after Night Lord (412), before Buccaneer (512)
const IDS: Array[int] = [112, 122, 132, 212, 222, 232, 312, 412, 422, 512, 522]

var save_path := TestCase.test_dir("creation_shadower/save.json")
var _nodes: Array[Node] = []


func before_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
	DataRepo.patch = {}


func after_each() -> void:
	DataRepo.patch = {}
	for n in _nodes:
		if is_instance_valid(n):
			n.free()
	_nodes.clear()
	TestCase.remove_tree(save_path.get_base_dir())


func _tree() -> JobTree:
	return DataRepo.jobs(DataRepo.load_all())


func _flow() -> SceneFlow:
	var flow := SceneFlow.new()
	_nodes.append(flow)
	flow.deferred_swaps = false
	flow.save = SaveData.new(save_path)
	var host := Node.new()
	(Engine.get_main_loop() as SceneTree).current_scene.add_child(host)
	_nodes.append(host)
	flow.host = host
	return flow


## Creation on its Job page: name -> look -> job (cache only).
func _job_page(flow: SceneFlow, character_name: String) -> Control:
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	creation.name_edit.text = character_name
	creation.create_button.pressed.emit()
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job")
	return creation


func _key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.pressed = true
	return e


func _row(creation: Control, id: int) -> Button:
	return creation.find_child("Job_%d" % id, true, false) as Button


func test_shipped_shadower_is_playable_between_night_lord_and_buccaneer_with_212_the_default() -> void:
	var shipped := _tree()
	assert_true(shipped.job(422).playable, "SH14 flipped it")
	assert_eq(shipped.playable_jobs(), IDS, "canonical order, eleven rows")
	assert_eq(shipped.playable_jobs().find(422), SHADOWER_ROW)
	assert_eq(shipped.default_job(), 212, "the pin keeps 212 the default with eleven playable jobs")
	assert_eq(shipped.name_of(422), "Shadower")
	assert_eq(shipped.creation_weapon(422), 1332005, "the Razor")
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	var patched := _tree()
	assert_false(patched.job(422).playable, "the patch seam still turns it off")
	assert_eq(patched.playable_jobs(), [112, 122, 132, 212, 222, 232, 312, 412, 512, 522] as Array[int], "unplayable again: ten rows")


func test_an_unplayable_shadower_has_no_row_and_the_page_keeps_the_ten_row_pitch() -> void:
	if not require_cache():
		return
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	var creation := _job_page(_flow(), "ShShip01")
	var ids: Array[int] = [112, 122, 132, 212, 222, 232, 312, 412, 512, 522]
	assert_eq(creation.job_ids, ids)
	assert_true(_row(creation, 422) == null, "no Shadower row while it is unplayable")
	assert_eq(creation.job_pitch, 16.0)


func test_eleven_rows_in_canonical_order_one_pitch_apart_with_212_chosen() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "ShRows01")
	var ids: Array[int] = IDS.duplicate()
	assert_eq(creation.job_ids, ids)
	assert_eq(creation.job_id, 212, "the default job is chosen when the page opens")
	for i in ids.size():
		var row := _row(creation, ids[i])
		assert_true(row != null, "row for %d" % ids[i])
		if row == null:
			return
		assert_eq(row.position.y, CREATE.ROW_AT.y + i * creation.job_pitch, "row %d is one pitch below the one above" % i)
		assert_eq(row.position.x, _row(creation, 112).position.x, "rows share a column")
		assert_true(row.size.x >= CREATE.JOB_ROW_SIZE.x, "row %d is at least the row width" % i)
	var shadower := _row(creation, 422)
	assert_eq(shadower.text, "Shadower")
	assert_true(shadower.get_theme_stylebox("normal") is StyleBoxEmpty, "Shadower is not highlighted until chosen")
	assert_false(_row(creation, 212).get_theme_stylebox("normal") is StyleBoxEmpty, "212 is highlighted")
	# Eleven rows: the pitch shrinks to floor((JOB_LIST_BOTTOM - ROW_AT.y) / 11) = 15 px so the last row still ends above the
	# "Choose your job." message strip.
	assert_eq(creation.job_pitch, 15.0)
	var end: float = _row(creation, 522).position.y + creation.job_pitch - 2.0 # the intended row height; a headless Button measures taller
	assert_true(end <= CREATE.JOB_LIST_BOTTOM, "the last row ends at %s, above %s" % [end, CREATE.JOB_LIST_BOTTOM])
	assert_true(end <= CREATE.MESSAGE_BOX.position.y, "and clear of the message strip")


func test_clicking_shadower_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "ShClick01")
	_row(creation, 422).pressed.emit()
	assert_eq(creation.job_id, 422)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false(_row(creation, 422).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state (under the mouse too)" % state)
		assert_true(_row(creation, 212).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Shadower"), "the blurb names the chosen job: %s" % creation._job_blurb.text)


func test_up_and_down_step_through_all_eleven_rows_and_clamp() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "ShKeys01")
	creation.select_job(312)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 412, "Down from Bowmaster is Night Lord")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 422, "Down from Night Lord is Shadower")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 512, "Down from Shadower is Buccaneer")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 422, "Up from Buccaneer is Shadower")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 412)
	creation.select_job(522)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 522, "Down at the last row stays")
	for i in 10:
		creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112)
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112, "Up at the first row stays")


func test_a_reduced_list_lays_out_two_rows_and_steps_between_them() -> void:
	if not require_cache():
		return
	DataRepo.patch = REDUCED.duplicate(true)
	var creation := _job_page(_flow(), "ShTwo01")
	assert_eq(creation.job_ids, [212, 422] as Array[int])
	assert_eq(creation.job_id, 212)
	assert_eq(_row(creation, 212).position.y, CREATE.ROW_AT.y, "the first row starts at the first Look row")
	assert_eq(creation.job_pitch, CREATE.JOB_ROW_SIZE.y + 2.0, "two rows keep the full pitch")
	assert_eq(_row(creation, 422).position.y - _row(creation, 212).position.y, creation.job_pitch)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 422)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 422)
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 212)


func test_the_weapon_box_shows_the_razor() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "ShWeapon01")
	creation.select_job(422)
	assert_eq(creation.avatar.look.equips[-1], 1332005, "the preview wears the Razor")
	assert_true(String(creation.option_labels.weapon.text).contains("Razor"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._weapon_label.text).contains("WATK"), "the weapon box shows its stats: %s" % creation._weapon_label.text)
	assert_true(String(creation._job_blurb.text).contains(creation._weapon_label.text), "the blurb repeats the weapon box")
	creation.select_job(212)
	assert_eq(creation.avatar.look.equips[-1], 1372005, "the preview swaps back to the wand")
	creation.select_job(412)
	assert_ne(creation.avatar.look.equips[-1], 1332005, "and a Night Lord next to it does not keep the dagger")


func test_create_makes_a_shadower_with_the_razor() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "ShOne01")
	creation.select_job(422)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var shadower_character: Dictionary = flow.save.slot(0).character
	assert_eq(shadower_character.job_id, 422)
	assert_eq(shadower_character.cleared_regions, [], "a new Shadower has cleared nothing (only Henesys open)")
	assert_eq(int(shadower_character.equipment.worn.weapon.id), 1332005, "a Shadower starts with the Razor")
	assert_eq(CharacterSnapshot.validation_error(shadower_character), "")
	assert_eq(WeaponInfo.family(1332005), "dagger")
	flow.goto_character_select()
	creation = _job_page(flow, "MageOne03")
	creation.create_button.pressed.emit()
	assert_eq(flow.save.slot(1).character.job_id, 212, "the untouched page still creates the default job")
	assert_eq(flow.save.slot(0).character.job_id, 422, "the first slot is unchanged")


func test_shadower_is_refused_when_it_stops_being_playable_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "ShRefused01")
	creation.select_job(422)
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_true(flow.save.slot(0).is_empty(), "nothing was saved")


func test_a_bare_job_tool_run_uses_the_creation_razor_and_no_ammo() -> void:
	var setup := RF.setup("quiet", 438, RF.quiet_data())
	setup.job = 422
	setup.equipment_info.merge({1332005: {"incPAD": 20, "attackSpeed": 4, "tuc": 7}}, true)
	var w := RunWorld.new(setup)
	assert_eq(int(w.equipment.worn.weapon.id), 1332005)
	assert_eq(w.ammo_id(), 0, "a dagger throws nothing")
	assert_true(1332005 in CharacterSnapshot.held_item_ids({"job_id": 422}, w.jobs))
