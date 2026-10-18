extends Node2D
## Results screen (docs/ARCHITECTURE.md 4.1, GAME_DESIGN section 1 step 6): the same world-select scroll as the stage
## select, unrolled with the run's results. Left: the headline ("Stage Clear!" or "You died", with the v83 tombstone
## Effect.wz/Tomb.img/land/0), the map, time survived, level, job, kills, damage dealt and a NEW BEST marker; right: the
## skills owned (Skill.wz icons with Basic.img/ItemNo rank digits, as on the HUD) and the previous best.
## The single Back button returns to character select; Enter and Esc do the same. Persistent last-tier clears
## say Victory and show tiers cleared; tool-only clears still say Stage Clear. No retry creates a parallel run.

const BT_BACK := "UI.wz/Login.img/Common/BtStart"
const ROLLED := "WorldSelect/signboard/2"
const SCROLL_WORLD_POS := Vector2(-214, -829)
const TOMB := "Effect.wz/Tomb.img/land/0"
const MARK := "Map.wz/MapHelper.img/mark/"
const RANK_DIGITS := "UI.wz/Basic.img/ItemNo/"
const LEFT_X := 46.0
const LEFT_W := 176.0
const RIGHT_X := 234.0
const RIGHT_W := 232.0
const SKILL_CELL := Vector2(58, 58)
const INK := Color8(102, 51, 0)
const INK_SOFT := Color8(136, 85, 34)
const INK_RED := Color8(170, 34, 0)
const CLEAR_COLOR := Color8(255, 136, 0)
const HEAD_OUTLINE := Color8(68, 34, 0)

## The run summary (Flow.finish_run); see SceneFlow for the keys.
var summary: Dictionary = {}
## True when this run set a new best for its stage.
var new_best := false
## The stage's best before this run ({} when none).
var previous_best: Dictionary = {}

var backdrop: LoginBackdrop
var scroll: ParchmentScroll
var flow: SceneFlow
var back_button: WzButton


## Sets the data to show (call before the screen enters the tree).
func configure(p_summary: Dictionary, p_new_best: bool, p_previous_best: Dictionary = {}, p_flow: SceneFlow = null) -> void:
	summary = p_summary
	new_best = p_new_best
	previous_best = p_previous_best
	flow = p_flow


func _ready() -> void:
	backdrop = LoginBackdrop.new(LoginBackdrop.WORLD_SELECT)
	backdrop.bgm = LoginBackdrop.BGM_SELECT
	add_child(backdrop)
	backdrop.hide_objs("neoCity")
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	scroll = ParchmentScroll.new()
	scroll.name = "Scroll"
	ui.add_child(scroll)
	scroll.draw_content.connect(_draw_parchment)
	scroll.opened.connect(func() -> void: backdrop.hide_objs(ROLLED))
	back_button = WzButton.new(BT_BACK)
	back_button.name = "CharacterSelect"
	back_button.fallback_size = Vector2(124, 52)
	back_button.label = "" if back_button.has_art() else "Character select"
	back_button.pressed.connect(to_character_select)
	ui.add_child(back_button)
	get_viewport().size_changed.connect(_layout)
	_layout()
	scroll.unroll()


## Returns to the living character slots after an ended run or a one-off round.
func to_character_select() -> void:
	if flow == null:
		flow = get_node_or_null("/root/Flow") as SceneFlow
	if flow != null:
		flow.goto_character_select()


## Headline of a summary.
static func headline(p_summary: Dictionary) -> String:
	if p_summary.get("ending") == "victory":
		return "Victory!"
	return "Stage Clear!" if bool(p_summary.get("cleared", false)) else "You died..."


## The stat rows shown for a summary: [[label, value], ...].
static func stat_rows(p_summary: Dictionary) -> Array:
	var t := float(p_summary.get("time", 0.0))
	var d := float(p_summary.get("duration", 0.0))
	var time_s := Hud.format_time(t) + (" / " + Hud.format_time(d) if d > 0.0 else "")
	var rows := [
		["Time", time_s],
		["Level", str(int(p_summary.get("level", 1)))],
		["Job", String(p_summary.get("job_name", ""))],
		["Kills", group_digits(int(p_summary.get("kills", 0)))],
		["Damage dealt", group_digits(int(p_summary.get("damage_dealt", 0)))],
	]
	if p_summary.has("tiers_cleared"):
		rows.append(["Tiers cleared", str(int(p_summary.tiers_cleared))])
	# Only persistent endings were credited; a tool round computes nx_awarded but never shows it.
	if p_summary.has("ending") and p_summary.has("nx_awarded"):
		rows.append(["NX earned", "+%s NX" % group_digits(int(p_summary.nx_awarded))])
	return rows


## 1234567 -> "1,234,567".
static func group_digits(n: int) -> String:
	return SaveData._group(n)


func _unhandled_input(event: InputEvent) -> void:
	if MapleWindow.is_confirm(event):
		back_button.pressed.emit()
		get_viewport().set_input_as_handled()
	elif MapleWindow.key_pressed(event, KEY_ESCAPE):
		back_button.pressed.emit()
		get_viewport().set_input_as_handled()


func _layout() -> void:
	var view := get_viewport_rect().size
	var o := ((view - Vector2(GameSettings.BASE_VIEW)) * 0.5).floor()
	scroll.position = (view * 0.5 + SCROLL_WORLD_POS - LoginBackdrop.WORLD_SELECT).floor()
	back_button.position = o + Vector2(18, 600 - 74)


func _draw_parchment(ci: Control) -> void:
	var r := ParchmentScroll.PARCHMENT
	ci.draw_line(Vector2(RIGHT_X - 7.0, r.position.y + 8.0), Vector2(RIGHT_X - 7.0, r.end.y - 8.0),
		Color(INK_SOFT, 0.45), 1.0)
	_draw_left(ci, r)
	_draw_right(ci, r)


func _draw_left(ci: Control, r: Rect2) -> void:
	var x := LEFT_X + 2.0
	var y := r.position.y + 4.0
	var cleared := bool(summary.get("cleared", false))
	var hx := x
	if not cleared:
		var tomb := UiArt.frame(TOMB)
		if tomb != null:
			UiArt.blit(ci, tomb, Vector2(x, y))
			hx += tomb.region.size.x + 6.0
	MapleText.draw(ci, Vector2(hx, y + 10.0), headline(summary), CLEAR_COLOR if cleared else INK_RED, 18, true, 2,
		HEAD_OUTLINE if cleared else Color8(255, 238, 204))
	y += 48.0
	var mark := UiArt.frame(MARK + _map_mark())
	var tx := x
	if mark != null:
		UiArt.blit(ci, mark, Vector2(x, y))
		tx += 44.0
	var lines := MapleText.wrap(String(summary.get("map_name", summary.get("stage", ""))), LEFT_W - (tx - x),
		MapleText.SMALL, true)
	var ly := y + (4.0 if lines.size() > 1 else 6.0)
	for k in mini(2, lines.size()):
		MapleText.draw(ci, Vector2(tx, ly), lines[k], INK, MapleText.SMALL, true)
		ly += MapleText.LINE_SMALL
	MapleText.draw(ci, Vector2(tx, ly), String(summary.get("street_name", "")), INK_SOFT, MapleText.SMALL)
	y += 46.0
	for row: Array in stat_rows(summary):
		MapleText.draw(ci, Vector2(x, y), String(row[0]), INK_SOFT, MapleText.SMALL)
		var v := String(row[1])
		MapleText.draw(ci, Vector2(LEFT_X + LEFT_W - 4.0 - MapleText.width(v, MapleText.SMALL), y), v, INK,
			MapleText.SMALL)
		y += 15.0


## Layout of learned skills, bounded above the best-result block in scroll-local coordinates.
static func skill_layout(count: int) -> Dictionary:
	# tier C: retain two named rows; larger loadouts use compact icons above a 6px best-block gap.
	var r := ParchmentScroll.PARCHMENT
	var area := Rect2(RIGHT_X, r.position.y + 26.0, RIGHT_W, r.size.y - 26.0 - 34.0 - 22.0 - 6.0)
	var names := count <= 8
	var cols := 4 if names else maxi(6, ceili(sqrt(float(count) * area.size.x / area.size.y)))
	var rows := maxi(1, ceili(float(count) / cols))
	var cell := SKILL_CELL if names else Vector2(area.size.x / cols, minf(36.0, area.size.y / rows)).floor()
	var side := minf(cell.x, cell.y)
	var icon_size := 32.0 if names else minf(32.0, side - minf(4.0, side * 0.1))
	var cells: Array[Rect2] = []
	for i in count:
		cells.append(Rect2(area.position + Vector2((i % cols) * cell.x, int(i / cols) * cell.y), cell))
	return {"area": area, "cells": cells, "names": names, "icon_size": icon_size}


func _draw_right(ci: Control, r: Rect2) -> void:
	var x := RIGHT_X
	var y := r.position.y + 6.0
	MapleText.draw(ci, Vector2(x, y), "Skills", INK, MapleText.SIZE, true)
	y += 20.0
	var skills: Array = summary.get("skills", [])
	var layout := skill_layout(skills.size())
	for i in skills.size():
		if not (skills[i] is Dictionary):
			continue
		var s: Dictionary = skills[i]
		_draw_skill(ci, s, layout.cells[i], layout.names, layout.icon_size)
	if skills.is_empty():
		MapleText.draw(ci, Vector2(x, y), "No skills.", INK_SOFT, MapleText.SMALL)
	var by := r.end.y - 34.0
	if new_best:
		MapleText.draw(ci, Vector2(x, by - 22.0), "NEW BEST!", CLEAR_COLOR, MapleText.SIZE, true, 0, HEAD_OUTLINE, true)
	MapleText.draw(ci, Vector2(x, by), "Previous best", INK, MapleText.SMALL, true)
	var prev := "none" if previous_best.is_empty() else SaveData.describe(previous_best)
	MapleText.draw(ci, Vector2(x, by + 14.0), MapleText.ellipsize(prev, RIGHT_W, MapleText.SMALL), INK_SOFT,
		MapleText.SMALL)


func _draw_skill(ci: Control, s: Dictionary, cell: Rect2, names: bool, icon_size: float) -> void:
	var icon_pos := cell.position + Vector2(floorf((cell.size.x - icon_size) * 0.5), 0)
	ci.draw_set_transform(icon_pos, 0.0, Vector2.ONE * (icon_size / 32.0))
	UiArt.blit_icon(ci, UiArt.icon_or_fallback(String(s.get("icon", ""))), Vector2.ZERO)
	var rank := str(int(s.get("rank", 0)))
	var frames: Array[SpriteFrame] = []
	var w := 0.0
	for ch in rank:
		var f := UiArt.frame(RANK_DIGITS + ch)
		if f != null:
			frames.append(f)
			w += f.region.size.x
	var rx := 32.0 - w
	for f in frames:
		UiArt.blit(ci, f, Vector2(rx, 32.0 - f.region.size.y))
		rx += f.region.size.x
	ci.draw_set_transform(Vector2.ZERO)
	if not names:
		return
	var y := cell.position.y + 34.0
	for line in MapleText.wrap(String(s.get("name", "")), cell.size.x - 8.0, MapleText.SMALL).slice(0, 2):
		MapleText.draw_centered(ci, cell.position.x, y, cell.size.x, line, INK, MapleText.SMALL)
		y += MapleText.LINE_SMALL - 1.0


func _map_mark() -> String:
	var v: Variant = UiArt.node(AssetLibrary.map_img_path(int(summary.get("map_id", 0))) + "/info/mapMark")
	return String(v) if v is String else ""
