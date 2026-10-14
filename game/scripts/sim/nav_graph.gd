class_name NavGraph
extends RefCounted
## Platform graph for mob pursuit (docs/GAME_DESIGN.md section 4): nodes are FootholdMap platforms, edges are the ways
## a ground mob can get from one platform to another without ladders.
##
## - "drop": step off an open platform end and fall. The step-off is the same for every mob whatever its walk speed
##   (so the graph can predict it exactly): from the end point (x_from, surface y) the mob drifts outward at
##   `drop_speed` until it is `drop_probe` px past the end, then falls straight down (gravity, fall_speed, walls,
##   landing exactly as MobSwarm's air step, simulated here with the same fixed `dt`). The edge goes to the platform
##   that trajectory lands on; ends whose trajectory lands nowhere or back on their own platform get no edge.
##   MobSwarm executes drops with `vx` = the edge's `vx` (+-drop_speed) and the same drift stop.
## - "jump" (only when `can_jump`): a platform whose surface is 1..`jump_height` px above and reachable with a
##   ballistic hop (`jump_speed`, `gravity`) whose takeoff is within `jump_reach` px horizontally of the landing
##   point. When the two platforms overlap horizontally the edge is a takeoff *range* [lo, hi] (the mob hops straight
##   up wherever it is in that range, unless a ceiling lies between the two surfaces); otherwise it is a single
##   point with a horizontal speed `vx` that lands `margin` px inside the target and clears any wall or ceiling on
##   the way (the arc is checked against FootholdMap).
##
## route() / hops() / reachable() read a next-hop table built by BFS (fewest edges) from every platform; P is small
## (23 on 104040000). Mobs do not steer by edge count, though: fewest edges can mean the far end of a long platform
## (on 104040000 the 1518 px platform above the ground drops onto the ground only at its left end; its right end drops
## onto a step one edge further, right next to the ground's right half). prepare_target(to_p, tx) builds a travel-cost
## field toward a target point instead: cost[e] is the px-equivalent cost of taking edge e from take[e] and going on to
## (to_p, tx) the cheapest way, i.e. the edge's air cost (`edge_cost` + its horizontal travel), the walks on every
## later platform from a landing to the next takeoff, and the walk on to_p from the last landing to tx (a straight-up
## hop takes off, and lands, at the point of its range nearest to where the route goes on). route_cost(p, x) /
## best_edge(p, x) add the walk from x to an edge's take and take the minimum; MobSwarm (which walks to take[e] and
## takes off there) and SpawnDirector use them.
## The field is rebuilt (a queue-based shortest-path pass over the edges, against the reverse transitions built once)
## when the target platform changes or tx moves `target_step` px.
## Defaults in DEFAULTS, overridable through `opts`. `gravity`, `fall_speed` and `jump_speed` must match the
## PhysicsConstants given to MobSwarm.step (RunWorld builds both graphs from the same Physics.img values).

const DROP := 0
const JUMP := 1
const KIND_NAMES := ["drop", "jump"]

const DEFAULTS := {
	"can_jump": true,
	"jump_height": 70.0,  # tier C: below the 77 px apex of a 555 px/s hop
	"jump_reach": 90.0,  # tier C: max horizontal takeoff-to-landing distance
	"jump_speed": 555.0,  # tier C: mobs hop with the player's Physics.img jumpSpeed
	"gravity": 2000.0,  # tier A: Physics.img gravityAcc
	"fall_speed": 670.0,  # tier A: Physics.img fallSpeed
	"drop_probe": 4.0,  # tier C: ours, a dropping mob drifts this far past the platform end, then falls straight
	"drop_speed": 120.0,  # tier C: ours, horizontal speed of that drift (2 ticks: a quick step off the edge)
	"dt": 1.0 / 60.0,  # the fixed sim tick (docs/ARCHITECTURE.md 4.3) used to simulate drops like MobSwarm does
	"margin": 8.0,  # tier C: land at least this far inside the target platform
	"sample_step": 4.0,  # tier C: x sampling when searching overlapping jump ranges
	"gap_inset": 1.0,  # tier C: ours, a gap jump's first takeoff candidate is this far inside the platform end
	"gap_step": 4.0,  # tier C: ours, takeoff candidates step back by this much until the arc clears walls
	"edge_cost": 40.0,  # tier C: ours, px of walking a drop or hop is worth in the travel-cost field (~ a fall's time)
	"target_step": 16.0,  # tier C: ours, the cost field is rebuilt when the target x moves this far
}

var opts: Dictionary
var node_count := 0
## Edge arrays (index = edge id): kind, platforms, representative takeoff/landing x, takeoff range, hop speed.
var e_kind := PackedInt32Array()
var e_from := PackedInt32Array()
var e_to := PackedInt32Array()
var e_x_from := PackedFloat32Array()
var e_x_to := PackedFloat32Array()
var e_lo := PackedFloat32Array()
var e_hi := PackedFloat32Array()
var e_vx := PackedFloat32Array()
## Outgoing edges per platform (CSR): edges of p are _out_edges[_out_start[p] .. _out_start[p + 1]).
var _out_start := PackedInt32Array()
var _out_edges := PackedInt32Array()
## Next-hop edge for (from * node_count + to), -1 = unreachable or same platform.
var _next := PackedInt32Array()
## Hop count for (from * node_count + to), -1 = unreachable.
var _dist := PackedInt32Array()
## Travel-cost field for the target given to prepare_target(): per edge, the cost (px) from its takeoff to the target
## point (INF = the target cannot be reached that way) and the takeoff x it is priced from (`take`: x_from for edges
## with one takeoff point; for a straight-up hop's range the point of [lo, hi] nearest to where the route goes on from
## its landing, which is the takeoff point), and per platform the edges with a finite cost (CSR:
## cand_edges[cand_start[p] .. cand_start[p + 1]); none on the target platform itself).
var cost := PackedFloat32Array()
var take := PackedFloat32Array()
var cand_start := PackedInt32Array()
var cand_edges := PackedInt32Array()
var _cand_target := -2
var _cand_also := -1
var _cand_tx := NAN
## Per edge: its air cost (edge_cost + horizontal travel).
var _air := PackedFloat32Array()
## Reverse transitions (CSR): the edges landing on edge f's source platform are _in_edges[_in_start[f] ..
## _in_start[f + 1]).
var _in_start := PackedInt32Array()
var _in_edges := PackedInt32Array()


## Builds the graph for one movement class (walkers: `{"can_jump": false}`, jumpers: `{"can_jump": true}`).
static func build(fhm: FootholdMap, p_opts: Dictionary = {}) -> NavGraph:
	var g := NavGraph.new()
	g.opts = DEFAULTS.duplicate()
	for k: String in p_opts:
		g.opts[k] = p_opts[k]
	g._build(fhm)
	return g


## Number of edges.
func edge_count() -> int:
	return e_kind.size()


## First edge to take from platform `from_p` towards `to_p`, or -1 (same platform or unreachable).
func route(from_p: int, to_p: int) -> int:
	if from_p < 0 or to_p < 0 or from_p >= node_count or to_p >= node_count:
		return -1
	return _next[from_p * node_count + to_p]


## Like route(), but among the first edges of all equally short routes picks the one whose takeoff range is nearest
## to x (so a mob does not walk to the far end of its platform when a nearer edge does the same job). Ties go to the
## lower edge index.
func route_near(from_p: int, to_p: int, x: float) -> int:
	if route(from_p, to_p) < 0:
		return -1
	var n := node_count
	var need := _dist[from_p * n + to_p] - 1
	var best := -1
	var best_d := INF
	for k in range(_out_start[from_p], _out_start[from_p + 1]):
		var c := _out_edges[k]
		var w := e_to[c]
		if (_dist[w * n + to_p] if w != to_p else 0) != need:
			continue
		var d := _range_dist(c, x)
		if d < best_d:
			best_d = d
			best = c
	return best


## Builds the travel-cost field toward the point (to_p, tx) (see the class doc): `cost` per edge and the candidate
## edges per platform. tx = NAN prices only the arrival on to_p (no final walk). also_p (>= 0, != to_p) is a second
## platform that counts as arrived, priced like to_p (MobSwarm: the floor right below a player standing on a low step,
## from where a mob touches it). Kept while the target platforms are the same and tx is within `target_step` px of the
## x it was built for.
func prepare_target(to_p: int, tx: float = NAN, also_p: int = -1) -> void:
	if also_p == to_p:
		also_p = -1
	if to_p == _cand_target and also_p == _cand_also and cand_start.size() == node_count + 1:
		if (is_nan(tx) and is_nan(_cand_tx)) or absf(tx - _cand_tx) < float(opts.target_step):
			return
	_cand_target = to_p
	_cand_also = also_p
	_cand_tx = tx
	var n := node_count
	var ne := e_kind.size()
	cost.resize(ne)
	cost.fill(INF)
	take = e_x_from.duplicate()
	cand_start.resize(n + 1)
	cand_edges.resize(0)
	if to_p >= 0 and to_p < n and ne > 0:
		# Shortest paths over the edges toward the target (queue-based label correcting: a few passes on these small
		# graphs). An edge landing on to_p ends there (its cost is its air cost + the walk to tx); routes never pass
		# through to_p (by the triangle inequality, leaving it and coming back is never cheaper than walking on it). A
		# straight-up hop lands where it took off, so it is priced from the point of its range nearest to where the
		# route goes on (tx, or the next edge's takeoff) and that point becomes its `take`.
		var queue := PackedInt32Array()
		var inq := PackedByteArray()
		inq.resize(ne)
		inq.fill(0)
		for g in ne:
			if e_to[g] == to_p or (also_p >= 0 and e_to[g] == also_p):
				var land := e_x_to[g]
				if e_lo[g] < e_hi[g] and not is_nan(tx):
					land = clampf(tx, e_lo[g], e_hi[g])
					take[g] = land
				cost[g] = _air[g] + (0.0 if is_nan(tx) else absf(land - tx))
				queue.append(g)
				inq[g] = 1
		var head := 0
		while head < queue.size():
			var f := queue[head]
			head += 1
			inq[f] = 0
			var cf := cost[f]
			var tf := take[f]
			for k in range(_in_start[f], _in_start[f + 1]):
				var g := _in_edges[k]
				if e_to[g] == to_p or e_to[g] == also_p:
					continue
				var ranged := e_lo[g] < e_hi[g]
				var land := clampf(tf, e_lo[g], e_hi[g]) if ranged else e_x_to[g]
				var c := _air[g] + absf(land - tf) + cf
				if c < cost[g] - 0.001:
					cost[g] = c
					if ranged:
						take[g] = land
					if inq[g] == 0:
						inq[g] = 1
						queue.append(g)
	for p in n:
		cand_start[p] = cand_edges.size()
		if p == to_p or p == also_p:
			continue
		for k in range(_out_start[p], _out_start[p + 1]):
			var c := _out_edges[k]
			if cost[c] < INF:
				cand_edges.append(c)
	cand_start[n] = cand_edges.size()


## Travel cost (px) from x on platform p to the point given to prepare_target() (|x - tx| on the target platform or
## also_p, 0 when it was given no x); INF when the target cannot be reached from p.
func route_cost(p: int, x: float) -> float:
	if p < 0 or p >= node_count or _cand_target < 0:
		return INF
	if p == _cand_target or p == _cand_also:
		return 0.0 if is_nan(_cand_tx) else absf(x - _cand_tx)
	var best := INF
	for k in range(cand_start[p], cand_start[p + 1]):
		var c := cand_edges[k]
		var d := absf(x - take[c]) + cost[c]
		if d < best:
			best = d
	return best


## The edge a mob at x on platform p takes toward the point given to prepare_target() (the cheapest walk to its
## `take` + its cost; ties go to the lower edge index), or -1 (on the target platform or also_p, or no way there).
func best_edge(p: int, x: float) -> int:
	if p < 0 or p >= node_count or p == _cand_target or p == _cand_also or _cand_target < 0:
		return -1
	var best := -1
	var best_d := INF
	for k in range(cand_start[p], cand_start[p + 1]):
		var c := cand_edges[k]
		var d := absf(x - take[c]) + cost[c]
		if d < best_d:
			best_d = d
			best = c
	return best


## Number of edges on the shortest route from a to b (0 when a == b, -1 when unreachable).
func hops(a: int, b: int) -> int:
	if a < 0 or b < 0 or a >= node_count or b >= node_count:
		return -1
	return _dist[a * node_count + b]


## True when platform b can be reached from a (a == b counts).
func reachable(a: int, b: int) -> bool:
	return a == b or route(a, b) >= 0


## Edge description: `kind` ("drop"/"jump"), `from_p`, `to_p`, `x_from`, `x_to` (where the mob lands), plus
## `lo`/`hi` (takeoff range on from_p) and `vx` (initial horizontal speed: the hop's for gap jumps, 0 for straight-up
## hops, +-drop_speed for drops).
func edge(e: int) -> Dictionary:
	return {
		"kind": KIND_NAMES[e_kind[e]], "from_p": e_from[e], "to_p": e_to[e],
		"x_from": e_x_from[e], "x_to": e_x_to[e], "lo": e_lo[e], "hi": e_hi[e], "vx": e_vx[e],
	}


## Outgoing edge ids of platform p.
func edges_from(p: int) -> PackedInt32Array:
	return _out_edges.slice(_out_start[p], _out_start[p + 1])


## Where a mob stepping off the platform end (xe, ye) towards `side` (-1/1) lands: Vector3(x, y, foothold), with
## foothold -1 when it falls below every foothold. Replays MobSwarm's air step for a drop tick by tick (drift at
## drop_speed until drop_probe px past the end, then straight down; walls, the foothold box's horizontal limits,
## landing via FootholdMap.find_landing; positions and speeds rounded to float32 like MobSwarm's packed arrays).
static func drop_landing(fhm: FootholdMap, xe: float, ye: float, side: int, p_opts: Dictionary = DEFAULTS) -> Vector3:
	var grav := float(p_opts.get("gravity", DEFAULTS.gravity))
	var fall := float(p_opts.get("fall_speed", DEFAULTS.fall_speed))
	var dt := float(p_opts.get("dt", DEFAULTS.dt))
	var fb := fhm.bounds()
	var f32 := PackedFloat32Array([xe, ye, side * float(p_opts.get("drop_speed", DEFAULTS.drop_speed)), 0.0,
		xe + side * float(p_opts.get("drop_probe", DEFAULTS.drop_probe))])
	var x := f32[0]
	var y := f32[1]
	var vx := f32[2]
	var vy := 0.0
	var stop := f32[4]
	for _tick in 100000:
		var vy1 := minf(vy + grav * dt, fall)
		var nx := x + vx * dt
		var ny := y + (vy + vy1) * 0.5 * dt
		if vx != 0.0 and (nx - stop) * vx >= 0.0:
			nx = stop
			vx = 0.0
		if nx != x:
			var w := fhm.wall_hit(x, y, nx, ny)
			if w >= 0:
				nx = fhm.x1[w] - signf(nx - x) * 0.01
				vx = 0.0
			if nx < fb.position.x or nx > fb.end.x:
				nx = clampf(nx, fb.position.x, fb.end.x)
				vx = 0.0
		if ny > y:
			var g := fhm.find_landing(x, y, nx, ny)
			if g >= 0:
				return Vector3(nx, fhm.y_at(g, nx), g)
		if ny > fb.end.y:
			break
		f32[0] = nx
		f32[1] = ny
		f32[2] = vx
		f32[3] = vy1
		x = f32[0]
		y = f32[1]
		vx = f32[2]
		vy = f32[3]
	return Vector3(x, y, -1)


func _range_dist(e: int, x: float) -> float:
	if x < e_lo[e]:
		return e_lo[e] - x
	if x > e_hi[e]:
		return x - e_hi[e]
	return 0.0


func _add(kind: int, from_p: int, to_p: int, x_from: float, x_to: float, lo: float, hi: float, vx: float) -> void:
	e_kind.append(kind)
	e_from.append(from_p)
	e_to.append(to_p)
	e_x_from.append(x_from)
	e_x_to.append(x_to)
	e_lo.append(lo)
	e_hi.append(hi)
	e_vx.append(vx)


func _build(fhm: FootholdMap) -> void:
	node_count = fhm.platform_count()
	for p in node_count:
		for side: int in [-1, 1]:
			if not fhm.platform_end_open(p, side):
				continue
			var span := fhm.platform_span(p)
			var xe := span.x if side < 0 else span.y
			var ye := fhm.y_at(fhm.platform_end_fh(p, side), xe)
			var land := drop_landing(fhm, xe, ye, side, opts)
			var q := fhm.platform_of(int(land.z))
			if q >= 0 and q != p:
				_add(DROP, p, q, xe, land.x, xe, xe, side * float(opts.drop_speed))
	if bool(opts.can_jump):
		for a in node_count:
			for b in node_count:
				if a != b:
					_try_jump(fhm, a, b)
	_build_csr()
	_build_next_hops()
	_build_transitions()


func _try_jump(fhm: FootholdMap, a: int, b: int) -> void:
	var jh := float(opts.jump_height)
	# Quick reject: b must have some surface above a, and not out of reach everywhere.
	if fhm.plat_y_min[b] >= fhm.plat_y_max[a] or fhm.plat_y_max[b] < fhm.plat_y_min[a] - jh:
		return
	var m := float(opts.margin)
	var sa := fhm.platform_span(a)
	var sb := fhm.platform_span(b)
	var lo := maxf(sa.x, sb.x) + m
	var hi := minf(sa.y, sb.y) - m
	if lo <= hi and _try_vertical_jump(fhm, a, b, lo, hi):
		return
	# Disjoint platforms, or overlapping ones without a clear straight-up hop (a ceiling in the way): a hop with
	# horizontal speed onto b's near end.
	_try_gap_jump(fhm, a, b)


## Overlapping platforms: the longest sampled run of x where b is 1..jump_height px above a with no ceiling between.
## Returns false (no edge added) when there is none.
func _try_vertical_jump(fhm: FootholdMap, a: int, b: int, lo: float, hi: float) -> bool:
	var v := float(opts.jump_speed)
	var jh := minf(float(opts.jump_height), v * v / (2.0 * float(opts.gravity)) - 1.0)
	var stepx := float(opts.sample_step)
	var best_lo := 0.0
	var best_hi := -1.0
	var run_lo := 0.0
	var in_run := false
	var x := lo
	while true:
		var ok := false
		var fa := fhm.platform_fh_at(a, x)
		var fb := fhm.platform_fh_at(b, x)
		if fa >= 0 and fb >= 0:
			var rise := fhm.y_at(fa, x) - fhm.y_at(fb, x)
			ok = rise >= 1.0 and rise <= jh
		if ok and fhm.ceiling_hit(x, fhm.y_at(fa, x), x, fhm.y_at(fb, x)) >= 0:
			ok = false  # a ceiling (the underside of a solid block) between the two surfaces
		if ok:
			if not in_run:
				run_lo = x
				in_run = true
			if x - run_lo > best_hi - best_lo:
				best_lo = run_lo
				best_hi = x
		else:
			in_run = false
		if x >= hi:
			break
		x = minf(x + stepx, hi)
	if best_hi < best_lo:
		return false
	var mid := (best_lo + best_hi) * 0.5
	_add(JUMP, a, b, mid, mid, best_lo, best_hi, 0.0)
	return true


## Non-overlapping platforms: one takeoff point on a, landing `margin` px inside b's near end, arc clear of walls.
func _try_gap_jump(fhm: FootholdMap, a: int, b: int) -> void:
	var m := float(opts.margin)
	var reach := float(opts.jump_reach)
	var jh := float(opts.jump_height)
	var v := float(opts.jump_speed)
	var grav := float(opts.gravity)
	var sa := fhm.platform_span(a)
	var sb := fhm.platform_span(b)
	var side := 1.0 if (sb.x + sb.y) > (sa.x + sa.y) else -1.0
	var x_to := sb.x + m if side > 0.0 else sb.y - m
	if x_to < sb.x or x_to > sb.y:
		return
	var fb := fhm.platform_fh_at(b, x_to)
	if fb < 0:
		return
	var y_to := fhm.y_at(fb, x_to)
	var a_end := sa.y if side > 0.0 else sa.x
	# Takeoff starts gap_inset px inside the end of a nearest to b (never past the landing x; off the line of a wall
	# standing at that end) and moves back by gap_step until the arc is clear.
	var inset := float(opts.gap_inset)
	var x_from := minf(a_end - inset, x_to) if side > 0.0 else maxf(a_end + inset, x_to)
	while absf(x_to - x_from) <= reach and x_from >= sa.x and x_from <= sa.y:
		var fa := fhm.platform_fh_at(a, x_from)
		if fa >= 0:
			var y_from := fhm.y_at(fa, x_from)
			var rise := y_from - y_to
			if rise < 1.0 or rise > jh:
				return
			var disc := v * v - 2.0 * grav * rise
			if disc >= 0.0:
				var t_land := (v + sqrt(disc)) / grav
				var vx := (x_to - x_from) / t_land
				if _arc_clear(fhm, x_from, y_from, vx, -v, grav, t_land):
					_add(JUMP, a, b, x_from, x_to, x_from, x_from, vx)
					return
		x_from -= side * float(opts.gap_step)


func _arc_clear(fhm: FootholdMap, x0: float, y0: float, vx: float, vy: float, grav: float, t_end: float) -> bool:
	var dt := 1.0 / 120.0
	var t := 0.0
	var px := x0
	var py := y0
	while t < t_end:
		t = minf(t + dt, t_end)
		var nx := x0 + vx * t
		var ny := y0 + vy * t + 0.5 * grav * t * t
		if fhm.wall_hit(px, py, nx, ny) >= 0 or fhm.ceiling_hit(px, py, nx, ny) >= 0:
			return false
		px = nx
		py = ny
	return true


func _build_csr() -> void:
	_out_start = PackedInt32Array()
	_out_start.resize(node_count + 1)
	_out_start.fill(0)
	for e in e_kind.size():
		_out_start[e_from[e] + 1] += 1
	for p in node_count:
		_out_start[p + 1] += _out_start[p]
	_out_edges = PackedInt32Array()
	_out_edges.resize(e_kind.size())
	var cur := _out_start.duplicate()
	for e in e_kind.size():
		_out_edges[cur[e_from[e]]] = e
		cur[e_from[e]] += 1


## Air costs and the reverse transitions of the cost field: for each edge f, the edges g landing on f's source platform.
func _build_transitions() -> void:
	var ne := e_kind.size()
	_air.resize(ne)
	for e in ne:
		_air[e] = float(opts.edge_cost) + absf(e_x_to[e] - e_x_from[e])
	_in_start.resize(ne + 1)
	_in_edges.resize(0)
	for f in ne:
		_in_start[f] = _in_edges.size()
		var q := e_from[f]
		for g in ne:
			if e_to[g] == q:
				_in_edges.append(g)
	_in_start[ne] = _in_edges.size()


## BFS from every source over outgoing edges; the first edge of the BFS tree path is the next hop.
func _build_next_hops() -> void:
	var n := node_count
	_next = PackedInt32Array()
	_next.resize(n * n)
	_next.fill(-1)
	_dist = PackedInt32Array()
	_dist.resize(n * n)
	_dist.fill(-1)
	var depth := PackedInt32Array()
	depth.resize(n)
	var first_edge := PackedInt32Array()
	first_edge.resize(n)
	var queue := PackedInt32Array()
	queue.resize(n)
	for s in n:
		first_edge.fill(-2)
		first_edge[s] = -1
		depth[s] = 0
		var head := 0
		var tail := 0
		queue[tail] = s
		tail += 1
		while head < tail:
			var u := queue[head]
			head += 1
			for k in range(_out_start[u], _out_start[u + 1]):
				var e := _out_edges[k]
				var w := e_to[e]
				if first_edge[w] != -2:
					continue
				first_edge[w] = e if u == s else first_edge[u]
				depth[w] = depth[u] + 1
				queue[tail] = w
				tail += 1
		for t in n:
			if first_edge[t] != -2:
				_dist[s * n + t] = depth[t]
			if t != s and first_edge[t] >= 0:
				_next[s * n + t] = first_edge[t]
