extends TestCase
## What the Jev brain (#94) needs from the playtest driver's card and job decide messages: owned skills with names and
## "r of max" ranks, boss counts (Node buckets them into "boss present" and the run phase), the skill levels a card
## window shows, and a one-line description of each job branch derived from data. Synthetic worlds, fixed dt.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const PROTOCOL := preload("res://tools/playtest/playtest_protocol.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const STDIO_LINK := preload("res://tools/playtest/stdio_brain_link.gd")
const DT := 1.0 / 60.0


## Captures each decide and answers it with its baseline.
class Capture:
	var decides: Array = []

	func write(line: String) -> void:
		if line.begins_with(PROTOCOL.PREFIX):
			decides.append(JSON.parse_string(line.substr(PROTOCOL.PREFIX.length())))

	func read() -> String:
		var d: Dictionary = decides[decides.size() - 1]
		return JSON.stringify({"v": 1, "type": "answer", "id": d.id, "answer": d.baseline.sensible, "source": "test",
			"confidence": null})


func _decides(w: RunWorld) -> Array:
	var cap := Capture.new()
	POLICY.new(STDIO_LINK.new(cap.write, cap.read)).choose(w)
	return cap.decides


func test_card_decide_carries_named_skills_boss_counts_and_skill_levels() -> void:
	var w := RF.quiet_world(400.0, 43)
	w.pending_bonus_choices = 1
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "fixture: a card window is open")
	# Boss records as BossDirector keeps them (only the fields live_count / all_dead read); the sim is paused.
	w.bosses.records.append({"spawn_time": 1.0, "dead": false, "skipped": false})
	w.bosses.records.append({"spawn_time": -1.0, "dead": false, "skipped": false})
	var d: Dictionary = _decides(w)[0]
	var s: Dictionary = d.situation
	assert_eq(int(s.bosses_alive), 1, "one spawned living boss")
	assert_eq(int(s.bosses_defeated), 0)
	assert_eq(int(s.bosses_scheduled), 2)
	assert_true(s.owned_skills.size() >= 1, "the starting skill is owned")
	var snails: Dictionary = s.owned_skills[0]
	assert_eq(String(snails.name), "Three Snails", "skills carry their in-game names")
	assert_eq(int(snails.rank), w.loadout.rank("three_snails"))
	assert_true(int(snails.max_rank) >= int(snails.rank) and int(snails.max_rank) > 1, "and their max rank")
	assert_true(s.has("hp") and s.has("max_hp") and s.has("level"), "the base situation is still there")
	for o: Dictionary in d.options:
		if String(o.kind) in ["skill_new", "skill_rank"]:
			assert_true(o.has("skill_level_next") and o.has("skill_level_max"), "skill cards show their skill levels")


func test_job_options_describe_each_branch_from_data() -> void:
	var w := RF.quiet_world(400.0, 53)
	w.change_job(200)
	w.progression.level = 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "fixture: Lv 30 opens the second-job window")
	var job: Dictionary = _decides(w)[0]
	assert_eq(String(job.kind), "job")
	var by_id := {}
	for o: Dictionary in job.options:
		by_id[String(o.id)] = o
	assert_true(by_id.has("230"), "Cleric is on offer")
	var cleric := String(by_id["230"].get("desc", ""))
	assert_true(cleric.contains("Magician"), "the description names the line: %s" % cleric)
	assert_true(cleric.contains("Heal"), "and the branch's skills from skills.json: %s" % cleric)
	assert_true(String(by_id["210"].get("desc", "")).contains("Fire Arrow"))
	assert_true(job.situation.has("owned_skills") and job.situation.has("bosses_alive"), "job decides carry the facts too")
