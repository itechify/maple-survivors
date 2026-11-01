extends TestCase
## A Hidden form (Shadower SH3 #428, spec #425 SH-1 and SH-3): the Hidden state rides the form's ordinary `buff` block
## (`hidden`, `stat`/`field`) through PlayerForms.start -> PlayerBuffs.start, so PlayerForms needs no `hidden` effect key,
## and a `form_sub` entry carrying `ignores_hidden` is admitted by the sub driver while the caster is Hidden.
## Everything here is a synthetic form (made-up job 999, skill 9991001+): no Shadower data and no asset cache.
## test_player_forms stays the contract of the seam, test_hidden the contract of the generic Hidden state, and
## test_morph_form is the sibling template for the buff-block capability; this file is what a later hidden form copies.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "hide_form"
const SUB := "hide_sub"
const SNAIL := 100100
## The synthetic level-1 numbers (Skill.wz-shaped): a speed penalty like Dark Sight's, the form's damage percent.
const SPEED := -26.0
const DAMAGE := 150.0


## A quiet world with one hidden form: 2 s window, a speed penalty, the form's damage effect, no subs yet.
func _world(seconds: float = 2.0) -> RunWorld:
	var data := RF.quiet_data()
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	data.balance.player.hp = 1000
	data.balance.regen.hp = 0
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0
	var w := RunWorld.new(RF.setup("quiet", 428, data))
	w.progression.job_id = 999
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.book.defs[KEY] = {"skill_id": 9991001, "book": "999", "kind": "form", "slot": "active", "damage": "none",
		"cooldown": 3.0, "ranks": [1, 2], "cast": {"rule": "form", "mob_within": 400}, "icon": "",
		"buff": {"hidden": true, "stat": "speed", "field": "speed"},
		"form": {"duration": seconds, "exclusive_group": "hide", "effects": {"damage": {"field": "damage"}}, "subs": []}}
	w.book.skill_imgs["999"] = {"skill": {"9991001": {"level": {
		"1": {"speed": SPEED, "damage": DAMAGE, "time": seconds}, "2": {"speed": SPEED / 2.0, "damage": DAMAGE, "time": seconds}}}}}
	w.loadout.add_skill(KEY)
	w.drain_events()
	return w


## The form's start without its cast: the manual start spends no cooldown, so the form is parked behind a long one when a
## test needs the pool to run after the window (otherwise the ready form would re-cast itself with a monster near).
func _start(w: RunWorld, key: String = KEY) -> void:
	w.runner.forms.start(w, key, w.loadout.stats(key))
	w.runner.cooldowns[key] = 100.0


func _tick(w: RunWorld, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _mob(w: RunWorld, px: float, id: int = SNAIL, speed: float = 0.0) -> int:
	var kind: MobKind = w.mob_kinds[int(w.kind_of_id[id])]
	kind.move_speed = speed
	var m := RF.put_mob(w, id, px, 190.0, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.swarm.alpha[m] = 1.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


## A damaging form_sub of KEY (fixed damage 10 / 30 by the parent's rank, two targets in 150 px), listed on the form with
## `rule` (first_after 0.5, interval 1.0 unless overridden).
func _sub(w: RunWorld, rule: Dictionary = {}) -> void:
	w.book.defs[SUB] = {"skill_id": 9991002, "book": "999", "kind": "instant", "slot": "form_sub",
		"form_sub_of": [KEY], "ranks": [1, 3], "damage": "fixed", "range": 150, "cooldown": 30,
		"cast": {"rule": "range_around", "min_targets": 2}}
	w.book.skill_imgs["999"].skill["9991002"] = {"level": {
		"1": {"fixdamage": 10, "range": 150, "mobCount": 2}, "3": {"fixdamage": 30, "range": 150, "mobCount": 2}}}
	var entry := {"skill": SUB, "first_after": 0.5, "interval": 1.0}
	entry.merge(rule, true)
	w.book.defs[KEY].form.subs = [entry]


# --- the Hidden window ------------------------------------------------------------------------------------------------

func test_hidden_exactly_from_form_started_until_form_ended_when_it_expires() -> void:
	var w := _world()
	assert_false(w.is_hidden())
	var stream := w.rng.state
	_start(w)
	assert_true(w.is_hidden(), "Hidden the moment the form starts")
	assert_eq(_of(w.drain_events(), "form_started").size(), 1)
	var events := _tick(w, 110)
	assert_true(w.is_hidden(), "still Hidden shortly before 2 s")
	assert_true(bool(w.player_state.hidden))
	events.append_array(_tick(w, 20))
	assert_false(w.is_hidden(), "over with the window")
	assert_false(bool(w.player_state.hidden))
	assert_true(events.has({"type": "form_ended", "skill": KEY, "skill_id": 9991001, "reason": "expired"}))
	assert_eq(w.rng.state, stream, "starting and ending a hidden form draws no RNG")


func test_hidden_ends_with_the_form_when_the_character_dies() -> void:
	var w := _world()
	_start(w)
	w.state = RunWorld.DEAD
	w.runner.tick_cooldowns(DT, w)
	assert_true(w.drain_events().has({"type": "form_ended", "skill": KEY, "skill_id": 9991001, "reason": "died"}))
	assert_false(w.is_hidden())


func test_hidden_ends_when_the_form_is_replaced() -> void:
	var w := _world()
	_start(w)
	assert_true(w.is_hidden())
	# A second form of the same group (a caller bypassing admission) replaces the first; this one hides nobody.
	w.book.defs["plain_form"] = w.book.defs[KEY].duplicate(true)
	w.book.defs.plain_form.erase("buff")
	w.book.defs.plain_form.skill_id = 9991003
	w.book.skill_imgs["999"].skill["9991003"] = {"level": {"1": {"damage": DAMAGE, "time": 2}}}
	w.loadout.add_skill("plain_form")
	w.runner.forms.start(w, "plain_form", w.loadout.stats("plain_form"))
	assert_true(w.drain_events().has({"type": "form_ended", "skill": KEY, "skill_id": 9991001, "reason": "replaced"}))
	assert_false(w.is_hidden(), "the replaced form took its Hidden state with it")
	# The same form restarted replaces its own window and is Hidden again with a fresh clock.
	_start(w)
	_tick(w, 60)
	_start(w)
	assert_true(w.is_hidden())
	assert_near(float(w.runner.forms.snapshot()[0].remaining), 2.0, 0.001)
	assert_eq(w.runner.forms.snapshot().size(), 1)


func test_hidden_is_kept_across_a_map_transfer_like_any_buff() -> void:
	var w := _world()
	_start(w)
	_tick(w, 30)
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.forms.snapshot().size(), 1)
	assert_true(w.is_hidden(), "the transfer neither ends nor skips the window")
	_tick(w, 1)
	assert_true(bool(w.player_state.hidden))
	var events := _tick(w, 95)
	assert_false(w.is_hidden(), "and it still ends on its own clock after the arrival")
	assert_true(events.has({"type": "form_ended", "skill": KEY, "skill_id": 9991001, "reason": "expired"}))


func test_the_buff_row_and_countdown_show_the_hidden_form() -> void:
	var w := _world()
	_start(w)
	_tick(w, 1)
	var rows: Array = w.player_state.buffs
	assert_eq(rows.size(), 1)
	assert_eq(String(rows[0].skill), KEY)
	assert_true(bool(rows[0].hidden))
	assert_near(float(rows[0].remaining), 2.0, 0.05)
	var row := HudBuffRow.new()
	row.update(w.player_state, {})
	var shown := row.displayed()
	assert_eq(shown.size(), 1, "one slot for the form's buff")
	assert_eq(String(shown[0].skill), KEY)
	assert_eq(int(shown[0].remaining_seconds), 2)
	row.free()


func test_the_speed_contribution_applies_and_drops_with_the_window() -> void:
	var w := _world()
	var speed := w.player_speed_stat()
	assert_near(w.loadout.stats(KEY).buff_value, SPEED, 0.001)
	_start(w)
	_tick(w, 1)
	assert_near(w.player_speed_stat() - speed, SPEED, 0.001, "the penalty applies while Hidden")
	_tick(w, 130)
	assert_near(w.player_speed_stat(), speed, 0.001, "and is gone with the window")
	# The rank table feeds the penalty (Dark Sight's -26 -> 0 by rank): rank 2 here halves it.
	w.loadout.ranks[KEY] = 2
	_start(w)
	_tick(w, 1)
	assert_near(w.player_speed_stat() - speed, SPEED / 2.0, 0.001)


# --- what Hidden silences and what it does not -----------------------------------------------------------------------

func test_a_pool_attack_is_silenced_for_the_window_and_casts_again_after() -> void:
	var w := _world()
	assert_true(w.learn_skill("three_snails"))
	_mob(w, 260.0)
	_start(w)
	var events := _tick(w, 110)
	assert_true(_of(events, "cast").is_empty(), "no attack casts while Hidden")
	assert_true(_of(events, "mob_hit").is_empty(), "and nothing is hit")
	events = _tick(w, 30)
	assert_false(_of(events, "cast").filter(func(e: Dictionary) -> bool: return e.skill == "three_snails").is_empty(),
		"it casts as soon as the window is over")


func test_the_silence_leaves_the_pool_cooldown_running() -> void:
	var control := _world()
	var w := _world()
	for world: RunWorld in [control, w]:
		world.learn_skill("three_snails")
		_mob(world, 260.0)
		world.runner.cooldowns.three_snails = 1.5
	_start(w)
	_tick(w, 60)
	_tick(control, 60)
	assert_near(float(w.runner.cooldowns.three_snails), float(control.runner.cooldowns.three_snails), 1e-6,
		"Hidden neither freezes nor resets the cooldown")
	assert_near(float(w.runner.cooldowns.three_snails), 0.5, 0.02)
	# Ready during the window, silent; the window's end lets it go with nothing owed.
	_tick(w, 50)
	assert_true(float(w.runner.cooldowns.three_snails) <= 0.0)
	assert_true(w.is_hidden())
	assert_true(_of(w.drain_events(), "cast").filter(func(e: Dictionary) -> bool: return e.skill == "three_snails").is_empty())


func test_a_monster_in_range_stops_chasing_and_no_hit_window_starts() -> void:
	var window := 6.0
	var control := _world()
	var cm := _mob(control, 100.0, SNAIL, 60.0)
	control.swarm.facing[cm] = -1
	_tick(control, 60)
	assert_true(control.swarm.x[cm] > 100.0, "control: the mob turns and walks at the character")
	var w := _world(window)
	var m := _mob(w, 100.0, SNAIL, 60.0)
	w.swarm.facing[m] = -1
	_start(w)
	var hp := int(w.player_state.hp)
	var events := _tick(w, 60)
	assert_true(w.swarm.x[m] < 100.0, "Hidden: it keeps walking the way it faced")
	assert_eq(int(w.swarm.facing[m]), -1)
	# A monster standing on the character hurts nobody, and the hit window never opens.
	_mob(w, w.player.pos.x)
	events.append_array(_tick(w, 60))
	assert_true(_of(events, "player_hit").is_empty())
	assert_eq(w.take_hit(100.0, false, "", w.player.pos + Vector2(5, 0)), 0)
	assert_eq(int(w.player_state.hp), hp)
	assert_eq(w.upkeep.invincible_t, 0.0, "no hit window was started")


# --- the sub driver's Hidden gate --------------------------------------------------------------------------------------

func test_a_sub_without_the_flag_waits_through_the_window() -> void:
	var w := _world()
	_sub(w)
	_mob(w, 240.0)
	_mob(w, 250.0)
	_start(w)
	_tick(w, 110)
	assert_eq(w.runner.casts, 0, "an attack sub is silenced like every attack")
	var sub: Dictionary = w.runner.forms.snapshot()[0].subs[0]
	assert_false(bool(sub.done))
	assert_near(float(sub.next), 0.5, 1e-6, "due and not consumed: it waits, it does not skip ahead")
	# The same sub on a form that is not Hidden casts on schedule: the gate, not the sub, is what waited.
	var open := _world()
	_sub(open)
	open.book.defs[KEY].erase("buff")
	_mob(open, 240.0)
	_mob(open, 250.0)
	_start(open)
	_tick(open, 40)
	assert_eq(open.runner.casts, 1, "control: the unhidden form's sub casts at first_after")


func test_a_sub_with_the_flag_casts_at_first_after_and_every_interval() -> void:
	var w := _world()
	_sub(w, {"ignores_hidden": true})
	_mob(w, 240.0)
	_mob(w, 250.0)
	_start(w)
	assert_true(w.is_hidden())
	_tick(w, 29)
	assert_eq(w.runner.casts, 0, "before first_after (0.5 s)")
	_tick(w, 2)
	assert_eq(w.runner.casts, 1, "at first_after")
	_tick(w, 58)
	assert_eq(w.runner.casts, 1, "and not before the interval")
	_tick(w, 3)
	assert_eq(w.runner.casts, 2, "every interval (1.0 s) after the cast")
	assert_true(w.is_hidden(), "the sub does not break the Hidden state")
	_tick(w, 60)
	assert_eq(w.runner.casts, 2, "the third would be due at 2.5 s, after the 2 s window")
	assert_false(w.is_hidden())


func test_the_flagged_sub_keeps_the_drivers_other_rules() -> void:
	# Its own cast rule: two targets or it waits.
	var w := _world()
	_sub(w, {"ignores_hidden": true})
	w.loadout.ranks[KEY] = 2
	w.loadout.add_skill_mod(KEY, "damage", "mul", 2.0)
	var m := _mob(w, 240.0)
	_start(w)
	_tick(w, 45)
	assert_eq(w.runner.casts, 0, "one monster is below the sub's own minimum of two targets")
	_mob(w, 250.0)
	var before := w.swarm.hp[m]
	_tick(w, 1)
	assert_eq(w.runner.casts, 1, "due, it casts the tick it is admitted")
	# Rank 2 maps to sub level 3 (30 fixed) * the parent's damage modifier 2 * the form's damage effect 1.5 = 90.
	assert_near(before - w.swarm.hp[m], 90.0, 0.01, "rank through its own table, parent's modifier and `damage` effect")
	# Its HP price is paid and refused like any sub's.
	var priced := _world()
	_sub(priced, {"ignores_hidden": true})
	priced.book.skill_imgs["999"].skill["9991002"].level["1"]["hpCon"] = 5
	_mob(priced, 240.0)
	_mob(priced, 250.0)
	_start(priced)
	priced.spend_hp(int(priced.player_state.hp) - 5)
	_tick(priced, 45)
	assert_eq(priced.runner.casts, 0, "cannot spend the last HP")
	priced.restore_player("hp", 30, "test")
	_tick(priced, 1)
	assert_eq(priced.runner.casts, 1)
	# A once sub casts once.
	var once := _world()
	_sub(once, {"ignores_hidden": true, "once": true})
	_mob(once, 240.0)
	_mob(once, 250.0)
	_start(once)
	_tick(once, 115)
	assert_eq(once.runner.casts, 1)


func test_a_flagged_attack_sub_hits_a_hidden_character_target_like_any_cast() -> void:
	var w := _world()
	_sub(w, {"ignores_hidden": true})
	assert_true(w.learn_skill("three_snails"))
	var a := _mob(w, 240.0)
	_mob(w, 250.0)
	w.swarm.mob_kind(a).elements = {}
	_start(w)
	var events := _tick(w, 40)
	assert_eq(w.runner.casts, 1, "only the sub: the pool attack stays silenced in the same window")
	assert_eq(_of(events, "cast").filter(func(e: Dictionary) -> bool: return e.skill == "three_snails").size(), 0)
	assert_false(_of(events, "mob_hit").is_empty(), "the sub's hits are ordinary hits")


# --- schema ------------------------------------------------------------------------------------------------------------

func test_validation_accepts_the_flag_and_rejects_a_misplaced_or_non_boolean_one() -> void:
	var w := _world()
	_sub(w, {"ignores_hidden": true})
	var defs := {KEY: w.book.defs[KEY], SUB: w.book.defs[SUB]}
	assert_true(PlayerForms.validation_errors(defs).is_empty())
	defs[KEY].form.subs[0].ignores_hidden = "yes"
	assert_true("ignores_hidden must be boolean" in " ".join(PlayerForms.validation_errors(defs)))
	defs[KEY].form.subs[0].ignores_hidden = 1
	assert_false(PlayerForms.validation_errors(defs).is_empty(), "a number is not a boolean")
	defs[KEY].form.subs[0].ignores_hidden = true
	# The flag belongs on a form's subs entry only: not on a skill definition, a form block or a non-sub.
	w.book.defs["plain"] = {"skill_id": 9991009, "kind": "instant", "slot": "active", "damage": "fixed", "ignores_hidden": true}
	defs["plain"] = w.book.defs.plain
	assert_true("plain.ignores_hidden" in " ".join(PlayerForms.validation_errors(defs)))
	defs.erase("plain")
	defs[SUB].ignores_hidden = true
	assert_true("hide_sub.ignores_hidden" in " ".join(PlayerForms.validation_errors(defs)), "on the sub's own definition")
	defs[SUB].erase("ignores_hidden")
	defs[KEY].form.ignores_hidden = true
	assert_true("hide_form.form.ignores_hidden" in " ".join(PlayerForms.validation_errors(defs)), "on the form block")
	defs[KEY].form.erase("ignores_hidden")
	assert_true(PlayerForms.validation_errors(defs).is_empty())


func test_player_forms_has_no_hidden_effect_and_no_shipped_form_lists_one() -> void:
	var keys := PlayerForms.EFFECTS.keys()
	keys.sort()
	assert_eq(keys, ["damage", "element"], "Hidden is a buff block, not an effect key")
	var w := _world()
	w.book.defs[KEY].form.effects["hidden"] = true
	assert_true("effects.hidden" in " ".join(PlayerForms.validation_errors({KEY: w.book.defs[KEY]})),
		"a form that lists effects.hidden is a schema error")
	var data := DataRepo.load_all()
	for key: String in data.skills.skills:
		var d: Dictionary = data.skills.skills[key]
		if String(d.get("kind", "")) == "form":
			assert_false(d.form.get("effects", {}).has("hidden"), "%s lists no effects.hidden" % key)


# --- a world without a hidden form is untouched ------------------------------------------------------------------------

func test_a_form_without_the_flag_or_the_buff_is_byte_identical_to_one_with_the_flag_false() -> void:
	var runs: Array = []
	for explicit in [false, true]:
		var w := _world()
		w.book.defs[KEY].erase("buff")
		_sub(w, {"ignores_hidden": false} if explicit else {})
		w.learn_skill("three_snails")
		_mob(w, 240.0)
		_mob(w, 250.0)
		_start(w)
		var trace: Array = _tick(w, 200)
		runs.append({"events": trace, "rng": w.rng.state, "hp": w.swarm.hp.duplicate(), "casts": w.runner.casts,
			"hidden": w.is_hidden()})
	assert_eq(runs[0], runs[1], "an explicit false is the default, event for event")
	assert_false(runs[0].hidden)
	assert_true(runs[0].casts > 0)


func test_a_hidden_form_draws_no_rng_while_it_runs() -> void:
	var w := _world()
	_sub(w, {"ignores_hidden": true})
	_mob(w, 240.0)
	_mob(w, 250.0)
	var control := _world()
	_sub(control, {"ignores_hidden": true})
	control.book.defs[KEY].erase("buff")
	_mob(control, 240.0)
	_mob(control, 250.0)
	_start(w)
	_start(control)
	_tick(w, 130)
	_tick(control, 130)
	assert_eq(w.rng.state, control.rng.state, "the Hidden state adds no draw")


# --- card text ---------------------------------------------------------------------------------------------------------

func test_card_text_of_a_hidden_form_names_the_window_and_its_subs() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	assert_eq(text.level_line(KEY, 1, w.loadout.stats(KEY)).split("\n")[-1],
		"Hidden for 2 s: monsters ignore you and you cannot attack.")
	_sub(w, {"ignores_hidden": true})
	var line := text.level_line(KEY, 1, w.loadout.stats(KEY))
	assert_true("Hidden for 2 s: monsters ignore you and you cannot attack except with Hide Sub. Hide Sub after 0.5 s, every 1 s (Lv1)" in line, line)
	assert_false("Transforms" in line or "Charges" in line, line)
	# A sub that does not ignore Hidden is listed as a sub but is not what the character may attack with.
	w.book.defs[KEY].form.subs[0].ignores_hidden = false
	line = text.level_line(KEY, 1, w.loadout.stats(KEY))
	assert_true("cannot attack. Hide Sub after" in line, line)


func test_card_text_of_a_form_that_does_not_hide_is_unchanged() -> void:
	var w := _world()
	w.book.defs[KEY].erase("buff")
	assert_eq(SkillText.new(w.book).level_line(KEY, 1, w.loadout.stats(KEY)).split("\n")[-1],
		"Transforms you for 2 s: attacks +50%.")
