extends TestCase
## Shade's Banish (MobSkill 129, ticket #256 of spec #253): a scheduled boss's area skill moves the character to a random
## `sp` portal of the current map, at most once per the boss entry's `skill_intervals` override. Synthetic Shade and
## MobSkill nodes (v83 129/5 area and interval), seeded worlds, fixed dt, through the public RunWorld seam.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const SHADE := 5090000
const PET := 5000000
## The synthetic big map's two `sp` portals (x 400 / 1500, y 180) dropped onto the ground (y 200).
const SP_FLOORS: Array = [Vector2(400, 200), Vector2(1500, 200)]
## Where the boss stands: x 700 keeps both portal floors outside its 400 px wide area.
const BOSS_AT := Vector2(700, 200)


## A quiet stage whose only boss is a synthetic Shade casting 129/5; `boss` fields merge into its stage entry.
func _setup(boss: Dictionary = {"skill_intervals": {"129": 15}}, seed_value := 22) -> Dictionary:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.bosses.teleport_stall = 10000.0
	data.balance.mob_motion.push_px = 0
	data.balance.magnet_radius = 0
	data.balance.mob_skills.enabled_ids = [SHADE]
	RF.set_bosses(data.stages.stages.quiet, [{"time": 0.0, "mob_id": SHADE}.merged(boss, true)])
	var setup := RF.setup("quiet", seed_value, data)
	var img: Dictionary = setup.mob_imgs[100100].duplicate(true)
	img.info = {"boss": 1.0, "level": 56.0, "maxHP": 4800.0, "PDDamage": 20.0, "MDDamage": 30.0, "speed": -100.0,
		"skill": {"0": {"skill": 129.0, "level": 5.0, "action": 1.0}}}
	img.skill1 = {"0": {"delay": 600.0}, "1": {"delay": 600.0}}
	setup.mob_imgs[SHADE] = img
	# tier A: v83 MobSkill.img/129/level/5 (interval 3, prop 100, count 5, the area below, time 1).
	setup.mob_skill_img = {"129": {"level": {"5": {"interval": 3.0, "prop": 100.0, "count": 5.0, "time": 1.0,
		"lt": {"$v": [-200.0, -150.0]}, "rb": {"$v": [200.0, 50.0]},
		"affected": {"0": {"delay": 120.0}, "pos": 0.0, "repeat": 1.0}}}}}
	return setup


## A world from `setup` with the boss arrived and parked at `at`, the player beside it (inside its area).
func _world_from(setup: Dictionary, at := BOSS_AT, player_x := 650.0) -> RunWorld:
	var w := RunWorld.new(setup)
	w.god = true
	RF.place_player(w, player_x, at.y - 10.0)
	w.step(DT, MoveInput.new())
	var slot := int(w.bosses.records[0].slot)
	w.relocate_mob(slot, at, w.fhm.find_below(at.x, at.y - 10.0))
	w.drain_events()
	return w


func _world(boss: Dictionary = {"skill_intervals": {"129": 15}}, seed_value := 22) -> RunWorld:
	return _world_from(_setup(boss, seed_value))


## Steps `ticks` ticks; with `chase` the player is put back beside the boss before every tick. Returns the events.
func _run(w: RunWorld, ticks: int, chase := false) -> Array:
	var out: Array = []
	for tick in ticks:
		if chase:
			RF.place_player(w, BOSS_AT.x - 50.0, BOSS_AT.y - 10.0)
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _banishes(events: Array) -> Array:
	return _of(events, "player_banished")


func test_the_boss_entry_override_spaces_banishes_fifteen_seconds_apart() -> void:
	var w := _world()
	var events := _run(w, 15 * 60 - 1, true)
	assert_eq(_banishes(events).size(), 0, "nothing before the 15 s override (the WZ interval is 3 s)")
	events = _run(w, 1, true)
	assert_eq(_banishes(events).size(), 1, "the first Banish is ready 15 s after the boss arrived")
	var skills := _of(events, "boss_skill")
	assert_eq(skills.size(), 1)
	if not skills.is_empty():
		assert_eq(int(skills[0].skill_id), 129)
		assert_eq(String(skills[0].action), "skill1", "Shade plays its skill1 action")
	assert_eq(_banishes(_run(w, 15 * 60 - 1, true)).size(), 0, "no second Banish inside 15 s")
	assert_eq(_banishes(_run(w, 1, true)).size(), 1, "the next one exactly 15 s later")


func test_without_an_override_banish_keeps_the_canonical_interval() -> void:
	var w := _world({})
	assert_eq(_banishes(_run(w, 15 * 60, true)).size(), 5, "v83 129/5 interval 3 s: five in the first 15 s")


func test_a_banished_character_lands_on_the_floor_under_an_sp_portal() -> void:
	var w := _world()
	_run(w, 15 * 60 - 1, true)
	RF.place_player(w, BOSS_AT.x - 50.0, BOSS_AT.y - 10.0)
	w.player.vel = Vector2(120, -300)
	var from := w.player.pos
	var banished := _banishes(_run(w, 1))
	assert_eq(banished.size(), 1)
	if banished.is_empty():
		return
	var e: Dictionary = banished[0]
	assert_true(w.player.pos in SP_FLOORS, "lands on a sp portal's floor: %s" % w.player.pos)
	assert_eq(e.pos, w.player.pos)
	assert_true((e.from as Vector2).distance_to(from) < 10.0, "from is where the tick's movement left it: %s" % e.from)
	assert_true(w.player.fh >= 0, "standing on a foothold")
	assert_eq(w.player.state, PlayerMotion.ST_STAND)
	assert_eq(w.player.vel, Vector2.ZERO, "the placement clears velocity")
	assert_eq(int(e.mob_id), SHADE)
	assert_eq(String(e.effect), "Skill.wz/MobSkill.img/129/level/5/affected", "the v83 affected art on the character")
	assert_eq(String(e.message), "As the Pentacle swayed in the shadows, you were thrown elsewhere in the Subway.")


func test_banish_fires_only_inside_its_canonical_area() -> void:
	# lt(-200,-150) rb(200,50) around the boss's feet; the box is symmetric, so facing does not matter here.
	for sample: Array in [[Vector2(-199, 0), true], [Vector2(199, 0), true], [Vector2(-201, 0), false],
			[Vector2(201, 0), false], [Vector2(0, -149), true], [Vector2(0, -151), false]]:
		var w := _world()
		_run(w, 15 * 60 - 1, true)
		var at: Vector2 = BOSS_AT + sample[0]
		w.player.place(at, w.fhm)
		var events := _run(w, 1)
		assert_eq(_banishes(events).size(), 1 if sample[1] else 0, "Banish at offset %s" % sample[0])
		if not sample[1]:
			assert_true(_of(events, "boss_skill").is_empty(), "no cast at nobody")
			assert_true(w.player.pos.distance_to(at) < 5.0, "the character stays where it was")


func test_the_same_seed_gives_the_same_arrivals() -> void:
	var runs: Array = []
	for i in 2:
		var w := _world({"skill_intervals": {"129": 15}}, 31)
		var arrivals: Array = []
		for e: Dictionary in _banishes(_run(w, 125 * 60, true)):
			arrivals.append(e.pos)
		runs.append(arrivals)
	assert_eq(runs[0].size(), 8, "eight Banishes by 2:05 at one per 15 s")
	assert_eq(runs[0], runs[1], "same seed, same portal draws")
	for pos: Vector2 in runs[0]:
		assert_true(pos in SP_FLOORS, "every arrival is an sp floor: %s" % pos)
	assert_true(SP_FLOORS[0] in runs[0] and SP_FLOORS[1] in runs[0], "both portals are drawn over eight Banishes")


func test_the_pet_lands_beside_the_banished_character() -> void:
	var setup := _setup()
	var character := RunWorld.new(setup).character_snapshot()
	character.pet = PET
	setup.character = character
	setup.account = {"owned": [PET]}
	var w := _world_from(setup)
	assert_true(w.pet_system != null, "fixture brings the pet out")
	_run(w, 15 * 60 - 1, true)
	var events := _run(w, 1, true)
	assert_eq(_banishes(events).size(), 1)
	var pet_pos: Vector2 = w.pet_state().pos
	assert_true(absf(pet_pos.x - w.player.pos.x) <= 30.0 + 1e-6 and absf(pet_pos.y - w.player.pos.y) <= 2.0,
		"pet %s beside player %s" % [pet_pos, w.player.pos])
	var jumps := _of(events, "pet_teleported")
	assert_eq(jumps.size(), 1, "the pet's jump is announced so its renderer snaps")
	if not jumps.is_empty():
		assert_eq(jumps[0].pos, pet_pos)


func test_banish_is_not_cast_while_the_character_is_hidden() -> void:
	var w := _world()
	var stats := {"skill_id": 9991001, "level": 1, "icon": "", "duration": 40.0, "buff_stat": "",
		"buff_value": 0.0, "pulse_interval": 0.0, "hidden": true, "buff_effects": {}}
	assert_true(w.start_buff("synthetic_hide", stats))
	var events := _run(w, 30 * 60, true)
	assert_true(_banishes(events).is_empty(), "no Banish while Hidden")
	assert_true(_of(events, "boss_skill").is_empty(), "and Shade does not cast at nobody")
	assert_eq(_banishes(_run(w, 11 * 60, true)).size(), 1, "a ready Banish lands once Hidden ends")


func test_a_map_without_sp_portals_falls_back_to_the_widest_platform() -> void:
	var setup := _setup()
	# Ground x 0..1200 at y 0 (the widest platform, middle x 600) and a short ledge; no portals at all.
	setup.map_img = RF.map_from_segments([{"x1": 0, "y1": 0, "x2": 1200, "y2": 0},
		{"x1": 200, "y1": -120, "x2": 400, "y2": -120}])
	var w := _world_from(setup, Vector2(900, 0), 850.0)
	var events: Array = []
	for tick in 15 * 60:
		RF.place_player(w, 850.0, -10.0)
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	var banished := _banishes(events)
	assert_eq(banished.size(), 1)
	assert_eq(w.player.pos, Vector2(600, 0), "the start-point rule's widest-platform middle")
	assert_true(w.player.fh >= 0)
