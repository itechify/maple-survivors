extends TestCase
## The level-scale draft tool's formulas (tools/level_scale_draft.gd, spec #449 C0): pure static functions on synthetic
## curves and stages, then the whole draft on a synthetic reference stage; one cache-backed check on the shipped Sleepywood.

const D := preload("res://tools/level_scale_draft.gd")


## hp = 100 l^2, pad = 10 l, mad = 20 l + 100 (as test_level_scale's curves): distinct, strictly rising.
func _curve() -> Dictionary:
	var out := {"hp": [], "pad": [], "mad": []}
	for level in range(1, 201):
		out.hp.append(100.0 * level * level)
		out.pad.append(10.0 * level)
		out.mad.append(20.0 * level + 100.0)
	return out


## A two-map reference stage: map 1 on keyframe pools (mob 1 only, then 1 and 2), map 2 from its life (mob 3 x3, mob 4 x1).
func _stage() -> Dictionary:
	return {"map_seconds": 300, "opening_ramp": {"seconds": 1000, "hp": {"start": 0.5, "end": 1.0},
			"damage": {"start": 0.25, "end": 1.0}},
		"maps": [
			{"map_id": 1, "pool": "curve", "boss": {"time": 300, "mob_id": 10, "hp_mult": 2.0, "dmg_mult": 0.5,
				"attack_dmg_mult": 0.5, "attacks": ["attack1"]}},
			{"map_id": 2, "pool_from_life": true, "opening_ramp": {"seconds": 1000, "power": 2.0,
					"hp": {"start": 1.0, "end": 1.0}, "damage": {"start": 1.0, "end": 1.0}},
				"boss": {"time": 300, "mob_id": 11, "hp_mult": 1.0, "dmg_mult": 1.0}}],
		"keyframes": [
			{"t": 0, "pool": {"1": 1}}, {"t": 200, "pool": {"1": 1, "2": 1}}, {"t": 300}, {"t": 450}]}


func _map_imgs() -> Array:
	return [{}, {"life": {"0": {"type": "m", "id": 3}, "1": {"type": "m", "id": 3}, "2": {"type": "m", "id": 3},
		"3": {"type": "m", "id": 4}, "4": {"type": "m", "id": 5, "hide": 1}, "5": {"type": "n", "id": 6}}}]


func _mobs() -> Dictionary:
	return {
		1: {"info": {"level": 10, "maxHP": 10000, "PADamage": 100}},
		2: {"info": {"level": 20, "maxHP": 40000, "PADamage": 200}},
		3: {"info": {"level": 30, "maxHP": 90000, "PADamage": 300}},
		4: {"info": {"level": 40, "maxHP": 160000, "PADamage": 400}},
		10: {"info": {"level": 15, "maxHP": 22500, "PADamage": 150}, "attack1": {"info": {"PADamage": 200}}},
		11: {"info": {"level": 20, "maxHP": 40000, "PADamage": 200}, "attack1": {"info": {"PADamage": 250}},
			"attack2": {"info": {"PADamage": 220}}},
		# the new region's bosses
		20: {"info": {"level": 30, "maxHP": 90000, "PADamage": 300}, "attack1": {"info": {"PADamage": 400}}},
		21: {"info": {"level": 40, "maxHP": 160000, "PADamage": 400, "MADamage": 500},
			"attack1": {"info": {"MADamage": 600}}, "attack2": {"info": {"PADamage": 450}}},
		22: {"info": {"level": 40, "maxHP": 160000, "PADamage": 400}},
	}


func _root(id: int) -> Dictionary:
	return _mobs().get(id, {})


func test_effective_level_inverts_the_curve_with_interpolation() -> void:
	var hp: Array = _curve().hp
	assert_near(D.effective_level(hp, 100.0 * 40.0 * 40.0), 40.0)
	assert_near(D.effective_level(hp, (100.0 * 40.0 * 40.0 + 100.0 * 41.0 * 41.0) / 2.0), 40.5, 1e-9)
	assert_eq(D.effective_level(hp, 1.0), 1.0, "below the first level")
	assert_eq(D.effective_level(hp, 1.0e12), 200.0, "above the last level")
	assert_near(D.curve_at(hp, 40.5), (100.0 * 40.0 * 40.0 + 100.0 * 41.0 * 41.0) / 2.0, 1e-6)
	# A plateau reaches the target at its first level.
	assert_eq(D.effective_level([1.0, 5.0, 5.0, 9.0], 5.0), 2.0)


func test_mean_hp_is_weighted_and_empty_pools_are_zero() -> void:
	var hp := func(id: int) -> float: return float(id) * 10.0
	assert_near(D.mean_hp({1: 3.0, 5: 1.0}, hp), (3.0 * 10.0 + 1.0 * 50.0) / 4.0)
	assert_eq(D.mean_hp({}, hp), 0.0)


func test_ramp_value_follows_the_runworld_arithmetic() -> void:
	# Sleepywood's documented map-2/3 ramp (GAME_DESIGN 4.1 #307): HP .02 -> 1 and damage .08 -> 1, power 3, 1200 s.
	var ramp := {"seconds": 1200, "power": 3, "hp": {"start": 0.02, "end": 1.0}, "damage": {"start": 0.08, "end": 1.0}}
	assert_near(D.ramp_value(ramp, "hp", 600.0), 0.1425, 1e-4)
	assert_near(D.ramp_value(ramp, "damage", 600.0), 0.195, 1e-4)
	assert_eq(D.ramp_value(ramp, "hp", 5000.0), 1.0, "past the end")
	assert_eq(D.ramp_value({}, "hp", 100.0), 1.0, "no ramp")


func test_map_and_pool_follow_curve_time() -> void:
	var stage := _stage()
	assert_eq([D.map_index_at(stage, 0.0), D.map_index_at(stage, 299.0), D.map_index_at(stage, 300.0),
		D.map_index_at(stage, 900.0)], [0, 0, 1, 1], "the map being entered at a boundary; the last map after")
	assert_eq(D.arrival_time(stage, 0), 300.0)
	assert_eq(D.arrival_time(stage, 1), 600.0)
	var pools := [{}, {3: 3.0, 4: 1.0}]
	assert_eq(D.pool_at(stage, pools, 0.0), {1: 1.0})
	assert_eq(D.pool_at(stage, pools, 199.0), {1: 1.0})
	assert_eq(D.pool_at(stage, pools, 200.0), {1: 1.0, 2: 1.0})
	assert_eq(D.pool_at(stage, pools, 299.0), {1: 1.0, 2: 1.0}, "map 1 keeps its last keyframe pool")
	assert_eq(D.pool_at(stage, pools, 300.0), {3: 3.0, 4: 1.0})


func test_scale_keyframes_add_the_step_offset_and_keep_the_reference_exp_level() -> void:
	var keys := D.scale_keyframes([0.0, 120.0, 900.0], [10.0, 20.123, 40.0], 6)
	assert_eq(keys, [{"t": 0, "level": 13.0, "exp_level": 10.0}, {"t": 120, "level": 23.12, "exp_level": 20.12},
		{"t": 900, "level": 43.0, "exp_level": 40.0}])
	assert_eq(D.scale_keyframes([0.0], [10.0], 16)[0].level, 43.0, "step 16: 3 x 11 levels above")
	assert_eq(D.scale_keyframes([0.0], [10.0], 5)[0].level, 10.0, "Sleepywood's own step adds nothing")
	assert_eq(D.scale_keyframes([0.0], [10.0], 8, 5.0)[0].level, 25.0, "a different per-step offset")
	assert_eq(Array(LevelScale.block_errors("x", {"keyframes": keys})), [], "the block passes the schema")


func test_levels_above_131_are_warned_about() -> void:
	assert_eq(D.level_warnings([{"t": 0, "level": 131.0, "exp_level": 131.0}, {"t": 60, "level": 40.0}]).size(), 0)
	var warnings := D.level_warnings([{"t": 0, "level": 20.0, "exp_level": 20.0}, {"t": 900, "level": 131.5, "exp_level": 90.0}])
	assert_eq(warnings.size(), 1)
	assert_true(warnings[0].contains("t=900") and warnings[0].contains("level") and warnings[0].contains("131"), warnings[0])
	assert_eq(D.level_warnings([{"t": 1, "level": 50.0, "exp_level": 140.0}]).size(), 1, "exp_level counts too")


func test_canonical_boss_picks_the_strongest_scheduled_attack() -> void:
	var all: Dictionary = D.canonical_boss(_root(21), [])
	assert_eq([all.level, all.hp, all.pad, all.attack, all.magic], [40, 160000.0, 400.0, 600.0, true], "every attackN stance")
	var physical: Dictionary = D.canonical_boss(_root(21), ["attack2"])
	assert_eq([physical.attack, physical.magic], [450.0, false])
	var none: Dictionary = D.canonical_boss(_root(22), [])
	assert_eq([none.attack, none.magic], [0.0, false], "no attack stance")
	var names := ["attack1"]
	D.canonical_boss(_root(10), names)
	assert_eq(names, ["attack1"], "the caller's list is not changed")


func test_boss_effective_applies_multipliers_and_the_ramp_at_arrival() -> void:
	var stage := _stage()
	var entry: Dictionary = stage.maps[0].boss
	var effective: Dictionary = D.boss_effective(entry, D.canonical_boss(_root(10), ["attack1"]), D.ramp_of(stage, 0), 300.0)
	# stage ramp at t=300: progress .3: HP .5 + .5*.3 = .65, damage .25 + .75*.3 = .475
	assert_near(effective.hp, 22500.0 * 2.0 * 0.65, 1e-6)
	assert_near(effective.touch, 150.0 * 0.5 * 0.475, 1e-6)
	assert_near(effective.attack, 200.0 * 0.5 * 0.475, 1e-6)


func test_match_boss_hits_the_level_scaled_target_and_is_independent_of_the_offset() -> void:
	var curve := _curve()
	var reference := {"hp": 1.0e6, "touch": 1000.0, "attack": 2000.0, "magic": false}
	var canon: Dictionary = D.canonical_boss(_root(20), ["attack1"])
	var e := 30.0
	var level := 39.0
	var m: Dictionary = D.match_boss(reference, curve, e, canon, level)
	# Effective HP of the new boss under the level scale = canonical x hp_mult x hp(level)/hp(own level).
	var hp_target: float = reference.hp * 100.0 * 39.0 * 39.0 / (100.0 * 30.0 * 30.0)
	assert_near(canon.hp * m.hp_mult * (100.0 * 39.0 * 39.0) / (100.0 * 30.0 * 30.0), hp_target, hp_target * 1e-3)
	var touch_target: float = reference.touch * 39.0 / 30.0
	assert_near(canon.pad * m.dmg_mult * 39.0 / 30.0, touch_target, touch_target * 1e-3)
	var attack_target: float = reference.attack * 39.0 / 30.0
	assert_near(canon.attack * m.attack_dmg_mult * 39.0 / 30.0, attack_target, attack_target * 1e-3)
	assert_eq(m.attack_interval, 8)
	assert_false(m.has("final_form_hp_mult"))
	var far: Dictionary = D.match_boss(reference, curve, e, canon, 120.0)
	for key in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
		assert_near(far[key], m[key], 2e-3, "%s does not depend on the region's level" % key)


func test_match_boss_uses_mad_for_a_magic_attack_and_splits_a_final_form() -> void:
	var curve := _curve()
	var reference := {"hp": 1.0e6, "touch": 1000.0, "attack": 2000.0, "magic": false}
	var magic: Dictionary = D.canonical_boss(_root(21), ["attack1"])
	var m: Dictionary = D.match_boss(reference, curve, 30.0, magic, 39.0)
	var mad := func(l: float) -> float: return 20.0 * l + 100.0
	var target: float = reference.attack * mad.call(39.0) / mad.call(30.0)
	assert_near(magic.attack * m.attack_dmg_mult * mad.call(39.0) / mad.call(40.0), target, target * 1e-3)
	var shell: Dictionary = D.canonical_boss(_root(22), [])
	var split: Dictionary = D.match_boss(reference, curve, 30.0, magic, 39.0, 0.25, shell)
	assert_true(split.has("final_form_hp_mult"))
	# The two forms add up to the target HP, the form carrying a quarter.
	var scale_hp: float = (100.0 * 39.0 * 39.0) / (100.0 * 40.0 * 40.0)
	var first: float = magic.hp * split.hp_mult * scale_hp
	var second: float = shell.hp * split.final_form_hp_mult * scale_hp
	var hp_target: float = reference.hp * (39.0 * 39.0) / (30.0 * 30.0)
	assert_near(first + second, hp_target, hp_target * 2e-3)
	assert_near(second / (first + second), 0.25, 2e-3)
	# A boss with no contact damage leaves its multiplier at 1.
	assert_eq(D.match_boss(reference, curve, 30.0, {"level": 40, "hp": 1000.0, "pad": 0.0, "attack": 0.0, "magic": false},
		39.0).dmg_mult, 1.0)


func test_the_whole_draft_on_a_synthetic_reference_stage() -> void:
	var result: Dictionary = D.draft(_stage(), _curve(), _map_imgs(), _root, 6, [20, 21], [["attack1"], ["attack1"]], [0, 22])
	assert_eq(Array(result.errors), [])
	assert_eq(result.keyframes.size(), 4)
	# t=0: pool {1}: HP 10000 x ramp .5 = 5000 -> hp 100 l^2 -> l = sqrt(50) = 7.07 (interpolated between 7 and 8)
	var row0: Dictionary = result.rows[0]
	assert_eq([row0.map, row0.pool_hp, row0.ramp], [1, 10000.0, 0.5])
	assert_between(row0.e_ref, 7.0, 8.0)
	assert_near(result.keyframes[0].level - result.keyframes[0].exp_level, 3.0, 0.011, "one step above")
	# t=300 enters map 2: pool {3:3, 4:1} = 107500 mean HP, its own ramp (power 2) at t=300 is 1
	assert_eq([result.rows[2].map, result.rows[2].pool_hp, result.rows[2].ramp], [2, 107500.0, 1.0])
	assert_between(result.rows[2].e_ref, 32.0, 33.0)
	assert_eq(result.bosses.size(), 2)
	assert_eq(result.bosses[0].arrival, 300.0)
	assert_eq(result.bosses[1].arrival, 600.0)
	assert_false(result.bosses[0].has("final_form"))
	assert_eq(result.bosses[1].final_form, 22)
	assert_true(result.bosses[1].has("final_form_hp_mult"))
	assert_true(result.bosses[0].hp_mult > 0.0 and result.bosses[0].dmg_mult > 0.0)
	var text: String = D.describe(result, 6, "synthetic")
	assert_true(text.contains("\"level_scale\": ") and text.contains("hp_mult") and text.contains("final_form"), text)
	assert_true(text.contains("strongest scheduled attack only") and text.contains("nominal arrival level"), text)
	assert_true(D.describe(result, 6, "synthetic", "newland").contains("step 6 of newland"))
	assert_eq(result.warnings.size(), 0)


func test_bosses_are_read_from_a_stage_file_and_overrides_replace_them() -> void:
	var root := test_dir("level_scale_draft_stage")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(root.path_join("survivor/stages")))
	var write := func(rel: String, value: Dictionary) -> void:
		var file := FileAccess.open(root.path_join(rel), FileAccess.WRITE)
		file.store_string(JSON.stringify(value))
		file.close()
	write.call("survivor/stages.json", {"progression": ["newland"], "stages": {}})
	write.call("survivor/stages/newland.json", {"maps": [
		{"map_id": 1, "boss": {"mob_id": 20, "attacks": ["attack1"]}},
		{"map_id": 2, "boss": {"mob_id": 21, "attacks": ["attack2"], "final_form": 22}}]})
	var stage: Dictionary = DataRepo.load_stages(root).stages.newland
	var plan: Dictionary = D.bosses_of(stage)
	assert_eq(plan, {"bosses": [20, 21], "attacks": [["attack1"], ["attack2"]], "finals": [0, 22]})
	assert_eq(D.bosses_of(stage, [7, 8]).bosses, [7, 8], "an override replaces the ids")
	assert_eq(D.bosses_of(stage, [7, 8]).finals, [0, 22], "and leaves the other lists")
	assert_eq(D.bosses_of({}), {"bosses": [], "attacks": [], "finals": []}, "no stage file, no bosses")
	# The draft from the file equals the draft from the same lists given by hand, and uses the scheduled attacks.
	var from_file: Dictionary = D.draft(_stage(), _curve(), _map_imgs(), _root, 6, plan.bosses, plan.attacks, plan.finals)
	assert_eq(Array(from_file.errors), [])
	assert_eq(from_file.bosses[1].final_form, 22)
	var magic: Dictionary = D.canonical_boss(_root(21), ["attack2"])
	assert_false(magic.magic, "attack2 (physical) was scheduled, not the stronger magic attack1")
	remove_tree(root)


func test_the_reference_boss_reads_only_its_scheduled_attacks() -> void:
	# Mob 10 gets an unscheduled attack2 far stronger than its scheduled attack1: the draft must not move.
	var stronger := _mobs()
	stronger[10].attack2 = {"info": {"PADamage": 99999}}
	var roots := func(id: int) -> Dictionary: return stronger.get(id, {})
	var plain: Dictionary = D.draft(_stage(), _curve(), _map_imgs(), _root, 6, [20, 21], [["attack1"], ["attack1"]])
	var with_extra: Dictionary = D.draft(_stage(), _curve(), _map_imgs(), roots, 6, [20, 21], [["attack1"], ["attack1"]])
	assert_eq(with_extra.bosses[0].attack_dmg_mult, plain.bosses[0].attack_dmg_mult)
	# The new region's boss too: naming no attacks uses every stance (attack2 of 21 is weaker than its attack1 here, but
	# naming attack2 alone changes the stat), naming one narrows it.
	var narrow: Dictionary = D.draft(_stage(), _curve(), _map_imgs(), _root, 6, [20, 21], [["attack1"], ["attack2"]])
	var wide: Dictionary = D.draft(_stage(), _curve(), _map_imgs(), _root, 6, [20, 21], [["attack1"], []])
	assert_ne(narrow.bosses[1].attack_dmg_mult, wide.bosses[1].attack_dmg_mult)


func test_the_draft_reports_a_wrong_boss_count_and_missing_hp() -> void:
	var result: Dictionary = D.draft(_stage(), _curve(), _map_imgs(), _root, 6, [20])
	assert_eq(result.errors.size(), 1)
	assert_true(result.errors[0].contains("2 maps"), result.errors[0])
	var empty: Dictionary = D.draft(_stage(), _curve(), _map_imgs(), func(_id: int) -> Dictionary: return {}, 6, [20, 21])
	assert_true(empty.errors.size() == 1 and empty.errors[0].contains("no canonical HP"), str(empty.errors))
	assert_true(D.describe(empty, 6, "x").contains("ERROR"))


func test_a_high_step_warns_when_the_level_passes_131() -> void:
	# A strong pool puts E near 125; step 16 adds 33 levels.
	var stage := _stage()
	stage.opening_ramp = {}
	var curve := _curve()
	var strong := func(_id: int) -> Dictionary: return {"info": {"level": 120, "maxHP": 100.0 * 125.0 * 125.0, "PADamage": 1}}
	var result: Dictionary = D.draft(stage, curve, _map_imgs(), strong, 16, [20, 21])
	assert_true(result.warnings.size() > 0, "levels above 131 are warned about")
	assert_true(D.describe(result, 16, "x").contains("WARNING"))


func test_the_shipped_sleepywood_drafts_a_valid_block() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var stage: Dictionary = data.stages.stages.sleepywood
	var library := AssetLibrary.new()
	library.open()
	var map_imgs: Array = []
	for entry: Dictionary in stage.maps:
		var img := library.img(DataRepo.map_img_path(int(entry.map_id)))
		map_imgs.append(img.root if img != null else {})
	var roots := func(id: int) -> Dictionary: return library.mob_root(id)
	var bosses: Array = stage.maps.map(func(m: Dictionary) -> int: return int(m.boss.mob_id))
	var result: Dictionary = D.draft(stage, data.level_curve, map_imgs, roots, 5, bosses)
	library.free()
	assert_eq(Array(result.errors), [])
	assert_eq(Array(LevelScale.block_errors("sleepywood", {"keyframes": result.keyframes})), [])
	for i in result.keyframes.size():
		assert_eq(result.keyframes[i].level, result.keyframes[i].exp_level, "step 5 is Sleepywood itself")
		assert_between(result.keyframes[i].level, 1.0, 131.0)
	# Every boss gets positive multipliers (step 5 is Sleepywood's level, but the bosses are level-scaled, so they differ from the shipped ones).
	for i in result.bosses.size():
		assert_true(result.bosses[i].hp_mult > 0.0 and result.bosses[i].dmg_mult > 0.0, "boss %d" % i)
