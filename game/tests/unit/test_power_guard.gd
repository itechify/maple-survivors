extends TestCase
## Warrior second job: Rage and Power Guard (spec #165 ticket #182, docs/GAME_DESIGN.md 7.10). Rage is a W.Att buff with
## a WDEF penalty (the WZ pdd is already negative); Power Guard reflects x% of CONTACT damage back at the touching
## monster (half against bosses, at most 10% of its Max HP) and takes the same amount off the damage the character
## receives. The 110/120 skill books are synthetic (level tables of the v83 shapes), the survivor data is the real
## data; one test pins the real Skill.wz values and SKIPs without the asset cache. Seeded, fixed ticks.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100 # Max HP 250, PAD 82, PDD 12, ACC 0 (no avoid roll)
const BOSS := 2220000 # Max HP 2000, PAD 90, canonical boss


## Rage 1101006 (20 levels) and Power Guard 1101007 / 1201007 (30 levels) in the Skill.wz shapes of the notes:
## Rage pad 3,3,4,4..12,12 with pdd the same number negative, time 46 + 6 (lv - 1), mpCon 12 / 20; Power Guard
## x = 10 + lv, time = 3 lv, mpCon 15 / 30.
func _books() -> Dictionary:
	var rage := {}
	for lv in range(1, 21):
		var pad := 3 + (lv - 1) / 2
		rage[str(lv)] = {"hs": "h%d" % lv, "mpCon": 12 if lv <= 10 else 20, "time": 46 + 6 * (lv - 1),
			"pad": pad, "pdd": -pad}
	var guard := {}
	for lv in range(1, 31):
		guard[str(lv)] = {"hs": "h%d" % lv, "mpCon": 15 if lv <= 15 else 30, "x": 10 + lv, "time": 3 * lv}
	var icon := {"$canvas": [0, 0, 0, 32, 32], "origin": {"$v": [0, 32]}, "z": 0}
	return {
		"110": {"skill": {
			"1101006": {"icon": icon, "action": {"0": "alert2"}, "level": rage},
			"1101007": {"icon": icon, "action": {"0": "alert2"}, "level": guard}}},
		"120": {"skill": {"1201007": {"icon": icon, "action": {"0": "alert2"}, "level": guard}}},
	}


## A non-god Fighter (110) or Page (120) on the synthetic map, wearing the creation sword.
func _world(seed_value := 182, job := 110, mutate: Callable = Callable()) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.magnet_radius = 0
	if mutate.is_valid():
		mutate.call(data)
	var setup := RF.with_basic_attack(RF.setup("quiet", seed_value, data))
	var books := _books()
	for book: String in books:
		setup.skill_imgs[book] = books[book]
	var w := RunWorld.new(setup)
	for mk: MobKind in w.mob_kinds:
		mk.move_speed = 0.0
	w.change_job(job)
	RF.place_player(w, 400)
	w.player_avoid = 0.0
	w.drain_events()
	return w


## Learns `key` at `rank` and steps once so the auto-cast buff starts.
func _cast_buff(w: RunWorld, key: String, rank: int) -> void:
	assert_true(w.learn_skill(key), "%s learned" % key)
	w.loadout.set_rank(key, rank)
	w.step(DT, MoveInput.new())
	assert_true(w.buffs.has(key), "%s is active" % key)
	w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


## One contact hit of the attack `attack` from mob `m`, with the combat stream reseeded so two worlds roll the same.
func _touch_hit(w: RunWorld, m: int, attack := 82.0, kind := "touch") -> int:
	w.rng.seed = 5
	w.upkeep.invincible_t = 0.0
	var src := Vector2(w.swarm.x[m], w.swarm.y[m])
	return w.take_hit(attack, false, "", src, {"mob": m, "mob_id": w.swarm.mob_kind(m).id, "source_kind": kind})


## The card's requires.jobs as ints (JSON parses numbers as floats).
func _jobs(card: Dictionary) -> Array:
	return card.requires.jobs.map(func(j: Variant) -> int: return int(j))


func _mob(w: RunWorld, id := MOB, dx := 30.0) -> int:
	return RF.put_mob(w, id, w.player.pos.x + dx, 190.0)


# --- Rage ----------------------------------------------------------------------------------------------------------------

func test_rage_raises_damage_and_lowers_defence_while_active_then_recasts_on_expiry() -> void:
	var w := _world()
	var watk0 := w.weapon_attack()
	var pdd0: float = w.hit_defense().pdd
	var bounds0: Vector2 = CombatMath.physical_damage_range(w.loadout.str_stat, w.loadout.dex_stat,
		w.loadout.luk_stat, w.loadout.watk, 1302077, "swingO1", 0, w.loadout.mastery)
	assert_true(w.learn_skill("rage"))
	w.loadout.set_rank("rage", 3)
	w.step(DT, MoveInput.new())
	assert_true(w.buffs.has("rage"), "auto-cast")
	assert_eq(w.weapon_attack(), watk0 + 4.0, "rank 3: pad +4")
	assert_eq(w.hit_defense().pdd, pdd0 - 4.0, "the WZ pdd is already negative: WDEF -4, not +4")
	var bounds1: Vector2 = CombatMath.physical_damage_range(w.loadout.str_stat, w.loadout.dex_stat,
		w.loadout.luk_stat, w.loadout.watk, 1302077, "swingO1", 0, w.loadout.mastery)
	assert_true(bounds1.y > bounds0.y, "the damage bounds rise")
	assert_eq(w.buffs.active.rage.duration, 58.0, "rank 3 lasts 58 s")
	w.drain_events()
	var casts := 1
	var expired := false
	for tick in int(60.0 * 60.0):
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			casts += 1 if e.type == "buff_cast" and e.skill == "rage" else 0
			expired = expired or (e.type == "buff_expired" and e.skill == "rage")
	assert_true(expired, "it ran out")
	assert_eq(casts, 2, "and was recast on expiry")
	assert_true(w.buffs.has("rage"))
	assert_eq(w.weapon_attack(), watk0 + 4.0, "the recast restores the effects")


func test_rage_works_with_any_held_weapon_and_both_effects_end_with_it() -> void:
	var w := _world()
	assert_true(w.learn_skill("rage"))
	var pdd0: float = w.hit_defense().pdd
	w.step(DT, MoveInput.new())
	w.buffs.active.rage.remaining = DT * 0.5
	w.loadout.set_rank("rage", 20) # the running cooldown (46 s) keeps it from recasting right away
	w.step(DT, MoveInput.new())
	assert_false(w.buffs.has("rage"))
	assert_eq(w.hit_defense().pdd, pdd0, "the WDEF penalty goes with the buff")


# --- Power Guard: the reflect ------------------------------------------------------------------------------------------

func test_contact_damage_is_reduced_by_x_percent_and_the_mob_takes_the_same_amount() -> void:
	var control := _world()
	var full := _touch_hit(control, _mob(control))
	assert_between(full, 40, 90, "the unguarded hit")
	var w := _world()
	_cast_buff(w, "power_guard_fighter", 1) # x = 11
	var m := _mob(w)
	var hp_before: int = w.swarm.hp[m]
	var taken := _touch_hit(w, m)
	var reflected := int(full * 11 / 100) # floor
	assert_true(reflected > 0)
	assert_eq(taken, full - reflected, "the character takes x% less")
	assert_eq(hp_before - w.swarm.hp[m], reflected, "and the mob takes exactly that")
	var events := w.drain_events()
	var hits := _of(events, "mob_hit")
	assert_eq(hits.size(), 1, "it shows as a damage number")
	assert_eq(hits[0].damage, reflected)
	assert_eq(hits[0].mob, m)
	assert_eq(hits[0].skill, "power_guard_fighter")
	assert_false(hits[0].crit)
	assert_eq(_of(events, "player_hit")[0].damage, full - reflected, "the player_hit event shows the reduced hit")
	assert_eq(w.damage_dealt, reflected, "it counts as damage dealt")


func test_the_page_branch_reflects_the_same_way() -> void:
	var control := _world(182, 120)
	var full := _touch_hit(control, _mob(control))
	var w := _world(182, 120)
	_cast_buff(w, "power_guard_page", 10) # x = 20
	var m := _mob(w)
	var taken := _touch_hit(w, m)
	assert_eq(taken, full - int(full * 20 / 100))
	assert_eq(_of(w.drain_events(), "mob_hit")[0].skill, "power_guard_page")


func test_a_boss_takes_half_the_rate() -> void:
	var control := _world()
	var full := _touch_hit(control, _mob(control, BOSS), 90.0)
	var w := _world()
	_cast_buff(w, "power_guard_fighter", 10) # x = 20: a boss gets 10%
	var m := _mob(w, BOSS)
	var hp_before: int = w.swarm.hp[m]
	var taken := _touch_hit(w, m, 90.0)
	var reflected := int(full * 10 / 100)
	assert_true(reflected > 0)
	assert_eq(taken, full - reflected)
	assert_eq(hp_before - w.swarm.hp[m], reflected)
	var ordinary := _world()
	_cast_buff(ordinary, "power_guard_fighter", 10)
	var o := _mob(ordinary, BOSS)
	ordinary.mob_kinds[ordinary.swarm.kind[o]].boss = false
	_touch_hit(ordinary, o, 90.0)
	assert_eq(_of(ordinary.drain_events(), "mob_hit")[0].damage, int(full * 20 / 100), "the full rate without boss")


func test_the_reflect_is_capped_at_ten_percent_of_the_monsters_max_hp() -> void:
	var control := _world()
	var full := _touch_hit(control, _mob(control), 600.0)
	var w := _world()
	_cast_buff(w, "power_guard_fighter", 30) # x = 40: 40% of the hit is far above 25
	var m := _mob(w)
	assert_eq(w.swarm.max_hp[m], 250)
	var taken := _touch_hit(w, m, 600.0)
	assert_true(full * 40 / 100 > 25, "the uncapped reflect would exceed the cap")
	assert_eq(250 - w.swarm.hp[m], 25, "10% of 250")
	assert_eq(taken, full - 25, "only the capped amount comes off the damage taken")


func test_a_cap_that_floors_to_zero_reflects_nothing() -> void:
	var w := _world()
	_cast_buff(w, "power_guard_fighter", 30)
	var m := RF.put_mob(w, 100100, w.player.pos.x + 30.0, 190.0) # Max HP 8: 10% = 0.8 -> 0
	var control := _world()
	var full := _touch_hit(control, RF.put_mob(control, 100100, control.player.pos.x + 30.0, 190.0), 82.0)
	assert_eq(_touch_hit(w, m, 82.0), full)
	assert_eq(w.swarm.hp[m], 8)
	assert_eq(_of(w.drain_events(), "mob_hit").size(), 0)


func test_only_contact_damage_is_reflected() -> void:
	var control := _world()
	var full := _touch_hit(control, _mob(control))
	for kind in ["mob_attack", "attack", "projectile", "other"]:
		var w := _world()
		_cast_buff(w, "power_guard_fighter", 30)
		var m := _mob(w)
		assert_eq(_touch_hit(w, m, 82.0, kind), full, "%s is not reflected" % kind)
		assert_eq(w.swarm.hp[m], w.swarm.max_hp[m])
		assert_eq(_of(w.drain_events(), "mob_hit").size(), 0)
	# Magic is not reflected either, even from a touch source.
	var w2 := _world()
	_cast_buff(w2, "power_guard_fighter", 30)
	var m2 := _mob(w2)
	w2.upkeep.invincible_t = 0.0
	w2.take_hit(82.0, true, "", Vector2(w2.swarm.x[m2], w2.swarm.y[m2]), {"mob": m2, "mob_id": MOB, "source_kind": "touch"})
	assert_eq(w2.swarm.hp[m2], w2.swarm.max_hp[m2])


func test_no_reflect_without_the_buff_a_miss_or_a_blocked_hit() -> void:
	var bare := _world()
	var m := _mob(bare)
	_touch_hit(bare, m)
	assert_eq(bare.swarm.hp[m], bare.swarm.max_hp[m], "no buff, no reflect")
	assert_eq(_of(bare.drain_events(), "mob_hit").size(), 0)
	var w := _world()
	_cast_buff(w, "power_guard_fighter", 10)
	var untouched := _mob(w)
	w.upkeep.invincible_t = 1.0 # inside the hit window the hit never lands
	w.take_hit(82.0, false, "", Vector2(w.swarm.x[untouched], w.swarm.y[untouched]),
		{"mob": untouched, "source_kind": "touch"})
	assert_eq(w.swarm.hp[untouched], w.swarm.max_hp[untouched], "a windowed hit reflects nothing")
	w.player_avoid = 100000.0
	w.upkeep.invincible_t = 0.0
	assert_eq(w.take_hit(82.0, false, "", Vector2(w.swarm.x[untouched], w.swarm.y[untouched]),
		{"mob": untouched, "accuracy": 1.0, "source_kind": "touch"}), 0)
	assert_eq(w.swarm.hp[untouched], w.swarm.max_hp[untouched], "a miss reflects nothing")


func test_the_hit_window_still_limits_it_to_one_reflect_per_window() -> void:
	var w := _world()
	_cast_buff(w, "power_guard_fighter", 10)
	var m := _mob(w)
	_touch_hit(w, m)
	var hp1: int = w.swarm.hp[m]
	w.rng.seed = 5
	w.take_hit(82.0, false, "", Vector2(w.swarm.x[m], w.swarm.y[m]), {"mob": m, "source_kind": "touch"})
	assert_eq(w.swarm.hp[m], hp1, "the second touch inside the window did nothing")


func test_a_real_touch_through_the_step_reflects_and_names_the_guard() -> void:
	var w := _world()
	assert_true(w.learn_skill("power_guard_fighter"))
	w.loadout.set_rank("power_guard_fighter", 10)
	var m := _mob(w, MOB, 0.0)
	w.mob_kinds[w.swarm.kind[m]].hitbox = Rect2(-20, -40, 40, 40)
	w.mob_kinds[w.swarm.kind[m]].body_attack = true # the synthetic Mob.wz nodes carry no bodyAttack
	var events: Array = []
	for tick in 120: # the mob first finishes its spawn stance
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
		if not _of(events, "player_hit").is_empty():
			break
	assert_true(w.buffs.has("power_guard_fighter"), "the guard was cast first")
	var taken := _of(events, "player_hit")
	var hits := _of(events, "mob_hit").filter(func(e: Dictionary) -> bool: return e.skill == "power_guard_fighter")
	assert_eq(taken.size(), 1, "the mob touched the player")
	assert_eq(taken[0].source_kind, "touch")
	assert_eq(hits.size(), 1)
	assert_eq(hits[0].skill, "power_guard_fighter")
	assert_true(w.swarm.hp[m] < w.swarm.max_hp[m])


# --- Power Guard: kills ------------------------------------------------------------------------------------------------

func test_a_mob_killed_by_the_reflect_gives_exp_and_can_drop() -> void:
	var w := _world(182, 110, func(data: Dictionary) -> void: data.balance.mesos.chance = 1.0)
	_cast_buff(w, "power_guard_fighter", 30)
	var m := _mob(w)
	w.swarm.hp[m] = 3
	_touch_hit(w, m)
	assert_eq(w.swarm.active[m], 0, "the reflect killed it")
	assert_eq(w.kills, 1)
	var events := w.drain_events()
	var died := _of(events, "mob_died")
	assert_eq(died.size(), 1)
	assert_true(int(died[0].exp) > 0, "it is worth EXP")
	var kinds := _of(events, "pickup_spawned").map(func(e: Dictionary) -> String: return String(e.kind))
	assert_true(kinds.has("exp"), "the EXP pickup was dropped: %s" % [kinds])
	assert_true(kinds.has("meso"), "and a meso drop rolled as for any kill")


func test_a_boss_kind_killed_by_the_reflect_dies_like_any_player_kill() -> void:
	# An unscheduled canonical boss (mob_boss -1) takes the ordinary kill path; scheduled-boss rewards are not exercised.
	var w := _world()
	_cast_buff(w, "power_guard_fighter", 30)
	var m := _mob(w, BOSS)
	w.swarm.hp[m] = 2
	_touch_hit(w, m, 90.0)
	assert_eq(w.swarm.active[m], 0)
	assert_eq(_of(w.drain_events(), "mob_died").size(), 1)


# --- The real data --------------------------------------------------------------------------------------------------------

func test_the_skill_and_card_data() -> void:
	var w := _world()
	for key in ["rage", "power_guard_fighter", "power_guard_page"]:
		assert_true(w.book.has(key), key)
	assert_eq(w.book.skill_id("rage"), 1101006)
	assert_eq(w.book.skill_id("power_guard_fighter"), 1101007)
	assert_eq(w.book.skill_id("power_guard_page"), 1201007)
	assert_eq(w.book.max_rank("rage"), 20)
	assert_eq(w.book.max_rank("power_guard_fighter"), 30)
	assert_eq(w.book.max_rank("power_guard_page"), 30)
	var cards: Array = w.data.upgrades.cards
	var seen := {}
	for c: Dictionary in cards:
		if String(c.get("skill", "")) in ["rage", "power_guard_fighter", "power_guard_page"]:
			seen[String(c.id)] = c
	for key in ["rage", "power_guard_fighter", "power_guard_page"]:
		assert_true(seen.has(key + "_new") and seen.has(key + "_rank"), "%s has its learn and rank cards" % key)
		assert_false(bool(seen[key + "_new"].get("power", false)), "not a power card")
	assert_eq(_jobs(seen.rage_new), [110])
	assert_eq(_jobs(seen.power_guard_fighter_new), [110])
	assert_eq(_jobs(seen.power_guard_page_new), [120])
	assert_eq(seen.power_guard_page_rank.max_rank, 30)
	assert_eq(seen.rage_rank.max_rank, 20)
	var scores: Dictionary = w.data.balance.bot.card_scores
	assert_true(scores.has("rage_new") and scores.has("rage_rank"), "Rage scores as an attack card")


func test_the_player_text_has_no_party_and_no_canonical() -> void:
	var w := _world()
	var text := SkillText.new(w.book, {})
	for key in ["rage", "power_guard_fighter", "power_guard_page"]:
		var d := text.desc(key).to_lower()
		assert_true(d != "", "%s has a description" % key)
		assert_false(d.contains("party") or d.contains("canonical"), "%s: %s" % [key, d])


func test_real_skill_wz_values() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var a := library.img("Skill.wz/110.img")
	var b := library.img("Skill.wz/120.img")
	if a == null or b == null:
		skip("the cache has no Skill.wz/110.img or 120.img (import with the Spec 165 manifest)")
		library.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"110": a.root, "120": b.root})
	assert_eq(book.canonical("rage", 1, "pad"), 3.0)
	assert_eq(book.canonical("rage", 1, "pdd"), -3.0, "the WZ pdd is negative")
	assert_eq(book.canonical("rage", 20, "pad"), 12.0)
	assert_eq(book.canonical("rage", 20, "pdd"), -12.0)
	assert_eq(book.canonical("rage", 20, "time"), 160.0)
	assert_eq(book.canonical("rage", 20, "mpCon"), 20.0)
	for key in ["power_guard_fighter", "power_guard_page"]:
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.canonical(key, 1, "x"), 11.0, key)
		assert_eq(book.canonical(key, 30, "x"), 40.0, key)
		assert_eq(book.canonical(key, 1, "time"), 3.0, key)
		assert_eq(book.canonical(key, 30, "time"), 90.0, key)
		assert_eq(book.canonical(key, 1, "mpCon"), 15.0, key)
		assert_eq(book.canonical(key, 30, "mpCon"), 30.0, key)
	# The art and sounds the data names resolve (the Page's sound names the UOL target).
	var world := _world()
	for key in ["rage", "power_guard_fighter", "power_guard_page"]:
		var def: Dictionary = world.book.def(key)
		assert_true(library.find_anim(String(def.effect)) != null, "%s effect art" % key)
		assert_true(library.sound(String(def.sounds.use)) != null, "%s sound" % key)
		assert_true(library.find(String(def.icon)) != null, "%s icon" % key)
	library.free()
