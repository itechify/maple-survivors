extends TestCase
## Brawler MP Recovery (spec #168 ticket #193, docs/GAME_DESIGN.md 7.16): the `self` cast rule with an `mp_below` plus
## `hp_at_least` condition and the `convert` block that pays a share of MaxHP and returns a share of it as MP. Seeded
## RunWorld ticks at a fixed dt on the synthetic map; the shipping definition runs over a synthetic 510 book carrying
## Skill.wz's ten levels (x 10, y 55..100, cooltime 70..25), and a real-cache test checks the original numbers.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MAX_HP := 1000
const MAX_MP := 1000
## Skill.wz/510.img skill 5101005 levels: y (percent of the paid HP returned as MP) and cooltime (seconds) per level.
const GAIN := [55, 60, 65, 70, 75, 80, 85, 90, 95, 100]
const COOLDOWN := [70, 65, 60, 55, 50, 45, 40, 35, 30, 25]


func _book() -> Dictionary:
	var levels := {}
	for i in 10:
		levels[str(i + 1)] = {"hs": "h%d" % (i + 1), "x": 10.0, "y": float(GAIN[i]), "cooltime": float(COOLDOWN[i])}
	return {"skill": {"5101005": {"level": levels}}}


## A world on the synthetic map that owns MP Recovery at `rank`, the pools full at 1000 each, no regeneration, no mobs.
func _world(rank_value := 1, edit: Callable = Callable()) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = MAX_HP
	data.balance.player.mp = MAX_MP
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	if edit.is_valid():
		edit.call(data.skills.skills.mp_recovery)
	var setup := RF.setup("quiet", 193, data)
	setup.skill_imgs["510"] = _book()
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.god = false
	w.learn_skill("mp_recovery")
	w.loadout.set_rank("mp_recovery", rank_value)
	w.drain_events()
	return w


func _pools(w: RunWorld, hp: float, mp: float) -> void:
	w._hp = hp
	w._mp = mp
	w._write_player_state(0.0)


func _tick(w: RunWorld) -> void:
	w.step(DT, MoveInput.new())


func _casts(w: RunWorld) -> int:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast").size()


func test_it_casts_at_mp_29_percent_with_hp_75_percent_and_needs_no_monster() -> void:
	var w := _world()
	_pools(w, 750.0, 290.0)
	_tick(w)
	assert_eq(_casts(w), 1)
	assert_eq(w.player_state.hp, 650, "pays 10% of MaxHP")
	assert_eq(w.player_state.mp, 290 + 55, "level 1 returns 55% of the 100 paid")


func test_it_does_not_cast_at_hp_74_percent_or_mp_30_percent() -> void:
	var low_hp := _world()
	_pools(low_hp, 740.0, 290.0)
	_tick(low_hp)
	assert_eq(_casts(low_hp), 0)
	assert_eq(low_hp.player_state.hp, 740)
	var enough_mp := _world()
	_pools(enough_mp, 1000.0, 300.0)
	_tick(enough_mp)
	assert_eq(_casts(enough_mp), 0, "30% of MaxMP is not below the threshold")
	assert_eq(enough_mp.player_state.mp, 300)
	var edge := _world()
	_pools(edge, 750.0, 299.0)
	_tick(edge)
	assert_eq(_casts(edge), 1, "one point under 30%")


func test_the_cooldown_is_canonical_and_restarts_at_the_cast() -> void:
	for example: Array in [[1, 70], [10, 25]]:
		var w := _world(example[0])
		_pools(w, 1000.0, 0.0)
		_tick(w)
		assert_eq(_casts(w), 1)
		_pools(w, 1000.0, 0.0)
		var ticks := int(example[1]) * 60
		for i in ticks - 2:
			_tick(w)
		assert_eq(_casts(w), 0, "rank %d: still cooling down" % example[0])
		for i in 3:
			_tick(w)
		assert_eq(_casts(w), 1, "rank %d: casts again after %d s" % [example[0], example[1]])


func test_a_blocked_condition_waits_for_the_cooldown_not_the_other_way_round() -> void:
	var w := _world()
	_pools(w, 500.0, 0.0)
	for i in 60:
		_tick(w)
	assert_eq(_casts(w), 0, "HP too low: nothing is spent")
	_pools(w, 900.0, 0.0)
	_tick(w)
	assert_eq(_casts(w), 1, "ready the first tick the condition holds")


func test_hp_paid_and_mp_gained_match_skill_wz_for_every_rank() -> void:
	for rank_value in range(1, 11):
		var w := _world(rank_value)
		_pools(w, 1000.0, 100.0)
		_tick(w)
		assert_eq(w.player_state.hp, 900, "rank %d pays 10%% of MaxHP" % rank_value)
		assert_eq(w.player_state.mp, 100 + GAIN[rank_value - 1], "rank %d returns %d%% of 100" % [rank_value, GAIN[rank_value - 1]])
		var restored := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_restored")
		assert_eq(restored.size(), 1)
		assert_eq(restored[0].stat, "mp")
		assert_eq(restored[0].amount, GAIN[rank_value - 1])
		assert_eq(restored[0].skill, "mp_recovery")


func test_the_share_follows_max_hp_and_rounds_down_the_mp() -> void:
	var w := _world(2)
	w._max_hp = 333
	_pools(w, 333.0, 0.0)
	_tick(w)
	assert_eq(w.player_state.hp, 333 - 33, "10% of 333 rounds to 33")
	assert_eq(w.player_state.mp, 19, "60% of 33 is 19.8, whole points down")


func test_the_gain_never_overfills_mp() -> void:
	var w := _world(10)
	w._max_mp = 120
	_pools(w, 1000.0, 30.0)
	_tick(w)
	assert_eq(w.player_state.mp, 120)
	var restored := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_restored")
	assert_eq(restored[0].amount, 90, "the event reports what was actually gained")


func test_it_never_kills_even_with_a_data_threshold_that_would_allow_it() -> void:
	var w := _world(1, func(d: Dictionary) -> void: d.cast.hp_at_least = 0.0)
	w._max_hp = 1000
	_pools(w, 100.0, 0.0)
	_tick(w)
	assert_eq(_casts(w), 0, "paying the whole remaining 100 HP would leave 0")
	assert_eq(w.player_state.hp, 100)
	_pools(w, 101.0, 0.0)
	_tick(w)
	assert_eq(_casts(w), 1)
	assert_eq(w.player_state.hp, 1)


func test_both_thresholds_live_in_survivor_data() -> void:
	var w := _world(1, func(d: Dictionary) -> void:
		d.cast.mp_below = 0.5
		d.cast.hp_at_least = 0.9)
	_pools(w, 890.0, 400.0)
	_tick(w)
	assert_eq(_casts(w), 0)
	_pools(w, 900.0, 499.0)
	_tick(w)
	assert_eq(_casts(w), 1)
	var st := w.loadout.stats("mp_recovery")
	assert_eq(st.cast_rule, "self")
	assert_near(float(st.cast_params.mp_below), 0.5)


func test_it_waits_while_climbing_like_every_auto_cast() -> void:
	var w := _world()
	RF.place_player(w, -100)
	w.step(DT, MoveInput.make(false, false, true))
	assert_eq(w.player.state, PlayerMotion.ST_LADDER)
	_pools(w, 1000.0, 0.0)
	_tick(w)
	assert_eq(_casts(w), 0)
	assert_eq(w.player_state.hp, 1000)


func test_recovery_still_casts_on_its_hp_threshold_alone() -> void:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 1000
	data.balance.player.mp = 100
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	var w := RunWorld.new(RF.setup("quiet", 13, data))
	RF.place_player(w, 400)
	w.learn_skill("recovery")
	w.take_hit(600, false, "", w.player.pos + Vector2(10, 0))
	w.god = true
	w.step(DT, MoveInput.new())
	assert_eq(w.player_state.buffs.size(), 1, "low HP starts Recovery")
	assert_eq(w.book.def("recovery").buff.hp_threshold, 0.5, "the buff threshold is data, untouched by the new condition")


func test_the_skill_stats_expose_the_conversion_and_the_canonical_cooldown() -> void:
	var w := _world(10)
	var st := w.loadout.stats("mp_recovery")
	assert_eq(st.conversion, {"pay": 0.10, "gain": 1.0})
	assert_near(float(st.cooldown), 25.0)
	assert_eq(st.mp_cost, 0)
	assert_eq(st.damage_type, "none")
	assert_eq(w.loadout.stats("mp_recovery", 1).conversion, {"pay": 0.10, "gain": 0.55})
	assert_eq(w.loadout.stats("mp_recovery", 4).cooldown, 55.0)


func test_cards_offer_learning_and_ten_ranks_to_brawlers_only() -> void:
	var w := RF.quiet_world()
	assert_false("mp_recovery_new" in w.upgrades.eligible(w), "a Beginner is not offered it")
	var card := w.upgrades.card("mp_recovery_new")
	assert_eq(card.kind, "skill_new")
	assert_eq(card.requires.jobs.map(func(j: Variant) -> int: return int(j)), [510])
	assert_eq(w.upgrades.card("mp_recovery_rank").max_rank, 10)
	assert_false(bool(card.power), "it raises no damage output")


func test_the_skill_window_line_names_the_shares_and_the_cooldown_of_the_level() -> void:
	var w := _world(1)
	var text := SkillText.new(w.book)
	assert_eq(text.level_line("mp_recovery", 1, w.loadout.stats("mp_recovery", 1)),
		"Pays 10% of Max HP, recovers 55% of it as MP; 70 sec. between uses")
	assert_eq(text.level_line("mp_recovery", 10, w.loadout.stats("mp_recovery", 10)),
		"Pays 10% of Max HP, recovers 100% of it as MP; 25 sec. between uses")
	assert_true(text.desc("mp_recovery") != "")


func test_original_numbers_resolve_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/510.img")
	assert_true(img != null, "import the Pirate manifest fragment")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"510": img.root})
	var loadout := Loadout.new(book)
	assert_eq(book.max_level("mp_recovery"), 10)
	for rank_value in range(1, 11):
		var st := loadout.stats("mp_recovery", rank_value)
		assert_eq(st.conversion, {"pay": 0.10, "gain": GAIN[rank_value - 1] / 100.0}, "rank %d" % rank_value)
		assert_near(float(st.cooldown), float(COOLDOWN[rank_value - 1]))
	assert_true(lib.sound("Sound.wz/Skill.img/5101005/Use") != null, "the use sound is exported")
	lib.free()
