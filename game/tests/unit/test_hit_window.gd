extends TestCase
## Spec #88 hit-window pressure through RunWorld.take_hit and the mob ball system: the shrinking window for contact
## damage and ordinary mob attacks, boss skill attacks that ignore it, and balls that fly on while it blocks them.
## Seeded RNG, fixed dt, accuracy-0 sources so no hit can be rolled a miss.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BF := preload("res://tests/fixtures/boss_attack_fixtures.gd")
const DT := 1.0 / 60.0

const TOUCH := {"boss": false, "source_kind": "touch", "accuracy": 0.0, "mob": -1}
const MOB_ATTACK := {"boss": false, "source_kind": "mob_attack", "accuracy": 0.0, "mob": -1}
const BOSS_TOUCH := {"boss": true, "source_kind": "touch", "accuracy": 0.0, "mob": -1}
const BOSS_ATTACK := {"boss": true, "source_kind": "attack", "accuracy": 0.0, "mob": -1}
const BOSS_BALL := {"boss": true, "source_kind": "projectile", "accuracy": 0.0, "mob": -1}


func _hit(w: RunWorld, source: Dictionary) -> int:
	return w.take_hit(1.0, false, "", w.player.pos - Vector2(10, 0), source)


func _idle(w: RunWorld, seconds: float) -> void:
	for tick in roundi(seconds / DT):
		w.step(DT, MoveInput.new())


func _wait_out_window(w: RunWorld) -> void:
	for tick in 600:
		if w.upkeep.invincible_t <= 0.0:
			return
		w.step(DT, MoveInput.new())
	fail("the window never ended")


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit")


func test_consecutive_contact_hits_give_shrinking_windows() -> void:
	var w := RF.quiet_world(400.0, 880)
	var windows: Array = []
	for i in 5:
		assert_true(_hit(w, TOUCH) > 0, "hit %d lands" % i)
		windows.append(w.upkeep.invincible_t)
		_wait_out_window(w)
	assert_eq(windows, [1.5, 1.0, 0.6, 0.4, 0.4], "1.5 -> 1.0 -> 0.6 -> 0.4, then held at the lowest")


func test_ordinary_mob_attacks_share_the_chain_with_contact() -> void:
	var w := RF.quiet_world(400.0, 881)
	var windows: Array = []
	for source: Dictionary in [TOUCH, MOB_ATTACK, TOUCH, MOB_ATTACK]:
		assert_true(_hit(w, source) > 0)
		windows.append(w.upkeep.invincible_t)
		_wait_out_window(w)
	assert_eq(windows, [1.5, 1.0, 0.6, 0.4])


func test_a_gap_past_the_reset_restores_the_full_window() -> void:
	var w := RF.quiet_world(400.0, 882)
	for i in 3:
		_hit(w, TOUCH)
		_wait_out_window(w)
	_idle(w, 3.1)
	assert_true(_hit(w, TOUCH) > 0)
	assert_eq(w.upkeep.invincible_t, 1.5, "3 s without a landed hit resets the chain")


func test_a_gap_between_chain_gap_and_reset_holds_the_step() -> void:
	var w := RF.quiet_world(400.0, 883)
	_hit(w, TOUCH)
	_wait_out_window(w)
	_hit(w, TOUCH)
	assert_eq(w.upkeep.invincible_t, 1.0)
	_idle(w, 2.7) # past chain_gap 2.5, short of reset_after 3.0 (the window itself is 1.0 of this)
	_hit(w, TOUCH)
	assert_eq(w.upkeep.invincible_t, 1.0, "neither lengthened nor shortened")
	_idle(w, 2.4) # within chain_gap: the chain goes on
	_hit(w, TOUCH)
	assert_eq(w.upkeep.invincible_t, 0.6)


func test_a_miss_gives_no_window_and_leaves_the_chain_alone() -> void:
	var data := RF.quiet_data()
	data.balance.player.stats.dex = 4000 # Avoids anything with a non-zero accuracy.
	var w := RunWorld.new(RF.setup("quiet", 884, data))
	RF.place_player(w, 400)
	w.drain_events()
	var miss := {"boss": false, "source_kind": "touch", "accuracy": 42.0, "mob": -1}
	assert_eq(_hit(w, miss), 0)
	assert_eq(w.upkeep.invincible_t, 0.0, "no window after a miss")
	assert_true(_hit(w, TOUCH) > 0)
	assert_eq(w.upkeep.invincible_t, 1.5, "the miss was not a step")
	_wait_out_window(w)
	_idle(w, 0.9) # 2.4 s after the landed hit
	assert_eq(_hit(w, miss), 0)
	_idle(w, 1.0) # 3.4 s after the landed hit; a miss that refreshed the clock would make this 1.0
	assert_true(_hit(w, TOUCH) > 0)
	assert_eq(w.upkeep.invincible_t, 1.5, "the miss did not refresh the time since the last landed hit")


func test_a_boss_attack_lands_inside_the_window_and_starts_a_full_one() -> void:
	var w := RF.quiet_world(400.0, 885)
	_hit(w, TOUCH)
	_wait_out_window(w)
	_hit(w, TOUCH)
	assert_eq(w.upkeep.invincible_t, 1.0)
	_idle(w, 0.3)
	var hp := int(w.player_state.hp)
	assert_eq(_hit(w, MOB_ATTACK), 0, "an ordinary attack is still blocked")
	assert_true(_hit(w, BOSS_ATTACK) > 0, "the boss attack ignores the window")
	assert_true(int(w.player_state.hp) < hp)
	assert_eq(w.upkeep.invincible_t, 1.5, "and starts the normal full window")


func test_a_boss_attack_does_not_advance_the_chain_but_counts_as_a_landed_hit() -> void:
	var w := RF.quiet_world(400.0, 886)
	_hit(w, TOUCH)
	_wait_out_window(w)
	_hit(w, TOUCH) # step 1
	_hit(w, BOSS_ATTACK)
	_wait_out_window(w)
	_hit(w, TOUCH)
	assert_eq(w.upkeep.invincible_t, 0.6, "step 2, not 3: the boss hit was not a step")
	# The boss hit still refreshes the last-hit time for the reset.
	var v := RF.quiet_world(400.0, 887)
	_hit(v, TOUCH)
	_wait_out_window(v)
	_hit(v, TOUCH) # step 1, at about 1.5 s
	_wait_out_window(v)
	_idle(v, 0.4)
	_hit(v, BOSS_ATTACK) # at about 2.9 s
	_wait_out_window(v)
	_idle(v, 0.3)
	_hit(v, TOUCH) # 3.2 s after the last contact hit (a reset on its own) but 1.8 s after the boss hit
	assert_eq(v.upkeep.invincible_t, 0.6, "the boss hit refreshed the clock, so the chain went on to step 2")


func test_a_boss_attack_after_a_reset_starts_the_chain_over() -> void:
	var w := RF.quiet_world(400.0, 888)
	assert_true(_hit(w, BOSS_ATTACK) > 0)
	assert_eq(w.upkeep.invincible_t, 1.5)
	_wait_out_window(w)
	_hit(w, TOUCH)
	assert_eq(w.upkeep.invincible_t, 1.0, "the boss hit was a landed hit 1.5 s ago, so this one chains from step 0")


func test_a_boss_attack_cannot_revive_a_lapsed_chain() -> void:
	var w := RF.quiet_world(400.0, 891)
	for i in 4:
		_hit(w, TOUCH)
		_wait_out_window(w)
	_idle(w, 3.1)
	_hit(w, BOSS_ATTACK)
	_wait_out_window(w)
	_hit(w, TOUCH)
	assert_eq(w.upkeep.invincible_t, 1.0, "the chain had lapsed before the boss hit: this is the second step, not the fifth")


func test_boss_body_touch_and_other_ordinary_sources_respect_the_window() -> void:
	var w := RF.quiet_world(400.0, 889)
	_hit(w, TOUCH)
	var hp := int(w.player_state.hp)
	assert_eq(_hit(w, BOSS_TOUCH), 0, "a boss's body is contact damage like any other mob")
	assert_eq(_hit(w, TOUCH), 0)
	assert_eq(_hit(w, {"boss": true, "accuracy": 0.0}), 0, "boss flag alone (no skill-attack kind) does not bypass")
	assert_eq(_hit(w, {"boss": false, "source_kind": "attack", "accuracy": 0.0}), 0, "only a boss's attack bypasses")
	assert_eq(int(w.player_state.hp), hp)


func test_god_and_death_still_block_boss_attacks() -> void:
	var w := RF.quiet_world(400.0, 890)
	w.god = true
	assert_eq(_hit(w, BOSS_ATTACK), 0)
	assert_eq(w.upkeep.invincible_t, 0.0)
	w.god = false
	w.drain_events()
	assert_true(w.take_hit(1.0e9, false, "", w.player.pos - Vector2(10, 0), BOSS_ATTACK) > 0, "a lethal boss attack")
	assert_eq(w.state, RunWorld.DEAD)
	w.drain_events()
	assert_eq(_hit(w, BOSS_ATTACK), 0, "the dead take no more hits")
	assert_true(_hits(w.drain_events()).is_empty())
