extends TestCase
## The creation page with Bishop (232) among the playable jobs (spec #372, BS9 #381; the Bishop copy of the I/L page test). Bishop
## is shipped playable since BS10 (the page lists `playable_jobs()`).
## Job-page tests need the cache because Look OK requires the hair/face columns; the data-level tests run without it.

const CREATE := preload("res://scenes/ui/character_create.gd")

var save_path := TestCase.test_dir("creation_bishop/save.json")
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
	var data := DataRepo.load_all()
	return JobTree.from_data(data.jobs, data.jobs_survivor)


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


func test_shipped_bishop_is_playable_in_canonical_order() -> void:
	var mirrored := _tree()
	assert_true(mirrored.job(232).playable)
	assert_eq(mirrored.playable_jobs(), [112, 122, 132, 212, 222, 232, 312, 412, 512] as Array[int])
	assert_eq(mirrored.name_of(232), "Bishop", "the name is the canonical job list's")
	assert_eq(mirrored.default_job(), 212, "F/P stays the default")
	assert_eq(mirrored.creation_weapon(232), 1372005, "the Wooden Wand")


func test_rows_follow_the_playable_jobs_and_212_is_chosen() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "BsRows01")
	var expected := _tree().playable_jobs()
	assert_eq(creation.job_ids, expected)
	assert_eq(creation.job_id, 212, "the default job is chosen when the page opens")
	var mage := _row(creation, 212)
	var bishop := _row(creation, 232)
	assert_true(mage != null and bishop != null, "one row per playable job")
	assert_eq(bishop.text, "Bishop")
	assert_true(bishop.size.x >= CREATE.JOB_ROW_SIZE.x)
	assert_eq(bishop.position.x, mage.position.x, "rows share a column")
	assert_eq(_row(creation, expected[0]).position.y, CREATE.ROW_AT.y, "the first row starts at the first Look row")
	var pitch: float = creation.job_pitch
	assert_eq(bishop.position.y - _row(creation, expected[0]).position.y, pitch * expected.find(232), "rows are one pitch apart in canonical order")
	assert_eq(bishop.alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_true(bishop.get_theme_stylebox("normal") is StyleBoxEmpty, "Bishop is not highlighted until chosen")


func test_clicking_bishop_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "BsClick01")
	_row(creation, 232).pressed.emit()
	assert_eq(creation.job_id, 232)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false(_row(creation, 232).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state (under the mouse too)" % state)
		assert_true(_row(creation, 212).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Bishop"), "the blurb names the chosen job")
	creation.select_job(999)
	assert_eq(creation.job_id, 232, "an id that is not listed changes nothing")


func test_up_and_down_step_through_every_row_and_clamp_at_the_ends() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "BsKeys01")
	var ids: Array = _tree().playable_jobs()
	creation.select_job(ids[ids.size() - 1])
	assert_eq(creation.job_id, ids.back(), "last playable row")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, ids.back(), "Down at the last row stays")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, ids[ids.size() - 2], "Up from the last row is the row above")
	creation.select_job(222)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 232, "Down from I/L is Bishop")
	for i in ids.size():
		creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, ids[0], "Up clamps at the first row")
	for i in ids.size():
		creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, ids.back())


func test_arrow_keys_do_nothing_off_the_job_page() -> void:
	var flow := _flow()
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	var before: int = creation.job_id
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, before, "only the Job page steps jobs")


func test_the_weapon_box_follows_the_chosen_jobs_creation_weapon() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "BsWeapon01")
	creation.select_job(232)
	assert_eq(creation.avatar.look.equips[-1], 1372005, "the preview wears the wand")
	assert_true(String(creation.option_labels.weapon.text).contains("Wand"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._weapon_label.text).contains("WATK") or String(creation._weapon_label.text).contains("MATK"),
		"the weapon box shows its stats: %s" % creation._weapon_label.text)
	assert_true(String(creation._job_blurb.text).contains(creation._weapon_label.text), "the Job page blurb repeats the weapon box")


func test_create_makes_a_bishop_with_its_wand_and_a_separate_f_p_in_the_next_slot() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "BsOne01")
	creation.select_job(232)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var bishop: Dictionary = flow.save.slot(0).character
	assert_eq(bishop.job_id, 232)
	assert_eq(bishop.tiers_unlocked, 1)
	assert_eq(int(bishop.equipment.worn.weapon.id), 1372005, "Bishop starts with the Wooden Wand")
	assert_eq(CharacterSnapshot.validation_error(bishop), "")
	flow.goto_character_select()
	creation = _job_page(flow, "FpOne01")
	creation.select_job(212)
	creation.create_button.pressed.emit()
	assert_eq(flow.save.slot(1).character.job_id, 212)
	assert_eq(flow.save.slot(0).character.job_id, 232, "the first slot is unchanged")
	assert_eq(flow.save.slot(0).character.tiers_unlocked, 1, "each job has its own tier ladder")


func test_bishop_is_refused_when_the_mirror_goes_away_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "Refused01")
	creation.select_job(232)
	DataRepo.patch = {"jobs_survivor": {"jobs": {"232": {"playable": false}}}}
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_true(flow.save.slot(0).is_empty(), "nothing was saved")
