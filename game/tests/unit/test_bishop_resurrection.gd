extends TestCase
## Resurrection (spec #372 ticket BS8 #380, docs/GAME_DESIGN.md 7.81): the Bishop's second life as a pool skill. The
## definition on the BS3 seam, its recharge by rank, the rarity entries, the presentation helpers and the real-cache
## identities (the `cooltime / 3 - 480` table, the 10 levels, the art nodes and the Use sound).

const RS := preload("res://tests/fixtures/resurrection_fixtures.gd")
const KEY := "resurrection"


func _raw() -> Dictionary:
	return DataRepo.load_all().skills.skills[KEY]


func test_the_definition_resolves_on_the_second_life_seam() -> void:
	var d := _raw()
	assert_eq(d.skill_id, 2321006)
	assert_eq(String(d.book), "232")
	assert_eq(int(d.job), 232)
	assert_eq(d.kind, "instant")
	assert_eq(d.slot, "active")
	assert_eq(d.damage, "none")
	assert_eq(d.cast, {"rule": "reaction"})
	assert_eq(d.ranks, [2.0, 3.0, 4.0, 5.0, 7.0, 8.0, 9.0, 10.0]) # JSON numbers parse as floats
	assert_eq(d.cooldown_by_rank, RS.TABLE)
	assert_false(d.has("cooldown_field"), "the table is the whole recharge")
	assert_eq(d.revive, {"hp": 0.5, "guard": 2.0, "push": {"distance": 140.0}})
	assert_eq(d.action, "resurrection")
	for note: String in ["_survivor", "_revive"]:
		var text := String(d.get(note, "")).to_lower()
		assert_true(text.contains("tier c"), "%s names its tier C numbers" % note)
		assert_true(text.contains("tier a"), "%s names its tier A facts" % note)


func test_the_resolved_stats_follow_the_ranks() -> void:
	var w := RS.world()
	assert_eq(w.book.max_rank(KEY), 8)
	for rank in range(1, 9):
		w.loadout.set_rank(KEY, rank)
		var st := w.loadout.stats(KEY)
		assert_eq(w.book.canonical_level(KEY, rank), RS.LEVELS[rank - 1], "rank %d is WZ level %d" % [rank, RS.LEVELS[rank - 1]])
		assert_eq(st.cast_rule, "reaction")
		assert_eq(st.damage_type, "none")
		assert_true(absf(SkillRunner.restart_cooldown(st) - float(RS.TABLE[rank - 1])) < 1e-3, "rank %d recharge" % rank)
		assert_true(bool(st.has_box), "rank %d carries the shove box" % rank)
		assert_eq((st.box as Rect2).size, Vector2(800.0, 600.0))
		assert_eq(st.revive, {"hp": 0.5, "guard": 2.0, "push": 140.0})


# --- the revive with the real definition --------------------------------------------------------------------------

## Revives `w` with a lethal touch hit; returns the player_revived event ({} when the hit killed).
func _revive(w: RunWorld) -> Dictionary:
	RS.lethal_hit(w)
	for e: Dictionary in w.drain_events():
		if e.type == "player_revived":
			return e
	return {}


## The twin worlds of a rarity card: one takes card `tier` (+1 rank and its bonus), the other only the +1 rank.
func _carded(tier: String) -> RunWorld:
	var w := RS.world()
	w.upgrades.apply("resurrection_rank", w, tier)
	return w


func _ranked() -> RunWorld:
	var w := RS.world()
	w.loadout.set_rank(KEY, 2)
	return w


func test_a_lethal_hit_revives_at_half_hp_with_a_two_second_guard_and_the_rank_one_recharge() -> void:
	var w := RS.world()
	var max_hp := int(w.player_state.max_hp)
	var e := _revive(w)
	assert_false(e.is_empty(), "the hit did not kill")
	assert_eq(int(e.hp), ceili(max_hp * 0.5))
	assert_eq(int(w.player_state.hp), ceili(max_hp * 0.5))
	assert_false(bool(w.player_state.dead))
	assert_true(absf(float(e.guard) - 2.0) < 1e-3)
	assert_true(absf(float(e.recharge) - 600.0) < 1e-3)
	assert_true(absf(float(w.runner.cooldowns[KEY]) - 600.0) < 1e-3, "the recharge is the skill's ordinary cooldown")


func test_the_diagnostic_lethal_hit_still_kills_a_ready_owned_resurrection() -> void:
	var w := RS.world()
	w.take_hit(1.0e9, false, "", w.player.pos - Vector2(10.0, 0.0), {"accuracy": 0.0, "mob": -1, "boss": true, "unrevivable": true})
	assert_true(bool(w.player_state.dead), "the redesign death steps still reach death")
	assert_eq(w.revives.size(), 0)


func test_the_stance_is_held_without_locking_movement_or_casting() -> void:
	var w := RS.world()
	_revive(w)
	assert_eq(w.upkeep.cast_action, "resurrection", "the sim plays the resurrection stance")
	assert_true(absf(w.upkeep.cast_left - 2.52) < 1e-3, "for the body's three 840 ms frames")
	# Let the lethal hit's knockback end, then walk: the stance is a display only.
	var input := MoveInput.new()
	input.right = true
	for i in 120:
		w.step(1.0 / 60.0, MoveInput.new())
	var x0 := w.player.pos.x
	for i in 30:
		w.step(1.0 / 60.0, input)
	assert_true(w.player.pos.x > x0 + 20.0, "the held stance does not lock walking")
	assert_true(w.can_cast(), "or casting")


func test_the_hud_slot_shows_the_recharge_as_a_cooldown() -> void:
	var w := RS.world()
	var left := PackedFloat32Array()
	var total := PackedFloat32Array()
	w.read_skill_cooldowns(left, total)
	assert_eq(left[0], 0.0, "ready at round start")
	_revive(w)
	w.read_skill_cooldowns(left, total)
	assert_true(absf(left[0] - 600.0) < 0.5 and absf(total[0] - 600.0) < 0.5, "the slot sweeps the %s recharge" % total[0])


# --- rarity: each entry changes the resolved plan ------------------------------------------------------------------

func test_rare_faster_prayer_shortens_the_recharge() -> void:
	var base := float(_revive(_ranked()).recharge)
	var with := float(_revive(_carded("rare")).recharge)
	assert_true(absf(base - 540.0) < 1e-3, "rank 2 recharge")
	assert_true(absf(with - 540.0 * 0.88) < 1e-2, "x0.88: %s" % with)


func test_epic_holy_vigor_raises_the_revive_hp_share() -> void:
	var w := _carded("epic")
	var max_hp := int(w.player_state.max_hp)
	assert_eq(int(_revive(_ranked()).hp), ceili(max_hp * 0.5))
	assert_eq(int(_revive(w).hp), ceili(max_hp * 0.65))


func test_unique_holy_shield_lengthens_the_guard() -> void:
	assert_true(absf(float(_revive(_ranked()).guard) - 2.0) < 1e-3)
	assert_true(absf(float(_revive(_carded("unique")).guard) - 3.5) < 1e-3)


func test_legendary_is_holy_shield_plus_holy_vigor_and_shares_the_uniques_counter() -> void:
	var w := _carded("legendary")
	var max_hp := int(w.player_state.max_hp)
	var e := _revive(w)
	assert_true(absf(float(e.guard) - 3.5) < 1e-3)
	assert_eq(int(e.hp), ceili(max_hp * 0.65))
	var twice := RS.world()
	twice.upgrades.apply("resurrection_rank", twice, "unique")
	twice.upgrades.apply("resurrection_rank", twice, "legendary")
	assert_eq(int(twice.loadout.card_ranks["bonus:resurrection:shield"]), 2, "one counter for Unique and Legendary")
	# The second Holy Shield is the x0.8 repeat: +1.2 s on top of the first +1.5 s.
	assert_true(absf(float(_revive(twice).guard) - (2.0 + 1.5 + 1.2)) < 1e-3)


func test_mastery_repeats_shrink_the_recharge_by_0_95_then_0_96() -> void:
	var w := RS.world()
	w.loadout.set_rank(KEY, 8)
	var base := SkillRunner.restart_cooldown(w.loadout.stats(KEY))
	assert_true(absf(base - 120.0) < 1e-3)
	var card := w.upgrades.choice_card("resurrection_rank", w, "normal")
	assert_eq(card.card_kind, "mastery")
	w.upgrades.apply("resurrection_rank", w, "normal")
	var one := SkillRunner.restart_cooldown(w.loadout.stats(KEY))
	assert_true(absf(one - base * 0.95) < 1e-2, "x0.95: %s" % one)
	w.upgrades.apply("resurrection_rank", w, "normal")
	var two := SkillRunner.restart_cooldown(w.loadout.stats(KEY))
	assert_true(absf(two - one * 0.96) < 1e-2, "the repeat shrinks x0.8: %s" % two)
	assert_eq(w.loadout.rank(KEY), 8, "Mastery gains no rank")


# --- text and card previews ----------------------------------------------------------------------------------------

func _text(w: RunWorld) -> SkillText:
	return SkillText.new(w.book, {})


func test_the_reaction_line_states_hp_guard_and_recharge() -> void:
	var w := RS.world()
	var line := _text(w).level_line(KEY, w.book.canonical_level(KEY, 1), w.loadout.stats(KEY, 1))
	assert_eq(line, "When a hit would kill you: return at 50% HP, 2 s guard; recharge 10:00")
	w.loadout.set_rank(KEY, 8)
	line = _text(w).level_line(KEY, w.book.canonical_level(KEY, 8), w.loadout.stats(KEY, 8))
	assert_eq(line, "When a hit would kill you: return at 50% HP, 2 s guard; recharge 2:00")
	w.loadout.add_skill_mod(KEY, "revive_hp", "add", 0.15)
	w.loadout.add_skill_mod(KEY, "revive_guard", "add", 1.5)
	line = _text(w).level_line(KEY, w.book.canonical_level(KEY, 8), w.loadout.stats(KEY, 8))
	assert_eq(line, "When a hit would kill you: return at 65% HP, 3.5 s guard; recharge 2:00")


func test_the_description_is_the_survivor_one_not_the_party_revive() -> void:
	var w := RS.world()
	assert_false(_text(w).desc(KEY).contains("member"), _text(w).desc(KEY))
	assert_true(_text(w).desc(KEY).begins_with("When a hit would have killed you"))


func test_clock_and_notice() -> void:
	assert_eq(SkillText.clock(600.0), "10:00")
	assert_eq(SkillText.clock(475.2), "7:55")
	assert_eq(SkillText.clock(59.6), "1:00", "seconds round up through the minute")
	assert_eq(SkillText.clock(0.0), "0:00")
	assert_eq(SkillText.revive_notice(120.0), "Resurrection! Ready again in 2:00")


func test_the_cards_preview_the_revive_numbers() -> void:
	var w := RS.world()
	var epic: Dictionary = w.upgrades.choice_card("resurrection_rank", w, "epic")
	assert_eq(epic.skill_mod_changes.revive_hp, {"before": 50, "after": 65})
	var unique: Dictionary = w.upgrades.choice_card("resurrection_rank", w, "unique")
	assert_eq(unique.skill_mod_changes.revive_guard, {"before": 2.0, "after": 3.5})
	var legendary: Dictionary = w.upgrades.choice_card("resurrection_rank", w, "legendary")
	assert_true(legendary.skill_mod_changes.has("revive_hp") and legendary.skill_mod_changes.has("revive_guard"))
	var rare: Dictionary = w.upgrades.choice_card("resurrection_rank", w, "rare")
	assert_eq(rare.skill_mod_changes.cooldown.before, 600.0)
	assert_true(absf(float(rare.skill_mod_changes.cooldown.after) - 528.0) < 0.01)


func test_the_level_up_window_words_the_revive_changes() -> void:
	var w := RS.world()
	var legendary: Dictionary = w.upgrades.choice_card("resurrection_rank", w, "legendary")
	var lines := LevelUpWindow.change_lines(legendary)
	assert_true("Revive HP: 50% → 65%" in lines, str(lines))
	assert_true("Guard: 2 s → 3.5 s" in lines, str(lines))


# --- the real cache (SKIPs without it) -----------------------------------------------------------------------------

func _library() -> AssetLibrary:
	var lib := AssetLibrary.new()
	lib.open()
	return lib


func _cache_ready(lib: AssetLibrary) -> bool:
	if not require_cache():
		return false
	if lib.img("Skill.wz/232.img") == null:
		skip("the cache has no Skill.wz/232.img (import with the Bishop manifest fragment)")
		return false
	return true


func test_the_shipped_recharge_is_the_wz_cooltime_over_three_minus_480_at_every_rank() -> void:
	var lib := _library()
	if not _cache_ready(lib):
		lib.free()
		return
	var d := _raw()
	var levels: Array = d.ranks
	var table: Array = d.cooldown_by_rank
	assert_eq(levels.size(), 8)
	assert_eq(table.size(), 8)
	for i in 8:
		var cooltime := float(lib.node("Skill.wz/232.img/skill/2321006/level/%d/cooltime" % int(levels[i])))
		assert_eq(float(table[i]), cooltime / 3.0 - 480.0, "rank %d (WZ level %d): cooltime %s" % [i + 1, int(levels[i]), cooltime])
	lib.free()


func test_the_skill_has_ten_levels_with_the_800_by_600_box() -> void:
	var lib := _library()
	if not _cache_ready(lib):
		lib.free()
		return
	var level_node: Dictionary = lib.node("Skill.wz/232.img/skill/2321006/level")
	var count := 0
	while level_node.has(str(count + 1)):
		count += 1
	assert_eq(count, 10, "only 10 levels")
	for lv in range(1, 11):
		var n: Dictionary = level_node[str(lv)]
		assert_eq(n.lt["$v"], [-400.0, -350.0], "level %d lt" % lv)
		assert_eq(n.rb["$v"], [400.0, 250.0], "level %d rb" % lv)
		assert_false(n.has("mad") or n.has("time") or n.has("mobCount"), "level %d has no damage fields" % lv)
	lib.free()


func test_every_art_node_and_the_use_sound_resolve_through_the_library() -> void:
	var lib := _library()
	if not _cache_ready(lib):
		lib.free()
		return
	var d := _raw()
	var effect := lib.anim(String(d.effect))
	var affected := lib.anim(String(d.affected))
	assert_false(effect.is_empty(), "effect")
	assert_false(affected.is_empty(), "affected")
	assert_eq(effect.frames.size(), 21)
	assert_eq(affected.frames.size(), 15)
	# The affected lead-in: frame 0 is the 1 x 1 canvas held for 1320 ms, the beams follow at 60 ms.
	assert_true(absf(affected.frames[0].delay_s - 1.32) < 1e-6)
	assert_eq(affected.frames[0].size(), Vector2(1, 1))
	assert_true(absf(affected.frames[1].delay_s - 0.06) < 1e-6)
	assert_true(lib.find_anim(String(d.icon)) != null, "icon")
	assert_true(lib.sound(String(d.sounds.use)) != null, "the Use sound")
	assert_eq(String(lib.node("Skill.wz/232.img/skill/2321006/action/0")), "resurrection")
	assert_eq(lib.missing.size(), 0, "no lookup missed: %s" % str(lib.missing))
	lib.free()
