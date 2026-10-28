extends TestCase
## SkillBook / Loadout stat resolution (canonical numbers from synthetic Skill.wz imgs, survivor numbers from
## skills.json, upgrade modifiers from upgrades.json) and SkillRunner auto-casting on the synthetic map.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _casts(w: RunWorld) -> Array:
	var out: Array = []
	for e: Dictionary in w.drain_events():
		if e.type == "cast":
			out.append(e)
	return out


func test_skill_book_levels_and_paths() -> void:
	var w := RF.quiet_world()
	var b := w.book
	assert_eq(b.skill_id("three_snails"), 1000)
	assert_eq(b.key_for_id(2001004), "energy_bolt")
	assert_eq(b.wz_path("three_snails"), "Skill.wz/000.img/skill/0001000")
	assert_eq(b.max_rank("three_snails"), 3)
	for r in range(1, 4):
		assert_eq(b.canonical_level("three_snails", r), r, "Three Snails rank = level")
	for r in range(1, 21):
		assert_eq(b.canonical_level("energy_bolt", r), r, "Energy Bolt rank %d" % r)
	assert_eq(b.canonical_level("energy_bolt", 21), 20, "clamped to the last rank")
	assert_eq(b.canonical_level("magic_armor", 20), 20)
	assert_eq(b.max_level("energy_bolt"), 20, "levels in the img")
	assert_near(b.canonical("three_snails", 2, "fixdamage"), 25.0, 1e-9, "read from skill_imgs")
	assert_near(b.canonical("energy_bolt", 20, "mad"), 55.0, 1e-9)
	assert_near(b.canonical("magic_claw", 1, "attackCount"), 2.0, 1e-9)
	assert_eq(b.visual("three_snails", "ball", 3, 1), "Skill.wz/000.img/skill/0001000/level/3/ball")
	assert_eq(b.visual("magic_claw", "hit", 1, 9), "Skill.wz/200.img/skill/2001005/hit/0", "below CharLevel 10")
	assert_eq(b.visual("magic_claw", "hit", 1, 12), "Skill.wz/200.img/skill/2001005/CharLevel/10/hit/0")
	assert_eq(b.visual("magic_claw", "effect", 1, 27), "Skill.wz/200.img/skill/2001005/CharLevel/25/effect")
	assert_true(b.is_active("magic_claw"))
	assert_true(b.is_active("magic_armor"), "timed buff participates in auto-casting")


func test_three_snails_base_stats() -> void:
	var w := RF.quiet_world()
	assert_true(w.loadout.has("three_snails"), "a Beginner starts with Three Snails")
	var st := w.loadout.stats("three_snails")
	assert_eq(st.skill_id, 1000)
	assert_eq(st.rank, 1)
	assert_eq(st.level, 1)
	assert_eq(st.damage_type, "fixed")
	assert_near(st.damage_min, 10.0, 1e-6, "canonical fixdamage L1")
	assert_near(st.damage_max, 10.0, 1e-6)
	assert_near(st.cooldown, 1.1, 1e-6)
	assert_near(st.range, 420.0, 1e-6)
	assert_near(st.speed, 400.0, 1e-6)
	assert_eq(st.count, 1)
	assert_eq(st.pierce, 0)
	assert_eq(st.ball, "Skill.wz/000.img/skill/0001000/level/1/ball")
	assert_eq(st.hit, "Skill.wz/000.img/skill/0001000/level/1/hit/0")
	assert_eq(st.action, "swingO1")


func test_three_snails_upgrades() -> void:
	var w := RF.quiet_world()
	var up := w.upgrades
	up.apply("three_snails_count", w)
	assert_eq(w.loadout.stats("three_snails").count, 2, "Additional Shell +1")
	up.apply("three_snails_cooldown", w)
	assert_near(w.loadout.stats("three_snails").cooldown, 1.1 * 0.88, 1e-5, "Faster Snails x0.88")
	up.apply("three_snails_cooldown", w)
	assert_near(w.loadout.stats("three_snails").cooldown, 1.1 * 0.88 * 0.88, 1e-5, "x0.88 per rank")
	up.apply("three_snails_pierce", w)
	assert_eq(w.loadout.stats("three_snails").pierce, 1, "Piercing Shells +1")
	up.apply("three_snails_speed", w)
	assert_near(w.loadout.stats("three_snails").speed, 500.0, 1e-3, "Rapid Snails +25%")
	w.loadout.set_rank("three_snails", 2)  # what level_ranks does at character Lv 3
	var st := w.loadout.stats("three_snails")
	assert_eq(st.rank, 2, "rank 2")
	assert_eq(st.level, 2, "-> canonical level 2")
	assert_near(st.damage_min, 25.0, 1e-6, "-> fixdamage 25")
	assert_eq(st.ball, "Skill.wz/000.img/skill/0001000/level/2/ball", "-> the level-2 shell")
	assert_eq(st.hit, "Skill.wz/000.img/skill/0001000/level/2/hit/0")
	w.loadout.set_rank("three_snails", 3)  # character Lv 6
	st = w.loadout.stats("three_snails")
	assert_eq(st.level, 3)
	assert_near(st.damage_max, 40.0, 1e-6, "rank 3 -> fixdamage 40")
	assert_eq(w.loadout.card_ranks.three_snails_cooldown, 2)


func test_magic_skills_resolve_from_canonical_levels() -> void:
	var w := RF.quiet_world()
	w.change_job(200)
	w.learn_skill("energy_bolt")
	w.learn_skill("magic_claw")
	w.learn_skill("magic_armor")
	var int_stat := float(w.player_state.int)
	var eb := w.loadout.stats("energy_bolt")
	var expect := CombatMath.magic_damage_range(int_stat, 23.0, 20.0, 0.15)
	assert_eq(eb.damage_type, "magic")
	assert_true(eb.magic)
	assert_near(eb.damage_min, expect.x, 1e-3, "Energy Bolt L1 min with INT and the wand's 23 magic attack")
	assert_near(eb.damage_max, expect.y, 1e-3, "max")
	w.upgrades.apply("energy_bolt_damage", w)
	assert_near(w.loadout.stats("energy_bolt").damage_max, expect.y * 1.2, 1e-3, "Overcharge +20%")
	w.upgrades.apply("energy_bolt_rank", w)
	var eb2 := w.loadout.stats("energy_bolt")
	assert_eq(eb2.level, 2, "rank 2 = level 2")
	var mad2 := w.book.canonical("energy_bolt", 2, "mad")
	var mas2 := CombatMath.mastery_fraction(int(w.book.canonical("energy_bolt", 2, "mastery")))
	assert_near(eb2.damage_max, CombatMath.magic_damage_range(int_stat, 23.0, mad2, mas2).y * 1.2, 1e-3)
	var mc := w.loadout.stats("magic_claw")
	assert_eq(mc.kind, "instant")
	assert_eq(mc.attack_count, 2, "canonical attackCount")
	assert_near(mc.range, 260.0, 1e-6)
	var ma := w.loadout.stats("magic_armor")
	assert_eq(ma.buff_stat, "pdd")
	assert_near(ma.buff_value, 2.0, 1e-6, "Magic Armor L1 pdd = 2")
	w.loadout.set_rank("magic_armor", 20)
	assert_near(w.loadout.stats("magic_armor").buff_value, 40.0, 1e-6, "rank 20 = level 20: pdd = 40")
	assert_near(w.player_pdd, 0.0, 1e-6, "no permanent defence")


func test_runner_fires_only_with_target_in_range() -> void:
	var data := RF.quiet_data()
	var w := RunWorld.new(RF.setup("quiet", 7, data))
	RF.place_player(w, 200)
	for i in 60:
		w.step(DT, MoveInput.new())
	assert_eq(_casts(w).size(), 0, "no mob, no cast")
	var far := RF.put_mob(w, 1110100, 700.0, 190.0, 20.0)
	for i in 60:
		w.step(DT, MoveInput.new())
	assert_eq(_casts(w).size(), 0, "a mob ~500 px away is out of the 420 px range")
	w.swarm.despawn(far)
	RF.put_mob(w, 1110100, 500.0, 190.0, 20.0)
	w.drain_events()
	var times: Array = []
	for i in 140:
		w.step(DT, MoveInput.new())
		for c: Dictionary in _casts(w):
			times.append(w.time)
			assert_eq(c.skill, "three_snails")
			assert_eq(c.skill_id, 1000)
			assert_eq(c.level, 1)
			assert_eq(c.action, "swingO1")
	assert_eq(times.size(), 3, "casts at once, then every 1.1 s: %s" % [times])
	if times.size() == 3:
		assert_near(times[1] - times[0], 1.1, DT + 1e-6, "cooldown respected")
		assert_near(times[2] - times[1], 1.1, DT + 1e-6)
	assert_eq(w.player_state.action, "swingO1", "standing still: the cast stance")


func test_runner_extra_shells_pick_different_targets() -> void:
	var w := RF.quiet_world(200.0)
	w.upgrades.apply("three_snails_count", w)
	var a := RF.put_mob(w, 1110100, 450.0, 190.0, 20.0)
	var b := RF.put_mob(w, 1110100, 30.0, 190.0, 20.0)
	w.step(DT, MoveInput.new())
	var p := w.projectiles
	var dirs: Array = []
	var o := w.cast_origin()
	for i in p.capacity():
		if p.active[i] != 0:
			dirs.append(signf(p.vx[i]))
			# Each shell leaves from the hand on its target's side (cast_forward px in front of the body), not the face.
			assert_near(p.x[i] - p.vx[i] * DT, o.x + signf(p.vx[i]) * w.cast_forward, 1.0, "shell start x")
	assert_eq(w.cast_forward, 22.0, "balance.json player.cast_forward")
	assert_eq(dirs.size(), 2, "two shells")
	assert_true(1.0 in dirs and -1.0 in dirs, "one toward each mob, not both at the nearest: %s" % [dirs])
	assert_ne(a, b)


func test_magic_claw_instant_two_hits() -> void:
	var w := RF.quiet_world(200.0)
	RF.change_job_bare(w, 200)
	w.learn_skill("magic_claw")
	w.loadout.ranks.erase("three_snails")
	w.loadout.order.erase("three_snails")
	w.loadout.version += 1
	var m := RF.put_mob(w, 1110100, 380.0, 190.0, 20.0)
	w.drain_events()
	w.step(DT, MoveInput.new())
	var hits := 0
	var casts := 0
	for e: Dictionary in w.drain_events():
		if e.type == "mob_hit":
			hits += 1
			assert_eq(e.mob, m)
			assert_eq(e.skill, "magic_claw")
			assert_eq(e.hit_visual, "Skill.wz/200.img/skill/2001005/hit/0")
		elif e.type == "cast":
			casts += 1
			assert_eq(e.effect, "Skill.wz/200.img/skill/2001005/effect")
	assert_eq(casts, 1)
	assert_eq(hits, 2, "attackCount 2 lines at once")
	assert_eq(w.projectiles.active_count(), 0, "no projectile")
	var out_of_range := RF.quiet_world(200.0)
	RF.change_job_bare(out_of_range, 200)
	out_of_range.learn_skill("magic_claw")
	out_of_range.loadout.ranks.erase("three_snails")
	out_of_range.loadout.order.erase("three_snails")
	out_of_range.loadout.version += 1
	RF.put_mob(out_of_range, 1110100, 520.0, 190.0, 20.0)
	out_of_range.step(DT, MoveInput.new())
	assert_eq(_casts(out_of_range).size(), 0, "320 px is beyond Magic Claw's 260 px")
