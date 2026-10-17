extends "res://tools/playtest/decision_point.gd"
## The `job` decision: an open job advancement window. Options are the available branches (job ids as text) plus
## "not_now"; the baseline is BotInput.pick_job seeded by w.job_rng (and the policy's forced branch), exactly what the
## harness `bot` policy takes. Tool code only.

const NOT_NOW := "not_now"


func _init() -> void:
	kind = "job"


## Open while the world waits in a job advancement window (CHOOSING_JOB).
func pending(w: RunWorld) -> bool:
	return w.state == RunWorld.CHOOSING_JOB


## The available branches (job id as text, name, `describe`) in window order, then "not_now".
func options(w: RunWorld) -> Array:
	var out: Array = []
	for o: Dictionary in w.pending_jobs:
		if bool(o.get("available", false)):
			out.append({"id": str(int(o.job_id)), "name": w.jobs.name_of(int(o.job_id)), "desc": describe(w, int(o.job_id))})
	out.append({"id": NOT_NOW, "name": "Not now"})
	return out


## A one-line description of job `id` derived from data (neither jobs.json has description text): its tier and parent
## from the canonical job tree, and the names of its skills in skills.json ("2nd job of the Magician line; skills: ...").
static func describe(w: RunWorld, id: int) -> String:
	var j := w.jobs.job(id)
	var tier := int(j.get("tier", 0))
	var ordinal: String = ["", "1st", "2nd", "3rd", "4th"][tier] if tier >= 0 and tier <= 4 else "%dth" % tier
	var parent := int(j.get("parent", -1))
	var line := "%s job" % ordinal
	if tier >= 2 and parent >= 0:
		line += " of the %s line" % w.jobs.name_of(parent)
	var skills: Array = []
	for k: String in w.book.defs:
		if int(w.book.def(k).get("job", -1)) == id:
			skills.append(String(w.book.def(k).get("name", k)))
	return line + ("; skills: " + ", ".join(skills) if not skills.is_empty() else "")


## The base situation plus the Jev brain's facts (owned skills, boss counts).
func situation(w: RunWorld) -> Dictionary:
	var s := SITUATION.of(w, memory)
	s.merge(SITUATION.brain_facts(w))
	return s


## The harness bot's branch: BotInput.pick_job on w.job_rng with the policy's forced branch ("not_now" for none).
func baseline(w: RunWorld, policy: RUN_POLICY) -> Dictionary:
	var job := BotInput.pick_job(w.pending_jobs, w.job_rng, int(policy.branch))
	return {"sensible": str(job) if job >= 0 else NOT_NOW}


## Takes branch `answer` (or declines for "not_now") through the run policy (run_policy.gd take_job).
func apply(w: RunWorld, policy: RUN_POLICY, answer: String) -> void:
	policy.take_job(w, -1 if answer == NOT_NOW else int(answer))
