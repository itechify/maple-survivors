extends TestCase
## Seeded fixed-tick F/P high-job attacks at the RunWorld boundary.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

func _world(key: String) -> RunWorld:
	var setup := RF.setup("quiet", 290, RF.quiet_data())
	for book: String in ["211", "212"]:
		setup.skill_imgs[book] = {"skill": {}}
	for id: int in [2111002, 2111003, 2111006, 2121001, 2121003, 2121006, 2121007]:
		var levels := {}
		for lv in range(1, 31):
			levels[str(lv)] = {"mad": 120.0, "mobCount": 6.0, "attackCount": 2.0,
				"time": 4.0, "prop": 100.0, "lt": {"$v": [-200, -150]}, "rb": {"$v": [200, 150]}}
		setup.skill_imgs[str(id / 10000)].skill[str(id)] = {"level": levels}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_caster(100.0, 0.0, 30)
	return w

func _mob(w: RunWorld, x: float = 250.0) -> int:
	var m := RF.put_mob(w, 1110100, x, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.swarm.mob_kind(m).move_speed = 0.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func test_explosion_strikes_both_sides_with_canonical_lines() -> void:
	var w := _world("explosion")
	_mob(w, 150)
	_mob(w, 250)
	w.drain_events()
	w.runner.step(DT, w)
	var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
	assert_eq(hits.size(), 4, "two canonical lines on each side")

func _advance(w: RunWorld, seconds: float) -> Array:
	w.loadout.order.clear()
	for tick in ceili(seconds / DT):
		w.runner.tick_cooldowns(DT, w)
	return w.drain_events()

func test_mist_poisons_new_arrivals_and_expires_at_its_ground_anchor() -> void:
	var w := _world("poison_mist")
	var m := _mob(w)
	w.runner.step(DT, w)
	_advance(w, 1.0)
	assert_true(w.swarm.status_time(m, MobSwarm.POISON) > 0.0)
	var later := _mob(w, 160)
	_advance(w, 1.0)
	assert_true(w.swarm.status_time(later, MobSwarm.POISON) > 0.0)
	_advance(w, 3.0)
	var expired := _mob(w, 180)
	_advance(w, 1.0)
	assert_eq(w.swarm.status_time(expired, MobSwarm.POISON), 0.0)

func test_element_composition_projectile_poisons_and_averages_fire_poison_attributes() -> void:
	var w := _world("element_composition")
	var m := _mob(w)
	w.swarm.mob_kind(m).elements = {"F": 1.5, "S": 0.5}
	w.runner.step(DT, w)
	w.loadout.order.clear()
	for tick in 60:
		w.step(DT, MoveInput.new())
	assert_true(w.swarm.status_time(m, MobSwarm.POISON) > 0.0)
	assert_near(w.swarm.element_multiplier(m, "fs"), 1.0)

func test_fire_demon_leaves_timed_ice_weakness_and_bosses_reject_it() -> void:
	var w := _world("fire_demon")
	var m := _mob(w)
	w.runner.step(DT, w)
	assert_near(w.swarm.element_multiplier(m, "i"), 1.5)
	assert_near(w.swarm.element_multiplier(m, "f"), 1.0)
	w.swarm.mob_kind(m).boss = true
	assert_false(w.swarm.apply_status(m, "ice_weak", {"time": 4.0}, w.events))

func test_paralyze_stuns_ordinary_mobs_but_never_bosses() -> void:
	for boss: bool in [false, true]:
		var w := _world("paralyze")
		var m := _mob(w)
		w.swarm.mob_kind(m).boss = boss
		w.runner.step(DT, w)
		assert_eq(w.swarm.status_time(m, MobSwarm.STUN) > 0.0, not boss)

func test_meteor_hits_only_after_delay_and_queries_living_targets_at_impact() -> void:
	var w := _world("meteor_shower")
	var m := _mob(w)
	w.runner.step(DT, w)
	assert_eq(w.swarm.hp[m], 100000)
	_advance(w, 1.7)
	assert_eq(w.swarm.hp[m], 100000)
	_advance(w, 0.11)
	assert_true(w.swarm.hp[m] < 100000)

func test_big_bang_charges_before_full_power_release_and_pending_clears_on_transfer() -> void:
	var w := _world("big_bang")
	var m := _mob(w)
	w.runner.step(DT, w)
	assert_eq(w.swarm.hp[m], 100000)
	_advance(w, 1.0)
	assert_eq(w.swarm.hp[m], 100000)
	_advance(w, 0.1)
	assert_true(w.swarm.hp[m] < 100000)
	var other := _world("big_bang")
	var n := _mob(other)
	other.runner.step(DT, other)
	other.runner.clear_pending()
	_advance(other, 2.0)
	assert_eq(other.swarm.hp[n], 100000)

func test_mist_does_not_postpone_existing_poison_pulses() -> void:
	var w := _world("poison_mist")
	var m := _mob(w)
	w.runner.step(DT, w)
	w.loadout.order.clear()
	for tick in 190:
		w.step(DT, MoveInput.new())
	assert_true(w.swarm.poison_dealt >= 3000, "two canonical poison pulses survive overlapping area applications")

func test_cached_high_actives_resolve_all_ranks_art_and_sounds() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var imgs := {}
	for book: String in ["211", "212"]:
		imgs[book] = lib.img("Skill.wz/%s.img" % book).root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var lo := Loadout.new(book)
	for key: String in ["explosion", "poison_mist", "element_composition", "fire_demon", "paralyze", "meteor_shower", "big_bang"]:
		# Independent loadout so all seven definitions can be inspected despite the six-slot limit.
		lo = Loadout.new(book)
		assert_true(lo.add_skill(key))
		assert_eq(book.max_rank(key), 8)
		lo.set_rank(key, 8)
		assert_eq(int(lo.stats(key).level), 30)
		var d := book.def(key)
		var paths: Array = [d.effect, d.ball, d.hit]
		paths.append_array(d.get("release_visuals", []))
		for visual: Dictionary in d.get("cast_visuals", []):
			paths.append(visual.path)
		paths.append(String(d.get("ground", {}).get("tile", "")))
		for path: String in paths:
			if path != "":
				assert_true(lib.anim(path).frames.size() > 0, path)
		for path: String in d.sounds.values():
			assert_true(lib.sound(path) != null, path)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()

func test_fire_demon_weakness_expires_and_does_not_mutate_shared_mob_kind() -> void:
	var w := _world("fire_demon")
	var m := _mob(w)
	w.swarm.mob_kind(m).elements = {"I": 0.0}
	w.runner.step(DT, w)
	var other := _mob(w, 600)
	assert_near(w.swarm.element_multiplier(m, "i"), 1.5)
	assert_near(w.swarm.element_multiplier(other, "i"), 0.0)
	w.loadout.order.clear()
	for tick in 241:
		w.step(DT, MoveInput.new())
	assert_near(w.swarm.element_multiplier(m, "i"), 0.0)

func test_delayed_attacks_use_impact_positions_not_recycled_target_slots() -> void:
	for key: String in ["meteor_shower", "big_bang"]:
		var w := _world(key)
		var m := _mob(w)
		w.runner.step(DT, w)
		w.swarm.x[m] = 1500.0
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		_advance(w, 2.0)
		assert_eq(w.swarm.hp[m], 100000, "mob that left the box takes no delayed damage")

func test_mist_skill_damage_modifiers_scale_its_poison_pulses() -> void:
	var totals: Array[int] = []
	for multiplier: float in [1.0, 2.0]:
		var w := _world("poison_mist")
		_mob(w)
		w.loadout.add_skill_mod("poison_mist", "damage", "mul", multiplier)
		w.runner.step(DT, w)
		w.loadout.order.clear()
		for tick in 150:
			w.step(DT, MoveInput.new())
		totals.append(w.swarm.poison_dealt)
	assert_eq(totals[1], totals[0] * 2, "damage bonuses work on ground poison")
