extends Node2D
## Stage select (docs/ARCHITECTURE.md 4.1): the v83 world-select section of the login scene (LoginBackdrop at
## WORLD_SELECT without the Neo City promo, BGM BgmUI/WCSelect); the world-select scroll (ParchmentScroll) unrolls from
## the rolled scroll hanging on the rod and lists the stages of game/data/survivor/stages.json.
##
## Left column: the progression list (stages.json `progression`, ADR 0007; #451), one row per region in order: its map mark
## (Map.wz/MapHelper.img/mark/<info/mapMark>), its region (stages.json `region`: Henesys, Ellinia, Sleepywood; #221), "Lv lo-hi"
## (the lowest and highest canonical level of the region's ordinary pool monsters over its maps, from the cache's mob info;
## omitted when the cache lacks it) and a state mark: CLEAR (in the character's `cleared_regions`, #450), a lock (greyed,
## cannot be started), or NEW (the frontier: the first unlocked, uncleared region). Six rows show; the list scrolls with the
## selection, the arrows and the mouse wheel, and opens on the frontier (the last region when all are cleared). The header
## reads "Regions cleared N/M". Right column, for the selected region: region and continent, its step in the progression, what
## unlocks it when locked (its predecessor's last boss), the objective, the best result from SaveData and the ordered maps
## with their bosses (String.wz names).
## Buttons: Start (Login.img/CharSelect/BtSelect) under the details column, Back (Login.img/Common/BtStart, the "Back" banner)
## at the bottom-left of the book and the v83 status-bar CASH SHOP button (StatusBar.img/BtShop, #118) beside it.
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
## The region rows the list shows at once: six 46 px rows (tier C, #451; the progression has five regions now and sixteen
## later, so the rest scroll). Six rows are taller than the stock parchment, so the paper grows by PAPER_EXTRA and CARD_AREA
## is the writable area of the grown paper (tier C, ported from the Nautilus branch idea, #264). Start sits under the
## details column, so no row can overlap it.
const MAX_CARDS := 6
const PAPER_EXTRA := 48.0
const CARD_AREA := Rect2(40, 148, 432, 286)
## Regions kept above the frontier when the list opens (tier C, #451): the frontier stays in view with a little context.
const FRONTIER_LEAD := 2
## Gap between the character line and the "Regions cleared N/M" header (tier C, #451).
const HEADING_GAP := 18.0
const DETAIL_X := 234.0
const DETAIL_W := 232.0
const MAP_ROW_GAP := 6.0 # tier C: compact map/boss groups on the v83 parchment; wrapped lines stay together.
const INK := Color8(102, 51, 0)
const INK_SOFT := Color8(136, 85, 34)
const INK_RED := Color8(170, 34, 0)
const INK_LOCKED := Color8(150, 134, 112) # tier C: ours, the parchment ink faded for a locked region
const INK_CLEAR := Color8(51, 102, 0) # tier C: ours, parchment-green CLEAR mark of a cleared region (#451)

var backdrop: LoginBackdrop
var scroll: ParchmentScroll
var start_button: WzButton
var back_button: WzButton
## Opens the Cash Shop as this character (#118); returns here on Leave.
var shop_button: WzButton
var character_label: Label
## "Regions cleared N/M" under the character line (#451).
var progress_label: Label
## Region cards in progression order: key, step, locked/cleared/frontier, previous (the region that unlocks it) and
## unlock_boss, first map_id/mark, region, continent, level_lo/level_hi, duration, objective and ordered map_rows.
var stages: Array[Dictionary] = []
## The loaded data (DataRepo.load_all() when empty) and the cache lookups of load_stages' `source`; tests inject synthetic ones.
var data: Dictionary = {}
var source: Dictionary = {}
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
	if data.is_empty():
		data = DataRepo.load_all()
	stages = load_progression(data, snapshot.get("character", {}).get("cleared_regions", []), source)
	selected = frontier_index(stages)
	top = list_top(selected, stages.size(), MAX_CARDS, selected - FRONTIER_LEAD)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_ui)
	scroll = RegionScroll.new()
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
	progress_label = MapleText.new(progress_text(stages), MapleText.SIZE, MapleText.WHITE, true)
	progress_label.name = "Progress"
	_ui.add_child(progress_label)
	get_viewport().size_changed.connect(_layout)
	_layout()
	_refresh()
	scroll.unroll()


## Stage infos from the loaded data (DataRepo.load_all()): those of `only` in that order, every stage in stages.json order
## when it is empty. `source` replaces the asset-cache lookups: "mob_level" (id -> canonical level, 0 unknown), "mob_name"
## (id -> String.wz name, "" unknown) and "map_img" (map id -> img root, {} absent); a missing key reads the cache.
static func load_stages(data: Dictionary, only: Array = [], source: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var all: Dictionary = data.get("stages", {}).get("stages", {})
	var keys: Array = all.keys()
	if not only.is_empty():
		keys = only.filter(func(key: String) -> bool: return all.has(key))
	var mob_name: Callable = source.get("mob_name", _cache_mob_name)
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
		for entry: Dictionary in DataRepo.stage_maps(data, key):
			var id := int(entry.map_id)
			var boss_id := int(entry.get("boss", {}).get("mob_id", 0))
			var map_name := String(source["map_name"].call(id)).strip_edges() if source.has("map_name") \
				else _cache_map_name(id)
			var boss_name := String(mob_name.call(boss_id)).strip_edges()
			map_rows.append("%s → %s" % [map_name if map_name != "" else str(id),
				boss_name if boss_name != "" else str(boss_id)])
		var levels := level_range(st, source)
		out.append({"key": key, "map_id": map_id, "step": NxAward.step_of(data.get("stages", {}), key),
			"locked": false, "cleared": false, "frontier": false, "previous": "", "unlock_boss": "",
			"region": String(labels.region),
			"continent": String(labels.continent),
			"mark": mark,
			"level_lo": levels.x, "level_hi": levels.y,
			"duration": float(st.get("duration", 0)),
			"objective": objective,
			"note": String(st.get("note", "")),
			"map_rows": map_rows})
	return out


## Every region of the progression in order. Each card carries its `step` (0-based), `locked` (not unlocked by the
## `cleared` keys), `cleared`, `frontier` (the first unlocked, uncleared region) and, for a locked one, `previous` (the
## region name that unlocks it) and `unlock_boss` (the String.wz name of that region's map 3 boss, its final form when it has one).
static func load_progression(data: Dictionary, cleared: Array, source: Dictionary = {}) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var ordered: Array = data.get("stages", {}).get("progression", [])
	var open := CharacterSnapshot.unlocked_keys(ordered, cleared)
	var cards := load_stages(data, ordered, source)
	var mob_name: Callable = source.get("mob_name", _cache_mob_name)
	for card in cards:
		var step := ordered.find(card.key)
		card["step"] = step
		card["locked"] = card.key not in open
		card["cleared"] = card.key in cleared
		if bool(card.locked) and step > 0:
			var before := String(ordered[step - 1])
			card["previous"] = DataRepo.stage_labels(data.get("stages", {}), before).region
			var boss_id := last_boss_id(data.get("stages", {}).get("stages", {}).get(before, {}))
			card["unlock_boss"] = String(mob_name.call(boss_id)).strip_edges() if boss_id > 0 else ""
		out.append(card)
	var frontier := frontier_index(out)
	if frontier >= 0 and not bool(out[frontier].cleared):
		out[frontier]["frontier"] = true
	return out


## The index of the frontier of `cards` (load_progression's): the first unlocked, uncleared region, or the last region when
## every one is cleared; -1 for an empty list.
static func frontier_index(cards: Array) -> int:
	for i in cards.size():
		if not bool(cards[i].locked) and not bool(cards[i].cleared):
			return i
	return cards.size() - 1


## The scroll position of a list of `count` rows showing `rows` at once, for the selected row and the wanted first row
## `want`: the selection always shows, and the window never runs past the last row.
static func list_top(selected: int, count: int, rows: int, want: int) -> int:
	var top_max := maxi(0, count - rows)
	return clampi(clampi(want, selected - rows + 1, selected), 0, top_max)


## The boss that ends a stage: its last map's boss, its final form when the entry names one (`final_form`); 0 when none.
static func last_boss_id(stage: Dictionary) -> int:
	var maps: Array = stage.get("maps", [])
	if maps.is_empty() or not maps[-1].get("boss") is Dictionary:
		return 0
	var boss: Dictionary = maps[-1].boss
	return int(boss.get("final_form", boss.get("mob_id", 0)))


## The lowest and highest canonical level (x, y) of the stage's ordinary pool monsters over its maps: the keyframe pools (for a
## "curve" map), explicit pools and `pool_from_life` lists minus `exclude`, without the scheduled bosses and their final
## forms (summons and revives are never in a pool). Monsters whose level the cache lacks are skipped; (0, 0) when none is known.
static func level_range(stage: Dictionary, source: Dictionary = {}) -> Vector2i:
	var level_of: Callable = source.get("mob_level", _cache_mob_level)
	var map_img: Callable = source.get("map_img", _cache_map_img)
	var skip := {}
	var ids := {}
	var maps: Array = stage.get("maps", [])
	for entry: Dictionary in maps:
		var boss: Variant = entry.get("boss", {})
		if boss is Dictionary:
			skip[int(boss.get("mob_id", 0))] = true
			skip[int(boss.get("final_form", 0))] = true
		if entry.get("pool") is String and entry.pool == "curve":
			for kf: Dictionary in stage.get("keyframes", []):
				for id: Variant in kf.get("pool", {}):
					ids[int(id)] = true
		var img: Variant = map_img.call(int(entry.get("map_id", 0))) if bool(entry.get("pool_from_life", false)) else {}
		for id: int in StagePools.resolve(entry, img if img is Dictionary else {}):
			ids[id] = true
	var lo := 0
	var hi := 0
	for id: int in ids:
		var level := int(level_of.call(id))
		if skip.has(id) or level <= 0:
			continue
		lo = level if lo == 0 else mini(lo, level)
		hi = maxi(hi, level)
	return Vector2i(lo, hi)


## "Lv lo-hi" of a card ("Lv n" when both ends meet, "" when the level is unknown).
static func level_text(card: Dictionary) -> String:
	var lo := int(card.get("level_lo", 0))
	var hi := int(card.get("level_hi", 0))
	if lo <= 0:
		return ""
	return "Lv %d" % lo if lo == hi else "Lv %d-%d" % [lo, hi]


## The header: how many of the listed regions the character has cleared.
static func progress_text(cards: Array) -> String:
	var n := 0
	for card: Dictionary in cards:
		n += 1 if bool(card.cleared) else 0
	return "Regions cleared %d/%d" % [n, cards.size()]


static func _cache_mob_level(id: int) -> int:
	var lib := UiArt.lib()
	if lib == null or not lib.has_img(AssetLibrary.mob_img_path(id)):
		return 0
	var info: Variant = lib.img(AssetLibrary.mob_img_path(id)).root.get("info", {})
	return int(info.get("level", 0)) if info is Dictionary else 0


static func _cache_mob_name(id: int) -> String:
	var lib := UiArt.lib()
	return lib.string_name("Mob", id).strip_edges() if lib != null and id > 0 else ""


static func _cache_map_name(id: int) -> String:
	var lib := UiArt.lib()
	return lib.string_name("Map", id).strip_edges() if lib != null else ""


static func _cache_map_img(map_id: int) -> Dictionary:
	var lib := UiArt.lib()
	var path := AssetLibrary.map_img_path(map_id)
	if lib == null or not lib.has_img(path):
		return {}
	return lib.img(path).root


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
		top = list_top(selected, stages.size(), MAX_CARDS, top)
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


## The card of stage `i` in the list window (cards above `top` or below the last visible row are not shown).
func _entry_rect(i: int) -> Rect2:
	return Rect2(LIST_X, CARD_AREA.position.y + 6.0 + (i - top) * ENTRY_H, LIST_W, ENTRY_H - 2.0)


## Where the Start button sits: centred under the details column, at the bottom of the paper.
func _start_rect() -> Rect2:
	return Rect2(DETAIL_X + floorf((DETAIL_W - start_button.size.x) * 0.5), CARD_AREA.end.y - 50.0, start_button.size.x,
		start_button.size.y)


func _layout() -> void:
	var view := get_viewport_rect().size
	var o := ((view - Vector2(GameSettings.BASE_VIEW)) * 0.5).floor()
	scroll.position = (view * 0.5 + SCROLL_WORLD_POS - Vector2(0, PAPER_EXTRA) - LoginBackdrop.WORLD_SELECT).floor()
	start_button.position = _start_rect().position
	back_button.position = o + Vector2(18, 600 - 74)
	# tier C: the v83 status-bar CASH SHOP button (54x34) beside Save & quit, centred on its plank.
	shop_button.position = back_button.position + Vector2(back_button.size.x + 8.0,
		floorf((back_button.size.y - shop_button.size.y) * 0.5))
	# tier C: #69 character/tier heading, above the existing parchment.
	# tier C: the "Regions cleared N/M" header shares the heading row (the grown scroll's rod covers a second row, #451).
	var heading_w := character_label.get_minimum_size().x + HEADING_GAP + progress_label.get_minimum_size().x
	character_label.position = Vector2(floorf((view.x - heading_w) * 0.5), 32)
	progress_label.position = Vector2(character_label.position.x + character_label.get_minimum_size().x + HEADING_GAP, 32)


func _draw_parchment(ci: Control) -> void:
	var r := CARD_AREA
	for i in range(top, mini(stages.size(), top + MAX_CARDS)):
		_draw_entry(ci, i)
	_draw_list_arrows(ci)
	PixelDraw.vline(ci, DETAIL_X - 7.0, r.position.y + 8.0, r.end.y - 8.0, Color(INK_SOFT, 0.45))
	if selected >= 0 and selected < stages.size():
		_draw_details(ci, stages[selected])


## Small triangles at the list's right edge when cards are hidden above or below.
func _draw_list_arrows(ci: Control) -> void:
	var x := LIST_X + LIST_W + 3.0
	if top > 0:
		var y := CARD_AREA.position.y + 8.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y + 5), Vector2(x + 8, y + 5), Vector2(x + 4, y)]), INK_SOFT)
	if top + MAX_CARDS < stages.size():
		var y := CARD_AREA.position.y + 6.0 + MAX_CARDS * ENTRY_H - 10.0
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x, y), Vector2(x + 8, y), Vector2(x + 4, y + 5)]), INK_SOFT)


## One row: the map mark, the region name, "Lv lo-hi" and the state mark (CLEAR, NEW or a lock).
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
	var ink := INK_LOCKED if locked else (INK_RED if i == selected else INK)
	MapleText.draw(ci, Vector2(tx, e.position.y + 8.0), MapleText.ellipsize(String(st.region), tw, MapleText.SMALL, true),
		ink, MapleText.SMALL, true)
	var y := e.position.y + 8.0 + MapleText.LINE_SMALL + 4.0
	MapleText.draw(ci, Vector2(tx, y), level_text(st), INK_LOCKED if locked else INK_SOFT, MapleText.SMALL)
	var right := e.end.x - 4.0
	if locked:
		_draw_lock(ci, Vector2(right - 9.0, y + 1.0), INK_LOCKED)
	elif bool(st.cleared):
		var word := "CLEAR"
		MapleText.draw(ci, Vector2(right - MapleText.width(word, MapleText.SMALL, true), y), word, INK_CLEAR,
			MapleText.SMALL, true)
	elif bool(st.frontier):
		var word := "NEW"
		MapleText.draw(ci, Vector2(right - MapleText.width(word, MapleText.SMALL, true), y), word, INK_RED,
			MapleText.SMALL, true)


## A 9x10 px padlock: a shackle over a body, `at` is its top-left.
static func _draw_lock(ci: Control, at: Vector2, color: Color) -> void:
	PixelDraw.outline(ci, Rect2(at + Vector2(2, 0), Vector2(5, 5)), color)
	ci.draw_rect(Rect2(at + Vector2(0, 4), Vector2(9, 6)), color)


func _draw_details(ci: Control, st: Dictionary) -> void:
	var x := DETAIL_X
	var y := CARD_AREA.position.y + 6.0
	var limit := _start_rect().position.y - 4.0 # nothing is drawn onto the Start button
	MapleText.draw(ci, Vector2(x, y), MapleText.ellipsize(String(st.region), DETAIL_W, MapleText.SIZE, true), INK,
		MapleText.SIZE, true)
	y += 16.0
	MapleText.draw(ci, Vector2(x, y), "%s / Region %d of %d" % [st.continent, int(st.step) + 1, stages.size()], INK_SOFT,
		MapleText.SMALL)
	y += 18.0
	if bool(st.locked):
		for line: String in MapleText.wrap(locked_text(String(st.previous), String(st.unlock_boss)), DETAIL_W,
				MapleText.SMALL, true):
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
			if y + MapleText.LINE_SMALL <= limit:
				MapleText.draw(ci, Vector2(x, y), line, INK, MapleText.SMALL)
			y += MapleText.LINE_SMALL
		y += MAP_ROW_GAP


## What unlocks a region: defeating its predecessor's last boss (`boss`, a String.wz name) in `previous_region`; without the
## name the line says to clear the region.
static func locked_text(previous_region: String, boss: String = "") -> String:
	if boss == "":
		return "Locked. Clear %s to unlock." % previous_region
	return "Locked. Defeat %s in %s to unlock." % [boss, previous_region]


## The best-result line of the details column.
static func best_text(best: Dictionary) -> String:
	return "Best: no record yet" if best.is_empty() else "Best: " + SaveData.describe(best)


## The map-select scroll: the stock parchment with up to PAPER_EXTRA more native paper scanlines inserted as it unrolls, both
## rollers kept; text and marks are never scaled (tier C, #451; the Nautilus branch's idea, #264).
class RegionScroll extends ParchmentScroll:
	func _init() -> void:
		super()
		size.y += PAPER_EXTRA
		custom_minimum_size = size
		content.size = size

	func _paper_area() -> Rect2:
		return CARD_AREA

	func _blit_frame(frame: SpriteFrame) -> void:
		var open_anim := UiArt.anim(UNROLL)
		var dims := frame.region.size
		# tier C: the paper is flat below this row of the art, so the extra scanlines repeat it
		var split := 240.0
		var extra := 0.0
		if dims.y > split and open_anim != null and not open_anim.is_empty():
			var full_height := open_anim.frames[open_anim.frame_count() - 1].region.size.y
			extra = floorf(PAPER_EXTRA * clampf((dims.y - split) / (full_height - split), 0.0, 1.0))
		if extra > 0:
			UiArt.blit_part(self, frame, Rect2(0, 0, dims.x, split), Vector2.ZERO)
			UiArt.blit_part(self, frame, Rect2(0, split, dims.x, extra), Vector2(0, split))
			UiArt.blit_part(self, frame, Rect2(0, split, dims.x, dims.y - split), Vector2(0, split + extra))
		else:
			UiArt.blit(self, frame, Vector2.ZERO)
