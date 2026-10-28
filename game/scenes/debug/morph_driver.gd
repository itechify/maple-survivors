extends Node
## Oak Barrel evidence on the real Henesys map and cache (#194): a character at 20% HP with Oak Barrel learned and mobs
## around it. The barrel auto-casts (a failed cast is retried), the morph is shot standing and walking among the mobs, then
## HP is topped up so the barrel ends early and the avatar is shot again. Saves barrel_before.png, barrel_stand.png,
## barrel_walk.png and avatar_back.png, and summary.json (hidden/morph/HP at each step, HP losses while Hidden).
## Needs a cache whose manifest has Morph.wz/1002.img. Tool only; the rank is forced and the character is not a Brawler.
## MAPLE_SURVIVORS_CACHE=<cache> ISOLATE=<name> bash scripts/run.sh \
##   res://scenes/debug/morph_driver.tscn -- --shots=<abs evidence dir> [--seed=60] [--rank=10] [--job=510]
## `--job=510` makes the character a real Brawler first (Pirate at Lv 10 on the knuckle path, Lv 30, advanced to 510 with
## its Prime Hands) and takes Oak Barrel through its learn card instead of forcing the skill.

const RF := preload("res://tests/fixtures/run_fixtures.gd")

var run: RunScene
var shots := ""
var hits_taken := 0
var _last_hp := 0


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
	run.configure("henesys", int(args.get("seed", 60)), {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	var w := run.world
	if int(args.get("job", 0)) == 510:
		w.progression.level = 10
		RF.as_job(w, 500, "knuckle")
		w.progression.level = 30
		RF.as_job(w, 510)
		w.pending_cards = []
		w.state = RunWorld.PLAYING
		w.upgrades.apply("oak_barrel_new", w)
		run.handle_events(w.drain_events())
	else:
		w.learn_skill("oak_barrel")
	w.loadout.set_rank("oak_barrel", int(args.get("rank", 10)))
	# A level-1 Beginner has 50 HP; give it a Brawler-sized pool so the cast is survivable.
	w.loadout.add_player_mod("max_hp", "add", 950.0)
	w.refresh_player_stats()
	w.heal_fraction("hp", -1.0)
	w.heal_fraction("hp", 0.2)
	var spots := [-160.0, -90.0, 70.0, 130.0, 210.0]
	for n in spots.size():
		var x: float = w.player.pos.x + float(spots[n])
		var f := w.fhm.find_below(x, w.player.pos.y - 10.0)
		var slot := w.spawn_mob(n % w.mob_kinds.size(), Vector2(x, w.fhm.y_at(f, x)), f, 1.0, false)
		w.swarm.alpha[slot] = 1.0
	await _frames(0.0)
	await _shot("barrel_before.png")
	var summary := {"steps": []}
	# Let the barrel cast; a failed roll leaves the skill on cooldown, so clear it and try again.
	var guard := 0
	while not w.is_hidden() and guard < 40:
		w.runner.cooldowns["oak_barrel"] = 0.0
		await _frames(0.1)
		guard += 1
	summary.steps.append(_state("cast"))
	await _frames(0.5)
	await _shot("barrel_stand.png")
	summary.steps.append(_state("standing"))
	Input.action_press("move_right")
	await _frames(0.6)
	Input.action_release("move_right")
	await _shot("barrel_walk.png")
	summary.steps.append(_state("walking"))
	await _frames(1.0)
	summary.steps.append(_state("1 s later"))
	w.heal_fraction("hp", 1.0)
	await _frames(0.4)
	await _shot("avatar_back.png")
	summary.steps.append(_state("after HP restored"))
	summary["hp_losses_while_hidden"] = hits_taken
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


func _state(label: String) -> Dictionary:
	var w := run.world
	return {"label": label, "hidden": w.is_hidden(), "morph": int(w.player_state.morph), "hp": int(w.player_state.hp),
		"max_hp": int(w.player_state.max_hp), "mobs": w.swarm.alive_count(), "x": w.player.pos.x,
		"avatar_morph": run.avatar.morph_id, "avatar_stance": run.avatar.stance}


func _frames(seconds: float) -> void:
	for i in maxi(1, roundi(seconds * 60.0)):
		run.advance_frame(1.0 / 60.0)
		var hp := int(run.world.player_state.hp)
		if run.world.is_hidden() and hp < _last_hp:
			hits_taken += 1
		_last_hp = hp
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
