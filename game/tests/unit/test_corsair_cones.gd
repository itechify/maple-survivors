extends TestCase
## Corsair's two cones (spec #384, ticket C9 #393): Flamethrower (5211004, burn with a literal pulse) and Ice Splitter
## (5211005, freeze) on the `corsair` line, GAME_DESIGN 7.120.5. Seeded synthetic worlds with fixed ticks (a flat floor, tiny
## mob bodies that never move); the 521 book is a synthetic one whose `damage` is a STRING at every level, like the WZ's.
## Tests marked "real cache" call require_cache() and SKIP without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const GROUND := {"x1": 0, "y1": 0, "x2": 1000, "y2": 0}
const UPPER := {"x1": 0, "y1": -150, "x2": 1000, "y2": -150}
const PISTOL := 1492000
const KEYS := ["flamethrower", "ice_splitter"]
const TIERS := ["rare", "epic", "unique", "legendary"]
const IDS := {"flamethrower": 5211004, "ice_splitter": 5211005}
## The eight mapped WZ levels (rank_levels "30").
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]


## 521.img with the two cones: damage a STRING (82 -> 160 and 78 -> 130 like the WZ), mobCount 2 -> 6, time 3 -> 5 (burn) and
## 1 -> 3 (freeze), the front-only box lt (-350,-100) rb (0,0), elemAttr and the art nodes.
func _book() -> Dictionary:
	var skills := {}
	for key: String in KEYS:
		var levels := {}
		var fire: bool = key == "flamethrower"
		for lv in range(1, 31):
			var t := clampf(float(lv - 4) / 26.0, 0.0, 1.0)
			levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 25, "itemConsume": 2331000 if fire else 2331001,
				"damage": str(roundi((82.0 if fire else 78.0) + t * (78.0 if fire else 52.0))),
				"mobCount": 2 + roundi(t * 4.0), "time": (3 + roundi(t * 2.0)) if fire else (1 + roundi(t * 2.0)),
				"lt": {"$v": [-350, -100]}, "rb": {"$v": [0, 0]}}
		skills[str(IDS[key])] = {"weapon": 49, "elemAttr": "f" if fire else "i", "icon": RF._canvas(32, 32),
			"action": {"0": "fireburner" if fire else "coolingeffect"}, "level": levels,
			"effect": RF._anim(15 if fire else 13, 90.0, 60, 60), "effect_ship": RF._anim(15 if fire else 13, 90.0, 60, 60),
			"hit": {"0": RF._anim(5, 90.0, 40, 40)}}
	return {"skill": skills}


## A Corsair (job 522) on a flat floor at `x`, mob bodies 4 x 10 px and standing still, `key` the only skill, at `rank_value`.
## `playable` is flipped in this world's data only (C14 ships the real flip) so the pool's cards exist.
func _corsair(key: String, rank_value := 1, segments: Array = [GROUND], x := 400.0, p_seed := 393) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["522"]["playable"] = true
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7}}, true)
	setup.map_img = RF.map_from_segments(segments)
	setup.skill_imgs["521"] = _book()
	setup["job"] = 522
	var w := RunWorld.new(setup)
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0.0
		mk.pdd = 0
	w.player.place(Vector2(x, 0), w.fhm)
	w.update_view()
	w.player.facing = 1
	w.god = true
	w.loadout.ranks.clear() # not the start skill (Double Shot): only `key` casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(key), "%s is learnable by a Corsair" % key)
	w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, y := -5.0, hp := 100000.0) -> int:
	return RF.put_mob(w, MOB, w.player.pos.x + dx, y, hp)


func _tick(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


## Plays `ticks` world ticks; every event of them.
func _play(w: RunWorld, ticks: int) -> Array:
	var events := []
	for tick in ticks:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	return events


func _of(events: Array, type: String, skill := "") -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type and (skill == "" or e.skill == skill))


func _hit_slots(events: Array, skill: String) -> Array:
	return _of(events, "mob_hit", skill).map(func(e: Dictionary) -> int: return int(e.mob))


func _damage(events: Array, skill: String) -> float:
	var total := 0.0
	for e: Dictionary in _of(events, "mob_hit", skill):
		total += float(e.damage)
	return total


func _boss(w: RunWorld, slot: int) -> void:
	w.mob_boss[slot] = 0
	w.swarm.steady[slot] = 1


# --- the definitions ----------------------------------------------------------------------------------------------------

func test_the_two_cones_are_defined_in_the_corsair_line_only_with_the_default_thirty_level_ranks() -> void:
	var data := DataRepo.load_all()
	var corsair: Dictionary = data.skills.skills
	for key: String in KEYS:
		assert_true(corsair.has(key), key + " is defined")
		var d: Dictionary = corsair[key]
		assert_eq(int(d.skill_id), IDS[key])
		assert_eq(String(d.book), "521")
		assert_eq(String(d.damage), "physical")
		assert_eq(String(d.cast.rule), "box")
		assert_eq(float(d.cooldown), 2.5)
		assert_false(d.has("ranks"), "the default eight ranks of a 30-level skill")
		assert_false(d.has("weapon_families"), "a weapon gates nothing")
		assert_eq(d.get("ball", "x"), "", "no ball")
		assert_eq(String(d.effect), "Skill.wz/521.img/skill/%d/effect" % IDS[key])
		assert_eq(String(d.effect_ship), "Skill.wz/521.img/skill/%d/effect_ship" % IDS[key], "declared for the ship's art_variant")
	assert_eq(String(corsair.flamethrower.action), "fireburner")
	assert_eq(String(corsair.ice_splitter.action), "coolingeffect")
	for other: String in ["pirate", "bowmaster", "il_arch_mage"]:
		var file := FileAccess.open("res://data/survivor/skills/%s.json" % other, FileAccess.READ)
		var text := file.get_as_text() if file != null else ""
		assert_false(text.contains("\"flamethrower\"") or text.contains("\"ice_splitter\""), other + ".json does not define them")
	assert_eq(data.skills.rank_levels["30"].map(func(v: Variant) -> int: return int(v)), LEVELS, "rank_levels 30 is the table both use")


func test_burn_and_freeze_blocks_name_the_literal_pulse_and_the_wz_time() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	assert_eq(skills.flamethrower.on_hit, {"status": "burn", "duration_field": "time", "pulse": 30.0})
	assert_eq(skills.ice_splitter.on_hit, {"status": "freeze", "duration_field": "time"})
	assert_false(skills.ice_splitter.on_hit.has("chance_field"), "no prop: every damaging hit attempts the freeze")


# --- the string damage --------------------------------------------------------------------------------------------------

func test_the_string_damage_resolves_to_the_numeric_percent_and_no_other_parsing_changes() -> void:
	for key: String in KEYS:
		var w := _corsair(key)
		var node: Dictionary = w.book.skill_node(key)
		for rank_value in range(1, 9):
			var lv: int = LEVELS[rank_value - 1]
			var level: Dictionary = node.level[str(lv)]
			assert_true(level.damage is String, "the WZ stores damage as a string")
			var st := w.loadout.stats(key, rank_value)
			assert_eq(int(st.level), lv)
			assert_near(st.damage_pct, float(int(level.damage)) / 100.0, 1e-9, "%s rank %d damage_pct" % [key, rank_value])
			assert_eq(w.book.canonical(key, lv, "damage"), float(int(level.damage)))
			assert_near(float(st.damage_pct), float(level.damage) / 100.0, 1e-9)
		assert_eq(w.book.canonical(key, 4, "mobCount"), 2.0, "an int field still parses")
		assert_eq(w.book.canonical(key, 4, "nothing", 7.0), 7.0, "a missing field keeps its default")
	var other := _corsair("flamethrower")
	other.book.skill_node("flamethrower").level["4"]["junk"] = "abc"
	assert_eq(other.book.canonical("flamethrower", 4, "junk", 3.0), 3.0, "a non-numeric string is still the default")


# --- Flamethrower: the front cone, the burn -------------------------------------------------------------------------------

func test_flamethrower_hits_only_in_front_inside_the_box_and_up_to_mob_count() -> void:
	var w := _corsair("flamethrower", 1, [GROUND, UPPER])
	var near := _mob(w, 60.0)
	var edge := _mob(w, 340.0)
	var behind := _mob(w, -60.0)
	var beyond := _mob(w, 360.0)
	var above := _mob(w, 100.0, -155.0)
	var hits := _hit_slots(_tick(w), "flamethrower")
	assert_eq(hits.size(), 2, "rank 1: two monsters")
	assert_has(hits, near)
	assert_has(hits, edge)
	assert_false(behind in hits, "never behind")
	assert_false(beyond in hits, "beyond 350 px")
	assert_false(above in hits, "100 px tall box")
	assert_eq(w.loadout.stats("flamethrower").box, Rect2(-350, -100, 350, 100), "the canonical front-only box")
	var left := _corsair("flamethrower")
	left.player.facing = -1
	var l_front := _mob(left, -200.0)
	var l_behind := _mob(left, 200.0)
	var l_hits := _hit_slots(_tick(left), "flamethrower")
	assert_eq(l_hits, [l_front], "facing left the cone is on the left")
	assert_false(l_behind in l_hits)
	var none := _corsair("flamethrower")
	_mob(none, -100.0)
	_mob(none, 400.0)
	assert_eq(_of(_tick(none), "cast").size(), 0, "nothing in the cone: no cast")


func test_flamethrower_burns_every_struck_monster_for_the_wz_time_with_the_literal_pulse() -> void:
	var w := _corsair("flamethrower")
	var a := _mob(w, 60.0)
	var b := _mob(w, 120.0)
	var far := _mob(w, 600.0)
	var st := w.loadout.stats("flamethrower")
	assert_eq(int(st.burn_pulse), BurnStatus.pulse(float(st.damage_min), float(st.damage_max), 30.0, 1.0), "30% of the cast's mean per second")
	assert_eq(float(st.burn_time), 3.0, "rank 1: the WZ time")
	assert_near(float(st.burn_share), 30.0, 1e-9)
	var events := _tick(w)
	assert_eq(_hit_slots(events, "flamethrower").size(), 2)
	for slot: int in [a, b]:
		assert_near(w.swarm.status_time(slot, MobSwarm.BURN), 3.0, 0.05, "burning for the WZ time")
	assert_eq(w.swarm.status_time(far, MobSwarm.BURN), 0.0, "an unstruck monster does not burn")
	var pulses := _of(_play(w, 61), "mob_hit", "flamethrower").filter(func(e: Dictionary) -> bool: return int(e.damage) == int(st.burn_pulse))
	assert_eq(pulses.size(), 2, "one pulse a second on each of the two")
	assert_true(w.swarm.burn_dealt > 0)
	var top := _corsair("flamethrower", 8)
	assert_eq(float(top.loadout.stats("flamethrower").burn_time), 5.0, "rank 8: five seconds")


func test_burn_damage_scales_the_pulse_and_the_cast_alone_is_unchanged() -> void:
	var w := _corsair("flamethrower", 4)
	var before := w.loadout.stats("flamethrower")
	w.loadout.add_skill_mod("flamethrower", "burn_damage", "mul", 1.5)
	var after := w.loadout.stats("flamethrower")
	assert_eq(int(after.burn_pulse), BurnStatus.pulse(float(before.damage_min), float(before.damage_max), 30.0, 1.5))
	assert_near(float(after.burn_share), 45.0, 1e-9)
	assert_eq(float(after.damage_max), float(before.damage_max), "the direct hit is not scaled")
	assert_eq(float(after.burn_time), float(before.burn_time))


func test_bosses_and_fire_immune_monsters_do_not_burn_but_are_hit() -> void:
	var w := _corsair("flamethrower")
	var boss := _mob(w, 60.0)
	_boss(w, boss)
	var immune := _mob(w, 120.0)
	w.swarm.mob_kind(immune).element_codes = {"F": "1"}
	w.swarm.mob_kind(immune).elements = {"F": 0.0}
	var events := _tick(w)
	assert_has(_hit_slots(events, "flamethrower"), boss)
	assert_eq(w.swarm.status_time(boss, MobSwarm.BURN), 0.0, "a boss rejects burn")
	assert_eq(w.swarm.status_time(immune, MobSwarm.BURN), 0.0, "a fire-immune monster rejects burn")


func test_flamethrower_is_fire_a_fire_weak_monster_takes_one_and_a_half() -> void:
	var plain := _corsair("flamethrower", 2)
	var weak := _corsair("flamethrower", 2)
	for w: RunWorld in [plain, weak]:
		w.loadout.add_skill_mod(w.loadout.order[0], "damage", "mul", 40.0) # big integers: the x1.5 shows through rounding
		w.refresh_player_stats()
		_mob(w, 100.0)
	weak.swarm.mob_kind(0).elements = {"F": 1.5}
	weak.swarm.mob_kind(0).element_codes = {"F": "3"}
	assert_eq(String(plain.loadout.stats("flamethrower").element), "f")
	var base := _damage(_tick(plain), "flamethrower")
	var more := _damage(_tick(weak), "flamethrower")
	assert_true(base > 0.0)
	assert_near(more / base, 1.5, 0.05, "fire-weak takes x1.5 (%f vs %f)" % [more, base])


func test_flamethrower_count_bonus_widens_the_cone_by_two_monsters_and_mob_count_is_wz() -> void:
	for pair: Array in [[1, 2], [4, 4], [8, 6]]:
		var w := _corsair("flamethrower", int(pair[0]))
		assert_eq(int(w.loadout.stats("flamethrower").mob_count), int(pair[1]), "rank %d mobCount" % int(pair[0]))
	var w := _corsair("flamethrower")
	w.loadout.add_skill_mod("flamethrower", "count", "add", 2)
	for i in 6:
		_mob(w, 40.0 + 40.0 * i)
	assert_eq(_hit_slots(_tick(w), "flamethrower").size(), 4, "Wide Flame: 2 + 2")


# --- Ice Splitter: the freeze ---------------------------------------------------------------------------------------------

func test_ice_splitter_freezes_the_struck_monsters_for_the_wz_time_in_the_same_cone() -> void:
	var w := _corsair("ice_splitter")
	var a := _mob(w, 80.0)
	var b := _mob(w, 300.0)
	var behind := _mob(w, -80.0)
	var beyond := _mob(w, 380.0)
	var st := w.loadout.stats("ice_splitter")
	assert_eq(st.box, Rect2(-350, -100, 350, 100), "the canonical front-only box")
	assert_eq(String(st.element), "i")
	var hits := _hit_slots(_tick(w), "ice_splitter")
	assert_eq(hits.size(), 2)
	assert_false(behind in hits or beyond in hits)
	for slot: int in [a, b]:
		assert_near(w.swarm.status_time(slot, MobSwarm.FREEZE), 1.0, 0.05, "rank 1: one second")
	assert_eq(w.swarm.status_time(behind, MobSwarm.FREEZE), 0.0)
	var top := _corsair("ice_splitter", 8)
	var s := _mob(top, 100.0)
	_tick(top)
	assert_near(top.swarm.status_time(s, MobSwarm.FREEZE), 3.0, 0.05, "rank 8: three seconds")


func test_ice_splitter_bosses_and_ice_immune_monsters_reject_the_freeze() -> void:
	var w := _corsair("ice_splitter")
	var boss := _mob(w, 60.0)
	_boss(w, boss)
	var immune := _mob(w, 120.0)
	w.swarm.mob_kind(immune).element_codes = {"I": "1"}
	w.swarm.mob_kind(immune).elements = {"I": 0.0}
	var events := _tick(w)
	assert_has(_hit_slots(events, "ice_splitter"), boss, "the boss is hit")
	assert_eq(w.swarm.status_time(boss, MobSwarm.FREEZE), 0.0, "a boss rejects the freeze")
	assert_eq(w.swarm.status_time(immune, MobSwarm.FREEZE), 0.0, "an ice-immune monster rejects it")


func test_ice_splitter_is_ice_a_fire_based_monster_takes_one_and_a_half() -> void:
	var plain := _corsair("ice_splitter", 2)
	var weak := _corsair("ice_splitter", 2)
	for w: RunWorld in [plain, weak]:
		w.loadout.add_skill_mod(w.loadout.order[0], "damage", "mul", 40.0) # big integers: the x1.5 shows through rounding
		w.refresh_player_stats()
		_mob(w, 100.0)
	weak.swarm.mob_kind(0).elements = {"I": 1.5}
	weak.swarm.mob_kind(0).element_codes = {"I": "3"}
	var base := _damage(_tick(plain), "ice_splitter")
	var more := _damage(_tick(weak), "ice_splitter")
	assert_true(base > 0.0)
	assert_near(more / base, 1.5, 0.05, "x1.5 (%f vs %f)" % [more, base])


# --- the ship's art ------------------------------------------------------------------------------------------------------

func test_the_ships_art_variant_swaps_effect_for_effect_ship_on_both_cones_only() -> void:
	var w := _corsair("flamethrower")
	var states: Array[Dictionary] = [{"effects": {"art_variant": {"effect": "effect_ship"}}}]
	for key: String in KEYS:
		var st := w.loadout.stats(key, 1)
		st["level"] = 4
		var swapped := FormRules.art_variant(states, w, key, st)
		assert_eq(String(swapped.effect), "Skill.wz/521.img/skill/%d/effect_ship" % IDS[key], key)
	var plain := {"level": 3, "effect": "kept"}
	assert_true(is_same(plain, FormRules.art_variant(states, w, "double_shot", plain)), "a skill without effect_ship keeps its art")


# --- rarity bonuses ------------------------------------------------------------------------------------------------------

## key -> [id, text, effects] for rare, epic, unique (Legendary = the Unique's plus damage x1.2).
const BONUSES := {
	"flamethrower": [["elemental_boost", "Elemental Boost", [["damage", "mul", 1.2]]],
		["scorch", "Scorch", [["burn_damage", "mul", 1.5]]], ["wide_flame", "Wide Flame", [["count", "add", 2.0]]]],
	"ice_splitter": [["elemental_boost", "Elemental Boost", [["damage", "mul", 1.2]]],
		["booster", "Gun Booster", [["cooldown", "mul", 0.88]]], ["wide_ice", "Wide Ice", [["count", "add", 2.0]]]],
}
## The resolved stat each effect moves, as the cast reads it.
const RESOLVED := {"damage": "damage_max", "cooldown": "cooldown", "count": "mob_count", "burn_damage": "burn_pulse"}


func _effects(entry: Dictionary) -> Array:
	return entry.effects.map(func(e: Dictionary) -> Array: return [String(e.stat), String(e.op), float(e.value)])


func test_the_catalog_lists_all_four_rarities_exactly_as_the_spec_table() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	for key: String in BONUSES:
		var bonuses: Dictionary = skills[key].rarity_bonuses
		for t in 3:
			var tier: String = TIERS[t]
			var want: Array = BONUSES[key][t]
			assert_eq(bonuses[tier].size(), 1, "%s %s: one bonus" % [key, tier])
			assert_eq(String(bonuses[tier][0].id), want[0], "%s %s id" % [key, tier])
			assert_eq(String(bonuses[tier][0].text), want[1], "%s %s names the lineage skill" % [key, tier])
			assert_eq(_effects(bonuses[tier][0]), want[2], "%s %s effects" % [key, tier])
		var legendary: Dictionary = bonuses.legendary[0]
		assert_eq(bonuses.legendary.size(), 1)
		assert_eq(String(legendary.id), String(bonuses.unique[0].id), "%s: Legendary shares the Unique's repeat counter" % key)
		assert_eq(_effects(legendary), BONUSES[key][2][2] + [["damage", "mul", 1.2]], "%s: the Unique's effects plus damage x1.2" % key)


func test_every_rarity_bonus_changes_the_resolved_cast_and_a_rare_card_adds_one_rank() -> void:
	for key: String in BONUSES:
		for t in TIERS.size():
			var tier: String = TIERS[t]
			var effects: Array = BONUSES[key][mini(t, 2)][2] + ([["damage", "mul", 1.2]] if t == 3 else [])
			var w := _corsair(key)
			var before := w.loadout.stats(key, 2) # the rank the card lands on, without the bonus
			var card := w.upgrades.choice_card(key + "_rank", w, tier)
			assert_false(card.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			assert_true(w.upgrades.apply(key + "_rank", w, tier), "%s %s" % [key, tier])
			assert_eq(w.loadout.rank(key), 2, "%s %s: exactly one rank on top" % [key, tier])
			var after := w.loadout.stats(key)
			for effect: Array in effects:
				var field: String = RESOLVED[effect[0]]
				var label := "%s %s %s" % [key, tier, effect[0]]
				if effect[1] == "mul":
					if effect[0] == "burn_damage":
						assert_near(float(after[field]), float(before[field]) * float(effect[2]), 1.0 + float(before[field]) * 0.01, label)
					else:
						assert_near(float(after[field]), float(before[field]) * float(effect[2]), 1e-6 + absf(float(before[field])) * 1e-6, label)
				else:
					assert_eq(int(after[field]), int(before[field]) + int(effect[2]), label)
			assert_false(w.loadout.skill_mods.get(key, {}).is_empty(), "%s %s: the bonus is applied" % [key, tier])


func test_legendary_shares_the_uniques_counter_and_a_repeated_bonus_shrinks_x0_8() -> void:
	for key: String in BONUSES:
		var w := _corsair(key)
		var counter := "bonus:%s:%s" % [key, BONUSES[key][2][0]]
		w.upgrades.apply(key + "_rank", w, "unique")
		assert_eq(int(w.loadout.card_ranks.get(counter, 0)), 1, key)
		var legendary := w.upgrades.rarity_bonus(w.upgrades.card(key + "_rank"), w, "legendary")
		assert_eq(String(legendary.counter), counter, "%s: Legendary counts on the Unique's counter" % key)
		w.upgrades.apply(key + "_rank", w, "legendary")
		assert_eq(int(w.loadout.card_ranks.get(counter, 0)), 2, "%s: one shared counter" % key)
		var rare := _corsair(key)
		var c := rare.upgrades.card(key + "_rank")
		assert_near(float(rare.upgrades.rarity_bonus(c, rare, "rare").effects[0].value), 1.2, 1e-9, key + " first Elemental Boost")
		rare.upgrades.apply(key + "_rank", rare, "rare")
		assert_near(float(rare.upgrades.rarity_bonus(c, rare, "rare").effects[0].value), 1.16, 1e-9, key + " repeat: x1 + 0.2 x 0.8")


func test_scorch_makes_the_burn_hit_harder_and_the_gun_booster_shortens_ice_splitters_cooldown() -> void:
	var plain := _corsair("flamethrower", 2)
	var scorched := _corsair("flamethrower", 2)
	scorched.upgrades.apply("flamethrower_rank", scorched, "epic")
	for w: RunWorld in [plain, scorched]:
		w.progression.level = 100
		w.refresh_player_stats()
		w.drain_events()
		_mob(w, 100.0)
		_tick(w)
	var base := _damage(_play(plain, 61), "flamethrower")
	var more := _damage(_play(scorched, 61), "flamethrower")
	assert_true(more > base, "a burn pulse is bigger with Scorch (%f vs %f)" % [more, base])
	var ice := _corsair("ice_splitter", 2)
	ice.upgrades.apply("ice_splitter_rank", ice, "epic")
	_mob(ice, 100.0)
	_tick(ice)
	assert_near(float(ice.runner.cooldowns["ice_splitter"]), 2.5 * 0.88 - DT, 0.001, "cooldown x0.88")


func test_the_cadence_is_two_and_a_half_seconds() -> void:
	for key: String in KEYS:
		var w := _corsair(key)
		_mob(w, 100.0)
		_tick(w)
		assert_near(float(w.runner.cooldowns[key]), 2.5 - DT, 0.001, key)


# --- other statuses are untouched ----------------------------------------------------------------------------------------

func test_inferno_and_cold_beam_keep_their_blocks_and_the_literal_pulse_is_only_used_without_a_field() -> void:
	var skills: Dictionary = DataRepo.load_all().skills.skills
	assert_eq(skills.inferno.on_hit.pulse_field, "x")
	assert_false(skills.inferno.on_hit.has("pulse"), "Inferno reads the WZ field")
	assert_eq(skills.cold_beam.on_hit, {"status": "freeze", "duration_field": "time"})


# --- text ---------------------------------------------------------------------------------------------------------------

func test_skill_text_states_the_burn_and_the_freeze() -> void:
	var fire := _corsair("flamethrower")
	var text := SkillText.new(fire.book)
	var line := text.level_line("flamethrower", 4, fire.loadout.stats("flamethrower", 1))
	assert_true(line.contains("Burns for 3 s, 30% of base damage per second"), line)
	assert_true(line.contains("Damage 82%"), line)
	assert_true(line.contains("up to 2 monsters"), line)
	var ice := _corsair("ice_splitter", 8)
	var ice_line := SkillText.new(ice.book).level_line("ice_splitter", 30, ice.loadout.stats("ice_splitter", 8))
	assert_true(ice_line.contains("freeze for 3 sec"), ice_line)
	assert_true(ice_line.contains("Damage 130%"), ice_line)


# --- real cache: all eight ranks against Skill.wz -----------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels_with_the_string_damage() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/521.img")
	assert_true(img != null, "Skill.wz/521.img is in the cache")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"521": img.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "gun"
	var spec_damage := {"flamethrower": [82, 115, 160], "ice_splitter": [78, 100, 130]}
	var spec_time := {"flamethrower": [3, 4, 5], "ice_splitter": [1, 2, 3]}
	var spec_count := [2, 4, 6]
	for key: String in KEYS:
		var node: Dictionary = img.root.skill["%07d" % IDS[key]]
		assert_eq(book.max_level(key), 30, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank_value in range(1, 9):
			var lv: int = LEVELS[rank_value - 1]
			var level: Dictionary = node.level[str(lv)]
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			var st := lo.stats(key, rank_value)
			assert_true(level.damage is String, label + ": damage is a string in the WZ")
			assert_eq(book.canonical_level(key, rank_value), lv, label)
			assert_near(st.damage_pct, float(int(level.damage)) / 100.0, 1e-9, label)
			assert_eq(st.mob_count, int(level.mobCount), label)
			assert_true(st.has_box, label)
			assert_eq(st.box, Rect2(-350, -100, 350, 100), label + " front-only")
			assert_eq(String(st.element), "f" if key == "flamethrower" else "i", label)
			if key == "flamethrower":
				assert_eq(float(st.burn_time), float(level.time), label)
				assert_eq(int(st.burn_pulse), BurnStatus.pulse(float(st.damage_min), float(st.damage_max), 30.0, 1.0), label)
			else:
				assert_eq(book.canonical(key, lv, "time"), float(level.time), label)
		for i in 3:
			var rank_value: int = [1, 4, 8][i]
			var st := lo.stats(key, rank_value)
			assert_near(st.damage_pct * 100.0, float(spec_damage[key][i]), 1e-6, "%s rank %d spec damage" % [key, rank_value])
			assert_eq(st.mob_count, spec_count[i], "%s rank %d spec mobCount" % [key, rank_value])
			assert_eq(book.canonical(key, book.canonical_level(key, rank_value), "time"), float(spec_time[key][i]), "%s rank %d spec time" % [key, rank_value])
		var d := book.def(key)
		assert_true(lib.sound(String(d.sounds.use)) != null, key + " use sound")
		assert_true(lib.sound(String(d.sounds.hit)) != null, key + " hit sound")
		assert_true(lib.node("Character.wz/00002000.img/" + String(d.action)) is Dictionary, key + " body action")
		var frames := 15 if key == "flamethrower" else 13
		for field in ["effect", "effect_ship", "hit"]:
			var path := book.visual(key, field, 1, 1) if field != "hit" else String(d.hit)
			assert_false(lib.anim(path).is_empty(), "%s %s resolves: %s" % [key, field, path])
		assert_eq(lib.anim(book.visual(key, "effect", 4, 1)).frame_count(), frames, key + " effect frames")
		assert_eq(lib.anim(book.visual(key, "effect_ship", 4, 1)).frame_count(), frames, key + " effect_ship frames")
	assert_eq(Array(lib.missing), [])
	lib.free()
