extends TestCase
## The agent playtest driver's decision protocol layer (game/tools/playtest/, spec #91, ticket #93): open card and job
## windows become versioned `decide` lines with baseline answers from real game code, answers read back are applied,
## invalid answers and a lost brain fall back to the baseline, and the builtin brain plays the `bot` run exactly.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const BR := preload("res://tools/balance_run.gd")
const PROTOCOL := preload("res://tools/playtest/playtest_protocol.gd")
const POLICY := preload("res://tools/playtest/playtest_policy.gd")
const BRAIN_LINK := preload("res://tools/playtest/brain_link.gd")
const STDIO_LINK := preload("res://tools/playtest/stdio_brain_link.gd")
const DT := 1.0 / 60.0


## Fake stdio for the stdio link: captures written lines and answers each decide through `reply`
## (decide Dictionary -> answer line String; "" is stdin EOF).
class FakeIO:
	var written: PackedStringArray = []
	var reply: Callable

	func write(line: String) -> void:
		written.append(line)

	func read() -> String:
		var decide: Dictionary = JSON.parse_string(written[written.size() - 1].substr(PROTOCOL.PREFIX.length()))
		return reply.call(decide)


static func answer_line(id: int, answer: String) -> String:
	return JSON.stringify({"v": 1, "type": "answer", "id": id, "answer": answer, "source": "test", "confidence": 0.75})


func _stdio_policy(io: FakeIO) -> POLICY:
	return POLICY.new(STDIO_LINK.new(io.write, io.read))


func _card_window(seed_value := 43) -> RunWorld:
	var w := RF.quiet_world(400.0, seed_value)
	w.pending_bonus_choices = 1
	w.step(DT, MoveInput.new())
	return w


func _job_window() -> RunWorld:
	var w := RF.quiet_world(400.0, 53)
	w.progression.level = 9
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	return w


func test_open_card_window_emits_a_versioned_decide_and_applies_the_answer() -> void:
	var w := _card_window()
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "fixture: a boss bonus card window is open")
	var offered: Array = w.pending_cards.map(func(c: Dictionary) -> String: return String(c.id))
	var sensible := BotInput.pick_card_for(w, w.pending_cards)
	var last := String(offered[offered.size() - 1])
	var io := FakeIO.new()
	io.reply = func(decide: Dictionary) -> String: return answer_line(int(decide.id), last)
	var policy := _stdio_policy(io)
	policy.choose(w)
	assert_eq(io.written.size(), 1, "one decide line for one window")
	var line := io.written[0]
	assert_true(line.begins_with("@@PT "), "decide lines carry the reserved prefix")
	var decide: Dictionary = JSON.parse_string(line.substr(5))
	assert_eq(int(decide.v), 1)
	assert_eq(String(decide.type), "decide")
	assert_eq(int(decide.id), 1)
	assert_eq(String(decide.kind), "card")
	assert_eq(decide.options.map(func(o: Dictionary) -> String: return String(o.id)), offered,
		"options are the offered cards in on-screen order")
	for o: Dictionary in decide.options:
		assert_true(String(o.get("name", "")) != "", "each card option carries its in-game name")
		assert_true(o.has("kind") and o.has("rank") and o.has("desc"))
	assert_eq(String(decide.baseline.sensible), sensible, "baseline from BotInput.pick_card_for")
	assert_true(decide.situation.has("level") and decide.situation.has("hp"), "a situation travels with the decide")
	assert_eq(w.state, RunWorld.PLAYING, "the window was answered")
	assert_true(String(policy.cards_taken[policy.cards_taken.size() - 1]).ends_with(":" + last),
		"the brain's answer (not the baseline) was applied")
	assert_eq(policy.decisions.size(), 1)
	assert_eq(String(policy.decisions[0].source), "test")
	assert_eq(String(policy.decisions[0].answer), last)


func test_open_job_window_offers_branches_and_not_now() -> void:
	var w := _job_window()
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "fixture: Lv 10 opens the job window")
	var io := FakeIO.new()
	io.reply = func(decide: Dictionary) -> String: return answer_line(int(decide.id), String(decide.baseline.sensible))
	var policy := _stdio_policy(io)
	policy.choose(w)
	var job: Dictionary = JSON.parse_string(io.written[0].substr(5))
	assert_eq(String(job.kind), "job")
	var ids: Array = job.options.map(func(o: Dictionary) -> String: return String(o.id))
	assert_has(ids, "200", "Magician is on offer")
	assert_eq(String(ids[ids.size() - 1]), "not_now", "\"not now\" is always the last option")
	assert_eq(String(job.baseline.sensible), "200", "baseline from BotInput.pick_job")
	assert_eq(w.progression.job_id, 200, "the job answer was applied")
	assert_true(io.written.size() >= 2, "the advancement card window that follows is another decide")
	var card: Dictionary = JSON.parse_string(io.written[1].substr(5))
	assert_eq(String(card.kind), "card")
	assert_eq(int(card.id), 2, "decide ids count up through the run")
	assert_eq(w.state, RunWorld.PLAYING)


func test_invalid_answer_falls_back_to_the_baseline() -> void:
	var w := _card_window()
	var sensible := BotInput.pick_card_for(w, w.pending_cards)
	var io := FakeIO.new()
	io.reply = func(decide: Dictionary) -> String: return answer_line(int(decide.id), "no_such_card")
	var policy := _stdio_policy(io)
	policy.choose(w)
	assert_eq(w.state, RunWorld.PLAYING, "the round goes on")
	assert_true(String(policy.cards_taken[0]).ends_with(":" + sensible), "the baseline card was taken")
	assert_eq(String(policy.decisions[0].source), "baseline")
	assert_true(String(policy.decisions[0].fallback_reason).contains("no_such_card"), "the reason names the bad answer")


func test_stdin_eof_marks_the_brain_lost_and_finishes_on_the_baseline() -> void:
	var w := _card_window()
	var io := FakeIO.new()
	io.reply = func(_decide: Dictionary) -> String: return ""
	var link := STDIO_LINK.new(io.write, io.read)
	var policy := POLICY.new(link)
	policy.choose(w)
	assert_true(link.lost, "EOF on stdin is a lost brain")
	assert_eq(w.state, RunWorld.PLAYING, "the window was still answered")
	assert_eq(String(policy.decisions[0].source), "baseline")
	var w2 := _card_window(44)
	policy.choose(w2)
	var decides := Array(io.written).filter(func(l: String) -> bool: return l.begins_with(PROTOCOL.PREFIX))
	assert_eq(decides.size(), 1, "a lost brain is not asked again")
	assert_true(io.written[io.written.size() - 1].contains("brain lost"), "the loss is logged")
	assert_eq(w2.state, RunWorld.PLAYING)


func test_builtin_brain_plays_exactly_the_bot_run() -> void:
	var data := RF.quiet_data()
	data.stages.stages.quiet.keyframes = [{"t": 0, "rate": 10, "max_alive": 20, "pool": {"100100": 1}}]
	data.balance.run_time_cap = 30.0
	var a: Dictionary = BR.run_one(_lv10_world(data), "bot", 9)
	var policy := POLICY.new(BRAIN_LINK.new())
	var b: Dictionary = BR.run_one(_lv10_world(data), policy, 9)
	assert_true(int(a.spawned) > 0 and a.cards_taken.size() >= 3, "the run had mobs and card windows")
	assert_eq(policy.decisions.filter(func(d: Dictionary) -> bool: return d.kind == "job").size(), 1,
		"the Lv 10 job window went through the decision protocol")
	assert_eq(policy.decisions.filter(func(d: Dictionary) -> bool: return d.kind == "card").size(),
		a.cards_taken.size(), "every card window went through the decision protocol")
	assert_eq(JSON.stringify(b), JSON.stringify(a), "the builtin brain (baseline answers) plays the bot run")


## A spawning quiet world one EXP bar from Lv 10 (job window) with two boss bonus windows queued.
func _lv10_world(data: Dictionary) -> RunWorld:
	var w := RunWorld.new(RF.setup("quiet", 9, data))
	w.progression.level = 9
	w.progression.add_exp(w.progression.exp_to_next())
	w.pending_bonus_choices = 2
	return w


func test_encode_round_trips_through_the_prefix() -> void:
	var line := PROTOCOL.encode(PROTOCOL.hello("henesys_hg1", 2026, 3.0, "sensible", "stdio"))
	assert_true(line.begins_with(PROTOCOL.PREFIX))
	var hello: Dictionary = JSON.parse_string(line.substr(PROTOCOL.PREFIX.length()))
	assert_eq(int(hello.v), PROTOCOL.VERSION)
	assert_eq(String(hello.type), "hello")
	assert_eq(int(hello.seed), 2026)
	var answer := PROTOCOL.parse_answer(answer_line(5, "x") + "\n")
	assert_eq(int(answer.id), 5)
	assert_eq(String(answer.answer), "x")
	assert_true(PROTOCOL.parse_answer("{oops").has("error"), "a malformed answer line is reported as an error")
	assert_true(PROTOCOL.parse_answer(JSON.stringify({"v": 2, "type": "answer", "id": 1, "answer": "x"})).has("error"),
		"a wrong protocol version is an error")
