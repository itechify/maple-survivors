class_name NxAward
extends RefCounted
## The NX a finished round pays (spec #34, ADR 0003). Pure functions over the balance.json `nx_award` block:
##   {clear_bonus: [per progression step, 0-based], per_level: int, per_boss: int}
## A cleared round pays clear_bonus[step] + per_level x levels gained in the round + per_boss x bosses killed in the
## round; a death pays the same without the clear bonus (bosses killed before dying count). Without the block
## nothing is paid. All numbers are tier C placeholders for the balance pass.


## NX for one round. `step` is the stage's 0-based step in the progression (step_of); steps past the table reuse its last entry.
static func compute(config: Dictionary, step: int, cleared: bool, levels_gained: int, bosses_killed: int) -> int:
	if config.is_empty():
		return 0
	var total := maxi(0, levels_gained) * maxi(0, int(config.get("per_level", 0))) \
		+ maxi(0, bosses_killed) * maxi(0, int(config.get("per_boss", 0)))
	var bonus: Array = config.get("clear_bonus", [])
	if cleared and not bonus.is_empty():
		total += maxi(0, int(bonus[clampi(step, 0, bonus.size() - 1)]))
	return total


## 0-based step of a stage in stages.json `progression`; a stage outside it (tool rounds, fixtures) counts as step 0.
static func step_of(stages: Dictionary, stage_key: String) -> int:
	return maxi(0, (stages.get("progression", []) as Array).find(stage_key))
