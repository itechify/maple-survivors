class_name PlayerMotion
extends RefCounted
## Player movement driven by Map.wz/Physics.img (docs/GAME_DESIGN.md section 3).
##
## Model (tier B, re-implemented from the prose description of NoLifeStory's CVecCtrl in docs/research/prior-art.md):
## on a floor the speed along the foothold accelerates at walkForce/mass up to walkSpeed x speed%, decelerates at
## walkDrag/mass, and footholds steeper than |sin| 0.9 slip; a jump sets vy = -jumpSpeed x jump% and clamps a held
## direction's vx into [0.8, 1] x max walk speed; in the air gravity pulls at gravityAcc up to fallSpeed and horizontal
## control is ~9 px/s; landing clamps vy to 162.5 and projects the velocity onto the foothold. Down + Jump on a
## foothold without cantThrough/forbidFallDown with a floor below jumps at -196 px/s and ignores the current platform
## until landing. Walls (vertical footholds rising above the feet) block; ceilings (x1 > x2) stop upward motion
## (tier B, prior-art.md 1b "nudge down"); the map's horizontal limits clamp; falling below the MapBounds bottom puts
## the player back on the nearest floor (EV_FELL_OUT).
## Unlike NoLifeStory there is no vertical float drag in the air, so the jump apex is 555^2/(2*2000) = 77 px as in
## GAME_DESIGN. Positions integrate with the exact constant-acceleration (trapezoid) step, 2 sub-steps per 1/60 tick.
##
## Ladders/ropes (tier C): Up within `ladder_reach` px of a rope whose span covers the hands (feet - ladder_grab_up)
## grabs it (also in the air); Down on the ground grabs one whose span covers feet + ladder_grab_down; climbing moves
## at climb_speed; Jump + a direction leaves; climbing past the top steps onto the floor there when `uf` = 1; climbing
## past the bottom lets go.

## States.
const ST_STAND := 0
const ST_WALK := 1
const ST_PRONE := 2
const ST_AIR := 3
const ST_LADDER := 4

## Event flags returned by step().
const EV_JUMP := 1
const EV_LAND := 2
const EV_DOWN_JUMP := 4
const EV_GRAB := 8
const EV_LADDER_EXIT := 16
const EV_WALK_OFF := 32
const EV_WALL := 64
## Fell below the MapBounds bottom (no floor caught the player): put back standing on the nearest floor.
const EV_FELL_OUT := 128

## Tunables (keys of the `tuning` Dictionary given to _init). All tier C (ours / HeavenClient as described in
## docs/research/prior-art.md) unless stated.
const TUNING_DEFAULTS := {
	"substeps": 2,  # tier C: ours, 2 per 1/60 s tick
	"climb_speed": 100.0,  # tier C: ours (HeavenClient uses 125)
	"ladder_reach": 10.0,  # tier C: ours
	"ladder_grab_up": 50.0,  # tier C: ours, how far above the feet the hands reach a ladder
	"ladder_grab_down": 10.0,  # tier C: ours, probe below the feet when grabbing downwards
	"ladder_top_probe": 24.0,  # tier C: ours, how far above a ladder top the exit floor may be
	"ladder_top_snap": 4.0,  # tier C: ours, how far below a ladder top the exit floor may be
	"ladder_regrab": 0.25,  # tier C: ours, seconds before another grab after leaving a ladder
	"ladder_jump_mult": 0.6667,  # tier C: HeavenClient exit jump vy = jumpforce / 1.5
	"knockback_speed": 187.5,  # tier C: HeavenClient
	"knockback_hop": 200.0,  # tier C: ours, the small hop when hit
	"knockback_lock": 0.3,  # tier C: HeavenClient, seconds without input
	"alert_time": 2.0,  # tier C: ours, seconds of "alert" stance after a hit
	"down_jump_max": 600.0,  # tier C: HeavenClient, a floor must be within this far below to down-jump
	"place_snap": 1.0,  # tier C: ours, place() snaps onto a floor at most this far below (else the player falls)
}

var pos := Vector2.ZERO
var vel := Vector2.ZERO
## Foothold stood on, -1 in the air or on a ladder.
var fh := -1
## Ladder/rope index while climbing, else -1.
var ladder := -1
## -1 left, 1 right.
var facing := 1
var state := ST_AIR
## MapleStory speed and jump stats in percent (100 = base).
var speed_stat := 100
var jump_stat := 100

## Body stances played while standing and walking: the held weapon's (WeaponInfo.stand_stance / walk_stance); a
## two-handed weapon stands with "stand2". Set by whoever owns the weapon (RunWorld, the Free Market).
var stand_stance := "stand1"
var walk_stance := "walk1"

var constants: PhysicsConstants
var tuning: Dictionary
## Seconds left of the post-hit input lock / alert stance / ladder re-grab cooldown.
var knock_t := 0.0
var alert_t := 0.0
var ladder_cd := 0.0
## Platform ignored for landing during a down-jump (-1 = none).
var down_jump_platform := -1

var _on_rope := false
var _input_dir := 0
var _input_down := false


func _init(p_constants: PhysicsConstants = null, p_tuning: Dictionary = {}) -> void:
	constants = p_constants if p_constants != null else PhysicsConstants.v83_defaults()
	tuning = TUNING_DEFAULTS.duplicate()
	for k: String in p_tuning:
		if tuning.has(k):
			tuning[k] = p_tuning[k]


## Puts the player at `p` at rest. Snaps onto a floor at most `place_snap` px below, else starts in the air.
func place(p: Vector2, fhm: FootholdMap) -> void:
	pos = p
	vel = Vector2.ZERO
	ladder = -1
	down_jump_platform = -1
	fh = -1
	state = ST_AIR
	if fhm == null:
		return
	var f := fhm.find_below(p.x, p.y)
	if f >= 0 and fhm.y_at(f, p.x) - p.y <= float(tuning.place_snap):
		fh = f
		pos.y = fhm.y_at(f, p.x)
		state = ST_STAND


## Queries a grounded blink destination without changing motion; climbing cannot teleport.
func teleport_destination(direction: Vector2, distance: float, fhm: FootholdMap, bounds: Rect2) -> Dictionary:
	if ladder >= 0 or state == ST_LADDER:
		return {}
	return fhm.teleport_destination(pos, direction, distance, bounds)


## Advances by dt seconds (normally 1/60) in `substeps` sub-steps. `ladders` may be null; `bounds` is the MapBounds
## rect (an empty Rect2 means only the foothold extent limits x). Returns EV_* flags of what happened.
func step(dt: float, input: MoveInput, fhm: FootholdMap, ladders: LadderSet, bounds: Rect2) -> int:
	var flags := 0
	var n := maxi(1, int(tuning.substeps))
	var h := dt / n
	var lim := _x_limits(fhm, bounds)
	for s in n:
		flags |= _substep(h, input, s == 0, fhm, ladders, lim)
		knock_t = maxf(0.0, knock_t - h)
		ladder_cd = maxf(0.0, ladder_cd - h)
	alert_t = maxf(0.0, alert_t - dt)
	if bounds.has_area() and pos.y > bounds.end.y:
		flags |= EV_FELL_OUT
		_recover(fhm, bounds.end.y)
	var locked := knock_t > 0.0
	_input_dir = 0 if locked else input.dir()
	_input_down = input.down and not locked
	if ladder >= 0:
		state = ST_LADDER
	elif fh < 0:
		state = ST_AIR
	elif _input_down:
		state = ST_PRONE
	elif _input_dir != 0:
		state = ST_WALK
	else:
		state = ST_STAND
	return flags


## Hit reaction: pushed away in `dir` (-1/1) with a small hop, input locked for knockback_lock s. On a ladder only
## the lock and alert apply.
func knockback(dir: int) -> void:
	knock_t = float(tuning.knockback_lock)
	alert_t = float(tuning.alert_time)
	if ladder >= 0:
		return
	vel = Vector2(signf(dir) * float(tuning.knockback_speed), -float(tuning.knockback_hop))
	fh = -1
	down_jump_platform = -1
	state = ST_AIR


## Body stance name in Character.wz/00002000.img to play now ("dead" is decided by the caller).
func stance() -> String:
	match state:
		ST_LADDER:
			return "rope" if _on_rope else "ladder"
		ST_AIR:
			return "jump"
		ST_PRONE:
			return "prone"
		ST_WALK:
			return walk_stance
	return "alert" if alert_t > 0.0 else stand_stance


## Current maximum walk speed in px/s (walkSpeed x speed%).
func max_walk_speed() -> float:
	return constants.walk_speed * speed_stat / 100.0


## Fell out of the world: stand on the floor point nearest to (pos.x, bottom). On a map without floors the player
## just stays at the bottom edge.
func _recover(fhm: FootholdMap, bottom: float) -> void:
	var best := -1
	var best_d := INF
	var best_x := pos.x
	for f in fhm.count():
		if not fhm.is_floor(f):
			continue
		var cx := clampf(pos.x, fhm.x1[f], fhm.x2[f])
		var d := Vector2(cx - pos.x, fhm.y_at(f, cx) - bottom).length_squared()
		if d < best_d:
			best_d = d
			best = f
			best_x = cx
	ladder = -1
	down_jump_platform = -1
	vel = Vector2.ZERO
	if best < 0:
		pos.y = bottom
		return
	fh = best
	pos = Vector2(best_x, fhm.y_at(best, best_x))


func _x_limits(fhm: FootholdMap, bounds: Rect2) -> Vector2:
	var fb := fhm.bounds()
	var lo := fb.position.x
	var hi := fb.end.x
	if bounds.has_area():
		lo = maxf(lo, bounds.position.x)
		hi = minf(hi, bounds.end.x)
	return Vector2(lo, hi)


func _substep(h: float, input: MoveInput, first: bool, fhm: FootholdMap, ladders: LadderSet, lim: Vector2) -> int:
	var locked := knock_t > 0.0
	var dir := 0 if locked else input.dir()
	var up := input.up and not locked
	var down := input.down and not locked
	var jump_pressed := input.jump_pressed and first and not locked
	var jump_held := input.jump_held and not locked
	if ladder >= 0:
		return _ladder_substep(h, dir, up, down, jump_pressed, fhm, ladders)
	if ladders != null and ladder_cd <= 0.0 and (up or (down and fh >= 0)):
		var probe := pos.y - float(tuning.ladder_grab_up) if up else pos.y + float(tuning.ladder_grab_down)
		var l := ladders.find_grab(pos.x, probe, float(tuning.ladder_reach))
		if l >= 0:
			_grab(l, ladders)
			return EV_GRAB
	if fh >= 0:
		return _ground_substep(h, dir, down, jump_pressed, jump_held, fhm, lim)
	return _air_substep(h, dir, fhm, lim)


func _grab(l: int, ladders: LadderSet) -> void:
	ladder = l
	_on_rope = ladders.is_ladder[l] == 0
	pos = Vector2(ladders.x[l], clampf(pos.y, ladders.y1[l], ladders.y2[l]))
	vel = Vector2.ZERO
	fh = -1
	down_jump_platform = -1


func _ladder_substep(h: float, dir: int, up: bool, down: bool, jump_pressed: bool, fhm: FootholdMap,
		ladders: LadderSet) -> int:
	var l := ladder
	if jump_pressed and dir != 0:
		ladder = -1
		ladder_cd = float(tuning.ladder_regrab)
		facing = dir
		vel = Vector2(dir * max_walk_speed(), -constants.jump_speed * jump_stat / 100.0 * float(tuning.ladder_jump_mult))
		return EV_JUMP | EV_LADDER_EXIT
	var v := 0.0
	if up:
		v = -float(tuning.climb_speed)
	elif down:
		v = float(tuning.climb_speed)
	vel = Vector2(0.0, v)
	var ny := pos.y + v * h
	var top := ladders.y1[l]
	var bottom := ladders.y2[l]
	if ny < top:
		ny = top
		if ladders.uf[l] != 0:
			var f := fhm.find_below(pos.x, top - float(tuning.ladder_top_probe))
			if f >= 0 and fhm.y_at(f, pos.x) <= top + float(tuning.ladder_top_snap):
				ladder = -1
				ladder_cd = float(tuning.ladder_regrab)
				fh = f
				pos.y = fhm.y_at(f, pos.x)
				vel = Vector2.ZERO
				return EV_LADDER_EXIT | EV_LAND
	elif ny > bottom:
		ladder = -1
		ladder_cd = float(tuning.ladder_regrab)
		pos.y = bottom
		vel = Vector2.ZERO
		return EV_LADDER_EXIT
	pos.y = ny
	return 0


func _ground_substep(h: float, dir: int, down: bool, jump_pressed: bool, jump_held: bool, fhm: FootholdMap,
		lim: Vector2) -> int:
	var f := fh
	if dir != 0:
		facing = dir
	if down and jump_pressed:
		if fhm.cant_through[f] == 0 and fhm.forbid_fall_down[f] == 0:
			var p := fhm.platform_of(f)
			var below := fhm.find_below(pos.x, pos.y, f, p)
			if below >= 0 and fhm.y_at(below, pos.x) - pos.y <= float(tuning.down_jump_max):
				down_jump_platform = p
				vel = Vector2(0.0, -constants.jump_speed * PhysicsConstants.DOWN_JUMP_MULT)
				fh = -1
				return EV_DOWN_JUMP
	elif (jump_pressed or jump_held) and not down:
		_jump(dir, f, fhm)
		return EV_JUMP
	var walk_dir := 0 if down else dir
	var fx := fhm.x2[f] - fhm.x1[f]
	var fy := fhm.y2[f] - fhm.y1[f]
	var flen := sqrt(fx * fx + fy * fy)
	var tx := fx / flen
	var ty := fy / flen
	var mvr := vel.x * tx + vel.y * ty
	var maxf := max_walk_speed()
	if absf(ty) > PhysicsConstants.WALK_SLANT:
		mvr = move_toward(mvr, constants.slip_speed * signf(ty), constants.slip_force / PhysicsConstants.MASS * h)
	elif walk_dir != 0:
		if mvr * walk_dir < maxf:
			mvr += walk_dir * constants.walk_acc() * h
			if mvr * walk_dir > maxf:
				mvr = walk_dir * maxf
		else:
			mvr = move_toward(mvr, walk_dir * maxf, constants.walk_dec() * h)
	else:
		mvr = move_toward(mvr, 0.0, constants.walk_dec() * h)
	var flags := 0
	var nx := pos.x + (mvr * tx + fhm.force[f]) * h
	var w := fhm.wall_hit(pos.x, pos.y, nx, pos.y)
	if w >= 0:
		nx = fhm.x1[w] - signf(nx - pos.x) * 0.01
		mvr = 0.0
		flags |= EV_WALL
	if nx < lim.x or nx > lim.y:
		nx = clampf(nx, lim.x, lim.y)
		mvr = 0.0
	# Follow the chain of floors; a missing/non-floor neighbour means the platform ends here.
	var guard := 0
	while nx > fhm.x2[f] and guard < 256:
		var g := fhm.next[f]
		if g < 0 or not fhm.is_floor(g):
			break
		mvr = _reproject(mvr, f, g, fhm)
		f = g
		guard += 1
	while nx < fhm.x1[f] and guard < 256:
		var g := fhm.prev[f]
		if g < 0 or not fhm.is_floor(g):
			break
		mvr = _reproject(mvr, f, g, fhm)
		f = g
		guard += 1
	fx = fhm.x2[f] - fhm.x1[f]
	fy = fhm.y2[f] - fhm.y1[f]
	flen = sqrt(fx * fx + fy * fy)
	vel = Vector2(fx, fy) / flen * mvr
	if nx > fhm.x2[f] or nx < fhm.x1[f]:
		pos = Vector2(nx, fhm.y_at(f, clampf(nx, fhm.x1[f], fhm.x2[f])))
		fh = -1
		return flags | EV_WALK_OFF
	fh = f
	pos = Vector2(nx, fhm.y_at(f, nx))
	return flags


func _reproject(mvr: float, f: int, g: int, fhm: FootholdMap) -> float:
	var ax := fhm.x2[f] - fhm.x1[f]
	var ay := fhm.y2[f] - fhm.y1[f]
	var bx := fhm.x2[g] - fhm.x1[g]
	var by := fhm.y2[g] - fhm.y1[g]
	return mvr * (ax * bx + ay * by) / (sqrt(ax * ax + ay * ay) * sqrt(bx * bx + by * by))


func _jump(dir: int, f: int, fhm: FootholdMap) -> void:
	vel.y = -constants.jump_speed * jump_stat / 100.0
	if dir != 0:
		var fmax := max_walk_speed()
		var fx := fhm.x2[f] - fhm.x1[f]
		var fy := fhm.y2[f] - fhm.y1[f]
		if (dir > 0 and fy < 0.0) or (dir < 0 and fy > 0.0):
			fmax *= 1.0 + fy * fy / (fx * fx + fy * fy)  # uphill take-off is faster (NoLifeStory, tier B)
		if dir > 0:
			vel.x = clampf(vel.x, 0.8 * fmax, fmax)
		else:
			vel.x = clampf(vel.x, -fmax, -0.8 * fmax)
	fh = -1
	down_jump_platform = -1


func _air_substep(h: float, dir: int, fhm: FootholdMap, lim: Vector2) -> int:
	var flags := 0
	if dir != 0:
		facing = dir
		var cap := constants.float_drag2 * PhysicsConstants.FLOAT_MULT
		if absf(vel.x) < cap:
			vel.x = clampf(vel.x + dir * 2.0 * constants.float_drag2 / PhysicsConstants.MASS * h, -cap, cap)
	else:
		var dec := constants.float_drag2 / PhysicsConstants.MASS
		if vel.y < constants.fall_speed:
			dec *= constants.float_coefficient
		vel.x = move_toward(vel.x, 0.0, dec * h)
	var vy0 := vel.y
	var vy1 := minf(vy0 + constants.gravity_acc * h, constants.fall_speed)
	vel.y = vy1
	var nx := pos.x + vel.x * h
	var ny := pos.y + (vy0 + vy1) * 0.5 * h
	var w := fhm.wall_hit(pos.x, pos.y, nx, ny)
	if w >= 0:
		nx = fhm.x1[w] - signf(nx - pos.x) * 0.01
		vel.x = 0.0
		flags |= EV_WALL
	if nx < lim.x or nx > lim.y:
		nx = clampf(nx, lim.x, lim.y)
		vel.x = 0.0
	if ny < pos.y:
		var c := fhm.ceiling_hit(pos.x, pos.y, nx, ny)
		if c >= 0:
			ny = fhm.y_at(c, nx) + FootholdMap.EPS  # head bump: stay just under it and start falling
			vel.y = 0.0
	if ny > pos.y:
		var g := fhm.find_landing(pos.x, pos.y, nx, ny, down_jump_platform)
		if g >= 0:
			pos = Vector2(nx, fhm.y_at(g, nx))
			fh = g
			down_jump_platform = -1
			vel.y = minf(vel.y, PhysicsConstants.MAX_LAND_SPEED)
			var fx := fhm.x2[g] - fhm.x1[g]
			var fy := fhm.y2[g] - fhm.y1[g]
			var t := Vector2(fx, fy) / sqrt(fx * fx + fy * fy)
			vel = t * vel.dot(t)
			return flags | EV_LAND
	pos = Vector2(nx, ny)
	return flags
