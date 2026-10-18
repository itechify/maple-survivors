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


## Spawns a ball `gap` px left of the player's grown body box (radius 8) flying right at `speed` px/s.
func _ball(w: RunWorld, boss: bool, gap: float, speed: float, flight := 500.0) -> int:
	var start := Vector2(w.player.pos.x - 14.0 - 8.0 - gap, w.player.pos.y - 30.0)
	return w.mob_projectiles.spawn({"pos": start, "velocity": Vector2(speed, 0), "visual": 0, "range": flight,
		"mob": 1, "mob_id": 8130100, "damage": 1.0, "multiplier": 1.0, "accuracy": 0.0, "magic": false,
		"element": "", "hit": "", "source_pos": start, "radius": 8.0, "ordinary": not boss, "elite": false})


func _events_of(w: RunWorld, type: String) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == type)


func test_a_boss_ball_hits_through_the_window_and_is_used_up() -> void:
	var w := RF.quiet_world(400.0, 892)
	w.upkeep.invincible_t = 1.0 # a contact window in progress
	w.drain_events()
	_ball(w, true, 6.0, 300.0)
	var events: Array = []
	for tick in 10:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
	assert_eq(hits.size(), 1, "the boss ball lands during the contact window")
	if hits.size() == 1:
		assert_eq(hits[0].source_kind, "projectile")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_projectile_hit").size(), 1)
	assert_eq(w.mob_projectiles.active_count(), 0, "and is used up")
	assert_between(w.upkeep.invincible_t, 1.3, 1.5, "starting the full window (a few ticks have run since the hit)")


func test_an_ordinary_ball_flies_on_through_the_window_without_a_hit_or_event() -> void:
	var w := RF.quiet_world(400.0, 893)
	w.upkeep.invincible_t = 1.0
	w.drain_events()
	var hp := int(w.player_state.hp)
	_ball(w, false, 6.0, 300.0)
	for tick in 30: # the ball is inside the box from tick 2 and stays there at 300 px/s over 44 px
		w.step(DT, MoveInput.new())
	var events := w.drain_events()
	assert_true(events.filter(func(e: Dictionary) -> bool: return e.type in ["player_hit", "mob_projectile_hit"]).is_empty(),
		"no hit, no hit art")
	assert_eq(int(w.player_state.hp), hp)
	assert_eq(w.mob_projectiles.active_count(), 1, "not used up")


func test_a_ball_through_the_whole_body_in_one_tick_during_the_window_is_not_used_up() -> void:
	var w := RF.quiet_world(400.0, 894)
	w.upkeep.invincible_t = 1.0
	w.drain_events()
	_ball(w, false, 20.0, 6000.0, 150.0) # 100 px per tick: crosses the 44 px box inside one step
	w.step(DT, MoveInput.new())
	assert_eq(w.mob_projectiles.active_count(), 1, "it flew over the player")
	w.step(DT, MoveInput.new())
	w.step(DT, MoveInput.new())
	assert_eq(w.mob_projectiles.active_count(), 0, "and ended at its range")
	assert_true(_events_of(w, "player_hit").is_empty())


func test_an_ordinary_ball_inside_the_body_when_the_window_ends_hits_then() -> void:
	# Pins decision 5: segment_enter from a start inside the box enters at t = 0, so the ball lands on the first
	# step after the window ends; it is not lost by having entered earlier.
	var w := RF.quiet_world(400.0, 895)
	w.upkeep.invincible_t = 0.5
	w.drain_events()
	_ball(w, false, 3.0, 60.0) # 1 px per tick: still inside the 44 px box after the window
	var events: Array = []
	for tick in 20:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	assert_true(events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit").is_empty(), "blocked at first")
	assert_eq(w.mob_projectiles.active_count(), 1)
	for tick in 20:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
	assert_eq(hits.size(), 1, "the window ended and the ball in the box hit")
	if hits.size() == 1:
		assert_eq(hits[0].source_kind, "mob_attack")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_projectile_hit").size(), 1)
	assert_eq(w.mob_projectiles.active_count(), 0)


func test_a_rolled_miss_still_uses_the_ball_up() -> void:
	var data := RF.quiet_data()
	data.balance.player.stats.dex = 4000
	var w := RunWorld.new(RF.setup("quiet", 896, data))
	RF.place_player(w, 400)
	w.drain_events()
	var ball := _ball(w, false, 6.0, 300.0)
	w.mob_projectiles.accuracy[ball] = 42.0
	var events: Array = []
	for tick in 10:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	var hits := events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
	assert_eq(hits.size(), 1)
	if hits.size() == 1:
		assert_true(hits[0].miss)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_projectile_hit").size(), 1)
	assert_eq(w.mob_projectiles.active_count(), 0, "a MISS consumes the ball as before")
	assert_eq(w.upkeep.invincible_t, 0.0, "and gives no window")


func test_a_scheduled_boss_slam_lands_during_a_running_window() -> void:
	var setup := BF.setup()
	setup.data.balance.player.hp = 1.0e6
	var w := RunWorld.new(setup)
	var landed := false
	for tick in 400:
		w.step(DT, MoveInput.new())
		w.upkeep.invincible_t = maxf(w.upkeep.invincible_t, 5.0) # swarm contact keeps the window up (and blocks the boss's body touch)
		for e: Dictionary in w.drain_events():
			if e.type == "player_hit" and e.source_kind == "attack":
				landed = true
		if landed:
			break
	assert_true(landed, "the real BossAttacks slam reaches take_hit and bypasses the window")


func test_one_boss_attack_hits_the_player_only_once() -> void:
	var setup := BF.setup()
	setup.data.balance.player.hp = 1.0e6
	var w := RunWorld.new(setup)
	var impacted := false
	var slam_hits := 0
	var after_impact_ticks := 0
	for tick in 400:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "boss_attack" and e.phase == "impact":
				impacted = true
			elif e.type == "player_hit" and e.source_kind == "attack":
				slam_hits += 1
		if impacted:
			after_impact_ticks += 1
			if after_impact_ticks >= 40:
				break # well inside the attack interval: no second attack can have started
	assert_true(impacted, "the slam impacted")
	assert_eq(slam_hits, 1, "one attack instance, one hit, although the player stays in the area under a boss window")
