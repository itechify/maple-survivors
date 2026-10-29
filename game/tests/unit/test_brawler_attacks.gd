extends TestCase
## The Brawler's attacks (spec #168 ticket #191, docs/GAME_DESIGN.md 7.18): Backspin Blow 5101002 (slides away, up to
## 3 mobs, stun), Double Uppercut 5101003 (2 hits, one mob, stun) and Corkscrew Blow 5101004 (a charge toward the mob
## that strikes up to 3 mobs on the way). The Brawler is stood directly (RF.as_job; #284 removed advancement).
## B4 #416 moved the three into skills/buccaneer.json: eight ranks on WZ levels 3, 5, 8, 10, 13, 15, 18, 20, no weapon gate, the
## new cooldowns, no legacy cards (the port itself is test_buccaneer_brawler.gd; this file keeps the seeded behaviour coverage).
## Shipping data through public RunWorld casts on a flat synthetic ground, seeded
## and fixed-tick; the original-data checks at the end use the private asset cache and SKIP without it.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100
const GROUND := {"x1": 0, "y1": 0, "x2": 1000, "y2": 0}
const KNUCKLE := 1482000
const PISTOL := 1492000
const SKILLS := ["backspin_blow", "double_uppercut", "corkscrew_blow"]
const PRIME_HANDS := 1482004
## The WZ level each of the eight ranks reads.
const LEVELS := [3, 5, 8, 10, 13, 15, 18, 20]
## Corkscrew Blow: the WZ reach (= the charge) at those levels.
const REACH := [110.0, 120.0, 130.0, 140.0, 160.0, 170.0, 180.0, 200.0]
## Synthetic Character.wz info; the knuckle borrows the synthetic "mace" swing so Double Uppercut has an envelope.
const INFO := {
	KNUCKLE: {"incPAD": 18, "attackSpeed": 5, "tuc": 7, "afterImage": "mace", "sfx": "mace"},
	PISTOL: {"incPAD": 13, "attackSpeed": 5, "tuc": 7},
	PRIME_HANDS: {"reqJob": 16, "reqLevel": 30, "reqSTR": 60, "reqDEX": 30, "incPAD": 34, "attackSpeed": 5, "tuc": 7,
		"afterImage": "mace", "sfx": "mace"},
}


## A Lv 30 Brawler (first job on `path`) on a flat ground at y = 0, standing at x facing right, holding the weapon of
## its path, knowing only `key` at `rank` (none when ""). Mobs get a tiny hitbox and do not move.
func _brawler(key := "", rank := 1, x := 400.0, path := "knuckle", segments: Array = [GROUND]) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", 191, data))
	setup.equipment_info.merge(INFO, true)
	setup.map_img = RF.map_from_segments(segments)
	setup["job"] = 500 # no start skills
	var w := RunWorld.new(setup)
	RF.as_job(w, 500, path)
	w.progression.level = 30
	RF.as_job(w, 510)
	var family := "knuckle" if path == "knuckle" else "gun"
	if w.held_weapon_family() != family:
		var ids: Array = w.equipment.inventory.map(func(i: Dictionary) -> int: return int(i.id))
		assert_eq(w.equip_item(ids.find(KNUCKLE if path == "knuckle" else PISTOL)), "")
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0.0
	w.player.place(Vector2(x, 0), w.fhm)
	w.player.facing = 1
	w.update_view()
	w.god = true
	if key != "":
		assert_true(w.learn_skill(key), "learn " + key)
		w.loadout.set_rank(key, rank)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, x: float) -> int:
	return RF.put_mob(w, MOB, x, -5.0, 10000.0)


## One cast scan: rebuild the mob grid, run the skill runner once, return the events.
func _cast(w: RunWorld) -> Array:
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	w.drain_events()
	w.runner.step(DT, w)
	return w.drain_events()


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


func _hit_slots(events: Array) -> Array:
	return _of(events, "mob_hit").map(func(e: Dictionary) -> int: return int(e.mob))


func _stunned(w: RunWorld, slot: int) -> float:
	return w.swarm.status_time(slot, MobSwarm.STUN)


# --- the data: rank tables, costs, counts ------------------------------------------------------------------------------

func test_the_three_skills_carry_the_v83_tables_by_rank() -> void:
	var facts := {
		"backspin_blow": {"pct": [1.04, 2.40], "mobs": 3, "lines": 1},
		"double_uppercut": {"pct": [1.20, 2.90], "mobs": 1, "lines": 2},
		"corkscrew_blow": {"pct": [1.65, 4.20], "mobs": 3, "lines": 1},
	}
	var w := _brawler()
	for key: String in facts:
		assert_true(w.book.has(key), key)
		assert_eq(w.book.max_level(key), 20)
		assert_eq(w.book.max_rank(key), 8, key + " has eight ranks")
		assert_eq(w.book.weapon_families(key), PackedStringArray(), key + " has no weapon gate")
		for r in [1, 8]:
			var st := w.loadout.stats(key, r)
			assert_near(st.damage_pct, facts[key].pct[0 if r == 1 else 1], 1e-6, "%s damage at rank %d" % [key, r])
			assert_eq(strike_count(st), facts[key].mobs, "%s mobs" % key)
			assert_eq(st.attack_count, facts[key].lines, "%s lines" % key)
			assert_eq(st.damage_type, "physical")


func strike_count(st: Dictionary) -> int:
	return SkillRunner.strike_count(st)


func test_damage_percent_follows_the_mapped_canonical_level_every_rank() -> void:
	var w := _brawler()
	for r in range(1, 9):
		var lv: int = LEVELS[r - 1]
		assert_near(w.loadout.stats("backspin_blow", r).damage_pct, (80.0 + 8.0 * lv) / 100.0, 1e-6, "backspin %d" % r)
		assert_near(w.loadout.stats("double_uppercut", r).damage_pct, (90.0 + 10.0 * lv) / 100.0, 1e-6, "uppercut %d" % r)
		assert_near(w.loadout.stats("corkscrew_blow", r).damage_pct, (120.0 + 15.0 * lv) / 100.0, 1e-6, "corkscrew %d" % r)


func test_displacement_blocks_resolve_direction_when_and_distance_by_rank() -> void:
	var w := _brawler()
	assert_eq(w.loadout.stats("double_uppercut").displacement, {}, "Double Uppercut stands still")
	for r in [1, 8]:
		assert_eq(w.loadout.stats("backspin_blow", r).displacement,
			{"direction": "away", "when": "after", "distance": 100.0})
	for r in range(1, 9):
		var d: Dictionary = w.loadout.stats("corkscrew_blow", r).displacement
		assert_eq(d, {"direction": "toward", "when": "during", "distance": REACH[r - 1]}, "corkscrew rank %d" % r)
		assert_near(-w.loadout.stats("corkscrew_blow", r).box.position.x, REACH[r - 1], 1e-6, "box reach matches the charge")


# --- Backspin Blow -----------------------------------------------------------------------------------------------------

func test_backspin_blow_hits_the_three_nearest_mobs_and_slides_away() -> void:
	var w := _brawler("backspin_blow")
	var near := _mob(w, 450.0)
	var second := _mob(w, 480.0)
	var third := _mob(w, 520.0)
	var fourth := _mob(w, 535.0)
	var far := _mob(w, 600.0)
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(_hit_slots(events), [near, second, third], "the 3 nearest mobs, one line each")
	assert_false(fourth in _hit_slots(events) or far in _hit_slots(events))
	assert_near(w.player.pos.x, 300.0, 1e-6, "100 px away from the nearest mob (it is on the right)")
	assert_eq(w.player.facing, 1, "still facing the mob it backed away from")
	assert_true(int(_of(events, "mob_hit")[0].damage) > 0)


func test_backspin_blow_slides_the_other_way_for_a_mob_on_the_left_and_acts_on_both_sides() -> void:
	var w := _brawler("backspin_blow")
	var behind := _mob(w, 330.0)
	var events := _cast(w)
	assert_eq(_hit_slots(events), [behind], "the canonical box lies behind the facing: it strikes around the character")
	assert_near(w.player.pos.x, 500.0, 1e-6, "away from a mob on the left means right")
	assert_eq(w.player.facing, -1, "turned to the mob it backed away from")


func test_backspin_blow_stops_at_the_platform_edge_and_a_wall_and_still_strikes() -> void:
	var edge := _brawler("backspin_blow", 1, 960.0)
	var m := _mob(edge, 900.0)
	var events := _cast(edge)
	assert_eq(_hit_slots(events), [m])
	assert_near(edge.player.pos.x, 1000.0, 1e-6, "stopped at the edge instead of walking off")
	var walled := _brawler("backspin_blow", 1, 400.0, "knuckle", [GROUND, {"x1": 450, "y1": 0, "x2": 450, "y2": -80}])
	var left := _mob(walled, 340.0)
	events = _cast(walled)
	assert_eq(_hit_slots(events), [left])
	assert_near(walled.player.pos.x, 450.0 - FootholdMap.EPS, 1e-4, "stopped short of the wall")


func test_backspin_blow_stuns_every_struck_mob_for_one_second_and_only_those() -> void:
	for r in [1, 8]:
		var w := _brawler("backspin_blow", r)
		var hit := _mob(w, 450.0)
		var also := _mob(w, 500.0)
		var outside := _mob(w, 700.0)
		_cast(w)
		assert_near(_stunned(w, hit), 1.0, 1e-6, "rank %d: stunned for the canonical time" % r)
		assert_near(_stunned(w, also), 1.0, 1e-6)
		assert_near(_stunned(w, outside), 0.0, 1e-6, "an unstruck mob is not stunned")
		assert_false(w.swarm.can_act(hit), "a stunned mob cannot attack")
		for tick in 61:
			w.step(DT, MoveInput.new())
		assert_near(_stunned(w, hit), 0.0, 1e-6, "the stun ends after a second")


func test_a_boss_is_struck_but_never_stunned() -> void:
	var w := _brawler("backspin_blow")
	var boss := _mob(w, 450.0)
	w.swarm.steady[boss] = 1
	var hp := w.swarm.hp[boss]
	var events := _cast(w)
	assert_eq(_hit_slots(events), [boss])
	assert_true(w.swarm.hp[boss] < hp, "damage still lands")
	assert_near(_stunned(w, boss), 0.0, 1e-6, "bosses resist the stun")


func test_backspin_blow_in_the_air_casts_without_moving() -> void:
	var w := _brawler("backspin_blow")
	w.player.place(Vector2(400, -60), w.fhm)
	assert_eq(w.player.fh, -1)
	var m := _mob(w, 450.0)
	w.swarm.y[m] = -60.0
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(w.player.pos.x, 400.0, "no displacement in the air")


# --- Double Uppercut ---------------------------------------------------------------------------------------------------

func test_double_uppercut_lands_two_hits_on_one_mob_and_stuns_once_for_a_second() -> void:
	var w := _brawler("double_uppercut")
	var first := _mob(w, 450.0)
	var second := _mob(w, 460.0)
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_eq(_hit_slots(events), [first, first], "two lines on the one nearest mob")
	assert_near(_stunned(w, first), 1.0, 1e-6, "two stuns keep the one second, they do not add up")
	assert_near(_stunned(w, second), 0.0, 1e-6)
	assert_eq(w.player.pos.x, 400.0, "Double Uppercut does not move")
	var top := _brawler("double_uppercut", 8)
	_mob(top, 450.0)
	assert_eq(_of(_cast(top), "cast").size(), 1, "rank 8 casts too")


func test_double_uppercut_strikes_nothing_out_of_the_knuckles_reach_and_does_not_cast() -> void:
	var w := _brawler("double_uppercut")
	_mob(w, 700.0)
	assert_true(_of(_cast(w), "cast").is_empty())


func test_double_uppercut_damage_scales_with_its_rank() -> void:
	var low := _brawler("double_uppercut", 1)
	var high := _brawler("double_uppercut", 8)
	var sums := []
	for w: RunWorld in [low, high]:
		_mob(w, 450.0)
		var total := 0
		for e: Dictionary in _of(_cast(w), "mob_hit"):
			total += int(e.damage)
		sums.append(total)
	assert_true(sums[1] > sums[0] * 2, "rank 8 (290%%) hits far harder than rank 1 (120%%): %s" % [sums])


# --- Corkscrew Blow ----------------------------------------------------------------------------------------------------

func test_corkscrew_blow_charges_toward_the_mob_and_strikes_three_along_the_way() -> void:
	var w := _brawler("corkscrew_blow")
	var a := _mob(w, 440.0)
	var b := _mob(w, 500.0)
	var c := _mob(w, 560.0)
	var d := _mob(w, 595.0)
	var beyond := _mob(w, 700.0)
	var events := _cast(w)
	assert_eq(_of(events, "cast").size(), 1)
	assert_near(w.player.pos.x, 510.0, 1e-6, "rank 1 (WZ level 3) charges its full 110 px toward the mob")
	assert_eq(_hit_slots(events), [a, b, c], "three mobs along the path, nearest first")
	assert_false(d in _hit_slots(events) or beyond in _hit_slots(events))
	assert_eq(_of(events, "cast")[0].pos, Vector2(400, 0), "the cast event reports where the charge began")
	var top := _brawler("corkscrew_blow", 8)
	_mob(top, 590.0)  # inside the 200 px box
	events = _cast(top)
	assert_near(top.player.pos.x, 600.0, 1e-6, "rank 8 (WZ level 20) charges 200 px")
	assert_eq(_hit_slots(events).size(), 1)


func test_corkscrew_blow_charges_left_toward_a_mob_on_the_left() -> void:
	var w := _brawler("corkscrew_blow")
	w.player.facing = -1
	_mob(w, 350.0)
	_cast(w)
	assert_near(w.player.pos.x, 290.0, 1e-6, "110 px to the left")
	assert_eq(w.player.facing, -1)


func test_corkscrew_blow_does_not_cast_for_a_mob_behind_or_out_of_reach() -> void:
	var w := _brawler("corkscrew_blow")
	_mob(w, 330.0)  # behind a character that faces right
	_mob(w, 520.0)  # beyond the rank 1 box (110 px)
	assert_true(_of(_cast(w), "cast").is_empty())
	assert_eq(w.player.pos.x, 400.0)


func test_corkscrew_blow_stops_at_the_edge_and_the_wall_and_still_hits_what_it_covered() -> void:
	var edge := _brawler("corkscrew_blow", 8, 900.0)
	var close := _mob(edge, 960.0)
	var events := _cast(edge)
	assert_near(edge.player.pos.x, 1000.0, 1e-6, "stopped at the edge")
	assert_eq(_hit_slots(events), [close])
	var walled := _brawler("corkscrew_blow", 8, 400.0, "knuckle", [GROUND, {"x1": 520, "y1": 0, "x2": 520, "y2": -80}])
	var near := _mob(walled, 470.0)
	_mob(walled, 740.0)  # past the end of the swept path (the charge ends at the wall, 520 + 200 px of box)
	events = _cast(walled)
	assert_near(walled.player.pos.x, 520.0 - FootholdMap.EPS, 1e-4, "stopped short of the wall")
	assert_eq(_hit_slots(events), [near], "the path ends at the wall")


func test_corkscrew_blow_does_not_stun() -> void:
	var w := _brawler("corkscrew_blow")
	var m := _mob(w, 450.0)
	assert_eq(_hit_slots(_cast(w)), [m])
	assert_near(_stunned(w, m), 0.0, 1e-6)


# --- the held weapon ----------------------------------------------------------------------------------------------------

func test_every_attack_casts_with_a_knuckle_or_a_gun_in_hand() -> void:
	# #284: weapons gate no skill. Double Uppercut strikes inside the held weapon's swing, and the synthetic gun has no
	# swing data, so it is checked with the knuckle only.
	for path: String in ["knuckle", "gun"]:
		for key: String in SKILLS:
			if path == "gun" and key == "double_uppercut":
				continue
			var w := _brawler(key, 1, 400.0, path)
			assert_eq(w.held_weapon_family(), path)
			_mob(w, 450.0)
			assert_eq(_of(_cast(w), "cast").size(), 1, "%s with a %s" % [key, path])


# --- cards and rarity bonuses (B4 #416: the legacy _new/_rank/_targets cards are deleted) -------------------------------------

func test_the_legacy_cards_are_gone_and_an_unplayable_brawler_job_is_offered_no_attack_card() -> void:
	var w := _brawler()
	var eligible := w.upgrades.eligible(w)
	for key: String in SKILLS:
		for suffix in ["_new", "_rank", "_targets"]:
			assert_false(key + suffix in eligible, key + suffix)
		assert_true(w.upgrades.card(key + "_targets").is_empty(), key + "_targets no longer exists")
		assert_true(w.upgrades.card(key + "_new").is_empty(), key + "_new comes from the pool of a playable job (test_buccaneer_brawler)")


func test_a_third_fist_bonus_makes_double_uppercut_land_three_hits_on_one_mob() -> void:
	var w := _brawler("double_uppercut")
	var effect: Dictionary = w.book.def("double_uppercut").rarity_bonuses.unique[0].effects[0]
	w.loadout.add_skill_mod("double_uppercut", String(effect.stat), String(effect.op), float(effect.value))
	var a := _mob(w, 450.0)
	var b := _mob(w, 465.0)
	var events := _cast(w)
	assert_eq(_hit_slots(events), [a, a, a], "three lines on the one nearest mob")
	assert_false(b in _hit_slots(events))


func test_a_boring_screw_bonus_makes_corkscrew_strike_five_mobs() -> void:
	var screw := _brawler("corkscrew_blow")
	var effect: Dictionary = screw.book.def("corkscrew_blow").rarity_bonuses.epic[0].effects[0]
	screw.loadout.add_skill_mod("corkscrew_blow", String(effect.stat), String(effect.op), float(effect.value))
	for x in [440.0, 470.0, 500.0, 530.0, 560.0, 590.0]:
		_mob(screw, x)
	assert_eq(_hit_slots(_cast(screw)).size(), 5, "3 + 2")


func test_the_gunslinger_is_never_offered_the_brawlers_attacks() -> void:
	var w := _brawler("", 1, 400.0, "gun")
	w.set_job(520)
	for key: String in SKILLS:
		assert_false(key + "_new" in w.upgrades.eligible(w), key + " is a Brawler card")


# --- determinism ----------------------------------------------------------------------------------------------------------

func test_the_same_seed_gives_the_same_brawler_run() -> void:
	var digests := []
	for run in 2:
		var w := _brawler("corkscrew_blow")
		for key in ["backspin_blow", "double_uppercut"]:
			w.learn_skill(key)
		for x in [440.0, 480.0, 520.0, 330.0]:
			_mob(w, x)
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		for tick in 600:
			w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
			w.step(DT, MoveInput.new())
			for e: Dictionary in w.drain_events():
				ctx.update(var_to_str(e).to_utf8_buffer())
		ctx.update(var_to_str(w.player.pos).to_utf8_buffer())
		digests.append(ctx.finish().hex_encode())
	assert_eq(digests[0], digests[1])


# --- the original data (private cache) ------------------------------------------------------------------------------------

func test_original_tables_reach_art_actions_and_sounds_resolve_in_the_private_cache() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	var img := lib.img("Skill.wz/510.img")
	assert_true(img != null, "import the Pirate manifest fragment")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"510": img.root})
	var loadout := Loadout.new(book)
	for key: String in SKILLS:
		assert_eq(book.max_level(key), 20, key)
	for r in range(1, 9):
		var lv: int = LEVELS[r - 1]
		var node := book.level_node("corkscrew_blow", lv)
		assert_near(loadout.stats("corkscrew_blow", r).displacement.distance, -float(node.lt["$v"][0]), 1e-6,
			"the charge equals the WZ reach at level %d (rank %d)" % [lv, r])
		assert_near(loadout.stats("backspin_blow", r).damage_pct, 0.80 + 0.08 * lv, 1e-6)
		assert_near(loadout.stats("double_uppercut", r).damage_pct, 0.90 + 0.10 * lv, 1e-6)
		assert_near(loadout.stats("corkscrew_blow", r).damage_pct, 1.20 + 0.15 * lv, 1e-6)
		assert_eq(loadout.stats("double_uppercut", r).attack_count, 2, "the string attackCount parses")
		assert_eq(strike_count(loadout.stats("backspin_blow", r)), 3)
		assert_eq(strike_count(loadout.stats("corkscrew_blow", r)), 3)
		assert_eq(strike_count(loadout.stats("double_uppercut", r)), 1)
		for key in ["backspin_blow", "double_uppercut"]:
			assert_near(book.canonical(key, lv, "time"), 1.0, 1e-6, key + " stun time")
			assert_eq(book.canonical(key, lv, "prop", -1.0), -1.0, key + " has no prop: every hit stuns")
	assert_eq(loadout.stats("backspin_blow").box, Rect2(-140, -50, 280, 50), "around: both sides of the canonical 140 px")
	for key: String in SKILLS:
		var d := book.def(key)
		for field in ["hit", "effect"]:
			assert_false(lib.anim(String(d[field])).is_empty(), String(d[field]))
		assert_true(lib.sound(d.sounds.use) != null, key + " use sound")
		assert_true(lib.sound(d.sounds.hit) != null, key + " hit sound")
		assert_true(lib.node("Character.wz/00002000.img/" + String(d.action)) is Dictionary, key + " body action")
	assert_false(lib.anim("Skill.wz/111.img/skill/1111008/mob").is_empty(), "the stun stars")
	assert_eq(Array(lib.missing), [])
	lib.free()
