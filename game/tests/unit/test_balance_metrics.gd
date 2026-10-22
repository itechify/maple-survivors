extends TestCase
## Deterministic balance records and aggregation through seeded worlds and the public harness seam.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const PF := preload("res://tests/fixtures/pet_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const REPORT := preload("res://tools/balance_report.gd")
const DT := 1.0/60.0


func test_rarity_report_counts_offers_and_picks_including_queued_boss_rewards() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = DT
	data.upgrades.rarity.weights = {"normal": 1.0}
	data.upgrades.cards = [{"id": "count", "kind": "skill_mod", "skill": "three_snails", "max_rank": 4,
		"effects": [{"stat": "count", "op": "add", "value": 1}]}]
	var w := RunWorld.new(RF.setup("quiet", 43, data))
	w.pending_bonus_choices = 2
	var r := BR.run_one(w, "first", 43)
	var offered := {"normal": 2, "rare": 2, "epic": 0, "unique": 0, "legendary": 0}
	var picked := {"normal": 0, "rare": 2, "epic": 0, "unique": 0, "legendary": 0}
	assert_eq(r.get("card_tiers_offered", {}), offered, "each boss window offers one Rare card and one Normal Elixir")
	assert_eq(r.get("card_tiers_picked", {}), picked, "the two Rare picks each count once, irrespective of magnitude")
	var summary := BR.aggregate([r, r, {}])
	assert_eq(summary.get("card_tier_runs", 0), 2, "legacy records do not invent rarity observations")
	assert_eq(summary.get("card_tiers_offered", {}).get("rare", 0), 4)
	assert_eq(summary.get("card_tiers_picked", {}).get("rare", 0), 4)
	assert_true(BR.describe_metrics(summary).contains("cards Rare offered 4 picked 4"))


func test_unspawned_boss_diagnostics_round_trip_as_finite_json_without_mutating_the_world() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = DT
	RF.set_bosses(data.stages.stages.quiet, [{"time": 300.0, "mob_id": 2220000}])
	var world := RunWorld.new(RF.setup("quiet", 26, data))
	var record := BR.run_one(world, "bot", 26)
	var encoded := JSON.stringify(record)
	assert_false(encoded.contains("1e99999"), "unobserved distance is nullable rather than an overflowing JSON number")
	if encoded.contains("1e99999"):
		return
	var parser := JSON.new()
	assert_eq(parser.parse(encoded), OK, "a public run record round-trips through JSON")
	var decoded: Dictionary = parser.data
	assert_eq(decoded.bosses[0].best_distance, null)
	assert_eq(decoded.boss_fights[0].status, "not_spawned")
	assert_eq(decoded.state, "TIMEOUT")
	assert_true(is_inf(float(world.bosses.records[0].best_distance)), "the live simulation keeps its route sentinel")


func test_report_reader_normalizes_only_legacy_nonfinite_boss_diagnostics() -> void:
	var old := '{"bosses":[{"best_distance":1e99999}],"state":"DEAD","time":612.5,"seed":26}'
	var parsed: Dictionary = REPORT.parse_record(old)
	assert_eq(parsed.error, "", "preserved legacy records are readable")
	if parsed.error != "":
		return
	assert_eq(parsed.normalized_diagnostics, 1)
	assert_eq(parsed.record.bosses[0].best_distance, null)
	assert_eq(parsed.record.time, 612.5, "actual measurements are untouched")
	assert_eq(parsed.record.state, "DEAD")
	assert_true(old.contains("1e99999"), "normalization leaves source text intact")
	var current: Dictionary = REPORT.parse_record('{"bosses":[{"best_distance":42.25}],"state":"TIMEOUT"}')
	assert_eq(current.normalized_diagnostics, 0)
	assert_eq(current.record.bosses[0].best_distance, 42.25)


func test_record_counts_waiting_seconds_and_whole_boss_hit_fraction() -> void:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.run_time_cap = 1.0
	var w := RunWorld.new(RF.setup("quiet", 26, data))
	RF.place_player(w, 400)
	RF.change_job_bare(w, 200)
	w.learn_skill("magic_guard")
	w.loadout.set_rank("magic_guard", 5)
	w.step(DT, MoveInput.new())
	w.drain_events()
	w.drink_potion("mp") # Hold the shared cooldown so this test observes a full second of MP wait.
	w.spend_mp(int(w.player_state.mp)-5)
	var whole := w.take_hit(40, false, "", w.player.pos+Vector2(10, 0), {"boss": true, "mob_id": 2220000, "source_kind": "attack"})
	w.learn_skill("energy_bolt")
	RF.put_mob(w, 1110100, 500, 190, 100)
	w.mob_kinds[int(w.kind_of_id[1110100])].move_speed = 0
	w.god = true
	var r: Dictionary = BR.run_one(w, "bot", 26)
	assert_near(r.mp_short_seconds, 1.0 - DT, 0.001, "fixed ticks count eligible waiting through the absolute cap")
	assert_eq(r.boss_hits.size(), 1)
	assert_eq(r.boss_hits[0].source_kind, "attack")
	assert_true(int(r.boss_hits[0].mp_absorbed)>0, "Magic Guard absorbed part of this hit")
	assert_near(r.boss_hits[0].fraction, float(whole)/50.0, 0.000001, "fraction uses whole hit before Guard and HP pool at hit time")
	assert_eq(r.boss_hit_fraction.count, 1)
	assert_eq(r.state, "TIMEOUT")


## The harness records actual canonical casts, rather than inferring active buffs from the final rank.
func test_buff_cast_timeline_records_seeded_canonical_snapshots() -> void:
	for rank: int in [1, 20]:
		var data := RF.quiet_data()
		data.balance.player.skills = []
		data.balance.run_time_cap = 1.0
		var w := RunWorld.new(RF.setup("quiet", 27, data))
		RF.place_player(w, 400)
		RF.change_job_bare(w, 200)
		w.learn_skill("magic_guard")
		w.loadout.set_rank("magic_guard", rank)
		var r: Dictionary = BR.run_one(w, "bot", 27)
		assert_true(r.has("buff_casts"), "cast timeline is part of the public record")
		if not r.has("buff_casts"):
			continue
		assert_eq(r.buff_casts.size(), 1, "one inactive Guard cast in the one-second run")
		var cast: Dictionary = r.buff_casts[0]
		assert_near(cast.time, DT, 0.000001, "cast observed on the first fixed tick")
		assert_eq(cast.skill, "magic_guard")
		assert_eq(cast.skill_id, 2001002)
		assert_eq(cast.level, 1 if rank == 1 else 20)
		assert_eq(cast.duration, 111.0 if rank == 1 else 600.0, "canonical endpoint duration")
		assert_eq(cast.effect_stat, "mp_guard")
		assert_eq(cast.value, 11.0 if rank == 1 else 80.0, "cast-time canonical effect from the public snapshot")


func test_ordinary_kill_hits_follow_relocation_and_reset_on_same_kind_slot_reuse() -> void:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.run_time_cap = DT
	var w := RunWorld.new(RF.setup("quiet", 26, data))
	w.god = true
	var weak := {"magic": false, "damage_min": 5.0, "damage_max": 5.0, "crit": 0.0, "crit_mult": 1.5, "skill": "basic_attack"}
	var strong := weak.merged({"damage_min": 20.0, "damage_max": 20.0}, true)
	var mob := RF.put_mob(w, 100100, 500)
	w.hit_mob(mob, weak, -1)
	var moved := w.relocate_mob(mob, Vector2(600, 200), w.fhm.find_below(600, 190))
	assert_eq(moved, mob, "this relocation reuses its own freshly freed slot")
	w.hit_mob(moved, weak, -1)
	w.swarm.despawn(moved)
	var fresh := RF.put_mob(w, 100100, 600)
	assert_eq(fresh, moved, "a fresh mob reuses the same kind and slot")
	w.hit_mob(fresh, strong, -1)
	var elite := RF.put_mob(w, 100100, 700, 190, 1.0, true)
	w.hit_mob(elite, strong, -1)
	var r := BR.run_one(w, "bot", 26)
	assert_true(r.has("ordinary_kill_hits_by_min"), "public run record exposes landed lifetime hits per ordinary kill")
	if not r.has("ordinary_kill_hits_by_min"):
		return
	assert_eq(r.ordinary_kill_hits_by_min[0], {"hits": 3, "kills": 2, "mean": 1.5}, "relocation preserves two hits; fresh reuse starts from zero; elites excluded")
	assert_eq(r.ordinary_kill_hits_by_min[1], {"hits": 0, "kills": 0, "mean": null}, "no kills is an undefined mean")


func test_kill_hit_means_pool_lifetime_hits_over_kills_instead_of_averaging_run_means() -> void:
	var summary := BR.aggregate([
		{"ordinary_kill_hits_by_min": [{"hits": 6, "kills": 2, "mean": 3.0}]},
		{"ordinary_kill_hits_by_min": [{"hits": 1, "kills": 1, "mean": 1.0}]},
		{"ordinary_kill_hits_by_min": [{"hits": 0, "kills": 0, "mean": null}]},
	])
	assert_true(summary.has("ordinary_kill_hits_by_min"))
	if not summary.has("ordinary_kill_hits_by_min"):
		return
	assert_eq(summary.ordinary_kill_hits_by_min[0].hits, 7)
	assert_eq(summary.ordinary_kill_hits_by_min[0].kills, 3)
	assert_near(summary.ordinary_kill_hits_by_min[0].mean, 2.333333333, 0.000001)
	assert_eq(summary.ordinary_kill_hits_by_min[1].mean, null)
	assert_true(BR.describe_metrics(summary).contains("minute 1 ordinary hits/kill 2.333 (7 hits / 3 kills)"))


func test_hits_before_a_minute_boundary_belong_to_the_minute_of_death() -> void:
	var data := RF.quiet_data()
	data.balance.player.mp = 100
	data.balance.run_time_cap = 60.8
	var w := RunWorld.new(RF.setup("quiet", 26, data))
	RF.place_player(w, 400)
	w.god = true
	w.time = 59.8
	w.loadout.set_rank("three_snails", 3)
	var mob := RF.put_mob(w, 100100, 600, 190, 5.0)
	w.hit_mob(mob, {"magic": false, "damage_min": 5.0, "damage_max": 5.0, "crit": 0.0, "crit_mult": 1.5, "skill": "basic_attack"}, -1)
	var r := BR.run_one(w, "bot", 26, 0.0)
	assert_eq(r.ordinary_kill_hits_by_min[0].kills, 0)
	assert_eq(r.ordinary_kill_hits_by_min[1], {"hits": 2, "kills": 1, "mean": 2.0}, "earlier damage follows a mob killed by a later projectile")


func test_magic_claw_counts_each_landed_line_but_a_scheduled_boss_is_excluded() -> void:
	var data := RF.quiet_data()
	data.balance.player.mp = 100
	data.balance.player.skills = ["magic_claw"]
	data.skills.skills.magic_claw.damage = "fixed"
	data.balance.run_time_cap = 0.1
	var setup := RF.setup("quiet", 26, data)
	setup.skill_imgs["200"].skill["2001005"].level["1"]["fixdamage"] = 10.0
	var w := RunWorld.new(setup)
	w.god = true
	RF.place_player(w, 400)
	RF.put_mob(w, 100101, 500)
	var r := BR.run_one(w, "bot", 26, 0.0)
	assert_eq(r.ordinary_kill_hits_by_min[0], {"hits": 2, "kills": 1, "mean": 2.0})
	RF.set_bosses(data.stages.stages.quiet, [{"time": DT, "mob_id": 100101}])
	w = RunWorld.new(RF.setup("quiet", 26, data))
	w.setup.skill_imgs["200"].skill["2001005"].level["1"]["fixdamage"] = 10.0
	w.god = true
	RF.place_player(w, 400)
	r = BR.run_one(w, "bot", 26, 0.0)
	assert_eq(r.boss_fights[0].status, "dead", "the excluded boss really receives a killing cast")
	assert_eq(r.ordinary_kill_hits_by_min[0].kills, 0, "scheduled bosses do not require canonical info/boss")


func test_late_waits_have_observation_time_without_stock_metrics() -> void:
	var data := RF.quiet_data()
	data.balance.player.mp = 0
	data.balance.run_time_cap = 480.5
	var w := RunWorld.new(RF.setup("quiet", 26, data))
	w.god = true
	RF.place_player(w, 400)
	RF.put_mob(w, 1110100, 500, 190, 100.0)
	w.time = 479.5
	var r := BR.run_one(w, "bot", 26, 0.0)
	assert_true(r.has("late_mp_short_seconds"), "late shortages are measured separately")
	if not r.has("late_mp_short_seconds"):
		return
	assert_near(r.late_mp_short_seconds, 0.5, DT)
	assert_near(r.late_observed_seconds, 0.5, DT)
	assert_false(r.has("potions_left"))
	assert_false(r.has("potions_collected"))
	assert_false(r.has("potions_start"))
	var early := r.duplicate(true)
	early.late_mp_short_seconds = 0.0
	early.late_observed_seconds = 0.0
	var summary := BR.aggregate([r, early])
	assert_eq(summary.late_mp_observed_runs, 1)
	assert_eq(summary.late_mp_short_runs, 1)
	assert_eq(summary.late_mp_short_seconds.count, 1, "unobserved late time is excluded from shortage samples")


func test_summary_counts_clears_deaths_and_timeouts_separately() -> void:
	var summary := BR.aggregate([
		{"state": "CLEARED", "time": 1000.0}, {"state": "DEAD", "time": 600.0},
		{"state": "DEAD", "time": 800.0}, {"state": "TIMEOUT", "time": 1800.0},
	])
	assert_eq(summary.get("outcomes", {}), {"CLEARED": 1, "DEAD": 2, "TIMEOUT": 1})
	assert_eq(summary.get("death_seconds", {}).get("median"), 700.0, "death-only median excludes clear and censored timeout")

func test_boss_fight_record_is_spawn_to_death_and_timeout_is_censored() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = 4.0
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.5, "mob_id": 100100}])
	var w := RunWorld.new(RF.setup("quiet", 26, data))
	w.god = true
	RF.place_player(w, 400)
	var r: Dictionary = BR.run_one(w, "bot", 26)
	assert_eq(r.state, "CLEARED")
	assert_eq(r.boss_fights.size(), 1)
	var fight: Dictionary = r.boss_fights[0]
	assert_eq(fight.status, "dead")
	assert_between(fight.duration, 0.0, 3.5)
	assert_near(fight.duration, float(fight.death_time)-float(fight.spawn_time), 0.000001)
	data = RF.quiet_data()
	data.balance.player.skills = []
	data.balance.run_time_cap = 901.0
	data.stages.stages.quiet.duration = 900.0
	RF.set_bosses(data.stages.stages.quiet, [{"time": 900.0, "mob_id": 100100, "hp_mult": 1000.0}])
	w = RunWorld.new(RF.setup("quiet", 27, data))
	w.god = true
	r = BR.run_one(w, "bot", 27)
	assert_eq(r.state, "TIMEOUT", "900 is not a false clear with a surviving boss")
	assert_eq(r.boss_fights[0].status, "alive")
	assert_eq(r.boss_fights[0].duration, -1.0, "unfinished fights do not become completed samples")
	assert_near(r.boss_fights[0].elapsed, 1.0, DT)


func _real_map_world(map_id: int) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.stages.stages.quiet.maps[0].map_id = map_id
	var setup := RF.setup("quiet", 26, data)
	setup.map_img = AssetLibrary.get_default().img(DataRepo.map_img_path(map_id)).root
	var world := RunWorld.new(setup)
	world.god = true
	return world


func test_henesys_camper_policies_reach_top_and_hold_the_ground_rope() -> void:
	if not require_cache():
		return
	for policy: String in ["camper_henesys_top", "camper_henesys_rope"]:
		var w := _real_map_world(104040000)
		var memo := {}
		for tick in 120:
			w.step(DT, BR.movement(w, policy, memo, 0.0))
		assert_true(bool(memo.get("reached", false)), "camper reached its chosen canonical target")
		if policy.ends_with("rope"):
			assert_eq(w.player.state, PlayerMotion.ST_LADDER)
			assert_eq(w.ladders.is_ladder[w.player.ladder], 0)
		else:
			assert_eq(w.player.state, PlayerMotion.ST_STAND)
			assert_eq(w.player_platform(), int(memo.target_platform))
		var at := w.player.pos
		for tick in 120:
			w.step(DT, BR.movement(w, policy, memo, 0.0))
		assert_eq(w.player.pos, at, "campers stay hands off after arrival")


func test_tree_camper_reaches_top_via_the_original_portal_chain() -> void:
	if not require_cache():
		return
	var w := _real_map_world(101010100)
	var memo := {}
	var portals := []
	for tick in 60*30:
		w.step(DT, BR.movement(w, "camper_tree_top", memo, 0.0))
		for event: Dictionary in w.drain_events():
			if event.type == "portal_used":
				portals.append(event.portal)
		if bool(memo.get("reached", false)):
			break
	assert_eq(portals, ["up00", "up01", "up02"], "camper physically traverses the canonical local chain")
	assert_eq(w.player_platform(), 7)
	assert_true(bool(memo.get("reached", false)))


func test_summary_aggregates_potions_waits_and_only_completed_fights() -> void:
	var common := {"bosses": [], "camper": {"reached": false, "started_time": -1.0},
		"potions_start": {"hp": 5, "mp": 0}, "potions_left": {"hp": 20, "mp": 30},
		"pet": {"potions_used": {"hp": 7, "mp": 8}}}
	var first := common.merged({"potions_collected": {"hp": 2, "mp": 3}, "potions_used": {"hp": 1, "mp": 1}, "mp_short_seconds": 10.0,
		"boss_hits": [{"mob_id": 2220000, "fraction": 0.4, "source_kind": "touch"}],
		"boss_fights": [{"mob_id": 2220000, "duration": 30.0, "elapsed": 30.0, "status": "dead"}]})
	var second := common.merged({"potions_collected": {"hp": 4, "mp": 5}, "potions_used": {"hp": 0, "mp": 2}, "mp_short_seconds": 20.0,
		"boss_hits": [{"mob_id": 2220000, "fraction": 0.5, "source_kind": "attack"}],
		"boss_fights": [{"mob_id": 2220000, "duration": -1.0, "elapsed": 80.0, "status": "alive"}]})
	var summary: Dictionary = BR.aggregate([first, second])
	assert_eq(summary.potions_used, {"hp": 1, "mp": 3})
	for removed: String in ["potions_collected", "potions_start", "potions_left", "mp_collected_used_ratio"]:
		assert_false(summary.has(removed), "legacy input does not revive removed potion metrics: " + removed)
	var report := BR.describe_metrics(summary)
	assert_true(report.contains("potions used HP 1 MP 3; MP-short seconds"))
	assert_false(report.contains("potions collected"))
	assert_false(report.contains("MP collected/used"))
	assert_false(report.contains("final stock"))
	assert_eq(summary.mp_short_seconds.median, 15.0)
	assert_eq(summary.boss_fights["2220000"].completed.count, 1)
	assert_eq(summary.boss_fights["2220000"].completed.median, 30.0, "unfinished eighty seconds is not a completed fight sample")
	assert_eq(summary.boss_fights["2220000"].alive, 1)
	assert_eq(summary.boss_fights["2220000"].spawned, 2, "completed 1 of 2 spawned fights")
	assert_eq(summary.boss_fights["2220000"].censored_median,
		{"count": 2, "censored": 1, "median": 55.0, "lower_bound": true},
		"the unfinished fight counts as at least its 80 s, so the median is only a lower bound")
	var text := BR.describe_metrics(summary)
	assert_true(text.contains("completed 1/2 spawned; censored median >=55.00 (n=2, 1 unfinished)"), text)
	assert_false(text.contains("campers"), "ordinary policies print no camper count")
	assert_near(summary.boss_hit_fraction.median, 0.45, 0.000001)
	assert_eq(summary.boss_hits["2220000"].by_source.touch.median, 0.4)
	assert_eq(summary.boss_hits["2220000"].by_source.attack.median, 0.5)


func test_summary_reports_zero_drinks_without_collection_or_stock_metrics() -> void:
	for records: Array in [[], [{"potions_collected": {"mp": 7}, "potions_used": {"mp": 0}}]]:
		var summary: Dictionary = BR.aggregate(records)
		assert_eq(summary.potions_used, {"hp": 0, "mp": 0})
		assert_false(summary.has("mp_collected_used_ratio"))
		assert_true(BR.describe_metrics(summary).contains("potions used HP 0 MP 0"))


func test_summary_reports_observed_times_per_job() -> void:
	# Records from before job_times only had the Magician's job_t.
	var summary := BR.aggregate([{"job_t": 240.0}, {"job_t": 260.0}, {"job_t": -1.0}, {}])
	assert_true(summary.job_seconds.has("200"), "report includes advancement timing")
	assert_eq(summary.job_seconds["200"].count, 2, "unreached and missing times are not observations")
	assert_eq(summary.job_seconds["200"].median, 250.0)
	assert_true("Job 200 seconds 240.00/250.00/260.00 (n=2)" in BR.describe_metrics(summary))
	var absent := BR.aggregate([{"job_t": -1.0}, {}])
	assert_true(absent.job_seconds.is_empty())
	assert_true("Job seconds none (n=0)" in BR.describe_metrics(absent))
	var mixed := BR.aggregate([{"job_t": 240.0, "job_times": {"200": 240.0, "210": 1000.0}},
		{"job_t": 260.0, "job_times": {"200": 260.0, "220": 900.0}}, {"job_t": 300.0, "job_times": {"200": 300.0}}])
	assert_eq(mixed.job_seconds.keys(), ["200", "210", "220"], "every job id advanced into has its own times")
	assert_eq(mixed.job_seconds["200"].count, 3)
	assert_eq(mixed.job_seconds["210"].median, 1000.0)
	assert_eq(mixed.job_seconds["220"].count, 1)
	var text := BR.describe_metrics(mixed)
	assert_true("Job 210 seconds 1000.00/1000.00/1000.00 (n=1)" in text, text)
	assert_true("Job 220 seconds 900.00/900.00/900.00 (n=1)" in text, text)


func test_run_records_unlimited_potion_drinks_and_restore_amounts() -> void:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.run_time_cap = 1.0
	# Harness recording, not drinking policy: let the bot sip as soon as one point is missing.
	data.balance.potions.bot.min_restore_fraction = 0.01
	var w := RunWorld.new(RF.setup("quiet", 26, data))
	RF.place_player(w, 400)
	w.spend_mp(int(w.player_state.mp))
	w.drink_potion("hp")
	var r: Dictionary = BR.run_one(w, "bot", 26)
	assert_eq(r.potions_used, {"hp": 1, "mp": 1})
	for removed: String in ["potions_collected", "potions_start", "potions_left", "mp_collected_used_ratio"]:
		assert_false(r.has(removed), "unlimited drinks have no collection/stock metric: " + removed)
	assert_false(BR.describe(r.merged({"seed": 26})).contains("potions collected"))
	assert_true(r.has("potion_uses"), "actual restored amounts expose early potion clipping")
	if r.has("potion_uses"):
		var mp_uses: Array = r.potion_uses.filter(func(use: Dictionary) -> bool: return use.kind == "mp")
		assert_eq(mp_uses.size(), 1)
		assert_eq(mp_uses[0].restored, 5, "a Blue Potion restores only the five-MP opening pool")
		assert_eq(mp_uses[0].capacity_waste, 95, "canonical restoration beyond the pool capacity is explicit")


func test_pet_drinks_stay_separate_from_player_use_totals_and_timeline() -> void:
	var data := PF.data()
	data.balance.player.skills = []
	data.balance.run_time_cap = 1.0
	var world := PF.world([PF.KITTY, PF.AUTO_HP, PF.AUTO_MP], {"hp": 0.5, "mp": 0.5}, data)
	world.take_hit(40, false, "", world.player.pos + Vector2(10, 0))
	world.spend_mp(int(world.player_state.mp))
	var record := BR.run_one(world, "bot", 5, 0.0) # Hands off; only the pet can drink.
	assert_eq(record.pet.potions_used, {"hp": 1, "mp": 1})
	assert_eq(record.potions_used, {"hp": 0, "mp": 0})
	assert_eq(record.potion_uses, [], "the player's restore/waste timeline excludes pet events")
	assert_eq(BR.aggregate([record]).potions_used, {"hp": 0, "mp": 0})


func test_censored_fight_median_is_exact_only_when_no_unfinished_fight_lies_below_it() -> void:
	assert_eq(BR.censored_median([]), {"count": 0, "censored": 0, "median": null, "lower_bound": false})
	assert_eq(BR.censored_median([Vector2(30, 0), Vector2(40, 0), Vector2(200, 1)]),
		{"count": 3, "censored": 1, "median": 40.0, "lower_bound": false}, "a long unfinished fight cannot lower it")
	assert_eq(BR.censored_median([Vector2(30, 0), Vector2(10, 1), Vector2(40, 0)]),
		{"count": 3, "censored": 1, "median": 30.0, "lower_bound": true}, "an early unfinished fight may hide a longer one")


func test_camper_arrivals_are_counted_over_camper_runs_only() -> void:
	var camper := {"bosses": [], "boss_fights": [], "boss_hits": [],
		"camper": {"policy": "camper_tree_top", "started_time": 60.0, "reached": true}}
	var ordinary := {"bosses": [], "boss_fights": [], "boss_hits": [], "camper": {"policy": "", "started_time": -1.0}}
	var summary: Dictionary = BR.aggregate([camper, ordinary])
	assert_eq([summary.camper_runs, summary.camper_started, summary.camper_reached], [1, 1, 1])
	assert_true(BR.describe_metrics(summary).contains("campers reached 1/1 runs (1 started)"))


func test_forced_branch_is_recorded_and_summary_groups_outcomes() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = DT
	var w := RunWorld.new(RF.setup("quiet", 53, data))
	w.change_job(200)
	w.progression.level = 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	var r := BR.run_one(w, "bot", 53, -1.0, 60.0, 230)
	assert_eq(r.get("branch", 0), 230)
	assert_eq(r.get("forced_branch", 0), 230)
	assert_true(r.get("job_times") is Dictionary, "advancements are timed per job id (the one-tick cap leaves it empty)")
	var legacy := r.duplicate(true)
	legacy.erase("branch")
	legacy.state = "DEAD"
	var summary := BR.aggregate([r, r, legacy])
	assert_eq(summary.get("branches", {}).get("230", {}).get("runs", 0), 2)
	assert_eq(summary.get("branches", {}).get("230", {}).get("TIMEOUT", 0), 2)
	assert_eq(summary.get("branches", {}).get("unobserved", {}).get("DEAD", 0), 1)
	assert_true(BR.describe_metrics(summary).contains("SUMMARY branch 230"))


func test_records_carry_the_nx_a_round_would_pay_and_the_summary_reports_it() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = DT
	data.balance["nx_award"] = {"clear_bonus": [100], "per_level": 5, "per_boss": 40}
	var w := RunWorld.new(RF.setup("quiet", 71, data))
	RF.place_player(w, 400)
	w.progression.add_exp(w.progression.exp_to_next())
	w.progression.queue.clear()
	var r := BR.run_one(w, "bot", 71)
	assert_eq(r.get("levels_gained"), 1)
	assert_eq(r.get("bosses_killed"), 0)
	assert_eq(r.get("nx_awarded"), 5, "unfinished round: no clear bonus, one level")
	var legacy := r.duplicate(true)
	legacy.erase("nx_awarded")
	var summary := BR.aggregate([r, r, legacy])
	assert_eq(summary.nx_awarded.count, 2, "legacy records do not invent NX")
	assert_eq(summary.nx_awarded.median, 5)
	assert_true(BR.describe_metrics(summary).contains("NX awarded per run"))
	r["seed"] = 71
	assert_true(BR.describe(r).contains("NX awarded 5 (bosses killed 0, levels gained 1)"))
