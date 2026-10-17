extends RefCounted
## One kind of decision the playtest brain makes (spec #91): when it is pending, the options shown, the baseline answer
## real game code gives, and how an answer is applied. playtest_policy.gd keeps a list of these (`decision_points`);
## card_decision.gd and job_decision.gd are the window kinds. A new kind (e.g. #95's tactic checkpoints) is a new file
## extending this one, registered in that list or asked directly through PlaytestPolicy.decide. Tool code only.

const RUN_POLICY := preload("res://tools/run_policy.gd")

## The protocol's decide `kind`.
var kind := ""


## True when this decision is open in `w` and must be answered before the next tick.
func pending(_w: RunWorld) -> bool:
	return false


## The options in on-screen order: [{id: String, name, ...}].
func options(_w: RunWorld) -> Array:
	return []


## Baseline answers by policy name ({"sensible": option id}). Called exactly once per decision, before the brain is
## asked, so any RNG it consumes is consumed in the same order as the harness policies.
func baseline(_w: RunWorld, _policy: RUN_POLICY) -> Dictionary:
	return {"sensible": ""}


## Applies option `answer` (one of `options`) in `w` through `policy` (run_policy.gd take_card / take_job).
func apply(_w: RunWorld, _policy: RUN_POLICY, _answer: String) -> void:
	pass
