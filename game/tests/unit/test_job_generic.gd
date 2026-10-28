extends TestCase
## Job-generic sim plumbing (spec #152): a job line is data only (its AP row, growth, bot weights, format-1 weapon)
## and the generic regen passive. Synthetic Warrior / Bowman rows are added to the loaded data inside the tests;
## fallback checks explicitly remove shipping rows. The job is fixed (#284): tests stand a character with set_job.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _data() -> Dictionary:
	var data := RF.quiet_data()
	data.upgrades.cards = [] # no stat cards: level-ups change pools only through growth
	return data


## Test-fixture data for a Warrior (100) and a Bowman (300) line; tier B v83 growth midpoints.
func _with_lines(data: Dictionary) -> Dictionary:
	var pb: Dictionary = data.balance.player
	pb.ap["100"] = {"primary": "str", "secondary": "dex", "keyframes": [{"level": 1, "target": 8}]}
	pb.ap["300"] = {"primary": "dex"}
	data.balance.growth["100"] = {"hp": 26, "mp": 5}
	data.balance.growth["300"] = {"hp": 22, "mp": 15}
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

func test_warrior_line_gets_its_ap_row_and_growth_from_data() -> void:
	var w := RunWorld.new(RF.setup("quiet", 71, _with_lines(_data())))
	RF.place_player(w, 400)
	var hp0: int = w.player_state.max_hp
	var mp0: int = w.player_state.max_mp
	w.set_job(100)
	assert_eq(w.player_state.max_hp, hp0, "a job grants nothing (#284)")
	_level_to(w, 2)
	assert_eq(w.player_state.max_hp, hp0 + 26, "Warrior growth: 26 HP per level")
	assert_eq(w.player_state.max_mp, mp0 + 5, "Warrior growth: 5 MP per level")
	assert_eq(w.player_state.dex, 8, "the secondary stat takes earned AP up to its target first")
	assert_eq(w.player_state.str, 14, "the rest of the 5 earned AP goes to the primary STR")
	_level_to(w, 3)
	assert_eq(w.player_state.str, 19, "5 more AP, secondary already at its target")
	assert_eq(w.player_state.dex, 8)
	assert_eq(w.player_state.max_hp, hp0 + 52)


func test_bowman_line_puts_ap_in_dex_and_grows_both_pools() -> void:
	var w := RunWorld.new(RF.setup("quiet", 72, _with_lines(_data())))
	RF.place_player(w, 400)
	var hp0: int = w.player_state.max_hp
	var mp0: int = w.player_state.max_mp
	w.set_job(300)
	_level_to(w, 2)
	assert_eq(w.player_state.dex, 10, "Bowman AP goes to DEX (5 base + 5)")
	assert_eq(w.player_state.str, 12)
	assert_eq(w.player_state.max_hp, hp0 + 22)
	assert_eq(w.player_state.max_mp, mp0 + 15)


func test_job_and_growth_survive_the_character_snapshot() -> void:
	var data := _with_lines(_data())
	var w := RunWorld.new(RF.setup("quiet", 73, data))
	RF.place_player(w, 400)
	w.set_job(100)
	_level_to(w, 2)
	var snapshot := w.character_snapshot()
	assert_eq(CharacterSnapshot.validation_error(snapshot), "")
	var setup := RF.setup("quiet", 74, _with_lines(_data()))
	setup.character = JSON.parse_string(JSON.stringify(snapshot))
	var restored := RunWorld.new(setup)
	assert_eq(restored.player_state.max_hp, w.player_state.max_hp, "Continue keeps the growth")
	assert_eq(restored.player_state.job_id, 100)
	assert_eq(restored.character_snapshot(), snapshot, "the snapshot format is unchanged")


func test_unlisted_job_falls_back_to_the_beginner_rows() -> void:
	var data := _data()
	# #199 ships Bowman: remove its rows to keep exercising the unlisted-line contract.
	data.jobs_survivor.jobs.erase("300")
	data.balance.growth.erase("300")
	data.balance.player.ap.erase("300")
	var w := RunWorld.new(RF.setup("quiet", 75, data))
	RF.place_player(w, 400)
	var hp0: int = w.player_state.max_hp
	w.set_job(300)
	_level_to(w, 2)
	assert_eq(w.player_state.max_hp, hp0 + int(w.balance.growth["0"].hp))
	assert_eq(w.player_state.str, 17)


# --- the generic regen passive ----------------------------------------------------------------------------------

func _regen_world(pool: String, skill_level: int, char_level: int) -> RunWorld:
	var data := _data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.balance.player.mp = 125 # the pool the removed Magician grant used to add room for (#284)
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	var def: Dictionary = (data.skills.skills.improved_mp_recovery as Dictionary).duplicate(true)
	def.regen = {"pool": pool, "divisor": 10}
	data.skills.skills["synthetic_recovery"] = def
	var w := RunWorld.new(RF.setup("quiet", 76, data))
	RF.place_player(w, 400)
	RF.as_job(w, 200)
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
	data.jobs_survivor.jobs["100"] = {"format1_weapon": 1402000}
	jobs = _tree(data)
	assert_eq(CharacterSnapshot.held_item_ids(old, jobs)[-1], 1402000, "a new line is a data row")
	old.job_id = 110
	assert_eq(CharacterSnapshot.held_item_ids(old, jobs)[-1], 1402000, "second jobs inherit it")
