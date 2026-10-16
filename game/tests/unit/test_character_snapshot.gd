extends TestCase
## Round-boundary carry, resets and determinism through RunWorld's public interface.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_character_survives_round_boundary_with_full_pools() -> void:
	var w := RF.quiet_world(400.0, 1)
	# Earn levels and AP through the same pickup/window interface as a real round.
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(35) + 17, 4000019)
	for tick in 120:
		BotInput.auto_choose(w, false, 210)
		w.step(DT, MoveInput.new())
	BotInput.auto_choose(w, false, 210)
	assert_eq(w.progression.level, 35)
	assert_eq(w.progression.job_id, 210)
	w.learn_skill("fire_arrow")
	w.loadout.set_rank("fire_arrow", 7)
	var old_count := int(w.loadout.stats("fire_arrow").count)
	w.loadout.add_skill_mod("fire_arrow", "count", "add", 2.0)
	w.loadout.add_skill_mod("fire_arrow", "cooldown", "mul", 0.88)
	w.loadout.add_player_mod("fortune", "add", 12.0)
	w.loadout.add_player_mod("max_hp", "mul", 1.1)
	w.refresh_player_stats()
	w.upgrade_potion("hp", 2000002)
	w.potions.add("hp", 9)
	w.learn_skill("teleport_fp")
	w.spend_mp(13)
	var snapshot := w.character_snapshot()
	var setup := RF.setup("quiet", 2, RF.quiet_data())
	setup.character = snapshot
	var next := RunWorld.new(setup)
	assert_eq(next.character_snapshot(), snapshot, "every carried field, including partial EXP and growth")
	assert_eq(next.player_state.hp, next.player_state.max_hp)
	assert_eq(next.player_state.mp, next.player_state.max_mp)
	assert_eq(next.player_state.fortune, 12.0)
	assert_eq(next.progression.exp, 17)
	assert_eq(next.loadout.rank("fire_arrow"), 7)
	assert_eq(next.loadout.stats("fire_arrow").count, old_count + 2)


func test_json_character_and_same_seed_replay_identically_for_three_minutes() -> void:
	var source := RF.quiet_world()
	source.change_job(210)
	source.learn_skill("fire_arrow")
	source.learn_skill("teleport_fp")
	source.loadout.set_rank("fire_arrow", 7)
	source.loadout.add_skill_mod("fire_arrow", "cooldown", "mul", 0.88)
	source.character_look = {"skin": 0, "face": 20000, "hair": 30030, "equips": [1040002]}
	source.beginner_weapon = 1302000
	var character := source.character_snapshot()
	character.level = 35
	character.exp = 17
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(character))
	var setup := RF.with_basic_attack(RF.setup("henesys_hg1", 2026))
	setup.character = character
	var a := RunWorld.new(setup)
	setup.character = parsed
	var b := RunWorld.new(setup)
	a.god = true
	b.god = true
	assert_eq(a.character_snapshot(), b.character_snapshot())
	assert_eq(a.player_state, b.player_state)
	assert_eq(b.beginner_weapon, 1302000)
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
	parsed.look.equips.append(1072001)
	var copy := b.character_snapshot()
	copy.look.equips.clear()
	assert_eq(b.character_snapshot().look.equips, [1040002])


func test_round_start_resets_buffs_slow_timers_and_every_map_pool() -> void:
	var w := preload("res://tests/fixtures/mano_fixtures.gd").world()
	# Mano casts its real-shaped area Slow through the normal boss skill entry point.
	for tick in 30:
		w.step(DT, MoveInput.new())
	w.time = 16.0
	w.mob_skills.step(w)
	w.change_job(210)
	w.learn_skill("nimble_feet")
	w.learn_skill("teleport_fp")
	w.start_buff("nimble_feet", w.loadout.stats("nimble_feet"))
	w.runner.cooldowns["nimble_feet"] = 60.0
	w.upkeep.start_action("alert2", 0.8)
	w.upkeep.invincible_t = 1.5
	w.basic.cooldown = 0.7
	w.spend_mp(1)
	w.pickups.spawn(w.player.pos, 19, 4000019)
	w.spawn_potion("hp", w.player.pos, 3)
	var input := MoveInput.new()
	input.teleport_pressed = true
	w.step(DT, input)
	assert_false(w.buffs.snapshot().is_empty(), "source buff active")
	assert_false(w.mob_skills.slow_state(w.time).is_empty(), "source slow active")
	assert_true(w.swarm.alive_count() > 0)
	var setup := RF.setup("quiet", 2026, RF.quiet_data())
	setup.character = w.character_snapshot()
	var next := RunWorld.new(setup)
	assert_eq(next.player_state.hp, next.player_state.max_hp)
	assert_eq(next.player_state.mp, next.player_state.max_mp)
	assert_eq(next.buffs.snapshot(), [])
	assert_eq(next.player_state.slow, {})
	assert_eq(next.runner.cooldowns, {})
	assert_eq(next.basic.cooldown, 0.0)
	assert_eq(next.upkeep.cast_left, 0.0)
	assert_eq(next.upkeep.invincible_t, 0.0)
	assert_eq(next.swarm.alive_count(), 0)
	assert_eq(next.pickups.active_count(), 0)
	assert_eq(next.projectiles.active_count(), 0)
	assert_true(next.bosses.records.is_empty())
	assert_eq(next.time, 0.0)
	assert_eq(next.kills, 0)
	assert_true(next.potions.collected.hp == 0 and next.potions.used.hp == 0)
	RF.place_player(next, 400)
	next.step(DT, input)
	var blinks := next.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "teleport")
	assert_eq(blinks.size(), 2, "learned manual skill can cast immediately in the new round")


func test_pending_choices_fail_loudly_in_child_process() -> void:
	for mode: String in ["job", "card", "queue", "reward", "advancement"]:
		var output: Array = []
		var status := OS.execute(OS.get_executable_path(), ["--headless", "--path",
			ProjectSettings.globalize_path("res://"), "--script", "res://tests/fixtures/pending_character_probe.gd",
			"--", mode], output, true)
		assert_eq(status, 0)
		var log := "\n".join(output)
		assert_true(log.contains("RunWorld.character_snapshot: a character choice is pending"), mode + " is loud")
		assert_true(log.contains("PENDING_SNAPSHOT_EMPTY=true"), mode + " returns no lossy snapshot")


func test_character_file_rejects_missing_malformed_and_unknown_formats() -> void:
	var errors := PackedStringArray()
	assert_eq(DataRepo.load_character(test_dir("absent.json"), errors), {})
	assert_eq(errors.size(), 1)
	var path := test_dir("invalid.json")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	for text: String in ["{", "[]", '{"format": 2}', '{"format": 1, "level": 35}']:
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string(text)
		file.close()
		errors.clear()
		assert_eq(DataRepo.load_character(path, errors), {})
		assert_eq(errors.size(), 1, "invalid character never silently starts fresh")
