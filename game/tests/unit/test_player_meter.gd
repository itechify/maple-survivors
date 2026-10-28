extends TestCase
## Meter behaviour through the pure counter seam and fixed-tick RunWorld casts.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const COMBO := {"id": "combo", "max": 10, "gain": {"event": "cast_landed", "amount": 1, "exclude": "finisher"},
	"per_unit": {"stat": "damage", "value": 0.02}}

func test_counter_clamps_emits_changes_and_other_event_meters_reuse_it() -> void:
	var meter := PlayerMeter.new(COMBO)
	var events: Array = []
	assert_eq(meter.value, 0)
	for i in 12:
		meter.gain("cast_landed", events)
	assert_eq(meter.value, 10)
	assert_eq(events.size(), 10)
	assert_eq(events[0], {"type": "meter_changed", "id": "combo", "value": 1, "max": 10})
	var meso := PlayerMeter.new({"id": "meso", "max": 3, "gain": {"event": "meso_picked", "amount": 2}})
	meso.gain("cast_landed", events)
	assert_eq(meso.value, 0)
	meso.gain("meso_picked", events)
	assert_eq(meso.value, 2)

func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["meter"] = COMBO
	data.jobs_survivor.jobs["212"]["skill_pool"] = ["magic_claw", "energy_bolt"]
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(RF.setup("quiet", 299, data))
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.loadout.set_caster(100.0, 100.0, 1)
	w.learn_skill("magic_claw")
	return w

func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, 1110100, px, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func test_landed_cast_once_across_lines_and_targets_no_hit_and_transfer() -> void:
	var w := _world()
	w.runner.step(DT, w)
	assert_eq(w.meter.value, 0, "no target earns nothing")
	_mob(w, 240)
	_mob(w, 260)
	w.loadout.add_skill_mod("magic_claw", "count", "add", 1)
	w.runner.step(DT, w)
	assert_eq(w.meter.value, 1, "two lines on two targets earn one orb")
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.meter.value, 1, "transfer keeps meter")
	assert_eq(_world().meter.value, 0, "new round starts empty")

func _finisher(w: RunWorld, key: String, count: int) -> void:
	var d := w.book.def("magic_claw").duplicate(true)
	d.meter = {"role": "finisher", "min": 5, "spend": "all", "damage_per_unit": 0.10}
	d.count = count
	d.cooldown = 0.1
	w.book.defs[key] = d
	w.data.jobs_survivor.jobs["212"].skill_pool.append(key)
	w.learn_skill(key)

func test_finisher_gate_spend_keep_bonus_snapshot_and_cooldown_floor() -> void:
	var w := _world()
	_finisher(w, "finish", 1)
	w.loadout.order.erase("magic_claw")
	_mob(w, 240)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "empty meter blocks finisher")
	for i in 5:
		w.meter.gain("cast_landed", w.events)
	var base := w.runner.stats_of(w, "finish")
	w.loadout.add_skill_mod("finish", "meter_keep", "add", 2)
	var boosted := w.meter.begin_cast(w, "finish", base)
	assert_near(float(boosted.damage_max), float(base.damage_max) * 1.1 * 1.3, 0.001)
	assert_eq(boosted.meter_spent, 3, "cast metadata is available to finisher art")
	assert_eq(w.meter.value, 2, "only three orbs spent")
	for i in 3:
		w.meter.gain("cast_landed", w.events)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.meter.value, 2, "finisher hits never earn orbs")
	assert_true(float(w.runner.cooldowns.finish) > 0.98, "one second floor")

func test_crowd_finisher_wins_then_single_target_boss_wins() -> void:
	var w := _world()
	_finisher(w, "single", 1)
	_finisher(w, "crowd", 3)
	w.loadout.order.erase("magic_claw")
	var boss := _mob(w, 240)
	_mob(w, 260)
	_mob(w, 280)
	for i in 10:
		w.meter.gain("cast_landed", w.events)
	w.runner.step(DT, w)
	assert_true(w.runner.cooldowns.has("crowd"))
	assert_eq(w.meter.value, 0)
	# A scheduled boss makes the single-target finisher the better use of the meter.
	w.mob_boss[boss] = 0
	w.runner.cooldowns.crowd = 0
	for i in 5:
		w.meter.gain("cast_landed", w.events)
	w.runner.step(DT, w)
	assert_true(w.runner.cooldowns.has("single"))

func test_pool_bonus_excludes_mobility_and_projectile_cast_only_gains_on_first_impact() -> void:
	var w := _world()
	w.loadout.order.clear()
	w.loadout.order.append("energy_bolt")
	_mob(w, 300)
	for i in 5:
		w.meter.gain("cast_landed", w.events)
	var base := w.runner.stats_of(w, "energy_bolt")
	var boosted := w.meter.begin_cast(w, "energy_bolt", base)
	assert_near(float(boosted.damage_max), float(base.damage_max) * 1.1, 0.001)
	assert_eq(w.meter.begin_cast(w, "teleport_fp", base), base)
	w.loadout.add_skill_mod("energy_bolt", "count", "add", 2)
	w.runner.step(DT, w)
	assert_eq(w.meter.value, 5, "launch is not a landed cast")
	for i in 120:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events, PackedFloat32Array(), PackedByteArray(),
			func(_slot: int, hit: Dictionary) -> void: w.meter.landed(hit.get("meter_receipt", {}), w.events))
	assert_eq(w.meter.value, 6, "three shots share the cast receipt")

func test_hud_pips_and_finisher_text_show_requirement_and_keep() -> void:
	var hud := HudMeter.new()
	hud.update({}, {"meter": {"id": "combo", "value": 4, "max": 10}})
	assert_eq(hud.pip_count(), 10)
	assert_eq(hud.filled_count(), 4)
	hud.update({}, {})
	assert_eq(hud.pip_count(), 0)
	hud.free()
	var w := _world()
	_finisher(w, "finish", 1)
	w.loadout.add_skill_mod("finish", "meter_keep", "add", 2)
	var text := SkillText.new(w.book)
	var line := text.level_line("finish", 1, w.loadout.stats("finish"))
	assert_true("Needs 5 orbs" in line)
	assert_true("Keeps 2 orbs" in line)

func test_rarity_keep_preview_and_applied_modifier_use_the_same_units() -> void:
	var w := _world()
	w.book.defs.magic_claw.meter = {"role": "finisher", "min": 5, "spend": "all", "damage_per_unit": 0.1}
	w.book.defs.magic_claw.rarity_bonuses = {"legendary": [
		{"id": "combo", "name": "Advanced Combo", "effects": [{"stat": "meter_keep", "op": "add", "value": 2}]}]}
	var c := w.upgrades.choice_card("magic_claw_rank", w, "legendary")
	assert_true("Keeps 2 orbs" in String(c.desc), String(c.desc))
	assert_eq(c.skill_mod_changes.meter_keep, {"before": 0, "after": 2})
	w.upgrades.apply(c.id, w, "legendary")
	assert_eq(w.loadout.stats("magic_claw").meter_keep, 2)

func test_a_projectile_cast_that_misses_does_not_gain_and_manual_hits_have_no_receipt() -> void:
	var w := _world()
	w.loadout.order.clear()
	w.loadout.order.append("energy_bolt")
	var m := _mob(w, 300)
	w.runner.step(DT, w)
	w.swarm.x[m] = 1500
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	for i in 120:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events, PackedFloat32Array(), PackedByteArray(),
			func(_slot: int, hit: Dictionary) -> void: w.meter.landed(hit.get("meter_receipt", {}), w.events))
	assert_eq(w.meter.value, 0)
	var st := w.runner.stats_of(w, "magic_claw")
	st = w.meter.begin_cast(w, "rush_hero", st)
	w.hit_mob(m, st, -1)
	assert_eq(w.meter.value, 0, "out-of-pool manual attack gives no orb")

func test_finisher_admission_waits_for_its_prepared_target_minimum() -> void:
	var w := _world()
	_finisher(w, "crowd", 3)
	w.loadout.order.erase("magic_claw")
	w.book.defs.crowd.cast = {"rule": "range_around", "mob_count": 3, "min_targets": 3}
	for i in 5:
		w.meter.gain("cast_landed", w.events)
	_mob(w, 240)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "a crowd finisher waits even when it is the only finisher owned")
	assert_eq(w.meter.value, 5, "target rejection spends nothing")
	_mob(w, 260)
	_mob(w, 280)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.meter.value, 0)
