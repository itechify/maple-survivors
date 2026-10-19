extends TestCase
## Issue #223 knockback guard through RunWorld.take_hit and PlayerUpkeep: a hit that knocks the player back starts a guard
## of the first hit-window length (balance.hit_window.lengths[0]); hits that land inside it still do damage but do not
## knock back or restart it. Boss skill attacks/balls (window bypass) still knock back and restart it. Seeded RNG, fixed
## dt, accuracy-0 sources so no hit can be rolled a miss.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

const TOUCH := {"boss": false, "source_kind": "touch", "accuracy": 0.0, "mob": -1}
const BOSS_ATTACK := {"boss": true, "source_kind": "attack", "accuracy": 0.0, "mob": -1}


## One hit from the left; the result is the damage and whether it knocked the player back (input lock set).
func _hit(w: RunWorld, source: Dictionary = TOUCH) -> Dictionary:
	w.player.knock_t = 0.0
	w.player.alert_t = 0.0
	var dmg := w.take_hit(1.0, false, "", w.player.pos - Vector2(10, 0), source)
	return {"damage": dmg, "knocked": w.player.knock_t > 0.0 or w.player.alert_t > 0.0}


func _idle(w: RunWorld, seconds: float) -> void:
	for tick in roundi(seconds / DT):
		w.step(DT, MoveInput.new())


func _wait_out_window(w: RunWorld) -> void:
	for tick in 600:
		if w.upkeep.invincible_t <= 0.0:
			return
		w.step(DT, MoveInput.new())
	fail("the window never ended")


func test_the_guard_comes_from_the_first_window_length() -> void:
	var data := RF.quiet_data()
	data.balance["hit_window"] = {"lengths": [2.0, 0.5], "chain_gap": 2.5, "reset_after": 3.0}
	var w := RunWorld.new(RF.setup("quiet", 2231, data))
	RF.place_player(w, 400)
	assert_true(_hit(w).knocked)
	assert_eq(w.upkeep.knockback_guard_t, 2.0, "read from the data, not a new constant")


func test_a_windowed_hit_inside_the_guard_does_damage_without_knockback() -> void:
	var w := RF.quiet_world(400.0, 2232)
	var first := _hit(w)
	assert_true(first.damage > 0 and first.knocked, "the first hit knocks back")
	_wait_out_window(w) # 1.5 s: the window and the guard end together
	var second := _hit(w) # step 1: window 1.0, guard 1.5 s from this knockback
	assert_true(second.damage > 0 and second.knocked, "past the guard the next hit knocks back")
	assert_eq(w.upkeep.invincible_t, 1.0)
	_wait_out_window(w) # 1.0 s later: window over, guard has 0.5 s left
	var hp := int(w.player_state.hp)
	var third := _hit(w)
	assert_true(third.damage > 0, "damage lands normally")
	assert_true(int(w.player_state.hp) < hp)
	assert_false(third.knocked, "no shove, input lock or alert stance inside the guard")
	assert_eq(w.upkeep.invincible_t, 0.6, "the damage window chain still steps")


func test_a_hit_past_the_guard_knocks_back_again() -> void:
	var w := RF.quiet_world(400.0, 2233)
	_hit(w)
	_wait_out_window(w)
	assert_true(_hit(w).knocked)
	_wait_out_window(w)
	assert_false(_hit(w).knocked, "1.0 s after the last knockback")
	_wait_out_window(w) # 0.6 s later: 1.6 s after the last knockback
	assert_true(_hit(w).knocked, "1.6 s after the last knockback")


func test_the_guard_does_not_restart_on_a_guarded_hit() -> void:
	var w := RF.quiet_world(400.0, 2234)
	_hit(w)
	_wait_out_window(w)
	_hit(w) # knockback at t = 1.5, guard until 3.0
	_wait_out_window(w)
	_hit(w) # t = 2.5, guarded, window 0.6
	assert_between(w.upkeep.knockback_guard_t, 0.4, 0.51, "counted from the knockback, not from this hit")
	_wait_out_window(w) # t = 3.1
	assert_true(_hit(w).knocked, "0.6 s after the guarded hit but 1.6 s after the last knockback")


func test_continuous_contact_knocks_back_at_most_every_guard_length() -> void:
	var w := RF.quiet_world(400.0, 2235)
	var knock_times: Array[float] = []
	var hits := 0
	var t := 0.0
	for tick in roundi(6.0 / DT):
		w.step(DT, MoveInput.new())
		t += DT
		if w.upkeep.invincible_t > 0.0:
			continue
		var r := _hit(w)
		assert_true(r.damage > 0)
		hits += 1
		if r.knocked:
			knock_times.append(t)
	assert_true(hits > knock_times.size(), "damage lands between the knockbacks")
	assert_true(knock_times.size() >= 3, "and the player is still pushed")
	for i in range(1, knock_times.size()):
		assert_true(knock_times[i] - knock_times[i - 1] >= 1.5 - 1e-6,
			"knockbacks %d and %d are %.3f s apart" % [i - 1, i, knock_times[i] - knock_times[i - 1]])


func test_a_boss_attack_inside_the_guard_knocks_back_and_restarts_it() -> void:
	var w := RF.quiet_world(400.0, 2236)
	_hit(w)
	_wait_out_window(w)
	_hit(w)
	_wait_out_window(w)
	_idle(w, 0.1) # guard has 0.4 s left
	assert_between(w.upkeep.knockback_guard_t, 0.3, 0.45)
	var boss := _hit(w, BOSS_ATTACK)
	assert_true(boss.damage > 0 and boss.knocked, "the bypassing hit still knocks back")
	assert_eq(w.upkeep.knockback_guard_t, 1.5, "and restarts the guard")


func test_a_boss_attack_during_the_window_also_knocks_back() -> void:
	var w := RF.quiet_world(400.0, 2237)
	_hit(w)
	_idle(w, 0.3)
	assert_true(_hit(w, BOSS_ATTACK).knocked)
	assert_eq(w.upkeep.knockback_guard_t, 1.5)


func test_a_miss_inside_the_guard_changes_nothing() -> void:
	var data := RF.quiet_data()
	data.balance.player.stats.dex = 4000
	var w := RunWorld.new(RF.setup("quiet", 2238, data))
	RF.place_player(w, 400)
	assert_true(_hit(w).knocked)
	_wait_out_window(w)
	_hit(w) # a second knockback, guard full again
	_wait_out_window(w)
	var guard: float = w.upkeep.knockback_guard_t
	var miss := {"boss": false, "source_kind": "touch", "accuracy": 42.0, "mob": -1}
	var r := _hit(w, miss)
	assert_eq(r.damage, 0)
	assert_false(r.knocked)
	assert_eq(w.upkeep.knockback_guard_t, guard)


func test_the_guard_ticks_down_and_is_per_round() -> void:
	var w := RF.quiet_world(400.0, 2239)
	assert_eq(w.upkeep.knockback_guard_t, 0.0, "a new round starts unguarded")
	assert_true(w.upkeep.may_knock_back())
	_hit(w)
	assert_false(w.upkeep.may_knock_back())
	_idle(w, 1.6)
	assert_eq(w.upkeep.knockback_guard_t, 0.0)
	assert_true(w.upkeep.may_knock_back())
