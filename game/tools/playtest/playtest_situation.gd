extends RefCounted
## The situation that travels with every decide message (spec #91): plain facts about the round right now plus named
## buckets computed in code, so the brain (Jev or the fallback rule table) judges meaning instead of doing arithmetic.
## Tool code only.
##
## `of(w, memory)` returns a stable shape that the Node side (tools/playtest/src/maple/) relies on; add keys, never
## rename or remove them:
##   state, time, level, job_id, job, hp, max_hp, mp, max_mp, kills, alive, skills, advancement, bonus   (facts)
##   buckets: {
##     hp, mp            "critical" | "low" | "ok" | "full"       share of the pool (an empty pool is "full")
##     mobs_near         "none" | "few" | "crowd" | "swarm"       live mobs in the NEAR box around the feet
##     mobs_near_step    0 | 1 | 2 | 3                            the same as an ordinal (trigger "mob bucket jumped")
##     boss              "none" | "present" | "attacking"         a living scheduled boss; attacking = it hit the player
##                                                                or started an attack within BOSS_ATTACK_S, or is close
##     potions_hp, potions_mp  "none" | "few" | "plenty"          potions in stock
##     drops_near        "none" | "some" | "many"                 drops on or below the player's level within DROP_NEAR_X
##     drops_above       "none" | "some" | "many"                 drops on platforms above, out of magnet reach
##     phase             "early" | "mid" | "late" | "boss"        thirds of the stage's own duration; boss = a boss lives
##     platform          int                                      FootholdMap platform under the player (-1 none)
##     recent_hits       "none" | "some" | "many"                 hits taken within RECENT_S (needs `memory`)
##   }
## Later tickets may add bucket keys; BUCKET_KEYS lists the ones every decide carries. Card and job decides also merge
## `brain_facts` (#94: owned skills, boss counts); tactic decides add `tactic` (tactic_decision.gd).
##
## Hits and boss attacks need memory across ticks: an instance of this script, fed every tick through `observe`
## (the playtest policy does that), is the `memory` argument. `of(w)` without memory reports no recent hits.

## Every bucket key `of` always fills.
const BUCKET_KEYS := ["hp", "mp", "mobs_near", "mobs_near_step", "boss", "potions_hp", "potions_mp", "drops_near",
	"drops_above", "phase", "platform", "recent_hits"]
## tier C: pool share below which HP/MP is critical / low, and at or above which it is full.
const POOL_CRITICAL := 0.25
const POOL_LOW := 0.5
const POOL_FULL := 0.95
## tier C: the "near" box of the balance metrics (balance_run.gd NEAR_X / NEAR_Y, px from the feet).
const NEAR_X := 300.0
const NEAR_Y := 150.0
## tier C: mobs near at which the count is "few" / "crowd" / "swarm".
const MOBS_FEW := 1
const MOBS_CROWD := 4
const MOBS_SWARM := 12
## tier C: potions in stock at which the stock is "plenty" (1 or more is "few").
const POTIONS_PLENTY := 5
## tier C: drops at which a count is "many" (1 or more is "some").
const DROPS_MANY := 6
## tier C: horizontal reach (px) of "drops near"; drops above use BotInput's climb window (1200 px).
const DROP_NEAR_X := 400.0
const DROP_ABOVE_X := 1200.0
## tier C: share of the magnet radius above the feet that still counts as the player's level (BotInput uses 0.7).
const DROP_REACH_UP := 0.7
## tier C: hits within this many seconds are "recent"; 3 or more are "many".
const RECENT_S := 5.0
const HITS_MANY := 3
## tier C: a boss is "attacking" for this long after it hits the player or starts an attack, or while it is within
## BOSS_CLOSE_X px horizontally (and on about the player's level, NEAR_Y).
const BOSS_ATTACK_S := 3.0
const BOSS_CLOSE_X := 200.0
## Stage duration used when the stage has none (s).
const DEFAULT_DURATION := 900.0

## Run times of recent hits (oldest first).
var _hits := PackedFloat32Array()
## Run time of the last boss hit or boss attack start (-INF: none).
var _boss_attack_t := -INF


## Folds one tick's events of `w` into the memory (the run loop's per-tick observer signature).
func observe(w: RunWorld, events: Array) -> void:
	for e: Dictionary in events:
		match String(e.get("type", "")):
			"player_hit":
				if not bool(e.get("miss", false)):
					_hits.append(w.time)
					if bool(e.get("boss", false)):
						_boss_attack_t = w.time
			"boss_attack":
				if String(e.get("phase", "")) == "start":
					_boss_attack_t = w.time
	while not _hits.is_empty() and w.time - _hits[0] > RECENT_S:
		_hits.remove_at(0)


## Hits taken within RECENT_S of run time `now`.
func recent_hits(now: float) -> int:
	var n := 0
	for t in _hits:
		if now - t <= RECENT_S + 1e-6:
			n += 1
	return n


## True when a boss hit the player or started an attack within BOSS_ATTACK_S of `now`.
func boss_attacked(now: float) -> bool:
	return now - _boss_attack_t <= BOSS_ATTACK_S + 1e-6


## Facts and buckets about run `w` for a decide message; `memory` is an instance of this script fed by `observe`
## (null: no recent hits, boss attacks only by distance).
static func of(w: RunWorld, memory: Variant = null) -> Dictionary:
	var ps := w.player_state
	var out := {
		"state": w.state_name(), "time": snappedf(w.time, 0.001), "level": int(ps.get("level", 0)),
		"job_id": int(ps.get("job_id", 0)), "job": w.jobs.name_of(int(ps.get("job_id", 0))),
		"hp": int(ps.get("hp", 0)), "max_hp": int(ps.get("max_hp", 0)),
		"mp": int(ps.get("mp", 0)), "max_mp": int(ps.get("max_mp", 0)),
		"kills": w.kills, "alive": w.swarm.alive_count(),
		"skills": w.loadout.order.map(func(k: String) -> String: return "%s:%d" % [k, w.loadout.rank(k)]),
		"advancement": w.choice_advancement, "bonus": w.choice_bonus,
	}
	out["buckets"] = buckets(w, memory)
	return out


## The named buckets of `w` (see the header); `memory` as in `of`.
static func buckets(w: RunWorld, memory: Variant = null) -> Dictionary:
	var ps := w.player_state
	var p := w.player.pos
	var near := mobs_near(w)
	var boss := "none"
	for i in w.swarm.capacity():
		if w.swarm.active[i] == 0 or not w.is_scheduled_boss(i):
			continue
		if boss == "none":
			boss = "present"
		if absf(w.swarm.x[i] - p.x) <= BOSS_CLOSE_X and absf(w.swarm.y[i] - p.y) <= NEAR_Y:
			boss = "attacking"
	if boss == "present" and memory != null and memory.boss_attacked(w.time):
		boss = "attacking"
	var drops := drops_around(w)
	return {
		"hp": pool_bucket(int(ps.get("hp", 0)), int(ps.get("max_hp", 0))),
		"mp": pool_bucket(int(ps.get("mp", 0)), int(ps.get("max_mp", 0))),
		"mobs_near": mobs_bucket(near), "mobs_near_step": mobs_step(near), "boss": boss,
		"potions_hp": potion_bucket(int(w.potions.stock.hp.count)),
		"potions_mp": potion_bucket(int(w.potions.stock.mp.count)),
		"drops_near": drops_bucket(drops.x), "drops_above": drops_bucket(drops.y),
		"phase": phase_bucket(w.time, float(w.stage.get("duration", DEFAULT_DURATION)), boss != "none"),
		"platform": w.player_platform(),
		"recent_hits": hits_bucket(memory.recent_hits(w.time) if memory != null else 0),
	}


## Live mobs within NEAR_X / NEAR_Y of the player's feet.
static func mobs_near(w: RunWorld) -> int:
	var s := w.swarm
	var p := w.player.pos
	var n := 0
	for i in s.capacity():
		if s.active[i] != 0 and absf(s.x[i] - p.x) <= NEAR_X and absf(s.y[i] - p.y) <= NEAR_Y:
			n += 1
	return n


## Vector2i(near, above): drops on or below the player's level within DROP_NEAR_X, and drops above it (out of magnet
## reach) within DROP_ABOVE_X.
static func drops_around(w: RunWorld) -> Vector2i:
	var pk := w.pickups
	var p := w.player.pos
	var reach_up := w.magnet_r * DROP_REACH_UP
	var out := Vector2i.ZERO
	for i in pk.capacity():
		if pk.active[i] == 0:
			continue
		var dx := absf(pk.x[i] - p.x)
		if pk.y[i] - p.y < -reach_up:
			out.y += 1 if dx <= DROP_ABOVE_X else 0
		elif dx <= DROP_NEAR_X:
			out.x += 1
	return out


## "critical" | "low" | "ok" | "full" for `value` of a pool of `max_value`.
static func pool_bucket(value: int, max_value: int) -> String:
	if max_value <= 0:
		return "full"
	var f := float(value) / float(max_value)
	if f < POOL_CRITICAL:
		return "critical"
	if f < POOL_LOW:
		return "low"
	return "full" if f >= POOL_FULL else "ok"


## "none" | "few" | "crowd" | "swarm" for `n` mobs near.
static func mobs_bucket(n: int) -> String:
	return ["none", "few", "crowd", "swarm"][mobs_step(n)]


## The mobs-near bucket as an ordinal 0..3.
static func mobs_step(n: int) -> int:
	if n >= MOBS_SWARM:
		return 3
	if n >= MOBS_CROWD:
		return 2
	return 1 if n >= MOBS_FEW else 0


## "none" | "few" | "plenty" for `n` potions in stock.
static func potion_bucket(n: int) -> String:
	return "none" if n <= 0 else ("plenty" if n >= POTIONS_PLENTY else "few")


## "none" | "some" | "many" for `n` drops.
static func drops_bucket(n: int) -> String:
	return "none" if n <= 0 else ("many" if n >= DROPS_MANY else "some")


## "none" | "some" | "many" for `n` recent hits.
static func hits_bucket(n: int) -> String:
	return "none" if n <= 0 else ("many" if n >= HITS_MANY else "some")


## "early" | "mid" | "late" (thirds of `duration`) at run time `t`, or "boss" while a boss lives.
static func phase_bucket(t: float, duration: float, boss_alive: bool) -> String:
	if boss_alive:
		return "boss"
	if t < duration / 3.0:
		return "early"
	return "mid" if t < duration * 2.0 / 3.0 else "late"


## Raw facts the Jev brain's card and job questions need (#94), merged into those decides' situation by
## card_decision.gd / job_decision.gd: owned skills with names and ranks, and boss counts. The Node side turns them
## into named buckets ("boss present", run phase); no thresholds live here.
static func brain_facts(w: RunWorld) -> Dictionary:
	var owned: Array = []
	for k: String in w.loadout.order:
		owned.append({"key": k, "name": String(w.book.def(k).get("name", k)), "rank": w.loadout.rank(k),
			"max_rank": w.book.max_rank(k)})
	var defeated := 0
	var scheduled := 0 # a skipped boss (no mob img) never arrives: not counted
	for r: Dictionary in w.bosses.records:
		if bool(r.get("skipped", false)):
			continue
		scheduled += 1
		if bool(r.get("dead", false)):
			defeated += 1
	return {"owned_skills": owned, "bosses_alive": w.bosses.live_count(), "bosses_defeated": defeated,
		"bosses_scheduled": scheduled}
