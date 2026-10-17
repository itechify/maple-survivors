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
	# Fixed ticks include setup events, all drained event bytes and bot choices, with synthetic assets only.
	var w := RunWorld.new(RF.with_basic_attack(RF.setup("henesys_hg1", 1)))
	w.god = true
	var memo := {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for tick in 72000:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		digest.update(JSON.stringify(w.drain_events(), "", false, true).to_utf8_buffer())
	assert_eq(digest.finish().hex_encode(), "6ff18c3e7f3efa4ecfe7acda1a5a326e872e2dd16ee80f65a40cde0850cfce6d", "20-minute pre-change event bytes, seed 1")


