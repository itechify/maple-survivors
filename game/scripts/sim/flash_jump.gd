class_name FlashJump
extends RefCounted
## Pure arithmetic behind Flash Jump (M14, spec #383, GAME_DESIGN 7.92): the distance of a flash by rank, the side it
## goes, whether a press is admitted and the ghost trail's points. No nodes, no RNG, no clock: RunWorld owns the repeat
## timer, PlayerMotion owns the once-per-airborne-period flag and the move itself (flash_destination / flash_to).

## Ghost copies of the avatar drawn along a flash, the seconds they take to fade and the opacity of the first one
## (the others fade linearly to a quarter of it). Presentation only. tier C: ours, the WZ node has no art.
const TRAIL_COPIES := 3
const TRAIL_TIME := 0.3
const TRAIL_ALPHA := 0.5


## The flash distance in px at `rank` (1-based): linear from the first entry of `distances` at rank 1 to the last at
## `top_rank`; a rank outside 1..top_rank clamps, one entry is a constant. tier C: ours, the WZ has no distance.
static func distance(distances: Array, rank: int, top_rank: int) -> float:
	if distances.is_empty():
		return 0.0
	var first := float(distances[0])
	var last := float(distances[distances.size() - 1])
	if top_rank <= 1:
		return first
	var t := clampf(float(rank - 1) / float(top_rank - 1), 0.0, 1.0)
	return lerpf(first, last, t)


## The side (-1 / 1) a press goes: the held side arrow, else the facing. Opposing arrows cancel (`held` is 0), and Up and
## Down never matter.
static func side(held: int, facing: int) -> int:
	return held if held != 0 else (1 if facing >= 0 else -1)


## Whether a press is admitted before the move is looked at: the character can act, no repeat delay is running.
## (PlayerMotion.flash_destination adds the airborne and once-per-period rules.)
static func admits(can_act: bool, delay_left: float) -> bool:
	return can_act and delay_left <= 1e-6


## The ghost copies of a flash from `from` to `to`: [{pos, alpha}] from the start of the path toward the end (never on
## the arrival point, where the avatar is), the first the brightest. tier C: ours.
static func trail(from: Vector2, to: Vector2) -> Array:
	var out: Array = []
	for i in TRAIL_COPIES:
		var t := float(i) / float(TRAIL_COPIES)
		out.append({"pos": from.lerp(to, t), "alpha": TRAIL_ALPHA * (1.0 - 0.75 * t)})
	return out
