extends TestCase
## Dark Knight fixed-tick event oracle (spec #348, D10 #358), synthetic assets, seed 1, bot, invulnerable. The same recipe as
## Hero's (test_hero_baseline): the pre-#241 opening and whole-round curve, the initial player state in the digest (job-local
## starting HP), and the synthetic spear swing reach of RF.with_basic_attack (so weapon-reach skills have a reach and the replay
## casts; Hero's first oracle lacked it, #346). The Spear is worn and every pool skill, Rush and the Beholder are defined with
## the D1-D9 test numbers (dark_knight_fixtures.gd). It runs 4 minutes (14400 ticks): a small independent replay regression, not
## balance evidence. A later ticket that moves GOLDEN must say why next to the constant.

const DKF := preload("res://tests/fixtures/dark_knight_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const GOLDEN := "6ca5b3f99b1ba5a3ba319dbd0ef7995c9f059011230fa95ff4b92cb85dd0690b"
## Capture: 14400 ticks, 107 casts, 8 skills held (4 minutes, seed 1).
const TICKS := 14400


func _event_digest(ticks: int) -> Dictionary:
	var data := DataRepo.load_all()
	# Tier C: freeze the pre-#241 opening so the schema/key migration must reproduce the existing golden unchanged.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := DKF.setup("henesys", 1, data)
	var w := RunWorld.new(setup)
	w.equipment.worn.weapon = Equipment.create(DKF.SPEAR, {"incPAD": 32})
	w.refresh_player_stats()
	# Keep this oracle on the historical whole-round pool curve as well as the historical opening.
	var legacy_curve: Dictionary = data.stages.stages.henesys.duplicate(true)
	legacy_curve.erase("maps")
	w.director = SpawnDirector.create(legacy_curve, w.kind_of_id, data.balance.get("spawn", {}))
	w.god = true
	var memo := {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(w.player_state))
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			event.erase("collector")
		digest.update(var_to_bytes(events))
	return {"digest": digest.finish().hex_encode(), "casts": w.runner.casts, "job": int(w.player_state.job_id), "learned": w.loadout.order.size()}


func test_dark_knight_event_stream_is_reproducible_and_matches_golden() -> void:
	var first := _event_digest(TICKS)
	assert_eq(first.job, 132, "the replay is a Dark Knight round")
	assert_true(first.casts > 0, "the replay exercises casts (%d)" % first.casts)
	assert_true(first.learned >= 3, "the bot took cards: %d skills" % first.learned)
	var second := _event_digest(TICKS)
	assert_eq(second.digest, first.digest, "two independent seeded rounds")
	assert_eq(first.digest, GOLDEN, "four-minute Dark Knight replay")
