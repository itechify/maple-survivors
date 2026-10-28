extends Node2D
## Tool-only synthetic burst in flight: --shots=<absolute evidence directory>. No cache or saved character needed.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
var world: RunWorld
var output := ""

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			output = arg.trim_prefix("--shots=")
	if output.is_empty():
		get_tree().quit(1)
		return
	world = RunWorld.new(RF.setup("quiet", 336, RF.quiet_data()))
	RF.place_player(world, 150)
	world.loadout.order.clear()
	var d := world.book.def("energy_bolt").duplicate(true)
	d.cast = {"rule": "burst"}
	d.burst = {"interval": 0.1, "wind_up": 0.4, "retarget": true}
	d.count = 12
	d.speed = 240.0
	d.range = 600.0
	world.book.defs["probe"] = d
	world.data.jobs_survivor.jobs["212"].skill_pool.append("probe")
	world.learn_skill("probe")
	RF.put_mob(world, 1110100, 700, 195, 100000.0)
	world.mob_grid.rebuild(world.swarm.x, world.swarm.y, world.swarm.active)
	for i in 86:
		world.player.pos.x += 0.3
		world.runner.step(DT, world)
		world.projectiles.step(DT, world.swarm, world.mob_grid, world.events)
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output.path_join("burst.png"))
	get_tree().quit()

func _draw() -> void:
	draw_rect(Rect2(0, 0, 800, 600), Color("132638"))
	draw_string(ThemeDB.fallback_font, Vector2(40, 70), "Burst: moving caster, staggered shots, retained target", HORIZONTAL_ALIGNMENT_LEFT, -1, 22)
	if world == null:
		return
	draw_circle(world.cast_origin(), 12, Color("72bbef"))
	draw_circle(Vector2(700, 175), 18, Color("f18a7a"))
	for i in world.projectiles.active.size():
		if world.projectiles.active[i] != 0:
			var p := Vector2(world.projectiles.x[i], world.projectiles.y[i])
			draw_line(p - Vector2(12, 0), p + Vector2(7, 0), Color("ffd373"), 3)
			draw_line(p + Vector2(2, -4), p + Vector2(7, 0), Color("ffd373"), 2)
			draw_line(p + Vector2(2, 4), p + Vector2(7, 0), Color("ffd373"), 2)
	draw_string(ThemeDB.fallback_font, Vector2(40, 300), "Synthetic diagnostic at 1.43 s; 12 arrows, 0.4 s wind-up, 0.1 s interval", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
