extends TestCase
## Warrior first job (100, spec #151 ticket #163), end to end on the synthetic map with the real survivor data: the
## advancement window and grants, Power Strike (weapon reach), Slash Blast (range around, HP and MP cost), facing
## before a cast, Iron Body, the three passives, the cards and the bot's weapon-aware scans. Seeded, fixed ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Mob 1110100 (level 15, PDD 12) is the target; its body is shrunk so reach tests are about the box, not the sprite.
const MOB := 1110100


func _world(seed_value := 7, job := 100) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.mp = 1000
	data.balance.player.skills = []
	data.balance.magnet_radius = 0
	var w := RunWorld.new(RF.with_basic_attack(RF.setup("quiet", seed_value, data)))
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	if job != 0:
		w.change_job(job)
	RF.place_player(w, 400)
	w.god = true # nothing here is about taking damage; HP-cost tests set the pool directly
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float) -> int:
	return RF.put_mob(w, MOB, w.player.pos.x + dx, 190.0, 1000.0)


## Sets the HP and MP pools directly and refreshes the published player_state.
func _pools(w: RunWorld, hp: float, mp: float = -1.0) -> void:
	w._hp = hp
	if mp >= 0.0:
		w._mp = mp
	w._write_player_state(0.0)


## Collects EXP worth one level through the real pickup path and answers the level-up window.
func _level_up(w: RunWorld) -> void:
	var level := w.progression.level
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	for tick in 120:
		w.step(DT, MoveInput.new())
		if w.progression.level > level:
			break
	assert_eq(w.progression.level, level + 1, "EXP was collected")
	RF.auto_choose(w)


func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


# --- the job window and its grants ----------------------------------------------------------------------------

func test_the_lv10_window_offers_the_warrior_and_advancing_gives_hp_and_str_ap() -> void:
	var w := _world(11, 0)
	var exp_gain := func(level: int) -> void:
		var need := w.progression.curve.total_to(level) - w.progression.curve.total_to(w.progression.level) \
			- w.progression.exp
		w.pickups.spawn(w.player.pos, need, 4000019)
		for tick in 120:
			w.step(DT, MoveInput.new())
			if w.state != RunWorld.PLAYING or w.progression.level == level:
				break
	for level in range(2, 10):
		exp_gain.call(level)
		RF.auto_choose(w)
	assert_eq(w.progression.level, 9)
	exp_gain.call(10)
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "Lv 10 opens the advancement window")
	var warrior: Array = w.pending_jobs.filter(func(o: Dictionary) -> bool: return int(o.job_id) == 100)
	assert_eq(warrior.size(), 1)
	assert_true(bool(warrior[0].available), "the Warrior is on offer at Lv 10")
	assert_eq(warrior[0].name, "Warrior")
	var others: Array = w.pending_jobs.filter(func(o: Dictionary) -> bool: return int(o.job_id) in [300, 400, 500])
	assert_true(others.all(func(o: Dictionary) -> bool: return not o.available and o.reason == "Not in this build"),
		"Bowman, Thief and Pirate stay locked")
	var hp0: int = w.player_state.max_hp
	var mp0: int = w.player_state.max_mp
	var str0: int = w.player_state.str
	assert_true(w.apply_job(100))
	assert_eq(w.player_state.max_hp, hp0 + 225, "first-job Max HP grant")
	assert_eq(w.player_state.max_mp, mp0, "no MP grant")
	assert_eq(w.player_state.str, str0, "advancing redistributes nothing: the earned AP already sat in STR")
	assert_eq(w.player_state.dex, 5, "DEX takes no AP: no Warrior item needs it")
	assert_eq(w.weapon_id(), 1302000, "no weapon grant: the creation weapon stays worn")
	var ids := w.pending_cards.map(func(c: Dictionary) -> String: return c.id)
	assert_has(ids, "power_strike_new", "the advancement draw offers Power Strike")
	assert_has(ids, "slash_blast_new", "and Slash Blast")
	assert_eq(w.pending_cards.size(), 3)
	w.apply_choice("power_strike_new")
	RF.auto_choose(w)
	var str1: int = w.player_state.str
	exp_gain.call(11)
	RF.auto_choose(w)
	assert_eq(w.player_state.str, str1 + 5, "every earned AP goes to STR")
	assert_eq(w.player_state.dex, 5)


func test_warrior_growth_is_26_hp_and_5_mp_per_level() -> void:
	var w := _world(12)
	var hp0: int = w.player_state.max_hp
	var mp0: int = w.player_state.max_mp
	_level_up(w)
	assert_eq(w.player_state.max_hp, hp0 + 26)
	assert_eq(w.player_state.max_mp, mp0 + 5)


func test_an_unforced_bot_still_takes_the_magician_when_both_first_jobs_are_open() -> void:
	var options := [{"job_id": 100, "available": true}, {"job_id": 200, "available": true}]
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var state := rng.state
	assert_eq(BotInput.pick_job(options, rng), 200, "tier C default: the Magician was the only first job")
	assert_eq(rng.state, state, "and the choice draws no random number, as before the Warrior existed")
	assert_eq(BotInput.pick_job(options, rng, 100), 100, "--job=100 takes the Warrior")
	assert_eq(BotInput.pick_job([{"job_id": 100, "available": true}], rng), 100, "the only open job is taken")


# --- data -----------------------------------------------------------------------------------------------------

func test_the_six_warrior_skills_are_defined_with_canonical_ids_and_level_counts() -> void:
	var w := _world(13)
	var want := {"power_strike": [1001004, 20], "slash_blast": [1001005, 20], "iron_body": [1001003, 20],
		"improved_hp_recovery": [1000000, 16], "improved_max_hp": [1000001, 10], "endure": [1000002, 8]}
	for key: String in want:
		assert_true(w.book.has(key), key)
		assert_eq(w.book.skill_id(key), want[key][0], key)
		assert_eq(w.book.max_rank(key), want[key][1], "%s canonical levels" % key)
		assert_eq(w.book.max_level(key), want[key][1], key)
	for key in ["power_strike", "slash_blast"]:
		assert_eq(Array(w.book.weapon_families(key)), ["sword", "axe", "blunt", "spear", "polearm"])
		for family in ["dagger", "wand", "staff", "bow", "claw", "knuckle", "gun", ""]:
			assert_false(w.book.usable_with(key, family), "%s is not usable with %s" % [key, family if family != "" else "bare hands"])
	for key in ["iron_body", "improved_hp_recovery", "improved_max_hp", "endure"]:
		assert_true(w.book.usable_with(key, "") and w.book.usable_with(key, "wand"), "%s needs no weapon" % key)


func test_real_100_img_matches_the_data() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/100.img")
	if img == null:
		skip("the cache has no Skill.wz/100.img (import with the Warrior manifest)")
		library.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"100": img.root})
	for key in ["power_strike", "slash_blast", "iron_body", "improved_hp_recovery", "improved_max_hp", "endure"]:
		assert_eq(book.max_level(key), book.max_rank(key), "%s: ranks cover every canonical level" % key)
	assert_eq(book.canonical("power_strike", 1, "damage"), 165.0)
	assert_eq(book.canonical("power_strike", 20, "damage"), 260.0)
	assert_eq(book.canonical("slash_blast", 1, "hpCon"), 8.0)
	assert_eq(book.canonical("slash_blast", 20, "mpCon"), 14.0)
	assert_eq(book.canonical("slash_blast", 16, "range"), 150.0)
	assert_eq(book.canonical("slash_blast", 1, "mobCount"), 6.0)
	assert_eq(book.canonical("iron_body", 20, "pdd"), 40.0)
	assert_eq(book.canonical("improved_hp_recovery", 16, "hp"), 50.0)
	assert_eq(book.canonical("improved_max_hp", 10, "x"), 40.0)
	assert_eq(book.canonical("endure", 8, "time"), 10.0)
	library.free()


# --- Power Strike: one target inside the weapon's reach ---------------------------------------------------------

func test_power_strike_hits_the_nearest_mob_inside_the_weapon_reach_and_none_outside() -> void:
	var w := _world(21)
	w.learn_skill("power_strike")
	w.player.facing = -1
	var reach := w.basic.reach(w)
	assert_near(reach, 88.0, 0.001, "the synthetic sword afterimage reaches 88 px")
	var far := _mob(w, -150.0)
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 0, "a mob outside the swing envelope does not trigger it")
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far])
	var mid := _mob(w, -60.0)
	var near := _mob(w, -40.0)
	var mp0: int = w.player_state.mp
	events = _cast(w)
	var hits := _of(events, "mob_hit")
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(hits.size(), 1, "attackCount 1 and one target")
	assert_eq(hits[0].mob, near, "the nearest mob in reach")
	assert_eq(hits[0].skill, "power_strike")
	assert_eq(mp0 - int(w.player_state.mp), 4, "canonical rank-1 MP cost")
	assert_eq(w.swarm.hp[mid], w.swarm.max_hp[mid])
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far])


func test_power_strike_damage_follows_the_canonical_percent_and_the_physical_formula() -> void:
	var w := _world(22)
	w.learn_skill("power_strike")
	var st := w.loadout.stats("power_strike")
	assert_eq(st.damage_type, "physical")
	assert_near(float(st.damage_pct), 1.65, 1e-9, "rank 1 is 165 %")
	assert_eq(st.attack_kind, "swing", "the sword's first basic stance is a swing")
	assert_eq(st.action, "swingO1")
	w.loadout.set_rank("power_strike", 20)
	assert_near(float(w.loadout.stats("power_strike").damage_pct), 2.6, 1e-9, "rank 20 is 260 %")
	assert_eq(w.loadout.stats("power_strike").attack_count, 1)
	assert_eq(w.loadout.stats("power_strike").mob_count, 1, "the canonical skill hits one monster")


func test_power_strike_stance_is_the_held_weapons_first_basic_action() -> void:
	var lo := Loadout.new(SkillBook.from_data(DataRepo.load_all().skills, {}))
	lo.add_skill("power_strike")
	for pair: Array in [[1302000, "swingO1", "swing"], [1432000, "stabT1", "stab"], [1442000, "swingP1", "swing"],
			[1402000, "swingT1", "swing"], [0, "swingO1", "swing"]]:
		lo.weapon_id = int(pair[0])
		lo.weapon_family = WeaponInfo.family(int(pair[0]))
		var st := lo.stats("power_strike")
		assert_eq(st.action, pair[1], "weapon %d" % int(pair[0]))
		assert_eq(st.attack_kind, pair[2], "weapon %d" % int(pair[0]))


func test_target_cards_are_the_only_source_of_extra_power_strike_targets() -> void:
	var w := _world(23)
	w.learn_skill("power_strike")
	w.player.facing = -1
	var mobs: Array[int] = []
	for dx: float in [-30.0, -45.0, -60.0, -75.0]:
		mobs.append(_mob(w, dx))
	assert_eq(_of(_cast(w), "mob_hit").size(), 1)
	w.runner.cooldowns["power_strike"] = 0.0
	w.upgrades.apply("power_strike_targets", w)
	assert_eq(w.loadout.stats("power_strike").mob_count, 2)
	var hits := _of(_cast(w), "mob_hit")
	assert_eq(hits.map(func(e: Dictionary) -> int: return e.mob), [mobs[0], mobs[1]], "the two nearest")


# --- Slash Blast: everything around, for HP and MP --------------------------------------------------------------

func test_slash_blast_hits_at_most_six_mobs_within_range_on_both_sides_and_costs_hp_and_mp() -> void:
	var w := _world(31)
	w.learn_skill("slash_blast")
	var st := w.loadout.stats("slash_blast")
	assert_eq(st.cast_rule, "range_around")
	assert_near(float(st.range), 130.0, 1e-9, "rank 1 canonical range")
	assert_eq(st.mob_count, 6)
	assert_eq(st.hp_cost, 8)
	assert_eq(st.mp_cost, 6)
	var outside := _mob(w, 160.0)
	var inside: Array[int] = []
	for dx: float in [-20.0, 30.0, -50.0, 70.0, -90.0, 110.0, -120.0, 125.0]:
		inside.append(_mob(w, dx))
	w.god = false
	var hp0: int = w.player_state.hp
	var mp0: int = w.player_state.mp
	var events := _cast(w)
	var hits := _of(events, "mob_hit")
	assert_eq(hits.size(), 6, "mobCount 6 caps the blast")
	assert_eq(hits.map(func(e: Dictionary) -> int: return e.mob), [inside[0], inside[1], inside[2], inside[3], inside[4], inside[5]],
		"the six nearest")
	assert_eq(hp0 - int(w.player_state.hp), 8, "canonical hpCon")
	assert_eq(mp0 - int(w.player_state.mp), 6, "canonical mpCon")
	assert_eq(w.swarm.hp[outside], w.swarm.max_hp[outside], "beyond range")
	assert_eq(w.swarm.hp[inside[7]], w.swarm.max_hp[inside[7]], "inside range but past the sixth")


func test_slash_blast_range_and_target_cards_widen_it() -> void:
	var w := _world(32)
	w.learn_skill("slash_blast")
	var edge := _mob(w, 150.0)
	assert_eq(_of(_cast(w), "cast").size(), 0, "150 px is beyond the rank-1 range")
	w.upgrades.apply("slash_blast_range", w)
	assert_near(float(w.loadout.stats("slash_blast").range), 156.0, 1e-3, "range x1.2")
	assert_eq(_of(_cast(w), "mob_hit").map(func(e: Dictionary) -> int: return e.mob), [edge])
	w.upgrades.apply("slash_blast_targets", w)
	assert_eq(w.loadout.stats("slash_blast").mob_count, 8, "+2 targets per step over the canonical 6")


func test_slash_blast_never_casts_when_its_hp_cost_would_leave_no_hp() -> void:
	var w := _world(33)
	w.learn_skill("slash_blast")
	w.god = false
	var m := _mob(w, 40.0)
	_pools(w, 8.0) # exactly the rank-1 cost: paying it would kill
	var mp0: int = w.player_state.mp
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 0)
	assert_eq(_of(events, "mp_short").size(), 0, "it is not an MP shortage")
	assert_eq(w.player_state.hp, 8)
	assert_eq(w.player_state.mp, mp0, "nothing is paid")
	assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
	_pools(w, 9.0)
	events = _cast(w)
	assert_eq(_of(events, "cast").size(), 1, "one HP to spare is enough")
	assert_eq(w.player_state.hp, 1)


func test_slash_blast_does_not_charge_hp_or_mp_when_mp_is_short() -> void:
	var w := _world(34)
	w.learn_skill("slash_blast")
	w.god = false
	_mob(w, 40.0)
	_pools(w, w._hp, 5.0)
	var hp0: int = w.player_state.hp
	var events := _cast(w)
	assert_eq(_of(events, "mp_short").size(), 1)
	assert_eq(w.player_state.hp, hp0, "a failed MP payment leaves HP alone")
	assert_eq(w.player_state.mp, 5)


# --- facing ---------------------------------------------------------------------------------------------------------

func test_both_attacks_turn_the_standing_character_toward_the_nearest_mob() -> void:
	for key in ["power_strike", "slash_blast"]:
		for side in [-1, 1]:
			var w := _world(41)
			w.learn_skill(key)
			w.player.facing = -side
			var m := _mob(w, 50.0 * side)
			var events := _cast(w)
			assert_eq(_of(events, "cast").size(), 1, "%s casts at a mob behind it" % key)
			assert_eq(w.player.facing, side, "%s faces the mob (side %d)" % [key, side])
			assert_eq(_of(events, "cast")[0].facing, side, "the cast event carries the new facing")
			assert_lt_hp(w, m, key)


func assert_lt_hp(w: RunWorld, m: int, key: String) -> void:
	assert_true(w.swarm.hp[m] < w.swarm.max_hp[m], "%s hit it" % key)


# --- Iron Body ------------------------------------------------------------------------------------------------------

func test_iron_body_recasts_on_expiry_and_adds_weapon_defence() -> void:
	var w := _world(51)
	w.learn_skill("iron_body")
	var pdd0: float = w.hit_defense().pdd
	w.step(DT, MoveInput.new())
	var events := w.drain_events()
	assert_eq(_of(events, "buff_cast").size(), 1, "cast as soon as it is affordable")
	assert_true(w.buffs.has("iron_body"))
	assert_near(float(w.hit_defense().pdd) - pdd0, 2.0, 1e-9, "rank 1: +2 W.DEF")
	assert_eq(75.0, float(w.loadout.stats("iron_body").duration))
	var casts := 1
	var expiries := 0
	for tick in int(80.0 / DT):
		w.step(DT, MoveInput.new())
		var step_events := w.drain_events()
		casts += _of(step_events, "buff_cast").size()
		expiries += _of(step_events, "buff_expired").size()
	assert_eq(expiries, 1, "it ran out once in 80 s")
	assert_eq(casts, 2, "and was recast when it did")
	assert_true(w.buffs.has("iron_body"))


# --- passives ---------------------------------------------------------------------------------------------------------

func test_improved_hp_recovery_adds_its_canonical_hp_to_every_pulse() -> void:
	var gains: Array[int] = []
	for rank in [0, 1, 16]:
		var w := _world(61)
		w.god = false
		if rank > 0:
			w.learn_skill("improved_hp_recovery")
			w.loadout.set_rank("improved_hp_recovery", rank)
		_pools(w, 20.0)
		for tick in 601:
			w.step(DT, MoveInput.new())
		gains.append(int(w.player_state.hp) - 20)
	assert_eq(gains[1] - gains[0], 3, "rank 1 adds +3 HP per pulse")
	assert_eq(gains[2] - gains[0], 50, "rank 16 adds +50 HP per pulse")


func test_improved_max_hp_adds_its_hp_to_each_later_level_up_only() -> void:
	var w := _world(62)
	w.learn_skill("improved_max_hp")
	w.loadout.set_rank("improved_max_hp", 3)
	var hp0: int = w.player_state.max_hp
	assert_eq(w.player_state.max_hp, hp0, "learning it is not retroactive")
	_level_up(w)
	assert_eq(w.player_state.max_hp, hp0 + 26 + 12, "26 growth + canonical x 12 at skill level 3")


func test_endure_recovers_hp_every_canonical_interval_only_while_climbing() -> void:
	for rank in [1, 8]:
		var w := _world(63)
		w.learn_skill("endure")
		w.loadout.set_rank("endure", rank)
		var interval := float(w.book.canonical("endure", rank, "time"))
		assert_eq(interval, 31.0 if rank == 1 else 10.0)
		w.god = false
		# Standing still for a minute: only the ordinary regeneration runs.
		_pools(w, 30.0)
		for tick in 3600:
			w.step(DT, MoveInput.new())
		assert_eq(_of(w.drain_events(), "player_restored").filter(
			func(e: Dictionary) -> bool: return e.skill == "endure").size(), 0, "no Endure on the ground")
		var ladder := -1
		for i in w.ladders.count():
			if w.ladders.is_ladder[i] == 1:
				ladder = i
		RF.place_player(w, w.ladders.x[ladder])
		var up := MoveInput.new()
		up.up = true
		w.step(DT, up)
		assert_eq(w.player.ladder, ladder, "grabbed the ladder")
		_pools(w, 30.0)
		w.drain_events()
		var seconds := 65.0
		for tick in int(seconds / DT):
			w.step(DT, MoveInput.new())
		var pulses := _of(w.drain_events(), "player_restored").filter(
			func(e: Dictionary) -> bool: return e.skill == "endure")
		assert_eq(pulses.size(), int(seconds / interval), "one recovery every %d s on the ladder (rank %d)" % [int(interval), rank])
		assert_eq(pulses[0].stat, "hp")
		assert_eq(pulses[0].amount, 10, "one base regeneration pulse (tier C)")


# --- cards ----------------------------------------------------------------------------------------------------------

func test_warrior_cards_are_offered_only_to_job_100_holding_a_warrior_weapon() -> void:
	var warrior_cards := ["power_strike_new", "slash_blast_new", "iron_body_new", "improved_hp_recovery_new",
		"improved_max_hp_new", "endure_new"]
	var magician := _world(71, 200)
	var beginner := _world(71, 0)
	for id in warrior_cards:
		assert_false(id in magician.upgrades.eligible(magician), "%s is not offered to a Magician" % id)
		assert_false(id in beginner.upgrades.eligible(beginner), "%s is not offered to a Beginner" % id)
	var w := _world(71)
	var ids: Array = w.upgrades.eligible(w)
	for id in warrior_cards:
		assert_has(ids, id)
	# A wand can use no attack: the attack cards go, the weaponless skills stay.
	w.equipment.worn["weapon"] = {"id": 1372005}
	ids = w.upgrades.eligible(w)
	assert_false("power_strike_new" in ids or "slash_blast_new" in ids, "no Power Strike or Slash Blast with a wand")
	for id in ["iron_body_new", "improved_hp_recovery_new", "improved_max_hp_new", "endure_new"]:
		assert_has(ids, id)
	w.equipment.worn.erase("weapon")
	ids = w.upgrades.eligible(w)
	assert_false("power_strike_new" in ids or "slash_blast_new" in ids, "no attack cards bare-handed")
	w.equipment.worn["weapon"] = {"id": 1432000}
	assert_has(w.upgrades.eligible(w), "power_strike_new", "a spear is a Warrior weapon")


func test_every_attack_has_a_hits_more_mobs_card() -> void:
	var w := _world(72)
	for pair: Array in [["power_strike", "power_strike_targets"], ["slash_blast", "slash_blast_targets"]]:
		var card := w.upgrades.card(pair[1])
		assert_eq(card.kind, "skill_mod")
		assert_eq(card.skill, pair[0])
		assert_eq(card.effects[0].stat, "count")
		assert_true(bool(card.get("power", false)), "it counts as a power card")
	assert_true(w.upgrades.card("slash_blast_range").effects[0].stat == "range", "and Slash Blast a wider-area card")


func test_rank_cards_raise_the_level_and_preview_the_damage_percent() -> void:
	var w := _world(73)
	assert_eq(w.upgrades.apply("power_strike_new", w), 1)
	assert_eq(w.upgrades.apply("power_strike_rank", w), 1)
	assert_eq(w.loadout.rank("power_strike"), 2)
	assert_near(float(w.loadout.stats("power_strike").damage_pct), 1.7, 1e-9)
	var card := w.upgrades.choice_card("power_strike_rank", w)
	assert_has(card.skill_changes, "damage")
	assert_eq(int(card.skill_changes.damage.before), 170)


# --- reach and the bot -----------------------------------------------------------------------------------------------

func test_reach_of_reads_the_weapon_swing_and_the_slash_blast_range() -> void:
	var w := _world(81)
	w.learn_skill("power_strike")
	w.learn_skill("slash_blast")
	w.learn_skill("iron_body")
	assert_near(SkillRunner.reach_of(w.loadout.stats("power_strike"), w), 88.0, 0.001, "the basic attack's reach")
	assert_near(SkillRunner.reach_of(w.loadout.stats("slash_blast"), w), 130.0, 1e-6, "range around the body")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("iron_body"), w), 0.0, "a buff is not an attack")
	w.upgrades.apply("slash_blast_range", w)
	assert_near(SkillRunner.reach_of(w.loadout.stats("slash_blast"), w), 156.0, 1e-3)


func test_the_bot_ignores_skills_the_held_weapon_cannot_use_and_unaffordable_hp_costs() -> void:
	var w := _world(82)
	w.learn_skill("slash_blast")
	assert_near(BotInput._reach_profile(w).x, 130.0, 1e-6, "with a sword Slash Blast is the longest attack")
	assert_near(BotInput._reach_profile(w).y, 130.0, 1e-6, "and it is ready")
	w.god = false
	_pools(w, 8.0)
	assert_near(BotInput._reach_profile(w).y, 88.0, 0.001, "it cannot be paid in HP: only the swing is ready")
	_pools(w, 200.0)
	w.equipment.worn["weapon"] = {"id": 1372005}
	w.loadout.weapon_family = w.held_weapon_family()
	assert_near(BotInput._reach_profile(w).x, 88.0, 0.001, "a wand cannot use Slash Blast: only the swing counts")
	var m := _mob(w, 40.0)
	assert_true(BotInput._can_duel(w, m), "and nothing else can fire, so the bot stands and swings")


func test_the_forced_warrior_bot_closes_to_melee_range() -> void:
	var w := _world(83)
	w.learn_skill("power_strike")
	_mob(w, 200.0)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var memo := {}
	var mi := BotInput.decide(w, memo)
	assert_true(mi.right, "it walks toward a mob 200 px away instead of kiting")


# --- card previews and skill text --------------------------------------------------------------------------------------

func test_passive_rank_cards_preview_their_own_numbers() -> void:
	var w := _world(91)
	var cases := [["improved_hp_recovery", UpgradePool.PASSIVE_REGEN_HP, 3, 6], ["improved_max_hp", UpgradePool.PASSIVE_MAX_HP, 4, 8],
		["endure", UpgradePool.PASSIVE_CLIMB_INTERVAL, 31, 28]]
	for c: Array in cases:
		w.upgrades.apply("%s_new" % c[0], w)
		var card := w.upgrades.choice_card("%s_rank" % c[0], w)
		assert_has(card.skill_changes, c[1], "%s previews under %s" % [c[0], c[1]])
		assert_eq(card.skill_changes.size(), 1, "and nothing else")
		assert_eq([int(card.skill_changes[c[1]].before), int(card.skill_changes[c[1]].after)], [c[2], c[3]])
		var lines := LevelUpWindow.change_lines(card)
		assert_eq(lines.size(), 1, "%s has one change line: %s" % [c[0], lines])
	assert_eq(LevelUpWindow.change_lines(w.upgrades.choice_card("endure_rank", w))[0], "Recovery every: 31 s → 28 s")


func test_slash_blast_text_names_its_hp_and_mp_cost_range_and_targets() -> void:
	var w := _world(92)
	w.learn_skill("slash_blast")
	var text := SkillText.new(w.book)
	var line := text.level_line("slash_blast", 1, w.loadout.stats("slash_blast"))
	assert_eq(line, "HP -8, MP -6; damage 72%, up to 6 monsters within 130 px")
	w.learn_skill("power_strike")
	assert_eq(text.level_line("power_strike", 20, w.loadout.stats("power_strike", 20)),
		"MP -12; damage 260%, up to 1 monster")
