extends TestCase
## The I/L Arch Mage's core bolts (spec #319, ticket I6 #325): Cold Beam, Thunder Bolt, Teleport (moved out of
## magician.json into the il_arch_mage line), Ice Strike and Thunder Spear. Seeded RNG, fixed 1/60 s ticks.
## Level tables are synthetic: the recorded v83 values at levels 1, 4, 15, 19 and 30, linear between them. The real-cache
## tests (require_cache(), SKIP without it) read Skill.wz itself.

const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const KEYS := ["cold_beam", "thunder_bolt", "ice_strike", "thunder_spear"]
## Rank 1..8 are these WZ levels (the default 30-level table, GAME_DESIGN 8).
const RANK_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const TIERS := ["rare", "epic", "unique", "legendary"]


# --- fixtures ---------------------------------------------------------------------------------------------------------


## The same round with only `key` learned, at `rank`, for a cast test.
func _alone(key: String, rank := 1) -> RunWorld:
	var w := IL.round_world()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_rank(key, rank)
	w.loadout.set_caster(100.0, 0.0, 30)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
	w.drain_events()
	return w


func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


func _hit_mobs(events: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in _hits(events):
		out[int(e.mob)] = true
	return out


func _mob_at(w: RunWorld, dx: float, dy := 0.0) -> int:
	return w.spawn_mob(int(w.kind_of_id[MOB]), w.player.pos + Vector2(dx, dy), w.player.fh, 100.0, false)


# --- the line ---------------------------------------------------------------------------------------------------------


func test_the_five_skills_live_in_the_il_line_and_not_in_magician_json() -> void:
	var il := IL.skill_file("il_arch_mage")
	var magician := IL.skill_file("magician")
	for key: String in KEYS + ["teleport_il"]:
		assert_true(il.has(key), "%s is in skills/il_arch_mage.json" % key)
		assert_false(magician.has(key), "%s left skills/magician.json (a key in two files is a load error)" % key)
	for key: String in ["energy_bolt", "magic_claw", "slow_il", "meditation_il"]:
		assert_true(magician.has(key), "%s stays in magician.json" % key)
	var skills: Dictionary = DataRepo.load_all().skills.skills
	assert_eq([int(skills.cold_beam.skill_id), int(skills.thunder_bolt.skill_id), int(skills.ice_strike.skill_id),
		int(skills.thunder_spear.skill_id), int(skills.teleport_il.skill_id)], [2201004, 2201005, 2211002, 2211003, 2201002])
	assert_eq([skills.cold_beam.book, skills.ice_strike.book, int(skills.ice_strike.job)], ["220", "221", 221])


func test_definitions_follow_the_pool_rules() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var want := {"cold_beam": 0.5, "thunder_bolt": 0.6, "ice_strike": 1.6, "thunder_spear": 0.8}
	for key: String in want:
		var d: Dictionary = skills[key]
		assert_eq(String(d.slot), "active", "%s: an explicit active slot" % key)
		assert_near(float(d.cooldown), want[key], 1e-9, "%s: first-pass cooldown (base x0.4)" % key)
		assert_false(d.has("ranks"), "%s: the default 30-level table" % key)
		assert_false(d.has("weapon_families"), key)
		assert_eq(String(d.damage), "magic", key)
	assert_eq(skills.cold_beam.get("cast", {}).get("rule", "nearest"), "nearest")
	assert_eq(skills.cold_beam.on_hit, {"status": "freeze", "duration_field": "time"}, "no chance field: every line attempts it")
	assert_eq(skills.cold_beam.action, "swingO1")
	assert_eq(skills.cold_beam.range, 300)
	assert_eq(skills.thunder_bolt.cast.rule, "box")
	assert_eq(skills.ice_strike.cast.rule, "box")
	assert_eq(int(skills.ice_strike.cast.get("min_targets", 1)), 1)
	assert_eq(skills.ice_strike.on_hit, {"status": "freeze", "duration_field": "time"})
	assert_eq(skills.ice_strike.action, "magic2")
	assert_eq(skills.thunder_spear.cast.rule, "nearest")
	assert_eq(skills.thunder_spear.kind, "instant")
	assert_eq(skills.thunder_spear.range, 400)
	assert_eq(int(skills.thunder_spear.count), 1)
	assert_eq(skills.thunder_spear.action, "magic1")
	assert_eq(skills.ice_strike.sounds.use, "Sound.wz/Skill.img/2211002/Use")
	assert_eq(skills.thunder_spear.sounds.use, "Sound.wz/Skill.img/2211003/Use")


func test_no_standalone_card_survives_for_the_four_pool_skills() -> void:
	for c: Dictionary in DataRepo.load_all().upgrades.cards:
		for prefix: String in ["cold_beam_", "thunder_bolt_", "ice_strike_", "thunder_spear_"]:
			assert_false(String(c.id).begins_with(prefix) and String(c.get("kind", "")) == "skill_mod",
				"%s: ported skills carry no standalone mod cards" % c.id)
	var w := IL.round_world()
	assert_eq(w.upgrades.card("cold_beam_new").get("kind"), "skill_new", "new and rank cards are generated from the pool")
	assert_eq(w.upgrades.card("thunder_spear_rank").get("kind"), "skill_rank")
	assert_true(w.upgrades.card("ice_strike_new").get("effects", []).is_empty())


# --- Cold Beam --------------------------------------------------------------------------------------------------------

func test_cold_beam_freezes_for_the_canonical_time_and_bosses_and_ice_immune_monsters_refuse() -> void:
	for rank: int in [1, 8]:
		var w := _alone("cold_beam", rank)
		var st := w.loadout.stats("cold_beam")
		assert_eq(st.level, RANK_LEVELS[rank - 1])
		assert_eq(st.kind, "instant")
		assert_eq(st.element, "i")
		assert_near(st.cooldown, 0.5, 1e-9)
		var plain := _mob_at(w, 100)
		var events := _cast(w)
		assert_eq(_hits(events).size(), 1, "one instant line on one target")
		assert_near(w.swarm.status_time(plain, MobSwarm.FREEZE), 1.0 if rank == 1 else 2.0, 1e-4, "freeze `time` of the level")
	var boss := _alone("cold_beam", 8)
	var b := _mob_at(boss, 100)
	boss.swarm.mob_kind(b).boss = true
	_cast(boss)
	assert_near(boss.swarm.status_time(b, MobSwarm.FREEZE), 0.0, 1e-9, "a boss refuses the freeze")
	assert_true(boss.swarm.hp[b] < boss.swarm.max_hp[b], "but takes the damage")
	var immune := _alone("cold_beam", 8)
	var m := _mob_at(immune, 100)
	immune.swarm.mob_kind(m).element_codes = {"I": "1"}
	_cast(immune)
	assert_near(immune.swarm.status_time(m, MobSwarm.FREEZE), 0.0, 1e-9, "an ice-immune monster refuses it")
	assert_true(immune.swarm.hp[m] < immune.swarm.max_hp[m])


func test_cold_beam_takes_count_more_targets_and_freezes_each() -> void:
	var w := _alone("cold_beam")
	w.loadout.add_skill_mod("cold_beam", "count", "add", 2.0)
	var mobs: Array[int] = []
	for dx: int in [40, 80, 120, 160, 250]:
		mobs.append(_mob_at(w, dx))
	var hit := _hit_mobs(_cast(w))
	assert_eq(hit.keys(), mobs.slice(0, 3), "the three nearest")
	for m: int in mobs.slice(0, 3):
		assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 1.0, 1e-4)
	assert_near(w.swarm.status_time(mobs[3], MobSwarm.FREEZE), 0.0, 1e-9)


func test_cold_beam_range_is_300_px() -> void:
	var w := _alone("cold_beam")
	_mob_at(w, 320)
	assert_eq(_hits(_cast(w)).size(), 0, "beyond the 300 px range nothing is cast")


# --- Thunder Bolt -----------------------------------------------------------------------------------------------------

func test_thunder_bolt_box_grows_at_level_19_and_admits_only_box_targets() -> void:
	var low := _alone("thunder_bolt", 4) # WZ level 15
	assert_true((low.loadout.stats("thunder_bolt").box as Rect2).is_equal_approx(Rect2(-150, -50, 300, 100)))
	var high := _alone("thunder_bolt", 5) # WZ level 19: the first with the wider box
	assert_eq(high.loadout.stats("thunder_bolt").level, 19)
	assert_true((high.loadout.stats("thunder_bolt").box as Rect2).is_equal_approx(Rect2(-170, -70, 340, 140)))
	_mob_at(low, 160)
	assert_eq(_hits(_cast(low)).size(), 0, "160 px is outside the level-15 box")
	_mob_at(high, 160)
	assert_eq(_hits(_cast(high)).size(), 1, "and inside the level-19 box")


func test_thunder_bolt_hits_at_most_six_monsters_and_count_adds_targets() -> void:
	for extra: int in [0, 2]:
		var w := _alone("thunder_bolt", 8)
		assert_eq(w.loadout.stats("thunder_bolt").mob_count, 6)
		w.loadout.add_skill_mod("thunder_bolt", "count", "add", float(extra))
		for i in 12:
			_mob_at(w, (i + 1) * 10 * (1 if i % 2 == 0 else -1))
		assert_eq(_hit_mobs(_cast(w)).size(), 6 + extra, "mobCount 6 + count %d" % extra)


# --- Ice Strike -------------------------------------------------------------------------------------------------------

func test_ice_strike_box_grows_with_the_rank() -> void:
	var boxes := [Rect2(-120, -90, 240, 180), Rect2(-150, -112, 300, 225), Rect2(-200, -150, 400, 300)]
	for i in 3:
		var rank: int = [1, 4, 8][i]
		var w := _alone("ice_strike", rank)
		assert_true((w.loadout.stats("ice_strike").box as Rect2).is_equal_approx(boxes[i]), "rank %d box" % rank)
		assert_eq(w.loadout.stats("ice_strike").cast_rule, "box")
		assert_near(w.loadout.stats("ice_strike").cooldown, 1.6, 1e-9)
	var narrow := _alone("ice_strike", 1)
	_mob_at(narrow, 130)
	assert_eq(_hits(_cast(narrow)).size(), 0, "130 px is outside the rank-1 half-width of 120")
	var wide := _alone("ice_strike", 8)
	_mob_at(wide, 130)
	assert_eq(_hits(_cast(wide)).size(), 1, "and inside rank 8's 200")


func test_ice_strike_freezes_on_every_hit_line_for_the_canonical_time_and_caps_at_six() -> void:
	for rank: int in [1, 8]:
		var w := _alone("ice_strike", rank)
		var mobs: Array[int] = []
		for i in 9:
			mobs.append(_mob_at(w, (i + 1) * 8 * (1 if i % 2 == 0 else -1)))
		var events := _cast(w)
		assert_eq(_hit_mobs(events).size(), 6, "mobCount 6 caps the cast")
		var frozen := 0
		for m: int in _hit_mobs(events):
			assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 1.0 if rank == 1 else 2.0, 1e-4)
			frozen += 1
		assert_eq(frozen, 6)
	var boss := _alone("ice_strike", 8)
	var b := _mob_at(boss, 50)
	boss.swarm.mob_kind(b).boss = true
	_cast(boss)
	assert_near(boss.swarm.status_time(b, MobSwarm.FREEZE), 0.0, 1e-9, "a boss takes the hit, not the freeze")
	assert_true(boss.swarm.hp[b] < boss.swarm.max_hp[b])


func test_ice_strike_attack_count_adds_a_freeze_attempt_per_line_without_stacking() -> void:
	var w := _alone("ice_strike", 1)
	w.loadout.add_skill_mod("ice_strike", "attack_count", "add", 1.0)
	var m := _mob_at(w, 50)
	var events := _cast(w)
	assert_eq(_hits(events).size(), 2, "two lines on one monster")
	assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 1.0, 1e-4, "reapplying refreshes, never stacks")


# --- Thunder Spear ----------------------------------------------------------------------------------------------------

func test_thunder_spear_hits_exactly_one_target_the_nearest() -> void:
	var w := _alone("thunder_spear", 8)
	var st := w.loadout.stats("thunder_spear")
	assert_eq([st.level, st.element, st.mob_count, st.count, st.range], [30, "l", 1, 1, 400.0])
	assert_near(st.cooldown, 0.8, 1e-9)
	var near := _mob_at(w, 120)
	_mob_at(w, 160)
	_mob_at(w, 200)
	_mob_at(w, -150)
	var hit := _hit_mobs(_cast(w))
	assert_eq(hit.keys(), [near], "the nearest alone, though four stand in range")


func test_thunder_spear_range_is_400_px_and_count_adds_targets() -> void:
	var w := _alone("thunder_spear")
	_mob_at(w, 420)
	assert_eq(_hits(_cast(w)).size(), 0, "beyond 400 px nothing is cast")
	var wide := _alone("thunder_spear")
	wide.loadout.add_skill_mod("thunder_spear", "count", "add", 1.0)
	_mob_at(wide, 100)
	_mob_at(wide, 200)
	_mob_at(wide, 300)
	assert_eq(_hit_mobs(_cast(wide)).size(), 2)


func test_thunder_spear_damage_follows_the_rank() -> void:
	var low := _alone("thunder_spear", 1).loadout.stats("thunder_spear")
	var high := _alone("thunder_spear", 8).loadout.stats("thunder_spear")
	assert_true(high.damage_max > low.damage_max * 1.5, "mad 100 -> 170")


# --- Teleport ---------------------------------------------------------------------------------------------------------

func test_teleport_il_is_the_mobility_skill_outside_both_slot_tracks() -> void:
	var data := IL.data()
	var skills: Dictionary = SkillBook.from_data(data.skills, {}).defs
	assert_eq(skills.teleport_il.slot, "mobility")
	assert_eq(skills.teleport_il.skill_key, "teleport")
	assert_eq(skills.teleport_il.cast.rule, "manual")
	assert_eq(skills.teleport_il.skill_id, 2201002)
	assert_eq(skills.teleport_il.sounds.use, "Sound.wz/Skill.img/2201002/Use")
	assert_eq(skills.teleport_il.teleport, skills.teleport_fp.teleport, "the same 0.3 s repeat and bot threat distance")
	assert_eq(skills.teleport_il.ranks, skills.teleport_fp.ranks, "the same 20 ranks")
	var w := IL.round_world()
	assert_true(w.loadout.has("teleport_il"), "learned at round start")
	assert_eq(w.loadout.rank("teleport_il"), 1)
	assert_false("teleport_il" in w.jobs.skill_pool(222), "not a pool entry")
	for c: Dictionary in w.upgrades.cards:
		assert_ne(String(c.get("skill", "")), "teleport_il", "%s: Teleport is never offered as a card" % c.id)
	assert_false("teleport_il_new" in w.upgrades.eligible(w) or "teleport_il_rank" in w.upgrades.eligible(w))
	assert_eq(w.loadout.slot_count("active"), 1, "Cold Beam alone occupies a slot; Teleport consumes none")


func test_teleport_il_blinks_exactly_like_the_fp_one() -> void:
	var landed := {}
	for job: int in [212, 222]:
		var data := IL.data()
		var setup := RF.setup("quiet", 60, data)
		setup.job = job
		setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
		var w := RunWorld.new(setup)
		w.player.place(Vector2(400, 0), w.fhm)
		w.loadout.set_rank(w.jobs.mobility_skill(job), 20)
		var input := MoveInput.new()
		input.press_skill("teleport")
		w.step(DT, input)
		landed[job] = w.player.pos
	assert_eq(landed[222], landed[212], "the same distance")
	assert_ne(landed[222], Vector2(400, 0))


func test_teleport_il_rank_follows_mobility_rank_levels() -> void:
	var w := IL.round_world()
	assert_eq(w.loadout.rank("teleport_il"), 1)
	var table: Dictionary = w.balance.mobility_rank_levels
	assert_eq(table["20"], 10, "the shared rule: rank N at character level 2N")
	for step in range(2, 41):
		w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		w.step(DT, MoveInput.new())
		while w.state == RunWorld.CHOOSING_UPGRADE:
			w.apply_choice(String(w.pending_cards[0].id))
		var level := w.progression.level
		assert_eq(w.loadout.rank("teleport_il"), clampi(level / 2, 1, 20), "level %d" % level)
	assert_true(w.progression.level >= 40, "the loop reached the cap level")
	assert_eq(w.loadout.rank("teleport_il"), 20)
	assert_false("teleport_il_rank" in w.upgrades.eligible(w))


# --- rarity: every entry changes the cast (see also test_rarity_bonus_effects) ------------------------------------------

const BONUSES := {
	"cold_beam": {"rare": ["amplify", "damage"], "epic": ["booster", "cooldown"], "unique": ["spread", "count"],
		"legendary": ["spread", "count"]},
	"thunder_bolt": {"rare": ["amplify", "damage"], "epic": ["storm", "area"], "unique": ["fork", "count"],
		"legendary": ["fork", "count"]},
	"ice_strike": {"rare": ["amplify", "damage"], "epic": ["storm", "area"], "unique": ["shatter", "attack_count"],
		"legendary": ["shatter", "attack_count"]},
	"thunder_spear": {"rare": ["amplify", "damage"], "epic": ["booster", "cooldown"], "unique": ["echo", "attack_count"],
		"legendary": ["echo", "attack_count"]},
}


func test_the_four_rarity_lists_name_the_spec_entries() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in BONUSES:
		for tier: String in TIERS:
			var entries: Array = skills[key].rarity_bonuses[tier]
			assert_eq(entries.size(), 1, "%s %s" % [key, tier])
			assert_eq(entries[0].id, BONUSES[key][tier][0], "%s %s id" % [key, tier])
			assert_eq(entries[0].effects[0].stat, BONUSES[key][tier][1], "%s %s stat" % [key, tier])
		var unique: Dictionary = skills[key].rarity_bonuses.unique[0]
		var legendary: Dictionary = skills[key].rarity_bonuses.legendary[0]
		assert_eq(legendary.id, unique.id, "%s: Legendary shares the Unique's counter" % key)
		assert_eq(legendary.effects.size(), 2)
		assert_eq(legendary.effects[0], unique.effects[0], "%s: Legendary = Unique plus damage" % key)
		assert_eq(legendary.effects[1], {"stat": "damage", "op": "mul", "value": 1.2})
	assert_eq(skills.thunder_bolt.rarity_bonuses.unique[0].effects[0].value, 2, "Forking Storm: +2 targets")
	assert_eq(skills.cold_beam.rarity_bonuses.unique[0].effects[0].value, 1)
	assert_eq(skills.cold_beam.rarity_bonuses.epic[0].effects[0].value, 0.88)
	assert_eq(skills.thunder_bolt.rarity_bonuses.epic[0].effects[0].value, 1.2)


func test_a_rare_plus_card_adds_one_rank_plus_its_bonus_and_legendary_shares_the_unique_counter() -> void:
	for key: String in KEYS:
		for tier: String in TIERS:
			var w := IL.round_world()
			var id := key + ("_rank" if w.loadout.has(key) else "_new")
			var offered := w.upgrades.choice_card(id, w, tier)
			assert_false(offered.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			assert_false(offered.skill_mod_changes.is_empty(), "%s %s previews the change" % [key, tier])
			w.upgrades.apply(id, w, tier)
			assert_true(w.loadout.has(key))
			assert_false(w.loadout.skill_mods.get(key, {}).is_empty(), "%s %s applied the bonus" % [key, tier])
		var w := IL.round_world()
		w.upgrades.apply(key + ("_rank" if w.loadout.has(key) else "_new"), w, "unique")
		w.upgrades.apply(key + "_rank", w, "legendary")
		var unique_id: String = BONUSES[key].unique[0]
		assert_eq(int(w.loadout.card_ranks["bonus:%s:%s" % [key, unique_id]]), 2, "%s: one counter for Unique and Legendary" % key)
		assert_eq(w.loadout.rank(key), 3 if key == "cold_beam" else 2, "%s: each card added exactly one rank" % key)


func test_mastery_repeats_shrink_by_0_8_on_every_new_skill() -> void:
	for key: String in KEYS:
		var w := IL.round_world()
		w.learn_skill(key)
		w.loadout.set_rank(key, 8)
		var mastery := w.upgrades.choice_card(key + "_rank", w, "rare")
		assert_eq(mastery.card_kind, "mastery", key)
		var first := w.loadout.skill_stat(key, "damage", 1.0)
		w.upgrades.apply(key + "_rank", w, "rare")
		var after_one := w.loadout.skill_stat(key, "damage", 1.0)
		w.upgrades.apply(key + "_rank", w, "rare")
		var after_two := w.loadout.skill_stat(key, "damage", 1.0)
		assert_near(after_one / first, 1.2, 1e-6, "%s: first Rare Mastery x1.2" % key)
		assert_near(after_two / after_one, 1.0 + 0.2 * 0.8, 1e-6, "%s: the repeat is x(1 + 0.2 x 0.8)" % key)
		assert_eq(w.loadout.rank(key), 8)


# --- real cache -------------------------------------------------------------------------------------------------------

func test_real_cache_the_eight_ranks_map_to_the_wz_levels_and_teleport_has_its_table() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	if lib.img("Skill.wz/221.img") == null:
		skip("the cache predates the I/L manifest fragment (no Skill.wz/221.img)")
		lib.free()
		return
	var imgs := {}
	for book: String in ["220", "221"]:
		imgs[book] = lib.img("Skill.wz/%s.img" % book).root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	for key: String in KEYS:
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank in range(1, 9):
			assert_eq(book.canonical_level(key, rank), RANK_LEVELS[rank - 1], "%s rank %d" % [key, rank])
	# Independent literals: the recorded WZ values at rank 1 / 4 / 8 (levels 4 / 15 / 30), I1-320.md.
	var mad := {"cold_beam": [22, 55, 100], "thunder_bolt": [8, 30, 60], "ice_strike": [38, 60, 90],
		"thunder_spear": [100, 135, 170]}
	for key: String in mad:
		for i in 3:
			var rank: int = [1, 4, 8][i]
			assert_eq(int(book.canonical(key, book.canonical_level(key, rank), "mad")), mad[key][i], "%s rank %d mad" % [key, rank])
	for rank: int in [1, 4, 8]:
		var cold_time := book.canonical("cold_beam", book.canonical_level("cold_beam", rank), "time")
		assert_false(book.level_node("cold_beam", book.canonical_level("cold_beam", rank)).has("prop"), "no canonical proc roll")
		assert_eq(int(cold_time), [1, 1, 2][[1, 4, 8].find(rank)])
		var node := book.level_node("ice_strike", book.canonical_level("ice_strike", rank))
		assert_eq(int(node.mobCount), 6)
		assert_eq(int(node.time), [1, 1, 2][[1, 4, 8].find(rank)])
		assert_eq(int(node.rb["$v"][0]), [120, 150, 200][[1, 4, 8].find(rank)], "Ice Strike half-width")
		assert_eq(int(node.rb["$v"][1]), [90, 113, 150][[1, 4, 8].find(rank)], "Ice Strike half-height")
		var bolt := book.level_node("thunder_bolt", book.canonical_level("thunder_bolt", rank))
		assert_eq(int(bolt.mobCount), 6)
	# The eight Thunder Bolt ranks: the wider box starts at rank 5 (level 19).
	for rank in range(1, 9):
		var bolt := book.level_node("thunder_bolt", book.canonical_level("thunder_bolt", rank))
		assert_eq(int(bolt.rb["$v"][0]), 150 if rank < 5 else 170, "Thunder Bolt rank %d half-width" % rank)
		assert_eq(int(bolt.rb["$v"][1]), 50 if rank < 5 else 70)
	# Teleport: 20 levels, one rank per level; range 130 -> 150.
	imgs["220"] = lib.img("Skill.wz/220.img").root
	var tele := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	assert_eq(tele.max_level("teleport_il"), 20)
	assert_eq(tele.max_rank("teleport_il"), 20)
	assert_eq(tele.canonical_level("teleport_il", 20), 20)
	assert_eq(tele.canonical("teleport_il", 1, "range"), 130.0)
	assert_eq(tele.canonical("teleport_il", 20, "range"), 150.0)
	for key: String in KEYS:
		assert_true(lib.frame(String(book.def(key).icon)) != null, "%s icon" % key)
		assert_true(lib.sound(String(book.def(key).sounds.use)) != null, "%s Use sound" % key)
		for field: String in ["hit", "effect"]:
			assert_true(lib.anim(book.visual(key, field, 30, 30)) != null, "%s %s art" % [key, field])
	assert_true(lib.sound(String(tele.def("teleport_il").sounds.use)) != null)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()


# --- text -------------------------------------------------------------------------------------------------------------

func test_skill_text_fills_every_placeholder_of_the_four_overrides() -> void:
	var w := IL.round_world()
	var text := SkillText.new(w.book, {})
	var want := {
		"cold_beam": "Basic attack 22, mastery 20%, up to 1 monster, freeze for 1 sec.",
		"thunder_bolt": "Basic attack 8, mastery 20%, up to 6 monsters",
		"ice_strike": "Basic attack 38, mastery 20%, up to 6 monsters, freeze for 1 sec.",
		"thunder_spear": "Basic attack 100, mastery 20%, up to 1 monster",
	}
	for key: String in want:
		w.learn_skill(key)
		assert_eq(text.level_line(key, 4, w.loadout.stats(key, 1)), want[key], key)
		assert_ne(text.desc(key), "", "%s has a description" % key)
