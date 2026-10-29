extends TestCase
## The Bishop's data seam (spec #372, ticket BS2 #374): the `bishop` data line loads and is discovered after the registered
## class lines, the job entry `survivor/jobs/bishop.json` (232, playable since BS10), its AP row and hub kit, the pool keys that are
## defined belonging to the 200/230/231/232 books, the weapon families of its equipment drops (wands and staves only;
## armour by the Magician class bit), and the Holy Symbol decision (the common EXP passive is offered to a 232 like any job).
## Seeded RNG; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")

## Synthetic items: id -> info. Magician wands and staves (the creation wand included), Magician armour, and one weapon of
## every other family a Bishop must never receive (sword, axe, bow, claw, gun, spear), a Warrior shield and all-job armour.
const INFO := {
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1040002: {"reqLevel": 30, "reqJob": 0, "incPDD": 3, "tuc": 7}, # top, all jobs
	1372005: {"reqLevel": 0, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # creation wand
	1372004: {"reqLevel": 30, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1382012: {"reqLevel": 30, "reqJob": 2, "incMAD": 45, "tuc": 7}, # staff
	1050001: {"reqLevel": 30, "reqJob": 2, "incPDD": 20, "incMDD": 12, "tuc": 10}, # Magician overall
	1302008: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed sword
	1312005: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed axe
	1432002: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # spear
	1452002: {"reqLevel": 30, "reqJob": 4, "incPAD": 47, "tuc": 7}, # bow
	1472002: {"reqLevel": 30, "reqJob": 8, "incPAD": 47, "tuc": 7}, # claw
	1492002: {"reqLevel": 30, "reqJob": 16, "incPAD": 47, "tuc": 7}, # gun
	1092002: {"reqLevel": 30, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
	# Synthetic: a sword and a claw that carry the Magician bit, so only the families filter (not the class bit) keeps them out
	1302099: {"reqLevel": 0, "reqJob": 2, "incPAD": 47, "tuc": 7}, # sword with the Magician bit (synthetic)
	1472099: {"reqLevel": 0, "reqJob": 2, "incPAD": 47, "tuc": 7}, # claw with the Magician bit (synthetic)
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]
const BISHOP_WEAPONS := [1372005, 1372004, 1382012]
const NOT_BISHOP_WEAPONS := [1302008, 1312005, 1432002, 1452002, 1472002, 1492002, 1302099, 1472099]
const POOL := ["holy_arrow", "magic_claw", "shining_ray", "angel_ray", "heal", "summon_dragon", "bahamut",
	"genesis", "big_bang_bishop", "resurrection"]


func _data() -> Dictionary:
	return DataRepo.load_all()


func _jobs(data: Dictionary) -> JobTree:
	return JobTree.from_data(data.jobs, data.jobs_survivor)


func _ids() -> Array:
	var ids := INFO.keys()
	ids.sort()
	return ids


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


# --- the line ---------------------------------------------------------------------------------------------------------

func test_bishop_is_a_class_line_discovered_from_its_files_after_the_registered_classes() -> void:
	var lines := Array(DataRepo.lines())
	assert_eq(lines.slice(0, 7), ["common", "beginner", "warrior", "magician", "bowman", "thief", "pirate"],
		"the lines before it keep their merge order")
	assert_eq(lines.slice(7), ["hero", "il_arch_mage", "bishop"],
		"registered classes first, then unregistered ones in sorted order: no shared list names bishop")
	assert_eq(DataRepo.fragment_path("jobs_survivor", "bishop", "res://data"), "res://data/survivor/jobs/bishop.json")
	assert_eq(DataRepo.fragment_path("skills", "bishop", "res://data"), "res://data/survivor/skills/bishop.json")


func test_the_line_loads_without_errors_and_adds_a_job_and_only_pool_skills_or_teleport() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(FileAccess.file_exists(DataRepo.fragment_path("jobs_survivor", "bishop")))
	assert_true(FileAccess.file_exists(DataRepo.fragment_path("skills", "bishop")))
	assert_true(d.jobs_survivor.jobs.has("232"), "jobs/bishop.json is merged into the survivor job data")
	assert_true(d.jobs_survivor.jobs.keys().find("232") > d.jobs_survivor.jobs.keys().find("212"),
		"base, then lines in discovered line order: 232 after 212")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "bishop"))
	# BS4-BS8 fill the skeleton in any order: the fragment holds pool keys and Teleport only (BS5 #377 ported four).
	for key: String in frag.skills:
		assert_true(key in POOL or key == "teleport_cleric", "%s is a pool skill or Teleport" % key)
	assert_eq(Array(DataRepo.unknown_line_files()), [])


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_232_has_the_spec_fields_and_is_playable() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(232)
	assert_eq(String(rec.name), "Bishop")
	assert_eq(jobs.starting_skill(232), "holy_arrow", "D2: every round starts with Holy Arrow in active slot 1")
	assert_eq(jobs.mobility_skill(232), "teleport_cleric", "D1: Teleport is the mobility skill")
	assert_eq(Array(jobs.start_skills(232)), ["holy_arrow", "teleport_cleric"])
	assert_eq(jobs.skill_pool(232), POOL)
	assert_eq(jobs.skill_pool(232).size(), 10)
	assert_false("teleport_cleric" in jobs.skill_pool(232), "Teleport is the mobility skill, not a pool entry")
	assert_eq(jobs.weapon_families(232), ["wand", "staff"])
	assert_eq(jobs.creation_weapon(232), 1372005)
	assert_true(bool(rec.playable), "BS10 ships Bishop")
	assert_eq(jobs.job_error(232), "")
	assert_true(232 in jobs.playable_jobs())


func test_212_keeps_its_entry_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.mobility_skill(212), "teleport_fp")
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.creation_weapon(212), 1372005)
	assert_true(bool(jobs.job(212).playable))


func test_default_job_stays_212_and_a_fresh_world_is_212() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.default_job(), 212)
	var w := RunWorld.new(RF.setup("quiet", 7, RF.quiet_data()))
	assert_eq(w.job_id(), 212)


func test_the_hub_kit_is_the_f_p_kit_with_bishop_s_own_fixture() -> void:
	var jobs := _jobs(_data())
	var kit: Dictionary = jobs.lineage_value(232, "hub_kit", {})
	var fp: Dictionary = jobs.lineage_value(212, "hub_kit", {})
	assert_eq(String(kit.fixture), "res://tests/fixtures/characters/bishop_t2.json")
	assert_eq(kit.scrolls, fp.scrolls, "the same wand and staff scroll lines as F/P")
	assert_eq(kit.equipment, fp.equipment, "the same Magician gear as F/P")
	assert_eq(int(kit.fallback_item), int(fp.fallback_item))


# --- AP row -----------------------------------------------------------------------------------------------------------

func test_the_232_ap_row_is_int_primary_luk_secondary_at_the_212_keyframes() -> void:
	var data := _data()
	var row: Dictionary = data.balance.player.ap["232"]
	assert_eq([String(row.primary), String(row.secondary)], ["int", "luk"])
	assert_eq(row.keyframes, [{"level": 1.0, "target": 3.0}, {"level": 200.0, "target": 202.0}])
	assert_eq(row.keyframes, data.balance.player.ap["212"].keyframes, "the same curve as F/P")
	assert_false(data.balance.growth.has("232"), "HP growth falls back to the 200 row")


func test_a_bishop_spends_its_auto_ap_on_int_and_luk() -> void:
	var w := RF.quiet_world()
	w.set_job(232)
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var row: Dictionary = w.balance.player.ap["232"]
	var luk_ap := AutoAp.secondary_ap(earned, level, float(base.luk), row.keyframes)
	assert_true(luk_ap > 0, "LUK takes its share")
	assert_eq(int(w.player_state.luk), int(base.luk) + luk_ap)
	assert_eq(int(w.player_state.int), int(base.int) + earned - luk_ap, "the rest goes to INT")
	assert_eq(int(w.player_state.str), int(base.str))
	assert_eq(int(w.player_state.dex), int(base.dex))


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_a_bishop_drop_pool_holds_wands_and_staves_and_no_other_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(232)
	var ids := EquipmentDrops.eligible(_ids(), INFO, 232, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	var want := BISHOP_WEAPONS.duplicate()
	want.sort()
	assert_eq(weapons, want, "wands and staves only")
	assert_true(1050001 in ids and 1040002 in ids, "Magician and all-job armour drop")
	assert_false(1092002 in ids, "the Warrior shield never drops for a Bishop")
	for id: int in NOT_BISHOP_WEAPONS:
		assert_false(id in ids, "%d is a sword, axe, spear, bow, claw or gun" % id)


func test_a_seeded_bishop_roll_sample_never_yields_another_weapon_family() -> void:
	var families: Array = _jobs(_data()).weapon_families(232)
	var rng := _rng(374)
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(_ids(), INFO, 232, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(_ids(), INFO, 232, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		assert_false(id in NOT_BISHOP_WEAPONS, "%d is another family" % id)
		if Equipment.slot_of(id) == "weapon":
			assert_true(WeaponInfo.family(id) in ["wand", "staff"], "%d" % id)
	for id: int in BISHOP_WEAPONS:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


func test_requirement_error_accepts_magician_bit_gear_only() -> void:
	var bishop := {"job_id": 232}
	assert_eq(Equipment.requirement_error({"reqJob": 2}, bishop), "", "Magician bit")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, bishop), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 3}, bishop), "", "Warrior and Magician")
	for bit in [1, 4, 8, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, bishop), "reqJob", "reqJob %d is another class" % bit)
	for id: int in [1372005, 1372004, 1382012, 1050001]:
		assert_eq(Equipment.requirement_error(INFO[id], bishop), "", "%d is Magician gear" % id)
	for id: int in [1302008, 1312005, 1092002]:
		assert_eq(Equipment.requirement_error(INFO[id], bishop), "reqJob", "%d is Warrior gear" % id)


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_creation_wand_is_wearable_and_the_shipped_pool_holds_only_wands_and_staves() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(232))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	var wand := jobs.creation_weapon(232)
	assert_true(infos.has(wand), "the creation wand is in the cache")
	assert_eq(WeaponInfo.family(wand), "wand")
	assert_eq(Equipment.requirement_error(infos[wand], {"job_id": 232}), "")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var families := {}
		var rng := _rng(232 + tier)
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 232, band, ed, rng, jobs.weapon_families(232))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 232}), "", "%d is wearable by a Bishop" % id)
			if Equipment.slot_of(id) == "weapon":
				families[WeaponInfo.family(id)] = true
		assert_eq(families.keys().size(), 2, "tier %d: wands and staves (%s)" % [tier + 1, families.keys()])
		assert_true(families.has("wand") and families.has("staff"), "tier %d" % (tier + 1))


# --- Holy Symbol ------------------------------------------------------------------------------------------------------

func test_holy_symbol_is_the_common_exp_passive_offered_to_a_bishop_like_any_job() -> void:
	var w := RF.quiet_world()
	w.set_job(232)
	assert_has(w.upgrades.eligible(w), "passive_exp_new")
	assert_false("passive_exp_rank" in w.upgrades.eligible(w), "the rank card waits for the skill")
	var c := w.upgrades.choice_card("passive_exp_new", w, "legendary")
	assert_eq(c.card_kind, "new_passive")
	assert_eq(w.upgrades.apply("passive_exp_new", w, "legendary"), 1)
	assert_has(w.upgrades.eligible(w), "passive_exp_rank")
	var f := RF.quiet_world()
	assert_has(f.upgrades.eligible(f), "passive_exp_new", "an F/P character is offered the same card")


func test_no_bishop_book_buff_card_exists_and_no_card_carries_holy_symbol_s_skill_id() -> void:
	var data := _data()
	# Holy Symbol (2311003) and the 231/232 buffs (ADR 0006: buffs are out of the pool). Bless and Invincible are the
	# unported Cleric (230) legacy buffs of magician.json; they keep their cards and are checked for eligibility below.
	var buffs := [2311003, 2311001, 2311002, 2311005, 2321000, 2321002, 2321004, 2321005, 2321009]
	for c: Dictionary in data.upgrades.cards:
		var key := String(c.get("skill", ""))
		if key == "":
			continue
		var sid := int(data.skills.skills[key].get("skill_id", 0)) if data.skills.skills.has(key) else 0
		assert_false(sid in buffs, "card %s is a Bishop buff (%d)" % [c.id, sid])
	for key: String in data.skills.skills:
		assert_false(int(data.skills.skills[key].get("skill_id", 0)) == 2311003, "%s is Holy Symbol's id" % key)


func test_the_legacy_cleric_buff_cards_are_never_offered_to_a_bishop() -> void:
	var w := RF.quiet_world()
	w.set_job(232)
	var offered := w.upgrades.eligible(w)
	for id in ["bless_new", "bless_rank", "invincible_new", "invincible_rank"]:
		assert_false(id in offered, "%s is unported (not in the pool)" % id)
