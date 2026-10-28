extends TestCase
## Player summons through seeded RunWorld casts, combat events and map cleanup.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

func _world() -> RunWorld:
	var setup := RF.setup("quiet", 291, RF.quiet_data())
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 100.0, "mastery": 10.0, "time": 3.0}
	setup.skill_imgs["212"] = {"skill": {"2121005": {"level": levels, "elemAttr": "i",
		"summon": {"attack1": {"info": {"attackAfter": 100.0, "mobCount": 2.0,
		"range": {"lt": {"$v": [-200, -150]}, "rb": {"$v": [0, 30]}}}}}}}}
	setup.data.stages.stages.quiet.maps.append(setup.data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("elquines")
	w.loadout.set_caster(100.0, 0.0, 30)
	return w

func test_summon_uses_an_active_slot_and_lives_for_the_mapped_wz_time() -> void:
	var w := _world()
	assert_eq(w.loadout.slot_count("active"), 1)
	w.runner.step(DT, w)
	assert_eq(w.runner.summons.living_count(), 1)
	w.loadout.order.clear()
	for tick in 181:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.summons.living_count(), 0)

func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, 1110100, px, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func test_summon_attacks_nearest_targets_after_wz_delay_with_ice_damage() -> void:
	var w := _world()
	var far := _mob(w, 360)
	var near := _mob(w, 260)
	var immune := _mob(w, 290)
	w.swarm.mob_kind(near).elements = {"I": 0.0}
	# All three share a kind: Fire Demon's per-mob weakness must override ice immunity only here.
	w.swarm.apply_status(near, "ice_weak", {"time": 10.0}, w.events)
	w.runner.step(DT, w)
	w.loadout.order.clear()
	for tick in 5:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.swarm.hp[near], 100000, "windup has no damage")
	for tick in 3:
		w.runner.tick_cooldowns(DT, w)
	assert_true(w.swarm.hp[near] < 100000, "nearest target takes magic ice damage")
	assert_eq(w.swarm.hp[immune], 100000, "ice immunity remains effective")
	assert_eq(w.swarm.hp[far], 100000, "only two closest targets fit canonical mobCount")

func test_follow_and_real_map_transfer_remove_summons_without_resetting_cooldown() -> void:
	var w := _world()
	w.runner.step(DT, w)
	w.loadout.order.clear()
	w.player.pos.x += 400
	for tick in 60:
		w.runner.tick_cooldowns(DT, w)
	assert_true(w.runner.summons.x[0] > 300.0, "ally follows the character")
	var cooldown := float(w.runner.cooldowns.elquines)
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.summons.living_count(), 0)
	assert_eq(w.runner.cooldowns.elquines, cooldown)

func test_cached_elquines_mapped_rank_and_summon_animations() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := SkillBook.from_data(DataRepo.load_all().skills,
		{"212": lib.img("Skill.wz/212.img").root})
	var lo := Loadout.new(book)
	lo.add_skill("elquines")
	assert_eq(book.max_rank("elquines"), 8)
	assert_eq(int(lo.stats("elquines").level), 4)
	assert_eq(lo.stats("elquines").duration, 30.0)
	lo.set_rank("elquines", 8)
	assert_eq(lo.stats("elquines").duration, 160.0)
	assert_eq(lo.stats("elquines").element, "i")
	for a: String in ["summoned", "stand", "move", "attack1", "die"]:
		assert_true(not lib.anim(book.def("elquines").summon.path + "/" + a).is_empty(), a)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()

func test_impact_does_not_hit_a_target_that_left_during_windup() -> void:
	var w := _world()
	var m := _mob(w, 260)
	w.runner.step(DT, w)
	w.loadout.order.clear()
	w.runner.tick_cooldowns(DT, w)
	w.swarm.x[m] = 1500
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	for tick in 10:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.swarm.hp[m], 100000)

func test_another_skill_id_and_attack_node_share_the_summon_runtime_and_recasts_are_bounded() -> void:
	var w := _world()
	var definition := w.book.def("elquines").duplicate(true)
	definition.skill_id = 9991000
	definition.summon.attack = "attack2"
	w.book.defs["test_ally"] = definition
	var node := w.book.skill_node("elquines").duplicate(true)
	node.summon.attack2 = node.summon.attack1
	w.book.skill_imgs["212"].skill["9991000"] = node
	w.loadout.order.clear()
	w.learn_skill("test_ally")
	w.loadout.add_skill_mod("test_ally", "summon_count", "add", 1.0)
	w.runner.step(DT, w)
	assert_eq(w.runner.summons.living_count(), 2)
	var m := _mob(w, 260)
	for tick in 15:
		w.runner.tick_cooldowns(DT, w)
	assert_true(w.swarm.hp[m] < 100000)
	w.runner.cooldowns.test_ally = 0.0
	w.runner.step(DT, w)
	assert_eq(w.runner.summons.living_count(), 2, "recast replaces its group")
	assert_eq(w.runner.summons.active.size(), 2, "dead slots are reused")
