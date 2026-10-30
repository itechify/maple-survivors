extends Node2D
## Stage select (docs/ARCHITECTURE.md 4.1): the v83 world-select section of the login scene (LoginBackdrop at
## WORLD_SELECT without the Neo City promo, BGM BgmUI/WCSelect); the world-select scroll (ParchmentScroll) unrolls from
## the rolled scroll hanging on the rod and lists the stages of game/data/survivor/stages.json.
##
## Left column: one entry per region of the progression (stages.json `progression`, ADR 0007), in order, with its map mark
## (Map.wz/MapHelper.img/mark/<info/mapMark>) and its region (stages.json `region`: Henesys, Ellinia, Sleepywood; #221). Four
## cards fit; the list scrolls with the selection and the mouse wheel. The regions the character has not unlocked (its
## `cleared_regions`, #450) are shown greyed and cannot be started: the details say what unlocks them. Right column, for the
## selected stage: region and continent, its step in the progression, the objective, the best result from SaveData and the ordered maps with their bosses (String.wz names).
## Buttons: Start (Login.img/CharSelect/
## BtSelect) on the parchment, Back (Login.img/Common/BtStart, the "Back" banner) at the bottom-left of the book and the
## v83 status-bar CASH SHOP button (StatusBar.img/BtShop, #118) beside it.
## Keys: Up/Down select, Enter starts, Esc returns to the character's Free Market.
## Flow supplies the snapshot and owner through configure().

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
## The most region cards the list shows at once: four 46 px rows from the parchment top end exactly where the Start button
## begins (tier C, spec #253). More stages scroll (tier C, #286).
const MAX_CARDS := 4
const DETAIL_X := 234.0
const DETAIL_W := 232.0
const MAP_ROW_GAP := 6.0 # tier C: compact map/boss groups on the v83 parchment; wrapped lines stay together.
const INK := Color8(102, 51, 0)
const INK_SOFT := Color8(136, 85, 34)
const INK_RED := Color8(170, 34, 0)
const INK_LOCKED := Color8(150, 134, 112) # tier C: ours, the parchment ink faded for a locked region

var backdrop: LoginBackdrop
var scroll: ParchmentScroll
var start_button: WzButton
var back_button: WzButton
## Opens the Cash Shop as this character (#118); returns here on Leave.
var shop_button: WzButton
var character_label: Label
## Region cards in file order: key, first map_id/mark, region, continent, duration, objective and ordered map_rows.
var stages: Array[Dictionary] = []
## Selected stage index, and the index of the first card shown.
var selected := 0
var top := 0
## Best results (Flow's SaveData).
var save: SaveData

var snapshot: Dictionary = {}
var flow: SceneFlow


## Sets the carried character and owning flow before entering the tree.
func configure(p_snapshot: Dictionary, p_flow: SceneFlow) -> void:
	snapshot = p_snapshot.duplicate(true)
	flow = p_flow


var _ui: Control


func _ready() -> void:
	backdrop = LoginBackdrop.new(LoginBackdrop.WORLD_SELECT)
	backdrop.bgm = LoginBackdrop.BGM_SELECT
	add_child(backdrop)
	backdrop.hide_objs("neoCity")
	if flow == null:
		flow = get_node_or_null("/root/Flow") as SceneFlow
	save = flow.save_data() if flow != null else SaveData.new()
	stages = load_progression(DataRepo.load_all(), snapshot.get("character", {}).get("cleared_regions", []))
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
	back_button.set_plate(124, 4)
	back_button.name = "Back"
	back_button.fallback_size = Vector2(124, 52)
	back_button.label = "Back"
	back_button.pressed.connect(_on_back)
	_ui.add_child(back_button)
	shop_button = WzButton.new(HudWidget.SB + "BtShop")
	shop_button.name = "Shop"
	shop_button.fallback_size = Vector2(54, 34)
	shop_button.label = "" if shop_button.has_art() else "SHOP"
	shop_button.pressed.connect(_on_shop)
	_ui.add_child(shop_button)
	var jobs := DataRepo.jobs(DataRepo.load_all())
	character_label = MapleText.new("%s / %s / %s NX" % [snapshot.get("name", ""),
		jobs.name_of(int(snapshot.get("character", {}).get("job_id", 0))), SaveData._group(int(save.account.nx))],
		MapleText.SIZE, MapleText.WHITE, true)
	_ui.add_child(character_label)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()
	scroll.unroll()


## Stage infos from the loaded data (DataRepo.load_all()): those of `only` in that order, every stage in stages.json order
## when it is empty.
static func load_stages(data: Dictionary, only: Array = []) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Dictionary = data.get("stages", {}).get("stages", {})
	var keys: Array = all.keys()
	if not only.is_empty():
		keys = only.filter(func(key: String) -> bool: return all.has(key))
	for key: String in keys:
		var st: Dictionary = all[key]
		var map_id := int(st.get("maps", [{}])[0].get("map_id", 0))
		var labels := DataRepo.stage_labels(data.get("stages", {}), key)
		var mark := ""
		var info: Variant = UiArt.node(AssetLibrary.map_img_path(map_id) + "/info/mapMark")
		if info is String:
			mark = info
		var count := DataRepo.stage_bosses(st).size()
		var objective := "Survive %s to clear the stage." % Hud.format_time(float(st.get("duration", 0)))
		if count > 0:
			objective = "Defeat %d bosses across %d maps" % [count, DataRepo.stage_maps(data, key).size()]
		var map_rows: Array[String] = []
		var library := UiArt.lib()
		for entry: Dictionary in DataRepo.stage_maps(data, key):
			var id := int(entry.map_id)
			var boss_id := int(entry.get("boss", {}).get("mob_id", 0))
			var map_name := library.string_name("Map", id).strip_edges() if library != null else ""
			var boss_name := library.string_name("Mob", boss_id).strip_edges() if library != null else ""
			map_rows.append("%s → %s" % [map_name if map_name != "" else str(id),
				boss_name if boss_name != "" else str(boss_id)])
		out.append({"key": key, "map_id": map_id, "step": NxAward.step_of(data.get("stages", {}), key),
			"locked": false, "cleared": false, "previous": "",
			"region": String(labels.region),
			"continent": String(labels.continent),
			"mark": mark,
			"duration": float(st.get("duration", 0)),
			"objective": objective,
			"note": String(st.get("note", "")),
			"map_rows": map_rows})
	return out


## Every region of the progression in order. Each card carries its `step` (0-based), `locked` (not unlocked by the
## `cleared` keys), `cleared` and, for a locked one, `previous`: the region name that unlocks it.
static func load_progression(data: Dictionary, cleared: Array) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ordered: Array = data.get("stages", {}).get("progression", [])
	var open := CharacterSnapshot.unlocked_keys(ordered, cleared)
	var cards := load_stages(data, ordered)
	for card in cards:
		var step := ordered.find(card.key)
		card["step"] = step
		card["locked"] = card.key not in open
		card["cleared"] = card.key in cleared
		if bool(card.locked) and step > 0:
			card["previous"] = DataRepo.stage_labels(data.get("stages", {}), String(ordered[step - 1])).region
		out.append(card)
	return out


## The keys of the stages the character may start, in list order.
func unlocked_keys() -> Array:
	return stages.filter(func(card: Dictionary) -> bool: return not bool(card.locked)).map(
		func(card: Dictionary) -> String: return String(card.key))


## Starts the selected stage (new random seed); a locked stage does nothing.
func start_selected() -> void:
	if selected < 0 or selected >= stages.size() or bool(stages[selected].locked):
		return
	if flow != null:
		flow.start_round(String(stages[selected].key))


## Selects stage `i` (clamped).
func select(i: int) -> void:
	if stages.is_empty():
		return
	i = clampi(i, 0, stages.size() - 1)
	if i != selected:
		selected = i
		top = clampi(top, maxi(0, selected - MAX_CARDS + 1), selected)
		UiArt.play_sound(UiArt.SND_OVER)
		_refresh()


func _on_shop() -> void:
	if flow != null:
		flow.goto_cash_shop("stage_select")


func _on_back() -> void:
	if flow != null:
		flow.goto_free_market()


## Redraws the parchment and dims Start for a locked stage.
func _refresh() -> void:
	if start_button != null:
		start_button.disabled = selected < stages.size() and bool(stages[selected].locked)
	if scroll != null:
		scroll.queue_redraw()


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
	if not scroll.is_open() or not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed:
		return
	if mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		select(selected + (1 if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN else -1))
		return
	var hit := _entry_at(mb.position)
	if hit < 0 or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.double_click and hit == selected:
		start_selected()
	else:
		select(hit)


func _entry_at(p: Vector2) -> int:
	for i in range(top, mini(stages.size(), top + MAX_CARDS)):
		if _entry_rect(i).has_point(p):
			return i
	return -1


## The card of stage `i` in the list window (cards above `top` or below the fourth are not shown).
func _entry_rect(i: int) -> Rect2:
	var r := ParchmentScroll.PARCHMENT
	return Rect2(LIST_X, r.position.y + 6.0 + (i - top) * ENTRY_H, LIST_W, ENTRY_H - 2.0)


func _layout() -> void:
	var view := get_viewport_rect().size
	var o := ((view - Vector2(GameSettings.BASE_VIEW)) * 0.5).floor()
	scroll.position = (view * 0.5 + SCROLL_WORLD_POS - LoginBackdrop.WORLD_SELECT).floor()
	var r := ParchmentScroll.PARCHMENT
	start_button.position = Vector2(LIST_X + floorf((LIST_W - start_button.size.x) * 0.5), r.end.y - 50.0)
	back_button.position = o + Vector2(18, 600 - 74)
	# tier C: the v83 status-bar CASH SHOP button (54x34) beside Save & quit, centred on its plank.
	shop_button.position = back_button.position + Vector2(back_button.size.x + 8.0,
		floorf((back_button.size.y - shop_button.size.y) * 0.5))
	# tier C: #69 character/tier heading, above the existing parchment.
	character_label.position = Vector2(floorf((view.x - character_label.get_minimum_size().x) * 0.5), 32)


func _draw_parchment(ci: Control) -> void:
	var r := ParchmentScroll.PARCHMENT
	for i in range(top, mini(stages.size(), top + MAX_CARDS)):
		_draw_entry(ci, i)
	_draw_list_arrows(ci)
	PixelDraw.vline(ci, DETAIL_X - 7.0, r.position.y + 8.0, r.end.y - 8.0, Color(INK_SOFT, 0.45))
	if selected >= 0 and selected < stages.size():
		_draw_details(ci, stages[selected])


## Small triangles at the list's right edge when cards are hidden above or below.
func _draw_list_arrows(ci: Control) -> void:
	var r := ParchmentScroll.PARCHMENT
	var x := LIST_X + LIST_W + 3.0
	if top > 0:
		var y := r.position.y + 8.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y + 5), Vector2(x + 8, y + 5), Vector2(x + 4, y)]), INK_SOFT)
	if top + MAX_CARDS < stages.size():
		var y := r.position.y + 6.0 + MAX_CARDS * ENTRY_H - 10.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 8, y), Vector2(x + 4, y + 5)]), INK_SOFT)


func _draw_entry(ci: Control, i: int) -> void:
	var st: Dictionary = stages[i]
	var locked := bool(st.locked)
	var e := _entry_rect(i)
	if i == selected:
		ci.draw_rect(e, Color8(255, 170, 68, 70))
		PixelDraw.outline(ci, e, Color8(170, 85, 0, 160))
	var mark := UiArt.frame(MARK + String(st.mark)) if String(st.mark) != "" else null
	if mark != null:
		UiArt.blit(ci, mark, e.position + Vector2(3, 3), Color(1, 1, 1, 0.4) if locked else Color.WHITE)
	var tx := e.position.x + 46.0
	var tw := e.size.x - 48.0
	var lines := MapleText.wrap(String(st.region), tw, MapleText.SMALL, true)
	var y := e.position.y + (6.0 if lines.size() > 1 else 14.0)
	for k in mini(2, lines.size()):
		MapleText.draw(ci, Vector2(tx, y), MapleText.ellipsize(lines[k], tw, MapleText.SMALL, true),
			INK_LOCKED if locked else (INK_RED if i == selected else INK), MapleText.SMALL, true)
		y += MapleText.LINE_SMALL + 1.0


func _draw_details(ci: Control, st: Dictionary) -> void:
	var r := ParchmentScroll.PARCHMENT
	var x := DETAIL_X
	var y := r.position.y + 6.0
	MapleText.draw(ci, Vector2(x, y), MapleText.ellipsize(String(st.region), DETAIL_W, MapleText.SIZE, true), INK,
		MapleText.SIZE, true)
	y += 16.0
	MapleText.draw(ci, Vector2(x, y), "%s / Region %d" % [st.continent, int(st.step) + 1], INK_SOFT, MapleText.SMALL)
	y += 18.0
	if bool(st.locked):
		for line: String in MapleText.wrap(locked_text(String(st.previous)), DETAIL_W, MapleText.SMALL, true):
			MapleText.draw(ci, Vector2(x, y), line, INK_RED, MapleText.SMALL, true)
			y += MapleText.LINE_SMALL
		y += MAP_ROW_GAP
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
	for row: String in st.map_rows:
		for line: String in MapleText.wrap(row, DETAIL_W, MapleText.SMALL):
			MapleText.draw(ci, Vector2(x, y), line, INK, MapleText.SMALL)
			y += MapleText.LINE_SMALL
		y += MAP_ROW_GAP


## What unlocks a region: clearing the previous one (A2, #451, names its last boss).
static func locked_text(previous_region: String) -> String:
	return "Locked. Clear %s to unlock." % previous_region


## The best-result line of the details column.
static func best_text(best: Dictionary) -> String:
	return "Best: no record yet" if best.is_empty() else "Best: " + SaveData.describe(best)
