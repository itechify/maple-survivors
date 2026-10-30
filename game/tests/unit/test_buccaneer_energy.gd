extends TestCase
## Buccaneer Energy Charge and Energy Drain (B6 #418, spec #412): the meter on Hero's PlayerMeter seam, the `energy` unit word, the
## first finisher (Drain's box, damage and heal by rank, the heal cap, admission at ten energy, what every rarity bonus changes), and
## the full-bar cue. Synthetic WZ-shaped book 511 (the eight mapped levels carry the real v83 numbers), seeded RNG, fixed 1/60 ticks.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const TRANSFORMATION := preload("res://tests/unit/test_buccaneer_transformation.gd")
const DT := 1.0 / 60.0
const KNUCKLE := 1482000
const MOB := 1110100
## Energy Drain's mapped levels (rank 1..8 -> WZ levels 3 5 8 10 13 15 18 20): damage % and heal % (tier A, Skill.wz 5111004).
const LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
const DAMAGE := [275, 285, 300, 310, 325, 335, 350, 360]
const HEAL := [12, 13, 14, 15, 17, 18, 19, 20]
const TIERS := ["rare", "epic", "unique", "legendary"]


## Book 511 with Energy Drain at every level 1..20 (the unmapped levels interpolate, nothing reads them), the canonical box and one target.
func _imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	var drain := {}
	for lv in range(1, 21):
		var at := LEVELS.find(lv)
		drain[str(lv)] = {"damage": DAMAGE[at] if at >= 0 else 265 + (lv - 1) * 5, "x": HEAL[at] if at >= 0 else 11 + lv / 3,
			"mobCount": 1, "lt": {"$v": [-200, -100]}, "rb": {"$v": [0, 0]}}
	imgs["511"] = TRANSFORMATION.book_node() # B9 #421: Transformation and Shockwave (the real subs of the "subs neither earn nor receive" test)
	imgs["511"].skill["5111004"] = {"level": drain}
	return imgs


## A Buccaneer (job 512 flipped playable for the test) on the flat quiet map at x = 400 with only `key` learned. `max_hp` and
## `pad` default to the shipped 600 HP and a plain knuckle; the heal tests raise them to expose one number at a time.
func _world(key := "energy_drain", max_hp := 0, pad := 17) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	if max_hp > 0:
		data.balance.player.hp = max_hp
		data.balance.regen.hp = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 418, data))
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
	w.learn_skill(key)
	return w


## A mob `dx` px in front of the player (the facing side), with `hp` hit points.
func _mob(w: RunWorld, dx: float, hp := 1000000) -> int:
	var m := RF.put_mob(w, MOB, 400.0 + dx * w.player.facing, 190, 10000)
	w.swarm.hp[m] = hp
	w.swarm.max_hp[m] = hp
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _fill(w: RunWorld, n: int) -> void:
	w.meter.value = 0
	for i in n:
		w.meter.gain("cast_landed", w.events)


func _step(w: RunWorld) -> Array:
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit")


# --- text --------------------------------------------------------------------------------------------------------

func test_drain_text_says_energy_and_hero_finishers_still_say_orbs() -> void:
	var w := _world()
	w.loadout.add_skill_mod("energy_drain", "meter_keep", "add", 2)
	var text := SkillText.new(w.book)
	var line := text.level_line("energy_drain", 1, w.loadout.stats("energy_drain"))
	assert_true("Needs 10 energy" in line, line)
	assert_true("Keeps 2 energy" in line, line)
	assert_false("orbs" in line, line)
	# Hero's real Panic carries no `unit`: its text is still "orbs".
	var imgs := RF.skill_imgs()
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"damage": 150 + lv, "prop": 100, "time": 3}
	imgs["111"] = {"skill": {"1111003": {"level": levels}}}
	var hero_book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	assert_false(hero_book.def("panic").meter.has("unit"))
	var hero_lo := Loadout.new(hero_book)
	hero_lo.add_skill("panic")
	hero_lo.add_skill_mod("panic", "meter_keep", "add", 2)
	var hero_line := SkillText.new(hero_book).level_line("panic", 1, hero_lo.stats("panic"))
	assert_true("Needs 5 orbs" in hero_line and "Keeps 2 orbs" in hero_line, hero_line)
	assert_false("energy" in hero_line, hero_line)

# --- Energy Drain: the catalog entry -----------------------------------------------------------------------------

func test_catalog_drain_is_an_eight_rank_finisher_on_the_canonical_box_with_the_heal_block() -> void:
	var w := _world()
	var book := w.book
	assert_eq(book.skill_id("energy_drain"), 5111004)
	assert_eq(book.max_rank("energy_drain"), 8)
	assert_eq(book.slot("energy_drain"), "active")
	assert_true(book.weapon_families("energy_drain").is_empty(), "no weapon gate: the job's drops are already knuckles")
	var def: Dictionary = book.def("energy_drain")
	assert_eq([def.meter.role, int(def.meter.min), def.meter.spend, def.meter.damage_per_unit, def.meter.unit],
		["finisher", 10, "all", 0.12, "energy"])
	assert_eq(def.damage_heal, {"percent_field": "x", "max_hp_fraction": 0.5, "target_max_hp": true})
	assert_eq([def.action, def.action_time, def.cooldown], ["edrain", 0.6, 2.0])
	assert_eq(def.cast.rule, "box")
	assert_eq(def.effect, "Skill.wz/511.img/skill/5111004/effect")
	assert_eq(def.hit, "Skill.wz/511.img/skill/5111004/hit/0")
	assert_eq(def.sounds.use, "Sound.wz/Skill.img/5111004/Use")
	assert_eq(def.sounds.hit, "Sound.wz/Skill.img/5111004/Hit")


func test_damage_and_heal_percent_by_rank_come_from_the_canonical_levels() -> void:
	var w := _world()
	for r in range(1, 9):
		w.loadout.set_rank("energy_drain", r)
		assert_eq(w.loadout.level("energy_drain"), LEVELS[r - 1])
		var st := w.loadout.stats("energy_drain")
		assert_near(float(st.damage_pct), DAMAGE[r - 1] / 100.0, 1e-6, "rank %d damage" % r)
		assert_eq(int(w.book.canonical("energy_drain", int(st.level), "x")), HEAL[r - 1], "rank %d heal percent" % r)
		assert_eq(int(st.mob_count), 1, "one target")
	assert_eq([DAMAGE[0], DAMAGE[3], DAMAGE[7]], [275, 310, 360], "the spec's rank 1 / 4 / 8")


# --- Energy Drain: the box and the target ------------------------------------------------------------------------

func test_the_box_is_the_canonical_forward_box_with_a_dead_zone_behind_and_beyond_it() -> void:
	var w := _world()
	assert_eq(w.loadout.stats("energy_drain").box, Rect2(-200, -100, 200, 100), "lt (-200,-100) rb (0,0), facing side")
	var inside := _mob(w, 150)
	var beyond := _mob(w, 260)
	var behind := _mob(w, -120)
	_fill(w, 10)
	var hits := _hits(_step(w))
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].mob, inside)
	assert_eq(w.swarm.hp[beyond], w.swarm.max_hp[beyond], "beyond 200 px")
	assert_eq(w.swarm.hp[behind], w.swarm.max_hp[behind], "behind the caster")


func test_drain_strikes_one_monster_even_in_a_crowd() -> void:
	var w := _world()
	for dx in [60, 90, 120, 150, 180]:
		_mob(w, dx)
	_fill(w, 10)
	assert_eq(_hits(_step(w)).size(), 1)


# --- Energy Drain: admission, spend, multiplier ------------------------------------------------------------------

func test_drain_waits_below_ten_energy_then_spends_all_and_earns_none() -> void:
	var w := _world()
	_mob(w, 100)
	_fill(w, 9)
	_step(w)
	assert_eq(w.runner.casts, 0, "nine energy is not enough")
	assert_eq(w.meter.value, 9)
	_fill(w, 10)
	var events := _step(w)
	assert_eq(w.runner.casts, 1)
	assert_eq(_hits(events).size(), 1)
	assert_eq(w.meter.value, 0, "all ten spent and the landing gave none back")
	assert_true(float(w.runner.cooldowns.energy_drain) > 1.9, "the 2.0 s cooldown, not the 1.0 s floor")


func test_a_full_bar_multiplies_by_the_held_bonus_and_the_spent_bonus() -> void:
	var w := _world()
	_fill(w, 10)
	var base := w.runner.stats_of(w, "energy_drain")
	var cast := w.meter.begin_cast(w, "energy_drain", base)
	# +3% per held energy (1.3) times 1 + 10 spent x 0.12 (2.2).
	assert_near(float(cast.damage_max) / float(base.damage_max), 1.3 * 2.2, 0.001)
	assert_eq(cast.meter_spent, 10)
	assert_eq(w.meter.value, 0)


# --- Energy Drain: the heal --------------------------------------------------------------------------------------

## A world with a very large Max HP and a strong knuckle (so the half-Max-HP cap never binds), the player down to 1 HP.
func _healing_world(max_hp := 1000000, pad := 400) -> RunWorld:
	var w := _world("energy_drain", max_hp, pad)
	w.god = true
	w.heal_fraction("hp", 1)
	w.spend_hp(int(w.player_state.hp) - 1)
	w.drain_events()
	return w


func _restored(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "player_restored")


func test_each_cast_heals_the_rank_percent_of_the_damage_it_dealt() -> void:
	for r in range(1, 9):
		var w := _healing_world()
		w.loadout.set_rank("energy_drain", r)
		_mob(w, 100)
		_fill(w, 10)
		var events := _step(w)
		var hits := _hits(events)
		var gains := _restored(events)
		assert_eq(hits.size(), 1, "rank %d" % r)
		assert_eq(gains.size(), 1, "rank %d" % r)
		assert_eq(gains[0].skill, "energy_drain")
		var expected := floori(float(hits[0].damage) * HEAL[r - 1] / 100.0)
		assert_eq(int(gains[0].amount), expected, "rank %d heals %d%% of %d" % [r, HEAL[r - 1], hits[0].damage])
		assert_true(expected > 0)
		assert_eq(int(w.player_state.hp), 1 + expected)


func test_the_heal_is_capped_at_half_max_hp_and_the_targets_max_hp_and_never_exceeds_max_hp() -> void:
	# Half of Max HP: a small Max HP and a big hit.
	var w := _healing_world(100, 3000)
	_mob(w, 100)
	_fill(w, 10)
	var events := _step(w)
	assert_true(float(_hits(events)[0].damage) * 0.12 > floorf(float(w.player_state.max_hp) / 2.0), "control: the uncapped heal is above half Max HP")
	assert_eq(int(_restored(events)[0].amount), floori(float(w.player_state.max_hp) / 2.0), "half the character's Max HP")
	# The target's Max HP, even on an overkill: a 37 HP mob.
	var big := _healing_world()
	var small := _mob(big, 100, 37)
	_fill(big, 10)
	var e2 := _step(big)
	assert_eq(big.swarm.hp[small] <= 0 or not bool(big.swarm.active[small]), true, "the mob died")
	assert_eq(int(_restored(e2)[0].amount), 37, "the target's Max HP, not the damage")
	# Never over max HP: three HP missing.
	var top := _healing_world()
	top.heal_fraction("hp", 1)
	top.spend_hp(3)
	top.drain_events()
	_mob(top, 100)
	_fill(top, 10)
	var e3 := _step(top)
	assert_eq(int(top.player_state.hp), int(top.player_state.max_hp))
	assert_eq(int(_restored(e3)[0].amount), 3, "restores only what is missing")

# --- Energy Charge: the meter on the Buccaneer data --------------------------------------------------------------

## A Buccaneer with flash_fist and somersault_kick (ported skills, still in pirate.json until B4) and a second map to transfer to.
func _meter_world() -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["512"]["playable"] = true
	data.stages.stages.quiet.maps.append(data.stages.stages.quiet.maps[0].duplicate(true))
	var setup := RF.with_basic_attack(RF.setup("quiet", 418, data))
	var w := RunWorld.new(setup)
	w.set_job(512)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	RF.place_player(w, 400)
	w.equipment.worn.weapon = Equipment.create(KNUCKLE, {"incPAD": 17})
	w.refresh_player_stats()
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	return w


func test_the_bar_starts_empty_with_ten_capacity_and_a_snapshot_the_hud_draws_as_ten_pips() -> void:
	var w := _meter_world()
	assert_eq(w.meter.value, 0)
	assert_eq(w.meter.snapshot(), {"id": "energy", "value": 0, "max": 10, "art": ""})
	var hud := HudMeter.new()
	hud.update(w.player_state, {"meter": w.meter.snapshot()})
	assert_eq(hud.pip_count(), 10, "ten pips, drawn (book 511 has no state node)")
	assert_eq(hud.filled_count(), 0)
	_fill(w, 4)
	hud.update(w.player_state, {"meter": w.meter.snapshot()})
	assert_eq(hud.filled_count(), 4)
	hud.free()


func test_one_energy_per_landed_cast_across_targets_and_lines_and_none_without_a_target() -> void:
	var w := _meter_world()
	w.learn_skill("somersault_kick")
	_step(w)
	assert_eq(w.meter.value, 0, "no target, no cast, no energy")
	_mob(w, 40)
	_mob(w, 60)
	_mob(w, -50)
	w.loadout.add_skill_mod("somersault_kick", "attack_count", "add", 1)
	var events := _step(w)
	assert_eq(w.runner.casts, 1)
	assert_eq(_hits(events).size(), 6, "three targets, two lines each")
	assert_eq(w.meter.value, 1, "one energy for the whole cast")
	var changes := events.filter(func(e: Dictionary) -> bool: return e.type == "meter_changed")
	assert_eq(changes, [{"type": "meter_changed", "id": "energy", "value": 1, "max": 10}])


func test_a_line_that_lands_on_nothing_earns_no_energy() -> void:
	# An instant line always deals at least 1 damage, so the only miss is a target that is already gone.
	var w := _meter_world()
	w.learn_skill("flash_fist")
	var m := _mob(w, 40)
	var st := w.meter.begin_cast(w, "flash_fist", w.runner.stats_of(w, "flash_fist"))
	w.swarm.active[m] = 0
	w.hit_mob(m, st, -1)
	assert_eq(_hits(w.drain_events()).size(), 0)
	assert_eq(w.meter.value, 0)


func test_the_bar_never_passes_ten_and_survives_a_map_transfer_but_not_a_new_round() -> void:
	var w := _meter_world()
	for i in 14:
		w.meter.gain("cast_landed", w.events)
	assert_eq(w.meter.value, 10)
	assert_eq(w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "meter_changed").size(), 10, "nothing emitted at the cap")
	w.transfer_pending = true
	w.advance_map()
	assert_eq(w.meter.value, 10, "the transfer keeps the bar")
	assert_eq(_meter_world().meter.value, 0, "a new round starts empty")


func test_the_bar_is_not_saved_in_a_character_snapshot() -> void:
	var w := _meter_world()
	_fill(w, 7)
	var text := JSON.stringify(w.character_snapshot())
	assert_false("energy" in text.to_lower(), "no meter state in the snapshot")
	assert_false("meter" in text.to_lower(), text)


func test_the_held_bonus_is_three_percent_per_energy_on_pool_skills_and_nothing_on_dash_or_subs() -> void:
	var w := _meter_world()
	w.learn_skill("flash_fist")
	w.learn_skill("dash")
	var base := w.runner.stats_of(w, "flash_fist")
	_fill(w, 0)
	assert_eq(w.meter.begin_cast(w, "flash_fist", base).damage_max, base.damage_max, "an empty bar adds nothing")
	for held in [1, 5, 10]:
		_fill(w, held)
		var cast := w.meter.begin_cast(w, "flash_fist", base)
		assert_near(float(cast.damage_max) / float(base.damage_max), 1.0 + 0.03 * held, 0.0005, "%d energy" % held)
	_fill(w, 10)
	var dash := w.runner.stats_of(w, "dash")
	assert_eq(w.meter.begin_cast(w, "dash", dash), dash, "Dash is outside the pool: no bonus, no receipt")
	# A form sub (Shockwave and the others live outside the pool): the same flash_fist numbers under a key the pool does not hold.
	var sub := w.book.def("flash_fist").duplicate(true)
	w.book.defs["a_form_sub"] = sub
	w.learn_skill("a_form_sub")
	var sub_stats := w.runner.stats_of(w, "a_form_sub")
	assert_eq(w.meter.begin_cast(w, "a_form_sub", sub_stats), sub_stats, "a sub neither gets the bonus nor earns energy")
	_mob(w, 40)
	w.meter.value = 3
	w.hit_mob(w.swarm.active.find(1), w.meter.begin_cast(w, "a_form_sub", sub_stats), -1)
	assert_eq(w.meter.value, 3)
	# Shockwave, the real sub (B9 #421; Demolition and Snatch join it in B10): no bonus, no receipt, no energy earned on a hit.
	var shock := w.loadout.stats("shockwave", 4)
	assert_eq(w.meter.begin_cast(w, "shockwave", shock), shock, "Shockwave neither gets the bonus nor earns energy")
	w.meter.value = 3
	w.hit_mob(w.swarm.active.find(1), w.meter.begin_cast(w, "shockwave", shock), -1)
	assert_eq(w.meter.value, 3)


func test_meter_keep_retains_energy_after_a_cast_and_the_card_text_says_energy() -> void:
	var w := _world()
	w.loadout.add_skill_mod("energy_drain", "meter_keep", "add", 2)
	_fill(w, 10)
	var base := w.runner.stats_of(w, "energy_drain")
	var cast := w.meter.begin_cast(w, "energy_drain", base)
	assert_eq(cast.meter_spent, 8)
	assert_eq(w.meter.value, 2, "two energy kept")
	assert_near(float(cast.damage_max) / float(base.damage_max), 1.3 * (1.0 + 8 * 0.12), 0.001, "only the spent energy counts for the finisher bonus")


# --- the full-bar cue --------------------------------------------------------------------------------------------

const CUE := {"effect": "Skill.wz/511.img/skill/5110001/affected", "sound": "Sound.wz/Skill.img/5110001/Use"}


func _changed(value: int, max_value := 10) -> Dictionary:
	return {"type": "meter_changed", "id": "energy", "value": value, "max": max_value}


func test_the_cue_plays_once_when_the_bar_fills_and_not_again_until_it_has_dropped_and_refilled() -> void:
	var played: Array = []
	var cue := MeterCue.new(CUE, func(effect: String, sound: String) -> void: played.append([effect, sound]))
	for v in range(1, 10):
		cue.on_event(_changed(v))
	assert_eq(played.size(), 0, "nothing below full")
	cue.on_event(_changed(10))
	assert_eq(played, [[CUE.effect, CUE.sound]], "the affected art and the Use sound")
	cue.on_event(_changed(10))
	assert_eq(played.size(), 1, "still full: not again")
	cue.on_event(_changed(2))
	cue.on_event(_changed(3))
	assert_eq(played.size(), 1, "dropped but not refilled")
	for v in range(4, 11):
		cue.on_event(_changed(v))
	assert_eq(played.size(), 2, "refilled: once more")


func test_a_finisher_that_keeps_energy_rearms_the_cue() -> void:
	var played: Array = []
	var cue := MeterCue.new(CUE, func(effect: String, sound: String) -> void: played.append(effect))
	cue.on_event(_changed(10))
	cue.on_event(_changed(2)) # Drain spent eight and kept two
	cue.on_event(_changed(10))
	assert_eq(played.size(), 2)


func test_the_cue_ignores_other_events_other_meters_and_a_job_without_a_cue() -> void:
	var played: Array = []
	var sink := func(effect: String, sound: String) -> void: played.append([effect, sound])
	var cue := MeterCue.new(CUE, sink)
	cue.on_event({"type": "mob_hit", "value": 10, "max": 10})
	assert_eq(played.size(), 0, "not a meter_changed")
	var none := MeterCue.new({}, sink)
	none.on_event(_changed(10))
	assert_eq(played.size(), 0, "Hero's meter has no cue")
	var sound_only := MeterCue.new({"sound": "s"}, sink)
	sound_only.on_event(_changed(10))
	assert_eq(played, [["", "s"]], "either half may be omitted")


func test_a_real_round_fills_the_bar_with_landed_casts_and_the_cue_plays_exactly_once() -> void:
	var w := _meter_world()
	w.learn_skill("flash_fist")
	var played: Array = []
	var cue := MeterCue.new(w.jobs.lineage_value(512, "meter", {}).get("cue", {}),
		func(effect: String, sound: String) -> void: played.append([effect, sound]))
	var m := _mob(w, 40, 100000000)
	var x0: float = w.swarm.x[m]
	w.god = true
	for tick in 60 * 60:
		w.swarm.x[m] = x0 # the hit's knock-back must not walk the mob out of the box between casts
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			cue.on_event(e)
		if w.meter.value >= 10:
			break
	assert_eq(w.meter.value, 10)
	assert_eq(played, [["Skill.wz/511.img/skill/5110001/affected", "Sound.wz/Skill.img/5110001/Use"]])


# --- real cache --------------------------------------------------------------------------------------------------

func test_real_cache_drain_numbers_at_all_eight_ranks_and_its_art_nodes() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.get_default()
	var img := library.img("Skill.wz/511.img")
	assert_true(img != null, "book 511 imported (cache-413 or any cache built after the Buccaneer fragment)")
	if img == null:
		return
	var root: Dictionary = img.root
	var b := SkillBook.from_data(DataRepo.load_all().skills, {"511": root})
	var lo := Loadout.new(b)
	lo.add_skill("energy_drain")
	assert_eq(b.rank_table("energy_drain").map(func(v: Variant) -> int: return int(v)), LEVELS)
	for rank in range(1, 9):
		var row: Dictionary = root.skill["5111004"].level[str(LEVELS[rank - 1])]
		var st := lo.stats("energy_drain", rank)
		assert_near(st.damage_pct, DAMAGE[rank - 1] / 100.0, 0.0001, "rank %d damage" % rank)
		assert_eq(int(row.x), HEAL[rank - 1], "rank %d heal percent in the WZ node" % rank)
		assert_near(b.canonical("energy_drain", LEVELS[rank - 1], "x"), float(HEAL[rank - 1]), 0.0001)
		assert_eq(st.mob_count, 1)
		assert_eq(st.box, Rect2(-200, -100, 200, 100), "the canonical box at every rank")
	var node: Dictionary = root.skill["5111004"]
	assert_eq((node.action as Dictionary)["0"], "edrain")
	assert_eq((node.effect as Dictionary).keys().size() - (1 if (node.effect as Dictionary).has("z") else 0) >= 15, true, "effect: 15 frames")
	assert_true((node.hit as Dictionary).has("0"), "hit/0")
	assert_true(library.find_anim("Skill.wz/511.img/skill/5111004/effect") != null)
	assert_true(library.find_anim("Skill.wz/511.img/skill/5111004/hit/0") != null)
	# The cue's art: Energy Charge `affected` is a 180 ms blank and ten 90 ms frames (1.08 s), and its Use sound loads.
	var affected: SpriteAnim = library.find_anim("Skill.wz/511.img/skill/5110001/affected")
	assert_true(affected != null)
	assert_eq(affected.frame_count(), 11)
	assert_near(affected.duration(), 0.18 + 10 * 0.09, 0.001)
	assert_true(library.sound("Sound.wz/Skill.img/5110001/Use") != null, "Energy Charge Use")
	assert_true(library.sound("Sound.wz/Skill.img/5111004/Use") != null, "Energy Drain Use")
	assert_true(library.sound("Sound.wz/Skill.img/5111004/Hit") != null, "Energy Drain Hit")
	assert_true(library.missing.is_empty(), str(library.missing))


# --- rarity bonuses: every one changes the resolved cast ---------------------------------------------------------

## Casts Drain in a world with a full bar every tick (so the cooldown is the only pacing) at a mob that is put back in the box
## after every tick; returns the casts over `seconds`, the damage dealt, the bar left by the first cast and its resolved stats.
func _probe(effects: Array, seconds: float) -> Dictionary:
	var w := _world("energy_drain", 0, 400)
	w.god = true
	var mob := _mob(w, 100, 1000000000)
	var x0: float = w.swarm.x[mob]
	for e: Dictionary in effects:
		w.loadout.add_skill_mod("energy_drain", String(e.stat), String(e.op), float(e.value))
	var dealt := 0
	var left := -1
	for tick in int(seconds / DT):
		if w.runner.casts == 0 or left >= 0:
			w.meter.value = 10
		w.swarm.x[mob] = x0
		w.swarm.hp[mob] = w.swarm.max_hp[mob]
		w.step(DT, MoveInput.new())
		for ev: Dictionary in w.drain_events():
			if ev.type == "mob_hit":
				dealt += int(ev.damage)
		if left < 0 and w.runner.casts >= 1:
			left = w.meter.value
	return {"casts": w.runner.casts, "dealt": dealt, "left": left, "stats": w.loadout.stats("energy_drain")}


func test_each_rarity_bonus_changes_the_resolved_cast() -> void:
	var bonuses: Dictionary = _world().book.def("energy_drain").rarity_bonuses
	assert_eq(bonuses.keys(), TIERS)
	var base_damage := _probe([], 12.0)
	var base_casts := _probe([], 66.0)
	var checked := 0
	for tier: String in TIERS:
		for bonus: Dictionary in bonuses[tier]:
			for effect: Dictionary in bonus.effects:
				var label := "%s %s (%s)" % [tier, bonus.id, effect.stat]
				match String(effect.stat):
					"damage":
						var with := _probe([effect], 12.0)
						assert_true(int(with.dealt) > int(base_damage.dealt), "%s: dealt %d -> %d" % [label, base_damage.dealt, with.dealt])
						assert_true(float(with.stats.damage_max) > float(base_damage.stats.damage_max), label)
					"cooldown":
						var with := _probe([effect], 66.0)
						assert_true(float(with.stats.cooldown) < float(base_casts.stats.cooldown), "%s: resolved cooldown" % label)
						assert_true(int(with.casts) > int(base_casts.casts), "%s: casts %d -> %d" % [label, base_casts.casts, with.casts])
					"meter_keep":
						var with := _probe([effect], 3.0)
						assert_eq(int(base_damage.left), 0, "control: a plain Drain empties the bar")
						assert_eq(int(with.left), int(effect.value), "%s: energy left after the cast" % label)
					_:
						fail("%s: a stat this audit does not know" % label)
				checked += 1
	assert_eq(checked, 5, "1 + 1 + 1 + 2 effects")


func test_the_legendary_card_keeps_energy_and_hits_harder_and_the_unique_only_keeps() -> void:
	var unique := _probe(_effects("unique"), 3.0)
	var legendary := _probe(_effects("legendary"), 3.0)
	var plain := _probe([], 3.0)
	assert_eq([int(plain.left), int(unique.left), int(legendary.left)], [0, 2, 2])
	assert_true(float(legendary.stats.damage_max) > float(unique.stats.damage_max))
	assert_eq(float(unique.stats.damage_max), float(plain.stats.damage_max), "Unique has no damage effect")


func _effects(tier: String) -> Array:
	var out := []
	for bonus: Dictionary in _world().book.def("energy_drain").rarity_bonuses[tier]:
		out.append_array(bonus.effects)
	return out


func test_the_cards_apply_the_bonuses_and_say_energy() -> void:
	for tier: String in TIERS:
		var w := _world()
		var card := w.upgrades.choice_card("energy_drain_rank", w, tier)
		var before := w.loadout.stats("energy_drain")
		w.upgrades.apply(card.id, w, tier)
		var after := w.loadout.stats("energy_drain")
		match tier:
			"rare":
				assert_true(float(after.damage_max) > float(before.damage_max))
			"epic":
				assert_true(float(after.cooldown) < float(before.cooldown))
			_:
				assert_eq(int(after.meter_keep), 2)
				assert_true("Keeps 2 energy" in String(card.desc), String(card.desc))
				assert_false("orbs" in String(card.desc), String(card.desc))
