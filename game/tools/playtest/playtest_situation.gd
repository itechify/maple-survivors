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
