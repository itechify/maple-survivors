extends TestCase
## Hero fixed-tick event oracle (H9/H10, spec #296), synthetic assets, seed 1, bot, invulnerable.
## Golden captured after all seven pool skills landed; repeated runs must reproduce it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const GOLDEN := "9adb0cee8138e1bf1aa6f91a2656e1cd4ad29f8552913269dbe08ec0cb841661"


func _event_digest(ticks: int) -> String:
	# Hero is explicit; the F/P oracle remains unchanged.
	var data := DataRepo.load_all()
	# Tier C: freeze the pre-#241 opening so the schema/key migration must reproduce the existing golden unchanged.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := RF.setup("henesys", 1, data)
	setup["job"] = 112
	var w := RunWorld.new(setup)
	# Keep this pre-#241 oracle on the historical whole-round pool curve as well as the historical opening.
	var legacy_curve: Dictionary = data.stages.stages.henesys.duplicate(true)
	legacy_curve.erase("maps")
	w.director = SpawnDirector.create(legacy_curve, w.kind_of_id, data.balance.get("spawn", {}))
	w.god = true
	var memo := {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			# Spec #34 (#119) added `collector` to pickup_collected; the stream is otherwise unchanged, which is the point.
			event.erase("collector")
		digest.update(var_to_bytes(events))
	return digest.finish().hex_encode()



func test_hero_event_stream_is_reproducible_and_matches_golden() -> void:
	var first := _event_digest(7200)
	assert_eq(_event_digest(7200), first, "two independent seeded rounds")
	assert_eq(first, GOLDEN, "two-minute Hero replay")
