extends TestCase
## Deterministic balance records and aggregation through seeded worlds and the public harness seam.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const DT := 1.0/60.0


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
	w.spend_mp(int(w.player_state.mp)-5)
	var whole := w.take_hit(40, false, "", w.player.pos+Vector2(10, 0), {"boss": true, "mob_id": 2220000, "source_kind": "attack"})
	w.learn_skill("energy_bolt")
	RF.put_mob(w, 1110100, 500, 190, 100)
	w.mob_kinds[int(w.kind_of_id[1110100])].move_speed = 0
	w.god = true
	var r: Dictionary = BR.run_one(w, "bot", 26)
	assert_near(r.mp_short_seconds, 1.0, DT, "fixed ticks count eligible skill waiting")
	assert_eq(r.boss_hits.size(), 1)
	assert_eq(r.boss_hits[0].source_kind, "attack")
	assert_true(int(r.boss_hits[0].mp_absorbed)>0, "Magic Guard absorbed part of this hit")
	assert_near(r.boss_hits[0].fraction, float(whole)/50.0, 0.000001, "fraction uses whole hit before Guard and HP pool at hit time")
	assert_eq(r.boss_hit_fraction.count, 1)
	assert_eq(r.state, "TIMEOUT")


## The harness records actual canonical casts, rather than inferring active buffs from the final rank.
func test_buff_cast_timeline_records_seeded_canonical_snapshots() -> void:
	for rank: int in [1, 5]:
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

func test_boss_fight_record_is_spawn_to_death_and_timeout_is_censored() -> void:
	var data := RF.quiet_data()
	data.balance.run_time_cap = 4.0
	data.stages.stages.quiet.bosses = [{"time": 0.5, "mob_id": 100100}]
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
	data.stages.stages.quiet.bosses = [{"time": 900.0, "mob_id": 100100, "hp_mult": 1000.0}]
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
	data.stages.stages.quiet.map_id = map_id
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
	var common := {"bosses": [], "camper": {"reached": false, "started_time": -1.0}}
	var first := common.merged({"potions_collected": {"hp": 2, "mp": 3}, "potions_used": {"hp": 1, "mp": 1}, "mp_short_seconds": 10.0,
		"boss_hits": [{"mob_id": 2220000, "fraction": 0.4, "source_kind": "touch"}],
		"boss_fights": [{"mob_id": 2220000, "duration": 30.0, "elapsed": 30.0, "status": "dead"}]})
	var second := common.merged({"potions_collected": {"hp": 4, "mp": 5}, "potions_used": {"hp": 0, "mp": 2}, "mp_short_seconds": 20.0,
		"boss_hits": [{"mob_id": 2220000, "fraction": 0.5, "source_kind": "attack"}],
		"boss_fights": [{"mob_id": 2220000, "duration": -1.0, "elapsed": 80.0, "status": "alive"}]})
	var summary: Dictionary = BR.aggregate([first, second])
	assert_eq(summary.potions_collected, {"hp": 6, "mp": 8})
	assert_eq(summary.potions_used, {"hp": 1, "mp": 3})
	assert_true(summary.has("mp_collected_used_ratio"), "policy summary exposes collected/used MP ratio")
	if summary.has("mp_collected_used_ratio"):
		assert_near(summary.mp_collected_used_ratio, 2.666666667, 0.000001, "ratio of totals, not mean of per-run ratios")
	assert_true(BR.describe_metrics(summary).contains("MP collected/used 2.667"))
	assert_eq(summary.mp_short_seconds.median, 15.0)
	assert_eq(summary.boss_fights["2220000"].completed.count, 1)
	assert_eq(summary.boss_fights["2220000"].completed.median, 30.0, "unfinished eighty seconds is not a completed fight sample")
	assert_eq(summary.boss_fights["2220000"].alive, 1)
	assert_near(summary.boss_hit_fraction.median, 0.45, 0.000001)
	assert_eq(summary.boss_hits["2220000"].by_source.touch.median, 0.4)
	assert_eq(summary.boss_hits["2220000"].by_source.attack.median, 0.5)


func test_summary_reports_undefined_ratio_when_no_mp_is_used() -> void:
	for records: Array in [[], [{"potions_collected": {"mp": 7}, "potions_used": {"mp": 0}}]]:
		var summary: Dictionary = BR.aggregate(records)
		assert_eq(summary.mp_collected_used_ratio, null, "zero use cannot produce a finite collected/used ratio")
		assert_true(BR.describe_metrics(summary).contains("MP collected/used undefined (no MP used)"))
	var none_collected: Dictionary = BR.aggregate([{"potions_collected": {"mp": 0}, "potions_used": {"mp": 2}}])
	assert_eq(none_collected.mp_collected_used_ratio, 0.0, "zero collection with positive use is a defined zero")
	assert_true(BR.describe_metrics(none_collected).contains("MP collected/used 0.000"))


func test_run_records_each_potion_kind_collected_and_drunk() -> void:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.run_time_cap = 1.0
	var w := RunWorld.new(RF.setup("quiet", 26, data))
	RF.place_player(w, 400)
	w.spawn_potion("hp", w.player.pos-Vector2(0, 25), 2)
	w.spawn_potion("mp", w.player.pos-Vector2(0, 25), 4)
	w.spend_mp(int(w.player_state.mp))
	w.drink_potion("hp")
	var r: Dictionary = BR.run_one(w, "bot", 26)
	assert_eq(r.potions_collected, {"hp": 2, "mp": 4})
	assert_eq(r.potions_used, {"hp": 1, "mp": 1})
