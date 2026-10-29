extends TestCase
## The chain cast rule (M12, spec #319 ticket I4): hit the nearest monster, then jump to the nearest unhit one, up to the
## skill's mob_count. Synthetic skill and art; seeded world, fixed dt. The rule lives in ChainCast; SkillRunner dispatches.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "chain_test"
const ACQUIRE := 450.0
const HOP := 200.0


func _definition(cast: Dictionary = {}) -> Dictionary:
	var block := {"rule": "chain", "acquire": ACQUIRE, "hop": HOP, "min_targets": 1}
	block.merge(cast, true)
	return {"skill_id": 9992000, "book": "212", "job": 212, "kind": "instant", "slot": "active", "name": "Chain Test",
		"damage": "magic", "element": "l", "cooldown": 1.6, "ranks": [1, 2, 3, 4, 5, 6, 7, 8], "action": "swingO1",
		"action_time": 0.5, "ball": "", "hit": "Skill.wz/212.img/skill/9992000/hit/0", "effect": "", "cast": block,
		"chain": {"ball": ["Skill.wz/212.img/skill/9992000/ball/0", "Skill.wz/212.img/skill/9992000/ball/1",
			"Skill.wz/212.img/skill/9992000/ball/2"]}}


## A quiet world with the player at x=200 and the synthetic chain skill learned (mobCount 3, one line).
func _world(cast: Dictionary = {}, mob_count := 3.0, lines := 1.0) -> RunWorld:
	var setup := RF.setup("quiet", 323, RF.quiet_data())
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 100.0, "mastery": 10.0, "mobCount": mob_count, "attackCount": lines}
	setup.skill_imgs["212"] = {"skill": {"9992000": {"level": levels, "elemAttr": "l"}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.book.defs[KEY] = _definition(cast)
	w.learn_skill(KEY)
	w.loadout.set_caster(100.0, 0.0, 30)
	w.drain_events()
	return w


func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, 1110100, px, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _plan(w: RunWorld) -> Dictionary:
	return ChainCast.admit(w, w.loadout.stats(KEY), w.cast_origin())


func _targets(plan: Dictionary) -> Array:
	var out := []
	for m: int in plan.get("targets", PackedInt32Array()):
		out.append(m)
	return out


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func test_nothing_in_acquire_range_admits_nothing_and_has_target_agrees() -> void:
	var w := _world()
	var st := w.loadout.stats(KEY)
	assert_true(_plan(w).is_empty())
	assert_false(ChainCast.has_target(w, st, w.cast_origin()))
	var far := _mob(w, 800)
	assert_true(_plan(w).is_empty(), "outside acquire")
	assert_false(ChainCast.has_target(w, st, w.cast_origin()))
	assert_false(w.runner.has_target(w, KEY, st, w.cast_origin()), "the runner agrees")
	w.swarm.x[far] = 500.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	assert_eq(_targets(_plan(w)), [far])
	assert_true(ChainCast.has_target(w, st, w.cast_origin()))
	assert_true(w.runner.has_target(w, KEY, st, w.cast_origin()))
	assert_eq(w.runner.reach_of(st, w), ACQUIRE, "the bot reads acquire as the reach")


func test_the_acquire_boundary_is_inclusive_in_body_centre_distance() -> void:
	var probe := _world()
	var m := _mob(probe, 450)
	var d := probe.mob_center(m).distance_to(probe.cast_origin())
	for case in [[d + 0.01, true], [d - 0.01, false]]:
		var w := _world({"acquire": case[0]})
		_mob(w, 450)
		assert_eq(not _plan(w).is_empty(), case[1], "acquire %s vs distance %s" % [case[0], d])
		assert_eq(w.runner.has_target(w, KEY, w.loadout.stats(KEY), w.cast_origin()), case[1])


func test_hop_goes_to_the_nearest_unhit_to_the_previous_link_not_to_the_caster() -> void:
	var w := _world()
	var head := _mob(w, 260)
	var behind := _mob(w, 100)  # nearer to the caster than the third link, farther from the head
	var third := _mob(w, 400)
	var plan := _plan(w)
	assert_eq(_targets(plan), [head, third], "the chain stops: behind is more than hop from the third link")
	assert_false(behind in _targets(plan))


func test_the_head_is_the_scheduled_boss_first_then_nearest_then_slot() -> void:
	var w := _world()
	var near := _mob(w, 230)
	var tied := _mob(w, 230)
	var boss := _mob(w, 420)
	assert_eq(_targets(_plan(w))[0], near, "nearest, ties by slot")
	assert_true(near < tied)
	w.mob_boss[boss] = 0
	assert_eq(_targets(_plan(w))[0], boss, "a scheduled boss in acquire is the head")


func test_the_hop_boundary_is_inclusive_in_body_centre_distance() -> void:
	var probe := _world()
	var head := _mob(probe, 260)
	var next := _mob(probe, 460)
	var d := probe.mob_center(head).distance_to(probe.mob_center(next))
	for case in [[d + 0.01, 2], [d - 0.01, 1]]:
		var w := _world({"hop": case[0]})
		_mob(w, 260)
		_mob(w, 460)
		assert_eq(_plan(w).targets.size(), case[1], "hop %s vs link distance %s" % [case[0], d])


func test_ties_on_a_hop_go_to_the_lower_slot_and_no_monster_is_struck_twice() -> void:
	var w := _world({}, 6.0)
	var head := _mob(w, 260)
	var a := _mob(w, 330)
	var b := _mob(w, 330)  # same spot as a
	var targets := _targets(_plan(w))
	assert_eq(targets, [head, a, b], "tie by slot, then the remaining one")
	var seen := {}
	for m: int in targets:
		assert_false(seen.has(m), "no repeats")
		seen[m] = true


func test_the_chain_is_capped_at_mob_count_and_fewer_is_fine() -> void:
	var w := _world({}, 3.0)
	for i in 6:
		_mob(w, 250 + 40 * i)
	assert_eq(_plan(w).targets.size(), 3, "cap")
	var lone := _world({}, 3.0)
	_mob(lone, 250)
	assert_eq(_plan(lone).targets.size(), 1, "one monster is a chain of one")


func test_min_targets_refuses_a_shorter_chain_and_has_target_agrees() -> void:
	var w := _world({"min_targets": 2})
	var st := w.loadout.stats(KEY)
	_mob(w, 250)
	assert_true(_plan(w).is_empty())
	assert_false(w.runner.has_target(w, KEY, st, w.cast_origin()))
	_mob(w, 300)
	assert_eq(_plan(w).targets.size(), 2)
	assert_true(w.runner.has_target(w, KEY, st, w.cast_origin()))


func test_count_modifiers_add_links() -> void:
	var w := _world({}, 3.0)
	for i in 6:
		_mob(w, 250 + 40 * i)
	w.loadout.add_skill_mod(KEY, "count", "add", 2.0)
	assert_eq(_plan(w).targets.size(), 5)


func test_area_widens_the_hop_and_range_widens_the_acquire() -> void:
	var w := _world()
	_mob(w, 260)
	var second := _mob(w, 520)  # more than the 200 px hop from the head
	assert_eq(_plan(w).targets.size(), 1)
	w.loadout.add_skill_mod(KEY, "area", "mul", 1.5)  # hop 300
	assert_eq(_targets(_plan(w)).size(), 2, "area widens hop")
	assert_eq(w.runner.reach_of(w.loadout.stats(KEY), w), ACQUIRE, "area does not move acquire")
	assert_true(second in _targets(_plan(w)))
	var far := _world()
	_mob(far, 800)  # 600 px from the caster, beyond acquire
	assert_true(_plan(far).is_empty())
	far.loadout.add_skill_mod(KEY, "range", "mul", 1.5)  # acquire 675
	assert_eq(_plan(far).targets.size(), 1, "range widens acquire")
	assert_eq(far.runner.reach_of(far.loadout.stats(KEY), far), ACQUIRE * 1.5)


func test_cast_strikes_every_link_on_the_cast_tick_with_attack_count_lines_and_unchanged_damage() -> void:
	var w := _world({}, 3.0, 2.0)
	var a := _mob(w, 260)
	var b := _mob(w, 330)
	var c := _mob(w, 400)
	var after := _mob(w, 470)  # a fourth monster in hop range: the cap leaves it alone
	w.swarm.hp[after] = 100000
	w.runner.step(DT, w)
	var events := w.drain_events()
	var hits := _hits(events)
	assert_eq(hits.size(), 6, "3 links x 2 lines")
	var order := []
	for h: Dictionary in hits:
		order.append(int(h.mob))
	assert_eq(order, [a, a, b, b, c, c], "chain order, lines together")
	assert_eq(w.swarm.hp[after], 100000)
	var first_damage := float(hits[0].damage)
	assert_true(first_damage > 0.0)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1)
	for h: Dictionary in hits:
		assert_eq(String(h.hit_visual), "Skill.wz/212.img/skill/9992000/hit/0", "the hit burst on every link")
		assert_true(float(h.damage) <= first_damage * 3.0, "no falloff along the chain")


func test_skill_chain_event_carries_the_hand_then_each_link_centre() -> void:
	var w := _world({}, 3.0)
	var a := _mob(w, 260)
	var b := _mob(w, 330)
	w.runner.step(DT, w)
	var events := w.drain_events()
	var chain := events.filter(func(e: Dictionary) -> bool: return e.type == "skill_chain")
	assert_eq(chain.size(), 1)
	var e: Dictionary = chain[0]
	assert_eq(String(e.skill), KEY)
	assert_eq(int(e.skill_id), 9992000)
	var points: PackedVector2Array = e.points
	assert_eq(points.size(), 3)
	assert_eq(points[1], w.mob_center(a))
	assert_eq(points[2], w.mob_center(b))
	assert_eq(points[0], w.shot_origin(w.mob_center(a)), "the caster's hand")
	var types := events.map(func(x: Dictionary) -> String: return x.type)
	assert_true(types.find("cast") < types.find("skill_chain"), "cast, then the chain")
	assert_true(types.find("skill_chain") < types.find("mob_hit"), "the bolt is announced before the hits")


func test_a_monster_that_is_gone_by_its_turn_is_skipped_and_leaves_the_bolt() -> void:
	var w := _world({}, 3.0)
	var a := _mob(w, 260)
	var b := _mob(w, 330)
	var c := _mob(w, 400)
	var plan := _plan(w)
	assert_eq(_targets(plan), [a, b, c])
	w.swarm.active[b] = 0
	ChainCast.resolve(w, KEY, w.loadout.stats(KEY), plan, -1)
	var events := w.drain_events()
	var struck := _hits(events).map(func(e: Dictionary) -> int: return int(e.mob))
	assert_eq(struck, [a, c])
	var points: PackedVector2Array = events.filter(func(e: Dictionary) -> bool: return e.type == "skill_chain")[0].points
	assert_eq(points.size(), 3, "hand, a, c")


func test_selection_and_admission_draw_no_random_numbers() -> void:
	var w := _world({}, 4.0)
	var twin := _world({}, 4.0)
	for world in [w, twin]:
		for i in 5:
			_mob(world, 250 + 45 * i)
	var before := w.rng.state
	_plan(w)
	ChainCast.has_target(w, w.loadout.stats(KEY), w.cast_origin())
	assert_eq(w.rng.state, before, "no draw while choosing")
	assert_eq(w.rng.state, twin.rng.state)
	w.runner.step(DT, w)
	twin.runner.step(DT, twin)
	assert_eq(w.rng.state, twin.rng.state, "identical worlds consume the same stream")
	assert_ne(w.rng.state, before, "the hits themselves roll damage")


func test_the_caster_faces_the_head() -> void:
	var w := _world()
	_mob(w, 100)  # 100 px left of the player
	w.player.facing = 1
	w.runner.step(DT, w)
	assert_eq(w.player.facing, -1)


func test_map_transfer_preserves_chain_cooldown_and_allows_the_next_cast() -> void:
	var w := _world()
	_mob(w, 260)
	w.runner.step(DT, w)
	var cooldown := float(w.runner.cooldowns[KEY])
	var maps: Array = w.setup.data.stages.stages.quiet.maps
	maps.append(maps[0].duplicate(true))
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.cooldowns[KEY], cooldown)
	assert_true(w.loadout.has(KEY))
	_mob(w, w.player.pos.x + 60)
	w.drain_events()
	w.runner.step(DT, w)
	assert_eq(_hits(w.drain_events()).size(), 0, "transfer grants no free recast")
	for tick in 100:
		w.runner.tick_cooldowns(DT, w)
	w.runner.step(DT, w)
	assert_true(_hits(w.drain_events()).size() > 0, "chain works on the next map after its cooldown")
