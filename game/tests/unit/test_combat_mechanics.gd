extends TestCase
## Generic opt-in combat mechanics (#200): synthetic skill tables, seeded worlds and fixed ticks.

const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


## Impact selection reuses packed storage rather than allocating containers or a comparator per contact.
func test_impact_blast_obeys_projectile_hot_loop_storage_rules() -> void:
	var source := FileAccess.get_file_as_string("res://scripts/sim/projectile_system.gd")
	var blast := source.get_slice("func _blast(", 1).get_slice("\nfunc ", 0)
	assert_false(blast.contains("= []"), "no per-impact target Array")
	assert_false(blast.contains("= {}"), "no per-impact distance Dictionary")
	assert_false(blast.contains("sort_custom"), "no per-impact comparator Callable")
	assert_false(source.contains("impact_blast: Array[Dictionary]"), "blast state uses packed projectile fields")


## A busy seeded blast replay freezes exact event bytes, RNG state, body-distance ordering and pool reuse.
func test_seeded_blast_replay_stays_byte_identical() -> void:
	var w := CF.world()
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	for wave in 3:
		w.swarm = MobSwarm.new(128, w.mob_kinds)
		w.swarm.fhm = w.fhm
		var primary := RF.put_mob(w, 1110100, 350, 190, 100)
		# Equal-distance bodies in distinct hash cells exercise the slot tie-break, beyond the old 64-slot buffer.
		for k in 80:
			RF.put_mob(w, 1110100, 350 + (k % 2 * 2 - 1) * (30 + k / 2 * 2), 190, 100)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.events.clear()
		var spec := {"x": 350, "y": 180, "vx": 600, "range": 800, "radius": 1,
			"dmg_min": 10, "dmg_max": 90, "crit": 0.35, "skill": "synthetic",
			"impact_blast": {"box": Rect2(-200, -60, 400, 60), "count": 70, "visual": "burst"}}
		w.projectiles.spawn(spec)
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
		var hits := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
		assert_eq(hits.size(), 70)
		assert_eq(hits[0].mob, primary)
		for k in range(1, 70):
			assert_eq(hits[k].mob, k, "nearest body, equal distance resolved by slot")
		digest.update(var_to_bytes(w.events))
		digest.update(var_to_bytes(w.projectiles.rng.state))
	assert_eq(digest.finish().hex_encode(), "9a2f1c81a5c6f4fbc5a779b2475600833dcd57e93ded818d0912a60420cc013a",
		"pre-fix event/RNG bytes on integration 730467c, seed 200")


func test_knockback_chance_direction_edge_boss_and_statuses() -> void:
	var w := CF.world({"knockback": {"chance_field": "prop", "distance": 120}})
	var right := RF.put_mob(w, 1110100, 350, 190, 100)
	var left := RF.put_mob(w, 1110100, 100, 190, 100)
	var edge := w.fhm.x2[w.swarm.fh[right]]
	w.swarm.apply_status(right, "stun", {"time": 3}, w.events)
	w.hit_mob(right, w.loadout.stats("synthetic"), -1)
	w.hit_mob(left, w.loadout.stats("synthetic"), -1)
	assert_near(w.swarm.x[right], minf(470, edge), 0.01)
	assert_near(w.swarm.x[left], -20, 0.01)
	assert_near(w.swarm.status_time(right, MobSwarm.STUN), 3)
	var near_edge := RF.put_mob(w, 1110100, edge - 10, 190, 100)
	w.hit_mob(near_edge, w.loadout.stats("synthetic"), -1)
	assert_near(w.swarm.x[near_edge], edge, 0.01, "stops at the floor edge")
	for scheduled: bool in [false, true]:
		var boss := RF.put_mob(w, 1110100 if scheduled else 2220000, 300, 190, 100)
		w.swarm.steady[boss] = 1 if scheduled else 0
		w.hit_mob(boss, w.loadout.stats("synthetic"), -1)
		assert_near(w.swarm.x[boss], 300)
	w.loadout.set_rank("synthetic", 2)
	var before := w.swarm.x[right]
	w.hit_mob(right, w.loadout.stats("synthetic"), -1)
	assert_near(w.swarm.x[right], before, 0.01, "zero prop never knocks back")


func test_knockback_rolls_only_stream_one_once_per_nonboss_hit() -> void:
	var w := CF.world({"knockback": {"chance_field": "prop", "distance": 1}})
	var control := CF.world()
	var m := RF.put_mob(w, 1110100, 350, 190, 100)
	var c := RF.put_mob(control, 1110100, 350, 190, 100)
	for line in 10:
		w.hit_mob(m, w.loadout.stats("synthetic"), -1)
		control.hit_mob(c, control.loadout.stats("synthetic"), -1)
		control.rng.randf()
	assert_eq(w.rng.state, control.rng.state)
	for stream: String in ["basic_rng", "final_rng", "spawn_rng", "drop_rng", "card_rng", "job_rng",
			"potion_rng", "meso_rng", "equip_rng", "scroll_rng", "reward_rng", "pirate_rng"]:
		assert_eq((w.get(stream) as RandomNumberGenerator).state,
			(control.get(stream) as RandomNumberGenerator).state, stream)


func test_knockback_clamps_at_walls_follows_slopes_and_does_not_relocate_airborne_mobs() -> void:
	var w := CF.world({"knockback": {"chance_field": "prop", "distance": 120}})
	w.bounds = Rect2(0, -500, 1000, 1000)
	w.fhm = FootholdMap.from_segments([
		{"x1": 0, "y1": 200, "x2": 1000, "y2": 200},
		{"x1": 400, "y1": 200, "x2": 400, "y2": 100}])
	w.swarm.fhm = w.fhm
	var m := RF.put_mob(w, 1110100, 350, 190, 100)
	w.hit_mob(m, w.loadout.stats("synthetic"), -1)
	assert_near(w.swarm.x[m], 400 - FootholdMap.EPS, 0.001)
	w.fhm = FootholdMap.from_segments([
		{"x1": 0, "y1": 200, "x2": 400, "y2": 200},
		{"x1": 400, "y1": 200, "x2": 600, "y2": 100}])
	w.swarm.x[m] = 350
	w.swarm.y[m] = 200
	w.swarm.fh[m] = 0
	w.hit_mob(m, w.loadout.stats("synthetic"), -1)
	assert_eq(w.swarm.pos(m), Vector2(470, 165), "follows the slope across the linked foothold")
	assert_eq(w.swarm.fh[m], 1)
	w.swarm.fh[m] = -1
	var before := w.swarm.pos(m)
	w.hit_mob(m, w.loadout.stats("synthetic"), -1)
	assert_eq(w.swarm.pos(m), before, "no ground destination invented for an airborne mob")


## Survivor combat data controls the floor; changing it affects later contacts without changing the first hit.
func test_pierce_floor_comes_from_survivor_combat_data() -> void:
	var setup := CF.world().setup.duplicate(true)
	setup.data.balance["combat"] = {"pierce_floor": 0.25}
	setup.data.skills.skills.synthetic["pierce_falloff"] = 0.5
	var w := RunWorld.new(setup)
	var text := SkillText.new(w.book)
	assert_true(text.level_line("synthetic", 1, w.loadout.stats("synthetic", 1)).contains("minimum 25%"))
	assert_true(text.level_line("synthetic", 1, w.loadout.clone().stats("synthetic", 1)).contains("minimum 25%"))
	w.loadout.order.clear()
	for k in 4:
		RF.put_mob(w, 1110100, 300 + k * 80, 190, 100)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.projectiles.spawn({"x": 200, "y": 180, "vx": 600, "range": 800,
		"dmg_min": 100, "dmg_max": 100, "pierce": 3, "pierce_falloff": 0.5})
	for tick in 60:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
	var hits := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.damage)), [100, 50, 25, 25])


func test_pierce_falloff_is_linear_with_a_floor_and_absent_key_keeps_full_damage() -> void:
	for falloff: float in [0.0, 0.1, 0.5]:
		var w := CF.world()
		w.loadout.order.clear()
		var mobs: Array[int] = []
		for k in 6:
			mobs.append(RF.put_mob(w, 1110100, 300 + k * 80, 190, 100))
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
		var spec := {"x": 200, "y": 180, "vx": 600, "vy": 0, "range": 800,
			"dmg_min": 100, "dmg_max": 100, "pierce": 5, "skill": "synthetic"}
		if falloff > 0:
			spec["pierce_falloff"] = falloff
		w.projectiles.spawn(spec)
		for tick in 60:
			w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
		var hits := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
		assert_eq(hits.size(), 6)
		var expected: Array = [100, 100, 100, 100, 100, 100]
		if falloff == 0.1:
			expected = [100, 90, 80, 70, 60, 50]
		elif falloff == 0.5:
			expected = [100, 50, 10, 10, 10, 10]
		assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.damage)), expected)


func test_impact_blast_hits_the_box_caps_including_primary_and_applies_stun() -> void:
	var w := CF.world({"kind": "projectile", "radius": 1,
		"impact_blast": {"visual": "hit"},
		"on_hit": {"status": "stun", "chance_field": "prop", "duration_field": "time"}})
	var primary := RF.put_mob(w, 1110100, 350, 190, 100)
	var near := RF.put_mob(w, 1110100, 380, 190, 100)
	var third := RF.put_mob(w, 1110100, 410, 190, 100)
	var capped := RF.put_mob(w, 1110100, 425, 190, 100)
	var outside := RF.put_mob(w, 1110100, 520, 190, 100)
	for tick in 25:
		w.step(DT, MoveInput.new())
	var hits := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [primary, near, third])
	for m: int in [primary, near, third]:
		assert_true(w.swarm.status_time(m, MobSwarm.STUN) > 2.5, "splash is an ordinary on-hit")
	for m: int in [capped, outside]:
		assert_eq(w.swarm.hp[m], w.swarm.max_hp[m], "cap and box both exclude mobs")
	var blasts := w.events.filter(func(e: Dictionary) -> bool: return e.type == "skill_impact")
	assert_eq(blasts.size(), 1, "one burst at the first projectile impact")


func test_impact_blast_can_read_physical_damage_from_a_different_canonical_field() -> void:
	var w := CF.world({"kind": "projectile", "damage": "physical", "impact_blast": {"damage_field": "x"}})
	assert_near(float(w.loadout.stats("synthetic").damage_pct), 0.72)
	w.loadout.set_rank("synthetic", 2)
	assert_near(float(w.loadout.stats("synthetic").damage_pct), 1.3)


func test_blast_snapshots_level_and_selects_before_knockback_or_primary_death() -> void:
	var w := CF.world({"kind": "projectile", "impact_blast": {},
		"knockback": {"chance_field": "prop", "distance": 120},
		"on_hit": {"status": "stun", "chance_field": "prop", "duration_field": "time"}})
	var primary := RF.put_mob(w, 1110100, 350, 190, 100)
	var splash := RF.put_mob(w, 1110100, 390, 190, 100)
	for m: int in [primary, splash]:
		w.mob_kinds[w.swarm.kind[m]].move_speed = 0
	w.swarm.hp[primary] = 1
	w.step(DT, MoveInput.new()) # launch at rank 1
	w.loadout.set_rank("synthetic", 2) # rank 2 has zero prop and a different duration/cap
	for tick in 25:
		w.step(DT, MoveInput.new())
	assert_false(w.swarm.is_live(primary))
	assert_near(w.swarm.x[splash], 510, 0.01, "splash selected at the original impact point, then knocked back")
	assert_true(w.swarm.status_time(splash, MobSwarm.STUN) > 2.5, "rank 1 status parameters captured at launch")
	var impact := w.events.filter(func(e: Dictionary) -> bool: return e.type == "skill_impact")
	assert_eq(impact[0].pos, Vector2(350, 200), "art stays at the pre-knockback impact point")


func test_projectile_pool_reuse_clears_blast_and_falloff() -> void:
	var w := CF.world()
	var first := RF.put_mob(w, 1110100, 350, 190, 100)
	var second := RF.put_mob(w, 1110100, 400, 190, 100)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var old := w.projectiles.spawn({"pierce_falloff": 0.5,
		"impact_blast": {"box": Rect2(-100, -60, 200, 60), "count": 6, "visual": "burst"}})
	w.projectiles.despawn(old)
	var fresh := w.projectiles.spawn({"x": 200, "y": 180, "vx": 600, "range": 800,
		"dmg_min": 100, "dmg_max": 100, "pierce": 1})
	assert_eq(fresh, old, "fixture: reused shot slot")
	for tick in 30:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
	var hits := w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [first, second])
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.damage)), [100, 100])
	assert_false(w.events.any(func(e: Dictionary) -> bool: return e.type == "skill_impact"))


func test_ranged_final_attack_fires_current_ammo_with_immediate_unchanged_damage_rolls() -> void:
	for row: Array in [[1452000, 310, 2060002], [1462000, 320, 2061002],
			[1472000, 410, 2070003], [1492000, 520, 2330001]]:
		var w := CF.ranged_final(row[0], row[1])
		var m := RF.put_mob(w, 1110100, 380, 190, 100)
		w.mob_kinds[w.swarm.kind[m]].move_speed = 0
		var st := w.loadout.stats("synthetic")
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.state = w.final_rng.state
		var mk := w.swarm.mob_kind(m)
		var expected := ProjectileSystem.roll_damage(st.damage_min, st.damage_max, false, mk.pdd,
			w.projectiles.magic_defense_k, st.crit, st.crit_mult, expected_rng, 1.0, "physical",
			st.damage_pct, st.crit_damage_bonus)
		w.hit_mob(m, {"skill": "trigger", "damage_type": "physical", "damage_min": 1,
			"damage_max": 1, "crit": 0, "crit_mult": 1.5}, -1)
		w.step(DT, MoveInput.new())
		var hits := w.events.filter(func(e: Dictionary) -> bool:
			return e.type == "mob_hit" and e.skill == "synthetic")
		assert_eq(hits.size(), 1, "follow-up damage is still immediate")
		assert_eq(hits[0].damage, expected.x)
		assert_eq(hits[0].crit, expected.y != 0)
		assert_eq(w.final_rng.state, expected_rng.state, "visual draws no RNG")
		var shots := w.events.filter(func(e: Dictionary) -> bool: return e.type == "ammo_shot")
		assert_eq(shots.size(), 1, "ranged follow-up announces one visual shot")
		if shots.size() == 1:
			assert_eq(w.ammo_id(), row[2], "upgraded current ammo")
			assert_eq(shots[0].ball, Ammo.bullet_path(row[2]))
			assert_eq(shots[0].to, w.mob_center(m))
			assert_true(shots[0].seconds > 0)
		assert_eq(w.projectiles.active_count(), 0, "the visual cannot deal a second delayed hit")


func test_ranged_final_attack_spread_uses_the_ranged_reach() -> void:
	var w := CF.ranged_final(1452000, 310)
	w.loadout.add_skill_mod("synthetic", "count", "add", 1)
	var primary := RF.put_mob(w, 1110100, 350, 190, 100)
	var nearby := RF.put_mob(w, 1110100, 550, 190, 100)
	var far := RF.put_mob(w, 1110100, 850, 190, 100)
	for m: int in [primary, nearby, far]:
		w.mob_kinds[w.swarm.kind[m]].move_speed = 0
	w.hit_mob(primary, {"skill": "trigger", "damage_type": "physical", "damage_min": 1,
		"damage_max": 1, "crit": 0, "crit_mult": 1.5}, -1)
	w.step(DT, MoveInput.new())
	var hits := w.events.filter(func(e: Dictionary) -> bool:
		return e.type == "mob_hit" and e.skill == "synthetic")
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [primary, nearby])


func test_cards_and_skill_text_preview_knockback_blast_targets_and_falloff() -> void:
	var w := CF.world({"kind": "projectile", "knockback": {"chance_field": "prop", "distance": 120},
		"impact_blast": {"damage_field": "x"}, "pierce_falloff": 0.1})
	w.upgrades = UpgradePool.from_data({"cards": [
		{"id": "rank", "kind": "skill_rank", "skill": "synthetic", "max_rank": 2},
		{"id": "blast", "kind": "skill_mod", "skill": "synthetic", "effects": [
			{"stat": "blast_targets", "op": "add", "value": 1}]},
		{"id": "falloff", "kind": "skill_mod", "skill": "synthetic", "effects": [
			{"stat": "pierce_falloff", "op": "add", "value": -0.05}]}]})
	var rank := w.upgrades.choice_card("rank", w)
	assert_eq(rank.skill_changes.get("knockback_chance"), {"before": 100, "after": 0})
	assert_eq(rank.skill_changes.get("blast_targets"), {"before": 3, "after": 4})
	assert_eq(rank.skill_changes.get("damage"), {"before": 72, "after": 130}, "the selected field is damage, not MP absorption")
	assert_false(rank.skill_changes.has("x"))
	var lines := "\n".join(LevelUpWindow.change_lines(rank))
	assert_true(lines.contains("Knock-back chance: 100%"))
	assert_true(lines.contains("Blast targets: 3"))
	var blast := w.upgrades.choice_card("blast", w)
	assert_eq(blast.skill_mod_changes.get("blast_targets"), {"before": 3, "after": 4})
	var falloff := w.upgrades.choice_card("falloff", w)
	assert_eq(falloff.skill_mod_changes.get("pierce_falloff"), {"before": 10.0, "after": 5.0})
	assert_true("\n".join(LevelUpWindow.change_lines(falloff)).contains("Pierce fall-off: 10%"))
	var text := SkillText.new(w.book)
	var current := text.level_line("synthetic", 1, w.loadout.stats("synthetic"))
	assert_true(current.contains("Knock-back: 100%"))
	assert_true(current.contains("Blast: 3 targets"))
	assert_true(current.contains("Pierce fall-off: 10%"))
	w.upgrades.apply("blast", w)
	assert_eq(w.loadout.stats("synthetic").count, 1, "a blast-target card does not add shots")
	var dressed := text.dress([rank], w.loadout)
	assert_true(String(dressed[0].desc).contains("Knock-back: 0%"))
	assert_true(String(dressed[0].desc).contains("Blast: 5 targets"))
