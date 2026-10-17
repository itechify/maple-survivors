extends RefCounted
## Helpers for the agent playtest's windowed replay (spec #91, ticket #100; scenes/debug/agent_replay.gd): the round
## end the headless run loop uses (balance_run.gd run_one's tick count for a time cap) and the part of its round record
## the fingerprint reads (playtest_fingerprint.gd of_round), so RunScene's round is fingerprinted exactly like the
## headless driver's. Tool code only.

const BR := preload("res://tools/balance_run.gd")
const DT := 1.0 / 60.0


## The time cap in seconds of a round played with `minutes` (the driver's --minutes; 0 = `balance.run_time_cap`, or
## balance_run.gd DEFAULT_RUN_CAP when the balance data has none).
static func cap_seconds(minutes: float, balance: Dictionary) -> float:
	return minutes * 60.0 if minutes > 0.0 else float(balance.get("run_time_cap", BR.DEFAULT_RUN_CAP))


## The number of fixed ticks run_one steps from run time 0 for time cap `cap` seconds (it stops earlier at a death or
## clear).
static func tick_cap(cap: float) -> int:
	return maxi(0, ceili(maxf(DT, cap) / DT - 1e-6))


## The round-record fields of `w` that the fingerprint reads, as run_one fills them: state (TIMEOUT for a living round),
## time (0.1 s), level, kills, job.
static func round_record(w: RunWorld) -> Dictionary:
	return {"state": "TIMEOUT" if w.state == RunWorld.PLAYING else w.state_name(), "time": snappedf(w.time, 0.1),
		"level": int(w.player_state.level), "kills": w.kills, "job": int(w.player_state.job_id)}
