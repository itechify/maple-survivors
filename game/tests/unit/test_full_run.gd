extends TestCase
## Headless full runs: 15 minutes at 60 Hz of stage henesys_hg1 with the autoplay bot (BotInput: kiting, climbing to
## drops above, the first available job and BotInput.pick_card_for's card). Once on the synthetic multi-platform map
## with synthetic mob/skill imgs, once on the real 104040000 with the real mob/skill imgs read from the asset cache
## (FileAccess + JSON; SKIP without it).
##
## Asserts: mobs spawn all run long and the alive count grows, Three Snails kills mobs, EXP is collected, level >= 8
## and job 200 are reached before 15:00, and the run ends DEAD or CLEARED consistently. The real map also checks the
## tuned pacing of docs/GAME_DESIGN.md 4.1 / 4.2 / 5 on PACING_SEEDS, the first two held-out seeds (never used for
## tuning, taken in order rather than for their results; tuning used seeds 1-60 and 2026; scripts/balance.sh 101..130
## shows the spread; 101 dies at 10:19, so 102, which clears, is what exercises the Lv 30 and late-crowd checks): Lv 8 at 2:30-3:45, Lv 10 at 3:00-5:30, Lv 30
## not before 10:00, under Lv 50 at the end, a death (if any) not before 10:00, a crowd of 200+ alive in the last
## minutes, mobs near the player and hits taken after 8:00.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const RUN_TICKS := 60 * 900
## Held-out seeds of the real-map pacing check (the first two of 101-130).
const PACING_SEEDS := [101, 102]


## Runs `w` to the end (or RUN_TICKS) and returns statistics.
func _run(w: RunWorld) -> Dictionary:
	var st := {
		"spawn_minutes": PackedInt32Array(), "alive": PackedInt32Array(), "killers": {}, "exp": 0, "job_time": -1.0,
		"lv8_time": -1.0, "lv10_time": -1.0, "lv30_time": -1.0, "levels": 0, "died": false, "cleared": false,
		"events": 0, "hits_after_8": 0, "near_after_8": 0,
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
			if w.time >= 480.0:
				st.near_after_8 = int(st.near_after_8) + _near(w)
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
					elif int(e.level) == 10:
						st.lv10_time = w.time
					elif int(e.level) == 30:
						st.lv30_time = w.time
				"player_hit":
					if w.time >= 480.0:
						st.hits_after_8 = int(st.hits_after_8) + 1
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
	print("%s: %.0f s, %s, level %d, job %d, kills %d, EXP %d, lv8 at %.0f s, lv10 at %.0f s, lv30 at %.0f s, job 200 at %.0f s, hits after 8:00 %d, killers %s, alive/min %s" % [
		label, w.time, w.state_name(), w.player_state.level, w.player_state.job_id, w.kills, st.exp, st.lv8_time,
		st.lv10_time, st.lv30_time, st.job_time, st.hits_after_8, st.killers, _per_minute(alive)])
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
	for pacing_seed: int in PACING_SEEDS:
		var missing := PackedStringArray()
		var setup := DataRepo.build_setup(data, "henesys_hg1", pacing_seed, Vector2(800, 600), _img, _mob, missing)
		if not missing.is_empty():
			skip("cache lacks %s" % [missing])
			return
		var w := RunWorld.new(setup)
		assert_eq(w.fhm.count(), 181, "the real 104040000")
		assert_eq(w.mob_kinds.size(), 8, "the henesys_hg1 pool")
		assert_true(w.warnings.is_empty(), "%s" % [w.warnings])
		var st := _run(w)
		var label := "104040000 seed %d" % pacing_seed
		_assert_run(w, st, label)
		_assert_pacing(w, st, label)


## The tuned pacing on the real map (docs/GAME_DESIGN.md 4.1, 5); windows with some slack for the bot.
func _assert_pacing(w: RunWorld, st: Dictionary, label: String) -> void:
	assert_between(float(st.lv8_time), 150.0, 225.0, "%s: Lv 8 (Magician) between 2:30 and 3:45" % label)
	assert_between(float(st.lv10_time), 180.0, 330.0, "%s: Lv 10 between 3:00 and 5:30" % label)
	if float(st.lv30_time) > 0.0:
		assert_true(float(st.lv30_time) >= 600.0, "%s: Lv 30 not before 10:00 (%.0f s)" % [label, float(st.lv30_time)])
	assert_true(int(w.player_state.level) < 50, "%s: far below the old Lv 50+ at the end (%d)" % [label,
		int(w.player_state.level)])
	if w.state == RunWorld.DEAD:
		assert_true(w.time >= 600.0, "%s: a death comes late in the run (%.0f s)" % [label, w.time])
	var alive: PackedInt32Array = st.alive
	if alive.size() > 840:
		var late := 0
		for i in range(780, alive.size()):
			late = maxi(late, alive[i])
		assert_true(late >= 200, "%s: a crowd of 200+ alive after 13:00 (%d)" % [label, late])
	assert_true(int(st.near_after_8) > 0, "%s: mobs reach the player after 8:00" % label)
	assert_true(int(st.hits_after_8) >= 5, "%s: the player takes hits after 8:00 (%d)" % [label, int(st.hits_after_8)])


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


## Live mobs within 300 px horizontally and 150 px vertically of the player (balance_run.gd's engagement box).
static func _near(w: RunWorld) -> int:
	var n := 0
	for i in w.swarm.capacity():
		if w.swarm.active[i] != 0 and absf(w.swarm.x[i] - w.player.pos.x) <= 300.0 				and absf(w.swarm.y[i] - w.player.pos.y) <= 150.0:
			n += 1
	return n


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
