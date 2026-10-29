extends TestCase
## Buccaneer Transformation and Shockwave (B9 #421, spec #412 BU-2, BU-3, BU-6, BU-7, BU-8): the first morph form (morph 1000)
## on Paladin's Form seam and the sub-skill both transformations carry. Synthetic WZ-shaped book 511 (the eight mapped levels of
## each skill carry the real v83 numbers), seeded RNG, fixed 1/60 ticks; the last test reads the real asset cache.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const KNUCKLE := 1482000
## Transformation's mapped levels (rank 1..8 -> WZ levels 3 5 8 10 13 15 18 20) and its defence (pdd = mdd, tier A, 5111005).
const T_LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
const T_DEFENCE := [6, 10, 16, 20, 26, 30, 36, 40]
## Shockwave's mapped levels (rank 1..8 -> WZ levels 4 8 12 15 19 23 27 30), damage % and targets (tier A, 5111006).
const S_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const S_DAMAGE := [310, 370, 430, 475, 535, 595, 655, 700]
const S_TARGETS := [4, 4, 5, 5, 5, 6, 6, 6]
## The art's first eruption (the blank lead-in of Skill.wz 5111006 effect, tier A) and the pending delay it sets (ruling BC1 #413).
const ERUPTION := 1.38


## Book 511 with Transformation at levels 1..20 and Shockwave at 1..30: the mapped levels read the real rows, the others interpolate.
func _imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	imgs["511"] = book_node()
	return imgs


## The synthetic `skill_imgs["511"]` node of the two skills (the rarity audit, test_rarity_bonus_effects, builds its world from it).
static func book_node() -> Dictionary:
	return preload("res://tests/fixtures/buccaneer_transformation_book.gd").book_node()


## A Buccaneer (job 512 flipped playable for the test) on the flat quiet map at x = 400 with only Transformation learned.
func _world(pad := 17) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	data.balance.player.hp = 100000
	data.balance.regen.hp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 421, data))
	setup.skill_imgs = _imgs()
	var w := RunWorld.new(setup)
	w.set_job(512)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.equipment.worn.weapon = Equipment.create(KNUCKLE, {"incPAD": pad})
	w.refresh_player_stats()
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	w.learn_skill("transformation")
	w.drain_events()
	return w


## A stationary mob `dx` px in front of the player (the facing side).
func _mob(w: RunWorld, dx: float, hp := 100000000) -> int:
	var m := RF.put_mob(w, MOB, w.player.pos.x + dx * w.player.facing, 190, 10000)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


## Runs `seconds` of the whole world and returns every event with the elapsed second it fired in (`at`).
func _run(w: RunWorld, seconds: float, from := 0.0) -> Array:
	var out: Array = []
	var ticks := roundi(seconds / DT)
	for i in ticks:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			e["at"] = from + float(i + 1) * DT
			out.append(e)
	return out


func _of(events: Array, type: String, skill := "") -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type and (skill == "" or String(e.get("skill", "")) == skill))


func _ats(events: Array) -> Array:
	return events.map(func(e: Dictionary) -> float: return snappedf(float(e.at), 0.01))


# --- the catalog -------------------------------------------------------------------------------------------------

func test_transformation_is_a_morph_form_with_the_spec_block() -> void:
	var book := _world().book
	var d: Dictionary = book.def("transformation")
	assert_eq([book.skill_id("transformation"), d.kind, d.slot, d.damage, int(d.job), d.book], [5111005, "form", "active", "none", 511, "511"])
	assert_eq(d.cast, {"rule": "form", "mob_within": 400.0})
	assert_eq(d.form, {"duration": 10.0, "exclusive_group": "buccaneer_transformation", "effects": {},
		"subs": [{"skill": "shockwave", "first_after": 1.0, "interval": 3.0}]})
	assert_eq(d.buff, {"stat": "pdd", "field": "pdd", "morph_field": "morph",
		"effects": [{"stat": "mdd", "field": "mdd"}, {"stat": "speed", "field": "speed"}, {"stat": "jump", "field": "jump"}]})
	assert_eq([d.cooldown, d.action, d.action_time], [14.0, "alert2", 0.6])
	assert_eq(d.sounds.use, "Sound.wz/Skill.img/5111005/Use")
	assert_true(String(d.get("effect", "")).is_empty(), "neither WZ node has cast art")
	assert_true(book.weapon_families("transformation").is_empty(), "no weapon gate")
	assert_eq(book.max_rank("transformation"), 8)


func test_shockwave_is_a_form_sub_of_both_forms_with_the_canonical_box() -> void:
	var book := _world().book
	var d: Dictionary = book.def("shockwave")
	assert_eq([book.skill_id("shockwave"), d.kind, d.slot, int(d.job), d.book], [5111006, "instant", "form_sub", 511, "511"])
	assert_eq(d.form_sub_of, ["transformation", "super_transformation"], "B10 #422 added Super as its second parent")
	assert_eq(d.cast.rule, "box")
	assert_eq(int(d.cast.min_targets), 1)
	assert_eq([d.action, d.action_time], ["shockwave", 0.8])
	assert_eq([d.sounds.use, d.sounds.hit], ["Sound.wz/Skill.img/5111006/Use", "Sound.wz/Skill.img/5111006/Hit"])
	assert_eq(d.hit, "Skill.wz/511.img/skill/5111006/hit/0")
	assert_false(d.has("rarity_bonuses"), "a sub has no cards and no rarity list")
	assert_eq(book.max_rank("shockwave"), 8)
	assert_false(book.slot("shockwave") == "active", "never a pool card")


func test_the_form_catalog_validates_with_both_new_definitions() -> void:
	var defs: Dictionary = _world().book.defs
	var mine := {"transformation": defs.transformation, "super_transformation": defs.super_transformation,
		"shockwave": defs.shockwave, "demolition": defs.demolition, "snatch": defs.snatch}
	assert_eq(Array(PlayerForms.validation_errors(mine)), [])
	for error in PlayerForms.validation_errors(defs):
		assert_false("transformation" in error or "shockwave" in error, "the shipped catalog: %s" % error)


# --- rank values -------------------------------------------------------------------------------------------------

func test_transformation_reads_the_mapped_levels_at_every_rank() -> void:
	var w := _world()
	for r in range(1, 9):
		w.loadout.set_rank("transformation", r)
		var st := w.loadout.stats("transformation")
		assert_eq(w.loadout.level("transformation"), T_LEVELS[r - 1], "rank %d level" % r)
		assert_eq(int(w.book.canonical("transformation", int(st.level), "pdd")), T_DEFENCE[r - 1])
		assert_eq(int(w.book.canonical("transformation", int(st.level), "mdd")), T_DEFENCE[r - 1])
		assert_eq(int(st.morph), 1000)
	assert_eq([T_DEFENCE[0], T_DEFENCE[3], T_DEFENCE[7]], [6, 20, 40], "the spec's rank 1 / 4 / 8")


func test_shockwave_ranks_with_its_parent_through_its_own_thirty_level_table() -> void:
	var w := _world()
	w.loadout.set_rank("transformation", 8)
	var st := w.loadout.clone().stats("shockwave", 8)
	assert_eq(int(st.level), 30, "rank 8 of the parent reads level 30 of the sub")
	for r in range(1, 9):
		var lo := w.loadout.clone()
		var sub := lo.stats("shockwave", r)
		assert_eq(int(sub.level), S_LEVELS[r - 1], "rank %d level" % r)
		assert_near(float(sub.damage_pct), S_DAMAGE[r - 1] / 100.0, 1e-6, "rank %d damage" % r)
		assert_eq(int(sub.mob_count), S_TARGETS[r - 1], "rank %d targets" % r)
	assert_eq([S_DAMAGE[0], S_DAMAGE[3], S_DAMAGE[7]], [310, 475, 700], "the spec's rank 1 / 4 / 8")
	assert_eq(w.loadout.stats("shockwave", 8).box, Rect2(-330, -140, 330, 160), "lt (-330,-140) rb (0,20)")


# --- the form's lifecycle ----------------------------------------------------------------------------------------

func test_it_waits_with_no_mob_within_400_px_and_then_transforms() -> void:
	var w := _world()
	var events := _run(w, 0.5)
	assert_true(_of(events, "form_started").is_empty(), "no mob: wait")
	_mob(w, 420)
	assert_true(_of(_run(w, 0.1), "form_started").is_empty(), "a mob 420 px away is outside the admission radius")
	_mob(w, 300)
	assert_eq(_of(_run(w, 0.1), "form_started").size(), 1)


func test_the_window_is_ten_seconds_with_the_events_and_the_morph_in_player_state() -> void:
	var w := _world()
	_mob(w, 300)
	var events := _run(w, 0.2)
	var started := _of(events, "form_started")
	assert_eq(started.size(), 1)
	assert_eq([started[0].skill, started[0].skill_id, started[0].element, started[0].duration], ["transformation", 5111005, "", 10.0])
	assert_eq(w.morph_id(), 1000)
	assert_eq(int(w.player_state.morph), 1000, "the presentation reads it from player_state")
	events = _run(w, 9.9, 0.2)
	var ended := _of(events, "form_ended")
	assert_eq(ended.size(), 1)
	assert_eq([ended[0].skill, ended[0].skill_id, ended[0].reason], ["transformation", 5111005, "expired"])
	assert_near(float(ended[0].at), 10.0, 0.06, "ten seconds after the cast")
	assert_eq(w.morph_id(), 0)
	assert_eq(int(w.player_state.morph), 0)


func test_the_cooldown_counts_from_the_cast_and_the_form_is_recast_after_fourteen_seconds() -> void:
	var w := _world()
	_mob(w, 300)
	var events := _run(w, 20.0)
	var starts := _ats(_of(events, "form_started"))
	assert_eq(starts.size(), 2)
	assert_near(float(starts[0]), 0.02, 0.03)
	assert_near(float(starts[1]) - float(starts[0]), 14.0, 0.05, "14 s from the cast, not from the end of the window")


func test_the_stat_package_moves_while_the_form_lives_and_returns_after_with_the_caps() -> void:
	var w := _world()
	w.loadout.set_rank("transformation", 4)
	var pdd := float(w.hit_defense().pdd)
	var mdd := float(w.hit_defense().mdd)
	var speed := w.player_speed_stat()
	var jump := w.player.jump_stat
	_mob(w, 300)
	_run(w, 0.1)
	assert_near(float(w.hit_defense().pdd) - pdd, 20.0, 0.001, "rank 4 reads level 10: pdd 20")
	assert_near(float(w.hit_defense().mdd) - mdd, 20.0, 0.001)
	assert_eq(w.player.speed_stat, mini(int(speed) + 40, Equipment.SPEED_CAP), "+40 speed reaches the cap of 140")
	assert_eq(w.player.speed_stat, Equipment.SPEED_CAP)
	assert_eq(w.player.jump_stat, jump + 20, "+20 jump gives 120, under the cap of 123")
	_run(w, 10.0, 0.1)
	assert_near(float(w.hit_defense().pdd), pdd, 0.001)
	assert_near(float(w.hit_defense().mdd), mdd, 0.001)
	assert_near(w.player_speed_stat(), speed, 0.001)
	assert_eq(w.player.jump_stat, jump)


func test_a_morphed_buccaneer_is_not_hidden_and_the_form_buff_has_no_attack_bonus() -> void:
	var w := _world()
	_mob(w, 300)
	_run(w, 0.1)
	assert_false(w.is_hidden())
	assert_eq(w.buffs.effect_total("watk"), 0.0, "BU-8: the stat package is defence, speed and jump only")
	assert_eq(w.buffs.effect_total("matk"), 0.0)


func test_the_form_lasts_longer_with_form_time_and_a_booster_shortens_its_cooldown() -> void:
	var w := _world()
	w.loadout.add_skill_mod("transformation", "form_time", "mul", 1.25)
	_mob(w, 300)
	var events := _run(w, 13.0)
	assert_eq(float(_of(events, "form_started")[0].duration), 12.5)
	assert_near(float(_of(events, "form_ended")[0].at), 12.5, 0.06)
	var b := _world()
	b.loadout.add_skill_mod("transformation", "cooldown", "mul", 0.88)
	_mob(b, 300)
	var starts := _ats(_of(_run(b, 15.0), "form_started"))
	assert_eq(starts.size(), 2)
	assert_near(float(starts[1]) - float(starts[0]), 14.0 * 0.88, 0.05)


# --- Shockwave inside the form ----------------------------------------------------------------------------------

func test_shockwave_casts_at_one_four_and_seven_seconds_and_not_at_ten() -> void:
	var w := _world()
	_mob(w, 300)
	var events := _run(w, 10.5)
	var casts := _ats(_of(events, "cast", "shockwave"))
	assert_eq(casts.size(), 3, "1, 4 and 7 s into the window, the tick the form ends is not a cast")
	var begin := float(_ats(_of(events, "form_started"))[0])
	for i in 3:
		assert_near(float(casts[i]) - begin, 1.0 + 3.0 * i, 0.04)
	assert_eq(_of(events, "cast", "shockwave")[0].action, "shockwave")


func test_shockwave_damage_lands_with_the_arts_first_eruption_not_at_the_cast() -> void:
	var w := _world()
	var m := _mob(w, 200)
	var events := _run(w, 3.0)
	var cast_at := float(_of(events, "cast", "shockwave")[0].at)
	var hits := _of(events, "mob_hit", "shockwave")
	assert_false(hits.is_empty())
	assert_near(float(hits[0].at) - cast_at, ERUPTION, 0.03, "one eruption, 1.38 s after the cast")
	assert_eq(_of(events, "skill_impact", "shockwave").size(), 1, "one wave, one impact")
	assert_eq(hits.size(), 1, "one line on one mob")
	assert_true(w.swarm.hp[m] < 100000000)


func test_the_box_is_the_facing_side_only_for_both_facings_and_is_fixed_at_the_cast() -> void:
	for facing in [1, -1]:
		var w := _world()
		w.player.facing = facing
		var front := _mob(w, 250)
		var behind := _mob(w, -100)
		var events := _run(w, 3.5)
		var struck := _of(events, "mob_hit", "shockwave").map(func(e: Dictionary) -> int: return int(e.mob))
		assert_true(front in struck, "facing %d: the mob in front is struck" % facing)
		assert_false(behind in struck, "facing %d: a mob behind is outside the strip" % facing)
	# The player turns right after the cast: the strip stays where the wave was thrown.
	var w2 := _world()
	var ahead := _mob(w2, 250)
	var e1 := _run(w2, 1.1)
	assert_eq(_of(e1, "cast", "shockwave").size(), 1)
	w2.player.facing = -1
	var struck2 := _of(_run(w2, 1.6, 1.1), "mob_hit", "shockwave").map(func(e: Dictionary) -> int: return int(e.mob))
	assert_true(ahead in struck2, "turning after the cast does not move the strip")


func test_shockwave_waits_when_its_box_is_empty_and_leaves_no_catch_up_burst() -> void:
	var w := _world()
	_mob(w, 380) # inside the 400 px admission radius, beyond the 330 px strip
	var events := _run(w, 5.0)
	assert_eq(_of(events, "form_started").size(), 1)
	assert_true(_of(events, "cast", "shockwave").is_empty(), "nothing in the strip: it waits")
	_mob(w, 200)
	events = _run(w, 1.0, 5.0)
	var casts := _of(events, "cast", "shockwave")
	assert_eq(casts.size(), 1, "one cast the tick a target arrives, not the casts it missed")
	var second := _of(_run(w, 1.8, 6.0), "cast", "shockwave")
	assert_eq(second.size(), 0, "no second cast inside the 3 s interval that began at the first")
	var third := _of(_run(w, 0.4, 7.8), "cast", "shockwave")
	assert_eq(third.size(), 1, "and one when the interval is over")


func test_shockwave_takes_the_parents_damage_modifier_and_the_energy_meter_does_not_touch_it() -> void:
	var base := _world(600)
	_mob(base, 200)
	var plain := float(_of(_run(base, 3.0), "mob_hit", "shockwave")[0].damage)
	var boosted := _world(600)
	boosted.loadout.add_skill_mod("transformation", "damage", "mul", 1.2)
	_mob(boosted, 200)
	var strong := float(_of(_run(boosted, 3.0), "mob_hit", "shockwave")[0].damage)
	assert_near(strong / plain, 1.2, 0.03, "the parent's damage multiplier multiplies the sub")
	var charged := _world(600)
	charged.meter.value = 7
	_mob(charged, 200)
	var events := _run(charged, 3.0)
	assert_near(float(_of(events, "mob_hit", "shockwave")[0].damage) / plain, 1.0, 0.0001, "no +3% per held energy on a sub")
	assert_eq(charged.meter.value, 7, "Shockwave neither earns nor spends energy")
	assert_true(_of(events, "meter_changed").is_empty())


func test_shockwave_strikes_up_to_the_rank_target_cap() -> void:
	var w := _world()
	for i in 8:
		_mob(w, 100 + 20 * i)
	var hits := _of(_run(w, 3.0), "mob_hit", "shockwave")
	assert_eq(hits.size(), 4, "rank 1 reads level 4: four targets")
	var w8 := _world()
	w8.loadout.set_rank("transformation", 8)
	for i in 8:
		_mob(w8, 100 + 20 * i)
	assert_eq(_of(_run(w8, 3.0), "mob_hit", "shockwave").size(), 6, "rank 8 reads level 30: six targets")


func test_the_wave_is_five_facing_ripples_played_where_it_was_cast() -> void:
	var d: Dictionary = _world().book.def("shockwave")
	assert_true(String(d.get("effect", "")).is_empty(), "no avatar-following effect: the wave stays where it was thrown")
	var paths: Array = d.cast_visuals.map(func(v: Dictionary) -> String: return v.path)
	assert_eq(paths, ["Skill.wz/511.img/skill/5111006/effect", "Skill.wz/511.img/skill/5111006/effect0",
		"Skill.wz/511.img/skill/5111006/effect1", "Skill.wz/511.img/skill/5111006/effect2",
		"Skill.wz/511.img/skill/5111006/effect3"])
	for v: Dictionary in d.cast_visuals:
		assert_true(bool(v.get("facing", false)), "flipped with the caster")
		assert_eq(float(v.x), 0.0, "each ripple's own origin places it along the wave")
	assert_eq(d.pending, {"delay": ERUPTION, "oriented": true, "effect": ""})
	assert_eq(SkillBook.visual_placement({"x": 0.0, "facing": true}, 1), {"x": 0.0, "flip": true})
	assert_eq(SkillBook.visual_placement({"x": 0.0, "facing": true}, -1), {"x": 0.0, "flip": false})


# --- text --------------------------------------------------------------------------------------------------------

func test_card_and_skill_window_text_read_the_transforms_you_line_then_the_shockwave_line() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	var expected := [
		"Transforms you for 10 s: defence +6, speed +40, jump +20. Shockwave after 1 s, every 3 s (Lv4): Damage 310%, up to 4 monsters. Base 310% weapon damage, 4 targets",
		"Transforms you for 10 s: defence +20, speed +40, jump +20. Shockwave after 1 s, every 3 s (Lv15): Damage 475%, up to 5 monsters. Base 475% weapon damage, 5 targets",
		"Transforms you for 10 s: defence +40, speed +40, jump +20. Shockwave after 1 s, every 3 s (Lv30): Damage 700%, up to 6 monsters. Base 700% weapon damage, 6 targets"]
	for i in 3:
		var rank: int = [1, 4, 8][i]
		w.loadout.set_rank("transformation", rank)
		var line := text.level_line("transformation", rank, w.loadout.stats("transformation"))
		assert_eq(line.split("\n")[-1], expected[i], "rank %d" % rank)
		assert_false("Charges" in line, line)
	assert_true(text.desc("transformation").begins_with("Turns you into"), text.desc("transformation"))


func test_lasting_transformation_shows_in_the_text_as_the_longer_window() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	w.loadout.add_skill_mod("transformation", "form_time", "mul", 1.25)
	var line := text.level_line("transformation", 1, w.loadout.stats("transformation")).split("\n")[-1]
	assert_true(line.begins_with("Transforms you for 12.5 s:"), line)


# --- rarity bonuses ----------------------------------------------------------------------------------------------

func test_the_rarity_table_is_the_spec_table() -> void:
	var bonuses: Dictionary = _world().book.def("transformation").rarity_bonuses
	var summary := {}
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		summary[tier] = (bonuses[tier] as Array).map(func(b: Dictionary) -> Array:
			return [b.id, b.effects.map(func(e: Dictionary) -> Array: return [e.stat, e.op, float(e.value)])])
	assert_eq(summary, {
		"rare": [["mastery", [["damage", "mul", 1.2]]]],
		"epic": [["booster", [["cooldown", "mul", 0.88]]]],
		"unique": [["lasting", [["form_time", "mul", 1.25]]]],
		"legendary": [["lasting", [["form_time", "mul", 1.25], ["damage", "mul", 1.2]]]]})
	assert_eq(bonuses.unique[0].text, "Lasting Transformation")


# --- real cache --------------------------------------------------------------------------------------------------

func test_real_cache_numbers_at_all_eight_ranks_and_the_art_nodes() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.get_default()
	var img := library.img("Skill.wz/511.img")
	assert_true(img != null, "book 511 imported (cache-413 or any cache built after the Buccaneer fragment)")
	if img == null:
		return
	var root: Dictionary = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"511": root})
	var lo := Loadout.new(book)
	lo.add_skill("transformation")
	assert_eq(book.rank_table("transformation").map(func(v: Variant) -> int: return int(v)), T_LEVELS)
	assert_eq(book.rank_table("shockwave").map(func(v: Variant) -> int: return int(v)), S_LEVELS)
	for rank in range(1, 9):
		lo.set_rank("transformation", rank)
		var row: Dictionary = root.skill["5111005"].level[str(T_LEVELS[rank - 1])]
		var st := lo.stats("transformation")
		assert_eq([int(row.pdd), int(row.mdd), int(row.speed), int(row.jump), int(row.morph)], [T_DEFENCE[rank - 1], T_DEFENCE[rank - 1], 40, 20, 1000],
			"rank %d: the WZ row" % rank)
		assert_eq(int(st.morph), 1000)
		assert_eq(int(st.level), T_LEVELS[rank - 1])
		assert_false(row.has("pad") or row.has("mad"), "no attack bonus in the node")
		var sub: Dictionary = root.skill["5111006"].level[str(S_LEVELS[rank - 1])]
		var shock := lo.clone().stats("shockwave", rank)
		assert_eq([int(sub.damage), int(sub.mobCount)], [S_DAMAGE[rank - 1], S_TARGETS[rank - 1]], "rank %d: the WZ row" % rank)
		assert_near(float(shock.damage_pct), S_DAMAGE[rank - 1] / 100.0, 1e-6)
		assert_eq(int(shock.mob_count), S_TARGETS[rank - 1])
		assert_eq(shock.box, Rect2(-330, -140, 330, 160), "the canonical box at every rank")
	# The art: five 8-frame ripples whose blank lead-in is the delay, the 5-frame hit, the sounds and the morph's own stance.
	var first_eruption := [1.38, 1.53, 1.68, 1.83, 1.98]
	var names := ["effect", "effect0", "effect1", "effect2", "effect3"]
	for i in 5:
		var ripple: SpriteAnim = library.find_anim("Skill.wz/511.img/skill/5111006/" + names[i])
		assert_true(ripple != null, names[i])
		assert_eq(ripple.frame_count(), 8, names[i])
		assert_eq(ripple.index_at(first_eruption[i] - 0.02, false), 0, "%s is blank until %.2f s" % [names[i], first_eruption[i]])
		assert_true(ripple.index_at(first_eruption[i] + 0.02, false) >= 1, "%s erupts after it" % names[i])
	var hit: SpriteAnim = library.find_anim("Skill.wz/511.img/skill/5111006/hit/0")
	assert_true(hit != null and hit.frame_count() == 5, "hit/0: 5 frames")
	assert_eq(int(root.skill["5111005"].level["1"].morph), 1000)
	assert_true(library.sound("Sound.wz/Skill.img/5111005/Use") != null, "Transformation Use")
	assert_true(library.sound("Sound.wz/Skill.img/5111006/Use") != null, "Shockwave Use")
	assert_true(library.sound("Sound.wz/Skill.img/5111006/Hit") != null, "Shockwave Hit")
	var morph: SpriteAnim = library.find_anim("Morph.wz/1000.img/shockwave")
	assert_true(morph != null and morph.frame_count() == 16, "morph 1000 has its own shockwave stance (16 frames)")
	assert_true(library.missing.is_empty(), str(library.missing))
