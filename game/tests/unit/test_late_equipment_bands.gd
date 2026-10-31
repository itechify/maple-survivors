extends TestCase
## Equipment for the drop bands of the sixteen progression steps (spec #449 C12, #474; ADR 0007): for each band and
## each job class, the shipped equipment lists hold at least one eligible weapon of every family the class lists and at
## least one piece for every armour slot it wears. The band table is data here, so steps 6-16 are checked before their
## regions exist; the cache-backed parts read the real Character.wz info and SKIP without the asset cache.

## Drop band of each progression step (#447 table, tier C owner call). Steps 1-5 are the shipped stages' bands. Step 16 is
## [108, 120] instead of #447's [110, 120] (tier C, #474): v83 has no Magician wand and no Magician overall between
## reqLevel 109 and 130 (the Dragon Wand and the Dragon Robe are Lv108), so the band reaches down to them. The mins and
## maxes stay non-decreasing along the progression.
const BANDS := [
	[0, 15], [10, 20], [15, 25], [20, 30], [30, 40], [35, 45], [40, 50], [45, 55], [50, 60], [55, 65], [60, 70],
	[70, 80], [80, 90], [90, 100], [100, 110], [108, 120],
]
## Job classes (one representative job id each) and the weapon families they list. The playable jobs' lists are checked
## against jobs/*.json below; Marksman (322), the Thief line (412) and Corsair (522) are planned classes whose families
## the line files already carry (spec #384 and later).
const CLASSES := {
	"Hero": {"job": 112, "families": ["sword", "axe"], "shield": true},
	"Paladin": {"job": 122, "families": ["sword", "blunt"], "shield": true},
	"Dark Knight": {"job": 132, "families": ["spear", "polearm"], "shield": false},
	"Arch Mage": {"job": 212, "families": ["wand", "staff"], "shield": false},
	"Bowmaster": {"job": 312, "families": ["bow"], "shield": false},
	"Marksman": {"job": 322, "families": ["crossbow"], "shield": false},
	"Night Lord": {"job": 412, "families": ["claw", "dagger"], "shield": false},
	"Buccaneer": {"job": 512, "families": ["knuckle"], "shield": false},
	"Corsair": {"job": 522, "families": ["gun"], "shield": false},
}
## Gaps the shipped lists already had in steps 1-5 (the old Cosmic-based selection listed no Warrior or Pirate armour below
## reqLevel 35): "step class: what is missing". The bands of those five stages are not touched by #474, so the gaps are
## recorded; a fixed gap makes this test fail until its entry is removed.
const KNOWN_GAPS := {
	"3 Hero": ["gloves", "body"], "3 Paladin": ["gloves", "body"], "3 Dark Knight": ["gloves", "body"],
	"3 Buccaneer": ["gloves", "body"], "3 Corsair": ["gloves", "body"],
	"4 Hero": ["gloves"], "4 Paladin": ["gloves"], "4 Dark Knight": ["gloves"],
	"4 Buccaneer": ["gloves"], "4 Corsair": ["gloves"],
}
## Info flags that mark an item no ordinary mob or shop gives (tier C: Character.wz facts; the earlier lists have none).
const NOT_ORDINARY := ["cash", "only", "notSale", "quest", "timeLimited", "equipTradeBlock", "expireOnLogout", "tradeBlock",
	"epic", "epicItem", "weekly"]
## Items of the older lists that are Lv35+ and reqJob 0 weapons (the Magician line takes every wand and staff): the Heart Wand.
const OLDER_ANY_JOB_WEAPONS := [1372033]


func _all_ids() -> Array:
	return DataRepo.load_all().equipment_drops.items


func _infos(ids: Array, lib: AssetLibrary) -> Dictionary:
	var infos := {}
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null and img.root.get("info") is Dictionary:
			infos[int(raw)] = img.root.info
	return infos


## What a class lacks in a band: weapon families, "hat", "shoes", "gloves", "body" (an overall, or a top with a bottom)
## and, for the classes that wear one, "shield".
func _missing(ids: Array, infos: Dictionary, spec: Dictionary, band: Array) -> Array:
	var job: int = spec.job
	var out := []
	for family: String in spec.families:
		if EquipmentDrops.eligible(ids, infos, job, band, [family]).filter(
				func(id: int) -> bool: return WeaponInfo.family(id) == family).is_empty():
			out.append(family)
	var slots := {}
	for id: int in EquipmentDrops.eligible(ids, infos, job, band, []):
		slots[Equipment.slot_of(id)] = true
	for slot: String in ["hat", "shoes", "gloves"]:
		if not slots.has(slot):
			out.append(slot)
	if not (slots.has("overall") or (slots.has("top") and slots.has("bottom"))):
		out.append("body")
	if spec.shield and not slots.has("shield"):
		out.append("shield")
	return out


func test_the_band_table_never_goes_down_and_overlaps_its_neighbour() -> void:
	for i in range(1, BANDS.size()):
		assert_true(BANDS[i][0] >= BANDS[i - 1][0] and BANDS[i][1] >= BANDS[i - 1][1], "step %d is not below step %d" % [i + 1, i])
		assert_true(BANDS[i][0] <= BANDS[i - 1][1], "step %d starts inside step %d" % [i + 1, i])


func test_the_stages_that_exist_carry_the_table_band() -> void:
	var stages: Dictionary = DataRepo.load_all().stages
	# The band belongs to the region's canonical step (#449 table), so a branch that lacks an earlier region still passes.
	var order: Array = FIRST_FIFTEEN + ["temple_of_time"]
	for key: String in stages.progression:
		var step := order.find(key)
		assert_true(step >= 0, "%s is a region of the #449 table" % key)
		if step >= 0:
			assert_eq(EquipmentDrops.band_of(stages.stages[key]), BANDS[step], "step %d %s" % [step + 1, key])


func test_the_class_table_covers_the_weapon_families_of_every_job() -> void:
	var listed := {}
	for spec: Dictionary in CLASSES.values():
		for family: String in spec.families:
			listed[family] = true
	var data := DataRepo.load_all()
	var jobs := DataRepo.jobs(data)
	for raw: Variant in data.jobs_survivor.get("jobs", {}):
		var job := int(raw)
		for family: String in jobs.weapon_families(job):
			assert_true(listed.has(family), "job %d lists the %s family" % [job, family])
	for name: String in CLASSES:
		var job: int = CLASSES[name].job
		if jobs.job_error(job) == "": # a playable job: its list is the table's
			assert_eq(jobs.weapon_families(job), CLASSES[name].families, name)


func test_every_band_has_each_class_its_weapon_families_and_armour_slots() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var ids := _all_ids()
	var infos := _infos(ids, lib)
	var gaps := {}
	for step in BANDS.size():
		for name: String in CLASSES:
			var missing := _missing(ids, infos, CLASSES[name], BANDS[step])
			if not missing.is_empty():
				gaps["%d %s" % [step + 1, name]] = missing
	assert_eq(gaps, KNOWN_GAPS, "no gap beyond the recorded ones in steps 1-5; none at all in steps 6-16")
	lib.free()


func test_every_listed_item_is_ordinary_equipment_within_reqlevel_120_with_art() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var ids := _all_ids()
	var infos := _infos(ids, lib)
	for raw: Variant in ids:
		var id := int(raw)
		assert_true(infos.has(id), "%d has info in the cache" % id)
		if not infos.has(id):
			continue
		var info: Dictionary = infos[id]
		assert_true(Equipment.slot_of(id) != "", "%d is worn in an equip slot (no cape)" % id)
		assert_true(int(info.get("reqLevel", 0)) <= 120, "%d reqLevel" % id)
		if int(info.get("reqLevel", 0)) < 35: # the older lists (spec #33 and the class specs) have their own checks
			continue
		var req := int(info.get("reqJob", 0))
		if Equipment.slot_of(id) == "weapon" and id not in OLDER_ANY_JOB_WEAPONS:
			assert_true(req > 0, "%d: a weapon carries its line's bit" % id)
		for flag: String in NOT_ORDINARY:
			assert_eq(int(info.get(flag, 0)), 0, "%d %s" % [id, flag])
		assert_true(int(info.get("price", 0)) > 1, "%d is sold (price above 1)" % id)
		var path := AvatarRenderer.part_img_path(id)
		for icon: String in ["icon", "iconRaw"]:
			assert_true(lib.frame(path + "/info/" + icon) != null, "%d %s" % [id, icon])
	lib.free()


func test_the_line_files_hold_each_item_in_the_file_of_its_class() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var by_file := {"common": 0, "warrior": 1, "magician": 2, "bowman": 4, "thief": 8, "pirate": 16}
	for line: String in by_file:
		var file: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", line, "res://data"))
		for raw: Variant in file.items:
			var id := int(raw)
			var img := lib.img(AvatarRenderer.part_img_path(id))
			if img == null or int(img.root.get("info", {}).get("reqLevel", 0)) < 35 or id in OLDER_ANY_JOB_WEAPONS:
				continue # the older lists are checked by their own tests
			var req := int(img.root.info.get("reqJob", 0))
			if line == "common":
				assert_eq(req, 0, "%d is for any job" % id)
			else:
				assert_true(req & by_file[line] != 0, "%d: reqJob %d carries the %s bit" % [id, req, line])
	lib.free()


# --- the late-progression fixture (spec #449 C12, #474) ---

const LATE := "res://tests/fixtures/characters/late_progression.json"
## The first fifteen progression keys (#449 table): the fixture clears them all, including the ten regions that ship later.
const FIRST_FIFTEEN := ["henesys", "ellinia", "perion", "kerning", "sleepywood", "ludibrium", "omega_sector", "korean_folk_town",
	"mu_lung", "el_nath", "magatia", "zipangu", "leafre", "phantom_forest", "clocktower"]


func _late() -> Dictionary:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(LATE, errors)
	assert_eq(errors, PackedStringArray(), "the fixture is a valid format-3 character")
	return character


func test_the_late_fixture_is_an_unscrolled_hero_who_cleared_fifteen_regions() -> void:
	var character := _late()
	assert_eq(int(character.job_id), 112)
	var cleared: Array = character.cleared_regions.duplicate()
	var expected := FIRST_FIFTEEN.duplicate()
	cleared.sort()
	expected.sort()
	assert_eq(cleared, expected)
	var data := DataRepo.load_all()
	var unlocked := CharacterSnapshot.unlocked_keys(data.stages.progression, character.cleared_regions)
	assert_eq(unlocked, data.stages.progression, "every shipped region is open")
	var listed := _all_ids().map(func(id: Variant) -> int: return int(id))
	var worn: Dictionary = character.equipment.worn
	assert_eq(worn.keys().size(), 6, "weapon, shield, hat, overall, shoes and gloves")
	for slot: String in worn:
		var item: Dictionary = worn[slot]
		assert_eq(int(item.scrolls), 0, slot + " is unscrolled")
		assert_true(int(item.id) in listed, "%d is a drop of the lists" % int(item.id))


func test_the_late_fixture_wears_band_15_equipment_of_the_warrior_line() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var character := _late()
	for slot: String in character.equipment.worn:
		var id := int(character.equipment.worn[slot].id)
		var info: Dictionary = lib.img(AvatarRenderer.part_img_path(id)).root.info
		assert_between(float(info.reqLevel), float(BANDS[14][0]), float(BANDS[14][1]), "%d is in the step-15 band" % id)
		assert_true(Equipment.job_allows(info, 112), "%d is for a Hero" % id)
	lib.free()


func test_hub_late_flag_opens_the_late_fixture_of_a_job_that_has_one() -> void:
	var late := HubTestKit.parse_args(PackedStringArray(["--hub", "--job=112", "--late"]))
	assert_eq(late.character, LATE)
	assert_false(late.has("error"))
	assert_eq(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=112", "--late", "--character=/x/y.json"])).character, "/x/y.json")
	assert_ne(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=112"])).character, LATE, "without --late: the tier-2 fixture")
	assert_true(HubTestKit.parse_args(PackedStringArray(["--hub", "--job=212", "--late"])).has("error"), "F/P has no late fixture yet")
