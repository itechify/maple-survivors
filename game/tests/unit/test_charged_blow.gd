extends TestCase
## Charged Blow (spec #308, P6 #314): the stun nova every Charge carries, a `form_sub` sub-skill of the Form seam (P3 #311).
## The behaviour tests run on a synthetic 121 book shaped like Skill.wz and a stand-in form (diagnostic job 999 keys, as
## test_player_forms does) that lists `charged_blow`, because no Charge exists yet (P7 and P8 attach it to the real ones).
## The real-cache tests at the end assert the eight mapped ranks and the art nodes against Skill.wz and SKIP without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 1000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}]
## Rank -> WZ level of the standard 30-level table (tier A reading, P1 #309).
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Element code -> art key of Charged Blow's `effect/<n>` and `hit/0/<n>` nodes (P1 #309: 1 ice, 2 fire, 3 lightning, 5 holy).
const ART := {"i": 1, "f": 2, "l": 3, "h": 5}


## Synthetic Skill.wz levels shaped like 1211002: damage 160 + 3 x level, prop 30 + 2 x level (capped at 100), time 2 + level / 10,
## range 120 + level, mobCount 6, hpCon 10 + level / 3.
func _levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 160 + 3 * lv, "prop": mini(100, 30 + 2 * lv), "time": 2 + lv / 10,
			"range": 120 + lv, "mobCount": 6, "hpCon": 10 + lv / 3}
	return levels


## A quiet world as Paladin (122) on a flat floor with the caster at x 1000 and a stand-in Charge of `element` listing
## Charged Blow after 0.1 s every 0.5 s. The Charge is not started: tests start it with `_charge`.
func _world(element := "f", p_seed := 314) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", p_seed, data)
	setup.skill_imgs["121"] = {"skill": {"1211002": {"level": _levels()}}}
	setup.skill_imgs["999"] = {"skill": {"9991001": {"level": {"1": {"damage": 100}}}}}
	var w := RunWorld.new(setup)
	w.set_job(122)
	w.bounds = Rect2(0, -500, 2000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.order.clear()
	w.book.defs["test_charge"] = {"skill_id": 9991001, "book": "999", "job": 999, "kind": "form", "slot": "active",
		"damage": "none", "cooldown": 18.0, "ranks": [1], "cast": {"rule": "form", "mob_within": 400},
		"form": {"duration": 12.0, "exclusive_group": "test", "effects": {"element": element, "damage": {"field": "damage"}},
			"subs": [{"skill": "charged_blow", "first_after": 0.1, "interval": 0.5}]}}
	w.drain_events()
	return w


func _charge(w: RunWorld) -> void:
	w.runner.forms.start(w, "test_charge", w.loadout.stats("test_charge"))
	w.drain_events()


func _tick(w: RunWorld, ticks := 1) -> void:
	for i in ticks:
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.runner.step(DT, w)


func _crowd(w: RunWorld, n := 3, hp := 100000.0) -> Array:
	var slots := []
	for i in n:
		slots.append(RF.put_mob(w, MOB, CASTER_X - 60 + i * 30, 190.0, hp))
	return slots


func _events(w: RunWorld, type: String) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == type)


# --- The definition --------------------------------------------------------------------------------------------------

func test_the_definition_is_a_pool_less_form_sub_of_book_121() -> void:
	var w := _world()
	assert_true(w.book.has("charged_blow"), "defined by skills/paladin.json")
	var d := w.book.def("charged_blow")
	assert_eq(int(d.skill_id), 1211002)
	assert_eq(String(d.book), "121")
	assert_eq(int(d.job), 121)
	assert_eq(String(d.slot), "form_sub")
	assert_eq(String(d.damage), "physical")
	assert_eq(String(d.cast.rule), "range_around")
	assert_eq(int(d.cast.min_targets), 3)
	assert_eq(d.on_hit, {"status": "stun", "chance_field": "prop", "duration_field": "time"})
	assert_eq(w.book.rank_table("charged_blow").map(func(v: Variant) -> int: return int(v)), LEVELS)
	assert_eq(w.book.max_rank("charged_blow"), 8)
	assert_false(d.has("rarity_bonuses"), "a sub-skill has no rarity list")
	assert_eq(String(d.action), "weapon", "the held weapon's first swing stance")
	assert_true(String(d.sounds.use).ends_with("1211002/Use"))


func test_it_is_in_no_pool_no_loadout_order_and_no_card() -> void:
	var w := _world()
	for job: Dictionary in w.setup.data.jobs_survivor.jobs.values():
		assert_false("charged_blow" in job.get("skill_pool", []), "never in a pool")
	assert_false(w.loadout.add_skill("charged_blow"), "the loadout refuses a form_sub")
	assert_false("charged_blow" in w.loadout.order)
	assert_false(w.upgrades.eligible(w).any(func(id: Variant) -> bool: return String(w.upgrades.card(String(id)).get("skill", "")) == "charged_blow"), "never offered")
	for card: Dictionary in w.setup.data.upgrades.cards:
		assert_ne(String(card.get("skill", "")), "charged_blow", "not a card")


func test_the_catalog_names_the_four_charges_as_parents() -> void:
	var w := _world()
	var parents: Array = w.book.def("charged_blow").form_sub_of
	parents = parents.duplicate()
	parents.sort()
	assert_eq(parents, ["fire_charge", "holy_charge", "ice_charge", "thunder_charge"])


# --- Admission --------------------------------------------------------------------------------------------------------

func test_a_world_without_a_charge_never_casts_it() -> void:
	var w := _world()
	_crowd(w, 5)
	_tick(w, 120)
	assert_eq(w.runner.casts, 0)
	assert_eq(_events(w, "cast").size(), 0)


func test_it_needs_three_mobs_within_range() -> void:
	var w := _world()
	_charge(w)
	_crowd(w, 2)
	_tick(w, 12)
	assert_eq(w.runner.casts, 0, "two mobs do not admit the nova")
	RF.put_mob(w, MOB, CASTER_X + 40, 190.0, 100000.0)
	_tick(w)
	assert_eq(w.runner.casts, 1, "the third admits it at once (it was due and waiting)")
	var far := _world()
	_charge(far)
	_crowd(far, 2)
	RF.put_mob(far, MOB, CASTER_X + 400, 190.0, 100000.0)
	_tick(far, 12)
	assert_eq(far.runner.casts, 0, "a mob outside the range does not count")


func test_it_strikes_at_most_six_mobs() -> void:
	var w := _world()
	_charge(w)
	_crowd(w, 9)
	_tick(w, 7)
	assert_eq(_events(w, "mob_hit").size(), 6)


func test_range_follows_the_rank() -> void:
	for rank in [1, 4, 8]:
		var reach: float = 120.0 + LEVELS[rank - 1]
		var w := _world()
		w.loadout.ranks["test_charge"] = rank
		assert_near(w.loadout.stats("charged_blow", rank).range, reach, 0.001, "rank %d range" % rank)
		_charge(w)
		RF.put_mob(w, MOB, CASTER_X - 20, 190.0, 100000.0)
		RF.put_mob(w, MOB, CASTER_X + 20, 190.0, 100000.0)
		var edge := RF.put_mob(w, MOB, CASTER_X + reach - 14.0, 190.0, 100000.0)
		_tick(w, 7)
		assert_eq(w.runner.casts, 1, "rank %d: a mob just inside reach completes the three" % rank)
		assert_true(w.swarm.hp[edge] < w.swarm.max_hp[edge])
		var out := _world()
		out.loadout.ranks["test_charge"] = rank
		_charge(out)
		RF.put_mob(out, MOB, CASTER_X - 20, 190.0, 100000.0)
		RF.put_mob(out, MOB, CASTER_X + 20, 190.0, 100000.0)
		RF.put_mob(out, MOB, CASTER_X + reach + 40.0, 190.0, 100000.0)
		_tick(out, 7)
		assert_eq(out.runner.casts, 0, "rank %d: a mob past reach does not" % rank)


# --- Stun -------------------------------------------------------------------------------------------------------------

func _stun_rate(rank: int, casts: int) -> Array:
	var w := _world()
	w.loadout.ranks["test_charge"] = rank
	w.god = true # mob contact must not push the caster off the crowd
	w.book.defs.test_charge.form.duration = 1000.0 # outlast the casts
	_charge(w)
	var slots := _crowd(w, 6)
	var landed := 0
	var time := 0.0
	for n in casts:
		w.drain_events()
		w.restore_player("hp", 100000, "test") # the blows cost HP: keep the caster able to pay
		for i in slots.size():
			w.swarm.x[slots[i]] = CASTER_X - 60 + i * 20 # blows push the crowd away: put it back
		_tick(w, 30) # the interval is 0.5 s
		for e: Dictionary in _events(w, "mob_status_applied"):
			landed += 1
			time = float(e.duration)
	return [float(landed) / float(casts * 6), time, w.runner.casts]


func test_stun_chance_and_seconds_follow_the_rank() -> void:
	# Synthetic: rank 1 = level 4 (prop 38, time 2), rank 8 = level 30 (prop 90, time 5).
	var low := _stun_rate(1, 40)
	assert_near(low[0], 0.38, 0.06, "rank 1 stuns at level 4's 38 %")
	assert_near(low[1], 2.0, 0.05, "for 2 s")
	var top := _stun_rate(8, 40)
	assert_near(top[0], 0.90, 0.05, "rank 8 stuns at level 30's 90 %")
	assert_near(top[1], 5.0, 0.05)
	assert_eq(_stun_rate(1, 40), low, "same seed, same outcome")


func test_one_main_stream_draw_per_target_and_none_at_a_certain_stun() -> void:
	# Measure the stun rolls as the difference from a twin cast of the same damage with no `on_hit`.
	var draws := func(prop_all: float, with_status: bool) -> int:
		var w := _world()
		for lv: Dictionary in w.book.skill_imgs["121"].skill["1211002"].level.values():
			lv["prop"] = prop_all
		if not with_status:
			w.book.defs.charged_blow = w.book.defs.charged_blow.duplicate(true)
			w.book.defs.charged_blow.erase("on_hit")
		_charge(w)
		_crowd(w, 4)
		var before := RandomNumberGenerator.new()
		before.seed = 1
		before.state = w.rng.state
		_tick(w, 7)
		assert_eq(w.runner.casts, 1)
		var probe := RandomNumberGenerator.new()
		probe.seed = 1
		probe.state = before.state
		var n := 0
		while probe.state != w.rng.state and n < 200:
			probe.randf()
			n += 1
		return n
	var base: int = draws.call(50.0, false)
	assert_eq(int(draws.call(50.0, true)) - base, 4, "one draw per struck mob at 50 %")
	assert_eq(int(draws.call(100.0, true)) - base, 0, "a certain stun draws nothing")


# --- HP cost ----------------------------------------------------------------------------------------------------------

func test_it_pays_hp_and_waits_instead_of_being_lethal() -> void:
	var w := _world()
	_charge(w)
	_crowd(w, 3)
	var cost := int(w.loadout.stats("charged_blow", 1).hp_cost)
	assert_eq(cost, 10 + LEVELS[0] / 3)
	w.spend_hp(int(w.player_state.hp) - cost)
	_tick(w, 12)
	assert_eq(w.runner.casts, 0, "paying would leave 0 HP: it waits")
	assert_eq(int(w.player_state.hp), cost)
	w.restore_player("hp", 50, "test")
	var hp := int(w.player_state.hp)
	_tick(w)
	assert_eq(w.runner.casts, 1, "the due cast goes the tick it can pay")
	assert_eq(int(w.player_state.hp), hp - cost)


# --- Element ----------------------------------------------------------------------------------------------------------

func test_the_hit_carries_the_running_forms_element() -> void:
	var w := _world("f")
	_charge(w)
	var weak := _crowd(w)
	w.swarm.mob_kind(weak[0]).elements = {"F": 1.5}
	var mild := _world("f")
	_charge(mild)
	var other := _crowd(mild)
	mild.swarm.mob_kind(other[0]).elements = {"F": 1.0}
	for world: RunWorld in [w, mild]:
		_tick(world, 7)
	var strong := float(_events(w, "mob_hit").filter(func(e: Dictionary) -> bool: return e.mob == weak[0])[0].damage)
	var plain := float(_events(mild, "mob_hit").filter(func(e: Dictionary) -> bool: return e.mob == other[0])[0].damage)
	assert_true(strong > plain, "a fire-weak mob takes more from a fire Charge's blow")
	assert_near(strong / plain, 1.5, 0.2, "about 1.5x (the damage rolls differ per mob)")


func test_art_follows_the_elements_index() -> void:
	for element: String in ART:
		var w := _world(element)
		_charge(w)
		_crowd(w)
		_tick(w, 7)
		var cast: Dictionary = _events(w, "cast")[0]
		assert_eq(String(cast.effect), "Skill.wz/121.img/skill/1211002/effect/%d" % ART[element], element)
		var hit: Dictionary = _events(w, "mob_hit")[0]
		assert_eq(String(hit.hit_visual), "Skill.wz/121.img/skill/1211002/hit/0/%d" % ART[element], element)


func test_art_index_table() -> void:
	assert_eq(PlayerForms.art_index(""), 0)
	assert_eq(PlayerForms.art_index("i"), 1)
	assert_eq(PlayerForms.art_index("f"), 2)
	assert_eq(PlayerForms.art_index("l"), 3)
	assert_eq(PlayerForms.art_index("h"), 5)
	assert_eq(PlayerForms.fill_art("a/{art}/b", "h"), "a/5/b")
	assert_eq(PlayerForms.fill_art("a/{art}/b", ""), "a/0/b")
	assert_eq(PlayerForms.fill_art("a/b", "h"), "a/b")


# --- Lifecycle --------------------------------------------------------------------------------------------------------

func test_it_fires_inside_the_window_on_its_interval_and_not_after() -> void:
	var w := _world()
	w.runner.forms.start(w, "test_charge", w.loadout.stats("test_charge"))
	w.runner.forms.snapshot()
	_crowd(w, 3)
	_tick(w, 6)
	assert_eq(w.runner.casts, 1, "first at first_after")
	_tick(w, 30)
	assert_eq(w.runner.casts, 2, "then every interval")
	w.runner.forms.clear(w, "test")
	var before := w.runner.casts
	_tick(w, 90)
	assert_eq(w.runner.casts, before, "no casts once the Charge is gone")


func test_a_sub_cast_reports_the_charged_blow_key_and_one_cast_event() -> void:
	var w := _world()
	_charge(w)
	_crowd(w)
	_tick(w, 7)
	var casts := _events(w, "cast")
	assert_eq(casts.size(), 1)
	assert_eq(String(casts[0].skill), "charged_blow")
	assert_eq(int(casts[0].skill_id), 1211002)


# --- Text -------------------------------------------------------------------------------------------------------------

func test_text_names_damage_range_stun_and_hp() -> void:
	var w := _world()
	var line := SkillText.new(w.book).level_line("charged_blow", 4, w.loadout.stats("charged_blow"))
	assert_true("172%" in line and "38%" in line and "stun" in line and "2 sec" in line, line)


# --- Real cache -------------------------------------------------------------------------------------------------------

func _real_world(lib: AssetLibrary) -> RunWorld:
	var w := _world()
	w.book.skill_imgs["121"] = lib.img("Skill.wz/121.img").root
	return w


func test_real_cache_eight_mapped_ranks() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(lib)
	# Tier A literals read from Skill.wz 121.img (P1 #309): per mapped level damage, prop, time, range, hpCon.
	var want := [[168, 38, 2, 130, 15], [176, 46, 2, 130, 15], [186, 54, 3, 140, 20], [195, 60, 3, 140, 20],
		[207, 68, 3, 140, 20], [222, 76, 4, 150, 25], [238, 84, 4, 150, 25], [250, 90, 4, 150, 25]]
	for rank in range(1, 9):
		var st := w.loadout.stats("charged_blow", rank)
		assert_eq(st.level, LEVELS[rank - 1], "rank %d" % rank)
		var node := w.book.level_node("charged_blow", st.level)
		var row: Array = want[rank - 1]
		assert_eq(int(node.damage), row[0], "rank %d damage" % rank)
		assert_eq(int(node.prop), row[1], "rank %d prop" % rank)
		assert_eq(int(node.time), row[2], "rank %d time" % rank)
		assert_eq(int(node.range), row[3], "rank %d range" % rank)
		assert_eq(int(node.hpCon), row[4], "rank %d hpCon" % rank)
		assert_eq(int(node.mobCount), 6)
		assert_near(st.range, float(row[3]), 0.001)
		assert_eq(st.hp_cost, row[4])
		assert_eq(st.mob_count, 6)
	lib.free()


func test_real_cache_art_and_sound_nodes_exist_for_every_element_index() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	for n: int in ART.values():
		assert_true(lib.find_anim("Skill.wz/121.img/skill/1211002/effect/%d" % n) != null, "effect/%d" % n)
		assert_true(lib.find_anim("Skill.wz/121.img/skill/1211002/hit/0/%d" % n) != null, "hit/0/%d" % n)
	assert_true(lib.find_anim("Skill.wz/121.img/skill/1211002/mob") != null, "the stun stars")
	assert_true(lib.sound("Sound.wz/Skill.img/1211002/Use") != null, "the Use sound")
	var w := _real_world(lib)
	for element: String in ART:
		var path: String = PlayerForms.fill_art(String(w.book.def("charged_blow").hit), element)
		assert_true(lib.find_anim(path) != null, path)
	lib.free()
