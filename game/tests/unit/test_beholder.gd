extends TestCase
## Dark Knight's Beholder (1321007, spec #348 D9 #357) with its sub-skills Aura (1320008) and Hex (1320009) on the
## support-summon seam (D4, SupportSummons): the level-10 rank table, the eight ranks through the sub-skills' own tables,
## the 60 s life and 45 s cooldown, the exact unlocked Hex stats, the rarity cards and the real Skill.wz rows. Synthetic
## Skill.wz rows carry the D1-verified numbers at the eight mapped levels; the real-cache tests at the end read the real rows.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "beholder"
const AURA := "aura_of_the_beholder"
const HEX := "hex_of_the_beholder"
## Rank -> the WZ level each skill reads (spec DK-4, DK-11).
const BEHOLDER_LEVELS := [2, 3, 4, 5, 7, 8, 9, 10]
const SUB_LEVELS := [4, 7, 10, 13, 16, 19, 22, 25]
## Aura at the eight sub levels (D1): canonical `hp` (flat) and `x` (seconds between pulses).
const AURA_HP := [85, 170, 200, 280, 360, 390, 470, 500]
const AURA_X := [10, 9, 8, 7, 7, 6, 5, 4]
## Hex at the eight sub levels (D1): the stats the level has (WZ names), `time` and `x`.
const HEX_ROWS := [
	{"pdd": 20, "time": 20, "x": 42},
	{"pdd": 40, "mdd": 25, "time": 40, "x": 36},
	{"pdd": 40, "mdd": 25, "time": 40, "x": 30},
	{"pdd": 60, "mdd": 50, "acc": 10, "time": 60, "x": 24},
	{"pdd": 80, "mdd": 75, "acc": 20, "eva": 30, "time": 80, "x": 18},
	{"pdd": 80, "mdd": 75, "acc": 20, "eva": 30, "time": 80, "x": 12},
	{"pdd": 100, "mdd": 100, "acc": 25, "eva": 50, "pad": 6, "time": 100, "x": 7},
	{"pdd": 100, "mdd": 100, "acc": 25, "eva": 50, "pad": 15, "time": 99, "x": 4},
]
## The WZ level at which a Hex stat first appears (D1; DK-5).
const UNLOCK := {"pdd": 1, "mdd": 6, "acc": 11, "eva": 16, "pad": 21}
const TIME_WZ := [720, 780, 840, 900, 1020, 1080, 1140, 1200]


func _anim(frames: int, ms := 100.0) -> Dictionary:
	var out := {}
	for i in frames:
		out[str(i)] = {"delay": ms}
	return out


## 25 levels of a sub-skill from its eight mapped rows: a level takes the row of the next mapped level at or above it,
## keeping only the fields it has unlocked (`unlock` maps WZ field -> first level).
func _sub_levels(rows: Array, unlock: Dictionary) -> Dictionary:
	var levels := {}
	for lv in range(1, 26):
		var row: Dictionary = rows[SUB_LEVELS.size() - 1]
		for i in SUB_LEVELS.size():
			if SUB_LEVELS[i] >= lv:
				row = rows[i]
				break
		var out := {}
		for field: String in row:
			if lv >= int(unlock.get(field, 1)):
				out[field] = float(row[field])
		levels[str(lv)] = out
	return levels


func _imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	var beholder_levels := {"1": {"time": 660.0}}
	for i in BEHOLDER_LEVELS.size():
		beholder_levels[str(BEHOLDER_LEVELS[i])] = {"time": float(TIME_WZ[i]), "mastery": 1.0}
	for lv in range(1, 11):
		if not beholder_levels.has(str(lv)):
			beholder_levels[str(lv)] = {"time": 700.0}
	var summon := {"summoned": _anim(16), "stand": _anim(16), "move": _anim(8), "die": _anim(8), "skill1": _anim(24)}
	for n in range(2, 7):
		summon["skill%d" % n] = _anim(16)
	var aura_rows := []
	for i in 8:
		aura_rows.append({"hp": AURA_HP[i], "x": AURA_X[i]})
	imgs["132"] = {"skill": {
		"1321007": {"level": beholder_levels, "summon": summon, "affected": _anim(9, 90.0)},
		"1320008": {"level": _sub_levels(aura_rows, {})},
		"1320009": {"level": _sub_levels(HEX_ROWS, UNLOCK)},
	}}
	return imgs


func _book() -> SkillBook:
	return SkillBook.from_data(DataRepo.load_all().skills, _imgs())


func _world(seed_value := 357) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["132"].playable = true
	data.balance["regen"] = {"interval": 10, "hp": 0} # natural regeneration off: only the Aura moves HP
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	setup.skill_imgs = _imgs()
	var w := RunWorld.new(setup)
	w.set_job(132)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.loadout.add_player_mod("max_hp", "add", 2000.0) # room for a flat heal to show exactly
	w.refresh_player_stats()
	w.learn_skill(KEY)
	return w


func _run(w: RunWorld, seconds: float) -> void:
	for tick in roundi(seconds / DT):
		w.step(DT, MoveInput.new())


func _events(w: RunWorld, type: String) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _hurt(w: RunWorld, amount: int) -> void:
	assert_true(w.spend_hp(amount), "setup: the knight can afford %d HP" % amount)


func _support(lo: Loadout, rank: int, kind: String) -> Dictionary:
	for p: Dictionary in lo.stats(KEY, rank).support:
		if p.kind == kind:
			return p
	return {}


# --- rank_levels["10"] (DK-11) -------------------------------------------------------------------------------------

func test_rank_levels_ten_is_the_spec_row_and_the_merged_data_holds_it_once() -> void:
	var skills: Dictionary = DataRepo.load_all().skills
	assert_true(skills.rank_levels.has("10"))
	assert_eq((skills.rank_levels["10"] as Array).map(func(v: Variant) -> int: return int(v)), [2, 3, 4, 5, 7, 8, 9, 10])
	assert_eq(skills.rank_levels["20"][7], 20.0, "the 20 and 30 rows are untouched")
	assert_eq(skills.rank_levels["30"][7], 30.0)
	# One copy in the source files: the shared file, and no per-line fragment declares its own table.
	var text := FileAccess.get_file_as_string("res://data/survivor/skills.json")
	var copies := RegEx.create_from_string("\"10\"\\s*:\\s*\\[").search_all(text)
	assert_eq(copies.size(), 1, "exactly one \"10\" row in survivor/skills.json")
	var dir := DirAccess.open("res://data/survivor/skills")
	for file in dir.get_files():
		if file.ends_with(".json"):
			assert_false(FileAccess.get_file_as_string("res://data/survivor/skills/" + file).contains("\"rank_levels\""),
				file + " declares no rank table of its own")


# --- the three definitions ---------------------------------------------------------------------------------------

func test_the_definitions_are_a_pool_skill_and_two_unowned_sub_skills() -> void:
	var book := _book()
	for key in [KEY, AURA, HEX]:
		assert_true(book.has(key), key)
		assert_eq(book.def(key).book, "132")
		assert_eq(int(book.def(key).job), 132)
	assert_eq(book.skill_id(KEY), 1321007)
	assert_eq(book.skill_id(AURA), 1320008)
	assert_eq(book.skill_id(HEX), 1320009)
	assert_eq(book.def(KEY).kind, "summon")
	assert_eq(book.def(KEY).slot, "active")
	assert_eq(book.def(KEY).cast.rule, "summon")
	assert_eq(book.def(KEY).damage, "none", "no attack: the Hidden pause does not see it")
	assert_eq(book.def(KEY).action, "alert2")
	assert_eq(float(book.def(KEY).cooldown), 45.0)
	for sub in [AURA, HEX]:
		assert_eq(book.def(sub).slot, "summon_sub")
		assert_eq(book.def(sub).summon_sub_of, KEY)
		assert_eq((book.def(sub).ranks as Array).map(func(v: Variant) -> int: return int(v)), SUB_LEVELS)
	var pool: Array = DataRepo.load_all().jobs_survivor.jobs["132"].skill_pool
	assert_true(KEY in pool)
	assert_false(AURA in pool or HEX in pool, "the sub-skills are in no pool and have no card")
	var support: Dictionary = book.def(KEY).summon.support
	assert_eq(support.pulses.size(), 2)
	assert_eq(support.pulses[0].skill, AURA)
	assert_eq(support.pulses[0].kind, "heal")
	assert_eq(support.pulses[0].first_after, "interval")
	assert_eq(support.pulses[0].anim, "skill1")
	assert_eq(support.pulses[1].skill, HEX)
	assert_eq(support.pulses[1].kind, "buff")
	assert_eq(float(support.pulses[1].first_after), 3.0)
	assert_eq(support.pulses[1].anim_by_stat, {"pdd": "skill2", "mdd": "skill3", "acc": "skill4", "avoid": "skill5",
		"watk": "skill6"}, "the five Hex runes in unlock order (D1)")


func test_the_eight_ranks_read_beholder_levels_and_sub_levels_through_their_own_tables() -> void:
	var book := _book()
	assert_eq(book.max_rank(KEY), 8)
	assert_eq(book.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), BEHOLDER_LEVELS)
	var lo := Loadout.new(book)
	lo.add_skill(KEY)
	for rank in range(1, 9):
		assert_eq(lo.stats(KEY, rank).level, BEHOLDER_LEVELS[rank - 1], "Beholder rank %d" % rank)
		assert_eq(lo.stats(AURA, rank).level, SUB_LEVELS[rank - 1], "Aura rank %d" % rank)
		assert_eq(lo.stats(HEX, rank).level, SUB_LEVELS[rank - 1], "Hex rank %d" % rank)
	assert_false(lo.has(AURA) or lo.has(HEX), "a sub is read through its parent and never owned")
	lo.add_skill(AURA)
	assert_false(lo.has(AURA), "add_skill refuses a summon_sub")


# --- the pulses ---------------------------------------------------------------------------------------------------

func test_aura_heals_85_to_500_every_10_to_4_seconds() -> void:
	var lo := Loadout.new(_book())
	lo.add_skill(KEY)
	for rank in range(1, 9):
		var aura := _support(lo, rank, "heal")
		assert_eq(aura.skill, AURA)
		assert_eq(int(aura.amount), AURA_HP[rank - 1], "Aura heal at rank %d" % rank)
		assert_near(float(aura.interval), float(AURA_X[rank - 1]), 0.001, "Aura interval at rank %d" % rank)
		assert_near(float(aura.first_after), float(AURA_X[rank - 1]), 0.001, "the first Aura pulse waits one interval")


func test_hex_applies_exactly_the_stats_its_level_has_for_time_every_x_seconds() -> void:
	var lo := Loadout.new(_book())
	lo.add_skill(KEY)
	for rank in range(1, 9):
		var row: Dictionary = HEX_ROWS[rank - 1]
		var hex := _support(lo, rank, "buff")
		assert_eq(hex.skill, HEX)
		var expected := {}
		for wz: String in ["pdd", "mdd", "acc", "eva", "pad"]:
			if row.has(wz):
				expected[{"eva": "avoid", "pad": "watk"}.get(wz, wz)] = float(row[wz])
		assert_eq(hex.effects, expected, "Hex stats at rank %d" % rank)
		assert_near(float(hex.duration), float(row.time), 0.001, "Hex time at rank %d" % rank)
		assert_near(float(hex.interval), float(row.x), 0.001, "Hex interval at rank %d" % rank)
		assert_near(float(hex.first_after), 3.0, 0.001, "the first Hex pulse is 3 s after the summon (tier C)")
	assert_eq(_support(lo, 1, "buff").effects.keys(), ["pdd"], "rank 1 carries pdd only")
	assert_eq(_support(lo, 8, "buff").effects.keys(), ["pdd", "mdd", "acc", "avoid", "watk"], "rank 8 carries all five")


func test_the_pulse_animation_follows_the_newest_unlocked_hex_stat() -> void:
	var lo := Loadout.new(_book())
	lo.add_skill(KEY)
	var anims := []
	for rank in range(1, 9):
		anims.append(_support(lo, rank, "buff").anim)
	assert_eq(anims, ["skill2", "skill3", "skill3", "skill4", "skill5", "skill5", "skill6", "skill6"])
	assert_eq(_support(lo, 1, "heal").anim, "skill1")


# --- life, cooldown, and the literal-duration lever -------------------------------------------------------------

func test_the_beholder_lives_sixty_seconds_whatever_the_wz_time_says() -> void:
	var lo := Loadout.new(_book())
	lo.add_skill(KEY)
	for rank in range(1, 9):
		assert_eq(float(lo.stats(KEY, rank).duration), 60.0, "rank %d (the WZ time is %d s)" % [rank, TIME_WZ[rank - 1]])
	assert_eq(float(lo.stats(KEY, 1).cooldown), 45.0)
	lo.add_skill_mod(KEY, "duration", "mul", 1.5)
	assert_eq(lo.skill_stat(KEY, "duration", 60.0), 90.0, "a duration card still scales the literal life")


func test_a_literal_buff_duration_overrides_the_canonical_time_and_nothing_else_changes() -> void:
	var book := _book()
	var lo := Loadout.new(book)
	lo.add_skill(KEY)
	assert_eq(float(lo.stats(KEY, 1).duration), 60.0)
	# Without the key the canonical field is read as before (the Beholder's own WZ time, 720 s at level 2).
	book.defs[KEY].buff.erase("duration")
	assert_eq(float(lo.stats(KEY, 1).duration), 720.0)
	book.defs[KEY].buff["duration_field"] = "mastery"
	assert_eq(float(lo.stats(KEY, 1).duration), 1.0, "duration_field still names another canonical field")
	book.defs[KEY].buff["duration"] = 12.5
	assert_eq(float(lo.stats(KEY, 1).duration), 12.5, "a literal wins over duration_field")


func test_no_other_shipped_skill_defines_a_literal_buff_duration() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var found := []
	for key: String in skills:
		if (skills[key] as Dictionary).get("buff", {}).has("duration"):
			found.append(key)
	assert_eq(found, [KEY], "the Beholder is the only user of the lever")


func test_the_summon_expires_after_sixty_seconds_and_the_cooldown_counts_from_the_cast() -> void:
	var w := _world()
	_run(w, 1.0)
	w.loadout.order.clear() # one cast only: no recast
	assert_eq(w.runner.summons.living_count(), 1)
	_run(w, 58.0)
	assert_eq(w.runner.summons.living_count(), 1, "still there at 59 s")
	_run(w, 3.0)
	assert_eq(w.runner.summons.living_count(), 0, "gone after 60 s")
	var w2 := _world()
	_run(w2, 44.0)
	assert_eq(_events(w2, "summon_spawn").size(), 1)
	_run(w2, 2.0)
	assert_eq(_events(w2, "summon_spawn").size(), 2, "recast after the 45 s cooldown, counted from the cast")
	assert_eq(w2.runner.summons.living_count(), 1, "a recast replaces the old one")


# --- in a world ---------------------------------------------------------------------------------------------------

func test_rank_one_aura_heals_85_every_ten_seconds_through_restore_player() -> void:
	var w := _world()
	_hurt(w, 1000)
	var hp := int(w.player_state.hp)
	_run(w, 1.0)
	assert_eq(int(w.player_state.hp), hp, "no pulse yet")
	_run(w, 9.5) # the Beholder was cast at the first tick: the Aura is due 10 s after it
	var restored := _events(w, "player_restored").filter(func(e: Dictionary) -> bool: return e.skill == AURA)
	assert_eq(restored.size(), 1)
	assert_eq(int(restored[0].amount), 85)
	assert_eq(int(w.player_state.hp), hp + 85)
	_run(w, 10.0)
	assert_eq(_events(w, "player_restored").size(), 2, "and every 10 s after that")


func test_rank_one_hex_gives_pdd_only_after_three_seconds_and_the_defence_returns() -> void:
	var w := _world()
	var before := float(w.hit_defense().pdd)
	_run(w, 2.5)
	assert_false(w.buffs.has(HEX))
	_run(w, 1.0)
	assert_true(w.buffs.has(HEX))
	assert_eq(w.buffs.active[HEX].effects, {"pdd": 20.0})
	assert_eq(float(w.buffs.active[HEX].duration), 20.0)
	assert_eq(float(w.hit_defense().pdd), before + 20.0, "the defence total moves while the buff lives")
	assert_eq(_events(w, "buff_cast").size(), 1)
	_run(w, 20.5) # 20 s buff, next pulse 42 s after the first
	assert_false(w.buffs.has(HEX))
	assert_eq(float(w.hit_defense().pdd), before, "and returns when it expires")


func test_rank_eight_hex_moves_all_five_player_totals_and_they_return() -> void:
	var w := _world()
	w.loadout.set_rank(KEY, 8)
	var def_before: Dictionary = w.hit_defense()
	var acc_before: float = w.loadout.acc
	var avoid_before := float(w.player_state.avoid)
	var watk_before := w.buffs.effect_total("watk")
	_run(w, 3.5)
	assert_true(w.buffs.has(HEX))
	var def: Dictionary = w.hit_defense()
	assert_eq(float(def.pdd), float(def_before.pdd) + 100.0)
	assert_eq(float(def.mdd), float(def_before.mdd) + 100.0)
	assert_eq(w.loadout.acc, acc_before + 25.0, "acc")
	assert_eq(float(w.player_state.avoid), avoid_before + 50.0, "WZ eva reaches the avoid total")
	assert_eq(w.buffs.effect_total("watk"), watk_before + 15.0, "WZ pad reaches the weapon attack")
	assert_eq(float(w.buffs.active[HEX].duration), 99.0)
	w.loadout.order.clear() # no recast, and the Beholder dies at 60 s: its last Hex pulse refreshed the buff at 3 s + k x 4 s
	_run(w, 58.0)
	assert_true(w.buffs.has(HEX), "the buff is still refreshed while the Beholder lives")
	_run(w, 100.0) # 99 s after the last pulse
	assert_false(w.buffs.has(HEX))
	assert_eq(float(w.hit_defense().pdd), float(def_before.pdd))
	assert_eq(float(w.player_state.avoid), avoid_before)
	assert_eq(w.loadout.acc, acc_before)
	assert_eq(w.buffs.effect_total("watk"), watk_before)


func test_a_hex_pulse_refreshes_the_buff_and_two_beholders_never_stack() -> void:
	var w := _world()
	w.loadout.set_rank(KEY, 8)
	w.loadout.add_skill_mod(KEY, "summon_count", "add", 1.0)
	_run(w, 3.5)
	assert_eq(w.runner.summons.living_count(), 2)
	assert_eq(w.buffs.active.size(), 1, "one entry keyed by the sub")
	assert_eq(w.buffs.effect_total("pdd"), 100.0, "the same stat never stacks")
	_run(w, 20.0)
	assert_eq(w.buffs.effect_total("pdd"), 100.0)


func test_a_recast_replaces_the_beholder() -> void:
	var w := _world()
	_run(w, 45.5)
	assert_eq(w.runner.summons.living_count(), 1)
	assert_eq(w.runner.summons.active.size(), 1, "the slot was reused")
	assert_eq(_events(w, "summon_spawn").size(), 2)


# --- text ---------------------------------------------------------------------------------------------------------

func test_the_skill_line_lists_each_pulse_with_amount_stats_and_interval() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	var line := text.level_line(KEY, 2, w.loadout.stats(KEY, 1))
	assert_true(line.contains("Aura of the Beholder: heals 85 HP every 10 s"), line)
	assert_true(line.contains("Hex of the Beholder: Weapon DEF +20 for 20 s every 42 s"), line)
	line = text.level_line(KEY, 10, w.loadout.stats(KEY, 8))
	assert_true(line.contains("heals 500 HP every 4 s"), line)
	assert_true(line.contains("Weapon DEF +100, Magic DEF +100, Accuracy +25, Avoid +50, Weapon ATT +15 for 99 s every 4 s"), line)
	assert_true(line.contains("60"), "the line names the 60 s life: " + line)
	assert_true(text.desc(KEY) != "", "a description")


# --- rarity cards (tier C, spec table) ----------------------------------------------------------------------------

func test_the_rarity_lists_are_the_spec_table() -> void:
	var bonuses: Dictionary = _book().def(KEY).rarity_bonuses
	assert_eq(bonuses.keys(), ["rare", "epic", "unique", "legendary"])
	var rare: Dictionary = bonuses.rare[0]
	assert_eq([rare.id, rare.text], ["aura", "Aura of the Beholder"])
	assert_eq(rare.effects, [{"stat": "support_heal", "op": "mul", "value": 1.3}])
	var epic: Dictionary = bonuses.epic[0]
	assert_eq([epic.id, epic.text], ["hex", "Hex of the Beholder"])
	assert_eq(epic.effects, [{"stat": "support_rate", "op": "mul", "value": 0.75}])
	var unique: Dictionary = bonuses.unique[0]
	assert_eq([unique.id, unique.text], ["twin", "Twin Beholder"])
	assert_eq(unique.effects, [{"stat": "summon_count", "op": "add", "value": 1.0}])
	var legendary: Dictionary = bonuses.legendary[0]
	assert_eq(legendary.id, "twin", "Legendary shares the Unique's counter")
	assert_eq(legendary.effects, [{"stat": "summon_count", "op": "add", "value": 1.0},
		{"stat": "support_heal", "op": "mul", "value": 1.3}], "the Beholder has no damage: the Rare's heal bonus instead")


func test_each_bonus_changes_the_resolved_cast_and_the_cast_itself() -> void:
	var bonuses: Dictionary = _book().def(KEY).rarity_bonuses
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		var base := _world()
		var boosted := _world()
		for bonus: Dictionary in bonuses[tier]:
			for e: Dictionary in bonus.effects:
				boosted.loadout.add_skill_mod(KEY, String(e.stat), String(e.op), float(e.value))
		var b := base.loadout.stats(KEY)
		var s := boosted.loadout.stats(KEY)
		var changed := false
		changed = changed or int(s.support[0].amount) != int(b.support[0].amount)
		changed = changed or float(s.support[0].interval) != float(b.support[0].interval)
		changed = changed or float(s.support[1].interval) != float(b.support[1].interval)
		changed = changed or boosted.loadout.skill_stat(KEY, "summon_count", 0.0) != base.loadout.skill_stat(KEY, "summon_count", 0.0)
		assert_true(changed, tier + ": the resolved cast differs")
		# And the cast itself: hurt the knight, run 25 s, compare HP restored / pulses / Beholders alive.
		for w: RunWorld in [base, boosted]:
			_hurt(w, 1500)
			_run(w, 25.0)
		match tier:
			"rare", "legendary":
				var restored := func(w: RunWorld) -> int:
					var total := 0
					for e: Dictionary in _events(w, "player_restored"):
						total += int(e.amount)
					return total
				assert_true(restored.call(boosted) > restored.call(base), tier + ": more HP healed")
			"epic":
				assert_true(_events(boosted, "support_pulse").size() > _events(base, "support_pulse").size(), tier + ": more pulses")
		if tier in ["unique", "legendary"]:
			assert_eq(boosted.runner.summons.living_count(), base.runner.summons.living_count() + 1, tier + ": a second Beholder")


func test_the_numbers_of_the_four_bonuses_at_rank_one() -> void:
	var w := _world()
	assert_eq(int(w.loadout.stats(KEY).support[0].amount), 85)
	w.loadout.add_skill_mod(KEY, "support_heal", "mul", 1.3)
	assert_eq(int(w.loadout.stats(KEY).support[0].amount), 110, "85 x 1.3 rounds to 110 (the float product is 110.49999999999999)")
	w.loadout.add_skill_mod(KEY, "support_rate", "mul", 0.75)
	assert_near(float(w.loadout.stats(KEY).support[0].interval), 7.5, 0.001)
	assert_near(float(w.loadout.stats(KEY).support[1].interval), 31.5, 0.001)
	assert_near(float(w.loadout.stats(KEY).support[1].first_after), 3.0, 0.001, "the 3 s first Hex is not a pulse interval")


func test_rarity_cards_add_one_rank_plus_their_bonus_and_legendary_shares_the_twins_counter() -> void:
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		var w := _world()
		w.upgrades.apply(KEY + "_rank", w, tier)
		assert_eq(w.loadout.rank(KEY), 2, tier + ": a Rare+ card adds one rank")
		assert_false(w.upgrades.choice_card(KEY + "_rank", w, tier).get("rarity_bonus", {}).is_empty(), tier)
		match tier:
			"rare": assert_near(w.loadout.skill_stat(KEY, "support_heal", 1.0), 1.3)
			"epic": assert_near(w.loadout.skill_stat(KEY, "support_rate", 1.0), 0.75)
			"unique": assert_near(w.loadout.skill_stat(KEY, "summon_count", 0.0), 1.0)
			"legendary":
				assert_near(w.loadout.skill_stat(KEY, "summon_count", 0.0), 1.0)
				assert_near(w.loadout.skill_stat(KEY, "support_heal", 1.0), 1.3)
	var w := _world()
	w.upgrades.apply(KEY + "_rank", w, "unique")
	w.upgrades.apply(KEY + "_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:twin" % KEY]), 2, "Legendary shares the Unique's counter")
	assert_eq(w.loadout.rank(KEY), 3)
	assert_near(w.loadout.skill_stat(KEY, "summon_count", 0.0), 1.8, 0.001, "the repeat shrinks x0.8")


func test_the_cards_preview_the_heal_and_the_interval_in_player_units() -> void:
	var w := _world()
	var rare := w.upgrades.choice_card(KEY + "_rank", w, "rare")
	assert_eq(rare.skill_mod_changes.support_heal, {"before": 85, "after": 110}, "85 x 1.3 = 110.49999999999999 in floats, rounded")
	var epic := w.upgrades.choice_card(KEY + "_rank", w, "epic")
	assert_eq(epic.skill_mod_changes.support_rate, {"before": 10.0, "after": 7.5}, "10 s x 0.75")


# --- real cache ---------------------------------------------------------------------------------------------------

func _real_imgs() -> Dictionary:
	var img := AssetLibrary.get_default().img("Skill.wz/132.img")
	return {"132": img.root} if img != null else {}


func test_real_cache_the_eight_ranks_read_the_spec_tables() -> void:
	if not require_cache():
		return
	var imgs := _real_imgs()
	assert_false(imgs.is_empty())
	if imgs.is_empty():
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var lo := Loadout.new(book)
	lo.add_skill(KEY)
	for rank in range(1, 9):
		assert_eq(lo.stats(KEY, rank).level, BEHOLDER_LEVELS[rank - 1])
		var aura := _support(lo, rank, "heal")
		assert_eq(int(aura.amount), AURA_HP[rank - 1], "real Aura hp at rank %d" % rank)
		assert_near(float(aura.interval), float(AURA_X[rank - 1]), 0.001)
		var row: Dictionary = HEX_ROWS[rank - 1]
		var hex := _support(lo, rank, "buff")
		assert_eq(hex.effects.size(), row.keys().size() - 2, "real Hex stat count at rank %d" % rank)
		assert_near(float(hex.interval), float(row.x), 0.001)
		assert_near(float(hex.duration), float(row.time), 0.001, "real Hex time at rank %d (100 at 21-24, 99 at 25)" % rank)
		for wz: String in ["pdd", "mdd", "acc", "eva", "pad"]:
			if row.has(wz):
				assert_eq(float(hex.effects[{"eva": "avoid", "pad": "watk"}.get(wz, wz)]), float(row[wz]), "%s at rank %d" % [wz, rank])
		assert_eq(float(lo.stats(KEY, rank).duration), 60.0)


func test_real_cache_the_summon_animations_and_the_owner_side_affected_node() -> void:
	if not require_cache():
		return
	var imgs := _real_imgs()
	if imgs.is_empty():
		assert_true(false, "Skill.wz/132.img is imported")
		return
	var node: Dictionary = imgs["132"].skill["1321007"]
	var counts := {"summoned": 16, "stand": 16, "move": 8, "die": 8, "skill1": 24, "skill2": 16, "skill3": 16, "skill4": 16,
		"skill5": 16, "skill6": 16}
	for anim: String in counts:
		var frames := 0
		for k: Variant in (node.summon[anim] as Dictionary).keys():
			if str(k).is_valid_int() and WzImg.is_canvas(node.summon[anim][k]):
				frames += 1
		assert_eq(frames, counts[anim], "summon/%s frames" % anim)
	var affected := 0
	for k: Variant in (node.affected as Dictionary).keys():
		if str(k).is_valid_int() and WzImg.is_canvas(node.affected[k]):
			affected += 1
	assert_eq(affected, 9, "affected: 9 frames on the owner")
	# Every path the definition names resolves to a node.
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var d := book.def(KEY)
	assert_true(String(d.summon.path).ends_with("1321007/summon"))
	assert_true(imgs["132"].skill["1321007"].has("summon"))
	assert_true(String(d.icon).ends_with("1321007/icon"))
	for sub in [AURA, HEX]:
		assert_true(String(book.def(sub).icon).ends_with("/icon"), sub)


func test_real_cache_the_summon_animation_lengths_drive_the_sim_summon_and_pulses() -> void:
	if not require_cache():
		return
	var imgs := _real_imgs()
	if imgs.is_empty():
		return
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["132"].playable = true
	var setup := RF.setup("quiet", 357, data)
	setup.skill_imgs = imgs
	var w := RunWorld.new(setup)
	w.set_job(132)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.learn_skill(KEY)
	_run(w, 12.0)
	assert_eq(w.runner.summons.living_count(), 1)
	assert_true(_events(w, "support_pulse").size() >= 2, "an Aura and a Hex pulse with the real animations")
	assert_eq(_events(w, "summon_attack").size(), 0)
