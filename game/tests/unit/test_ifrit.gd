extends TestCase
## Ifrit (2221005), the I/L Arch Mage's fire ally (spec #319, I9 #328): the Elquines data on the PlayerSummons seam
## plus the opt-in `summon.priority_status` target order. Seeded RunWorld casts and fixed ticks; the real-cache test
## reads the mapped Skill.wz levels and the five animations.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

## Synthetic Skill.wz/222.img Ifrit: the canonical attack info (type 0 box, 3 monsters, 1080 ms) with a short windup so a test
## needs few ticks, `mad` 100 and `time` 3 s at every level.
func _setup(mob_count := 3.0) -> Dictionary:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 328, data)
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 100.0, "mastery": 10.0, "time": 3.0}
	setup.skill_imgs["222"] = {"skill": {"2221005": {"level": levels, "elemAttr": "f",
		"summon": {"attack1": {"info": {"attackAfter": 100.0, "mobCount": mob_count, "priority": 2221003.0,
		"range": {"lt": {"$v": [-200, -150]}, "rb": {"$v": [0, 30]}}}}}}}}
	setup.data.stages.stages.quiet.maps.append(setup.data.stages.stages.quiet.maps[0].duplicate(true))
	return setup

func _world(mob_count := 3.0, learned := true) -> RunWorld:
	var w := RunWorld.new(_setup(mob_count))
	w.set_job(222)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	if learned:
		w.learn_skill("ifrit")
	w.loadout.set_caster(100.0, 0.0, 30)
	return w

func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, 1110100, px, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func _run(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.runner.tick_cooldowns(DT, w)

func test_ifrit_is_a_fire_summon_that_takes_an_active_slot_and_lives_for_the_mapped_time() -> void:
	var w := _world()
	assert_eq(w.loadout.slot_count("active"), 1)
	assert_eq(w.loadout.stats("ifrit").element, "f")
	w.runner.step(DT, w)
	assert_eq(w.runner.summons.living_count(), 1)
	w.loadout.order.clear()
	_run(w, 181)
	assert_eq(w.runner.summons.living_count(), 0)

func test_ifrit_hits_at_most_three_monsters_in_its_box_nearest_first_after_the_wz_delay() -> void:
	var w := _world()
	var mobs: Array[int] = []
	for px in [360.0, 260.0, 300.0, 330.0]:
		mobs.append(_mob(w, px))
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_run(w, 5)
	for m in mobs:
		assert_eq(w.swarm.hp[m], 100000, "windup has no damage")
	_run(w, 3)
	assert_true(w.swarm.hp[mobs[1]] < 100000, "nearest")
	assert_true(w.swarm.hp[mobs[2]] < 100000, "second nearest")
	assert_true(w.swarm.hp[mobs[3]] < 100000, "third nearest")
	assert_eq(w.swarm.hp[mobs[0]], 100000, "the fourth does not fit the canonical mobCount")

func test_a_monster_marked_fire_weak_takes_one_and_a_half_times_ifrits_fire_damage() -> void:
	var lost := {}
	for marked in [false, true]:
		var w := _world(1.0)
		var m := _mob(w, 260)
		if marked:
			w.swarm.apply_status(m, "fire_weak", {"time": 10.0}, w.events)
		w.runner.step(DT, w)
		w.loadout.order.clear()
		_run(w, 8)
		lost[marked] = 100000 - w.swarm.hp[m]
	assert_true(lost[false] > 0)
	assert_near(float(lost[true]) / float(lost[false]), 1.5, 0.02)

## One mob of `mob_count` 1 is hit: returns the slot that lost HP, or -1.
func _first_victim(w: RunWorld, mobs: Array[int]) -> int:
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_run(w, 8)
	for m in mobs:
		if w.swarm.hp[m] < 100000:
			return m
	return -1

func _mark(w: RunWorld, m: int) -> void:
	w.swarm.apply_status(m, "fire_weak", {"time": 10.0}, w.events)

func test_priority_status_ranks_a_marked_monster_before_a_nearer_unmarked_one() -> void:
	var w := _world(1.0)
	var near := _mob(w, 260)
	var far := _mob(w, 330)
	_mark(w, far)
	assert_eq(_first_victim(w, [near, far]), far)

func test_priority_status_ranks_the_nearest_marked_monster_then_the_lowest_slot() -> void:
	var w := _world(1.0)
	var unmarked := _mob(w, 240)
	var far_marked := _mob(w, 340)
	var near_marked := _mob(w, 300)
	_mark(w, far_marked)
	_mark(w, near_marked)
	assert_eq(_first_victim(w, [unmarked, far_marked, near_marked]), near_marked)
	var t := _world(1.0)
	var first := _mob(t, 300)
	var second := _mob(t, 300)
	_mark(t, first)
	_mark(t, second)
	assert_eq(_first_victim(t, [first, second]), first, "equal distance: the lower slot")

func test_priority_status_ranks_a_scheduled_boss_before_a_marked_monster() -> void:
	var w := _world(1.0)
	var marked := _mob(w, 250)
	var boss := _mob(w, 340)
	w.mob_boss[boss] = 0
	_mark(w, marked)
	assert_eq(_first_victim(w, [marked, boss]), boss)

func test_without_priority_status_the_order_is_unchanged_marked_monsters_get_no_preference() -> void:
	var w := _world(1.0)
	w.book.defs.ifrit.summon.erase("priority_status")
	var near := _mob(w, 260)
	var far := _mob(w, 330)
	_mark(w, far)
	assert_eq(_first_victim(w, [near, far]), near)

func test_real_map_transfer_removes_ifrit_and_keeps_its_cooldown() -> void:
	var w := _world()
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_run(w, 30)
	var cooldown := float(w.runner.cooldowns.ifrit)
	assert_true(cooldown > 0.0)
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.summons.living_count(), 0)
	assert_eq(w.runner.cooldowns.ifrit, cooldown)

func test_ifrit_follows_the_character() -> void:
	var w := _world()
	w.runner.step(DT, w)
	w.loadout.order.clear()
	w.player.pos.x += 400
	_run(w, 60)
	assert_true(w.runner.summons.x[0] > 300.0)

const TIERS := ["rare", "epic", "unique", "legendary"]

func test_ifrit_declares_the_four_rarity_lists() -> void:
	var b: Dictionary = _world().book.def("ifrit").rarity_bonuses
	for tier in TIERS:
		assert_eq(b[tier].size(), 1, tier)
		for effect: Dictionary in b[tier][0].effects:
			assert_true(String(effect.stat) in ["damage", "area", "summon_count"], "%s: a stat the summon seam reads" % tier)
	assert_eq(b.rare[0].effects, [{"stat": "damage", "op": "mul", "value": 1.2}])
	assert_eq(b.epic[0].effects, [{"stat": "area", "op": "mul", "value": 1.2}])
	assert_eq(b.unique[0].effects, [{"stat": "summon_count", "op": "add", "value": 1.0}])
	assert_eq(b.legendary[0].id, b.unique[0].id, "legendary shares the unique's repeat counter")
	assert_eq(b.legendary[0].effects, [{"stat": "summon_count", "op": "add", "value": 1.0},
		{"stat": "damage", "op": "mul", "value": 1.2}])

## Casts Ifrit with `effects` applied, lets the allies settle behind the player, then puts a mob at each offset in front of
## the first ally (its facing side; the base attack box reaches 200 px) and returns {allies, lost} (HP lost per mob).
func _cast_with(effects: Array, offsets: Array) -> Dictionary:
	var w := _world(8.0)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod("ifrit", String(e.stat), String(e.op), float(e.value))
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_run(w, 90)
	var mobs: Array[int] = []
	for off: float in offsets:
		mobs.append(_mob(w, w.runner.summons.x[0] + off))
	_run(w, 12)
	var lost := []
	for m in mobs:
		lost.append(100000 - w.swarm.hp[m])
	return {"allies": w.runner.summons.living_count(), "lost": lost}

func test_each_rarity_effect_changes_the_resolved_cast() -> void:
	var bonuses: Dictionary = _world().book.def("ifrit").rarity_bonuses
	var offsets := [100.0, 230.0] # inside the base box, and beyond its 200 px edge (inside the Epic x1.2 box, 240 px)
	var base := _cast_with([], offsets)
	assert_eq(base.allies, 1)
	assert_true(base.lost[0] > 0, "the mob inside the box is hit")
	assert_eq(base.lost[1], 0, "the mob beyond the box is not")
	for tier in TIERS:
		for effect: Dictionary in bonuses[tier][0].effects:
			var with := _cast_with([effect], offsets)
			var label := "%s %s" % [tier, effect.stat]
			match String(effect.stat):
				"damage":
					assert_true(int(with.lost[0]) > int(base.lost[0]), label)
				"area":
					assert_true(int(with.lost[1]) > 0, "%s: the box now reaches the far mob" % label)
				"summon_count":
					assert_eq(with.allies, 2, label)
				_:
					assert_true(false, "%s: a stat this test does not know" % label)

func test_a_stat_the_summon_seam_ignores_changes_nothing() -> void:
	# The audit's negative control: `range` is read by projectile/instant rules, not by an ally's box.
	var base := _cast_with([], [100.0, 230.0])
	var range_mod := _cast_with([{"stat": "range", "op": "mul", "value": 1.2}], [100.0, 230.0])
	assert_eq(range_mod, base)

func test_ifrit_rarity_cards_apply_one_rank_and_the_repeat_rules() -> void:
	for tier in TIERS:
		var a := _world(3.0, false)
		var c := a.upgrades.choice_card("ifrit_new", a, tier)
		assert_false(c.get("rarity_bonus", {}).is_empty(), tier)
		a.upgrades.apply("ifrit_new", a, tier)
		assert_eq(a.loadout.rank("ifrit"), 1, "%s: exactly one rank" % tier)
		match tier:
			"rare": assert_near(a.loadout.skill_stat("ifrit", "damage", 1.0), 1.2)
			"epic": assert_near(a.loadout.stats("ifrit").area, 1.2)
			"unique": assert_near(a.loadout.skill_stat("ifrit", "summon_count", 1.0), 2.0)
			"legendary":
				assert_near(a.loadout.skill_stat("ifrit", "summon_count", 1.0), 2.0)
				assert_near(a.loadout.skill_stat("ifrit", "damage", 1.0), 1.2)
	var w := _world(3.0, false)
	w.upgrades.apply("ifrit_new", w, "epic")
	w.upgrades.apply("ifrit_rank", w, "epic")
	assert_near(w.loadout.stats("ifrit").area, 1.2 * 1.16, 0.00001, "second Epic area repeat is x1.16")
	w.upgrades.apply("ifrit_rank", w, "unique")
	w.upgrades.apply("ifrit_rank", w, "legendary")
	assert_near(w.loadout.skill_stat("ifrit", "summon_count", 1.0), 1.0 + 1.0 + 0.8, 0.00001, "Unique and Legendary share the twin counter")

func test_ifrit_normal_mastery_is_a_five_percent_damage_card_that_repeats_at_point_eight() -> void:
	var w := _world(3.0, false)
	w.upgrades.apply("ifrit_new", w, "normal")
	w.loadout.set_rank("ifrit", 8)
	var normal := w.upgrades.choice_card("ifrit_rank", w)
	assert_eq(normal.card_kind, "mastery")
	assert_near(float(normal.rarity_bonus.effects[0].value), 1.05)
	w.upgrades.apply("ifrit_rank", w, "normal")
	assert_near(w.loadout.skill_stat("ifrit", "damage", 1.0), 1.05)
	w.upgrades.apply("ifrit_rank", w, "normal")
	assert_near(w.loadout.skill_stat("ifrit", "damage", 1.0), 1.05 * 1.04, 0.00001, "the repeat is x0.8 of +5%")

func test_cached_ifrit_mapped_ranks_and_animations() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"222": lib.img("Skill.wz/222.img").root})
	var lo := Loadout.new(book)
	lo.add_skill("ifrit")
	assert_eq(book.max_rank("ifrit"), 8)
	assert_eq(book.skill_id("ifrit"), 2221005)
	assert_eq(lo.stats("ifrit").element, "f")
	# WZ levels 4 / 15 / 30 at ranks 1 / 4 / 8 (I1 field scan): mad 192 / 230 / 300, time 30 / 85 / 160 s, mastery 10.
	var wanted := {1: [4, 192.0, 30.0], 4: [15, 230.0, 85.0], 8: [30, 300.0, 160.0]}
	for rank: int in wanted:
		lo.set_rank("ifrit", rank)
		var st := lo.stats("ifrit")
		assert_eq(int(st.level), wanted[rank][0], "rank %d level" % rank)
		assert_near(book.canonical("ifrit", int(st.level), "mad", 0.0), wanted[rank][1], 0.0001, "rank %d mad" % rank)
		assert_near(book.canonical("ifrit", int(st.level), "mastery", 0.0), 10.0, 0.0001, "rank %d mastery" % rank)
		assert_eq(float(st.duration), wanted[rank][2], "rank %d time" % rank)
	var node: Dictionary = book.skill_node("ifrit")
	var info: Dictionary = node.summon.attack1.info
	assert_eq(int(info.mobCount), 3)
	assert_eq(int(info.attackAfter), 1080)
	assert_eq(int(info.priority), 2221003, "the WZ priority names Ice Demon")
	for a: String in ["summoned", "stand", "move", "attack1", "die"]:
		assert_true(not lib.anim(book.def("ifrit").summon.path + "/" + a).is_empty(), a)
	assert_eq(lib.anim(book.def("ifrit").hit).frame_count(), 8, "hit/0 has 8 frames")
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
