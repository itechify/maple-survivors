extends TestCase
## Gunslinger attacks (spec #168 ticket #192, docs/GAME_DESIGN.md 7.20): Blank Shot, the one Gunslinger attack that stays on the
## unported Pirate line, through the shipping data on seeded synthetic worlds with fixed ticks (a flat floor, tiny mob bodies that
## never move), then the original v83 numbers and art in the private cache (those SKIP without it). Invisible Shot, Recoil Shot
## and Grenade moved to the `corsair` line with Double Shot and Burst Fire (Corsair C4 #388): their tests are
## test_corsair_fillers.gd, run on job 522.

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
const ATTACKS := ["blank_shot"]


## A Gunslinger (job 520 set directly with its old Lv 30 gun, RF.as_job; #284 removed advancement) on a flat floor at x = 400, a spare knuckle in the Equip tab,
## mob bodies shrunk to 4 x 10 px and standing still, `key` learned at `rank_value`.
func _gunslinger(key: String, rank_value := 1, segments: Array = [GROUND], x := 400.0, p_seed := 192) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""; data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.balance.magnet_radius = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge(INFO, true)
	setup.map_img = RF.map_from_segments(segments)
	var w := RunWorld.new(setup)
	RF.as_job(w, 500, "gun")
	w.progression.level = 30
	RF.as_job(w, 520)
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

func test_cast_rule_count_and_damage_by_rank() -> void:
	# [damage fraction, mob count] at rank 1 and 20 (Skill.wz/520.img).
	var w := _gunslinger("blank_shot")
	for i in 2:
		var st := w.loadout.stats("blank_shot", 1 if i == 0 else 20)
		assert_near(st.damage_pct, [0.63, 1.20][i], 1e-6, "blank_shot damage")
		assert_eq(st.mob_count, 3, "blank_shot mobs")
		assert_eq(st.damage_type, "physical")
	assert_eq(w.loadout.stats("blank_shot").cast_rule, "box")
	assert_eq(w.book.max_rank("blank_shot"), 20)
	assert_eq(w.book.max_level("blank_shot"), 20)


func test_each_attack_casts_once_with_a_target() -> void:
	for key: String in ATTACKS:
		var w := _gunslinger(key)
		_mob(w, 100.0)
		var events := _tick(w)
		assert_eq(_of(events, "cast").size(), 1, key + " cast")


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
		"blank_shot": {"damage": [0.63, 1.20], "mobs": [3, 3], "lt": Vector2(-250, -80), "rb": Vector2(-20, 30)},
	}
	for key: String in facts:
		assert_eq(book.max_level(key), 20, key)
		for i in 2:
			var st := loadout.stats(key, 1 if i == 0 else 20)
			assert_near(st.damage_pct, facts[key].damage[i], 1e-6, key)
			assert_eq(st.mob_count, facts[key].mobs[i], key)
			if facts[key].has("lt"):
				assert_eq(st.box.position, facts[key].lt, key + " box")
				assert_eq(st.box.end, facts[key].rb, key + " box")
		assert_true(lib.sound(String(book.def(key).sounds.use)) != null, key + " sound " + String(book.def(key).sounds.use))
		for field in ["effect", "hit", "ball"]:
			var path := book.visual(key, field, 1, 1)
			if path != "":
				assert_false(lib.anim(path).is_empty(), path)
		assert_true(String(book.def(key).action) == "weapon"
			or lib.node("Character.wz/00002000.img/" + String(book.def(key).action)) is Dictionary, key + " action")
	assert_eq(loadout.stats("blank_shot", 20).box.position.x, -250.0)
	assert_eq(book.canonical("blank_shot", 1, "prop"), 43.0)
	assert_eq(book.canonical("blank_shot", 20, "prop"), 100.0)
	assert_eq(book.canonical("blank_shot", 1, "time"), 1.0)
	assert_eq(book.canonical("blank_shot", 20, "time"), 4.0)
	assert_eq(book.weapon_families("blank_shot"), PackedStringArray(["gun"]), "blank_shot WZ weapon 49")
	assert_eq(Array(lib.missing), [])
	lib.free()
