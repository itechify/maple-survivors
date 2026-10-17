extends "res://tools/playtest/decision_point.gd"
## The `card` decision: an open card window (normal level-up, advancement or boss bonus). Options are the offered
## cards in on-screen order; the baseline is the sensible player's BotInput.pick_card_for. Tool code only.

## Card fields copied into each option (see UpgradePool's pending card entries). The skill levels are what the
## level-up window shows for skill_new / skill_rank cards (LevelUpWindow.rank_text).
const FIELDS := ["name", "desc", "kind", "tier", "rank", "rank_before", "max_rank", "skill", "skill_name",
	"skill_level", "skill_level_next", "skill_level_max"]


func _init() -> void:
	kind = "card"


## Open while the world waits in a card window (CHOOSING_UPGRADE).
func pending(w: RunWorld) -> bool:
	return w.state == RunWorld.CHOOSING_UPGRADE


## The offered cards in on-screen order: id, the FIELDS the window shows, and the fallbacks' `tags`.
func options(w: RunWorld) -> Array:
	var out: Array = []
	for c: Dictionary in w.pending_cards:
		var o := {"id": String(c.get("id", ""))}
		for f: String in FIELDS:
			if c.has(f):
				o[f] = c[f]
		o.merge(tags(w, c))
		out.append(o)
	return out


## What the personality fallbacks (#97, personality_fallback.ts) weigh: `sensible_score` (BotInput.card_score), `stat`
## (the card's first effect stat, else its skill's buff stat, e.g. "count", "damage", "magnet", "hp", "mp_guard"; ""
## for none) and `role` ("attack" / "support" for skill cards, classified the way BotInput.card_score does; else
## "none").
static func tags(w: RunWorld, c: Dictionary) -> Dictionary:
	var d := w.upgrades.card(String(c.get("id", "")))
	var effects: Array = d.get("effects", [])
	var stat := String(effects[0].get("stat", "")) if not effects.is_empty() and effects[0] is Dictionary else ""
	if stat == "" or stat == "rank":
		stat = String(c.get("skill_effect_stat", ""))
	var role := "none"
	var key := String(d.get("skill", ""))
	if key != "" and w.book.has(key):
		var sd := w.book.def(key)
		var rule := String(sd.get("cast", {}).get("rule", ""))
		var attack := rule != "manual" and rule != "crowd" and (String(sd.get("kind", "")) in ["projectile", "instant"] or rule == "box")
		role = "attack" if attack else "support"
	return {"sensible_score": BotInput.card_score(w, c), "stat": stat, "role": role}


## The base situation plus the Jev brain's facts (owned skills, boss counts).
func situation(w: RunWorld) -> Dictionary:
	var s := SITUATION.of(w, memory)
	s.merge(SITUATION.brain_facts(w))
	return s


## The sensible player's card: BotInput.pick_card_for over the offer.
func baseline(w: RunWorld, _policy: RUN_POLICY) -> Dictionary:
	return {"sensible": BotInput.pick_card_for(w, w.pending_cards)}


## Takes card `answer` through the run policy (run_policy.gd take_card).
func apply(w: RunWorld, policy: RUN_POLICY, answer: String) -> void:
	policy.take_card(w, answer)
