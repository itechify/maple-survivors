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
	data.balance.growth["100"] = {"hp": 26}
	data.balance.growth["300"] = {"hp": 22}
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
	w.set_job(100)
	assert_eq(w.player_state.max_hp, hp0, "a job grants nothing (#284)")
	_level_to(w, 2)
	assert_eq(w.player_state.max_hp, hp0 + 26, "Warrior growth: 26 HP per level")
	assert_eq(w.player_state.dex, 8, "the secondary stat takes earned AP up to its target first")
	assert_eq(w.player_state.str, 14, "the rest of the 5 earned AP goes to the primary STR")
	_level_to(w, 3)
	assert_eq(w.player_state.str, 19, "5 more AP, secondary already at its target")
	assert_eq(w.player_state.dex, 8)
	assert_eq(w.player_state.max_hp, hp0 + 52)


func test_bowman_line_puts_ap_in_dex_and_grows_hp() -> void:
	var w := RunWorld.new(RF.setup("quiet", 72, _with_lines(_data())))
	RF.place_player(w, 400)
	var hp0: int = w.player_state.max_hp
	w.set_job(300)
	_level_to(w, 2)
	assert_eq(w.player_state.dex, 10, "Bowman AP goes to DEX (5 base + 5)")
	assert_eq(w.player_state.str, 12)
	assert_eq(w.player_state.max_hp, hp0 + 22)


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

## Improved HP Recovery (1000000, its `regen` field) owned at `skill_level`; base regeneration off, 1000 max HP,
## invulnerable.
func _regen_world(skill_level: int) -> RunWorld:
	var data := _data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.regen.hp = 0
	data.balance.player.hp = 1000 # room above 1 HP for the whole Lv 16 bonus
	var w := RunWorld.new(RF.setup("quiet", 76, data))
	RF.place_player(w, 400)
	w.learn_skill("improved_hp_recovery")
	w.loadout.set_rank("improved_hp_recovery", skill_level)
	w.god = true
	return w


func test_regen_passive_adds_its_canonical_hp_to_each_pulse() -> void:
	for example: Array in [[1, 3.0], [16, 50.0]]: # the synthetic table's end points: hp 3 at Lv 1, 50 at Lv 16
		var w := _regen_world(int(example[0]))
		assert_eq(w.loadout.regen_bonus(), float(example[1]), "skill level %d" % example[0])
		w._hp = 1.0
		for tick in 600:
			w.step(DT, MoveInput.new())
		assert_eq(w.player_state.hp, 1 + int(example[1]), "one 10 s pulse adds the bonus (level %d)" % example[0])


func test_regen_bonus_is_zero_without_the_skill() -> void:
	var w := RunWorld.new(RF.setup("quiet", 77, _data()))
	assert_eq(w.loadout.regen_bonus(), 0.0)


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
