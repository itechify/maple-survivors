extends TestCase
## Save format 3 (spec #282, #286): the character keeps its identity and belongings between rounds, never its build.
## Seam: RunWorld.character_snapshot() out, RunWorld.new({character}) back in, JSON in between.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## The keys a format-3 character persists when it has no cash equipment and no pet (independent literal).
const KEYS := ["equipment", "format", "job_id", "look", "mesos", "scrolls", "tiers_unlocked"]


func _json_round_trip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value))


func test_snapshot_holds_only_identity_and_belongings() -> void:
	var w := RF.quiet_world(400.0, 1)
	var keys := w.character_snapshot().keys()
	keys.sort()
	assert_eq(keys, KEYS)
	assert_eq(w.character_snapshot().format, 3)
	assert_eq(w.character_snapshot().job_id, 212)
	assert_eq(w.character_snapshot().tiers_unlocked, 1, "tier 1 is always unlocked")


func test_round_trip_keeps_belongings_and_restarts_the_build() -> void:
	var w := RF.quiet_world(400.0, 1)
	# Earn a build in the round: levels, a learned skill, a rank, mods.
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(12) + 5, 4000019)
	for tick in 120:
		BotInput.auto_choose(w, false)
		w.step(DT, MoveInput.new())
	BotInput.auto_choose(w, false)
	assert_eq(w.progression.level, 12)
	w.learn_skill("fire_arrow")
	w.loadout.set_rank("fire_arrow", 5)
	w.loadout.add_player_mod("fortune", "add", 12.0)
	w.mesos = 4321
	w.scrolls["2043700"] = 3
	w.character_look = {"skin": 0, "face": 20000, "hair": 30030}
	var snapshot := w.character_snapshot()
	assert_eq(snapshot.mesos, 4321)
	assert_eq(snapshot.scrolls, {"2043700": 3})
	var setup := RF.setup("quiet", 2, RF.quiet_data())
	setup.character = _json_round_trip(snapshot)
	var next := RunWorld.new(setup)
	assert_eq(next.character_snapshot(), snapshot, "belongings, look and unlocks survive the JSON round trip")
	assert_eq(next.progression.level, 1, "every round starts at Lv1")
	assert_eq(next.progression.exp, 0)
	assert_false(next.loadout.has("fire_arrow"), "no skill is carried")
	assert_eq(next.loadout.player_mods, {}, "no card modifier is carried")
	assert_eq(next.player_state.fortune, 0.0)
	assert_eq(next.player_state.hp, next.player_state.max_hp)
	assert_true(next.loadout.has("energy_bolt"), "the job's start skills are learned again")


## A quiet two-boss world on the first tier (stage "quiet" listed in tier index `tier`), god mode off for deaths.
func _round(tier: int = 0, unlocked: int = 1) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.stages["tiers"] = [["other"], ["other2"]]
	data.stages.tiers[tier].append("quiet")
	RF.set_bosses(data.stages.stages.quiet, [
		{"time": 0.1, "mob_id": 2220000, "hp_mult": 1.0, "rewards": {"exp_mult": 1, "bonus_choices": 0}}])
	var setup := RF.setup("quiet", 20, data)
	setup.character = {"format": 3, "job_id": 212, "look": {}, "equipment": Equipment.empty_state(),
		"scrolls": {}, "mesos": 100, "tiers_unlocked": unlocked}
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	for i in 20:
		w.step(DT, MoveInput.new())
	return w


func _clear(w: RunWorld) -> void:
	w.hit_mob(int(w.bosses.records[0].slot), {"damage_min": 1000000.0, "damage_max": 1000000.0,
		"magic": false, "crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	for i in 3:
		w.step(DT, MoveInput.new())
	RF.auto_choose(w)
	assert_eq(w.state, RunWorld.CLEARED)


func _die(w: RunWorld) -> void:
	w.god = false
	w.upkeep.invincible_t = 0.0
	w.take_hit(1000000.0, false, "", w.player.pos + Vector2(20, 0), {"accuracy": 100000.0})
	assert_eq(w.state, RunWorld.DEAD)


func test_clearing_a_stage_of_tier_one_unlocks_tier_two() -> void:
	var w := _round(0, 1)
	assert_eq(w.character_snapshot().tiers_unlocked, 1, "nothing before the clear")
	_clear(w)
	assert_eq(w.character_snapshot().tiers_unlocked, 2)


func test_dying_unlocks_nothing() -> void:
	var w := _round(0, 1)
	_die(w)
	assert_eq(w.character_snapshot().tiers_unlocked, 1)


func test_unlocks_never_go_back_or_past_the_last_tier() -> void:
	var replay := _round(0, 2)
	_clear(replay)
	assert_eq(replay.character_snapshot().tiers_unlocked, 2, "replaying tier 1 keeps tier 2")
	var last := _round(1, 2)
	_clear(last)
	assert_eq(last.character_snapshot().tiers_unlocked, 2, "no tier 3 to unlock")
	var dead_later := _round(1, 2)
	_die(dead_later)
	assert_eq(dead_later.character_snapshot().tiers_unlocked, 2, "a death never takes an unlock away")


func test_the_unlock_rule_alone() -> void:
	assert_eq(CharacterSnapshot.unlocked_after_round(1, 0, true, 2), 2)
	assert_eq(CharacterSnapshot.unlocked_after_round(1, 0, false, 2), 1)
	assert_eq(CharacterSnapshot.unlocked_after_round(0, 0, false, 2), 1, "tier 1 is always unlocked")
	assert_eq(CharacterSnapshot.unlocked_after_round(2, 1, true, 3), 3)
	assert_eq(CharacterSnapshot.unlocked_after_round(2, 0, true, 3), 2)


func test_a_death_keeps_what_the_round_picked_up() -> void:
	var w := _round(0, 1)
	w.spawn_meso(w.player.pos, 250)
	w.spawn_equipment(w.player.pos, {"id": 1002001, "stats": {"incPDD": 4}, "slots": 7, "scrolls": 0})
	w.scrolls["2043700"] = 2
	for i in 60:
		w.step(DT, MoveInput.new())
	assert_eq(w.mesos, 350, "the meso drop was picked up")
	assert_eq(Equipment.held_ids(w.equipment), [1002001], "the equipment drop was picked up (and worn)")
	_die(w)
	var kept := w.character_snapshot()
	assert_eq(kept.mesos, 350)
	assert_eq(kept.scrolls, {"2043700": 2})
	assert_eq(Equipment.held_ids(kept.equipment), [1002001])
