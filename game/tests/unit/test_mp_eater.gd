extends TestCase
## MP Eater's canonical monster pools, branch cards and seeded resolved-hit behaviour.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const KEYS := ["mp_eater_fp", "mp_eater_il", "mp_eater_cleric"]
const JOBS := [210, 220, 230]


func _setup() -> Dictionary:
	var setup := RF.setup()
	for job: int in JOBS:
		var levels := {}
		for level in range(1, 21):
			# Synthetic levels; canonical endpoints are independently checked against the real cache below.
			levels[str(level)] = {"prop": float(10 + level), "x": float(20 + level)}
		var book := str(job)
		if not setup.skill_imgs.has(book):
			setup.skill_imgs[book] = {"skill": {}}
		setup.skill_imgs[book].skill[str(job * 10000)] = {"level": levels}
	return setup


func test_monster_max_mp_is_canonical_and_defaults_to_zero() -> void:
	var kind := MobKind.from_wz({"info": {"maxHP": 50.0, "maxMP": 15.0}}, 210100, {"hp_mult": 3.0})
	assert_eq(kind.get("max_mp"), 15, "MP is independent of survivor HP scaling")
	assert_eq(MobKind.from_wz({}, 100100).get("max_mp"), 0, "absent maxMP means no MP")
	assert_eq(MobKind.from_wz({"info": {"maxMP": 0.0}}, 100100).get("max_mp"), 0)


func test_spawn_growth_and_reuse_reset_monster_mp() -> void:
	var kind := MobKind.from_wz({"info": {"maxMP": 15.0}}, 210100)
	var swarm := MobSwarm.new(1, [kind])
	var first := swarm.spawn(0, 0, 0, -1, 100)
	var mp: Variant = swarm.get("mp")
	assert_true(mp is PackedInt32Array, "per-slot MP is packed")
	if not (mp is PackedInt32Array):
		return
	assert_eq(mp[first], 15)
	swarm.mp[first] = 2
	var second := swarm.spawn(0, 0, 0, -1)
	assert_eq(swarm.mp[second], 15, "growing the pool initializes MP")
	assert_eq(swarm.mp[first], 2, "growth keeps depleted MP")
	swarm.despawn(first)
	assert_eq(swarm.mp[first], 0, "free slots hold no MP")
	var reused := swarm.spawn(0, 0, 0, -1)
	assert_eq(reused, first)
	assert_eq(swarm.mp[reused], 15, "a fresh monster has full MP")


func test_relocation_preserves_depleted_mp_and_fresh_spawn_refills_it() -> void:
	var w := RF.quiet_world()
	w.mob_kinds[0].max_mp = 200
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 3, false)
	w.swarm.mp[slot] = 7
	var moved := w.relocate_mob(slot, w.player.pos + Vector2(200, 0), w.player.fh)
	assert_eq(w.swarm.mp[moved], 7, "relocation cannot refill a drained monster")
	w.swarm.mp[moved] = 0
	var drained := w.relocate_mob(moved, w.player.pos + Vector2(300, 0), w.player.fh)
	assert_eq(w.swarm.mp[drained], 0)
	w.swarm.despawn(drained)
	var fresh := w.spawn_mob(0, w.player.pos, w.player.fh, 1, false)
	assert_eq(w.swarm.mp[fresh], 200)


func test_branch_cards_learn_and_rank_passive_only_in_their_job() -> void:
	for branch in JOBS.size():
		var w := RunWorld.new(_setup())
		RF.change_job_bare(w, JOBS[branch])
		var key: String = KEYS[branch]
		assert_true(w.book.has(key), "branch has MP Eater")
		if not w.book.has(key):
			continue
		assert_eq(w.book.skill_id(key), JOBS[branch] * 10000)
		assert_eq(w.book.kind(key), "passive")
		assert_false(w.book.is_active(key), "MP Eater never auto-casts")
		assert_eq(w.book.max_rank(key), 20)
		assert_has(w.upgrades.eligible(w), key + "_new")
		for other in JOBS.size():
			if other != branch:
				assert_false(KEYS[other] + "_new" in w.upgrades.eligible(w))
		w.upgrades.apply(key + "_new", w)
		assert_eq(w.loadout.level(key), 1)
		assert_has(w.upgrades.eligible(w), key + "_rank")
		w.upgrades.apply(key + "_rank", w)
		assert_eq(w.loadout.level(key), 2)
		w.loadout.set_rank(key, 20)
		assert_false(key + "_rank" in w.upgrades.eligible(w), "maxed passive has no rank offer")
		for card: Dictionary in w.upgrades.cards:
			if String(card.get("skill", "")) == key:
				assert_true(String(card.kind) in ["skill_new", "skill_rank"], "no behaviour cards")


func test_bot_prefers_attack_then_mp_eater_over_general_magnet() -> void:
	var w := RunWorld.new(_setup())
	RF.change_job_bare(w, 210)
	var learn := {"id": "mp_eater_fp_new"}
	assert_true(BotInput.card_score(w, {"id": "fire_arrow_new"}) > BotInput.card_score(w, learn))
	assert_true(BotInput.card_score(w, learn) > BotInput.card_score(w, {"id": "magnet"}))
	assert_true(BotInput.card_score(w, {"id": "mp_eater_fp_rank"}) > BotInput.card_score(w, learn))


func test_real_cache_mp_eater_levels_effects_and_monster_pools() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	var imgs := {}
	for job: int in JOBS:
		imgs[str(job)] = library.img("Skill.wz/%d.img" % job).root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	for key: String in KEYS:
		assert_eq(book.max_level(key), 20)
		assert_eq(book.canonical(key, 1, "prop"), 11.0)
		assert_eq(book.canonical(key, 1, "x"), 21.0)
		assert_eq(book.canonical(key, 20, "prop"), 30.0)
		assert_eq(book.canonical(key, 20, "x"), 40.0)
		assert_true(library.anim(book.visual(key, "effect", 1, 30)).duration() > 0.0)
	for id: int in [100100, 100101, 210100]:
		var img := library.img("Mob.wz/%07d.img" % id)
		var kind := MobKind.from_wz(img.root, id)
		assert_eq(kind.max_mp, {100100: 0, 100101: 15, 210100: 35}[id])
	assert_eq(library.missing, PackedStringArray(), "all required MP Eater assets are cached")
	library.free()


func _world(prop: float = 100.0, percent: float = 40.0, branch: int = 0, learn: bool = true) -> RunWorld:
	var setup := _setup()
	setup.data = RF.quiet_data()
	setup.stage = "quiet"
	setup.skill_imgs[str(JOBS[branch])].skill[str(JOBS[branch] * 10000)].level["1"] = {"prop": prop, "x": percent}
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.change_job(JOBS[branch])
	if learn:
		w.learn_skill(KEYS[branch])
	w.mob_kinds[0].max_mp = 200
	w.spend_mp(int(w.player_state.mp))
	w.drain_events()
	return w


func _hit(w: RunWorld, slot: int, magic: bool = true, damage: float = 1.0) -> void:
	w.hit_mob(slot, {"skill": "magic_claw" if magic else "basic_attack", "level": 1,
		"magic": magic, "damage_min": damage, "damage_max": damage, "crit": 0.0,
		"crit_mult": 1.5, "element": ""}, -1)


func _gains(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_restored")


func test_instant_magic_hit_absorbs_percent_of_max_mp_even_on_a_lethal_hit() -> void:
	var w := _world()
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1, false)
	_hit(w, slot, true, 10)
	assert_eq(w.swarm.mp[slot], 120, "40% of canonical 200 MP = 80, before kill handling")
	assert_eq(w.player_state.mp, 80)
	var gains := _gains(w)
	assert_eq(gains.size(), 1)
	if not gains.is_empty():
		assert_eq(gains[0].amount, 80)
		assert_eq(gains[0].stat, "mp")
		assert_eq(gains[0].skill, "mp_eater_fp")


func test_drain_caps_at_remaining_mp_and_player_maximum() -> void:
	var w := _world()
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1000, false)
	w.swarm.mp[slot] = 90
	w.restore_player("mp", int(w.player_state.max_mp) - 85, "")
	w.drain_events()
	_hit(w, slot)
	assert_eq(w.swarm.mp[slot], 10)
	assert_eq(_gains(w)[0].amount, 80)
	_hit(w, slot)
	assert_eq(w.swarm.mp[slot], 0, "the last absorb gives only remaining MP")
	assert_eq(w.player_state.mp, w.player_state.max_mp)
	assert_eq(_gains(w)[0].amount, 5, "gain number reports capped player gain")
	_hit(w, slot)
	assert_eq(w.swarm.mp[slot], 0, "never negative")
	assert_eq(_gains(w).size(), 0, "a drained monster gives nothing")


func test_absorb_effect_event_still_fires_when_player_mp_is_full() -> void:
	var w := _world()
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1000, false)
	w.restore_player("mp", int(w.player_state.max_mp), "")
	w.drain_events()
	_hit(w, slot)
	assert_eq(w.swarm.mp[slot], 120, "full player MP does not replenish monster MP")
	assert_eq(w.player_state.mp, w.player_state.max_mp)
	var events := w.drain_events()
	var absorbed := events.filter(func(e: Dictionary) -> bool: return e.type == "mp_eater_absorbed")
	assert_eq(absorbed.size(), 1, "every absorb has effect art, even when actual player gain is zero")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "player_restored").size(), 0)


func test_seeded_canonical_proc_frequency_and_replay() -> void:
	var counts := []
	for repeat in 2:
		var w := _world(30.0)
		var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 100000, false)
		var count := 0
		for line in 4000:
			w.swarm.mp[slot] = 200 # Independent full pools for the frequency measurement.
			_hit(w, slot)
			var absorbed := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mp_eater_absorbed")
			if not absorbed.is_empty():
				count += 1
				assert_eq(absorbed[0].amount, 80, "40% of 200 MP on every proc")
				assert_eq(w.swarm.mp[slot], 120)
		assert_between(count, 1080, 1320, "30% of 4000 hits, conservative statistical bounds")
		counts.append(count)
	assert_eq(counts[0], counts[1], "same seed reproduces absorb rolls")


func test_physical_instant_and_projectile_hits_never_absorb() -> void:
	var w := _world()
	w.loadout.order.assign(["mp_eater_fp"]) # Keep the owned passive, suppress auto-casting during impact.
	w.mob_kinds[0].move_speed = 0.0
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1000, false)
	_hit(w, slot, false)
	w.projectiles.spawn({"x": w.swarm.x[slot], "y": w.swarm.y[slot] - 5,
		"magic": false, "skill": "three_snails", "level": 1, "dmg_min": 1, "dmg_max": 1})
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.swarm.mp[slot], 200)
	assert_eq(w.player_state.mp, 0)
	var events := w.drain_events()
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit").size(), 2, "both physical lines landed")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "mp_eater_absorbed").size(), 0)


func test_magic_projectile_uses_current_passive_rank_at_impact() -> void:
	var w := _world()
	w.loadout.order.assign(["mp_eater_fp"])
	w.mob_kinds[0].move_speed = 0.0
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1, false)
	w.projectiles.spawn({"x": w.swarm.x[slot], "y": w.swarm.y[slot] - 5,
		"magic": true, "skill": "energy_bolt", "level": 1, "dmg_min": 10, "dmg_max": 10})
	w.book.skill_imgs["210"].skill["2100000"].level["2"] = {"prop": 100.0, "x": 50.0}
	w.loadout.set_rank("mp_eater_fp", 2)
	w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.swarm.mp[slot], 100, "50% from the passive's live rank, including lethal projectile")
	assert_eq(w.player_state.mp, 100)
	assert_eq(_gains(w).size(), 1)


func test_all_three_branch_passives_absorb_from_their_own_level_table() -> void:
	for branch in JOBS.size():
		var w := _world(100.0, 21.0, branch)
		var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1000, false)
		_hit(w, slot)
		assert_eq(w.swarm.mp[slot], 158)
		var gains := _gains(w)
		assert_eq(gains.size(), 1)
		if not gains.is_empty():
			assert_eq(gains[0].skill, KEYS[branch])
			assert_eq(gains[0].amount, 42)


func test_absorb_definition_uses_configured_fields_and_loadout_order_for_other_skill_keys() -> void:
	var w := _world(0.0, 0.0, 0, false)
	var expected: Array = []
	for index in 2:
		var key := "synthetic_absorb_%d" % index
		var original: String = KEYS[index]
		var definition := w.book.def(original).duplicate(true)
		definition.absorb_mp = {"chance_field": "custom_chance", "percent_field": "custom_percent"}
		w.book.defs[key] = definition
		var level := w.book.level_node(key, 1)
		level["custom_chance"] = 100.0
		level["custom_percent"] = 25.0 * (index + 1)
	# Reverse definition/old branch order to establish the listener's learned-order contract.
	for index in [1, 0]:
		var key := "synthetic_absorb_%d" % index
		w.learn_skill(key)
		expected.append(key)
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1000, false)
	w.drain_events()
	_hit(w, slot)
	var absorbed := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mp_eater_absorbed")
	assert_eq(absorbed.map(func(e: Dictionary) -> String: return String(e.skill)), expected)
	assert_eq(absorbed.map(func(e: Dictionary) -> int: return int(e.amount)), [100, 50])
	assert_eq(w.swarm.mp[slot], 50)


func test_inapplicable_passive_preserves_combat_rng_and_rounds_down_whole_mp() -> void:
	for reason: String in ["unowned", "drained", "zero_max", "fractional", "zero_chance", "physical"]:
		var control := _world(0.0)
		var w := _world(30.0, 40.0, 0, reason != "unowned")
		if reason in ["zero_max", "fractional"]:
			w.mob_kinds[0].max_mp = 0 if reason == "zero_max" else 1
		var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1000, false)
		var other := control.spawn_mob(0, control.player.pos + Vector2(100, 0), control.player.fh, 1000, false)
		if reason == "drained":
			w.swarm.mp[slot] = 0
		if reason == "zero_chance":
			w.book.skill_imgs["210"].skill["2100000"].level["1"].prop = 0.0
		for line in 100:
			_hit(w, slot, reason != "physical")
			_hit(control, other, reason != "physical")
		assert_eq(w.rng.state, control.rng.state, "%s consumes no passive RNG" % reason)
		assert_eq(_gains(w).size(), 0, reason)
	var rounded := _world(100.0, 21.0)
	rounded.mob_kinds[0].max_mp = 15
	var slot := rounded.spawn_mob(0, rounded.player.pos + Vector2(100, 0), rounded.player.fh, 1000, false)
	_hit(rounded, slot)
	assert_eq(rounded.swarm.mp[slot], 12, "21% of 15 = 3.15, truncated to 3 whole MP")
	assert_eq(rounded.player_state.mp, 3)


func test_poison_ticks_and_elementally_immune_hits_never_absorb() -> void:
	var w := _world()
	w.loadout.order.assign(["mp_eater_fp"])
	w.mob_kinds[0].move_speed = 0.0
	w.mob_kinds[0].elements["F"] = 0.0
	var slot := w.spawn_mob(0, w.player.pos + Vector2(100, 0), w.player.fh, 1000, false)
	w.hit_mob(slot, {"skill": "fire_arrow", "level": 1, "magic": true, "damage_min": 10.0,
		"damage_max": 10.0, "crit": 0.0, "crit_mult": 1.5, "element": "F"}, -1)
	w.projectiles.spawn({"x": w.swarm.x[slot], "y": w.swarm.y[slot] - 5,
		"magic": true, "skill": "fire_arrow", "level": 1, "element": "F", "dmg_min": 10, "dmg_max": 10})
	w.swarm.apply_status(slot, "poison", {"level": 1, "time": 1.0}, w.events)
	for tick in 60:
		w.step(1.0 / 60.0, MoveInput.new())
	assert_eq(w.swarm.mp[slot], 200)
	assert_eq(w.player_state.mp, 0)
	assert_eq(_gains(w).size(), 0)


func test_real_hit_presents_each_branch_effect_and_mp_gain_without_missing_sound() -> void:
	if not require_cache():
		return
	for branch in JOBS.size():
		var library := AssetLibrary.new()
		var scene: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
		scene.library = library
		scene.configure("henesys_hg1", 59, {"use_flow": false})
		var tree := Engine.get_main_loop() as SceneTree
		tree.current_scene.add_child(scene)
		var w := scene.world
		w.change_job(JOBS[branch])
		w.learn_skill(KEYS[branch])
		w.loadout.set_rank(KEYS[branch], 20)
		w.spend_mp(int(w.player_state.mp))
		w.drain_events()
		var kind := int(w.kind_of_id[210100])
		var slot := w.spawn_mob(kind, w.player.pos + Vector2(100, 0), w.player.fh, 100, false)
		var effects := scene.fx.active_count()
		var numbers := scene.numbers.active_count()
		var absorbed := false
		for line in 100:
			_hit(w, slot)
			var events := w.drain_events()
			if not events.filter(func(e: Dictionary) -> bool: return e.type == "mp_eater_absorbed").is_empty():
				scene.handle_events(events)
				absorbed = true
				break
		assert_true(absorbed, "seeded real-cache magic hit procs branch MP Eater")
		assert_eq(scene.fx.active_count(), effects + 1, "canonical absorb effect is pooled")
		assert_eq(scene.numbers.active_count(), numbers + 2, "hit damage plus actual MP gain")
		assert_eq(library.missing, PackedStringArray(), "no lookup for the absent optional Sound.wz entry")
		scene.free()
		library.free()
