extends RefCounted
## Per-second telemetry for agent playtests (spec #91, ticket #96): a run loop observer that writes one JSON row per
## EVERY_S of run time (timeline.jsonl in the run directory): time, tick, HP / MP, level, EXP, mobs alive and near
## the player, bosses alive, position, platform, tactic and state; from #99 also kills, EXP drops on the map, drops
## above the player (out of magnet reach) and the HP potion stock. With a hits writer (#99) every landed player hit is
## written as it happens (hits.jsonl): time, tick, damage, max_hp, fraction, source, boss, mob_id. Hits are not rows
## (the fingerprint samples the rows' cadence). Read-only. Tool code only.

const BR := preload("res://tools/balance_run.gd")
const SITUATION := preload("res://tools/playtest/playtest_situation.gd")
const DT := 1.0 / 60.0
## Run seconds between rows.
const EVERY_S := 1.0

## The run policy whose tactic is read (any Object or null; no tactic reads as "kite").
var policy: Object
## Receives each row as one JSON line.
var write: Callable
## Receives each landed player hit as one JSON line (invalid: hits are not written).
var write_hit: Callable
## Rows written so far.
var rows := 0
var _next := EVERY_S


## `p_policy` is read for its tactic; `p_write(line)` receives each row; `p_write_hit(line)` each landed hit.
func _init(p_policy: Object = null, p_write := Callable(), p_write_hit := Callable()) -> void:
	policy = p_policy
	write = p_write
	write_hit = p_write_hit


## The run loop observer: writes every landed hit of this tick, and a row whenever another EVERY_S of run time has
## passed.
func observe(w: RunWorld, events: Array) -> void:
	if write_hit.is_valid():
		for e: Dictionary in events:
			if String(e.get("type", "")) == "player_hit" and not bool(e.get("miss", false)):
				write_hit.call(JSON.stringify(hit_row(w, e)))
	if w.time < _next - 1e-6:
		return
	while _next <= w.time + 1e-6:
		_next += EVERY_S
	rows += 1
	if write.is_valid():
		write.call(JSON.stringify(row(w)))


## The hits.jsonl line for player_hit event `e` now.
static func hit_row(w: RunWorld, e: Dictionary) -> Dictionary:
	var max_hp := maxi(1, int(e.get("max_hp", 1)))
	return {"time": snappedf(w.time, 0.001), "tick": roundi(w.time / DT), "damage": int(e.get("damage", 0)),
		"max_hp": max_hp, "fraction": snappedf(float(e.get("damage", 0)) / max_hp, 0.001),
		"source": String(e.get("source_kind", "other")), "boss": bool(e.get("boss", false)),
		"mob_id": int(e.get("mob_id", 0))}


## The row for `w` now.
func row(w: RunWorld) -> Dictionary:
	var ps := w.player_state
	var p := w.player.pos
	var t: Variant = policy.get("tactic") if policy != null else null
	return {"time": snappedf(w.time, 0.001), "tick": roundi(w.time / DT), "hp": int(ps.get("hp", 0)),
		"max_hp": int(ps.get("max_hp", 0)), "mp": int(ps.get("mp", 0)), "max_mp": int(ps.get("max_mp", 0)),
		"level": int(ps.get("level", 0)), "exp": int(ps.get("exp", 0)), "alive": w.swarm.alive_count(),
		"near": BR._near(w), "bosses": w.bosses.live_count() if w.bosses != null else 0,
		"x": snappedf(p.x, 0.1), "y": snappedf(p.y, 0.1), "platform": w.fhm.platform_of(w.player.fh),
		"tactic": "kite" if t == null or String(t) == "" else String(t), "state": w.state_name(),
		"kills": w.kills, "drops": w.pickups.exp_count(), "drops_above": SITUATION.drops_around(w).y,
		"potions_hp": int(w.potions.stock.hp.count)}
