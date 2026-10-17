extends "res://tools/playtest/decision_point.gd"
## The `tactic` decision (spec #91, ticket #95): which play style the tactic controller carries out next. Never pending
## in the window poll; the playtest policy asks it from `move` at checkpoints and triggers (playtest_policy.gd).
## Options are the allowed tactics (tactic_controller.gd TACTICS order) with a one-line description; the baseline is
## the sensible player, who always kites. The situation gains a `tactic` entry (see `extra_situation`). Tool code only.

const CONTROLLER := preload("res://tools/playtest/tactic_controller.gd")
## What each tactic does, as the option text.
const DESCRIPTIONS := {
	"kite": "Kite like the standard bot: run from nearby mobs, duel a lone one, pick up safe drops.",
	"aggressive": "Close in on the nearest mob or boss and fight it face to face, hopping now and then.",
	"defensive": "Keep a wide berth from every mob, flee early, only take drops with no mob near, drink potions early.",
	"explore": "Walk, jump, climb ropes and take portals toward the platforms visited least.",
	"collect": "Sweep up EXP and potion drops anywhere on the map, including platforms above.",
	"hold": "Stand still and press no movement keys.",
}

## Allowed tactics in offer order (a subset of CONTROLLER.TACTICS).
var allowed: Array = CONTROLLER.TACTICS.duplicate()
## Set by the policy before each ask: what fired the decision, the current tactic, seconds it has been held, and how
## many switches happened so far.
var trigger := ""
var current := "kite"
var held_s := 0.0
var switches := 0


func _init() -> void:
	kind = "tactic"


func options(_w: RunWorld) -> Array:
	return allowed.map(func(t: String) -> Dictionary: return {"id": t, "name": t, "desc": String(DESCRIPTIONS.get(t, ""))})


func baseline(_w: RunWorld, _policy: RUN_POLICY) -> Dictionary:
	return {"sensible": "kite" if "kite" in allowed else String(allowed[0])}


## {"tactic": {current, trigger, held_s, switches}} merged into the decide's situation.
func extra_situation(_w: RunWorld) -> Dictionary:
	return {"tactic": {"current": current, "trigger": trigger, "held_s": snappedf(held_s, 0.01), "switches": switches}}


func apply(w: RunWorld, policy: RUN_POLICY, answer: String) -> void:
	policy.call("set_tactic", w, answer, trigger)
