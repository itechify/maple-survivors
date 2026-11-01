extends TestCase
## The Ludibrium Clocktower region (spec #449 C10, ticket #472, progression step 15; tier C rules in docs/GAME_DESIGN.md
## "Ludibrium Clocktower (C10) constants"): `stages/clocktower.json`, its manifest fragment and `mobs.json` entries,
## Sleepywood's curve numbers, the level scale, explicit pools of the Path of Time's ordinary monsters and the three bosses
## (Gatekeeper, Thanatos, Papulatus clock into its flying form). Parts that read canonical data (pool mobs, the bosses'
## skills, summons) are cache-backed and SKIP without the asset cache.

const CAL := preload("res://tests/calibrated_levels.gd")
const RC := preload("res://tests/region_checks.gd")
const KEY := "clocktower"
const MAPS := [220060400, 220070400, 220080000]
const BOSSES := [8160000, 8170000, 8500001]
const FINAL_FORM := 8500002
## The clock's MobSkill 200/39 and 200/40 summons: High and Low Darkstar (both present in v83, no ABSENT_IN_V83 entry). Their
## Mob.wz `selfDestruction` is not modelled: they stay until killed, so the stage bounds the summons with `skill_intervals`.
const DARKSTARS := [8500003, 8500004]
## Ordinary mobs by map: Ghost Pirate (Lv83), Death Teddy (85), Dual Ghost Pirate (87); Master Death Teddy (89), Spirit
## Viking (93), Phantom Watch (95); Gigantic Spirit Viking (98), Grim Phantom Watch (99).
const POOL_LEVELS := {7140000: 83, 7130010: 85, 7160000: 87, 7130300: 89, 8141000: 93, 8142000: 95, 8141100: 98, 8143000: 99}
## The Etc drops used as EXP pickups, by mob (Papulatus's four entries share its Certificate).
const EXP_ITEMS := {7140000: 4000132, 7130010: 4000147, 7160000: 4000133, 7130300: 4000148, 8141000: 4000134,
	8142000: 4000149, 8141100: 4000135, 8143000: 4000150, 8160000: 4000151, 8170000: 4000152, 8500001: 4001084,
	8500002: 4001084, 8500003: 4001084, 8500004: 4001084}
## The attack stances each boss schedules. The clock's attack3 (attackAfter 0, a +-800 px instant strike) is not scheduled.
const ATTACKS := [["attack1", "attack2"], ["attack1"], ["attack1", "attack2", "attack4"]]
## MobSkill ids per boss in the v83 data (sorted). Thanatos's Seal 120 is the one skipped id.
const SKILLS := [[123], [120, 121, 124, 125], [114, 123, 126, 127, 200, 200]]

var data: Dictionary
var stage: Dictionary


func before_each() -> void:
	data = DataRepo.load_all()
	stage = data.stages.stages.get(KEY, {})


func test_the_stage_is_in_the_progression_with_the_clocktower_fields() -> void:
	var progression: Array = data.stages.progression
	assert_true(progression.has(KEY), "listed in the progression")
	assert_eq(RC.neighbours(progression, KEY), ["phantom_forest", "temple_of_time"], "step 15 sits between phantom_forest and temple_of_time")
	assert_eq(String(stage.get("region", "")), "Ludibrium Clocktower")
	assert_eq(String(stage.get("continent", "")), "Ossyria", "String.wz group ossyria")
	assert_eq(stage.get("drop_band"), [100.0, 110.0], "#447's drop band")
	assert_true(String(stage.get("note", "")).contains("Papulatus"), "the note names the bosses")
	assert_eq(stage.get("original_life"), {"8160000": 2.0}, "map 1's own spawn list: the two Gatekeepers")
	assert_eq(DataRepo.stage_label_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.progression_errors(data.stages), PackedStringArray())
	assert_eq(DataRepo.stage_map_errors(data.stages), PackedStringArray())


func test_three_maps_with_explicit_pools_of_the_path_of_times_monsters() -> void:
	assert_eq(stage.get("map_seconds"), 300)
	var maps: Array = stage.get("maps", [])
	assert_eq(maps.size(), 3)
	for i in maps.size():
		assert_eq(int(maps[i].map_id), MAPS[i], "map %d" % (i + 1))
		assert_false(maps[i].has("opening_ramp"), "map %d: level_scale replaces the opening ramp" % (i + 1))
		assert_false(maps[i].has("pool_from_life"), "map %d: the passages' life lists are only bosses" % (i + 1))
		assert_false(maps[i].has("exclude"), "map %d lists no pool ids to exclude" % (i + 1))
	assert_eq(maps[0].pool, "curve", "map 1 is a hand-written curve pool")
	assert_eq(maps[1].pool, {"7130300": 15.0, "8141000": 14.0, "8142000": 26.0}, "Master Death Teddy, Spirit Viking, Phantom Watch")
	assert_eq(maps[2].pool, {"8141100": 26.0, "8143000": 14.0}, "Gigantic Spirit Viking, Grim Phantom Watch")
	var note := String(stage.get("_maps", ""))
	assert_true(note.contains("2995") and note.contains("4143"), "the map note records the passage widths")
	assert_true(note.contains("2265"), "the map note records the rejected towers")


func test_the_bosses_are_in_no_pool() -> void:
	for boss: int in BOSSES + [FINAL_FORM]:
		for kf: Dictionary in stage.keyframes:
			assert_false(kf.get("pool", {}).has(str(boss)), "%d is in no keyframe pool" % boss)
		for entry: Dictionary in stage.maps:
			if entry.pool is Dictionary:
				assert_false(entry.pool.has(str(boss)), "%d is in no explicit pool" % boss)
	for id: int in DataRepo.stage_mob_ids(data, KEY):
		assert_true(EXP_ITEMS.has(id) and (POOL_LEVELS.has(id) or id in BOSSES + [FINAL_FORM] + DARKSTARS),
			"stage mob %d is a known Clocktower mob" % id)


func test_map_one_keyframe_pools_rise_from_ghost_pirate_to_dual_ghost_pirate() -> void:
	var pooled := 0
	for kf: Dictionary in stage.keyframes:
		if not kf.has("pool"):
			assert_true(float(kf.t) >= 120.0, "only keyframes from 300 s on carry no pool")
			continue
		pooled += 1
		assert_true(float(kf.t) < 300.0, "map 1 reads keyframes below 300 s")
		for key: String in kf.pool:
			assert_has([7140000, 7130010, 7160000], int(key), "%s is a lower Path of Time mob" % key)
	assert_eq(pooled, 2)
	assert_eq(stage.keyframes[0].pool, {"7140000": 3.0, "7130010": 2.0}, "the two weaker mobs open")
	assert_eq(stage.keyframes[1].pool, {"7140000": 2.0, "7130010": 2.0, "7160000": 2.0}, "the Dual Ghost Pirate joins at 120 s")
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


func test_level_scale_is_present_valid_and_thirty_levels_above_sleepywoods_pace() -> void:
	assert_true(stage.has("level_scale"), "level_scale")
	assert_eq(LevelScale.block_errors(KEY, stage.get("level_scale")), PackedStringArray())
	assert_eq(LevelScale.stage_errors(data.stages.stages), PackedStringArray(), "no stage has both a scale and a ramp")
	var kfs: Array = stage.level_scale.keyframes
	assert_eq(kfs.size(), stage.keyframes.size(), "one level per pacing keyframe")
	for i in kfs.size():
		assert_eq(float(kfs[i].t), float(stage.keyframes[i].t), "keyframe %d at the pacing time" % i)
		assert_near(float(kfs[i].level), CAL.level_at(float(kfs[i].exp_level), float(kfs[i].t), 15), 0.011,
			"step 15: the calibrated level (C13): 1 at 0:00 rising to Sleepywood's pace + CAL.ABOVE at 10:00, keyframe %d" % i)
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
		assert_eq(int(boss.attack_interval), 8)
		for field: String in ["hp_mult", "dmg_mult", "attack_dmg_mult"]:
			assert_true(float(boss.get(field, 0.0)) > 0.0, "%d %s" % [BOSSES[i], field])
		assert_true(String(boss.get("_tier", "")).begins_with("tier C"), "%d has a tier C note" % BOSSES[i])
		assert_has(data.balance.mob_skills.enabled_ids, float(BOSSES[i]), "%d casts its kit" % BOSSES[i])
	assert_false(bosses[0].has("final_form") or bosses[1].has("final_form"), "only Papulatus has a final form")
	assert_eq(int(bosses[2].final_form), FINAL_FORM, "the clock revives into the flying form")
	assert_true(float(bosses[2].final_form_hp_mult) > 0.0, "final_form_hp_mult")
	assert_has(data.balance.mob_skills.enabled_ids, float(FINAL_FORM), "the flying form is enabled")
	# Tier C fairness floors on the clock: heal 114/4 (WZ 30,000 every 1 s) every 15 s, both Darkstar summons (WZ every 1 s,
	# four mobs a cast, selfDestruction not modelled so they stay until killed) every 8 s; skill ids key both summon levels.
	assert_eq(bosses[2].skill_intervals, {"114": 15.0, "200": 8.0}, "the clock's heal and summon intervals")
	assert_true(String(bosses[2]._tier).contains("skill_intervals") and String(bosses[2]._tier).contains("attack3 is NOT scheduled"),
		"the tier note records the intervals and the dropped attack3")
	assert_false(bosses[0].has("skill_intervals") or bosses[1].has("skill_intervals"), "only the clock needs intervals")
	# The draft tool's numbers (--step=15 --stage=clocktower), pinned so a retune is a visible change.
	assert_eq([float(bosses[0].hp_mult), float(bosses[1].hp_mult), float(bosses[2].hp_mult)], [521.119, 130.256, 0.453])
	assert_eq([float(bosses[0].dmg_mult), float(bosses[1].dmg_mult), float(bosses[2].dmg_mult)], [1.064, 0.822, 1.594])
	assert_eq([float(bosses[0].attack_dmg_mult), float(bosses[1].attack_dmg_mult), float(bosses[2].attack_dmg_mult)],
		[1.171, 0.834, 2.784])
	assert_eq(float(bosses[2].final_form_hp_mult), 6.554)


func test_the_clocks_lockout_floors_cover_its_stun_and_dispel() -> void:
	# Stun 123/4 has interval 1 and Dispel 127/1 interval 1: B1's default floor and B6's 20 s floor bound them.
	var lockout: Dictionary = data.balance.mob_skills.status_lockout
	assert_true(float(lockout.default) >= 4.0, "a default re-apply floor")
	assert_eq(float(lockout.get("127", 0.0)), 20.0, "Dispel's floor")
	for skill: int in [114, 123, 124, 125, 126, 127, 121, 200]:
		assert_true(skill in MobSkillRunner.SUPPORTED, "MobSkill %d is supported" % skill)
	assert_false(120 in MobSkillRunner.SUPPORTED, "Seal 120 is the one skipped id")


func test_every_mob_has_an_exp_item_that_the_manifest_imports() -> void:
	var manifest: Dictionary = AssetManifest.load_merged("res://data/asset_manifest.json")
	var fragment: Dictionary = DataRepo.load_json("res://data/asset_manifest.d/region_clocktower.json")
	for map_id: int in MAPS:
		assert_has(fragment.maps, float(map_id), "the fragment imports map %d" % map_id)
		assert_has(manifest.maps, float(map_id), "the merged manifest has map %d" % map_id)
	for id: int in EXP_ITEMS:
		var mob: Dictionary = data.mobs.mobs.get(str(id), {})
		assert_false(String(mob.get("name", "")).is_empty(), "mob %d has an English fallback name" % id)
		assert_eq(int(mob.get("exp_item", 0)), EXP_ITEMS[id], "mob %d EXP item" % id)
		assert_true(String(mob.get("_exp_item", "")).length() > 20, "mob %d EXP item provenance" % id)
		assert_has(fragment.mobs, float(id), "the fragment imports mob %d" % id)
		assert_has(manifest.mobs, float(id), "the merged manifest has mob %d" % id)
		assert_has(manifest.items, float(EXP_ITEMS[id]), "EXP art %d is imported" % EXP_ITEMS[id])
	assert_eq(String(data.mobs.mobs["8500001"].name), String(data.mobs.mobs["8500002"].name), "the clock and its form are one boss")
	# Ordinary mobs: the Lv70 Tauromacis (420) to Lv75 Taurospear (504) slope, 16.8 per level, +-20% (Ludibrium's method).
	for id: int in POOL_LEVELS:
		var centre := roundi(420.0 + 16.8 * float(POOL_LEVELS[id] - 70))
		var mesos: Array = data.mobs.mobs[str(id)].get("mesos", [])
		assert_eq(mesos.size(), 2, "mob %d meso range" % id)
		assert_eq([int(mesos[0]), int(mesos[1])], [roundi(centre * 0.8), roundi(centre * 1.2)], "mob %d range" % id)
		assert_true(data.mobs.mobs[str(id)].has("_mesos"), "mob %d meso range is a tier C note" % id)
	for id: int in BOSSES + [FINAL_FORM] + DARKSTARS:
		assert_false(data.mobs.mobs[str(id)].has("mesos"), "boss or summon %d uses the level fallback" % id)
		assert_false(data.mobs.mobs[str(id)].has("banish_message"), "%d casts no Banish" % id)
	for id: int in [8160000, 8170000]:
		assert_eq(int(data.mobs.mobs[str(id)].boss_ui.icon_id), 6220001, "%d is not boss-flagged: it borrows Zeno's gauge icon" % id)
	for id: int in [8500001, 8500002]:
		assert_false(data.mobs.mobs[str(id)].has("boss_ui"), "%d: its MobGage icon and hpTag are canonical" % id)
	var last := -1
	for key: String in data.mobs.mobs.keys():
		if EXP_ITEMS.has(int(key)):
			assert_true(int(key) > last, "%s inserted in id order" % key)
			last = int(key)


func test_pools_resolve_to_real_monsters_that_pay_close_to_the_level_curves_exp() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var curve: Array = DataRepo.load_json("res://data/survivor/level_curve.json").exp
	var pool_want := [{}, {7130300: 15.0, 8141000: 14.0, 8142000: 26.0}, {8141100: 26.0, 8143000: 14.0}]
	for i in MAPS.size():
		var img := lib.img(DataRepo.map_img_path(MAPS[i]))
		if img == null:
			skip("map img not imported: %d" % MAPS[i])
			lib.free()
			return
		if i > 0:
			assert_eq(StagePools.resolve(stage.maps[i], img.root), pool_want[i], "map %d pool" % (i + 1))
		# The passages' own life lists are only the bosses (the reason for the explicit pools).
		var life := StagePools.resolve({"pool_from_life": true}, img.root)
		for id: int in life:
			assert_true(id in BOSSES, "map %d's v83 life holds only a boss, got %d" % [i + 1, id])
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
		var ratio := float(info.exp) / float(curve[int(info.level) - 1])
		assert_between(ratio, 0.7, 1.3, "mob %d EXP is %.2fx the level-%d curve" % [id, ratio, int(info.level)])
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
		var listed: Array = []
		for entry: Dictionary in info.get("skill", {}).values():
			var skill := int(entry.skill)
			listed.append(skill)
			if skill != 120:
				assert_true(skill in MobSkillRunner.SUPPORTED, "boss %d lists MobSkill %d: supported" % [id, skill])
			assert_true(table.root.has(str(skill)), "MobSkill.img has %d" % skill)
			assert_false(table.root[str(skill)].level.get(str(int(entry.level)), {}).is_empty(),
				"boss %d skill %d level %d is in MobSkill.img" % [id, skill, int(entry.level)])
		listed.sort()
		assert_eq(listed, SKILLS[i], "boss %d's v83 kit" % id)
		for attack: String in ATTACKS[i]:
			assert_true(img.root.has(attack), "%d has %s" % [id, attack])
			assert_true(int(img.root[attack].info.type) in [0, 1, 2, 3], "%d %s is a supported attack type" % [id, attack])
	# Thanatos's attack1 is the type-3 area-warning attack (B5): nine columns, five struck per cast.
	var thanatos := lib.img("Mob.wz/8170000.img").root
	assert_eq(int(thanatos.attack1.info.type), 3)
	assert_true(thanatos.attack1.info.has("areaWarning"), "the warning art")
	assert_eq(int(thanatos.attack1.info.range.areaCount), 9)
	assert_eq(int(thanatos.attack1.info.range.attackCount), 5)
	# The clock revives into the flying form, which has no attack stance and fights by touch.
	var clock := lib.img("Mob.wz/8500001.img").root
	assert_eq(clock.info.revive.values().map(func(v: Variant) -> int: return int(v)), [FINAL_FORM], "the clock revives into Papulatus")
	# attack3 is the unscheduled one: attackAfter 0 and a +-800 px box, an instant unwarned strike without its effect0 strikes.
	assert_eq(float(clock.attack3.info.get("attackAfter", -1)), 0.0, "attack3 hits at once")
	assert_true(clock.attack3.has("effect0") or clock.attack3.info.has("effect0"), "attack3's effect0 secondary strikes are the unmodelled part")
	assert_eq(float(clock.attack1.info.get("deadlyAttack", 0)), 1.0, "attack1's deadlyAttack flag is not modelled")
	assert_eq(float(clock.attack1.info.get("doFirst", 0)), 1.0, "attack1's doFirst flag is not modelled")
	var form := lib.img("Mob.wz/8500002.img").root
	assert_true(form.has("fly"), "the final form has a fly stance")
	assert_false(form.has("attack1"), "the final form has no attack stance: contact only")
	assert_true(clock.has("move") and not clock.has("fly"), "the clock walks")
	# The clock's two Summon levels name the Low and High Darkstar, both in v83.
	var extras := StageRoster.boss_extra_ids(clock, table.root)
	assert_eq(Array(extras), [FINAL_FORM] + DARKSTARS, "the revive form and the High and Low Darkstar")
	for extra in extras:
		assert_true(lib.img("Mob.wz/%07d.img" % extra) != null, "Mob.wz holds the summon %d" % extra)
		assert_false(extra in StageRoster.ABSENT_IN_V83, "%d is not on the absent list" % extra)
	for darkstar: int in DARKSTARS:
		# Mob.wz gives them a selfDestruction (hp 5000), which the sim does not model: they stay until killed.
		var self_destruct: Variant = lib.img("Mob.wz/%07d.img" % darkstar).root.info.get("selfDestruction", {})
		assert_true(self_destruct is Dictionary and int(self_destruct.get("hp", 0)) > 0, "%d has a selfDestruction in Mob.wz" % darkstar)
	# Gatekeeper and Thanatos summon nothing.
	for id: int in [8160000, 8170000]:
		assert_eq(StageRoster.boss_extra_ids(lib.img("Mob.wz/%d.img" % id).root, table.root), PackedInt32Array(), "%d summons nothing" % id)
	lib.free()
