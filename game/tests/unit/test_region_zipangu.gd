extends TestCase
## The Zipangu region (spec #449 C7, ticket #469, progression step 12; tier C rules in docs/GAME_DESIGN.md "Zipangu (C7)
## constants"): `stages/zipangu.json`, its manifest fragment and `mobs.json` entries, Sleepywood's curve numbers, the level
## scale and the three bosses. Parts that read canonical data (pools from the maps' life lists, the bosses' skills) are
## cache-backed and SKIP without the asset cache.

const KEY := "zipangu"
const MAPS := [800020110, 801030000, 800020130]
const BOSSES := [9400120, 9400121, 9400014]
## The timed native bosses of maps 2 and 3 (Male Boss mobTime 10 s, Black Crow mobTime 82800 s): never in a pool.
const MALE_BOSS := 9400120
const BLACK_CROW := 9400014
## The Armory / story copy of the Male Boss: the same mob under another id, never scheduled.
const MALE_BOSS_COPY := 9400122
## Summons of the Male Boss (MobSkill 200 levels 8-26): map 2's own pool.
const SUMMONS := [9400100, 9400101, 9400102, 9400110, 9400111]
const EXP_ITEMS := {9400004: 4000066, 9400011: 4000222, 9400013: 4000225, 9400014: 4031902, 9400100: 4000224,
	9400101: 4000223, 9400102: 4000411, 9400110: 4000412, 9400111: 4000414, 9400120: 4000413, 9400121: 4000225}
## Item 4000413 is Shade's (already in the main manifest), so the Zipangu fragment does not list it.
const IN_MAIN_MANIFEST := [4000413]
const ATTACKS := [["attack1", "attack2"], ["attack1", "attack2"], ["attack1", "attack2"]]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_follows_magatia_in_the_progression() -> void:
	var progression: Array = data.stages.progression
	assert_true(progression.has(KEY), "listed in the progression")
	assert_true(progression.find(KEY) > progression.find("magatia"), "after Magatia; step 12 once Mu Lung sits between")
	assert_eq(String(stage.get("region", "")), "Zipangu")
	assert_eq(String(stage.get("continent", "")), "Zipangu", "String.wz group jp")
	assert_eq(stage.get("drop_band"), [70.0, 80.0], "#447's drop band")
	assert_true(String(stage.get("note", "")).contains("Male Boss"), "the note names the bosses")
	assert_eq(stage.get("original_life"), {"9400011": 12.0, "9400004": 7.0}, "map 1's own spawn list")
	assert_eq(DataRepo.stage_label_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray())


func test_three_maps_with_pool_rules_and_the_timed_boss_exclusions() -> void:
	assert_eq(stage.get("map_seconds"), 300)
	var maps: Array = stage.get("maps", [])
	assert_eq(maps.size(), 3)
	for i in maps.size():
		assert_eq(int(maps[i].map_id), MAPS[i], "map %d" % (i + 1))
		assert_false(maps[i].has("opening_ramp"), "map %d: level_scale replaces the opening ramp" % (i + 1))
	assert_eq(maps[0].pool, "curve", "map 1 is a hand-written curve pool")
	assert_false(maps[0].has("exclude"), "map 1 lists no pool ids to exclude")
	assert_true(bool(maps[1].get("pool_from_life", false)), "map 2 takes its life list")
	assert_eq(maps[1].get("exclude"), [float(MALE_BOSS)], "Showa Street 3 drops its timed Male Boss")
	assert_true(bool(maps[2].get("pool_from_life", false)), "map 3 takes its life list")
	assert_eq(maps[2].get("exclude"), [float(BLACK_CROW)], "the Buddha's clearing drops its timed Black Crow")
	var rows := {"0": {"type": "m", "id": str(MALE_BOSS)}, "1": {"type": "m", "id": "9400100"}}
	assert_eq(StagePools.resolve({"pool_from_life": true, "exclude": [MALE_BOSS]}, {"life": rows}), {9400100: 1.0},
		"the Male Boss never pools")
	assert_false(BOSSES.has(MALE_BOSS_COPY), "the story copy 9400122 is not scheduled")
	assert_false(DataRepo.stage_mob_ids(data, KEY).has(MALE_BOSS_COPY), "nor loaded")


func test_map_one_keyframe_pools_are_the_lantern_ghost_and_the_cloud_fox() -> void:
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		assert_eq(kf.pool.keys(), ["9400011", "9400004"], "Paper Lantern Ghost and Big Cloud Fox, the field's whole roster")
	assert_eq(pooled, 2)
	assert_eq(stage.keyframes[0].pool, {"9400011": 12.0, "9400004": 7.0})
	assert_eq(stage.keyframes[1].pool, {"9400011": 1.0, "9400004": 1.0})
	assert_true(String(stage.get("_pools", "")).begins_with("Tier C"), "the weights carry a tier note")


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


func test_level_scale_is_present_valid_and_twenty_one_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level) - float(kfs[i].exp_level), 21.0, 0.011,
			"step 12 is 21 levels above Sleepywood's pace (3 per step after step 5)")
	assert_true(String(stage.get("_level_scale", "")).contains("Tier C"), "a _tier note")


func test_bosses_are_scheduled_with_tier_notes_and_enabled_kits() -> void:
	var bosses := DataRepo.stage_bosses(stage)
	assert_eq(bosses.size(), 3)
	for i in bosses.size():
		var boss: Dictionary = bosses[i]
		assert_eq(int(boss.mob_id), BOSSES[i], "map %d boss" % (i + 1))
		assert_eq(int(boss.map_time), 300, "a boss 300 s after each entry")
		assert_eq(boss.get("attacks", []), ATTACKS[i], "%d: its own WZ attacks" % BOSSES[i])
		assert_false(boss.has("final_form"), "no final form in Zipangu")
		assert_eq(int(boss.attack_interval), 8)
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])
		assert_false(boss.get("skill_intervals", {}).has("129"), "no boss here casts Banish")


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_zipangu.json")
	for map_id: int in MAPS:
		assert_has(fragment.maps, float(map_id), "the fragment imports map %d" % map_id)
		assert_has(manifest.maps, float(map_id), "the merged manifest has map %d" % map_id)
	for id: int in EXP_ITEMS:
		var mob: Dictionary = data.mobs.mobs.get(str(id), {})
		assert_false(String(mob.get("name", "")).is_empty(), "mob %d has an English fallback name" % id)
		assert_eq(int(mob.get("exp_item", 0)), EXP_ITEMS[id], "mob %d EXP item" % id)
		assert_true(String(mob.get("_exp_item", "")).begins_with("tier A"), "mob %d EXP item provenance" % id)
		assert_has(fragment.mobs, float(id), "the fragment imports mob %d" % id)
		assert_has(manifest.mobs, float(id), "the merged manifest has mob %d" % id)
		assert_has(manifest.items, float(EXP_ITEMS[id]), "EXP art %d is imported" % EXP_ITEMS[id])
		if not IN_MAIN_MANIFEST.has(EXP_ITEMS[id]):
			assert_has(fragment.items, float(EXP_ITEMS[id]), "the fragment imports EXP art %d" % EXP_ITEMS[id])
	for id: int in DataRepo.stage_mob_ids(data, KEY):
		assert_true(EXP_ITEMS.has(id), "stage mob %d is a known Zipangu mob" % id)
	var ranges := {9400011: [100, 150], 9400004: [150, 226], 9400100: [150, 226], 9400101: [170, 256], 9400102: [200, 300],
		9400110: [306, 460], 9400111: [324, 486], 9400013: [739, 1109]}
	for id: int in ranges:
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_eq([int(mesos[0]), int(mesos[1])], ranges[id], "mob %d range" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	for id: int in BOSSES:
		assert_false(data.mobs.mobs[str(id)].has("mesos"), "boss %d uses the level fallback" % id)
		assert_eq(data.mobs.mobs[str(id)].boss_ui.icon_id, 6220001, "boss %d borrows Zeno's icon: v83 has none" % id)
	var last := -1
	for key: String in data.mobs.mobs.keys():
		if EXP_ITEMS.has(int(key)):
			assert_true(int(key) > last, "%s inserted in id order" % key)
			last = int(key)


func test_pools_resolve_to_the_maps_own_life_lists() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var life_want := [{9400011: 12.0, 9400004: 7.0},
		{9400100: 4.0, 9400101: 3.0, 9400102: 3.0, 9400110: 4.0, 9400111: 4.0, MALE_BOSS: 1.0},
		{9400013: 15.0, BLACK_CROW: 1.0}]
	var pool_want := [life_want[0],
		{9400100: 4.0, 9400101: 3.0, 9400102: 3.0, 9400110: 4.0, 9400111: 4.0}, {9400013: 15.0}]
	for i in MAPS.size():
		var img := lib.img(DataRepo.map_img_path(MAPS[i]))
		if img == null:
			skip("map img not imported: %d" % MAPS[i])
			lib.free()
			return
		assert_eq(StagePools.resolve({"pool_from_life": true}, img.root), life_want[i], "map %d v83 life counts" % (i + 1))
		if i > 0:
			assert_eq(StagePools.resolve(stage.maps[i], img.root), pool_want[i], "map %d pool" % (i + 1))
		for id: int in pool_want[i]:
			assert_true(lib.img("Mob.wz/%07d.img" % id) != null, "mob %d is imported" % id)
	lib.free()


func test_the_male_bosss_summons_come_from_its_skill_table_and_are_all_in_the_pool() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var table := lib.img("Skill.wz/MobSkill.img")
	var boss := lib.img("Mob.wz/%07d.img" % MALE_BOSS)
	if table == null or boss == null:
		skip("the cache has no MobSkill.img or the Male Boss")
		lib.free()
		return
	assert_eq(Array(StageRoster.boss_extra_ids(boss.root, table.root)), SUMMONS, "Extra A/B/C and Leader A/B")
	var map_img := lib.img(DataRepo.map_img_path(MAPS[1]))
	if map_img == null:
		skip("map img not imported: %d" % MAPS[1])
		lib.free()
		return
	var pooled := StagePools.resolve(stage.maps[1], map_img.root)
	for id: int in SUMMONS:
		assert_true(pooled.has(id), "summon %d is in map 2's pool" % id)
		assert_false(StageRoster.ABSENT_IN_V83.has(id), "v83 holds summon %d" % id)
		assert_true(lib.img("Mob.wz/%07d.img" % id) != null, "summon %d is imported" % id)
	lib.free()


func test_each_boss_skill_resolves_to_a_supported_id() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var table := lib.img("Skill.wz/MobSkill.img")
	if table == null:
		skip("the cache has no Skill.wz/MobSkill.img")
		lib.free()
		return
	var kit_sizes := [19, 0, 0]
	for i in BOSSES.size():
		var id: int = BOSSES[i]
		var img := lib.img("Mob.wz/%07d.img" % id)
		if img == null:
			skip("boss %d is not imported" % id)
			lib.free()
			return
		var info: Dictionary = img.root.info
		assert_eq(float(info.get("boss", 0)), 1.0, "%d boss flag" % id)
		var listed: Array = []
		for entry: Dictionary in info.get("skill", {}).values():
			var skill := int(entry.skill)
			listed.append(skill)
			assert_true(skill in MobSkillRunner.SUPPORTED, "boss %d lists MobSkill %d: supported" % [id, skill])
			assert_true(table.root.has(str(skill)), "MobSkill.img has %d" % skill)
			assert_false(table.root[str(skill)].level.get(str(int(entry.level)), {}).is_empty(),
				"boss %d skill %d level %d is in MobSkill.img" % [id, skill, int(entry.level)])
		assert_eq(listed.size(), kit_sizes[i], "boss %d's v83 kit size" % id)
		for skill in listed:
			assert_eq(skill, 200, "the Male Boss casts only Summon 200 (no Banish 129 anywhere)")
		for attack: String in ATTACKS[i]:
			assert_true(img.root.has(attack), "%d has %s" % [id, attack])
			assert_eq(int(img.root[attack].info.type), 0, "%d %s is a type 0 attack" % [id, attack])
	lib.free()
