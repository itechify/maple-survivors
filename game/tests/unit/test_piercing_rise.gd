extends TestCase
## Marksman MS4: signed piercing curves through synthetic, seeded fixed-tick contacts.

const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _line(w: RunWorld, count: int = 6) -> void:
	w.loadout.order.clear()
	for k in count:
		RF.put_mob(w, 1110100, 300 + k * 40, 190, 10000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)


func _fly(w: RunWorld, allowed := PackedByteArray()) -> Array:
	for tick in 60:
		w.projectiles.step(DT, w.swarm, w.mob_grid, w.events, PackedFloat32Array(), allowed)
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit").map(
		func(e: Dictionary) -> int: return int(e.damage))


func _shot() -> Dictionary:
	return {"x": 200, "y": 180, "vx": 600, "range": 800, "radius": 1,
		"dmg_min": 100, "dmg_max": 100, "pierce": 5, "pierce_falloff": -0.1}


func test_negative_fraction_rises_across_six_contacts() -> void:
	var w := CF.world()
	_line(w)
	w.projectiles.spawn(_shot())
	assert_eq(_fly(w), [100, 110, 120, 130, 140, 150])


func test_curve_preserves_old_float_bytes_and_bounds_the_rise() -> void:
	for fraction: float in [0.0, 0.1, 0.5]:
		for n in 16:
			var old := maxf(0.1, 1.0 - fraction * n)
			assert_eq(var_to_bytes(PierceCurve.factor(n + 1, fraction, 0.1, 2.0)), var_to_bytes(old))
	assert_eq(PierceCurve.factor(16, -0.1, 0.1, 2.0), 2.0)
	assert_eq(PierceCurve.factor(6, -0.1, 0.1, 1.25), 1.25)


func test_ceiling_is_data_driven_captured_at_launch_and_reuse_resets_rise() -> void:
	var setup := CF.world().setup.duplicate(true)
	setup.data.balance.combat.pierce_ceiling = 1.25
	var w := RunWorld.new(setup)
	_line(w)
	var shot := _shot()
	var old := w.projectiles.spawn(shot)
	shot.pierce_falloff = -0.9
	w.projectiles.pierce_ceiling = 9.0
	assert_eq(_fly(w), [100, 110, 120, 125, 125, 125])
	w.events.clear()
	shot.erase("pierce_falloff")
	var fresh := w.projectiles.spawn(shot)
	assert_eq(fresh, old)
	assert_eq(_fly(w), [100, 100, 100, 100, 100, 100])


func test_immune_contact_consumes_index_and_critical_bonus_is_inside_the_factor() -> void:
	var w := CF.world()
	_line(w)
	var shot := _shot()
	shot.damage_pct = 2.0
	shot.crit_damage_bonus = 50.0
	shot.crit = 1.0
	w.projectiles.spawn(shot)
	var allowed := PackedByteArray()
	allowed.resize(w.swarm.capacity())
	allowed.fill(1)
	allowed[0] = 0
	assert_eq(_fly(w, allowed), [275, 300, 325, 350, 375])


func test_signed_loadout_preview_and_card_added_contacts_capture_at_cast() -> void:
	var w := CF.world({"kind": "projectile", "pierce": 5, "pierce_falloff": -0.1})
	_line(w, 7)
	for m in 7:
		w.mob_kinds[w.swarm.kind[m]].hitbox = Rect2(-2, -10, 4, 10)
		w.swarm.y[m] = w.cast_origin().y + 5.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.loadout.order.append("synthetic")
	w.loadout.add_skill_mod("synthetic", "crit", "add", -1.0)
	w.loadout.add_skill_mod("synthetic", "pierce", "add", 1)
	assert_eq(w.loadout.stats("synthetic").pierce_falloff, -0.1)
	w.runner.step(DT, w)
	w.loadout.add_skill_mod("synthetic", "pierce_falloff", "add", -0.5)
	assert_eq(_fly(w), [100, 110, 120, 130, 140, 150, 160])


func test_skill_and_card_previews_describe_rise_as_positive_points() -> void:
	var w := CF.world({"kind": "projectile", "pierce_falloff": -0.1})
	var text := SkillText.new(w.book)
	for lo: Loadout in [w.loadout, w.loadout.clone()]:
		var line := text.level_line("synthetic", 1, lo.stats("synthetic"))
		assert_true(line.contains("+10 points per later monster"), line)
		assert_true(line.contains("maximum 200%"), line)
	w.book.defs.synthetic["rarity_bonuses"] = {
		"epic": [{"id": "rise", "text": "Rise", "effects": [
			{"stat": "pierce_falloff", "op": "add", "value": -0.1}]}]}
	w.upgrades = UpgradePool.from_data({"cards": [
		{"id": "rank", "kind": "skill_rank", "skill": "synthetic", "max_rank": 2}]})
	var card := w.upgrades.choice_card("rank", w, "epic")
	assert_eq(card.skill_mod_changes.pierce_falloff, {"before": -10.0, "after": -20.0})
	var lines := "\n".join(LevelUpWindow.change_lines(card))
	assert_true(lines.contains("+10 points per later monster"), lines)
	assert_true(lines.contains("+20 points per later monster"), lines)
