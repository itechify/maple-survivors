extends TestCase
## The survivor data files (game/data/survivor/*.json, docs/ARCHITECTURE.md 4.4.4) load through DataRepo and refer to
## each other consistently: card skills exist, rank cards match the rank tables, stage pools name mobs with EXP items,
## jobs exist in the canonical tree, and the asset manifest imports the stages and the Free Market hub.

var data: Dictionary

const RF := preload("res://tests/fixtures/run_fixtures.gd")


func before_each() -> void:
	data = DataRepo.load_all()


func test_load_all_has_every_file() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	for key: String in ["skills", "upgrades", "stages", "balance", "mobs", "equipment_drops", "jobs_survivor", "scrolls", "shops", "jobs", "exp_table", "cash_items", "ammo"]:
		assert_true(d.has(key) and not d[key].is_empty(), "setup.data.%s" % key)
	var bad := PackedStringArray()
	assert_true(DataRepo.load_all("res://no_such_dir", bad).skills.is_empty())
	assert_eq(bad.size(), 13, "every missing file reported")


func test_every_stage_names_its_region_and_continent() -> void:
	var want := {"henesys": ["Henesys", "Victoria Island"], "ellinia": ["Ellinia", "Victoria Island"],
		"perion": ["Perion", "Victoria Island"], "kerning": ["Kerning City", "Victoria Island"],
		"sleepywood": ["Sleepywood", "Victoria Island"]}
	assert_eq(data.stages.stages.keys(), want.keys())
	for key: String in want:
		var st: Dictionary = data.stages.stages[key]
		assert_eq(String(st.get("region", "")), want[key][0], "%s region" % key)
		assert_eq(String(st.get("continent", "")), want[key][1], "%s continent" % key)
		assert_eq(DataRepo.stage_labels(data.stages, key), {"region": want[key][0], "continent": want[key][1]})
	assert_true(DataRepo.stage_label_errors(data.stages).is_empty(), "the shipped stages validate")
	var broken: Dictionary = data.stages.duplicate(true)
	broken.stages.henesys.erase("region")
	broken.stages.sleepywood.continent = " "
	var errors := DataRepo.stage_label_errors(broken)
	assert_eq(errors.size(), 2, "%s" % [errors])
	assert_true(errors[0].contains("henesys") and errors[0].contains("region"))
	assert_true(errors[1].contains("sleepywood") and errors[1].contains("continent"))


func test_stage_labels_fall_back_to_the_old_name() -> void:
	var stages := {"stages": {"x": {"name": "Old Map"}}}
	assert_eq(DataRepo.stage_labels(stages, "x"), {"region": "Old Map", "continent": ""})
	assert_eq(DataRepo.stage_labels(stages, "gone"), {"region": "", "continent": ""})


func test_skills_reference_canonical_ids() -> void:
	var skills: Dictionary = data.skills.skills
	var want := {"three_snails": 1000, "energy_bolt": 2001004, "magic_claw": 2001005,
		"magic_armor": 2001003, "recovery": 1001, "nimble_feet": 1002}
	for gone: String in ["magic_guard", "improved_max_mp", "improved_mp_recovery", "mp_eater_fp", "mp_eater_il",
			"mp_eater_cleric", "mp_recovery"]:
		assert_false(skills.has(gone), "%s went with MP (#285)" % gone)
	for key: String in want:
		assert_true(skills.has(key), key)
		assert_eq(int(skills[key].skill_id), want[key], key)
	assert_eq(skills.magic_claw.kind, "instant")
	for key: String in skills:
		var s: Dictionary = skills[key]
		assert_true(String(s.book) == "%03d" % floori(float(s.skill_id) / 10000.0), "%s: book matches the id" % key)
		assert_eq(String(s.icon), "Skill.wz/%s.img/skill/%07d/icon" % [s.book, int(s.skill_id)], "%s icon" % key)
		for f: String in ["ball", "hit", "effect"]:
			var p := String(s.get(f, ""))
			var shared_teleport := f == "effect" and s.has("teleport") and p == "Effect.wz/BasicEff.img/Teleport"
			assert_true(p == "" or shared_teleport or p.begins_with("Skill.wz/%s.img/skill/%07d/" % [s.book, int(s.skill_id)]),
				"%s.%s is a WZ path of the skill" % [key, f])
		assert_false(s.has("fixdamage") or s.has("mad") or s.has("mastery"), "%s: no canonical numbers here" % key)


func test_skill_ranks_cover_every_canonical_level_in_the_fixtures() -> void:
	_assert_ranks_cover_canonical_levels(SkillBook.from_data(data.skills, RF.skill_imgs()))


func test_skill_ranks_cover_every_canonical_level_in_the_real_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var imgs := {}
	for skill: Dictionary in data.skills.skills.values():
		var book := String(skill.book)
		if not imgs.has(book):
			imgs[book] = lib.img("Skill.wz/%s.img" % book).root
	_assert_ranks_cover_canonical_levels(SkillBook.from_data(data.skills, imgs))
	lib.free()


func _assert_ranks_cover_canonical_levels(book: SkillBook) -> void:
	for key: String in book.defs:
		if bool(book.def(key).get("common_passive", false)):
			# #289: a common passive is survivor-made: its icon skill's WZ node has no level table, rank r is level r.
			assert_eq(book.max_rank(key), 5, "%s: five ranks" % key)
			assert_eq(book.canonical_level(key, 5), 5)
			continue
		if key == "rush_hero" and book.skill_node(key).is_empty():
			continue # the synthetic fixtures carry no Rush node; the real-cache run covers it
		var top := book.max_level(key)
		assert_true(top > 0, "%s has a canonical level table" % key)
		# Hero's Rush (#302) takes the level-30 survivor table like a pool skill, but stays at rank 1 for the whole round.
		if key in data.jobs_survivor.jobs["212"].skill_pool or key in data.jobs_survivor.jobs["112"].skill_pool or key == "rush_hero":
			assert_eq(book.max_rank(key), 8)
			assert_eq(book.canonical_level(key, 8), top)
			continue
		assert_eq(book.max_rank(key), top, "%s: one rank per canonical level" % key)
		var ranks: Array = book.rank_table(key)
		for level in range(1, top + 1):
			if level <= ranks.size():
				assert_eq(int(ranks[level - 1]), level, "%s rank %d is canonical level %d" % [key, level, level])


func test_cards_are_consistent() -> void:
	var skills: Dictionary = data.skills.skills
	var ids := {}
	var kinds := ["skill_new", "skill_rank", "skill_mod", "passive", "stat"]
	for c: Dictionary in data.upgrades.cards:
		assert_false(ids.has(c.id), "unique id %s" % c.id)
		ids[c.id] = true
		assert_true(String(c.kind) in kinds, "%s kind" % c.id)
		for k: String in ["id", "kind", "skill", "icon", "name", "desc", "max_rank", "weight", "requires", "effects"]:
			assert_true(c.has(k), "%s has %s" % [c.id, k])
		if String(c.kind).begins_with("skill_"):
			assert_true(skills.has(String(c.skill)), "%s: skill %s exists" % [c.id, c.skill])
		if c.kind == "skill_rank":
			assert_eq(int(c.max_rank), 0 if c.skill in ["energy_bolt", "magic_claw", "fire_arrow", "poison_breath"] else skills[c.skill].ranks.size(), "%s: max_rank is the canonical level cap" % c.id)
			assert_eq(c.effects, [{"stat": "rank", "op": "add", "value": 1.0}], "%s: one level per card" % c.id)
		for effect: Dictionary in c.effects:
			assert_false(effect.op == "heal", "%s cannot heal by percentage" % c.id)
			assert_false(effect.stat == "hp_regen", "%s cannot grant the removed passive Recovery regen" % c.id)
		if "{value}" in String(c.desc):
			assert_true(c.has("value"), "%s fills {value}" % c.id)
	for id: String in ["energy_bolt_new", "magic_claw_new", "magic_armor_new"]:
		assert_true(ids.has(id), "card %s" % id)
	# #284: the Beginner is gone (its cards with it) and Teleport is a start skill, not a card.
	for c: Dictionary in data.upgrades.cards:
		assert_false(String(c.get("skill", "")) in ["three_snails", "nimble_feet", "recovery"], "%s is a Beginner card" % c.id)
		assert_false(String(c.get("skill", "")).begins_with("teleport_"), "%s is a Teleport card" % c.id)
		assert_false(c.get("requires", {}).has("carry_jobs"), "%s has no carry_jobs" % c.id)
	var fallback: Dictionary = data.upgrades.fallback
	assert_false(ids.has(fallback.id), "fallback is outside the weighted pool")
	assert_eq(fallback.kind, "filler")
	assert_eq(fallback.requires, {}, "fallback is job-neutral")
	assert_eq(int(fallback.max_rank), 0, "healing can be taken again on a later reward")
	assert_eq(fallback.effects, [{"stat": "hp", "op": "heal", "value": 1.0}], "Power Elixir fully restores HP (no MP, #285)")
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_has(manifest.items, 2000005.0, "Power Elixir art is imported")


func test_stat_cards_are_replaced_by_owned_skills() -> void:
	var pool := UpgradePool.from_data(data.upgrades)
	assert_true(pool.card("max_hp").is_empty(), "the non-MapleStory Max HP card is removed")
	var key := "magic_armor"
	assert_eq(pool.card(key + "_new").kind, "skill_new", "%s learns its skill" % key)
	assert_eq(pool.card(key + "_new").skill, key)
	assert_eq(pool.card(key + "_new").effects, [], "no flat stat effects remain")
	assert_eq(pool.card(key + "_rank").kind, "skill_rank")
	assert_eq(pool.card(key + "_new").requires.jobs, [200.0])
	assert_eq(pool.card(key + "_rank").requires.jobs, [200.0])
	for gone: String in ["improved_max_mp", "nimble_feet", "recovery"]:
		assert_true(pool.card(gone).is_empty(), "%s went with MP (#285) or the Beginner (#284)" % gone)


func test_stages_mobs_and_manifest() -> void:
	var stages: Dictionary = data.stages.stages
	var mobs: Dictionary = data.mobs.mobs
	var manifest: Variant = AssetManifest.load_merged("res://data/asset_manifest.json")
	assert_true(manifest is Dictionary)
	var want_maps := {"henesys": 104040000, "ellinia": 101010100, "perion": 102010000, "kerning": 103010000,
		"sleepywood": 105050400}
	assert_eq(stages.keys(), want_maps.keys(), "the five distinct stages are offered")
	assert_eq(manifest.maps, [104040000.0, 104010001.0, 100030001.0, 101010100.0, 100040100.0,
		100040105.0, 102010000.0, 101030404.0, 106000101.0, 103010000.0, 103000101.0, 107000000.0,
		105050400.0, 105090310.0, 105090900.0, 910000000.0],
		"the three maps of each region and the Free Market hub are imported")
	for key: String in want_maps:
		assert_true(stages.has(key), key)
		assert_eq(int(stages[key].maps[0].map_id), want_maps[key])
		assert_true(float(want_maps[key]) in manifest.maps, "%s map in the asset manifest" % key)
		var last := -1.0
		for kf: Dictionary in stages[key].keyframes:
			assert_true(float(kf.t) > last, "%s keyframes in time order" % key)
			last = float(kf.t)
		assert_eq(last, float(stages[key].duration), "%s: a keyframe at the clear time" % key)
		for id in DataRepo.stage_mob_ids(data, key):
			if not mobs.has(str(id)):
				skip("later map mob metadata awaits #242: %d" % id)
				return
			assert_true(mobs.has(str(id)), "%s: mob %d in mobs.json" % [key, id])
			assert_true(float(id) in manifest.mobs, "mob %d in the asset manifest" % id)
			var item := int(mobs[str(id)].get("exp_item", 0))
			assert_true(item >= 4000000, "mob %d has an EXP item" % id)
			assert_true(float(item) in manifest.items, "item %d in the asset manifest" % item)
	var hg: Dictionary = stages.henesys
	assert_true(hg.keyframes.size() >= 7, "base pacing plus flyer arrival keyframes")
	assert_eq(float(hg.bursts.every), 90.0)
	assert_eq(float(hg.elites.hp_mult), 8.0)
	assert_eq(float(hg.elites.exp_mult), 5.0)
	var items := {100100: 4000019, 100101: 4000000, 130101: 4000016, 120100: 4000011, 210100: 4000010,
		1210100: 4000017, 1210102: 4000001, 1110100: 4000012}
	for id: int in items:
		assert_eq(int(mobs[str(id)].exp_item), items[id], "EXP item of %d" % id)


func test_three_map_mobs_have_imported_exp_pickups_and_meso_ranges() -> void:
	var manifest := AssetManifest.load_merged("res://data/asset_manifest.json")
	# tier B: v83 server drop facts; tier C: signature drops represent EXP in survivor mode.
	var drops := {1210101: [4000002, 20, 30], 2220100: [4000009, 36, 54],
		4230101: [4000031, 104, 156], 5300100: [4000041, 251, 359],
		4230100: [4000023, 96, 144], 5130100: [4000014, 200, 300], 6230600: [4000030, 324, 486]}
	for id: int in drops:
		assert_has(manifest.mobs, float(id), "mob %d is imported" % id)
		var mob: Dictionary = data.mobs.mobs.get(str(id), {})
		assert_eq(int(mob.get("exp_item", 0)), drops[id][0], "mob %d signature EXP pickup" % id)
		assert_has(manifest.items, float(drops[id][0]), "mob %d EXP art is imported" % id)
		assert_eq(PackedInt32Array(mob.get("mesos", [])), PackedInt32Array(drops[id].slice(1)),
			"mob %d tier B meso range" % id)
	assert_true(4090000.0 in manifest.mobs, "Iron Hook is imported for Perion's third map (spec #253)")


## Spec #253: every ordinary mob of the Perion and Kerning City maps (map-1 pools and the map-2/3 v83 life lists) and
## both new bosses have a mobs.json entry with a signature EXP item and meso range, and are explicitly imported.
## Expected values are v83 server drop facts (tier B: the most likely Etc drop and the itemid-0 meso range), or tier C
## where the server lists no drops (Iron Hook: level-fallback mesos and a borrowed EXP icon).
func test_perion_and_kerning_mobs_have_exp_pickups_meso_ranges_and_imports() -> void:
	var manifest := AssetManifest.load_merged("res://data/asset_manifest.json")
	var drops := {130100: [4000003, 12, 18], 1110101: [4000005, 20, 30], 1130100: [4000018, 32, 48],
		2130100: [4000215, 40, 60], 2230102: [4000020, 44, 66], 3210100: [4000024, 76, 114],
		1120100: [4000006, 24, 36], 1210103: [4000037, 24, 36], 3110100: [4000032, 74, 144],
		2130103: [4000034, 33, 49], 5090000: [4000413, 800, 920], 4090000: [4000020]}
	for id: int in drops:
		assert_has(manifest.mobs, float(id), "mob %d is imported" % id)
		var mob: Dictionary = data.mobs.mobs.get(str(id), {})
		assert_false(String(mob.get("name", "")).is_empty(), "mob %d has an English fallback name" % id)
		assert_eq(int(mob.get("exp_item", 0)), drops[id][0], "mob %d signature EXP pickup" % id)
		assert_has(manifest.items, float(drops[id][0]), "mob %d EXP art is imported" % id)
		assert_eq(PackedInt32Array(mob.get("mesos", [])), PackedInt32Array(drops[id].slice(1)),
			"mob %d meso range (none = the level fallback)" % id)
	for key: String in ["perion", "kerning"]:
		for id in DataRepo.stage_mob_ids(data, key):
			assert_true(data.mobs.mobs.has(str(id)), "%s: pool/boss mob %d in mobs.json" % [key, id])
			assert_has(manifest.mobs, float(id), "%s: pool/boss mob %d in the asset manifest" % [key, id])


## Spec #253: Iron Hook and Shade cast their kits like the other scheduled bosses (unsupported skills are skipped).
func test_iron_hook_and_shade_are_enabled_boss_kits() -> void:
	var enabled: Array = data.balance.mob_skills.enabled_ids
	for id: float in [2220000.0, 3220000.0, 9300003.0, 6220000.0, 4090000.0, 5090000.0]:
		assert_has(enabled, id, "boss %d casts its kit" % int(id))


func test_three_map_assets_load_from_the_real_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var ids := [104010001, 100030001, 100040100, 100040105, 105090310, 105090900, 102010000, 101030404, 106000101,
		103010000, 103000101, 107000000]
	for id: int in ids:
		if not lib.has_img(AssetLibrary.map_img_path(id)):
			lib.free()
			skip("three-map assets not imported (run scripts/import.sh with the current manifest)")
			return
	var renderer := MapRenderer.new()
	renderer.library = lib
	for id: int in ids:
		assert_true(renderer.load_map(id), "map %d loads" % id)
		assert_true(renderer.missing.is_empty(), "map %d art: %s" % [id, renderer.missing])
		var root: Dictionary = renderer.map_root
		assert_false(root.get("foothold", {}).is_empty(), "map %d has footholds" % id)
		var spawns := 0
		for portal: Dictionary in root.get("portal", {}).values():
			if portal.get("pn", "") == "sp":
				spawns += 1
		assert_true(spawns > 0, "map %d has a spawn portal" % id)
		var info: Dictionary = root.get("info", {})
		var bgm := String(info.get("bgm", "")).split("/", true, 1)
		assert_eq(bgm.size(), 2, "map %d names a BGM" % id)
		if bgm.size() == 2:
			assert_true(lib.sound("Sound.wz/%s.img/%s" % [bgm[0], bgm[1]]) != null, "map %d BGM" % id)
		var mark := String(info.get("mapMark", "None"))
		if mark != "None":
			assert_true(lib.frame("Map.wz/MapHelper.img/mark/" + mark) != null, "map %d mapMark" % id)
		if id == 104010001:
			var has_iron_hook := false
			for life: Dictionary in root.get("life", {}).values():
				if life.get("type", "") == "m" and int(life.get("id", 0)) == 4090000:
					has_iron_hook = true
			assert_true(has_iron_hook, "Pig Beach retains canonical Iron Hook life; stage data excludes it")
	assert_true(lib.missing.is_empty(), "map asset lookups: %s" % lib.missing)
	renderer.free()
	lib.free()


func test_three_map_mob_animations_and_exp_art_load_from_the_real_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var ids := [1210101, 2220100, 4230101, 5300100, 4230100, 5130100, 6230600, 130100, 1110101, 1130100, 2130100,
		2230102, 3210100, 4090000, 1120100, 1210103, 3110100, 2130103, 5090000]
	for id: int in ids:
		if not lib.has_img(AssetLibrary.mob_img_path(id)):
			lib.free()
			skip("three-map mobs not imported (run scripts/import.sh with the current manifest)")
			return
	var renderer := MobRenderer.new()
	renderer.library = lib
	for id: int in ids:
		for state: int in [MobRenderer.STAND, MobRenderer.MOVE, MobRenderer.HIT, MobRenderer.DIE]:
			var anim := renderer.anim_for(id, state)
			assert_true(anim != null and not anim.is_empty(), "mob %d state %d" % [id, state])
			if anim != null:
				for frame: SpriteFrame in anim.frames:
					assert_true(frame.page != null, "mob %d state %d drawable atlas" % [id, state])
		var item := int(data.mobs.mobs[str(id)].exp_item)
		assert_true(lib.frame(AssetLibrary.item_icon_path(item)) != null, "mob %d EXP art" % id)
		if id == 5300100:
			assert_true(MobKind.from_wz(lib.mob_root(id), id, data.mobs.mobs[str(id)]).flies,
				"Malady uses the same canonical fly-stance detection as Stirge")
			assert_true(renderer.anim_for(id, MobRenderer.MOVE).path.ends_with("/fly"))
	assert_true(renderer.missing.is_empty(), "mob animations: %s" % renderer.missing)
	assert_true(lib.missing.is_empty(), "mob asset lookups: %s" % lib.missing)
	renderer.free()
	lib.free()


## Every scheduled boss's HP bar has a MobGage icon and hpTag frames: its own, or the borrowed boss_ui ones (Blue
## Mushmom, Snack Bar, Iron Hook and Shade have no icon in v83).
func test_every_scheduled_boss_has_boss_bar_art_in_the_real_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	for key: String in data.stages.stages:
		for entry: Dictionary in DataRepo.stage_bosses(data.stages.stages[key]):
			var id := int(entry.mob_id)
			var ui: Dictionary = data.mobs.mobs.get(str(id), {}).get("boss_ui", {})
			var info: Dictionary = lib.mob_root(id).get("info", {})
			assert_true(lib.frame(HudBossBar.ART + "Mob/%d" % int(ui.get("icon_id", id))) != null, "%d icon" % id)
			for tag: String in ["%d/0" % int(ui.get("hp_tag_color", info.get("hpTagColor", 1))),
					"%d/1" % int(ui.get("hp_tag_bgcolor", info.get("hpTagBgcolor", 5)))]:
				assert_true(lib.frame(HudBossBar.ART + "Gage/" + tag) != null, "%d hpTag %s" % [id, tag])
	assert_true(lib.missing.is_empty(), "boss bar lookups: %s" % lib.missing)
	lib.free()


func test_henesys_boss_order_and_slam_data() -> void:
	var entries: Array = DataRepo.stage_bosses(data.stages.stages.henesys)
	assert_eq(entries.map(func(e: Dictionary) -> int: return int(e.mob_id)), [2220000, 6130101, 9400205])
	assert_eq(entries.map(func(e: Dictionary) -> int: return int(e.time)), [300, 600, 900])
	assert_eq(entries[1].attacks, ["attack1"])
	assert_eq(entries[2].attacks, ["attack1"])
	assert_eq(data.mobs.mobs["9400205"].boss_ui.icon_id, 6130101)


func test_jobs_and_balance() -> void:
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for k: String in data.jobs_survivor.jobs:
		assert_false(tree.job(int(k)).is_empty(), "survivor job %s exists in the canonical tree" % k)
	# #284 (ADR 0006): one fixed job; F/P Arch Mage is the only playable job until the next line is ported.
	assert_eq(tree.playable_jobs(), [212] as Array[int])
	for id: int in [0, 100, 110, 200, 210, 220, 230, 300, 400, 500, 510, 520]:
		assert_false(tree.job(id).playable, "%d is not playable" % id)
	for k: String in data.jobs_survivor.jobs:
		for key: String in ["paths", "grants", "level"]:
			assert_false(data.jobs_survivor.jobs[k].has(key), "job %s has no advancement %s" % [k, key])
	for key: Variant in tree.start_skills(212):
		assert_true(data.skills.skills.has(String(key)), "start skill %s exists" % key)
	var b: Dictionary = data.balance
	assert_false(b.has("invincible_time"), "replaced by the shrinking hit_window (spec #88)")
	assert_eq(b.hit_window, {"lengths": [1.5, 1.0, 0.6, 0.4], "chain_gap": 2.5, "reset_after": 3.0})
	assert_eq(float(b.magnet_radius), 90.0)
	assert_eq(float(b.mob_speed_factor), 0.625)
	assert_eq(float(b.knockback.speed), 187.5)
	assert_false(b.has("mp_regen"), "no MP (#285)")
	assert_eq(b.regen, {"interval": 10.0, "hp": 10.0})
	assert_eq(b.level_up_refill, {"hp": 0.0}, "level-ups add no HP (owner choice); no MP refill (#285)")
	assert_eq(b.potions.cooldown, {"hp": 20.0}, "tier C: spec #237 cooldown; no MP potion (#285)")
	assert_false(b.potions.has("mp"), "no MP potion (#285)")
	assert_false(b.potions.has("drops"))
	assert_false(b.bosses.rewards.has("potions"))
	assert_false(b.bosses.rewards.has("potion_spread"))
	assert_false(b.potions.hp.has("start"))
	for key: String in data.stages.stages:
		for kf: Dictionary in data.stages.stages[key].get("keyframes", []):
			assert_false(kf.has("normal_mp_drop_chance") or kf.has("normal_hp_drop_chance"), "%s has no potion curves" % key)
		for boss: Dictionary in DataRepo.stage_bosses(data.stages.stages[key]):
			assert_false(boss.get("rewards", {}).has("potions"))
	assert_eq(float(b.growth["0"].hp), 14.0)
	assert_false(b.growth["200"].has("mp"), "no MP growth (#285)")
	assert_eq(int(b.player.ap_per_level), 5)
	assert_false(b.player.has("ap_stat") or b.player.has("ap_secondary") or b.player.has("weapon_grants") \
		or b.player.has("skills"), "#284: one AP row per job, no job weapon grant, start skills per job")
	assert_eq([String(b.player.ap["212"].primary), String(b.player.ap["212"].secondary)], ["int", "luk"],
		"212: INT primary, LUK secondary (spec #282)")
	for job: String in b.player.ap:
		assert_false(job.contains(":"), "no weapon-path AP row (%s)" % job)
	assert_false(b.growth["200"].has("int_mp_divisor"))


## Code fallbacks exist only for synthetic setups without balance data; each must repeat the shipped value exactly so
## a fact has one source (balance.json) and the fallback cannot drift from it.
func test_code_fallbacks_match_shipped_balance_data() -> void:
	var b: Dictionary = data.balance
	for key: String in RunWorld.DEFAULT_REGEN:
		assert_eq(float(b.regen[key]), float(RunWorld.DEFAULT_REGEN[key]), "RunWorld.DEFAULT_REGEN.%s" % key)
	assert_eq(b.regen.size(), RunWorld.DEFAULT_REGEN.size(), "every regen value has its fallback")
	assert_eq(b.level_up_refill, RunWorld.DEFAULT_LEVEL_UP_REFILL, "RunWorld.DEFAULT_LEVEL_UP_REFILL")
	for key: String in RunWorld.DEFAULT_STATS:
		assert_eq(int(b.player.stats[key]), int(RunWorld.DEFAULT_STATS[key]), "RunWorld.DEFAULT_STATS.%s" % key)
	var body: Array = b.player.body
	assert_eq(Rect2(body[0], body[1], body[2], body[3]), RunWorld.DEFAULT_BODY, "RunWorld.DEFAULT_BODY")
	assert_eq(float(b.player.cast_height), RunWorld.DEFAULT_CAST_HEIGHT, "RunWorld.DEFAULT_CAST_HEIGHT")
	assert_eq(float(b.player.cast_forward), RunWorld.DEFAULT_CAST_FORWARD, "RunWorld.DEFAULT_CAST_FORWARD")
	assert_eq(float(b.mob_skills.summon_spacing), RunWorld.DEFAULT_SUMMON_SPACING, "RunWorld.DEFAULT_SUMMON_SPACING")
	for key: String in BossDirector.DEFAULT_RULES:
		assert_eq(float(b.bosses[key]), float(BossDirector.DEFAULT_RULES[key]), "BossDirector.DEFAULT_RULES.%s" % key)
	for kind: String in PotionInventory.DEFAULT_ITEMS:
		assert_eq(int(b.potions[kind].item_id), int(PotionInventory.DEFAULT_ITEMS[kind]), "PotionInventory.DEFAULT_ITEMS.%s" % kind)
	assert_eq(float(b.mob_projectiles.radius), MobProjectileSystem.DEFAULT_RADIUS, "MobProjectileSystem.DEFAULT_RADIUS")
	assert_eq(float(b.mob_attacks.default_interval), MobAttacks.DEFAULT_INTERVAL, "MobAttacks.DEFAULT_INTERVAL")
	assert_false(b.player.has("equipment") or b.player.has("weapon_by_job"), "worn equipment is the only source")
	assert_eq(int(b.player.inventory_slots), RunWorld.DEFAULT_INVENTORY_SLOTS, "RunWorld.DEFAULT_INVENTORY_SLOTS")
	assert_eq(AvatarRenderer.DEFAULT_LOOK.equips, Equipment.DEFAULT_OUTFIT.slice(0, 3),
		"AvatarRenderer.DEFAULT_LOOK.equips is the default creation outfit without its weapon")
	var no_drops := data.duplicate()
	no_drops.erase("equipment_drops")
	assert_eq(DataRepo.starter_equipment_ids(no_drops), PackedInt32Array(Equipment.DEFAULT_OUTFIT),
		"without MakeCharInfo the setup loads the default outfit only (no job grants a weapon since #284)")
	var with_drops := DataRepo.starter_equipment_ids(data)
	var expected := {}
	for id: Variant in Equipment.DEFAULT_OUTFIT + data.equipment_drops.items:
		expected[int(id)] = true
	for id: Variant in data.equipment_drops.items:
		assert_true(int(id) in with_drops, "the drop list item %d has its info loaded" % int(id))
	assert_eq(with_drops.size(), expected.size(), "listed items are added once")


func test_build_setup_and_paths() -> void:
	assert_eq(DataRepo.map_img_path(104040000), "Map.wz/Map/Map1/104040000.img")
	assert_eq(DataRepo.map_img_path(101010100), "Map.wz/Map/Map1/101010100.img")
	assert_eq(DataRepo.map_img_path(10000), "Map.wz/Map/Map0/000010000.img")
	var mob_ids := DataRepo.stage_mob_ids(data, "henesys")
	assert_eq(mob_ids, PackedInt32Array([100100, 100101, 120100, 130101, 210100, 1110100, 1210100, 1210102,
		2220000, 2300100, 6130101, 9300062, 9300063, 9300064, 9400205]))
	var asked: Array = []
	var loader := func(p: String) -> Dictionary:
		asked.append(p)
		if p == "Item.wz/Consume/0200.img" or p == "Item.wz/Consume/0202.img":
			var items := {}
			for id in DataRepo.potion_item_ids(data):
				if DataRepo.potion_img_path(id) == p:
					items["%08d" % id] = {"spec": {"hp": 50.0}}
			return items
		if p == DataRepo.SCROLL_IMG:
			var scrolls := {}
			for id: int in Scrolls.ids(data.scrolls):
				scrolls["%08d" % id] = {"info": {"success": 60.0, "incMAD": 2.0}}
			return scrolls
		for ammo_id in Ammo.item_ids(data.ammo):
			if p == Ammo.img_path(ammo_id):
				var ammo_items := {}
				for id in Ammo.item_ids(data.ammo):
					ammo_items["%08d" % id] = {"info": {"incPAD": 7}}
				return ammo_items
		return {"info": {}} if p.begins_with("Character.wz/") else {"stub": p}
	var mob_loader := func(id: int) -> Dictionary: return {} if id == 1110100 else {"info": {"id": id}}
	var missing := PackedStringArray()
	var s := DataRepo.build_setup(data, "henesys", 5, Vector2(800, 600), loader, mob_loader, missing)
	assert_eq(s.map_img, {"stub": "Map.wz/Map/Map1/104040000.img"})
	assert_eq(s.physics_img, {"stub": "Map.wz/Physics.img"})
	assert_eq(s.skill_imgs.keys().size(), DataRepo.skill_books(data).size(), "every shipped skill book is loaded")
	assert_true(s.skill_imgs.has("000") and s.skill_imgs.has("200"))
	assert_has(s.skill_imgs, "220", "Ice/Lightning Wizard book")
	assert_has(s.skill_imgs, "230", "Cleric attacks and Teleport book")
	assert_eq(s.mob_imgs.size(), mob_ids.size() - 1, "all stage kinds except the loader's missing Green Mushroom")
	assert_eq(missing, PackedStringArray(["Mob.wz/1110100.img"]))
	assert_eq(s.ammo_info.size(), 18, "the ammo items' canonical facts are in the setup (#155)")
	assert_eq(s.ammo_info[2070001], {"incPAD": 7})
	assert_eq(s.scroll_info.size(), Scrolls.ids(data.scrolls).size(), "every roster scroll's canonical info is loaded")
	assert_eq(s.scroll_info[2043700], {"success": 60, "incMAD": 2})
	assert_eq(s.stage, "henesys")
	assert_eq(s.seed, 5)
	assert_eq(s.view_size, Vector2(800, 600))
	assert_true(s.data == data)


func test_setup_carries_canonical_equipment_and_mob_skills() -> void:
	var loader := func(p: String) -> Dictionary:
		if p == "Skill.wz/MobSkill.img":
			return {"126": {"level": {"1": {"time": 10.0, "x": 50.0}}}}
		if p == "Character.wz/Coat/01040002.img":
			return {"info": {"incPDD": 3.0}}
		if p.begins_with("Character.wz/Weapon/"):
			return {"info": {"incPDD": 1.0, "afterImage": "swordOL"}}
		return {"info": {"incPDD": 1.0}}
	var s := DataRepo.build_setup(data, "henesys", 1, Vector2(800, 600), loader,
		func(_id: int) -> Dictionary: return {"info": {"maxHP": 1}})
	assert_eq(s.equipment_info[1040002].incPDD, 3.0, "canonical equipment info, untouched")
	assert_true(s.equipment_info.has(1302000) and s.equipment_info.has(1372005), "both starter weapons")
	assert_eq(s.mob_skill_img["126"].level["1"].time, 10.0, "boss skill levels, untouched")
	assert_eq(s.body_img.info.incPDD, 1.0, "body root reaches the sim untouched")
	assert_eq(s.afterimage_imgs.swordOL.info.incPDD, 1.0, "afterimage root reaches the sim untouched")
	assert_eq(s.afterimage_imgs.keys(), ["swordOL"], "only the afterimages the worn weapons name are loaded")


func test_monster_damage_has_no_hidden_balance_scales() -> void:
	assert_false(data.balance.has("touch_damage"), "the owner-provided formula replaces hidden touch tuning")
	for stage: String in data.stages.stages:
		for keyframe: Dictionary in data.stages.stages[stage].keyframes:
			assert_false(keyframe.has("damage"), "%s damage belongs to the monster, not run time" % stage)
		assert_true(float(data.stages.stages[stage].elites.damage_mult) > 1.0, "explicit elite danger")


func test_setup_carries_canonical_potion_specs() -> void:
	var asked: Array = []
	var loader := func(path: String) -> Dictionary:
		asked.append(path)
		if path == "Item.wz/Consume/0200.img" or path == "Item.wz/Consume/0202.img":
			# Every potion entry of the img, its spec marked with its own id so the routing is visible.
			var items := {}
			for id in DataRepo.potion_item_ids(data):
				if DataRepo.potion_img_path(id) == path:
					items["%08d" % id] = {"spec": {"hp": float(id)}, "info": {"price": 25.0}}
			return items
		return {"info": {}}
	var setup := DataRepo.build_setup(data, "henesys", 10, Vector2(800, 600), loader,
		func(_id: int) -> Dictionary: return {"info": {"maxHP": 1}})
	assert_eq(setup.get("item_info", {}).get(2000000, {}).get("spec", {}).get("hp", -1), 2000000.0,
		"canonical potion spec reaches the pure simulation")
	assert_eq(DataRepo.potion_item_ids(data), PackedInt32Array([2000000, 2000001, 2000002, 2001001, 2022003]),
		"the starter and the potions.schedule items: Red, Orange, White, Ice Cream Pop, Unagi (no MP potions, #285)")
	assert_eq(setup.get("item_info", {}).keys(), Array(DataRepo.potion_item_ids(data)), "every scheduled potion is retained")
	assert_eq(setup.item_info[2022003].spec.hp, 2022003.0, "Unagi comes from Consume/0202.img")
	assert_eq(setup.item_info[2001001].spec.hp, 2001001.0, "Ice Cream Pop comes from Consume/0200.img")
	assert_eq(asked.count("Item.wz/Consume/0202.img"), 1, "each potion img is read once")
	assert_eq(asked.count("Item.wz/Consume/0200.img"), 1)
	assert_eq(DataRepo.potion_img_path(2022000), "Item.wz/Consume/0202.img")
	assert_eq(DataRepo.potion_img_path(2000002), "Item.wz/Consume/0200.img")
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var sounds := []
	for entry: Dictionary in manifest.imgs:
		if String(entry.img) == "Sound.wz/Item.img":
			sounds.append_array(entry.get("paths", []))
	for id in DataRepo.potion_item_ids(data):
		assert_true(float(id) in manifest.items, "potion %d imported" % id)
		assert_true(("%08d/Use" % id) in sounds, "potion %d has its Use sound in the manifest" % id)


func test_boss_summon_and_revive_ids_come_from_canonical_data_not_stages_json() -> void:
	for key: String in data.stages.stages:
		for boss: Dictionary in DataRepo.stage_bosses(data.stages.stages[key]):
			assert_false(boss.has("summon_ids") or boss.has("revive_ids"),
				"%s boss %d: summon/revive lists are v83 data" % [key, int(boss.mob_id)])
	var stage := {"keyframes": [{"t": 0, "pool": {"100100": 1}}],
		"maps": [{"map_id": 100000000, "boss": {"mob_id": 7000000}},
			{"map_id": 100000001, "boss": {"mob_id": 7000001}}]}
	var mob_skill := {"200": {"level": {"5": {"0": 8000000.0, "1": 8000000.0, "2": 8000001.0, "interval": 40.0,
		"hp": 50.0, "limit": 5.0, "summonEffect": 2.0}, "6": {"0": 8000009.0}}}}
	var imgs := {
		7000000: {"info": {"skill": {"0": {"skill": 126.0, "level": 6.0}, "1": {"skill": 200.0, "level": 5.0}}}},
		"7000001": {"info": {"revive": {"0": 8000002.0, "1": 8000002.0}}},
		8000000: {"info": {"revive": {"0": 8000003.0}}},
	}
	assert_eq(StageRoster.named_ids(stage), PackedInt32Array([100100, 7000000, 7000001]))
	assert_eq(StageRoster.boss_extra_ids(imgs[7000000], mob_skill), PackedInt32Array([8000000, 8000001]),
		"only the levels the boss lists, integer keys only")
	assert_eq(StageRoster.mob_ids(stage, imgs, mob_skill),
		PackedInt32Array([100100, 7000000, 7000001, 8000000, 8000001, 8000002]),
		"bosses' summons and revives; an ordinary mob's own revive list is not followed")
	assert_eq(StageRoster.mob_ids(stage, {}, mob_skill), StageRoster.named_ids(stage), "no imgs: the named ids")
	data.stages.stages["roster"] = stage
	var asked: Array[int] = []
	var setup := DataRepo.build_setup(data, "roster", 1, Vector2(800, 600),
		func(p: String) -> Dictionary: return mob_skill if p == DataRepo.MOB_SKILL_IMG else {"info": {}},
		func(id: int) -> Dictionary:
			asked.append(id)
			return imgs.get(id, imgs.get(str(id), {"info": {"maxHP": 1.0}})))
	data.stages.stages.erase("roster")
	asked.sort()
	assert_eq(asked, [100100, 7000000, 7000001, 8000000, 8000001, 8000002] as Array[int],
		"build_setup loads each derived id once")
	assert_true(setup.mob_imgs.has(8000001) and setup.mob_imgs.has(8000002))


func test_real_boss_imgs_supply_their_summon_and_revive_families() -> void:
	if not require_cache():
		return
	var root := AssetCachePaths.resolve_cache_root()
	var load_json := func(p: String) -> Dictionary:
		var file := root.path_join(p + ".json")
		if not FileAccess.file_exists(file):
			return {}
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
		return v if v is Dictionary else {}
	var mob_skill: Dictionary = load_json.call(DataRepo.MOB_SKILL_IMG)
	assert_eq(StageRoster.boss_extra_ids(load_json.call("Mob.wz/2220000.img"), mob_skill),
		PackedInt32Array([100100, 100101, 130101]), "Mano's MobSkill 200/78 summons")
	assert_eq(StageRoster.boss_extra_ids(load_json.call("Mob.wz/9300003.img"), mob_skill),
		PackedInt32Array([210100]), "King Slime's MobSkill 200/2 summons and eleven-entry revive list")
	for id: int in [6130101, 9400205, 3220000, 6220000]:
		assert_eq(StageRoster.boss_extra_ids(load_json.call("Mob.wz/%07d.img" % id), mob_skill).size(), 0,
			"boss %d summons and revives nothing" % id)


## Active skills without a hit-more-mobs card (docs/GAME_DESIGN.md card rules), each with the reason it is exempt.
const HIT_MORE_EXEMPT := {
	"heal": "support: heals the player; its undead strike hits every undead in the box already",
	"slow_fp": "support: slows, deals no damage",
	"slow_il": "support: slows, deals no damage",
	"teleport_fp": "movement: deals no damage",
	"teleport_il": "movement: deals no damage",
	"teleport_cleric": "movement: deals no damage",
	"dash": "movement buff: deals no damage",
	"threaten": "support: threatens, deals no damage",
	"disorder": "support: threatens and interrupts, deals no damage",
}


## Manual skills and skill keys (#188): every manual skill names a known skill key with an input action, and only
## manual skills have one.
func test_manual_skills_name_a_skill_key_with_an_input_action() -> void:
	var skills: Dictionary = data.skills.skills
	for key: String in skills:
		var s: Dictionary = skills[key]
		var manual := String(s.get("cast", {}).get("rule", "")) == "manual"
		assert_eq(s.has("skill_key"), manual, "%s: a skill key exactly when the cast rule is manual" % key)
		if manual:
			var id := String(s.skill_key)
			assert_true(id in KeyBindings.SKILL_KEYS, "%s: skill key %s is listed in KeyBindings.SKILL_KEYS" % [key, id])
			assert_true(InputMap.has_action(id), "%s: project.godot has an input action %s" % [key, id])
			assert_false(GameSettings.default_keys(id).is_empty(), "%s: %s has a default key" % [key, id])
	for id: String in KeyBindings.SKILL_KEYS:
		assert_true(skills.values().any(func(s: Dictionary) -> bool: return s.get("skill_key", "") == id),
			"skill key %s belongs to a skill" % id)


func test_every_attack_skill_has_a_signature_bonus_or_legacy_hit_more_card() -> void:
	var skills: Dictionary = data.skills.skills
	var covered := {}
	for c: Dictionary in data.upgrades.cards:
		if String(c.kind) != "skill_mod":
			continue
		for effect: Dictionary in c.effects:
			if String(effect.stat) in ["count", "pierce"] and float(effect.value) > 0.0:
				covered[String(c.skill)] = true
	for key: String in skills:
		var s: Dictionary = skills[key]
		if HIT_MORE_EXEMPT.has(key):
			assert_eq(String(s.damage), "none", "exempt %s must not be an attack skill" % key)
			assert_true(String(s.slot) in ["active", "mobility"], "exempt %s is active or manual mobility" % key)
			assert_false(covered.has(key), "%s has a hit-more-mobs card: remove its exemption" % key)
			continue
		if s.has("rarity_bonuses"):
			for tier: String in ["rare", "epic", "unique", "legendary"]:
				var entries: Array = s.rarity_bonuses.get(tier, [])
				assert_false(entries.is_empty(), "%s needs %s rarity bonuses" % [key, tier])
				for entry: Dictionary in entries:
					assert_false(entry.get("effects", []).is_empty(), "%s bonus has effects" % key)
			assert_false(covered.has(key), "%s uses rarity bonuses instead of standalone cards" % key)
			continue
		assert_false(key in data.jobs_survivor.jobs["212"].skill_pool, "%s is a pool skill and needs rarity_bonuses (#288)" % key)
		if int(s.get("job", -1)) == 0:
			continue # #284: the Beginner is gone and its skills have no cards
		if String(s.slot) == "mobility":
			continue # a mobility skill is never offered as a card (Rush, #302)
		if String(s.damage) != "none" or String(s.slot) == "active":
			assert_true(covered.has(key), "%s needs a skill_mod card with more shots, targets or pierce" % key)


func test_every_derived_stage_mob_is_in_the_asset_manifest() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var manifest: Variant = AssetManifest.load_merged("res://data/asset_manifest.json")
	var mob_skill := lib.img(DataRepo.MOB_SKILL_IMG).root
	for key: String in data.stages.tiers[0]:
		var stage: Dictionary = data.stages.stages[key]
		var imgs := {}
		for id in StageRoster.named_ids(stage):
			imgs[id] = lib.mob_root(id)
		for id in StageRoster.mob_ids(stage, imgs, mob_skill):
			assert_true(float(id) in manifest.mobs, "%s: derived mob %d in the asset manifest" % [key, id])
	lib.free()


func test_stage_keyframe_parser_ignores_retired_potion_curve() -> void:
	var stage := {"keyframes": [{"t": 0, "rate": 1, "max_alive": 3, "normal_hp_drop_chance": 0.5}]}
	var director := SpawnDirector.create(stage, {})
	assert_false(director.keyframes[0].has("normal_hp_drop_chance"), "retired potion curves are not parsed")
	assert_near(director.rate_at(0.0), 1.0, 1e-6, "supported pacing fields are still parsed")

func test_meter_catalog_schema() -> void:
	for job: Dictionary in data.jobs_survivor.jobs.values():
		if not job.has("meter"):
			continue
		var meter: Dictionary = job.meter
		assert_true(meter.id is String and not String(meter.id).is_empty())
		assert_true(float(meter.max) > 0 and float(meter.max) == floorf(float(meter.max)))
		assert_true(String(meter.gain.event) in ["cast_landed", "hit_taken", "meso_picked"])
		assert_true(float(meter.gain.amount) > 0 and float(meter.gain.amount) == floorf(float(meter.gain.amount)))
		assert_true(String(meter.gain.get("exclude", "")) in ["", "finisher"])
		assert_eq(String(meter.per_unit.stat), "damage")
		assert_true(float(meter.per_unit.value) >= 0.0)
		assert_true(meter.get("art", "") is String)
	for skill: Dictionary in data.skills.skills.values():
		if not skill.has("meter"):
			continue
		var meter: Dictionary = skill.meter
		assert_eq(String(meter.role), "finisher")
		assert_true(float(meter.min) > 0 and float(meter.min) == floorf(float(meter.min)))
		assert_eq(String(meter.spend), "all")
		assert_true(float(meter.damage_per_unit) >= 0.0)
		assert_eq(String(skill.slot), "active")
