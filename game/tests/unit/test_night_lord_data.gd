extends TestCase
## Night Lord's data seam (spec #383, ticket NL2 #401): the `night_lord` line is discovered from its files, its job entry
## `survivor/jobs/night_lord.json` (412, not playable yet) names the pool, Flash Jump, the claw family, the Garnier and the
## meso charge meter, its AP row, bot card scores and status-bonus catalogue come from the line file (nothing in the shared
## balance), its drops are claws only (Thief-bit gear), and its claw ammo schedule has the Lv60 Ilbi step. The pool keys
## and Flash Jump stay inert until NL6-NL10 define them; the meter block stays inert until NL4 reads it.
## Seeded RNG, fixed dt; item info is synthetic unless a test says "real cache".

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

const POOL := ["lucky_seven", "drain", "avenger", "triple_throw", "ninja_storm", "ninja_ambush", "shadow_partner",
	"shadow_meso"]
const GARNIER := 1472000
## The books a Night Lord skill may belong to (the lineage: Thief 400, Assassin 410, Hermit 411, Night Lord 412).
const BOOKS := ["400", "410", "411", "412"]
## Ammo steps of job 412 (round level, item, incPAD): tier C levels, tier A items and incPAD (Item.wz).
const STEPS := [[10, 2070001, 17, "Wolbi Throwing-Stars"], [20, 2070002, 19, "Mokbi Throwing-Stars"],
	[30, 2070003, 21, "Kumbi Throwing-Stars"], [40, 2070004, 23, "Tobi Throwing-Stars"],
	[50, 2070005, 25, "Steely Throwing-Knives"], [60, 2070006, 27, "Ilbi Throwing-Stars"]]
const CLAW := 1472007
const DAGGER := 1332007
## Synthetic item info (reqJob bits as in the v83 Item.wz): claws and daggers carry the Thief bit (8), the rest belong to
## other classes, so the family filter alone decides which Thief-bit weapons drop.
const INFO := {
	1472000: {"reqLevel": 0, "reqJob": 8, "incPAD": 10, "tuc": 7}, # Garnier (creation weapon)
	1472007: {"reqLevel": 0, "reqJob": 8, "incPAD": 16, "tuc": 7}, # Meba
	1472030: {"reqLevel": 0, "reqJob": 8, "incPAD": 40, "tuc": 7}, # claw
	1332007: {"reqLevel": 0, "reqJob": 8, "incPAD": 20, "tuc": 7}, # dagger
	1332025: {"reqLevel": 0, "reqJob": 8, "incPAD": 40, "tuc": 7}, # dagger
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

func test_night_lord_line_is_discovered_from_its_files_without_a_shared_registration() -> void:
	var lines := Array(DataRepo.lines())
	assert_true("night_lord" in lines, "discovered from its files")
	assert_false("night_lord" in DataRepo.CLASS_LINES, "no shared registration list was edited")
	assert_true(lines.find("night_lord") > lines.find("hero"), "a class line follows the Adventurer lines and hero")
	assert_eq(DataRepo.fragment_path("jobs_survivor", "night_lord", "res://data"), "res://data/survivor/jobs/night_lord.json")
	assert_eq(DataRepo.fragment_path("skills", "night_lord", "res://data"), "res://data/survivor/skills/night_lord.json")


func test_the_night_lord_line_loads_without_errors_and_adds_its_job() -> void:
	var errors := PackedStringArray()
	var d := DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	assert_true(errors.is_empty(), "%s" % [errors])
	assert_true(d.jobs_survivor.jobs.has("412"), "jobs/night_lord.json is merged into the survivor job data")
	var frag: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "night_lord"))
	assert_true(frag.has("_doc"), "the skill file names the tickets that append to it")
	assert_true(frag.has("skills"))
	assert_eq(Array(DataRepo.unknown_line_files()), [])


func test_the_shared_defaults_hold_no_night_lord_rows() -> void:
	var shared: Dictionary = DataRepo.load_json("res://data/survivor/balance.json")
	assert_false(shared.player.ap.has("412"), "the Night Lord AP row lives in jobs/night_lord.json")
	assert_false(shared.get("status_bonuses", {}).has("venomous_star"), "the catalogue lives in the line file")
	assert_false(shared.get("status_bonuses", {}).has("stunning_avenger"))
	for key: String in ["shadow_partner_new", "shadow_partner_rank"]:
		assert_false(shared.bot.card_scores.has(key), "%s lives in the line file" % key)
	assert_false(DataRepo.load_json("res://data/survivor/jobs.json").jobs.has("412"), "no shared job entry")


## No other line's file names job 412 or its balance rows: the class touches no other class's file.
func test_no_other_line_file_names_night_lord_rows() -> void:
	for line: String in DataRepo.lines():
		var path := DataRepo.fragment_path("jobs_survivor", line)
		if line == "night_lord" or not FileAccess.file_exists(path):
			continue
		var frag: Dictionary = DataRepo.load_json(path)
		var balance: Dictionary = frag.get("balance", {})
		assert_false(frag.get("jobs", {}).has("412"), "%s names no Night Lord job entry" % line)
		assert_false(balance.get("player", {}).get("ap", {}).has("412"), "%s has no 412 AP row" % line)
		assert_false(balance.get("status_bonuses", {}).has("venomous_star"), "%s has no Night Lord catalogue" % line)


# --- the job entry ----------------------------------------------------------------------------------------------------

func test_job_412_has_the_spec_fields_and_is_not_playable() -> void:
	var jobs := _jobs(_data())
	var rec := jobs.job(412)
	assert_eq(String(rec.name), "Night Lord")
	assert_eq(jobs.starting_skill(412), "lucky_seven")
	assert_eq(jobs.mobility_skill(412), "flash_jump")
	assert_eq(jobs.skill_pool(412), POOL)
	assert_eq(jobs.skill_pool(412).size(), 8)
	assert_false("flash_jump" in jobs.skill_pool(412), "Flash Jump is the mobility skill, not a pool entry")
	assert_eq(jobs.weapon_families(412), ["claw"])
	assert_eq(jobs.creation_weapon(412), GARNIER)
	assert_false(bool(rec.playable), "NL12 flips playable")
	assert_true(jobs.job_error(412).contains("not playable"), "a tool cannot choose it yet")
	assert_false(412 in jobs.playable_jobs(), "not selectable")


func test_default_job_is_212_and_night_lord_is_not_selectable() -> void:
	var data := _data()
	var jobs := _jobs(data)
	assert_eq(jobs.default_job(), 212)
	assert_false(412 in jobs.playable_jobs())
	data.jobs_survivor.jobs["412"]["playable"] = true
	assert_eq(_jobs(data).default_job(), 212, "the pin, not the first playable job, even when 412 becomes playable")


func test_start_skills_are_lucky_seven_and_flash_jump_and_flash_jump_is_not_in_the_pool() -> void:
	var jobs := _jobs(_data())
	assert_eq(Array(jobs.start_skills(412)), ["lucky_seven", "flash_jump"], "the starting skill, then the mobility skill")
	assert_false("flash_jump" in jobs.skill_pool(412))


func test_other_jobs_keep_their_entries_unchanged() -> void:
	var jobs := _jobs(_data())
	assert_eq(jobs.starting_skill(212), "energy_bolt")
	assert_eq(jobs.weapon_families(212), ["wand", "staff"])
	assert_eq(jobs.starting_skill(112), "power_strike")
	assert_eq(jobs.mobility_skill(112), "rush_hero")
	assert_eq(jobs.starting_skill(312), "arrow_blow")
	assert_eq(jobs.mobility_skill(312), "")
	assert_eq(jobs.starting_skill(512), "flash_fist")
	assert_eq(jobs.mobility_skill(512), "dash")


# --- the pool: defined keys resolve, undefined keys stay inert --------------------------------------------------------

func test_each_pool_key_and_flash_jump_is_defined_in_at_most_one_file() -> void:
	for key: String in POOL + ["flash_jump"]:
		var lines := _defining_lines(key)
		assert_true(lines.size() <= 1, "%s is defined once at most (%s)" % [key, lines])


## The pool keys and Flash Jump resolve once their tickets land (NL6-NL10): a defined key is a Night Lord skill (a book of
## the 400/410/411/412 lineage, a curated active or the mobility skill); an undefined one is simply not there yet.
func test_a_defined_pool_key_belongs_to_the_night_lord_books_and_flash_jump_is_mobility() -> void:
	var defined: Dictionary = _data().skills.skills
	for key: String in POOL:
		if not defined.has(key):
			continue
		assert_true(String(defined[key].book) in BOOKS, "%s is a Night Lord book skill" % key)
		assert_eq(String(defined[key].slot), "active", "%s is an active" % key)
	if defined.has("flash_jump"):
		assert_eq(String(defined.flash_jump.slot), "mobility", "Flash Jump is the mobility skill")
		assert_eq(String(defined.flash_jump.book), "411")
		assert_eq(_defining_lines("flash_jump"), ["night_lord"])


func test_lucky_seven_and_drain_were_moved_into_night_lord_json() -> void:
	var data := _data()
	for key: String in ["lucky_seven", "drain"]:
		assert_true(data.skills.skills.has(key), "%s exists today" % key)
		var lines := _defining_lines(key)
		assert_eq(lines, ["night_lord"], "%s moved out of thief.json (NL7 #406)" % key)


func test_an_undefined_pool_key_is_never_offered_as_a_card_and_flash_jump_is_never_a_card() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["412"]["playable"] = true
	var setup := RF.setup("quiet", 7, data)
	setup["job"] = 412
	var w := RunWorld.new(setup)
	var ids := Array(w.upgrades.eligible(w))
	for key: String in POOL.filter(func(k: String) -> bool: return not data.skills.skills.has(k)):
		assert_false(ids.has(key + "_new") or ids.has(key + "_rank"), "%s is not offered" % key)
	assert_false(ids.has("flash_jump_new") or ids.has("flash_jump_rank"), "Flash Jump is never a card")


# --- the meter (meso charge) ------------------------------------------------------------------------------------------

func test_the_meter_block_is_the_spec_meso_charge() -> void:
	var meter: Dictionary = _data().jobs_survivor.jobs["412"].meter
	assert_eq(String(meter.id), "meso_charge")
	assert_eq(int(meter.max), 10)
	assert_eq(String(meter.gain.event), "meso_picked")
	assert_eq(int(meter.gain.amount), 1)
	assert_eq(int(meter.gain.per_mesos), 1000, "tier C: one pip per 1000 mesos")
	assert_near(float(meter.decay.interval), 6.0, 1e-9, "tier C: one pip leaves every 6 s")
	assert_eq(int(meter.decay.amount), 1)
	assert_eq(String(meter.per_unit.stat), "damage")
	assert_near(float(meter.per_unit.value), 0.03, 1e-9, "tier C: +3% damage per held pip")
	assert_eq(String(meter.art), "Item.wz/Special/0900.img/09000002/iconRaw")


## The block is data until NL4: a 412 round carries the meter config, and without the `meso_picked` rule in PlayerMeter
## nothing moves it (Combo and every other job are untouched).
func test_the_meter_block_is_inert_until_nl4_reads_it() -> void:
	var w := RF.quiet_world()
	w.set_job(412)
	assert_eq(String(w.meter.config.id), "meso_charge")
	assert_eq(w.meter.snapshot().max, 10)
	assert_eq(w.meter.value, 0)
	w.meter.gain("cast_landed", w.events)
	assert_eq(w.meter.value, 0, "a cast earns no charge")
	var f := RF.quiet_world()
	f.set_job(212)
	assert_true(f.meter.config.is_empty(), "F/P has no meter")
	var h := RF.quiet_world()
	h.set_job(112)
	assert_eq(String(h.meter.config.id), "combo", "Hero keeps Combo")


# --- balance rows: AP, bot scores, status catalogue -------------------------------------------------------------------

func test_the_412_ap_row_is_luk_primary_dex_secondary_with_the_400_keyframes_verbatim() -> void:
	var ap: Dictionary = _data().balance.player.ap
	assert_eq(String(ap["412"].primary), "luk")
	assert_eq(String(ap["412"].secondary), "dex")
	assert_eq(ap["412"].keyframes, ap["400"].keyframes, "the Thief row verbatim, no new tuning")
	assert_eq(String(ap["400"].primary), "luk")
	var line: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "night_lord"))
	assert_true(line.balance.player.ap.has("412"), "the row is in the line file")


func test_a_night_lord_spends_its_auto_ap_on_luk_and_dex() -> void:
	var w := RF.quiet_world()
	w.set_job(412)
	var base: Dictionary = w.balance.player.stats
	for lv in 20:
		w._gain_exp(w.progression.exp_to_next())
	var level := int(w.player_state.level)
	var earned := (level - 1) * int(w.balance.player.ap_per_level)
	var row: Dictionary = w.balance.player.ap["412"]
	var dex_ap := AutoAp.secondary_ap(earned, level, float(base.dex), row.keyframes)
	assert_true(dex_ap > 0, "DEX takes its share")
	assert_eq(int(w.player_state.dex), int(base.dex) + dex_ap)
	assert_eq(int(w.player_state.luk), int(base.luk) + earned - dex_ap, "the rest goes to LUK")


func test_the_shadow_partner_card_scores_come_from_the_line_file() -> void:
	var data := _data()
	var scores: Dictionary = data.balance.bot.card_scores
	assert_eq(int(scores.shadow_partner_new), 100)
	assert_eq(int(scores.shadow_partner_rank), 74)
	var line: Dictionary = DataRepo.load_json(DataRepo.fragment_path("jobs_survivor", "night_lord"))
	assert_eq(int(line.balance.bot.card_scores.shadow_partner_new), 100)
	assert_eq(int(line.balance.bot.card_scores.shadow_partner_rank), 74)
	assert_eq(line.balance.bot.card_scores.size(), 16, "NL11 #410 scores all eight pool skills explicitly (the summon needs it, the rest are a guard)")
	for key: String in ["lucky_seven", "drain", "avenger", "triple_throw", "ninja_storm", "ninja_ambush", "shadow_meso"]:
		assert_eq(int(line.balance.bot.card_scores[key + "_new"]), 100, key)
		assert_eq(int(line.balance.bot.card_scores[key + "_rank"]), 74, key)


func test_the_status_catalogue_is_stored_in_the_line_with_the_spec_numbers() -> void:
	var cat: Dictionary = _data().balance.status_bonuses
	assert_eq(cat.keys().size(), 2)
	var v: Dictionary = cat.venomous_star
	assert_eq(String(v.kind), "poison")
	assert_eq(String(v.element), "s")
	assert_eq(v.chance, [14.0, 16.0, 18.0, 20.0, 24.0, 26.0, 28.0, 30.0])
	assert_eq(v.time, [2.0, 2.0, 3.0, 3.0, 3.0, 4.0, 4.0, 4.0])
	assert_eq(v.level, [4.0, 8.0, 12.0, 15.0, 19.0, 23.0, 27.0, 30.0], "tier A: Venomous Star's rank -> poison level map")
	assert_eq(int(v.repeat_chance), 3)
	var s: Dictionary = cat.stunning_avenger
	assert_eq(String(s.kind), "stun")
	assert_eq(s.chance, [20.0, 24.0, 28.0, 32.0, 36.0, 40.0, 45.0, 50.0])
	assert_near(float(s.time), 1.5, 1e-9)
	assert_eq(int(s.repeat_chance), 4)
	for id: String in cat:
		for field: String in ["chance", "time", "level"]:
			if cat[id].get(field) is Array:
				assert_eq(cat[id][field].size(), 8, "%s.%s is eight long (one per rank)" % [id, field])
		for p: Variant in cat[id].chance:
			assert_true(float(p) >= 0.0 and float(p) <= 100.0, "%s chance in range" % id)


# --- weapon families and drops ----------------------------------------------------------------------------------------

func test_a_night_lord_drop_pool_holds_claws_only_and_thief_bit_armour() -> void:
	var families: Array = _jobs(_data()).weapon_families(412)
	var ids := EquipmentDrops.eligible(INFO.keys(), INFO, 412, BAND, families)
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	assert_eq(weapons, [1472000, 1472007, 1472030], "the claws of the synthetic table")
	assert_true(1002001 in ids, "all-job armour drops")
	assert_true(1040003 in ids, "Thief-bit armour drops")
	assert_false(1092002 in ids, "the Warrior shield is Warrior-bit gear, never a Night Lord's")
	for id: int in [1332007, 1332025, 1452000, 1462000, 1492000, 1482000, 1302008, 1312005, 1432002, 1372004]:
		assert_false(id in ids, "%d (%s) never drops for a Night Lord" % [id, WeaponInfo.family(id)])


func test_a_seeded_night_lord_roll_never_yields_a_non_claw_weapon() -> void:
	var families: Array = _jobs(_data()).weapon_families(412)
	var rng := _rng(401)
	var ids := INFO.keys()
	var seen := {}
	for i in 400:
		var id := EquipmentDrops.pick(ids, INFO, 412, BAND, RULES, rng, families) if i % 2 == 0 \
			else EquipmentDrops.pick_boss(ids, INFO, 412, BAND, RULES, rng, families)
		assert_true(id > 0)
		seen[id] = true
		if Equipment.slot_of(id) == "weapon":
			assert_eq(WeaponInfo.family(id), "claw", "%d" % id)
	for id: int in [1472000, 1472007, 1472030]:
		assert_true(seen.has(id), "%d dropped in the sample" % id)


## A dagger job (Shadower's families, `["dagger"]`) never receives a claw: the filter is symmetric.
func test_a_dagger_family_filter_never_receives_a_claw() -> void:
	var ids := EquipmentDrops.eligible(INFO.keys(), INFO, 422, BAND, ["dagger"])
	var weapons := ids.filter(func(id: int) -> bool: return Equipment.slot_of(id) == "weapon")
	weapons.sort()
	assert_eq(weapons, [1332007, 1332025])


## The shipped drop list (every equipment_drops item that is a weapon): the families filter holds on the real ids, not only
## on the synthetic table above. Runs without the cache.
func test_the_shipped_weapon_drops_keep_claws_only_for_a_night_lord() -> void:
	var data := _data()
	var weapons: Array = []
	for raw: Variant in data.equipment_drops.items:
		if Equipment.slot_of(int(raw)) == "weapon":
			weapons.append(int(raw))
	assert_false(weapons.is_empty(), "the shipped list has weapons")
	var info := {}
	for id: int in weapons:
		info[id] = {"reqLevel": 0, "reqJob": 8, "tuc": 7}
	var families: Array = _jobs(data).weapon_families(412)
	var ids := EquipmentDrops.eligible(weapons, info, 412, BAND, families)
	var fams := {}
	for id: int in ids:
		fams[WeaponInfo.family(id)] = true
	assert_eq(fams.keys(), ["claw"], "%s" % [fams.keys()])
	for id: int in weapons:
		if WeaponInfo.family(id) == "claw":
			assert_true(id in ids, "%d (claw) drops for a Night Lord" % id)
		else:
			assert_false(id in ids, "%d (%s) never drops for a Night Lord" % [id, WeaponInfo.family(id)])
	assert_true(GARNIER in weapons, "the creation Garnier is in the drop list")


func test_requirement_error_accepts_thief_bit_gear_only() -> void:
	var night_lord := {"job_id": 412}
	assert_eq(Equipment.requirement_error(INFO[GARNIER], night_lord), "", "the Garnier (reqJob 8, the Thief bit)")
	assert_eq(Equipment.requirement_error({"reqJob": 0}, night_lord), "", "all jobs")
	assert_eq(Equipment.requirement_error({"reqJob": 8}, night_lord), "", "Thief bit")
	for bit in [1, 2, 4, 16]:
		assert_eq(Equipment.requirement_error({"reqJob": bit}, night_lord), "reqJob", "reqJob %d is another class" % bit)
	for id: int in [1302008, 1452000, 1482000, 1372004, 1092002]:
		assert_eq(Equipment.requirement_error(INFO[id], night_lord), "reqJob", "%d is another class's gear" % id)
	assert_eq(Equipment.requirement_error(INFO[GARNIER], {"job_id": 212}), "reqJob", "and a 212 cannot wear the Garnier")


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_garnier_is_wearable_and_each_tier_drops_claws_only() -> void:
	if not require_cache():
		return
	var data := _data()
	var jobs := _jobs(data)
	var lib := AssetLibrary.new()
	lib.open()
	var infos := {}
	var ids: Array = data.equipment_drops.items.duplicate()
	ids.append(jobs.creation_weapon(412))
	for raw: Variant in ids:
		var img := lib.img(AvatarRenderer.part_img_path(int(raw)))
		if img != null:
			infos[int(raw)] = img.root.get("info", {})
	lib.free()
	assert_true(infos.has(GARNIER), "the Garnier is in the cache")
	assert_eq(WeaponInfo.family(GARNIER), "claw")
	assert_eq(int(infos[GARNIER].get("reqJob", 0)), 8, "tier A: the Thief bit")
	assert_eq(Equipment.requirement_error(infos[GARNIER], {"job_id": 412}), "", "a Night Lord can wear the creation claw")
	assert_eq(Equipment.requirement_error(infos[GARNIER], {"job_id": 312}), "reqJob", "a Bowmaster cannot")
	var ed: Dictionary = data.equipment_drops
	for tier in data.stages.tiers.size():
		var band := EquipmentDrops.band_of(data.stages, tier)
		var rng := _rng(401 + tier)
		var claws := 0
		for i in 300:
			var id := EquipmentDrops.pick(ed.items, infos, 412, band, ed, rng, jobs.weapon_families(412))
			assert_true(id > 0)
			assert_eq(Equipment.requirement_error(infos[id], {"job_id": 412}), "", "%d is wearable by a Night Lord" % id)
			if Equipment.slot_of(id) == "weapon":
				assert_eq(WeaponInfo.family(id), "claw", "%d" % id)
				claws += 1
		assert_true(claws > 0, "tier %d drops claws" % (tier + 1))


# --- ammo: the claw schedule and its Lv60 Ilbi step -------------------------------------------------------------------

func _schedule(data: Dictionary) -> Dictionary:
	for s: Dictionary in data.ammo.schedules:
		if int(s.job) == 412:
			return s
	return {}


func test_the_412_schedule_has_six_strictly_increasing_steps_ending_with_ilbi_at_60() -> void:
	var data := _data()
	var schedule := _schedule(data)
	assert_eq(String(schedule.family), "claw")
	assert_eq(schedule.steps.size(), STEPS.size())
	var last_level := 1
	for i in STEPS.size():
		var step: Dictionary = schedule.steps[i]
		assert_eq(int(step.level), STEPS[i][0], "step %d level" % i)
		assert_eq(int(step.item), STEPS[i][1], "step %d item" % i)
		assert_eq(String(step.tier), "C", "step %d is tier C" % i)
		assert_true(int(step.level) > last_level, "levels strictly increase")
		last_level = int(step.level)
	assert_eq(int(schedule.steps[-1].item), 2070006, "the last step is Ilbi Throwing-Stars")
	assert_eq(int(schedule.steps[-1].level), 60)
	assert_true(2070006 in Ammo.item_ids(data.ammo), "Ammo.item_ids names Ilbi again")
	assert_eq(Ammo.item_ids(data.ammo).size(), 18, "18 ammo items (B3's 17 plus Ilbi)")


func test_the_lookup_gives_the_exact_star_at_each_level_for_a_night_lord_claw_only() -> void:
	var ammo: Dictionary = _data().ammo
	assert_eq(Ammo.item_for(ammo, "claw", 412, 1), 2070015, "starts on A Beginner Thief's Throwing Stars")
	for row: Array in STEPS:
		assert_eq(Ammo.item_for(ammo, "claw", 412, row[0] - 1) != row[1], true, "not before Lv%d" % row[0])
		assert_eq(Ammo.item_for(ammo, "claw", 412, row[0]), row[1], "Lv%d" % row[0])
	assert_eq(Ammo.item_for(ammo, "claw", 412, 99), 2070006, "Ilbi from Lv60 on")
	assert_eq(Ammo.item_for(ammo, "dagger", 412, 99), 0, "a dagger in a Night Lord's hand has no ammo")
	assert_eq(Ammo.item_for(ammo, "claw", 400, 99), 2070015, "no other job borrows the schedule")
	assert_eq(Ammo.item_for(ammo, "claw", 422, 99), 2070015)


func _world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	var setup := RF.with_basic_attack(RF.setup("quiet", 401, data))
	setup.equipment_info.merge({CLAW: {"incPAD": 16, "attackSpeed": 6, "tuc": 7},
		DAGGER: {"incPAD": 20, "attackSpeed": 4, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	var w := RunWorld.new(setup)
	assert_eq(w.wear_new_item(CLAW), "")
	assert_eq(w.wear_new_item(DAGGER), "")
	assert_eq(w.equip_item(_ids(w).find(CLAW)), "")
	RF.place_player(w, 400)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
	w.player.facing = 1
	w.god = true
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	RF.change_job_bare(w, 412)
	w.drain_events()
	return w


func _ids(w: RunWorld) -> Array:
	return w.equipment.inventory.map(func(item: Dictionary) -> int: return int(item.id))


func _upgrades(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")


## Plays the round to `level` with real EXP drops (the ordinary level-up path), collecting every ammo_upgraded.
func _level_to(w: RunWorld, level: int, notices: Array) -> void:
	while w.progression.level < level:
		w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		for tick in 120:
			w.step(DT, MoveInput.new())
			BotInput.auto_choose(w, false)
		notices.append_array(_upgrades(w))


func test_a_night_lord_round_starts_on_the_beginner_stars_and_announces_nothing() -> void:
	var w := _world()
	assert_eq(w.progression.level, 1)
	assert_eq(w.ammo_id(), 2070015)
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(_upgrades(w).size(), 0, "no notice at the start of the round")


func test_the_stars_step_at_10_20_30_40_50_and_60_with_one_notice_each() -> void:
	var w := _world()
	var notices: Array = []
	_level_to(w, 9, notices)
	assert_eq(w.ammo_id(), 2070015)
	assert_eq(notices.size(), 0, "nothing before Lv10")
	_level_to(w, 60, notices)
	assert_eq(notices.size(), 6, "Wolbi, Mokbi, Kumbi, Tobi, Steely and Ilbi: one notice per step, no repeats")
	var from_item := 2070015
	for i in mini(notices.size(), STEPS.size()):
		assert_eq(notices[i].level, STEPS[i][0], "the step's own round level")
		assert_eq(notices[i].from_item_id, from_item)
		assert_eq(notices[i].item_id, STEPS[i][1])
		assert_eq(notices[i].family, "claw")
		from_item = STEPS[i][1]
	assert_eq(w.ammo_id(), 2070006, "Ilbi Throwing-Stars at Lv60")
	_level_to(w, 62, notices)
	assert_eq(notices.size(), 6, "nothing after the last step")


func test_each_step_is_announced_exactly_once_when_the_level_changes() -> void:
	var w := _world()
	for row: Array in [[9, 2070015, 0], [10, 2070001, 1], [19, 2070001, 0], [20, 2070002, 1], [49, 2070004, 1],
			[50, 2070005, 1], [59, 2070005, 0], [60, 2070006, 1], [61, 2070006, 0]]:
		w.progression.level = row[0]
		w.refresh_player_stats()
		assert_eq(w.ammo_id(), row[1], "Lv %d" % row[0])
		assert_eq(_upgrades(w).size(), row[2], "Lv %d notices" % row[0])
		w.refresh_player_stats()
		assert_eq(_upgrades(w).size(), 0, "a second refresh at Lv %d announces nothing" % row[0])


func test_the_notice_text_is_the_v83_name_in_the_ammo_noun() -> void:
	var ammo: Dictionary = _data().ammo
	assert_eq(Ammo.notice(Ammo.noun(ammo, "claw"), "Wolbi Throwing-Stars"), "Your throwing stars are now Wolbi Throwing-Stars")
	assert_eq(Ammo.notice(Ammo.noun(ammo, "claw"), "Ilbi Throwing-Stars"), "Your throwing stars are now Ilbi Throwing-Stars")


func test_a_dagger_in_a_night_lords_hand_never_steps() -> void:
	var w := _world()
	assert_eq(w.equip_item(_ids(w).find(DAGGER)), "")
	w.drain_events()
	var notices: Array = []
	_level_to(w, 61, notices)
	assert_eq(w.ammo_id(), 0, "a dagger fires nothing")
	assert_eq(notices.size(), 0, "and never announces a step")


func test_the_incpad_of_the_current_star_adds_to_ranged_attack_only() -> void:
	var w := _world()
	w.setup.ammo_info = RF.ammo_info()
	var plain := w.weapon_attack(true)
	assert_eq(w.weapon_attack(false), plain - 15.0, "the Lv1 stars add +15 to a ranged attack only")
	for row: Array in STEPS:
		w.progression.level = row[0]
		w.refresh_player_stats()
		assert_eq(w.weapon_attack(true), w.weapon_attack(false) + float(row[2]), "%s: incPAD +%d" % [row[3], row[2]])
	w.progression.level = 60
	w.refresh_player_stats()
	assert_eq(w.weapon_attack(true) - w.weapon_attack(false), 27.0, "Ilbi adds +27")


func test_the_shot_sprite_is_the_current_stars_bullet() -> void:
	for level in [1, 10, 30, 50, 60]:
		var w := _world()
		w.progression.level = level
		w.refresh_player_stats()
		assert_true(w.learn_skill("lucky_seven"))
		RF.put_mob(w, 1110100, w.player.pos.x + 80, 190, 10000)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.drain_events()
		w.runner.step(DT, w)
		var seen := 0
		for i in w.projectiles.capacity():
			if w.projectiles.active[i] != 0:
				seen += 1
				assert_eq(w.projectiles.paths[w.projectiles.visual[i]], Ammo.bullet_path(w.ammo_id()), "Lv %d shot" % level)
		assert_true(seen >= 1, "Lv %d: a star in flight" % level)


func test_another_job_holding_a_claw_never_steps() -> void:
	var w := _world()
	RF.change_job_bare(w, 212)
	w.drain_events()
	var notices: Array = []
	_level_to(w, 61, notices)
	assert_eq(w.ammo_id(), 2070015, "the F/P Arch Mage with a claw keeps the Beginner's stars")
	assert_eq(notices.size(), 0)


## Needs the real asset cache (SKIPs without it, which proves nothing).
func test_real_cache_the_star_items_and_their_string_names_exist() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var data := _data()
	var missing := PackedStringArray()
	var info := DataRepo.ammo_info(data.ammo, func(path: String) -> Dictionary:
		var img := lib.img(path)
		return img.root if img != null else {}, missing)
	assert_eq(missing, PackedStringArray(), "the manifest imports every ammo item, Ilbi included")
	assert_eq(info.size(), 18)
	assert_eq(info[2070015].incPAD, 15, "tier A: Item.wz")
	var last := 15
	for row: Array in STEPS:
		assert_true(info.has(row[1]), "item %d exists" % row[1])
		assert_eq(info[row[1]].incPAD, row[2], "incPAD of %d" % row[1])
		assert_true(int(info[row[1]].incPAD) > last, "incPAD strictly increases")
		last = int(info[row[1]].incPAD)
		var found: Variant = lib.find(InventoryModel.name_path(row[1]))
		assert_eq(String(found), row[3], "String.wz name of %d" % row[1])
		assert_eq(Ammo.notice(Ammo.noun(data.ammo, "claw"), String(found)), "Your throwing stars are now %s" % row[3])
		assert_true(lib.anim(Ammo.bullet_path(row[1])) != null, "%d has a flight animation" % row[1])
