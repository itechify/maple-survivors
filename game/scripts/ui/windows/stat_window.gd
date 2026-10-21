class_name StatWindow
extends UiWindow
## The v83 character Stat window (hotkey S, or Menu -> Stat): UI.wz/UIWindow.img/Stat `backgrnd` (CHARACTER STAT:
## name, job, level, guild, HP, MP, EXP, fame, ability points, STR/DEX/INT/LUK) with the `backgrnd2` detail panel
## (attack, weapon defence, magic, magic defence, accuracy, avoidability, hands, speed, jump) beside it; BtDetail
## shows / hides the detail panel, BtUIClose closes the window. Read-only: AP is spent automatically, so the BtApUp
## buttons are never shown. v83 stats only (survivor cards are skills, listed on the Skill window).
##
##   StatWindow.new(info)   # info: RunScene.stat_info() - name, job, level, exp, exp_next, hp, max_hp, mp, max_mp,
##                          # str, dex, int, luk, ap, attack, magic, weapon_def, magic_def, accuracy, avoid, speed, jump
##                          # and str_bonus .. luk_bonus (what worn equipment adds)
## A main stat with an equipment bonus shows the v83 way, "total (base+bonus)"; without one just the total.
##
## A row whose key is missing from `info` (guild, fame, hands: the sim has no such stat) shows "-". Without the cache
## the window keeps its size and draws plain panels with the labels.

const ART := "UI.wz/UIWindow.img/Stat/"
const CLOSE := "UI.wz/UIWindow.img/BtUIClose"
## Art sizes (v83 Stat backgrnd 175x347, backgrnd2 177x203).
const MAIN_SIZE := Vector2(175, 347)
const DETAIL_SIZE := Vector2(177, 203)
## tier C (ours): the detail panel hangs on the main panel's right edge, bottoms aligned (both end in the same blue
## strip).
const DETAIL_POS := Vector2(175, 144)
## tier C (ours, measured on the v83 art): value text inset in the main panel's fields, the detail panel's fields,
## the AP box, and the buttons in the bottom strip.
const MAIN_VALUE_X := 61.0
const DETAIL_VALUE_X := 80.0
const AP_BOX := Rect2(61, 214, 28, 15)
const DETAIL_BUTTON_POS := Vector2(120, 324)
const CLOSE_BUTTON_POS := Vector2(10, 325)
## Main panel rows: key, label (fallback drawing only), field top y (v83 backgrnd; the job field is two rows tall).
const MAIN_ROWS := [["name", "NAME", 33], ["job", "JOB", 56], ["level", "LEVEL", 79], ["guild", "GUILD", 97],
	["hp", "HP", 115], ["mp", "MP", 133], ["exp", "EXP.", 151], ["fame", "FAME", 169], ["str", "STR", 245],
	["dex", "DEX", 263], ["int", "INT", 281], ["luk", "LUK", 299]]
## Detail panel rows (v83 backgrnd2).
const DETAIL_ROWS := [["attack", "ATTACK", 7], ["weapon_def", "WEAPON DEF.", 25], ["magic", "MAGIC", 43],
	["magic_def", "MAGIC DEF.", 61], ["accuracy", "ACCURACY", 79], ["avoid", "AVOIDABILITY", 97],
	["hands", "HANDS", 115], ["speed", "SPEED", 133], ["jump", "JUMP", 151]]
const FIELD_H := 16.0

## The stats shown (RunScene.stat_info()).
var info: Dictionary = {}
## Whether the detail panel is shown.
var show_detail := true:
	set(v):
		show_detail = v
		_resize()

var _bt_detail: WzButton
var _bt_close: WzButton


func _init(p_info: Dictionary = {}) -> void:
	super._init()
	name = "StatWindow"
	window_id = "stat"
	info = p_info
	title_height = UiWindow.TITLE_H
	_bt_detail = WzButton.new(ART + "BtDetail")
	_bt_detail.name = "Detail"
	_bt_detail.fallback_size = Vector2(47, 18)
	_bt_detail.label = "" if _bt_detail.has_art() else "DETAIL"
	_bt_detail.position = DETAIL_BUTTON_POS
	_bt_detail.pressed.connect(func() -> void: show_detail = not show_detail)
	add_child(_bt_detail)
	_bt_close = WzButton.new(CLOSE)
	_bt_close.name = "Close"
	_bt_close.fallback_size = Vector2(32, 15)
	_bt_close.label = "" if _bt_close.has_art() else "X"
	_bt_close.position = CLOSE_BUTTON_POS
	_bt_close.pressed.connect(request_close)
	add_child(_bt_close)
	_resize()


## Replaces the shown stats.
func set_info(p_info: Dictionary) -> void:
	info = p_info
	queue_redraw()


## The text shown for row `key` ("-" when the sim has no such stat).
func value_text(key: String) -> String:
	if key == "hp" or key == "mp":
		if not info.has(key):
			return "-"
		return "%d / %d" % [int(info[key]), int(info.get("max_" + key, 0))]
	if key == "exp":
		if not info.has("exp"):
			return "-"
		var next := float(info.get("exp_next", 0))
		var pct := 0.0 if next <= 0.0 else 100.0 * clampf(float(info.exp) / next, 0.0, 1.0)
		return "%d (%.2f%%)" % [int(info.exp), pct]
	if not info.has(key):
		return "-"
	var v: Variant = info[key]
	if key == "speed" or key == "jump":
		return "%d%%" % int(v)
	var bonus := int(info.get(key + "_bonus", 0))
	if key in ["str", "dex", "int", "luk"] and bonus != 0:
		return "%d (%d+%d)" % [int(v), int(v) - bonus, bonus]
	if v is String:
		return v
	return str(int(v))


## The +AP buttons are never shown (AP is spent automatically).
func ap_buttons_visible() -> bool:
	return false


func title_rect() -> Rect2:
	return Rect2(0, 0, MAIN_SIZE.x, title_height)


func _has_point(p: Vector2) -> bool:
	if Rect2(Vector2.ZERO, MAIN_SIZE).has_point(p):
		return true
	return show_detail and Rect2(DETAIL_POS, DETAIL_SIZE).has_point(p)


func _resize() -> void:
	size = Vector2(DETAIL_POS.x + DETAIL_SIZE.x, MAIN_SIZE.y) if show_detail else MAIN_SIZE
	queue_redraw()


func _draw() -> void:
	_draw_panel(ART + "backgrnd", Vector2.ZERO, MAIN_SIZE, MAIN_ROWS, MAIN_VALUE_X - 4.0)
	var black := MapleText.BLACK
	for row: Array in MAIN_ROWS:
		MapleText.draw(self, Vector2(MAIN_VALUE_X, float(row[2]) + 2.0), value_text(String(row[0])), black,
			MapleText.SMALL)
	MapleText.draw_centered(self, AP_BOX.position.x, AP_BOX.position.y + 1.0, AP_BOX.size.x, value_text("ap"), black,
		MapleText.SMALL)
	if not show_detail:
		return
	_draw_panel(ART + "backgrnd2", DETAIL_POS, DETAIL_SIZE, DETAIL_ROWS, DETAIL_VALUE_X - 4.0)
	for row: Array in DETAIL_ROWS:
		MapleText.draw(self, DETAIL_POS + Vector2(DETAIL_VALUE_X, float(row[2]) + 2.0), value_text(String(row[0])),
			black, MapleText.SMALL)


## The panel art, or (without the cache) a plain panel with the row labels.
func _draw_panel(path: String, at: Vector2, panel: Vector2, rows: Array, label_w: float) -> void:
	var f := UiArt.frame(path)
	if f != null:
		UiArt.blit(self, f, at)
		return
	draw_rect(Rect2(at, panel), Color8(220, 228, 240))
	PixelDraw.outline(self, Rect2(at, panel), Color8(99, 147, 183))
	for row: Array in rows:
		var y := float(row[2])
		draw_rect(Rect2(at + Vector2(6, y), Vector2(label_w - 8.0, FIELD_H)), Color8(204, 85, 136))
		MapleText.draw(self, at + Vector2(9, y + 2.0), String(row[1]), MapleText.WHITE, MapleText.SMALL)
