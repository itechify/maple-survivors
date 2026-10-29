extends TestCase
## Paladin fixed-tick event oracle (spec #308, P9 #317): the job-122 sibling of `test_hero_baseline` and `test_il_baseline`. A
## god-mode bot run of seed 1 on the synthetic Henesys, hashed over the initial player state (starting HP) and the drained event
## bytes, with the 212 recipe (the pre-#241 opening freeze, the legacy whole-round pool curve, `auto_choose` + `decide`,
## var_to_bytes so the digest is platform independent) and a golden of its own, so the 212 and 112 oracles stay pinned to their
## jobs. Synthetic assets only (PaladinFixtures): no cache is needed.
##
## The pool is frozen to the eight skills of `PF.POOL` and their synthetic books, so a later Paladin skill or a changed pool
## moves this digest only through the cause named next to the constant (T7 method: a shift is the change's, never a reason to
## recapture on its own). Captured by P9 on the spec/308 tip 32eb2a3c + P9 data, Godot 4.7.2. No earlier Paladin hash existed.

const PF := preload("res://tests/fixtures/paladin_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Six minutes: past the first boss arrival; the bot exercises three Charges and Charged Blow.
## The scripted replay below covers Holy Charge, Blast and the Hammer.
const TICKS := 21600
## Captured by P9, seed 1, 21600 ticks, the eight-skill pool, Godot 4.7.2.
const GOLDEN := "cd1a60103b801ed70de7039badb0e92860b5714e41d0c5c2fa00cc6a298cd5b4"
const CHARGES := ["fire_charge", "ice_charge", "thunder_charge", "holy_charge"]


## SHA-256 over the initial player state and the drained event bytes of a fixed-tick Paladin bot run, seed 1. `facts` collects
## counts for the sanity tests.
func _event_digest(ticks: int, facts := {}) -> String:
	var data := DataRepo.load_all()
	data.jobs_survivor.jobs["122"]["skill_pool"] = PF.POOL.duplicate()
	# Tier C: freeze the pre-#241 opening so the schema/key migration must reproduce the existing golden unchanged.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var w := RunWorld.new(PF.setup("henesys", 1, data))
	# Keep this pre-#241 oracle on the historical whole-round pool curve as well as the historical opening.
	var legacy_curve: Dictionary = data.stages.stages.henesys.duplicate(true)
	legacy_curve.erase("maps")
	w.director = SpawnDirector.create(legacy_curve, w.kind_of_id, data.balance.get("spawn", {}))
	w.god = true
	var memo := {}
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(w.player_state))
	var counts := {}
	for tick in ticks:
		BotInput.auto_choose(w)
		w.step(DT, BotInput.decide(w, memo))
		var events := w.drain_events()
		for event: Dictionary in events:
			event.erase("collector")
			counts[event.type] = int(counts.get(event.type, 0)) + 1
			if event.type == "mob_hit":
				facts["hits_by_skill"] = facts.get("hits_by_skill", {})
				facts.hits_by_skill[String(event.get("skill", ""))] = int(facts.hits_by_skill.get(String(event.get("skill", "")), 0)) + 1
		digest.update(var_to_bytes(events))
	facts["counts"] = counts
	facts["casts"] = w.runner.casts
	facts["loadout"] = Array(w.loadout.order)
	facts["actives"] = w.loadout.slot_count("active")
	facts["level"] = w.progression.level
	return digest.finish().hex_encode()


func test_paladin_event_stream_is_reproducible_and_matches_golden() -> void:
	var facts := {}
	var first := _event_digest(TICKS, facts)
	assert_eq(_event_digest(TICKS), first, "two independent seeded rounds")
	assert_eq(first, GOLDEN, "six-minute Paladin replay")
	# The digest is not a vacuum: the bot casts, lands hits with several skills, fills the six active slots and takes a Charge.
	assert_true(int(facts.casts) > 100, "the run casts (%d)" % int(facts.casts))
	assert_true(facts.hits_by_skill.size() >= 3, "several skills land hits: %s" % [facts.hits_by_skill])
	assert_true(int(facts.hits_by_skill.get("charged_blow", 0)) > 0, "a Charge's Charged Blow lands (the Form seam ran)")
	assert_eq(int(facts.actives), 6, "the six active slots are full")
	var charges := Array(facts.loadout).filter(func(k: Variant) -> bool: return String(k) in CHARGES)
	assert_true(charges.size() >= 1, "the bot took at least one Charge among its six actives: %s" % [facts.loadout])
	assert_true(int(facts.counts.get("form_started", 0)) > 0, "a Form window opened")

## New scripted golden captured after two independent identical runs on the merged #308/#441 tree.
## Scripted Holy/Blast replay complements the bot seed, which never learns these skills.
func _holy_digest(facts: Dictionary) -> String:
	var w := PF.round_world(308)
	w.loadout.order.clear()
	for key: String in ["holy_charge", "blast"]:
		w.loadout.add_skill(key)
	for x: int in [430, 450, 470]:
		RF.put_mob(w, 1110100, x, 195, 10000000.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for tick in 240:
		w.restore_player("hp", 100, "test")
		w.runner.step(DT, w)
		var events := w.drain_events()
		for event: Dictionary in events:
			if event.type == "mob_hit":
				facts[String(event.get("skill", ""))] = true
		digest.update(var_to_bytes(events))
	return digest.finish().hex_encode()

func test_scripted_holy_blast_and_hammer_replay() -> void:
	var facts := {}
	var first := _holy_digest(facts)
	assert_eq(first, _holy_digest({}), "independent fixed-tick Holy runs")
	assert_eq(first, "68e6db2d1eb5b59eb1e1a7d20d508627b432b6f65e79515601d7e0592e88ca79", "scripted Holy replay")
	assert_true(facts.has("blast"), str(facts))
	assert_true(facts.has("heavens_hammer"), str(facts))
