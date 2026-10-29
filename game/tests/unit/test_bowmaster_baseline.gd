extends TestCase
## Bowmaster fixed-tick event oracle (spec #332, B12 #344), synthetic assets, seed 1, bot, invulnerable: the event stream of a
## Henesys round of a Bowmaster (312) holding a bow, with all ten pool skills defined. It sits beside the F/P (`test_character_baseline`)
## and Hero (`test_hero_baseline`) goldens and pins the whole Bowmaster combat stack (arrows, bursts, blasts, burn, followers,
## ammo schedule, bot picks) so later work (B13 tuning, a Marksman line) cannot move it unnoticed. The recipe is Hero's: the
## pre-#241 opening and whole-round pool curve, the same bot and `var_to_bytes` digest, initial player stats included.
## Captured LAST in the spec (after B7-B11 merged): a change to any Bowmaster skill, shared combat mechanics or the bot must
## either leave GOLDEN alone or re-capture it with the cause written next to the constant.

const BF := preload("res://tests/fixtures/bowmaster_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 14400 # four minutes of run time
const GOLDEN := "c1b3b654c469fde20e427d2eaa99b5afa99fb20a047c0302e5ea1ea7eb1c3e1b"


## {"digest": hex, "skills": {skill key: hits}, "casts": int} of the first `ticks` of the round.
func _replay(ticks: int) -> Dictionary:
	var data := DataRepo.load_all()
	# tier C: freeze the pre-#241 opening and whole-round pool curve, as the F/P and Hero oracles do.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := BF.setup("henesys", 1, data)
	# Review #332: freeze the original replay's sword outfit explicitly; bare tools now wear creation weapons.
	setup.character = {"format": 3, "job_id": 312, "look": {},
		"equipment": {"worn": Equipment.worn_from_ids(Equipment.DEFAULT_OUTFIT, setup.equipment_info), "inventory": []},
		"scrolls": {}, "mesos": 0, "tiers_unlocked": 1}
	var w := RunWorld.new(setup)
	var legacy_curve: Dictionary = data.stages.stages.henesys.duplicate(true)
	legacy_curve.erase("maps")
	w.director = SpawnDirector.create(legacy_curve, w.kind_of_id, data.balance.get("spawn", {}))
	w.god = true
	var memo := {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(w.player_state))
	var skills := {}
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			event.erase("collector")
			if event.type == "mob_hit" and event.has("skill"):
				skills[String(event.skill)] = int(skills.get(String(event.skill), 0)) + 1
		digest.update(var_to_bytes(events))
	return {"digest": digest.finish().hex_encode(), "skills": skills, "casts": w.runner.casts}


func test_bowmaster_event_stream_is_reproducible_and_matches_golden() -> void:
	var first := _replay(TICKS)
	assert_true(int(first.casts) > 0, "the replay exercises casts")
	assert_true((first.skills as Dictionary).size() >= 3, "several pool skills landed hits: %s" % [first.skills.keys()])
	assert_eq(_replay(TICKS).digest, first.digest, "two independent seeded rounds")
	assert_eq(first.digest, GOLDEN, "four-minute Bowmaster replay")
