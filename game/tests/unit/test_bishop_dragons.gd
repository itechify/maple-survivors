extends TestCase
## Summon Dragon (2311006) and Bahamut (2321003), the Bishop's two holy followers (spec #372, BS7 #379): data on the
## PlayerSummons seam plus its two opt-in knobs, `summon.count_field` (the strike count is a level field) and `summon.move`
## (the node played while following: the dragons `fly`). Seeded RunWorld casts and fixed ticks on synthetic Skill.wz-shaped
## books (the recorded v83 values at the eight ranks, BS1 note); test_bishop_dragons_cache.gd reads the real cache.
const BF := preload("res://tests/fixtures/bishop_bolt_fixtures.gd")
const IL := preload("res://tests/fixtures/il_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## WZ levels of ranks 1..8 are BF.RANK_LEVELS; the recorded values at those levels (BS1-373.md "Rank values").
const DRAGON_MAD := [76, 92, 108, 120, 128, 136, 144, 150]
const DRAGON_TIME := [25, 45, 65, 80, 96, 112, 128, 140]
const BAHAMUT_MAD := [122, 134, 148, 160, 176, 195, 215, 230]
const BAHAMUT_TIME := [30, 50, 70, 85, 105, 125, 145, 160]
const BAHAMUT_TARGETS := [3, 3, 3, 3, 3, 3, 3, 6]

static func _points(values: Array, first: float) -> Dictionary:
	var out := {1: first}
	for i in 8:
		out[BF.RANK_LEVELS[i]] = values[i]
	return out

## An animation node of `frames` frames, each `delay_ms` long.
static func _anim(frames: int, delay_ms: float) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"$canvas": [0, 0, 0, 40, 40], "delay": delay_ms}
	return out

static func _range(lt: Array, rb: Array) -> Dictionary:
	return {"lt": {"$v": lt}, "rb": {"$v": rb}}

## Skill.wz/231.img Summon Dragon: five animations and NO `move` (it flies), one-target attack (no `mobCount`), box (-200,-150)..(200,150),
## attackAfter 500, no `elemAttr`. Skill.wz/232.img Bahamut: `elemAttr h`, attack box (-200,-150)..(0,30), attackAfter 990, constant
## `info.mobCount` 3 and the level `mobCount` 3 up to level 29 and 6 at level 30.
static func books() -> Dictionary:
	var dragon := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "action": {"0": "alert2"}, "hit": {"0": _anim(1, 250)},
		"level": IL.levels({"mad": _points(DRAGON_MAD, 70), "mastery": BF._mastery(), "time": _points(DRAGON_TIME, 20)}),
		"summon": {"summoned": _anim(5, 100), "fly": _anim(5, 90), "stand": _anim(5, 90), "attack1": _anim(8, 75),
			"die": _anim(6, 100)}}
	dragon.summon.attack1["info"] = {"range": _range([-200, -150], [200, 150]), "type": 1.0, "attackAfter": 500.0}
	var bahamut := {"icon": {"$canvas": [0, 0, 0, 32, 32]}, "elemAttr": "h", "action": {"0": "alert2"}, "hit": {"0": _anim(7, 100)},
		"level": IL.levels({"mad": _points(BAHAMUT_MAD, 110), "mastery": BF._mastery(), "time": _points(BAHAMUT_TIME, 25),
			"mobCount": {1: 3, 29: 3, 30: 6}}),
		"summon": {"summoned": _anim(6, 120), "fly": _anim(6, 150), "stand": _anim(12, 150), "attack1": _anim(18, 90),
			"die": _anim(6, 100)}}
	bahamut.summon.attack1["info"] = {"range": _range([-200, -150], [0, 30]), "type": 0.0, "attackAfter": 990.0, "mobCount": 3.0}
	return {"dragon": dragon, "bahamut": bahamut}

static func setup() -> Dictionary:
	var setup := BF.setup()
	var b := books()
	setup.skill_imgs["231"]["skill"]["2311006"] = b.dragon
	setup.skill_imgs["232"]["skill"]["2321003"] = b.bahamut
	return setup

## A Bishop world with `keys` learned and nothing else in the active slots, the caster strong enough that a hit never kills.
func _world(keys: Array = ["bahamut"]) -> RunWorld:
	var w := RunWorld.new(setup())
	RF.place_player(w, 200)
	w.loadout.order.clear()
	for key: String in keys:
		w.learn_skill(key)
	w.loadout.set_caster(100.0, 0.0, 30)
	w.drain_events()
	return w

func _mob(w: RunWorld, px: float) -> int:
	var m := RF.put_mob(w, 1110100, px, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func _run(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.runner.tick_cooldowns(DT, w)

## Casts `key` once at `rank` with a mob at each x offset in front of the player (left of it: the dragons trail behind a right-facing
## character and strike the side they face), lets one strike land and returns how many of the mobs lost HP.
func _struck(key: String, rank: int, mob_count: int, effects: Array = []) -> int:
	var w := _world([key])
	w.loadout.set_rank(key, rank)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(key, String(e.stat), String(e.op), float(e.value))
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_run(w, 45)
	var mobs: Array[int] = []
	for k in mob_count:
		mobs.append(_mob(w, w.runner.summons.x[0] + 20.0 + 10.0 * k))
	_run(w, 75)
	var hit := 0
	for m in mobs:
		if w.swarm.hp[m] < 100000:
			hit += 1
	return hit

func test_bahamut_strikes_three_monsters_until_rank_eight_and_six_at_rank_eight() -> void:
	for rank in range(1, 9):
		assert_eq(_struck("bahamut", rank, 8), BAHAMUT_TARGETS[rank - 1], "rank %d" % rank)

func test_a_dragon_follows_the_character_playing_fly_and_stands_when_it_arrives() -> void:
	for key: String in ["summon_dragon", "bahamut"]:
		var w := _world([key])
		w.runner.step(DT, w)
		w.loadout.order.clear()
		_run(w, 90) # the spawn animation ends, the ally settles at its trailing point
		assert_eq(w.runner.summons.action[0], "stand", "%s arrived" % key)
		w.player.pos.x += 300
		_run(w, 10)
		assert_eq(w.runner.summons.action[0], "fly", "%s follows with the fly node" % key)
		assert_eq(w.runner.summons.definitions[0].durations.get("fly", -1.0) > 0.0, true, "%s: the stored fly duration" % key)
		assert_false(w.runner.summons.definitions[0].durations.has("move"), "%s has no move node to measure" % key)
		_run(w, 120)
		assert_eq(w.runner.summons.action[0], "stand", "%s stands again at the trailing point" % key)

func test_summon_dragon_strikes_one_monster_at_every_rank() -> void:
	for rank in range(1, 9):
		assert_eq(_struck("summon_dragon", rank, 8), 1, "rank %d" % rank)

func test_the_count_modifier_adds_targets_to_both_dragons_and_to_bahamuts_level_count() -> void:
	var plus_two := [{"stat": "count", "op": "add", "value": 2.0}]
	assert_eq(_struck("summon_dragon", 1, 8, plus_two), 3)
	assert_eq(_struck("bahamut", 1, 8, plus_two), 5, "3 from the level field + 2")
	assert_eq(_struck("bahamut", 8, 8, plus_two), 8, "6 from the level field + 2")

func test_without_count_field_bahamut_keeps_the_attack_nodes_constant_count() -> void:
	var w := _world()
	w.book.defs.bahamut.summon.erase("count_field")
	w.loadout.set_rank("bahamut", 8)
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_run(w, 45)
	var mobs: Array[int] = []
	for k in 8:
		mobs.append(_mob(w, w.runner.summons.x[0] + 20.0 + 10.0 * k))
	_run(w, 75)
	var hit := mobs.filter(func(m: int) -> bool: return w.swarm.hp[m] < 100000)
	assert_eq(hit.size(), 3, "info.mobCount 3, the level's 6 is not read")

func test_bahamuts_box_is_one_sided_mirrored_by_facing_and_the_dragons_is_symmetric() -> void:
	for key in ["bahamut", "summon_dragon"]:
		var w := _world([key])
		w.runner.step(DT, w)
		w.loadout.order.clear()
		_run(w, 45)
		var ally_x: float = w.runner.summons.x[0]
		var front := _mob(w, ally_x + 150.0)
		var past := _mob(w, ally_x + 260.0) # beyond 200 px
		_run(w, 75)
		assert_true(w.swarm.hp[front] < 100000, "%s: inside the box" % key)
		assert_eq(w.swarm.hp[past], 100000, "%s: beyond the 200 px edge" % key)

func _strike_times(key: String, seconds: float) -> Array[float]:
	var w := _world([key])
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_mob(w, 150.0) # always inside the box: the ally acquires it and keeps striking
	var times: Array[float] = []
	for tick in int(seconds / DT):
		_run(w, 1)
		for e in w.drain_events():
			if e.type == "summon_attack":
				times.append(tick * DT)
	return times

func test_the_dragons_strike_on_their_attack_intervals() -> void:
	var fast := _strike_times("summon_dragon", 6.0)
	var slow := _strike_times("bahamut", 6.0)
	assert_true(fast.size() >= 4 and slow.size() >= 2, "%d / %d strikes" % [fast.size(), slow.size()])
	assert_near(fast[2] - fast[1], 1.2, 0.04, "Summon Dragon 1.2 s")
	assert_near(slow[1] - slow[0], 2.4, 0.04, "Bahamut 2.4 s")
	assert_true(fast.size() > 2 * slow.size() - 2, "the dragon is the fast one")

func test_a_dragon_lives_for_the_mapped_wz_time_then_dies() -> void:
	for key: String in ["summon_dragon", "bahamut"]:
		var times: Array = DRAGON_TIME if key == "summon_dragon" else BAHAMUT_TIME
		for rank in [1, 4, 8]:
			var w := _world([key])
			w.loadout.set_rank(key, rank)
			w.runner.step(DT, w)
			w.loadout.order.clear()
			var life := float(times[rank - 1])
			_run(w, int(life / DT) - 30)
			assert_eq(w.runner.summons.living_count(), 1, "%s rank %d alive just before %d s" % [key, rank, life])
			_run(w, 60)
			assert_eq(w.runner.summons.living_count(), 0, "%s rank %d gone after %d s" % [key, rank, life])

func test_the_dragons_are_holy_and_take_an_active_slot_each() -> void:
	var w := _world(["summon_dragon", "bahamut"])
	assert_eq(w.loadout.slot_count("active"), 2)
	assert_eq(w.loadout.stats("summon_dragon").element, "h")
	assert_eq(w.loadout.stats("bahamut").element, "h")

func test_both_dragons_coexist_and_a_recast_replaces_only_its_own_group() -> void:
	var w := _world(["summon_dragon", "bahamut"])
	for tick in 120: # one cast at a time: the second skill follows after the first's stance
		w.runner.step(DT, w)
	assert_eq(w.runner.summons.living_count(), 2)
	w.runner.cooldowns["bahamut"] = 0.0
	w.runner.cooldowns["summon_dragon"] = 99.0
	w.drain_events()
	w.runner.step(DT, w)
	var spawned := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "summon_spawn")
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0].skill, "bahamut")
	assert_eq(w.runner.summons.living_count(), 2, "the dragon survived Bahamut's recast")

func test_a_hidden_or_dead_caster_has_no_dragon_strike() -> void:
	for state in ["hidden", "dead"]:
		for key: String in ["summon_dragon", "bahamut"]:
			var w := _world([key])
			w.runner.step(DT, w)
			w.loadout.order.clear()
			_run(w, 45)
			var m := _mob(w, w.runner.summons.x[0] + 100.0)
			if state == "hidden":
				w.buffs._hidden = true # what Dark Sight sets; the seam only asks is_hidden()
			else:
				w.player_state.dead = true
			_run(w, 240)
			assert_eq(w.swarm.hp[m], 100000, "%s %s: no strike" % [key, state])

const TIERS := ["rare", "epic", "unique", "legendary"]
const DRAGONS := ["summon_dragon", "bahamut"]
## Probe layouts in front of the settled ally: six monsters well inside the 200 px box, and one monster alone 30 px beyond its
## edge (inside the Epic x1.2 box, 240 px). Alone, because a dragon takes its nearest monsters first.
const INSIDE := [40.0, 60.0, 80.0, 100.0, 120.0, 140.0]
const EDGE := [230.0]

## Casts `key` at rank 1 with `effects` applied and a monster at each of `offsets` in front of the first ally; returns the allies
## alive, the HP lost by all the monsters (summed) and how many were struck.
func _cast_with(key: String, effects: Array, offsets: Array) -> Dictionary:
	var w := _world([key])
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(key, String(e.stat), String(e.op), float(e.value))
	w.runner.step(DT, w)
	w.loadout.order.clear()
	_run(w, 90)
	var ally_x: float = w.runner.summons.x[0]
	var mobs: Array[int] = []
	for off: float in offsets:
		mobs.append(_mob(w, ally_x + off))
	_run(w, 100)
	var lost := 0
	var struck := 0
	for m in mobs:
		lost += 100000 - w.swarm.hp[m]
		struck += 1 if w.swarm.hp[m] < 100000 else 0
	return {"allies": w.runner.summons.living_count(), "lost": lost, "struck": struck}

func test_the_dragons_declare_the_four_rarity_lists_with_stats_the_seam_reads() -> void:
	for key: String in DRAGONS:
		var b: Dictionary = _world([key]).book.def(key).rarity_bonuses
		for tier: String in TIERS:
			assert_eq(b[tier].size(), 1, "%s %s" % [key, tier])
			for effect: Dictionary in b[tier][0].effects:
				assert_true(String(effect.stat) in ["damage", "area", "summon_count", "count"], "%s %s: a stat the summon seam reads" % [key, tier])
		assert_eq(b.rare[0].id, "power")
		assert_eq(b.epic[0].id, "reach")
		assert_eq(b.rare[0].effects, [{"stat": "damage", "op": "mul", "value": 1.2}])
		assert_eq(b.epic[0].effects, [{"stat": "area", "op": "mul", "value": 1.2}])
		assert_eq(b.legendary[0].id, b.unique[0].id, "%s: legendary shares the unique's repeat counter" % key)
		assert_eq(b.legendary[0].effects.back(), {"stat": "damage", "op": "mul", "value": 1.2})
	var twin: Dictionary = _world(["summon_dragon"]).book.def("summon_dragon").rarity_bonuses
	assert_eq(twin.unique[0].id, "twin")
	assert_eq(twin.unique[0].effects, [{"stat": "summon_count", "op": "add", "value": 1.0}])
	var crowd: Dictionary = _world(["bahamut"]).book.def("bahamut").rarity_bonuses
	assert_eq(crowd.unique[0].id, "crowd")
	assert_eq(crowd.unique[0].effects, [{"stat": "count", "op": "add", "value": 2.0}])

func test_each_dragon_rarity_effect_changes_the_resolved_cast() -> void:
	for key: String in DRAGONS:
		var bonuses: Dictionary = _world([key]).book.def(key).rarity_bonuses
		var base := _cast_with(key, [], INSIDE)
		assert_eq(base.allies, 1, key)
		assert_eq(base.struck, 1 if key == "summon_dragon" else 3, "%s: the canonical target count" % key)
		assert_eq(_cast_with(key, [], EDGE).struck, 0, "%s: the edge monster is beyond the box" % key)
		for tier: String in TIERS:
			for effect: Dictionary in bonuses[tier][0].effects:
				var with := _cast_with(key, [effect], INSIDE)
				var label := "%s %s %s" % [key, tier, effect.stat]
				match String(effect.stat):
					"damage":
						assert_true(int(with.lost) > int(base.lost), "%s: damage dealt %d -> %d" % [label, base.lost, with.lost])
					"area":
						assert_eq(_cast_with(key, [effect], EDGE).struck, 1, "%s: the box now reaches the far monster" % label)
					"summon_count":
						assert_eq(with.allies, 2, label)
					"count":
						assert_eq(with.struck, int(base.struck) + 2, label)
					_:
						assert_true(false, "%s: a stat this test does not know" % label)

func test_a_stat_the_summon_seam_ignores_changes_nothing_for_a_dragon() -> void:
	for key: String in DRAGONS:
		var base := _cast_with(key, [], INSIDE)
		assert_eq(_cast_with(key, [{"stat": "range", "op": "mul", "value": 1.2}], INSIDE), base, key)
		assert_eq(_cast_with(key, [{"stat": "pierce", "op": "add", "value": 2.0}], INSIDE), base, key)

func test_dragon_rarity_cards_apply_one_rank_and_the_repeat_rules() -> void:
	for key: String in DRAGONS:
		for tier: String in TIERS:
			var w := _world([])
			var id := key + "_new"
			assert_false(w.upgrades.choice_card(id, w, tier).get("rarity_bonus", {}).is_empty(), "%s %s" % [key, tier])
			w.upgrades.apply(id, w, tier)
			assert_eq(w.loadout.rank(key), 1, "%s %s: exactly one rank" % [key, tier])
			match tier:
				"rare": assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2)
				"epic": assert_near(w.loadout.stats(key).area, 1.2)
				"unique":
					var stat := "summon_count" if key == "summon_dragon" else "count"
					assert_near(w.loadout.skill_stat(key, stat, 0.0), 1.0 if key == "summon_dragon" else 2.0)
				"legendary":
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2)
		var w := _world([])
		w.upgrades.apply(key + "_new", w, "epic")
		w.upgrades.apply(key + "_rank", w, "epic")
		assert_near(w.loadout.stats(key).area, 1.2 * 1.16, 0.00001, "%s: the second Epic area repeat is x1.16" % key)
		w.upgrades.apply(key + "_rank", w, "unique")
		w.upgrades.apply(key + "_rank", w, "legendary")
		var shared := "summon_count" if key == "summon_dragon" else "count"
		var step := 1.0 if key == "summon_dragon" else 2.0
		assert_near(w.loadout.skill_stat(key, shared, 0.0), step + step * 0.8, 0.00001, "%s: Unique and Legendary share one counter" % key)

func test_dragon_normal_mastery_is_a_five_percent_damage_card_that_repeats_at_point_eight() -> void:
	for key: String in DRAGONS:
		var w := _world([])
		w.upgrades.apply(key + "_new", w, "normal")
		w.loadout.set_rank(key, 8)
		var normal := w.upgrades.choice_card(key + "_rank", w)
		assert_eq(normal.card_kind, "mastery", key)
		w.upgrades.apply(key + "_rank", w, "normal")
		assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.05, 0.00001, key)
		w.upgrades.apply(key + "_rank", w, "normal")
		assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.05 * 1.04, 0.00001, "%s: the repeat is x0.8 of +5%%" % key)
