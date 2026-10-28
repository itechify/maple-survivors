class_name AutoAp
## Automatic AP split (spec #33 ticket #106, docs/GAME_DESIGN.md section 11): the earned AP of a character goes first
## into a job line's secondary stat until that stat's base value reaches the target for the character's level, and the
## rest goes to the primary stat. Pure static functions; the rows come from balance.json `player.ap` (one per job, #284).

## Target of the secondary stat at `level`: linear keyframes of `[{level, target}, ...]` (sorted by level), floored;
## held at the first and last keyframe outside their range. No keyframes gives 0.
static func secondary_target(keyframes: Array, level: int) -> int:
	if keyframes.is_empty():
		return 0
	var first: Dictionary = keyframes[0]
	var last: Dictionary = keyframes[keyframes.size() - 1]
	if level <= int(first.level):
		return int(first.target)
	if level >= int(last.level):
		return int(last.target)
	for i in range(1, keyframes.size()):
		var b: Dictionary = keyframes[i]
		if level <= int(b.level):
			var a: Dictionary = keyframes[i - 1]
			# Integer span first, so an exact slope of 1 per level never floors one point short.
			var span := int(b.level) - int(a.level)
			return int(a.target) + floori(float((level - int(a.level)) * (int(b.target) - int(a.target))) / span)
	return int(last.target)


## AP of the earned total that goes to the secondary stat: enough to lift `base_secondary` to the target at `level`,
## never more than `earned_ap`, never negative. The rest of the earned AP belongs to the primary stat.
static func secondary_ap(earned_ap: int, level: int, base_secondary: float, keyframes: Array) -> int:
	if earned_ap <= 0 or keyframes.is_empty():
		return 0
	var need := secondary_target(keyframes, level) - floori(base_secondary)
	return clampi(need, 0, earned_ap)
