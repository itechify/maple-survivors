extends TestCase
## Bowmaster's core arrows (spec #332, ticket B7 #339): Arrow Blow, Double Shot, Arrow Bomb and Strafe on the `bowmaster` line.
## Fixed 1/60 s ticks, seeded RNG; the Skill.wz levels are the synthetic fixture tables (endpoints recorded from v83) unless a
## test says "real cache" (those call require_cache() and SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOW := 1452051
const KEYS := ["arrow_blow", "bow_double_shot", "arrow_bomb", "strafe"]


## A quiet round of a Bowmaster holding a bow, `key` learned at `rank_value`, mobs frozen and tiny.
func _world(key: String, rank_value := 1, p_seed := 339) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["312"]["playable"] = true # in this test's data only: its pool cards exist (B12 ships the flip)
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup["job"] = 312
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != BOW:
		w.wear_new_item(BOW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50) # snail-sized: the volley is spread a few px vertically
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Arrow Blow): only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Bowmaster" % key)
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


func _ints(values: Array) -> Array:
	return values.map(func(v: Variant) -> int: return int(v))


func _run(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.step(DT, MoveInput.new())


# --- Strafe -----------------------------------------------------------------------------------------------------------

func test_strafe_fires_all_four_arrows_at_one_monster_not_four_monsters() -> void:
	var w := _world("strafe")
	var near := _mob(w, 80)
	_mob(w, 140)
	_mob(w, 200)
	_mob(w, -120)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.projectiles.active_count(), 4, "bulletCount 4")
	_run(w, 45)
	var hits := _hits(w, "strafe")
	assert_eq(hits.size(), 4)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == near), "every arrow reaches the nearest monster")



func test_strafe_prefers_a_scheduled_boss_over_a_nearer_monster() -> void:
	var w := _world("strafe")
	_mob(w, 80)
	var boss := _mob(w, -200, true) # the other side: an arrow stops at the first monster on its line
	w.mob_boss[boss] = 0
	w.runner.step(DT, w)
	_run(w, 50)
	var hits := _hits(w, "strafe")
	assert_eq(hits.size(), 4)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == boss), "all four arrows go to the boss")


func test_strafe_waits_for_a_monster_in_range_and_keeps_its_cooldown() -> void:
	var w := _world("strafe")
	_mob(w, 400) # past the 350 px range
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0)
	_mob(w, 300)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns.strafe), 2.5 - DT, 0.001, "2.5 s cooldown")
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "not ready again")
	var st := w.loadout.stats("strafe")
	assert_eq(st.count, 4)
	assert_eq(st.range, 350.0)
	assert_eq(st.speed, 700.0)
	assert_eq(st.radius, 6.0)
	assert_eq(String(st.hit), "Skill.wz/311.img/skill/3111006/hit/0", "Strafe's own hit art (3 frames), not Arrow Blow's")


func test_strafe_arrows_carry_the_current_ammo_and_rank_damage() -> void:
	var w := _world("strafe", 8)
	_mob(w, 80)
	w.runner.step(DT, w)
	var ammo := w.visual_index(Ammo.bullet_path(w.ammo_id()))
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.visual[i], ammo)
	assert_near(w.loadout.stats("strafe").damage_pct, 1.0, 0.001, "rank 8 is WZ level 30: 100% per arrow")
	assert_near(w.loadout.stats("strafe", 1).damage_pct, 0.74, 0.001, "rank 1 is WZ level 4: 74%")


# --- the ported fillers -----------------------------------------------------------------------------------------------

func test_arrow_blow_fires_one_arrow_with_the_current_ammo_at_the_nearest_monster() -> void:
	var w := _world("arrow_blow")
	var near := _mob(w, 90)
	_mob(w, 160)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 1)
	assert_near(float(w.runner.cooldowns.arrow_blow), 1.0 - DT, 0.001)
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.visual[i], w.visual_index(Ammo.bullet_path(w.ammo_id())), "the ammo's art, not a skill ball")
	_run(w, 40)
	var hits := _hits(w, "arrow_blow")
	assert_eq(hits.size(), 1)
	assert_eq(int(hits[0].mob), near)
	var st := w.loadout.stats("arrow_blow")
	assert_eq([st.range, st.speed, st.radius, st.pierce], [300.0, 600.0, 8.0, 0])


func test_double_shot_splits_its_two_arrows_over_two_monsters() -> void:
	var w := _world("bow_double_shot")
	var first := _mob(w, 90)
	var second := _mob(w, -150) # the other side: an arrow stops at the first monster on its line
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 2)
	_run(w, 40)
	var hit_mobs := _hits(w, "bow_double_shot").map(func(e: Dictionary) -> int: return int(e.mob))
	hit_mobs.sort()
	assert_eq(hit_mobs, [first, second])
	assert_eq(w.loadout.stats("bow_double_shot").count, 2)


func test_double_shot_with_one_monster_sends_both_arrows_at_it() -> void:
	var w := _world("bow_double_shot")
	var only := _mob(w, 100)
	w.runner.step(DT, w)
	_run(w, 40)
	var hits := _hits(w, "bow_double_shot")
	assert_eq(hits.size(), 2)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == only))


func test_the_ported_arrows_name_no_weapon_and_use_the_default_eight_ranks() -> void:
	var w := _world("arrow_blow")
	for key: String in KEYS:
		var d := w.book.def(key)
		assert_false(d.has("weapon_families"), "%s: a weapon gates nothing" % key)
		assert_false(d.has("ranks"), "%s: the default rank table" % key)
		assert_eq(String(d.slot), "active")
		assert_eq(w.book.max_rank(key), 8, key)
	assert_eq(_ints(w.book.rank_table("arrow_blow")), [3, 5, 8, 10, 13, 15, 18, 20])
	assert_eq(_ints(w.book.rank_table("arrow_bomb")), [4, 8, 12, 15, 19, 23, 27, 30])
	assert_eq(_ints(w.book.rank_table("strafe")), [4, 8, 12, 15, 19, 23, 27, 30])
	assert_eq(_ints(KEYS.map(func(k: String) -> Variant: return w.book.def(k).job)), [300, 300, 310, 311])


# --- Arrow Bomb -------------------------------------------------------------------------------------------------------

func test_arrow_bomb_flies_first_then_blasts_six_and_waits_two_seconds() -> void:
	var w := _world("arrow_bomb", 8)
	var slots: Array[int] = []
	for dx in [80, 100, 120, 140, 160, 180, 200, 400]:
		slots.append(_mob(w, dx))
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 1)
	assert_eq(w.swarm.hp[slots[0]], w.swarm.max_hp[slots[0]], "no blast until the arrow lands")
	assert_near(float(w.runner.cooldowns.arrow_bomb), 2.0 - DT, 0.001, "2 s cooldown, up from the old 1 s placeholder")
	_run(w, 40)
	var hits := _hits(w, "arrow_bomb")
	assert_eq(hits.size(), 6, "the primary is inside the canonical mobCount 6")
	assert_eq(w.swarm.hp[slots[6]], w.swarm.max_hp[slots[6]], "the seventh monster is outside the cap")
	assert_eq(w.swarm.hp[slots[7]], w.swarm.max_hp[slots[7]], "the far monster is outside the box")


func test_arrow_bomb_stun_chance_and_time_follow_the_rank_and_never_touch_a_boss() -> void:
	var counts := []
	for rank_value in [1, 8]:
		var w := _world("arrow_bomb", rank_value)
		var st := w.loadout.stats("arrow_bomb")
		var stunned := 0
		var slots: Array[int] = []
		for k in 120:
			slots.append(_mob(w, 80))
		for slot: int in slots:
			w.hit_mob(slot, st, -1)
			if w.swarm.status_time(slot, MobSwarm.STUN) > 0.0:
				stunned += 1
				assert_near(w.swarm.status_time(slot, MobSwarm.STUN), w.book.canonical("arrow_bomb", int(st.level), "time"), 0.001,
					"stunned for the level's `time`")
		counts.append(stunned)
		var boss := _mob(w, -80, true)
		for hit in 30:
			w.hit_mob(boss, st, -1)
		assert_eq(w.swarm.status_time(boss, MobSwarm.STUN), 0.0, "bosses resist")
	assert_true(counts[1] > counts[0], "rank 8 (60%%) stuns more often than rank 1: %s" % [counts])
	assert_true(counts[0] > 18 and counts[0] < 66, "rank 1 near its level's prop: %s of 120" % counts[0])
	assert_true(counts[1] > 42 and counts[1] < 96, "rank 8 near its level's prop: %s of 120" % counts[1])


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

## skill -> [rare, epic, unique] as [[id, [stat, op, value]...]]; Legendary is the Unique's id and effects plus damage x1.2.
const BONUSES := {
	"arrow_blow": [["bow_mastery", ["damage", "mul", 1.2]], ["booster", ["cooldown", "mul", 0.88]], ["final_attack", ["count", "add", 1.0]]],
	"bow_double_shot": [["bow_mastery", ["damage", "mul", 1.2]], ["eye", ["range", "mul", 1.25]], ["final_attack", ["count", "add", 1.0]]],
	"arrow_bomb": [["bow_mastery", ["damage", "mul", 1.2]], ["bigger_bomb", ["area", "mul", 1.2]], ["wide_blast", ["blast_targets", "add", 2.0]]],
	"strafe": [["bow_mastery", ["damage", "mul", 1.2]], ["booster", ["cooldown", "mul", 0.88]], ["final_attack", ["count", "add", 2.0]]],
}
const NAMES := {"bow_mastery": "Bow Mastery", "booster": "Bow Booster", "final_attack": "Final Attack", "eye": "Eye of Amazon",
	"bigger_bomb": "Bigger Bomb", "wide_blast": "Wide Blast"}


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
			assert_eq(String(entry.text), NAMES[expected[t][0]], "%s %s names the lineage passive" % [key, tier])
			assert_eq(entry.effects.size(), 1)
			var effect: Dictionary = entry.effects[0]
			var want: Array = expected[t][1]
			assert_eq([String(effect.stat), String(effect.op), float(effect.value)], want, "%s %s effect" % [key, tier])
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
		for tier: String in ["rare", "epic", "unique", "legendary"]:
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



# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

## skill -> [book, WZ id, WZ max level, the eight mapped levels (ceil(rank x max / 8))]
const MAPPED := {
	"arrow_blow": ["300", 3001004, 20, [3, 5, 8, 10, 13, 15, 18, 20]],
	"bow_double_shot": ["300", 3001005, 20, [3, 5, 8, 10, 13, 15, 18, 20]],
	"arrow_bomb": ["310", 3101005, 30, [4, 8, 12, 15, 19, 23, 27, 30]],
	"strafe": ["311", 3111006, 30, [4, 8, 12, 15, 19, 23, 27, 30]],
}


func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var imgs := {}
	for book: String in ["300", "310", "311"]:
		var img := lib.img("Skill.wz/%s.img" % book)
		assert_true(img != null, "Skill.wz/%s.img is in the cache" % book)
		if img == null:
			lib.free()
			return
		imgs[book] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var lo := Loadout.new(book)
	lo.weapon_family = "bow"
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
			match key:
				"arrow_blow":
					assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
					assert_eq(st.count, 1, label)
				"bow_double_shot":
					assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
					assert_eq(st.count, int(level.bulletCount), label)
					assert_eq(st.count, 2, label)
				"strafe":
					assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
					assert_eq(st.count, int(level.bulletCount), label)
					assert_eq(st.count, 4, label)
				"arrow_bomb":
					assert_near(st.damage_pct, float(level.x) / 100.0, 0.000001, label)
					assert_eq(st.blast_targets, int(level.mobCount), label)
					assert_eq(st.blast_targets, 6, label)
					var lt: Array = level.lt["$v"]
					var rb: Array = level.rb["$v"]
					assert_eq(st.box, Rect2(float(lt[0]), float(lt[1]), float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])), label)
					assert_eq(book.canonical(key, lv, "prop"), float(level.prop), label)
					assert_eq(book.canonical(key, lv, "time"), float(level.time), label)
	# The spec's worked rank values (rank 1 / 4 / 8), as literals.
	for expectation: Array in [["arrow_blow", 1.96, 2.20, 2.60], ["bow_double_shot", 0.96, 1.10, 1.30], ["strafe", 0.74, 0.85, 1.00]]:
		for i in 3:
			assert_near(lo.stats(expectation[0], [1, 4, 8][i]).damage_pct, expectation[i + 1], 0.000001, "%s" % expectation[0])
	for i in 3:
		var st := lo.stats("arrow_bomb", [1, 4, 8][i])
		assert_near(st.damage_pct, [0.78, 1.00, 1.30][i], 0.000001)
		assert_eq(book.canonical("arrow_bomb", int(st.level), "prop"), [34.0, 45.0, 60.0][i])
		assert_eq(book.canonical("arrow_bomb", int(st.level), "time"), [2.0, 4.0, 6.0][i])
	# Art and sounds resolve (Strafe's own hit/0 has three frames; the three sounds are the JSON nodes').
	for key: String in MAPPED:
		for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
			assert_true(lib.frame(book.wz_path(key) + "/" + suffix) != null, "%s %s" % [key, suffix])
		var hit := book.visual(key, "hit", 1, 1)
		assert_false(lib.anim(hit).is_empty(), "%s hit art %s" % [key, hit])
		for sound: String in book.def(key).sounds.values():
			if sound != "":
				assert_true(lib.sound(sound) != null, "%s sound %s" % [key, sound])
	assert_eq(lib.anim("Skill.wz/311.img/skill/3111006/hit/0").frame_count(), 3, "Strafe's own hit has three frames")
	assert_true(lib.anim(String(book.def("arrow_bomb").ball)).frame_count() > 0)
	assert_eq(Array(lib.missing), [])
	lib.free()
