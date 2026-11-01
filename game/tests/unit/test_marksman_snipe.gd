extends TestCase
## Snipe (3221007), the Marksman's fixed-share nuke (spec #360, ticket MS8 #368): the shipped definition in skills/marksman.json
## on a Skill.wz-shaped synthetic book 322 (the real node carries only mpCon and cooltime) held with a crossbow, the amounts
## it deals, its target rule, cooldown, rarity bonuses and text, and the real-cache check that the WZ node still has no damage.
## Seeded RNG, fixed dt. The mechanism itself (FixedShare, cast.prefer, the hit_mob branch) is test_fixed_share (MS3).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CROSSBOW := 1462001
const SNIPE := "snipe"
const SNAIL := 1110100
const BOSS := 2220000
const TIERS := ["rare", "epic", "unique", "legendary"]
## The spec's rank table (tier C): share of a monster's max HP at ranks 1..8.
const SHARES := [0.20, 0.24, 0.28, 0.32, 0.36, 0.40, 0.43, 0.45]


## A quiet round of a Marksman holding a crossbow with Snipe learned at `rank_value`; mobs stand still and are snail-sized.
func _world(rank_value := 1, p_seed := 368) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({CROSSBOW: {"incPAD": 29, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	# v83 shape: the node holds mpCon and cooltime per level and the three art nodes; no damage, range, mobCount or weapon.
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mpCon": 40.0 - lv * 0.9, "cooltime": 250.0 - lv * 8.0}
	setup.skill_imgs["322"] = {"skill": {"3221007": {"level": levels, "effect": RF.anim(11, 60.0), "ball": RF.anim(9, 60.0),
		"hit": {"0": RF.anim(5, 0.0)}}}}
	setup["job"] = 322
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != CROSSBOW:
		w.wear_new_item(CROSSBOW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Iron Arrow): only Snipe casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(SNIPE), "snipe is learnable by a Marksman")
	w.loadout.set_rank(SNIPE, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, hp := 1000, boss := false) -> int:
	var slot := RF.put_mob(w, BOSS if boss else SNAIL, w.player.pos.x + dx, 190)
	w.swarm.max_hp[slot] = hp
	w.swarm.hp[slot] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == SNIPE)


func _run(w: RunWorld, ticks: int) -> Array:
	var events := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	return events


## The one hit of a first cast on a lone monster: its damage.
func _bite(w: RunWorld, slot: int) -> int:
	var hits := _hits(_run(w, 30))
	assert_eq(hits.size(), 1, "one bolt, one hit")
	assert_eq(int(hits[0].mob), slot)
	return int(hits[0].damage)


func _mod(w: RunWorld, stat: String, op: String, value: float) -> void:
	w.loadout.add_skill_mod(SNIPE, stat, op, value)


# --- definition -------------------------------------------------------------------------------------------------------

func test_the_definition_is_the_specs_fixed_share_instant_on_the_322_book() -> void:
	var w := _world()
	var d := w.book.def(SNIPE)
	assert_eq(int(d.skill_id), 3221007)
	assert_eq(String(d.book), "322")
	assert_eq(int(d.job), 322)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "physical", "any other type leaves the cap base at 0 and every hit at 1")
	assert_eq(d.cast, {"rule": "nearest", "prefer": "max_hp"})
	assert_near(float(d.cooldown), 10.0, 0.0001)
	assert_near(float(d.range), 450.0, 0.0001)
	assert_true(float(d.speed) > 0.0, "the cosmetic bolt needs a speed")
	assert_false(d.has("weapon_families"), "weapons gate nothing")
	assert_false(d.has("ranks"), "the default 30-level rank table")
	assert_false(d.has("cooldown_field"), "the WZ cooltime is a session value and is not read")
	assert_eq(d.fixed_share, {"share": SHARES, "cap_mult": 20.0, "boss": {"share_scale": 0.1, "cap_mult": 6.0}})
	assert_eq(d.sounds, {"use": "Sound.wz/Skill.img/3221007/Use", "hit": "Sound.wz/Skill.img/3221007/Hit"})
	for art: String in ["ball", "effect"]:
		assert_eq(String(d[art]), "Skill.wz/322.img/skill/3221007/" + art)
	assert_eq(String(d.hit), "Skill.wz/322.img/skill/3221007/hit/0")
	assert_true(d.has("rarity_bonuses"))


func test_the_eight_ranks_resolve_the_share_table_and_the_caps() -> void:
	var w := _world()
	for rank_value in range(1, 9):
		var st := w.loadout.stats(SNIPE, rank_value)
		assert_near(float(st.fixed_share.share), float(SHARES[rank_value - 1]), 0.000001, "rank %d" % rank_value)
		assert_near(float(st.fixed_share.cap_mult), 20.0, 0.000001)
		assert_near(float(st.fixed_share.boss.share_scale), 0.1, 0.000001)
		assert_near(float(st.fixed_share.boss.cap_mult), 6.0, 0.000001)
		assert_eq(String(st.damage_type), "physical")
	var st := w.loadout.stats(SNIPE, 1)
	var base := (float(st.damage_min) + float(st.damage_max)) * 0.5
	assert_true(base > 0.0, "a crossbow in hand gives the cap a base")
	assert_near(float(st.fixed_share.cap), base * 20.0, 0.01)
	assert_near(float(st.fixed_share.boss.cap), base * 6.0, 0.01)


# --- amounts ----------------------------------------------------------------------------------------------------------

func test_rank_one_and_eight_amounts_below_and_above_the_cap() -> void:
	for row: Array in [[1, 0.20], [8, 0.45]]:
		var rank_value: int = row[0]
		var share: float = row[1]
		var below := _world(rank_value)
		var cap := float(below.loadout.stats(SNIPE).fixed_share.cap)
		var small := _mob(below, 300, 100)
		assert_eq(_bite(below, small), floori(100.0 * share), "rank %d below the cap: a share of max HP" % rank_value)
		assert_eq(below.swarm.hp[small], 100 - floori(100.0 * share))
		var above := _world(rank_value)
		var big := _mob(above, 300, 100000000)
		assert_eq(_bite(above, big), floori(cap), "rank %d above the cap: cap_mult x the mean damage" % rank_value)
		assert_true(float(floori(cap)) < 100000000.0 * share)


func test_an_amount_is_at_least_one() -> void:
	var w := _world()
	var m := _mob(w, 300, 2)
	assert_eq(_bite(w, m), 1, "floor(2 x 20%) is 0 and a fixed hit always deals 1")


func test_the_hit_rolls_nothing_and_ignores_defence_and_crit() -> void:
	var w := _world(8)
	var twin := _world(8)
	var m := _mob(w, 300, 100)
	_mob(twin, 300, 100)
	w.swarm.mob_kind(m).pdd = 999999
	w.loadout.add_player_mod("crit", "add", 100.0)
	w.refresh_player_stats()
	var hits := _hits(_run(w, 30))
	assert_eq(int(hits[0].damage), 45)
	assert_false(hits[0].crit)
	_run(twin, 30)
	assert_eq(w.rng.state, twin.rng.state, "no combat draw")


func test_a_boss_takes_the_boss_formula_and_never_more_than_the_boss_cap() -> void:
	var small := _world(8)
	var boss := _mob(small, 300, 500, true)
	assert_eq(_bite(small, boss), 22, "4.5% of 500: the share scaled by 0.1")
	var big := _world(8)
	var cap := float(big.loadout.stats(SNIPE).fixed_share.boss.cap)
	var giant := _mob(big, 300, 100000000, true)
	var taken := _bite(big, giant)
	assert_eq(taken, floori(cap), "capped at 6x the base")
	assert_true(float(taken) <= cap)
	var scheduled := _world(1)
	var steady := _mob(scheduled, 300, 100000000)
	scheduled.swarm.steady[steady] = 1
	assert_eq(_bite(scheduled, steady), floori(float(scheduled.loadout.stats(SNIPE).fixed_share.boss.cap)),
		"a scheduled boss takes the boss cap")


# --- target rule ------------------------------------------------------------------------------------------------------

func test_the_cast_picks_the_strongest_non_boss_in_range() -> void:
	var w := _world()
	var weak := _mob(w, 120, 100)
	var strong := _mob(w, 400, 5000)
	var boss := _mob(w, 80, 99999999, true)
	var out_of_reach := _mob(w, 470, 9000000)
	var hits := _hits(_run(w, 30))
	assert_eq(hits.size(), 1)
	assert_eq(int(hits[0].mob), strong, "the strongest non-boss, not the nearest and not the boss")
	assert_eq(w.swarm.hp[weak], 100)
	assert_eq(w.swarm.hp[boss], 99999999)
	assert_eq(w.swarm.hp[out_of_reach], 9000000, "a monster past the 450 px reach is not a target")


func test_a_boss_is_the_target_only_when_nothing_else_is_in_reach() -> void:
	var w := _world()
	_mob(w, 470, 9000000)
	var boss := _mob(w, 200, 50000, true)
	var hits := _hits(_run(w, 30))
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [boss])


## Weapon immunity (a mob skill) refuses physical hits, so the strongest monster is not a target while it holds it.
func _make_immune(w: RunWorld, slot: int) -> void:
	w.mob_skills._weapon_until[slot] = w.time + 100.0
	assert_false(w.physical_hit_allowed(slot), "the fixture monster is physically immune")


func test_a_physically_immune_strongest_is_skipped_for_the_next_strongest() -> void:
	var w := _world()
	var strong := _mob(w, 200, 5000)
	var weak := _mob(w, 120, 1000)
	_make_immune(w, strong)
	var hits := _hits(_run(w, 30))
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [weak], "the hittable monster takes the bolt")
	assert_eq(w.swarm.hp[strong], 5000)


func test_only_immune_monsters_in_reach_mean_no_cast_and_no_cooldown_spent() -> void:
	var w := _world()
	var strong := _mob(w, 200, 5000)
	_make_immune(w, strong)
	assert_true(_hits(_run(w, 60)).is_empty())
	assert_false(w.events.any(func(e: Dictionary) -> bool: return e.type == "ammo_shot"))
	assert_false(w.runner.has_target(w, SNIPE, w.loadout.stats(SNIPE, 1), w.cast_origin()), "has_target agrees")
	w.mob_skills._weapon_until[strong] = 0.0
	assert_eq(_hits(_run(w, 30)).size(), 1, "the cooldown was not spent: Snipe fires once the immunity ends")


func test_nothing_in_reach_means_no_cast() -> void:
	var w := _world()
	_mob(w, 470, 1000)
	assert_true(_hits(_run(w, 120)).is_empty())
	assert_false(w.events.any(func(e: Dictionary) -> bool: return e.type == "ammo_shot"))


func test_a_count_bonus_fires_a_second_bolt_at_the_next_strongest() -> void:
	var w := _world()
	var weak := _mob(w, 120, 100)
	var strong := _mob(w, 400, 5000)
	var mid := _mob(w, 250, 800)
	var boss := _mob(w, 80, 99999999, true)
	var strong_at := w.mob_center(strong)
	var mid_at := w.mob_center(mid)
	_mod(w, "count", "add", 1.0)
	var events := _run(w, 30)
	var hits := _hits(events)
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [strong, mid], "the two strongest non-bosses")
	assert_eq(w.swarm.hp[weak], 100)
	assert_eq(w.swarm.hp[boss], 99999999)
	var bolts := events.filter(func(e: Dictionary) -> bool: return e.type == "ammo_shot")
	assert_eq(bolts.size(), 2, "one cosmetic bolt per target")
	assert_eq(String(bolts[0].ball), "Skill.wz/322.img/skill/3221007/ball")
	assert_eq(bolts[0].to, strong_at)
	assert_eq(bolts[1].to, mid_at)


func test_the_bolt_is_cosmetic_and_the_damage_lands_at_the_cast() -> void:
	var w := _world()
	var m := _mob(w, 300, 100)
	var events := _run(w, 2)
	assert_eq(_hits(events).size(), 1, "damage on the cast tick")
	assert_eq(w.swarm.hp[m], 80)
	assert_eq(w.projectiles.active_count(), 0, "no damage projectile")


func test_a_dead_or_hidden_caster_does_not_fire() -> void:
	var dead := _world()
	var a := _mob(dead, 300, 1000)
	dead.god = false
	dead.take_hit(1.0e9, false, "", dead.player.pos + Vector2(50, 0), {"accuracy": 9999.0})
	assert_eq(dead.state, RunWorld.DEAD)
	assert_true(_hits(_run(dead, 120)).is_empty())
	assert_eq(dead.swarm.hp[a], 1000)
	var hidden := _world()
	var b := _mob(hidden, 300, 1000)
	assert_true(hidden.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 20.0,
		"buff_stat": "", "buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}}))
	assert_true(hidden.is_hidden())
	assert_true(_hits(_run(hidden, 120)).is_empty())
	assert_eq(hidden.swarm.hp[b], 1000)


# --- cooldown ---------------------------------------------------------------------------------------------------------

func test_the_cooldown_is_ten_seconds_and_booster_shortens_it() -> void:
	var plain := _world()
	var quick := _world()
	_mod(quick, "cooldown", "mul", 0.88)
	assert_near(float(plain.loadout.stats(SNIPE).cooldown), 10.0, 0.001)
	assert_near(float(quick.loadout.stats(SNIPE).cooldown), 8.8, 0.001)
	for w: RunWorld in [plain, quick]:
		_mob(w, 300, 100000000)
	var plain_hits := 0
	var quick_hits := 0
	for t in 570: # 9.5 s
		plain.step(DT, MoveInput.new())
		quick.step(DT, MoveInput.new())
		plain_hits += _hits(plain.drain_events()).size()
		quick_hits += _hits(quick.drain_events()).size()
	assert_eq(plain_hits, 1, "still cooling down at 9.5 s")
	assert_eq(quick_hits, 2, "Booster's second bolt has flown at 8.8 s")
	for t in 60: # 10.5 s
		plain.step(DT, MoveInput.new())
		plain_hits += _hits(plain.drain_events()).size()
	assert_eq(plain_hits, 2, "the second plain bolt flies at 10 s")


# --- rarity -----------------------------------------------------------------------------------------------------------

func test_the_catalog_lists_the_specs_bonuses() -> void:
	var bonuses: Dictionary = DataRepo.load_all().skills.skills[SNIPE].rarity_bonuses
	for tier: String in TIERS:
		assert_eq(bonuses[tier].size(), 1, tier)
	assert_eq([String(bonuses.rare[0].id), String(bonuses.rare[0].text)], ["marksman_boost", "Marksman Boost"])
	assert_eq(bonuses.rare[0].effects, [{"stat": "damage", "op": "mul", "value": 1.2}])
	assert_eq([String(bonuses.epic[0].id), String(bonuses.epic[0].text)], ["booster", "Crossbow Booster"])
	assert_eq(bonuses.epic[0].effects, [{"stat": "cooldown", "op": "mul", "value": 0.88}])
	assert_eq([String(bonuses.unique[0].id), String(bonuses.unique[0].text)], ["final_attack", "Final Attack"])
	assert_eq(bonuses.unique[0].effects, [{"stat": "count", "op": "add", "value": 1.0}])
	assert_eq(String(bonuses.legendary[0].id), String(bonuses.unique[0].id), "Legendary shares the Unique's repeat counter")
	assert_eq(bonuses.legendary[0].effects, [{"stat": "count", "op": "add", "value": 1.0}, {"stat": "damage", "op": "mul", "value": 1.2}])


func test_each_bonus_changes_the_resolved_cast() -> void:
	var bonuses: Dictionary = DataRepo.load_all().skills.skills[SNIPE].rarity_bonuses
	var before := _world(4).loadout.stats(SNIPE)
	for tier: String in TIERS:
		var w := _world(4)
		for bonus: Dictionary in bonuses[tier]:
			for effect: Dictionary in bonus.effects:
				_mod(w, String(effect.stat), String(effect.op), float(effect.value))
		var after := w.loadout.stats(SNIPE)
		assert_true(after.fixed_share.damage_mult != before.fixed_share.damage_mult or after.cooldown != before.cooldown
			or after.count != before.count, tier)
		var boosted: bool = tier in ["rare", "legendary"]
		assert_near(float(after.fixed_share.damage_mult), float(before.fixed_share.damage_mult) * (1.2 if boosted else 1.0), 0.00001, tier)
		assert_near(float(after.fixed_share.cap), float(before.fixed_share.cap), 0.01, tier + ": the modifier scales the amount after the cap")
		assert_near(float(after.cooldown), float(before.cooldown) * (0.88 if tier == "epic" else 1.0), 0.0001, tier)
		assert_eq(int(after.count), int(before.count) + (1 if tier in ["unique", "legendary"] else 0), tier)


func test_rare_and_legendary_multiply_the_amount_after_the_cap() -> void:
	var plain := _world(8)
	var rare := _world(8)
	_mod(rare, "damage", "mul", 1.2)
	var below_plain := _mob(plain, 300, 100)
	var below_rare := _mob(rare, 300, 100)
	assert_eq(_bite(plain, below_plain), 45)
	assert_eq(_bite(rare, below_rare), 54, "45 x 1.2")
	var capped := _world(8)
	var capped_boosted := _world(8)
	_mod(capped_boosted, "damage", "mul", 1.2)
	var cap := float(capped.loadout.stats(SNIPE).fixed_share.cap)
	var a := _mob(capped, 300, 100000000)
	var b := _mob(capped_boosted, 300, 100000000)
	assert_eq(_bite(capped, a), floori(cap))
	assert_eq(_bite(capped_boosted, b), floori(cap * 1.2), "the capped amount is what Marksman Boost multiplies")
	var boss := _world(8)
	_mod(boss, "damage", "mul", 1.2)
	var boss_cap := float(boss.loadout.stats(SNIPE).fixed_share.boss.cap)
	var giant := _mob(boss, 300, 100000000, true)
	assert_eq(_bite(boss, giant), floori(boss_cap * 1.2))


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for tier: String in TIERS:
		var a := _world()
		var b := _world()
		var c := a.upgrades.choice_card(SNIPE + "_rank", a, tier)
		assert_false(c.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		a.upgrades.apply(SNIPE + "_rank", a, tier)
		b.upgrades.apply(SNIPE + "_rank", b, tier)
		assert_eq(a.loadout.rank(SNIPE), 2, "%s: exactly one rank on top" % tier)
		assert_eq(a.loadout.skill_mods.get(SNIPE, {}), b.loadout.skill_mods.get(SNIPE, {}))
		assert_false(a.loadout.skill_mods.get(SNIPE, {}).is_empty(), "%s: the bonus is applied" % tier)
		var plain := _world()
		plain.loadout.set_rank(SNIPE, 2)
		assert_ne(a.loadout.stats(SNIPE), plain.loadout.stats(SNIPE), "%s changes the resolved cast beyond the rank" % tier)


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	var w := _world()
	w.upgrades.apply(SNIPE + "_rank", w, "unique")
	w.upgrades.apply(SNIPE + "_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:final_attack" % SNIPE]), 2, "one counter for both")
	assert_near(w.loadout.skill_stat(SNIPE, "count", 1.0), 1.0 + 1.0 + 0.8, 0.00001, "the second award x0.8")
	var m := _world()
	m.loadout.set_rank(SNIPE, 8)
	var expected := 1.0
	for n in 3:
		m.upgrades.apply(SNIPE + "_rank", m, "normal")
		expected *= 1.0 + 0.05 * pow(0.8, n)
		assert_near(m.loadout.skill_stat(SNIPE, "damage", 1.0), expected, 0.00001, "Mastery repeat %d" % n)
	assert_eq(m.loadout.rank(SNIPE), 8, "Mastery never raises the rank")


# --- text -------------------------------------------------------------------------------------------------------------

func test_the_skill_window_and_the_rank_card_read_the_share_and_the_caps() -> void:
	var w := _world(8)
	var text := SkillText.new(w.book)
	var line := text.level_line(SNIPE, 30, w.loadout.stats(SNIPE))
	assert_true(line.contains("Deals 45% of a monster's max HP (up to 20x your damage); bosses 4.5% (up to 6x)"), line)
	var one := _world(1)
	var card := one.upgrades.choice_card(SNIPE + "_rank", one, "normal")
	assert_eq(card.skill_changes.get("fixed_share"), {"before": 20, "after": 24}, "the rank card previews the share")
	assert_false(card.skill_changes.has("cooltime"), "and not the WZ session cooltime the skill never reads")
	assert_true(Array(LevelUpWindow.change_lines(card)).has("Max HP bite: 20% → 24%"), str(LevelUpWindow.change_lines(card)))
	var learn := SkillText.new(one.book).dress([one.upgrades.choice_card(SNIPE + "_new", one, "normal")], one.loadout)
	assert_true(String(learn[0].detail).contains("Deals 20% of a monster's max HP"), String(learn[0].detail))


# --- data validation --------------------------------------------------------------------------------------------------

func test_a_fixed_share_skill_must_be_physical() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	assert_eq(FixedShare.definition_errors(skills), PackedStringArray(), "the shipped data is fine")
	var errors := PackedStringArray()
	DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_eq(errors, PackedStringArray(), "and loads without errors")
	var bad: Dictionary = {SNIPE: skills[SNIPE].duplicate(true)}
	bad[SNIPE].damage = "magic"
	assert_eq(FixedShare.definition_errors(bad).size(), 1, "magic leaves the cap base at 0")
	bad[SNIPE].erase("damage")
	assert_eq(FixedShare.definition_errors(bad).size(), 1, "no damage type either")
	bad[SNIPE].damage = "physical"
	bad[SNIPE].fixed_share.share = []
	assert_eq(FixedShare.definition_errors(bad).size(), 1, "an empty share table")
	bad[SNIPE].fixed_share = skills[SNIPE].fixed_share.duplicate(true)
	bad[SNIPE].fixed_share.erase("boss")
	assert_eq(FixedShare.definition_errors(bad).size(), 1, "no boss block")
	bad[SNIPE].fixed_share = skills[SNIPE].fixed_share.duplicate(true)
	bad[SNIPE].fixed_share.share = ["0.2"]
	assert_eq(FixedShare.definition_errors(bad).size(), 1, "a share entry that is not a number would deal 1")
	bad[SNIPE].fixed_share.share = [0.2, 1.5]
	assert_eq(FixedShare.definition_errors(bad).size(), 1, "a share above 100% of max HP")
	bad[SNIPE].fixed_share = skills[SNIPE].fixed_share.duplicate(true)
	bad[SNIPE].fixed_share.cap_mult = 0
	assert_eq(FixedShare.definition_errors(bad).size(), 1, "a zero cap")
	bad[SNIPE].fixed_share = skills[SNIPE].fixed_share.duplicate(true)
	bad[SNIPE].fixed_share.boss.share_scale = 2.0
	assert_eq(FixedShare.definition_errors(bad).size(), 1, "a boss share scale above 1")
	var plain: Dictionary = {"energy_bolt": {"damage": "magic"}}
	assert_true(FixedShare.definition_errors(plain).is_empty(), "skills without the block are not checked")


# --- real cache -------------------------------------------------------------------------------------------------------

func test_real_cache_the_wz_node_still_has_no_damage() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var img := lib.img("Skill.wz/322.img")
	assert_true(img != null, "Skill.wz/322.img is in the cache")
	if img == null:
		lib.free()
		return
	var node: Dictionary = img.root.skill["3221007"]
	assert_eq(node.level.size(), 30)
	for lv in range(1, 31):
		var level: Dictionary = node.level[str(lv)]
		for field: String in ["damage", "range", "mobCount", "lt", "rb", "attackCount", "bulletCount"]:
			assert_false(level.has(field), "level %d has no `%s`: a data change must revisit the fixed-share design" % [lv, field])
		assert_true(level.has("cooltime"), "the session cooltime is still there (and unused)")
	assert_false(node.has("weapon"), "no weapon field, so the cast draws with the crossbow's own shoot2")
	assert_false(node.has("action"))
	for art: String in ["effect", "ball", "hit"]:
		assert_true(node.has(art), art)
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"322": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "crossbow"
	assert_eq(book.max_rank(SNIPE), 8)
	for rank_value in range(1, 9):
		var st := lo.stats(SNIPE, rank_value)
		assert_near(float(st.fixed_share.share), float(SHARES[rank_value - 1]), 0.000001, "rank %d" % rank_value)
		assert_near(float(st.cooldown), 10.0, 0.001, "the cooldown ignores the WZ cooltime")
	lib.free()
