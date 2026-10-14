extends TestCase
## Event schema conformance (docs/ARCHITECTURE.md 4.4.3): every event RunWorld emits in a real run has `type` plus
## exactly the documented fields, with the documented value types; every type shows up. Also checks seeded replays
## are identical.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

const INT_FIELDS := ["mob", "pickup", "mob_id", "item_id", "job_id", "skill_id", "level", "damage", "mp_absorbed",
	"dir", "exp", "count", "rank", "facing", "relocated_from", "boss_index", "max_hp", "restored", "required_mp", "mp", "from_item_id", "weapon_id"]
const BOOL_FIELDS := ["crit", "elite", "miss", "boss", "bonus"]
const STRING_FIELDS := ["skill", "hit_visual", "action", "effect", "name", "id", "portal", "target", "kind", "potion_kind", "phase", "afterimage", "sound"]


func _check(e: Dictionary, seen: Dictionary) -> void:
	var type := String(e.get("type", ""))
	if not RunWorld.EVENT_FIELDS.has(type):
		fail("unknown event type %s" % type)
		return
	seen[type] = int(seen.get(type, 0)) + 1
	var want: Array = ["type"] + RunWorld.EVENT_FIELDS[type]
	want.sort()
	var got: Array = e.keys()
	got.sort()
	if got != want:
		fail("%s fields %s, documented %s" % [type, got, want])
		return
	for k: String in e:
		var v: Variant = e[k]
		if k == "pos" and not (v is Vector2):
			fail("%s.pos is %s" % [type, type_string(typeof(v))])
		elif k in INT_FIELDS and typeof(v) != TYPE_INT:
			fail("%s.%s is %s, not int" % [type, k, type_string(typeof(v))])
		elif k in BOOL_FIELDS and typeof(v) != TYPE_BOOL:
			fail("%s.%s is %s, not bool" % [type, k, type_string(typeof(v))])
		elif k in STRING_FIELDS and typeof(v) != TYPE_STRING:
			fail("%s.%s is %s, not String" % [type, k, type_string(typeof(v))])
		elif k in ["time", "hit_after", "interval", "duration"] and typeof(v) != TYPE_FLOAT:
			fail("%s.time is not float" % type)
	match type:
		"job_advance_pending":
			for o: Dictionary in e.options:
				var ok: Array = o.keys()
				ok.sort()
				if ok != ["available", "job_id", "name", "reason"]:
					fail("job option fields %s" % [ok])
				elif typeof(o.job_id) != TYPE_INT or typeof(o.available) != TYPE_BOOL:
					fail("job option types %s" % [o])
		"choice_pending":
			for c: Dictionary in e.cards:
				var ck: Array = c.keys()
				ck.sort()
				if ck != ["desc", "icon", "id", "kind", "max_rank", "name", "rank", "skill", "skill_changes", "skill_level", "skill_level_next",
						"skill_name"]:
					fail("card fields %s" % [ck])
				elif typeof(c.rank) != TYPE_INT or typeof(c.max_rank) != TYPE_INT or typeof(c.skill_level) != TYPE_INT 						or typeof(c.skill_level_next) != TYPE_INT:
					fail("card rank types %s" % [c])
				elif not (c.skill_changes is Dictionary):
					fail("card skill_changes is not a Dictionary")
				else:
					for field: String in c.skill_changes:
						var change: Dictionary = c.skill_changes[field]
						if not field in ["mad", "mastery", "mpCon", "fixdamage", "time", "x", "pdd"] or change.size() != 2 \
								or typeof(change.get("before")) != TYPE_INT or typeof(change.get("after")) != TYPE_INT:
							fail("card skill change schema %s: %s" % [field, change])
		"mob_hit":
			if int(e.damage) < 1:
				fail("damage below 1")
		"player_hit":
			if bool(e.miss) and (int(e.damage) != 0 or int(e.mp_absorbed) != 0):
				fail("a missed hit cannot spend HP or MP")
			elif not bool(e.miss) and int(e.damage) < 1:
				fail("a landed hit must deal at least 1")
		"cast":
			if not (int(e.facing) in [-1, 1]):
				fail("facing %s" % e.facing)


func test_every_event_matches_the_schema() -> void:
	var w := RunWorld.new(RF.setup("henesys_hg1", 4242))
	w.god = true # Schema coverage uses a living run; separate seeded full runs test actual survival.
	var seen := {}
	var memo := {}
	var declined := false
	for t in 60 * 360:
		var guard := 0
		while w.state != RunWorld.PLAYING and w.state != RunWorld.DEAD and w.state != RunWorld.CLEARED and guard < 64:
			guard += 1
			if w.state == RunWorld.CHOOSING_JOB and not declined:
				declined = w.decline_job()
			else:
				RF.auto_choose(w)
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, RF.bot_input(w, memo))
		for e: Dictionary in w.drain_events():
			_check(e, seen)
	if w.state == RunWorld.PLAYING:
		w.duration = w.time
		w.bosses = BossDirector.new() # The clear event's schema is independent of the boss clear gate.
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			_check(e, seen)
	# A death for player_died.
	var d := RF.quiet_world(400.0)
	RF.put_mob(d, 1110100, 430.0)
	for t in 60 * 20:
		d.step(DT, MoveInput.new())
		if d.state == RunWorld.DEAD:
			break
	for e: Dictionary in d.drain_events():
		_check(e, seen)
	# Both player-hit variants obey the same documented event schema.
	var m := RF.quiet_world(400.0, 617)
	m.loadout.add_player_mod("avoid", "add", 1000.0)
	m.refresh_player_stats()
	m.drain_events()
	m.take_hit(82.0, false, "", m.player.pos, {"accuracy": 42})
	for e: Dictionary in m.drain_events():
		_check(e, seen)
	# A short scheduled boss encounter covers warning/spawn/death and a boss hit's source fields.
	var boss_setup := RF.setup("quiet", 19, RF.quiet_data())
	boss_setup.data.balance.player.skills = []
	boss_setup.data.stages.stages.quiet.bosses = [{"time": 0.5, "mob_id": 100100}]
	var b := RunWorld.new(boss_setup)
	b.god = true
	for tick in 35:
		b.step(DT, MoveInput.new())
	var slot := int(b.bosses.records[0].slot)
	b.mob_kinds[b.swarm.kind[slot]].move_speed = 0
	for tick in 360:
		b.step(DT, MoveInput.new())
	slot = int(b.bosses.records[0].slot)
	b.god = false
	b.take_hit(12.0, false, "", b.player.pos, {"mob": slot, "mob_id": 100100, "boss": true})
	b.hit_mob(slot, {"damage_min": 999.0, "damage_max": 999.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	b.step(DT, MoveInput.new())
	for e: Dictionary in b.drain_events():
		_check(e, seen)
	# A same-map warp for portal_used (the synthetic hunting ground otherwise has only spawn points).
	var p_setup := RF.setup("quiet", 17, RF.quiet_data())
	p_setup.map_img.portal = {
		"0": {"pn": "source", "pt": 1, "x": 400, "y": 200, "tm": 999999999, "tn": "destination"},
		"1": {"pn": "destination", "pt": 1, "x": 800, "y": 80, "tm": 999999999, "tn": ""},
	}
	var p := RunWorld.new(p_setup)
	p.player.place(Vector2(400, 200), p.fhm)
	p.step(DT, MoveInput.make(false, false, true))
	for e: Dictionary in p.drain_events():
		_check(e, seen)
	var basic_world := preload("res://tests/fixtures/basic_attack_fixtures.gd").world()
	RF.put_mob(basic_world, 100100, 450, 190, 100)
	for tick in 30:
		basic_world.step(DT, MoveInput.new())
	for event: Dictionary in basic_world.drain_events():
		_check(event, seen)
	# Guaranteed potion use and collection exercise the consumable schema regardless of random drop rolls.
	var potion := RF.quiet_world()
	potion.spawn_potion("mp", potion.player.pos - Vector2(0, 25), 2)
	potion.step(DT, MoveInput.new())
	potion.drink_potion("hp")
	potion.drink_potion("mp")
	potion.progression.level = 10
	potion.upgrades.apply("orange_potion", potion)
	for e: Dictionary in potion.drain_events():
		_check(e, seen)
	var buff_setup := RF.setup("quiet", 12, RF.quiet_data())
	buff_setup.data.balance.player.skills = []
	buff_setup.data.balance.regen.mp = 0
	var buff_world := RunWorld.new(buff_setup)
	buff_world.change_job(200)
	buff_world.loadout.ranks.erase("energy_bolt")
	buff_world.loadout.order.erase("energy_bolt")
	buff_world.learn_skill("magic_guard")
	buff_world.learn_skill("magic_armor")
	for tick in 2:
		buff_world.step(DT, MoveInput.new())
	buff_world.spend_mp(int(buff_world.player_state.mp))
	for tick in 60 * 112:
		buff_world.step(DT, MoveInput.new())
	for e: Dictionary in buff_world.drain_events():
		_check(e, seen)
	for type: String in RunWorld.EVENT_FIELDS:
		if type == "mp_short":
			var short_world := RF.quiet_world()
			short_world.change_job(200)
			short_world.spend_mp(int(short_world.player_state.mp))
			RF.put_mob(short_world, 1110100, short_world.player.pos.x + 100, 190, 100)
			for tick in 3:
				short_world.step(DT, MoveInput.new())
			for event: Dictionary in short_world.drain_events():
				_check(event, seen)
		assert_true(seen.has(type), "%s was emitted (seen %s)" % [type, seen])
	assert_true(declined, "the run went through a declined job window")


func _digest(p_seed: int, seconds: float) -> String:
	var w := RunWorld.new(RF.setup("henesys_hg1", p_seed))
	var memo := {}
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for t in roundi(seconds * 60.0):
		RF.auto_choose(w)
		if w.state != RunWorld.PLAYING:
			break
		w.step(DT, RF.bot_input(w, memo))
		for e: Dictionary in w.drain_events():
			ctx.update(var_to_str(e).to_utf8_buffer())
	ctx.update(var_to_str(w.player_state).to_utf8_buffer())
	return ctx.finish().hex_encode()


func test_seeded_runs_replay_identically() -> void:
	var a := _digest(31, 90.0)
	var b := _digest(31, 90.0)
	var c := _digest(32, 90.0)
	assert_eq(a, b, "same seed, same events")
	assert_ne(a, c, "another seed differs")
