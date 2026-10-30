extends TestCase
## Marksman fixed-tick event oracle (spec #360, MS10 #370), synthetic assets, seed 1, bot, invulnerable: the event stream of a
## Henesys round of a Marksman (322) holding a crossbow, with all ten pool skills defined. It sits beside the F/P
## (`test_character_baseline`), Hero (`test_hero_baseline`) and Bowmaster (`test_bowmaster_baseline`) goldens and pins the whole
## Marksman stack (crossbow arrows, the piercing rise, fixed-share Snipe, the area strikes, the two followers, the crossbow ammo
## schedule, bot picks) so later work (MS11 QA, the balance pass) cannot move it unnoticed. The recipe is Bowmaster's: the
## pre-#241 opening and whole-round pool curve, the same bot and `var_to_bytes` digest, initial player stats included.
## Captured LAST in the spec's selection ticket (after MS1-MS9 merged): a change to any Marksman skill, shared combat mechanics
## or the bot must either leave GOLDEN alone or re-capture it with the cause written next to the constant.

const MF := preload("res://tests/fixtures/marksman_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 28800 # eight minutes of run time: the six actives have filled and the crossbow ammo has stepped
const GOLDEN := "fd8a41136aadef79e8afebc1a0a9c46038b814e46e6738dd81366f46cfd1fde1"


## {"digest": hex, "skills": {skill key: hits}, "casts": int, "picked": [keys the bot learned], "upgrades": int, "level": int} of the first `ticks` of the round.
func _replay(ticks: int) -> Dictionary:
	var data := DataRepo.load_all()
	# tier C: freeze the pre-#241 opening and whole-round pool curve, as the F/P, Hero and Bowmaster oracles do.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := MF.setup("henesys", 1, data)
	# The creation outfit with the creation crossbow, frozen explicitly like the Bowmaster oracle's.
	setup.character = {"format": 3, "job_id": 322, "look": {},
		"equipment": {"worn": Equipment.worn_from_ids([1040002, 1060002, 1072001, MF.CROSSBOW], setup.equipment_info), "inventory": []},
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
	var upgrades := 0
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			event.erase("collector")
			if event.type == "mob_hit" and event.has("skill"):
				skills[String(event.skill)] = int(skills.get(String(event.skill), 0)) + 1
			elif event.type == "ammo_upgraded":
				upgrades += 1
		digest.update(var_to_bytes(events))
	var picked: Array = w.loadout.order.duplicate()
	return {"digest": digest.finish().hex_encode(), "skills": skills, "casts": w.runner.casts, "picked": picked, "upgrades": upgrades, "level": w.progression.level}


func test_marksman_event_stream_is_reproducible_and_matches_golden() -> void:
	var first := _replay(TICKS)
	assert_true(int(first.casts) > 0, "the replay exercises casts")
	for key: String in ["iron_arrow", "strafe_crossbow", "blizzard_crossbow", "snipe", "piercing_arrow", "golden_eagle"]:
		assert_true(int(first.skills.get(key, 0)) > 0, "%s landed hits in the replay: %s" % [key, first.skills])
	assert_true(int(first.upgrades) > 0, "the crossbow ammo schedule stepped the bolts")
	assert_eq(_replay(TICKS).digest, first.digest, "two independent seeded rounds")
	assert_eq(first.digest, GOLDEN, "eight-minute Marksman replay")
