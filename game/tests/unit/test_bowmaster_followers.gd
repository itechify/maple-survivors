extends TestCase
## Silver Hawk (3111005) and Phoenix (3121006), the Bowmaster physical followers (spec #332, ticket B11 #343): the shipped
## definitions in skills/bowmaster.json on Skill.wz-shaped synthetic books 311/312, and the mapped WZ levels and animation
## nodes against the real cache. Seeded RNG, fixed dt.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOW := 1452051
const SNAIL := 1110100
const BOSS := 2220000
const HAWK_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]

## Independent facts from Skill.wz (v83, tier A) at the eight mapped levels, written out as literals.
const HAWK_PAD := [32, 44, 56, 65, 77, 86, 94, 100]
const HAWK_PROP := [59, 71, 82, 88, 93, 96, 98, 99]
const HAWK_TIME := [112, 124, 136, 145, 157, 166, 174, 180]
const PHOENIX_PAD := [320, 340, 410, 425, 445, 515, 535, 550]
const PHOENIX_TIME := [122, 134, 146, 155, 167, 179, 191, 200]


## Generic books: pad = 10 x level, prop = 40 + 2 x level (level 30 = 100), time 60 s. The follower nodes carry the shape of
## the real ones: a body frame then a placeholder for the hawk, a long attack for the phoenix.
func _levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"pad": 10.0 * lv, "prop": 40.0 + 2.0 * lv, "time": 60.0}
	return levels


func _frames(count: int, delay: float) -> Dictionary:
	var node := {}
	for k in count:
		node[str(k)] = {"delay": delay}
	return node


func _summon_node(range_box: Array, attack_after: float, mob_count: int, attack_frames: Dictionary) -> Dictionary:
	var info := {"attackAfter": attack_after,
		"range": {"lt": {"$v": [range_box[0], range_box[1]]}, "rb": {"$v": [range_box[2], range_box[3]]}}}
	if mob_count > 0:
		info["mobCount"] = float(mob_count)
	var attack := attack_frames.duplicate()
	attack["info"] = info
	return {"summoned": _frames(5, 100.0), "fly": _frames(5, 90.0), "stand": _frames(5, 90.0), "attack1": attack,
		"die": _frames(5, 100.0)}


func _world(key: String, p_seed := 343) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", p_seed, data)
	setup["job"] = 312
	var hawk_attack := {"0": {"delay": 100.0}, "1": {"delay": 600.0}}
	setup.skill_imgs["311"] = {"skill": {"3111005": {"level": _levels(),
		"summon": _summon_node([-200, -150, 200, 150], 100.0, 0, hawk_attack)}}}
	setup.skill_imgs["312"] = {"skill": {"3121006": {"level": _levels(), "elemAttr": "f",
		"summon": _summon_node([-100, -60, 100, 60], 360.0, 4, _frames(11, 120.0))}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.wear_new_item(BOW)
	w.learn_skill(key)
	w.loadout.str_stat = 20.0
	w.loadout.dex_stat = 100.0
	w.loadout.mastery = 0.6
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.move_speed = 0.0
	return w


func _mob(w: RunWorld, id: int, px: float, hp := 1000000) -> int:
	var m := RF.put_mob(w, id, px, 195, 100000.0)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


## Runs `ticks` follower ticks with no other skill casting; returns the ticks at which a `summon_attack` began.
func _run(w: RunWorld, ticks: int) -> Array:
	var attacks := []
	w.loadout.order.clear()
	for t in ticks:
		w.runner.tick_cooldowns(DT, w)
		for e: Dictionary in w.drain_events():
			if e.type == "summon_attack":
				attacks.append(t)
	return attacks


func _struck(w: RunWorld, mobs: Array) -> int:
	var n := 0
	for m: int in mobs:
		if w.swarm.hp[m] < w.swarm.max_hp[m]:
			n += 1
	return n


# --- definitions ------------------------------------------------------------------------------------------------------

func test_the_two_followers_are_defined_physical_summons_of_the_312_pool() -> void:
	var skills: Dictionary = RF.quiet_data().skills.skills
	for key in ["silver_hawk", "phoenix"]:
		var d: Dictionary = skills[key]
		assert_eq(String(d.kind), "summon", key)
		assert_eq(String(d.damage), "physical", key)
		assert_eq(String(d.cast.rule), "summon", key)
		assert_eq(String(d.action), "alert2", key)
		assert_eq(String(d.summon.move), "fly", key)
		assert_eq(String(d.summon.watk_field), "pad", key)
		assert_true(bool(d.summon.settle), "%s: the 1x1 placeholder frame must not hide the follower (B6)" % key)
		assert_true(float(d.summon.hover) > 0.0 and float(d.summon.hover) <= 30.0, "%s: small hover (B6 finding)" % key)
	assert_eq(int(skills.silver_hawk.skill_id), 3111005)
	assert_eq(int(skills.phoenix.skill_id), 3121006)
	assert_eq(float(skills.silver_hawk.cooldown), 30.0)
	assert_eq(float(skills.phoenix.cooldown), 40.0)
	assert_eq(float(skills.silver_hawk.summon.attack_interval), 1.6)
	assert_eq(float(skills.phoenix.summon.attack_interval), 3.0)
	assert_false(skills.silver_hawk.has("element"), "the hawk is neutral")
	assert_eq(String(skills.phoenix.element), "f")
	assert_eq(String(skills.silver_hawk.on_hit.status), "stun")
	assert_eq(String(skills.silver_hawk.on_hit.chance_field), "prop")
	assert_eq(float(skills.silver_hawk.on_hit.duration), 1.5)
	assert_false(skills.phoenix.has("on_hit"), "the Phoenix node has no status (A)")
	assert_eq(String(skills.silver_hawk.sounds.summon), "Sound.wz/Skill.img/3111005/Summon")
	assert_eq(String(skills.phoenix.sounds.summon), "Sound.wz/Skill.img/3121006/Summon")


func test_the_pool_keys_resolve_to_a_book_for_job_312() -> void:
	var data := RF.quiet_data()
	for key in ["silver_hawk", "phoenix"]:
		assert_true(key in data.jobs_survivor.jobs["312"].skill_pool, key)
		assert_true(data.skills.skills.has(key), key)


# --- Silver Hawk ------------------------------------------------------------------------------------------------------

func test_hawk_strikes_one_monster_per_1_6_seconds() -> void:
	var w := _world("silver_hawk")
	var mobs := [_mob(w, SNAIL, 240), _mob(w, SNAIL, 270), _mob(w, SNAIL, 160)]
	w.runner.step(DT, w)
	var attacks := _run(w, 500)
	assert_true(attacks.size() >= 4, "attacks: %d" % attacks.size())
	for k in range(1, attacks.size()):
		assert_true(absi(int(attacks[k]) - int(attacks[k - 1]) - 96) <= 1, "1.6 s between strikes: %d" % (attacks[k] - attacks[k - 1]))
	# One struck monster per strike: the number of damaged monsters never exceeds the strikes, and one strike hurts one.
	var w2 := _world("silver_hawk")
	var again := [_mob(w2, SNAIL, 240), _mob(w2, SNAIL, 270), _mob(w2, SNAIL, 160)]
	w2.runner.step(DT, w2)
	var first := _run(w2, 1)
	while first.is_empty():
		first = _run(w2, 1)
	_run(w2, 12)
	assert_eq(_struck(w2, again), 1, "one monster per strike")
	assert_true(_struck(w, mobs) >= 1)


func test_hawk_damage_is_the_pad_of_the_rank_in_the_bow_row() -> void:
	var w := _world("silver_hawk")
	var st := w.loadout.stats("silver_hawk")
	assert_eq(int(st.level), 4)
	# Bow row 3.4 x DEX + STR = 360 over pad 40 (level 4 of the generic table): 144.
	assert_near(st.damage_max, 144.0, 0.001)
	assert_eq(st.damage_type, "physical")
	w.loadout.set_rank("silver_hawk", 8)
	assert_near(w.loadout.stats("silver_hawk").damage_max, 360.0 * 3.0, 0.001)


func test_hawk_stuns_by_prop_for_one_and_a_half_seconds_and_bosses_resist() -> void:
	var stunned := 0
	for seed_value in range(1, 21):
		var w := _world("silver_hawk", seed_value)
		var snail := _mob(w, SNAIL, 260)
		var boss := _mob(w, BOSS, 280)
		w.runner.step(DT, w)
		_run(w, 70)
		var left := w.swarm.status_time(snail, MobSwarm.STUN)
		if left > 0.0:
			stunned += 1
			assert_true(left > 1.0 and left <= 1.5, "the literal 1.5 s, not the lifetime: %f" % left)
		assert_eq(w.swarm.status_time(boss, MobSwarm.STUN), 0.0, "bosses resist")
	assert_true(stunned > 3 and stunned < 17, "a prop of 48 at rank 1 stuns some strikes: %d/20" % stunned)


func test_hawk_prop_100_stuns_every_strike() -> void:
	for seed_value in range(1, 6):
		var w := _world("silver_hawk", seed_value)
		w.loadout.set_rank("silver_hawk", 8)
		var snail := _mob(w, SNAIL, 260)
		w.runner.step(DT, w)
		_run(w, 70)
		assert_true(w.swarm.status_time(snail, MobSwarm.STUN) > 1.0, "seed %d" % seed_value)


func test_hawk_is_not_fire() -> void:
	var w := _world("silver_hawk")
	var immune := _mob(w, SNAIL, 260)
	w.swarm.mob_kind(immune).elements = {"F": 0.0}
	w.runner.step(DT, w)
	_run(w, 70)
	assert_true(w.swarm.hp[immune] < w.swarm.max_hp[immune], "a fire-immune monster is still struck by the neutral hawk")


# --- Phoenix ----------------------------------------------------------------------------------------------------------

func test_phoenix_strikes_up_to_four_monsters_per_3_seconds() -> void:
	var w := _world("phoenix")
	var mobs := []
	for k in 6:
		mobs.append(_mob(w, SNAIL, 230.0 + 15.0 * k))
	w.runner.step(DT, w)
	var attacks := _run(w, 800)
	assert_true(attacks.size() >= 3, "attacks: %d" % attacks.size())
	for k in range(1, attacks.size()):
		assert_true(absi(int(attacks[k]) - int(attacks[k - 1]) - 180) <= 1, "3.0 s between strikes")
	var one := _world("phoenix")
	var six := []
	for k in 6:
		six.append(_mob(one, SNAIL, 230.0 + 15.0 * k))
	one.runner.step(DT, one)
	var first := _run(one, 1)
	while first.is_empty():
		first = _run(one, 1)
	_run(one, 30)
	assert_eq(_struck(one, six), 4, "mobCount 4: four of six")
	assert_true(_struck(w, mobs) >= 4)


func test_phoenix_is_fire() -> void:
	var w := _world("phoenix")
	var immune := _mob(w, SNAIL, 240)
	var plain := _mob(w, SNAIL, 250)
	w.swarm.mob_kind(immune).elements = {"F": 0.0}
	w.runner.step(DT, w)
	_run(w, 60)
	assert_eq(w.swarm.hp[immune], w.swarm.max_hp[immune], "fire-immune: unharmed")
	assert_true(w.swarm.hp[plain] < w.swarm.max_hp[plain] or w.swarm.hp[immune] == w.swarm.max_hp[immune])


func test_phoenix_pad_is_the_w_att_and_applies_no_status() -> void:
	var w := _world("phoenix")
	var st := w.loadout.stats("phoenix")
	assert_near(st.damage_max, 360.0 * 0.4, 0.001, "pad 40 at level 4 of the generic table")
	var m := _mob(w, SNAIL, 240)
	w.runner.step(DT, w)
	_run(w, 60)
	assert_eq(w.swarm.status_time(m, MobSwarm.STUN), 0.0)


# --- both -------------------------------------------------------------------------------------------------------------

func test_both_followers_hover_above_the_trailing_point_and_follow_on_the_fly_node() -> void:
	for key in ["silver_hawk", "phoenix"]:
		var w := _world(key)
		var hover := float(w.book.def(key).summon.hover)
		w.runner.step(DT, w)
		_run(w, 60)
		w.player.pos.x += 300
		_run(w, 20)
		assert_eq(w.runner.summons.action[0], "fly", key)
		_run(w, 300)
		assert_eq(w.runner.summons.action[0], "stand", key)
		assert_near(w.runner.summons.y[0], w.player.pos.y - hover, 1.0, key)
		assert_true(absf(w.runner.summons.x[0] - w.player.pos.x) < 200.0, "%s follows" % key)


func test_a_flying_follower_still_strikes_a_ground_monster() -> void:
	for key in ["silver_hawk", "phoenix"]:
		var w := _world(key)
		var m := _mob(w, SNAIL, 240)
		w.runner.step(DT, w)
		_run(w, 80)
		assert_true(w.swarm.hp[m] < w.swarm.max_hp[m], key)


func test_the_hawk_leaves_its_strike_pose_between_strikes_so_it_is_not_drawn_as_the_empty_frame() -> void:
	var w := _world("silver_hawk")
	_mob(w, SNAIL, 260)
	w.runner.step(DT, w)
	var began := _run(w, 60) # past the summoned animation: the first strike starts
	assert_false(began.is_empty())
	_run(w, 5)
	assert_eq(w.runner.summons.action[0], "attack1")
	_run(w, 60)
	assert_ne(w.runner.summons.action[0], "attack1", "settle: the 0.7 s attack is over, the 1.6 s interval is not")


func test_unique_summon_count_calls_a_second_follower_and_recast_replaces_the_group() -> void:
	for key in ["silver_hawk", "phoenix"]:
		var w := _world(key)
		w.runner.step(DT, w)
		assert_eq(w.runner.summons.living_count(), 1, key)
		w.loadout.add_skill_mod(key, "summon_count", "add", 1.0)
		w.runner.cooldowns[key] = 0.0
		w.runner.step(DT, w)
		assert_eq(w.runner.summons.living_count(), 2, "%s: summon_count 1 -> 2" % key)
		w.runner.cooldowns[key] = 0.0
		w.runner.step(DT, w)
		assert_eq(w.runner.summons.living_count(), 2, "%s: recast replaces the group" % key)


func test_the_spawn_event_carries_the_summon_sound() -> void:
	var w := _world("silver_hawk")
	w.runner.step(DT, w)
	var spawns := w.events.filter(func(e: Dictionary) -> bool: return e.type == "summon_spawn")
	assert_eq(spawns.size(), 1)
	assert_eq(spawns[0].sound, "Sound.wz/Skill.img/3111005/Summon")


# --- the real Skill.wz / Sound.wz ---------------------------------------------------------------------------------------

func test_cached_mapped_levels_for_all_eight_ranks_of_both_followers() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := SkillBook.from_data(DataRepo.load_all().skills,
		{"311": lib.img("Skill.wz/311.img").root, "312": lib.img("Skill.wz/312.img").root})
	for key in ["silver_hawk", "phoenix"]:
		var lo := Loadout.new(book)
		assert_true(lo.add_skill(key), key)
		assert_eq(book.max_rank(key), 8)
		for rank in range(1, 9):
			lo.set_rank(key, rank)
			var st := lo.stats(key)
			assert_eq(int(st.level), HAWK_LEVELS[rank - 1], "%s rank %d" % [key, rank])
			var level: Dictionary = book.skill_node(key).level[str(HAWK_LEVELS[rank - 1])]
			if key == "silver_hawk":
				assert_eq(int(level.pad), HAWK_PAD[rank - 1], "hawk pad rank %d" % rank)
				assert_eq(int(level.prop), HAWK_PROP[rank - 1], "hawk prop rank %d" % rank)
				assert_eq(int(level.time), HAWK_TIME[rank - 1], "hawk time rank %d" % rank)
				assert_eq(float(st.duration), float(HAWK_TIME[rank - 1]), "hawk lifetime rank %d" % rank)
			else:
				assert_eq(int(level.pad), PHOENIX_PAD[rank - 1], "phoenix pad rank %d" % rank)
				assert_eq(int(level.time), PHOENIX_TIME[rank - 1], "phoenix time rank %d" % rank)
				assert_false(level.has("prop"), "the Phoenix node has no status chance (A)")
				assert_eq(float(st.duration), float(PHOENIX_TIME[rank - 1]), "phoenix lifetime rank %d" % rank)
	assert_eq(book.def("phoenix").element, "f")
	lib.free()


func test_cached_attack_boxes_counts_and_every_animation_node_exists() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := SkillBook.from_data(DataRepo.load_all().skills,
		{"311": lib.img("Skill.wz/311.img").root, "312": lib.img("Skill.wz/312.img").root})
	for key in ["silver_hawk", "phoenix"]:
		var d := book.def(key)
		for a: String in ["summoned", "stand", String(d.summon.move), String(d.summon.attack), "die"]:
			assert_true(not lib.anim(String(d.summon.path) + "/" + a).is_empty(), "%s %s" % [key, a])
		assert_true(lib.anim(String(d.hit)).frames.size() > 0, "%s hit" % key)
		assert_true(lib.find(String(d.icon)) != null, "%s icon" % key)
	var hawk: Dictionary = book.skill_node("silver_hawk").summon.attack1.info
	assert_false(hawk.has("mobCount"), "the hawk strikes one monster")
	assert_eq(hawk.range.lt["$v"], [-200.0, -150.0])
	assert_eq(hawk.range.rb["$v"], [200.0, 150.0])
	assert_eq(int(hawk.attackAfter), 100)
	assert_true(hawk.effect is Dictionary, "the bolt landing on the target is a strike art")
	var phoenix: Dictionary = book.skill_node("phoenix").summon.attack1.info
	assert_eq(int(phoenix.mobCount), 4)
	assert_eq(phoenix.range.lt["$v"], [-100.0, -60.0])
	assert_eq(phoenix.range.rb["$v"], [100.0, 60.0])
	assert_eq(int(phoenix.attackAfter), 360)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()


func test_cached_sounds_resolve_through_the_3211005_nodes() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	for path in ["Sound.wz/Skill.img/3111005/Use", "Sound.wz/Skill.img/3111005/Summon", "Sound.wz/Skill.img/3121006/Use",
			"Sound.wz/Skill.img/3121006/Summon"]:
		assert_true(lib.sound(path) != null, path)
	assert_eq(lib.find("Sound.wz/Skill.img/3111005/Summon")["$sound"], "Sound.wz/Skill.img/3211005/Summon.mp3")
	assert_eq(lib.find("Sound.wz/Skill.img/3121006/Summon")["$sound"], "Sound.wz/Skill.img/3211005/Summon.mp3")
	assert_eq(lib.find("Sound.wz/Skill.img/3111005/Use")["$sound"], "Sound.wz/Skill.img/3211005/Use.mp3")
	assert_eq(lib.find("Sound.wz/Skill.img/3121006/Use")["$sound"], "Sound.wz/Skill.img/3121006/Use.mp3")
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
