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
## heads back toward the middle of the map. When it has not moved for a while it jumps: on over a wall low enough to
## clear, otherwise turning around; a wall it could not clear is remembered for a while (goals beyond it are skipped and
## it bounds the kiting room like the map edge, #259).
## Same-map portals are approached when they shorten the trip to drops or leave nearby danger for a safer floor.
## The bot reads the jump graph to reach an entrance ledge and holds Up through the portal chain; mob nav is unchanged.
##
## Choices (auto_choose): the upgrade card a sensible player would take (pick_card_for):
## a new attack skill first, then more shots / pierce / damage / rank for the attack skills of the current job, then
## defence, then the rest; ties go to the earlier card. Each step a card grants beyond the first adds SCORE_GAIN_STEP
## (balance bot.gain_step_score), so a higher-tier offer outscores the same card at Normal tier. pick_card() is the
## plain "first card" policy.

## The map edge counts as this much danger / (distance + 10) on its side.
const EDGE_DANGER := 4.0
## A mob nearer than this (px, on about the bot's level) makes it flee.
const FLEE_DIST := 160.0
## tier C: a mob within this height of the feet (px) is on the bot's level (threats, melee engaging).
const DUEL_DY := 40.0
## tier C: five seconds leaves several auto-cast cycles and ordinary kiting between emergency blink requests.
const TELEPORT_MIN_INTERVAL := 5.0
## tier C (#302): three seconds between Rush dashes (the 2.0 s cooldown plus room for ordinary kiting), and a dash needs
## room to cover at least this share of its reach, else it would only bump the nearest wall or ledge.
const RUSH_MIN_INTERVAL := 3.0
const RUSH_LANE_FRACTION := 0.5
## tier C (#257): after a same-map warp the reverse link (back to where it came from) stays closed this long (s), so
## an escape through a two-way pair (Perion's hide00/tohide00) is not undone by the drop route on the next portal
## cooldown, straight back into the crowd it fled.
const REVERSE_PORTAL_HOLD := 5.0
## Walls (#259). tier C: ticks without moving toward its goal before the bot treats itself as stuck (the old flip rule).
const STUCK_TICKS := 15
## tier C: a wall the bot is stuck at counts as a step it can jump when no wall stands this share of the jump's apex
## (Physics.img jumpSpeed^2 / 2 gravityAcc, ~77 px) above its feet. 0.85 (~65 px): the jump rises flush against the
## wall before it moves on, so only a small margin is needed, and the synthetic map's 60 px pit walls count as steps.
const STEP_CLEAR_FRACTION := 0.85
## tier C: how far ahead (px) the stuck bot looks for the wall that stops it (it stands 0.01 px from it).
const WALL_PROBE_AHEAD := 4.0
## tier C: after the bot is stuck at a wall too tall to jump, goals beyond it (drops, ladders, the map centre) are ignored
## for this long (s, renewed at every new stall there) while the bot is on the near side and within WALL_BAND px of the
## height it stood at, so it stops walking back into the wall (Kerning City Construction Site's x 350 pocket).
const WALL_HOLD := 30.0
const WALL_BAND := 140.0
## tier C: with nothing else to do and the map centre beyond such a wall, the bot walks away from it until this far (px).
const WALL_CLEAR := 300.0
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
## tier C (#509): the bot walks to a scheduled boss that has stood alive this long (s) farther than BOSS_HUNT_GAP away on its own
## level, instead of keeping to the swarm around it. A boss that casts nearly all the time (the Timer holds a 3.1 s stance
## continuously) hardly walks and, in a stance, is never relocated to the character, so without this the bot never met it (2 of
## C13's 7 Ludibrium attempts ended TIMEOUT at 1800 s with the Timer alive 865 s). The gap is beyond a screen's half-width so a
## boss that does come to the bot, or that a kiting build keeps its distance from, is left to the ordinary rules.
const BOSS_HUNT_AFTER := 45.0
const BOSS_HUNT_GAP := 700.0
## A mob nearer than this (px, on the drop's side and before it) keeps the bot from walking to a drop.
const BLOCK_DIST := 250.0
## Climbing: drops above needed to go up; the highest rope bottom (px above the floor) reachable with a jump; a rope
## bottom higher than LADDER_STAND_REACH above the feet needs that jump; ticks before a climb attempt is given up.
const CLIMB_MIN_DROPS := 4
const LADDER_JUMP_REACH := 115.0
const LADDER_STAND_REACH := 45.0
const CLIMB_GIVE_UP := 8 * 60

## tier C: Card scores of pick_card_for (higher = taken first). Skill-mod stats not listed score SCORE_MOD_OTHER.
const SCORE_NEW_ATTACK := 100.0
const SCORE_NEW_PASSIVE := 50.0
const SCORE_RANK_ATTACK := 62.0
const SCORE_RANK_PASSIVE := 42.0
## tier C: area defaults to 58, like pierce (spec #31 foundations); other modifier scores retain their defaults.
const SCORE_MOD := {"count": 75.0, "damage": 64.0, "pierce": 58.0, "area": 58.0, "cooldown": 54.0, "range": 30.0, "speed": 20.0}
const SCORE_MOD_OTHER := 25.0
## Bonus for cards of a skill of the player's current job (a Magician invests in Magician skills).
const SCORE_JOB_BONUS := 12.0
# tier C: bot card scoring defaults; survivor policy weights.
const SCORE_PLAYER := {"max_hp": 46.0, "hp_regen": 36.0, "pdd": 34.0, "speed": 26.0}
## tier C: score added per step a card grants beyond its first (`c.magnitude - 1`); survivor balance.json bot.gain_step_score
## overrides it. 6 lets a Rare or Epic offer pass the cards just below it (a Rare +2 attack rank, 62+12+6 = 80, passes a
## Normal pierce card, 70). A Unique stacking card (+4 shots, 87+18 = 105) and a Legendary +8 attack rank
## (62+12+6*7 = 116) pass a Normal new attack skill (100); a Unique +5 attack rank is 98 and a +2 passive rank
## 54+6 = 60. A higher-tier new attack skill (106-124) passes a Normal one, as it should. A Legendary clamped to the
## ranks left scores the gain it grants (+6 ranks: 104). Gains only add, so this never reorders Normal offers.
const SCORE_GAIN_STEP := 6.0


## The input for the next tick of `w`.
static func decide(w: RunWorld, memo: Dictionary) -> MoveInput:
	if int(memo.get("map_index", 0)) != w.map_index:
		for key: String in ["portal_x", "climb_x", "climb_t", "flip", "flip_t", "stuck", "last_x", "down_cd", "closed",
				"wall"]:
			memo.erase(key)
	memo["map_index"] = w.map_index
	var mi := MoveInput.new()
	var guard := float(w.balance.get("potions", {}).get("bot", {}).get("min_restore_fraction", 0.5))
	var ps := w.player_state
	mi.drink_hp = worth_drinking(w, "hp", float(ps.max_hp) - float(ps.hp), guard)
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
	var profile := _reach_profile(w, float(engage.kite_reach))
	var melee: bool = profile.x > 0.0 and profile.x < float(engage.kite_reach)
	var engage_target := -1
	var engage_gap := INF
	var danger := [0.0, 0.0]
	var nearest := [INF, INF]
	var threat_nearest := [INF, INF]
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
		# tier C: emergency blinks use the on-level height band, not mobs on remote platforms.
		if absf(dy) <= DUEL_DY:
			threat_nearest[side] = minf(threat_nearest[side], absf(dx))
			if absf(dx) <= surround_distance:
				surrounding += 1
		if melee and absf(dy) <= DUEL_DY and absf(dx) <= float(engage.chase_range) and absf(dx) < engage_gap:
			engage_gap = absf(dx)
			engage_target = i
	var room := [p.x - w.bounds.position.x, w.bounds.end.x - p.x]
	# tier C (#259): a wall the bot got stuck at bounds its room like the map edge, so it does not flee into that dead end.
	var held := _held_wall(w, memo)
	if held != 0:
		var k := 0 if held < 0 else 1
		room[k] = minf(room[k], absf(p.x - float(memo.wall.x)))
	danger[0] += EDGE_DANGER / (room[0] + 10.0)
	danger[1] += EDGE_DANGER / (room[1] + 10.0)
	var teleport := w.teleport_skill()
	if teleport != "" and w.can_cast() \
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
	# tier C (#302): the manual damaging dash (Rush) leaves a mob within its threat distance on the bot's level, away from it
	# when that lane is free, else through the crowd; never toward a mob that is not an emergency.
	var rush := w.manual_skill("rush")
	if rush != "" and w.can_cast() and float(w.skill_readiness(rush).left) <= 1e-6 \
			and w.time - float(memo.get("rush_at", -INF)) >= RUSH_MIN_INTERVAL - 1e-6 \
			and minf(threat_nearest[0], threat_nearest[1]) < float(w.book.def(rush).rush.bot_threat_distance):
		var reach := float(w.runner.stats_of(w, rush).displacement.distance)
		var away := -1 if danger[0] < danger[1] else 1
		for side: int in [away, -away]:
			var lane: Dictionary = w.player.dash_destination(side, reach, w.fhm, w.bounds)
			if not lane.is_empty() and float(lane.moved) >= reach * RUSH_LANE_FRACTION:
				mi.left = side < 0
				mi.right = side > 0
				mi.press_skill("rush")
				memo["rush_at"] = w.time
				return mi
	# tier C (#188): a manual flee buff (Dash) is pressed when HP is low with a mob close, or when mobs surround the bot.
	if not flee_buff.is_empty():
		var low_hp: bool = float(w.player_state.hp) < float(w.player_state.max_hp) * float(flee_buff.hp) \
				and minf(nearest[0], nearest[1]) < FLEE_DIST
		if low_hp or surrounding >= int(flee_buff.count):
			mi.press_skill(String(flee_buff.id))
	var dir := 0
	var down := false
	_note_arrival(w, memo)
	var portal := _useful_portal(w, minf(nearest[0], nearest[1]) < 160.0, memo)
	if not portal.is_empty():
		PortalApproach.steer(w, portal, mi)
		memo["portal_x"] = portal.source.x
		memo.erase("climb_x")
		memo.erase("flip_t")
		memo["stuck"] = 0
		memo["last_x"] = p.x
		return mi
	memo.erase("portal_x")
	var hunt := 0 if _backing_off(w, engage) else _boss_hunt_direction(w, bool(memo.get("hunting", false)), float(engage.chase_range))
	memo["hunting"] = hunt != 0
	var engaging := engage_target >= 0 and hunt == 0 and not _backing_off(w, engage)
	if hunt != 0:
		dir = hunt
	elif engaging:
		# tier C: walk to the engage distance of the nearest on-level mob, then stand facing it (one press turns).
		var side := 1 if s.x[engage_target] > p.x else -1
		if engage_gap > float(profile.y) * float(engage.reach_fraction):
			dir = side
		elif engage_gap > float(engage.deadzone) and w.player.facing != side:
			dir = side
	elif minf(nearest[0], nearest[1]) < FLEE_DIST:
		dir = -1 if danger[0] < danger[1] else 1
	else:
		var best := INF
		var reach_up := w.magnet_r * 0.7
		var above := 0
		var pk := w.pickups
		for i in pk.capacity():
			if pk.active[i] == 0 or not _can_take(w, i) or _beyond_wall(w, memo, pk.x[i]):
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
		var lad := climb_ladder(w, memo) if best == INF and above >= CLIMB_MIN_DROPS else -1
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
			if _beyond_wall(w, memo, cx):
				if absf(p.x - float(memo.wall.x)) < WALL_CLEAR:
					dir = -int(memo.wall.side)
			elif absf(cx - p.x) > 200.0:
				dir = 1 if cx > p.x else -1
	var flip: int = memo.get("flip", 1)
	if int(memo.get("flip_t", 0)) > 0:
		memo["flip_t"] = int(memo.flip_t) - 1
		dir = flip
		down = false
	if dir != 0 and absf(p.x - float(memo.get("last_x", p.x))) < 0.2 and w.player.fh >= 0:
		memo["stuck"] = int(memo.get("stuck", 0)) + 1
		if int(memo.stuck) > STUCK_TICKS:
			memo["stuck"] = 0
			mi.jump_pressed = true
			# tier C (#259): a low wall (a step) is jumped going on; a taller one turns the bot back and is remembered.
			var wall := _wall_ahead(w, dir)
			var step := wall >= 0 and _step_jumpable(w, dir)
			if not step:
				memo["flip"] = -dir
				memo["flip_t"] = 45
			if wall >= 0 and not step:
				memo["wall"] = {"x": w.fhm.x1[wall], "y": p.y, "side": dir, "until": w.time + WALL_HOLD}
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
		elif dir != 0 and not engaging:
			var ahead: float = nearest[0 if dir < 0 else 1]
			if ahead > 25.0 and ahead < 75.0:
				mi.jump_pressed = true
	memo["down_cd"] = int(memo.get("down_cd", 0)) - 1
	# Airborne next to the rope it jumped for: hold Up so the hands catch it.
	if memo.has("climb_x") and w.player.fh < 0 and absf(p.x - float(memo.climb_x)) <= 10.0:
		mi.up = true
	mi.jump_held = mi.jump_pressed
	return mi


## -1 / 1 toward a scheduled boss of the entered map that has been alive BOSS_HUNT_AFTER s and stands on the bot's level farther
## than BOSS_HUNT_GAP away, and (`hunting`, the previous tick's answer) on until it is within `chase_range`; 0 when there is none.
static func _boss_hunt_direction(w: RunWorld, hunting: bool, chase_range: float) -> int:
	for record: Dictionary in w.bosses.records:
		var slot := int(record.slot)
		if slot < 0 or bool(record.dead) or not w.swarm.is_live(slot) or float(record.spawn_time) < 0.0 \
				or w.time - float(record.spawn_time) < BOSS_HUNT_AFTER:
			continue
		if w.map_sequence_enabled() and int(record.get("map_index", -1)) != w.map_index:
			continue
		var dx := w.swarm.x[slot] - w.player.pos.x
		if absf(w.swarm.y[slot] - w.player.pos.y) <= DUEL_DY and absf(dx) > (chase_range if hunting else BOSS_HUNT_GAP):
			return 1 if dx > 0.0 else -1
	return 0


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


## (longest attack reach the build owns, longest reach that is ready now), px. Counts the active damaging skills
## (SkillRunner.reach_of); ready = off cooldown with enough HP. Beginner (job 0) skills such as Three Snails only count while the build has no attack of its own job
## line, so a Warrior's long starter shot does not make it kite. (0, 0) = nothing can attack. A skill that pays HP (`hp_cost` > 0)
## or waits on an HP gate (`hp_gate` > 0) never counts with a reach of `kite_reach` or more (`kite_reach` < 0 reads the engage
## config): tier C, spec #348 DK-9, so Dragon Fury (241 px) and Dragon Roar (400 px) do not make a melee knight kite like an
## archer, while a short HP-paying skill such as Slash Blast keeps counting.
static func _reach_profile(w: RunWorld, kite_reach: float) -> Vector2:
	var line := Vector2.ZERO
	var base := Vector2.ZERO
	for key: String in w.loadout.order:
		if not w.loadout.book.is_active(key):
			continue
		var st := w.runner.stats_of(w, key)
		var r := SkillRunner.reach_of(st, w)
		if r <= 0.0:
			continue
		if r >= kite_reach and HpRisk.pays_hp(st):
			continue
		var ready := float(w.runner.cooldowns.get(key, 0.0)) <= 1e-6 and HpRisk.admits(w, st)
		var own := Vector2(r, r if ready else 0.0)
		if int(w.book.def(key).get("job", 0)) == 0:
			base = Vector2(maxf(base.x, own.x), maxf(base.y, own.y))
		else:
			line = Vector2(maxf(line.x, own.x), maxf(line.y, own.y))
	return line if line.x > 0.0 else base


## Whether the bot can collect pickup `i` now: an equipment drop needs room in the Equip tab (a full one never takes it,
## so chasing it would camp the bot on the drop); every other kind is always takable.
static func _can_take(w: RunWorld, i: int) -> bool:
	return w.pickups.kind[i] != PickupSystem.EQUIP or w.equipment.inventory.size() < w.inventory_slots()


## The manual flee buff the bot can press now ({} when it owns none, or it is running, cooling down or cannot pay its HP cost):
## {id (skill key), hp (flee below this HP fraction), count (mobs
## on its level that surround it), distance (px)}, read from the skill's `manual` block (survivor data, tier C).
static func _flee_buff(w: RunWorld) -> Dictionary:
	for key: String in w.loadout.order:
		var id := w.skill_key_of(key)
		var def := w.book.def(key)
		if id == "" or def.has("teleport") or w.book.kind(key) != "buff" or not def.has("manual") \
				or w.buffs.has(key) or float(w.runner.cooldowns.get(key, 0.0)) > 1e-6 \
				or not w.can_cast():
			continue
		var st := w.runner.stats_of(w, key)
		if not HpRisk.admits(w, st):
			continue
		var manual: Dictionary = def.manual
		return {"id": id, "hp": float(manual.get("bot_flee_hp", 0.0)), "count": int(manual.get("bot_surround_count", 99)),
			"distance": float(manual.get("bot_surround_distance", 0.0))}
	return {}


## tier C: drink a `kind` potion only when its cooldown is ready and `missing` is at least `guard` of one potion's canonical
## restore, so most of it lands below the pool cap. The restore counts only up to the max HP pool (#229: the
## 1000-2000 point steps restore more than a pool holds, and would otherwise never be worth drinking), but never as less
## than `potions.bot.pool_floor` of the potion, so a tiny pool never wastes a big potion.
static func worth_drinking(w: RunWorld, kind: String, missing: float, guard: float) -> bool:
	var restore := w.potions.restore_amount(kind)
	var floor_share := float(w.balance.get("potions", {}).get("bot", {}).get("pool_floor", 0.25))
	var amount := maxf(minf(float(restore), float(w.player_state.get("max_" + kind, 0))), floor_share * restore)
	return restore > 0 and w.potions.is_ready(kind) and missing >= guard * amount


## Just warped (the portal cooldown is running and the feet are at a link's arrival): closes that link's reverse
## (the link from its target back to its source) for REVERSE_PORTAL_HOLD seconds (#257).
static func _note_arrival(w: RunWorld, memo: Dictionary) -> void:
	if w.portals.cooldown_left <= 0.0:
		return
	var lift := float(w.portals.tuning.arrival_lift)
	for link: Dictionary in w.portals.links:
		var arrival: Vector2 = link.target_pos - Vector2(0, lift)
		if w.player.pos.distance_to(arrival) <= lift + 1.0:
			memo["closed"] = {"link": [String(link.target), String(link.name)], "until": w.time + REVERSE_PORTAL_HOLD}
			return


static func _useful_portal(w: RunWorld, escaping: bool, memo: Dictionary) -> Dictionary:
	if w.player.fh < 0 or w.portals.links.is_empty():
		return {}
	var closed_memo: Dictionary = memo.get("closed", {})
	var closed: Array = closed_memo.link if w.time < float(closed_memo.get("until", -INF)) else []
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
		if closed == [String(link.name), String(link.target)]:
			continue
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


## The wall within WALL_PROBE_AHEAD px of the feet in direction `dir` (FootholdMap.wall_hit), or -1.
static func _wall_ahead(w: RunWorld, dir: int) -> int:
	var p := w.player.pos
	return w.fhm.wall_hit(p.x, p.y, p.x + dir * WALL_PROBE_AHEAD, p.y, w.player.walls_of(w.fhm))


## True when no wall stands in direction `dir` at STEP_CLEAR_FRACTION of the jump's apex above the feet, so a jump
## going on clears the wall that stops the bot.
static func _step_jumpable(w: RunWorld, dir: int) -> bool:
	var apex := w.physics.jump_speed * w.physics.jump_speed / (2.0 * w.physics.gravity_acc)
	var p := w.player.pos
	var y := p.y - apex * STEP_CLEAR_FRACTION
	return w.fhm.wall_hit(p.x, y, p.x + dir * WALL_PROBE_AHEAD, y, w.player.walls_of(w.fhm)) < 0


## True while the wall the bot got stuck at (#259) still bars the way (_held_wall) and x lies past it.
static func _beyond_wall(w: RunWorld, memo: Dictionary, x: float) -> bool:
	var side := _held_wall(w, memo)
	return side != 0 and (x - float(memo.wall.x)) * side > 0.0


## The side (-1 left, 1 right) of a wall the bot got stuck at (#259, `memo.wall` {x, y, side, until}) while it still
## bars the way: the hold is running, the bot is on the wall's near side and within WALL_BAND px of the height it stood
## at; 0 otherwise.
static func _held_wall(w: RunWorld, memo: Dictionary) -> int:
	var wall: Dictionary = memo.get("wall", {})
	if w.time >= float(wall.get("until", -INF)):
		return 0
	var side := int(wall.side)
	var p := w.player.pos
	if (p.x - float(wall.x)) * side < 0.0 and absf(p.y - float(wall.y)) <= WALL_BAND:
		return side
	return 0


## The nearest ladder or rope that starts on the bot's platform (its bottom at most LADDER_JUMP_REACH above the floor
## under it) and leads up, and not beyond a wall the bot got stuck at (`memo`, #259); -1 when none.
static func climb_ladder(w: RunWorld, memo: Dictionary = {}) -> int:
	var l := w.ladders
	if l == null:
		return -1
	var plat := w.player_platform()
	var p := w.player.pos
	var best := -1
	var best_d := INF
	for i in l.x.size():
		if l.y1[i] > p.y - 40.0 or _beyond_wall(w, memo, l.x[i]):
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


## Resolves an open card window with the card pick_card_for() prefers (`first_card` = true: always the first card).
## Returns how many choices were made.
static func auto_choose(w: RunWorld, first_card := false) -> int:
	var guard := 0
	var made := 0
	while guard < 64 and w.state == RunWorld.CHOOSING_UPGRADE:
		guard += 1
		made += 1
		w.apply_choice(pick_card(w.pending_cards) if first_card else pick_card_for(w, w.pending_cards))
	return made


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
## 1). The Elixir filler scores its base, regardless of magnitude; a
## card the pool does not know scores 0 (a meter-gated finisher scores like any pool skill, #305: class-owned balance.bot.card_scores gives
## its cards new 100 and rank 74). #293 adds a global-passive preference after three actives and scores
## Mastery by its diminished effect (100 points per unit), so a small repeat cannot crowd out a global boost.
static func card_score(w: RunWorld, c: Dictionary) -> float:
	var d := w.upgrades.card(String(c.get("id", "")))
	if d.is_empty():
		return 0.0
	var kind := String(d.get("kind", ""))
	if kind == "filler":
		return _base_score(w, d) # the Elixir fallback ignores magnitude even if a table ever gave it one
	var step := float(w.balance.get("bot", {}).get("gain_step_score", SCORE_GAIN_STEP))
	var bonus_score := 0.0
	# tier C: score the actual diminished effect, not the rarity label or fictitious ranks.
	for effect: Dictionary in c.get("rarity_bonus", {}).get("effects", []):
		var value := float(effect.get("value", 0.0))
		bonus_score += absf(value - 1.0) if String(effect.get("op", "add")) == "mul" else absf(value)
	var base := _base_score(w, d)
	var key := String(d.get("skill", ""))
	# tier C (#293): after three actives, global boosts beat a low-value rank, but learning an active wins.
	if w.book.def(key).get("common_passive", false) and w.loadout.slot_count("active") >= int(w.balance.get("bot", {}).get("passive_active_threshold", 0)):
		base += float(w.balance.get("bot", {}).get("passive_score_bonus", 0.0))
	# tier C (#293): Mastery scores its actual diminished bonus; a 20% improvement is worth 20 points.
	if String(c.get("card_kind", "")) == "mastery":
		return bonus_score * float(w.balance.get("bot", {}).get("mastery_bonus_score", 0.0))
	return base + bonus_score * step + step * float(maxi(int(c.get("magnitude", 1)), 1) - 1)


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
	# tier C: every curated pool skill shares the established new/rank bases.
	if key in w.jobs.skill_pool(w.job_id()) and kind in ["skill_new", "skill_rank"]:
		return 100.0 if kind == "skill_new" else 74.0
	var sd := w.book.def(key)
	var rule := String(sd.get("cast", {}).get("rule", ""))
	var attack := not SkillRunner.is_triggered_rule(rule) and (String(sd.get("kind", "")) in ["projectile", "instant"] or rule == "box")
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
