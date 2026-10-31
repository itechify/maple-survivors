extends TestCase
## The Phantom Forest region (spec #449 C9, ticket #471, progression step 14; tier C rules in docs/GAME_DESIGN.md
## "Phantom Forest (C9) constants"): `stages/phantom_forest.json`, its manifest fragment and `mobs.json` entries,
## Sleepywood's curve numbers, the level scale and the three bosses. Parts that read canonical data (the maps' life lists,
## the bosses' skills and sounds) are cache-backed and SKIP without the asset cache.

const CAL := preload("res://tests/calibrated_levels.gd")
const KEY := "phantom_forest"
const MAPS := [610010005, 610020014, 610010103]
const BOSSES := [9400549, 9400594, 9400575]
## The timed or filler natives no pool may name: Phantom Tree (mobTime 1200 s, Lv50, immobile), Leprechaun (Lv45, a stand/die
## decoration), Jr. Wraith (Lv35) and the two native bosses (Horseman mobTime 21600 s, Bigfoot 43200 s).
const PHANTOM_TREE := 9400588
const LEPRECHAUN := 9400584
const JR_WRAITH := 3230101
const EXCLUDED := [PHANTOM_TREE, LEPRECHAUN, JR_WRAITH, 9400549, 9400575, 9400576, 9400577, 9400581]
## The pooled ordinary mobs: Firebrand's flying revive form (Lv90), Nightshadow (Lv100) and Elderwraith (Lv95, flies). Each
## pays within 0.7-1.3 of the level curve's EXP at its own level (the EXP gate, #471 review).
const POOL_MOBS := [9400578, 9400579, 9400580]
## The field natives left out of every pool because their canonical EXP is far off the curve: Windraider (Lv70, 2.9x),
## Stormbreaker (Lv80, 1.9x) and the ground Firebrand (Lv90, 0.48x).
const OFF_CURVE := [9400576, 9400577, 9400581]
## The Etc items used as EXP pickups, by mob.
const EXP_ITEMS := {9400581: 4032006, 9400577: 4032008, 9400578: 4032008, 9400580: 4032010, 9400579: 4032009, 9400549: 4031903, 9400594: 4032012, 9400575: 4032013}
## The attack stances each boss schedules.
const ATTACKS := [["attack1", "attack2"], ["attack1", "attack2"], ["attack1"]]
## MobSkill ids per boss in the v83 data (sorted): Master Guardian's Seal 120 is the one permanent skip.
const SKILLS := [[], [120], []]
const KNOWN_SKIPPED_SKILLS := [120]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_follows_leafre_in_the_progression() -> void:
	var progression: Array = data.stages.progression
	assert_true(progression.has(KEY), "listed in the progression")
	assert_true(progression.find(KEY) > progression.find("leafre"), "after Leafre (step 13)")
	assert_eq(String(stage.get("region", "")), "Phantom Forest")
	assert_eq(String(stage.get("continent", "")), "Masteria", "String.wz group MasteriaGL")
	assert_eq(stage.get("drop_band"), [90.0, 100.0], "#447's drop band")
	assert_true(String(stage.get("note", "")).contains("Horseman"), "the note names the bosses")
	assert_eq(stage.get("original_life"), {"9400581": 5.0, "9400577": 3.0, "9400580": 2.0}, "map 1's ordinary spawn list")
	assert_eq(DataRepo.stage_label_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray())


func test_three_maps_with_pool_rules_and_no_native_timed_mob() -> void:
	assert_eq(stage.get("map_seconds"), 300)
	var maps: Array = stage.get("maps", [])
	assert_eq(maps.size(), 3)
	for i in maps.size():
		assert_eq(int(maps[i].map_id), MAPS[i], "map %d" % (i + 1))
		assert_false(maps[i].has("opening_ramp"), "map %d: level_scale replaces the opening ramp" % (i + 1))
	assert_eq(maps[0].pool, "curve", "map 1 is a hand-written curve pool")
	assert_false(maps[0].has("exclude"), "map 1 lists no pool ids to exclude")
	for i in [1, 2]:
		assert_false(maps[i].has("pool_from_life"), "map %d: its life list is off the EXP curve or filler: a hand-written pool" % (i + 1))
		assert_true(maps[i].pool is Dictionary, "map %d has an explicit pool" % (i + 1))
	var seen := {}
	for kf: Dictionary in stage.keyframes:
		for id: Variant in kf.get("pool", {}):
			seen[int(id)] = true
	for id: Variant in maps[2].pool:
		seen[int(id)] = true
	for id: int in seen:
		assert_has(POOL_MOBS, id, "pool mob %d is one of the forest's ordinary mobs" % id)
		assert_false(id in EXCLUDED, "pool mob %d is not a timed native, filler or boss" % id)
	assert_eq(StagePools.resolve(maps[1], {}), {9400578: 4.0, 9400579: 3.0, 9400580: 2.0}, "map 2's pool")
	assert_eq(StagePools.resolve(maps[2], {}), {9400579: 3.0, 9400580: 2.0, 9400578: 3.0}, "map 3's pool")
	for boss_id: int in BOSSES:
		assert_false(seen.has(boss_id), "boss %d is never in an ordinary pool" % boss_id)
	assert_true(String(stage.get("_maps", "")).contains("Twisted Paths"), "the map note records the pool decisions")


func test_map_one_keyframe_pools_are_the_in_band_forest_mobs() -> void:
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		assert_eq(kf.pool.keys(), ["9400579", "9400578", "9400580"], "Nightshadow, the flying Firebrand form and Elderwraith")
	assert_eq(pooled, 2)
	assert_eq(stage.keyframes[0].pool, {"9400579": 4.0, "9400578": 3.0, "9400580": 2.0})
	assert_eq(stage.keyframes[1].pool, {"9400579": 3.0, "9400578": 3.0, "9400580": 2.0})
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


func test_level_scale_is_present_valid_and_twenty_seven_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level), CAL.level_at(float(kfs[i].exp_level), float(kfs[i].t), 14), 0.011,
			"step 14: the calibrated level (C13): 1 at 0:00 rising to Sleepywood's pace + CAL.ABOVE at 10:00, keyframe %d" % i)
	assert_true(String(stage.get("_level_scale", "")).contains("Tier C"), "a _tier note")


func test_bosses_are_scheduled_with_tier_notes_and_enabled_kits() -> void:
	var bosses := DataRepo.stage_bosses(stage)
	assert_eq(bosses.size(), 3)
	for i in bosses.size():
		var boss: Dictionary = bosses[i]
		assert_eq(int(boss.mob_id), BOSSES[i], "map %d boss" % (i + 1))
		assert_eq(int(boss.map_time), 300, "a boss 300 s after each entry")
		assert_eq(boss.get("attacks", []), ATTACKS[i], "%d: its own WZ attacks" % BOSSES[i])
		assert_false(boss.has("final_form"), "no final form in the Phantom Forest")
		assert_eq(int(boss.attack_interval), 8)
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_false(boss.has("skill_intervals"), "%d has no Banish, so no per-skill interval" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])
	assert_false(120 in MobSkillRunner.SUPPORTED, "Seal 120 is permanently skipped: Master Guardian's one skill casts nothing")


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_phantom_forest.json")
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
		assert_true(EXP_ITEMS.has(id), "stage mob %d is a known Phantom Forest mob" % id)
		assert_false(id in OFF_CURVE, "stage mob %d is not an off-curve native" % id)
	assert_false(data.mobs.mobs.has("9400576"), "Windraider is in no pool and not in original_life: no entry")
	var ranges := {9400581: [398, 596], 9400577: [458, 688], 9400578: [458, 688], 9400580: [490, 734],
		9400579: [520, 780]}
	for id: int in ranges:
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_eq([int(mesos[0]), int(mesos[1])], ranges[id], "mob %d range" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	for id: int in BOSSES:
		assert_false(data.mobs.mobs[str(id)].has("mesos"), "boss %d uses the level fallback" % id)
	assert_eq(data.mobs.mobs["9400549"].boss_ui.icon_id, 6220001, "the Horseman borrows Zeno's icon: v83 has none for it")
	assert_eq(data.mobs.mobs["9400594"].boss_ui.icon_id, 6220001, "Master Guardian borrows Zeno's icon: v83 has none for it")
	assert_false(data.mobs.mobs["9400575"].has("boss_ui"), "Bigfoot's MobGage icon is canonical")
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
	var life_want := [
		{9400581: 5.0, 9400577: 3.0, LEPRECHAUN: 6.0, PHANTOM_TREE: 3.0, 9400580: 2.0, 9400575: 1.0, 9400549: 1.0},
		{9400577: 4.0, 9400579: 3.0, 9400576: 4.0},
		{JR_WRAITH: 10.0, PHANTOM_TREE: 4.0, 9400575: 1.0}]
	for i in MAPS.size():
		var img := lib.img(DataRepo.map_img_path(MAPS[i]))
		if img == null:
			skip("map img not imported: %d" % MAPS[i])
			lib.free()
			return
		assert_eq(StagePools.resolve({"pool_from_life": true}, img.root), life_want[i], "map %d v83 life counts" % (i + 1))
		for id: Variant in stage.maps[i].get("pool", {}) if stage.maps[i].get("pool") is Dictionary else {}:
			assert_has(POOL_MOBS, int(id), "map %d pool mob %d" % [i + 1, int(id)])
		var rows: Dictionary = img.root.life
		for row: Dictionary in rows.values():
			assert_false(row.has("hideName"), "map %d holds no hideName instance copies" % (i + 1))
			if int(row.get("id", 0)) in [PHANTOM_TREE, 9400575]:
				assert_true(int(row.get("mobTime", 0)) > 0, "natives %s are timed spawns" % row.id)
			if int(row.get("id", 0)) == 9400549:
				assert_eq(int(row.mobTime), 21600, "the Horseman is a six-hour spawn")
	for id: int in POOL_MOBS + OFF_CURVE:
		assert_true(lib.img("Mob.wz/%07d.img" % id) != null, "mob %d is imported" % id)
	# Firebrand's revive form is the ordinary flying mob 9400578; Elderwraith has no ground stance.
	var firebrand := lib.img("Mob.wz/9400577.img")
	assert_eq(Array(StageRoster.list_ids(firebrand.root.info.revive)), [9400578], "Firebrand revives into its flying form")
	assert_true(lib.img("Mob.wz/9400578.img").root.has("fly"), "the revive form flies")
	assert_true(lib.img("Mob.wz/9400580.img").root.has("fly"), "Elderwraith flies")
	assert_false(lib.img("Mob.wz/9400580.img").root.has("move"), "Elderwraith has no ground stance")
	lib.free()


## The EXP gate (#471 review): a kill's EXP is rescaled by the curve at the mob's own level, so a pooled mob whose canonical
## EXP is far off level_curve.json's levels the character too fast or too slow.
func test_every_pooled_mob_pays_within_0_7_and_1_3_of_the_level_curve() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var curve: Array = data.level_curve.exp
	var ratios := {}
	for id: int in POOL_MOBS + OFF_CURVE:
		var img := lib.img("Mob.wz/%07d.img" % id)
		if img == null:
			skip("mob %d is not imported" % id)
			lib.free()
			return
		var info: Dictionary = img.root.info
		ratios[id] = float(info.exp) / float(curve[int(info.level) - 1])
	for id: int in POOL_MOBS:
		assert_between(float(ratios[id]), 0.7, 1.3, "pooled mob %d EXP / curve" % id)
	for id: int in OFF_CURVE:
		assert_true(float(ratios[id]) < 0.7 or float(ratios[id]) > 1.3, "native %d is off the curve (%.2f): why it is in no pool" % [id, ratios[id]])
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
	for i in BOSSES.size():
		var id: int = BOSSES[i]
		var img := lib.img("Mob.wz/%07d.img" % id)
		if img == null:
			skip("boss %d is not imported" % id)
			lib.free()
			return
		var info: Dictionary = img.root.info
		assert_eq(float(info.get("boss", 0)), 1.0, "%d is a v83 boss" % id)
		var listed: Array = []
		for entry: Dictionary in info.get("skill", {}).values():
			var skill := int(entry.skill)
			listed.append(skill)
			assert_true(skill in MobSkillRunner.SUPPORTED or skill in KNOWN_SKIPPED_SKILLS,
				"boss %d lists MobSkill %d: supported or a known skip" % [id, skill])
			assert_true(table.root.has(str(skill)), "MobSkill.img has %d" % skill)
		listed.sort()
		assert_eq(listed, SKILLS[i], "boss %d's v83 kit" % id)
		for attack: String in ATTACKS[i]:
			assert_true(img.root.has(attack), "%d has %s" % [id, attack])
			assert_eq(int(img.root[attack].info.type), 0, "%d %s is a type 0 contact attack" % [id, attack])
		assert_eq(StageRoster.boss_extra_ids(img.root, table.root), PackedInt32Array(), "boss %d summons and revives nothing" % id)
	# Master Guardian's attack1 is the flagged magic one (MADamage 500); attack2 is physical.
	var guardian := lib.img("Mob.wz/9400594.img")
	assert_eq(int(guardian.root.attack1.info.get("magic", 0)), 1, "Master Guardian attack1 is flagged magic")
	assert_false(guardian.root.attack2.info.has("magic"), "attack2 is physical")
	lib.free()


func test_sounds_v83_lacks_are_absent_not_missing() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	if lib.find("Sound.wz/Mob.img/9400594") == null:
		skip("Master Guardian's sounds are not imported")
		lib.free()
		return
	assert_true(lib.find("Sound.wz/Mob.img/9400594/Damage") == null, "tier A: v83 gives Master Guardian no Damage sound")
	assert_true(lib.find("Sound.wz/Mob.img/9400580/Attack1") == null, "tier A: v83 gives Elderwraith no Attack1 sound (it never attacks)")
	assert_true(lib.find("Sound.wz/Mob.img/9400580/Damage") != null, "Elderwraith keeps its Damage sound")
	lib.free()
