extends TestCase
## Gunslinger attacks (spec #168 ticket #192, docs/GAME_DESIGN.md 7.16): Invisible Shot, Blank Shot, Grenade and Recoil
## Shot through the shipping data on seeded synthetic worlds with fixed ticks (a flat floor, tiny mob bodies that never
## move), then the cards and the Lv 30 advancement draw, then the original v83 numbers and art in the private cache
## (those SKIP without it).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const GROUND := {"x1": 0, "y1": 0, "x2": 1000, "y2": 0}
const STEEL_KNUCKLER := 1482000
const PISTOL := 1492000
const INFO := {
	STEEL_KNUCKLER: {"incPAD": 18, "attackSpeed": 5, "tuc": 7},
	PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7},
	1482004: {"reqJob": 16, "reqLevel": 30, "reqSTR": 60, "reqDEX": 30, "incPAD": 34, "attackSpeed": 5, "tuc": 7},
	1492004: {"reqJob": 16, "reqLevel": 30, "reqSTR": 30, "reqDEX": 70, "incPAD": 31, "attackSpeed": 5, "tuc": 7},
}
const ATTACKS := ["invisible_shot", "blank_shot", "grenade", "recoil_shot"]
const GUN_ONLY := ["invisible_shot", "blank_shot", "recoil_shot"]


## A Gunslinger (job 520 by way of a gun-path Pirate) on a flat floor at x = 400, a spare knuckle in the Equip tab,
## mob bodies shrunk to 4 x 10 px and standing still, MP full, `key` learned at `rank_value`.
func _gunslinger(key: String, rank_value := 1, segments: Array = [GROUND], x := 400.0, p_seed := 192) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge(INFO, true)
	setup.map_img = RF.map_from_segments(segments)
	var w := RunWorld.new(setup)
	w.change_job(500, "gun")
	w.progression.level = 30
	w.change_job(520)
	w.equipment.inventory.append(Equipment.create(STEEL_KNUCKLER, INFO[STEEL_KNUCKLER]))
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0.0
	w.player.place(Vector2(x, 0), w.fhm)
	w.update_view()
	w.player.facing = 1
	w.god = true
	w.loadout.order.clear()
	if key != "":
		assert_true(w.learn_skill(key), "learn " + key)
		w.loadout.set_rank(key, rank_value)
	w.refresh_player_stats()
	w.heal_fraction("mp", 1.0)
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float) -> int:
	return RF.put_mob(w, MOB, w.player.pos.x + dx, -5.0, 100000.0)


## One runner tick on the current mobs; the events it produced.
func _tick(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String, skill := "") -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type and (skill == "" or e.skill == skill))


func _hit_slots(events: Array, skill: String) -> Array:
	return _of(events, "mob_hit", skill).map(func(e: Dictionary) -> int: return int(e.mob))


func _wear(w: RunWorld, id: int) -> void:
	var ids: Array = w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))
	var index: int = ids.find(id)
	assert_true(index >= 0, "item %d is in the Equip tab" % id)
	assert_eq(w.equip_item(index), "")


# --- numbers by rank ----------------------------------------------------------------------------------------------------

func test_cast_rule_cost_count_and_damage_by_rank() -> void:
	# [mp, damage fraction, mob count] at rank 1 and 20 (Skill.wz/520.img).
	var want := {
		"invisible_shot": [[10, 0.75, 3], [25, 1.70, 3]],
		"blank_shot": [[10, 0.63, 3], [25, 1.20, 3]],
		"grenade": [[15, 0.45, 3], [27, 1.40, 6]],
		"recoil_shot": [[14, 0.70, 1], [26, 2.60, 1]],
	}
	for key: String in ATTACKS:
		var w := _gunslinger(key)
		for i in 2:
			var st := w.loadout.stats(key, 1 if i == 0 else 20)
			assert_eq(st.mp_cost, want[key][i][0], "%s MP at rank %d" % [key, 1 if i == 0 else 20])
			assert_near(st.damage_pct, want[key][i][1], 1e-6, key + " damage")
			assert_eq(st.mob_count, want[key][i][2], key + " mobs")
			assert_eq(st.damage_type, "physical")
		assert_eq(w.loadout.stats(key).cast_rule, {"invisible_shot": "box", "blank_shot": "box", "grenade": "cluster",
			"recoil_shot": "nearest"}[key])
		assert_eq(w.book.max_rank(key), 20)
		assert_eq(w.book.max_level(key), 20)


func test_each_attack_pays_its_mp_once_per_cast_and_waits_when_short() -> void:
	for key: String in ATTACKS:
		var w := _gunslinger(key)
		var mp: int = w.player_state.mp
		_mob(w, 100.0)
		var events := _tick(w)
		assert_eq(_of(events, "cast").size(), 1, key + " cast")
		assert_eq(w.player_state.mp, mp - w.loadout.stats(key).mp_cost, key + " paid its cost")
		var short := _gunslinger(key)
		assert_true(short.spend_mp(int(short.player_state.mp)))
		_mob(short, 100.0)
		events = _tick(short)
		assert_eq(_of(events, "cast").size(), 0, key + " does not cast without MP")
		assert_eq(_of(events, "mp_short").size(), 1)
		assert_eq(short.player_state.mp, 0)


# --- Invisible Shot -----------------------------------------------------------------------------------------------------

func test_invisible_shot_hits_in_front_and_behind_up_to_three_mobs_inside_the_box() -> void:
	var w := _gunslinger("invisible_shot")
	var front := _mob(w, 120.0)
	var behind := _mob(w, -120.0)
	var edge_front := _mob(w, 240.0)
	var edge_behind := _mob(w, -240.0)
	var outside := _mob(w, 270.0)
	var events := _tick(w)
	var hits := _hit_slots(events, "invisible_shot")
	assert_eq(hits.size(), 3, "three mobs at rank 1")
	assert_has(hits, front)
	assert_has(hits, behind)
	assert_false(outside in hits, "beyond the 250 px box")
	# Nearest first: the two at 120 px, then one of the two at 240 px.
	assert_true((hits[2] == edge_front) or (hits[2] == edge_behind))
	# A mob only behind is enough to cast, and only behind is hit.
	var rear := _gunslinger("invisible_shot")
	var only := _mob(rear, -200.0)
	events = _tick(rear)
	assert_eq(_hit_slots(events, "invisible_shot"), [only], "a lone mob behind is struck")
	var far := _gunslinger("invisible_shot")
	_mob(far, 300.0)
	_mob(far, -300.0)
	assert_eq(_of(_tick(far), "cast").size(), 0, "nothing inside the box: no cast, no cost")
	assert_eq(far.player_state.mp, far.player_state.max_mp)


func test_invisible_shot_mob_count_grows_with_its_card_and_stays_inside_one_cast() -> void:
	var w := _gunslinger("invisible_shot", 20)
	for dx in [-200.0, -100.0, 50.0, 100.0, 200.0]:
		_mob(w, dx)
	assert_eq(_hit_slots(_tick(w), "invisible_shot").size(), 3)
	var more := _gunslinger("invisible_shot", 20)
	assert_true(more.upgrades.apply("invisible_shot_targets", more))
	for dx in [-200.0, -100.0, 50.0, 100.0, 200.0]:
		_mob(more, dx)
	assert_eq(_hit_slots(_tick(more), "invisible_shot").size(), 4, "+1 target from the card")


# --- Blank Shot ---------------------------------------------------------------------------------------------------------

func test_blank_shot_hits_only_in_front_up_to_three_mobs() -> void:
	var w := _gunslinger("blank_shot")
	var front: Array = [_mob(w, 60.0), _mob(w, 120.0), _mob(w, 180.0), _mob(w, 230.0)]
	var behind := _mob(w, -100.0)
	var too_close := _mob(w, 10.0)
	var events := _tick(w)
	var hits := _hit_slots(events, "blank_shot")
	assert_eq(hits.size(), 3)
	assert_false(behind in hits, "behind is not in the front-only box")
	assert_false(too_close in hits, "the box starts 20 px in front of the character")
	for slot in hits:
		assert_has(front, slot)
	var rear_only := _gunslinger("blank_shot")
	_mob(rear_only, -100.0)
	assert_eq(_of(_tick(rear_only), "cast").size(), 0, "a mob only behind does not trigger it")


func test_blank_shot_at_rank_twenty_always_stuns_for_four_seconds() -> void:
	var w := _gunslinger("blank_shot", 20)
	var slots: Array = [_mob(w, 80.0), _mob(w, 120.0), _mob(w, 160.0)]
	var events := _tick(w)
	var applied := _of(events, "mob_status_applied").filter(func(e: Dictionary) -> bool: return e.status == "stun")
	assert_eq(applied.size(), 3, "prop 100: every struck mob is stunned")
	for e: Dictionary in applied:
		assert_near(float(e.duration), 4.0)
	for slot in slots:
		assert_near(w.swarm.status_time(slot, MobSwarm.STUN), 4.0, 1e-6)
		assert_false(w.swarm.can_act(slot))


func test_blank_shot_rank_one_stun_chance_is_forty_three_percent_for_one_second() -> void:
	var stunned := 0
	var struck := 0
	var w := _gunslinger("blank_shot", 1, [GROUND], 400.0, 7)
	var slots: Array = [_mob(w, 80.0), _mob(w, 120.0), _mob(w, 160.0)]
	for cast in 120:
		w.runner.cooldowns["blank_shot"] = 0.0
		w.heal_fraction("mp", 1.0)
		for slot in slots:
			w.swarm.hp[slot] = w.swarm.max_hp[slot]
		var events := _tick(w)
		struck += _hit_slots(events, "blank_shot").size()
		var applied := _of(events, "mob_status_applied").filter(func(e: Dictionary) -> bool: return e.status == "stun")
		stunned += applied.size()
		for e: Dictionary in applied:
			assert_near(float(e.duration), 1.0)
		# The stun is cleared between casts so each hit is a fresh roll.
		for slot in slots:
			w.swarm._clear_statuses(slot)
	assert_eq(struck, 360, "three mobs struck by each of 120 casts")
	assert_between(float(stunned) / float(struck), 0.33, 0.53, "about 43%% (%d of %d)" % [stunned, struck])
	# The same seed gives the same count.
	var again := _gunslinger("blank_shot", 1, [GROUND], 400.0, 7)
	var slots2: Array = [_mob(again, 80.0), _mob(again, 120.0), _mob(again, 160.0)]
	var stunned2 := 0
	for cast in 120:
		again.runner.cooldowns["blank_shot"] = 0.0
		again.heal_fraction("mp", 1.0)
		for slot in slots2:
			again.swarm.hp[slot] = again.swarm.max_hp[slot]
		stunned2 += _of(_tick(again), "mob_status_applied").filter(
			func(e: Dictionary) -> bool: return e.status == "stun").size()
		for slot in slots2:
			again.swarm._clear_statuses(slot)
	assert_eq(stunned2, stunned, "seeded: reproducible")


func test_blank_shot_never_stuns_a_scheduled_boss_but_still_damages_it() -> void:
	var w := _gunslinger("blank_shot", 20)
	var boss := _mob(w, 100.0)
	w.mob_boss[boss] = 0
	w.swarm.steady[boss] = 1
	w.drain_events()
	var events := _tick(w)
	assert_eq(_hit_slots(events, "blank_shot"), [boss], "the boss is struck")
	assert_eq(_of(events, "mob_status_applied").size(), 0, "bosses resist the stun")
	assert_eq(w.swarm.status_time(boss, MobSwarm.STUN), 0.0)


# --- Recoil Shot --------------------------------------------------------------------------------------------------------

func test_recoil_shot_fires_the_current_ammo_bullet_then_hops_back_the_canonical_distance() -> void:
	for case: Array in [[1, 115.0], [20, 250.0]]:
		var w := _gunslinger("recoil_shot", case[0])
		_mob(w, 200.0)
		var events := _tick(w)
		assert_eq(_of(events, "cast").size(), 1)
		assert_eq(w.projectiles.active_count(), 1, "one bullet in flight")
		assert_near(w.player.pos.x, 400.0 - case[1], 1e-6, "rank %d hops %d px away from the mob" % [case[0], case[1]])
		assert_eq(w.player.facing, 1, "still facing the mob it backed away from")
		assert_eq(_of(events, "cast")[0].pos.x, 400.0, "the cast event reports the start")
		assert_eq(w.loadout.stats("recoil_shot", case[0]).displacement,
			{"direction": "away", "when": "after", "distance": case[1]})
	# A mob on the left: the hop goes right.
	var left := _gunslinger("recoil_shot", 20)
	_mob(left, -200.0)
	_tick(left)
	assert_near(left.player.pos.x, 650.0, 1e-6)
	assert_eq(left.player.facing, -1)


func test_recoil_shot_bullet_is_the_ammo_item_visual_and_follows_the_tier() -> void:
	var w := _gunslinger("recoil_shot")
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
	var upgraded := _gunslinger("recoil_shot")
	upgraded.progression.level = 50
	upgraded.refresh_player_stats()
	upgraded._sync_ammo()
	assert_eq(upgraded.ammo_id(), 2330002, "Mighty Bullet from Lv 50")
	_mob(upgraded, 200.0)
	_tick(upgraded)
	for i in upgraded.projectiles.capacity():
		if upgraded.projectiles.active[i] != 0:
			assert_eq(upgraded.projectiles.paths[upgraded.projectiles.visual[i]], Ammo.bullet_path(2330002))


func test_recoil_shot_hop_is_cut_short_by_a_platform_edge_and_by_a_wall() -> void:
	var edge := _gunslinger("recoil_shot", 20, [GROUND], 100.0)
	_mob(edge, 150.0)
	var events := _tick(edge)
	assert_near(edge.player.pos.x, 0.0, 1e-6, "stopped at the edge, 100 of 250 px")
	assert_eq(_of(events, "cast").size(), 1, "the edge never fails the cast")
	assert_eq(edge.projectiles.active_count(), 1)
	var wall := _gunslinger("recoil_shot", 20, [GROUND, {"x1": 300, "y1": 0, "x2": 300, "y2": -80}], 400.0)
	_mob(wall, 150.0)
	_tick(wall)
	assert_near(wall.player.pos.x, 300.0 + FootholdMap.EPS, 1e-4, "stopped short of the wall")
	var corner := _gunslinger("recoil_shot", 20, [GROUND], 0.0)
	_mob(corner, 150.0)
	assert_eq(_of(_tick(corner), "cast").size(), 1)
	assert_near(corner.player.pos.x, 0.0, 1e-6, "already on the edge: no hop, still a shot")


func test_recoil_shot_does_not_hop_in_the_air() -> void:
	var w := _gunslinger("recoil_shot", 20)
	w.player.place(Vector2(400, -60), w.fhm)
	_mob(w, 150.0)
	var events := _tick(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(w.player.pos, Vector2(400, -60))


func test_recoil_shot_bullet_pierce_card_hits_a_second_mob() -> void:
	var w := _gunslinger("recoil_shot", 20)
	assert_true(w.upgrades.apply("recoil_shot_pierce", w))
	_mob(w, 150.0)
	_mob(w, 200.0)
	var events := _tick(w)
	assert_eq(_of(events, "cast").size(), 1)
	for tick in 60:
		w.step(DT, MoveInput.new())
		events.append_array(w.drain_events())
	assert_eq(_hit_slots(events, "recoil_shot").size(), 2, "the bullet pierced the first mob")


# --- Grenade ------------------------------------------------------------------------------------------------------------

func test_grenade_is_thrown_on_the_cast_tick_without_a_wind_up_and_lands_after_its_flight() -> void:
	var w := _gunslinger("grenade")
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
	assert_eq(w.runner.casts, 1)


func test_grenade_targets_the_cluster_over_a_nearer_lone_mob() -> void:
	var w := _gunslinger("grenade", 1)
	var lone := _mob(w, 120.0)
	var cluster: Array = [_mob(w, 300.0), _mob(w, 320.0), _mob(w, 340.0)]
	var events := _tick(w)
	var thrown: Dictionary = _of(events, "skill_thrown")[0]
	assert_true(float(thrown.to.x) > w.player.pos.x + 250.0, "aimed at the cluster, not the lone mob")
	var hits := []
	for tick in 120:
		hits.append_array(_hit_slots(_tick(w), "grenade"))
	hits.sort()
	var expect := cluster.duplicate()
	expect.sort()
	assert_eq(hits, expect, "the three clustered mobs, not the lone one (%d)" % lone)
	# With no cluster the nearest mob is the target.
	var single := _gunslinger("grenade", 1)
	var near := _mob(single, 120.0)
	_mob(single, 380.0)
	var thrown2: Dictionary = _of(_tick(single), "skill_thrown")[0]
	assert_near(thrown2.to.x, single.mob_center(near).x, 1e-3, "ties go to the nearest")


func test_grenade_strikes_up_to_its_mob_count_by_rank_inside_the_canonical_blast_box() -> void:
	for case: Array in [[1, 3], [20, 6]]:
		var w := _gunslinger("grenade", case[0])
		var group: Array = []
		for i in 8:
			group.append(_mob(w, 250.0 + 10.0 * i))
		var outside := _mob(w, 390.0)  # 90 px past the first one: outside its 50 px blast reach
		var hits := []
		for tick in 45:
			hits.append_array(_hit_slots(_tick(w), "grenade"))
		assert_eq(hits.size(), case[1], "rank %d strikes %d mobs" % case)
		assert_false(outside in hits)
		assert_eq(w.player_state.mp, w.player_state.max_mp - w.loadout.stats("grenade", case[0]).mp_cost)


func test_grenade_casts_with_a_knuckle_and_with_any_weapon() -> void:
	var w := _gunslinger("grenade")
	_wear(w, STEEL_KNUCKLER)
	assert_eq(w.held_weapon_family(), "knuckle")
	_mob(w, 200.0)
	var events := _tick(w)
	assert_eq(_of(events, "cast", "").size(), 1)
	assert_eq(_of(events, "skill_thrown").size(), 1)
	var hits := []
	for tick in 120:
		hits.append_array(_hit_slots(_tick(w), "grenade"))
	assert_eq(hits.size(), 1)


func test_grenade_throw_range_and_a_scheduled_boss_priority() -> void:
	var w := _gunslinger("grenade")
	_mob(w, 410.0)
	assert_eq(_of(_tick(w), "cast").size(), 0, "beyond the 400 px throw range: waits")
	var boss_world := _gunslinger("grenade")
	var boss := _mob(boss_world, 380.0)
	boss_world.mob_boss[boss] = 0
	boss_world.swarm.steady[boss] = 1
	for dx in [100.0, 110.0, 120.0]:
		_mob(boss_world, dx)
	var thrown: Dictionary = _of(_tick(boss_world), "skill_thrown")[0]
	assert_near(thrown.to.x, boss_world.mob_center(boss).x, 1e-3, "a scheduled boss in reach is the target")


# --- the gun-only skills and the knuckle --------------------------------------------------------------------------------

func test_the_gun_only_skills_do_not_cast_with_a_knuckle() -> void:
	for key: String in GUN_ONLY:
		var w := _gunslinger(key)
		_wear(w, STEEL_KNUCKLER)
		var mp: int = w.player_state.mp
		_mob(w, 100.0)
		_mob(w, -100.0)
		var events := _tick(w)
		assert_eq(_of(events, "cast").size(), 0, key + " needs a gun")
		assert_eq(w.player_state.mp, mp)
		assert_eq(w.player.pos.x, 400.0)
	for key: String in GUN_ONLY:
		assert_eq(_gunslinger(key).book.weapon_families(key), PackedStringArray(["gun"]), key)
	assert_true(_gunslinger("grenade").book.usable_with("grenade", "knuckle"))
	assert_true(_gunslinger("grenade").book.usable_with("grenade", ""))


# --- cards and the advancement draw -------------------------------------------------------------------------------------

func test_every_attack_has_learn_rank_and_a_hit_more_mobs_card_for_the_gunslinger_only() -> void:
	var w := _gunslinger("")
	var upgrades: UpgradePool = w.upgrades
	for key: String in ATTACKS:
		for suffix in ["_new", "_rank"]:
			var c: Dictionary = upgrades.card(key + suffix)
			assert_false(c.is_empty(), key + suffix)
			assert_true(UpgradePool.is_power(c), key + suffix + " is a power card")
			assert_eq(c.requires.jobs.map(func(j: Variant) -> int: return int(j)), [520], key + suffix + " is the Gunslinger's")
		assert_eq(int(upgrades.card(key + "_rank").max_rank), 20)
		var more_id := key + ("_pierce" if key == "recoil_shot" else "_targets")
		var more: Dictionary = upgrades.card(more_id)
		assert_eq(more.kind, "skill_mod")
		assert_true(UpgradePool.is_power(more))
		assert_eq(more.effects[0].stat, "pierce" if key == "recoil_shot" else "count")
		assert_true(float(more.effects[0].value) > 0.0)
	for case: Array in [[510, ""], [500, "gun"], [210, ""]]:
		var other := _gunslinger("")
		other.change_job(case[0], case[1] if case[0] == 500 else "")
		var eligible: Array = other.upgrades.eligible(other)
		for key: String in ATTACKS:
			assert_false(key + "_new" in eligible, "%s is not on offer to job %d" % [key, case[0]])


func test_gun_only_cards_are_offered_only_while_a_gun_is_held() -> void:
	var w := _gunslinger("")
	var eligible: Array = w.upgrades.eligible(w)
	for key: String in ATTACKS:
		assert_has(eligible, key + "_new")
	_wear(w, STEEL_KNUCKLER)
	eligible = w.upgrades.eligible(w)
	for key: String in GUN_ONLY:
		assert_false(key + "_new" in eligible, key + " needs a gun")
	assert_has(eligible, "grenade_new", "Grenade takes any weapon")
	for key: String in ATTACKS:
		assert_true(w.learn_skill(key))
	eligible = w.upgrades.eligible(w)
	for key: String in GUN_ONLY:
		assert_false(key + "_rank" in eligible)
		assert_false(key + "_targets" in eligible or key + "_pierce" in eligible)
	assert_has(eligible, "grenade_rank")
	assert_has(eligible, "grenade_targets")
	_wear(w, PISTOL)
	eligible = w.upgrades.eligible(w)
	for key: String in GUN_ONLY:
		assert_has(eligible, key + "_rank")


func test_each_hit_more_card_adds_one_target_or_pierce_per_step_for_three_steps() -> void:
	for key: String in ATTACKS:
		var w := _gunslinger(key)
		var id := key + ("_pierce" if key == "recoil_shot" else "_targets")
		var stat := "pierce" if key == "recoil_shot" else "mob_count"
		var base: int = w.loadout.stats(key)[stat]
		for step in 3:
			assert_true(w.upgrades.apply(id, w), "%s step %d" % [id, step + 1])
			assert_eq(w.loadout.stats(key)[stat], base + step + 1)
		assert_false(id in w.upgrades.eligible(w), "three steps at most")


func _pirate_at_the_window(path: String) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	var setup := RF.with_basic_attack(RF.setup("quiet", 192, data))
	setup.equipment_info.merge(INFO, true)
	var w := RunWorld.new(setup)
	w.change_job(500, path)
	RF.place_player(w, 400)
	w.god = true
	w.progression.level = 29
	w.progression.add_exp(w.progression.exp_to_next())
	w.step(DT, MoveInput.new())
	assert_eq(w.state, RunWorld.CHOOSING_JOB)
	return w


func test_the_gunslinger_advancement_draw_offers_the_four_attacks() -> void:
	for path in ["gun", "knuckle"]:
		var w := _pirate_at_the_window(path)
		assert_true(w.apply_job(520), "Gunslinger on offer to a %s Pirate" % path)
		assert_eq(w.held_weapon_family(), "gun", "the branch's weapon is worn at once")
		var ids: Array = w.pending_cards.map(func(c: Dictionary) -> String: return String(c.id))
		for key: String in ATTACKS:
			assert_has(ids, key + "_new")
		var brawler := _pirate_at_the_window(path)
		assert_true(brawler.apply_job(510))
		var brawler_ids: Array = brawler.pending_cards.map(func(c: Dictionary) -> String: return String(c.id))
		for key: String in ATTACKS:
			assert_false(key + "_new" in brawler_ids, "the Brawler's draw has none of the Gunslinger's attacks")


func test_every_attack_card_choice_teaches_a_working_skill() -> void:
	var w := _pirate_at_the_window("gun")
	assert_true(w.apply_job(520))
	for key: String in ATTACKS:
		assert_true(w.upgrades.apply(key + "_new", w), key)
		assert_true(w.loadout.has(key))
		assert_true(w.book.is_active(key))


# --- the original data ----------------------------------------------------------------------------------------------------

func test_original_v83_tables_boxes_art_and_sounds_resolve_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/520.img")
	assert_true(img != null, "import the Pirate manifest fragment")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"520": img.root})
	var loadout := Loadout.new(book)
	var facts := {
		"invisible_shot": {"mp": [10, 25], "damage": [0.75, 1.70], "mobs": [3, 3], "lt": Vector2(-250, -80), "rb": Vector2(-10, 40)},
		"blank_shot": {"mp": [10, 25], "damage": [0.63, 1.20], "mobs": [3, 3], "lt": Vector2(-250, -80), "rb": Vector2(-20, 30)},
		"grenade": {"mp": [15, 27], "damage": [0.45, 1.40], "mobs": [3, 6], "lt": Vector2(-50, -50), "rb": Vector2(50, 20)},
		"recoil_shot": {"mp": [14, 26], "damage": [0.70, 2.60], "mobs": [1, 1]},
	}
	for key: String in facts:
		assert_eq(book.max_level(key), 20, key)
		for i in 2:
			var st := loadout.stats(key, 1 if i == 0 else 20)
			assert_eq(st.mp_cost, facts[key].mp[i], key + " mpCon")
			assert_near(st.damage_pct, facts[key].damage[i], 1e-6, key)
			assert_eq(st.mob_count, facts[key].mobs[i], key)
			if facts[key].has("lt") and key != "invisible_shot":
				assert_eq(st.box.position, facts[key].lt, key + " box")
				assert_eq(st.box.end, facts[key].rb, key + " box")
		assert_true(lib.sound(String(book.def(key).sounds.use)) != null, key + " sound " + String(book.def(key).sounds.use))
		for field in ["effect", "hit", "ball"]:
			var path := book.visual(key, field, 1, 1)
			if path != "":
				assert_false(lib.anim(path).is_empty(), path)
		assert_true(String(book.def(key).action) == "weapon"
			or lib.node("Character.wz/00002000.img/" + String(book.def(key).action)) is Dictionary, key + " action")
	assert_eq(loadout.stats("invisible_shot", 1).box, Rect2(-250, -80, 500, 120), "mirrored to both sides")
	assert_eq(loadout.stats("blank_shot", 20).box.position.x, -250.0)
	assert_eq(book.canonical("blank_shot", 1, "prop"), 43.0)
	assert_eq(book.canonical("blank_shot", 20, "prop"), 100.0)
	assert_eq(book.canonical("blank_shot", 1, "time"), 1.0)
	assert_eq(book.canonical("blank_shot", 20, "time"), 4.0)
	assert_eq(book.canonical("recoil_shot", 1, "range"), 115.0)
	assert_eq(book.canonical("recoil_shot", 20, "range"), 250.0)
	assert_eq(loadout.stats("recoil_shot", 20).displacement.distance, 250.0)
	assert_false(lib.anim(String(book.def("grenade").burst)).is_empty(), "the blast art")
	for key in ["invisible_shot", "blank_shot", "recoil_shot"]:
		assert_eq(book.weapon_families(key), PackedStringArray(["gun"]), key + " WZ weapon 49")
	assert_eq(book.weapon_families("grenade"), PackedStringArray(), "Grenade names no weapon")
	assert_eq(Array(lib.missing), [])
	lib.free()
