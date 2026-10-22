extends RefCounted
## Generated WZ-shaped Stumpy attacks/skills on a flat test map; artwork is synthetic.
const RF := preload("res://tests/fixtures/run_fixtures.gd")


## A synthetic Stumpy setup with canonical-shaped attack metadata and selected attacks.
static func setup(attacks: Array = ["attack2"], seed_value: int = 2401) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 300
	data.balance.player.stats.dex = 0
	data.balance.player.stats.luk = 0
	data.balance.mob_skills.enabled_ids = []
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.5, "mob_id": 3220000, "hp_mult": 0.5,
		"dmg_mult": 1.2, "attacks": attacks, "attack_interval": 8.0, "attack_dmg_mult": 1.12}])
	var out := RF.setup("quiet", seed_value, data)
	out.map_img = RF.map_from_segments([{"x1": -2000, "y1": 0, "x2": 2000, "y2": 0}], [Vector2.ZERO])
	out.equipment_info[1040002] = {"incPDD": 7.0}
	var img := RF.mob_img(100100)
	img.info = {"level": 35, "maxHP": 7000, "PADamage": 125, "PDDamage": 50,
		"MDDamage": 70, "acc": 80, "speed": -60, "bodyAttack": 1, "boss": 1, "exp": 405}
	var ball := {"0": {"$canvas": [0, 0, 0, 32, 32], "origin": {"$v": [16, 16]}, "delay": 90}}
	img["attack2"] = {"info": {"type": 2, "range": {"r": 200, "sp": {"$v": [6, -60]}},
		"bulletSpeed": 140, "attackAfter": 1320, "PADamage": 135, "ball": ball, "hit": ball}}
	img["attack1"] = {"info": {"type": 0, "range": {"lt": {"$v": [-288, -172]}, "rb": {"$v": [255, 0]}},
		"attackAfter": 1500, "jumpAttack": 1, "PADamage": 135}}
	for stance: String in ["attack1", "attack2", "skill1"]:
		if not img.has(stance):
			img[stance] = {}
		for i in 20:
			var frame: Dictionary = img.move["0"].duplicate(true)
			frame.delay = 150
			img[stance][str(i)] = frame
	out.mob_imgs[3220000] = img
	return out


## An isolated heal-only setup with the v83 level-15 bounds, gate, interval and application delay.
static func heal_setup(seed_value: int = 2402) -> Dictionary:
	var out := setup([], seed_value)
	out.data.balance.mob_skills.enabled_ids = [3220000]
	out.mob_imgs[3220000].info.skill = {"0": {"skill": 114, "level": 15, "action": 1, "effectAfter": 1500}}
	out["mob_skill_img"] = {"114": {"level": {"15": {"x": 700, "y": 200, "hp": 80, "interval": 30,
		"time": 1, "lt": {"$v": [-400, -350]}, "rb": {"$v": [400, 250]}}}}}
	return out
