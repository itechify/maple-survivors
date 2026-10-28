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
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	var setup := RF.setup("quiet", p_seed, data)
	setup["job"] = job
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	return w


func test_fresh_arch_mage_eligibility() -> void:
	var w := RF.quiet_world()
	var el := w.upgrades.eligible(w)
	for id: String in ["energy_bolt_rank", "energy_bolt_count", "magic_claw_new", "improved_max_mp", "fire_arrow_new",
			"poison_breath_new"]:
		assert_has(el, id, "a card of the 212 line")
	assert_false("energy_bolt_new" in el, "the start skill is owned")
	for id: String in ["magic_claw_targets", "fire_arrow_count", "improved_max_mp_rank"]:
		assert_false(id in el, "%s: no mods or ranks for a skill not owned" % id)
	for id: String in ["cold_beam_new", "holy_arrow_new", "power_strike_new"]:
		assert_false(id in el, "%s is off the 212 line" % id)


func test_magician_eligibility_and_mods_after_owning() -> void:
	var w := _bare(200)
	var el := w.upgrades.eligible(w)
	assert_has(el, "energy_bolt_new", "the first Magician skill")
	for id: String in ["improved_max_mp", "improved_mp_recovery"]:
		assert_has(el, id, "Magician MP card")
	# tier C: #31 ignores canonical req and the old survivor prerequisite.
	for id: String in ["magic_claw_new", "magic_guard_new", "magic_armor_new"]:
		assert_has(el, id, "new job skills need no prerequisite")
	w.upgrades.apply("energy_bolt_new", w)
	el = w.upgrades.eligible(w)
	assert_false("fire_arrow_new" in el, "Fire Arrow needs 210")
	assert_false("magic_claw_cooldown" in el, "Quick Claw only once Magic Claw is owned")
	w.upgrades.apply("magic_claw_new", w)
	assert_true(w.loadout.has("magic_claw"))
	el = w.upgrades.eligible(w)
	assert_false("magic_claw_new" in el, "learned: no second copy")
	assert_has(el, "magic_claw_cooldown")
	assert_has(el, "magic_claw_targets")
	assert_has(el, "magic_claw_rank")
	RF.as_job(w, 210)
	assert_has(w.upgrades.eligible(w), "fire_arrow_new", "a 210 descends from 200 and gets its own card")
	assert_has(w.upgrades.eligible(w), "magic_claw_rank", "the 200 cards stay on a 210's line")


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


func test_power_pity_with_no_eligible_power_card_draws_ordinary_choices() -> void:
	var w := RF.quiet_world()
	# Exhaust every power card of the line, including #55's second attack and future additions.
	for card: Dictionary in w.upgrades.cards:
		if not UpgradePool.is_power(card):
			continue
		while w.upgrades.is_eligible(card, w):
			w.upgrades.apply(String(card.id), w, "legendary")
	w.power_dry = w.upgrades.pity_draws
	var cards := w.upgrades.roll_choices(w, _rng(38))
	assert_false(cards.is_empty(), "pity with no eligible power cards still draws ordinary choices")
	for c: Dictionary in cards:
		assert_false(UpgradePool.is_power(w.upgrades.card(c.id)), "pity cannot invent a power card")


func test_maxed_cards_disappear() -> void:
	var w := RF.quiet_world()
	for i in 3:
		assert_has(w.upgrades.eligible(w), "energy_bolt_count")
		assert_eq(w.upgrades.apply("energy_bolt_count", w), i + 1, "new rank")
	assert_false("energy_bolt_count" in w.upgrades.eligible(w), "+1 bolt x3 is the max")
	assert_eq(w.loadout.stats("energy_bolt").count, 4)


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
	# The more heavily weighted Magic Guard card (8) appears more often than Energy Bolt's piercing card (2).
	assert_true(int(counts.get("magic_guard_new", 0)) > int(counts.get("energy_bolt_pierce", 0)),
		"Magic Guard frequency > piercing frequency: %s" % [counts])


func test_exhausted_pool_and_one_card_draw_offer_one_elixir_alternative() -> void:
	var w := RF.quiet_world()
	# Max out everything a 212 can take (learning a skill opens its later cards, so two passes).
	for pass_i in 2:
		for c: Dictionary in w.upgrades.cards:
			var guard := 0
			while w.upgrades.is_eligible(c, w) and guard < 40:
				w.upgrades.apply(String(c.id), w)
				guard += 1
	assert_eq(w.upgrades.eligible(w).size(), 0, "nothing left")
	var cards := w.upgrades.roll_choices(w, _rng(5), 3)
	assert_eq(cards.map(func(c: Dictionary) -> String: return c.id), ["elixir"], "an exhausted pool still gives a choice")
	# Exactly one card left: offer it and one Elixir, without repeating identical healing cards.
	var w2 := RF.quiet_world()
	for pass_i in 2:
		for c: Dictionary in w2.upgrades.cards:
			if c.id == "meditation_fp_new":
				continue # left unlearned, so its rank card stays ineligible too
			var guard := 0
			while w2.upgrades.is_eligible(c, w2) and guard < 40:
				w2.upgrades.apply(String(c.id), w2)
				guard += 1
	var mixed := w2.upgrades.roll_choices(w2, _rng(9), 3)
	assert_eq(mixed.size(), 2)
	assert_eq(mixed[0].id, "meditation_fp_new")
	if mixed.size() == 2:
		assert_eq(mixed[1].id, "elixir")
	assert_false("elixir" in w2.upgrades.eligible(w2), "Elixir never enters the weighted pool")


func test_picking_elixir_from_an_exhausted_levelup_fully_restores_both_pools() -> void:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	# No level-up MP refill, so MP is still short when the window opens and the Elixir has both pools to restore.
	data.balance.level_up_refill = {"hp": 0.0, "mp": 0.0}
	var w := RunWorld.new(RF.setup("quiet", 38, data))
	RF.place_player(w, 400)
	w.take_hit(10.0, false, "", w.player.pos - Vector2(10, 0))
	assert_true(w.spend_mp(3))
	w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "an empty normal pool must still open the level-up window")
	assert_true(w.player_state.hp < w.player_state.max_hp)
	assert_true(w.player_state.mp < w.player_state.max_mp)
	var stock := w.potions.snapshot()
	assert_true(w.apply_choice("elixir"))
	assert_eq(w.player_state.hp, w.player_state.max_hp, "Power Elixir restores all HP")
	assert_eq(w.player_state.mp, w.player_state.max_mp, "Power Elixir restores all MP")
	assert_eq(w.potions.snapshot(), stock, "this card does not consume or replace carried potions")
	assert_eq(w.state, RunWorld.PLAYING)
	assert_false(w.progression.has_pending())


func test_applying_general_cards() -> void:
	var w := _bare()
	w.upgrades.apply("magic_guard_new", w)
	assert_eq(w.loadout.level("magic_guard"), 1, "the card learns a buff")
	assert_eq(w.player.speed_stat, 100, "learning gives no permanent speed increase")
	w.upgrades.apply("improved_mp_recovery", w)
	assert_eq(w.loadout.level("improved_mp_recovery"), 1, "the card learns the canonical passive")
	w.upgrades.apply("improved_max_mp", w)
	assert_eq(w.loadout.level("improved_max_mp"), 1, "the card learns the percentage passive")
	w.drain_events()
	assert_eq(w.upgrades.apply("energy_bolt_new", w), 1)
	var learned := false
	for e: Dictionary in w.drain_events():
		if e.type == "skill_learned":
			learned = e.skill == "energy_bolt" and e.skill_id == 2001004
	assert_true(learned, "skill_new emits skill_learned")
	assert_eq(w.upgrades.apply("no_such_card", w), 0)


func test_choice_cards_carry_the_skill_level_change() -> void:
	var start := RF.quiet_world()
	# A mod card names its skill and shows the skill's current level without changing it.
	var c := start.upgrades.choice_card("energy_bolt_count", start)
	assert_eq(c.skill_name, "Energy Bolt", "the skill's name")
	assert_eq(int(c.skill_level), 1, "Energy Bolt is level 1 now")
	start.loadout.set_rank("energy_bolt", 2)
	assert_eq(int(start.upgrades.choice_card("energy_bolt_count", start).skill_level_next), 0, "a mod keeps the level")
	assert_eq(int(start.upgrades.choice_card("energy_bolt_count", start).skill_level), 2, "the mod's skill level is shown")
	assert_eq(String(start.upgrades.choice_card("elixir", start).skill_name), "", "no skill")
	var w := _bare(200)
	c = w.upgrades.choice_card("energy_bolt_new", w)
	assert_eq([int(c.skill_level), int(c.skill_level_next)], [0, 1], "learning Energy Bolt: level 1")
	w.upgrades.apply("energy_bolt_new", w)
	c = w.upgrades.choice_card("energy_bolt_rank", w)
	assert_eq([int(c.skill_level), int(c.skill_level_next)], [1, 2], "one rank card is one canonical level")
	w.upgrades.apply("energy_bolt_rank", w)
	assert_eq(w.loadout.level("energy_bolt"), 2)
	for level in range(3, 21):
		assert_has(w.upgrades.eligible(w), "energy_bolt_rank", "rank card remains until level 20")
		w.upgrades.apply("energy_bolt_rank", w)
		assert_eq(w.loadout.level("energy_bolt"), level)
	assert_false("energy_bolt_rank" in w.upgrades.eligible(w), "no rank offer at canonical level 20")
	for seed in [1, 2, 2026]:
		for choice: Dictionary in w.upgrades.roll_choices(w, _rng(seed)):
			assert_ne(choice.id, "energy_bolt_rank", "seeded draws respect the canonical cap")


func test_rank_cards_preview_canonical_attack_mastery_and_mp() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	w.loadout.add_skill("energy_bolt")
	# Synthetic WZ levels make the expected preview independent of survivor damage tuning.
	w.book.skill_node("energy_bolt")["level"]["1"] = {"mad": 20.0, "mastery": 1.0, "mpCon": 6.0}
	w.book.skill_node("energy_bolt")["level"]["2"] = {"mad": 22.0, "mastery": 2.0, "mpCon": 7.0}
	w.loadout.add_skill_mod("energy_bolt", "damage", "mul", 2.0)
	var c := w.upgrades.choice_card("energy_bolt_rank", w)
	assert_eq(c.get("skill_changes", {}), {
		"mad": {"before": 20, "after": 22},
		"mastery": {"before": 15, "after": 20},
		"mpCon": {"before": 6, "after": 7},
	}, "rank preview uses canonical levels, mastery percent, and unmodified MP cost")
	assert_eq(w.upgrades.choice_card("energy_bolt_new", w).skill_changes, {}, "learning has no prior skill rank")
	assert_eq(w.upgrades.choice_card("energy_bolt_count", w).skill_changes, {}, "modifiers have no canonical rank change")
	assert_eq(w.upgrades.choice_card("elixir", w).skill_changes, {}, "the filler has no canonical skill values")


func test_mod_cards_preview_the_effective_stat_they_change() -> void:
	var w := RF.quiet_world()
	assert_eq(w.upgrades.choice_card("energy_bolt_count", w).skill_mod_changes, {"shots": {"before": 1, "after": 2}},
		"a projectile skill's count is its bolts")
	w.upgrades.apply("magic_claw_new", w)
	assert_eq(w.upgrades.choice_card("magic_claw_cooldown", w).skill_mod_changes,
		{"cooldown": {"before": 1.25, "after": 1.1}}, "1.25 s x0.88, to two decimals")
	w.upgrades.apply("poison_breath_new", w)
	w.upgrades.apply("poison_breath_pierce", w)
	var pierce0 := int(w.loadout.stats("poison_breath").pierce)
	assert_eq(w.upgrades.choice_card("poison_breath_pierce", w, "rare").skill_mod_changes,
		{"pierce": {"before": pierce0, "after": pierce0 + 2}}, "a Rare pick shows both of its steps on top of the one taken")
	assert_eq(w.upgrades.choice_card("elixir", w).skill_mod_changes, {}, "the filler changes no skill")
	assert_eq(w.upgrades.choice_card("fire_arrow_new", w).skill_mod_changes, {}, "learn cards have no modifier preview")
	assert_eq(w.upgrades.choice_card("magic_claw_targets", w).skill_mod_changes, {"targets": {"before": 1, "after": 2}},
		"a nearest instant skill's count is its targets")
	assert_eq(w.upgrades.choice_card("energy_bolt_damage", w, "rare").skill_mod_changes,
		{"damage": {"before": 100, "after": 144}}, "damage x1.2 twice, in percent")
	assert_eq(w.loadout.skill_mods.get("energy_bolt", {}), {}, "previewing changes nothing")
	RF.change_job_bare(w, 220)
	w.upgrades.apply("thunder_bolt_new", w)
	assert_eq(w.upgrades.choice_card("thunder_bolt_area", w).skill_mod_changes, {"area": {"before": 100, "after": 120}},
		"reach in percent of the canonical box")
	var pool := UpgradePool.from_data({"cards": [{"id": "storm_targets", "kind": "skill_mod", "skill": "thunder_bolt",
		"max_rank": 3, "effects": [{"stat": "count", "op": "add", "value": 2}]}]})
	assert_eq(pool.choice_card("storm_targets", w).skill_mod_changes, {"targets": {"before": 6, "after": 8}},
		"a box skill's targets are its canonical mobCount plus cards")


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
	w.upgrades.apply("improved_max_mp", w)
	var card := w.upgrades.choice_card("improved_max_mp_rank", w)
	assert_eq(card.skill_changes, {"max_mp_percent": {"before": 2, "after": 4}},
		"preview the survivor percentage, not canonical MP gained per level or Guard absorption")
	for pick in 9:
		assert_has(w.upgrades.eligible(w), "improved_max_mp_rank")
		w.upgrades.apply("improved_max_mp_rank", w)
	assert_eq(w.loadout.level("improved_max_mp"), 10)
	assert_eq(w.player_state.max_mp, 6, "base 5 with the +20% cap (no job grant since #284)")
	assert_false("improved_max_mp_rank" in w.upgrades.eligible(w))
	for seed in [1, 2, 2026]:
		for choice: Dictionary in w.upgrades.roll_choices(w, _rng(seed)):
			assert_false(choice.id in ["improved_max_mp", "improved_max_mp_rank"],
				"seeded offers respect the learned-skill cap")


func test_fire_arrow_rank_cards_cover_all_thirty_canonical_levels() -> void:
	var w := RF.quiet_world()
	w.upgrades.apply("fire_arrow_new", w)
	assert_eq(w.loadout.level("fire_arrow"), 1)
	for level in range(2, 31):
		assert_has(w.upgrades.eligible(w), "fire_arrow_rank")
		w.upgrades.apply("fire_arrow_rank", w)
		assert_eq(w.loadout.level("fire_arrow"), level)
	assert_false("fire_arrow_rank" in w.upgrades.eligible(w))


func test_fixed_damage_rank_card_previews_only_fields_in_canonical_data() -> void:
	var w := RF.quiet_world()
	w.learn_skill("three_snails")
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
	cards.append({"id": "pow", "kind": "skill_mod", "skill": "energy_bolt", "power": true, "name": "Power",
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
