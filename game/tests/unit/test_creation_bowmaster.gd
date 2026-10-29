extends TestCase
## The creation Job page with five playable jobs (spec #332, B12 #344): Hero (112), the Arch Mages (F/P 212, I/L 222) and the
## Bowmaster (312). Shipped data is used for acceptance; an explicit disabling patch tests refusal.
## The Job page needs the cache (Look OK stays disabled until the hair/face columns exist), so every test that opens it
## calls `require_cache()`; the data-level tests run in CI.

const CREATE := preload("res://scenes/ui/character_create.gd")
const DISABLED := {"jobs_survivor": {"jobs": {"312": {"playable": false}}}}

var save_path := TestCase.test_dir("creation_bowmaster/save.json")
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


func test_shipped_bowmaster_is_the_last_playable_job_and_212_stays_the_default() -> void:
	var tree := DataRepo.jobs(DataRepo.load_all())
	assert_eq(tree.playable_jobs(), [112, 212, 222, 232, 312] as Array[int], "canonical order: Hero, F/P, I/L, Bishop, Bowmaster")
	assert_eq(tree.default_job(), 212, "the pin keeps 212 the default with five playable jobs")
	assert_eq(tree.creation_weapon(312), 1452002, "the War Bow")
	DataRepo.patch = DISABLED.duplicate(true)
	assert_false(DataRepo.jobs(DataRepo.load_all()).job(312).playable, "disabled Bowmaster is not selectable")
	assert_eq(DataRepo.jobs(DataRepo.load_all()).playable_jobs(), [112, 212, 222, 232] as Array[int])


func test_five_rows_in_canonical_order_with_212_chosen() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "FourJobs01")
	assert_eq(creation.job_ids, [112, 212, 222, 232, 312])
	assert_eq(creation.job_id, 212, "the default job is chosen when the page opens")
	var rows := {}
	for id: int in [112, 212, 222, 232, 312]:
		rows[id] = creation.find_child("Job_%d" % id, true, false) as Button
		assert_true(rows[id] != null, "row for %d" % id)
	if rows.values().has(null):
		return
	assert_eq(rows[312].text, "Bowmaster")
	assert_eq(rows[312].size.x, CREATE.JOB_ROW_SIZE.x)
	assert_eq(rows[312].position.x, rows[112].position.x, "rows share a column")
	assert_eq(rows[212].position.y - rows[112].position.y, CREATE.JOB_ROW_SIZE.y + 2.0)
	assert_eq(rows[222].position.y - rows[212].position.y, CREATE.JOB_ROW_SIZE.y + 2.0)
	assert_eq(rows[232].position.y - rows[222].position.y, CREATE.JOB_ROW_SIZE.y + 2.0)
	assert_eq(rows[312].position.y - rows[232].position.y, CREATE.JOB_ROW_SIZE.y + 2.0, "Bowmaster is the fifth row, one pitch below Bishop")
	assert_true(rows[312].get_theme_stylebox("normal") is StyleBoxEmpty, "Bowmaster is not highlighted")
	assert_false(rows[212].get_theme_stylebox("normal") is StyleBoxEmpty, "212 is highlighted")


func test_clicking_bowmaster_selects_it_and_moves_the_highlight() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "FourJobs02")
	(creation.find_child("Job_312", true, false) as Button).pressed.emit()
	assert_eq(creation.job_id, 312)
	for state: String in CREATE.JOB_ROW_STATES:
		assert_false((creation.find_child("Job_312", true, false) as Button).get_theme_stylebox(state) is StyleBoxEmpty,
			"the chosen row keeps its plate in the %s state" % state)
		assert_true((creation.find_child("Job_212", true, false) as Button).get_theme_stylebox(state) is StyleBoxEmpty)
	assert_true(String(creation._job_blurb.text).begins_with("Bowmaster"), "the blurb names the chosen job: %s" % creation._job_blurb.text)


func test_up_and_down_step_through_all_five_rows_and_clamp() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "FourJobs03")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 222, "Down from 212 is the I/L Arch Mage")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 232, "Down from 222 is Bishop")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 312, "Down from 232 is Bowmaster")
	creation._input(_key(KEY_DOWN))
	assert_eq(creation.job_id, 312, "Down at the last row stays")
	for i in 4:
		creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112)
	creation._input(_key(KEY_UP))
	assert_eq(creation.job_id, 112, "Up at the first row stays")


func test_the_weapon_box_shows_the_war_bow() -> void:
	if not require_cache():
		return
	var creation := _job_page(_flow(), "FourJobs04")
	creation.select_job(312)
	assert_eq(creation.avatar.look.equips[-1], 1452002, "the preview wears the War Bow")
	assert_true(String(creation.option_labels.weapon.text).contains("Bow"), "the weapon row names it: %s" % creation.option_labels.weapon.text)
	assert_true(String(creation._weapon_label.text).contains("WATK"), "the weapon box shows its stats: %s" % creation._weapon_label.text)
	assert_true(String(creation._job_blurb.text).contains(creation._weapon_label.text), "the blurb repeats the weapon box")
	creation.select_job(212)
	assert_eq(creation.avatar.look.equips[-1], 1372005, "the preview swaps back to the wand")


func test_create_makes_a_bowmaster_with_its_war_bow_and_separate_ladders() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "BowOne01")
	creation.select_job(312)
	creation.create_button.pressed.emit()
	assert_eq(flow.current_name, "free_market")
	var bowman: Dictionary = flow.save.slot(0).character
	assert_eq(bowman.job_id, 312)
	assert_eq(bowman.tiers_unlocked, 1)
	assert_eq(int(bowman.equipment.worn.weapon.id), 1452002, "Bowmaster starts with the War Bow")
	assert_eq(CharacterSnapshot.validation_error(bowman), "")
	assert_eq(WeaponInfo.family(1452002), "bow")
	flow.goto_character_select()
	creation = _job_page(flow, "MageOne03")
	creation.create_button.pressed.emit()
	assert_eq(flow.save.slot(1).character.job_id, 212, "the untouched page still creates the default job")
	assert_eq(flow.save.slot(0).character.job_id, 312, "the first slot is unchanged")


func test_bowmaster_is_refused_when_disabled_after_selection() -> void:
	if not require_cache():
		return
	var flow := _flow()
	var creation := _job_page(flow, "Refused03")
	creation.select_job(312)
	DataRepo.patch = DISABLED.duplicate(true)
	creation.create_button.pressed.emit()
	assert_eq(creation.phase, "job", "still on the page")
	assert_ne(String(creation.message.text), "", "the refusal is shown")
	assert_true(flow.save.slot(0).is_empty(), "nothing was saved")

func test_bare_job_tool_run_uses_creation_weapon_and_ammo() -> void:
	var rf := preload("res://tests/fixtures/run_fixtures.gd")
	var setup := rf.setup("quiet", 332, rf.quiet_data())
	setup.job = 312
	var w := RunWorld.new(setup)
	assert_eq(int(w.equipment.worn.weapon.id), 1452002)
	assert_eq(w.ammo_id(), 2060000)
	assert_true(1452002 in CharacterSnapshot.held_item_ids({"job_id": 312}, w.jobs))
