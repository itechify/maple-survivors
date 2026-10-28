extends TestCase
## Hero's Rush (spec #296 H6, WZ 1121006): the first damaging manual skill, a directional dash on the `rush` key.
## Synthetic worlds with the real `hero.json` skill data and a Skill.wz-shaped level-4 node (the real numbers are
## asserted in the real-cache test at the end).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "rush_hero"


## Skill.wz/112.img/skill/1121006 in the shape the book reads, with the real node's level 1 / 4 / 30 numbers so a wrong
## level shows; the img tops out at level 30 (the survivor rank table follows the WZ maximum level).
static func _rush_img() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var reach := 160.0 if lv < 4 else 170.0 if lv == 4 else 250.0
		levels[str(lv)] = {"damage": 72.0 if lv < 4 else 78.0 if lv == 4 else 130.0, "mobCount": 15.0,
			"lt": {"$v": [-reach, -50.0]}, "rb": {"$v": [0.0, 0.0]}}
	return {"icon": RF._canvas(32, 32), "action": {"0": "rush2"}, "effect": RF._anim(7, 120.0, 86, 98),
		"level": levels}


## A Hero (job 112, the creation sword) on a flat map 0..1000 with `segments` instead when given; the player stands at x.
func _world(x := 400.0, segments: Array = []) -> RunWorld:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 60, data)
	setup.map_img = RF.map_from_segments(segments if not segments.is_empty()
		else [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	setup.skill_imgs["112"] = {"skill": {"1121006": _rush_img()}}
	setup["job"] = 112
	var w := RunWorld.new(setup)
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


# --- Definition and learning ------------------------------------------------------------------------------------------

func test_learned_at_round_start_on_the_mobility_slot_outside_the_pool() -> void:
	var w := _world()
	assert_true(w.loadout.has(KEY), "Rush is a start skill of the Hero")
	assert_eq(w.book.slot(KEY), "mobility")
	assert_eq(w.jobs.mobility_skill(112), KEY)
	assert_false(KEY in w.jobs.skill_pool(112), "never in the pool, so never offered as a card")
	assert_eq(w.loadout.rank(KEY), 1)
	assert_eq(w.skill_key_of(KEY), "rush")
	var st := w.runner.stats_of(w, KEY)
	assert_eq(int(st.level), 4, "fixed rank 1 reads WZ level 4")
	assert_near(float(st.damage_pct), 0.78, 1e-9)
	assert_eq(int(st.mob_count), 15)


# --- Movement: distance, direction, stops -----------------------------------------------------------------------------

func test_the_dash_covers_the_level_4_reach_toward_the_pressed_arrow() -> void:
	var w := _world()
	_press(w, false, true)
	assert_eq(w.player.pos, Vector2(570, 0), "lt.x of level 4 = 170 px to the right")
	assert_eq(w.player.facing, 1)
	var left := _world()
	_press(left, true, false)
	assert_eq(left.player.pos, Vector2(230, 0))
	assert_eq(left.player.facing, -1)


func test_without_an_arrow_the_dash_follows_the_facing_and_opposing_arrows_cancel() -> void:
	var w := _world()
	w.player.facing = -1
	_press(w)
	assert_eq(w.player.pos, Vector2(230, 0), "facing left, no arrow")
	var both := _world()
	both.player.facing = 1
	_press(both, true, true)
	assert_eq(both.player.pos, Vector2(570, 0), "left + right cancel and fall back to the facing")


func test_up_and_down_arrows_do_not_change_the_horizontal_direction() -> void:
	var w := _world()
	var input := MoveInput.new()
	input.press_skill("rush")
	input.up = true
	w.step(DT, input)
	assert_eq(w.player.pos, Vector2(570, 0), "Rush is horizontal only: the facing decides when no side key is held")


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
	assert_eq(casts[0].action, "rush2")
	assert_eq(int(casts[0].level), 4)
	var ready := w.skill_readiness(KEY)
	assert_near(float(ready.total), 2.0, 1e-6)
	assert_near(float(ready.left), 2.0 - DT, 1e-6, "the cooldown ticks down in the cast's own tick")


func test_stops_at_a_wall_the_map_edge_and_a_platform_edge() -> void:
	# A platform edge: the floor ends at x = 500, so the dash from 400 covers 100 px, never off the ledge.
	var ledge := _world(400.0, [{"x1": 0, "y1": 0, "x2": 500, "y2": 0}])
	_press(ledge, false, true)
	assert_eq(ledge.player.pos, Vector2(500, 0), "stops on the platform's last pixel")
	# The map edge: a floor wider than the map is cut at the map limit.
	var edge := _world(40.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	_press(edge, true, false)
	assert_true(edge.player.pos.x >= 0.0 and edge.player.pos.x < 40.0, "never past x = 0")
	# A wall across the floor stops the dash short of it.
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
	assert_true(w.player.pos.x < 401.0, "no 170 px dash: %s" % w.player.pos)
	assert_eq(float(w.skill_readiness(KEY).left), 0.0)
	for event: Dictionary in w.drain_events():
		assert_ne(event.type, "cast")


func test_an_airborne_dash_moves_in_the_air() -> void:
	var w := _world()
	w.player.pos = Vector2(400, -60)
	w.player.fh = -1
	w.player.vel = Vector2.ZERO
	_press(w, false, true)
	assert_near(w.player.pos.x, 570.0, 1.0, "the dash covers its reach in the air")
	assert_true(w.player.pos.y >= -60.0 - 1e-6, "no upward lift")


# --- Hits and knock-back ----------------------------------------------------------------------------------------------

## Mob 1110100 (250 HP) at x with the HP multiplier that lets it survive several 78% hits; returns its slot.
func _mob(w: RunWorld, x: float) -> int:
	return RF.put_mob(w, 1110100, x, 0, 1000)


func _hits(w: RunWorld) -> Dictionary:
	var out := {}
	for event: Dictionary in w.drain_events():
		if event.type == "mob_hit":
			out[int(event.mob)] = int(out.get(int(event.mob), 0)) + 1
	return out


func test_every_mob_in_the_path_is_hit_once_and_only_those() -> void:
	var w := _world(400.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}, {"x1": 0, "y1": -300, "x2": 1000, "y2": -300}])
	var ahead := _mob(w, 450)       # inside the start box (400..570)
	var far := _mob(w, 700)         # inside the box at the end of the dash (570..740)
	var beyond := _mob(w, 820)      # past the dash and its box
	var behind := _mob(w, 300)      # behind the caster
	var above := RF.put_mob(w, 1110100, 450, -300, 1000) # the platform above: outside the 50 px box
	_press(w, false, true)
	var hits := _hits(w)
	assert_eq(hits.get(ahead, 0), 1)
	assert_eq(hits.get(far, 0), 1)
	assert_eq(hits.get(beyond, 0), 0)
	assert_eq(hits.get(behind, 0), 0)
	assert_eq(hits.get(above, 0), 0)


func test_the_dash_strikes_at_most_fifteen_mobs() -> void:
	var w := _world()
	for i in 20:
		_mob(w, 420 + i * 7)
	_press(w, false, true)
	var hits := _hits(w)
	assert_eq(hits.size(), 15, "mobCount 15 of the 20 mobs in the path")


func test_the_hit_shoves_mobs_80_px_along_the_dash_for_both_directions() -> void:
	var w := _world()
	var passed := _mob(w, 450)   # the dash ends at 570: this mob is now behind the caster
	var ahead := _mob(w, 600)    # inside the box at the end of the dash
	_press(w, false, true)
	assert_near(w.swarm.x[passed], 530.0, 1.5, "pushed forward 80 px, not back toward the start")
	assert_near(w.swarm.x[ahead], 680.0, 1.5)
	var left := _world()
	var l_mob := _mob(left, 350)
	_press(left, true, false)
	assert_near(left.swarm.x[l_mob], 270.0, 1.5)


func test_knockback_always_applies_and_draws_no_random_number() -> void:
	var with_shove := _world()
	_mob(with_shove, 450)
	var plain := _world()
	plain.book.defs[KEY].erase("knockback")
	plain.loadout.version += 1 # drop the cached stats
	_mob(plain, 450)
	_press(with_shove, false, true)
	_press(plain, false, true)
	assert_eq(with_shove.rng.state, plain.rng.state, "the shove rolls nothing: the streams stay in step")
	assert_ne(with_shove.swarm.x[0], plain.swarm.x[0], "and the mob was moved")


func test_bosses_are_damaged_but_not_shoved() -> void:
	var w := _world()
	var boss := _mob(w, 450)
	w.swarm.steady[boss] = 1 # a scheduled boss
	_press(w, false, true)
	assert_eq(_hits(w).get(boss, 0), 1)
	assert_near(w.swarm.x[boss], 450.0, 0.02)


# --- Cooldown, hold-to-repeat, no ranks -------------------------------------------------------------------------------

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
	assert_near(w.player.pos.x, 270.0, 1.5, "100 + one 170 px dash")
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


func test_rush_stays_rank_one_for_the_whole_round() -> void:
	var w := _world()
	for i in 45:
		w._gain_exp(w.progression.exp_to_next())
	assert_true(int(w.player_state.level) >= 40, "level %d" % int(w.player_state.level))
	assert_eq(w.loadout.rank(KEY), 1)
	assert_eq(int(w.runner.stats_of(w, KEY).level), 4, "still WZ level 4: 78%")
	assert_eq(w.mobility_rank(int(w.player_state.level)), 1, "the one seam a shared rank rule replaces")


func test_rush_gives_no_orb_and_takes_no_orb_bonus() -> void:
	var empty := _world()
	var full := _world()
	assert_false(empty.meter.config.is_empty(), "the Hero's Combo meter is configured")
	full.meter.value = 5
	for w: RunWorld in [empty, full]:
		_mob(w, 450)
		_press(w, false, true)
	assert_eq(empty.meter.value, 0, "a landed dash earns no orb")
	assert_eq(full.meter.value, 5, "and spends none")
	var damage := {}
	for pair: Array in [["empty", empty], ["full", full]]:
		for event: Dictionary in (pair[1] as RunWorld).drain_events():
			if event.type == "mob_hit":
				damage[pair[0]] = event.damage
	assert_true(damage.has("empty") and damage.has("full"))
	assert_eq(damage.full, damage.empty, "five held orbs add nothing to Rush (same seed, same roll)")


func test_the_card_draw_never_offers_rush() -> void:
	var w := _world()
	for i in 60:
		for card: Dictionary in w.upgrades.roll_choices(w, w.card_rng, 3):
			assert_ne(String(card.get("skill", "")), KEY)


# --- Key Config and the HUD -------------------------------------------------------------------------------------------

func test_rush_is_a_skill_key_bound_to_x_like_teleport_and_dash() -> void:
	assert_true("rush" in KeyBindings.SKILL_KEYS)
	assert_true(InputMap.has_action("rush"), "the project defines the action")
	var key := InputEventKey.new()
	key.physical_keycode = KEY_X
	key.pressed = true
	assert_true(key.is_action_pressed("rush"), "X is the default, shared with Teleport and Dash")


func test_key_config_lists_exactly_the_rush_key_for_a_hero() -> void:
	var w := _world()
	var keys := w.manual_skill_keys()
	assert_eq(keys.size(), 1, "a Hero owns Rush alone: one skill key row")
	assert_eq(keys[0].action, "rush")
	assert_eq(keys[0].name, "Rush")
	assert_eq(keys[0].icon, "Skill.wz/112.img/skill/1121006/icon")
	var draft := KeyBindings.from_settings(GameSettings.new(), ["rush"])
	assert_eq(draft.skill_keys, ["rush"])
	assert_true(draft.keys.has("rush"), "the draft binds it")
	assert_eq(HudQuickSlot.movement_skill_of(keys).get("action", ""), "rush", "the quick slot shows it")


func test_the_hud_row_carries_the_rush_key_and_its_cooldown() -> void:
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


# --- The bot -----------------------------------------------------------------------------------------------------------

func test_the_bot_dashes_away_from_a_mob_within_60_px_and_never_otherwise() -> void:
	var w := _world()
	assert_false(BotInput.decide(w, {}).skill_pressed("rush"), "no mob: no dash")
	var mob := _mob(w, 530)
	w.player.facing = 1
	assert_false(BotInput.decide(w, {}).skill_pressed("rush"), "a mob 130 px away is no emergency, and never a reason to approach")
	w.swarm.x[mob] = 450
	var input := BotInput.decide(w, {})
	assert_true(input.skill_pressed("rush"), "a mob 50 px away on the right")
	assert_true(input.left and not input.right, "the dash goes away from it")
	w.swarm.x[mob] = 350
	input = BotInput.decide(w, {})
	assert_true(input.skill_pressed("rush") and input.right and not input.left, "and the other way for a mob on the left")


func test_the_bot_ignores_mobs_on_other_platforms_and_dashes_nowhere_it_cannot_go() -> void:
	var w := _world(400.0, [{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}, {"x1": 0, "y1": -300, "x2": 1000, "y2": -300}])
	RF.put_mob(w, 1110100, 440, -300, 1000)
	assert_false(BotInput.decide(w, {}).skill_pressed("rush"), "a mob on the platform above is no threat")
	# Pinned: the floor ends 20 px behind the bot, so fleeing from the mob on its right has no lane. It dashes through the mob.
	var pinned := _world(420.0, [{"x1": 400, "y1": 0, "x2": 1000, "y2": 0}])
	_mob(pinned, 460)
	var input := BotInput.decide(pinned, {})
	assert_true(input.skill_pressed("rush") and input.right and not input.left, "escapes through the crowd, not off the ledge")
	# No lane either way: a 30 px floor.
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


# --- The real Skill.wz node -------------------------------------------------------------------------------------------

func test_real_cache_rush_numbers_art_and_sound() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var imgs := lib.img("Skill.wz/112.img").root
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"112": imgs})
	assert_eq(book.max_level(KEY), 30)
	assert_eq(book.max_rank(KEY), 8, "the level-30 rank table")
	assert_eq(book.canonical_level(KEY, 1), 4, "fixed rank 1 = WZ level 4")
	# Independent literals read from Skill.wz/112.img/skill/1121006/level/4.
	assert_eq(book.canonical(KEY, 4, "damage"), 78.0)
	assert_eq(book.canonical(KEY, 4, "mobCount"), 15.0)
	var lt: Array = book.level_node(KEY, 4).lt["$v"]
	var rb: Array = book.level_node(KEY, 4).rb["$v"]
	assert_eq([lt[0], lt[1], rb[0], rb[1]], [-170.0, -50.0, 0.0, 0.0])
	assert_eq(book.def(KEY).action, "rush2")
	# Through a world: the numbers the cast really uses.
	var setup := RF.setup("quiet", 60, RF.quiet_data())
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1000, "y2": 0}])
	setup.skill_imgs["112"] = imgs
	setup["job"] = 112
	var w := RunWorld.new(setup)
	var st := w.runner.stats_of(w, KEY)
	assert_eq(int(st.level), 4)
	assert_near(float(st.damage_pct), 0.78, 1e-9)
	assert_eq(int(st.mob_count), 15)
	assert_eq(float(st.displacement.distance), 170.0, "the dash covers the box reach")
	assert_eq(st.box, Rect2(-170, -50, 170, 50))
	# Art and sound named by the definition all resolve, including the dust.
	assert_eq(lib.anim(String(book.def(KEY).effect)).frames.size(), 7, "effect/0 is blank, 1..6 the streak")
	assert_eq(lib.anim(String(book.def(KEY).cast_visuals[0].path)).frames.size(), 6, "the dust")
	assert_true(lib.sound(String(book.def(KEY).sounds.use)) != null)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
