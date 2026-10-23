extends TestCase
## Shade's Banish (MobSkill 129, ticket #256 of spec #253): a scheduled boss's area skill moves the character to a random
## `sp` portal of the current map, at most once per the boss entry's `skill_intervals` override. Synthetic Shade and
## MobSkill nodes (v83 129/5 area and interval), seeded worlds, fixed dt, through the public RunWorld seam.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const SF := preload("res://tests/fixtures/shade_fixtures.gd")
const DT := 1.0 / 60.0
const SHADE := SF.SHADE
const PET := 5000000
## The synthetic big map's two `sp` portals (x 400 / 1500, y 180) dropped onto the ground (y 200).
const SP_FLOORS: Array = [Vector2(400, 200), Vector2(1500, 200)]
const BOSS_AT := SF.BOSS_AT


func _setup(boss: Dictionary = {"skill_intervals": {"129": 15}}, seed_value := 22) -> Dictionary:
	return SF.setup(boss, seed_value)


func _world_from(setup: Dictionary, at := BOSS_AT, player_x := 650.0) -> RunWorld:
	return SF.world_from(setup, at, player_x)


func _world(boss: Dictionary = {"skill_intervals": {"129": 15}}, seed_value := 22) -> RunWorld:
	return SF.world(boss, seed_value)


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


func test_skill_interval_reads_the_entry_override_else_the_given_wz_interval() -> void:
	var bosses := BossDirector.new([{"time": 0.0, "mob_id": SHADE, "skill_intervals": {"129": 15}},
		{"time": 0.0, "mob_id": SHADE}])
	assert_eq(bosses.skill_interval(0, 129, 3.0), 15.0, "the entry's override")
	assert_eq(bosses.skill_interval(0, 126, 3.0), 3.0, "a skill the override does not name keeps the WZ interval")
	assert_eq(bosses.skill_interval(1, 129, 3.0), 3.0, "an entry without overrides keeps the WZ interval")


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


## Arrivals of every Banish in `seconds` with the character kept beside the boss at `at` (player 50 px left of it).
func _arrivals(w: RunWorld, seconds: int, at := BOSS_AT) -> Array:
	var out: Array = []
	for tick in seconds * 60:
		RF.place_player(w, at.x - 50.0, at.y - 10.0)
		w.step(DT, MoveInput.new())
		for e: Dictionary in _banishes(w.drain_events()):
			out.append(e.pos)
	return out


func test_with_two_sp_portals_the_character_is_always_thrown_to_the_other_one() -> void:
	# Beside x 650 the nearest portal is x 400, so every Banish lands under x 1500 ...
	var near_left := _arrivals(_world(), 125)
	assert_eq(near_left.size(), 8, "eight Banishes by 2:05 at one per 15 s")
	for pos: Vector2 in near_left:
		assert_eq(pos, SP_FLOORS[1], "thrown away from the portal it stood by")
	# ... and beside x 1350 (boss parked at 1400) the nearest is x 1500, so every Banish lands under x 400.
	var at := Vector2(1400, 200)
	var near_right := _arrivals(_world_from(_setup(), at, 1350.0), 125, at)
	assert_eq(near_right.size(), 8)
	for pos: Vector2 in near_right:
		assert_eq(pos, SP_FLOORS[0], "thrown away from the portal it stood by")


func test_the_same_seed_gives_the_same_arrivals_among_the_other_portals() -> void:
	var runs: Array = []
	for i in 2:
		var setup := _setup({"skill_intervals": {"129": 15}}, 31)
		setup.map_img.portal["2"] = {"pn": "sp", "pt": 0.0, "x": -500.0, "y": 180.0}
		runs.append(_arrivals(_world_from(setup), 125))
	assert_eq(runs[0].size(), 8)
	assert_eq(runs[0], runs[1], "same seed, same portal draws on stream 17")
	var others: Array = [Vector2(-500, 200), SP_FLOORS[1]]
	for pos: Vector2 in runs[0]:
		assert_true(pos in others, "never the portal nearest the character (x 400): %s" % pos)
	assert_true(others[0] in runs[0] and others[1] in runs[0], "both other portals are drawn over eight Banishes")


func test_a_map_with_one_sp_portal_uses_it() -> void:
	var setup := _setup()
	setup.map_img.portal.erase("1")
	var arrivals := _arrivals(_world_from(setup), 16)
	assert_eq(arrivals, [SP_FLOORS[0]], "the only portal, even though it is the nearest")


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
