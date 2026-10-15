extends TestCase
## Canonical timed Guard/Armor lifecycle and hit effects through seeded RunWorld ticks and take_hit.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _mage(skill: String) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 1000
	data.balance.player.mp = 300
	data.balance.regen.mp = 0
	data.balance.regen.hp = 0
	var w := RunWorld.new(RF.setup("quiet", 12, data))
	RF.change_job_bare(w, 200)
	RF.place_player(w, 400)
	w.learn_skill(skill)
	w.drain_events()
	return w


func _buff(w: RunWorld, skill: String) -> Dictionary:
	for b: Dictionary in w.player_state.get("buffs", []):
		if b.skill == skill:
			return b
	return {}


func test_guard_and_armor_cast_without_a_target_pay_mp_and_expire_then_wait_and_recast() -> void:
	for example: Array in [["magic_guard", 6, 111], ["magic_armor", 8, 54]]:
		var key: String = example[0]
		var w := _mage(key)
		var before: int = w.player_state.mp
		w.step(DT, MoveInput.new())
		var buff := _buff(w, key)
		assert_false(buff.is_empty(), "%s auto-casts when learned, without a mob target" % key)
		assert_eq(w.player_state.mp, before - int(example[1]))
		if buff.is_empty():
			continue
		assert_near(buff.remaining, example[2], DT)
		assert_true(w.runner.fired_this_tick, "buff casts reserve this tick from basic attacks")
		w.spend_mp(int(w.player_state.mp))
		w.drain_events()
		for i in int(example[2]) * 60 - 1:
			w.step(DT, MoveInput.new())
		assert_false(_buff(w, key).is_empty(), "active until its canonical duration")
		w.step(DT, MoveInput.new())
		assert_true(_buff(w, key).is_empty(), "expires exactly on duration")
		assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "buff_expired").size(), 1)
		w.heal_fraction("mp", 1.0)
		before = int(w.player_state.mp)
		w.step(DT, MoveInput.new())
		assert_false(_buff(w, key).is_empty(), "recasts as soon as affordable")
		assert_eq(w.player_state.mp, before - int(example[1]))



func test_magic_guard_splits_damage_only_while_cast_buff_is_active() -> void:
	for active: bool in [false, true]:
		var w := _mage("magic_guard")
		if active:
			w.step(DT, MoveInput.new())
		var mp := int(w.player_state.mp)
		w.drain_events()
		w.take_hit(100, false, "", w.player.pos + Vector2(10, 0), {"accuracy": 1000000})
		var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
		assert_eq(hits.size(), 1)
		if not hits.is_empty():
			assert_eq(hits[0].mp_absorbed, floori(float(hits[0].damage) * 0.11) if active else 0)
			assert_eq(w.player_state.mp, mp - int(hits[0].mp_absorbed))


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
	for example: Array in [["magic_guard", 111, "mp_guard", 11.0], ["magic_armor", 54, "pdd", 2.0]]:
		var key: String = example[0]
		var w := _mage(key)
		RF.place_player(w, -100)
		var before: int = w.player_state.mp
		w.step(DT, MoveInput.make(false, false, true))
		assert_eq(w.player.state, PlayerMotion.ST_LADDER)
		assert_true(_buff(w, key).is_empty())
		assert_eq(w.player_state.mp, before, "no MP spent while hanging")
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
	var w := _mage("magic_guard")
	w.learn_skill("magic_armor")
	w.learn_skill("energy_bolt")
	RF.put_mob(w, 1110100, 550, 190, 100)
	for expected: String in ["magic_guard", "magic_armor", "energy_bolt"]:
		w.step(DT, MoveInput.new())
		var casts := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "cast")
		assert_eq(casts.size(), 1)
		assert_eq(casts[0].skill, expected)
		assert_true(w.runner.fired_this_tick)
