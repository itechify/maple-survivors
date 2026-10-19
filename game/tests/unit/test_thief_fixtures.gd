extends TestCase
## Real-cache Thief diagnostic fixtures: provenance, branch/path identity, and playable snapshot restoration (#215).

const ASSASSIN := "res://tests/fixtures/characters/assassin_2nd.json"
const BANDIT := "res://tests/fixtures/characters/bandit_2nd.json"


func test_fixtures_document_reproduction_and_diagnostic_aids() -> void:
	for spec: Array in [[ASSASSIN, 410, "claw"], [BANDIT, 420, "dagger"]]:
		var errors := PackedStringArray()
		var character := DataRepo.load_character(spec[0], errors)
		assert_eq(errors, PackedStringArray(), spec[0])
		if character.is_empty():
			return
		var doc: Dictionary = character._doc
		assert_eq(int(doc.forced_branch), spec[1])
		assert_eq(doc.forced_path, spec[2])
		assert_eq(doc.policy, "bot")
		assert_eq(doc.stage, "henesys_hg1")
		assert_eq(int(doc.seed), 1)
		assert_eq(doc.branch, "spec167/ticket-215")
		assert_eq(String(doc.revision).length(), 40)
		assert_true(String(doc.diagnostic).contains("RunWorld.god"), "record invulnerability")
		assert_true(String(doc.source).contains("600 s cap"), "record the exact fixture command's cap")
		assert_eq(float(doc.exp_mult), 3.0, "record the diagnostic EXP multiplier")
		assert_false(String(doc.diagnostic_exp).contains("knuckle"), "the aid description must describe this Thief run")
		assert_eq(int(character.format), CharacterSnapshot.FORMAT)
		assert_eq(int(character.job_id), spec[1])
		assert_eq(character.weapon_path, spec[2])
		assert_true(int(character.level) >= 30, "second job reached")
		assert_eq(WeaponInfo.family(int(character.equipment.worn.weapon.id)), spec[2])
		var attack := "drain" if spec[1] == 410 else "savage_blow"
		assert_true(character.skills.has(attack), "a real branch attack learned: " + attack)


func test_fixtures_restore_all_skills_and_play_without_warnings() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	for path: String in [ASSASSIN, BANDIT]:
		var errors := PackedStringArray()
		var character := DataRepo.load_character(path, errors)
		assert_eq(errors, PackedStringArray(), path)
		if character.is_empty():
			lib.free()
			return
		var missing := PackedStringArray()
		var setup := DataRepo.build_setup(DataRepo.load_all(), "henesys_hg1", 215, Vector2(800, 600),
			func(img: String) -> Dictionary: return lib.img(img).root if lib.img(img) != null else {},
			func(id: int) -> Dictionary: return lib.mob_root(id), missing, character)
		assert_eq(missing, PackedStringArray())
		var w := RunWorld.new(setup)
		assert_eq(w.progression.job_id, int(character.job_id))
		assert_eq(w.progression.level, int(character.level))
		assert_eq(w.weapon_path, character.weapon_path)
		assert_eq(w.weapon_id(), int(character.equipment.worn.weapon.id))
		var restored: Dictionary = w.character_snapshot().skills
		assert_eq(restored.size(), character.skills.size(), "all learned skills survive restoration")
		assert_eq(w.character_snapshot().skill_order, character.skill_order, "casting order survives restoration")
		for key: String in character.skills:
			assert_eq(w.loadout.rank(key), int(character.skills[key].rank), key)
			var mods: Dictionary = character.skills[key].mods
			assert_eq(restored[key].mods.keys(), mods.keys(), "modifier fields: " + key)
			for stat: String in mods:
				for component in 2:
					assert_near(float(restored[key].mods[stat][component]), float(mods[stat][component]), 0.000001,
						"fixture JSON rounds modifiers to six decimal places: " + key + "/" + stat)
		for tick in 600:
			w.step(1.0 / 60.0, MoveInput.new())
		assert_eq(w.warnings, PackedStringArray())
	lib.free()
