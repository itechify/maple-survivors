extends TestCase
## The five Brawler skills ported into the `buccaneer` line (spec #412, ticket B4 #416, GAME_DESIGN 7.90): Flash Fist,
## Somersault Kick, Backspin Blow, Double Uppercut and Corkscrew Blow live in skills/buccaneer.json with no weapon gate, the
## default eight-rank table (WZ levels 3, 5, 8, 10, 13, 15, 18, 20), the new cooldowns and lineage-named rarity bonuses; the
## 15 legacy cards are gone. Synthetic WZ-shaped books (run_fixtures.gd) cast through RunWorld on a flat ground, seeded and
## fixed-tick; the original-table checks at the end use the private asset cache and SKIP without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const KEYS := ["flash_fist", "somersault_kick", "backspin_blow", "double_uppercut", "corkscrew_blow"]
const LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
const TIERS := ["rare", "epic", "unique", "legendary"]
const KNUCKLE := 1482000
const SWORD := 1302000
const WAND := 1372005
const IDS := {"flash_fist": 5001001, "somersault_kick": 5001002, "backspin_blow": 5101002, "double_uppercut": 5101003,
	"corkscrew_blow": 5101004}
const BOOKS := {"flash_fist": "500", "somersault_kick": "500", "backspin_blow": "510", "double_uppercut": "510",
	"corkscrew_blow": "510"}
## Tier C cooldowns of the port (spec BU-19), seconds.
const COOLDOWNS := {"flash_fist": 0.45, "somersault_kick": 1.0, "backspin_blow": 1.4, "double_uppercut": 1.0,
	"corkscrew_blow": 1.8}
## The spec's rarity table: tier -> [id, [[stat, op, value] ...]] (Legendary repeats the Unique's id and adds damage x1.2).
const BONUSES := {
	"flash_fist": {"rare": ["mastery", [["damage", "mul", 1.2]]], "epic": ["booster", [["cooldown", "mul", 0.88]]],
		"unique": ["flurry", [["attack_count", "add", 1.0]]],
		"legendary": ["flurry", [["attack_count", "add", 1.0], ["damage", "mul", 1.2]]]},
	"somersault_kick": {"rare": ["mastery", [["damage", "mul", 1.2]]], "epic": ["wide_kick", [["area", "mul", 1.2]]],
		"unique": ["whirl", [["count", "add", 2.0]]],
		"legendary": ["whirl", [["count", "add", 2.0], ["damage", "mul", 1.2]]]},
	"backspin_blow": {"rare": ["mastery", [["damage", "mul", 1.2]]], "epic": ["stun_mastery", [["crit", "add", 0.15]]],
		"unique": ["booster", [["cooldown", "mul", 0.8]]],
		"legendary": ["booster", [["cooldown", "mul", 0.8], ["damage", "mul", 1.2]]]},
	"double_uppercut": {"rare": ["mastery", [["damage", "mul", 1.2]]], "epic": ["stun_mastery", [["crit", "add", 0.15]]],
		"unique": ["third_fist", [["attack_count", "add", 1.0]]],
		"legendary": ["third_fist", [["attack_count", "add", 1.0], ["damage", "mul", 1.2]]]},
	"corkscrew_blow": {"rare": ["mastery", [["damage", "mul", 1.2]]], "epic": ["boring", [["count", "add", 2.0]]],
		"unique": ["booster", [["cooldown", "mul", 0.8]]],
		"legendary": ["booster", [["cooldown", "mul", 0.8], ["damage", "mul", 1.2]]]},
}
## Damage percent at ranks 1 / 4 / 8 (spec "Rank values": WZ levels 3 / 10 / 20) and the mob cap there.
const DAMAGE := {"flash_fist": [1.68, 2.10, 2.70], "somersault_kick": [1.22, 1.50, 1.90], "backspin_blow": [1.04, 1.60, 2.40],
	"double_uppercut": [1.20, 1.90, 2.90], "corkscrew_blow": [1.65, 2.70, 4.20]}
## The WZ reach -lt.x of Corkscrew Blow at the eight mapped levels 3/5/8/10/13/15/18/20 (also the charge distance): two levels
## per 10 px from 100 at level 1, 200 at level 20 (levels 17 and 18 are 180, 19 is 190).
const CORKSCREW_REACH := [110.0, 120.0, 130.0, 140.0, 160.0, 170.0, 180.0, 200.0]


func _data() -> Dictionary:
	return DataRepo.load_all()


func _defining_lines(key: String) -> Array:
	var out := []
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("skills", line)
		if FileAccess.file_exists(path) and DataRepo.load_json(path).get("skills", {}).has(key):
			out.append(line)
	return out


## A 512 round on a flat ground (y = 200 in the fixture), holding `weapon`, knowing only `key` at `rank`; mobs are tiny and
## still. Job 512 is made playable in the data copy only (B11 ships the flip).
func _world(key: String, rank := 1, weapon := KNUCKLE, level := 30) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 416, data))
	setup.equipment_info[KNUCKLE] = {"incPAD": 18, "attackSpeed": 5, "tuc": 7, "afterImage": "mace", "sfx": "mace"}
	var w := RunWorld.new(setup)
	w.set_job(512)
	if w.weapon_id() != weapon:
		w.wear_new_item(weapon)
	w.progression.level = level
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0.0
	RF.place_player(w, 400.0)
	w.player.facing = 1
	w.update_view()
	w.god = true
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "learn " + key)
	w.loadout.set_rank(key, rank)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float) -> int:
	return RF.put_mob(w, MOB, w.player.pos.x + dx, 190.0, 100000.0)


func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


# --- placement ----------------------------------------------------------------------------------------------------------

func test_the_five_skills_are_defined_in_the_buccaneer_line_only() -> void:
	var skills: Dictionary = _data().skills.skills
	for key: String in KEYS:
		assert_eq(_defining_lines(key), ["buccaneer"], "%s moved out of pirate.json" % key)
		assert_eq(int(skills[key].skill_id), IDS[key], key)
		assert_eq(String(skills[key].book), BOOKS[key], key)
		assert_eq(int(skills[key].job), int(BOOKS[key]), key)
		assert_eq(String(skills[key].slot), "active", key)
	var corsair: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "pirate")).skills
	for key in ["double_shot", "grenade", "recoil_shot", "blank_shot", "invisible_shot", "dash", "knuckler_mastery", "bullet_time"]:
		assert_true(corsair.has(key), "%s stays in pirate.json" % key)


func test_the_definitions_have_no_weapon_gate_no_explicit_ranks_and_the_new_cooldowns() -> void:
	var skills: Dictionary = _data().skills.skills
	for key: String in KEYS:
		var d: Dictionary = skills[key]
		assert_false(d.has("weapon_families"), key + " has no weapon gate")
		assert_false(d.has("ranks"), key + " uses the default eight-rank table")
		assert_near(float(d.cooldown), float(COOLDOWNS[key]), 1e-9, key + " cooldown")
		assert_true(String(d.get("_tier", d.get("_survivor", ""))).contains("Tier C"), key + " notes its tier C choices")
		assert_true(d.has("rarity_bonuses"), key)


func test_the_legacy_cards_of_the_five_skills_are_gone_and_corsair_cards_stay() -> void:
	var ids := {}
	for c: Dictionary in _data().upgrades.cards:
		ids[String(c.id)] = true
	for key: String in KEYS:
		for suffix in ["_new", "_rank", "_targets"]:
			assert_false(ids.has(key + suffix), key + suffix + " is deleted from upgrades/pirate.json")
	for id in ["dash_new", "dash_rank"]:
		assert_false(ids.has(id), id + " is deleted: B5 (#417) made Dash a mobility skill with no cards")
	var legacy := 0
	for id: String in ids:
		for key: String in KEYS:
			legacy += 1 if id.begins_with(key + "_") else 0
	assert_eq(legacy, 0, "no card id starts with a ported key")


func test_the_pool_generates_the_new_and_rank_cards_for_a_playable_512() -> void:
	var w := _world("somersault_kick")
	var eligible := Array(w.upgrades.eligible(w))
	assert_has(eligible, "somersault_kick_rank")
	for key in ["flash_fist", "backspin_blow", "double_uppercut", "corkscrew_blow"]:
		assert_has(eligible, key + "_new")
		assert_false(eligible.has(key + "_rank"), "no rank card before learning " + key)
	assert_false(eligible.has("somersault_kick_new"))
	for key: String in KEYS:
		assert_false(eligible.has(key + "_targets"), "the more-mobs card is gone")


# --- eight ranks ---------------------------------------------------------------------------------------------------------

func test_each_skill_has_eight_ranks_mapped_to_wz_levels_3_to_20() -> void:
	var w := _world("flash_fist")
	for key: String in KEYS:
		assert_eq(w.book.max_level(key), 20, key)
		assert_eq(w.book.max_rank(key), 8, key)
		for r in range(1, 9):
			assert_eq(w.book.canonical_level(key, r), LEVELS[r - 1], "%s rank %d" % [key, r])


func test_synthetic_rank_one_four_and_eight_damage_and_caps_match_the_spec() -> void:
	var w := _world("flash_fist")
	for key: String in KEYS:
		for i in 3:
			var r: int = [1, 4, 8][i]
			var st := w.loadout.stats(key, r)
			assert_near(st.damage_pct, DAMAGE[key][i], 1e-6, "%s damage at rank %d" % [key, r])
			assert_eq(st.damage_type, "physical")
		assert_eq(w.loadout.stats(key, 8).attack_count, 2 if key == "double_uppercut" else 1, key + " lines")
	assert_eq([1, 4, 8].map(func(r: int) -> int: return SkillRunner.strike_count(w.loadout.stats("somersault_kick", r))), [3, 4, 6])
	for key in ["backspin_blow", "corkscrew_blow"]:
		assert_eq(SkillRunner.strike_count(w.loadout.stats(key, 8)), 3, key)
	assert_eq(SkillRunner.strike_count(w.loadout.stats("flash_fist", 8)), 1)
	assert_eq(SkillRunner.strike_count(w.loadout.stats("double_uppercut", 8)), 1)


func test_double_uppercut_reads_its_string_typed_attack_count_and_stun_time_at_every_rank() -> void:
	var w := _world("double_uppercut")
	for r in range(1, 9):
		assert_eq(w.loadout.stats("double_uppercut", r).attack_count, 2, "attackCount '2' at rank %d" % r)
		assert_near(w.book.canonical("double_uppercut", w.book.canonical_level("double_uppercut", r), "time"), 1.0, 1e-9)


func test_corkscrew_charge_distance_is_the_wz_reach_of_the_mapped_level_at_all_eight_ranks() -> void:
	var w := _world("corkscrew_blow")
	for r in range(1, 9):
		var d: Dictionary = w.loadout.stats("corkscrew_blow", r).displacement
		assert_eq(String(d.direction), "toward")
		assert_eq(String(d.when), "during")
		assert_near(float(d.distance), CORKSCREW_REACH[r - 1], 1e-6, "charge at rank %d" % r)
		assert_near(-w.loadout.stats("corkscrew_blow", r).box.position.x, CORKSCREW_REACH[r - 1], 1e-6, "box reach at rank %d" % r)
		assert_near(float(d.distance), -float(w.book.level_node("corkscrew_blow", w.book.canonical_level("corkscrew_blow", r)).lt["$v"][0]), 1e-6)


func test_backspin_keeps_its_hundred_pixel_back_off_at_every_rank() -> void:
	var w := _world("backspin_blow")
	for r in range(1, 9):
		assert_eq(w.loadout.stats("backspin_blow", r).displacement, {"direction": "away", "when": "after", "distance": 100.0})
	assert_eq(w.loadout.stats("double_uppercut", 1).displacement, {}, "Double Uppercut stands still")


# --- the cast with any weapon ----------------------------------------------------------------------------------------------

func test_every_skill_casts_with_a_sword_a_wand_and_a_knuckle_in_hand() -> void:
	for key: String in KEYS:
		for weapon: int in [SWORD, WAND, KNUCKLE]:
			var w := _world(key, 1, weapon)
			assert_eq(w.weapon_id(), weapon)
			_mob(w, 50.0)
			assert_eq(_cast(w).filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1, "%s with weapon %d" % [key, weapon])


# --- the new cooldowns -------------------------------------------------------------------------------------------------------

func test_the_resolved_cooldown_is_the_new_cadence_and_flash_fist_casts_at_it() -> void:
	for key: String in KEYS:
		var w := _world(key, 8)
		assert_near(float(w.loadout.stats(key).cooldown), float(COOLDOWNS[key]), 1e-6, key + " resolved cooldown")
	var w := _world("flash_fist", 8)
	var slot := _mob(w, 40.0)
	var x0: float = w.swarm.x[slot]
	for t in int(9.0 / DT):
		w.step(DT, MoveInput.new())
		w.swarm.hp[slot] = w.swarm.max_hp[slot]
		w.swarm.x[slot] = x0 # knockback must not walk the mob out of the box between casts
	assert_true(w.runner.casts >= 18 and w.runner.casts <= 21, "0.45 s cadence: %d casts in 9 s (the old 0.9 s gave 10)" % w.runner.casts)


# --- the seeded behaviours the old tests pinned ---------------------------------------------------------------------------------

func test_backspin_stuns_one_second_slides_a_hundred_pixels_and_caps_at_three_mobs_at_every_rank() -> void:
	for r in [1, 8]:
		var w := _world("backspin_blow", r)
		var hit := [_mob(w, 50.0), _mob(w, 80.0), _mob(w, 120.0)]
		var fourth := _mob(w, 135.0)
		var events := _cast(w)
		assert_eq(_hits(events).map(func(e: Dictionary) -> int: return int(e.mob)), hit, "rank %d: the 3 nearest" % r)
		for s: int in hit:
			assert_near(w.swarm.status_time(s, MobSwarm.STUN), 1.0, 1e-6, "rank %d stun" % r)
		assert_near(w.swarm.status_time(fourth, MobSwarm.STUN), 0.0, 1e-6)
		assert_near(w.player.pos.x, 300.0, 1e-6, "100 px away from the mobs on the right")


func test_double_uppercut_strikes_one_mob_twice_and_stuns_one_second() -> void:
	for r in [1, 8]:
		var w := _world("double_uppercut", r)
		var first := _mob(w, 40.0)
		var second := _mob(w, 50.0)
		var events := _cast(w)
		assert_eq(_hits(events).map(func(e: Dictionary) -> int: return int(e.mob)), [first, first], "rank %d" % r)
		assert_near(w.swarm.status_time(first, MobSwarm.STUN), 1.0, 1e-6)
		assert_near(w.swarm.status_time(second, MobSwarm.STUN), 0.0, 1e-6)


func test_corkscrew_charges_the_mapped_distance_and_strikes_three_along_the_way() -> void:
	for r in range(1, 9):
		var w := _world("corkscrew_blow", r)
		var reach: float = CORKSCREW_REACH[r - 1]
		var target := _mob(w, reach - 10.0)
		_mob(w, reach - 20.0)
		_mob(w, reach - 30.0)
		_mob(w, reach - 40.0)
		var x0 := w.player.pos.x
		var events := _cast(w)
		assert_eq(_hits(events).size(), 3, "rank %d: the 3-mob cap" % r)
		assert_near(w.player.pos.x - x0, reach, 1e-6, "rank %d charge" % r)
		assert_near(w.swarm.status_time(target, MobSwarm.STUN), 0.0, 1e-6, "Corkscrew does not stun")


func test_flash_fist_hits_one_mob_in_front_and_nothing_behind() -> void:
	var w := _world("flash_fist")
	var front := _mob(w, 35.0)
	_mob(w, 45.0)
	_mob(w, -35.0)
	assert_eq(_hits(_cast(w)).map(func(e: Dictionary) -> int: return int(e.mob)), [front])
	var behind := _world("flash_fist")
	_mob(behind, -35.0)
	assert_true(_cast(behind).is_empty(), "no front target means no cast")


func test_somersault_kick_strikes_around_up_to_the_rank_cap() -> void:
	for pair: Array in [[1, 3], [4, 4], [8, 6]]:
		var w := _world("somersault_kick", pair[0])
		for dx in [-60.0, -50.0, -40.0, 30.0, 40.0, 50.0, 60.0]:
			_mob(w, dx)
		var hits := _hits(_cast(w))
		assert_eq(hits.size(), pair[1], "rank %d" % pair[0])
		assert_true(hits.any(func(e: Dictionary) -> bool: return e.pos.x < w.player.pos.x))
		assert_true(hits.any(func(e: Dictionary) -> bool: return e.pos.x > w.player.pos.x))


func test_char_level_art_follows_the_round_level_at_10_15_20_25() -> void:
	var w := _world("flash_fist")
	for key in ["flash_fist", "somersault_kick"]:
		var d: Dictionary = w.book.def(key)
		assert_eq(Array(d.char_level.thresholds), [10.0, 15.0, 20.0, 25.0], key)
		var picked := {}
		for lv in [1, 9, 10, 14, 15, 19, 20, 24, 25, 40]:
			picked[lv] = w.book.visual(key, "hit", 8, lv)
		var base := "Skill.wz/500.img/skill/%d/hit/0" % IDS[key]
		assert_eq(picked[1], base)
		assert_eq(picked[9], base)
		for pair: Array in [[10, 10], [14, 10], [15, 15], [19, 15], [20, 20], [24, 20], [25, 25], [40, 25]]:
			assert_eq(picked[pair[0]], "Skill.wz/500.img/skill/%d/CharLevel/%d/hit/0" % [IDS[key], pair[1]], "%s at Lv%d" % [key, pair[0]])
	var low := _world("flash_fist", 1, KNUCKLE, 9)
	var high := _world("flash_fist", 1, KNUCKLE, 25)
	assert_eq(low.loadout.stats("flash_fist").hit, "Skill.wz/500.img/skill/5001001/hit/0")
	assert_eq(high.loadout.stats("flash_fist").hit, "Skill.wz/500.img/skill/5001001/CharLevel/25/hit/0", "the round level selects the art")


# --- rarity bonuses ---------------------------------------------------------------------------------------------------------

func test_the_rarity_lists_are_the_specs_table() -> void:
	var skills: Dictionary = SkillTemplate.resolve(_data().skills.skills)
	for key: String in KEYS:
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for tier: String in TIERS:
			assert_eq((bonuses[tier] as Array).size(), 1, "%s %s: one bonus" % [key, tier])
			var b: Dictionary = bonuses[tier][0]
			var want: Array = BONUSES[key][tier]
			assert_eq(String(b.id), want[0], "%s %s id" % [key, tier])
			assert_false(String(b.text).is_empty(), "%s %s has a name" % [key, tier])
			assert_eq((b.effects as Array).size(), (want[1] as Array).size(), "%s %s effects" % [key, tier])
			for i in (want[1] as Array).size():
				assert_eq(String(b.effects[i].stat), want[1][i][0], "%s %s stat" % [key, tier])
				assert_eq(String(b.effects[i].op), want[1][i][1], "%s %s op" % [key, tier])
				assert_near(float(b.effects[i].value), float(want[1][i][2]), 1e-9, "%s %s value" % [key, tier])
		assert_eq(String(bonuses.legendary[0].id), String(bonuses.unique[0].id), key + ": Legendary shares the Unique's counter")


func test_a_rare_or_better_card_adds_one_rank_and_its_bonus() -> void:
	for key: String in KEYS:
		for tier: String in TIERS:
			var w := _world(key, 3)
			var preview := w.upgrades.choice_card(key + "_rank", w, tier)
			assert_false(preview.get("rarity_bonus", {}).is_empty(), "%s %s: the preview shows the bonus" % [key, tier])
			w.upgrades.apply(key + "_rank", w, tier)
			assert_eq(w.loadout.rank(key), 4, "%s %s: +1 rank" % [key, tier])
			for effect: Array in BONUSES[key][tier][1]:
				var stat: String = effect[0]
				var base := 1.0 if effect[1] == "mul" else 0.0
				assert_near(w.loadout.skill_stat(key, stat, base), float(effect[2]), 1e-6,
					"%s %s: %s resolved" % [key, tier, stat])


func test_a_new_skill_card_at_unique_takes_the_skill_with_the_bonus() -> void:
	var w := _world("flash_fist")
	w.upgrades.apply("backspin_blow_new", w, "unique")
	assert_true(w.loadout.has("backspin_blow"))
	assert_near(w.loadout.skill_stat("backspin_blow", "cooldown", 1.0), 0.8, 1e-6)


func test_mastery_repeats_shrink_and_share_the_uniques_counter() -> void:
	var w := _world("flash_fist", 8)
	w.upgrades.apply("flash_fist_rank", w, "unique")
	assert_near(w.loadout.skill_stat("flash_fist", "attack_count", 0.0), 1.0, 1e-9)
	var card := w.upgrades.choice_card("flash_fist_rank", w, "legendary")
	assert_eq(card.card_kind, "mastery")
	w.upgrades.apply(card.id, w, "legendary")
	assert_eq(w.loadout.rank("flash_fist"), 8, "Mastery does not rank past 8")
	assert_near(w.loadout.skill_stat("flash_fist", "attack_count", 0.0), 1.8, 1e-6, "the second Flurry counts x0.8")
	assert_near(w.loadout.skill_stat("flash_fist", "damage", 1.0), 1.16, 1e-6)
	assert_eq(int(w.loadout.card_ranks["bonus:flash_fist:flurry"]), 2, "Unique and Legendary share one counter")


# --- the original tables (private cache) ---------------------------------------------------------------------------------------

func test_real_cache_all_eight_ranks_read_the_mapped_wz_rows() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var imgs := {}
	for book in ["500", "510"]:
		var img := library.img("Skill.wz/%s.img" % book)
		assert_true(img != null, book + " book imported")
		if img == null:
			library.free()
			return
		imgs[book] = img.root
	var b := SkillBook.from_data(_data().skills, imgs)
	var lo := Loadout.new(b)
	for key: String in KEYS:
		assert_eq(b.rank_table(key).map(func(v: Variant) -> int: return int(v)), LEVELS, key)
		lo.add_skill(key)
		for rank in range(1, 9):
			var lv: int = LEVELS[rank - 1]
			assert_eq(b.canonical_level(key, rank), lv)
			var row: Dictionary = imgs[BOOKS[key]].skill[str(IDS[key])].level[str(lv)]
			var st := lo.stats(key, rank)
			assert_near(st.damage_pct, float(row.damage) / 100.0, 1e-9, "%s rank %d damage" % [key, rank])
			assert_eq(st.attack_count, int(row.get("attackCount", 1)), "%s rank %d attackCount" % [key, rank])
			assert_eq(st.mob_count, int(row.get("mobCount", 1)), "%s rank %d mobCount" % [key, rank])
			if key in ["backspin_blow", "double_uppercut"]:
				assert_near(b.canonical(key, lv, "time"), float(row.time), 1e-9, "%s stun time" % key)
				assert_eq(b.canonical(key, lv, "prop", -1.0), -1.0, key + " has no prop")
			if row.has("lt"):
				var lt: Array = row.lt["$v"]
				var rb: Array = row.rb["$v"]
				var box: Rect2 = st.box
				if key in ["backspin_blow", "somersault_kick"]:
					var half := maxf(absf(float(lt[0])), absf(float(rb[0])))
					assert_near(box.position.x, -half, 1e-6, "%s rank %d around box left" % [key, rank])
					assert_near(box.end.x, half, 1e-6, "%s rank %d around box right" % [key, rank])
				else:
					assert_eq(box, Rect2(float(lt[0]), float(lt[1]), float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])), "%s rank %d box" % [key, rank])
			if key == "corkscrew_blow":
				assert_near(float(st.displacement.distance), -float(row.lt["$v"][0]), 1e-6, "charge = -lt.x at rank %d" % rank)
				assert_near(float(st.displacement.distance), CORKSCREW_REACH[rank - 1], 1e-6)
		for i in 3:
			assert_near(lo.stats(key, [1, 4, 8][i]).damage_pct, DAMAGE[key][i], 1e-9, "%s spec literal" % key)
	assert_eq(strike_count(lo, "somersault_kick"), [3, 4, 6])
	for key: String in KEYS:
		var d := b.def(key)
		for field in ["hit", "effect"]:
			assert_false(library.anim(String(d[field])).is_empty(), String(d[field]))
		assert_true(library.sound(d.sounds.use) != null, key + " use sound")
		assert_true(library.node("Character.wz/00002000.img/" + String(d.action)) is Dictionary, key + " body action")
	for key in ["flash_fist", "somersault_kick"]:
		for cl in [10, 15, 20, 25]:
			for field in ["hit", "effect"]:
				var path := b.visual(key, field, 8, cl)
				assert_true(path.contains("CharLevel/%d/" % cl), path)
				assert_false(library.anim(path).is_empty(), path)
	assert_eq(Array(library.missing), [])
	library.free()


func strike_count(lo: Loadout, key: String) -> Array:
	return [1, 4, 8].map(func(r: int) -> int: return SkillRunner.strike_count(lo.stats(key, r)))
