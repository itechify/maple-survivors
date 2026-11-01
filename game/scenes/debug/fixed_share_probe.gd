extends Node2D
## Tool-only synthetic Marksman M15 visual: actual cast events displayed as diagnostic bolts and damage numbers.
## ISOLATE=363 bash scripts/run.sh res://scenes/debug/fixed_share_probe.tscn -- --shots=<evidence directory>
const CF := preload("res://tests/fixtures/combat_mechanics_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
var world: RunWorld
var hits: Array = []
var bolts: Array = []
var slots: Array[int] = []


func _ready() -> void:
	get_window().content_scale_size = Vector2i(1000, 600)
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var output := String(SceneFlow.parse_flags(OS.get_cmdline_user_args()).get("shots", ""))
	if output.is_empty():
		get_tree().quit(2)
		return
	world = CF.world({"damage": "physical", "count": 2, "range": 900.0,
		"ball": "synthetic/bolt", "cast": {"rule": "nearest", "prefer": "max_hp"},
		"fixed_share": {"share": [0.2, 0.45], "cap_mult": 20.0, "boss": {"share_scale": 0.1, "cap_mult": 6.0}}})
	world.progression.job_id = 322 # diagnostic only: the probe builds its own world
	world.loadout.weapon_id = 1462001
	world.loadout.dex_stat = 100
	world.loadout.str_stat = 10
	world.loadout.watk = 50
	for i in 2:
		var slot := RF.put_mob(world, 1110100, 500 + i * 260, 190)
		world.swarm.max_hp[slot] = 10000
		world.swarm.hp[slot] = 10000
		world.swarm.steady[slot] = i # second target is a scheduled boss by the shared predicate
		slots.append(slot)
	world.mob_grid.rebuild(world.swarm.x, world.swarm.y, world.swarm.active)
	world.drain_events()
	world.runner.step(1.0 / 60.0, world)
	hits = world.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")
	bolts = world.events.filter(func(e: Dictionary) -> bool: return e.type == "ammo_shot")
	queue_redraw()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	get_viewport().get_texture().get_image().save_png(output.path_join("fixed_share.png"))
	var file := FileAccess.open(output.path_join("summary.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"job": 322, "hits": hits, "bolts": bolts}, "\t"))
	get_tree().quit(0 if hits.size() == 2 and bolts.size() == 2 else 1)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1200, 800), Color("132638"))
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(40, 60), "Marksman (322) — fixed-share diagnostic", HORIZONTAL_ALIGNMENT_LEFT, -1, 26)
	draw_string(font, Vector2(40, 105), "Synthetic data; damage lands at cast; bolts are cosmetic", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	if world == null:
		return
	draw_circle(Vector2(200, 240), 16, Color("72bbef"))
	draw_string(font, Vector2(150, 285), "Caster", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	for bolt: Dictionary in bolts:
		var end := Vector2(float(bolt.to.x), 240)
		var p := Vector2(200, 240).lerp(end, 0.35)
		draw_line(p - Vector2(26, 0), p, Color("ffd373"), 3)
		draw_line(p - Vector2(8, 6), p, Color("ffd373"), 3)
		draw_line(p - Vector2(8, -6), p, Color("ffd373"), 3)
	for i in slots.size():
		var x := world.swarm.x[slots[i]]
		draw_circle(Vector2(x, 240), 24, Color("f18a7a"))
		draw_string(font, Vector2(x - 60, 310), "Strong monster" if i == 0 else "Scheduled boss", HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		draw_string(font, Vector2(x - 60, 345), "HP %d / 10000" % world.swarm.hp[slots[i]], HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
	for hit: Dictionary in hits:
		draw_string(font, Vector2(world.swarm.x[int(hit.mob)] - 24, 185), str(hit.damage), HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color("ffd373"))
	draw_string(font, Vector2(40, 420), "20% of max HP: 2000    |    boss scale 0.1: 200", HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
