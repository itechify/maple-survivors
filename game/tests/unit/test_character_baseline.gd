extends TestCase
## Round-boundary carry, resets and deterministic one-off rounds through RunWorld's public interface.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_fresh_character_event_stream_matches_before_ticket_67() -> void:
	# Captured without the character implementation: on bf26c5d, then re-captured on main 3f7e4b7 (#79 changed MP refill,
	# MP drops and boss targeting) by running this test there. Do not regenerate to bless a change.
	# re-captured on the #33 integration branch for #106 (Magician LUK split)
	# re-captured for #105 (worn equipment replaces the fixed starter outfit): the only new bytes are the one
	# equipment_changed event of the Wooden Wand grant (filtering it out reproduces the #106 hash b17af353...).
	# re-captured for #107 (meso drops): with balance.mesos.chance and boss_drops set to 0 the old hash 6ff18c3e... is
	# reproduced exactly, so the only new bytes are the meso pickup events (amounts at the shipped multiplier) and their pop positions.
	# Fixed ticks include setup events, all drained event bytes and bot choices, with synthetic assets only.
	var w := RunWorld.new(RF.with_basic_attack(RF.setup("henesys_hg1", 1)))
	w.god = true
	var memo := {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for tick in 72000:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			# Spec #34 (#119) added `collector` to pickup_collected; the stream is otherwise unchanged, which is the point.
			event.erase("collector")
		digest.update(JSON.stringify(events, "", false, true).to_utf8_buffer())
	assert_eq(digest.finish().hex_encode(), "08f7edf307d19c9f0d69dd005a7af6dc23aeb6b3ac2d3d80a6e2cc8bc628e03e", "20-minute pre-change event bytes, seed 1")


