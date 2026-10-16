extends TestCase
## Seeded support auto-casts through RunWorld, canonical level snapshots and the shared status interface.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0


func _world(skill: String, seed: int = 58) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 100000
	data.balance.player.mp = 300
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	data.skills.skills["support"] = {"skill_id": 9991000, "book": "999", "kind": "buff",
		"damage": "none", "ranks": [1, 2], "buff": {"duration_field": "time", "effects": [
			{"stat": "matk", "field": "mad"}, {"stat": "pdd", "field": "pdd"},
			{"stat": "mdd", "field": "mdd"}, {"stat": "acc", "field": "acc"},
			{"stat": "avoid", "field": "eva"}]}}
	var setup := RF.setup("quiet", seed, data)
	setup.skill_imgs["999"] = {"skill": {"9991000": {"level": {
		"1": {"mpCon": 7, "time": 2, "mad": 20, "pdd": 12, "mdd": 15, "acc": 8, "eva": 20},
		"2": {"mpCon": 9, "time": 4, "mad": 30, "pdd": 18, "mdd": 21, "acc": 10, "eva": 25}}}}}
	var w := RunWorld.new(setup)
	RF.change_job_bare(w, 200)
	RF.place_player(w, 400)
	w.learn_skill(skill)
	w.drain_events()
	return w


func test_active_avoid_changes_seeded_misses_and_bless_defense_mitigates_both_hit_types() -> void:
	var misses := []
	for active: bool in [false, true]:
		var w := _world("support")
		if active:
			w.step(DT, MoveInput.new())
		assert_eq(w.player_state.avoid, w.player_avoid + (20.0 if active else 0.0))
		var count := 0
		for hit in 1000:
			w.upkeep.invincible_t = 0.0
			if w.take_hit(1, false, "", w.player.pos, {"accuracy": 20}) == 0:
				count += 1
		misses.append(count)
	assert_true(misses[1] > misses[0] + 150, "active canonical eva measurably raises seeded misses")
	for magic: bool in [false, true]:
		var damage := []
		for active: bool in [false, true]:
			var w := _world("support")
			if active:
				w.step(DT, MoveInput.new())
			damage.append(w.take_hit(100, magic, "", w.player.pos))
		assert_eq(damage[0] - damage[1], 11 if magic else 9)


func test_effect_array_coexists_with_legacy_scalar_in_one_buff_snapshot() -> void:
	var w := _world("support")
	w.book.defs.support.buff.merge({"stat": "speed", "field": "speed"})
	w.book.level_node("support", 1)["speed"] = 10
	w.step(DT, MoveInput.new())
	assert_eq(w.player.speed_stat, 110)
	assert_eq(w.buffs.effect_total("matk"), 20.0)
	assert_eq(w.player_state.buffs.size(), 1)
	assert_eq(w.player_state.buffs[0].duration, 2.0)


func _crowd() -> RunWorld:
	var w := _world("support")
	w.loadout.order.clear()
	w.book.defs.support.kind = "instant"
	w.book.defs.support.cast = {"rule": "crowd", "min_targets": 3}
	w.book.defs.support.cooldown = 1.0
	var level := w.book.level_node("support", 1)
	level.merge({"lt": {"$v": [-100, -60]}, "rb": {"$v": [100, 20]}, "mobCount": 2,
		"x": -40, "time": 2}, true)
	w.loadout.order.append("support")
	w.player.facing = -1
	return w


func test_crowd_waits_for_eligible_unslowed_threshold_caps_targets_and_pays_once() -> void:
	var w := _crowd()
	var a := RF.put_mob(w, 1110100, 380)
	var b := RF.put_mob(w, 1110100, 360)
	var boss := RF.put_mob(w, 1110100, 370)
	w.swarm.steady[boss] = 1
	RF.put_mob(w, 1110100, 700)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var mp := int(w.player_state.mp)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "bosses and out-of-box mobs cannot satisfy crowd admission")
	assert_eq(w.player_state.mp, mp)
	var c := RF.put_mob(w, 1110100, 340)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.player_state.mp, mp - 7)
	assert_near(w.swarm.status_time(a, MobSwarm.SLOW), 2.0)
	assert_near(w.swarm.status_time(b, MobSwarm.SLOW), 2.0)
	assert_near(w.swarm.slow_factor[a], 0.6)
	assert_near(w.swarm.status_time(c, MobSwarm.SLOW), 0.0, 1e-6, "mobCount caps nearest eligible targets")
	assert_near(w.swarm.status_time(boss, MobSwarm.SLOW), 0.0)
	w.runner.step(1.0, w)
	assert_eq(w.runner.casts, 1, "already slowed mobs cannot satisfy the next crowd")


func test_slow_allows_two_consecutive_casts_then_requires_a_cast_on_other_monsters() -> void:
	var w := _crowd()
	w.book.defs.support.cast.min_targets = 1
	var a := RF.put_mob(w, 1110100, 380)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	for cast in 2:
		w.runner.step(2.0, w)
		assert_eq(w.runner.casts, cast + 1)
		for tick in 120:
			w.swarm.step(DT, {"fhm": w.fhm, "target": w.player.pos, "target_fh": w.player.fh,
				"bounds": w.bounds, "events": w.events, "speed_mult": 0.0})
	# Relocation must retain consecutive-use history even though it clears the active status.
	a = w.relocate_mob(a, Vector2(380, 190), w.player.fh)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var mp := int(w.player_state.mp)
	w.runner.step(2.0, w)
	assert_eq(w.runner.casts, 2, "a third consecutive Slow is ineligible before MP payment")
	assert_eq(w.player_state.mp, mp)
	w.swarm.x[a] = 700
	var b := RF.put_mob(w, 1110100, 380)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 3, "a successful cast on another monster breaks the sequence")
	w.swarm.x[a] = 360
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(1.0, w)
	assert_eq(w.runner.casts, 4)
	assert_near(w.swarm.status_time(a, MobSwarm.SLOW), 2.0)
	w.swarm.despawn(a)
	w.swarm.despawn(b)
	var fresh := RF.put_mob(w, 1110100, 380)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.runner.step(1.0, w)
	assert_eq(w.runner.casts, 5, "fresh spawns do not inherit the previous occupant's history")
	assert_near(w.swarm.status_time(fresh, MobSwarm.SLOW), 2.0)


func test_crowd_keeps_climbing_mp_short_and_later_affordable_cast_rules() -> void:
	var w := _crowd()
	w.book.defs.support.cast.min_targets = 1
	RF.put_mob(w, 1110100, 380)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.spend_mp(int(w.player_state.mp))
	w.player.state = PlayerMotion.ST_LADDER
	w.runner.step(DT, w)
	assert_false(w.runner.waiting_mp, "climbing never enters crowd admission")
	w.player.state = PlayerMotion.ST_STAND
	w.runner.step(DT, w)
	assert_true(w.runner.waiting_mp)
	assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "mp_short").size(), 1)
	w.runner.step(DT, w)
	assert_eq(w.drain_events().size(), 0, "one shortage event per waiting episode")
	w.learn_skill("magic_guard")
	w.restore_player("mp", 6, "")
	w.runner.step(DT, w)
	assert_true(w.buffs.has("magic_guard"), "a later affordable skill still casts")
	assert_true(w.runner.waiting_mp, "earlier eligible Slow still contributes MP-short time")
	assert_eq(w.runner.casts, 1)
	assert_near(w.swarm.status_time(0, MobSwarm.SLOW), 0.0)
	w.restore_player("mp", 7, "")
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 2)
	assert_near(w.swarm.status_time(0, MobSwarm.SLOW), 2.0)


func test_multi_effect_buff_snapshots_one_timer_and_refreshes_magic_damage_on_start_and_expiry() -> void:
	var w := _world("support")
	w.learn_skill("energy_bolt")
	var before := w.runner.stats_of(w, "energy_bolt")
	var mp := int(w.player_state.mp)
	w.step(DT, MoveInput.new())
	assert_eq(w.player_state.mp, mp - 7)
	assert_eq(w.player_state.buffs.size(), 1, "all effects share one icon and timer")
	assert_eq(w.buffs.effect_total("matk"), 20.0)
	assert_eq(w.buffs.effect_total("acc"), 8.0)
	assert_eq(w.hit_defense().pdd, 12.0)
	assert_eq(w.hit_defense().mdd, 15.0)
	var active := w.runner.stats_of(w, "energy_bolt")
	assert_true(float(active.damage_min) > float(before.damage_min))
	assert_true(float(active.damage_max) > float(before.damage_max))
	w.loadout.set_rank("support", 2)
	assert_eq(w.buffs.effect_total("matk"), 20.0, "rank changes do not alter an active snapshot")
	w.spend_mp(int(w.player_state.mp))
	for tick in 120:
		w.step(DT, MoveInput.new())
	assert_false(w.buffs.has("support"))
	assert_eq(w.buffs.effect_total("acc"), 0.0)
	assert_near(w.runner.stats_of(w, "energy_bolt").damage_max, before.damage_max)
	w.restore_player("mp", 100, "")
	w.step(DT, MoveInput.new())
	assert_eq(w.buffs.effect_total("matk"), 30.0)
	assert_eq(w.player_state.buffs[0].duration, 4.0)


func test_invincible_reduces_only_weapon_damage_before_magic_guard() -> void:
	for magic: bool in [false, true]:
		var damage := []
		for active: bool in [false, true]:
			var w := _world("support")
			w.book.defs.support.buff.effects = [{"stat": "weapon_damage_reduction", "field": "x"}]
			w.book.level_node("support", 1)["x"] = 25
			w.learn_skill("magic_guard")
			if active:
				w.step(DT, MoveInput.new())
			w.runner.cooldowns.support = 100.0
			w.step(DT, MoveInput.new())
			w.drain_events()
			damage.append(w.take_hit(100, magic, "", w.player.pos))
			var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
			assert_eq(hits.size(), 1)
			assert_eq(hits[0].mp_absorbed, floori(float(hits[0].damage) * 0.11), "Guard splits the reduced damage")
		assert_eq(damage[1], damage[0] if magic else roundi(float(damage[0]) * 0.75))


func test_real_support_buffs_use_canonical_values_lifetimes_and_affordable_recasts() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	for sample: Array in [["meditation_fp", "210", 2101001, "matk", 1, 20, 10, 200, 10, 20],
			["meditation_il", "220", 2201001, "matk", 1, 20, 10, 200, 10, 20],
			["bless", "230", 2301004, "avoid", 1, 20, 10, 200, 12, 24],
			["invincible", "230", 2301003, "weapon_damage_reduction", 11, 30, 15, 300, 15, 30]]:
		for rank_index in 2:
			var key := String(sample[0])
			var w := _world(key)
			assert_true(w.loadout.has(key), "support skill is defined: " + key)
			if not w.loadout.has(key):
				continue
			w.book.skill_imgs[sample[1]] = lib.img("Skill.wz/%s.img" % sample[1]).root
			w.loadout.set_rank(key, 1 if rank_index == 0 else 20)
			var mp := int(w.player_state.mp)
			var duration := int(sample[6 + rank_index])
			w.step(DT, MoveInput.new())
			assert_eq(w.buffs.effect_total(sample[3]), float(sample[4 + rank_index]))
			assert_eq(w.player_state.buffs.size(), 1)
			assert_eq(w.player_state.buffs[0].duration, float(duration))
			assert_eq(w.player_state.mp, mp - int(sample[8 + rank_index]))
			if key == "bless":
				for stat: String in ["acc", "pdd", "mdd"]:
					assert_eq(w.buffs.effect_total(stat), float(sample[4 + rank_index]))
			w.spend_mp(int(w.player_state.mp))
			for tick in duration * 60 - 1:
				w.step(DT, MoveInput.new())
			assert_true(w.buffs.has(key), "active until exact expiry")
			w.step(DT, MoveInput.new())
			assert_false(w.buffs.has(key), "expires even when MP is short")
			assert_true(w.runner.waiting_mp)
			assert_eq(w.buffs.effect_total(sample[3]), 0.0)
			w.restore_player("mp", 100, "")
			w.step(DT, MoveInput.new())
			assert_true(w.buffs.has(key), "recasts when affordable")
			assert_eq(w.runner.casts, 2)
	lib.free()


func test_support_cards_are_branch_gated_rank_only_and_score_below_attacks() -> void:
	var w := _world("support")
	for branch: int in [210, 220, 230]:
		RF.change_job_bare(w, branch)
		var eligible := w.upgrades.eligible(w)
		for key: String in ["meditation_fp", "meditation_il", "bless", "invincible", "slow_fp", "slow_il"]:
			var own := int(w.book.def(key).get("job", -1)) == branch
			assert_eq(eligible.has(key + "_new"), own)
			assert_eq(w.book.max_rank(key), 20)
			assert_eq(BotInput.card_score(w, {"id": key + "_new"}), 50.0)
			assert_eq(w.upgrades.cards.filter(func(c: Dictionary) -> bool:
				return c.get("skill", "") == key and c.kind == "skill_mod").size(), 0)
			if own:
				assert_eq(BotInput.card_score(w, {"id": key + "_rank"}), 54.0)


func test_real_slow_copies_use_canonical_box_count_time_signed_x_and_cast_assets() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open(AssetCachePaths.resolve_cache_root()))
	for key: String in ["meditation_fp", "meditation_il", "bless", "invincible", "slow_fp", "slow_il"]:
		var w := _world(key)
		var d := w.book.def(key)
		w.book.skill_imgs[d.book] = lib.img("Skill.wz/%s.img" % d.book).root
		assert_eq(String(w.book.skill_node(key).action["0"]), String(d.action))
		assert_true(lib.anim(String(d.effect)) != null)
		assert_true(lib.frame(String(d.icon)) != null)
		assert_true(lib.sound(String(d.sounds.use)) != null)
		if not key.begins_with("slow_"):
			continue
		w.loadout.set_rank(key, 20)
		var st := w.loadout.stats(key)
		assert_eq(st.box, Rect2(-250, -150, 500, 300))
		assert_eq(st.mob_count, 6)
		assert_eq(st.cast_params.min_targets, 3)
		for index in 8:
			RF.put_mob(w, 1110100, 420 + index * 10)
		w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
		var mp := int(w.player_state.mp)
		w.runner.step(DT, w)
		assert_eq(w.player_state.mp, mp - 16)
		assert_eq(w.events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied").size(), 6)
		assert_near(w.swarm.status_time(0, MobSwarm.SLOW), 40.0)
		assert_near(w.swarm.slow_factor[0], 0.6)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
