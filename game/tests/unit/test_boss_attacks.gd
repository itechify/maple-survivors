extends TestCase
## Delayed grounded boss attacks through fixed-tick seeded RunWorld, using synthetic art and canonical-shaped metadata.

const BF := preload("res://tests/fixtures/boss_attack_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _start(w: RunWorld) -> Dictionary:
	for tick in 180:
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "boss_attack" and event.phase == "start":
				return event
	fail("the in-range boss should begin its delayed attack")
	return {}


func test_slam_hits_only_at_canonical_impact_time_with_its_own_damage_multiplier() -> void:
	var w := RunWorld.new(BF.setup())
	var start := _start(w)
	if start.is_empty():
		return
	assert_near(float(start.impact_time) - float(start.time), 1.05, 1e-6)
	assert_eq(start.area.size, Vector2(500, 150))
	assert_eq(start.sound, "Sound.wz/Mob.img/6130101/Attack1", "canonical sound property contains no space")
	var before := int(w.player_state.hp)
	for tick in 62:
		w.step(DT, MoveInput.new())
		assert_eq(int(w.player_state.hp), before, "windup cannot damage before attackAfter")
	w.step(DT, MoveInput.new())
	var hit := {}
	var impact := {}
	for event: Dictionary in w.drain_events():
		if event.type == "player_hit":
			hit = event
		elif event.type == "boss_attack" and event.phase == "impact":
			impact = event
	assert_false(hit.is_empty(), "grounded, in-area player takes the slam")
	assert_false(impact.is_empty(), "impact is explicitly reported")
	if hit.is_empty() or impact.is_empty():
		return
	assert_eq(hit.source_kind, "attack", "attack and touch metrics are distinct")
	assert_eq(hit.mob_id, 6130101)
	assert_true(hit.boss)
	assert_between(float(hit.damage) / float(hit.max_hp), 0.4, 0.5)
	assert_near(float(impact.time), float(start.impact_time), DT)


func test_player_can_leave_the_area_during_the_windup() -> void:
	var w := RunWorld.new(BF.setup())
	var start := _start(w)
	if start.is_empty():
		return
	var hp := int(w.player_state.hp)
	# The player begins on the near edge of the 500 px box; run away from the captured anchor.
	var left := float(start.pos.x) > w.player.pos.x
	for tick in 64:
		w.step(DT, MoveInput.make(left, not left))
	assert_eq(int(w.player_state.hp), hp, "being outside at impact dodges the slam")
	var landed := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
	assert_true(landed.is_empty())


func test_jump_after_windup_dodges_even_while_still_inside_the_area() -> void:
	var w := RunWorld.new(BF.setup())
	var start := _start(w)
	if start.is_empty():
		return
	var hp := int(w.player_state.hp)
	for tick in 44:
		w.step(DT, MoveInput.new())
	w.step(DT, MoveInput.make(false, false, false, false, true, true))
	for tick in 18:
		w.step(DT, MoveInput.make(false, false, false, false, false, true))
	assert_true(w.player.fh < 0, "the jump is still airborne at impact")
	assert_true((start.area as Rect2).intersects(Rect2(w.player.pos + w.body.position, w.body.size), true),
		"the dodge comes from jumpAttack, not leaving the box")
	assert_eq(int(w.player_state.hp), hp)
	var events := w.drain_events()
	assert_true(events.any(func(e: Dictionary) -> bool: return e.type == "boss_attack" and e.phase == "impact"))
	assert_false(events.any(func(e: Dictionary) -> bool: return e.type == "player_hit"))


func test_asymmetric_attack_area_mirrors_with_captured_facing() -> void:
	var facings := {}
	for seed_value in range(2302, 2312):
		var w := RunWorld.new(BF.setup(6130101, seed_value, Rect2(-250, -150, 250, 150)))
		var start := _start(w)
		if start.is_empty():
			continue
		facings[int(start.facing)] = true
		var expected: Rect2 = Rect2(start.pos + Vector2(-250, -150), Vector2(250, 150)) if int(start.facing) < 0 \
			else Rect2(start.pos + Vector2(0, -150), Vector2(250, 150))
		assert_eq(start.area, expected, "WZ's left-facing box is mirrored for a right-facing boss")
	assert_true(facings.has(-1) and facings.has(1), "seeded scenarios cover both directions")


func test_both_canonical_mushroom_slams_stay_in_the_documented_hp_band() -> void:
	for id in [6130101, 9400205]:
		for seed_value in range(2302, 2332):
			var w := RunWorld.new(BF.setup(id, seed_value))
			var start := _start(w)
			if start.is_empty():
				continue
			for tick in 63:
				w.step(DT, MoveInput.new())
			var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
			assert_eq(hits.size(), 1)
			if hits.size() == 1:
				assert_between(float(hits[0].damage) / float(hits[0].max_hp), 0.4, 0.5)
				assert_eq(hits[0].source_kind, "attack")


func test_dead_boss_cannot_finish_a_pending_slam_while_other_bosses_live() -> void:
	var setup := BF.setup()
	setup.data.balance.bosses.rewards.bonus_choices = 0
	setup.data.balance.bosses.rewards.exp_mult = 0
	RF.set_bosses(setup.data.stages.stages.quiet, DataRepo.stage_bosses(setup.data.stages.stages.quiet) + [{"mob_id": 2220000, "time": 0.5}])
	var w := RunWorld.new(setup)
	var start := _start(w)
	if start.is_empty():
		return
	w.hit_mob(int(start.mob), {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	w.drain_events()
	for tick in 63:
		w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.PLAYING, "the second living boss keeps the run active")
	var events := w.drain_events()
	assert_false(events.any(func(e: Dictionary) -> bool: return e.type == "boss_attack" and e.phase == "impact"))


func test_real_mushroom_attack_metadata_keeps_its_canonical_impact_and_wave_frames() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	for id in [6130101, 9400205]:
		var img := lib.mob_root(id)
		assert_eq(int(img.attack1.info.type), 0)
		assert_eq(int(img.attack1.info.attackAfter), 1050)
		assert_eq(int(img.attack1.info.PADamage), 300)
		assert_eq(int(img.attack1.info.jumpAttack), 1)
		assert_eq(BossAttacks.area_at(img.attack1.info.range, Vector2.ZERO, -1), Rect2(-250, -150, 500, 150))
		var effect := lib.anim("Mob.wz/%07d.img/attack1/info/effect" % id)
		assert_near(effect.frames[8].start, 1.1, 1e-6, "the original ground-wave frames begin after the 1.05 s impact")
		assert_eq(effect.frames[8].size(), Vector2(217, 51))
	lib.free()


## A boss whose first listed attack holds its stance longer than `attack_interval` (the Papulatus clock: attack1 9.21 s against
## 8 s) still casts its other attacks (#476); the attack that has waited longest goes first.
func _attack_starts(w: RunWorld, seconds: float) -> Array[String]:
	var out: Array[String] = []
	w.god = true # the slams are not what is measured; the character must outlive them
	for tick in int(seconds / DT):
		w.step(DT, MoveInput.new())
		for event: Dictionary in w.drain_events():
			if event.type == "boss_attack" and event.phase == "start":
				out.append(String(event.attack))
	return out


func test_a_long_first_attack_does_not_starve_the_second() -> void:
	var w := RunWorld.new(BF.setup(6130101, 2302, Rect2(-250, -150, 500, 150), ["attack1", "attack2"], {"attack1": 9.5}))
	var starts := _attack_starts(w, 60.0)
	assert_true(starts.size() >= 4, "the boss keeps attacking: %s" % [starts])
	assert_true(starts.has("attack2"), "attack2 is cast although attack1 outlasts the 8 s interval: %s" % [starts])
	assert_eq(starts.slice(0, 4), ["attack1", "attack2", "attack1", "attack2"], "the two attacks alternate")


func test_attacks_that_fit_the_interval_keep_their_listed_order() -> void:
	var w := RunWorld.new(BF.setup(6130101, 2302, Rect2(-250, -150, 500, 150), ["attack1", "attack2"]))
	var starts := _attack_starts(w, 40.0)
	assert_true(starts.size() >= 4, "the boss keeps attacking: %s" % [starts])
	assert_eq(starts.slice(0, 4), ["attack1", "attack2", "attack1", "attack2"], "listed order, one cast per interval each")
