extends TestCase
## The agent playtest's deterministic invariants (game/tools/playtest/playtest_invariants.gd, spec #91, ticket #96):
## each check fires on a constructed violation and stays silent over a normal synthetic run, repeats are
## de-duplicated, and the stuck detector ignores hold / idle / camper parking. Synthetic worlds, seeded, fixed dt.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const RUN_POLICY := preload("res://tools/run_policy.gd")
const INVARIANTS := preload("res://tools/playtest/playtest_invariants.gd")
const PROTOCOL := preload("res://tools/playtest/playtest_protocol.gd")
const DT := 1.0 / 60.0


## A spawning quiet world one EXP bar from Lv 10 (job window) with two boss bonus windows queued.
func _lv10_world(data: Dictionary) -> RunWorld:
	var w := RunWorld.new(RF.setup("quiet", 9, data))
	w.progression.level = 9
	w.progression.add_exp(w.progression.exp_to_next())
	w.pending_bonus_choices = 2
	return w


func _spawning_data(cap := 30.0) -> Dictionary:
	var data := RF.quiet_data()
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = cap
	return data


## Invariants watching `w` (one tick observed so the baseline state is known).
func _watch(w: RunWorld, policy: Object = null, options := {}) -> INVARIANTS:
	var inv := INVARIANTS.new(policy, options)
	inv.observe(w, [])
	return inv


func _kinds(inv: INVARIANTS) -> Array:
	return inv.findings.map(func(f: Dictionary) -> String: return String(f.kind))


func test_a_normal_synthetic_run_with_windows_is_silent() -> void:
	var policy := POLICY.new()
	var inv := INVARIANTS.new(policy)
	inv.attach(policy)
	var w := _lv10_world(_spawning_data())
	var r: Dictionary = BR.run_one(w, policy, 9, -1.0, 60.0, 0, policy.observe)
	assert_true(int(r.spawned) > 0 and r.cards_taken.size() >= 3, "fixture: mobs, a job window and card windows")
	assert_eq(inv.findings, [], "no invariant fires on a normal run")
	assert_eq(inv.checked_offers, r.cards_taken.size(), "every card window was checked, chained ones included")


func test_observer_only_on_a_bot_run_through_windows_is_silent() -> void:
	var inv := INVARIANTS.new()
	var w := _lv10_world(_spawning_data())
	w.pending_bonus_choices = 0 # the first window after a step is the job window
	var r: Dictionary = BR.run_one(w, "bot", 9, -1.0, 60.0, 0, inv.observe)
	assert_true(r.cards_taken.size() >= 2, "fixture: a job window and card windows resolved inside choose()")
	assert_eq(inv.findings, [], "windows resolved between two observations are not bad transitions")


func test_hp_above_max_is_a_finding_with_a_snapshot() -> void:
	var w := RF.quiet_world(400.0, 3)
	w.step(DT, MoveInput.new())
	var inv := _watch(w)
	RF.put_mob(w, 100100, 700.0)
	w.player_state.hp = int(w.player_state.max_hp) + 5
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["hp_out_of_range"])
	var f: Dictionary = inv.findings[0]
	assert_eq(String(f.severity), "error")
	assert_eq(int(f.tick), roundi(w.time / DT))
	assert_near(float(f.time), w.time, 0.001)
	assert_eq(int(f.count), 1)
	assert_true(String(f.message).contains(str(int(w.player_state.hp))), f.message)
	var s: Dictionary = f.snapshot
	for key: String in ["x", "y", "fh", "platform", "hp", "max_hp", "mp", "max_mp", "level", "job", "tactic", "state",
			"mobs"]:
		assert_has(s, key, "snapshot has " + key)
	assert_eq(String(s.tactic), "kite", "no tactic on the policy reads as kite")
	assert_eq(String(s.state), "PLAYING")
	assert_eq(s.mobs.size(), 1, "the nearest mobs")
	assert_near(float(s.mobs[0].d), 300.0, 2.0, "mob distance")
	assert_eq(int(s.mobs[0].mob), 100100)


## A quiet world (job 0) with a boss bonus card window open, watched by invariants.
func _card_window() -> Array:
	var w := RF.quiet_world(400.0, 43)
	var inv := _watch(w)
	w.pending_bonus_choices = 1
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "fixture: a card window is open")
	return [w, inv]


func _offer(w: RunWorld, ids: Array) -> void:
	w.pending_cards = ids.map(func(id: String) -> Dictionary: return w.upgrades.choice_card(id, w))


func _messages(inv: INVARIANTS) -> String:
	return " | ".join(inv.findings.map(func(f: Dictionary) -> String: return "%s: %s" % [f.kind, f.message]))


func test_a_real_card_window_passes_the_offer_rules() -> void:
	var pair := _card_window()
	var inv: INVARIANTS = pair[1]
	inv.observe(pair[0], [])
	assert_eq(inv.findings, [], _messages(inv))
	assert_eq(inv.checked_offers, 1)


func test_an_empty_card_offer_is_a_finding() -> void:
	var pair := _card_window()
	var w: RunWorld = pair[0]
	var inv: INVARIANTS = pair[1]
	w.pending_cards = []
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["card_offer"])
	assert_true(_messages(inv).contains("empty"), _messages(inv))


func test_duplicate_card_ids_are_a_finding() -> void:
	var pair := _card_window()
	var w: RunWorld = pair[0]
	var inv: INVARIANTS = pair[1]
	_offer(w, ["magnet", "magnet", "recovery"])
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["card_offer"])
	assert_true(_messages(inv).contains("duplicate") and _messages(inv).contains("magnet"), _messages(inv))


func test_a_card_of_another_job_is_a_finding() -> void:
	var pair := _card_window()
	var w: RunWorld = pair[0]
	var inv: INVARIANTS = pair[1]
	_offer(w, ["magnet", "magic_guard_new", "recovery"])
	inv.observe(w, [])
	var m := _messages(inv)
	assert_true(m.contains("magic_guard_new") and m.contains("job 0"), m)
	assert_true(m.contains("requires jobs [200]"), "the exact-job rule of GAME_DESIGN 8: " + m)
	assert_true(m.contains("not in the line"), "the skill's job is outside the current job's line: " + m)


func test_a_job_neutral_skill_card_of_another_line_is_a_finding() -> void:
	var pair := _card_window()
	var w: RunWorld = pair[0]
	var inv: INVARIANTS = pair[1]
	w.upgrades.card("teleport_fp_new").erase("requires") # constructed: a card that forgot its job requirement
	_offer(w, ["magnet", "teleport_fp_new", "recovery"])
	inv.observe(w, [])
	var m := _messages(inv)
	assert_eq(_kinds(inv), ["card_offer"], m)
	assert_true(m.contains("teleport_fp") and m.contains("not in the line"), m)


func test_a_card_for_a_skill_at_its_max_rank_is_a_finding() -> void:
	var pair := _card_window()
	var w: RunWorld = pair[0]
	var inv: INVARIANTS = pair[1]
	w.loadout.add_skill("recovery")
	w.loadout.set_rank("recovery", w.loadout.book.max_rank("recovery"))
	_offer(w, ["magnet", "recovery_rank"])
	inv.observe(w, [])
	var m := _messages(inv)
	assert_eq(_kinds(inv), ["card_offer"], m)
	assert_true(m.contains("recovery_rank") and m.contains("max rank"), m)


func test_the_elixir_beside_three_cards_is_a_finding() -> void:
	var pair := _card_window()
	var w: RunWorld = pair[0]
	var inv: INVARIANTS = pair[1]
	_offer(w, ["magnet", "recovery", "nimble_feet", "elixir"])
	inv.observe(w, [])
	var m := _messages(inv)
	assert_eq(_kinds(inv), ["card_offer", "card_offer"], m)
	assert_true(m.contains("Power Elixir"), m)
	assert_true(m.contains("at most three"), "four cards in a normal draw: " + m)


func test_a_state_outside_the_pause_protocol_is_a_finding() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	w.state = RunWorld.DEAD
	inv.observe(w, [])
	assert_eq(inv.findings, [], "PLAYING -> DEAD is allowed")
	w.state = RunWorld.PLAYING
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["bad_state_transition"])
	assert_true(_messages(inv).contains("DEAD -> PLAYING"), _messages(inv))


func test_a_job_window_must_lead_to_a_card_window() -> void:
	var w := RF.quiet_world(400.0, 53)
	var inv := _watch(w)
	w.progression.level = 9
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	inv.observe(w, [])
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "fixture: Lv 10 opens the job window")
	w.state = RunWorld.PLAYING # constructed: the window vanished without a card choice
	inv.on_decision(w, "job", "applied")
	assert_eq(_kinds(inv), ["bad_state_transition"])
	assert_true(_messages(inv).contains("CHOOSING_JOB -> PLAYING"), _messages(inv))


func test_mp_outside_its_pool_is_a_finding() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	w.player_state.mp = -1
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["mp_out_of_range"])


func test_a_non_finite_position_is_a_finding() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	w.player.pos.x = NAN
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["position_not_finite"])


func test_a_position_outside_the_map_bounds_and_margin_is_a_finding() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	assert_true(w.bounds.has_area(), "fixture: the map has bounds")
	w.player.pos = Vector2(w.bounds.end.x + INVARIANTS.BOUNDS_MARGIN - 1.0, w.bounds.position.y - INVARIANTS.BOUNDS_MARGIN + 1.0)
	inv.observe(w, [])
	assert_eq(inv.findings, [], "inside the margin is fine")
	w.player.pos.x = w.bounds.end.x + INVARIANTS.BOUNDS_MARGIN + 1.0
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["out_of_bounds"])


func test_level_and_exp_never_decrease_except_a_level_up_resetting_exp() -> void:
	var w := RF.quiet_world(400.0, 5)
	w.player_state.level = 4
	w.player_state.exp = 30
	var inv := _watch(w)
	w.player_state.level = 5
	w.player_state.exp = 2
	inv.observe(w, [])
	assert_eq(inv.findings, [], "a level-up resets EXP")
	w.player_state.exp = 1
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["exp_decreased"])
	w.player_state.level = 4
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["exp_decreased", "level_decreased"])


func test_each_new_world_warning_is_a_finding_once() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	w.warnings.append("boss 9300003 has no spawn point")
	inv.observe(w, [])
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["world_warning"])
	assert_true(String(inv.findings[0].message).contains("9300003"))
	w.warnings.append("another warning")
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["world_warning", "world_warning"], "a different warning is its own finding")


func test_missing_assets_are_findings() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	inv.check_missing(w, PackedStringArray([]))
	assert_eq(inv.findings, [])
	inv.check_missing(w, PackedStringArray(["Mob.wz/9300003.img"]))
	assert_eq(_kinds(inv), ["missing_asset"])
	assert_true(String(inv.findings[0].message).contains("Mob.wz/9300003.img"))


func test_missing_assets_given_at_setup_are_reported_once_on_the_first_tick() -> void:
	var w := RF.quiet_world(400.0, 5)
	var seen: Array = []
	var inv := INVARIANTS.new(null, {"missing": PackedStringArray(["Mob.wz/9300003.img", "Map.wz/Back/x.img"])},
		func(f: Dictionary) -> void: seen.append(f))
	inv.observe(w, [])
	w.time += DT
	inv.observe(w, [])
	assert_eq(_kinds(inv), ["missing_asset", "missing_asset"], "one finding per missing entry, not per tick")
	assert_eq(seen.size(), 2, "streamed like every finding")
	assert_eq(int(inv.findings[0].tick), 0, "reported at the round start")
	assert_true(String(inv.findings[1].message).contains("Map.wz/Back/x.img"))


func test_the_driver_starts_a_round_with_missing_entries_but_not_without_a_map() -> void:
	var driver: GDScript = load("res://tools/playtest/playtest_driver.gd")
	var setup := {"map_img": {"info": {}}}
	assert_eq(driver.setup_error(setup, PackedStringArray()), "")
	assert_eq(driver.setup_error(setup, PackedStringArray(["Mob.wz/9300003.img"])), "",
		"missing entries are a missing_asset finding, not an infrastructure error")
	var no_map: String = driver.setup_error({"map_img": {}}, PackedStringArray(["Map.wz/Map/Map1/104040000.img"]))
	assert_true(no_map.contains("104040000"), "no map: the round cannot start (cache_missing, exit 2)")
	assert_true(driver.setup_error({}, PackedStringArray()) != "")


func test_repeats_of_one_kind_at_one_place_count_once() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	for i in 120:
		w.time += DT
		w.player_state.hp = int(w.player_state.max_hp) + 1
		inv.observe(w, [])
	assert_eq(_kinds(inv), ["hp_out_of_range"], "two seconds of the same failure are one finding")
	assert_eq(int(inv.findings[0].count), 120)
	w.player.pos.x += INVARIANTS.DEDUP_PX + 10.0
	inv.observe(w, [])
	assert_eq(inv.findings.size(), 2, "the same kind at another place is another finding")
	w.time += INVARIANTS.DEDUP_S + 1.0
	inv.observe(w, [])
	assert_eq(inv.findings.size(), 3, "the same kind at the same place after the window is another finding")
	assert_eq(inv.results().map(func(f: Dictionary) -> int: return int(f.count)), [120, 1, 1])
	assert_false(inv.results()[0].has("_key"), "results carry no bookkeeping fields")


func test_new_findings_stream_to_the_sink_once() -> void:
	var w := RF.quiet_world(400.0, 5)
	var sent: Array = []
	var inv := INVARIANTS.new(null, {}, func(f: Dictionary) -> void: sent.append(f))
	inv.observe(w, [])
	for i in 10:
		w.player_state.mp = -5
		inv.observe(w, [])
	assert_eq(sent.size(), 1)
	assert_eq(String(sent[0].kind), "mp_out_of_range")


## Holds the player at its spot in movement state `state` for `seconds` of run time, observing every tick.
func _hold_still(w: RunWorld, inv: INVARIANTS, seconds: float, state := PlayerMotion.ST_WALK) -> void:
	for i in roundi(seconds / DT):
		w.time += DT
		w.player.state = state
		inv.observe(w, [])


func test_a_player_pressing_movement_without_moving_is_stuck() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	_hold_still(w, inv, INVARIANTS.STUCK_S - 2.0)
	assert_eq(inv.findings, [], "not yet a full window")
	_hold_still(w, inv, 3.0)
	assert_eq(_kinds(inv), ["stuck"])
	assert_true(String(inv.findings[0].message).contains("20"), inv.findings[0].message)


func test_a_player_walking_back_and_forth_is_not_stuck() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w)
	for i in roundi(30.0 / DT):
		w.time += DT
		w.player.state = PlayerMotion.ST_WALK
		w.player.pos.x = 400.0 + 40.0 * sin(w.time)
		inv.observe(w, [])
	assert_eq(inv.findings, [])


class HoldPolicy:
	var tactic := "hold"


func test_the_stuck_detector_ignores_hold() -> void:
	var w := RF.quiet_world(400.0, 5)
	var inv := _watch(w, HoldPolicy.new())
	_hold_still(w, inv, 30.0)
	assert_eq(inv.findings, [])


func test_the_stuck_detector_ignores_camper_parking() -> void:
	var w := RF.quiet_world(400.0, 5)
	var camper := RUN_POLICY.new("camper_henesys_top", 1, 0, 0.0)
	var inv := _watch(w, camper)
	_hold_still(w, inv, 30.0)
	assert_eq(inv.findings, [], "a parked camper is not stuck")
	var w2 := RF.quiet_world(400.0, 6)
	var rope := _watch(w2)
	_hold_still(w2, rope, 30.0, PlayerMotion.ST_LADDER)
	assert_eq(rope.findings, [], "hanging on a rope presses no movement")


func test_an_injected_finding_fires_once_at_its_time_and_streams_as_a_protocol_line() -> void:
	var w := RF.quiet_world(400.0, 5)
	var lines: PackedStringArray = []
	var inv := INVARIANTS.new(null, {"inject": "out_of_bounds", "inject_at": 1.0},
		func(f: Dictionary) -> void: lines.append(PROTOCOL.encode(PROTOCOL.finding(f))))
	for i in 120:
		w.step(DT, MoveInput.new())
		inv.observe(w, [])
	assert_eq(_kinds(inv), ["out_of_bounds"])
	assert_true(String(inv.findings[0].message).contains("--inject-finding"), inv.findings[0].message)
	assert_near(float(inv.findings[0].time), 1.0, 0.02)
	assert_eq(lines.size(), 1)
	var msg: Dictionary = JSON.parse_string(lines[0].substr(PROTOCOL.PREFIX.length()))
	assert_eq(String(msg.type), "finding")
	assert_eq(int(msg.v), PROTOCOL.VERSION)
	assert_eq(String(msg.kind), "out_of_bounds")
	assert_eq(int(msg.tick), 60)
	assert_true(msg.snapshot.has("x"))
	assert_true(INVARIANTS.KINDS.has("stuck") and INVARIANTS.KINDS.has("card_offer"), "the known kinds are listed")


func test_the_stuck_detector_ignores_an_idle_player() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = 30.0
	var w := RunWorld.new(RF.setup("quiet", 9, data))
	var inv := INVARIANTS.new()
	BR.run_one(w, "bot", 9, 0.0, 60.0, 0, inv.observe)
	assert_true(w.time >= 29.0, "fixture: a 30 s hands-off round")
	assert_eq(inv.findings, [], "hands off the keys is not stuck")
