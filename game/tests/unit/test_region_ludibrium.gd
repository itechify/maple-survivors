extends TestCase
## The Ludibrium region (spec #449 C1, ticket #463, progression step 6; tier C rules in docs/GAME_DESIGN.md "Ludibrium (C1)
## constants"): `stages/ludibrium.json`, its manifest fragment and `mobs.json` entries, Sleepywood's curve numbers, the
## level scale and the three bosses. Parts that read canonical data (pools from the maps' life lists, the bosses' skills)
## are cache-backed and SKIP without the asset cache.

const CAL := preload("res://tests/calibrated_levels.gd")
const KEY := "ludibrium"
const MAPS := [220011000, 220030400, 220030000]
const BOSSES := [4130103, 9300012, 5220003]
## Map 1's own roster (Roloduck, Panda Teddy) and the Etc drops used as EXP pickups, by mob.
const EXP_ITEMS := {3210204: 4000109, 3210203: 4000108, 4230111: 4000111, 4230112: 4000112, 4130103: 4000124,
	9300012: 4001023, 5220003: 4000113, 9300015: 4000113, 9300016: 4000113, 9300017: 4000113}
## MobSkill ids this region's bosses list that the runner skips for good (Alishar's Seal).
const KNOWN_SKIPPED_SKILLS := [120]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_is_step_six_of_the_progression() -> void:
	assert_eq(data.stages.progression.find(KEY), 5, "position 6, after Sleepywood")
	assert_eq(String(stage.get("region", "")), "Ludibrium")
	assert_eq(String(stage.get("continent", "")), "Ossyria", "String.wz group ossyria")
	assert_eq(stage.get("drop_band"), [35.0, 45.0], "#447's drop band")
	assert_false(String(stage.get("note", "")).is_empty(), "a one-line note")
	assert_eq(stage.get("original_life"), {"3210204": 22.0, "3210203": 19.0}, "map 1's own spawn list")
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


func test_map_one_keyframe_pools_use_only_its_own_roster() -> void:
	var roster := ["3210204", "3210203"]
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		for id: String in kf.pool:
			assert_has(roster, id, "pool mob %s is on Sky Terrace" % id)
	assert_eq(pooled, 2)
	assert_eq(stage.keyframes[0].pool, {"3210204": 1.0}, "Roloduck opens alone")


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


func test_level_scale_is_present_valid_and_three_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level), CAL.level_at(float(kfs[i].exp_level), float(kfs[i].t), 6), 0.011,
			"step 6: the calibrated level (C13): 1 at 0:00 rising to Sleepywood's pace + CAL.ABOVE at 10:00, keyframe %d" % i)
	assert_true(String(stage.get("_level_scale", "")).contains("Tier C"), "a _tier note")


func test_bosses_are_scheduled_with_tier_notes_and_enabled_kits() -> void:
	var bosses := DataRepo.stage_bosses(stage)
	assert_eq(bosses.size(), 3)
	for i in bosses.size():
		var boss: Dictionary = bosses[i]
		assert_eq(int(boss.mob_id), BOSSES[i], "map %d boss" % (i + 1))
		assert_eq(int(boss.map_time), 300, "a boss 300 s after each entry")
		assert_eq(boss.attacks, ["attack1"], "the boss's own WZ attack")
		assert_eq(int(boss.attack_interval), 8)
		assert_false(boss.has("final_form"), "no final form in Ludibrium")
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_ludibrium.json")
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
		assert_true(EXP_ITEMS.has(id), "stage mob %d is a known Ludibrium mob" % id)
	for id: int in [3210204, 3210203, 4230111, 4230112]:
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_true(float(mesos[0]) > 0.0 and float(mesos[0]) < float(mesos[1]), "mob %d range is ordered" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	assert_eq(data.mobs.mobs["4130103"].boss_ui.icon_id, 6220001, "Rombot borrows an icon: v83 has none for it")


func test_pools_resolve_to_the_maps_own_life_lists() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var want := [{3210204: 22.0, 3210203: 19.0}, {4230111: 28.0, 3210203: 8.0}, {4230112: 29.0}]
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
	for id: int in BOSSES:
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
		assert_true(img.root.has("attack1"), "%d has attack1" % id)
		assert_true(int(img.root.attack1.info.type) in [0, 1, 2], "%d attack1 is a supported attack type" % id)
	assert_true(listed.has(121) and listed.has(123) and listed.has(141) and listed.has(120), "Alishar's and Timer's kits are read")
	assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/9300012.img").root, table.root), PackedInt32Array([9300015, 9300016, 9300017]),
		"Alishar's MobSkill 200 summons the Cronos")
	assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/5220003.img").root, table.root), PackedInt32Array(), "Timer summons nothing")
	assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/4130103.img").root, table.root), PackedInt32Array(), "Rombot summons nothing")
	lib.free()


func test_zone_one_has_conveyor_footholds() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var img := lib.img(DataRepo.map_img_path(220030000))
	if img == null:
		skip("map 220030000 is not imported")
		lib.free()
		return
	var forces := 0
	for layer: Variant in img.root.get("foothold", {}).values():
		for group: Variant in layer.values():
			for fh: Variant in group.values():
				if fh is Dictionary and float(fh.get("force", 0.0)) != 0.0:
					forces += 1
	assert_eq(forces, 4, "Zone 1's four conveyor footholds use the existing force support")
	lib.free()


func test_alishar_has_no_skill_sound_in_v83() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	if lib.find("Sound.wz/Mob.img/9300012") == null:
		skip("Alishar's sounds are not imported")
		lib.free()
		return
	assert_true(lib.find("Sound.wz/Mob.img/9300012/Skill1") == null, "tier A: v83 gives Alishar no Skill1 sound")
	assert_true(lib.find("Sound.wz/Mob.img/5220003/Skill1") != null, "Timer's Skill1 sound is imported")
	lib.free()
