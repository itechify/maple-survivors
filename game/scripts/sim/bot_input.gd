class_name BotInput
extends RefCounted
## A simple deterministic kiting bot that plays a RunWorld (autoplay in RunScene, the headless full-run tests and the
## run benchmark). Pure: it reads the world's state and returns a MoveInput; `memo` keeps its state between ticks.
##
## It scores the danger on each side (mobs on about its level, closer = worse, the map edge counts as a wall of mobs)
## and, when a mob is near, runs to the safer side, hopping over a mob right ahead. With nothing near it walks to the
## nearest EXP drop that no mob stands in front of (a mob nearer than BLOCK_DIST; down-jumping to one just below).
## When the only drops left are on platforms above (at least CLIMB_MIN_DROPS), it walks to the nearest ladder or rope
## that starts on its platform and climbs it (jumping for a rope that hangs above the floor). With no drop at all it
## heads back toward the middle of the map. When it has not moved for a while it turns around and jumps.
## Same-map portals are approached when they shorten the trip to drops or leave nearby danger for a safer floor.
## The bot reads the jump graph to reach an entrance ledge and holds Up through the portal chain; mob nav is unchanged.
##
## Choices (auto_choose): the first available job, and the upgrade card a sensible player would take (pick_card_for):
## a new attack skill first, then more shots / pierce / damage / rank for the attack skills of the current job, then
## defence, then the rest; ties go to the earlier card. pick_card() is the plain "first card" policy.

## The map edge counts as this much danger / (distance + 10) on its side.
const EDGE_DANGER := 4.0
## A mob nearer than this (px, on the drop's side and before it) keeps the bot from walking to a drop.
const BLOCK_DIST := 250.0
## Climbing: drops above needed to go up; the highest rope bottom (px above the floor) reachable with a jump; a rope
## bottom higher than LADDER_STAND_REACH above the feet needs that jump; ticks before a climb attempt is given up.
const CLIMB_MIN_DROPS := 4
const LADDER_JUMP_REACH := 115.0
const LADDER_STAND_REACH := 45.0
const CLIMB_GIVE_UP := 8 * 60

## Card scores of pick_card_for (higher = taken first). Skill-mod stats not listed score SCORE_MOD_OTHER.
const SCORE_NEW_ATTACK := 100.0
const SCORE_NEW_PASSIVE := 50.0
const SCORE_RANK_ATTACK := 62.0
const SCORE_RANK_PASSIVE := 42.0
const SCORE_MOD := {"count": 75.0, "damage": 64.0, "pierce": 58.0, "cooldown": 54.0, "range": 30.0, "speed": 20.0}
const SCORE_MOD_OTHER := 25.0
## Bonus for cards of a skill of the player's current job (a Magician invests in Magician skills).
const SCORE_JOB_BONUS := 12.0
const SCORE_PLAYER := {"max_hp": 46.0, "hp_regen": 36.0, "pdd": 34.0, "speed": 26.0, "magnet": 22.0, "max_mp": 16.0,
	"mp_regen": 16.0}
## tier C: permanent potion tier improvement is preferred to a general defence card, below attack ranks.
const SCORE_POTION_TIER := 52.0


## The input for the next tick of `w`.
static func decide(w: RunWorld, memo: Dictionary) -> MoveInput:
	var mi := MoveInput.new()
	var thresholds: Dictionary = w.balance.get("potions", {}).get("bot", {})
	var ps := w.player_state
	mi.drink_hp = int(ps.potions.hp.count) > 0 and float(ps.hp) < float(ps.max_hp) * float(thresholds.get("hp_threshold", 0.0))
	mi.drink_mp = int(ps.potions.mp.count) > 0 and float(ps.mp) < float(ps.max_mp) * float(thresholds.get("mp_threshold", 0.0))
	var s := w.swarm
	var p := w.player.pos
	# Keep Up held during the small hop onto a portal's entrance ledge.
	if memo.has("portal_x") and w.player.fh < 0 and absf(p.x - float(memo.portal_x)) <= float(w.portals.tuning.reach_x):
		mi.up = true
		return mi
	# On a ladder or rope (the bot only grabs one to climb up): keep climbing; jump off if it takes far too long.
	if w.player.ladder >= 0:
		memo["climb_t"] = int(memo.get("climb_t", 0)) + 1
		mi.up = int(memo.climb_t) < CLIMB_GIVE_UP
		if not mi.up:
			mi.jump_pressed = true
			mi.right = true
			memo.erase("climb_x")
		mi.jump_held = mi.jump_pressed
		return mi
	if memo.has("climb_x"):
		memo["climb_t"] = int(memo.get("climb_t", 0)) + 1
		if int(memo.climb_t) > CLIMB_GIVE_UP or (w.player.fh >= 0 and absf(p.x - float(memo.climb_x)) > 12.0
				and int(memo.climb_t) > 2):
			memo.erase("climb_x")
	var danger := [0.0, 0.0]
	var nearest := [INF, INF]
	for i in s.capacity():
		if s.active[i] == 0:
			continue
		var dx := s.x[i] - p.x
		var dy := s.y[i] - p.y
		if dy < -140.0 or dy > 90.0 or absf(dx) > 450.0:
			continue
		var side := 0 if dx < 0.0 else 1
		danger[side] += 1.0 / (absf(dx) + 30.0)
		nearest[side] = minf(nearest[side], absf(dx))
	var room := [p.x - w.bounds.position.x, w.bounds.end.x - p.x]
	danger[0] += EDGE_DANGER / (room[0] + 10.0)
	danger[1] += EDGE_DANGER / (room[1] + 10.0)
	var dir := 0
	var down := false
	var portal := _useful_portal(w, minf(nearest[0], nearest[1]) < 160.0)
	if not portal.is_empty():
		var dx: float = portal.pos.x - p.x
		mi.up = bool(portal.same_floor) and absf(dx) <= float(w.portals.tuning.reach_x)
		mi.left = not mi.up and dx < 0.0
		mi.right = not mi.up and dx > 0.0
		if not bool(portal.same_floor) and absf(dx) < 3.0:
			mi.jump_pressed = bool(portal.hop)
			mi.jump_held = mi.jump_pressed
			mi.left = float(portal.hop_dir) < 0.0
			mi.right = float(portal.hop_dir) > 0.0
		memo["portal_x"] = portal.source.x
		memo.erase("climb_x")
		memo.erase("flip_t")
		memo["stuck"] = 0
		memo["last_x"] = p.x
		return mi
	memo.erase("portal_x")
	if minf(nearest[0], nearest[1]) < 160.0:
		dir = -1 if danger[0] < danger[1] else 1
	else:
		var best := INF
		var reach_up := w.magnet_r * 0.7
		var above := 0
		var pk := w.pickups
		for i in pk.capacity():
			if pk.active[i] == 0:
				continue
			var ddx := pk.x[i] - p.x
			var ddy := pk.y[i] - p.y
			# A drop on a platform above, out of magnet reach: not walkable (counted for climbing).
			if ddy < -reach_up:
				if absf(ddx) < 1200.0:
					above += 1
				continue
			var d := absf(ddx) + absf(ddy) * 2.0
			if d >= best or d > 1200.0:
				continue
			# A mob between the bot and the drop blocks it only while that mob is near (a strong build kills the far ones
			# on the way; skipping every drop behind any mob would leave the EXP on the ground for good).
			if nearest[0 if ddx < 0.0 else 1] < minf(absf(ddx), BLOCK_DIST):
				continue
			best = d
			dir = 0 if absf(ddx) < 4.0 else (1 if ddx > 0.0 else -1)
			down = ddy > 40.0 and absf(ddx) < 60.0
		var lad := climb_ladder(w) if best == INF and above >= CLIMB_MIN_DROPS else -1
		if lad >= 0:
			var lx := w.ladders.x[lad]
			if absf(lx - p.x) > 3.0:
				dir = 1 if lx > p.x else -1
			elif w.player.fh >= 0:
				mi.up = true
				var floor_y := w.fhm.y_at(w.player.fh, p.x)
				if floor_y - w.ladders.y2[lad] > LADDER_STAND_REACH:
					mi.jump_pressed = true
				if not memo.has("climb_x"):
					memo["climb_x"] = lx
					memo["climb_t"] = 0
		elif best == INF:
			var cx := w.bounds.get_center().x
			if absf(cx - p.x) > 200.0:
				dir = 1 if cx > p.x else -1
	var flip: int = memo.get("flip", 1)
	if int(memo.get("flip_t", 0)) > 0:
		memo["flip_t"] = int(memo.flip_t) - 1
		dir = flip
		down = false
	if dir != 0 and absf(p.x - float(memo.get("last_x", p.x))) < 0.2 and w.player.fh >= 0:
		memo["stuck"] = int(memo.get("stuck", 0)) + 1
		if int(memo.stuck) > 15:
			memo["flip"] = -dir
			memo["flip_t"] = 45
			memo["stuck"] = 0
			mi.jump_pressed = true
	else:
		memo["stuck"] = 0
	memo["last_x"] = p.x
	mi.left = dir < 0
	mi.right = dir > 0
	if w.player.fh >= 0:
		if down and int(memo.get("down_cd", 0)) <= 0:
			mi.down = true
			mi.jump_pressed = true
			memo["down_cd"] = 60
		elif dir != 0:
			var ahead: float = nearest[0 if dir < 0 else 1]
			if ahead > 25.0 and ahead < 75.0:
				mi.jump_pressed = true
	memo["down_cd"] = int(memo.get("down_cd", 0)) - 1
	# Airborne next to the rope it jumped for: hold Up so the hands catch it.
	if memo.has("climb_x") and w.player.fh < 0 and absf(p.x - float(memo.climb_x)) <= 10.0:
		mi.up = true
	mi.jump_held = mi.jump_pressed
	return mi


static func _useful_portal(w: RunWorld, escaping: bool) -> Dictionary:
	if w.player.fh < 0 or w.portals.links.is_empty():
		return {}
	var p := w.player.pos
	var pk := w.pickups
	var best := INF
	for i in pk.capacity():
		if pk.active[i] != 0:
			best = minf(best, _drop_distance(p, Vector2(pk.x[i], pk.y[i])))
	if best == INF and not escaping:
		return {}
	var chosen := {}
	var safer := {}
	var safety := _mob_danger(w, p) if escaping else 0.0
	var plat := w.player_platform()
	for link: Dictionary in w.portals.links:
		var source: Vector2 = link.pos
		var f := w.fhm.find_below(source.x, source.y - float(w.portals.tuning.reach_above))
		if f < 0 or w.fhm.y_at(f, source.x) > source.y + float(w.portals.tuning.reach_below):
			continue
		var source_plat := w.fhm.platform_of(f)
		var plan := {"pos": source, "source": source, "same_floor": source_plat == plat, "hop": false, "hop_dir": 0.0}
		if source_plat != plat:
			var edge := w.nav_jump.route_near(plat, source_plat, p.x)
			if edge < 0:
				continue
			var e := w.nav_jump.edge(edge)
			plan.pos = Vector2(clampf(source.x, float(e.lo), float(e.hi)), p.y)
			plan.hop = String(e.kind) == "jump"
			plan.hop_dir = signf(float(e.vx))
		if w.fhm.walk_blocked(plat, p.x, plan.pos.x):
			continue
		var arrival: Vector2 = link.target_pos - Vector2(0, float(w.portals.tuning.arrival_lift))
		if escaping and absf(source.x - p.x) <= BLOCK_DIST:
			var danger := _mob_danger(w, arrival)
			if danger < safety:
				safety = danger
				safer = plan
		for i in pk.capacity():
			if pk.active[i] == 0:
				continue
			var cost := absf(source.x - p.x) + _drop_distance(arrival, Vector2(pk.x[i], pk.y[i]))
			if cost < best:
				best = cost
				chosen = plan
	return safer if not safer.is_empty() else chosen


static func _mob_danger(w: RunWorld, point: Vector2) -> float:
	# tier C: the same nearby-mob box and distance weights as the existing kiting decision.
	var danger := 0.0
	for i in w.swarm.capacity():
		if w.swarm.active[i] == 0:
			continue
		var dx := w.swarm.x[i] - point.x
		var dy := w.swarm.y[i] - point.y
		if dy >= -140.0 and dy <= 90.0 and absf(dx) <= 450.0:
			danger += 1.0 / (absf(dx) + 30.0)
	return danger


static func _drop_distance(from: Vector2, to: Vector2) -> float:
	# tier C: match the bot's existing preference for horizontal travel over changing floors.
	return absf(to.x - from.x) + absf(to.y - from.y) * 2.0


## The nearest ladder or rope that starts on the bot's platform (its bottom at most LADDER_JUMP_REACH above the floor
## under it) and leads up; -1 when none.
static func climb_ladder(w: RunWorld) -> int:
	var l := w.ladders
	if l == null:
		return -1
	var plat := w.player_platform()
	var p := w.player.pos
	var best := -1
	var best_d := INF
	for i in l.x.size():
		if l.y1[i] > p.y - 40.0:
			continue
		var f := w.fhm.find_below(l.x[i], l.y2[i] - 2.0)
		if f < 0 or w.fhm.platform_of(f) != plat:
			continue
		if w.fhm.y_at(f, l.x[i]) - l.y2[i] > LADDER_JUMP_REACH:
			continue
		var d := absf(l.x[i] - p.x)
		if d < best_d:
			best_d = d
			best = i
	return best


## Resolves an open window like a player who always takes the first available job (else "Not now") and the card
## pick_card_for() prefers (`first_card` = true: always the first card). Returns how many choices were made.
static func auto_choose(w: RunWorld, first_card := false) -> int:
	var guard := 0
	var made := 0
	while guard < 64 and (w.state == RunWorld.CHOOSING_JOB or w.state == RunWorld.CHOOSING_UPGRADE):
		guard += 1
		made += 1
		if w.state == RunWorld.CHOOSING_JOB:
			var job := pick_job(w.pending_jobs)
			if job < 0 or not w.apply_job(job):
				w.decline_job()
		else:
			w.apply_choice(pick_card(w.pending_cards) if first_card else pick_card_for(w, w.pending_cards))
	return made


## The option a first-available player takes in a job window: the first available job id, -1 = "Not now".
static func pick_job(options: Array) -> int:
	for o: Variant in options:
		if o is Dictionary and bool((o as Dictionary).get("available", false)):
			return int(o.job_id)
	return -1


## The card a first-card player takes ("" when there is none).
static func pick_card(cards: Array) -> String:
	if cards.is_empty() or not (cards[0] is Dictionary):
		return ""
	return String(cards[0].get("id", ""))


## The card a sensible player takes from `cards` in run `w` (the highest card_score; ties: the earlier card).
static func pick_card_for(w: RunWorld, cards: Array) -> String:
	var best := ""
	var best_score := -INF
	for c: Variant in cards:
		if not (c is Dictionary):
			continue
		var sc := card_score(w, c)
		if sc > best_score:
			best_score = sc
			best = String(c.get("id", ""))
	return best


## How much a sensible player wants card `c` (a choice_pending card) now; see the class doc.
static func card_score(w: RunWorld, c: Dictionary) -> float:
	var d := w.upgrades.card(String(c.get("id", "")))
	if d.is_empty():
		return 0.0
	var kind := String(d.get("kind", ""))
	var effects: Array = d.get("effects", [])
	var stat := String(effects[0].get("stat", "")) if not effects.is_empty() and effects[0] is Dictionary else ""
	if kind == "potion_tier":
		return SCORE_POTION_TIER
	var key := String(d.get("skill", ""))
	if key == "":
		return float(SCORE_PLAYER.get(stat, SCORE_MOD_OTHER))
	var sd := w.book.def(key)
	var attack := String(sd.get("kind", "")) in ["projectile", "instant"]
	var sj := int(sd.get("job", -1))
	var pj := w.progression.job_id
	var bonus := SCORE_JOB_BONUS if sj == pj or (sj > 0 and w.jobs.is_descendant(pj, sj)) else 0.0
	match kind:
		"skill_new":
			return SCORE_NEW_ATTACK if attack else SCORE_NEW_PASSIVE
		"skill_rank":
			return (SCORE_RANK_ATTACK if attack else SCORE_RANK_PASSIVE) + bonus
	return float(SCORE_MOD.get(stat, SCORE_MOD_OTHER)) + bonus
