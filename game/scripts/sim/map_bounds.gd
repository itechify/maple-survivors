class_name MapBounds
extends RefCounted
## World/camera limits of a map (docs/ARCHITECTURE.md 4.4).
##
## Rule: `info/VRLeft,VRTop,VRRight,VRBottom` when all four are present (tier A, the map's own view range); otherwise
## the miniMap rectangle `(-centerX, -centerY, width, height)` (tier C: matches the minimap's world extent, e.g.
## 104040000 -> x -530..1787, y -1278..554, which contains every foothold); otherwise the foothold bounding box with
## 300 px added above and 100 px below (tier C: HeavenClient's border rule as described in docs/research/prior-art.md).

## Fallback margins around the foothold box. tier C: HeavenClient border rule.
const FALLBACK_TOP := 300.0
const FALLBACK_BOTTOM := 100.0


## World rectangle for the map img (cache JSON) and its footholds.
static func from_map(map_img: Dictionary, fhm: FootholdMap) -> Rect2:
	var info: Variant = map_img.get("info", {})
	if info is Dictionary and _has_nums(info, ["VRLeft", "VRTop", "VRRight", "VRBottom"]):
		var l := float(info.VRLeft)
		var t := float(info.VRTop)
		var r := float(info.VRRight)
		var b := float(info.VRBottom)
		if r > l and b > t:
			return Rect2(l, t, r - l, b - t)
	var mm: Variant = map_img.get("miniMap", {})
	if mm is Dictionary and _has_nums(mm, ["centerX", "centerY", "width", "height"]):
		var w := float(mm.width)
		var h := float(mm.height)
		if w > 0.0 and h > 0.0:
			return Rect2(-float(mm.centerX), -float(mm.centerY), w, h)
	var fb := fhm.bounds() if fhm != null else Rect2()
	return Rect2(fb.position.x, fb.position.y - FALLBACK_TOP, fb.size.x, fb.size.y + FALLBACK_TOP + FALLBACK_BOTTOM)


static func _has_nums(d: Dictionary, keys: Array) -> bool:
	for k: String in keys:
		var t := typeof(d.get(k))
		if t != TYPE_FLOAT and t != TYPE_INT:
			return false
	return true
