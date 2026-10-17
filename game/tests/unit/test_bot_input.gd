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
	var cards := _cards(w, ["improved_max_mp", "magnet", "energy_bolt_new"])
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_new", "a new attack skill first")
	assert_eq(BotInput.pick_card(cards), "improved_max_mp", "the first-card policy takes the first")
	w.upgrades.apply("energy_bolt_new", w)
	assert_eq(BotInput.pick_card_for(w, _cards(w, ["energy_bolt_pierce", "magnet", "energy_bolt_count"])),
		"energy_bolt_count", "more bolts before pierce")
	assert_eq(BotInput.pick_card_for(w, _cards(w, ["three_snails_count", "energy_bolt_count"])), "energy_bolt_count",
		"the current job's skill before the Beginner's")
	assert_eq(BotInput.pick_card_for(w, _cards(w, ["magnet", "improved_max_mp"])), "improved_max_mp",
		"an owned passive skill before a general utility modifier")
	assert_eq(BotInput.pick_card_for(w, []), "", "nothing to pick")


func test_optional_card_scores_are_final_and_missing_cards_keep_their_fallback() -> void:
	var w := RF.quiet_world()
	w.balance.erase("bot")
	w.change_job(200)
	var cards := _cards(w, ["magic_guard_new", "energy_bolt_rank"])
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "without overrides the existing offense preference remains")
	w.balance["bot"] = {"card_scores": {"magic_guard_new": 70.0}}
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "70 is the final score: no additional current-job bonus")
	w.balance.bot.card_scores.magic_guard_new = 90.0
	assert_eq(BotInput.pick_card_for(w, cards), "magic_guard_new", "survivor data can prioritize a useful defense card")
	w.learn_skill("magic_guard")
	cards = _cards(w, ["magic_guard_rank", "energy_bolt_rank"])
	w.balance.bot.card_scores.magic_guard_rank = 70.0
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "a rank override also receives no job bonus")
	w.balance.bot.card_scores.magic_guard_rank = 90.0
	assert_eq(BotInput.pick_card_for(w, cards), "magic_guard_rank")
	w.balance.bot.card_scores.erase("magic_guard_rank")
	assert_eq(BotInput.pick_card_for(w, cards), "energy_bolt_rank", "a missing individual card uses its original score")


func test_a_tiny_pool_never_wastes_a_blue_potion_on_a_shortage() -> void:
	var data := RF.quiet_data()
	data.balance.potions.mp.start = 2
	var w := RunWorld.new(RF.setup("quiet", 26, data))
	w.god = true
	RF.place_player(w, 400)
	RF.put_mob(w, 1110100, 600, 190, 100.0)
	w.step(DT, MoveInput.new())
	assert_eq(w.player_state.mp, 2, "opening canonical L1 cast spends three of the five MP")
	for tick in 67:
		w.step(DT, MoveInput.new())
	assert_true(w.player_state.mp_short, "a ready targeted shell cannot afford its canonical cost")
	assert_false(BotInput.decide(w, {}).drink_mp, "three missing MP would waste 97 of a canonical 100-MP Blue")


func test_duels_a_lone_mob_with_the_sword_when_no_skill_can_fire() -> void:
	var w := RF.quiet_world(400, 9)
	w.god = true
	w.spend_mp(int(w.player_state.mp))
	var mob := RF.put_mob(w, 100100, 470, 190, 100.0)
	var face := 1 if w.player.facing > 0 else -1
	w.swarm.x[mob] = 400.0 + 70.0 * face
	var mi := BotInput.decide(w, {})
	assert_false(mi.left or mi.right, "facing the lone snail: stand still so the basic attack swings")
	w.swarm.x[mob] = 400.0 - 70.0 * face
	mi = BotInput.decide(w, {})
	assert_true(mi.left if face > 0 else mi.right, "a lone snail behind: one press turns toward it")
	w.heal_fraction("mp", 1.0)
	mi = BotInput.decide(w, {})
	assert_true(mi.left or mi.right, "an affordable ready Three Snails: keep kiting, the skill does the work")


func test_flees_two_mobs_instead_of_dueling() -> void:
	var w := RF.quiet_world(400, 9)
	w.god = true
	w.spend_mp(int(w.player_state.mp))
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
