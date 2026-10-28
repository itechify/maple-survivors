extends TestCase
## UpgradePool (docs/GAME_DESIGN.md section 8): eligibility (cards of the character's job line, mods only for owned
## skills, maxed cards, uncapped learning), seeded weighted draws without duplicates, Elixir alternatives when short, and
## what applying a card does. The fresh character is a 212 holding Energy Bolt and Teleport (#284).

const RF := preload("res://tests/fixtures/run_fixtures.gd")



func _rng(s: int) -> RandomNumberGenerator:
	var r := RandomNumberGenerator.new()
	r.seed = s
	return r


## A world of job `job` that starts with no skill (no start skills).
func _bare(job := 212, p_seed := 7) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	var setup := RF.setup("quiet", p_seed, data)
	setup["job"] = job
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


func test_fresh_arch_mage_eligibility() -> void:
	var w := RF.quiet_world()
	var el := w.upgrades.eligible(w)
	for id: String in ["energy_bolt_rank", "magic_claw_new", "fire_arrow_new",
			"poison_breath_new"]:
		assert_has(el, id, "a card of the 212 line")
	assert_false("energy_bolt_new" in el, "the start skill is owned")
	for id: String in ["magic_claw_targets", "fire_arrow_count", "magic_armor_rank"]:
		assert_false(id in el, "%s: no mods or ranks for a skill not owned" % id)
	for id: String in ["cold_beam_new", "holy_arrow_new", "power_strike_new"]:
		assert_false(id in el, "%s is off the 212 line" % id)



func test_an_owned_beginner_skill_keeps_its_rank_and_casts_without_cards() -> void:
	var w := _bare(212, 38)
	w.learn_skill("three_snails")
	w.loadout.set_rank("three_snails", 2)
	for seed_value in range(1, 21):
		for c: Dictionary in w.upgrades.roll_choices(w, _rng(seed_value)):
			assert_ne(String(w.upgrades.card(c.id).get("skill", "")), "three_snails", "no Beginner cards: %s" % c.id)
	RF.put_mob(w, 2220000, 580)
	w.drain_events()
	w.step(1.0 / 60.0, MoveInput.new())
	var snails := w.drain_events().filter(func(e: Dictionary) -> bool:
		return e.type == "cast" and e.skill == "three_snails")
	assert_eq(snails.size(), 1, "the owned Beginner attack casts")
	if not snails.is_empty():
		assert_eq(int(snails[0].level), 2, "it casts at its canonical level")


func test_seeded_offers_never_bring_back_removed_cards() -> void:
	for job_id in [212, 200]:
		var w := RF.quiet_world(400.0, 38)
		w.set_job(job_id)
		w.progression.level = 25
		var seen := {}
		for seed_value in range(1, 61):
			for c: Dictionary in w.upgrades.roll_choices(w, _rng(seed_value)):
				seen[c.id] = true
				if job_id == 200:
					assert_false(c.id.begins_with("fire_arrow") or c.id.begins_with("poison_breath"),
						"a 200 never sees the 210 cards (%s)" % c.id)
		for id: String in ["magnet", "orange_potion", "white_potion", "mana_elixir"]:
			assert_false(seen.has(id), "%s is no longer offered to job %d" % [id, job_id])




func test_draws_are_distinct_seeded_and_weighted() -> void:
	var w := RF.quiet_world()
	# Plain weighted draws: the pity rule (its own test) would make a draw depend on the draws before it.
	pass # pity removed by #287
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
	# The more heavily weighted Magic Claw card (4) appears more often than Energy Bolt's piercing card (2).
	assert_true(int(counts.get("magic_claw_new", 0)) > int(counts.get("energy_bolt_pierce", 0)),
		"Magic Claw frequency > piercing frequency: %s" % [counts])


func test_exhausted_pool_and_one_card_draw_offer_one_elixir_alternative() -> void:
	var w := RF.quiet_world()
	var data := DataRepo.load_all()
	w.upgrades = UpgradePool.from_data({"cards": [], "fallback": data.upgrades.fallback})
	var cards := w.upgrades.roll_choices(w, _rng(5), 3)
	assert_eq(cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"])
	w.upgrades = UpgradePool.from_data({"cards": [{"id": "magic_claw_new", "kind": "skill_new", "skill": "magic_claw"}], "fallback": data.upgrades.fallback})
	var mixed := w.upgrades.roll_choices(w, _rng(9), 3)
	assert_eq(mixed.size(), 2)
	assert_eq(mixed[0].id, "magic_claw_new")
	assert_eq(mixed[1].id, "elixir")
	assert_false("elixir" in w.upgrades.eligible(w))


func test_picking_elixir_from_an_exhausted_levelup_fully_restores_hp() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	var w := RunWorld.new(RF.setup("quiet", 38, data))
	RF.place_player(w, 400)
	w.take_hit(10.0, false, "", w.player.pos - Vector2(10, 0))
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "an empty normal pool must still open the level-up window")
	assert_true(w.player_state.hp < w.player_state.max_hp)
	var stock := w.potions.snapshot()
	assert_true(w.apply_choice("elixir"))
	assert_eq(w.player_state.hp, w.player_state.max_hp, "Power Elixir restores all HP")
	assert_eq(w.potions.snapshot(), stock, "this card does not consume or replace carried potions")
	assert_eq(w.state, RunWorld.PLAYING)
	assert_false(w.progression.has_pending())


func test_applying_general_cards() -> void:
	var w := _bare()
	w.upgrades.apply("magic_armor_new", w)
	assert_eq(w.loadout.level("magic_armor"), 1, "the card learns a buff")
	assert_eq(w.player.speed_stat, 100, "learning gives no permanent speed increase")
	w.upgrades.apply("meditation_fp_new", w)
	assert_eq(w.loadout.level("meditation_fp"), 1, "the card learns a skill of the line's second job")
	w.drain_events()
	assert_eq(w.upgrades.apply("energy_bolt_new", w), 1)
	var learned := false
	for e: Dictionary in w.drain_events():
		if e.type == "skill_learned":
			learned = e.skill == "energy_bolt" and e.skill_id == 2001004
	assert_true(learned, "skill_new emits skill_learned")
	assert_eq(w.upgrades.apply("no_such_card", w), 0)


func test_choice_cards_carry_the_skill_level_change() -> void:
	var w := _bare()
	var c := w.upgrades.choice_card("energy_bolt_new", w)
	assert_eq([c.skill_level, c.skill_level_next], [0, 3])
	w.upgrades.apply("energy_bolt_new", w)
	c = w.upgrades.choice_card("energy_bolt_rank", w)
	assert_eq([c.skill_level, c.skill_level_next], [3, 5])
	for r in range(2, 9):
		assert_has(w.upgrades.eligible(w), "energy_bolt_rank")
		w.upgrades.apply("energy_bolt_rank", w)
		assert_eq(w.loadout.rank("energy_bolt"), r)
	assert_eq(w.loadout.level("energy_bolt"), 20)
	assert_has(w.upgrades.eligible(w), "energy_bolt_rank", "Mastery replaces capped ranks")


func test_rank_cards_preview_canonical_attack_and_mastery() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	w.loadout.add_skill("energy_bolt")
	# Synthetic WZ levels make the expected preview independent of survivor damage tuning.
	w.book.skill_node("energy_bolt")["level"]["3"] = {"mad": 20.0, "mastery": 1.0, "mpCon": 6.0}
	w.book.skill_node("energy_bolt")["level"]["5"] = {"mad": 22.0, "mastery": 2.0, "mpCon": 7.0}
	w.loadout.add_skill_mod("energy_bolt", "damage", "mul", 2.0)
	var c := w.upgrades.choice_card("energy_bolt_rank", w)
	assert_eq(c.get("skill_changes", {}), {
		"mad": {"before": 20, "after": 22},
		"mastery": {"before": 15, "after": 20},
	}, "rank preview uses canonical levels and mastery percent; no MP cost (#285)")
	assert_eq(w.upgrades.choice_card("energy_bolt_new", w).skill_changes, {}, "learning has no prior skill rank")
	assert_eq(w.upgrades.choice_card("elixir", w).skill_changes, {}, "the filler has no canonical skill values")



func test_loadout_clone_copies_every_field_and_stays_independent() -> void:
	var lo := RF.quiet_world().loadout
	lo.add_skill_mod("energy_bolt", "count", "add", 1.0)
	lo.add_player_mod("speed", "mul", 1.1)
	lo.card_ranks["energy_bolt_count"] = 2
	lo.set_caster(31.0, 12.0, 17)
	lo.crit_chance = 0.15
	lo.crit_mult = 1.8
	var c := lo.clone()
	for field: String in ["ranks", "order", "skill_mods", "player_mods", "card_ranks", "int_stat", "matk", "char_level",
			"crit_chance", "crit_mult", "version"]:
		assert_eq(c.get(field), lo.get(field), field)
	assert_true(c.book == lo.book, "the same skill book")
	assert_eq(c.stats("energy_bolt"), lo.stats("energy_bolt"), "resolves the same numbers")
	c.add_skill_mod("energy_bolt", "count", "add", 1.0)
	c.add_player_mod("speed", "add", 5.0)
	c.card_ranks["energy_bolt_count"] = 3
	c.order.append("magic_claw")
	assert_eq(lo.skill_mods.energy_bolt.count, Vector2(1.0, 1.0), "the original's skill mods are untouched")
	assert_eq(lo.player_mods.speed, Vector2(0.0, 1.1), "and its player mods")
	assert_eq(int(lo.card_ranks.energy_bolt_count), 2, "and its card ranks")
	assert_false("magic_claw" in lo.order, "and its learned order")


func test_real_stat_replacement_rank_previews_and_skill_caps() -> void:
	var w := RF.quiet_world(400, 41)
	w.upgrades.apply("magic_armor_new", w)
	var card := w.upgrades.choice_card("magic_armor_rank", w)
	assert_eq(card.kind, "skill_rank")
	var cap := w.book.max_rank("magic_armor")
	for pick in cap - 1:

		w.upgrades.apply("magic_armor_rank", w)
	assert_eq(w.loadout.rank("magic_armor"), cap)
	assert_false("magic_armor_rank" in w.upgrades.eligible(w))
	for seed in [1, 2, 2026]:
		for choice: Dictionary in w.upgrades.roll_choices(w, _rng(seed)):
			assert_false(choice.id in ["magic_armor_new", "magic_armor_rank"],
				"seeded offers respect the learned-skill cap")



func test_fixed_damage_rank_card_previews_only_fields_in_canonical_data() -> void:
	var w := RF.quiet_world()
	w.learn_skill("three_snails")
	# Three Snails ranks automatically in this design; a synthetic rank card exercises fixed-damage support.
	w.upgrades = UpgradePool.from_data({"cards": [{"id": "fixed_rank", "kind": "skill_rank", "skill": "three_snails",
		"effects": [{"stat": "rank", "value": 1}]}]})
	var c := w.upgrades.choice_card("fixed_rank", w)
	assert_eq(c.skill_changes, {"fixdamage": {"before": 10, "after": 25}},
		"canonical fixed damage; no MP cost (#285), no fabricated magic attack or mastery")


func test_unported_modifier_previews_keep_existing_mechanics() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 220)
	w.upgrades.apply("thunder_bolt_new", w)
	assert_eq(w.upgrades.choice_card("thunder_bolt_area", w).skill_mod_changes, {"area": {"before": 100, "after": 120}},
		"reach in percent of the canonical box")
	var pool := UpgradePool.from_data({"cards": [{"id": "storm_targets", "kind": "skill_mod", "skill": "thunder_bolt",
		"max_rank": 3, "effects": [{"stat": "count", "op": "add", "value": 2}]}]})
	assert_eq(pool.choice_card("storm_targets", w).skill_mod_changes, {"targets": {"before": 6, "after": 8}},
		"a box skill's targets are its canonical mobCount plus cards")
