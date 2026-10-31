extends TestCase
## El Nath (progression step 10, spec #449 C5 #467): the stage file, map and pool rules, exclusions, drop band, level
## scale, manifest and mobs.json entries; the cache-backed parts check the real v83 rosters (including the timed Snow
## Witch and Riche that no pool may hold) and that every skill of the three bosses resolves to a supported MobSkill.

const CAL := preload("res://tests/calibrated_levels.gd")
const KEY := "el_nath"
const MAPS := [211010000, 211041100, 211042100]
const BOSSES := [6090001, 6090000, 8220001]
## Timed native bosses of the snow fields (mobTime 3600): never in a pool.
const EXCLUDED := [6090001, 6090000]
## The ordinary roster: Jr. Yeti (Lv50), Hector (55), Coolie Zombie (57), Jr. Cerebes (43), Cerebes (72).
const POOL_MOBS := [4230108, 5100000, 5130104, 5130107, 7130001]
## Skill ids the bosses may list that the runner skips on purpose.
const KNOWN_SKIPS := [120]
## Each boss's v83 skill ids (Mob.wz info/skill): Snow Witch Banish; Riche Banish and a heal; Snowman a summon, Stun and mist.
const BOSS_SKILLS := {6090001: [129], 6090000: [129, 114], 8220001: [200, 123, 131]}


func _stage() -> Dictionary:
	return DataRepo.load_all().stages.stages[KEY]


func test_stage_names_its_region_maps_and_bosses() -> void:
	var data := DataRepo.load_all()
	var stage: Dictionary = data.stages.stages[KEY]
	assert_eq(String(stage.region), "El Nath")
	assert_eq(String(stage.continent), "Ossyria")
	assert_false(String(stage.get("note", "")).is_empty(), "a card note")
	assert_eq(stage.original_life, {"5100000": 23.0, "5130104": 2.0}, "map 1's own life without the timed Snow Witch")
	assert_eq(stage.maps.map(func(e: Dictionary) -> int: return int(e.map_id)), MAPS)
	assert_eq(stage.maps.map(func(e: Dictionary) -> int: return int(e.boss.mob_id)), BOSSES)
	for entry: Dictionary in stage.maps:
		assert_eq(int(entry.boss.time), 300, "a boss 300 s after each entry")
		assert_true(String(entry.boss.get("_tier", "")).begins_with("tier C"), "tier note on the boss numbers")
		for field: String in ["hp_mult", "dmg_mult"]:
			assert_true(float(entry.boss[field]) > 0.0, "%d %s" % [int(entry.boss.mob_id), field])
	var witch: Dictionary = stage.maps[0].boss
	assert_false(witch.has("attacks"), "Snow Witch has contact and Banish only: no attack stance")
	assert_false(witch.has("attack_interval") or witch.has("attack_dmg_mult"), "so no cadence or attack scale")
	for i in [1, 2]:
		var boss: Dictionary = stage.maps[i].boss
		assert_eq(Array(boss.attacks), ["attack1"], "boss %d" % int(boss.mob_id))
		assert_eq(float(boss.attack_interval), 8.0)
		assert_true(float(boss.attack_dmg_mult) > 0.0)
	assert_true(data.stages.progression.find(KEY) > data.stages.progression.find("sleepywood"), "after Sleepywood")


func test_drop_band_and_level_scale_replace_the_opening_ramp() -> void:
	var stage := _stage()
	assert_eq(stage.drop_band, [55.0, 65.0])
	assert_false(stage.has("opening_ramp"), "level_scale, no stage ramp")
	for entry: Dictionary in stage.maps:
		assert_false(entry.has("opening_ramp"), "no map ramp either")
	assert_true(stage.has("level_scale"))
	assert_true(String(stage.get("_level_scale", "")).begins_with("Tier C"))
	var keyframes: Array = stage.level_scale.keyframes
	assert_eq(keyframes.size(), stage.keyframes.size(), "one level per curve keyframe")
	for i in keyframes.size():
		assert_eq(float(keyframes[i].t), float(stage.keyframes[i].t))
		assert_near(float(keyframes[i].level), CAL.level_at(float(keyframes[i].exp_level), float(keyframes[i].t), 10), 0.011,
			"step 10: the calibrated level (C13): 1 at 0:00 rising to Sleepywood's pace + CAL.ABOVE at 10:00, keyframe %d" % i)
	var errors := PackedStringArray()
	DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_eq(Array(errors), [], "the data validates, level_scale included")


func test_the_curve_copies_sleepywood() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var nath: Dictionary = stages[KEY]
	var reference: Dictionary = stages.sleepywood
	for field: String in ["duration", "hard_cap", "map_seconds", "exp_mult", "bursts", "elites"]:
		assert_eq(nath[field], reference[field], field)
	assert_eq(nath.get("post_duration_slope"), reference.get("post_duration_slope"), "post_duration_slope")
	assert_eq(nath.keyframes.size(), reference.keyframes.size())
	for i in nath.keyframes.size():
		for field: String in ["t", "rate", "max_alive", "hp", "speed"]:
			assert_eq(nath.keyframes[i][field], reference.keyframes[i][field], "keyframe %d %s" % [i, field])


func test_pool_rules_and_exclusions() -> void:
	var maps: Array = _stage().maps
	assert_eq(maps[0].pool, "curve", "map 1 is the hand-written curve pool")
	var want := {0.0: {"5100000": 1.0}, 120.0: {"5100000": 11.0, "5130104": 1.0}}
	for kf: Dictionary in _stage().keyframes:
		if float(kf.t) < 300.0:
			assert_eq(kf.pool, want[float(kf.t)], "map 1's own roster at %d s" % int(kf.t))
		else:
			assert_false(kf.has("pool"), "no pool from 300 s: map 1 reads only keyframes under 300 s")
	for i in [1, 2]:
		assert_eq(maps[i].get("pool_from_life"), true, "map %d uses its life list" % (i + 1))
		assert_eq(maps[i].exclude, [6090001.0, 6090000.0])
	for boss_id: int in EXCLUDED:
		assert_false(StagePools.resolve({"pool_from_life": true, "exclude": EXCLUDED}, {"life": {
			"0": {"type": "m", "id": str(boss_id)}}}).has(boss_id), "timed native boss %d never pools" % boss_id)


func test_manifest_fragment_and_mobs_json() -> void:
	var data := DataRepo.load_all()
	var manifest := AssetManifest.load_merged("res://data/asset_manifest.json")
	for map_id: int in MAPS:
		assert_has(manifest.maps, float(map_id), "map %d in the manifest" % map_id)
	for id: int in POOL_MOBS + BOSSES:
		assert_has(manifest.mobs, float(id), "mob %d in the manifest" % id)
		var entry: Dictionary = data.mobs.mobs.get(str(id), {})
		assert_false(entry.is_empty(), "mob %d in mobs.json" % id)
		assert_false(String(entry.get("name", "")).is_empty(), "mob %d named" % id)
		var item := int(entry.get("exp_item", 0))
		assert_true(item >= 4000000, "mob %d has an EXP item" % id)
		assert_has(manifest.items, float(item), "item %d in the manifest" % item)
		assert_true(String(entry.get("_exp_item", "")).begins_with("tier"), "mob %d EXP item provenance" % id)
		if id in POOL_MOBS:
			assert_eq(Array(entry.get("mesos", [])).size(), 2, "mob %d lists a meso range (neighbour method)" % id)
	for id: int in BOSSES:
		assert_has(data.balance.mob_skills.enabled_ids, float(id), "boss %d casts its kit" % id)
	var last := -1
	for key: String in data.mobs.mobs.keys():
		if int(key) in POOL_MOBS or int(key) in BOSSES:
			assert_true(int(key) > last, "%s inserted in id order" % key)
			last = int(key)

## Snow Witch and Riche cast Banish every 15 s (Shade's #256 rule), with their v83 banMsg as the notice.
func test_banish_bosses_follow_shades_interval_and_have_their_message() -> void:
	var stage := _stage()
	var mobs: Dictionary = DataRepo.load_all().mobs.mobs
	for i in 2:
		var boss: Dictionary = stage.maps[i].boss
		assert_eq(int(boss.get("skill_intervals", {}).get("129", 0)), 15, "boss %d Banish every 15 s" % int(boss.mob_id))
		assert_ne(String(mobs[str(int(boss.mob_id))].get("banish_message", "")), "", "boss %d banish message" % int(boss.mob_id))


func test_rosters_and_boss_skills_on_the_real_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	for map_id: int in MAPS:
		if lib.img(DataRepo.map_img_path(map_id)) == null:
			lib.free()
			skip("El Nath maps not imported (run scripts/import.sh with the current manifest)")
			return
	var stage := _stage()
	var want := [{5100000: 23.0, 5130104: 2.0}, {5130107: 26.0}, {7130001: 13.0, 4230108: 7.0}]
	var timed := {}
	for i in 3:
		var img := lib.img(DataRepo.map_img_path(MAPS[i]))
		var pooled := StagePools.resolve({"pool_from_life": true, "exclude": EXCLUDED}, img.root)
		assert_eq(pooled, want[i], "v83 life of map %d without the timed bosses" % MAPS[i])
		for entry: Dictionary in img.root.get("life", {}).values():
			if entry.get("type", "") == "m" and float(entry.get("mobTime", 0.0)) > 0.0:
				timed[int(entry.id)] = float(entry.mobTime)
		assert_eq(int(stage.maps[i].map_id), MAPS[i])
	assert_eq(timed, {6090001: 3600.0, 6090000: 3600.0}, "the only timed entries are Snow Witch and Riche")
	# The snow maps carry decHP 10 and ice friction (ignored, tier C); the cave carries neither.
	assert_eq(int(lib.img(DataRepo.map_img_path(MAPS[0])).root.info.get("decHP", 0)), 10)
	assert_eq(int(lib.img(DataRepo.map_img_path(MAPS[1])).root.info.get("decHP", 0)), 10)
	assert_false(lib.img(DataRepo.map_img_path(MAPS[2])).root.info.has("decHP"), "The Cave of Trial II is decHP-free")
	var skill_img: Dictionary = lib.img("Skill.wz/MobSkill.img").root
	for id: int in BOSSES:
		var boss_img: Variant = lib.img("Mob.wz/%07d.img" % id)
		assert_true(boss_img != null, "boss %d imported" % id)
		if boss_img == null:
			continue
		for attack: Variant in stage.maps[BOSSES.find(id)].boss.get("attacks", []):
			assert_true(boss_img.root.has(String(attack)), "boss %d has %s" % [id, attack])
		var skills: Variant = boss_img.root.get("info", {}).get("skill", {})
		var listed := []
		for entry: Dictionary in skills.values() if skills is Dictionary else []:
			var skill := int(entry.skill)
			listed.append(skill)
			if skill in KNOWN_SKIPS:
				continue
			assert_has(MobSkillRunner.SUPPORTED, skill, "boss %d skill %d is supported" % [id, skill])
			assert_false(skill_img.get(str(skill), {}).get("level", {}).get(str(int(entry.level)), {}).is_empty(),
				"boss %d skill %d level %d is in MobSkill.img" % [id, skill, int(entry.level)])
		assert_eq(listed, BOSS_SKILLS[id], "boss %d v83 skills" % id)
		for extra in StageRoster.boss_extra_ids(boss_img.root, skill_img):
			assert_true(lib.img("Mob.wz/%07d.img" % extra) != null, "summon %d of boss %d imported" % [extra, id])
	assert_eq(Array(StageRoster.boss_extra_ids(lib.img("Mob.wz/8220001.img").root, skill_img)), [5100000],
		"Snowman summons Jr. Yeti (already in map 1's pool)")
	assert_eq(Array(StageRoster.boss_extra_ids(lib.img("Mob.wz/6090001.img").root, skill_img)), [], "Snow Witch summons nothing")
	lib.free()
