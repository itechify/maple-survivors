extends TestCase
## Buccaneer fixed-tick event oracle (spec #412, B11 #423): the recipe of the Hero oracle for job 512. Seed 1, bot, invulnerable,
## fixed 1/60 ticks on the synthetic Henesys, hashed over the initial player state and the drained event bytes (var_to_bytes, so the
## digest is platform independent, #142). Synthetic assets only (no cache): every pool skill is defined by the skill tickets' fixtures
## (`buccaneer_fixtures.gd`), and the knuckle carries a synthetic afterimage so the weapon-reach skills have a swing envelope (the
## way #346 repaired Hero's oracle, which cast nothing without one). The F/P, Hero and I/L oracles stay untouched.
## A later ticket that moves GOLDEN must say why next to the constant.

const BF := preload("res://tests/fixtures/buccaneer_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 14400
## Captured by B11 #423 on spec/412-buccaneer tip 196b6485 plus this ticket (the whole eleven-skill pool, seed 1, 14400 ticks, Godot 4.7.2).
const GOLDEN := "247fabb2015086b005715cc2e443e95ace09d1e602cf2b83a500cfa1b455ac8a"


## SHA-256 over the initial player state and the drained event bytes of the run. `counts` collects the events by type and the
## cast skills by key.
func _event_digest(ticks: int, counts := {}) -> String:
	var data := DataRepo.load_all()
	# Tier C: freeze the pre-#241 opening, as the other oracles do.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := BF.setup("henesys", 1, data)
	# Merge #332: preserve the replay's historical Sword input; bare tools now use the creation weapon.
	setup.character = {"format": 3, "job_id": 512, "look": {},
		"equipment": {"worn": Equipment.worn_from_ids(Equipment.DEFAULT_OUTFIT, setup.equipment_info), "inventory": []},
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
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			event.erase("collector")
			counts[event.type] = int(counts.get(event.type, 0)) + 1
			if event.type == "cast":
				var key := "cast:" + String(event.get("skill", ""))
				counts[key] = int(counts.get(key, 0)) + 1
		digest.update(var_to_bytes(events))
	counts["casts"] = w.runner.casts
	return digest.finish().hex_encode()


func test_buccaneer_event_stream_is_reproducible_and_matches_golden() -> void:
	var counts := {}
	var first := _event_digest(TICKS, counts)
	assert_eq(_event_digest(TICKS), first, "two independent seeded rounds")
	assert_true(int(counts.casts) > 0, "the replay exercises casts (%s)" % [counts])
	var skills := counts.keys().filter(func(k: String) -> bool: return k.begins_with("cast:"))
	assert_true(skills.size() >= 3, "at least three distinct skills cast (%s)" % [skills])
	assert_true(int(counts.get("cast:energy_drain", 0)) > 0, "the finisher fires: the bot plays the Energy Charge bar (%s)" % [counts])
	assert_eq(first, GOLDEN, "four-minute Buccaneer replay")
