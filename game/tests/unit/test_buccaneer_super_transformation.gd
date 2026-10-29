extends TestCase
## Buccaneer Super Transformation, Demolition and Snatch (B10 #422, spec #412 BU-2, BU-3, BU-6, BU-7, BU-8, BU-11, BU-12): the
## strong morph form (morph 1001) and its two own subs on Paladin's Form seam, Hero's `pull` block and the stun status; Shockwave
## now has two parents. Synthetic WZ-shaped books 511 and 512 (the eight mapped levels carry the real v83 numbers), seeded RNG,
## fixed 1/60 ticks; the last test reads the real asset cache.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const TRANS := preload("res://tests/unit/test_buccaneer_transformation.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const BOSS := 2220000
const FLYER := 9300063
const KNUCKLE := 1482000
## The 20-level skill's mapped levels (rank 1..8) and Super Transformation's defence (pdd = mdd, tier A, 5121003).
const S_LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
const S_DEFENCE := [43, 45, 48, 50, 53, 55, 58, 60]
## The 30-level subs' mapped levels, and their tier A damage % and mob counts (5121004, 5121005, 5111006).
const SUB_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const D_DAMAGE := [120, 160, 210, 240, 280, 330, 370, 400]
const N_DAMAGE := [240, 280, 370, 400, 440, 530, 570, 600]
const N_TARGETS := [2, 3, 3, 4, 5, 5, 6, 6]
const SHOCK_DAMAGE := [310, 370, 430, 475, 535, 595, 655, 700]


## The synthetic `skill_imgs["512"]` node of the three skills (the rarity audit builds its world from it too).
static func book_node() -> Dictionary:
	return preload("res://tests/fixtures/buccaneer_super_transformation_book.gd").book_node()


## A Buccaneer (job 512 flipped playable for the test) on the flat quiet map at x = 400 knowing `learned`.
func _world(learned: Array = ["super_transformation"], pad := 17) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	data.balance.player.hp = 100000
	data.balance.regen.hp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 422, data))
	setup.skill_imgs["511"] = TRANS.book_node()
	setup.skill_imgs["512"] = book_node()
	var w := RunWorld.new(setup)
	w.set_job(512)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.equipment.worn.weapon = Equipment.create(KNUCKLE, {"incPAD": pad})
	w.refresh_player_stats()
	w.god = true # a mob in Demolition's strip touches the player: no knockback may move the box
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	for key: String in learned:
		w.learn_skill(key)
	w.drain_events()
	return w


## A stationary mob `dx` px in front of the player (the facing side).
func _mob(w: RunWorld, dx: float, hp := 100000000, id := MOB) -> int:
	var m := RF.put_mob(w, id, w.player.pos.x + dx * w.player.facing, 190, 10000)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _run(w: RunWorld, seconds: float, from := 0.0) -> Array:
	var out: Array = []
	var ticks := roundi(seconds / DT)
	for i in ticks:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			e["at"] = from + float(i + 1) * DT
			out.append(e)
	return out


func _of(events: Array, type: String, skill := "") -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type and (skill == "" or String(e.get("skill", "")) == skill))


func _ats(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> float: return snappedf(float(e.at), 0.01))


## The elapsed seconds of `skill`'s casts, relative to the form's start.
func _cast_times(events: Array, skill: String) -> Array:
	var begin := float(_ats(_of(events, "form_started"))[0])
	return _ats(_of(events, "cast", skill)).map(func(t: float) -> float: return snappedf(t - begin, 0.01))


func _near(times: Array, want: Array, tolerance := 0.04) -> bool:
	if times.size() != want.size():
		return false
	for i in times.size():
		if absf(float(times[i]) - float(want[i])) > tolerance:
			return false
	return true


# --- the catalog -------------------------------------------------------------------------------------------------

func test_super_transformation_is_a_morph_form_with_the_spec_block() -> void:
	var book := _world().book
	var d: Dictionary = book.def("super_transformation")
	assert_eq([book.skill_id("super_transformation"), d.kind, d.slot, d.damage, int(d.job), d.book], [5121003, "form", "active", "none", 512, "512"])
	assert_eq(d.cast, {"rule": "form", "mob_within": 400.0})
	assert_eq(d.form, {"duration": 15.0, "exclusive_group": "buccaneer_transformation", "effects": {},
		"subs": [{"skill": "snatch", "first_after": 0.5, "interval": 6.0},
			{"skill": "shockwave", "first_after": 1.0, "interval": 3.0},
			{"skill": "demolition", "first_after": 2.0, "interval": 5.0}]})
	assert_eq(d.buff, book.def("transformation").buff, "the same morph buff block, Morph 1001 by the WZ level")
	assert_eq([d.cooldown, d.action, d.action_time], [24.0, "alert2", 0.6])
	assert_eq(d.sounds.use, "Sound.wz/Skill.img/5121003/Use")
	assert_true(String(d.get("effect", "")).is_empty(), "neither WZ node has cast art")
	assert_true(book.weapon_families("super_transformation").is_empty(), "no weapon gate")
	assert_eq(book.max_rank("super_transformation"), 8)


func test_demolition_is_a_form_sub_of_super_with_the_canonical_box_and_a_stun() -> void:
	var book := _world().book
	var d: Dictionary = book.def("demolition")
	assert_eq([book.skill_id("demolition"), d.kind, d.slot, int(d.job), d.book], [5121004, "instant", "form_sub", 512, "512"])
	assert_eq(d.form_sub_of, ["super_transformation"], "Super alone")
	assert_eq(d.cast.rule, "box")
	assert_eq(d.on_hit, {"status": "stun", "duration_field": "time"}, "no chance field: every landed line stuns")
	assert_false(d.has("pending"), "no delay: the eight lines land at the cast")
	assert_eq([d.action, d.action_time], ["demolition", 1.0])
	assert_eq([d.sounds.use, d.sounds.hit], ["Sound.wz/Skill.img/5121004/Use", "Sound.wz/Skill.img/5121004/Hit"])
	assert_eq(d.hit, "Skill.wz/512.img/skill/5121004/hit/0")
	assert_false(d.has("rarity_bonuses"), "a sub has no cards and no rarity list")
	assert_false(book.slot("demolition") == "active", "never a pool card")


func test_snatch_is_a_form_sub_of_super_with_the_pull_block_and_a_stun() -> void:
	var book := _world().book
	var d: Dictionary = book.def("snatch")
	assert_eq([book.skill_id("snatch"), d.kind, d.slot, int(d.job), d.book], [5121005, "instant", "form_sub", 512, "512"])
	assert_eq(d.form_sub_of, ["super_transformation"])
	assert_eq(d.cast.rule, "box")
	assert_eq(d.pull, {"range_field": "range", "min_gap": 60.0}, "no chance field: the pull always applies (BU-12)")
	assert_eq(float(d.range), 300.0, "the node has no range: the definition carries the box's far edge")
	assert_eq(d.on_hit, {"status": "stun", "duration_field": "time"})
	assert_eq([d.action, d.action_time], ["snatch", 0.8])
	assert_eq([d.sounds.use, d.sounds.hit], ["Sound.wz/Skill.img/5121005/Use", "Sound.wz/Skill.img/5121005/Hit"])
	assert_eq([d.effect, d.hit], ["Skill.wz/512.img/skill/5121005/effect", "Skill.wz/512.img/skill/5121005/hit/0"])
	assert_false(d.has("rarity_bonuses"))


func test_shockwave_has_both_forms_as_parents() -> void:
	var d: Dictionary = _world().book.def("shockwave")
	assert_eq(d.form_sub_of, ["transformation", "super_transformation"])


func test_the_form_catalog_validates_with_every_new_definition() -> void:
	var defs: Dictionary = _world().book.defs
	var mine := {}
	for key: String in ["transformation", "super_transformation", "shockwave", "demolition", "snatch"]:
		mine[key] = defs[key]
	assert_eq(Array(PlayerForms.validation_errors(mine)), [])
	for error in PlayerForms.validation_errors(defs):
		assert_false("super_transformation" in error or "demolition" in error or "snatch" in error, "the shipped catalog: %s" % error)


# --- rank values -------------------------------------------------------------------------------------------------

func test_super_reads_the_mapped_levels_at_every_rank() -> void:
	var w := _world()
	for r in range(1, 9):
		w.loadout.set_rank("super_transformation", r)
		var st := w.loadout.stats("super_transformation")
		assert_eq(w.loadout.level("super_transformation"), S_LEVELS[r - 1], "rank %d level" % r)
		assert_eq(int(w.book.canonical("super_transformation", int(st.level), "pdd")), S_DEFENCE[r - 1])
		assert_eq(int(w.book.canonical("super_transformation", int(st.level), "mdd")), S_DEFENCE[r - 1])
		assert_eq(int(st.morph), 1001)
	assert_eq([S_DEFENCE[0], S_DEFENCE[3], S_DEFENCE[7]], [43, 50, 60], "the spec's rank 1 / 4 / 8")


func test_the_subs_rank_with_their_parent_through_their_own_thirty_level_table() -> void:
	var w := _world()
	w.loadout.set_rank("super_transformation", 8)
	for key: String in ["shockwave", "demolition", "snatch"]:
		assert_eq(int(w.loadout.clone().stats(key, 8).level), 30, "rank 8 of the parent reads level 30 of %s" % key)
	for r in range(1, 9):
		var lo := w.loadout.clone()
		var demo := lo.stats("demolition", r)
		assert_eq(int(demo.level), SUB_LEVELS[r - 1])
		assert_near(float(demo.damage_pct), D_DAMAGE[r - 1] / 100.0, 1e-6, "Demolition rank %d" % r)
		assert_eq([int(demo.attack_count), int(demo.mob_count)], [8, 1], "eight lines on one monster")
		var snatch := lo.stats("snatch", r)
		assert_near(float(snatch.damage_pct), N_DAMAGE[r - 1] / 100.0, 1e-6, "Snatch rank %d" % r)
		assert_eq(int(snatch.mob_count), N_TARGETS[r - 1], "Snatch rank %d targets" % r)
		assert_near(float(snatch.pull_chance), 100.0, 1e-6, "no chance field: always")
		assert_near(float(snatch.pull_gap), 60.0, 1e-6)
		assert_near(float(snatch.range), 300.0, 1e-6)
	assert_eq([D_DAMAGE[0], D_DAMAGE[3], D_DAMAGE[7]], [120, 240, 400], "the spec's Demolition rank 1 / 4 / 8")
	assert_eq([N_DAMAGE[0], N_DAMAGE[3], N_DAMAGE[7]], [240, 400, 600], "the spec's Snatch rank 1 / 4 / 8")
	assert_eq([N_TARGETS[0], N_TARGETS[3], N_TARGETS[7]], [2, 4, 6])
	assert_eq(w.loadout.stats("demolition", 8).box, Rect2(-300, -150, 280, 165), "lt (-300,-150) rb (-20,15)")
	assert_eq(w.loadout.stats("snatch", 8).box, Rect2(-300, -100, 250, 115), "lt (-300,-100) rb (-50,15)")


# --- the form's lifecycle ----------------------------------------------------------------------------------------

func test_the_window_is_fifteen_seconds_with_morph_1001_and_the_cooldown_counts_from_the_cast() -> void:
	var w := _world()
	_mob(w, 300)
	var events := _run(w, 0.2)
	var started := _of(events, "form_started")
	assert_eq(started.size(), 1)
	assert_eq([started[0].skill, started[0].skill_id, started[0].element, started[0].duration], ["super_transformation", 5121003, "", 15.0])
	assert_eq(w.morph_id(), 1001)
	assert_eq(int(w.player_state.morph), 1001, "the presentation reads it from player_state")
	events = _run(w, 15.3, 0.2)
	var ended := _of(events, "form_ended")
	assert_eq([ended[0].skill, ended[0].reason], ["super_transformation", "expired"])
	assert_near(float(ended[0].at), 15.0, 0.06)
	assert_eq(w.morph_id(), 0)
	assert_eq(int(w.player_state.morph), 0)
	events = _run(w, 9.6, 15.5)
	var starts := _ats(_of(events, "form_started"))
	assert_eq(starts.size(), 1, "recast 24 s after the cast, not after the end of the window (15 s)")
	assert_near(float(starts[0]), 24.02, 0.05)


func test_the_stat_package_moves_while_the_form_lives_and_returns_after_with_the_caps() -> void:
	var w := _world()
	w.loadout.set_rank("super_transformation", 4)
	var pdd := float(w.hit_defense().pdd)
	var mdd := float(w.hit_defense().mdd)
	var speed := w.player_speed_stat()
	var jump := w.player.jump_stat
	_mob(w, 300)
	_run(w, 0.1)
	assert_near(float(w.hit_defense().pdd) - pdd, 50.0, 0.001, "rank 4 reads level 10: pdd 50")
	assert_near(float(w.hit_defense().mdd) - mdd, 50.0, 0.001)
	assert_eq(w.player.speed_stat, Equipment.SPEED_CAP, "+40 speed reaches the cap of 140")
	assert_eq(w.player.jump_stat, jump + 20, "+20 jump gives 120, under the cap of 123")
	assert_eq(w.buffs.effect_total("watk"), 0.0, "BU-8: no attack bonus, the node holds none")
	_run(w, 15.0, 0.1)
	assert_near(float(w.hit_defense().pdd), pdd, 0.001)
	assert_near(float(w.hit_defense().mdd), mdd, 0.001)
	assert_near(w.player_speed_stat(), speed, 0.001)
	assert_eq(w.player.jump_stat, jump)


func test_the_two_forms_alternate_with_no_gap_and_no_overlap_over_sixty_seconds() -> void:
	var w := _world(["transformation", "super_transformation"])
	_mob(w, 300)
	var events := _run(w, 60.0)
	var windows: Array = []
	var open: Dictionary = {}
	for e: Dictionary in events:
		if e.type == "form_started":
			assert_true(open.is_empty(), "overlap: %s started while %s runs" % [e.skill, open.get("skill", "")])
			open = {"skill": e.skill, "from": float(e.at), "morph": w.morph_id()}
		elif e.type == "form_ended":
			open["to"] = float(e.at)
			windows.append(open)
			open = {}
	var order := windows.map(func(win: Dictionary) -> String: return win.skill)
	assert_eq(order.slice(0, 4), ["transformation", "super_transformation", "transformation", "super_transformation"])
	for i in range(1, windows.size()):
		var gap := float(windows[i].from) - float(windows[i - 1].to)
		assert_true(gap >= -0.001 and gap <= 0.04, "window %d starts the tick after window %d ends (gap %.3f)" % [i, i - 1, gap])
	assert_near(float(windows[0].to) - float(windows[0].from), 10.0, 0.06)
	assert_near(float(windows[1].to) - float(windows[1].from), 15.0, 0.06)
	assert_near(float(windows[1].from), 10.02, 0.05, "Super is admitted the tick after Transformation ends")


func test_player_state_morph_is_1001_in_supers_window_and_1000_in_transformations() -> void:
	var w := _world(["transformation", "super_transformation"])
	_mob(w, 300)
	var seen := {}
	for i in roundi(30.0 / DT):
		w.step(DT, MoveInput.new())
		w.drain_events()
		var t := float(i + 1) * DT
		var morph := int(w.player_state.morph)
		if t > 1.0 and t < 9.0:
			seen[morph] = true
		if t > 11.0 and t < 24.0:
			seen[morph] = true
	assert_eq(seen.keys(), [1000, 1001], "1000 in the first 10 s, then 1001")


func test_the_form_lasts_longer_with_form_time_and_a_booster_shortens_its_cooldown() -> void:
	var w := _world()
	w.loadout.add_skill_mod("super_transformation", "form_time", "mul", 1.25)
	_mob(w, 300)
	var events := _run(w, 20.0)
	assert_eq(float(_of(events, "form_started")[0].duration), 18.75)
	assert_near(float(_of(events, "form_ended")[0].at), 18.75, 0.06)
	var b := _world()
	b.loadout.add_skill_mod("super_transformation", "cooldown", "mul", 0.88)
	_mob(b, 300)
	var starts := _ats(_of(_run(b, 26.0), "form_started"))
	assert_eq(starts.size(), 2)
	assert_near(float(starts[1]) - float(starts[0]), 24.0 * 0.88, 0.05)


# --- the subs inside the window ----------------------------------------------------------------------------------

func test_the_subs_fire_at_their_first_after_and_interval_while_a_mob_stands_in_every_box() -> void:
	var w := _world()
	_mob(w, 150)
	var events := _run(w, 15.5)
	assert_true(_near(_cast_times(events, "snatch"), [0.5, 6.5, 12.5]), "Snatch: %s" % [_cast_times(events, "snatch")])
	assert_true(_near(_cast_times(events, "shockwave"), [1.0, 4.0, 7.0, 10.0, 13.0]), "Shockwave: %s" % [_cast_times(events, "shockwave")])
	assert_true(_near(_cast_times(events, "demolition"), [2.0, 7.0, 12.0]), "Demolition: %s" % [_cast_times(events, "demolition")])
	assert_eq(_of(events, "cast", "snatch")[0].action, "snatch")
	assert_eq(_of(events, "cast", "demolition")[0].action, "demolition")


func test_the_subs_wait_when_their_box_is_empty_and_leave_no_catch_up_burst() -> void:
	var w := _world()
	_mob(w, 380) # inside the 400 px admission radius, beyond every strip (330 / 300)
	var events := _run(w, 4.0)
	assert_eq(_of(events, "form_started").size(), 1)
	for key in ["snatch", "shockwave", "demolition"]:
		assert_true(_of(events, "cast", key).is_empty(), "%s: nothing in its strip, it waits" % key)
	_mob(w, 150)
	events = _run(w, 0.1, 4.0)
	for key in ["snatch", "shockwave", "demolition"]:
		assert_eq(_of(events, "cast", key).size(), 1, "%s: one cast the tick a target arrives, not the casts it missed" % key)
	events = _run(w, 1.0, 4.1)
	for key in ["snatch", "shockwave", "demolition"]:
		assert_true(_of(events, "cast", key).is_empty(), "%s: its interval started at the cast" % key)


func test_every_sub_takes_the_forms_damage_modifier_and_none_earns_energy() -> void:
	var plain := _world(["super_transformation"], 600)
	_mob(plain, 150)
	var before := _run(plain, 3.0)
	var boosted := _world(["super_transformation"], 600)
	boosted.loadout.add_skill_mod("super_transformation", "damage", "mul", 1.2)
	_mob(boosted, 150)
	var after := _run(boosted, 3.0)
	for key in ["snatch", "shockwave", "demolition"]:
		var a := float(_of(before, "mob_hit", key)[0].damage)
		var b := float(_of(after, "mob_hit", key)[0].damage)
		assert_near(b / a, 1.2, 0.03, "%s: the parent's multiplier multiplies the sub" % key)
	var charged := _world(["super_transformation"], 600)
	charged.meter.value = 7
	_mob(charged, 150)
	var events := _run(charged, 3.0)
	assert_eq(charged.meter.value, 7, "no sub earns or spends energy")
	assert_true(_of(events, "meter_changed").is_empty())


func test_shockwave_resolves_the_same_under_either_parent() -> void:
	var stats := []
	for parent in ["transformation", "super_transformation"]:
		var w := _world([parent], 600)
		w.loadout.set_rank(parent, 8)
		var shock := w.loadout.clone().stats("shockwave", 8)
		_mob(w, 200)
		var events := _run(w, 3.5)
		assert_eq(_of(events, "cast", "shockwave").size(), 1, "%s: Shockwave casts at 1 s" % parent)
		assert_eq(_of(events, "mob_hit", "shockwave").size(), 1, "%s: and lands 1.38 s later" % parent)
		stats.append([shock.level, shock.damage_pct, shock.mob_count, shock.box, shock.damage_min, shock.damage_max])
	assert_eq(stats[0], stats[1], "same rank, same level, same box, same damage range")


# --- Demolition --------------------------------------------------------------------------------------------------

func test_demolition_strikes_one_monster_eight_times_and_stuns_it_for_one_second() -> void:
	var w := _world()
	var near := _mob(w, 30) # inside Demolition's box (it starts 20 px out), outside Snatch's (50 px)
	var second := _mob(w, 60)
	var events := _run(w, 2.1)
	var hits := _of(events, "mob_hit", "demolition")
	assert_eq(hits.size(), 8, "eight lines")
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [near, near, near, near, near, near, near, near], "one monster, the nearest")
	assert_eq(_of(events, "cast", "demolition").size(), 1)
	assert_near(w.swarm.status_time(near, MobSwarm.STUN), 1.0, 0.1, "the 1 s stun, minus the ticks since the cast")
	assert_eq(_of(events, "mob_hit", "demolition").filter(func(e: Dictionary) -> bool: return int(e.mob) == second).size(), 0, "never the second")


func test_demolitions_dead_zone_is_twenty_pixels() -> void:
	var inside := _world()
	_mob(inside, 10) # its body spans 5..15 px: wholly inside the 20 px dead zone
	assert_true(_of(_run(inside, 2.1), "cast", "demolition").is_empty(), "nothing in the strip")
	var edge := _world()
	_mob(edge, 30)
	assert_eq(_of(_run(edge, 2.1), "cast", "demolition").size(), 1)


func test_demolition_stuns_every_landed_line_with_no_chance_roll_and_a_boss_resists() -> void:
	var w := _world()
	var boss := _mob(w, 40, 100000000, BOSS)
	var events := _run(w, 2.1)
	assert_eq(_of(events, "mob_hit", "demolition").size(), 8, "a boss is struck")
	assert_near(w.swarm.status_time(boss, MobSwarm.STUN), 0.0, 1e-6, "bosses resist the stun")
	var d: Dictionary = w.book.def("demolition")
	assert_false(d.on_hit.has("chance_field"), "no roll")


# --- Snatch ------------------------------------------------------------------------------------------------------

func test_snatch_pulls_before_it_strikes_and_leaves_the_mob_sixty_pixels_away() -> void:
	var w := _world()
	var m := _mob(w, 250)
	var events := _run(w, 0.6)
	var pulled := _of(events, "mob_pulled")
	assert_eq(pulled.size(), 1)
	assert_eq(int(pulled[0].mob), m)
	assert_near(absf(w.swarm.x[m] - w.player.pos.x), 60.0, 0.1, "the 60 px gap")
	var order := events.filter(func(e: Dictionary) -> bool: return e.type in ["cast", "mob_pulled", "mob_hit"] and (e.type == "mob_pulled" or e.skill == "snatch"))
	assert_eq(order.map(func(e: Dictionary) -> String: return e.type), ["cast", "mob_pulled", "mob_hit"], "the pull before the damage")
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 1.0, 0.15, "stunned for one second")


func test_snatch_strikes_a_mob_it_pulled_into_what_was_its_dead_zone() -> void:
	# The strip starts 50 px out; the pull leaves the mob 60 px away, so the mob that was dragged in is struck.
	var w := _world()
	var m := _mob(w, 290)
	var events := _run(w, 0.6)
	var hits := _of(events, "mob_hit", "snatch")
	assert_eq(hits.map(func(e: Dictionary) -> int: return int(e.mob)), [m])


func test_the_pull_never_rolls_and_never_moves_bosses_flyers_or_scheduled_mobs() -> void:
	var w := _world()
	var boss := _mob(w, 260, 100000000, BOSS)
	var flyer := _mob(w, 270, 100000000, FLYER)
	w.swarm.fh[flyer] = -1
	var scheduled := _mob(w, 280)
	w.swarm.steady[scheduled] = 1
	var ordinary := _mob(w, 200)
	_mob(w, 230)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var moved_from := [w.swarm.pos(boss), w.swarm.pos(flyer), w.swarm.pos(scheduled)]
	var st := w.loadout.clone().stats("snatch", 1)
	var rng_before := w.rng.state
	assert_eq(w.runner.apply_pull(w, "snatch", st, w.cast_origin()), 2, "rank 1 pulls two mobs")
	assert_eq(w.rng.state, rng_before, "no roll: the pull never draws")
	assert_eq([w.swarm.pos(boss), w.swarm.pos(flyer), w.swarm.pos(scheduled)], moved_from)
	assert_near(absf(w.swarm.x[ordinary] - w.player.pos.x), 60.0, 0.1)


func test_a_pull_or_knockback_of_a_mob_on_a_foothold_the_map_lacks_is_a_no_op() -> void:
	# The rarity audit swaps the map under a live swarm, leaving a mob on index 1 of a one-foothold map: the slide must not crash.
	var map := FootholdMap.from_segments([{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}])
	var stop := map.slide_along(1, 100.0, 1, 50.0, 0.0, 4000.0)
	assert_eq([stop.x, stop.fh, stop.moved], [100.0, 1, 0.0])
	var w := _world(["super_transformation"], 600)
	var slot := _mob(w, 250.0)
	w.swarm.fh[slot] = map.count()
	var before := [w.swarm.x[slot], w.swarm.y[slot], w.swarm.fh[slot]]
	assert_eq(w.swarm.pull(slot, 2000.0, 10.0, map, w.bounds), 0.0)
	assert_eq([w.swarm.x[slot], w.swarm.y[slot], w.swarm.fh[slot]], before, "pull leaves all coordinates unchanged")
	w.swarm.knockback(slot, 2000.0, 50.0, map, w.bounds)
	assert_eq([w.swarm.x[slot], w.swarm.y[slot], w.swarm.fh[slot]], before, "knockback leaves all coordinates unchanged")



func test_snatch_damage_and_targets_follow_the_rank() -> void:
	var targets := {1: 2, 4: 4, 8: 6}
	for r: int in targets:
		var w := _world(["super_transformation"], 600)
		w.loadout.set_rank("super_transformation", r)
		for i in 8:
			_mob(w, 100 + 20 * i)
		var hits := _of(_run(w, 0.6), "mob_hit", "snatch")
		assert_eq(hits.size(), targets[r], "rank %d targets" % r)
		assert_near(float(w.loadout.clone().stats("snatch", r).damage_pct), N_DAMAGE[r - 1] / 100.0, 1e-6)
	assert_eq([N_DAMAGE[0], N_DAMAGE[3], N_DAMAGE[7]], [240, 400, 600])


## Records how often Snatch's pull and its damage choose different mobs (BU-12: accepted, tier C): seeded crowds of 3 to 10 mobs at
## rank 4 (the pull takes up to 4), once spread to both sides of the caster and once all in front of it.
func _pull_damage_difference(rng: RandomNumberGenerator, lo_dx: float, hi_dx: float, trials: int) -> Dictionary:
	var differ := 0
	var from_behind := 0
	for t in trials:
		var w := _world(["super_transformation"], 600)
		var ids := []
		for i in rng.randi_range(3, 10):
			ids.append(_mob(w, rng.randf_range(lo_dx, hi_dx)))
		var st := w.loadout.clone().stats("snatch", 4)
		var before := {}
		for m: int in ids:
			before[m] = w.swarm.x[m]
		w.runner.apply_pull(w, "snatch", st, w.cast_origin())
		var pulled := ids.filter(func(m: int) -> bool: return w.swarm.x[m] != before[m])
		var struck: Array = []
		for m: int in ids:
			var rel: float = (w.swarm.x[m] - w.player.pos.x) * w.player.facing
			if rel >= 50.0 - 5.0 and rel <= 300.0 + 5.0:
				struck.append([absf(rel), m])
		struck.sort()
		var damaged := struck.slice(0, int(st.mob_count)).map(func(p: Array) -> int: return p[1])
		pulled.sort()
		damaged.sort()
		if pulled != damaged:
			differ += 1
		for m: int in pulled:
			if (before[m] - w.player.pos.x) * w.player.facing < 0.0:
				from_behind += 1
	return {"differ": differ, "behind": from_behind, "trials": trials}


func test_the_pull_and_the_damage_choose_their_own_sets_and_the_difference_is_measured() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 422
	var both := _pull_damage_difference(rng, -350.0, 350.0, 120)
	var front := _pull_damage_difference(rng, 60.0, 350.0, 120)
	print("B10 Snatch (rank 4, up to 4 mobs, 120 seeded crowds of 3-10): pull and damage sets differ in %d with mobs on both sides (%d pulled mobs came from behind), in %d with every mob in front" % [
		both.differ, both.behind, front.differ])
	assert_true(int(both.differ) > 0 and int(both.behind) > 0, "the pull also takes mobs behind the caster, the strip never does")
	assert_true(int(front.differ) < int(both.differ), "with every mob in front they agree more often: the dragged mobs land nearest")
	assert_true(int(front.differ) > 0, "but not always: a nearer mob inside the floor of the pull is struck without being pulled")


# --- the new text ------------------------------------------------------------------------------------------------

func test_card_text_reads_the_transforms_you_line_then_the_three_sub_lines() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	var tail := {
		1: "Transforms you for 15 s: defence +43, speed +40, jump +20. Snatch after 0.5 s, every 6 s (Lv4): Damage 240%, up to 2 monsters, stun for 1 sec. Pulls up to 2 monsters from 300 px Base 240% weapon damage, 2 targets; Shockwave after 1 s, every 3 s (Lv4): Damage 310%, up to 4 monsters. Base 310% weapon damage, 4 targets; Demolition after 2 s, every 5 s (Lv4): Damage 120% x 8, 1 monster, stun for 1 sec. Base 120% weapon damage, 1 targets",
		4: "Transforms you for 15 s: defence +50, speed +40, jump +20. Snatch after 0.5 s, every 6 s (Lv15): Damage 400%, up to 4 monsters, stun for 1 sec. Pulls up to 4 monsters from 300 px Base 400% weapon damage, 4 targets; Shockwave after 1 s, every 3 s (Lv15): Damage 475%, up to 5 monsters. Base 475% weapon damage, 5 targets; Demolition after 2 s, every 5 s (Lv15): Damage 240% x 8, 1 monster, stun for 1 sec. Base 240% weapon damage, 1 targets",
		8: "Transforms you for 15 s: defence +60, speed +40, jump +20. Snatch after 0.5 s, every 6 s (Lv30): Damage 600%, up to 6 monsters, stun for 1 sec. Pulls up to 6 monsters from 300 px Base 600% weapon damage, 6 targets; Shockwave after 1 s, every 3 s (Lv30): Damage 700%, up to 6 monsters. Base 700% weapon damage, 6 targets; Demolition after 2 s, every 5 s (Lv30): Damage 400% x 8, 1 monster, stun for 1 sec. Base 400% weapon damage, 1 targets"}
	for rank: int in tail:
		w.loadout.set_rank("super_transformation", rank)
		var line := text.level_line("super_transformation", rank, w.loadout.stats("super_transformation")).split("\n")[-1]
		assert_eq(line, tail[rank], "rank %d" % rank)
		assert_false("Charges" in line, line)


# --- rarity bonuses ----------------------------------------------------------------------------------------------

func test_the_rarity_table_is_the_spec_table() -> void:
	var bonuses: Dictionary = _world().book.def("super_transformation").rarity_bonuses
	var summary := {}
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		summary[tier] = (bonuses[tier] as Array).map(func(b: Dictionary) -> Array:
			return [b.id, b.effects.map(func(e: Dictionary) -> Array: return [e.stat, e.op, float(e.value)])])
	assert_eq(summary, {
		"rare": [["mastery", [["damage", "mul", 1.2]]]],
		"epic": [["booster", [["cooldown", "mul", 0.88]]]],
		"unique": [["time_leap", [["form_time", "mul", 1.25]]]],
		"legendary": [["time_leap", [["form_time", "mul", 1.25], ["damage", "mul", 1.2]]]]})
	assert_eq(bonuses.unique[0].text, "Time Leap")


# --- real cache --------------------------------------------------------------------------------------------------

func test_real_cache_numbers_at_all_eight_ranks_and_the_art_nodes() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.get_default()
	var img := library.img("Skill.wz/512.img")
	var img511 := library.img("Skill.wz/511.img")
	assert_true(img != null and img511 != null, "books 511 and 512 imported (cache-413 or any cache built after the Buccaneer fragment)")
	if img == null or img511 == null:
		return
	var root: Dictionary = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"511": img511.root, "512": root})
	var lo := Loadout.new(book)
	lo.add_skill("super_transformation")
	assert_eq(book.rank_table("super_transformation").map(func(v: Variant) -> int: return int(v)), S_LEVELS)
	for key in ["shockwave", "demolition", "snatch"]:
		assert_eq(book.rank_table(key).map(func(v: Variant) -> int: return int(v)), SUB_LEVELS, key)
	for rank in range(1, 9):
		lo.set_rank("super_transformation", rank)
		var row: Dictionary = root.skill["5121003"].level[str(S_LEVELS[rank - 1])]
		var st := lo.stats("super_transformation")
		assert_eq([int(row.pdd), int(row.mdd), int(row.speed), int(row.jump), int(row.morph)], [S_DEFENCE[rank - 1], S_DEFENCE[rank - 1], 40, 20, 1001],
			"rank %d: the WZ row" % rank)
		assert_eq(int(st.morph), 1001)
		assert_false(row.has("pad") or row.has("mad"), "no attack bonus in the node (the text says att., the node pdd/mdd)")
		var demo_row: Dictionary = root.skill["5121004"].level[str(SUB_LEVELS[rank - 1])]
		var demo := lo.clone().stats("demolition", rank)
		assert_eq([int(demo_row.damage), int(demo_row.attackCount), int(demo_row.time)], [D_DAMAGE[rank - 1], 8, 1], "rank %d: Demolition's WZ row" % rank)
		assert_near(float(demo.damage_pct), D_DAMAGE[rank - 1] / 100.0, 1e-6)
		assert_eq([int(demo.attack_count), int(demo.mob_count)], [8, 1])
		assert_eq(demo.box, Rect2(-300, -150, 280, 165))
		var snatch_row: Dictionary = root.skill["5121005"].level[str(SUB_LEVELS[rank - 1])]
		var snatch := lo.clone().stats("snatch", rank)
		assert_eq([int(snatch_row.damage), int(snatch_row.mobCount), int(snatch_row.time)], [N_DAMAGE[rank - 1], N_TARGETS[rank - 1], 1], "rank %d: Snatch's WZ row" % rank)
		assert_false(snatch_row.has("range") or snatch_row.has("prop"), "no range node and no prop: the definition's 300 and the always-pull")
		assert_near(float(snatch.damage_pct), N_DAMAGE[rank - 1] / 100.0, 1e-6)
		assert_eq(int(snatch.mob_count), N_TARGETS[rank - 1])
		assert_eq(snatch.box, Rect2(-300, -100, 250, 115))
		assert_near(float(snatch.range), 300.0, 1e-6)
		var shock := lo.clone().stats("shockwave", rank)
		assert_near(float(shock.damage_pct), SHOCK_DAMAGE[rank - 1] / 100.0, 1e-6, "Shockwave under Super reads the same row")
	# The art: Demolition's 23-frame hit/0 (the spec said 24), Snatch's 10-frame effect and 3-frame hit/0, the sounds, the morph stances.
	var hit: SpriteAnim = library.find_anim("Skill.wz/512.img/skill/5121004/hit/0")
	assert_true(hit != null and hit.frame_count() == 23, "Demolition hit/0: 23 frames")
	var effect: SpriteAnim = library.find_anim("Skill.wz/512.img/skill/5121005/effect")
	assert_true(effect != null and effect.frame_count() == 10, "Snatch effect: 10 frames")
	var snatch_hit: SpriteAnim = library.find_anim("Skill.wz/512.img/skill/5121005/hit/0")
	assert_true(snatch_hit != null and snatch_hit.frame_count() == 3, "Snatch hit/0: 3 frames")
	for path in ["5121003/Use", "5121004/Use", "5121004/Hit", "5121005/Use", "5121005/Hit"]:
		assert_true(library.sound("Sound.wz/Skill.img/" + path) != null, path)
	for action in ["demolition", "snatch"]:
		var morph: SpriteAnim = library.find_anim("Morph.wz/1001.img/" + action)
		assert_true(morph != null and morph.frame_count() == 11, "Morph 1001 has its own %s (11 frames)" % action)
	assert_true(library.missing.is_empty(), str(library.missing))
