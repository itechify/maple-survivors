extends RefCounted
## The playtest driver's link to the brain that answers decisions (spec #91). This base class is the builtin brain
## (`--brain=builtin`, no pipe): it answers every decide with its "sensible" baseline, the answer real game code gives.
## stdio_brain_link.gd asks the Node CLI over the decision protocol instead. Tool code only.

## True once the brain can no longer answer (stdin EOF); every later decision then takes its baseline.
var lost := false
## Name echoed in the hello message ("builtin", "stdio").
var mode := "builtin"


## The answer to decide message `decide` (playtest_protocol.gd shape): {id, answer, source, confidence}, or
## {"error": why} when the brain gave no usable answer (the caller then applies the baseline).
func ask(decide: Dictionary) -> Dictionary:
	return {"id": int(decide.id), "answer": String(decide.baseline.get("sensible", "")), "source": "builtin",
		"confidence": null}


## Sends a non-decide message (hello, finding, end, error). The builtin brain has no one to tell.
func send(_msg: Dictionary) -> void:
	pass
