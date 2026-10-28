extends RefCounted
## A skill-less world on the synthetic map with canonical-shaped weapon swing data (WeaponReach), for seeded hit,
## event-schema and stance tests (the automatic basic attack itself is gone, #284).
const RF := preload("res://tests/fixtures/run_fixtures.gd")

static func world(seed_value: int = 7) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	var world := RunWorld.new(setup)
	RF.place_player(world, 400)
	world.player.facing = 1
	world.god = true
	world.drain_events()
	return world
