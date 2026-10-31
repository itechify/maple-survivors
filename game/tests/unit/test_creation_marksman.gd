extends TestCase
## The creation Job page with Marksman (spec #360, MS10 #370). Marksman ships `playable: true` (MS11 #371), so the page is
## verified two ways: the shipped list (the real row count) and a list the `DataRepo.patch` seam reduces to two jobs (layout,
## selection, keyboard step, weapon box); a `playable: false` patch tests the refusal.
## The expected lists are derived from the shipped `playable_jobs()` rather than pinned, so another class line flipping `playable`
## (Night Lord, Corsair) never breaks this file. The Job page needs the cache (Look OK stays disabled until the hair/face columns
## exist), so every test that opens it calls `require_cache()`; the data-level tests run in CI.

const CREATE := preload("res://scenes/ui/character_create.gd")
const DISABLED := {"jobs_survivor": {"jobs": {"322": {"playable": false}}}}

var save_path := TestCase.test_dir("creation_marksman/save.json")
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


## A patch that disables every shipped playable job, leaving 322 as the only other row besides 212.
func _reduced() -> Dictionary:
	var jobs := {}
	for id: int in _tree().playable_jobs():
		if id != 212 and id != 322:
			jobs[str(id)] = {"playable": false}
	return {"jobs_survivor": {"jobs": jobs}}


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


func test_shipped_marksman_is_playable_right_after_bowmaster_and_a_disabled_patch_unlists_it() -> void:
	var shipped := _tree()
	assert_true(shipped.job(322).playable)
	var ids := shipped.playable_jobs()
	assert_true(322 in ids)
	assert_eq(shipped.default_job(), 212, "the pin keeps 212 the default with Marksman playable")
	assert_eq(ids.find(322), ids.find(312) + 1, "canonical order: Marksman follows Bowmaster (no job between 312 and 322)")
	assert_eq(shipped.name_of(322), "Marksman")
	assert_eq(shipped.creation_weapon(322), 1462001, "the Crossbow")
	DataRepo.patch = DISABLED.duplicate(true)
	var disabled := _tree()
	assert_false(disabled.job(322).playable)
	var rest := ids.duplicate()
	rest.erase(322)
	assert_eq(disabled.playable_jobs(), rest, "the other rows keep their order")


func test_the_shipped_page_lists_marksman_and_unlisted_jobs_change_nothing() -> void:
	if not require_cache():
		return
	DataRepo.patch = DISABLED.duplicate(true)
	var without := _job_page(_flow(), "MsDisabled01")
	assert_true(_row(without, 322) == null, "no Marksman row when disabled")
	without.select_job(322)
	assert_eq(without.job_id, 212, "an unlisted job changes nothing")
	DataRepo.patch = {}
	var creation := _job_page(_flow(), "MsShipped01")
	assert_eq(creation.job_ids, _tree().playable_jobs())
	assert_true(_row(creation, 322) != null, "the shipped list has the Marksman row")
	var last := _row(creation, creation.job_ids[creation.job_ids.size() - 1])
	assert_true(last.position.y + creation.job_pitch - 2.0 <= CREATE.JOB_LIST_BOTTOM, "the shipped list fits above the message strip")


func test_every_shipped_row_is_one_pitch_below_the_last_and_fits_above_the_message_strip() -> void:
	if not require_cache():
		return
	var ids := _tree().playable_jobs()
	var creation := _job_page(_flow(), "MsRows01")
	assert_eq(creation.job_ids, ids)
	assert_eq(creation.job_id, 212, "the default job is chosen when the page opens")
	var pitch: float = minf(CREATE.JOB_ROW_SIZE.y + 2.0, floorf((CREATE.JOB_LIST_BOTTOM - CREATE.ROW_AT.y) / ids.size()))
	assert_eq(creation.job_pitch, pitch, "the pitch shrinks only as far as the list needs")
	for i in ids.size():
		var row := _row(creation, ids[i])
		assert_true(row != null, "row for %d" % ids[i])
		if row == null:
			return
		assert_eq(row.position.y, CREATE.ROW_AT.y + i * creation.job_pitch, "row %d is one pitch below the one above" % i)
		assert_eq(row.position.x, _row(creation, ids[0]).position.x, "rows share a column")
	var marksman := _row(creation, 322)
	assert_eq(marksman.text, "Marksman")
	assert_eq(marksman.position.y - _row(creation, 312).position.y, creation.job_pitch, "Marksman is the row below Bowmaster")
	assert_true(marksman.get_theme_stylebox("normal") is StyleBoxEmpty, "Marksman is not highlighted until chosen")
	assert_false(_row(creation, 212).get_theme_stylebox("normal") is StyleBoxEmpty, "212 is highlighted")
	var end: float = _row(creation, ids[ids.size() - 1]).position.y + creation.job_pitch - 2.0 # the intended row height; a headless Button measures taller
	assert_true(end <= CREATE.JOB_LIST_BOTTOM, "the last row ends at %s, above %s" % [end, CREATE.JOB_LIST_BOTTOM])
	assert_true(end <= CREATE.MESSAGE_BOX.position.y, "and clear of the message strip")


func test_clicking_marksman_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "MsClick01")
	_row(creation, 322).pressed.emit()
	assert_eq(creation.job_id, 322)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false(_row(creation, 322).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state (under the mouse too)" % state)
		assert_true(_row(creation, 212).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Marksman"), "the blurb names the chosen job: %s" % creation._job_blurb.text)


func test_up_and_down_step_through_every_row_including_marksman_and_clamp() -> void:
	if not require_cache():
		return
	var ids := _tree().playable_jobs()
	var creation := _job_page(_flow(), "MsKeys01")
	creation.select_job(312)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 322, "Down from Bowmaster is Marksman")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 312, "Up from Marksman is Bowmaster")
	for i in ids.size():
		creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, ids[ids.size() - 1], "Down at the last row stays")
	for i in ids.size():
		creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, ids[0])
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, ids[0], "Up at the first row stays")


func test_a_reduced_list_lays_out_two_rows_and_steps_between_them() -> void:
	if not require_cache():
		return
	DataRepo.patch = _reduced()
	var creation := _job_page(_flow(), "MsTwo01")
	assert_eq(creation.job_ids, [212, 322] as Array[int])
	assert_eq(creation.job_id, 212)
	assert_eq(_row(creation, 212).position.y, CREATE.ROW_AT.y, "the first row starts at the first Look row")
	assert_eq(creation.job_pitch, CREATE.JOB_ROW_SIZE.y + 2.0, "two rows keep the full pitch")
	assert_eq(_row(creation, 322).position.y - _row(creation, 212).position.y, creation.job_pitch)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 322)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 322)
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 212)


func test_the_weapon_box_shows_the_crossbow() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "MsWeapon01")
	creation.select_job(322)
	assert_eq(creation.avatar.look.equips[-1], 1462001, "the preview wears the Crossbow")
	assert_true(String(creation.option_labels.weapon.text).contains("Crossbow"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._weapon_label.text).contains("WATK"), "the weapon box shows its stats: %s" % creation._weapon_label.text)
	assert_true(String(creation._job_blurb.text).contains(creation._weapon_label.text), "the blurb repeats the weapon box")
	creation.select_job(212)
	assert_eq(creation.avatar.look.equips[-1], 1372005, "the preview swaps back to the wand")


func test_create_makes_a_marksman_with_its_crossbow_and_separate_ladders() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "MsOne01")
	creation.select_job(322)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var archer: Dictionary = flow.save.slot(0).character
	assert_eq(archer.job_id, 322)
	assert_eq(archer.tiers_unlocked, 1)
	assert_eq(int(archer.equipment.worn.weapon.id), 1462001, "a Marksman starts with the Crossbow")
	assert_eq(CharacterSnapshot.validation_error(archer), "")
	assert_eq(WeaponInfo.family(1462001), "crossbow")
	flow.goto_character_select()
	creation = _job_page(flow, "MageOne03")
	creation.create_button.pressed.emit()
	assert_eq(flow.save.slot(1).character.job_id, 212, "the untouched page still creates the default job")
	assert_eq(flow.save.slot(0).character.job_id, 322, "the first slot is unchanged")


func test_marksman_is_refused_when_it_is_disabled_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "MsRefused01")
	creation.select_job(322)
	DataRepo.patch = DISABLED.duplicate(true)
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_true(flow.save.slot(0).is_empty(), "nothing was saved")
