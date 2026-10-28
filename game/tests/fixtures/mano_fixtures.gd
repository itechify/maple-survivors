extends RefCounted


## Synthetic Mano and MobSkill nodes with independently inspected v83 values; quiet seeded world seam.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const LEVELS := {126: 7, 200: 78, 112: 1, 113: 1}
static func setup(ids: Array = [126], seed_value: int = 22) -> Dictionary:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	# Timer/area tests hold the synthetic boss still; separate lifecycle tests cover pursuit teleport.
	data.balance.bosses.teleport_stall = 10000.0
	data.balance.mob_motion.push_px = 0
	data.balance.magnet_radius = 0
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.0, "mob_id": 2220000}])
	var setup := RF.setup("quiet", seed_value, data)
	var img: Dictionary = setup.mob_imgs[100100].duplicate(true)
	img.info = {"boss": 1.0, "level": 20.0, "maxHP": 2000.0, "PDDamage": 20.0, "MDDamage": 30.0, "speed": -100.0, "skill": {}}
	img.skill1 = {"0": {"delay": 750.0}, "1": {"delay": 750.0}}
	for id: int in ids:
		img.info.skill[str(img.info.skill.size())] = {"skill": float(id), "level": float(LEVELS[id]), "action": 1.0, "effectAfter": 0.0}
	setup.mob_imgs[2220000] = img
	var area := {"lt": {"$v": [-300.0, -200.0]}, "rb": {"$v": [300.0, 200.0]}}
	var defense := area.merged({"interval": 10.0, "time": 30.0, "x": 85.0, "effect": {"0": {"delay": 100.0}}, "mob0": {"0": {"delay": 100.0}}})
	setup.mob_skill_img = {
		"126": {"level": {"7": {"interval": 15.0, "time": 15.0, "prop": 100.0, "x": 80.0,
			"lt": {"$v": [-300.0, -120.0]}, "rb": {"$v": [300.0, 120.0]}, "affected": {"0": {"delay": 70.0}}}}},
		"200": {"level": {"78": {"interval": 10.0, "hp": 90.0, "limit": 30.0, "summonEffect": 1.0,
			"0": 100100.0, "1": 100100.0, "2": 100101.0, "3": 100101.0, "4": 130101.0, "5": 130101.0}}},
		"112": {"level": {"1": defense}}, "113": {"level": {"1": defense.duplicate(true)}}}
	return setup
static func world(ids: Array = [126], seed_value: int = 22) -> RunWorld:
	var w := RunWorld.new(setup(ids, seed_value))
	w.god = true
	RF.place_player(w, 400)
	w.step(1.0 / 60.0, MoveInput.new())
	if w.transfer_pending:
		w.advance_map()
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot, Vector2(600, 200), w.fhm.find_below(600, 190))
	w.drain_events()
	return w
