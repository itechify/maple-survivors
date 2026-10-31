extends TestCase
## Meso charge (M23, spec #383 NL4): the `meso_picked` event, amount-driven gain with a carried remainder, the decay
## clock, the read-only per-pip bonus and the meter's held-pip summary. Synthetic data only: a test job carries the
## spec's meter block and a test skill carries `read_per_unit`; Night Lord's own entries are other tickets'.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const PF := preload("res://tests/fixtures/pet_fixtures.gd")
const DT := 1.0 / 60.0
const MESO := {"id": "meso_charge", "max": 10, "gain": {"event": "meso_picked", "amount": 1, "per_mesos": 1000},
	"decay": {"interval": 6.0, "amount": 1}, "per_unit": {"stat": "damage", "value": 0.03}, "art": "x/y/iconRaw"}
const COMBO := {"id": "combo", "max": 10, "gain": {"event": "cast_landed", "amount": 1, "exclude": "finisher"},
	"per_unit": {"stat": "damage", "value": 0.02}}


func _meter(definition: Dictionary = MESO) -> PlayerMeter:
	return PlayerMeter.new(definition)


func _mesos_world(definition: Dictionary = MESO) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["meter"] = definition
	data.jobs_survivor.jobs["212"]["skill_pool"] = ["magic_claw", "energy_bolt"]
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(RF.setup("quiet", 403, data))
	RF.place_player(w, 200)
	return w


func _meso_drop(w: RunWorld, amount: int, dx := 0.0) -> void:
	var slot := w.pickups.spawn_meso(w.player.pos + Vector2(dx, -10.0), amount)
	w.pickups.state[slot] = PickupSystem.REST


func _events_of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


# --- MesoCharge arithmetic ---------------------------------------------------------------------------------------

func test_take_carries_the_remainder_so_no_mesos_are_rounded_away() -> void:
	var first := MesoCharge.take(0, 999, 1000)
	assert_eq(first, {"units": 0, "carry": 999})
	var second := MesoCharge.take(int(first.carry), 1, 1000)
	assert_eq(second, {"units": 1, "carry": 0}, "999 then 1 is one pip")
	var burst := MesoCharge.take(0, 1999, 1000)
	var topped := MesoCharge.take(int(burst.carry), 1, 1000)
	assert_eq(int(burst.units) + int(topped.units), 2, "1999 then 1 is two pips")
	assert_eq(topped.carry, 0)
	assert_eq(MesoCharge.take(250, 3300, 1000), {"units": 3, "carry": 550})


func test_take_ignores_nonpositive_amounts_and_rates() -> void:
	assert_eq(MesoCharge.take(400, 0, 1000), {"units": 0, "carry": 400})
	assert_eq(MesoCharge.take(400, -50, 1000), {"units": 0, "carry": 400})
	assert_eq(MesoCharge.take(400, 900, 0), {"units": 0, "carry": 400}, "a missing rate gains nothing")


func test_decay_clock_arithmetic() -> void:
	assert_eq(MesoCharge.decay(0.0, 2.0, 6.0, 3, 1), {"clock": 2.0, "lost": 0})
	assert_eq(MesoCharge.decay(5.0, 1.0, 6.0, 3, 1), {"clock": 0.0, "lost": 1}, "a whole interval is one pip")
	assert_eq(MesoCharge.decay(0.0, 13.0, 6.0, 5, 1), {"clock": 1.0, "lost": 2}, "two intervals in one step")
	assert_eq(MesoCharge.decay(0.0, 20.0, 6.0, 2, 1), {"clock": 0.0, "lost": 2}, "never more than is held; clock cleared")
	assert_eq(MesoCharge.decay(4.0, 10.0, 6.0, 0, 1), {"clock": 0.0, "lost": 0}, "nothing held: the clock does not run")
	assert_eq(MesoCharge.decay(0.0, 7.0, 6.0, 5, 2), {"clock": 1.0, "lost": 2}, "amount per interval")


# --- PlayerMeter: amount-driven gain -----------------------------------------------------------------------------

func test_gain_amount_turns_mesos_into_pips_with_a_carry_and_caps() -> void:
	var meter := _meter()
	var events: Array = []
	meter.gain_amount("meso_picked", 999, events)
	assert_eq(meter.value, 0)
	assert_eq(events.size(), 0, "no pip, no event")
	meter.gain_amount("meso_picked", 1, events)
	assert_eq(meter.value, 1)
	assert_eq(events, [{"type": "meter_changed", "id": "meso_charge", "value": 1, "max": 10}])
	meter.gain_amount("meso_picked", 4300, events)
	assert_eq(meter.value, 5)
	assert_eq(meter.carry, 300, "the remainder is held")
	meter.gain_amount("meso_picked", 900000, events)
	assert_eq(meter.value, 10, "capped at max")
	var count := events.size()
	meter.gain_amount("meso_picked", 5000, events)
	assert_eq(events.size(), count, "no meter_changed at the cap")


func test_gain_amount_ignores_other_events_and_rules_without_per_mesos() -> void:
	var meter := _meter()
	var events: Array = []
	meter.gain_amount("cast_landed", 5000, events)
	assert_eq(meter.value, 0)
	assert_eq(meter.carry, 0)
	var flat := _meter({"id": "f", "max": 5, "gain": {"event": "meso_picked", "amount": 2}})
	flat.gain_amount("meso_picked", 123, events)
	assert_eq(flat.value, 2, "a rule without per_mesos adds its amount once, like gain()")


func test_count_driven_gain_is_unchanged_and_a_meter_without_per_mesos_keeps_no_carry() -> void:
	var meter := _meter(COMBO)
	var events: Array = []
	meter.gain("cast_landed", events)
	meter.gain_amount("meso_picked", 99999, events)
	assert_eq(meter.value, 1)
	assert_eq(meter.carry, 0)
	assert_eq(meter.snapshot(), {"id": "combo", "value": 1, "max": 10, "art": ""}, "the HUD snapshot keeps its shape")
	meter.gain("meso_picked", events)
	assert_eq(meter.value, 1, "gain() never reads mesos")


# --- PlayerMeter: decay ------------------------------------------------------------------------------------------

func test_decay_removes_one_pip_per_interval_only_while_positive_and_never_below_zero() -> void:
	var meter := _meter()
	var events: Array = []
	meter.gain_amount("meso_picked", 3000, events)
	events.clear()
	for tick in 359:
		meter.step(DT, events)
	assert_eq(meter.value, 3, "just under 6 s: nothing lost")
	meter.step(DT, events)
	assert_eq(meter.value, 2, "at 6 s one pip leaves")
	assert_eq(events, [{"type": "meter_changed", "id": "meso_charge", "value": 2, "max": 10}])
	for tick in 720:
		meter.step(DT, events)
	assert_eq(meter.value, 0)
	for tick in 1200:
		meter.step(DT, events)
	assert_eq(meter.value, 0, "never negative")
	assert_eq(events.size(), 3, "three changes in all, none while empty")


func test_decay_clock_runs_only_while_positive_and_restarts_from_empty() -> void:
	var meter := _meter()
	var events: Array = []
	for tick in 600:
		meter.step(DT, events)
	meter.gain_amount("meso_picked", 1000, events)
	for tick in 300:
		meter.step(DT, events)
	assert_eq(meter.value, 1, "the idle seconds at zero did not pre-load the clock")
	for tick in 60:
		meter.step(DT, events)
	assert_eq(meter.value, 0)


func test_an_emptied_meter_clears_the_clock() -> void:
	var meter := _meter()
	var events: Array = []
	meter.gain_amount("meso_picked", 2000, events)
	for tick in 300:
		meter.step(DT, events)
	meter.value = 0
	meter.step(DT, events) # an empty meter drops the half-run clock
	meter.gain_amount("meso_picked", 1000, events)
	for tick in 300:
		meter.step(DT, events)
	assert_eq(meter.value, 1, "a fresh pip gets a full interval")


func test_without_a_decay_key_step_does_nothing() -> void:
	var meter := _meter(COMBO)
	var events: Array = []
	meter.gain("cast_landed", events)
	events.clear()
	for tick in 2000:
		meter.step(DT, events)
	assert_eq(meter.value, 1)
	assert_eq(events.size(), 0)


func test_decay_draws_no_rng() -> void:
	var still := MESO.duplicate(true)
	still.erase("decay")
	var a := _mesos_world()
	var b := _mesos_world(still)
	a.meter.gain_amount("meso_picked", 5000, a.events)
	b.meter.gain_amount("meso_picked", 5000, b.events)
	for tick in 1900:
		a.step(DT, MoveInput.new())
		b.step(DT, MoveInput.new())
	assert_eq(a.meter.value, 0)
	assert_eq(b.meter.value, 5)
	for stream: String in ["rng", "spawn_rng", "card_rng", "drop_rng", "meso_rng", "equip_rng", "scroll_rng", "reward_rng", "final_rng"]:
		assert_eq((a.get(stream) as RandomNumberGenerator).state, (b.get(stream) as RandomNumberGenerator).state, stream)


# --- RunWorld: the event, the wallet and the lifetime of the carry -----------------------------------------------

func test_meso_picked_fires_once_per_tick_with_the_total_and_the_count() -> void:
	var w := _mesos_world()
	_meso_drop(w, 300, -5)
	_meso_drop(w, 450, 5)
	w.step(DT, MoveInput.new())
	var got := _events_of(w.drain_events(), "meso_picked")
	assert_eq(got, [{"type": "meso_picked", "amount": 750, "count": 2}])
	assert_eq(w.mesos, 750)
	w.step(DT, MoveInput.new())
	assert_eq(_events_of(w.drain_events(), "meso_picked").size(), 0, "no mesos this tick, no event")


func test_pickups_feed_the_meter_and_the_carry_survives_map_transfer_and_resets_with_a_new_round() -> void:
	var w := _mesos_world()
	_meso_drop(w, 700)
	w.step(DT, MoveInput.new())
	_meso_drop(w, 700)
	w.step(DT, MoveInput.new())
	assert_eq(w.meter.value, 1)
	assert_eq(w.meter.carry, 400)
	assert_eq(w.mesos, 1400, "the wallet is the plain sum")
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.meter.carry, 400, "the carry travels between maps")
	assert_eq(w.meter.value, 1)
	var fresh := _mesos_world()
	assert_eq(fresh.meter.carry, 0)
	assert_eq(fresh.meter.value, 0)


func test_the_pets_pickups_and_the_finale_vacuum_feed_the_charge_too() -> void:
	var data := PF.data({"lost_seconds": 1000.0, "teleport_distance": 5000.0, "lost_distance": 5000.0})
	data.jobs_survivor.jobs["212"]["meter"] = MESO
	var w := PF.world([PF.KITTY], {}, data)
	PF.put_player(w, 100.0, 0.0)
	PF.put_pet(w, Vector2(1100.0, 0.0))
	var slot := w.pickups.spawn_meso(Vector2(1120.0, 0.0), 2500)
	w.pickups.state[slot] = PickupSystem.REST
	var events := PF.run(w, 2)
	assert_eq(PF.of_type(events, "meso_picked"), [{"type": "meso_picked", "amount": 2500, "count": 1}])
	assert_eq(w.meter.value, 2)
	assert_eq(w.meter.carry, 500)


func test_a_shop_sale_is_not_a_pickup() -> void:
	var w := _mesos_world()
	w.setup.scroll_info = {2043700: {"incMAD": 1, "success": 100, "price": 5000}}
	w.grant_scrolls(2043700, 3)
	assert_eq(w.sell_scrolls(2043700, 3), "")
	assert_true(w.mesos > 0, "the sale paid out")
	w.step(DT, MoveInput.new())
	assert_eq(_events_of(w.drain_events(), "meso_picked").size(), 0)
	assert_eq(w.meter.value, 0)
	assert_eq(w.meter.carry, 0)


func test_only_a_meter_driven_by_mesos_hears_them_so_other_jobs_event_bytes_stay_put() -> void:
	for definition: Dictionary in [{}, COMBO]:
		var w := _mesos_world(definition)
		_meso_drop(w, 800)
		w.step(DT, MoveInput.new())
		assert_eq(_events_of(w.drain_events(), "meso_picked").size(), 0, "no event for %s" % definition.get("id", "no meter"))
		assert_eq(w.mesos, 800, "the wallet is credited either way")
		assert_eq(w.meter.value, 0)


# --- read_per_unit -----------------------------------------------------------------------------------------------

func _reader(w: RunWorld, key: String, read: float) -> void:
	var d := w.book.def("magic_claw").duplicate(true)
	d.meter = {"read_per_unit": read}
	w.book.defs[key] = d
	w.data.jobs_survivor.jobs["212"].skill_pool.append(key)
	w.learn_skill(key)


func test_read_per_unit_multiplies_damage_and_status_damage_without_spending_or_gating() -> void:
	var w := _mesos_world()
	_reader(w, "reader", 0.10)
	var base := w.runner.stats_of(w, "reader")
	assert_true(w.meter.admits(w.book.def("reader")), "no gate at an empty charge")
	var empty := w.meter.begin_cast(w, "reader", base)
	assert_near(float(empty.damage_max), float(base.damage_max) * 1.0, 1e-6)
	w.meter.value = 5
	var held := w.meter.begin_cast(w, "reader", base)
	# per_unit 0.03 x5 on every pool cast, read 0.10 x5 on this skill: both multiply.
	assert_near(float(held.damage_min), float(base.damage_min) * 1.15 * 1.5, 1e-6)
	assert_near(float(held.damage_max), float(base.damage_max) * 1.15 * 1.5, 1e-6)
	assert_near(float(held.status_damage_mult), float(base.status_damage_mult) * 1.15 * 1.5, 1e-6)
	assert_eq(w.meter.value, 5, "nothing spent")
	assert_false(held.has("meter_spent"))


func test_read_per_unit_is_admitted_even_on_a_job_without_a_meter() -> void:
	var w := RF.quiet_world(200.0)
	w.learn_skill("magic_claw")
	var d := w.book.def("magic_claw").duplicate(true)
	d.meter = {"read_per_unit": 0.10}
	assert_true(w.meter.admits(d), "a read-only block never gates")
	d.meter = {"role": "finisher", "min": 1, "spend": "all", "damage_per_unit": 0.1}
	assert_false(w.meter.admits(d), "a finisher still needs a meter")


func test_a_skill_without_read_per_unit_is_byte_identical_to_before() -> void:
	var w := _mesos_world()
	w.learn_skill("magic_claw")
	w.meter.value = 4
	var base := w.runner.stats_of(w, "magic_claw")
	var held := w.meter.begin_cast(w, "magic_claw", base)
	assert_near(float(held.damage_max), float(base.damage_max) * 1.12, 1e-6)
	assert_near(float(held.status_damage_mult), float(base.status_damage_mult) * 1.12, 1e-6)


func test_a_read_only_cast_lands_the_boosted_damage_end_to_end() -> void:
	var plain := _mesos_world()
	var boosted := _mesos_world()
	for w: RunWorld in [plain, boosted]:
		w.loadout.order.clear()
		w.loadout.set_caster(100.0, 100.0, 1)
		_reader(w, "reader", 0.10)
		w.loadout.order.erase("magic_claw")
		var m := RF.put_mob(w, 1110100, 240, 195, 100000.0)
		w.swarm.hp[m] = 100000
		w.swarm.max_hp[m] = 100000
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	boosted.meter.value = 10
	plain.runner.step(DT, plain)
	boosted.runner.step(DT, boosted)
	assert_eq(boosted.meter.value, 10, "casting spent nothing")
	assert_eq(plain.runner.casts, 1)
	assert_eq(boosted.runner.casts, 1)


# --- summary -----------------------------------------------------------------------------------------------------

func test_meter_stats_are_time_weighted_mean_and_peak() -> void:
	var meter := _meter()
	var events: Array = []
	assert_eq(meter.stats(), {"mean": 0.0, "peak": 0})
	meter.gain_amount("meso_picked", 4000, events)
	for tick in 60:
		meter.step(DT, events) # 1 s holding 4
	meter.gain_amount("meso_picked", 2000, events)
	for tick in 60:
		meter.step(DT, events) # 1 s holding 6
	var stats := meter.stats()
	assert_near(float(stats.mean), 5.0, 1e-6)
	assert_eq(stats.peak, 6)


func test_a_job_without_a_meter_has_no_stats_and_combo_stats_do_not_touch_its_events() -> void:
	assert_eq(_meter({}).stats(), {})
	var meter := _meter(COMBO)
	var events: Array = []
	meter.gain("cast_landed", events)
	events.clear()
	for tick in 120:
		meter.step(DT, events)
	assert_eq(events.size(), 0)
	assert_near(float(meter.stats().mean), 1.0, 1e-6)
	assert_eq(meter.stats().peak, 1)


func test_the_world_reports_meter_stats_for_the_run() -> void:
	var w := _mesos_world()
	_meso_drop(w, 3000)
	for tick in 120:
		w.step(DT, MoveInput.new())
	var stats := w.meter.stats()
	assert_eq(stats.peak, 3)
	assert_true(float(stats.mean) > 2.0 and float(stats.mean) <= 3.0)


func test_skill_text_names_the_read_and_no_gate() -> void:
	var w := _mesos_world()
	_reader(w, "reader", 0.10)
	w.book.defs.reader.meter.unit = "pips"
	var line := SkillText.new(w.book).level_line("reader", 1, w.loadout.stats("reader"))
	assert_true("+10% damage per pips held" in line, line)
	assert_false("Needs" in line or "Spends" in line, line)


# --- docs and data contracts -------------------------------------------------------------------------------------

func test_meso_picked_is_a_registered_event() -> void:
	assert_eq(RunWorld.EVENT_FIELDS.get("meso_picked"), ["amount", "count"])
