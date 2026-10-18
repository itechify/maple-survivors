extends Node2D
## Debug contact sheets of every weapon family on the avatar (spec #151 #154), for evidence screenshots. Tool-only.
##
##   bash scripts/godot.sh --path game res://scenes/debug/weapon_gallery.tscn -- --shots=C:/abs/dir [--weapons=1302000,1452000]
##       [--mode=cash]
##
## One PNG per weapon (<family>_<id>.png): row 1 stands and walks facing left and right in the weapon's own stances
## (WeaponInfo.stand_stance / walk_stance); row 2 fires every basic-attack action of the family (WeaponInfo.basic_actions)
## at a dummy target, each cell frozen on the impact frame with the afterimage trail and the hit spark, the swing box
## (BasicAttack.action_spec, the data the automatic attack uses) outlined. --mode=cash: a cash weapon cover
## (CASH_COVER) worn over a two-handed sword and over a claw (cash_<id>.png). Prints the action specs and every missing
## asset. Needs an asset cache imported with asset_manifest.d/common.json (MAPLE_SURVIVORS_CACHE).

## One representative weapon per family and handedness: the sword, axe and blunt weapon in both handednesses.
const WEAPONS := [1302000, 1402001, 1312004, 1412000, 1322005, 1422000, 1332000, 1372005, 1382000, 1432000, 1442000,
	1452000, 1462000, 1472000, 1482000, 1492000]
const CASH_COVER := 1702083
const CASH_OVER := [1402001, 1472000]
const OUTFIT := [1040002, 1060002, 1072001]
const SCALE := 1.6
## Unscaled sheet units: the row heights, the feet position inside a cell and the width of a standing cell.
const ROW1_H := 150.0
const ROW2_H := 190.0
const FEET := Vector2(90.0, 120.0)
const STAND_W := 170.0
const HIT_TIME_PAD := 0.01

var _shots_dir := ""
var _lib: AssetLibrary
var _body: Dictionary = {}


func _ready() -> void:
	var args := _args()
	_shots_dir = String(args.get("shots", OS.get_user_data_dir().path_join("_test_cache")))
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	_lib = AssetLibrary.get_default()
	var body := _lib.img("Character.wz/00002000.img")
	_body = body.root if body != null else {}
	if String(args.get("mode", "weapons")) == "cash":
		for id: int in CASH_OVER:
			await _sheet(id, {"weapon": CASH_COVER}, "cash_%d_over_%d" % [CASH_COVER, id])
	else:
		var ids: Array = WEAPONS
		if args.has("weapons"):
			ids = Array(String(args.weapons).split(",")).map(func(s: String) -> int: return int(s))
		for id: int in ids:
			await _sheet(id, {}, "%s_%d" % [WeaponInfo.family(id), id])
	get_tree().quit()


func _sheet(weapon: int, cash: Dictionary, file_name: String) -> void:
	var item := _lib.img(AvatarRenderer.part_img_path(weapon))
	if item == null:
		print("weapon_gallery: %s missing item img" % file_name)
		return
	var info: Dictionary = item.node("info")
	var after_name := WeaponInfo.afterimage_name(info)
	var after := _lib.img(WeaponInfo.afterimage_img_path(after_name))
	var images := {after_name: after.root} if after != null else {}
	var attack := BasicAttack.new(_body, images)
	var actions := WeaponInfo.basic_actions(weapon)
	var specs := {}
	var widths := PackedFloat32Array()
	for action in actions:
		var spec := attack.action_spec(weapon, info, action)
		specs[action] = spec
		var reach: float = -(spec.box as Rect2).position.x if not spec.is_empty() else 80.0
		widths.append(FEET.x + reach + 70.0)
	var row2_w := 0.0
	for w in widths:
		row2_w += w
	var size := Vector2(maxf(STAND_W * 4.0, row2_w), ROW1_H + ROW2_H) * SCALE
	var viewport := SubViewport.new()
	viewport.size = Vector2i(size)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	var root := Node2D.new()
	viewport.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0.35, 0.45, 0.55)
	bg.size = size
	root.add_child(bg)
	var content := Node2D.new()
	content.scale = Vector2(SCALE, SCALE)
	root.add_child(content)
	var missing := PackedStringArray()
	var look := {"skin": 0, "face": 20000, "hair": 30030, "equips": OUTFIT + [weapon]}
	if not cash.is_empty():
		look["cash"] = cash
	# Row 1: stand and walk facing left (WZ default) and right.
	for i in 4:
		var pose := "stand1" if i < 2 else "walk1"
		var a := _avatar(content, look, Vector2(STAND_W * i, 0.0) + FEET, 1 if i % 2 == 1 else -1)
		a.play(pose, true)
		a.advance(0.0 if i < 2 else 0.2)
		_label(root, Vector2(STAND_W * i, 2.0), "%s %s %s" % [pose, a.stance, "R" if i % 2 == 1 else "L"])
		missing.append_array(a.missing)
	# Row 2: every basic-attack action at its impact frame, a dummy in the swing box.
	var x := 0.0
	for n in actions.size():
		var action: String = actions[n]
		var spec: Dictionary = specs[action]
		var origin := Vector2(x, ROW1_H) + FEET
		var a := _avatar(content, look, origin, 1)
		a.play(action, true, false)
		if spec.is_empty():
			_label(root, Vector2(x, ROW1_H + 2.0), "%s: no spec" % action)
			x += widths[n]
			missing.append("%d no spec for %s" % [weapon, action])
			continue
		var box: Rect2 = spec.box
		box.position.x = -box.end.x # faces right: mirror the left-facing data box
		var outline := ReferenceRect.new()
		outline.border_color = Color(1, 1, 0.3)
		outline.editor_only = false
		outline.position = origin + box.position
		outline.size = box.size
		content.add_child(outline)
		var dummy := ColorRect.new()
		dummy.color = Color(0.85, 0.25, 0.25)
		dummy.size = Vector2(26.0, minf(48.0, box.size.y))
		dummy.position = origin + box.get_center() - dummy.size * 0.5
		content.add_child(dummy)
		a.advance(float(spec.hit_after) + HIT_TIME_PAD)
		var fx := FxRenderer.new()
		fx.library = _lib
		content.add_child(fx)
		if String(spec.afterimage) != "":
			if fx.play(String(spec.afterimage), Vector2.ZERO, true, a) < 0:
				missing.append(String(spec.afterimage))
		if fx.play(String(spec.hit_visual), origin + box.get_center(), true) < 0:
			missing.append(String(spec.hit_visual))
		fx.advance(0.03)
		var sound_ok := _lib.img("Sound.wz/Weapon.img") != null and \
			(_lib.img("Sound.wz/Weapon.img") as WzImg).node(String(spec.sound).trim_prefix("Sound.wz/Weapon.img/")) != null
		if not sound_ok:
			missing.append(String(spec.sound))
		_label(root, Vector2(x, ROW1_H + 2.0), "%s [%s] hit %.2fs" % [action, WeaponInfo.basic_kind(weapon, action),
			float(spec.hit_after)])
		print("weapon_gallery: %d %s %s kind=%s hit_after=%.3f box=%s trail=%s spark=%s sound=%s" % [weapon, WeaponInfo.family(weapon),
			action, WeaponInfo.basic_kind(weapon, action), float(spec.hit_after), box, spec.afterimage, spec.hit_visual, spec.sound])
		missing.append_array(a.missing)
		x += widths[n]
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	viewport.get_texture().get_image().save_png(_shots_dir.path_join(file_name + ".png"))
	print("weapon_gallery: %s stand=%s walk=%s actions=%s missing=%s" % [file_name, WeaponInfo.stand_stance(info),
		WeaponInfo.walk_stance(info), actions, missing])
	viewport.queue_free()
	await get_tree().process_frame


func _avatar(parent: Node2D, look: Dictionary, at: Vector2, facing: int) -> AvatarRenderer:
	var a := AvatarRenderer.new()
	a.library = _lib
	a.position = at
	parent.add_child(a)
	a.set_look(look)
	a.set_facing(facing)
	return a


func _label(parent: Node, at: Vector2, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.position = at * SCALE
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	parent.add_child(label)


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
