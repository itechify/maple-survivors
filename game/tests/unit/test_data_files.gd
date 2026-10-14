extends TestCase
## The survivor data files (game/data/survivor/*.json, docs/ARCHITECTURE.md 4.4.4) load through DataRepo and refer to
## each other consistently: card skills exist, rank cards match the rank tables, stage pools name mobs with EXP items,
## jobs exist in the canonical tree, and the asset manifest imports everything the stages need.

var data: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()


func test_load_all_has_every_file() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	for key: String in ["skills", "upgrades", "stages", "balance", "mobs", "jobs_survivor", "jobs", "exp_table"]:
		assert_true(d.has(key) and not d[key].is_empty(), "setup.data.%s" % key)
	var bad := PackedStringArray()
	assert_true(DataRepo.load_all("res://no_such_dir", bad).skills.is_empty())
	assert_eq(bad.size(), 8, "every missing file reported")


func test_skills_reference_canonical_ids() -> void:
	var skills: Dictionary = data.skills.skills
	var want := {"three_snails": 1000, "energy_bolt": 2001004, "magic_claw": 2001005, "magic_guard": 2001002,
		"magic_armor": 2001003}
	for key: String in want:
		assert_true(skills.has(key), key)
		assert_eq(int(skills[key].skill_id), want[key], key)
	assert_eq(skills.three_snails.ranks, [1.0, 2.0, 3.0])
	assert_eq(skills.energy_bolt.ranks, [1.0, 5.0, 9.0, 13.0, 17.0, 20.0])
	assert_eq(skills.magic_guard.ranks, [1.0, 5.0, 10.0, 15.0, 20.0])
	assert_eq(skills.magic_claw.kind, "instant")
	for key: String in skills:
		var s: Dictionary = skills[key]
		assert_true(String(s.book) == "%03d" % floori(float(s.skill_id) / 10000.0), "%s: book matches the id" % key)
		assert_eq(String(s.icon), "Skill.wz/%s.img/skill/%07d/icon" % [s.book, int(s.skill_id)], "%s icon" % key)
		for f: String in ["ball", "hit", "effect"]:
			var p := String(s.get(f, ""))
			assert_true(p == "" or p.begins_with("Skill.wz/%s.img/skill/%07d/" % [s.book, int(s.skill_id)]),
				"%s.%s is a WZ path of the skill" % [key, f])
		assert_false(s.has("fixdamage") or s.has("mad") or s.has("mastery"), "%s: no canonical numbers here" % key)


func test_cards_are_consistent() -> void:
	var skills: Dictionary = data.skills.skills
	var ids := {}
	var kinds := ["skill_new", "skill_rank", "skill_mod", "passive", "stat", "filler"]
	var fillers := 0
	for c: Dictionary in data.upgrades.cards:
		assert_false(ids.has(c.id), "unique id %s" % c.id)
		ids[c.id] = true
		assert_true(String(c.kind) in kinds, "%s kind" % c.id)
		for k: String in ["id", "kind", "skill", "icon", "name", "desc", "max_rank", "weight", "requires", "effects"]:
			assert_true(c.has(k), "%s has %s" % [c.id, k])
		if String(c.kind).begins_with("skill_"):
			assert_true(skills.has(String(c.skill)), "%s: skill %s exists" % [c.id, c.skill])
		if c.kind == "skill_rank":
			assert_eq(int(c.max_rank), skills[c.skill].ranks.size() - 1, "%s: ranks 2..max" % c.id)
		if c.kind == "filler":
			fillers += 1
		if "{value}" in String(c.desc):
			assert_true(c.has("value"), "%s fills {value}" % c.id)
	assert_true(fillers >= 3, "enough fillers for a full draw")
	for id: String in ["three_snails_count", "three_snails_cooldown", "three_snails_pierce",
			"three_snails_speed", "energy_bolt_new", "magic_claw_new", "magic_guard_new", "magic_armor_new", "max_hp",
			"nimble_feet", "recovery", "improved_max_mp", "improved_mp_recovery", "magnet"]:
		assert_true(ids.has(id), "card %s" % id)


func test_stages_mobs_and_manifest() -> void:
	var stages: Dictionary = data.stages.stages
	var mobs: Dictionary = data.mobs.mobs
	var manifest: Variant = DataRepo.load_json("res://data/asset_manifest.json")
	assert_true(manifest is Dictionary)
	var want_maps := {"henesys_hg1": 104040000, "tree_that_grew_1": 101010100}
	assert_eq(stages.keys(), want_maps.keys(), "only the two distinct stages are offered")
	assert_eq(manifest.maps, [104040000.0, 101010100.0], "only playable maps are imported")
	for key: String in want_maps:
		assert_true(stages.has(key), key)
		assert_eq(int(stages[key].map_id), want_maps[key])
		assert_true(float(want_maps[key]) in manifest.maps, "%s map in the asset manifest" % key)
		var last := -1.0
		for kf: Dictionary in stages[key].keyframes:
			assert_true(float(kf.t) > last, "%s keyframes in time order" % key)
			last = float(kf.t)
		assert_eq(last, float(stages[key].duration), "%s: a keyframe at the clear time" % key)
		for id in DataRepo.stage_mob_ids(data, key):
			assert_true(mobs.has(str(id)), "%s: mob %d in mobs.json" % [key, id])
			assert_true(float(id) in manifest.mobs, "mob %d in the asset manifest" % id)
			var item := int(mobs[str(id)].get("exp_item", 0))
			assert_true(item >= 4000000, "mob %d has an EXP item" % id)
			assert_true(float(item) in manifest.items, "item %d in the asset manifest" % item)
	var hg: Dictionary = stages.henesys_hg1
	assert_true(hg.keyframes.size() >= 7, "base pacing plus flyer arrival keyframes")
	assert_eq(float(hg.bursts.every), 90.0)
	assert_eq(float(hg.elites.hp_mult), 8.0)
	assert_eq(float(hg.elites.exp_mult), 5.0)
	var items := {100100: 4000019, 100101: 4000000, 130101: 4000016, 120100: 4000011, 210100: 4000010,
		1210100: 4000017, 1210102: 4000001, 1110100: 4000012}
	for id: int in items:
		assert_eq(int(mobs[str(id)].exp_item), items[id], "EXP item of %d" % id)


func test_jobs_and_balance() -> void:
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for k: String in data.jobs_survivor.jobs:
		assert_false(tree.job(int(k)).is_empty(), "survivor job %s exists in the canonical tree" % k)
	assert_true(tree.job(200).playable)
	for id: int in [100, 210, 220, 230, 300, 400, 500]:
		assert_false(tree.job(id).playable, "%d not playable" % id)
	var b: Dictionary = data.balance
	assert_eq(float(b.invincible_time), 1.5)
	assert_eq(float(b.magnet_radius), 90.0)
	assert_eq(float(b.mob_speed_factor), 0.625)
	assert_eq(float(b.knockback.speed), 187.5)
	assert_eq(float(b.touch_damage.scale), 0.55)
	assert_eq(float(b.mp_regen), 2.0)
	assert_eq(float(b.growth["0"].hp), 14.0)
	assert_eq(float(b.growth["200"].mp), 22.0)
	assert_eq(float(b.growth["200"].int), 5.0)


func test_build_setup_and_paths() -> void:
	assert_eq(DataRepo.map_img_path(104040000), "Map.wz/Map/Map1/104040000.img")
	assert_eq(DataRepo.map_img_path(101010100), "Map.wz/Map/Map1/101010100.img")
	assert_eq(DataRepo.map_img_path(10000), "Map.wz/Map/Map0/000010000.img")
	var mob_ids := DataRepo.stage_mob_ids(data, "henesys_hg1")
	assert_eq(mob_ids, PackedInt32Array([100100, 100101, 120100, 130101, 210100, 1110100, 1210100, 1210102,
		2300100, 9300062, 9300063, 9300064]))
	var asked: Array = []
	var loader := func(p: String) -> Dictionary:
		asked.append(p)
		return {"info": {}} if p.begins_with("Character.wz/") else {"stub": p}
	var mob_loader := func(id: int) -> Dictionary: return {} if id == 1110100 else {"info": {"id": id}}
	var missing := PackedStringArray()
	var s := DataRepo.build_setup(data, "henesys_hg1", 5, Vector2(800, 600), loader, mob_loader, missing)
	assert_eq(s.map_img, {"stub": "Map.wz/Map/Map1/104040000.img"})
	assert_eq(s.physics_img, {"stub": "Map.wz/Physics.img"})
	assert_eq(s.skill_imgs.keys().size(), 3, "books 000, 200, 210")
	assert_true(s.skill_imgs.has("000") and s.skill_imgs.has("200"))
	assert_eq(s.mob_imgs.size(), mob_ids.size() - 1, "all stage kinds except the loader's missing Green Mushroom")
	assert_eq(missing, PackedStringArray(["Mob.wz/1110100.img"]))
	assert_eq(s.stage, "henesys_hg1")
	assert_eq(s.seed, 5)
	assert_eq(s.view_size, Vector2(800, 600))
	assert_true(s.data == data)


func test_setup_carries_canonical_equipment_and_mob_skills() -> void:
	var loader := func(p: String) -> Dictionary:
		if p == "Skill.wz/MobSkill.img":
			return {"126": {"level": {"1": {"time": 10.0, "x": 50.0}}}}
		if p == "Character.wz/Coat/01040002.img":
			return {"info": {"incPDD": 3.0}}
		return {"info": {"incPDD": 1.0}}
	var s := DataRepo.build_setup(data, "henesys_hg1", 1, Vector2(800, 600), loader,
		func(_id: int) -> Dictionary: return {"info": {"maxHP": 1}})
	assert_eq(s.equipment_info[1040002].incPDD, 3.0, "canonical equipment info, untouched")
	assert_true(s.equipment_info.has(1302000) and s.equipment_info.has(1372005), "both starter weapons")
	assert_eq(s.mob_skill_img["126"].level["1"].time, 10.0, "boss skill levels, untouched")
