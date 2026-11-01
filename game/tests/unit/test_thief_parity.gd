extends TestCase
## Thief parity (#208): seeded card application and fixed-tick combat through the shipping pool and runner.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const LINES := ["double_stab"]


func _world(path := "dagger") -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.player.hp = 50 + 125 # the removed first-job grant (+125/+37), folded into the base pools (#284)
	var setup := RF.with_basic_attack(RF.setup("quiet", 208, data))
	setup.equipment_info.merge({
		1472061: {"incPAD": 11, "attackSpeed": 5, "tuc": 7},
		1332063: {"incPAD": 28, "afterImage": "swordOL", "attackSpeed": 3, "tuc": 7},
	}, true)
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	RF.as_job(w, 400, path)
	w.heal_fraction("mp", 1.0)
	w.player.facing = 1
	w.god = true
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
		mk.no_flinch = true
	w.drain_events()
	return w


func _targets(w: RunWorld, offsets: Array) -> void:
	for offset: Vector2 in offsets:
		RF.put_mob(w, 1110100, w.player.pos.x + offset.x, 190 + offset.y, 10000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()


func _hits(events: Array, key := "double_stab") -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


func test_extra_hit_modifier_adds_one_damage_line_per_target_without_changing_other_skills() -> void:
	var w := _world()
	assert_true(w.learn_skill("double_stab"))
	assert_true(w.learn_skill("magic_claw"))
	w.loadout.add_skill_mod("double_stab", "attack_count", "add", 1)
	w.loadout.add_skill_mod("double_stab", "count", "add", 1)
	assert_eq(w.loadout.stats("double_stab").attack_count, 3)
	assert_eq(w.loadout.stats("magic_claw").attack_count, 2)
	_targets(w, [Vector2(35, 0), Vector2(45, 0)])
	w.runner.step(DT, w)
	var hits := _hits(w.drain_events())
	assert_eq(hits.size(), 6, "three lines on each of two targets")
	for x in [435.0, 445.0]:
		assert_eq(hits.filter(func(e: Dictionary) -> bool: return is_equal_approx(e.pos.x, x)).size(), 3)


func test_reach_modifier_expands_only_this_skills_envelope_on_both_sides() -> void:
	for side in [-1, 1]:
		var w := _world()
		assert_true(w.learn_skill("double_stab"))
		var basic_box := w.weapon_reach.envelope(w)
		assert_near(w.weapon_reach.reach(w), 88)
		_targets(w, [Vector2(100 * side, 0)])
		w.runner.step(DT, w)
		assert_true(_hits(w.drain_events()).is_empty(), "base envelope cannot reach 100px")
		w.loadout.add_skill_mod("double_stab", "area", "mul", 1.2)
		var st := w.loadout.stats("double_stab")
		assert_near(SkillRunner.reach_of(st, w), 105.6, 0.001, "the bot sees the expanded reach")
		assert_true(w.runner.has_target(w, "double_stab", st, w.cast_origin()), "short-MP probe uses the same box")
		w.runner.step(DT, w)
		assert_eq(_hits(w.drain_events()).size(), 2)
		assert_eq(w.player.facing, side)
		assert_eq(w.weapon_reach.envelope(w), basic_box, "the weapon swing envelope stays canonical")
		assert_near(w.weapon_reach.reach(w), 88)
		assert_near(SkillRunner.reach_of(w.loadout.stats("power_strike"), w), 88, 0.001, "another skill keeps base reach")
	var far := _world()
	far.learn_skill("double_stab")
	far.loadout.add_skill_mod("double_stab", "area", "mul", 1.2)
	_targets(far, [Vector2(120, 0)])
	var st := far.loadout.stats("double_stab")
	assert_false(far.runner.has_target(far, "double_stab", st, far.cast_origin()))
	far.runner.step(DT, far)
	assert_true(_hits(far.drain_events()).is_empty(), "the expanded box still has a far edge")


## SH6 #431 deleted Double Stab's five standalone behaviour cards (`double_stab_targets/hits/damage/cooldown/reach`, thirteen steps;
## the old "thirteen steps across five behaviour lines" test went with them). The modifier stats those cards applied are still
## the ones the rarity bonuses and Mastery use, so this checks the modifiers directly.
func test_the_legacy_double_stab_cards_are_gone() -> void:
	# SH14 #439: a Shadower is playable, so the pool generates Double Stab's plain new / rank cards; the explicit legacy cards
	# (targets, hits, damage, cooldown, reach) stay gone.
	var w := _world()
	var cards: Array = w.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.get("skill", "") == "double_stab")
	var ids := cards.map(func(c: Dictionary) -> String: return String(c.id))
	ids.sort()
	assert_eq(ids, ["double_stab_new", "double_stab_rank"], "only the pool-generated cards of the playable Shadower")
	for c: Dictionary in cards:
		assert_eq(String(c.get("desc", "")), "+1 rank", "%s is the generic pool card" % c.id)


func test_damage_and_cooldown_modifiers_scale_effective_stats_and_cast_cadence() -> void:
	for key: String in LINES:
		var casts: Array[int] = []
		for upgraded in [false, true]:
			var w := _world("dagger")
			w.learn_skill(key)
			var before := w.loadout.stats(key)
			if upgraded:
				for step in 2:
					w.loadout.add_skill_mod(key, "damage", "mul", 1.2)
					w.loadout.add_skill_mod(key, "cooldown", "mul", 0.88)
				var after := w.loadout.stats(key)
				assert_near(after.damage_min / before.damage_min, 1.44)
				assert_near(after.damage_max / before.damage_max, 1.44)
				assert_near(after.cooldown / before.cooldown, 0.7744)
			_targets(w, [Vector2(40, 0)])
			# Keep affordability out of this observation of cast cadence.
			for tick in 360:
				w.heal_fraction("mp", 1.0)
				w.step(DT, MoveInput.new())
			casts.append(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast" and e.skill == key).size())
		assert_true(casts[1] > casts[0], key + " casts more often over six seconds")
