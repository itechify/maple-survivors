extends TestCase
## Round-boundary carry, resets and deterministic one-off rounds through RunWorld's public interface.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Captured once; identical on Windows and Linux (see the test below).
const GOLDEN := "9545f55b76f16af7631c0508b15c9ae884f7ab0142481fc48edb79df588cd551"


## SHA-256 over the drained event bytes of a fixed-tick bot run, seed 1, synthetic assets only. The events are encoded
## with var_to_bytes, which writes ints, floats and Vector2 components as binary and never goes through float-to-text
## (JSON.stringify turned Vector2 into "(1090.813, 260.0)", whose decimal-tie rounding differs between platforms, #142).
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
		digest.update(var_to_bytes(events))
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
	# re-captured for #152 (upgrades.json cards grouped by job line, common -> beginner -> magician, the per-line file merge
	# order): the same cards in their pre-#152 order reproduce the #63 hash 823defb0... exactly (bb6eee9), so the only
	# change is which cards the seeded roll draws.
	# Fixed ticks include setup events, all drained event bytes and bot choices, with synthetic assets only.
	# Platform independent (#142): the digest hashes var_to_bytes of the events, not JSON text. The earlier Windows-only
	# golden differed on Linux in 16 of 72000 ticks, all from one artifact: JSON.stringify writes Vector2 fields through
	# float-to-text, which rounds exact decimal ties differently per platform (1090.8125 -> .813 on Windows, .812 on
	# Linux). The simulation itself did not diverge. libm does differ across platforms (a sin in the flyer bob,
	# integer-exponent pow calls in upgrades) but none of it reaches the event stream today.
	# Re-captured for #142 (serializer only; the old serializer reproduced the old Windows golden f3f8998b... on the same
	# code immediately before the change).
	assert_eq(_event_digest(72000), GOLDEN, "20-minute pre-change event bytes, seed 1")
