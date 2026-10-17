extends RefCounted
## The situation that travels with every decide message (spec #91): plain facts about the round right now. Later
## tickets add named buckets (HP low, crowd large, boss present) here for the Jev brain. Tool code only.


## Facts about run `w` for a decide message.
static func of(w: RunWorld) -> Dictionary:
	var ps := w.player_state
	return {
		"state": w.state_name(), "time": snappedf(w.time, 0.001), "level": int(ps.get("level", 0)),
		"job_id": int(ps.get("job_id", 0)), "job": w.jobs.name_of(int(ps.get("job_id", 0))),
		"hp": int(ps.get("hp", 0)), "max_hp": int(ps.get("max_hp", 0)),
		"mp": int(ps.get("mp", 0)), "max_mp": int(ps.get("max_mp", 0)),
		"kills": w.kills, "alive": w.swarm.alive_count(),
		"skills": w.loadout.order.map(func(k: String) -> String: return "%s:%d" % [k, w.loadout.rank(k)]),
		"advancement": w.choice_advancement, "bonus": w.choice_bonus,
	}
