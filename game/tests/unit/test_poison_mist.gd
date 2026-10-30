extends TestCase
## Poison mist (MobSkill 131, #459): a pooled ground hazard placed in front of the boss that slows (ice) or poisons (poison)
## whoever stands in it, through seeded synthetic RunWorld ticks (independent of the asset cache).
const MF := preload("res://tests/fixtures/mano_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MAPS := preload("res://tests/fixtures/map_transfer_fixtures.gd")
const DT := 1.0 / 60.0
const BOSS_AT := Vector2(600, 200)


## A world whose boss casts only a synthetic 131 level shaped like Snowman's 131/7 (x 500, interval 30, time 10, box
## (-50,-160)-(300,40)); `elem` is the level's elemAttr ("" for none). The boss stands at BOSS_AT, the player (outside the
## mist) at x 450 and the regen is off, so HP only changes by poison.
func _world(elem := "I", x := 500.0, interval := 30.0, time := 10.0, prop := 100.0, seed_value := 22) -> RunWorld:
	var setup := MF.setup([126], seed_value)
	setup.mob_imgs[2220000].info.skill = {"0": {"skill": 131.0, "level": 7.0, "action": 1.0}}
	var level := {"interval": interval, "time": time, "prop": prop, "x": x,
		"lt": {"$v": [-50.0, -160.0]}, "rb": {"$v": [300.0, 40.0]}, "affected": {"repeat": 1.0},
		"tile": {"0": {"0": {"delay": 900.0}}, "1": {"0": {"delay": 700.0}}, "2": {"0": {"delay": 750.0}}}}
	if elem != "":
		level["elemAttr"] = elem
	setup.mob_skill_img = {"131": {"level": {"7": level}}}
	setup.mob_imgs[2220000].skill1 = {"0": {"delay": 10.0}}
	setup.data.balance.regen = {"interval": 100000.0, "hp": 0.0}
	var w := RunWorld.new(setup)
	w.god = true
	RF.place_player(w, 450)
	w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot, BOSS_AT, w.fhm.find_below(600, 190))
	w.drain_events()
	return w


func _ticks(w: RunWorld, n: int) -> void:
	for tick in n:
		w.step(DT, MoveInput.new())


## Ticks to the cast (first at one interval) and returns the `hazard_spawned` events the cast made.
func _cast(w: RunWorld, interval := 30.0) -> Array:
	_ticks(w, roundi(interval * 60.0) - 1)
	assert_eq(w.hazards.active_count(), 0, "no mist before the interval")
	_ticks(w, 1)
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "hazard_spawned")


func _slowed(w: RunWorld) -> bool:
	return not w.player_state.get("slow", {}).is_empty()


func _poisoned(w: RunWorld) -> bool:
	return not w.player_state.get("poison", {}).is_empty()


func _stand(w: RunWorld, x: float) -> void:
	RF.place_player(w, x)


## The level's box is placed relative to the boss at the cast, mirrored by its facing, and lasts exactly `time`.
func test_placement_is_the_level_box_mirrored_by_facing() -> void:
	var left := _world()
	var spawned := _cast(left)
	assert_eq(spawned.size(), 1)
	assert_eq(int(left.swarm.facing[int(left.bosses.records[0].slot)]), -1, "the boss faces the player on its left")
	assert_eq(left.hazards.rect(0), Rect2(BOSS_AT + Vector2(-50, -160), Vector2(350, 200)), "the raw box facing left")
	assert_eq(spawned[0].rect, left.hazards.rect(0))
	assert_eq(left.hazards.cast_count, 1)
	var right := _world()
	_ticks(right, 1)
	_stand(right, 700)
	_ticks(right, 1799)
	_stand(right, 700)
	_ticks(right, 1)
	assert_eq(right.hazards.active_count(), 1)
	assert_eq(int(right.swarm.facing[int(right.bosses.records[0].slot)]), 1, "facing right")
	assert_eq(right.hazards.rect(0), Rect2(BOSS_AT + Vector2(-300, -160), Vector2(350, 200)), "mirrored: x -300..50")


## The mist lasts exactly `time` (live on the tick before the end, gone on it), then its slot is free and the counters
## keep what it was.
func test_lifetime_is_time_and_counts_seconds() -> void:
	var w := _world()
	_cast(w)
	var born := w.time
	_ticks(w, 599)
	assert_eq(w.hazards.active_count(), 1, "alive one tick before time")
	assert_true(w.hazards.is_live(0, w.time))
	_ticks(w, 1)
	assert_near(w.time - born, 10.0, 1e-6)
	assert_eq(w.hazards.active_count(), 0, "gone after exactly 10 s")
	assert_near(w.hazards.seconds, 10.0, 0.02, "10 s of hazard time")
	assert_eq(w.hazards.cast_count, 1)
	_ticks(w, 600)
	assert_near(w.hazards.seconds, 10.0, 0.02, "an expired mist adds nothing")


## Ice: Slow while the body is in the box (the 126 rule's x80), ending slow_seconds after leaving; nothing before entering.
func test_ice_slows_on_enter_and_releases_after_leaving() -> void:
	var w := _world("I")
	_cast(w)
	assert_false(_slowed(w), "outside the box at the cast")
	_ticks(w, 30)
	assert_false(_slowed(w))
	_stand(w, 620)
	_ticks(w, 1)
	assert_true(_slowed(w), "slowed on the tick it enters")
	assert_near(w.mob_skills.speed_multiplier(w.time), 0.8, 1e-6, "126's x80 as 80% speed")
	assert_true(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "hazard_status" and int(e.skill_id) == 126))
	_ticks(w, 120)
	assert_true(_slowed(w), "stays while inside")
	_stand(w, 450)
	_ticks(w, 59)
	assert_true(_slowed(w), "a moment of slow after leaving (slow_seconds 1)")
	_ticks(w, 2)
	assert_false(_slowed(w), "then it ends")
	_stand(w, 620)
	_ticks(w, 1)
	assert_true(_slowed(w), "and the mist slows again when re-entered")


## A Slow already on the character is never weakened or shortened by the mist.
func test_ice_does_not_weaken_a_longer_slow() -> void:
	var w := _world("I")
	_cast(w)
	w.mob_skills.statuses.apply(126, w.time, 12.0, {"multiplier": 0.5, "visual": ""}, false)
	_stand(w, 620)
	_ticks(w, 5)
	assert_near(w.mob_skills.speed_multiplier(w.time), 0.5, 1e-6, "the stronger slow stays")
	assert_true(float(w.player_state.slow.remaining) > 11.0, "and keeps its long duration")


## Poison: the level's x HP per second (capped), never lethal, with source_kind "poison"; a status still on is not
## refreshed, and the poison outlasts the mist.
func test_poison_applies_the_level_x_and_outlasts_the_mist() -> void:
	var w := _world("S", 4.0)
	_cast(w)
	w.god = false
	w.grant_second_life(45.0)
	_stand(w, 620)
	_ticks(w, 1)
	assert_true(_poisoned(w), "poisoned on entering")
	assert_eq(int(w.player_state.poison.x), 4)
	var applied := w.time
	_ticks(w, 59)
	assert_eq(int(w.player_state.hp), 45)
	_ticks(w, 1)
	assert_eq(int(w.player_state.hp), 41, "x HP at one second")
	_ticks(w, 600)
	assert_eq(w.hazards.active_count(), 0, "the mist is over")
	assert_true(w.time > applied + 10.0)
	assert_eq(int(w.player_state.hp), 45 - 4 * 10, "ten whole-second ticks in all (poison_seconds 10), mist or not")
	var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
	assert_true(hits.all(func(e: Dictionary) -> bool: return e.source_kind == "poison"))


func test_poison_x_is_capped_and_never_lethal() -> void:
	var w := _world("S", 800.0)
	_cast(w)
	w.god = false
	w.grant_second_life(40.0)
	_stand(w, 620)
	_ticks(w, 1)
	assert_eq(int(w.player_state.poison.x), 300, "the level's 800 is capped at poison_x_max")
	_ticks(w, 61)
	assert_eq(int(w.player_state.hp), 1, "one tick takes it to 1 HP, not 0")
	assert_eq(w.state, RunWorld.PLAYING)


## Poison applies once while it lasts (the lockout floor): standing in the mist for its whole life is a single poisoning.
func test_poison_is_not_reapplied_while_standing_in_the_mist() -> void:
	var w := _world("S", 2.0)
	_cast(w)
	w.god = false
	w.grant_second_life(45.0)
	_stand(w, 620)
	_ticks(w, 1)
	var events := w.drain_events()
	_ticks(w, 300)
	events.append_array(w.drain_events())
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "hazard_status").size(), 1, "announced once")
	assert_between(float(w.player_state.poison.remaining), 4.9, 5.1, "ten s from the first tick, not refreshed")


## A level with no elemAttr only shows its mist; a Hidden character is not affected and nothing is cast while Hidden.
func test_no_element_and_hidden_do_nothing() -> void:
	var none := _world("")
	_cast(none)
	_stand(none, 620)
	_ticks(none, 120)
	assert_false(_slowed(none))
	assert_false(_poisoned(none))
	assert_eq(none.hazards.active_count(), 1, "the mist is still placed")
	var hidden := _world("I")
	hidden.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 100.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
	_ticks(hidden, 1900)
	assert_eq(hidden.hazards.cast_count, 0, "nothing is cast while the character is Hidden")
	var cast := _world("I")
	_cast(cast)
	cast.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 100.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
	_stand(cast, 620)
	_ticks(cast, 60)
	assert_false(_slowed(cast), "a mist already placed does not touch a Hidden character")


## A failed `prop` roll (stream 19) places nothing but still spends the interval.
func test_failed_roll_spends_the_interval() -> void:
	var w := _world("I", 500.0, 30.0, 10.0, 0.0)
	_ticks(w, 3700)
	assert_eq(w.hazards.cast_count, 0, "prop 0 never places a mist")
	var random := _world("I", 500.0, 10.0, 1.0, 50.0, 7)
	var status := random.mob_status_rng.state
	_ticks(random, 600 * 12)
	assert_ne(random.mob_status_rng.state, status, "stream 19 is drawn")
	var casts := random.hazards.cast_count
	assert_true(casts > 0 and casts < 12, "a 50%% roll fails sometimes and succeeds sometimes: %d of 12" % casts)


## Many casts reuse the same pool slots: its capacity never grows past the most that are alive at once.
func test_pool_does_not_grow_over_many_casts() -> void:
	var w := _world("I", 500.0, 1.0, 0.5)
	_ticks(w, 60 * 120)
	assert_true(w.hazards.cast_count >= 100, "about 119 casts: %d" % w.hazards.cast_count)
	assert_eq(w.hazards.capacity(), 4, "the initial capacity; never more than one live at a time")
	var pool := GroundHazards.new(2)
	for i in 1000:
		var slot := pool.spawn({"rect": Rect2(0, 0, 10, 10), "born": 0.0, "until": 1.0})
		assert_true(slot < 2)
		pool.clear()
	assert_eq(pool.capacity(), 2)
	assert_eq(pool.cast_count, 1000)
	var grown := GroundHazards.new(2)
	for i in 5:
		grown.spawn({"rect": Rect2(0, 0, 10, 10), "born": 0.0, "until": 1.0})
	assert_eq(grown.active_count(), 5, "all live ones are kept when more than the capacity are alive")
	assert_true(grown.capacity() >= 5)


## The same seed gives the same casts, positions and statuses tick for tick; another seed rolls differently.
func test_same_seed_same_outcome() -> void:
	var traces: Array = []
	for seed_value in [22, 22, 23]:
		var w := _world("S", 2.0, 10.0, 4.0, 60.0, seed_value)
		var trace := []
		for second in 120:
			_stand(w, 560 if second % 7 < 4 else 450)
			_ticks(w, 60)
			trace.append([w.hazards.active_count(), w.hazards.cast_count, int(w.player_state.get("poison", {}).get("remaining", -1.0) * 100.0)])
		traces.append(trace)
	assert_eq(traces[0], traces[1], "same seed, same outcome")
	assert_ne(traces[0], traces[2], "another seed differs (a 60% roll)")


## Hazards are removed with the map: the transfer, a death and the settled clear all empty the pool, keeping the counters.
func test_hazards_clear_on_map_transfer_and_on_death() -> void:
	var w := RunWorld.new(MAPS.setup(300.0))
	w.god = true
	w.hazards.spawn({"rect": Rect2(0, 0, 100, 100), "born": 0.0, "until": 1000.0, "effect": GroundHazards.ICE})
	w.hazards.spawn({"rect": Rect2(0, 0, 100, 100), "born": 0.0, "until": 1000.0})
	assert_eq(w.hazards.active_count(), 2)
	for tick in 60:
		w.step(DT, MoveInput.new())
	assert_eq(w.hazards.active_count(), 2, "they last across ticks")
	var slot := int(w.bosses.records[0].slot)
	if slot < 0:
		for tick in 60 * 300:
			w.step(DT, MoveInput.new())
		slot = int(w.bosses.records[0].slot)
	w.hit_mob(slot, {"damage_min": 1e9, "damage_max": 1e9, "magic": false, "crit": 0.0, "crit_mult": 1.5,
		"skill": "three_snails"}, -1)
	w.step(DT, MoveInput.new())
	assert_true(w.transfer_pending)
	assert_eq(w.hazards.active_count(), 0, "emptied when the map is cleared")
	assert_eq(w.hazards.cast_count, 2, "the counters stay")
	w.hazards.spawn({"rect": Rect2(0, 0, 100, 100), "born": 0.0, "until": 1000.0})
	w.advance_map()
	assert_eq(w.hazards.active_count(), 0, "and at the transfer itself")
	assert_eq(w.hazards.cast_count, 3)
	var dying := _world("I")
	dying.hazards.spawn({"rect": Rect2(0, 0, 100, 100), "born": 0.0, "until": 1000.0})
	dying.god = false
	dying.take_hit(1.0e7, false, "", dying.player.pos - Vector2(10, 0), {"accuracy": 10000.0})
	assert_eq(dying.state, RunWorld.DEAD)
	assert_eq(dying.hazards.active_count(), 0, "emptied on death")


## The stage clear (the settled last boss kill) empties the pool as well.
func test_hazards_clear_on_stage_clear() -> void:
	var w := _world("I")
	w.hazards.spawn({"rect": Rect2(0, 0, 100, 100), "born": 0.0, "until": 1000.0})
	w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1e9, "damage_max": 1e9, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)
	_ticks(w, 5)
	BotInput.auto_choose(w) # the final reward choice must be answered before the clear settles
	_ticks(w, 5)
	assert_eq(w.state, RunWorld.CLEARED, "the only boss's death clears the stage once the choices are answered")
	assert_eq(w.hazards.active_count(), 0, "emptied by the clear")
	assert_eq(w.hazards.cast_count, 1, "the counters stay")
