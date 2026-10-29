extends TestCase
## The Bishop's deterministic one-off round (spec #372, BS9 #381): the oracle of `test_character_baseline` for job 232. A fixed-tick
## god-mode bot run of seed 1 on the synthetic Henesys, hashed over the drained event bytes; the same recipe as the 212 and I/L
## baselines (same opening freeze, legacy pool curve, `BotInput.auto_choose` + `decide`, 72000 ticks, var_to_bytes so the digest is
## platform independent, #142), and a golden of its own so the other oracles stay pinned to their jobs. Synthetic assets only: no
## cache needed.
##
## BS10 widens BS9's seven-skill pool to all ten: dragons and Resurrection change card choices and event bytes.
## The golden is recaptured once for this workload expansion; F/P, Hero and I/L oracles stay untouched.

const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const BG := preload("res://tests/fixtures/bishop_genesis_fixtures.gd")
const HF := preload("res://tests/fixtures/heal_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DF := preload("res://tests/fixtures/bishop_dragon_fixtures.gd")
const REV := preload("res://tests/fixtures/resurrection_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 72000
## tier C: the full BS10 pool, frozen in the shipped pool order.
const POOL := ["holy_arrow", "magic_claw", "shining_ray", "angel_ray", "heal", "summon_dragon", "bahamut", "genesis", "big_bang_bishop", "resurrection"]
## Recaptured by BS10 on integration e5f7b50 with the full ten-skill pool, seed 1, 72000 ticks, Godot 4.7.2; recaptured once more by the
## #372 review fixes, which reword the Heal and Resurrection bonus cards ("recovery x1.2", "guard +1.5 s": the card text is part of the
## choice events). Nothing else changed: with the old wording the previous digest (f0766314...) still reproduced.
const GOLDEN := "35b8cde5d422c2cdf7f39f78a6901610d15008be2bad24bf4091eddb8c761af1"


## SHA-256 over the drained event bytes of a fixed-tick Bishop bot run, seed 1, synthetic assets only (see the 212 baseline).
func _event_digest(ticks: int, counts := {}) -> String:
	var data := DataRepo.load_all()
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
	BG.add_books(setup)
	var dragons := DF.books()
	setup.skill_imgs["231"].skill["2311006"] = dragons.dragon
	setup.skill_imgs["232"].skill["2321003"] = dragons.bahamut
	setup.skill_imgs["232"].skill["2321006"] = REV.img().skill["2321006"]
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
	assert_eq(POOL, shipped, "oracle covers all ten shipped skills")
	for key: String in POOL:
		assert_true(key in shipped, "%s is still a shipped pool key" % key)
