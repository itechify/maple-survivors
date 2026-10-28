extends TestCase
## Thief parity (#208): seeded card application and fixed-tick combat through the shipping pool and runner.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const LINES := {
	"lucky_seven": {"count": 3, "pierce": 2, "damage": 3, "cooldown": 3, "range": 2},
	"double_stab": {"targets": 3, "hits": 2, "damage": 3, "cooldown": 3, "reach": 2},
}


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


func test_each_path_has_thirteen_steps_across_five_behaviour_lines() -> void:
	var w := _world()
	for key: String in LINES:
		var cards := w.upgrades.cards.filter(func(c: Dictionary) -> bool:
			return c.get("skill", "") == key and c.kind == "skill_mod")
		assert_eq(cards.size(), 5, key)
		var steps := 0
		for line: String in LINES[key]:
			var c := w.upgrades.card(key + "_" + line)
			assert_false(c.is_empty(), key + "_" + line)
			assert_eq(int(c.get("max_rank", 0)), LINES[key][line], key + "_" + line)
			assert_true(UpgradePool.is_power(c), "every attack modifier counts for pity")
			steps += int(c.get("max_rank", 0))
		assert_eq(steps, 13, key)


func test_extra_hit_card_previews_and_applies_rarity_steps_per_target() -> void:
	for tier: String in ["normal", "rare", "legendary"]:
		var w := _world()
		w.learn_skill("double_stab")
		var offer := w.upgrades.choice_card("double_stab_hits", w, tier)
		var extra := 1 if tier == "normal" else 2
		assert_eq(offer.magnitude, extra)
		assert_eq(offer.skill_mod_changes.get("attack_count", {}), {"before": 2, "after": 2 + extra})
		assert_has(LevelUpWindow.change_lines(offer), "Hits: 2 → " + str(2 + extra))
		assert_true(w.upgrades.apply("double_stab_hits", w, tier))
		assert_eq(w.upgrades.rank("double_stab_hits", w), extra)
		assert_true(w.upgrades.apply("double_stab_targets", w))
		_targets(w, [Vector2(35, 0), Vector2(45, 0)])
		w.runner.step(DT, w)
		assert_eq(_hits(w.drain_events()).size(), 6 if tier == "normal" else 8)
		assert_false("double_stab_hits" in w.upgrades.eligible(w), "#287: behaviour cards are excluded")



func test_lucky_seven_extra_star_and_pierce_reach_more_monsters_in_seeded_combat() -> void:
	for upgraded in [false, true]:
		var w := _world("claw")
		w.learn_skill("lucky_seven")
		for mk: MobKind in w.mob_kinds:
			mk.hitbox = Rect2(-2, -40, 4, 40)
		if upgraded:
			assert_eq(w.upgrades.apply("lucky_seven_count", w), 1)
			assert_eq(w.upgrades.apply("lucky_seven_pierce", w), 1)
		_targets(w, [Vector2(100, 0), Vector2(150, 0)])
		w.runner.step(DT, w)
		assert_eq(w.projectiles.active_count(), 3 if upgraded else 2)
		w.drain_events()
		for tick in 25:
			w.step(DT, MoveInput.new())
		var hits := _hits(w.drain_events(), "lucky_seven")
		assert_eq(hits.size(), 6 if upgraded else 2, "each upgraded star hits both monsters once")


func test_range_and_reach_cards_compound_and_respect_their_two_step_cap() -> void:
	for key: String in LINES:
		var w := _world("claw" if key == "lucky_seven" else "dagger")
		w.learn_skill(key)
		var id := key + ("_range" if key == "lucky_seven" else "_reach")
		var offer := w.upgrades.choice_card(id, w, "rare")
		assert_eq(offer.magnitude, 2)
		assert_eq(offer.skill_mod_changes, {"range": {"before": 250, "after": 360}} if key == "lucky_seven"
			else {"area": {"before": 100, "after": 144}})
		assert_eq(w.upgrades.apply(id, w, "rare"), 2)
		assert_false(id in w.upgrades.eligible(w))
		assert_eq(w.upgrades.apply(id, w), 0, "cap cannot be exceeded")
		assert_near(SkillRunner.reach_of(w.loadout.stats(key), w), 360 if key == "lucky_seven" else 126.72, 0.001)
		_targets(w, [Vector2(330 if key == "lucky_seven" else 120, 0)])
		w.runner.step(DT, w)
		var events := w.drain_events()
		assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast" and e.skill == key).size(), 1)
		assert_eq(w.projectiles.active_count() if key == "lucky_seven" else _hits(events).size(), 2)


func test_damage_and_cooldown_cards_scale_effective_stats_and_cast_cadence() -> void:
	for key: String in LINES:
		var casts: Array[int] = []
		for upgraded in [false, true]:
			var w := _world("claw" if key == "lucky_seven" else "dagger")
			w.learn_skill(key)
			var before := w.loadout.stats(key)
			if upgraded:
				assert_eq(w.upgrades.apply(key + "_damage", w, "rare"), 2)
				assert_eq(w.upgrades.apply(key + "_cooldown", w, "rare"), 2)
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
