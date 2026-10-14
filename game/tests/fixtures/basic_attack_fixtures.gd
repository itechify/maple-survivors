extends RefCounted
## Synthetic canonical-shaped setup for seeded basic-attack and event-schema tests.
const RF := preload("res://tests/fixtures/run_fixtures.gd")

static func world(seed_value: int = 7) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades = {"cards": []}
	data.balance.player.skills = []
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0
	var setup := RF.setup("quiet", seed_value, data)
	setup.equipment_info = {
		1302000: {"incPAD": 17.0, "attackSpeed": 4.0, "afterImage": "swordOL", "sfx": "swordL"},
		1372005: {"incPAD": 15.0, "incMAD": 23.0, "attackSpeed": 6.0, "afterImage": "mace", "sfx": "mace"}}
	setup.body_img = {}
	var images := {"0": {}}
	for action: String in BasicAttack.ACTIONS:
		setup.body_img[action] = {"0": {"delay": 300.0}, "1": {"delay": 150.0}, "2": {"delay": 350.0}}
		images["0"][action] = {"lt": {"$v": [-88.0, -62.0]}, "rb": {"$v": [-18.0, -6.0]},
			"2": {"0": {"$canvas": [0, 0, 0, 40, 30], "delay": 200.0}}}
	setup.afterimage_imgs = {"swordOL": images, "mace": images}
	var world := RunWorld.new(setup)
	RF.place_player(world, 400)
	world.player.facing = 1
	world.god = true
	world.drain_events()
	return world

