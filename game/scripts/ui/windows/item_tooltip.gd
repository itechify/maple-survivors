class_name ItemTooltip
extends Control
## The v83 item tooltip of the Equip and Item windows (#108), laid out the way the v83 client shows equipment: the
## name in bold (with "(+N)" after N successful scrolls; tier B, RE clients), the icon in its box with the
## requirements beside it (UIWindow.img/ToolTip/Equip `Can` / `Cannot` label and digit art: REQ LEV / STR / DEX /
## INT / LUK, the `Cannot` red set for an unmet one), the job row (`beginner` .. `pirate`, lit for the lines the item
## allows), then one line per fact with the v83 label art (`Property`: CATEGORY, ATTACK SPEED, WEAPON ATTACK ..
## JUMP, NUMBER OF UPGRADES AVAILABLE) and the `ItemCategory` / `WeaponCategory` / `Speed` word art for its value;
## STR / DEX / INT / LUK / MaxHP / MaxMP have no v83 label art and are drawn as text. A Use item (scroll)
## shows its name, icon and String.wz description. v83 has no tooltip frame art (UI.wz holds no UIToolTip.img), so
## the box is drawn, like the Skill window's.
##
##   tip.show_data(window.equip_tooltip(instance), anchor, view)   # InventoryModel.tooltip (+ "icon", "desc")
##   tip.show_data(window.use_tooltip(id), anchor, view)            # {"name", "desc", "icon"}
##   tip.show_data({}, anchor)                                      # hides it
##
## An InventoryWindow owns one as a top_level child with a raised z_index, so it draws over every window in the
## stack. It never takes the mouse.

const TT := "UI.wz/UIWindow.img/ToolTip/Equip/"
## tier C (ours): box width, padding, icon box and gaps.
const WIDTH := 262.0
const PAD := 8.0
const ICON_BOX := Vector2(36, 36)
const LINE := 13.0
const FILL := Color(0.06, 0.08, 0.15, 0.9)
const FRAME := Color(0.78, 0.82, 0.9)
const TEXT := Color(1, 1, 1)
const DIM := Color8(190, 200, 215)
const RED := Color8(255, 80, 80)
const CREAM := Color8(255, 236, 200)
## tier C (ours): where each requirement sits beside the icon box (relative to the requirement block).
const REQ_AT := {"reqLEV": Vector2(0, 2), "reqSTR": Vector2(0, 18), "reqDEX": Vector2(0, 28),
	"reqINT": Vector2(75, 18), "reqLUK": Vector2(75, 28)}
const REQ_TEXT := {"reqLEV": "REQ LEV", "reqSTR": "REQ STR", "reqDEX": "REQ DEX", "reqINT": "REQ INT",
	"reqLUK": "REQ LUK"}
## Fact -> ToolTip/Equip/Property label canvas (tier A art, read: 3 CATEGORY, 4 ATTACK SPEED, 6 WEAPON ATTACK,
## 7 MAGIC ATTACK, 8 WEAPON DEF., 9 MAGIC DEF., 10 ACCURACY, 11 AVOIDABILITY, 13 SPEED, 14 JUMP, 16 NUMBER OF
## UPGRADES AVAILABLE); facts without art use TEXT_LABELS.
const PROPERTY := {"category": 3, "attack_speed": 4, "incPAD": 6, "incMAD": 7, "incPDD": 8, "incMDD": 9,
	"incACC": 10, "incEVA": 11, "incSpeed": 13, "incJump": 14, "slots": 16}
const TEXT_LABELS := {"category": "CATEGORY", "attack_speed": "ATTACK SPEED", "ammo": "AMMO", "incSTR": "STR", "incDEX": "DEX",
	"incINT": "INT", "incLUK": "LUK", "incMHP": "MaxHP", "incMMP": "MaxMP", "incPAD": "WEAPON ATTACK",
	"incMAD": "MAGIC ATTACK", "incPDD": "WEAPON DEF.", "incMDD": "MAGIC DEF.", "incACC": "ACCURACY",
	"incEVA": "AVOIDABILITY", "incSpeed": "SPEED", "incJump": "JUMP", "slots": "NUMBER OF UPGRADES AVAILABLE"}
const SPEED_NAMES := ["FASTEST", "FASTER", "FAST", "NORMAL", "SLOW", "SLOWER", "SLOWEST"]
const CATEGORY_NAMES := {1: "HAT", 5: "TOP", 6: "BOTTOM", 7: "SHOES", 8: "GLOVE", 21: "LONGCOAT"}
const WEAPON_NAMES := {30: "ONE-HANDED SWORD", 37: "WAND", 38: "STAFF"}

## The data shown; {} hides the tooltip.
var data: Dictionary = {}


func _init() -> void:
	name = "ItemTooltip"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_level = true
	z_index = 50
	visible = false


## Shows `p_data` with its top-left at canvas position `anchor` (moved to stay inside `view`), or hides it for {}.
func show_data(p_data: Dictionary, anchor: Vector2, view: Vector2 = Vector2.ZERO) -> void:
	data = p_data
	visible = not data.is_empty()
	if not visible:
		return
	size = Vector2(WIDTH, _paint(false))
	if view == Vector2.ZERO:
		view = get_viewport_rect().size if is_inside_tree() else Vector2(GameSettings.BASE_VIEW)
	position = Vector2(clampf(anchor.x, 0.0, maxf(0.0, view.x - size.x)),
		clampf(anchor.y, 0.0, maxf(0.0, view.y - size.y))).floor()
	queue_redraw()


## The fact lines of equipment data as [[fact key, value text], ...] (what the lower block shows, for tests).
static func fact_lines(d: Dictionary) -> Array:
	var out := []
	if int(d.get("weapon_category", -1)) >= 0 or int(d.get("category", -1)) >= 0:
		out.append(["category", ""])
	if int(d.get("attack_speed", -1)) >= 0:
		out.append(["attack_speed", ""])
	var ammo: Dictionary = d.get("ammo", {})
	if not ammo.is_empty():
		out.append(["ammo", "%s (+%d)" % [String(ammo.get("name", "")), int(ammo.get("incPAD", 0))]])
	for stat: Array in d.get("stats", []):
		var v := int(stat[1])
		out.append([String(stat[0]), ("+%d" if v > 0 else "%d") % v])
	out.append(["slots", str(int(d.get("slots", 0)))])
	return out


func _draw() -> void:
	if data.is_empty():
		return
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, FILL)
	draw_rect(r.grow(-0.5), FRAME, false, 1.0)
	_paint(true)


## Lays the tooltip out from the top; draws it when `paint`. Returns the height.
func _paint(paint: bool) -> float:
	var y := PAD - 2.0
	var title := String(data.get("name", ""))
	if int(data.get("scrolls", 0)) > 0:
		title += " (+%d)" % int(data.scrolls)
	if paint:
		MapleText.draw_centered(self, PAD, y, WIDTH - PAD * 2.0, title, TEXT, MapleText.SIZE, true)
	y += MapleText.LINE + 4.0
	if paint:
		PixelDraw.hline(self, PAD, WIDTH - PAD, y, Color(FRAME, 0.5))
	y += 6.0
	var icon_at := Vector2(PAD + 2.0, y)
	if paint:
		draw_rect(Rect2(icon_at, ICON_BOX), Color(1, 1, 1, 0.12))
		draw_rect(Rect2(icon_at, ICON_BOX).grow(0.5), Color(1, 1, 1, 0.7), false, 1.0)
		UiArt.blit_icon(self, UiArt.icon_or_fallback(String(data.get("icon", ""))), icon_at + Vector2(2, 2))
	if not data.has("reqs"):
		return _paint_use(paint, y, icon_at)
	var req_at := Vector2(icon_at.x + ICON_BOX.x + 16.0, y)
	for req: Dictionary in data.reqs:
		var at: Vector2 = req_at + REQ_AT.get(String(req.key), Vector2.ZERO)
		if paint:
			_draw_req(at, String(req.key), int(req.value), bool(req.met))
	y += 44.0
	if paint:
		_draw_jobs(Vector2(PAD + 2.0, y), data.get("jobs", []))
	y += 18.0
	if paint:
		PixelDraw.hline(self, PAD, WIDTH - PAD, y, Color(FRAME, 0.5))
	y += 5.0
	for line: Array in fact_lines(data):
		if paint:
			_draw_fact(Vector2(PAD + 2.0, y), String(line[0]), String(line[1]))
		y += LINE
	var desc := String(data.get("desc", ""))
	if desc != "":
		y += 3.0
		if paint:
			PixelDraw.hline(self, PAD, WIDTH - PAD, y, Color(FRAME, 0.5))
		y += 5.0
		for text in MapleText.wrap(desc, WIDTH - PAD * 2.0 - 2.0, MapleText.SMALL):
			if paint:
				MapleText.draw(self, Vector2(PAD + 2.0, y), text, TEXT, MapleText.SMALL)
			y += LINE
	return y + PAD


## A Use item: the description beside the icon.
func _paint_use(paint: bool, y: float, icon_at: Vector2) -> float:
	var x := icon_at.x + ICON_BOX.x + 10.0
	var lines := MapleText.wrap(String(data.get("desc", "")), WIDTH - x - PAD, MapleText.SMALL)
	var ty := y
	for text in lines:
		if paint:
			MapleText.draw(self, Vector2(x, ty), text, TEXT, MapleText.SMALL)
		ty += LINE
	return maxf(ty, y + ICON_BOX.y) + PAD


## One requirement: the v83 label art and three digits (Can or Cannot set), or text without the cache.
func _draw_req(at: Vector2, key: String, value: int, met: bool) -> void:
	var set := TT + ("Can/" if met else "Cannot/")
	var label := UiArt.frame(set + key)
	if label == null:
		MapleText.draw(self, at - Vector2(0, 2), "%s : %03d" % [String(REQ_TEXT.get(key, key)), value],
			CREAM if met else RED, 9)
		return
	UiArt.blit(self, label, at)
	var x := at.x + label.region.size.x + 3.0
	for ch in "%03d" % value:
		var d := UiArt.frame(set + ch)
		if d == null:
			continue
		# The narrow "1" has origin x -1: every digit advances one 6 px cell.
		UiArt.blit(self, d, Vector2(x - d.origin.x, at.y))
		x += 6.0


## The job row: every line's v83 word, lit (`Can`) for the lines the item allows.
func _draw_jobs(at: Vector2, allowed: Array) -> void:
	var x := at.x
	for job: Array in InventoryModel.JOB_ROW:
		var key := String(job[0])
		var ok := key in allowed
		var f := UiArt.frame(TT + ("Can/" if ok else "Cannot/") + key)
		if f != null:
			UiArt.blit(self, f, Vector2(x, at.y))
			x += f.region.size.x + 4.0
		else:
			var text := key.to_upper()
			MapleText.draw(self, Vector2(x, at.y), text, CREAM if ok else DIM, 9, true)
			x += MapleText.width(text, 9, true) + 6.0


## One fact line: the v83 label art (or text), then the value as word art (category, speed) or text.
func _draw_fact(at: Vector2, key: String, value: String) -> void:
	var x := at.x
	var label := UiArt.frame(TT + "Property/%d" % int(PROPERTY[key])) if PROPERTY.has(key) else null
	if label != null:
		UiArt.blit(self, label, at + Vector2(0, 2))
		x += label.region.size.x + 4.0
	else:
		var text := String(TEXT_LABELS.get(key, key)) + " :"
		MapleText.draw(self, at, text, CREAM, MapleText.SMALL)
		x += MapleText.width(text, MapleText.SMALL) + 4.0
	match key:
		"category":
			var weapon := int(data.get("weapon_category", -1))
			var word := UiArt.frame(TT + ("WeaponCategory/%d" % weapon if weapon >= 0
				else "ItemCategory/%d" % int(data.get("category", -1))))
			if word != null:
				UiArt.blit(self, word, Vector2(x, at.y + 2.0))
			else:
				MapleText.draw(self, Vector2(x, at.y), String(WEAPON_NAMES.get(weapon, "WEAPON")) if weapon >= 0
					else String(CATEGORY_NAMES.get(int(data.get("category", -1)), "")), TEXT, MapleText.SMALL)
		"attack_speed":
			var speed := int(data.get("attack_speed", -1))
			var word := UiArt.frame(TT + "Speed/%d" % speed)
			if word != null:
				UiArt.blit(self, word, Vector2(x, at.y + 2.0))
			else:
				MapleText.draw(self, Vector2(x, at.y), SPEED_NAMES[clampi(speed, 0, 6)], TEXT, MapleText.SMALL)
		_:
			MapleText.draw(self, Vector2(x, at.y), value, TEXT, MapleText.SMALL)
