extends TestCase
## Heal as a Bishop pool skill (spec #372, ticket BS4 #376): the port into the `bishop` line (default eight ranks, rarity
## bonuses, no legacy cards), the two new modifier stats `heal_power` and `heal_threshold`, the resolved `damage` on the
## undead strike, and the proof that every rarity entry changes the resolved cast. Seeded RNG, fixed 1/60 s ticks, synthetic
## Skill.wz levels (HF.levels); the real-cache test reads Skill.wz itself and SKIPs without the cache.

const HF := preload("res://tests/fixtures/heal_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const TIERS := ["rare", "epic", "unique", "legendary"]
## The spec's table: tier -> [id, [[stat, op, value]...]] (Legendary shares Holy Smite's id and counter).
const BONUSES := {
	"rare": ["restore", [["heal_power", "mul", 1.2]]],
	"epic": ["mending", [["heal_threshold", "add", 0.15]]],
	"unique": ["smite", [["damage", "mul", 1.5], ["area", "mul", 1.2]]],
	"legendary": ["smite", [["damage", "mul", 1.5], ["area", "mul", 1.2], ["heal_power", "mul", 1.2]]],
}


func _skill_file(line: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivor/skills/%s.json" % line))
	return parsed.skills if parsed is Dictionary else {}


# --- the port ---------------------------------------------------------------------------------------------------------


func test_heal_lives_in_the_bishop_line_and_not_in_magician_json() -> void:
	assert_true(_skill_file("bishop").has("heal"), "skills/bishop.json holds Heal")
	assert_false(_skill_file("magician").has("heal"), "it left skills/magician.json (a key in two files is a load error)")
	var heal: Dictionary = DataRepo.load_all().skills.skills.heal
	assert_eq([int(heal.skill_id), String(heal.book), int(heal.job)], [2301002, "230", 230])


func test_the_definition_keeps_the_shipped_rule_and_drops_the_explicit_ranks() -> void:
	var d: Dictionary = DataRepo.load_all().skills.skills.heal
	assert_false(d.has("ranks"), "the default 30-level table: eight ranks")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "none")
	assert_eq(String(d.kind), "instant")
	assert_eq(d.cast, {"rule": "hp_or_undead"})
	assert_eq(d.heal, {"field": "hp", "hp_threshold": 0.5, "recast_delay": 2.0}, "formulas, 2.0 s recast and half-HP trigger unchanged")
	assert_eq(String(d.action), "alert2")
	assert_eq(String(d.effect), "Skill.wz/230.img/skill/2301002/effect")
	assert_eq(String(d.hit), "Skill.wz/230.img/skill/2301002/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/2301002/Use")


func test_the_four_rarity_lists_are_the_spec_table() -> void:
	var lists: Dictionary = DataRepo.load_all().skills.skills.heal.rarity_bonuses
	for tier: String in TIERS:
		var entries: Array = lists[tier]
		assert_eq(entries.size(), 1, tier)
		assert_eq(String(entries[0].id), BONUSES[tier][0], "%s id" % tier)
		var want: Array = []
		for e: Array in BONUSES[tier][1]:
			want.append({"stat": e[0], "op": e[1], "value": e[2]})
		assert_eq(entries[0].effects.size(), want.size(), "%s effect count" % tier)
		for i in want.size():
			assert_eq(String(entries[0].effects[i].stat), want[i].stat, "%s stat %d" % [tier, i])
			assert_eq(String(entries[0].effects[i].op), want[i].op, "%s op %d" % [tier, i])
			assert_near(float(entries[0].effects[i].value), float(want[i].value), 1e-9, "%s value %d" % [tier, i])
	assert_eq(lists.legendary[0].id, lists.unique[0].id, "Legendary shares Holy Smite's repeat counter")


func test_the_legacy_heal_cards_are_deleted() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/survivor/upgrades/magician.json"))
	for c: Dictionary in parsed.cards:
		assert_false(String(c.id).begins_with("heal_"), "%s: Heal is a pool skill, its cards are generated" % c.id)
	var w := HF.world(1)
	assert_eq(w.upgrades.card("heal_new").get("kind"), "skill_new", "the new and rank cards come from the pool")
	assert_eq(w.upgrades.card("heal_rank").get("kind"), "skill_rank")


func test_heal_has_eight_ranks_mapped_to_the_wz_levels() -> void:
	var w := HF.world(1)
	assert_eq(w.book.max_rank("heal"), 8)
	for rank in range(1, 9):
		w.loadout.set_rank("heal", rank)
		assert_eq(w.loadout.stats("heal").level, HF.RANK_LEVELS[rank - 1], "rank %d" % rank)
		assert_near(w.book.canonical("heal", HF.RANK_LEVELS[rank - 1], "hp"), 10.0 * HF.RANK_LEVELS[rank - 1], 1e-9)


func test_the_box_steps_up_at_level_16_so_ranks_five_to_eight_use_the_large_one() -> void:
	var w := HF.world(1)
	for rank in range(1, 9):
		w.loadout.set_rank("heal", rank)
		var box: Rect2 = w.loadout.stats("heal").box
		var half := 300.0 if rank >= 5 else 250.0
		assert_eq(box.position.x, -half, "rank %d half width" % rank)
		assert_eq(box.size.x, 2.0 * half, "rank %d width" % rank)


# --- the new stats: defaults leave the shipped cast as it was -----------------------------------------------------------


func test_new_stats_default_to_one_and_the_data_threshold() -> void:
	var st := HF.world(8).loadout.stats("heal")
	assert_eq(st.heal_power, 1.0)
	assert_eq(st.heal_threshold, 0.5)


func test_defaults_reproduce_the_shipped_formulas() -> void:
	# The pre-port numbers: the damage multiplier is exactly 1.0 (the strike keeps CombatMath.heal_damage_range's bounds) and the
	# recovery is CombatMath.heal_recovery_range with the canonical hp. This is what keeps the pinned oracle byte-identical.
	var w := HF.world(8)
	assert_eq(w.loadout.stats("heal").status_damage_mult, 1.0)
	HF.set_hp(w, 100.0)
	HF.put_undead(w, 60.0)
	HF.put_undead(w, 100.0)
	var result := HF.cast(w)
	assert_true(result.fired)
	assert_eq(result.damages.size(), 2)
	var luk := float(w.player_state.luk)
	var want := CombatMath.heal_damage_range(w.loadout.int_stat, luk, w.loadout.matk, 300.0, 3)
	for d: int in result.damages:
		assert_between(float(d), floorf(want.x) - 1.0, ceilf(want.y * w.loadout.stats("heal").crit_mult) + 1.0)
	var range_ := CombatMath.heal_recovery_range(w.loadout.int_stat, luk, w.loadout.matk, 300.0)
	assert_between(result.restored, floori(range_.x) - 1, floori(range_.y))


func test_the_pinned_pre_port_definition_resolves_to_the_defaults() -> void:
	# test_tick_cost_identity keeps the pre-#376 Heal (thirty explicit ranks, no bonuses). With it every new stat is at the value
	# that leaves the oracle's bytes alone: the level is the rank, heal_power 1.0, the threshold the data's 0.5, damage x1.0.
	var d := HF.data()
	d.skills.skills.heal.ranks = range(1, 31)
	d.skills.skills.heal.erase("rarity_bonuses")
	for rank in [1, 15, 30]:
		var st := HF.world(rank, 376, d).loadout.stats("heal")
		assert_eq(st.level, rank)
		assert_eq(st.heal_power, 1.0)
		assert_eq(st.heal_threshold, 0.5)
		assert_eq(st.status_damage_mult, 1.0)


# --- heal_power -------------------------------------------------------------------------------------------------------


func _restored_with(effects: Array, p_seed := 7, hp := 100.0) -> int:
	var w := HF.world(8, p_seed)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod("heal", String(e.stat), String(e.op), float(e.value))
	HF.set_hp(w, hp)
	return int(HF.cast(w).restored)


func test_heal_power_scales_both_bounds_of_the_recovery() -> void:
	var power := {"stat": "heal_power", "op": "mul", "value": 1.2}
	var w := HF.world(8)
	var base := CombatMath.heal_recovery_range(w.loadout.int_stat, float(w.player_state.luk), w.loadout.matk, 300.0)
	w.loadout.add_skill_mod("heal", "heal_power", "mul", 1.2)
	assert_near(w.loadout.stats("heal").heal_power, 1.2, 1e-6)
	for seed_ in range(1, 9):
		var plain := _restored_with([], seed_)
		var boosted := _restored_with([power], seed_)
		# The same seed rolls the same fraction of the range, so the boosted roll is the plain one x1.2 (floored).
		assert_true(boosted > plain, "seed %d: %d -> %d" % [seed_, plain, boosted])
		assert_between(boosted, floori(base.x * 1.2) - 1, floori(base.y * 1.2))
		assert_between(float(boosted), float(plain) * 1.2 - 1.5, float(plain) * 1.2 + 1.5)


func test_heal_power_adds_up_across_cards_and_never_touches_the_undead_strike() -> void:
	var w := HF.world(8)
	w.loadout.add_skill_mod("heal", "heal_power", "mul", 1.2)
	w.loadout.add_skill_mod("heal", "heal_power", "mul", 1.2)
	assert_near(w.loadout.stats("heal").heal_power, 1.44, 1e-5)
	var plain := HF.world(8)
	for world: RunWorld in [w, plain]:
		HF.set_hp(world, 1000.0)
		HF.put_undead(world, 50.0)
	assert_eq(HF.cast(w).damages, HF.cast(plain).damages, "heal_power is the recovery only")


# --- heal_threshold ---------------------------------------------------------------------------------------------------


func test_heal_threshold_adds_to_the_data_value_and_is_capped_at_0_95() -> void:
	var w := HF.world(8)
	w.loadout.add_skill_mod("heal", "heal_threshold", "add", 0.15)
	assert_near(w.loadout.stats("heal").heal_threshold, 0.65, 1e-6)
	w.loadout.add_skill_mod("heal", "heal_threshold", "add", 0.9)
	assert_eq(w.loadout.stats("heal").heal_threshold, 0.95, "capped")


func test_a_hit_exactly_at_the_threshold_does_not_admit_and_the_three_readers_agree() -> void:
	# Exclusive: HP strictly below max x threshold. has_target, admission and resolution (the restore) all read the same
	# resolved value, with and without Mending Touch.
	for mending: bool in [false, true]:
		var threshold := 0.65 if mending else 0.5
		for delta: float in [-1.0, 0.0, 1.0]:
			var w := HF.world(8)
			if mending:
				w.loadout.add_skill_mod("heal", "heal_threshold", "add", 0.15)
			var hp := float(HF.MAX_HP) * threshold + delta
			HF.set_hp(w, hp)
			var st := w.runner.stats_of(w, "heal")
			var origin := w.cast_origin()
			var below := delta < 0.0
			var label := "mending %s, HP %d of %d" % [mending, int(hp), HF.MAX_HP]
			assert_eq(w.runner.has_target(w, "heal", st, origin), below, "has_target: " + label)
			assert_eq(not w.runner._admit_cast(w, "heal", st, origin).is_empty(), below, "admission: " + label)
			var result := HF.cast(w)
			assert_eq(result.fired, below, "cast: " + label)
			assert_eq(result.restored > 0, below, "resolution restores: " + label)


func test_an_undead_strike_above_the_threshold_does_not_heal() -> void:
	# 70% HP with an undead in the box: the cast fires for the strike; the recovery is for the injured only.
	var w := HF.world(8)
	HF.set_hp(w, 700.0)
	var undead := HF.put_undead(w, 80.0)
	var result := HF.cast(w)
	assert_true(result.fired)
	assert_eq(result.restored, 0)
	assert_eq(result.hits.size(), 1)
	assert_eq(result.hits[0].slot, undead)
	assert_eq(int(w.player_state.hp), 700)


func test_resolution_agrees_with_admission_when_the_threshold_card_makes_a_non_undead_cast_possible() -> void:
	var w := HF.world(8)
	HF.set_hp(w, 600.0)
	assert_false(HF.cast(w).fired, "60% HP is above the data's half")
	w.loadout.add_skill_mod("heal", "heal_threshold", "add", 0.15)
	w.runner.cooldowns["heal"] = 0.0
	var result := HF.cast(w)
	assert_true(result.fired, "Mending Touch: below 65%")
	assert_true(result.restored > 0)


# --- the damage fix ---------------------------------------------------------------------------------------------------


func _strike_damage(mods: Array, player_mods: Array = []) -> int:
	var w := HF.world(8)
	w.loadout.set_caster(200.0, 100.0, 70) # a big caster: lines large enough that rounding does not hide a ratio
	for m: Array in mods:
		w.loadout.add_skill_mod("heal", m[0], m[1], m[2])
	for m: Array in player_mods:
		w.loadout.add_player_mod(m[0], m[1], m[2])
	HF.set_hp(w, 1000.0)
	HF.put_undead(w, 50.0)
	var result := HF.cast(w)
	assert_eq(result.damages.size(), 1)
	return int(result.damages[0])


func test_the_undead_strike_multiplies_its_bounds_by_the_resolved_damage() -> void:
	# The same seed rolls the same fraction of the bounds, so x1.5 on the bounds is x1.5 on the line.
	var base := _strike_damage([])
	assert_true(base > 20, "a line big enough to compare (%d)" % base)
	assert_between(float(_strike_damage([["damage", "mul", 1.5]])), float(base) * 1.5 - 1.5, float(base) * 1.5 + 1.5)


func test_a_player_wide_damage_stat_reaches_the_strike_like_any_skill() -> void:
	var base := _strike_damage([])
	assert_between(float(_strike_damage([], [["damage", "mul", 1.25]])), float(base) * 1.25 - 1.5, float(base) * 1.25 + 1.5)


func test_normal_mastery_on_heal_is_cooldown_x0_95_and_leaves_damage_alone() -> void:
	var w := HF.world(8)
	var before := w.loadout.stats("heal")
	assert_near(SkillRunner.restart_cooldown(before), 2.0, 1e-6)
	var offered := w.upgrades.choice_card("heal_rank", w, "normal")
	assert_eq(offered.card_kind, "mastery")
	assert_true(offered.skill_mod_changes.has("cooldown"), "the card previews a cooldown")
	w.upgrades.apply("heal_rank", w, "normal")
	assert_near(SkillRunner.restart_cooldown(w.loadout.stats("heal")), 1.9, 1e-3)
	assert_eq(w.loadout.skill_stat("heal", "damage", 1.0), 1.0)
	assert_eq(w.loadout.rank("heal"), 8)


func test_area_widens_the_undead_box() -> void:
	# Rank 1 box is 250 px a side; Holy Smite's x1.2 reaches 300.
	var plain := HF.world(1)
	var wide := HF.world(1)
	wide.loadout.add_skill_mod("heal", "area", "mul", 1.2)
	var results: Array = []
	for w: RunWorld in [plain, wide]:
		HF.set_hp(w, 1000.0)
		HF.put_undead(w, 275.0)
		results.append(HF.cast(w))
	assert_false(results[0].fired, "275 px is outside the 250 px box")
	assert_true(results[1].fired)
	assert_eq(results[1].hits.size(), 1)


func test_the_strike_hits_every_undead_in_the_box_bosses_first_and_never_a_living_mob() -> void:
	var w := HF.world(8)
	HF.set_hp(w, 1000.0)
	var living := RF.put_mob(w, 100100, w.player.pos.x + 30.0, 190.0, 100000.0)
	var slots: Array[int] = []
	for i in 8:
		slots.append(HF.put_undead(w, 40.0 + 25.0 * i))
	w.mob_boss[slots[7]] = 0
	var result := HF.cast(w)
	assert_eq(result.hits.size(), 8, "no six-target cap")
	assert_eq(result.hits[0].slot, slots[7], "the scheduled boss first")
	for h: Dictionary in result.hits:
		assert_ne(h.slot, living)


func test_hidden_admits_only_the_healing() -> void:
	var w := HF.world(8)
	assert_true(w.start_buff("synthetic_hide", {"skill_id": 9991001, "level": 1, "icon": "", "duration": 4.0, "buff_stat": "",
		"buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}}))
	w.loadout.set_caster(50.0, 23.0, 70) # starting a buff refreshes the character's stats
	HF.set_hp(w, 1000.0)
	HF.put_undead(w, 50.0)
	assert_false(HF.cast(w).fired, "an undead strike is an attack: Hidden refuses it")
	HF.set_hp(w, 100.0)
	w.runner.cooldowns["heal"] = 0.0
	var result := HF.cast(w)
	assert_true(result.fired, "healing still admits")
	assert_eq(result.hits.size(), 0)
	assert_true(result.restored > 0)


# --- every rarity entry changes the resolved cast ---------------------------------------------------------------------


## What the cast does with `effects` applied to a fresh world, probed for the stat's own symptom.
func _probe(effects: Array, stat: String) -> Dictionary:
	var w := HF.world(1 if stat == "area" else 8)
	for e: Dictionary in effects:
		w.loadout.add_skill_mod("heal", String(e.stat), String(e.op), float(e.value))
	match stat:
		"heal_threshold":
			HF.set_hp(w, 600.0) # 60%: below Mending's 65%, above the data's 50%
		"area":
			HF.set_hp(w, 1000.0)
			HF.put_undead(w, 275.0) # past the rank-1 box (250 px), inside x1.2
		"damage":
			HF.set_hp(w, 1000.0)
			HF.put_undead(w, 50.0)
		_:
			HF.set_hp(w, 100.0)
	var result := HF.cast(w)
	var damage := 0
	for d: int in result.damages:
		damage = maxi(damage, d)
	return {"fired": result.fired, "restored": result.restored, "hits": result.hits.size(), "damage": damage}


func test_every_rarity_effect_changes_the_resolved_cast() -> void:
	var lists: Dictionary = DataRepo.load_all().skills.skills.heal.rarity_bonuses
	for tier: String in TIERS:
		for effect: Dictionary in lists[tier][0].effects:
			var stat := String(effect.stat)
			var label := "%s %s" % [tier, stat]
			var base := _probe([], stat)
			var with := _probe([effect], stat)
			match stat:
				"heal_power":
					assert_true(int(with.restored) > int(base.restored), "%s: recovery %d -> %d" % [label, base.restored, with.restored])
				"heal_threshold":
					assert_false(bool(base.fired), label + ": 60% HP does not cast at the base threshold")
					assert_true(bool(with.fired) and int(with.restored) > 0, label + ": it heals below 65%")
				"damage":
					assert_true(int(with.damage) > int(base.damage), "%s: strike %d -> %d" % [label, base.damage, with.damage])
				"area":
					assert_eq(int(base.hits), 0, label + ": the undead past the base box is not struck")
					assert_eq(int(with.hits), 1, label + ": it is inside the widened box")


func test_normal_mastery_cooldown_changes_the_casts_in_a_minute() -> void:
	var counts: Array = []
	for mastery: bool in [false, true]:
		var w := HF.world(8)
		if mastery:
			w.loadout.add_skill_mod("heal", "cooldown", "mul", 0.95)
		for tick in 3960:
			HF.set_hp(w, 100.0)
			w.runner.step(HF.DT, w)
			w.drain_events()
		counts.append(w.runner.casts)
	assert_true(int(counts[1]) > int(counts[0]), "casts in 66 s: %s" % [counts])


func test_cards_offer_and_apply_each_tier_and_legendary_shares_the_unique_counter() -> void:
	for tier: String in TIERS:
		var w := HF.world(3)
		var offered := w.upgrades.choice_card("heal_rank", w, tier)
		assert_false(offered.get("rarity_bonus", {}).is_empty(), "%s offers a bonus" % tier)
		assert_false(offered.skill_mod_changes.is_empty(), "%s previews the change" % tier)
		w.upgrades.apply("heal_rank", w, tier)
		assert_eq(w.loadout.rank("heal"), 4, "%s: one rank" % tier)
		assert_false(w.loadout.skill_mods.get("heal", {}).is_empty(), "%s applied the bonus" % tier)
	var epic := HF.world(3)
	var card := epic.upgrades.choice_card("heal_rank", epic, "epic")
	assert_eq(card.skill_mod_changes.get("heal_threshold"), {"before": 50, "after": 65}, "Mending Touch previews 50% -> 65%")
	var rare := HF.world(3)
	var power := rare.upgrades.choice_card("heal_rank", rare, "rare")
	assert_eq(power.skill_mod_changes.get("heal_power"), {"before": 100, "after": 120}, "Greater Heal previews 100% -> 120%")
	var shared := HF.world(3)
	shared.upgrades.apply("heal_rank", shared, "unique")
	shared.upgrades.apply("heal_rank", shared, "legendary")
	assert_eq(int(shared.loadout.card_ranks["bonus:heal:smite"]), 2, "one counter for Unique and Legendary")


func test_the_skill_window_line_names_the_resolved_threshold() -> void:
	var w := HF.world(4)
	var text := SkillText.new(w.book, {})
	assert_true("Restores HP below 50% health; strikes undead in the area" in text.level_line("heal", 15, w.loadout.stats("heal")))
	w.upgrades.apply("heal_rank", w, "epic")
	assert_true("Restores HP below 65% health" in text.level_line("heal", 19, w.loadout.stats("heal")))


# --- real cache -------------------------------------------------------------------------------------------------------


func test_real_cache_the_mapped_hp_and_box_of_all_eight_ranks() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var root: Dictionary = lib.img("Skill.wz/230.img").root
	var node: Dictionary = root.skill["2301002"]
	assert_eq(node.level.size(), 30)
	var w := HF.world(1, 376, {}, root)
	for rank in range(1, 9):
		w.loadout.set_rank("heal", rank)
		var st := w.loadout.stats("heal")
		var level: int = HF.RANK_LEVELS[rank - 1]
		assert_eq(st.level, level, "rank %d" % rank)
		var wz: Dictionary = node.level[str(level)]
		assert_near(w.book.canonical("heal", level, "hp"), float(wz.hp), 1e-9, "rank %d hp" % rank)
		assert_eq(float(wz.hp), 10.0 * level, "rank %d: hp is 10 x level" % rank)
		var lt: Array = wz.lt["$v"]
		var rb: Array = wz.rb["$v"]
		assert_eq(st.box, Rect2(Vector2(lt[0], lt[1]), Vector2(float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1]))), "rank %d box" % rank)
		assert_eq(float(st.box.end.x), 300.0 if level >= 16 else 250.0, "rank %d half width" % rank)
	assert_true(lib.anim(String(w.book.def("heal").effect)) != null)
	assert_true(lib.anim(String(w.book.def("heal").hit)) != null)
	assert_true(lib.anim("Skill.wz/230.img/skill/2301002/affected") != null)
	assert_true(lib.frame(String(w.book.def("heal").icon)) != null)
	assert_true(lib.sound(String(w.book.def("heal").sounds.use)) != null)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
