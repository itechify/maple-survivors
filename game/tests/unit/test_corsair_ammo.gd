extends TestCase
## Corsair's gun ammo (spec #384, ticket C2 #386): the 522 schedule of survivor/ammo.json (spec #332 B3) re-verified for the
## job that owns it, with no Corsair skill involved. Exact job only (no lineage walk), Lv18 Split Bullet (+12) and Lv35
## Mighty Bullet (+14), the `ammo_upgraded` event once per step, the "Your bullets are now ..." notice, and incPAD read from the
## real cache. The generic lookup is test_ammo; this is the 522 slice of it plus the RunWorld side with a Pistol.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const CF := preload("res://tests/fixtures/corsair_fixtures.gd")
const DT := 1.0 / 60.0
const BULLET := 2330000
const SPLIT := 2330001
const MIGHTY := 2330002
const VITAL := 2330003

var _data: Dictionary


func before_each() -> void:
	_data = DataRepo.load_all()


func _item(job: int, level: int, family := "gun") -> int:
	return Ammo.item_for(_data.ammo, family, job, level)


func _world(job := 522) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	var setup := RF.with_basic_attack(RF.setup("quiet", 386, data))
	setup.equipment_info.merge({CF.PISTOL: {"incPAD": 20, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	var w := RunWorld.new(setup)
	assert_eq(w.wear_new_item(CF.PISTOL), "", "granting a weapon wears it")
	assert_eq(int(w.equipment.worn.weapon.id), CF.PISTOL)
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	RF.change_job_bare(w, job)
	w.drain_events()
	return w


func _upgrades(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")


# --- the schedule -----------------------------------------------------------------------------------------------------

func test_the_522_gun_schedule_is_exactly_split_at_18_and_mighty_at_35() -> void:
	var rows: Array = _data.ammo.schedules.filter(func(s: Dictionary) -> bool: return int(s.job) == 522)
	assert_eq(rows.size(), 1, "one schedule for the exact job 522")
	var sched: Dictionary = rows[0]
	assert_eq(String(sched.family), "gun")
	assert_eq(sched.steps.size(), 2, "two steps: Vital Bullet is not scheduled")
	assert_eq([int(sched.steps[0].level), int(sched.steps[0].item)], [18, SPLIT])
	assert_eq([int(sched.steps[1].level), int(sched.steps[1].item)], [35, MIGHTY])
	assert_eq(String(sched.steps[0].tier), "C")
	assert_eq(String(sched.steps[1].tier), "C")
	assert_false(sched.has("branch"), "a format-2 schedule names a job, never a branch")
	assert_eq(Array(Ammo.schedule_errors(_data.ammo)), [])
	assert_false(VITAL in Ammo.item_ids(_data.ammo), "Vital Bullet (img not imported) is not an ammo item")


func test_the_522_lookup_steps_at_the_round_levels() -> void:
	assert_eq(_data.ammo.families.gun.start, BULLET, "the family's plain Bullet covers Lv1")
	for row: Array in [[1, BULLET], [17, BULLET], [18, SPLIT], [34, SPLIT], [35, MIGHTY], [99, MIGHTY]]:
		assert_eq(_item(522, row[0]), row[1], "Lv %d" % row[0])


func test_only_the_exact_job_522_steps_and_no_lineage_is_walked() -> void:
	for job in [0, 212, 112, 500, 510, 512, 520, 521, 312, 322, 412]:
		assert_eq(_item(job, 99), BULLET, "job %d holding a gun keeps the plain Bullet" % job)
	assert_eq(_item(522, 99, "claw"), _data.ammo.families.claw.start, "522's gun steps never apply to another family")
	assert_eq(_item(522, 99, "bow"), _data.ammo.families.bow.start)
	assert_eq(_item(522, 99, "knuckle"), 0, "a knuckler has no ammo")


func test_the_real_cache_incpad_rises_along_the_schedule_and_the_notice_names_each_step() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.get_default()
	var missing := PackedStringArray()
	var info := DataRepo.ammo_info(_data.ammo, func(path: String) -> Dictionary:
		var img := lib.img(path)
		return img.root if img != null else {}, missing)
	assert_eq(missing, PackedStringArray(), "every ammo item is imported")
	assert_eq([int(info[BULLET].incPAD), int(info[SPLIT].incPAD), int(info[MIGHTY].incPAD)], [10, 12, 14], "tier A: Item.wz")
	for id: int in [BULLET, SPLIT, MIGHTY]:
		assert_true(lib.anim(Ammo.bullet_path(id)) != null, "%d has a flight animation" % id)
	for pair: Array in [[SPLIT, "Split Bullet"], [MIGHTY, "Mighty Bullet"]]:
		var found: Variant = lib.find(InventoryModel.name_path(int(pair[0])))
		assert_eq(String(found), pair[1], "String.wz name of %d" % pair[0])
		assert_eq(Ammo.notice(Ammo.noun(_data.ammo, "gun"), String(found)), "Your bullets are now %s" % pair[1])


# --- the world --------------------------------------------------------------------------------------------------------

func test_a_corsair_round_starts_on_the_plain_bullet_and_announces_nothing() -> void:
	var w := _world()
	assert_eq(w.progression.level, 1)
	assert_eq(w.ammo_id(), BULLET)
	assert_eq(w.ammo_attack(), 10.0, "the Bullet's incPAD, tier A")
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(_upgrades(w).size(), 0, "no notice at the start of the round")


func test_each_step_is_announced_exactly_once_when_the_level_changes() -> void:
	var w := _world()
	for row: Array in [[17, BULLET, 0], [18, SPLIT, 1], [34, SPLIT, 0], [35, MIGHTY, 1], [60, MIGHTY, 0]]:
		w.progression.level = row[0]
		w.refresh_player_stats()
		assert_eq(w.ammo_id(), row[1], "Lv %d" % row[0])
		var notices := _upgrades(w)
		assert_eq(notices.size(), row[2], "Lv %d notices" % row[0])
		w.refresh_player_stats()
		assert_eq(_upgrades(w).size(), 0, "a second refresh at Lv %d announces nothing" % row[0])


func test_real_level_ups_to_35_give_exactly_two_notices_with_the_steps_own_fields() -> void:
	var w := _world()
	var notices: Array = []
	while w.progression.level < 35:
		w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
		for tick in 120:
			w.step(DT, MoveInput.new())
			BotInput.auto_choose(w, false)
		notices.append_array(_upgrades(w))
	assert_eq(notices.size(), 2, "Split and Mighty: one notice per step, no repeats")
	assert_eq([notices[0].level, notices[0].from_item_id, notices[0].item_id, notices[0].family], [18, BULLET, SPLIT, "gun"])
	assert_eq([notices[1].level, notices[1].from_item_id, notices[1].item_id, notices[1].family], [35, SPLIT, MIGHTY, "gun"])
	assert_eq(w.ammo_id(), MIGHTY)


func test_the_incpad_of_the_current_bullet_adds_to_ranged_attack_only() -> void:
	var w := _world()
	var plain := w.weapon_attack(true)
	assert_eq(w.weapon_attack(false), plain - 10.0, "melee attack ignores ammo: the Lv1 Bullet adds +10 to ranged")
	for row: Array in [[18, 12.0], [35, 14.0]]:
		w.progression.level = row[0]
		w.refresh_player_stats()
		assert_eq(w.weapon_attack(true) - w.weapon_attack(false), row[1], "Lv %d: incPAD +%d" % [row[0], row[1]])
	assert_eq(Ammo.bullet_path(w.ammo_id()), "Item.wz/Consume/0233.img/02330002/bullet", "the shot sprite is the Mighty Bullet's")


func test_another_job_holding_the_pistol_never_steps() -> void:
	var w := _world(212)
	w.progression.level = 60
	w.refresh_player_stats()
	assert_eq(w.ammo_id(), BULLET, "the F/P Arch Mage with a gun keeps the plain Bullet")
	assert_eq(_upgrades(w).size(), 0)
	var b := _world(512)
	b.progression.level = 60
	b.refresh_player_stats()
	assert_eq(b.ammo_id(), BULLET, "a Buccaneer with a gun keeps it too: the schedule is the exact job's")
