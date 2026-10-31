extends TestCase
## Corsair Battleship (spec #384 C13 #397, CS-10, CS-11): the ship Form on Paladin's seam with the C11 hull / `only_skills` /
## `art_variant` effects and its two sub-skills, Battleship Cannon and Torpedo, plus the rarity bonuses. Synthetic book 522 with the
## real level rows (tests/fixtures/battleship_book.gd), seeded RNG, fixed 1/60 ticks; the last tests read the real asset cache.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/corsair_fixtures.gd")
const BOOK := preload("res://tests/fixtures/battleship_book.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
## The eight survivor ranks' WZ levels (rank_levels["10"] for the ship, the 30-level table for the subs) and the hull percents.
const SHIP_LEVELS := [2, 3, 4, 5, 7, 8, 9, 10]
const SUB_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const HULL_PCT := [20, 30, 40, 50, 70, 80, 90, 100]
const CANNON_PCT := [220, 240, 270, 285, 305, 345, 365, 380]
const CANNON_SHOTS := [3, 3, 4, 4, 4, 4, 4, 4]
const TORPEDO_PCT := [420, 460, 550, 580, 620, 710, 750, 780]
const TORPEDO_TARGETS := [4, 4, 5, 5, 5, 6, 6, 6]
const SHIP_KEYS := ["battleship", "battleship_cannon", "battleship_torpedo"]


## A Corsair (522) with a gun on the flat quiet map at x = 400 and only the Battleship learned.
func _world(hp := 1000, pad := 40) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = hp
	data.balance.regen.hp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 397, data))
	setup.equipment_info.merge({CF.PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7}}, true)
	setup.skill_imgs["522"] = BOOK.book_node()
	var w := RunWorld.new(setup)
	w.set_job(522)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.equipment.worn.weapon = Equipment.create(CF.PISTOL, {"incPAD": pad})
	w.refresh_player_stats()
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-10, -60, 20, 60) # tall enough that the shell's slope from the gun to the first body cannot clear the line behind it
		mk.move_speed = 0.0
	w.learn_skill("battleship")
	w.drain_events()
	return w


## A stationary mob `dx` px in front of the player (the facing side). `_run` puts it back on its spot every tick, so the
## knock-back of the ship's own hits cannot walk it out of the cannon's reach (set `pin` false to let it fly).
func _mob(w: RunWorld, dx: float, hp := 100000000, pin := true) -> int:
	var m := RF.put_mob(w, MOB, w.player.pos.x + dx * w.player.facing, 190, 10000)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	if pin:
		var pins: Dictionary = w.get_meta("pins", {})
		pins[m] = Vector2(w.swarm.x[m], w.swarm.y[m])
		w.set_meta("pins", pins)
	return m


## Runs `seconds` of the whole world and returns every event with the elapsed second it fired in (`at`).
func _run(w: RunWorld, seconds: float, from := 0.0) -> Array:
	var out: Array = []
	var pins: Dictionary = w.get_meta("pins", {})
	for i in roundi(seconds / DT):
		for m: int in pins:
			w.swarm.x[m] = pins[m].x
			w.swarm.y[m] = pins[m].y
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			e["at"] = from + float(i + 1) * DT
			out.append(e)
	return out


func _of(events: Array, type: String, skill := "") -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type and (skill == "" or String(e.get("skill", "")) == skill))


func _ats(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> float: return snappedf(float(e.at), 0.01))


## Starts the ship directly (no cast) and returns its live window state.
func _board(w: RunWorld) -> Dictionary:
	w.runner.forms.start(w, "battleship", w.loadout.stats("battleship"))
	return w.runner.forms.snapshot().back()


## Synthetic gun / blast pool actives under the real keys the ship permits or pauses, each firing at anything within 400 px.
func _guns(w: RunWorld, keys: Array) -> void:
	for i in keys.size():
		var id := 9992001 + i
		w.book.defs[keys[i]] = {"skill_id": id, "book": "999", "kind": "instant", "slot": "active", "ranks": [1, 3],
			"damage": "fixed", "range": 400, "cooldown": 1.0, "cast": {"rule": "range_around", "min_targets": 1},
			"effect": "Skill.wz/999.img/skill/%d/effect" % id, "name": String(keys[i])}
		w.book.skill_imgs["999"] = w.book.skill_imgs.get("999", {"skill": {}})
		w.book.skill_imgs["999"].skill[str(id)] = {"level": {"1": {"fixdamage": 10, "range": 400, "mobCount": 3},
			"3": {"fixdamage": 10, "range": 400, "mobCount": 3}}}
		w.loadout.add_skill(keys[i])


# --- the catalog -------------------------------------------------------------------------------------------------

func test_battleship_is_a_form_with_the_spec_block() -> void:
	var book := _world().book
	var d: Dictionary = book.def("battleship")
	assert_eq([book.skill_id("battleship"), d.kind, d.slot, d.damage, int(d.job), d.book], [5221006, "form", "active", "none", 522, "522"])
	assert_eq(d.cast, {"rule": "form", "mob_within": 400.0})
	assert_eq(d.cooldown, 45.0)
	assert_eq([d.form.duration, d.form.exclusive_group], [15.0, "corsair_ship"])
	assert_eq(d.form.effects, {"hull": {"field": "pdd", "of": "max_hp"}, "only_skills": ["grenade", "flamethrower", "ice_splitter"],
		"art_variant": {"effect": "effect_ship"}})
	assert_eq(int(d.form.presentation.mount), 1932000)
	assert_eq(d.form.presentation.keys(), ["mount"])
	assert_eq(d.form.subs.map(func(s: Dictionary) -> Array: return [s.skill, float(s.first_after), float(s.interval)]),
		[["battleship_cannon", 0.8, 1.4], ["battleship_torpedo", 1.6, 3.0]])
	assert_eq(d.sounds.use, "Sound.wz/Skill.img/5221006/Use")
	assert_eq(d.effect, "Skill.wz/522.img/skill/5221006/effect")
	assert_eq(d.cast_visuals[0].path, "Skill.wz/522.img/skill/5221006/effect0")
	assert_eq(d.icon, "Skill.wz/522.img/skill/5221006/icon")
	assert_true(book.weapon_families("battleship").is_empty(), "no weapon gate")
	assert_eq(book.max_rank("battleship"), 8)
	assert_false(d.has("ranks"), "the default table of rank_levels[\"10\"] applies, not a copy")


func test_the_subs_are_form_subs_of_the_ship_with_no_slot_and_no_card() -> void:
	var w := _world()
	var cannon: Dictionary = w.book.def("battleship_cannon")
	var torpedo: Dictionary = w.book.def("battleship_torpedo")
	assert_eq([w.book.skill_id("battleship_cannon"), cannon.slot, cannon.form_sub_of, cannon.damage, cannon.cast.rule],
		[5221007, "form_sub", ["battleship"], "physical", "nearest"])
	assert_eq([w.book.skill_id("battleship_torpedo"), torpedo.slot, torpedo.form_sub_of, torpedo.damage, torpedo.cast.rule],
		[5221008, "form_sub", ["battleship"], "physical", "nearest"])
	assert_eq([cannon.speed, cannon.radius, cannon.action, cannon.get("ammo_shot", false)], [900.0, 8.0, "cannon", false])
	assert_eq([torpedo.speed, torpedo.radius, torpedo.action, torpedo.range, torpedo.pierce_field], [700.0, 14.0, "torpedo", 400.0, "mobCount"])
	assert_eq([cannon.ball, torpedo.ball], ["Skill.wz/522.img/skill/5221007/ball", "Skill.wz/522.img/skill/5221008/ball"])
	for key in ["battleship_cannon", "battleship_torpedo"]:
		assert_false(w.book.def(key).has("rarity_bonuses"), "%s has no rarity list" % key)
		assert_eq(w.book.slot(key), "form_sub", "%s is not a pool active" % key)
		assert_false(key in DataRepo.load_all().jobs_survivor.jobs["522"].skill_pool)
	var data := DataRepo.load_all()
	var cards := UpgradePool.from_data(data.upgrades)
	cards.add_pool_skills(w.book, JobTree.from_data(data.jobs, data.jobs_survivor))
	for card: Dictionary in cards.cards:
		assert_false(String(card.get("skill", "")) in ["battleship_cannon", "battleship_torpedo"], "no card for a sub: %s" % card.id)


func test_the_form_catalog_validates_with_the_three_definitions() -> void:
	var defs: Dictionary = _world().book.defs
	var mine := {}
	for key in SHIP_KEYS:
		mine[key] = defs[key]
	assert_eq(Array(PlayerForms.validation_errors(mine)), [])
	for error in PlayerForms.validation_errors(defs):
		assert_false("battleship" in error, "the shipped catalog: %s" % error)


func test_rank_levels_ten_exists_exactly_once_in_the_merged_data() -> void:
	var data := DataRepo.load_all()
	assert_eq(data.skills.rank_levels["10"].map(func(v: Variant) -> int: return int(v)), [2, 3, 4, 5, 7, 8, 9, 10])
	var copies := 0
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("skills", line)
		if FileAccess.file_exists(path) and DataRepo.load_json(path).has("rank_levels"):
			copies += 1
	assert_eq(copies, 0, "no line fragment carries a second table")
	assert_eq(FileAccess.get_file_as_string("res://data/survivor/skills.json").count("\"rank_levels\""), 1, "one table in the shared file")
	assert_eq(_defining_lines("battleship"), ["corsair"], "defined once")


## The line names (`skills/<line>.json`) whose file defines `key`.
func _defining_lines(key: String) -> Array:
	var out := []
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("skills", line)
		if FileAccess.file_exists(path) and DataRepo.load_json(path).get("skills", {}).has(key):
			out.append(line)
	return out


# --- rank values -------------------------------------------------------------------------------------------------

func test_the_ship_reads_the_level_ten_table_and_the_hull_share_follows_pdd_at_every_rank() -> void:
	var w := _world()
	assert_eq(w.book.rank_table("battleship").map(func(v: Variant) -> int: return int(v)), SHIP_LEVELS)
	for r in range(1, 9):
		w.loadout.set_rank("battleship", r)
		var st := w.loadout.stats("battleship")
		assert_eq(int(st.level), SHIP_LEVELS[r - 1], "rank %d level" % r)
		assert_eq(int(w.book.canonical("battleship", int(st.level), "pdd")), HULL_PCT[r - 1], "rank %d pdd" % r)
		assert_near(float(st.hull_share), HULL_PCT[r - 1] / 100.0, 1e-9, "rank %d hull share" % r)
		assert_eq(float(st.duration), 15.0)
	assert_eq([HULL_PCT[0], HULL_PCT[3], HULL_PCT[7]], [20, 50, 100], "the spec's rank 1 / 4 / 8")


func test_the_hull_points_equal_pdd_percent_of_max_hp_at_rank_one_four_and_eight() -> void:
	for r in [1, 4, 8]:
		var w := _world()
		w.loadout.set_rank("battleship", r)
		var max_hp := int(w.player_state.max_hp)
		var s := _board(w)
		assert_eq(int(s.level), SHIP_LEVELS[r - 1])
		assert_eq(int(s.hull_max), floori(HULL_PCT[r - 1] / 100.0 * max_hp), "rank %d" % r)
		assert_eq(int(s.hull_hp), int(s.hull_max))
	var w8 := _world()
	w8.loadout.set_rank("battleship", 8)
	assert_eq(int(_board(w8).hull_max), int(w8.player_state.max_hp), "rank 8: a hull as big as max HP")


func test_cannon_and_torpedo_read_their_own_thirty_level_table_at_every_parent_rank() -> void:
	var w := _world()
	assert_eq(w.book.rank_table("battleship_cannon").map(func(v: Variant) -> int: return int(v)), SUB_LEVELS)
	assert_eq(w.book.rank_table("battleship_torpedo").map(func(v: Variant) -> int: return int(v)), SUB_LEVELS)
	for r in range(1, 9):
		w.loadout.set_rank("battleship", r)
		var parent := w.loadout.stats("battleship")
		var cannon := w.loadout.sub_stats("battleship_cannon", parent, r)
		var torpedo := w.loadout.sub_stats("battleship_torpedo", parent, r)
		assert_eq([int(cannon.level), int(torpedo.level)], [SUB_LEVELS[r - 1], SUB_LEVELS[r - 1]], "rank %d" % r)
		assert_near(float(cannon.damage_pct), CANNON_PCT[r - 1] / 100.0, 1e-6, "rank %d cannon damage" % r)
		assert_eq(int(cannon.count), CANNON_SHOTS[r - 1], "rank %d cannon rounds" % r)
		assert_eq(float(cannon.range), 400.0)
		assert_near(float(torpedo.damage_pct), TORPEDO_PCT[r - 1] / 100.0, 1e-6, "rank %d torpedo damage" % r)
		assert_eq(int(torpedo.pierce), TORPEDO_TARGETS[r - 1] - 1, "rank %d torpedo pierces mobCount - 1" % r)
		assert_eq(float(torpedo.range), 400.0)
	assert_eq([CANNON_PCT[0], CANNON_PCT[3], CANNON_PCT[7]], [220, 285, 380], "the spec's rank 1 / 4 / 8 cannon")
	assert_eq([TORPEDO_PCT[0], TORPEDO_PCT[3], TORPEDO_PCT[7]], [420, 580, 780], "the spec's rank 1 / 4 / 8 torpedo")
	assert_eq([TORPEDO_TARGETS[0], TORPEDO_TARGETS[3], TORPEDO_TARGETS[7]], [4, 5, 6])
	w.loadout.set_rank("battleship", 8)
	assert_eq(int(w.loadout.sub_stats("battleship_cannon", w.loadout.stats("battleship"), 8).level), 30, "rank 8 casts the subs at level 30")


# --- the form's lifecycle ----------------------------------------------------------------------------------------

func test_it_waits_with_no_monster_within_400_px_then_boards() -> void:
	var w := _world()
	assert_true(_of(_run(w, 0.5), "form_started").is_empty(), "no monster: wait, nothing burned")
	assert_true(float(w.runner.cooldowns.get("battleship", 0.0)) <= 0.0, "the cooldown was not spent")
	_mob(w, 420)
	assert_true(_of(_run(w, 0.1), "form_started").is_empty(), "420 px is outside the admission radius")
	_mob(w, 300)
	assert_eq(_of(_run(w, 0.1), "form_started").size(), 1)


func test_the_window_lasts_fifteen_seconds_and_carries_the_mount() -> void:
	var w := _world()
	_mob(w, 300)
	var events := _run(w, 0.2)
	var started := _of(events, "form_started")
	assert_eq(started.size(), 1)
	assert_eq([started[0].skill, started[0].skill_id, started[0].element, started[0].duration, int(started[0].mount)],
		["battleship", 5221006, "", 15.0, 1932000])
	var ended := _of(_run(w, 14.9, 0.2), "form_ended")
	assert_eq(ended.size(), 1)
	assert_eq([ended[0].skill, ended[0].reason], ["battleship", "expired"])
	assert_near(float(ended[0].at), 15.0, 0.06)


func test_the_cooldown_is_forty_five_seconds_from_the_cast_and_runs_through_the_ride() -> void:
	var w := _world()
	_mob(w, 300)
	var events := _run(w, 44.0)
	_mob(w, 300)
	events.append_array(_run(w, 3.0, 44.0))
	var starts := _ats(_of(events, "form_started"))
	assert_eq(starts.size(), 2)
	assert_near(float(starts[1]) - float(starts[0]), 45.0, 0.05, "45 s from the cast, not from the end of the ride")


func test_the_hull_absorbs_hits_and_its_break_ends_the_ride_with_the_cooldown_still_counting() -> void:
	var w := _world()
	_mob(w, 300)
	_run(w, 0.1)
	var s: Dictionary = w.runner.forms.snapshot()[0]
	var hull := int(s.hull_hp)
	var hp := float(w.player_state.hp)
	var hit := {"accuracy": 100000.0, "source_kind": "touch"}
	assert_eq(w.take_hit(100.0, false, "", Vector2(300, 190), hit), 0, "the hull takes the whole hit")
	assert_eq(float(w.player_state.hp), hp)
	assert_true(int(w.runner.forms.snapshot()[0].hull_hp) < hull)
	w.runner.forms._active.back().hull_hp = 1
	w.upkeep.invincible_t = 0.0
	w.take_hit(100.0, false, "", Vector2(300, 190), hit)
	assert_true(w.runner.forms.snapshot().is_empty(), "the hull broke")
	assert_true(w.events.any(func(e: Dictionary) -> bool: return e.type == "form_ended" and e.skill == "battleship" and e.reason == "broken"))
	var cd := float(w.runner.cooldowns.battleship)
	assert_true(cd > 40.0 and cd <= 45.0, "the 45 s cooldown is running (%f)" % cd)
	w.runner.tick_cooldowns(1.0, w)
	assert_near(float(w.runner.cooldowns.battleship), cd - 1.0, 0.001)


func test_the_flow_drivers_diagnostic_lethal_hit_kills_a_corsair_aboard_a_full_hull() -> void:
	var w := _world()
	w.loadout.ranks["battleship"] = 8
	w.refresh_player_stats()
	_mob(w, 300)
	_run(w, 0.1)
	var s: Dictionary = w.runner.forms.snapshot()[0]
	assert_eq(int(s.hull_hp), int(s.hull_max), "boarded with the whole hull")
	# The exact source the flow driver (`redesign`, Sleepywood) uses: the hull takes at most its points, the rest reaches HP.
	var lethal := {"boss": true, "source_kind": "attack", "mob": -1, "unrevivable": true}
	w.take_hit(1.0e9, false, "", w.player.pos + Vector2(40.0, 0.0), lethal)
	assert_eq(w.state, RunWorld.DEAD, "a hull cannot absorb the diagnostic hit into a survived one")
	assert_true(w.runner.forms.snapshot().is_empty(), "the ride is over")


# --- Cannon and Torpedo inside the ride ------------------------------------------------------------------------

func test_cannon_fires_at_point_eight_then_every_one_point_four_seconds_and_torpedo_at_one_point_six_then_every_three() -> void:
	var w := _world()
	_mob(w, 250)
	var events := _run(w, 15.5)
	var begin := float(_ats(_of(events, "form_started"))[0])
	var cannon := _ats(_of(events, "cast", "battleship_cannon"))
	var torpedo := _ats(_of(events, "cast", "battleship_torpedo"))
	assert_eq(cannon.size(), 11, "0.8 + 1.4 k inside 15 s: k = 0 .. 10")
	assert_eq(torpedo.size(), 5, "1.6 + 3.0 k inside 15 s: k = 0 .. 4")
	for k in cannon.size():
		assert_near(float(cannon[k]) - begin, 0.8 + 1.4 * k, 0.05, "cannon cast %d" % k)
	for k in torpedo.size():
		assert_near(float(torpedo[k]) - begin, 1.6 + 3.0 * k, 0.05, "torpedo cast %d" % k)
	assert_eq([_of(events, "cast", "battleship_cannon")[0].action, _of(events, "cast", "battleship_torpedo")[0].action], ["cannon", "torpedo"])


func test_the_subs_do_not_fire_after_the_ride_ends() -> void:
	var w := _world()
	_mob(w, 250)
	var events := _run(w, 20.0)
	var ended := float(_ats(_of(events, "form_ended"))[0])
	for e: Dictionary in events:
		if e.type == "cast" and String(e.skill).begins_with("battleship_"):
			assert_true(float(e.at) <= ended + 0.001, "%s cast after the ship left" % e.skill)


func test_cannon_lands_at_least_its_rank_rounds_on_a_lone_target() -> void:
	for r in [1, 4, 8]:
		var w := _world(100000, 100)
		w.loadout.set_rank("battleship", r)
		_mob(w, 250)
		var events := _run(w, 3.0)
		var cast := _of(events, "cast", "battleship_cannon")
		assert_false(cast.is_empty(), "rank %d cast" % r)
		var shots := _of(events, "mob_hit", "battleship_cannon")
		assert_true(shots.size() >= CANNON_SHOTS[r - 1], "rank %d: %d rounds land on the lone target (%d hits)" % [r, CANNON_SHOTS[r - 1], shots.size()])
		assert_true(float(shots[0].damage) > 0.0, "and the round does damage")


func test_torpedo_pierces_mob_count_minus_one_monsters_in_a_line() -> void:
	for r in [1, 4, 8]:
		var w := _world(100000, 100)
		w.loadout.set_rank("battleship", r)
		for i in 9:
			_mob(w, 120 + 30 * i)
		var hits := _of(_run(w, 2.6), "mob_hit", "battleship_torpedo")
		var struck := {}
		for e: Dictionary in hits:
			struck[int(e.mob)] = true
		assert_eq(struck.size(), TORPEDO_TARGETS[r - 1], "rank %d: the torpedo strikes mobCount monsters in all" % r)


func test_the_parent_damage_modifier_multiplies_both_subs() -> void:
	var base := _world(100000, 3000)
	var boosted := _world(100000, 3000)
	boosted.loadout.add_skill_mod("battleship", "damage", "mul", 1.2)
	for w in [base, boosted]:
		_mob(w, 250)
	var a := _run(base, 3.0)
	var b := _run(boosted, 3.0)
	for sub in ["battleship_cannon", "battleship_torpedo"]:
		var plain := float(_of(a, "mob_hit", sub)[0].damage)
		var strong := float(_of(b, "mob_hit", sub)[0].damage)
		assert_near(strong / plain, 1.2, 0.04, "%s takes the parent's damage multiplier" % sub)


# --- the skills the ship pauses and the ones it keeps ---------------------------------------------------------------

func test_aboard_only_grenade_flamethrower_and_ice_splitter_cast_and_the_others_resume_when_the_ship_leaves() -> void:
	var w := _world()
	_guns(w, ["grenade", "flamethrower", "ice_splitter", "double_shot", "rapid_fire"])
	_mob(w, 250)
	_board(w)
	for key in ["grenade", "flamethrower", "ice_splitter"]:
		assert_true(w.runner.forms.permits(w, key), key)
	for key in ["double_shot", "rapid_fire"]:
		assert_false(w.runner.forms.permits(w, key), key)
	w.runner.cooldowns.battleship = 50.0
	for i in 30:
		w.runner.step(DT, w)
	assert_true(float(w.runner.cooldowns.get("grenade", 0.0)) > 0.0, "a permitted skill cast")
	assert_true(float(w.runner.cooldowns.get("double_shot", 0.0)) <= 0.0, "a paused skill stayed ready")
	w.runner.forms.end(w, "battleship", "expired")
	w.runner.step(DT, w)
	assert_true(float(w.runner.cooldowns.get("double_shot", 0.0)) > 0.0 or float(w.runner.cooldowns.get("rapid_fire", 0.0)) > 0.0,
		"the paused skills cast the tick the ship leaves")


func test_dash_and_the_ship_itself_are_never_paused() -> void:
	var w := _world()
	w.learn_skill("dash")
	_board(w)
	assert_true(w.runner.forms.permits(w, "dash"))
	assert_true(w.runner.forms.permits(w, "battleship"))
	var input := MoveInput.new()
	input.press_skill("dash")
	w.drain_events()
	w.step(DT, input)
	assert_true(w.buffs.has("dash"), "Dash casts aboard")
	assert_eq(w.runner.forms.snapshot().size(), 1, "and the ship stays")


func test_the_cones_draw_effect_ship_aboard_and_effect_otherwise() -> void:
	var w := _world()
	_guns(w, ["flamethrower", "ice_splitter", "grenade"])
	for key in ["flamethrower", "ice_splitter"]:
		w.book.defs[key]["effect_ship"] = "Skill.wz/999.img/skill/%d/effect_ship" % int(w.book.defs[key].skill_id)
	var plain: String = w.runner.forms.begin_cast(w, "flamethrower", w.loadout.stats("flamethrower")).effect
	assert_eq(plain, "Skill.wz/999.img/skill/%d/effect" % int(w.book.defs.flamethrower.skill_id))
	_board(w)
	for key in ["flamethrower", "ice_splitter"]:
		assert_eq(w.runner.forms.begin_cast(w, key, w.loadout.stats(key)).effect,
			"Skill.wz/999.img/skill/%d/effect_ship" % int(w.book.defs[key].skill_id), "%s aboard" % key)
	assert_eq(w.runner.forms.begin_cast(w, "grenade", w.loadout.stats("grenade")).effect,
		"Skill.wz/999.img/skill/%d/effect" % int(w.book.defs.grenade.skill_id), "a skill without the node keeps its effect")


# --- rarity bonuses ---------------------------------------------------------------------------------------------

func _bonus(tier: String) -> Dictionary:
	return _world().book.def("battleship").rarity_bonuses[tier][0]


func _with_bonus(w: RunWorld, tier: String) -> void:
	for e: Dictionary in _bonus(tier).effects:
		w.loadout.add_skill_mod("battleship", String(e.stat), String(e.op), float(e.value))


func test_the_four_lists_name_the_lineage_skills_and_legendary_shares_the_uniques_counter() -> void:
	var rb: Dictionary = _world().book.def("battleship").rarity_bonuses
	assert_eq(rb.keys(), ["rare", "epic", "unique", "legendary"])
	assert_eq([rb.rare[0].id, rb.rare[0].text], ["gun_mastery", "Gun Mastery"])
	assert_eq([rb.epic[0].id, rb.epic[0].text], ["reinforced_hull", "Reinforced Hull"])
	assert_eq([rb.unique[0].id, rb.unique[0].text], ["full_steam", "Full Steam"])
	assert_eq(rb.legendary[0].id, rb.unique[0].id, "same id: the same repeat counter")
	assert_eq(rb.legendary[0].effects.slice(0, 1), rb.unique[0].effects)
	assert_eq(rb.legendary[0].effects[1], {"stat": "damage", "op": "mul", "value": 1.2})


func test_gun_mastery_raises_what_the_subs_deal() -> void:
	var base := _world()
	var boosted := _world()
	_with_bonus(boosted, "rare")
	for sub in ["battleship_cannon", "battleship_torpedo"]:
		var a := base.loadout.sub_stats(sub, base.loadout.stats("battleship"), 1)
		var b := boosted.loadout.sub_stats(sub, boosted.loadout.stats("battleship"), 1)
		assert_near(float(b.damage_max) / float(a.damage_max), 1.2, 0.001, sub)


func test_reinforced_hull_makes_the_hull_one_and_a_half_times_bigger() -> void:
	var base := _world()
	var strong := _world()
	_with_bonus(strong, "epic")
	assert_near(float(strong.loadout.stats("battleship").hull_share), float(base.loadout.stats("battleship").hull_share) * 1.5, 1e-9)
	assert_eq(int(_board(strong).hull_max), floori(0.2 * 1.5 * int(strong.player_state.max_hp)))
	assert_true(int(_board(strong).hull_max) > int(_board(base).hull_max))


func test_full_steam_lengthens_the_ride_and_legendary_adds_the_damage() -> void:
	var w := _world()
	_with_bonus(w, "unique")
	assert_near(float(w.loadout.stats("battleship").duration), 21.0, 1e-4)
	_mob(w, 300)
	var events := _run(w, 22.0)
	assert_near(float(_of(events, "form_started")[0].duration), 21.0, 1e-4)
	assert_near(float(_of(events, "form_ended")[0].at), 21.0, 0.06)
	var legendary := _world()
	_with_bonus(legendary, "legendary")
	assert_near(float(legendary.loadout.stats("battleship").duration), 21.0, 1e-4)
	var plain := _world()
	var a := plain.loadout.sub_stats("battleship_cannon", plain.loadout.stats("battleship"), 1)
	var b := legendary.loadout.sub_stats("battleship_cannon", legendary.loadout.stats("battleship"), 1)
	assert_near(float(b.damage_max) / float(a.damage_max), 1.2, 0.001)


func test_a_booster_style_cooldown_card_does_not_touch_the_ride() -> void:
	var w := _world()
	w.loadout.add_skill_mod("battleship", "cooldown", "mul", 0.88)
	_mob(w, 300)
	var events := _run(w, 39.0)
	_mob(w, 300)
	events.append_array(_run(w, 3.0, 39.0))
	var starts := _ats(_of(events, "form_started"))
	assert_eq(starts.size(), 2)
	assert_near(float(starts[1]) - float(starts[0]), 45.0 * 0.88, 0.06)


# --- determinism ------------------------------------------------------------------------------------------------

func test_two_worlds_with_the_same_seed_produce_the_same_events() -> void:
	var out := []
	for i in 2:
		var w := _world(100000, 100)
		_mob(w, 250)
		_mob(w, 330)
		out.append(JSON.stringify(_run(w, 16.0)))
	assert_eq(out[0], out[1])
	assert_true(String(out[0]).contains("battleship_torpedo"))


# --- text -------------------------------------------------------------------------------------------------------

func test_the_skill_window_line_names_the_hull_the_permitted_skills_and_the_sub_clocks() -> void:
	var w := _world()
	var text := SkillText.new(w.book, {})
	var line := text.level_line("battleship", 2, w.loadout.stats("battleship", 1))
	assert_true(line.contains("Rides a battleship for 15 s"), line)
	assert_true(line.contains("hull 20% of max HP"), line)
	assert_true(line.contains("only Grenade, Flamethrower and Ice Splitter fire"), line)
	assert_true(line.contains("Cannon every 1.4 s") and line.contains("Torpedo every 3 s"), line)
	assert_true(text.level_line("battleship", 10, w.loadout.stats("battleship", 8)).contains("hull 100% of max HP"))


func test_the_hull_modifier_previews_as_a_percent_of_max_hp_on_its_card() -> void:
	var w := _world()
	var changes := UpgradePool._bonus_changes({"skill": "battleship", "effects": [{"stat": "hull", "op": "mul", "value": 1.5}]}, w.loadout, 1)
	assert_eq(changes.hull, {"before": 20, "after": 30})
	assert_true("hull" in LevelUpWindow.MOD_LABELS)


# --- real cache -------------------------------------------------------------------------------------------------

func _real_book() -> SkillBook:
	var img := AssetLibrary.get_default().img("Skill.wz/522.img")
	if img == null:
		return null
	return SkillBook.from_data(DataRepo.load_all().skills, {"522": img.root})


func test_real_cache_the_battleship_levels_two_to_ten_and_the_subs_over_all_eight_ranks() -> void:
	if not require_cache_img("Skill.wz/522.img"):
		return
	var book := _real_book()
	assert_true(book != null, "book 522 imported")
	if book == null:
		return
	var lo := Loadout.new(book)
	lo.add_skill("battleship")
	for level in range(2, 11):
		var row: Dictionary = book.level_node("battleship", level)
		assert_eq([int(row.pdd), int(row.mdd), int(row.x)], [10 * level, 10 * level, 1], "Battleship level %d" % level)
	assert_eq(book.rank_table("battleship").map(func(v: Variant) -> int: return int(v)), SHIP_LEVELS)
	for level in range(4, 31):
		var c: Dictionary = book.level_node("battleship_cannon", level)
		var t: Dictionary = book.level_node("battleship_torpedo", level)
		assert_eq([int(c.damage), int(c.bulletCount), int(c.range)], [BOOK.CANNON_DAMAGE[level - 1], 3 if level <= 10 else 4, 400], "Cannon level %d" % level)
		assert_eq(int(t.damage), BOOK.TORPEDO_DAMAGE[level - 1], "Torpedo level %d" % level)
		assert_eq(int(t.mobCount), 4 if level <= 10 else 5 if level <= 20 else 6, "Torpedo level %d targets" % level)
		assert_eq([t.lt.get("$v"), t.rb.get("$v")], [[-400.0, -80.0], [-10.0, 20.0]], "Torpedo level %d box" % level)
	for r in range(1, 9):
		lo.set_rank("battleship", r)
		var parent := lo.stats("battleship")
		assert_eq(int(parent.level), SHIP_LEVELS[r - 1])
		assert_near(float(parent.hull_share), HULL_PCT[r - 1] / 100.0, 1e-9, "rank %d" % r)
		var cannon := lo.clone().sub_stats("battleship_cannon", parent, r)
		var torpedo := lo.clone().sub_stats("battleship_torpedo", parent, r)
		assert_eq([int(cannon.level), int(torpedo.level)], [SUB_LEVELS[r - 1], SUB_LEVELS[r - 1]])
		assert_near(float(cannon.damage_pct), CANNON_PCT[r - 1] / 100.0, 1e-6, "rank %d cannon" % r)
		assert_eq(int(cannon.count), CANNON_SHOTS[r - 1])
		assert_near(float(torpedo.damage_pct), TORPEDO_PCT[r - 1] / 100.0, 1e-6, "rank %d torpedo" % r)
		assert_eq(int(torpedo.pierce), TORPEDO_TARGETS[r - 1] - 1)


func test_real_cache_the_art_the_sounds_and_the_mount_exist() -> void:
	if not require_cache_img("Skill.wz/522.img"):
		return
	var lib := AssetLibrary.get_default()
	if lib.img("Skill.wz/522.img") == null:
		assert_true(false, "book 522 imported")
		return
	var w := _world()
	var seen := []
	for key in SHIP_KEYS:
		var d: Dictionary = w.book.def(key)
		for field in ["icon", "effect", "ball", "hit"]:
			if String(d.get(field, "")) != "":
				assert_true(lib.node(String(d[field])) != null, "%s.%s %s" % [key, field, d[field]])
				seen.append(field)
		for s in ["use", "hit"]:
			if String(d.sounds.get(s, "")) != "":
				assert_true(lib.sound(String(d.sounds[s])) != null, "%s sound %s" % [key, s])
	assert_eq(lib.find_anim("Skill.wz/522.img/skill/5221006/effect").frame_count(), 11)
	assert_eq(lib.find_anim("Skill.wz/522.img/skill/5221006/effect0").frame_count(), 7)
	assert_eq(lib.find_anim("Skill.wz/522.img/skill/5221008/ball").frame_count(), 6)
	assert_eq(lib.find_anim("Skill.wz/522.img/skill/5221007/ball").frame_count(), 1)
	assert_true(MountArt.load_mount(lib, 1932000).has_stance("cannon"))
	assert_true(seen.size() >= 8)
