extends TestCase
## Seeded run behavior for automatic AP, job redistribution and canonical equipment-derived stats.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


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


func test_beginner_ap_and_magician_redistribution() -> void:
	var w := RF.quiet_world(400.0, 501)
	assert_eq(w.player_state.str, 12)
	assert_eq(w.player_state.dex, 5)
	assert_eq(w.player_state.int, 4)
	assert_eq(w.player_state.luk, 4)
	var beginner_str := [17, 22, 27, 32, 37, 42]
	for level in range(2, 8):
		_level_to(w, level)
		assert_eq(w.player_state.str, beginner_str[level - 2], "all Beginner AP goes to STR")
		assert_eq(w.player_state.int, 4, "a Beginner receives no INT AP")
	_level_to(w, 8)
	assert_eq(w.player_state.job_id, 200)
	assert_eq(w.player_state.str, 12, "only earned AP is reset")
	assert_eq(w.player_state.int, 39, "seven levels of AP move to INT")
	assert_eq(w.player_state.dex, 5)
	assert_eq(w.player_state.luk, 4)
	_level_to(w, 9)
	assert_eq(w.player_state.int, 44)
	assert_eq(w.player_state.str, 12)


func test_worn_equipment_defense_and_avoid() -> void:
	var setup := RF.setup("quiet", 502, RF.quiet_data())
	setup.data.balance.player.stats = {"str": 12, "dex": 20, "int": 4, "luk": 10}
	setup.equipment_info = {
		1040002: {"incPDD": 3.0, "incMDD": 2.0, "incEVA": 1.0},
		1060002: {"incPDD": 2.0, "incMDD": 3.0},
		1072001: {"incPDD": 2.0, "incEVA": 4.0},
		1302000: {"incPDD": 0.0},
		1372005: {"incMAD": 23.0},
		9999999: {"incPDD": 999.0}, # An unworn item must not count.
	}
	var w := RunWorld.new(setup)
	assert_eq(w.player_state.pdd, 7.0, "sum of the worn gear's defense")
	assert_eq(w.player_state.mdd, 5.0)
	assert_eq(w.player_state.avoid, 15.0, "20 DEX / 4 + 10 LUK / 2 + 5 gear avoid")
	w.change_job(200)
	assert_eq(w.player_state.pdd, 7.0, "changing weapon keeps the outfit defense")
	assert_eq(w.player_state.avoid, 15.0)


func test_magician_mp_growth_uses_int_before_new_ap() -> void:
	var data := RF.quiet_data()
	data.upgrades = {"cards": []} # No max-MP cards change the known level-growth example.
	var w := RunWorld.new(RF.setup("quiet", 503, data))
	_level_to(w, 8)
	assert_eq(w.player_state.int, 39)
	var mp_at_8 := int(w.player_state.max_mp)
	_level_to(w, 9)
	assert_eq(w.player_state.max_mp, mp_at_8 + 25, "22 base + floor(39 INT / 10)")
	assert_eq(w.player_state.int, 44)
	_level_to(w, 10)
	assert_eq(w.player_state.max_mp, mp_at_8 + 51, "next level: 22 base + floor(44 INT / 10)")
	var bolt := w.loadout.stats("energy_bolt")
	assert_near(float(bolt.damage_max), 56.356, 0.0001, "Energy Bolt L1 at 49 INT and 23 magic attack")
	assert_near(float(bolt.damage_min), 14.836, 0.0001, "canonical 15% mastery")


func test_real_starter_outfit_defense() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var loader := func(path: String) -> Dictionary:
		var img := lib.img(path)
		return img.root if img != null else {}
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys_hg1", 504, Vector2(800, 600), loader,
		lib.mob_root, missing)
	assert_true(missing.is_empty(), "canonical run setup is present: %s" % [missing])
	var w := RunWorld.new(setup)
	assert_eq(w.player_state.pdd, 7.0, "real outfit 3 + 2 + 2 W.DEF")
	assert_eq(w.player_state.mdd, 0.0, "real starter equipment has no M.DEF")
	lib.free()
