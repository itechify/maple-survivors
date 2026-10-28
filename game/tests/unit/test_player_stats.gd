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
	BotInput.auto_choose(w, false) # these tests are about the Magician line: force it at the Lv 10 window


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
	RF.as_job(w, 200)
	assert_eq(w.player_state.pdd, 7.0, "changing weapon keeps the outfit defense")
	assert_eq(w.player_state.avoid, 15.0)


func test_magician_mp_growth_uses_int_before_new_ap() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = [] # No max-MP cards change the known level-growth example; keep the Elixir fallback.
	var w := RunWorld.new(RF.setup("quiet", 503, data))
	w.wear_new_item(1372005) # the Wooden Wand (23 M.ATT) the removed Lv10 advancement used to grant
	_level_to(w, 10)
	assert_eq(w.player_state.int, 41)
	var mp_at_10 := int(w.player_state.max_mp)
	_level_to(w, 11)
	assert_eq(w.player_state.max_mp, mp_at_10 + 26, "22 base + floor(41 INT / 10)")
	assert_eq(w.player_state.int, 45)
	_level_to(w, 12)
	assert_eq(w.player_state.max_mp, mp_at_10 + 52, "next level: 22 base + floor(45 INT / 10)")
	assert_eq(w.player_state.int, 49)
	var bolt := w.loadout.stats("energy_bolt")
	# Hand-computed from combat_math: INT 49 + 23 magic attack, spell attack 20 (mastery 15% for the minimum).
	assert_near(float(bolt.damage_max), 56.356, 0.0001, "Energy Bolt L1 at 49 INT and 23 magic attack")
	assert_near(float(bolt.damage_min), 14.836, 0.0001, "canonical 15% mastery")


func test_max_mp_skill_recomputes_percentage_and_preserves_mp_ratio() -> void:
	var data := RF.quiet_data()
	data.balance.player.mp = 220
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.balance.player.stats.int = 49
	data.balance.regen.mp = 0
	# No level-up MP refill, so the level-up below shows the passive's ratio rule on its own.
	data.balance.level_up_refill = {"hp": 0.0, "mp": 0.0}
	var w := RunWorld.new(RF.setup("quiet", 41, data))
	RF.place_player(w, 400)
	RF.as_job(w, 200)
	assert_eq(w.player_state.max_mp, 220, "base 220 (the old 100 base plus a 120 job grant, #284)")
	assert_true(w.spend_mp(110))
	w.upgrades.apply("improved_max_mp", w)
	assert_eq(w.loadout.level("improved_max_mp"), 1, "the learn card owns the real passive")
	for pick in 4:
		w.upgrades.apply("improved_max_mp_rank", w)
	assert_eq(w.loadout.level("improved_max_mp"), 5)
	assert_eq(w.player_state.max_mp, 242, "rank 5: round(220 base x 1.10)")
	assert_eq(w.player_state.mp, 121, "the half-full MP pool keeps its ratio")
	w.refresh_player_stats()
	assert_eq(w.player_state.max_mp, 242, "recomputing does not compound the multiplier")
	assert_eq(w.player_state.mp, 121, "recomputing does not refill MP")
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.state != RunWorld.PLAYING:
			break
	assert_eq(w.player_state.level, 2)
	assert_eq(w.player_state.max_mp, 271, "base 220 + 22 growth + floor(49 INT/10), times 1.10 rounded once")
	assert_eq(w.player_state.mp, 135, "half of 271 MP, displayed as whole MP without granting the full growth")
	w.set_job(210)
	assert_eq(w.player_state.max_mp, 271, "a job recompute grants nothing (#284) and does not compound the multiplier")
	assert_eq(w.player_state.mp, 135, "and keeps the half-full pool")


func test_real_starter_outfit_defense() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var loader := func(path: String) -> Dictionary:
		var img := lib.img(path)
		return img.root if img != null else {}
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys", 504, Vector2(800, 600), loader,
		lib.mob_root, missing)
	assert_true(missing.is_empty(), "canonical run setup is present: %s" % [missing])
	var w := RunWorld.new(setup)
	assert_eq(w.player_state.pdd, 7.0, "real outfit 3 + 2 + 2 W.DEF")
	assert_eq(w.player_state.mdd, 0.0, "real starter equipment has no M.DEF")
	lib.free()
