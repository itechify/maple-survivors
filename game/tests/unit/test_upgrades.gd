extends TestCase
## UpgradePool (docs/GAME_DESIGN.md section 8): eligibility (job gates, mods only for owned skills, maxed cards,
## slots), seeded weighted draws without duplicates, fillers when short, and what applying a card does.

const RF := preload("res://tests/fixtures/run_fixtures.gd")

const JOB_SKILL_CARDS := ["energy_bolt_new", "magic_claw_new", "magic_guard_new", "magic_armor_new", "fire_arrow_new"]


func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


func test_beginner_eligibility() -> void:
	var w := RF.quiet_world()
	var el := w.upgrades.eligible(w)
	for id: String in ["three_snails_count", "three_snails_cooldown", "three_snails_pierce",
			"three_snails_speed", "max_hp", "nimble_feet", "recovery", "magnet"]:
		assert_has(el, id, "Beginner card")
	for id: String in ["improved_max_mp", "improved_mp_recovery"]:
		assert_false(id in el, "%s: a Magician skill (2000001 / 2000000), not for a Beginner" % id)
	for id: String in JOB_SKILL_CARDS:
		assert_false(id in el, "%s never before the job" % id)
	for id: String in ["energy_bolt_count", "magic_claw_targets", "energy_bolt_rank"]:
		assert_false(id in el, "%s: no mods for a skill not owned" % id)
	for id: String in ["elixir", "power_elixir", "white_potion"]:
		assert_false(id in el, "fillers are not in the normal pool")


func test_magician_eligibility_and_mods_after_owning() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	var el := w.upgrades.eligible(w)
	assert_has(el, "energy_bolt_new", "the first Magician skill")
	for id: String in ["improved_max_mp", "improved_mp_recovery"]:
		assert_has(el, id, "Magician MP card")
	# v83 Skill.wz req: Magic Claw needs Energy Bolt 1, Magic Armor needs Magic Guard 3 (rank 2 = level 5); Magic
	# Guard waits for Energy Bolt too (survivor rule: the first Magician skill is an attack).
	for id: String in ["magic_claw_new", "magic_guard_new", "magic_armor_new"]:
		assert_false(id in el, "%s needs Energy Bolt first" % id)
	w.upgrades.apply("energy_bolt_new", w)
	el = w.upgrades.eligible(w)
	assert_has(el, "magic_claw_new", "Magic Claw after Energy Bolt")
	assert_has(el, "magic_guard_new", "Magic Guard after Energy Bolt")
	assert_false("magic_armor_new" in el, "Magic Armor needs Magic Guard rank 2")
	w.upgrades.apply("magic_guard_new", w)
	assert_false("magic_armor_new" in w.upgrades.eligible(w), "Magic Guard rank 1 is not enough")
	w.upgrades.apply("magic_guard_rank", w)
	assert_has(w.upgrades.eligible(w), "magic_armor_new", "Magic Guard rank 2 (level 5) opens Magic Armor")
	assert_false("fire_arrow_new" in el, "Fire Arrow needs 210")
	assert_false("magic_claw_cooldown" in el, "Quick Claw only once Magic Claw is owned")
	w.upgrades.apply("magic_claw_new", w)
	assert_true(w.loadout.has("magic_claw"))
	el = w.upgrades.eligible(w)
	assert_false("magic_claw_new" in el, "learned: no second copy")
	assert_has(el, "magic_claw_cooldown")
	assert_has(el, "magic_claw_targets")
	assert_has(el, "magic_claw_rank")
	w.change_job(210)
	assert_has(w.upgrades.eligible(w), "fire_arrow_new", "a 210 descends from 200 and gets its own card")
	assert_has(w.upgrades.eligible(w), "magic_claw_rank", "Magician cards stay for descendants")


func test_maxed_cards_disappear() -> void:
	var w := RF.quiet_world()
	for i in 4:
		assert_has(w.upgrades.eligible(w), "three_snails_count")
		assert_eq(w.upgrades.apply("three_snails_count", w), i + 1, "new rank")
	assert_false("three_snails_count" in w.upgrades.eligible(w), "Additional Shell x4 is the max")
	assert_eq(w.loadout.stats("three_snails").count, 5)
	# Three Snails levels with the character (skills.json level_ranks), so it has no rank card to max out.
	assert_false("three_snails_rank" in w.upgrades.eligible(w), "no Stronger Snails card")


func test_slot_limit_blocks_new_skills() -> void:
	var w := RF.quiet_world()
	w.change_job(200)
	w.loadout.add_skill("energy_bolt")
	w.book.slots["active"] = 2
	var el := w.upgrades.eligible(w)
	assert_false("magic_claw_new" in el, "two active slots, Three Snails and Energy Bolt hold them")
	assert_has(el, "magic_guard_new", "passive slots are separate")


func test_draws_are_distinct_seeded_and_weighted() -> void:
	var w := RF.quiet_world()
	# Plain weighted draws: the pity rule (its own test) would make a draw depend on the draws before it.
	w.upgrades.pity_draws = 0
	var first: Array = []
	var counts := {}
	for d in 400:
		var cards := w.upgrades.roll_choices(w, _rng(1000 + d), 3)
		assert_eq(cards.size(), 3)
		var ids: Array = []
		for c: Dictionary in cards:
			assert_false(c.id in ids, "no duplicates in one draw")
			ids.append(c.id)
			counts[c.id] = int(counts.get(c.id, 0)) + 1
			assert_false(c.kind == "filler", "enough eligible cards: no filler")
		if d == 0:
			first = ids
	var again: Array = []
	for c: Dictionary in w.upgrades.roll_choices(w, _rng(1000), 3):
		again.append(c.id)
	assert_eq(again, first, "same seed, same draw")
	# Weight 3 cards come up more often than weight 2 ones.
	assert_true(int(counts.get("three_snails_count", 0)) > int(counts.get("three_snails_pierce", 0)),
		"weight 3 > weight 2: %s" % [counts])


func test_fillers_fill_a_short_draw() -> void:
	var w := RF.quiet_world()
	# Max out everything a Beginner can take.
	for c: Dictionary in w.upgrades.cards:
		if c.kind == "filler":
			continue
		var guard := 0
		while w.upgrades.is_eligible(c, w) and guard < 10:
			w.upgrades.apply(String(c.id), w)
			guard += 1
	assert_eq(w.upgrades.eligible(w).size(), 0, "nothing left")
	var cards := w.upgrades.roll_choices(w, _rng(5), 3)
	assert_eq(cards.size(), 3, "three fillers")
	var ids: Array = []
	for c: Dictionary in cards:
		assert_eq(c.kind, "filler")
		assert_false(c.id in ids, "distinct fillers")
		ids.append(c.id)
		assert_eq(c.max_rank, 0, "unlimited")
	# Exactly one real card left: it is drawn, fillers fill the rest.
	var w2 := RF.quiet_world()
	for c: Dictionary in w2.upgrades.cards:
		if c.kind == "filler" or c.id == "magnet":
			continue
		var guard := 0
		while w2.upgrades.is_eligible(c, w2) and guard < 10:
			w2.upgrades.apply(String(c.id), w2)
			guard += 1
	var mixed := w2.upgrades.roll_choices(w2, _rng(9), 3)
	assert_eq(mixed.size(), 3)
	var kinds: Array = []
	for c: Dictionary in mixed:
		kinds.append(c.id if c.kind != "filler" else "filler")
	assert_has(kinds, "magnet")
	assert_eq(kinds.count("filler"), 2)


func test_applying_general_cards() -> void:
	var w := RF.quiet_world()
	var hp0: int = w.player_state.max_hp
	w.upgrades.apply("max_hp", w)
	assert_eq(w.player_state.max_hp, roundi(hp0 * 1.1), "Max HP +10%")
	assert_eq(w.player_state.hp, w.player_state.max_hp, "the extra HP is granted")
	w.upgrades.apply("nimble_feet", w)
	assert_eq(w.player.speed_stat, 106, "speed +6")
	var m0 := w.magnet_r
	w.upgrades.apply("magnet", w)
	assert_near(w.magnet_r, m0 * 1.25, 1e-3)
	w.upgrades.apply("recovery", w)
	assert_near(w.hp_regen, 10.0, 1e-6, "interim Recovery adds HP per pulse")
	w.upgrades.apply("improved_mp_recovery", w)
	assert_eq(w.loadout.level("improved_mp_recovery"), 1, "the card learns the canonical passive")
	var mp0: int = w.player_state.max_mp
	w.upgrades.apply("improved_max_mp", w)
	assert_eq(w.player_state.max_mp, mp0 + 25)
	w.drain_events()
	assert_eq(w.upgrades.apply("energy_bolt_new", w), 1)
	var learned := false
	for e: Dictionary in w.drain_events():
		if e.type == "skill_learned":
			learned = e.skill == "energy_bolt" and e.skill_id == 2001004
	assert_true(learned, "skill_new emits skill_learned")
	assert_eq(w.upgrades.apply("no_such_card", w), 0)


func test_choice_cards_carry_the_skill_level_change() -> void:
	var w := RF.quiet_world()
	# A mod card names its skill and shows the skill's current level without changing it.
	var c := w.upgrades.choice_card("three_snails_count", w)
	assert_eq(c.skill_name, "Three Snails", "the skill's name")
	assert_eq(int(c.skill_level), 1, "Three Snails is level 1 now")
	w.loadout.set_rank("three_snails", 2)
	assert_eq(int(w.upgrades.choice_card("three_snails_count", w).skill_level_next), 0, "a mod keeps the level")
	assert_eq(int(w.upgrades.choice_card("three_snails_count", w).skill_level), 2, "the mod's skill level is shown")
	assert_eq(String(w.upgrades.choice_card("max_hp", w).skill_name), "", "no skill")
	RF.change_job_bare(w, 200)
	c = w.upgrades.choice_card("energy_bolt_new", w)
	assert_eq([int(c.skill_level), int(c.skill_level_next)], [0, 1], "learning Energy Bolt: level 1")
	w.upgrades.apply("energy_bolt_new", w)
	c = w.upgrades.choice_card("energy_bolt_rank", w)
	assert_eq([int(c.skill_level), int(c.skill_level_next)], [1, 5], "Energy Bolt rank 2 = canonical level 5")


func test_rank_cards_preview_canonical_attack_mastery_and_mp() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	w.loadout.add_skill("energy_bolt")
	# Synthetic WZ levels make the expected preview independent of survivor damage tuning.
	w.book.skill_node("energy_bolt")["level"]["1"] = {"mad": 20.0, "mastery": 1.0, "mpCon": 6.0}
	w.book.skill_node("energy_bolt")["level"]["5"] = {"mad": 28.0, "mastery": 3.0, "mpCon": 9.0}
	w.loadout.add_skill_mod("energy_bolt", "damage", "mul", 2.0)
	var c := w.upgrades.choice_card("energy_bolt_rank", w)
	assert_eq(c.get("skill_changes", {}), {
		"mad": {"before": 20, "after": 28},
		"mastery": {"before": 15, "after": 25},
		"mpCon": {"before": 6, "after": 9},
	}, "rank preview uses canonical levels, mastery percent, and unmodified MP cost")
	assert_eq(w.upgrades.choice_card("energy_bolt_new", w).skill_changes, {}, "learning has no prior skill rank")
	assert_eq(w.upgrades.choice_card("three_snails_count", w).skill_changes, {}, "modifiers have no canonical rank change")
	assert_eq(w.upgrades.choice_card("max_hp", w).skill_changes, {}, "stat cards have no canonical skill values")


func test_fixed_damage_rank_card_previews_only_fields_in_canonical_data() -> void:
	var w := RF.quiet_world()
	# Three Snails ranks automatically in this design; a synthetic rank card exercises fixed-damage support.
	w.upgrades = UpgradePool.from_data({"cards": [{"id": "fixed_rank", "kind": "skill_rank", "skill": "three_snails",
		"effects": [{"stat": "rank", "value": 1}]}]})
	var c := w.upgrades.choice_card("fixed_rank", w)
	assert_eq(c.skill_changes, {"mpCon": {"before": 3, "after": 5}, "fixdamage": {"before": 10, "after": 25}},
		"canonical MP and fixed damage; no fabricated magic attack or mastery")


func test_pity_offers_a_power_card_after_dry_draws() -> void:
	var w := RF.quiet_world()
	var cards: Array = []
	for id: String in ["a", "b", "c", "d", "e"]:
		cards.append({"id": id, "kind": "stat", "name": id, "max_rank": 0, "weight": 1, "effects": []})
	# A power card so rare that only the pity rule will offer it.
	cards.append({"id": "pow", "kind": "skill_mod", "skill": "three_snails", "power": true, "name": "Power",
		"max_rank": 0, "weight": 0.000001, "effects": []})
	w.upgrades = UpgradePool.from_data({"pity": {"draws": 2}, "cards": cards})
	assert_eq(w.upgrades.pity_draws, 2)
	var rng := _rng(5)
	for d in 2:
		var ids: Array = []
		for c: Dictionary in w.upgrades.roll_choices(w, rng, 3):
			ids.append(c.id)
		assert_false("pow" in ids, "draw %d: no power card by chance (%s)" % [d, ids])
	assert_eq(w.power_dry, 2, "two dry draws counted")
	var third := w.upgrades.roll_choices(w, rng, 3)
	assert_eq(String(third[0].id), "pow", "after two dry draws the power card comes first")
	assert_eq(w.power_dry, 0, "reset by a draw with a power card")
	# Without pity the rare card stays rare.
	var v := RF.quiet_world()
	v.upgrades = UpgradePool.from_data({"cards": cards})
	var rng2 := _rng(5)
	for d in 6:
		for c: Dictionary in v.upgrades.roll_choices(v, rng2, 3):
			assert_ne(String(c.id), "pow", "no pity: not offered")
	assert_eq(UpgradePool.is_power(w.upgrades.card("pow")), true)
	assert_eq(UpgradePool.is_power(w.upgrades.card("a")), false)
