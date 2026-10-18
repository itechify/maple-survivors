extends TestCase
## Synthetic skill contracts shared by spec #31's parallel skill tickets. All worlds use seeded combat RNG.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(cast: Dictionary = {}, kind: String = "instant", on_hit: Dictionary = {}) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = 100
	data.skills.skills["synthetic"] = {"skill_id": 9991000, "book": "999", "kind": kind,
		"damage": "fixed", "ranks": [1, 2], "cooldown": 1.0, "range": 400.0, "speed": 400.0,
		"cast": cast, "on_hit": on_hit}
	var setup := RF.setup("quiet", 31, data)
	setup.skill_imgs["999"] = {"skill": {"9991000": {"level": {
		"1": {"lt": {"$v": [-100.0, -60.0]}, "rb": {"$v": [20.0, 0.0]}, "mobCount": 2.0,
			"attackCount": 2.0, "fixdamage": 10.0, "mpCon": 7.0, "time": 3.0, "prop": 30.0, "x": -40.0},
		"2": {"lt": {"$v": [-120.0, -60.0]}, "rb": {"$v": [30.0, 0.0]}, "mobCount": 3.0,
			"attackCount": 2.0, "fixdamage": 20.0, "mpCon": 9.0, "time": 8.0, "prop": 100.0, "x": -50.0},
	}}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("synthetic")
	w.drain_events()
	return w


func test_stats_resolve_canonical_box_area_count_and_cast_rule() -> void:
	var w := _world({"rule": "box", "min_targets": 2})
	w.loadout.add_skill_mod("synthetic", "area", "mul", 1.2)
	w.loadout.add_skill_mod("synthetic", "count", "add", 1.0)
	w.loadout.add_skill_mod("synthetic", "count", "mul", 2.0)
	var st := w.loadout.stats("synthetic")
	assert_true(st.get("has_box", false))
	assert_true((st.get("box", Rect2()) as Rect2).is_equal_approx(Rect2(-120, -72, 144, 72)))
	assert_eq(st.get("mob_count"), 6)
	assert_near(float(st.get("area", 0)), 1.2)
	assert_eq(st.get("cast_rule"), "box")
	assert_eq(st.get("cast_params"), {"rule": "box", "min_targets": 2})
	var legacy := w.loadout.stats("three_snails")
	assert_false(legacy.get("has_box", true))
	assert_eq(legacy.get("cast_rule"), "")
	assert_eq(legacy.count, 1)


func test_box_query_mirrors_filters_sorts_and_uses_half_open_edges() -> void:
	var w := _world()
	w.player.facing = -1
	# Identical tiny synthetic bodies make the exact boundary and distance examples unambiguous.
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
	w.body_pad = 12.0
	var a := RF.put_mob(w, 1110100, 160, 195)
	var b := RF.put_mob(w, 1110100, 180, 195)
	var c := RF.put_mob(w, 1110100, 180, 195)
	var min_edge := RF.put_mob(w, 1110100, 95, 195)
	var max_edge := RF.put_mob(w, 1110100, 225, 195) # body starts at max x: excluded
	RF.put_mob(w, 1110100, 180, 210) # body starts at max y: excluded
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	assert_eq(w.skill_box_targets(Rect2(-100, -60, 120, 60)), PackedInt32Array([b, c, a, min_edge]))
	assert_eq(w.skill_box_targets(Rect2(-100, -60, 120, 60), func(m: int) -> bool: return m == a),
		PackedInt32Array([a]))
	w.player.facing = 1
	assert_eq(w.skill_box_targets(Rect2(-100, -60, 120, 60)), PackedInt32Array([b, c, max_edge]))
	w.swarm.despawn(b)
	assert_false(b in w.skill_box_targets(Rect2(-100, -60, 120, 60)), "stale grid ignores released mobs")


func _events(w: RunWorld, type: String) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == type)


func test_box_admission_pays_once_and_hits_capped_targets_per_line() -> void:
	var w := _world({"rule": "box", "min_targets": 2}, "projectile")
	w.player.facing = -1
	var a := RF.put_mob(w, 1110100, 165, 195)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_eq(_events(w, "cast").size(), 0, "one target cannot admit min_targets=2")
	assert_eq(w.player_state.mp, 100)
	var b := RF.put_mob(w, 1110100, 145, 195)
	var c := RF.put_mob(w, 1110100, 125, 195)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_eq(_events(w, "cast").size(), 1)
	assert_eq(w.player_state.mp, 93, "one mpCon for the whole cast")
	assert_eq(w.swarm.hp[a], 230, "two lines on nearest")
	assert_eq(w.swarm.hp[b], 230)
	assert_eq(w.swarm.hp[c], 250, "canonical mobCount caps targets")
	assert_eq(w.projectiles.active_count(), 0, "box always resolves instant hits")
	w.runner.step(DT, w)
	assert_eq(_events(w, "cast").size(), 0, "cooldown holds")


func test_box_and_nearest_skip_remaining_lines_after_kill_and_preserve_hit_order_and_rng() -> void:
	for rule: String in ["box", "nearest"]:
		var w := _world({"rule": rule})
		var control := _world({"rule": rule})
		for world: RunWorld in [w, control]:
			world.player.facing = -1
			world.loadout.add_skill_mod("synthetic", "count", "add", 1.0)
			RF.put_mob(world, 1110100, 180, 195)
			RF.put_mob(world, 1110100, 160, 195)
			RF.put_mob(world, 1110100, 140, 195)
			world.swarm.hp[0] = 5
			world.mob_grid.rebuild(world.swarm.x, world.swarm.y, world.swarm.active)
			world.drain_events()
		w.runner.step(DT, w)
		var st := control.loadout.stats("synthetic")
		var limit := 3 if rule == "box" else 2
		var expected: Array = []
		control.hit_mob(0, st, control.visual_index(String(st.hit)))
		expected.append(0)
		for slot in range(1, limit):
			for line in 2:
				control.hit_mob(slot, st, control.visual_index(String(st.hit)))
				expected.append(slot)
		var hits := _events(w, "mob_hit")
		assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), expected, rule)
		assert_eq(hits, _events(control, "mob_hit"), "same damage lines and visuals: " + rule)
		assert_eq(w.swarm.hp, control.swarm.hp, "same per-target damage: " + rule)
		assert_eq(w.rng.state, control.rng.state, "no rolls for lines after death: " + rule)


func test_manual_and_unknown_rules_never_auto_cast_or_wait_for_mp() -> void:
	for rule: String in ["manual", "unimplemented"]:
		var w := _world({"rule": rule})
		RF.put_mob(w, 1110100, 250)
		w.spend_mp(100)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.drain_events()
		w.runner.step(DT, w)
		assert_true(w.drain_events().is_empty(), rule)
		assert_false(w.runner.waiting_mp, rule)


func test_explicit_nearest_uses_legacy_targeting_and_climbing_gate() -> void:
	var w := _world({"rule": "nearest"})
	var a := RF.put_mob(w, 1110100, 350)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.player.state = PlayerMotion.ST_LADDER
	w.runner.step(DT, w)
	assert_eq(_events(w, "cast").size(), 0)
	w.player.state = PlayerMotion.ST_STAND
	w.runner.step(DT, w)
	assert_eq(_events(w, "cast").size(), 1)
	assert_eq(w.swarm.hp[a], 230, "nearest ignores canonical box and keeps count=1")


func test_hit_listeners_observe_cast_level_status_and_live_hp_before_lethal_hit() -> void:
	for projectile: bool in [false, true]:
		var w := _world({}, "projectile" if projectile else "instant", {"status": "freeze", "duration_field": "time"})
		var m := RF.put_mob(w, 1110100, 350)
		var hits: Array = []
		var swarm := w.swarm
		w.add_hit_listener(func(slot: int, hit: Dictionary) -> void:
			hits.append({"slot": slot, "hit": hit.duplicate(), "hp": swarm.hp[slot],
				"freeze": swarm.status_time(slot, MobSwarm.FREEZE)}))
		w.swarm.hp[m] = 5
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.runner.step(DT, w)
		if projectile:
			w.loadout.set_rank("synthetic", 2)
			for tick in 45:
				w.step(DT, MoveInput.new())
		assert_eq(hits.size(), 1, "one hook for the lethal line, projectile=%s" % projectile)
		if hits.is_empty():
			continue
		assert_eq(hits[0].slot, m)
		assert_eq(hits[0].hit, {"skill": "synthetic", "level": 1, "magic": false, "damage": 10, "element": ""})
		assert_eq(hits[0].hp, 5, "listener can absorb from the still-living victim")
		assert_near(hits[0].freeze, 3.0, 1e-6, "status applies first and snapshots launch level")


func test_seeded_on_hit_chance_and_all_status_parameters() -> void:
	var observations: Array = []
	for repeat in 2:
		var w := _world({}, "instant", {"status": "poison", "chance_field": "prop", "duration_field": "time"})
		var m := RF.put_mob(w, 1110100, 350, 195, 100.0)
		var st := w.loadout.stats("synthetic")
		w.drain_events()
		for line in 1000:
			w.hit_mob(m, st, -1)
		var applied := _events(w, "mob_status_applied")
		assert_between(applied.size(), 250, 350, "synthetic 30% prop over 1000 seeded hits")
		observations.append(applied.size())
		assert_near(w.swarm.status_time(m, MobSwarm.POISON), 3.0)
		w.book.defs.synthetic.on_hit = {"status": "slow", "duration_field": "time"}
		w.hit_mob(m, st, -1)
		assert_near(w.swarm.status_time(m, MobSwarm.SLOW), 3.0)
		assert_near(w.swarm.slow_factor[m], 0.6, 1e-6, "canonical signed x")
	assert_eq(observations[0], observations[1], "same seed reproduces status rolls")


func test_hook_receives_post_element_magic_and_physical_hits_but_no_poison_or_immune_hit() -> void:
	for projectile: bool in [false, true]:
		var w := _world({}, "instant", {"status": "freeze", "duration_field": "time"})
		w.loadout.order.clear()
		var mk: MobKind = w.mob_kinds[0]
		mk.move_speed = 0.0
		mk.mdd = 0
		mk.pdd = 0
		var m := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 100.0, false)
		var hits: Array = []
		w.add_hit_listener(func(_slot: int, hit: Dictionary) -> void: hits.append(hit.duplicate()))
		for magic: bool in [false, true]:
			for multiplier: float in [1.5, 0.0]:
				mk.elements["F"] = multiplier
				var st := w.loadout.stats("synthetic")
				st.magic = magic
				st.damage_type = "magic" if magic else "physical"
				st.defense = "mdd" if magic else "pdd"
				st.player_level = mk.level
				st.crit = 0.0 # This checks listener/element routing independently of accuracy crit rolls.
				st.element = "f"
				if projectile:
					w.projectiles.spawn({"x": w.swarm.x[m], "y": w.swarm.y[m] - 5,
						"dmg_min": 10, "dmg_max": 10, "magic": magic, "damage_type": st.damage_type,
						"player_level": mk.level, "element": "f", "skill": "synthetic", "level": 1})
					w.step(DT, MoveInput.new())
				else:
					w.hit_mob(m, st, -1)
		assert_eq(hits.size(), 2, "only the physical and magical nonimmune lines")
		if hits.size() == 2:
			assert_false(hits[0].magic)
			assert_eq(hits[0].damage, 15, "post-element physical damage")
			assert_true(hits[1].magic)
			assert_eq(hits[1].damage, 15, "post-element magic damage")
		w.swarm.apply_status(m, "poison", {"level": 1, "time": 1.0}, w.events)
		for tick in 60:
			w.step(DT, MoveInput.new())
		assert_eq(hits.size(), 2, "poison ticks do not trigger player hit listeners")


func test_restoration_clamps_emits_actual_gain_and_rejects_invalid_pools() -> void:
	var w := _world()
	assert_eq(w.take_hit(20, false, "", w.player.pos - Vector2(10, 0)), 18, "seeded injury setup")
	w.spend_mp(25)
	w.drain_events()
	assert_eq(w.restore_player("hp", 8, "synthetic"), 8)
	assert_eq(w.restore_player("hp", 999, "synthetic"), 10)
	assert_eq(w.restore_player("mp", 999, ""), 25)
	assert_eq(w.restore_player("mp", 1, "synthetic"), 0)
	assert_eq(w.restore_player("hp", -10, "synthetic"), 0)
	assert_eq(w.restore_player("str", 99, "synthetic"), 0)
	assert_eq(w.player_state.hp, w.player_state.max_hp)
	assert_eq(w.player_state.mp, w.player_state.max_mp)
	assert_eq(w.drain_events(), [
		{"type": "player_restored", "stat": "hp", "amount": 8, "skill": "synthetic", "pos": w.player.pos},
		{"type": "player_restored", "stat": "hp", "amount": 10, "skill": "synthetic", "pos": w.player.pos},
		{"type": "player_restored", "stat": "mp", "amount": 25, "skill": "", "pos": w.player.pos},
	])


func test_area_card_has_attack_modifier_score_default() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards.append({"id": "synthetic_area", "kind": "skill_mod", "skill": "three_snails",
		"effects": [{"stat": "area", "op": "mul", "value": 1.2}]})
	var w := RunWorld.new(RF.setup("quiet", 31, data))
	assert_eq(BotInput.card_score(w, {"id": "synthetic_area"}), 70.0, "58 area plus existing 12 current-job bonus")


func test_on_hit_respects_status_immunity_without_suppressing_hit_listeners() -> void:
	for rejection: String in ["boss", "element", "scheduled"]:
		var w := _world({}, "instant", {"status": "freeze", "duration_field": "time"})
		var m := RF.put_mob(w, 1110100, 350)
		var mk := w.swarm.mob_kind(m)
		if rejection == "boss":
			mk.boss = true
		elif rejection == "element":
			mk.element_codes["I"] = "2"
		else:
			w.swarm.steady[m] = 1
		var hits: Array = []
		w.add_hit_listener(func(slot: int, hit: Dictionary) -> void: hits.append([slot, hit.damage]))
		w.drain_events()
		w.hit_mob(m, w.loadout.stats("synthetic"), -1)
		assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 0.0, 1e-6, rejection)
		assert_eq(_events(w, "mob_status_applied").size(), 0, rejection)
		assert_eq(hits, [[m, 10]], "a resisted status still permits listeners on its damaging hit")


func test_every_hit_line_and_piercing_contact_notifies_each_listener_once() -> void:
	for projectile: bool in [false, true]:
		var w := _world({"rule": "box"} if not projectile else {}, "projectile" if projectile else "instant")
		w.player.facing = -1
		var a := RF.put_mob(w, 1110100, 165, 195)
		var b := RF.put_mob(w, 1110100, 145, 195)
		for m: int in [a, b]:
			w.swarm.mob_kind(m).move_speed = 0.0
		var first: Array = []
		var second: Array = []
		w.add_hit_listener(func(slot: int, _hit: Dictionary) -> void: first.append(slot))
		w.add_hit_listener(func(slot: int, _hit: Dictionary) -> void: second.append(slot))
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		if projectile:
			w.loadout.order.clear()
			w.projectiles.spawn({"x": 200, "y": 180, "vx": -200, "range": 100, "radius": 1,
				"dmg_min": 1, "pierce": 1, "skill": "synthetic", "level": 1})
			for tick in 60:
				w.step(DT, MoveInput.new())
			assert_eq(first, [a, b], "one hook per piercing contact")
		else:
			w.runner.step(DT, w)
			assert_eq(first, [a, a, b, b], "one hook per instant attack line")
		assert_eq(second, first, "all registered listeners receive every resolved line")
