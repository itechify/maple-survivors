extends Node
## Visual acceptance probe for every Dark Cave boss/attack on the real map and carried fixture.
## ISOLATE=t73 bash scripts/run.sh res://scenes/debug/dark_cave_boss_driver.tscn -- --shots=<abs evidence dir>
## Diagnostic only: normal waves are disabled, skills wait, damage is disabled and one selected encounter starts early.
## It uses real RunWorld attack events and RunScene presentation, never synthetic art or balance candidates.

const DT := 1.0 / 60.0 # tier C: normal simulation tick, matching RunScene.
const FIXTURE := "res://tests/fixtures/characters/lv35_magician_2nd.json"
var shots := ""
var records: Array = []


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	shots = String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	var entries: Array = DataRepo.stage_bosses(DataRepo.load_all().stages.stages.sleepywood)
	for entry: Dictionary in entries:
		if args.has("mob") and int(args.mob) != int(entry.mob_id):
			continue
		for attack: String in entry.attacks:
			if args.has("attack") and String(args.attack) != attack:
				continue
			await _encounter(entry, attack)
	var file := FileAccess.open(shots.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"diagnostic": true, "encounters": records}, "\t"))
	get_tree().quit()


func _encounter(shipped: Dictionary, attack: String) -> void:
	var run: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	run.configure("sleepywood", 73, {"use_flow": false, "character": ProjectSettings.globalize_path(FIXTURE)})
	add_child(run)
	run.set_process(false)
	if run.world == null:
		push_error(run.error)
		get_tree().quit(2)
		return
	var w := run.world
	w.god = true
	var quiet := {"duration": 900, "keyframes": [{"t": 0, "rate": 0, "max_alive": 0, "pool": {}}]}
	w.director = SpawnDirector.create(quiet, w.kind_of_id)
	var entry := shipped.duplicate(true)
	entry.time = 0.5 # tier C: shortened diagnostic arrival only; shipped schedule is unchanged.
	entry.attacks = [attack]
	w.bosses = BossDirector.new([entry], w.balance.bosses)
	# Keep fixture ranks and HUD, while allowing each boss to finish its canonical stance before being attacked.
	for skill: String in w.loadout.order:
		w.runner.cooldowns[skill] = 60.0 # tier C: diagnostic suppression for this at-most-eight-second probe.
	var start := -1.0
	var impact := -1.0
	var windup_saved := false
	var impact_saved := false
	var positioned := false
	var ball := int(entry.mob_id) == 8130100 and attack == "attack2"
	var ball_contact := -1.0
	var flight_saved := false
	var phases: Array = []
	# tier C: eight-second ceiling; windup halfway (max 850 ms), impact +120 ms, ball flight +200 ms after launch.
	for tick in 480:
		await get_tree().create_timer(DT).timeout
		if not positioned and float(w.bosses.records[0].spawn_time) >= 0.0:
			var slot := int(w.bosses.records[0].slot)
			var offset := 200.0 if ball else 100.0 # tier C: diagnostic separation to make the ball visible in flight.
			# Snack Bar's long attack3 needs space in front; its short attack2 needs a nearby character.
			if int(entry.mob_id) == 8220009 and attack == "attack3":
				offset = 300.0 # tier C: diagnostic separation for the long beam's windup/impact view.
			var x := w.player.pos.x + offset
			var fh := w.fhm.find_below(x, w.player.pos.y - 5.0)
			if fh >= 0:
				w.relocate_mob(slot, Vector2(x, w.fhm.y_at(fh, x)), fh)
			positioned = true
		w.step(DT, MoveInput.new())
		var events := w.drain_events()
		for event: Dictionary in events:
			if event.type == "mob_projectile_hit":
				ball_contact = w.time
				phases.append({"phase": "ball_contact", "time": w.time})
			if event.type == "boss_attack":
				phases.append({"phase": event.phase, "time": w.time})
				if event.phase == "start":
					start = w.time
					impact = float(event.impact_time)
		run.handle_events(events)
		run._present(DT)
		if start >= 0.0 and not windup_saved and w.time >= start + minf(0.85, (impact - start) * 0.5):
			await _shot("%d_%s_windup.png" % [int(entry.mob_id), attack])
			windup_saved = true
		if ball and impact >= 0.0 and not flight_saved and w.time >= impact + 0.2:
			await _shot("%d_%s_flight.png" % [int(entry.mob_id), attack])
			flight_saved = true
		var contact := ball_contact if ball else impact
		if contact >= 0.0 and not impact_saved and w.time >= contact + 0.12:
			await _shot("%d_%s_impact.png" % [int(entry.mob_id), attack])
			impact_saved = true
		if impact_saved and w.time >= contact + 0.8:
			break
	var summary := run.perf_summary()
	records.append({"mob_id": entry.mob_id, "attack": attack, "phases": phases,
		"windup_saved": windup_saved, "impact_saved": impact_saved,
		"missing": summary.get("missing", []), "warnings": Array(w.warnings)})
	print("BOSS_PROBE ", JSON.stringify(records[-1]))
	run.queue_free()
	await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots.path_join(name))
