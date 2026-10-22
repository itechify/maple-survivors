extends TestCase
## The three second-job Warrior character fixtures (spec #165 ticket #185): Fighter, Page and Spearman at Lv 34, each from a
## real headless Henesys bot round with the character invulnerable (`character_fixture.gd --god --seconds=600`; a Warrior
## bot dies at the first boss near Lv 12 and never advances otherwise). Reproduce one byte for byte with
##   ISOLATE=<name> MAPLE_SURVIVORS_CACHE=<cache> bash scripts/godot.sh --headless --path _scratch/godot_runs/<name>/game
##   --script res://tools/character_fixture.gd -- --out=<abs json> --revision=<_doc.revision> --job=<110|120|130> --god
##   --seconds=600 --label=spec165/ticket-185
## (regenerating is a one-minute round, so the suite only checks what the files hold and that a one-off round restores them).

const FIXTURES := {
	110: "res://tests/fixtures/characters/lv34_fighter_2nd.json",
	120: "res://tests/fixtures/characters/lv34_page_2nd.json",
	130: "res://tests/fixtures/characters/lv34_spearman_2nd.json",
}
## The Final Attack keys of each branch (GAME_DESIGN 7.9) and the weapon families its skills use.
const FINAL_ATTACKS := {
	110: ["final_attack_sword_fighter", "final_attack_axe"],
	120: ["final_attack_sword_page", "final_attack_bw"],
	130: ["final_attack_spear", "final_attack_polearm"],
}
const FAMILIES := {
	110: ["sword", "axe"],
	120: ["sword", "blunt"],
	130: ["spear", "polearm"],
}


func _load(job: int) -> Dictionary:
	var errors := PackedStringArray()
	var character := DataRepo.load_character(FIXTURES[job], errors)
	assert_eq(errors, PackedStringArray(), "fixture %d loads" % job)
	return character


func test_each_fixture_is_a_living_lv34_second_job_warrior_with_provenance() -> void:
	for job: int in FIXTURES:
		var character := _load(job)
		if character.is_empty():
			continue
		assert_eq(int(character.format), CharacterSnapshot.FORMAT)
		assert_eq(int(character.job_id), job, "job %d" % job)
		assert_between(float(character.level), 30.0, 39.0, "approximately level 34")
		var doc: Dictionary = character._doc
		assert_eq(int(doc.forced_branch), job)
		assert_eq(int(doc.seed), 1)
		assert_eq(doc.policy, "bot")
		assert_eq(DataRepo.canonical_stage_key(String(doc.stage)), "henesys")
		assert_eq(doc.outcome, "TIMEOUT", "a capped, living round")
		assert_eq(doc.invulnerable, true, "the Warrior bot cannot reach Lv 30 otherwise")
		assert_eq(String(doc.revision).length(), 40, "the full generation revision")
		assert_eq(doc.branch, "spec165/ticket-185")


func test_each_fixture_holds_its_branch_skills_and_a_weapon_it_can_use() -> void:
	for job: int in FIXTURES:
		var character := _load(job)
		if character.is_empty():
			continue
		var owned: Array = FINAL_ATTACKS[job].filter(func(key: String) -> bool: return character.skills.has(key))
		assert_false(owned.is_empty(), "job %d learned a Final Attack of its own branch" % job)
		for key: String in character.skills:
			assert_false(key.begins_with("final_attack_") and not (key in FINAL_ATTACKS[job]),
				"%s belongs to another branch than %d" % [key, job])
		assert_true(character.skills.has("power_strike") and character.skills.has("slash_blast"),
			"the first-job attacks carry over (carry_jobs)")
		var weapon := int(character.equipment.worn.weapon.id)
		assert_true(WeaponInfo.family(weapon) in FAMILIES[job], "weapon %d (%s) is of the branch's families" % [weapon, WeaponInfo.family(weapon)])


func test_a_one_off_round_restores_each_fixture_without_warnings() -> void:
	if not require_cache():
		return
	for job: int in FIXTURES:
		var path := ProjectSettings.globalize_path(test_dir("warrior2_%d.json" % job))
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		DirAccess.copy_absolute(ProjectSettings.globalize_path(FIXTURES[job]), path)
		var output: Array = []
		var status := OS.execute(OS.get_executable_path(), ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--script", "res://tools/balance_run.gd", "--",
			"--stage=sleepywood", "--seed=2", "--cap=0.016666667", "--character=" + path], output, true)
		assert_eq(status, 0, "job %d round runs" % job)
		var record := {}
		for line: String in "\n".join(output).split("\n"):
			if line.begins_with("BALANCE "):
				record = JSON.parse_string(line.substr(8))
		assert_false(record.is_empty(), "job %d: balance tool produced a record" % job)
		if record.is_empty():
			continue
		var character: Dictionary = DataRepo.load_json(FIXTURES[job])
		assert_eq(int(record.job), job)
		assert_eq(int(record.level), int(character.level))
		assert_eq(record.missing, [])
		assert_eq(PackedStringArray(record.warnings), PackedStringArray())
		for key: String in character.skills:
			assert_eq(int(record.skills.get(key, 0)), int(character.skills[key].rank), "%s rank restored" % key)
