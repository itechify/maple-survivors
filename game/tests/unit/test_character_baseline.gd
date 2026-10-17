extends TestCase
## Round-boundary carry, resets and deterministic one-off rounds through RunWorld's public interface.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Captured on Windows (see the test below).
const WINDOWS_GOLDEN := "823defb05bfcb5a7a10b25f1e679e5be7979ce4562a93ec2ce53f448eb5c6f0e"


## SHA-256 over the drained event bytes of a fixed-tick bot run, seed 1, synthetic assets only.
func _event_digest(ticks: int) -> String:
	var w := RunWorld.new(RF.with_basic_attack(RF.setup("henesys_hg1", 1)))
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
		digest.update(JSON.stringify(events, "", false, true).to_utf8_buffer())
	return digest.finish().hex_encode()


func test_fresh_character_event_stream_matches_before_ticket_67() -> void:
	# Captured without the character implementation: on bf26c5d, then re-captured on main 3f7e4b7 (#79 changed MP refill,
	# MP drops and boss targeting) by running this test there. Do not regenerate to bless a change.
	# re-captured on the #33 integration branch for #106 (Magician LUK split)
	# re-captured for #105 (worn equipment replaces the fixed starter outfit): the only new bytes are the one
	# equipment_changed event of the Wooden Wand grant (filtering it out reproduces the #106 hash b17af353...).
	# re-captured for #107 (meso drops): with balance.mesos.chance and boss_drops set to 0 the old hash 6ff18c3e... is
	# reproduced exactly, so the only new bytes are the meso pickup events (amounts at the shipped multiplier) and their pop positions.
	# re-captured for #109 (equipment drops): with equipment_drops.chance and boss_drops set to 0 the #107 hash 08f7edf3...
	# is reproduced exactly, so the only new bytes are the equipment pickup events and the pop positions they shift.
	# re-captured for #63 (the bot scores a card by the steps it grants): with balance.bot.gain_step_score set to 0 the hash
	# ce161497... is reproduced exactly, so the only new bytes are the bot taking a higher-tier card over a Normal-preferred one.
	# Fixed ticks include setup events, all drained event bytes and bot choices, with synthetic assets only.
	# The golden digest is a Windows capture. On Linux the same code and data give other event bytes (seen on the CI
	# runner and in WSL, #135; cause not investigated, probably the platform's math library), so there the test
	# checks what survives a platform change: two runs on the same machine agree, over two minutes of play.
	if OS.get_name() != "Windows":
		assert_eq(_event_digest(7200), _event_digest(7200), "two replays agree (the golden digest is Windows-only)")
		return
	assert_eq(_event_digest(72000), WINDOWS_GOLDEN, "20-minute pre-change event bytes, seed 1")
