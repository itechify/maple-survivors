extends TestCase
## Shadower's dagger fillers (spec #425, ticket SH6 #431): Double Stab, Steal and Savage Blow ported from `skills/thief.json` into
## the `shadower` line on the default rank tables, their rarity bonuses (the first two Venomous Stab grants) and the deletion of
## their legacy cards. Fixed 1/60 s ticks, seeded RNG, a Razor in hand. The behaviour tests run on synthetic Skill.wz levels
## shaped like the originals; the real-cache test at the end calls require_cache() and SKIPS without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## The creation weapon of the job (v83 Item.wz 1332005, PAD 20), with the survivor test afterimage a weapon_reach cast needs.
const RAZOR := 1332005
const STAB := "double_stab"
const STEAL := "steal"
const SAVAGE := "savage_blow"
const KEYS := [STAB, STEAL, SAVAGE]
const LEVELS_20 := [3, 5, 8, 10, 13, 15, 18, 20]
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
## Savage Blow, ranks 1..8 (levels 4 / 8 / 12 / 15 / 19 / 23 / 27 / 30): the node's lines and per-line percent (tier A).
const SAVAGE_LINES := [4, 4, 5, 5, 5, 6, 6, 6]
const SAVAGE_PCT := [52, 68, 62, 68, 76, 73, 77, 80]
## key -> [[id, stat, op, value] of Rare, Epic, Unique] (the spec's table; Legendary = Unique + damage x1.2).
const RARITY := {
	STAB: [["dagger_mastery", "damage", "mul", 1.2], ["venomous_stab", "status", "grant", 0.0], ["triple_stab", "attack_count", "add", 1.0]],
	STEAL: [["dagger_mastery", "damage", "mul", 1.2], ["dagger_booster", "cooldown", "mul", 0.88], ["pickpocket", "count", "add", 2.0]],
	SAVAGE: [["dagger_mastery", "damage", "mul", 1.2], ["venomous_stab", "status", "grant", 0.0], ["savage_flurry", "attack_count", "add", 1.0]],
}
const TEXTS := {
	STAB: ["Dagger Mastery", "Venomous Stab", "Triple Stab"],
	STEAL: ["Dagger Mastery", "Dagger Booster", "Pickpocket"],
	SAVAGE: ["Dagger Mastery", "Venomous Stab", "Savage Flurry"],
}


## Synthetic Skill.wz levels 1..30 of Savage Blow: the node's line counts (4 / 5 / 6 at levels 1 / 11 / 21) and, at the eight
## mapped levels, its per-line percent; the other levels are filler (the rank table never reads them).
func _savage_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var pct := 40.0 + lv
		if lv in LEVELS_30:
			pct = float(SAVAGE_PCT[LEVELS_30.find(lv)])
		levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 15.0, "damage": pct, "attackCount": 4.0 if lv <= 10 else 5.0 if lv <= 20 else 6.0}
	return levels


## A quiet round of a Shadower holding the Razor with `key` learned at `rank_value`; god mode, frozen sturdy mobs.
func _world(key: String, rank_value := 1, p_seed := 431) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["422"]["playable"] = true # in this test's data only: SH14 #439 ships the flip
	data.balance.player.hp = 500
	data.balance.regen.hp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({RAZOR: {"incPAD": 20, "attackSpeed": 4, "afterImage": "swordOS", "tuc": 7}}, true)
	setup.skill_imgs["420"].skill["4201005"].level = _savage_levels()
	setup["job"] = 422
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != RAZOR:
		w.wear_new_item(RAZOR)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
		mk.no_flinch = true
	w.player.facing = 1
	w.god = true
	w.loadout.ranks.clear() # not the start skill: only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Shadower" % key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


## A sturdy monster `dx` px in front of the player, in the melee reach.
func _mob(w: RunWorld, dx: float, hp := 100000000.0) -> int:
	var slot := RF.put_mob(w, 1110100, w.player.pos.x + dx, 190.0, 100000.0)
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


# --- the move ---------------------------------------------------------------------------------------------------------

func test_the_three_fillers_live_in_the_shadower_file_only_and_the_legacy_cards_are_gone() -> void:
	var shadower: Dictionary = DataRepo.load_json("res://data/survivor/skills/shadower.json").skills
	var thief: Dictionary = DataRepo.load_json("res://data/survivor/skills/thief.json").skills
	for key: String in KEYS:
		assert_true(shadower.has(key), key + " is in skills/shadower.json")
		assert_false(thief.has(key), key + " is no longer in skills/thief.json (a repeated key is a load error)")
	for key in ["nimble_body", "keen_eyes", "disorder", "dagger_mastery", "dagger_booster"]:
		assert_true(thief.has(key), key + " stays in skills/thief.json")
	# Dark Sight moved too, by SH11 #436 (a hidden Form in the Shadower file).
	assert_true(shadower.has("dark_sight") and not thief.has("dark_sight"), "dark_sight lives in skills/shadower.json only")
	var cards: Array = DataRepo.load_json("res://data/survivor/upgrades/thief.json").cards
	for card: Dictionary in cards:
		assert_false(String(card.get("skill", "")) in KEYS, "no legacy card is left: %s" % card.id)
	assert_false(cards.any(func(c: Dictionary) -> bool: return c.get("skill", "") == "dark_sight"), "Dark Sight's legacy cards went with SH11")
	var w := _world(STAB)
	for key: String in KEYS:
		for suffix in ["_targets", "_hits", "_damage", "_cooldown", "_reach", "_count", "_pierce", "_range"]:
			assert_true(w.upgrades.card(key + suffix).is_empty(), key + suffix + " is gone")
		# A playable Shadower's cards come from add_pool_skills: a new / rank card per pool skill, nothing else.
		for kind in ["_new", "_rank"]:
			assert_eq(String(w.upgrades.card(key + kind).get("desc", "")), "+1 rank", key + kind + " is the pool-generated card")
			assert_false(w.upgrades.card(key + kind).has("requires"), key + kind + " carries no jobs gate")
		assert_eq(w.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.get("skill", "") == key and c.kind == "skill_mod").size(),
			0, key + " has no standalone modifier card")


func test_the_three_skills_use_the_default_rank_tables_and_keep_their_cast_rules() -> void:
	var w := _world(STAB)
	for key: String in KEYS:
		var d := w.book.def(key)
		assert_false(d.has("ranks"), key + " drops its explicit rank list")
		assert_false(d.has("weapon_families"), key + ": weapons gate nothing")
		assert_eq(w.book.max_rank(key), 8, key)
		assert_eq(String(d.damage), "physical")
		assert_eq(String(d.slot), "active")
		assert_near(float(d.cooldown), 1.2, 0.000001, key + ": the 1.2 s cadence stays")
	assert_eq(w.book.max_level(STAB), 20)
	assert_eq(w.book.max_level(STEAL), 30)
	assert_eq(w.book.max_level(SAVAGE), 30)
	for r in 8:
		assert_eq(w.book.canonical_level(STAB, r + 1), LEVELS_20[r], "Double Stab rank %d" % (r + 1))
		assert_eq(w.book.canonical_level(STEAL, r + 1), LEVELS_30[r], "Steal rank %d" % (r + 1))
		assert_eq(w.book.canonical_level(SAVAGE, r + 1), LEVELS_30[r], "Savage Blow rank %d" % (r + 1))
	assert_eq(String(w.book.def(STAB).cast.rule), "weapon_reach")
	assert_eq(String(w.book.def(SAVAGE).cast.rule), "weapon_reach")
	assert_eq(String(w.book.def(STEAL).cast.rule), "range_around")
	assert_eq(int(w.book.def(STEAL).range), 100)
	assert_eq(String(w.book.def(STEAL).steal.chance_field), "prop", "the steal block is unchanged")
	assert_eq(String(w.book.def(STAB).action), "stabO1")
	assert_eq(String(w.book.def(STEAL).action), "swingO2")
	assert_eq(String(w.book.def(SAVAGE).action), "savage")


# --- the ports ---------------------------------------------------------------------------------------------------------

func test_double_stab_hits_one_monster_twice_at_every_rank() -> void:
	for rank_value in range(1, 9):
		var w := _world(STAB, rank_value)
		var st := w.loadout.stats(STAB)
		assert_eq(st.cast_rule, "weapon_reach")
		assert_eq(st.attack_count, 2, "rank %d: two lines" % rank_value)
		assert_eq(st.mob_count, 1, "rank %d: one base target" % rank_value)
		var a := _mob(w, 35.0)
		_mob(w, 45.0)
		w.runner.step(DT, w)
		var by_mob := _by_mob(_hits(w.drain_events(), STAB))
		assert_eq(by_mob.size(), 1, "rank %d: one monster is struck" % rank_value)
		assert_eq(by_mob.values(), [2], "rank %d: twice" % rank_value)
		assert_true(by_mob.has(a), "the nearer monster")


func test_steal_strikes_one_base_target_and_rolls_the_chance_by_rank() -> void:
	for rank_value in range(1, 9):
		var w := _world(STEAL, rank_value)
		var st := w.runner.stats_of(w, STEAL)
		assert_eq(st.mob_count, 1, "rank %d: one base target" % rank_value)
		assert_eq(st.cast_rule, "range_around")
		assert_near(w.book.canonical(STEAL, int(st.level), "prop"), 10.0 + int(st.level), 0.0001, "the fixture's prop at level %d" % int(st.level))
		_mob(w, 20.0)
		_mob(w, 60.0)
		w.runner.step(DT, w)
		var by_mob := _by_mob(_hits(w.drain_events(), STEAL))
		assert_eq(by_mob.size(), 1, "rank %d: one monster is struck" % rank_value)
		assert_eq(by_mob.values(), [1])
	# The chance is the node's prop at the rank's level, on stream 15 (the moved test of Steal's rules lives in test_bandit_attacks).
	var reference := RandomNumberGenerator.new()
	var w := _world(STEAL, 8)
	reference.state = w.thief_rng.state
	var m := _mob(w, 20.0)
	var st := w.runner.stats_of(w, STEAL)
	var expected := reference.randf() * 100.0 < 40.0
	w.hit_mob(m, st, -1)
	assert_eq(w.swarm.stolen[m], 1 if expected else 0)


func test_savage_blow_casts_four_five_or_six_lines_by_rank_with_the_nodes_percent() -> void:
	for r in range(1, 9):
		var w := _world(SAVAGE, r)
		var st := w.loadout.stats(SAVAGE)
		assert_eq(st.attack_count, SAVAGE_LINES[r - 1], "rank %d lines" % r)
		assert_near(st.damage_pct, SAVAGE_PCT[r - 1] / 100.0, 0.000001, "rank %d per-line percent (not interpolated)" % r)
		_mob(w, 40.0)
		w.runner.step(DT, w)
		assert_eq(_hits(w.drain_events(), SAVAGE).size(), SAVAGE_LINES[r - 1], "rank %d" % r)


# --- rarity bonuses ----------------------------------------------------------------------------------------------------

func test_the_rarity_tables_follow_the_spec() -> void:
	var w := _world(STAB)
	for key: String in RARITY:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		var rows: Array = RARITY[key]
		assert_eq(bonuses.keys().size(), 4, "%s: exactly the four tiers" % key)
		for t in 3:
			var tier: String = ["rare", "epic", "unique"][t]
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), String(rows[t][0]), "%s %s" % [key, tier])
			assert_eq(String(bonuses[tier][0].text), String(TEXTS[key][t]), "%s %s has the spec's card text" % [key, tier])
			assert_eq(bonuses[tier][0].effects.size(), 1)
			var effect: Dictionary = bonuses[tier][0].effects[0]
			assert_eq(String(effect.stat), String(rows[t][1]))
			assert_eq(String(effect.op), String(rows[t][2]))
			if String(effect.op) == "grant":
				assert_eq(String(effect.status), "venomous_stab", "the grant names the SH2 catalogue entry")
				assert_true(w.loadout.status_bonuses.has(effect.status))
			else:
				assert_near(float(effect.value), float(rows[t][3]), 0.0001)
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(String(legendary.id), String(rows[2][0]), "%s: Legendary shares the Unique's id (and its repeat counter)" % key)
		assert_eq(legendary.effects.size(), 2)
		assert_eq(String(legendary.effects[0].stat), String(rows[2][1]))
		assert_eq(String(legendary.effects[1].stat), "damage")
		assert_near(float(legendary.effects[1].value), 1.2, 0.0001)


func test_the_shipped_data_loads_without_an_error() -> void:
	var errors := PackedStringArray()
	DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "no load error: %s" % [errors])


## What one cast of `key` did after a Rare / Epic / Unique / Legendary rank card (`tier`, "normal" = the bare rank card).
func _probe(key: String, tier: String) -> Dictionary:
	var w := _world(key)
	w.upgrades.apply(key + "_rank", w, tier)
	var st := w.loadout.stats(key)
	var out := {"cooldown": float(st.cooldown), "grants": st.get("status_grants", []).size(), "count": int(st.mob_count),
		"attack_count": int(st.attack_count), "damage": w.loadout.skill_stat(key, "damage", 1.0)}
	# A crowd inside every reach, so a second line or a second target shows as more lines or more monsters.
	for k in 6:
		_mob(w, 20.0 + 10.0 * k)
	w.runner.step(DT, w)
	var hits := _hits(w.drain_events(), key)
	out["lines"] = hits.size()
	out["mobs"] = _by_mob(hits).size()
	var casts := 1
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
					assert_near(float(got.damage), 1.2, 0.0001, label)
				"cooldown":
					assert_near(float(got.cooldown) / float(base.cooldown), 0.88, 0.0001, label)
					assert_true(int(got.casts) > int(base.casts), label + ": casts more often")
				"attack_count":
					assert_eq(int(got.attack_count), int(base.attack_count) + 1, label)
					assert_eq(int(got.lines), int(base.lines) + int(base.mobs), label + ": one more line on every struck monster")
				"count":
					assert_eq(int(got.count), int(base.count) + 2, label)
					assert_eq(int(got.mobs), int(base.mobs) + 2, label + ": two more monsters per strike")
				"status":
					assert_eq(int(got.grants), 1, label)
					assert_eq(int(base.grants), 0, label)
			if t == 3:
				assert_true(float(got.damage) > float(_probe(key, "unique").damage), label + ": Legendary adds damage x1.2")


func test_the_epic_cards_grant_venomous_stab_and_nothing_else_changes() -> void:
	for key: String in [STAB, SAVAGE]:
		var w := _world(key)
		var mods := w.loadout.skill_mods.duplicate(true)
		var card := w.upgrades.choice_card(key + "_rank", w, "epic")
		assert_true(w.loadout.grants.is_empty(), "a preview awards nothing")
		assert_false(card.get("rarity_bonus", {}).is_empty())
		assert_true("venomous stab" in String(card.desc).to_lower(), "the card names the status: %s" % card.desc)
		w.upgrades.apply(key + "_rank", w, "epic")
		assert_eq(w.loadout.grants[key], ["venomous_stab"])
		assert_eq(w.loadout.skill_mods, mods, "a grant never alters skill_mods")
		assert_eq(w.loadout.rank(key), 2, "plus the one rank every card gives")
		var grant: Dictionary = w.loadout.stats(key).status_grants[0]
		assert_eq(grant.kind, "poison")
		assert_true(float(grant.chance) > 0.0 and float(grant.time) > 0.0 and int(grant.level) > 0, "chance, time and level resolve: %s" % [grant])
	# Steal gains no key.
	var other := _world(STEAL)
	assert_false(other.loadout.stats(STEAL).has("status_grants"))


func test_a_poisoned_monster_appears_in_a_seeded_run_with_the_epic_double_stab() -> void:
	var poisoned := {}
	for epic in [false, true]:
		var w := _world(STAB)
		if epic:
			w.upgrades.apply(STAB + "_rank", w, "epic")
		var m := _mob(w, 40.0)
		var seen := false
		for tick in 60 * 60:
			w.step(DT, MoveInput.new())
			w.drain_events()
			if w.swarm.status_time(m, MobSwarm.POISON) > 0.0:
				seen = true
				break
		poisoned[epic] = seen
	assert_false(poisoned[false], "without the card a Double Stab never poisons")
	assert_true(poisoned[true], "with the Epic card a monster is poisoned within a minute")


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for key: String in RARITY:
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			var w := _world(key)
			var card := w.upgrades.choice_card(key + "_rank", w, tier)
			assert_false(card.get("rarity_bonus", {}).is_empty(), "%s %s carries a bonus" % [key, tier])
			var before := var_to_bytes(w.loadout.stats(key))
			w.upgrades.apply(key + "_rank", w, tier)
			assert_eq(w.loadout.rank(key), 2, "%s %s: one rank, whatever the rarity" % [key, tier])
			assert_true(var_to_bytes(w.loadout.stats(key)) != before)
			var st := w.loadout.stats(key)
			match tier:
				"rare":
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2, 0.0001)
				"epic":
					if key == STEAL:
						assert_near(w.loadout.skill_stat(key, "cooldown", 1.0), 0.88, 0.0001)
					else:
						assert_eq(st.status_grants.size(), 1)
				"unique", "legendary":
					if key == STEAL:
						assert_eq(st.mob_count, 1 + 2)
					else:
						assert_eq(st.attack_count, (2 if key == STAB else 4) + 1)
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
		assert_near(m.loadout.skill_stat(key, "damage", 1.0), 1.2 * (1.0 + 0.2 * 0.8), 0.00001, "%s: the repeat is x0.8" % key)
		assert_eq(m.loadout.rank(key), 8)


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var roots := {}
	for book_id: String in ["400", "420"]:
		var img := lib.img("Skill.wz/%s.img" % book_id)
		assert_true(img != null, "Skill.wz/%s.img is in the cache" % book_id)
		if img == null:
			lib.free()
			return
		roots[book_id] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, roots)
	var lo := Loadout.new(book)
	lo.weapon_family = "dagger"
	var node_of := {STAB: roots["400"].skill["4001334"], STEAL: roots["420"].skill["4201004"], SAVAGE: roots["420"].skill["4201005"]}
	for key: String in node_of:
		var top := 20 if key == STAB else 30
		assert_eq(book.max_level(key), top, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank_value in range(1, 9):
			var lv: int = (LEVELS_20 if key == STAB else LEVELS_30)[rank_value - 1]
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			assert_eq(book.canonical_level(key, rank_value), lv, label)
			var level: Dictionary = node_of[key].level[str(lv)]
			var st := lo.stats(key, rank_value)
			assert_eq(int(st.level), lv, label)
			assert_near(st.damage_pct, float(level.damage) / 100.0, 0.000001, label)
			match key:
				STAB:
					assert_eq(st.attack_count, int(level.attackCount), label)
					assert_eq(st.attack_count, 2, label)
					assert_eq(st.mob_count, 1, label)
				STEAL:
					assert_eq(st.mob_count, 1, label)
					assert_eq(st.attack_count, 1, label)
					assert_eq(book.canonical(key, lv, "prop"), float(level.prop), label)
				SAVAGE:
					assert_eq(st.attack_count, int(level.attackCount), label)
					assert_eq(st.attack_count, SAVAGE_LINES[rank_value - 1], label)
					assert_near(st.damage_pct, SAVAGE_PCT[rank_value - 1] / 100.0, 0.000001, label + ": the node's per-line percent")
					assert_eq(st.mob_count, 1, label)
	# The spec's worked rank values (rank 1 / 4 / 8) as literals.
	for i in 3:
		var r: int = [1, 4, 8][i]
		assert_near(lo.stats(STAB, r).damage_pct, [1.02, 1.16, 1.40][i], 0.000001, "Double Stab rank %d" % r)
		assert_near(lo.stats(STEAL, r).damage_pct, [0.48, 0.70, 1.00][i], 0.000001, "Steal rank %d" % r)
		assert_eq(book.canonical(STEAL, book.canonical_level(STEAL, r), "prop"), [14.0, 25.0, 40.0][i], "Steal chance rank %d" % r)
		assert_near(lo.stats(SAVAGE, r).damage_pct, [0.52, 0.68, 0.80][i], 0.000001, "Savage Blow rank %d" % r)
		assert_eq(lo.stats(SAVAGE, r).attack_count, [4, 5, 6][i], "Savage Blow lines rank %d" % r)
	# Art, sounds and the dagger's stances resolve in the cache.
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
	assert_eq(Array(lib.missing), [])
	lib.free()
