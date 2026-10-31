extends TestCase
## The Korean Folk Town region (spec #449 C3, ticket #465, progression step 8; tier C rules in docs/GAME_DESIGN.md "Korean
## Folk Town (C3) constants"): `stages/korean_folk_town.json`, its manifest fragment and `mobs.json` entries, Sleepywood's
## curve numbers, the level scale and the three bosses. Parts that read canonical data (pools from the maps' life lists, the
## bosses' skills) are cache-backed and SKIP without the asset cache.

const CAL := preload("res://tests/calibrated_levels.gd")
const KEY := "korean_folk_town"
const MAPS := [222010000, 222010200, 222010300]
const BOSSES := [6090003, 7130401, 7220001]
## The Etc drops used as EXP pickups, by mob.
const EXP_ITEMS := {4230300: 4000169, 5100003: 4000170, 5100005: 4000171, 5100004: 4000172, 6090003: 4000416,
	7130401: 4010004, 7220001: 4000172}
## The attack stances each boss schedules (Scholar Ghost has none: contact damage and Banish only).
const ATTACKS := [[], ["attack1"], ["attack1"]]
## MobSkill ids per boss in the v83 data: all must be supported (none is skipped in this region).
const SKILLS := [[129], [], [114, 121, 122, 123]]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_is_step_eight_of_the_progression() -> void:
	var progression: Array = data.stages.progression
	assert_true(progression.has(KEY), "listed in the progression")
	assert_true(progression.find(KEY) > progression.find("ludibrium"), "after Ludibrium; step 8 once Omega Sector (#464) sits between them")
	assert_eq(String(stage.get("region", "")), "Korean Folk Town")
	assert_eq(String(stage.get("continent", "")), "Ossyria", "String.wz group ossyria")
	assert_eq(stage.get("drop_band"), [45.0, 55.0], "#447's drop band")
	assert_false(String(stage.get("note", "")).is_empty(), "a one-line note")
	assert_eq(stage.get("original_life"), {"4230300": 13.0}, "map 1's own spawn list, without the stray stumps")
	assert_eq(DataRepo.stage_label_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray())


func test_three_maps_with_pool_rules_and_the_scholar_ghost_exclusion() -> void:
	assert_eq(stage.get("map_seconds"), 300)
	var maps: Array = stage.get("maps", [])
	assert_eq(maps.size(), 3)
	for i in maps.size():
		assert_eq(int(maps[i].map_id), MAPS[i], "map %d" % (i + 1))
		assert_false(maps[i].has("opening_ramp"), "map %d: level_scale replaces the opening ramp" % (i + 1))
	assert_eq(maps[0].pool, "curve", "map 1 is a hand-written curve pool")
	assert_false(maps[0].has("exclude"), "map 1 lists no pool ids to exclude")
	assert_true(bool(maps[1].get("pool_from_life", false)), "map 2 takes its life list")
	assert_false(maps[1].has("exclude"), "Hogul's timed spawn is an ordinary mob")
	assert_true(bool(maps[2].get("pool_from_life", false)), "map 3 takes its life list")
	assert_eq(maps[2].get("exclude"), [6090003.0], "Fox Ridge drops the timed Scholar Ghost, map 1's boss")


func test_map_one_keyframe_pools_are_moon_bunny_alone() -> void:
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		assert_eq(kf.pool, {"4230300": 1.0}, "Moon Bunny is Entrance to Black Mountain's only monster")
	assert_eq(pooled, 2)


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


func test_level_scale_is_present_valid_and_nine_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level), CAL.level_at(float(kfs[i].exp_level), float(kfs[i].t), 8), 0.011,
			"step 8: the calibrated level (C13): 1 at 0:00 rising to Sleepywood's pace + CAL.ABOVE at 10:00, keyframe %d" % i)
	assert_true(String(stage.get("_level_scale", "")).contains("Tier C"), "a _tier note")


func test_bosses_are_scheduled_with_tier_notes_and_enabled_kits() -> void:
	var bosses := DataRepo.stage_bosses(stage)
	assert_eq(bosses.size(), 3)
	for i in bosses.size():
		var boss: Dictionary = bosses[i]
		assert_eq(int(boss.mob_id), BOSSES[i], "map %d boss" % (i + 1))
		assert_eq(int(boss.map_time), 300, "a boss 300 s after each entry")
		assert_eq(boss.get("attacks", []), ATTACKS[i], "%d: its own WZ attacks" % BOSSES[i])
		assert_false(boss.has("final_form"), "no final form in Korean Folk Town")
		for field: String in ["hp_mult", "dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		if not ATTACKS[i].is_empty():
			assert_eq(int(boss.attack_interval), 8)
			assert_true(float(boss.get("attack_dmg_mult", 0.0)) > 0.0, "%d attack_dmg_mult" % BOSSES[i])
		else:
			assert_false(boss.has("attack_dmg_mult"), "Scholar Ghost has no attack to scale")
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])
	assert_eq(stage.maps[0].boss.skill_intervals, {"129": 15.0}, "Scholar Ghost banishes once per 15 s, as Shade (#256)")


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_korean_folk_town.json")
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
		assert_true(EXP_ITEMS.has(id), "stage mob %d is a known Korean Folk Town mob" % id)
	var ranges := {4230300: [150, 226], 5100003: [200, 300], 5100005: [226, 340], 5100004: [253, 379]}
	for id: int in ranges:
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_eq([int(mesos[0]), int(mesos[1])], ranges[id], "mob %d range" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	for id: int in BOSSES:
		assert_false(data.mobs.mobs[str(id)].has("mesos"), "boss %d uses the level fallback" % id)
	assert_eq(data.mobs.mobs["6090003"].boss_ui.icon_id, 6090000, "Scholar Ghost borrows Riche's icon: v83 has none for it")
	assert_eq(data.mobs.mobs["7130401"].boss_ui.icon_id, 6220001, "Blue King Goblin borrows Zeno's icon: v83 has none for it")
	assert_false(data.mobs.mobs["7220001"].has("boss_ui"), "the Fox's MobGage icon is canonical")
	assert_eq(String(data.mobs.mobs["6090003"].get("banish_message", "")).substr(0, 24), "You have been relocated ", "v83 banMsg")


func test_only_blue_king_goblin_is_scheduled() -> void:
	for key: String in data.stages.progression:
		for boss: Dictionary in DataRepo.stage_bosses(data.stages.stages[key]):
			assert_false(int(boss.mob_id) in [7130400, 7130402], "%s: Yellow and Green King Goblin stay unscheduled" % key)


func test_pools_resolve_to_the_maps_own_life_lists() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var life_want := [{4230300: 13.0}, {5100003: 10.0, 5100005: 3.0}, {5100004: 21.0, 6090003: 1.0}]
	var pool_want := [{4230300: 13.0}, {5100003: 10.0, 5100005: 3.0}, {5100004: 21.0}]
	for i in MAPS.size():
		var img := lib.img(DataRepo.map_img_path(MAPS[i]))
		if img == null:
			skip("map img not imported: %d" % MAPS[i])
			lib.free()
			return
		var life := StagePools.resolve({"pool_from_life": true}, img.root)
		if i == 0:
			# The stray Dark Axe Stump (2130100, three spawn points) is in the life list but not in the hand-written pool.
			assert_eq(life, {2130100: 3.0, 4230300: 13.0}, "map 1 v83 life counts")
		else:
			assert_eq(life, life_want[i], "map %d v83 life counts" % (i + 1))
		if i > 0:
			assert_eq(StagePools.resolve(stage.maps[i], img.root), pool_want[i], "map %d pool" % (i + 1))
		for id: int in pool_want[i]:
			assert_true(lib.img("Mob.wz/%07d.img" % id) != null, "mob %d is imported" % id)
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
	for i in BOSSES.size():
		var id: int = BOSSES[i]
		var img := lib.img("Mob.wz/%07d.img" % id)
		if img == null:
			skip("boss %d is not imported" % id)
			lib.free()
			return
		var info: Dictionary = img.root.info
		assert_true(float(info.get("boss", 0)) == 1.0, "%d is a v83 boss" % id)
		var listed: Array = []
		for entry: Dictionary in info.get("skill", {}).values():
			var skill := int(entry.skill)
			listed.append(skill)
			assert_true(skill in MobSkillRunner.SUPPORTED, "boss %d lists MobSkill %d: supported" % [id, skill])
			assert_true(table.root.has(str(skill)), "MobSkill.img has %d" % skill)
		listed.sort()
		assert_eq(listed, SKILLS[i], "boss %d's v83 kit" % id)
		for attack: String in ATTACKS[i]:
			assert_true(img.root.has(attack), "%d has %s" % [id, attack])
			assert_true(int(img.root[attack].info.type) in [0, 1, 2], "%d %s is a supported attack type" % [id, attack])
		assert_eq(StageRoster.boss_extra_ids(img.root, table.root), PackedInt32Array(), "%d summons nothing" % id)
	assert_false(lib.img("Mob.wz/6090003.img").root.has("attack1"), "Scholar Ghost has no attack stance")
	lib.free()
