extends TestCase
## The per-job-line survivor data files (DataRepo.load_split / load_all, docs/ARCHITECTURE.md 4.4.4): a base file
## `survivor/<name>.json` plus line fragments `survivor/<name>/<line>.json` merged in DataRepo.lines() order. Merge rules
## are tested on synthetic fixture directories under the user data dir; the shipped data is checked for the files that
## exist (only known line names) and for the entry placement rules (skills by book, cards by skill, wands in magician).

const WORK := "survivor_lines"


func after_each() -> void:
	remove_tree(test_dir(WORK))


## Writes `value` (a Dictionary, as JSON) to `<fixture root>/<rel>` and returns the fixture root.
func _put(rel: String, value: Dictionary) -> String:
	var root := test_dir(WORK)
	var path := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "", false))
	file.close()
	return root


func test_lines_are_fixed_adventurers_then_registered_classes() -> void:
	var root := _put("survivor/jobs/paladin.json", {"jobs": {}})
	_put("survivor/skills/hero.json", {"skills": {}})
	_put("survivor/jobs/il_arch_mage.json", {"jobs": {}})
	assert_eq(Array(DataRepo.lines(root)), ["common", "beginner", "warrior", "magician", "bowman", "thief", "pirate",
		"hero", "il_arch_mage", "paladin"])
	assert_eq(DataRepo.fragment_path("skills", "magician", "res://data"), "res://data/survivor/skills/magician.json")


func test_the_shipped_class_lines_are_discovered_from_their_files() -> void:
	var lines := Array(DataRepo.lines())
	assert_eq(lines.slice(0, 7), ["common", "beginner", "warrior", "magician", "bowman", "thief", "pirate"])
	var classes: Array = lines.slice(7)
	assert_true("hero" in classes and "il_arch_mage" in classes, "both shipped class lines are found by their files")
	assert_true(classes.find("hero") < classes.find("il_arch_mage"), "existing class order stays stable")


func test_job_fragments_contribute_balance_through_load_all() -> void:
	var root := _put("survivor/jobs.json", {})
	_put("survivor/balance.json", {"player": {"ap": {"212": {"str": 4}}}})
	_put("survivor/jobs/hero.json", {"jobs": {}, "balance": {"player": {"ap": {"112": {"str": 5}}}}})
	var data := DataRepo.load_all(root)
	assert_eq(data.balance.player.ap["112"], {"str": 5.0})
	assert_eq(data.balance.player.ap["212"], {"str": 4.0})


func test_skills_merge_in_line_order_and_keep_the_base_doc() -> void:
	_put("survivor/skills.json", {"_doc": "base doc", "skills": {"base_one": {"n": 1}}})
	_put("survivor/skills/magician.json", {"_doc": "mage", "skills": {"m_one": {"n": 3}, "m_two": {"n": 4}}})
	_put("survivor/skills/beginner.json", {"_doc": "beg", "skills": {"b_one": {"n": 2}}})
	_put("survivor/skills/warrior.json", {"skills": {"w_one": {"n": 9}}})
	var errors := PackedStringArray()
	var d := DataRepo.load_split("skills", test_dir(WORK), errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_eq(d._doc, "base doc", "the base _doc is never overwritten by a fragment")
	assert_eq(d.skills.keys(), ["base_one", "b_one", "w_one", "m_one", "m_two"], "base, beginner, warrior, magician")
	assert_eq(d.skills.w_one, {"n": 9.0})
	assert_eq(d.keys(), ["_doc", "skills"], "fragment _doc notes are not merged")


func test_a_class_line_after_pirate_merges_last_for_jobs_and_skills() -> void:
	_put("survivor/jobs.json", {"_doc": "d", "default_job": 212, "jobs": {"0": {"a": 1}}})
	_put("survivor/jobs/magician.json", {"jobs": {"212": {"playable": true}}})
	_put("survivor/jobs/hero.json", {"_doc": "hero", "jobs": {"112": {"playable": false}}})
	_put("survivor/skills.json", {"_doc": "d"})
	_put("survivor/skills/hero.json", {"skills": {"h": {}}})
	_put("survivor/skills/pirate.json", {"skills": {"p": {}}})
	var errors := PackedStringArray()
	var jobs := DataRepo.load_split("jobs_survivor", test_dir(WORK), errors)
	var skills := DataRepo.load_split("skills", test_dir(WORK), errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_eq(jobs.jobs.keys(), ["0", "212", "112"], "base, magician, then hero")
	assert_eq(jobs.default_job, 212, "top-level config stays in the base")
	assert_eq(skills.skills.keys(), ["p", "h"])


func test_missing_fragments_are_skipped_and_the_entries_key_always_exists() -> void:
	_put("survivor/skills.json", {"_doc": "only a base"})
	_put("survivor/upgrades.json", {"fallback": {"id": "elixir"}})
	_put("survivor/equipment_drops.json", {})
	_put("survivor/scrolls.json", {})
	_put("survivor/shops.json", {"prices": {"armour": 1}})
	var errors := PackedStringArray()
	var root := test_dir(WORK)
	assert_eq(DataRepo.load_split("skills", root, errors).skills, {})
	assert_eq(DataRepo.load_split("upgrades", root, errors).cards, [])
	assert_eq(DataRepo.load_split("equipment_drops", root, errors).items, [])
	assert_eq(DataRepo.load_split("scrolls", root, errors).families, {})
	assert_eq(DataRepo.load_split("shops", root, errors).weapon_slots, [])
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_eq(DataRepo.load_split("shops", root, errors).prices, {"armour": 1.0}, "base config stays")


func test_upgrade_cards_concatenate_in_line_order() -> void:
	_put("survivor/upgrades.json", {"_doc": "d", "pity": {"draws": 1}, "fallback": {"id": "elixir"}})
	_put("survivor/upgrades/magician.json", {"cards": [{"id": "m1"}, {"id": "m2"}]})
	_put("survivor/upgrades/common.json", {"cards": [{"id": "c1"}]})
	_put("survivor/upgrades/beginner.json", {"cards": [{"id": "b1"}, {"id": "b2"}]})
	var errors := PackedStringArray()
	var d := DataRepo.load_split("upgrades", test_dir(WORK), errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	var ids := []
	for c: Dictionary in d.cards:
		ids.append(c.id)
	assert_eq(ids, ["c1", "b1", "b2", "m1", "m2"])
	assert_eq(d.pity, {"draws": 1.0}, "job-neutral config stays in the base")
	assert_eq(d.fallback.id, "elixir")
	assert_eq(d.keys(), ["_doc", "pity", "fallback", "cards"])


func test_equipment_drop_ids_concatenate_then_sort_ascending() -> void:
	_put("survivor/equipment_drops.json", {"_doc": "d", "below": 10})
	_put("survivor/equipment_drops/common.json", {"items": [1002001, 1040002, 1082002]})
	_put("survivor/equipment_drops/magician.json", {"items": [1002008, 1372000, 1041002]})
	var errors := PackedStringArray()
	var d := DataRepo.load_split("equipment_drops", test_dir(WORK), errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_eq(d["items"], [1002001.0, 1002008.0, 1040002.0, 1041002.0, 1082002.0, 1372000.0])
	assert_eq(d.below, 10)


func test_scroll_families_merge_per_slot_keeping_slot_order() -> void:
	_put("survivor/scrolls.json", {"_doc": "d"})
	_put("survivor/scrolls/common.json", {"families": {"hat": {"DEF": {"100": 1}}, "top": {"DEF": {"100": 2}}}})
	_put("survivor/scrolls/warrior.json", {"families": {"hat": {"STR": {"100": 3}}}})
	_put("survivor/scrolls/magician.json", {"families": {"wand": {"Magic Att.": {"100": 4}}, "staff": {"Magic Att.": {"100": 5}}}})
	var errors := PackedStringArray()
	var d := DataRepo.load_split("scrolls", test_dir(WORK), errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_eq(d.families.keys(), ["hat", "top", "wand", "staff"])
	assert_eq(d.families.hat.keys(), ["DEF", "STR"], "a later file adds families to an existing slot")
	assert_eq(d.families.hat.STR, {"100": 3.0})
	assert_eq(Scrolls.ids(d), [1, 2, 3, 4, 5])


func test_shop_weapon_slots_concatenate() -> void:
	_put("survivor/shops.json", {"_doc": "d", "prices": {"armour": 1, "weapon": 2}})
	_put("survivor/shops/magician.json", {"weapon_slots": ["wand", "staff"]})
	_put("survivor/shops/bowman.json", {"weapon_slots": ["bow"]})
	var errors := PackedStringArray()
	var d := DataRepo.load_split("shops", test_dir(WORK), errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_eq(d.weapon_slots, ["wand", "staff", "bow"])


func test_a_duplicate_across_files_is_an_error_and_the_first_value_is_kept() -> void:
	var root := _put("survivor/skills.json", {"_doc": "d"})
	_put("survivor/skills/beginner.json", {"skills": {"dup": {"from": "beginner"}}})
	_put("survivor/skills/magician.json", {"skills": {"dup": {"from": "magician"}, "ok": {}}})
	var errors := PackedStringArray()
	var d := DataRepo.load_split("skills", root, errors)
	assert_eq(errors.size(), 1, "%s" % [errors])
	assert_true("dup" in errors[0] and "magician.json" in errors[0], errors[0] if errors.size() > 0 else "no error")
	assert_eq(d.skills.dup, {"from": "beginner"}, "first value kept")
	assert_true(d.skills.has("ok"))

	_put("survivor/upgrades.json", {})
	_put("survivor/upgrades/common.json", {"cards": [{"id": "x", "n": 1}]})
	_put("survivor/upgrades/magician.json", {"cards": [{"id": "x", "n": 2}, {"id": "y"}]})
	errors = PackedStringArray()
	d = DataRepo.load_split("upgrades", root, errors)
	assert_eq(errors.size(), 1, "duplicate card id: %s" % [errors])
	assert_eq(d.cards.size(), 2)
	assert_eq(d.cards[0].n, 1)

	_put("survivor/equipment_drops.json", {})
	_put("survivor/equipment_drops/common.json", {"items": [1002001]})
	_put("survivor/equipment_drops/magician.json", {"items": [1002001, 1372000]})
	errors = PackedStringArray()
	d = DataRepo.load_split("equipment_drops", root, errors)
	assert_eq(errors.size(), 1, "duplicate item id: %s" % [errors])
	assert_eq(d["items"], [1002001.0, 1372000.0])

	_put("survivor/scrolls.json", {})
	_put("survivor/scrolls/common.json", {"families": {"hat": {"DEF": {"100": 1}}}})
	_put("survivor/scrolls/warrior.json", {"families": {"hat": {"DEF": {"100": 9}, "STR": {"100": 2}}}})
	errors = PackedStringArray()
	d = DataRepo.load_split("scrolls", root, errors)
	assert_eq(errors.size(), 1, "duplicate slot+family: %s" % [errors])
	assert_eq(d.families.hat.DEF, {"100": 1.0})
	assert_true(d.families.hat.has("STR"), "the non-duplicate family of the same slot is still merged")

	_put("survivor/shops.json", {})
	_put("survivor/shops/magician.json", {"weapon_slots": ["wand", "staff"]})
	_put("survivor/shops/bowman.json", {"weapon_slots": ["staff", "bow"]})
	errors = PackedStringArray()
	d = DataRepo.load_split("shops", root, errors)
	assert_eq(errors.size(), 1, "duplicate weapon slot: %s" % [errors])
	assert_eq(d.weapon_slots, ["wand", "staff", "bow"])


func test_underscore_keys_never_count_as_duplicates_or_overwrite_the_base() -> void:
	var root := _put("survivor/skills.json", {"_doc": "base", "_note": "base note"})
	_put("survivor/skills/beginner.json", {"_doc": "beginner doc", "_note": "x", "skills": {"_n": {}, "a": {}}})
	_put("survivor/skills/magician.json", {"_doc": "magician doc", "skills": {"_n": {}, "b": {}}})
	var errors := PackedStringArray()
	var d := DataRepo.load_split("skills", root, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_eq(d._doc, "base")
	assert_eq(d._note, "base note")
	assert_eq(d.skills.keys(), ["a", "b"])


func test_an_unreadable_fragment_and_a_stray_key_are_reported() -> void:
	var root := _put("survivor/skills.json", {"_doc": "d"})
	var path := root.path_join("survivor/skills/beginner.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ not json")
	file.close()
	_put("survivor/skills/magician.json", {"skill": {"typo": {}}, "skills": {"ok": {}}})
	var errors := PackedStringArray()
	var d := DataRepo.load_split("skills", root, errors)
	assert_eq(errors.size(), 2, "%s" % [errors])
	assert_true("beginner.json" in errors[0])
	assert_true("'skill'" in errors[1])
	assert_true(d.skills.has("ok"))


func test_load_all_merges_the_split_keys_and_a_missing_base_is_one_error() -> void:
	var root := test_dir(WORK)
	var errors := PackedStringArray()
	var d := DataRepo.load_all(root, errors)
	assert_eq(errors.size(), DataRepo.FILES.size(), "every missing base reported once, no fragment errors")
	assert_true(d.skills.is_empty(), "a missing base gives {}")
	_put("survivor/skills.json", {"_doc": "d"})
	_put("survivor/skills/beginner.json", {"skills": {"a": {}}})
	errors = PackedStringArray()
	d = DataRepo.load_all(root, errors)
	assert_eq(errors.size(), DataRepo.FILES.size() - 1)
	assert_eq(d.skills.skills.keys(), ["a"])


func test_json_names_are_discovered_and_non_json_files_are_reported() -> void:
	var root := _put("survivor/skills/beginner.json", {})
	_put("survivor/skills/rogue.json", {})
	_put("survivor/upgrades/magician.json", {})
	_put("survivor/upgrades/mage.json", {})
	_put("survivor/shops/notes.txt", {})
	var unknown := DataRepo.unknown_line_files(root)
	assert_eq(Array(unknown), ["survivor/shops/notes.txt"])


func test_the_shipped_fragment_directories_hold_only_json_files() -> void:
	assert_eq(Array(DataRepo.unknown_line_files()), [], "a fragment file must be named after a discovered line")


func test_shipped_data_has_no_duplicates_and_places_entries_by_line() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	var root := DataRepo.DATA_ROOT
	# skills: book 000 in beginner, 2xx in magician; 220/221/222-book skills may live in il_arch_mage (#321: the I/L
	# skills ship in il_arch_mage.json)
	for line in ["beginner", "magician"]:
		var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", line, root))
		assert_false(frag.skills.is_empty(), "skills/%s.json has entries" % line)
		for key: String in frag.skills:
			assert_eq(String(frag.skills[key].book) == "000", line == "beginner", "%s in %s" % [key, line])
	var il_frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "il_arch_mage", root))
	for key: String in il_frag.skills:
		assert_true(String(il_frag.skills[key].book) in ["220", "221", "222"], "%s in il_arch_mage" % key)
	# Pirate tree (B2 #414): the 510/511/512 books may live in buccaneer.json, 500 stays valid in pirate.json (and 520, the
	# gun book, which is not a Buccaneer skill); a 511 or 512 skill is never in pirate.json.
	var bucc_frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "buccaneer", root))
	for key: String in bucc_frag.skills:
		assert_true(String(bucc_frag.skills[key].book) in ["500", "510", "511", "512"], "%s in buccaneer" % key)
	var pirate_frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "pirate", root))
	for key: String in pirate_frag.skills:
		assert_true(String(pirate_frag.skills[key].book) in ["500", "510", "520"], "%s in pirate" % key)
	# cards: no skill or a common passive's -> common, otherwise magician; #284 deleted the Beginner cards (no
	# upgrades/beginner.json)
	assert_false(FileAccess.file_exists(DataRepo.fragment_path("upgrades", "beginner", root)))
	for line in ["common", "magician"]:
		var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("upgrades", line, root))
		# Spec #289: the common fragment holds the common passives' cards (they carry no job); the Magician's has the rest.
		assert_false(frag.cards.is_empty(), "upgrades/%s.json cards" % line)
		for c: Dictionary in frag.cards:
			var skill := String(c.get("skill", ""))
			var want := "common" if skill == "" or bool(d.skills.skills[skill].get("common_passive", false)) \
				else ("beginner" if String(d.skills.skills[skill].book) == "000" else "magician")
			assert_eq(line, want, "card %s" % c.id)
	assert_false(d.upgrades.has("cards") and d.upgrades.cards.is_empty())
	assert_eq(d.upgrades.fallback.id, "elixir", "the fallback card stays in the base")
	# equipment: wands (137) and staves (138) in magician; the merged list is sorted
	var magician: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", "magician", root))
	var common: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", "common", root))
	for id: Variant in common["items"]:
		assert_false(floori(float(id) / 10000.0) in [137, 138], "%d is a weapon, not common" % int(id))
	var wands := 0
	for id: Variant in magician["items"]:
		wands += 1 if floori(float(id) / 10000.0) in [137, 138] else 0
	assert_true(wands > 0)
	var sorted_items: Array = d.equipment_drops["items"].duplicate()
	sorted_items.sort()
	assert_eq(d.equipment_drops["items"], sorted_items, "ascending")
	var warrior: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", "warrior", root))
	var thief: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", "thief", root))
	var pirate: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", "pirate", root))
	var bowman: Dictionary = DataRepo.load_json(DataRepo.fragment_path("equipment_drops", "bowman", root))
	assert_eq(d.equipment_drops["items"].size(), common["items"].size() + warrior["items"].size() + magician["items"].size()
		+ bowman["items"].size() + thief["items"].size() + pirate["items"].size())
	# scrolls: armour slots in common, the Warrior's weapon kinds and shield, then wand and staff in magician
	assert_eq(d.scrolls.families.keys(), ["hat", "top", "bottom", "overall", "shoes", "gloves", "sword", "axe", "blunt",
		"two_handed_sword", "two_handed_axe", "two_handed_blunt", "spear", "polearm", "shield", "wand", "staff", "bow", "crossbow", "claw", "dagger", "knuckle", "gun"])
	assert_eq(d.shops.weapon_slots, ["sword", "axe", "blunt", "two_handed_sword", "two_handed_axe", "two_handed_blunt",
		"spear", "polearm", "wand", "staff", "bow", "crossbow", "claw", "dagger", "knuckle", "gun"], "line order: Warrior, Magician, Bowman, Thief, Pirate")


func test_new_alphabetically_earlier_class_does_not_move_shipped_lines() -> void:
	var root := _put("survivor/skills/hero.json", {"skills": {}})
	_put("survivor/skills/il_arch_mage.json", {"skills": {}})
	_put("survivor/jobs/bishop.json", {"jobs": {}})
	assert_eq(Array(DataRepo.lines(root)).slice(7), ["hero", "il_arch_mage", "bishop"])
