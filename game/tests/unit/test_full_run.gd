extends TestCase
## Seeded full runs to death/clear or the configured cap, including boss finales past15:00.
## Synthetic setup exercises the whole simulation; real-cache setup covers both playable stages.
## Predetermined training seeds 1/2/2026 provide ongoing regressions, avoiding held-out acceptance leakage.
## The fresh held-out matrix is a separate frozen-candidate assessment in GAME_DESIGN 4.2.
## Checks include spawning/engagement, kills/EXP, progression/event consistency, ordinary late landed hits,
## no lost mobs and all scheduled bosses dead before clear. Individual progression windows allow build spread;
## Henesys stage sample medians use Lv8 210–270s, Mage at Lv10 180–330s and Lv30 540–720s when reached (coarse #29
## pass for the sword-paced v83 Beginner; final pacing waits for later specs).
## Tree records outcomes without judging its pacing; both stages retain event, cache and finale invariants.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Tier C: fixed regression sample chosen before held-out execution; both stages use the same seeds.
const PACING_SEEDS := [1, 2, 2026]
## Pacing guards are active; final acceptance uses a separate frozen held-out matrix.
const CHECK_PACING := true
## The swarm engagement box (balance_run.gd ENG_X / ENG_Y) and the least share of the live mobs in it at 6:00-12:00.
const ENGAGED_X := 400.0
const ENGAGED_Y := 200.0
const ENGAGED_MIN := 0.3 # tier C: inherited swarm-pressure regression floor


## Runs `w` to the end (or balance.run_time_cap) and returns statistics.
func _run(w: RunWorld) -> Dictionary:
	var st := {
		"spawn_minutes": PackedInt32Array(), "alive": PackedInt32Array(), "killers": {}, "exp": 0, "job_time": -1.0,
		"lv8_time": -1.0, "lv10_time": -1.0, "lv30_time": -1.0, "levels": 0, "died": false, "cleared": false,
		"events": 0, "hits_after_8": 0, "ordinary_hits_after_8": 0, "near_after_8": 0, "engaged_6_12": 0, "alive_6_12": 0,
	}
	var spawn_minutes: PackedInt32Array = st.spawn_minutes
	var cap := float(w.balance.get("run_time_cap", 1800.0)) # tier C: harness fallback, configured in balance.
	spawn_minutes.resize(ceili(cap / 60.0) + 1)
	var alive: PackedInt32Array = st.alive
	var last_skill := {}
	var memo := {}
	for t in ceili(cap / DT):
		RF.auto_choose(w)
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, RF.bot_input(w, memo))
		if t % 60 == 0:
			alive.append(w.swarm.alive_count())
			if w.time >= 480.0:
				st.near_after_8 = int(st.near_after_8) + _near(w)
			if w.time >= 360.0 and w.time < 720.0:
				st.engaged_6_12 = int(st.engaged_6_12) + _engaged(w)
				st.alive_6_12 = int(st.alive_6_12) + w.swarm.alive_count()
		for e: Dictionary in w.drain_events():
			st.events += 1
			match String(e.type):
				"mob_spawned":
					spawn_minutes[mini(int(w.time / 60.0), spawn_minutes.size() - 1)] += 1
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
					if w.time >= 480.0 and not bool(e.miss):
						st.hits_after_8 = int(st.hits_after_8) + 1
						if not bool(e.boss):
							st.ordinary_hits_after_8 = int(st.ordinary_hits_after_8) + 1
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


func _assert_run(w: RunWorld, st: Dictionary, label: String, enforce_pacing := true) -> void:
	var alive: PackedInt32Array = st.alive
	var minutes := int(w.time / 60.0)
	print("%s: %.0f s, %s, level %d, job %d, kills %d, EXP %d, lv8 at %.0f s, lv10 at %.0f s, lv30 at %.0f s, job 200 at %.0f s, hits after 8:00 %d (ordinary %d), killers %s, alive/min %s, engaged 6:00-12:00 %.2f, relocated %d" % [
		label, w.time, w.state_name(), w.player_state.level, w.player_state.job_id, w.kills, st.exp, st.lv8_time,
		st.lv10_time, st.lv30_time, st.job_time, st.hits_after_8, st.ordinary_hits_after_8, st.killers, _per_minute(alive), _engaged_share(st),
		w.director.relocated])
	var spawn_minutes: PackedInt32Array = st.spawn_minutes
	if CHECK_PACING and enforce_pacing:
		for m in minutes:
			assert_true(spawn_minutes[m] > 0, "%s: mobs spawned in minute %d" % [label, m])
		var third := maxi(1, floori(alive.size() / 3.0))
		assert_true(_mean(alive, alive.size() - third, alive.size()) > _mean(alive, 0, third),
			"%s: the mean alive count grows (%s)" % [label, _per_minute(alive)])
		# The v83 Beginner kills with Three Snails (one cast per MP pulse) and, mostly, the basic attack.
		assert_true(int(st.killers.get("three_snails", 0)) + int(st.killers.get("basic_attack", 0)) > 20,
			"%s: Three Snails and the basic attack killed mobs %s" % [label, st.killers])
	assert_true(int(st.exp) > 0, "%s: EXP collected" % label)
	assert_eq(int(st.exp), w.pickups.collected_exp, "%s: collected EXP matches its events" % label)
	var kill_events := 0
	for count: int in st.killers.values():
		kill_events += count
	assert_eq(kill_events, w.kills, "%s: exactly one death event per kill" % label)
	if enforce_pacing and float(st.job_time) > 0.0:
		assert_true(w.jobs.is_descendant(int(w.player_state.job_id), 200), label + ": Magician lineage survives second advancement")
	assert_eq(st.levels, w.player_state.level - 1, "%s: one level_up event per level" % label)
	assert_true(w.state == RunWorld.DEAD or w.state == RunWorld.CLEARED or (not enforce_pacing and w.state == RunWorld.PLAYING),
		"%s: ended or informational Tree timeout (%s)" % [label, w.state_name()])
	if w.state == RunWorld.DEAD:
		assert_true(st.died and not st.cleared, "%s: DEAD with player_died" % label)
		assert_true(w.player_state.dead)
		assert_eq(w.player_state.hp, 0)
	elif w.state == RunWorld.CLEARED:
		assert_true(st.cleared and not st.died, "%s: CLEARED with stage_cleared" % label)
		if w.bosses.has_bosses():
			assert_true(w.time >= w.duration - DT, "%s: the finale can continue past the timer" % label)
			assert_true(w.bosses.all_dead(), "%s: every scheduled boss is dead" % label)
		else:
			assert_near(w.time, w.duration, DT, "%s: the full duration" % label)
		assert_false(w.player_state.dead)
	else:
		assert_false(st.died or st.cleared, "%s: timeout cannot manufacture death or clear" % label)
		assert_false(w.player_state.dead)
	assert_eq(w.swarm.lost_count, 0, "%s: no mob fell out of the world" % label)
	assert_true(w.warnings.is_empty(), "%s: no skipped boss or missing simulation data (%s)" % [label, w.warnings])
	if CHECK_PACING and enforce_pacing and int(st.alive_6_12) > 0:
		# Henesys retains the inherited engagement floor; Tree is not a pacing acceptance stage.
		assert_true(_engaged_share(st) >= ENGAGED_MIN, "%s: %.2f of the live mobs within %d x %d px of the player at %s" % [
			label, _engaged_share(st), ENGAGED_X, ENGAGED_Y, "6:00-12:00"])


func test_full_run_synthetic_map() -> void:
	var w := RunWorld.new(RF.with_basic_attack(RF.setup("henesys_hg1", 2026)))
	assert_true(w.warnings.is_empty(), "every pool mob has an img: %s" % [w.warnings])
	_assert_run(w, _run(w), "synthetic")



func test_full_run_real_map() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	for stage: String in ["henesys_hg1", "tree_that_grew_1"]:
		var outcomes := {"CLEARED": 0, "DEAD": 0, "TIMEOUT": 0}
		var magician: Array[float] = []
		var lv8: Array[float] = []
		var lv10: Array[float] = []
		var lv30: Array[float] = []
		for pacing_seed: int in PACING_SEEDS:
			var missing := PackedStringArray()
			var setup := DataRepo.build_setup(data, stage, pacing_seed, Vector2(800, 600), _img, _mob, missing)
			assert_true(missing.is_empty(), "%s seed%d: cache has every required img (%s)" % [stage, pacing_seed, missing])
			if not missing.is_empty():
				return
			var w := RunWorld.new(setup)
			if stage == "henesys_hg1":
				assert_eq(w.fhm.count(), 181, "the real104040000")
			else:
				assert_true(w.fhm.count() > 0, "the real Tree has footholds")
			assert_eq(w.mob_kinds.size(), DataRepo.stage_mob_ids(data, stage).size(), "every stage pool kind")
			assert_true(w.warnings.is_empty(), "%s" % [w.warnings])
			var st := _run(w)
			var outcome := "TIMEOUT" if w.state == RunWorld.PLAYING else w.state_name()
			outcomes[outcome] += 1
			var label := "%s seed%d" % [stage, pacing_seed]
			_assert_run(w, st, label, stage == "henesys_hg1")
			if CHECK_PACING and stage == "henesys_hg1":
				_assert_pacing(w, st, label)
			if float(st.lv8_time) > 0.0:
				lv8.append(float(st.lv8_time))
			if float(st.job_time) > 0.0:
				magician.append(float(st.job_time))
			if float(st.lv10_time) > 0.0:
				lv10.append(float(st.lv10_time))
			if float(st.lv30_time) > 0.0:
				lv30.append(float(st.lv30_time))
		print("%s outcomes %s; milestone reaches Lv8 %d/3, Lv10 %d/3, Magician %d/3, Lv30 %d/3" % [
			stage, outcomes, lv8.size(), lv10.size(), magician.size(), lv30.size()])
		if CHECK_PACING and stage == "henesys_hg1":
			# Population acceptance allows early deaths. The fixed sample still needs majority early progression.
			assert_true(lv8.size() >= 2 and lv10.size() >= 2 and magician.size() >= 2,
				"%s: at least2/3 predetermined runs reach the early milestones" % stage)
			if not lv8.is_empty():
				assert_between(_median(lv8), 210.0, 270.0, "%s: Lv8 median210–270s (n%d/3)" % [stage, lv8.size()])
			if not magician.is_empty():
				assert_between(_median(magician), 180.0, 330.0, "%s: Mage median180–330s (n%d/3)" % [stage, magician.size()])
			if not lv10.is_empty():
				assert_between(_median(lv10), 180.0, 330.0, "%s: Lv10 median180–330s (n%d/3)" % [stage, lv10.size()])
			assert_true(lv30.size() >= 1, "%s: at least1 of3 predetermined runs reachesLv30; population clear target40–50%%" % stage)
			if not lv30.is_empty():
				assert_between(_median(lv30), 540.0, 720.0, "%s: Lv30 median540–720s (n%d/3)" % [stage, lv30.size()])


## Median of a nonempty regression sample; the caller checks milestone reach separately.
static func _median(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() >> 1
	return sorted[mid] if sorted.size() % 2 else (sorted[mid - 1] + sorted[mid]) * 0.5


## The tuned pacing on the real map, per seed (docs/GAME_DESIGN.md 4.1, 5); windows with some slack for the bot.
func _assert_pacing(w: RunWorld, st: Dictionary, label: String) -> void:
	if float(st.lv8_time) > 0.0:
		assert_between(float(st.lv8_time), 180.0, 300.0, "%s: reached Lv8 between3:00 and5:00" % label)
	if float(st.job_time) > 0.0:
		assert_between(float(st.job_time), 150.0, 360.0, "%s: reached Magician between2:30 and6:00" % label)
		# _run drains the accepted job event after the next fixed tick; allow floating-point accumulation error.
		assert_near(float(st.job_time), float(st.lv10_time) + DT, 1e-6, "%s: Magician at Lv10" % label)
	if float(st.lv10_time) > 0.0:
		assert_between(float(st.lv10_time), 150.0, 360.0, "%s: reached Lv10 between2:30 and6:00" % label)
	if float(st.lv30_time) > 0.0:
		assert_between(float(st.lv30_time), 480.0, 1080.0, "%s: individual Lv30 in8:00–18:00; sample median9:00–12:00" % label)
	assert_true(int(w.player_state.level) < 50, "%s: far below the old Lv 50+ at the end (%d)" % [label,
		int(w.player_state.level)])
	var alive: PackedInt32Array = st.alive
	if alive.size() > 840:
		var late := 0
		for i in range(780, alive.size()):
			late = maxi(late, alive[i])
		assert_true(late >= 200, "%s: a crowd of 200+ alive after 13:00 (%d)" % [label, late])
	if w.time >= 540.0:
		assert_true(int(st.near_after_8) > 0, "%s: mobs reach the player after 8:00" % label)
		assert_true(int(st.ordinary_hits_after_8) >= 5, "%s: at least5 ordinary nonmiss hits after a full late minute (%d)" % [label, int(st.ordinary_hits_after_8)])


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


## Engaged share (live mobs within ENGAGED_X x ENGAGED_Y of the player's feet, balance_run.gd's ENG_X/ENG_Y) over the
## 6:00-12:00 samples.
static func _engaged_share(st: Dictionary) -> float:
	return float(st.engaged_6_12) / maxf(1.0, float(st.alive_6_12))


## Live mobs within ENGAGED_X px horizontally and ENGAGED_Y px vertically of the player's feet.
static func _engaged(w: RunWorld) -> int:
	var n := 0
	for i in w.swarm.capacity():
		if w.swarm.active[i] == 0:
			continue
		if absf(w.swarm.x[i] - w.player.pos.x) <= ENGAGED_X and absf(w.swarm.y[i] - w.player.pos.y) <= ENGAGED_Y:
			n += 1
	return n


## Live mobs within 300 px horizontally and 150 px vertically of the player (balance_run.gd's NEAR box).
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
	for stage: String in ["tree_that_grew_1"]:
		_short_run(RunWorld.new(RF.with_basic_attack(RF.setup(stage, 77))), stage)


func test_other_stages_real_maps() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	for stage: String in ["tree_that_grew_1"]:
		var missing := PackedStringArray()
		var setup := DataRepo.build_setup(data, stage, 77, Vector2(800, 600), _img, _mob, missing)
		assert_true(missing.is_empty(), "%s: the cache has every img (%s)" % [stage, missing])
		if missing.is_empty():
			_short_run(RunWorld.new(setup), stage + " (real)")
