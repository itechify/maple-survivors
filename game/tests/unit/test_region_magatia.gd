extends TestCase
## The Magatia region (spec #449 C6, ticket #468, progression step 11; tier C rules in docs/GAME_DESIGN.md "Magatia (C6)
## constants"): `stages/magatia.json`, its manifest fragment and `mobs.json` entries, Sleepywood's curve numbers, the level
## scale and the three bosses. Parts that read canonical data (pools from the maps' life lists, the bosses' skills) are
## cache-backed and SKIP without the asset cache.

const KEY := "magatia"
const MAPS := [260020300, 261020400, 261010101]
const BOSSES := [3220001, 8110300, 8220002]
## Rurumo (Lv63, boss-flagged, mobTime 2400 s) is the timed native boss of Area C-2: never in a pool.
const RURUMO := 6090004
## Ordinary mobs by map: Kiyo (Lv30), Sand Dwarf (32), Roid (54), Neo Huroid (58), Homun (65), Saitie (68).
const POOL_MOBS := [3100101, 3100102, 5110301, 5110302, 6110300, 6110301]
## The Etc drops used as EXP pickups, by mob.
const EXP_ITEMS := {3100102: 4000335, 3100101: 4000334, 5110301: 4000364, 5110302: 4000365, 6110300: 4000354,
	6110301: 4000363, 3220001: 4000329, 8110300: 4000355, 8220002: 4000364}
## The attack stances each boss schedules.
const ATTACKS := [["attack1"], ["attack1", "attack2"], ["attack1"]]
## MobSkill ids per boss in the v83 data (sorted): all supported.
const SKILLS := [[112], [], [101, 103, 111, 114, 140, 200]]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_follows_korean_folk_town_in_the_progression() -> void:
	var progression: Array = data.stages.progression
	assert_true(progression.has(KEY), "listed in the progression")
	assert_true(progression.find(KEY) > progression.find("korean_folk_town"), "after El Nath; step 11 once Mu Lung sits between")
	assert_eq(String(stage.get("region", "")), "Magatia")
	assert_eq(String(stage.get("continent", "")), "Ossyria", "String.wz group ossyria")
	assert_eq(stage.get("drop_band"), [60.0, 70.0], "#447's drop band")
	assert_true(String(stage.get("note", "")).contains("Ariant"), "the note names the desert road from Ariant")
	assert_eq(stage.get("original_life"), {"3100102": 9.0, "3100101": 6.0}, "map 1's own spawn list")
	assert_eq(DataRepo.stage_label_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray())


func test_three_maps_with_pool_rules_and_the_rurumo_exclusion() -> void:
	assert_eq(stage.get("map_seconds"), 300)
	var maps: Array = stage.get("maps", [])
	assert_eq(maps.size(), 3)
	for i in maps.size():
		assert_eq(int(maps[i].map_id), MAPS[i], "map %d" % (i + 1))
		assert_false(maps[i].has("opening_ramp"), "map %d: level_scale replaces the opening ramp" % (i + 1))
	assert_eq(maps[0].pool, "curve", "map 1 is a hand-written curve pool")
	assert_false(maps[0].has("exclude"), "map 1 lists no pool ids to exclude")
	assert_true(bool(maps[1].get("pool_from_life", false)), "map 2 takes its life list")
	assert_eq(maps[1].get("exclude"), [float(RURUMO)], "Area C-2 drops the timed Rurumo")
	assert_true(bool(maps[2].get("pool_from_life", false)), "map 3 takes its life list")
	assert_false(maps[2].has("exclude"), "Unit 201 holds no timed boss")
	var rows := {"0": {"type": "m", "id": str(RURUMO)}, "1": {"type": "m", "id": "5110301"}}
	assert_eq(StagePools.resolve({"pool_from_life": true, "exclude": [RURUMO]}, {"life": rows}), {5110301: 1.0},
		"Rurumo never pools")
	for boss_id: int in BOSSES:
		assert_false(boss_id == RURUMO, "Rurumo is not a scheduled boss")


func test_map_one_keyframe_pools_are_kiyo_and_sand_dwarf() -> void:
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		assert_eq(kf.pool.keys(), ["3100102", "3100101"], "Kiyo and Sand Dwarf, the field's whole roster")
	assert_eq(pooled, 2)
	assert_eq(stage.keyframes[0].pool, {"3100102": 3.0, "3100101": 2.0})
	assert_eq(stage.keyframes[1].pool, {"3100102": 1.0, "3100101": 1.0})
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


func test_level_scale_is_present_valid_and_eighteen_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level) - float(kfs[i].exp_level), 18.0, 0.011,
			"step 11 is 18 levels above Sleepywood's pace (3 per step after step 5)")
	assert_true(String(stage.get("_level_scale", "")).contains("Tier C"), "a _tier note")


func test_bosses_are_scheduled_with_tier_notes_and_enabled_kits() -> void:
	var bosses := DataRepo.stage_bosses(stage)
	assert_eq(bosses.size(), 3)
	for i in bosses.size():
		var boss: Dictionary = bosses[i]
		assert_eq(int(boss.mob_id), BOSSES[i], "map %d boss" % (i + 1))
		assert_eq(int(boss.map_time), 300, "a boss 300 s after each entry")
		assert_eq(boss.get("attacks", []), ATTACKS[i], "%d: its own WZ attacks" % BOSSES[i])
		assert_false(boss.has("final_form"), "no final form in Magatia")
		assert_eq(int(boss.attack_interval), 8)
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_magatia.json")
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
	for id: int in DataRepo.stage_mob_ids(data, KEY):
		assert_true(EXP_ITEMS.has(id) or id == RURUMO, "stage mob %d is a known Magatia mob" % id)
	var ranges := {3100102: [59, 89], 3100101: [66, 100], 5110301: [235, 353], 5110302: [270, 406], 6110300: [326, 490],
		6110301: [332, 498]}
	for id: int in ranges:
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_eq([int(mesos[0]), int(mesos[1])], ranges[id], "mob %d range" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	for id: int in BOSSES:
		assert_false(data.mobs.mobs[str(id)].has("mesos"), "boss %d uses the level fallback" % id)
	assert_eq(data.mobs.mobs["8110300"].boss_ui.icon_id, 6220001, "Homunscullo borrows Zeno's icon: v83 has none for it")
	assert_false(data.mobs.mobs["3220001"].has("boss_ui"), "Deo's MobGage icon is canonical")
	assert_false(data.mobs.mobs["8220002"].has("boss_ui"), "Chimera's MobGage icon is canonical")
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
	var life_want := [{3100102: 9.0, 3100101: 6.0}, {5110301: 14.0, 5110302: 13.0, RURUMO: 1.0}, {6110300: 11.0, 6110301: 5.0}]
	var pool_want := [{3100102: 9.0, 3100101: 6.0}, {5110301: 14.0, 5110302: 13.0}, {6110300: 11.0, 6110301: 5.0}]
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


func test_absent_summons_are_not_stage_mobs() -> void:
	var boss := {"info": {"skill": {"0": {"skill": 200, "level": 1}}}}
	var table := {"200": {"level": {"1": {"0": 9300167, "1": 9300168, "2": 100100, "limit": 15}}}}
	assert_eq(StageRoster.boss_extra_ids(boss, table), PackedInt32Array([100100]), "ids v83 lacks are dropped, others stay")
	assert_eq(StageRoster.list_ids(table["200"].level["1"]), PackedInt32Array([9300167, 9300168, 100100]), "the cast list is unchanged")


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
	for i in BOSSES.size():
		var id: int = BOSSES[i]
		var img := lib.img("Mob.wz/%07d.img" % id)
		if img == null:
			skip("boss %d is not imported" % id)
			lib.free()
			return
		var info: Dictionary = img.root.info
		# Homunscullo is the one unflagged mob: Unit 202's 5400 s spawn, not a v83 boss.
		assert_eq(float(info.get("boss", 0)) == 1.0, id != 8110300, "%d boss flag" % id)
		var listed: Array = []
		for entry: Dictionary in info.get("skill", {}).values():
			var skill := int(entry.skill)
			listed.append(skill)
			assert_true(skill in MobSkillRunner.SUPPORTED, "boss %d lists MobSkill %d: supported" % [id, skill])
			assert_true(table.root.has(str(skill)), "MobSkill.img has %d" % skill)
			assert_false(table.root[str(skill)].level.get(str(int(entry.level)), {}).is_empty(),
				"boss %d skill %d level %d is in MobSkill.img" % [id, skill, int(entry.level)])
		listed.sort()
		assert_eq(listed, SKILLS[i], "boss %d's v83 kit" % id)
		for attack: String in ATTACKS[i]:
			assert_true(img.root.has(attack), "%d has %s" % [id, attack])
			assert_true(int(img.root[attack].info.type) in [0, 1, 2], "%d %s is a supported attack type" % [id, attack])
	# Chimera's Summon (200/88) lists mobs v83 does not hold: it spawns nothing, so nothing is loaded for it.
	var listed_summons := StageRoster.list_ids(table.root["200"].level["88"])
	assert_eq(Array(listed_summons), [9300167, 9300167, 9300167, 9300168, 9300168, 9300168], "Chimera's canonical summon list")
	for extra in listed_summons:
		assert_true(lib.img("Mob.wz/%07d.img" % extra) == null, "v83 has no Mob.wz img for summon %d" % extra)
	assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/8220002.img").root, table.root), PackedInt32Array(),
		"nothing to load for Chimera's absent summons")
	assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/3220001.img").root, table.root), PackedInt32Array(), "Deo summons nothing")
	lib.free()
