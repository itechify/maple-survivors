extends TestCase
## Headless full runs: 15 minutes at 60 Hz of stage henesys_hg1 with a simple kiting bot that always takes the first
## card and the first available job. Once on the synthetic multi-platform map with synthetic mob/skill imgs, once on
## the real 104040000 with the real mob/skill imgs read from the asset cache (FileAccess + JSON; SKIP without it).
##
## Asserts: mobs spawn all run long and the alive count grows, Three Snails kills mobs, EXP is collected, level >= 8
## and job 200 are reached before 15:00, and the run ends DEAD or CLEARED consistently.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const RUN_TICKS := 60 * 900


## Runs `w` to the end (or RUN_TICKS) and returns statistics.
func _run(w: RunWorld) -> Dictionary:
	var st := {
		"spawn_minutes": PackedInt32Array(), "alive": PackedInt32Array(), "killers": {}, "exp": 0, "job_time": -1.0,
		"lv8_time": -1.0, "levels": 0, "died": false, "cleared": false, "events": 0,
	}
	var spawn_minutes: PackedInt32Array = st.spawn_minutes
	spawn_minutes.resize(16)
	var alive: PackedInt32Array = st.alive
	var last_skill := {}
	var memo := {}
	for t in RUN_TICKS:
		RF.auto_choose(w)
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, RF.bot_input(w, memo))
		if t % 60 == 0:
			alive.append(w.swarm.alive_count())
		for e: Dictionary in w.drain_events():
			st.events += 1
			match String(e.type):
				"mob_spawned":
					spawn_minutes[mini(int(w.time / 60.0), 15)] += 1
				"mob_hit":
					last_skill[e.mob] = e.skill
				"mob_died":
					var k := String(last_skill.get(e.mob, ""))
					st.killers[k] = int(st.killers.get(k, 0)) + 1
				"pickup_collected":
					st.exp += int(e.exp)
				"level_up":
					st.levels += 1
					if int(e.level) == 8:
						st.lv8_time = w.time
				"job_changed":
					if int(e.job_id) == 200:
						st.job_time = w.time
				"player_died":
					st.died = true
				"stage_cleared":
					st.cleared = true
	RF.auto_choose(w)
	st["alive"] = alive
	st["spawn_minutes"] = spawn_minutes
	return st


func _assert_run(w: RunWorld, st: Dictionary, label: String) -> void:
	var alive: PackedInt32Array = st.alive
	var minutes := mini(int(w.time / 60.0), 15)
	print("%s: %.0f s, %s, level %d, job %d, kills %d, EXP %d, lv8 at %.0f s, job 200 at %.0f s, killers %s, alive/min %s" % [
		label, w.time, w.state_name(), w.player_state.level, w.player_state.job_id, w.kills, st.exp, st.lv8_time,
		st.job_time, st.killers, _per_minute(alive)])
	var spawn_minutes: PackedInt32Array = st.spawn_minutes
	for m in minutes:
		assert_true(spawn_minutes[m] > 0, "%s: mobs spawned in minute %d" % [label, m])
	var third := maxi(1, floori(alive.size() / 3.0))
	assert_true(_mean(alive, alive.size() - third, alive.size()) > _mean(alive, 0, third),
		"%s: the mean alive count grows (%s)" % [label, _per_minute(alive)])
	assert_true(int(st.killers.get("three_snails", 0)) > 20, "%s: Three Snails killed mobs %s" % [label, st.killers])
	assert_true(int(st.exp) > 0, "%s: EXP collected" % label)
	assert_true(w.player_state.level >= 8, "%s: level 8 reached" % label)
	assert_true(float(st.lv8_time) > 0.0 and float(st.lv8_time) < 900.0, "%s: level 8 before 15:00" % label)
	assert_true(float(st.job_time) > 0.0 and float(st.job_time) < 900.0, "%s: Magician before 15:00" % label)
	assert_eq(w.player_state.job_id, 200, label)
	assert_eq(st.levels, w.player_state.level - 1, "%s: one level_up event per level" % label)
	assert_true(w.state == RunWorld.DEAD or w.state == RunWorld.CLEARED, "%s: ended (%s)" % [label, w.state_name()])
	if w.state == RunWorld.DEAD:
		assert_true(st.died and not st.cleared, "%s: DEAD with player_died" % label)
		assert_true(w.player_state.dead)
		assert_eq(w.player_state.hp, 0)
	else:
		assert_true(st.cleared and not st.died, "%s: CLEARED with stage_cleared" % label)
		assert_near(w.time, 900.0, DT, "%s: the full duration" % label)
		assert_false(w.player_state.dead)
	assert_eq(w.swarm.lost_count, 0, "%s: no mob fell out of the world" % label)


func test_full_run_synthetic_map() -> void:
	var w := RunWorld.new(RF.setup("henesys_hg1", 2026))
	assert_true(w.warnings.is_empty(), "every pool mob has an img: %s" % [w.warnings])
	_assert_run(w, _run(w), "synthetic")


func test_full_run_real_map() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(data, "henesys_hg1", 2026, Vector2(800, 600), _img, _mob, missing)
	if not missing.is_empty():
		skip("cache lacks %s" % [missing])
		return
	var w := RunWorld.new(setup)
	assert_eq(w.fhm.count(), 181, "the real 104040000")
	assert_eq(w.mob_kinds.size(), 8, "the henesys_hg1 pool")
	assert_true(w.warnings.is_empty(), "%s" % [w.warnings])
	_assert_run(w, _run(w), "104040000")


func _img(path: String) -> Dictionary:
	var file := AssetCachePaths.resolve_cache_root().path_join(path + ".json")
	if not FileAccess.file_exists(file):
		return {}
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(file))
	return d if d is Dictionary else {}


## The mob img with info/link followed (none of the stage mobs has one in v83, but follow it anyway).
func _mob(id: int) -> Dictionary:
	var img := _img("Mob.wz/%07d.img" % id)
	var link: Variant = img.get("info", {}).get("link")
	if link != null and str(link) != "":
		var linked := _img("Mob.wz/%07d.img" % int(str(link)))
		if not linked.is_empty():
			linked = linked.duplicate()
			linked["info"] = img.info
			return linked
	return img


static func _mean(a: PackedInt32Array, from: int, to: int) -> float:
	var s := 0.0
	for i in range(from, to):
		s += a[i]
	return s / maxf(1.0, to - from)


static func _per_minute(alive: PackedInt32Array) -> String:
	var parts := PackedStringArray()
	for i in range(0, alive.size(), 60):
		parts.append(str(alive[i]))
	return ",".join(parts)


## One minute of each other stage: every pool mob has a kind, the run starts on a floor, mobs spawn and die.
func _short_run(w: RunWorld, label: String) -> void:
	assert_true(w.warnings.is_empty(), "%s: %s" % [label, w.warnings])
	assert_true(w.player.fh >= 0, "%s: the player starts on a floor" % label)
	assert_true(w.bounds.has_point(w.player.pos), "%s: inside the bounds" % label)
	var st := {"spawned": 0, "died": 0}
	var memo := {}
	for t in 60 * 60:
		RF.auto_choose(w)
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, RF.bot_input(w, memo))
		for e: Dictionary in w.drain_events():
			if e.type == "mob_spawned":
				st.spawned += 1
			elif e.type == "mob_died":
				st.died += 1
	assert_true(int(st.spawned) > 20, "%s: mobs spawned (%d)" % [label, st.spawned])
	assert_true(int(st.died) > 5, "%s: mobs died (%d)" % [label, st.died])
	assert_eq(w.swarm.lost_count, 0, label)


func test_other_stages_synthetic() -> void:
	for stage: String in ["hill_east_henesys", "tree_that_grew_1"]:
		_short_run(RunWorld.new(RF.setup(stage, 77)), stage)


func test_other_stages_real_maps() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	for stage: String in ["hill_east_henesys", "tree_that_grew_1"]:
		var missing := PackedStringArray()
		var setup := DataRepo.build_setup(data, stage, 77, Vector2(800, 600), _img, _mob, missing)
		assert_true(missing.is_empty(), "%s: the cache has every img (%s)" % [stage, missing])
		if missing.is_empty():
			_short_run(RunWorld.new(setup), stage + " (real)")
