class_name TabStrip
extends RefCounted
## The v83 tab control skin: a row of tab shapes (grey for a hidden tab, pink for the shown one) built from one of the
## `UI.wz/Basic.img/Tab*` piece sets, the way the client's tab control draws them. The glyphs ("Equip", "Use" ...) are
## separate white canvases (`UIWindow.img/<window>/Tab/enabled|disabled/<i>`) that the windows blit on top.
##
## WZ finding (docs/research/wz-inventory.md "Tab backgrounds"): `Item/Tab` holds only the white text glyphs, so the
## shapes behind them live in Basic.img/Tab2..Tab7. Every set has the same nine canvases, `<piece><state>` with state 0
## a hidden tab and 1 the shown one: `left`/`right` the two ends of the row (6 px), `fill` a 1 px column repeated over a
## tab's body, and `middle0/1/2` the 12 px join between two neighbours (their dividing line is column 5): 0 hidden |
## hidden, 1 shown | hidden, 2 hidden | shown. Tab5 is 19 body rows plus the 2 red rows that continue the red rule under
## the Item, Skill and Shop windows' tab strips; Tab2 is a 19 px set for a plain strip.
##
## `bounds` are the n + 1 x positions that cut the strip into n tabs; the row's first tab starts at bounds[0] and the
## last ends (exclusive) at bounds[n]. Tabs may be any width of at least one join half (6 px) plus an edge.

## Tab5: the grey / pink tab with the red base, for the strips that sit on the v83 red rule.
const RED_BASE_SET := "UI.wz/Basic.img/Tab5/"
## Tab3: the same shapes with a grey base instead of the red one (a strip without the red rule).
const GREY_BASE_SET := "UI.wz/Basic.img/Tab3/"
## Width of the `left*` / `right*` end pieces and of the `middle*` joins in Tab2-Tab5 (read from the art when drawn).
const EDGE_W := 6.0
const JOIN_W := 12.0
## tier C (ours): the shown tab's flat fill when there is no cache (the tab glyphs fall back to text).
const FALLBACK_SHOWN := Color8(236, 112, 144)


## The pieces of a row of tabs from left to right (they tile [bounds[0], bounds[n]) exactly): Dictionaries {name, x, w}, `name` a canvas name of the set
## ("left1", "fill0", "middle2" ...). `fill*` pieces are 1 px canvases stretched to `w`. Pure geometry, no art needed.
static func pieces(bounds: PackedFloat32Array, selected: int, edge_w: float = EDGE_W,
		join_w: float = JOIN_W) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var n := bounds.size() - 1
	if n < 1:
		return out
	var half := join_w * 0.5
	out.append({"name": "left%d" % _state(0, selected), "x": bounds[0], "w": edge_w})
	for i in n:
		if i > 0:
			var join := 1 if _state(i - 1, selected) == 1 else (2 if _state(i, selected) == 1 else 0)
			out.append({"name": "middle%d" % join, "x": bounds[i] - half, "w": join_w})
		var x0 := bounds[0] + edge_w if i == 0 else bounds[i] + half
		var x1 := bounds[n] - edge_w if i == n - 1 else bounds[i + 1] - half
		if x1 > x0:
			out.append({"name": "fill%d" % _state(i, selected), "x": x0, "w": x1 - x0})
	out.append({"name": "right%d" % _state(n - 1, selected), "x": bounds[n] - edge_w, "w": edge_w})
	return out


## The local hit rect of every tab for a strip whose tab shapes start at `top` and are `height` tall.
static func tab_rects(bounds: PackedFloat32Array, top: float, height: float) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in bounds.size() - 1:
		out.append(Rect2(bounds[i], top, bounds[i + 1] - bounds[i], height))
	return out


## True when the piece set `set_path` ("UI.wz/Basic.img/Tab5/") is in the asset cache.
static func has_art(set_path: String) -> bool:
	return UiArt.frame(set_path + "left0") != null and UiArt.frame(set_path + "fill1") != null \
		and UiArt.frame(set_path + "middle2") != null


## Draws the row with the top of its shapes at `top`; false (nothing drawn) when the cache has no such set.
static func draw(ci: CanvasItem, set_path: String, top: float, bounds: PackedFloat32Array, selected: int) -> bool:
	if not has_art(set_path):
		return false
	for p: Dictionary in pieces(bounds, selected):
		var f := UiArt.frame(set_path + String(p.name))
		if f == null:
			continue
		var at := Vector2(float(p.x), top)
		if String(p.name).begins_with("fill"):
			UiArt.blit_part(ci, f, Rect2(Vector2.ZERO, f.region.size), at, Vector2(float(p.w), f.region.size.y))
		else:
			UiArt.blit(ci, f, at)
	return true


static func _state(i: int, selected: int) -> int:
	return 1 if i == selected else 0
