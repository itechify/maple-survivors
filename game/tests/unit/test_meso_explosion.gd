extends TestCase
## Shadower's Meso Explosion (SH10 #435, spec #425): the finisher on the Shadower meso charge. Admission (at least 4 pips and 3
## monsters in the forward box), the whole charge spent (keeping `meter_keep` pips), the lines and per-line percent by rank
## (`attackCount` and `x` / 10 through `damage_basis`), damage x(1 + spent x 0.08) on top of the held-pip +2%, `meso_picked` pips
## (600 mesos each, remainder carried, no decay, cap 10, `meter_changed` only on change), no mesos change anywhere, arbitration
## with a synthetic second finisher, the rarity bonuses, and the 20-line x 6-monster tick. Synthetic book 421 whose 4211006
## levels carry the real v83 numbers at the eight mapped levels, seeded RNG, fixed 1/60 s ticks; the "real cache" tests call
## require_cache() and SKIP without it.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const DAGGER := 1332005
const KEY := "meso_explosion"
const TIERS := ["rare", "epic", "unique", "legendary"]
## Rank 1..8 -> WZ level (a 30-level skill), then `x` (tier A, the String's "Mastery"), `attackCount` and the box at that level.
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const X := [560, 640, 720, 780, 860, 930, 970, 1000]
const LINES := [10, 12, 14, 14, 16, 18, 20, 20]
## The forward box (left-facing feet offsets) changes at levels 11 and 21: ranks 1-2, 3-5, 6-8.
const BOXES := [Rect2(-200, -100, 200, 150), Rect2(-250, -110, 250, 160), Rect2(-300, -120, 300, 170)]
const BOX_OF_RANK := [0, 0, 1, 1, 1, 2, 2, 2]


static func _box_group(lv: int) -> int:
	return 0 if lv <= 10 else 1 if lv <= 20 else 2


## `x` / `attackCount` at WZ level `lv`: the recorded values at the mapped levels, linear in between (nothing reads those).
static func _x(lv: int) -> float:
	var at := LEVELS.find(lv)
	return float(X[at]) if at >= 0 else roundf(500.0 + 500.0 * float(lv - 1) / 29.0)


static func _lines(lv: int) -> float:
	var at := LEVELS.find(lv)
	return float(LINES[at]) if at >= 0 else roundf(10.0 + 10.0 * float(lv - 1) / 29.0)


## Book 421 with Meso Explosion: no `damage` field on any level, `x`, `attackCount`, `mobCount` 6 and the box by level group.
## `mob_count` overrides the monsters (the synthetic second finisher uses a smaller one).
static func book_node(mob_count := 6.0, skill_id := "4211006") -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var box: Rect2 = BOXES[_box_group(lv)]
		levels[str(lv)] = {"x": _x(lv), "attackCount": _lines(lv), "mobCount": mob_count, "mpCon": 10.0 + lv,
			"lt": {"$v": [box.position.x, box.position.y]}, "rb": {"$v": [box.end.x, box.end.y]}}
	return {"icon": RF._canvas(32, 32), "level": levels}


## A Shadower (job 422 flipped playable in this test's data) holding a dagger on the flat quiet map at x = 400, only Meso
## Explosion learned at rank `rank_value`. Mobs are tiny and still; the player cannot die. `extra` skill keys join the pool.
func _world(rank_value := 1, p_seed := 435, extra: Dictionary = {}) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["422"]["playable"] = true
	for k: String in extra:
		data.skills.skills[k] = extra[k]
		data.jobs_survivor.jobs["422"].skill_pool.append(k)
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.skill_imgs["421"] = {"skill": {"4211006": book_node()}}
	for k: String in extra:
		setup.skill_imgs["421"].skill[str(int(extra[k].skill_id))] = book_node(2.0)
	var w := RunWorld.new(setup)
	w.set_job(422)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.equipment.worn.weapon = Equipment.create(DAGGER, {"incPAD": 20})
	w.refresh_player_stats()
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0.0
	w.god = true
	assert_true(w.learn_skill(KEY), "a Shadower can learn Meso Explosion")
	w.loadout.set_rank(KEY, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


## A monster `dx` px in front of the player (the facing side; negative = behind).
func _mob(w: RunWorld, dx: float, hp := 1000000000, boss := false) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx * w.player.facing, 190, 100000)
	w.swarm.hp[slot] = hp
	w.swarm.max_hp[slot] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _mobs(w: RunWorld, n: int, first := 60.0, gap := 15.0) -> Array[int]:
	var out: Array[int] = []
	for i in n:
		out.append(_mob(w, first + gap * i))
	return out


func _fill(w: RunWorld, pips: int) -> void:
	w.meter.value = pips


## One runner tick; returns that tick's events.
func _step(w: RunWorld) -> Array:
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _hits(events: Array, key := KEY) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


func _meter_events(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "meter_changed")


func _run(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.step(DT, MoveInput.new())


# --- the definition ------------------------------------------------------------------------------------------------------

func test_the_definition_matches_the_spec_row() -> void:
	var w := _world()
	var d := w.book.def(KEY)
	assert_eq([int(d.skill_id), String(d.book), int(d.job), String(d.kind), String(d.slot), String(d.damage)],
		[4211006, "421", 421, "instant", "active", "physical"])
	assert_eq([String(d.cast.rule), int(d.cast.min_targets), d.cast.size()], ["box", 3, 2])
	assert_eq(d.damage_basis, {"field": "x", "scale": 0.1})
	assert_eq([String(d.meter.role), int(d.meter.min), String(d.meter.spend), float(d.meter.damage_per_unit), String(d.meter.unit),
		d.meter.size()], ["finisher", 4, "all", 0.08, "pips", 5])
	assert_eq([float(d.cooldown), String(d.action)], [6.0, "prone2"])
	assert_false(d.has("ranks"), "the default 30-level table: 4 / 8 / 12 / 15 / 19 / 23 / 27 / 30")
	assert_false(d.has("hp_cost"))
	assert_false(d.has("cost") or d.has("mesos") or d.has("meso_cost"), "nothing is ever spent from the mesos (D7)")
	assert_eq(String(d.effect), "Skill.wz/421.img/skill/4211006/effect")
	assert_eq(d.sounds, {"use": "Sound.wz/Skill.img/4211006/Use", "hit": "Sound.wz/Skill.img/4211006/Hit"})
	assert_eq(w.book.max_level(KEY), 30)
	assert_eq(w.book.max_rank(KEY), 8)
	assert_true(KEY in w.jobs.skill_pool(422), "the pool names it")


func test_the_hit_art_cycles_the_nine_burst_nodes_per_line() -> void:
	var d := _world().book.def(KEY)
	var lines: Array = d.hit_lines
	assert_eq(lines.size(), 20, "one entry for each line of the longest cast")
	for i in lines.size():
		assert_eq(String(lines[i]), "Skill.wz/421.img/skill/4211006/hit/%d" % (i % 9), "line %d" % i)
	assert_eq(String(d.hit), "Skill.wz/421.img/skill/4211006/hit/0")


# --- lines, percent, box by rank -----------------------------------------------------------------------------------------

func test_lines_and_the_per_line_percent_follow_the_node_by_rank() -> void:
	var w := _world()
	for rank_value in range(1, 9):
		var st := w.loadout.stats(KEY, rank_value)
		var label := "rank %d" % rank_value
		assert_eq(int(st.level), LEVELS[rank_value - 1], label)
		assert_eq(int(st.attack_count), LINES[rank_value - 1], "%s: the node's attackCount" % label)
		assert_near(st.damage_percent, X[rank_value - 1] / 10.0, 0.0001, "%s: x / 10" % label)
		assert_near(st.damage_pct, X[rank_value - 1] / 1000.0, 0.000001, label)
		assert_eq(int(st.mob_count), 6, label)
		assert_eq(st.box, BOXES[BOX_OF_RANK[rank_value - 1]], "%s: the WZ box" % label)
		assert_true(st.has_box, label)
	for i in 3:
		var rank_value: int = [1, 4, 8][i]
		assert_near(w.loadout.stats(KEY, rank_value).damage_percent, [56.0, 78.0, 100.0][i], 0.0001)
		assert_eq(int(w.loadout.stats(KEY, rank_value).attack_count), [10, 14, 20][i])


func test_the_lines_are_not_interpolated_and_a_wz_damage_field_would_win() -> void:
	var w := _world()
	# Ranks 3 and 4 (levels 12 and 15) both explode 14 bags; ranks 7 and 8 both 20, while the percent keeps rising.
	assert_eq(int(w.loadout.stats(KEY, 3).attack_count), int(w.loadout.stats(KEY, 4).attack_count))
	assert_eq(int(w.loadout.stats(KEY, 7).attack_count), int(w.loadout.stats(KEY, 8).attack_count))
	assert_true(w.loadout.stats(KEY, 4).damage_percent > w.loadout.stats(KEY, 3).damage_percent)
	var node: Dictionary = w.book.level_node(KEY, 15)
	node["damage"] = 250.0
	assert_near(w.loadout.stats(KEY, 4).damage_pct, 2.5, 0.000001, "the basis yields to a WZ damage number")
	node.erase("damage")
	assert_near(w.loadout.stats(KEY, 4).damage_pct, 0.78, 0.000001)


# --- admission ------------------------------------------------------------------------------------------------------------

func test_it_needs_four_pips_and_three_monsters_in_the_box() -> void:
	var w := _world(8)
	_mobs(w, 3)
	_fill(w, 3)
	_step(w)
	assert_eq(w.runner.casts, 0, "three pips: not yet")
	assert_eq(w.meter.value, 3, "a refusal spends nothing")
	_fill(w, 4)
	var events := _step(w)
	assert_eq(w.runner.casts, 1, "four pips, three monsters")
	assert_eq(_hits(events).size(), 20 * 3)

	var lone := _world(8)
	_mobs(lone, 2)
	_fill(lone, 10)
	_step(lone)
	assert_eq(lone.runner.casts, 0, "two monsters: a lone crowd is not enough")
	assert_eq(lone.meter.value, 10)
	assert_false(lone.runner.cooldowns.has(KEY) and float(lone.runner.cooldowns[KEY]) > 0.5, "and no cooldown starts")


func test_monsters_behind_or_beyond_the_box_do_not_count() -> void:
	var w := _world(1)
	# Rank 1: the box reaches 200 px in front. Two inside, one behind, one beyond.
	_mob(w, 60)
	_mob(w, 90)
	_mob(w, -80)
	_mob(w, 260)
	_fill(w, 10)
	_step(w)
	assert_eq(w.runner.casts, 0, "only two monsters are inside the forward box")
	_mob(w, 150)
	_step(w)
	assert_eq(w.runner.casts, 1, "a third one inside admits it")


func test_a_monster_above_the_box_does_not_count() -> void:
	var w := _world(1)
	_mob(w, 60)
	_mob(w, 90)
	var high := _mob(w, 120)
	w.swarm.y[high] -= 400.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_fill(w, 10)
	_step(w)
	assert_eq(w.runner.casts, 0)


func test_it_strikes_at_most_six_monsters_and_every_one_takes_every_line() -> void:
	var w := _world(8)
	var slots := _mobs(w, 8, 40.0, 12.0)
	_fill(w, 10)
	var hits := _hits(_step(w))
	assert_eq(hits.size(), 6 * 20, "six monsters x twenty lines")
	var per := {}
	for h: Dictionary in hits:
		per[int(h.mob)] = int(per.get(int(h.mob), 0)) + 1
	assert_eq(per.size(), 6)
	for m in per:
		assert_eq(per[m], 20, "slot %d" % m)
	assert_false(slots[7] in per, "the farthest two are left out")


func test_a_scheduled_boss_is_struck_before_the_nearer_crowd() -> void:
	var w := _world(8)
	_mobs(w, 6, 40.0, 10.0)
	var boss := _mob(w, 150, 1000000000, true)
	w.mob_boss[boss] = 0
	_fill(w, 10)
	var per := {}
	for h: Dictionary in _hits(_step(w)):
		per[int(h.mob)] = int(per.get(int(h.mob), 0)) + 1
	assert_eq(per.get(boss, 0), 20, "bosses first, as every capped skill")
	assert_eq(per.size(), 6)


func test_the_cast_holds_the_prone_stance_and_waits_six_seconds() -> void:
	var w := _world(8)
	_mobs(w, 3)
	_fill(w, 10)
	var events := _step(w)
	var casts := events.filter(func(e: Dictionary) -> bool: return e.type == "cast" and e.skill == KEY)
	assert_eq(casts.size(), 1)
	assert_eq(String(casts[0].action), "prone2")
	assert_eq(String(casts[0].effect), "Skill.wz/421.img/skill/4211006/effect")
	assert_near(w.runner.stats_of(w, KEY).action_time, 1.0, 0.0001, "the stance's two frames, 700 + 300 ms (tier C)")
	assert_near(float(w.runner.cooldowns[KEY]), 6.0, 0.05)
	_fill(w, 10)
	for tick in 300:
		w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "five seconds later it is still cooling down")
	for tick in 90:
		w.runner.step(DT, w)
	assert_eq(w.runner.casts, 2, "and casts again once the six seconds are over")


# --- spending the charge --------------------------------------------------------------------------------------------------

func test_it_spends_the_whole_charge_and_reports_only_the_change() -> void:
	var w := _world(8)
	_mobs(w, 3)
	_fill(w, 7)
	var events := _step(w)
	assert_eq(w.meter.value, 0)
	assert_eq(_meter_events(events), [{"type": "meter_changed", "id": "meso_charge", "value": 0, "max": 10}])
	# Its own hits never earn a pip (the Shadower meter gains from mesos only).
	_run(w, 30)
	assert_eq(w.meter.value, 0)


func test_meter_keep_pips_stay_and_only_the_rest_is_spent() -> void:
	var w := _world(8)
	w.loadout.add_skill_mod(KEY, "meter_keep", "add", 2)
	_mobs(w, 3)
	_fill(w, 10)
	var st := w.runner.stats_of(w, KEY)
	assert_eq(int(roundf(st.meter_keep)), 2)
	_step(w)
	assert_eq(w.meter.value, 2, "the explosion keeps two pips")
	# Exactly at the minimum with a keep of two: it casts and spends two.
	var cast := w.meter.begin_cast(w, KEY, st)
	assert_eq(cast.meter_spent, 0, "nothing left above the kept pips (value 2 now)")
	_fill(w, 4)
	cast = w.meter.begin_cast(w, KEY, st)
	assert_eq(cast.meter_spent, 2)
	assert_eq(w.meter.value, 2)


func test_a_keep_beyond_the_held_pips_spends_nothing_and_never_makes_pips() -> void:
	var w := _world(8)
	w.loadout.add_skill_mod(KEY, "meter_keep", "add", 6)
	_mobs(w, 3)
	_fill(w, 4)
	var events := _step(w)
	assert_eq(w.runner.casts, 1, "four pips still admit it")
	assert_eq(w.meter.value, 4, "no pip spent, none created")
	assert_eq(_meter_events(events).size(), 0, "no change, no event")


func test_the_damage_is_one_plus_the_pips_spent_times_eight_percent_on_top_of_the_held_pip_bonus() -> void:
	var w := _world(8)
	var st := w.loadout.stats(KEY)
	for pips in [4, 7, 10]:
		_fill(w, pips)
		var cast := w.meter.begin_cast(w, KEY, st)
		var want: float = (1.0 + pips * 0.02) * (1.0 + pips * 0.08)
		assert_near(cast.damage_max / st.damage_max, want, 0.000001, "%d pips: x%.4f" % [pips, want])
		assert_near(cast.damage_min / st.damage_min, want, 0.000001)
		assert_eq(cast.meter_spent, pips)
		assert_eq(w.meter.value, 0, "spent")
	_fill(w, 10)
	assert_near(w.meter.begin_cast(w, KEY, st).damage_max / st.damage_max, 1.2 * 1.8, 0.000001, "a full charge is x2.16 in all")


func test_a_full_charge_hits_harder_than_four_pips_end_to_end() -> void:
	var dealt := {}
	for pips in [4, 10]:
		var w := _world(8, 77)
		w.loadout.add_skill_mod(KEY, "damage", "mul", 500.0) # big numbers: integer rounding of 2-7 point hits would swamp the ratio
		_mobs(w, 3)
		_fill(w, pips)
		var total := 0
		for h: Dictionary in _hits(_step(w)):
			total += int(h.damage)
		dealt[pips] = total
	assert_true(dealt[4] > 0)
	var want := ((1.0 + 10 * 0.02) * (1.0 + 10 * 0.08)) / ((1.0 + 4 * 0.02) * (1.0 + 4 * 0.08))
	assert_near(float(dealt[10]) / float(dealt[4]), want, want * 0.03, "the same seed rolls the same lines, scaled by the pips")


func test_the_per_line_hit_is_the_node_percent_of_the_weapon_roll() -> void:
	# Rank 1 (56%) against rank 8 (100%) with the same seed and the same pips: the lines scale as 100 / 56.
	var dealt := []
	for rank_value in [1, 8]:
		var w := _world(rank_value, 5)
		w.loadout.add_skill_mod(KEY, "damage", "mul", 500.0) # big numbers: integer rounding of 2-7 point hits would swamp the ratio
		_mobs(w, 3)
		_fill(w, 4)
		var total := 0.0
		var count := 0
		for h: Dictionary in _hits(_step(w)):
			total += float(h.damage)
			count += 1
		dealt.append(total / count)
	assert_near(dealt[1] / dealt[0], 100.0 / 56.0, 0.08, "mean damage per line, rank 8 over rank 1")


func test_the_hits_spend_no_mesos_and_change_no_wallet_or_drop() -> void:
	var w := _world(8)
	w.mesos = 98765
	var snapshot_before: int = w.character_snapshot().mesos
	var slots := _mobs(w, 3)
	w.swarm.hp[slots[0]] = 3
	w.swarm.max_hp[slots[0]] = 3
	_fill(w, 10)
	var pickups_before := w.pickups.step_mesos
	_run(w, 5)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.mesos, 98765, "the wallet is untouched by the cast and by its hits")
	assert_eq(w.character_snapshot().mesos, snapshot_before, "and so is the saved character")
	assert_eq(w.pickups.step_mesos, pickups_before, "no meso drop is made or taken by the cast")
	assert_eq(w.meter.carry, 0)


# --- the Shadower meso charge ---------------------------------------------------------------------------------------------

func test_the_meter_block_is_the_shadower_charge_with_no_decay() -> void:
	var w := _world()
	var cfg: Dictionary = w.meter.config
	assert_eq(String(cfg.id), "meso_charge")
	assert_eq(int(cfg.max), 10)
	assert_eq([String(cfg.gain.event), int(cfg.gain.amount), int(cfg.gain.per_mesos), cfg.gain.size()], ["meso_picked", 1, 600, 3])
	assert_eq([String(cfg.per_unit.stat), float(cfg.per_unit.value)], ["damage", 0.02])
	assert_false(cfg.has("decay"), "SH-10: the charge never decays")


func test_pickups_make_a_pip_per_six_hundred_mesos_and_carry_the_remainder() -> void:
	var w := _world()
	w.mesos = 0
	var events: Array = []
	w.meter.gain_amount("meso_picked", 599, events)
	assert_eq(w.meter.value, 0)
	assert_eq(w.meter.carry, 599)
	assert_eq(events.size(), 0, "no pip, no event")
	w.meter.gain_amount("meso_picked", 1, events)
	assert_eq(w.meter.value, 1)
	assert_eq(w.meter.carry, 0)
	assert_eq(events, [{"type": "meter_changed", "id": "meso_charge", "value": 1, "max": 10}])
	w.meter.gain_amount("meso_picked", 1850, events)
	assert_eq(w.meter.value, 4, "three more")
	assert_eq(w.meter.carry, 50, "the remainder is held")
	w.meter.gain_amount("meso_picked", 550, events)
	assert_eq(w.meter.value, 5, "50 + 550 is one pip exactly")
	assert_eq(w.meter.carry, 0)


func test_the_charge_caps_at_ten_and_the_cap_emits_nothing() -> void:
	var w := _world()
	var events: Array = []
	w.meter.gain_amount("meso_picked", 600 * 40, events)
	assert_eq(w.meter.value, 10)
	assert_eq(events.size(), 1, "one event for the one change (0 -> 10)")
	assert_eq(events[0].value, 10)
	events.clear()
	w.meter.gain_amount("meso_picked", 6000, events)
	assert_eq(w.meter.value, 10)
	assert_eq(events.size(), 0, "a pickup at the cap changes nothing")


func test_real_pickups_feed_the_charge_and_the_wallet_both() -> void:
	var w := _world()
	w.mesos = 100
	for amount in [400, 500]:
		var slot := w.pickups.spawn_meso(w.player.pos + Vector2(0, -10), amount)
		w.pickups.state[slot] = PickupSystem.REST
	w.drain_events()
	w.step(DT, MoveInput.new())
	var events := w.drain_events()
	assert_eq(w.mesos, 1000, "the wallet gets every meso")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "meso_picked"),
		[{"type": "meso_picked", "amount": 900, "count": 2}])
	assert_eq(w.meter.value, 1)
	assert_eq(w.meter.carry, 300)
	assert_eq(_meter_events(events), [{"type": "meter_changed", "id": "meso_charge", "value": 1, "max": 10}])


func test_a_shadower_without_steal_gains_pips_from_ordinary_pickups() -> void:
	var w := _world()
	assert_false(w.loadout.order.has("steal"), "only Meso Explosion is learned")
	var slot := w.pickups.spawn_meso(w.player.pos + Vector2(0, -10), 1300)
	w.pickups.state[slot] = PickupSystem.REST
	w.step(DT, MoveInput.new())
	assert_eq(w.meter.value, 2)
	assert_eq(w.meter.carry, 100)


func test_the_charge_never_decays() -> void:
	var w := _world()
	w.meter.gain_amount("meso_picked", 3000, w.events)
	assert_eq(w.meter.value, 5)
	_run(w, 60 * 60)
	assert_eq(w.meter.value, 5, "a minute later: still five")
	w.drain_events()
	assert_eq(_meter_events(w.drain_events()).size(), 0)


func test_the_summary_records_the_mean_and_the_peak() -> void:
	var w := _world()
	w.meter.gain_amount("meso_picked", 3000, w.events)
	_run(w, 60)
	w.meter.gain_amount("meso_picked", 3000, w.events)
	_run(w, 60)
	var stats := w.meter.stats()
	assert_eq(int(stats.peak), 10)
	assert_near(float(stats.mean), 7.5, 0.1, "five for a second, ten for a second")


func test_every_pool_cast_gets_two_percent_per_held_pip_and_other_keys_do_not() -> void:
	var w := _world()
	# double_stab is a pool key (defined in thief.json until SH6): any pool key reads the per-unit bonus.
	var st := {"damage_min": 100.0, "damage_max": 200.0, "status_damage_mult": 1.0}
	for field: String in SkillRunner.DAMAGE_FIELDS:
		st[field] = float(st.get(field, 100.0))
	_fill(w, 5)
	for key: String in ["double_stab", "steal", "savage_blow", "boomerang_step"]:
		if key in w.jobs.skill_pool(422):
			var cast := w.meter.begin_cast(w, key, st)
			assert_near(cast.damage_max / st.damage_max, 1.10, 0.000001, "%s: +2%% x 5 pips" % key)
			assert_eq(w.meter.value, 5, "%s spends nothing" % key)
	assert_eq(w.meter.begin_cast(w, "energy_bolt", st), st, "a key outside the pool is untouched")
	assert_eq(w.meter.begin_cast(w, "assaulter", st), st, "so is the mobility skill")


# --- arbitration with a second finisher -----------------------------------------------------------------------------------

## A synthetic second finisher in the Shadower's pool: Meso Explosion's definition under another key and id, `mobCount` 2.
func _rival() -> Dictionary:
	var d: Dictionary = DataRepo.load_all().skills.skills[KEY].duplicate(true)
	d["skill_id"] = 4211999
	d["name"] = "Rival Finisher"
	d["cooldown"] = 1.0
	d.erase("rarity_bonuses")
	return {"rival": d}


func test_the_bigger_crowd_gets_the_charge_whatever_the_learned_order() -> void:
	for rival_first in [false, true]:
		var w := _world(8, 435, _rival())
		if rival_first:
			w.loadout.order.erase("rival")
			w.loadout.order.push_front("rival")
		assert_true(w.learn_skill("rival") or w.loadout.has_skill("rival"))
		w.loadout.set_rank("rival", 8)
		w.refresh_player_stats()
		_mobs(w, 5)
		_fill(w, 8)
		var events := _step(w)
		assert_eq(_hits(events, KEY).size(), 5 * 20, "five monsters: Meso Explosion's six beats the rival's two (rival first: %s)" % rival_first)
		assert_eq(_hits(events, "rival").size(), 0)
		assert_eq(w.meter.value, 0)
		assert_eq(w.runner.casts, 1, "one finisher per tick, and the charge is gone")
		_run(w, 5)
		assert_eq(w.runner.casts, 1, "the rival cannot pay either")


func test_a_single_scheduled_boss_goes_to_the_single_target_finisher() -> void:
	var d: Dictionary = _rival()
	d.rival["cast"] = {"rule": "box"}
	var w := _world(8, 435, d)
	w.learn_skill("rival")
	w.loadout.set_rank("rival", 8)
	w.refresh_player_stats()
	# The rival's node strikes two monsters; make it one so a scheduled boss makes it the better use of the charge.
	w.book.level_node("rival", 30)["mobCount"] = 1.0
	var boss := _mob(w, 60, 1000000000, true)
	w.mob_boss[boss] = 0
	_mob(w, 80)
	_mob(w, 100)
	_fill(w, 6)
	var events := _step(w)
	assert_eq(_hits(events, "rival").size(), 20, "the boss takes the whole rival cast")
	assert_eq(_hits(events, KEY).size(), 0)


func test_a_lone_finisher_that_is_ready_without_a_crowd_waits_for_one() -> void:
	var w := _world(8, 435, _rival())
	w.learn_skill("rival")
	w.loadout.set_rank("rival", 8)
	w.refresh_player_stats()
	_mobs(w, 2)
	_fill(w, 10)
	_step(w)
	assert_eq(w.runner.casts, 0, "both rivals need three monsters: neither fires")
	assert_eq(w.meter.value, 10)


# --- rarity bonuses -------------------------------------------------------------------------------------------------------

func _effects(tier: String) -> Array:
	var out := []
	for bonus: Dictionary in _world().book.def(KEY).rarity_bonuses[tier]:
		out.append_array(bonus.effects)
	return out


func test_the_catalog_lists_the_spec_table_exactly() -> void:
	var bonuses: Dictionary = _world().book.def(KEY).rarity_bonuses
	assert_eq(bonuses.keys(), TIERS)
	var expected := [["meso_up", "Meso Up", [["damage", "mul", 1.2]]], ["wide_explosion", "Wide Explosion", [["area", "mul", 1.2]]],
		["pickpocket", "Pickpocket", [["meter_keep", "add", 2.0]]],
		["pickpocket", "Pickpocket", [["meter_keep", "add", 2.0], ["damage", "mul", 1.2]]]]
	for t in 4:
		assert_eq(bonuses[TIERS[t]].size(), 1, TIERS[t])
		var entry: Dictionary = bonuses[TIERS[t]][0]
		assert_eq([String(entry.id), String(entry.text)], [expected[t][0], expected[t][1]], TIERS[t])
		var got := []
		for effect: Dictionary in entry.effects:
			got.append([String(effect.stat), String(effect.op), float(effect.value)])
		assert_eq(got, expected[t][2], "%s effects" % TIERS[t])
	assert_eq(String(bonuses.legendary[0].id), String(bonuses.unique[0].id), "Legendary shares the Unique's repeat counter")


## One cast at rank 8 with `effects` as skill modifiers: the three monsters in the box and a fourth just beyond the base reach
## (300 px; 340 px is inside the box only when `area` x1.2 widens it to 360). Returns what the cast did.
func _probe(effects: Array) -> Dictionary:
	var w := _world(8)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(KEY, String(e.stat), String(e.op), float(e.value))
	var inside := _mobs(w, 3, 60.0, 20.0)
	var far := _mob(w, 340.0)
	_fill(w, 10)
	var dealt := 0
	var far_hits := 0
	var hits := _hits(_step(w))
	for h: Dictionary in hits:
		dealt += int(h.damage)
		if int(h.mob) == far:
			far_hits += 1
	return {"stats": w.loadout.stats(KEY), "dealt": dealt, "hits": hits.size(), "far": far_hits, "left": w.meter.value,
		"inside": inside.size()}


func test_each_rarity_bonus_changes_the_resolved_cast() -> void:
	var base := _probe([])
	assert_eq(int(base.far), 0, "the fourth monster is out of reach at the base box")
	assert_eq(int(base.left), 0)
	var checked := 0
	for tier: String in TIERS:
		for effect: Dictionary in _effects(tier):
			var label := "%s (%s)" % [tier, effect.stat]
			var with := _probe([effect])
			match String(effect.stat):
				"damage":
					assert_true(float(with.stats.damage_max) > float(base.stats.damage_max), "%s: resolved damage" % label)
					assert_near(float(with.stats.damage_max) / float(base.stats.damage_max), 1.2, 0.000001, label)
					assert_true(int(with.dealt) > int(base.dealt), "%s: dealt %d -> %d" % [label, base.dealt, with.dealt])
				"area":
					assert_true(float(with.stats.area) > float(base.stats.area), "%s: resolved area" % label)
					assert_near(with.stats.box.size.x, base.stats.box.size.x * 1.2, 0.01, "%s: the box widens" % label)
					assert_true(int(with.far) > 0, "%s: the monster beyond the base reach is struck" % label)
					assert_true(int(with.hits) > int(base.hits), label)
				"meter_keep":
					assert_eq(int(with.left), 2, "%s: two pips survive the explosion" % label)
					assert_eq(int(roundf(with.stats.meter_keep)), 2, label)
				_:
					fail("%s: a stat this audit does not know" % label)
			checked += 1
	assert_eq(checked, 5, "1 + 1 + 1 + 2 effects")


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus_and_the_preview_is_stable() -> void:
	for tier: String in TIERS:
		var a := _world()
		var b := _world()
		var id := KEY + "_rank"
		assert_eq(a.loadout.rank(KEY), 1)
		var card := a.upgrades.choice_card(id, a, tier)
		assert_false(card.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		assert_eq(card, a.upgrades.choice_card(id, a, tier), "the preview does not spend the bonus")
		a.upgrades.apply(id, a, tier)
		b.upgrades.apply(id, b, tier)
		assert_eq(a.loadout.rank(KEY), 2, "%s: exactly one rank on top" % tier)
		assert_eq(a.loadout.skill_mods.get(KEY, {}), b.loadout.skill_mods.get(KEY, {}), "%s: same bonus twice" % tier)
		assert_false(a.loadout.skill_mods.get(KEY, {}).is_empty(), "%s: the bonus is applied" % tier)


func test_keep_previews_in_whole_pips_in_the_card_and_the_skill_text() -> void:
	var w := _world()
	var card := w.upgrades.choice_card(KEY + "_rank", w, "unique")
	assert_true("Keeps 2 pips" in String(card.desc), String(card.desc))
	assert_eq(card.skill_mod_changes.meter_keep, {"before": 0, "after": 2})
	w.upgrades.apply(card.id, w, "unique")
	var line := SkillText.new(w.book).level_line(KEY, w.loadout.rank(KEY), w.loadout.stats(KEY))
	assert_true("Needs 4 pips" in line and "Keeps 2 pips" in line, line)
	assert_false("orbs" in line or "energy" in line, line)
	var legendary := w.upgrades.choice_card(KEY + "_rank", w, "legendary")
	w.upgrades.apply(legendary.id, w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:pickpocket" % KEY]), 2, "Legendary shares the Unique's counter")
	assert_eq(int(roundf(w.loadout.stats(KEY).meter_keep)), 4, "two Pickpocket cards keep four")


func test_mastery_repeats_shrink_and_a_new_card_is_offered_to_a_shadower_who_lacks_it() -> void:
	var m := _world(8)
	var card := m.upgrades.choice_card(KEY + "_rank", m, "rare")
	assert_eq(card.card_kind, "mastery")
	m.upgrades.apply(KEY + "_rank", m, "rare")
	m.upgrades.apply(KEY + "_rank", m, "rare")
	assert_eq(m.loadout.rank(KEY), 8)
	assert_near(m.loadout.skill_stat(KEY, "damage", 1.0), 1.392, 0.00001, "x1.2 then x(1 + 0.2 x 0.8)")
	var w := _world()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	assert_has(w.upgrades.eligible(w), KEY + "_new")


func test_the_skill_text_names_the_percent_the_lines_and_the_charge() -> void:
	var w := _world(8)
	var text := SkillText.new(w.book, {})
	var line := text.level_line(KEY, 30, w.loadout.stats(KEY, 8))
	assert_true("100%" in line and "20 bags" in line, line)
	assert_true("Needs 4 pips" in line, line)
	assert_true("Spends all pips" in line, line)


func test_the_window_text_follows_the_balance_levers_and_the_desc_names_no_number() -> void:
	# Review #425 S4: the pips, monsters and per-pip damage are balance levers, so the hand-written desc holds no numbers and the
	# generated lines change when the data does.
	var w := _world(8)
	var text := SkillText.new(w.book, {})
	assert_false(RegEx.create_from_string("\\d").search(text.desc(KEY)) != null, "no digit in the desc: " + text.desc(KEY))
	assert_true("every pip spent adds 8% damage" in text.level_line(KEY, 30, w.loadout.stats(KEY, 8)))
	w.book.defs[KEY] = w.book.defs[KEY].duplicate(true)
	w.book.defs[KEY].meter.damage_per_unit = 0.1
	w.book.defs[KEY].meter.min = 5
	var line := text.level_line(KEY, 30, w.loadout.stats(KEY, 8))
	assert_true("adds 10% damage" in line and "Needs 5 pips" in line, line)


# --- the performance tick -------------------------------------------------------------------------------------------------

## The worst cast: rank 8, a full charge, six monsters, twenty lines each = 120 hits in one tick. The tick's cost is printed
## for the ticket report; the assertion only guards against a runaway (the frame budget is 16 667 us at 60 Hz, measured on the
## quiet synthetic map).
func test_the_twenty_line_six_monster_tick_lands_120_hits_and_is_timed() -> void:
	var w := _world(8)
	_mobs(w, 6, 40.0, 15.0)
	_fill(w, 10)
	w.drain_events()
	var start := Time.get_ticks_usec()
	w.step(DT, MoveInput.new())
	var cast_us := Time.get_ticks_usec() - start
	var events := w.drain_events()
	assert_eq(_hits(events).size(), 120, "20 lines x 6 monsters in one tick")
	var numbers := 0
	for e: Dictionary in events:
		if e.type == "mob_hit":
			numbers += 1
	assert_eq(numbers, 120, "one damage number per hit: the pool grows on demand, it has no cap to overflow")
	start = Time.get_ticks_usec()
	w.step(DT, MoveInput.new())
	var next_us := Time.get_ticks_usec() - start
	print("SH10 perf: meso_explosion 120-hit tick %d us (budget 16667 us), the next idle tick %d us" % [cast_us, next_us])
	assert_true(cast_us < 250000, "the 120-hit tick stays far from a hitch (%d us)" % cast_us)


# --- real cache: all eight ranks against Skill.wz -------------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache_img("Skill.wz/421.img"):
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/421.img")
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"421": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "dagger"
	var node: Dictionary = img.root.skill["4211006"]
	assert_eq(book.max_level(KEY), 30)
	assert_eq(book.max_rank(KEY), 8)
	for rank_value in range(1, 9):
		var lv: int = LEVELS[rank_value - 1]
		var level: Dictionary = node.level[str(lv)]
		var label := "rank %d (level %d)" % [rank_value, lv]
		assert_eq(book.canonical_level(KEY, rank_value), lv, label)
		assert_false(level.has("damage"), "%s: the WZ carries no damage field" % label)
		assert_eq(float(level.x), float(X[rank_value - 1]), "%s: tier A x" % label)
		assert_eq(float(level.attackCount), float(LINES[rank_value - 1]), "%s: tier A attackCount" % label)
		assert_eq(float(level.mobCount), 6.0, label)
		var st := lo.stats(KEY, rank_value)
		assert_eq(int(st.level), lv, label)
		assert_eq(int(st.attack_count), LINES[rank_value - 1], label)
		assert_near(st.damage_percent, X[rank_value - 1] / 10.0, 0.0001, label)
		assert_near(st.damage_pct, X[rank_value - 1] / 1000.0, 0.000001, label)
		assert_eq(int(st.mob_count), 6, label)
		assert_eq(st.box, BOXES[BOX_OF_RANK[rank_value - 1]], "%s: the WZ box" % label)
	for i in 3:
		var rank_value: int = [1, 4, 8][i]
		assert_near(lo.stats(KEY, rank_value).damage_percent, [56.0, 78.0, 100.0][i], 0.0001, "spec rank %d" % rank_value)
	lib.free()


func test_real_cache_the_art_and_sounds_resolve() -> void:
	if not require_cache_img("Skill.wz/421.img"):
		return
	var lib := AssetLibrary.new()
	var d: Dictionary = DataRepo.load_all().skills.skills[KEY]
	var effect := lib.anim(String(d.effect))
	assert_eq(effect.frame_count(), 13, "the dark figure beside the caster")
	var seen := {}
	for path: String in d.hit_lines:
		seen[path] = true
		var anim := lib.anim(path)
		assert_eq(anim.frame_count(), 4, "%s: every burst has four frames" % path)
	assert_eq(seen.size(), 9, "all nine hit nodes are used")
	assert_true(lib.frame(String(d.icon)) != null, "icon")
	for sound: String in d.sounds.values():
		assert_true(lib.sound(sound) != null, "sound %s" % sound)
	assert_eq(Array(lib.missing), [])
	lib.free()
