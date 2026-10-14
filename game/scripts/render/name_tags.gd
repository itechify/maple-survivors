class_name NameTags
extends Node2D
## Name tags under mobs: elites are drawn with a name tag (docs/GAME_DESIGN.md section 4), in the style of v83's default
## character name tag - the name in the white system font (no antialiasing) on a dark translucent box just below the
## feet. v83 draws that default tag in code (UI.wz/NameTag.img only holds the cash styles 3..28), so the box colour,
## padding and offset are tier C (ours).
##
## update_from(swarm, elite, kind_names): `swarm` exposes the MobSwarm arrays `state kind x y` (docs/ARCHITECTURE.md
## 4.4.3), `elite[i]` is RunWorld.mob_elite (1 = tagged), `kind_names[kind]` the mob name (MobKind.name, i.e. String.wz).
## Live slots (STAND..HIT) get a tag; dying and free slots do not. Few elites are alive at once, so this draws with
## _draw() (one rect + one string per tag). Put it above the mob layers so tags are never hidden by terrain.

## tier C: box colour, text colour, font size, horizontal padding, box height and gap below the feet.
const BOX_COLOR := Color(0, 0, 0, 0.6)
const TEXT_COLOR := Color(1, 1, 1)
const FONT_SIZE := 12
const PAD_X := 3.0
const BOX_H := 15.0
const GAP_Y := 2.0
## Mirrors MobSwarm.STAND / HIT: slots in these states are alive.
const FIRST_LIVE := 0
const LAST_LIVE := 3

## Text font; defaults to Hud.make_font() (system Arial/Tahoma, no antialiasing).
var font: Font

## Feet positions and texts of the tags drawn this frame.
var _pos: PackedVector2Array = []
var _text: PackedStringArray = []


## Collects the tags of the tagged live slots and redraws when they changed.
func update_from(swarm: Object, elite: PackedByteArray, kind_names: PackedStringArray) -> void:
	var states: PackedInt32Array = swarm.state
	var kinds: PackedInt32Array = swarm.kind
	var xs: PackedFloat32Array = swarm.x
	var ys: PackedFloat32Array = swarm.y
	var pos := PackedVector2Array()
	var text := PackedStringArray()
	var n := mini(states.size(), elite.size())
	for i in n:
		if elite[i] == 0 or states[i] < FIRST_LIVE or states[i] > LAST_LIVE:
			continue
		var k := kinds[i]
		var name_s := kind_names[k] if k >= 0 and k < kind_names.size() else ""
		if name_s == "":
			continue
		pos.append(Vector2(roundf(xs[i]), roundf(ys[i])))
		text.append(name_s)
	if pos != _pos or text != _text:
		_pos = pos
		_text = text
		queue_redraw()


## Names per kind for update_from(): MobKind.name, else String.wz/Mob.img (`lib`) by the kind's id.
static func names_for(kinds: Array, lib: AssetLibrary) -> PackedStringArray:
	var out := PackedStringArray()
	for k: Variant in kinds:
		var s := ""
		var id := -1
		if k is Object:
			s = String(k.get("name")) if k.get("name") != null else ""
			id = int(k.get("id")) if k.get("id") != null else -1
		else:
			id = int(k)
		if s == "" and id >= 0 and lib != null:
			s = lib.string_name("Mob", id)
		out.append(s)
	return out


## Number of tags drawn.
func tag_count() -> int:
	return _pos.size()


## The tag of tag `i`: {"text": String, "feet": Vector2}.
func tag(i: int) -> Dictionary:
	return {"text": _text[i], "feet": _pos[i]}


## The box of a tag whose text is `text_w` px wide, centred under `feet` (whole pixels).
static func box_rect(feet: Vector2, text_w: float) -> Rect2:
	var w := ceilf(text_w) + 2.0 * PAD_X
	return Rect2(Vector2(feet.x - floorf(w * 0.5), feet.y + GAP_Y), Vector2(w, BOX_H))


func _draw() -> void:
	if _pos.is_empty():
		return
	if font == null:
		font = Hud.make_font()
	var ascent := font.get_ascent(FONT_SIZE)
	for i in _pos.size():
		var tw := font.get_string_size(_text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var r := box_rect(_pos[i], tw)
		draw_rect(r, BOX_COLOR)
		var baseline := r.position.y + floorf((BOX_H - font.get_height(FONT_SIZE)) * 0.5) + ascent
		draw_string(font, Vector2(r.position.x + PAD_X, baseline), _text[i], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE,
			TEXT_COLOR)
