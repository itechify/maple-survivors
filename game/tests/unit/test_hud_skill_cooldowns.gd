extends TestCase
## HUD skill icon state (#82): the cooldown sweep shape, the sim's per-skill readiness (cooldown left/total,
## waiting for MP) on seeded worlds, the allocation-free per-frame cooldown query, and the skill widget redrawing only
## when a sweep step or tint changes.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const ICON := Rect2(10, 20, 24, 24)


func _sweep(remaining: float, total: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	CooldownSweep.sweep_polygon(remaining, total, ICON, out)
	return out


func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	for i in poly.size():
		a += poly[i].cross(poly[(i + 1) % poly.size()])
	return absf(a) * 0.5


func test_sweep_is_full_at_cast_and_empty_when_ready() -> void:
	assert_near(_area(_sweep(0.9, 0.9)), 576.0, 1e-3, "the whole 24 px icon is dark at the cast")
	assert_near(_area(_sweep(5.0, 0.9)), 576.0, 1e-3, "clamped to full")
	assert_eq(_sweep(0.0, 0.9).size(), 0, "nothing drawn when ready")
	assert_eq(_sweep(-0.2, 0.9).size(), 0, "nothing drawn past ready")
	assert_eq(_sweep(0.5, 0.0).size(), 0, "nothing drawn before any cast")


func test_sweep_clears_clockwise_from_twelve_o_clock() -> void:
	var half := _sweep(0.45, 0.9)
	assert_near(_area(half), 288.0, 1e-3, "half dark at half the cooldown")
	for p: Vector2 in half:
		assert_true(p.x <= 22.0 + 1e-4, "the right half (12 to 6 o'clock) has cleared first: %s" % p)
	var three_quarters := _sweep(0.75, 1.0)
	assert_near(_area(three_quarters), 432.0, 1e-3)
	for p: Vector2 in three_quarters:
		assert_false(p.x > 22.0 + 1e-4 and p.y < 32.0 - 1e-4, "12 to 3 o'clock cleared: %s" % p)
	var quarter := _sweep(0.25, 1.0)
	assert_near(_area(quarter), 144.0, 1e-3)
	for p: Vector2 in quarter:
		assert_true(p.x <= 22.0 + 1e-4 and p.y <= 32.0 + 1e-4, "the last dark wedge ends at 12 o'clock: %s" % p)


func _mage(skill: String) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var world := RunWorld.new(RF.setup("quiet", 9, data))
	RF.change_job_bare(world, 200)
	RF.place_player(world, 1200)
	world.learn_skill(skill)
	RF.put_mob(world, 1110100, 1350, 190, 100)
	world.mob_kinds[int(world.kind_of_id[1110100])].move_speed = 0
	world.god = true
	world.drain_events()
	return world


func test_cast_exposes_cooldown_left_and_total_of_the_skill() -> void:
	var world := _mage("energy_bolt")
	var before := world.skill_readiness("energy_bolt")
	assert_eq(float(before.total), 0.0, "no cooldown before the first cast")
	assert_eq(float(before.left), 0.0, "ready before the first cast")
	world.step(DT, MoveInput.new())
	var after := world.skill_readiness("energy_bolt")
	# Energy Bolt's survivor cooldown is 0.9 s; the first tick's overshoot (one dt) carries into it.
	assert_near(float(after.total), 0.9, DT + 1e-6, "total is the cooldown set at the cast")
	assert_near(float(after.left), float(after.total), 1e-6, "full at the cast")
	for tick in 27:
		world.step(DT, MoveInput.new())
	var mid := world.skill_readiness("energy_bolt")
	assert_near(float(mid.left), float(after.total) - 27 * DT, 1e-4, "counts down by dt per tick")
	assert_near(float(mid.total), float(after.total), 1e-6, "the total stays until the next cast")
	assert_false(bool(mid.mp_short), "a cooling skill is not waiting for MP")


func test_ready_skill_below_its_mp_cost_is_mp_short_until_affordable() -> void:
	var world := _mage("energy_bolt")
	world.spend_mp(int(world.player_state.mp) - 5)
	world.step(DT, MoveInput.new())
	var row := world.skill_readiness("energy_bolt")
	assert_true(bool(row.mp_short), "ready, in range, 5 MP < 6: waiting for MP")
	assert_eq(float(row.left), 0.0, "still ready")
	world.heal_fraction("mp", 1.0)
	world.step(DT, MoveInput.new())
	row = world.skill_readiness("energy_bolt")
	assert_false(bool(row.mp_short), "cast once affordable")
	assert_true(float(row.left) > 0.0, "and cooling down again")


func _teleporter() -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = 200
	var setup := RF.setup("quiet", 60, data)
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	setup.skill_imgs["210"] = {"skill": {"2101002": {"level": {"1": {"mpCon": 60, "range": 130}}}}}
	var w := RunWorld.new(setup)
	w.change_job(210)
	w.heal_fraction("mp", 1.0)
	w.loadout.add_skill("teleport_fp")
	w.player.place(Vector2(400, 0), w.fhm)
	w.drain_events()
	return w


func test_teleport_exposes_its_repeat_timer_and_waits_for_mp_only_when_ready() -> void:
	var w := _teleporter()
	assert_false(bool(w.skill_readiness("teleport_fp").mp_short), "affordable and ready")
	var press := MoveInput.new()
	press.press_skill("teleport")
	w.step(DT, press)
	var row: Dictionary = w.skill_readiness("teleport_fp")
	# Teleport's survivor repeat delay is 0.3 s (skills.json).
	assert_near(float(row.total), 0.3, 1e-6, "total is Teleport's repeat delay")
	assert_near(float(row.left), 0.3, 1e-6, "full right after the blink")
	w.spend_mp(int(w.player_state.mp))
	assert_false(bool(w.skill_readiness("teleport_fp").mp_short), "cooling down: the sweep shows, not the MP tint")
	for tick in 20:
		w.step(DT, MoveInput.new())
	row = w.skill_readiness("teleport_fp")
	assert_eq(float(row.left), 0.0, "ready again")
	assert_true(bool(row.mp_short), "ready but below its MP cost")
	w.heal_fraction("mp", 1.0)
	assert_false(bool(w.skill_readiness("teleport_fp").mp_short), "affordable again")


func test_lean_cooldown_query_fills_the_callers_buffers_like_skill_readiness() -> void:
	var world := _mage("energy_bolt")
	world.learn_skill("magic_claw")
	var left := PackedFloat32Array()
	var total := PackedFloat32Array()
	var short := PackedByteArray()
	var tinted := false
	for frame: int in 4:
		if frame == 0:
			world.spend_mp(int(world.player_state.mp)) # ready with a target but out of MP: the tint
		if frame == 1:
			world.heal_fraction("mp", 1.0) # then both cast, one per tick, and cool down
		world.step(DT, MoveInput.new())
		world.read_skill_cooldowns(left, total, short)
		assert_eq(left.size(), world.loadout.order.size(), "one entry per owned skill, in learned order")
		for i in world.loadout.order.size():
			var key := String(world.loadout.order[i])
			var r := world.skill_readiness(key)
			assert_near(left[i], float(r.left), 1e-5, "left of %s" % key)
			assert_near(total[i], float(r.total), 1e-5, "total of %s" % key)
			assert_eq(short[i], int(bool(r.mp_short)), "mp_short of %s" % key)
		tinted = tinted or 1 in short
	assert_true(tinted, "a ready skill out of MP shows the tint in the buffers too")
	assert_true(left[0] > 0.0 and left[1] > 0.0, "and both cooling once paid for")


func _row(left: float, total: float) -> Dictionary:
	return {"icon": "", "rank": 1, "key_label": "", "cooldown_left": left, "cooldown_total": total, "mp_short": false}


func test_skill_widget_redraws_only_when_a_sweep_step_or_tint_changes() -> void:
	var w := HudSkills.new()
	w.update({}, {"skills": [_row(0.0, 0.0), _row(0.0, 0.0)]})
	var left := PackedFloat32Array([0.0, 0.0])
	var total := PackedFloat32Array([0.0, 0.0])
	var short := PackedByteArray([0, 0])
	assert_false(w.set_cooldowns(left, total, short), "both ready, as last drawn: no redraw")
	left[0] = 0.9
	total[0] = 0.9
	assert_true(w.set_cooldowns(left, total, short), "a cast covers the icon")
	assert_eq(int(w.displayed()[0].sweep_step), HudSkills.SWEEP_STEPS, "fully dark")
	assert_false(w.set_cooldowns(left, total, short), "same values: no redraw")
	left[0] = 0.9 - DT
	assert_true(w.set_cooldowns(left, total, short), "a 0.9 s cooldown moves its sweep every tick")
	left[1] = 30.0
	total[1] = 30.0
	w.set_cooldowns(left, total, short)
	left[1] = 30.0 - DT
	assert_false(w.set_cooldowns(left, total, short), "a 30 s cooldown waits for its next step, not every tick")
	left[1] = 30.0 - 20 * DT
	assert_true(w.set_cooldowns(left, total, short), "and moves once the step is crossed")
	short[1] = 1
	assert_true(w.set_cooldowns(left, total, short), "the MP-wait tint redraws")
	assert_true(bool(w.displayed()[1].mp_short))
	w.free()
