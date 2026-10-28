extends TestCase
## Melee-aware bot movement (#162): SkillRunner.reach_of, WeaponReach.reach and BotInput's engage mode, on the
## synthetic map of run_fixtures.gd with seeded RNG and fixed dt. Magician and Beginner inputs are pinned by digests of
## the kiting bot (first captured on main before the engage mode existed).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BF := preload("res://tests/fixtures/basic_attack_fixtures.gd")
const DT := 1.0 / 60.0

## Digest of 900 bot inputs plus player positions in the fixed swarm below, captured on main (b2ef00d lineage).
## Re-captured for #238: the Magician can request unlimited MP on its shared cooldown.
## Re-captured for #259 (wall rule; disabling it reproduces 720344116 / 130203406 exactly).
## Re-captured for #285 (no MP): no MP potion input, skills cast on their cooldown only.
## Re-captured for #284 on top (the #285 digests were 813012817 / 365424704): no basic attack; the Magician is the fresh 212 (Energy Bolt and Teleport), the Beginner
## a job-0 character set up with Three Snails.
const MAGICIAN_DIGEST := 168893068
const BEGINNER_DIGEST := 556679015


## Rolling digest over the decided inputs and the resulting player position, so any change to a decision shows.
func _trace(w: RunWorld, ticks: int) -> int:
	var memo := {}
	var h := 7
	for t in ticks:
		var mi := BotInput.decide(w, memo)
		var bits := int(mi.left) + 2 * int(mi.right) + 4 * int(mi.up) + 8 * int(mi.down) + 16 * int(mi.jump_pressed) \
				+ 32 * int(mi.jump_held) + 64 * int(mi.drink_hp)
		h = (h * 31 + bits) % 1000000007
		w.step(DT, mi)
		w.drain_events()
		h = (h * 31 + int(w.player.pos.x * 4.0)) % 1000000007
	return h


## A seeded swarm of tough snails on both sides of the player; the player is invulnerable so the trace is long.
func _swarm(w: RunWorld) -> void:
	w.god = true
	for i in 6:
		RF.put_mob(w, 100100, 150.0 + 90.0 * i, 190, 100.0)
	for i in 4:
		RF.put_mob(w, 100100, 700.0 + 130.0 * i, 190, 100.0)


func test_magician_inputs_are_identical_to_main() -> void:
	var data := RF.quiet_data()
	var w := RunWorld.new(RF.setup("quiet", 9, data))
	RF.place_player(w, 400)
	_swarm(w)
	var digest := _trace(w, 900)
	assert_eq(digest, MAGICIAN_DIGEST, "Magician bot inputs match main")


func test_beginner_inputs_are_identical_to_main() -> void:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["0"]["starting_skill"] = "three_snails"
	var setup := RF.setup("quiet", 9, data)
	setup["job"] = 0
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	_swarm(w)
	var digest := _trace(w, 900)
	assert_eq(digest, BEGINNER_DIGEST, "Beginner bot inputs match main")


## The weapon-swing world with one synthetic short-reach box skill ("slash", job 100, fixed damage, box 90 px ahead) as the
## only skill, a sword (afterimage reach 88) and an invulnerable player on the first floor facing right.
func _melee_world(seed_value := 9) -> RunWorld:
	var data := RF.quiet_data()
	data.upgrades.cards = []
	data.balance.magnet_radius = 0
	data.skills.skills["slash"] = {"skill_id": 9991001, "book": "999", "job": 100, "kind": "instant",
		"damage": "fixed", "ranks": [1], "cooldown": 1.0, "action": "swingO1", "action_time": 0.4,
		"cast": {"rule": "box"}}
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	setup.skill_imgs["999"] = {"skill": {"9991001": {"level": {"1": {
		"lt": {"$v": [-90.0, -60.0]}, "rb": {"$v": [10.0, 0.0]}, "mobCount": 1.0, "attackCount": 1.0,
		"fixdamage": 10.0, "mpCon": 1.0}}}}}
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.player.facing = 1
	w.god = true
	w.loadout.order.clear()
	w.learn_skill("slash")
	w.drain_events()
	return w


func test_reach_of_reads_projectile_range_box_extent_and_zero_for_non_attacks() -> void:
	var w := _melee_world()
	assert_eq(SkillRunner.reach_of(w.loadout.stats("slash"), w), 90.0, "a box reaches its far edge")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("three_snails"), w), 420.0, "a projectile reaches its range")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("magic_claw"), w), 260.0, "an instant nearest skill reaches its range")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("magic_guard"), w), 0.0, "a buff is not an attack")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("teleport_fp"), w), 0.0, "a manual skill is not an attack")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("slow_fp"), w), 0.0, "a status-only crowd skill is not an attack")
	w.loadout.add_skill_mod("slash", "area", "mul", 1.5)
	assert_eq(SkillRunner.reach_of(w.loadout.stats("slash"), w), 135.0, "area cards widen the box")


func test_weapon_reach_is_the_widest_afterimage_stance_or_the_punch() -> void:
	var w := BF.world(83)
	assert_eq(w.weapon_reach.reach(w), 88.0, "the sword's afterimage box")
	var fresh := BF.world(83)
	fresh.setup.afterimage_imgs.swordOL["0"].swingO3.lt["$v"][0] = -102.0
	assert_eq(fresh.weapon_reach.reach(fresh), 102.0, "the longest stance is the reach")
	assert_eq(fresh.unequip_item("weapon"), "")
	assert_eq(fresh.weapon_reach.reach(fresh), -WeaponReach.BARE_HANDS_BOX.position.x, "bare hands punch")


## Ticks of a fixed swarm of tough snails around the melee world's player where the slash is ready; counts how many
## of them have the nearest mob within the slash's 90 px.
func _ready_ticks_in_reach(w: RunWorld, ticks: int, warmup: int) -> Array:
	var memo := {}
	var ready := 0
	var inside := 0
	for t in ticks:
		var mi := BotInput.decide(w, memo)
		# The cooldown counts down inside the step, so a skill that becomes ready in it still reads DT here.
		if t >= warmup and float(w.runner.cooldowns.get("slash", 0.0)) <= DT + 1e-6:
			var best := INF
			for i in w.swarm.capacity():
				if w.swarm.active[i] != 0:
					best = minf(best, absf(w.swarm.x[i] - w.player.pos.x))
			ready += 1
			if best <= 90.0:
				inside += 1
		w.step(DT, mi)
		w.drain_events()
	return [ready, inside]


func _melee_swarm(w: RunWorld) -> void:
	for i in 3:
		RF.put_mob(w, 100100, 650.0 + 80.0 * i, 190, 1000.0)
	for i in 3:
		RF.put_mob(w, 100100, 150.0 - 40.0 * i, 190, 1000.0)


func test_melee_bot_closes_to_its_reach_on_most_attack_ready_ticks() -> void:
	var w := _melee_world()
	_melee_swarm(w)
	var r := _ready_ticks_in_reach(w, 60 * 40, 60 * 8)
	assert_true(int(r[0]) > 20, "the slash is ready often enough to measure (%d)" % r[0])
	# Threshold: at least 70% of ready ticks after an 8 s approach have a mob inside the 90 px box.
	assert_true(float(r[1]) >= 0.7 * float(r[0]), "ready ticks in reach: %d of %d" % [r[1], r[0]])


func test_without_engage_mode_the_same_swarm_is_kited_out_of_reach() -> void:
	var w := _melee_world()
	w.balance["bot"] = {"engage": {"kite_reach": 0.0}}
	_melee_swarm(w)
	var r := _ready_ticks_in_reach(w, 60 * 40, 60 * 8)
	assert_true(float(r[1]) < 0.5 * float(r[0]), "kiting keeps mobs out of the 90 px box: %d of %d" % [r[1], r[0]])


func test_starter_shot_does_not_make_a_melee_build_kite() -> void:
	var w := _melee_world()
	w.learn_skill("three_snails")
	_melee_swarm(w)
	var r := _ready_ticks_in_reach(w, 60 * 40, 60 * 8)
	assert_true(float(r[1]) >= 0.7 * float(r[0]), "Three Snails (420) is a fallback: %d of %d" % [r[1], r[0]])


func test_melee_bot_walks_to_the_engage_distance_then_holds_facing_the_mob() -> void:
	var w := _melee_world()
	var mob := RF.put_mob(w, 100100, 600, 190, 1000.0)
	var mi := BotInput.decide(w, {})
	assert_true(mi.right and not mi.left, "a mob 200 px ahead: walk toward it")
	assert_false(mi.jump_pressed, "no hop over the mob it is walking to")
	w.swarm.x[mob] = 400.0 + 0.8 * 90.0 - 1.0
	mi = BotInput.decide(w, {})
	assert_false(mi.left or mi.right, "inside 0.8 x reach and facing it: hold still")
	w.swarm.x[mob] = 400.0 - 40.0
	mi = BotInput.decide(w, {})
	assert_true(mi.left and not mi.right, "a mob in reach behind: one press turns toward it")


func test_melee_bot_kites_below_the_hp_threshold_and_during_a_boss_telegraph() -> void:
	var w := _melee_world()
	RF.put_mob(w, 100100, 470, 190, 1000.0)
	assert_false(BotInput.decide(w, {}).left, "healthy: hold the ground facing the mob")
	w.player_state.hp = int(float(w.player_state.max_hp) * 0.2)
	assert_true(BotInput.decide(w, {}).left, "low HP: run from the mob on the right")
	w.player_state.hp = w.player_state.max_hp
	assert_false(BotInput.decide(w, {}).left)
	w.boss_attacks._pending[0] = {}
	assert_true(w.boss_attacks.telegraph_up())
	assert_true(BotInput.decide(w, {}).left, "a boss attack winding up: run")
