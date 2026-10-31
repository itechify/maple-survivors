extends TestCase
## The Mu Lung region (spec #449 C4, ticket #466; tier C rules in docs/GAME_DESIGN.md "Mu Lung (C4) constants"):
## `stages/mu_lung.json`, its manifest fragment and `mobs.json` entries, Sleepywood's curve numbers, the level scale and
## the three bosses. Parts that read canonical data (pools from the maps' life lists, the bosses' skills) are
## cache-backed and SKIP without the asset cache.

const CAL := preload("res://tests/calibrated_levels.gd")
const KEY := "mu_lung"
const MAPS := [250010300, 250010301, 250010700]
const BOSSES := [5220004, 7220000, 7220002]
## Each boss's scheduled attacks (the stances its Mob.wz img has).
const BOSS_ATTACKS := [["attack1", "attack2", "attack3"], ["attack1", "attack2"], ["attack1"]]
## The Etc drops used as EXP pickups, by mob (ordinary monsters and bosses).
const EXP_ITEMS := {4230502: 4000278, 4230503: 4000281, 4230504: 4000281, 5120500: 4000283, 5120505: 4000021,
	6130207: 4000282, 5220004: 4031227, 7220000: 4000284, 7220002: 4000298}
## MobSkill ids this region's bosses list that the runner skips for good (none: every kit here is supported).
const KNOWN_SKIPPED_SKILLS := [120]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_follows_ludibrium_in_the_progression() -> void:
	var order: Array = data.stages.progression
	assert_true(order.has(KEY), "mu_lung is in the progression")
	assert_true(order.find(KEY) > order.find("ludibrium"), "Mu Lung comes after Ludibrium (step 9 of the final order)")
	assert_eq(String(stage.get("region", "")), "Mu Lung")
	assert_eq(String(stage.get("continent", "")), "Ossyria", "String.wz group ossyria")
	assert_eq(stage.get("drop_band"), [50.0, 60.0], "#447's drop band")
	assert_false(String(stage.get("note", "")).is_empty(), "a one-line note")
	assert_eq(stage.get("original_life"), {"4230502": 9.0, "4230503": 11.0, "4230504": 7.0}, "map 1's own spawn list")
	assert_eq(DataRepo.stage_label_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray())


func test_three_maps_with_pool_rules_and_no_exclusions() -> void:
	assert_eq(stage.get("map_seconds"), 300)
	var maps: Array = stage.get("maps", [])
	assert_eq(maps.size(), 3)
	for i in maps.size():
		assert_eq(int(maps[i].map_id), MAPS[i], "map %d" % (i + 1))
		assert_false(maps[i].has("exclude"), "map %d: its life list holds no timed, hidden or event entries" % (i + 1))
		assert_false(maps[i].has("opening_ramp"), "map %d: level_scale replaces the opening ramp" % (i + 1))
	assert_eq(maps[0].pool, "curve", "map 1 is a hand-written curve pool")
	assert_true(bool(maps[1].get("pool_from_life", false)), "map 2 takes its life list")
	assert_true(bool(maps[2].get("pool_from_life", false)), "map 3 takes its life list")
	assert_true(String(stage.get("_maps", "")).contains("Tier C"), "_maps records the arena choice")


func test_map_one_keyframe_pools_use_only_its_own_roster() -> void:
	var roster := ["4230502", "4230503", "4230504"]
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		for id: String in kf.pool:
			assert_has(roster, id, "pool mob %s is on Snake Area" % id)
	assert_eq(pooled, 2)
	assert_eq(stage.keyframes[0].pool, {"4230502": 1.0}, "Black Porky opens alone")


func test_the_curve_copies_sleepywoods_numbers_and_has_no_opening_ramp() -> void:
	var ref: Dictionary = data.stages.stages.sleepywood
	assert_false(stage.has("opening_ramp"), "no opening_ramp")
	for field: String in ["bursts", "elites", "exp_mult", "hard_cap", "duration", "post_duration_slope"]:
		assert_eq(stage.get(field), ref.get(field), "%s copies Sleepywood" % field)
	assert_eq(stage.keyframes.size(), ref.keyframes.size())
	for i in ref.keyframes.size():
		for field: String in ["t", "rate", "max_alive", "hp", "speed"]:
			assert_eq(stage.keyframes[i][field], ref.keyframes[i][field], "keyframe %d %s" % [i, field])
	assert_eq(float(stage.keyframes[-1].t), float(stage.duration), "a keyframe at the clear time")


func test_level_scale_is_present_valid_and_twelve_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level), CAL.level_at(float(kfs[i].exp_level), float(kfs[i].t), 9), 0.011,
			"step 9: the calibrated level (C13): 1 at 0:00 rising to Sleepywood's pace + CAL.ABOVE at 10:00, keyframe %d" % i)
	assert_true(String(stage.get("_level_scale", "")).contains("Tier C"), "a _tier note")


func test_bosses_are_scheduled_with_tier_notes_and_enabled_kits() -> void:
	var bosses := DataRepo.stage_bosses(stage)
	assert_eq(bosses.size(), 3)
	for i in bosses.size():
		var boss: Dictionary = bosses[i]
		assert_eq(int(boss.mob_id), BOSSES[i], "map %d boss" % (i + 1))
		assert_eq(int(boss.map_time), 300, "a boss 300 s after each entry")
		assert_eq(boss.attacks, BOSS_ATTACKS[i], "the boss's own WZ attacks")
		assert_eq(int(boss.attack_interval), 8)
		assert_false(boss.has("final_form"), "no final form in Mu Lung")
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_mu_lung.json")
	for map_id: int in MAPS:
		assert_has(fragment.maps, float(map_id), "the fragment imports map %d" % map_id)
		assert_has(manifest.maps, float(map_id), "the merged manifest has map %d" % map_id)
	for id: int in EXP_ITEMS:
		var mob: Dictionary = data.mobs.mobs.get(str(id), {})
		assert_false(String(mob.get("name", "")).is_empty(), "mob %d has an English fallback name" % id)
		assert_eq(int(mob.get("exp_item", 0)), EXP_ITEMS[id], "mob %d EXP item" % id)
		assert_has(fragment.mobs, float(id), "the fragment imports mob %d" % id)
		assert_has(manifest.mobs, float(id), "the merged manifest has mob %d" % id)
		assert_has(manifest.items, float(EXP_ITEMS[id]), "EXP art %d is imported" % EXP_ITEMS[id])
	for id: int in DataRepo.stage_mob_ids(data, KEY):
		assert_true(EXP_ITEMS.has(id), "stage mob %d is a known Mu Lung mob" % id)
	for id: int in [4230502, 4230503, 4230504, 5120500, 5120505, 6130207]:
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_true(float(mesos[0]) > 0.0 and float(mesos[0]) < float(mesos[1]), "mob %d range is ordered" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	assert_eq(data.mobs.mobs["5220004"].boss_ui.icon_id, 6220000, "Giant Centipede borrows Dyle's icon: v83 has none for it")


func test_pools_resolve_to_the_maps_own_life_lists() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var want := [{4230502: 9.0, 4230503: 11.0, 4230504: 7.0}, {5120500: 19.0}, {5120505: 4.0, 6130207: 20.0}]
	for i in MAPS.size():
		var img := lib.img(DataRepo.map_img_path(MAPS[i]))
		if img == null:
			skip("map img not imported: %d" % MAPS[i])
			lib.free()
			return
		var life := StagePools.resolve({"pool_from_life": true}, img.root)
		assert_eq(life, want[i], "map %d v83 life counts" % (i + 1))
		var pool := StagePools.resolve(stage.maps[i], img.root)
		if i > 0:
			assert_eq(pool, want[i], "map %d takes its life list" % (i + 1))
		for id: int in life:
			assert_true(lib.img("Mob.wz/%07d.img" % id) != null, "mob %d is imported" % id)
	lib.free()


func test_each_boss_skill_resolves_to_a_supported_id_or_the_known_skip() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var table := lib.img("Skill.wz/MobSkill.img")
	if table == null:
		skip("the cache has no Skill.wz/MobSkill.img")
		lib.free()
		return
	var listed := {}
	for i in BOSSES.size():
		var id: int = BOSSES[i]
		var img := lib.img("Mob.wz/%07d.img" % id)
		if img == null:
			skip("boss %d is not imported" % id)
			lib.free()
			return
		var info: Dictionary = img.root.info
		assert_true(float(info.get("boss", 0)) == 1.0, "%d is a v83 boss" % id)
		var skills: Dictionary = info.get("skill", {})
		for entry: Dictionary in skills.values():
			var skill := int(entry.skill)
			listed[skill] = true
			assert_true(skill in MobSkillRunner.SUPPORTED or skill in KNOWN_SKIPPED_SKILLS,
				"boss %d lists MobSkill %d: supported or a known skip" % [id, skill])
			assert_true(table.root.has(str(skill)), "MobSkill.img has %d" % skill)
		for attack: String in BOSS_ATTACKS[i]:
			assert_true(img.root.has(attack), "%d has %s" % [id, attack])
			assert_true(int(img.root[attack].info.type) in [0, 1, 2], "%d %s is a supported attack type" % [id, attack])
	for skill: int in [110, 112, 113, 114, 140, 200]:
		assert_true(listed.has(skill), "the kits list MobSkill %d" % skill)
	assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/7220000.img").root, table.root), PackedInt32Array([5120500]),
		"Tae Roon's MobSkill 200 summons Grizzlies")
	assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/7220002.img").root, table.root), PackedInt32Array(), "King Sage Cat summons nothing")
	assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/5220004.img").root, table.root), PackedInt32Array(), "Giant Centipede casts nothing")
	lib.free()
