extends TestCase
## Spec #447 "Bosses" (ticket #452, tier C owner rule): no boss appears twice across the progression. Every scheduled
## boss `mob_id` and `final_form` is distinct, and so are their names. A final form is the same boss as its shell, so
## the two may share a name (King Clang's 5220001 and 5220000) but no other encounter may use it.

## Expected rosters, in map order (a shell is listed with its final form).
const ROSTERS := {
	"henesys": [[2220000], [6130101], [9400205]],
	"ellinia": [[3300008], [3300005], [5220002]],
	"perion": [[5220001, 5220000], [3220000], [4090000]],
	"kerning": [[9300003], [5090000], [6220000]],
	"sleepywood": [[6300005], [8220009], [8130100]],
	"omega_sector": [[4240000], [5120100], [6220001]],
}


## Every scheduled boss of the progression's stages, in order: {label, ids: [mob_id, final_form?]}.
func _encounters(stages_file: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for key: Variant in stages_file.get("progression", []):
		var maps: Array = stages_file.get("stages", {}).get(key, {}).get("maps", [])
		for i in maps.size():
			var boss: Dictionary = maps[i].get("boss", {})
			var ids: Array[int] = [int(boss.get("mob_id", 0))]
			if boss.has("final_form"):
				ids.append(int(boss.final_form))
			out.append({"label": "%s map %d" % [key, i + 1], "ids": ids})
	return out


## One message per id that two encounters (or one encounter's shell and form) schedule.
func _id_errors(encounters: Array[Dictionary]) -> PackedStringArray:
	var errors := PackedStringArray()
	var seen := {}
	for e: Dictionary in encounters:
		for id: int in e.ids:
			if seen.has(id):
				errors.append("boss %d is scheduled twice (%s and %s)" % [id, seen[id], e.label])
			seen[id] = e.label
	return errors


## One message per name two different encounters share, or a scheduled id without a name. `names` maps mob id -> name.
func _name_errors(encounters: Array[Dictionary], names: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	var owner_of := {}
	for e: Dictionary in encounters:
		for id: int in e.ids:
			var boss_name := String(names.get(id, "")).strip_edges()
			if boss_name.is_empty():
				errors.append("boss %d (%s) has no name" % [id, e.label])
			elif owner_of.has(boss_name) and owner_of[boss_name] != e.label:
				errors.append("boss name '%s' is used by %s and %s" % [boss_name, owner_of[boss_name], e.label])
			else:
				owner_of[boss_name] = e.label
	return errors


func _survivor_names(ids: Array, mobs: Dictionary) -> Dictionary:
	var names := {}
	for id: int in ids:
		names[id] = String(mobs.get(str(id), {}).get("name", ""))
	return names


func _all_ids(encounters: Array[Dictionary]) -> Array:
	var ids: Array = []
	for e: Dictionary in encounters:
		ids.append_array(e.ids)
	return ids


func test_shipped_progression_schedules_each_boss_once() -> void:
	var data := DataRepo.load_all()
	var encounters := _encounters(data.stages)
	assert_eq(encounters.size(), 3 * data.stages.progression.size(), "every region of the progression has three bosses")
	assert_eq(_id_errors(encounters), PackedStringArray(), "no mob_id or final_form is scheduled twice")
	assert_eq(_name_errors(encounters, _survivor_names(_all_ids(encounters), data.mobs.mobs)), PackedStringArray(),
		"no two encounters share a mobs.json name")


func test_every_region_keeps_its_expected_bosses() -> void:
	var stages: Dictionary = DataRepo.load_all().stages.stages
	for key: String in ROSTERS:
		var got: Array = []
		for entry: Dictionary in DataRepo.stage_bosses(stages[key]):
			var ids: Array = [int(entry.mob_id)]
			if entry.has("final_form"):
				ids.append(int(entry.final_form))
			got.append(ids)
		assert_eq(got, ROSTERS[key], "%s bosses in map order" % key)


func test_king_clang_shell_and_form_are_one_boss_with_one_name() -> void:
	var data := DataRepo.load_all()
	var mobs: Dictionary = data.mobs.mobs
	assert_eq(String(mobs["5220001"].name), String(mobs["5220000"].name), "the shell and its form share a name")
	var entry: Dictionary = DataRepo.stage_bosses(data.stages.stages.perion)[0]
	assert_eq(int(entry.mob_id), 5220001, "the shell is scheduled")
	assert_eq(int(entry.final_form), 5220000, "its final form takes over")
	for id: int in [5220001, 5220000]:
		assert_has(data.balance.mob_skills.enabled_ids, float(id), "%d casts its kit" % id)


func test_a_repeated_id_fails() -> void:
	var stages_file: Dictionary = DataRepo.load_all().stages.duplicate(true)
	stages_file.stages.ellinia.maps[0].boss.mob_id = 2220000 # Mano, also Henesys map 1
	var errors := _id_errors(_encounters(stages_file))
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("2220000") and errors[0].contains("henesys map 1") and errors[0].contains("ellinia map 1"),
		"names the id and both maps: %s" % errors)


func test_a_final_form_that_repeats_another_boss_fails() -> void:
	var stages_file: Dictionary = DataRepo.load_all().stages.duplicate(true)
	stages_file.stages.perion.maps[0].boss.final_form = 3220000 # Stumpy, Perion map 2
	var errors := _id_errors(_encounters(stages_file))
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("3220000") and errors[0].contains("perion map 2"), "names the id: %s" % errors)


func test_a_different_id_with_the_same_name_fails() -> void:
	var data := DataRepo.load_all()
	var stages_file: Dictionary = data.stages.duplicate(true)
	stages_file.stages.ellinia.maps[0].boss.mob_id = 9300187 # an unscheduled id ...
	var names := _survivor_names(_all_ids(_encounters(stages_file)), data.mobs.mobs)
	names[9300187] = "Mano" # ... named like Henesys's boss
	var errors := _name_errors(_encounters(stages_file), names)
	assert_eq(errors.size(), 1)
	assert_true(errors[0].contains("'Mano'") and errors[0].contains("henesys map 1") and errors[0].contains("ellinia map 1"),
		"names the name and both maps: %s" % errors)


func test_a_scheduled_boss_without_a_name_fails() -> void:
	var encounters: Array[Dictionary] = [{"label": "x map 1", "ids": [1]}]
	assert_eq(_name_errors(encounters, {}).size(), 1)
	assert_eq(_name_errors(encounters, {1: "  "}).size(), 1, "blank names count as missing")


func test_a_shell_may_share_its_forms_name_but_nobody_else_may() -> void:
	var encounters: Array[Dictionary] = [{"label": "a", "ids": [10, 11]}, {"label": "b", "ids": [12]}]
	assert_eq(_name_errors(encounters, {10: "Clang", 11: "Clang", 12: "Lorang"}), PackedStringArray())
	assert_eq(_name_errors(encounters, {10: "Clang", 11: "Clang", 12: "Clang"}).size(), 1)


## Cache-backed variant: the same rule on the canonical String.wz names, which the boss bar shows.
func test_string_wz_names_are_distinct() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var encounters := _encounters(DataRepo.load_all().stages)
	var names := {}
	for id: int in _all_ids(encounters):
		names[id] = lib.string_name("Mob", id)
	assert_eq(_name_errors(encounters, names), PackedStringArray(), "String.wz names: %s" % names)
	lib.free()
