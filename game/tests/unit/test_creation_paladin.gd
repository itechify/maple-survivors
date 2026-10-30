extends TestCase
## The shipped Paladin on the creation Job page (spec #308, P9 #317): canonical job rows with Paladin between Hero and the Arch
## Mages, selection, keyboard step, the weapon box and separate character slots. Job-page tests need the cache because Look OK
## requires the hair/face columns; the data-level assertions run cache-free.

const CREATE := preload("res://scenes/ui/character_create.gd")
const DISABLE := {"jobs_survivor": {"jobs": {"122": {"playable": false}}}}

var save_path := TestCase.test_dir("creation_paladin/save.json")
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


func test_shipped_paladin_is_playable_between_hero_and_the_arch_mages_and_212_stays_the_default() -> void:
	var tree := _tree()
	assert_true(tree.job(122).playable)
	assert_eq(tree.job_error(122), "")
	var playable := tree.playable_jobs()
	assert_true(playable.find(112) < playable.find(122) and playable.find(122) < playable.find(212), "Hero, Paladin, F/P: %s" % [playable])
	assert_eq(tree.name_of(122), "Paladin")
	assert_eq(tree.default_job(), 212, "the pin, not the first playable job")


func test_a_disabling_patch_takes_paladin_off_the_list_and_refuses_it() -> void:
	DataRepo.patch = DISABLE.duplicate(true)
	var tree := _tree()
	assert_false(122 in tree.playable_jobs())
	assert_true(tree.job_error(122).contains("not playable"))
	assert_true(112 in tree.playable_jobs() and 212 in tree.playable_jobs())


func test_the_paladin_row_sits_one_pitch_below_hero_and_the_plate_follows_the_selection() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "PalRows01")
	var ids: Array = creation.job_ids
	assert_eq(ids, _tree().playable_jobs(), "one row per playable job, canonical order")
	assert_eq(creation.job_id, 212, "the default job (F/P) is chosen when the page opens")
	var hero := _row(creation, 112)
	var paladin := _row(creation, 122)
	var mage := _row(creation, 212)
	assert_true(hero != null and paladin != null and mage != null)
	assert_eq(paladin.text, "Paladin")
	assert_eq(paladin.size.x, CREATE.JOB_ROW_SIZE.x)
	assert_eq(paladin.position.x, hero.position.x, "rows share a column")
	assert_eq(paladin.position.y - hero.position.y, CREATE.JOB_ROW_SIZE.y + 2.0, "Paladin is one pitch below Hero")
	assert_eq(mage.position.y - paladin.position.y, (CREATE.JOB_ROW_SIZE.y + 2.0) * (ids.find(212) - ids.find(122)))
	assert_eq(hero.position.y, CREATE.ROW_AT.y, "the first row starts at the first Look row")
	assert_eq(paladin.alignment, HORIZONTAL_ALIGNMENT_LEFT)
	assert_true(paladin.get_theme_stylebox("normal") is StyleBoxEmpty, "Paladin is not highlighted until chosen")


func test_clicking_paladin_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "PalClick01")
	_row(creation, 122).pressed.emit()
	assert_eq(creation.job_id, 122)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false(_row(creation, 122).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state (under the mouse too)" % state)
		assert_true(_row(creation, 212).get_theme_stylebox(state) is StyleBoxEmpty)
		assert_true(_row(creation, 112).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Paladin"), "the blurb names the chosen job")
	creation.select_job(999)
	assert_eq(creation.job_id, 122, "an id that is not listed changes nothing")


func test_up_and_down_step_through_paladin_and_clamp_at_the_ends() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "PalKeys01")
	var ids: Array = creation.job_ids
	creation.select_job(ids[0])
	assert_eq(creation.job_id, 112)
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 122, "Down from Hero is Paladin")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, ids[ids.find(122) + 1], "Down from Paladin is the next row")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 122, "Up returns")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112)
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112, "Up at the first row stays")
	for i in ids.size() + 1:
		creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, ids.back(), "Down at the last row stays")


func test_the_weapon_box_follows_the_chosen_jobs_creation_weapon() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "PalWeapon01")
	assert_eq(creation._jobs.creation_weapon(122), 1322000, "the Mace")
	creation.select_job(122)
	assert_eq(creation.avatar.look.equips[-1], 1322000, "the preview wears the Mace")
	assert_true(String(creation.option_labels.weapon.text).contains("Mace"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._weapon_label.text).contains("WATK"), "the weapon box shows its stats: %s" % creation._weapon_label.text)
	assert_true(String(creation._job_blurb.text).contains(creation._weapon_label.text), "the Job page blurb repeats the weapon box")
	creation.select_job(112)
	assert_ne(creation.avatar.look.equips[-1], 1322000, "the weapon follows the job back to Hero's sword")


func test_create_makes_a_paladin_with_its_mace_and_a_separate_f_p_in_the_next_slot() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "PalOne01")
	creation.select_job(122)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var paladin: Dictionary = flow.save.slot(0).character
	assert_eq(paladin.job_id, 122)
	assert_eq(paladin.cleared_regions, [])
	assert_eq(int(paladin.equipment.worn.weapon.id), 1322000, "a Paladin starts with the Mace")
	assert_eq(CharacterSnapshot.validation_error(paladin), "")
	flow.goto_character_select()
	creation = _job_page(flow, "FpOne01")
	creation.select_job(212)
	creation.create_button.pressed.emit()
	assert_eq(flow.save.slot(1).character.job_id, 212)
	assert_eq(flow.save.slot(0).character.job_id, 122, "the first slot is unchanged")
	assert_eq(flow.save.slot(0).character.cleared_regions, [], "each job has its own progress")


func test_paladin_is_refused_when_disabled_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "PalRefused01")
	creation.select_job(122)
	DataRepo.patch = DISABLE.duplicate(true)
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_true(flow.save.slot(0).is_empty(), "nothing was saved")
