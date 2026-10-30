extends TestCase
## The shipped Buccaneer creation page (spec #412, B11 #423): its row in canonical order beside the other playable jobs,
## selection, the keyboard step, the weapon box (Steel Knuckler) and separate character slots.
## Job-page tests need the cache because Look OK requires the hair/face columns. Data assertions run cache-free.

const CREATE := preload("res://scenes/ui/character_create.gd")

var save_path := TestCase.test_dir("creation_buccaneer/save.json")
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


func test_shipped_buccaneer_is_playable_in_canonical_order_and_212_stays_the_default() -> void:
	var tree := _tree()
	assert_true(tree.job(512).playable)
	var playable := tree.playable_jobs()
	for job: int in [112, 212, 222]:
		assert_true(job in playable and playable.find(job) < playable.find(512), "%d is above the Buccaneer" % job)
	assert_eq(playable[playable.size() - 1], 512, "Buccaneer is the last row of the shipped playable jobs")
	assert_eq(tree.name_of(512), "Buccaneer", "the name is the canonical job list's")
	assert_eq(tree.default_job(), 212, "F/P stays the default (the pin, not the first row)")


func test_rows_follow_the_playable_jobs_names_from_the_job_data_and_212_chosen() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "BucRows01")
	var expected := _expected()
	assert_eq(creation.job_ids, expected)
	assert_eq(creation.job_id, 212, "the default job (F/P, not the first row) is chosen when the page opens")
	var mage := _row(creation, 212)
	var buc := _row(creation, 512)
	assert_true(mage != null and buc != null, "one row per playable job")
	assert_eq(buc.text, "Buccaneer")
	assert_true(buc.size.x >= CREATE.JOB_ROW_SIZE.x and mage.size.x >= CREATE.JOB_ROW_SIZE.x)
	assert_eq(buc.position.x, mage.position.x, "rows share a column")
	var rows_between := expected.find(512) - expected.find(212)
	assert_eq(buc.position.y - mage.position.y, rows_between * (CREATE.JOB_ROW_SIZE.y + 2.0), "rows are one pitch apart")
	assert_eq(_row(creation, expected[0]).position.y, CREATE.ROW_AT.y, "the first row starts at the first Look row")
	assert_eq(buc.alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_true(buc.get_theme_stylebox("normal") is StyleBoxEmpty, "Buccaneer is not highlighted until chosen")


func test_clicking_buccaneer_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "BucClick01")
	_row(creation, 512).pressed.emit()
	assert_eq(creation.job_id, 512)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false(_row(creation, 512).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state (under the mouse too)" % state)
		assert_true(_row(creation, 212).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Buccaneer"), "the blurb names the chosen job")
	creation.select_job(999)
	assert_eq(creation.job_id, 512, "an id that is not listed changes nothing")


func test_up_and_down_step_through_every_row_and_clamp_at_the_ends() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "BucKeys01")
	var ids := _expected()
	creation.select_job(ids[ids.size() - 1])
	assert_eq(creation.job_id, 512, "Buccaneer is the last row")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 512, "Down at the last row stays")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, ids[ids.size() - 2], "Up from Buccaneer is the row above")
	for i in ids.size():
		creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, ids[0], "Up clamps at the first row")
	for i in ids.size():
		creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 512)


func test_the_weapon_box_follows_the_buccaneers_creation_weapon() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "BucWeapon01")
	var jobs: JobTree = creation._jobs
	assert_eq(jobs.creation_weapon(512), 1482000, "the Steel Knuckler")
	creation.select_job(512)
	assert_eq(creation.avatar.look.equips[-1], 1482000, "the preview wears the knuckles")
	var box := String(creation._weapon_label.text)
	assert_true(box.contains("Knuckler") or box.contains("Knuckle"), "the weapon box names it: %s" % box)
	assert_true(box.contains("WATK"), "the weapon box shows WATK: %s" % box)
	assert_true(box.contains("s"), "and its speed: %s" % box)
	assert_true(String(creation.option_labels.weapon.text).contains("Knuckle"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._job_blurb.text).contains(box), "the Job page blurb repeats the weapon box")


func test_create_makes_a_buccaneer_with_its_knuckles_and_a_separate_f_p_in_the_next_slot() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "BucOne01")
	creation.select_job(512)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var buc: Dictionary = flow.save.slot(0).character
	assert_eq(buc.job_id, 512)
	assert_eq(buc.cleared_regions, [])
	assert_eq(int(buc.equipment.worn.weapon.id), 1482000, "the Buccaneer starts with the Steel Knuckler")
	assert_eq(CharacterSnapshot.validation_error(buc), "")
	flow.goto_character_select()
	creation = _job_page(flow, "FpOne01")
	creation.select_job(212)
	creation.create_button.pressed.emit()
	var mage: Dictionary = flow.save.slot(1).character
	assert_eq(mage.job_id, 212)
	assert_eq(flow.save.slot(0).character.job_id, 512, "the first slot is unchanged")
	assert_eq(flow.save.slot(0).character.cleared_regions, [], "each job has its own progress")


func test_the_job_page_is_not_a_cache_test_for_the_arrow_keys_off_the_page() -> void:
	var flow := _flow()
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	var before: int = creation.job_id
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, before, "only the Job page steps jobs")


func test_buccaneer_is_refused_when_disabled_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "Refused01")
	creation.select_job(512)
	DataRepo.patch = {"jobs_survivor": {"jobs": {"512": {"playable": false}}}}
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_eq(flow.save.slot(0).is_empty(), true, "nothing was saved")
