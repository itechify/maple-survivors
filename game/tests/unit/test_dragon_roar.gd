extends TestCase
## Dragon Roar (spec #348 D7, #355): the HP-gated screen stun of the Dark Knight. The behaviour tests run on a synthetic 131
## book whose eight mapped levels carry the real Skill.wz 1311006 numbers (damage, x = HP cost %, y = stun seconds, the
## symmetric lt/rb box) and made-up numbers in between; the real-cache tests at the end assert the same eight ranks against the
## asset cache and SKIP without it (a SKIP proves nothing). Seeded, fixed ticks, no Dark Knight tool path needed.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const BOSS := 2220000
const CASTER_X := 2000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 4000, "y2": 200}]
const KEY := "dragon_roar"
## The default 30-level table of the spec (rank -> WZ level).
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Tier A, Skill.wz 1311006 at those levels: damage %, x (HP cost % of max HP), y (stun s), box half-width and the box's y span.
const DAMAGE := [114, 138, 160, 175, 195, 212, 228, 240]
const COST_PCT := [56, 52, 48, 45, 41, 37, 33, 30]
const STUN_S := [4, 4, 3, 3, 3, 2, 2, 2]
const HALF_W := [140, 180, 220, 250, 290, 330, 370, 400]
const TOP := [-155, -185, -215, -237, -267, -297, -327, -350]
const BOTTOM := [55, 85, 115, 138, 168, 198, 228, 250]
## Max HP of the synthetic world (balance.player.hp; Dark Knight's own row is 600 too).
const MAX_HP := 600


## Synthetic Skill.wz 1311006 levels: the eight mapped levels hold the real numbers, the others a plausible fill.
func _levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var i := LEVELS.find(lv)
		var r := i if i >= 0 else clampi(lv / 4, 0, 7)
		levels[str(lv)] = {"damage": DAMAGE[r], "x": COST_PCT[r], "y": STUN_S[r], "mobCount": 15, "mpCon": 16,
			"lt": {"$v": [-HALF_W[r], TOP[r]]}, "rb": {"$v": [HALF_W[r], BOTTOM[r]]}}
	return levels


## A quiet world as Dark Knight (132) on a flat floor with the caster at x 2000 holding only Dragon Roar at rank 1. `edit`
## may change the loaded data first. Mob hitboxes are 10 px squares that never move.
func _world(p_seed := 355, learn := true, edit := Callable()) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["132"]["playable"] = true # D10 flips this; it makes the cards exist
	data.balance.player.hp = MAX_HP
	if edit.is_valid():
		edit.call(data)
	var setup := RF.setup("quiet", p_seed, data)
	setup.skill_imgs["131"] = {"skill": {"1311006": {"level": _levels()}}}
	var w := RunWorld.new(setup)
	w.set_job(132)
	w.bounds = Rect2(0, -500, 4000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.loadout.order.clear()
	if learn:
		w.learn_skill(KEY)
	w.god = false
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, hp_mult := 100000.0) -> int:
	return RF.put_mob(w, MOB, CASTER_X + dx, 190.0, hp_mult)


## Sets the HP pool directly and refreshes the published player_state.
func _hp(w: RunWorld, hp: float) -> void:
	w._hp = hp
	w._write_player_state(0.0)


## One runner step with the grid rebuilt: the events it produced.
func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


# --- the definition by rank -------------------------------------------------------------------------------------------

func test_every_rank_reads_the_default_table_and_a_symmetric_box() -> void:
	var w := _world()
	assert_true(w.book.has(KEY), "Dragon Roar is defined")
	assert_eq(w.book.max_rank(KEY), 8)
	assert_eq(w.book.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), LEVELS)
	for rank in range(1, 9):
		var st := w.loadout.stats(KEY, rank)
		var r := rank - 1
		assert_eq(st.level, LEVELS[r], "rank %d level" % rank)
		assert_eq(st.cast_rule, "box")
		assert_eq(st.box, Rect2(-HALF_W[r], TOP[r], 2 * HALF_W[r], BOTTOM[r] - TOP[r]), "rank %d box" % rank)
		assert_eq(st.mob_count, 15, "rank %d cap" % rank)
		assert_eq(int(st.cast_params.min_targets), 3)


func test_damage_percent_follows_the_rank() -> void:
	var lo := _world().loadout
	for rank in range(1, 9):
		assert_near(float(lo.stats(KEY, rank).damage_pct), DAMAGE[rank - 1] / 100.0, 0.0001, "rank %d" % rank)


# --- the cast: admission, the cap, the stun ---------------------------------------------------------------------------

func test_needs_three_mobs_in_the_box_and_strikes_at_most_fifteen() -> void:
	var w := _world()
	_mob(w, 60.0)
	_mob(w, -60.0)
	_cast(w)
	assert_eq(w.runner.casts, 0, "two mobs in the box do not admit the cast")
	_mob(w, 100.0)
	_cast(w)
	assert_eq(w.runner.casts, 1, "the third mob admits it")
	w = _world()
	for i in 18:
		_mob(w, -85.0 + i * 10.0)
	var far := _mob(w, 900.0)
	var hits := _of(_cast(w), "mob_hit")
	assert_eq(hits.size(), 15, "mobCount 15 caps the mobs struck")
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far], "a mob outside the box is untouched")


func test_stun_lasts_y_seconds_by_rank_and_lands_on_every_struck_mob() -> void:
	for rank in [1, 4, 6, 8]:
		var w := _world()
		w.loadout.set_rank(KEY, rank)
		var mobs := []
		for i in 5:
			mobs.append(_mob(w, -80.0 + i * 40.0))
		_hp(w, float(MAX_HP))
		var events := _cast(w)
		assert_eq(_of(events, "mob_status_applied").size(), 5, "rank %d: every struck mob is stunned" % rank)
		for m: int in mobs:
			assert_near(w.swarm.status_time(m, MobSwarm.STUN), float(STUN_S[rank - 1]), 0.05, "rank %d seconds" % rank)


func test_a_boss_is_damaged_never_stunned() -> void:
	var w := _world()
	var boss := RF.put_mob(w, BOSS, CASTER_X + 50.0, 190.0, 100000.0)
	_mob(w, -50.0)
	_mob(w, 90.0)
	var events := _cast(w)
	assert_eq(w.runner.casts, 1)
	assert_true(w.swarm.hp[boss] < w.swarm.max_hp[boss], "the boss is hurt")
	assert_eq(w.swarm.status_time(boss, MobSwarm.STUN), 0.0, "and never stunned")
	assert_eq(_of(events, "mob_status_applied").size(), 2, "the two ordinary mobs are")


func test_the_always_on_stun_draws_no_random_number() -> void:
	var drop_stun := func(data: Dictionary) -> void: data.skills.skills[KEY].erase("on_hit")
	var a := _world(355)
	var b := _world(355, true, drop_stun)
	for w: RunWorld in [a, b]:
		for i in 4:
			_mob(w, -60.0 + i * 40.0)
		_cast(w)
	assert_eq(a.runner.casts, 1)
	assert_eq(b.runner.casts, 1)
	assert_eq(a.rng.state, b.rng.state, "the stunning cast leaves the main stream where the unstunning twin leaves it")
	assert_eq(a.swarm.hp, b.swarm.hp, "and deals the same damage")


# --- the HP cost and the 50% gate -------------------------------------------------------------------------------------

func _three_mobs(w: RunWorld) -> void:
	for dx in [-60.0, 0.0, 60.0]:
		_mob(w, dx)


func test_cost_is_the_rank_percentage_of_max_hp_by_rank() -> void:
	var w := _world()
	assert_eq(int(w.player_state.max_hp), MAX_HP, "the fixture's max HP")
	for rank in range(1, 9):
		assert_eq(w.loadout.stats(KEY, rank).hp_cost, COST_PCT[rank - 1] * MAX_HP / 100, "rank %d" % rank)


func test_a_cast_at_full_hp_pays_the_cost_and_reports_it() -> void:
	var w := _world()
	_three_mobs(w)
	var events := _cast(w)
	assert_eq(w.runner.casts, 1)
	assert_eq(int(w.player_state.hp), MAX_HP - 336, "56% of 600")
	var spent := _of(events, "hp_spent")
	assert_eq(spent.size(), 1)
	assert_eq(spent[0].amount, 336)
	assert_eq(spent[0].kind, "cost")
	assert_eq(spent[0].skill, KEY)


func test_the_cast_then_waits_below_the_gate_until_hp_is_above_it_again() -> void:
	var w := _world()
	_three_mobs(w)
	_cast(w)
	assert_eq(w.runner.casts, 1)
	assert_eq(int(w.player_state.hp), 264, "44% of max HP: below the gate")
	w.runner.cooldowns[KEY] = 0.0
	_cast(w)
	assert_eq(w.runner.casts, 1, "a second cast is blocked with the cooldown ready")
	_hp(w, 300.0) # exactly half
	_cast(w)
	assert_eq(w.runner.casts, 1, "exactly 50% is not above the gate")
	_hp(w, 301.0) # above the gate, but not enough to pay 336
	_cast(w)
	assert_eq(w.runner.casts, 1, "the gate is open but rank 1 cannot pay 336 from 301")
	_hp(w, 337.0)
	_cast(w)
	assert_eq(w.runner.casts, 2, "above the gate and able to pay: it fires")
	assert_eq(int(w.player_state.hp), 1, "and leaves the last HP")


func test_a_refused_cast_spends_nothing_and_starts_no_cooldown() -> void:
	var w := _world()
	_three_mobs(w)
	_hp(w, 200.0)
	var events := _cast(w)
	assert_eq(w.runner.casts, 0)
	assert_eq(_of(events, "hp_spent").size(), 0)
	assert_eq(int(w.player_state.hp), 200)
	assert_true(float(w.runner.cooldowns.get(KEY, 0.0)) <= 1e-6, "a refused cast takes no cooldown")
	assert_eq(_of(events, "mob_status_applied").size(), 0, "and nobody is stunned")


func test_at_rank_8_the_gate_alone_blocks_at_half_hp() -> void:
	var w := _world()
	w.loadout.set_rank(KEY, 8)
	_three_mobs(w)
	assert_eq(w.loadout.stats(KEY).hp_cost, 180, "30% of 600")
	_hp(w, 300.0)
	_cast(w)
	assert_eq(w.runner.casts, 0, "300 of 600 is not above half although 180 is affordable")
	_hp(w, 301.0)
	_cast(w)
	assert_eq(w.runner.casts, 1)
	assert_eq(int(w.player_state.hp), 121, "it leaves 20% at the top rank")


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

const BONUS_STATS := {"rare": ["damage"], "epic": ["area"], "unique": ["hp_cost"], "legendary": ["hp_cost", "damage"]}


func test_declares_all_four_rarity_lists_and_legendary_shares_the_uniques_id() -> void:
	var w := _world(355, false)
	var bonuses: Dictionary = w.book.def(KEY).rarity_bonuses
	for tier: String in BONUS_STATS:
		assert_eq(bonuses[tier].size(), 1, tier)
		assert_eq(bonuses[tier][0].effects.map(func(e: Dictionary) -> String: return e.stat), BONUS_STATS[tier], tier)
	assert_eq(bonuses.legendary[0].id, bonuses.unique[0].id, "Legendary shares the Unique's repeats")
	assert_eq([bonuses.rare[0].text, bonuses.epic[0].text], ["Mastery", "Super Dragon Roar"])
	assert_false(w.upgrades.card(KEY + "_new").is_empty(), "a pool card")
	assert_false(w.upgrades.card(KEY + "_rank").is_empty())


func test_a_rare_or_better_card_adds_one_rank_and_its_bonus() -> void:
	for tier: String in BONUS_STATS:
		var a := _world(355, false)
		var b := _world(355, false)
		var c := a.upgrades.choice_card(KEY + "_new", a, tier)
		assert_false(c.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		a.upgrades.apply(KEY + "_new", a, tier)
		b.upgrades.apply(KEY + "_new", b, tier)
		assert_eq(a.loadout.rank(KEY), 1, "%s: exactly one rank" % tier)
		assert_eq(a.loadout.skill_mods.get(KEY, {}), b.loadout.skill_mods.get(KEY, {}), "same bonus in both runs")
		assert_eq(a.loadout.skill_mods[KEY].keys(), BONUS_STATS[tier], tier)


func _with(tier: String) -> RunWorld:
	var w := _world(355, false)
	w.upgrades.apply(KEY + "_new", w, tier)
	return w


func test_mastery_raises_the_damage_percent() -> void:
	var base := _with("normal")
	var rare := _with("rare")
	assert_near(float(rare.loadout.stats(KEY).damage_pct), 1.14, 0.0001)
	assert_near(float(rare.loadout.stats(KEY).damage_max) / float(base.loadout.stats(KEY).damage_max), 1.2, 0.001)


func test_super_dragon_roar_widens_the_box_and_a_mob_beyond_the_base_edge_is_struck() -> void:
	var base := _with("normal")
	var epic := _with("epic")
	assert_near(epic.loadout.stats(KEY).box.size.x, base.loadout.stats(KEY).box.size.x * 1.2, 0.01)
	for pair: Array in [[base, false], [epic, true]]:
		var w: RunWorld = pair[0]
		var far := _mob(w, 160.0) # beyond the 140 px half-width, inside 168
		_mob(w, 0.0)
		_mob(w, 40.0)
		_mob(w, -40.0)
		_cast(w)
		assert_eq(w.swarm.hp[far] < w.swarm.max_hp[far], pair[1], "the 160 px mob is struck only with Super Dragon Roar")


func test_dragon_blood_shrinks_the_cost_and_so_changes_when_the_roar_can_fire() -> void:
	var base := _with("normal")
	var unique := _with("unique")
	assert_eq(base.loadout.stats(KEY).hp_cost, 336)
	assert_eq(unique.loadout.stats(KEY).hp_cost, 252, "floor(336 x 0.75)")
	for w: RunWorld in [base, unique]:
		_three_mobs(w)
		_hp(w, 310.0) # above the gate; 336 is out of reach, 252 is not
		_cast(w)
	assert_eq(base.runner.casts, 0, "without Dragon Blood the Roar waits at 310 HP")
	assert_eq(unique.runner.casts, 1, "with it the Roar fires")
	assert_eq(int(unique.player_state.hp), 58)
	var legendary := _with("legendary")
	assert_eq(legendary.loadout.stats(KEY).hp_cost, 252)
	assert_near(float(legendary.loadout.stats(KEY).damage_max) / float(base.loadout.stats(KEY).damage_max), 1.2, 0.001,
		"Legendary adds damage x1.2")
	legendary.upgrades.apply(KEY + "_rank", legendary, "unique")
	assert_near(legendary.loadout.skill_stat(KEY, "hp_cost", 1.0), 0.75 * (1.0 - 0.25 * 0.8), 0.0001,
		"Unique and Legendary share the Dragon Blood counter, the repeat shrinks x0.8")


func test_every_bonus_effect_changes_the_resolved_cast() -> void:
	var base := _with("normal")
	var st := base.loadout.stats(KEY)
	for tier: String in BONUS_STATS:
		var w := _with(tier)
		var now := w.loadout.stats(KEY)
		for stat: String in BONUS_STATS[tier]:
			match stat:
				"damage":
					assert_true(float(now.damage_max) > float(st.damage_max), "%s: damage" % tier)
				"area":
					assert_true(now.box.size.x > st.box.size.x, "%s: box" % tier)
				"hp_cost":
					assert_true(int(now.hp_cost) < int(st.hp_cost), "%s: cost" % tier)
				_:
					assert_true(false, "%s: unknown stat %s" % [tier, stat])


# --- text -------------------------------------------------------------------------------------------------------------

func test_the_skill_window_line_states_the_cost_the_gate_and_the_stun() -> void:
	var w := _world()
	var text := SkillText.new(w.book, {})
	var line := text.level_line(KEY, 4, w.loadout.stats(KEY))
	assert_true(line.contains("Costs %d HP" % w.loadout.stats(KEY).hp_cost), line)
	assert_true(line.contains("Needs more than 50% HP"), line)
	assert_true(line.contains("up to 15 monsters"), line)
	assert_true(line.contains("stun for 4 sec"), line)
	w.loadout.set_rank(KEY, 8)
	var top := text.level_line(KEY, 30, w.loadout.stats(KEY))
	assert_true(top.contains("Costs %d HP" % w.loadout.stats(KEY).hp_cost) and top.contains("stun for 2 sec"), top)


# --- Real cache (SKIPs without it: a SKIP proves nothing) --------------------------------------------------------------

## A world with the real 131 book in place of the synthetic one.
func _real_world(lib: AssetLibrary) -> RunWorld:
	var w := _world()
	w.book.skill_imgs["131"] = lib.img("Skill.wz/131.img").root
	return w


func test_real_cache_all_eight_ranks_match_skill_wz() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(lib)
	assert_eq(w.book.max_rank(KEY), 8)
	for rank in range(1, 9):
		var r := rank - 1
		var st := w.loadout.stats(KEY, rank)
		var node := w.book.level_node(KEY, st.level)
		assert_eq(st.level, LEVELS[r], "rank %d level" % rank)
		assert_eq(int(node.damage), DAMAGE[r], "rank %d damage" % rank)
		assert_eq(int(node.x), COST_PCT[r], "rank %d x" % rank)
		assert_eq(int(node.y), STUN_S[r], "rank %d y" % rank)
		assert_eq(int(node.mobCount), 15, "rank %d mobCount" % rank)
		assert_false(node.has("prop"), "rank %d: no chance node, the stun always lands" % rank)
		assert_eq(node.lt.get("$v").map(func(v: Variant) -> int: return int(v)), [-HALF_W[r], TOP[r]], "rank %d lt" % rank)
		assert_eq(node.rb.get("$v").map(func(v: Variant) -> int: return int(v)), [HALF_W[r], BOTTOM[r]], "rank %d rb" % rank)
		assert_eq(st.box, Rect2(-HALF_W[r], TOP[r], 2 * HALF_W[r], BOTTOM[r] - TOP[r]), "rank %d resolved box" % rank)
		assert_eq(st.mob_count, 15)
		assert_eq(st.hp_cost, COST_PCT[r] * MAX_HP / 100, "rank %d cost" % rank)
	assert_eq(int(w.book.level_node(KEY, 1).damage), 96, "level 1 is not a rank")
	lib.free()


func test_real_cache_art_and_sounds_resolve() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(lib)
	var d := w.book.def(KEY)
	assert_eq(w.book.skill_node(KEY).action.get("0"), "alert3", "the book's stance")
	assert_eq(String(d.action), "alert3")
	assert_true(lib.frame(String(d.icon)) != null, "icon")
	assert_true(lib.sound(String(d.sounds.use)) != null, "Use sound")
	var effect := lib.anim(String(w.loadout.stats(KEY).effect))
	assert_true(effect != null, "effect")
	assert_eq(effect.frames.size(), 18, "effect frames")
	assert_near(effect.total, 1.44, 0.001, "18 frames at 80 ms")
	var hit := lib.anim(String(d.hit))
	assert_true(hit != null, "hit burst")
	assert_eq(hit.frames.size(), 3, "hit frames")
	lib.free()


func test_skill_text_shows_the_modified_cost() -> void:
	var w := _world()
	w.loadout.add_skill_mod(KEY, "hp_cost", "mul", 0.75)
	var st := w.loadout.stats(KEY)
	var line := SkillText.new(w.book).level_line(KEY, int(st.level), st)
	assert_true(line.contains("Costs %d HP" % int(st.hp_cost)), line)
