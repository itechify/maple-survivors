class_name SpatialHash
extends RefCounted
## Broad phase for mobs: a uniform grid (64 px cells by default) rebuilt every tick by counting sort
## (docs/ARCHITECTURE.md section 6).
##
## rebuild() buckets every active point; queries return the point indices inside a rectangle (Rect2.has_point rules:
## right/bottom edges excluded) or a circle (distance <= r), written into a caller-supplied PackedInt32Array that is
## grown when too small. The return value is the count; entries past it are stale.
##
## With a `world` rect the grid covers it (points outside are clamped into the border cells, queries still test exact
## positions); without one the grid is fitted to the active points on every rebuild.

## Upper bound on cells when the grid is fitted to the points (coarser cells beyond it).
const MAX_CELLS := 65536

var cell := 64.0
var world := Rect2()

var _inv := 1.0 / 64.0
var _x0 := 0.0
var _y0 := 0.0
var _cols := 0
var _rows := 0
var _count := 0
## Cell start offsets (size cells + 1) into the sorted arrays below.
var _start := PackedInt32Array()
var _ids := PackedInt32Array()
var _sx := PackedFloat32Array()
var _sy := PackedFloat32Array()
var _cellof := PackedInt32Array()
var _cursor := PackedInt32Array()


func _init(p_cell: float = 64.0, p_world: Rect2 = Rect2()) -> void:
	cell = maxf(1.0, p_cell)
	world = p_world


## Number of points in the last rebuild.
func size() -> int:
	return _count


## Buckets points i (0 <= i < n, n = xs.size() when negative) whose active[i] != 0.
func rebuild(xs: PackedFloat32Array, ys: PackedFloat32Array, active: PackedByteArray, n: int = -1) -> void:
	if n < 0:
		n = mini(xs.size(), mini(ys.size(), active.size()))
	var c := cell
	if world.has_area():
		_x0 = world.position.x
		_y0 = world.position.y
		_cols = int(world.size.x / c) + 1
		_rows = int(world.size.y / c) + 1
	else:
		var lx := INF
		var ly := INF
		var hx := -INF
		var hy := -INF
		for i in n:
			if active[i] != 0:
				lx = minf(lx, xs[i])
				hx = maxf(hx, xs[i])
				ly = minf(ly, ys[i])
				hy = maxf(hy, ys[i])
		if lx == INF:
			lx = 0.0
			ly = 0.0
			hx = 0.0
			hy = 0.0
		while (int((hx - lx) / c) + 1) * (int((hy - ly) / c) + 1) > MAX_CELLS:
			c *= 2.0
		_x0 = lx
		_y0 = ly
		_cols = int((hx - lx) / c) + 1
		_rows = int((hy - ly) / c) + 1
	_inv = 1.0 / c
	var cells := _cols * _rows
	if _start.size() != cells + 1:
		_start.resize(cells + 1)
	_start.fill(0)
	if _cellof.size() < n:
		_cellof.resize(n)
	var cols := _cols
	var rows := _rows
	var inv := _inv
	var x0 := _x0
	var y0 := _y0
	var count := 0
	for i in n:
		if active[i] == 0:
			_cellof[i] = -1
			continue
		var cx := clampi(int(floor((xs[i] - x0) * inv)), 0, cols - 1)
		var cy := clampi(int(floor((ys[i] - y0) * inv)), 0, rows - 1)
		var ci := cy * cols + cx
		_cellof[i] = ci
		_start[ci + 1] += 1
		count += 1
	for ci in cells:
		_start[ci + 1] += _start[ci]
	_count = count
	if _ids.size() < count:
		_ids.resize(count)
		_sx.resize(count)
		_sy.resize(count)
	_cursor = _start.duplicate()
	for i in n:
		var ci := _cellof[i]
		if ci < 0:
			continue
		var k := _cursor[ci]
		_cursor[ci] = k + 1
		_ids[k] = i
		_sx[k] = xs[i]
		_sy[k] = ys[i]


## Writes the indices of points inside r into out; returns how many. With `limit` > 0 it stops after that many (the
## first ones in cell order).
func query_rect(r: Rect2, out: PackedInt32Array, limit: int = 0) -> int:
	if _count == 0:
		return 0
	var c0 := clampi(int(floor((r.position.x - _x0) * _inv)), 0, _cols - 1)
	var c1 := clampi(int(floor((r.end.x - _x0) * _inv)), 0, _cols - 1)
	var r0 := clampi(int(floor((r.position.y - _y0) * _inv)), 0, _rows - 1)
	var r1 := clampi(int(floor((r.end.y - _y0) * _inv)), 0, _rows - 1)
	var lx := r.position.x
	var ly := r.position.y
	var hx := r.end.x
	var hy := r.end.y
	var n := 0
	var cap := out.size()
	for row in range(r0, r1 + 1):
		var base := row * _cols
		for k in range(_start[base + c0], _start[base + c1 + 1]):
			var px := _sx[k]
			var py := _sy[k]
			if px >= lx and px < hx and py >= ly and py < hy:
				if n >= cap:
					cap = maxi(16, cap * 2)
					out.resize(cap)
				out[n] = _ids[k]
				n += 1
				if n == limit:
					return n
	return n


## Writes the indices of points within distance rad of c into out; returns how many. With `limit` > 0 it stops after
## that many (the first ones in cell order).
func query_radius(c: Vector2, rad: float, out: PackedInt32Array, limit: int = 0) -> int:
	if _count == 0 or rad < 0.0:
		return 0
	var c0 := clampi(int(floor((c.x - rad - _x0) * _inv)), 0, _cols - 1)
	var c1 := clampi(int(floor((c.x + rad - _x0) * _inv)), 0, _cols - 1)
	var r0 := clampi(int(floor((c.y - rad - _y0) * _inv)), 0, _rows - 1)
	var r1 := clampi(int(floor((c.y + rad - _y0) * _inv)), 0, _rows - 1)
	var r2 := rad * rad
	var n := 0
	var cap := out.size()
	for row in range(r0, r1 + 1):
		var base := row * _cols
		for k in range(_start[base + c0], _start[base + c1 + 1]):
			var dx := _sx[k] - c.x
			var dy := _sy[k] - c.y
			if dx * dx + dy * dy <= r2:
				if n >= cap:
					cap = maxi(16, cap * 2)
					out.resize(cap)
				out[n] = _ids[k]
				n += 1
				if n == limit:
					return n
	return n
