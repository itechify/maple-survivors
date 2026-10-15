extends RefCounted
## Synthetic canonical-shaped setup for seeded basic-attack and event-schema tests.
const RF := preload("res://tests/fixtures/run_fixtures.gd")

static func world(seed_value: int = 7) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	data.balance.player.skills = []
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	var world := RunWorld.new(setup)
	RF.place_player(world, 400)
	world.player.facing = 1
	world.god = true
	world.drain_events()
	return world
