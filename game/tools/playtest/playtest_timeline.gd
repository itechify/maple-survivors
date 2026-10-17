extends RefCounted
## Per-second telemetry for agent playtests (spec #91, ticket #96): a run loop observer that writes one JSON row per
## EVERY_S of run time (timeline.jsonl in the run directory): time, tick, HP / MP, level, EXP, mobs alive and near
## the player, bosses alive, position, platform, tactic and state. Read-only. Tool code only.

const BR := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0
## Run seconds between rows.
const EVERY_S := 1.0

## The run policy whose tactic is read (any Object or null; no tactic reads as "kite").
var policy: Object
## Receives each row as one JSON line.
var write: Callable
## Rows written so far.
var rows := 0
var _next := EVERY_S


## `p_policy` is read for its tactic; `p_write(line)` receives each row.
func _init(p_policy: Object = null, p_write := Callable()) -> void:
	policy = p_policy
	write = p_write


## The run loop observer: writes a row whenever another EVERY_S of run time has passed.
func observe(w: RunWorld, _events: Array) -> void:
	if w.time < _next - 1e-6:
		return
	while _next <= w.time + 1e-6:
		_next += EVERY_S
	rows += 1
	if write.is_valid():
		write.call(JSON.stringify(row(w)))


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
		"tactic": "kite" if t == null or String(t) == "" else String(t), "state": w.state_name()}
