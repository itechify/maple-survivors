extends TestCase
## Shared run seams route the current combat formula and auto-casting through the public boundaries.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_shared_hit_uses_current_formula_whole_on_hp() -> void:
	var w := RF.quiet_world()
	w.god = false
	w.step(DT, MoveInput.new())
	var before: Dictionary = w.player_state.duplicate()
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = w.rng.state
	var expected := CombatMath.monster_damage(30.0, expected_rng.randf(), w.player_pdd)
	w.drain_events()
	w.take_hit(30.0, false, "", w.player.pos - Vector2(10, 0))
	assert_eq(int(w.player_state.hp), int(before.hp) - expected, "the whole hit comes off HP (no Magic Guard, #285)")
	var hit: Dictionary = w.drain_events()[0]
	assert_eq(hit.type, "player_hit")
	assert_eq(hit.damage, expected)
	assert_false(hit.has("mp_absorbed"))
	assert_eq(hit.dir, 1)
	assert_eq(w.rng.state, expected_rng.state, "exactly the old random roll is consumed")


func test_cast_tick_signal_and_cooldowns() -> void:
	var w := RF.quiet_world()
	assert_true(w.can_cast(), "standing is a valid cast state")
	w.step(DT, MoveInput.new())
	assert_false(w.runner.fired_this_tick, "no target")
	var p := w.player.pos + Vector2(70, 0)
	var fh := w.fhm.find_below(p.x, p.y - 1)
	w.spawn_mob(0, Vector2(p.x, w.fhm.y_at(fh, p.x)), fh, 100.0, false)
	w.step(DT, MoveInput.new())
	assert_true(w.runner.fired_this_tick, "a target triggers the current skill path")
	var cd := float(w.runner.cooldowns.three_snails)
	w.runner.tick_cooldowns(DT, w)
	assert_false(w.runner.fired_this_tick, "cooldown tick does not cast")
	assert_near(float(w.runner.cooldowns.three_snails), cd - DT, 1e-6)
	w.runner.cast_ready(DT, w)
	assert_false(w.runner.fired_this_tick, "separate cast phase still waits for the cooldown")
