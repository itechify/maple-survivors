extends RefCounted
## Generated canonical-shaped Tree boss metadata on a quiet flat map; no proprietary artwork.
const RF := preload("res://tests/fixtures/run_fixtures.gd")


## An isolated King Slime or Dyle encounter with selected canonical skills.
static func setup(id: int = 6220000, skills: Array = [140], attacks: Array = [], seed_value: int = 2501) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 550
	data.balance.player.stats.dex = 0
	data.balance.player.stats.luk = 0
	data.balance.mob_skills.enabled_ids = [id]
	data.stages.stages.quiet.bosses = [{"time": 0.5, "mob_id": id, "hp_mult": 1.5,
		"dmg_mult": 0.0, "attacks": attacks, "attack_interval": 8.0, "attack_dmg_mult": 2.09,
		"rewards": {"bonus_choices": 0, "exp_mult": 0}}]
	var out := RF.setup("quiet", seed_value, data)
	out.map_img = RF.map_from_segments([{"x1": -2000, "y1": 0, "x2": 2000, "y2": 0}], [Vector2.ZERO])
	out.equipment_info[1040002] = {"incPDD": 47.0}
	var img := RF.mob_img(100100)
	img.info = {"level": 40 if id == 9300003 else 65, "maxHP": 8000 if id == 9300003 else 31000,
		"PADamage": 130 if id == 9300003 else 190, "PDDamage": 160 if id == 9300003 else 190,
		"MDDamage": 160 if id == 9300003 else 220, "speed": -20 if id == 9300003 else -30,
		"bodyAttack": 1, "acc": 140, "exp": 800, "pushed": 300, "skill": {}}
	if id == 6220000:
		img.info.boss = 1
	else:
		img.info.revive = {}
		for i in 11:
			img.info.revive[str(i)] = 210100
	var levels := {140: 8, 114: 17, 200: 2}
	for i in skills.size():
		img.info.skill[str(i)] = {"skill": skills[i], "level": levels[skills[i]], "action": 1, "effectAfter": 0}
	img.attack1 = {"info": {"type": 0, "effectAfter": 300, "attackAfter": 900, "jumpAttack": 1,
		"PADamage": 165, "range": {"lt": {"$v": [-250, -150]}, "rb": {"$v": [250, 0]}}}}
	for stance: String in ["attack1", "skill1"]:
		if not img.has(stance):
			img[stance] = {}
		for i in 12:
			var frame: Dictionary = img.move["0"].duplicate(true)
			frame.delay = 100
			img[stance][str(i)] = frame
	out.mob_imgs[id] = img
	out.mob_skill_img = {"140": {"level": {"8": {"x": 1, "hp": 80, "interval": 30, "time": 5,
		"mob": {"0": {"$canvas": [0, 0, 0, 34, 34], "origin": {"$v": [17, 34]}, "delay": 100}, "repeat": 1, "pos": 2}}}},
		"114": {"level": {"17": {"x": 5000, "y": 500, "hp": 90, "interval": 20, "time": 1,
			"lt": {"$v": [-400, -350]}, "rb": {"$v": [400, 250]}}}},
		"200": {"level": {"2": {"hp": 50, "interval": 50, "limit": 15, "summonEffect": 3,
			"0": 210100, "1": 210100, "2": 210100}}}}
	return out
