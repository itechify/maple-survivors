extends TestCase
## Corsair's five gun fillers (spec #384, ticket C4 #388): Double Shot, Burst Fire, Invisible Shot, Recoil Shot and Grenade on
## the `corsair` line, GAME_DESIGN 7.120.3. Seeded synthetic worlds with fixed ticks (a flat floor, tiny mob bodies that never
## move); the Skill.wz levels are the synthetic fixture tables unless a test says "real cache" (those call require_cache() and
## SKIP without it). The four moved definitions used to be the Gunslinger's (test_gunslinger_attacks.gd, now Blank Shot only).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const GROUND := {"x1": 0, "y1": 0, "x2": 1000, "y2": 0}
const PISTOL := 1492000
const KNUCKLER := 1482000
const KEYS := ["double_shot", "burst_fire", "invisible_shot", "recoil_shot", "grenade"]
const TIERS := ["rare", "epic", "unique", "legendary"]


## A Corsair (job 522) on a flat floor at `x`, mob bodies shrunk to 4 x 10 px and standing still, `key` the only skill, at
## `rank_value`.
func _corsair(key: String, rank_value := 1, segments: Array = [GROUND], x := 400.0, p_seed := 388) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7},
		KNUCKLER: {"incPAD": 18, "attackSpeed": 5, "tuc": 7}}, true)
	setup.map_img = RF.map_from_segments(segments)
	setup.skill_imgs["521"] = _burst_fire_book()
	setup["job"] = 522
	var w := RunWorld.new(setup)
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0.0
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


## The synthetic 521 book (the shared fixtures have none): Burst Fire 5210000's real endpoints, damage 115 -> 210 %, three bullets, range 350,
## linear between (rank 1 = level 3 = 125 %, rank 4 = level 10 = 160 %, rank 8 = level 20 = 210 %).
func _burst_fire_book() -> Dictionary:
	var levels := {}
	for lv in range(1, 21):
		levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 13 + lv / 2, "damage": 115.0 + 95.0 * float(lv - 1) / 19.0, "bulletCount": 3, "range": 350}
	return {"skill": {"5210000": {"weapon": 49, "icon": RF._canvas(32, 32), "action": {"0": "triplefire"}, "level": levels,
		"hit": {"0": RF._anim(4, 60.0, 86, 49)}, "effect": RF._anim(8, 90.0, 60, 60)}}}


func _mob(w: RunWorld, dx: float, boss := false) -> int:
	var slot := RF.put_mob(w, MOB, w.player.pos.x + dx, -5.0, 100000.0)
	if boss:
		w.mob_boss[slot] = 0
		w.swarm.steady[slot] = 1
	return slot


## One runner tick on the current mobs; the events it produced.
func _tick(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


## Casts once and plays `ticks` more world ticks; every event of it all.
func _cast_and_fly(w: RunWorld, ticks := 60) -> Array:
	var events := _tick(w)
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


func _ints(values: Array) -> Array:
	return values.map(func(v: Variant) -> int: return int(v))


# --- the definitions --------------------------------------------------------------------------------------------------

func test_the_five_fillers_are_defined_in_the_corsair_line_only_with_no_gate_and_the_default_ranks() -> void:
	var w := _corsair("double_shot")
	for key: String in KEYS:
		var d := w.book.def(key)
		assert_false(d.has("weapon_families"), "%s: a weapon gates nothing" % key)
		assert_false(d.has("ranks"), "%s: the default rank table" % key)
		assert_eq(String(d.slot), "active", key)
		assert_eq(w.book.max_rank(key), 8, key)
		assert_eq(_ints(w.book.rank_table(key)), [3, 5, 8, 10, 13, 15, 18, 20], key)
		assert_eq(w.book.max_level(key), 20, key)
		assert_true(String(d.get("_tier", "")).contains("Tier C"), key + " notes its tier C choices")
	assert_eq(_ints(KEYS.map(func(k: String) -> Variant: return w.book.def(k).skill_id)), [5001003, 5210000, 5201001, 5201006, 5201002])
	assert_eq(_ints(KEYS.map(func(k: String) -> Variant: return w.book.def(k).job)), [500, 521, 520, 520, 520])
	assert_eq(KEYS.map(func(k: String) -> Variant: return String(w.book.def(k).book)), ["500", "521", "520", "520", "520"])
	var cooldowns := {"double_shot": 1.0, "burst_fire": 2.0, "invisible_shot": 1.0, "recoil_shot": 1.8, "grenade": 2.0}
	for key: String in KEYS:
		assert_near(float(w.book.def(key).cooldown), float(cooldowns[key]), 1e-9, key + " cooldown")


func test_each_key_is_defined_in_one_line_file_and_the_pirate_file_keeps_the_rest() -> void:
	var corsair: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "corsair")).skills
	var pirate: Dictionary = DataRepo.load_json(DataRepo.fragment_path("skills", "pirate")).skills
	for key: String in KEYS:
		assert_true(corsair.has(key), "%s lives in corsair.json" % key)
		assert_false(pirate.has(key), "%s is gone from pirate.json (a repeated key is a load error)" % key)
	for key in ["blank_shot", "dash", "gun_mastery", "gun_booster", "bullet_time", "knuckler_mastery", "oak_barrel"]:
		assert_true(pirate.has(key), "%s stays in pirate.json" % key)
	assert_false(corsair.has("blank_shot"), "Blank Shot is not ported (CS-5)")


func test_the_legacy_gunslinger_cards_are_gone_and_the_pool_generates_new_and_rank_cards() -> void:
	var w := _corsair("double_shot")
	for key: String in ["double_shot", "invisible_shot", "recoil_shot", "grenade"]:
		for suffix in ["_pierce", "_targets"]:
			assert_true(w.upgrades.card(key + suffix).is_empty(), key + suffix + " is deleted")
	for key: String in KEYS:
		for suffix in ["_new", "_rank"]:
			var c := w.upgrades.card(key + suffix)
			assert_false(c.is_empty(), key + suffix + " is generated by UpgradePool.add_pool_skills")
			assert_false(c.has("requires"), key + suffix + " has no legacy job gate")
	var legacy: Array = DataRepo.load_json(DataRepo.fragment_path("upgrades", "pirate")).cards.map(
		func(c: Dictionary) -> String: return String(c.id))
	for id: String in legacy:
		for key: String in ["double_shot", "invisible_shot", "recoil_shot", "grenade"]:
			assert_false(id.begins_with(key + "_"), id + " should be deleted")
	for id in ["blank_shot_new", "gun_mastery_new", "bullet_time_new", "oak_barrel_new"]:
		assert_has(legacy, id)


# --- Double Shot ------------------------------------------------------------------------------------------------------

func test_double_shot_splits_its_two_bullets_over_two_monsters_and_flies_the_ammo_bullet_art() -> void:
	var w := _corsair("double_shot")
	var first := _mob(w, 90)
	var second := _mob(w, -150) # the other side: a bullet stops at the first monster on its line
	var events := _tick(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(w.projectiles.active_count(), 2)
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			assert_eq(w.projectiles.visual[i], w.visual_index(Ammo.bullet_path(w.ammo_id())), "the ammo's bullet, not a skill ball")
	for tick in 40:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	var hit_mobs := _hit_slots(events, "double_shot")
	hit_mobs.sort()
	assert_eq(hit_mobs, [first, second])
	var st := w.loadout.stats("double_shot")
	assert_eq([st.count, st.cooldown, st.speed, st.radius, st.pierce], [2, 1.0, 600.0, 8.0, 0])
	assert_eq(String(st.action), "doublefire")


func test_double_shot_with_one_monster_sends_both_bullets_at_it_and_a_pistol_or_knuckle_both_cast() -> void:
	for weapon in [PISTOL, KNUCKLER]:
		var w := _corsair("double_shot")
		if weapon == KNUCKLER:
			w.wear_new_item(KNUCKLER)
		var only := _mob(w, 100)
		var hits := _hit_slots(_cast_and_fly(w, 40), "double_shot")
		assert_eq(hits.size(), 2, "weapon %d" % weapon)
		assert_true(hits.all(func(s: int) -> bool: return s == only))


func test_double_shot_waits_for_a_monster_inside_its_range() -> void:
	var w := _corsair("double_shot")
	_mob(w, 360) # rank 1 is WZ level 3: 229 px in the fixture table
	assert_eq(_of(_tick(w), "cast").size(), 0)


# --- Burst Fire ---------------------------------------------------------------------------------------------------------

func _broad_mobs(w: RunWorld) -> void:
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -50, 40, 50) # a volley is spread a few px vertically: snail-sized, not 4 x 10
	w.refresh_player_stats()


func test_burst_fire_puts_all_three_bullets_on_one_monster_and_a_boss_comes_first() -> void:
	var w := _corsair("burst_fire")
	_broad_mobs(w)
	var near := _mob(w, 80)
	_mob(w, 140)
	_mob(w, -120)
	var events := _tick(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(w.projectiles.active_count(), 3, "bulletCount 3")
	for tick in 45:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	var hits := _hit_slots(events, "burst_fire")
	assert_eq(hits.size(), 3)
	assert_true(hits.all(func(s: int) -> bool: return s == near), "every bullet reaches the nearest monster")
	var b := _corsair("burst_fire")
	_broad_mobs(b)
	_mob(b, 80)
	var boss := _mob(b, -200, true) # the other side: a bullet stops at the first monster on its line
	var boss_hits := _hit_slots(_cast_and_fly(b, 50), "burst_fire")
	assert_eq(boss_hits.size(), 3)
	assert_true(boss_hits.all(func(s: int) -> bool: return s == boss), "all three go to the scheduled boss")


func test_burst_fire_numbers_are_the_wz_ones_and_the_cooldown_and_range_hold() -> void:
	var w := _corsair("burst_fire")
	_mob(w, 400) # past the 350 px range
	assert_eq(_of(_tick(w), "cast").size(), 0)
	_mob(w, 300)
	assert_eq(_of(_tick(w), "cast").size(), 1)
	assert_near(float(w.runner.cooldowns.burst_fire), 2.0 - DT, 0.001)
	var st := w.loadout.stats("burst_fire")
	assert_eq([st.count, st.range, st.speed, st.radius, st.pierce], [3, 350.0, 700.0, 6.0, 0])
	assert_eq(String(st.action), "triplefire")
	assert_eq(String(st.hit), "Skill.wz/521.img/skill/5210000/hit/0")
	assert_eq(String(w.book.def("burst_fire").sounds.hit), "Sound.wz/Skill.img/5210000/Hit", "Hit goes through the UOL to Double Shot's")


# --- Invisible Shot -----------------------------------------------------------------------------------------------------

func test_invisible_shot_hits_in_front_and_behind_up_to_three_mobs_inside_the_mirrored_box() -> void:
	var w := _corsair("invisible_shot")
	var front := _mob(w, 120.0)
	var behind := _mob(w, -120.0)
	var edge_front := _mob(w, 240.0)
	var edge_behind := _mob(w, -240.0)
	var outside := _mob(w, 270.0)
	var hits := _hit_slots(_tick(w), "invisible_shot")
	assert_eq(hits.size(), 3, "three mobs")
	assert_has(hits, front)
	assert_has(hits, behind)
	assert_false(outside in hits, "beyond the 250 px box")
	assert_true((hits[2] == edge_front) or (hits[2] == edge_behind), "nearest first: the two at 120 px, then one at 240 px")
	var rear := _corsair("invisible_shot")
	var only := _mob(rear, -200.0)
	assert_eq(_hit_slots(_tick(rear), "invisible_shot"), [only], "a lone mob behind is struck")
	var far := _corsair("invisible_shot")
	_mob(far, 300.0)
	_mob(far, -300.0)
	assert_eq(_of(_tick(far), "cast").size(), 0, "nothing inside the box: no cast")


# --- Recoil Shot --------------------------------------------------------------------------------------------------------

func test_recoil_shot_fires_the_ammo_bullet_then_hops_back_the_level_range() -> void:
	for case: Array in [[1, 129.0], [8, 250.0]]:
		var w := _corsair("recoil_shot", case[0])
		_mob(w, 200.0)
		var events := _tick(w)
		assert_eq(_of(events, "cast").size(), 1)
		assert_eq(w.projectiles.active_count(), 1, "one bullet in flight")
		var hop := float(w.loadout.stats("recoil_shot", case[0]).displacement.distance)
		assert_near(w.player.pos.x, 400.0 - hop, 1e-6, "rank %d hops %d px away from the mob" % [case[0], hop])
		assert_eq(w.player.facing, 1, "still facing the mob it backed away from")
		assert_eq(_of(events, "cast")[0].pos.x, 400.0, "the cast event reports the start")
		assert_eq(w.loadout.stats("recoil_shot", case[0]).displacement.direction, "away")
	var left := _corsair("recoil_shot", 8)
	_mob(left, -200.0)
	_tick(left)
	assert_true(left.player.pos.x > 400.0, "a mob on the left: the hop goes right")
	assert_eq(left.player.facing, -1)


func test_recoil_shot_bullet_is_the_ammo_item_visual_and_follows_the_corsair_tier() -> void:
	var w := _corsair("recoil_shot")
	assert_eq(w.ammo_id(), 2330000, "Bullet at Lv 1")
	w.progression.level = 30
	w.refresh_player_stats()
	w._sync_ammo()
	_mob(w, 200.0)
	_tick(w)
	assert_eq(w.ammo_id(), 2330001, "Split Bullet at Lv 30")
	var shot := -1
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			shot = i
	assert_true(shot >= 0)
	assert_eq(w.projectiles.paths[w.projectiles.visual[shot]], Ammo.bullet_path(2330001))
	assert_eq(w.projectiles.rotate[shot], 1, "bullets turn to their direction")


func test_recoil_shot_hop_is_cut_short_by_a_platform_edge_and_by_a_wall() -> void:
	var edge := _corsair("recoil_shot", 8, [GROUND], 100.0)
	_mob(edge, 150.0)
	var events := _tick(edge)
	assert_near(edge.player.pos.x, 0.0, 1e-6, "stopped at the edge, 100 of 250 px")
	assert_eq(_of(events, "cast").size(), 1, "the edge never fails the cast")
	assert_eq(edge.projectiles.active_count(), 1)
	var wall := _corsair("recoil_shot", 8, [GROUND, {"x1": 300, "y1": 0, "x2": 300, "y2": -80}], 400.0)
	_mob(wall, 150.0)
	_tick(wall)
	assert_near(wall.player.pos.x, 300.0 + FootholdMap.EPS, 1e-4, "stopped short of the wall")
	var corner := _corsair("recoil_shot", 8, [GROUND], 0.0)
	_mob(corner, 150.0)
	assert_eq(_of(_tick(corner), "cast").size(), 1)
	assert_near(corner.player.pos.x, 0.0, 1e-6, "already on the edge: no hop, still a shot")


func test_recoil_shot_does_not_hop_in_the_air() -> void:
	var w := _corsair("recoil_shot", 8)
	w.player.place(Vector2(400, -60), w.fhm)
	_mob(w, 150.0)
	assert_eq(_of(_tick(w), "cast").size(), 1)
	assert_eq(w.player.pos, Vector2(400, -60))


# --- Grenade ------------------------------------------------------------------------------------------------------------

func test_grenade_is_thrown_on_the_cast_tick_without_a_wind_up_and_lands_after_its_flight() -> void:
	var w := _corsair("grenade")
	var target := _mob(w, 300.0)
	var events := _tick(w)
	assert_eq(_of(events, "cast").size(), 1)
	var thrown := _of(events, "skill_thrown", "grenade")
	assert_eq(thrown.size(), 1, "the throw starts on the very tick of the cast")
	assert_eq(_hit_slots(events, "grenade").size(), 0, "nothing is struck before it lands")
	assert_near(thrown[0].to.x, w.mob_center(target).x, 1e-3)
	assert_near(float(thrown[0].seconds), maxf(0.1, thrown[0].from.distance_to(thrown[0].to) / 600.0), 1e-6)
	assert_eq(thrown[0].ball, "Skill.wz/520.img/skill/5201002/ball")
	assert_eq(thrown[0].burst, "Skill.wz/520.img/skill/5201002/special")
	var landed := []
	var ticks := 0
	while landed.is_empty() and ticks < 120:
		landed = _hit_slots(_tick(w), "grenade")
		ticks += 1
	assert_eq(landed, [target])
	assert_near(float(ticks) * DT, float(thrown[0].seconds), DT * 1.5, "it landed when the ball arrived")


func test_grenade_lands_on_the_thickest_cluster_over_a_nearer_lone_mob() -> void:
	var w := _corsair("grenade", 1)
	var lone := _mob(w, 120.0)
	var cluster: Array = [_mob(w, 300.0), _mob(w, 320.0), _mob(w, 340.0)]
	var thrown: Dictionary = _of(_tick(w), "skill_thrown")[0]
	assert_true(float(thrown.to.x) > w.player.pos.x + 250.0, "aimed at the cluster, not the lone mob")
	var hits := []
	for tick in 120:
		hits.append_array(_hit_slots(_tick(w), "grenade"))
	hits.sort()
	var expect := cluster.duplicate()
	expect.sort()
	assert_eq(hits, expect, "the three clustered mobs, not the lone one (%d)" % lone)
	var single := _corsair("grenade", 1)
	var near := _mob(single, 120.0)
	_mob(single, 380.0)
	var thrown2: Dictionary = _of(_tick(single), "skill_thrown")[0]
	assert_near(thrown2.to.x, single.mob_center(near).x, 1e-3, "ties go to the nearest")
	var boss_world := _corsair("grenade")
	var boss := _mob(boss_world, 380.0, true)
	for dx in [100.0, 110.0, 120.0]:
		_mob(boss_world, dx)
	var thrown3: Dictionary = _of(_tick(boss_world), "skill_thrown")[0]
	assert_near(thrown3.to.x, boss_world.mob_center(boss).x, 1e-3, "a scheduled boss in reach is the target")
	var out_of_reach := _corsair("grenade")
	_mob(out_of_reach, 410.0)
	assert_eq(_of(_tick(out_of_reach), "cast").size(), 0, "beyond the 400 px throw range: waits")


func test_grenade_blasts_three_at_rank_one_and_six_at_rank_eight_inside_the_canonical_box() -> void:
	for case: Array in [[1, 3], [8, 6]]:
		var w := _corsair("grenade", case[0])
		var group: Array = []
		for i in 8:
			group.append(_mob(w, 250.0 + 10.0 * i))
		var outside := _mob(w, 390.0) # 90 px past the first one: outside its 50 px blast reach
		var hits := []
		for tick in 45:
			hits.append_array(_hit_slots(_tick(w), "grenade"))
		assert_eq(hits.size(), case[1], "rank %d strikes %d mobs" % case)
		assert_false(outside in hits)
		assert_eq(w.loadout.stats("grenade", case[0]).box, Rect2(-50, -50, 100, 70))


# --- rarity bonuses -----------------------------------------------------------------------------------------------------

## skill -> [rare, epic, unique] as [id, name, [[stat, op, value]...]]; Legendary is the Unique's id and effects plus damage x1.2.
const BONUSES := {
	"double_shot": [["gun_mastery", "Gun Mastery", [["damage", "mul", 1.2]]], ["booster", "Gun Booster", [["cooldown", "mul", 0.88]]],
		["bullet_time", "Bullet Time", [["count", "add", 1.0]]]],
	"burst_fire": [["gun_mastery", "Gun Mastery", [["damage", "mul", 1.2]]], ["booster", "Gun Booster", [["cooldown", "mul", 0.88]]],
		["bullet_time", "Bullet Time", [["count", "add", 1.0]]]],
	"invisible_shot": [["gun_mastery", "Gun Mastery", [["damage", "mul", 1.2]]], ["bullet_time", "Bullet Time", [["area", "mul", 1.2]]],
		["speed_infusion", "Speed Infusion", [["cooldown", "mul", 0.75], ["count", "add", 2.0]]]],
	"recoil_shot": [["gun_mastery", "Gun Mastery", [["damage", "mul", 1.2]]], ["booster", "Gun Booster", [["cooldown", "mul", 0.88]]],
		["bullet_time", "Bullet Time", [["count", "add", 1.0]]]],
	"grenade": [["gun_mastery", "Gun Mastery", [["damage", "mul", 1.2]]], ["bigger_boom", "Bigger Boom", [["area", "mul", 1.2]]],
		["cluster", "Cluster Grenade", [["count", "add", 2.0]]]],
}


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


## The resolved stat each effect moves, as the cast reads it.
const RESOLVED := {"damage": "damage_max", "cooldown": "cooldown", "count": "count", "area": "area"}


func test_every_rarity_bonus_changes_the_resolved_cast_and_a_rare_card_adds_one_rank() -> void:
	for key: String in BONUSES:
		for t in TIERS.size():
			var tier: String = TIERS[t]
			var effects: Array = BONUSES[key][mini(t, 2)][2] + ([["damage", "mul", 1.2]] if t == 3 else [])
			var w := _corsair(key)
			var before := w.loadout.stats(key, 2) # the rank the card lands on, without the bonus
			var card := w.upgrades.choice_card(key + "_rank", w, tier)
			assert_false(card.get("rarity_bonus", {}).is_empty(), "%s %s offers a bonus" % [key, tier])
			assert_eq(card, w.upgrades.choice_card(key + "_rank", w, tier), "the preview does not spend the bonus")
			assert_true(w.upgrades.apply(key + "_rank", w, tier), "%s %s" % [key, tier])
			assert_eq(w.loadout.rank(key), 2, "%s %s: exactly one rank on top" % [key, tier])
			var after := w.loadout.stats(key)
			for effect: Array in effects:
				var field: String = RESOLVED[effect[0]]
				var label := "%s %s %s" % [key, tier, effect[0]]
				if effect[1] == "mul":
					assert_near(float(after[field]), float(before[field]) * float(effect[2]), 1e-6 + absf(float(before[field])) * 1e-6, label)
				else:
					assert_eq(int(after[field]), int(before[field]) + int(effect[2]), label)
			# The Rare+ rank card at an owned repeat: a second Unique/Legendary of the same id repeats it (x0.8 for the Mastery).
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
		assert_near(float(rare.upgrades.rarity_bonus(c, rare, "rare").effects[0].value), 1.2, 1e-9, key + " first Gun Mastery")
		rare.upgrades.apply(key + "_rank", rare, "rare")
		assert_near(float(rare.upgrades.rarity_bonus(c, rare, "rare").effects[0].value), 1.16, 1e-9, key + " repeat: x1 + 0.2 x 0.8")


# --- behaviour of the bonuses (not only the resolved number) ------------------------------------------------------------

func _with_bonus(key: String, tier := "unique") -> RunWorld:
	var w := _corsair(key)
	w.upgrades.apply(key + "_rank", w, tier)
	return w


func test_bullet_time_adds_a_third_bullet_a_fourth_burst_bullet_and_a_second_recoil_bullet() -> void:
	for case: Array in [["double_shot", 3], ["burst_fire", 4], ["recoil_shot", 2]]:
		var w := _with_bonus(case[0])
		_mob(w, 100.0)
		_tick(w)
		assert_eq(w.projectiles.active_count(), case[1], "%s fires %d bullets" % [case[0], case[1]])


func test_speed_infusion_widens_invisible_shot_to_five_targets_and_cuts_the_cooldown() -> void:
	var w := _with_bonus("invisible_shot")
	for dx in [-200.0, -150.0, -100.0, 50.0, 100.0, 150.0, 200.0]:
		_mob(w, dx)
	assert_eq(_hit_slots(_tick(w), "invisible_shot").size(), 5, "3 + 2 targets")
	assert_near(float(w.runner.cooldowns.invisible_shot), 0.75 - DT, 0.001, "cooldown x0.75")


func test_bullet_time_widens_the_invisible_shot_box_and_bigger_boom_the_grenade_blast() -> void:
	var plain := _corsair("invisible_shot", 2)
	_mob(plain, 270.0)
	assert_eq(_of(_tick(plain), "cast").size(), 0, "270 px is outside the 250 px box")
	var wide := _with_bonus("invisible_shot", "epic")
	var edge := _mob(wide, 270.0)
	assert_eq(_hit_slots(_tick(wide), "invisible_shot"), [edge], "x1.2 reaches 300 px")
	var small := _corsair("grenade", 2)
	_mob(small, 300.0)
	_mob(small, 355.0) # 55 px past the first: outside its 50 px blast reach
	var landed := []
	for tick in 60:
		landed.append_array(_hit_slots(_tick(small), "grenade"))
	assert_eq(landed.size(), 1, "only the target")
	var big := _with_bonus("grenade", "epic")
	var group := [_mob(big, 300.0), _mob(big, 355.0)]
	var landed2 := []
	for tick in 60:
		landed2.append_array(_hit_slots(_tick(big), "grenade"))
	landed2.sort()
	assert_eq(landed2, group, "Bigger Boom x1.2: the 60 px reach takes the second mob")


func test_cluster_grenade_blasts_two_more_monsters() -> void:
	var base: int = _corsair("grenade", 2).loadout.stats("grenade", 2).mob_count
	var w := _with_bonus("grenade")
	for i in 10:
		_mob(w, 250.0 + 5.0 * i)
	var hits := []
	for tick in 45:
		hits.append_array(_hit_slots(_tick(w), "grenade"))
	assert_eq(hits.size(), base + 2, "the rank's mobCount plus Cluster Grenade's 2")


func test_gun_mastery_and_the_gun_booster_change_the_damage_dealt_and_the_cooldown() -> void:
	for key: String in ["double_shot", "burst_fire", "invisible_shot", "recoil_shot"]:
		var plain := _corsair(key, 2)
		var strong := _with_bonus(key, "rare")
		for w: RunWorld in [plain, strong]:
			w.progression.level = 100 # enough STR/DEX that a x1.2 shows in the integer damage rolls
			w.refresh_player_stats()
			for mk: MobKind in w.mob_kinds:
				mk.pdd = 0 # a defence floor would round both casts to the same 1 damage
			_mob(w, 100.0)
			_mob(w, -100.0)
		var base := _damage(_cast_and_fly(plain, 45), key)
		var more := _damage(_cast_and_fly(strong, 45), key)
		assert_true(more > base, "%s: Gun Mastery x1.2 deals more (%f vs %f)" % [key, more, base])
	for key: String in ["double_shot", "burst_fire", "recoil_shot"]:
		var w := _with_bonus(key, "epic")
		var base_cd := float(w.book.def(key).cooldown)
		_mob(w, 100.0)
		_tick(w)
		assert_near(float(w.runner.cooldowns[key]), base_cd * 0.88 - DT, 0.001, "%s cooldown x0.88" % key)


# --- real cache: all eight ranks against Skill.wz ----------------------------------------------------------------------

## skill -> [book, WZ id, the eight mapped levels (ceil(rank x 20 / 8))]
const MAPPED := {
	"double_shot": ["500", 5001003], "burst_fire": ["521", 5210000], "invisible_shot": ["520", 5201001],
	"recoil_shot": ["520", 5201006], "grenade": ["520", 5201002],
}
const LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
## [rank 1, rank 4, rank 8] damage percent, from the spec's "Rank values".
const DAMAGE := {"double_shot": [63, 70, 80], "burst_fire": [125, 160, 210], "invisible_shot": [85, 120, 170],
	"recoil_shot": [90, 160, 260], "grenade": [55, 90, 140]}


func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var imgs := {}
	for book_id: String in ["500", "520", "521"]:
		var img := lib.img("Skill.wz/%s.img" % book_id)
		assert_true(img != null, "Skill.wz/%s.img is in the cache" % book_id)
		if img == null:
			lib.free()
			return
		imgs[book_id] = img.root
	var book := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var lo := Loadout.new(book)
	lo.weapon_family = "gun"
	for key: String in MAPPED:
		var row: Array = MAPPED[key]
		var node: Dictionary = imgs[row[0]].skill["%07d" % int(row[1])]
		assert_eq(book.max_level(key), 20, key)
		assert_eq(book.max_rank(key), 8, key)
		for rank_value in range(1, 9):
			var lv: int = LEVELS[rank_value - 1]
			var level: Dictionary = node.level[str(lv)]
			var st := lo.stats(key, rank_value)
			var label := "%s rank %d (level %d)" % [key, rank_value, lv]
			assert_eq(book.canonical_level(key, rank_value), lv, label)
			assert_eq(int(st.level), lv, label)
			assert_near(st.damage_pct, float(level.damage) / 100.0, 1e-6, label)
			match key:
				"double_shot":
					assert_eq(st.count, int(level.bulletCount), label)
					assert_eq(st.count, 2, label)
					assert_eq(st.range, float(level.range), label)
				"burst_fire":
					assert_eq(st.count, int(level.bulletCount), label)
					assert_eq(st.count, 3, label)
					assert_eq(st.range, 350.0, label)
				"invisible_shot":
					assert_eq(st.mob_count, int(level.mobCount), label)
					assert_eq(st.mob_count, 3, label)
					assert_eq(st.box, Rect2(-250, -80, 500, 120), label + " mirrored")
				"recoil_shot":
					assert_eq(st.displacement.distance, float(level.range), label)
				"grenade":
					assert_eq(st.mob_count, int(level.mobCount), label)
					assert_eq(st.box.position, Vector2(-50, -50), label)
					assert_eq(st.box.end, Vector2(50, 20), label)
		for i in 3:
			var rank_value: int = [1, 4, 8][i]
			assert_near(lo.stats(key, rank_value).damage_pct * 100.0, float(DAMAGE[key][i]), 1e-6, "%s rank %d spec damage" % [key, rank_value])
	assert_eq(_ints([lo.stats("recoil_shot", 1).displacement.distance, lo.stats("recoil_shot", 4).displacement.distance,
		lo.stats("recoil_shot", 8).displacement.distance]), [130, 175, 250], "hop 130 / 175 / 250")
	assert_eq(_ints([lo.stats("grenade", 1).mob_count, lo.stats("grenade", 4).mob_count, lo.stats("grenade", 8).mob_count]), [3, 4, 6])
	for key: String in MAPPED:
		var d := book.def(key)
		assert_true(lib.sound(String(d.sounds.use)) != null, key + " use sound")
		for field in ["effect", "hit", "ball"]:
			var path := book.visual(key, field, 1, 1)
			if path != "":
				assert_false(lib.anim(path).is_empty(), path)
		assert_true(String(d.action) == "weapon" or lib.node("Character.wz/00002000.img/" + String(d.action)) is Dictionary, key + " action")
	assert_true(lib.sound("Sound.wz/Skill.img/5210000/Hit") != null, "Burst Fire's Hit sound resolves through the UOL")
	assert_eq(Array(lib.missing), [])
	lib.free()
