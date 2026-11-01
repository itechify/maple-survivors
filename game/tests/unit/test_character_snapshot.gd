extends TestCase
## Round-boundary carry, resets and determinism through RunWorld's public interface.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_json_character_and_same_seed_replay_identically_for_three_minutes() -> void:
	var source := RF.quiet_world()
	source.character_look = {"skin": 0, "face": 20000, "hair": 30030}
	var character := source.character_snapshot()
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(character))
	var setup := RF.with_basic_attack(RF.setup("henesys", 2026))
	setup.character = character
	var a := RunWorld.new(setup)
	setup.character = parsed
	var b := RunWorld.new(setup)
	a.god = true
	b.god = true
	assert_eq(a.character_snapshot(), b.character_snapshot())
	assert_eq(a.player_state, b.player_state)
	assert_eq(b.weapon_id(), 1372005)
	var memo_a := {}
	var memo_b := {}
	for tick in 10800:
		BotInput.auto_choose(a)
		BotInput.auto_choose(b)
		a.step(DT, BotInput.decide(a, memo_a))
		b.step(DT, BotInput.decide(b, memo_b))
		assert_eq(JSON.stringify(a.drain_events(), "", false, true),
			JSON.stringify(b.drain_events(), "", false, true), "event bytes at tick %d" % tick)
		if not failures.is_empty():
			return
	BotInput.auto_choose(a)
	BotInput.auto_choose(b)
	assert_eq(a.character_snapshot(), b.character_snapshot())
	assert_eq(a.player_state, b.player_state)
	# Snapshot and input are detached from the live character and one another.
	parsed.look.hair = 30000
	parsed.equipment.worn.erase("weapon")
	var copy := b.character_snapshot()
	copy.equipment.worn.clear()
	copy.look.clear()
	assert_eq(b.character_snapshot().look, {"skin": 0, "face": 20000, "hair": 30030})
	assert_eq(Equipment.worn_ids(b.character_snapshot().equipment.worn), [1040002, 1060002, 1072001, 1372005])


func test_round_start_resets_buffs_slow_timers_and_every_map_pool() -> void:
	var w := preload("res://tests/fixtures/mano_fixtures.gd").world()
	# Mano casts its real-shaped area Slow through the normal boss skill entry point.
	for tick in 30:
		w.step(DT, MoveInput.new())
	w.time = 16.0
	w.mob_skills.step(w)
	w.learn_skill("nimble_feet")
	w.start_buff("nimble_feet", w.loadout.stats("nimble_feet"))
	w.runner.cooldowns["nimble_feet"] = 60.0
	w.upkeep.start_action("alert2", 0.8)
	w.upkeep.invincible_t = 1.5
	w.pickups.spawn(w.player.pos, 19, 4000019)
	w.drink_potion("hp")
	var input := MoveInput.new()
	input.press_skill("teleport")
	w.step(DT, input)
	assert_false(w.buffs.snapshot().is_empty(), "source buff active")
	assert_false(w.mob_skills.slow_state(w.time).is_empty(), "source slow active")
	assert_true(w.swarm.alive_count() > 0)
	var setup := RF.setup("quiet", 2026, RF.quiet_data())
	setup.character = w.character_snapshot()
	var next := RunWorld.new(setup)
	assert_eq(next.player_state.hp, next.player_state.max_hp)
	assert_eq(next.buffs.snapshot(), [])
	assert_eq(next.player_state.slow, {})
	assert_eq(next.runner.cooldowns, {})
	assert_eq(next.upkeep.cast_left, 0.0)
	assert_eq(next.upkeep.invincible_t, 0.0)
	assert_eq(next.swarm.alive_count(), 0)
	assert_eq(next.pickups.active_count(), 0)
	assert_eq(next.projectiles.active_count(), 0)
	assert_true(next.bosses.records.is_empty())
	assert_eq(next.time, 0.0)
	assert_eq(next.kills, 0)
	assert_true(next.potions.is_ready("hp") and next.potions.used.hp == 0)
	RF.place_player(next, 400)
	next.step(DT, input)
	var blinks := next.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "teleport")
	assert_eq(blinks.size(), 2, "learned manual skill can cast immediately in the new round")


func test_a_snapshot_is_always_available_even_with_choices_pending() -> void:
	# Nothing a choice would change is saved (no level, skill or card), so a death or Quit round mid-choice loses nothing.
	for mode: String in ["card", "queue", "reward"]:
		var w := RF.quiet_world()
		match mode:
			"card": w.state = RunWorld.CHOOSING_UPGRADE
			"queue": w.progression.queue.append(2)
			"reward": w.pending_bonus_choices = 1
		w.mesos = 55
		var character := w.character_snapshot()
		assert_eq(character.mesos, 55, mode)
		assert_eq(CharacterSnapshot.validation_error(character), "", mode)


func test_character_file_rejects_missing_malformed_and_unknown_formats() -> void:
	var errors := PackedStringArray()
	assert_eq(DataRepo.load_character(test_dir("absent.json"), errors), {})
	assert_eq(errors.size(), 1)
	var path := test_dir("invalid.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	for text: String in ["{", "[]", '{"format": 2}', '{"format": 3}', '{"format": 4}', '{"format": 1, "level": 35}']:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		errors.clear()
		assert_eq(DataRepo.load_character(path, errors), {})
		assert_eq(errors.size(), 1, "invalid character never silently starts fresh")


## Creation-item info shaped like v83 Character.wz (incPDD/tuc as in the real items; weapon stats invented).
const CREATION_INFO := {1041011: {"incPDD": 3, "tuc": 7}, 1061008: {"incPDD": 2, "tuc": 7},
	1072038: {"incPDD": 2, "tuc": 5}, 1040002: {"incPDD": 3, "tuc": 7}, 1060002: {"incPDD": 2, "tuc": 7},
	1072001: {"incPDD": 2, "tuc": 5}, 1322005: {"incPAD": 19, "attackSpeed": 5, "tuc": 7},
	1302000: {"incPAD": 17, "attackSpeed": 4, "tuc": 7}, 1372005: {"incPAD": 15, "incMAD": 23, "tuc": 7}}


func _creation_setup() -> Dictionary:
	var setup := RF.setup("quiet", 3, RF.quiet_data())
	setup.equipment_info = CREATION_INFO.duplicate(true)
	return setup


## The spec #32 shape of a character: no equipment, scrolls or mesos; look equips and beginner_weapon instead.
func _format1(character: Dictionary, equips: Array, weapon: int) -> Dictionary:
	var old := character.duplicate(true)
	for key: String in ["equipment", "scrolls", "mesos"]:
		old.erase(key)
	old.format = 1
	old.look = {"skin": 3, "face": 21002, "hair": 31057}
	if not equips.is_empty():
		old.look["equips"] = equips
	old.beginner_weapon = weapon
	return old


func test_format_one_migrates_to_a_format_three_character_wearing_the_old_outfit() -> void:
	var source := RunWorld.new(_creation_setup())
	var current := source.character_snapshot()
	for spec: Array in [[0, [1041011, 1061008, 1072038], 1322005, [1041011, 1061008, 1072038, 1322005]],
			[210, [1041011, 1061008, 1072038], 1322005, [1041011, 1061008, 1072038, 1372005]],
			[0, [], 0, [1040002, 1060002, 1072001, 1302000]]]:
		var character := current.duplicate(true)
		character.job_id = spec[0]
		var old := _format1(character, spec[1], spec[2])
		assert_eq(CharacterSnapshot.validation_error(old), "", "format-1 tool files stay valid")
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(old))
		var expected := {"format": 3, "job_id": spec[0], "look": {"skin": 3, "face": 21002, "hair": 31057},
			"equipment": {"worn": Equipment.worn_from_ids(spec[3], CREATION_INFO), "inventory": []},
			"scrolls": {}, "mesos": 0, "cleared_regions": []}
		assert_eq(CharacterSnapshot.migrate(old, source.jobs, CREATION_INFO, _progression()), expected,
			"job %d: the outfit and resolved weapon are worn, nothing of the old build is kept" % spec[0])
		var setup := _creation_setup()
		setup.character = parsed
		var migrated := RunWorld.new(setup).character_snapshot()
		expected.job_id = spec[0]
		assert_eq(migrated, expected, "a world restored from it hands over the same character")
		assert_eq(DataRepo.character_look(old, DataRepo.load_all()).equips, spec[3],
			"a format-1 file draws exactly what it will wear")


func test_format_two_tool_files_migrate_to_format_three() -> void:
	var current := RunWorld.new(_creation_setup()).character_snapshot()
	var old := current.duplicate(true)
	old.erase("cleared_regions")
	old.merge({"format": 2, "level": 38, "exp": 12, "skills": {}, "skill_order": [], "player_mods": {}, "card_ranks": {},
		"attributes": {"str": 4, "dex": 4, "int": 4, "luk": 4}, "base_attributes": {"str": 4, "dex": 4, "int": 4, "luk": 4},
		"earned_ap": 0, "base_hp": 50.0, "fortune": 0.0, "base_fortune": 0.0, "mesos": 99, "pet": 5000000}, true)
	assert_eq(CharacterSnapshot.validation_error(old), "")
	var migrated := CharacterSnapshot.migrate(old, JobTree.from_data(DataRepo.load_all().jobs, {}), {}, _progression())
	var keys := migrated.keys()
	keys.sort()
	assert_eq(keys, ["cleared_regions", "equipment", "format", "job_id", "look", "mesos", "pet", "scrolls"])
	assert_eq(migrated.mesos, 99)
	assert_eq(migrated.cleared_regions, [])
	assert_eq(CharacterSnapshot.migrate(migrated, JobTree.from_data(DataRepo.load_all().jobs, {}), {}, _progression()), migrated,
		"migrating is idempotent")


func test_only_a_format_three_character_is_a_living_slot() -> void:
	var character := RunWorld.new(_creation_setup()).character_snapshot()
	var wrapper := {"name": "Maple70", "created": "2026-10-16", "rounds_played": 0, "character": character}
	assert_eq(SaveData.validation_error(wrapper), "")
	var old := _format1(character, [1041011, 1061008, 1072038], 1322005)
	assert_eq(CharacterSnapshot.validation_error(old), "", "a tool file of format 1 still validates")
	wrapper.character = old
	assert_ne(SaveData.validation_error(wrapper), "", "but a slot holds only format 3: older characters are history")
	var future := character.duplicate(true)
	future.format = 4
	assert_ne(CharacterSnapshot.validation_error(future), "")
	var bad := character.duplicate(true)
	bad.equipment.worn.top = bad.equipment.worn.weapon
	assert_ne(CharacterSnapshot.validation_error(bad), "", "an item in the wrong equip slot")
	for broken: Dictionary in [{"mesos": null}, {"scrolls": {"2040002": -1}}, {"cleared_regions": "henesys"}, {"cleared_regions": [1]},
			{"cleared_regions": ["henesys", "henesys"]}, {"cleared_regions": [""]},
			{"job_id": -1}, {"look": []}, {"cash": {"nowhere": 1}}, {"pet": -1}]:
		bad = character.duplicate(true)
		bad.merge(broken, true)
		assert_ne(CharacterSnapshot.validation_error(bad), "", str(broken))
	bad = character.duplicate(true)
	bad.erase("mesos")
	assert_ne(CharacterSnapshot.validation_error(bad), "")


func _progression() -> Array:
	return DataRepo.load_all().stages.progression


## A format-3 character with the legacy `tiers_unlocked` counter instead of the cleared set.
func _legacy(tiers: int) -> Dictionary:
	var legacy := RunWorld.new(_creation_setup()).character_snapshot()
	legacy.erase("cleared_regions")
	legacy["tiers_unlocked"] = tiers
	return legacy


func test_a_fresh_snapshot_unlocks_only_the_first_region() -> void:
	var fresh := RunWorld.new(_creation_setup()).character_snapshot()
	assert_eq(fresh.cleared_regions, [])
	assert_eq(CharacterSnapshot.unlocked_keys(_progression(), fresh.cleared_regions), ["henesys"])


func test_tiers_unlocked_one_migrates_to_nothing_cleared() -> void:
	var legacy := _legacy(1)
	assert_eq(CharacterSnapshot.validation_error(legacy), "", "a stored legacy character still validates")
	var migrated := CharacterSnapshot.migrate(legacy, JobTree.from_data(DataRepo.load_all().jobs, {}), {}, _progression())
	assert_eq(migrated.cleared_regions, [])
	assert_false(migrated.has("tiers_unlocked"), "the counter is dropped")
	assert_eq(CharacterSnapshot.validation_error(migrated), "")


func test_tiers_unlocked_two_migrates_to_the_first_four_regions_cleared() -> void:
	var migrated := CharacterSnapshot.migrate(_legacy(2), JobTree.from_data(DataRepo.load_all().jobs, {}), {}, _progression())
	assert_eq(migrated.cleared_regions, ["ellinia", "henesys", "kerning", "perion"])
	assert_false(migrated.has("tiers_unlocked"))
	assert_eq(CharacterSnapshot.unlocked_keys(_progression(), migrated.cleared_regions),
		["henesys", "ellinia", "perion", "kerning", "sleepywood"], "Sleepywood stays reachable")
	assert_eq(CharacterSnapshot.with_cleared_regions(_legacy(2), _progression()).cleared_regions, migrated.cleared_regions)


func test_every_committed_tier_two_fixture_loads_with_sleepywood_unlocked() -> void:
	var dir := "res://tests/fixtures/characters/"
	var seen := 0
	for file_name in DirAccess.get_files_at(dir):
		if not (file_name.ends_with("_t2.json") or file_name == "fp_arch_mage.json"):
			continue
		seen += 1
		var character := SceneFlow.migrated_character(DataRepo.load_json(dir + file_name), Callable())
		assert_eq(CharacterSnapshot.validation_error(character), "", file_name)
		assert_true(CharacterSnapshot.is_unlocked(_progression(), character.cleared_regions, "sleepywood"), file_name)
		assert_false(character.has("tiers_unlocked"), file_name)
	assert_true(seen >= 8, "the F/P, Hero, Dark Knight, Paladin, I/L, Bishop, Bowmaster and Buccaneer fixtures")


func test_a_snapshot_with_neither_field_is_invalid() -> void:
	var bad := RunWorld.new(_creation_setup()).character_snapshot()
	bad.erase("cleared_regions")
	assert_ne(CharacterSnapshot.validation_error(bad), "")
	bad["tiers_unlocked"] = 0
	assert_ne(CharacterSnapshot.validation_error(bad), "")
	bad["tiers_unlocked"] = 1.5
	assert_ne(CharacterSnapshot.validation_error(bad), "")
