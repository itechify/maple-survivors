extends TestCase
## The rarity bonuses of the I/L Ice Demon and Element Composition (spec #319, ticket I7 #326): the catalog has the four
## lists, a Rare+ card adds one rank plus its bonus, the Legendary shares the Unique's counter, and Mastery repeats shrink
## x0.8. That each effect changes the resolved cast is audited with the other I/L skills in test_rarity_bonus_effects.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CASTER_X := 2000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]
const TIERS := ["rare", "epic", "unique", "legendary"]
const KEYS := ["ice_demon", "element_composition_il"]
## What each key's lists must hold: [id, text] per tier (Legendary repeats the Unique's id).
const LISTS := {
	"ice_demon": {"rare": ["amplify", "Element Amplification"], "epic": ["reach", "Wide Chill"],
		"unique": ["crowd", "Cold Crowd"], "legendary": ["crowd", "Cold Crowd and damage"]},
	"element_composition_il": {"rare": ["amplify", "Element Amplification"], "epic": ["pierce", "Pierce"],
		"unique": ["twin", "Twin Bolt"], "legendary": ["twin", "Twin Bolt and damage"]},
}


func _levels(box: bool) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 60.0 + lv, "mobCount": 6.0, "time": 4.0}
		if box:
			levels[str(lv)]["lt"] = {"$v": [-300, -100]}
			levels[str(lv)]["rb"] = {"$v": [-15, 0]}
	return levels


func _setup() -> Dictionary:
	var data := RF.quiet_data()
	var setup := RF.with_basic_attack(RF.setup("quiet", 326, data))
	setup.skill_imgs["222"] = {"skill": {"2221003": {"level": _levels(true)}}}
	setup.skill_imgs["221"] = {"skill": {"2211006": {"level": _levels(false)}}}
	return setup


func _world(key: String, own_skill := true) -> RunWorld:
	var w := RunWorld.new(_setup())
	w.set_job(222)
	w.bounds = Rect2(0, -500, 4000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.player.facing = -1
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	if own_skill:
		w.learn_skill(key)
	w.loadout.set_caster(100.0, 0.0, 30)
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.drain_events()
	return w


func test_each_skill_has_four_lists_with_the_named_effects() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in KEYS:
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for tier: String in TIERS:
			assert_eq(bonuses[tier].size(), 1, "%s %s: one bonus" % [key, tier])
			assert_eq(bonuses[tier][0].id, LISTS[key][tier][0], "%s %s id" % [key, tier])
			assert_eq(bonuses[tier][0].text, LISTS[key][tier][1], "%s %s text" % [key, tier])
		var unique: Dictionary = bonuses.unique[0].effects[0]
		var legendary: Array = bonuses.legendary[0].effects
		assert_eq(legendary.size(), 2, "%s: Legendary = the Unique effect plus damage" % key)
		assert_eq(legendary[0], unique, "%s: the Unique's effect" % key)
		assert_eq(legendary[1].stat, "damage")
		assert_eq(legendary[1].op, "mul")
		assert_near(float(legendary[1].value), 1.2)
		assert_eq(bonuses.rare[0].effects.size(), 1)
		assert_eq(bonuses.rare[0].effects[0].stat, "damage")
		assert_near(float(bonuses.rare[0].effects[0].value), 1.2)
	var shape := func(skill: String, tier: String) -> Array:
		return (skills[skill].rarity_bonuses[tier][0].effects as Array).map(
			func(e: Dictionary) -> Array: return [e.stat, e.op, float(e.value)])
	assert_eq(shape.call("ice_demon", "epic"), [["area", "mul", 1.2]])
	assert_eq(shape.call("ice_demon", "unique"), [["count", "add", 1.0]])
	assert_eq(shape.call("element_composition_il", "epic"), [["pierce", "add", 1.0]])
	assert_eq(shape.call("element_composition_il", "unique"), [["count", "add", 1.0]])


func test_a_rare_or_better_card_adds_one_rank_and_its_bonus() -> void:
	for key: String in KEYS:
		for tier: String in TIERS:
			var w := _world(key, false)
			var id := key + "_new"
			var c := w.upgrades.choice_card(id, w, tier)
			assert_false(c.get("rarity_bonus", {}).is_empty(), "%s %s: the card names a bonus" % [key, tier])
			w.upgrades.apply(id, w, tier)
			assert_true(w.loadout.has(key), "%s %s: learned" % [key, tier])
			assert_eq(w.loadout.rank(key), 1, "%s %s: one rank" % [key, tier])
			assert_false(w.loadout.skill_mods.get(key, {}).is_empty(), "%s %s: the bonus is applied" % [key, tier])
			w.upgrades.apply(key + "_rank", w, tier)
			assert_eq(w.loadout.rank(key), 2, "%s %s: +1 rank" % [key, tier])


func test_the_legendary_shares_the_uniques_repeat_counter() -> void:
	for key: String in KEYS:
		var stat := "count"
		var w := _world(key, false)
		w.upgrades.apply(key + "_new", w, "normal")
		var base := int(w.loadout.stats(key).count)
		w.upgrades.apply(key + "_rank", w, "unique")
		assert_eq(int(w.loadout.stats(key).count), base + 1, "%s: the first Unique +1" % key)
		w.upgrades.apply(key + "_rank", w, "legendary")
		var after := w.loadout.skill_stat(key, stat, 0.0)
		assert_near(after, 1.8, 1e-6, "%s: the Legendary's repeat is the Unique's x0.8 (shared counter)" % key)
		assert_eq(int(w.loadout.card_ranks["bonus:%s:%s" % [key, LISTS[key].unique[0]]]), 2, "%s: one counter" % key)


func test_mastery_repeats_shrink_by_0_8() -> void:
	for key: String in KEYS:
		var w := _world(key)
		w.loadout.set_rank(key, 8)
		var expected := 1.0
		for n in 3:
			w.upgrades.apply(key + "_rank", w, "normal")
			expected *= 1.0 + 0.05 * pow(0.8, n)
			assert_near(w.loadout.skill_stat(key, "damage", 1.0), expected, 1e-5, "%s repeat %d" % [key, n])
		assert_eq(w.loadout.rank(key), 8)
