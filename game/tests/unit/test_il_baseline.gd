extends TestCase
## The I/L Arch Mage's deterministic one-off round (spec #319, I11 #330): the oracle of `test_character_baseline` for job 222. A
## fixed-tick god-mode bot run of seed 1 on the synthetic Henesys, hashed over the drained event bytes; the same recipe as the 212
## baseline (same opening freeze, legacy pool curve, `BotInput.auto_choose` + `decide`, 72000 ticks, var_to_bytes so the digest is
## platform independent, #142), and a golden of its own so the 212 one stays pinned to 212. Synthetic assets only: no cache needed.
##
## The pool is frozen to the skills defined when this oracle was captured (Energy Bolt, Magic Claw and the four I6 bolts; Teleport is
## the mobility skill), so tickets that add the other I/L skills (Chain Lightning, Ice Demon, Ifrit, Blizzard, Element Composition,
## Big Bang) leave it unchanged and a changed hash means a shared-mechanics change. I12 widens POOL to the full twelve and re-captures
## once every skill has landed (tier C: ours; the F/P oracle freezes nothing because its whole pool existed when it was captured).
## The synthetic books below are this file's own copy of the I6 tests' (a baseline must not move when another test's fixture does).
## Do not regenerate the golden to bless a change: find the cause (the T7 method: remove the new behaviour and the hash must return).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const TICKS := 72000
const POOL := ["energy_bolt", "magic_claw", "cold_beam", "thunder_bolt", "ice_strike", "thunder_spear"]
## Captured on spec/319 at the I6 merge (c058729) plus I11, seed 1, 72000 ticks, Godot 4.7.2.
const GOLDEN := "5768c01d2691e35493b11e7c9219497051d2da2eb68efb7eb79f0b97f99bf82a"


# --- synthetic books --------------------------------------------------------------------------------------------------

static func _lerp_points(points: Dictionary, lv: int) -> float:
	var xs := points.keys()
	xs.sort()
	for i in xs.size() - 1:
		var a: int = xs[i]
		var b: int = xs[i + 1]
		if lv >= a and lv <= b:
			return lerpf(float(points[a]), float(points[b]), float(lv - a) / float(b - a))
	return float(points[xs.back()])


static func _levels(fields: Dictionary, extra: Callable = Callable()) -> Dictionary:
	var out := {}
	for lv in range(1, 31):
		var node := {}
		for field: String in fields:
			node[field] = float(roundi(_lerp_points(fields[field], lv)))
		if extra.is_valid():
			extra.call(node, lv)
		out[str(lv)] = node
	return out


static func _box(node: Dictionary, half_w: float, up: float, down: float) -> void:
	node["lt"] = {"$v": [-half_w, -up]}
	node["rb"] = {"$v": [half_w, down]}


static func _mastery() -> Dictionary:
	return {1: 1, 4: 2, 15: 5, 19: 7, 30: 10}


static func _anim(frames: int) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"$canvas": [0, 0, 0, 40, 40], "delay": 100.0}
	return out


## Skill.wz-shaped books 220 (Cold Beam, Thunder Bolt) and 221 (Ice Strike, Thunder Spear) with the recorded levels.
static func _books() -> Dictionary:
	var cold := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "i", "effect": _anim(4), "hit": {"0": _anim(6)},
		"level": _levels({"mad": {1: 13, 4: 22, 15: 55, 19: 67, 30: 100}, "mastery": _mastery(),
			"x": {1: -100, 30: -100}}, func(node: Dictionary, lv: int) -> void: node["time"] = 1.0 if lv < 19 else 2.0)}
	var thunder := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "l", "effect": _anim(7), "hit": {"0": _anim(9)},
		"level": _levels({"mad": {1: 2, 4: 8, 15: 30, 19: 38, 30: 60}, "mastery": _mastery(), "mobCount": {1: 6, 30: 6}},
			func(node: Dictionary, lv: int) -> void:
				_box(node, 150.0 if lv < 19 else 170.0, 50.0 if lv < 19 else 70.0, 50.0 if lv < 19 else 70.0))}
	var strike := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "i", "action": {"0": "magic2"},
		"effect": _anim(11), "hit": {"0": _anim(6)},
		"level": _levels({"mad": {1: 32, 4: 38, 15: 60, 19: 68, 30: 90}, "mastery": _mastery(), "mobCount": {1: 6, 30: 6}},
			func(node: Dictionary, lv: int) -> void:
				node["time"] = 1.0 if lv < 19 else 2.0
				_box(node, roundf(_lerp_points({1: 110, 4: 120, 15: 150, 19: 170, 30: 200}, lv)),
					roundf(_lerp_points({1: 82, 4: 90, 15: 112, 19: 127, 30: 150}, lv)),
					roundf(_lerp_points({1: 83, 4: 90, 15: 113, 19: 128, 30: 150}, lv))))}
	var spear := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "l", "action": {"0": "magic1"},
		"effect": _anim(15), "hit": {"0": _anim(5)},
		"level": _levels({"mad": {1: 80, 4: 100, 15: 135, 19: 145, 30: 170}, "mastery": _mastery()})}
	return {"cold": cold, "thunder": thunder, "strike": strike, "spear": spear}


## SHA-256 over the drained event bytes of a fixed-tick I/L bot run, seed 1, synthetic assets only (see the 212 baseline).
func _event_digest(ticks: int, counts := {}) -> String:
	var data := DataRepo.load_all()
	data.jobs_survivor.jobs["222"]["playable"] = true # not playable in the shipped data until I12
	data.jobs_survivor.jobs["222"]["skill_pool"] = POOL.duplicate()
	# Tier C: the same pre-#241 opening freeze as the 212 oracle.
	for opening: Array in [[0, 0.15, 3], [1, 0.4, 8], [2, 0.6, 12]]:
		data.stages.stages.henesys.keyframes[int(opening[0])].rate = float(opening[1])
		data.stages.stages.henesys.keyframes[int(opening[0])].max_alive = int(opening[2])
	var setup := RF.setup("henesys", 1, data)
	var books := _books()
	setup.job = 222
	setup.skill_imgs["220"].skill["2201004"] = books.cold
	setup.skill_imgs["220"].skill["2201005"] = books.thunder
	setup.skill_imgs["221"] = {"skill": {"2211002": books.strike, "2211003": books.spear}}
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
