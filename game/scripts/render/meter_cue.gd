class_name MeterCue
extends RefCounted
## The full-bar cue of a job's meter (Buccaneer's Energy Charge `affected` art and Use sound; spec #412, B6 #418). Fed the sim's
## `meter_changed` events, it hands the job's `cue` {effect, sound} to a sink once when the bar reaches its maximum, and not
## again until the bar has dropped below it and refilled. Presentation only: no sim state, no RNG, nothing saved. It reads the
## cue from the job's meter block, so another job's meter (Shadower's meso charge) can reuse it.

## Called with (effect path, sound path) when the cue fires; either may be "".
var _sink: Callable
var _effect := ""
var _sound := ""
var _armed := true


## `cue` is the meter block's optional `cue` object ({} = no cue, the helper never fires).
func _init(cue: Dictionary, sink: Callable) -> void:
	_effect = String(cue.get("effect", ""))
	_sound = String(cue.get("sound", ""))
	_sink = sink


## One sim event: a `meter_changed` that brings `value` to `max` fires the cue if the bar has been below full since it last did.
func on_event(e: Dictionary) -> void:
	if String(e.get("type", "")) != "meter_changed" or (_effect == "" and _sound == ""):
		return
	if int(e.value) < int(e.max):
		_armed = true
	elif _armed:
		_armed = false
		_sink.call(_effect, _sound)
