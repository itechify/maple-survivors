extends TestCase
## The merge of spec #332 (burst skills) and spec #372 (second life): a lethal hit that the Resurrection reaction turns into a
## survived one leaves a running burst alone, while a lethal hit nothing claims ends it. Fixed ticks, no cache needed.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const RS := preload("res://tests/fixtures/resurrection_fixtures.gd")
const DT := 1.0 / 60.0


## A Bishop on the quiet stage with a ready Resurrection (when `second_life`) and a copy of Energy Bolt turned into a burst
## that is mid-stream: the wind-up has passed, shots are still to come.
func _world(second_life: bool) -> RunWorld:
	var w := RunWorld.new(RS.setup(332))
	RF.place_player(w, 200)
	w.loadout.order.clear()
	var d := w.book.def("energy_bolt").duplicate(true)
	d.cast = {"rule": "burst"}
	d.burst = {"interval": 0.1, "wind_up": 0.0, "retarget": true}
	d.count = 8
	d.cooldown = 6.0
	d.range = 450.0
	w.book.defs["stream"] = d
	w.data.jobs_survivor.jobs["232"].skill_pool.append("stream")
	w.learn_skill("stream")
	if second_life:
		w.learn_skill(RS.KEY)
	var m := RF.put_mob(w, 1110100, 400, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	for tick in 20:
		w.runner.step(DT, w)
	return w


func test_a_revived_character_keeps_the_burst_streaming() -> void:
	var w := _world(true)
	assert_true(w.runner.bursts.has_skill("stream"), "the stream is running")
	w.drain_events()
	RS.lethal_hit(w)
	var types := w.drain_events().map(func(e: Dictionary) -> String: return e.type)
	assert_true("player_revived" in types, "Resurrection claimed the hit")
	assert_false("player_died" in types)
	assert_false("burst_end" in types, "the revive did not cancel the stream")
	assert_true(w.runner.bursts.has_skill("stream"), "the burst is still running")


func test_a_death_nothing_claims_ends_the_burst() -> void:
	var w := _world(false)
	assert_true(w.runner.bursts.has_skill("stream"), "the stream is running")
	w.drain_events()
	RS.lethal_hit(w)
	var types := w.drain_events().map(func(e: Dictionary) -> String: return e.type)
	assert_true("player_died" in types)
	assert_eq(types.count("burst_end"), 1, "the stream art is told to stop once")
	assert_false(w.runner.bursts.has_skill("stream"), "no burst survives the death")
