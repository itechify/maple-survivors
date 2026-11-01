extends TestCase
## Dark Sight and Assassinate (Shadower SH11 #436, spec #425 SH-4 to SH-7): Dark Sight is a pool Form (a 5 s Hidden window, the speed
## penalty, admitted with a monster within 150 px) that carries Assassinate (a form sub that ignores the Hidden gate: three lines on one
## monster, the last a critical on `prop` by `criticalDamage` points). Replaces the passive-slot buff of #211 (auto-cast below 30% HP).
## The SHIPPED definitions run through seeded RunWorld ticks on synthetic Skill.wz tables (`dark_sight_book.gd`, the real v83 numbers
## at the eight mapped levels); the last tests read the real asset cache and SKIP without it. The generic Hidden state stays
## test_hidden / test_hidden_form's contract.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const BF := preload("res://tests/fixtures/boss_attack_fixtures.gd")
const BOOK := preload("res://tests/fixtures/dark_sight_book.gd")
const DT := 1.0 / 60.0
const KEY := "dark_sight"
const SUB := "assassinate"
const SNAIL := 100100
const TIERS := ["rare", "epic", "unique", "legendary"]


## A Shadower (job 422 flipped playable) alone on the flat quiet map at x = 400 facing right, Dark Sight learned (and nothing else),
## one stationary monster `mob_dx` px ahead (0 = none) with a huge HP pool.
func _world(mob_dx := 100.0, rank := 1, seed_value := 436) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["422"]["playable"] = true
	data.balance.player.hp = 100000
	data.balance.regen.hp = 0
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0 # a struck monster stays where it stands
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	_books(setup)
	var w := RunWorld.new(setup)
	w.set_job(422)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.player.facing = 1
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	assert_true(w.learn_skill(KEY))
	w.loadout.set_rank(KEY, rank)
	if mob_dx != 0.0:
		_mob(w, mob_dx)
	w.drain_events()
	return w


func _books(setup: Dictionary) -> void:
	setup.skill_imgs["422"] = BOOK.book_node()
	setup.skill_imgs["400"].skill["4001003"] = {"level": BOOK.dark_sight_levels()}


## A stationary monster `dx` px in front of the player (a negative `dx` is behind).
func _mob(w: RunWorld, dx: float, hp := 100000000) -> int:
	var m := RF.put_mob(w, SNAIL, w.player.pos.x + dx * w.player.facing, 190.0, 1000000.0)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.swarm.alpha[m] = 1.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


## Runs `seconds` of the whole world; every event carries the elapsed second it fired in (`at`).
func _run(w: RunWorld, seconds: float, from := 0.0) -> Array:
	var out: Array = []
	for i in roundi(seconds / DT):
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			e["at"] = from + float(i + 1) * DT
			out.append(e)
	return out


func _of(events: Array, type: String, skill := "") -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type and (skill == "" or String(e.get("skill", "")) == skill))


## The seconds (snapped to 0.01) of each Assassinate cast: the first hit event of every tick that has some.
func _cast_times(events: Array) -> Array:
	var out: Array = []
	for e: Dictionary in _of(events, "mob_hit", SUB):
		var at := snappedf(float(e.at), 0.01)
		if out.is_empty() or not is_equal_approx(float(out.back()), at):
			out.append(at)
	return out


## The Assassinate casts land on `expected` seconds (+ the one-tick start of the window), a tick of tolerance.
func _assert_times(events: Array, expected: Array, message: String) -> void:
	var got := _cast_times(events)
	assert_eq(got.size(), expected.size(), message)
	for i in mini(got.size(), expected.size()):
		assert_near(float(got[i]), float(expected[i]), 0.04, message)


# --- the catalogue ----------------------------------------------------------------------------------------------------

func test_dark_sight_is_the_spec_form() -> void:
	var book := _world().book
	var d: Dictionary = book.def(KEY)
	assert_eq([book.skill_id(KEY), d.kind, d.slot, d.damage, int(d.job), d.book], [4001003, "form", "active", "none", 400, "400"])
	assert_eq(d.cast, {"rule": "form", "mob_within": 150.0})
	assert_eq(d.buff, {"hidden": true, "stat": "speed", "field": "speed", "duration": 5.0})
	assert_eq(d.form, {"duration": 5.0, "exclusive_group": "shadower_stance", "effects": {},
		"subs": [{"skill": SUB, "first_after": 0.8, "interval": 2.0, "ignores_hidden": true}]})
	assert_eq([d.cooldown, d.action], [20.0, "darksight"])
	assert_eq(d.effect, "Skill.wz/400.img/skill/4001003/effect")
	assert_eq(d.sounds.use, "Sound.wz/Skill.img/4001003/Use")
	assert_false(d.has("ranks"), "the default 20-level table: ranks read levels 3 / 5 / 8 / 10 / 13 / 15 / 18 / 20")
	assert_eq(book.max_rank(KEY), 8)
	assert_eq(Array(book.rank_table(KEY)).map(func(v: Variant) -> int: return int(v)), BOOK.D_LEVELS)
	for stale: String in ["hp_threshold", "end_hp_above", "cooldown_from_cast", "duration_field"]:
		assert_false(d.buff.has(stale), "the passive-slot buff's %s is gone" % stale)


func test_assassinate_is_the_spec_form_sub() -> void:
	var book := _world().book
	var d: Dictionary = book.def(SUB)
	assert_eq([book.skill_id(SUB), d.kind, d.slot, d.damage, int(d.job), d.book], [4221001, "instant", "form_sub", "physical", 422, "422"])
	assert_eq(d.form_sub_of, [KEY])
	assert_eq(d.cast, {"rule": "box", "min_targets": 1.0})
	assert_eq(d.finish_strike, {"chance_field": "prop", "bonus_field": "criticalDamage"})
	assert_eq(d.action, "assassination")
	assert_eq(d.effect, "Skill.wz/422.img/skill/4221001/effect")
	assert_eq(d.hit, "Skill.wz/422.img/skill/4221001/special", "the strike lines are drawn on the target")
	assert_eq(d.sounds.use_cycle, ["Sound.wz/Skill.img/4221001/Use", "Sound.wz/Skill.img/4221001/Use2"])
	assert_false(d.has("ignores_hidden"), "the flag lives on the parent's subs entry (SH3)")
	assert_false(d.has("rarity_bonuses"), "a sub has no cards and no rarity list")
	assert_true(book.slot(SUB) != "active", "never a pool card")
	assert_eq(book.max_rank(SUB), 8)
	assert_eq(Array(book.rank_table(SUB)).map(func(v: Variant) -> int: return int(v)), BOOK.A_LEVELS)


func test_the_pair_validates_as_a_form_catalogue() -> void:
	var defs: Dictionary = _world().book.defs
	assert_eq(Array(PlayerForms.validation_errors({KEY: defs[KEY], SUB: defs[SUB]})), [])
	assert_eq(Array(FinishingStrike.errors({"skills": {SUB: defs[SUB]}})), [])


func test_the_old_passive_slot_definition_cards_and_tests_are_gone() -> void:
	var thief: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "thief"))
	assert_false(thief.skills.has(KEY), "moved out of thief.json")
	var homes := []
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("skills", line)
		if FileAccess.file_exists(path) and DataRepo.load_json(path).get("skills", {}).has(KEY):
			homes.append(line)
	assert_eq(homes, ["shadower"], "defined once, in the Shadower line")
	var cards: Dictionary = DataRepo.load_json(DataRepo.fragment_path("upgrades", "thief"))
	for card: Dictionary in cards.get("upgrades", []):
		assert_false(String(card.id).begins_with("dark_sight"), "the legacy dark_sight cards are removed")
		assert_false(String(card.get("skill", "")) == KEY)
	assert_false(FileAccess.file_exists("res://tests/unit/test_dark_sight_hp.gd"))
	var book := _world().book
	assert_true(book.def(KEY).get("kind") == "form" and book.slot(KEY) == "active", "no longer a passive-slot buff")


# --- admission and the window -----------------------------------------------------------------------------------------

func test_the_form_admits_only_with_a_monster_within_150_px() -> void:
	for dx: float in [0.0, 190.0, 300.0, -190.0]:
		var w := _world(dx)
		assert_true(_of(_run(w, 1.0), "form_started").is_empty(), "dx %s: nothing in reach" % dx)
		assert_false(w.is_hidden())
	for dx: float in [140.0, 100.0, -100.0, -140.0]:
		var w := _world(dx)
		var started := _of(_run(w, 0.1), "form_started")
		assert_eq(started.size(), 1, "dx %s: a living mob within 150 px starts the Form" % dx)
		assert_eq(String(started[0].skill), KEY)
		assert_true(w.is_hidden())


func test_the_window_is_five_seconds_hidden_and_ends_with_form_ended() -> void:
	var w := _world()
	var events := _run(w, 4.9)
	assert_true(w.is_hidden(), "Hidden through 4.9 s")
	assert_true(bool(w.player_state.hidden))
	assert_eq(_of(events, "form_started").size(), 1)
	assert_true(_of(events, "form_ended").is_empty())
	assert_near(float(w.runner.forms.snapshot()[0].remaining), 0.1, 0.02)
	events.append_array(_run(w, 0.2, 4.9))
	assert_false(w.is_hidden(), "over with the window")
	var ended := _of(events, "form_ended")
	assert_eq(ended.size(), 1)
	assert_eq([ended[0].skill, ended[0].reason], [KEY, "expired"])
	assert_near(float(ended[0].at), 5.0, 0.03)
	assert_eq(w.runner.forms.snapshot().size(), 0)


func test_the_cooldown_is_twenty_seconds_from_the_cast() -> void:
	var w := _world()
	var starts := _of(_run(w, 61.0), "form_started")
	assert_eq(starts.size(), 4, "casts at 0, 20, 40 and 60 s")
	for i in starts.size():
		assert_near(float(starts[i].at), 0.0167 + 20.0 * i, 0.1)
	assert_near(float(w.loadout.stats(KEY).cooldown), 20.0)


func test_the_speed_penalty_by_rank_and_it_ends_with_the_window() -> void:
	var w := _world()
	for rank in range(1, 9):
		var st := w.loadout.stats(KEY, rank)
		assert_near(float(st.buff_effects.speed), float(BOOK.D_SPEED[rank - 1]), 1e-6, "rank %d" % rank)
		assert_eq(int(st.level), BOOK.D_LEVELS[rank - 1])
		assert_near(float(st.duration), 5.0)
		assert_true(bool(st.hidden))
	assert_eq([BOOK.D_SPEED[0], BOOK.D_SPEED[3], BOOK.D_SPEED[7]], [-26, -12, 0], "the spec's rank 1 / 4 / 8")
	for rank: int in [1, 4, 8]:
		var ranked := _world(100.0, rank)
		var before := ranked.player_speed_stat()
		_run(ranked, 0.1)
		assert_true(ranked.is_hidden())
		assert_near(ranked.player_speed_stat(), before + BOOK.D_SPEED[rank - 1], 1e-6, "rank %d speed during the window" % rank)
		_run(ranked, 5.0, 0.1)
		assert_false(ranked.is_hidden())
		assert_near(ranked.player_speed_stat(), before, 1e-6, "the penalty ends with the window")


func test_the_skill_text_names_the_window_and_the_sub() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	var line := text.level_line(KEY, 3, w.loadout.stats(KEY, 1))
	assert_true(line.contains("Speed -26"), line)
	assert_true(line.contains("20 sec. between uses"), line)
	assert_true(line.contains("Hidden for 5 s: monsters ignore you and you cannot attack except with Assassinate."), line)
	assert_true(line.contains("Assassinate after 0.8 s, every 2 s"), line)
	var top := text.level_line(KEY, 20, w.loadout.stats(KEY, 8))
	assert_true(top.contains("Speed 0"), top)
	assert_true(top.contains("(Lv30)"), "rank 8 names the sub at WZ level 30: " + top)
	assert_true(text.level_line(SUB, 30, w.loadout.sub_stats(SUB, w.loadout.stats(KEY, 8), 8)).contains(
		"The last strike has a 90% chance of +250% critical damage"))


# --- Assassinate ------------------------------------------------------------------------------------------------------

func test_assassinate_casts_at_0_8_then_every_2_seconds_three_lines_on_one_monster() -> void:
	var w := _world()
	var other := _mob(w, 60)
	var events := _run(w, 5.1)
	_assert_times(events, [0.8, 2.8, 4.8], "0.8 s into the 5 s window, then every 2.0 s")
	var hits := _of(events, "mob_hit", SUB)
	assert_eq(hits.size(), 9, "three casts of three lines")
	for cast in 3:
		var mobs := {}
		for line in 3:
			mobs[int(hits[cast * 3 + line].mob)] = true
		assert_eq(mobs.size(), 1, "cast %d: one monster, three lines" % cast)
	assert_true(_of(events, "mob_hit").all(func(e: Dictionary) -> bool: return e.skill == SUB), "no other skill hit")
	assert_true(other >= 0)


func test_assassinate_takes_the_nearest_monster_and_a_scheduled_boss_first() -> void:
	var w := _world(100.0)
	var near := _mob(w, 40)
	var hits := _of(_run(w, 1.0), "mob_hit", SUB)
	assert_eq(hits.size(), 3)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == near), "the monster nearest the caster")
	# A scheduled boss in the box beats a nearer ordinary monster.
	var b := _world(100.0)
	var boss := _mob(b, 90)
	b.mob_boss[boss] = 0 # a scheduled boss, the way BossDirector marks a spawned one
	b.swarm.steady[boss] = 1
	var boss_hits := _of(_run(b, 1.0), "mob_hit", SUB)
	assert_eq(boss_hits.size(), 3)
	assert_true(boss_hits.all(func(e: Dictionary) -> bool: return int(e.mob) == boss), "the scheduled boss first, though a snail is nearer")


func test_assassinate_waits_while_no_monster_is_in_its_box() -> void:
	# 130 px ahead: inside the 150 px admission, outside the box (10 to 100 px in front).
	var w := _world(0.0)
	var mob := _mob(w, 130.0)
	var events := _run(w, 2.3)
	assert_eq(_of(events, "form_started").size(), 1, "the Form admitted")
	assert_true(_of(events, "mob_hit").is_empty(), "no monster in the box: nothing struck, the cast stays due")
	assert_true(w.is_hidden())
	# The monster steps into the box at 2.3 s: the due cast fires on the next tick, the interval then starts there.
	w.swarm.x[mob] = w.player.pos.x + 60.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	events = _run(w, 2.0, 2.3)
	var times := _cast_times(events)
	assert_eq(times.size(), 1, "one cast in the rest of the window")
	assert_near(float(times[0]), 2.3, 0.04, "cast the tick the monster entered the box (due, not consumed)")
	# 2.0 s after that cast the next one would fall at 4.3 s: the window runs to 5.0 s.
	var later := _run(w, 0.8, 4.3)
	assert_near(float(_cast_times(later)[0]), 4.3, 0.04)


func test_assassinate_ranks_with_dark_sight_through_its_thirty_level_table() -> void:
	var w := _world()
	for rank in range(1, 9):
		var parent := w.loadout.stats(KEY, rank)
		var st := w.loadout.sub_stats(SUB, parent, rank)
		assert_eq(int(st.level), BOOK.A_LEVELS[rank - 1], "rank %d casts WZ level %d" % [rank, BOOK.A_LEVELS[rank - 1]])
		assert_near(float(st.damage_pct), BOOK.A_DAMAGE[rank - 1] / 100.0, 1e-6, "rank %d damage" % rank)
		assert_eq(roundi(float(st.attack_count)), 3, "three lines at every rank")
		assert_eq(int(st.mob_count), 1)
		assert_near(float(st.finish_chance), float(BOOK.A_PROP[rank - 1]), 1e-6)
		assert_near(float(st.finish_bonus), float(BOOK.A_CRIT[rank - 1]), 1e-6)
		assert_eq(st.box, Rect2(-100, -120, 90, 120), "the canonical box (-100,-120)..(-10,0) at every rank")
	assert_eq([BOOK.A_DAMAGE[0], BOOK.A_DAMAGE[3], BOOK.A_DAMAGE[7]], [230, 425, 600], "the spec's rank 1 / 4 / 8")
	assert_eq(int(w.loadout.sub_stats(SUB, w.loadout.stats(KEY, 8), 8).level), 30, "Dark Sight rank 8 casts level 30")


func test_the_cast_resolves_the_rank_mapped_percent_in_a_run() -> void:
	for rank: int in [1, 8]:
		var w := _world(100.0, rank)
		var st := w.loadout.sub_stats(SUB, w.loadout.stats(KEY, rank), rank)
		var hits := _of(_run(w, 1.0), "mob_hit", SUB)
		assert_eq(hits.size(), 3)
		# A plain line (no crit) lies in the resolved damage range scaled by the rank's percent; a crit never falls below it.
		for hit: Dictionary in hits:
			assert_true(float(hit.damage) >= minf(1.0, float(st.damage_min)) - 1.0, "rank %d: a positive line" % rank)
			assert_true(float(hit.damage) <= float(st.damage_max) * (float(st.damage_pct) + 3.0) * 4.0 + 10.0, "rank %d: within the range" % rank)
		# More percent, more damage: rank 8 (600%) out-damages rank 1 (230%) on the same stream.
	var low := _damage_dealt(_run(_world(100.0, 1), 1.0))
	var high := _damage_dealt(_run(_world(100.0, 8), 1.0))
	assert_true(high > low * 1.8, "rank 8 deals far more per cast (%d vs %d)" % [high, low])


## The last line crits on `prop`, the first two on the base chance only; same stream for every rank.
func test_the_last_line_is_the_finisher_over_many_casts() -> void:
	for rank: int in [1, 8]:
		var w := _world(100.0, rank, 7)
		var st := w.loadout.sub_stats(SUB, w.loadout.stats(KEY, rank), rank)
		var origin := w.cast_origin()
		var last_crits := 0
		var early_crits := 0
		var casts := 300
		for i in casts:
			w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
			var plan := w.runner.prepare_cast(w, SUB, st, origin)
			assert_false(plan.is_empty())
			w.runner.resolve_cast(w, SUB, st, origin, plan)
			var hits := _of(w.drain_events(), "mob_hit", SUB)
			assert_eq(hits.size(), 3)
			early_crits += int(bool(hits[0].crit)) + int(bool(hits[1].crit))
			last_crits += int(bool(hits[2].crit))
		var chance := float(BOOK.A_PROP[rank - 1]) / 100.0
		var base := float(st.crit)
		var expected := minf(1.0, base + chance)
		assert_near(float(last_crits) / casts, expected, 0.09, "rank %d: last-line crit rate near %.2f" % [rank, expected])
		assert_near(float(early_crits) / (2.0 * casts), base, 0.07, "rank %d: lines 1 and 2 crit on the base chance (%.2f)" % [rank, base])
		assert_true(float(last_crits) / casts > float(early_crits) / (2.0 * casts), "the last line crits more often than a plain one")


# --- Hidden: every other attack silenced, nothing hits the caster -----------------------------------------------------

func test_every_other_attack_is_silenced_for_the_window_and_returns_after() -> void:
	var w := _world(100.0)
	assert_true(w.learn_skill("energy_bolt"))
	w.drain_events()
	var events := _run(w, 5.0)
	var inside := _of(events, "mob_hit")
	assert_false(inside.is_empty())
	assert_true(inside.all(func(e: Dictionary) -> bool: return e.skill == SUB), "only Assassinate struck while Hidden")
	assert_true(_of(events, "cast").all(func(e: Dictionary) -> bool: return e.skill == KEY or e.skill == SUB))
	events = _run(w, 3.0, 5.0)
	assert_false(w.is_hidden())
	assert_true(_of(events, "mob_hit").any(func(e: Dictionary) -> bool: return e.skill == "energy_bolt"), "the pool attack casts again after it")


func test_hidden_blocks_contact_hits_and_mob_and_boss_attacks() -> void:
	for setup: Dictionary in [MF.setup(436), BF.setup(6130101, 436)]:
		setup.data.balance.regen.hp = 0
		setup.data.jobs_survivor.jobs["422"]["playable"] = true
		_books(setup)
		var w := RunWorld.new(setup)
		assert_true(w.learn_skill(KEY))
		var ordinary: bool = setup.mob_imgs.has(MF.TAURO)
		if ordinary:
			RF.place_player(w, 400)
			RF.put_mob(w, MF.TAURO, 540)
		else:
			RF.put_mob(w, SNAIL, w.player.pos.x + 100, w.player.pos.y)
		w.drain_events()
		var events := _run(w, 4.9)
		assert_true(w.is_hidden(), "the Form started")
		assert_true(_of(events, "player_hit").is_empty(), "mob and boss attacks cannot hurt a Hidden Shadower")
		assert_true(_of(events, "mob_attack").is_empty())
		assert_true(_of(events, "boss_attack").is_empty())
		if not ordinary:
			assert_false(_of(events, "boss_spawned").is_empty(), "a scheduled boss was present")


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

func test_the_rarity_table_is_the_spec_table() -> void:
	var bonuses: Dictionary = _world().book.def(KEY).rarity_bonuses
	var summary := {}
	for tier: String in TIERS:
		summary[tier] = (bonuses[tier] as Array).map(func(b: Dictionary) -> Array:
			return [b.id, b.text, b.effects.map(func(e: Dictionary) -> Array: return [e.stat, e.op, float(e.value)])])
	assert_eq(summary, {
		"rare": [["assassinate", "Assassinate", [["damage", "mul", 1.2]]]],
		"epic": [["haste", "Haste", [["cooldown", "mul", 0.88]]]],
		"unique": [["deep_shadow", "Deep Shadow", [["form_time", "mul", 1.5]]]],
		"legendary": [["deep_shadow", "Deep Shadow", [["form_time", "mul", 1.5], ["damage", "mul", 1.2]]]]})


## Applies the `tier` bonus of Dark Sight to a fresh world's loadout.
func _with_bonus(tier: String, w: RunWorld) -> RunWorld:
	var bonus: Dictionary = w.book.def(KEY).rarity_bonuses[tier][0]
	RF.add_modifier_effects(w, {"skill": KEY, "effects": bonus.effects})
	return w


func _damage_dealt(events: Array) -> int:
	var total := 0
	for e: Dictionary in _of(events, "mob_hit", SUB):
		total += int(e.damage)
	return total


func test_rare_and_legendary_damage_multiplies_the_sub() -> void:
	var base := _world()
	var base_stats := base.loadout.sub_stats(SUB, base.loadout.stats(KEY, 1), 1)
	var base_damage := _damage_dealt(_run(base, 5.1))
	for tier: String in ["rare", "legendary"]:
		var w := _with_bonus(tier, _world())
		var st := w.loadout.sub_stats(SUB, w.loadout.stats(KEY, 1), 1)
		assert_near(float(st.damage_pct), float(base_stats.damage_pct), 1e-6, "the parent's damage never touches the sub's own percent")
		assert_near(float(st.damage_max), float(base_stats.damage_max) * 1.2, float(base_stats.damage_max) * 0.001, tier)
		assert_near(float(w.loadout.stats(KEY).form_sub_damage), 1.2, 1e-6)
		var dealt := _damage_dealt(_run(w, 5.1))
		assert_true(dealt > base_damage * 1.1 and dealt < base_damage * 1.3, "%s: the window deals ~x1.2 (%d vs %d)" % [tier, dealt, base_damage])


func test_epic_haste_shortens_the_cooldown() -> void:
	var base := _world()
	var haste := _with_bonus("epic", _world())
	assert_near(float(base.loadout.stats(KEY).cooldown), 20.0)
	assert_near(float(haste.loadout.stats(KEY).cooldown), 17.6, 1e-6)
	var base_windows := _of(_run(base, 95.0), "form_started").size()
	var haste_windows := _of(_run(haste, 95.0), "form_started").size()
	assert_eq([base_windows, haste_windows], [5, 6], "windows started in 95 s")


func test_unique_and_legendary_deep_shadow_lengthen_the_window() -> void:
	for tier: String in ["unique", "legendary"]:
		var w := _with_bonus(tier, _world())
		assert_near(float(w.loadout.stats(KEY).duration), 7.5, 1e-6)
		var events := _run(w, 7.4)
		assert_true(w.is_hidden(), "%s: still Hidden at 7.4 s" % tier)
		_assert_times(events, [0.8, 2.8, 4.8, 6.8], "%s: a fourth Assassinate fits the 7.5 s window" % tier)
		events.append_array(_run(w, 0.2, 7.4))
		assert_false(w.is_hidden())
		assert_near(float(_of(events, "form_ended")[0].at), 7.5, 0.03)
	var legendary := _with_bonus("legendary", _world())
	assert_near(float(legendary.loadout.stats(KEY).form_sub_damage), 1.2, 1e-6, "the legendary adds the damage bonus too")


func test_the_cards_come_from_the_pool_rare_adds_a_rank_and_legendary_shares_the_unique_counter() -> void:
	var w := _world(0.0)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	assert_eq(w.upgrades.apply("dark_sight_new", w), 1, "a playable Shadower's new card comes from the pool (UpgradePool.add_pool_skills)")
	assert_eq(w.loadout.rank(KEY), 1)
	assert_near(float(w.loadout.stats(KEY).form_sub_damage), 1.0)
	assert_eq(w.upgrades.apply("dark_sight_rank", w, "rare"), 1)
	assert_eq(w.loadout.rank(KEY), 2, "a Rare card adds one rank plus the bonus")
	assert_near(float(w.loadout.stats(KEY).form_sub_damage), 1.2, 1e-6, "the Rare Assassinate bonus")
	var counter := "bonus:%s:deep_shadow" % KEY
	w.upgrades.apply("dark_sight_rank", w, "unique")
	assert_eq(int(w.loadout.card_ranks.get(counter, 0)), 1)
	assert_near(float(w.loadout.stats(KEY).duration), 7.5, 1e-6)
	w.upgrades.apply("dark_sight_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks.get(counter, 0)), 2, "the Legendary shares the Unique's counter")
	assert_near(float(w.loadout.stats(KEY).duration), 5.0 * 1.5 * (1.0 + 0.5 * 0.8), 1e-6, "its repeat shrinks x0.8")
	assert_near(float(w.loadout.stats(KEY).form_sub_damage), 1.2 * 1.16, 1e-6, "plus damage x1.2, shrunk with the shared repeat (1 + 0.2 x 0.8)")


func test_mastery_repeats_cut_the_cooldown_of_this_damage_none_skill_and_shrink() -> void:
	var w := _world(0.0)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.upgrades.apply("dark_sight_new", w)
	w.loadout.set_rank(KEY, w.book.max_rank(KEY))
	assert_near(float(w.loadout.stats(KEY).cooldown), 20.0)
	w.upgrades.apply("dark_sight_rank", w)
	assert_near(float(w.loadout.stats(KEY).cooldown), 20.0 * 0.95, 1e-6, "Mastery: cooldown x0.95 (no damage to raise)")
	w.upgrades.apply("dark_sight_rank", w)
	assert_near(float(w.loadout.stats(KEY).cooldown), 20.0 * 0.95 * (1.0 - 0.05 * 0.8), 1e-6, "the repeat shrinks x0.8")


# --- real cache -------------------------------------------------------------------------------------------------------

func test_real_cache_numbers_for_both_skills_at_all_eight_ranks() -> void:
	if not require_cache_img("Skill.wz/422.img"):
		return
	var library := AssetLibrary.get_default()
	var root_400: Dictionary = library.img("Skill.wz/400.img").root
	var root_422: Dictionary = library.img("Skill.wz/422.img").root
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"400": root_400, "422": root_422})
	var lo := Loadout.new(book)
	lo.add_skill(KEY)
	assert_eq(book.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), BOOK.D_LEVELS)
	assert_eq(book.rank_table(SUB).map(func(v: Variant) -> int: return int(v)), BOOK.A_LEVELS)
	assert_eq(book.max_level(KEY), 20)
	assert_eq(book.max_level(SUB), 30)
	for rank in range(1, 9):
		lo.set_rank(KEY, rank)
		var dark := lo.stats(KEY)
		var dark_row: Dictionary = root_400.skill["4001003"].level[str(BOOK.D_LEVELS[rank - 1])]
		assert_eq(int(dark_row.speed), BOOK.D_SPEED[rank - 1], "rank %d: the WZ row" % rank)
		assert_near(float(dark.buff_effects.speed), float(BOOK.D_SPEED[rank - 1]), 1e-6)
		assert_near(float(dark.duration), 5.0)
		var row: Dictionary = root_422.skill["4221001"].level[str(BOOK.A_LEVELS[rank - 1])]
		assert_eq([int(row.damage), int(row.prop), int(row.criticalDamage), int(row.attackCount), int(row.mobCount)],
			[BOOK.A_DAMAGE[rank - 1], BOOK.A_PROP[rank - 1], BOOK.A_CRIT[rank - 1], 3, 1], "rank %d: the WZ row" % rank)
		var st := lo.clone().sub_stats(SUB, dark, rank)
		assert_near(float(st.damage_pct), BOOK.A_DAMAGE[rank - 1] / 100.0, 1e-6)
		assert_near(float(st.finish_chance), float(BOOK.A_PROP[rank - 1]), 1e-6)
		assert_near(float(st.finish_bonus), float(BOOK.A_CRIT[rank - 1]), 1e-6)
		assert_eq(roundi(float(st.attack_count)), 3)
		assert_eq(st.box, Rect2(-100, -120, 90, 120))
	assert_eq(Array(FinishingStrike.level_errors(book)), [], "the named fields exist on every rank of Assassinate")


func test_real_cache_art_nodes_and_sounds() -> void:
	if not require_cache_img("Skill.wz/422.img"):
		return
	var library := AssetLibrary.get_default()
	var effect: SpriteAnim = library.find_anim("Skill.wz/422.img/skill/4221001/effect")
	assert_true(effect != null and effect.frame_count() == 25, "Assassinate effect: 25 frames")
	var special: SpriteAnim = library.find_anim("Skill.wz/422.img/skill/4221001/special")
	assert_true(special != null and special.frame_count() == 10, "Assassinate special: 10 frames")
	var dark: SpriteAnim = library.find_anim("Skill.wz/400.img/skill/4001003/effect")
	assert_true(dark != null and dark.frame_count() == 4, "Dark Sight effect: 4 frames")
	for sound: String in ["4221001/Use", "4221001/Use2", "4001003/Use"]:
		assert_true(library.sound("Sound.wz/Skill.img/" + sound) != null, sound)
	assert_true(library.missing.is_empty(), str(library.missing))
