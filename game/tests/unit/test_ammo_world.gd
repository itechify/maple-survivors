extends TestCase
## Ammo in a running world (spec #332 ticket #335, ruling D9): a Bowmaster (312) levelling through its round steps its
## arrows at Lv15 / 30 / 45, announces each step once through `ammo_upgraded`, never at the start of the round and never
## on a weapon swap, and the shot sprite follows the ammo. The lookup itself is test_ammo; this is the RunWorld side.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOW := 1452051
const CROSSBOW := 1462001


func _world(job := 312) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	var setup := RF.with_basic_attack(RF.setup("quiet", 335, data))
	setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7},
		CROSSBOW: {"incPAD": 29, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	var w := RunWorld.new(setup)
	assert_eq(w.wear_new_item(BOW), "")
	assert_eq(w.wear_new_item(CROSSBOW), "")
	assert_eq(w.equip_item(_ids(w).find(BOW)), "")
	RF.place_player(w, 400)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
	w.player.facing = 1
	w.god = true
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	RF.change_job_bare(w, job)
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


func test_a_bowmaster_round_starts_on_the_plain_arrow_and_announces_nothing() -> void:
	var w := _world()
	assert_eq(w.progression.level, 1)
	assert_eq(w.ammo_id(), 2060000, "Arrow for Bow at Lv1")
	assert_eq(w.ammo_attack(), 0.0)
	for tick in 30:
		w.step(DT, MoveInput.new())
	assert_eq(_upgrades(w).size(), 0, "no notice at the start of the round")


func test_the_arrows_step_at_15_30_and_45_with_one_notice_each() -> void:
	var w := _world()
	var notices: Array = []
	_level_to(w, 14, notices)
	assert_eq(w.progression.level, 14)
	assert_eq(w.ammo_id(), 2060000)
	assert_eq(notices.size(), 0, "nothing before Lv15")
	_level_to(w, 45, notices)
	assert_eq(notices.size(), 3, "Bronze, Steel and Red: one notice per step, no repeats")
	var want := [[15, 2060000, 2060001], [30, 2060001, 2060002], [45, 2060002, 2060003]]
	for i in mini(notices.size(), want.size()):
		assert_eq(notices[i].level, want[i][0], "the step's own round level")
		assert_eq(notices[i].from_item_id, want[i][1])
		assert_eq(notices[i].item_id, want[i][2])
		assert_eq(notices[i].family, "bow")
	assert_eq(w.ammo_id(), 2060003, "Red Arrow for Bow at Lv45")


func test_each_step_is_announced_exactly_once_when_the_level_changes() -> void:
	var w := _world()
	for row: Array in [[14, 2060000, 0], [15, 2060001, 1], [29, 2060001, 0], [30, 2060002, 1], [44, 2060002, 0],
			[45, 2060003, 1]]:
		w.progression.level = row[0]
		w.refresh_player_stats()
		assert_eq(w.ammo_id(), row[1], "Lv %d" % row[0])
		assert_eq(_upgrades(w).size(), row[2], "Lv %d notices" % row[0])
		w.refresh_player_stats()
		assert_eq(_upgrades(w).size(), 0, "a second refresh at Lv %d announces nothing" % row[0])


func test_a_weapon_swap_never_announces_and_the_ammo_follows_the_family() -> void:
	var w := _world()
	w.progression.level = 45
	w.refresh_player_stats()
	w.drain_events()
	assert_eq(w.ammo_id(), 2060003)
	assert_eq(w.equip_item(_ids(w).find(CROSSBOW)), "")
	assert_eq(w.ammo_id(), 2061000, "a Bowmaster holding a crossbow fires the plain crossbow arrow: the Marksman's steps are not his")
	assert_eq(_upgrades(w).size(), 0, "a swap down is silent")
	assert_eq(w.equip_item(_ids(w).find(BOW)), "")
	assert_eq(w.ammo_id(), 2060003)
	assert_eq(_upgrades(w).size(), 0, "so is the swap back")


func test_the_incpad_of_the_current_arrow_adds_to_ranged_attack_only() -> void:
	var w := _world()
	w.setup.ammo_info = RF.ammo_info()
	var plain := w.weapon_attack(true)
	assert_eq(w.weapon_attack(false), plain, "the Lv1 arrow adds +0")
	w.progression.level = 45
	w.refresh_player_stats()
	assert_eq(w.weapon_attack(true), plain + 4.0, "Red Arrow for Bow: incPAD +4")
	assert_eq(w.weapon_attack(false), plain, "melee attack ignores ammo")


func test_the_shot_sprite_is_the_current_arrows_bullet() -> void:
	for level in [1, 15, 30, 45]:
		var w := _world()
		w.progression.level = level
		w.refresh_player_stats()
		assert_true(w.learn_skill("arrow_blow"))
		RF.put_mob(w, 1110100, w.player.pos.x + 80, 190, 10000)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		w.drain_events()
		w.runner.step(DT, w)
		var seen := 0
		for i in w.projectiles.capacity():
			if w.projectiles.active[i] != 0:
				seen += 1
				assert_eq(w.projectiles.paths[w.projectiles.visual[i]], Ammo.bullet_path(w.ammo_id()), "Lv %d shot" % level)
		assert_eq(seen, 1, "Lv %d: one arrow in flight" % level)


func test_another_job_holding_the_bow_never_steps() -> void:
	var w := _world(212)
	var notices: Array = []
	_level_to(w, 46, notices)
	assert_eq(w.ammo_id(), 2060000, "the F/P Arch Mage with a bow keeps the plain arrow")
	assert_eq(notices.size(), 0)
