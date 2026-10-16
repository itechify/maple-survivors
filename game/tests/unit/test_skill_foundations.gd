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
	RF.put_mob(w, 1110100, 225, 195) # body starts at max x: excluded
	RF.put_mob(w, 1110100, 180, 210) # body starts at max y: excluded
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	assert_eq(w.skill_box_targets(Rect2(-100, -60, 120, 60)), PackedInt32Array([b, c, a, min_edge]))
	assert_eq(w.skill_box_targets(Rect2(-100, -60, 120, 60), func(m: int) -> bool: return m == a),
		PackedInt32Array([a]))
	w.player.facing = 1
	assert_eq(w.skill_box_targets(Rect2(-100, -60, 120, 60)), PackedInt32Array([b, c, 4]))
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
