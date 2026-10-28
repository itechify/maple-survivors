extends RefCounted
## A synthetic Shade 5090000 casting Banish (v83 MobSkill.img/129/level/5) as the quiet stage's only boss, on the big
## RunFixtures map, for the #256 tests. No Nexon data: the skill node carries the independently inspected v83 values.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const SHADE := 5090000
## Where the boss stands: x 700 keeps both of the big map's portal floors (x 400 / 1500) outside its 400 px wide area.
const BOSS_AT := Vector2(700, 200)


## A quiet-stage setup whose only boss is the synthetic Shade; `boss` fields merge into its stage entry.
static func setup(boss: Dictionary = {"skill_intervals": {"129": 15}}, seed_value := 22) -> Dictionary:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["start_skills"] = []
	data.balance.bosses.teleport_stall = 10000.0
	data.balance.mob_motion.push_px = 0
	data.balance.magnet_radius = 0
	data.balance.mob_skills.enabled_ids = [SHADE]
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.0, "mob_id": SHADE}.merged(boss, true)])
	var s := RF.setup("quiet", seed_value, data)
	var img: Dictionary = s.mob_imgs[100100].duplicate(true)
	img.info = {"boss": 1.0, "level": 56.0, "maxHP": 4800.0, "PDDamage": 20.0, "MDDamage": 30.0, "speed": -100.0,
		"skill": {"0": {"skill": 129.0, "level": 5.0, "action": 1.0}}}
	img.skill1 = {"0": {"delay": 600.0}, "1": {"delay": 600.0}}
	s.mob_imgs[SHADE] = img
	# tier A: v83 MobSkill.img/129/level/5 (interval 3, prop 100, count 5, the area below, time 1).
	s.mob_skill_img = {"129": {"level": {"5": {"interval": 3.0, "prop": 100.0, "count": 5.0, "time": 1.0,
		"lt": {"$v": [-200.0, -150.0]}, "rb": {"$v": [200.0, 50.0]},
		"affected": {"0": {"delay": 120.0}, "pos": 0.0, "repeat": 1.0}}}}}
	return s


## An invulnerable world from `s` with the boss arrived and parked at `at`, the player at `player_x` (inside its area).
static func world_from(s: Dictionary, at := BOSS_AT, player_x := 650.0) -> RunWorld:
	var w := RunWorld.new(s)
	w.god = true
	RF.place_player(w, player_x, at.y - 10.0)
	w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot, at, w.fhm.find_below(at.x, at.y - 10.0))
	w.drain_events()
	return w


## world_from(setup(boss, seed_value)).
static func world(boss: Dictionary = {"skill_intervals": {"129": 15}}, seed_value := 22) -> RunWorld:
	return world_from(setup(boss, seed_value))
