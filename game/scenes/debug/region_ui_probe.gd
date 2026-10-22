extends Node
## Evidence for #247: the real map-select cards and results after a diagnostic boss kill, transfer and map-2 death.
## Use scripts/run.sh res://scenes/debug/region_ui_probe.tscn -- --shots=<absolute evidence directory> with ISOLATE
## and MAPLE_SURVIVORS_CACHE. Only the evidence directory's probe_save.json is written. This is UI QA, not balance.

var _shots := ""
var _flow: SceneFlow


func _ready() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	_shots = String(args.get("shots", ""))
	if _shots.is_empty():
		_fail("--shots=<absolute evidence directory> is required")
		return
	DirAccess.make_dir_recursive_absolute(_shots)
	_flow = get_node("/root/Flow") as SceneFlow
	_flow.save = SaveData.new(_shots.path_join("probe_save.json"))
	_flow.host = self
	_flow.deferred_swaps = false
	# Defer until this scene is in the tree so flow swaps can add screens safely.
	_capture.call_deferred()


func _capture() -> void:
	if _flow.create_character("Region247") < 0:
		_fail("use a fresh evidence directory: " + _flow.action_error)
		return
	await _shot("map_select_henesys")
	await _key(KEY_DOWN)
	await _shot("map_select_ellinia")
	var slot := _flow.save.slot(_flow.active_slot)
	slot.tier = 1
	if _flow.save.update_slot(_flow.active_slot, slot) != OK:
		_fail("could not stage tier-2 map select")
		return
	_flow.goto_stage_select()
	await _shot("map_select_sleepywood")
	_flow.start_run("henesys", 247, {"autopick": true})
	var run := _flow.current as RunScene
	if run == null or run.world == null:
		_fail("round did not start")
		return
	run.set_process(false)
	var world := run.world
	world.god = true
	# tier C: diagnostic time jump and lethal hit, solely to exercise the real boss settlement/transfer path quickly.
	world.time = 300.0
	world.step(RunScene.DT, MoveInput.new())
	var boss_slot := int(world.bosses.records[0].slot)
	if boss_slot < 0:
		_fail("map-1 boss did not arrive")
		return
	world.hit_mob(boss_slot, {"skill": "three_snails", "magic": true, "damage_min": 1e9,
		"damage_max": 1e9, "crit": 0.0, "crit_mult": 1.0}, -1)
	for tick in 900:
		run.advance_frame(RunScene.DT)
		if world.map_index == 1 and not world.transfer_pending:
			break
	if world.current_map_id() != 104010001:
		_fail("the settled boss kill did not reach map 2")
		return
	# Let any presentation fade finish before death; the run still uses fixed frame deltas.
	for tick in 180:
		run.advance_frame(RunScene.DT)
	world.god = false
	world.take_hit(1e9, true, "", world.player.pos, {"source_kind": "boss_attack"})
	run.handle_events(world.drain_events())
	if world.state != RunWorld.DEAD:
		_fail("diagnostic map-2 hit did not kill the character")
		return
	var summary := run.build_summary()
	if int(summary.map_id) != 104010001 or summary.map_name != "The Pig Beach":
		_fail("results summary does not identify map 2")
		return
	var report := FileAccess.open(_shots.path_join("summary.json"), FileAccess.WRITE)
	report.store_string(JSON.stringify(summary, "\t"))
	report.close()
	# Resume the actual tombstone/finish_run path into the real results screen.
	run.set_process(true)
	for frame in 1200:
		await get_tree().process_frame
		if _flow.current_name == "results":
			break
	if _flow.current_name != "results":
		_fail("map-2 death never reached results")
		return
	await _shot("results_map_2_death")
	print("region_ui_probe: passed; ending map %d, %s" % [summary.map_id, summary.map_name])
	get_tree().quit()


func _key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	await get_tree().process_frame
	event = InputEventKey.new()
	event.keycode = key
	Input.parse_input_event(event)
	await get_tree().process_frame


func _shot(name: String) -> void:
	await get_tree().create_timer(0.8).timeout
	await get_tree().process_frame
	RenderingServer.force_draw()
	var error := get_viewport().get_texture().get_image().save_png(_shots.path_join(name + ".png"))
	if error != OK:
		_fail("could not save " + name)
	print("region_ui_probe: " + name)


func _fail(message: String) -> void:
	push_error("region_ui_probe: " + message)
	get_tree().quit(1)
