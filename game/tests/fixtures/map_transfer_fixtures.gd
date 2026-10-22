extends RefCounted
## Synthetic three-map stage using the binding #241 schema and RunFixtures map builders.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
## tier C: owner's region map lists (#241), used only until #243 supplies them as stage data.
const MAP_CHAINS := {
	104040000: [104040000, 104010001, 100030001],
	101010100: [101010100, 100040100, 100040105],
	105050400: [105050400, 105090310, 105090900],
}


## Real-cache transfer fixture while #243 is pending; integrated stages use their actual maps without overrides.
static func stage_maps(stage: Dictionary) -> Array:
	if not stage.get("maps", []).is_empty():
		return stage.maps
	var maps: Array = []
	var chain: Array = MAP_CHAINS.get(int(stage.get("map_id", 0)), [])
	for i in chain.size():
		var boss: Dictionary = stage.bosses[i].duplicate(true)
		boss.time = 300.0 # tier C: spec #241 per-map boss wait
		maps.append({"map_id": int(chain[i]), "pool": "curve", "boss": boss})
	return maps


## Aligned stage/maps and setup/map_imgs; seconds overrides boss waits for focused boundary tests.
static func setup(seconds := 300.0) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.mesos.boss_drops = 0
	var stage: Dictionary = data.stages.stages.quiet
	stage.erase("map_id")
	stage.erase("bosses")
	stage.map_seconds = 300.0
	stage.maps = []
	var setup := RF.setup("quiet", 244, data)
	setup.map_imgs = []
	for i in 3:
		stage.maps.append({"map_id": 100000000 + i, "pool": "curve",
			"boss": {"mob_id": 100100, "time": seconds, "rewards": {"bonus_choices": 0, "exp_mult": 0.0}}})
		setup.map_imgs.append(RF.map_from_segments([
			{"x1": -2000, "y1": i * 200, "x2": 2000, "y2": i * 200}],
			[Vector2(-500, i * 200 - 10), Vector2(500, i * 200 - 10)]))
	setup.map_img = setup.map_imgs[0]
	return setup
