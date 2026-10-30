extends TestCase
## Boss Poison (MobSkill 125, #459): a non-lethal damage over time on the status seam, through seeded synthetic RunWorld ticks
## (independent of the asset cache).
const MF := preload("res://tests/fixtures/mano_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


## A world whose boss casts only a synthetic Poison level shaped like Thanatos 125/1 (interval 10, prop 50 by default, box
## (-150,-90)-(0,0), x 15): `time`, `x` and `prop` can be varied. The player stands 100 px in front of the boss.
func _world(prop := 100.0, x := 3.0, time := 5.0, seed_value := 22, rules := {}) -> RunWorld:
	var setup := MF.setup([126], seed_value)
	setup.mob_imgs[2220000].info.skill = {"0": {"skill": 125.0, "level": 1.0, "action": 1.0}}
	setup.mob_skill_img = {"125": {"level": {"1": {"interval": 10.0, "time": time, "prop": prop, "x": x,
		"lt": {"$v": [-150.0, -90.0]}, "rb": {"$v": [0.0, 0.0]}, "affected": {"repeat": 1.0}}}}}
	setup.mob_imgs[2220000].skill1 = {"0": {"delay": 10.0}}
	setup.data.balance.mob_skills.merge(rules, true)
	setup.data.balance.regen = {"interval": 100000.0, "hp": 0.0} # HP changes only by poison
	var w := RunWorld.new(setup)
	w.god = true
	RF.place_player(w, 500)
	w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot, Vector2(600, 200), w.fhm.find_below(600, 190))
	w.drain_events()
	return w


func _ticks(w: RunWorld, n: int) -> void:
	for tick in n:
		w.step(DT, MoveInput.new())


func _poisoned(w: RunWorld) -> bool:
	return not w.player_state.get("poison", {}).is_empty()


func _poison_hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit" and e.source_kind == "poison")


## Casts at the interval, then loses exactly x HP at each whole second for `time` (the last tick on the expiry tick), and
## the status ends after exactly `time` seconds.
func test_whole_second_ticks_for_the_canonical_time() -> void:
	var w := _world()
	w.god = false
	w.grant_second_life(40.0)
	_ticks(w, 599)
	assert_false(_poisoned(w), "no poison before the 10 s interval")
	_ticks(w, 1)
	assert_true(_poisoned(w), "poisoned at 10 s")
	assert_eq(int(w.player_state.hp), 40, "nothing is lost at the cast")
	w.drain_events()
	_ticks(w, 59)
	assert_eq(int(w.player_state.hp), 40, "nothing before the first whole second")
	_ticks(w, 1)
	assert_eq(int(w.player_state.hp), 37, "x HP at one second")
	_ticks(w, 60)
	assert_eq(int(w.player_state.hp), 34, "and again at two")
	_ticks(w, 179)
	assert_true(_poisoned(w), "still poisoned one tick before the end")
	assert_eq(int(w.player_state.hp), 28, "four ticks in")
	_ticks(w, 1)
	assert_false(_poisoned(w), "the status ends after exactly time")
	assert_eq(int(w.player_state.hp), 25, "the last tick lands on the expiry tick: time x HP in all")
	var hits := _poison_hits(w.drain_events())
	assert_eq(hits.size(), 5, "one hit per second")
	_ticks(w, 120)
	assert_eq(int(w.player_state.hp), 25, "no ticks after the end")


## Poison never kills: it leaves 1 HP, reports only what was lost, and then stops emitting.
func test_never_lethal_and_reports_what_was_lost() -> void:
	var w := _world(100.0, 100.0, 4.0)
	w.god = false
	w.grant_second_life(30.0)
	_ticks(w, 600 + 60 * 4)
	assert_eq(w.state, RunWorld.PLAYING, "alive")
	assert_eq(int(w.player_state.hp), 1, "1 HP left")
	var hits := _poison_hits(w.drain_events())
	assert_eq(hits.size(), 1, "only the tick that took HP is reported; later ones lost nothing")
	assert_eq(int(hits[0].damage), 29)
	var again := _world(100.0, 5.0, 3.0)
	again.god = false
	again.grant_second_life(1.0)
	_ticks(again, 600 + 180)
	assert_eq(int(again.player_state.hp), 1)
	assert_true(_poison_hits(again.drain_events()).is_empty(), "at 1 HP no hit is emitted")


## A tick is a `player_hit` with source_kind "poison" from the boss (so the boss-hit telemetry sees it), with no hit
## window and no knockback; it does not start the hit invincibility either.
func test_hit_event_carries_source_kind_and_does_not_knock_back_or_open_a_window() -> void:
	var w := _world()
	w.god = false
	w.grant_second_life(40.0)
	_ticks(w, 600)
	w.drain_events()
	var pos := w.player.pos
	_ticks(w, 60)
	var hits := _poison_hits(w.drain_events())
	assert_eq(hits.size(), 1)
	var hit: Dictionary = hits[0]
	assert_eq(int(hit.damage), 3)
	assert_false(bool(hit.miss))
	assert_true(bool(hit.boss), "counted as a boss hit")
	assert_eq(int(hit.mob_id), 2220000)
	assert_eq(int(hit.max_hp), int(w.player_state.max_hp))
	assert_eq(w.player.pos.x, pos.x, "no knockback")
	assert_near(w.upkeep.invincible_t, 0.0, 1e-9, "no hit window")
	var normal := w.take_hit(5.0, false, "", w.player.pos - Vector2(10, 0), {"accuracy": 10000.0, "source_kind": "touch"})
	assert_true(normal > 0, "an ordinary hit still lands right after a poison tick")


## A tick ignores defence and avoid but not god mode: god takes nothing (the status still shows).
func test_god_mode_takes_no_poison_damage() -> void:
	var w := _world()
	_ticks(w, 600 + 120)
	assert_true(_poisoned(w))
	assert_true(_poison_hits(w.drain_events()).is_empty())


## Outside the mirrored box, with a failed roll or while Hidden nothing is applied; a failed roll still spends the interval.
func test_area_roll_hidden_and_interval() -> void:
	for place in [Vector2(-170, 0), Vector2(170, 0), Vector2(-100, -150), Vector2(-100, 60)]:
		var w := _world()
		_ticks(w, 599)
		w.player.place(Vector2(600, 200) + place, w.fhm)
		_ticks(w, 1)
		assert_false(_poisoned(w), "outside the box: %s" % place)
	var inside := _world()
	_ticks(inside, 600)
	assert_true(_poisoned(inside), "control: inside the box")
	var zero := _world(0.0)
	_ticks(zero, 1200)
	assert_false(_poisoned(zero), "zero chance fails")
	var hidden := _world()
	hidden.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 40.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}})
	_ticks(hidden, 1200)
	assert_false(_poisoned(hidden), "Hidden skips Poison")
	var mirrored := _world()
	_ticks(mirrored, 599)
	mirrored.player.place(Vector2(680, 200), mirrored.fhm)
	_ticks(mirrored, 1)
	assert_eq(int(mirrored.swarm.facing[int(mirrored.bosses.records[0].slot)]), 1, "the boss faces right")
	assert_true(_poisoned(mirrored), "the strip mirrors with the facing")


## The shared lockout floor: an 8 s poison cast at 10 s ends at 18 s and is immune to a new cast until 26 s, so the 20 s
## cast does nothing and the 30 s cast poisons again; a recast cannot refresh a status that is still on.
func test_lockout_floor_after_the_status_ends() -> void:
	var w := _world(100.0, 3.0, 8.0)
	_ticks(w, 600)
	assert_true(_poisoned(w), "first cast at 10 s")
	_ticks(w, 480)
	assert_false(_poisoned(w), "ended at 18 s")
	_ticks(w, 120)
	assert_false(_poisoned(w), "the cast at 20 s falls inside the immunity")
	_ticks(w, 360)
	assert_false(_poisoned(w), "26 s: immunity over, but the next cast is at 30 s")
	_ticks(w, 240)
	assert_true(_poisoned(w), "the cast at 30 s takes effect")
	var remaining := float(w.player_state.poison.remaining)
	assert_between(remaining, 7.9, 8.0, "a fresh full duration")


## The prop roll is on stream 19 and repeats for a seed: a 50% poison casts and fails across seeds the same way twice, and
## no other stream moves.
func test_chance_uses_stream_19_and_repeats_for_a_seed() -> void:
	var outcomes: Array = []
	for run in 2:
		var w := _world(50.0, 3.0, 1.0)
		var combat := w.rng.state
		var ground := w.ground_rng.state
		var status := w.mob_status_rng.state
		var cast: Array = []
		for second in 20:
			_ticks(w, 600)
			cast.append(_poisoned(w) or w.player_state.get("poison", {}).has("x"))
			cast.append(w.mob_status_rng.state != status)
		outcomes.append(cast)
		assert_eq(w.rng.state, combat, "stream 1 untouched")
		assert_eq(w.ground_rng.state, ground, "stream 18 untouched")
		assert_ne(w.mob_status_rng.state, status, "stream 19 drawn")
	assert_eq(outcomes[0], outcomes[1], "same seed, same outcome")
