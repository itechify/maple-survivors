extends RefCounted
## Seeded synthetic skill tables and ranged weapons for generic combat mechanics tests and visual evidence (#200).

const RF := preload("res://tests/fixtures/run_fixtures.gd")


## A quiet world with an optional combat mechanic on its synthetic skill.
static func world(extra: Dictionary = {}) -> RunWorld:
	var data := RF.quiet_data()
	var def := {"skill_id": 9991000, "book": "999", "kind": "instant", "damage": "fixed",
		"ranks": [1, 2], "range": 600.0, "speed": 600.0, "cooldown": 10.0, "cast": {}}
	def.merge(extra, true)
	data.skills.skills["synthetic"] = def
	var setup := RF.setup("quiet", 200, data)
	setup.skill_imgs["999"] = {"skill": {"9991000": {"level": {
		"1": {"fixdamage": 100, "prop": 100, "time": 3, "x": 72, "mobCount": 3,
			"lt": {"$v": [-80, -60]}, "rb": {"$v": [80, 0]}},
		"2": {"fixdamage": 100, "prop": 0, "time": 4, "x": 130, "mobCount": 4,
			"lt": {"$v": [-80, -60]}, "rb": {"$v": [80, 0]}}
	}}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("synthetic")
	w.god = true
	w.drain_events()
	return w


## A synthetic ranged Final Attack with the current ammo of the given job and level.
static func ranged_final(weapon: int, job: int, level: int = 40) -> RunWorld:
	var w := world({"kind": "passive", "damage": "physical", "final_attack": {"chance_field": "prop"}})
	var info := {"incPAD": 40, "attackSpeed": 5, "tuc": 7}
	w.setup.equipment_info[weapon] = info
	w.equipment.inventory.append(Equipment.create(weapon, info))
	w.equip_item(w.equipment.inventory.size() - 1)
	w.progression.job_id = job
	w.progression.level = level
	w.refresh_player_stats(false)
	w.loadout.add_player_mod("crit", "add", 0.35)
	w.drain_events()
	return w
