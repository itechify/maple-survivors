extends TestCase
## The nine job-neutral common passives (ADR 0006, spec #282 ticket #289): data, cards, slots and one effect test per
## passive at ranks 1 and 5. Expected numbers are the spec's per-rank table (tier C), written out as literals.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

## key -> [display name, icon path]; the paths are the T1 (#283) icon table.
const PASSIVES := {
	"might": ["Maple Warrior", "Skill.wz/2112.img/skill/21121000/icon"],
	"max_hp": ["Hyper Body", "Skill.wz/910.img/skill/9101008/icon"],
	"speed": ["Haste", "Skill.wz/910.img/skill/9101001/icon"],
	"regen": ["Recovery", "Skill.wz/1000.img/skill/10001001/icon"],
	"cooldown": ["Spell Booster", "Skill.wz/1210.img/skill/12101004/icon"],
	"area": ["Dragon Roar", "Skill.wz/910.img/skill/9101006/icon"],
	"exp": ["Holy Symbol", "Skill.wz/910.img/skill/9101002/icon"],
	"armor": ["Iron Body", "Skill.wz/1100.img/skill/11001001/icon"],
	"crit": ["Sharp Eyes", "Skill.wz/312.img/skill/3121002/icon"],
}


## The skill key of common passive `name`.
func _key(name: String) -> String:
	return "passive_" + name


## A quiet world holding `name` at `rank` (the cards applied one by one, as the draw does).
func _world_with(name: String, rank: int) -> RunWorld:
	var w := RF.quiet_world()
	_take(w, name, rank)
	return w


func _take(w: RunWorld, name: String, rank: int) -> void:
	if rank <= 0:
		return
	for i in rank:
		w.upgrades.apply(_key(name) + ("_new" if i == 0 else "_rank"), w, "legendary")


func test_nine_passives_are_defined_with_five_ranks_names_and_icons() -> void:
	var data := DataRepo.load_all()
	var book := SkillBook.from_data(data.skills, RF.skill_imgs())
	for name: String in PASSIVES:
		var key := _key(name)
		assert_true(book.has(key), key)
		assert_eq(book.slot(key), "passive", key)
		assert_true(bool(book.def(key).get("common_passive", false)), key)
		assert_eq(book.max_rank(key), 5, key)
		assert_eq(String(book.def(key).name), PASSIVES[name][0], key)
		assert_eq(String(book.def(key).icon), PASSIVES[name][1], key)
		assert_eq(book.wz_path(key) + "/icon", PASSIVES[name][1], "the icon follows the id and book: " + key)


func test_every_passive_offers_a_new_and_a_rank_card_that_is_always_normal_plus_one() -> void:
	var w := RF.quiet_world()
	for name: String in PASSIVES:
		var key := _key(name)
		assert_has(w.upgrades.eligible(w), key + "_new")
		assert_false(key + "_rank" in w.upgrades.eligible(w), "rank cards wait for the skill: " + key)
		var c := w.upgrades.choice_card(key + "_new", w, "legendary")
		assert_eq(c.tier, "normal", key)
		assert_eq(c.magnitude, 1, key)
		assert_eq(c.card_kind, "new_passive", key)
	assert_eq(w.upgrades.apply("passive_might_new", w, "legendary"), 1)
	assert_eq(w.loadout.rank("passive_might"), 1)
	assert_eq(w.loadout.slot_count("passive"), 1)


func test_the_sixth_passive_closes_new_passives_but_owned_ranks_keep_coming_to_rank_five() -> void:
	var w := RF.quiet_world()
	var names := PASSIVES.keys()
	for i in 6:
		w.upgrades.apply(_key(names[i]) + "_new", w)
	for i in range(6, 9):
		assert_false(_key(names[i]) + "_new" in w.upgrades.eligible(w), names[i])
		assert_eq(w.upgrades.apply(_key(names[i]) + "_new", w), 0)
	var held := _key(names[0])
	for i in 4:
		assert_has(w.upgrades.eligible(w), held + "_rank")
		w.upgrades.apply(held + "_rank", w, "legendary")
		assert_eq(w.upgrades.choice_card(held + "_rank", w, "legendary").tier, "normal")
	assert_eq(w.loadout.rank(held), 5)
	assert_false(held + "_rank" in w.upgrades.eligible(w), "rank 5 is the cap")


func test_passives_never_roll_rarity_in_a_seeded_draw() -> void:
	var w := RF.quiet_world()
	for name: String in ["might", "crit"]:
		w.upgrades.apply(_key(name) + "_new", w)
	var rng := RandomNumberGenerator.new()
	rng.seed = 289
	w.player_state["fortune"] = 500.0
	var seen_passive := 0
	for i in 600:
		for c in w.upgrades.roll_choices(w, rng):
			if c.card_kind in ["new_passive", "passive_rank"]:
				seen_passive += 1
				assert_eq(c.tier, "normal", String(c.id))
				assert_eq(c.magnitude, 1, String(c.id))
	assert_true(seen_passive > 100, "the draw did offer passives")


# --- effects: ranks 1 and 5 (+10% per rank is +10% and +50%, additive across ranks) ---

func test_might_adds_ten_percent_damage_per_rank() -> void:
	var base := _world_with("crit", 0).loadout.stats("energy_bolt")
	for rank: int in [1, 5]:
		var st := _world_with("might", rank).loadout.stats("energy_bolt")
		var k := 1.0 + 0.10 * rank
		assert_true(absf(st.damage_max - base.damage_max * k) < 1e-6, "max at rank %d" % rank)
		assert_true(absf(st.damage_min - base.damage_min * k) < 1e-6, "min at rank %d" % rank)


func test_max_hp_adds_twenty_percent_per_rank_and_grants_the_new_hp() -> void:
	var base := _world_with("crit", 0)
	var m0 := int(base.player_state.max_hp)
	for rank: int in [1, 5]:
		var w := _world_with("max_hp", rank)
		assert_eq(int(w.player_state.max_hp), roundi(m0 * (1.0 + 0.20 * rank)), "rank %d" % rank)
		assert_eq(int(w.player_state.hp), int(w.player_state.max_hp), "a full bar stays full as the maximum grows")


func test_speed_adds_ten_percent_per_rank() -> void:
	assert_eq(roundi(_world_with("crit", 0).player_speed_stat()), 100)
	assert_eq(roundi(_world_with("speed", 1).player_speed_stat()), 110)
	var w := _world_with("speed", 5)
	assert_eq(roundi(w.player_speed_stat()), 150)
	assert_eq(w.player.speed_stat, 150, "the movement model gets it")


func _hp_gained_over(w: RunWorld, seconds: float) -> float:
	w.take_hit(30.0, false, "", w.player.pos - Vector2(10, 0))
	var hp0 := float(w.player_state.hp)
	for i in roundi(seconds / DT):
		w.step(DT, MoveInput.new())
	return float(w.player_state.hp) - hp0


func test_regen_heals_one_percent_of_max_hp_per_second_per_rank() -> void:
	# 8 s sits between the base 10 s pulses, so only the passive heals. Max HP is 50 at Lv1.
	assert_true(absf(_hp_gained_over(_world_with("crit", 0), 8.0)) < 0.01)
	assert_true(absf(_hp_gained_over(_world_with("regen", 1), 8.0) - 4.0) < 0.5)
	assert_true(absf(_hp_gained_over(_world_with("regen", 5), 8.0) - 20.0) < 0.5)


func test_cooldown_multiplies_by_one_minus_eight_percent_per_rank_with_a_floor_of_035() -> void:
	var c0: float = _world_with("crit", 0).loadout.stats("energy_bolt").cooldown
	assert_true(absf(_world_with("cooldown", 1).loadout.stats("energy_bolt").cooldown - c0 * 0.92) < 1e-6)
	assert_true(absf(_world_with("cooldown", 5).loadout.stats("energy_bolt").cooldown - c0 * 0.60) < 1e-6)
	var w := _world_with("cooldown", 5)
	w.loadout.add_skill_mod("energy_bolt", "cooldown", "mul", 0.4) # 0.4 x 0.6 would be 0.24 of the base
	assert_true(absf(w.loadout.stats("energy_bolt").cooldown - c0 * 0.35) < 1e-6, "the factor stops at x0.35")
	assert_true(absf(w.loadout.stats("teleport_fp").cooldown - _world_with("crit", 0).loadout.stats("teleport_fp").cooldown) < 1e-6,
		"Teleport is not a cast")


func test_area_adds_ten_percent_per_rank() -> void:
	var a0: float = _world_with("crit", 0).loadout.stats("energy_bolt").area
	assert_true(absf(_world_with("area", 1).loadout.stats("energy_bolt").area - a0 * 1.1) < 1e-6)
	assert_true(absf(_world_with("area", 5).loadout.stats("energy_bolt").area - a0 * 1.5) < 1e-6)


func test_exp_adds_eight_percent_per_rank_without_losing_the_fraction() -> void:
	for rank_expected in [[0, 100], [1, 108], [5, 140]]:
		var w := _world_with("crit", 0) if rank_expected[0] == 0 else _world_with("exp", rank_expected[0])
		w.progression.level = 30 # far from a level-up
		var before := w.progression.exp
		for i in 100:
			w._gain_exp(1)
		assert_eq(w.progression.exp - before, rank_expected[1], "100 one-EXP orbs at rank %d" % rank_expected[0])


func test_armor_takes_two_flat_per_rank_off_every_hit_but_never_below_one() -> void:
	var raw := _world_with("crit", 0).take_hit(40.0, false, "", Vector2.ZERO)
	assert_true(raw > 12, "the hit is big enough to show the reduction")
	assert_eq(_world_with("armor", 1).take_hit(40.0, false, "", Vector2.ZERO), raw - 2)
	assert_eq(_world_with("armor", 5).take_hit(40.0, false, "", Vector2.ZERO), raw - 10)
	assert_eq(_world_with("armor", 5).take_hit(40.0, true, "", Vector2.ZERO),
		_world_with("crit", 0).take_hit(40.0, true, "", Vector2.ZERO) - 10, "magic hits too")
	assert_eq(_world_with("armor", 5).take_hit(3.0, false, "", Vector2.ZERO), 1)


func test_crit_adds_five_percent_chance_per_rank() -> void:
	var c0: float = _world_with("crit", 0).loadout.stats("energy_bolt").crit
	assert_true(absf(_world_with("crit", 1).loadout.stats("energy_bolt").crit - (c0 + 0.05)) < 1e-6)
	assert_true(absf(_world_with("crit", 5).loadout.stats("energy_bolt").crit - (c0 + 0.25)) < 1e-6)


# --- windows ---

func test_the_skill_window_has_a_common_tab_with_the_nine_passives_and_their_ranks() -> void:
	var w := _world_with("might", 3)
	_take(w, "crit", 1)
	var text := SkillText.new(w.book)
	var m := SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 212, text)
	assert_eq(m.tabs[0].name, "Common")
	assert_eq(m.tabs[0].tier, 0)
	assert_eq(m.tabs[m.tabs.size() - 1].job_id, 212, "the window still opens on the job's own tab")
	var rows: Array = m.tabs[0].rows
	assert_eq(rows.size(), 9)
	var by_name := {}
	for r: Dictionary in rows:
		by_name[r.name] = r
	assert_eq(by_name["Maple Warrior"].level, 3)
	assert_eq(by_name["Maple Warrior"].max_level, 5)
	assert_true(by_name["Maple Warrior"].learned)
	assert_eq(by_name["Sharp Eyes"].level, 1)
	assert_eq(by_name["Iron Body"].level, 0)
	assert_false(by_name["Iron Body"].learned)
	var tip := m.skill_tooltip("passive_might")
	assert_eq(tip.current, "Damage +30%")
	assert_eq(tip.next, "Damage +40%")
	assert_eq(m.skill_tooltip("passive_armor").next, "Damage taken -2 per hit")


func test_held_common_passives_list_name_icon_and_rank_in_learning_order() -> void:
	var w := RF.quiet_world()
	assert_eq(w.loadout.held_common_passives(), [])
	_take(w, "crit", 2)
	_take(w, "might", 1)
	var held := w.loadout.held_common_passives()
	assert_eq(held.size(), 2)
	assert_eq(held[0], {"key": "passive_crit", "name": "Sharp Eyes", "icon": PASSIVES.crit[1], "rank": 2, "max_rank": 5})
	assert_eq(held[1].name, "Maple Warrior")


func test_the_stat_window_lists_the_passives_held_with_their_ranks() -> void:
	var w := _world_with("might", 2)
	var sw := StatWindow.new({"passives": w.loadout.held_common_passives()})
	assert_eq(sw.passive_texts(), PackedStringArray(["Maple Warrior  2/5"]))
	sw.set_info({})
	assert_eq(sw.passive_texts(), PackedStringArray())
	sw.free()


# --- bot ---

func test_the_sensible_bot_ranks_passives_below_pool_attacks_and_by_usefulness() -> void:
	var w := RF.quiet_world()
	var offer := func(ids: Array) -> Array:
		var out: Array = []
		for id: String in ids:
			out.append(w.upgrades.choice_card(id, w))
		return out
	assert_eq(BotInput.pick_card_for(w, offer.call(["passive_exp_new", "passive_might_new", "passive_speed_new"])),
		"passive_might_new")
	assert_eq(BotInput.pick_card_for(w, offer.call(["passive_might_new", "magic_claw_new", "passive_cooldown_new"])),
		"magic_claw_new", "a new pool attack beats every passive")
	assert_eq(BotInput.pick_card_for(w, offer.call(["passive_might_new", "energy_bolt_rank"])), "energy_bolt_rank",
		"so does an attack rank")
	var order := ["might", "cooldown", "crit", "max_hp", "area", "armor", "regen", "speed", "exp"]
	var last := INF
	for name: String in order:
		var s := BotInput.card_score(w, w.upgrades.choice_card(_key(name) + "_new", w))
		assert_true(s < last and s > 0.0, name)
		last = s
	_take(w, "might", 1)
	assert_true(BotInput.card_score(w, w.upgrades.choice_card("passive_might_rank", w))
		< BotInput.card_score(w, w.upgrades.choice_card("passive_might_new", RF.quiet_world())), "rank scores 4 less")
