extends TestCase
## The autoplay bot's Hero scoring and melee reach (spec #296, H9 #305). Data-level checks run on the shipped files; the
## card and reach checks need the Hero skills (H5-H8) and are below.


func test_every_pool_skill_of_both_jobs_has_new_100_and_rank_74_scores() -> void:
	var data := DataRepo.load_all()
	var scores: Dictionary = data.balance.bot.card_scores
	var tree := JobTree.from_data(data.jobs, data.jobs_survivor)
	for job: int in [212, 112]:
		var pool: Array = tree.skill_pool(job)
		assert_false(pool.is_empty(), "job %d has a pool" % job)
		for key: String in pool:
			assert_eq(float(scores.get(key + "_new", -1)), 100.0, "%s learn card (job %d)" % [key, job])
			assert_eq(float(scores.get(key + "_rank", -1)), 74.0, "%s rank card (job %d)" % [key, job])


func test_hero_scores_name_the_three_cards_the_default_scorer_would_undervalue() -> void:
	var scores: Dictionary = DataRepo.load_all().balance.bot.card_scores
	for key: String in ["panic", "coma", "monster_magnet"]:
		assert_true(scores.has(key + "_new") and scores.has(key + "_rank"), key)
