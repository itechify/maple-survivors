extends TestCase
## Shadower's Assaulter (spec #425, ticket SH7 #432; WZ 4211002, book 421): the mobility skill, a data cousin of Hero's Rush
## (test_rush.gd) that stuns one monster instead of shoving every monster in its path. The Rush test set re-run for it
## where the rule is the same (learned at start, no slot, not a card, direction and distance, walls and ledges, cooldown,
## hold-to-repeat, rank by the round level, no meter gain, key binding and label, the bot escape) and rewritten where it
## differs (one monster per press, a stun on `prop` for `time` seconds, no knock-back, 200 px, 240 / 350 / 450 %).
## Synthetic worlds with the real skill data and a Skill.wz-shaped level table; the real numbers are asserted in the
## real-cache tests at the end (they SKIP without the cache, which proves nothing).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "assaulter"
const ACTION := "assaulter"
const BOSS_ID := 2220000


## Skill.wz/421.img/skill/4211002 in the shape the book reads, with the real node's constant box and a level table that
## hits the real values at the three mapped levels 4 / 15 / 30 (240 / 350 / 450 %, prop 28 / 50 / 80, time 2 / 3 / 4);
## `prop_override` >= 0 replaces the stun chance at every level.
func _img(prop_override := -1.0) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var damage := 210.0 + (lv - 1) * 10.0 if lv <= 4 else 240.0 + (lv - 4) * 10.0 if lv <= 15 else 350.0 + (lv - 15) * (100.0 / 15.0)
		var prop := 22.0 + (lv - 1) * 2.0 if lv <= 4 else 28.0 + (lv - 4) * 2.0 if lv <= 15 else 50.0 + (lv - 15) * 2.0
		levels[str(lv)] = {"damage": damage, "prop": prop_override if prop_override >= 0.0 else prop,
			"time": 2.0 if lv < 10 else 3.0 if lv < 21 else 4.0, "mobCount": 1.0,
			"lt": {"$v": [-200.0, -120.0]}, "rb": {"$v": [0.0, 0.0]}}
	return {"icon": RF._canvas(32, 32), "action": {"0": ACTION}, "weapon": 33, "level": levels}


## The quiet test data with Shadower playable (the shipped flag flips in SH14; this test's data only).
static func _data() -> Dictionary:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["422"]["playable"] = true
	return data


## A Shadower round on a flat map 0..1000 (or `segments`), the player standing at x, with only Assaulter learned.
func _world(x := 400.0, segments: Array = [], p_seed := 60, prop_override := -1.0, keep_start := false) -> RunWorld:
	var setup := RF.setup("quiet", p_seed, _data())
	setup.map_img = RF.map_from_segments(segments if not segments.is_empty()
		else [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	setup.skill_imgs["421"] = {"skill": {"4211002": _img(prop_override)}}
	setup["job"] = 422
	var w := RunWorld.new(setup)
	if not keep_start:
		for key: String in w.loadout.order.duplicate():
			if key != KEY:
				w.loadout.order.erase(key)
				w.loadout.ranks.erase(key)
		w.loadout.version += 1
	w.player.place(Vector2(x, 0), w.fhm)
	w.drain_events()
	return w


func _press(w: RunWorld, left := false, right := false) -> void:
	# The mob grid is rebuilt inside a tick (after the player's move); mobs placed by the test enter it like the previous tick's.
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active, w.swarm.capacity())
	var input := MoveInput.new()
	input.press_skill("rush")
	input.left = left
	input.right = right
	w.step(DT, input)


## A frozen mob with plenty of HP at x (a boss when `boss`); returns its slot.
func _mob(w: RunWorld, x: float, boss := false, y := 0.0) -> int:
	var slot := RF.put_mob(w, BOSS_ID if boss else 1110100, x, y, 1000)
	w.swarm.hp[slot] = 100000000
	w.swarm.max_hp[slot] = 100000000
	w.swarm.steady[slot] = 1 if boss else 0
	if boss:
		w.mob_boss[slot] = 0 # a scheduled boss (RunWorld.targets_before: bosses first)
	w.mob_kinds[int(w.kind_of_id[BOSS_ID if boss else 1110100])].move_speed = 0
	return slot


func _hits(w: RunWorld) -> Dictionary:
	var out := {}
	for event: Dictionary in w.drain_events():
		if event.type == "mob_hit":
			out[int(event.mob)] = int(out.get(int(event.mob), 0)) + 1
	return out


func _stunned(w: RunWorld, slot: int) -> bool:
	return w.swarm.status_time(slot, MobSwarm.STUN) > 0.0


func _level_to(w: RunWorld, level: int) -> void:
	while int(w.player_state.level) < level:
		w._gain_exp(w.progression.exp_to_next())


# --- Definition and learning ------------------------------------------------------------------------------------------

func test_the_definition_is_the_mobility_slot_manual_dash_with_a_stun_and_no_knockback() -> void:
	var d: Dictionary = DataRepo.load_all().skills.skills[KEY]
	assert_eq(int(d.skill_id), 4211002)
	assert_eq(String(d.book), "421")
	assert_eq(int(d.job), 421)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.slot), "mobility")
	assert_eq(String(d.cast.rule), "manual")
	assert_eq(String(d.skill_key), "rush", "the existing key: a job owns one mobility skill")
	assert_eq(float(d.cooldown), 2.0)
	assert_eq(d.displacement, {"direction": "input", "when": "during", "field": "lt.x"})
	assert_eq(d.on_hit, {"status": "stun", "chance_field": "prop", "duration_field": "time"})
	assert_false(d.has("knockback"), "the stun replaces the shove")
	assert_eq(float(d.rush.bot_threat_distance), 60.0)
	assert_eq(String(d.action), ACTION)
	assert_eq(String(d.hit), "Skill.wz/421.img/skill/4211002/hit/0")
	assert_eq(String(d.effect), "", "the node has no effect")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4211002/Use")
	assert_eq(String(d.icon), "Skill.wz/421.img/skill/4211002/icon")
	for absent: String in ["ranks", "level_ranks", "rarity_bonuses", "cast_visuals"]:
		assert_false(d.has(absent), "%s: it takes no cards and no rarity bonuses" % absent)


func test_assaulter_is_a_data_cousin_of_rush_hero_apart_from_the_stun_and_the_art() -> void:
	var defs: Dictionary = DataRepo.load_all().skills.skills
	var rush: Dictionary = defs.rush_hero
	var assaulter: Dictionary = defs[KEY]
	for field: String in ["kind", "slot", "damage", "cast", "skill_key", "cooldown", "displacement", "rush", "action_time", "ball", "rotate"]:
		assert_eq(assaulter[field], rush[field], "same %s as Hero's Rush" % field)
	assert_false(assaulter.has("ranks") or rush.has("ranks"), "neither overrides the default rank table")


func test_learned_at_round_start_on_the_mobility_slot_outside_the_pool() -> void:
	var w := _world(400.0, [], 60, -1.0, true)
	assert_true(w.loadout.has(KEY), "Assaulter is a start skill of the job")
	assert_true(w.loadout.has("double_stab"), "beside the starting active")
	assert_eq(w.book.slot(KEY), "mobility")
	assert_eq(w.jobs.mobility_skill(422), KEY)
	assert_eq(Array(w.jobs.start_skills(422)), ["double_stab", KEY])
	assert_false(KEY in w.jobs.skill_pool(422), "never in the pool, so never offered as a card")
	assert_eq(w.skill_key_of(KEY), "rush")
	assert_eq(w.loadout.rank(KEY), 1)
	assert_eq(w.loadout.slot_count("active"), 1, "it fills no active slot: Double Stab alone")
	var st := w.runner.stats_of(w, KEY)
	assert_eq(int(st.level), 4, "fixed rank 1 reads WZ level 4")
	assert_near(float(st.damage_pct), 2.40, 1e-9)
	assert_eq(int(st.mob_count), 1)
	assert_eq(float(st.displacement.distance), 200.0, "the box reach")
	assert_eq(st.box, Rect2(-200, -120, 200, 120))
	assert_eq(w.book.canonical(KEY, int(st.level), "prop"), 28.0)
	assert_eq(w.book.canonical(KEY, int(st.level), "time"), 2.0)


# --- Movement: distance, direction, stops -----------------------------------------------------------------------------

func test_the_dash_covers_200_px_toward_the_pressed_arrow() -> void:
	var w := _world()
	_press(w, false, true)
	assert_eq(w.player.pos, Vector2(600, 0), "lt.x = 200 px to the right")
	assert_eq(w.player.facing, 1)
	var left := _world()
	_press(left, true, false)
	assert_eq(left.player.pos, Vector2(200, 0))
	assert_eq(left.player.facing, -1)


func test_without_an_arrow_the_dash_follows_the_facing_and_opposing_arrows_cancel() -> void:
	var w := _world()
	w.player.facing = -1
	_press(w)
	assert_eq(w.player.pos, Vector2(200, 0), "facing left, no arrow")
	var both := _world()
	both.player.facing = 1
	_press(both, true, true)
	assert_eq(both.player.pos, Vector2(600, 0), "left + right cancel and fall back to the facing")


func test_up_and_down_arrows_do_not_change_the_horizontal_direction() -> void:
	var w := _world()
	var input := MoveInput.new()
	input.press_skill("rush")
	input.up = true
	w.step(DT, input)
	assert_eq(w.player.pos, Vector2(600, 0), "horizontal only: the facing decides when no side key is held")


func test_the_cast_event_and_cooldown() -> void:
	var w := _world()
	_press(w, false, true)
	var casts: Array = []
	for event: Dictionary in w.drain_events():
		if event.type == "cast":
			casts.append(event)
	assert_eq(casts.size(), 1)
	assert_eq(casts[0].skill, KEY)
	assert_eq(casts[0].pos, Vector2(400, 0), "the cast begins where the dash starts")
	assert_eq(casts[0].action, ACTION)
	assert_eq(casts[0].effect, "", "no effect art")
	assert_eq(int(casts[0].level), 4)
	assert_eq(int(casts[0].skill_id), 4211002)
	var ready := w.skill_readiness(KEY)
	assert_near(float(ready.total), 2.0, 1e-6)
	assert_near(float(ready.left), 2.0 - DT, 1e-6, "the cooldown ticks down in the cast's own tick")


func test_stops_at_a_wall_the_map_edge_and_a_platform_edge() -> void:
	var ledge := _world(400.0, [{"x1": 0, "y1": 0, "x2": 500, "y2": 0}])
	_press(ledge, false, true)
	assert_eq(ledge.player.pos, Vector2(500, 0), "stops on the platform's last pixel, never off the ledge")
	var edge := _world(40.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	_press(edge, true, false)
	assert_true(edge.player.pos.x >= 0.0 and edge.player.pos.x < 40.0, "never past x = 0")
	var walled := _world(400.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}, {"x1": 520, "y1": 0, "x2": 520, "y2": -200}])
	_press(walled, false, true)
	assert_true(walled.player.pos.x > 400.0 and walled.player.pos.x < 520.0, "stops before the wall at 520: %s" % walled.player.pos)


func test_an_impossible_dash_spends_nothing() -> void:
	var w := _world(500.0, [{"x1": 0, "y1": 0, "x2": 500, "y2": 0}])
	_press(w, false, true)
	assert_eq(w.player.pos, Vector2(500, 0), "already on the edge: nowhere to go")
	assert_eq(float(w.skill_readiness(KEY).left), 0.0, "no cooldown")
	for event: Dictionary in w.drain_events():
		assert_ne(event.type, "cast", "no cast event")


func test_no_dash_starts_while_climbing() -> void:
	var w := _world()
	w.player.state = PlayerMotion.ST_LADDER
	_press(w, false, true)
	assert_true(w.player.pos.x < 401.0, "no 200 px dash: %s" % w.player.pos)
	assert_eq(float(w.skill_readiness(KEY).left), 0.0)
	for event: Dictionary in w.drain_events():
		assert_ne(event.type, "cast")


func test_an_airborne_dash_moves_in_the_air() -> void:
	var w := _world()
	w.player.pos = Vector2(400, -60)
	w.player.fh = -1
	w.player.vel = Vector2.ZERO
	_press(w, false, true)
	assert_near(w.player.pos.x, 600.0, 1.0, "the dash covers its reach in the air")
	assert_true(w.player.pos.y >= -60.0 - 1e-6, "no upward lift")


# --- Hits: one monster, the first along the path ----------------------------------------------------------------------

func test_one_monster_per_press_the_first_along_the_path() -> void:
	var w := _world(400.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}, {"x1": 0, "y1": -300, "x2": 1000, "y2": -300}])
	var first := _mob(w, 450)
	var second := _mob(w, 520)
	var far := _mob(w, 700)       # inside the box at the end of the dash (600), still in the path
	var behind := _mob(w, 300)    # behind the caster
	var above := _mob(w, 450, false, -300) # the platform above: outside the 120 px box
	_press(w, false, true)
	var hits := _hits(w)
	assert_eq(hits.size(), 1, "mobCount 1: a single monster is struck")
	assert_eq(hits.get(first, 0), 1, "the first one along the path, once")
	for other: int in [second, far, behind, above]:
		assert_eq(hits.get(other, 0), 0, "slot %d is not struck" % other)


func test_the_other_direction_strikes_the_first_monster_on_that_side() -> void:
	var w := _world()
	var near := _mob(w, 350)
	_mob(w, 260)
	_mob(w, 450) # on the other side
	_press(w, true, false)
	assert_eq(_hits(w), {near: 1})


func test_the_path_reaches_200_px_plus_nothing_past_it() -> void:
	var w := _world()
	var edge := _mob(w, 600)    # the box at the end of the dash spans 400..600 behind the 600 px stop
	var past := _mob(w, 640)    # past the dash and its box
	_press(w, false, true)
	var hits := _hits(w)
	assert_eq(hits.get(edge, 0), 1)
	assert_eq(hits.get(past, 0), 0)


func test_no_knockback_the_struck_monster_stays_where_it_was() -> void:
	var w := _world()
	var m := _mob(w, 450)
	var x := w.swarm.x[m]
	_press(w, false, true)
	assert_eq(_hits(w).get(m, 0), 1)
	assert_near(w.swarm.x[m], x, 3.0, "no 80 px shove along the dash (only the ordinary hit reaction)")


func test_a_boss_in_the_path_is_taken_before_a_nearer_ordinary_monster() -> void:
	# The charge's shared ordering (bosses first, then nearest to where the dash began), unchanged from Rush.
	var w := _world()
	var snail := _mob(w, 430)
	var boss := _mob(w, 520, true)
	_press(w, false, true)
	var hits := _hits(w)
	assert_eq(hits.get(boss, 0), 1)
	assert_eq(hits.get(snail, 0), 0)


# --- The stun ---------------------------------------------------------------------------------------------------------

func test_a_struck_monster_is_stunned_for_the_ranks_seconds_when_the_chance_holds() -> void:
	var w := _world(400.0, [], 60, 100.0)
	var m := _mob(w, 450)
	_press(w, false, true)
	assert_true(_stunned(w, m), "prop 100 always stuns")
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 2.0, 0.1, "rank 1: 2 s")
	var top := _world(400.0, [], 60, 100.0)
	_level_to(top, 16)
	var t := _mob(top, 450)
	_press(top, false, true)
	assert_near(top.swarm.status_time(t, MobSwarm.STUN), 4.0, 0.1, "rank 8: 4 s")
	var none := _world(400.0, [], 60, 0.0)
	var n := _mob(none, 450)
	_press(none, false, true)
	assert_eq(_hits(none).get(n, 0), 1, "damaged")
	assert_false(_stunned(none, n), "prop 0 never stuns")


func test_bosses_are_damaged_but_never_stunned() -> void:
	var w := _world(400.0, [], 60, 100.0)
	var boss := _mob(w, 450, true)
	_press(w, false, true)
	assert_eq(_hits(w).get(boss, 0), 1)
	assert_false(_stunned(w, boss), "even with a certain chance")


func test_the_stun_is_rolled_once_per_struck_non_boss_on_the_world_stream() -> void:
	var stun := _world()
	var plain := _world()
	plain.book.defs[KEY].erase("on_hit")
	plain.loadout.version += 1 # drop the cached stats
	_mob(stun, 450)
	_mob(plain, 450)
	_press(stun, false, true)
	_press(plain, false, true)
	assert_ne(stun.rng.state, plain.rng.state, "the chance consumed a number")
	plain.rng.randf()
	assert_eq(stun.rng.state, plain.rng.state, "exactly one stream-1 draw for the one struck monster")
	# A press that strikes nothing rolls nothing.
	var empty := _world()
	var reference := _world()
	empty.book.defs[KEY].erase("on_hit")
	_press(empty, false, true)
	_press(reference, false, true)
	assert_eq(empty.rng.state, reference.rng.state, "no monster in the path, no draw")


func test_the_stun_chance_is_the_ranks_prop_over_seeds() -> void:
	var total := 60
	var stunned := 0
	for p_seed in range(1, total + 1):
		var w := _world(400.0, [], p_seed) # rank 1: prop 28
		var m := _mob(w, 450)
		_press(w, false, true)
		if _stunned(w, m):
			stunned += 1
	assert_true(stunned >= 6 and stunned <= 30, "28%% of %d dashes stun (%d did)" % [total, stunned])


func test_damage_stun_chance_and_seconds_by_rank() -> void:
	var w := _world()
	var expected := {1: [2.40, 28.0, 2.0], 4: [3.50, 50.0, 3.0], 8: [4.50, 80.0, 4.0]}
	for rank_value: int in expected:
		w.loadout.set_rank(KEY, rank_value)
		var st := w.runner.stats_of(w, KEY)
		var row: Array = expected[rank_value]
		assert_near(float(st.damage_pct), float(row[0]), 1e-6, "damage at rank %d" % rank_value)
		assert_eq(w.book.canonical(KEY, int(st.level), "prop"), row[1], "stun chance at rank %d" % rank_value)
		assert_eq(w.book.canonical(KEY, int(st.level), "time"), row[2], "stun seconds at rank %d" % rank_value)
		assert_eq(int(st.mob_count), 1, "one monster at every rank")


# --- Cooldown, hold-to-repeat, rank -----------------------------------------------------------------------------------

func _count_casts(w: RunWorld) -> int:
	var n := 0
	for event: Dictionary in w.drain_events():
		if event.type == "cast" and event.skill == KEY:
			n += 1
	return n


func test_a_held_key_repeats_only_after_the_two_second_cooldown() -> void:
	var w := _world(100.0, [{"x1": -1000, "y1": 0, "x2": 5000, "y2": 0}])
	var casts := 0
	w.player.facing = 1
	var held := MoveInput.new()
	held.hold_skill("rush")
	for tick in int(1.9 / DT):
		w.step(DT, held)
		casts += _count_casts(w)
	assert_eq(casts, 1, "one dash in the first 1.9 s")
	assert_near(w.player.pos.x, 300.0, 1.5, "100 + one 200 px dash")
	for tick in int(0.3 / DT):
		w.step(DT, held)
		casts += _count_casts(w)
	assert_eq(casts, 2, "the held key dashes again once 2.0 s have passed")


func test_a_press_inside_the_cooldown_does_nothing() -> void:
	var w := _world()
	_press(w, false, true)
	w.drain_events()
	var x := w.player.pos.x
	for tick in 30:
		_press(w, false, true)
	assert_eq(_count_casts(w), 0)
	assert_true(w.player.pos.x - x < 200.0, "only ordinary walking moved the character")


func test_assaulter_ranks_with_the_round_level_by_the_shared_mobility_rule() -> void:
	var w := _world()
	assert_eq(w.loadout.rank(KEY), 1, "rank 1 at Lv1: WZ level 4, 240%, 200 px")
	assert_eq(int(w.runner.stats_of(w, KEY).level), 4)
	_level_to(w, 10)
	assert_eq(w.loadout.rank(KEY), 5, "Lv10 -> rank 5 (WZ level 19)")
	_level_to(w, 16)
	assert_eq(w.loadout.rank(KEY), 8, "Lv16 -> rank 8, the top of the level-30 table")
	var st := w.runner.stats_of(w, KEY)
	assert_eq(int(st.level), 30)
	assert_near(float(st.damage_pct), 4.50, 1e-6)
	assert_eq(float(st.displacement.distance), 200.0, "the reach does not grow: the box is the same at every level")
	_level_to(w, 40)
	assert_eq(w.loadout.rank(KEY), 8, "clamped at the skill's rank cap; no card ever raises it")


## Hero's Rush ranks by the same rule: the two mobility skills agree at every round level 1..40.
func test_assaulter_rank_equals_hero_rush_rank_at_every_level() -> void:
	var rush: Variant = load("res://tests/unit/test_rush.gd").new()
	var hero: RunWorld = rush._world_for(112, "112", 1121006)
	var shadower := _world()
	for level in range(1, 41):
		_level_to(hero, level)
		_level_to(shadower, level)
		assert_eq(shadower.loadout.rank(KEY), hero.loadout.rank("rush_hero"), "rank at Lv%d" % level)
		assert_eq(int(shadower.runner.stats_of(shadower, KEY).level), int(hero.runner.stats_of(hero, "rush_hero").level),
			"WZ level at Lv%d" % level)
	assert_eq(shadower.loadout.rank(KEY), 8)


func test_assaulter_gives_no_meter_and_takes_no_meter_bonus() -> void:
	var empty := _world()
	var full := _world()
	full.meter.value = 5
	for w: RunWorld in [empty, full]:
		_mob(w, 450)
		_press(w, false, true)
	assert_eq(empty.meter.value, 0, "a landed dash earns nothing")
	assert_eq(full.meter.value, 5, "and spends nothing")
	var damage := {}
	for pair: Array in [["empty", empty], ["full", full]]:
		for event: Dictionary in (pair[1] as RunWorld).drain_events():
			if event.type == "mob_hit":
				damage[pair[0]] = event.damage
	assert_true(damage.has("empty") and damage.has("full"))
	assert_eq(damage.full, damage.empty, "a held charge adds nothing (same seed, same roll)")


func test_the_card_draw_never_offers_assaulter() -> void:
	var w := _world(400.0, [], 60, -1.0, true)
	for i in 60:
		for card: Dictionary in w.upgrades.roll_choices(w, w.card_rng, 3):
			assert_ne(String(card.get("skill", "")), KEY)


func test_a_hidden_shadower_still_dashes_and_strikes() -> void:
	# Manual skills are not gated by Hidden (GAME_DESIGN 7.18): recorded, not changed.
	var w := _world()
	var m := _mob(w, 450)
	assert_true(w.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 4.0, "buff_stat": "",
		"buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}}))
	assert_true(w.is_hidden())
	_press(w, false, true)
	assert_eq(w.player.pos, Vector2(600, 0), "dashed")
	assert_eq(_hits(w).get(m, 0), 1, "and struck")


# --- Key Config and the HUD -------------------------------------------------------------------------------------------

func test_key_config_lists_one_row_labelled_assaulter() -> void:
	var w := _world()
	var keys := w.manual_skill_keys()
	assert_eq(keys.size(), 1, "the job owns Assaulter alone: one skill key row")
	assert_eq(keys[0].action, "rush", "on the existing skill key")
	assert_eq(keys[0].name, "Assaulter", "labelled by the skill's own name")
	assert_eq(keys[0].icon, "Skill.wz/421.img/skill/4211002/icon")
	assert_eq(keys[0].skill, KEY)
	var draft := KeyBindings.from_settings(GameSettings.new(), ["rush"])
	assert_eq(draft.skill_keys, ["rush"])
	assert_eq(HudQuickSlot.movement_skill_of(keys).get("action", ""), "rush", "the quick slot shows it")


func test_the_hud_row_carries_the_key_and_its_cooldown() -> void:
	var scene := RunScene.new()
	scene.world = _world()
	var row: Dictionary = scene.run_info().skills.back()
	assert_eq(row.key_label, "X")
	assert_eq(row.cooldown_left, 0.0)
	_press(scene.world, false, true)
	row = scene.run_info().skills.back()
	assert_near(float(row.cooldown_total), 2.0, 1e-6)
	assert_true(float(row.cooldown_left) > 1.9, "the sweep reads the 2.0 s cooldown")
	scene.free()


# --- The bot ----------------------------------------------------------------------------------------------------------

func test_the_bot_dashes_away_from_a_mob_within_60_px_and_never_otherwise() -> void:
	var w := _world()
	assert_false(BotInput.decide(w, {}).skill_pressed("rush"), "no mob: no dash")
	var mob := _mob(w, 530)
	w.player.facing = 1
	assert_false(BotInput.decide(w, {}).skill_pressed("rush"), "a mob 130 px away is no emergency")
	w.swarm.x[mob] = 450
	var input := BotInput.decide(w, {})
	assert_true(input.skill_pressed("rush"), "a mob 50 px away on the right")
	assert_true(input.left and not input.right, "the dash goes away from it")
	w.swarm.x[mob] = 350
	input = BotInput.decide(w, {})
	assert_true(input.skill_pressed("rush") and input.right and not input.left, "and the other way for a mob on the left")


func test_the_bot_ignores_other_platforms_and_dashes_nowhere_it_cannot_go() -> void:
	var w := _world(400.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}, {"x1": 0, "y1": -300, "x2": 1000, "y2": -300}])
	_mob(w, 440, false, -300)
	assert_false(BotInput.decide(w, {}).skill_pressed("rush"), "a mob on the platform above is no threat")
	var pinned := _world(420.0, [{"x1": 400, "y1": 0, "x2": 1000, "y2": 0}])
	_mob(pinned, 460)
	var input := BotInput.decide(pinned, {})
	assert_true(input.skill_pressed("rush") and input.right and not input.left, "escapes through the crowd, not off the ledge")
	var boxed := _world(420.0, [{"x1": 400, "y1": 0, "x2": 440, "y2": 0}])
	_mob(boxed, 435)
	assert_false(BotInput.decide(boxed, {}).skill_pressed("rush"), "nowhere to go: no press")


func test_the_bot_waits_three_seconds_between_dashes() -> void:
	var w := _world()
	w.god = true
	var mob := _mob(w, 440)
	var memo := {}
	var input := BotInput.decide(w, memo)
	assert_true(input.skill_pressed("rush"))
	w.step(DT, input)
	for tick in int(2.9 / DT):
		w.player.place(Vector2(400, 0), w.fhm)
		w.swarm.x[mob] = 440
		w.swarm.y[mob] = 0
		w.step(DT, MoveInput.new())
		assert_false(BotInput.decide(w, memo).skill_pressed("rush"), "no second request inside 3 s (tick %d)" % tick)
	for tick in int(0.2 / DT):
		w.step(DT, MoveInput.new())
	w.player.place(Vector2(400, 0), w.fhm)
	w.swarm.x[mob] = 440
	w.swarm.y[mob] = 0
	assert_true(BotInput.decide(w, memo).skill_pressed("rush"), "the same emergency dashes again after 3 s")


# --- Action and presentation ------------------------------------------------------------------------------------------

func test_the_dash_owns_the_tick_and_the_presented_action() -> void:
	var w := _world()
	_press(w, false, true)
	assert_eq(w.player_state.action, ACTION)
	for state: int in [PlayerMotion.ST_WALK, PlayerMotion.ST_AIR]:
		var other := _world()
		other.player.state = state
		if state == PlayerMotion.ST_AIR:
			other.player.fh = -1
			other.player.pos.y = -60
		_press(other, false, true)
		assert_eq(other.player_state.action, ACTION, "state %d" % state)


# --- The real Skill.wz node -------------------------------------------------------------------------------------------

## SKIPs without the cache. Independent literals read from Skill.wz/421.img/skill/4211002 (SH1 #426 scan): damage 240 /
## 450 %, prop 28 / 80, time 2 / 4 and the constant box at levels 4 / 30.
func test_real_cache_assaulter_numbers_art_and_sound() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var imgs := lib.img("Skill.wz/421.img").root
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"421": imgs})
	assert_eq(book.max_level(KEY), 30)
	assert_eq(book.max_rank(KEY), 8, "the level-30 rank table")
	assert_eq(book.canonical_level(KEY, 1), 4, "rank 1 = WZ level 4")
	assert_eq(book.canonical_level(KEY, 8), 30, "rank 8 = WZ level 30")
	var rows := {4: [240.0, 28.0, 2.0], 30: [450.0, 80.0, 4.0]}
	for level: int in rows:
		var row: Array = rows[level]
		assert_eq(book.canonical(KEY, level, "damage"), row[0], "damage at level %d" % level)
		assert_eq(book.canonical(KEY, level, "prop"), row[1], "stun chance at level %d" % level)
		assert_eq(book.canonical(KEY, level, "time"), row[2], "stun seconds at level %d" % level)
		assert_eq(book.canonical(KEY, level, "mobCount"), 1.0)
		var lt: Array = book.level_node(KEY, level).lt["$v"]
		var rb: Array = book.level_node(KEY, level).rb["$v"]
		assert_eq([lt[0], lt[1], rb[0], rb[1]], [-200.0, -120.0, 0.0, 0.0], "the box at level %d" % level)
	for level in range(1, 31):
		assert_eq(book.canonical(KEY, level, "mobCount"), 1.0, "mobCount 1 at every level")
		assert_eq(float(book.level_node(KEY, level).lt["$v"][0]), -200.0, "reach 200 at every level")
	# Through a world: the numbers the dash really uses at Lv1 and from Lv16.
	var setup := RF.setup("quiet", 60, _data())
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	setup.skill_imgs["421"] = imgs
	setup["job"] = 422
	var w := RunWorld.new(setup)
	var st := w.runner.stats_of(w, KEY)
	assert_eq(int(st.level), 4)
	assert_near(float(st.damage_pct), 2.40, 1e-9)
	assert_eq(int(st.mob_count), 1)
	assert_eq(float(st.displacement.distance), 200.0)
	assert_eq(st.box, Rect2(-200, -120, 200, 120))
	_level_to(w, 16)
	st = w.runner.stats_of(w, KEY)
	assert_eq(int(st.level), 30)
	assert_near(float(st.damage_pct), 4.50, 1e-9)
	# Art and sound named by the definition all resolve; the node has no effect, only the action, hit and mob art.
	assert_false(imgs.skill["4211002"].has("effect"), "no effect node")
	assert_eq(book.def(KEY).action, ACTION)
	assert_eq(lib.anim(String(book.def(KEY).hit)).frames.size(), 4, "hit/0 is the four-frame red streak")
	assert_true(lib.anim("Skill.wz/421.img/skill/4211002/mob/0") != null)
	assert_true(lib.sound(String(book.def(KEY).sounds.use)) != null)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()


## SKIPs without the cache: Assaulter's rank table reads the same WZ levels as Hero's Rush (both 30-level skills).
func test_real_cache_assaulter_ranks_on_the_same_wz_levels_as_hero_rush() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var book := SkillBook.from_data(DataRepo.load_all().skills, {
		"112": lib.img("Skill.wz/112.img").root, "421": lib.img("Skill.wz/421.img").root})
	assert_eq(book.max_level(KEY), book.max_level("rush_hero"))
	for rank_value in range(1, 9):
		assert_eq(book.canonical_level(KEY, rank_value), book.canonical_level("rush_hero", rank_value), "rank %d" % rank_value)
	lib.free()
