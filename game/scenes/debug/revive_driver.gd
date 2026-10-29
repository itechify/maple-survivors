extends Node
## Resurrection evidence on the real Henesys map and cache (spec #372 BS8, docs/GAME_DESIGN.md 7.81): a Bishop with
## Resurrection at rank 8 takes (1) a lethal revivable hit (pillar, beams, notice, HP back, monsters shoved, guard blink,
## HUD recharge), (2) a second lethal hit inside the recharge (dies), and, in a second round, (3) a lethal hit after the
## recharge has run out (revives again). Tool-only; no saves, no balance data.
## ISOLATE=<name> bash scripts/run.sh res://scenes/debug/revive_driver.tscn -- --shots=<abs evidence dir>
## Writes revive_*.png and summary.json (the three outcomes, the HP, the shoved monsters, `missing`). Exits 1 when an
## outcome is not the expected one.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const KEY := "resurrection"
const DT := 1.0 / 60.0
## Monsters put around the character before the first hit (x offsets in px, both sides).
const MOB_OFFSETS := [-130.0, -80.0, -40.0, 40.0, 80.0, 130.0]

var run: RunScene
var shots := ""
var summary := {}
var failures: Array[String] = []


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(args.get("shots", ""))
	if shots == "":
		push_error("revive_driver: --shots=<abs dir> is required")
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	await _round_one()
	await _round_two()
	summary["failures"] = failures
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit(1 if not failures.is_empty() else 0)


## Starts a round with a Bishop (the Wooden Wand) holding Resurrection at rank 8 and monsters crowded around it.
func _start(p_seed: int) -> RunWorld:
	if run != null:
		run.queue_free()
		await get_tree().process_frame
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", p_seed, {"use_flow": false})
	add_child(run)
	run.set_process(false)
	run.fx.set_process(false)
	run.fx_back.set_process(false)
	var w := run.world
	RF.as_job(w, 200)
	RF.as_job(w, 232)
	w.learn_skill(KEY)
	w.loadout.set_rank(KEY, 8)
	run.handle_events(w.drain_events())
	await _frames(30)
	for offset: float in MOB_OFFSETS:
		RF.put_mob(w, 100100, w.player.pos.x + offset, w.player.pos.y - 5.0, 50.0)
	await _frames(3) # a tick files the new monsters into the spatial hash, which the shove's box query reads
	return w


## Advances the scene `n` frames: one simulation tick and one fixed step of the effect renderers (their own clock is
## switched off in _start, so a throttled window cannot run the pillar, the beams and the guard out of step).
func _frames(n: int) -> void:
	for i in n:
		run.advance_frame(DT)
		run.fx.advance(DT)
		run.fx_back.advance(DT)
		await get_tree().process_frame


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(file_name))


## A lethal hit from a monster touching the character; returns the damage dealt.
func _lethal(w: RunWorld) -> int:
	return w.take_hit(1.0e9, false, "", w.player.pos + Vector2(12.0, 0.0), {"accuracy": 0.0, "mob": -1, "source_kind": "touch"})


func _expect(ok: bool, what: String) -> void:
	if not ok:
		failures.append(what)
		push_error("revive_driver: %s" % what)


func _mob_xs(w: RunWorld) -> Array:
	var xs := []
	for m in w.swarm.kind.size():
		if w.swarm.state[m] != MobSwarm.FREE and w.swarm.state[m] != MobSwarm.DIE:
			xs.append(snappedf(w.swarm.x[m] - w.player.pos.x, 0.1))
	return xs


## Outcomes 1 and 2: the first lethal hit revives, the second inside the recharge kills.
func _round_one() -> void:
	var w := await _start(380)
	var before := _mob_xs(w)
	await _shot("revive_0_before.png")
	_lethal(w)
	var events := w.drain_events()
	run.handle_events(events)
	var pushed := 0
	for e: Dictionary in events:
		if e.type == "player_revived":
			pushed = int(e.pushed)
	_expect(pushed > 0, "the revive shoved monsters")
	_expect(not w.revives.is_empty() and w.state != RunWorld.DEAD, "the first lethal hit revived")
	summary["revive_1"] = {"revives": w.revives.duplicate(true), "hp": int(w.player_state.hp), "max_hp": int(w.player_state.max_hp),
		"pushed": pushed, "mob_offsets_before": before, "guard": w.hit_guard_left(),
		"recharge_left": w.runner.cooldowns.get(KEY, 0.0), "notices": run.hud.messages().map(func(m: Dictionary) -> String: return m.text)}
	await _frames(30)
	summary["revive_1"]["mob_offsets_after_0_5s"] = _mob_xs(w)
	await _shot("revive_1_pillar.png") # 0.5 s: the pillar rises, the beams still in their lead-in
	await _frames(60)
	await _shot("revive_2_beams.png") # 1.5 s: the first beam frames
	# The guard blink: the first drawn frame at which the avatar is dimmed.
	var blinked := false
	for i in 24:
		await _frames(1)
		if run.player_group.self_modulate.a < 1.0 and w.revive.guarding():
			await _shot("revive_3_guard_blink.png")
			blinked = true
			break
	_expect(blinked, "the avatar dimmed while the guard ran")
	await _frames(60)
	_expect(not w.revive.guarding(), "the guard ended")
	await _shot("revive_4_hud_recharge.png") # guard over: the slot's recharge sweep and the notice (6 s)
	w.upkeep.invincible_t = 0.0 # a touching monster's last hit must not hide the lethal one behind the hit window
	_lethal(w)
	run.handle_events(w.drain_events())
	_expect(bool(w.player_state.dead) and w.revives.size() == 1, "the second lethal hit inside the recharge killed")
	summary["revive_2"] = {"dead": bool(w.player_state.dead), "revives": w.revives.size()}
	await _frames(20)
	await _shot("revive_5_second_hit_dies.png")


## Outcome 3: a lethal hit after the recharge has run out revives again.
func _round_two() -> void:
	var w := await _start(381)
	_lethal(w)
	run.handle_events(w.drain_events())
	_expect(w.revives.size() == 1, "round two: the first hit revived")
	var recharge := float(w.runner.cooldowns.get(KEY, 0.0))
	print("revive_driver: round two fast-forwards %.0f s of recharge" % recharge)
	# Fast-forward the recharge without drawing (the character cannot be hurt meanwhile; level-ups take their first card).
	w.god = true
	var ticks := int(ceil(recharge / DT)) + 5
	for i in ticks:
		if w.state == RunWorld.CHOOSING_UPGRADE: # a level-up from the kills: take the first card and go on
			w.apply_choice(String(w.pending_cards[0].id))
		w.step(DT, MoveInput.new())
	w.drain_events()
	print("revive_driver: recharge elapsed at sim time %.1f s" % w.time)
	w.god = false
	_expect(float(w.runner.cooldowns.get(KEY, 1.0)) <= 1e-6, "the recharge ran out")
	await _frames(5)
	_lethal(w)
	run.handle_events(w.drain_events())
	summary["revive_3"] = {"revives": w.revives.size(), "dead": bool(w.player_state.dead), "hp": int(w.player_state.hp),
		"recharge_seconds": recharge, "missing": AssetLibrary.get_default().missing}
	_expect(w.revives.size() == 2 and not bool(w.player_state.dead), "the lethal hit after the recharge revived again")
	await _frames(60)
	await _shot("revive_6_revived_again.png")
