extends TestCase
## The Leafre region (spec #449 C8, ticket #470, progression step 13; tier C rules in docs/GAME_DESIGN.md "Leafre (C8)
## constants"): `stages/leafre.json`, its manifest fragment and `mobs.json` entries, Sleepywood's curve numbers, the level
## scale and the three bosses. Parts that read canonical data (pools from the maps' life lists, the bosses' skills) are
## cache-backed and SKIP without the asset cache.

const KEY := "leafre"
const MAPS := [240020400, 240030200, 240050300]
const BOSSES := [8180000, 8180001, 8220003]
## Leviathan's MobSkill 200 summons (levels 89, 90, 91): Red, Blue and Dark Wyvern.
const WYVERNS := [8150300, 8150301, 8150302]
## Ordinary mobs by map: Blue Kentaurus (Lv88), Rexton (95), Green Cornian (100), Skelegon (110), Skelosaurus (113).
const POOL_MOBS := [8140103, 8140702, 8150200, 8190003, 8190004]
## The Cave of Light's own life list: hideName instance copies of the Skelegons with a third of the EXP (1500 against 4500 and
## 4750); the spec's rule excludes them, so map 3 has an explicit pool of the real mobs instead.
const CAVE_COPIES := [9300076, 9300077]
## The Etc drops used as EXP pickups, by mob.
const EXP_ITEMS := {8140103: 4000233, 8140702: 4000264, 8150200: 4000266, 8150300: 4000268, 8150301: 4000269,
	8150302: 4000270, 8180000: 4000235, 8180001: 4000243, 8220003: 4000268, 8190003: 4000274, 8190004: 4000273}
## The attack stances each boss schedules.
const ATTACKS := [["attack1", "attack2", "attack3"], ["attack1", "attack2", "attack3"], ["attack1", "attack2"]]
## MobSkill ids per boss in the v83 data (sorted): all supported (Leviathan's 132 and 122 are B3's, 200 is the summons).
const SKILLS := [[], [], [122, 132, 200, 200, 200]]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_is_in_the_progression_with_the_leafre_fields() -> void:
	var progression: Array = data.stages.progression
	assert_true(progression.has(KEY), "listed in the progression")
	assert_true(progression.find(KEY) > progression.find("el_nath"), "after El Nath; step 13 once the regions between sit in")
	assert_eq(String(stage.get("region", "")), "Leafre")
	assert_eq(String(stage.get("continent", "")), "Ossyria", "String.wz group ossyria")
	assert_eq(stage.get("drop_band"), [80.0, 90.0], "#447's drop band")
	assert_true(String(stage.get("note", "")).contains("Leviathan"), "the note names the bosses")
	assert_eq(stage.get("original_life"), {"8140103": 22.0}, "map 1's own spawn list")
	assert_eq(DataRepo.stage_label_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray())


func test_three_maps_with_pool_rules_and_an_explicit_cave_pool() -> void:
	assert_eq(stage.get("map_seconds"), 300)
	var maps: Array = stage.get("maps", [])
	assert_eq(maps.size(), 3)
	for i in maps.size():
		assert_eq(int(maps[i].map_id), MAPS[i], "map %d" % (i + 1))
		assert_false(maps[i].has("opening_ramp"), "map %d: level_scale replaces the opening ramp" % (i + 1))
		assert_false(maps[i].has("exclude"), "map %d lists no pool ids to exclude" % (i + 1))
	assert_eq(maps[0].pool, "curve", "map 1 is a hand-written curve pool")
	assert_true(bool(maps[1].get("pool_from_life", false)), "map 2 takes its life list")
	assert_false(maps[2].has("pool_from_life"), "map 3 does not take the cave's instance copies")
	assert_eq(maps[2].pool, {"8190003": 11.0, "8190004": 6.0}, "Skelegon and Skelosaurus, as Nest of a Dead Dragon spawns them")
	assert_true(String(stage.get("_maps", "")).contains("hideName"), "the map note says why the life list is not used")
	assert_true(String(stage.get("_maps", "")).contains("1530"), "the map note records the rejected native strips")


func test_map_one_keyframe_pools_are_blue_kentaurus_alone() -> void:
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		assert_eq(kf.pool, {"8140103": 1.0}, "Blue Kentaurus, the field's whole roster")
	assert_eq(pooled, 2)
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


func test_level_scale_is_present_valid_and_twenty_four_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level) - float(kfs[i].exp_level), 24.0, 0.011,
			"step 13 is 24 levels above Sleepywood's pace (3 per step after step 5)")
		assert_true(float(kfs[i].level) < 131.0, "below the level where the reference curves go flat")
	assert_true(String(stage.get("_level_scale", "")).contains("Tier C"), "a _tier note")


func test_bosses_are_scheduled_with_tier_notes_and_enabled_kits() -> void:
	var bosses := DataRepo.stage_bosses(stage)
	assert_eq(bosses.size(), 3)
	for i in bosses.size():
		var boss: Dictionary = bosses[i]
		assert_eq(int(boss.mob_id), BOSSES[i], "map %d boss" % (i + 1))
		assert_eq(int(boss.map_time), 300, "a boss 300 s after each entry")
		assert_eq(boss.get("attacks", []), ATTACKS[i], "%d: its own WZ attacks" % BOSSES[i])
		assert_false(boss.has("final_form"), "no final form in Leafre")
		assert_eq(int(boss.attack_interval), 8)
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])
	# The draft tool's numbers (--step=13 --stage=leafre), pinned so a retune is a visible change.
	assert_eq([float(bosses[0].hp_mult), float(bosses[1].hp_mult), float(bosses[2].hp_mult)], [0.828, 0.186, 0.115])
	assert_eq([float(bosses[0].dmg_mult), float(bosses[1].dmg_mult), float(bosses[2].dmg_mult)], [1.019, 0.729, 1.555])
	assert_eq([float(bosses[0].attack_dmg_mult), float(bosses[1].attack_dmg_mult), float(bosses[2].attack_dmg_mult)],
		[0.661, 0.698, 1.815])


func test_leviathans_status_levels_are_the_b3_ones() -> void:
	# 132 level 2 spells its interval `inteval`: the cast reads it through MobSkillRunner.interval_of.
	assert_eq(MobSkillRunner.interval_of({"inteval": 60.0}), 60.0)
	for skill: int in [122, 132, 200]:
		assert_true(skill in MobSkillRunner.SUPPORTED, "MobSkill %d is supported" % skill)


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_leafre.json")
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
		assert_true(EXP_ITEMS.has(id), "stage mob %d is a known Leafre mob" % id)
	var ranges := {8140103: [578, 866], 8140702: [672, 1008], 8150200: [739, 1109], 8190003: [874, 1310], 8190004: [914, 1370]}
	for id: int in ranges:
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_eq([int(mesos[0]), int(mesos[1])], ranges[id], "mob %d range" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	for id: int in BOSSES + WYVERNS:
		assert_false(data.mobs.mobs[str(id)].has("mesos"), "boss or summon %d uses the level fallback" % id)
		assert_false(data.mobs.mobs[str(id)].has("boss_ui"), "%d: its MobGage icon and hpTag are canonical" % id)
		assert_false(data.mobs.mobs[str(id)].has("banish_message"), "%d casts no Banish" % id)
	for id: int in CAVE_COPIES:
		assert_false(data.mobs.mobs.has(str(id)), "the instance copy %d is not a Leafre mob" % id)
		assert_false(fragment.mobs.has(float(id)), "the fragment does not import the instance copy %d" % id)
	var last := -1
	for key: String in data.mobs.mobs.keys():
		if EXP_ITEMS.has(int(key)):
			assert_true(int(key) > last, "%s inserted in id order" % key)
			last = int(key)


func test_pools_resolve_and_the_cave_uses_real_monsters() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var life_want := [{8140103: 22.0}, {8140702: 10.0, 8150200: 6.0}, {9300077: 6.0, 9300076: 15.0}]
	var pool_want := [{8140103: 22.0}, {8140702: 10.0, 8150200: 6.0}, {8190003: 11.0, 8190004: 6.0}]
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
	# The real skeletons are Lv105-115 and pay far more EXP than the cave's instance copies (the reason for the explicit pool).
	for id: int in [8190003, 8190004]:
		var info: Dictionary = lib.img("Mob.wz/%07d.img" % id).root.info
		assert_between(float(info.level), 105.0, 115.0, "%d is a Lv105-115 mob" % id)
		assert_true(float(info.exp) >= 4500.0, "%d pays its canonical EXP" % id)
	for id: int in CAVE_COPIES:
		var copy := lib.img("Mob.wz/%07d.img" % id)
		if copy == null:
			continue # imported only as the map's life, when the manifest still does so
		var info: Dictionary = copy.root.info
		assert_eq(float(info.exp), 1500.0, "the instance copy %d pays a third of the real EXP" % id)
		assert_eq(float(info.get("hideName", 0)), 1.0, "%d is a hideName instance mob" % id)
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
		assert_eq(float(info.get("boss", 0)), 1.0, "%d boss flag" % id)
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
			assert_eq(int(img.root[attack].info.get("magic", 0)), 1, "%d %s is a magic attack (matched on MAD)" % [id, attack])
	# Leviathan's three Summon levels name the Wyverns, all present in v83 (no ABSENT_IN_V83 entry is needed).
	var extras := StageRoster.boss_extra_ids(lib.img("Mob.wz/8220003.img").root, table.root)
	assert_eq(Array(extras), WYVERNS, "Leviathan summons the Red, Blue and Dark Wyvern")
	for extra in extras:
		assert_true(lib.img("Mob.wz/%07d.img" % extra) != null, "Mob.wz holds the summon %d" % extra)
		assert_false(extra in StageRoster.ABSENT_IN_V83, "%d is not on the absent list" % extra)
	# Manon and Griffey cast nothing, so nothing is loaded for them.
	for id: int in [8180000, 8180001]:
		assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/%d.img" % id).root, table.root), PackedInt32Array(), "%d summons nothing" % id)
	lib.free()
