extends TestCase
## Event schema conformance (docs/ARCHITECTURE.md 4.4.3): every event RunWorld emits in a real run has `type` plus
## exactly the documented fields, with the documented value types; every type shows up. Also checks seeded replays
## are identical.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

const INT_FIELDS := ["mob", "pickup", "mob_id", "item_id", "job_id", "skill_id", "level", "damage", "mp_absorbed",
	"dir", "exp", "count", "rank", "facing", "relocated_from"]
const BOOL_FIELDS := ["crit", "elite"]
const STRING_FIELDS := ["skill", "hit_visual", "action", "effect", "name", "id"]


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
		elif k == "time" and typeof(v) != TYPE_FLOAT:
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
						if not field in ["mad", "mastery", "mpCon", "fixdamage"] or change.size() != 2 \
								or typeof(change.get("before")) != TYPE_INT or typeof(change.get("after")) != TYPE_INT:
							fail("card skill change schema %s: %s" % [field, change])
		"mob_hit":
			if int(e.damage) < 1:
				fail("damage below 1")
		"cast":
			if not (int(e.facing) in [-1, 1]):
				fail("facing %s" % e.facing)


func test_every_event_matches_the_schema() -> void:
	var w := RunWorld.new(RF.setup("henesys_hg1", 4242))
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
	for type: String in RunWorld.EVENT_FIELDS:
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
