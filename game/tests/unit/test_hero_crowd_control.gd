extends TestCase
## Hero crowd control (spec #296, H7 #303): Shout (box, `min_targets 3`, stun, the explicit rank table) and Monster Magnet
## (`range_around`, `min_targets 3`, the shared pull block of #300), with their rarity bonuses. The behaviour tests run on
## synthetic 111/112 books shaped like Skill.wz (including the missing `prop` of Shout level 4); the real-cache tests at the
## end assert the mapped WZ levels against the cache and SKIP without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const BOSS := 2220000
const FLYER := 9300063
const CASTER_X := 1000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}]

## Rank -> WZ level of Shout (spec D4) and of the standard 30-level table Monster Magnet uses (tier A reading, H1 #297).
const SHOUT_LEVELS := [5, 8, 12, 15, 19, 23, 27, 30]
const MAGNET_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]


## Synthetic Skill.wz levels of Shout: prop 40 + 2 x level and time 3 + level / 6, except level 4, which like the real node
## stores its chance under the stray key "58" instead of `prop`.
func _shout_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var node := {"damage": 10 + lv, "mobCount": 6, "time": 3 + lv / 6, "prop": 40 + 2 * lv,
			"lt": {"$v": [-100 - 3 * lv, -80 - 2 * lv]}, "rb": {"$v": [100 + 3 * lv, 80 + 2 * lv]}}
		if lv == 4:
			node.erase("prop")
			node["58"] = 38
		levels[str(lv)] = node
	return levels


## Synthetic levels of Monster Magnet: range 160 + 8 x level, prop 40 + 2 x level, mobCount 6.
func _magnet_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mobCount": 6, "prop": 40 + 2 * lv, "range": 160 + 8 * lv}
	return levels


## A quiet world as job 112 on a flat floor with the caster at x 1000, holding only `key` at rank 1, god mode on.
func _world(key: String, p_seed := 303, learn := true) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"]["playable"] = true # Hero is flipped playable by H9/H10; this makes its cards exist
	var setup := RF.setup("quiet", p_seed, data)
	setup.skill_imgs["111"] = {"skill": {"1111008": {"level": _shout_levels()}}}
	setup.skill_imgs["112"] = {"skill": {"1121001": {"level": _magnet_levels()}}}
	var w := RunWorld.new(setup)
	w.set_job(112)
	w.bounds = Rect2(0, -500, 2000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.order.clear()
	if learn:
		w.learn_skill(key)
	w.god = true
	w.drain_events()
	return w


func _tick(w: RunWorld) -> void:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)


func _stuns(w: RunWorld) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied")


# --- Shout: the rank table --------------------------------------------------------------------------------------------

func test_shout_rank_1_reads_level_5_because_level_4_has_no_prop() -> void:
	var w := _world("shout")
	assert_true(w.book.has("shout"), "Shout is defined")
	assert_eq(w.book.rank_table("shout").map(func(v: Variant) -> int: return int(v)), SHOUT_LEVELS)
	assert_eq(w.book.max_rank("shout"), 8)
	var st := w.loadout.stats("shout")
	assert_eq(st.level, 5, "rank 1 skips the corrupted level 4")
	assert_eq(w.book.canonical("shout", st.level, "prop"), 50.0, "level 5's prop, not a missing field")
	for rank in range(1, 9):
		assert_eq(w.loadout.stats("shout", rank).level, SHOUT_LEVELS[rank - 1])
		assert_true(w.book.level_node("shout", w.loadout.stats("shout", rank).level).has("prop"),
			"rank %d has a prop" % rank)


# --- Shout: the cast --------------------------------------------------------------------------------------------------

func test_shout_needs_three_mobs_in_the_box_and_strikes_at_most_six() -> void:
	var w := _world("shout")
	RF.put_mob(w, MOB, CASTER_X + 60, 190.0, 1000.0)
	RF.put_mob(w, MOB, CASTER_X - 60, 190.0, 1000.0)
	_tick(w)
	assert_eq(w.runner.casts, 0, "two mobs in the box do not admit the cast")
	RF.put_mob(w, MOB, CASTER_X + 80, 190.0, 1000.0)
	_tick(w)
	assert_eq(w.runner.casts, 1, "the third mob admits it")
	w = _world("shout")
	for i in 9:
		RF.put_mob(w, MOB, CASTER_X - 80 + i * 20, 190.0, 1000.0)
	var far := RF.put_mob(w, MOB, CASTER_X + 900, 190.0, 1000.0)
	_tick(w)
	var hits := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
	assert_eq(hits.size(), 6, "mobCount 6 caps the mobs struck")
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far], "a mob outside the box is untouched")


func test_shout_box_is_centred_and_grows_with_the_rank() -> void:
	var w := _world("shout")
	var one: Rect2 = w.loadout.stats("shout", 1).box
	assert_near(one.position.x, -one.end.x, 0.001, "centred on the caster")
	assert_true(w.loadout.stats("shout", 8).box.size.x > one.size.x)
	var wide := _world("shout", 303, false)
	wide.upgrades.apply("shout_new", wide, "rare")
	assert_near(wide.loadout.stats("shout").box.size.x, one.size.x * 1.2, 0.01, "Rare area x1.2")


func _stun_rate(rank: int, casts: int) -> Array:
	var w := _world("shout")
	w.loadout.set_rank("shout", rank)
	var mobs := []
	for i in 6:
		mobs.append(RF.put_mob(w, MOB, CASTER_X - 100 + i * 40, 190.0, 100000.0))
	var landed := 0
	var time := 0.0
	for n in casts:
		w.runner.cooldowns["shout"] = 0.0
		w.drain_events()
		_tick(w)
		for e: Dictionary in _stuns(w):
			landed += 1
			time = w.swarm.status_time(int(e.mob), MobSwarm.STUN)
	return [float(landed) / float(casts * 6), time]


func test_shout_stun_chance_and_seconds_follow_the_mapped_level() -> void:
	# Synthetic tables: rank 1 = level 5 (prop 50, time 3), rank 8 = level 30 (prop 100 -> always, time 8).
	var low := _stun_rate(1, 60)
	assert_near(low[0], 0.50, 0.06, "rank 1 stuns at level 5's 50 %")
	assert_near(low[1], 3.0, 0.05, "for level 5's seconds")
	var top := _stun_rate(8, 20)
	assert_eq(top[0], 1.0, "rank 8 (level 30, prop 100) always stuns")
	assert_near(top[1], 8.0, 0.05)
	assert_eq(_stun_rate(1, 60), low, "same seed, same outcome")
