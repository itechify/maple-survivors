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
##   hidden: bool (the character is Hidden, #194): nothing chases it; ground mobs patrol their platform as if it had no route
##     to the character and flyers hover in place (tier C)
##   boss_actions: action_snapshot() arrays; nonempty actions hold grounded movement and captured facing
##   events: Array receiving status expiry and poison mob_hit events (RunWorld's current event list)
## Both graphs must be built with the same gravity/fall_speed/jump_speed as `physics`.
## `kinds` must hold the MobKind of every `kind` index used (RunWorld shares its mob_kinds array). Their fields are
## re-read at every step(), so replacing or editing a kind (elite or speed overrides) takes effect on the next tick.

const STAND := 0
const MOVE := 1
const JUMP := 2
const HIT := 3
const DIE := 4
const FREE := 5
## tier C: v83 server-reference poison rule; tier B (v95 RE) supports the 1-second display clock only.
## Formula/rounding limits and pinned sources: docs/research/monster-status-effects.md.
const POISON_INTERVAL := 1.0
const POISON_LEVEL_BASE := 70
const POISON_DAMAGE_CAP := 32767
## tier C: numerical tolerance for double status clocks at the fixed-tick boundary.
const STATUS_EPSILON := 1e-9
## tier C interpretation of the canonical two-consecutive-uses text; shared across branch copies.
const SLOW_CONSECUTIVE_LIMIT := 2
## Player-inflicted statuses: index into the flattened per-slot status table (slot * STATUS_COUNT + status).
const SLOW := 0
const POISON := 1
const FREEZE := 2
const THREATENED := 3
const STUN := 4
const STATUS_COUNT := 5
## Status names used by apply_status and the mob_status_* events, in table order.
const STATUS_NAMES := ["slow", "poison", "freeze", "threatened", "stun"]
## tier A: the element a status shares with its applying v83 skill (Slow none, Poison Breath elemAttr s, Cold Beam i).
## Stun has none and never reads an element, not even one passed in `params` (tier C, #187).
const STATUS_ELEMENTS := ["", "S", "I", "", ""]

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
## Logical mob identity in a packed 64-bit array, independent of its reusable slot and canonical kind ID.
## tier C: run-local monotonic spawn bookkeeping; RunWorld retains identity when relocating the same entity.
var identity := PackedInt64Array()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var hp := PackedInt32Array()
var max_hp := PackedInt32Array()
## Remaining canonical monster MP; fresh spawns reset it, relocation preserves it.
var mp := PackedInt32Array()
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
## 1 for a scheduled-boss slot: never stunned or pushed whatever its kind's flags (RunWorld sets it after a boss
## arrival or relocation); spawn() clears it.
var steady := PackedByteArray()
## 1 while the mob is alive (not DIE/FREE): the mask for SpatialHash.rebuild and targeting.
var active := PackedByteArray()
## Travel cost (px) left to the player at the last grounded step: the walk on the player's platform, else the chosen
## route's (NavGraph.route_cost); INF = no way there (or not computed yet). Kept while airborne.
var route_len := PackedFloat32Array()
## Player-inflicted status table, index slot * STATUS_COUNT + status: seconds left (doubles, so a canonical whole
## second expires after exactly 60 fixed ticks) and seconds since application (the status art clock).
var status_left := PackedFloat64Array()
var status_elapsed := PackedFloat32Array()
## Canonical signed Slow x scales pursuit speed by (100 + x) / 100; 1 when not slowed.
var slow_factor := PackedFloat32Array()
## Threatened (Page Threaten, spec #165 #183): the flat weapon attack and weapon defence the mob loses while it lasts, as
## positive amounts (the canonical x and y are negative); 0 when the mob is not threatened.
var threat_pad := PackedFloat32Array()
var threat_pdd := PackedFloat32Array()
## tier C: consecutive successful Slow auto-casts on this logical mob; expiry does not reset the sequence.
var _slow_cast_serial := PackedInt32Array()
var _slow_cast_streak := PackedByteArray()
var _poison_pulse := PackedFloat64Array()
var _poison_damage := PackedInt32Array()
var _poison_skill := PackedStringArray()
## Actual nonlethal poison damage, included in RunWorld's player damage credit.
var poison_dealt := 0
## Slots carrying at least one status, unordered (the status tick visits only these); _status_at[slot] is the slot's
## index in it, or -1.
var _status_slots := PackedInt32Array()
var _status_at := PackedInt32Array()

var kinds: Array = []
var fhm: FootholdMap
var tuning: Dictionary
## Mobs recycled because they fell out of the world (should stay 0 on sane maps).
var lost_count := 0

var _free := PackedInt32Array()
var _alive := 0
var _next_identity := 0
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


## Feet position of slot i.
func pos(i: int) -> Vector2:
	return Vector2(x[i], y[i])


## Whether slot i holds a live mob (not dying, not free); false for out-of-range slots.
func is_live(i: int) -> bool:
	return i >= 0 and i < capacity() and active[i] != 0


## Whether slot i holds a live mob that has fully faded in (alpha 1), so it may touch or act.
func is_settled(i: int) -> bool:
	return is_live(i) and alpha[i] >= 1.0


## Seconds left on status `s` (SLOW, POISON, FREEZE, THREATENED or STUN) of slot i; 0 when it is not active.
func status_time(i: int, s: int) -> float:
	return status_left[i * STATUS_COUNT + s]


## Gate for monster touch damage and starting attacks/skills: fully visible, not frozen and not stunned (tier B
## later-client RE for frozen attacks/skills; tier C owner choice for frozen touch damage; a stunned monster follows
## the frozen rule, #187).
func can_act(i: int) -> bool:
	var base := i * STATUS_COUNT
	return is_settled(i) and status_left[base + FREEZE] <= 0.0 and status_left[base + STUN] <= 0.0


## Whether any slot has a player-inflicted status; presentation can skip status work when false.
func has_statuses() -> bool:
	return not _status_slots.is_empty()


## The MobKind of the mob in slot i.
func mob_kind(i: int) -> MobKind:
	return kinds[kind[i]]


## Live slots whose feet are inside `area`, ascending.
func live_in_rect(area: Rect2) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in capacity():
		if active[i] != 0 and area.has_point(Vector2(x[i], y[i])):
			out.append(i)
	return out


## Adds a mob of kind index `k` standing on foothold `f` (or falling from (px, py) when f = -1). hp <= 0 uses the
## kind's max_hp. Returns the slot. The arrays grow when full.
func spawn(k: int, px: float, py: float, f: int, p_hp: int = 0) -> int:
	if _free.is_empty():
		_grow(capacity() * 2)
	var i := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	_next_identity += 1
	identity[i] = _next_identity
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
	mp[i] = kinds[k].max_mp if k >= 0 and k < kinds.size() else 0
	state[i] = STAND if f >= 0 else JUMP
	state_t[i] = 0.0
	anim_t[i] = 0.0
	fh[i] = f
	platform[i] = -1
	facing[i] = -1
	alpha[i] = 0.0
	fading_out[i] = 0
	steady[i] = 0
	active[i] = 1
	slow_factor[i] = 1.0
	threat_pad[i] = 0.0
	threat_pdd[i] = 0.0
	_slow_cast_serial[i] = -1
	_slow_cast_streak[i] = 0
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


## Relocates the same live mob through despawn/spawn, preserving identity, HP/MP and Slow cast history.
## Active statuses and movement reset as on a fresh spawn. Returns the new slot, or -1 when not live.
func relocate(i: int, pos: Vector2, f: int) -> int:
	if not is_live(i):
		return -1
	var k := kind[i]
	var old_identity := identity[i]
	var slow_serial := _slow_cast_serial[i]
	var slow_streak := _slow_cast_streak[i]
	var old_hp := hp[i]
	var old_max_hp := max_hp[i]
	var old_mp := mp[i]
	despawn(i)
	var j := spawn(k, pos.x, pos.y, f, old_max_hp)
	identity[j] = old_identity
	_slow_cast_serial[j] = slow_serial
	_slow_cast_streak[j] = slow_streak
	hp[j] = old_hp
	mp[j] = old_mp
	return j


## Whether a crowd Slow may include slot i after the last successful global Slow cast `serial`.
func can_slow_cast(i: int, serial: int) -> bool:
	return accepts_status(i, "slow") and status_time(i, SLOW) <= 0.0 \
		and (_slow_cast_serial[i] != serial or _slow_cast_streak[i] < SLOW_CONSECUTIVE_LIMIT)


## Applies an admitted Slow cast and records its serial only if status application succeeds.
func apply_slow_cast(i: int, serial: int, params: Dictionary, events: Array) -> bool:
	if not apply_status(i, "slow", params, events):
		return false
	_slow_cast_streak[i] = _slow_cast_streak[i] + 1 if _slow_cast_serial[i] == serial - 1 else 1
	_slow_cast_serial[i] = serial
	return true


## Whether a crowd cast of `status` (the skill's cast.status, "slow" when it names none) may include slot i: Slow keeps its
## consecutive-use rule (can_slow_cast); any other status needs a mob that accepts it and does not carry it yet.
func can_crowd_cast(i: int, status: String, serial: int) -> bool:
	if status == "slow":
		return can_slow_cast(i, serial)
	var s := STATUS_NAMES.find(status)
	return s >= 0 and accepts_status(i, status) and status_time(i, s) <= 0.0


## `weapon_attack` of the mob in slot i after a Threaten cut: lowered by the flat amount (never below 0) while it is
## threatened, `weapon_attack` itself otherwise. Contact damage and weapon attacks (MobAttacks) read it.
func threatened_pad(i: int, weapon_attack: float) -> float:
	return _threat_cut(i, weapon_attack, threat_pad)


## `weapon_defense` of the mob in slot i after a Threaten cut (never below 0) while it is threatened, else unchanged.
func threatened_pdd(i: int, weapon_defense: float) -> float:
	return _threat_cut(i, weapon_defense, threat_pdd)


## Applies the Threaten cut to `pdd` (per-slot weapon defence already filled for the live slots) of every threatened slot.
func lower_threatened_pdd(pdd: PackedFloat32Array) -> void:
	for k in _status_slots.size():
		var i := _status_slots[k]
		if i < pdd.size():
			pdd[i] = _threat_cut(i, pdd[i], threat_pdd)


## `value` less the Threaten cut `cuts[i]` (never below 0) while slot i is threatened, else `value` unchanged.
func _threat_cut(i: int, value: float, cuts: PackedFloat32Array) -> float:
	if i < 0 or i >= capacity() or status_left[i * STATUS_COUNT + THREATENED] <= 0.0:
		return value
	return maxf(0.0, value - cuts[i])


## Applies "slow" (canonical signed x/time), "freeze" or "stun" (time) or "threatened" (flat signed x/y and time), or "poison" (canonical level/time, optional skill
## key); `params.element` overrides the status's own element (STATUS_ELEMENTS; "stun" ignores it). Refreshes without
## stacking (tier C, issue #54; a stun keeps the longer of the remaining and the new time, #187); poison snapshots the slot's max HP at application. Bosses and kinds immune, strong or neutral (Mob.wz
## digit 4) against the status element reject it. Appends application/expiry events to the supplied simulation event list. Removal/death/
## relocation clears silently; mob_died/mob_spawned and the arrays describe those transitions.
func apply_status(i: int, status: String, params: Dictionary, events: Array) -> bool:
	var s := STATUS_NAMES.find(status)
	var time := float(params.get("time", 0.0))
	if time <= 0.0 or not accepts_status(i, status, params):
		return false
	var j := i * STATUS_COUNT + s
	var refreshed := false
	if s == POISON:
		var level := int(params.get("level", 0))
		if level <= 0 or level >= POISON_LEVEL_BASE:
			return false
		_poison_pulse[i] = POISON_INTERVAL
		_poison_damage[i] = mini(POISON_DAMAGE_CAP, ceili(float(max_hp[i]) / (POISON_LEVEL_BASE - level)))
		_poison_skill[i] = String(params.get("skill", STATUS_NAMES[POISON]))
	elif s == SLOW:
		# tier C: a canonical positive x would speed the monster up; only slowing is applied.
		slow_factor[i] = clampf(1.0 + float(params.get("x", 0.0)) / 100.0, 0.0, 1.0)
	elif s == STUN and status_left[j] > time:
		# tier C: a new stun on a stunned monster refreshes it to the longer remaining time (#187); a shorter new one
		# changes nothing, art clock included.
		time = status_left[j]
		refreshed = true
	elif s == THREATENED:
		# tier A: the canonical signed x (weapon attack) and y (weapon defence) are flat; only lowering is applied.
		threat_pad[i] = maxf(0.0, -float(params.get("x", 0.0)))
		threat_pdd[i] = maxf(0.0, -float(params.get("y", 0.0)))
	if _status_at[i] < 0:
		_status_at[i] = _status_slots.size()
		_status_slots.append(i)
	status_left[j] = time
	if not refreshed:
		status_elapsed[j] = 0.0
	events.append({"type": "mob_status_applied", "mob": i, "mob_id": mob_kind(i).id, "status": status, "duration": time})
	return true


## Non-mutating status eligibility, shared by cast admission and application. Duration/value checks stay in apply_status.
func accepts_status(i: int, status: String, params: Dictionary = {}) -> bool:
	var s := STATUS_NAMES.find(status)
	if s < 0 or not is_live(i):
		return false
	var mk := mob_kind(i)
	# tier C: v83 server reference rejects boss statuses and immune/strong/neutral status elements.
	if mk.boss or steady[i] != 0:
		return false
	# tier C: stun is elementless; elemental resistance only gates the other statuses.
	return s == STUN or not mk.resists_status(String(params.get("element", STATUS_ELEMENTS[s])))


## Damages mob i by dmg from direction dir (-1/1: the way the blow pushes). Returns true when this hit killed it.
## Dying or free slots ignore hits. Scheduled-boss slots (`steady`) and kinds with canonical info/boss or the survivor
## no_flinch override ignore stun/push; other mobs require damage >= canonical pushed.
func apply_hit(i: int, dmg: int, dir: int) -> bool:
	if dmg <= 0 or i < 0 or i >= capacity() or state[i] == DIE or state[i] == FREE:
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
		_clear_statuses(i)
		_alive -= 1
		return true
	# tier C: a frozen or stunned monster keeps its pose instead of starting the hit stun or push.
	if status_left[i * STATUS_COUNT + FREEZE] > 0.0 or status_left[i * STATUS_COUNT + STUN] > 0.0 or steady[i] != 0 \
			or (mk != null and (mk.boss or mk.no_flinch or dmg < mk.pushed)):
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
	var hidden: bool = ctx.get("hidden", false)
	var tp := -1
	if not hidden:
		tp = m.platform_of(tfh) if tfh >= 0 else m.platform_of(m.find_below(target.x, target.y))
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
	var statuses_active := not _status_slots.is_empty()
	for i in _hi:
		var st := state[i]
		if st == FREE:
			continue
		var k := kind[i]
		# tier B: later-client RE holds frozen movement and attacks; both animation clocks stay fixed as well. Tier C
		# (owner): a monster frozen mid-air still falls straight down and a fading-in one keeps fading in.
		if statuses_active and st != DIE and status_left[i * STATUS_COUNT + FREEZE] > 0.0:
			if fading_out[i] == 0 and alpha[i] < 1.0:
				alpha[i] = minf(1.0, alpha[i] + dt / regen)
			if fh[i] < 0 and _k_fly[k] == 0:
				vx[i] = 0.0
				_air(i, dt, m, grav, fall, lim, bottom)
			continue
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
		if statuses_active and status_left[i * STATUS_COUNT + STUN] > 0.0:
			# tier C (#187): a stunned monster stands where it is (a flyer hovers without its bob) and runs no route,
			# jump or hit slide; its clocks keep running, and one stunned mid-air still falls straight down.
			vx[i] = 0.0
			if fh[i] >= 0 or _k_fly[k] != 0:
				if st != STAND:
					_set_state(i, STAND)
			else:
				_air(i, dt, m, grav, fall, lim, bottom)
			continue
		if _k_fly[k] != 0:
			var fly_speed := _k_speed[k] * smult
			if statuses_active:
				fly_speed *= slow_factor[i]
			# Hidden: the flyer steers at its own resting point, so it stands and bobs where it is.
			var aim := Vector2(x[i], y[i] - _fly_bob[i]) if hidden else target
			_fly(i, dt, fly_speed, aim, bounds)
			route_len[i] = INF if hidden else Vector2(x[i], y[i]).distance_to(target)
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
		if statuses_active:
			spd *= slow_factor[i]
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
	if not _status_slots.is_empty():
		_step_statuses(dt, ctx.get("events", []))


func _step_statuses(dt: float, events: Array) -> void:
	# Backwards: a slot whose last status ends swaps the list's (already visited) last slot into its place.
	for k in range(_status_slots.size() - 1, -1, -1):
		var i := _status_slots[k]
		var base := i * STATUS_COUNT
		var poison := status_left[base + POISON]
		if poison > 0.0:
			_poison_pulse[i] -= minf(dt, poison)
			while _poison_pulse[i] <= STATUS_EPSILON:
				_poison_pulse[i] += POISON_INTERVAL
				_poison_tick(i, events)
		for s in STATUS_COUNT:
			var left := status_left[base + s]
			if left <= 0.0:
				continue
			status_elapsed[base + s] += minf(dt, left)
			left = maxf(0.0, left - dt)
			if left > STATUS_EPSILON:
				status_left[base + s] = left
				continue
			status_left[base + s] = 0.0
			_end_status(i, s)
			events.append({"type": "mob_status_expired", "mob": i, "mob_id": mob_kind(i).id,
				"status": STATUS_NAMES[s]})


## One poison pulse on slot i: its snapshot damage, never below 1 HP and without stun/push.
func _poison_tick(i: int, events: Array) -> void:
	# tier C: v83 server poison leaves at least 1 HP and never causes stun/push.
	var damage := mini(_poison_damage[i], maxi(0, hp[i] - 1))
	if damage <= 0:
		return
	hp[i] -= damage
	poison_dealt += damage
	var mk := mob_kind(i)
	events.append({"type": "mob_hit", "mob": i, "mob_id": mk.id, "damage": damage, "crit": false,
		"pos": Vector2(x[i], y[i] + mk.hitbox.position.y), "hit_visual": "", "skill": _poison_skill[i]})


## Resets the side data of status `s` of slot i, whose timer already reads 0, and drops the slot from the status
## list once it carries none.
func _end_status(i: int, s: int) -> void:
	if s == SLOW:
		slow_factor[i] = 1.0
	elif s == THREATENED:
		threat_pad[i] = 0.0
		threat_pdd[i] = 0.0
	elif s == POISON:
		_poison_pulse[i] = 0.0
		_poison_damage[i] = 0
		_poison_skill[i] = ""
	var base := i * STATUS_COUNT
	for other in STATUS_COUNT:
		if status_left[base + other] > 0.0:
			return
	var at := _status_at[i]
	var last := _status_slots[_status_slots.size() - 1]
	_status_slots[at] = last
	_status_at[last] = at
	_status_slots.resize(_status_slots.size() - 1)
	_status_at[i] = -1


func _clear_statuses(i: int) -> void:
	var base := i * STATUS_COUNT
	for s in STATUS_COUNT:
		if status_left[base + s] > 0.0:
			status_left[base + s] = 0.0
			_end_status(i, s)
		status_elapsed[base + s] = 0.0


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
	_clear_statuses(i)
	mp[i] = 0
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
	mp.resize(n)
	state.resize(n)
	identity.resize(n)
	state_t.resize(n)
	anim_t.resize(n)
	_fly_bob.resize(n)
	fh.resize(n)
	platform.resize(n)
	facing.resize(n)
	alpha.resize(n)
	fading_out.resize(n)
	steady.resize(n)
	active.resize(n)
	_stop_x.resize(n)
	_route_e.resize(n)
	route_len.resize(n)
	status_left.resize(n * STATUS_COUNT)
	status_elapsed.resize(n * STATUS_COUNT)
	slow_factor.resize(n)
	threat_pad.resize(n)
	threat_pdd.resize(n)
	_slow_cast_serial.resize(n)
	_slow_cast_streak.resize(n)
	_poison_pulse.resize(n)
	_poison_damage.resize(n)
	_poison_skill.resize(n)
	_status_at.resize(n)
	for i in range(old, n):
		slow_factor[i] = 1.0
		_status_at[i] = -1
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
