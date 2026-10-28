extends TestCase
## Ice/Lightning Wizard attacks use canonical levels and the shared targeting/status seams with seeded combat.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(lightning_attr: String = "", bolt_mob_count: float = 2.0) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 56, data)
	setup.mob_imgs[1110100].info.elemAttr = lightning_attr
	# Synthetic level nodes: endpoints exercise rank-dependent damage, mastery, MP and freeze duration.
	setup.skill_imgs["220"] = {"skill": {
		"2201004": {"elemAttr": "i", "level": {
			"1": {"mad": 13.0, "mastery": 1.0, "mpCon": 12.0, "time": 1.0, "x": -100.0},
			"30": {"mad": 100.0, "mastery": 10.0, "mpCon": 24.0, "time": 2.0, "x": -100.0},
		}},
		"2201005": {"elemAttr": "l", "level": {
			"1": {"mad": 2.0, "mastery": 1.0, "mpCon": 20.0, "mobCount": bolt_mob_count,
				"lt": {"$v": [-150.0, -50.0]}, "rb": {"$v": [150.0, 50.0]}},
			"30": {"mad": 60.0, "mastery": 10.0, "mpCon": 40.0, "mobCount": 3.0,
				"lt": {"$v": [-170.0, -70.0]}, "rb": {"$v": [170.0, 70.0]}},
		}},
	}}
	var w := RunWorld.new(setup)
	RF.as_job(w, 220)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.drain_events()
	return w


func _targets(w: RunWorld) -> void:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()


func _events(w: RunWorld, type: String) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == type)


func test_cold_beam_cast_uses_rank_damage_and_guaranteed_freeze_except_bosses() -> void:
	for rank: int in [1, 30]:
		for boss: bool in [false, true]:
			var w := _world()
			assert_true(w.book.has("cold_beam"), "Cold Beam is defined")
			if not w.book.has("cold_beam"):
				return
			w.learn_skill("cold_beam")
			w.loadout.set_rank("cold_beam", rank)
			w.loadout.set_caster(100.0, 0.0, 30)
			var st := w.loadout.stats("cold_beam")
			assert_eq(st.level, rank)
			assert_eq(st.kind, "instant", "v83 has hit/effect art, no ball")
			assert_eq(st.element, "i")
			assert_near(st.damage_min, 16.683333 if rank == 1 else 263.333333, 0.0001)
			assert_near(st.damage_max, 54.166667 if rank == 1 else 416.666667, 0.0001)
			var m := RF.put_mob(w, 1110100, 300, 190, 100.0)
			w.swarm.mob_kind(m).mdd = 0
			w.swarm.mob_kind(m).boss = boss
			_targets(w)
			var hp_before := w.swarm.hp[m]
			w.runner.step(DT, w)
			var hits := _events(w, "mob_hit")
			assert_eq(hits.size(), 1, "one instant line on one target")
			if not hits.is_empty():
				assert_eq(hp_before - w.swarm.hp[m], hits[0].damage)
				assert_between(hits[0].damage, 17 if rank == 1 else 263, 54 if rank == 1 else 417)
			assert_near(w.swarm.status_time(m, MobSwarm.FREEZE),
				0.0 if boss else (1.0 if rank == 1 else 2.0), 0.0001)
			assert_eq(w.projectiles.active_count(), 0)


func test_thunder_bolt_admits_only_box_targets_caps_canonical_count_and_expands_with_area() -> void:
	for facing: int in [-1, 1]:
		var w := _world()
		assert_true(w.book.has("thunder_bolt"), "Thunder Bolt is defined")
		if not w.book.has("thunder_bolt"):
			return
		w.learn_skill("thunder_bolt")
		w.player.facing = facing
		for mk: MobKind in w.mob_kinds:
			mk.hitbox = Rect2(-5, -10, 10, 10)
		var outside := w.spawn_mob(int(w.kind_of_id[1110100]), w.player.pos + Vector2(165, 0), w.player.fh, 100.0, false)
		_targets(w)
		w.runner.step(DT, w)
		assert_eq(_events(w, "cast").size(), 0, "target beyond canonical box cannot trigger")
		w.loadout.add_skill_mod("thunder_bolt", "area", "mul", 1.2)
		assert_true((w.loadout.stats("thunder_bolt").box as Rect2).is_equal_approx(Rect2(-180, -60, 360, 120)))
		var mobs: Array[int] = []
		for dx: int in [-40, 40, -80, 80]:
			mobs.append(w.spawn_mob(int(w.kind_of_id[1110100]), w.player.pos + Vector2(dx, 0), w.player.fh, 100.0, false))
		_targets(w)
		w.runner.step(DT, w)
		var hits := _events(w, "mob_hit")
		assert_eq(hits.size(), 2, "synthetic canonical mobCount=2 caps crowded casts")
		assert_eq(hits.map(func(e: Dictionary) -> int: return e.mob), [mobs[0], mobs[1]])
		for m: int in [outside, mobs[2], mobs[3]]:
			assert_eq(w.swarm.hp[m], w.swarm.max_hp[m], "unselected targets take no damage")
		for m: int in mobs:
			w.swarm.despawn(m)
		w.runner.cooldowns["thunder_bolt"] = 0.0
		_targets(w)
		w.runner.step(DT, w)
		hits = _events(w, "mob_hit")
		assert_eq(hits.size(), 1, "area admits the formerly outside target")
		if not hits.is_empty():
			assert_eq(hits[0].mob, outside)


func test_thunder_bolt_target_card_raises_hits_in_a_crowded_box_by_two_per_step() -> void:
	for steps in range(0, 4):
		var w := _world("", 6.0) # the real v83 Thunder Bolt mobCount is 6 at every level
		w.upgrades.apply("thunder_bolt_new", w)
		for step in steps:
			assert_eq(w.upgrades.apply("thunder_bolt_targets", w), step + 1)
		for mk: MobKind in w.mob_kinds:
			mk.hitbox = Rect2(-5, -10, 10, 10)
		var mobs: Array[int] = []
		for i in 14:
			var dx := (i / 2 + 1) * 10 * (1 if i % 2 == 0 else -1)
			mobs.append(w.spawn_mob(int(w.kind_of_id[1110100]), w.player.pos + Vector2(dx, 0), w.player.fh, 100.0, false))
		_targets(w)
		w.runner.step(DT, w)
		var hit_mobs := {}
		for e: Dictionary in _events(w, "mob_hit"):
			hit_mobs[e.mob] = true
		assert_eq(hit_mobs.size(), 6 + 2 * steps, "%d card steps: distinct monsters hit by one cast" % steps)
	var w := _world()
	assert_false("thunder_bolt_targets" in w.upgrades.eligible(w), "needs Thunder Bolt learned")
	w.upgrades.apply("thunder_bolt_new", w)
	assert_has(w.upgrades.eligible(w), "thunder_bolt_targets")
	for step in 3:
		w.upgrades.apply("thunder_bolt_targets", w)
	assert_false("thunder_bolt_targets" in w.upgrades.eligible(w), "three steps cap the card")
	assert_eq(w.upgrades.apply("thunder_bolt_targets", w), 0)


func test_thunder_bolt_cast_applies_lightning_weakness_with_the_same_seed() -> void:
	var damage: Array[int] = []
	for attr: String in ["", "L3"]:
		var w := _world(attr)
		assert_true(w.book.has("thunder_bolt"))
		if not w.book.has("thunder_bolt"):
			return
		w.learn_skill("thunder_bolt")
		w.loadout.set_rank("thunder_bolt", 30)
		w.loadout.set_caster(1000.0, 0.0, 30)
		var m := RF.put_mob(w, 1110100, 300, 190, 100.0)
		w.swarm.mob_kind(m).mdd = 0
		_targets(w)
		w.runner.step(DT, w)
		var hits := _events(w, "mob_hit")
		assert_eq(hits.size(), 1)
		if not hits.is_empty():
			damage.append(int(hits[0].damage))
	if damage.size() == 2:
		assert_near(damage[1], damage[0] * 1.5, 1.0, "L3 gives 1.5x before integer rounding")


func test_ice_lightning_cards_gate_jobs_apply_steps_and_stop_at_caps() -> void:
	var w := _world()
	var ids := ["cold_beam_new", "cold_beam_rank", "cold_beam_targets", "cold_beam_cooldown",
		"thunder_bolt_new", "thunder_bolt_rank", "thunder_bolt_area", "thunder_bolt_targets", "thunder_bolt_cooldown"]
	for id: String in ids:
		var card := w.upgrades.card(id)
		assert_false(card.is_empty(), id)
		if card.is_empty():
			return
		assert_eq(card.requires.jobs, [220.0], id)
		assert_true(bool(card.get("power", false)), id)
	for job: int in [200, 210, 230]:
		RF.as_job(w, job)
		for id: String in ids:
			assert_false(id in w.upgrades.eligible(w), "%s excluded for job %d" % [id, job])
	RF.as_job(w, 220)
	for skill: String in ["cold_beam", "thunder_bolt"]:
		assert_has(w.upgrades.eligible(w), skill + "_new")
		assert_eq(w.upgrades.apply(skill + "_new", w), 1)
		assert_eq(w.loadout.rank(skill), 1)
		assert_false(skill + "_new" in w.upgrades.eligible(w))
		assert_has(w.upgrades.eligible(w), skill + "_rank")
		assert_eq(BotInput.card_score(w, {"id": skill + "_new"}), 100.0)
		assert_eq(BotInput.card_score(w, {"id": skill + "_rank"}), 74.0)
		var cooldown := float(w.loadout.stats(skill).cooldown)
		for step in range(1, 4):
			assert_eq(w.upgrades.apply(skill + "_cooldown", w), step)
			assert_near(w.loadout.stats(skill).cooldown, cooldown * pow(0.88, step), 0.0001)
		assert_false(skill + "_cooldown" in w.upgrades.eligible(w))
		assert_eq(w.upgrades.apply(skill + "_cooldown", w), 0, "cap rejects another step")
		assert_near(w.loadout.stats(skill).cooldown, cooldown * 0.681472, 0.0001)
		assert_eq(BotInput.card_score(w, {"id": skill + "_cooldown"}), 66.0)
		for consumed: int in [8, 16, 24, 29]:
			assert_eq(w.upgrades.apply(skill + "_rank", w, "legendary"), consumed)
		assert_eq(w.loadout.rank(skill), 30, "rank cards reach canonical maximum")
		assert_false(skill + "_rank" in w.upgrades.eligible(w))
		assert_eq(w.upgrades.apply(skill + "_rank", w), 0)
	for step in range(1, 4):
		assert_eq(w.upgrades.apply("cold_beam_targets", w), step)
		assert_eq(w.loadout.stats("cold_beam").count, 1 + step)
		assert_eq(w.upgrades.apply("thunder_bolt_area", w), step)
		assert_near(w.loadout.stats("thunder_bolt").area, pow(1.2, step), 0.0001)
	assert_false("cold_beam_targets" in w.upgrades.eligible(w))
	assert_eq(w.upgrades.apply("cold_beam_targets", w), 0)
	assert_eq(w.loadout.stats("cold_beam").count, 4)
	assert_false("thunder_bolt_area" in w.upgrades.eligible(w))
	assert_eq(w.upgrades.apply("thunder_bolt_area", w), 0)
	assert_near(w.loadout.stats("thunder_bolt").area, 1.728, 0.0001)
	assert_eq(BotInput.card_score(w, {"id": "cold_beam_targets"}), 87.0)
	assert_eq(BotInput.card_score(w, {"id": "thunder_bolt_area"}), 70.0)
	assert_eq(BotInput.card_score(w, {"id": "thunder_bolt_targets"}), 87.0, "scored like Cold Beam's target card")


func test_cold_beam_target_card_hits_and_freezes_distinct_nearest_monsters() -> void:
	var w := _world()
	w.upgrades.apply("cold_beam_new", w)
	w.upgrades.apply("cold_beam_targets", w, "legendary")
	var mobs: Array[int] = []
	for dx: int in [40, 80, 120, 160, 200]:
		mobs.append(RF.put_mob(w, 1110100, 200 + dx, 190, 100.0))
	_targets(w)
	w.runner.step(DT, w)
	var hits := _events(w, "mob_hit")
	assert_eq(hits.map(func(e: Dictionary) -> int: return e.mob), mobs.slice(0, 4))
	for m: int in mobs.slice(0, 4):
		assert_near(w.swarm.status_time(m, MobSwarm.FREEZE), 1.0)
	assert_near(w.swarm.status_time(mobs[4], MobSwarm.FREEZE), 0.0)


func test_real_cache_ice_lightning_levels_freeze_fields_art_and_use_sounds() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var tree := lib.img("Skill.wz/220.img").root
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"220": tree})
	var lo := Loadout.new(book)
	lo.set_caster(100.0, 0.0, 30)
	for key: String in ["cold_beam", "thunder_bolt"]:
		assert_eq(book.max_level(key), 30)
		assert_eq(book.max_rank(key), 30)
		lo.add_skill(key)
		assert_false(book.skill_node(key).has("ball"), "instant hit matches the real v83 art")
		for rank in range(1, 31):
			lo.set_rank(key, rank)
			var node := book.level_node(key, rank)
			var st := lo.stats(key)
			assert_eq(st.level, rank)
			if key == "cold_beam":
				assert_false(node.has("prop"), "no canonical proc roll")
				assert_eq(int(node.x), -100)
				assert_between(float(node.time), 1.0, 2.0)
			else:
				assert_eq(st.mob_count, 6)
				assert_eq(st.cast_rule, "box")
				assert_true(st.has_box)
		for field: String in ["hit", "effect"]:
			assert_true(lib.anim(book.visual(key, field, 30, 30)) != null, "%s %s" % [key, field])
		assert_true(lib.frame(String(book.def(key).icon)) != null)
		assert_true(lib.sound(String(book.def(key).sounds.use)) != null)
	assert_eq(lo.stats("cold_beam").element, "i")
	assert_near(lo.stats("cold_beam").damage_min, 263.333333, 0.0001)
	assert_near(lo.stats("cold_beam").damage_max, 416.666667, 0.0001)
	assert_eq(lo.stats("thunder_bolt").element, "l")
	assert_near(lo.stats("thunder_bolt").damage_min, 158.0, 0.0001)
	assert_near(lo.stats("thunder_bolt").damage_max, 250.0, 0.0001)
	assert_true((lo.stats("thunder_bolt").box as Rect2).is_equal_approx(Rect2(-170, -70, 340, 140)))
	assert_true(lib.missing.is_empty())
	lib.free()
