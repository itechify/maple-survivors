extends TestCase
## The generic Hidden state (#194 of spec #168, docs/GAME_DESIGN.md 7.18): while an active buff makes the character
## Hidden, monsters (bosses included) neither chase nor attack it and the character cannot attack, but buffs, potions and
## movement still work; it ends at the buff's duration. Synthetic buffs and data (no Pirate skill), seeded RNG, fixed dt.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const BF := preload("res://tests/fixtures/boss_attack_fixtures.gd")
const MANO := preload("res://tests/fixtures/mano_fixtures.gd")
const DT := 1.0 / 60.0
const SNAIL := 100100
const BODY_MOB := 1110100
const FLYER := 9300063


## A quiet world: 1000 HP, 100 MP, no regeneration, mobs stand still unless a test gives them speed, no skills.
func _world(p_seed := 194) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = 1000
	data.balance.player.mp = 100
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0
	var w := RunWorld.new(RF.with_basic_attack(RF.setup("quiet", p_seed, data)))
	RF.place_player(w, 400)
	w.player.facing = 1
	w.drain_events()
	return w


## Makes the character Hidden for `seconds` through the same entry point a cast uses.
func _hide(w: RunWorld, seconds := 4.0, extra := {}) -> void:
	var stats := {"skill_id": 9991001, "level": 1, "icon": "", "duration": seconds, "buff_stat": "",
		"buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}}
	stats.merge(extra, true)
	assert_true(w.start_buff("synthetic_hide", stats))


func _stand_mob(w: RunWorld, id: int, x: float, speed := 0.0) -> int:
	var kind: MobKind = w.mob_kinds[int(w.kind_of_id[id])]
	kind.move_speed = speed
	var m := RF.put_mob(w, id, x, 190.0, 1000.0)
	w.swarm.alpha[m] = 1.0
	return m


func _types(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _run(w: RunWorld, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


# --- the state -------------------------------------------------------------------------------------------------------

func test_hidden_lasts_exactly_the_buffs_duration() -> void:
	var w := _world()
	assert_false(w.is_hidden())
	assert_false(bool(w.player_state.hidden))
	_hide(w, 4.0)
	assert_true(w.is_hidden())
	assert_true(bool(w.player_state.hidden))
	_run(w, 230)
	assert_true(w.is_hidden(), "still Hidden shortly before 4 s")
	var events := _run(w, 20)
	assert_false(w.is_hidden(), "over after 4 s")
	assert_false(bool(w.player_state.hidden))
	assert_eq(_types(events, "buff_expired").size(), 1)


func test_a_buff_without_the_flag_does_not_hide_the_character() -> void:
	var w := _world()
	w.start_buff("plain", {"skill_id": 9991002, "level": 1, "icon": "", "duration": 4.0, "buff_stat": "avoid",
		"buff_value": 5.0, "pulse_interval": 0.0})
	assert_false(w.is_hidden())
	assert_eq(w.morph_id(), 0)


func test_a_buff_can_end_early_when_hp_is_above_its_fraction() -> void:
	var w := _world()
	w.take_hit(700.0, false, "", w.player.pos + Vector2(10, 0))
	assert_between(float(w.player_state.hp), 1.0, 600.0)
	_hide(w, 30.0, {"end_hp_above": 0.6})
	_run(w, 60)
	assert_true(w.is_hidden(), "HP is still low")
	w.heal_fraction("hp", 0.5)
	assert_true(float(w.player_state.hp) > 600.0)
	var events := _run(w, 2)
	assert_false(w.is_hidden(), "ends once HP is above 60%")
	assert_eq(_types(events, "buff_expired").size(), 1)


## The hidden flag and morph id are cached fields (review of #194): they follow a buff starting, expiring and being
## ended or cleared, and the first active morph wins like the first active buff in cast order.
func test_the_cached_hidden_flag_and_morph_follow_every_start_and_end() -> void:
	var b := PlayerBuffs.new()
	var events := []
	var base := {"skill_id": 1, "level": 1, "icon": "", "duration": 1.0, "buff_stat": "avoid", "buff_value": 1.0,
		"pulse_interval": 0.0}
	assert_false(b.hidden())
	assert_eq(b.morph(), 0)
	assert_false(b.ends_on_hp())
	b.start("plain", base)
	assert_false(b.hidden())
	var barrel := base.duplicate()
	barrel.merge({"hidden": true, "morph": 1002, "end_hp_above": 0.6, "duration": 3.0}, true)
	b.start("barrel", barrel)
	var second := base.duplicate()
	second.merge({"morph": 1003, "duration": 5.0}, true)
	b.start("second", second)
	assert_true(b.hidden())
	assert_eq(b.morph(), 1002, "the first active morph")
	assert_true(b.ends_on_hp())
	b.step(1.5, events)  # "plain" expires
	assert_true(b.hidden() and b.morph() == 1002)
	assert_true(b.end("barrel", events))
	assert_false(b.hidden())
	assert_eq(b.morph(), 1003, "the next active morph takes over")
	assert_false(b.ends_on_hp())
	b.step(10.0, events)
	assert_eq(b.morph(), 0)
	b.start("barrel", barrel)
	b.clear()
	assert_false(b.hidden() or b.ends_on_hp())
	assert_eq(b.morph(), 0)


# --- monsters ignore the character -----------------------------------------------------------------------------------

func test_walking_into_a_monster_deals_no_contact_damage() -> void:
	var control := _world()
	_stand_mob(control, BODY_MOB, 400.0)
	var hits := _types(_run(control, 120), "player_hit")
	assert_false(hits.is_empty(), "control: a monster on top of the character hurts it")
	var w := _world()
	_stand_mob(w, BODY_MOB, 400.0)
	_hide(w, 20.0)
	var hp := int(w.player_state.hp)
	assert_true(_types(_run(w, 120), "player_hit").is_empty(), "no hit of any kind while Hidden")
	assert_eq(int(w.player_state.hp), hp)
	assert_eq(w.take_hit(100.0, false, "", w.player.pos + Vector2(5, 0)), 0, "nothing lands, whatever its source")
	assert_eq(int(w.player_state.hp), hp)


func test_ground_mobs_stop_chasing_and_patrol_instead() -> void:
	var control := _world()
	var cm := _stand_mob(control, SNAIL, 100.0, 60.0)
	control.swarm.facing[cm] = -1
	_run(control, 60)
	assert_true(control.swarm.x[cm] > 100.0, "control: the mob turns and walks at the character")
	var w := _world()
	var m := _stand_mob(w, SNAIL, 100.0, 60.0)
	w.swarm.facing[m] = -1
	_hide(w, 20.0)
	_run(w, 60)
	assert_true(w.swarm.x[m] < 100.0, "Hidden: it keeps walking the way it faced, as if nobody were there")
	assert_eq(int(w.swarm.facing[m]), -1)


func test_flying_mobs_hover_where_they_are() -> void:
	var control := _world()
	var cf := _stand_mob(control, FLYER, 900.0, 60.0)
	_run(control, 60)
	assert_true(absf(control.swarm.x[cf] - 900.0) > 5.0, "control: a flyer closes in on the character")
	var w := _world()
	var f := _stand_mob(w, FLYER, 900.0, 60.0)
	_hide(w, 20.0)
	_run(w, 60)
	assert_near(w.swarm.x[f], 900.0, 0.01, "Hidden: it stays over its spot")


func test_mob_attack_does_not_start_and_a_windup_in_progress_lands_nothing() -> void:
	var control := MF.world(194)
	RF.put_mob(control, MF.TAURO, 600)
	var started := _types(_run(control, 600), "mob_attack").filter(func(e: Dictionary) -> bool: return e.phase == "start")
	assert_false(started.is_empty(), "control: the Tauromacis attacks")
	var w := MF.world(194)
	RF.put_mob(w, MF.TAURO, 600)
	_hide(w, 20.0)
	var events := _run(w, 600)
	assert_true(_types(events, "mob_attack").is_empty(), "no attack is even started")
	assert_true(_types(events, "player_hit").is_empty())
	# A windup already under way when the character vanishes lands nothing.
	var late := MF.world(194)
	RF.put_mob(late, MF.TAURO, 600)
	var hp := int(late.player_state.hp)
	var begun := false
	for tick in 600:
		late.step(DT, MoveInput.new())
		for e: Dictionary in late.drain_events():
			if e.type == "mob_attack" and e.phase == "start":
				begun = true
		if begun:
			break
	assert_true(begun)
	_hide(late, 20.0)
	var rest := _run(late, 120)
	assert_true(_types(rest, "player_hit").is_empty(), "the strike that was winding up hits nobody")
	assert_eq(int(late.player_state.hp), hp)


func test_a_boss_neither_attacks_nor_pursues_a_hidden_character() -> void:
	var control := RunWorld.new(BF.setup())
	var hit := false
	for tick in 600:
		control.step(DT, MoveInput.new())
		for e: Dictionary in control.drain_events():
			if e.type == "player_hit" and e.boss:
				hit = true
	assert_true(hit, "control: the boss hurts the character")
	var w := RunWorld.new(BF.setup())
	_hide(w, 40.0)
	var events: Array = []
	for tick in 1800:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	assert_false(_types(events, "boss_spawned").is_empty(), "the boss still arrives")
	assert_true(_types(events, "boss_attack").is_empty(), "it starts no attack")
	assert_true(_types(events, "player_hit").is_empty(), "no touch, slam or ball hurts a Hidden character")
	assert_true(_types(events, "boss_teleported").is_empty(), "it does not stall and teleport to the character")


func test_balls_in_flight_pass_through_the_character() -> void:
	var spec := func(w: RunWorld) -> Dictionary:
		var from := w.player.pos + Vector2(-120.0, -30.0)
		return {"pos": from, "velocity": Vector2(300.0, 0.0), "range": 400.0, "visual": -1, "radius": 8.0,
			"mob": 0, "mob_id": MF.TAURO, "damage": 100.0, "multiplier": 1.0, "accuracy": 0.0, "magic": false,
			"element": "", "hit": "", "source_pos": from, "ordinary": true}
	var control := _world()
	control.mob_projectiles.spawn(spec.call(control))
	assert_false(_types(_run(control, 90), "mob_projectile_hit").is_empty(), "control: the ball hits")
	var w := _world()
	w.mob_projectiles.spawn(spec.call(w))
	_hide(w, 20.0)
	var events := _run(w, 50)
	assert_true(_types(events, "mob_projectile_hit").is_empty())
	assert_eq(w.mob_projectiles.active_count(), 1, "the ball is not used up by passing through")
	assert_true(w.mob_projectiles.x[0] > w.player.pos.x + 20.0, "it flew on past the body")
	_run(w, 40)
	assert_eq(w.mob_projectiles.active_count(), 0, "and ends at the end of its range")
	assert_true(_types(events, "player_hit").is_empty())


func test_a_boss_skill_aimed_at_the_character_is_not_cast() -> void:
	var control := MANO.world()
	_run(control, 900)
	assert_eq(control.player.speed_stat, 80, "control: Mano's area Slow slows the character in its box")
	var w := MANO.world()
	_hide(w, 40.0)
	var events := _run(w, 900)
	assert_true(_types(events, "boss_skill").is_empty(), "the Slow is not cast at nobody")
	assert_eq(w.player.speed_stat, 100)


# --- the character cannot attack, but everything else works ---------------------------------------------------------

func test_auto_casts_pause_and_resume_when_hidden_ends() -> void:
	var control := _world()
	_stand_mob(control, SNAIL, 450.0)
	assert_true(control.learn_skill("three_snails"))
	assert_false(_types(_run(control, 120), "cast").is_empty(), "control: the character casts")
	var w := _world()
	var m := _stand_mob(w, SNAIL, 450.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	assert_true(w.learn_skill("three_snails"))
	_hide(w, 3.0)
	var events := _run(w, 170)
	assert_true(_types(events, "cast").is_empty(), "no skill casts")
	assert_true(_types(events, "mob_hit").is_empty(), "nothing is hit")
	events = _run(w, 60)
	assert_false(_types(events, "cast").is_empty(), "the skill is ready again once Hidden ends")


func test_heal_still_heals_but_never_strikes_undead_while_hidden() -> void:
	var make := func() -> RunWorld:
		var data := RF.quiet_data()
		data.balance.player.hp = 1000
		data.balance.player.mp = 1000
		data.balance.regen.hp = 0
		var setup := RF.setup("quiet", 57, data)
		setup.skill_imgs["230"] = {"skill": {"2301002": {"level": {
			"1": {"hp": 10.0, "mpCon": 12.0, "mobCount": 6.0,
				"lt": {"$v": [-250.0, -150.0]}, "rb": {"$v": [250.0, 150.0]}}}}}}
		var cleric := RunWorld.new(setup)
		RF.place_player(cleric, 400)
		RF.as_job(cleric, 200)
		RF.as_job(cleric, 230)
		cleric.loadout.order.clear()
		cleric.learn_skill("heal")
		cleric.loadout.set_caster(100.0, 23.0, 30)
		var m := _stand_mob(cleric, BODY_MOB, 500.0)
		cleric.swarm.hp[m] = 100000
		cleric.swarm.max_hp[m] = 100000
		cleric.swarm.mob_kind(m).undead = true
		cleric.drain_events()
		return cleric
	var control: RunWorld = make.call()
	var events := _run(control, 30)
	assert_false(_types(events, "mob_hit").is_empty(), "control: Heal strikes the undead in its box at full HP")
	var w: RunWorld = make.call()
	_hide(w, 20.0)
	events = _run(w, 60)
	assert_true(_types(events, "cast").is_empty(), "Hidden: no undead strike is cast at full HP")
	assert_true(_types(events, "mob_hit").is_empty())
	w.take_hit(800.0, false, "", w.player.pos + Vector2(10, 0)) # no-op while Hidden
	w.heal_fraction("hp", -0.7)
	events = _run(w, 30)
	assert_eq(_types(events, "cast").size(), 1, "below half HP the Heal is still cast")
	assert_true(_types(events, "mob_hit").is_empty(), "and still strikes nobody")


func test_buffs_potions_and_movement_still_work_while_hidden() -> void:
	var w := _world()
	assert_true(w.learn_skill("recovery"))
	w.take_hit(800.0, false, "", w.player.pos + Vector2(10, 0))
	_hide(w, 20.0)
	var events := _run(w, 5)
	assert_false(_types(events, "buff_cast").filter(func(e: Dictionary) -> bool: return e.skill == "recovery").is_empty(),
		"a buff (Recovery below half HP) is still cast")
	var hp := int(w.player_state.hp)
	assert_true(w.drink_potion("hp"), "potions still work")
	assert_true(int(w.player_state.hp) > hp)
	_run(w, 60) # the hit's knockback lock ends
	var x := w.player.pos.x
	for i in 30:
		w.step(DT, MoveInput.make(false, true))
	assert_true(w.player.pos.x > x + 20.0, "manual movement still works")
