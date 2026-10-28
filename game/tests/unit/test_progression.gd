extends TestCase
## ExpCurve, RunProgression and RunWorld's pause protocol (docs/ARCHITECTURE.md 4.4.2): level queue, choice windows
## (no job advancement since #284), touch damage with invincibility / knockback / Magic Guard, death and stage clear.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const CARD_KEYS := ["rarity_bonus", "skill_rank_before", "skill_rank_max", "card_kind", "slots", "id", "kind", "name", "desc", "icon", "tier", "magnitude", "rank_before", "rank", "max_rank", "skill", "skill_name", "skill_level",
	"skill_level_next", "skill_level_max", "skill_changes", "skill_effect_stat", "skill_mod_changes"]


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


## A worked survivor-data example: round(4 + 12 L + 4.4 L^2), independent of subsequent balance calibration.
func test_exp_curve_values() -> void:
	var c := ExpCurve.from_data({"a": 4, "b": 12, "c": 4.4})
	assert_eq(c.exp_to_next(1), 20, "round(20.4)")
	assert_eq(c.exp_to_next(2), 46, "round(45.6)")
	assert_eq(c.exp_to_next(7), 304, "round(303.6)")
	assert_eq(c.exp_to_next(29), 4052, "round(4052.4)")
	assert_eq(c.total_to(8), 980, "worked sum from level 1 to 8")
	assert_eq(c.total_to(10), 1830, "worked sum from level 1 to 10")
	assert_eq(c.total_to(30), 42978, "worked sum from level 1 to 30")
	assert_eq(ExpCurve.new().exp_to_next(29), 3600, "missing-data fallback preserves the original curve")
	assert_eq(ExpCurve.new().total_to(8), 812, "fallback is independent of configured survivor tuning")

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
	assert_eq(w.player_state.max_hp, 62, "50 + 12 (the Magician growth of 212's line)")
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


func test_touch_damage_invincibility_knockback_and_death() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = "" # Contact fixture must not kill its target first.
	var w := RunWorld.new(RF.setup("quiet", 7, data))
	RF.place_player(w, 400.0)
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
				assert_false(e.has("mp_absorbed"), "no MP (#285)")
				assert_eq(e.dir, -1, "pushed away from the mob on the right")
			elif e.type == "player_died":
				died = true
		if w.state != RunWorld.PLAYING:
			break
	assert_true(died, "one Green Mushroom hit kills a level 1 character without gear")
	assert_eq(w.state, RunWorld.DEAD)
	assert_true(w.player_state.dead)
	assert_eq(w.player_state.hp, 0)
	assert_eq(w.player_state.action, "dead")
	assert_eq(hits.size(), 1)
	var t := w.time
	w.step(DT, MoveInput.new())
	assert_eq(w.time, t, "DEAD: step is a no-op")


func test_knockback_and_whole_damage_to_hp() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = "" # Contact fixture must not kill its target first.
	var w := RunWorld.new(RF.setup("quiet", 7, data))
	RF.place_player(w, 400.0)
	RF.change_job_bare(w, 200)
	w.drain_events()
	RF.put_mob(w, 130101, 375.0)
	var hit: Dictionary = {}
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
	assert_eq(w.player_state.hp, hp0 - int(hit.damage), "the whole hit comes off HP: no Magic Guard (#285)")
	assert_true(w.player.vel.x > 0.0, "knocked back")
	assert_true(w.player_state.invincible_t > 1.4)


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
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = "three_snails" # the Beginner skill's level_ranks rule
	var w := RunWorld.new(RF.setup("quiet", 7, data))
	RF.place_player(w, 400.0)
	assert_eq(w.loadout.rank("three_snails"), 1, "rank 1 at level 1")
	var ranks := {}
	for target in [3, 6]:
		_give_exp(w, w.progression.curve.total_to(target) - w.progression.curve.total_to(w.progression.level)
			- w.progression.exp)
		var guard := 0
		while w.state != RunWorld.PLAYING and guard < 32:
			guard += 1
			# No card raises Three Snails: the rank comes from the character level alone.
			for c: Dictionary in w.pending_cards:
				assert_ne(String(c.get("kind", "")) + ":" + String(c.get("skill", "")), "skill_rank:three_snails",
					"no Three Snails rank card is offered")
			w.apply_choice(String(w.pending_cards[0].id))
		ranks[target] = w.loadout.rank("three_snails")
		assert_eq(int(w.player_state.level), target, "reached level %d" % target)
	assert_eq(ranks.get(3), 2, "level 3: Three Snails rank 2 (skill level 2)")
	assert_eq(ranks.get(6), 3, "level 6: rank 3 (skill level 3, the max)")
