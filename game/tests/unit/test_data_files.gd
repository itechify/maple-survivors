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
	for key: String in ["skills", "upgrades", "stages", "balance", "mobs", "equipment_drops", "jobs_survivor", "scrolls", "shops", "jobs", "exp_table", "cash_items"]:
		assert_true(d.has(key) and not d[key].is_empty(), "setup.data.%s" % key)
	var bad := PackedStringArray()
	assert_true(DataRepo.load_all("res://no_such_dir", bad).skills.is_empty())
	assert_eq(bad.size(), 12, "every missing file reported")


func test_skills_reference_canonical_ids() -> void:
	var skills: Dictionary = data.skills.skills
	var want := {"three_snails": 1000, "energy_bolt": 2001004, "magic_claw": 2001005, "magic_guard": 2001002,
		"magic_armor": 2001003, "recovery": 1001, "improved_max_mp": 2000001, "nimble_feet": 1002}
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
		var top := book.max_level(key)
		assert_true(top > 0, "%s has a canonical level table" % key)
		assert_eq(book.max_rank(key), top, "%s: one rank per canonical level" % key)
		var ranks: Array = book.def(key).ranks
		for level in range(1, top + 1):
			if level <= ranks.size():
				assert_eq(int(ranks[level - 1]), level, "%s rank %d is canonical level %d" % [key, level, level])


func test_cards_are_consistent() -> void:
	var skills: Dictionary = data.skills.skills
	var ids := {}
	var kinds := ["skill_new", "skill_rank", "skill_mod", "passive", "stat", "potion_tier"]
	for c: Dictionary in data.upgrades.cards:
		assert_false(ids.has(c.id), "unique id %s" % c.id)
		ids[c.id] = true
		assert_true(String(c.kind) in kinds, "%s kind" % c.id)
		for k: String in ["id", "kind", "skill", "icon", "name", "desc", "max_rank", "weight", "requires", "effects"]:
			assert_true(c.has(k), "%s has %s" % [c.id, k])
		if String(c.kind).begins_with("skill_"):
			assert_true(skills.has(String(c.skill)), "%s: skill %s exists" % [c.id, c.skill])
		if c.kind == "skill_rank":
			assert_eq(int(c.max_rank), skills[c.skill].ranks.size(), "%s: max_rank is the canonical level cap" % c.id)
			assert_eq(c.effects, [{"stat": "rank", "op": "add", "value": 1.0}], "%s: one level per card" % c.id)
		for effect: Dictionary in c.effects:
			assert_false(effect.op == "heal", "%s cannot heal by percentage" % c.id)
			assert_false(effect.stat == "hp_regen", "%s cannot grant the removed passive Recovery regen" % c.id)
		if c.kind == "potion_tier":
			assert_true(c.potion_kind in ["hp", "mp"])
			var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/asset_manifest.json"))
			assert_has(manifest.items.map(func(id: Variant) -> int: return int(id)), int(c.item_id), "%s target is imported" % c.id)
			assert_true(c.requires.potions.has(c.potion_kind), "tier requires its predecessor")
		if "{value}" in String(c.desc):
			assert_true(c.has("value"), "%s fills {value}" % c.id)
	for id: String in ["three_snails_count", "three_snails_cooldown", "three_snails_pierce",
			"three_snails_speed", "energy_bolt_new", "magic_claw_new", "magic_guard_new", "magic_armor_new",
			"nimble_feet", "recovery", "improved_max_mp", "improved_mp_recovery", "magnet"]:
		assert_true(ids.has(id), "card %s" % id)
	var fallback: Dictionary = data.upgrades.fallback
	assert_false(ids.has(fallback.id), "fallback is outside the weighted pool")
	assert_eq(fallback.kind, "filler")
	assert_eq(fallback.requires, {}, "fallback is job-neutral")
	assert_eq(int(fallback.max_rank), 0, "healing can be taken again on a later reward")
	assert_eq(fallback.effects, [{"stat": "hp", "op": "heal", "value": 1.0},
		{"stat": "mp", "op": "heal", "value": 1.0}], "Power Elixir fully restores both pools")
	var manifest: Dictionary = DataRepo.load_json("res://data/asset_manifest.json")
	assert_has(manifest.items, 2000005.0, "Power Elixir art is imported")


func test_stat_cards_are_replaced_by_owned_skills() -> void:
	var pool := UpgradePool.from_data(data.upgrades)
	assert_true(pool.card("max_hp").is_empty(), "the non-MapleStory Max HP card is removed")
	for key: String in ["improved_max_mp", "nimble_feet"]:
		assert_eq(pool.card(key).kind, "skill_new", "%s learns its skill" % key)
		assert_eq(pool.card(key).skill, key)
		assert_eq(pool.card(key).effects, [], "no flat stat effects remain")
		assert_eq(pool.card(key + "_rank").kind, "skill_rank")
		var is_mp := key == "improved_max_mp"
		assert_eq(int(pool.card(key + "_rank").max_rank), 10 if is_mp else 3)
		assert_eq(pool.card(key).requires.jobs, [200.0] if is_mp else [0.0])
		assert_eq(pool.card(key + "_rank").requires.jobs, [200.0] if is_mp else [0.0])


func test_stages_mobs_and_manifest() -> void:
	var stages: Dictionary = data.stages.stages
	var mobs: Dictionary = data.mobs.mobs
	var manifest: Variant = DataRepo.load_json("res://data/asset_manifest.json")
	assert_true(manifest is Dictionary)
	var want_maps := {"henesys_hg1": 104040000, "tree_that_grew_1": 101010100, "dark_cave": 105050400}
	assert_eq(stages.keys(), want_maps.keys(), "the three distinct stages are offered")
	assert_eq(manifest.maps, [104040000.0, 101010100.0, 105050400.0, 910000000.0],
		"the three stages and the Free Market hub are imported")
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


func test_henesys_boss_order_and_slam_data() -> void:
	var entries: Array = data.stages.stages.henesys_hg1.bosses
	assert_eq(entries.map(func(e: Dictionary) -> int: return int(e.mob_id)), [2220000, 6130101, 9400205])
	assert_eq(entries.map(func(e: Dictionary) -> int: return int(e.time)), [300, 600, 900])
	assert_eq(entries[1].attacks, ["attack1"])
	assert_eq(entries[2].attacks, ["attack1"])
	assert_eq(data.mobs.mobs["9400205"].boss_ui.icon_id, 6130101)


func test_jobs_and_balance() -> void:
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for k: String in data.jobs_survivor.jobs:
		assert_false(tree.job(int(k)).is_empty(), "survivor job %s exists in the canonical tree" % k)
	assert_true(tree.job(200).playable)
	for id: int in [210, 220, 230]:
		assert_true(tree.job(id).playable, "%d playable" % id)
	for id: int in [100, 300, 400, 500]:
		assert_false(tree.job(id).playable, "%d not playable" % id)
	var b: Dictionary = data.balance
	assert_false(b.has("invincible_time"), "replaced by the shrinking hit_window (spec #88)")
	assert_eq(b.hit_window, {"lengths": [1.5, 1.0, 0.6, 0.4], "chain_gap": 2.5, "reset_after": 3.0})
	assert_eq(float(b.magnet_radius), 90.0)
	assert_eq(float(b.mob_speed_factor), 0.625)
	assert_eq(float(b.knockback.speed), 187.5)
	assert_eq(float(b.mp_regen), 0.0, "no per-second MP recovery")
	assert_eq(b.regen, {"interval": 10.0, "hp": 10.0, "mp": 3.0, "improved_mp_divisor": 10.0})
	assert_eq(float(b.level_up_refill.hp), 0.0, "level-ups add no HP (owner choice)")
	assert_eq(float(b.level_up_refill.mp), 1.0, "level-ups refill MP to the new maximum")
	assert_eq(float(b.potions.drops.normal.mp), 0.03, "normal mobs drop a Blue 3% of the time")
	for key: String in data.stages.stages:
		for kf: Dictionary in data.stages.stages[key].get("keyframes", []):
			assert_false(kf.has("normal_mp_drop_chance"), "%s has no map-specific normal MP chance" % key)
	assert_eq(float(b.potions.drops.normal.hp), 0.012, "normal HP drops unchanged")
	assert_eq(b.potions.drops.elite, {"hp": 0.15, "mp": 0.6}, "elite drops unchanged")
	assert_eq(float(b.growth["0"].hp), 14.0)
	assert_eq(float(b.growth["200"].mp), 22.0)
	assert_eq(int(b.player.ap_per_level), 5)
	assert_eq(b.player.ap_stat, {"0": "str", "200": "int"})
	assert_eq(String(b.player.ap_secondary["200"].stat), "luk", "Magician AP keeps LUK at the v83 requirement pattern")
	assert_false(b.player.ap_secondary.has("0"), "the Beginner has no secondary stat")
	assert_eq(float(b.growth["200"].int_mp_divisor), 10.0)


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
	assert_eq(DataRepo.starter_equipment_ids(no_drops), PackedInt32Array([1040002, 1060002, 1072001, 1302000, 1372005]),
		"without MakeCharInfo the setup loads the default outfit and the granted wand")
	var with_drops := DataRepo.starter_equipment_ids(data)
	for id: Variant in data.equipment_drops.items:
		assert_true(int(id) in with_drops, "the drop list item %d has its info loaded" % int(id))
	assert_eq(with_drops.size(), 5 + data.equipment_drops.items.size() - 4, "listed items are added once (the creation coat, pants, shoes and the Wooden Wand are also listed)")


func test_build_setup_and_paths() -> void:
	assert_eq(DataRepo.map_img_path(104040000), "Map.wz/Map/Map1/104040000.img")
	assert_eq(DataRepo.map_img_path(101010100), "Map.wz/Map/Map1/101010100.img")
	assert_eq(DataRepo.map_img_path(10000), "Map.wz/Map/Map0/000010000.img")
	var mob_ids := DataRepo.stage_mob_ids(data, "henesys_hg1")
	assert_eq(mob_ids, PackedInt32Array([100100, 100101, 120100, 130101, 210100, 1110100, 1210100, 1210102,
		2220000, 2300100, 6130101, 9300062, 9300063, 9300064, 9400205]))
	var asked: Array = []
	var loader := func(p: String) -> Dictionary:
		asked.append(p)
		if p == "Item.wz/Consume/0200.img":
			var items := {}
			for id in range(2000000, 2000007):
				items["%08d" % id] = {"spec": {"hp": 50.0}}
			return items
		if p == DataRepo.SCROLL_IMG:
			var scrolls := {}
			for id: int in Scrolls.ids(data.scrolls):
				scrolls["%08d" % id] = {"info": {"success": 60.0, "incMAD": 2.0}}
			return scrolls
		return {"info": {}} if p.begins_with("Character.wz/") else {"stub": p}
	var mob_loader := func(id: int) -> Dictionary: return {} if id == 1110100 else {"info": {"id": id}}
	var missing := PackedStringArray()
	var s := DataRepo.build_setup(data, "henesys_hg1", 5, Vector2(800, 600), loader, mob_loader, missing)
	assert_eq(s.map_img, {"stub": "Map.wz/Map/Map1/104040000.img"})
	assert_eq(s.physics_img, {"stub": "Map.wz/Physics.img"})
	assert_eq(s.skill_imgs.keys().size(), DataRepo.skill_books(data).size(), "every shipped skill book is loaded")
	assert_true(s.skill_imgs.has("000") and s.skill_imgs.has("200"))
	assert_has(s.skill_imgs, "220", "Ice/Lightning Wizard book")
	assert_has(s.skill_imgs, "230", "Cleric attacks and Teleport book")
	assert_eq(s.mob_imgs.size(), mob_ids.size() - 1, "all stage kinds except the loader's missing Green Mushroom")
	assert_eq(missing, PackedStringArray(["Mob.wz/1110100.img"]))
	assert_eq(s.scroll_info.size(), Scrolls.ids(data.scrolls).size(), "every roster scroll's canonical info is loaded")
	assert_eq(s.scroll_info[2043700], {"success": 60, "incMAD": 2})
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
		if p.begins_with("Character.wz/Weapon/"):
			return {"info": {"incPDD": 1.0, "afterImage": "swordOL"}}
		return {"info": {"incPDD": 1.0}}
	var s := DataRepo.build_setup(data, "henesys_hg1", 1, Vector2(800, 600), loader,
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
	var loader := func(path: String) -> Dictionary:
		if path == "Item.wz/Consume/0200.img":
			var items := {}
			for id in range(2000000, 2000007):
				items["%08d" % id] = {"spec": {"hp": 50.0}, "info": {"price": 25.0}}
			return items
		return {"info": {}}
	var setup := DataRepo.build_setup(data, "henesys_hg1", 10, Vector2(800, 600), loader,
		func(_id: int) -> Dictionary: return {"info": {"maxHP": 1}})
	assert_eq(setup.get("item_info", {}).get(2000000, {}).get("spec", {}).get("hp", -1), 50.0,
		"canonical potion spec reaches the pure simulation")
	assert_eq(DataRepo.potion_item_ids(data), PackedInt32Array([2000000, 2000001, 2000002, 2000003, 2000006]),
		"the starters and the potion_tier ladders: Red, Orange, White, Blue, Mana Elixir")
	assert_eq(setup.get("item_info", {}).keys(), Array(DataRepo.potion_item_ids(data)), "every ladder potion is retained")
	var manifest: Dictionary = DataRepo.load_json("res://data/asset_manifest.json")
	for id in DataRepo.potion_item_ids(data):
		assert_true(float(id) in manifest.items, "potion %d imported" % id)


func test_boss_summon_and_revive_ids_come_from_canonical_data_not_stages_json() -> void:
	for key: String in data.stages.stages:
		for boss: Dictionary in data.stages.stages[key].get("bosses", []):
			assert_false(boss.has("summon_ids") or boss.has("revive_ids"),
				"%s boss %d: summon/revive lists are v83 data" % [key, int(boss.mob_id)])
	var stage := {"keyframes": [{"t": 0, "pool": {"100100": 1}}],
		"bosses": [{"mob_id": 7000000}, {"mob_id": 7000001}]}
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
	data.stages.stages["roster"] = stage.merged({"map_id": 100000000})
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
}


func test_every_attack_skill_has_a_hit_more_mobs_card() -> void:
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
			assert_eq(String(s.slot), "active", "exempt %s is an active skill" % key)
			assert_false(covered.has(key), "%s has a hit-more-mobs card: remove its exemption" % key)
			continue
		if String(s.damage) != "none" or String(s.slot) == "active":
			assert_true(covered.has(key), "%s needs a skill_mod card with more shots, targets or pierce" % key)


func test_every_derived_stage_mob_is_in_the_asset_manifest() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var manifest: Variant = DataRepo.load_json("res://data/asset_manifest.json")
	var mob_skill := lib.img(DataRepo.MOB_SKILL_IMG).root
	for key: String in ["henesys_hg1", "tree_that_grew_1"]:
		var stage: Dictionary = data.stages.stages[key]
		var imgs := {}
		for id in StageRoster.named_ids(stage):
			imgs[id] = lib.mob_root(id)
		for id in StageRoster.mob_ids(stage, imgs, mob_skill):
			assert_true(float(id) in manifest.mobs, "%s: derived mob %d in the asset manifest" % [key, id])
	lib.free()
