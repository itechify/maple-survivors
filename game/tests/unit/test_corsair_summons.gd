extends TestCase
## Corsair's two summons (spec #384, ticket C6 #390): the Octopus (a stationary turret) and Gaviota (a one-shot kamikaze bird)
## as data on the `summon.behavior` seam of C5, with the Wrath of the Octopi and Flock bonuses (GAME_DESIGN 7.120.4). Seeded
## synthetic worlds with fixed ticks on the real Corsair definitions; the Skill.wz levels are a synthetic 521 book unless a test
## says "real cache" (those call require_cache() and SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/corsair_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const GROUND := {"x1": 0, "y1": 0, "x2": 2000, "y2": 0}
const KEYS := ["octopus", "gaviota"]
const TIERS := ["rare", "epic", "unique", "legendary"]
const OCTOPUS_ID := "5211001"
const GAVIOTA_ID := "5211002"
## Ticks of the Octopus' summon-in (a 630 ms first frame, then 11 x 120 ms = 1.95 s) and of Gaviota's (5 x 120 ms).
const OCTOPUS_IN := 120
const GAVIOTA_IN := 40


## A Corsair (job 522) on a flat floor at `x` facing right, mob bodies 4 x 10 px that stand still, `key` the only skill at
## `rank_value`, the synthetic 521 summons book (CF.summons_skills). The pistol's `incPAD` is `pistol_pad`.
func _corsair(key: String, rank_value := 1, x := 400.0, pistol_pad := 13, p_seed := 390) -> RunWorld:
	var w := CF.quiet_corsair(key, rank_value, {"521": {"skill": CF.summons_skills()}},
		{"x": x, "pistol_pad": pistol_pad, "seed": p_seed, "segments": [GROUND]})
	assert_true(w.loadout.has(key), "%s is learnable by a Corsair" % key)
	return w


func _mob(w: RunWorld, dx: float, hp := 100000.0) -> int:
	var m := RF.put_mob(w, MOB, w.player.pos.x + dx, -5.0, hp)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _move_mob(w: RunWorld, m: int, x: float) -> void:
	w.swarm.x[m] = x
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)


## One world tick with the mob grid fresh; the events it produced.
func _tick(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.step(DT, MoveInput.new())
	return w.drain_events()


## `ticks` world ticks; every event of them.
func _run(w: RunWorld, ticks: int) -> Array:
	var events := []
	for t in ticks:
		events.append_array(_tick(w))
	return events


func _of(events: Array, type: String, skill := "") -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type and (skill == "" or e.skill == skill))


func _hits(events: Array, skill: String) -> Array:
	return _of(events, "mob_hit", skill)


func _ints(values: Array) -> Array:
	return values.map(func(v: Variant) -> int: return int(v))


func _s(w: RunWorld) -> PlayerSummons:
	return w.runner.summons


# --- definitions ------------------------------------------------------------------------------------------------------

func test_both_are_defined_in_the_corsair_line_only_on_the_spec_shape() -> void:
	var corsair: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "corsair")).skills
	var pirate: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "pirate")).skills
	var w := _corsair("octopus")
	for key: String in KEYS:
		assert_true(corsair.has(key), key + " lives in corsair.json")
		assert_false(pirate.has(key), key + " is not in pirate.json")
		var d := w.book.def(key)
		assert_false(d.has("weapon_families"), "%s: a weapon gates nothing" % key)
		assert_false(d.has("ranks"), "%s: the default 30-level rank table" % key)
		assert_eq(String(d.kind), "summon", key)
		assert_eq(String(d.slot), "active", key)
		assert_eq(String(d.book), "521", key)
		assert_eq(String(d.damage), "physical", key)
		assert_eq(String(d.cast.rule), "summon", key)
		assert_eq(String(d.summon.watk_field), "pad", key + ": the ally's W.Att is the level's pad")
		assert_eq(String(d.summon.attack), "attack1", key)
		assert_eq(w.book.max_rank(key), 8, key)
		assert_eq(w.book.max_level(key), 30, key)
		assert_eq(_ints(w.book.rank_table(key)), [4, 8, 12, 15, 19, 23, 27, 30], key)
		assert_true(String(d.get("_tier", "")).contains("Tier C"), key + " notes its tier C choices")
	assert_eq(_ints([w.book.def("octopus").skill_id, w.book.def("gaviota").skill_id]), [5211001, 5211002])
	assert_eq([String(w.book.def("octopus").summon.behavior), String(w.book.def("gaviota").summon.behavior)], ["turret", "kamikaze"])
	assert_near(float(w.book.def("octopus").cooldown), 20.0, 1e-9)
	assert_near(float(w.book.def("gaviota").cooldown), 8.0, 1e-9)
	assert_near(float(w.book.def("octopus").summon.follow_speed), 0.0, 1e-9, "the Octopus never follows")
	assert_near(float(w.book.def("octopus").summon.attack_interval), 1.5, 1e-9)
	assert_eq(String(w.book.def("octopus").action), "octopus", "the WZ body stance")
	assert_eq(String(w.book.def("gaviota").summon.move), "fly")
	assert_near(float(w.book.def("gaviota").summon.hover), 60.0, 1e-9)
	assert_near(float(w.book.def("gaviota").summon.follow_speed), 260.0, 1e-9)
	assert_near(float(w.book.def("gaviota").cast.mob_within), 400.0, 1e-9)
	assert_near(float(w.book.def("gaviota").summon.attack_after), 0.84, 1e-9, "tier C: the dive art's length, not the WZ 1.92 s")
	assert_false(w.book.def("octopus").summon.has("attack_after"), "the Octopus keeps its WZ attackAfter 0.48 s")
	assert_false(w.book.def("octopus").cast.has("mob_within"), "an Octopus is planted wherever you stand")
	for key: String in KEYS:
		for suffix in ["_new", "_rank"]:
			assert_false(w.upgrades.card(key + suffix).is_empty(), key + suffix + " is generated by UpgradePool.add_pool_skills")


# --- Octopus ----------------------------------------------------------------------------------------------------------

func test_the_octopus_is_planted_where_it_was_cast_and_never_follows() -> void:
	var w := _corsair("octopus")
	_run(w, 1)
	var s := _s(w)
	assert_eq(s.living_count(), 1)
	var planted := Vector2(s.x[0], s.y[0])
	assert_near(planted.x, 400.0, 0.01)
	w.player.pos.x = 900.0
	_run(w, 240)
	assert_eq(Vector2(s.x[0], s.y[0]), planted, "the owner walked away and it stayed")


func test_the_circle_is_300_px_around_the_sp_offset() -> void:
	var w := _corsair("octopus")
	_run(w, 1)
	var s := _s(w)
	var centre := SummonTurret.centre(s, 0)
	assert_near(centre.x, 400.0 + 23.0, 0.01, "a right-facing octopus mirrors the WZ sp (-23, -18)")
	assert_near(SummonTurret.radius(s, 0), 300.0, 1e-6)
	var inside := _mob(w, 20.0 + 296.0)
	var outside := _mob(w, 20.0 + 340.0)
	assert_eq(_hits(_run(w, OCTOPUS_IN - 20), "octopus").size(), 0, "the summon-in has not finished: nothing fired yet")
	var events := _run(w, 240)
	var hit_slots := _hits(events, "octopus").map(func(e: Dictionary) -> int: return int(e.mob))
	assert_has(hit_slots, inside, "a monster inside the circle is shot")
	assert_false(hit_slots.has(outside), "a monster past the circle is not")


func test_a_ball_takes_attack_after_plus_distance_over_300_to_land() -> void:
	var w := _corsair("octopus")
	_run(w, 1)
	var s := _s(w)
	var centre := SummonTurret.centre(s, 0)
	_run(w, OCTOPUS_IN)
	var m := _mob(w, 20.0 + 240.0)
	var aim := w.mob_center(m)
	var flight := aim.distance_to(centre) / 300.0
	var started := -1
	var landed := -1
	for tick in 300:
		var events := _tick(w)
		if started < 0 and not _of(events, "summon_attack", "octopus").is_empty():
			started = tick
		if landed < 0 and not _hits(events, "octopus").is_empty():
			landed = tick
			break
	assert_true(started >= 0 and landed > started, "it attacked and the ball landed")
	assert_near(float(landed - started) * DT, 0.48 + flight, 3.0 * DT, "attackAfter 0.48 s plus the flight at 300 px/s")


func test_the_octopus_shoots_one_target_per_attack_the_nearest() -> void:
	var w := _corsair("octopus")
	_run(w, OCTOPUS_IN)
	var far := _mob(w, 20.0 + 250.0)
	var near := _mob(w, 20.0 + 120.0)
	var mid := _mob(w, 20.0 + 180.0)
	var events := _run(w, 100)
	var first := _hits(events, "octopus")
	assert_eq(first.size(), 1, "one target (WZ mobCount 1) per attack, in the first attack's window")
	assert_eq(int(first[0].mob), near, "the nearest monster to the circle's centre")
	assert_true(w.swarm.hp[far] == w.swarm.max_hp[far] and w.swarm.hp[mid] == w.swarm.max_hp[mid])


func test_the_octopus_fires_every_one_and_a_half_seconds_while_a_target_stands() -> void:
	var w := _corsair("octopus")
	_run(w, OCTOPUS_IN)
	_mob(w, 20.0 + 100.0)
	var events := _run(w, 60 * 6)
	var attacks := _of(events, "summon_attack", "octopus").size()
	assert_true(attacks >= 3 and attacks <= 5, "about one attack every 1.5 s over six seconds: %d" % attacks)


func test_octopus_damage_is_the_pad_formula_not_the_worn_weapon_or_ammo() -> void:
	var weak := _corsair("octopus", 1, 400.0, 13)
	var strong := _corsair("octopus", 1, 400.0, 90)
	var a := weak.loadout.stats("octopus", 1)
	var b := strong.loadout.stats("octopus", 1)
	assert_near(float(a.damage_max), float(b.damage_max), 1e-6, "a 90 PAD pistol changes nothing")
	assert_near(float(a.damage_min), float(b.damage_min), 1e-6)
	assert_true(float(a.damage_max) > 0.0)
	# The formula is linear in W.Att: the range per point of pad is the same at every rank, and the pad is the level's.
	var per_pad := float(a.damage_max) / (float(weak.book.canonical("octopus", int(a.level), "pad")) )
	for rank_value in [1, 4, 8]:
		var st := weak.loadout.stats("octopus", rank_value)
		var pad := float(weak.book.canonical("octopus", int(st.level), "pad"))
		assert_near(float(st.damage_max), per_pad * pad, 1e-3, "rank %d: damage scales with its pad %d" % [rank_value, int(pad)])
	var m := _mob(weak, 20.0 + 100.0)
	var events := _run(weak, OCTOPUS_IN + 100)
	var hits := _hits(events, "octopus")
	assert_true(hits.size() >= 1, "it hit")
	for e: Dictionary in hits:
		assert_true(float(e.damage) <= float(a.damage_max) + 1.0 and float(e.damage) >= minf(float(a.damage_min), 1.0), "%s inside the formula's range" % e.damage)
	assert_true(weak.swarm.hp[m] < weak.swarm.max_hp[m])


func test_the_life_is_the_level_time_and_it_expires_into_die() -> void:
	for rank_value in [1, 4, 8]:
		var w := _corsair("octopus", rank_value)
		_run(w, 1)
		var want: float = [10.0, 20.0, 30.0][[1, 4, 8].find(rank_value)]
		assert_near(float(w.loadout.stats("octopus", rank_value).duration), want, 1e-9, "rank %d lives %d s" % [rank_value, int(want)])
		assert_near(_s(w).left[0], want, 2.0 * DT, "the ally's life")
	var w := _corsair("octopus")
	_run(w, 1)
	w.runner.cooldowns["octopus"] = 1000.0 # one octopus only: no recast
	_s(w).left[0] = 0.5
	_run(w, 40)
	assert_eq(_s(w).action[0], "die")
	assert_eq(_s(w).living_count(), 0)
	_run(w, 80)
	assert_eq(_s(w).active[0], 0, "the slot is free after die")


func test_a_recast_replaces_the_octopus_and_summon_count_two_plants_two_side_by_side() -> void:
	var w := _corsair("octopus")
	_run(w, 1)
	var s := _s(w)
	assert_eq(s.living_count(), 1)
	w.runner.cooldowns["octopus"] = 0.0
	w.player.pos.x = 600.0
	_run(w, 1)
	assert_eq(s.living_count(), 1, "a recast replaces the group instead of stacking")
	assert_near(s.x[s.active.find(1)], 600.0, 0.01, "at the new spot")
	var two := _corsair("octopus")
	two.loadout.skill_mods["octopus"] = {"summon_count": Vector2(1.0, 1.0)}
	_run(two, 1)
	assert_eq(_s(two).living_count(), 2, "summon_count 2 gives two octopi")
	assert_near(absf(_s(two).x[1] - _s(two).x[0]), 48.0, 0.01, "side by side, 48 px apart")
	_mob(two, 20.0 + 100.0)
	var events := _run(two, OCTOPUS_IN + 60 * 3)
	var slots := {}
	for e: Dictionary in _of(events, "summon_attack", "octopus"):
		slots[int(e.slot)] = true
	assert_eq(slots.size(), 2, "both octopi fire at the monster")


func test_a_hidden_or_dead_caster_silences_the_octopus_and_it_resumes_afterwards() -> void:
	for case: String in ["hidden", "dead"]:
		var w := _corsair("octopus")
		_run(w, OCTOPUS_IN)
		var m := _mob(w, 20.0 + 100.0)
		if case == "hidden":
			w.buffs._hidden = true
		else:
			w.player_state.dead = true
		w.drain_events()
		for t in 120:
			w.runner.tick_cooldowns(DT, w) # the world's own step would end a dead run
		var events := w.drain_events()
		assert_eq(_of(events, "summon_attack", "octopus").size(), 0, case + ": nothing launched")
		assert_eq(_s(w).turret.ball_count(), 0, case)
		assert_true(w.swarm.hp[m] == w.swarm.max_hp[m], case + ": no damage")
		w.buffs._hidden = false
		w.player_state.dead = false
		for t in 200:
			w.runner.tick_cooldowns(DT, w)
		assert_true(w.swarm.hp[m] < w.swarm.max_hp[m], case + ": it fires again once the caster is back")


# --- Gaviota ----------------------------------------------------------------------------------------------------------

func test_gaviota_is_cast_only_with_a_living_monster_within_400_px() -> void:
	var w := _corsair("gaviota")
	var m := _mob(w, 401.0 + 4.0)
	_run(w, 5)
	assert_eq(_s(w).living_count(), 0, "a monster past 400 px does not admit the cast")
	assert_true(float(w.runner.cooldowns.get("gaviota", 0.0)) <= 0.0, "and nothing was spent")
	_move_mob(w, m, w.player.pos.x + 390.0)
	_run(w, 2)
	assert_eq(_s(w).living_count(), 1, "within 400 px: the bird is sent")
	assert_true(float(w.runner.cooldowns.get("gaviota", 0.0)) > 7.0, "and its 8 s recast starts")


func test_gaviota_dives_once_hits_three_monsters_in_its_box_with_its_pad_and_is_gone() -> void:
	var w := _corsair("gaviota")
	var cluster: Array[int] = []
	for k in 5:
		cluster.append(_mob(w, 300.0 + 6.0 * k))
	var events := _run(w, 60 * 6)
	var hits := _hits(events, "gaviota")
	assert_eq(hits.size(), 3, "mobCount 3 of the five in the box, once")
	var lost := 0
	for m in cluster:
		lost += 1 if w.swarm.hp[m] < w.swarm.max_hp[m] else 0
	assert_eq(lost, 3)
	assert_eq(_s(w).living_count(), 0, "single use: nothing left able to attack")
	assert_eq(_of(events, "summon_attack", "gaviota").size(), 1, "one dive")
	_run(w, 60)
	assert_eq(_s(w).active[0], 0, "the slot is free after die")
	var st := w.loadout.stats("gaviota", 1)
	for e: Dictionary in hits:
		assert_true(float(e.damage) <= float(st.damage_max) + 1.0, "inside the pad formula's range")


func test_gaviota_damage_scales_with_its_pad_not_the_weapon() -> void:
	var weak := _corsair("gaviota", 1, 400.0, 13)
	var strong := _corsair("gaviota", 1, 400.0, 90)
	assert_near(float(weak.loadout.stats("gaviota").damage_max), float(strong.loadout.stats("gaviota").damage_max), 1e-6)
	var per_pad := float(weak.loadout.stats("gaviota", 1).damage_max) / float(weak.book.canonical("gaviota", 4, "pad"))
	for rank_value in [1, 4, 8]:
		var st := weak.loadout.stats("gaviota", rank_value)
		var pad := float(weak.book.canonical("gaviota", int(st.level), "pad"))
		assert_near(float(st.damage_max), per_pad * pad, 1e-3, "rank %d" % rank_value)


func test_gaviota_waits_the_level_time_for_a_target_then_leaves_with_no_hit() -> void:
	var w := _corsair("gaviota")
	var m := _mob(w, 300.0)
	_run(w, 2)
	assert_eq(_s(w).living_count(), 1)
	# the monster leaves before the bird can strike: out of the 400 px reach, it has nothing to hunt.
	_move_mob(w, m, w.player.pos.x + 1000.0)
	_s(w).kamikaze.target[0] = -1
	_s(w).kamikaze.phase[0] = SummonKamikaze.SEEK
	assert_near(_s(w).left[0], 10.0, 0.1, "the wait limit is the level's time (10 s at rank 1)")
	var events := _run(w, 60 * 11)
	assert_eq(_hits(events, "gaviota").size(), 0, "expired unspent: no hit")
	assert_eq(_s(w).living_count(), 0)
	for rank_value in [4, 8]:
		var r := _corsair("gaviota", rank_value)
		_mob(r, 300.0)
		_run(r, 2)
		assert_near(_s(r).left[0], [20.0, 30.0][[4, 8].find(rank_value)], 0.1, "rank %d waits %d s" % [rank_value, [20, 30][[4, 8].find(rank_value)]])


func test_the_dive_reaches_the_strike_in_attack_after() -> void:
	var w := _corsair("gaviota")
	_mob(w, 300.0)
	var started := -1
	var struck := -1
	for tick in 60 * 8:
		var events := _tick(w)
		if started < 0 and not _of(events, "summon_attack", "gaviota").is_empty():
			started = tick
		if struck < 0 and not _hits(events, "gaviota").is_empty():
			struck = tick
			break
	assert_true(started >= 0 and struck > started, "it dived and struck")
	var after := float(w.book.def("gaviota").summon.attack_after)
	assert_true(after < float(w.book.skill_node("gaviota").summon.attack1.info.attackAfter) / 1000.0, "shortened from the WZ 1.92 s")
	assert_near(float(struck - started) * DT, after, 2.0 * DT, "the strike lands attackAfter after the dive starts")


func test_summon_count_two_sends_two_birds_at_the_first_and_second_nearest() -> void:
	var w := _corsair("gaviota")
	w.loadout.skill_mods["gaviota"] = {"summon_count": Vector2(1.0, 1.0)}
	var far := _mob(w, 340.0)
	var near := _mob(w, 260.0)
	_run(w, GAVIOTA_IN + 5)
	assert_eq(_s(w).living_count(), 2)
	var targets := [_s(w).kamikaze.target[0], _s(w).kamikaze.target[1]]
	assert_eq(targets, [near, far], "ordinal k takes the k-th nearest")
	_run(w, 60 * 6)
	assert_true(w.swarm.hp[near] < w.swarm.max_hp[near] and w.swarm.hp[far] < w.swarm.max_hp[far], "both were struck")


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

const BONUSES := {
	"octopus": [["eight_arms", "Eight Arms", [["damage", "mul", 1.2]]], ["long_arms", "Long Arms", [["area", "mul", 1.25]]],
		["wrath", "Wrath of the Octopi", [["summon_count", "add", 1.0]]]],
	"gaviota": [["heavy_load", "Heavy Load", [["damage", "mul", 1.2]]], ["bigger_boom", "Bigger Boom", [["area", "mul", 1.2]]],
		["flock", "Flock", [["summon_count", "add", 1.0]]]],
}


func _effects(entry: Dictionary) -> Array:
	return entry.effects.map(func(e: Dictionary) -> Array: return [String(e.stat), String(e.op), float(e.value)])


func test_the_catalog_lists_all_four_rarities_exactly_as_the_spec_table() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in BONUSES:
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for t in 3:
			var tier: String = TIERS[t]
			var want: Array = BONUSES[key][t]
			assert_eq(bonuses[tier].size(), 1, "%s %s: one bonus" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), want[0], "%s %s id" % [key, tier])
			assert_eq(String(bonuses[tier][0].text), want[1], "%s %s names the lineage skill" % [key, tier])
			assert_eq(_effects(bonuses[tier][0]), want[2], "%s %s effects" % [key, tier])
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(bonuses.legendary.size(), 1)
		assert_eq(String(legendary.id), String(bonuses.unique[0].id), "%s: Legendary shares the Unique's repeat counter" % key)
		assert_eq(_effects(legendary), BONUSES[key][2][2] + [["damage", "mul", 1.2]], "%s: the Unique's effects plus damage x1.2" % key)


func test_every_rarity_bonus_changes_the_resolved_cast() -> void:
	for key: String in BONUSES:
		for t in TIERS.size():
			var tier: String = TIERS[t]
			var effects: Array = BONUSES[key][mini(t, 2)][2] + ([["damage", "mul", 1.2]] if t == 3 else [])
			var w := _corsair(key)
			var before := w.loadout.stats(key, 2)
			assert_true(w.upgrades.apply(key + "_rank", w, tier), "%s %s" % [key, tier])
			assert_eq(w.loadout.rank(key), 2, "%s %s: exactly one rank on top" % [key, tier])
			var after := w.loadout.stats(key)
			for effect: Array in effects:
				match String(effect[0]):
					"damage":
						assert_near(float(after.damage_max), float(before.damage_max) * float(effect[2]), 1e-6 + float(before.damage_max) * 1e-6, "%s %s damage" % [key, tier])
					"area":
						assert_near(float(after.area), float(before.area) * float(effect[2]), 1e-6, "%s %s area" % [key, tier])
					"summon_count":
						assert_near(w.loadout.skill_stat(key, "summon_count", 1.0), 2.0, 1e-6, "%s %s summon_count" % [key, tier])


func test_legendary_shares_the_uniques_counter() -> void:
	for key: String in BONUSES:
		var w := _corsair(key)
		var counter := "bonus:%s:%s" % [key, BONUSES[key][2][0]]
		w.upgrades.apply(key + "_rank", w, "unique")
		assert_eq(int(w.loadout.card_ranks.get(counter, 0)), 1, key)
		var legendary := w.upgrades.rarity_bonus(w.upgrades.card(key + "_rank"), w, "legendary")
		assert_eq(String(legendary.counter), counter, "%s: Legendary counts on the Unique's counter" % key)


func test_wrath_plants_a_second_octopus_and_flock_sends_a_second_bird() -> void:
	var w := _corsair("octopus")
	w.upgrades.apply("octopus_rank", w, "unique")
	_run(w, 1)
	assert_eq(_s(w).living_count(), 2, "Wrath of the Octopi: two octopi")
	var flock := _corsair("gaviota")
	flock.upgrades.apply("gaviota_rank", flock, "unique")
	_mob(flock, 300.0)
	_mob(flock, 330.0)
	_run(flock, 2)
	assert_eq(_s(flock).living_count(), 2, "Flock: two birds")


func test_long_arms_widens_the_turret_radius_and_bigger_boom_the_strike_box() -> void:
	var w := _corsair("octopus")
	_run(w, 1)
	assert_near(SummonTurret.radius(_s(w), 0), 300.0, 1e-6)
	var wide := _corsair("octopus")
	wide.upgrades.apply("octopus_rank", wide, "epic")
	_run(wide, 1)
	assert_near(SummonTurret.radius(_s(wide), 0), 375.0, 1e-6, "Long Arms: 300 x 1.25")
	var plain := _corsair("gaviota")
	var boom := _corsair("gaviota")
	boom.upgrades.apply("gaviota_rank", boom, "epic")
	_mob(plain, 300.0)
	_mob(boom, 300.0)
	_run(plain, 2)
	_run(boom, 2)
	assert_near(_s(boom).box(0).size.x, _s(plain).box(0).size.x * 1.2, 1e-4, "Bigger Boom widens the box x1.2")


# --- text -------------------------------------------------------------------------------------------------------------

func test_the_card_and_skill_window_text_name_the_numbers() -> void:
	var w := _corsair("octopus")
	var text := SkillText.new(w.book, {})
	var octopus := text.level_line("octopus", 4, w.loadout.stats("octopus", 1))
	assert_true(octopus.contains("Calls Octopus for 10 s"), octopus)
	assert_true(octopus.contains("96 W.Att"), octopus)
	assert_true(octopus.contains("within 300 px"), octopus)
	var gaviota := text.level_line("gaviota", 4, w.loadout.stats("gaviota", 1))
	assert_true(gaviota.contains("Calls Gaviota, waiting up to 10 s for a target"), gaviota)
	assert_true(gaviota.contains("242 W.Att"), gaviota)
	assert_true(gaviota.contains("Dives once at a monster within 400 px of you, hitting up to 3, then is spent"), gaviota)
	assert_true(text.desc("octopus").contains("never moves"), text.desc("octopus"))


# --- the real cache ---------------------------------------------------------------------------------------------------

const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const PAD := {"octopus": [96, 140, 200], "gaviota": [242, 330, 450]}
const TIME := {"octopus": [10, 20, 30], "gaviota": [10, 20, 30]}


func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache_img("Skill.wz/521.img"):
		return
	var lib := AssetLibrary.new()
	var imgs := {}
	for book_id: String in ["500", "520", "521"]:
		var img := lib.img("Skill.wz/%s.img" % book_id)
		assert_true(img != null, "Skill.wz/%s.img is in the cache" % book_id)
		if img == null:
			lib.free()
			return
		imgs[book_id] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var lo := Loadout.new(book)
	lo.weapon_family = "gun"
	for key: String in KEYS:
		var id := OCTOPUS_ID if key == "octopus" else GAVIOTA_ID
		var node: Dictionary = imgs["521"].skill[id]
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank_value in range(1, 9):
			var lv: int = LEVELS[rank_value - 1]
			var level: Dictionary = node.level[str(lv)]
			var st := lo.stats(key, rank_value)
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			assert_eq(book.canonical_level(key, rank_value), lv, label)
			assert_eq(int(st.level), lv, label)
			assert_near(float(st.duration), float(level.time), 1e-6, label + " life / wait limit")
			assert_eq(book.canonical(key, lv, "pad"), float(level.pad), label + " pad")
		for i in 3:
			var rank_value: int = [1, 4, 8][i]
			assert_eq(int(book.canonical(key, int(lo.stats(key, rank_value).level), "pad")), PAD[key][i], "%s rank %d spec pad" % [key, rank_value])
			assert_near(float(lo.stats(key, rank_value).duration), float(TIME[key][i]), 1e-6, "%s rank %d spec life" % [key, rank_value])
		var info: Dictionary = node.summon.attack1.info
		if key == "octopus":
			assert_eq(float(info.range.r), 300.0)
			assert_eq(float(info.bulletSpeed), 300.0)
			assert_eq(int(info.mobCount), 1)
			assert_eq(float(info.attackAfter), 480.0)
			assert_eq(String(node.action["0"]), "octopus")
			assert_false(node.summon.has("move"), "the Octopus has no move animation")
		else:
			assert_eq(float(info.range.r), 400.0)
			assert_eq(int(info.mobCount), 3)
			assert_eq(Array(info.range.lt["$v"]), [-80.0, -60.0])
			assert_eq(Array(info.range.rb["$v"]), [80.0, 60.0])
			assert_true(node.summon.has("fly"))
	for key: String in KEYS:
		var d := book.def(key)
		assert_true(lib.sound(String(d.sounds.use)) != null, key + " use sound")
		for field in ["hit"]:
			var path := book.visual(key, field, 1, 1)
			assert_false(lib.anim(path).is_empty(), path)
		for anim: String in ["summoned", "stand", "attack1", "die"]:
			assert_false(lib.anim("%s/%s" % [d.summon.path, anim]).is_empty(), "%s/%s" % [d.summon.path, anim])
	assert_false(lib.anim("%s/fly" % book.def("gaviota").summon.path).is_empty())
	assert_false(lib.anim("%s/attack1/info/ball" % book.def("octopus").summon.path).is_empty())
	assert_eq(Array(lib.missing), [])
	lib.free()
