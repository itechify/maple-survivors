extends TestCase
## The creation Job page with Night Lord (spec #383, NL11 #410, NL12 #411). Night Lord ships `playable: true` since NL12, so the
## shipped page has eleven rows (Night Lord between Bowmaster and Shadower, at the 15 px pitch); a list the `DataRepo.patch`
## seam reduces to two jobs checks layout, selection, keyboard step and weapon box, and a patch that makes 412 unplayable again
## checks the refusal.
## The Job page needs the cache (Look OK stays disabled until the hair/face columns exist), so every test that opens it calls
## `require_cache()`; the data-level tests run in CI.

const CREATE := preload("res://scenes/ui/character_create.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
## 412 and 522 both off: the eight-row page the pre-Night-Lord tests describe (Shadower, 422, and Corsair, 522, are also playable on the merged list).
const UNPLAYABLE := {"jobs_survivor": {"jobs": {"412": {"playable": false}, "422": {"playable": false}, "522": {"playable": false}}}}
## Every other playable job disabled: the page has the two rows 212 and 412.
const REDUCED := {"jobs_survivor": {"jobs": {"112": {"playable": false}, "122": {"playable": false}, "132": {"playable": false},
	"222": {"playable": false}, "232": {"playable": false}, "312": {"playable": false}, "422": {"playable": false}, "512": {"playable": false}, "522": {"playable": false}}}}
const NIGHT_LORD_ROW := 7 ## zero-based row of 412: after Bowmaster (312), before Shadower (422)

var save_path := TestCase.test_dir("creation_night_lord/save.json")
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


func test_shipped_night_lord_is_playable_between_bowmaster_and_buccaneer() -> void:
	var shipped := _tree()
	assert_true(shipped.job(412).playable, "NL12 flipped it")
	assert_eq(shipped.playable_jobs(), [112, 122, 132, 212, 222, 232, 312, 412, 422, 512, 522] as Array[int], "canonical order, eleven rows")
	assert_eq(shipped.default_job(), 212, "the pin keeps 212 the default with eleven playable jobs")
	assert_eq(shipped.name_of(412), "Night Lord")
	assert_eq(shipped.creation_weapon(412), 1472000, "the Garnier")
	assert_eq(shipped.playable_jobs().find(412), NIGHT_LORD_ROW)
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	var patched := _tree()
	assert_false(patched.job(412).playable)
	assert_eq(patched.playable_jobs(), [112, 122, 132, 212, 222, 232, 312, 512] as Array[int], "unplayable again: eight rows")


func test_an_unplayable_night_lord_has_no_row_and_the_page_keeps_the_original_pitch() -> void:
	if not require_cache():
		return
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	var creation := _job_page(_flow(), "NlShipped01")
	assert_eq(creation.job_ids, _tree().playable_jobs())
	assert_eq(creation.job_pitch, CREATE.JOB_ROW_SIZE.y + 2.0, "eight rows keep the 21 px pitch")
	assert_true(_row(creation, 512).position.y + creation.job_pitch - 2.0 <= CREATE.JOB_LIST_BOTTOM)
	assert_true(_row(creation, 412) == null, "no Night Lord row while it is unplayable")
	creation.select_job(412)
	assert_eq(creation.job_id, 212, "an unlisted job changes nothing")


func test_eleven_rows_in_canonical_order_one_pitch_apart_with_212_chosen() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "NlRows01")
	var ids: Array[int] = [112, 122, 132, 212, 222, 232, 312, 412, 422, 512, 522]
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
	var nl := _row(creation, 412)
	assert_eq(nl.text, "Night Lord")
	assert_true(nl.get_theme_stylebox("normal") is StyleBoxEmpty, "Night Lord is not highlighted until chosen")
	assert_false(_row(creation, 212).get_theme_stylebox("normal") is StyleBoxEmpty, "212 is highlighted")
	# Eleven rows at the eight-row pitch (21 px) would run past the sign's panel and under the "Choose your job." message: the
	# pitch shrinks to 15 px so the last row ends above CREATE.JOB_LIST_BOTTOM.
	assert_eq(creation.job_pitch, 15.0)
	var end: float = _row(creation, 522).position.y + creation.job_pitch - 2.0 # the intended row height; a headless Button measures taller
	assert_true(end <= CREATE.JOB_LIST_BOTTOM, "the last row ends at %s, above %s" % [end, CREATE.JOB_LIST_BOTTOM])
	assert_true(end <= CREATE.MESSAGE_BOX.position.y, "and clear of the message strip")


func test_clicking_night_lord_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "NlClick01")
	_row(creation, 412).pressed.emit()
	assert_eq(creation.job_id, 412)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false(_row(creation, 412).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state (under the mouse too)" % state)
		assert_true(_row(creation, 212).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Night Lord"), "the blurb names the chosen job: %s" % creation._job_blurb.text)


func test_up_and_down_step_through_all_eleven_rows_and_clamp() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "NlKeys01")
	creation.select_job(312)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 412, "Down from Bowmaster is Night Lord")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 422, "Down from Night Lord is Shadower")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 512, "Down from Shadower is Buccaneer")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 522, "Down from Buccaneer is Corsair")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 522, "Down at the last row stays")
	creation._input(_key(KEY_UP))
	creation._input(_key(KEY_UP))
	creation._input(_key(KEY_UP))
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 312, "Up from Corsair, Buccaneer, Shadower and Night Lord is Bowmaster")
	for i in 9:
		creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112)
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112, "Up at the first row stays")


func test_a_reduced_list_lays_out_two_rows_and_steps_between_them() -> void:
	if not require_cache():
		return
	DataRepo.patch = REDUCED.duplicate(true)
	var creation := _job_page(_flow(), "NlTwo01")
	assert_eq(creation.job_ids, [212, 412] as Array[int])
	assert_eq(creation.job_id, 212)
	assert_eq(_row(creation, 212).position.y, CREATE.ROW_AT.y, "the first row starts at the first Look row")
	assert_eq(creation.job_pitch, CREATE.JOB_ROW_SIZE.y + 2.0, "two rows keep the full pitch")
	assert_eq(_row(creation, 412).position.y - _row(creation, 212).position.y, creation.job_pitch)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 412)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 412)
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 212)


func test_the_weapon_box_shows_the_garnier() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "NlWeapon01")
	creation.select_job(412)
	assert_eq(creation.avatar.look.equips[-1], 1472000, "the preview wears the Garnier")
	assert_true(String(creation.option_labels.weapon.text).contains("Garnier"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._weapon_label.text).contains("WATK"), "the weapon box shows its stats: %s" % creation._weapon_label.text)
	assert_true(String(creation._job_blurb.text).contains(creation._weapon_label.text), "the blurb repeats the weapon box")
	creation.select_job(212)
	assert_eq(creation.avatar.look.equips[-1], 1372005, "the preview swaps back to the wand")


func test_create_makes_a_night_lord_with_its_garnier_and_separate_ladders() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "NlOne01")
	creation.select_job(412)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var thief: Dictionary = flow.save.slot(0).character
	assert_eq(thief.job_id, 412)
	assert_eq(thief.cleared_regions, [], "a new Night Lord has cleared nothing (only Henesys open)")
	assert_eq(int(thief.equipment.worn.weapon.id), 1472000, "a Night Lord starts with the Garnier")
	assert_eq(CharacterSnapshot.validation_error(thief), "")
	assert_eq(WeaponInfo.family(1472000), "claw")
	flow.goto_character_select()
	creation = _job_page(flow, "MageOne03")
	creation.create_button.pressed.emit()
	assert_eq(flow.save.slot(1).character.job_id, 212, "the untouched page still creates the default job")
	assert_eq(flow.save.slot(0).character.job_id, 412, "the first slot is unchanged")


func test_night_lord_is_refused_when_it_becomes_unplayable_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "NlRefused01")
	creation.select_job(412)
	DataRepo.patch = UNPLAYABLE.duplicate(true)
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_true(flow.save.slot(0).is_empty(), "nothing was saved")


func test_a_bare_job_tool_run_uses_the_creation_claw_and_the_beginner_thief_stars() -> void:
	var setup := RF.setup("quiet", 410, RF.quiet_data())
	setup.job = 412
	setup.equipment_info.merge({1472000: {"incPAD": 10, "attackSpeed": 6, "tuc": 7}}, true)
	var w := RunWorld.new(setup)
	assert_eq(int(w.equipment.worn.weapon.id), 1472000)
	assert_eq(w.ammo_id(), 2070015, "the Beginner Thief's stars")
	assert_true(1472000 in CharacterSnapshot.held_item_ids({"job_id": 412}, w.jobs))
