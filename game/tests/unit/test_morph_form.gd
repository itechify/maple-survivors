extends TestCase
## A morph form (Buccaneer BC3 #415, spec #412 BU-9): the morph rides the form's ordinary `buff` block (`morph_field`,
## `stat`/`field`, `effects`) through PlayerForms.start -> PlayerBuffs.start, so PlayerForms needs no `morph` effect key.
## Everything here is a synthetic form (made-up job 999, skill 9991001+, Morph ids 7771/7772): no Buccaneer data and no
## asset cache. test_player_forms stays the contract of the seam itself; this file is the template Shadower copies.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "morph_form"
const MORPH_A := 7771
const MORPH_B := 7772
## The synthetic level-1 numbers (Skill.wz-shaped): defence, speed and jump points, the form's damage percent.
const PDD := 20.0
const MDD := 16.0
const SPEED := 40.0
const JUMP := 20.0
const DAMAGE := 150.0


func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	data.balance.player.hp = 1000
	data.balance.regen.hp = 0
	var w := RunWorld.new(RF.setup("quiet", 415, data))
	w.progression.job_id = 999
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.book.defs[KEY] = {"skill_id": 9991001, "book": "999", "kind": "form", "slot": "active", "damage": "none",
		"cooldown": 3.0, "ranks": [1], "cast": {"rule": "form", "mob_within": 400}, "icon": "",
		"buff": {"morph_field": "morph", "stat": "pdd", "field": "pdd", "duration_field": "time",
			"effects": [{"stat": "mdd", "field": "mdd"}, {"stat": "speed", "field": "speed"}, {"stat": "jump", "field": "jump"}]},
		"form": {"duration": 2.0, "exclusive_group": "morph", "effects": {}, "subs": []}}
	w.book.skill_imgs["999"] = {"skill": {"9991001": {"level": {"1": {"morph": MORPH_A, "pdd": PDD, "mdd": MDD,
		"speed": SPEED, "jump": JUMP, "damage": DAMAGE, "time": 2}}}}}
	w.loadout.add_skill(KEY)
	w.drain_events()
	return w


## A second morph form in another exclusion group (two morph buffs at once), wearing `morph`.
func _twin(w: RunWorld, key: String, morph: int) -> void:
	w.book.defs[key] = w.book.defs[KEY].duplicate(true)
	w.book.defs[key].skill_id = 9991002
	w.book.defs[key].form.exclusive_group = "morph_b"
	w.book.skill_imgs["999"].skill["9991002"] = {"level": {"1": {"morph": morph, "pdd": 5.0, "mdd": 5.0,
		"speed": 5.0, "jump": 5.0, "damage": DAMAGE, "time": 2}}}
	w.loadout.add_skill(key)


func _start(w: RunWorld, key: String = KEY) -> void:
	w.runner.forms.start(w, key, w.loadout.stats(key))


func _tick(w: RunWorld, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func test_the_morph_id_comes_from_the_buff_block_and_is_set_while_the_form_lives() -> void:
	var w := _world()
	assert_eq(w.loadout.stats(KEY).morph, MORPH_A, "Loadout resolves morph_field from the level numbers")
	assert_eq(w.morph_id(), 0)
	_start(w)
	assert_eq(w.morph_id(), MORPH_A)
	assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "form_started").size(), 1)
	_tick(w, 1)
	assert_eq(int(w.player_state.morph), MORPH_A, "the presentation reads it from player_state")


func test_the_morph_is_cleared_when_the_form_ends_for_each_reason() -> void:
	# Expired: the window and the buff run out on the same tick.
	var w := _world()
	_start(w)
	var events := _tick(w, 130)
	assert_true(events.has({"type": "form_ended", "skill": KEY, "skill_id": 9991001, "reason": "expired"}))
	assert_eq(w.morph_id(), 0)
	assert_eq(int(w.player_state.morph), 0)
	# Replaced: a second start in the same group ends the first and the new morph shows.
	w = _world()
	_start(w)
	w.book.skill_imgs["999"].skill["9991001"].level["1"].morph = MORPH_B
	_start(w)
	assert_true(w.drain_events().has({"type": "form_ended", "skill": KEY, "skill_id": 9991001, "reason": "replaced"}))
	assert_eq(w.morph_id(), MORPH_B, "only the new window's morph")
	# Died: the death clears every window.
	w = _world()
	_start(w)
	w.state = RunWorld.DEAD
	w.runner.tick_cooldowns(DT, w)
	assert_true(w.drain_events().has({"type": "form_ended", "skill": KEY, "skill_id": 9991001, "reason": "died"}))
	assert_eq(w.morph_id(), 0)


func test_the_morph_is_kept_across_a_map_transfer() -> void:
	var w := _world()
	_start(w)
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.forms.snapshot().size(), 1)
	assert_eq(w.morph_id(), MORPH_A)
	_tick(w, 1)
	assert_eq(int(w.player_state.morph), MORPH_A)


func test_the_buff_row_shows_the_form_with_its_morph() -> void:
	var w := _world()
	_start(w)
	_tick(w, 1)
	var rows: Array = w.player_state.buffs
	assert_eq(rows.size(), 1)
	assert_eq(String(rows[0].skill), KEY)
	assert_eq(int(rows[0].morph), MORPH_A)
	assert_near(float(rows[0].remaining), 2.0, 0.05)
	var row := HudBuffRow.new()
	row.update(w.player_state, {})
	var shown := row.displayed()
	assert_eq(shown.size(), 1, "one slot for the form's buff")
	assert_eq(String(shown[0].skill), KEY)
	assert_eq(int(shown[0].remaining_seconds), 2)
	row.free()


func test_a_morphed_caster_is_not_hidden_still_casts_and_still_takes_hits() -> void:
	var w := _world()
	_start(w)
	assert_false(w.is_hidden(), "a morph without `hidden` is not Hidden")
	assert_true(w.can_cast())
	assert_true(w.learn_skill("three_snails"))
	var m := RF.put_mob(w, 100100, 260.0, 190.0, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	var events := _tick(w, 90)
	assert_false(_of(events, "cast").filter(func(e: Dictionary) -> bool: return e.skill == "three_snails").is_empty(),
		"a morphed caster casts")
	assert_false(_of(events, "mob_hit").is_empty(), "and hits")
	var hp := int(w.player_state.hp)
	var dealt := w.take_hit(300.0, false, "", w.player.pos + Vector2(10, 0))
	assert_true(dealt > 0, "and takes hits (no Hidden immunity)")
	_tick(w, 1)
	assert_eq(int(w.player_state.hp), hp - dealt, "the hit cost HP")
	assert_eq(w.morph_id(), MORPH_A, "taking a hit does not end the form")


func test_the_buff_stats_move_while_it_lives_and_return_after() -> void:
	var w := _world()
	var pdd := float(w.hit_defense().pdd)
	var mdd := float(w.hit_defense().mdd)
	var speed := w.player_speed_stat()
	var jump := w.player.jump_stat
	_start(w)
	_tick(w, 1)
	assert_near(float(w.hit_defense().pdd) - pdd, PDD, 0.001)
	assert_near(float(w.hit_defense().mdd) - mdd, MDD, 0.001)
	assert_near(w.player_speed_stat() - speed, SPEED, 0.001)
	assert_eq(w.player.jump_stat - jump, int(JUMP))
	_tick(w, 130)
	assert_eq(w.morph_id(), 0)
	assert_near(float(w.hit_defense().pdd), pdd, 0.001)
	assert_near(float(w.hit_defense().mdd), mdd, 0.001)
	assert_near(w.player_speed_stat(), speed, 0.001)
	assert_eq(w.player.jump_stat, jump)


func test_speed_and_jump_stop_at_their_v83_caps() -> void:
	var w := _world()
	w.book.skill_imgs["999"].skill["9991001"].level["1"].speed = 300.0
	w.book.skill_imgs["999"].skill["9991001"].level["1"].jump = 300.0
	_start(w)
	_tick(w, 1)
	assert_eq(w.player.speed_stat, Equipment.SPEED_CAP)
	assert_eq(w.player.jump_stat, Equipment.JUMP_CAP)
	_tick(w, 130)
	assert_eq(w.player.speed_stat, 100)
	assert_eq(w.player.jump_stat, 100)


func test_two_morph_buffs_resolve_to_the_first_started() -> void:
	var w := _world()
	_twin(w, "morph_form_b", MORPH_B)
	_start(w, "morph_form_b")
	_start(w)
	assert_eq(w.runner.forms.snapshot().size(), 2, "two groups, two windows")
	assert_eq(w.morph_id(), MORPH_B, "the first started wins")
	w.buffs.end("morph_form_b", w.events)
	assert_eq(w.morph_id(), MORPH_A, "the other shows once the first ends")


func test_the_forms_damage_modifier_still_multiplies_its_subs() -> void:
	var w := _world()
	w.book.defs[KEY].form.effects = {"damage": {"field": "damage"}}
	w.book.defs["morph_sub"] = {"skill_id": 9991003, "book": "999", "kind": "instant", "slot": "form_sub",
		"form_sub_of": [KEY], "ranks": [1], "damage": "fixed", "range": 150, "cooldown": 30,
		"cast": {"rule": "range_around", "min_targets": 1}}
	w.book.skill_imgs["999"].skill["9991003"] = {"level": {"1": {"fixdamage": 10, "range": 150, "mobCount": 1}}}
	w.book.defs[KEY].form.subs = [{"skill": "morph_sub", "first_after": 0.1, "interval": 5.0}]
	var m := RF.put_mob(w, 100100, 240.0, 190.0, 100000.0)
	w.swarm.hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_start(w)
	var before := w.swarm.hp[m]
	for i in 8:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(before - w.swarm.hp[m], 15.0, 0.01, "10 fixed * the form's 150% (the morph is on the same form)")
	assert_eq(w.morph_id(), MORPH_A)


func test_player_forms_has_no_morph_effect_and_no_shipped_form_lists_one() -> void:
	var keys := PlayerForms.EFFECTS.keys()
	keys.sort()
	assert_eq(keys, ["damage", "element"], "the morph is a buff block, not an effect key")
	var w := _world()
	w.book.defs[KEY].form.effects["morph"] = MORPH_A
	assert_true("effects.morph" in " ".join(PlayerForms.validation_errors({KEY: w.book.defs[KEY]})),
		"a form that lists effects.morph is a schema error")
	var data := DataRepo.load_all()
	# Every form shipped today or added later (the Paladin Charges, Buccaneer's morphs): none lists an effects.morph.
	for key: String in data.skills.skills:
		var d: Dictionary = data.skills.skills[key]
		if String(d.get("kind", "")) == "form":
			assert_false(d.form.get("effects", {}).has("morph"), "%s lists no effects.morph" % key)


# --- card text for a form without an element (BC3 #415) ---------------------------------------------------------------

func test_card_text_of_a_form_without_an_element_names_the_buff_stats() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	var line := text.level_line(KEY, 1, w.loadout.stats(KEY))
	assert_eq(line.split("\n")[-1], "Transforms you for 2 s: weapon defence +20, magic defence +16, speed +40, jump +20.")
	assert_false("Charges" in line, line)
	assert_false("fire" in line, line)
	# Equal defences read as one number; a stat the buff block does not feed is not named.
	w.book.skill_imgs["999"].skill["9991001"].level["1"].mdd = PDD
	w.book.skill_imgs["999"].skill["9991001"].level["1"].jump = 0.0
	assert_eq(text.level_line(KEY, 1, w.loadout.stats(KEY)).split("\n")[-1],
		"Transforms you for 2 s: defence +20, speed +40.")


func test_card_text_of_a_form_that_feeds_no_stat_still_reads() -> void:
	var w := _world()
	w.book.defs[KEY].erase("buff")
	assert_eq(SkillText.new(w.book).level_line(KEY, 1, w.loadout.stats(KEY)).split("\n")[-1], "Transforms you for 2 s.")


func test_card_text_of_a_form_without_an_element_keeps_the_sub_lines() -> void:
	var w := _world()
	w.book.defs["morph_sub"] = {"skill_id": 9991003, "book": "999", "kind": "instant", "slot": "form_sub",
		"form_sub_of": [KEY], "ranks": [1], "damage": "fixed", "range": 150, "cooldown": 30,
		"cast": {"rule": "range_around", "min_targets": 1}}
	w.book.skill_imgs["999"].skill["9991003"] = {"level": {"1": {"fixdamage": 10, "range": 150, "mobCount": 2, "hpCon": 5}}}
	w.book.defs[KEY].form.subs = [{"skill": "morph_sub", "first_after": 0.1, "interval": 3.0}]
	var line := SkillText.new(w.book).level_line(KEY, 1, w.loadout.stats(KEY))
	assert_true(line.contains("jump +20. Morph Sub after 0.1 s, every 3 s (Lv1)"), line)
	assert_true("Base 10 fixed damage" in line and "5 HP" in line, line)


func test_card_text_of_an_element_form_is_unchanged() -> void:
	var w := _world()
	w.book.defs[KEY].form.effects = {"element": "f", "damage": {"field": "damage"}}
	var line := SkillText.new(w.book).level_line(KEY, 1, w.loadout.stats(KEY))
	assert_eq(line.split("\n")[-1], "Charges your weapon for 2 s: your attacks deal fire damage (+50%)")
	w.book.defs[KEY].form.effects = {"element": "i"}
	line = SkillText.new(w.book).level_line(KEY, 1, w.loadout.stats(KEY))
	assert_eq(line.split("\n")[-1], "Charges your weapon for 2 s: your attacks deal ice damage (+0%)")


func test_card_text_of_a_form_with_damage_but_no_element_does_not_name_an_element() -> void:
	var w := _world()
	w.book.defs[KEY].form.effects = {"damage": {"field": "damage"}}
	var line := SkillText.new(w.book).level_line(KEY, 1, w.loadout.stats(KEY)).split("\n")[-1]
	assert_eq(line, "Transforms you for 2 s: attacks +50%, weapon defence +20, magic defence +16, speed +40, jump +20.")
