extends RefCounted
## A run policy for the headless run loop (balance_run.gd `run_one` / `run_chain`): it answers every open job or card
## window (`choose`) and gives the player's input for one fixed tick (`move`). Tool code only.
##
## `new(name, seed, branch, camp_after)` is one of the harness policies of `balance_run.gd` POLICIES:
##   bot     jobs BotInput.pick_job (seeded by w.job_rng, `branch` forces 210/220/230), cards BotInput.pick_card_for,
##           movement BotInput.decide
##   random  cards: a seeded random one of the offered (its own stream, hash("careless-<seed>"))
##   first   cards: BotInput.pick_card (always the first offered)
##   camper_*  sensible cards, camper_input.gd movement after `camp_after` seconds
## Other policies extend this script and override `choose` and/or `move`; a `choose` override takes cards and jobs
## through `take_card` / `take_job` so the record's cards_taken stays complete.

const CAMPER := preload("res://tools/camper_input.gd")

## Policy name (the record's "policy"; a camper name also fills the record's camper fields).
var name := "bot"
## "<job id>:<card id>" for every card taken, in order (the record's cards_taken).
var cards_taken: Array = []
## Movement memo shared with BotInput.decide / camper_input.gd (the record's camper fields read it).
var memo := {}
## Forced second-job branch (210, 220, 230) or 0 for BotInput's seeded pick.
var branch := 0
## Seconds before a camper policy starts parking.
var camp_after := 60.0
## The careless player's own card stream ("random").
var rng := RandomNumberGenerator.new()


func _init(p_name := "bot", seed_value := 0, p_branch := 0, p_camp_after := 60.0) -> void:
	name = p_name
	branch = p_branch
	camp_after = p_camp_after
	rng.seed = hash("careless-%d" % seed_value)


## Answers every open job / card window of `w` (at most 64 in one call).
func choose(w: RunWorld) -> void:
	var guard := 0
	while guard < 64 and (w.state == RunWorld.CHOOSING_JOB or w.state == RunWorld.CHOOSING_UPGRADE):
		guard += 1
		if w.state == RunWorld.CHOOSING_JOB:
			take_job(w, BotInput.pick_job(w.pending_jobs, w.job_rng, branch))
			continue
		var id := ""
		match name:
			"random":
				id = String(w.pending_cards[rng.randi_range(0, w.pending_cards.size() - 1)].get("id", ""))
			"first":
				id = BotInput.pick_card(w.pending_cards)
			_:
				id = BotInput.pick_card_for(w, w.pending_cards)
		take_card(w, id)


## The player's input for the next fixed tick of `w`.
func move(w: RunWorld) -> MoveInput:
	return CAMPER.decide(w, name, memo, camp_after) if CAMPER.STAGES.has(name) else BotInput.decide(w, memo)


## Applies card `id` in the open card window of `w` and records it in cards_taken.
func take_card(w: RunWorld, id: String) -> void:
	cards_taken.append("%d:%s" % [w.progression.front(), id])
	w.apply_choice(id)


## Advances to `job` in the open job window of `w`, or declines it ("not now") when `job` < 0 or not applicable.
func take_job(w: RunWorld, job: int) -> void:
	if job < 0 or not w.apply_job(job):
		w.decline_job()
