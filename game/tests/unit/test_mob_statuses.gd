extends TestCase
## Seeded fixed-tick status and elemental hit contracts from issue #54; synthetic WZ-shaped inputs only.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_canonical_elements_and_undead_are_queryable() -> void:
	var img := RF.mob_img(1110100)
	img.info["elemAttr"] = "I2F3L1H2"
	img.info["undead"] = 1.0
	var kind := MobKind.from_wz(img, 1110100)
	assert_true(kind.undead)
	assert_near(kind.element_multiplier("f"), 1.5)
	assert_near(kind.element_multiplier("I"), 0.5)
	assert_near(kind.element_multiplier("l"), 0.0)
	assert_near(kind.element_multiplier(""), 1.0)
	assert_near(kind.element_multiplier("s"), 1.0, 1e-6, "unlisted element is neutral")


func test_elements_resolve_on_instant_and_projectile_impact_and_numbers() -> void:
	for attr: String in ["F3", "F2", "F1", ""]:
		for projectile: bool in [false, true]:
			var w := RF.quiet_world()
			var img := RF.mob_img(1110100)
			img.info["elemAttr"] = attr
			var kind := MobKind.from_wz(img, 1110100)
			kind.move_speed = 0.0
			w.mob_kinds[0] = kind
			var m := w.spawn_mob(0, w.player.pos + Vector2(80, 0), w.player.fh, 1.0, false)
			var initial := w.swarm.hp[m]
			w.drain_events()
			var expected := {"F3": 30, "F2": 10, "F1": 0, "": 20}
			if projectile:
				w.projectiles.spawn({"x": w.swarm.x[m], "y": w.swarm.y[m] - 10,
					"range": 100.0, "dmg_min": 20.0, "dmg_max": 20.0, "element": "f", "skill": "test"})
				w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
				w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
			else:
				w.hit_mob(m, {"damage_min": 20.0, "damage_max": 20.0, "magic": false,
					"crit": 0.0, "crit_mult": 1.5, "element": "f", "skill": "test"}, -1)
			assert_eq(w.swarm.hp[m], initial - int(expected[attr]), "%s projectile=%s" % [attr, projectile])
			assert_eq(w.events.size(), 1)
			if not w.events.is_empty():
				assert_eq(w.events[0].damage, int(expected[attr]), "number matches damage, including immune zero")
			if attr == "F1":
				assert_ne(w.swarm.state[m], MobSwarm.HIT, "immune hit cannot flinch")
			w.hit_mob(m, {"damage_min": 20.0, "damage_max": 20.0, "magic": false,
				"crit": 0.0, "crit_mult": 1.5, "skill": "neutral"}, -1)
			assert_eq(w.swarm.hp[m], initial - int(expected[attr]) - 20, "elementless damage unchanged")


func test_loadout_reads_the_canonical_skill_element() -> void:
	var w := RF.quiet_world()
	assert_eq(w.loadout.stats("fire_arrow").element, "f")
	assert_eq(w.loadout.stats("three_snails").element, "")


func _ctx(w: RunWorld) -> Dictionary:
	return {"fhm": w.fhm, "target": w.player.pos, "target_fh": w.player.fh, "bounds": w.bounds,
		"events": w.events}


func test_slow_uses_signed_canonical_x_and_refreshes_without_stacking() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 100100, 700)
	w.swarm.alpha[m] = 1.0
	var ctx := _ctx(w)
	var start := w.swarm.x[m]
	assert_true(w.swarm.apply_status(m, "slow", {"x": -40.0, "time": 1.0}, w.events))
	for tick in 30:
		w.swarm.step(DT, ctx)
	assert_near(start - w.swarm.x[m], 6.5625, 0.002, "half a second at 60% of 21.875 px/s")
	assert_true(w.swarm.apply_status(m, "slow", {"x": -40.0, "time": 1.0}, w.events))
	start = w.swarm.x[m]
	for tick in 59:
		w.swarm.step(DT, ctx)
	assert_true(w.swarm.status_time(m, MobSwarm.SLOW) > 0.0, "still slowed one tick before refreshed expiry")
	w.swarm.step(DT, ctx)
	assert_near(start - w.swarm.x[m], 13.125, 0.002, "refresh does not stack")
	assert_near(w.swarm.status_time(m, MobSwarm.SLOW), 0.0)
	start = w.swarm.x[m]
	w.swarm.step(DT, ctx)
	assert_near(start - w.swarm.x[m], 21.875 / 60.0, 0.0001, "normal speed on next tick")
	var status_events := w.events.filter(func(e: Dictionary) -> bool: return String(e.type).begins_with("mob_status"))
	assert_eq(status_events.size(), 3, "two applications, one expiry")
	assert_eq(status_events[-1].type, "mob_status_expired")
	assert_false(w.swarm.has_statuses(), "the last expiry empties the status list")


func test_poison_pulses_through_expiry_stops_at_one_hp_and_credits_player_damage() -> void:
	var w := RF.quiet_world()
	w.loadout.order.clear()
	w.god = true
	var m := RF.put_mob(w, 1110100, 700, 190, 16.0)
	w.swarm.mob_kind(m).move_speed = 0.0
	w.drain_events()
	assert_true(w.swarm.apply_status(m, "poison", {"level": 30, "time": 2.0, "skill": "poison_breath"}, w.events))
	for tick in 59:
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.hp[m], 4000, "no immediate pulse")
	w.step(DT, MoveInput.new())
	assert_eq(w.swarm.hp[m], 3900, "maxHP / (70 - skill level) per second")
	assert_eq(w.damage_dealt, 100, "poison contributes to the player's damage total")
	for tick in 60:
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.hp[m], 3800, "final pulse is due at expiry")
	assert_eq(w.damage_dealt, 200)
	assert_near(w.swarm.status_time(m, MobSwarm.POISON), 0.0)
	w.swarm.hp[m] = 5
	assert_true(w.swarm.apply_status(m, "poison", {"level": 30, "time": 2.0}, w.events))
	for tick in 120:
		w.step(DT, MoveInput.new())
	assert_eq(w.swarm.hp[m], 1, "poison cannot kill")
	assert_true(w.swarm.is_live(m))
	assert_eq(w.damage_dealt, 204, "only actual nonlethal poison damage is credited")
	w.hit_mob(m, {"damage_min": 1.0, "damage_max": 1.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "finisher"}, -1)
	assert_eq(w.kills, 1, "ordinary final hit retains kill credit")
	assert_eq(w.pickups.exp_count(), 1, "poisoned monster still drops EXP")


func test_poison_rounding_cap_and_refresh() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	var ctx := _ctx(w)
	assert_true(w.swarm.apply_status(m, "poison", {"level": 1, "time": 1.5}, w.events))
	for tick in 60:
		w.swarm.step(DT, ctx)
	assert_eq(w.swarm.hp[m], 246, "ceil(250 / 69) = 4")
	assert_true(w.swarm.apply_status(m, "poison", {"level": 1, "time": 1.0}, w.events))
	for tick in 60:
		w.swarm.step(DT, ctx)
	assert_eq(w.swarm.hp[m], 242, "one refreshed poison, no stacking")
	w.swarm.max_hp[m] = 4000000
	w.swarm.hp[m] = 4000000
	assert_true(w.swarm.apply_status(m, "poison", {"level": 30, "time": 1.0}, w.events))
	for tick in 60:
		w.swarm.step(DT, ctx)
	assert_eq(w.swarm.hp[m], 3967233, "per-pulse cap is 32767")


func test_freeze_holds_motion_animation_and_action_gate_for_exact_duration() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	w.swarm.alpha[m] = 1.0
	var ctx := _ctx(w)
	w.swarm.step(DT, ctx)
	var start := w.swarm.pos(m)
	var anim_time := w.swarm.anim_t[m]
	var state_time := w.swarm.state_t[m]
	assert_true(w.swarm.apply_status(m, "freeze", {"time": 1.0}, w.events))
	assert_false(w.swarm.can_act(m), "frozen mobs cannot start attacks or skills")
	w.swarm.apply_hit(m, 1, 1)
	for tick in 59:
		w.swarm.step(DT, ctx)
	assert_true(w.swarm.status_time(m, MobSwarm.FREEZE) > 0.0)
	w.swarm.step(DT, ctx)
	assert_eq(w.swarm.pos(m), start)
	assert_eq(w.swarm.anim_t[m], anim_time, "even hits cannot restart frozen art")
	assert_eq(w.swarm.state_t[m], state_time)
	assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 0.0)
	assert_true(w.swarm.can_act(m))
	w.swarm.step(DT, ctx)
	assert_true(w.swarm.x[m] < start.x, "movement resumes the next tick")
	assert_true(w.swarm.anim_t[m] > anim_time)


func test_canonical_and_scheduled_bosses_reject_every_status() -> void:
	for scheduled: bool in [false, true]:
		var w := RF.quiet_world()
		var m := RF.put_mob(w, 1110100 if scheduled else 2220000, 700)
		w.swarm.steady[m] = 1 if scheduled else 0
		w.drain_events()
		for status: String in MobSwarm.STATUS_NAMES:
			assert_false(w.swarm.apply_status(m, status, {"level": 30, "x": -40, "time": 2}, w.events),
				"%s on a %s boss (v83 server reference)" % [status, "scheduled" if scheduled else "canonical"])
		assert_true(w.events.is_empty(), "a rejected status emits nothing")
		assert_false(w.swarm.has_statuses())


func test_statuses_fail_on_immune_strong_or_neutral_elements() -> void:
	var w := RF.quiet_world()
	var img := RF.mob_img(1110100)
	img.info["elemAttr"] = "S1I2F3L4"
	w.mob_kinds[0] = MobKind.from_wz(img, 1110100)
	var m := w.spawn_mob(0, w.player.pos + Vector2(200, 0), w.player.fh, 1.0, false)
	w.drain_events()
	assert_false(w.swarm.apply_status(m, "poison", {"level": 30, "time": 2}, w.events), "poison-immune S1")
	assert_false(w.swarm.apply_status(m, "freeze", {"time": 2}, w.events), "ice-strong I2")
	assert_true(w.events.is_empty(), "rejections emit nothing")
	assert_true(w.swarm.apply_status(m, "slow", {"x": -40, "time": 2}, w.events), "Slow has no element")
	assert_true(w.swarm.apply_status(m, "freeze", {"time": 2, "element": "f"}, w.events),
		"an applying skill's own element overrides the status default: fire-weak F3 takes it")
	assert_false(w.swarm.apply_status(m, "slow", {"x": -40, "time": 2, "element": "s"}, w.events),
		"an elemental Slow follows its element too")
	assert_false(w.swarm.apply_status(m, "slow", {"x": -40, "time": 2, "element": "l"}, w.events),
		"digit 4 (neutral) also rejects a status, as in the v83 server reference")
	assert_near(w.mob_kinds[0].element_multiplier("l"), 1.0, 1e-6, "but digit 4 hits stay neutral")


func test_statuses_clear_on_death_release_reuse_and_relocation() -> void:
	for removal: String in ["death", "release", "relocate"]:
		var w := RF.quiet_world()
		var m := RF.put_mob(w, 1110100, 700)
		for status: String in ["slow", "poison", "freeze"]:
			assert_true(w.swarm.apply_status(m, status, {"level": 30, "x": -40, "time": 20}, w.events))
		if removal == "death":
			w.swarm.apply_hit(m, 99999, 1)
		elif removal == "release":
			w.swarm.despawn(m)
			m = w.swarm.spawn(w.swarm.kind[m], 700, w.player.pos.y, w.player.fh)
		else:
			m = w.relocate_mob(m, Vector2(750, w.player.pos.y), w.player.fh)
		assert_near(w.swarm.status_time(m, MobSwarm.SLOW), 0.0, 1e-9, removal)
		assert_near(w.swarm.status_time(m, MobSwarm.POISON), 0.0, 1e-9, removal)
		assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 0.0, 1e-9, removal)
		assert_near(w.swarm.slow_factor[m], 1.0)
		assert_false(w.swarm.has_statuses(), "%s empties the status list" % removal)


func test_frozen_monsters_deal_no_touch_damage_and_pause_stops_status_clocks() -> void:
	var w := RF.quiet_world()
	w.loadout.order.clear()
	var m := RF.put_mob(w, 1110100, w.player.pos.x)
	w.swarm.alpha[m] = 1.0
	assert_true(w.swarm.apply_status(m, "freeze", {"time": 1.0}, w.events))
	w.state = RunWorld.CHOOSING_UPGRADE
	w.step(DT, MoveInput.new())
	assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 1.0)
	w.state = RunWorld.PLAYING
	var hp := float(w.player_state.hp)
	w.step(DT, MoveInput.new())
	assert_eq(float(w.player_state.hp), hp, "tier C (owner): a frozen monster deals no touch damage")
	for tick in 60:
		w.step(DT, MoveInput.new())
	assert_true(float(w.player_state.hp) < hp, "its canonical bodyAttack returns when the freeze ends")


func test_freeze_lets_an_airborne_monster_fall_and_a_fading_one_appear() -> void:
	var w := RF.quiet_world()
	var m := RF.put_mob(w, 1110100, 700)
	var ctx := _ctx(w)
	w.swarm.alpha[m] = 0.2
	w.swarm.fh[m] = -1
	w.swarm.y[m] -= 80.0
	w.swarm.vx[m] = 50.0
	w.swarm.vy[m] = 0.0
	var start := w.swarm.pos(m)
	var anim_time := w.swarm.anim_t[m]
	assert_true(w.swarm.apply_status(m, "freeze", {"time": 1.0}, w.events))
	for tick in 20:
		w.swarm.step(DT, ctx)
	assert_true(w.swarm.y[m] > start.y, "a monster frozen mid-air falls")
	assert_eq(w.swarm.x[m], start.x, "straight down: no drift while frozen")
	assert_true(w.swarm.alpha[m] > 0.2, "the fade-in continues")
	assert_eq(w.swarm.anim_t[m], anim_time, "the frozen pose holds")


func test_real_v83_status_parameters_and_cached_cues() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var skills := lib.img("Skill.wz/210.img").root
	assert_eq(int(skills.skill["2101003"].level["20"].x), -40)
	assert_eq(int(skills.skill["2101003"].level["20"].time), 40)
	assert_eq(String(skills.skill["2101005"].elemAttr), "s")
	assert_true(lib.find_anim("Skill.wz/210.img/skill/2101003/mob") != null)
	assert_true(lib.find_anim("Skill.wz/210.img/skill/2101005/mob") != null)
	var text := String(lib.img("String.wz/Skill.img").root["2201004"].desc)
	assert_true("1.5" in text, "canonical Cold Beam text documents elemental weakness")
	lib.free()
