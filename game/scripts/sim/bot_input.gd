class_name BotInput
extends RefCounted
## A simple deterministic kiting bot that plays a RunWorld (autoplay in RunScene, the headless full-run tests and the
## run benchmark). Pure: it reads the world's state and returns a MoveInput; `memo` keeps its state between ticks.
##
## It scores the danger on each side (mobs on about its level, closer = worse, the map edge counts as a wall of mobs)
## and, when a mob is near, runs to the safer side, hopping over a mob right ahead; a lone ordinary mob while no attack
## skill can fire is instead dueled standing still, facing it, so the basic attack swings. With nothing near it walks to the
## nearest EXP drop that no mob stands in front of (a mob nearer than BLOCK_DIST; down-jumping to one just below).
## When the only drops left are on platforms above (at least CLIMB_MIN_DROPS), it walks to the nearest ladder or rope
## that starts on its platform and climbs it (jumping for a rope that hangs above the floor). With no drop at all it
## heads back toward the middle of the map. When it has not moved for a while it turns around and jumps.
## Same-map portals are approached when they shorten the trip to drops or leave nearby danger for a safer floor.
## The bot reads the jump graph to reach an entrance ledge and holds Up through the portal chain; mob nav is unchanged.
##
## Choices (auto_choose): a seeded random available job (optionally a forced first or second job: its first-job ancestor is taken at the first window, itself at the second), and the upgrade card a sensible player would take (pick_card_for):
## a new attack skill first, then more shots / pierce / damage / rank for the attack skills of the current job, then
## defence, then the rest; ties go to the earlier card. Each step a card grants beyond the first adds SCORE_GAIN_STEP
## (balance bot.gain_step_score), so a higher-tier offer outscores the same card at Normal tier. pick_card() is the
## plain "first card" policy.

## The map edge counts as this much danger / (distance + 10) on its side.
const EDGE_DANGER := 4.0
## A mob nearer than this (px, on about the bot's level) makes it flee, or duel when it is the only one.
const FLEE_DIST := 160.0
## tier C: a mob within this height of the feet (px) is on the bot's level for a sword duel.
const DUEL_DY := 40.0
## tier C: a manual skill (Teleport, Dash) leaves a quarter of the pool for Magic Guard, or two most-expensive learned auto
## attacks, whichever is larger.
const MANUAL_SKILL_MP_RESERVE_FRACTION := 0.25
## tier C: one attack plus an equal combat margin, even for a small MP pool or costly learned attack.
const MANUAL_SKILL_ATTACK_RESERVE_CASTS := 2.0
## tier C: five seconds leaves several auto-cast cycles and ordinary kiting between emergency blink requests.
const TELEPORT_MIN_INTERVAL := 5.0
## Engage mode (balance.json bot.engage overrides these). tier C: a build whose longest attack reaches less than this (px)
## walks up to mobs instead of kiting; 220 sits below every Magician attack (Magic Claw 260 is the shortest) and above
## the one-handed swings (~90-130).
const ENGAGE_KITE_REACH := 220.0
## tier C: stop at this fraction of the longest ready attack's reach, so the body hit boxes still overlap its box.
const ENGAGE_REACH_FRACTION := 0.8
## tier C: only mobs this far (px) on the bot's level are engaged; farther ones leave the bot to its EXP drops.
const ENGAGE_CHASE_RANGE := 300.0
## tier C: below this HP fraction, or while a boss attack winds up, the melee bot kites like any other build.
const ENGAGE_RETREAT_HP := 0.35
## tier C: closer than this (px) to the engaged mob the bot keeps its facing instead of turning back and forth.
const ENGAGE_DEADZONE := 6.0
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
## tier C: area defaults to 58, like pierce (spec #31 foundations); other modifier scores retain their defaults.
const SCORE_MOD := {"count": 75.0, "damage": 64.0, "pierce": 58.0, "area": 58.0, "cooldown": 54.0, "range": 30.0, "speed": 20.0}
const SCORE_MOD_OTHER := 25.0
## Bonus for cards of a skill of the player's current job (a Magician invests in Magician skills).
const SCORE_JOB_BONUS := 12.0
const SCORE_PLAYER := {"max_hp": 46.0, "hp_regen": 36.0, "pdd": 34.0, "speed": 26.0, "magnet": 22.0, "max_mp": 16.0,
	"mp_regen": 16.0}
## tier C: permanent potion tier improvement is preferred to a general defence card, below attack ranks.
const SCORE_POTION_TIER := 52.0
## tier C: score added per step a card grants beyond its first (`c.magnitude - 1`); survivor balance.json bot.gain_step_score
## overrides it. 6 lets a Rare or Epic offer pass the cards just below it (a Rare +2 attack rank, 62+12+6 = 80, passes a
## Normal pierce card, 70). A Unique stacking card (+4 shots, 87+18 = 105) and a Legendary +8 attack rank
## (62+12+6*7 = 116) pass a Normal new attack skill (100); a Unique +5 attack rank is 98 and a +2 passive rank
## 54+6 = 60. A higher-tier new attack skill (106-124) passes a Normal one, as it should. A Legendary clamped to the
## ranks left scores the gain it grants (+6 ranks: 104). Gains only add, so this never reorders Normal offers.
const SCORE_GAIN_STEP := 6.0


## The input for the next tick of `w`.
static func decide(w: RunWorld, memo: Dictionary) -> MoveInput:
	var mi := MoveInput.new()
	var guard := float(w.balance.get("potions", {}).get("bot", {}).get("min_restore_fraction", 0.5))
	var ps := w.player_state
	mi.drink_hp = worth_drinking(w, "hp", float(ps.max_hp) - float(ps.hp), guard)
	mi.drink_mp = worth_drinking(w, "mp", float(ps.max_mp) - float(ps.mp), guard)
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
	# Engage mode (#162): a build whose attacks all reach less than kite_reach closes to its ready attack's reach.
	if not memo.has("engage"): # built once per run: balance.json does not change under a bot
		memo["engage"] = _engage_config(w)
	var engage: Dictionary = memo.engage
	var profile := _reach_profile(w)
	var melee: bool = profile.x > 0.0 and profile.x < float(engage.kite_reach)
	var engage_target := -1
	var engage_gap := INF
	var danger := [0.0, 0.0]
	var nearest := [INF, INF]
	var threat_nearest := [INF, INF]
	var close := 0
	var duel := -1
	var flee_buff := _flee_buff(w)
	var surround_distance := float(flee_buff.get("distance", 0.0))
	var surrounding := 0
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
		# tier C: emergency blinks use the existing duel-height band, not mobs on remote platforms.
		if absf(dy) <= DUEL_DY:
			threat_nearest[side] = minf(threat_nearest[side], absf(dx))
			if absf(dx) <= surround_distance:
				surrounding += 1
		if melee and absf(dy) <= DUEL_DY and absf(dx) <= float(engage.chase_range) and absf(dx) < engage_gap:
			engage_gap = absf(dx)
			engage_target = i
		if absf(dx) < FLEE_DIST:
			close += 1
			duel = i if absf(dy) <= DUEL_DY else -2
	var room := [p.x - w.bounds.position.x, w.bounds.end.x - p.x]
	danger[0] += EDGE_DANGER / (room[0] + 10.0)
	danger[1] += EDGE_DANGER / (room[1] + 10.0)
	var teleport := w.teleport_skill()
	if teleport != "" and w.can_cast() and w.teleport_affordable() and _keeps_mp_reserve(w, teleport) \
			and w.time - float(memo.get("teleport_at", -INF)) >= TELEPORT_MIN_INTERVAL - 1e-6:
		var reach := float(w.runner.stats_of(w, teleport).teleport_range)
		var threat_distance := float(w.book.def(teleport).teleport.bot_threat_distance)
		# tier C: both retreat sides blocked by mobs within flee distance, or an imminent threat against an edge.
		var cornered: bool = threat_nearest[0] < FLEE_DIST and threat_nearest[1] < FLEE_DIST
		var edge_trapped: bool = (room[0] < threat_distance and threat_nearest[1] < threat_distance) \
				or (room[1] < threat_distance and threat_nearest[0] < threat_distance)
		if cornered or edge_trapped or minf(threat_nearest[0], threat_nearest[1]) < threat_distance:
			var escape := (1 if room[1] > room[0] else -1) if edge_trapped else (-1 if danger[0] < danger[1] else 1)
			if not w.player.teleport_destination(Vector2(escape, 0), reach, w.fhm, w.bounds).is_empty():
				mi.left = escape < 0
				mi.right = escape > 0
				mi.press_skill("teleport")
				memo["teleport_at"] = w.time
				return mi
	# tier C (#188): a manual flee buff (Dash) is pressed when HP is low with a mob close, or when mobs surround the bot.
	if not flee_buff.is_empty():
		var low_hp: bool = float(w.player_state.hp) < float(w.player_state.max_hp) * float(flee_buff.hp) \
				and minf(nearest[0], nearest[1]) < FLEE_DIST
		if low_hp or surrounding >= int(flee_buff.count):
			mi.press_skill(String(flee_buff.id))
	var dir := 0
	var down := false
	var portal := _useful_portal(w, minf(nearest[0], nearest[1]) < 160.0)
	if not portal.is_empty():
		PortalApproach.steer(w, portal, mi)
		memo["portal_x"] = portal.source.x
		memo.erase("climb_x")
		memo.erase("flip_t")
		memo["stuck"] = 0
		memo["last_x"] = p.x
		return mi
	memo.erase("portal_x")
	var dueling := false
	var engaging := engage_target >= 0 and not _backing_off(w, engage)
	if engaging:
		# tier C: walk to the engage distance of the nearest on-level mob, then stand facing it (one press turns).
		var side := 1 if s.x[engage_target] > p.x else -1
		if engage_gap > float(profile.y) * float(engage.reach_fraction):
			dir = side
		elif engage_gap > float(engage.deadzone) and w.player.facing != side:
			dir = side
	elif minf(nearest[0], nearest[1]) < FLEE_DIST:
		dueling = close == 1 and duel >= 0 and _can_duel(w, duel)
		if dueling:
			# tier C: a lone ordinary mob while no attack skill can fire: stand facing it so the basic attack swings
			# (one tick of pressing toward it turns the bot).
			var side := 1 if w.swarm.x[duel] > p.x else -1
			dir = side if w.player.facing != side else 0
		else:
			dir = -1 if danger[0] < danger[1] else 1
	else:
		var best := INF
		var reach_up := w.magnet_r * 0.7
		var above := 0
		var pk := w.pickups
		for i in pk.capacity():
			if pk.active[i] == 0 or not _can_take(w, i):
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
		elif dir != 0 and not dueling and not engaging:
			var ahead: float = nearest[0 if dir < 0 else 1]
			if ahead > 25.0 and ahead < 75.0:
				mi.jump_pressed = true
	memo["down_cd"] = int(memo.get("down_cd", 0)) - 1
	# Airborne next to the rope it jumped for: hold Up so the hands catch it.
	if memo.has("climb_x") and w.player.fh < 0 and absf(p.x - float(memo.climb_x)) <= 10.0:
		mi.up = true
	mi.jump_held = mi.jump_pressed
	return mi


## The engage-mode constants: balance.json bot.engage over the tier C defaults above.
static func _engage_config(w: RunWorld) -> Dictionary:
	var cfg := {"kite_reach": ENGAGE_KITE_REACH, "reach_fraction": ENGAGE_REACH_FRACTION,
		"chase_range": ENGAGE_CHASE_RANGE, "retreat_hp": ENGAGE_RETREAT_HP, "deadzone": ENGAGE_DEADZONE}
	cfg.merge(w.balance.get("bot", {}).get("engage", {}), true)
	return cfg


## True when a melee build should fall back to kiting: HP below the retreat fraction, or a boss attack winding up.
static func _backing_off(w: RunWorld, engage: Dictionary) -> bool:
	return float(w.player_state.hp) < float(w.player_state.max_hp) * float(engage.retreat_hp) \
			or w.boss_attacks.telegraph_up()


## (longest attack reach the build owns, longest reach that is ready now), px. Counts the held weapon's swing
## (BasicAttack.reach, always ready) and the active damaging skills (SkillRunner.reach_of); ready = off cooldown and
## affordable. Beginner (job 0) skills such as Three Snails only count while the build has no attack of its own job
## line, so a Warrior's long starter shot does not make it kite. (0, 0) = nothing can attack.
static func _reach_profile(w: RunWorld) -> Vector2:
	var line := Vector2.ZERO
	var base := Vector2.ZERO
	for key: String in w.loadout.order:
		if not w.loadout.book.is_active(key) or not _usable(w, key):
			continue
		var st := w.runner.stats_of(w, key)
		var r := SkillRunner.reach_of(st, w)
		if r <= 0.0:
			continue
		var ready := float(w.runner.cooldowns.get(key, 0.0)) <= 1e-6 and _affordable(w, st)
		var own := Vector2(r, r if ready else 0.0)
		if int(w.book.def(key).get("job", 0)) == 0:
			base = Vector2(maxf(base.x, own.x), maxf(base.y, own.y))
		else:
			line = Vector2(maxf(line.x, own.x), maxf(line.y, own.y))
	var skills := line if line.x > 0.0 else base
	var swing := w.basic.reach(w)
	return Vector2(maxf(skills.x, swing), maxf(skills.y, swing))


## Whether the bot can collect pickup `i` now: an equipment drop needs room in the Equip tab (a full one never takes it,
## so chasing it would camp the bot on the drop); every other kind is always takable.
static func _can_take(w: RunWorld, i: int) -> bool:
	return w.pickups.kind[i] != PickupSystem.EQUIP or w.equipment.inventory.size() < w.inventory_slots()


## Whether the held weapon can use owned skill `key` (SkillBook.usable_with, spec #151 #156/#163): the bot's MP and reach
## scans skip a skill the runner would never cast.
static func _usable(w: RunWorld, key: String) -> bool:
	return w.book.usable_with(key, w.held_weapon_family())


## Whether the player can pay the MP and HP cost of resolved skill stats `st` now.
static func _affordable(w: RunWorld, st: Dictionary) -> bool:
	return float(w.player_state.mp) >= int(st.mp_cost) and w.can_pay_hp(int(st.hp_cost))


## The manual flee buff the bot can press now ({} when it owns none, or it is running, cooling down, blocked by the
## weapon, unaffordable or would eat the MP reserve): {id (skill key), hp (flee below this HP fraction), count (mobs
## on its level that surround it), distance (px)}, read from the skill's `manual` block (survivor data, tier C).
static func _flee_buff(w: RunWorld) -> Dictionary:
	for key: String in w.loadout.order:
		var id := w.skill_key_of(key)
		var def := w.book.def(key)
		if id == "" or def.has("teleport") or w.book.kind(key) != "buff" or not def.has("manual") \
				or not _usable(w, key) or w.buffs.has(key) or float(w.runner.cooldowns.get(key, 0.0)) > 1e-6 \
				or not w.can_cast():
			continue
		var st := w.runner.stats_of(w, key)
		if not _affordable(w, st) or not _keeps_mp_reserve(w, key):
			continue
		var manual: Dictionary = def.manual
		return {"id": id, "hp": float(manual.get("bot_flee_hp", 0.0)), "count": int(manual.get("bot_surround_count", 99)),
			"distance": float(manual.get("bot_surround_distance", 0.0))}
	return {}


## Whether paying manual skill `manual_key` (Teleport, Dash) still leaves the attack/Magic Guard MP reserve.
static func _keeps_mp_reserve(w: RunWorld, manual_key: String) -> bool:
	var reserve := float(w.player_state.max_mp) * MANUAL_SKILL_MP_RESERVE_FRACTION
	for key: String in w.loadout.order:
		if not w.book.is_active(key) or not _usable(w, key):
			continue
		var stats := w.runner.stats_of(w, key)
		if String(stats.kind) != "buff" and String(stats.cast_rule) != "manual" and String(stats.damage_type) != "none":
			reserve = maxf(reserve, float(stats.mp_cost) * MANUAL_SKILL_ATTACK_RESERVE_CASTS)
	return float(w.player_state.mp) - float(w.runner.stats_of(w, manual_key).mp_cost) >= reserve


## tier C: drink a `kind` potion only when stock remains and `missing` is at least `guard` of one potion's canonical
## restore, so most of it lands below the pool cap.
static func worth_drinking(w: RunWorld, kind: String, missing: float, guard: float) -> bool:
	var amount := w.potions.restore_amount(kind)
	return amount > 0 and int(w.potions.stock[kind].count) > 0 and missing >= guard * amount


## True when mob `i` is an ordinary (non-elite, non-boss) mob and no attack skill could fire now: every attack is
## cooling down or unaffordable, so standing still lets the basic attack swing instead.
static func _can_duel(w: RunWorld, i: int) -> bool:
	var kind: MobKind = w.mob_kinds[w.swarm.kind[i]]
	if kind.boss or w.mob_elite[i] != 0:
		return false
	for key: String in w.loadout.order:
		if not w.loadout.book.is_active(key) or not _usable(w, key) or float(w.runner.cooldowns.get(key, 0.0)) > 1e-6:
			continue
		var st := w.runner.stats_of(w, key)
		if String(st.kind) != "buff" and String(st.cast_rule) != "manual" and _affordable(w, st):
			return false
	return true


static func _useful_portal(w: RunWorld, escaping: bool) -> Dictionary:
	if w.player.fh < 0 or w.portals.links.is_empty():
		return {}
	var p := w.player.pos
	var pk := w.pickups
	var best := INF
	for i in pk.capacity():
		if pk.active[i] != 0 and _can_take(w, i):
			best = minf(best, _drop_distance(p, Vector2(pk.x[i], pk.y[i])))
	if best == INF and not escaping:
		return {}
	var chosen := {}
	var safer := {}
	var safety := _mob_danger(w, p) if escaping else 0.0
	for link: Dictionary in w.portals.links:
		var source: Vector2 = link.pos
		var plan := PortalApproach.plan(w, source)
		if plan.is_empty() or float(plan.floor_y) > source.y + float(w.portals.tuning.reach_below):
			continue
		var arrival: Vector2 = link.target_pos - Vector2(0, float(w.portals.tuning.arrival_lift))
		if escaping and absf(source.x - p.x) <= BLOCK_DIST:
			var danger := _mob_danger(w, arrival)
			if danger < safety:
				safety = danger
				safer = plan
		for i in pk.capacity():
			if pk.active[i] == 0 or not _can_take(w, i):
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


## Resolves an open window using a seeded available job (or the forced job, see pick_choice) and the card
## pick_card_for() prefers (`first_card` = true: always the first card). Returns how many choices were made.
static func auto_choose(w: RunWorld, first_card := false, forced_job := 0, forced_path := "") -> int:
	var guard := 0
	var made := 0
	while guard < 64 and (w.state == RunWorld.CHOOSING_JOB or w.state == RunWorld.CHOOSING_UPGRADE):
		guard += 1
		made += 1
		if w.state == RunWorld.CHOOSING_JOB:
			var pick := pick_choice(w.pending_jobs, w.job_rng, forced_job, w.jobs, forced_path)
			if pick.job_id < 0 or not w.apply_job(pick.job_id, pick.path):
				w.decline_job()
		else:
			w.apply_choice(pick_card(w.pending_cards) if first_card else pick_card_for(w, w.pending_cards))
	return made


## The window entry the bot takes: {job_id, path} (job_id -1 and path "" = "Not now"). A seeded available job, or the
## forced job (`forced`, 0 = none) when it is available; with `jobs` given, an available option that is an ancestor of
## `forced` counts too, so forcing a second job takes its first job at the first window. A forced or sole job needs no
## draw to select the job. A named forced path is used when the selected advancement offers it; otherwise every multi-family
## advancement draws uniformly on the same job stream (8). Zero/one-path jobs and RNG-less callers use the default.
static func pick_choice(options: Array, rng: RandomNumberGenerator = null, forced := 0, jobs: JobTree = null,
		forced_path := "") -> Dictionary:
	var available: Array[Dictionary] = []
	for o: Variant in options:
		if o is Dictionary and bool((o as Dictionary).get("available", false)):
			available.append(o)
	if available.is_empty():
		return {"job_id": -1, "path": ""}
	var ids := available.map(func(o: Dictionary) -> int: return int(o.job_id))
	var target := -1
	if forced in ids:
		target = forced
	elif forced > 0 and jobs != null:
		for id: int in ids:
			if jobs.is_descendant(forced, id):
				target = id
				break
	if target < 0:
		return _entry(available[rng.randi_range(0, available.size() - 1)] if available.size() > 1 and rng != null
			else available[0], forced_path, rng)
	for o: Dictionary in available:
		if int(o.job_id) == target:
			return _entry(o, forced_path, rng)
	return {"job_id": -1, "path": ""}


static func _entry(o: Dictionary, forced_path: String, rng: RandomNumberGenerator) -> Dictionary:
	var paths: Array = o.get("paths", [])
	for p: Dictionary in paths:
		if String(p.id) == forced_path:
			return {"job_id": int(o.job_id), "path": forced_path}
	# tier C (#226): one uniform family draw at every multi-family advancement unless its offered path is forced.
	if paths.size() >= 2 and rng != null:
		return {"job_id": int(o.job_id), "path": String(paths[rng.randi_range(0, paths.size() - 1)].id)}
	return {"job_id": int(o.job_id), "path": ""}


## The card a first-card player takes ("" when there is none).
static func pick_card(cards: Array) -> String:
	if cards.is_empty() or not (cards[0] is Dictionary):
		return ""
	return String(cards[0].get("id", ""))


## The card a sensible player takes from `cards` in run `w` (the highest card_score, which counts the ranks or steps the
## offer grants; ties: the earlier card).
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


## How much a sensible player wants card `c`: its base score (by kind / skill / stat, plus the current-job bonus;
## a survivor bot.card_scores entry replaces the base and gets no job bonus) plus gain_step_score for every step beyond
## the first that the offer grants (`c.magnitude`, the resolved ranks / steps / starting rank; missing or <= 0 counts as
## 1). Potion-tier cards score their configured tier_score and the Elixir filler its base, regardless of magnitude; a
## card the pool does not know scores 0.
static func card_score(w: RunWorld, c: Dictionary) -> float:
	var d := w.upgrades.card(String(c.get("id", "")))
	if d.is_empty():
		return 0.0
	var kind := String(d.get("kind", ""))
	if kind == "potion_tier":
		return float(w.balance.get("potions", {}).get("bot", {}).get("tier_score", SCORE_POTION_TIER))
	if kind == "filler":
		return _base_score(w, d) # the Elixir fallback ignores magnitude even if a table ever gave it one
	var step := float(w.balance.get("bot", {}).get("gain_step_score", SCORE_GAIN_STEP))
	return _base_score(w, d) + step * float(maxi(int(c.get("magnitude", 1)), 1) - 1)


## The score of card definition `d` before the gain term (Normal tier, one step).
static func _base_score(w: RunWorld, d: Dictionary) -> float:
	var overrides: Dictionary = w.balance.get("bot", {}).get("card_scores", {})
	if overrides.has(String(d.id)):
		return float(overrides[String(d.id)])
	var kind := String(d.get("kind", ""))
	var effects: Array = d.get("effects", [])
	var stat := String(effects[0].get("stat", "")) if not effects.is_empty() and effects[0] is Dictionary else ""
	var key := String(d.get("skill", ""))
	if key == "":
		return float(SCORE_PLAYER.get(stat, SCORE_MOD_OTHER))
	var sd := w.book.def(key)
	var rule := String(sd.get("cast", {}).get("rule", ""))
	var attack := rule != "manual" and (String(sd.get("kind", "")) in ["projectile", "instant"] or rule == "box")
	if String(sd.get("cast", {}).get("rule", "")) == "crowd":
		attack = false # Slow uses existing support scores (tier C), below damaging attacks.
	var sj := int(sd.get("job", -1))
	var pj := w.progression.job_id
	var bonus := SCORE_JOB_BONUS if sj == pj or (sj > 0 and w.jobs.is_descendant(pj, sj)) else 0.0
	match kind:
		"skill_new":
			return SCORE_NEW_ATTACK if attack else SCORE_NEW_PASSIVE
		"skill_rank":
			return (SCORE_RANK_ATTACK if attack else SCORE_RANK_PASSIVE) + bonus
	return float(SCORE_MOD.get(stat, SCORE_MOD_OTHER)) + bonus
