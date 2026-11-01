extends TestCase
## Shadower's Ninja Ambush (spec #425, ticket SH9 #434): a data copy of Night Lord's `ninja_ambush` (key
## `ninja_ambush_shadower`, WZ 4221004) on the merged `ground.strike` zone, with its rarity bonuses. This is the Night Lord
## test set (`test_night_lord_crowd`) re-run for the Shadower definition: the first strike at 0.3 s then every second for
## 4 / 8 / 12 s, six monsters and one ordinary hit each, `area` widens the box, `count` adds monsters, a second cast makes a
## second zone. Fixed 1/60 s ticks, seeded RNG, a dagger in hand, synthetic book-422 level tables shaped like Skill.wz. The
## real-cache tests at the end call require_cache() and SKIP without the cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const RAZOR := 1332005
const AMBUSH := "ninja_ambush_shadower"
const NIGHT_LORD_AMBUSH := "ninja_ambush"
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
const ART := "Skill.wz/422.img/skill/4221004/"


## Synthetic Skill.wz levels of Ninja Ambush (damage 62 -> 100, time 4 / 8 / 12 s, +-120 / 150 / 200 by (-130, 70), mobCount 6).
func _ambush_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var extent := 120.0 if lv <= 10 else 150.0 if lv <= 20 else 200.0
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": roundf(lerpf(62.0, 100.0, (lv - 1) / 29.0)),
			"mobCount": 6.0, "time": 4.0 if lv <= 10 else 8.0 if lv <= 20 else 12.0,
			"lt": {"$v": [-extent, -130.0]}, "rb": {"$v": [extent, 70.0]}}
	return levels


## A quiet round of a Shadower holding a Razor with Ninja Ambush learned at `rank_value`; god mode, frozen snail-sized mobs.
func _world(rank_value := 1, p_seed := 434) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["422"]["playable"] = true # in this test's data only: SH14 ships the flip
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	# A strong test Razor: hits well above the 1-point floor, so a x1.2 damage bonus shows in whole hit damage.
	setup.equipment_info.merge({RAZOR: {"incPAD": 200, "attackSpeed": 4, "tuc": 7, "afterImage": "swordOS", "sfx": "swordS"}}, true)
	for action: String in ["alert3", "swingO1", "stabO1"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.skill_imgs["422"] = {"skill": {"4221004": {"level": _ambush_levels()}}}
	setup["job"] = 422
	var w := RunWorld.new(setup)
	RF.place_player(w, 300)
	if w.weapon_id() != RAZOR:
		w.wear_new_item(RAZOR)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50)
		mk.move_speed = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill: only Ninja Ambush casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(AMBUSH), "%s is learnable by a Shadower" % AMBUSH)
	w.loadout.set_rank(AMBUSH, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190.0, 100000.0)
	w.swarm.hp[slot] = 100000000
	w.swarm.max_hp[slot] = 100000000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _hits(events: Array) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_hit" and e.skill == AMBUSH)


## Runs `ticks` ticks and returns [[time, mob_hit event]...] in order.
func _timed(w: RunWorld, ticks: int) -> Array:
	var out := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		for e: Dictionary in _hits(w.drain_events()):
			out.append([w.time, e])
	return out


func _mod(w: RunWorld, stat: String, op: String, value: float) -> void:
	w.loadout.add_skill_mod(AMBUSH, stat, op, value)


func _struck(hits: Array) -> Dictionary:
	var out := {}
	for pair: Array in hits:
		out[int(pair[1].mob)] = int(out.get(int(pair[1].mob), 0)) + 1
	return out


# --- the definition -----------------------------------------------------------------------------------------------------

func test_ninja_ambush_shadower_is_a_box_cast_that_leaves_a_strike_zone() -> void:
	var w := _world()
	var d := w.book.def(AMBUSH)
	assert_eq(int(d.skill_id), 4221004)
	assert_eq(String(d.book), "422")
	assert_eq(int(d.job), 422)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.cast.rule), "box")
	assert_eq(int(d.cast.min_targets), 1)
	assert_eq(String(d.damage), "physical")
	assert_eq(d.ground, {"strike": {"interval": 1.0, "first_delay": 0.3}})
	assert_eq(String(d.action), "alert3")
	assert_eq(String(d.icon), ART + "icon")
	assert_eq(String(d.effect), ART + "effect")
	assert_eq(String(d.hit), ART + "mob0", "the ninja that strikes each monster")
	assert_eq(String(d.ball), "")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4221004/Use")
	assert_false(d.has("knockback"))
	assert_false(d.has("weapon_families"))
	assert_false(d.has("ranks"))
	assert_near(w.loadout.stats(AMBUSH).cooldown, 14.0, 0.0001)
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)
	assert_near(float(w.runner.cooldowns[AMBUSH]), 14.0 - DT, 0.001)


func test_the_shadower_definition_is_night_lords_with_only_the_owner_data_changed() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	var mine: Dictionary = skills[AMBUSH].duplicate(true)
	var theirs: Dictionary = skills[NIGHT_LORD_AMBUSH].duplicate(true)
	for owner_key: String in ["skill_id", "book", "job", "icon", "hit", "effect", "sounds", "rarity_bonuses", "_rarity", "_provenance"]:
		mine.erase(owner_key)
		theirs.erase(owner_key)
	assert_eq(mine, theirs, "name, text, cast, cooldown, action, ground.strike and the rest are Night Lord's")
	assert_eq(skills[NIGHT_LORD_AMBUSH].ground, skills[AMBUSH].ground)
	assert_eq(int(skills[NIGHT_LORD_AMBUSH].skill_id), 4121004, "Night Lord's own entry is untouched")


func test_ninja_ambush_needs_a_monster_in_the_box() -> void:
	var w := _world()
	_mob(w, 300) # box +-120
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 0)
	_mob(w, 100)
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 1)


# --- the zone -----------------------------------------------------------------------------------------------------------

func test_the_first_strike_lands_0_3_s_after_the_cast_then_every_second() -> void:
	var w := _world()
	var m := _mob(w, 80)
	w.step(DT, MoveInput.new()) # the cast
	var cast_at := w.time
	assert_true(_hits(w.drain_events()).is_empty(), "nothing is struck on the cast tick")
	var hits := _timed(w, 330)
	assert_eq(hits.size(), 4, "4 strikes in a 4 s zone")
	var expect := [0.3, 1.3, 2.3, 3.3]
	for k in 4:
		assert_near(float(hits[k][0]) - cast_at, float(expect[k]), DT * 1.5, "strike %d" % k)
		assert_eq(int(hits[k][1].mob), m)
		assert_eq(String(hits[k][1].hit_visual), ART + "mob0", "the ninja art rides each hit")


func test_a_strike_of_the_zone_carries_the_casts_status_grants() -> void:
	# The zone's strikes are ordinary hits of the cast snapshot, so a granted status lands on a strike.
	var w := _world()
	w.loadout.status_bonuses = {"stop": {"kind": "stun", "chance": 100, "time": 1.5}}
	w.loadout.add_status_grant(AMBUSH, "stop")
	var m := _mob(w, 80)
	w.step(DT, MoveInput.new()) # the cast
	assert_near(w.swarm.status_time(m, MobSwarm.STUN), 0.0, 0.00001, "nothing is struck on the cast tick")
	w.loadout.grants.clear() # the zone keeps its snapshot
	assert_false(_timed(w, 24).is_empty(), "the first strike landed")
	assert_true(w.swarm.status_time(m, MobSwarm.STUN) > 1.0, "and stunned")


func test_the_zone_lives_four_eight_and_twelve_seconds_by_rank() -> void:
	for row: Array in [[1, 4], [4, 8], [8, 12]]:
		var w := _world(int(row[0]))
		_mob(w, 80)
		var hits := _timed(w, int(13.5 / DT))
		assert_eq(hits.size(), int(row[1]), "rank %d: %d strikes" % [int(row[0]), int(row[1])])
		assert_eq(w.runner.casts, 1, "the 14 s cooldown never lets it overlap itself")
		assert_eq(w.loadout.stats(AMBUSH).mob_count, 6)


func test_each_strike_is_one_ordinary_hit_on_the_six_nearest_to_the_anchor() -> void:
	var w := _world(8)
	var slots := []
	for k in 9:
		slots.append(_mob(w, 20.0 + 15.0 * k))
	var hits := _timed(w, 60) # the first strike only
	var struck := _struck(hits)
	assert_eq(hits.size(), 6, "mobCount 6: one hit each")
	assert_eq(struck.size(), 6)
	for k in 6:
		assert_true(struck.has(slots[k]), "the six nearest to the anchor")


func test_the_zone_is_anchored_where_the_caster_stood() -> void:
	var w := _world()
	var near := _mob(w, 80)
	w.step(DT, MoveInput.new())
	w.drain_events()
	w.player.pos.x += 900.0 # the caster walks away: the zone stays
	var far := _mob(w, 80)
	var struck := _struck(_timed(w, 100))
	assert_true(struck.has(near), "the monster inside the anchored box is struck")
	assert_false(struck.has(far), "the one beside the caster's new position is not")


func test_a_monster_that_leaves_or_dies_is_not_struck() -> void:
	var w := _world(8)
	var leaver := _mob(w, 60)
	var dier := _mob(w, 70)
	var stayer := _mob(w, 80)
	w.step(DT, MoveInput.new())
	w.drain_events()
	var first := _struck(_timed(w, 24)) # through the 0.3 s strike
	assert_eq(first.size(), 3)
	w.swarm.x[leaver] = 1700.0 # out of the 400 px box
	w.swarm.apply_hit(dier, 1.0e9, 1)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var later := _struck(_timed(w, 70)) # through the 1.3 s strike
	assert_eq(later.size(), 1, "only the monster still inside is struck")
	assert_true(later.has(stayer))


func test_ambush_squad_adds_two_monsters_and_area_widens_the_box() -> void:
	var plain := _world()
	var squad := _world()
	_mod(squad, "count", "add", 2)
	for w: RunWorld in [plain, squad]:
		for k in 9:
			_mob(w, 10.0 + 12.0 * k)
	assert_eq(squad.loadout.stats(AMBUSH).mob_count, 8)
	assert_eq(_struck(_timed(plain, 60)).size(), 6)
	assert_eq(_struck(_timed(squad, 60)).size(), 8, "two more monsters per strike")
	var narrow := _world()
	var wide := _world()
	_mod(wide, "area", "mul", 1.2)
	_mob(narrow, 60)
	_mob(wide, 60)
	var edge_narrow := _mob(narrow, 145) # the body starts at 125: past +-120, inside +-144
	var edge_wide := _mob(wide, 145)
	assert_near(wide.loadout.stats(AMBUSH).box.size.x, 288.0, 0.01)
	assert_false(_struck(_timed(narrow, 60)).has(edge_narrow))
	assert_true(_struck(_timed(wide, 60)).has(edge_wide))


func test_a_second_cast_makes_a_second_zone() -> void:
	var w := _world()
	var m := _mob(w, 80)
	w.step(DT, MoveInput.new())
	w.drain_events()
	for tick in 30:
		w.step(DT, MoveInput.new())
	w.drain_events()
	w.runner.cooldowns[AMBUSH] = 0.0 # the 14 s cooldown is a tier C lever; a second cast is what is tested
	w.step(DT, MoveInput.new())
	assert_eq(w.runner.casts, 2)
	w.drain_events()
	var hits := _timed(w, 150)
	assert_true(_struck(hits).has(m))
	# both zones are alive: over 2.5 s the monster is struck by two clocks, offset by about half a second
	assert_true(hits.size() >= 4, "two interleaved clocks, got %d" % hits.size())


func test_map_transfer_and_clear_drop_the_zones() -> void:
	var w := _world()
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	w.drain_events()
	w.runner.clear_pending(w) # what advance_map and a stage clear call
	assert_true(_timed(w, 300).is_empty(), "no strike after the zones are cleared")


func test_ambush_damage_scales_by_rank_and_with_the_damage_bonus() -> void:
	var lo := _world().loadout
	assert_true(lo.stats(AMBUSH, 8).damage_pct > lo.stats(AMBUSH, 4).damage_pct, "rank 8 over 4")
	assert_true(lo.stats(AMBUSH, 4).damage_pct > lo.stats(AMBUSH, 1).damage_pct, "rank 4 over 1")
	assert_eq(lo.stats(AMBUSH, 1).box, Rect2(-120, -130, 240, 200))
	assert_eq(lo.stats(AMBUSH, 8).box, Rect2(-200, -130, 400, 200))
	var base := _world(8)
	var strong := _world(8)
	_mod(strong, "damage", "mul", 1.2)
	var totals := []
	for w: RunWorld in [base, strong]:
		_mob(w, 80)
		var sum := 0.0
		for pair: Array in _timed(w, 60):
			sum += float(pair[1].damage)
		totals.append(sum)
	assert_true(totals[1] > totals[0], "damage x1.2: %s" % str(totals))


func test_the_skill_window_names_the_zone() -> void:
	var w := _world()
	var text := SkillText.new(w.book)
	for row: Array in [[1, 4, 4], [4, 15, 8], [8, 30, 12]]:
		var line := text.level_line(AMBUSH, int(row[1]), w.loadout.stats(AMBUSH, int(row[0])))
		assert_true(line.contains("Strikes up to 6 monsters every 1 s for %d s" % int(row[2])), line)


func test_the_zone_event_carries_no_tile_art() -> void:
	var w := _world()
	_mob(w, 80)
	w.step(DT, MoveInput.new())
	var zone := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "skill_ground")
	assert_eq(zone.size(), 1)
	assert_eq(String(zone[0].effect), "", "no tile: the effect plays once at the cast, the strikes bring their own ninjas")
	assert_eq(float(zone[0].duration), 4.0)


# --- rarity bonuses -----------------------------------------------------------------------------------------------------

const RARITY := [["shadow_shifter", "damage", "mul", 1.2], ["wide_ambush", "area", "mul", 1.2], ["ambush_squad", "count", "add", 2.0]]
const NAMES := ["Shadow Shifter", "Wide Ambush", "Ambush Squad"]


func test_the_rarity_table_follows_the_spec() -> void:
	var bonuses: Dictionary = _world().book.def(AMBUSH).rarity_bonuses
	for t in 3:
		var tier: String = ["rare", "epic", "unique"][t]
		assert_eq(bonuses[tier].size(), 1, tier)
		assert_eq(String(bonuses[tier][0].id), String(RARITY[t][0]), tier)
		assert_eq(String(bonuses[tier][0].text), String(NAMES[t]), tier)
		assert_eq(bonuses[tier][0].effects.size(), 1)
		var effect: Dictionary = bonuses[tier][0].effects[0]
		assert_eq(String(effect.stat), String(RARITY[t][1]))
		assert_eq(String(effect.op), String(RARITY[t][2]))
		assert_near(float(effect.value), float(RARITY[t][3]), 0.0001)
	var legendary: Dictionary = bonuses.legendary[0]
	assert_eq(String(legendary.id), "ambush_squad", "Legendary shares the Unique's id (and its repeat counter)")
	assert_eq(legendary.effects.size(), 2)
	assert_eq(String(legendary.effects[0].stat), "count")
	assert_near(float(legendary.effects[0].value), 2.0, 0.0001)
	assert_eq(String(legendary.effects[1].stat), "damage")
	assert_near(float(legendary.effects[1].value), 1.2, 0.0001)
	assert_eq(bonuses.keys().size(), 4, "exactly the four tiers")


## What a cast did in the field below: the total damage, the hit lines, the monsters struck and whether the edge monster (just
## beyond the base box) was struck; `effects` are applied as skill modifiers first.
func _probe(effects: Array) -> Dictionary:
	var w := _world(8)
	for effect: Dictionary in effects:
		_mod(w, String(effect.stat), String(effect.op), float(effect.value))
	# Three monsters well inside the box (the cap of six would otherwise crowd the edge one out), ten when `count` is probed.
	var crowd := 10 if effects.any(func(e: Dictionary) -> bool: return String(e.stat) == "count") else 3
	for k in crowd:
		_mob(w, 10.0 + 10.0 * k)
	var edge := _mob(w, 225.0) # rank 8 reaches +-200: the body starts at 205, outside the base box and inside x1.2
	var hits := _timed(w, 64)
	var dealt := 0.0
	for pair: Array in hits:
		dealt += float(pair[1].damage)
	var struck := _struck(hits)
	return {"dealt": dealt, "lines": hits.size(), "mobs": struck.size(), "edge": struck.has(edge)}


func test_every_bonus_changes_the_resolved_cast() -> void:
	var bonuses: Dictionary = _world().book.def(AMBUSH).rarity_bonuses
	var base := _probe([])
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		for effect: Dictionary in bonuses[tier][0].effects:
			var with_effect := _probe([effect])
			var label := "%s %s" % [tier, String(effect.stat)]
			match String(effect.stat):
				"damage":
					assert_true(float(with_effect.dealt) > float(base.dealt), label)
				"area":
					assert_false(bool(base.edge), label + ": the edge monster is outside the base box")
					assert_true(bool(with_effect.edge), label)
				"count":
					assert_true(int(with_effect.mobs) > int(base.mobs), label)
				_:
					assert_true(false, label + ": unprobed stat")


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		var w := _world()
		var card := w.upgrades.choice_card(AMBUSH + "_rank", w, tier)
		assert_false(card.get("rarity_bonus", {}).is_empty(), "%s carries a bonus" % tier)
		w.upgrades.apply(AMBUSH + "_rank", w, tier)
		assert_eq(w.loadout.rank(AMBUSH), 2, "%s: one rank, whatever the rarity" % tier)
		var st := w.loadout.stats(AMBUSH)
		match tier:
			"rare":
				assert_near(w.loadout.skill_stat(AMBUSH, "damage", 1.0), 1.2, 0.0001)
			"epic":
				assert_near(st.area, 1.2, 0.0001)
			"unique", "legendary":
				assert_eq(st.mob_count, 8)
				assert_near(w.loadout.skill_stat(AMBUSH, "damage", 1.0), 1.2 if tier == "legendary" else 1.0, 0.0001)


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	var w := _world()
	w.upgrades.apply(AMBUSH + "_rank", w, "unique")
	w.upgrades.apply(AMBUSH + "_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:ambush_squad" % AMBUSH]), 2, "one shared counter")
	var m := _world()
	m.loadout.set_rank(AMBUSH, 8)
	var c := m.upgrades.choice_card(AMBUSH + "_rank", m, "rare")
	assert_eq(c.card_kind, "mastery", "at rank 8 the rank card is a Mastery card")
	m.upgrades.apply(AMBUSH + "_rank", m, "rare")
	m.upgrades.apply(AMBUSH + "_rank", m, "rare")
	assert_near(m.loadout.skill_stat(AMBUSH, "damage", 1.0), 1.2 * (1.0 + 0.2 * 0.8), 0.00001, "the repeat is x0.8")
	assert_eq(m.loadout.rank(AMBUSH), 8)


func test_night_lords_ambush_is_unchanged_by_the_copy() -> void:
	var bonuses: Dictionary = DataRepo.load_all().skills.skills[NIGHT_LORD_AMBUSH].rarity_bonuses
	assert_eq(String(bonuses.rare[0].id), "ninja_arts", "Night Lord keeps Ninja Arts, not Shadow Shifter")
	assert_eq(String(bonuses.epic[0].id), "wide_ambush")
	assert_eq(String(bonuses.unique[0].id), "ambush_squad")


# --- real cache: the two definitions against Skill.wz and the Use sound ---------------------------------------------------

func test_real_cache_the_two_definitions_resolve_equal_numbers_at_every_rank() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var img_412 := lib.img("Skill.wz/412.img")
	var img_422 := lib.img("Skill.wz/422.img")
	assert_true(img_412 != null and img_422 != null, "Skill.wz/412.img and 422.img are in the cache")
	if img_412 == null or img_422 == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"412": img_412.root, "422": img_422.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "dagger"
	var mine: Dictionary = img_422.root.skill["4221004"]
	var theirs: Dictionary = img_412.root.skill["4121004"]
	assert_eq(mine.level, theirs.level, "all 30 levels of 4221004 equal 4121004 field for field")
	assert_eq(book.max_level(AMBUSH), 30)
	assert_eq(book.max_rank(AMBUSH), 8)
	for rank_value in range(1, 9):
		var lv: int = LEVELS[rank_value - 1]
		var label := "rank %d (level %d)" % [rank_value, lv]
		assert_eq(book.canonical_level(AMBUSH, rank_value), book.canonical_level(NIGHT_LORD_AMBUSH, rank_value), label)
		assert_eq(book.canonical_level(AMBUSH, rank_value), lv, label)
		var a := lo.stats(AMBUSH, rank_value)
		var b := lo.stats(NIGHT_LORD_AMBUSH, rank_value)
		for field: String in ["level", "damage_pct", "box", "mob_count", "attack_count", "cooldown", "area"]:
			assert_eq(a[field], b[field], "%s: %s" % [label, field])
		assert_eq(book.canonical(AMBUSH, lv, "time"), book.canonical(NIGHT_LORD_AMBUSH, lv, "time"), label)
		var level: Dictionary = mine.level[str(lv)]
		assert_near(a.damage_pct, float(level.damage) / 100.0, 0.000001, label)
		assert_eq(a.mob_count, 6, label)
	# The spec's worked rank values (rank 1 / 4 / 8) as literals.
	for i in 3:
		var r: int = [1, 4, 8][i]
		assert_near(lo.stats(AMBUSH, r).damage_pct, [0.68, 0.85, 1.00][i], 0.000001, "damage rank %d" % r)
		assert_eq(lo.stats(AMBUSH, r).box.size.x, [240.0, 300.0, 400.0][i], "box rank %d" % r)
		assert_eq(book.canonical(AMBUSH, int(LEVELS[[0, 3, 7][i]]), "time"), [4.0, 8.0, 12.0][i], "zone life rank %d" % r)
	# The art resolves in the cache.
	var d := book.def(AMBUSH)
	for path: String in [d.effect, d.hit]:
		assert_true(lib.anim(path).frames.size() > 0, path)
	assert_eq(lib.anim(String(d.effect)).frames.size(), 19)
	assert_eq(lib.anim(String(d.hit)).frames.size(), 13)
	lib.free()


func test_real_cache_the_use_sound_resolves_through_the_uol() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var path := String(DataRepo.load_all().skills.skills[AMBUSH].sounds.use)
	assert_eq(path, "Sound.wz/Skill.img/4221004/Use")
	var stream := lib.sound(path)
	assert_true(stream != null, "the Use sound plays")
	assert_eq(String(lib.find(path)["$sound"]), "Sound.wz/Skill.img/4121004/Use.mp3", "exported under the UOL target's file")
	var night_lords := lib.sound("Sound.wz/Skill.img/4121004/Use")
	assert_true(night_lords != null)
	if stream != null and night_lords != null:
		assert_eq(stream.get_length(), night_lords.get_length(), "the same file as Night Lord's")
	assert_true(lib.missing.is_empty(), str(lib.missing))
	lib.free()
