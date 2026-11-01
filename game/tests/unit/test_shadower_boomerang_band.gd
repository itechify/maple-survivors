extends TestCase
## Shadower's two multi-target skills (spec #425, ticket SH8 #433): Boomerang Step (a forward-line box that stabs the
## 2 / 3 / 4 nearest monsters twice each and stuns on `prop`) and Band of Thieves (a symmetric box whose `x` "other
## selves" each land one line on the 2 / 4 / 6 nearest), with their rarity bonuses. Fixed 1/60 s ticks, seeded RNG, a
## dagger in hand. The behaviour tests run on synthetic book-421/422 level tables shaped like Skill.wz (Band of Thieves'
## damage drops where its `x` steps up, exactly as in the WZ); the real-cache test at the end calls require_cache() and
## SKIPS without the cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const RAZOR := 1332005
const STEP := "boomerang_step"
const BAND := "band_of_thieves"
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Skill.wz 4211004 levels 1..30 (damage, x, mobCount, half-width of the box), read from the v83 data (SH1 scan).
const BAND_DAMAGE := [110, 120, 130, 140, 150, 160, 120, 130, 140, 150, 160, 170, 130, 140, 150, 160, 170, 180, 140, 150, 160, 170, 180, 190, 160, 170, 180, 190, 200, 210]
const BAND_X := [1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5]
const BAND_MOBS := [2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 5, 5, 6, 6, 6, 6, 6, 6]
const BAND_HALF := [130, 130, 130, 130, 130, 130, 135, 135, 135, 135, 135, 135, 140, 140, 140, 140, 140, 140, 145, 145, 145, 145, 145, 145, 150, 150, 150, 150, 150, 150]
## Skill.wz 4221007 levels 1..30.
const STEP_DAMAGE := [260, 270, 280, 290, 300, 310, 320, 330, 340, 350, 360, 370, 380, 390, 400, 410, 420, 430, 440, 450, 455, 460, 465, 470, 475, 480, 485, 490, 495, 500]
const STEP_MOBS := [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4]
const STEP_PROP := [32, 34, 36, 38, 40, 42, 44, 46, 48, 50, 52, 54, 56, 58, 60, 62, 64, 66, 68, 70, 72, 74, 76, 78, 80, 82, 84, 86, 88, 90]
const STEP_TIME := [2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4]


func _band_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var half := float(BAND_HALF[lv - 1])
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": float(BAND_DAMAGE[lv - 1]), "x": float(BAND_X[lv - 1]),
			"mobCount": float(BAND_MOBS[lv - 1]), "lt": {"$v": [-half, -50.0]}, "rb": {"$v": [half, 50.0]}}
	return levels


func _step_levels(prop_override := -1.0) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": float(STEP_DAMAGE[lv - 1]), "attackCount": 2.0,
			"mobCount": float(STEP_MOBS[lv - 1]), "prop": prop_override if prop_override >= 0.0 else float(STEP_PROP[lv - 1]),
			"time": float(STEP_TIME[lv - 1]), "lt": {"$v": [-300.0, -110.0]}, "rb": {"$v": [0.0, 0.0]}}
	return levels


## A quiet round of a Shadower holding a Razor with `key` learned at `rank_value`; god mode, frozen snail-sized mobs.
func _world(key: String, rank_value := 1, p_seed := 433, prop_override := -1.0) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["422"]["playable"] = true # in this test's data only: SH14 ships the flip
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({RAZOR: {"incPAD": 20, "attackSpeed": 4, "tuc": 7, "afterImage": "swordOS", "sfx": "swordS"}}, true)
	for action: String in ["alert5", "swingO1", "stabO1"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.skill_imgs["421"] = {"skill": {"4211004": {"weapon": 33, "level": _band_levels()}}}
	setup.skill_imgs["422"] = {"skill": {"4221007": {"weapon": 33, "level": _step_levels(prop_override)}}}
	setup["job"] = 422
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	if w.weapon_id() != RAZOR:
		w.wear_new_item(RAZOR)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill: only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Shadower" % key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190.0, 100000.0)
	w.swarm.hp[slot] = 100000000
	w.swarm.max_hp[slot] = 100000000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(events: Array, key: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == key)


## Runs `ticks` ticks and returns every mob_hit event of `key`, in order.
func _run(w: RunWorld, ticks: int, key: String) -> Array:
	var out := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		out.append_array(_hits(w.drain_events(), key))
	return out


func _struck(hits: Array) -> Dictionary:
	var out := {}
	for e: Dictionary in hits:
		out[int(e.mob)] = int(out.get(int(e.mob), 0)) + 1
	return out


func _stunned(w: RunWorld, slot: int) -> bool:
	return w.swarm.status_time(slot, MobSwarm.STUN) > 0.0


func _mod(w: RunWorld, key: String, stat: String, op: String, value: float) -> void:
	w.loadout.add_skill_mod(key, stat, op, value)


# --- Boomerang Step ---------------------------------------------------------------------------------------------------

func test_boomerang_step_is_a_forward_box_with_a_stun_and_the_shipped_art() -> void:
	var w := _world(STEP)
	var d := w.book.def(STEP)
	assert_eq(int(d.skill_id), 4221007)
	assert_eq(String(d.book), "422")
	assert_eq(int(d.job), 422)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.cast.rule), "box")
	assert_eq(String(d.damage), "physical")
	assert_eq(String(d.action), "alert5")
	assert_eq(String(d.effect), "Skill.wz/422.img/skill/4221007/effect")
	assert_eq(String(d.hit), "Skill.wz/422.img/skill/4221007/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4221007/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/4221007/Hit")
	assert_eq(d.on_hit, {"status": "stun", "chance_field": "prop", "duration_field": "time", "once_per_target": true})
	assert_false(d.has("weapon_families"), "weapons gate nothing")
	assert_false(d.has("ranks"), "the default 30-level rank table")
	assert_false(d.has("attack_count_field"), "Boomerang Step reads the node's attackCount")
	var st := w.loadout.stats(STEP)
	assert_near(st.cooldown, 3.0, 0.0001)
	assert_eq(st.box, Rect2(-300, -110, 300, 110), "the WZ forward line, left-authored")
	assert_eq(st.attack_count, 2)


func test_boomerang_step_waits_for_a_monster_in_the_line() -> void:
	var w := _world(STEP)
	w.player.facing = -1
	_mob(w, 150) # behind the caster
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0, "nothing in front: no cast")
	_mob(w, -150)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[STEP]), 3.0 - DT, 0.001)


func test_boomerang_step_line_follows_the_facing() -> void:
	for facing in [-1, 1]:
		var w := _world(STEP)
		w.player.facing = facing
		var front := _mob(w, 120.0 * facing)
		var behind := _mob(w, -120.0 * facing)
		var far := _mob(w, 340.0 * facing)
		var struck := _struck(_run(w, 5, STEP))
		assert_true(struck.has(front), "facing %d: in front" % facing)
		assert_false(struck.has(behind), "facing %d: not behind" % facing)
		assert_false(struck.has(far), "facing %d: past the 300 px line" % facing)


func test_boomerang_step_stabs_the_nearest_two_three_four_twice_each() -> void:
	for rank_pair: Array in [[1, 2], [4, 3], [8, 4]]:
		var w := _world(STEP, rank_pair[0])
		w.player.facing = -1
		var slots := []
		for k in 6:
			slots.append(_mob(w, -(20.0 + 30.0 * k)))
		var struck := _struck(_run(w, 5, STEP))
		assert_eq(struck.size(), rank_pair[1], "rank %d: mobCount" % rank_pair[0])
		for k in int(rank_pair[1]):
			assert_eq(int(struck.get(slots[k], 0)), 2, "rank %d: target %d takes both lines" % [rank_pair[0], k])


func test_boomerang_step_stuns_on_prop_and_never_a_boss() -> void:
	var w := _world(STEP, 8, 433, 100.0)
	w.player.facing = -1
	var a := _mob(w, -60)
	var boss := _mob(w, -100, true)
	var hits := _run(w, 5, STEP)
	var struck := _struck(hits)
	assert_true(_stunned(w, a), "prop 100: the snail is stunned")
	assert_near(w.swarm.status_time(a, MobSwarm.STUN), 4.0, 0.2, "rank 8 stuns for 4 s")
	assert_eq(int(struck.get(boss, 0)), 2, "the boss is damaged")
	assert_false(_stunned(w, boss), "and never stunned")
	var none := _world(STEP, 8, 433, 0.0)
	none.player.facing = -1
	var b := _mob(none, -60)
	_run(none, 5, STEP)
	assert_false(_stunned(none, b), "prop 0 never stuns")


## How many of `casts` seeded rank-`rank` casts at one snail stun it (D18: one roll per struck target, not per line).
func _stun_count(rank: int, casts: int) -> int:
	var stunned := 0
	for p_seed in range(1, casts + 1):
		var w := _world(STEP, rank, p_seed)
		w.player.facing = -1
		var m := _mob(w, -60)
		_run(w, 5, STEP)
		if _stunned(w, m):
			stunned += 1
	return stunned


func test_boomerang_step_rolls_the_stun_once_per_struck_monster_at_the_ranks_chance() -> void:
	# D18 (review #425 S2): the WZ `prop` is a per-target chance; the two damage lines roll it once (the first line), so a
	# snail is stunned on 38 / 60 / 90 % of casts at ranks 1 / 4 / 8. Per-line rolling would give 62 / 84 / 99 %.
	# Bounds are the binomial mean +- 3.5 sd for the right chance, which exclude the per-line one at every rank.
	var one := _stun_count(1, 100) # 38 +- 17 (per-line: 62)
	assert_true(one >= 21 and one <= 55, "rank 1: 38%% of 100 casts stun (%d did)" % one)
	var four := _stun_count(4, 100) # 60 +- 17 (per-line: 84)
	assert_true(four >= 43 and four <= 77, "rank 4: 60%% of 100 casts stun (%d did)" % four)
	var eight := _stun_count(8, 200) # 180 +- 15 (per-line: 198)
	assert_true(eight >= 165 and eight <= 193, "rank 8: 90%% of 200 casts stun (%d did)" % eight)


func test_boomerang_step_stun_lasts_the_rank_time() -> void:
	var w := _world(STEP, 1, 1, 100.0)
	w.player.facing = -1
	var m := _mob(w, -60)
	_run(w, 5, STEP)
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 2.0, 0.2, "rank 1 stuns for 2 s")


func test_the_per_target_roll_is_opt_in_and_other_skills_still_roll_per_line() -> void:
	# Only the data key `on_hit.once_per_target` changes the roll: without it the same two-line skill rolls twice per target.
	var per_line := 0
	for p_seed in range(1, 101):
		var w := _world(STEP, 1, p_seed)
		w.book.defs[STEP] = w.book.defs[STEP].duplicate(true)
		w.book.defs[STEP].on_hit.erase("once_per_target")
		w.player.facing = -1
		var m := _mob(w, -60)
		_run(w, 5, STEP)
		if _stunned(w, m):
			per_line += 1
	assert_true(per_line >= 48, "per-line rolling stuns about 62%% of casts (%d of 100)" % per_line)


# --- Band of Thieves --------------------------------------------------------------------------------------------------

func test_band_of_thieves_is_a_symmetric_box_whose_lines_come_from_x() -> void:
	var w := _world(BAND)
	var d := w.book.def(BAND)
	assert_eq(int(d.skill_id), 4211004)
	assert_eq(String(d.book), "421")
	assert_eq(int(d.job), 421)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.cast.rule), "box")
	assert_eq(String(d.damage), "physical")
	assert_eq(String(d.attack_count_field), "x")
	assert_eq(String(d.action), "weapon", "the node has no action: the held dagger's stance")
	assert_eq(String(d.effect), "Skill.wz/421.img/skill/4211004/effect")
	assert_eq(String(d.hit), "Skill.wz/421.img/skill/4211004/hit/0")
	assert_eq(d.hit_lines.size(), 6, "thief figures hit/1..5, one per line, and hit/0 for the sixth line Bigger Band adds at rank 8")
	assert_eq(String(d.hit_lines[5]), "Skill.wz/421.img/skill/4211004/hit/0")
	for i in 5:
		assert_eq(String(d.hit_lines[i]), "Skill.wz/421.img/skill/4211004/hit/%d" % (i + 1))
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4211004/Use")
	assert_false(d.has("on_hit"), "no status")
	assert_false(d.has("weapon_families"))
	assert_false(d.has("ranks"))
	assert_near(w.loadout.stats(BAND).cooldown, 8.0, 0.0001)


func test_band_lines_monsters_and_box_by_rank_follow_the_node() -> void:
	var lo := _world(BAND).loadout
	for r in range(1, 9):
		var lv: int = LEVELS[r - 1]
		var st := lo.stats(BAND, r)
		assert_eq(st.level, lv)
		assert_eq(st.attack_count, int(BAND_X[lv - 1]), "rank %d: lines = x" % r)
		assert_eq(st.mob_count, int(BAND_MOBS[lv - 1]), "rank %d: mobCount" % r)
		assert_near(st.damage_pct, float(BAND_DAMAGE[lv - 1]) / 100.0, 0.000001, "rank %d: per-line percent" % r)
		var half := float(BAND_HALF[lv - 1])
		assert_eq(st.box, Rect2(-half, -50.0, 2.0 * half, 100.0), "rank %d: symmetric box" % r)
	assert_eq([lo.stats(BAND, 1).attack_count, lo.stats(BAND, 4).attack_count, lo.stats(BAND, 8).attack_count], [1, 3, 5])
	assert_eq([lo.stats(BAND, 1).mob_count, lo.stats(BAND, 4).mob_count, lo.stats(BAND, 8).mob_count], [2, 4, 6])


func test_the_per_line_percent_drops_where_x_steps_up_but_the_per_cast_total_always_rises() -> void:
	var lo := _world(BAND).loadout
	var dropped := false
	var previous := 0.0
	var previous_pct := 0.0
	for r in range(1, 9):
		var st := lo.stats(BAND, r)
		if r > 1 and st.damage_pct < previous_pct:
			dropped = true
		var total: float = st.damage_pct * st.attack_count * st.mob_count
		assert_true(total > previous, "rank %d: the cast total (%.2f) beats rank %d (%.2f)" % [r, total, r - 1, previous])
		assert_true(st.damage_pct * st.attack_count > (previous / maxf(1.0, lo.stats(BAND, maxi(1, r - 1)).mob_count)),
			"rank %d: the per-monster total never falls" % r)
		previous = total
		previous_pct = st.damage_pct
	assert_true(dropped, "the synthetic table reproduces the WZ drop of the per-line percent")


func test_band_of_thieves_hits_the_nearest_two_four_six_with_one_three_five_lines_each() -> void:
	for rank_pair: Array in [[1, 2, 1], [4, 4, 3], [8, 6, 5]]:
		var w := _world(BAND, rank_pair[0])
		var slots := []
		for k in 8:
			slots.append(_mob(w, (-1.0 if k % 2 == 0 else 1.0) * (20.0 + 8.0 * k)))
		var struck := _struck(_run(w, 5, BAND))
		assert_eq(struck.size(), rank_pair[1], "rank %d: mobCount" % rank_pair[0])
		for k in int(rank_pair[1]):
			assert_eq(int(struck.get(slots[k], 0)), rank_pair[2], "rank %d: target %d takes every other self's line" % [rank_pair[0], k])


func test_band_of_thieves_strikes_both_sides_inside_the_box_only() -> void:
	var w := _world(BAND)
	var left := _mob(w, -110)
	var right := _mob(w, 110)
	var outside := _mob(w, 175) # the body starts at 155: past the +-130 box of rank 1
	var struck := _struck(_run(w, 5, BAND))
	assert_true(struck.has(left) and struck.has(right))
	assert_false(struck.has(outside))


func test_band_of_thieves_stuns_nothing_and_damages_a_boss() -> void:
	var w := _world(BAND, 8)
	var snail := _mob(w, -50)
	var boss := _mob(w, 50, true)
	var struck := _struck(_run(w, 5, BAND))
	assert_eq(int(struck.get(snail, 0)), 5)
	assert_eq(int(struck.get(boss, 0)), 5, "bosses are damaged")
	assert_false(_stunned(w, snail) or _stunned(w, boss))


func test_each_band_line_carries_its_thief_figure_art() -> void:
	var w := _world(BAND, 8)
	_mob(w, -50)
	var hits := _run(w, 5, BAND)
	assert_eq(hits.size(), 5)
	for i in 5:
		assert_eq(String(hits[i].hit_visual), "Skill.wz/421.img/skill/4211004/hit/%d" % (i + 1), "line %d" % i)


# --- Rarity bonuses ---------------------------------------------------------------------------------------------------

const RARITY := {
	STEP: [["dagger_mastery", "damage", "mul", 1.2], ["dagger_booster", "cooldown", "mul", 0.88], ["second_pass", "count", "add", 1.0]],
	BAND: [["band_mastery", "damage", "mul", 1.2], ["wide_band", "area", "mul", 1.2], ["bigger_band", "attack_count", "add", 1.0]],
}


func test_the_rarity_tables_follow_the_spec() -> void:
	var w := _world(STEP)
	for key: String in RARITY:
		var bonuses: Dictionary = w.book.def(key).rarity_bonuses
		var rows: Array = RARITY[key]
		assert_eq(bonuses.keys().size(), 4, "%s: exactly the four tiers" % key)
		for t in 3:
			var tier: String = ["rare", "epic", "unique"][t]
			assert_eq(bonuses[tier].size(), 1, "%s %s" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), String(rows[t][0]), "%s %s" % [key, tier])
			assert_true(String(bonuses[tier][0].text) != "", "%s %s has card text" % [key, tier])
			assert_eq(bonuses[tier][0].effects.size(), 1)
			var effect: Dictionary = bonuses[tier][0].effects[0]
			assert_eq(String(effect.stat), String(rows[t][1]))
			assert_eq(String(effect.op), String(rows[t][2]))
			assert_near(float(effect.value), float(rows[t][3]), 0.0001)
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(String(legendary.id), String(rows[2][0]), "%s: Legendary shares the Unique's id (and its repeat counter)" % key)
		assert_eq(legendary.effects.size(), 2)
		assert_eq(String(legendary.effects[0].stat), String(rows[2][1]))
		assert_near(float(legendary.effects[0].value), float(rows[2][3]), 0.0001)
		assert_eq(String(legendary.effects[1].stat), "damage")
		assert_near(float(legendary.effects[1].value), 1.2, 0.0001)


## What a cast of `key` did below: the total damage, the hit lines, the monsters struck, the cooldown, and whether the edge
## monster (just beyond the base reach) was struck; `effects` are applied as skill modifiers first.
func _probe(key: String, effects: Array) -> Dictionary:
	var w := _world(key, 8)
	w.player.facing = -1
	for effect: Dictionary in effects:
		_mod(w, key, String(effect.stat), String(effect.op), float(effect.value))
	var reach := 300.0 if key == STEP else 150.0 # rank 8
	var sign_x := -1.0
	# Three monsters well inside the reach (the caps of four / six would otherwise crowd the edge one out), eight when
	# `count` is probed.
	var crowd := 8 if effects.any(func(e: Dictionary) -> bool: return String(e.stat) == "count") else 3
	for k in crowd:
		_mob(w, sign_x * (10.0 + 10.0 * k))
	var edge := _mob(w, sign_x * (reach + 25.0)) # the body starts at reach + 5: outside the base box, inside x1.2
	var hits := _run(w, 5, key)
	var dealt := 0.0
	for e: Dictionary in hits:
		dealt += float(e.damage)
	var struck := _struck(hits)
	return {"dealt": dealt, "lines": hits.size(), "mobs": struck.size(), "edge": struck.has(edge),
		"cooldown": w.loadout.stats(key).cooldown}


func test_every_bonus_changes_the_resolved_cast() -> void:
	var skills := _world(STEP).book
	for key: String in RARITY:
		var bonuses: Dictionary = skills.def(key).rarity_bonuses
		var base := _probe(key, [])
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			for effect: Dictionary in bonuses[tier][0].effects:
				var with_effect := _probe(key, [effect])
				var label := "%s %s %s" % [key, tier, String(effect.stat)]
				match String(effect.stat):
					"damage":
						assert_true(float(with_effect.dealt) > float(base.dealt), label)
					"cooldown":
						assert_true(float(with_effect.cooldown) < float(base.cooldown), label)
						assert_near(float(with_effect.cooldown), float(base.cooldown) * 0.88, 0.0001, label)
					"area":
						assert_false(bool(base.edge), label + ": the edge monster is outside the base box")
						assert_true(bool(with_effect.edge), label)
					"attack_count":
						assert_true(int(with_effect.lines) > int(base.lines), label)
						assert_eq(int(with_effect.lines), int(base.lines) + int(base.mobs), label + ": one more line on each struck monster")
					"count":
						assert_true(int(with_effect.mobs) > int(base.mobs), label)
					_:
						assert_true(false, label + ": unprobed stat")


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for key: String in RARITY:
		for tier: String in ["rare", "epic", "unique", "legendary"]:
			var w := _world(key)
			var card := w.upgrades.choice_card(key + "_rank", w, tier)
			assert_false(card.get("rarity_bonus", {}).is_empty(), "%s %s carries a bonus" % [key, tier])
			w.upgrades.apply(key + "_rank", w, tier)
			assert_eq(w.loadout.rank(key), 2, "%s %s: one rank, whatever the rarity" % [key, tier])
			var st := w.loadout.stats(key)
			match tier:
				"rare":
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2, 0.0001)
				"epic":
					if key == STEP:
						assert_near(st.cooldown, 3.0 * 0.88, 0.0001)
					else:
						assert_near(st.area, 1.2, 0.0001)
				"unique", "legendary":
					if key == STEP:
						assert_eq(st.mob_count, 3, "rank 2 reads WZ level 8 (2 monsters) plus Second Pass")
					else:
						assert_eq(st.attack_count, 3, "rank 2 reads WZ level 8 (x 2) plus Bigger Band")
					assert_near(w.loadout.skill_stat(key, "damage", 1.0), 1.2 if tier == "legendary" else 1.0, 0.0001)


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	for key: String in RARITY:
		var w := _world(key)
		var unique_id: String = RARITY[key][2][0]
		w.upgrades.apply(key + "_rank", w, "unique")
		w.upgrades.apply(key + "_rank", w, "legendary")
		assert_eq(int(w.loadout.card_ranks["bonus:%s:%s" % [key, unique_id]]), 2, "%s: one shared counter" % key)
		var m := _world(key)
		m.loadout.set_rank(key, 8)
		var c := m.upgrades.choice_card(key + "_rank", m, "rare")
		assert_eq(c.card_kind, "mastery", "%s: at rank 8 the rank card is a Mastery card" % key)
		m.upgrades.apply(key + "_rank", m, "rare")
		m.upgrades.apply(key + "_rank", m, "rare")
		assert_near(m.loadout.skill_stat(key, "damage", 1.0), 1.2 * (1.0 + 0.2 * 0.8), 0.00001, "%s: the repeat is x0.8" % key)
		assert_eq(m.loadout.rank(key), 8)


func test_the_bot_scores_the_learn_card_100_and_the_rank_card_74_and_takes_them_over_a_passive() -> void:
	for key: String in [STEP, BAND]:
		var w := _world(key)
		var learn_world := _world(key)
		learn_world.loadout.ranks.erase(key) # a round that has not learned it yet
		var learn := learn_world.upgrades.choice_card(key + "_new", learn_world, "normal")
		assert_false(learn.is_empty(), "%s is offered as a new skill" % key)
		assert_eq(BotInput.card_score(learn_world, learn), 100.0, key + " learn card")
		var rank := w.upgrades.choice_card(key + "_rank", w, "normal")
		assert_false(rank.is_empty(), "%s is offered as a rank card" % key)
		assert_eq(BotInput.card_score(w, rank), 74.0, key + " rank card")
		var passive := w.upgrades.choice_card("passive_might_new", w, "normal")
		if not passive.is_empty():
			assert_eq(BotInput.pick_card_for(learn_world, [passive, learn]), key + "_new")


func test_the_skill_window_names_the_lines_the_monsters_and_the_stun() -> void:
	var w := _world(BAND, 8)
	var text := SkillText.new(w.book)
	var h := MapleText.plain(text.level_line(BAND, 30, w.loadout.stats(BAND, 8)))
	assert_true(h.contains("210%"), h)
	assert_true(h.contains("5"), h)
	assert_true(h.contains("6 monsters"), h)
	var step := MapleText.plain(text.level_line(STEP, 30, w.loadout.stats(STEP, 8)))
	assert_true(step.contains("500%") and step.contains("4 monsters") and step.contains("90%") and step.contains("4 sec"), step)


# --- real cache: all eight ranks against Skill.wz ---------------------------------------------------------------------

func test_real_cache_all_eight_ranks_of_both_skills_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var img_421 := lib.img("Skill.wz/421.img")
	var img_422 := lib.img("Skill.wz/422.img")
	assert_true(img_421 != null and img_422 != null, "Skill.wz/421.img and 422.img are in the cache")
	if img_421 == null or img_422 == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"421": img_421.root, "422": img_422.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "dagger"
	var band_node: Dictionary = img_421.root.skill["4211004"]
	var step_node: Dictionary = img_422.root.skill["4221007"]
	for key: String in [BAND, STEP]:
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.max_rank(key), 8, key)
	var previous_total := 0.0
	for rank_value in range(1, 9):
		var lv: int = LEVELS[rank_value - 1]
		var label := "rank %d (level %d)" % [rank_value, lv]
		assert_eq(book.canonical_level(BAND, rank_value), lv, label)
		var band_level: Dictionary = band_node.level[str(lv)]
		var b := lo.stats(BAND, rank_value)
		assert_near(b.damage_pct, float(band_level.damage) / 100.0, 0.000001, "Band " + label)
		assert_eq(b.attack_count, int(band_level.x), "Band lines " + label)
		assert_eq(b.mob_count, int(band_level.mobCount), "Band monsters " + label)
		var lt: Array = band_level.lt["$v"]
		var rb: Array = band_level.rb["$v"]
		assert_eq(b.box, Rect2(float(lt[0]), float(lt[1]), float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])), "Band box " + label)
		assert_eq(b.box.position.x, -b.box.end.x, "Band box is symmetric " + label)
		assert_eq(b.box.size.y, 100.0, label)
		var total: float = b.damage_pct * b.attack_count * b.mob_count
		assert_true(total > previous_total, "Band per-cast total rises at " + label)
		previous_total = total
		var step_level: Dictionary = step_node.level[str(lv)]
		var s := lo.stats(STEP, rank_value)
		assert_near(s.damage_pct, float(step_level.damage) / 100.0, 0.000001, "Step " + label)
		assert_eq(s.attack_count, 2, "Step lines " + label)
		assert_eq(s.mob_count, int(step_level.mobCount), "Step monsters " + label)
		assert_eq(s.knockback_chance, 0.0, label)
		assert_eq(book.canonical(STEP, lv, "prop"), float(step_level.prop), "Step stun chance " + label)
		assert_eq(book.canonical(STEP, lv, "time"), float(step_level.time), "Step stun seconds " + label)
		assert_eq(s.box, Rect2(-300, -110, 300, 110), "Step box " + label)
	# The spec's worked rank values (rank 1 / 4 / 8) as literals.
	for i in 3:
		var r: int = [1, 4, 8][i]
		var lv: int = LEVELS[r - 1]
		assert_near(lo.stats(STEP, r).damage_pct, [2.9, 4.0, 5.0][i], 0.000001, "Boomerang Step damage rank %d" % r)
		assert_eq(lo.stats(STEP, r).mob_count, [2, 3, 4][i])
		assert_eq(book.canonical(STEP, lv, "prop"), [38.0, 60.0, 90.0][i])
		assert_eq(book.canonical(STEP, lv, "time"), [2.0, 3.0, 4.0][i])
		assert_near(lo.stats(BAND, r).damage_pct, [1.4, 1.5, 2.1][i], 0.000001, "Band damage rank %d" % r)
		assert_eq(lo.stats(BAND, r).attack_count, [1, 3, 5][i])
		assert_eq(lo.stats(BAND, r).mob_count, [2, 4, 6][i])
		assert_eq(lo.stats(BAND, r).box.size.x, [260.0, 280.0, 300.0][i])
	# The importer's per-level drop of Band's damage is in the cache, and its line count steps up there.
	assert_true(float(band_node.level["7"].damage) < float(band_node.level["6"].damage))
	assert_true(float(band_node.level["7"].x) > float(band_node.level["6"].x))
	# Art and sounds resolve in the cache (hit/0 plus the five thief figures).
	for key: String in [BAND, STEP]:
		var d := book.def(key)
		var paths: Array = [d.effect, d.ball, d.hit]
		paths.append_array(d.get("hit_lines", []))
		for path: String in paths:
			if path != "":
				assert_true(lib.anim(path).frames.size() > 0, path)
		for path: String in d.sounds.values():
			if path != "":
				assert_true(lib.sound(path) != null, path)
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
