extends TestCase
## Fire, Ice and Thunder Charge (spec #308, P7 #315): the first three Forms of the Form seam (P3 #311), each carrying
## Charged Blow (P6 #314). Synthetic Skill.wz books shaped like 121.img (the eight mapped levels hold the real numbers, the
## levels between repeat the next mapped one), the real skill data and a quiet Paladin world; the real-cache tests at the end
## read Skill.wz itself and SKIP without it. Holy Charge is P8's.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const CASTER_X := 1000.0
const FLAT := [{"x1": 0, "y1": 200, "x2": 2000, "y2": 200}]
## Rank -> WZ level of the standard 30-level table (tier A reading, P1 #309).
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const CHARGES := ["fire_charge", "ice_charge", "thunder_charge"]
## Tier A, Skill.wz 121.img `damage` at the eight mapped levels (P1 #309).
const DAMAGE := {
	"fire_charge": [105, 109, 111, 112, 114, 116, 118, 120],
	"ice_charge": [102, 103, 104, 105, 107, 108, 109, 110],
	"thunder_charge": [107, 111, 115, 117, 119, 121, 123, 125],
}
const SKILL_ID := {"fire_charge": 1211003, "ice_charge": 1211005, "thunder_charge": 1211007}
const TWIN_ID := {"fire_charge": 1211004, "ice_charge": 1211006, "thunder_charge": 1211008}
const ELEMENT := {"fire_charge": "f", "ice_charge": "i", "thunder_charge": "l"}
## Charged Blow's tier A rows at the eight mapped levels.
const BLOW := {"damage": [168, 176, 186, 195, 207, 222, 238, 250], "prop": [38, 46, 54, 60, 68, 76, 84, 90],
	"time": [2, 2, 3, 3, 3, 4, 4, 4], "range": [130, 130, 140, 140, 140, 150, 150, 150],
	"hpCon": [15, 15, 20, 20, 20, 25, 25, 25]}


## 30 level rows from `rows` (field -> its eight values): a mapped level holds its value, the levels between the next one's.
static func _levels(rows: Dictionary) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var index := 0
		while LEVELS[index] < lv:
			index += 1
		var row := {}
		for field: String in rows:
			row[field] = rows[field][index]
		levels[str(lv)] = row
	return levels


static func _books(setup: Dictionary) -> void:
	var skills := {}
	for key in CHARGES:
		skills[str(SKILL_ID[key])] = {"level": _levels({"damage": DAMAGE[key]})}
	var blow := BLOW.duplicate()
	blow["mobCount"] = [6, 6, 6, 6, 6, 6, 6, 6]
	skills["1211002"] = {"level": _levels(blow)}
	setup.skill_imgs["121"] = {"skill": skills}
	var rush := {"damage": [78, 86, 94, 100, 108, 116, 124, 130], "mobCount": [15, 15, 15, 15, 15, 15, 15, 15]}
	var rush_levels := _levels(rush)
	for level: Dictionary in rush_levels.values():
		level["lt"] = {"$v": [-170.0, -50.0]}
		level["rb"] = {"$v": [0.0, 0.0]}
	setup.skill_imgs["122"] = {"skill": {"1221007": {"level": rush_levels}}}


## A quiet Paladin (122) on a flat floor at x 1000 that learned `keys`, with mobs that never walk.
func _world(keys: Array = [], p_seed := 315) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["122"]["playable"] = true # P9 #317 flips it for real; the pool's cards need it
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	_books(setup)
	var w := RunWorld.new(setup)
	w.set_job(122)
	w.bounds = Rect2(0, -500, 2000, 1000)
	w.fhm = FootholdMap.from_segments(FLAT)
	w.swarm.fhm = w.fhm
	RF.place_player(w, CASTER_X)
	w.loadout.order.clear()
	w.loadout.ranks.clear()
	for key: String in keys:
		w.learn_skill(key)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.drain_events()
	return w


func _tick(w: RunWorld, ticks := 1) -> void:
	for i in ticks:
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.runner.step(DT, w)


func _mob(w: RunWorld, dx: float, hp := 1000000.0) -> int:
	var m := RF.put_mob(w, MOB, CASTER_X + dx, 190.0, hp)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _events(w: RunWorld, type: String) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _start(w: RunWorld, key: String, rank := 1) -> void:
	w.runner.forms.start(w, key, w.loadout.stats(key, rank))
	w.drain_events()


# --- The definitions ---------------------------------------------------------------------------------------------------

func test_each_charge_is_a_pool_form_of_book_121() -> void:
	var w := _world()
	for key in CHARGES:
		assert_true(w.book.has(key), "%s is defined by skills/paladin.json" % key)
		var d := w.book.def(key)
		assert_eq(int(d.skill_id), SKILL_ID[key], key)
		assert_eq(String(d.book), "121")
		assert_eq(int(d.job), 121)
		assert_eq(String(d.kind), "form")
		assert_eq(String(d.slot), "active")
		assert_eq(String(d.damage), "none", "a Form deals no damage itself")
		assert_eq(float(d.cooldown), 18.0)
		assert_eq(String(d.cast.rule), "form")
		assert_eq(int(d.cast.mob_within), 400)
		assert_eq(d.cast.size(), 2)
		assert_eq(String(d.action), "alert4", "the stance every Charge shares (tier A)")
		assert_true(key in w.jobs.skill_pool(122), "%s is in the Paladin pool" % key)
		assert_eq(d.form.duration, 12.0)
		assert_eq(d.form.exclusive_group, "paladin_charge")
		assert_eq(d.form.effects, {"element": ELEMENT[key], "damage": {"field": "damage"}})
		assert_eq(d.form.subs, [{"skill": "charged_blow", "first_after": 1.0, "interval": 3.0}])
		assert_eq(d.art_by_family.keys(), ["blunt"])
		assert_eq(int(d.art_by_family.blunt), TWIN_ID[key])
		assert_eq(w.book.rank_table(key).map(func(v: Variant) -> int: return int(v)), LEVELS, "rank 1 reads WZ level 4")
		assert_eq(w.book.max_rank(key), 8)
		assert_eq(String(d.effect), "Skill.wz/121.img/skill/%d/effect" % SKILL_ID[key])
		assert_eq(String(d.icon), "Skill.wz/121.img/skill/%d/icon" % SKILL_ID[key])
		assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/%d/Use" % SKILL_ID[key])


func test_the_catalog_validates_with_the_charges_defined() -> void:
	var defs: Dictionary = _world().book.defs
	assert_eq(Array(PlayerForms.validation_errors(defs)).filter(func(e: String) -> bool: return "holy_charge" not in e), [])


func test_a_blunt_weapon_shows_the_twins_art_and_a_sword_its_own() -> void:
	var w := _world()
	for key in CHARGES:
		assert_eq(w.book.art_skill_id(key, "blunt"), TWIN_ID[key], key)
		for family in ["sword", "", "axe"]:
			assert_eq(w.book.art_skill_id(key, family), SKILL_ID[key], "%s with %s" % [key, family])
		w.loadout.weapon_family = "sword"
		assert_true(String(w.loadout.stats(key).effect).contains("/%d/" % SKILL_ID[key]), key)
		w.loadout.weapon_family = "blunt"
		assert_true(String(w.loadout.stats(key).effect).contains("/%d/" % TWIN_ID[key]), "%s with a mace" % key)
		assert_eq(int(w.loadout.stats(key).skill_id), SKILL_ID[key], "the numbers and id stay the sword's")
		assert_eq(w.loadout.stats(key).level, 4)


# --- The multiplier by rank --------------------------------------------------------------------------------------------

func test_the_damage_multiplier_follows_the_wz_table_per_rank() -> void:
	var w := _world()
	for key in CHARGES:
		for rank in range(1, 9):
			_start(w, key, rank)
			var snap: Array = w.runner.forms.snapshot()
			assert_near(float(snap[0].effects.damage), DAMAGE[key][rank - 1] / 100.0, 1e-5, "%s rank %d" % [key, rank])
			assert_eq(int(snap[0].rank), rank)
			w.runner.forms.clear(w, "test")
	assert_near(float(w.loadout.stats("fire_charge", 8).form_power), 0.0, 1e-5)


# --- Admission ---------------------------------------------------------------------------------------------------------

func test_a_charge_casts_only_with_a_mob_within_400_px() -> void:
	for key in CHARGES:
		var w := _world([key])
		_mob(w, 450.0)
		_tick(w, 3)
		assert_true(w.runner.forms.snapshot().is_empty(), "%s: a mob at 450 px is too far" % key)
		_mob(w, 380.0)
		_tick(w, 1)
		assert_eq(w.runner.forms.snapshot().size(), 1, "%s: a mob at 380 px admits it" % key)
		assert_eq(_events(w, "form_started")[0].element, ELEMENT[key])
		assert_eq(String(_events(w, "cast")[0].skill), key)
		assert_true(w.buffs.has(key), "the buff row shows the running Charge")


func test_the_cooldown_counts_from_the_cast_and_a_recast_waits_for_the_window_to_end() -> void:
	var w := _world(["fire_charge"])
	_mob(w, 100.0)
	_tick(w, 1)
	assert_near(float(w.runner.cooldowns.fire_charge), 18.0, 0.05)
	_tick(w, 12 * 60 + 2)
	assert_true(w.runner.forms.snapshot().is_empty(), "the 12 s window ended")
	assert_eq(_events(w, "form_started").size(), 1)
	_tick(w, 6 * 60 + 2)
	assert_eq(_events(w, "form_started").size(), 2, "a new window at 18 s")


# --- Two Charges ---------------------------------------------------------------------------------------------------------

func test_two_charges_chain_with_no_gap_and_never_overlap() -> void:
	var w := _world(["fire_charge", "ice_charge"])
	w.god = true
	var m := _mob(w, 100.0)
	w.swarm.mob_kind(m).elements = {"F": 1.5, "I": 0.5}
	var started := []
	var ended := []
	for tick in 12 * 60 * 2:
		_tick(w)
		assert_true(w.runner.forms.snapshot().size() <= 1, "tick %d: two Charges never run together" % tick)
		for e: Dictionary in w.drain_events():
			if e.type == "form_started":
				started.append([tick, String(e.skill)])
			elif e.type == "form_ended":
				ended.append([tick, String(e.skill), String(e.reason)])
	assert_eq(started[0][1], "fire_charge", "the mob is weak to fire")
	assert_eq(started[1][1], "ice_charge", "the other Charge takes over")
	assert_eq(ended[0][2], "expired")
	assert_true(int(started[1][0]) - int(ended[0][0]) <= 1, "no gap: ended at tick %d, next at %d" % [ended[0][0], started[1][0]])
	assert_true(absi(int(started[1][0]) - 12 * 60) <= 2, "the second begins when the first's 12 s are up")


func test_the_charge_the_nearby_mobs_are_weak_to_is_chosen() -> void:
	for pair: Array in [["fire_charge", {"F": 1.5, "I": 1.0, "L": 1.0}], ["ice_charge", {"F": 1.0, "I": 1.5, "L": 1.0}],
			["thunder_charge", {"F": 1.0, "I": 1.0, "L": 1.5}], ["ice_charge", {"F": 0.5, "I": 1.0, "L": 0.5}]]:
		var w := _world(CHARGES)
		var m := _mob(w, 150.0)
		w.swarm.mob_kind(m).elements = pair[1]
		_tick(w, 1)
		assert_eq(String(w.runner.forms.snapshot()[0].skill), pair[0], str(pair[1]))
		assert_eq(w.runner.forms.snapshot().size(), 1)


# --- The element reaches every Paladin attack --------------------------------------------------------------------------

## Damage dealt (mob_hit events) to a crowd of four by the first cast of `skill` under `charge` when the crowd's element
## multiplier for the Charge's element is `mult`.
func _damage_dealt(charge: String, skill: String, mult: float) -> float:
	var w := _world([skill])
	w.loadout.add_skill_mod(skill, "damage", "mul", 500.0) # big hits: whole-number rounding stays under 0.3%
	var slots := []
	for dx in [-90.0, -40.0, 40.0, 90.0]:
		slots.append(_mob(w, dx))
	w.swarm.mob_kind(slots[0]).elements = {String(ELEMENT[charge]).to_upper(): mult} # one kind: all four share it
	_start(w, charge)
	if skill == "rush_paladin":
		assert_true(w.runner.cast_dash(w, skill, 1), "%s dashes" % skill)
	else:
		for i in 120:
			_tick(w)
			if w.runner.casts > 0:
				break
		assert_eq(w.runner.casts, 1, "%s cast once" % skill)
	var dealt := 0.0
	for e in _events(w, "mob_hit"):
		if String(e.skill) == skill:
			dealt += float(e.damage)
	return dealt


func test_each_charges_element_reaches_power_strike_slash_blast_blast_and_rush() -> void:
	var probe := _world()
	var skills := ["power_strike", "slash_blast", "blast", "rush_paladin"]
	for charge in CHARGES:
		for skill: String in skills:
			if not probe.book.has(skill):
				continue # blast is P5's (#313): the loop covers it from the merge on
			var neutral := _damage_dealt(charge, skill, 1.0)
			assert_true(neutral > 0.0, "%s under %s hurts" % [skill, charge])
			assert_near(_damage_dealt(charge, skill, 1.5) / neutral, 1.5, 0.03, "%s %s weak" % [charge, skill])
			assert_near(_damage_dealt(charge, skill, 0.5) / neutral, 0.5, 0.03, "%s %s resistant" % [charge, skill])
			assert_eq(_damage_dealt(charge, skill, 0.0), 0.0, "%s %s immune takes nothing" % [charge, skill])


# --- Charged Blow inside the window ------------------------------------------------------------------------------------

func test_charged_blow_fires_on_its_interval_inside_the_window_and_never_outside() -> void:
	var w := _world(["fire_charge"])
	w.god = true
	for dx in [-60.0, 0.0, 60.0]:
		_mob(w, dx)
	var blows := []
	for tick in 17 * 60:
		w.restore_player("hp", 100, "test") # Charged Blow pays HP and waits when it cannot
		_tick(w)
		for e: Dictionary in w.drain_events():
			if e.type == "cast" and String(e.skill) == "charged_blow":
				blows.append(tick)
	# The Charge starts on tick 0; the blow is due 1.0 s later, then every 3.0 s while the 12 s window lasts.
	assert_eq(blows.size(), 4, str(blows))
	for i in blows.size():
		assert_true(absi(int(blows[i]) - (60 + i * 180)) <= 2, "blow %d at tick %d" % [i, blows[i]])
	assert_true(int(blows.back()) < 12 * 60, "none once the window is over")


func test_charged_blow_damage_scales_with_the_charge_rank() -> void:
	var first := []
	for rank in [1, 8]:
		var w := _world(["fire_charge"])
		w.loadout.set_rank("fire_charge", rank)
		for dx in [-60.0, 0.0, 60.0]:
			_mob(w, dx)
		_tick(w, 70)
		var total := 0.0
		for e in _events(w, "mob_hit"):
			if String(e.skill) == "charged_blow":
				total += float(e.damage)
		first.append(total)
	# The blow reads the Charge's rank through its own table (168 -> 250 %) and takes the Charge's multiplier (1.05 -> 1.20).
	assert_true(first[0] > 0.0)
	assert_near(first[1] / first[0], (250.0 / 168.0) * (1.20 / 1.05), 0.12, "rolls and whole-number rounding of small hits")


func test_advanced_charge_multiplies_the_blow_and_not_the_charges_own_multiplier() -> void:
	var dealt := []
	var form := []
	for factor in [1.0, 1.3]:
		var w := _world(["fire_charge"])
		w.loadout.add_skill_mod("fire_charge", "damage", "mul", factor)
		w.loadout.add_skill_mod("charged_blow", "damage", "mul", 100.0) # whole numbers
		for dx in [-60.0, 0.0, 60.0]:
			_mob(w, dx)
		_tick(w, 70)
		var total := 0.0
		for e in _events(w, "mob_hit"):
			if String(e.skill) == "charged_blow":
				total += float(e.damage)
		dealt.append(total)
		form.append(float(w.runner.forms.snapshot()[0].effects.damage))
	assert_near(dealt[1] / dealt[0], 1.3, 0.02)
	assert_near(form[1], form[0], 1e-9, "the Charge's own multiplier is the WZ table's alone")


# --- Rarity --------------------------------------------------------------------------------------------------------------

func test_every_charge_carries_the_four_lists_of_the_spec() -> void:
	var w := _world()
	for key in CHARGES:
		var lists: Dictionary = w.book.def(key).rarity_bonuses
		assert_eq(lists.keys(), ["rare", "epic", "unique", "legendary"], key)
		var rare: Dictionary = lists.rare[0]
		assert_eq([rare.id, rare.text], ["mastery", "Mastery"])
		assert_eq(rare.effects, [{"stat": "form_power", "op": "add", "value": 0.1}])
		var epic: Dictionary = lists.epic[0]
		assert_eq([epic.id, epic.text], ["booster", "Booster"])
		assert_eq(epic.effects, [{"stat": "cooldown", "op": "mul", "value": 0.88}])
		var unique: Dictionary = lists.unique[0]
		assert_eq([unique.id, unique.text], ["advanced_charge", "Advanced Charge"])
		assert_eq(unique.effects, [{"stat": "damage", "op": "mul", "value": 1.3}, {"stat": "form_time", "op": "mul", "value": 1.25}])
		var legendary: Dictionary = lists.legendary[0]
		assert_eq(legendary.id, "advanced_charge", "the Unique's id: one shared repeat counter")
		assert_eq(legendary.effects, unique.effects + [{"stat": "damage", "op": "mul", "value": 1.2}])
		for tier: String in lists:
			assert_eq(lists[tier].size(), 1)


func _rank_card(key: String) -> String:
	return key + "_rank"


func test_a_rare_or_better_card_adds_one_rank_and_its_bonus() -> void:
	for key in CHARGES:
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			var w := _world([key])
			var card: Dictionary = w.upgrades.choice_card(_rank_card(key), w, tier)
			assert_false(card.get("rarity_bonus", {}).is_empty(), "%s %s names its bonus" % [key, tier])
			assert_false(card.skill_mod_changes.is_empty(), "%s %s previews a change" % [key, tier])
			w.upgrades.apply(_rank_card(key), w, tier)
			assert_eq(w.loadout.rank(key), 2, "%s %s: exactly one rank" % [key, tier])
			match tier:
				"rare":
					assert_near(w.loadout.skill_stat(key, "form_power", 0.0), 0.1, 1e-5)
				"epic":
					assert_near(float(w.loadout.stats(key).cooldown), 18.0 * 0.88, 0.01)
				"unique":
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.3, 1e-5)
					assert_near(float(w.loadout.stats(key).duration), 15.0, 1e-5)
				"legendary":
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.56, 1e-5)
					assert_near(float(w.loadout.stats(key).duration), 15.0, 1e-5)


func test_the_card_previews_show_form_power_duration_and_cooldown_in_resolved_units() -> void:
	var w := _world(["fire_charge"])
	var rare: Dictionary = w.upgrades.choice_card("fire_charge_rank", w, "rare")
	assert_eq(rare.skill_mod_changes.form_power, {"before": 0.0, "after": 10.0})
	var unique: Dictionary = w.upgrades.choice_card("fire_charge_rank", w, "unique")
	assert_eq(unique.skill_mod_changes.form_time, {"before": 12.0, "after": 15.0})
	assert_eq(unique.skill_mod_changes.damage, {"before": 100, "after": 130})
	var epic: Dictionary = w.upgrades.choice_card("fire_charge_rank", w, "epic")
	assert_eq(epic.skill_mod_changes.cooldown, {"before": 18.0, "after": 15.84})


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	var w := _world(["ice_charge"])
	w.upgrades.apply("ice_charge_rank", w, "unique")
	w.upgrades.apply("ice_charge_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:ice_charge:advanced_charge"]), 2)
	# The Legendary is the second use of the shared id: x0.8 of each effect's distance from neutral.
	assert_near(w.loadout.skill_stat("ice_charge", "form_time", 1.0), 1.25 * (1.0 + 0.25 * 0.8) * 1.0, 1e-6)
	var m := _world(["thunder_charge"])
	m.upgrades.apply("thunder_charge_rank", m, "rare")
	m.upgrades.apply("thunder_charge_rank", m, "rare")
	assert_near(m.loadout.skill_stat("thunder_charge", "form_power", 0.0), 0.1 + 0.08, 1e-6, "Mastery repeats x0.8")
	m.loadout.set_rank("thunder_charge", 8)
	var c: Dictionary = m.upgrades.choice_card("thunder_charge_rank", m, "rare")
	assert_eq(c.card_kind, "mastery", "after rank 8 the card is a Mastery: no rank")
	m.upgrades.apply("thunder_charge_rank", m, "rare")
	assert_eq(m.loadout.rank("thunder_charge"), 8)
	assert_near(m.loadout.skill_stat("thunder_charge", "form_power", 0.0), 0.1 + 0.08 + 0.064, 1e-6)


# --- Real cache -----------------------------------------------------------------------------------------------------------

func _real_world(lib: AssetLibrary) -> RunWorld:
	var w := _world()
	w.book.skill_imgs["121"] = lib.img("Skill.wz/121.img").root
	return w


func test_real_cache_the_eight_mapped_ranks_read_the_right_wz_level() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(lib)
	for key in CHARGES:
		for rank in range(1, 9):
			var st := w.loadout.stats(key, rank)
			assert_eq(st.level, LEVELS[rank - 1], "%s rank %d" % [key, rank])
			assert_eq(int(w.book.level_node(key, st.level).damage), DAMAGE[key][rank - 1], "%s rank %d damage" % [key, rank])
			_start(w, key, rank)
			assert_near(float(w.runner.forms.snapshot()[0].effects.damage), DAMAGE[key][rank - 1] / 100.0, 1e-5)
			w.runner.forms.clear(w, "test")
	assert_eq(int(w.book.level_node("fire_charge", 1).damage), 102, "level 1 would read 102")
	lib.free()


func test_real_cache_both_twins_nodes_sounds_and_the_cast_effect_exist() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	var w := _real_world(lib)
	for key in CHARGES:
		for id: int in [SKILL_ID[key], TWIN_ID[key]]:
			var effect := lib.find_anim("Skill.wz/121.img/skill/%d/effect" % id)
			assert_true(effect != null, "%d effect" % id)
			assert_eq(effect.frames.size(), 15, "%d: the 15-frame cast effect" % id)
			assert_true(lib.frame("Skill.wz/121.img/skill/%d/icon" % id) != null, "%d icon" % id)
			assert_true(lib.sound("Sound.wz/Skill.img/%d/Use" % id) != null, "%d Use sound (the twin's is a UOL)" % id)
		var twin_effect := String(w.book.art_path(key, String(w.book.def(key).effect), "blunt"))
		assert_true(twin_effect.ends_with("%d/effect" % TWIN_ID[key]), twin_effect)
	lib.free()


func test_blast_art_follows_every_charge_and_uses_gold_without_one() -> void:
	for charge in ["", "ice_charge", "fire_charge", "thunder_charge", "holy_charge"]:
		var w := _world(["blast"])
		if charge != "":
			_start(w, charge)
		var stats := w.loadout.stats("blast").duplicate(true)
		stats = w.runner.forms.begin_cast(w, "blast", stats)
		var index: int = {"": 0, "ice_charge": 1, "fire_charge": 2, "thunder_charge": 3, "holy_charge": 5}[charge]
		assert_eq(String(stats.effect), "Skill.wz/122.img/skill/1221009/effect/%d" % index, charge)
		assert_eq(String(stats.hit), "Skill.wz/122.img/skill/1221009/hit/0/%d" % index, charge)

func test_form_bonus_text_names_the_sub_damage_and_duration() -> void:
	var w := _world(["fire_charge"])
	var card: Dictionary = SkillText.new(w.book).dress([w.upgrades.choice_card("fire_charge_rank", w, "unique")], w.loadout)[0]
	assert_true("Charged Blow +30%" in String(card.rarity_bonus.text), String(card.rarity_bonus.text))
	assert_true("charge lasts 25% longer" in String(card.rarity_bonus.text), String(card.rarity_bonus.text))
	var lines := " ".join(LevelUpWindow.change_lines(card))
	assert_true("Charged Blow damage" in lines, lines)
