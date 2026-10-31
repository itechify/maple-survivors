extends Node2D
## Tool-only probe of the summon behaviours (spec #384 M9, GAME_DESIGN 7.121): --shots=<absolute evidence dir>.
## A synthetic Octopus (turret) and Gaviota (kamikaze) from tests/fixtures/summon_behavior_fixtures.gd with made-up ids, drawn with synthetic
## art through the real PlayerSummonRenderer and ProjectileRenderer (the turret's ball array). No asset cache or saved
## character needed. Shots: t<tick>.png (the label measures a ball's speed; the bird dives, strikes once and is gone).
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const SummonFixtures := preload("res://tests/fixtures/summon_behavior_fixtures.gd")
const DT := 1.0 / 60.0
const PREFIX_OCTOPUS := "Skill.wz/212.img/skill/2129901/summon/"
const PREFIX_GAVIOTA := "Skill.wz/212.img/skill/2129902/summon/"
const BALL := "Skill.wz/212.img/skill/2129901/summon/attack1/info/ball"
const SHOT_TICKS := [16, 24, 32, 40, 52, 64, 76, 100, 150]

var world: RunWorld
var output := ""
var _view: Node2D
var _summons: PlayerSummonRenderer
var _balls: ProjectileRenderer
var _library := AssetLibrary.new()
var _label := ""
var _last_ball := Vector2.INF
var _speed := 0.0


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			output = arg.trim_prefix("--shots=")
	if output.is_empty():
		push_error("summon_behavior_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(output)
	world = SummonFixtures.both_world(60.0)
	world.god = true
	for path: String in ["stand", "summoned", "die", "attack1"]:
		_art(PREFIX_OCTOPUS + path, Vector2i(40, 56), Color("e8714a") if path != "attack1" else Color("ffb15a"), 4)
	for path: String in ["stand", "summoned", "die", "attack1", "fly"]:
		_art(PREFIX_GAVIOTA + path, Vector2i(50, 40), Color("f2f2f2") if path != "attack1" else Color("fff08a"), 5)
	_art(BALL, Vector2i(24, 10), Color("ffe36b"), 2)
	_view = Node2D.new()
	_view.position = Vector2(0, 140)
	add_child(_view)
	_summons = PlayerSummonRenderer.new()
	_summons.library = _library
	_view.add_child(_summons)
	_balls = ProjectileRenderer.new()
	_balls.library = _library
	_view.add_child(_balls)
	world.player.facing = -1
	world.runner.step(DT, world)
	world.runner.step(DT, world)
	RF.put_mob(world, 1110100, 330, 195, 100000.0)
	RF.put_mob(world, 1110100, 560, 195, 100000.0)
	world.mob_grid.rebuild(world.swarm.x, world.swarm.y, world.swarm.active)
	world.loadout.order.clear()
	for tick in 200:
		world.runner.tick_cooldowns(DT, world)
		_summons.update_from(world.runner.summons)
		_balls.update_from(world.runner.summons.turret, world.visual_paths, DT)
		_measure()
		queue_redraw()
		if tick in SHOT_TICKS:
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(output.path_join("t%03d.png" % tick))
	get_tree().quit()


## The ball's measured speed between two ticks, in px/s (must equal the WZ bulletSpeed, 300).
func _measure() -> void:
	var t := world.runner.summons.turret
	for b in t.active.size():
		if t.active[b] != 0:
			var p := Vector2(t.x[b], t.y[b])
			if _last_ball != Vector2.INF:
				_speed = p.distance_to(_last_ball) / DT
			_last_ball = p
			_label = "ball %d  v = %.0f px/s" % [b, _speed]
			return
	_last_ball = Vector2.INF


func _draw() -> void:
	draw_rect(Rect2(0, 0, 800, 600), Color("132638"))
	draw_set_transform(_view.position)
	draw_line(Vector2(0, 190), Vector2(800, 190), Color("3b6a52"), 2)
	if world == null:
		return
	var s := world.runner.summons
	for i in s.active.size():
		if s.active[i] != 0 and s.definitions[i].get("behavior", "") == "turret":
			draw_arc(SummonTurret.centre(s, i), SummonTurret.radius(s, i), 0, TAU, 96, Color(1, 1, 1, 0.25), 1.0)
	draw_circle(world.cast_origin(), 10, Color("72bbef"))
	for m in world.swarm.active.size():
		if world.swarm.active[m] != 0:
			var body := world.swarm.mob_kind(m).hitbox_at(world.swarm.x[m], world.swarm.y[m], world.swarm.facing[m])
			draw_rect(body, Color("f18a7a") if world.swarm.hp[m] == world.swarm.max_hp[m] else Color("ffc0b0"), true)
	draw_set_transform(Vector2.ZERO)
	draw_string(ThemeDB.fallback_font, Vector2(20, 40), "Octopus (turret): circle r 300, ball at bulletSpeed 300. Gaviota: dives once, then dies.",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 16)
	draw_string(ThemeDB.fallback_font, Vector2(20, 64), _label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16)


## A flat synthetic animation: `count` frames of a filled rounded rectangle whose shade alternates.
func _art(path: String, size: Vector2i, color: Color, count: int) -> void:
	var anim := SpriteAnim.new()
	anim.path = path
	for k in count:
		var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
		image.fill(Color(0, 0, 0, 0))
		var tint := color.lightened(0.15 * (k % 2))
		for px in size.x:
			for py in size.y:
				var edge := Vector2(px - size.x * 0.5, py - size.y * 0.5) / (Vector2(size) * 0.5)
				if edge.length() <= 1.0:
					image.set_pixel(px, py, tint)
		var frame := SpriteFrame.new()
		frame.page = ImageTexture.create_from_image(image)
		frame.region = Rect2(Vector2.ZERO, Vector2(size))
		frame.origin = Vector2(size.x * 0.5, size.y)
		if path == BALL:
			frame.origin = Vector2(size.x * 0.5, size.y * 0.5)
		frame.delay_s = 0.12
		frame.start = anim.total
		anim.total += frame.delay_s
		anim.frames.append(frame)
	_library._anims[path] = anim
