extends TestCase
## The ship's three Form effects (spec #384 C11, GAME_DESIGN 7.120.9) on a synthetic ship: `hull` (PlayerHull, a state effect),
## `only_skills` and `art_variant` (FormRules), the `mount` field of `form_started` and the `absorbed` field of `player_hit`.
## No Corsair data or real art is involved; the real Battleship (C13) copies this form's shape.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const ATTACK := 100.0
const SOURCE := {"accuracy": 100000.0, "source_kind": "touch"}


func _world(p_seed := 395) -> RunWorld:
	var data := RF.quiet_data()
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(RF.setup("quiet", p_seed, data))
	w.progression.job_id = 999
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.book.defs["test_ship"] = {"skill_id": 9991001, "book": "999", "kind": "form", "slot": "active",
		"damage": "none", "cooldown": 5.0, "ranks": [1, 2], "cast": {"rule": "form", "mob_within": 400},
		"form": {"duration": 4.0, "exclusive_group": "test_ship",
			"effects": {"hull": {"field": "pdd", "of": "max_hp"}, "only_skills": ["test_ok"],
				"art_variant": {"effect": "effect_ship"}},
			"presentation": {"mount": 1932000}, "subs": []}}
	w.book.skill_imgs["999"] = {"skill": {"9991001": {"level": {"1": {"pdd": 20}, "2": {"pdd": 50}}}}}
	w.loadout.add_skill("test_ship")
	w.loadout.add_player_mod("max_hp", "add", 950.0) # a Lv1 character has 50 HP: room for a hull a hit does not empty
	w.refresh_player_stats()
	w.restore_player("hp", 2000, "test")
	return w


## Two ordinary pool actives (a blocked gun and a permitted one) that fire at anything within 300 px.
func _guns(w: RunWorld) -> void:
	for i in 2:
		var key: String = ["test_gun", "test_ok"][i]
		var id := 9991003 + i
		w.book.defs[key] = {"skill_id": id, "book": "999", "kind": "instant", "slot": "active", "ranks": [1, 3],
			"damage": "fixed", "range": 300, "cooldown": 1.0, "cast": {"rule": "range_around", "min_targets": 1},
			"effect": "Skill.wz/999.img/skill/%d/effect" % id}
		w.book.skill_imgs["999"].skill[str(id)] = {"level": {"1": {"fixdamage": 10, "range": 300, "mobCount": 3},
			"3": {"fixdamage": 10, "range": 300, "mobCount": 3}}}
		w.loadout.add_skill(key)
	w.book.defs.test_gun["effect_ship"] = "Skill.wz/999.img/skill/9991003/effect_ship"


func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, 1110100, px, 195, 100000.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _start(w: RunWorld, key := "test_ship") -> Dictionary:
	w.runner.forms.start(w, key, w.loadout.stats(key))
	return w.runner.forms.snapshot().back()


## Sets the running hull's points (snapshot() returns a copy, so the test reaches the live window).
func _set_hull(w: RunWorld, points: int) -> void:
	w.runner.forms._active.back().hull_hp = points


func _synthetic(w: RunWorld) -> Dictionary:
	var out := {}
	for key: String in w.book.defs:
		if key.begins_with("test_"):
			out[key] = w.book.defs[key]
	return out


func _hits(w: RunWorld) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e: Dictionary in w.events:
		if e.type == "player_hit":
			out.append(e)
	return out


func _hull(w: RunWorld) -> int:
	return int(w.runner.forms.snapshot()[0].hull_hp)


func test_hull_resolves_from_pdd_at_the_forms_level_and_max_hp_at_start() -> void:
	var w := _world()
	var max_hp := int(w.player_state.max_hp)
	var s := _start(w)
	assert_eq(int(s.hull_max), maxi(1, floori(20.0 / 100.0 * max_hp)))
	assert_eq(int(s.hull_hp), int(s.hull_max))
	w.runner.forms.clear(w)
	w.loadout.ranks.test_ship = 2
	assert_eq(int(_start(w).hull_max), maxi(1, floori(50.0 / 100.0 * max_hp)), "level 2 reads the level 2 pdd")
	w.runner.forms.clear(w)
	w.loadout.add_skill_mod("test_ship", "hull", "mul", 1.5)
	assert_eq(int(_start(w).hull_max), maxi(1, floori(50.0 / 100.0 * max_hp * 1.5)), "the hull modifier is a multiplier")


func test_hull_has_a_floor_of_one_and_is_fixed_at_the_start() -> void:
	var w := _world()
	w.book.skill_imgs["999"].skill["9991001"].level["1"].pdd = 0
	assert_eq(int(_start(w).hull_max), 1, "a zero pdd still gives a one point hull")
	w.runner.forms.clear(w)
	w.book.skill_imgs["999"].skill["9991001"].level["1"].pdd = 20
	var s := _start(w)
	var hull_max := int(s.hull_max)
	w.loadout.add_skill_mod("test_ship", "hull", "mul", 3.0)
	assert_eq(int(w.runner.forms.snapshot()[0].hull_max), hull_max, "a later modifier does not resize a running hull")


func test_absorb_takes_exactly_the_damage_and_returns_the_remainder() -> void:
	var w := _world()
	var s := _start(w)
	var hull := int(s.hull_max)
	assert_eq(int(w.runner.forms.absorb(w, 3.0)), 0)
	assert_eq(_hull(w), hull - 3)
	assert_eq(int(w.runner.forms.absorb(w, float(hull - 3 + 7))), 7, "the part the hull cannot take reaches HP")
	assert_true(w.runner.forms.snapshot().is_empty(), "the hull broke")


func test_a_hit_the_hull_takes_costs_no_hp_but_starts_the_hit_window_and_knock_back_guard() -> void:
	var w := _world()
	_start(w)
	var hp := float(w.player_state.hp)
	var hull := _hull(w)
	var dmg := w.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	assert_eq(dmg, 0, "nothing reached HP")
	assert_eq(float(w.player_state.hp), hp)
	var e := _hits(w)[0]
	assert_eq(int(e.damage), 0)
	assert_false(bool(e.miss))
	assert_true(int(e.absorbed) > 0)
	assert_eq(hull - _hull(w), int(e.absorbed), "the hull lost exactly what the event says")
	assert_true(w.upkeep.invincible_t > 0.0, "the hit window started")
	assert_false(w.upkeep.may_knock_back(), "the knock-back guard started")
	assert_eq(w.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE), 0)
	assert_eq(_hits(w).size(), 1, "the window still turns the next hit away")


func test_the_remainder_reaches_hp_and_the_hull_breaks_with_the_cooldown_still_counting() -> void:
	var w := _world()
	var control := _world()
	_start(w)
	_set_hull(w, 5)
	var total := control.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	assert_true(total > 5, "the probe hit is bigger than the hull")
	var hp := float(w.player_state.hp)
	var dmg := w.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	assert_eq(dmg, total - 5, "the hull took 5, the rest is HP")
	assert_eq(hp - float(w.player_state.hp), float(total - 5))
	var e := _hits(w)[0]
	assert_eq(int(e.damage), total - 5)
	assert_eq(int(e.absorbed), 5)
	assert_true(w.runner.forms.snapshot().is_empty())
	assert_true(w.events.has({"type": "form_ended", "skill": "test_ship", "skill_id": 9991001, "reason": "broken"}))
	assert_false(w.buffs.has("test_ship"))
	w.runner.cooldowns.test_ship = 5.0
	w.runner.tick_cooldowns(0.5, w)
	assert_near(float(w.runner.cooldowns.test_ship), 4.5, 0.001, "the cooldown keeps counting after the break")


func test_a_hull_that_exactly_covers_the_hit_ends_it_with_no_hp_lost() -> void:
	var w := _world()
	var control := _world()
	var total := control.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	_start(w)
	_set_hull(w, total)
	var hp := float(w.player_state.hp)
	assert_eq(w.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE), 0)
	assert_eq(float(w.player_state.hp), hp)
	assert_eq(int(_hits(w)[0].absorbed), total)
	assert_true(w.runner.forms.snapshot().is_empty(), "a hull at 0 is broken")


func test_absorbed_is_only_on_events_that_absorbed_something() -> void:
	var w := _world()
	w.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	assert_false(_hits(w)[0].has("absorbed"), "no hull: the event keeps its old fields")
	var plain := _world()
	plain.book.defs.test_ship.form.effects = {}
	_start(plain)
	plain.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	assert_false(_hits(plain)[0].has("absorbed"), "a form without a hull absorbs nothing")
	var miss := _world()
	_start(miss)
	miss.take_hit(ATTACK, false, "", Vector2(100, 190), {"accuracy": 0.0})
	for e in _hits(miss):
		assert_false(bool(e.miss) and e.has("absorbed"), "a miss absorbs nothing")


func test_a_boss_attack_that_ignores_the_hit_window_is_absorbed() -> void:
	var w := _world()
	_start(w)
	_set_hull(w, 1000000)
	var boss := {"accuracy": 100000.0, "boss": true, "source_kind": "attack"}
	w.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	assert_true(w.upkeep.invincible_t > 0.0)
	var before := _hull(w)
	assert_eq(w.take_hit(ATTACK, false, "", Vector2(100, 190), boss), 0, "inside the window, the boss hit lands and is absorbed")
	assert_true(_hull(w) < before)
	assert_eq(_hits(w).size(), 2)
	assert_true(int(_hits(w)[1].absorbed) > 0)


func test_map_transfer_keeps_the_hull_and_death_ends_it() -> void:
	var w := _world()
	_start(w)
	_set_hull(w, 123)
	w.transfer_pending = true
	w.advance_map()
	assert_eq(_hull(w), 123, "player state like a buff: the hull crosses a map transfer")
	w.state = RunWorld.DEAD
	w.runner.tick_cooldowns(DT, w)
	assert_true(w.runner.forms.snapshot().is_empty())
	assert_true(w.events.has({"type": "form_ended", "skill": "test_ship", "skill_id": 9991001, "reason": "died"}))


func test_a_lethal_hit_past_the_hull_still_kills() -> void:
	var w := _world()
	_start(w)
	_set_hull(w, 1)
	w.take_hit(1.0e9, false, "", Vector2(100, 190), SOURCE)
	assert_eq(w.state, RunWorld.DEAD)
	assert_true(w.events.has({"type": "form_ended", "skill": "test_ship", "skill_id": 9991001, "reason": "broken"}))
	assert_true(w.runner.forms.snapshot().is_empty())


func test_the_hull_draws_no_rng_and_a_world_without_it_is_unchanged() -> void:
	var a := _world()
	var b := _world()
	_start(b)
	a.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	b.take_hit(ATTACK, false, "", Vector2(100, 190), SOURCE)
	assert_eq(a.rng.state, b.rng.state, "the hull consumes the same draws as no hull")
	var plain_events := a.events.duplicate(true)
	for e: Dictionary in plain_events:
		assert_false(e.has("absorbed") or e.has("mount"))


func test_form_started_carries_the_mount_only_when_the_form_names_one() -> void:
	var w := _world()
	_start(w)
	var e: Dictionary = w.events.filter(func(x: Dictionary) -> bool: return x.type == "form_started")[0]
	assert_eq(int(e.mount), 1932000)
	var plain := _world()
	plain.book.defs.test_ship.form.erase("presentation")
	_start(plain)
	var p: Dictionary = plain.events.filter(func(x: Dictionary) -> bool: return x.type == "form_started")[0]
	assert_false(p.has("mount"))


func test_only_skills_blocks_pool_actives_outside_the_list_and_keeps_their_cooldown() -> void:
	var w := _world()
	_guns(w)
	_mob(w, 240)
	w.runner.cooldowns.test_ship = 50.0 # so the ship does not recast itself the tick it ends
	_start(w)
	assert_false(w.runner.forms.permits(w, "test_gun"))
	assert_true(w.runner.forms.permits(w, "test_ok"))
	for i in 30:
		w.runner.step(DT, w)
	assert_true(float(w.runner.cooldowns.get("test_ok", 0.0)) > 0.0 or w.runner.casts >= 2, "the permitted skill casts")
	assert_true(float(w.runner.cooldowns.get("test_gun", 0.0)) <= 0.0, "the blocked gun was never cast: it is ready and waiting")
	var casts := w.runner.casts
	w.runner.forms.end(w, "test_ship", "expired")
	assert_true(w.runner.forms.permits(w, "test_gun"), "permitted the tick the form ends")
	w.runner.step(DT, w)
	assert_true(w.runner.casts > casts, "a ready skill that was paused casts the tick the form is gone")
	assert_true(float(w.runner.cooldowns.test_gun) > 0.5, "it was the waiting gun that cast, its cooldown restarted")


func test_a_blocked_skill_cools_down_while_blocked() -> void:
	var w := _world()
	_guns(w)
	_mob(w, 240)
	w.runner.cooldowns.test_gun = 2.0
	_start(w)
	for i in 30:
		w.runner.tick_cooldowns(DT, w)
	assert_near(float(w.runner.cooldowns.test_gun), 1.5, 0.02)


func test_only_skills_leaves_subs_mobility_forms_and_triggered_skills_alone() -> void:
	var w := _world()
	_guns(w)
	_start(w)
	w.book.defs["test_dash"] = {"skill_id": 9991010, "book": "999", "kind": "buff", "slot": "mobility", "cast": {"rule": "manual"}}
	w.book.defs["test_sub"] = {"skill_id": 9991011, "book": "999", "kind": "instant", "slot": "form_sub", "form_sub_of": ["test_ship"]}
	w.book.defs["test_other_form"] = w.book.defs.test_ship.duplicate(true)
	w.book.defs["test_other_form"].form.exclusive_group = "other"
	w.book.defs["test_reaction"] = {"skill_id": 9991012, "book": "999", "kind": "instant", "slot": "active", "cast": {"rule": "reaction"}}
	w.book.defs["test_manual"] = {"skill_id": 9991013, "book": "999", "kind": "instant", "slot": "active", "cast": {"rule": "manual"}}
	for key in ["test_dash", "test_sub", "test_other_form", "test_reaction", "test_manual", "test_ok", "test_ship"]:
		assert_true(w.runner.forms.permits(w, key), key)
	assert_false(w.runner.forms.permits(w, "test_gun"))


func test_sub_skills_keep_casting_aboard() -> void:
	var w := _world()
	_guns(w)
	w.book.defs["test_sub"] = {"skill_id": 9991002, "book": "999", "kind": "instant", "slot": "form_sub",
		"form_sub_of": ["test_ship"], "ranks": [1, 3], "damage": "fixed", "range": 300, "cooldown": 30,
		"cast": {"rule": "range_around", "min_targets": 1}}
	w.book.skill_imgs["999"].skill["9991002"] = {"level": {"1": {"fixdamage": 10, "range": 300, "mobCount": 3},
		"3": {"fixdamage": 10, "range": 300, "mobCount": 3}}}
	w.book.defs.test_ship.form.subs = [{"skill": "test_sub", "first_after": 0.1, "interval": 0.5}]
	var m := _mob(w, 240)
	var before := w.swarm.hp[m]
	_start(w)
	for i in 12:
		w.runner.tick_cooldowns(DT, w)
	assert_true(w.swarm.hp[m] < before, "the ship's own sub fired while the gun was paused")


func test_only_skills_is_inert_without_a_running_form() -> void:
	var w := _world()
	_guns(w)
	for key in ["test_gun", "test_ok", "test_ship"]:
		assert_true(w.runner.forms.permits(w, key))
	_start(w)
	w.runner.forms.end(w, "test_ship", "expired")
	assert_true(w.runner.forms.permits(w, "test_gun"))


func test_art_variant_swaps_the_named_node_only_while_the_form_runs_and_only_for_skills_that_define_it() -> void:
	var w := _world()
	_guns(w)
	var plain: String = w.loadout.stats("test_gun").effect
	assert_eq(w.runner.forms.begin_cast(w, "test_gun", w.loadout.stats("test_gun")).effect, plain)
	_start(w)
	var out := w.runner.forms.begin_cast(w, "test_gun", w.loadout.stats("test_gun"))
	assert_eq(out.effect, "Skill.wz/999.img/skill/9991003/effect_ship", "the ship's node replaces the slot")
	assert_eq(w.loadout.stats("test_gun").effect, plain, "the cast copy is edited, not the shared stats")
	var no_node := w.runner.forms.begin_cast(w, "test_ok", w.loadout.stats("test_ok"))
	assert_eq(no_node.effect, w.loadout.stats("test_ok").effect, "a skill without the node keeps its art")
	w.runner.forms.end(w, "test_ship", "expired")
	assert_eq(w.runner.forms.begin_cast(w, "test_gun", w.loadout.stats("test_gun")).effect, plain, "after the form")


func test_art_variant_changes_no_number() -> void:
	var w := _world()
	_guns(w)
	var plain := w.runner.forms.begin_cast(w, "test_gun", w.loadout.stats("test_gun"))
	_start(w)
	var aboard := w.runner.forms.begin_cast(w, "test_gun", w.loadout.stats("test_gun"))
	for k: String in plain:
		if k != "effect":
			assert_eq(aboard[k], plain[k], k)


func test_validation_accepts_the_synthetic_ship_and_names_each_malformed_block() -> void:
	var w := _world()
	_guns(w)
	assert_true(PlayerForms.validation_errors(_synthetic(w)).is_empty(), str(PlayerForms.validation_errors(_synthetic(w))))
	var bad := {
		"hull": [{"field": "pdd"}, {"field": "", "of": "max_hp"}, {"field": "pdd", "of": "mp"}, "pdd", 5],
		"only_skills": ["x", [1], [""], {}],
		"art_variant": [[], {"effect": 1}, {"": "x"}, {"effect": ""}],
	}
	for effect: String in bad:
		for value: Variant in bad[effect]:
			w.book.defs.test_ship.form.effects = {effect: value}
			var errors := PlayerForms.validation_errors(_synthetic(w))
			assert_false(errors.is_empty(), "%s = %s must be rejected" % [effect, value])
			assert_true(("form.effects.%s" % effect) in " ".join(errors), str(errors))
	for value: Variant in [5, [], {"mount": "x"}, {"mount": 0}, {"mount": -3}, {"mount": 1.5}]:
		w.book.defs.test_ship.form.effects = {}
		w.book.defs.test_ship.form.presentation = value
		assert_false(PlayerForms.validation_errors(_synthetic(w)).is_empty(), "presentation = %s must be rejected" % [value])
	w.book.defs.test_ship.form.presentation = {}
	assert_true(PlayerForms.validation_errors(_synthetic(w)).is_empty(), "an empty presentation is fine")


func test_state_effects_registry_runs_start_and_end_with_the_reason() -> void:
	var w := _world()
	var seen: Array = []
	PlayerForms.STATE_EFFECTS["test_probe"] = {
		"start": func(_w, state, value):
			seen.append(["start", value])
			state.probe = value,
		"end": func(_w, state, reason): seen.append(["end", state.probe, reason]),
		"validate": func(value): return value is int,
	}
	w.book.defs.test_ship.form.effects = {"test_probe": 7}
	assert_true(PlayerForms.validation_errors(_synthetic(w)).is_empty())
	_start(w)
	assert_eq(seen, [["start", 7]])
	w.runner.forms.end(w, "test_ship", "consumed")
	assert_eq(seen, [["start", 7], ["end", 7, "consumed"]])
	PlayerForms.STATE_EFFECTS.erase("test_probe")
