extends Node
## Boss-kit evidence on the real Henesys map and cache (#461): Papulatus's clock casts Dispel on a buffed character and,
## once killed, becomes its flying form (`--phase=papulatus`: dispel_*.png, papulatus_fly_*.png); Lilynouch reflects
## (`--phase=lilynouch`: reflect_icon.png, reflect_hit.png). The boss is forced into the first map by a data patch; the
## sim is the shipped one. Needs a cache that holds Papulatus (8500001, 8500002) and Lilynouch (8220005), e.g. a private
## one imported with those mobs added to a local copy of the manifest.
## MAPLE_SURVIVORS_CACHE=<cache> ISOLATE=<name> bash scripts/run.sh res://scenes/debug/boss_kit_driver.tscn -- \
##   --phase=papulatus --shots=<abs evidence dir>

const KILL := {"damage_min": 1000000000, "damage_max": 1000000000, "magic": true, "crit": 0.0, "crit_mult": 1.5,
	"skill": "energy_bolt"}

var run: RunScene
var shots := ""
var summary := {}


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(args.get("shots", ""))
	var phase := String(args.get("phase", "papulatus"))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	# Uncapped, as the flow driver: an unfocused or occluded window is otherwise throttled to about one frame a second.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_patch(phase)
	run = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("henesys", 60, {"use_flow": false, "autopick": true})
	add_child(run)
	run.set_process(false)
	DataRepo.patch = {}
	if phase == "papulatus":
		await _papulatus()
	else:
		await _lilynouch()
	var file := FileAccess.open(shots.path_join("boss_kit_%s.json" % phase), FileAccess.WRITE)
	file.store_string(JSON.stringify(summary, "\t"))
	get_tree().quit()


## The shipped data with the first map's boss replaced, no ordinary spawns and a roomier HP pool.
func _patch(phase: String) -> void:
	var data := DataRepo.load_all()
	var maps: Array = data.stages.stages.henesys.maps.duplicate(true)
	var ids := [8500001, 8500002] if phase == "papulatus" else [8220005]
	maps[0].boss = {"time": 1, "mob_id": ids[0], "hp_mult": 1.0, "dmg_mult": 1.0, "attacks": [],
		"rewards": {"bonus_choices": 0}}
	if phase == "papulatus":
		maps[0].boss.final_form = 8500002
	var keyframes: Array = data.stages.stages.henesys.keyframes.duplicate(true)
	for keyframe: Dictionary in keyframes:
		keyframe.rate = 0.0
		keyframe.max_alive = 0.0
	DataRepo.patch = {"stages": {"stages": {"henesys": {"maps": maps, "keyframes": keyframes}}},
		"balance": {"player": {"hp": 5000}, "mob_skills": {"enabled_ids": ids}}}


func _papulatus() -> void:
	var w := run.world
	w.god = true
	await _until(func() -> bool: return int(w.bosses.records[0].slot) >= 0 and w.swarm.alpha[int(w.bosses.records[0].slot)] >= 1.0, 8.0)
	# A timed self-buff for the clock's Dispel (127/1: interval 1 s, box +-300 x 120) to end.
	w.start_buff("diag_buff", {"skill_id": 9991002, "level": 1, "icon": "", "duration": 100.0, "buff_stat": "pdd",
		"buff_value": 10.0, "pulse_interval": 0.0, "buff_effects": {"pdd": 10.0}})
	var dispelled := false
	for n in 600:
		await _frames(1.0 / 60.0)
		if not w.buffs.has("diag_buff"):
			dispelled = true
			await _frames(0.35)
			await _shot("dispel_notice.png")
			break
	summary["dispelled"] = dispelled
	summary["clock_fh"] = w.swarm.fh[int(w.bosses.records[0].slot)]
	await _shot("papulatus_clock.png")
	var shell := int(w.bosses.records[0].slot)
	w.hit_mob(shell, KILL, -1)
	run.handle_events(w.drain_events())
	var form := int(w.bosses.records[0].slot)
	summary["form_mob_id"] = int(w.bosses.records[0].mob_id)
	summary["form_fh"] = w.swarm.fh[form]
	var first := w.swarm.pos(form)
	await _frames(1.5)
	await _shot("papulatus_fly_1.png")
	await _frames(2.0)
	await _shot("papulatus_fly_2.png")
	summary["flew_px"] = w.swarm.pos(form).distance_to(first)
	summary["form_fh_after"] = w.swarm.fh[form]
	summary["touch_hits"] = run.world.bosses.records[0].get("form_time", -1.0)


func _lilynouch() -> void:
	var w := run.world
	await _until(func() -> bool: return int(w.bosses.records[0].slot) >= 0 and w.swarm.alpha[int(w.bosses.records[0].slot)] >= 1.0, 8.0)
	var slot := int(w.bosses.records[0].slot)
	w.swarm.hp[slot] = int(float(w.swarm.max_hp[slot]) * 0.4)
	# tier C diagnostic: Lilynouch's 145 is on a 60 s interval; make its first cast due now instead of waiting for it.
	w.mob_skills._ready["0/145/1"] = w.time
	await _until(func() -> bool: return not w.mob_skills.reflect_state(slot, w.time).is_empty(), 5.0)
	await _frames(0.4)
	await _shot("reflect_icon.png")
	await _frames(0.7) # the character's own bolts are reflected too; let the 0.5 s limit run out first
	summary["diag"] = {"god": w.god, "invincible_t": w.upkeep.invincible_t, "guarded": w._hit_guarded(),
		"time": w.time, "hp": w.player_state.hp}
	var before := int(w.player_state.hp)
	var boss_hp: int = w.swarm.hp[slot]
	w.hit_mob(slot, {"damage_min": 800, "damage_max": 800, "magic": false, "crit": 0.0, "crit_mult": 1.5,
		"skill": "three_snails"}, -1)
	var events := w.drain_events()
	summary["reflects"] = events.filter(func(e: Dictionary) -> bool: return e.type == "boss_reflect").map(
		func(e: Dictionary) -> Array: return [e.damage, e.amount])
	summary["player_hits"] = events.filter(func(e: Dictionary) -> bool: return e.type == "player_hit").map(
		func(e: Dictionary) -> Array: return [e.damage, e.source_kind])
	run.handle_events(events)
	await _frames(0.3)
	await _shot("reflect_hit.png")
	summary["boss_hp_unchanged"] = w.swarm.hp[slot] == boss_hp
	summary["player_hp_lost"] = before - int(w.player_state.hp)


func _until(done: Callable, seconds: float) -> void:
	for n in roundi(seconds * 60.0):
		if done.call():
			return
		await _frames(1.0 / 60.0)


func _frames(seconds: float) -> void:
	for i in maxi(1, roundi(seconds * 60.0)):
		run.advance_frame(1.0 / 60.0)
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
