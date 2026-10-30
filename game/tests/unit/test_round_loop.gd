extends TestCase
## The standalone-round loop (spec #282, #286, ADR 0006) through SceneFlow's public seams: create_character, start_round,
## finish_run, delete_character. Every round ends back at the character's hub; a death and a quit change nothing but
## what the round picked up; a clear unlocks the next region (ADR 0007). Saves go to TestCase.test_dir(), never user://save.json.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

var save_path := TestCase.test_dir("round_loop/save.json")
var _nodes: Array[Node] = []


func before_each() -> void:
	TestCase.remove_tree(save_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))


func after_each() -> void:
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


static func summary(cleared: bool, level: int = 12, stage: String = "henesys") -> Dictionary:
	return {"stage": stage, "map_id": 104040000, "map_name": "Henesys Hunting Ground I", "street_name": "Victoria Road",
		"time": 600.0, "duration": 900.0, "cleared": cleared, "level": level, "job_id": 212,
		"job_name": "Arch Mage (Fire, Poison)", "kills": 900, "damage_dealt": 36000, "seed": 7, "skills": [],
		"nx_awarded": 120}


## The character a round of the synthetic quiet stage, played as region `region` of the shipped progression, hands over
## after a clear or a death, picking up 250 mesos and a hat on the way.
func _character_after(flow: SceneFlow, cleared: bool, region: String = "henesys") -> Dictionary:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.stages.stages[region] = data.stages.stages.quiet
	RF.set_bosses(data.stages.stages[region], [
		{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0, "rewards": {"exp_mult": 1, "bonus_choices": 0}}])
	var setup := RF.setup(region, 20, data)
	setup.character = flow.save.slot(0).character
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.god = cleared
	for i in 20:
		w.step(DT, MoveInput.new())
	w.spawn_meso(w.player.pos, 250)
	w.spawn_equipment(w.player.pos, {"id": 1002001, "stats": {"incPDD": 4}, "slots": 7, "scrolls": 0})
	for i in 60:
		w.step(DT, MoveInput.new())
	if cleared:
		w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
			"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
		for i in 3:
			w.step(DT, MoveInput.new())
		RF.auto_choose(w)
		assert_eq(w.state, RunWorld.CLEARED)
	else:
		w.upkeep.invincible_t = 0.0
		w.take_hit(1000000.0, false, "", w.player.pos + Vector2(20, 0), {"accuracy": 100000.0})
		assert_eq(w.state, RunWorld.DEAD)
	return w.character_snapshot()


func test_a_new_character_is_an_arch_mage_in_the_free_market_with_nothing_cleared() -> void:
	var flow := _flow()
	assert_eq(flow.create_character("Maple69"), 0)
	assert_eq(flow.current_name, "free_market", "home is the Free Market")
	var saved := SaveData.new(save_path).slot(0)
	var keys: Array = saved.keys()
	keys.sort()
	assert_eq(keys, ["character", "created", "name", "rounds_played"])
	assert_eq(int(saved.character.format), 3)
	assert_eq(int(saved.character.job_id), 212)
	assert_eq(saved.character.cleared_regions, [])
	assert_eq(flow.create_character("maple69"), -1, "living names are unique ignoring case")
	assert_eq(flow.create_character("no!"), -1)


func test_creation_wears_the_chosen_outfit_and_the_jobs_own_weapon() -> void:
	var flow := _flow()
	var look := {"skin": 3, "face": 21002, "hair": 31057, "equips": [1041011, 1061008, 1072038]}
	assert_eq(flow.create_character("Maple70", look, 212), 0)
	var saved := SaveData.new(save_path).slot(0)
	assert_eq(saved.character.look, JSON.parse_string(JSON.stringify({"skin": 3, "face": 21002, "hair": 31057})))
	assert_eq(Equipment.worn_ids(saved.character.equipment.worn), [1041011, 1061008, 1072038, 1372005],
		"top, bottom, shoes and the wand jobs.json gives the Arch Mage at creation")


func test_only_a_playable_job_can_be_created() -> void:
	var flow := _flow()
	assert_eq(flow.create_character("Maple71", {}, 210), -1, "Wizard (Fire, Poison) is not a playable job")
	assert_ne(flow.action_error, "")
	assert_eq(flow.save.slot(0), {})


func test_a_death_keeps_the_pickups_clears_nothing_and_returns_to_the_hub() -> void:
	var flow := _flow()
	flow.create_character("Dead69")
	var character := _character_after(flow, false)
	flow.finish_run(summary(false), character)
	assert_eq(flow.current_name, "results")
	var saved := SaveData.new(save_path).slot(0)
	assert_eq(saved.name, "Dead69", "the character lives on")
	assert_eq(int(saved.character.mesos), 250, "the round's mesos are kept")
	assert_true(Equipment.held_ids(saved.character.equipment).has(1002001), "and its equipment drop")
	assert_eq(saved.character.cleared_regions, [], "no unlock")
	assert_eq(int(saved.rounds_played), 1)
	assert_eq(flow.save.history.size(), 1)
	assert_eq(flow.save.history[0].ending, "died")
	assert_eq(int(flow.save.history[0].level), 12)
	assert_eq(flow.save.history[0].stage, "henesys")
	assert_eq(int(flow.save.account.nx), 120, "the round's NX is credited on a death too")
	assert_true(flow.last_new_best)
	flow.current.to_hub()
	assert_eq(flow.current_name, "free_market")
	assert_eq(flow.active_slot, 0, "the character is still the active one")


func test_a_clear_unlocks_the_next_region_in_map_select() -> void:
	var flow := _flow()
	flow.create_character("Clear69")
	flow.goto_stage_select()
	assert_eq(flow.current_name, "stage_select")
	assert_eq(flow.current.unlocked_keys(), ["henesys"], "a new character has only Henesys")
	var character := _character_after(flow, true)
	flow.finish_run(summary(true), character)
	assert_eq(flow.save.slot(0).character.cleared_regions, ["henesys"])
	assert_eq(flow.save.history[0].ending, "cleared")
	flow.goto_stage_select()
	assert_eq(flow.current.unlocked_keys(), ["henesys", "ellinia"], "the clear unlocks Ellinia and nothing else")
	assert_eq(flow.current.stages.map(func(c: Dictionary) -> bool: return bool(c.cleared)), [true, false, false, false, false])


func test_replaying_a_cleared_region_changes_nothing_and_a_clear_in_a_row_unlocks_step_by_step() -> void:
	var flow := _flow()
	flow.create_character("Replay69")
	flow.finish_run(summary(true), _character_after(flow, true))
	flow.finish_run(summary(true), _character_after(flow, true))
	assert_eq(flow.save.slot(0).character.cleared_regions, ["henesys"], "a replay is idempotent")
	flow.finish_run(summary(true, 12, "ellinia"), _character_after(flow, true, "ellinia"))
	assert_eq(flow.save.slot(0).character.cleared_regions, ["ellinia", "henesys"], "sorted")
	flow.goto_stage_select()
	assert_eq(flow.current.unlocked_keys(), ["henesys", "ellinia", "perion"])


func test_quit_round_ends_the_round_exactly_like_a_death() -> void:
	var dead := _flow()
	dead.create_character("Alike69")
	var died_with := _character_after(dead, false)
	dead.finish_run(summary(false), died_with)
	var quit := _flow()
	TestCase.remove_tree(save_path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_path.get_base_dir()))
	quit.save = SaveData.new(save_path)
	quit.create_character("Alike69")
	var quit_with := _character_after(quit, false)
	quit.finish_run(summary(false), quit_with, "quit")
	assert_eq(quit.current_name, dead.current_name, "the same results screen")
	assert_eq(quit.save.slot(0).character, dead.save.slot(0).character, "same character: pickups kept, nothing unlocked")
	assert_eq(quit.save.slot(0).rounds_played, dead.save.slot(0).rounds_played)
	assert_eq(quit.save.runs_for("henesys"), dead.save.runs_for("henesys"))
	assert_eq(quit.save.account, dead.save.account)
	assert_eq(quit.save.history[0].ending, "quit", "only the history's label tells them apart")
	assert_eq(quit.save.history[0].level, dead.save.history[0].level)


func test_starting_a_round_saves_nothing_and_is_refused_for_a_locked_region() -> void:
	var flow := _flow()
	flow.create_character("Start69")
	flow.goto_stage_select()
	var before := FileAccess.get_file_as_string(save_path)
	flow.start_round("ellinia")
	assert_eq(flow.current_name, "stage_select", "Ellinia is locked until Henesys is cleared")
	flow.start_round("sleepywood")
	assert_eq(flow.current_name, "stage_select", "and so is every later region")
	assert_eq(FileAccess.get_file_as_string(save_path), before)
	flow.start_round("henesys", 2026)
	assert_eq(flow.current_name, "run")
	assert_eq(FileAccess.get_file_as_string(save_path), before,
		"nothing is written for a round: closing the game mid-round loses it, and Continue never resumes one")
	assert_eq(SaveData.new(save_path).slot(0).get("rounds_played", -1), 0)


func test_a_region_unlocked_by_the_previous_clear_starts() -> void:
	var flow := _flow()
	flow.create_character("Start70")
	var character: Dictionary = flow.save.slot(0).character
	character.cleared_regions = ["ellinia", "henesys", "perion", "kerning"]
	var slot := flow.save.slot(0)
	slot.character = character
	assert_eq(flow.save.update_slot(0, slot), OK)
	flow.goto_stage_select()
	flow.start_round("sleepywood", 5)
	assert_eq(flow.current_name, "run")
	assert_eq(flow.current.stage_key, "sleepywood")


func test_deleting_a_character_frees_its_slot_and_keeps_the_history() -> void:
	var flow := _flow()
	flow.create_character("Gone69")
	flow.finish_run(summary(false), _character_after(flow, false))
	assert_true(flow.delete_character(0))
	assert_eq(flow.current_name, "character_select")
	assert_eq(flow.save.slot(0), {})
	assert_eq(flow.save.history.map(func(h: Dictionary) -> String: return h.ending), ["died", "deleted"])
	assert_eq(flow.create_character("Gone69"), 0, "the freed slot and name can be used again")


func test_map_select_selects_a_stage_and_a_locked_one_cannot_start() -> void:
	var flow := _flow()
	flow.create_character("Scroll69")
	flow.goto_stage_select()
	var screen: Node = flow.current
	assert_eq(screen.stages.size(), 5, "every region of the progression is listed")
	assert_eq(screen.top, 0)
	screen.select(4)
	assert_eq(screen.selected, 4)
	assert_eq(screen.top, 0, "all five regions fit the six rows, so the list does not scroll")
	assert_true(screen.stages[4].locked)
	assert_true(screen.start_button.disabled, "Start is dimmed for a locked stage")
	screen.start_selected()
	assert_eq(flow.current_name, "stage_select", "a locked stage does not start")
	screen.select(0)
	assert_eq(screen.top, 0)
	assert_false(screen.start_button.disabled)
	assert_eq(screen.stages.map(func(c: Dictionary) -> int: return int(c.step)), [0, 1, 2, 3, 4])
