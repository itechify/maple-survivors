extends TestCase
## RunScene's options.policy seam (spec #91, ticket #100) against the real asset cache (SKIP without it; a SKIP proves
## nothing): without a policy, autoplay + autopick play exactly BotInput (decide, pick_job on job_rng, pick_card_for),
## the way RunScene always did; with a policy, its move / choose / observe drive the run instead (autoplay, autopick
## and warp); stop_tick holds the sim at a tick; and RunScene with the playtest policy plays exactly the headless
## driver's round (balance_run.gd run_one: same fingerprint), whatever the number of ticks per frame.

const DT := 1.0 / 60.0
const BR := preload("res://tools/balance_run.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const FINGERPRINT := preload("res://tools/playtest/playtest_fingerprint.gd")
const WINDOWED := preload("res://tools/playtest/windowed_replay.gd")

var lib: AssetLibrary
var scene: RunScene


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()


func after_each() -> void:
	if scene != null and is_instance_valid(scene):
		scene.free()
	scene = null
	lib.free()


func _make(stage: String, p_seed: int, options: Dictionary) -> RunScene:
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	var o := options.duplicate()
	o["use_flow"] = false
	s.configure(stage, p_seed, o)
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	return s


## A RunWorld built like RunScene builds its own (fresh data, the library's loaders, the scene's view size).
func _world_like(s: RunScene, stage: String, p_seed: int) -> RunWorld:
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(DataRepo.load_all(), stage, p_seed, s.world.view_size,
		func(p: String) -> Dictionary:
			var w := lib.img(p)
			return w.root if w != null else {},
		func(id: int) -> Dictionary: return lib.mob_root(id), missing)
	return RunWorld.new(setup)


## The state compared tick by tick between two worlds.
static func _state(w: RunWorld) -> Array:
	return [roundi(w.time / DT), w.player.pos, int(w.player_state.hp), int(w.player_state.mp),
		int(w.player_state.level), int(w.player_state.exp), int(w.player_state.job_id), w.kills, w.swarm.alive_count(),
		w.state]


func test_without_a_policy_autoplay_and_autopick_play_exactly_botinput() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 7, {"autoplay": true, "autopick": true})
	assert_eq(scene.error, "", "scene started")
	var ref := _world_like(scene, "henesys_hg1", 7)
	var memo := {}
	var differing := -1
	var choices := 0
	for t in 60 * 120:
		# RunScene answers a window right after the tick that opened it (before the next tick), as here.
		ref.step(DT, BotInput.decide(ref, memo))
		ref.drain_events()
		choices += BotInput.auto_choose(ref, false, 0)
		scene.advance_frame(DT)
		if differing < 0 and _state(scene.world) != _state(ref):
			differing = t
	assert_eq(differing, -1, "RunScene's autoplay world equals the BotInput loop's every tick (first difference at %d: %s vs %s)"
		% [differing, _state(scene.world), _state(ref)])
	assert_true(choices >= 3, "cards were chosen on the way (%d)" % choices)
	assert_eq(int(scene.counters.autopicks), choices, "every window was resolved by autopick")
	assert_eq(scene.world.loadout.card_ranks, ref.loadout.card_ranks, "the same cards were taken")
	assert_eq(scene.world.job_rng.state, ref.job_rng.state, "the same job RNG draws")


## A run policy stub: always walks right, answers windows with the first card / "not now", counts every call.
class StubPolicy:
	extends RefCounted
	var moves := 0
	var chooses := 0
	var answered := 0
	var observed := 0
	var events := 0

	func move(_w: RunWorld) -> MoveInput:
		moves += 1
		var mi := MoveInput.new()
		mi.right = true
		return mi

	func choose(w: RunWorld) -> void:
		chooses += 1
		while w.state == RunWorld.CHOOSING_JOB or w.state == RunWorld.CHOOSING_UPGRADE:
			answered += 1
			if w.state == RunWorld.CHOOSING_JOB:
				w.decline_job()
			else:
				w.apply_choice(String(w.pending_cards[0].id))

	func observe(_w: RunWorld, batch: Array) -> void:
		observed += 1
		events += batch.size()


func test_a_policy_moves_chooses_and_observes_instead_of_botinput() -> void:
	if not require_cache():
		return
	var stub := StubPolicy.new()
	scene = _make("henesys_hg1", 7, {"autoplay": true, "autopick": true, "policy": stub})
	assert_eq(scene.error, "", "scene started")
	var x0 := scene.world.player.pos.x
	var max_x := x0
	for i in 60 * 90:
		scene.advance_frame(DT)
		max_x = maxf(max_x, scene.world.player.pos.x)
		if scene.world.state == RunWorld.DEAD:
			break
	var ticks := roundi(scene.world.time / DT)
	assert_eq(stub.moves, ticks, "the policy gave the input of every tick")
	assert_eq(stub.observed, ticks, "the policy observed every tick once")
	assert_true(stub.events > 0, "with the tick's events")
	assert_true(max_x > x0 + 200.0, "the player walked right as the stub said (%.0f -> %.0f)" % [x0, max_x])
	assert_true(stub.answered >= 1, "the policy answered the windows (%d)" % stub.answered)
	assert_eq(int(scene.counters.autopicks), stub.chooses, "autopick asked the policy (no BotInput pick)")
	assert_true(scene.world.state != RunWorld.CHOOSING_UPGRADE and scene.world.state != RunWorld.CHOOSING_JOB,
		"no window left open")


func test_warp_with_a_policy_is_played_by_the_policy() -> void:
	if not require_cache():
		return
	var stub := StubPolicy.new()
	scene = _make("henesys_hg1", 7, {"autoplay": true, "autopick": true, "policy": stub, "warp": 5.0})
	assert_near(scene.world.time, 5.0, 1e-6, "warped to 0:05 before the first frame")
	assert_eq(stub.moves, 300, "the policy moved every warp tick")
	assert_eq(stub.observed, 300, "and observed it (warp events go to the policy, not dropped)")


func test_stop_tick_holds_the_sim_until_raised() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 7, {"autoplay": true, "autopick": true, "stop_tick": 120})
	for i in 50:
		scene.advance_frame(DT * 4.0)
	assert_eq(roundi(scene.world.time / DT), 120, "held at tick 120")
	scene.stop_tick = 200
	for i in 50:
		scene.advance_frame(DT * 4.0)
	assert_eq(roundi(scene.world.time / DT), 200, "held again at the raised tick")
	scene.stop_tick = -1
	scene.advance_frame(DT)
	assert_eq(roundi(scene.world.time / DT), 201, "-1 releases the hold, one tick per DT (no burst of held time)")


## A brain that varies its answers deterministically (option id % count), so tactics switch and cards differ from
## the bot's.
class VariedLink:
	extends "res://tools/playtest/brain_link.gd"

	func ask(decide: Dictionary) -> Dictionary:
		var options: Array = decide.options
		return {"id": int(decide.id), "answer": String(options[int(decide.id) % options.size()].id), "source": "varied",
			"confidence": null}


## The headless driver's round (playtest_driver.gd: its loaders, an 800x600 view, run_one) for `cap` seconds.
func _headless_round(stage: String, seed_value: int, cap: float, params: Dictionary) -> Dictionary:
	var data := DataRepo.load_all()
	data.balance["run_time_cap"] = cap
	var root := AssetCachePaths.resolve_cache_root()
	var missing := PackedStringArray()
	var setup := DataRepo.build_setup(data, stage, 0, Vector2(800, 600),
		func(p: String) -> Dictionary: return BR._json(root, p),
		func(id: int) -> Dictionary: return BR._json(root, "Mob.wz/%07d.img" % id), missing)
	setup.seed = seed_value
	var w := RunWorld.new(setup)
	var policy := POLICY.new(VariedLink.new(), seed_value)
	policy.configure(params)
	var fp := FINGERPRINT.new()
	policy.observers.append(fp.observe)
	var record := BR.run_one(w, policy, seed_value, -1.0, 60.0, 0, policy.observe)
	return {"fingerprint": FINGERPRINT.of_round(policy, w, record, fp), "decisions": policy.decisions.size()}


func test_runscene_with_the_playtest_policy_plays_the_headless_round_exactly() -> void:
	if not require_cache():
		return
	var params := {"tactics": {"checkpoint_s": 4.0}, "motor": {"reaction_delay_ticks": 3, "mistake_rate": 0.05}}
	var cap := 90.0
	var expected := _headless_round("henesys_hg1", 2026, cap, params)
	var policy := POLICY.new(VariedLink.new(), 2026)
	policy.configure(params)
	var fp := FINGERPRINT.new()
	policy.observers.append(fp.observe)
	var cap_tick := WINDOWED.tick_cap(cap)
	scene = _make("henesys_hg1", 2026, {"autoplay": true, "autopick": true, "policy": policy, "stop_tick": cap_tick,
		"view_size": Vector2(800, 600)})
	assert_eq(scene.world.view_size, Vector2(800, 600), "the forced view is the driver's")
	var steps := [1.0, 4.0, 7.0, 0.5]
	var frame := 0
	while roundi(scene.world.time / DT) < cap_tick and scene.world.state != RunWorld.DEAD and frame < 100000:
		scene.advance_frame(DT * float(steps[frame % steps.size()]))
		frame += 1
	policy.choose(scene.world)
	var got := FINGERPRINT.of_round(policy, scene.world, WINDOWED.round_record(scene.world), fp)
	assert_true(int(expected.decisions) > 15, "tactics and cards were decided (%d)" % int(expected.decisions))
	assert_eq(JSON.stringify(got), JSON.stringify(expected.fingerprint), "RunScene played the driver's round")
