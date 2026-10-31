extends TestCase
## The stage level scale (#453): a synthetic curve and stage through RunWorld spawns, hits, kills and boss arrivals, the
## validation of the block, determinism, and the committed v83 reference curve file.

const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0
## Tauromacis fixture: level 70, 1,000,000 HP. Its defences and EXP are set by _setup so ratios are visible.
const L := 70
const KEYS := [{"t": 0.0, "level": 40.0, "exp_level": 30.0}, {"t": 100.0, "level": 80.0, "exp_level": 60.0}]


## Distinct, simple synthetic curves: every stat grows differently, so a mixed-up stat shows.
func _curve() -> Dictionary:
	var out := {"hp": [], "pad": [], "mad": [], "pdd": [], "mdd": [], "exp": []}
	for level in range(1, 201):
		out.hp.append(100.0 * level * level)
		out.pad.append(10.0 * level)
		out.mad.append(20.0 * level + 100.0)
		out.pdd.append(5.0 * level)
		out.mdd.append(8.0 * level + 40.0)
		out.exp.append(3.0 * level * level)
	return out


func _hp(l: float) -> float:
	return 100.0 * l * l


func _pad(l: float) -> float:
	return 10.0 * l


func _mad(l: float) -> float:
	return 20.0 * l + 100.0


func _pdd(l: float) -> float:
	return 5.0 * l


func _mdd(l: float) -> float:
	return 8.0 * l + 40.0


func _exp(l: float) -> float:
	return 3.0 * l * l


## The Tauromacis setup with PDD 140, MDD 80, EXP 1000 and (when keyframes is non-empty) a level_scale on the quiet stage.
func _setup(keyframes: Array = KEYS, p_seed := 76) -> Dictionary:
	var setup := MF.setup(p_seed)
	setup.data["level_curve"] = _curve()
	var info: Dictionary = setup.mob_imgs[MF.TAURO].info
	info["PDDamage"] = 140.0
	info["MDDamage"] = 80.0
	info["exp"] = 1000.0
	var boogie: Dictionary = setup.mob_imgs[MF.BOOGIE].info
	boogie["PDDamage"] = 60.0
	boogie["MDDamage"] = 40.0
	boogie["exp"] = 500.0
	if not keyframes.is_empty():
		setup.data.stages.stages.quiet["level_scale"] = {"keyframes": keyframes.duplicate(true)}
	return setup


func _world(keyframes: Array = KEYS, p_seed := 76) -> RunWorld:
	var w := RunWorld.new(_setup(keyframes, p_seed))
	RF.place_player(w, 400)
	return w


func _spawn(w: RunWorld, hp_mult := 1.0) -> int:
	return w.spawn_mob(int(w.kind_of_id[MF.TAURO]), Vector2(750, 200), 0, hp_mult, false)


func _kill_exp(w: RunWorld, slot: int) -> int:
	w.drain_events()
	w._on_kill(slot)
	for event: Dictionary in w.drain_events():
		if event.type == "mob_died":
			return int(event.exp)
	return -1


# ---- the scale itself ----

func test_level_and_exp_level_interpolate_along_curve_time_and_hold() -> void:
	var scale := LevelScale.from_stage({"level_scale": {"keyframes": KEYS}}, _curve())
	assert_true(scale != null)
	assert_near(scale.level_at(0.0), 40.0)
	assert_near(scale.level_at(25.0), 50.0)
	assert_near(scale.level_at(100.0), 80.0)
	assert_near(scale.level_at(5000.0), 80.0, 1e-9, "holds after the last keyframe")
	assert_near(scale.exp_level_at(50.0), 45.0, 1e-9, "exp_level has its own keyframes")
	assert_near(scale.level_at(-5.0), 40.0, 1e-9, "holds before the first keyframe")
	var no_exp := LevelScale.from_stage({"level_scale": {"keyframes": [{"t": 0, "level": 33}]}}, _curve())
	assert_near(no_exp.exp_level_at(10.0), 33.0, 1e-9, "exp_level defaults to level")


func test_curve_value_interpolates_between_levels_and_ratio_is_one_at_the_same_level() -> void:
	var scale := LevelScale.from_stage({"level_scale": {"keyframes": KEYS}}, _curve())
	assert_near(scale.value("hp", 50.5), (_hp(50.0) + _hp(51.0)) * 0.5, 1e-6)
	assert_eq(scale.ratio("hp", 70.0, 70), 1.0, "E = L is exactly 1")
	assert_eq(scale.ratio("mad", 12.0, 12), 1.0)
	assert_near(scale.value("pad", 0.0), _pad(1.0), 1e-9, "clamped to level 1")
	assert_near(scale.value("pad", 999.0), _pad(200.0), 1e-9, "clamped to level 200")
	var flat := _curve()
	flat.mad = []
	for i in 200:
		flat.mad.append(0.0 if i < 50 else 100.0)
	var zero := LevelScale.from_stage({"level_scale": {"keyframes": KEYS}}, _curve())
	zero._curve["mad"] = PackedFloat64Array(flat.mad)
	assert_eq(zero.ratio("mad", 80.0, 10), 1.0, "a stat that is 0 at the canonical level scales by 1")


func test_stage_without_block_has_no_scale_and_slots_stay_empty() -> void:
	var w := _world([])
	assert_true(w.level_scale == null)
	_spawn(w)
	assert_eq(w.mob_level_exp.size(), 0, "no per-slot arrays without a level scale")


# ---- spawn-time ratios ----

func test_identity_when_effective_level_equals_the_monsters_level() -> void:
	var identity := _world([{"t": 0.0, "level": float(L)}])
	var plain := _world([])
	var a := _spawn(identity, 2.0)
	var b := _spawn(plain, 2.0)
	assert_eq(identity.swarm.max_hp[a], plain.swarm.max_hp[b], "HP unchanged")
	assert_eq(identity.mob_defense(a, false), plain.mob_defense(b, false), "PDD unchanged")
	assert_eq(identity.mob_defense(a, true), plain.mob_defense(b, true), "MDD unchanged")
	assert_eq(identity.hit_source_multiplier({"mob_id": MF.TAURO}, false), 1.0)
	assert_eq(identity.hit_source_multiplier({"mob_id": MF.TAURO}, true), 1.0)
	assert_eq(_kill_exp(identity, a), _kill_exp(plain, b), "EXP unchanged")


func test_hp_pdd_mdd_and_exp_ratios_at_a_keyframe_and_between_two() -> void:
	for t: float in [0.0, 50.0, 100.0]:
		var w := _world()
		w.time = t
		var e := 40.0 + 40.0 * t / 100.0
		var x := 30.0 + 30.0 * t / 100.0
		var slot := _spawn(w)
		assert_eq(w.swarm.max_hp[slot], roundi(1000000.0 * _hp(e) / _hp(L)), "HP at t=%s (E=%s)" % [t, e])
		assert_near(w.mob_defense(slot, false), 140.0 * _pdd(e) / _pdd(L), 1e-6, "PDD at t=%s" % t)
		assert_near(w.mob_defense(slot, true), 80.0 * _mdd(e) / _mdd(L), 1e-6, "MDD at t=%s" % t)
		var plain_exp := roundi(1000.0 * float(w.balance.get("exp_mult", 1.0)) * float(w.stage.get("exp_mult", 1.0)))
		assert_eq(_kill_exp(w, slot), roundi(plain_exp * _exp(x) / _exp(L)), "EXP uses exp_level at t=%s (X=%s)" % [t, x])


func test_bulk_live_defense_matches_mob_defense() -> void:
	var w := _world()
	w.time = 50.0
	var slot := _spawn(w)
	w._fill_live_defense()
	assert_near(w._live_pdd[slot], w.mob_defense(slot, false), 0.01, "shots and hits use the same defence")
	assert_near(w._live_mdd[slot], w.mob_defense(slot, true), 0.01)


func test_spawn_values_are_captured_and_hold_after_the_last_keyframe() -> void:
	var w := _world()
	var early := _spawn(w)
	var early_hp: int = w.swarm.max_hp[early]
	var early_pdd := w.mob_defense(early, false)
	w.time = 60.0
	assert_eq(w.swarm.max_hp[early], early_hp, "a living monster keeps its spawn HP")
	assert_near(w.mob_defense(early, false), early_pdd, 1e-9, "and its spawn defence")
	var late := _spawn(w)
	assert_ne(w.swarm.max_hp[late], early_hp)
	w.time = 4000.0
	var held := _spawn(w)
	assert_eq(w.swarm.max_hp[held], roundi(1000000.0 * _hp(80.0) / _hp(L)), "level 80 holds after the last keyframe")
	assert_near(w.mob_defense(held, false), 140.0 * _pdd(80.0) / _pdd(L), 1e-6)


func test_scale_stacks_with_the_spawn_hp_multiplier_and_follows_curve_time_of_the_map() -> void:
	var w := _world()
	var slot := _spawn(w, 3.0)
	assert_eq(w.swarm.max_hp[slot], roundi(1000000.0 * 3.0 * _hp(40.0) / _hp(L)), "x3 spawn scale stacks")
	var second := _world()
	second.stage["map_seconds"] = 60.0
	second.stage.maps.append(second.stage.maps[0].duplicate(true))
	second.map_index = 1
	second.time = 20.0
	second.map_entered_at = 10.0
	# curve time = 1 * 60 + (20 - 10) = 70 s: 70% of the way to level 80.
	assert_near(second.curve_time(), 70.0)
	assert_eq(second.swarm.max_hp[_spawn(second)], roundi(1000000.0 * _hp(68.0) / _hp(L)))


# ---- damage at impact ----

func test_physical_and_magic_damage_ratios_follow_the_time_of_the_impact() -> void:
	for t: float in [0.0, 50.0, 100.0, 400.0]:
		var w := _world()
		w.time = t
		var e := minf(80.0, 40.0 + 40.0 * t / 100.0)
		assert_near(w.hit_source_multiplier({"mob_id": MF.TAURO}, false), _pad(e) / _pad(L), 1e-9, "physical at t=%s" % t)
		assert_near(w.hit_source_multiplier({"mob_id": MF.TAURO}, true), _mad(e) / _mad(L), 1e-9, "magic at t=%s" % t)
		assert_near(w.hit_source_multiplier({"mob_id": MF.TAURO, "dmg_mult": 0.5, "elite": true}, false),
			0.5 * _pad(e) / _pad(L) * float(w.stage.get("elites", {}).get("damage_mult", 1.0)), 1e-9, "stacks with dmg_mult and elite")
	var w2 := _world()
	assert_eq(w2.hit_source_multiplier({}, false), 1.0, "a source without a mob id is unscaled")
	assert_eq(w2.hit_source_multiplier({"mob_id": 424242}, false), 1.0, "so is an unknown mob")


func test_take_hit_damage_scales_with_the_ratio_after_defence() -> void:
	for magic: bool in [false, true]:
		var w := _world()
		var plain := _world([])
		w.god = false
		plain.god = false
		var source := {"accuracy": 0, "mob_id": MF.TAURO, "dmg_mult": 1.0, "source_kind": "mob_attack"}
		var scaled := w.take_hit(300.0, magic, "", Vector2.ZERO, source)
		var base := plain.take_hit(300.0, magic, "", Vector2.ZERO, source)
		var expected := (_mad(40.0) / _mad(70.0)) if magic else (_pad(40.0) / _pad(70.0))
		assert_between(scaled, maxi(1, roundi(base * expected) - 1), roundi(base * expected) + 1,
			"same seed, same roll (magic=%s)" % magic)


func test_attack_n_and_touch_through_the_live_sim_use_the_scale() -> void:
	var w := _world([{"t": 0.0, "level": 700.0 / 10.0}], 76) # E = 70 = L: identity, the rolls match the plain world
	var plain := _world([], 76)
	RF.put_mob(w, MF.TAURO, 600)
	RF.put_mob(plain, MF.TAURO, 600)
	var log_a := []
	var log_b := []
	for tick in 400:
		w.step(DT, MoveInput.new())
		plain.step(DT, MoveInput.new())
		log_a.append_array(w.drain_events())
		log_b.append_array(plain.drain_events())
	assert_true(log_a.any(func(e: Dictionary) -> bool: return e.type == "player_hit"), "an attack landed")
	assert_eq(str(log_a), str(log_b), "identity scale: the same event log")


# ---- bosses capture at arrival ----

func _boss_world(keyframes: Array = KEYS) -> RunWorld:
	var setup := _setup(keyframes)
	RF.set_bosses(setup.data.stages.stages.quiet, [{"time": 10, "mob_id": MF.TAURO, "hp_mult": 1.0, "dmg_mult": 1.0}])
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.god = true
	return w


func test_boss_captures_hp_defence_exp_and_damage_at_arrival_while_ordinary_damage_follows_time() -> void:
	var w := _boss_world()
	var guard := 0
	while int(w.bosses.records[0].slot) < 0 and guard < 3000:
		w.step(DT, MoveInput.new())
		guard += 1
	var record: Dictionary = w.bosses.records[0]
	assert_true(int(record.slot) >= 0, "the boss arrived")
	if int(record.slot) < 0:
		return
	var arrival := float(record.spawn_time)
	var e := 40.0 + 40.0 * arrival / 100.0
	assert_near(float(record.level_scale_at), e, 1e-6, "the arrival's effective level is recorded")
	var slot := int(record.slot)
	assert_eq(w.swarm.max_hp[slot], roundi(1000000.0 * _hp(e) / _hp(L)), "boss HP at arrival")
	assert_near(w.mob_defense(slot, false), 140.0 * _pdd(e) / _pdd(L), 1e-6, "boss PDD at arrival")
	var boss_source := {"mob_id": MF.TAURO, "boss": true, "boss_index": 0}
	var ordinary_source := {"mob_id": MF.TAURO}
	assert_near(w.hit_source_multiplier(boss_source, false), _pad(e) / _pad(L), 1e-9, "boss physical at arrival")
	assert_near(w.hit_source_multiplier(boss_source, true), _mad(e) / _mad(L), 1e-9, "boss magic at arrival")
	w.time = 90.0
	assert_near(w.hit_source_multiplier(boss_source, false), _pad(e) / _pad(L), 1e-9, "the boss's damage is frozen")
	assert_near(w.hit_source_multiplier(boss_source, true), _mad(e) / _mad(L), 1e-9)
	assert_near(w.hit_source_multiplier(ordinary_source, false), _pad(76.0) / _pad(L), 1e-9, "an ordinary monster's follows t")
	assert_eq(w.swarm.max_hp[slot], roundi(1000000.0 * _hp(e) / _hp(L)), "boss HP stays")
	var x := 30.0 + 30.0 * arrival / 100.0
	w.swarm.hp[slot] = 0
	assert_eq(_kill_exp(w, slot), roundi(1000.0 * float(w.bosses.reward_config(0).get("exp_mult", 1.0)) * _exp(x) / _exp(L)),
		"boss EXP captured at arrival")


func test_balance_record_lists_the_level_at_each_boss_arrival_only_with_a_scale() -> void:
	var w := _boss_world()
	for tick in 1500:
		w.step(DT, MoveInput.new())
	var arrivals: Array = BR.level_scale_arrivals(w)
	assert_eq(arrivals.size(), 1)
	if arrivals.size() == 1:
		assert_eq(arrivals[0].mob_id, MF.TAURO)
		assert_near(float(arrivals[0].level), 40.0 + 0.4 * float(w.bosses.records[0].spawn_time), 1e-6)
	assert_true(BR.fight_records(w)[0].has("level_scale_at"))
	var plain := _boss_world([])
	for tick in 1500:
		plain.step(DT, MoveInput.new())
	assert_true(BR.level_scale_arrivals(plain).is_empty(), "no scale, no entries")
	assert_false(BR.fight_records(plain)[0].has("level_scale_at"), "and the fight record keeps its shape")
	assert_false(plain.bosses.records[0].has("level_scale_at"))


# ---- summons, revives, same-id bosses and final forms ----

func test_offspring_spawned_later_capture_their_own_ratios_and_take_damage_at_impact() -> void:
	var w := _world()
	var parent := RF.put_mob(w, MF.TAURO, 600)
	for tick in 5:
		w.step(DT, MoveInput.new())
	assert_true(w.swarm.platform[parent] >= 0, "the parent stands on a platform")
	var parent_hp: int = w.swarm.max_hp[parent]
	var parent_pdd := w.mob_defense(parent, false)
	assert_eq(parent_hp, roundi(1000000.0 * _hp(40.0) / _hp(L)), "the parent captured t = 0")
	w.time = 50.0 # E = 60, X = 45
	var kids := w.spawn_offspring(parent, 600.0, PackedInt32Array([MF.TAURO, MF.BOOGIE]), 0)
	assert_eq(kids.size(), 2)
	if kids.size() != 2:
		return
	var tauro_kid := kids[0]
	var boogie_kid := kids[1]
	assert_eq(w.swarm.max_hp[tauro_kid], roundi(1000000.0 * _hp(60.0) / _hp(L)), "same kind, its own spawn time")
	assert_ne(w.swarm.max_hp[tauro_kid], parent_hp)
	assert_near(w.mob_defense(tauro_kid, false), 140.0 * _pdd(60.0) / _pdd(L), 1e-6)
	assert_ne(w.mob_defense(tauro_kid, false), parent_pdd)
	assert_eq(w.swarm.max_hp[boogie_kid], roundi(1000000.0 * _hp(60.0) / _hp(35.0)), "a kind with another level uses its L")
	assert_near(w.mob_defense(boogie_kid, true), 40.0 * _mdd(60.0) / _mdd(35.0), 1e-6)
	var plain_exp := float(w.balance.get("exp_mult", 1.0)) * float(w.stage.get("exp_mult", 1.0))
	assert_eq(_kill_exp(w, boogie_kid), roundi(500.0 * plain_exp * _exp(45.0) / _exp(35.0)), "EXP at the kid's spawn")
	assert_eq(_kill_exp(w, parent), roundi(1000.0 * plain_exp * _exp(30.0) / _exp(L)), "the parent keeps its own")
	var source := {"mob_id": MF.BOOGIE}
	assert_near(w.hit_source_multiplier(source, false), _pad(60.0) / _pad(35.0), 1e-9, "damage at the impact's time")
	assert_near(w.hit_source_multiplier(source, true), _mad(60.0) / _mad(35.0), 1e-9)
	w.time = 100.0
	assert_near(w.hit_source_multiplier(source, false), _pad(80.0) / _pad(35.0), 1e-9, "and it follows t afterwards")
	assert_eq(w.swarm.max_hp[tauro_kid], roundi(1000000.0 * _hp(60.0) / _hp(L)), "while HP stays captured")


func test_two_scheduled_bosses_of_one_id_keep_separate_damage_freezes() -> void:
	var setup := _setup()
	RF.set_bosses(setup.data.stages.stages.quiet, [
		{"time": 5, "mob_id": MF.TAURO, "hp_mult": 1.0, "dmg_mult": 1.0},
		{"time": 40, "mob_id": MF.TAURO, "hp_mult": 1.0, "dmg_mult": 1.0}])
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.god = true
	var guard := 0
	while (int(w.bosses.records[0].slot) < 0 or int(w.bosses.records[1].slot) < 0) and guard < 4000:
		w.step(DT, MoveInput.new())
		guard += 1
	var first: Dictionary = w.bosses.records[0]
	var second: Dictionary = w.bosses.records[1]
	assert_true(int(first.slot) >= 0 and int(second.slot) >= 0, "both arrived")
	if int(first.slot) < 0 or int(second.slot) < 0:
		return
	var e0 := 40.0 + 0.4 * float(first.spawn_time)
	var e1 := 40.0 + 0.4 * float(second.spawn_time)
	assert_true(e1 > e0 + 5.0, "the arrivals are at different levels")
	var a := {"mob_id": MF.TAURO, "boss": true, "boss_index": 0}
	var b := {"mob_id": MF.TAURO, "boss": true, "boss_index": 1}
	assert_near(w.hit_source_multiplier(a, false), _pad(e0) / _pad(L), 1e-9, "boss 0 keeps its arrival")
	assert_near(w.hit_source_multiplier(b, false), _pad(e1) / _pad(L), 1e-9, "boss 1 has its own")
	assert_near(w.hit_source_multiplier(a, true), _mad(e0) / _mad(L), 1e-9)
	assert_near(w.hit_source_multiplier(b, true), _mad(e1) / _mad(L), 1e-9)
	assert_near(float(first.level_scale_at), e0, 1e-6)
	assert_near(float(second.level_scale_at), e1, 1e-6)


func test_a_final_form_recaptures_its_encounters_freeze_at_its_own_spawn() -> void:
	var w := _boss_world()
	var guard := 0
	while int(w.bosses.records[0].slot) < 0 and guard < 3000:
		w.step(DT, MoveInput.new())
		guard += 1
	var record: Dictionary = w.bosses.records[0]
	assert_true(int(record.slot) >= 0)
	if int(record.slot) < 0:
		return
	var arrival_level := float(record.level_scale_at)
	var source := {"mob_id": MF.BOOGIE, "boss": true, "boss_index": 0}
	w.time = 60.0 # E = 64 when the final form (another mob id, Lv35) spawns for the same encounter
	w.capture_boss_level_scale(0, MF.BOOGIE, record)
	assert_near(w.hit_source_multiplier(source, false), _pad(64.0) / _pad(35.0), 1e-9, "the final form's own level and time")
	assert_near(w.hit_source_multiplier(source, true), _mad(64.0) / _mad(35.0), 1e-9)
	w.time = 95.0
	assert_near(w.hit_source_multiplier(source, false), _pad(64.0) / _pad(35.0), 1e-9, "frozen again")
	assert_near(float(record.level_scale_at), arrival_level, 1e-9, "the telemetry keeps the first arrival")
	assert_eq(w.hit_source_multiplier({"mob_id": MF.TAURO, "boss": true, "boss_index": 3}, false), 1.0,
		"an encounter with no capture is unscaled")


func test_a_level_scale_stage_that_keeps_an_opening_ramp_still_builds() -> void:
	var setup := _setup()
	setup.data.stages.stages.quiet["opening_ramp"] = {"seconds": 60, "hp": {"start": 1.0, "end": 1.0}}
	var w := RunWorld.new(setup) # warns (push_warning); the data validation is what rejects it
	assert_true(w.level_scale != null)
	assert_false(LevelScale.stage_errors(setup.data.stages).is_empty())


# ---- slots follow relocation ----

func test_relocation_keeps_the_captured_multipliers() -> void:
	var w := _world()
	w.time = 50.0
	var slot := _spawn(w)
	var pdd := w.mob_defense(slot, false)
	var moved := w.relocate_mob(slot, Vector2(900, 200), 0)
	assert_true(moved >= 0)
	assert_near(w.mob_defense(moved, false), pdd, 1e-9)
	assert_eq(w.swarm.max_hp[moved], roundi(1000000.0 * _hp(60.0) / _hp(L)))


# ---- determinism and untouched stages ----

## The events of `ticks` steps; every 100th tick the newest live monster is killed so kills, EXP and drops enter the log.
func _run_log(w: RunWorld, ticks: int) -> String:
	var log := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		log.append_array(w.drain_events())
		if tick % 100 == 99:
			for slot in range(w.swarm.capacity() - 1, 0, -1): # slot 0 is the monster in attack range: it stays
				if w.swarm.active[slot] != 0:
					if w.swarm.apply_hit(slot, 1.0e9, 1):
						w._on_kill(slot)
					break
	return str(log)


func _busy_setup(keyframes: Array, p_seed: int) -> Dictionary:
	var setup := _setup(keyframes, p_seed)
	var kf: Dictionary = setup.data.stages.stages.quiet.keyframes[0]
	kf["rate"] = 4.0
	kf["max_alive"] = 12.0
	kf["pool"] = {str(MF.TAURO): 1.0}
	setup.data.balance.player.hp = 10000000 # the monsters hit (no god mode, which blocks the hit events) without a death
	return setup


## A world of _busy_setup with the player at x = 400 and a monster in attack range at x = 600.
func _busy_world(keyframes: Array, p_seed: int, drop_curve := false) -> RunWorld:
	var setup := _busy_setup(keyframes, p_seed)
	if drop_curve:
		setup.data.erase("level_curve")
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	RF.put_mob(w, MF.TAURO, 600)
	return w


func test_same_seed_same_outcome_with_a_scale() -> void:
	var keys := [{"t": 0.0, "level": 40.0, "exp_level": 30.0}, {"t": 20.0, "level": 90.0}]
	var a := _busy_world(keys, 5)
	var log_a := _run_log(a, 900)
	assert_eq(log_a, _run_log(_busy_world(keys, 5), 900))
	assert_true("mob_died" in log_a and "player_hit" in log_a, "the run kills and gets hit")


func test_stage_without_block_is_bit_identical_whatever_the_curve_file_holds() -> void:
	var with_curve := _busy_world([], 5)
	var without_curve := _busy_world([], 5, true)
	var a := _run_log(with_curve, 900)
	assert_true("mob_died" in a and "player_hit" in a, "the run kills and gets hit")
	assert_eq(a, _run_log(without_curve, 900), "the curve file alone changes nothing")
	assert_eq(with_curve.rng.state, without_curve.rng.state)


func test_an_identity_scale_draws_no_rng_and_matches_the_unscaled_event_log() -> void:
	var scaled := _busy_world([{"t": 0.0, "level": float(L)}], 5)
	var plain := _busy_world([], 5)
	assert_eq(_run_log(scaled, 900), _run_log(plain, 900), "E = L everywhere: the same events as without the block")
	for stream: String in ["rng", "spawn_rng", "drop_rng", "meso_rng", "equip_rng", "reward_rng"]:
		assert_eq((scaled.get(stream) as RandomNumberGenerator).state, (plain.get(stream) as RandomNumberGenerator).state,
			"%s state" % stream)


func test_an_invalid_block_warns_and_leaves_the_stage_unscaled() -> void:
	var w := _world([{"t": 5.0, "level": 0.0}])
	assert_true(w.level_scale == null)
	assert_eq(w.warnings.size(), 1)
	var no_curve := _setup()
	no_curve.data.erase("level_curve")
	assert_true(RunWorld.new(no_curve).level_scale == null, "no curve, no scale")


# ---- validation ----

func _stages(stage: Dictionary) -> Dictionary:
	return {"stages": {"x": stage}}


func test_a_stage_with_both_level_scale_and_opening_ramp_is_rejected() -> void:
	var ramp := {"seconds": 60, "hp": {"start": 1.0, "end": 1.0}}
	assert_true(LevelScale.stage_errors(_stages({"level_scale": {"keyframes": KEYS}, "maps": []})).is_empty())
	var stage_level := LevelScale.stage_errors(_stages({"level_scale": {"keyframes": KEYS}, "opening_ramp": ramp}))
	assert_eq(stage_level.size(), 1)
	assert_true("opening_ramp" in stage_level[0])
	var map_level := LevelScale.stage_errors(_stages({"level_scale": {"keyframes": KEYS},
		"maps": [{"map_id": 1, "boss": {}}, {"map_id": 2, "boss": {}, "opening_ramp": ramp}]}))
	assert_eq(map_level.size(), 1)
	assert_true("maps[1]" in map_level[0])
	assert_true(LevelScale.stage_errors(_stages({"opening_ramp": ramp})).is_empty(), "a ramp alone is fine")


func test_the_load_reports_the_conflict_and_the_block_problems() -> void:
	var broken := {"stages": {"x": {"level_scale": {"keyframes": KEYS}, "opening_ramp": {"seconds": 1}}}}
	assert_false(LevelScale.stage_errors(broken).is_empty())
	var bad: Array = [
		{"keyframes": []},
		{"keyframes": [{"t": 0, "level": 0}]},
		{"keyframes": [{"t": 0, "level": 201}]},
		{"keyframes": [{"t": 0, "level": 10, "exp_level": 300}]},
		{"keyframes": [{"t": 10, "level": 10}, {"t": 10, "level": 20}]},
		{"keyframes": [{"t": -1, "level": 10}]},
		{"keyframes": [{"level": 10}]},
		{"keyframes": ["x"]},
		{},
	]
	for block: Dictionary in bad:
		assert_false(LevelScale.stage_errors(_stages({"level_scale": block})).is_empty(), "rejects %s" % str(block))
	assert_true(LevelScale.stage_errors(_stages({"level_scale": {"keyframes": [{"t": 0, "level": 1}, {"t": 1, "level": 200}]}})).is_empty())


func test_curve_errors() -> void:
	assert_true(LevelScale.curve_errors(_curve()).is_empty())
	var short := _curve()
	short.hp.pop_back()
	assert_false(LevelScale.curve_errors(short).is_empty(), "199 entries")
	var falling := _curve()
	falling.pad[50] = 1.0
	assert_false(LevelScale.curve_errors(falling).is_empty(), "not monotone")
	var zero := _curve()
	zero.exp[0] = 0.0
	assert_false(LevelScale.curve_errors(zero).is_empty(), "a zero entry")
	assert_false(LevelScale.curve_errors({}).is_empty())


# ---- the committed reference curves ----

func test_level_curve_file_has_200_monotone_positive_entries_per_stat() -> void:
	var curve: Variant = DataRepo.load_json(DataRepo.DATA_ROOT.path_join(DataRepo.FILES.level_curve))
	assert_true(curve is Dictionary, "level_curve.json parses")
	if not curve is Dictionary:
		return
	for stat: String in LevelScale.STATS:
		assert_eq(curve[stat].size(), 200, stat)
		for i in 200:
			assert_true(float(curve[stat][i]) > 0.0, "%s[%d] positive" % [stat, i])
			if i > 0:
				assert_true(float(curve[stat][i]) >= float(curve[stat][i - 1]), "%s monotone at level %d" % [stat, i + 1])
	assert_true(LevelScale.curve_errors(curve).is_empty())
	var doc: Dictionary = curve._doc
	for field: String in ["method", "date", "samples", "source", "generator"]:
		assert_has(doc, field)
	assert_eq(doc.samples.per_level.size(), 200)
	assert_true(int(doc.samples.ordinary_samples) > 200, "the curve rests on real samples")
	assert_true(DataRepo.load_all().level_curve.hp.size() == 200, "setup.data carries the curve")


func test_shipped_data_validates_and_no_shipped_stage_uses_the_block_yet() -> void:
	var errors := PackedStringArray()
	var data := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_eq(errors, PackedStringArray(), "the shipped data loads without errors")
	for key: String in data.stages.stages:
		var original: bool = data.stages.progression.find(key) in range(5) # the first five predate the scale (#453); a new region has one
		assert_eq(data.stages.stages[key].has("level_scale"), not original, "%s: level_scale exactly for the regions of #449" % key)
