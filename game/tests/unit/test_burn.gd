extends TestCase
## The burn status (spec #332 B5, M5): a fire damage-over-time beside poison whose pulse comes from the cast that applied
## it. Synthetic skill tables and mobs, seeded worlds, fixed 1/60 s ticks; no test needs the asset cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const AF := preload("res://tests/fixtures/asset_fixtures.gd")
const DT := 1.0 / 60.0
const BURN_HIT := {"status": "burn", "duration_field": "time", "pulse_field": "x"}


func _ctx(w: RunWorld) -> Dictionary:
	return {"fhm": w.fhm, "target": w.player.pos, "target_fh": w.player.fh, "bounds": w.bounds,
		"events": w.events}


## A quiet world with one motionless, fully faded-in 4000 HP mob; returns [world, slot].
func _target(hp_mult := 16.0) -> Array:
	var w := RF.quiet_world()
	w.god = true
	var m := RF.put_mob(w, 1110100, 700, 190, hp_mult)
	w.swarm.mob_kind(m).move_speed = 0.0
	w.swarm.alpha[m] = 1.0
	w.drain_events()
	return [w, m]


func _run(w: RunWorld, ticks: int) -> void:
	var ctx := _ctx(w)
	for tick in ticks:
		w.swarm.step(DT, ctx)


func _burn(w: RunWorld, m: int, pulse: int, time: float, skill := "inferno") -> bool:
	return w.swarm.apply_status(m, "burn", {"pulse": pulse, "time": time, "skill": skill}, w.events)


func _hits(w: RunWorld) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func test_burn_is_appended_after_ice_weak_and_the_tables_match() -> void:
	assert_eq(MobSwarm.ICE_WEAK, 5, "never renumber an existing status")
	assert_eq(MobSwarm.BURN, 6)
	assert_eq(MobSwarm.STATUS_COUNT, 7)
	assert_eq(MobSwarm.STATUS_NAMES[MobSwarm.BURN], "burn")
	assert_eq(MobSwarm.STATUS_NAMES[MobSwarm.ICE_WEAK], "ice_weak")
	assert_eq(MobSwarm.STATUS_ELEMENTS[MobSwarm.BURN], "F")
	assert_eq(MobSwarm.STATUS_NAMES.size(), MobSwarm.STATUS_COUNT)
	assert_eq(MobSwarm.STATUS_ELEMENTS.size(), MobSwarm.STATUS_COUNT)


func test_pulse_arithmetic_is_the_rounded_mean_share_times_the_burn_multiplier() -> void:
	assert_eq(BurnStatus.pulse(100.0, 200.0, 50.0, 1.0), 75)
	assert_eq(BurnStatus.pulse(100.0, 200.0, 50.0, 1.5), 113, "112.5 rounds up")
	assert_eq(BurnStatus.pulse(80.0, 80.0, 24.0, 1.0), 19, "19.2")
	assert_eq(BurnStatus.pulse(100.0, 100.0, 0.0, 1.0), 0, "no share, no burn")
	assert_eq(BurnStatus.pulse(100.0, 100.0, 50.0, -2.0), 0, "never negative")
	assert_eq(BurnStatus.tick_damage(10, 4000), 10)
	assert_eq(BurnStatus.tick_damage(10, 5), 4, "leaves 1 HP")
	assert_eq(BurnStatus.tick_damage(10, 1), 0)
	assert_eq(BurnStatus.tick_damage(10, 0), 0)


func test_burn_pulses_every_second_for_its_time_and_the_last_pulse_is_due_at_expiry() -> void:
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	assert_true(_burn(w, m, 10, 3.0))
	_run(w, 59)
	assert_eq(w.swarm.hp[m], 4000, "no immediate pulse")
	_run(w, 1)
	assert_eq(w.swarm.hp[m], 3990)
	_run(w, 60)
	assert_eq(w.swarm.hp[m], 3980)
	_run(w, 60)
	assert_eq(w.swarm.hp[m], 3970, "the pulse due at expiry still lands")
	assert_near(w.swarm.status_time(m, MobSwarm.BURN), 0.0)
	_run(w, 120)
	assert_eq(w.swarm.hp[m], 3970, "nothing after the status ends")
	assert_false(w.swarm.has_statuses())
	var types := w.events.filter(func(e: Dictionary) -> bool: return String(e.type).begins_with("mob_status"))
	assert_eq(types.map(func(e: Dictionary) -> String: return "%s:%s" % [e.type, e.status]),
		["mob_status_applied:burn", "mob_status_expired:burn"])
	assert_near(float(types[0].duration), 3.0)


func test_burn_pulses_are_mob_hit_events_with_the_skill_key_and_count_as_player_damage() -> void:
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	assert_true(_burn(w, m, 25, 2.0, "inferno"))
	_run(w, 120)
	var hits := _hits(w)
	assert_eq(hits.size(), 2)
	for h: Dictionary in hits:
		assert_eq(h.skill, "inferno")
		assert_eq(h.damage, 25)
		assert_eq(h.mob, m)
		assert_false(bool(h.crit))
		assert_eq(h.hit_visual, "")
	assert_eq(w.swarm.burn_dealt, 50)
	assert_eq(w.swarm.poison_dealt, 0, "poison keeps its own counter")
	assert_eq(w.damage_dealt, 50, "burn is part of the player's damage total")


func test_burn_never_kills_and_never_stuns_or_pushes() -> void:
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	var start := w.swarm.pos(m)
	w.swarm.hp[m] = 5
	assert_true(_burn(w, m, 10, 4.0))
	_run(w, 60)
	assert_eq(w.swarm.hp[m], 1, "the pulse is cut to leave 1 HP")
	assert_ne(w.swarm.state[m], MobSwarm.HIT, "no flinch")
	assert_eq(w.swarm.pos(m), start, "no push")
	assert_true(w.swarm.can_act(m))
	_run(w, 180)
	assert_eq(w.swarm.hp[m], 1)
	assert_true(w.swarm.is_live(m))
	assert_eq(_hits(w).size(), 1, "a pulse that would deal 0 emits nothing")
	assert_eq(w.swarm.burn_dealt, 4, "only the actual damage is credited")
	assert_eq(w.damage_dealt, 4)
	assert_eq(w.kills, 0)


func test_a_refresh_replaces_the_timer_and_pulse_size_without_resetting_the_running_pulse() -> void:
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	assert_true(_burn(w, m, 10, 2.0))
	_run(w, 30)
	assert_true(_burn(w, m, 20, 3.0), "a refresh is accepted")
	assert_near(w.swarm.status_time(m, MobSwarm.BURN), 3.0, 1e-6, "the timer is the new time, not added")
	_run(w, 29)
	assert_eq(w.swarm.hp[m], 4000)
	_run(w, 1)
	assert_eq(w.swarm.hp[m], 3980, "the pulse still lands one second after the FIRST application, now 20 strong")
	_run(w, 60)
	assert_eq(w.swarm.hp[m], 3960, "one pulse a second, never two (no stacking)")
	_run(w, 60)
	assert_eq(w.swarm.hp[m], 3940)
	_run(w, 60)
	assert_eq(w.swarm.hp[m], 3940, "3 s from the refresh at 0.5 s ends at 3.5 s")
	assert_eq(_hits(w).size(), 3)
	assert_eq(w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied").size(), 2)


func test_two_offset_sources_keep_one_pulse_a_second() -> void:
	# Review #282 C1 (Poison Mist): refreshing must not restart a running pulse. Two sources alternate every 0.5 s with a
	# 2 s burn; a refresh that reset the clock would starve the status of every pulse.
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	var sources := [["inferno", 10], ["phoenix", 14]]
	for half in 12:
		var source: Array = sources[half % 2]
		assert_true(_burn(w, m, int(source[1]), 2.0, String(source[0])))
		_run(w, 30)
	var hits := _hits(w)
	assert_eq(hits.size(), 6, "six seconds, six pulses")
	assert_eq(w.swarm.hp[m], 4000 - 6 * 14)
	for k in hits.size():
		assert_eq(hits[k].damage, 14, "each pulse is the latest snapshot (the 0.5 s source, applied before it)")
		assert_eq(hits[k].skill, "phoenix")
	assert_eq(w.damage_dealt, 6 * 14)
	_run(w, 180)
	assert_eq(_hits(w).size(), 7, "the last refresh (5.5 s) runs to 7.5 s: one more pulse at 7.0 s, then none")
	assert_false(w.swarm.has_statuses())


func test_a_fresh_burn_after_expiry_restarts_the_clock() -> void:
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	assert_true(_burn(w, m, 10, 1.5))
	_run(w, 90)
	assert_eq(w.swarm.hp[m], 3990)
	assert_false(w.swarm.has_statuses())
	_run(w, 20)
	assert_true(_burn(w, m, 10, 2.0))
	_run(w, 59)
	assert_eq(w.swarm.hp[m], 3990, "a new burn waits a full second for its first pulse")
	_run(w, 1)
	assert_eq(w.swarm.hp[m], 3980)


func test_a_burn_needs_a_pulse_and_a_time() -> void:
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	assert_false(_burn(w, m, 0, 3.0), "no pulse, nothing to apply")
	assert_false(_burn(w, m, 10, 0.0))
	assert_false(w.swarm.apply_status(m, "burn", {"time": 3.0}, w.events))
	assert_true(w.events.is_empty())
	assert_false(w.swarm.has_statuses())


func test_bosses_and_fire_immune_strong_or_neutral_kinds_reject_burn() -> void:
	for scheduled: bool in [false, true]:
		var w := RF.quiet_world()
		var boss := RF.put_mob(w, 1110100 if scheduled else 2220000, 700)
		w.swarm.steady[boss] = 1 if scheduled else 0
		w.drain_events()
		assert_false(w.swarm.accepts_status(boss, "burn"))
		assert_false(_burn(w, boss, 10, 3.0), "%s boss" % ("scheduled" if scheduled else "canonical"))
		assert_true(w.events.is_empty())
	for digit in ["1", "2", "3", "4"]:
		var w := RF.quiet_world()
		var img := RF.mob_img(1110100)
		img.info["elemAttr"] = "F" + digit
		w.mob_kinds[0] = MobKind.from_wz(img, 1110100)
		var m := w.spawn_mob(0, w.player.pos + Vector2(200, 0), w.player.fh, 1.0, false)
		w.drain_events()
		var expected: bool = digit == "3"
		assert_eq(_burn(w, m, 10, 3.0), expected, "F%s: immune, strong and neutral reject; weak (3) burns" % digit)
		assert_eq(w.swarm.accepts_status(m, "burn"), expected)


func test_burn_coexists_with_poison_and_each_keeps_its_own_clock_and_credit() -> void:
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	assert_true(w.swarm.apply_status(m, "poison", {"level": 30, "time": 2.0, "skill": "poison_breath"}, w.events))
	_run(w, 30)
	assert_true(_burn(w, m, 7, 3.0))
	_run(w, 30)
	assert_eq(w.swarm.hp[m], 3900, "poison's pulse at 1.0 s, unchanged by the burn (maxHP / (70 - 30) = 100)")
	_run(w, 30)
	assert_eq(w.swarm.hp[m], 3893, "burn's pulse a second after ITS application")
	_run(w, 30)
	assert_eq(w.swarm.hp[m], 3793)
	assert_near(w.swarm.status_time(m, MobSwarm.POISON), 0.0)
	assert_true(w.swarm.status_time(m, MobSwarm.BURN) > 0.0, "the burn outlives the poison")
	_run(w, 60)
	assert_eq(w.swarm.hp[m], 3786)
	assert_eq(w.swarm.poison_dealt, 200)
	assert_eq(w.swarm.burn_dealt, 14)
	assert_eq(w.damage_dealt, 214, "the credit is the sum of both")
	var skills := _hits(w).map(func(e: Dictionary) -> String: return String(e.skill))
	assert_has(skills, "poison_breath")
	assert_has(skills, "inferno")


func test_burn_clears_silently_on_death_release_and_relocation() -> void:
	for removal: String in ["death", "release", "relocate"]:
		var w := RF.quiet_world()
		var m := RF.put_mob(w, 1110100, 700)
		w.drain_events()
		assert_true(_burn(w, m, 10, 20.0))
		if removal == "death":
			w.swarm.apply_hit(m, 99999, 1)
		elif removal == "release":
			w.swarm.despawn(m)
			m = w.swarm.spawn(w.swarm.kind[m], 700, w.player.pos.y, w.player.fh)
		else:
			m = w.relocate_mob(m, Vector2(750, w.player.pos.y), w.player.fh)
		assert_near(w.swarm.status_time(m, MobSwarm.BURN), 0.0, 1e-9, removal)
		assert_false(w.swarm.has_statuses(), "%s empties the status list" % removal)
		var fresh := w.swarm.hp[m]
		if removal != "death":
			var ctx := _ctx(w)
			for tick in 90:
				w.swarm.step(DT, ctx)
			assert_eq(w.swarm.hp[m], fresh, "%s leaves no pulse behind" % removal)
		assert_eq(_hits(w).size(), 0, removal)


func test_map_transfer_clears_burning_monsters() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(RF.setup("quiet", 337, data))
	RF.place_player(w, 400)
	var m := RF.put_mob(w, 1110100, 700)
	w.drain_events()
	assert_true(_burn(w, m, 10, 20.0))
	w.transfer_pending = true
	w.advance_map()
	assert_false(w.swarm.has_statuses(), "the transfer sweeps every mob and its statuses")
	assert_eq(w.swarm.burn_dealt, 0)


# --- the cast: Loadout.stats resolves burn_pulse, and the pulse travels with the shot --------------------------------

func _burn_world(extra := {}) -> RunWorld:
	var def := {"kind": "instant", "damage": "fixed", "on_hit": BURN_HIT}
	def.merge(extra, true)
	return CF.world(def)


func test_loadout_resolves_the_pulse_from_the_casts_bounds_x_and_burn_damage() -> void:
	var w := _burn_world()
	var st := w.loadout.stats("synthetic")
	# fixed damage 100 (rank 1), x 72, no modifiers.
	assert_eq(int(st.burn_pulse), 72)
	assert_near(float(st.burn_time), 3.0)
	assert_near(float(st.burn_share), 72.0, 1e-6, "percent of base damage per second")
	w.loadout.set_rank("synthetic", 2)
	st = w.loadout.stats("synthetic")
	assert_eq(int(st.burn_pulse), 130, "rank 2: x 130")
	assert_near(float(st.burn_time), 4.0)
	w.loadout.add_skill_mod("synthetic", "damage", "mul", 2.0)
	assert_eq(int(w.loadout.stats("synthetic").burn_pulse), 260, "a damage modifier scales the bounds, so the burn")
	w.loadout.add_skill_mod("synthetic", "burn_damage", "mul", 1.5)
	var boosted := w.loadout.stats("synthetic")
	assert_eq(int(boosted.burn_pulse), 390, "burn_damage x1.5 on top")
	assert_near(float(boosted.burn_share), 195.0, 1e-6)
	var plain := _burn_world().loadout
	plain.add_player_mod("damage", "mul", 2.0)
	assert_eq(int(plain.stats("synthetic").burn_pulse), 144, "a player-wide damage multiplier scales it too")


func test_a_physical_burn_follows_the_resolved_physical_bounds_before_skill_percent() -> void:
	var w := _burn_world({"damage": "physical"})
	var st := w.loadout.stats("synthetic")
	var mean := (float(st.damage_min) + float(st.damage_max)) * 0.5
	assert_true(mean > 0.0, "fixture: the character has a physical range")
	assert_eq(int(st.burn_pulse), roundi(mean * 72.0 / 100.0))
	assert_near(float(st.damage_pct), 1.0, 1e-6, "the skill percent is not part of the burn")


func test_skills_without_a_burn_resolve_no_burn_keys() -> void:
	var st := CF.world().loadout.stats("synthetic")
	for key: String in ["burn_pulse", "burn_time", "burn_share"]:
		assert_false(st.has(key), key)
	var other := _burn_world({"on_hit": {"status": "stun", "chance_field": "prop", "duration_field": "time"}})
	assert_false(other.loadout.stats("synthetic").has("burn_pulse"))


func test_an_instant_hit_applies_burn_always_with_the_levels_time_and_pulse_and_draws_no_rng() -> void:
	var w := _burn_world()
	var twin := CF.world({"on_hit": {}})
	var m := RF.put_mob(w, 1110100, 350, 190, 100)
	var t := RF.put_mob(twin, 1110100, 350, 190, 100)
	w.hit_mob(m, w.loadout.stats("synthetic"), -1)
	twin.hit_mob(t, twin.loadout.stats("synthetic"), -1)
	assert_near(w.swarm.status_time(m, MobSwarm.BURN), 3.0)
	assert_eq(w.rng.state, twin.rng.state, "no chance field: the application draws nothing")
	assert_near(twin.swarm.status_time(t, MobSwarm.BURN), 0.0)
	for tick in 200:
		w.step(DT, MoveInput.new())
		twin.step(DT, MoveInput.new())
	assert_eq(w.swarm.burn_dealt, 3 * 72, "three pulses of the snapshot")
	assert_eq(w.rng.state, twin.rng.state, "pulses draw nothing either")
	assert_eq(w.swarm.hp[m], twin.swarm.hp[t] - 3 * 72, "the same casts hit both worlds; only the burn differs")
	var pulses := _hits(w).filter(func(e: Dictionary) -> bool: return e.skill == "synthetic" and e.hit_visual == "" \
		and e.damage == 72)
	assert_eq(pulses.size(), 3)


func test_burn_ignores_monster_defence() -> void:
	var damages := []
	for pdd in [0, 400]:
		var w := _burn_world({"damage": "physical"})
		var m := RF.put_mob(w, 1110100, 350, 190, 100)
		w.mob_kinds[w.swarm.kind[m]].pdd = pdd
		var expected := int(w.loadout.stats("synthetic").burn_pulse)
		w.hit_mob(m, w.loadout.stats("synthetic"), -1)
		for tick in 70:
			w.step(DT, MoveInput.new())
		var pulse := _hits(w).filter(func(e: Dictionary) -> bool: return e.hit_visual == "" and e.damage == expected)
		assert_eq(pulse.size(), 1, "pdd %d: the pulse is the snapshot" % pdd)
		damages.append(expected)
	assert_eq(damages[0], damages[1])


func test_a_projectile_blast_carries_the_cast_pulse_and_a_later_rank_change_does_not_alter_it() -> void:
	var w := _burn_world({"kind": "projectile", "radius": 1, "impact_blast": {"visual": "hit"}})
	var primary := RF.put_mob(w, 1110100, 350, 190, 100)
	var splash := RF.put_mob(w, 1110100, 390, 190, 100)
	for m: int in [primary, splash]:
		w.mob_kinds[w.swarm.kind[m]].move_speed = 0
	w.step(DT, MoveInput.new()) # launch at rank 1
	w.loadout.set_rank("synthetic", 2)
	for tick in 25:
		w.step(DT, MoveInput.new())
	for m: int in [primary, splash]:
		assert_true(w.swarm.status_time(m, MobSwarm.BURN) > 2.0, "every blast target burns")
	var hp := [w.swarm.hp[primary], w.swarm.hp[splash]]
	for tick in 62:
		w.step(DT, MoveInput.new())
	assert_eq(hp[0] - w.swarm.hp[primary], 72, "the rank-1 pulse travelled with the shot")
	assert_eq(hp[1] - w.swarm.hp[splash], 72)


func test_a_plain_projectile_hit_and_pooled_shots_do_not_inherit_a_previous_pulse() -> void:
	var w := _burn_world({"kind": "projectile", "radius": 1})
	var first := w.projectiles.spawn({"burn_pulse": 55, "x": 0, "y": 0})
	w.projectiles.despawn(first)
	var fresh := w.projectiles.spawn({"x": 0, "y": 0})
	assert_eq(fresh, first, "fixture: reused shot slot")
	assert_eq(w.projectiles.burn_pulse[fresh], 0)


# --- presentation -------------------------------------------------------------------------------------------------

func test_the_renderer_has_a_fifth_cue_and_an_orange_fallback_tint() -> void:
	assert_eq(MobRenderer.BURN_CUE, 4)
	assert_eq(MobRenderer.CUES_PER_SLOT, 5)
	assert_eq(MobRenderer.STUN_CUE, 3, "existing cue indices are unchanged")
	var c := MobRenderer.BURN_TINT
	assert_true(c.r > c.g and c.g > c.b, "orange: red over green over blue")


func _renderer(lib: AssetLibrary, root: Node) -> MobRenderer:
	var r := MobRenderer.new()
	r.library = lib
	root.add_child(r)
	return r


func _burning_world() -> Array:
	var pair := _target()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	w.swarm.state[m] = MobSwarm.STAND
	assert_true(_burn(w, m, 10, 5.0))
	return pair


func _kind_ids(w: RunWorld) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for k in w.mob_kinds.size():
		ids.append(100100)
	return ids


func test_a_burning_mob_without_configured_art_takes_the_orange_tint() -> void:
	var lib := AssetLibrary.new()
	lib.open(AF.write_cache())
	var root := Node2D.new()
	var pair := _burning_world()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	var r := _renderer(lib, root)
	r.update_from(w.swarm, _kind_ids(w))
	assert_eq(r._pool.tint_of(m), MobRenderer.BURN_TINT)
	assert_false(r._status_pool.is_shown(m * MobRenderer.CUES_PER_SLOT + MobRenderer.BURN_CUE), "no art, no cue sprite")
	w.swarm.status_left[m * MobSwarm.STATUS_COUNT + MobSwarm.BURN] = 0.0
	r.update_from(w.swarm, _kind_ids(w))
	assert_eq(r._pool.tint_of(m), Color.WHITE, "the tint ends with the status")
	root.free()
	lib.free()


func test_a_configured_cue_is_drawn_repeating_and_replaces_the_tint() -> void:
	var lib := AssetLibrary.new()
	lib.open(AF.write_cache())
	var root := Node2D.new()
	var pair := _burning_world()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	var r := _renderer(lib, root)
	r.burn_cue_path = "Mob.wz/0100100.img/stand"
	r.update_from(w.swarm, _kind_ids(w))
	var slot := m * MobRenderer.CUES_PER_SLOT + MobRenderer.BURN_CUE
	assert_true(r._status_pool.is_shown(slot), "the configured art is drawn on the burning monster")
	assert_eq(r._pool.tint_of(m), Color.WHITE, "art configured: no fallback tint")
	# Repeats while the status lasts: far past the animation's length it is still shown.
	w.swarm.status_elapsed[m * MobSwarm.STATUS_COUNT + MobSwarm.BURN] = 50.0
	r.update_from(w.swarm, _kind_ids(w))
	assert_true(r._status_pool.is_shown(slot))
	w.swarm.status_left[m * MobSwarm.STATUS_COUNT + MobSwarm.BURN] = 0.0
	r.update_from(w.swarm, _kind_ids(w))
	assert_false(r._status_pool.is_shown(slot), "hidden when the burn ends")
	root.free()
	lib.free()


func test_burning_poisoned_and_frozen_keep_the_existing_tint_order() -> void:
	var lib := AssetLibrary.new()
	lib.open(AF.write_cache())
	var root := Node2D.new()
	var pair := _burning_world()
	var w: RunWorld = pair[0]
	var m: int = pair[1]
	assert_true(w.swarm.apply_status(m, "poison", {"level": 30, "time": 5.0}, w.events))
	var r := _renderer(lib, root)
	r.update_from(w.swarm, _kind_ids(w))
	assert_eq(r._pool.tint_of(m), MobRenderer.BURN_TINT, "burn over poison (both are damage over time; the fire reads first)")
	assert_true(w.swarm.apply_status(m, "freeze", {"time": 3.0}, w.events))
	r.update_from(w.swarm, _kind_ids(w))
	assert_eq(r._pool.tint_of(m), MobRenderer.FREEZE_TINT, "freeze still wins")
	root.free()
	lib.free()


func test_skill_text_states_the_burn_time_and_share() -> void:
	var w := _burn_world()
	var text := SkillText.new(w.book)
	var line := text.level_line("synthetic", 1, w.loadout.stats("synthetic"))
	assert_eq(line, "Burns for 3 s, 72% of base damage per second")
	w.loadout.add_skill_mod("synthetic", "burn_damage", "mul", 1.5)
	line = text.level_line("synthetic", 1, w.loadout.stats("synthetic"))
	assert_eq(line, "Burns for 3 s, 108% of base damage per second", "the burn_damage modifier shows in the share")
	var plain := CF.world()
	assert_false(SkillText.new(plain.book).level_line("synthetic", 1, plain.loadout.stats("synthetic")).contains("Burns"))


func test_a_burn_damage_card_previews_the_percent_before_and_after() -> void:
	var w := _burn_world()
	var changes := UpgradePool._bonus_changes({"skill": "synthetic",
		"effects": [{"stat": "burn_damage", "op": "mul", "value": 1.5}]}, w.loadout, 1)
	assert_eq(changes.keys(), ["burn_damage"])
	assert_eq(changes.burn_damage, {"before": 100, "after": 150})
	var lines := LevelUpWindow.change_lines({"skill_mod_changes": changes})
	assert_eq(Array(lines), ["Burn: 100% → 150%"])
