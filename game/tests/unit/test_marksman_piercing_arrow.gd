extends TestCase
## Piercing Arrow (3221001), the Marksman's charged line nuke (spec #360, ticket MS7 #367): the shipped definition in
## skills/marksman.json on the burst rule (count 1 and a wind-up, B4) and the piercing rise (MS4), on a synthetic book 322 whose
## damage and mobCount rows are the v83 values, held with a crossbow. The wind-up, the release and the aim, the rising factor per
## contact, the rank's monster count, the rarity bonuses, the text, the cancels, the presentation and the bot. Seeded RNG, fixed dt.
## The mapped levels of all eight ranks are asserted against the real cache at the bottom (SKIPPED without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const HURRICANE := preload("res://tests/unit/test_hurricane.gd")
const DT := 1.0 / 60.0
const CROSSBOW := 1462001
const KEY := "piercing_arrow"
const SNAIL := 1110100
const TIERS := ["rare", "epic", "unique", "legendary"]
const RANK_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30] # tier C: the 30-level mapping every 30-level skill uses
## Skill.wz 322.img/skill/3221001/level/<n>/damage and mobCount, levels 1..30 (tier A, read from the v83 data).
const WZ_DAMAGE := [320, 340, 360, 380, 400, 420, 440, 460, 480, 500, 520, 540, 560, 580, 600, 620, 640, 660, 680, 700, 715, 730,
	745, 760, 775, 790, 805, 820, 835, 850]
const WZ_MOBS := [4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 6, 6, 6]
## The release of the first (and only) arrow: the wind-up in ticks after the admission tick.
const WIND_UP_TICKS := 36


func _levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 18.0, "damage": float(WZ_DAMAGE[lv - 1]), "mobCount": float(WZ_MOBS[lv - 1])}
	return levels


## A quiet round of a Marksman holding a crossbow with Piercing Arrow learned at `rank_value`; mobs stand still, snail-sized.
func _world(rank_value := 1, p_seed := 367) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["322"]["playable"] = true # in this test's data only: MS11 ships the flip
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.data.stages.stages.quiet.maps.append(setup.data.stages.stages.quiet.maps[0].duplicate(true)) # a map to transfer to
	setup.equipment_info.merge({CROSSBOW: {"incPAD": 29, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.skill_imgs["322"] = {"skill": {"3221001": {"level": _levels(), "prepare": RF.anim(20, 60.0), "effect": RF.anim(5, 100.0),
		"ball": RF.anim(5, 100.0), "hit": {"0": RF.anim(6, 100.0)}}}}
	setup["job"] = 322
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != CROSSBOW:
		w.wear_new_item(CROSSBOW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
		mk.pdd = 0 # defence would split the damage range; the rise is the only thing that varies a pinned hit
	w.player.facing = 1
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Iron Arrow): only Piercing Arrow casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(KEY), "piercing arrow is learnable by a Marksman")
	w.loadout.set_rank(KEY, rank_value)
	w.loadout.add_skill_mod(KEY, "crit", "add", -1.0) # no crit rolls: the rise is the only thing that varies a hit
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, hp := 100000000.0) -> int:
	var slot := RF.put_mob(w, SNAIL, w.player.pos.x + dx, 190)
	w.swarm.max_hp[slot] = int(hp)
	w.swarm.hp[slot] = int(hp)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


## `count` monsters in a line from 100 px ahead of the caster, `gap` px apart (the arrow's range is 450).
func _line(w: RunWorld, count: int, gap := 60.0) -> Array:
	var slots := []
	for k in count:
		slots.append(_mob(w, 100.0 + gap * k))
	return slots


func _shots(w: RunWorld) -> int:
	return w.projectiles.active.count(1)


func _ticks(w: RunWorld, n: int) -> void:
	for i in n:
		w.step(DT, MoveInput.new())


## The hit damages of the cast in the order they landed: the arrow is released, its damage range is pinned to one value (the
## roll is the only other variable) and it flies through the line.
func _flight(w: RunWorld) -> Array:
	var guard := 0
	while _shots(w) == 0 and guard < 200:
		_ticks(w, 1)
		guard += 1
	var slot: int = w.projectiles.active.find(1)
	assert_true(slot >= 0, "the arrow was released")
	w.projectiles.dmg_min[slot] = w.projectiles.dmg_max[slot]
	var events := w.drain_events()
	for tick in 90:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and String(e.get("skill", "")) == KEY) \
		.map(func(e: Dictionary) -> int: return int(e.damage))


# --- the definition ---------------------------------------------------------------------------------------------------

func test_the_definition_follows_the_specs_row() -> void:
	var w := _world()
	var d := w.book.def(KEY)
	assert_eq(int(d.skill_id), 3221001)
	assert_eq(String(d.book), "322")
	assert_eq(int(d.job), 322)
	assert_eq(String(d.kind), "projectile")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "physical")
	assert_false(d.has("weapon_families"), "skills have no weapon gate")
	assert_eq(d.cast, {"rule": "burst"})
	assert_eq(d.burst, {"wind_up": 0.6})
	assert_eq(int(d.count), 1)
	assert_eq(float(d.cooldown), 6.0)
	assert_eq(float(d.range), 450.0)
	assert_eq(float(d.speed), 900.0)
	assert_eq(float(d.radius), 10.0)
	assert_eq(int(d.pierce), 0)
	assert_eq(String(d.pierce_field), "mobCount")
	assert_eq(float(d.pierce_falloff), -0.1)
	assert_eq(String(d.action), "weapon", "the crossbow's shoot2, never the body dash prepare/action names")
	assert_eq(String(d.effect), "", "the effect plays at the release (burst_art.end), not at the cast")
	assert_eq(String(d.ball), "Skill.wz/322.img/skill/3221001/ball", "its own ball, not the ammo's sprite")
	assert_eq(String(d.hit), "Skill.wz/322.img/skill/3221001/hit/0")
	assert_eq(d.burst_art, {"prepare": "Skill.wz/322.img/skill/3221001/prepare", "end": "Skill.wz/322.img/skill/3221001/effect",
		"end_on_drop": false})
	assert_eq(d.sounds, {"use": "Sound.wz/Skill.img/3221001/Use", "loop": "Sound.wz/Skill.img/3221001/Loop",
		"hit": "Sound.wz/Skill.img/3221001/Hit"})
	assert_eq(w.book.max_rank(KEY), 8)
	assert_eq(w.book.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), RANK_LEVELS)
	assert_true(KEY in w.jobs.skill_pool(322), "it is in the Marksman's pool")


func test_the_resolved_cast_reads_the_rank_level() -> void:
	var w := _world()
	for rank_value in range(1, 9):
		var st := w.loadout.stats(KEY, rank_value)
		var lv: int = RANK_LEVELS[rank_value - 1]
		assert_near(float(st.damage_pct), float(WZ_DAMAGE[lv - 1]) / 100.0, 1e-6, "rank %d" % rank_value)
		assert_eq(int(st.pierce), WZ_MOBS[lv - 1] - 1, "rank %d: mobCount - 1 more monsters" % rank_value)
		assert_eq(int(st.count), 1)
		assert_eq(float(st.pierce_falloff), -0.1, "the rise is captured from the definition")
		assert_eq(float(st.pierce_ceiling), 2.0, "balance.combat.pierce_ceiling")
	assert_near(float(w.loadout.stats(KEY, 1).damage_pct), 3.8, 1e-6)
	assert_near(float(w.loadout.stats(KEY, 4).damage_pct), 6.0, 1e-6)
	assert_near(float(w.loadout.stats(KEY, 8).damage_pct), 8.5, 1e-6)
	assert_eq([w.loadout.stats(KEY, 1).pierce + 1, w.loadout.stats(KEY, 4).pierce + 1, w.loadout.stats(KEY, 8).pierce + 1], [4, 5, 6])


# --- the cast ---------------------------------------------------------------------------------------------------------

func test_the_arrow_leaves_exactly_at_the_wind_up() -> void:
	var w := _world()
	_mob(w, 300)
	_ticks(w, 1)
	assert_eq(w.runner.casts, 1)
	assert_eq(_shots(w), 0, "nothing flies during the wind-up")
	_ticks(w, WIND_UP_TICKS - 1)
	assert_eq(_shots(w), 0, "not yet at 0.6 s - one tick")
	_ticks(w, 1)
	assert_eq(_shots(w), 1, "0.6 s after admission")
	_ticks(w, 120)
	assert_eq(w.runner.casts, 1, "one cast, one arrow, however long the cooldown runs")
	assert_true(w.drain_events().any(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == KEY), "and it struck")
	assert_false(w.runner.bursts.has_skill(KEY))


func test_the_stance_is_the_crossbows_shooting_stance_for_the_wind_up() -> void:
	var w := _world()
	_mob(w, 300)
	_ticks(w, 1)
	assert_eq(w.upkeep.cast_action, "shoot2", "weapon resolves to the crossbow's shoot2, not the body dash")
	assert_true(w.upkeep.cast_left >= 0.59, "held for the whole wind-up: %f" % w.upkeep.cast_left)


func test_the_arrow_is_aimed_at_the_targets_position_at_the_release() -> void:
	var still := _world()
	var m0 := _mob(still, 300)
	var moved := _world()
	var m1 := _mob(moved, 300)
	_ticks(still, 1)
	_ticks(moved, 1)
	_ticks(still, WIND_UP_TICKS - 1)
	_ticks(moved, WIND_UP_TICKS - 1)
	moved.swarm.y[m1] = 60.0 # the monster is somewhere else when the bow is released
	moved.mob_grid.rebuild(moved.swarm.x, moved.swarm.y, moved.swarm.active)
	still.runner.step(DT, still) # the release tick alone: the swarm's own step would put the climber back on its foothold
	moved.runner.step(DT, moved)
	assert_eq(_shots(still), 1)
	assert_eq(_shots(moved), 1)
	var a: int = still.projectiles.active.find(1)
	var b: int = moved.projectiles.active.find(1)
	assert_true(absf(still.projectiles.vy[a]) < 80.0, "a standing monster: a flat shot (%f)" % still.projectiles.vy[a])
	assert_true(moved.projectiles.vy[b] < still.projectiles.vy[a] - 200.0, "the arrow rises to where the monster is now (%f)" % moved.projectiles.vy[b])
	assert_eq(m0, m1)


func test_the_cooldown_starts_at_the_cast_not_at_the_release() -> void:
	var w := _world()
	_mob(w, 300)
	_ticks(w, 1)
	assert_true(float(w.runner.cooldowns[KEY]) > 5.9, "6 s from the admission tick")
	_ticks(w, WIND_UP_TICKS)
	assert_true(float(w.runner.cooldowns[KEY]) < 5.45, "the wind-up already ran down %f" % float(w.runner.cooldowns[KEY]))
	_ticks(w, 6 * 60 - WIND_UP_TICKS - 4)
	assert_eq(w.runner.casts, 1, "no second cast before 6 s after the first")
	_ticks(w, 8)
	assert_eq(w.runner.casts, 2, "ready 6 s after the first cast")


func test_contact_n_deals_the_rising_factor() -> void:
	var w := _world(8)
	_line(w, 8)
	var hits := _flight(w)
	assert_eq(hits.size(), 6, "rank 8: six monsters")
	for n in hits.size():
		assert_true(absi(hits[n] - roundi(hits[0] * (1.0 + 0.1 * n))) <= 1,
			"contact %d is %d%% of the first: %s" % [n + 1, 100 + 10 * n, str(hits)])
	assert_true(hits[5] > hits[0] * 1.45 and hits[5] < hits[0] * 1.55, "the sixth takes 150%%: %s" % str(hits))


func test_the_monster_count_follows_the_rank() -> void:
	for pair: Array in [[1, 4], [4, 5], [8, 6]]:
		var w := _world(int(pair[0]))
		_line(w, 8)
		assert_eq(_flight(w).size(), int(pair[1]), "rank %d strikes %d monsters" % [int(pair[0]), int(pair[1])])


func test_a_higher_rank_hits_harder() -> void:
	var totals := []
	for rank_value in [1, 8]:
		var w := _world(rank_value)
		_line(w, 1)
		totals.append(_flight(w)[0])
	assert_true(totals[1] > totals[0] * 2.0, "850%% against 380%%: %s" % str(totals))


func test_a_pierce_bonus_adds_contacts_that_continue_the_rise() -> void:
	var w := _world(1)
	w.loadout.add_skill_mod(KEY, "pierce", "add", 2)
	_line(w, 8)
	var hits := _flight(w)
	assert_eq(hits.size(), 6, "Deep Pierce: two more monsters take the hit")
	assert_true(absi(hits[5] - roundi(hits[0] * 1.5)) <= 1, "the added contacts continue the curve: %s" % str(hits))
	var top := _world(8)
	top.loadout.add_skill_mod(KEY, "pierce", "add", 2)
	_line(top, 9, 40.0)
	var all := _flight(top)
	assert_eq(all.size(), 8)
	assert_true(absi(all[7] - roundi(all[0] * 1.7)) <= 1, "the eighth takes 170%%: %s" % str(all))


# --- cancels ----------------------------------------------------------------------------------------------------------

func test_map_transfer_death_and_hidden_cancel_the_wind_up() -> void:
	for mode in ["transfer", "dead", "hidden"]:
		var w := _world()
		_mob(w, 300)
		_ticks(w, 10)
		assert_true(w.runner.bursts.has_skill(KEY), mode + ": winding up")
		match mode:
			"transfer":
				w.transfer_pending = true
				w.advance_map()
			"dead":
				w.player_state.dead = true
			"hidden":
				w.buffs.start("hidden_test", {"skill_id": 0, "level": 1, "icon": "", "duration": 10.0, "buff_stat": "", "buff_value": 0.0,
					"hidden": true, "pulse_interval": 0.0})
		w.runner.step(DT, w)
		assert_false(w.runner.bursts.has_skill(KEY), mode)
		var shots := 0
		for tick in 60:
			if mode == "transfer":
				w.runner.step(DT, w)
			else:
				w.step(DT, MoveInput.new())
			shots = maxi(shots, _shots(w))
		assert_eq(shots, 0, "%s: the arrow never leaves" % mode)


# --- rarity -----------------------------------------------------------------------------------------------------------

func test_the_catalog_lists_the_specs_bonuses() -> void:
	var bonuses: Dictionary = DataRepo.load_all().skills.skills[KEY].rarity_bonuses
	for tier: String in TIERS:
		assert_eq(bonuses[tier].size(), 1, tier)
	assert_eq([String(bonuses.rare[0].id), String(bonuses.rare[0].text)], ["marksman_boost", "Marksman Boost"])
	assert_eq(bonuses.rare[0].effects, [{"stat": "damage", "op": "mul", "value": 1.2}])
	assert_eq([String(bonuses.epic[0].id), String(bonuses.epic[0].text)], ["booster", "Crossbow Booster"])
	assert_eq(bonuses.epic[0].effects, [{"stat": "cooldown", "op": "mul", "value": 0.88}])
	assert_eq([String(bonuses.unique[0].id), String(bonuses.unique[0].text)], ["deep_pierce", "Deep Pierce"])
	assert_eq(bonuses.unique[0].effects, [{"stat": "pierce", "op": "add", "value": 2.0}])
	assert_eq(String(bonuses.legendary[0].id), String(bonuses.unique[0].id), "Legendary shares the Unique's repeat counter")
	assert_eq(bonuses.legendary[0].effects, [{"stat": "pierce", "op": "add", "value": 2.0}, {"stat": "damage", "op": "mul", "value": 1.2}])


func test_each_bonus_changes_the_resolved_cast_and_the_arrow() -> void:
	var bonuses: Dictionary = DataRepo.load_all().skills.skills[KEY].rarity_bonuses
	var base := _world(4)
	var before := base.loadout.stats(KEY)
	_line(base, 8)
	var plain := _flight(base)
	for tier: String in TIERS:
		var w := _world(4)
		for bonus: Dictionary in bonuses[tier]:
			for effect: Dictionary in bonus.effects:
				w.loadout.add_skill_mod(KEY, String(effect.stat), String(effect.op), float(effect.value))
		var after := w.loadout.stats(KEY)
		assert_ne(after, before, tier + " changes the resolved cast")
		var boosted: bool = tier in ["rare", "legendary"]
		assert_near(float(after.damage_max), float(before.damage_max) * (1.2 if boosted else 1.0), 0.5, tier)
		assert_near(float(after.cooldown), float(before.cooldown) * (0.88 if tier == "epic" else 1.0), 0.0001, tier)
		assert_eq(int(after.pierce), int(before.pierce) + (2 if tier in ["unique", "legendary"] else 0), tier)
		_line(w, 8)
		var hits := _flight(w)
		assert_eq(hits.size(), plain.size() + (2 if tier in ["unique", "legendary"] else 0), tier + ": monsters struck")
		if boosted:
			assert_true(hits[0] > plain[0], tier + ": a harder hit")


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for tier: String in TIERS:
		var a := _world()
		var b := _world()
		var c := a.upgrades.choice_card(KEY + "_rank", a, tier)
		assert_false(c.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		a.upgrades.apply(KEY + "_rank", a, tier)
		b.upgrades.apply(KEY + "_rank", b, tier)
		assert_eq(a.loadout.rank(KEY), 2, "%s: exactly one rank on top" % tier)
		assert_eq(a.loadout.skill_mods.get(KEY, {}), b.loadout.skill_mods.get(KEY, {}))
		var plain := _world()
		plain.loadout.set_rank(KEY, 2)
		assert_ne(a.loadout.stats(KEY), plain.loadout.stats(KEY), "%s changes the resolved cast beyond the rank" % tier)


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	var w := _world()
	w.upgrades.apply(KEY + "_rank", w, "unique")
	w.upgrades.apply(KEY + "_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:deep_pierce" % KEY]), 2, "one counter for both")
	assert_near(w.loadout.skill_stat(KEY, "pierce", 0.0), 2.0 + 2.0 * 0.8, 0.00001, "the second award x0.8")
	var m := _world()
	m.loadout.set_rank(KEY, 8)
	var expected := 1.0
	for n in 3:
		m.upgrades.apply(KEY + "_rank", m, "normal")
		expected *= 1.0 + 0.05 * pow(0.8, n)
		assert_near(m.loadout.skill_stat(KEY, "damage", 1.0), expected, 0.00001, "Mastery repeat %d" % n)
	assert_eq(m.loadout.rank(KEY), 8, "Mastery never raises the rank")


# --- text -------------------------------------------------------------------------------------------------------------

func test_the_skill_window_states_the_wind_up_the_pierce_and_the_rise() -> void:
	var w := _world(8)
	var line := SkillText.new(w.book).level_line(KEY, 30, w.loadout.stats(KEY))
	assert_true(line.contains("Looses one arrow after a 0.6 s wind-up"), line)
	assert_true(line.contains("Pierces up to 5 more monsters"), line)
	assert_true(line.contains("+10 points per later monster"), line)
	assert_true(line.contains("maximum 200%"), line)
	assert_false(line.contains("Fires 1 arrows"), line)


# --- presentation -----------------------------------------------------------------------------------------------------

func _scene(w: RunWorld) -> Array:
	var s := HURRICANE.ArtScene.new()
	var log := HURRICANE.FxLog.new()
	s.fx = log
	s.world = w
	return [s, log]


func test_the_scene_plays_prepare_then_the_effect_at_the_release() -> void:
	var w := _world()
	_mob(w, 300)
	var pair := _scene(w)
	var s: RunScene = pair[0]
	var log: FxRenderer = pair[1]
	w.step(DT, MoveInput.new())
	s.handle_events(w.drain_events())
	assert_eq(log.calls, [["play", "prepare", 11, true], ["fit", 11, 0.6]], "the wind-up art, fitted to 0.6 s")
	for tick in WIND_UP_TICKS - 1:
		w.step(DT, MoveInput.new())
		s._after_tick()
		s.handle_events(w.drain_events())
	assert_eq(log.calls.size(), 2, "still drawing the bow")
	w.step(DT, MoveInput.new())
	s._after_tick()
	s.handle_events(w.drain_events())
	assert_eq(log.calls.slice(2), [["stop", 11], ["play", "effect", 12, true]], "the effect at the release")
	log.free()
	s.free()


func test_a_dropped_wind_up_stops_its_art_and_shows_no_release_effect() -> void:
	for mode in ["dead", "clear"]:
		var w := _world()
		_mob(w, 300)
		var pair := _scene(w)
		var s: RunScene = pair[0]
		var log: FxRenderer = pair[1]
		w.step(DT, MoveInput.new())
		s.handle_events(w.drain_events())
		for tick in 10:
			w.step(DT, MoveInput.new())
		w.drain_events()
		if mode == "dead":
			w.player_state.dead = true
		else:
			w.runner.clear_pending(w)
		for tick in 3:
			w.step(DT, MoveInput.new())
		var events := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "burst_end")
		assert_eq(events.size(), 1, mode)
		assert_true(bool(events[0].dropped), mode)
		s.handle_events(events)
		assert_eq(log.calls.slice(2), [["stop", 11]], mode + ": the prepare art stops and nothing is released")
		log.free()
		s.free()


func test_a_finished_wind_up_reports_not_dropped() -> void:
	var w := _world()
	_mob(w, 300)
	var ended := []
	for tick in WIND_UP_TICKS + 2:
		w.step(DT, MoveInput.new())
		ended.append_array(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "burst_end"))
	assert_eq(ended.size(), 1)
	assert_false(bool(ended[0].dropped))
	assert_eq(String(ended[0].skill), KEY)


# --- the bot ----------------------------------------------------------------------------------------------------------

func test_the_bot_reads_it_as_an_attack_at_its_reach_and_scores_its_cards() -> void:
	var w := _world()
	assert_eq(SkillRunner.reach_of(w.loadout.stats(KEY), w), 450.0, "a burst reads as its range")
	var learn := w.upgrades.choice_card(KEY + "_new", w, "normal")
	var rank := w.upgrades.choice_card(KEY + "_rank", w, "normal")
	assert_true(learn.is_empty() or BotInput.card_score(w, learn) == 100.0)
	assert_eq(BotInput.card_score(w, rank), 74.0)
	_mob(w, 60)
	var memo := {}
	var pressed := 0
	for tick in 120:
		var input := BotInput.decide(w, memo)
		if not input.skills_pressed.is_empty() or not input.skills_held.is_empty():
			pressed += 1
		w.step(DT, input)
	assert_eq(pressed, 0, "322 has no mobility skill and every pool skill auto-casts")
	assert_true(w.runner.casts >= 1, "the bot's round casts it")


# --- the real cache ---------------------------------------------------------------------------------------------------

func test_real_cache_ranks_read_the_mapped_wz_levels_for_all_eight_ranks() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	assert_true(library.open())
	var img := library.img("Skill.wz/322.img")
	assert_true(img != null, "the 322 book is imported")
	if img == null:
		library.free()
		return
	var node: Dictionary = img.root.skill["3221001"]
	assert_eq(node.level.size(), 30)
	for lv in range(1, 31):
		assert_eq(int(node.level[str(lv)].damage), WZ_DAMAGE[lv - 1], "level %d damage" % lv)
		assert_eq(int(node.level[str(lv)].mobCount), WZ_MOBS[lv - 1], "level %d mobCount" % lv)
	assert_eq(int(node.weapon), 46, "the crossbow")
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"322": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "crossbow"
	lo.pierce_ceiling = 2.0
	lo.add_skill(KEY)
	assert_eq(book.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), RANK_LEVELS)
	var previous := 0.0
	for rank_value in range(1, 9):
		var lv: int = RANK_LEVELS[rank_value - 1]
		assert_eq(book.canonical_level(KEY, rank_value), lv)
		var row: Dictionary = node.level[str(lv)]
		var st := lo.stats(KEY, rank_value)
		assert_near(float(st.damage_pct), float(row.damage) / 100.0, 1e-6, "rank %d" % rank_value)
		assert_eq(int(st.pierce), int(row.mobCount) - 1, "rank %d pierces mobCount - 1" % rank_value)
		assert_true(float(st.damage_pct) > previous)
		previous = float(st.damage_pct)
		assert_eq(int(st.count), 1)
		assert_eq(float(st.pierce_falloff), -0.1)
	assert_near(float(lo.stats(KEY, 1).damage_pct), 3.8, 1e-6)
	assert_near(float(lo.stats(KEY, 4).damage_pct), 6.0, 1e-6)
	assert_near(float(lo.stats(KEY, 8).damage_pct), 8.5, 1e-6)
	library.free()


func test_real_cache_has_the_art_and_sounds_the_definition_names() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	assert_true(library.open())
	var d: Dictionary = DataRepo.load_all().skills.skills[KEY]
	for path: String in [String(d.ball), String(d.hit), String(d.icon), String(d.burst_art.prepare), String(d.burst_art.end)]:
		var anim := library.anim(path)
		assert_true(anim != null and not anim.is_empty(), path)
	assert_eq(library.anim(String(d.ball)).frame_count(), 5, "the five-frame ball")
	assert_eq(library.anim(String(d.burst_art.prepare)).frame_count(), 20)
	assert_eq(library.anim(String(d.burst_art.end)).frame_count(), 5)
	for sound: String in d.sounds.values():
		assert_true(library.find(sound) != null, sound)
	var fx := FxRenderer.new()
	fx.library = library
	var slot := fx.play(String(d.burst_art.prepare), Vector2.ZERO)
	fx.fit(slot, 0.6)
	assert_near(fx.rate_of(slot), library.anim(String(d.burst_art.prepare)).total / 0.6, 1e-4, "prepare is fitted to the wind-up")
	fx.free()
	library.free()
