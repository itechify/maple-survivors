extends Node
## Dark Sight evidence (#211): a real Thief takes its learn card and auto-casts among real Henesys mobs at 20% HP.
## Fixed ticks capture before, Hidden standing/walking, and recovered; summary.json records state and missing art.
## Tool only, no save writes. ISOLATE=s167-t211 MAPLE_SURVIVORS_CACHE=<cache> bash scripts/run.sh \
## res://scenes/debug/dark_sight_driver.tscn -- --shots=<absolute evidence dir> [--path=claw|dagger]

const RF := preload("res://tests/fixtures/run_fixtures.gd")

var run: RunScene
var shots := ""


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 211, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	w.progression.level = 10
	RF.as_job(w, 400, String(args.get("path", "dagger")))
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	w.upgrades.apply("dark_sight_new", w)
	w.heal_fraction("hp", 1.0)
	w.heal_fraction("hp", -1.0)
	w.heal_fraction("hp", 0.2)
	for dx: float in [-110.0, -55.0, 55.0, 110.0, 180.0]:
		var x := w.player.pos.x + dx
		var f := w.fhm.find_below(x, w.player.pos.y - 10.0)
		var slot := w.spawn_mob(0, Vector2(x, w.fhm.y_at(f, x)), f, 1.0, false)
		w.swarm.alpha[slot] = 1.0
	# Synchronize the equipped look without playing the diagnostic job grant's large advancement effect over the avatar.
	run.handle_events(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "equipment_changed"))
	# Draw the initial state without a simulation tick, so the before shot precedes the automatic escape cast.
	run.advance_frame(0.0)
	await _shot("before.png")
	await _frames(150)
	await _shot("hidden_stand.png")
	var summary := {"hidden": _state()}
	Input.action_press("move_right")
	await _frames(25)
	Input.action_release("move_right")
	await _shot("hidden_walk.png")
	summary["walking"] = _state()
	w.heal_fraction("hp", 1.0)
	await _frames(1)
	await _shot("recovered.png")
	summary["recovered"] = _state()
	summary["missing"] = run.library.missing
	summary["avatar_missing"] = run.avatar.missing
	summary["warnings"] = w.warnings
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit(0 if bool(summary.hidden.hidden) and not bool(summary.recovered.hidden) \
		and run.library.missing.is_empty() and run.avatar.missing.is_empty() and w.warnings.is_empty() else 1)


func _state() -> Dictionary:
	var w := run.world
	return {"hidden": w.is_hidden(), "hp": w.player_state.hp, "max_hp": w.player_state.max_hp,
		"speed": w.player_speed_stat(), "alpha": run.player_group.self_modulate.a,
		"cooldown": w.skill_readiness("dark_sight"), "mobs": w.swarm.alive_count()}


func _frames(n: int) -> void:
	for i in n:
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
