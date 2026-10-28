extends Node
## Round-loop visual probe (#286). Uses an evidence-only save: the real creation screens (name, look, Job page), the new
## character's Free Market, map select with tier 2 locked and then unlocked (the Sleepywood card selected), character select
## and the round history. Run: ISOLATE=286 bash scripts/run.sh res://scenes/debug/round_loop_driver.tscn
## -- --shots=<absolute evidence path>. Needs the asset cache; no proprietary screenshot belongs in git.

var flow: SceneFlow
var shots := ""
var _n := 0


func _ready() -> void:
	var flags := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(flags.get("shots", ""))
	if shots.is_empty():
		push_error("round_loop_driver requires --shots=<absolute evidence path>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var save_path := shots.path_join("driver_save.json")
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(save_path + suffix):
			DirAccess.remove_absolute(save_path + suffix)
	flow = SceneFlow.new()
	flow.save = SaveData.new(save_path)
	flow.host = Node.new()
	add_child(flow.host)
	add_child(flow)
	flow.goto_character_select()
	await _shot("character_select_empty")
	flow.current.show_creation()
	await _shot("creation_name")
	var creation: Control = flow.current.creation
	creation.name_edit.text = "ArchMage1"
	creation.create_button.pressed.emit()
	await _shot("creation_look")
	creation.create_button.pressed.emit()
	await _shot("creation_job")
	creation.create_button.pressed.emit()
	await _sleep(1.0)
	await _shot("free_market_home")
	flow.goto_stage_select()
	await _sleep(1.5)
	flow.current.select(4)
	await _sleep(0.6)
	await _shot("map_select_tier2_locked")
	var slot := flow.save.slot(0)
	slot.character.tiers_unlocked = 2
	flow.save.update_slot(0, slot)
	flow.goto_stage_select()
	await _sleep(1.5)
	flow.current.select(4)
	await _sleep(0.6)
	await _shot("map_select_tier2_unlocked")
	var summary := {"stage": "henesys", "cleared": false, "level": 14, "job_id": 212, "job_name": "Arch Mage (Fire, Poison)",
		"time": 431.0, "duration": 900.0, "kills": 612, "damage_dealt": 90210, "skills": [], "nx_awarded": 160, "seed": 1,
		"map_id": 104040000}
	flow.finish_run(summary, slot.character)
	await _sleep(3.5)
	await _shot("results_after_death")
	flow.goto_character_select()
	await _sleep(0.5)
	await _shot("character_select_after_round")
	flow.goto_history()
	await _sleep(1.0)
	await _shot("history")
	get_tree().quit()


func _sleep(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _shot(step: String) -> void:
	await _sleep(0.4)
	await get_tree().process_frame
	RenderingServer.force_draw()
	_n += 1
	var path := shots.path_join("%02d_%s.png" % [_n, step])
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path) if img != null else ERR_CANT_CREATE
	print("round_loop_driver: shot %s err=%d screen=%s" % [path.get_file(), err, flow.current_name])
