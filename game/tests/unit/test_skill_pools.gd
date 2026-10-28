extends TestCase
## Survivor pool, rank and slot contracts (ADR 0006 #287).
const RF := preload("res://tests/fixtures/run_fixtures.gd")

func test_pool_ranks_read_mapped_wz_levels_and_allow_override() -> void:
	var data := DataRepo.load_all()
	var book := SkillBook.from_data(data.skills, RF.skill_imgs())
	assert_eq(book.max_rank("energy_bolt"), 8)
	var levels := []
	for r in range(1, 9):
		levels.append(book.canonical_level("energy_bolt", r))
	assert_eq(levels, [3, 5, 8, 10, 13, 15, 18, 20])
	data.skills.skills.energy_bolt.ranks = [1, 2, 3, 4, 5, 6, 7, 20]
	book = SkillBook.from_data(data.skills, RF.skill_imgs())
	assert_eq(book.canonical_level("energy_bolt", 1), 1)
	assert_eq(book.canonical("energy_bolt", book.canonical_level("energy_bolt", 8), "mad"), 55.0)

func test_starting_skill_and_mobility_use_only_one_active_slot() -> void:
	var w := RF.quiet_world()
	assert_eq(w.progression.level, 1)
	assert_eq(w.loadout.order, ["energy_bolt", "teleport_fp"])
	assert_eq(w.loadout.rank("energy_bolt"), 1)
	assert_eq(w.loadout.slot_count("active"), 1)
	assert_eq(w.loadout.slot_count("passive"), 0)
	assert_eq(w.loadout.slot_limit("active"), 6)
	assert_eq(w.loadout.slot_limit("passive"), 6)

func test_only_implemented_pool_skills_offer_one_rank_at_every_rarity() -> void:
	var w := RF.quiet_world()
	assert_eq(w.upgrades.eligible(w), ["energy_bolt_rank", "magic_claw_new", "fire_arrow_new", "poison_breath_new"])
	for tier in UpgradePool.TIERS:
		var c := w.upgrades.choice_card("energy_bolt_rank", w, tier)
		assert_eq(c.magnitude, 1)
		assert_eq(c.tier, tier)
		w.upgrades.apply("energy_bolt_rank", w, tier)
	assert_eq(w.loadout.rank("energy_bolt"), 6)

func test_six_slots_stop_new_actives_but_keep_owned_rank_cards() -> void:
	var data := RF.quiet_data()
	for i in range(3):
		var key := "probe%d" % i
		data.skills.skills[key] = {"skill_id": 9900000 + i, "kind": "instant", "ranks": [1,2,3,4,5,6,7,8]}
		data.jobs_survivor.jobs["212"].skill_pool.append(key)
	var w := RunWorld.new(RF.setup("quiet", 287, data))
	for key in ["magic_claw", "fire_arrow", "poison_breath", "probe0", "probe1"]:
		assert_true(w.learn_skill(key))
	assert_eq(w.loadout.slot_count("active"), 6)
	assert_false(w.learn_skill("probe2"))
	assert_false("probe2_new" in w.upgrades.eligible(w))
	assert_has(w.upgrades.eligible(w), "probe1_rank")
	assert_eq(w.upgrades.apply("probe2_new", w, "legendary"), 0)

func test_seeded_draw_weights_by_kind_and_distinct_offers() -> void:
	var w := RF.quiet_world()
	var rng := RandomNumberGenerator.new()
	rng.seed = 287
	var counts := {"energy_bolt_rank": 0, "magic_claw_new": 0, "fire_arrow_new": 0, "poison_breath_new": 0}
	for i in 12000:
		var offer := w.upgrades.roll_choices(w, rng, 1)
		counts[offer[0].id] += 1
	# Independent expected frequencies: weights 1.2:1:1:1. Within 2 percentage points.
	assert_true(absf(float(counts.energy_bolt_rank) / 12000.0 - 2.0/7.0) < 0.02)
	for key in ["magic_claw_new", "fire_arrow_new", "poison_breath_new"]:
		assert_true(absf(float(counts[key]) / 12000.0 - 5.0/21.0) < 0.02)
	for i in 100:
		var ids := {}
		for c in w.upgrades.roll_choices(w, rng):
			ids[c.id] = true
		assert_eq(ids.size(), 3)
