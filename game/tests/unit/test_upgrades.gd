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
	for id: String in ["three_snails_count", "three_snails_cooldown", "three_snails_pierce", "three_snails_rank",
			"three_snails_speed", "max_hp", "nimble_feet", "recovery", "improved_max_mp", "improved_mp_recovery",
			"magnet"]:
		assert_has(el, id, "Beginner card")
	for id: String in JOB_SKILL_CARDS:
		assert_false(id in el, "%s never before the job" % id)
	for id: String in ["energy_bolt_count", "magic_claw_targets", "energy_bolt_rank"]:
		assert_false(id in el, "%s: no mods for a skill not owned" % id)
	for id: String in ["elixir", "power_elixir", "white_potion"]:
		assert_false(id in el, "fillers are not in the normal pool")


func test_magician_eligibility_and_mods_after_owning() -> void:
	var w := RF.quiet_world()
	w.change_job(200)
	var el := w.upgrades.eligible(w)
	for id: String in ["energy_bolt_new", "magic_claw_new", "magic_guard_new", "magic_armor_new"]:
		assert_has(el, id, "Magician skill card")
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
	w.upgrades.apply("three_snails_rank", w)
	w.upgrades.apply("three_snails_rank", w)
	assert_false("three_snails_rank" in w.upgrades.eligible(w), "Three Snails is at its max rank 3")
	assert_eq(w.loadout.rank("three_snails"), 3)


func test_slot_limit_blocks_new_skills() -> void:
	var w := RF.quiet_world()
	w.change_job(200)
	w.book.slots["active"] = 1
	var el := w.upgrades.eligible(w)
	assert_false("energy_bolt_new" in el, "one active slot, Three Snails holds it")
	assert_false("magic_claw_new" in el)
	assert_has(el, "magic_guard_new", "passive slots are separate")


func test_draws_are_distinct_seeded_and_weighted() -> void:
	var w := RF.quiet_world()
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
	assert_near(w.hp_regen, 1.0, 1e-6)
	var mp_regen0 := w.mp_regen
	w.upgrades.apply("improved_mp_recovery", w)
	assert_near(w.mp_regen, mp_regen0 + 1.0, 1e-6)
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
