extends TestCase
## The creation Job page with two playable jobs (spec #296, H9 #305): Hero (112) and the Arch Mage (F/P, 212). Both jobs are playable; these tests drive the
## real page and SceneFlow through it. Saves go to TestCase.test_dir().

const CREATE := preload("res://scenes/ui/character_create.gd")

var save_path := TestCase.test_dir("creation_two_jobs/save.json")
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


## Creation on its Job page: name -> look -> job.
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


func test_shipped_jobs_are_playable_and_a_patch_can_refuse_hero() -> void:
	var shipped := DataRepo.load_all()
	var tree := DataRepo.jobs(shipped)
	var playable := tree.playable_jobs()
	assert_true(playable.find(112) >= 0 and playable.find(112) < playable.find(212), "canonical order: Hero above the Arch Mage")
	assert_eq(tree.default_job(), 212, "the pin keeps 212 the default with several playable jobs")
	assert_true(JobTree.from_data(shipped.jobs, shipped.jobs_survivor).job(112).playable)
	DataRepo.patch = {"jobs_survivor": {"jobs": {"112": {"playable": false}}}}
	assert_false(DataRepo.jobs(DataRepo.load_all()).job(112).playable)


func test_name_to_look_and_cancel_work_without_art() -> void:
	var flow := _flow()
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	assert_eq(creation.phase, "name")
	creation.name_edit.text = "NoArt306"
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "look")
	creation._return_name()
	assert_eq(creation.phase, "name")


func test_two_rows_in_canonical_order_names_from_the_job_data_and_212_chosen() -> void:
	# Look OK needs the cache-backed face/hair columns; do not bypass the real creation flow.
	if not require_cache():
		return
	var creation := _job_page(_flow(), "TwoJobs01")
	assert_eq(creation.job_ids, [112, 212])
	assert_eq(creation.job_id, 212, "the default job is chosen when the page opens")
	var hero := creation.find_child("Job_112", true, false) as Button
	var mage := creation.find_child("Job_212", true, false) as Button
	assert_true(hero != null and mage != null, "one row per playable job")
	assert_eq(hero.text, "Hero")
	assert_eq(mage.text, "Arch Mage (Fire, Poison)")
	assert_eq(hero.size.x, CREATE.JOB_ROW_SIZE.x) # the height is the text server's: the dummy one of a headless run measures 31
	assert_eq(hero.position.x, mage.position.x, "rows share a column")
	assert_eq(mage.position.y - hero.position.y, CREATE.JOB_ROW_SIZE.y + 2.0, "rows are one pitch apart, Hero first")
	assert_eq(hero.position.y, CREATE.ROW_AT.y, "the first row starts at the first Look row")
	assert_true(hero.get_theme_stylebox("normal") is StyleBoxEmpty, "Hero is not highlighted")
	assert_false(mage.get_theme_stylebox("normal") is StyleBoxEmpty, "212 is highlighted")


func test_clicking_a_row_selects_it_and_moves_the_highlight() -> void:
	# Look OK needs the cache-backed face/hair columns; do not bypass the real creation flow.
	if not require_cache():
		return
	var creation := _job_page(_flow(), "TwoJobs02")
	(creation.find_child("Job_112", true, false) as Button).pressed.emit()
	assert_eq(creation.job_id, 112)
	assert_false((creation.find_child("Job_112", true, false) as Button).get_theme_stylebox("normal") is StyleBoxEmpty)
	assert_true((creation.find_child("Job_212", true, false) as Button).get_theme_stylebox("normal") is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Hero"), "the blurb names the chosen job")
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false((creation.find_child("Job_112", true, false) as Button).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state (under the mouse too)" % state)
		assert_true((creation.find_child("Job_212", true, false) as Button).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_eq((creation.find_child("Job_112", true, false) as Button).alignment, HORIZONTAL_ALIGNMENT_LEFT)
	creation.select_job(999)
	assert_eq(creation.job_id, 112, "an id that is not listed changes nothing")


func test_up_and_down_step_the_selection_and_clamp_at_the_ends() -> void:
	# Look OK needs the cache-backed face/hair columns; do not bypass the real creation flow.
	if not require_cache():
		return
	var creation := _job_page(_flow(), "TwoJobs03")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112, "Up from 212 is Hero")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112, "Up at the first row stays")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 212)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 212, "Down at the last row stays")


func test_arrow_keys_do_nothing_off_the_job_page() -> void:
	var flow := _flow()
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 212, "only the Job page steps jobs")


func test_the_weapon_box_follows_the_chosen_jobs_creation_weapon() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "TwoJobs04")
	var jobs: JobTree = creation._jobs
	assert_eq(jobs.creation_weapon(112), 1302000)
	assert_eq(jobs.creation_weapon(212), 1372005)
	creation.select_job(112)
	assert_eq(creation.avatar.look.equips[-1], 1302000, "the preview wears the Hero sword")
	assert_true(String(creation.option_labels.weapon.text).contains("Sword"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._weapon_label.text).contains("WATK"), "the weapon box shows its stats")
	var hero_box: String = creation._weapon_label.text
	assert_true(String(creation._job_blurb.text).contains(hero_box), "the Job page blurb repeats the weapon box: %s" % creation._job_blurb.text)
	creation.select_job(212)
	assert_eq(creation.avatar.look.equips[-1], 1372005, "the preview swaps to the wand")
	assert_ne(creation._weapon_label.text, hero_box)


func test_create_makes_a_hero_with_its_sword_and_a_separate_arch_mage_in_the_next_slot() -> void:
	# Look OK needs the cache-backed face/hair columns; do not bypass the real creation flow.
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "HeroOne01")
	creation.select_job(112)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var hero: Dictionary = flow.save.slot(0).character
	assert_eq(hero.job_id, 112)
	assert_eq(hero.tiers_unlocked, 1)
	assert_eq(int(hero.equipment.worn.weapon.id), 1302000, "Hero starts with the plain Sword")
	assert_eq(CharacterSnapshot.validation_error(hero), "")
	flow.goto_character_select()
	creation = _job_page(flow, "MageOne01")
	creation.create_button.pressed.emit()
	var mage: Dictionary = flow.save.slot(1).character
	assert_eq(mage.job_id, 212, "the untouched page creates the default job")
	assert_eq(int(mage.equipment.worn.weapon.id), 1372005)
	assert_eq(flow.save.slot(0).character.job_id, 112, "the first slot is unchanged")
	assert_eq(flow.save.slot(0).character.tiers_unlocked, 1, "each job has its own tier ladder")


func test_hero_is_refused_when_disabled_after_selection() -> void:
	# Look OK needs the cache-backed face/hair columns; do not bypass the real creation flow.
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "Refused01")
	creation.select_job(112)
	DataRepo.patch = {"jobs_survivor": {"jobs": {"112": {"playable": false}}}}
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_eq(flow.save.slot(0).is_empty(), true, "nothing was saved")
