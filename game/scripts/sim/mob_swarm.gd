class_name MobSwarm
extends RefCounted
## Every mob of a run as struct-of-arrays with a free list (docs/ARCHITECTURE.md 4.4, docs/GAME_DESIGN.md section 4).
##
## Ground mobs walk along footholds toward the player: on the player's platform straight at the player's x, elsewhere
## along the cheapest NavGraph route to the player's point (NavGraph.prepare_target's travel-cost field: walk to the
## edge's takeoff, then step off it for a "drop" or hop for a "jump"). A mob keeps the edge it chose until another is
## `route_hysteresis` px cheaper (so it does not turn back and forth under a moving player) and reports what is left of
## its way in `route_len` (px; SpawnDirector relocates off-screen mobs that stop closing in). A player standing on a
## low step (at most `reach_y` px above the floor right below it, low_platform()) is within touch of that floor too:
## walkers on it walk to the player's x like mobs on the player's own platform, and walkers' routes may end there
## (jumpers hop onto the step instead). A drop
## is the same for every mob whatever its walk speed: from the platform end it drifts at the edge's `vx` until
## NavGraph `drop_probe` px past the end, then falls straight down, which is exactly the trajectory
## NavGraph.drop_landing used to pick the edge's target, so a drop edge always lands where the graph says. Walls stop
## walking (and turn a patrolling mob around). A mob with no route patrols its platform, turning at the ends. In the
## air mobs fall with Physics.img gravity up to fallSpeed and land on floors from above; walls stop horizontal motion
## and ceilings upward motion; outside a drop's drift a descending mob never drifts from a column with a floor below
## into one without (so a hop toward a narrow ledge lands on it instead of overshooting into the void); a mob that
## still ends up below the world bounds is recycled silently (`lost_count`). Flying mobs move straight at the player.
## New mobs fade in (regen) and stand still meanwhile; a hit reaching canonical `pushed` stuns (HIT) and pushes the
## mob along its platform; weaker hits only damage HP. A
## killed mob stays in DIE for its die1 time, then its slot is freed for reuse.
##
## step(dt, ctx) takes a Dictionary:
##   fhm: FootholdMap (required)            nav: NavGraph for walkers        nav_jump: NavGraph for jumpers (default nav)
##   target: Vector2 (player position)       target_fh: int (player foothold, -1 = find the floor below target)
##   bounds: Rect2 (MapBounds; default foothold box + 300 above/100 below)
##   speed_mult: float (stage speed multiplier, default 1)   physics: PhysicsConstants (default v83)
##   boss_actions: action_snapshot() arrays; nonempty actions hold grounded movement and captured facing
## Both graphs must be built with the same gravity/fall_speed/jump_speed as `physics`.
## `kinds` must hold the MobKind of every `kind` index used (RunWorld shares its mob_kinds array). Their fields are
## re-read at every step(), so replacing or editing a kind (elite or speed overrides) takes effect on the next tick.

const STAND := 0
const MOVE := 1
const JUMP := 2
const HIT := 3
const DIE := 4
const FREE := 5

## Tunables (keys of the `tuning` Dictionary given to _init).
const TUNING_DEFAULTS := {
	"regen_time": 0.3,  # tier C: fade-in time of a new mob (HeavenClient fades at a similar rate)
	"push_px": 12.0,  # tier C: how far a hit with damage >= pushed slides the mob
	"stop_dist": 2.0,  # tier C: ours, a mob on the player's platform stops this close to the player's x
	"route_hysteresis": 96.0,  # tier C: ours, a mob switches to another route only when it is this many px cheaper
	"reach_y": 40.0,  # tier C: ours, a floor at most this far below the player's feet counts as the player's (touch reach)
	"fly_bob_px": 2.0,  # tier C: ours, small vertical flyer bob independent of pursuit
	"fly_bob_period": 1.2,  # tier C: ours, seconds per flyer bob
}

var kind := PackedInt32Array()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var hp := PackedInt32Array()
var max_hp := PackedInt32Array()
var state := PackedInt32Array()
## Seconds in the current state / current animation (the latter restarts when the shown stance changes).
var state_t := PackedFloat32Array()
var anim_t := PackedFloat32Array()
## Foothold stood on (-1 in the air) and its platform.
var fh := PackedInt32Array()
var platform := PackedInt32Array()
## -1 left (WZ default), 1 right.
var facing := PackedInt32Array()
## Regen fade-in 0 -> 1.
var alpha := PackedFloat32Array()
## BossDirector drives fade-out while movement/regen is suspended; respawning clears this flag.
var fading_out := PackedByteArray()
## 1 while the mob is alive (not DIE/FREE): the mask for SpatialHash.rebuild and targeting.
var active := PackedByteArray()
## Travel cost (px) left to the player at the last grounded step: the walk on the player's platform, else the chosen
## route's (NavGraph.route_cost); INF = no way there (or not computed yet). Kept while airborne.
var route_len := PackedFloat32Array()

var kinds: Array = []
var fhm: FootholdMap
var tuning: Dictionary
## Mobs recycled because they fell out of the world (should stay 0 on sane maps).
var lost_count := 0

var _free := PackedInt32Array()
var _alive := 0
var _hi := 0
var _pending := false
## x where a drop's step-off drift ends (INF = not drifting).
var _stop_x := PackedFloat32Array()
## The NavGraph edge the mob is heading for (-1 = none yet; reset on landing).
var _route_e := PackedInt32Array()
var _k_speed := PackedFloat32Array()
var _k_jump := PackedByteArray()
var _k_fly := PackedByteArray()
var _k_die := PackedFloat32Array()
var _k_hit := PackedFloat32Array()
## The bob already included in y; subtract it before steering so oscillation never accumulates drift.
var _fly_bob := PackedFloat32Array()


func _init(capacity: int = 256, p_kinds: Array = [], p_tuning: Dictionary = {}) -> void:
	kinds = p_kinds
	tuning = TUNING_DEFAULTS.duplicate()
	for k: String in p_tuning:
		if tuning.has(k):
			tuning[k] = p_tuning[k]
	_grow(maxi(1, capacity))


## The platform of the floor right below the player's feet other than its own platform tp, when that floor is at most
## reach_y px below them (the player stands on a low step walkers on that floor can touch it from); -1 otherwise.
static func low_platform(m: FootholdMap, target: Vector2, tp: int, reach_y: float) -> int:
	var f := m.find_below(target.x, target.y + 0.5, -1, tp)
	if f < 0 or m.y_at(f, target.x) - target.y > reach_y:
		return -1
	return m.platform_of(f)


## Number of slots (live, dying and free); iterate 0..capacity()-1 and skip FREE.
func capacity() -> int:
	return state.size()


## Number of live mobs (not dying, not free).
func alive_count() -> int:
	return _alive


## Adds a mob of kind index `k` standing on foothold `f` (or falling from (px, py) when f = -1). hp <= 0 uses the
## kind's max_hp. Returns the slot. The arrays grow when full.
func spawn(k: int, px: float, py: float, f: int, p_hp: int = 0) -> int:
	if _free.is_empty():
		_grow(capacity() * 2)
	var i := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	var h := p_hp
	if h <= 0:
		h = kinds[k].max_hp if k >= 0 and k < kinds.size() else 1
	kind[i] = k
	x[i] = px
	y[i] = py
	_fly_bob[i] = 0.0
	vx[i] = 0.0
	vy[i] = 0.0
	hp[i] = h
	max_hp[i] = h
	state[i] = STAND if f >= 0 else JUMP
	state_t[i] = 0.0
	anim_t[i] = 0.0
	fh[i] = f
	platform[i] = -1
	facing[i] = -1
	alpha[i] = 0.0
	fading_out[i] = 0
	active[i] = 1
	_stop_x[i] = INF
	_route_e[i] = -1
	route_len[i] = INF
	_alive += 1
	_hi = maxi(_hi, i + 1)
	if f >= 0:
		if fhm != null:
			_snap(i, f)
		else:
			_pending = true
	return i


## Removes mob i at once and silently (no death animation; RunWorld recycles far-off mobs with it). False when the
## slot is already free.
func despawn(i: int) -> bool:
	if i < 0 or i >= capacity() or state[i] == FREE:
		return false
	if state[i] != DIE:
		_alive -= 1
	_release(i)
	return true


## Damages mob i by dmg from direction dir (-1/1: the way the blow pushes). Returns true when this hit killed it.
## Dying or free slots ignore hits. Bosses ignore stun/push; normal mobs require damage >= canonical pushed.
func apply_hit(i: int, dmg: int, dir: int) -> bool:
	if i < 0 or i >= capacity() or state[i] == DIE or state[i] == FREE:
		return false
	var k := kind[i]
	var mk: MobKind = kinds[k] if k >= 0 and k < kinds.size() else null
	hp[i] -= dmg
	if hp[i] <= 0:
		hp[i] = 0
		state[i] = DIE
		state_t[i] = 0.0
		anim_t[i] = 0.0
		if fh[i] >= 0:
			vx[i] = 0.0
		active[i] = 0
		_alive -= 1
		return true
	if mk != null and (mk.boss or mk.no_flinch or dmg < mk.pushed):
		return false
	state[i] = HIT
	state_t[i] = 0.0
	anim_t[i] = 0.0
	if dir != 0:
		facing[i] = -signi(dir)
	if fh[i] >= 0:
		var stun := mk.hit_time if mk != null else MobKind.DEFAULT_HIT_TIME
		vx[i] = signf(dir) * float(tuning.push_px) / maxf(stun, 0.01)
	return false


## Advances every mob by dt seconds (see the class comment for ctx).
func step(dt: float, ctx: Dictionary) -> void:
	fhm = ctx.fhm
	var m: FootholdMap = fhm
	if _pending:
		_pending = false
		for i in _hi:
			if state[i] != FREE and fh[i] >= 0 and platform[i] < 0:
				_snap(i, fh[i])
	_sync_kinds()
	var nav_w: NavGraph = ctx.get("nav")
	var nav_j: NavGraph = ctx.get("nav_jump", nav_w)
	var fb := m.bounds()
	var bounds: Rect2 = ctx.get("bounds", Rect2(fb.position.x, fb.position.y - 300.0, fb.size.x, fb.size.y + 400.0))
	var phys: PhysicsConstants = ctx.get("physics", null)
	var grav := phys.gravity_acc if phys != null else 2000.0
	var fall := phys.fall_speed if phys != null else 670.0
	var target: Vector2 = ctx.get("target", Vector2.ZERO)
	var tfh: int = ctx.get("target_fh", -1)
	var tp := m.platform_of(tfh) if tfh >= 0 else m.platform_of(m.find_below(target.x, target.y))
	var smult := float(ctx.get("speed_mult", 1.0))
	var regen := maxf(0.001, float(tuning.regen_time))
	var stop := float(tuning.stop_dist)
	var lim := Vector2(maxf(fb.position.x, bounds.position.x), minf(fb.end.x, bounds.end.x))
	var bottom := bounds.end.y
	var tx := target.x
	# Local handles to the hot read-only arrays.
	var fx1 := m.x1
	var fy1 := m.y1
	var fx2 := m.x2
	var fy2 := m.y2
	var fnext := m.next
	var fprev := m.prev
	var px1 := m.plat_x1
	var px2 := m.plat_x2
	var fwall := m.floor_wall
	# Travel-cost fields toward the player's point for both movement classes (see NavGraph.prepare_target).
	var cs_w := PackedInt32Array()
	var ce_w := PackedInt32Array()
	var co_w := PackedFloat32Array()
	var tk_w := PackedFloat32Array()
	var cs_j := PackedInt32Array()
	var ce_j := PackedInt32Array()
	var co_j := PackedFloat32Array()
	var tk_j := PackedFloat32Array()
	var ef_w := PackedInt32Array()
	var ef_j := PackedInt32Array()
	var lowp := low_platform(m, target, tp, float(tuning.reach_y)) if tp >= 0 else -1
	if nav_w != null and tp >= 0:
		nav_w.prepare_target(tp, tx, lowp)
		cs_w = nav_w.cand_start
		ce_w = nav_w.cand_edges
		co_w = nav_w.cost
		tk_w = nav_w.take
		ef_w = nav_w.e_from
	if nav_j != null and tp >= 0:
		nav_j.prepare_target(tp, tx)
		cs_j = nav_j.cand_start
		ce_j = nav_j.cand_edges
		co_j = nav_j.cost
		tk_j = nav_j.take
		ef_j = nav_j.e_from
	var hyst := float(tuning.route_hysteresis)
	var action_state: Dictionary = ctx.get("boss_actions", {})
	var actions: PackedStringArray = action_state.get("actions", PackedStringArray())
	var action_facings: PackedInt32Array = action_state.get("facings", PackedInt32Array())
	for i in _hi:
		var st := state[i]
		if st == FREE:
			continue
		var k := kind[i]
		var t := state_t[i] + dt
		state_t[i] = t
		anim_t[i] += dt
		if st == DIE:
			if fh[i] < 0 and _k_fly[k] == 0:
				_air(i, dt, m, grav, fall, lim, bottom)
			if state[i] == DIE and t >= _k_die[k]:
				_release(i)
			continue
		if fading_out[i] != 0:
			continue
		if alpha[i] < 1.0:
			alpha[i] = minf(1.0, alpha[i] + dt / regen)
		if i < actions.size() and actions[i] != "" and fh[i] >= 0:
			# tier C: an authored boss stance holds its ground anchor; airborne art comes from canonical origins.
			vx[i] = 0.0
			if i < action_facings.size():
				facing[i] = action_facings[i]
			continue
		if _k_fly[k] != 0:
			_fly(i, dt, _k_speed[k] * smult, target, bounds)
			route_len[i] = Vector2(x[i], y[i]).distance_to(target)
			continue
		var f := fh[i]
		if f < 0:
			_air(i, dt, m, grav, fall, lim, bottom)
			continue
		if st == HIT:
			if t >= _k_hit[k]:
				vx[i] = 0.0
				_set_state(i, MOVE)
			else:
				_slide(i, f, x[i] + vx[i] * dt, m)
			continue
		if alpha[i] < 1.0:
			continue
		var p := platform[i]
		var cx := x[i]
		var spd := _k_speed[k] * smult
		var want := 0
		var wander := false
		if p == tp or (p == lowp and _k_jump[k] == 0):
			var d := clampf(tx, px1[p], px2[p]) - cx
			route_len[i] = absf(tx - cx)
			if d > stop:
				want = 1
			elif d < -stop:
				want = -1
		else:
			var jumper := _k_jump[k] != 0
			var cs := cs_j if jumper else cs_w
			var e := -1
			var take := cx
			var best_d := INF
			if p >= 0 and p + 1 < cs.size():
				# The cheapest walk to an edge's take + its cost (NavGraph.best_edge, inlined; a straight-up hop takes
				# off at its take, the point of its range that suits the route on); the edge chosen before stays unless
				# this one is route_hysteresis px cheaper.
				var ce := ce_j if jumper else ce_w
				var co := co_j if jumper else co_w
				var etk := tk_j if jumper else tk_w
				for c in range(cs[p], cs[p + 1]):
					var ec := ce[c]
					var tk := etk[ec]
					var dd := absf(tk - cx) + co[ec]
					if dd < best_d:
						best_d = dd
						e = ec
						take = tk
				var r := _route_e[i]
				# r is still a candidate when it leaves p and still reaches the target (cand_edges of p: exactly
				# those out-edges of p with a finite cost).
				if r >= 0 and r != e and e >= 0 and r < co.size() and co[r] < INF \
						and (ef_j if jumper else ef_w)[r] == p:
					var tk := etk[r]
					var dd := absf(tk - cx) + co[r]
					if dd <= best_d + hyst:
						best_d = dd
						e = r
						take = tk
				if r != e:
					_route_e[i] = e
			route_len[i] = best_d
			if e < 0:
				wander = true
				want = facing[i]
			else:
				var nav := nav_j if jumper else nav_w
				var d := take - cx
				if absf(d) > spd * dt + 0.001:
					want = 1 if d > 0.0 else -1
				elif nav.e_kind[e] == NavGraph.DROP:
					# Step off the platform end: drift at the edge's vx until drop_probe px past it, then fall
					# (the trajectory NavGraph.drop_landing simulated, whatever this mob's walk speed).
					var side := 1 if nav.e_vx[e] > 0.0 else -1
					x[i] = take
					y[i] = m.y_at(m.platform_end_fh(p, side), take)
					vx[i] = nav.e_vx[e]
					vy[i] = 0.0
					_stop_x[i] = take + side * float(nav.opts.drop_probe)
					fh[i] = -1
					facing[i] = side
					_set_state(i, JUMP)
					continue
				else:
					# The takeoff may be on a neighbouring foothold of the chain: take its surface y.
					var tf := f
					while take > fx2[tf] and fnext[tf] >= 0 and fx1[fnext[tf]] < fx2[fnext[tf]]:
						tf = fnext[tf]
					while take < fx1[tf] and fprev[tf] >= 0 and fx1[fprev[tf]] < fx2[fprev[tf]]:
						tf = fprev[tf]
					x[i] = take
					y[i] = fy1[tf] + (fy2[tf] - fy1[tf]) * (take - fx1[tf]) / (fx2[tf] - fx1[tf])
					vx[i] = nav.e_vx[e]
					vy[i] = -float(nav.opts.jump_speed)
					_stop_x[i] = INF
					fh[i] = -1
					if vx[i] != 0.0:
						facing[i] = 1 if vx[i] > 0.0 else -1
					_set_state(i, JUMP)
					continue
		if want == 0:
			if st != STAND:
				_set_state(i, STAND)
			continue
		facing[i] = want
		var nx := cx + want * spd * dt
		# Walls: only footholds with a wall inside their span, or a step onto the next foothold, can meet one.
		if fwall[f] != 0 or nx > fx2[f] or nx < fx1[f]:
			var w := m.wall_hit(cx, y[i], nx, y[i])
			if w >= 0:
				nx = fx1[w] - want * 0.01
				if wander:
					facing[i] = -want
		if want > 0:
			while nx > fx2[f]:
				var g := fnext[f]
				if g >= 0 and fx1[g] < fx2[g]:
					f = g
					continue
				nx = fx2[f] - 0.01  # stay off the line of a wall standing at the end
				if wander:
					facing[i] = -1
				break
		else:
			while nx < fx1[f]:
				var g := fprev[f]
				if g >= 0 and fx1[g] < fx2[g]:
					f = g
					continue
				nx = fx1[f] + 0.01
				if wander:
					facing[i] = 1
				break
		if nx < lim.x or nx > lim.y:
			nx = clampf(nx, lim.x, lim.y)
			if wander:
				facing[i] = -want
		x[i] = nx
		y[i] = fy1[f] + (fy2[f] - fy1[f]) * (nx - fx1[f]) / (fx2[f] - fx1[f])
		fh[i] = f
		if st != MOVE:
			_set_state(i, MOVE)


## Ballistic step of an airborne mob: gravity, a drop's drift stop, walls, the void guard, ceilings, landing,
## recycling below the world. NavGraph.drop_landing replays this for drops; keep the two in step.
func _air(i: int, dt: float, m: FootholdMap, grav: float, fall: float, lim: Vector2, bottom: float) -> void:
	var ox := x[i]
	var oy := y[i]
	var vy0 := vy[i]
	var vy1 := minf(vy0 + grav * dt, fall)
	vy[i] = vy1
	var nx := ox + vx[i] * dt
	var ny := oy + (vy0 + vy1) * 0.5 * dt
	var stop := _stop_x[i]
	var drifting := stop != INF
	if drifting and vx[i] != 0.0 and (nx - stop) * vx[i] >= 0.0:
		nx = stop
		vx[i] = 0.0
	if nx != ox:
		var w := m.wall_hit(ox, oy, nx, ny)
		if w >= 0:
			nx = m.x1[w] - signf(nx - ox) * 0.01
			vx[i] = 0.0
		# The void guard is not for a drop's drift: drop_landing already checked where that ends.
		if not drifting and vy1 > 0.0 and m.find_below(nx, oy) < 0 and m.find_below(ox, oy) >= 0:
			nx = ox
			vx[i] = 0.0
		if nx < lim.x or nx > lim.y:
			nx = clampf(nx, lim.x, lim.y)
			vx[i] = 0.0
	if ny < oy:
		var c := m.ceiling_hit(ox, oy, nx, ny)
		if c >= 0:
			ny = m.y_at(c, nx) + FootholdMap.EPS  # head bump
			vy[i] = 0.0
	if ny > oy:
		var g := m.find_landing(ox, oy, nx, ny)
		if g >= 0:
			x[i] = nx
			y[i] = m.y_at(g, nx)
			vx[i] = 0.0
			vy[i] = 0.0
			_stop_x[i] = INF
			_route_e[i] = -1
			fh[i] = g
			platform[i] = m.platform[g]
			if state[i] == JUMP:
				_set_state(i, MOVE)
			return
	if ny > bottom:
		lost_count += 1
		if state[i] != DIE:
			_alive -= 1
		_release(i)
		return
	x[i] = nx
	y[i] = ny


## Flying mobs steer through footholds toward the target, with a small non-drifting bob inside the bounds.
func _fly(i: int, dt: float, spd: float, target: Vector2, bounds: Rect2) -> void:
	if state[i] == HIT:
		if state_t[i] >= _k_hit[kind[i]]:
			_set_state(i, MOVE)
		return
	if alpha[i] < 1.0:
		return
	var base := Vector2(x[i], y[i] - _fly_bob[i])
	var d := target - base
	var len := d.length()
	if len <= float(tuning.stop_dist):
		if state[i] != STAND:
			_set_state(i, STAND)
	else:
		base += d / len * minf(spd * dt, len)
		if absf(d.x) > 0.5:
			facing[i] = 1 if d.x > 0.0 else -1
		if state[i] != MOVE:
			_set_state(i, MOVE)
	base.x = clampf(base.x, bounds.position.x, bounds.end.x)
	base.y = clampf(base.y, bounds.position.y, bounds.end.y)
	var bob := float(tuning.fly_bob_px) * sin(anim_t[i] * TAU / maxf(0.01, float(tuning.fly_bob_period)))
	x[i] = base.x
	y[i] = clampf(base.y + bob, bounds.position.y, bounds.end.y)
	_fly_bob[i] = y[i] - base.y


## Moves a grounded mob along its platform to nx, stopping at walls and the platform ends (used for hit pushes).
func _slide(i: int, f: int, nx: float, m: FootholdMap) -> void:
	if m.floor_wall[f] != 0 or nx > m.x2[f] or nx < m.x1[f]:
		var w := m.wall_hit(x[i], y[i], nx, y[i])
		if w >= 0:
			nx = m.x1[w] - signf(nx - x[i]) * 0.01
	var guard := 0
	while nx > m.x2[f] and guard < 256:
		var g := m.next[f]
		if g < 0 or not m.is_floor(g):
			nx = m.x2[f] - 0.01
			break
		f = g
		guard += 1
	while nx < m.x1[f] and guard < 256:
		var g := m.prev[f]
		if g < 0 or not m.is_floor(g):
			nx = m.x1[f] + 0.01
			break
		f = g
		guard += 1
	x[i] = nx
	y[i] = m.y_at(f, nx)
	fh[i] = f


func _snap(i: int, f: int) -> void:
	if f >= fhm.count() or not fhm.is_floor(f):
		fh[i] = -1  # not something to stand on: fall from here
		state[i] = JUMP
		return
	var px := clampf(x[i], fhm.x1[f], fhm.x2[f])
	x[i] = px
	y[i] = fhm.y_at(f, px)
	platform[i] = fhm.platform_of(f)


func _set_state(i: int, s: int) -> void:
	if state[i] != s:
		anim_t[i] = 0.0
	state[i] = s
	state_t[i] = 0.0


func _release(i: int) -> void:
	state[i] = FREE
	active[i] = 0
	fh[i] = -1
	platform[i] = -1
	_stop_x[i] = INF
	_free.append(i)
	while _hi > 0 and state[_hi - 1] == FREE:
		_hi -= 1


## Copies the per-kind fields the hot loop reads into packed arrays (every step: kinds may be replaced or edited).
func _sync_kinds() -> void:
	var n := kinds.size()
	_k_speed.resize(n)
	_k_jump.resize(n)
	_k_fly.resize(n)
	_k_die.resize(n)
	_k_hit.resize(n)
	for k in n:
		var mk: MobKind = kinds[k]
		_k_speed[k] = mk.move_speed
		_k_jump[k] = 1 if mk.can_jump else 0
		_k_fly[k] = 1 if mk.flies else 0
		_k_die[k] = mk.die_time
		_k_hit[k] = mk.hit_time


func _grow(n: int) -> void:
	var old := capacity()
	if n <= old:
		return
	kind.resize(n)
	x.resize(n)
	y.resize(n)
	vx.resize(n)
	vy.resize(n)
	hp.resize(n)
	max_hp.resize(n)
	state.resize(n)
	state_t.resize(n)
	anim_t.resize(n)
	_fly_bob.resize(n)
	fh.resize(n)
	platform.resize(n)
	facing.resize(n)
	alpha.resize(n)
	fading_out.resize(n)
	active.resize(n)
	_stop_x.resize(n)
	_route_e.resize(n)
	route_len.resize(n)
	for i in range(n - 1, old - 1, -1):
		state[i] = FREE
		active[i] = 0
		_stop_x[i] = INF
		_route_e[i] = -1
		route_len[i] = INF
		fh[i] = -1
		platform[i] = -1
		facing[i] = -1
		_free.append(i)
