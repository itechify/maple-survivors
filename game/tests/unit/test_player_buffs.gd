extends TestCase
## Canonical timed buff lifecycle (Nimble Feet, Magic Armor) and hit effects through seeded RunWorld ticks and take_hit.
## There is no MP or Magic Guard (#285): a buff is gated by its cooldown only.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func test_nimble_feet_uses_canonical_speed_duration_and_cast_cooldown() -> void:
	for example: Array in [[1, 10, 4], [2, 15, 8], [3, 20, 12]]:
		var data := RF.quiet_data()
		data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
		var w := RunWorld.new(RF.setup("quiet", 41, data))
		RF.place_player(w, 400)
		# The skill is set up directly: its Beginner cards are gone (#284), its skill data stays.
		w.learn_skill("nimble_feet")
		w.loadout.set_rank("nimble_feet", int(example[0]))
		w.step(DT, MoveInput.new())
		var buff := _buff(w, "nimble_feet")
		assert_false(buff.is_empty(), "Nimble Feet casts without a mob target")
		assert_eq(w.player.speed_stat, 100 + int(example[1]), "canonical speed bonus")
		if buff.is_empty():
			continue
		assert_eq(buff.icon, "Skill.wz/000.img/skill/0001002/icon")
		assert_near(float(buff.duration), float(example[2]), 1e-6)
		w.drain_events()
		for tick in int(example[2]) * 60 - 1:
			w.step(DT, MoveInput.new())
		assert_false(_buff(w, "nimble_feet").is_empty(), "active until the canonical duration")
		w.step(DT, MoveInput.new())
		assert_true(_buff(w, "nimble_feet").is_empty())
		assert_eq(w.player.speed_stat, 100, "expiry removes the speed bonus immediately")
		assert_eq(w.runner.casts, 1, "expiry alone does not bypass the 60-second canonical cooldown")
		for tick in (60 - int(example[2])) * 60 - 1:
			w.step(DT, MoveInput.new())
		assert_eq(w.runner.casts, 1, "not yet ready before 60 seconds from cast")
		w.step(DT, MoveInput.new())
		assert_eq(w.runner.casts, 2, "recasts as soon as the cooldown allows")
		assert_eq(w.player.speed_stat, 100 + int(example[1]))


func _mage(skill: String) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.player.hp = 1000
	data.balance.regen.hp = 0
	var w := RunWorld.new(RF.setup("quiet", 12, data))
	RF.change_job_bare(w, 200)
	RF.place_player(w, 400)
	w.learn_skill(skill)
	w.drain_events()
	return w


func test_nimble_feet_waits_while_climbing_and_its_active_speed_expires_there() -> void:
	var w := _mage("nimble_feet")
	RF.place_player(w, -100)
	w.step(DT, MoveInput.make(false, false, true))
	assert_eq(w.player.state, PlayerMotion.ST_LADDER)
	assert_true(_buff(w, "nimble_feet").is_empty(), "no cast while hanging")
	var jump := MoveInput.new()
	jump.jump_pressed = true
	jump.left = true
	w.step(DT, jump)
	assert_false(_buff(w, "nimble_feet").is_empty(), "casts on leaving the rope")
	assert_eq(w.player.speed_stat, 110)
	w = _mage("nimble_feet")
	w.step(DT, MoveInput.new())
	RF.place_player(w, -100)
	w.step(DT, MoveInput.make(false, false, true))
	assert_eq(w.player.state, PlayerMotion.ST_LADDER)
	assert_eq(w.player.speed_stat, 110, "the active speed bonus persists while climbing")
	for tick in 4 * 60 - 1:
		w.step(DT, MoveInput.new())
	assert_true(_buff(w, "nimble_feet").is_empty(), "expires after its four-second duration on the rope")
	assert_eq(w.player.speed_stat, 100)
	for tick in 56 * 60:
		w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1, "the ready cooldown cannot cast while hanging")
	w.step(DT, jump)
	assert_eq(w.runner.casts, 2)
	assert_eq(w.player.speed_stat, 110)


func _buff(w: RunWorld, skill: String) -> Dictionary:
	for b: Dictionary in w.player_state.get("buffs", []):
		if b.skill == skill:
			return b
	return {}


func test_armor_casts_without_a_target_and_expires_then_recasts() -> void:
	for example: Array in [["magic_armor", 54]]:
		var key: String = example[0]
		var w := _mage(key)
		w.step(DT, MoveInput.new())
		var buff := _buff(w, key)
		assert_false(buff.is_empty(), "%s auto-casts when learned, without a mob target" % key)
		if buff.is_empty():
			continue
		assert_near(buff.remaining, example[1], DT)
		assert_true(w.runner.fired_this_tick, "buff casts reserve this tick from basic attacks")
		w.drain_events()
		for i in int(example[1]) * 60 - 1:
			w.step(DT, MoveInput.new())
		assert_false(_buff(w, key).is_empty(), "active until its canonical duration")
		var expired := 0
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			expired += 1 if e.type == "buff_expired" else 0
		assert_eq(expired, 1, "expires exactly on duration")
		w.step(DT, MoveInput.new())
		assert_false(_buff(w, key).is_empty(), "recasts at once: nothing but its cooldown gates it")



func test_magic_armor_changes_the_hit_defense_only_while_cast_buff_is_active() -> void:
	var damage := []
	for active: bool in [false, true]:
		var w := _mage("magic_armor")
		w.loadout.set_rank("magic_armor", 20)
		w.refresh_player_stats()
		if active:
			w.step(DT, MoveInput.new())
		assert_eq(w.hit_defense().pdd, 40.0 if active else 0.0)
		w.drain_events()
		w.take_hit(100, false, "", w.player.pos + Vector2(10, 0), {"accuracy": 1000000})
		var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
		assert_eq(hits.size(), 1)
		damage.append(int(hits[0].damage))
	assert_eq(damage[0] - damage[1], 30, "canonical 40 PDD reduces this same seeded hit by floor(.75 × 40)")


func test_climbing_blocks_buff_casts_but_active_effects_expire_on_time_and_recast_after_exit() -> void:
	for example: Array in [["magic_armor", 54, "pdd", 2.0]]:
		var key: String = example[0]
		var w := _mage(key)
		RF.place_player(w, -100)
		w.step(DT, MoveInput.make(false, false, true))
		assert_eq(w.player.state, PlayerMotion.ST_LADDER)
		assert_true(_buff(w, key).is_empty(), "no cast while hanging")
		var jump := MoveInput.new()
		jump.jump_pressed = true
		jump.left = true
		w.step(DT, jump)
		assert_false(_buff(w, key).is_empty(), "casts on the exit tick")
		# A fresh run casts before grabbing, so its whole lifetime can be measured on the rope.
		w = _mage(key)
		w.step(DT, MoveInput.new())
		RF.place_player(w, -100)
		w.step(DT, MoveInput.make(false, false, true))
		assert_eq(w.player.state, PlayerMotion.ST_LADDER)
		assert_eq(w.buffs.effect_total(example[2]), example[3], "active effect keeps working while climbing")
		for i in int(example[1]) * 60 - 2:
			w.step(DT, MoveInput.new())
		assert_false(_buff(w, key).is_empty())
		w.step(DT, MoveInput.new())
		assert_eq(w.player.state, PlayerMotion.ST_LADDER)
		assert_true(_buff(w, key).is_empty(), "expires on time while hanging and cannot recast there")
		assert_eq(w.buffs.effect_total(example[2]), 0.0)
		w.step(DT, jump)
		assert_false(_buff(w, key).is_empty())


func test_buffs_share_the_one_cast_per_tick_learned_order_with_attack_skills() -> void:
	var w := _mage("nimble_feet")
	w.learn_skill("magic_armor")
	w.learn_skill("energy_bolt")
	RF.put_mob(w, 1110100, 550, 190, 100)
	for expected: String in ["nimble_feet", "magic_armor", "energy_bolt"]:
		w.step(DT, MoveInput.new())
		var casts := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast")
		assert_eq(casts.size(), 1)
		assert_eq(casts[0].skill, expected)
		assert_true(w.runner.fired_this_tick)
