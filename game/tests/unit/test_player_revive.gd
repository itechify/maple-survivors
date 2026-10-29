extends TestCase
## The second-life seam (spec #372 BS3, docs/GAME_DESIGN.md 7.81): RunWorld.take_hit's ordered hit hooks, PlayerRevive on a
## test-only synthetic reaction skill (no Bishop definition), the `reaction` cast rule and `cooldown_by_rank`.
## Seeded, fixed dt, accuracy-0 sources (no miss can be rolled).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const RV := preload("res://tests/fixtures/revive_fixtures.gd")
const DT := 1.0 / 60.0
const TOUCH := {"boss": false, "source_kind": "touch"}
const MOB_ATTACK := {"boss": false, "source_kind": "mob_attack"}
const PROJECTILE := {"boss": false, "source_kind": "projectile"}
const BOSS_TOUCH := {"boss": true, "source_kind": "touch"}
const BOSS_ATTACK := {"boss": true, "source_kind": "attack"}
const BOSS_BALL := {"boss": true, "source_kind": "projectile"}
const SOURCES := [TOUCH, MOB_ATTACK, PROJECTILE, BOSS_TOUCH, BOSS_ATTACK, BOSS_BALL]


## A hook that records the calls it gets into a shared log.
class LogHook extends HitHook:
	var tag := ""
	var calls: Array
	var guard := false
	var claim := false

	func guarding() -> bool:
		return guard

	func intercept_lethal(_world: RunWorld, _source: Dictionary) -> bool:
		calls.append("lethal:" + tag)
		return claim

	func step(_dt: float) -> void:
		calls.append("step:" + tag)


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _idle(w: RunWorld, seconds: float) -> void:
	for tick in roundi(seconds / DT):
		w.step(DT, MoveInput.new())


func _hp(w: RunWorld) -> int:
	return int(w.player_state.hp)


# ---------------------------------------------------------------- the ordered hook point

func test_hooks_run_in_order_and_the_first_lethal_claim_wins() -> void:
	var w := RV.world(1, RV.TABLE, {}, false)
	var calls: Array = []
	var late := LogHook.new()
	late.tag = "late"
	late.calls = calls
	late.claim = true
	var early := LogHook.new()
	early.tag = "early"
	early.calls = calls
	var also := LogHook.new()
	also.tag = "also"
	also.calls = calls
	w.add_hit_hook(late, 50)
	w.add_hit_hook(early, -5)
	w.add_hit_hook(also, 50)
	RV.hit(w, TOUCH)
	assert_eq(calls, ["lethal:early", "lethal:late"], "lower order first, a claim stops the walk")
	assert_eq(w.state, RunWorld.PLAYING, "the claiming hook kept the character alive")
	assert_eq(_of(w.drain_events(), "player_died").size(), 0)


func test_unclaimed_lethal_hits_kill_as_before_and_every_hook_is_asked() -> void:
	var w := RV.world(2, RV.TABLE, {}, false)
	var calls: Array = []
	for tag in ["a", "b"]:
		var h := LogHook.new()
		h.tag = tag
		h.calls = calls
		w.add_hit_hook(h)
	RV.hit(w, TOUCH)
	assert_eq(calls, ["lethal:a", "lethal:b"], "equal orders keep registration order")
	assert_eq(w.state, RunWorld.DEAD)
	assert_eq(_of(w.drain_events(), "player_died").size(), 1)


func test_any_guarding_hook_returns_before_the_miss_roll_and_hooks_step_with_the_world() -> void:
	var w := RV.world(3, RV.TABLE, {}, false)
	var calls: Array = []
	var g := LogHook.new()
	g.tag = "g"
	g.calls = calls
	w.add_hit_hook(g)
	g.guard = true
	var before := w.rng.state
	for s: Dictionary in SOURCES:
		assert_eq(RV.hit(w, s), 0, "guarded: %s" % s.source_kind)
	assert_eq(w.rng.state, before, "a guarded hit draws nothing")
	assert_true(w.drain_events().is_empty(), "and emits nothing")
	assert_eq(calls, [], "a guarded hit never reaches the lethal walk")
	w.step(DT, MoveInput.new())
	assert_eq(calls, ["step:g"], "hooks step once per world tick")


# ---------------------------------------------------------------- admission

func test_a_lethal_hit_with_a_ready_owned_skill_revives_instead_of_dying() -> void:
	var w := RV.world(10)
	var max_hp := int(w.player_state.max_hp)
	var dmg := RV.hit(w, TOUCH)
	assert_true(dmg > 0, "the lethal hit is processed in full: its damage number still shows")
	assert_eq(w.state, RunWorld.PLAYING)
	assert_eq(_hp(w), ceili(max_hp * 0.5), "50% of max HP, rounded up")
	var events := w.drain_events()
	assert_eq(_of(events, "player_hit").size(), 1)
	assert_eq(_of(events, "player_died").size(), 0, "no death on a revive")
	var revived := _of(events, "player_revived")
	assert_eq(revived.size(), 1)
	var e: Dictionary = revived[0]
	assert_eq(e.skill, RV.KEY)
	assert_eq(e.hp, ceili(max_hp * 0.5))
	assert_eq(e.max_hp, max_hp)
	assert_near(float(e.guard), 2.0)
	assert_near(float(e.recharge), 600.0)
	assert_eq(e.pushed, 0)
	assert_true(_hp(w) > 0)


func test_a_non_lethal_hit_does_not_use_the_skill() -> void:
	var w := RV.world(11)
	assert_true(RV.hit(w, TOUCH, 1.0) > 0)
	assert_eq(_of(w.drain_events(), "player_revived").size(), 0)
	assert_false(w.revive.guarding())
	assert_true(float(w.runner.cooldowns.get(RV.KEY, 0.0)) <= 0.0, "the skill stays ready")
	assert_eq(w.revives.size(), 0)


func test_every_source_kind_triggers_the_revive() -> void:
	for s: Dictionary in SOURCES:
		var w := RV.world(12)
		RV.hit(w, s)
		assert_eq(w.state, RunWorld.PLAYING, "revived by %s%s" % ["boss " if s.boss else "", s.source_kind])
		assert_eq(_of(w.drain_events(), "player_revived").size(), 1)
		assert_eq(String(w.revives[0].source_kind), String(s.source_kind))


func test_recharge_not_owned_unrevivable_and_dead_all_kill_as_today() -> void:
	var w := RV.world(13)
	RV.hit(w, TOUCH)
	assert_eq(w.state, RunWorld.PLAYING)
	_idle(w, 2.1) # the guard has ended, the 600 s recharge has not
	assert_false(w.revive.guarding())
	RV.hit(w, TOUCH)
	assert_eq(w.state, RunWorld.DEAD, "a lethal hit while the recharge runs kills")
	assert_eq(w.revives.size(), 1)
	var n := RV.world(14, RV.TABLE, {}, false)
	RV.hit(n, TOUCH)
	assert_eq(n.state, RunWorld.DEAD, "not owned")
	var u := RV.world(15)
	RV.hit(u, {"boss": true, "source_kind": "attack", "unrevivable": true})
	assert_eq(u.state, RunWorld.DEAD, "the diagnostic flag beats a ready owned skill")
	assert_true(float(u.runner.cooldowns.get(RV.KEY, 0.0)) <= 0.0, "and the skill is not spent")
	assert_eq(u.revives.size(), 0)
	assert_eq(_of(u.drain_events(), "player_died").size(), 1)


func test_god_and_hidden_are_unchanged() -> void:
	var g := RV.world(16)
	g.god = true
	assert_eq(RV.hit(g, TOUCH), 0)
	assert_eq(_of(g.drain_events(), "player_revived").size(), 0)
	assert_true(float(g.runner.cooldowns.get(RV.KEY, 0.0)) <= 0.0, "a god-mode hit does not spend it")
	var h := RV.world(17)
	h.buffs._hidden = true # the Hidden state itself (Dark Sight) is covered by test_dark_sight
	assert_eq(RV.hit(h, TOUCH), 0, "a hidden character takes no hit, so nothing to revive from")
	assert_eq(_of(h.drain_events(), "player_revived").size(), 0)


# ---------------------------------------------------------------- the guard

func test_the_guard_blocks_every_source_including_window_bypassing_ones_without_rng_or_events() -> void:
	var w := RV.world(20)
	RV.hit(w, TOUCH)
	w.drain_events()
	assert_true(w.revive.guarding())
	var before := w.rng.state
	var hp := _hp(w)
	for s: Dictionary in SOURCES:
		assert_eq(RV.hit(w, s), 0, "guarded: %s%s" % ["boss " if s.boss else "", s.source_kind])
	assert_eq(RV.hit(w, {"boss": true, "source_kind": "attack", "unrevivable": true}), 0, "even a diagnostic hit")
	assert_eq(w.rng.state, before, "no miss roll, no RNG")
	assert_true(w.drain_events().is_empty(), "nothing emitted")
	assert_eq(_hp(w), hp)


func test_the_guard_ends_on_time_and_the_next_lethal_hit_kills() -> void:
	var w := RV.world(21)
	RV.hit(w, TOUCH)
	_idle(w, 1.9)
	assert_true(w.revive.guarding(), "still guarded just before 2.0 s")
	assert_eq(RV.hit(w, BOSS_ATTACK), 0)
	_idle(w, 0.15)
	assert_false(w.revive.guarding(), "over after 2.0 s")
	RV.hit(w, BOSS_ATTACK)
	assert_eq(w.state, RunWorld.DEAD, "after the guard and before the recharge it kills")


func test_two_lethal_hits_in_one_tick_revive_once() -> void:
	var w := RV.world(22)
	var first := RV.hit(w, BOSS_ATTACK)
	var second := RV.hit(w, BOSS_BALL)
	assert_true(first > 0)
	assert_eq(second, 0, "the second returns at the guard check")
	assert_eq(w.state, RunWorld.PLAYING)
	assert_eq(w.revives.size(), 1)


func test_the_lethal_hits_knockback_still_applies() -> void:
	var w := RV.world(23)
	w.player.knock_t = 0.0
	RV.hit(w, TOUCH)
	assert_true(w.player.knock_t > 0.0, "the revived character is pushed clear of its killer")
	assert_false(w.upkeep.may_knock_back(), "and the knockback guard started")
	assert_true(w.player.vel.x > 0.0, "away from the source on its left")


# ---------------------------------------------------------------- the plan: HP, guard, modifiers

func test_hp_share_is_clamped_to_one_through_max_hp() -> void:
	var w := RV.world(30)
	w.loadout.add_skill_mod(RV.KEY, "revive_hp", "add", 5.0)
	RV.hit(w, TOUCH)
	assert_eq(_hp(w), int(w.player_state.max_hp), "clamped to max HP")
	var low := RV.world(31, RV.TABLE, {"hp": -3.0})
	RV.hit(low, TOUCH)
	assert_eq(_hp(low), 1, "clamped to at least 1")


func test_revive_hp_and_revive_guard_modifiers_change_the_plan() -> void:
	var w := RV.world(32)
	var max_hp := int(w.player_state.max_hp)
	w.loadout.add_skill_mod(RV.KEY, "revive_hp", "add", 0.15)
	w.loadout.add_skill_mod(RV.KEY, "revive_guard", "add", 1.5)
	RV.hit(w, TOUCH)
	var e: Dictionary = _of(w.drain_events(), "player_revived")[0]
	assert_eq(e.hp, ceili(max_hp * 0.65))
	assert_near(float(e.guard), 3.5)
	_idle(w, 3.4)
	assert_true(w.revive.guarding())
	_idle(w, 0.2)
	assert_false(w.revive.guarding())


func test_the_plan_reads_the_skills_revive_block() -> void:
	var w := RV.world(33, RV.TABLE, {"hp": 0.25, "guard": 4.0, "push": {"distance": 10.0}})
	var max_hp := int(w.player_state.max_hp)
	RV.hit(w, TOUCH)
	var e: Dictionary = _of(w.drain_events(), "player_revived")[0]
	assert_eq(e.hp, ceili(max_hp * 0.25))
	assert_near(float(e.guard), 4.0)


# ---------------------------------------------------------------- recharge

func test_cooldown_by_rank_indexes_by_rank_and_repeats_its_last_value() -> void:
	var w := RV.world(40, [10.0, 5.0, 2.5])
	var seen: Array = []
	for r in range(1, 9):
		w.loadout.set_rank(RV.KEY, r)
		seen.append(float(w.loadout.stats(RV.KEY).cooldown))
	assert_eq(seen, [10.0, 5.0, 2.5, 2.5, 2.5, 2.5, 2.5, 2.5])
	assert_eq(float(w.loadout.stats(RV.KEY, 1).cooldown), 10.0, "a preview of another rank reads that rank")


func test_the_recharge_is_the_rank_table_through_every_cooldown_modifier() -> void:
	var w := RV.world(41)
	for r in range(1, 9):
		w.loadout.set_rank(RV.KEY, r)
		assert_near(float(w.loadout.stats(RV.KEY).cooldown), float(RV.TABLE[r - 1]), 1e-6, "rank %d" % r)
	w.loadout.set_rank(RV.KEY, 8)
	w.loadout.add_skill_mod(RV.KEY, "cooldown", "mul", 0.88) # a rarity "Faster Prayer"
	w.loadout.add_skill_mod(RV.KEY, "cooldown", "mul", 0.95) # one Normal Mastery card on a damage: none skill
	assert_near(float(w.loadout.stats(RV.KEY).cooldown), 120.0 * 0.88 * 0.95, 1e-3)
	# The Booster passive: base x (1 - cast speed), floored at COOLDOWN_FLOOR of the base.
	assert_true(w.learn_skill("passive_cooldown"))
	w.loadout.set_rank("passive_cooldown", 5)
	var pct := w.loadout.passive_total(Loadout.CAST_SPEED_PCT)
	assert_true(pct > 0.0)
	var want := maxf(120.0 * 0.88 * 0.95 * (1.0 - pct / 100.0), 120.0 * Loadout.COOLDOWN_FLOOR)
	assert_near(float(w.loadout.stats(RV.KEY).cooldown), want, 1e-3)
	w.loadout.add_skill_mod(RV.KEY, "cooldown", "mul", 0.01)
	assert_near(float(w.loadout.stats(RV.KEY).cooldown), 120.0 * Loadout.COOLDOWN_FLOOR, 1e-6, "the floor holds")


func test_a_revive_sets_the_resolved_cooldown_and_a_rank_card_mid_recharge_refunds_nothing() -> void:
	var w := RV.world(42)
	w.loadout.set_rank(RV.KEY, 4)
	w.loadout.add_skill_mod(RV.KEY, "cooldown", "mul", 0.5)
	RV.hit(w, TOUCH)
	assert_near(float(w.runner.cooldowns[RV.KEY]), 210.0, 1e-6)
	assert_near(float(w.runner.cooldown_totals[RV.KEY]), 210.0, 1e-6, "the HUD sweep's denominator")
	assert_near(float(_of(w.drain_events(), "player_revived")[0].recharge), 210.0, 1e-6)
	w.loadout.set_rank(RV.KEY, 8)
	assert_near(float(w.runner.cooldowns[RV.KEY]), 210.0, 1e-6, "the next recharge is shorter, this one is not refunded")
	_idle(w, 1.0)
	assert_near(float(w.runner.cooldowns[RV.KEY]), 209.0, 0.02, "it counts down with the world")


func test_a_recharged_skill_revives_again() -> void:
	var w := RV.world(43, [3.0])
	RV.hit(w, TOUCH)
	assert_eq(w.revives.size(), 1)
	_idle(w, 3.1)
	assert_false(w.revive.guarding())
	RV.hit(w, TOUCH)
	assert_eq(w.state, RunWorld.PLAYING)
	assert_eq(w.revives.size(), 2)
	assert_eq(_of(w.drain_events(), "player_revived").size(), 2)


func test_round_state_survives_a_map_transfer() -> void:
	var data := RV.data()
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	var s := RF.setup("quiet", 44, data)
	s.skill_imgs[RV.BOOK] = RV.img()
	var w := RunWorld.new(s)
	RF.place_player(w, 800)
	w.loadout.order.clear()
	w.learn_skill(RV.KEY)
	RV.hit(w, TOUCH)
	w.transfer_pending = true
	w.advance_map()
	assert_true(float(w.runner.cooldowns[RV.KEY]) > 500.0, "the recharge keeps running")
	assert_eq(w.revives.size(), 1, "and the record stays")


# ---------------------------------------------------------------- the shove

func _mob(w: RunWorld, id: int, px: float) -> int:
	var m := RF.put_mob(w, id, px, 195, 100000.0)
	w.swarm.hp[m] = 100000
	w.swarm.max_hp[m] = 100000
	return m


func test_the_shove_moves_non_boss_non_steady_monsters_in_the_box_and_nothing_else() -> void:
	var w := RV.world(50)
	var left := _mob(w, 100100, 650.0)
	var right := _mob(w, 100100, 950.0)
	var far := _mob(w, 100100, 1500.0)
	var boss := _mob(w, 100101, 700.0)
	w.mob_kinds[w.swarm.kind[boss]].boss = true
	var steady := _mob(w, 120100, 900.0)
	w.swarm.steady[steady] = 1
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var x0 := {}
	var hp0 := {}
	for m: int in [left, right, far, boss, steady]:
		x0[m] = w.swarm.x[m]
		hp0[m] = w.swarm.hp[m]
	RV.hit(w, TOUCH)
	assert_near(w.swarm.x[left], x0[left] - 140.0, 0.01, "away from the character, 140 px")
	assert_near(w.swarm.x[right], x0[right] + 140.0, 0.01)
	assert_eq(w.swarm.x[far], x0[far], "outside the 800 px box")
	assert_eq(w.swarm.x[boss], x0[boss], "bosses resist")
	assert_eq(w.swarm.x[steady], x0[steady], "steady monsters resist")
	for m: int in hp0:
		assert_eq(w.swarm.hp[m], hp0[m], "no damage")
	var events := w.drain_events()
	assert_eq(_of(events, "player_revived")[0].pushed, 2)
	assert_eq(_of(events, "mob_hit").size(), 0)


func test_the_shove_scales_with_the_area_stat_and_a_zero_distance_pushes_nothing() -> void:
	var w := RV.world(51)
	w.loadout.add_skill_mod(RV.KEY, "area", "mul", 0.5) # the box halves to 400 px: a mob at 650 (150 px) is still in
	var near := _mob(w, 100100, 650.0)
	var out := _mob(w, 100100, 1250.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var out_x: float = w.swarm.x[out]
	RV.hit(w, TOUCH)
	assert_near(w.swarm.x[near], 650.0 - 140.0, 0.01)
	assert_eq(w.swarm.x[out], out_x, "450 px is outside the halved box")
	var z := RV.world(52, RV.TABLE, {"push": {"distance": 0.0}})
	var m := _mob(z, 100100, 650.0)
	z.mob_grid.rebuild(z.swarm.x, z.swarm.y, z.swarm.active)
	RV.hit(z, TOUCH)
	assert_eq(z.swarm.x[m], 650.0)


# ---------------------------------------------------------------- records, determinism

func test_the_revive_is_recorded() -> void:
	var w := RV.world(60, [2.0])
	w.loadout.set_rank(RV.KEY, 3)
	_idle(w, 5.0)
	RV.hit(w, BOSS_BALL)
	assert_eq(w.revives.size(), 1)
	var r: Dictionary = w.revives[0]
	assert_eq(r.keys(), ["t", "level", "rank", "source_kind", "hp"])
	assert_near(float(r.t), w.time, 1e-9)
	assert_eq(r.level, int(w.player_state.level))
	assert_eq(r.rank, 3)
	assert_eq(r.source_kind, "projectile")
	assert_eq(r.hp, _hp(w))


func test_no_rng_stream_moves_for_the_revive_itself() -> void:
	var a := RV.world(61)
	var b := RV.world(61, RV.TABLE, {}, false) # the twin: the same world and hit, no skill
	RV.hit(a, TOUCH)
	RV.hit(b, TOUCH)
	for name in ["rng", "spawn_rng", "card_rng", "drop_rng", "meso_rng", "equip_rng", "scroll_rng", "reward_rng",
			"final_rng", "thief_rng", "pirate_rng", "banish_rng", "ground_rng"]:
		assert_eq((a.get(name) as RandomNumberGenerator).state, (b.get(name) as RandomNumberGenerator).state, name)
	assert_eq(b.state, RunWorld.DEAD)
	assert_eq(a.state, RunWorld.PLAYING)


func test_grant_second_life_is_the_only_hp_setter_and_clamps() -> void:
	var w := RV.world(62, RV.TABLE, {}, false)
	var max_hp := int(w.player_state.max_hp)
	assert_eq(w.grant_second_life(1.0e9), float(max_hp))
	assert_eq(_hp(w), max_hp)
	assert_eq(w.grant_second_life(-5.0), 1.0)
	assert_eq(_hp(w), 1)


# ---------------------------------------------------------------- the `reaction` cast rule

func test_a_reaction_skill_is_never_cast_and_is_not_an_attack() -> void:
	var w := RV.world(70)
	_mob(w, 100100, 850.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var st := w.runner.stats_of(w, RV.KEY)
	assert_eq(st.cast_rule, "reaction")
	assert_true(SkillRunner.is_triggered(st))
	assert_false(SkillRunner.is_attack(st), "Hidden never pauses it")
	assert_eq(SkillRunner.reach_of(st, w), 0.0)
	assert_false(w.runner.has_target(w, RV.KEY, st, w.cast_origin()), "no target for a reaction")
	assert_true(w.runner.prepare_cast(w, RV.KEY, st, w.cast_origin()).is_empty(), "and no admission plan")
	for tick in 120:
		w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "never auto-cast")
	assert_eq(_of(w.drain_events(), "cast").size(), 0)
	assert_true(float(w.runner.cooldowns[RV.KEY]) < 0.0, "its cooldown just counts (ready)")


func test_is_triggered_covers_manual_and_reaction_only() -> void:
	for rule in ["manual", "reaction"]:
		assert_true(SkillRunner.is_triggered_rule(rule), rule)
	for rule in ["", "nearest", "box", "crowd", "chain", "hp_or_undead"]:
		assert_false(SkillRunner.is_triggered_rule(rule), rule)


func test_the_bot_classifies_a_reaction_skill_as_no_attack() -> void:
	var w := RV.world(71)
	w.upgrades._by_id["test_revive_new"] = {"id": "test_revive_new", "kind": "skill_new", "skill": RV.KEY, "effects": []}
	w.upgrades._by_id["test_revive_rank"] = {"id": "test_revive_rank", "kind": "skill_rank", "skill": RV.KEY, "effects": []}
	assert_eq(BotInput.card_score(w, {"id": "test_revive_new"}), BotInput.SCORE_NEW_PASSIVE)
	assert_true(BotInput.card_score(w, {"id": "test_revive_rank"}) <= BotInput.SCORE_RANK_PASSIVE + BotInput.SCORE_JOB_BONUS)
	# and it never presses anything for it
	_mob(w, 100100, 850.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var memo := {}
	for tick in 60:
		w.step(DT, BotInput.decide(w, memo))
	assert_eq(w.runner.casts, 0)
	assert_true(float(w.runner.cooldowns[RV.KEY]) < 0.0, "the bot spent nothing on it")


# ---------------------------------------------------------------- tools that kill on purpose

func test_the_flow_drivers_diagnostic_lethal_hit_cannot_be_revived() -> void:
	var text := FileAccess.get_file_as_string("res://scenes/debug/flow_driver.gd")
	var at := text.find("w.take_hit(1.0e9")
	assert_true(at >= 0)
	var lethal_at := text.rfind("var lethal := ", at)
	assert_true(lethal_at >= 0 and at - lethal_at < 400)
	assert_true(text.substr(lethal_at, at - lethal_at).contains("\"unrevivable\": true"),
		"the diagnostic lethal source carries the flag")
