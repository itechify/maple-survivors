extends TestCase
## Round-boundary carry, resets and deterministic one-off rounds through RunWorld's public interface.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Re-captured for #228 (spec #225): Magnet and potion-tier cards are gone and potions upgrade by level, so the bot draws
## different cards and the run emits potion_tier_up. Earlier: re-captured on Windows for #199: Bowman changes the job-window options and stream-8 first-job choice.
## Binary event encoding is platform independent (see below).
## Re-captured for #229: the bot waste guard counts a restore up to the pool (potions.bot.pool_floor 0.25 of the potion
## at least), so it drinks earlier when a potion exceeds a small pool. With pool_floor set to 1.0 (the old guard) the #228
## hash 769106d4... is reproduced exactly, so the guard is the only change; the four new schedule steps do not fire here.
const GOLDEN := "6ffbb887c7c4e39ec26cbcca92f1378236aca93a61eeac56ff9b2c0db9dddc76"


## SHA-256 over the drained event bytes of a fixed-tick bot run, seed 1, synthetic assets only. The events are encoded
## with var_to_bytes, which writes ints, floats and Vector2 components as binary and never goes through float-to-text
## (JSON.stringify turned Vector2 into "(1090.813, 260.0)", whose decimal-tie rounding differs between platforms, #142).
func _event_digest(ticks: int) -> String:
	# #186 froze Pirate out of this baseline. #199 keeps that exclusion and adds Bowman to the retained job pool;
	# the golden changes for the new job option / stream-8 choice, not a new combat RNG stream.
	var data := DataRepo.load_all()
	# #207: retain the same pre-expansion pool; the Thief is covered by its tracer tests.
	data.jobs_survivor.jobs["400"].playable = false
	data.jobs_survivor.jobs["400"].reason = "Not in this build"
	data.jobs_survivor.jobs["500"].playable = false
	data.jobs_survivor.jobs["500"].reason = "Not in this build"
	var w := RunWorld.new(RF.with_basic_attack(RF.setup("henesys_hg1", 1, data)))
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
	# Re-captured on Windows for #153: accuracy grants critical chance to every job/damage type, including Beginner
	# and fixed Three Snails; basic damage and crit rolls now use stream 5. Non-critical creation-weapon bounds are
	# unchanged (test_physical_damage). The owner explicitly permits the resulting Beginner/Magician event deltas.
	# Re-captured on Windows for #163 (Warrior playable, lead-approved): the Lv 10 job_advance_pending options now list the
	# Warrior as available, and the unforced bot picks a seeded random available first job on the job stream (spec #151), so
	# the run takes whichever job that draw gives. With jobs.json 100 locked ("Not in this build") the #153 hash 1a6cdb7c...
	# is reproduced exactly (checked on the pre-merge head).
	# Fixed ticks include setup events, all drained event bytes and bot choices, with synthetic assets only.
	# Platform independent (#142): the digest hashes var_to_bytes of the events, not JSON text. The earlier Windows-only
	# golden differed on Linux in 16 of 72000 ticks, all from one artifact: JSON.stringify writes Vector2 fields through
	# float-to-text, which rounds exact decimal ties differently per platform (1090.8125 -> .813 on Windows, .812 on
	# Linux). The simulation itself did not diverge. libm does differ across platforms (a sin in the flyer bob,
	# integer-exponent pow calls in upgrades) but none of it reaches the event stream today.
	# Re-captured for the #142 merge onto spec #151 (serializer only). This branch retains the #153 crit rolls and
	# #163 Warrior option / seeded first-job pick above, so its golden legitimately differs from main's 9545f55b... .
	# The binary digest matches on the unoptimised 19ca0a8 tip and the merged code (Windows, Godot 4.7.2).
	assert_eq(_event_digest(72000), GOLDEN, "20-minute physical-combat baseline event bytes, seed 1")
