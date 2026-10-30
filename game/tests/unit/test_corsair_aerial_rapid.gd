extends TestCase
## Corsair's Aerial Strike (5221003) and Rapid Fire (5221004), spec #384 ticket C10 #394, GAME_DESIGN 7.120.8. Aerial Strike is the
## delayed box strike (Meteor Shower / Genesis / Arrow Rain's seam) and Rapid Fire the channelled burst (Hurricane's seam, B4): both
## are data. A flat floor, tiny mob bodies that never move, fixed 1/60 s ticks and a seeded world; the Skill.wz levels are the
## synthetic fixture tables (the v83 endpoints) unless a test says "real cache" (those call require_cache() and SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const GROUND := {"x1": 0, "y1": 0, "x2": 1400, "y2": 0}
const PISTOL := 1492000
const AERIAL := "aerial_strike"
const RAPID := "rapid_fire"
const RANK_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30] # tier C: the 30-level mapping every 30-level skill uses
const TIERS := ["rare", "epic", "unique", "legendary"]


## The synthetic 522 book: v83's endpoints (Aerial Strike 520 -> 1200 %, mobCount 6, box (-400,-500)..(400,100); Rapid Fire
## 102 -> 170 %, range 350), linear between, as the C1 scan found every level.
func _book() -> Dictionary:
	var aerial := {}
	var rapid := {}
	for lv in range(1, 31):
		var t := float(lv - 1) / 29.0
		aerial[str(lv)] = {"hs": "h%d" % lv, "mpCon": 31 + lv, "damage": float(roundi(lerpf(520.0, 1200.0, t))), "mobCount": 6,
			"cooltime": 5, "lt": {"$v": [-400, -500]}, "rb": {"$v": [400, 100]}}
		rapid[str(lv)] = {"hs": "h%d" % lv, "mpCon": 6 + lv / 10, "damage": float(roundi(lerpf(102.0, 170.0, t))), "range": 350}
	return {"skill": {
		"5221003": {"icon": RF._canvas(32, 32), "action": {"0": "airstrike"}, "level": aerial,
			"effect": RF._anim(10, 120.0, 50, 60), "effect0": RF._anim(30, 90.0, 400, 300), "effect1": RF._anim(14, 120.0, 800, 500),
			"hit": {"0": RF._anim(5, 120.0, 124, 109)}},
		"5221004": {"icon": RF._canvas(32, 32), "level": rapid, "prepare": RF._anim(9, 60.0, 74, 79),
			"keydown": RF._anim(8, 60.0, 121, 54), "keydownend": RF._anim(9, 60.0, 234, 137), "hit": {"0": RF._anim(3, 60.0, 84, 83)}}}}


## A Corsair (job 522) holding a pistol on a flat floor at `x`, tiny stationary mobs, `key` the only skill at `rank_value`.
## `playable` is flipped in this world's data only (C14 ships the real flip) so the pool's cards exist.
func _world(key: String, rank_value := 1, x := 400.0, p_seed := 394, segments: Array = [GROUND], two_maps := false) -> RunWorld:
	var data := RF.quiet_data()
	if two_maps:
		data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	data.jobs_survivor.jobs["522"]["playable"] = true
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2", "airstrike", "rapidfire"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.map_img = RF.map_from_segments(segments)
	setup.skill_imgs["522"] = _book()
	setup["job"] = 522
	var w := RunWorld.new(setup)
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0.0
	w.player.place(Vector2(x, 0), w.fhm)
	w.update_view()
	w.player.facing = 1
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Double Shot): only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Corsair" % key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, dy := -5.0, hp := 100000000.0) -> int:
	var slot := RF.put_mob(w, MOB, w.player.pos.x + dx, dy, hp)
	w.swarm.hp[slot] = int(hp)
	w.swarm.max_hp[slot] = int(hp)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(events: Array, key: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


func _run(w: RunWorld, ticks: int) -> Array:
	var events := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	return events


func _shots(w: RunWorld) -> int:
	return w.projectiles.active.count(1)


func _ticks(w: RunWorld, n: int) -> void:
	for i in n:
		w.runner.step(DT, w)


# --- Aerial Strike: the definition -------------------------------------------------------------------------------------

func test_aerial_strike_is_a_delayed_box_strike_with_the_specs_numbers() -> void:
	var w := _world(AERIAL)
	var d := w.book.def(AERIAL)
	assert_eq(int(d.skill_id), 5221003)
	assert_eq(String(d.book), "522")
	assert_eq(int(d.job), 522)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "physical")
	assert_false(d.has("weapon_families"), "a weapon gates nothing")
	assert_false(d.has("ranks"), "the default 30-level rank table")
	assert_eq(String(d.cast.rule), "box")
	assert_eq(int(d.cast.min_targets), 1)
	assert_near(float(d.pending.delay), 1.8, 0.0001)
	assert_eq(String(d.pending.effect), "", "the impact art is a cast visual: its own 1800 ms first frame is the delay")
	assert_false(bool(d.pending.get("follow_player", false)), "anchored where the caster stood")
	assert_near(float(d.cooldown), 6.0, 0.0001)
	assert_eq(String(d.action), "airstrike")
	assert_eq(String(d.effect), "Skill.wz/522.img/skill/5221003/effect")
	assert_eq(String(d.hit), "Skill.wz/522.img/skill/5221003/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/5221003/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/5221003/Hit")
	assert_eq(d.cast_visuals.size(), 2)
	var paths := ["Skill.wz/522.img/skill/5221003/effect0", "Skill.wz/522.img/skill/5221003/effect1"]
	for k in 2:
		assert_eq(String(d.cast_visuals[k].path), paths[k], "the flock crossing, then the explosions")
		assert_eq(float(d.cast_visuals[k].x), 0.0, "at the cast position")
		assert_true(bool(d.cast_visuals[k].facing), "authored for a left-facing caster, mirrored for a right-facing one")
		assert_false(bool(d.cast_visuals[k].get("follow", false)), "left where the caster stood")
	var placed: Array = w.loadout.stats(AERIAL).cast_visuals
	assert_eq(placed.size(), 2)
	assert_eq(String(placed[1].path), paths[1])
	assert_eq(w.book.max_rank(AERIAL), 8)
	assert_eq(w.book.rank_table(AERIAL).map(func(v: Variant) -> int: return int(v)), RANK_LEVELS)
	var st := w.loadout.stats(AERIAL)
	assert_eq(st.box, Rect2(-400, -500, 800, 600))
	assert_eq(st.mob_count, 6)
	assert_eq(st.attack_count, 1)


# --- Aerial Strike: the cast -------------------------------------------------------------------------------------------

func test_the_bombs_land_one_point_eight_seconds_after_the_cast_where_the_caster_stood() -> void:
	var w := _world(AERIAL)
	var near := _mob(w, 100)
	w.step(DT, MoveInput.new()) # the cast
	assert_eq(w.runner.casts, 1)
	var cast_at := w.time
	assert_true(_hits(w.drain_events(), AERIAL).is_empty(), "nothing is struck on the cast tick")
	w.player.pos.x += 600.0 # the caster walks away: the run stays where it was called
	var far := _mob(w, 100)
	var first_hit := -1.0
	for tick in 140:
		w.step(DT, MoveInput.new())
		var hits := _hits(w.drain_events(), AERIAL)
		if not hits.is_empty() and first_hit < 0.0:
			first_hit = w.time
			assert_eq(hits.size(), 1, "only the monster in the box at the cast position is struck")
			assert_eq(int(hits[0].mob), near)
			assert_true(int(hits[0].mob) != far)
	assert_near(first_hit - cast_at, 1.8, DT * 1.5, "the strike lands 1.8 s after the cast")


func test_the_cast_plays_the_flock_and_the_explosions_where_the_caster_stood() -> void:
	var w := _world(AERIAL)
	_mob(w, 100)
	w.step(DT, MoveInput.new())
	var casts := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast")
	assert_eq(casts.size(), 1)
	assert_eq(String(casts[0].effect), "Skill.wz/522.img/skill/5221003/effect", "the flourish on the caster")
	assert_near((casts[0].pos as Vector2).x, 400.0, 0.5)
	var impacts := []
	for tick in 140:
		w.step(DT, MoveInput.new())
		impacts.append_array(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "skill_impact"))
	assert_eq(impacts.size(), 1, "one impact event, for the sound and the hit art")
	assert_eq(String(impacts[0].effect), "")
	assert_near((impacts[0].pos as Vector2).x, 400.0, 0.5)


func test_the_box_spans_eight_hundred_px_around_the_caster_and_reaches_up_five_hundred() -> void:
	# Platforms at 480 px and 520 px above the caster's floor (mobs stand on the foothold below them).
	var w := _world(AERIAL, 1, 400.0, 394, [GROUND, {"x1": 440, "y1": -480, "x2": 480, "y2": -480}, {"x1": 520, "y1": -520, "x2": 560, "y2": -520}])
	var left := _mob(w, -380)
	var right := _mob(w, 380)
	var high := _mob(w, 60, -480)
	var out_side := _mob(w, 430)
	var out_up := _mob(w, 140, -520)
	assert_near(w.swarm.y[high], -480.0, 0.5)
	assert_near(w.swarm.y[out_up], -520.0, 0.5)
	var struck := {}
	for e: Dictionary in _hits(_run(w, 140), AERIAL):
		struck[int(e.mob)] = true
	for slot: int in [left, right, high]:
		assert_true(struck.has(slot), "inside (-400,-500)..(400,100)")
	assert_false(struck.has(out_side))
	assert_false(struck.has(out_up))


func test_it_hits_at_most_six_monsters_nearest_first() -> void:
	var w := _world(AERIAL)
	var slots := []
	for k in 9:
		slots.append(_mob(w, 20.0 + 25.0 * k))
	var struck := {}
	for e: Dictionary in _hits(_run(w, 140), AERIAL):
		struck[int(e.mob)] = int(struck.get(int(e.mob), 0)) + 1
	assert_eq(struck.size(), 6, "mobCount 6")
	for k in 6:
		assert_true(struck.has(slots[k]), "the six nearest to the caster")


func test_it_needs_a_monster_in_the_box_and_waits_six_seconds() -> void:
	var w := _world(AERIAL)
	_mob(w, 500) # outside the 400 px half-width
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0, "min_targets 1: nothing in the box, no cast")
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[AERIAL]), 6.0 - DT, 0.001)
	assert_near(w.loadout.stats(AERIAL).cooldown, 6.0, 0.0001)


func test_area_widens_the_box() -> void:
	var plain := _world(AERIAL)
	_mob(plain, 80)
	var wide := _world(AERIAL)
	_mob(wide, 80)
	wide.loadout.add_skill_mod(AERIAL, "area", "mul", 1.2)
	var edge_plain := _mob(plain, 450) # past 400, inside 480
	var edge_wide := _mob(wide, 450)
	assert_near(wide.loadout.stats(AERIAL).box.size.x, 960.0, 0.01)
	var struck_plain := {}
	for e: Dictionary in _hits(_run(plain, 140), AERIAL):
		struck_plain[int(e.mob)] = true
	var struck_wide := {}
	for e: Dictionary in _hits(_run(wide, 140), AERIAL):
		struck_wide[int(e.mob)] = true
	assert_false(struck_plain.has(edge_plain))
	assert_true(struck_wide.has(edge_wide))


func test_attack_count_adds_a_second_line_on_every_target() -> void:
	var base := _world(AERIAL)
	var second := _world(AERIAL)
	for w: RunWorld in [base, second]:
		_mob(w, 60)
		_mob(w, -60)
	second.loadout.add_skill_mod(AERIAL, "attack_count", "add", 1)
	assert_eq(_hits(_run(base, 140), AERIAL).size(), 2, "one line on each of the two monsters")
	assert_eq(_hits(_run(second, 140), AERIAL).size(), 4, "a second line on each")
	assert_eq(second.loadout.stats(AERIAL).attack_count, 2)


func test_a_map_transfer_drops_the_bombs_in_the_air() -> void:
	var w := _world(AERIAL, 1, 400.0, 394, [GROUND], true)
	_mob(w, 100)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	_run(w, 60)
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.map_index, 1)
	var m := _mob(w, 100)
	w.runner.cooldowns[AERIAL] = 1.0e9 # no second cast on the new map
	var events := _run(w, 200)
	assert_true(_hits(events, AERIAL).is_empty(), "nothing happens after the transfer")
	assert_eq(int(w.swarm.hp[m]), int(w.swarm.max_hp[m]))
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "skill_impact").size(), 0)


func test_a_clear_or_a_death_drops_them_too() -> void:
	for mode in ["clear", "death"]:
		var w := _world(AERIAL)
		var m := _mob(w, 100)
		w.step(DT, MoveInput.new())
		_run(w, 30)
		if mode == "clear":
			w.runner.clear_pending(w)
		else:
			w.god = false
			w.take_hit(1e9, true, "", w.player.pos - Vector2(100, 0), {"accuracy": 1e9})
		w.runner.cooldowns[AERIAL] = 1.0e9
		var events := _run(w, 200)
		assert_true(_hits(events, AERIAL).is_empty(), mode)
		assert_eq(int(w.swarm.hp[m]), int(w.swarm.max_hp[m]), mode)


func test_the_damage_rises_with_the_rank() -> void:
	var w := _world(AERIAL)
	var levels: Dictionary = _book().skill["5221003"].level
	var previous := 0.0
	for rank in range(1, 9):
		var pct := float(w.loadout.stats(AERIAL, rank).damage_pct)
		assert_near(pct, float(levels[str(RANK_LEVELS[rank - 1])].damage) / 100.0, 1e-6, "rank %d" % rank)
		assert_true(pct > previous, "damage rises with rank")
		previous = pct
	assert_near(float(w.loadout.stats(AERIAL, 8).damage_pct), 12.0, 1e-6, "rank 8 is 1200 %")


# --- Rapid Fire: the definition ----------------------------------------------------------------------------------------

func test_rapid_fire_is_a_burst_with_the_specs_numbers() -> void:
	var w := _world(RAPID)
	var d := w.book.def(RAPID)
	assert_eq(int(d.skill_id), 5221004)
	assert_eq(String(d.book), "522")
	assert_eq(int(d.job), 522)
	assert_eq(String(d.kind), "projectile")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "physical")
	assert_false(d.has("weapon_families"), "a weapon gates nothing")
	assert_false(d.has("ranks"), "the default 30-level rank table")
	assert_eq(d.cast, {"rule": "burst"})
	assert_eq(d.burst, {"interval": 0.08, "wind_up": 0.3, "retarget": true})
	assert_eq(int(d.count), 10)
	assert_true(bool(d.ammo_shot), "the current ammo's bullets")
	assert_near(float(d.cooldown), 5.0, 0.0001)
	assert_eq([float(d.range), float(d.speed), float(d.radius), int(d.pierce)], [350.0, 1000.0, 6.0, 0])
	assert_eq(String(d.hit), "Skill.wz/522.img/skill/5221004/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/5221004/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/5221004/Hit")
	assert_eq(d.burst_art, {"prepare": "Skill.wz/522.img/skill/5221004/prepare", "loop": "Skill.wz/522.img/skill/5221004/keydown",
		"end": "Skill.wz/522.img/skill/5221004/keydownend"})
	assert_eq(w.book.max_rank(RAPID), 8)
	assert_eq(w.book.rank_table(RAPID).map(func(v: Variant) -> int: return int(v)), RANK_LEVELS)
	var st := w.loadout.stats(RAPID)
	assert_eq(String(st.cast_rule), "burst")
	assert_eq(st.count, 10)
	assert_eq(st.mob_count, 1, "one monster per bullet")


func test_the_bot_reads_the_bursts_range_as_its_reach() -> void:
	var w := _world(RAPID)
	assert_eq(SkillRunner.reach_of(w.loadout.stats(RAPID), w), 350.0)


# --- Rapid Fire: the cast ----------------------------------------------------------------------------------------------

func test_ten_bullets_at_the_wind_up_then_every_twelve_hundredths_of_a_second() -> void:
	var w := _world(RAPID)
	_mob(w, 300)
	_ticks(w, 1)
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[RAPID]), 5.0 - DT, 0.001)
	assert_eq(_shots(w), 0, "nothing flies during the wind-up")
	_ticks(w, 17)
	assert_eq(_shots(w), 0, "0.3 s is 18 ticks")
	_ticks(w, 1)
	assert_eq(_shots(w), 1, "0.3 s after admission")
	var last := 1
	var ticks_since := 0
	var at := []
	for tick in 60:
		_ticks(w, 1)
		ticks_since += 1
		if _shots(w) > last:
			at.append(ticks_since)
			last = _shots(w)
			ticks_since = 0
	assert_eq(_shots(w), 10, "ten bullets, no eleventh")
	assert_eq(at.size(), 9)
	for gap in at:
		assert_true(int(gap) in [4, 5], "a bullet every 0.08 s (4 or 5 ticks of 1/60 s): %d" % gap)
	assert_eq(w.runner.casts, 1)
	assert_false(w.runner.bursts.has_skill(RAPID))


func test_the_stance_is_the_wz_rapidfire_held_for_the_whole_stream() -> void:
	var w := _world(RAPID)
	_mob(w, 300)
	_ticks(w, 1)
	assert_eq(w.upkeep.cast_action, "rapidfire")
	assert_true(w.upkeep.cast_left >= 1.0, "held until the tenth bullet (1.02 s): %f" % w.upkeep.cast_left)


func test_the_stream_follows_a_walking_character() -> void:
	var w := _world(RAPID)
	_mob(w, 340)
	_ticks(w, 19)
	var first := w.projectiles.x[0]
	for step in 5:
		_ticks(w, 5)
		w.player.place(Vector2(w.player.pos.x + 20.0, 0), w.fhm)
	_ticks(w, 5)
	assert_eq(_shots(w), 7)
	assert_true(w.projectiles.x[6] > first + 80.0, "the later bullets leave from where the character walked to")
	assert_eq(w.runner.casts, 1)


func test_the_target_is_kept_for_every_bullet() -> void:
	var w := _world(RAPID)
	var kept := _mob(w, 200)
	var other := _mob(w, 120) # nearer than the kept target once the stream starts
	_ticks(w, 1)
	# The kept target is the one admission picked (the nearest, 120 px); every bullet lands on it.
	var events := _run(w, 90)
	var targets := {}
	for e: Dictionary in _hits(events, RAPID):
		targets[int(e.mob)] = int(targets.get(int(e.mob), 0)) + 1
	assert_eq(targets.keys(), [other], "all ten bullets on the one monster")
	assert_eq(int(targets[other]), 10)
	assert_true(kept != other)


func test_a_dead_target_is_replaced_by_the_nearest_living_one() -> void:
	var w := _world(RAPID)
	var first := _mob(w, 150)
	var second := _mob(w, 250)
	_ticks(w, 1)
	_ticks(w, 40) # some bullets are out
	w.swarm.despawn(first)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var events := _run(w, 90)
	var on_second := _hits(events, RAPID).filter(func(e: Dictionary) -> bool: return int(e.mob) == second)
	assert_true(on_second.size() >= 3, "the remaining bullets are re-picked onto the second monster: %d" % on_second.size())
	assert_false(w.runner.bursts.has_skill(RAPID))


func test_no_second_burst_starts_while_one_runs() -> void:
	var w := _world(RAPID)
	_mob(w, 300)
	_ticks(w, 1)
	assert_eq(w.runner.casts, 1)
	for tick in 40:
		w.runner.cooldowns[RAPID] = 0.0 # the cooldown is not what blocks it
		_ticks(w, 1)
	assert_true(w.runner.bursts.has_skill(RAPID), "still streaming")
	assert_eq(w.runner.casts, 1, "the running stream gates a recast")
	w.runner.cooldowns[RAPID] = 1.0e9
	_ticks(w, 40)
	assert_false(w.runner.bursts.has_skill(RAPID))
	w.runner.cooldowns[RAPID] = 0.0
	_ticks(w, 2)
	assert_eq(w.runner.casts, 2, "ready again once the stream is over")


func test_count_adds_bullets() -> void:
	var w := _world(RAPID)
	w.loadout.add_skill_mod(RAPID, "count", "add", 4)
	_mob(w, 300)
	_ticks(w, 1 + 18 + 13 * 5)
	assert_eq(_shots(w), 14, "Bullet Time: fourteen bullets")
	_ticks(w, 60)
	assert_eq(_shots(w), 14)
	assert_eq(w.loadout.stats(RAPID).count, 14)


func test_every_bullet_hits_one_monster_and_a_higher_rank_hits_harder() -> void:
	var totals := []
	for rank in [1, 8]:
		var w := _world(RAPID, rank)
		var m := _mob(w, 300)
		var hits := 0
		for e: Dictionary in _hits(_run(w, 150), RAPID):
			hits += 1
		assert_eq(hits, 10, "ten bullets land at rank %d" % rank)
		totals.append(int(w.swarm.max_hp[m]) - int(w.swarm.hp[m]))
	assert_true(totals[1] > totals[0] * 1.4, "rank 8 (170 %%) out-damages rank 1 (about 108 %%): %s" % str(totals))


func test_the_damage_percent_follows_the_mapped_level_of_each_rank() -> void:
	var w := _world(RAPID)
	var levels: Dictionary = _book().skill["5221004"].level
	var previous := 0.0
	for rank in range(1, 9):
		var pct := float(w.loadout.stats(RAPID, rank).damage_pct)
		assert_near(pct, float(levels[str(RANK_LEVELS[rank - 1])].damage) / 100.0, 1e-6, "rank %d" % rank)
		assert_true(pct > previous)
		previous = pct
	assert_near(float(w.loadout.stats(RAPID, 8).damage_pct), 1.7, 1e-6)


# --- Rarity ------------------------------------------------------------------------------------------------------------

func test_the_rarity_tables_follow_the_spec() -> void:
	var w := _world(AERIAL)
	var table := {
		AERIAL: [["gun_mastery", "damage", "mul", 1.2], ["wide_run", "area", "mul", 1.2], ["second_run", "attack_count", "add", 1.0]],
		RAPID: [["gun_mastery", "damage", "mul", 1.2], ["booster", "cooldown", "mul", 0.88], ["bullet_time", "count", "add", 4.0]],
	}
	for key: String in table:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		var rows: Array = table[key]
		for t in 3:
			var tier: String = TIERS[t]
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), String(rows[t][0]), "%s %s" % [key, tier])
			assert_eq(bonuses[tier][0].effects.size(), 1)
			var effect: Dictionary = bonuses[tier][0].effects[0]
			assert_eq(String(effect.stat), String(rows[t][1]))
			assert_eq(String(effect.op), String(rows[t][2]))
			assert_near(float(effect.value), float(rows[t][3]), 0.0001)
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(String(legendary.id), String(rows[2][0]), "%s: Legendary shares the Unique's id (and its repeat counter)" % key)
		assert_eq(legendary.effects.size(), 2)
		assert_eq(String(legendary.effects[0].stat), String(rows[2][1]))
		assert_near(float(legendary.effects[0].value), float(rows[2][3]), 0.0001)
		assert_eq(String(legendary.effects[1].stat), "damage")
		assert_near(float(legendary.effects[1].value), 1.2, 0.0001)


func test_each_card_tier_changes_a_resolved_stat() -> void:
	for key: String in [AERIAL, RAPID]:
		for tier: String in TIERS:
			var w := _world(key)
			w.loadout.ranks.clear()
			w.loadout.order.clear()
			var before := w.loadout.stats(key).duplicate()
			w.upgrades.apply(key + "_new", w, tier)
			assert_false(w.upgrades.choice_card(key + "_rank", w, tier).get("rarity_bonus", {}).is_empty(), "%s %s carries a bonus" % [key, tier])
			var after := w.loadout.stats(key)
			var damage_up := w.loadout.skill_stat(key, "damage", 1.0) > 1.19
			match [key, tier]:
				[AERIAL, "rare"], [RAPID, "rare"]:
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2, 1e-6, "%s %s" % [key, tier])
				[AERIAL, "epic"]:
					assert_near(float(after.area), float(before.area) * 1.2, 1e-6)
					assert_true((after.box as Rect2).size.x > (before.box as Rect2).size.x)
				[RAPID, "epic"]:
					assert_near(float(after.cooldown), float(before.cooldown) * 0.88, 1e-6)
				[AERIAL, "unique"], [AERIAL, "legendary"]:
					assert_eq(int(after.attack_count), int(before.attack_count) + 1)
					assert_eq(damage_up, tier == "legendary")
				[RAPID, "unique"], [RAPID, "legendary"]:
					assert_eq(int(after.count), int(before.count) + 4)
					assert_eq(damage_up, tier == "legendary")


func test_a_legendary_card_hits_harder_than_the_unique() -> void:
	var unique := _world(AERIAL)
	unique.loadout.add_skill_mod(AERIAL, "attack_count", "add", 1)
	var legendary := _world(AERIAL)
	legendary.loadout.add_skill_mod(AERIAL, "attack_count", "add", 1)
	legendary.loadout.add_skill_mod(AERIAL, "damage", "mul", 1.2)
	var totals := []
	for w: RunWorld in [unique, legendary]:
		var m := _mob(w, 60)
		_run(w, 140)
		totals.append(int(w.swarm.max_hp[m]) - int(w.swarm.hp[m]))
	assert_true(totals[1] > totals[0], "Second Run + damage out-damages Second Run: %s" % str(totals))


# --- the real cache: all eight ranks against Skill.wz ------------------------------------------------------------------

func test_real_cache_all_eight_ranks_read_the_mapped_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var img := lib.img("Skill.wz/522.img")
	assert_true(img != null, "the 522 book is imported")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"522": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "gun"
	lo.add_skill(AERIAL)
	lo.add_skill(RAPID)
	for key: String in [AERIAL, RAPID]:
		var node: Dictionary = img.root.skill["5221003" if key == AERIAL else "5221004"]
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.max_rank(key), 8, key)
		assert_eq(book.rank_table(key).map(func(v: Variant) -> int: return int(v)), RANK_LEVELS)
		var previous := 0.0
		for rank_value in range(1, 9):
			var lv: int = RANK_LEVELS[rank_value - 1]
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			assert_eq(book.canonical_level(key, rank_value), lv, label)
			var level: Dictionary = node.level[str(lv)]
			var st := lo.stats(key, rank_value)
			assert_eq(int(st.level), lv, label)
			assert_near(float(st.damage_pct), float(level.damage) / 100.0, 1e-6, label)
			assert_true(float(st.damage_pct) > previous, label)
			previous = float(st.damage_pct)
			if key == AERIAL:
				assert_eq(st.box, Rect2(-400, -500, 800, 600), label)
				assert_eq(st.mob_count, 6, label)
				assert_eq(st.attack_count, 1, label)
				assert_eq(st.cast_rule, "box", label)
			else:
				assert_eq(st.range, 350.0, label)
				assert_eq(st.count, 10, label)
				assert_eq(st.mob_count, 1, "one monster per bullet: the node has no mobCount")
				assert_eq(st.attack_count, 1, "no attackCount")
	# The spec's worked rank values (rank 1 / 4 / 8) as literals.
	for i in 3:
		var r: int = [1, 4, 8][i]
		assert_near(float(lo.stats(AERIAL, r).damage_pct), [5.80, 8.50, 12.00][i], 1e-6, "Aerial Strike rank %d" % r)
		assert_near(float(lo.stats(RAPID, r).damage_pct), [1.08, 1.30, 1.70][i], 1e-6, "Rapid Fire rank %d" % r)
	lib.free()


func test_real_cache_has_the_art_and_sounds_the_definitions_name() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var counts := {"Skill.wz/522.img/skill/5221003/effect": 10, "Skill.wz/522.img/skill/5221003/effect0": 30,
		"Skill.wz/522.img/skill/5221003/effect1": 14, "Skill.wz/522.img/skill/5221003/hit/0": 5,
		"Skill.wz/522.img/skill/5221004/prepare": 9, "Skill.wz/522.img/skill/5221004/keydown": 8,
		"Skill.wz/522.img/skill/5221004/keydownend": 9, "Skill.wz/522.img/skill/5221004/hit/0": 3}
	for path: String in counts:
		var anim := lib.anim(path)
		assert_true(anim != null and not anim.is_empty(), path)
		if anim != null:
			assert_true(anim.frame_count() >= int(counts[path]), "%s has its frames (%d)" % [path, anim.frame_count()])
	var data := DataRepo.load_all()
	for key: String in [AERIAL, RAPID]:
		var d: Dictionary = data.skills.skills[key]
		assert_true(lib.anim(String(d.icon)) != null, String(d.icon))
		for sound: String in d.sounds.values():
			assert_true(lib.find(sound) != null, sound)
	var impact := lib.anim("Skill.wz/522.img/skill/5221003/effect1")
	assert_eq(impact.index_at(1.79, false), 0, "the impact art's first frame holds 1800 ms: the pending delay")
	assert_eq(impact.index_at(1.81, false), 1)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()


# --- the Rapid Fire art in the scene -----------------------------------------------------------------------------------

class FxLog extends FxRenderer:
	var calls: Array = []
	var _next := 10
	func play(path: String, _pos: Vector2, flip: bool = false, _follow: Node2D = null,
			_offset: Vector2 = Vector2.ZERO, _hold: bool = false, _delay: float = 0.0) -> int:
		_next += 1
		calls.append(["play", path.get_file(), _next, flip])
		return _next
	func play_repeating(path: String, _pos: Vector2, seconds: float, flip: bool = false,
			_follow: Node2D = null, _offset: Vector2 = Vector2.ZERO) -> int:
		_next += 1
		calls.append(["repeat", path.get_file(), _next, flip, is_inf(seconds)])
		return _next
	func fit(i: int, seconds: float) -> void:
		calls.append(["fit", i, seconds])
	func stop(i: int) -> void:
		calls.append(["stop", i])


class ArtScene extends RunScene:
	func handle_events(batch: Array) -> void:
		super.handle_events(batch.filter(func(e: Dictionary) -> bool: return String(e.type).begins_with("burst_")))


func test_the_scene_plays_prepare_fitted_to_the_wind_up_then_keydown_then_keydownend() -> void:
	var s := ArtScene.new()
	var log := FxLog.new()
	s.fx = log
	s.world = _world(RAPID)
	_mob(s.world, 300)
	s.world.step(DT, MoveInput.new())
	s.handle_events(s.world.drain_events())
	assert_eq(log.calls, [["play", "prepare", 11, true], ["fit", 11, 0.3]], "the wind-up art, fitted to 0.3 s")
	for tick in 20:
		s.world.step(DT, MoveInput.new())
		s._after_tick()
	assert_eq(log.calls.slice(2), [["stop", 11], ["repeat", "keydown", 12, true, true]], "the loop starts with the first bullet")
	for tick in 90:
		s.world.step(DT, MoveInput.new())
		s._after_tick()
		s.handle_events(s.world.drain_events())
	assert_eq(log.calls.slice(4), [["stop", 12], ["play", "keydownend", 13, true]], "the end art when the stream is over")
	log.free()
	s.free()
