extends TestCase
## ExpCurve, RunProgression, JobTree and RunWorld's pause protocol (docs/ARCHITECTURE.md 4.4.2): level queue,
## choice windows, job advancement at 8 (accept / "Not now"), the guaranteed Magician card, touch damage with
## invincibility / knockback / Magic Guard, death and stage clear.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CARD_KEYS := ["id", "kind", "name", "desc", "icon", "rank", "max_rank", "skill", "skill_name", "skill_level",
	"skill_level_next", "skill_changes"]
const JOB_OPTION_KEYS := ["job_id", "name", "available", "reason"]


## Drops `n` EXP on the player and steps until it is collected (or a window opens).
func _give_exp(w: RunWorld, n: int) -> void:
	var i := w.pickups.spawn(w.player.pos, n, 4000019)
	for t in 120:
		if w.state != RunWorld.PLAYING or w.pickups.active[i] == 0:
			return
		w.step(DT, MoveInput.new())


func _of_type(events: Array, type: String) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		if e.type == type:
			out.append(e)
	return out


func _sorted_keys(d: Dictionary) -> Array:
	var k := d.keys()
	k.sort()
	return k


func _sorted(a: Array) -> Array:
	var c := a.duplicate()
	c.sort()
	return c


## The tuned curve of balance.json (docs/GAME_DESIGN.md 5): round(4 + 8 L + 4 L^2).
func test_exp_curve_values() -> void:
	var c := ExpCurve.from_data(DataRepo.load_all().balance.exp_curve)
	assert_eq(c.exp_to_next(1), 16, "4 + 8 + 4")
	assert_eq(c.exp_to_next(2), 36, "4 + 16 + 16")
	assert_eq(c.exp_to_next(7), 256, "4 + 56 + 196")
	assert_eq(c.exp_to_next(29), 3600, "4 + 232 + 3364")
	assert_eq(c.total_to(8), 16 + 36 + 64 + 100 + 144 + 196 + 256, "EXP from 1 to 8 (812)")
	assert_eq(c.total_to(10), 1536, "EXP from 1 to 10")
	assert_eq(c.total_to(30), 37816, "EXP from 1 to 30")
	assert_eq(ExpCurve.new().exp_to_next(29), 3600, "defaults = the design curve")
	assert_eq(ExpCurve.new().total_to(8), c.total_to(8), "defaults = the design curve")


func test_run_progression_queue() -> void:
	var curve := ExpCurve.new()
	var p := RunProgression.new(curve)
	var l1 := curve.exp_to_next(1)
	assert_eq(p.add_exp(l1 - 1), 0)
	assert_eq(p.level, 1)
	assert_eq(p.add_exp(1), 1, "exp_to_next(1) -> level 2")
	assert_eq(p.exp, 0)
	assert_eq(p.add_exp(curve.exp_to_next(2) + curve.exp_to_next(3) + 5), 2, "two more levels at once")
	assert_eq(p.level, 4)
	assert_eq(p.exp, 5)
	assert_eq(p.queue, PackedInt32Array([2, 3, 4]))
	assert_eq(p.front(), 2)
	p.pop_front()
	assert_eq(p.front(), 3)
	var capped := RunProgression.new(ExpCurve.new(), 3)
	capped.add_exp(100000)
	assert_eq(capped.level, 3, "max level")
	assert_eq(capped.exp, 0)


func test_job_tree_options() -> void:
	var data := DataRepo.load_all()
	var t := JobTree.from_data(data.jobs, data.jobs_survivor)
	var at8 := t.advancements(0, 8)
	var ids: Array = []
	for o: Dictionary in at8:
		ids.append(int(o.job_id))
		assert_eq(_sorted_keys(o), _sorted(JOB_OPTION_KEYS))
		if int(o.job_id) == 200:
			assert_true(o.available, "Magician at 8")
			assert_eq(o.name, "Magician")
			assert_eq(o.reason, "")
		else:
			assert_false(o.available)
			assert_eq(o.reason, "Lv. 10", "%d shows its requirement" % o.job_id)
	assert_eq(_sorted(ids), [100, 200, 300, 400, 500])
	for o: Dictionary in t.advancements(0, 10):
		if int(o.job_id) != 200:
			assert_eq(o.reason, "Not in this build")
	assert_true(t.should_offer(0, 8))
	assert_true(t.should_offer(0, 9), "declined: asked again")
	assert_false(t.should_offer(0, 7))
	var at30 := t.advancements(200, 30)
	assert_eq(at30.size(), 3)
	for o: Dictionary in at30:
		assert_false(o.available, "%d not playable yet" % o.job_id)
		if int(o.job_id) == 210:
			assert_eq(o.reason, "Phase 2")
	assert_true(t.should_offer(200, 30), "shown once at 30")
	assert_false(t.should_offer(200, 31), "nothing available: not again")
	assert_eq(t.name_of(200), "Magician")
	assert_true(t.is_descendant(210, 200))
	assert_false(t.is_descendant(200, 210))
	assert_eq(t.job(200).grants.max_mp, 120.0)


func test_pause_protocol_single_level() -> void:
	var w := RF.quiet_world()
	w.drain_events()
	_give_exp(w, w.progression.curve.exp_to_next(1))
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	assert_eq(w.state_name(), "CHOOSING_UPGRADE")
	var ev := w.drain_events()
	var lv := _of_type(ev, "level_up")
	assert_eq(lv.size(), 1)
	if lv.size() == 1:
		assert_eq(lv[0].level, 2)
	var cp := _of_type(ev, "choice_pending")
	assert_eq(cp.size(), 1)
	var cards: Array = cp[0].cards if cp.size() == 1 else []
	assert_eq(cards.size(), 3, "three cards")
	for c: Dictionary in cards:
		assert_eq(_sorted_keys(c), _sorted(CARD_KEYS), "card fields")
		assert_eq(c.rank, 1, "rank the card gives")
		assert_false("{value}" in String(c.desc), "placeholders filled")
	assert_eq(w.player_state.level, 2)
	assert_eq(w.player_state.max_hp, 64, "50 + 14")
	var t := w.time
	var pos := w.player.pos
	var mob := RF.put_mob(w, 100100, 900.0)
	var mx := w.swarm.x[mob]
	for i in 30:
		w.step(DT, MoveInput.make(false, true))
	assert_eq(w.time, t, "step is a no-op while choosing")
	assert_eq(w.player.pos, pos)
	assert_eq(w.swarm.x[mob], mx)
	assert_false(w.apply_choice("no_such_card"))
	assert_false(w.apply_job(200), "no job window open")
	assert_false(w.decline_job())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
	assert_true(w.apply_choice(String(cards[0].id)))
	var after := w.drain_events()
	var ua := _of_type(after, "upgrade_applied")
	assert_eq(ua.size(), 1)
	if ua.size() == 1:
		assert_eq(ua[0].id, cards[0].id)
		assert_eq(ua[0].rank, 1)
	assert_eq(w.state, RunWorld.PLAYING, "apply_choice resumes")
	assert_false(w.apply_choice(String(cards[1].id)), "the window is closed")
	w.step(DT, MoveInput.new())
	assert_true(w.time > t, "running again")


func test_level_queue_opens_one_window_per_level() -> void:
	var w := RF.quiet_world()
	w.drain_events()
	_give_exp(w, w.progression.curve.total_to(4))
	var ev := w.drain_events()
	assert_eq(_of_type(ev, "level_up").size(), 3, "all three level_up events at once")
	assert_eq(w.player_state.level, 4)
	var windows := 0
	while w.state == RunWorld.CHOOSING_UPGRADE and windows < 10:
		windows += 1
		assert_true(w.apply_choice(String(w.pending_cards[0].id)))
	assert_eq(windows, 3, "one choice per queued level")
	assert_eq(w.state, RunWorld.PLAYING)
	assert_eq(_of_type(w.drain_events(), "choice_pending").size(), 2, "the next two windows")


func test_job_advancement_decline_then_accept() -> void:
	var w := RF.quiet_world()
	w.drain_events()
	_give_exp(w, w.progression.curve.total_to(8))
	assert_eq(w.player_state.level, 8)
	var guard := 0
	while w.state == RunWorld.CHOOSING_UPGRADE and guard < 20:
		guard += 1
		for c: Dictionary in w.pending_cards:
			assert_false(String(c.id) in ["energy_bolt_new", "fire_arrow_new", "magic_claw_new", "magic_guard_new",
				"magic_armor_new"], "no job skill before the job: %s" % c.id)
		w.apply_choice(String(w.pending_cards[0].id))
	assert_eq(guard, 6, "levels 2..7 are plain upgrades")
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "level 8: the job window first")
	var pend := _of_type(w.drain_events(), "job_advance_pending")
	assert_eq(pend.size(), 1)
	if pend.size() == 1:
		var opts: Array = pend[0].options
		assert_eq(opts.size(), 5)
		for o: Dictionary in opts:
			assert_eq(bool(o.available), int(o.job_id) == 200, "only Magician is available")
	assert_false(w.apply_job(300), "Bowman is not available")
	assert_true(w.decline_job())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "then the level-8 upgrade")
	w.apply_choice(String(w.pending_cards[0].id))
	assert_eq(w.state, RunWorld.PLAYING)
	assert_eq(w.player_state.job_id, 0, "still a Beginner")
	_give_exp(w, w.progression.curve.exp_to_next(8))
	assert_eq(w.player_state.level, 9)
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "asked again at the next level")
	var mp_before: int = w.player_state.max_mp
	w.drain_events()
	assert_true(w.apply_job(200))
	var ev := w.drain_events()
	var jc := _of_type(ev, "job_changed")
	assert_eq(jc.size(), 1)
	if jc.size() == 1:
		assert_eq(jc[0].job_id, 200)
		assert_eq(jc[0].name, "Magician")
	assert_eq(w.player_state.job_id, 200)
	assert_eq(w.player_state.max_mp, mp_before + 120, "MP +120")
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "then the upgrade window of that level")
	var magician_card := false
	for c: Dictionary in w.pending_cards:
		if c.kind == "skill_new" and int(w.book.def(String(c.skill)).get("job", -1)) == 200:
			magician_card = true
	assert_true(magician_card, "the first draw after advancing has a Magician skill card")


func test_guarantee_holds_for_many_seeds() -> void:
	for seed_i in 8:
		var w := RF.quiet_world(400.0, 100 + seed_i)
		w.change_job(200)
		_give_exp(w, w.progression.curve.exp_to_next(1))
		var ok := false
		for c: Dictionary in w.pending_cards:
			if c.kind == "skill_new" and int(w.book.def(String(c.skill)).get("job", -1)) == 200:
				ok = true
		assert_true(ok, "seed %d" % seed_i)
		assert_true(w.guarantee.is_empty(), "consumed")


func test_touch_damage_invincibility_knockback_and_death() -> void:
	var w := RF.quiet_world(400.0)
	w.drain_events()
	RF.put_mob(w, 1110100, 430.0)
	var hits: Array = []
	var died := false
	for t in 60 * 30:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "player_hit":
				hits.append([w.time, e])
				assert_eq(typeof(e.damage), TYPE_INT)
				assert_between(e.damage, 70, 82, "Green Mushroom PAD 82 x [0.85, 1], synthetic player has no gear")
				assert_eq(e.mp_absorbed, 0, "no Magic Guard")
				assert_eq(e.dir, -1, "pushed away from the mob on the right")
			elif e.type == "player_died":
				died = true
		if w.state != RunWorld.PLAYING:
			break
	assert_true(died, "one Green Mushroom hit kills a level 1 Beginner without gear")
	assert_eq(w.state, RunWorld.DEAD)
	assert_true(w.player_state.dead)
	assert_eq(w.player_state.hp, 0)
	assert_eq(w.player_state.action, "dead")
	assert_eq(hits.size(), 1)
	var t := w.time
	w.step(DT, MoveInput.new())
	assert_eq(w.time, t, "DEAD: step is a no-op")


func test_knockback_and_magic_guard_split() -> void:
	var w := RF.quiet_world(400.0)
	RF.change_job_bare(w, 200)
	w.learn_skill("magic_guard")
	w.heal_fraction("mp", 1.0)
	w.drain_events()
	RF.put_mob(w, 130101, 375.0)
	var hit: Dictionary = {}
	var mp0: int = w.player_state.mp
	var hp0: int = w.player_state.hp
	for t in 120:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "player_hit" and hit.is_empty():
				hit = e
		if not hit.is_empty():
			break
	assert_false(hit.is_empty(), "the Red Snail touches")
	if hit.is_empty():
		return
	assert_eq(hit.dir, 1, "pushed right, away from the mob on the left")
	assert_eq(hit.mp_absorbed, floori(int(hit.damage) * 11 / 100.0), "Magic Guard L1: 11% to MP")
	assert_eq(w.player_state.hp, hp0 - int(hit.damage) + int(hit.mp_absorbed))
	assert_true(w.player.vel.x > 0.0, "knocked back")
	assert_true(w.player_state.invincible_t > 1.4)
	assert_true(int(w.player_state.mp) <= mp0)


func test_stage_clear() -> void:
	var w := RF.quiet_world()
	w.duration = 2.0
	w.drain_events()
	for t in 200:
		w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CLEARED)
	var sc := _of_type(w.drain_events(), "stage_cleared")
	assert_eq(sc.size(), 1)
	if sc.size() == 1:
		assert_near(sc[0].time, 2.0, DT)
	assert_near(w.time, 2.0, DT, "stopped at the duration")


func test_level_ranks_raise_a_skill_with_the_character_level() -> void:
	# skills.json: Three Snails reaches skill level 2 at Lv 3 and 3 at Lv 6 (the v83 Beginner SP).
	assert_eq(DataRepo.load_all().skills.skills.three_snails.level_ranks, {"3": 2.0, "6": 3.0})
	var w := RF.quiet_world(400.0)
	assert_eq(w.loadout.rank("three_snails"), 1, "rank 1 at level 1")
	var ranks := {}
	for target in [3, 6]:
		_give_exp(w, w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level)
			- w.progression.exp)
		var guard := 0
		while w.state != RunWorld.PLAYING and guard < 32:
			guard += 1
			if w.state == RunWorld.CHOOSING_JOB:
				w.decline_job()
				continue
			# No card raises Three Snails: the rank comes from the character level alone.
			for c: Dictionary in w.pending_cards:
				assert_ne(String(c.get("kind", "")) + ":" + String(c.get("skill", "")), "skill_rank:three_snails",
					"no Three Snails rank card is offered")
			w.apply_choice(String(w.pending_cards[0].id))
		ranks[target] = w.loadout.rank("three_snails")
		assert_eq(int(w.player_state.level), target, "reached level %d" % target)
	assert_eq(ranks.get(3), 2, "level 3: Three Snails rank 2 (skill level 2)")
	assert_eq(ranks.get(6), 3, "level 6: rank 3 (skill level 3, the max)")


func test_job_grants_skills() -> void:
	# jobs.json: advancing to Magician teaches Energy Bolt (the first SP of a v83 Magician).
	assert_eq(DataRepo.load_all().jobs_survivor.jobs["200"].grants.skills, ["energy_bolt"])
	var w := RF.quiet_world(400.0)
	w.drain_events()
	w.change_job(200)
	var ev := w.drain_events()
	assert_true(w.loadout.has("energy_bolt"), "advancing teaches Energy Bolt")
	assert_eq(w.loadout.rank("energy_bolt"), 1)
	var learned := _of_type(ev, "skill_learned")
	assert_eq(learned.size(), 1, "one skill_learned")
	if learned.size() == 1:
		assert_eq(learned[0].skill, "energy_bolt")
	assert_eq(String(_of_type(ev, "job_changed")[0].type), "job_changed", "job_changed comes first")
	assert_true(ev.find(_of_type(ev, "job_changed")[0]) < ev.find(learned[0]), "then skill_learned")
