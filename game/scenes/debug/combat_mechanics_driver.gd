extends Node2D
## Synthetic-only visual evidence for #200. Uses the real RunScene event handlers and pooled effects with generated
## arrow/burst pixels; no WZ data. Run this scene with --shots=<absolute evidence directory>.

const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

class SyntheticLibrary extends AssetLibrary:
	func anim(path: String) -> SpriteAnim:
		var image := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		image.fill(Color.TRANSPARENT)
		if path == "synthetic_blast":
			for y in 64:
				for x in 64:
					var delta := Vector2(x - 32, y - 32)
					if delta.length() < 28 and (absf(delta.x) < 5 or absf(delta.y) < 5
							or absf(absf(delta.x) - absf(delta.y)) < 4):
						image.set_pixel(x, y, Color("ffcb66"))
		else:
			# All ammo fixtures use our own left-facing arrow, including rotating diagonal flights.
			image.fill_rect(Rect2i(15, 31, 35, 3), Color("80d9ff"))
			for x in 12:
				image.fill_rect(Rect2i(12 + x, 32 - x / 2, 1, 1 + x), Color("e9f6ff"))
		var frame := SpriteFrame.new()
		frame.page = ImageTexture.create_from_image(image)
		frame.region = Rect2(0, 0, 64, 64)
		frame.origin = Vector2(32, 32)
		frame.delay_s = 1.0
		var result := SpriteAnim.new()
		result.frames.append(frame)
		result.total = 1.0
		return result

var presenter: RunScene
var title := ""
var labels: Array[Dictionary] = []
var points: Array[Dictionary] = []
var blast_box := Rect2()


func _ready() -> void:
	call_deferred("_drive")


func _drive() -> void:
	var args := SceneFlow.parse_flags(OS.get_cmdline_user_args())
	var shots := String(args.get("shots", ""))
	if shots == "":
		get_tree().quit(2)
		return
	DirAccess.make_dir_recursive_absolute(shots)
	DisplayServer.window_set_size(Vector2i(800, 600))
	presenter = RunScene.new() # deliberately not in the tree: only the real event-to-effect boundary is needed
	presenter.fx = FxRenderer.new()
	presenter.fx.library = SyntheticLibrary.new()
	add_child(presenter.fx)
	presenter.fx.set_process(false)
	title = "Ranged Final Attack — synthetic pixels"
	for row: int in 4:
		var weapon: int = [1452000, 1462000, 1472000, 1492000][row]
		var job: int = [310, 320, 410, 520][row]
		var world := CF.ranged_final(weapon, job)
		var target := RF.put_mob(world, 1110100, 620 if row % 2 == 0 else -220, 190, 100)
		world.mob_kinds[world.swarm.kind[target]].move_speed = 0
		world.swarm.y[target] -= 50 if row % 2 == 0 else 0
		world.hit_mob(target, {"skill": "trigger", "damage_type": "physical", "damage_min": 1,
			"damage_max": 1, "crit": 0, "crit_mult": 1.5}, -1)
		world.step(DT, MoveInput.new())
		for event: Dictionary in world.drain_events():
			if event.type != "ammo_shot":
				continue
			var offset := Vector2(0 if row % 2 == 0 else 450, -65 + row * 125)
			event.from += offset
			event.to += offset
			labels.append({"at": Vector2(35, 75 + row * 125),
				"text": "%s · ammo %d · immediate damage, visual in flight" % [world.held_weapon_family(), world.ammo_id()]})
			points.append({"at": event.from, "color": Color("80d9ff")})
			points.append({"at": event.to, "color": Color("9bdeae")})
			presenter.handle_events([event])
	# All four real flight slots advance by the same elapsed time; no arc is applied.
	presenter._update_throws(0.18)
	await _shot(shots.path_join("ranged_final_attack.png"))
	presenter.fx.clear()
	labels.clear()
	points.clear()
	title = "Impact blast — synthetic pixels"
	var blaster := CF.world({"kind": "projectile", "hit": "synthetic_blast", "impact_blast": {},
		"on_hit": {"status": "stun", "chance_field": "prop", "duration_field": "time"}})
	var mobs: Array[int] = []
	for x: int in [350, 380, 410, 425, 520]:
		mobs.append(RF.put_mob(blaster, 1110100, x, 190, 100))
	for tick in 25:
		blaster.step(DT, MoveInput.new())
	for event: Dictionary in blaster.drain_events():
		if event.type == "skill_impact":
			event.pos += Vector2(0, 100)
			blast_box = SkillRunner.blast_rect(blaster.loadout.stats("synthetic"), event.pos)
			presenter.handle_events([event])
	for m: int in mobs:
		var hit := blaster.swarm.hp[m] < blaster.swarm.max_hp[m]
		points.append({"at": blaster.swarm.pos(m) + Vector2(0, 80),
			"color": Color("9bdeae") if hit else Color("687483")})
	labels.append({"at": Vector2(35, 100), "text": "Three green targets hit and stunned; fourth capped, fifth outside the box."})
	labels.append({"at": Vector2(35, 420), "text": SkillText.new(blaster.book).level_line("synthetic", 1, blaster.loadout.stats("synthetic"))})
	await _shot(shots.path_join("impact_blast.png"))
	presenter.fx.library.free()
	presenter.free()
	get_tree().quit()


func _shot(path: String) -> void:
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var error := get_viewport().get_texture().get_image().save_png(path)
	print("synthetic screenshot %s: %s" % [path, error_string(error)])


func _draw() -> void:
	draw_rect(Rect2(0, 0, 800, 600), Color("14202d"))
	draw_string(ThemeDB.fallback_font, Vector2(35, 35), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.WHITE)
	if blast_box.has_area():
		draw_rect(blast_box, Color("ffcb66"), false, 2)
	for point: Dictionary in points:
		draw_circle(point.at, 9, point.color)
	for label: Dictionary in labels:
		draw_string(ThemeDB.fallback_font, label.at, label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("c5d5e5"))
