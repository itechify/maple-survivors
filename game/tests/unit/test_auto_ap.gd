extends TestCase
## Automatic AP split between a job line's secondary stat and its primary stat (spec #33 ticket #106): the pure split,
## seeded Magician and Beginner levelling through RunWorld, and loading the committed Lv38 Magician snapshot.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const FIXTURE := "res://tests/fixtures/characters/lv35_magician_2nd.json"

## v83 Character.wz reqLUK of the Magician equipment levels: the independent source for the LUK targets.
const V83_REQ_LUK := {13: 15, 28: 30, 38: 40, 48: 50, 58: 60, 68: 70}


func _keyframes() -> Array:
	return DataRepo.load_all().balance.player.ap_secondary["200"].keyframes


func _level_to(w: RunWorld, target: int) -> void:
	var exp := (w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level)
		- w.progression.exp)
	w.pickups.spawn(w.player.pos, exp, 4000019)
	for tick in 120:
		w.step(1.0 / 60.0, MoveInput.new())
		if int(w.player_state.level) == target:
			break
	assert_eq(int(w.player_state.level), target, "EXP was collected through the run")
	RF.auto_choose(w)


func test_luk_target_matches_the_v83_magician_requirements() -> void:
	var kf := _keyframes()
	for level: int in V83_REQ_LUK:
		assert_eq(AutoAp.secondary_target(kf, level), V83_REQ_LUK[level], "Lv%d target" % level)


func test_split_fills_the_secondary_stat_up_to_target_and_never_more_than_earned() -> void:
	var kf := _keyframes()
	assert_eq(AutoAp.secondary_ap(45, 10, 4.0, kf), 8, "Lv10 target 12 from base LUK 4 needs 8 of 45 AP")
	assert_eq(AutoAp.secondary_ap(5, 10, 4.0, kf), 5, "capped by the AP earned")
	assert_eq(AutoAp.secondary_ap(45, 10, 20.0, kf), 0, "a base above the target takes no AP")
	assert_eq(AutoAp.secondary_ap(0, 10, 4.0, kf), 0)
	assert_eq(AutoAp.secondary_ap(45, 10, 4.0, []), 0, "no keyframes means no secondary stat")


func test_magician_levelled_from_10_to_70_keeps_base_luk_at_target_and_the_rest_in_int() -> void:
	var w := RF.quiet_world(400.0, 601)
	_level_to(w, 9)
	for level in range(10, 71):
		_level_to(w, level)
		assert_true(int(w.player_state.job_id) in [200, 210, 220, 230], "a Magician line job")
		var earned := 5 * (level - 1)
		# Base values come from the Beginner start (LUK 4, INT 4); equipment is not involved here.
		var luk := int(w.player_state.luk)
		assert_true(luk >= level + 2, "Lv%d base LUK %d reaches the target" % [level, luk])
		assert_eq(luk, mini(4 + earned, level + 2), "Lv%d LUK takes exactly the AP needed for the target" % level)
		assert_eq(int(w.player_state.int), 4 + earned - (luk - 4), "Lv%d every other point goes to INT" % level)
		assert_eq(int(w.player_state.str), 12, "the Magician's STR gets no AP")
		assert_eq(int(w.player_state.dex), 5)


func test_beginner_attributes_are_unchanged_at_every_level() -> void:
	var data := RF.quiet_data()
	# Keep the line at Beginner past Lv10 so that only the Beginner rules are exercised.
	data.jobs_survivor.jobs["200"].playable = false
	data.jobs_survivor.jobs["100"].playable = false
	data.jobs_survivor.jobs["500"].playable = false
	var w := RunWorld.new(RF.setup("quiet", 602, data))
	RF.place_player(w, 400.0)
	for level in range(2, 31):
		_level_to(w, level)
		assert_eq(int(w.player_state.job_id), 0)
		assert_eq(int(w.player_state.str), 12 + 5 * (level - 1), "Lv%d all AP to STR" % level)
		assert_eq(int(w.player_state.dex), 5)
		assert_eq(int(w.player_state.int), 4)
		assert_eq(int(w.player_state.luk), 4)


func test_committed_lv38_magician_snapshot_derives_the_split_on_load() -> void:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(FIXTURE, errors)
	assert_eq(errors, PackedStringArray())
	if character.is_empty():
		return
	var setup := RF.setup("quiet", 2, RF.quiet_data())
	setup.character = character
	var w := RunWorld.new(setup)
	assert_eq(int(w.progression.level), 38)
	assert_eq(int(w.player_state.luk), 40, "base LUK 4 + 36 AP reaches the Lv38 target")
	assert_eq(int(w.player_state.int), 153, "base INT 4 + 185 earned - 36 AP moved to LUK")
	assert_eq(int(w.character_snapshot().earned_ap), 185, "the snapshot still stores only earned AP")
