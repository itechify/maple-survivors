extends TestCase
## Synthetic Form contract, independent of playable class data and real assets.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(RF.setup("quiet", 311, data))
	w.progression.job_id = 999
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.book.defs["test_form"] = {"skill_id": 9991001, "book": "999", "kind": "form", "slot": "active",
		"damage": "none", "cooldown": 3.0, "ranks": [1, 2], "cast": {"rule": "form", "mob_within": 400},
		"form": {"duration": 1.0, "exclusive_group": "test", "effects": {"element": "f", "damage": {"field": "damage"}}, "subs": []}}
	w.book.skill_imgs["999"] = {"skill": {"9991001": {"level": {"1": {"damage": 120}, "2": {"damage": 150}}}}}
	w.loadout.add_skill("test_form")
	return w

func test_form_lifecycle_events_and_cooldown() -> void:
	var w := _world()
	var stream := w.rng.state
	w.runner.step(DT, w)
	assert_true(w.runner.forms.snapshot().is_empty(), "no nearby mob: wait")
	RF.put_mob(w, 1110100, 240, 195, 100000.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_eq(w.runner.forms.snapshot().size(), 1)
	assert_true(w.buffs.has("test_form"))
	assert_true(w.events.has({"type": "form_started", "skill": "test_form", "skill_id": 9991001, "element": "f", "duration": 1.0}))
	for i in 60:
		w.runner.tick_cooldowns(DT, w)
	assert_true(w.runner.forms.snapshot().is_empty())
	assert_true(w.events.has({"type": "form_ended", "skill": "test_form", "skill_id": 9991001, "reason": "expired"}))
	assert_near(float(w.runner.cooldowns.test_form), 2.0, 0.02)
	assert_eq(w.rng.state, stream, "Form lifecycle draws no RNG")

func _start(w: RunWorld, key: String = "test_form") -> void:
	w.runner.forms.start(w, key, w.loadout.stats(key))

func _twin(w: RunWorld, key: String, element: String, group: String = "test") -> void:
	w.book.defs[key] = w.book.defs.test_form.duplicate(true)
	w.book.defs[key].form.effects.element = element
	if element.is_empty():
		w.book.defs[key].form.effects.erase("element")
	w.book.defs[key].form.exclusive_group = group
	w.loadout.add_skill(key)

func test_effects_are_cast_local_keep_declared_element_and_skip_no_damage() -> void:
	var w := _world()
	_start(w)
	var base := {"damage_type": "physical", "element": "", "damage_min": 10.0, "damage_max": 20.0, "status_damage_mult": 2.0}
	var out := w.runner.forms.begin_cast(w, "arbitrary", base)
	assert_eq(out.element, "f")
	assert_near(out.damage_min, 12.0, 0.001)
	assert_near(out.damage_max, 24.0, 0.001)
	assert_near(out.status_damage_mult, 2.4, 0.001)
	assert_eq(base.damage_min, 10.0)
	assert_eq(base.element, "")
	base.element = "h"
	assert_eq(w.runner.forms.begin_cast(w, "arbitrary", base).element, "h")
	base.damage_type = "none"
	assert_eq(w.runner.forms.begin_cast(w, "arbitrary", base), base)

func test_exclusion_replacement_independent_groups_transfer_and_death() -> void:
	var w := _world()
	_twin(w, "second", "i")
	_twin(w, "other", "h", "other")
	_start(w)
	assert_false(w.runner.forms.admits(w, "second"))
	assert_true(w.runner.forms.admits(w, "other"))
	_start(w, "second")
	assert_true(w.events.has({"type": "form_ended", "skill": "test_form", "skill_id": 9991001, "reason": "replaced"}))
	assert_false(w.buffs.has("test_form"))
	_start(w, "other")
	assert_eq(w.runner.forms.snapshot().size(), 2)
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.forms.snapshot().size(), 2)
	w.state = RunWorld.DEAD
	w.runner.tick_cooldowns(DT, w)
	assert_true(w.runner.forms.snapshot().is_empty())
	assert_false(w.buffs.has("second"))
	assert_true(w.events.has({"type": "form_ended", "skill": "other", "skill_id": 9991001, "reason": "died"}))

func _sub(w: RunWorld, once: bool = false) -> void:
	w.book.defs["test_sub"] = {"skill_id": 9991002, "book": "999", "kind": "instant", "slot": "form_sub",
		"form_sub_of": ["test_form"], "ranks": [1, 3], "damage": "fixed", "range": 150,
		"cooldown": 30, "cast": {"rule": "range_around", "min_targets": 2}}
	w.book.skill_imgs["999"].skill["9991002"] = {"level": {
		"1": {"fixdamage": 10, "range": 150, "mobCount": 2, "hpCon": 5},
		"3": {"fixdamage": 30, "range": 150, "mobCount": 2, "hpCon": 5}}}
	w.book.defs.test_form.form.subs = [{"skill": "test_sub", "first_after": 0.1, "interval": 0.2, "once": once}]

func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, 1110100, px, 195, 100000.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func test_sub_waits_for_targets_and_hp_then_interval_and_once_reset() -> void:
	var w := _world()
	_sub(w, true)
	_start(w)
	for i in 10:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 0)
	_mob(w, 240)
	w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 0, "minimum targets must hold")
	_mob(w, 250)
	w.spend_hp(int(w.player_state.hp) - 5)
	w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 0, "cannot spend last HP")
	w.restore_player("hp", 30, "test")
	w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 1, "due sub retries immediately")
	for i in 20:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 1, "once is consumed")
	_start(w)
	for i in 6:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 2, "new window resets once")

func test_sub_rank_damage_area_inheritance_and_slot_exclusion() -> void:
	var w := _world()
	_sub(w)
	assert_false(w.loadout.add_skill("test_sub"))
	assert_false("test_sub" in w.loadout.order)
	w.loadout.ranks.test_form = 2
	w.loadout.add_skill_mod("test_form", "damage", "mul", 2.0)
	w.loadout.add_skill_mod("test_form", "area", "mul", 2.0)
	w.loadout.add_skill_mod("test_form", "cooldown", "mul", 0.1)
	var m := _mob(w, 430)
	_mob(w, 440)
	_start(w)
	var before := w.swarm.hp[m]
	for i in 6:
		w.runner.tick_cooldowns(DT, w)
	# Rank 2 maps to sub level 3: 30 fixed * parent damage 2 * form 1.5 = 90.
	assert_near(before - w.swarm.hp[m], 90.0, 0.01)
	for i in 12:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 2, "sub interval ignores parent cooldown")

func test_form_modifiers_snapshot_and_text() -> void:
	var w := _world()
	_sub(w)
	w.loadout.add_skill_mod("test_form", "form_time", "mul", 2.0)
	w.loadout.add_skill_mod("test_form", "form_power", "add", 0.1)
	_start(w)
	assert_near(w.runner.forms.snapshot()[0].remaining, 2.0, 0.001)
	assert_near(w.runner.forms.snapshot()[0].effects.damage, 1.3, 0.001)
	w.loadout.add_skill_mod("test_form", "form_time", "mul", 2.0)
	assert_near(w.runner.forms.snapshot()[0].remaining, 2.0, 0.001)
	var line := SkillText.new(w.book).level_line("test_form", 1, w.loadout.stats("test_form"))
	assert_true("fire" in line and "4 s" in line and "30%" in line, line)
	assert_true("10 fixed damage" in line and "every 0.2 s" in line and "5 HP" in line, line)

## The synthetic catalog alone: the shipped Paladin sub-skill names Charges that later tickets define (P6 #314).
func _synthetic(w: RunWorld) -> Dictionary:
	var out := {}
	for key: String in w.book.defs:
		if key.begins_with("test_"):
			out[key] = w.book.defs[key]
	return out

func test_schema_rejects_unknown_effects_and_missing_sub_links() -> void:
	var w := _world()
	_sub(w)
	assert_true(PlayerForms.validation_errors(_synthetic(w)).is_empty())
	w.book.defs["test_form_more"] = w.book.defs.test_form.duplicate(true)
	w.book.defs.test_form_more.form.subs = []
	w.book.defs.test_sub.form_sub_of = "test_form_more"
	assert_true("test_form.form.subs" in " ".join(PlayerForms.validation_errors(_synthetic(w))), "string parent links match whole keys")
	w.book.defs.test_sub.form_sub_of = ["test_form"]
	w.book.defs.test_form.form.effects["typo"] = true
	assert_true("effects.typo" in " ".join(PlayerForms.validation_errors(_synthetic(w))))
	w.book.defs.test_form.form.duration = -1
	w.book.defs.test_sub.erase("form_sub_of")
	var errors := " ".join(PlayerForms.validation_errors(_synthetic(w)))
	assert_true("duration" in errors and "form_sub_of" in errors, errors)
	w.book.defs.test_form.cast.mob_within = {}
	w.book.defs.test_form.form.subs[0].interval = "later"
	w.book.defs.test_form.form.subs[0].once = "yes"
	errors = " ".join(PlayerForms.validation_errors(_synthetic(w)))
	assert_true("mob_within" in errors and "interval" in errors and "once" in errors, errors)

func test_preferred_scores_living_nearby_mobs_and_keeps_order_on_ties() -> void:
	var w := _world()
	_twin(w, "ice", "i")
	_twin(w, "plain", "")
	var m := _mob(w, 240)
	var kind := w.swarm.mob_kind(m)
	kind.elements = {"F": 0.5, "I": 1.5}
	var ready: Array[String] = ["plain", "test_form", "ice"]
	assert_eq(w.runner.forms.preferred(w, ready), ["ice"])
	kind.elements = {"F": 1.0, "I": 1.0}
	assert_eq(w.runner.forms.preferred(w, ready), ["test_form"])
	kind.elements = {"F": 0.0, "I": 0.0}
	assert_eq(w.runner.forms.preferred(w, ready), ["plain"])
	kind.elements = {"F": 0.5, "I": 1.5}
	w.runner.step(DT, w)
	assert_eq(w.runner.forms.snapshot()[0].skill, "ice", "cast_ready uses arbitration")
	assert_true(float(w.runner.cooldowns.test_form) <= 0, "excluded loser spends nothing")
	for i in 60:
		w.runner.tick_cooldowns(DT, w)
	w.runner.cast_ready(DT, w)
	assert_eq(w.runner.forms.snapshot()[0].skill, "test_form", "other form starts when first expires")

func _pending_sub(w: RunWorld) -> void:
	_sub(w, true)
	w.book.defs.test_sub.pending = {"delay": 0.4}
	for level: Dictionary in w.book.skill_imgs["999"].skill["9991002"].level.values():
		level["lt"] = {"$v": [-150, -100]}
		level["rb"] = {"$v": [150, 0]}

func test_pending_sub_is_dropped_on_transfer_but_once_remains_consumed() -> void:
	var control := _world()
	_pending_sub(control)
	var target := _mob(control, 240)
	_mob(control, 250)
	_start(control)
	var control_hp := control.swarm.hp[target]
	for i in 36:
		control.runner.tick_cooldowns(DT, control)
	assert_near(control_hp - control.swarm.hp[target], 12.0, 0.01, "control: pending strike actually hits")
	var w := _world()
	_pending_sub(w)
	_mob(w, 240)
	_mob(w, 250)
	_start(w)
	for i in 6:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 1)
	w.transfer_pending = true
	w.advance_map()
	var m := _mob(w, 240)
	var before := w.swarm.hp[m]
	for i in 30:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.swarm.hp[m], before, "in-flight map-space hit discarded")
	assert_eq(w.runner.casts, 1, "once consumed across transfer")

func test_rarity_previews_form_time_and_power_in_resolved_units() -> void:
	var w := _world()
	w.book.defs.test_form.rarity_bonuses = {"rare": [{"id": "long", "name": "Long form", "effects": [
		{"stat": "form_time", "op": "mul", "value": 1.5}, {"stat": "form_power", "op": "add", "value": 0.1}]}]}
	w.upgrades = UpgradePool.from_data({"cards": [{"id": "test_rank", "kind": "skill_rank", "skill": "test_form", "max_rank": 2}]})
	var c := w.upgrades.choice_card("test_rank", w, "rare")
	assert_eq(c.skill_mod_changes.form_time, {"before": 1.0, "after": 1.5})
	assert_eq(c.skill_mod_changes.form_power, {"before": 0.0, "after": 10.0})

func test_manual_dash_takes_form_effects_without_changing_its_definition() -> void:
	var w := _world()
	w.book.defs["test_dash"] = {"skill_id": 9991003, "book": "999", "kind": "instant", "slot": "mobility",
		"ranks": [1], "damage": "fixed", "cooldown": 2, "cast": {"rule": "manual"},
		"displacement": {"distance": 80, "direction": "toward", "when": "during"}}
	w.book.skill_imgs["999"].skill["9991003"] = {"level": {"1": {"fixdamage": 100, "mobCount": 1,
		"lt": {"$v": [-100, -70]}, "rb": {"$v": [0, 0]}}}}
	w.loadout.add_skill("test_dash")
	var m := _mob(w, 250)
	w.swarm.mob_kind(m).elements = {"F": 1.5}
	_start(w)
	var before := w.swarm.hp[m]
	assert_true(w.runner.cast_dash(w, "test_dash", 1))
	assert_near(before - w.swarm.hp[m], 180.0, 0.01, "100 fixed * 1.2 form * 1.5 weakness")
	assert_eq(w.loadout.stats("test_dash").element, "")
