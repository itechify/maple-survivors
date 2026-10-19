extends TestCase
## Job-generic sim plumbing (spec #152): a new job line is data only (AP stat, growth, max_hp grant, bot weights,
## format-1 weapon), the generic regen passive, and the forced-job (--job) rules. Synthetic Warrior / Bowman rows are
## added to the loaded data inside the tests; fallback checks explicitly remove shipping rows.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _data() -> Dictionary:
	var data := RF.quiet_data()
	data.upgrades.cards = [] # no stat cards: level-ups change pools only through growth
	return data


## Test-fixture data for a Warrior (100) and a Bowman (300) line; tier B v83 growth midpoints.
func _with_lines(data: Dictionary) -> Dictionary:
	var pb: Dictionary = data.balance.player
	pb.ap_stat["100"] = "str"
	pb.ap_stat["300"] = "dex"
	pb.ap_secondary["100"] = {"stat": "dex", "keyframes": [{"level": 1, "target": 8}]}
	data.balance.growth["100"] = {"hp": 26, "mp": 5}
	data.balance.growth["300"] = {"hp": 22, "mp": 15}
	data.jobs_survivor.jobs["100"] = {"playable": true, "grants": {"max_hp": 300}}
	data.jobs_survivor.jobs["300"] = {"playable": true, "grants": {"max_hp": 200, "max_mp": 50}}
	return data


func _level_to(w: RunWorld, target: int) -> void:
	var exp := (w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level)
		- w.progression.exp)
	w.pickups.spawn(w.player.pos, exp, 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if int(w.player_state.level) == target:
			break
	assert_eq(int(w.player_state.level), target, "EXP was collected through the run")
	RF.auto_choose(w)


# --- a new job line is data only ------------------------------------------------------------------------------

func test_warrior_line_gets_ap_stat_growth_and_max_hp_grant_from_data() -> void:
	var w := RunWorld.new(RF.setup("quiet", 71, _with_lines(_data())))
	RF.place_player(w, 400)
	var hp0: int = w.player_state.max_hp
	var mp0: int = w.player_state.max_mp
	w.change_job(100)
	assert_eq(w.player_state.max_hp, hp0 + 300, "grants.max_hp raises Max HP")
	assert_eq(w.player_state.max_mp, mp0, "no max_mp grant for the Warrior")
	_level_to(w, 2)
	assert_eq(w.player_state.max_hp, hp0 + 300 + 26, "Warrior growth: 26 HP per level")
	assert_eq(w.player_state.max_mp, mp0 + 5, "Warrior growth: 5 MP per level")
	assert_eq(w.player_state.dex, 8, "the secondary stat takes earned AP up to its target first")
	assert_eq(w.player_state.str, 14, "the rest of the 5 earned AP goes to the primary STR")
	_level_to(w, 3)
	assert_eq(w.player_state.str, 19, "5 more AP, secondary already at its target")
	assert_eq(w.player_state.dex, 8)
	assert_eq(w.player_state.max_hp, hp0 + 300 + 52)


func test_bowman_line_puts_ap_in_dex_and_grants_both_pools() -> void:
	var w := RunWorld.new(RF.setup("quiet", 72, _with_lines(_data())))
	RF.place_player(w, 400)
	var hp0: int = w.player_state.max_hp
	var mp0: int = w.player_state.max_mp
	w.change_job(300)
	assert_eq(w.player_state.max_hp, hp0 + 200)
	assert_eq(w.player_state.max_mp, mp0 + 50)
	_level_to(w, 2)
	assert_eq(w.player_state.dex, 10, "Bowman AP goes to DEX (5 base + 5)")
	assert_eq(w.player_state.str, 12)
	assert_eq(w.player_state.max_hp, hp0 + 200 + 22)
	assert_eq(w.player_state.max_mp, mp0 + 50 + 15)


func test_max_hp_grant_survives_the_character_snapshot() -> void:
	var data := _with_lines(_data())
	var w := RunWorld.new(RF.setup("quiet", 73, data))
	RF.place_player(w, 400)
	w.change_job(100)
	_level_to(w, 2)
	var snapshot := w.character_snapshot()
	assert_eq(CharacterSnapshot.validation_error(snapshot), "")
	var setup := RF.setup("quiet", 74, _with_lines(_data()))
	setup.character = JSON.parse_string(JSON.stringify(snapshot))
	var restored := RunWorld.new(setup)
	assert_eq(restored.player_state.max_hp, w.player_state.max_hp, "Continue keeps grant and growth")
	assert_eq(restored.player_state.job_id, 100)
	assert_eq(restored.character_snapshot(), snapshot, "the snapshot format is unchanged (base_hp carries the grant)")
	restored.change_job(100)
	assert_eq(restored.player_state.max_hp, w.player_state.max_hp + 300, "a further advancement adds on top")


func test_unlisted_job_falls_back_to_the_beginner_rows() -> void:
	var data := _data()
	# #199 ships Bowman: remove its rows to keep exercising the unlisted-line contract.
	data.jobs_survivor.jobs.erase("300")
	data.balance.growth.erase("300")
	data.balance.player.ap_stat.erase("300")
	data.balance.player.ap_secondary.erase("300")
	var w := RunWorld.new(RF.setup("quiet", 75, data))
	RF.place_player(w, 400)
	var hp0: int = w.player_state.max_hp
	w.change_job(300)
	assert_eq(w.player_state.max_hp, hp0, "no grant")
	_level_to(w, 2)
	assert_eq(w.player_state.max_hp, hp0 + int(w.balance.growth["0"].hp))
	assert_eq(w.player_state.str, 17)


# --- the generic regen passive ----------------------------------------------------------------------------------

func _regen_world(pool: String, skill_level: int, char_level: int) -> RunWorld:
	var data := _data()
	data.balance.player.skills = []
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	var def: Dictionary = (data.skills.skills.improved_mp_recovery as Dictionary).duplicate(true)
	def.regen = {"pool": pool, "divisor": 10}
	data.skills.skills["synthetic_recovery"] = def
	var w := RunWorld.new(RF.setup("quiet", 76, data))
	RF.place_player(w, 400)
	w.change_job(200)
	w.learn_skill("synthetic_recovery")
	w.loadout.set_rank("synthetic_recovery", skill_level)
	w.progression.level = char_level
	w.god = true
	return w


func test_regen_passive_adds_floor_of_level_times_skill_level_over_divisor() -> void:
	var mp := _regen_world("mp", 5, 23)
	assert_eq(mp.loadout.level("synthetic_recovery"), 5)
	assert_eq(mp.loadout.regen_bonus("mp", 23), 11.0, "floor(23 x 5 / 10)")
	assert_eq(mp.loadout.regen_bonus("hp", 23), 0.0, "other pools are untouched")
	mp.spend_mp(int(mp.player_state.mp))
	for tick in 600:
		mp.step(DT, MoveInput.new())
	assert_eq(mp.player_state.mp, 11, "one 10 s pulse restores the bonus to MP")


func test_regen_passive_serves_hp_with_data_only() -> void:
	var w := _regen_world("hp", 4, 30)
	assert_eq(w.loadout.regen_bonus("hp", 30), 12.0, "floor(30 x 4 / 10)")
	assert_eq(w.loadout.regen_bonus("mp", 30), 0.0)
	var mp0: int = w.player_state.mp
	w._hp = 1.0
	for tick in 600:
		w.step(DT, MoveInput.new())
	assert_eq(w.player_state.hp, 13, "1 HP plus the 12 HP pulse bonus")
	assert_eq(w.player_state.mp, mp0, "the HP skill adds no MP")


func test_regen_bonus_is_zero_without_the_skill() -> void:
	var w := RunWorld.new(RF.setup("quiet", 77, _data()))
	assert_eq(w.loadout.regen_bonus("mp", 50), 0.0)
	assert_eq(w.loadout.regen_bonus("hp", 50), 0.0)


# --- bot equipment weights per job line ----------------------------------------------------------------------

func _tree(data: Dictionary) -> JobTree:
	return JobTree.from_data(data.jobs, data.jobs_survivor)


func test_bot_weights_resolve_through_the_job_lineage() -> void:
	var data := RF.quiet_data()
	var jobs := _tree(data)
	var table: Dictionary = data.balance.bot.equipment_weights
	assert_eq(BotShop.weights_for(data.balance, 0, jobs), table["0"], "Beginner")
	for job_id in [200, 210, 220, 230]:
		assert_eq(BotShop.weights_for(data.balance, job_id, jobs), table["200"], "Magician line: %d" % job_id)
	assert_eq(BotShop.weights_for(data.balance, 100, jobs), table["0"], "a line without an entry uses the Beginner's")
	table["100"] = {"incPAD": 10, "incSTR": 6}
	assert_eq(BotShop.weights_for(data.balance, 100, jobs), table["100"], "a new line is a data row")
	assert_eq(BotShop.weights_for(data.balance, 110, jobs), table["100"], "second jobs inherit their first job's")
	assert_eq(BotShop.weights_for(data.balance, 210, jobs), table["200"], "other lines are unaffected")
	assert_eq(BotShop.weights_for(data.balance, 99999, jobs), BotShop.DEFAULT_WEIGHTS, "unknown job, no default row")
	table["default"] = {"incPAD": 1}
	assert_eq(BotShop.weights_for(data.balance, 99999, jobs), table["default"])


# --- format-1 weapon rule from data -------------------------------------------------------------------------

func test_format_one_weapon_comes_from_the_job_lineage_data() -> void:
	var data := RF.quiet_data()
	var jobs := _tree(data)
	var old := {"look": {}, "beginner_weapon": 0, "job_id": 0}
	assert_eq(CharacterSnapshot.held_item_ids(old, jobs)[-1], 1302000, "Beginner without a weapon")
	old.beginner_weapon = 1322005
	assert_eq(CharacterSnapshot.held_item_ids(old, jobs)[-1], 1322005, "a Beginner keeps its own weapon")
	for job_id in [200, 210, 220, 230]:
		old.job_id = job_id
		assert_eq(CharacterSnapshot.held_item_ids(old, jobs)[-1], 1372005, "Magician line: %d" % job_id)
	old.job_id = 100
	assert_eq(CharacterSnapshot.held_item_ids(old, jobs)[-1], 1302000, "a line without the field uses the Beginner's")
	data.jobs_survivor.jobs["100"]["format1_weapon"] = 1402000
	jobs = _tree(data)
	assert_eq(CharacterSnapshot.held_item_ids(old, jobs)[-1], 1402000, "a new line is a data row")
	old.job_id = 110
	assert_eq(CharacterSnapshot.held_item_ids(old, jobs)[-1], 1402000, "second jobs inherit it")


# --- forcing a job (--job) ----------------------------------------------------------------------------------

func test_forced_job_must_be_a_playable_first_or_second_job() -> void:
	var data := RF.quiet_data()
	# Explicit locked fixture: shipped Hunter is playable since #202.
	data.jobs_survivor.jobs["310"] = {"playable": false}
	var jobs := _tree(data)
	for id in [200, 210, 220, 230]:
		assert_eq(jobs.forced_job_error(id), "", "Magician line %d is playable" % id)
	assert_eq(jobs.forced_job_error(100), "", "the Warrior is playable since #163")
	assert_eq(jobs.forced_job_error(300), "", "Bowman is playable since #199")
	for id in [110, 120, 130]:
		assert_eq(jobs.forced_job_error(id), "", "the Warrior branch %d is playable since #180" % id)
	assert_true("not playable" in jobs.forced_job_error(310), "a second job needs to be playable itself")
	assert_true("first or second job" in jobs.forced_job_error(211), "third jobs are refused")
	assert_true("first or second job" in jobs.forced_job_error(0), "the Beginner is not an advancement")
	assert_true("not in the canonical" in jobs.forced_job_error(12345))
	data.jobs_survivor.jobs["300"] = {"playable": true}
	jobs = _tree(data)
	assert_eq(jobs.forced_job_error(300), "", "playable once the data says so")
	assert_true("310" in jobs.forced_job_error(310), "its second job still is not")
	data.jobs_survivor.jobs["310"] = {"playable": true}
	assert_eq(_tree(data).forced_job_error(310), "")
	assert_eq(SceneFlow.forced_job_error({"job": 310}, data), "")
	assert_true(SceneFlow.forced_job_error({"job": 400}, data) != "")
	assert_eq(SceneFlow.forced_job_error({}, data), "", "nothing forced")


func test_second_job_of_a_line() -> void:
	var jobs := _tree(RF.quiet_data())
	assert_eq([jobs.second_job(210), jobs.second_job(200), jobs.second_job(0), jobs.second_job(211)], [210, 0, 0, 210])


func test_pick_job_takes_the_first_job_of_a_forced_second_job() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["100"] = {"playable": true}
	var jobs := _tree(data)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var first := [{"job_id": 100, "available": true}, {"job_id": 200, "available": true}]
	assert_eq(RF.pick_job(first, rng, 200), 200, "a forced first job")
	assert_eq(RF.pick_job(first, rng, 210, jobs), 200, "a forced second job takes its first job at the first window")
	assert_eq(RF.pick_job(first, rng, 110, jobs), 100)
	var second := [{"job_id": 210, "available": true}, {"job_id": 220, "available": true},
		{"job_id": 230, "available": true}]
	assert_eq(RF.pick_job(second, rng, 220, jobs), 220, "and itself at the second")
	assert_eq(RF.pick_job([{"job_id": 200, "available": true}], rng, 210), 200, "one option: no jobs needed")
	assert_true(RF.pick_job(second, rng, 200, jobs) in [210, 220, 230], "an unrelated forced job falls back")
	assert_eq(RF.pick_job([{"job_id": 200, "available": false}], rng, 200, jobs), -1)


func test_auto_choose_walks_a_forced_second_job_through_both_windows() -> void:
	var w := RF.quiet_world(400.0, 53)
	w.progression.level = 9
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB)
	BotInput.auto_choose(w, false, 220)
	assert_eq(w.progression.job_id, 200, "the first window offers only the Magician")
	w.progression.level = 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB)
	BotInput.auto_choose(w, false, 220)
	assert_eq(w.progression.job_id, 220)
