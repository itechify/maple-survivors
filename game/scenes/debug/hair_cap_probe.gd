extends Node2D
## Debug contact sheet for the cap/hair rule (spec #34 #126 QA): one row per cap, two columns per pose (the shipped rule: smap/vslot,
## then the pre-#126 rule that hid hairOverHead under a CpH5 cap). Evidence only.
##   bash scripts/godot.sh --path game res://scenes/debug/hair_cap_probe.tscn -- --shots=C:/abs/dir
##   [--caps=0,1002067,1002317] [--hairs=30000,30030]

const CELL := Vector2(100, 150)
const SCALE := 2.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.35, 0.45, 0.55))
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	var shots := String(args.get("shots", OS.get_user_data_dir()))
	DirAccess.make_dir_recursive_absolute(shots)
	var caps: Array = []
	for s in String(args.get("caps", "0,1002067,1002317,1002001")).split(","):
		caps.append(int(s))
	for hair_s in String(args.get("hairs", "30000,30030")).split(","):
		var hair := int(hair_s)
		var holder := Node2D.new()
		add_child(holder)
		var poses: Array = []
		for st in String(args.get("stances", "stand1,walk1,ladder")).split(","):
			poses.append([st, -1])
		for row in caps.size():
			for col in poses.size() * 2:
				var a := AvatarRenderer.new()
				a.position = Vector2(CELL.x * (col + 0.5), CELL.y * (row + 0.85))
				a.scale = Vector2(SCALE, SCALE)
				holder.add_child(a)
				var equips: Array = [1040002, 1060002, 1072001]
				if caps[row] > 0:
					equips.append(caps[row])
				a.set_look({"skin": 0, "face": 20000, "hair": hair, "equips": equips})
				if col % 2 == 1:
					a._cap_vslot = "CpH1H5" # the pre-#126 rule: a CpH5 cap hid hairOverHead
				@warning_ignore("integer_division")
				var pose: Array = poses[col / 2]
				a.play(pose[0], true)
				a.set_facing(pose[1])
				a.advance(0.0)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img = img.get_region(Rect2i(0, 0, int(CELL.x * poses.size() * 2), int(CELL.y * caps.size())))
		img.save_png(shots.path_join("hair_%d.png" % hair))
		holder.queue_free()
		await get_tree().process_frame
	get_tree().quit()
