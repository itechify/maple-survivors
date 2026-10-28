extends TestCase
## Spearman buffs (spec #165 ticket #184, docs/GAME_DESIGN.md 7.12): Iron Will (W.DEF and M.DEF through the shared pdd/mdd
## buff consumers) and Hyper Body (a percentage MaxHP buff on the whole maximum; its Max MP half went with MP, #285). The
## simulation tests run on a synthetic Skill.wz 130 shaped like the real one (_book130: the level formulas of the v83
## tables); one test compares it with the real cache and SKIPs without it. Seeded, fixed ticks, no HP regeneration.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Synthetic Character.wz info (stats invented): a cap with +40 Max HP and +25 Max MP.
const CAP := 1002001
const INFO := {CAP: {"incMHP": 40, "incMMP": 25, "tuc": 7}}


## Skill.wz/130.img-shaped levels of Iron Will (pdd = mdd = level, 15 s per level, MP 12 then 24) and Hyper Body
## (x = y = 2 per level, 10 s per level, MP 20 / 40 / 60); v83 values, see docs/GAME_DESIGN.md 7.12.
func _book130() -> Dictionary:
	var will := {}
	for lv in range(1, 21):
		will[str(lv)] = {"hs": "h%d" % lv, "pdd": float(lv), "mdd": float(lv), "time": float(15 * lv),
			"mpCon": 12.0 if lv <= 10 else 24.0}
	var hyper := {}
	for lv in range(1, 31):
		hyper[str(lv)] = {"hs": "h%d" % lv, "x": float(2 * lv), "y": float(2 * lv), "time": float(10 * lv),
			"mpCon": 20.0 if lv <= 10 else (40.0 if lv <= 20 else 60.0)}
	return {"skill": {"1301006": {"level": will}, "1301007": {"level": hyper}}}


## A Spearman (130) with regeneration off and the cap in the inventory (not worn); set up directly (#284).
func _spearman(seed_value := 11, god := true) -> RunWorld:
	var data := RF.quiet_data()
	# #284: no advancement grants HP; give the 50 + 225 + 325 the Warrior and Spearman advancements added, and no start
	# skills (a fresh character is a 212).
	data.balance.player.hp = 600
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.magnet_radius = 0
	data.balance.regen.hp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	setup.equipment_info.merge(INFO.duplicate(true))
	setup.skill_imgs["130"] = _book130()
	var w := RunWorld.new(setup)
	w.equipment.inventory.append(Equipment.create(CAP, INFO[CAP]))
	RF.as_job(w, 130)
	RF.place_player(w, 400)
	w.god = god
	w.drain_events()
	return w


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _rank(w: RunWorld, key: String, rank: int) -> void:
	assert_true(w.learn_skill(key), "%s learned" % key)
	w.loadout.set_rank(key, rank)
	w.refresh_player_stats()


## Steps one tick and checks that `skill` was cast on it (a buff starts on the first ready tick).
func _cast(w: RunWorld, skill: String) -> void:
	w.step(DT, MoveInput.new())
	assert_true(w.buffs.has(skill), "%s cast on the first ready tick" % skill)
	w.drain_events()


# --- Iron Will ---------------------------------------------------------------------------------------------------------

func test_iron_will_adds_its_canonical_defence_to_both_hit_defences() -> void:
	var w := _spearman()
	_rank(w, "iron_will", 20)
	var before := w.hit_defense()
	_cast(w, "iron_will")
	var after := w.hit_defense()
	assert_near(float(after.pdd) - float(before.pdd), 20.0, 1e-9, "Lv 20: W.DEF +20")
	assert_near(float(after.mdd) - float(before.mdd), 20.0, 1e-9, "Lv 20: M.DEF +20")
	assert_eq(300.0, float(w.loadout.stats("iron_will").duration), "Lv 20 lasts 300 s")


func test_iron_will_lowers_physical_and_magic_damage_taken_while_active() -> void:
	for magic: bool in [false, true]:
		var taken: Array[int] = []
		for active: bool in [false, true]:
			var w := _spearman(21, false)
			_rank(w, "iron_will", 20)
			if active:
				_cast(w, "iron_will")
			w.drain_events()
			w.take_hit(100.0, magic, "", w.player.pos + Vector2(10, 0), {"accuracy": 1000000})
			var hits := _of(w.drain_events(), "player_hit")
			assert_eq(hits.size(), 1)
			taken.append(int(hits[0].damage))
		assert_eq(taken[0] - taken[1], 15, "%s: 20 defence takes floor(.75 x 20) off the same seeded hit"
			% ("magic" if magic else "physical"))


func test_iron_will_recasts_on_expiry() -> void:
	var w := _spearman()
	_rank(w, "iron_will", 1)
	_cast(w, "iron_will")
	assert_eq(15.0, float(w.loadout.stats("iron_will").duration))
	var casts := 1
	var expiries := 0
	for tick in int(16.0 / DT):
		w.step(DT, MoveInput.new())
		var events := w.drain_events()
		casts += _of(events, "buff_cast").size()
		expiries += _of(events, "buff_expired").size()
	assert_eq(expiries, 1, "ran out once in 16 s")
	assert_eq(casts, 2, "and was recast")
	assert_true(w.buffs.has("iron_will"))


# --- Hyper Body --------------------------------------------------------------------------------------------------------

func test_hyper_body_raises_max_hp_by_the_levels_percent() -> void:
	var w := _spearman()
	_rank(w, "hyper_body", 5)
	var max_hp := int(w.player_state.max_hp)
	assert_eq(50.0, float(w.loadout.stats("hyper_body").duration), "Lv 5 lasts 50 s")
	_cast(w, "hyper_body")
	assert_eq(int(w.player_state.max_hp), roundi(max_hp * 1.10), "Lv 5: Max HP +10%")
	assert_false(w.player_state.has("max_mp"), "no Max MP to raise (#285)")
	assert_true(int(w.player_state.max_hp) > max_hp)


func test_hyper_body_leaves_current_hp_unchanged_at_cast() -> void:
	for full: bool in [true, false]:
		var w := _spearman()
		_rank(w, "hyper_body", 10)
		var hp := float(w.player_state.max_hp) if full else 77.0
		w._hp = hp
		w._write_player_state(0.0)
		_cast(w, "hyper_body")
		assert_eq(float(w.player_state.hp), hp, "HP stays where it was (full: %s)" % full)


func test_hyper_body_expiry_clamps_hp_above_the_normal_max_and_keeps_hp_below_it() -> void:
	for above: bool in [true, false]:
		var w := _spearman()
		_rank(w, "hyper_body", 1)
		var normal_hp := int(w.player_state.max_hp)
		_cast(w, "hyper_body")
		assert_true(int(w.player_state.max_hp) > normal_hp, "raised while active")
		w.runner.cooldowns["hyper_body"] = 1000.0 # held, so the tick it ends does not recast it
		w._hp = float(w.player_state.max_hp) if above else 5.0
		w._write_player_state(0.0)
		var expired := false
		for tick in int(11.0 / DT):
			w.step(DT, MoveInput.new())
			if not w.buffs.has("hyper_body"):
				expired = true
				break
		assert_true(expired, "Hyper Body ended")
		assert_eq(int(w.player_state.max_hp), normal_hp, "the maximum is back to normal")
		assert_eq(int(w.player_state.hp), normal_hp if above else 5, "above the normal max drops to it; below is untouched")


func test_hyper_body_applies_to_base_equipment_and_improved_max_hp() -> void:
	var plain := _spearman()
	var base_hp := int(plain.player_state.max_hp)
	var w := _spearman()
	_rank(w, "improved_max_hp", 10)
	assert_eq(w.equip_item(0), "", "the cap is worn")
	assert_eq(int(w.player_state.max_hp), base_hp + 40, "equipment HP before the buff")
	# Improved MaxHP Increase: +40 Max HP per level-up at Lv 10, never retroactive.
	var level := w.progression.level
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.progression.level > level:
			break
	assert_eq(w.progression.level, level + 1, "EXP was collected")
	RF.auto_choose(w)
	w.drain_events()
	var normal_hp := int(w.player_state.max_hp)
	assert_true(normal_hp > base_hp + 40 + 40, "the level-up grew Max HP by more than the passive alone")
	_rank(w, "hyper_body", 10)
	for tick in 120: # the level-up card may have been another buff, whose cast hold comes first
		w.step(DT, MoveInput.new())
		if w.buffs.has("hyper_body"):
			break
	assert_true(w.buffs.has("hyper_body"), "Hyper Body cast")
	assert_eq(int(w.player_state.max_hp), roundi(normal_hp * 1.20), "Lv 10: +20% of base, passive growth and equipment")


func test_hyper_body_recasts_on_expiry() -> void:
	var w := _spearman()
	_rank(w, "hyper_body", 1)
	_cast(w, "hyper_body")
	var casts := 1
	var expiries := 0
	for tick in int(11.0 / DT):
		w.step(DT, MoveInput.new())
		var events := w.drain_events()
		casts += _of(events, "buff_cast").size()
		expiries += _of(events, "buff_expired").size()
	assert_eq(expiries, 1, "ran out once in 11 s")
	assert_eq(casts, 2, "and was recast")
	assert_true(w.buffs.has("hyper_body"))
	assert_true(int(w.player_state.max_hp) > 0)


# --- data and text -----------------------------------------------------------------------------------------------------

func test_both_skills_read_without_party_or_canonical_wording() -> void:
	var w := _spearman()
	for key in ["iron_will", "hyper_body"]:
		var d: Dictionary = w.book.def(key)
		var texts := [String(d.desc), String(d.get("text", {}).get("desc", ""))]
		for t: String in texts:
			assert_false(t.to_lower().contains("party"), "%s: no party wording: %s" % [key, t])
			assert_false(t.to_lower().contains("canonical"), "%s: never 'canonical'" % key)
		assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/%d/Use" % int(d.skill_id), "%s keeps its Use sound" % key)
		assert_eq(String(d.kind), "buff")


func test_the_cards_are_job_gated_and_not_power() -> void:
	var w := _spearman()
	for id in ["iron_will_new", "iron_will_rank", "hyper_body_new", "hyper_body_rank"]:
		var card := w.upgrades.card(id)
		assert_false(card.is_empty(), "%s exists" % id)
		assert_false(bool(card.get("power", false)), "%s is not a power card" % id)
		assert_eq(card.requires.jobs, [130.0], "%s is the Spearman's" % id)
		assert_false(w.balance.bot.card_scores.has(id), "%s keeps the default bot score (like Iron Body)" % id)
	assert_has(w.upgrades.eligible(w), "iron_will_new")
	assert_has(w.upgrades.eligible(w), "hyper_body_new")


func test_real_130_img_matches_the_data_and_the_fixture_formulas() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/130.img")
	if img == null:
		skip("the cache has no Skill.wz/130.img (import with the Warrior second-job manifest)")
		library.free()
		return
	var real := SkillBook.from_data(DataRepo.load_all().skills, {"130": img.root})
	var fake := SkillBook.from_data(DataRepo.load_all().skills, {"130": _book130()})
	for key in ["iron_will", "hyper_body"]:
		assert_eq(real.max_level(key), real.max_rank(key), "%s: ranks cover every canonical level" % key)
		assert_eq(real.max_level(key), fake.max_level(key))
	for lv in range(1, 21):
		for field in ["pdd", "mdd", "time", "mpCon"]:
			assert_eq(real.canonical("iron_will", lv, field), fake.canonical("iron_will", lv, field),
				"iron_will %s at Lv %d" % [field, lv])
	for lv in range(1, 31):
		for field in ["x", "y", "time"]:
			assert_eq(real.canonical("hyper_body", lv, field), fake.canonical("hyper_body", lv, field),
				"hyper_body %s at Lv %d" % [field, lv])
		# 20 / 40 / 60 MP per ten levels, except the data's Lv 25 value of 50 (canonical, kept).
		var want := 50.0 if lv == 25 else (20.0 if lv <= 10 else (40.0 if lv <= 20 else 60.0))
		assert_eq(real.canonical("hyper_body", lv, "mpCon"), want, "hyper_body mpCon at Lv %d" % lv)
	library.free()
