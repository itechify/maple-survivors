extends RefCounted
## Synthetic artwork and WZ-shaped attack metadata for seeded public boss attack scenarios.

const RF := preload("res://tests/fixtures/run_fixtures.gd")


static func setup(id: int = 6130101, p_seed: int = 2302, area: Rect2 = Rect2(-250, -150, 500, 150)) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 550.0 if id == 6130101 else 800.0
	data.balance.player.stats.dex = 0
	data.balance.player.stats.luk = 0
	data.stages.stages.quiet.bosses = [{"mob_id": id, "time": 0.5, "hp_mult": 0.6,
		"dmg_mult": 1.66, "attacks": ["attack1"], "attack_interval": 8.0,
		"attack_dmg_mult": 1.03 if id == 6130101 else 1.48}]
	var out := RF.setup("quiet", p_seed, data)
	out.map_img = RF.map_from_segments([{"x1": -2000, "y1": 0, "x2": 2000, "y2": 0}], [Vector2.ZERO])
	out.equipment_info[1040002] = {"incPDD": 47.0}
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
