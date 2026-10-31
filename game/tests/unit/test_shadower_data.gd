extends TestCase
## Shadower's data seam (spec #425, ticket SH2 #427): the `shadower` line (discovered by its files; ruling D15 keeps it out of
## CLASS_LINES until its redesign merge) loads from its files, its job entry `survivor/jobs/shadower.json` (422, not playable
## until SH14 #439) names the nine-key pool, Assaulter, the dagger family, the Razor and the meso charge meter (no decay), its AP row,
## bot card scores and status-bonus catalogue entry come from the line file (nothing in the shared balance), and its drops are
## daggers only (Thief-bit gear, Thief shields beside a dagger). The pool keys and Assaulter stay inert until SH6-SH12 define them.
## Seeded RNG, fixed dt; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

const POOL := ["double_stab", "steal", "savage_blow", "boomerang_step", "band_of_thieves", "meso_explosion",
	"ninja_ambush_shadower", "dark_sight", "smokescreen"]
const RAZOR := 1332005
## The books a Shadower skill may belong to (the lineage: Thief 400, Bandit 420, Chief Bandit 421, Shadower 422).
const BOOKS := ["400", "420", "421", "422"]
## Synthetic item info (reqJob bits as in the v83 Item.wz): daggers and claws carry the Thief bit (8), the rest belong to
## other classes, so the family filter alone decides which Thief-bit weapons drop.
const INFO := {
	1332005: {"reqLevel": 0, "reqJob": 0, "incPAD": 20, "tuc": 7}, # Razor (creation weapon, every class)
	1332007: {"reqLevel": 0, "reqJob": 8, "incPAD": 20, "tuc": 7}, # dagger
	1332025: {"reqLevel": 0, "reqJob": 8, "incPAD": 40, "tuc": 7}, # dagger
	1472000: {"reqLevel": 0, "reqJob": 8, "incPAD": 10, "tuc": 7}, # claw
	1472030: {"reqLevel": 0, "reqJob": 8, "incPAD": 40, "tuc": 7}, # claw
	1452000: {"reqLevel": 0, "reqJob": 4, "incPAD": 20, "tuc": 7}, # bow
	1462000: {"reqLevel": 0, "reqJob": 4, "incPAD": 20, "tuc": 7}, # crossbow
	1492000: {"reqLevel": 0, "reqJob": 16, "incPAD": 20, "tuc": 7}, # gun
	1482000: {"reqLevel": 0, "reqJob": 16, "incPAD": 20, "tuc": 7}, # knuckle
	1302008: {"reqLevel": 0, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed sword
	1312005: {"reqLevel": 0, "reqJob": 1, "incPAD": 47, "tuc": 7}, # one-handed axe
	1432002: {"reqLevel": 0, "reqJob": 1, "incPAD": 52, "tuc": 7}, # spear
	1372004: {"reqLevel": 0, "reqJob": 2, "incPAD": 24, "incMAD": 38, "tuc": 7}, # wand
	1002001: {"reqLevel": 0, "reqJob": 0, "incPDD": 4, "tuc": 7}, # hat, all jobs
	1040003: {"reqLevel": 0, "reqJob": 8, "incPDD": 4, "tuc": 7}, # top, Thief bit (synthetic)
	1092018: {"reqLevel": 0, "reqJob": 8, "incPDD": 30, "tuc": 7}, # Thief shield
	1092002: {"reqLevel": 0, "reqJob": 1, "incPDD": 40, "tuc": 7}, # Warrior shield
}
const RULES := {"boss_top_parts": 3}
const BAND := [0, 70]


func _data() -> Dictionary:
	return DataRepo.load_all()


func _jobs(data: Dictionary) -> JobTree:
	return JobTree.from_data(data.jobs, data.jobs_survivor)


func _rng(p_seed: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = p_seed
	return rng


## The line names (`skills/<line>.json`) whose file defines `key` in its `skills` map, in discovery order.
func _defining_lines(key: String) -> Array:
	var out := []
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("skills", line)
		if FileAccess.file_exists(path) and DataRepo.load_json(path).get("skills", {}).has(key):
			out.append(line)
	return out


# --- the line ---------------------------------------------------------------------------------------------------------

## Ruling D15: Shadower stays out of CLASS_LINES during the spec (the redesign merge appends it), so DataRepo.lines() finds it by
## its files and sorts it after every registered class.
func test_shadower_line_is_discovered_by_its_files_and_not_registered() -> void:
	var lines := Array(DataRepo.lines())
	assert_true("shadower" in lines, "loaded from its files")
	assert_false("shadower" in Array(DataRepo.CLASS_LINES), "D15: appended to CLASS_LINES at its redesign merge, not during the spec")
	assert_true(lines.find("shadower") > lines.find("hero"), "a class line follows the Adventurer lines and hero")
	assert_true(lines.find("shadower") > lines.find("night_lord"), "unregistered lines sort after the registered classes")
	assert_eq(DataRepo.fragment_path("jobs_survivor", "shadower", "res://data"), "res://data/survivor/jobs/shadower.json")
	assert_eq(DataRepo.fragment_path("skills", "shadower", "res://data"), "res://data/survivor/skills/shadower.json")


func test_the_shadower_line_loads_without_errors_and_adds_its_job() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(d.jobs_survivor.jobs.has("422"), "jobs/shadower.json is merged into the survivor job data")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "shadower"))
	assert_true(frag.has("_doc"), "the skill file names the tickets that append to it")
	assert_true(frag.has("skills"))
	assert_eq(Array(DataRepo.unknown_line_files()), [], "no stray fragment file")


func test_the_shared_defaults_hold_no_shadower_rows() -> void:
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("422"), "the Shadower AP row lives in jobs/shadower.json")
	assert_false(shared.get("status_bonuses", {}).has("venomous_stab"), "the catalogue entry lives in the line file")
	for key: String in ["dark_sight_new", "dark_sight_rank", "smokescreen_new", "smokescreen_rank", "meso_explosion_new",
			"meso_explosion_rank"]:
		assert_false(shared.bot.card_scores.has(key), "%s lives in the line file" % key)
	assert_false(DataRepo.load_json("res://data/survivor/jobs.json").jobs.has("422"), "no shared job entry")
	assert_false(shared.get("growth", {}).has("422"), "no HP growth row: the HP baseline (SH-14) is the QA ticket's")
	assert_false(shared.player.ap.get("422", {}).has("hp"), "and no AP-row hp")


## No other line's file names job 422 or its balance rows: the class touches no other class's file.
func test_no_other_line_file_names_shadower_rows() -> void:
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("jobs_survivor", line)
		if line == "shadower" or not FileAccess.file_exists(path):
			continue
		var frag: Dictionary = DataRepo.load_json(path)
		var balance: Dictionary = frag.get("balance", {})
		assert_false(frag.get("jobs", {}).has("422"), "%s names no Shadower job entry" % line)
		assert_false(balance.get("player", {}).get("ap", {}).has("422"), "%s has no 422 AP row" % line)
		assert_false(balance.get("status_bonuses", {}).has("venomous_stab"), "%s has no Shadower catalogue entry" % line)


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_422_has_the_spec_fields_and_is_not_playable() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(422)
	assert_eq(String(rec.name), "Shadower")
	assert_eq(jobs.starting_skill(422), "double_stab")
	assert_eq(jobs.mobility_skill(422), "assaulter")
	assert_eq(jobs.skill_pool(422), POOL)
	assert_eq(jobs.skill_pool(422).size(), 9)
	assert_false("assaulter" in jobs.skill_pool(422), "Assaulter is the mobility skill, not a pool entry")
	assert_false("assassinate" in jobs.skill_pool(422), "Assassinate is a Dark Sight sub-skill, not a pool entry")
	assert_eq(jobs.weapon_families(422), ["dagger"])
	assert_eq(jobs.creation_weapon(422), RAZOR)
	assert_false(bool(rec.playable), "SH14 #439 flips playable")
	assert_true(jobs.job_error(422).contains("not playable"), jobs.job_error(422))
	assert_false(422 in jobs.playable_jobs(), "not selectable yet")


func test_default_job_is_212_and_shadower_stays_unreachable_until_playable() -> void:
	var data := _data()
	assert_eq(_jobs(data).default_job(), 212)
	assert_false(422 in _jobs(data).playable_jobs())
	data.jobs_survivor.jobs["422"]["playable"] = true
	assert_true(422 in _jobs(data).playable_jobs(), "the flag alone makes it selectable")
	assert_eq(_jobs(data).default_job(), 212, "the pin, not the first playable job")


## Double Stab and Assaulter, in that order, once both are defined; Assaulter never enters the pool.
func test_start_skills_are_double_stab_and_assaulter_and_assaulter_is_not_in_the_pool() -> void:
	var jobs := _jobs(_data())
	assert_eq(Array(jobs.start_skills(422)), ["double_stab", "assaulter"], "the starting skill, then the mobility skill")
	assert_false("assaulter" in jobs.skill_pool(422))


func test_other_jobs_keep_their_entries_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.starting_skill(112), "power_strike")
	assert_eq(jobs.mobility_skill(112), "rush_hero")
	assert_eq(jobs.starting_skill(412), "lucky_seven")
	assert_eq(jobs.weapon_families(412), ["claw"])
	assert_eq(jobs.mobility_skill(412), "flash_jump")
	assert_eq(jobs.starting_skill(512), "flash_fist")
	assert_eq(jobs.mobility_skill(512), "dash")


# --- the pool: defined keys resolve, undefined keys stay inert --------------------------------------------------------

func test_each_pool_key_and_assaulter_is_defined_in_at_most_one_file() -> void:
	for key: String in POOL + ["assaulter", "assassinate"]:
		var lines := _defining_lines(key)
		assert_true(lines.size() <= 1, "%s is defined once at most (%s)" % [key, lines])


## The pool keys and Assaulter resolve once their tickets land (SH6-SH12). A key the shadower file defines is a Shadower skill (a
## book of the 400/420/421/422 lineage, a curated active, the mobility skill or the Dark Sight sub-skill); a key still in
## thief.json is a Thief-tree skill; an undefined one is simply not there yet. Which keys are defined is not pinned, so the
## skill tickets do not have to edit this test.
func test_a_defined_pool_key_belongs_to_the_shadower_books_and_assaulter_is_mobility() -> void:
	var defined: Dictionary = _data().skills.skills
	for key: String in POOL:
		if not defined.has(key):
			continue
		assert_true(String(defined[key].book) in BOOKS, "%s is a Shadower-lineage book skill" % key)
		if _defining_lines(key) == ["shadower"]:
			assert_eq(String(defined[key].slot), "active", "%s is an active" % key)
	if defined.has("assaulter"):
		assert_eq(String(defined.assaulter.slot), "mobility", "Assaulter is the mobility skill")
		assert_eq(String(defined.assaulter.book), "421")
		assert_eq(_defining_lines("assaulter"), ["shadower"])
	if defined.has("assassinate"):
		assert_eq(String(defined.assassinate.slot), "form_sub", "Assassinate is a Dark Sight sub-skill")
		assert_eq(_defining_lines("assassinate"), ["shadower"])
	if defined.has("ninja_ambush_shadower"):
		assert_eq(String(defined.ninja_ambush_shadower.book), "422")


func test_the_shadower_ninja_ambush_key_does_not_collide_with_night_lords() -> void:
	assert_true("ninja_ambush_shadower" in _jobs(_data()).skill_pool(422))
	assert_false("ninja_ambush" in _jobs(_data()).skill_pool(422), "SH-16: the key is ninja_ambush_shadower")
	assert_true("ninja_ambush" in _jobs(_data()).skill_pool(412), "Night Lord keeps its own")


func test_an_undefined_pool_key_is_never_offered_as_a_card_and_assaulter_is_never_a_card() -> void:
	var data := RF.quiet_data()
	var setup := RF.setup("quiet", 7, data)
	setup["job"] = 422
	var w := RunWorld.new(setup)
	var ids := Array(w.upgrades.eligible(w))
	for key: String in POOL.filter(func(k: String) -> bool: return not data.skills.skills.has(k)):
		assert_false(ids.has(key + "_new") or ids.has(key + "_rank"), "%s is not offered" % key)
	assert_false(ids.has("assaulter_new") or ids.has("assaulter_rank"), "Assaulter is never a card")


# --- the meter (meso charge) ------------------------------------------------------------------------------------------

func test_the_meter_block_is_the_spec_meso_charge_without_decay() -> void:
	var meter: Dictionary = _data().jobs_survivor.jobs["422"].meter
	assert_eq(String(meter.id), "meso_charge")
	assert_eq(int(meter.max), 10)
	assert_eq(String(meter.gain.event), "meso_picked")
	assert_eq(int(meter.gain.amount), 1)
	assert_eq(int(meter.gain.per_mesos), 600, "tier C: one pip per 600 mesos (Night Lord 1000)")
	assert_false(meter.has("decay"), "tier C SH-10: no decay, the finisher spends the charge")
	assert_eq(String(meter.per_unit.stat), "damage")
	assert_near(float(meter.per_unit.value), 0.02, 1e-9, "tier C: +2% damage per held pip")
	assert_eq(String(meter.art), "Item.wz/Special/0900.img/09000002/iconRaw")
	assert_eq(meter.keys().size(), 5, "id, max, gain, per_unit, art: nothing else")


func _drop(w: RunWorld, amount: int, dx := 0.0) -> void:
	var slot := w.pickups.spawn_meso(w.player.pos + Vector2(dx, -10.0), amount)
	w.pickups.state[slot] = PickupSystem.REST


func _changes(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "meter_changed")


## A world configured with job 422 builds the meso-charge meter from the line file: one pip per 600 mesos with the
## remainder carried, no decay, a cap of 10, `meter_changed` only on actual changes, and the wallet is the plain sum.
func test_a_shadower_world_builds_a_meso_charge_that_gains_per_600_never_decays_and_caps() -> void:
	var w := RF.quiet_world()
	w.set_job(422)
	w.drain_events()
	assert_eq(String(w.meter.config.id), "meso_charge")
	assert_eq(w.meter.snapshot(), {"id": "meso_charge", "max": 10, "value": 0, "art": "Item.wz/Special/0900.img/09000002/iconRaw"})
	_drop(w, 599)
	w.step(DT, MoveInput.new())
	assert_eq(w.meter.value, 0, "599 mesos earn nothing yet")
	assert_eq(w.meter.carry, 599)
	assert_eq(_changes(w.drain_events()).size(), 0, "no change, no event")
	_drop(w, 1)
	w.step(DT, MoveInput.new())
	assert_eq(w.meter.value, 1, "the 600th meso earns the first pip")
	assert_eq(w.meter.carry, 0)
	assert_eq(_changes(w.drain_events()), [{"type": "meter_changed", "id": "meso_charge", "value": 1, "max": 10}])
	_drop(w, 1300)
	w.step(DT, MoveInput.new())
	assert_eq(w.meter.value, 3, "1300 more is two pips and 100 carried")
	assert_eq(w.meter.carry, 100)
	for tick in 60 * 120:
		w.step(DT, MoveInput.new())
	assert_eq(w.meter.value, 3, "two minutes later nothing has decayed")
	_drop(w, 600 * 20)
	w.step(DT, MoveInput.new())
	assert_eq(w.meter.value, 10, "the meter caps at 10")
	w.drain_events()
	_drop(w, 600)
	w.step(DT, MoveInput.new())
	assert_eq(_changes(w.drain_events()).size(), 0, "a pickup at the cap changes nothing, so no event")
	assert_eq(w.mesos, 599 + 1 + 1300 + 12000 + 600, "the wallet is the plain sum: the charge never spends mesos (D7)")


func test_the_meter_stats_show_no_decay_over_a_long_hold() -> void:
	var w := RF.quiet_world()
	w.set_job(422)
	_drop(w, 600 * 4)
	w.step(DT, MoveInput.new())
	for tick in 60 * 60:
		w.step(DT, MoveInput.new())
	assert_eq(w.meter.value, 4)
	assert_eq(int(w.meter.stats().peak), 4)
	assert_near(float(w.meter.stats().mean), 4.0, 0.01, "held for the whole minute")


func test_other_jobs_meters_are_untouched() -> void:
	var f := RF.quiet_world()
	f.set_job(212)
	assert_true(f.meter.config.is_empty(), "F/P has no meter")
	var h := RF.quiet_world()
	h.set_job(112)
	assert_eq(String(h.meter.config.id), "combo", "Hero keeps Combo")
	var n := RF.quiet_world()
	n.set_job(412)
	assert_eq(int(n.meter.config.gain.per_mesos), 1000, "Night Lord keeps its own rate")
	assert_true(n.meter.config.has("decay"), "and its decay")


# --- balance rows: AP, bot scores, status catalogue -------------------------------------------------------------------

func test_the_422_ap_row_is_luk_primary_dex_secondary_with_the_400_keyframes_verbatim() -> void:
	var ap: Dictionary = _data().balance.player.ap
	assert_eq(String(ap["422"].primary), "luk")
	assert_eq(String(ap["422"].secondary), "dex")
	assert_eq(ap["422"].keyframes, ap["400"].keyframes, "the Thief row verbatim, no new tuning")
	assert_eq(String(ap["400"].primary), "luk")
	var line: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "shadower"))
	assert_true(line.balance.player.ap.has("422"), "the row is in the line file")


func test_a_shadower_spends_its_auto_ap_on_luk_and_dex() -> void:
	var w := RF.quiet_world()
	w.set_job(422)
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var row: Dictionary = w.balance.player.ap["422"]
	var dex_ap := AutoAp.secondary_ap(earned, level, float(base.dex), row.keyframes)
	assert_true(dex_ap > 0, "DEX takes its share")
	assert_eq(int(w.player_state.dex), int(base.dex) + dex_ap)
	assert_eq(int(w.player_state.luk), int(base.luk) + earned - dex_ap, "the rest goes to LUK")


func test_the_card_scores_for_the_form_the_zone_and_the_finisher_come_from_the_line_file() -> void:
	var scores: Dictionary = _data().balance.bot.card_scores
	var line: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "shadower"))
	var own: Dictionary = line.balance.bot.card_scores
	assert_eq(own.size(), 6, "dark_sight, smokescreen and meso_explosion, new and rank each")
	for key: String in ["dark_sight", "smokescreen", "meso_explosion"]:
		assert_eq(int(own[key + "_new"]), 100, key)
		assert_eq(int(own[key + "_rank"]), 74, key)
		assert_eq(int(scores[key + "_new"]), 100, "%s reaches the merged balance" % key)
		assert_eq(int(scores[key + "_rank"]), 74, key)


func test_the_venomous_stab_entry_is_stored_in_the_line_with_the_spec_numbers() -> void:
	var cat: Dictionary = _data().balance.status_bonuses
	var line: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "shadower"))
	assert_eq(line.balance.status_bonuses.keys(), ["venomous_stab"], "the line file holds its own one entry")
	assert_true(cat.has("venomous_stab"), "and it reaches the merged catalogue")
	var v: Dictionary = cat.venomous_stab
	assert_eq(String(v.kind), "poison")
	assert_eq(String(v.element), "s")
	assert_eq(v.chance, [14.0, 16.0, 18.0, 20.0, 24.0, 26.0, 28.0, 30.0])
	assert_eq(v.time, [2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0, 4.0])
	assert_eq(v.level, [4.0, 8.0, 12.0, 15.0, 19.0, 23.0, 27.0, 30.0], "tier A: Venomous Stab's rank -> poison level map")
	assert_eq(int(v.repeat_chance), 3)
	for field: String in ["chance", "time", "level"]:
		assert_eq(v[field].size(), 8, "%s is eight long (one per rank)" % field)
	var star: Dictionary = cat.venomous_star
	for field: String in ["kind", "element", "chance", "time", "level", "repeat_chance"]:
		assert_eq(v[field], star[field], "%s equals Night Lord's venomous_star (SH-13, verified level for level)" % field)
	var errors := StatusBonus.errors(cat, _data())
	assert_true(errors.is_empty(), "NL3's catalogue validation accepts it: %s" % [errors])


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_a_shadower_drop_pool_holds_daggers_only_and_thief_bit_armour() -> void:
	var families: Array = _jobs(_data()).weapon_families(422)
	var ids := EquipmentDrops.eligible(INFO.keys(), INFO, 422, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	assert_eq(weapons, [1332005, 1332007, 1332025], "the daggers of the synthetic table, the Razor included")
	assert_true(1002001 in ids, "all-job armour drops")
	assert_true(1040003 in ids, "Thief-bit armour drops")
	assert_true(1092018 in ids, "a Thief shield drops")
	assert_false(1092002 in ids, "the Warrior shield is Warrior-bit gear, never a Shadower's")
	for id: int in [1472000, 1472030, 1452000, 1462000, 1492000, 1482000, 1302008, 1312005, 1432002, 1372004]:
		assert_false(id in ids, "%d (%s) never drops for a Shadower" % [id, WeaponInfo.family(id)])


func test_a_seeded_shadower_roll_never_yields_a_non_dagger_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(422)
	var rng := _rng(427)
	var ids := INFO.keys()
	var seen := {}
	for i in 600:
		var id := EquipmentDrops.pick(ids, INFO, 422, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(ids, INFO, 422, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		if Equipment.slot_of(id) == "weapon":
			assert_eq(WeaponInfo.family(id), "dagger", "%d" % id)
	for id: int in [1332005, 1332007, 1332025, 1040003, 1092018]:
		assert_true(seen.has(id), "%d dropped in the sample" % id)
	for id: int in [1472000, 1472030, 1452000, 1462000, 1492000, 1482000, 1302008, 1312005, 1432002, 1372004, 1092002]:
		assert_false(seen.has(id), "%d never dropped" % id)


## A claw-only job (Night Lord's families, `["claw"]`) never receives a dagger: the filter is symmetric.
func test_a_night_lord_never_receives_a_dagger() -> void:
	var families: Array = _jobs(_data()).weapon_families(412)
	var ids := EquipmentDrops.eligible(INFO.keys(), INFO, 412, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	assert_eq(weapons, [1472000, 1472030])
	var rng := _rng(412)
	for i in 300:
		var id := EquipmentDrops.pick(INFO.keys(), INFO, 412, BAND, RULES, rng, families)
		assert_ne(WeaponInfo.family(id), "dagger", "%d" % id)


## The shipped drop list (every equipment_drops item that is a weapon): the families filter holds on the real ids, not only
## on the synthetic table above. Runs without the cache.
func test_the_shipped_weapon_drops_keep_daggers_only_for_a_shadower_and_never_daggers_for_a_night_lord() -> void:
	var data := _data()
	var weapons: Array = []
	for raw: Variant in data.equipment_drops.items:
		if Equipment.slot_of(int(raw)) == "weapon":
			weapons.append(int(raw))
	assert_false(weapons.is_empty(), "the shipped list has weapons")
	var info := {}
	for id: int in weapons:
		info[id] = {"reqLevel": 0, "reqJob": 8, "tuc": 7}
	var jobs := _jobs(data)
	var ids := EquipmentDrops.eligible(weapons, info, 422, [0, 999], jobs.weapon_families(422))
	var fams := {}
	for id: int in ids:
		fams[WeaponInfo.family(id)] = true
	assert_eq(fams.keys(), ["dagger"], "%s" % [fams.keys()])
	var claws := EquipmentDrops.eligible(weapons, info, 412, [0, 999], jobs.weapon_families(412))
	for id: int in weapons:
		if WeaponInfo.family(id) == "dagger":
			assert_true(id in ids, "%d (dagger) drops for a Shadower" % id)
			assert_false(id in claws, "%d (dagger) never drops for a Night Lord" % id)
		else:
			assert_false(id in ids, "%d (%s) never drops for a Shadower" % [id, WeaponInfo.family(id)])


## A Thief shield sits beside a one-handed dagger (a dagger is not two-handed), so the shipped Thief shields are worn with
## the Shadower's weapon and the existing tier C rule needs no change.
func test_a_thief_shield_is_worn_beside_a_dagger() -> void:
	assert_eq(WeaponInfo.family(1332007), "dagger")
	assert_false(WeaponInfo.is_two_handed(1332007))
	var worn := {"weapon": {"id": 1332007}}
	assert_eq(Equipment.displaced_slots(worn, 1092018), [], "wearing the shield takes nothing off")
	assert_eq(Equipment.requirement_error(INFO[1092018], {"job_id": 422}), "", "a Thief shield passes the class check")
	var drops: Array = _data().equipment_drops.items
	var shields := drops.filter(func(id: Variant) -> bool: return Equipment.slot_of(int(id)) == "shield")
	assert_false(shields.is_empty(), "the shipped list holds shields")


func test_requirement_error_accepts_thief_bit_gear_only() -> void:
	var shadower := {"job_id": 422}
	assert_eq(Equipment.requirement_error(INFO[1332007], shadower), "", "a dagger (reqJob 8, the Thief bit)")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, shadower), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 8}, shadower), "", "Thief bit")
	assert_eq(Equipment.requirement_error({"reqJob": 9}, shadower), "", "a shared Warrior-and-Thief item (the Iron Dagger)")
	for bit in [1, 2, 4, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, shadower), "reqJob", "reqJob %d is another class" % bit)
	for id: int in [1302008, 1452000, 1482000, 1372004, 1092002]:
		assert_eq(Equipment.requirement_error(INFO[id], shadower), "reqJob", "%d is another class's gear" % id)
	assert_eq(Equipment.requirement_error(INFO[1332007], {"job_id": 212}), "reqJob", "and a 212 cannot wear a Thief dagger")


## The creation Razor has reqJob 0 (tier A, Character.wz info of 1332005), so a character of any class can wear it.
func test_the_creation_razor_is_wearable_by_a_character_of_any_class() -> void:
	assert_eq(WeaponInfo.family(RAZOR), "dagger")
	for job_id: int in [0, 112, 122, 132, 212, 312, 322, 412, 422, 512, 522]:
		assert_eq(Equipment.requirement_error(INFO[RAZOR], {"job_id": job_id}), "", "job %d" % job_id)
		assert_true(Equipment.job_allows(INFO[RAZOR], job_id), "job %d" % job_id)


## Needs the real asset cache (SKIPs without it, which proves nothing). The Razor image is not in every cache (the manifest
## names it in SH1 #426), so that half SKIPs when it is missing.
func test_real_cache_the_razor_is_a_reqjob_0_dagger() -> void:
	if not require_cache_img("Character.wz/Weapon/01332005.img"):
		return
	var lib := AssetLibrary.new()
	lib.open()
	var info: Dictionary = lib.img(AvatarRenderer.part_img_path(RAZOR)).root.get("info", {})
	lib.free()
	assert_eq(int(info.get("reqJob", -1)), 0, "tier A: any class")
	assert_eq(int(info.get("reqLevel", -1)), 5)
	assert_eq(int(info.get("incPAD", -1)), 20)
	assert_eq(Equipment.requirement_error(info, {"job_id": 422}), "")
	assert_eq(Equipment.requirement_error(info, {"job_id": 212}), "")


## Needs the real asset cache. Per ADR 0007 every progression region carries its own drop band; a Shadower rolled in each band
## gets wearable gear and only daggers, and a Night Lord in the same band only claws.
func test_real_cache_each_region_drops_daggers_only_for_a_shadower() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	for raw: Variant in data.equipment_drops.items:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	assert_true(infos.has(1332010), "the Iron Dagger is in the cache")
	assert_eq(Equipment.requirement_error(infos[1332010], {"job_id": 422}), "", "a Shadower can wear the Iron Dagger (reqJob 9)")
	assert_eq(Equipment.requirement_error(infos[1332010], {"job_id": 212}), "reqJob", "a Magician cannot")
	var progression: Array = data.stages.progression
	for tier in progression.size():
		var band := EquipmentDrops.band_of(data.stages.stages[String(progression[tier])])
		var rng := _rng(427 + tier)
		var daggers := 0
		for i in 300:
			var id := EquipmentDrops.pick(data.equipment_drops.items, infos, 422, band, data.equipment_drops, rng, jobs.weapon_families(422))
			if id == 0:
				continue
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 422}), "", "%d is wearable by a Shadower" % id)
			if Equipment.slot_of(id) == "weapon":
				assert_eq(WeaponInfo.family(id), "dagger", "%d" % id)
				daggers += 1
			var nl := EquipmentDrops.pick(data.equipment_drops.items, infos, 412, band, data.equipment_drops, rng, jobs.weapon_families(412))
			if nl > 0 and Equipment.slot_of(nl) == "weapon":
				assert_eq(WeaponInfo.family(nl), "claw", "a Night Lord is never rolled %d" % nl)
		assert_true(daggers > 0, "region %s drops daggers" % progression[tier])
