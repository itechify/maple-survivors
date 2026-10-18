class_name SkillTooltip
extends Control
## The v83-style tooltip of the Skill window (#86): a dark translucent box with a light frame (v83's
## UI.wz/UIToolTip.img frame is not in the asset cache, so it is drawn), the name in bold, the icon beside the
## description, then "[Current Level : N]" / "[Next Level : N]" with their lines, cooldown and MP cost, the weapon the
## skill needs ("Weapon : Claw", red with "(not held)" when the held weapon cannot use it), and an orange
## "Upgrades" section with one line per behaviour card. A star-tab card shows its name, icon, text and rank.
##
##   tip.show_data(model.skill_tooltip(key), anchor)   # anchor: canvas position of its top-left (clamped to the view)
##   tip.show_data({}, anchor)                         # hides it
##
## SkillWindow owns one as a top_level child with a raised z_index, so it draws over every window in the stack and
## may hang outside the Skill window. It never takes the mouse. Text with v83 markup (`#c...#`) is drawn orange.

## tier C (ours): box width, padding, icon slot and gaps.
const WIDTH := 290.0
const PAD := 8.0
const ICON := 32.0
const GAP := 6.0
const FILL := Color(0.06, 0.08, 0.15, 0.9)
const FRAME := Color(0.78, 0.82, 0.9)
const TEXT := Color(1, 1, 1)
const DIM := Color8(190, 200, 215)
## tier C (ours): the "Weapon : X (not held)" line of a skill the held weapon cannot use.
const BLOCKED := Color8(255, 130, 130)

## The data shown (SkillWindowModel.skill_tooltip / card_tooltip); {} hides the tooltip.
var data: Dictionary = {}

var _lines: Array = []


func _init() -> void:
	name = "SkillTooltip"
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
	_lines = layout(data)
	var h := PAD
	for l: Array in _lines:
		h += float(l[3])
	size = Vector2(WIDTH, h + PAD)
	if view == Vector2.ZERO:
		view = get_viewport_rect().size if is_inside_tree() else Vector2(GameSettings.BASE_VIEW)
	position = Vector2(clampf(anchor.x, 0.0, maxf(0.0, view.x - size.x)),
		clampf(anchor.y, 0.0, maxf(0.0, view.y - size.y))).floor()
	queue_redraw()


## The tooltip as drawn lines [[kind, text, color, height], ...]: kind "name", "icon_text" (the icon with the first
## text lines beside it), "text", "rule" (a separator). Plain data so tests can read what is shown.
static func layout(d: Dictionary) -> Array:
	var out: Array = []
	var inner := WIDTH - PAD * 2.0
	out.append(["name", String(d.get("name", "")), TEXT, float(MapleText.LINE) + 4.0])
	var side := MapleText.wrap_markup(String(d.get("desc", "")), inner - ICON - GAP, MapleText.SMALL)
	var beside := maxi(1, int(ceilf(ICON / MapleText.LINE_SMALL)))
	var first := PackedStringArray()
	for i in mini(beside, side.size()):
		first.append(side[i])
	out.append(["icon_text", "\n".join(first), TEXT, maxf(ICON, float(first.size() * MapleText.LINE_SMALL)) + 2.0])
	for i in range(beside, side.size()):
		out.append(["text", side[i], TEXT, float(MapleText.LINE_SMALL)])
	if d.has("rank"):
		out.append(["rule", "", FRAME, 7.0])
		out.append(["text", "Rank %d / %d" % [int(d.rank), int(d.get("max_rank", 0))], DIM,
			float(MapleText.LINE_SMALL)])
		return out
	out.append(["rule", "", FRAME, 7.0])
	if int(d.get("level", 0)) > 0:
		_para(out, "[Current Level : %d]" % int(d.level), String(d.get("current", "")), inner)
	if int(d.get("next_level", 0)) > 0:
		_para(out, "[Next Level : %d]" % int(d.next_level), String(d.get("next", "")), inner)
	var facts := PackedStringArray()
	if float(d.get("cooldown", -1.0)) >= 0.0:
		facts.append("Cooldown %s sec." % SkillText.number(float(d.cooldown)))
	if int(d.get("hp_cost", 0)) > 0:
		facts.append("HP cost %d" % int(d.hp_cost))
	if int(d.get("mp_cost", -1)) >= 0:
		facts.append("MP cost %d" % int(d.mp_cost))
	if not facts.is_empty():
		out.append(["text", "   ".join(facts), DIM, float(MapleText.LINE_SMALL) + 2.0])
	if String(d.get("needs", "")) != "":
		var blocked := not bool(d.get("usable", true))
		out.append(["text", "Weapon : %s%s" % [d.needs, " (not held)" if blocked else ""], BLOCKED if blocked else DIM,
			float(MapleText.LINE_SMALL) + 2.0])
	var ups: Array = d.get("upgrades", [])
	if not ups.is_empty():
		out.append(["rule", "", FRAME, 7.0])
		out.append(["text", "Upgrades", MapleText.ORANGE, float(MapleText.LINE_SMALL)])
		for u: Dictionary in ups:
			for line in MapleText.wrap(String(u.get("text", "")), inner, MapleText.SMALL):
				out.append(["text", line, MapleText.ORANGE, float(MapleText.LINE_SMALL)])
	return out


static func _para(out: Array, head: String, body: String, inner: float) -> void:
	out.append(["text", head, TEXT, float(MapleText.LINE_SMALL)])
	for line in MapleText.wrap_markup(body, inner, MapleText.SMALL):
		out.append(["text", line, TEXT, float(MapleText.LINE_SMALL)])


func _draw() -> void:
	if data.is_empty():
		return
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, FILL)
	draw_rect(r.grow(-0.5), FRAME, false, 1.0)
	var y := PAD
	for l: Array in _lines:
		var kind := String(l[0])
		match kind:
			"name":
				MapleText.draw_centered(self, PAD, y, WIDTH - PAD * 2.0, String(l[1]), TEXT, MapleText.SIZE, true)
			"icon_text":
				var at := Vector2(PAD, y)
				draw_rect(Rect2(at, Vector2(ICON, ICON)).grow(1.0), Color(1, 1, 1, 0.9), false, 1.0)
				UiArt.blit_icon(self, UiArt.icon_or_fallback(String(data.get("icon", ""))), at)
				var ty := y
				for line in String(l[1]).split("\n"):
					MapleText.draw_markup(self, Vector2(PAD + ICON + GAP, ty), line, l[2], MapleText.SMALL)
					ty += MapleText.LINE_SMALL
			"rule":
				draw_line(Vector2(PAD, y + 3.0), Vector2(WIDTH - PAD, y + 3.0), Color(FRAME, 0.5), 1.0)
			_:
				MapleText.draw_markup(self, Vector2(PAD, y), String(l[1]), l[2], MapleText.SMALL)
		y += float(l[3])
