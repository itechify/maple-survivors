extends TestCase
## The playtest motor layer (spec #91 ticket #97, motor_noise.gd): a personality's reaction delay and seeded mistake
## bursts on top of the tactic controller's input, and its potion thresholds. Zero noise passes the input through
## exactly; a fixed seed reproduces the same noise.
const MOTOR := preload("res://tools/playtest/motor_noise.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")

const QUIET := {"reaction_delay_ticks": 0, "mistake_rate": 0.0, "potion_hp_fraction": null, "potion_mp_fraction": null}


## A scripted controller: right for 30 ticks, a jump press, left for 30 ticks, nothing for 20, up for 20 (repeated).
func _script(n: int) -> Array:
	var out: Array = []
	for i in n:
		var k := i % 101
		var mi := MoveInput.new()
		if k < 30:
			mi.right = true
		elif k == 30:
			mi.right = true
			mi.jump_pressed = true
			mi.jump_held = true
		elif k < 61:
			mi.left = true
		elif k >= 81:
			mi.up = true
		out.append(mi)
	return out


func _keys(mi: MoveInput) -> String:
	return "%d%d%d%d%d%d%d%d" % [int(mi.left), int(mi.right), int(mi.up), int(mi.down), int(mi.jump_pressed),
		int(mi.jump_held), int(mi.drink_hp), int(mi.drink_mp)]


func _run(params: Dictionary, seed_value: int, inputs: Array) -> Array:
	var m := MOTOR.new(seed_value, params)
	return inputs.map(func(mi: MoveInput) -> String: return _keys(m.apply(null, mi)))


func test_zero_noise_passes_every_input_through_exactly() -> void:
	var inputs := _script(600)
	var want: Array = inputs.map(func(mi: MoveInput) -> String: return _keys(mi))
	assert_eq(_run(QUIET, 2026, inputs), want)
	var m := MOTOR.new(2026, QUIET)
	var mi := MoveInput.new()
	assert_true(m.apply(null, mi) == mi, "zero noise returns the controller's own MoveInput")
	assert_eq(m.summary().delayed_ticks, 0)
	assert_eq(m.summary().bursts, 0)


func test_reaction_delay_repeats_the_previous_input_for_n_ticks_after_a_change() -> void:
	var p := QUIET.duplicate()
	p.reaction_delay_ticks = 5
	var out := _run(p, 1, _script(101))
	var right := "01000000"
	var left := "10000000"
	assert_eq(out[0], right, "the first input has nothing to lag behind")
	assert_eq(out[29], right)
	# tick 30 adds a jump press: a change, so ticks 30..34 repeat "right", and the press is kept for tick 35
	for i in range(30, 35):
		assert_eq(out[i], right, "tick %d is stale" % i)
	# tick 31 already wanted left; at tick 35 the latest wanted input (left) arrives with the latched jump press
	assert_eq(out[35], "10001000", "the delayed input arrives with the jump press latched")
	assert_eq(out[36], left)
	# tick 61 lets go: "left" repeats for 5 more ticks
	for i in range(61, 66):
		assert_eq(out[i], left, "tick %d is stale" % i)
	assert_eq(out[66], "00000000")
	assert_eq(out[86], "00100000", "up arrives 5 ticks after tick 81")
	assert_eq(out[85], "00000000")


func test_potion_presses_are_never_delayed() -> void:
	var p := QUIET.duplicate()
	p.reaction_delay_ticks = 10
	var m := MOTOR.new(1, p)
	m.apply(null, MoveInput.make(false, true))
	var mi := MoveInput.make(true)
	mi.drink_hp = true
	var out := m.apply(null, mi)
	assert_true(out.right and not out.left, "movement is stale")
	assert_true(out.drink_hp, "the drink goes through at once")


func test_mistake_bursts_are_reproducible_for_a_fixed_seed() -> void:
	var p := QUIET.duplicate()
	p.mistake_rate = 1.0
	var inputs := _script(3600)
	var a := _run(p, 2026, inputs)
	assert_eq(_run(p, 2026, inputs), a, "same seed, same noise")
	assert_true(_run(p, 7, inputs) != a, "another seed, other noise")
	var m := MOTOR.new(2026, p)
	var wrong := 0
	var frozen := 0
	for i in inputs.size():
		var want: MoveInput = inputs[i]
		var got := m.apply(null, want)
		if want.dir() != 0 and got.dir() == -want.dir():
			wrong += 1
		if (want.dir() != 0 or want.up) and got.dir() == 0 and not got.up:
			frozen += 1
	var s: Dictionary = m.summary()
	assert_true(int(s.bursts) >= 30 and int(s.bursts) <= 100, "about one burst per second over 60 s: %d" % s.bursts)
	assert_true(wrong > 0, "some ticks walk the wrong way")
	assert_true(frozen > 0, "some ticks press nothing")
	assert_eq(int(s.wrong_direction) + int(s.no_input), int(s.bursts))


func test_potion_thresholds_replace_the_controllers_timing() -> void:
	var w := RunWorld.new(RF.setup("quiet", 3, RF.quiet_data()))
	w.potions.stock.hp.count = 5
	var max_hp := int(w.player_state.max_hp)
	var p := QUIET.duplicate()
	p.potion_hp_fraction = 0.3
	var m := MOTOR.new(1, p)
	var bot_wants := MoveInput.new()
	bot_wants.drink_hp = true
	w.player_state.hp = int(max_hp * 0.5)
	assert_false(m.apply(w, bot_wants).drink_hp, "above 30% a late drinker does not drink, whatever the bot wants")
	w.player_state.hp = int(max_hp * 0.2)
	assert_true(m.apply(w, MoveInput.new()).drink_hp, "below 30% it drinks")
	w.potions.stock.hp.count = 0
	assert_false(m.apply(w, MoveInput.new()).drink_hp, "no stock, no drink")
	assert_eq(MOTOR.new(1, QUIET).apply(w, bot_wants).drink_hp, true, "null keeps the controller's timing")
