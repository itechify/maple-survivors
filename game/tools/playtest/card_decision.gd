extends "res://tools/playtest/decision_point.gd"
## The `card` decision: an open card window (normal level-up, advancement or boss bonus). Options are the offered
## cards in on-screen order; the baseline is the sensible player's BotInput.pick_card_for. Tool code only.

## Card fields copied into each option (see UpgradePool's pending card entries).
const FIELDS := ["name", "desc", "kind", "tier", "rank", "rank_before", "max_rank", "skill", "skill_name"]


func _init() -> void:
	kind = "card"


func pending(w: RunWorld) -> bool:
	return w.state == RunWorld.CHOOSING_UPGRADE


func options(w: RunWorld) -> Array:
	var out: Array = []
	for c: Dictionary in w.pending_cards:
		var o := {"id": String(c.get("id", ""))}
		for f: String in FIELDS:
			if c.has(f):
				o[f] = c[f]
		out.append(o)
	return out


func baseline(w: RunWorld, _policy: RUN_POLICY) -> Dictionary:
	return {"sensible": BotInput.pick_card_for(w, w.pending_cards)}


func apply(w: RunWorld, policy: RUN_POLICY, answer: String) -> void:
	policy.take_card(w, answer)
