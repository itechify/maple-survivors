class_name LadderSet
extends RefCounted
## Ladders and ropes of a map (`ladderRope/<n>/{l, uf, x, y1, y2, page}`): a vertical climbable line at `x` from
## `y1` (top) to `y2` (bottom). `l` = 1 ladder, 0 rope; `uf` = 1 lets you climb off the top onto the floor there.

var x := PackedFloat32Array()
var y1 := PackedFloat32Array()
var y2 := PackedFloat32Array()
var is_ladder := PackedByteArray()
var uf := PackedByteArray()
var page := PackedInt32Array()


## Reads `ladderRope` from a map img (cache JSON).
static func from_wz(map_img: Dictionary) -> LadderSet:
	var list: Array = []
	var root: Variant = map_img.get("ladderRope", {})
	if root is Dictionary:
		for k: String in root:
			if not k.begins_with("$") and root[k] is Dictionary:
				list.append(root[k])
	return from_list(list)


## Builds from Dictionaries shaped like the WZ nodes: `{x, y1, y2, l, uf, page}` (`l`, `uf`, `page` optional).
static func from_list(list: Array) -> LadderSet:
	var s := LadderSet.new()
	for d: Dictionary in list:
		var a := float(d.get("y1", 0))
		var b := float(d.get("y2", 0))
		s.x.append(float(d.get("x", 0)))
		s.y1.append(minf(a, b))
		s.y2.append(maxf(a, b))
		s.is_ladder.append(1 if int(d.get("l", 0)) != 0 else 0)
		s.uf.append(1 if int(d.get("uf", 0)) != 0 else 0)
		s.page.append(int(d.get("page", 0)))
	return s


## Number of ladders/ropes.
func count() -> int:
	return x.size()


## The ladder/rope nearest to x (within `reach` px horizontally) whose span y1..y2 contains y, or -1.
func find_grab(px: float, py: float, reach: float) -> int:
	var best := -1
	var best_d := INF
	for i in x.size():
		var d := absf(x[i] - px)
		if d <= reach and py >= y1[i] and py <= y2[i] and d < best_d:
			best_d = d
			best = i
	return best
