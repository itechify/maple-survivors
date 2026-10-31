extends TestCase
## Golden Eagle (3211005) and Frostprey (3221005), the Marksman physical followers (spec #360, ticket MS9 #369): the shipped
## definitions in skills/marksman.json on Skill.wz-shaped synthetic books 321/322 held with a crossbow, their rarity bonuses,
## and the mapped WZ levels and animation nodes against the real cache. Seeded RNG, fixed dt. The Silver Hawk and Phoenix
## (test_bowmaster_followers) are the seam these two reuse and must stay unchanged.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CROSSBOW := 1462001
const SNAIL := 1110100
const BOSS := 2220000
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const KEYS := ["golden_eagle", "frostprey"]
const TIERS := ["rare", "epic", "unique", "legendary"]

## Independent facts from Skill.wz (v83, tier A) at the eight mapped levels, written out as literals.
const EAGLE_PAD := [32, 44, 56, 65, 77, 86, 94, 100]
const EAGLE_PROP := [59, 71, 82, 88, 93, 96, 98, 99]
const EAGLE_TIME := [112, 124, 136, 145, 160, 168, 176, 180]
const FROSTPREY_PAD := [270, 290, 360, 375, 395, 465, 485, 500]
const FROSTPREY_TIME := [122, 134, 146, 155, 167, 179, 191, 200]


## Generic books: pad = 10 x level, prop = 40 + 2 x level (level 30 = 100), time 60 s. The follower nodes carry the shape of
## the real ones: a body frame then a placeholder for the eagle, a long attack for the frostprey.
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


func _world(key: String, p_seed := 369) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", p_seed, data)
	setup.data.stages.stages.quiet.maps.append(setup.data.stages.stages.quiet.maps[0].duplicate(true)) # a second map to transfer to
	setup["job"] = 322
	var eagle_attack := {"0": {"delay": 100.0}, "1": {"delay": 600.0}}
	setup.skill_imgs["321"] = {"skill": {"3211005": {"level": _levels(),
		"summon": _summon_node([-200, -150, 200, 150], 100.0, 0, eagle_attack)}}}
	setup.skill_imgs["322"] = {"skill": {"3221005": {"level": _levels(), "elemAttr": "i",
		"summon": _summon_node([-100, -60, 100, 60], 1440.0, 4, _frames(11, 90.0))}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.wear_new_item(CROSSBOW)
	assert_true(w.learn_skill(key), "%s is learnable by a Marksman" % key)
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


## Ticks until the first strike began (plus `after` more ticks for its damage to land).
func _to_first_strike(w: RunWorld, after := 0) -> void:
	var first := _run(w, 1)
	while first.is_empty():
		first = _run(w, 1)
	_run(w, after)


# --- definitions ------------------------------------------------------------------------------------------------------

func test_the_two_followers_are_defined_physical_summons_of_the_322_pool() -> void:
	var data := RF.quiet_data()
	var skills: Dictionary = data.skills.skills
	for key in KEYS:
		var d: Dictionary = skills[key]
		assert_eq(String(d.kind), "summon", key)
		assert_eq(String(d.slot), "active", key)
		assert_eq(String(d.damage), "physical", key)
		assert_eq(String(d.cast.rule), "summon", key)
		assert_eq(String(d.action), "alert2", key)
		assert_eq(String(d.summon.move), "fly", key)
		assert_eq(String(d.summon.attack), "attack1", key)
		assert_eq(String(d.summon.watk_field), "pad", key)
		assert_true(bool(d.summon.settle), "%s: the 1x1 placeholder frame must not hide the follower (B6)" % key)
		assert_true(float(d.summon.hover) > 0.0 and float(d.summon.hover) <= 30.0, "%s: small hover (B6 finding)" % key)
		assert_false(d.has("weapon_families"), "%s: weapons gate nothing" % key)
		assert_true(key in data.jobs_survivor.jobs["322"].skill_pool, key)
	assert_eq(int(skills.golden_eagle.skill_id), 3211005)
	assert_eq([String(skills.golden_eagle.book), int(skills.golden_eagle.job)], ["321", 321])
	assert_eq(int(skills.frostprey.skill_id), 3221005)
	assert_eq([String(skills.frostprey.book), int(skills.frostprey.job)], ["322", 322])
	assert_eq(float(skills.golden_eagle.cooldown), 30.0)
	assert_eq(float(skills.frostprey.cooldown), 40.0)
	assert_eq(float(skills.golden_eagle.summon.attack_interval), 1.6)
	assert_eq(float(skills.frostprey.summon.attack_interval), 3.0)
	assert_false(skills.golden_eagle.has("element"), "the eagle is neutral")
	assert_eq(String(skills.frostprey.element), "i")
	assert_eq(String(skills.golden_eagle.on_hit.status), "stun")
	assert_eq(String(skills.golden_eagle.on_hit.chance_field), "prop")
	assert_eq(float(skills.golden_eagle.on_hit.duration), 1.5)
	assert_false(skills.frostprey.has("on_hit"), "the Frostprey node has no status (A)")
	assert_eq(String(skills.golden_eagle.summon.path), "Skill.wz/321.img/skill/3211005/summon")
	assert_eq(String(skills.frostprey.summon.path), "Skill.wz/322.img/skill/3221005/summon")
	assert_eq(String(skills.golden_eagle.sounds.summon), "Sound.wz/Skill.img/3211005/Summon")
	assert_eq(String(skills.frostprey.sounds.summon), "Sound.wz/Skill.img/3221005/Summon")
	assert_eq(String(skills.golden_eagle.sounds.use), "Sound.wz/Skill.img/3211005/Use")
	assert_eq(String(skills.frostprey.sounds.use), "Sound.wz/Skill.img/3221005/Use")


func test_the_eagle_and_frostprey_mirror_the_hawk_and_the_phoenix_except_for_what_the_spec_names() -> void:
	var skills: Dictionary = RF.quiet_data().skills.skills
	for pair: Array in [["golden_eagle", "silver_hawk"], ["frostprey", "phoenix"]]:
		var mine: Dictionary = skills[pair[0]]
		var theirs: Dictionary = skills[pair[1]]
		for field: String in ["kind", "slot", "damage", "cooldown", "action", "action_time", "cast", "rotate"]:
			assert_eq(mine[field], theirs[field], "%s.%s" % [pair[0], field])
		var a: Dictionary = (mine.summon as Dictionary).duplicate()
		var b: Dictionary = (theirs.summon as Dictionary).duplicate()
		a.erase("path")
		b.erase("path")
		assert_eq(a, b, "%s: the follower settings are the %s's" % [pair[0], pair[1]])
	assert_eq(skills.golden_eagle.on_hit, skills.silver_hawk.on_hit)


# --- Golden Eagle -----------------------------------------------------------------------------------------------------

func test_eagle_strikes_one_monster_per_1_6_seconds() -> void:
	var w := _world("golden_eagle")
	var mobs := [_mob(w, SNAIL, 240), _mob(w, SNAIL, 270), _mob(w, SNAIL, 160)]
	w.runner.step(DT, w)
	var attacks := _run(w, 500)
	assert_true(attacks.size() >= 4, "attacks: %d" % attacks.size())
	for k in range(1, attacks.size()):
		assert_true(absi(int(attacks[k]) - int(attacks[k - 1]) - 96) <= 1, "1.6 s between strikes: %d" % (attacks[k] - attacks[k - 1]))
	var w2 := _world("golden_eagle")
	var again := [_mob(w2, SNAIL, 240), _mob(w2, SNAIL, 270), _mob(w2, SNAIL, 160)]
	w2.runner.step(DT, w2)
	_to_first_strike(w2, 12)
	assert_eq(_struck(w2, again), 1, "one monster per strike")
	assert_true(_struck(w, mobs) >= 1)


func test_eagle_attack_box_is_200_by_150_around_the_follower() -> void:
	var w := _world("golden_eagle")
	w.runner.step(DT, w)
	_run(w, 120) # past the summoned animation: it stands at its trailing point
	var fx: float = w.runner.summons.x[0]
	var inside := _mob(w, SNAIL, fx + 190.0)
	var outside := _mob(w, SNAIL, fx + 260.0)
	_to_first_strike(w, 12)
	assert_true(w.swarm.hp[inside] < w.swarm.max_hp[inside], "inside the +-200 box")
	assert_eq(w.swarm.hp[outside], w.swarm.max_hp[outside], "outside the box: untouched")


func test_eagle_damage_is_the_pad_of_the_rank_in_the_crossbow_row() -> void:
	var w := _world("golden_eagle")
	var st := w.loadout.stats("golden_eagle")
	assert_eq(int(st.level), 4)
	# Crossbow row 3.6 x DEX + STR = 380 over pad 40 (level 4 of the generic table): 152; a bow's row would be 144.
	assert_near(st.damage_max, 152.0, 0.001)
	assert_eq(st.damage_type, "physical")
	w.loadout.set_rank("golden_eagle", 8)
	assert_near(w.loadout.stats("golden_eagle").damage_max, 380.0 * 3.0, 0.001)
	w.loadout.watk = 900.0 # the worn crossbow plus ammo: a follower must ignore it, pad is its W.Att
	assert_near(w.loadout.stats("golden_eagle").damage_max, 380.0 * 3.0, 0.001)


func test_eagle_stuns_by_prop_for_one_and_a_half_seconds_and_bosses_resist() -> void:
	var stunned := 0
	for seed_value in range(1, 21):
		var w := _world("golden_eagle", seed_value)
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


func test_eagle_stun_draws_one_stream_1_roll_per_hit_below_100_and_none_at_100() -> void:
	var w := _world("golden_eagle")
	var snail := _mob(w, SNAIL, 260)
	var level := int(w.loadout.stats("golden_eagle").level)
	assert_true(w.book.canonical("golden_eagle", level, "prop") < 100.0, "the generic table's prop at rank 1 is below 100")
	var reference := RandomNumberGenerator.new()
	reference.state = w.rng.state
	reference.randf()
	w._on_player_hit(snail, {"skill": "golden_eagle", "level": level, "element": ""})
	assert_eq(w.rng.state, reference.state, "exactly one stream-1 draw")
	w.loadout.set_rank("golden_eagle", 8)
	level = int(w.loadout.stats("golden_eagle").level)
	assert_eq(w.book.canonical("golden_eagle", level, "prop"), 100.0)
	var before := w.rng.state
	w._on_player_hit(snail, {"skill": "golden_eagle", "level": level, "element": ""})
	assert_eq(w.rng.state, before, "a 100% chance draws nothing")
	assert_true(w.swarm.status_time(snail, MobSwarm.STUN) > 1.0, "and always stuns")


func test_eagle_prop_100_stuns_every_strike() -> void:
	for seed_value in range(1, 6):
		var w := _world("golden_eagle", seed_value)
		w.loadout.set_rank("golden_eagle", 8)
		var snail := _mob(w, SNAIL, 260)
		w.runner.step(DT, w)
		_run(w, 70)
		assert_true(w.swarm.status_time(snail, MobSwarm.STUN) > 1.0, "seed %d" % seed_value)


func test_eagle_is_neutral() -> void:
	var w := _world("golden_eagle")
	var immune := _mob(w, SNAIL, 260)
	w.swarm.mob_kind(immune).elements = {"I": 0.0, "F": 0.0}
	w.runner.step(DT, w)
	_run(w, 70)
	assert_true(w.swarm.hp[immune] < w.swarm.max_hp[immune], "an ice- and fire-immune monster is still struck by the neutral eagle")


# --- Frostprey --------------------------------------------------------------------------------------------------------

func test_frostprey_strikes_up_to_four_monsters_per_3_seconds() -> void:
	var w := _world("frostprey")
	var mobs := []
	for k in 6:
		mobs.append(_mob(w, SNAIL, 230.0 + 15.0 * k))
	w.runner.step(DT, w)
	var attacks := _run(w, 800)
	assert_true(attacks.size() >= 3, "attacks: %d" % attacks.size())
	for k in range(1, attacks.size()):
		assert_true(absi(int(attacks[k]) - int(attacks[k - 1]) - 180) <= 1, "3.0 s between strikes")
	var one := _world("frostprey")
	var six := []
	for k in 6:
		six.append(_mob(one, SNAIL, 230.0 + 15.0 * k))
	one.runner.step(DT, one)
	_to_first_strike(one, 100)
	assert_eq(_struck(one, six), 4, "mobCount 4: four of six")
	assert_true(_struck(w, mobs) >= 4)


func test_frostprey_damage_lands_at_attack_after_1440_ms_inside_the_cycle() -> void:
	var w := _world("frostprey")
	var m := _mob(w, SNAIL, 240)
	w.runner.step(DT, w)
	_to_first_strike(w, 0)
	var ticks_to_damage := 0
	while w.swarm.hp[m] == w.swarm.max_hp[m] and ticks_to_damage < 400:
		_run(w, 1)
		ticks_to_damage += 1
	# attackAfter 1440 ms = 86.4 ticks after the strike began (the tick that began it already ran once).
	assert_true(absi(ticks_to_damage - 86) <= 2, "damage landed %d ticks after the strike began" % ticks_to_damage)
	assert_true(ticks_to_damage < 180, "inside the 3.0 s cycle")


func test_frostprey_attack_box_is_100_by_60_around_the_follower() -> void:
	var w := _world("frostprey")
	w.runner.step(DT, w)
	_run(w, 120)
	var fx: float = w.runner.summons.x[0]
	var inside := _mob(w, SNAIL, fx + 90.0)
	var outside := _mob(w, SNAIL, fx + 160.0)
	_to_first_strike(w, 100)
	assert_true(w.swarm.hp[inside] < w.swarm.max_hp[inside], "inside the +-100 box")
	assert_eq(w.swarm.hp[outside], w.swarm.max_hp[outside], "outside the box: untouched")


func test_frostprey_is_ice_and_applies_no_status() -> void:
	var immune_world := _world("frostprey")
	var immune := _mob(immune_world, SNAIL, 240)
	immune_world.swarm.mob_kind(immune).elements = {"I": 0.0}
	immune_world.runner.step(DT, immune_world)
	_to_first_strike(immune_world, 100)
	assert_eq(immune_world.swarm.hp[immune], immune_world.swarm.max_hp[immune], "ice-immune: unharmed")
	var w := _world("frostprey")
	var plain := _mob(w, SNAIL, 240)
	w.runner.step(DT, w)
	_to_first_strike(w, 100)
	assert_true(w.swarm.hp[plain] < w.swarm.max_hp[plain], "a neutral monster is hurt")
	for status in [MobSwarm.STUN, MobSwarm.FREEZE]:
		assert_eq(w.swarm.status_time(plain, status), 0.0, "the node has no status (A)")
	var fire_immune := _world("frostprey")
	var f := _mob(fire_immune, SNAIL, 240)
	fire_immune.swarm.mob_kind(f).elements = {"F": 0.0}
	fire_immune.runner.step(DT, fire_immune)
	_to_first_strike(fire_immune, 100)
	assert_true(fire_immune.swarm.hp[f] < fire_immune.swarm.max_hp[f], "a fire-immune monster is not special to ice")


func test_frostprey_pad_is_the_w_att_in_the_crossbow_row() -> void:
	var w := _world("frostprey")
	var st := w.loadout.stats("frostprey")
	assert_near(st.damage_max, 380.0 * 0.4, 0.001, "pad 40 at level 4 of the generic table, crossbow row")
	assert_eq(st.damage_type, "physical")
	assert_eq(st.element, "i")


# --- both -------------------------------------------------------------------------------------------------------------

func test_both_followers_hover_above_the_trailing_point_and_follow_on_the_fly_node() -> void:
	for key in KEYS:
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
	for key in KEYS:
		var w := _world(key)
		var m := _mob(w, SNAIL, 240)
		w.runner.step(DT, w)
		_run(w, 160)
		assert_true(w.swarm.hp[m] < w.swarm.max_hp[m], key)


func test_the_eagle_leaves_its_strike_pose_between_strikes_so_it_is_not_drawn_as_the_empty_frame() -> void:
	var w := _world("golden_eagle")
	_mob(w, SNAIL, 260)
	w.runner.step(DT, w)
	var began := _run(w, 60)
	assert_false(began.is_empty())
	_run(w, 5)
	assert_eq(w.runner.summons.action[0], "attack1")
	_run(w, 60)
	assert_ne(w.runner.summons.action[0], "attack1", "settle: the 0.7 s attack is over, the 1.6 s interval is not")


func test_unique_summon_count_calls_a_second_follower_and_recast_replaces_the_group() -> void:
	for key in KEYS:
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


func test_map_transfer_clears_the_followers() -> void:
	for key in KEYS:
		var w := _world(key)
		w.runner.step(DT, w)
		assert_eq(w.runner.summons.living_count(), 1, key)
		w.transfer_pending = true
		w.advance_map()
		assert_eq(w.runner.summons.living_count(), 0, "%s: map transfer clears" % key)


func test_a_dead_or_hidden_caster_s_followers_do_not_attack() -> void:
	for key in KEYS:
		var dead := _world(key)
		var near := _mob(dead, SNAIL, 240)
		dead.runner.step(DT, dead)
		dead.player_state.dead = true
		_run(dead, 200)
		assert_eq(dead.swarm.hp[near], dead.swarm.max_hp[near], "%s: a dead caster's follower does not attack" % key)
		var hidden := _world(key)
		var seen := _mob(hidden, SNAIL, 240)
		hidden.runner.step(DT, hidden)
		assert_true(hidden.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 20.0,
			"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}}))
		assert_true(hidden.is_hidden())
		assert_true(_run(hidden, 200).is_empty(), "%s: a hidden caster's follower begins no strike" % key)
		assert_eq(hidden.swarm.hp[seen], hidden.swarm.max_hp[seen], key)


func test_the_spawn_event_carries_the_summon_sound() -> void:
	for key in KEYS:
		var w := _world(key)
		w.runner.step(DT, w)
		var spawns := w.events.filter(func(e: Dictionary) -> bool: return e.type == "summon_spawn")
		assert_eq(spawns.size(), 1, key)
		assert_eq(spawns[0].sound, String(w.book.def(key).sounds.summon), key)


func test_both_followers_are_scored_explicitly_by_the_bot() -> void:
	var scores: Dictionary = RF.quiet_data().balance.bot.card_scores
	for key in KEYS:
		assert_eq(float(scores[key + "_new"]), 100.0, key)
		assert_eq(float(scores[key + "_rank"]), 74.0, key)


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

## skill -> [rare, epic, unique] as [id, text, [stat, op, value]]; Legendary is the Unique's id and effect plus damage x1.2.
const BONUSES := {
	"golden_eagle": [["crossbow_mastery", "Crossbow Mastery", ["damage", "mul", 1.2]], ["eagle_eyes", "Eagle Eyes", ["area", "mul", 1.2]],
		["second_eagle", "Second Eagle", ["summon_count", "add", 1.0]]],
	"frostprey": [["marksman_boost", "Marksman Boost", ["damage", "mul", 1.2]], ["cold_wings", "Cold Wings", ["count", "add", 1.0]],
		["second_frostprey", "Second Frostprey", ["summon_count", "add", 1.0]]],
}


func test_the_catalog_lists_all_four_rarities_exactly_as_the_spec_table() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in BONUSES:
		var bonuses: Dictionary = skills[key].rarity_bonuses
		var expected: Array = BONUSES[key]
		for t in 3:
			var tier: String = TIERS[t]
			assert_eq(bonuses[tier].size(), 1, "%s %s: one bonus" % [key, tier])
			var entry: Dictionary = bonuses[tier][0]
			assert_eq(String(entry.id), expected[t][0], "%s %s id" % [key, tier])
			assert_eq(String(entry.text), expected[t][1], "%s %s names the lineage passive" % [key, tier])
			assert_eq(entry.effects.size(), 1)
			var effect: Dictionary = entry.effects[0]
			assert_eq([String(effect.stat), String(effect.op), float(effect.value)], expected[t][2], "%s %s effect" % [key, tier])
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(bonuses.legendary.size(), 1)
		assert_eq(String(legendary.id), String(bonuses.unique[0].id), "%s: Legendary shares the Unique's repeat counter" % key)
		assert_eq(legendary.effects.size(), 2)
		var unique_effect: Dictionary = bonuses.unique[0].effects[0]
		assert_eq([String(legendary.effects[0].stat), String(legendary.effects[0].op), float(legendary.effects[0].value)],
			[String(unique_effect.stat), String(unique_effect.op), float(unique_effect.value)])
		assert_eq([String(legendary.effects[1].stat), String(legendary.effects[1].op), float(legendary.effects[1].value)],
			["damage", "mul", 1.2])


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus_and_the_preview_is_stable() -> void:
	for key: String in BONUSES:
		for tier: String in TIERS:
			var a := _world(key, 369)
			var b := _world(key, 369)
			var id := key + "_rank"
			assert_eq(a.loadout.rank(key), 1)
			var c := a.upgrades.choice_card(id, a, tier)
			assert_false(c.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			assert_eq(c, a.upgrades.choice_card(id, a, tier), "the preview does not spend the bonus")
			a.upgrades.apply(id, a, tier)
			b.upgrades.apply(id, b, tier)
			assert_eq(a.loadout.rank(key), 2, "%s %s: exactly one rank on top" % [key, tier])
			assert_eq(a.loadout.skill_mods.get(key, {}), b.loadout.skill_mods.get(key, {}), "%s %s: same bonus twice" % [key, tier])
			assert_false(a.loadout.skill_mods.get(key, {}).is_empty(), "%s %s: the bonus is applied" % [key, tier])


func test_legendary_shares_the_uniques_counter_and_repeats_shrink_by_0_8() -> void:
	for key: String in BONUSES:
		var w := _world(key, 369)
		var unique_id: String = BONUSES[key][2][0]
		w.upgrades.apply(key + "_rank", w, "unique")
		assert_near(w.loadout.skill_stat(key, "summon_count", 1.0), 2.0, 0.00001, "%s: the first Unique is a full +1" % key)
		w.upgrades.apply(key + "_rank", w, "legendary")
		assert_near(w.loadout.skill_stat(key, "summon_count", 1.0), 2.0 + 0.8, 0.00001, "%s: Legendary repeats the Unique's bonus x0.8" % key)
		assert_eq(int(w.loadout.card_ranks["bonus:%s:%s" % [key, unique_id]]), 2, "%s: one shared counter" % key)
		# Legendary's damage x1.2 is its own (first) application on the Rare's counter-free path.
		assert_true(w.loadout.skill_stat(key, "damage", 1.0) > 1.0, "%s: Legendary adds damage" % key)


func test_mastery_after_rank_8_repeats_shrink_by_0_8() -> void:
	for key: String in BONUSES:
		var w := _world(key, 369)
		w.loadout.set_rank(key, 8)
		var c := w.upgrades.choice_card(key + "_rank", w, "rare")
		assert_eq(c.card_kind, "mastery", key)
		w.upgrades.apply(key + "_rank", w, "rare")
		w.upgrades.apply(key + "_rank", w, "rare")
		assert_eq(w.loadout.rank(key), 8, "%s: Mastery never raises the rank" % key)
		assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2 * (1.0 + 0.2 * 0.8), 0.00001, "%s: second repeat x1.16" % key)


# --- the real Skill.wz / Sound.wz ---------------------------------------------------------------------------------------

func _cached_book(lib: AssetLibrary) -> SkillBook:
	return SkillBook.from_data(DataRepo.load_all().skills,
		{"321": lib.img("Skill.wz/321.img").root, "322": lib.img("Skill.wz/322.img").root})


func test_cached_mapped_levels_for_all_eight_ranks_of_both_followers() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := _cached_book(lib)
	for key in KEYS:
		var lo := Loadout.new(book)
		assert_true(lo.add_skill(key), key)
		assert_eq(book.max_rank(key), 8)
		assert_eq(book.max_level(key), 30, key)
		for rank in range(1, 9):
			lo.set_rank(key, rank)
			var st := lo.stats(key)
			assert_eq(int(st.level), LEVELS[rank - 1], "%s rank %d" % [key, rank])
			var level: Dictionary = book.skill_node(key).level[str(LEVELS[rank - 1])]
			if key == "golden_eagle":
				assert_eq(int(level.pad), EAGLE_PAD[rank - 1], "eagle pad rank %d" % rank)
				assert_eq(int(level.prop), EAGLE_PROP[rank - 1], "eagle prop rank %d" % rank)
				assert_eq(int(level.time), EAGLE_TIME[rank - 1], "eagle time rank %d" % rank)
				assert_eq(float(st.duration), float(EAGLE_TIME[rank - 1]), "eagle lifetime rank %d" % rank)
			else:
				assert_eq(int(level.pad), FROSTPREY_PAD[rank - 1], "frostprey pad rank %d" % rank)
				assert_eq(int(level.time), FROSTPREY_TIME[rank - 1], "frostprey time rank %d" % rank)
				assert_false(level.has("prop"), "the Frostprey node has no status chance (A)")
				assert_eq(float(st.duration), float(FROSTPREY_TIME[rank - 1]), "frostprey lifetime rank %d" % rank)
	# The spec's worked rank values (rank 1 / 4 / 8) as literals.
	for i in 3:
		var rank: int = [1, 4, 8][i]
		assert_eq(int(book.skill_node("golden_eagle").level[str(LEVELS[rank - 1])].pad), [32, 65, 100][i])
		assert_eq(int(book.skill_node("golden_eagle").level[str(LEVELS[rank - 1])].prop), [59, 88, 99][i])
		assert_eq(int(book.skill_node("golden_eagle").level[str(LEVELS[rank - 1])].time), [112, 145, 180][i])
		assert_eq(int(book.skill_node("frostprey").level[str(LEVELS[rank - 1])].pad), [270, 375, 500][i])
		assert_eq(int(book.skill_node("frostprey").level[str(LEVELS[rank - 1])].time), [122, 155, 200][i])
	assert_eq(book.def("frostprey").element, "i")
	assert_eq(String(book.skill_node("frostprey").elemAttr), "i")
	lib.free()


func test_cached_the_eagle_mirrors_the_hawk_s_pad_and_stun_chance_level_for_level() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var eagle: Dictionary = lib.img("Skill.wz/321.img").root.skill["3211005"].level
	var hawk: Dictionary = lib.img("Skill.wz/311.img").root.skill["3111005"].level
	for lv in range(1, 31):
		for field: String in ["pad", "prop"]:
			assert_eq(eagle[str(lv)][field], hawk[str(lv)][field], "level %d %s" % [lv, field])
		# The spec calls the tables identical; the lifetime differs by 2-3 s at levels 19-29 (the ends match).
		assert_true(absf(float(eagle[str(lv)].time) - float(hawk[str(lv)].time)) <= 3.0, "level %d time" % lv)
	assert_eq(eagle["30"].time, hawk["30"].time)
	lib.free()


func test_cached_attack_boxes_counts_and_every_animation_node_exists() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var book := _cached_book(lib)
	for key in KEYS:
		var d := book.def(key)
		for a: String in ["summoned", "stand", String(d.summon.move), String(d.summon.attack), "die"]:
			assert_true(not lib.anim(String(d.summon.path) + "/" + a).is_empty(), "%s %s" % [key, a])
		assert_true(lib.anim(String(d.hit)).frames.size() > 0, "%s hit" % key)
		assert_true(lib.find(String(d.icon)) != null, "%s icon" % key)
	var eagle: Dictionary = book.skill_node("golden_eagle").summon.attack1.info
	assert_false(eagle.has("mobCount"), "the eagle strikes one monster")
	assert_eq(eagle.range.lt["$v"], [-200.0, -150.0])
	assert_eq(eagle.range.rb["$v"], [200.0, 150.0])
	assert_eq(int(eagle.attackAfter), 100)
	var frostprey: Dictionary = book.skill_node("frostprey").summon.attack1.info
	assert_eq(int(frostprey.mobCount), 4)
	assert_eq(frostprey.range.lt["$v"], [-100.0, -60.0])
	assert_eq(frostprey.range.rb["$v"], [100.0, 60.0])
	assert_eq(int(frostprey.attackAfter), 1440)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()


func test_cached_sounds_resolve() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	for path in ["Sound.wz/Skill.img/3211005/Use", "Sound.wz/Skill.img/3211005/Summon", "Sound.wz/Skill.img/3221005/Use",
			"Sound.wz/Skill.img/3221005/Summon"]:
		assert_true(lib.sound(path) != null, path)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
