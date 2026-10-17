extends RefCounted
## The playtest tactic controller (spec #91, ticket #95): turns the current tactic into the player's MoveInput for one
## fixed tick. Deterministic and pure apart from its own movement state (`visits`, `_memo`); it never touches the
## sim's RNG streams. Tool code only.
##
##   kite        BotInput.decide with the caller's memo, unchanged (the sensible bot; byte-identical play)
##   aggressive  close on the nearest mob on the player's level (a scheduled boss first) and duel it facing it, hopping
##               now and then; kites like the bot while HP is low or nothing is in reach
##   defensive   flee any mob within DEFENSIVE_FLEE_X (twice the bot's flee range), walk only to drops no mob is near,
##               drink potions earlier; otherwise stand still
##   explore     walk, hop, climb ropes and take same-map portals toward the platform visited least (`visits` counts
##               arrivals per FootholdMap platform, whatever the tactic)
##   collect     walk to the cheapest drop anywhere, climbing to platforms above (nav graph hops, ropes, portals)
##   hold        press no movement key (potions still drink like the bot)
## An unknown tactic kites. Non-kite tactics keep their own memo, so switching back to kite resumes BotInput's state.
## Reaction delay, mistakes and personality potion thresholds are #97's (the motor layer on top of this).

const SITUATION := preload("res://tools/playtest/playtest_situation.gd")

## Every tactic, in the order the decision offers them.
const TACTICS := ["kite", "aggressive", "defensive", "explore", "collect", "hold"]
## tier C: BotInput's "on the player's level" box: mobs from LEVEL_UP px above to LEVEL_DOWN px below the feet.
const LEVEL_UP := 140.0
const LEVEL_DOWN := 90.0
## tier C: an aggressive player goes after mobs within this many px horizontally.
const AGGRO_X := 600.0
## tier C: within this many px of its target the aggressive player stops, faces it and lets its attacks swing.
const DUEL_X := 50.0
## tier C: ticks between hops while dueling (contact damage dodge, MapleStory-style).
const HOP_EVERY := 90
## tier C: a defensive player flees mobs within this many px (BotInput.FLEE_DIST is 160).
const DEFENSIVE_FLEE_X := 320.0
## tier C: a drop with a mob within this many px of it is not worth the walk for a defensive player.
const DEFENSIVE_DROP_CLEAR := 250.0
## tier C: a defensive player drinks once a quarter of a potion's restore is missing (the bot waits for half).
const DEFENSIVE_DRINK_GUARD := 0.25
## tier C: ticks spent on a reached explore target before choosing the next one, and ticks before a target that was
## not reached is given up (and skipped for EXPLORE_SKIP ticks).
const EXPLORE_DWELL := 90
const ROUTE_GIVE_UP := 20 * 60
const EXPLORE_SKIP := 60 * 60
## tier C: ticks collect chases one drop before skipping it (well inside the stuck invariant's 20 s).
const COLLECT_GIVE_UP := 10 * 60
## tier C: ticks pressing a direction without moving before a hop to get over the obstacle.
const STUCK_TICKS := 15
## tier C: a jump/drop takeoff point is reached within this many px (PortalApproach uses 3).
const TAKEOFF_X := 3.0
## tier C: drops this far below the feet and within DOWN_X horizontally are reached with a down-jump (as BotInput).
const DOWN_Y := 40.0
const DOWN_X := 60.0
## tier C: the bot's travel cost weighs height twice (BotInput._drop_distance).
const HEIGHT_COST := 2.0

## Arrivals per platform: {platform: count}.
var visits := {}
var _memo := {}
var _last_platform := -2
var _tick := 0
## True when _begin found a portal hop or rope climb in progress (its input is then final).
var _busy := false


## The input for the next tick of `w` under `tactic`; `kite_memo` is BotInput's memo (the run policy's `memo`).
func input(w: RunWorld, tactic: String, kite_memo: Dictionary) -> MoveInput:
	_tick += 1
	_count_visit(w)
	match tactic:
		"aggressive":
			return _aggressive(w, kite_memo)
		"defensive":
			return _defensive(w)
		"explore":
			return _explore(w)
		"collect":
			return _collect(w, kite_memo)
		"hold":
			return _drinks(w, _bot_guard(w))
	return BotInput.decide(w, kite_memo)


## Counts an arrival on a new platform (grounded only).
func _count_visit(w: RunWorld) -> void:
	if w.player.fh < 0:
		return
	var p := w.fhm.platform_of(w.player.fh)
	if p != _last_platform:
		_last_platform = p
		visits[p] = int(visits.get(p, 0)) + 1


func _aggressive(w: RunWorld, kite_memo: Dictionary) -> MoveInput:
	var ps := w.player_state
	var hp := SITUATION.pool_bucket(int(ps.hp), int(ps.max_hp))
	var target := _target_mob(w)
	if hp == "low" or hp == "critical" or target < 0:
		return BotInput.decide(w, kite_memo)
	var mi := _begin(w, _bot_guard(w))
	if _busy:
		return mi
	var dx := w.swarm.x[target] - w.player.pos.x
	var side := 1 if dx > 0.0 else -1
	if absf(dx) > DUEL_X:
		_memo.erase("duel_t")
		_walk(w, mi, side)
		return mi
	_memo["duel_t"] = int(_memo.get("duel_t", 0)) + 1
	_walk(w, mi, side if w.player.facing != side else 0)
	if int(_memo.duel_t) % HOP_EVERY == 0 and w.player.fh >= 0:
		mi.jump_pressed = true
		mi.jump_held = true
	return mi


func _defensive(w: RunWorld) -> MoveInput:
	var mi := _begin(w, DEFENSIVE_DRINK_GUARD)
	if _busy:
		return mi
	var p := w.player.pos
	var danger := [0.0, 0.0]
	var nearest := [INF, INF]
	var s := w.swarm
	for i in s.capacity():
		if s.active[i] == 0 or not _on_level(s.y[i] - p.y):
			continue
		var dx := s.x[i] - p.x
		var side := 0 if dx < 0.0 else 1
		danger[side] += 1.0 / (absf(dx) + 30.0)
		nearest[side] = minf(nearest[side], absf(dx))
	if minf(nearest[0], nearest[1]) < DEFENSIVE_FLEE_X:
		danger[0] += BotInput.EDGE_DANGER / (p.x - w.bounds.position.x + 10.0)
		danger[1] += BotInput.EDGE_DANGER / (w.bounds.end.x - p.x + 10.0)
		var dir := -1 if danger[0] < danger[1] else 1
		_walk(w, mi, dir)
		var ahead: float = nearest[0 if dir < 0 else 1]
		if w.player.fh >= 0 and ahead > 25.0 and ahead < 75.0:
			mi.jump_pressed = true
			mi.jump_held = true
		return mi
	var drop := _nearest_drop(w, true)
	if drop >= 0:
		_walk_to_drop(w, mi, drop)
	else:
		_memo.erase("stuck")
	return mi


func _explore(w: RunWorld) -> MoveInput:
	var mi := _begin(w, _bot_guard(w))
	if _busy or w.player.fh < 0:
		return _air(w, mi)
	var cur := w.player_platform()
	var target := int(_memo.get("explore_target", -1))
	var since := _tick - int(_memo.get("explore_since", _tick))
	if target >= 0 and target != cur and since > ROUTE_GIVE_UP:
		_memo["explore_skip_%d" % target] = _tick + EXPLORE_SKIP
		target = -1
	if target == cur:
		_memo["explore_dwell"] = int(_memo.get("explore_dwell", 0)) + 1
		if int(_memo.explore_dwell) > EXPLORE_DWELL:
			target = -1
	if target < 0:
		target = _least_visited(w, cur)
		_memo["explore_target"] = target
		_memo["explore_since"] = _tick
		_memo["explore_dwell"] = 0
	if target < 0:
		return mi
	var span := w.fhm.platform_span(target)
	if not _go_to_platform(w, mi, target, (span.x + span.y) * 0.5):
		_memo["explore_skip_%d" % target] = _tick + EXPLORE_SKIP
		_memo["explore_target"] = -1
	return mi


func _collect(w: RunWorld, kite_memo: Dictionary) -> MoveInput:
	var drop := _collect_target(w) # every tick, so the give-up clock also runs through hops and climbs
	var mi := _begin(w, _bot_guard(w))
	if _busy or w.player.fh < 0:
		return _air(w, mi)
	if drop < 0:
		return BotInput.decide(w, kite_memo)
	var pk := w.pickups
	if pk.y[drop] - w.player.pos.y >= -w.magnet_r * SITUATION.DROP_REACH_UP:
		_walk_to_drop(w, mi, drop)
		return mi
	var f := w.fhm.find_below(pk.x[drop], pk.y[drop] - 4.0)
	var plat := w.fhm.platform_of(f)
	if plat < 0 or not _go_to_platform(w, mi, plat, pk.x[drop]):
		return BotInput.decide(w, kite_memo)
	return mi


## The drop collect goes for. It stays the one chosen first while that drop is on the map: re-picking the cheapest drop
## every tick dithered between two drops whose travel costs cross as the player walks (#96: Henesys seed 2, 1:05).
## A drop is the same while its slot is active and its age has not gone back (a reused or merged slot restarts it). A
## drop not swept within COLLECT_GIVE_UP ticks is skipped while it stays; -1 when there is no drop to go for.
func _collect_target(w: RunWorld) -> int:
	var pk := w.pickups
	var skip: Dictionary = _memo.get("collect_skip", {})
	for k: int in skip.keys():
		if not _same_drop(pk, k, float(skip[k])):
			skip.erase(k)
	var i := int(_memo.get("collect_drop", -1))
	if int(_memo.get("collect_seen", -1)) != _tick - 1:
		i = -1 # collect resumes after another tactic: choose afresh
	_memo["collect_seen"] = _tick
	if i >= 0 and _same_drop(pk, i, float(_memo.collect_age)):
		_memo["collect_age"] = pk.age[i]
		if _tick - int(_memo.collect_since) <= COLLECT_GIVE_UP:
			return i
		skip[i] = pk.age[i]
	_memo["collect_skip"] = skip
	i = _nearest_drop(w, false, skip)
	_memo["collect_drop"] = i
	if i >= 0:
		_memo["collect_age"] = pk.age[i]
		_memo["collect_since"] = _tick
	return i


## True while pickup slot `i` still holds the drop that was `age` seconds old when last seen.
func _same_drop(pk: PickupSystem, i: int, age: float) -> bool:
	return i < pk.capacity() and pk.active[i] != 0 and pk.age[i] >= age


## A MoveInput with the potion presses (BotInput.worth_drinking with `guard`) and, when a portal hop or a rope climb is
## in progress, its keys; `_busy` then tells the caller to return it as it is.
func _begin(w: RunWorld, guard: float) -> MoveInput:
	_busy = false
	var mi := _drinks(w, guard)
	var p := w.player.pos
	if _memo.has("portal_x") and w.player.fh < 0 and absf(p.x - float(_memo.portal_x)) <= float(w.portals.tuning.reach_x):
		mi.up = true
		_busy = true
		return mi
	if w.player.fh >= 0:
		_memo.erase("portal_x")
	if w.player.ladder >= 0:
		_memo["climb_t"] = int(_memo.get("climb_t", 0)) + 1
		mi.up = int(_memo.climb_t) < BotInput.CLIMB_GIVE_UP
		if not mi.up:
			mi.jump_pressed = true
			mi.jump_held = true
			mi.right = true
		_busy = true
		return mi
	_memo.erase("climb_t")
	return mi


## Potion presses only.
func _drinks(w: RunWorld, guard: float) -> MoveInput:
	var mi := MoveInput.new()
	var ps := w.player_state
	mi.drink_hp = BotInput.worth_drinking(w, "hp", float(ps.max_hp) - float(ps.hp), guard)
	mi.drink_mp = BotInput.worth_drinking(w, "mp", float(ps.max_mp) - float(ps.mp), _bot_guard(w))
	return mi


## The bot's potion guard (balance.potions.bot.min_restore_fraction, as BotInput.decide reads it).
func _bot_guard(w: RunWorld) -> float:
	return float(w.balance.get("potions", {}).get("bot", {}).get("min_restore_fraction", 0.5))


## Airborne: keep the horizontal key of the takeoff (held Up near a rope or portal stays from _begin).
func _air(w: RunWorld, mi: MoveInput) -> MoveInput:
	if w.player.fh < 0 and not _busy:
		var dir := int(_memo.get("air_dir", 0))
		mi.left = dir < 0
		mi.right = dir > 0
		if _memo.has("rope_x") and absf(w.player.pos.x - float(_memo.rope_x)) <= 10.0:
			mi.up = true
	return mi


func _on_level(dy: float) -> bool:
	return dy >= -LEVEL_UP and dy <= LEVEL_DOWN


## The aggressive target: the nearest living scheduled boss on the player's level within AGGRO_X, else the nearest
## mob there; -1 when none.
func _target_mob(w: RunWorld) -> int:
	var s := w.swarm
	var p := w.player.pos
	var best := -1
	var best_d := INF
	for i in s.capacity():
		if s.active[i] == 0 or not _on_level(s.y[i] - p.y):
			continue
		var d := absf(s.x[i] - p.x)
		if d > AGGRO_X:
			continue
		if w.is_scheduled_boss(i):
			d -= AGGRO_X * 2.0
		if d < best_d:
			best_d = d
			best = i
	return best


## The cheapest drop (BotInput's travel cost). `walkable_only`: drops on or below the player's level within 1200 px
## and no mob within DEFENSIVE_DROP_CLEAR of them (the defensive rule); otherwise any drop on the map. Slots in `skip`
## are left out.
func _nearest_drop(w: RunWorld, walkable_only: bool, skip: Dictionary = {}) -> int:
	var pk := w.pickups
	var p := w.player.pos
	var reach_up := w.magnet_r * SITUATION.DROP_REACH_UP
	var best := -1
	var best_d := INF
	for i in pk.capacity():
		if pk.active[i] == 0 or skip.has(i):
			continue
		var dx := pk.x[i] - p.x
		var dy := pk.y[i] - p.y
		var d := absf(dx) + absf(dy) * HEIGHT_COST
		if d >= best_d:
			continue
		if walkable_only and (dy < -reach_up or absf(dx) > SITUATION.DROP_ABOVE_X or _mob_near(w, Vector2(pk.x[i], pk.y[i]))):
			continue
		best_d = d
		best = i
	return best


func _mob_near(w: RunWorld, at: Vector2) -> bool:
	var s := w.swarm
	for i in s.capacity():
		if s.active[i] != 0 and absf(s.x[i] - at.x) <= DEFENSIVE_DROP_CLEAR and _on_level(s.y[i] - at.y):
			return true
	return false


## Walks to drop `i` on the player's level, down-jumping to one just below (as BotInput).
func _walk_to_drop(w: RunWorld, mi: MoveInput, i: int) -> void:
	var dx := w.pickups.x[i] - w.player.pos.x
	var dy := w.pickups.y[i] - w.player.pos.y
	_walk(w, mi, 0 if absf(dx) < 4.0 else (1 if dx > 0.0 else -1))
	if dy > DOWN_Y and absf(dx) < DOWN_X and w.player.fh >= 0 and int(_memo.get("down_cd", 0)) <= _tick:
		mi.down = true
		mi.jump_pressed = true
		mi.jump_held = true
		_memo["down_cd"] = _tick + 60


## Presses `dir` (-1, 0, 1); pressing without moving for STUCK_TICKS grounded ticks hops.
func _walk(w: RunWorld, mi: MoveInput, dir: int) -> void:
	mi.left = dir < 0
	mi.right = dir > 0
	_memo["air_dir"] = dir
	var x := w.player.pos.x
	if dir != 0 and w.player.fh >= 0 and absf(x - float(_memo.get("last_x", x + 1.0))) < 0.2:
		_memo["stuck"] = int(_memo.get("stuck", 0)) + 1
		if int(_memo.stuck) > STUCK_TICKS:
			_memo["stuck"] = 0
			mi.jump_pressed = true
			mi.jump_held = true
	else:
		_memo["stuck"] = 0
	_memo["last_x"] = x


## The platform with the fewest arrivals (then the cheapest to walk to, then the lowest id), other than `cur` and
## platforms skipped for now; -1 when there is none.
func _least_visited(w: RunWorld, cur: int) -> int:
	var p := w.player.pos
	var best := -1
	var best_key := Vector2(INF, INF)
	for q in w.fhm.platform_count():
		if q == cur or int(_memo.get("explore_skip_%d" % q, 0)) > _tick:
			continue
		var span := w.fhm.platform_span(q)
		var cx := clampf(p.x, span.x, span.y)
		var cost := absf(cx - p.x) + absf(w.fhm.plat_y_min[q] - p.y) * HEIGHT_COST
		var key := Vector2(int(visits.get(q, 0)), cost)
		if key.x < best_key.x or (key.x == best_key.x and key.y < best_key.y):
			best_key = key
			best = q
	return best


## Steers toward x `tx` on platform `target`: a walk on the same platform, a nav-graph hop or drop, a rope up, or a
## same-map portal whose arrival is the target (or closer to it). False when no way is known from here.
func _go_to_platform(w: RunWorld, mi: MoveInput, target: int, tx: float) -> bool:
	var cur := w.player_platform()
	var p := w.player.pos
	if cur == target:
		_walk(w, mi, 0 if absf(tx - p.x) < 4.0 else (1 if tx > p.x else -1))
		return true
	var e := w.nav_jump.route_near(cur, target, p.x)
	if e >= 0:
		var ed := w.nav_jump.edge(e)
		var vx := float(ed.vx)
		if String(ed.kind) == "drop":
			var xe := float(ed.x_from)
			# Walk to the open end and on past it.
			var past := absf(xe - p.x) < TAKEOFF_X or signf(p.x - xe) == signf(vx)
			_walk(w, mi, int(signf(vx)) if past else (1 if xe > p.x else -1))
			return true
		# A straight-up hop takes off as soon as the player is under the target (its nearest point of the range).
		var at := clampf(p.x, float(ed.lo), float(ed.hi)) if vx == 0.0 else float(ed.x_from)
		if absf(at - p.x) > TAKEOFF_X:
			_walk(w, mi, 1 if at > p.x else -1)
			return true
		mi.jump_pressed = true
		mi.jump_held = true
		var hop := int(signf(vx))
		mi.left = hop < 0
		mi.right = hop > 0
		_memo["air_dir"] = hop
		return true
	var portal := _portal_toward(w, target)
	if not portal.is_empty():
		PortalApproach.steer(w, portal, mi)
		_memo["portal_x"] = portal.source.x
		_memo["air_dir"] = mi.dir()
		return true
	var lad := BotInput.climb_ladder(w)
	if lad >= 0 and w.fhm.plat_y_min[target] < p.y - LEVEL_DOWN:
		var lx := w.ladders.x[lad]
		if absf(lx - p.x) > TAKEOFF_X:
			_walk(w, mi, 1 if lx > p.x else -1)
		else:
			mi.up = true
			if w.fhm.y_at(w.player.fh, p.x) - w.ladders.y2[lad] > BotInput.LADDER_STAND_REACH:
				mi.jump_pressed = true
				mi.jump_held = true
			_memo["rope_x"] = lx
			_memo["air_dir"] = 0
		return true
	return false


## A same-map portal approachable from here whose arrival platform is `target`, or from which `target` is fewer nav
## hops away than from here; {} when none (PortalApproach plan otherwise).
func _portal_toward(w: RunWorld, target: int) -> Dictionary:
	if w.player.fh < 0:
		return {}
	var cur := w.player_platform()
	var here := w.nav_jump.hops(cur, target) if w.nav_jump.reachable(cur, target) else 1 << 20
	var best := {}
	var best_hops := here
	for link: Dictionary in w.portals.links:
		var arrival: Vector2 = link.target_pos
		var q := w.fhm.platform_of(w.fhm.find_below(arrival.x, arrival.y - 4.0))
		if q < 0:
			continue
		var hops := 0 if q == target else (w.nav_jump.hops(q, target) if w.nav_jump.reachable(q, target) else 1 << 20)
		if hops >= best_hops:
			continue
		var plan := PortalApproach.plan(w, link.pos)
		if plan.is_empty() or float(plan.floor_y) > (link.pos as Vector2).y + float(w.portals.tuning.reach_below):
			continue
		best_hops = hops
		best = plan
	return best

