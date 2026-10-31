extends TestCase
## Omega Sector (progression step 7, spec #449 C2 #464): the stage file, map and pool rules, exclusions, drop band,
## level scale, manifest and mobs.json entries; the cache-backed parts check the real v83 rosters and that every
## skill of the three bosses resolves to a supported MobSkill.

const KEY := "omega_sector"
const MAPS := [221040000, 221030200, 221030500]
const BOSSES := [4240000, 5120100, 6220001]
## Timed native bosses of the Omega fields (mobTime > 0): never in a pool.
const EXCLUDED := [4240000, 5120100]
## The ordinary roster: Barnard Gray (Lv40), Mateon (41), Plateon (44), Mecateon (46).
const POOL_MOBS := [4230116, 4230119, 4230120, 4230121]
## Skill ids the bosses may list that the runner skips on purpose.
const KNOWN_SKIPS := [120]


func _stage() -> Dictionary:
	return DataRepo.load_all().stages.stages[KEY]


func test_stage_names_its_region_maps_and_bosses() -> void:
	var data := DataRepo.load_all()
	var stage: Dictionary = data.stages.stages[KEY]
	assert_eq(String(stage.region), "Omega Sector")
	assert_eq(String(stage.continent), "Ossyria")
	assert_false(String(stage.get("note", "")).is_empty(), "a card note")
	assert_eq(stage.original_life, {"4230116": 17.0}, "map 1's own life")
	assert_eq(stage.maps.map(func(e: Dictionary) -> int: return int(e.map_id)), MAPS)
	assert_eq(stage.maps.map(func(e: Dictionary) -> int: return int(e.boss.mob_id)), BOSSES)
	for entry: Dictionary in stage.maps:
		assert_eq(int(entry.boss.time), 300, "a boss 300 s after each entry")
		assert_eq(Array(entry.boss.attacks), ["attack1"])
		assert_eq(float(entry.boss.attack_interval), 8.0)
		assert_true(String(entry.boss.get("_tier", "")).begins_with("tier C"), "tier note on the boss numbers")
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(entry.boss[field]) > 0.0, "%d %s" % [int(entry.boss.mob_id), field])
	assert_true(data.stages.progression.find(KEY) > data.stages.progression.find("sleepywood"), "after Sleepywood")


func test_drop_band_and_level_scale_replace_the_opening_ramp() -> void:
	var stage := _stage()
	assert_eq(stage.drop_band, [40.0, 50.0])
	assert_false(stage.has("opening_ramp"), "level_scale, no stage ramp")
	for entry: Dictionary in stage.maps:
		assert_false(entry.has("opening_ramp"), "no map ramp either")
	assert_true(stage.has("level_scale"))
	assert_true(String(stage.get("_level_scale", "")).begins_with("Tier C"))
	var keyframes: Array = stage.level_scale.keyframes
	assert_eq(keyframes.size(), stage.keyframes.size(), "one level per curve keyframe")
	for i in keyframes.size():
		assert_eq(float(keyframes[i].t), float(stage.keyframes[i].t))
		assert_true(float(keyframes[i].level) > float(keyframes[i].exp_level), "harder than the character's pace")
	var errors := PackedStringArray()
	DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_eq(Array(errors), [], "the data validates, level_scale included")


func test_the_curve_copies_sleepywood() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	var omega: Dictionary = stages[KEY]
	var reference: Dictionary = stages.sleepywood
	for field: String in ["duration", "hard_cap", "map_seconds", "exp_mult", "bursts", "elites"]:
		assert_eq(omega[field], reference[field], field)
	assert_eq(omega.get("post_duration_slope"), reference.get("post_duration_slope"), "post_duration_slope")
	assert_eq(omega.keyframes.size(), reference.keyframes.size())
	for i in omega.keyframes.size():
		for field: String in ["t", "rate", "max_alive", "hp", "speed"]:
			assert_eq(omega.keyframes[i][field], reference.keyframes[i][field], "keyframe %d %s" % [i, field])


func test_pool_rules_and_exclusions() -> void:
	var maps: Array = _stage().maps
	assert_eq(maps[0].pool, "curve", "map 1 is the hand-written curve pool")
	for kf: Dictionary in _stage().keyframes:
		if float(kf.t) < 300.0:
			assert_eq(kf.pool, {"4230116": 1.0}, "map 1's own roster under 300 s")
		else:
			assert_false(kf.has("pool"), "no pool from 300 s: map 1 reads only keyframes under 300 s")
	for i in [1, 2]:
		assert_eq(maps[i].get("pool_from_life"), true, "map %d uses its life list" % (i + 1))
		assert_eq(maps[i].exclude, [4240000.0, 5120100.0])
	for entry: Dictionary in maps:
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
	for id: int in BOSSES:
		assert_has(data.balance.mob_skills.enabled_ids, float(id), "boss %d casts its kit" % id)
	var ids: Array = data.mobs.mobs.keys()
	var last := -1
	for key: String in ids:
		if int(key) in POOL_MOBS or int(key) in BOSSES:
			assert_true(int(key) > last, "%s inserted in id order" % key)
			last = int(key)


func test_a_grouped_attack_effect_plays_its_first_group() -> void:
	var grouped := {"effect": {"0": {"0": {"$canvas": {}}, "1": {"$canvas": {}}}, "1": {"0": {"$canvas": {}}}, "x": 105}}
	assert_eq(MobAttacks.effect_path(4240000, "attack1", grouped), "Mob.wz/4240000.img/attack1/info/effect/0",
		"Chief Gray's falling bolts: the first group")
	var plain := {"effect": {"0": {"$canvas": {}}, "1": {"$canvas": {}}}}
	assert_eq(MobAttacks.effect_path(8130100, "attack1", plain), "Mob.wz/8130100.img/attack1/info/effect", "frames stay")
	assert_eq(MobAttacks.effect_path(5120100, "attack1", {"ball": {}}), "", "no effect")


func test_rosters_and_boss_skills_on_the_real_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	for map_id: int in MAPS:
		if lib.img(DataRepo.map_img_path(map_id)) == null:
			lib.free()
			skip("Omega Sector maps not imported (run scripts/import.sh with the current manifest)")
			return
	var stage := _stage()
	var want := [{4230116: 17.0}, {4230120: 27.0, 4230119: 7.0}, {4230121: 21.0, 4230120: 11.0}]
	for i in 3:
		var img := lib.img(DataRepo.map_img_path(MAPS[i]))
		assert_eq(StagePools.resolve({"pool_from_life": true, "exclude": EXCLUDED}, img.root), want[i],
			"v83 life of map %d" % MAPS[i])
		for entry: Dictionary in img.root.get("life", {}).values():
			if entry.get("type", "") == "m":
				assert_false(int(entry.id) in EXCLUDED, "map %d lists no timed native boss" % MAPS[i])
		assert_eq(int(stage.maps[i].map_id), MAPS[i])
	var skill_img: Dictionary = lib.img("Skill.wz/MobSkill.img").root
	for id: int in BOSSES:
		var boss_img: Variant = lib.img("Mob.wz/%07d.img" % id)
		assert_true(boss_img != null, "boss %d imported" % id)
		if boss_img == null:
			continue
		for attack: Variant in stage.maps[BOSSES.find(id)].boss.attacks:
			assert_true(boss_img.root.has(String(attack)), "boss %d has %s" % [id, attack])
		var skills: Variant = boss_img.root.get("info", {}).get("skill", {})
		for entry: Dictionary in skills.values() if skills is Dictionary else []:
			var skill := int(entry.skill)
			if skill in KNOWN_SKIPS:
				continue
			assert_has(MobSkillRunner.SUPPORTED, skill, "boss %d skill %d is supported" % [id, skill])
			assert_false(skill_img.get(str(skill), {}).get("level", {}).get(str(int(entry.level)), {}).is_empty(),
				"boss %d skill %d level %d is in MobSkill.img" % [id, skill, int(entry.level)])
		for extra in StageRoster.boss_extra_ids(boss_img.root, skill_img):
			assert_true(lib.img("Mob.wz/%07d.img" % extra) != null, "summon %d of boss %d imported" % [extra, id])
	assert_eq(Array(StageRoster.boss_extra_ids(lib.img("Mob.wz/4240000.img").root, skill_img)), [4230116],
		"Chief Gray summons Barnard Gray")
	lib.free()
