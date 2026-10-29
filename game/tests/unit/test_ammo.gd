extends TestCase
## Endless ammo (spec #151 #155): which ammo item a weapon family, job and level use (Ammo over survivor/ammo.json), the
## data file's own rules, and the upgrade notice text. The world side (events, W.Att, projectiles) is
## test_ranged_basic_attack.

var _data: Dictionary
var _jobs: JobTree

## Exact-job schedules of survivor/ammo.json (ruling D9, spec #332): job -> [family, [[round level, item, incPAD], ...]].
## incPAD is tier A (Item.wz); the levels are tier C (the spec's table).
const SCHEDULES := {
	312: ["bow", [[1, 2060000, 0], [15, 2060001, 1], [30, 2060002, 2], [45, 2060003, 4]]],
	322: ["crossbow", [[1, 2061000, 0], [15, 2061001, 1], [30, 2061002, 2], [45, 2061003, 4]]],
	412: ["claw", [[1, 2070015, 15], [10, 2070001, 17], [20, 2070002, 19], [30, 2070003, 21], [40, 2070004, 23],
		[50, 2070005, 25]]],
	522: ["gun", [[1, 2330000, 10], [18, 2330001, 12], [35, 2330002, 14]]],
}


func before_each() -> void:
	_data = DataRepo.load_all()
	_jobs = JobTree.from_data(_data.jobs, _data.jobs_survivor)


func _item(family: String, job: int, level: int) -> int:
	return Ammo.item_for(_data.ammo, family, job, level)


func test_every_ranged_family_starts_with_its_v83_ammo() -> void:
	assert_eq(_item("claw", 0, 1), 2070015, "A Beginner Thief's Throwing Stars")
	assert_eq(_item("bow", 0, 1), 2060000, "Arrow for Bow")
	assert_eq(_item("crossbow", 0, 1), 2061000, "Arrow for Crossbow")
	assert_eq(_item("gun", 0, 1), 2330000, "Bullet")
	assert_eq(_item("sword", 0, 1), 0, "a melee family has no ammo")
	assert_eq(_item("", 0, 1), 0, "bare hands neither")
	assert_eq(_item("sword", 312, 60), 0, "a scheduled job holding a melee weapon fires nothing")


func test_each_exact_job_steps_at_the_rounds_levels() -> void:
	for job: int in SCHEDULES:
		var family: String = SCHEDULES[job][0]
		var steps: Array = SCHEDULES[job][1]
		for i in steps.size():
			var level: int = steps[i][0]
			assert_eq(_item(family, job, level), steps[i][1], "job %d at Lv %d" % [job, level])
			if i > 0:
				assert_eq(_item(family, job, level - 1), steps[i - 1][1], "job %d one level before Lv %d" % [job, level])
		assert_eq(_item(family, job, int(steps[-1][0])), steps[-1][1], "job %d reaches its known step" % job)
		assert_eq(_item(family, job, 1), steps[0][1], "job %d starts the round on the family's start ammo" % job)


func test_the_bowmaster_steps_arrow_bronze_steel_red() -> void:
	var want := {1: 2060000, 14: 2060000, 15: 2060001, 29: 2060001, 30: 2060002, 44: 2060002, 45: 2060003, 70: 2060003}
	for level: int in want:
		assert_eq(_item("bow", 312, level), want[level], "Bowmaster Lv %d" % level)


func test_no_other_job_borrows_a_schedule_and_nothing_is_inherited() -> void:
	for job in [0, 100, 212, 300, 310, 311, 320, 400, 410, 411, 500, 510, 520, 521]:
		assert_eq(_item("bow", job, 99), 2060000, "job %d holding a bow keeps the plain arrow" % job)
		assert_eq(_item("claw", job, 99), 2070015, "job %d holding a claw keeps the Beginner's stars" % job)
		assert_eq(_item("gun", job, 99), 2330000, "job %d holding a gun keeps the Bullet" % job)
	assert_eq(_item("crossbow", 312, 99), 2061000, "a Bowmaster holding a crossbow: the Marksman's schedule is not his")
	assert_eq(_item("bow", 322, 99), 2060000, "a Marksman holding a bow")
	assert_eq(_item("claw", 312, 99), 2070015, "another job's schedule never touches a different family")
	assert_eq(_item("bow", 412, 99), 2060000)


func test_the_lookup_has_no_job_lineage_walk() -> void:
	# Branch 310 is Bowmaster's ancestor; the old rule let a descendant inherit its branch's schedule. The exact-job rule
	# gives 311 and 310 nothing, and 312 only its own steps.
	assert_eq(_item("bow", 311, 60), 2060000)
	assert_eq(_item("bow", 312, 60), 2060003)


func test_the_data_file_is_consistent() -> void:
	var ammo: Dictionary = _data.ammo
	assert_eq(int(ammo.format), 2, "format 2: schedules are keyed by the exact job")
	for family: String in WeaponInfo.RANGED_FAMILIES:
		var f: Dictionary = ammo.families.get(family, {})
		assert_true(int(f.get("start", 0)) > 0, "%s has a starting ammo" % family)
		assert_true(String(f.get("noun", "")) != "", "%s has a noun for the notice" % family)
		var shot: Dictionary = f.get("projectile", {})
		for key: String in ["speed", "radius", "overshoot"]:
			assert_true(float(shot.get(key, 0.0)) > 0.0, "%s projectile %s" % [family, key])
		assert_true(shot.has("rotate"))
	var seen := {}
	for schedule: Dictionary in ammo.schedules:
		assert_false(schedule.has("branch"), "a schedule keyed by branch is a data error (format 1)")
		assert_true(schedule.has("job"), "a schedule names its exact job")
		var job := int(schedule.get("job", 0))
		assert_true(_jobs.job(job).size() > 0, "job %d is a job" % job)
		assert_true(WeaponInfo.RANGED_FAMILIES.has(String(schedule.family)))
		var key := "%d:%s" % [job, schedule.family]
		assert_false(seen.has(key), "one schedule per job and family: " + key)
		seen[key] = true
		var last := 1
		for step: Dictionary in schedule.steps:
			assert_true(int(step.level) > last, "levels ascend and start after Lv1 (the family start covers Lv1)")
			last = int(step.level)
			assert_true(String(step.tier) in ["A", "B", "C"], "every step carries its provenance tier")
	for job: int in SCHEDULES:
		assert_true(seen.has("%d:%s" % [job, SCHEDULES[job][0]]), "job %d has its schedule" % job)
	var ids := Ammo.item_ids(ammo)
	for id in [2070015, 2070001, 2070005, 2060000, 2060003, 2061000, 2061003, 2330000, 2330002]:
		assert_true(id in ids, "%d is an ammo item the setup loads" % id)


func test_a_schedule_carrying_a_branch_is_rejected() -> void:
	var bad := {"families": _data.ammo.families, "schedules": [{"branch": 310, "family": "bow", "steps": [{"level": 30,
		"item": 2060001, "tier": "C"}]}]}
	assert_true(Ammo.schedule_errors(bad).size() > 0, "format 1 branch key")
	assert_eq(Ammo.schedule_errors(_data.ammo), PackedStringArray(), "the shipped data has none")
	var no_job := {"families": _data.ammo.families, "schedules": [{"family": "bow", "steps": []}]}
	assert_true(Ammo.schedule_errors(no_job).size() > 0, "a schedule without a job")


func test_the_bullet_animation_is_the_items_own_node() -> void:
	assert_eq(Ammo.bullet_path(2070001), "Item.wz/Consume/0207.img/02070001/bullet")
	assert_eq(Ammo.bullet_path(2060000), "Item.wz/Consume/0206.img/02060000/bullet")
	assert_eq(Ammo.bullet_path(2330002), "Item.wz/Consume/0233.img/02330002/bullet")


func test_ammo_info_reads_incpad_from_the_item_imgs_and_reports_absent_items() -> void:
	var imgs := {
		"Item.wz/Consume/0207.img": {"02070001": {"info": {"incPAD": 17, "slotMax": 500}}, "02070015": {"info": {"incPAD": 15}}},
		"Item.wz/Consume/0206.img": {"02060000": {"info": {"price": 0, "slotMax": 2000}}},
	}
	var missing := PackedStringArray()
	var info := DataRepo.ammo_info(_data.ammo, func(path: String) -> Dictionary: return imgs.get(path, {}), missing)
	assert_eq(info[2070001], {"incPAD": 17})
	assert_eq(info[2070015], {"incPAD": 15})
	assert_eq(info[2060000], {"incPAD": 0}, "Arrow for Bow has no incPAD node: 0")
	assert_false(info.has(2070005), "an absent node is left out")
	assert_true("Item.wz/Consume/0207.img/02070005" in missing)
	assert_eq(info.size() + missing.size(), Ammo.item_ids(_data.ammo).size())


func test_the_real_cache_carries_every_ammo_item() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var missing := PackedStringArray()
	var info := DataRepo.ammo_info(_data.ammo, func(path: String) -> Dictionary:
		var img := lib.img(path)
		return img.root if img != null else {}, missing)
	assert_eq(missing, PackedStringArray(), "the manifest imports every ammo item")
	assert_eq(info[2070015].incPAD, 15, "tier A: Item.wz")
	assert_eq(info[2330002].incPAD, 14)
	assert_eq(info[2060003].incPAD, 4)
	# Every scheduled item exists with the spec's incPAD, strictly increasing along each schedule (tier A).
	for job: int in SCHEDULES:
		var last_pad := -1
		for step: Array in SCHEDULES[job][1]:
			assert_true(info.has(step[1]), "job %d: item %d exists" % [job, step[1]])
			assert_eq(info[step[1]].incPAD, step[2], "job %d: incPAD of %d" % [job, step[1]])
			assert_true(int(info[step[1]].incPAD) > last_pad, "job %d: incPAD strictly increases" % job)
			last_pad = int(info[step[1]].incPAD)
	for id in Ammo.item_ids(_data.ammo):
		assert_true(lib.anim(Ammo.bullet_path(id)) != null, "%d has a flight animation" % id)


func test_the_upgrade_notice_names_the_ammo_in_the_v83_item_words() -> void:
	assert_eq(Ammo.notice("throwing stars", "Ilbi Throwing-Stars"), "Your throwing stars are now Ilbi Throwing-Stars")
	assert_eq(Ammo.noun(_data.ammo, "gun"), "bullets")


func test_the_real_string_names_appear_in_the_notice() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var names := {2060001: "Bronze Arrow for Bow", 2060002: "Steel Arrow for Bow", 2060003: "Red Arrow for Bow",
		2061003: "Blue Arrow for Crossbow", 2070005: "Steely Throwing-Knives", 2330001: "Split Bullet",
		2330002: "Mighty Bullet"}
	for id: int in names:
		var found: Variant = lib.find(InventoryModel.name_path(id))
		assert_eq(String(found), names[id], "String.wz name of %d" % id)
		var family: String = "bow" if id < 2061000 else ("crossbow" if id < 2070000 else ("claw" if id < 2330000 else "gun"))
		assert_eq(Ammo.notice(Ammo.noun(_data.ammo, family), String(found)),
			"Your %s are now %s" % [Ammo.noun(_data.ammo, family), names[id]])
