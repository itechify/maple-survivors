extends TestCase
## M22's synthetic catalogue, cards, cast snapshots and ordinary-hit contracts (#402).
const RF := preload("res://tests/fixtures/run_fixtures.gd")

func test_catalogue_rejects_invalid_kinds_rank_lists_chances_and_references() -> void:
	assert_true(StatusBonus.errors({"v": {"kind": "poison", "chance": 14, "time": 2, "level": 4}}, {}).is_empty())
	for entry: Dictionary in [{"kind": "unknown"}, {"kind": "stun", "chance": [20, 30]},
			{"kind": "poison", "chance": 101}, {"kind": "poison", "chance": -1}]:
		assert_false(StatusBonus.errors({"v": entry}, {}).is_empty())
	assert_false(StatusBonus.errors({}, {"skills": {"test": {"rarity_bonuses": {"epic": [
		{"effects": [{"stat": "status", "op": "grant", "status": "missing"}]}]}}}}).is_empty())

func test_catalogue_rejects_a_kind_missing_the_parameters_it_needs() -> void:
	# Review S2: a burn needs `pulse`, a slow a negative `x`, a threatened an `x` or `y`; a poison needs a level below 70
	# and every kind a positive time, or the grant would validate and then do nothing.
	for entry: Dictionary in [{"kind": "burn", "time": 3}, {"kind": "burn", "time": 3, "pulse": 0},
			{"kind": "slow", "time": 3}, {"kind": "slow", "time": 3, "x": 20}, {"kind": "threatened", "time": 3},
			{"kind": "poison", "time": 3}, {"kind": "poison", "time": 3, "level": 70}, {"kind": "stun"},
			{"kind": "stun", "time": 2, "x": "nope"}]:
		assert_false(StatusBonus.errors({"v": entry}, {}).is_empty(), str(entry))
	for entry: Dictionary in [{"kind": "burn", "time": 3, "pulse": 40}, {"kind": "slow", "time": 3, "x": -30},
			{"kind": "threatened", "time": 3, "y": -20}, {"kind": "freeze", "time": 2},
			{"kind": "slow", "time": 3, "x": [-10, -12, -14, -16, -18, -20, -22, -24]}]:
		assert_true(StatusBonus.errors({"v": entry}, {}).is_empty(), str(entry))

func test_burn_and_slow_grants_really_change_the_monster() -> void:
	var w := _world()
	w.loadout.status_bonuses["scorch"] = {"kind": "burn", "chance": 100, "time": 4, "pulse": 25}
	w.loadout.status_bonuses["chill"] = {"kind": "slow", "chance": 100, "time": 4, "x": -40}
	w.loadout.add_status_grant("energy_bolt", "scorch")
	w.loadout.add_status_grant("energy_bolt", "chill")
	var st := w.loadout.stats("energy_bolt")
	assert_eq(st.status_grants[0].pulse, 25)
	assert_eq(st.status_grants[1].x, -40.0)
	var m := RF.put_mob(w, 1110100, 700)
	_hit(w, m, st)
	assert_near(w.swarm.status_time(m, MobSwarm.BURN), 4.0)
	assert_near(w.swarm.status_time(m, MobSwarm.SLOW), 4.0)
	assert_near(w.swarm.slow_factor[m], 0.6, 0.0001, "a 40 percent slow")

func test_a_reapplied_poison_grant_keeps_the_pulse_clock_running() -> void:
	# Review N2: the ground-zone path preserves the clock; a star's grant must not restart it on every re-roll.
	var w := _world()
	w.loadout.status_bonuses["venom"]["chance"] = 100
	w.loadout.add_status_grant("energy_bolt", "venom")
	var st := w.loadout.stats("energy_bolt")
	var m := RF.put_mob(w, 1110100, 700, 180, 100000)
	_hit(w, m, st)
	w.swarm._poison_pulse[m] = 0.4 # the clock has run for 0.6 s
	_hit(w, m, st)
	assert_near(w.swarm._poison_pulse[m], 0.4, 0.0001, "the second grant did not reset the pulse clock")

func _world() -> RunWorld:
	var w := RF.quiet_world()
	w.loadout.status_bonuses = {
		"venom": {"name": "Venomous Star", "kind": "poison", "chance": [14, 16, 18, 20, 22, 24, 26, 30],
			"time": [2, 2, 2, 3, 3, 3, 4, 4], "level": [4, 8, 12, 15, 19, 23, 27, 30], "repeat_chance": 3},
		"stop": {"kind": "stun", "chance": 100, "time": 1.5, "repeat_chance": 4}}
	w.book.status_bonuses = w.loadout.status_bonuses
	w.book.def("energy_bolt").rarity_bonuses.epic = [{"id": "venom", "text": "Venomous Star",
		"effects": [{"stat": "status", "op": "grant", "status": "venom"}]}]
	return w

func test_grant_card_is_separate_rank_resolved_repeatable_and_preview_is_pure() -> void:
	var w := _world()
	var before := var_to_bytes(w.loadout.stats("fire_arrow"))
	var mods := w.loadout.skill_mods.duplicate(true)
	var card := w.upgrades.choice_card("energy_bolt_rank", w, "epic")
	assert_true(w.loadout.grants.is_empty(), "preview cannot award grants")
	assert_true("poison" in String(card.desc))
	w.upgrades.apply("energy_bolt_rank", w, "epic")
	assert_eq(w.loadout.grants.energy_bolt, ["venom"])
	assert_eq(w.loadout.skill_mods, mods)
	assert_eq(var_to_bytes(w.loadout.stats("fire_arrow")), before)
	var grant: Dictionary = w.loadout.stats("energy_bolt").status_grants[0]
	assert_eq(grant, {"id": "venom", "kind": "poison", "element": "S", "chance": 16.0, "time": 2.0, "level": 8})
	w.upgrades.apply("energy_bolt_rank", w, "epic")
	assert_near(w.loadout.stats("energy_bolt").status_grants[0].chance, 20.4)
	w.loadout.set_rank("energy_bolt", 8)
	assert_near(w.loadout.stats("energy_bolt").status_grants[0].chance, 32.4)
	var copy := w.loadout.clone()
	copy.add_status_grant("energy_bolt", "stop")
	assert_eq(w.loadout.grants.energy_bolt, ["venom"])
	assert_eq(copy.stats("energy_bolt").status_grants[1].time, 1.5)
	assert_true("Venomous Star: 32.4% to poison for 4 s" in SkillText.new(w.book).level_line(
		"energy_bolt", w.loadout.level("energy_bolt"), w.loadout.stats("energy_bolt")))

func _hit(w: RunWorld, m: int, st: Dictionary) -> void:
	var damage_rng := RandomNumberGenerator.new()
	damage_rng.seed = 402
	st = st.duplicate(true)
	st.damage_min = 1.0
	st.damage_max = 1.0
	st.damage_type = "fixed"
	st.element = ""
	st.crit = 0.0
	w.hit_mob(m, st, -1, damage_rng)

func test_hit_grants_draw_once_in_order_refresh_and_coexist_with_native_status() -> void:
	var w := _world()
	w.loadout.add_status_grant("energy_bolt", "stop")
	w.loadout.add_status_grant("energy_bolt", "venom")
	w.book.def("energy_bolt")["on_hit"] = {"status": "freeze"}
	# Synthetic native status duration at canonical level 1.
	w.book.level_node("energy_bolt", w.loadout.level("energy_bolt"))["time"] = 2.0
	var m := RF.put_mob(w, 1110100, 700)
	var expected := RandomNumberGenerator.new()
	expected.state = w.rng.state
	var succeeds := expected.randf() * 100.0 < 14.0
	var st := w.loadout.stats("energy_bolt")
	_hit(w, m, st)
	assert_eq(w.rng.state, expected.state, "100% stun and native status draw nothing; poison draws once")
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 1.5)
	assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 2.0)
	assert_eq(w.swarm.status_time(m, MobSwarm.POISON) > 0, succeeds)
	_hit(w, m, st)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 1.5, 0.00001, "refresh, never stack")

func test_grants_keep_boss_and_element_gates_and_cap_chance() -> void:
	for attr: String in ["S1", "S2", "S4", "S3", ""]:
		var w := _world()
		w.loadout.add_status_grant("energy_bolt", "venom")
		for repeat in 100:
			w.loadout.add_status_grant("energy_bolt", "venom")
		var st := w.loadout.stats("energy_bolt")
		assert_eq(st.status_grants[0].chance, 100.0)
		var m := RF.put_mob(w, 1110100, 700)
		w.swarm.mob_kind(m).element_codes = MobKind.from_wz({"info": {"elemAttr": attr}}, 1).element_codes
		_hit(w, m, st)
		assert_eq(w.swarm.status_time(m, MobSwarm.POISON) > 0, attr in ["", "S3"], attr)
	for scheduled: bool in [false, true]:
		var w := _world()
		w.loadout.add_status_grant("energy_bolt", "stop")
		var m := RF.put_mob(w, 1110100 if scheduled else 2220000, 700)
		w.swarm.steady[m] = 1 if scheduled else 0
		_hit(w, m, w.loadout.stats("energy_bolt"))
		assert_near(w.swarm.status_time(m, MobSwarm.STUN), 0.0)

func test_projectile_carries_cast_time_grants_after_loadout_changes() -> void:
	var w := _world()
	w.loadout.add_status_grant("energy_bolt", "stop")
	var m := RF.put_mob(w, 1110100, 700)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var st := w.loadout.stats("energy_bolt")
	st.damage_min = 1.0
	st.damage_max = 1.0
	st.damage_type = "fixed"
	w.runner.fire_shot(w, "energy_bolt", st, Vector2(650, 180), w.mob_center(m), Vector2(650, 180))
	w.loadout.grants.clear()
	for tick in 60:
		w.projectiles.step(1.0 / 60.0, w.swarm, w.mob_grid, w.events, PackedFloat32Array(),
			PackedByteArray(), w._on_player_hit)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 1.5)

func test_each_rank_resolves_all_three_tables_and_scalar_stun_duration() -> void:
	var w := _world()
	w.loadout.add_status_grant("energy_bolt", "venom")
	w.loadout.add_status_grant("energy_bolt", "stop")
	var chances := [14, 16, 18, 20, 22, 24, 26, 30]
	var times := [2, 2, 2, 3, 3, 3, 4, 4]
	var levels := [4, 8, 12, 15, 19, 23, 27, 30]
	for r in 8:
		var grants: Array = w.loadout.stats("energy_bolt", r + 1).status_grants
		assert_eq(grants[0].chance, float(chances[r]))
		assert_eq(grants[0].time, float(times[r]))
		assert_eq(grants[0].level, levels[r])
		assert_eq(grants[1].time, 1.5)

func test_zero_and_partial_grants_draw_once_each_in_order_on_every_hit() -> void:
	var w := _world()
	var m := RF.put_mob(w, 1110100, 700)
	var st := w.loadout.stats("energy_bolt")
	st["status_grants"] = [
		{"id": "zero", "kind": "poison", "element": "S", "chance": 0.0, "time": 2.0, "level": 30},
		{"id": "half", "kind": "stun", "element": "", "chance": 50.0, "time": 1.5, "level": 1}]
	var expected := RandomNumberGenerator.new()
	expected.seed = 402
	w.rng.seed = 402
	var successes := 0
	for hit in 20:
		w.swarm.despawn(m)
		m = RF.put_mob(w, 1110100, 700)
		expected.randf() # zero chance still consumes the first draw
		var succeeds := expected.randf() * 100.0 < 50.0
		successes += int(succeeds)
		_hit(w, m, st)
		assert_eq(w.rng.state, expected.state)
		assert_eq(w.swarm.status_time(m, MobSwarm.STUN) > 0, succeeds)
		assert_eq(w.swarm.status_time(m, MobSwarm.POISON), 0.0)
	assert_true(successes > 0 and successes < 20, "seed exercises success and failure")

func test_load_time_validation_sees_patched_catalogue_and_card_references() -> void:
	DataRepo.patch = {"balance": {"status_bonuses": {"bad": {"kind": "invalid"}}}}
	var errors := PackedStringArray()
	DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	DataRepo.patch = {}
	assert_false(errors.is_empty())

func test_delayed_strike_retains_grant_snapshot_until_ordinary_hit() -> void:
	var w := _world()
	w.loadout.order = ["energy_bolt"]
	var d := w.book.def("energy_bolt")
	d.kind = "instant"
	d["cast"] = {"rule": "box"}
	d["pending"] = {"delay": 0.2}
	d.cooldown = 10.0
	w.book.level_node("energy_bolt", w.loadout.level("energy_bolt")).merge({
		"lt": {"$v": [-200, -100]}, "rb": {"$v": [200, 100]}})
	w.loadout.add_status_grant("energy_bolt", "stop")
	var m := RF.put_mob(w, 1110100, w.player.pos.x + 70, int(w.player.pos.y), 100000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(1.0 / 60.0, w)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 0.0, 0.00001, "queued, not immediate")
	w.loadout.grants.clear()
	for tick in 30:
		w.runner.step(1.0 / 60.0, w)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 1.5)


func test_shipped_catalogue_validates_and_resolves_its_first_users() -> void:
	var errors := PackedStringArray()
	var data := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "the shipped data has no status-bonus error: %s" % [errors])
	var catalogue: Dictionary = data.balance.status_bonuses
	assert_true(catalogue.has("venomous_star") and catalogue.has("stunning_avenger"))
	var venom: Dictionary = StatusBonus.resolve(catalogue, ["venomous_star"], 8)[0]
	assert_eq(venom, {"id": "venomous_star", "kind": "poison", "element": "s", "chance": 30.0, "time": 4.0, "level": 30})
	var stun: Dictionary = StatusBonus.resolve(catalogue, ["stunning_avenger"], 1)[0]
	assert_eq(stun.kind, "stun")
	assert_near(float(stun.chance), 20.0)
	assert_near(float(stun.time), 1.5)
	# A repeat adds repeat_chance x scale points, capped at 100 percent.
	assert_near(float(StatusBonus.resolve(catalogue, ["stunning_avenger"], 8, {"stunning_avenger": 4.0 * 0.8})[0].chance), 53.2)
	assert_near(float(StatusBonus.resolve(catalogue, ["stunning_avenger"], 8, {"stunning_avenger": 90.0})[0].chance), 100.0)


func test_bot_scores_a_grant_card_like_any_rarity_card() -> void:
	var w := _world()
	w.balance.get("bot", {})["mastery_bonus_score"] = 100.0
	var card := w.upgrades.choice_card("energy_bolt_rank", w, "epic")
	assert_true(BotInput.card_score(w, card) > BotInput.card_score(w, {"id": "energy_bolt_rank"}),
		"the granted status adds to the card's score")
	var half := card.duplicate(true)
	half.rarity_bonus.effects[0]["scale"] = 0.8
	assert_true(BotInput.card_score(w, half) < BotInput.card_score(w, card), "a repeat's diminished grant scores less")


func test_real_cache_venomous_star_numbers_equal_skill_wz_4120005() -> void:
	# Review S6: the survivor catalogue copies the Venomous Star WZ numbers (tier A), so the copy is checked against the node:
	# rank r reads WZ level LEVELS[r - 1]; its `prop` is the chance, `time` the seconds, and the poison level is the level.
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var levels: Dictionary = lib.img("Skill.wz/412.img").root.skill["4120005"].level
	lib.free()
	var data := DataRepo.load_all()
	var rows := StatusBonus.resolve(data.balance.status_bonuses, ["venomous_star"], 1)
	assert_eq(rows.size(), 1)
	var wz_levels := [4, 8, 12, 15, 19, 23, 27, 30]
	for rank in 8:
		var grant: Dictionary = StatusBonus.resolve(data.balance.status_bonuses, ["venomous_star"], rank + 1)[0]
		var node: Dictionary = levels[str(wz_levels[rank])]
		assert_eq(grant.chance, float(node.prop), "rank %d chance is prop of WZ level %d" % [rank + 1, wz_levels[rank]])
		assert_eq(grant.time, float(node.time), "rank %d time" % [rank + 1])
		assert_eq(grant.level, wz_levels[rank], "rank %d poison level is the WZ level" % [rank + 1])
