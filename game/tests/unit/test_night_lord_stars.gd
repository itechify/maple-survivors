extends TestCase
## Night Lord's core stars (spec #383, ticket NL7 #406): Lucky Seven and Drain ported into the `night_lord` line, Avenger
## (`pierce_field`, own rotating ball) and Triple Throw (`cast.focus`), their rarity bonuses and the first two status grants
## (Venomous Star on Lucky Seven's Epic, Stunning Avenger on Avenger's). Fixed 1/60 s ticks, seeded RNG, a claw in hand. The
## behaviour tests run on synthetic Skill.wz levels shaped like the originals; the real-cache test at the end calls
## require_cache() and SKIPS without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CLAW := 1472000
const LUCKY := "lucky_seven"
const DRAIN := "drain"
const AVENGER := "avenger"
const TRIPLE := "triple_throw"
const KEYS := [LUCKY, DRAIN, AVENGER, TRIPLE]
const LEVELS_20 := [3, 5, 8, 10, 13, 15, 18, 20]
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
## key -> [[tier, id, text, stat, op, value] of Rare, Epic, Unique] (the spec's table; Legendary = Unique + damage x1.2).
const RARITY := {
	LUCKY: [["claw_mastery", "damage", "mul", 1.2], ["venomous_star", "status", "grant", 0.0], ["lucky_eight", "count", "add", 1.0]],
	DRAIN: [["claw_mastery", "damage", "mul", 1.2], ["claw_booster", "cooldown", "mul", 0.88], ["double_drain", "count", "add", 1.0]],
	AVENGER: [["claw_mastery", "damage", "mul", 1.2], ["stunning_avenger", "status", "grant", 0.0], ["deep_avenger", "pierce", "add", 2.0]],
	TRIPLE: [["critical_throw", "crit", "add", 0.15], ["claw_booster", "cooldown", "mul", 0.88], ["fourth_star", "count", "add", 1.0]],
}


## Synthetic Skill.wz levels 1..30 of Avenger (damage 65 -> 180, mobCount 4 / 5 / 6 at levels 1 / 11 / 21).
func _avenger_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": roundf(lerpf(65.0, 180.0, (lv - 1) / 29.0)),
			"mobCount": 4.0 if lv <= 10 else 5.0 if lv <= 20 else 6.0, "bulletConsume": 3.0}
	return levels


## Synthetic levels of Triple Throw (damage 102 -> 150, bulletCount 3).
func _triple_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": roundf(lerpf(102.0, 150.0, (lv - 1) / 29.0)), "bulletCount": 3.0}
	return levels


## A quiet round of a Night Lord holding a claw with `key` learned at `rank_value`; god mode, frozen snail-sized mobs.
func _world(key: String, rank_value := 1, p_seed := 406) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["412"]["playable"] = true # in this test's data only: NL12 ships the flip
	data.balance.player.hp = 500
	data.balance.regen.hp = 0
	data.balance.player.stats = {"str": 4, "dex": 30, "int": 4, "luk": 100}
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({CLAW: {"incPAD": 22, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["avenger", "swingO1"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.skill_imgs["411"] = {"skill": {"4111005": {"level": _avenger_levels()}}}
	setup.skill_imgs["412"] = {"skill": {"4121007": {"weapon": 47, "level": _triple_levels()}}}
	setup["job"] = 412
	var w := RunWorld.new(setup)
	RF.place_player(w, 300)
	if w.weapon_id() != CLAW:
		w.wear_new_item(CLAW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -60, 40, 60) # a level line: the hand is ~30 px up, so a body centred 30 px up is hit head on
		mk.move_speed = 0
		mk.pdd = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill: only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Night Lord" % key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false, hp := 100000000.0) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190.0, 100000.0)
	w.swarm.hp[slot] = int(hp)
	w.swarm.max_hp[slot] = int(hp)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(events: Array, key: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


## Runs `ticks` ticks and returns the mob_hit events of `key` (every other event is dropped).
func _run(w: RunWorld, ticks: int, key: String) -> Array:
	var out := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		out.append_array(_hits(w.drain_events(), key))
	return out


func _by_mob(hits: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in hits:
		out[int(e.mob)] = int(out.get(int(e.mob), 0)) + 1
	return out


func _mod(w: RunWorld, key: String, stat: String, op: String, value: float) -> void:
	w.loadout.add_skill_mod(key, stat, op, value)


func _ammo_visual(w: RunWorld) -> int:
	return w.visual_index(Ammo.bullet_path(w.ammo_id()))


# --- the move ---------------------------------------------------------------------------------------------------------

func test_lucky_seven_and_drain_live_in_the_night_lord_file_only_and_the_legacy_cards_are_gone() -> void:
	var night: Dictionary = DataRepo.load_json("res://data/survivor/skills/night_lord.json").skills
	var thief: Dictionary = DataRepo.load_json("res://data/survivor/skills/thief.json").skills
	for key: String in KEYS:
		assert_true(night.has(key), key + " is in skills/night_lord.json")
		assert_false(thief.has(key), key + " is no longer in skills/thief.json (a repeated key is a load error)")
	var cards: Array = DataRepo.load_json("res://data/survivor/upgrades/thief.json").cards
	for card: Dictionary in cards:
		assert_false(String(card.get("skill", "")) in [LUCKY, DRAIN], "no legacy card is left: %s" % card.id)
	var w := _world(LUCKY)
	for id in ["lucky_seven_new", "lucky_seven_rank", "lucky_seven_count", "lucky_seven_pierce", "lucky_seven_damage",
			"lucky_seven_cooldown", "lucky_seven_range", "drain_new", "drain_rank", "drain_pierce"]:
		assert_true(id.ends_with("_new") or id.ends_with("_rank") or w.upgrades.card(id).is_empty(), id)
	# The pool cards of a playable Night Lord come from add_pool_skills: a new / rank card per pool skill, nothing else.
	for key: String in KEYS:
		assert_false(w.upgrades.card(key + "_rank").is_empty(), key + " has its pool rank card")
		assert_eq(w.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.get("skill", "") == key and c.kind == "skill_mod").size(),
			0, key + " has no standalone modifier card")


func test_the_four_skills_use_the_default_rank_tables_and_the_spec_numbers() -> void:
	var w := _world(LUCKY)
	for key: String in KEYS:
		var d := w.book.def(key)
		assert_false(d.has("ranks"), key + " drops its explicit rank list")
		assert_false(d.has("weapon_families"), key + ": weapons gate nothing")
		assert_eq(w.book.max_rank(key), 8, key)
		assert_eq(String(d.damage), "physical")
		assert_eq(String(d.slot), "active")
		assert_eq(String(d.cast.rule), "nearest")
	assert_eq(w.book.max_level(LUCKY), 20)
	assert_eq(w.book.max_level(DRAIN), 30)
	assert_eq(w.book.max_level(AVENGER), 30)
	assert_eq(w.book.max_level(TRIPLE), 30)
	for r in 8:
		assert_eq(w.book.canonical_level(LUCKY, r + 1), LEVELS_20[r], "Lucky Seven rank %d" % (r + 1))
		for key: String in [DRAIN, AVENGER, TRIPLE]:
			assert_eq(w.book.canonical_level(key, r + 1), LEVELS_30[r], "%s rank %d" % [key, r + 1])


func test_lucky_seven_and_drain_throw_from_the_claws_own_stance_and_echo_as_attacks() -> void:
	var w := _world(LUCKY)
	for key: String in KEYS:
		var d := w.book.def(key)
		# tier C (ROSTER_PLAN D10): shoot1 hides the claw, so the throws use the claw's swing.
		assert_eq(String(d.action), "avenger" if key == AVENGER else "swingO1", key)
		assert_true(d.has("echo"), key + " carries the echo flag")
		assert_eq(String(d.echo["class"]), "skill" if key in [AVENGER, TRIPLE] else "attack", key)
	assert_eq(w.book.def(DRAIN).damage_heal, {"percent_field": "x", "max_hp_fraction": 0.5, "target_max_hp": true})
	var formula: Dictionary = w.book.def(LUCKY).physical_formula
	assert_eq(String(formula.primary), "luk")
	assert_eq(float(formula.max_mult), 5.0)
	assert_eq(float(formula.min_mult), 2.5)
	assert_true(bool(formula.ignore_mastery), "the LUK formula is unchanged")


# --- Lucky Seven -------------------------------------------------------------------------------------------------------

func test_lucky_seven_throws_two_stars_at_the_nearest_with_the_current_ammo() -> void:
	var w := _world(LUCKY)
	var near := _mob(w, 100)
	_mob(w, 180)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 2, "bulletCount 2")
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.visual[i], _ammo_visual(w), "the ammo's art")
	var hits := _run(w, 40, LUCKY)
	assert_eq(hits.size(), 2)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == near), "both stars reach the nearest monster")
	var st := w.loadout.stats(LUCKY)
	assert_eq([st.range, st.speed, st.radius, st.pierce, st.cooldown], [250.0, 600.0, 8.0, 0, 1.0])


func test_lucky_seven_damage_follows_the_rank_and_keeps_the_luk_formula() -> void:
	var w := _world(LUCKY)
	w.loadout.luk_stat = 100
	w.loadout.watk = 50
	w.loadout.mastery = 0.6
	assert_near(w.loadout.stats(LUCKY, 1).damage_pct, 0.68, 0.000001, "rank 1 = level 3 on the fixture table")
	assert_near(w.loadout.stats(LUCKY, 8).damage_pct, 1.50, 0.000001, "rank 8 = level 20")
	var st := w.loadout.stats(LUCKY, 8)
	assert_eq(st.damage_min, 125.0, "LUK x2.5 x W.Att 50, mastery ignored")
	assert_eq(st.damage_max, 250.0)


# --- Drain -------------------------------------------------------------------------------------------------------------

func test_drain_heals_the_rank_share_of_each_hit_and_caps_at_half_max_hp() -> void:
	for r in [1, 4, 8]:
		var w := _world(DRAIN, r)
		w.spend_hp(int(w.player_state.hp) - 1)
		w.drain_events()
		var m := _mob(w, 90)
		var share: float = [19.0, 30.0, 45.0][[1, 4, 8].find(r)]
		w.runner.step(DT, w)
		var events := []
		var hit := {}
		for tick in 40:
			w.step(DT, MoveInput.new())
			for e: Dictionary in w.drain_events():
				events.append(e)
		for e: Dictionary in events:
			if e.type == "mob_hit" and e.skill == DRAIN:
				hit = e
		assert_false(hit.is_empty(), "rank %d hit" % r)
		var gains := events.filter(func(e: Dictionary) -> bool: return e.type == "player_restored" and e.skill == DRAIN)
		assert_eq(gains.size(), 1, "one star, one heal")
		var expected := mini(floori(float(hit.damage) * share / 100.0), floori(float(w.player_state.max_hp) / 2.0))
		assert_eq(int(gains[0].amount), expected, "rank %d absorbs %d%% of the actual hit (capped)" % [r, int(share)])
		assert_eq(int(w.player_state.hp), 1 + expected)
		assert_true(m >= 0)


func test_drain_throws_one_star_and_its_cooldown_range_and_numbers() -> void:
	var w := _world(DRAIN)
	_mob(w, 100)
	_mob(w, 160)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 1)
	assert_near(float(w.runner.cooldowns[DRAIN]), 1.0 - DT, 0.001)
	var st := w.loadout.stats(DRAIN)
	assert_eq([st.range, st.speed, st.radius, st.pierce], [250.0, 600.0, 8.0, 0])


func test_double_drain_sends_a_second_star_at_another_monster_and_each_heals() -> void:
	var w := _world(DRAIN, 8)
	w.upgrades.apply("drain_rank", w, "unique")
	w.loadout.set_rank(DRAIN, 8)
	assert_eq(w.loadout.stats(DRAIN).count, 2)
	w.spend_hp(int(w.player_state.hp) - 1)
	var first := _mob(w, 90)
	var second := _mob(w, -150) # the other side: a star stops at the first monster on its line
	w.drain_events()
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 2)
	var events := []
	for tick in 40:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	var hits := _hits(events, DRAIN)
	assert_eq(_by_mob(hits).keys().size(), 2, "two different monsters")
	assert_true(_by_mob(hits).has(first) and _by_mob(hits).has(second))
	var gains := events.filter(func(e: Dictionary) -> bool: return e.type == "player_restored" and e.skill == DRAIN)
	assert_eq(gains.size(), 2, "each star drains")


# --- Avenger -----------------------------------------------------------------------------------------------------------

func test_avenger_is_one_rotating_star_with_its_own_ball_and_art() -> void:
	var w := _world(AVENGER)
	var d := w.book.def(AVENGER)
	assert_eq(int(d.skill_id), 4111005)
	assert_eq(String(d.book), "411")
	assert_eq(String(d.ball), "Skill.wz/411.img/skill/4111005/ball")
	assert_true(bool(d.rotate), "the 72 x 72 star spins")
	assert_eq(String(d.effect), "Skill.wz/411.img/skill/4111005/effect")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4111005/Use")
	assert_eq(String(d.action), "avenger")
	assert_false(d.get("ammo_shot", false), "no ammo sprite: the WZ star")
	assert_eq(String(d.pierce_field), "mobCount")
	var st := w.loadout.stats(AVENGER)
	assert_eq([st.range, st.speed, st.radius, st.cooldown], [350.0, 700.0, 14.0, 3.5])
	assert_eq(st.pierce_falloff, 0.0, "no falloff along the line")
	_mob(w, 100)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 1)
	assert_near(float(w.runner.cooldowns[AVENGER]), 3.5 - DT, 0.001)
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.paths[w.projectiles.visual[i]], "Skill.wz/411.img/skill/4111005/ball")
			assert_true(w.projectiles.rotate[i] != 0, "and it rotates")


func test_avenger_pierces_mob_count_minus_one_by_rank_with_no_falloff() -> void:
	for row: Array in [[1, 3], [4, 4], [8, 5]]:
		var w := _world(AVENGER, int(row[0]))
		for k in 8:
			_mob(w, 40.0 + 45.0 * k)
		var st := w.loadout.stats(AVENGER)
		assert_eq(st.pierce, int(row[1]), "rank %d: mobCount - 1" % int(row[0]))
		var hits := _run(w, 90, AVENGER)
		var struck := _by_mob(hits)
		assert_eq(struck.size(), int(row[1]) + 1, "rank %d strikes 1 + %d monsters" % [int(row[0]), int(row[1])])
		for count: int in struck.values():
			assert_eq(count, 1, "a star hits each monster once")
		# No falloff: every contact rolls within the same bounds, the last one included.
		var lo: float = st.damage_min * st.damage_pct
		var hi: float = st.damage_max * st.damage_pct
		for e: Dictionary in hits:
			if bool(e.crit):
				continue
			assert_true(float(e.damage) >= floorf(lo) - 1.0 and float(e.damage) <= ceilf(hi) + 1.0,
				"rank %d damage %d inside [%d, %d]" % [int(row[0]), int(e.damage), int(lo), int(hi)])


func test_deep_avenger_adds_two_more_monsters_to_the_line() -> void:
	var w := _world(AVENGER, 1)
	_mod(w, AVENGER, "pierce", "add", 2)
	assert_eq(w.loadout.stats(AVENGER).pierce, 5, "3 from mobCount 4, plus Deep Avenger 2")
	for k in 9:
		_mob(w, 40.0 + 45.0 * k)
	assert_eq(_by_mob(_run(w, 120, AVENGER)).size(), 6)
	assert_eq(w.loadout.stats(AVENGER).mob_count, 4, "mob_count itself is unchanged")


func test_avenger_waits_for_a_monster_within_350_px() -> void:
	var w := _world(AVENGER)
	_mob(w, 400)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0)
	_mob(w, 340)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)


# --- Triple Throw ------------------------------------------------------------------------------------------------------

func test_triple_throw_sends_all_three_stars_at_one_monster() -> void:
	var w := _world(TRIPLE)
	var near := _mob(w, 80)
	_mob(w, 140)
	_mob(w, 200)
	_mob(w, -120)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.projectiles.active_count(), 3, "bulletCount 3")
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.visual[i], _ammo_visual(w), "the current star")
	var hits := _run(w, 45, TRIPLE)
	assert_eq(hits.size(), 3)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == near), "every star reaches the nearest monster")


func test_triple_throw_prefers_a_scheduled_boss_over_a_nearer_monster() -> void:
	var w := _world(TRIPLE)
	_mob(w, 80)
	var boss := _mob(w, -200, true) # the other side: a star stops at the first monster on its line
	w.mob_boss[boss] = 0
	w.runner.step(DT, w)
	var hits := _run(w, 60, TRIPLE)
	assert_eq(hits.size(), 3)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == boss), "all three go to the boss")


func test_triple_throw_numbers_cooldown_and_cast_rule() -> void:
	var w := _world(TRIPLE)
	var d := w.book.def(TRIPLE)
	assert_eq(int(d.skill_id), 4121007)
	assert_eq(String(d.book), "412")
	assert_true(bool(d.cast.focus))
	assert_true(bool(d.ammo_shot))
	assert_eq(String(d.hit), "Skill.wz/412.img/skill/4121007/hit/0")
	assert_eq(String(d.effect), "Skill.wz/412.img/skill/4121007/effect")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4121007/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/4121007/Hit")
	var st := w.loadout.stats(TRIPLE)
	assert_eq([st.count, st.range, st.speed, st.radius, st.pierce, st.cooldown], [3, 300.0, 650.0, 8.0, 0, 2.5])
	_mob(w, 400)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "past the 300 px range")
	_mob(w, 280)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[TRIPLE]), 2.5 - DT, 0.001)


func test_fourth_star_puts_a_fourth_star_into_the_same_monster() -> void:
	var w := _world(TRIPLE, 1)
	_mod(w, TRIPLE, "count", "add", 1)
	var near := _mob(w, 80)
	_mob(w, 140)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 4)
	var hits := _run(w, 45, TRIPLE)
	assert_eq(hits.size(), 4)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == near))


# --- the two status grants ---------------------------------------------------------------------------------------------

const VENOM_CHANCE := [14.0, 16.0, 18.0, 20.0, 24.0, 26.0, 28.0, 30.0]
const VENOM_TIME := [2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0, 4.0]
const VENOM_LEVEL := [4, 8, 12, 15, 19, 23, 27, 30]
const STUN_CHANCE := [20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 45.0, 50.0]


func _hit(w: RunWorld, m: int, st: Dictionary) -> void:
	var damage_rng := RandomNumberGenerator.new()
	damage_rng.seed = 406
	st = st.duplicate(true)
	st.damage_min = 1.0
	st.damage_max = 1.0
	st.damage_type = "fixed"
	st.element = ""
	st.crit = 0.0
	w.hit_mob(m, st, -1, damage_rng)


func test_the_epic_cards_grant_the_status_and_nothing_else_changes() -> void:
	for pair: Array in [[LUCKY, "venomous_star"], [AVENGER, "stunning_avenger"]]:
		var w := _world(pair[0])
		var mods := w.loadout.skill_mods.duplicate(true)
		var card := w.upgrades.choice_card(String(pair[0]) + "_rank", w, "epic")
		assert_true(w.loadout.grants.is_empty(), "a preview awards nothing")
		assert_false(card.get("rarity_bonus", {}).is_empty())
		assert_true(String(pair[1]).replace("_", " ") in String(card.desc).to_lower(), "the card names the status: %s" % card.desc)
		w.upgrades.apply(String(pair[0]) + "_rank", w, "epic")
		assert_eq(w.loadout.grants[pair[0]], [pair[1]])
		assert_eq(w.loadout.skill_mods, mods, "a grant never alters skill_mods")
		assert_eq(w.loadout.rank(pair[0]), 2, "plus the one rank every card gives")
		assert_eq(w.loadout.stats(pair[0]).status_grants.size(), 1)
	# Another skill's stats gain no key.
	var other := _world(DRAIN)
	assert_false(other.loadout.stats(DRAIN).has("status_grants"))


func test_venomous_star_resolves_chance_time_and_poison_level_by_rank() -> void:
	var w := _world(LUCKY)
	w.loadout.add_status_grant(LUCKY, "venomous_star")
	for r in 8:
		var g: Dictionary = w.loadout.stats(LUCKY, r + 1).status_grants[0]
		assert_eq(g.kind, "poison")
		assert_near(float(g.chance), float(VENOM_CHANCE[r]), 0.0001, "rank %d chance" % (r + 1))
		assert_eq(float(g.time), float(VENOM_TIME[r]), "rank %d time" % (r + 1))
		assert_eq(int(g.level), int(VENOM_LEVEL[r]), "rank %d poison level" % (r + 1))


func test_stunning_avenger_resolves_chance_by_rank_and_a_fixed_1_5_s() -> void:
	var w := _world(AVENGER)
	w.loadout.add_status_grant(AVENGER, "stunning_avenger")
	for r in 8:
		var g: Dictionary = w.loadout.stats(AVENGER, r + 1).status_grants[0]
		assert_eq(g.kind, "stun")
		assert_near(float(g.chance), float(STUN_CHANCE[r]), 0.0001, "rank %d chance" % (r + 1))
		assert_eq(float(g.time), 1.5)


func test_a_lucky_seven_hit_poisons_with_the_rank_chance_time_and_level() -> void:
	for r in [1, 4, 8]:
		var w := _world(LUCKY, r)
		w.loadout.add_status_grant(LUCKY, "venomous_star")
		var st := w.loadout.stats(LUCKY)
		var reference := RandomNumberGenerator.new()
		reference.state = w.rng.state
		var applied := 0
		for k in 60:
			var m := RF.put_mob(w, 1110100, 700.0 + 20.0 * k)
			w.swarm.max_hp[m] = 7000
			w.swarm.hp[m] = 7000
			var succeeds := reference.randf() * 100.0 < float(VENOM_CHANCE[r - 1])
			_hit(w, m, st)
			assert_eq(w.swarm.status_time(m, MobSwarm.POISON) > 0.0, succeeds, "rank %d mob %d: one stream-1 draw" % [r, k])
			if succeeds:
				applied += 1
				assert_near(w.swarm.status_time(m, MobSwarm.POISON), float(VENOM_TIME[r - 1]), 0.0001)
				assert_eq(w.swarm._poison_damage[m], ceili(7000.0 / (70 - int(VENOM_LEVEL[r - 1]))), "the v83 level rule")
		assert_true(applied > 0, "rank %d poisoned at least one of 60" % r)
		assert_eq(w.rng.state, reference.state, "exactly one draw per hit, nothing else")


func test_an_avenger_hit_stuns_with_the_rank_chance_and_1_5_s() -> void:
	for r in [1, 8]:
		var w := _world(AVENGER, r)
		w.loadout.add_status_grant(AVENGER, "stunning_avenger")
		var st := w.loadout.stats(AVENGER)
		var reference := RandomNumberGenerator.new()
		reference.state = w.rng.state
		var applied := 0
		for k in 60:
			var m := RF.put_mob(w, 1110100, 700.0 + 20.0 * k)
			var succeeds := reference.randf() * 100.0 < float(STUN_CHANCE[r - 1])
			_hit(w, m, st)
			assert_eq(w.swarm.status_time(m, MobSwarm.STUN) > 0.0, succeeds, "rank %d mob %d" % [r, k])
			if succeeds:
				applied += 1
				assert_near(w.swarm.status_time(m, MobSwarm.STUN), 1.5, 0.0001)
		assert_true(applied > 0)


func test_bosses_reject_both_grants_and_a_sure_chance_draws_nothing() -> void:
	for pair: Array in [[LUCKY, "venomous_star", MobSwarm.POISON], [AVENGER, "stunning_avenger", MobSwarm.STUN]]:
		var w := _world(pair[0])
		w.loadout.add_status_grant(pair[0], pair[1])
		for repeat in 100:
			w.loadout.add_status_grant(pair[0], pair[1]) # repeats raise the chance to the 100 cap
		var st := w.loadout.stats(pair[0])
		assert_eq(float(st.status_grants[0].chance), 100.0)
		var normal := RF.put_mob(w, 1110100, 700)
		var boss := RF.put_mob(w, 2220000, 760)
		w.swarm.max_hp[normal] = 7000
		w.swarm.hp[normal] = 7000
		var before := w.rng.state
		_hit(w, normal, st)
		assert_true(w.swarm.status_time(normal, pair[2]) > 0.0, "%s lands at 100%%" % pair[1])
		assert_eq(w.rng.state, before, "a 100%% chance draws nothing")
		_hit(w, boss, st)
		assert_near(w.swarm.status_time(boss, pair[2]), 0.0, 0.00001, "a boss rejects %s" % pair[1])
	var scheduled := _world(AVENGER)
	scheduled.loadout.add_status_grant(AVENGER, "stunning_avenger")
	for repeat in 100:
		scheduled.loadout.add_status_grant(AVENGER, "stunning_avenger")
	var m := RF.put_mob(scheduled, 1110100, 700)
	scheduled.swarm.steady[m] = 1
	_hit(scheduled, m, scheduled.loadout.stats(AVENGER))
	assert_near(scheduled.swarm.status_time(m, MobSwarm.STUN), 0.0, 0.00001, "a scheduled boss rejects it too")


func test_an_avengers_star_stuns_every_monster_on_its_line_when_it_rolls() -> void:
	var w := _world(AVENGER, 8)
	w.loadout.add_status_grant(AVENGER, "stunning_avenger")
	for repeat in 100:
		w.loadout.add_status_grant(AVENGER, "stunning_avenger")
	var slots := []
	for k in 6:
		slots.append(_mob(w, 40.0 + 45.0 * k))
	w.runner.step(DT, w)
	w.loadout.grants.clear() # the star keeps its cast-time snapshot
	_run(w, 40, AVENGER)
	var stunned := slots.filter(func(s: int) -> bool: return w.swarm.status_time(s, MobSwarm.STUN) > 0.0)
	assert_eq(stunned.size(), 6, "the sure stun reached the whole line")


func test_lucky_seven_stars_carry_the_poison_grant_after_the_loadout_changes() -> void:
	var w := _world(LUCKY, 8)
	w.loadout.add_status_grant(LUCKY, "venomous_star")
	for repeat in 100:
		w.loadout.add_status_grant(LUCKY, "venomous_star")
	var m := _mob(w, 100, false, 7000.0)
	w.runner.step(DT, w)
	w.loadout.grants.clear()
	_run(w, 40, LUCKY)
	assert_true(w.swarm.status_time(m, MobSwarm.POISON) > 0.0, "the flying star kept its snapshot")


func test_the_skill_window_and_card_name_the_grant() -> void:
	var w := _world(LUCKY)
	w.loadout.add_status_grant(LUCKY, "venomous_star")
	var line := SkillText.new(w.book, {}).level_line(LUCKY, w.loadout.level(LUCKY), w.loadout.stats(LUCKY))
	assert_true("Venomous Star: 14% to poison for 2 s" in line, line)
	w.loadout.add_status_grant(AVENGER, "stunning_avenger")
	w.learn_skill(AVENGER)
	var aline := SkillText.new(w.book, {}).level_line(AVENGER, w.loadout.level(AVENGER), w.loadout.stats(AVENGER))
	assert_true("Stunning Avenger: 20% to stun for 1.5 s" in aline, aline)
	assert_true("Pierces up to 3 more monsters" in aline, aline)


# --- rarity bonuses ----------------------------------------------------------------------------------------------------

func test_the_rarity_tables_follow_the_spec() -> void:
	var w := _world(LUCKY)
	for key: String in RARITY:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		var rows: Array = RARITY[key]
		assert_eq(bonuses.keys().size(), 4, "%s: exactly the four tiers" % key)
		for t in 3:
			var tier: String = ["rare", "epic", "unique"][t]
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), String(rows[t][0]), "%s %s" % [key, tier])
			assert_true(String(bonuses[tier][0].text) != "", "%s %s has card text" % [key, tier])
			assert_eq(bonuses[tier][0].effects.size(), 1)
			var effect: Dictionary = bonuses[tier][0].effects[0]
			assert_eq(String(effect.stat), String(rows[t][1]))
			assert_eq(String(effect.op), String(rows[t][2]))
			if String(effect.op) == "grant":
				assert_eq(String(effect.status), String(rows[t][0]), "the grant names the catalogue entry")
				assert_true(w.loadout.status_bonuses.has(effect.status))
			else:
				assert_near(float(effect.value), float(rows[t][3]), 0.0001)
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(String(legendary.id), String(rows[2][0]), "%s: Legendary shares the Unique's id (and its repeat counter)" % key)
		assert_eq(legendary.effects.size(), 2)
		assert_eq(String(legendary.effects[0].stat), String(rows[2][1]))
		assert_eq(String(legendary.effects[1].stat), "damage")
		assert_near(float(legendary.effects[1].value), 1.2, 0.0001)
	assert_eq(w.book.def(LUCKY).rarity_bonuses.epic[0].text, "Venomous Star")
	assert_eq(w.book.def(AVENGER).rarity_bonuses.epic[0].text, "Stunning Avenger")
	assert_eq(w.book.def(TRIPLE).rarity_bonuses.rare[0].text, "Critical Throw")
	assert_eq(w.book.def(DRAIN).rarity_bonuses.unique[0].text, "Double Drain")


func test_the_shipped_data_loads_without_an_error() -> void:
	var errors := PackedStringArray()
	DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "no load error: %s" % [errors])


## What one cast of `key` did after a Rare / Epic / Unique / Legendary rank card (`tier`, "normal" = the bare rank card).
func _probe(key: String, tier: String) -> Dictionary:
	var w := _world(key)
	w.upgrades.apply(key + "_rank", w, tier)
	var st := w.loadout.stats(key)
	var out := {"cooldown": float(st.cooldown), "crit": float(st.crit), "grants": st.get("status_grants", []).size(),
		"count": int(st.count), "pierce": int(st.pierce), "damage": w.loadout.skill_stat(key, "damage", 1.0)}
	# A crowd along the line, so a longer line, a third star or a second target all show as more lines or more monsters.
	for k in 8:
		_mob(w, 40.0 + 45.0 * k)
	var hits := _run(w, 90, key)
	out["lines"] = hits.size()
	out["mobs"] = _by_mob(hits).size()
	var casts := 0
	for tick in 600:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "cast" and e.skill == key:
				casts += 1
	out["casts"] = casts
	return out


func test_every_bonus_changes_the_resolved_cast() -> void:
	for key: String in RARITY:
		var base := _probe(key, "normal")
		var rows: Array = RARITY[key]
		for t in 4:
			var tier: String = ["rare", "epic", "unique", "legendary"][t]
			var got := _probe(key, tier)
			var row: Array = rows[mini(t, 2)]
			var label := "%s %s %s" % [key, tier, row[0]]
			match String(row[1]):
				"damage":
					assert_true(float(got.damage) > float(base.damage), label)
				"cooldown":
					assert_near(float(got.cooldown) / float(base.cooldown), 0.88, 0.0001, label)
					assert_true(int(got.casts) > int(base.casts), label + ": casts more often")
				"crit":
					assert_near(float(got.crit) - float(base.crit), 0.15, 0.0001, label)
				"count":
					assert_eq(int(got.count), int(base.count) + 1, label)
					assert_true(int(got.lines) > int(base.lines), label + ": one more star lands")
				"pierce":
					assert_eq(int(got.pierce), int(base.pierce) + 2, label)
					assert_true(int(got.mobs) > int(base.mobs), label + ": the line reaches two more monsters")
				"status":
					assert_eq(int(got.grants), 1, label)
					assert_eq(int(base.grants), 0, label)
			if t == 3:
				assert_true(float(got.damage) > float(_probe(key, "unique").damage), label + ": Legendary adds damage x1.2")


func test_critical_throw_raises_the_crit_rate_in_seeded_combat() -> void:
	var crits: Array[int] = []
	for tier in ["normal", "rare"]:
		var w := _world(TRIPLE, 8)
		w.upgrades.apply(TRIPLE + "_rank", w, tier)
		w.loadout.set_rank(TRIPLE, 8)
		_mob(w, 80)
		var n := 0
		for tick in 60 * 120:
			w.step(DT, MoveInput.new())
			for e: Dictionary in _hits(w.drain_events(), TRIPLE):
				if bool(e.crit):
					n += 1
		crits.append(n)
	assert_true(crits[1] > crits[0], "more critical stars with Critical Throw: %s" % [crits])


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for key: String in RARITY:
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			var w := _world(key)
			var card := w.upgrades.choice_card(key + "_rank", w, tier)
			assert_false(card.get("rarity_bonus", {}).is_empty(), "%s %s carries a bonus" % [key, tier])
			var mods := var_to_bytes(w.loadout.stats(key))
			w.upgrades.apply(key + "_rank", w, tier)
			assert_eq(w.loadout.rank(key), 2, "%s %s: one rank, whatever the rarity" % [key, tier])
			assert_true(var_to_bytes(w.loadout.stats(key)) != mods)
			var st := w.loadout.stats(key)
			match tier:
				"rare":
					if key == TRIPLE:
						assert_near(w.loadout.skill_stat(key, "crit", 0.0), 0.15, 0.0001)
					else:
						assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2, 0.0001)
				"epic":
					if key in [LUCKY, AVENGER]:
						assert_eq(st.status_grants.size(), 1)
					else:
						assert_near(w.loadout.skill_stat(key, "cooldown", 1.0), 0.88, 0.0001)
				"unique", "legendary":
					if key == AVENGER:
						assert_near(w.loadout.skill_stat(key, "pierce", 0.0), 2.0, 0.0001)
					else:
						assert_eq(st.count, (3 if key == TRIPLE else 1 if key == DRAIN else 2) + 1)
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2 if tier == "legendary" else 1.0, 0.0001)


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	for key: String in RARITY:
		var w := _world(key)
		var unique_id: String = RARITY[key][2][0]
		w.upgrades.apply(key + "_rank", w, "unique")
		w.upgrades.apply(key + "_rank", w, "legendary")
		assert_eq(int(w.loadout.card_ranks["bonus:%s:%s" % [key, unique_id]]), 2, "%s: one shared counter" % key)
		var m := _world(key)
		m.loadout.set_rank(key, 8)
		var c := m.upgrades.choice_card(key + "_rank", m, "rare")
		assert_eq(c.card_kind, "mastery", "%s: at rank 8 the rank card is a Mastery card" % key)
		m.upgrades.apply(key + "_rank", m, "rare")
		m.upgrades.apply(key + "_rank", m, "rare")
		if key == TRIPLE:
			assert_near(m.loadout.skill_stat(key, "crit", 0.0), 0.15 + 0.15 * 0.8, 0.0001, "Critical Throw repeats x0.8")
		else:
			assert_near(m.loadout.skill_stat(key, "damage", 1.0), 1.2 * (1.0 + 0.2 * 0.8), 0.00001, "%s: the repeat is x0.8" % key)
		assert_eq(m.loadout.rank(key), 8)


func test_a_mastery_grant_repeat_raises_the_chance_by_the_catalogue_points() -> void:
	var w := _world(LUCKY, 8)
	w.upgrades.apply(LUCKY + "_rank", w, "epic")
	w.loadout.set_rank(LUCKY, 8)
	assert_near(float(w.loadout.stats(LUCKY).status_grants[0].chance), 30.0, 0.0001)
	w.upgrades.apply(LUCKY + "_rank", w, "epic") # a Mastery card at rank 8: the grant repeats
	assert_near(float(w.loadout.stats(LUCKY).status_grants[0].chance), 30.0 + 3.0 * 0.8, 0.0001, "repeat_chance 3 x 0.8")
	var a := _world(AVENGER, 8)
	a.upgrades.apply(AVENGER + "_rank", a, "epic")
	a.upgrades.apply(AVENGER + "_rank", a, "epic")
	assert_near(float(a.loadout.stats(AVENGER).status_grants[0].chance), 50.0 + 4.0 * 0.8, 0.0001, "repeat_chance 4 x 0.8")


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var roots := {}
	for book_id: String in ["400", "410", "411", "412"]:
		var img := lib.img("Skill.wz/%s.img" % book_id)
		assert_true(img != null, "Skill.wz/%s.img is in the cache" % book_id)
		if img == null:
			lib.free()
			return
		roots[book_id] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, roots)
	var lo := Loadout.new(book)
	lo.weapon_family = "claw"
	var node_of := {LUCKY: roots["400"].skill["4001344"], DRAIN: roots["410"].skill["4101005"],
		AVENGER: roots["411"].skill["4111005"], TRIPLE: roots["412"].skill["4121007"]}
	for key: String in node_of:
		var top := 20 if key == LUCKY else 30
		assert_eq(book.max_level(key), top, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank_value in range(1, 9):
			var lv: int = (LEVELS_20 if key == LUCKY else LEVELS_30)[rank_value - 1]
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			assert_eq(book.canonical_level(key, rank_value), lv, label)
			var level: Dictionary = node_of[key].level[str(lv)]
			var st := lo.stats(key, rank_value)
			assert_eq(int(st.level), lv, label)
			assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
			match key:
				LUCKY:
					assert_eq(st.count, int(level.bulletCount), label)
					assert_eq(st.count, 2, label)
				TRIPLE:
					assert_eq(st.count, int(level.bulletCount), label)
					assert_eq(st.count, 3, label)
				AVENGER:
					assert_eq(st.mob_count, int(level.mobCount), label)
					assert_eq(st.pierce, int(level.mobCount) - 1, label)
				DRAIN:
					assert_eq(book.canonical(key, lv, "x"), float(level.x), label)
	# The spec's worked rank values (rank 1 / 4 / 8) as literals.
	for i in 3:
		var r: int = [1, 4, 8][i]
		assert_near(lo.stats(LUCKY, r).damage_pct, [0.66, 1.00, 1.50][i], 0.000001, "Lucky Seven rank %d" % r)
		assert_near(lo.stats(DRAIN, r).damage_pct, [1.08, 1.30, 1.60][i], 0.000001, "Drain rank %d" % r)
		assert_eq(book.canonical(DRAIN, book.canonical_level(DRAIN, r), "x"), [19.0, 30.0, 45.0][i], "Drain absorb rank %d" % r)
		assert_near(lo.stats(AVENGER, r).damage_pct, [0.80, 1.30, 1.80][i], 0.000001, "Avenger rank %d" % r)
		assert_eq(lo.stats(AVENGER, r).mob_count, [4, 5, 6][i], "Avenger monsters rank %d" % r)
		assert_near(lo.stats(TRIPLE, r).damage_pct, [1.08, 1.30, 1.50][i], 0.000001, "Triple Throw rank %d" % r)
	# Art, sounds and the claw's stances resolve in the cache.
	for key: String in node_of:
		var d := book.def(key)
		var paths: Array = [d.effect, d.ball, d.hit, String(d.get("char_level", {}).get("hit", "")).replace("{cl}", "10")]
		for path: String in paths:
			if path != "":
				assert_true(lib.anim(path).frames.size() > 0, path)
		for path: String in d.sounds.values():
			if path != "":
				assert_true(lib.sound(path) != null, path)
		assert_true(lib.node("Character.wz/00002000.img/" + String(d.action)) is Dictionary, "body action " + String(d.action))
		if String(d.action) == "swingO1":
			assert_true(lib.node("Character.wz/Weapon/01472000.img/swingO1") is Dictionary, "the Garnier has its own swing")
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
