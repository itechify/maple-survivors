extends Node
## Tool-only Shadow Partner probe (spec #383 NL10 #409): --shots=<absolute evidence dir>. A Night Lord (job 412 stand-in, a claw
## in hand, Shadow Partner and Lucky Seven at rank 8) on a scripted timeline: stand, walk, jump, then a row of still monsters so
## the clone throws. Writes zoomed crops of the character and the clone (`clone_<step>.png`, 3x) and full frames of the throw.
## Needs the Night Lord books (Skill.wz/411.img, 412.img) in the cache. Never saves a character.
const CLAW := 1472000
const ZOOM := 3
## Half-size in pixels of the crop around the character (before the zoom).
const CROP := Vector2i(150, 110)

var _run: RunScene
var _t := 0.0
var _shots := ""
var _step := 0
var _was_throwing := false
var _throw_shots := 0
var _after := 0.0


func _ready() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.trim_prefix("--shots=")
	if _shots.is_empty():
		push_error("echo_clone_probe requires --shots=<absolute evidence directory>")
		get_tree().quit(1)
		return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	_run = load(RunScene.SCENE_PATH).instantiate()
	_run.configure("henesys", 409, {"use_flow": false, "shots_dir": _shots, "quit_after": 17.0,
		"world_prepared": func(w: RunWorld) -> void:
			w.god = true
			w.book.skill_imgs["411"] = AssetLibrary.get_default().img("Skill.wz/411.img").root
			w.book.skill_imgs["412"] = AssetLibrary.get_default().img("Skill.wz/412.img").root
			w.set_job(412)
			w.wear_new_item(CLAW)
			w.loadout.order.clear()
			w.loadout.ranks.clear()
			for key in ["shadow_partner", "lucky_seven"]:
				w.learn_skill(key)
				w.loadout.set_rank(key, 8)
			for kind: MobKind in w.mob_kinds:
				kind.move_speed = 0.0
	})
	add_child(_run)


func _process(delta: float) -> void:
	if _run == null or _run.world == null:
		return
	_t += delta
	var w := _run.world
	match _step:
		0:
			if _t > 2.5:
				_crop("stand")
				Input.action_press("move_right")
				_step = 1
		1:
			if _t > 3.1:
				_crop("walk")
				Input.action_release("move_right")
				_step = 2
		2:
			if _t > 3.8:
				Input.action_press("jump")
				_step = 3
		3:
			if _t > 3.9:
				Input.action_release("jump")
			if _t > 4.15:
				_crop("jump")
				Input.action_press("move_right")
				_step = 4
		4:
			if _t > 8.0: # walked on to open ground before the monsters appear
				Input.action_release("move_right")
				for i in 4:
					var slot := w.spawn_mob(0, w.player.pos + Vector2(110 + 25 * i, 0), w.player.fh, 1.0, false)
					if slot >= 0:
						w.swarm.hp[slot] = 100000000
						w.swarm.max_hp[slot] = 100000000
				_step = 5
		5:
			var slot := _clone_slot(w)
			var throwing := slot >= 0 and _run.clone_renderer.is_throwing(slot)
			if throwing and not _was_throwing and _throw_shots < 3:
				_throw_shots += 1
				_after = 0.0
				_crop("throw_%d" % _throw_shots)
				_run._request_shot("full_throw_%d.png" % _throw_shots)
			if throwing and _after >= 0.0:
				_after += delta
				if _after > 0.12:
					_after = -1.0
					_crop("throw_%d_later" % _throw_shots)
			_was_throwing = throwing
			if _t > 16.0:
				_step = 6


func _clone_slot(w: RunWorld) -> int:
	var clones := w.runner.summons.clones()
	return clones[0] if not clones.is_empty() else -1


## Saves the frame around the character after the next draw, zoomed ZOOM times with nearest sampling.
func _crop(step: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	# The window may be larger than the canvas the avatar is placed on: scale its viewport position to the image.
	var ratio := Vector2(image.get_size()) / get_viewport().get_visible_rect().size
	var at := Vector2i(_run.avatar.get_global_transform_with_canvas().origin * ratio) - Vector2i(0, CROP.y / 2)
	var rect := Rect2i(at - CROP, CROP * 2).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	var out := image.get_region(rect)
	out.resize(out.get_width() * ZOOM, out.get_height() * ZOOM, Image.INTERPOLATE_NEAREST)
	out.save_png(_shots.path_join("clone_%s.png" % step))
