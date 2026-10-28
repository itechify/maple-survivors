extends TestCase
## A character is one fixed job (#284, ADR 0006): 212 is the only playable job, a fresh round starts with its start
## skills (Energy Bolt, Teleport on its key from Lv1), levelling never opens a job window, cards follow the job's line,
## auto-AP reads the job's one row, there is no basic attack and weapons gate no skill. Seeded synthetic worlds, fixed dt.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(p_seed := 7) -> RunWorld:
	var data := RF.quiet_data()
	var w := RunWorld.new(RF.setup("quiet", p_seed, data))
	RF.place_player(w, 400)
	return w


func test_212_is_the_only_playable_job_and_the_default() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	assert_eq(jobs.playable_jobs(), [212] as Array[int])
	assert_eq(jobs.default_job(), 212)
	assert_eq(jobs.job_error(212), "")
	for id: int in [0, 100, 200, 210, 211, 220, 500]:
		assert_ne(jobs.job_error(id), "", "job %d is not playable" % id)
	assert_ne(jobs.job_error(999), "", "an unknown job is refused")
	assert_eq(Array(jobs.start_skills(212)), ["energy_bolt", "teleport_fp"])


func test_tool_job_flag_names_a_whole_playable_job() -> void:
	assert_eq(JobTree.parse_job("212"), 212)
	assert_eq(JobTree.parse_job(" 212 "), 212)
	assert_eq(JobTree.parse_job("212:wand"), -1, "the old <id>:<path> form is refused")
	assert_eq(JobTree.parse_job("wizard"), -1)
	var data := DataRepo.load_all()
	var options := {}
	JobTree.put_job(options, "212")
	assert_eq(SceneFlow.forced_job_error(options, data), "")
	JobTree.put_job(options, "210")
	assert_ne(SceneFlow.forced_job_error(options, data), "", "a second job is not playable any more")
	JobTree.put_job(options, "100:spear")
	assert_ne(SceneFlow.forced_job_error(options, data), "")
	assert_eq(SceneFlow.forced_job_error({}, data), "", "no --job is fine")


func test_fresh_round_is_212_with_energy_bolt_and_teleport_at_rank_1() -> void:
	var w := _world()
	assert_eq(w.job_id(), 212)
	assert_eq(int(w.player_state.job_id), 212)
	assert_eq(int(w.player_state.level), 1)
	assert_eq(Array(w.loadout.order), ["energy_bolt", "teleport_fp"])
	assert_eq(w.loadout.rank("energy_bolt"), 1)
	assert_eq(w.loadout.rank("teleport_fp"), 1)
	assert_eq(w.teleport_skill(), "teleport_fp", "Teleport is on its key from Lv1, with no card")
	assert_eq(w.manual_skill_keys().map(func(k: Dictionary) -> String: return String(k.action)), ["teleport"])


func test_teleport_blinks_at_level_1() -> void:
	var w := _world()
	w.drain_events()
	var start := w.player.pos
	var input := MoveInput.new()
	input.right = true
	input.press_skill("teleport")
	w.step(DT, input)
	var blinks := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "teleport")
	assert_eq(blinks.size(), 2, "departure and arrival")
	assert_true(w.player.pos.x > start.x + 50.0, "the Lv1 character blinked right (%s -> %s)" % [start, w.player.pos])


func test_setup_job_and_set_job_change_only_the_job() -> void:
	var setup := RF.setup("quiet", 7, RF.quiet_data())
	setup["job"] = 110
	var w := RunWorld.new(setup)
	assert_eq(w.job_id(), 110, "setup.job names a fresh character's job (tools, tests)")
	assert_true(w.loadout.order.is_empty(), "a job without start skills learns nothing")
	var worn := w.equipment.duplicate(true)
	w.set_job(212)
	assert_eq(w.job_id(), 212)
	assert_eq(w.equipment, worn, "set_job grants and wears nothing")
	assert_true(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "job_changed").is_empty())


func test_levelling_past_10_and_30_never_opens_a_job_window() -> void:
	var w := _world()
	var types := {}
	var guard := 0
	while int(w.player_state.level) < 35 and guard < 200:
		guard += 1
		w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		w.step(DT, MoveInput.new())
		while w.state == RunWorld.CHOOSING_UPGRADE:
			for e: Dictionary in w.drain_events():
				types[String(e.type)] = true
			assert_true(w.apply_choice(BotInput.pick_card_for(w, w.pending_cards)))
		for e: Dictionary in w.drain_events():
			types[String(e.type)] = true
	assert_true(int(w.player_state.level) >= 35, "levelled to %d" % int(w.player_state.level))
	assert_eq(w.job_id(), 212, "the job never changes")
	assert_true(types.has("choice_pending"))
	assert_false(types.has("job_advance_pending") or types.has("job_changed"))
	assert_eq(RunWorld.STATE_NAMES, ["PLAYING", "CHOOSING_UPGRADE", "DEAD", "CLEARED"])


func test_cards_follow_the_job_line_without_beginner_or_teleport_cards() -> void:
	var w := _world()
	var eligible := w.upgrades.eligible(w)
	for id: String in ["energy_bolt_rank", "magic_claw_new", "fire_arrow_new", "poison_breath_new"]:
		assert_has(eligible, id, "a 200 or 210 card is on a 212's line")
	for id: String in eligible:
		var skill := String(w.upgrades.card(id).skill)
		if not bool(w.book.def(skill).get("common_passive", false)): # #289: job-neutral passives join every pool
			assert_has(w.jobs.skill_pool(212), skill)
		assert_false(id.begins_with("teleport_"), "Teleport needs no card")
	assert_false(eligible.has("energy_bolt_new"), "the start skill is owned")
	assert_false(eligible.has("cold_beam_new"), "an Ice/Lightning card is off the F/P line")
	for c: Dictionary in w.upgrades.cards:
		assert_false(c.get("requires", {}).has("carry_jobs"), "%s has no carry_jobs" % c.id)
		for j: Variant in c.get("requires", {}).get("jobs", []):
			assert_ne(int(j), 0, "%s is not a Beginner card" % c.id)


func test_auto_ap_reads_the_212_row_int_primary_luk_secondary() -> void:
	var w := _world()
	var row: Dictionary = w.balance.player.ap["212"]
	assert_eq([String(row.primary), String(row.secondary)], ["int", "luk"])
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var luk_ap := AutoAp.secondary_ap(earned, level, float(base.luk), row.keyframes)
	assert_true(luk_ap > 0, "LUK takes its share")
	assert_eq(int(w.player_state.luk), int(base.luk) + luk_ap)
	assert_eq(int(w.player_state.int), int(base.int) + earned - luk_ap, "the rest goes to INT")
	assert_eq(int(w.player_state.str), int(base.str))
	assert_eq(int(w.player_state.dex), int(base.dex))


func test_no_basic_attack_hits_a_mob_in_reach() -> void:
	var w := _world()
	w.loadout.order.clear()
	w.loadout.version += 1
	var slot := RF.put_mob(w, int(RF.MOB_INFO.keys()[0]), 430)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	var hp := int(w.swarm.hp[slot])
	for i in 300:
		w.step(DT, MoveInput.new())
	assert_eq(int(w.swarm.hp[slot]), hp, "nothing swings without a skill")
	for e: Dictionary in w.drain_events():
		assert_ne(String(e.type), "basic_attack")


func test_a_skill_naming_a_weapon_casts_with_any_weapon() -> void:
	var w := _world()
	w.book.defs.energy_bolt["weapon_families"] = ["claw"]
	assert_eq(w.held_weapon_family(), WeaponInfo.family(w.weapon_id()))
	assert_ne(w.held_weapon_family(), "claw")
	RF.put_mob(w, int(RF.MOB_INFO.keys()[0]), 520)
	var cast := false
	for i in 120:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			cast = cast or (e.type == "cast" and String(e.skill) == "energy_bolt")
	assert_true(cast, "Energy Bolt casts though its data names a claw (weapons gate no skill)")
	assert_has(w.upgrades.eligible(w), "energy_bolt_rank", "and its cards stay on offer")

func test_mobility_ranks_follow_round_level_without_cards() -> void:
	var w := RF.quiet_world()
	assert_eq(w.loadout.rank("teleport_fp"), 1)
	for level in range(2, 41):
		w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		w.step(DT, MoveInput.new())
		while w.state == RunWorld.CHOOSING_UPGRADE:
			w.apply_choice(String(w.pending_cards[0].id))
		if level == 20:
			assert_eq(w.loadout.rank("teleport_fp"), 10)
	assert_eq(w.loadout.rank("teleport_fp"), 20, "mobility reaches its cap at level 40")
	assert_false("teleport_fp_rank" in w.upgrades.eligible(w))
