extends TestCase
## Warrior first job (100, spec #151 ticket #163), on the synthetic map with the real survivor data: Power Strike
## (weapon reach), Slash Blast (range around, HP cost), facing before a cast, Iron Body, the three passives, the
## cards and the bot's reach scans. The character is stood as a Warrior directly (RF.as_job: job 100 with the sword its
## removed advancement granted; #284 removed advancement). Seeded, fixed ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
## Mob 1110100 (level 15, PDD 12) is the target; its body is shrunk so reach tests are about the box, not the sprite.
const MOB := 1110100


func _world(seed_value := 7, job := 100) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["112"].playable = true
	data.balance.player.hp = 275 # the Beginner's 50 plus the removed first-job +225 grant (#284)
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	setup["job"] = job # a job without start skills: the loadout starts empty
	var w := RunWorld.new(setup)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-5, -10, 10, 10)
		mk.move_speed = 0.0
	if job != 0:
		RF.as_job(w, job)
	RF.place_player(w, 400)
	w.god = true # nothing here is about taking damage; HP-cost tests set the pool directly
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float) -> int:
	return RF.put_mob(w, MOB, w.player.pos.x + dx, 190.0, 1000.0)


## Sets the HP pool directly and refreshes the published player_state.
func _pools(w: RunWorld, hp: float) -> void:
	w._hp = hp
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


func test_cheap_target_check_matches_warrior_admission_on_both_sides() -> void:
	# The #146 cheap target scan must keep both #151 rules, including Power Strike turning while walking or airborne.
	for key: String in ["power_strike", "slash_blast"]:
		for facing in [-1, 1]:
			for dx in [-1000.0, -40.0, 40.0, 1000.0]:
				var w := _world()
				w.learn_skill(key)
				w.player.facing = facing
				_mob(w, dx)
				w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
				var st := w.runner.stats_of(w, key)
				var origin := w.cast_origin()
				var admitted := not w.runner._admit_cast(w, key, st, origin).is_empty()
				assert_eq(admitted, absf(dx) < 100.0, "near targets admit; distant targets wait")
				assert_eq(w.runner.has_target(w, key, st, origin), admitted,
					"%s facing %d, target dx %.0f" % [key, facing, dx])
				assert_eq(w.player.facing, facing, "admission checks do not turn the player")


func test_warrior_growth_is_26_hp_per_level() -> void:
	var w := _world(12)
	var hp0: int = w.player_state.max_hp
	_level_up(w)
	assert_eq(w.player_state.max_hp, hp0 + 26)


# --- data -----------------------------------------------------------------------------------------------------

func test_the_six_warrior_skills_are_defined_with_canonical_ids_and_level_counts() -> void:
	var w := _world(13)
	var want := {"power_strike": [1001004, 20], "slash_blast": [1001005, 20], "iron_body": [1001003, 20],
		"improved_hp_recovery": [1000000, 16], "improved_max_hp": [1000001, 10]}
	for key: String in want:
		assert_true(w.book.has(key), key)
		assert_eq(w.book.skill_id(key), want[key][0], key)
		assert_eq(w.book.max_rank(key), 8 if key in ["power_strike", "slash_blast"] else want[key][1], "%s canonical levels" % key)
		assert_eq(w.book.max_level(key), want[key][1], key)
	for key in ["power_strike", "slash_blast"]:
		assert_true(w.book.weapon_families(key).is_empty())
	for key in ["iron_body", "improved_hp_recovery", "improved_max_hp"]:
		assert_true(w.book.weapon_families(key).is_empty(), "%s names no weapon" % key)


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
	for key in ["power_strike", "slash_blast", "iron_body", "improved_hp_recovery", "improved_max_hp"]:
		assert_eq(book.max_rank(key), 8 if key in ["power_strike", "slash_blast"] else book.max_level(key), "%s: ranks cover every canonical level" % key)
	assert_eq(book.canonical("power_strike", 1, "damage"), 165.0)
	assert_eq(book.canonical("power_strike", 20, "damage"), 260.0)
	assert_eq(book.canonical("slash_blast", 1, "hpCon"), 8.0)
	assert_eq(book.canonical("slash_blast", 20, "mpCon"), 14.0)
	assert_eq(book.canonical("slash_blast", 16, "range"), 150.0)
	assert_eq(book.canonical("slash_blast", 1, "mobCount"), 6.0)
	assert_eq(book.canonical("iron_body", 20, "pdd"), 40.0)
	assert_eq(book.canonical("improved_hp_recovery", 16, "hp"), 50.0)
	assert_eq(book.canonical("improved_max_hp", 10, "x"), 40.0)
	library.free()


# --- Power Strike: one target inside the weapon's reach ---------------------------------------------------------

func test_power_strike_hits_the_nearest_mob_inside_the_weapon_reach_and_none_outside() -> void:
	var w := _world(21)
	w.learn_skill("power_strike")
	w.player.facing = -1
	var reach := w.weapon_reach.reach(w)
	assert_near(reach, 88.0, 0.001, "the synthetic sword afterimage reaches 88 px")
	var far := _mob(w, -150.0)
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 0, "a mob outside the swing envelope does not trigger it")
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far])
	var mid := _mob(w, -60.0)
	var near := _mob(w, -40.0)
	events = _cast(w)
	var hits := _of(events, "mob_hit")
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(hits.size(), 1, "attackCount 1 and one target")
	assert_eq(hits[0].mob, near, "the nearest mob in reach")
	assert_eq(hits[0].skill, "power_strike")
	assert_eq(w.swarm.hp[mid], w.swarm.max_hp[mid])
	assert_eq(w.swarm.hp[far], w.swarm.max_hp[far])


func test_power_strike_damage_follows_the_canonical_percent_and_the_physical_formula() -> void:
	var w := _world(22)
	w.learn_skill("power_strike")
	var st := w.loadout.stats("power_strike")
	assert_eq(st.damage_type, "physical")
	assert_near(float(st.damage_pct), 1.75, 1e-9, "rank 1 maps to level 3: 175 %")
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
	w.loadout.add_skill_mod("power_strike", "count", "add", 1)
	assert_eq(w.loadout.stats("power_strike").mob_count, 2)
	var hits := _of(_cast(w), "mob_hit")
	assert_eq(hits.map(func(e: Dictionary) -> int: return e.mob), [mobs[0], mobs[1]], "the two nearest")


# --- Slash Blast: everything around, for HP -------------------------------------------------------------------

func test_slash_blast_hits_at_most_six_mobs_within_range_on_both_sides_and_costs_hp() -> void:
	var w := _world(31)
	w.learn_skill("slash_blast")
	var st := w.loadout.stats("slash_blast")
	assert_eq(st.cast_rule, "range_around")
	assert_near(float(st.range), 132.0, 1e-9, "rank 1 canonical range")
	assert_eq(st.mob_count, 6)
	assert_eq(st.hp_cost, 9)
	var outside := _mob(w, 160.0)
	var inside: Array[int] = []
	for dx: float in [-20.0, 30.0, -50.0, 70.0, -90.0, 110.0, -120.0, 125.0]:
		inside.append(_mob(w, dx))
	w.god = false
	var hp0: int = w.player_state.hp
	var events := _cast(w)
	var hits := _of(events, "mob_hit")
	assert_eq(hits.size(), 6, "mobCount 6 caps the blast")
	assert_eq(hits.map(func(e: Dictionary) -> int: return e.mob), [inside[0], inside[1], inside[2], inside[3], inside[4], inside[5]],
		"the six nearest")
	assert_eq(hp0 - int(w.player_state.hp), 9, "canonical hpCon")
	assert_eq(w.swarm.hp[outside], w.swarm.max_hp[outside], "beyond range")
	assert_eq(w.swarm.hp[inside[7]], w.swarm.max_hp[inside[7]], "inside range but past the sixth")


func test_slash_blast_range_and_target_cards_widen_it() -> void:
	var w := _world(32)
	w.learn_skill("slash_blast")
	var edge := _mob(w, 150.0)
	assert_eq(_of(_cast(w), "cast").size(), 0, "150 px is beyond the rank-1 range")
	w.loadout.add_skill_mod("slash_blast", "area", "mul", 1.2)
	assert_near(float(w.loadout.stats("slash_blast").range), 158.4, 1e-3, "range x1.2")
	assert_eq(_of(_cast(w), "mob_hit").map(func(e: Dictionary) -> int: return e.mob), [edge])
	w.loadout.add_skill_mod("slash_blast", "count", "add", 2)
	assert_eq(w.loadout.stats("slash_blast").mob_count, 8, "+2 targets per step over the canonical 6")


func test_slash_blast_never_casts_when_its_hp_cost_would_leave_no_hp() -> void:
	var w := _world(33)
	w.learn_skill("slash_blast")
	w.god = false
	var m := _mob(w, 40.0)
	_pools(w, 9.0) # exactly the rank-1 cost: paying it would kill
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 0)
	assert_eq(w.player_state.hp, 9)
	assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
	_pools(w, 10.0)
	events = _cast(w)
	assert_eq(_of(events, "cast").size(), 1, "one HP to spare is enough")
	assert_eq(w.player_state.hp, 1)


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


func test_both_attacks_turn_toward_the_nearest_mob_in_every_movement_state() -> void:
	for state: int in [PlayerMotion.ST_WALK, PlayerMotion.ST_AIR, PlayerMotion.ST_PRONE]:
		for key in ["power_strike", "slash_blast"]:
			for side in [-1, 1]:
				var w := _world(42)
				w.learn_skill(key)
				w.player.state = state
				w.player.facing = -side
				var m := _mob(w, 50.0 * side)
				var events := _cast(w)
				var label := "%s, state %d, mob on side %d" % [key, state, side]
				assert_eq(_of(events, "cast").size(), 1, "%s casts at a mob behind it" % label)
				assert_eq(w.player.facing, side, "%s faces the mob" % label)
				assert_eq(_of(events, "cast")[0].facing, side, "%s: the cast event carries the facing" % label)
				assert_lt_hp(w, m, label)


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


# --- cards ----------------------------------------------------------------------------------------------------------


func test_core_melee_has_rarity_bonuses_instead_of_standalone_mod_cards() -> void:
	var w := _world()
	for key: String in ["power_strike", "slash_blast"]:
		assert_true(w.book.def(key).has("rarity_bonuses"))
		for card: Dictionary in w.upgrades.cards:
			assert_false(card.get("skill", "") == key and card.kind == "skill_mod")


func test_rank_cards_raise_the_level_and_preview_the_damage_percent() -> void:
	var w := _world(73)
	assert_eq(w.upgrades.apply("power_strike_new", w), 1)
	assert_eq(w.upgrades.apply("power_strike_rank", w), 1)
	assert_eq(w.loadout.rank("power_strike"), 2)
	assert_near(float(w.loadout.stats("power_strike").damage_pct), 1.85, 1e-9)
	var card := w.upgrades.choice_card("power_strike_rank", w)
	assert_has(card.skill_changes, "damage")
	assert_eq(int(card.skill_changes.damage.before), 185)


# --- reach and the bot -----------------------------------------------------------------------------------------------

func test_reach_of_reads_the_weapon_swing_and_the_slash_blast_range() -> void:
	var w := _world(81)
	w.learn_skill("power_strike")
	w.learn_skill("slash_blast")
	w.learn_skill("iron_body")
	assert_near(SkillRunner.reach_of(w.loadout.stats("power_strike"), w), 88.0, 0.001, "the weapon's swing reach")
	assert_near(SkillRunner.reach_of(w.loadout.stats("slash_blast"), w), 132.0, 1e-6, "range around the body")
	assert_eq(SkillRunner.reach_of(w.loadout.stats("iron_body"), w), 0.0, "a buff is not an attack")
	w.loadout.add_skill_mod("slash_blast", "area", "mul", 1.2)
	assert_near(SkillRunner.reach_of(w.loadout.stats("slash_blast"), w), 158.4, 1e-3)


func test_the_bot_counts_slash_blast_ready_only_while_its_hp_cost_can_be_paid() -> void:
	var w := _world(82)
	w.learn_skill("slash_blast")
	assert_near(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).x, 132.0, 1e-6, "with a sword Slash Blast is the longest attack")
	assert_near(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).y, 132.0, 1e-6, "and it is ready")
	w.god = false
	_pools(w, 9.0)
	assert_eq(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).y, 0.0, "it cannot be paid in HP: nothing is ready (no basic attack, #284)")
	_pools(w, 200.0)
	w.equipment.worn["weapon"] = {"id": 1372005}
	w.loadout.weapon_family = w.held_weapon_family()
	assert_near(BotInput._reach_profile(w, float(BotInput._engage_config(w).kite_reach)).x, 132.0, 1e-6, "a wand does not block Slash Blast (#284)")


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
	var cases := [["improved_hp_recovery", UpgradePool.PASSIVE_REGEN_HP, 3, 6], ["improved_max_hp", UpgradePool.PASSIVE_MAX_HP, 4, 8]]
	for c: Array in cases:
		w.upgrades.apply("%s_new" % c[0], w)
		var card := w.upgrades.choice_card("%s_rank" % c[0], w)
		assert_has(card.skill_changes, c[1], "%s previews under %s" % [c[0], c[1]])
		assert_eq(card.skill_changes.size(), 1, "and nothing else")
		assert_eq([int(card.skill_changes[c[1]].before), int(card.skill_changes[c[1]].after)], [c[2], c[3]])
		var lines := LevelUpWindow.change_lines(card)
		assert_eq(lines.size(), 1, "%s has one change line: %s" % [c[0], lines])


func test_the_tooltip_shows_an_hp_cost_only_for_a_skill_that_pays_one() -> void:
	var w := _world(93)
	w.learn_skill("slash_blast")
	w.learn_skill("power_strike")
	var model := SkillWindowModel.new(w.book, w.upgrades, w.loadout, w.jobs, 100, SkillText.new(w.book))
	assert_eq(model.skill_tooltip("slash_blast").hp_cost, 9)
	assert_eq(model.skill_tooltip("power_strike").hp_cost, 0)
	var lines := SkillTooltip.layout(model.skill_tooltip("slash_blast")).filter(
		func(l: Array) -> bool: return l[0] == "text").map(func(l: Array) -> String: return String(l[1]))
	assert_has(lines, "Cooldown 0.64 sec.   HP cost 9")
	lines = SkillTooltip.layout(model.skill_tooltip("power_strike")).filter(
		func(l: Array) -> bool: return l[0] == "text").map(func(l: Array) -> String: return String(l[1]))
	assert_has(lines, "Cooldown 0.4 sec.")


func test_slash_blast_text_names_its_hp_cost_range_and_targets() -> void:
	var w := _world(92)
	w.learn_skill("slash_blast")
	var text := SkillText.new(w.book)
	var line := text.level_line("slash_blast", 1, w.loadout.stats("slash_blast"))
	assert_eq(line, "HP -9; damage 72%, up to 6 monsters within 132 px")
	w.learn_skill("power_strike")
	assert_eq(text.level_line("power_strike", 20, w.loadout.stats("power_strike", 20)),
		"Damage 260%, up to 1 monster")


# --- Save & quit -> Continue (QA #164) --------------------------------------------------------------------------

func test_a_warrior_with_a_shield_keeps_job_weapon_and_shield_through_save_and_continue() -> void:
	var shield := {"reqLevel": 5, "incPDD": 5, "tuc": 7}
	var setup := RF.with_basic_attack(RF.setup("quiet", 41, RF.quiet_data()))
	setup.equipment_info[1092003] = shield
	var base := RunWorld.new(setup).character_snapshot()
	base.equipment.inventory.append(Equipment.create(1092003, shield))
	setup.character = base
	var w := RunWorld.new(setup)
	w.progression.level = 10 # the shield needs Lv5; a character has no level between rounds (#286)
	w.refresh_player_stats()
	RF.as_job(w, 100)
	assert_true(w.learn_skill("power_strike"))
	assert_eq(w.equip_item(0), "", "the shield is worn beside the sword")
	var pdd_before: int = w.player_state.pdd
	var saved := w.character_snapshot()
	assert_eq(CharacterSnapshot.validation_error(saved), "")
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(saved))
	assert_eq(CharacterSnapshot.validation_error(parsed), "")
	setup.character = parsed
	var again := RunWorld.new(setup)
	assert_eq(again.progression.job_id, 100, "Continue keeps the Warrior")
	assert_eq(again.weapon_id(), 1302077, "and the granted sword")
	assert_eq(again.held_weapon_family(), "sword")
	assert_eq(int(again.equipment.worn.shield.id), 1092003, "and the shield")
	assert_eq(again.player_state.pdd, pdd_before, "the shield still counts")
	assert_false(again.loadout.has("power_strike"), "skills are not saved: a new round starts from the job's own")
	assert_eq(again.character_snapshot(), saved, "a second save changes nothing")
