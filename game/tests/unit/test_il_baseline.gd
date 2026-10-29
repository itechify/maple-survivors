extends TestCase
## The I/L Arch Mage's deterministic one-off round (spec #319, I11 #330): the oracle of `test_character_baseline` for job 222. A
## fixed-tick god-mode bot run of seed 1 on the synthetic Henesys, hashed over the drained event bytes; the same recipe as the 212
## baseline (same opening freeze, legacy pool curve, `BotInput.auto_choose` + `decide`, 72000 ticks, var_to_bytes so the digest is
## platform independent, #142), and a golden of its own so the 212 one stays pinned to 212. Synthetic assets only: no cache needed.
##
## I12 widens the historical six-skill pool to all twelve, changing the offered cards and event bytes. The additional
## synthetic books are frozen here too; no real cache is read. F/P oracle constants stay untouched.

const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 72000
const POOL := ["energy_bolt", "magic_claw", "cold_beam", "thunder_bolt", "ice_strike", "thunder_spear", "element_composition_il", "ice_demon", "ifrit", "chain_lightning", "blizzard", "big_bang_il"]
## Captured by I12 on spec/319 tip ec6f50a with the complete pool, seed 1, 72000 ticks, Godot 4.7.2.
const GOLDEN := "92a7b6274549dbb1f1fbccdb2685b46f3db27222a590bba05e542ffd61d74d44"


# --- synthetic books --------------------------------------------------------------------------------------------------


## SHA-256 over the drained event bytes of a fixed-tick I/L bot run, seed 1, synthetic assets only (see the 212 baseline).
func _event_digest(ticks: int, counts := {}) -> String:
	var data := DataRepo.load_all()
	data.jobs_survivor.jobs["222"]["skill_pool"] = POOL.duplicate()
	# Tier C: the same pre-#241 opening freeze as the 212 oracle.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := RF.setup("henesys", 1, data)
	var books := IL.books()
	setup.job = 222
	setup.skill_imgs["220"].skill["2201004"] = books.cold
	setup.skill_imgs["220"].skill["2201005"] = books.thunder
	setup.skill_imgs["221"] = {"skill": {"2211002": books.strike, "2211003": books.spear}}
	setup.skill_imgs["221"].skill["2211006"] = {"level": IL.levels({"mad": {1: 80, 30: 140}, "time": {1: 1, 30: 2}})}
	setup.skill_imgs["222"] = {"skill": {
		"2221003": {"level": IL.levels({"mad": {1: 42, 30: 100}, "mobCount": {1: 2, 30: 6}, "time": {1: 10, 30: 15}},
			func(n: Dictionary, _lv: int) -> void:
				n["lt"] = {"$v": [-300, -100]}
				n["rb"] = {"$v": [-15, 0]})},
		"2221005": {"level": IL.levels({"mad": {1: 183, 30: 300}, "mastery": {1: 10, 30: 10}, "time": {1: 20, 30: 160}}),
			"summon": {"attack1": {"info": {"attackAfter": 1080.0, "mobCount": 3.0, "priority": 2221003.0,
				"range": {"lt": {"$v": [-200, -150]}, "rb": {"$v": [0, 30]}}}}}},
		"2221006": {"level": IL.levels({"mad": {1: 103, 30: 180}, "mobCount": {1: 2, 30: 6}, "mastery": IL.mastery()})},
		"2221007": {"level": IL.levels({"mad": {1: 330, 30: 570}, "mobCount": {1: 15, 30: 15}, "time": {1: 1, 30: 3}},
			func(n: Dictionary, _lv: int) -> void: IL.box(n, 400, 350, 250))},
		"2221001": {"level": IL.levels({"mad": {1: 160, 30: 450}, "mobCount": {1: 6, 30: 6}, "mastery": IL.mastery()})}}}
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


func test_i_l_character_event_stream_matches_the_golden() -> void:
	assert_eq(_event_digest(TICKS), GOLDEN, "20-minute I/L baseline event bytes, seed 1")


func test_the_run_is_an_i_l_with_workload_and_reproduces() -> void:
	# A short run: the digest is not a vacuum (I/L casts hit and kill mobs, cards are picked) and two runs agree.
	var counts := {}
	var a := _event_digest(3600, counts)
	assert_eq(a, _event_digest(3600), "the same seed reproduces the stream")
	assert_true(int(counts.get("mob_hit", 0)) > 20, "mobs are hit (%s)" % [counts])
	assert_true(int(counts.get("mob_died", 0)) > 5, "mobs die")
