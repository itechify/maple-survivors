extends TestCase
## Paladin's data seam (spec #308, ticket P2 #310): the `paladin` line is discovered after `hero`, its job entry
## `survivor/jobs/paladin.json` (122, not playable yet), its skill pool (defined keys resolve, undefined keys stay inert),
## its AP row, and the weapon families of its drops (sword and blunt, one- and two-handed; never an axe, spear or polearm)
## with the Warrior-bit requirement (Mace). Seeded RNG; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")

const POOL := ["power_strike", "slash_blast", "blast", "monster_magnet_paladin", "fire_charge", "ice_charge",
	"thunder_charge", "holy_charge"]
const DEFINED_IN_HERO := ["power_strike", "slash_blast"]
## Synthetic item info for the Warrior-bit weapons (reqJob 1) and the Mace (reqJob 3, as in the v83 Item.wz).
const MACE := 1322000
const INFO := {
	1302008: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed sword
	1402002: {"reqLevel": 30, "reqJob": 1, "incPAD": 50, "tuc": 7}, # two-handed sword
	1312005: {"reqLevel": 30, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed axe
	1412006: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # two-handed axe
	1322014: {"reqLevel": 30, "reqJob": 1, "incPAD": 49, "tuc": 7}, # one-handed blunt weapon
	1422001: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # two-handed blunt weapon
	1432002: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # spear
	1442001: {"reqLevel": 30, "reqJob": 1, "incPAD": 52, "tuc": 7}, # polearm
	1092002: {"reqLevel": 30, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1372004: {"reqLevel": 30, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1050001: {"reqLevel": 30, "reqJob": 2, "incPDD": 20, "incMDD": 12, "tuc": 10}, # Magician overall
	MACE: {"reqLevel": 15, "reqJob": 3, "incPAD": 34, "tuc": 7}, # Mace (reqJob 3 includes the Warrior bit)
}
const PALADIN_WEAPONS := [1302008, 1402002, 1322014, 1422001, MACE]
const NOT_PALADIN_WEAPONS := [1312005, 1412006, 1432002, 1442001]
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]


func _data() -> Dictionary:
	return DataRepo.load_all()


func _jobs(data: Dictionary) -> JobTree:
	return JobTree.from_data(data.jobs, data.jobs_survivor)


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


## The line names (`skills/<line>.json`) whose file defines `key` in its `skills` map, in discovery order.
func _defining_lines(key: String) -> Array:
	var out := []
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("skills", line)
		if FileAccess.file_exists(path) and DataRepo.load_json(path).get("skills", {}).has(key):
			out.append(line)
	return out


# --- the line ---------------------------------------------------------------------------------------------------------

func test_paladin_line_is_discovered_after_hero_without_a_shared_registration() -> void:
	var lines := Array(DataRepo.lines())
	assert_true("paladin" in lines, "discovered from its files")
	assert_true(lines.find("paladin") > lines.find("hero"), "a class line follows the Adventurer lines and hero")
	assert_eq(DataRepo.fragment_path("jobs_survivor", "paladin", "res://data"), "res://data/survivor/jobs/paladin.json")
	assert_eq(DataRepo.fragment_path("skills", "paladin", "res://data"), "res://data/survivor/skills/paladin.json")


func test_the_paladin_line_loads_without_errors_and_adds_only_its_job_and_an_empty_skill_skeleton() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(d.jobs_survivor.jobs.has("122"), "jobs/paladin.json is merged into the survivor job data")
	assert_eq(d.jobs_survivor.jobs.keys(), ["0", "200", "212", "112", "122"], "base entries, then lines in discovered order")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "paladin"))
	# The skill tickets append their own definitions (P4-P8); only the spec's Paladin keys may live here.
	var own := ["rush_paladin", "blast", "monster_magnet_paladin", "charged_blow", "fire_charge", "ice_charge", "thunder_charge",
		"holy_charge", "heavens_hammer"]
	for key: String in frag.skills:
		assert_true(key in own, "%s is a Paladin key of the spec" % key)
	assert_true(frag.has("_doc"))
	assert_eq(Array(DataRepo.unknown_line_files()), [])


func test_the_shared_defaults_hold_no_paladin_rows() -> void:
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("122"), "the Paladin AP row lives in jobs/paladin.json")
	assert_false(shared.bot.card_scores.has("blast_new"), "no shared score for a Paladin skill")


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_122_has_the_spec_fields_and_is_not_playable_yet() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(122)
	assert_eq(String(rec.name), "Paladin")
	assert_eq(jobs.starting_skill(122), "power_strike")
	assert_eq(jobs.mobility_skill(122), "rush_paladin")
	assert_eq(Array(jobs.start_skills(122)), ["power_strike", "rush_paladin"])
	assert_eq(jobs.skill_pool(122), POOL)
	assert_eq(jobs.skill_pool(122).size(), 8)
	assert_false("rush_paladin" in jobs.skill_pool(122), "Rush is the mobility skill, not a pool entry")
	assert_eq(jobs.weapon_families(122), ["sword", "blunt"])
	assert_eq(jobs.creation_weapon(122), MACE)
	assert_false(bool(rec.playable))
	assert_ne(jobs.job_error(122), "", "a tool cannot choose it until P9 flips playable")
	assert_eq(jobs.playable_jobs(), [112, 212] as Array[int], "Paladin is not in the playable list")


func test_job_122_entry_names_no_meter_and_no_hub_kit_yet() -> void:
	var entry: Dictionary = _data().jobs_survivor.jobs["122"]
	assert_false(entry.has("meter"), "Paladin's Forms (P3) are its own seam, not a Combo meter")
	assert_false(entry.has("hub_kit"), "the Paladin hub kit is P9")


func test_212_and_112_keep_their_entries_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.starting_skill(112), "power_strike")
	assert_eq(jobs.mobility_skill(112), "rush_hero")
	assert_eq(jobs.weapon_families(112), ["sword", "axe"])


func test_default_job_stays_212_with_paladin_on_the_line() -> void:
	var data := _data()
	assert_eq(_jobs(data).default_job(), 212)
	data.jobs_survivor.jobs["122"]["playable"] = true
	assert_eq(_jobs(data).default_job(), 212, "the pin, not the first playable job")


# --- the pool: defined keys resolve, undefined keys stay inert --------------------------------------------------------

func test_each_shared_pool_key_is_defined_in_exactly_one_file() -> void:
	for key: String in DEFINED_IN_HERO:
		assert_eq(_defining_lines(key), ["hero"], "%s is defined by Hero's file only" % key)


## The pool keys no skills file defines yet: P5 #313, P7 #315 and P8 #316 each define theirs, so this list shrinks to nothing.
func _undefined() -> Array:
	var defined: Dictionary = _data().skills.skills
	return POOL.filter(func(key: String) -> bool: return not defined.has(key))


func test_the_two_shared_pool_keys_are_defined_and_the_rest_wait_for_their_tickets() -> void:
	var defined: Dictionary = _data().skills.skills
	for key: String in DEFINED_IN_HERO:
		assert_true(defined.has(key), "%s is Hero's definition" % key)
	for key: String in _undefined():
		assert_false(key in DEFINED_IN_HERO, key)


func test_an_undefined_pool_key_is_never_offered_but_a_defined_one_is() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["122"]["playable"] = true
	var setup := RF.setup("quiet", 7, data)
	setup["job"] = 122
	var w := RunWorld.new(setup)
	var ids := Array(w.upgrades.eligible(w))
	for key: String in _undefined():
		assert_false(ids.has(key + "_new") or ids.has(key + "_rank"), "%s is not offered" % key)
	assert_false(ids.has("rush_paladin_new"), "Rush is not a card")
	assert_true(ids.has("power_strike_new") or w.loadout.has("power_strike"),
		"a defined pool key resolves to its definition")


func test_power_strike_takes_slot_one_for_a_paladin_and_rush_is_learned_outside_the_slots() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["122"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", 7, data))
	setup["job"] = 122
	var w := RunWorld.new(setup)
	assert_eq(String(w.loadout.order[0]), "power_strike", "slot 1")
	var tracked := w.loadout.order.filter(func(k: Variant) -> bool: return w.book.slot(String(k)) != "mobility")
	assert_eq(tracked.size(), 1, "Rush is not on a slot track")
	assert_true(w.loadout.has("rush_paladin"), "Rush (P4 #312) is learned at round start too")
	assert_eq(w.book.slot("rush_paladin"), "mobility", "on the mobility slot, not a slot track")


# --- AP row and growth ------------------------------------------------------------------------------------------------

func test_the_122_ap_row_is_str_primary_dex_secondary_like_hero() -> void:
	var data := _data()
	var row: Dictionary = data.balance.player.ap["122"]
	var hero: Dictionary = data.balance.player.ap["112"]
	assert_eq([String(row.primary), String(row.secondary)], ["str", "dex"])
	assert_eq(row.keyframes, [{"level": 1.0, "target": 4.0}, {"level": 200.0, "target": 204.0}])
	assert_eq(row.keyframes, hero.keyframes, "the Hero shape (tier C)")


func test_paladin_has_no_growth_row_so_it_inherits_the_warrior_line() -> void:
	var data := _data()
	assert_false(data.balance.growth.has("122"), "HP growth is inherited")
	assert_eq(_jobs(data).lineage(122), [122, 121, 120, 100, 0] as PackedInt32Array, "the canonical line up to the root")
	assert_eq(int(data.balance.growth["100"].hp), 26)


func test_a_paladin_spends_its_auto_ap_on_str_and_dex() -> void:
	var w := RF.quiet_world()
	w.set_job(122)
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var row: Dictionary = w.balance.player.ap["122"]
	var dex_ap := AutoAp.secondary_ap(earned, level, float(base.dex), row.keyframes)
	assert_true(dex_ap > 0, "DEX takes its share")
	assert_eq(int(w.player_state.dex), int(base.dex) + dex_ap)
	assert_eq(int(w.player_state.str), int(base.str) + earned - dex_ap, "the rest goes to STR")


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_a_paladin_drop_pool_holds_swords_and_blunt_weapons_of_both_hands() -> void:
	var families: Array = _jobs(_data()).weapon_families(122)
	var ids := EquipmentDrops.eligible(INFO.keys(), INFO, 122, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	var want := PALADIN_WEAPONS.duplicate()
	want.sort()
	assert_eq(weapons, want, "one- and two-handed swords and blunt weapons")
	assert_true(1092002 in ids, "the Warrior shield drops by the class bit")
	assert_true(1002001 in ids, "all-job armour drops")
	assert_false(1372004 in ids or 1050001 in ids, "Magician gear never drops for a Paladin")


func test_a_seeded_paladin_roll_never_yields_an_axe_spear_or_polearm() -> void:
	var families: Array = _jobs(_data()).weapon_families(122)
	var rng := _rng(310)
	var ids := INFO.keys()
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(ids, INFO, 122, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(ids, INFO, 122, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		assert_false(id in NOT_PALADIN_WEAPONS, "%d is an axe, spear or polearm" % id)
		if Equipment.slot_of(id) == "weapon":
			assert_true(WeaponInfo.family(id) in ["sword", "blunt"], "%d" % id)
	for id: int in PALADIN_WEAPONS:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


## The shipped drop list (every equipment_drops item that is a weapon), with the Warrior-bit reqJob every such weapon has:
## the families filter holds on the real ids, not only on the synthetic table above. Runs without the cache.
func test_the_shipped_weapon_drops_keep_swords_and_blunt_weapons_only_for_a_paladin() -> void:
	var data := _data()
	var weapons: Array = []
	for raw: Variant in data.equipment_drops.items:
		if Equipment.slot_of(int(raw)) == "weapon":
			weapons.append(int(raw))
	assert_false(weapons.is_empty(), "the shipped list has weapons")
	var info := {}
	for id: int in weapons:
		info[id] = {"reqLevel": 0, "reqJob": 1, "tuc": 7}
	var families: Array = _jobs(data).weapon_families(122)
	var ids := EquipmentDrops.eligible(weapons, info, 122, BAND, families)
	var fams := {}
	for id: int in ids:
		fams[WeaponInfo.family(id)] = true
	assert_eq(fams.keys().size(), 2, "%s" % [fams.keys()])
	assert_true(fams.has("sword") and fams.has("blunt"), "%s" % [fams.keys()])
	for id: int in weapons:
		if WeaponInfo.family(id) in ["axe", "spear", "polearm"]:
			assert_false(id in ids, "%d (%s) never drops for a Paladin" % [id, WeaponInfo.family(id)])


func test_requirement_error_accepts_warrior_bit_gear_and_the_mace_only() -> void:
	var paladin := {"job_id": 122}
	assert_eq(Equipment.requirement_error({"reqJob": 1}, paladin), "", "Warrior bit")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, paladin), "", "all jobs")
	assert_eq(Equipment.requirement_error(INFO[MACE], paladin), "", "the Mace (reqJob 3)")
	for bit in [2, 4, 8, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, paladin), "reqJob", "reqJob %d is another class" % bit)
	for id: int in [1372004, 1050001]:
		assert_eq(Equipment.requirement_error(INFO[id], paladin), "reqJob", "%d is Magician gear" % id)


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_mace_is_wearable_and_each_tier_drops_swords_and_blunt_weapons_of_each_hand() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(122))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	assert_true(infos.has(MACE), "the Mace is in the cache")
	assert_eq(WeaponInfo.family(MACE), "blunt")
	assert_eq(Equipment.requirement_error(infos[MACE], {"job_id": 122}), "", "a Paladin can wear the creation Mace")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var hands := {}
		var rng := _rng(122 + tier)
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 122, band, ed, rng, jobs.weapon_families(122))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 122}), "", "%d is wearable by a Paladin" % id)
			if Equipment.slot_of(id) == "weapon":
				var family := WeaponInfo.family(id)
				assert_true(family in ["sword", "blunt"], "%d is a %s" % [id, family])
				hands["%s_%s" % [family, "2h" if WeaponInfo.is_two_handed(id) else "1h"]] = true
		assert_eq(hands.size(), 4, "tier %d: sword and blunt, one- and two-handed (%s)" % [tier + 1, hands.keys()])
