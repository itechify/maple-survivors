extends TestCase
## Shared run seams preserve the existing hit and auto-cast behavior before the difficulty overhaul.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_shared_hit_uses_existing_formula_and_guard() -> void:
	var w := RF.quiet_world()
	w.god = false
	w.change_job(200)
	w.learn_skill("magic_guard")
	var before: Dictionary = w.player_state.duplicate()
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.state = w.rng.state
	var expected := CombatMath.touch_damage(30.0, expected_rng.randf(),
		w.director.value_at("damage", w.time), w.player_pdd)
	var split := CombatMath.magic_guard_split(expected, w.loadout.passive_total("mp_guard"), int(before.mp))
	w.drain_events()
	w.take_hit(30.0, false, "", w.player.pos - Vector2(10, 0))
	assert_eq(int(w.player_state.hp), int(before.hp) - split.x)
	assert_eq(int(w.player_state.mp), int(before.mp) - split.y)
	var hit: Dictionary = w.drain_events()[0]
	assert_eq(hit.type, "player_hit")
	assert_eq(hit.damage, expected)
	assert_eq(hit.mp_absorbed, split.y)
	assert_eq(hit.dir, 1)
	assert_eq(w.rng.state, expected_rng.state, "exactly the old random roll is consumed")


func test_cast_tick_signal_and_cooldowns() -> void:
	var w := RF.quiet_world()
	assert_true(w.can_cast(), "the prefactor keeps climbing casts allowed until ticket #8")
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
