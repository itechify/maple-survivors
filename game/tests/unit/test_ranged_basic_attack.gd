extends TestCase
## The ranged basic attack and endless ammo (spec #151 #155): a claw, bow, crossbow or gun fires one ammo projectile
## through ProjectileSystem per attack, never runs out, adds the ammo's incPAD to W.Att, and the branch's ammo upgrades
## itself by level (ammo_upgraded). Seeded RunWorlds on the synthetic map with canonical-shaped weapon trees.

const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

## family -> [weapon id, item info, body actions, expected starting ammo].
const WEAPONS := {
	"claw": [1472000, {"incPAD": 10.0, "attackSpeed": 6.0, "afterImage": "swordOL", "sfx": "tGlove", "stand": 1.0, "walk": 1.0},
		["swingO1", "swingO2", "swingO3"], 2070015],
	"bow": [1452000, {"incPAD": 40.0, "attackSpeed": 5.0, "afterImage": "bow", "sfx": "bow", "stand": 1.0, "walk": 1.0},
		["shoot1"], 2060000],
	"crossbow": [1462000, {"incPAD": 40.0, "attackSpeed": 5.0, "afterImage": "crossBow", "sfx": "cBow", "stand": 1.0,
		"walk": 1.0}, ["shoot2"], 2061000],
	"gun": [1492000, {"incPAD": 13.0, "attackSpeed": 5.0, "afterImage": "gun", "sfx": "gun", "stand": 1.0, "walk": 1.0},
		["shoot1"], 2330000],
}


## A BF world wearing the family's weapon (level `level`, job `job`).
func _world(family: String, seed_value := 7, level := 1, job := 0) -> RunWorld:
	var spec: Array = WEAPONS[family]
	var world := BF.world(seed_value)
	var info: Dictionary = spec[1]
	world.setup.equipment_info[int(spec[0])] = info
	var images: Dictionary = {"0": {}}
	for action: String in spec[2]:
		world.setup.body_img[action] = {"0": {"delay": 300.0}, "1": {"delay": 150.0}, "2": {"delay": 350.0}}
		images["0"][action] = {"2": {"0": {"$canvas": [0, 0, 0, 40, 30], "delay": 200.0}}} if family != "gun" else {}
	world.setup.afterimage_imgs[String(info.afterImage)] = images
	world.equipment.inventory.append(Equipment.create(int(spec[0]), info))
	assert_eq(world.equip_item(world.equipment.inventory.size() - 1), "", "wears the %s" % family)
	world.progression.level = level
	world.progression.job_id = job
	world.refresh_player_stats(false)
	world.drain_events()
	return world


func _target(world: RunWorld, x: float) -> int:
	var kind: MobKind = world.mob_kinds[int(world.kind_of_id[100100])]
	kind.move_speed = 0
	kind.pdd = 0
	var mob := RF.put_mob(world, 100100, x, 190, 100)
	world.swarm.hp[mob] = 100000000
	world.swarm.max_hp[mob] = 100000000
	return mob


## Fixed ticks; returns {"impacts": [tick], "hits": [{tick, damage, crit}], "events": every ammo_upgraded}.
func _fight(world: RunWorld, ticks: int) -> Dictionary:
	var out := {"impacts": [], "hits": [], "upgrades": []}
	for tick in ticks:
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type == "basic_attack" and event.phase == "impact":
				out.impacts.append(tick)
			elif event.type == "mob_hit":
				out.hits.append({"tick": tick, "damage": int(event.damage), "crit": bool(event.crit)})
			elif event.type == "ammo_upgraded":
				out.upgrades.append(event)
	return out


func test_each_ranged_family_fires_one_projectile_per_attack_and_never_runs_out() -> void:
	for family: String in WEAPONS:
		var world := _world(family)
		_target(world, 400 + 200)
		var items_before: int = world.equipment.inventory.size()
		var ammo_before: int = world.ammo_id()
		assert_eq(ammo_before, int(WEAPONS[family][3]), "%s starts with its v83 ammo" % family)
		var first := _fight(world, 60 * 10)
		var shots_after_10: int = world.basic.shots
		var impacts_early: int = first.impacts.size()
		assert_true(impacts_early >= 5, "%s attacks repeatedly (%d)" % [family, impacts_early])
		var last := _fight(world, 60 * 50)
		var impacts_late: int = last.impacts.size()
		assert_eq(world.basic.shots, first.impacts.size() + last.impacts.size(),
			"%s: exactly one projectile per attack (impact)" % family)
		assert_eq(shots_after_10, impacts_early)
		# Ammo is endless: the same rate in the last ten seconds as in the first ten, nothing consumed, nothing stacked.
		var late_rate: int = (last.impacts as Array).filter(func(t: int) -> bool: return t >= 60 * 40).size()
		assert_true(absi(late_rate - impacts_early) <= 1, "%s: %d attacks in the last 10 s vs %d in the first" % [family,
			late_rate, impacts_early])
		assert_eq(world.ammo_id(), ammo_before, "%s: the ammo is unchanged" % family)
		assert_eq(world.equipment.inventory.size(), items_before, "%s: no ammo stack in the inventory" % family)
		assert_true(impacts_late > 0)


func test_a_booster_releases_the_ranged_shot_on_the_boosted_timing() -> void:
	# #160 scales hit_after and the interval by the Booster steps; the shot is released at that impact (#155).
	var plain := _world("bow")
	var boosted := _world("bow")
	boosted.loadout.speed_steps = 2
	_target(plain, 400 + 200)
	_target(boosted, 400 + 200)
	var plain_fight := _fight(plain, 60 * 6)
	var boosted_fight := _fight(boosted, 60 * 6)
	assert_true(boosted_fight.impacts.size() > plain_fight.impacts.size(),
		"two Booster steps release more arrows in six seconds (%d vs %d)" % [boosted_fight.impacts.size(),
		plain_fight.impacts.size()])
	assert_true(int(boosted_fight.impacts[0]) < int(plain_fight.impacts[0]), "the first arrow leaves sooner")
	assert_eq(boosted.basic.shots, boosted_fight.impacts.size(), "one arrow per boosted attack")


func test_ammo_shots_roll_on_the_basic_attack_stream() -> void:
	var world := _world("bow", 5)
	assert_true(world.projectiles.alt_rng == world.basic_rng, "the shots' rolls and crits come from stream 5")
	var twin := _world("bow", 5)
	_target(world, 400 + 200)
	_target(twin, 400 + 200)
	var rng_before: int = world.rng.state
	var hits_a: Array = _fight(world, 60 * 6).hits
	assert_true(hits_a.size() >= 2)
	assert_eq(world.rng.state, rng_before, "stream 1 (skills) is untouched by arrow hits")
	assert_eq(_fight(twin, 60 * 6).hits, hits_a, "same seed, same hits")


func test_the_shot_flies_after_the_impact_tick_carrying_the_ammos_sprite() -> void:
	var world := _world("claw")
	_target(world, 400 + 200)
	var impact_tick := -1
	var slot := -1
	for tick in 120:
		world.step(DT, MoveInput.new())
		var hit_now := false
		for event: Dictionary in world.drain_events():
			if event.type == "basic_attack" and event.phase == "impact":
				impact_tick = tick
			elif event.type == "mob_hit":
				hit_now = true
		if impact_tick == tick:
			assert_false(hit_now, "the star leaves the hand; it does not hit on the same tick")
			for i in world.projectiles.capacity():
				if world.projectiles.active[i] != 0:
					slot = i
		if impact_tick >= 0 and tick > impact_tick:
			break
	assert_true(slot >= 0, "an ammo projectile is in flight right after the impact")
	if slot < 0:
		return
	assert_eq(world.visual_paths[world.projectiles.visual[slot]], "Item.wz/Consume/0207.img/02070015/bullet")
	assert_eq(world.projectiles.damage_type[slot], "physical")
	assert_eq(world.projectiles.rotate[slot], 0, "stars spin in their own animation")
	assert_true(absf(world.projectiles.vx[slot]) > 700.0)


func test_arrows_turn_to_their_direction() -> void:
	var world := _world("bow")
	_target(world, 400 + 200)
	var seen := false
	for tick in 120:
		world.step(DT, MoveInput.new())
		for i in world.projectiles.capacity():
			if world.projectiles.active[i] != 0:
				seen = true
				assert_eq(world.projectiles.rotate[i], 1)
				assert_eq(world.visual_paths[world.projectiles.visual[i]], "Item.wz/Consume/0206.img/02060000/bullet")
	assert_true(seen)


func test_the_ammo_incpad_adds_to_ranged_weapon_attack_only() -> void:
	var claw := _world("claw")
	assert_eq(claw.weapon_attack(), 10.0, "melee-style W.Att is the weapon alone")
	assert_eq(claw.weapon_attack(true), 25.0, "10 + the Beginner Thief's Throwing Stars' 15")
	assert_eq(_world("gun").weapon_attack(true), 23.0, "13 + Bullet 10")
	assert_eq(_world("bow").weapon_attack(true), 40.0, "Arrow for Bow adds nothing")
	assert_eq(_world("crossbow").weapon_attack(true), 40.0)
	var assassin := _world("claw", 7, 55, 410)
	assert_eq(assassin.weapon_attack(true), 37.0, "10 + Ilbi 27")


func test_ammo_incpad_changes_the_damage_dealt() -> void:
	var best := {}
	for pad in [0, 100]:
		var world := _world("claw", 11)
		world.setup.ammo_info[2070015] = {"incPAD": pad}
		world.loadout.crit_per_acc = 0.0
		world.loadout.crit_chance = 0.0
		world.refresh_player_stats(false)
		_target(world, 400 + 200)
		var fight := _fight(world, 60 * 10)
		var top := 0
		for hit: Dictionary in fight.hits:
			top = maxi(top, int(hit.damage))
		best[pad] = top
		assert_true(fight.hits.size() >= 3)
	assert_true(int(best[100]) > int(best[0]) * 3, "W.Att 110 vs 10 changes the damage: %s" % [best])


func test_advancing_at_level_37_goes_straight_to_mokbi() -> void:
	var world := _world("claw", 7, 37, 400)
	assert_eq(world.ammo_id(), 2070015)
	world.change_job(410)
	var upgrades: Array = world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded")
	assert_eq(upgrades.size(), 1, "one upgrade, not Wolbi then Mokbi")
	if upgrades.size() == 1:
		assert_eq(upgrades[0].family, "claw")
		assert_eq(upgrades[0].from_item_id, 2070015)
		assert_eq(upgrades[0].item_id, 2070002)
		assert_eq(upgrades[0].level, 37)
	assert_eq(world.ammo_id(), 2070002)


func test_reaching_the_next_level_upgrades_the_ammo_and_other_levels_do_not() -> void:
	var world := _world("claw", 7, 29, 410)
	assert_eq(world.ammo_id(), 2070015, "Lv 29: Assassin stars not yet")
	var got := []
	for level in range(30, 57):
		world._gain_exp(world.progression.exp_to_next())
		assert_eq(world.progression.level, level)
		for event: Dictionary in world.drain_events():
			if event.type == "ammo_upgraded":
				got.append([level, event.from_item_id, event.item_id])
	assert_eq(got, [[30, 2070015, 2070001], [35, 2070001, 2070002], [40, 2070002, 2070003], [45, 2070003, 2070004],
		[50, 2070004, 2070005], [55, 2070005, 2070006]])
	assert_eq(world.ammo_id(), 2070006)


func test_first_job_and_other_branches_never_upgrade() -> void:
	var thief := _world("claw", 7, 60, 400)
	var bandit := _world("claw", 7, 60, 420)
	for world in [thief, bandit]:
		world._gain_exp(world.progression.exp_to_next())
		assert_eq(world.ammo_id(), 2070015)
		assert_eq(world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded").size(), 0)


func test_swapping_the_weapon_changes_the_ammo_without_an_upgrade_event() -> void:
	var world := _world("claw", 7, 55, 410)
	assert_eq(world.ammo_id(), 2070006)
	assert_eq(world.unequip_item("weapon"), "")
	assert_eq(world.ammo_id(), 0, "bare hands have no ammo")
	world.setup.equipment_info[1452000] = WEAPONS.bow[1]
	world.equipment.inventory.append(Equipment.create(1452000, WEAPONS.bow[1]))
	assert_eq(world.equip_item(world.equipment.inventory.size() - 1), "")
	assert_eq(world.ammo_id(), 2060000, "an Assassin with a bow shoots plain arrows")
	assert_eq(world.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded").size(), 0)


func test_a_saved_character_keeps_its_ammo_tier_without_a_notice() -> void:
	var source := _world("claw", 7, 52, 410)
	var setup := source.setup.duplicate(true)
	setup.character = source.character_snapshot()
	var restored := RunWorld.new(setup)
	assert_eq(restored.ammo_id(), 2070005, "Steely Throwing-Knives at Lv 52")
	assert_eq(restored.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "ammo_upgraded").size(), 0)
	assert_eq(restored.weapon_attack(true), 35.0)


func test_the_weapon_tooltip_lists_the_current_ammo() -> void:
	var world := _world("claw", 7, 40, 410)
	assert_eq(world.ammo_tooltip(1472000), {"item_id": 2070003, "incPAD": 21})
	assert_eq(world.ammo_tooltip(1302000), {}, "a sword has no ammo")
