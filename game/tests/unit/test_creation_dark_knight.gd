extends TestCase
## The creation Job page with the Dark Knight (132) beside Hero, the F/P Arch Mage and the I/L Arch Mage (spec #348, D10 #358):
## the row in canonical order (112, 132, 212, 222), selection, the arrow keys, the weapon box (the Spear), and creating a Dark
## Knight in a slot beside another job keeps separate tier ladders. The page needs the cache-backed face/hair columns
## (Look OK is disabled without them), so every test that opens it calls `require_cache()`; the data-level test runs in CI.

const CREATE := preload("res://scenes/ui/character_create.gd")

var save_path := TestCase.test_dir("creation_dark_knight/save.json")
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


func _row(creation: Control, job: int) -> Button:
	return creation.find_child("Job_%d" % job, true, false) as Button


func test_the_dark_knight_is_playable_in_canonical_order_and_212_stays_the_default() -> void:
	var tree := DataRepo.jobs(DataRepo.load_all())
	var playable := tree.playable_jobs()
	assert_true(132 in playable)
	assert_true(playable.find(112) < playable.find(132) and playable.find(132) < playable.find(212), "Hero, Dark Knight, Arch Mage")
	assert_eq(tree.default_job(), 212)
	DataRepo.patch = {"jobs_survivor": {"jobs": {"132": {"playable": false}}}}
	assert_false(132 in DataRepo.jobs(DataRepo.load_all()).playable_jobs(), "a disabling patch removes the row")


func test_the_row_is_listed_between_hero_and_the_arch_mage_with_its_name_and_pitch() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "DarkKn01")
	var ids: Array = creation.job_ids
	assert_true(ids.find(112) < ids.find(132) and ids.find(132) < ids.find(212), "canonical order: %s" % str(ids))
	assert_eq(creation.job_id, 212, "the default job is chosen when the page opens")
	var knight := _row(creation, 132)
	var hero := _row(creation, 112)
	assert_true(knight != null and hero != null)
	assert_eq(knight.text, "Dark Knight")
	assert_eq(knight.size.x, CREATE.JOB_ROW_SIZE.x)
	assert_eq(knight.position.x, hero.position.x, "rows share a column")
	assert_eq(knight.position.y - hero.position.y, (CREATE.JOB_ROW_SIZE.y + 2.0) * (ids.find(132) - ids.find(112)), "one pitch per row")
	assert_true(knight.get_theme_stylebox("normal") is StyleBoxEmpty, "not highlighted until chosen")
	assert_eq(knight.alignment, HORIZONTAL_ALIGNMENT_LEFT)


func test_clicking_the_row_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "DarkKn02")
	_row(creation, 132).pressed.emit()
	assert_eq(creation.job_id, 132)
	assert_true(String(creation._job_blurb.text).begins_with("Dark Knight"), "the blurb names the job: %s" % creation._job_blurb.text)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false(_row(creation, 132).get_theme_stylebox(state) is StyleBoxEmpty, "the chosen row keeps its plate in the %s state" % state)
		assert_true(_row(creation, 212).get_theme_stylebox(state) is StyleBoxEmpty)
		assert_true(_row(creation, 112).get_theme_stylebox(state) is StyleBoxEmpty)


func test_up_and_down_step_through_the_dark_knight_row() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "DarkKn03")
	var ids: Array = creation.job_ids
	creation.select_job(212)
	for i in ids.find(212) - ids.find(132):
		creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 132, "Up from the Arch Mage reaches the Dark Knight")
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112, "Up from the Dark Knight is Hero")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 132, "Down from Hero is the Dark Knight")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, ids[ids.find(132) + 1], "Down from the Dark Knight is the next row")


func test_arrows_do_nothing_to_the_selection_off_the_job_page() -> void:
	var flow := _flow()
	flow.goto_character_select()
	flow.current.show_creation()
	var creation: Control = flow.current.creation
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 212, "only the Job page steps jobs")


func test_the_weapon_box_shows_the_spear_with_its_attack_and_speed() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "DarkKn04")
	assert_eq((creation._jobs as JobTree).creation_weapon(132), 1432000)
	creation.select_job(132)
	assert_eq(creation.avatar.look.equips[-1], 1432000, "the preview wears the Spear")
	assert_true(String(creation.option_labels.weapon.text).contains("Spear"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	var box: String = creation._weapon_label.text
	assert_true(box.contains("WATK"), "the box shows its attack: %s" % box)
	assert_true(box.contains("Spear"), box)
	assert_true(String(creation._job_blurb.text).contains(box), "the Job page blurb repeats the weapon box: %s" % creation._job_blurb.text)
	creation.select_job(212)
	assert_ne(creation._weapon_label.text, box, "the box follows the job")


func test_create_makes_a_dark_knight_with_a_spear_and_a_separate_arch_mage_in_the_next_slot() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "DarkKn05")
	creation.select_job(132)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var knight: Dictionary = flow.save.slot(0).character
	assert_eq(knight.job_id, 132)
	assert_eq(knight.tiers_unlocked, 1)
	assert_eq(int(knight.equipment.worn.weapon.id), 1432000, "a Dark Knight starts with the plain Spear")
	assert_eq(CharacterSnapshot.validation_error(knight), "")
	flow.goto_character_select()
	creation = _job_page(flow, "MageOne02")
	creation.create_button.pressed.emit()
	var mage: Dictionary = flow.save.slot(1).character
	assert_eq(mage.job_id, 212)
	assert_eq(int(mage.equipment.worn.weapon.id), 1372005)
	assert_eq(flow.save.slot(0).character.job_id, 132, "the first slot is unchanged")
	assert_eq(flow.save.slot(0).character.tiers_unlocked, 1, "each job has its own tier ladder")


func test_a_dark_knight_is_refused_when_the_job_is_disabled_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "DarkKn06")
	creation.select_job(132)
	DataRepo.patch = {"jobs_survivor": {"jobs": {"132": {"playable": false}}}}
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_true(flow.save.slot(0).is_empty(), "nothing was saved")
