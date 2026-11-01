extends RefCounted
## The calibrated level scale of the new regions (spec #449 C13, ticket #475; tier C), as the region tests check it:
## `level(t) = lerp(START_LEVEL, exp_level(t) + ABOVE[step], min(1, t / WARMUP_S))`, with exp_level(t) = Sleepywood's
## effective level at the keyframe time (unchanged from the first draft). ABOVE is the levels above Sleepywood's pace per
## progression step: 0.75 per step to step 12 and 0.25 per step after it. `level_scale_draft.gd --above=<ABOVE>
## --start=1 --warmup=600 --boss-hp-scale=4` prints these keyframes.

const START_LEVEL := 1.0
const WARMUP_S := 600.0
const ABOVE := {6: 0.75, 7: 1.5, 8: 2.25, 9: 3.0, 10: 3.75, 11: 4.5, 12: 5.25, 13: 5.5, 14: 5.75, 15: 6.0, 16: 6.25}


## The effective level the calibrated scale gives step `step` at curve time `t`, for Sleepywood's effective level `exp_level`.
static func level_at(exp_level: float, t: float, step: int) -> float:
	return lerpf(START_LEVEL, exp_level + float(ABOVE[step]), clampf(t / WARMUP_S, 0.0, 1.0))
