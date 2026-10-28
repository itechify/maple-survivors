extends TestCase
## BotInput (game/scripts/sim/bot_input.gd), the autoplay bot of RunScene, the full-run tests and scripts/balance.sh:
## the sensible card choice (pick_card_for), the first-card policy, potion sips, sword duels, and climbing a ladder to EXP drops left on a
## platform above (synthetic map of run_fixtures.gd, no spawns).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _cards(w: RunWorld, ids: Array) -> Array:
	var out: Array = []
	for id: String in ids:
		out.append(w.upgrades.choice_card(id, w))
	return out


func test_pick_card_for_prefers_attack_skills() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	var cards := _cards(w, ["magic_armor_new", "recovery", "energy_bolt_new"])
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_new", "a new attack skill first")
	assert_eq(BotInput.pick_card(cards), "magic_armor_new", "the first-card policy takes the first")
	w.upgrades.apply("energy_bolt_new", w)
	assert_eq(BotInput.pick_card_for(w, _cards(w, ["energy_bolt_pierce", "recovery", "energy_bolt_count"])),
		"energy_bolt_count", "more bolts before pierce")
	assert_eq(BotInput.pick_card_for(w, _cards(w, ["three_snails_count", "energy_bolt_count"])), "energy_bolt_count",
		"the current job's skill before the Beginner's")
	assert_eq(BotInput.pick_card_for(w, _cards(w, ["three_snails_speed", "magic_armor_new"])), "magic_armor_new",
		"an owned passive skill before a Beginner utility skill")
	assert_eq(BotInput.pick_card_for(w, []), "", "nothing to pick")


func test_optional_card_scores_replace_the_base_without_job_bonus_and_missing_cards_keep_their_fallback() -> void:
	var w := RF.quiet_world()
	w.balance.erase("bot")
	RF.as_job(w, 200)
	var cards := _cards(w, ["magic_armor_new", "energy_bolt_rank"])
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "without overrides the existing offense preference remains")
	w.balance["bot"] = {"card_scores": {"magic_armor_new": 70.0}}
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "70 replaces the base score: no additional current-job bonus")
	w.balance.bot.card_scores.magic_armor_new = 90.0
	assert_eq(BotInput.pick_card_for(w, cards), "magic_armor_new", "survivor data can prioritize a useful defense card")
	w.learn_skill("magic_armor")
	cards = _cards(w, ["magic_armor_rank", "energy_bolt_rank"])
	w.balance.bot.card_scores.magic_armor_rank = 70.0
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "a rank override also receives no job bonus")
	w.balance.bot.card_scores.magic_armor_rank = 90.0
	assert_eq(BotInput.pick_card_for(w, cards), "magic_armor_rank")
	w.balance.bot.card_scores.erase("magic_armor_rank")
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "a missing individual card uses its original score")


func _magnitude(c: Dictionary) -> int:
	return int(c.get("magnitude", 1))


func test_the_same_card_at_a_higher_tier_scores_strictly_more_by_the_gain_step() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	w.balance.erase("bot")
	var step := BotInput.SCORE_GAIN_STEP
	var normal_new := w.upgrades.choice_card("energy_bolt_new", w, "normal")
	var epic_new := w.upgrades.choice_card("energy_bolt_new", w, "epic")
	assert_true(_magnitude(epic_new) > _magnitude(normal_new), "an Epic new skill starts at a higher rank")
	assert_eq(BotInput.card_score(w, normal_new), BotInput.SCORE_NEW_ATTACK, "Normal scores exactly the base")
	assert_eq(BotInput.card_score(w, epic_new), BotInput.SCORE_NEW_ATTACK + step * float(_magnitude(epic_new) - 1))
	w.upgrades.apply("energy_bolt_new", w)
	for id: String in ["energy_bolt_rank", "energy_bolt_count"]:
		var normal := w.upgrades.choice_card(id, w, "normal")
		var rare := w.upgrades.choice_card(id, w, "rare")
		assert_true(_magnitude(rare) > _magnitude(normal), id + ": a Rare offer grants more than a Normal one")
		var base := BotInput.card_score(w, normal)
		assert_eq(BotInput.card_score(w, rare), base + step * float(_magnitude(rare) - 1), id)
		assert_true(BotInput.card_score(w, rare) > base, id + ": strictly more")
	assert_eq(BotInput.card_score(w, w.upgrades.choice_card("energy_bolt_rank", w, "normal")),
		BotInput.SCORE_RANK_ATTACK + BotInput.SCORE_JOB_BONUS, "a Normal rank card keeps its old score")
	assert_eq(BotInput.card_score(w, w.upgrades.choice_card("energy_bolt_count", w, "normal")),
		BotInput.SCORE_MOD.count + BotInput.SCORE_JOB_BONUS, "a Normal stacking card keeps its old score")


func test_a_missing_or_non_positive_magnitude_counts_as_one_step() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	w.balance.erase("bot")
	var base := BotInput.card_score(w, {"id": "energy_bolt_new"})
	assert_eq(base, BotInput.SCORE_NEW_ATTACK)
	assert_eq(BotInput.card_score(w, {"id": "energy_bolt_new", "magnitude": 0}), base)
	assert_eq(BotInput.card_score(w, {"id": "energy_bolt_new", "magnitude": -3}), base)
	assert_eq(BotInput.card_score(w, {"id": "energy_bolt_new", "magnitude": 4}), base + 3.0 * BotInput.SCORE_GAIN_STEP)
	w.balance["bot"] = {"gain_step_score": 10.0}
	assert_eq(BotInput.card_score(w, {"id": "energy_bolt_new", "magnitude": 4}), base + 30.0, "survivor data sets the step")


func test_a_large_enough_gain_outranks_the_card_that_wins_at_normal_tier() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	w.balance.erase("bot")
	w.upgrades.apply("energy_bolt_new", w)
	var normal := [w.upgrades.choice_card("energy_bolt_count", w, "normal"),
		w.upgrades.choice_card("energy_bolt_rank", w, "normal")]
	assert_eq(BotInput.pick_card_for(w, normal), "energy_bolt_count", "more shots wins at Normal tier")
	var rare_rank := w.upgrades.choice_card("energy_bolt_rank", w, "rare")
	var big_rank := w.upgrades.choice_card("energy_bolt_rank", w, "unique")
	assert_true(_magnitude(big_rank) >= 4, "the Unique rank offer grants several ranks")
	assert_eq(BotInput.pick_card_for(w, [normal[0], rare_rank]), "energy_bolt_count", "+2 ranks is not yet enough")
	assert_eq(BotInput.pick_card_for(w, [normal[0], big_rank]), "energy_bolt_rank", "a Unique rank offer outweighs one more shot")
	assert_eq(BotInput.pick_card_for(w, [big_rank, normal[0]]), "energy_bolt_rank", "regardless of the order")
	# A real Rare +2 passive rank offer must not beat a Normal new attack skill.
	w.learn_skill("magic_armor")
	var rare_passive := w.upgrades.choice_card("magic_armor_rank", w, "rare")
	assert_eq(_magnitude(rare_passive), 2, "a Rare passive rank offer grants two ranks")
	assert_true(BotInput.card_score(w, rare_passive) < BotInput.card_score(w, {"id": "energy_bolt_new"}))


func test_a_card_score_override_is_the_base_and_the_gain_is_added_without_a_job_bonus() -> void:
	var w := RF.quiet_world()
	RF.as_job(w, 200)
	w.learn_skill("magic_armor")
	w.balance["bot"] = {"card_scores": {"magic_armor_rank": 70.0, "magic_armor_new": 90.0}}
	var step := BotInput.SCORE_GAIN_STEP
	assert_eq(BotInput.card_score(w, {"id": "magic_armor_rank"}), 70.0, "no gain, no job bonus: the override itself")
	assert_eq(BotInput.card_score(w, {"id": "magic_armor_rank", "magnitude": 3}), 70.0 + 2.0 * step)
	assert_eq(BotInput.card_score(w, {"id": "magic_armor_new", "magnitude": 5}), 90.0 + 4.0 * step)
	var cards := [w.upgrades.choice_card("magic_armor_rank", w, "rare"), w.upgrades.choice_card("energy_bolt_rank", w, "normal")]
	assert_true(_magnitude(cards[0]) > 1)
	assert_eq(BotInput.card_score(w, cards[0]), 70.0 + step * float(_magnitude(cards[0]) - 1))


func test_elixir_score_ignores_tier_and_magnitude() -> void:
	var w := RF.quiet_world()
	RF.change_job_bare(w, 200)
	for m: int in [-1, 0, 1, 3, 9]:
		assert_eq(BotInput.card_score(w, {"id": "elixir", "magnitude": m}), BotInput.SCORE_MOD_OTHER, "the Elixir fallback keeps its old score")
		assert_eq(BotInput.card_score(w, {"id": "not_a_card", "magnitude": m}), 0.0, "an unknown card scores 0")
		assert_eq(BotInput.card_score(w, {"id": "orange_potion", "magnitude": m}), 0.0, "a removed potion card scores 0")




func test_flees_two_mobs_instead_of_dueling() -> void:
	var w := RF.quiet_world(400, 9)
	w.god = true
	w.runner.cooldowns["three_snails"] = 1000.0
	RF.put_mob(w, 100100, 470, 190, 100.0)
	RF.put_mob(w, 100100, 500, 190, 100.0)
	var mi := BotInput.decide(w, {})
	assert_true(mi.left, "two mobs on the right: run left")


func test_auto_choose_policies() -> void:
	var w := RF.quiet_world()
	w.pickups.spawn(w.player.pos, w.progression.curve.exp_to_next(1), 4000019)
	for i in 120:
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "a level-up window")
	var expected := BotInput.pick_card_for(w, w.pending_cards)
	assert_eq(BotInput.auto_choose(w), 1, "one choice made")
	assert_eq(int(w.loadout.card_ranks.get(expected, 0)), 1, "the sensible card was applied (%s)" % expected)


func test_climbs_a_ladder_to_drops_above() -> void:
	var w := RF.quiet_world(1400.0)
	assert_eq(w.player.pos.y, 200.0, "on the ground")
	# Drops on the platform above the ladder at x 1200 (ground 200 -> platform ~80), out of magnet reach.
	for i in 5:
		w.pickups.spawn(Vector2(1230.0 + i * 8.0, 70.0), 2, 4000019)
	var memo := {}
	var grabbed := false
	var up_top := false
	for t in 60 * 12:
		w.step(DT, BotInput.decide(w, memo))
		w.drain_events()
		if w.player.ladder >= 0:
			grabbed = true
		if grabbed and w.player.fh >= 0 and w.player.pos.y < 100.0:
			up_top = true
		if up_top and w.pickups.active_count() == 0:
			break
	assert_true(grabbed, "walked to the ladder and grabbed it")
	assert_true(up_top, "climbed off the top onto the platform (y %.0f)" % w.player.pos.y)
	assert_eq(w.pickups.active_count(), 0, "collected the drops up there")
	assert_eq(w.progression.exp, 10, "their EXP")


func test_a_few_drops_above_do_not_start_a_climb() -> void:
	var w := RF.quiet_world(400.0)
	# Three drops above (fewer than CLIMB_MIN_DROPS): the bot stays on the ground and does not grab a ladder.
	for i in BotInput.CLIMB_MIN_DROPS - 1:
		w.pickups.spawn(Vector2(-700.0 + i * 10.0, 70.0), 1, 4000019)
	var memo := {}
	for t in 60 * 5:
		w.step(DT, BotInput.decide(w, memo))
		assert_true(w.player.ladder < 0, "no climb for a few drops")
		if w.player.ladder >= 0:
			break
	assert_true(w.player.pos.y >= 190.0, "still on the ground")


# --- equipment drops the bot cannot take (#112) ---

func _fill_equip_tab(w: RunWorld) -> void:
	while w.equipment.inventory.size() < w.inventory_slots():
		w.equipment.inventory.append({"id": 1002001, "stats": {"incPDD": 1}, "slots": 7, "scrolls": 0})


func _drop_equipment_and_exp(w: RunWorld) -> int:
	var i := w.pickups.spawn_equipment(Vector2(440.0, 190.0), {"id": 1372005, "stats": {"incMAD": 20}, "slots": 7, "scrolls": 0})
	w.pickups.spawn(Vector2(250.0, 190.0), 3, 4000019)
	return i


func test_a_bot_with_a_full_equip_tab_ignores_an_equipment_drop_and_collects_the_exp_instead() -> void:
	var w := RF.quiet_world(400.0, 11)
	_fill_equip_tab(w)
	var drop := _drop_equipment_and_exp(w)
	var memo := {}
	for t in 60 * 6:
		w.step(DT, BotInput.decide(w, memo))
		w.drain_events()
	assert_eq(w.progression.exp, 3, "walked past the nearer equipment to the EXP drop")
	assert_eq(w.pickups.active[drop], 1, "the equipment is still on the ground")
	assert_eq(w.equipment.inventory.size(), w.inventory_slots(), "nothing was added to a full tab")


func test_a_bot_with_room_still_walks_to_the_nearest_equipment_drop() -> void:
	var w := RF.quiet_world(400.0, 11)
	var drop := _drop_equipment_and_exp(w)
	var memo := {}
	for t in 60 * 6:
		w.step(DT, BotInput.decide(w, memo))
		w.drain_events()
	assert_eq(w.pickups.active[drop], 0, "picked up")
	assert_eq(w.equips_collected, 1)
	assert_eq(w.progression.exp, 3, "and then the EXP drop as before")


func test_a_full_equip_tab_leaves_the_bot_idle_when_only_equipment_lies_around() -> void:
	var w := RF.quiet_world(400.0, 11)
	_fill_equip_tab(w)
	var centre := w.bounds.get_center().x
	var away := -1.0 if centre > w.player.pos.x else 1.0 # the drop lies on the far side from the map centre
	w.pickups.spawn_equipment(Vector2(w.player.pos.x + away * 150.0, 190.0), {"id": 1372005, "stats": {"incMAD": 20},
		"slots": 7, "scrolls": 0})
	var memo := {}
	var start := absf(centre - w.player.pos.x)
	assert_true(start > 300.0, "the fixture map is wide enough to tell the two goals apart")
	for t in 60 * 4:
		w.step(DT, BotInput.decide(w, memo))
		w.drain_events()
	assert_true(absf(centre - w.player.pos.x) < start - 100.0, "it heads for the map centre, not to the drop it cannot take")
