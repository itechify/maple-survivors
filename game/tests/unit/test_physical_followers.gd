extends TestCase
## Physical followers (spec #332 M8, GAME_DESIGN 7.44): the PlayerSummons seam with a `pad` W.Att, a literal stun
## duration, hover/fly and a spawn sound, on synthetic Skill.wz-shaped data (no Bowmaster definition needed yet).
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOW := 1452051

## Test-only follower: a hawk-like physical summon on the 212 book (id 2121099). pad = 10 x level, so rank 1 (level 4 of 30)
## is pad 40. The attack node carries the type-1 art of Silver Hawk (info.hit / info.effect) as empty frames.
func _hawk_def(extra := {}) -> Dictionary:
	var d: Dictionary = RF.quiet_data().skills.skills.elquines.duplicate(true)
	d.erase("element")
	d.erase("rarity_bonuses")
	d.merge({"skill_id": 2121099, "name": "Test Hawk", "damage": "physical", "cooldown": 30.0,
		"on_hit": {"status": "stun", "chance_field": "prop", "duration": 1.5},
		"sounds": {"use": "Sound.wz/Skill.img/2121099/Use", "summon": "Sound.wz/Skill.img/2121099/Summon"}}, true)
	d.summon.merge({"path": "Skill.wz/212.img/skill/2121099/summon", "move": "fly", "hover": 80.0,
		"watk_field": "pad", "attack_interval": 1.6, "follow_distance": 70.0, "follow_speed": 220.0}, true)
	d.merge(extra, true)
	return d

func _world(def := {}, strike_effect := false, prop := 50.0, p_seed := 338) -> RunWorld:
	var data := RF.quiet_data()
	data.skills.skills["test_hawk"] = def if not def.is_empty() else _hawk_def()
	var setup := RF.setup("quiet", p_seed, data)
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"pad": 10.0 * lv, "prop": prop, "time": 60.0}
	var info := {"attackAfter": 100.0, "mobCount": 2.0, "range": {"lt": {"$v": [-200, -150]}, "rb": {"$v": [200, 150]}}}
	if strike_effect:
		info["effect"] = {"0": {"delay": 80.0}}
	# attack1 of Silver Hawk: a 100 ms body frame, then a 600 ms placeholder while the bolt strikes.
	var attack := {"info": info, "0": {"delay": 100.0}, "1": {"delay": 600.0}}
	setup.skill_imgs["212"].skill["2121099"] = {"level": levels, "summon": {"attack1": attack}}
	setup.data.stages.stages.quiet.maps.append(setup.data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.wear_new_item(BOW)
	w.learn_skill("test_hawk")
	w.loadout.str_stat = 20.0
	w.loadout.dex_stat = 100.0
	w.loadout.watk = 900.0 # the worn weapon plus ammo: a follower must ignore it
	w.loadout.mastery = 0.6
	return w

func _mob(w: RunWorld, id: int, px: float, hp := 100000) -> int:
	var m := RF.put_mob(w, id, px, 195, 100000.0)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func _run(w: RunWorld, ticks: int) -> void:
	w.loadout.order.clear()
	for t in ticks:
		w.runner.tick_cooldowns(DT, w)

func test_pad_is_the_w_att_of_the_held_bow_row_not_the_worn_weapon_and_ammo() -> void:
	var w := _world()
	var st := w.loadout.stats("test_hawk")
	# Bow row 3.4 x DEX + STR = 3.4 x 100 + 20 = 360; x pad 40 / 100 = 144 (max). min: 0.9 x 0.6 mastery x 340 + 20 = 203.6.
	assert_near(st.damage_max, 144.0, 0.001)
	assert_near(st.damage_min, 203.6 * 0.4, 0.001)
	assert_eq(st.damage_type, "physical")
	assert_eq(st.defense, "pdd")
	w.loadout.watk = 1.0
	assert_near(w.loadout.stats("test_hawk").damage_max, 144.0, 0.001, "the worn weapon's attack changes nothing")
	var r8 := w.loadout.stats("test_hawk", 8)
	assert_eq(r8.level, 30)
	assert_near(r8.damage_max, 360.0 * 3.0, 0.001, "rank 8 reads level 30 of the table (pad 300)")

func test_a_follower_hit_deals_pad_damage_to_the_nearest_targets() -> void:
	var w := _world()
	var near := _mob(w, 1110100, 260)
	w.runner.step(DT, w)
	_run(w, 12)
	assert_true(w.swarm.hp[near] < 100000, "the follower struck")
	assert_true(100000 - w.swarm.hp[near] <= 144, "no more than the pad-resolved maximum")

func test_literal_stun_duration_with_the_prop_chance_and_bosses_reject_it() -> void:
	var stunned_seeds := 0
	for seed_value in range(1, 21):
		var w := _world({}, false, 50.0, seed_value)
		var mob := _mob(w, 1110100, 260)
		var boss := _mob(w, 2220000, 280)
		w.runner.step(DT, w)
		_run(w, 10)
		var left := w.swarm.status_time(mob, MobSwarm.STUN)
		if left > 0.0:
			stunned_seeds += 1
			assert_true(left > 1.0 and left <= 1.5, "the literal 1.5 s, not the 60 s lifetime: %f" % left)
		assert_eq(w.swarm.status_time(boss, MobSwarm.STUN), 0.0, "bosses reject stun")
	assert_true(stunned_seeds > 3 and stunned_seeds < 17, "a prop of 50 stuns some hits and not others: %d/20" % stunned_seeds)

func test_prop_100_stuns_every_hit() -> void:
	for seed_value in range(1, 6):
		var w := _world({}, false, 100.0, seed_value)
		var mob := _mob(w, 1110100, 260)
		w.runner.step(DT, w)
		_run(w, 10)
		assert_true(w.swarm.status_time(mob, MobSwarm.STUN) > 1.0, "seed %d" % seed_value)

func test_hover_and_the_fly_alias_set_the_trailing_point_and_the_stored_action() -> void:
	var w := _world()
	w.runner.step(DT, w)
	_run(w, 5) # leave the 'summoned' wait
	w.player.pos.x += 300
	_run(w, 30)
	var s := w.runner.summons
	assert_eq(s.action[0], "fly", "following plays the resolved fly node")
	_run(w, 240)
	assert_eq(s.action[0], "stand", "arrived: stand")
	assert_near(s.y[0], w.player.pos.y - 80.0, 1.0, "hovers 80 px above the trailing point")
	assert_true(s.definitions[0].durations.has("fly"), "the resolved move node has a duration")

func test_elquines_keeps_move_and_no_hover() -> void:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 291, data)
	setup.skill_imgs["212"] = {"skill": {"2121005": {"level": {"1": {"mad": 100.0, "mastery": 10.0, "time": 3.0}},
		"elemAttr": "i", "summon": {"attack1": {"info": {"attackAfter": 100.0,
		"range": {"lt": {"$v": [-200, -150]}, "rb": {"$v": [0, 30]}}}}}}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("elquines")
	w.runner.step(DT, w)
	w.loadout.order.clear()
	w.player.pos.x += 300
	for t in 30:
		w.runner.tick_cooldowns(DT, w)
	assert_eq(w.runner.summons.action[0], "move")
	for t in 240:
		w.runner.tick_cooldowns(DT, w)
	assert_near(w.runner.summons.y[0], w.player.pos.y, 0.01)

func test_summon_sound_rides_each_spawn_event_when_listed() -> void:
	var w := _world()
	w.runner.step(DT, w)
	var spawns := w.events.filter(func(e: Dictionary) -> bool: return e.type == "summon_spawn")
	assert_eq(spawns.size(), 1)
	assert_eq(spawns[0].sound, "Sound.wz/Skill.img/2121099/Summon")
	var plain := _hawk_def()
	plain.sounds.erase("summon")
	var q := _world(plain)
	q.runner.step(DT, q)
	var quiet := q.events.filter(func(e: Dictionary) -> bool: return e.type == "summon_spawn")
	assert_false(quiet[0].has("sound"), "no key when none is listed: Elquines events stay byte-identical")

func test_summon_count_recast_transfer_and_a_dead_caster() -> void:
	var w := _world()
	w.loadout.skill_mods["test_hawk"] = {"summon_count": Vector2(1.0, 1.0)}
	w.runner.step(DT, w)
	assert_eq(w.runner.summons.living_count(), 2, "summon_count adds a follower")
	var near := _mob(w, 1110100, 260)
	w.player_state.dead = true
	_run(w, 40)
	assert_eq(w.swarm.hp[near], 100000, "a dead caster's followers do not attack")
	w.player_state.dead = false
	w.runner.cooldowns["test_hawk"] = 0.0
	w.runner.step(DT, w)
	assert_eq(w.runner.summons.living_count(), 2, "a recast replaces the group instead of stacking")
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.summons.living_count(), 0, "map transfer clears")

func test_a_type_1_strike_emits_its_info_effect_on_each_struck_monster() -> void:
	var w := _world({}, true)
	var near := _mob(w, 1110100, 260)
	w.runner.step(DT, w)
	_run(w, 12)
	var strikes := w.events.filter(func(e: Dictionary) -> bool: return e.type == "summon_strike")
	assert_eq(strikes.size(), 1)
	assert_eq(strikes[0].mob, near)
	assert_eq(strikes[0].effect, "Skill.wz/212.img/skill/2121099/summon/attack1/info/effect")
	var plain := _world()
	_mob(plain, 1110100, 260)
	plain.runner.step(DT, plain)
	_run(plain, 12)
	assert_eq(plain.events.filter(func(e: Dictionary) -> bool: return e.type == "summon_strike").size(), 0)

func test_elquines_twin_world_is_unchanged_by_explicit_defaults() -> void:
	var states: Array = []
	for explicit in [false, true]:
		var data := RF.quiet_data()
		if explicit:
			data.skills.skills.elquines.summon.merge({"move": "move", "hover": 0.0}, true)
		var setup := RF.setup("quiet", 291, data)
		setup.skill_imgs["212"] = {"skill": {"2121005": {"level": {"1": {"mad": 100.0, "mastery": 10.0, "time": 5.0}},
			"elemAttr": "i", "summon": {"attack1": {"info": {"attackAfter": 100.0, "mobCount": 2.0,
			"range": {"lt": {"$v": [-200, -150]}, "rb": {"$v": [0, 30]}}}}}}}}
		var w := RunWorld.new(setup)
		RF.place_player(w, 200)
		w.loadout.order.clear()
		w.learn_skill("elquines")
		w.loadout.set_caster(100.0, 0.0, 30)
		var m := _mob(w, 1110100, 260)
		w.runner.step(DT, w)
		_run(w, 90)
		states.append([w.runner.summons.x[0], w.runner.summons.y[0], w.runner.summons.action[0], w.swarm.hp[m], w.rng.state])
	assert_eq(states[0], states[1])


func test_a_settling_follower_leaves_its_attack_pose_and_keeps_following_between_strikes() -> void:
	var plain := _world()
	var settle := _world(_hawk_def({"summon": _hawk_def().summon.merged({"settle": true})}))
	for w: RunWorld in [plain, settle]:
		_mob(w, 1110100, 260)
		w.runner.step(DT, w)
		_run(w, 20) # past the summoned animation: the first strike starts
		assert_eq(w.runner.summons.action[0], "attack1")
		w.player.pos.x += 250
		_run(w, 60) # 1 s: the 0.7 s attack animation is over, the 1.6 s interval is not
	assert_eq(plain.runner.summons.action[0], "attack1", "Elquines-style: the pose is held for the whole interval")
	assert_eq(settle.runner.summons.action[0], "fly", "a settling follower resumes its move node")
	assert_true(settle.runner.summons.x[0] > plain.runner.summons.x[0] + 40.0, "and follows the caster between strikes")
	_run(settle, 120)
	assert_eq(settle.runner.summons.action[0], "attack1", "the next strike starts after the interval")
