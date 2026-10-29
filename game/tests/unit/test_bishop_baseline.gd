extends TestCase
## The Bishop's deterministic one-off round (spec #372, BS9 #381): the oracle of `test_character_baseline` for job 232. A fixed-tick
## god-mode bot run of seed 1 on the synthetic Henesys, hashed over the drained event bytes; the same recipe as the 212 and I/L
## baselines (same opening freeze, legacy pool curve, `BotInput.auto_choose` + `decide`, 72000 ticks, var_to_bytes so the digest is
## platform independent, #142), and a golden of its own so the other oracles stay pinned to their jobs. Synthetic assets only: no
## cache needed.
##
## The pool is FROZEN to the seven skills that existed on the integration branch when this was captured (Holy Arrow, Magic Claw,
## Shining Ray, Angel Ray, Heal, Genesis, Big Bang; Summon Dragon, Bahamut and Resurrection, BS7 #379 and BS8 #380, landed later), so
## later Bishop skills do not move it. The QA ticket (BS10) widens POOL to the ten, adds the synthetic books of the three new skills
## and re-captures GOLDEN once, documenting the cause. F/P, Hero and I/L oracle constants stay untouched.

const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const G := preload("res://tests/unit/test_bishop_genesis.gd")
const HF := preload("res://tests/fixtures/heal_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 72000
## tier C: the frozen BS9 pool (the skills that exist at capture), in the pool's own order.
const POOL := ["holy_arrow", "magic_claw", "shining_ray", "angel_ray", "heal", "genesis", "big_bang_bishop"]
## Captured by BS9 on spec/372-bishop tip a420111 plus this ticket (no sim change), seed 1, 72000 ticks, Godot 4.7.2.
const GOLDEN := "22ce31d79a882a2ae94c17a927e10089bb64544c34240a0945a76591e2b46b78"


## SHA-256 over the drained event bytes of a fixed-tick Bishop bot run, seed 1, synthetic assets only (see the 212 baseline).
func _event_digest(ticks: int, counts := {}) -> String:
	var data := DataRepo.load_all()
	data.jobs_survivor.jobs["232"]["playable"] = true
	data.jobs_survivor.jobs["232"]["skill_pool"] = POOL.duplicate()
	# Tier C: the same pre-#241 opening freeze as the 212 oracle.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := RF.setup("henesys", 1, data)
	var books := BF.books()
	setup.job = 232
	setup.skill_imgs["230"].skill["2301005"] = books.arrow
	setup.skill_imgs["230"].skill["2301001"] = books.teleport
	setup.skill_imgs["230"].skill["2301002"] = {"level": HF.levels()}
	setup.skill_imgs["231"] = {"skill": {"2311004": books.ray}}
	setup.skill_imgs["232"] = {"skill": {"2321007": books.angel}}
	G.add_books(setup)
	var w := RunWorld.new(setup)
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
			event.erase("collector")
			counts[event.type] = int(counts.get(event.type, 0)) + 1
		digest.update(var_to_bytes(events))
	return digest.finish().hex_encode()


func test_bishop_character_event_stream_matches_the_golden() -> void:
	assert_eq(_event_digest(TICKS), GOLDEN, "20-minute Bishop baseline event bytes, seed 1")


func test_the_run_is_a_bishop_with_workload_and_reproduces() -> void:
	# A short run: the digest is not a vacuum (Bishop casts hit and kill mobs, cards are picked) and two runs agree.
	var counts := {}
	var a := _event_digest(3600, counts)
	assert_eq(a, _event_digest(3600), "the same seed reproduces the stream")
	assert_true(int(counts.get("mob_hit", 0)) > 20, "mobs are hit (%s)" % [counts])
	assert_true(int(counts.get("mob_died", 0)) > 5, "mobs die")


func test_the_frozen_pool_is_what_the_run_offers() -> void:
	# The pool a later ticket extends must not leak in: the world's pool is exactly POOL, and every key of it is defined.
	var data := DataRepo.load_all()
	data.jobs_survivor.jobs["232"]["skill_pool"] = POOL.duplicate()
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	assert_eq(tree.skill_pool(232), POOL)
	var shipped: Array = DataRepo.load_all().jobs_survivor.jobs["232"].skill_pool
	for key: String in POOL:
		assert_true(key in shipped, "%s is still a shipped pool key" % key)
