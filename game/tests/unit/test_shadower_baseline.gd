extends TestCase
## Shadower fixed-tick event oracle (spec #425, SH13 #438), synthetic assets, seed 1, bot, invulnerable: the event stream of a
## Henesys round of a Shadower (422) holding a dagger, with the nine pool skills, Assaulter and Assassinate defined. It sits beside
## the F/P (`test_character_baseline`), Hero, Bowmaster and Night Lord goldens and pins the whole Shadower stack (the dagger skills,
## the hidden form and its sub-skill, the safe zone, the meso charge and its finisher, Ninja Ambush, Assaulter, bot picks) so later
## work (SH14 QA, the balance pass, a Marksman line) cannot move it unnoticed. The recipe is the Night Lord oracle's: the pre-#241
## opening, whole-round pool curve, the same bot and `var_to_bytes` digest, initial player stats included.
## Shadower is playable since SH14 #439; the flip itself moves nothing (no code reads the flag inside a round). SH14's HP baseline
## (Hero's melee 600 start / 65 growth, `jobs/shadower.json`) DID move both goldens: see the cause next to each. A change to any Shadower skill, shared combat mechanics or the bot must either leave
## GOLDEN alone or re-capture it with the cause written next to the constant.

const SF := preload("res://tests/fixtures/shadower_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 21600 # six minutes of run time, the length of the Night Lord and Corsair oracles
## The shipped pool, as the bot takes it at seed 1: Double Stab, Assaulter, Steal, Band of Thieves, Ninja Ambush, Meso Explosion and
## Dark Sight fill the six actives; Boomerang Step, Savage Blow and Smokescreen are never offered in time.
## Recaptured by SH14 #439 (was 4a7a6a0e705ad262721d92019fe1d66d48fa47c42a0180f96b60172cfcd30a72). Cause: the HP baseline only
## (`balance.player.ap["422"].hp` 600 and `balance.growth["422"].hp` 65, Hero's melee numbers, tier C #346): the initial
## `player_state` is hashed and the round's hits, regen and potions change with the pool of HP. With the two HP rows removed from
## the data the old hash reproduced exactly, so neither the `playable` flip nor anything else moved it.
const GOLDEN := "1d6313f323a30b6c6c75b5e0537f98c3f3198b2950a8a150dcdd6e6bde6ec910"
## Second oracle: the pool frozen to the three skills the first one leaves out (Boomerang Step, Savage Blow, Smokescreen), so the
## stun line, the five-line Savage Blow and the safe zone with its negated hits are pinned too.
const OUTSIDERS := ["boomerang_step", "savage_blow", "smokescreen"]
## Recaptured by SH14 #439 for the same cause (was 38eac8d13529543734a706e0ab4955db57d50c43253e4e10b6956032eaab313f; the old hash
## reproduced exactly with the HP rows removed).
const GOLDEN_OUTSIDERS := "9405eac0a78bc0b476efabfe2cc3f766297bc531dd1c1e785c3a4b11b3a537a6"


## {"digest": hex, "skills": {skill key: hits}, "casts": int, "picked": [keys the bot learned], "assaults": int, "forms": int,
## "zones": int, "negated": int, "explosions": int, "mesos": int} of the first `ticks` of the round.
func _replay(ticks: int, pool: Array = []) -> Dictionary:
	var data := DataRepo.load_all()
	if not pool.is_empty():
		data.jobs_survivor.jobs["422"]["skill_pool"] = pool.duplicate()
	# tier C: freeze the pre-#241 opening and whole-round pool curve, as the F/P, Hero, Bowmaster and Night Lord oracles do.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := SF.setup("henesys", 1, data)
	# The creation outfit with the creation dagger (the Razor), frozen explicitly like the Night Lord oracle's claw.
	setup.character = {"format": 3, "job_id": 422, "look": {},
		"equipment": {"worn": Equipment.worn_from_ids([1040002, 1060002, 1072001, SF.DAGGER], setup.equipment_info), "inventory": []},
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
	var counts := {}
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			event.erase("collector")
			counts[String(event.type)] = int(counts.get(String(event.type), 0)) + 1
			if event.type == "mob_hit" and event.has("skill"):
				skills[String(event.skill)] = int(skills.get(String(event.skill), 0)) + 1
		digest.update(var_to_bytes(events))
	var picked: Array = w.loadout.order.duplicate()
	return {"digest": digest.finish().hex_encode(), "skills": skills, "casts": w.runner.casts, "picked": picked, "counts": counts}


func test_shadower_event_stream_is_reproducible_and_matches_golden() -> void:
	var first := _replay(TICKS)
	assert_true(int(first.casts) > 0, "the replay exercises casts")
	for key: String in ["double_stab", "steal", "band_of_thieves", "assaulter", "ninja_ambush_shadower", "meso_explosion", "assassinate"]:
		assert_true(int(first.skills.get(key, 0)) > 0, "%s landed hits in the replay: %s" % [key, first.skills])
	for key: String in ["dark_sight", "meso_explosion", "ninja_ambush_shadower", "band_of_thieves", "steal"]:
		assert_true(key in first.picked, "the bot took %s: %s" % [key, first.picked])
	assert_true(int(first.counts.get("form_started", 0)) > 0 and int(first.counts.get("form_ended", 0)) > 0, "Dark Sight windows opened and closed")
	assert_true(int(first.counts.get("meter_changed", 0)) > 0, "mesos charged the Shadower meter")
	assert_true(int(first.counts.get("meso_picked", 0)) > 0)
	assert_true(int(first.counts.get("mob_status_applied", 0)) > 0, "something was stunned")
	assert_eq(_replay(TICKS).digest, first.digest, "two independent seeded rounds")
	assert_eq(first.digest, GOLDEN, "six-minute Shadower replay")


func test_the_three_skills_the_first_replay_leaves_out_are_pinned_too() -> void:
	var first := _replay(TICKS, OUTSIDERS)
	for key: String in OUTSIDERS:
		assert_true(key in first.picked, "the bot took %s: %s" % [key, first.picked])
	for key: String in ["boomerang_step", "savage_blow"]:
		assert_true(int(first.skills.get(key, 0)) > 0, "%s landed hits: %s" % [key, first.skills])
	assert_true(int(first.counts.get("safe_zone_started", 0)) > 0, "Smokescreen placed a zone: %s" % first.counts)
	assert_eq(_replay(TICKS, OUTSIDERS).digest, first.digest, "two independent seeded rounds")
	assert_eq(first.digest, GOLDEN_OUTSIDERS, "six-minute replay of the three outsiders")
