extends TestCase
## Dark Knight Dragon Fury and Sacrifice (spec #348, ticket D6 #354): the long box swing that pays a flat HP cost, and the heavy
## single hit that hurts the caster by a share of the damage it dealt (Achilles shrinks the recoil, Berserk raises damage at
## or below half HP). Synthetic Skill.wz levels and the fixture spear (box (-88,-62)..(-18,-6)) for geometry; the
## real-cache tests at the end read the eight mapped ranks of both skills. Seeded RNG, fixed ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 400.0
const MAX_HP := 1000
const SPEAR := 1432000
const POLE_ARM := 1442000
const TIERS := ["rare", "epic", "unique", "legendary"]


func _levels() -> Dictionary:
	var fury := {}
	var sacrifice := {}
	for lv in range(1, 31):
		fury[str(lv)] = {"damage": 150, "mobCount": 6, "hpCon": 20}
		sacrifice[str(lv)] = {"damage": 200, "x": 18}
	return {"131": {"skill": {"1311003": {"level": fury}, "1311004": {"level": fury}, "1311005": {"level": sacrifice}}}}


## A Dark Knight (job 132, the fixture spear in hand) with `key` learned at rank 1, full HP, nothing else on the map.
func _world(key: String, weapon := SPEAR, max_hp := MAX_HP) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["132"]["playable"] = true
	data.balance.player.hp = max_hp
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 354, data))
	setup.equipment_info[POLE_ARM] = {"reqJob": 13, "reqLevel": 10, "incPAD": 32.0, "attackSpeed": 8.0,
		"afterImage": "spear", "sfx": "spear"}
	# The fixture swings only the one-handed stances: a spear stabs and a pole arm swings P-stances (WeaponInfo.BASIC_ACTIONS), 120 px of reach.
	for action in ["stabT1", "stabT2", "swingP1", "swingP2", "swingT2"]:
		setup.body_img[action] = {"0": {"delay": 300.0}, "1": {"delay": 150.0}, "2": {"delay": 350.0}}
		setup.afterimage_imgs.spear["0"][action] = {"lt": {"$v": [-120.0, -62.0]}, "rb": {"$v": [-18.0, -6.0]},
			"2": {"0": {"$canvas": [0, 0, 0, 40, 30], "delay": 200.0}}}
	for book: String in _levels():
		setup.skill_imgs[book] = _levels()[book]
	var w := RunWorld.new(setup)
	w.set_job(132)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.equipment.worn.weapon = Equipment.create(weapon, {"incPAD": 1500})
	w.refresh_player_stats()
	w.learn_skill(key)
	RF.place_player(w, CASTER_X)
	w.player.facing = -1
	w.god = false
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, hp := 100000.0) -> int:
	return RF.put_mob(w, MOB, CASTER_X + dx, 190.0, hp)


func _hp(w: RunWorld, hp: float) -> void:
	w._hp = hp
	w._write_player_state(0.0)


## One runner step with the grid rebuilt: the events it produced.
func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


# --- Dragon Fury ------------------------------------------------------------------------------------------------

func test_fury_is_defined_with_the_tier_a_numbers() -> void:
	var w := _world("dragon_fury")
	var d := w.book.def("dragon_fury")
	assert_eq(int(d.skill_id), 1311003)
	assert_eq(String(d.cast.rule), "box")
	assert_eq(int(d.art_by_family.polearm), 1311004)
	assert_eq(w.book.max_rank("dragon_fury"), 8)
	var st := w.loadout.stats("dragon_fury")
	assert_eq(st.box, Rect2(-241, -81, 225, 112), "the skill's own afterimage rectangle (-241,-81)..(-16,31)")
	assert_eq(st.mob_count, 6)
	assert_eq(st.hp_cost, 20)
	assert_eq(st.action, "swingP1")
	assert_near(st.cooldown, 1.2)


func test_fury_hits_a_mob_at_240_px_but_not_at_250() -> void:
	for side in [-1, 1]:
		var w := _world("dragon_fury")
		w.player.facing = side
		var near := _mob(w, 240.0 * side)
		var far := _mob(w, 250.0 * side)
		var behind := _mob(w, -100.0 * side)
		var events := _cast(w)
		assert_eq(_of(events, "cast").size(), 1)
		var hit := _of(events, "mob_hit").map(func(e: Dictionary) -> int: return int(e.mob))
		assert_eq(hit, [near], "side %d: only the mob inside the box" % side)
		assert_eq(w.swarm.hp[far], w.swarm.max_hp[far])
		assert_eq(w.swarm.hp[behind], w.swarm.max_hp[behind])


func test_fury_strikes_six_mobs_at_most() -> void:
	var w := _world("dragon_fury")
	for k in 9:
		_mob(w, -30.0 - 20.0 * k)
	var hits := _of(_cast(w), "mob_hit")
	assert_eq(hits.size(), 6, "mobCount 6 caps the targets")


func test_fury_pays_its_flat_hp_cost_in_red_and_never_a_lethal_one() -> void:
	var w := _world("dragon_fury")
	_mob(w, -100.0)
	var events := _cast(w)
	var spent := _of(events, "hp_spent")
	assert_eq(spent.size(), 1)
	assert_eq(int(spent[0].amount), 20)
	assert_eq(String(spent[0].kind), "cost")
	assert_eq(w.hp_exact(), float(MAX_HP - 20))
	# With 20 HP or less left the cast waits: nothing is spent, no cooldown starts, no cast.
	var low := _world("dragon_fury")
	_mob(low, -100.0)
	_hp(low, 20.0)
	var waiting := _cast(low)
	assert_eq(_of(waiting, "cast").size(), 0, "paying 20 of 20 HP would kill: the cast waits")
	assert_eq(low.hp_exact(), 20.0)
	assert_true(float(low.runner.cooldowns.get("dragon_fury", 0.0)) <= 0.0, "no cooldown started")
	_hp(low, 21.0)
	assert_eq(_of(_cast(low), "cast").size(), 1, "21 HP pays 20 and survives with 1")
	assert_eq(low.hp_exact(), 1.0)


func test_the_pole_arm_twin_changes_the_art_and_not_the_numbers() -> void:
	var spear := _world("dragon_fury", SPEAR)
	var pole := _world("dragon_fury", POLE_ARM)
	var a := spear.loadout.stats("dragon_fury")
	var b := pole.loadout.stats("dragon_fury")
	assert_eq(a.hit, "Skill.wz/131.img/skill/1311003/hit/0")
	assert_eq(b.hit, "Skill.wz/131.img/skill/1311004/hit/0")
	assert_eq(b.effect, "Skill.wz/131.img/skill/1311004/effect")
	assert_eq(b.box, a.box)
	assert_eq(b.mob_count, a.mob_count)
	assert_eq(b.hp_cost, a.hp_cost)
	assert_eq(b.damage_pct, a.damage_pct)
	assert_eq(spear.book.art_path("dragon_fury", "Sound.wz/Skill.img/1311003/Use", "spear"), "Sound.wz/Skill.img/1311003/Use")
	assert_eq(pole.book.art_path("dragon_fury", "Sound.wz/Skill.img/1311003/Use", "polearm"), "Sound.wz/Skill.img/1311004/Use")


func test_the_fury_cast_plays_the_rune_circle_art_at_the_caster() -> void:
	var w := _world("dragon_fury", POLE_ARM)
	_mob(w, -100.0)
	var cast: Dictionary = _of(_cast(w), "cast")[0]
	assert_eq(String(cast.effect), "Skill.wz/131.img/skill/1311004/effect")
	var extra: Array = w.book.def("dragon_fury").get("cast_visuals", [])
	assert_eq(extra.size(), 2, "flower burst and delayed swing trail")
	assert_eq(w.book.art_path("dragon_fury", String(extra[0].path), "polearm"), "Skill.wz/131.img/skill/1311004/effect0")


# --- Sacrifice --------------------------------------------------------------------------------------------------

func _dealt(events: Array) -> int:
	var total := 0
	for e: Dictionary in _of(events, "mob_hit"):
		total += int(e.damage)
	return total


func _recoil(events: Array) -> int:
	var paid := _of(events, "hp_spent").filter(func(e: Dictionary) -> bool: return e.kind == "recoil")
	return int(paid[0].amount) if not paid.is_empty() else 0


## A Sacrifice cast at a lone mob 50 px in front, the caster at `hp` of a 10000 HP pool (so the 10% cap is 1000 and out of the way).
func _sacrifice_cast(hp: float, cards: Array = [], max_hp := 10000) -> Dictionary:
	var w := _world("sacrifice", SPEAR, max_hp)
	for card: Array in cards:
		w.upgrades.apply(String(card[0]), w, String(card[1]))
	_mob(w, -50.0)
	_hp(w, hp)
	var events := _cast(w)
	return {"w": w, "events": events, "dealt": _dealt(events), "recoil": _recoil(events)}


func test_sacrifice_is_defined_with_the_tier_a_numbers() -> void:
	var w := _world("sacrifice")
	var d := w.book.def("sacrifice")
	assert_eq(int(d.skill_id), 1311005)
	assert_eq(String(d.cast.rule), "weapon_reach")
	assert_eq(w.book.max_rank("sacrifice"), 8)
	var st := w.loadout.stats("sacrifice")
	assert_eq(st.count, 1)
	assert_eq(st.attack_count, 1)
	assert_near(st.cooldown, 2.0)
	assert_near(st.self_damage, 18.0)
	assert_near(st.self_damage_cap, 0.10)
	assert_near(st.damage_pct, 2.0)
	assert_eq(st.hp_cost, 0, "Sacrifice pays only the recoil, no cost up front")
	assert_near(st.low_hp_damage, 0.0)


func test_sacrifice_strikes_one_mob_inside_the_weapons_reach() -> void:
	for side in [-1, 1]:
		var w := _world("sacrifice")
		w.player.facing = side
		var inside := _mob(w, 60.0 * side)
		var second := _mob(w, 70.0 * side)
		var outside := _mob(w, 130.0 * side)
		var events := _cast(w)
		var hits := _of(events, "mob_hit")
		assert_eq(hits.size(), 1, "one line on one target")
		assert_eq(int(hits[0].mob), inside, "the nearest mob in reach")
		assert_eq(w.swarm.hp[second], w.swarm.max_hp[second])
		assert_eq(w.swarm.hp[outside], w.swarm.max_hp[outside])


func test_the_hit_spark_is_the_held_weapons() -> void:
	# The spear stabs (stabT1, the mace stab spark), the pole arm swings (swingP1, the mace swing spark).
	for row: Array in [[SPEAR, "stabT1", "Character.wz/Afterimage/hit.img/mace2"],
			[POLE_ARM, "swingP1", "Character.wz/Afterimage/hit.img/mace1"]]:
		var w := _world("sacrifice", int(row[0]))
		_mob(w, -50.0)
		assert_eq(w.loadout.stats("sacrifice").action, row[1])
		var hit: Dictionary = _of(_cast(w), "mob_hit")[0]
		assert_eq(String(hit.hit_visual), row[2], "the node has no hit art: the held weapon's spark")


func test_the_recoil_is_18_percent_of_the_damage_dealt() -> void:
	var c := _sacrifice_cast(10000.0)
	assert_true(c.dealt > 500, "a real hit: %d" % c.dealt)
	assert_eq(c.recoil, floori(0.18 * c.dealt))
	assert_eq(c.w.hp_exact(), 10000.0 - c.recoil)
	var spent: Dictionary = _of(c.events, "hp_spent")[0]
	assert_eq(String(spent.skill), "sacrifice")


func test_the_recoil_is_capped_at_ten_percent_of_max_hp() -> void:
	var c := _sacrifice_cast(100.0, [], 100)
	assert_true(floori(0.18 * c.dealt) > 10, "the uncapped share would be %d" % floori(0.18 * c.dealt))
	assert_eq(c.recoil, 10, "10% of 100 max HP")
	assert_eq(c.w.hp_exact(), 90.0)


func test_the_recoil_never_takes_the_last_hp_but_the_cast_still_happens() -> void:
	var c := _sacrifice_cast(4.0, [], 10000)
	assert_eq(_of(c.events, "cast").size(), 1, "never lethal, never refused")
	assert_true(c.dealt > 0)
	assert_eq(c.recoil, 3)
	assert_eq(c.w.hp_exact(), 1.0)
	var one := _sacrifice_cast(1.0)
	assert_eq(_of(one.events, "cast").size(), 1)
	assert_eq(one.recoil, 0, "at 1 HP there is nothing to take")
	assert_eq(one.w.hp_exact(), 1.0)


func test_achilles_shrinks_the_recoil_and_changes_nothing_else() -> void:
	var base := _sacrifice_cast(10000.0)
	var achilles := _sacrifice_cast(10000.0, [["sacrifice_rank", "epic"]])
	assert_near(achilles.w.loadout.stats("sacrifice").self_damage, 18.0 * 0.6)
	assert_eq(achilles.recoil, floori(0.108 * achilles.dealt), "x0.6 of the recoil percentage")
	assert_true(achilles.recoil < base.recoil, "%d -> %d" % [base.recoil, achilles.recoil])
	assert_near(float(achilles.w.loadout.stats("sacrifice").self_damage_cap), 0.10, 0.0001, "the cap does not move")


func test_berserk_raises_damage_only_at_or_below_half_hp() -> void:
	var cards := [["sacrifice_rank", "unique"]]
	var above := _sacrifice_cast(5100.0, cards)
	var at_half := _sacrifice_cast(5000.0, cards)
	var plain := _sacrifice_cast(5000.0)
	assert_near(above.w.loadout.stats("sacrifice").low_hp_damage, 0.5)
	assert_true(above.dealt > 0)
	assert_true(absi(above.dealt - plain.dealt) <= 1, "51%% HP: no bonus (%d vs %d)" % [above.dealt, plain.dealt])
	assert_near(float(at_half.dealt) / float(above.dealt), 1.5, 0.02, "50% HP: x1.5 on the same seeded cast")


func test_the_recoil_is_computed_on_the_berserk_boosted_damage() -> void:
	var c := _sacrifice_cast(5000.0, [["sacrifice_rank", "unique"]])
	var base := _sacrifice_cast(5000.0)
	assert_eq(c.recoil, floori(0.18 * c.dealt))
	assert_true(c.recoil > base.recoil, "%d vs %d" % [base.recoil, c.recoil])


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	var expect := {"rare": "mastery", "epic": "achilles", "unique": "berserk", "legendary": "berserk"}
	for tier: String in TIERS:
		var w := _world("sacrifice")
		var before := w.loadout.rank("sacrifice")
		var card := w.upgrades.choice_card("sacrifice_rank", w, tier)
		assert_eq(String(card.rarity_bonus.id), expect[tier], tier)
		w.upgrades.apply("sacrifice_rank", w, tier)
		assert_eq(w.loadout.rank("sacrifice"), before + 1, tier)
	var w := _world("sacrifice")
	w.upgrades.apply("sacrifice_rank", w, "unique")
	w.upgrades.apply("sacrifice_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:sacrifice:berserk"]), 2, "Legendary shares the Unique's counter")
	assert_near(w.loadout.skill_stat("sacrifice", "low_hp_damage", 0.0), 0.5 + 0.5 * 0.8, 0.0001, "the repeat shrinks x0.8")


func test_every_sacrifice_bonus_changes_a_resolved_stat() -> void:
	var w := _world("sacrifice")
	var base := w.loadout.stats("sacrifice")
	var rows := {"rare": ["damage_max", "up"], "epic": ["self_damage", "down"], "unique": ["low_hp_damage", "up"]}
	for tier: String in rows:
		var v := _world("sacrifice")
		v.upgrades.apply("sacrifice_rank", v, tier)
		var rank_one := v.loadout.stats("sacrifice", 1)
		var st := v.loadout.stats("sacrifice")
		var field := String(rows[tier][0])
		if rows[tier][1] == "up":
			assert_true(float(rank_one[field]) > float(base[field]), "%s: %s" % [tier, field])
		else:
			assert_true(float(rank_one[field]) < float(base[field]), "%s: %s" % [tier, field])
		assert_eq(st.rank, 2, tier)
	var legendary := _world("sacrifice")
	legendary.upgrades.apply("sacrifice_rank", legendary, "legendary")
	var lst := legendary.loadout.stats("sacrifice", 1)
	assert_true(float(lst.low_hp_damage) > 0.0 and float(lst.damage_max) > float(base.damage_max), "Berserk and damage x1.2")


func test_the_sacrifice_card_preview_states_the_recoil() -> void:
	var w := _world("sacrifice")
	var card := w.upgrades.choice_card("sacrifice_rank", w, "epic")
	var text := JSON.stringify(card)
	assert_true(text.contains("Achilles"), "the bonus is named")
	var lines := HpRisk.mechanic_lines(w.loadout.stats("sacrifice"))
	assert_true(lines.size() >= 1 and String(lines[0]).begins_with("Recoil: 18% of damage dealt"), str(lines))
	var line := SkillText.new(w.book).level_line("sacrifice", w.book.canonical_level("sacrifice", 1), w.loadout.stats("sacrifice"))
	assert_true(line.contains("Recoil: 18% of damage dealt (at most 10% of max HP)"), line)
	assert_true(line.contains("Damage 200%"), line)


# --- Fury rarity bonuses -----------------------------------------------------------------------------------------

func test_every_fury_bonus_changes_a_resolved_stat() -> void:
	var base_world := _world("dragon_fury")
	var base := base_world.loadout.stats("dragon_fury", 1)
	var expect := {"rare": "damage_max", "epic": "mob_count", "unique": "cooldown"}
	for tier: String in expect:
		var w := _world("dragon_fury")
		w.upgrades.apply("dragon_fury_rank", w, tier)
		var st := w.loadout.stats("dragon_fury", 1)
		var field := String(expect[tier])
		if tier == "unique":
			assert_true(float(st[field]) < float(base[field]), "%s: %s" % [tier, field])
		else:
			assert_true(float(st[field]) > float(base[field]), "%s: %s" % [tier, field])
		assert_eq(w.loadout.rank("dragon_fury"), 2, tier + " adds a rank")
	assert_eq(base.mob_count + 2, _fury_count("epic"), "Wide Fury is +2 targets")
	var legendary := _world("dragon_fury")
	legendary.upgrades.apply("dragon_fury_rank", legendary, "legendary")
	var lst := legendary.loadout.stats("dragon_fury", 1)
	assert_true(float(lst.cooldown) < float(base.cooldown) and float(lst.damage_max) > float(base.damage_max), "Booster and damage x1.2")


func _fury_count(tier: String) -> int:
	var w := _world("dragon_fury")
	w.upgrades.apply("dragon_fury_rank", w, tier)
	return w.loadout.stats("dragon_fury", 1).mob_count


func test_wide_fury_strikes_eight_mobs() -> void:
	var w := _world("dragon_fury")
	w.upgrades.apply("dragon_fury_rank", w, "epic")
	for k in 10:
		_mob(w, -30.0 - 20.0 * k)
	assert_eq(_of(_cast(w), "mob_hit").size(), 8)


# --- the real cache: all eight mapped ranks (SKIP without it, which proves nothing) ----------------------------------

const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Skill.wz 131.img at those levels, verbatim (tier A; D1 #349 notes).
const FURY_DAMAGE := [110, 150, 180, 195, 215, 229, 241, 250]
const FURY_HP := [20, 20, 25, 25, 25, 30, 30, 30]
const SACRIFICE_DAMAGE := [220, 240, 260, 275, 295, 315, 335, 350]
const SACRIFICE_RECOIL := [18, 16, 14, 13, 11, 9, 7, 5]


func _real_book() -> Array:
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/131.img")
	var imgs := {}
	if img != null:
		imgs["131"] = img.root
	return [library, SkillBook.from_data(DataRepo.load_all().skills, imgs), imgs]


func test_real_cache_dragon_fury_reads_the_eight_mapped_ranks() -> void:
	if not require_cache():
		return
	var parts := _real_book()
	var book: SkillBook = parts[1]
	assert_true(not (parts[2] as Dictionary).is_empty(), "book 131 imported")
	assert_eq(book.rank_table("dragon_fury").map(func(v: Variant) -> int: return int(v)), LEVELS)
	for rank in range(1, 9):
		var lo := Loadout.new(book)
		lo.max_hp = 1000
		lo.add_skill("dragon_fury")
		var st := lo.stats("dragon_fury", rank)
		assert_eq(st.level, LEVELS[rank - 1], "rank %d" % rank)
		assert_near(st.damage_pct, FURY_DAMAGE[rank - 1] / 100.0, 0.0001, "rank %d damage" % rank)
		assert_eq(st.hp_cost, FURY_HP[rank - 1], "rank %d flat HP cost" % rank)
		assert_eq(st.mob_count, 6, "rank %d" % rank)
		assert_eq(st.box, Rect2(-241, -81, 225, 112), "rank %d: the literal box, not a per-level lt/rb" % rank)
		assert_eq(st.action, "swingP1")
	var twin := book.level_node("dragon_fury", 30)
	assert_eq(twin.damage, 250.0)
	(parts[0] as AssetLibrary).free()


func test_real_cache_sacrifice_reads_the_eight_mapped_ranks() -> void:
	if not require_cache():
		return
	var parts := _real_book()
	var book: SkillBook = parts[1]
	assert_true(not (parts[2] as Dictionary).is_empty(), "book 131 imported")
	for rank in range(1, 9):
		var lo := Loadout.new(book)
		lo.max_hp = 1000
		lo.add_skill("sacrifice")
		var st := lo.stats("sacrifice", rank)
		assert_eq(st.level, LEVELS[rank - 1], "rank %d" % rank)
		assert_near(st.damage_pct, SACRIFICE_DAMAGE[rank - 1] / 100.0, 0.0001, "rank %d damage" % rank)
		assert_near(st.self_damage, float(SACRIFICE_RECOIL[rank - 1]), 0.0001, "rank %d recoil %%" % rank)
		assert_near(st.self_damage_cap, 0.10, 0.0001)
		assert_eq(st.hp_cost, 0)
		assert_eq(st.attack_count, 1, "the node has no attackCount: one line")
		assert_eq(st.count, 1)
	(parts[0] as AssetLibrary).free()


func test_real_cache_the_art_nodes_the_two_skills_name_exist_for_both_weapons() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/131.img")
	assert_true(img != null)
	if img != null:
		var skill: Dictionary = img.root["skill"]
		for id in ["1311003", "1311004"]:
			for node in ["effect", "effect0", "hit"]:
				assert_true(skill[id].has(node), "%s/%s" % [id, node])
		assert_true(skill["1311005"].has("effect"), "Sacrifice's ring")
		assert_false(skill["1311005"].has("hit"), "Sacrifice has no hit art: the weapon's spark")
	library.free()


func test_fury_resolves_the_weapon_trail_and_its_body_frame_delay() -> void:
	for row in [[SPEAR, "1311003/afterimage/spear/swingP1/2"], [POLE_ARM, "1311004/afterimage/poleArm/swingP1/2"]]:
		var w := _world("dragon_fury", int(row[0]))
		var visuals: Array = w.loadout.stats("dragon_fury").cast_visuals
		assert_eq(visuals.size(), 2, "rune burst and swing trail")
		if visuals.size() < 2: continue
		assert_eq(visuals[1].path, "Skill.wz/131.img/skill/" + String(row[1]))
		assert_near(visuals[1].delay, 0.45)
		assert_true(visuals[1].follow)
