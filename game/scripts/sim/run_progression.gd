class_name RunProgression
extends RefCounted
## Level, EXP, job and the queue of level-ups still owed a choice window (docs/ARCHITECTURE.md 4.4.2).
##
## add_exp() raises `level` immediately for every threshold crossed and appends each new level to `queue`; RunWorld
## applies the per-level stats at once and works the queue off through the job / upgrade windows (the job check uses
## the queued level, not the current one). `exp` is the EXP into the current level.

var curve: ExpCurve
var level := 1
var exp := 0
## Canonical job id (0 Beginner, 200 Magician, ...).
var job_id := 0
## Levels gained but not yet through their choice window, oldest first.
var queue := PackedInt32Array()
## Level cap (no EXP is kept beyond it).
var max_level := 200


func _init(p_curve: ExpCurve = null, p_max_level: int = 200) -> void:
	curve = p_curve if p_curve != null else ExpCurve.new()
	max_level = maxi(1, p_max_level)


## EXP needed for the next level from the current one.
func exp_to_next() -> int:
	return curve.exp_to_next(level)


## Adds EXP; returns how many levels were gained (each queued).
func add_exp(n: int) -> int:
	if n <= 0 or level >= max_level:
		return 0
	exp += n
	var gained := 0
	while level < max_level and exp >= curve.exp_to_next(level):
		exp -= curve.exp_to_next(level)
		level += 1
		gained += 1
		queue.append(level)
	if level >= max_level:
		exp = 0
	return gained


## True while some level still needs its window.
func has_pending() -> bool:
	return not queue.is_empty()


## The oldest queued level (-1 when none).
func front() -> int:
	return queue[0] if not queue.is_empty() else -1


## Drops the oldest queued level (its window is done).
func pop_front() -> void:
	if not queue.is_empty():
		queue.remove_at(0)
