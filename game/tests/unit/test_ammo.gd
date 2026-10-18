extends TestCase
## Endless ammo (spec #151 #155): which ammo item a weapon family, job and level use (Ammo over survivor/ammo.json), the
## data file's own rules, and the upgrade notice text. The world side (events, W.Att, projectiles) is
## test_ranged_basic_attack.

var _data: Dictionary
var _jobs: JobTree


func before_each() -> void:
	_data = DataRepo.load_all()
	_jobs = JobTree.from_data(_data.jobs, _data.jobs_survivor)


func _item(family: String, job: int, level: int) -> int:
	return Ammo.item_for(_data.ammo, family, job, level, _jobs)


func test_every_ranged_family_starts_with_its_v83_ammo() -> void:
	assert_eq(_item("claw", 0, 1), 2070015, "A Beginner Thief's Throwing Stars")
	assert_eq(_item("bow", 0, 1), 2060000, "Arrow for Bow")
	assert_eq(_item("crossbow", 0, 1), 2061000, "Arrow for Crossbow")
	assert_eq(_item("gun", 0, 1), 2330000, "Bullet")
	assert_eq(_item("sword", 0, 1), 0, "a melee family has no ammo")
	assert_eq(_item("", 0, 1), 0, "bare hands neither")


func test_assassin_throwing_stars_follow_the_level_schedule() -> void:
	var want := {29: 2070015, 30: 2070001, 34: 2070001, 35: 2070002, 37: 2070002, 40: 2070003, 45: 2070004, 50: 2070005,
		55: 2070006, 120: 2070006}
	for level: int in want:
		assert_eq(_item("claw", 410, level), want[level], "Assassin Lv %d" % level)
	assert_eq(_item("claw", 411, 55), 2070006, "a later advancement of the branch keeps the branch's stars")
	assert_eq(_item("claw", 412, 36), 2070002)


func test_other_branches_have_their_own_schedules() -> void:
	var hunter := {29: 2060000, 30: 2060001, 39: 2060001, 40: 2060002, 49: 2060002, 50: 2060003, 99: 2060003}
	var crossbowman := {29: 2061000, 30: 2061001, 40: 2061002, 50: 2061003}
	var gunslinger := {29: 2330000, 30: 2330001, 49: 2330001, 50: 2330002, 99: 2330002}
	for level: int in hunter:
		assert_eq(_item("bow", 310, level), hunter[level], "Hunter Lv %d" % level)
	for level: int in crossbowman:
		assert_eq(_item("crossbow", 320, level), crossbowman[level], "Crossbowman Lv %d" % level)
	for level: int in gunslinger:
		assert_eq(_item("gun", 520, level), gunslinger[level], "Gunslinger Lv %d" % level)


func test_first_job_and_other_branches_keep_the_starting_ammo() -> void:
	assert_eq(_item("claw", 400, 70), 2070015, "a Thief who never chose the Assassin")
	assert_eq(_item("claw", 420, 70), 2070015, "a Bandit's stars do not upgrade")
	assert_eq(_item("bow", 300, 70), 2060000, "a first-job Bowman")
	assert_eq(_item("gun", 500, 70), 2330000, "a first-job Pirate")
	assert_eq(_item("bow", 320, 70), 2060000, "a Crossbowman holding a bow keeps the plain arrow")
	assert_eq(_item("crossbow", 310, 70), 2061000, "a Hunter holding a crossbow")
	assert_eq(_item("claw", 310, 70), 2070015, "another branch's schedule never touches a different family")


func test_the_data_file_is_consistent() -> void:
	var ammo: Dictionary = _data.ammo
	for family: String in WeaponInfo.RANGED_FAMILIES:
		var f: Dictionary = ammo.families.get(family, {})
		assert_true(int(f.get("start", 0)) > 0, "%s has a starting ammo" % family)
		assert_true(String(f.get("noun", "")) != "", "%s has a noun for the notice" % family)
		var shot: Dictionary = f.get("projectile", {})
		for key: String in ["speed", "radius", "overshoot"]:
			assert_true(float(shot.get(key, 0.0)) > 0.0, "%s projectile %s" % [family, key])
		assert_true(shot.has("rotate"))
	for schedule: Dictionary in ammo.schedules:
		assert_true(_jobs.job(int(schedule.branch)).size() > 0, "branch %s is a job" % schedule.branch)
		assert_true(WeaponInfo.RANGED_FAMILIES.has(String(schedule.family)))
		var last := 0
		for step: Dictionary in schedule.steps:
			assert_true(int(step.level) > last, "levels ascend")
			last = int(step.level)
			assert_true(String(step.tier) in ["A", "B", "C"], "every step carries its provenance tier")
	var ids := Ammo.item_ids(ammo)
	for id in [2070015, 2070001, 2070006, 2060000, 2060003, 2061000, 2061003, 2330000, 2330002]:
		assert_true(id in ids, "%d is an ammo item the setup loads" % id)
	assert_eq(ids.size(), 18)


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
	assert_false(info.has(2070006), "an absent node is left out")
	assert_true("Item.wz/Consume/0207.img/02070006" in missing)
	assert_eq(info.size() + missing.size(), 18)


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
	assert_eq(info[2070006].incPAD, 27)
	assert_eq(info[2330002].incPAD, 14)
	assert_eq(info[2060003].incPAD, 4)
	for id in Ammo.item_ids(_data.ammo):
		assert_true(lib.anim(Ammo.bullet_path(id)) != null, "%d has a flight animation" % id)


func test_the_upgrade_notice_names_the_ammo_in_the_v83_item_words() -> void:
	assert_eq(Ammo.notice("throwing stars", "Ilbi Throwing-Stars"), "Your throwing stars are now Ilbi Throwing-Stars")
	assert_eq(Ammo.noun(_data.ammo, "gun"), "bullets")
