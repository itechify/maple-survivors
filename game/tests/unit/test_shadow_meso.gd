extends TestCase
## Night Lord's Shadow Meso (NL9 #408, spec #383): `damage_basis` (the skill percent from the tier A `moneyCon`), the held-pip
## bonus of the meso charge (`meter.read_per_unit`, spending nothing), the art tier by level, one bag at the nearest monster
## (a scheduled boss first), the `count` card and the rarity bonuses. Synthetic book 411 whose 4111004 levels carry the real
## v83 endpoints (`moneyCon` 135 -> 570 over 30 levels), seeded RNG, fixed 1/60 s ticks; the "real cache" tests call
## require_cache() and SKIP without it.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CLAW := 1472000
const KEY := "shadow_meso"
const TIERS := ["rare", "epic", "unique", "legendary"]
## Rank 1..8 -> WZ level (30-level skill), `moneyCon` there (tier A) and the skill percent (moneyCon x 0.6, tier C).
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]


## `moneyCon` at WZ level `lv`: the recorded endpoints 135 (Lv1) and 570 (Lv30), linear between (Lv4 180, Lv15 345 exact).
static func money_con(lv: int) -> float:
	return roundf(135.0 + 435.0 * float(lv - 1) / 29.0)


static func _anim(frames: int, w: int, h: int) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"$canvas": [0.0, 0.0, 0.0, float(w), float(h)], "origin": {"$v": [w / 2.0, h / 2.0]}, "delay": 100.0}
	return out


## Book 411 with Shadow Meso: no `damage` field on any level, `moneyCon`, `x` 50, `prop`, and the three art tiers by level
## (87x33 at Lv1-10, 87x33 other art at Lv11-20, 91x34 at Lv21-30: the sizes tell the tiers apart in the nodes).
static func book_node() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var tier := 0 if lv <= 10 else 1 if lv <= 20 else 2
		levels[str(lv)] = {"hs": "h%d" % lv, "moneyCon": money_con(lv), "prop": float(1 + lv / 4), "x": 50.0,
			"ball": _anim(4, [87, 87, 91][tier], [33, 33, 34][tier]), "hit": {"0": _anim(3, [61, 67, 98][tier], 61)}}
	return {"skill": {"4111004": {"icon": RF._canvas(32, 32), "req": {"4111001": 5}, "level": levels}}}


## A Night Lord (job 412 flipped playable in this test's data) holding a claw, on the flat quiet map at x = 400, only Shadow
## Meso learned. Mobs are tiny and still; the player cannot die.
func _world(rank_value := 1, p_seed := 408, with_meso_charge := true) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["412"]["playable"] = true
	if not with_meso_charge:
		data.jobs_survivor.jobs["412"].erase("meter")
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.skill_imgs["411"] = book_node()
	var w := RunWorld.new(setup)
	w.set_job(412)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.equipment.worn.weapon = Equipment.create(CLAW, {"incPAD": 17})
	w.refresh_player_stats()
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0.0
	w.god = true
	assert_true(w.learn_skill(KEY), "a Night Lord can learn Shadow Meso")
	w.loadout.set_rank(KEY, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190, 100000)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == KEY)


func _run(w: RunWorld, ticks: int) -> void:
	for tick in ticks:
		w.step(DT, MoveInput.new())


# --- damage_basis ------------------------------------------------------------------------------------------------------

func test_the_skill_percent_is_money_con_times_point_six_by_rank() -> void:
	var w := _world()
	for rank_value in range(1, 9):
		var st := w.loadout.stats(KEY, rank_value)
		assert_eq(int(st.level), LEVELS[rank_value - 1], "rank %d" % rank_value)
		assert_near(st.damage_pct, money_con(LEVELS[rank_value - 1]) * 0.6 / 100.0, 0.000001, "rank %d" % rank_value)
		assert_near(st.damage_percent, money_con(LEVELS[rank_value - 1]) * 0.6, 0.0001, "the same number x 100")
	assert_near(w.loadout.stats(KEY, 1).damage_pct, 1.08, 0.000001, "rank 1 is 108%")
	assert_near(w.loadout.stats(KEY, 4).damage_pct, 2.07, 0.000001, "rank 4 is 207%")
	assert_near(w.loadout.stats(KEY, 8).damage_pct, 3.42, 0.000001, "rank 8 is 342%")
	assert_eq(String(w.loadout.stats(KEY).damage_type), "physical")


func test_damage_basis_is_the_data_field_and_the_unused_wz_fields_change_nothing() -> void:
	var w := _world()
	var d := w.book.def(KEY)
	assert_eq(d.damage_basis, {"field": "moneyCon", "scale": 0.6})
	var base := w.loadout.stats(KEY, 4)
	# x 50, prop and bulletCount are recorded as unused: a level that changes them resolves the same cast.
	var node: Dictionary = w.book.level_node(KEY, 15)
	var saved := node.duplicate()
	node["x"] = 999.0
	node["prop"] = 99.0
	node["bulletCount"] = 7.0
	var edited := w.loadout.stats(KEY, 4)
	for field: String in ["damage_pct", "count", "pierce", "cooldown", "range", "mob_count", "damage_min", "damage_max"]:
		assert_eq(edited[field], base[field], field)
	node.assign(saved)


func test_a_level_with_a_wz_damage_field_keeps_it_and_other_skills_are_untouched() -> void:
	var w := _world()
	var book := w.book
	book.level_node(KEY, 15)["damage"] = 250.0
	assert_near(w.loadout.stats(KEY, 4).damage_pct, 2.5, 0.000001, "a WZ damage number is never overridden by the basis")
	book.level_node(KEY, 15).erase("damage")
	assert_near(w.loadout.stats(KEY, 4).damage_pct, 2.07, 0.000001)
	# A skill with no damage_basis resolves exactly as before and gains no damage_percent key.
	var other := RF.quiet_world()
	var st := other.loadout.stats("energy_bolt")
	assert_false(st.has("damage_percent"))
	assert_false(other.book.def("energy_bolt").has("damage_basis"))
	for key: String in other.book.defs:
		# Meso Explosion (Shadower SH10 #435) is the second skill with a basis, on `x`.
		if key != KEY and key != "meso_explosion":
			assert_false(other.book.def(key).has("damage_basis"), "only Shadow Meso and Meso Explosion carry a basis (%s)" % key)


func test_a_magic_or_fixed_skill_ignores_a_basis() -> void:
	var w := RF.quiet_world()
	w.book.defs.energy_bolt["damage_basis"] = {"field": "mad", "scale": 0.6}
	assert_eq(w.loadout.stats("energy_bolt").damage_pct, 1.0, "damage_basis is for a physical skill")


# --- the meso charge read ----------------------------------------------------------------------------------------------

func test_each_held_pip_adds_ten_percent_on_top_of_the_meters_three() -> void:
	var w := _world(8)
	var st := w.loadout.stats(KEY)
	assert_eq(w.book.def(KEY).meter, {"read_per_unit": 0.10, "unit": "pip"})
	w.meter.value = 0
	var zero := w.meter.begin_cast(w, KEY, st)
	assert_near(zero.damage_max, st.damage_max, 0.0001, "no pip, no bonus")
	for pips in [1, 5, 10]:
		w.meter.value = pips
		var cast := w.meter.begin_cast(w, KEY, st)
		var want: float = 1.0 + pips * 0.03
		want *= 1.0 + pips * 0.10
		assert_near(cast.damage_max / st.damage_max, want, 0.000001, "%d pips: x%.3f" % [pips, want])
		assert_near(cast.damage_min / st.damage_min, want, 0.000001)
	w.meter.value = 10
	assert_near(w.meter.begin_cast(w, KEY, st).damage_max / st.damage_max, 1.3 * 2.0, 0.000001, "a full charge is x2.6 in all")
	assert_eq(w.meter.value, 10, "begin_cast spends nothing")


func test_a_cast_spends_no_pip_and_no_mesos() -> void:
	var w := _world(8)
	w.mesos = 12345
	w.meter.value = 7
	var carry := w.meter.carry
	_mob(w, 100)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	_run(w, 60)
	assert_eq(_hits(w).size(), 1)
	assert_eq(w.mesos, 12345, "the wallet is untouched by a cast and by its hit")
	assert_eq(w.meter.value, 7, "the pips are read, not spent")
	assert_eq(w.meter.carry, carry)
	assert_false(w.book.def(KEY).has("hp_cost"))
	assert_eq(int(w.loadout.stats(KEY).hp_cost), 0)


func test_a_cast_never_needs_a_pip_or_mesos() -> void:
	var w := _world(1)
	w.mesos = 0
	w.meter.value = 0
	_mob(w, 100)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "an empty charge and an empty wallet still cast")


func test_a_held_pip_changes_the_projectile_it_throws() -> void:
	var damage := []
	for pips in [0, 10]:
		var w := _world(8)
		w.meter.value = pips
		_mob(w, 100)
		w.runner.step(DT, w)
		for i in w.projectiles.capacity():
			if w.projectiles.active[i] != 0:
				damage.append(w.projectiles.dmg_max[i])
	assert_eq(damage.size(), 2)
	assert_near(damage[1] / damage[0], 2.6, 0.0001, "the thrown bag carries the charge read")


func test_without_a_meso_charge_the_skill_still_casts_at_its_plain_damage() -> void:
	var w := _world(8, 408, false)
	assert_true(w.meter.config.is_empty())
	var st := w.loadout.stats(KEY)
	assert_eq(w.meter.begin_cast(w, KEY, st).damage_max, st.damage_max)
	_mob(w, 100)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)


# --- the cast ----------------------------------------------------------------------------------------------------------

func test_it_throws_one_bag_with_the_resolved_numbers_and_waits_three_seconds() -> void:
	var w := _world()
	var near := _mob(w, 90)
	_mob(w, 200)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 1, "one bag")
	assert_near(float(w.runner.cooldowns[KEY]), 3.0 - DT, 0.001, "3.0 s cooldown")
	_run(w, 40)
	var hits := _hits(w)
	assert_eq(hits.size(), 1)
	assert_eq(int(hits[0].mob), near, "the nearest monster")
	var st := w.loadout.stats(KEY)
	assert_eq([st.range, st.speed, st.radius, st.pierce, st.count, st.cast_rule], [300.0, 650.0, 10.0, 0, 1, "nearest"])
	assert_eq(String(st.action), "swingO1", "the claw's own stance: the node has no action and shoot1 hides the claw")
	assert_eq(w.runner.casts, 1)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "not ready again")


func test_it_waits_for_a_monster_inside_three_hundred_pixels() -> void:
	var w := _world()
	_mob(w, 340)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0)
	_mob(w, 280)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)


func test_a_scheduled_boss_is_the_target_before_a_nearer_monster() -> void:
	var w := _world()
	_mob(w, 80)
	var boss := _mob(w, -200, true)
	w.mob_boss[boss] = 0
	w.runner.step(DT, w)
	_run(w, 50)
	var hits := _hits(w)
	assert_eq(hits.size(), 1, "a single target")
	assert_eq(int(hits[0].mob), boss, "the boss first")


func test_the_hit_damage_follows_the_rank_through_the_ordinary_physical_formula() -> void:
	var totals := []
	for rank_value in [1, 8]:
		var w := _world(rank_value)
		var mob := _mob(w, 100)
		w.runner.step(DT, w)
		_run(w, 40)
		var hits := _hits(w)
		assert_eq(hits.size(), 1)
		totals.append(float(w.swarm.max_hp[mob] - w.swarm.hp[mob]))
	assert_true(totals[1] > totals[0] * 2.0, "rank 8 (342%%) hits far harder than rank 1 (108%%): %s" % [totals])


func test_a_count_card_throws_the_second_bag_at_the_next_monster() -> void:
	var w := _world()
	w.loadout.add_skill_mod(KEY, "count", "add", 1.0)
	var first := _mob(w, 80)
	var second := _mob(w, -150)
	w.runner.step(DT, w)
	assert_eq(w.projectiles.active_count(), 2)
	_run(w, 50)
	var hit_mobs := _hits(w).map(func(e: Dictionary) -> int: return int(e.mob))
	hit_mobs.sort()
	assert_eq(hit_mobs, [first, second], "one bag each, not both at the nearest")
	assert_eq(w.loadout.stats(KEY).count, 2)


func test_a_second_bag_with_one_monster_does_not_double_up_on_it() -> void:
	var w := _world()
	w.loadout.add_skill_mod(KEY, "count", "add", 1.0)
	var only := _mob(w, 100)
	w.runner.step(DT, w)
	_run(w, 50)
	var hits := _hits(w)
	assert_true(hits.all(func(e: Dictionary) -> bool: return int(e.mob) == only))
	assert_true(hits.size() >= 1)


# --- art tiers ---------------------------------------------------------------------------------------------------------

func test_the_ball_and_hit_follow_the_level_nodes_by_art_tier() -> void:
	var w := _world()
	for lv in [1, 10, 11, 20, 21, 30]:
		assert_eq(w.book.visual(KEY, "ball", lv, 1), "Skill.wz/411.img/skill/4111004/level/%d/ball" % lv)
		assert_eq(w.book.visual(KEY, "hit", lv, 1), "Skill.wz/411.img/skill/4111004/level/%d/hit/0" % lv)
	# The resolved paths of a cast, by rank: rank 1 -> Lv4, rank 4 -> Lv15, rank 8 -> Lv30 (tiers 1 / 2 / 3).
	for pair: Array in [[1, 4], [4, 15], [8, 30]]:
		var st := w.loadout.stats(KEY, pair[0])
		assert_eq(String(st.ball), "Skill.wz/411.img/skill/4111004/level/%d/ball" % pair[1])
		assert_eq(String(st.hit), "Skill.wz/411.img/skill/4111004/level/%d/hit/0" % pair[1])
	assert_false(w.book.def(KEY).has("art_by_level"), "SkillBook.visual follows the level nodes: no template needed")
	assert_eq(String(w.book.def(KEY).sounds.use), "Sound.wz/Skill.img/4111004/Use")
	assert_eq(String(w.book.def(KEY).sounds.hit), "Sound.wz/Skill.img/4111004/Hit")


func test_the_thrown_bag_uses_the_ball_of_its_rank_and_does_not_spin() -> void:
	for pair: Array in [[1, 4], [8, 30]]:
		var w := _world(pair[0])
		_mob(w, 100)
		w.runner.step(DT, w)
		var want := w.visual_index("Skill.wz/411.img/skill/4111004/level/%d/ball" % pair[1])
		var seen := 0
		for i in w.projectiles.capacity():
			if w.projectiles.active[i] != 0:
				assert_eq(w.projectiles.visual[i], want, "rank %d throws the Lv%d ball" % pair)
				assert_eq(w.projectiles.rotate[i], 0, "the bag does not spin")
				seen += 1
		assert_eq(seen, 1)


# --- rarity bonuses ----------------------------------------------------------------------------------------------------

func _effects(tier: String) -> Array:
	var out := []
	for bonus: Dictionary in _world().book.def(KEY).rarity_bonuses[tier]:
		out.append_array(bonus.effects)
	return out


func test_the_catalog_lists_the_spec_table_exactly() -> void:
	var bonuses: Dictionary = _world().book.def(KEY).rarity_bonuses
	assert_eq(bonuses.keys(), TIERS)
	var expected := [["meso_up", "Meso Up", [["damage", "mul", 1.2]]], ["claw_booster", "Claw Booster", [["cooldown", "mul", 0.88]]],
		["second_bag", "Second Bag", [["count", "add", 1.0]]], ["second_bag", "Second Bag", [["count", "add", 1.0], ["damage", "mul", 1.2]]]]
	for t in 4:
		assert_eq(bonuses[TIERS[t]].size(), 1, TIERS[t])
		var entry: Dictionary = bonuses[TIERS[t]][0]
		assert_eq([String(entry.id), String(entry.text)], [expected[t][0], expected[t][1]], TIERS[t])
		var got := []
		for effect: Dictionary in entry.effects:
			got.append([String(effect.stat), String(effect.op), float(effect.value)])
		assert_eq(got, expected[t][2], "%s effects" % TIERS[t])
	assert_eq(String(bonuses.legendary[0].id), String(bonuses.unique[0].id), "Legendary shares the Unique's repeat counter")


## Casts in a world with `effects` as skill modifiers against a lone monster that is put back every tick; returns the cast count,
## the damage dealt and the resolved stats.
func _probe(effects: Array, seconds: float) -> Dictionary:
	var w := _world(8)
	var mob := _mob(w, 100)
	var near := _mob(w, -110)
	var x0: float = w.swarm.x[mob]
	for e: Dictionary in effects:
		w.loadout.add_skill_mod(KEY, String(e.stat), String(e.op), float(e.value))
	var dealt := 0
	for tick in int(seconds / DT):
		for slot in [mob, near]:
			w.swarm.hp[slot] = w.swarm.max_hp[slot]
		w.swarm.x[mob] = x0
		w.step(DT, MoveInput.new())
		for ev: Dictionary in w.drain_events():
			if ev.type == "mob_hit" and ev.skill == KEY:
				dealt += int(ev.damage)
	return {"casts": w.runner.casts, "dealt": dealt, "stats": w.loadout.stats(KEY)}


func test_each_rarity_bonus_changes_the_resolved_cast() -> void:
	var base_short := _probe([], 6.0)
	var base_long := _probe([], 30.0)
	var checked := 0
	for tier: String in TIERS:
		for effect: Dictionary in _effects(tier):
			var label := "%s (%s)" % [tier, effect.stat]
			match String(effect.stat):
				"damage":
					var with := _probe([effect], 6.0)
					assert_true(float(with.stats.damage_max) > float(base_short.stats.damage_max), "%s: resolved damage" % label)
					assert_true(int(with.dealt) > int(base_short.dealt), "%s: dealt %d -> %d" % [label, base_short.dealt, with.dealt])
				"cooldown":
					var with := _probe([effect], 30.0)
					assert_true(float(with.stats.cooldown) < float(base_long.stats.cooldown), "%s: resolved cooldown" % label)
					assert_true(int(with.casts) >= int(base_long.casts), "%s: casts %d -> %d" % [label, base_long.casts, with.casts])
				"count":
					var with := _probe([effect], 6.0)
					assert_eq(int(with.stats.count), int(base_short.stats.count) + 1, "%s: resolved count" % label)
					assert_true(int(with.dealt) > int(base_short.dealt), "%s: a second bag lands" % label)
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


func test_a_new_card_is_offered_to_a_night_lord_who_lacks_the_skill() -> void:
	var w := _world()
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	assert_has(w.upgrades.eligible(w), KEY + "_new")


func test_unique_and_legendary_share_a_counter_and_mastery_repeats_shrink() -> void:
	var w := _world()
	w.upgrades.apply(KEY + "_rank", w, "unique")
	w.upgrades.apply(KEY + "_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:second_bag" % KEY]), 2, "one counter for both")
	assert_eq(w.loadout.stats(KEY).count, 1 + 1 + 1 * 1, "the second application adds a full bag at the shrink rule's repeat value")
	# Past the rank cap the Rare card is Mastery: Meso Up x1.2, then x(1 + 0.2 x 0.8) on the repeat.
	var m := _world(8)
	var card := m.upgrades.choice_card(KEY + "_rank", m, "rare")
	assert_eq(card.card_kind, "mastery")
	m.upgrades.apply(KEY + "_rank", m, "rare")
	m.upgrades.apply(KEY + "_rank", m, "rare")
	assert_eq(m.loadout.rank(KEY), 8)
	assert_near(m.loadout.skill_stat(KEY, "damage", 1.0), 1.392, 0.00001, "x1.2 then x1.16")


# --- the data -----------------------------------------------------------------------------------------------------------

func test_the_definition_matches_the_spec_row() -> void:
	var d := _world().book.def(KEY)
	assert_eq([int(d.skill_id), String(d.book), int(d.job), String(d.kind), String(d.slot)], [4111004, "411", 411, "projectile", "active"])
	assert_eq(String(d.damage), "physical")
	assert_eq(d.cast, {"rule": "nearest"})
	assert_eq([float(d.cooldown), float(d.range), float(d.speed), float(d.radius), int(d.pierce)], [3.0, 300.0, 650.0, 10.0, 0])
	assert_eq(d.echo, {"class": "skill"})
	assert_false(d.get("ammo_shot", false), "the bag is the skill's own ball, not a star")
	assert_false(d.has("ranks"), "the default 30-level table: 4 / 8 / 12 / 15 / 19 / 23 / 27 / 30")
	assert_eq(_world().book.max_rank(KEY), 8)


func test_the_pool_offers_the_skill_to_job_412_only() -> void:
	var data := DataRepo.load_all()
	var jobs := JobTree.from_data(data.jobs, data.jobs_survivor)
	assert_true(KEY in jobs.skill_pool(412))
	for job in [212, 112, 312, 512]:
		assert_false(KEY in jobs.skill_pool(job), "job %d" % job)


func test_the_skill_text_names_the_percent_and_says_no_mesos() -> void:
	var w := _world(8)
	var text := SkillText.new(w.book, {})
	var line := text.level_line(KEY, 30, w.loadout.stats(KEY, 8))
	assert_true("342%" in line, line)
	assert_true("costs no mesos" in line, line)
	assert_true("+10% damage per pip held" in line, line)


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/411.img")
	assert_true(img != null, "Skill.wz/411.img is in the cache")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"411": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "claw"
	var node: Dictionary = img.root.skill["4111004"]
	assert_eq(book.max_level(KEY), 30)
	assert_eq(book.max_rank(KEY), 8)
	var expected_money := [180.0, 240.0, 300.0, 345.0, 405.0, 465.0, 525.0, 570.0]
	var expected_percent := [108.0, 144.0, 180.0, 207.0, 243.0, 279.0, 315.0, 342.0]
	for rank_value in range(1, 9):
		var lv: int = LEVELS[rank_value - 1]
		var level: Dictionary = node.level[str(lv)]
		var label := "rank %d (level %d)" % [rank_value, lv]
		assert_eq(book.canonical_level(KEY, rank_value), lv, label)
		assert_false(level.has("damage"), "%s: the WZ carries no damage field" % label)
		var st := lo.stats(KEY, rank_value)
		assert_eq(int(st.level), lv, label)
		assert_eq(float(level.moneyCon), expected_money[rank_value - 1], "%s: tier A moneyCon" % label)
		assert_near(st.damage_pct, float(level.moneyCon) * 0.6 / 100.0, 0.000001, label)
		assert_near(st.damage_percent, expected_percent[rank_value - 1], 0.0001, label)
		assert_eq(st.count, 1, label)
		# The unused fields are really there (and really unused): x 50, prop 1 -> 10, no bulletCount.
		assert_eq(float(level.x), 50.0, label)
		assert_true(float(level.prop) >= 1.0 and float(level.prop) <= 10.0, label)
		assert_false(level.has("bulletCount"), label)
	# Spec rank values at ranks 1 / 4 / 8 as literals.
	for i in 3:
		assert_near(lo.stats(KEY, [1, 4, 8][i]).damage_pct, [1.08, 2.07, 3.42][i], 0.000001)
	lib.free()


func test_real_cache_the_art_tiers_change_at_levels_eleven_and_twenty_one() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/411.img")
	assert_true(img != null)
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"411": img.root})
	var sizes := {}
	var origins := {}
	var first_frames := {}
	for lv in [1, 10, 11, 20, 21, 30]:
		var ball := book.visual(KEY, "ball", lv, 1)
		var anim := lib.anim(ball)
		assert_eq(anim.frame_count(), 4, "Lv%d ball has four frames: %s" % [lv, ball])
		var hit := lib.anim(book.visual(KEY, "hit", lv, 1))
		assert_eq(hit.frame_count(), 3, "Lv%d hit has three frames" % lv)
		var node: Dictionary = img.root.skill["4111004"].level[str(lv)].ball
		sizes[lv] = [int(node["0"]["$canvas"][3]), int(node["0"]["$canvas"][4])]
		origins[lv] = node["0"].origin["$v"]
		first_frames[lv] = JSON.stringify(node["0"]["$canvas"])
	assert_eq(sizes[1], [87, 33])
	assert_eq(sizes[11], [87, 33])
	assert_eq(sizes[21], [91, 34])
	assert_eq([first_frames[1] == first_frames[10], first_frames[11] == first_frames[20], first_frames[21] == first_frames[30]], [true, true, true],
		"one art inside a tier")
	assert_true(first_frames[1] != first_frames[11], "levels 1 and 11 are other art")
	assert_true(first_frames[11] != first_frames[21], "levels 11 and 21 are other art")
	assert_eq(origins[21], [20.0, 18.0], "the third tier's origin")
	# The rank levels land in 1-10 / 11-20 / 21-30: ranks 1-2 tier one, 3-5 tier two, 6-8 tier three.
	var tiers := []
	for rank_value in range(1, 9):
		var lv := book.canonical_level(KEY, rank_value)
		tiers.append(0 if lv <= 10 else 1 if lv <= 20 else 2)
	assert_eq(tiers, [0, 0, 1, 1, 1, 2, 2, 2])
	for suffix: String in ["icon", "iconDisabled", "iconMouseOver"]:
		assert_true(lib.frame(book.wz_path(KEY) + "/" + suffix) != null, suffix)
	for sound: String in book.def(KEY).sounds.values():
		assert_true(lib.sound(sound) != null, "sound %s" % sound)
	assert_eq(Array(lib.missing), [])
	lib.free()
