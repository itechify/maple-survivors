extends TestCase
## The shipped I/L creation page: canonical job rows, selection, weapons and separate character slots.
## Job-page tests need the cache because Look OK requires the hair/face columns. Data assertions run cache-free.

const CREATE := preload("res://scenes/ui/character_create.gd")

var save_path := TestCase.test_dir("creation_il/save.json")
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


## The shipped playable jobs, in canonical order.
func _expected() -> Array[int]:
	return _tree().playable_jobs()


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


func test_shipped_il_is_playable_in_canonical_order() -> void:
	var tree := _tree()
	assert_true(tree.job(222).playable)
	var playable := tree.playable_jobs()
	assert_true(222 in playable and playable.find(212) < playable.find(222), "I/L follows F/P")
	assert_eq(tree.name_of(222), "Arch Mage (Ice, Lightning)", "the name is the canonical job list's")
	assert_eq(tree.default_job(), 212, "F/P stays the default (Hero's pin on a branch that has it, canonical order here)")


func test_rows_follow_the_playable_jobs_names_from_the_job_data_and_212_chosen() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "IlRows01")
	var expected := _expected()
	assert_eq(creation.job_ids, expected)
	assert_eq(creation.job_id, 212, "the default job (F/P, not the first row) is chosen when the page opens")
	var mage := _row(creation, 212)
	var il := _row(creation, 222)
	assert_true(mage != null and il != null, "one row per playable job")
	assert_eq(mage.text, "Arch Mage (Fire, Poison)")
	assert_eq(il.text, "Arch Mage (Ice, Lightning)")
	# The headless dummy text server measures 8 px a character, so a long name widens its Button past JOB_ROW_SIZE (208 for I/L's
	# 26 characters; a real window's font fits it, checked by the creation screenshot): only the minimum is asserted.
	assert_true(il.size.x >= CREATE.JOB_ROW_SIZE.x and mage.size.x >= CREATE.JOB_ROW_SIZE.x)
	assert_eq(il.position.x, mage.position.x, "rows share a column")
	assert_eq(il.position.y - mage.position.y, CREATE.JOB_ROW_SIZE.y + 2.0, "I/L is one pitch below F/P")
	assert_eq(_row(creation, expected[0]).position.y, CREATE.ROW_AT.y, "the first row starts at the first Look row")
	assert_eq(il.alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_true(il.get_theme_stylebox("normal") is StyleBoxEmpty, "I/L is not highlighted until chosen")


func test_clicking_i_l_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "IlClick01")
	_row(creation, 222).pressed.emit()
	assert_eq(creation.job_id, 222)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false(_row(creation, 222).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state (under the mouse too)" % state)
		assert_true(_row(creation, 212).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Arch Mage (Ice, Lightning)"), "the blurb names the chosen job")
	creation.select_job(999)
	assert_eq(creation.job_id, 222, "an id that is not listed changes nothing")


func test_up_and_down_step_through_every_row_and_clamp_at_the_ends() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "IlKeys01")
	var ids := _expected()
	var last: int = ids[ids.size() - 1] # the last playable job (Buccaneer since B11 #423; the I/L row is not the last)
	assert_true(ids.find(222) >= 0 and ids.find(222) > ids.find(212), "I/L is a row below F/P")
	creation.select_job(last)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, last, "Down at the last row stays")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, ids[ids.size() - 2], "Up from the last row is the row above")
	creation.select_job(212)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 222, "Down from F/P is I/L")
	for i in ids.size():
		creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, ids[0], "Up clamps at the first row")
	for i in ids.size():
		creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, last)


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
	var creation := _job_page(_flow(), "IlWeapon01")
	var jobs: JobTree = creation._jobs
	assert_eq(jobs.creation_weapon(222), 1372005, "I/L starts with the same Wooden Wand as F/P")
	creation.select_job(222)
	assert_eq(creation.avatar.look.equips[-1], 1372005, "the preview wears the wand")
	assert_true(String(creation.option_labels.weapon.text).contains("Wand"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._weapon_label.text).contains("WATK") or String(creation._weapon_label.text).contains("MATK"),
		"the weapon box shows its stats: %s" % creation._weapon_label.text)
	assert_true(String(creation._job_blurb.text).contains(creation._weapon_label.text), "the Job page blurb repeats the weapon box")


func test_create_makes_an_i_l_with_its_wand_and_a_separate_f_p_in_the_next_slot() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "IlOne01")
	creation.select_job(222)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var il: Dictionary = flow.save.slot(0).character
	assert_eq(il.job_id, 222)
	assert_eq(il.cleared_regions, [])
	assert_eq(int(il.equipment.worn.weapon.id), 1372005, "I/L starts with the Wooden Wand")
	assert_eq(CharacterSnapshot.validation_error(il), "")
	flow.goto_character_select()
	creation = _job_page(flow, "FpOne01")
	creation.select_job(212)
	creation.create_button.pressed.emit()
	var mage: Dictionary = flow.save.slot(1).character
	assert_eq(mage.job_id, 212)
	assert_eq(flow.save.slot(0).character.job_id, 222, "the first slot is unchanged")
	assert_eq(flow.save.slot(0).character.cleared_regions, [], "each job has its own progress")


func test_i_l_is_refused_when_disabled_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "Refused01")
	creation.select_job(222)
	DataRepo.patch = {"jobs_survivor": {"jobs": {"222": {"playable": false}}}}
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_eq(flow.save.slot(0).is_empty(), true, "nothing was saved")
