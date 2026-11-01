extends TestCase
## The safe zone (M18, spec #425 SH4, docs/GAME_DESIGN.md 7.132): `SafeZone`, the `safe_zone` cast rule, the `take_hit`
## negation, the `zone_time` modifier and the three events, on a synthetic skill (made-up book 999, skill 9992001) in a quiet
## world with seeded RNG and fixed dt. No Shadower data or real art is involved; Smokescreen (SH12) copies this shape.

const SZ := preload("res://tests/fixtures/safe_zone_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const ATTACK := 100.0
const TOUCH := {"accuracy": 100000.0, "source_kind": "touch"}


func _run(w: RunWorld, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


## Places the cloud at the character's body at rank `rank` and returns the world.
func _placed(rank := 1, p_seed := 429) -> RunWorld:
	var w := SZ.world(p_seed)
	w.loadout.ranks[SZ.KEY] = rank
	w.safe_zones.place(w, SZ.KEY, w.loadout.stats(SZ.KEY), w.cast_origin())
	w.drain_events()
	return w


func _hit(w: RunWorld, source := TOUCH) -> int:
	return w.take_hit(ATTACK, false, "", w.player.pos + Vector2(-30, 0), source)


# --- placement --------------------------------------------------------------------------------------------------------

func test_the_box_is_the_canonical_box_by_rank() -> void:
	var w := SZ.world()
	for case: Array in [[1, 120.0, 90.0], [2, 150.0, 113.0], [3, 200.0, 150.0]]:
		w.loadout.ranks[SZ.KEY] = case[0]
		var st := w.loadout.stats(SZ.KEY)
		assert_eq(st.box, Rect2(-case[1], -case[2], case[1] * 2.0, case[2] * 2.0), "rank %d" % case[0])
		w.safe_zones.place(w, SZ.KEY, st, w.cast_origin())
		var started: Dictionary = SZ.of(w.drain_events(), "safe_zone_started")[0]
		assert_eq(started.size, Vector2(case[1] * 2.0, case[2] * 2.0))
		assert_eq(started.pos, w.cast_origin() + Vector2(-case[1], -case[2]), "top-left corner, anchored at the cast origin")
		assert_eq(w.safe_zones.rect_of(SZ.KEY), Rect2(started.pos, started.size))


func test_the_area_modifier_scales_the_box() -> void:
	var w := SZ.world()
	w.loadout.add_skill_mod(SZ.KEY, "area", "mul", 1.2)
	var st := w.loadout.stats(SZ.KEY)
	assert_near((st.box as Rect2).size.x, 288.0, 1e-3)
	assert_near((st.box as Rect2).size.y, 216.0, 1e-3)
	w.safe_zones.place(w, SZ.KEY, st, w.cast_origin())
	assert_near(w.safe_zones.rect_of(SZ.KEY).size.x, 288.0, 1e-3)
	assert_near(w.safe_zones.rect_of(SZ.KEY).get_center().x, w.cast_origin().x, 1e-3, "still centred on the cast")


func test_the_zone_stays_where_the_cast_stood() -> void:
	var w := _placed()
	var rect := w.safe_zones.rect_of(SZ.KEY)
	RF.place_player(w, 900)
	_run(w, 30)
	assert_eq(w.safe_zones.rect_of(SZ.KEY), rect, "the cloud does not follow the character")
	assert_true(w.safe_zones.negates(Vector2(400, 160)))
	assert_false(w.safe_zones.negates(Vector2(900, 160)))


func test_the_life_is_the_duration_times_zone_time_read_at_placement() -> void:
	var w := SZ.world()
	assert_near(float(w.loadout.stats(SZ.KEY).safe_zone_duration), 6.0, 1e-9)
	assert_near(float(w.loadout.stats(SZ.KEY).zone_time), 1.0, 1e-9)
	w.loadout.add_skill_mod(SZ.KEY, "zone_time", "mul", 1.5)
	assert_near(float(w.loadout.stats(SZ.KEY).safe_zone_duration), 9.0, 1e-9, "a 9 s cloud")
	w.safe_zones.place(w, SZ.KEY, w.loadout.stats(SZ.KEY), w.cast_origin())
	assert_near(float(SZ.of(w.drain_events(), "safe_zone_started")[0].duration), 9.0, 1e-9)
	w.loadout.add_skill_mod(SZ.KEY, "zone_time", "mul", 2.0)
	assert_near(float(w.safe_zones.snapshot()[0].total), 9.0, 1e-9, "a placed zone ignores a later zone_time")
	assert_near(float(w.safe_zones.snapshot()[0].left), 9.0, 1e-9)


func test_a_skill_without_the_block_gains_no_keys() -> void:
	var w := RF.quiet_world()
	for key: String in w.loadout.order:
		assert_false(w.loadout.stats(key).has("zone_time"), key)
		assert_false(w.loadout.stats(key).has("safe_zone_duration"), key)


# --- admission --------------------------------------------------------------------------------------------------------

func test_it_waits_with_its_cooldown_at_zero_until_enough_monsters_are_near() -> void:
	var w := SZ.world()
	SZ.mob(w, 460.0)
	SZ.mob(w, 490.0)
	SZ.mob(w, 900.0) # the third is out of the 250 px reach
	_run(w, 120)
	assert_eq(w.runner.casts, 0, "two near monsters are not enough")
	assert_true(float(w.runner.cooldowns[SZ.KEY]) <= 0.0, "nothing was spent: the cooldown is at 0 and waiting")
	assert_true(w.safe_zones.is_empty())
	SZ.mob(w, 520.0)
	var events := _run(w, 3)
	assert_eq(w.runner.casts, 1, "the third near monster admits the cast on the next tick")
	assert_eq(SZ.of(events, "safe_zone_started").size(), 1)
	assert_eq(SZ.of(events, "cast").size(), 1)
	assert_near(float(w.runner.cooldowns[SZ.KEY]), 24.0, 0.1, "the 24 s cooldown starts")


func test_the_reach_is_measured_to_the_body_centre() -> void:
	var w := SZ.world()
	SZ.mob(w, 560.0)
	SZ.mob(w, 600.0)
	var third := SZ.mob(w, 640.0)
	var st := w.loadout.stats(SZ.KEY)
	var centre := w.mob_center(third)
	assert_true(w.safe_zones.admits(w, SZ.KEY, st, centre - Vector2(249.5, 0.0)), "just inside 250 px")
	assert_false(w.safe_zones.admits(w, SZ.KEY, st, centre - Vector2(250.5, 0.0)), "just outside: the third is out of reach")


func test_it_does_not_cast_again_while_the_character_stands_inside_its_live_zone() -> void:
	var w := SZ.world()
	SZ.crowd(w)
	_run(w, 3)
	assert_eq(w.runner.casts, 1)
	w.runner.cooldowns[SZ.KEY] = 0.0 # the cooldown is not what refuses it
	_run(w, 5)
	assert_eq(w.runner.casts, 1, "inside its own live zone it waits")
	assert_true(float(w.runner.cooldowns[SZ.KEY]) <= 0.0, "with the cooldown still at 0")
	# Out of the box (but the cloud still live) it admits again and replaces the cloud.
	RF.place_player(w, 400.0 + 500.0)
	SZ.crowd(w)
	var events := _run(w, 3)
	assert_eq(w.runner.casts, 2)
	var ended := SZ.of(events, "safe_zone_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].reason, "replaced")
	assert_eq(w.safe_zones.snapshot().size(), 1, "one zone per skill")


func test_the_cast_rule_is_not_an_attack_so_hidden_does_not_silence_it() -> void:
	var st := SZ.world().loadout.stats(SZ.KEY)
	assert_false(SkillRunner.is_attack(st))
	assert_eq(SkillRunner.reach_of(st, SZ.world()), 0.0, "the bot reads no reach from it")


# --- negation ---------------------------------------------------------------------------------------------------------

func test_every_hit_source_is_negated_inside_and_changes_nothing() -> void:
	var sources := {
		"touch": {"mob": 3, "accuracy": 100000.0, "source_kind": "touch"},
		"mob_attack": {"mob": 3, "accuracy": 100000.0, "source_kind": "mob_attack"},
		"projectile": {"mob": 3, "accuracy": 100000.0, "boss": true, "source_kind": "projectile"},
		"attack": {"mob": 3, "accuracy": 100000.0, "boss": true, "boss_index": 0, "source_kind": "attack"},
	}
	for kind: String in sources:
		var w := _placed()
		var hp := float(w.player_state.hp)
		var pos := w.player.pos
		var rng_before := w.rng.state
		assert_eq(_hit(w, sources[kind]), 0, kind)
		var events := w.drain_events()
		assert_eq(float(w.player_state.hp), hp, "%s: HP unchanged" % kind)
		assert_eq(w.upkeep.invincible_t, 0.0, "%s: no hit window" % kind)
		assert_true(w.upkeep.may_knock_back(), "%s: no knock-back guard" % kind)
		assert_eq(w.player.pos, pos, "%s: not pushed" % kind)
		assert_eq(events.size(), 1, "%s: exactly one event" % kind)
		assert_eq(events[0].type, "hit_negated")
		assert_eq(events[0].skill, SZ.KEY)
		assert_eq(events[0].source, kind, "the source string is take_hit's source_kind")
		assert_eq(w.rng.state, rng_before, "%s: no RNG draw (not even the avoid roll)" % kind)


func test_a_hit_without_a_source_kind_reads_other() -> void:
	var w := _placed()
	assert_eq(w.take_hit(ATTACK, false, "", w.player.pos, {"accuracy": 100000.0}), 0)
	assert_eq(w.drain_events()[0].source, "other")


func test_a_hit_lands_the_tick_after_stepping_out_and_after_expiry() -> void:
	var w := _placed()
	assert_eq(_hit(w), 0)
	# Out of the box: just past the right edge (the box is +-120 around x = 400).
	var rect := w.safe_zones.rect_of(SZ.KEY)
	RF.place_player(w, rect.end.x + 20.0)
	w.drain_events()
	assert_true(_hit(w) > 0, "outside the cloud the hit lands")
	assert_eq(SZ.of(w.drain_events(), "player_hit").size(), 1)
	# Back in, still negated; then the cloud expires and the hit lands.
	RF.place_player(w, 400)
	w.upkeep.invincible_t = 0.0
	assert_eq(_hit(w), 0)
	_run(w, 359)
	assert_false(w.safe_zones.is_empty(), "6.0 s is 360 ticks: still live one tick before the end")
	assert_eq(_hit(w), 0)
	var events := _run(w, 1)
	assert_true(w.safe_zones.is_empty())
	assert_eq(SZ.of(events, "safe_zone_ended")[0].reason, "expired")
	assert_true(_hit(w) > 0, "after expiry the hit lands")


func test_the_body_centre_decides_not_the_feet() -> void:
	var w := _placed()
	var rect := w.safe_zones.rect_of(SZ.KEY)
	# Feet on the floor 30 px below the cast origin; put the body centre one pixel above the top edge by moving the zone.
	w.safe_zones.clear(w, "transferred")
	var st := w.loadout.stats(SZ.KEY)
	w.safe_zones.place(w, SZ.KEY, st, w.cast_origin() + Vector2(0, -(float(rect.size.y) * 0.5 + 40.0)))
	assert_true(w.safe_zones.rect_of(SZ.KEY).end.y < w.player_body_center().y, "the whole box is above the body centre")
	assert_true(_hit(w) > 0, "a cloud overhead does not protect")


func test_a_negated_contact_hit_in_a_real_tick_is_repeated_every_tick_without_damage() -> void:
	var w := _placed()
	var m := SZ.mob(w, 400.0)
	w.mob_kinds[w.swarm.kind[m]].body_attack = true
	w.mob_kinds[w.swarm.kind[m]].pad = 100000.0
	w.mob_kinds[w.swarm.kind[m]].acc = 100000.0
	var hp := float(w.player_state.hp)
	var events := _run(w, 10)
	assert_eq(float(w.player_state.hp), hp)
	assert_eq(SZ.of(events, "player_hit").size(), 0)
	assert_eq(SZ.of(events, "hit_negated").size(), 10, "no hit window, so the contact is negated each tick")
	assert_eq(SZ.of(events, "hit_negated")[0].source, "touch")
	assert_eq(SZ.of(_run(w, 349), "player_hit").size(), 0, "negated until the tick before the end (360 ticks in all)")
	assert_false(w.safe_zones.is_empty())
	var after := _run(w, 3)
	assert_true(w.safe_zones.is_empty())
	assert_true(SZ.of(after, "player_hit").size() >= 1, "from the tick the cloud ends the contact damages")
	assert_true(float(w.player_state.hp) < hp)


func test_a_monster_ball_inside_the_cloud_is_negated_and_used_up() -> void:
	var w := _placed()
	var from := w.player.pos + Vector2(-120.0, -30.0)
	w.mob_projectiles.spawn({"pos": from, "velocity": Vector2(300.0, 0.0), "range": 400.0, "visual": -1, "radius": 8.0,
		"mob": 0, "mob_id": SZ.SNAIL, "damage": 100.0, "multiplier": 1.0, "accuracy": 100000.0, "magic": false,
		"element": "", "hit": "", "source_pos": from, "ordinary": true})
	var hp := float(w.player_state.hp)
	var events := _run(w, 40)
	assert_eq(float(w.player_state.hp), hp)
	assert_eq(SZ.of(events, "player_hit").size(), 0)
	var negated := SZ.of(events, "hit_negated")
	assert_eq(negated.size(), 1)
	assert_eq(negated[0].source, "mob_attack", "an ordinary monster's ball")
	assert_eq(w.mob_projectiles.active_count(), 0, "the ball met the body and is spent")


## A targeted (type 1) pending attack of monster `m` due now, with hit art, aimed at the character.
func _pending(w: RunWorld, m: int) -> Dictionary:
	return {"type": 1, "magic": false, "mob": m, "mob_id": SZ.SNAIL, "damage": ATTACK, "element": "", "hit": "Mob.wz/x/hit",
		"pos": w.player.pos + Vector2(-30.0, 0.0), "attack": "attack1", "facing": 1, "area": Rect2(), "impact_time": 0.0,
		"effect_time": 0.0, "effect": "", "sound": "", "boss_index": -1, "elite": false, "dmg_mult": 1.0, "jump_attack": false,
		"effect_done": true, "impact_done": false}


func _hit_art(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_attack" and e.phase == "hit")


func test_a_negated_attack_and_a_negated_ball_play_no_hit_art() -> void:
	# The hit-window convention (no damage, no player_hit, no hit art) holds for a safe zone too (review #425, standards S3).
	var w := _placed()
	var m := SZ.mob(w, 520.0)
	w.drain_events()
	MobAttacks.service(_pending(w, m), w)
	var events := w.drain_events()
	assert_eq(SZ.of(events, "hit_negated").size(), 1, "the cloud turns the strike away")
	assert_true(_hit_art(events).is_empty(), "and the monster's hit art does not burst on the body")
	assert_false(SZ.of(events, "mob_attack").is_empty(), "the impact phase itself still plays")
	var from := w.player.pos + Vector2(-120.0, -30.0)
	var ball := {"pos": from, "velocity": Vector2(300.0, 0.0), "range": 400.0, "visual": -1, "radius": 8.0, "mob": m,
		"mob_id": SZ.SNAIL, "damage": 100.0, "multiplier": 1.0, "accuracy": 100000.0, "magic": false, "element": "",
		"hit": "Mob.wz/x/ballhit", "source_pos": from, "ordinary": true}
	w.mob_projectiles.spawn(ball)
	events = _run(w, 40)
	assert_eq(SZ.of(events, "hit_negated").size(), 1)
	assert_true(SZ.of(events, "mob_projectile_hit").is_empty(), "no ball burst on a negated hit")
	assert_eq(w.mob_projectiles.active_count(), 0, "the ball is still used up")
	# Control: with the cloud gone both play their art.
	w.safe_zones.clear(w, "transferred")
	w.drain_events()
	MobAttacks.service(_pending(w, m), w)
	assert_eq(_hit_art(w.drain_events()).size(), 1, "without a cloud the strike's hit art plays")
	w.mob_projectiles.spawn(ball)
	assert_eq(SZ.of(_run(w, 40), "mob_projectile_hit").size(), 1, "and so does the ball's")


func test_statuses_are_not_hits_and_are_not_negated() -> void:
	var w := _placed()
	w.hazards.spawn({"rect": Rect2(0, 0, 2000, 400), "born": 0.0, "until": 1000.0, "effect": GroundHazards.ICE})
	_run(w, 2)
	assert_true(w.mob_skills.statuses.is_active(MobSkillRunner.SKILL_SLOW, w.time), "a Slow mist still slows inside the cloud")
	var hp := float(w.player_state.hp)
	assert_true(w.take_poison(5, -1, 0) > 0, "poison still ticks")
	assert_true(float(w.player_state.hp) < hp)
	assert_eq(SZ.of(w.drain_events(), "hit_negated").size(), 0)


func test_god_and_hidden_keep_their_own_silence() -> void:
	var w := _placed()
	w.god = true
	assert_eq(_hit(w), 0)
	assert_eq(SZ.of(w.drain_events(), "hit_negated").size(), 0, "a guard that already refused it appends nothing")


func test_a_boss_reflect_is_negated_inside_the_cloud() -> void:
	var w := _placed()
	var hp := float(w.player_state.hp)
	var m := SZ.mob(w, 520.0)
	assert_false(w._hurt_by_reflect(m, 50), "the reflect does not land")
	assert_eq(float(w.player_state.hp), hp)
	assert_eq(SZ.of(w.drain_events(), "hit_negated")[0].source, "reflect")
	w.safe_zones.clear(w, "transferred")
	assert_true(w._hurt_by_reflect(m, 50), "without a cloud it lands")


# --- the zone's end ---------------------------------------------------------------------------------------------------

func test_a_recast_replaces_the_zone() -> void:
	var w := _placed()
	var st := w.loadout.stats(SZ.KEY)
	w.safe_zones.place(w, SZ.KEY, st, w.cast_origin() + Vector2(50, 0))
	var events := w.drain_events()
	assert_eq(events.map(func(e: Dictionary) -> String: return e.type), ["safe_zone_ended", "safe_zone_started"])
	assert_eq(events[0].reason, "replaced")
	assert_eq(w.safe_zones.snapshot().size(), 1)
	assert_near(float(w.safe_zones.snapshot()[0].left), 6.0, 1e-9, "the new one starts a fresh life")


func test_two_skills_keep_their_own_zones() -> void:
	var w := _placed()
	w.book.defs["test_cloud_b"] = w.book.defs[SZ.KEY].duplicate(true)
	w.book.defs["test_cloud_b"].skill_id = 9992002
	w.book.skill_imgs["999"].skill["9992002"] = w.book.skill_imgs["999"].skill[str(SZ.SKILL_ID)]
	w.learn_skill("test_cloud_b")
	w.safe_zones.place(w, "test_cloud_b", w.loadout.stats("test_cloud_b"), w.cast_origin() + Vector2(400, 0))
	assert_eq(w.safe_zones.snapshot().size(), 2)
	assert_true(w.safe_zones.negates(w.player_body_center()))
	assert_true(w.safe_zones.negates(w.cast_origin() + Vector2(400, 0)))
	assert_eq(SZ.of(w.drain_events(), "safe_zone_ended").size(), 0, "a different skill never replaces it")


func test_death_ends_the_zone() -> void:
	var w := _placed()
	w.safe_zones.clear(w, "transferred")
	w.safe_zones.place(w, SZ.KEY, w.loadout.stats(SZ.KEY), w.cast_origin() + Vector2(2000, 0)) # far away: no protection
	w.drain_events()
	w._hp = 1.0
	assert_true(w.take_hit(100000.0, false, "", w.player.pos, TOUCH) > 0)
	var events := w.drain_events()
	var types := events.map(func(e: Dictionary) -> String: return e.type)
	assert_true(types.has("player_died"))
	var ended := SZ.of(events, "safe_zone_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].reason, "died")
	assert_true(types.find("safe_zone_ended") < types.find("player_died"), "the zone ends before the death is announced")
	assert_true(w.safe_zones.is_empty())


func test_a_map_transfer_clears_it() -> void:
	var w := RunWorld.new(preload("res://tests/fixtures/map_transfer_fixtures.gd").setup(0.1))
	w.god = true
	w.loadout.order.clear()
	w.book.defs[SZ.KEY] = SZ.world().book.defs[SZ.KEY]
	w.book.skill_imgs["999"] = SZ.world().book.skill_imgs["999"]
	assert_true(w.learn_skill(SZ.KEY))
	for tick in 60:
		w.step(DT, MoveInput.new())
	w.safe_zones.place(w, SZ.KEY, w.loadout.stats(SZ.KEY), w.cast_origin())
	w.drain_events()
	w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1e9, "damage_max": 1e9, "magic": false, "crit": 0.0,
		"crit_mult": 1.5, "skill": "three_snails"}, -1)
	w.step(DT, MoveInput.new())
	assert_true(w.transfer_pending)
	assert_false(w.safe_zones.is_empty(), "it is cleared when the map changes, not when it is cleared")
	w.advance_map()
	var ended := SZ.of(w.drain_events(), "safe_zone_ended")
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].reason, "transferred")
	assert_true(w.safe_zones.is_empty())


func test_expiry_order_is_placement_order() -> void:
	var w := _placed()
	w.book.defs["test_cloud_b"] = w.book.defs[SZ.KEY].duplicate(true)
	w.book.defs["test_cloud_b"].skill_id = 9992002
	w.book.defs["test_cloud_b"].safe_zone = {"duration": 1.0}
	w.book.skill_imgs["999"].skill["9992002"] = w.book.skill_imgs["999"].skill[str(SZ.SKILL_ID)]
	w.learn_skill("test_cloud_b")
	w.safe_zones.place(w, "test_cloud_b", w.loadout.stats("test_cloud_b"), w.cast_origin())
	w.drain_events()
	var events := _run(w, 361)
	var ended := SZ.of(events, "safe_zone_ended")
	assert_eq(ended.map(func(e: Dictionary) -> String: return e.skill), ["test_cloud_b", SZ.KEY])
	assert_eq(ended.map(func(e: Dictionary) -> String: return e.reason), ["expired", "expired"])


# --- determinism ------------------------------------------------------------------------------------------------------

func _digest(w: RunWorld, ticks: int) -> String:
	var parts: Array = []
	for i in ticks:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			parts.append(var_to_str(e))
	parts.append(str(w.rng.state))
	parts.append(str(w.player_state.hp))
	return "\n".join(parts).sha256_text()


func test_a_seeded_run_with_a_cloud_replays_identically() -> void:
	var a := SZ.world(77)
	var b := SZ.world(77)
	for w: RunWorld in [a, b]:
		SZ.crowd(w)
	assert_eq(_digest(a, 600), _digest(b, 600))


func test_placing_and_negating_draws_no_random_number() -> void:
	var w := SZ.world(5)
	var before := w.rng.state
	w.safe_zones.place(w, SZ.KEY, w.loadout.stats(SZ.KEY), w.cast_origin())
	_hit(w)
	w.safe_zones.step(DT, w)
	w.safe_zones.clear(w, "died")
	assert_eq(w.rng.state, before)


func test_a_world_whose_zone_never_places_is_byte_identical_to_one_without_the_skill() -> void:
	var with_skill := SZ.world(9)
	var without := SZ.world(9)
	without.loadout.order.clear()
	without.loadout.ranks.clear()
	without.loadout.version += 1
	for w: RunWorld in [with_skill, without]:
		SZ.mob(w, 900.0)
		SZ.mob(w, 950.0) # only two monsters, never near: the cloud waits for ever
	assert_eq(_digest(with_skill, 300), _digest(without, 300))


# --- data -------------------------------------------------------------------------------------------------------------

func _errors(definition: Dictionary) -> PackedStringArray:
	return SafeZone.errors({"skills": {"cloud": definition}})


func test_the_data_errors() -> void:
	var good := {"damage": "none", "cast": {"rule": "safe_zone", "min_mobs": 3, "mob_within": 250.0}, "safe_zone": {"duration": 6.0}}
	assert_eq(_errors(good), PackedStringArray())
	assert_eq(_errors({"damage": "physical"}), PackedStringArray(), "another skill is not checked")
	var no_block := good.duplicate(true)
	no_block.erase("safe_zone")
	assert_eq(_errors(no_block).size(), 1)
	var no_rule := good.duplicate(true)
	no_rule.cast.rule = "box"
	assert_eq(_errors(no_rule).size(), 1, "a block on another rule")
	var bad_life := good.duplicate(true)
	bad_life.safe_zone.duration = 0.0
	assert_eq(_errors(bad_life).size(), 1)
	var bad_min := good.duplicate(true)
	bad_min.cast.min_mobs = 0
	assert_eq(_errors(bad_min).size(), 1)
	var no_reach := good.duplicate(true)
	no_reach.cast.erase("mob_within")
	assert_eq(_errors(no_reach).size(), 1)
	var damaging := good.duplicate(true)
	damaging.damage = "physical"
	assert_eq(_errors(damaging).size(), 1)


func test_the_card_text_names_the_resolved_life_and_admission() -> void:
	var w := SZ.world()
	w.book.defs[SZ.KEY]["name"] = "Test Cloud"
	var text := SkillText.new(w.book)
	var line := text.level_line(SZ.KEY, 1, w.loadout.stats(SZ.KEY))
	assert_true(line.contains("Sets off a zone for 6 s: hits that land while you stand inside it are negated."), "the noun defaults to zone: " + line)
	w.book.defs[SZ.KEY].safe_zone["noun"] = "smoke cloud"
	line = text.level_line(SZ.KEY, 1, w.loadout.stats(SZ.KEY))
	assert_true(line.contains("Sets off a smoke cloud for 6 s: hits that land"), "the block names the noun: " + line)
	assert_true(line.contains("Needs 3 monsters within 250 px."), line)
	w.loadout.add_skill_mod(SZ.KEY, "zone_time", "mul", 1.5)
	assert_true(text.level_line(SZ.KEY, 1, w.loadout.stats(SZ.KEY)).contains("for 9 s"), "a Thick Smoke card shows in the window")
