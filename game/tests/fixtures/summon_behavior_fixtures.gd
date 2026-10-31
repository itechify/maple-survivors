extends RefCounted
## Synthetic turret ("Octopus") and kamikaze ("Gaviota") summons with made-up skill ids on the F/P book, the template later jobs
## copy (spec #384 M9, GAME_DESIGN 7.121). Shared by test_summon_behaviors and the tool probe summon_behavior_probe.tscn; no
## Corsair definition and no asset cache needed.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const OCTOPUS := 2129901
const GAVIOTA := 2129902
const RADIUS := 300.0
const SPEED := 300.0
const SP := Vector2(-23.0, -18.0)

static func frames(n: int, delay := 100.0) -> Dictionary:
	var out := {}
	for k in n:
		out[str(k)] = {"delay": delay}
	return out

static func octopus_def(extra := {}) -> Dictionary:
	var d: Dictionary = RF.quiet_data().skills.skills.elquines.duplicate(true)
	d.erase("rarity_bonuses")
	d.merge({"skill_id": OCTOPUS, "name": "Test Octopus", "cooldown": 30.0,
		"sounds": {}, "hit": "", "element": "i"}, true)
	d.summon.merge({"path": "Skill.wz/212.img/skill/%d/summon" % OCTOPUS, "behavior": "turret",
		"attack_interval": 1.0, "ordinal_spread": 36.0}, true)
	d.merge(extra, true)
	return d

static func gaviota_def(extra := {}) -> Dictionary:
	var d: Dictionary = RF.quiet_data().skills.skills.elquines.duplicate(true)
	d.erase("rarity_bonuses")
	d.merge({"skill_id": GAVIOTA, "name": "Test Gaviota", "cooldown": 30.0,
		"sounds": {}, "hit": "", "element": "i"}, true)
	d.summon.merge({"path": "Skill.wz/212.img/skill/%d/summon" % GAVIOTA, "behavior": "kamikaze",
		"move": "fly", "hover": 30.0, "follow_speed": 300.0, "follow_distance": 60.0, "teleport_distance": 2000.0}, true)
	d.merge(extra, true)
	return d

static func octopus_node(attack_after := 480.0, mob_count := 1.0) -> Dictionary:
	return {"summoned": frames(2), "stand": frames(2), "die": frames(2),
		"attack1": {"0": {"delay": 120.0}, "1": {"delay": 120.0}, "info": {
			"range": {"sp": {"$v": [SP.x, SP.y]}, "r": RADIUS}, "ball": {"0": {}, "1": {}},
			"attackAfter": attack_after, "mobCount": mob_count, "bulletSpeed": SPEED}}}

static func gaviota_node(attack_after := 400.0, mob_count := 3.0) -> Dictionary:
	return {"summoned": frames(2), "stand": frames(2), "fly": frames(2), "die": frames(2),
		"attack1": {"0": {"delay": 120.0}, "1": {"delay": 120.0}, "info": {
			"range": {"lt": {"$v": [-80, -60]}, "rb": {"$v": [80, 60]}, "sp": {"$v": [-14, -29]}, "r": 400.0},
			"type": 1, "attackAfter": attack_after, "mobCount": mob_count}}}

static func levels(time: float) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"mad": 100.0, "mastery": 10.0, "time": time}
	return levels

static func octopus_world(time := 30.0, attack_after := 480.0, mob_count := 1.0, def := {}) -> RunWorld:
	var data := RF.quiet_data()
	data.skills.skills["test_octopus"] = def if not def.is_empty() else octopus_def()
	var setup := RF.setup("quiet", 389, data)
	setup.skill_imgs["212"].skill[str(OCTOPUS)] = {"level": levels(time), "elemAttr": "i",
		"summon": octopus_node(attack_after, mob_count)}
	return finish(setup, "test_octopus")

static func gaviota_world(time := 30.0, attack_after := 400.0, mob_count := 3.0) -> RunWorld:
	var data := RF.quiet_data()
	data.skills.skills["test_gaviota"] = gaviota_def()
	var setup := RF.setup("quiet", 389, data)
	setup.skill_imgs["212"].skill[str(GAVIOTA)] = {"level": levels(time), "elemAttr": "i",
		"summon": gaviota_node(attack_after, mob_count)}
	return finish(setup, "test_gaviota")

## Both synthetic skills learned in one world (also the fixture of the tool probe `summon_behavior_probe.tscn`).
static func both_world(time := 30.0) -> RunWorld:
	var data := RF.quiet_data()
	data.skills.skills["test_octopus"] = octopus_def()
	data.skills.skills["test_gaviota"] = gaviota_def()
	var setup := RF.setup("quiet", 389, data)
	setup.skill_imgs["212"].skill[str(OCTOPUS)] = {"level": levels(time), "elemAttr": "i", "summon": octopus_node()}
	setup.skill_imgs["212"].skill[str(GAVIOTA)] = {"level": levels(time), "elemAttr": "i", "summon": gaviota_node()}
	var w := finish(setup, "test_octopus")
	w.learn_skill("test_gaviota")
	return w

static func finish(setup: Dictionary, key: String) -> RunWorld:
	setup.data.stages.stages.quiet.maps.append(setup.data.stages.stages.quiet.maps[0].duplicate(true))
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.player.facing = -1
	w.loadout.order.clear()
	w.learn_skill(key)
	w.loadout.set_caster(100.0, 0.0, 30)
	return w
