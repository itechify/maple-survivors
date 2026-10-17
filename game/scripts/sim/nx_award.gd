class_name NxAward
extends RefCounted
## The NX a finished round pays (spec #34, ADR 0003). Pure functions over the balance.json `nx_award` block:
##   {clear_bonus: [per tier, 0-based], per_level: int, per_boss: int}
## A cleared round pays clear_bonus[tier] + per_level x levels gained in the round + per_boss x bosses killed in the
## round; a death pays the same without the clear bonus (bosses killed before dying count). Without the block
## nothing is paid. All numbers are tier C placeholders for the balance pass.


## NX for one round. `tier` is the stage's 0-based tier; tiers past the table reuse its last entry.
static func compute(config: Dictionary, tier: int, cleared: bool, levels_gained: int, bosses_killed: int) -> int:
	if config.is_empty():
		return 0
	var total := maxi(0, levels_gained) * maxi(0, int(config.get("per_level", 0))) \
		+ maxi(0, bosses_killed) * maxi(0, int(config.get("per_boss", 0)))
	var bonus: Array = config.get("clear_bonus", [])
	if cleared and not bonus.is_empty():
		total += maxi(0, int(bonus[clampi(tier, 0, bonus.size() - 1)]))
	return total


## 0-based tier of a stage from stages.json `tiers`; a stage outside them (tool rounds, fixtures) counts as tier 1.
static func tier_of(stages: Dictionary, stage_key: String) -> int:
	var tiers: Array = stages.get("tiers", [])
	for index in tiers.size():
		if stage_key in tiers[index]:
			return index
	return 0
