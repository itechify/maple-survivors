extends TestCase
## Round-boundary carry, resets and deterministic one-off rounds through RunWorld's public interface.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_fresh_character_event_stream_matches_before_ticket_67() -> void:
	# Captured on integration bf26c5d BEFORE the character implementation; do not regenerate to bless a change.
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
	assert_eq(digest.finish().hex_encode(), "585d0e709f6b7b9b64f39f06cef172713c40ba0a789a8b2b0aeb5c14deca7387", "20-minute pre-change event bytes, seed 1")


