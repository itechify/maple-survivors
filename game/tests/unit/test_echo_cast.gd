extends TestCase
## Echo summon (spec #383 M11, docs/GAME_DESIGN.md 7.91): a clone on the PlayerSummons seam repeats a star cast
## `delay` seconds later at a percent of its damage, on synthetic data (a test clone `test_shadow` with the real x / y
## shapes and a test star `test_star`; Shadow Partner and the real star skills come with their own tickets).
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Per-level table of the test clone: x = 10 per level, y = 5 per level (rank 1 reads level 4, rank 8 level 30).
const X_PER_LEVEL := 10.0
const Y_PER_LEVEL := 5.0

## A world with the clone skill and the star skill learned (clone first, so it casts alone on the first tick).
## `star` merges into the star's definition; `shadow` into the clone's; `life` is the clone's `time` in seconds.
static func world(star := {}, shadow := {}, life := 60.0, p_seed := 383) -> RunWorld:
	var data := RF.quiet_data()
	var clone: Dictionary = data.skills.skills.elquines.duplicate(true)
	clone.erase("element")
	clone.erase("rarity_bonuses")
	clone.merge({"skill_id": 2129001, "name": "Test Shadow", "damage": "none", "cooldown": 50.0}, true)
	clone.summon = {"echo": {"attack_field": "x", "skill_field": "y", "delay": 0.25},
		"follow_speed": 200.0, "follow_distance": 55.0, "teleport_distance": 600.0, "ordinal_spread": 40.0}
	clone.merge(shadow, true)
	var bolt: Dictionary = data.skills.skills.energy_bolt.duplicate(true)
	bolt.merge({"cooldown": 50.0, "speed": 100.0, "range": 450.0, "count": 1, "echo": {"class": "attack"}}, true)
	bolt.merge(star, true)
	data.skills.skills["test_shadow"] = clone
	data.skills.skills["test_star"] = bolt
	var setup := RF.setup("quiet", p_seed, data)
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"x": X_PER_LEVEL * lv, "y": Y_PER_LEVEL * lv, "time": life}
	setup.skill_imgs["212"].skill["2129001"] = {"level": levels}
	var w := RunWorld.new(setup)
	RF.place_player(w, 200)
	w.loadout.order.clear()
	w.learn_skill("test_shadow")
	w.learn_skill("test_star")
	return w

static func mob(w: RunWorld, px: float, hp := 1000000) -> int:
	var m := RF.put_mob(w, 1110100, px, 195, 100000.0)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m

func _ticks(w: RunWorld, n: int) -> void:
	for t in n:
		w.step(DT, MoveInput.new())

## Summons the clone on tick 1 (no monster yet), then adds a monster 300 px ahead and casts the star on tick 2.
func _cast_star(w: RunWorld, at := 500.0, settle := 0) -> int:
	_ticks(w, 1 + settle)
	var m := mob(w, at)
	_ticks(w, 1)
	return m

func _events(w: RunWorld, type: String) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == type)

## dmg_max of every shot in flight, ascending.
func _flying(w: RunWorld) -> Array:
	var out := []
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			out.append(w.projectiles.dmg_max[i])
	out.sort()
	return out

func _percent(w: RunWorld, field: String, rank := 1) -> float:
	w.loadout.set_rank("test_shadow", rank)
	return w.book.canonical("test_shadow", w.loadout.stats("test_shadow").level, field) / 100.0

# --- the clone on the seam -------------------------------------------------------------------------------------------

func test_a_cast_spawns_a_clone_that_follows_mirrors_and_never_strikes() -> void:
	var w := world()
	mob(w, 230) # in the box of any follower: a clone still never strikes
	_ticks(w, 2)
	var s := w.runner.summons
	assert_eq(s.clones().size(), 1)
	assert_true(s.definitions[0].has("echo"))
	assert_eq(String(s.definitions[0].attack), "", "no attack node")
	w.player.facing = -1
	w.player.pos.x += 300.0
	_ticks(w, 120)
	assert_eq(s.facing[0], -1, "mirrors the owner")
	assert_near(s.x[0], w.player.pos.x + 55.0, 2.0, "trails at follow_distance on the side opposite its facing")
	assert_eq(_events(w, "summon_attack").size(), 0, "no attack cycle")

func test_the_clone_lives_for_time_and_a_recast_replaces_it() -> void:
	var w := world({}, {}, 2.0)
	_ticks(w, 1)
	var s := w.runner.summons
	assert_eq(s.clones().size(), 1)
	var first := s.uid[0]
	s.spawn(w, w.loadout.stats("test_shadow"))
	assert_eq(s.clones().size(), 1, "a recast replaces the clone")
	assert_true(s.uid[s.clones()[0]] != first, "a new spawn serial")
	_ticks(w, 119)
	assert_eq(s.clones().size(), 1)
	_ticks(w, 3)
	assert_eq(s.clones().size(), 0, "gone after its time")

func test_summon_count_makes_two_clones_forty_pixels_apart() -> void:
	var w := world()
	w.loadout.add_skill_mod("test_shadow", "summon_count", "add", 1)
	_ticks(w, 1)
	var s := w.runner.summons
	assert_eq(s.clones().size(), 2)
	assert_near(s.offsets[1] - s.offsets[0], 40.0, 0.001)

func test_map_transfer_death_and_hidden_clear_or_ignore_the_clone_and_pending_echoes() -> void:
	for mode in ["clear", "dead", "hidden"]:
		var w := world()
		_cast_star(w)
		assert_eq(w.runner.echoes.pending_count(), 1, mode)
		match mode:
			"clear": w.runner.clear_pending(w)
			"dead": w.player_state.dead = true
			"hidden": w.buffs.start("hidden_test", {"skill_id": 0, "level": 1, "icon": "", "duration": 10.0, "buff_stat": "", "buff_value": 0.0, "hidden": true, "pulse_interval": 0.0})
		w.runner.echoes.step(DT, w)
		assert_eq(w.runner.echoes.pending_count(), 0 if mode != "clear" else 0, mode)
		assert_eq(_events(w, "echo_cast").size(), 0, mode)
		if mode == "clear":
			assert_eq(w.runner.summons.clones().size(), 0, "a map transfer clears the clone")

# --- what echoes and when ------------------------------------------------------------------------------------------

func test_one_echo_per_shot_per_clone_exactly_delay_later() -> void:
	var w := world({"count": 2})
	_cast_star(w)
	assert_eq(_flying(w).size(), 2, "the owner's two stars")
	assert_eq(w.runner.echoes.pending_count(), 2)
	_ticks(w, 13)
	assert_eq(_flying(w).size(), 2, "not yet: 0.25 s is 15 ticks")
	_ticks(w, 2)
	assert_eq(_flying(w).size(), 4, "the clone's two stars left 15 ticks after the cast")
	assert_eq(_events(w, "echo_cast").size(), 2)
	_ticks(w, 120)
	assert_eq(_events(w, "echo_cast").size(), 2, "never an echo of an echo")

func test_two_clones_echo_every_shot_twice() -> void:
	var w := world({"count": 2})
	w.loadout.add_skill_mod("test_shadow", "summon_count", "add", 1)
	_cast_star(w)
	assert_eq(w.runner.echoes.pending_count(), 4)
	_ticks(w, 16)
	assert_eq(_flying(w).size(), 6, "two stars plus two clones' two echoes each")
	var clones := {}
	for e in _events(w, "echo_cast"):
		clones[int(e.clone)] = int(clones.get(int(e.clone), 0)) + 1
	assert_eq(clones.size(), 2)

func test_the_echo_leaves_the_clones_hand() -> void:
	var w := world()
	_cast_star(w, 500.0, 40) # the clone has arrived at its trailing point
	_ticks(w, 16)
	var s := w.runner.summons
	var body := Vector2(s.x[0], s.y[0] - w.cast_height)
	var echo_index := -1
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0 and w.projectiles.dmg_max[i] < w.loadout.stats("test_star").damage_max:
			echo_index = i
	assert_true(echo_index >= 0, "the echo is in flight")
	assert_near(w.projectiles.y[echo_index], body.y, 12.0, "level with the clone's body")
	# The echo left the hand one or two ticks ago at 100 px/s.
	var hand_x := body.x + w.cast_forward
	assert_near(w.projectiles.x[echo_index], hand_x, 4.0)
	var e: Dictionary = _events(w, "echo_cast")[0]
	assert_eq(e.skill, "test_star")
	assert_eq(e.clone, 0)
	assert_eq(e.facing, 1)
	assert_near(e.pos.x, hand_x, 0.01)

func test_percent_is_x_for_the_attack_class_and_y_for_the_skill_class_by_rank() -> void:
	for cls in ["attack", "skill"]:
		for rank in [1, 4, 8]:
			var w := world({"echo": {"class": cls}})
			w.loadout.set_rank("test_shadow", rank)
			_cast_star(w)
			var owner_max: float = _flying(w)[0]
			_ticks(w, 16)
			var flying := _flying(w)
			assert_eq(flying.size(), 2, "%s rank %d" % [cls, rank])
			flying.erase(owner_max)
			var level: int = w.loadout.stats("test_shadow").level
			var field: float = X_PER_LEVEL * level if cls == "attack" else Y_PER_LEVEL * level
			assert_eq(flying.size(), 1)
			assert_near(flying[0] / owner_max, field / 100.0, 0.0001, "%s rank %d: %d%% of the owner's star" % [cls, rank, field])

func test_the_shadow_damage_modifier_scales_the_echo() -> void:
	var plain := world()
	_cast_star(plain)
	_ticks(plain, 16)
	var boosted := world()
	boosted.loadout.add_skill_mod("test_shadow", "damage", "mul", 1.2)
	_cast_star(boosted)
	_ticks(boosted, 16)
	assert_near(_flying(boosted)[0] / _flying(plain)[0], 1.2, 0.0001)
	assert_near(_flying(boosted)[1], _flying(plain)[1], 0.0001, "the owner's star is not scaled")

func test_a_skill_without_the_echo_flag_and_a_cast_without_a_clone_echo_nothing() -> void:
	var w := world({"echo": null})
	w.book.defs.test_star.erase("echo")
	_cast_star(w)
	_ticks(w, 40)
	assert_eq(_events(w, "echo_cast").size(), 0)
	assert_eq(w.runner.echoes.pending_count(), 0)
	var lone := world()
	lone.runner.cooldowns["test_shadow"] = 1000.0 # the clone is never cast
	mob(lone, 500)
	_ticks(lone, 40)
	assert_eq(_events(lone, "echo_cast").size(), 0, "no clone alive")
	assert_eq(lone.runner.echoes.pending_count(), 0)

func test_an_expired_or_replaced_clone_throws_nothing() -> void:
	var w := world()
	_cast_star(w)
	w.runner.summons.spawn(w, w.loadout.stats("test_shadow")) # replaced before the echo leaves
	_ticks(w, 20)
	assert_eq(_events(w, "echo_cast").size(), 0, "the replaced clone's echo is dropped")
	assert_eq(_flying(w).size(), 1)

# --- the four rules of an echo hit -------------------------------------------------------------------------------

func test_the_snapshot_drops_the_receipt_and_the_heal_and_marks_the_echo() -> void:
	var w := world()
	_ticks(w, 1)
	var m := mob(w, 500)
	var st := w.loadout.stats("test_star")
	st["meter_receipt"] = {"landed": false}
	st["damage_heal"] = {"percent_field": "x"}
	w.runner.echoes.on_cast(w, "test_star", st, [{"slot": m, "aim": w.mob_center(m)}])
	var entry: Dictionary = w.runner.echoes._entries[0]
	assert_false(entry.st.has("meter_receipt"))
	assert_false(entry.st.has("damage_heal"))
	assert_true(entry.st.echo)
	assert_true(st.has("meter_receipt"), "the owner's snapshot is untouched")
	assert_false(st.has("echo"))
	# An echoed cast schedules nothing.
	var before: int = w.runner.echoes.pending_count()
	w.runner.echoes.on_cast(w, "test_star", entry.st, [{"slot": m, "aim": w.mob_center(m)}])
	assert_eq(w.runner.echoes.pending_count(), before)

func test_an_echo_hit_heals_nothing_but_the_owners_hit_does() -> void:
	for echoed in [false, true]:
		var w := world({"damage_heal": {"percent_field": "mad", "max_hp_fraction": 0.5}})
		var m := mob(w, 260)
		w.runner.cooldowns["test_star"] = 1000.0 # only the manual shot below hits
		w.runner.cooldowns["test_shadow"] = 1000.0
		w.player_state.hp = 5
		w._hp = 5.0
		var st := w.loadout.stats("test_star")
		st["echo"] = echoed
		w.runner.fire_shot(w, "test_star", st, w.cast_origin(), w.mob_center(m))
		_ticks(w, 40)
		assert_true(_events(w, "mob_hit").size() > 0, "it hit")
		var restored := _events(w, "player_restored").filter(func(e: Dictionary) -> bool: return e.skill == "test_star")
		assert_eq(restored.size() == 0, echoed, "echo %s" % echoed)

func test_the_echo_keeps_on_hit_statuses() -> void:
	var w := world({"on_hit": {"status": "stun", "duration": 1.5}})
	var m := _cast_star(w, 330)
	for i in w.projectiles.capacity():
		w.projectiles.active[i] = 0 # lose the owner's star: only the echo can stun
	_ticks(w, 15)
	assert_eq(_events(w, "echo_cast").size(), 1)
	assert_eq(w.swarm.status_time(m, MobSwarm.STUN), 0.0)
	for t in 200:
		_ticks(w, 1)
		if w.swarm.hp[m] < 1000000:
			break
	assert_true(w.swarm.hp[m] < 1000000, "the echo landed")
	assert_true(w.swarm.status_time(m, MobSwarm.STUN) > 0.0, "and stunned")

# --- retarget and drop ----------------------------------------------------------------------------------------------

func test_a_dead_target_retargets_to_the_nearest_living_monster_in_reach_of_the_clone() -> void:
	var w := world()
	var first := _cast_star(w, 500)
	var near := mob(w, 60) # left of the clone, in reach
	w.swarm.despawn(first)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_ticks(w, 16)
	assert_eq(_events(w, "echo_cast").size(), 1)
	assert_eq(_events(w, "echo_cast")[0].facing, -1, "thrown at the monster on the left")
	assert_true(w.swarm.is_live(near))

func test_no_monster_in_reach_drops_the_echo_without_refund() -> void:
	var w := world()
	var first := _cast_star(w, 500)
	w.swarm.despawn(first)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	_ticks(w, 20)
	assert_eq(_events(w, "echo_cast").size(), 0)
	assert_eq(w.runner.echoes.pending_count(), 0)
	assert_eq(_flying(w).size(), 1, "only the owner's star")
	assert_true(float(w.runner.cooldowns.test_star) > 40.0, "the cooldown stays spent")

func test_a_reused_slot_is_not_the_recorded_target() -> void:
	var w := world()
	var first := _cast_star(w, 500)
	w.swarm.despawn(first)
	var other := mob(w, 600) # takes the freed slot, but is beyond reach of the clone
	assert_eq(other, first)
	_ticks(w, 16)
	assert_eq(_events(w, "echo_cast").size(), 0)

# --- nothing changes without a clone, and the RNG order is stable -----------------------------------------------

func _digest(w: RunWorld) -> String:
	return var_to_str([w.events, w.swarm.hp.slice(0, 8), w.runner.casts, _flying(w)])

func test_a_world_without_a_clone_is_byte_identical_with_or_without_the_echo_flag() -> void:
	var plain := world({"echo": {"class": "attack"}})
	var bare := world()
	bare.book.defs.test_star.erase("echo")
	for w in [plain, bare]:
		w.runner.cooldowns["test_shadow"] = 1000.0 # the clone is never cast
		mob(w, 500)
		_ticks(w, 90)
	assert_eq(plain.runner.casts, 1)
	assert_eq(_digest(plain), _digest(bare))

func test_twin_worlds_reproduce_the_same_events_and_hp() -> void:
	var digests := []
	for i in 2:
		var w := world({"count": 3})
		w.loadout.add_skill_mod("test_shadow", "summon_count", "add", 1)
		_cast_star(w, 300)
		_ticks(w, 300)
		digests.append(_digest(w))
	assert_eq(digests[0], digests[1])
	assert_true(String(digests[0]).contains("echo_cast"))
