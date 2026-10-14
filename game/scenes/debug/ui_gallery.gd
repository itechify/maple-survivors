extends Node2D
## Debug gallery of the MapleStory UI: shows one window (over a live map with the HUD) or one menu screen with sample
## data, for visual checks and evidence screenshots.
##
##   bash scripts/godot.sh --path game res://scenes/debug/ui_gallery.tscn -- --window=levelup --shot=C:/abs/x.png
##
## --window=<name>:
##   levelup         level-up choice (3 cards)          levelup_missing  cards with "" / missing icons, long texts
##   levelup_rank    Stronger Snails (Three Snails level 2 -> 3), Magic Claw (new), Nimble Feet (--focus=2: the notice
##                   without its "raised your ___ skill" sentence)
##   job             job advancement at Lv. 8 (Magician available, the others locked)
##   job10           at Lv. 10 (the others "Not in this build")       job_none  Lv. 30 Magician, nothing available
##   job_confirm     the confirmation line after picking Magician      pause     pause menu
##   title | stage_select | results | results_dead | import            the menu screens (sample data)
##   flow            the real scene flow end to end (Flow autoload, this node as its host): title -> stage select ->
##                   run (autoplay, windows answered after 1 s) -> results (from the run's own summary) -> retry; a
##                   screenshot of each step into --shots=<dir>; saves to user://_test_cache/gallery_save.json
##   import --wz=<folder> --autostart   runs the importer from the import screen; the shot is taken when it ends
##                   (point MAPLE_SURVIVORS_CACHE at a scratch folder to leave the real cache alone)
##   backdrop        the login map alone: --cam=x,y (camera centre), --frame=0 hides the book frame,
##                   --hide=a,b hides map sprites whose path contains a or b
## --shot=<png>    save the logical viewport after --frames=N (default 40) or --at=<seconds>, and quit
## --focus=<i>     focus entry i (windows)             --map=<id>   map behind the windows (104040000)
## --quit=<n>      quit after n frames          --size=WxH   window size (e.g. 1920x1080: a 1066x600 view)

const SAMPLE_CARDS := [
	{"id": "energy_bolt_new", "kind": "skill_new", "skill": "energy_bolt", "name": "Energy Bolt",
		"desc": "Learn Energy Bolt: a magic bolt at the nearest monster.",
		"icon": "Skill.wz/200.img/skill/2001004/icon", "rank": 1, "max_rank": 1, "skill_name": "Energy Bolt",
		"skill_level": 0, "skill_level_next": 1},
	{"id": "three_snails_count", "kind": "skill_mod", "skill": "three_snails", "name": "Additional Shell",
		"desc": "Three Snails throws +1 shell.", "icon": "Skill.wz/000.img/skill/0001000/icon", "rank": 2,
		"max_rank": 4, "skill_name": "Three Snails", "skill_level": 1, "skill_level_next": 0},
	{"id": "magnet", "kind": "stat", "skill": "", "name": "Magnet", "desc": "Pick-up radius +25%.",
		"icon": "Character.wz/PetEquip/01812000.img/info/icon", "rank": 1, "max_rank": 4},
]
const MISSING_CARDS := [
	{"id": "improved_max_mp", "kind": "passive", "skill": "", "name": "Improved MaxMP Increase",
		"desc": "Max MP +25.", "icon": "Skill.wz/200.img/skill/2000001/icon", "rank": 5, "max_rank": 5},
	{"id": "no_icon", "kind": "stat", "skill": "", "name": "Card Without Icon",
		"desc": "This card has an empty icon path, so the neutral icon base is drawn instead of a skill icon.",
		"icon": "", "rank": 3, "max_rank": 5},
	{"id": "elixir", "kind": "filler", "skill": "", "name": "Elixir", "desc": "Recover 50% of max HP and MP.",
		"icon": "Item.wz/Consume/0200.img/02000004/info/icon", "rank": 1, "max_rank": 0},
]
const RANK_CARDS := [
	{"id": "three_snails_rank", "kind": "skill_rank", "skill": "three_snails", "name": "Stronger Snails",
		"desc": "Three Snails +1 skill level: a heavier shell.", "icon": "Skill.wz/000.img/skill/0001000/icon",
		"rank": 2, "max_rank": 2, "skill_name": "Three Snails", "skill_level": 2, "skill_level_next": 3},
	{"id": "magic_claw_new", "kind": "skill_new", "skill": "magic_claw", "name": "Magic Claw",
		"desc": "Learn Magic Claw: rakes the nearest monster twice.", "icon": "Skill.wz/200.img/skill/2001005/icon",
		"rank": 1, "max_rank": 1, "skill_name": "Magic Claw", "skill_level": 0, "skill_level_next": 1},
	{"id": "nimble_feet", "kind": "passive", "skill": "", "name": "Nimble Feet", "desc": "Speed +6.",
		"icon": "Skill.wz/000.img/skill/0001002/icon", "rank": 1, "max_rank": 5, "skill_name": "", "skill_level": 0,
		"skill_level_next": 0},
]
const JOB8 := [
	{"job_id": 200, "name": "Magician", "available": true, "reason": ""},
	{"job_id": 100, "name": "Warrior", "available": false, "reason": "Lv. 10"},
	{"job_id": 300, "name": "Bowman", "available": false, "reason": "Lv. 10"},
	{"job_id": 400, "name": "Thief", "available": false, "reason": "Lv. 10"},
	{"job_id": 500, "name": "Pirate", "available": false, "reason": "Lv. 10"},
]
const JOB10 := [
	{"job_id": 200, "name": "Magician", "available": true, "reason": ""},
	{"job_id": 100, "name": "Warrior", "available": false, "reason": "Not in this build"},
	{"job_id": 300, "name": "Bowman", "available": false, "reason": "Not in this build"},
	{"job_id": 400, "name": "Thief", "available": false, "reason": "Not in this build"},
	{"job_id": 500, "name": "Pirate", "available": false, "reason": "Not in this build"},
]
const JOB30 := [
	{"job_id": 210, "name": "Wizard (Fire, Poison)", "available": false, "reason": "Phase 2"},
	{"job_id": 220, "name": "Wizard (Ice, Lightning)", "available": false, "reason": "Not yet available"},
	{"job_id": 230, "name": "Cleric", "available": false, "reason": "Not yet available"},
]
const SCREENS := {
	"title": "res://scenes/ui/title_screen.tscn",
	"stage_select": "res://scenes/ui/stage_select.tscn",
	"results": "res://scenes/ui/results_screen.tscn",
	"results_dead": "res://scenes/ui/results_screen.tscn",
	"import": "res://scenes/ui/import_screen.tscn",
}

var args: Dictionary = {}
var window: MapleWindow
var _frame := 0
var _time := 0.0
var _shot_taken := false
var _import_screen: Node


func _ready() -> void:
	args = SceneFlow.parse_flags(OS.get_cmdline_user_args())
	if args.has("size"):
		var wh := str(args.size).split("x")
		if wh.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(wh[0]), int(wh[1])))
	var which := str(args.get("window", "levelup"))
	if which == "flow":
		_run_flow()
	elif which == "backdrop":
		var b := LoginBackdrop.new(_vec(str(args.get("cam", "0,0"))))
		b.show_frame = str(args.get("frame", "1")) != "0"
		add_child(b)
		if args.has("hide"):
			for part in str(args.hide).split(","):
				b.hide_objs(part)
	elif SCREENS.has(which):
		_show_screen(which)
	else:
		_show_window(which)
	print("ui_gallery: %s" % which)


func _process(delta: float) -> void:
	_frame += 1
	_time += delta
	var due := _time >= float(args.at) if args.has("at") else _frame >= int(args.get("frames", "40"))
	if args.has("autostart") and _import_screen != null:
		# Import runs: shoot when the importer has finished (before the screen moves on to the title).
		due = is_instance_valid(_import_screen) and String(_import_screen.state) in ["done", "failed"]
	if args.has("shot") and due and not _shot_taken:
		_shot_taken = true
		_take_shot()
	elif args.has("quit") and _frame >= int(args.quit):
		get_tree().quit()


func _show_screen(which: String) -> void:
	var scene: Node = (load(SCREENS[which]) as PackedScene).instantiate()
	match which:
		"results", "results_dead":
			var dead := which == "results_dead"
			var summary := {"stage": "henesys_hg1", "map_id": 104040000, "map_name": "Henesys Hunting Ground I",
				"street_name": "Victoria Road", "time": 512.4 if dead else 900.0, "duration": 900.0,
				"cleared": not dead, "level": 17 if dead else 31, "job_id": 200, "job_name": "Magician",
				"kills": 1342 if dead else 3120, "damage_dealt": 48210 if dead else 151377, "seed": 12345,
				"skills": [
					{"key": "three_snails", "name": "Three Snails", "icon": "Skill.wz/000.img/skill/0001000/icon",
						"rank": 3},
					{"key": "energy_bolt", "name": "Energy Bolt", "icon": "Skill.wz/200.img/skill/2001004/icon",
						"rank": 4},
					{"key": "magic_claw", "name": "Magic Claw", "icon": "Skill.wz/200.img/skill/2001005/icon",
						"rank": 2},
					{"key": "magic_guard", "name": "Magic Guard", "icon": "Skill.wz/200.img/skill/2001002/icon",
						"rank": 1},
				]}
			scene.configure(summary, not dead, {"time": 900.0, "cleared": true, "level": 33, "kills": 3300})
	add_child(scene)
	if which == "stage_select" and args.has("focus"):
		scene.call("select", int(args.focus))
	if which == "import":
		_import_screen = scene
		if args.has("wz"):
			scene.path_edit.text = str(args.wz)
			scene._validate_now()
		if args.has("autostart"):
			scene.start_import()


func _show_window(which: String) -> void:
	var map := MapRenderer.new()
	add_child(map)
	var map_id := int(args.get("map", "104040000"))
	map.load_map(map_id)
	var cam := Camera2D.new()
	add_child(cam)
	cam.make_current()
	var c := _spawn_point(map)
	cam.position = c + Vector2(0, -120)
	map.camera = cam
	var avatar := AvatarRenderer.new()
	map.actor_layer(_floor_layer(map, c)).add_child(avatar)
	avatar.position = c
	avatar.set_look({})
	var hud := Hud.new()
	add_child(hud)
	hud.update({"hp": 37, "max_hp": 50, "mp": 12, "max_mp": 25, "exp": 0, "level": 8, "job_id": 0},
		{"time": 183.0, "kills": 87, "name": "MapleHero", "job_name": "Beginner", "exp_next": 79,
			"skills": [{"icon": "Skill.wz/000.img/skill/0001000/icon", "rank": 2}]})
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	match which:
		"levelup", "levelup_missing", "levelup_rank":
			var w := LevelUpWindow.new()
			layer.add_child(w)
			var cards: Array = SAMPLE_CARDS
			if which == "levelup_missing":
				cards = MISSING_CARDS
			elif which == "levelup_rank":
				cards = RANK_CARDS
			w.open(cards, 8)
			w.card_chosen.connect(func(id: String) -> void: print("ui_gallery: card_chosen ", id))
			window = w
			if args.has("focus"):
				w.set_focus(int(args.focus))
		"job", "job10", "job_none", "job_confirm":
			var w := JobAdvanceWindow.new()
			layer.add_child(w)
			match which:
				"job10":
					w.open(JOB10, 10, 0)
				"job_none":
					w.open(JOB30, 30, 200)
				_:
					w.open(JOB8, 8, 0)
			w.job_chosen.connect(func(id: int) -> void: print("ui_gallery: job_chosen ", id))
			w.declined.connect(func() -> void: print("ui_gallery: declined"))
			if which == "job_confirm":
				w.confirm_seconds = 999.0
				w.select(0)
			window = w
		"pause":
			var w := PauseMenu.new()
			layer.add_child(w)
			w.open()
			w.resumed.connect(func() -> void: print("ui_gallery: resumed"))
			w.quit_requested.connect(func() -> void: print("ui_gallery: quit_requested"))
			if args.has("focus"):
				w.focus = int(args.focus)
			window = w
		_:
			push_error("ui_gallery: unknown --window=%s" % which)


func _spawn_point(map: MapRenderer) -> Vector2:
	var portal: Variant = map.map_root.get("portal", {})
	var p := map.bounds.get_center()
	if portal is Dictionary:
		for k in SpriteAnim.frame_keys(portal):
			var d: Dictionary = portal[k]
			if str(d.get("pn", "")) == "sp":
				p = Vector2(float(d.x), float(d.y))
				break
	var fhm := map.footholds
	if fhm != null:
		var f := fhm.find_below(p.x, p.y - 5.0)
		if f >= 0:
			p.y = roundf(fhm.y_at(f, p.x))
	return p


func _floor_layer(map: MapRenderer, p: Vector2) -> int:
	var fhm := map.footholds
	if fhm == null:
		return 0
	var f := fhm.find_below(p.x, p.y - 2.0)
	return fhm.layer[f] if f >= 0 else 0


## Drives the Flow through every screen with timed steps, saving a screenshot of each.
func _run_flow() -> void:
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow == null:
		push_error("ui_gallery: no Flow autoload")
		return
	var dir := str(args.get("shots", OS.get_user_data_dir().path_join("_test_cache")))
	DirAccess.make_dir_recursive_absolute(dir)
	var host := Node.new()
	host.name = "FlowHost"
	add_child(host)
	flow.host = host
	flow.save = SaveData.new("user://_test_cache/gallery_save.json")
	var steps: Array = [
		[0.0, func() -> void: flow.goto_title()],
		[9.0, _shot_to.bind(dir.path_join("flow_1_title.png"))],
		[9.5, func() -> void: flow.goto_stage_select()],
		[11.5, _shot_to.bind(dir.path_join("flow_2_stage_select.png"))],
		[12.0, func() -> void: flow.start_run("hill_east_henesys", 11, {"autoplay": true, "window_autopick": 1.0,
			"speed": 4})],
		[30.0, _shot_to.bind(dir.path_join("flow_3_run.png"))],
		[30.5, func() -> void:
			var run := flow.current
			if run != null and run.has_method("build_summary"):
				flow.finish_run(run.build_summary())],
		[33.0, _shot_to.bind(dir.path_join("flow_4_results.png"))],
		[33.5, func() -> void: print("ui_gallery: flow best = ", flow.save.best_for("hill_east_henesys"))],
		[34.0, func() -> void:
			var res := flow.current
			if res != null and res.has_method("retry"):
				res.retry()],
		[38.0, _shot_to.bind(dir.path_join("flow_5_retry.png"))],
		[38.5, func() -> void: print("ui_gallery: flow done, current = ", flow.current_name); get_tree().quit()],
	]
	for s: Array in steps:
		get_tree().create_timer(float(s[0])).timeout.connect(s[1])


func _shot_to(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	print("ui_gallery: shot %s err=%d" % [path, img.save_png(path)])


static func _vec(s: String) -> Vector2:
	var p := s.split(",")
	if p.size() != 2:
		return Vector2.ZERO
	return Vector2(float(p[0]), float(p[1]))


func _take_shot() -> void:
	await RenderingServer.frame_post_draw
	var path := str(args.shot)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("ui_gallery: shot %s %dx%d err=%d" % [path, img.get_width(), img.get_height(), err])
	get_tree().quit()
