extends TestCase
## The all-element mark (spec #384 C7, ticket #391): the `all_weak` status multiplies every damaging hit on a monster, the
## `mark_time` / `mark_power` modifiers resolve through Loadout, and `targets_before` prefers a marked monster after scheduled
## bosses. A synthetic marking skill on a non-Corsair job; fixed ticks, seeded RNG, no asset cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const AF := preload("res://tests/fixtures/asset_fixtures.gd")
const DT := 1.0 / 60.0
const MARK_HIT := {"status": "all_weak", "duration": 8.0}


func _world(extra := {}) -> RunWorld:
	var def := {"kind": "instant", "damage": "fixed", "on_hit": MARK_HIT}
	def.merge(extra, true)
	return CF.world(def)


## The same world without the skill's own mark, so a test marks monsters by hand and its casts never refresh them.
func _plain(extra := {}) -> RunWorld:
	var def := {"on_hit": {}}
	def.merge(extra, true)
	return _world(def)


func _tick(w: RunWorld, ticks: int) -> void:
	var ctx := {"fhm": w.fhm, "target": w.player.pos, "target_fh": w.player.fh, "bounds": w.bounds, "events": w.events}
	for tick in ticks:
		w.swarm.step(DT, ctx)


## A motionless, fully faded-in 100000 HP mob at x.
func _mob(w: RunWorld, x := 350.0) -> int:
	var m := RF.put_mob(w, 1110100, x, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.swarm.mob_kind(m).move_speed = 0.0
	w.swarm.alpha[m] = 1.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _hit(w: RunWorld, m: int, skill := "synthetic") -> int:
	w.drain_events()
	w.hit_mob(m, w.loadout.stats(skill), -1)
	var damage := -1
	for e: Dictionary in w.events:
		if e.type == "mob_hit":
			damage = int(e.damage)
	return damage


func _mark(w: RunWorld, m: int, time := 8.0, params := {}) -> bool:
	var p := {"time": time}
	p.merge(params, true)
	return w.swarm.apply_status(m, "all_weak", p, w.events)


func _marked(w: RunWorld, m: int) -> bool:
	return w.swarm.status_time(m, MobSwarm.ALL_WEAK) > 0.0


# --- the status row -------------------------------------------------------------------------------------------------

func test_the_mark_is_the_next_status_and_every_table_keeps_its_length_and_earlier_rows() -> void:
	assert_eq(MobSwarm.ALL_WEAK, MobSwarm.BURN + 1)
	assert_eq(MobSwarm.STATUS_COUNT, MobSwarm.ALL_WEAK + 1)
	assert_eq(MobSwarm.STATUS_TABLE.size(), MobSwarm.STATUS_COUNT)
	assert_eq(MobSwarm.STATUS_NAMES.size(), MobSwarm.STATUS_COUNT)
	assert_eq(MobSwarm.STATUS_ELEMENTS.size(), MobSwarm.STATUS_COUNT)
	assert_eq(MobSwarm.STATUS_NAMES[MobSwarm.ALL_WEAK], "all_weak")
	assert_eq(MobSwarm.STATUS_ELEMENTS[MobSwarm.ALL_WEAK], "")
	var earlier := ["slow", "poison", "freeze", "threatened", "stun", "ice_weak", "fire_weak", "burn"]
	for i in earlier.size():
		assert_eq(MobSwarm.STATUS_NAMES[i], earlier[i], "index %d is unchanged" % i)
	assert_eq(MobSwarm.VULNERABLE[MobSwarm.ICE_WEAK], "i")
	assert_eq(MobSwarm.VULNERABLE[MobSwarm.FIRE_WEAK], "f")
	assert_false(MobSwarm.VULNERABLE.has(MobSwarm.ALL_WEAK), "the mark runs through _mark_mult, not the vulnerability table")


func test_the_mark_applies_expires_with_its_events_and_a_reapplication_refreshes_without_stacking() -> void:
	var w := _plain()
	var m := _mob(w)
	assert_true(_mark(w, m, 1.0))
	var applied := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied")
	assert_eq(applied.size(), 1)
	assert_eq(applied[0].status, "all_weak")
	assert_near(w.swarm.element_multiplier(m, ""), 1.5)
	for tick in 30:
		_tick(w, 1)
	assert_true(_mark(w, m, 1.0, {"mult": 1.5}))
	assert_near(w.swarm.status_time(m, MobSwarm.ALL_WEAK), 1.0, 1e-6, "refreshed to the full time")
	assert_near(w.swarm.element_multiplier(m, ""), 1.5, 1e-9, "a second application does not stack")
	for tick in 59:
		_tick(w, 1)
	assert_true(_marked(w, m))
	for tick in 3:
		_tick(w, 1)
	assert_false(_marked(w, m))
	assert_near(w.swarm.element_multiplier(m, ""), 1.0, 1e-12, "the multiplier ends with the status")
	var expired := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_status_expired" \
		and e.status == "all_weak")
	assert_eq(expired.size(), 1)


func test_a_reapplication_replaces_the_stored_multiplier_it_never_adds() -> void:
	var w := _plain()
	var m := _mob(w)
	assert_true(_mark(w, m, 8.0, {"mult": 1.75}))
	assert_near(w.swarm.element_multiplier(m, ""), 1.75)
	assert_true(_mark(w, m, 8.0, {"mult": 1.5}))
	assert_near(w.swarm.element_multiplier(m, ""), 1.5)


# --- the damage ----------------------------------------------------------------------------------------------------

func test_an_element_less_hit_takes_x1_5_and_an_unmarked_twin_is_untouched() -> void:
	var w := _plain()
	var marked := _mob(w, 350.0)
	var plain := _mob(w, 380.0)
	assert_eq(_hit(w, plain), 100)
	assert_true(_mark(w, marked))
	assert_eq(_hit(w, marked), 150)
	assert_eq(_hit(w, plain), 100, "only the marked monster")


func test_an_elemental_hit_multiplies_with_the_element_multiplier() -> void:
	var w := _plain({"element": "f"})
	var m := _mob(w)
	w.swarm.mob_kind(m).elements = {"F": 1.5}
	assert_eq(_hit(w, m), 150)
	assert_true(_mark(w, m))
	assert_eq(_hit(w, m), 225, "1.5 (element) x 1.5 (mark)")
	w.swarm.mob_kind(m).elements = {"F": 0.5}
	assert_eq(_hit(w, m), 75, "0.5 x 1.5")
	w.swarm.mob_kind(m).elements = {"F": 0.0}
	assert_eq(_hit(w, m), 0, "an immune monster stays immune")


func test_a_marked_monster_stacks_with_the_other_vulnerabilities() -> void:
	var w := _plain({"element": "f"})
	var m := _mob(w)
	assert_true(w.swarm.apply_status(m, "fire_weak", {"time": 8.0}, w.events))
	assert_eq(_hit(w, m), 150, "fire_weak alone")
	assert_true(_mark(w, m))
	assert_eq(_hit(w, m), 225, "fire_weak x mark")


func test_a_projectile_takes_the_mark_too() -> void:
	var w := _plain({"kind": "projectile", "radius": 1})
	var twin := _plain({"kind": "projectile", "radius": 1})
	var m := _mob(w)
	var t := _mob(twin)
	assert_true(_mark(w, m))
	var dealt: Array[int] = []
	for world: RunWorld in [w, twin]:
		var slot: int = m if world == w else t
		world.drain_events()
		world.runner.fire_shot(world, "synthetic", world.loadout.stats("synthetic"), world.player.pos, world.mob_center(slot))
		var damage := 0
		for tick in 60:
			world.step(DT, MoveInput.new())
			for e: Dictionary in world.drain_events():
				if e.type == "mob_hit" and e.skill == "synthetic":
					damage = int(e.damage)
		dealt.append(damage)
	assert_eq(dealt[1], 100, "fixture: the unmarked shot lands")
	assert_eq(dealt[0], 150)


func test_poison_and_burn_pulses_are_not_multiplied() -> void:
	var w := _plain()
	var m := _mob(w)
	assert_true(_mark(w, m, 10.0))
	assert_true(w.swarm.apply_status(m, "burn", {"pulse": 40, "time": 3.0, "skill": "synthetic"}, w.events))
	var before := w.swarm.hp[m]
	_tick(w, 62)
	assert_eq(before - w.swarm.hp[m], 40, "one burn pulse of exactly its snapshot")
	var poisoned := _mob(w, 380.0)
	assert_true(_mark(w, poisoned, 10.0))
	assert_true(w.swarm.apply_status(poisoned, "poison", {"level": 30, "time": 4.0}, w.events))
	var hp := w.swarm.hp[poisoned]
	var expected := mini(MobSwarm.POISON_DAMAGE_CAP, ceili(float(w.swarm.max_hp[poisoned]) / (MobSwarm.POISON_LEVEL_BASE - 30)))
	_tick(w, 62)
	assert_eq(hp - w.swarm.hp[poisoned], expected, "one poison pulse, unmultiplied")


func test_the_mark_draws_no_rng() -> void:
	var w := _world()
	var twin := _world({"on_hit": {}})
	var m := _mob(w)
	var t := _mob(twin)
	_hit(w, m)
	_hit(twin, t)
	for tick in 120:
		w.step(DT, MoveInput.new())
		twin.step(DT, MoveInput.new())
	assert_eq(w.rng.state, twin.rng.state, "applying, holding and expiring the mark draw nothing")


# --- bosses ------------------------------------------------------------------------------------------------------------

func test_a_canonical_boss_is_markable_and_takes_x1_25() -> void:
	var w := _plain()
	var m := _mob(w)
	w.swarm.mob_kind(m).boss = true
	assert_false(w.swarm.apply_status(m, "freeze", {"time": 3.0}, w.events), "fixture: a boss still rejects the other statuses")
	assert_true(_mark(w, m))
	assert_true(_marked(w, m))
	assert_eq(_hit(w, m), 125)


func test_a_scheduled_boss_is_markable_and_takes_x1_25() -> void:
	var w := _plain()
	var m := _mob(w)
	w.mob_boss[m] = 0
	w.swarm.steady[m] = 1
	assert_true(w.is_scheduled_boss(m))
	assert_true(_mark(w, m))
	assert_eq(_hit(w, m), 125)
	assert_true(_mark(w, m, 8.0, {"mult": 1.5, "boss_mult": 1.5}))
	assert_eq(_hit(w, m), 150, "mark_power raises the boss multiplier too")


func test_the_mark_ignores_the_hit_element_when_applied_so_an_immune_kind_still_takes_it() -> void:
	var w := _world({"element": "f"})
	var m := _mob(w)
	w.swarm.mob_kind(m).elements = {"F": 1.0}
	w.swarm.mob_kind(m).element_codes = {"F": "1"}
	w.hit_mob(m, w.loadout.stats("synthetic"), -1)
	assert_true(_marked(w, m), "a fire hit on a fire-immune-status kind still marks (the mark is elementless)")


# --- the modifiers -----------------------------------------------------------------------------------------------------

func test_the_loadout_resolves_the_mark_numbers_and_the_modifiers_change_them() -> void:
	var w := _world()
	var st := w.loadout.stats("synthetic")
	assert_near(float(st.mark_time), 8.0)
	assert_near(float(st.mark_mult), 1.5)
	assert_near(float(st.mark_boss_mult), 1.25)
	w.loadout.add_skill_mod("synthetic", "mark_power", "add", 0.25)
	w.loadout.add_skill_mod("synthetic", "mark_time", "mul", 1.5)
	st = w.loadout.stats("synthetic")
	assert_near(float(st.mark_time), 12.0)
	assert_near(float(st.mark_mult), 1.75)
	assert_near(float(st.mark_boss_mult), 1.5)
	assert_false(CF.world().loadout.stats("synthetic").has("mark_mult"), "a skill with no mark gains no key")


func test_a_cast_stores_the_modified_duration_and_multipliers() -> void:
	var w := _world()
	w.loadout.add_skill_mod("synthetic", "mark_power", "add", 0.25)
	w.loadout.add_skill_mod("synthetic", "mark_time", "mul", 1.5)
	var m := _mob(w)
	assert_eq(_hit(w, m), 100, "the first hit lands before the mark")
	assert_near(w.swarm.status_time(m, MobSwarm.ALL_WEAK), 12.0, 1e-9, "8 s x 1.5")
	assert_eq(_hit(w, m), 175, "x1.75")
	var boss := _mob(w, 380.0)
	w.mob_boss[boss] = 0
	w.swarm.steady[boss] = 1
	_hit(w, boss)
	assert_eq(_hit(w, boss), 150, "x1.25 + 0.25 on a boss")


func test_mark_power_never_weakens_the_hit() -> void:
	var w := _world()
	w.loadout.add_skill_mod("synthetic", "mark_power", "add", -3.0)
	var mult := w.loadout.mark_multipliers("synthetic")
	assert_eq(mult, Vector2(1.0, 1.0))


# --- targeting ---------------------------------------------------------------------------------------------------------

func test_targets_before_orders_boss_then_marked_then_distance_then_slot() -> void:
	var w := _plain()
	var near := _mob(w, 260.0)
	var far_marked := _mob(w, 500.0)
	var farther_marked := _mob(w, 520.0)
	var boss := _mob(w, 600.0)
	w.mob_boss[boss] = 0
	w.swarm.steady[boss] = 1
	assert_true(_mark(w, far_marked))
	assert_true(_mark(w, farther_marked))
	assert_true(w.targets_before(far_marked, 90000.0, near, 100.0), "marked before nearer unmarked")
	assert_false(w.targets_before(near, 100.0, far_marked, 90000.0))
	assert_true(w.targets_before(far_marked, 100.0, farther_marked, 200.0), "marked ties fall to distance")
	assert_true(w.targets_before(boss, 1.0e9, far_marked, 1.0), "a scheduled boss first, marked or not")
	assert_false(w.targets_before(far_marked, 1.0, boss, 1.0e9))
	assert_true(w.targets_before(boss, 1.0e9, near, 1.0))
	# Unmarked: the old order exactly (distance, then slot).
	var other := _mob(w, 270.0)
	assert_true(w.targets_before(near, 100.0, other, 200.0))
	assert_true(w.targets_before(near, 100.0, other, 100.0), "equal distance: lower slot")
	assert_false(w.targets_before(other, 100.0, near, 100.0))
	assert_false(w.targets_before(near, 100.0, near, 100.0), "strict")


func test_the_nearest_rule_picks_the_marked_monster_first_and_the_rest_by_distance() -> void:
	var w := _plain()
	var near := _mob(w, 250.0)
	var mid := _mob(w, 300.0)
	var marked := _mob(w, 450.0)
	assert_true(_mark(w, marked))
	var origin := w.player.pos
	assert_eq(w.runner._find_targets(w, origin, 600.0, 1), 1)
	assert_eq(w.runner._tgt[0], marked)
	assert_eq(w.runner._find_targets(w, origin, 600.0, 3), 3)
	assert_eq(Array(w.runner._tgt), [marked, near, mid])
	assert_eq(w.runner._find_targets(w, origin, 200.0, 1), 1, "a marked monster out of range is not a candidate")
	assert_eq(w.runner._tgt[0], near)


func test_a_box_cast_still_hits_everything_in_the_box() -> void:
	var w := _plain()
	var a := _mob(w, 260.0)
	var b := _mob(w, 280.0)
	assert_true(_mark(w, b))
	var hit := w.skill_box_targets(Rect2(-100.0, -80.0, 200.0, 100.0), Callable(), 1)
	assert_true(a in hit and b in hit, "the box rule takes both marked and unmarked")


func test_a_burst_retarget_prefers_the_marked_monster() -> void:
	var w := RunWorld.new(RF.setup("quiet", 336, RF.quiet_data()))
	RF.place_player(w, 200)
	w.loadout.order.clear()
	var d := w.book.def("energy_bolt").duplicate(true)
	d.cast = {"rule": "burst"}
	d.burst = {"interval": 0.1, "wind_up": 0.0, "retarget": true}
	d.count = 5
	d.cooldown = 6.0
	d.range = 450.0
	w.book.defs["stream"] = d
	w.data.jobs_survivor.jobs["212"].skill_pool.append("stream")
	w.learn_skill("stream")
	var first := _mob(w, 400.0)
	w.runner.step(DT, w)
	var near_right := _mob(w, 230.0)
	var marked_left := _mob(w, 20.0)
	assert_true(_mark(w, marked_left))
	w.swarm.despawn(first)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	for tick in 6:
		w.runner.step(DT, w)
	assert_true(w.projectiles.vx[1] < 0, "the replacement goes for the marked monster on the left, not the nearer one")
	assert_true(w.swarm.is_live(near_right))


func test_a_summon_strikes_the_marked_monster_before_a_nearer_one() -> void:
	var setup := RF.setup("quiet", 291, RF.quiet_data())
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 100.0, "mastery": 10.0, "time": 3.0}
	setup.skill_imgs["212"] = {"skill": {"2121005": {"level": levels, "elemAttr": "i",
		"summon": {"attack1": {"info": {"attackAfter": 100.0, "mobCount": 1.0,
		"range": {"lt": {"$v": [-200, -150]}, "rb": {"$v": [0, 30]}}}}}}}}
	setup.data.stages.stages.quiet.maps.append(setup.data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("elquines")
	w.loadout.set_caster(100.0, 0.0, 30)
	var near := _mob(w, 260.0)
	var marked := _mob(w, 330.0)
	assert_true(_mark(w, marked, 30.0))
	w.runner.step(DT, w)
	w.loadout.order.clear()
	for tick in 12:
		w.runner.tick_cooldowns(DT, w)
	assert_true(w.swarm.hp[marked] < 100000, "mobCount 1: the one strike goes to the marked monster")
	assert_eq(w.swarm.hp[near], 100000)


# --- presentation ---------------------------------------------------------------------------------------------------------

func test_the_renderer_has_a_mark_cue_and_a_red_fallback_tint_and_keeps_the_earlier_cues() -> void:
	assert_eq(MobRenderer.BURN_CUE, 4)
	assert_eq(MobRenderer.MARK_CUE, 5)
	assert_eq(MobRenderer.CUES_PER_SLOT, 6)
	assert_eq(MobRenderer.STUN_CUE, 3, "existing cue indices are unchanged")
	var c := MobRenderer.MARK_TINT
	assert_true(c.r > c.g and c.r > c.b, "red")


func _renderer(lib: AssetLibrary, root: Node) -> MobRenderer:
	var r := MobRenderer.new()
	r.library = lib
	root.add_child(r)
	return r


func _kind_ids(w: RunWorld) -> PackedInt32Array:
	var ids := PackedInt32Array()
	for k in w.mob_kinds.size():
		ids.append(100100)
	return ids


func test_a_marked_mob_without_configured_art_takes_the_fallback_tint() -> void:
	var lib := AssetLibrary.new()
	lib.open(AF.write_cache())
	var root := Node2D.new()
	var w := _plain()
	var m := _mob(w)
	w.swarm.state[m] = MobSwarm.STAND
	assert_true(_mark(w, m))
	var r := _renderer(lib, root)
	r.update_from(w.swarm, _kind_ids(w))
	assert_eq(r._pool.tint_of(m), MobRenderer.MARK_TINT)
	assert_false(r._status_pool.is_shown(m * MobRenderer.CUES_PER_SLOT + MobRenderer.MARK_CUE), "no art, no cue sprite")
	w.swarm.status_left[m * MobSwarm.STATUS_COUNT + MobSwarm.ALL_WEAK] = 0.0
	r.update_from(w.swarm, _kind_ids(w))
	assert_eq(r._pool.tint_of(m), Color.WHITE, "the tint ends with the status")
	root.free()
	lib.free()


func test_a_configured_mark_cue_loops_over_the_monster_and_replaces_the_tint() -> void:
	var lib := AssetLibrary.new()
	lib.open(AF.write_cache())
	var root := Node2D.new()
	var w := _plain()
	var m := _mob(w)
	w.swarm.state[m] = MobSwarm.STAND
	assert_true(_mark(w, m))
	var r := _renderer(lib, root)
	r.mark_cue_path = "Mob.wz/0100100.img/stand"
	r.update_from(w.swarm, _kind_ids(w))
	var slot := m * MobRenderer.CUES_PER_SLOT + MobRenderer.MARK_CUE
	assert_true(r._status_pool.is_shown(slot))
	assert_eq(r._pool.tint_of(m), Color.WHITE, "art configured: no fallback tint")
	w.swarm.status_elapsed[m * MobSwarm.STATUS_COUNT + MobSwarm.ALL_WEAK] = 50.0
	r.update_from(w.swarm, _kind_ids(w))
	assert_true(r._status_pool.is_shown(slot), "loops while the status lasts")
	w.swarm.status_left[m * MobSwarm.STATUS_COUNT + MobSwarm.ALL_WEAK] = 0.0
	r.update_from(w.swarm, _kind_ids(w))
	assert_false(r._status_pool.is_shown(slot), "hidden when the mark ends")
	root.free()
	lib.free()


func test_skill_text_and_the_cards_state_the_mark() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	assert_eq(text.level_line("synthetic", 1, w.loadout.stats("synthetic")),
		"Marks a monster for 8 s: it takes 50% more damage; bosses 25%")
	var changes := UpgradePool._bonus_changes({"skill": "synthetic", "effects": [
		{"stat": "mark_power", "op": "add", "value": 0.25}, {"stat": "mark_time", "op": "mul", "value": 1.5}]}, w.loadout, 1)
	assert_eq(changes.mark_power, {"before": 150, "after": 175})
	assert_eq(changes.mark_time, {"before": 8.0, "after": 12.0})
	var lines := LevelUpWindow.change_lines({"skill_mod_changes": changes})
	assert_true("Mark damage: 150% → 175%" in Array(lines))
	assert_true("Mark duration: 8 s → 12 s" in Array(lines))
	assert_false(SkillText.new(CF.world().book).level_line("synthetic", 1, CF.world().loadout.stats("synthetic")).contains("Marks"))
