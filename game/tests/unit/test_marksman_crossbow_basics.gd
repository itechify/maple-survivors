extends TestCase
## Marksman's crossbow basics (spec #360, ticket MS5 #365): Iron Arrow (ported from `skills/bowman.json`), Arrow Blow's crossbow
## names (`text_by_family`), and the crossbow copies of Strafe and Dragon's Breath, with their rarity bonuses.
## Fixed 1/60 s ticks, seeded RNG; the Skill.wz levels are the synthetic fixture tables (endpoints recorded from v83) unless a
## test says "real cache" (those call require_cache() and SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CROSSBOW := 1462001
const BOW := 1452051
const IRON := "iron_arrow"
const BLOW := "arrow_blow"
const STRAFE := "strafe_crossbow"
const BREATH := "dragons_breath_crossbow"
const KEYS := [IRON, BLOW, STRAFE, BREATH]
const OWN_KEYS := [IRON, STRAFE, BREATH]
const TIERS := ["rare", "epic", "unique", "legendary"]


## A quiet round of a Marksman holding the crossbow, `key` the only learned skill at `rank_value`, mobs frozen and tall enough
## that the hand-height arrow line crosses them.
func _world(key: String, rank_value := 1, p_seed := 365) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["322"]["playable"] = true # in this test's data only: its pool cards exist (MS11 ships the flip)
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7},
		CROSSBOW: {"incPAD": 29, "attackSpeed": 6, "tuc": 7, "reqJob": 4}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup["job"] = 322
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != CROSSBOW:
		assert_eq(w.wear_new_item(CROSSBOW), "")
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -60, 40, 60)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Iron Arrow): only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Marksman" % key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190, 100000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(w: RunWorld, key: String) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


func _run(w: RunWorld, ticks: int) -> RunWorld:
	for tick in ticks:
		w.step(DT, MoveInput.new())
	return w


func _ints(values: Array) -> Array:
	return values.map(func(v: Variant) -> int: return int(v))


func _mod(w: RunWorld, key: String, stat: String, op: String, value: float) -> void:
	w.loadout.add_skill_mod(key, stat, op, value)
	w.refresh_player_stats()


# --- the ported definitions -------------------------------------------------------------------------------------------

func test_the_four_skills_name_no_weapon_and_use_the_default_eight_ranks_on_their_own_books() -> void:
	var w := _world(IRON)
	for key: String in KEYS:
		var d := w.book.def(key)
		assert_false(d.has("weapon_families"), "%s: a weapon gates nothing" % key)
		assert_false(d.has("ranks"), "%s: the default rank table" % key)
		assert_eq(String(d.slot), "active")
		assert_eq(w.book.max_rank(key), 8, key)
	assert_eq(_ints(w.book.rank_table(IRON)), [4, 8, 12, 15, 19, 23, 27, 30])
	assert_eq(_ints(w.book.rank_table(BLOW)), [3, 5, 8, 10, 13, 15, 18, 20])
	assert_eq(_ints(w.book.rank_table(STRAFE)), [4, 8, 12, 15, 19, 23, 27, 30])
	assert_eq(_ints(w.book.rank_table(BREATH)), [4, 8, 12, 15, 19, 23, 27, 30])
	assert_eq(_ints(KEYS.map(func(k: String) -> Variant: return w.book.def(k).job)), [320, 300, 321, 322])
	assert_eq(_ints(KEYS.map(func(k: String) -> Variant: return w.book.skill_id(k))), [3201005, 3001004, 3211006, 3221003])
	assert_eq(String(w.book.def(STRAFE).book), "321")
	assert_eq(String(w.book.def(BREATH).book), "322")


func test_iron_arrow_moved_to_the_marksman_line_and_its_legacy_cards_are_gone() -> void:
	var bowman: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "bowman"))
	var marksman: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "marksman"))
	assert_false(bowman.skills.has(IRON), "no longer defined in skills/bowman.json")
	for key: String in OWN_KEYS:
		assert_true(marksman.skills.has(key), "%s is in skills/marksman.json" % key)
	assert_false(marksman.skills.has(BLOW), "Arrow Blow stays Bowmaster's one shared definition")
	assert_true(DataRepo.load_json(DataRepo.fragment_path("skills", "bowmaster")).skills.has(BLOW))
	var w := _world(IRON)
	for id in ["iron_arrow_pierce", "iron_arrow_shots"]:
		assert_true(w.upgrades.card(id).is_empty(), "%s was removed" % id)
	for id in ["iron_arrow_new", "iron_arrow_rank"]:
		assert_false(w.upgrades.card(id).has("requires"), "%s is now a generated pool card, not the old Crossbowman-gated one" % id)
	# A playable Marksman's new / rank cards come from the pool (UpgradePool.add_pool_skills).
	for key: String in KEYS:
		assert_false(w.upgrades.card(key + "_new").is_empty(), "%s_new exists for a Marksman" % key)
		assert_false(w.upgrades.card(key + "_rank").is_empty(), "%s_rank exists for a Marksman" % key)


# --- Iron Arrow -------------------------------------------------------------------------------------------------------

func test_iron_arrow_pierces_five_after_the_first_with_the_falloff_and_its_own_ball() -> void:
	var w := _world(IRON, 8)
	var st := w.loadout.stats(IRON)
	assert_eq([st.pierce, st.count, st.range, st.speed, st.radius], [5, 1, 300.0, 600.0, 8.0])
	assert_near(st.pierce_falloff, 0.1, 0.000001)
	assert_near(st.damage_pct, 1.8, 0.000001, "rank 8 is WZ level 30: 180%")
	var slots: Array[int] = []
	for i in 7:
		slots.append(_mob(w, 70.0 + 30.0 * i))
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.projectiles.active_count(), 1, "one arrow")
	for p in w.projectiles.capacity():
		if w.projectiles.active[p] != 0:
			assert_eq(w.projectiles.visual[p], w.visual_index("Skill.wz/320.img/skill/3201005/ball"), "its own ball, not the ammo's")
	assert_near(float(w.runner.cooldowns[IRON]), 1.0 - DT, 0.001, "1 s cooldown")
	var hits := _hits(_run(w, 40), IRON)
	var struck := hits.map(func(e: Dictionary) -> int: return int(e.mob))
	assert_eq(struck, slots.slice(0, 6), "mobCount 6: the arrow strikes six, in order, and not the seventh")
	assert_eq(w.swarm.hp[slots[6]], w.swarm.max_hp[slots[6]])


func test_iron_arrow_ranks_follow_the_wz_levels() -> void:
	var w := _world(IRON)
	var lo := w.loadout
	assert_near(lo.stats(IRON, 1).damage_pct, 1.28, 0.000001, "WZ level 4")
	assert_near(lo.stats(IRON, 4).damage_pct, 1.50, 0.000001, "WZ level 15")
	assert_near(lo.stats(IRON, 8).damage_pct, 1.80, 0.000001, "WZ level 30")
	for rank_value in [1, 4, 8]:
		assert_eq(lo.stats(IRON, rank_value).pierce, 5)


func test_iron_arrow_waits_for_a_monster_in_reach() -> void:
	var w := _world(IRON)
	_mob(w, 340) # past the 300 px reach
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0)
	_mob(w, 250)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)


func test_iron_arrow_casts_the_held_weapon_stance_and_ignores_the_weapon_family() -> void:
	var w := _world(IRON)
	_mob(w, 100)
	w.runner.step(DT, w)
	var casts := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast")
	assert_eq(casts.size(), 1)
	assert_eq(String(w.book.def(IRON).action), "weapon", "the data names the held weapon's stance")
	assert_eq(String(casts[0].action), "shoot2", "which resolves to the crossbow's shooting stance")
	# A weapon gates nothing since #284: with the bow in hand the skill still casts.
	var bow := _world(IRON)
	assert_eq(bow.wear_new_item(BOW), "")
	_mob(bow, 100)
	bow.runner.step(DT, bow)
	assert_eq(bow.runner.casts, 1)


# --- Arrow Blow (shared) ----------------------------------------------------------------------------------------------

func test_arrow_blow_fires_the_current_crossbow_arrow_and_steps_with_the_round_level() -> void:
	var w := _world(BLOW)
	_mob(w, 90)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 1)
	assert_eq(w.ammo_id(), 2061000, "Arrow for Crossbow at Lv1")
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.visual[i], w.visual_index(Ammo.bullet_path(2061000)))
	var late := _world(BLOW)
	late.progression.level = 30
	late.refresh_player_stats()
	assert_eq(late.ammo_id(), 2061002, "Steel Arrow for Crossbow from Lv30")
	_mob(late, 90)
	late.runner.step(DT, late)
	for i in late.projectiles.capacity():
		if late.projectiles.active[i] != 0:
			assert_eq(late.projectiles.visual[i], late.visual_index(Ammo.bullet_path(2061002)))
	assert_eq(_hits(_run(w, 40), BLOW).size(), 1)


func _bonus_texts(w: RunWorld, key: String) -> Dictionary:
	var out := {}
	for tier: String in TIERS:
		out[tier] = w.upgrades.rarity_bonus(w.upgrades.card(key + "_rank"), w, tier)
	return out


func test_arrow_blow_shows_the_crossbow_names_for_a_crossbow_and_the_bow_names_for_a_bow() -> void:
	var cross := _world(BLOW)
	var texts := _bonus_texts(cross, BLOW)
	assert_true(String(texts.rare.text).begins_with("Crossbow Mastery: "), String(texts.rare.text))
	assert_true(String(texts.epic.text).begins_with("Crossbow Booster: "), String(texts.epic.text))
	assert_true(String(texts.unique.text).begins_with("Final Attack: "), String(texts.unique.text))
	assert_true(String(texts.legendary.text).begins_with("Final Attack: "), String(texts.legendary.text))
	var bow := _world(BLOW)
	assert_eq(bow.wear_new_item(BOW), "")
	assert_eq(bow.loadout.weapon_family, "bow")
	var bow_texts := _bonus_texts(bow, BLOW)
	assert_true(String(bow_texts.rare.text).begins_with("Bow Mastery: "), String(bow_texts.rare.text))
	assert_true(String(bow_texts.epic.text).begins_with("Bow Booster: "), String(bow_texts.epic.text))
	# The text is the only difference: ids, counters and every effect number are the same.
	for tier: String in TIERS:
		assert_eq(cross.upgrades.rarity_bonus(cross.upgrades.card(BLOW + "_rank"), cross, tier).effects,
			bow.upgrades.rarity_bonus(bow.upgrades.card(BLOW + "_rank"), bow, tier).effects, "%s: same numbers" % tier)
		assert_eq(texts[tier].id, bow_texts[tier].id)
		assert_eq(texts[tier].counter, bow_texts[tier].counter)


func test_the_card_description_carries_the_crossbow_name() -> void:
	var w := _world(BLOW)
	var card := w.upgrades.choice_card(BLOW + "_rank", w, "rare")
	assert_true(String(card.desc).contains("Crossbow Mastery"), String(card.desc))
	assert_false(String(card.desc).contains("Bow Mastery: damage"), String(card.desc))


func test_text_by_family_is_only_on_arrow_blows_two_bow_named_bonuses() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in skills:
		var bonuses: Dictionary = skills[key].get("rarity_bonuses", {})
		for tier: String in bonuses:
			for entry: Dictionary in bonuses[tier]:
				var has := entry.has("text_by_family")
				var wanted: bool = key == BLOW and tier in ["rare", "epic"]
				assert_eq(has, wanted, "%s %s: text_by_family only on Arrow Blow's rare and epic" % [key, tier])
	var rare: Dictionary = skills[BLOW].rarity_bonuses.rare[0]
	assert_eq(rare.text_by_family, {"crossbow": "Crossbow Mastery"})
	assert_eq(skills[BLOW].rarity_bonuses.epic[0].text_by_family, {"crossbow": "Crossbow Booster"})
	assert_eq(String(rare.text), "Bow Mastery", "the Bowmaster's own text is unchanged")


# --- Strafe (crossbow copy) -------------------------------------------------------------------------------------------

func test_strafe_sends_all_four_arrows_at_the_nearest_monster_and_prefers_a_boss() -> void:
	var w := _world(STRAFE)
	var near := _mob(w, 80)
	_mob(w, 140)
	_mob(w, -120)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 4, "bulletCount 4")
	var hits := _hits(_run(w, 45), STRAFE)
	assert_eq(hits.size(), 4)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == near), "every arrow reaches the nearest monster")
	var boss_world := _world(STRAFE)
	_mob(boss_world, 80)
	var boss := _mob(boss_world, -200, true)
	boss_world.mob_boss[boss] = 0
	boss_world.runner.step(DT, boss_world)
	var boss_hits := _hits(_run(boss_world, 50), STRAFE)
	assert_eq(boss_hits.size(), 4)
	assert_true(boss_hits.all(func(e: Dictionary) -> bool: return int(e.mob) == boss), "all four arrows go to the boss")


func test_strafe_is_a_crossbow_copy_with_its_own_art_ammo_range_and_cooldown() -> void:
	var w := _world(STRAFE, 8)
	_mob(w, 300)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[STRAFE]), 2.5 - DT, 0.001, "2.5 s cooldown")
	var st := w.loadout.stats(STRAFE)
	assert_eq([st.count, st.range, st.speed, st.radius, st.pierce], [4, 350.0, 700.0, 6.0, 0])
	assert_eq(String(st.hit), "Skill.wz/321.img/skill/3211006/hit/0", "the 321 book's hit art, not the 311 one")
	assert_eq(String(w.book.def(STRAFE).sounds.use), "Sound.wz/Skill.img/3211006/Use")
	var ammo := w.visual_index(Ammo.bullet_path(w.ammo_id()))
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.visual[i], ammo, "the current crossbow arrow")
	assert_near(st.damage_pct, 1.0, 0.000001, "rank 8: 100% per arrow")
	assert_near(w.loadout.stats(STRAFE, 1).damage_pct, 0.74, 0.000001)
	assert_near(w.loadout.stats(STRAFE, 4).damage_pct, 0.85, 0.000001)
	var far := _world(STRAFE)
	_mob(far, 400)
	far.runner.step(DT, far)
	assert_eq(far.runner.casts, 0, "past the 350 px range")


func test_the_bowmasters_strafe_is_untouched() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	assert_eq(int(skills.strafe.job), 311)
	assert_eq(int(skills.strafe.skill_id), 3111006)
	assert_eq(String(skills.strafe.hit), "Skill.wz/311.img/skill/3111006/hit/0")
	assert_eq(int(skills.dragons_breath.job), 312)
	assert_eq(int(skills.dragons_breath.skill_id), 3121003)
	assert_eq(String(skills.dragons_breath.ball), "Skill.wz/312.img/skill/3121003/ball")


# --- Dragon's Breath (crossbow copy) ----------------------------------------------------------------------------------

func _line(w: RunWorld, n: int) -> Array[int]:
	var slots: Array[int] = []
	for k in n:
		slots.append(_mob(w, 40.0 + 45.0 * k))
	return slots


func _distinct(w: RunWorld, ticks: int) -> Dictionary:
	var struck := {}
	for e: Dictionary in _hits(_run(w, ticks), BREATH):
		struck[int(e.mob)] = int(struck.get(int(e.mob), 0)) + 1
	return struck


func _without_knockback(w: RunWorld) -> RunWorld:
	w.book.defs[BREATH].erase("knockback")
	w.loadout.version += 1
	return w


func test_dragons_breath_pierces_three_four_and_five_extra_monsters_by_rank() -> void:
	for row: Array in [[1, 3], [4, 4], [8, 5]]:
		var w := _without_knockback(_world(BREATH, int(row[0])))
		_line(w, 8)
		assert_eq(w.loadout.stats(BREATH).pierce, int(row[1]), "rank %d: mobCount - 1" % int(row[0]))
		var struck := _distinct(w, 90)
		assert_eq(struck.size(), int(row[1]) + 1, "rank %d strikes 1 + %d monsters" % [int(row[0]), int(row[1])])
		for count: int in struck.values():
			assert_eq(count, 1, "a shot hits each monster once")


func test_dragons_breath_knocks_every_struck_monster_back_180_px_both_ways() -> void:
	for side in [-1, 1]:
		var pushed := _world(BREATH, 8)
		var plain := _without_knockback(_world(BREATH, 8))
		var slots := {}
		for w: RunWorld in [pushed, plain]:
			slots[w] = [_mob(w, 80.0 * side), _mob(w, 140.0 * side)]
			_distinct(w, 60)
		for k in 2:
			var delta: float = pushed.swarm.x[slots[pushed][k]] - plain.swarm.x[slots[plain][k]]
			assert_near(delta, 180.0 * side, 1.5, "side %d, monster %d: 180 px away from the caster" % [side, k])


func test_dragons_breath_damages_a_boss_but_never_moves_it() -> void:
	var pushed := _world(BREATH, 8)
	var plain := _without_knockback(_world(BREATH, 8))
	var boss := {}
	var other := {}
	for w: RunWorld in [pushed, plain]:
		other[w] = _mob(w, 60)
		boss[w] = _mob(w, 120, true)
		assert_true(_distinct(w, 90).has(boss[w]), "the boss is struck")
		assert_true(w.swarm.hp[boss[w]] < w.swarm.max_hp[boss[w]], "and damaged")
	assert_eq(pushed.swarm.x[boss[pushed]], plain.swarm.x[boss[plain]], "the boss is not pushed")
	assert_near(pushed.swarm.x[other[pushed]] - plain.swarm.x[other[plain]], 180.0, 1.5, "while the monster beside it is")


func test_dragons_breath_reach_cooldown_ball_and_art_are_the_crossbow_copys_own() -> void:
	var w := _world(BREATH)
	_mob(w, 450)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0, "450 px is out of reach")
	_mob(w, 430)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	var st := w.loadout.stats(BREATH)
	assert_eq([st.range, st.speed, st.radius], [440.0, 700.0, 16.0])
	assert_near(float(w.runner.cooldowns[BREATH]), 3.5 - DT, 0.001)
	assert_eq(st.knockback_chance, 100.0)
	assert_eq(st.knockback_distance, 180.0)
	var d := w.book.def(BREATH)
	assert_eq(String(d.ball), "Skill.wz/322.img/skill/3221003/ball")
	assert_eq(String(d.hit), "Skill.wz/322.img/skill/3221003/hit/0")
	assert_eq(String(d.effect), "Skill.wz/322.img/skill/3221003/effect")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/3221003/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/3221003/Hit")
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.visual[i], w.visual_index(String(d.ball)), "its own ball, no ammo sprite")
	for row: Array in [[1, 0.48, 4], [4, 0.70, 5], [8, 1.0, 6]]:
		var ranked := w.loadout.stats(BREATH, int(row[0]))
		assert_near(ranked.damage_pct, float(row[1]), 0.000001, "rank %d" % int(row[0]))
		assert_eq(ranked.mob_count, int(row[2]))


# --- the Skill window -------------------------------------------------------------------------------------------------

func test_every_pool_skill_of_this_ticket_is_on_a_tab_of_a_marksman() -> void:
	var w := _world(IRON)
	for key: String in KEYS:
		if not w.loadout.has(key):
			assert_true(w.learn_skill(key))
	var model := SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 322, SkillText.new(w.book, {}))
	var tab_of := {}
	for tab: Dictionary in model.tabs:
		for row: Dictionary in tab.rows:
			tab_of[String(row.key)] = int(tab.job_id)
	assert_eq(_ints(model.tabs.slice(1).map(func(t: Dictionary) -> Variant: return t.job_id)), [300, 320, 321, 322],
		"Common, then Bowman, Crossbowman, Sniper, Marksman")
	for key: String in KEYS:
		assert_true(tab_of.has(key), "%s is listed on some tab" % key)
		assert_eq(tab_of.get(key, -1), int(w.book.def(key).job), "%s sits on the tab of its own job" % key)
	assert_eq(tab_of[IRON], 320)
	assert_eq(tab_of[BLOW], 300)
	assert_eq(tab_of[STRAFE], 321)
	assert_eq(tab_of[BREATH], 322)


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

## skill -> [rare, epic, unique] as [id, text, [stat, op, value]]; Legendary is the Unique's id and effect plus damage x1.2.
const BONUSES := {
	"iron_arrow": [["crossbow_mastery", "Crossbow Mastery", ["damage", "mul", 1.2]], ["booster", "Crossbow Booster", ["cooldown", "mul", 0.88]],
		["final_attack", "Final Attack", ["count", "add", 1.0]]],
	"strafe_crossbow": [["crossbow_mastery", "Crossbow Mastery", ["damage", "mul", 1.2]], ["booster", "Crossbow Booster", ["cooldown", "mul", 0.88]],
		["final_attack", "Final Attack", ["count", "add", 2.0]]],
	"dragons_breath_crossbow": [["marksman_boost", "Marksman Boost", ["damage", "mul", 1.2]], ["eye", "Eye of Amazon", ["range", "mul", 1.25]],
		["dragons_spirit", "Dragon's Spirit", ["pierce", "add", 2.0]]],
}


func test_the_catalog_lists_all_four_rarities_exactly_as_the_spec_table() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in BONUSES:
		var bonuses: Dictionary = skills[key].rarity_bonuses
		var expected: Array = BONUSES[key]
		for t in 3:
			var tier: String = ["rare", "epic", "unique"][t]
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
		assert_eq([String(legendary.effects[1].stat), String(legendary.effects[1].op), float(legendary.effects[1].value)], ["damage", "mul", 1.2])
	# Arrow Blow keeps Bowmaster's ids and numbers (only its text is renamed by weapon family).
	var blow: Dictionary = skills[BLOW].rarity_bonuses
	assert_eq([blow.rare[0].id, blow.epic[0].id, blow.unique[0].id, blow.legendary[0].id],
		["bow_mastery", "booster", "final_attack", "final_attack"])


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus_and_the_preview_is_stable() -> void:
	for key: String in KEYS:
		for tier: String in TIERS:
			var a := _world(key)
			var b := _world(key)
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


func test_legendary_shares_the_uniques_counter_and_repeats_shrink_by_a_fifth() -> void:
	for key: String in KEYS:
		var w := _world(key)
		var unique := w.upgrades.rarity_bonus(w.upgrades.card(key + "_rank"), w, "unique")
		w.upgrades.apply(key + "_rank", w, "unique")
		var legendary := w.upgrades.rarity_bonus(w.upgrades.card(key + "_rank"), w, "legendary")
		assert_eq(legendary.counter, unique.counter, "%s: one repeat counter" % key)
		var first := float(unique.effects[0].value)
		var second := float(legendary.effects[0].value)
		var op := String(unique.effects[0].op)
		if op == "mul":
			assert_near(second, 1.0 + (first - 1.0) * 0.8, 0.000001, "%s: x0.8 on the repeat" % key)
		else:
			assert_near(second, first * 0.8, 0.000001, "%s: x0.8 on the repeat" % key)
	var rare := _world(IRON)
	var one := float(rare.upgrades.rarity_bonus(rare.upgrades.card(IRON + "_rank"), rare, "rare").effects[0].value)
	rare.upgrades.apply(IRON + "_rank", rare, "rare")
	var two := float(rare.upgrades.rarity_bonus(rare.upgrades.card(IRON + "_rank"), rare, "rare").effects[0].value)
	assert_near(one, 1.2, 0.000001)
	assert_near(two, 1.16, 0.000001, "Rare + Rare: x0.8 on the second")


func test_mastery_repeats_shrink_by_a_fifth_after_rank_eight() -> void:
	for key: String in KEYS:
		var w := _world(key, 8)
		var first := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_eq(String(first.card_kind), UpgradePool.MASTERY, "%s: rank 8 offers Mastery" % key)
		assert_false(first.rarity_bonus.is_empty(), key)
		var one := float(first.rarity_bonus.effects[0].value)
		w.upgrades.apply(key + "_rank", w, "normal")
		assert_eq(w.loadout.rank(key), 8, "Mastery gains no rank")
		var two := float(w.upgrades.choice_card(key + "_rank", w, "normal").rarity_bonus.effects[0].value)
		assert_near(two - 1.0, (one - 1.0) * 0.8, 0.000001, "%s: Mastery x0.8 on the repeat" % key)


# --- every bonus changes the resolved cast ----------------------------------------------------------------------------

## What casting `key` with `effects` applied does against a layout that exposes `stat`: casts over 66 s, damage over 12 s, hit
## lines and monsters struck by one cast, and whether the monster just past the base reach was struck.
func _probe(key: String, effects: Array, stat: String) -> Dictionary:
	var w := _world(key, 8)
	if key == BREATH:
		w.loadout.set_rank(key, 1) # mobCount 4: the pierce bonus has monsters left to add
		w.refresh_player_stats()
	var reach := float(w.loadout.stats(key).range)
	var xs: Array = []
	var edge: Array = []
	match stat:
		"pierce":
			for k in 10:
				xs.append(40.0 + 45.0 * k)
		"range":
			# The only monster is just past the base reach: the base never casts, the widened reach shoots it.
			edge = [reach * 1.1]
			xs.append_array(edge)
		_:
			xs.append_array([reach * 0.4, reach * 0.55])
	var slots := []
	var edge_slots := []
	for off: float in xs:
		var slot := _mob(w, off)
		slots.append(slot)
		if off in edge:
			edge_slots.append(slot)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(key, String(e.stat), String(e.op), float(e.value))
	var repeating := stat in ["cooldown", "damage"]
	var window := 66.0 if stat == "cooldown" else 12.0 if stat == "damage" else 1.5 if stat == "range" else 3.5
	var affected := {}
	var lines := 0
	var x0 := {}
	for s: int in slots:
		x0[s] = w.swarm.x[s]
	for tick in int(window / DT):
		w.step(DT, MoveInput.new())
		if not repeating and w.runner.casts >= 1:
			w.runner.cooldowns[key] = 1.0e9
		for e: Dictionary in w.drain_events():
			if e.type == "mob_hit":
				lines += 1
				affected[int(e.mob)] = true
		for s: int in slots:
			if repeating:
				w.swarm.x[s] = x0[s] # a knock-back must not walk the monsters out of reach between casts
			if w.swarm.hp[s] < w.swarm.max_hp[s] and repeating:
				w.swarm.hp[s] = w.swarm.max_hp[s]
	var edge_hit := false
	for s: int in edge_slots:
		edge_hit = edge_hit or affected.has(s)
	return {"casts": w.runner.casts, "dealt": w.damage_dealt, "lines": lines, "affected": affected.size(), "edge": edge_hit}


func test_each_bonus_effect_changes_the_resolved_cast() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var checked := 0
	for key: String in KEYS:
		for tier: String in TIERS:
			for bonus: Dictionary in skills[key].rarity_bonuses[tier]:
				for effect: Dictionary in bonus.effects:
					_assert_effect_changes_the_cast(key, tier, String(bonus.id), effect)
					checked += 1
	assert_eq(checked, KEYS.size() * 5, "each skill: 1 + 1 + 1 + 2 effects")


func _assert_effect_changes_the_cast(key: String, tier: String, id: String, effect: Dictionary) -> void:
	var stat := String(effect.stat)
	var label := "%s %s %s (%s)" % [key, tier, id, stat]
	assert_true(stat in ["damage", "cooldown", "count", "pierce", "range"], "%s: a stat this probe knows" % label)
	var base := _probe(key, [], stat)
	var with := _probe(key, [effect], stat)
	match stat:
		"cooldown":
			assert_true(int(with.casts) > int(base.casts), "%s: casts %d -> %d" % [label, base.casts, with.casts])
		"damage":
			assert_true(int(with.dealt) > int(base.dealt), "%s: damage dealt %d -> %d" % [label, base.dealt, with.dealt])
		"count":
			assert_true(int(with.lines) > int(base.lines), "%s: hit lines %d -> %d" % [label, base.lines, with.lines])
		"pierce":
			assert_true(int(with.affected) > int(base.affected), "%s: monsters struck %d -> %d" % [label, base.affected, with.affected])
		"range":
			assert_false(bool(base.edge), "%s: the monster beyond the base reach is outside it" % label)
			assert_true(bool(with.edge), "%s: the monster beyond the base reach is inside the widened one" % label)


func test_the_probe_catches_a_modifier_the_cast_never_reads() -> void:
	# Dragon's Breath never reads `attack_count`: the probe must report no change, or the audit above would pass anything.
	var base := _probe(BREATH, [], "count")
	var with := _probe(BREATH, [{"stat": "attack_count", "op": "add", "value": 3.0}], "count")
	assert_eq(int(with.lines), int(base.lines))
	assert_eq(int(with.casts), int(base.casts))


# --- real cache: all eight ranks against Skill.wz ---------------------------------------------------------------------

## skill -> [book, WZ id, WZ max level, the eight mapped levels (ceil(rank x max / 8))]
const MAPPED := {
	"iron_arrow": ["320", 3201005, 30, [4, 8, 12, 15, 19, 23, 27, 30]],
	"arrow_blow": ["300", 3001004, 20, [3, 5, 8, 10, 13, 15, 18, 20]],
	"strafe_crossbow": ["321", 3211006, 30, [4, 8, 12, 15, 19, 23, 27, 30]],
	"dragons_breath_crossbow": ["322", 3221003, 30, [4, 8, 12, 15, 19, 23, 27, 30]],
}


func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var imgs := {}
	for book: String in ["300", "320", "321", "322", "311", "312"]:
		var img := lib.img("Skill.wz/%s.img" % book)
		assert_true(img != null, "Skill.wz/%s.img is in the cache" % book)
		if img == null:
			lib.free()
			return
		imgs[book] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var lo := Loadout.new(book)
	lo.weapon_family = "crossbow"
	for key: String in MAPPED:
		var row: Array = MAPPED[key]
		var node: Dictionary = imgs[row[0]].skill["%07d" % int(row[1])]
		assert_eq(book.max_level(key), row[2], "%s: WZ max level" % key)
		assert_eq(book.max_rank(key), 8, key)
		for rank_value in range(1, 9):
			var lv := int(row[3][rank_value - 1])
			assert_eq(book.canonical_level(key, rank_value), lv, "%s rank %d" % [key, rank_value])
			var level: Dictionary = node.level[str(lv)]
			var st := lo.stats(key, rank_value)
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			assert_eq(int(st.level), lv, label)
			assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
			match key:
				"iron_arrow":
					assert_eq(st.pierce, int(level.mobCount) - 1, label)
					assert_eq(st.pierce, 5, label)
				"arrow_blow":
					assert_eq(st.count, 1, label)
				"strafe_crossbow":
					assert_eq(st.count, int(level.bulletCount), label)
					assert_eq(st.count, 4, label)
				"dragons_breath_crossbow":
					assert_eq(st.mob_count, int(level.mobCount), label)
					assert_eq(st.pierce, int(level.mobCount) - 1, label)
					assert_eq(st.range, float(level.range), label)
					assert_eq(st.range, 440.0, label)
					assert_eq(st.knockback_chance, float(level.prop), label)
	# The spec's worked rank values (rank 1 / 4 / 8), as literals.
	for expectation: Array in [["iron_arrow", 1.28, 1.50, 1.80], ["arrow_blow", 1.96, 2.20, 2.60], ["strafe_crossbow", 0.74, 0.85, 1.00],
			["dragons_breath_crossbow", 0.48, 0.70, 1.00]]:
		for i in 3:
			assert_near(lo.stats(expectation[0], [1, 4, 8][i]).damage_pct, expectation[i + 1], 0.000001, "%s" % expectation[0])
	for i in 3:
		assert_eq(lo.stats("dragons_breath_crossbow", [1, 4, 8][i]).mob_count, [4, 5, 6][i])
	# The crossbow twins are node for node the Bowmaster's (MS1 compared them): same numbers at all 30 levels, weapon 46 not 45.
	for pair: Array in [["311", 3111006, "321", 3211006, ["damage", "bulletCount"]], ["312", 3121003, "322", 3221003, ["damage", "mobCount", "range", "prop"]]]:
		var bow: Dictionary = imgs[pair[0]].skill["%07d" % int(pair[1])]
		var cross: Dictionary = imgs[pair[2]].skill["%07d" % int(pair[3])]
		assert_eq(int(bow.weapon), 45)
		assert_eq(int(cross.weapon), 46)
		for lv in range(1, 31):
			for field: String in pair[4]:
				assert_eq(float(cross.level[str(lv)][field]), float(bow.level[str(lv)][field]), "%d level %d %s" % [pair[3], lv, field])
	# Art and sounds resolve (the sounds are UOLs the importer expanded).
	for key: String in MAPPED:
		for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
			assert_true(lib.frame(book.wz_path(key) + "/" + suffix) != null, "%s %s" % [key, suffix])
		var hit := book.visual(key, "hit", 1, 1)
		assert_false(lib.anim(hit).is_empty(), "%s hit art %s" % [key, hit])
		for field: String in ["ball", "effect"]:
			var path := book.visual(key, field, 1, 1)
			if path != "":
				assert_false(lib.anim(path).is_empty(), "%s %s %s" % [key, field, path])
		for sound: String in book.def(key).sounds.values():
			if sound != "":
				assert_true(lib.sound(sound) != null, "%s sound %s" % [key, sound])
	assert_eq(lib.anim("Skill.wz/321.img/skill/3211006/hit/0").frame_count(), 3, "Strafe's hit has three frames")
	assert_true(lib.anim("Skill.wz/322.img/skill/3221003/ball").frame_count() > 0)
	assert_true(lib.anim("Skill.wz/320.img/skill/3201005/ball").frame_count() > 0)
	assert_eq(Array(lib.missing), [])
	lib.free()
