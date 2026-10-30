extends TestCase
## Night Lord fixed-tick event oracle (spec #383, NL11 #410), synthetic assets, seed 1, bot, invulnerable: the event stream of a
## Henesys round of a Night Lord (412) holding a claw, with all eight pool skills and Flash Jump defined. It sits beside the F/P
## (`test_character_baseline`), Hero (`test_hero_baseline`) and Bowmaster (`test_bowmaster_baseline`) goldens and pins the whole
## Night Lord stack (stars, the echo clone, Flash Jump, the meso charge, status grants, zones, the ammo schedule, bot picks) so later
## work (NL12 QA, the balance pass, a Shadower line) cannot move it unnoticed. The recipe is Bowmaster's: the pre-#241 opening and
## whole-round pool curve, the same bot and `var_to_bytes` digest, initial player stats included.
## Captured LAST in the spec's selection ticket (after NL1-NL10 merged, ruling D12 applied): a change to any Night Lord skill,
## shared combat mechanics or the bot must either leave GOLDEN alone or re-capture it with the cause written next to the constant.

const NF := preload("res://tests/fixtures/night_lord_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 21600 # six minutes of run time: long enough for Flash Jump, both ninja skills and the first ammo step
const GOLDEN := "6077b1621513d89e067eda3a3dbce14355f8e96860454f6f0e3ef4d7363e0bd1"


## {"digest": hex, "skills": {skill key: hits}, "casts": int, "picked": [keys the bot learned], "flashes": int, "echoes": int,
## "upgrades": int} of the first `ticks` of the round.
func _replay(ticks: int) -> Dictionary:
	var data := DataRepo.load_all()
	# tier C: freeze the pre-#241 opening and whole-round pool curve, as the F/P, Hero and Bowmaster oracles do.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := NF.setup("henesys", 1, data)
	# The creation outfit with the creation claw (the Garnier), frozen explicitly like the Bowmaster oracle's.
	setup.character = {"format": 3, "job_id": 412, "look": {},
		"equipment": {"worn": Equipment.worn_from_ids([1040002, 1060002, 1072001, NF.CLAW], setup.equipment_info), "inventory": []},
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
	var flashes := 0
	var echoes := 0
	var upgrades := 0
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			event.erase("collector")
			if event.type == "mob_hit" and event.has("skill"):
				skills[String(event.skill)] = int(skills.get(String(event.skill), 0)) + 1
			elif event.type == "flash_jump":
				flashes += 1
			elif event.type == "echo_cast":
				echoes += 1
			elif event.type == "ammo_upgraded":
				upgrades += 1
		digest.update(var_to_bytes(events))
	var picked: Array = w.loadout.order.duplicate()
	return {"digest": digest.finish().hex_encode(), "skills": skills, "casts": w.runner.casts, "picked": picked, "flashes": flashes,
		"echoes": echoes, "upgrades": upgrades}


func test_night_lord_event_stream_is_reproducible_and_matches_golden() -> void:
	var first := _replay(TICKS)
	assert_true(int(first.casts) > 0, "the replay exercises casts")
	for key: String in ["lucky_seven", "drain", "triple_throw", "ninja_ambush", "ninja_storm"]:
		assert_true(int(first.skills.get(key, 0)) > 0, "%s landed hits in the replay: %s" % [key, first.skills])
	assert_true(int(first.echoes) > 0, "the Shadow Partner clone echoed stars")
	assert_true(int(first.flashes) > 0, "the bot flashed away from a close threat while airborne")
	assert_true(int(first.upgrades) > 0, "the claw schedule stepped the stars")
	assert_true(String("shadow_partner") in first.picked and String("flash_jump") in first.picked, "the bot took the clone")
	assert_eq(_replay(TICKS).digest, first.digest, "two independent seeded rounds")
	assert_eq(first.digest, GOLDEN, "six-minute Night Lord replay")
