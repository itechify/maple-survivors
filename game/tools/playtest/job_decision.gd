extends "res://tools/playtest/decision_point.gd"
## The `job` decision: an open job advancement window. Options are the available branches (job ids as text) plus
## "not_now"; the baseline is BotInput.pick_job seeded by w.job_rng (and the policy's forced branch), exactly what the
## harness `bot` policy takes. Tool code only.

const NOT_NOW := "not_now"


func _init() -> void:
	kind = "job"


func pending(w: RunWorld) -> bool:
	return w.state == RunWorld.CHOOSING_JOB


func options(w: RunWorld) -> Array:
	var out: Array = []
	for o: Dictionary in w.pending_jobs:
		if bool(o.get("available", false)):
			out.append({"id": str(int(o.job_id)), "name": w.jobs.name_of(int(o.job_id))})
	out.append({"id": NOT_NOW, "name": "Not now"})
	return out


func baseline(w: RunWorld, policy: RUN_POLICY) -> Dictionary:
	var job := BotInput.pick_job(w.pending_jobs, w.job_rng, int(policy.branch))
	return {"sensible": str(job) if job >= 0 else NOT_NOW}


func apply(w: RunWorld, policy: RUN_POLICY, answer: String) -> void:
	policy.take_job(w, -1 if answer == NOT_NOW else int(answer))
