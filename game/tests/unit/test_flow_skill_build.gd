extends TestCase
## The diagnostic Skill scenario builds the selected job from its shipped pool, including future jobs.
const DRIVER := preload("res://scenes/debug/flow_driver.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")


func test_hero_skill_build_uses_hero_cards_and_common_passives() -> void:
	var setup := RF.setup("quiet", 319, RF.quiet_data())
	setup.job = 112
	var w := RunWorld.new(setup)
	var build: Array = DRIVER.skill_build(w)
	assert_eq(build, ["slash_blast_new", "slash_blast_rank", "brandish_new", "brandish_rank", "shout_new", "shout_rank",
		"passive_might_new", "passive_speed_new", "passive_speed_rank"])
	for id: String in build:
		assert_true(w.upgrades.apply(id, w) > 0, "%s applies" % id)
	assert_eq(w.loadout.slot_count("active"), 4)
