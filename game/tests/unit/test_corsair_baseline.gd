extends TestCase
## Corsair fixed-tick event oracle (spec #384, C14 #398), synthetic assets, seed 1, bot, invulnerable: the event stream of a Henesys
## round of a Corsair (522) holding the Pistol, with the thirteen pool skills defined (Dash is the mobility skill). It sits beside the
## F/P (`test_character_baseline`), Hero, I/L, Paladin and Bowmaster goldens and pins the whole Corsair stack (the gun skills, the
## turret and kamikaze summons, the mark, the cones' burn and freeze, the bursts, Aerial Strike, the Battleship, the ammo schedule,
## the bot's picks) so later work (C15 QA, the balance pass, a Marksman line) cannot move it unnoticed. The recipe is Bowmaster's:
## the pre-#241 opening and whole-round pool curve, the same bot and `var_to_bytes` digest, initial player stats included.
## The pool is FROZEN here: `skill_pool` is written out below, so a fourteenth skill added to the shipped job cannot change the
## replay. Captured at C14, after C1-C13 merged (all thirteen existed), so the QA ticket does not need to widen or recapture it.
## A change to a Corsair skill, shared combat mechanics or the bot must either leave GOLDEN alone or re-capture it with the cause
## written next to the constant.

const CF := preload("res://tests/fixtures/corsair_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 21600 # six minutes of run time: the six slots are full and every kind of event below has happened
const GOLDEN := "a5590d4ad8e1355172a1bfc80c4496eee1d7af9456314dab8566c791b7d1b55b"
## The frozen pool: the thirteen actives of C4-C13, in the shipped order.
const POOL := ["double_shot", "burst_fire", "invisible_shot", "recoil_shot", "grenade", "flamethrower", "ice_splitter", "octopus",
	"gaviota", "homing_beacon", "aerial_strike", "rapid_fire", "battleship"]


## {"digest": hex, "skills": {skill key: hits}, "casts": int, "picked": [keys the bot learned], "types": {event type: count}} of the
## first `ticks` of the round.
func _replay(ticks: int) -> Dictionary:
	var data := DataRepo.load_all()
	# tier C: freeze the pre-#241 opening and whole-round pool curve, as the F/P, Hero and Bowmaster oracles do.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	# The Corsair is unplayable until C15 and its pool is frozen: both in this test's data copy only.
	data.jobs_survivor.jobs["522"]["playable"] = true
	data.jobs_survivor.jobs["522"]["skill_pool"] = POOL.duplicate()
	var setup := CF.setup("henesys", 1, data)
	# The creation outfit with the creation Pistol, frozen explicitly like the Bowmaster oracle's.
	setup.character = {"format": 3, "job_id": 522, "look": {},
		"equipment": {"worn": Equipment.worn_from_ids([1040002, 1060002, 1072001, CF.PISTOL], setup.equipment_info), "inventory": []},
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
	var types := {}
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			event.erase("collector")
			types[String(event.type)] = int(types.get(String(event.type), 0)) + 1
			if event.type == "mob_hit" and event.has("skill"):
				skills[String(event.skill)] = int(skills.get(String(event.skill), 0)) + 1
		digest.update(var_to_bytes(events))
	var picked: Array = w.loadout.order.duplicate()
	return {"digest": digest.finish().hex_encode(), "skills": skills, "casts": w.runner.casts, "picked": picked, "types": types}


func test_corsair_event_stream_is_reproducible_and_matches_golden() -> void:
	var first := _replay(TICKS)
	assert_true(int(first.casts) > 0, "the replay exercises casts")
	# The bot's six slots at seed 1: Double Shot, Recoil Shot, Ice Splitter, Homing Beacon, Gaviota and Rapid Fire land hits; Dash is
	# learned at the start and the Battleship, Octopus, Flamethrower, Burst Fire, Grenade, Invisible Shot and Aerial Strike are not taken.
	for key: String in ["double_shot", "recoil_shot", "ice_splitter", "homing_beacon", "gaviota", "rapid_fire"]:
		assert_true(int(first.skills.get(key, 0)) > 0, "%s landed hits in the replay: %s" % [key, first.skills])
	for key: String in ["dash", "gaviota"]:
		assert_true(key in first.picked, "%s was learned: %s" % [key, first.picked])
	for type: String in ["summon_spawn", "summon_attack", "mob_status_applied", "burst_start"]:
		assert_true(int(first.types.get(type, 0)) > 0, "%s happened" % type)
	assert_eq(_replay(TICKS).digest, first.digest, "two independent seeded rounds")
	assert_eq(first.digest, GOLDEN, "six-minute Corsair replay")
