extends RefCounted
## Synthetic artwork and WZ-shaped attack metadata for seeded public boss attack scenarios. The boss's contact and
## slam multipliers, cadence, and the player's HP pool and W.DEF come from the shipped Henesys schedule entry
## (stages.json `dmg_mult`, `attack_dmg_mult`, `attack_interval`, `typical_hp`, `typical_pdd`).

const RF := preload("res://tests/fixtures/run_fixtures.gd")


static func setup(id: int = 6130101, p_seed: int = 2302, area: Rect2 = Rect2(-250, -150, 500, 150)) -> Dictionary:
	var data := RF.quiet_data()
	var shipped := shipped_entry(data, id)
	data.balance.player.skills = []
	data.balance.player.hp = float(shipped.typical_hp)
	data.balance.player.stats.dex = 0
	data.balance.player.stats.luk = 0
	RF.set_bosses(data.stages.stages.quiet, [{"mob_id": id, "time": 0.5, "hp_mult": 0.6,
		"dmg_mult": float(shipped.dmg_mult), "attacks": ["attack1"],
		"attack_interval": float(shipped.attack_interval), "attack_dmg_mult": float(shipped.attack_dmg_mult)}])
	var out := RF.setup("quiet", p_seed, data)
	out.map_img = RF.map_from_segments([{"x1": -2000, "y1": 0, "x2": 2000, "y2": 0}], [Vector2.ZERO])
	out.equipment_info[1040002] = {"incPDD": float(shipped.typical_pdd)}
	var img: Dictionary = out.mob_imgs[id]
	img["attack1"] = {"info": {"type": 0.0, "attackAfter": 1050.0, "effectAfter": 0.0,
		"jumpAttack": 1.0, "PADamage": 300.0,
		"range": {"lt": {"$v": [area.position.x, area.position.y]}, "rb": {"$v": [area.end.x, area.end.y]}},
		"effect": {"0": {"$canvas": [0, 0, 0, 40, 40], "delay": 100.0}}}}
	for i in 5:
		var frame: Dictionary = img.move["0"].duplicate(true)
		frame.delay = [800.0, 200.0, 50.0, 50.0, 750.0][i]
		img.attack1[str(i)] = frame
	return out


## The shipped henesys_hg1 schedule entry of boss `id` ({} when it is not scheduled there).
static func shipped_entry(data: Dictionary, id: int) -> Dictionary:
	for entry: Dictionary in DataRepo.stage_bosses(data.stages.stages.henesys):
		if int(entry.mob_id) == id:
			return entry
	return {}
