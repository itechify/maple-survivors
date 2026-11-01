extends TestCase
## The finishing strike (spec #425, SH5 #430): the last damage line of a cast rolls its own crit chance and adds its own crit
## bonus. The pure arithmetic (FinishingStrike), the `finish_chance` / `finish_bonus` stats a `finish_strike` block adds
## (and the byte-identical stats of a skill without it), the line-by-line behaviour on a SYNTHETIC skill ("finisher", book 999,
## fixed damage so the only random draw of a line is its crit roll), the unchanged stream, the crit flag on the hit, the hit of a
## form's sub, and the data checks. No Shadower data is used; Assassinate's own numbers are SH11's tests.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const BASE_CRIT := 0.3
## Rank 1 = WZ level 1: prop 38 (%), criticalDamage 120 (points), fixdamage 10, three lines.
const BLOCK := {"chance_field": "prop", "bonus_field": "criticalDamage"}


## A world with the synthetic "finisher" learned. `def_extra` is merged over the definition (`finish_strike`, `cast` ...),
## `level_extra` over the level numbers (`attackCount`, `prop` ...). The player has a 30% base crit chance from a skill mod.
func _world(def_extra: Dictionary = {}, level_extra: Dictionary = {}, p_seed := 430) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.magnet_radius = 0
	var def := {"skill_id": 9991000, "book": "999", "kind": "instant", "damage": "fixed", "ranks": [1, 2],
		"cooldown": 1.0, "range": 400.0, "cast": {"rule": "box"}}
	def.merge(def_extra, true)
	data.skills.skills["finisher"] = def
	var setup := RF.setup("quiet", p_seed, data)
	var level := {"lt": {"$v": [-100.0, -60.0]}, "rb": {"$v": [20.0, 0.0]}, "mobCount": 3.0, "attackCount": 3.0,
		"fixdamage": 10.0, "prop": 38.0, "criticalDamage": 120.0}
	level.merge(level_extra, true)
	var level_two := level.duplicate()
	level_two.prop = 60.0
	level_two.criticalDamage = 175.0
	setup.skill_imgs["999"] = {"skill": {"9991000": {"level": {"1": level, "2": level_two}},
		"9991001": {"level": {"1": {"damage": 100}}}}}
	var w := RunWorld.new(setup)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.loadout.order.clear()
	w.learn_skill("finisher")
	w.loadout.add_skill_mod("finisher", "crit", "add", BASE_CRIT)
	RF.place_player(w, 400)
	w.player.facing = -1
	w.god = true
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float) -> int:
	return RF.put_mob(w, MOB, w.player.pos.x + dx, 190.0, 100000.0)


## One runner step with the grid rebuilt: the events it produced.
func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


# --- The pure arithmetic ----------------------------------------------------------------------------------------------

func test_only_the_last_line_is_the_finisher_and_a_one_line_cast_is_its_own_last() -> void:
	assert_false(FinishingStrike.is_last(0, 3))
	assert_false(FinishingStrike.is_last(1, 3))
	assert_true(FinishingStrike.is_last(2, 3))
	assert_true(FinishingStrike.is_last(0, 1), "a one-line cast treats its only line as the last")
	assert_true(FinishingStrike.is_last(0, 0), "never fewer than one line")


func test_line_stats_raises_chance_and_adds_bonus_on_the_last_line_only() -> void:
	var st := {"crit": 0.3, "crit_damage_bonus": 25.0, "finish_chance": 38.0, "finish_bonus": 120.0, "damage_min": 7.0,
		"damage_pct": 2.0, "crit_mult": 1.5}
	assert_true(FinishingStrike.line_stats(st, 0, 3) == st, "the first line is the stats themselves")
	assert_true(FinishingStrike.line_stats(st, 1, 3) == st)
	var last := FinishingStrike.line_stats(st, 2, 3)
	assert_near(float(last.crit), 0.68, 1e-9, "30% + 38%")
	assert_near(float(last.crit_damage_bonus), 145.0, 1e-9, "a skill already crit-by-points: its own 25 + the 120 points")
	assert_eq(last.damage_min, 7.0, "everything else is copied")
	assert_near(float(st.crit), 0.3, 1e-9, "the shared dictionary is not edited")
	assert_near(float(st.crit_damage_bonus), 25.0, 1e-9)


func test_the_chance_is_capped_at_certain() -> void:
	var st := {"crit": 0.8, "crit_damage_bonus": 0.0, "finish_chance": 90.0, "finish_bonus": 250.0, "damage_pct": 1.0, "crit_mult": 1.5}
	assert_near(float(FinishingStrike.line_stats(st, 0, 1).crit), 1.0, 1e-9, "min(100%, 80% + 90%)")


func test_the_finishing_bonus_goes_on_top_of_an_ordinary_crit() -> void:
	# D19: roll_damage multiplies a bonus crit by damage_pct + bonus / 100, so the stored bonus is made to equal
	# pct x crit_mult + finish_bonus / 100 (rank 8 Assassinate: 6.0 x 1.5 + 2.5 = 11.5 against the old 8.5).
	var st := {"crit": 0.3, "crit_damage_bonus": 0.0, "finish_chance": 90.0, "finish_bonus": 250.0, "damage_pct": 6.0, "crit_mult": 1.5}
	var last := FinishingStrike.line_stats(st, 2, 3)
	assert_near(6.0 + float(last.crit_damage_bonus) / 100.0, 11.5, 1e-9, "the multiplier of a finishing crit")
	var rank_one := {"crit": 0.3, "crit_damage_bonus": 0.0, "finish_chance": 38.0, "finish_bonus": 120.0, "damage_pct": 2.3, "crit_mult": 1.5}
	assert_near(2.3 + float(FinishingStrike.line_stats(rank_one, 2, 3).crit_damage_bonus) / 100.0, 2.3 * 1.5 + 1.2, 1e-9)
	assert_true(2.3 * 1.5 + 1.2 > 2.3 * 1.5, "never weaker than an ordinary crit")
	var plain := {"crit": 0.3, "crit_damage_bonus": 0.0, "damage_pct": 6.0, "crit_mult": 1.5}
	assert_true(FinishingStrike.line_stats(plain, 2, 3) == plain, "a skill without the block is untouched")


func test_a_skill_without_the_keys_takes_the_unchanged_path() -> void:
	var st := {"crit": 0.3, "crit_damage_bonus": 25.0}
	assert_false(FinishingStrike.is_active(st))
	assert_true(FinishingStrike.line_stats(st, 2, 3) == st)
	assert_eq(FinishingStrike.resolve({"damage": "physical"}, {"prop": 38.0}), {}, "no block, no keys")


func test_resolve_reads_the_named_fields_and_floors_them_at_zero() -> void:
	var got := FinishingStrike.resolve({"finish_strike": BLOCK}, {"prop": 60.0, "criticalDamage": 175.0})
	assert_eq(got, {"finish_chance": 60.0, "finish_bonus": 175.0})
	var other := FinishingStrike.resolve({"finish_strike": {"chance_field": "x", "bonus_field": "y"}}, {"x": "50", "y": -5.0})
	assert_eq(other, {"finish_chance": 50.0, "finish_bonus": 0.0}, "a numeric string reads; a negative is floored")
	var missing := FinishingStrike.resolve({"finish_strike": BLOCK}, {})
	assert_eq(missing, {"finish_chance": 0.0, "finish_bonus": 0.0}, "a level without the field gives 0 (level_errors reports it)")


# --- Loadout.stats -----------------------------------------------------------------------------------------------------

func test_stats_carry_the_fields_by_rank_for_a_skill_with_the_block() -> void:
	var w := _world({"finish_strike": BLOCK})
	var one := w.loadout.stats("finisher", 1)
	assert_eq(one.finish_chance, 38.0)
	assert_eq(one.finish_bonus, 120.0)
	var two := w.loadout.stats("finisher", 2)
	assert_eq(two.finish_chance, 60.0)
	assert_eq(two.finish_bonus, 175.0)
	assert_near(float(one.crit), _base(w), 1e-9, "the stats' own crit stays the base chance (only the last line is raised)")
	assert_true(float(one.crit) >= BASE_CRIT and float(one.crit) < BASE_CRIT + 0.05, "the skill mod plus the character's small crit")


func test_a_skill_without_the_block_has_byte_identical_stats() -> void:
	var with_block := _world({"finish_strike": BLOCK})
	var without := _world()
	var a := without.loadout.stats("finisher", 1)
	var b := with_block.loadout.stats("finisher", 1)
	assert_false(a.has("finish_chance"))
	assert_false(a.has("finish_bonus"))
	var stripped := b.duplicate()
	stripped.erase("finish_chance")
	stripped.erase("finish_bonus")
	assert_eq(var_to_str(a), var_to_str(stripped), "the block adds exactly its two keys")
	for key: String in without.book.defs:
		# Assassinate (SH11 #436) is the one shipped skill with the block: it carries the keys, every other skill none.
		assert_eq(without.loadout.stats(key).has("finish_chance"), FinishingStrike.has_block(without.book.defs[key]),
			"%s: the key exists exactly when the skill has the block" % key)


# --- Behaviour on a cast -----------------------------------------------------------------------------------------------

## The crit flags and damages `lines` rolls of a single cast give: the shadow stream replays the world's own stream from the same
## state, so the expectation is the formula (one randf per line, in order), not a copy of the code under test.
func _expected_lines(draws: Array, with_finish: bool, count: int, base: float) -> Array:
	var out := []
	for i in draws.size():
		var chance := base
		var bonus := 0.0
		if with_finish and i % count == count - 1:
			chance = minf(1.0, base + 0.38)
			bonus = 120.0
		var crit: bool = draws[i] < chance
		var damage := 10.0
		if crit:
			damage = 10.0 * (1.5 + bonus / 100.0)
		out.append({"crit": crit, "damage": roundi(damage)})
	return out


## The world's resolved base crit chance of the skill (the 30% skill mod plus the character's own crit).
func _base(w: RunWorld) -> float:
	return float(w.loadout.stats("finisher").crit)


func _cast_with_seed(w: RunWorld, s: int, mobs: int) -> Array:
	for i in mobs:
		_mob(w, -20.0 - 10.0 * i)
	w.rng.seed = s
	var shadow := RandomNumberGenerator.new()
	shadow.state = w.rng.state
	var draws := []
	for i in 3 * mobs:
		draws.append(shadow.randf())
	var hits := _of(_cast(w), "mob_hit")
	assert_eq(hits.size(), 3 * mobs, "every line lands")
	return [hits, draws]


func test_a_three_line_cast_rolls_two_lines_at_base_and_the_last_at_the_finishing_chance() -> void:
	var seen_branch := {"base_only": false, "finisher_only": false}
	for s in range(1, 41):
		var w := _world({"finish_strike": BLOCK})
		var got := _cast_with_seed(w, s, 1)
		var hits: Array = got[0]
		var want := _expected_lines(got[1], true, 3, _base(w))
		for i in 3:
			assert_eq(hits[i].crit, want[i].crit, "seed %d line %d crit flag" % [s, i])
			assert_eq(hits[i].damage, want[i].damage, "seed %d line %d damage" % [s, i])
		var draw: float = got[1][2]
		if draw >= _base(w) and draw < _base(w) + 0.38:
			assert_true(hits[2].crit, "a draw between the base and the finishing chance crits only the last line")
			seen_branch.finisher_only = true
		if draw < _base(w):
			seen_branch.base_only = true
	assert_true(seen_branch.finisher_only, "the seeds exercise the branch the finisher changes")
	assert_true(seen_branch.base_only, "and the branch where even the base chance crits")


func test_the_finishing_crit_adds_skill_percent_points_on_top_of_the_ordinary_multiplier() -> void:
	var got := {}
	for s in range(1, 200):
		var w := _world({"finish_strike": BLOCK})
		var r := _cast_with_seed(w, s, 1)
		var hits: Array = r[0]
		if hits[2].crit and not got.has("last"):
			got["last"] = hits[2].damage
		if hits[0].crit and not got.has("first"):
			got["first"] = hits[0].damage
		if got.size() == 2:
			break
	assert_eq(got.last, 27, "10 x (1 x 1.5 + 120/100): the bonus points go on top of the ordinary 1.5 multiplier (D19)")
	assert_eq(got.first, 15, "an ordinary line's crit is still x1.5")


func test_a_one_line_cast_uses_its_only_line_as_the_finisher() -> void:
	var worlds := 0
	for s in range(1, 41):
		var w := _world({"finish_strike": BLOCK}, {"attackCount": 1.0})
		_mob(w, -20.0)
		w.rng.seed = s
		var shadow := RandomNumberGenerator.new()
		shadow.state = w.rng.state
		var draw := shadow.randf()
		var hits := _of(_cast(w), "mob_hit")
		assert_eq(hits.size(), 1)
		assert_eq(hits[0].crit, draw < _base(w) + 0.38, "seed %d: the only line rolls at base + 38%%" % s)
		worlds += 1
	assert_eq(worlds, 40)


func test_every_targets_last_line_is_a_finisher() -> void:
	for s in range(1, 41):
		var w := _world({"finish_strike": BLOCK})
		var got := _cast_with_seed(w, s, 2)
		var hits: Array = got[0]
		# Targets resolve one after the other, three lines each: lines 3 and 6 of the stream are the finishers.
		var want := _expected_lines(got[1], true, 3, _base(w))
		for i in 6:
			assert_eq(hits[i].crit, want[i].crit, "seed %d line %d" % [s, i])
			assert_eq(hits[i].damage, want[i].damage, "seed %d line %d" % [s, i])


func test_a_skill_without_the_block_rolls_every_line_at_the_base_chance() -> void:
	for s in range(1, 41):
		var w := _world()
		var got := _cast_with_seed(w, s, 1)
		var want := _expected_lines(got[1], false, 3, _base(w))
		for i in 3:
			assert_eq(got[0][i].crit, want[i].crit, "seed %d line %d" % [s, i])
			assert_eq(got[0][i].damage, want[i].damage, "seed %d line %d" % [s, i])


func test_twin_worlds_draw_the_same_number_of_values() -> void:
	for s in [1, 7, 430]:
		var finishing := _world({"finish_strike": BLOCK}, {}, s)
		var plain := _world({}, {}, s)
		for w: RunWorld in [finishing, plain]:
			_mob(w, -20.0)
			_mob(w, -30.0)
			_cast(w)
		assert_eq(finishing.rng.state, plain.rng.state, "seed %d: same stream position after the cast (no extra, no reorder)" % s)
		for w: RunWorld in [finishing, plain]:
			for i in 70:
				_cast(w) # the cooldown passes and the skill casts again; the events are discarded
		assert_eq(finishing.rng.state, plain.rng.state, "seed %d: and after a second cast" % s)


func test_the_hit_carries_the_crit_flag_the_numbers_use() -> void:
	for s in range(1, 41):
		var w := _world({"finish_strike": BLOCK, "damage": "fixed"})
		_mob(w, -20.0)
		w.rng.seed = s
		var hits := _of(_cast(w), "mob_hit")
		for h: Dictionary in hits:
			assert_true(h.has("crit"))
			assert_eq(h.crit, h.damage > 10, "seed %d: a crit line is the one above the plain 10" % s)


# --- Skill window -------------------------------------------------------------------------------------------------------

func test_the_skill_window_names_the_last_strike_only_for_a_skill_with_the_block() -> void:
	var with_block := _world({"finish_strike": BLOCK})
	var line := SkillText.new(with_block.book).level_line("finisher", 1, with_block.loadout.stats("finisher", 1))
	assert_true(line.contains("The last strike has a 38% chance of +120% on top of a critical hit"), line)
	var rank_two := SkillText.new(with_block.book).level_line("finisher", 2, with_block.loadout.stats("finisher", 2))
	assert_true(rank_two.contains("60% chance of +175% on top of a critical hit"), rank_two)
	var without := _world()
	assert_false(SkillText.new(without.book).level_line("finisher", 1, without.loadout.stats("finisher", 1)).contains("last strike"))


# --- A form's sub ------------------------------------------------------------------------------------------------------

func test_a_hit_from_a_forms_sub_carries_the_finishing_strike() -> void:
	var seen_last_only := false
	for s in range(1, 41):
		var w := _world({"slot": "form_sub", "form_sub_of": ["synth_form"], "finish_strike": BLOCK, "cooldown": 0.5,
			"cast": {"rule": "range_around", "min_targets": 1}})
		w.loadout.order.clear()
		w.book.defs["synth_form"] = {"skill_id": 9991001, "book": "999", "job": 999, "kind": "form", "slot": "active",
			"damage": "none", "cooldown": 18.0, "ranks": [1], "cast": {"rule": "form", "mob_within": 400},
			"form": {"duration": 12.0, "exclusive_group": "test", "effects": {},
				"subs": [{"skill": "finisher", "first_after": 0.1, "interval": 0.5}]}}
		_mob(w, -20.0)
		w.rng.seed = s
		var shadow := RandomNumberGenerator.new()
		shadow.state = w.rng.state
		var draws := [shadow.randf(), shadow.randf(), shadow.randf()]
		w.runner.forms.start(w, "synth_form", w.loadout.stats("synth_form"))
		w.drain_events()
		var hits := []
		for tick in 30:
			hits.append_array(_of(_cast(w), "mob_hit"))
			if hits.size() >= 3:
				break
		assert_true(hits.size() >= 3, "seed %d: the sub struck" % s)
		var want := _expected_lines(draws, true, 3, _base(w))
		for i in 3:
			assert_eq(hits[i].crit, want[i].crit, "seed %d line %d crit" % [s, i])
			assert_eq(hits[i].damage, want[i].damage, "seed %d line %d damage" % [s, i])
		if draws[2] >= _base(w) and draws[2] < _base(w) + 0.38:
			seen_last_only = true
	assert_true(seen_last_only, "a seed where only the finishing chance crits")


# --- Data checks -------------------------------------------------------------------------------------------------------

func _errors(block: Variant) -> PackedStringArray:
	return FinishingStrike.errors({"skills": {"slash": {"finish_strike": block}}})


func test_the_block_must_name_both_fields() -> void:
	assert_eq(_errors(BLOCK), PackedStringArray())
	assert_eq(FinishingStrike.errors({"skills": {"slash": {}}}), PackedStringArray(), "no block, no error")
	assert_eq(_errors("prop").size(), 1, "an object is required")
	var no_bonus := _errors({"chance_field": "prop"})
	assert_eq(no_bonus.size(), 1)
	assert_true(no_bonus[0].contains("bonus_field") and no_bonus[0].contains("slash"), no_bonus[0])
	assert_eq(_errors({}).size(), 2, "both fields missing")
	assert_eq(_errors({"chance_field": "", "bonus_field": 5}).size(), 2)


func test_the_shipped_data_passes_the_structural_check() -> void:
	var data := DataRepo.load_all()
	assert_eq(FinishingStrike.errors(data.skills), PackedStringArray())


## The level errors of the synthetic skill only: the shipped Assassinate has no table in these synthetic books (test_dark_sight checks it
## on the real one).
func _own_level_errors(book: SkillBook) -> PackedStringArray:
	var out := PackedStringArray()
	for error in FinishingStrike.level_errors(book):
		if error.begins_with("skill 'finisher'"):
			out.append(error)
	return out


func test_the_named_fields_must_exist_on_every_level_of_the_skill() -> void:
	var good := _world({"finish_strike": BLOCK})
	assert_eq(_own_level_errors(good.book), PackedStringArray())
	var typo := _world({"finish_strike": {"chance_field": "prop", "bonus_field": "critDamage"}})
	var errors := _own_level_errors(typo.book)
	assert_eq(errors.size(), 2, "one per rank of the skill")
	assert_true(errors[0].contains("finisher") and errors[0].contains("critDamage"), errors[0])
	var thin := _world({"finish_strike": BLOCK})
	thin.book.level_node("finisher", 1).erase("prop")
	assert_eq(_own_level_errors(thin.book).size(), 1, "a level missing the field is named")
