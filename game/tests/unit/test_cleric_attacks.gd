extends TestCase
## Cleric attack contracts through seeded RunWorld casts and the real upgrade pool; level nodes are synthetic.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(key: String) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.hp = 1000
	data.balance.player.mp = 1000
	var setup := RF.setup("quiet", 57, data)
	setup.skill_imgs["230"] = {"skill": {
		"2301005": {"elemAttr": "h", "level": {
			"1": {"mad": 22.0, "mastery": 1.0, "mpCon": 12.0},
			"7": {"mad": 34.0, "mastery": 3.0, "mpCon": 14.0}}},
		"2301002": {"level": {
			"1": {"hp": 10.0, "mpCon": 12.0, "mobCount": 6.0,
				"lt": {"$v": [-250.0, -150.0]}, "rb": {"$v": [250.0, 150.0]}},
			"7": {"hp": 70.0, "mpCon": 14.0, "mobCount": 6.0,
				"lt": {"$v": [-250.0, -150.0]}, "rb": {"$v": [250.0, 150.0]}}}},
	}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	RF.as_job(w, 200)
	RF.as_job(w, 230)
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_caster(100.0, 23.0, 30)
	w.drain_events()
	return w


func test_holy_arrow_canonical_rank_cost_damage_and_holy_weakness() -> void:
	var damage: Array = []
	for weak: bool in [false, true]:
		var w := _world("holy_arrow")
		assert_true(w.loadout.has("holy_arrow"))
		w.loadout.set_rank("holy_arrow", 7)
		var st := w.loadout.stats("holy_arrow")
		assert_eq(st.level, 7)
		assert_eq(st.mp_cost, 14)
		assert_eq(st.element, "h")
		# Worked standard magic formula: INT 100 + wand 23, mad 34, mastery 25%.
		assert_near(st.damage_min, 65.5112, 0.001)
		assert_near(st.damage_max, 173.5462, 0.001)
		var m := RF.put_mob(w, 1110100, 500, 190, 100.0)
		w.swarm.mob_kind(m).mdd = 0
		if weak:
			w.swarm.kinds[w.swarm.kind[m]] = MobKind.from_wz(
				{"info": {"elemAttr": "H3", "maxHP": 250.0}}, 1110100)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		var mp := int(w.player_state.mp)
		w.runner.step(DT, w)
		assert_eq(w.player_state.mp, mp - 14)
		assert_eq(w.projectiles.active_count(), 1)
		for tick in 30:
			w.projectiles.step(DT, w.swarm, w.mob_grid, w.events)
		var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
		assert_eq(hits.size(), 1)
		if not hits.is_empty():
			damage.append(int(hits[0].damage))
	if damage.size() == 2:
		assert_near(float(damage[1]), float(damage[0]) * 1.5, 1.0)


func test_heal_admission_restoration_and_recast_delay() -> void:
	var w := _world("heal")
	assert_true(w.loadout.has("heal"))
	var mp := int(w.player_state.mp)
	w.runner.step(DT, w)
	assert_false(w.runner.fired_this_tick, "full HP without undead waits")
	assert_eq(w.player_state.mp, mp)
	w.take_hit(650, false, "", w.player.pos - Vector2(10, 0))
	assert_true(int(w.player_state.hp) < int(w.player_state.max_hp) / 2)
	w.drain_events()
	var before := int(w.player_state.hp)
	w.runner.step(DT, w)
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1)
	var gains := events.filter(func(e: Dictionary) -> bool: return e.type == "player_restored")
	assert_eq(gains.size(), 1)
	# The historical single-target recovery fit: INT 100, LUK 4, Magic 123, Heal L1 => 19..24 HP.
	assert_between(int(w.player_state.hp) - before, 19, 24)
	if not gains.is_empty():
		assert_eq(gains[0].amount, int(w.player_state.hp) - before)
		assert_eq(gains[0].skill, "heal")
	assert_eq(w.player_state.mp, mp - 12)
	for tick in 118:
		w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "two-second survivor recast holds")
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 2, "still injured: recasts at two seconds")


func test_heal_holy_arrow_cards_are_cleric_only_and_behaviour_steps_match_first_job() -> void:
	var w := _world("holy_arrow")
	for id: String in ["holy_arrow_new", "holy_arrow_rank", "holy_arrow_count", "holy_arrow_pierce", "holy_arrow_cooldown", "heal_new", "heal_rank"]:
		var card := w.upgrades.card(id)
		assert_false(card.is_empty(), id)
		assert_eq(card.get("requires", {}).get("jobs"), [230.0], id)
	for id: String in ["holy_arrow_count", "holy_arrow_pierce", "holy_arrow_cooldown"]:
		var max_steps := 2 if id == "holy_arrow_pierce" else 3
		for pick in max_steps:
			assert_true(id in w.upgrades.eligible(w), id)
			w.upgrades.apply(id, w)
		assert_false(id in w.upgrades.eligible(w), "modifier cap: " + id)
	assert_eq(w.loadout.stats("holy_arrow").count, 4)
	assert_eq(w.loadout.stats("holy_arrow").pierce, 2)
	assert_near(w.loadout.stats("holy_arrow").cooldown, 0.681472, 0.00001)
	assert_near(BotInput.card_score(w, {"id": "holy_arrow_rank"}), 74.0)
	assert_near(BotInput.card_score(w, {"id": "holy_arrow_count"}), 87.0)
	w.progression.job_id = 220
	for id: String in w.upgrades.eligible(w):
		assert_false(id.begins_with("holy_arrow") or id.begins_with("heal_"), id)


func test_heal_at_full_hp_hits_every_boxed_undead_once_through_hit_hook() -> void:
	var w := _world("heal")
	w.loadout.set_rank("heal", 7)
	var normal := RF.put_mob(w, 100100, 430)
	var undead: Array[int] = []
	for i in 7:
		undead.append(RF.put_mob(w, 1110100, 450 + 10 * i, 190, 100.0))
	w.swarm.mob_kind(undead[0]).undead = true
	w.swarm.mob_kind(undead[0]).mdd = 0
	var outside := RF.put_mob(w, 1110100, 800, 190, 100.0)
	var hooks: Array = []
	w.add_hit_listener(func(slot: int, hit: Dictionary) -> void: hooks.append({"slot": slot, "hit": hit.duplicate()}))
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var normal_hp := w.swarm.hp[normal]
	var outside_hp := w.swarm.hp[outside]
	var mp := int(w.player_state.mp)
	w.runner.step(DT, w)
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1)
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "player_restored").size(), 0, "no gain at full HP")
	assert_eq(w.player_state.mp, mp - 14)
	assert_eq(hooks.size(), 7, "every undead, including beyond canonical six-target cap")
	for observed: Dictionary in hooks:
		assert_true(observed.slot in undead)
		assert_eq(observed.hit.skill, "heal")
		assert_eq(observed.hit.level, 7)
		assert_eq(observed.hit.magic, true)
		assert_eq(observed.hit.element, "h")
		assert_between(int(observed.hit.damage), 6, 23)
	assert_eq(w.swarm.hp[normal], normal_hp)
	assert_eq(w.swarm.hp[outside], outside_hp)
	assert_eq(w.projectiles.active_count(), 0)


func test_heal_half_hp_boundary_mp_wait_and_climbing_gate() -> void:
	var w := _world("heal")
	w.take_hit(650, false, "", w.player.pos - Vector2(10, 0))
	w.restore_player("hp", 500 - int(w.player_state.hp), "")
	w.runner.step(DT, w)
	assert_false(w.runner.fired_this_tick, "exactly half HP waits")
	for tick in 91:
		w.step(DT, MoveInput.new())
	w.take_hit(1, false, "", w.player.pos - Vector2(10, 0))
	w.spend_mp(int(w.player_state.mp))
	w.drain_events()
	w.runner.step(DT, w)
	assert_true(w.runner.waiting_mp)
	w.runner.step(DT, w)
	var shortages := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mp_short")
	assert_eq(shortages.size(), 1, "one shortage episode")
	w.restore_player("mp", 12, "")
	w.player.state = PlayerMotion.ST_LADDER
	w.runner.step(DT, w)
	assert_false(w.runner.fired_this_tick)
	w.player.state = PlayerMotion.ST_STAND
	w.runner.step(DT, w)
	assert_true(w.runner.fired_this_tick)
	assert_eq(w.player_state.mp, 0)


func test_heal_researched_damage_bounds_and_seeded_recovery() -> void:
	# Worked example from the RE rule: INT 100, LUK 4, Magic 123, hp 70%, two targets including self.
	var damage := CombatMath.heal_damage_range(100, 4, 23, 70, 2)
	assert_near(damage.x, 11.7096, 0.0001)
	assert_near(damage.y, 42.7056, 0.0001)
	var amounts: Array = []
	for repeat in 2:
		var w := _world("heal")
		w.take_hit(650, false, "", w.player.pos - Vector2(10, 0))
		w.drain_events()
		w.runner.step(DT, w)
		var gains := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_restored")
		assert_eq(gains.size(), 1)
		if not gains.is_empty():
			amounts.append(gains[0].amount)
	assert_eq(amounts.size(), 2)
	if amounts.size() == 2:
		assert_eq(amounts[0], amounts[1], "fixed seed reproduces the heal roll")


func test_heal_rank_preview_names_the_canonical_power_percentage() -> void:
	var w := _world("heal")
	# Only endpoints exist in this synthetic book: six rank steps reach its second fixture node.
	var card := w.upgrades.choice_card("heal_rank", w, "legendary")
	assert_eq(card.skill_changes.get("hp"), {"before": 10, "after": 70})
	assert_true("Recovery power: 10% → 70%" in LevelUpWindow.change_lines(card))


func test_cleric_cache_levels_visuals_and_sounds() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var root := lib.img("Skill.wz/230.img").root
	for key: String in ["holy_arrow", "heal"]:
		var w := _world(key)
		var id := "%07d" % w.book.skill_id(key)
		assert_eq(root.skill[id].level.size(), 30)
		for level in range(1, 31):
			assert_true(root.skill[id].level[str(level)].has("mpCon"))
		assert_true(lib.frame(String(w.book.def(key).icon)) != null)
		assert_true(lib.anim(String(w.book.def(key).effect)) != null)
		assert_true(lib.anim(String(w.book.def(key).hit)) != null)
		assert_true(lib.sound(String(w.book.def(key).sounds.use)) != null)
	assert_true(lib.anim("Skill.wz/230.img/skill/2301005/ball") != null)
	assert_eq(String(root.skill["2301005"].elemAttr), "h")
	assert_eq(int(root.skill["2301002"].level["30"].hp), 300)
	var arrow := _world("holy_arrow")
	arrow.book.skill_imgs["230"] = root
	for example: Array in [[1, 12, 34.2716, 112.2946], [30, 24, 257.464, 408.344]]:
		arrow.loadout.set_rank("holy_arrow", int(example[0]))
		var st := arrow.loadout.stats("holy_arrow")
		assert_eq(st.level, int(example[0]))
		assert_eq(st.mp_cost, int(example[1]))
		assert_near(st.damage_min, float(example[2]), 0.001, "original v83 endpoint with INT 100 / wand 23")
		assert_near(st.damage_max, float(example[3]), 0.001)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
