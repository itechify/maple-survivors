extends Node2D
## Stage select (docs/ARCHITECTURE.md 4.1): the v83 world-select section of the login scene (LoginBackdrop at
## WORLD_SELECT without the Neo City promo, BGM BgmUI/WCSelect); the world-select scroll (ParchmentScroll) unrolls from
## the rolled scroll hanging on the rod and lists the stages of game/data/survivor/stages.json.
##
## Left column: one entry per stage with its map mark (Map.wz/MapHelper.img/mark/<info/mapMark>), map name and street
## name (String.wz/Map.img). Right column, for the selected stage: names, survival time, the best result from SaveData,
## and the survivor roster (each mob's Mob.wz stand/0 frame and String.wz name). Buttons: Start (Login.img/CharSelect/
## BtSelect) on the parchment, Back (Login.img/Common/BtStart, the "Back" banner) at the bottom-left of the book.
## Keys: Up/Down select, Enter starts, Esc goes back to the title.

const BT_START := "UI.wz/Login.img/CharSelect/BtSelect"
const BT_BACK := "UI.wz/Login.img/Common/BtStart"
## The rolled scroll obj of the world-select section (hidden while our scroll is open) and its top-left in the map.
const ROLLED := "WorldSelect/signboard/2"
const SCROLL_WORLD_POS := Vector2(-214, -829)
const MARK := "Map.wz/MapHelper.img/mark/"
## Parchment layout (scroll-local px).
const LIST_X := 46.0
const LIST_W := 176.0
const ENTRY_H := 46.0
const DETAIL_X := 234.0
const DETAIL_W := 232.0
const ROSTER_CELL := Vector2(58, 76)
## Mob feet above the cell bottom (two name lines below them).
const ROSTER_FEET := 26.0
const INK := Color8(102, 51, 0)
const INK_SOFT := Color8(136, 85, 34)
const INK_RED := Color8(170, 34, 0)

var backdrop: LoginBackdrop
var scroll: ParchmentScroll
var start_button: WzButton
var back_button: WzButton
## Stage keys in file order and their info: key, map_id, name, street, mark, duration, objective and normal mobs.
var stages: Array[Dictionary] = []
## Selected stage index.
var selected := 0
## Best results (Flow's SaveData).
var save: SaveData

var _ui: Control
var _mob_frames: Dictionary = {}


func _ready() -> void:
	backdrop = LoginBackdrop.new(LoginBackdrop.WORLD_SELECT)
	backdrop.bgm = LoginBackdrop.BGM_SELECT
	add_child(backdrop)
	backdrop.hide_objs("neoCity")
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	save = flow.save_data() if flow != null else SaveData.new()
	stages = load_stages(DataRepo.load_all())
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	scroll = ParchmentScroll.new()
	scroll.name = "Scroll"
	_ui.add_child(scroll)
	scroll.draw_content.connect(_draw_parchment)
	scroll.gui_input.connect(_on_scroll_input)
	scroll.opened.connect(func() -> void: backdrop.hide_objs(ROLLED))
	start_button = WzButton.new(BT_START)
	start_button.name = "Start"
	start_button.fallback_size = Vector2(101, 30)
	start_button.label = "" if start_button.has_art() else "Start"
	start_button.pressed.connect(start_selected)
	scroll.content.add_child(start_button)
	back_button = WzButton.new(BT_BACK)
	back_button.name = "Back"
	back_button.fallback_size = Vector2(124, 52)
	back_button.label = "" if back_button.has_art() else "Back"
	back_button.pressed.connect(_on_back)
	_ui.add_child(back_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	scroll.unroll()


## Stage infos from the loaded data (DataRepo.load_all()) in stages.json order.
static func load_stages(data: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Dictionary = data.get("stages", {}).get("stages", {})
	for key: String in all:
		var st: Dictionary = all[key]
		var map_id := int(st.get("map_id", 0))
		var names := {}
		var lib := UiArt.lib()
		if lib != null:
			names = lib.map_strings(map_id)
		var mark := ""
		var info: Variant = UiArt.node(AssetLibrary.map_img_path(map_id) + "/info/mapMark")
		if info is String:
			mark = info
		var count := (st.get("bosses", []) as Array).size()
		var objective := "Survive %s to clear the stage." % Hud.format_time(float(st.get("duration", 0)))
		if count > 0:
			objective = "Defeat the boss to clear." if count == 1 else "Defeat all %d bosses to clear." % count
		var roster := DataRepo.stage_mob_ids(data, key)
		for boss: Dictionary in st.get("bosses", []):
			var index := roster.find(int(boss.mob_id))
			if index >= 0:
				roster.remove_at(index)
		out.append({"key": key, "map_id": map_id,
			"name": String(names.get("mapName", st.get("name", key))),
			"street": String(names.get("streetName", "")),
			"mark": mark,
			"duration": float(st.get("duration", 0)),
			"objective": objective,
			"note": String(st.get("note", "")),
			"mobs": roster})
	return out


## Starts the selected stage (new random seed).
func start_selected() -> void:
	if selected < 0 or selected >= stages.size():
		return
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.start_run(String(stages[selected].key))


## Selects stage `i` (clamped).
func select(i: int) -> void:
	if stages.is_empty():
		return
	i = clampi(i, 0, stages.size() - 1)
	if i != selected:
		selected = i
		UiArt.play_sound(UiArt.SND_OVER)
		scroll.queue_redraw()


func _on_back() -> void:
	var flow := get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.goto_title()


func _unhandled_input(event: InputEvent) -> void:
	var used := true
	var step := MapleWindow.vertical_step(event)
	if step != 0:
		select(selected + step)
	elif MapleWindow.is_confirm(event):
		start_button.pressed.emit()
	elif MapleWindow.key_pressed(event, KEY_ESCAPE):
		back_button.pressed.emit()
	else:
		used = false
	if used:
		get_viewport().set_input_as_handled()


func _on_scroll_input(event: InputEvent) -> void:
	if not scroll.is_open():
		return
	var p := (event as InputEventMouse).position if event is InputEventMouse else Vector2(-1, -1)
	var hit := _entry_at(p)
	if hit < 0:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			if mb.double_click and hit == selected:
				start_selected()
			else:
				select(hit)


func _entry_at(p: Vector2) -> int:
	for i in stages.size():
		if _entry_rect(i).has_point(p):
			return i
	return -1


func _entry_rect(i: int) -> Rect2:
	var r := ParchmentScroll.PARCHMENT
	return Rect2(LIST_X, r.position.y + 6.0 + i * ENTRY_H, LIST_W, ENTRY_H - 2.0)


func _layout() -> void:
	var view := get_viewport_rect().size
	var o := ((view - Vector2(GameSettings.BASE_VIEW)) * 0.5).floor()
	scroll.position = (view * 0.5 + SCROLL_WORLD_POS - LoginBackdrop.WORLD_SELECT).floor()
	var r := ParchmentScroll.PARCHMENT
	start_button.position = Vector2(LIST_X + floorf((LIST_W - start_button.size.x) * 0.5), r.end.y - 50.0)
	back_button.position = o + Vector2(18, 600 - 74)


func _draw_parchment(ci: Control) -> void:
	var r := ParchmentScroll.PARCHMENT
	for i in stages.size():
		_draw_entry(ci, i)
	ci.draw_line(Vector2(DETAIL_X - 7.0, r.position.y + 8.0), Vector2(DETAIL_X - 7.0, r.end.y - 8.0),
		Color(INK_SOFT, 0.45), 1.0)
	if selected >= 0 and selected < stages.size():
		_draw_details(ci, stages[selected])


func _draw_entry(ci: Control, i: int) -> void:
	var st: Dictionary = stages[i]
	var e := _entry_rect(i)
	if i == selected:
		ci.draw_rect(e, Color8(255, 170, 68, 70))
		ci.draw_rect(e, Color8(170, 85, 0, 160), false)
	var mark := UiArt.frame(MARK + String(st.mark)) if String(st.mark) != "" else null
	if mark != null:
		UiArt.blit(ci, mark, e.position + Vector2(3, 3))
	var tx := e.position.x + 46.0
	var tw := e.size.x - 48.0
	var lines := MapleText.wrap(String(st.name), tw, MapleText.SMALL, true)
	var y := e.position.y + (6.0 if lines.size() > 1 else 14.0)
	for k in mini(2, lines.size()):
		MapleText.draw(ci, Vector2(tx, y), MapleText.ellipsize(lines[k], tw, MapleText.SMALL, true),
			INK_RED if i == selected else INK, MapleText.SMALL, true)
		y += MapleText.LINE_SMALL + 1.0


func _draw_details(ci: Control, st: Dictionary) -> void:
	var r := ParchmentScroll.PARCHMENT
	var x := DETAIL_X
	var y := r.position.y + 6.0
	MapleText.draw(ci, Vector2(x, y), MapleText.ellipsize(String(st.name), DETAIL_W, MapleText.SIZE, true), INK,
		MapleText.SIZE, true)
	y += 16.0
	MapleText.draw(ci, Vector2(x, y), String(st.street), INK_SOFT, MapleText.SMALL)
	y += 18.0
	MapleText.draw(ci, Vector2(x, y), String(st.objective), INK,
		MapleText.SMALL)
	y += 15.0
	var note := String(st.get("note", ""))
	if note != "":
		MapleText.draw(ci, Vector2(x, y), MapleText.ellipsize(note, DETAIL_W, MapleText.SMALL), INK_SOFT,
			MapleText.SMALL)
		y += 15.0
	MapleText.draw(ci, Vector2(x, y), best_text(save.best_for(String(st.key)) if save != null else {}), INK_RED,
		MapleText.SMALL, true)
	y += 18.0
	var mobs: PackedInt32Array = st.mobs
	var cols := int(DETAIL_W / ROSTER_CELL.x)
	var rows := maxi(1, ceili(float(mobs.size()) / cols))
	var cell_size := Vector2(ROSTER_CELL.x, minf(ROSTER_CELL.y, (r.end.y - 6.0 - y) / rows))
	for i in mobs.size():
		var cell := Vector2(x + (i % cols) * cell_size.x, y + int(i / cols) * cell_size.y)
		_draw_mob(ci, mobs[i], cell, cell_size)


func _draw_mob(ci: Control, mob_id: int, cell: Vector2, cell_size: Vector2) -> void:
	var f := _mob_frame(mob_id)
	if f != null:
		# Fit the entire preview canvas above its two name lines; the in-run sprites keep native scale.
		var icon_box := Vector2(cell_size.x - 4.0, cell_size.y - ROSTER_FEET)
		var scale := minf(1.0, minf(icon_box.x / f.size().x, icon_box.y / f.size().y))
		var size := (f.size() * scale).floor()
		var top := cell + Vector2((cell_size.x - size.x) * 0.5, icon_box.y - size.y)
		ci.draw_texture_rect(f.texture, Rect2(top.floor(), size), false)
	var lib := UiArt.lib()
	var nm := lib.string_name("Mob", mob_id) if lib != null else str(mob_id)
	var y := cell.y + cell_size.y - ROSTER_FEET + 1.0
	for line in MapleText.wrap(nm, ROSTER_CELL.x + 2.0, MapleText.SMALL).slice(0, 2):
		MapleText.draw_centered(ci, cell.x - 1.0, y, ROSTER_CELL.x + 2.0, line, INK, MapleText.SMALL)
		y += MapleText.LINE_SMALL - 1.0


func _mob_frame(mob_id: int) -> SpriteFrame:
	if _mob_frames.has(mob_id):
		return _mob_frames[mob_id]
	var lib := UiArt.lib()
	var f: SpriteFrame = null
	if lib != null:
		var root := lib.mob_root(mob_id)
		for stance: String in ["stand", "fly", "move"]:
			if root.get(stance) is Dictionary:
				f = UiArt.frame(lib.mob_anim_img_path(mob_id) + "/" + stance + "/0")
				break
	_mob_frames[mob_id] = f
	return f


## The best-result line of the details column.
static func best_text(best: Dictionary) -> String:
	return "Best: no record yet" if best.is_empty() else "Best: " + SaveData.describe(best)
