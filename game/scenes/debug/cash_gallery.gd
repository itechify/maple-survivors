extends Node2D
## Debug contact sheets of the cash equipment on the avatar (spec #34 #117), for evidence screenshots.
##
##   bash scripts/godot.sh --path game res://scenes/debug/cash_gallery.tscn -- --shots=C:/abs/dir [--mode=items|sets]
##        [--ids=1002279,1012000] [--quit-after-shots]
##
## --mode=items (default): one PNG per curated item (or per --ids entry), named <slot>_<id>.png. Four columns: standing
##   facing left and right, walking facing left and right, with the item worn over the starter outfit. Weapon covers get
##   two rows (a Beginner sword wearer, then a Magician wand wearer); every other item one row (the sword wearer).
## --mode=montage --from=<items dir>: stacks the one-row sheets two per image (montage_<n>.png) for quick review.
## --mode=sets: every cash slot filled at once (a top + bottom set and an overall set, with a wand and a sword wearer,
##   standing and walking), named set_<n>.png.
## Needs the asset cache to contain the manifest's cash equipment (MAPLE_SURVIVORS_CACHE).

const OUTFIT := [1040002, 1060002, 1072001]
const WEAPONS := [1302000, 1372005]
const POSES := [["stand1", -1, 0.0], ["stand1", 1, 0.0], ["walk1", -1, 0.25], ["walk1", 1, 0.25]]
const CELL := Vector2(190, 300)
const SCALE := 3.0

var _shots_dir := ""


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color(0.35, 0.45, 0.55))
	var args := _args()
	_shots_dir = String(args.get("shots", OS.get_user_data_dir().path_join("_test_cache")))
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	if String(args.get("mode", "items")) == "sets":
		await _sets()
	elif String(args.get("mode", "items")) == "montage":
		_montage(String(args.get("from", _shots_dir)))
	else:
		await _items(args)
	get_tree().quit()


func _items(args: Dictionary) -> void:
	var data := DataRepo.load_all()
	var ids: Array = []
	if args.has("ids"):
		for s in String(args.ids).split(","):
			ids.append(int(s))
	else:
		for item: Dictionary in data.cash_items.items:
			if String(item.kind) == "equip":
				ids.append(int(item.id))
	var catalog := CashCatalog.from_data(data)
	for id: int in ids:
		var cash := {}
		for slot in catalog.slots_for(id):
			cash[slot] = id
		var is_cover := _slot_name(id) == "weapon"
		await _sheet("%s_%d" % [_slot_name(id), id], func(weapon: int) -> Dictionary:
			return {"skin": 0, "face": 20000, "hair": 30030, "equips": OUTFIT + [weapon], "cash": cash},
			2 if is_cover else 1)


func _sets() -> void:
	var sets := [
		{"hat": 1002279, "face": 1012000, "eye": 1022000, "earrings": 1032029, "top": 1042000, "bottom": 1062003,
			"shoes": 1072010, "gloves": 1082040, "cape": 1102005, "weapon": 1702012, "shield": 1092031},
		{"hat": 1002480, "face": 1012021, "eye": 1022018, "earrings": 1032051, "top": 1052013, "bottom": 1052013,
			"shoes": 1072088, "gloves": 1082156, "cape": 1102066, "weapon": 1702175, "shield": 1092033},
		{"hat": 1002544, "face": 1012028, "eye": 1022005, "earrings": 1032054, "top": 1052077, "bottom": 1052077,
			"shoes": 1072097, "gloves": 1082172, "cape": 1102044, "weapon": 1702004, "shield": 1702004},
	]
	for i in sets.size():
		var cash: Dictionary = sets[i]
		await _sheet("set_%d" % (i + 1), func(weapon: int) -> Dictionary:
			return {"skin": 0, "face": 20000, "hair": 30030, "equips": OUTFIT + [weapon], "cash": cash})


func _sheet(file_name: String, look_for: Callable, rows: int = 2) -> void:
	var holder := Node2D.new()
	add_child(holder)
	for row in rows:
		for col in POSES.size():
			var a := AvatarRenderer.new()
			a.position = Vector2(CELL.x * (col + 0.5), CELL.y * (row + 0.78))
			a.scale = Vector2(SCALE, SCALE)
			holder.add_child(a)
			a.set_look(look_for.call(WEAPONS[row]))
			a.play(POSES[col][0], true)
			a.set_facing(POSES[col][1])
			a.advance(POSES[col][2])
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img = img.get_region(Rect2i(0, 0, int(CELL.x * POSES.size()), int(CELL.y * rows)))
	img.save_png(_shots_dir.path_join(file_name + ".png"))
	var missing := PackedStringArray()
	for a in holder.get_children():
		for m in (a as AvatarRenderer).missing:
			if not (m in missing):
				missing.append(m)
	print("cash_gallery: %s missing=%s" % [file_name, missing])
	holder.queue_free()
	await get_tree().process_frame


## Stacks the one-row item sheets of --from two per image (montage_<n>.png in --shots) to review many items quickly.
func _montage(from: String) -> void:
	var names := PackedStringArray()
	for f in DirAccess.get_files_at(from):
		if f.ends_with(".png"):
			names.append(f)
	names.sort()
	var one_row := Vector2i(int(CELL.x * POSES.size()), int(CELL.y))
	var pending: Array[Image] = []
	var labels := PackedStringArray()
	var n := 0
	for f in names:
		var img := Image.load_from_file(from.path_join(f))
		if img == null or img.get_size() != one_row:
			continue
		pending.append(img)
		labels.append(f)
		if pending.size() == 2:
			n = _save_montage(pending, labels, n)
			pending = []
			labels = PackedStringArray()
	if not pending.is_empty():
		_save_montage(pending, labels, n)


func _save_montage(images: Array[Image], labels: PackedStringArray, n: int) -> int:
	var sheet := Image.create(int(CELL.x * POSES.size()), int(CELL.y) * 2, false, Image.FORMAT_RGBA8)
	for i in images.size():
		sheet.blit_rect(images[i], Rect2i(Vector2i.ZERO, images[i].get_size()), Vector2i(0, int(CELL.y) * i))
	sheet.save_png(_shots_dir.path_join("montage_%02d.png" % n))
	print("montage_%02d: %s" % [n, ", ".join(labels)])
	return n + 1


func _slot_name(id: int) -> String:
	@warning_ignore("integer_division")
	var category := id / 10000
	return "overall" if category == 105 else String(CashCatalog.CATEGORY_SLOT.get(category, "x"))


func _args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "1"
	return out
