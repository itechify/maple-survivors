extends TestCase
## Support summons (spec #348 M10, ticket #352): a follower that pulses instead of attacking, tested on a synthetic
## Beholder (made-up job 999, skills 9990001-9990003, no Dark Knight data). This file is the template a later job
## copies for its own support summon.
const SSF := preload("res://tests/fixtures/support_summon_fixtures.gd")
const DT := 1.0 / 60.0
const PARENT := SSF.PARENT
const AURA := SSF.AURA
const HEX := SSF.HEX


func _world(seed_value := 352) -> RunWorld:
	return SSF.world(seed_value)


func _run(w: RunWorld, seconds: float) -> void:
	for tick in roundi(seconds / DT):
		w.step(DT, MoveInput.new())


func _events(w: RunWorld, type: String) -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == type)


## The support_pulse events of one pulse kind.
func _pulses(w: RunWorld, kind: String) -> Array:
	return _events(w, "support_pulse").filter(func(e: Dictionary) -> bool: return e.kind == kind)


func test_a_support_summon_spawns_follows_and_expires_without_an_attack() -> void:
	var w := _world()
	_run(w, DT)
	w.loadout.order.clear() # one cast only: no recast at the 45 s cooldown
	assert_eq(w.runner.summons.living_count(), 1)
	assert_eq(_events(w, "summon_spawn").size(), 1)
	w.player.pos.x += 400.0
	_run(w, 2.0)
	assert_true(w.runner.summons.x[0] > 400.0, "the Beholder follows its owner")
	assert_eq(_events(w, "summon_attack").size(), 0, "a support summon never attacks")
	_run(w, 60.0)
	assert_eq(w.runner.summons.living_count(), 0, "it expires with the canonical time")


func _hurt(w: RunWorld, amount: int) -> void:
	assert_true(w.spend_hp(amount), "setup: the owner can afford %d HP" % amount)


func test_heal_pulse_restores_the_sub_hp_at_its_first_interval_then_every_interval() -> void:
	var w := _world()
	_hurt(w, 50)
	var hp := int(w.player_state.hp)
	# Rank 1 reads Aura level 2 through the sub's own table: hp 20 every 18 s.
	_run(w, 17.9)
	assert_eq(int(w.player_state.hp), hp, "no pulse before the first interval")
	_run(w, 0.2)
	assert_eq(int(w.player_state.hp), hp + 20)
	_run(w, 17.8)
	assert_eq(int(w.player_state.hp), hp + 20, "the next pulse is a full interval later")
	_run(w, 0.4)
	assert_eq(int(w.player_state.hp), hp + 40)
	var restored := _events(w, "player_restored")
	assert_eq(restored.size(), 2)
	assert_eq(int(restored[0].amount), 20)
	assert_eq(String(restored[0].skill), AURA)


func test_heal_clamps_at_max_hp_and_a_full_hp_pulse_plays_but_restores_nothing() -> void:
	var w := _world()
	var max_hp := int(w.player_state.max_hp)
	_hurt(w, 5)
	_run(w, 18.1)
	assert_eq(int(w.player_state.hp), max_hp, "a 20 HP pulse on a 5 HP gap restores exactly 5")
	var restored := _events(w, "player_restored")
	assert_eq(restored.size(), 1)
	assert_eq(int(restored[0].amount), 5, "the event carries the real gain")
	_run(w, 18.0)
	assert_eq(_events(w, "player_restored").size(), 1, "no restore event at full HP")
	assert_eq(_pulses(w, "heal").size(), 2, "the pulse still plays at full HP")


func test_support_pulse_event_names_the_sub_skill_kind_and_summon_slot() -> void:
	var w := _world()
	_run(w, 18.1)
	var pulses := _pulses(w, "heal")
	assert_eq(pulses.size(), 1)
	assert_eq(pulses[0], {"type": "support_pulse", "skill": AURA, "skill_id": 9990002, "kind": "heal", "slot": 0})
	assert_eq(_pulses(w, "buff")[0].skill, HEX, "the Hex pulse names the Hex sub-skill")
	var want: Array = ["type"] + RunWorld.EVENT_FIELDS.support_pulse
	var got: Array = pulses[0].keys()
	want.sort()
	got.sort()
	assert_eq(got, want, "the payload is exactly the registered fields")


func test_buff_pulse_starts_one_entry_with_exactly_the_stats_the_sub_level_has() -> void:
	var w := _world()
	var before := float(w.hit_defense().pdd)
	_run(w, 2.9)
	assert_false(w.buffs.has(HEX), "the Hex pulse waits for its own first_after")
	_run(w, 0.2)
	assert_true(w.buffs.has(HEX))
	var entry: Dictionary = w.buffs.active[HEX]
	# Rank 1 reads Hex level 2 through the sub's own table: only pdd (5 x 2), for 12 s.
	assert_eq(entry.effects, {"pdd": 10.0})
	assert_eq(float(entry.duration), 12.0)
	assert_eq(float(w.hit_defense().pdd), before + 10.0, "the player's defence moves while the buff lives")
	assert_eq(_events(w, "buff_cast").size(), 1)


func test_rank_eight_hex_carries_every_unlocked_stat_with_wz_names_mapped() -> void:
	var w := _world()
	w.loadout.set_rank(PARENT, 8)
	_run(w, 3.1)
	# Sub level 16: pdd 80, mdd 48, acc 16, eva 32 -> avoid, pad 16 -> watk.
	assert_eq(w.buffs.active[HEX].effects, {"pdd": 80.0, "mdd": 48.0, "acc": 16.0, "avoid": 32.0, "watk": 16.0})
	assert_eq(w.buffs.effect_total("avoid"), 32.0)
	assert_eq(w.buffs.effect_total("watk"), 16.0)
	assert_eq(float(w.buffs.active[HEX].duration), 26.0)


func test_a_repeat_pulse_refreshes_the_buff_and_never_stacks() -> void:
	var w := _world()
	w.loadout.set_rank(PARENT, 8) # 26 s buff every 8 s: the next pulse lands while it is still running
	_run(w, 3.1)
	_run(w, 5.0)
	var left := float(w.buffs.active[HEX].remaining)
	assert_true(left < 22.0, "the buff has been running for 5 s")
	_run(w, 3.0) # the second pulse lands at 11 s
	assert_true(float(w.buffs.active[HEX].remaining) > 25.0, "the pulse refreshed the timer")
	assert_eq(w.buffs.active.size(), 1)
	assert_eq(w.buffs.effect_total("pdd"), 80.0, "the same stat never stacks")


func test_the_buffed_stats_return_when_the_buff_expires() -> void:
	var w := _world()
	var before := float(w.hit_defense().pdd)
	_run(w, 3.1)
	assert_eq(float(w.hit_defense().pdd), before + 10.0)
	_run(w, 12.0) # the 12 s buff ends well before the next pulse at 25 s
	assert_false(w.buffs.has(HEX))
	assert_eq(float(w.hit_defense().pdd), before)
	assert_eq(_events(w, "buff_expired").size(), 1)


func test_a_dead_owner_gets_no_pulse_and_no_countdown() -> void:
	var w := _world()
	_hurt(w, 100)
	w.player_state["dead"] = true
	var hp := int(w.player_state.hp)
	for tick in roundi(40.0 / DT):
		w.runner.tick_cooldowns(DT, w)
	assert_eq(_events(w, "support_pulse").size(), 0)
	assert_eq(int(w.player_state.hp), hp)
	assert_false(w.buffs.has(HEX))


func test_the_pulse_animation_plays_from_the_tick_the_effect_applies_then_the_summon_resumes() -> void:
	var w := _world()
	_run(w, 2.99)
	assert_ne(w.runner.summons.action[0], "skill2")
	_run(w, 0.03) # the Hex pulse at 3.0 s
	assert_true(w.buffs.has(HEX), "the effect applies when the animation starts")
	assert_eq(w.runner.summons.action[0], "skill2")
	_run(w, 0.3)
	assert_eq(w.runner.summons.action[0], "skill2", "the 4 frame x 100 ms animation is still playing")
	_run(w, 0.3)
	assert_true(w.runner.summons.action[0] in ["stand", "move"], "back to following")


func test_a_summon_sub_is_never_learned_into_the_loadout() -> void:
	var w := _world()
	assert_false(w.learn_skill(AURA))
	assert_false(w.loadout.has(AURA))
	assert_eq(w.loadout.order, [PARENT])


func test_sub_numbers_come_from_the_subs_own_rank_table() -> void:
	var w := _world()
	var pulses: Array = w.loadout.stats(PARENT).support
	assert_eq(pulses.size(), 2)
	assert_eq(w.loadout.stats(AURA, 1).level, 2)
	assert_eq(w.loadout.stats(AURA, 5).level, 10)
	assert_eq(w.loadout.stats(AURA, 8).level, 16)
	assert_eq(int(pulses[0].amount), 20)
	assert_eq(float(pulses[0].interval), 18.0)
	assert_eq(float(pulses[0].first_after), 18.0, "\"interval\" is the sub's first interval")
	assert_eq(float(pulses[1].first_after), 3.0)
	w.loadout.set_rank(PARENT, 5)
	pulses = w.loadout.stats(PARENT).support
	assert_eq(int(pulses[0].amount), 100, "Aura level 10")
	assert_eq(float(pulses[0].interval), 10.0)
	assert_eq(pulses[1].effects, {"pdd": 50.0, "mdd": 30.0}, "acc unlocks at level 11, after rank 5's level 10")
	w.loadout.set_rank(PARENT, 6)
	assert_eq(w.loadout.stats(PARENT).support[1].effects, {"pdd": 60.0, "mdd": 36.0, "acc": 12.0})


func test_support_heal_scales_the_heal_amount_only() -> void:
	var w := _world()
	w.loadout.add_skill_mod(PARENT, "support_heal", "mul", 1.5)
	var pulses: Array = w.loadout.stats(PARENT).support
	assert_eq(int(pulses[0].amount), 30)
	assert_eq(pulses[1].effects, {"pdd": 10.0}, "a buff pulse is not a heal")
	_hurt(w, 100)
	var hp := int(w.player_state.hp)
	_run(w, 18.1)
	assert_eq(int(w.player_state.hp), hp + 30)


func test_support_rate_scales_every_pulse_interval_and_not_first_after() -> void:
	var w := _world()
	w.loadout.add_skill_mod(PARENT, "support_rate", "mul", 0.5)
	var pulses: Array = w.loadout.stats(PARENT).support
	assert_eq(float(pulses[0].interval), 9.0)
	assert_eq(float(pulses[1].interval), 11.0)
	assert_eq(float(pulses[0].first_after), 9.0, "an \"interval\" first pulse follows the faster interval")
	assert_eq(float(pulses[1].first_after), 3.0, "a literal first_after is not an interval")
	_run(w, 9.1)
	assert_eq(_pulses(w, "heal").size(), 1)
	_run(w, 9.0)
	assert_eq(_pulses(w, "heal").size(), 2)


func test_support_rate_can_never_pulse_faster_than_the_floor() -> void:
	var w := _world()
	w.loadout.add_skill_mod(PARENT, "support_rate", "mul", 0.0001)
	for p: Dictionary in w.loadout.stats(PARENT).support:
		assert_eq(float(p.interval), SupportSummons.MIN_INTERVAL)


func test_summon_count_gives_each_beholder_its_own_timers_and_buffs_do_not_stack() -> void:
	var w := _world()
	w.loadout.add_skill_mod(PARENT, "summon_count", "add", 1.0)
	_hurt(w, 100)
	var hp := int(w.player_state.hp)
	_run(w, 3.1)
	assert_eq(w.runner.summons.living_count(), 2)
	assert_eq(_pulses(w, "buff").size(), 2)
	assert_eq(w.buffs.active.size(), 1)
	assert_eq(w.buffs.effect_total("pdd"), 10.0, "two Hexes refresh one entry")
	_run(w, 15.0)
	assert_eq(_pulses(w, "heal").size(), 2, "each Beholder pulses on its own timer")
	assert_eq(int(w.player_state.hp), hp + 40)
	var slots := _pulses(w, "heal").map(func(e: Dictionary) -> int: return int(e.slot))
	slots.sort()
	assert_eq(slots, [0, 1])


func test_a_recast_replaces_the_beholder_and_restarts_its_countdowns() -> void:
	var w := _world()
	_run(w, 44.0)
	assert_eq(_pulses(w, "heal").size(), 2, "pulses at 18 s and 36 s")
	_run(w, 1.1) # the 45 s cooldown ends: a new Beholder replaces the old one
	assert_eq(w.runner.summons.living_count(), 1)
	assert_eq(w.runner.summons.active.size(), 1, "the dead slot was reused")
	_run(w, 17.0)
	assert_eq(_pulses(w, "heal").size(), 2, "the new Beholder has not yet reached its first interval")
	_run(w, 1.5)
	assert_eq(_pulses(w, "heal").size(), 3)


func test_map_transfer_removes_the_beholder_like_any_summon() -> void:
	var w := _world()
	_run(w, 5.0)
	var cooldown := float(w.runner.cooldowns[PARENT])
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.runner.summons.living_count(), 0)
	assert_eq(w.runner.cooldowns[PARENT], cooldown, "the cooldown carries over")
	var pulses := _events(w, "support_pulse").size()
	for tick in roundi(40.0 / DT):
		w.runner.tick_cooldowns(DT, w)
	assert_eq(_events(w, "support_pulse").size(), pulses, "no pulse after the transfer")


func test_pulses_draw_no_random_numbers() -> void:
	var with_beholder := _world()
	var without := _world()
	without.loadout.order.clear()
	_run(with_beholder, 40.0)
	_run(without, 40.0)
	assert_eq(_pulses(with_beholder, "heal").size(), 2)
	for property: Dictionary in with_beholder.get_property_list():
		var value: Variant = with_beholder.get(property.name)
		if value is RandomNumberGenerator:
			assert_eq((value as RandomNumberGenerator).state, (without.get(property.name) as RandomNumberGenerator).state,
				"%s drew nothing" % property.name)


func test_anim_by_stat_plays_the_animation_of_the_newest_unlocked_stat() -> void:
	var w := _world()
	w.book.defs[PARENT].summon.support.pulses[1]["anim_by_stat"] = {"pdd": "skill2", "mdd": "skill3", "acc": "skill4",
		"avoid": "skill5", "watk": "skill6"}
	assert_eq(w.loadout.stats(PARENT, 1).support[1].anim, "skill2", "rank 1 has only pdd")
	assert_eq(w.loadout.stats(PARENT, 3).support[1].anim, "skill3", "rank 3 adds mdd")
	assert_eq(w.loadout.stats(PARENT, 5).support[1].anim, "skill3", "level 10 is still before acc")
	assert_eq(w.loadout.stats(PARENT, 6).support[1].anim, "skill4")
	assert_eq(w.loadout.stats(PARENT, 8).support[1].anim, "skill6", "rank 8 has all five")


func _rarity_world() -> RunWorld:
	var w := _world()
	w.book.defs[PARENT]["rarity_bonuses"] = {
		"rare": [{"id": "soothe", "text": "Soothing", "effects": [{"stat": "support_heal", "op": "mul", "value": 1.5}]}],
		"epic": [{"id": "quicken", "text": "Quickening", "effects": [{"stat": "support_rate", "op": "mul", "value": 0.5}]}]}
	w.upgrades = UpgradePool.from_data({"cards": [
		{"id": "rank", "kind": "skill_rank", "skill": PARENT, "max_rank": 2}]})
	return w


func test_cards_preview_support_heal_and_support_rate_in_their_resolved_units() -> void:
	var w := _rarity_world()
	var rare := w.upgrades.choice_card("rank", w, "rare")
	assert_eq(rare.skill_mod_changes.support_heal, {"before": 20, "after": 30}, "the first heal pulse, in HP")
	var epic := w.upgrades.choice_card("rank", w, "epic")
	assert_eq(epic.skill_mod_changes.support_rate, {"before": 18.0, "after": 9.0}, "the first pulse interval, in seconds")
	var lines := "\n".join(LevelUpWindow.change_lines(rare)) + "\n" + "\n".join(LevelUpWindow.change_lines(epic))
	assert_true(lines.contains("Pulse heal: 20 HP → 30 HP"), lines)
	assert_true(lines.contains("Pulse interval: 18 s → 9 s"), lines)


func test_a_support_card_changes_the_resolved_pulses_once_taken() -> void:
	var w := _rarity_world()
	w.upgrades.apply("rank", w, "rare")
	assert_eq(int(w.loadout.stats(PARENT).support[0].amount), 60, "rank 2 reads Aura level 4 (40 HP), x1.5")


func test_skill_text_lists_each_pulse_with_its_amount_and_interval() -> void:
	var w := _world()
	var line := SkillText.new(w.book).level_line(PARENT, 1, w.loadout.stats(PARENT))
	assert_true(line.contains("Synth Aura: heals 20 HP every 18 s"), line)
	assert_true(line.contains("Synth Hex: Weapon DEF +10 for 12 s every 22 s"), line)
	w.loadout.set_rank(PARENT, 8)
	w.loadout.add_skill_mod(PARENT, "support_heal", "mul", 2.0)
	line = SkillText.new(w.book).level_line(PARENT, 8, w.loadout.stats(PARENT))
	assert_true(line.contains("heals 320 HP every 4 s"), line)
	assert_true(line.contains("Weapon DEF +80, Magic DEF +48, Accuracy +16, Avoid +32, Weapon ATT +16 for 26 s every 8 s"), line)
