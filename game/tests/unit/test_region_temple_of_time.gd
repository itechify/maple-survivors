extends TestCase
## The Temple of Time region (spec #449 C11, ticket #473, progression step 16; tier C rules in docs/GAME_DESIGN.md "Temple of
## Time (C11) constants"): `stages/temple_of_time.json`, its manifest fragment and `mobs.json` entries, Sleepywood's curve
## numbers, the level scale and the three bosses. Parts that read canonical data (pools from the maps' life lists, the bosses'
## skills, the pool mobs' EXP against the level curve) are cache-backed and SKIP without the asset cache.

const KEY := "temple_of_time"
const MAPS := [270010500, 270020500, 270030500]
const BOSSES := [8220004, 8220005, 8220006]
## Ordinary mobs by map: Chief Memory Guardian (Lv101), Chief Qualm Guardian (Lv116), Chief Oblivion Guardian (Lv131).
const POOL_MOBS := [8200004, 8200008, 8200012]
const POOL_LEVELS := {8200004: 101, 8200008: 116, 8200012: 131}
## The Lv80 filler of the first two lanes, never in a pool.
const EYE_OF_TIME := 8200000
## The Etc drops used as EXP pickups, by mob.
const EXP_ITEMS := {8200004: 4000448, 8200008: 4000453, 8200012: 4000458, 8220004: 4000460, 8220005: 4000461, 8220006: 4000462}
## The attack stances each boss schedules.
const ATTACKS := [["attack1", "attack2"], ["attack1", "attack2"], ["attack1", "attack2"]]
## Their WZ attack types: Dodo's ball (2) and bolt (0), Lilynouch's two plain attacks, Lyka's area warning (4, B5) and bolt.
const ATTACK_TYPES := [[2, 0], [0, 0], [4, 0]]
## MobSkill ids per boss in the v83 data (sorted): all supported (Dodo's 102 is B2, 129 Banish, Lilynouch's 145 B6, Lyka's 128 B3).
const SKILLS := [[102, 129], [114, 145], [100, 114, 128]]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_is_the_last_of_the_progression_with_the_temple_fields() -> void:
	var progression: Array = data.stages.progression
	assert_true(progression.has(KEY), "listed in the progression")
	assert_eq(progression[-1], KEY, "the last region of the progression")
	assert_true(progression.find(KEY) > progression.find("leafre"), "after Leafre; step 16 once the regions between sit in")
	assert_eq(String(stage.get("region", "")), "Temple of Time")
	assert_eq(String(stage.get("continent", "")), "Ossyria", "String.wz group ossyria")
	assert_eq(stage.get("drop_band"), [108.0, 120.0], "C12 widened step 16's band from [110, 120] (GAME_DESIGN 8.3)")
	assert_true(String(stage.get("note", "")).contains("Lyka"), "the note names the bosses")
	assert_eq(stage.get("original_life"), {"8200004": 14.0}, "map 1's own spawn list without Dodo and the Eye of Time")
	assert_eq(DataRepo.stage_label_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray())


func test_three_maps_with_pool_rules_and_the_timed_bosses_and_eye_of_time_excluded() -> void:
	assert_eq(stage.get("map_seconds"), 300)
	var maps: Array = stage.get("maps", [])
	assert_eq(maps.size(), 3)
	for i in maps.size():
		assert_eq(int(maps[i].map_id), MAPS[i], "map %d" % (i + 1))
		assert_false(maps[i].has("opening_ramp"), "map %d: level_scale replaces the opening ramp" % (i + 1))
	assert_eq(maps[0].pool, "curve", "map 1 is a hand-written curve pool")
	assert_false(maps[0].has("pool_from_life"))
	assert_true(bool(maps[1].get("pool_from_life", false)), "map 2 takes its life list")
	assert_true(bool(maps[2].get("pool_from_life", false)), "map 3 takes its life list")
	assert_eq(maps[1].exclude, [8220005.0, float(EYE_OF_TIME)], "map 2 leaves out its timed Lilynouch and the Eye of Time")
	assert_eq(maps[2].exclude, [8220006.0], "map 3 leaves out its timed Lyka (no Eye of Time on that lane)")
	for i in maps.size():
		assert_true(float(BOSSES[i]) in maps[i].get("exclude", []) or i == 0, "map %d excludes its own boss" % (i + 1))
	# Dodo (map 1) is outside every pool: map 1's pool is the curve's keyframe pools only.
	for kf: Dictionary in stage.keyframes:
		for id: Variant in kf.get("pool", {}):
			assert_false(int(id) in BOSSES or int(id) == EYE_OF_TIME, "no keyframe pool holds the boss or the Eye of Time")
	assert_true(String(stage.get("_maps", "")).contains("Eye of Time"), "the map note records the exclusions")


func test_map_one_keyframe_pools_are_chief_memory_guardian_alone() -> void:
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		assert_eq(kf.pool, {"8200004": 1.0}, "Chief Memory Guardian, the lane's whole ordinary roster")
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


func test_level_scale_is_present_valid_and_thirty_three_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level) - float(kfs[i].exp_level), 33.0, 0.011,
			"step 16 is 33 levels above Sleepywood's pace (3 per step after step 5)")
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
		assert_false(boss.has("final_form"), "no final form in the Temple of Time")
		assert_eq(int(boss.attack_interval), 8)
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])
	# The draft tool's numbers (--step=16 --stage=temple_of_time), pinned so a retune is a visible change.
	assert_eq([float(bosses[0].hp_mult), float(bosses[1].hp_mult), float(bosses[2].hp_mult)], [0.881, 0.187, 0.21])
	assert_eq([float(bosses[0].dmg_mult), float(bosses[1].dmg_mult), float(bosses[2].dmg_mult)], [1.063, 0.768, 1.538])
	assert_eq([float(bosses[0].attack_dmg_mult), float(bosses[1].attack_dmg_mult), float(bosses[2].attack_dmg_mult)],
		[0.781, 0.848, 1.823])


func test_dodos_banish_runs_every_fifteen_seconds_with_its_v83_notice() -> void:
	var bosses := DataRepo.stage_bosses(stage)
	assert_eq(bosses[0].get("skill_intervals"), {"129": 15.0}, "Dodo's Banish every 15 s (Shade's #256 cadence)")
	assert_true(String(bosses[0].get("_skill_intervals", "")).begins_with("tier C"), "the cadence carries a tier note")
	assert_false(bosses[1].has("skill_intervals"), "Lilynouch casts no Banish")
	assert_false(bosses[2].has("skill_intervals"), "Lyka casts no Banish")
	var dodo: Dictionary = data.mobs.mobs["8220004"]
	assert_eq(String(dodo.get("banish_message", "")), "You have been ousted by the force of Dodo.", "the v83 banMsg as written")
	assert_true(String(dodo.get("_banish_message", "")).begins_with("tier A"), "the notice carries its provenance")
	for id: int in [8220005, 8220006]:
		assert_false(data.mobs.mobs[str(id)].has("banish_message"), "%d casts no Banish" % id)
	for skill: int in [102, 129, 100, 114, 128, 145]:
		assert_true(skill in MobSkillRunner.SUPPORTED, "MobSkill %d is supported" % skill)
	assert_true(145 in MobSkillRunner.REFLECT_IDS, "Lilynouch's 145 is B6's Reflect")


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_temple_of_time.json")
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
		assert_true(EXP_ITEMS.has(id), "stage mob %d is a known Temple of Time mob" % id)
	assert_false(fragment.mobs.has(float(EYE_OF_TIME)), "the Eye of Time is not imported as a mob of its own")
	var ranges := {8200004: [753, 1129], 8200008: [954, 1431], 8200012: [1156, 1734]}
	for id: int in ranges:
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_eq([int(mesos[0]), int(mesos[1])], ranges[id], "mob %d range" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	for id: int in BOSSES:
		assert_false(data.mobs.mobs[str(id)].has("mesos"), "boss %d uses the level fallback" % id)
		assert_false(data.mobs.mobs[str(id)].has("boss_ui"), "%d: its MobGage icon and hpTag are canonical" % id)
	var last := -1
	for key: String in data.mobs.mobs.keys():
		if EXP_ITEMS.has(int(key)):
			assert_true(int(key) > last, "%s inserted in id order" % key)
			last = int(key)


## The pool mobs are real ordinary monsters (no `hideName` instance or PQ copy) paying close to the level curve's EXP at their
## own level. Lv131 is the last level before level_curve.json holds its values flat, so a ratio measured above 131 would be
## against the held value; the three pool mobs are Lv101, Lv116 and Lv131 and need no such allowance.
func test_pools_resolve_to_real_monsters_that_pay_close_to_the_level_curves_exp() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var curve: Array = DataRepo.load_json("res://data/survivor/level_curve.json").exp
	var life_want := [{8200004: 14.0, 8200000: 4.0, 8220004: 1.0}, {8200008: 14.0, 8200000: 3.0, 8220005: 1.0}, {8200012: 15.0, 8220006: 1.0}]
	var pool_want := [{}, {8200008: 14.0}, {8200012: 15.0}]
	for i in MAPS.size():
		var img := lib.img(DataRepo.map_img_path(MAPS[i]))
		if img == null:
			skip("map img not imported: %d" % MAPS[i])
			lib.free()
			return
		assert_eq(StagePools.resolve({"pool_from_life": true}, img.root), life_want[i], "map %d v83 life counts" % (i + 1))
		assert_eq(StagePools.resolve(stage.maps[i], img.root), pool_want[i], "map %d pool" % (i + 1))
		for id: int in pool_want[i]:
			assert_false(id in BOSSES or id == EYE_OF_TIME, "map %d pool holds no timed boss or Eye of Time" % (i + 1))
	for id: int in POOL_LEVELS:
		var mob := lib.img("Mob.wz/%07d.img" % id)
		if mob == null:
			skip("mob %d is not imported" % id)
			lib.free()
			return
		var info: Dictionary = mob.root.info
		assert_eq(int(info.level), POOL_LEVELS[id], "mob %d level" % id)
		assert_eq(float(info.get("boss", 0)), 0.0, "%d is an ordinary mob" % id)
		assert_eq(float(info.get("hideName", 0)), 0.0, "%d is a real monster, not a hideName copy" % id)
		var ratio := float(info.exp) / float(curve[mini(int(info.level), curve.size()) - 1])
		assert_between(ratio, 0.7, 1.3, "mob %d EXP is %.2fx the level-%d curve" % [id, ratio, int(info.level)])
	# The Eye of Time is a Lv80 filler (it would pay a fraction of a Lv101-116 mob), which is why it is left out.
	var eye := lib.img("Mob.wz/%07d.img" % EYE_OF_TIME)
	if eye != null:
		assert_eq(int(eye.root.info.level), 80, "the Eye of Time is the Lv80 filler")
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
			# Spam audit (#473): no skill of these kits recasts faster than every 20 s, bar Dodo's Banish, which the stage
			# slows to the 15 s precedent through skill_intervals (its canonical 50 s is longer).
			var interval := MobSkillRunner.interval_of(table.root[str(skill)].level.get(str(int(entry.level)), {}))
			assert_true(interval >= 20.0, "boss %d skill %d recasts every %.0f s, not a spam" % [id, skill, interval])
		listed.sort()
		assert_eq(listed, SKILLS[i], "boss %d's v83 kit" % id)
		for j in ATTACKS[i].size():
			var attack: String = ATTACKS[i][j]
			assert_true(img.root.has(attack), "%d has %s" % [id, attack])
			assert_eq(int(img.root[attack].info.type), ATTACK_TYPES[i][j], "%d %s attack type" % [id, attack])
			# Spam audit (#473): every attack winds up for at least 900 ms (none is an instant screen-wide hit).
			assert_true(float(img.root[attack].info.attackAfter) >= 900.0, "%d %s winds up (attackAfter)" % [id, attack])
			assert_true(int(img.root[attack].info.type) in [0, 1, 2, 3, 4], "%d %s is a supported attack type" % [id, attack])
		# Lyka's attack1 is the type-4 area-warning attack (B5): fifteen columns, seven struck per cast.
		if id == 8220006:
			var info1: Dictionary = img.root.attack1.info
			assert_true(info1.has("areaWarning"), "Lyka's attack1 carries an area warning")
			assert_eq(int(info1.range.areaCount), 15)
			assert_eq(int(info1.range.attackCount), 7)
		# Dodo's PDD Up is a self buff at level 3; Lilynouch's Reflect is 145 level 1.
	var entries: Dictionary = lib.img("Mob.wz/8220004.img").root.info.skill
	var dodo_levels := {}
	for entry: Dictionary in entries.values():
		dodo_levels[int(entry.skill)] = int(entry.level)
	assert_eq(dodo_levels, {129: 2, 102: 3}, "Dodo's Banish 129/2 and PDD Up 102/3")
	# None of the three casts MobSkill 200, so nothing is summoned and nothing is loaded for them.
	for id: int in BOSSES:
		var extras := StageRoster.boss_extra_ids(lib.img("Mob.wz/%07d.img" % id).root, table.root)
		assert_eq(extras, PackedInt32Array(), "%d summons nothing" % id)
	lib.free()
