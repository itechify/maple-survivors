extends TestCase
## Hurricane (3121004, spec #332 ticket B10 #342): the first skill on the burst cast rule. A real definition, synthetic
## Skill.wz-shaped levels (the endpoints are the v83 values: damage 51 -> 100), a Bowmaster (312) holding a bow, fixed
## ticks and a seeded world. The mapped WZ levels of all eight ranks are asserted against the real cache at the bottom.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const BOW := 1452051
const KEY := "hurricane"
const RANK_LEVELS := [4, 8, 12, 15, 19, 23, 27, 30] # tier C: the 30-level mapping every Hero/F-P 30-level skill uses
const TIERS := ["rare", "epic", "unique", "legendary"]


## Synthetic Skill.wz 312.img: Hurricane's own ball and hit, and 30 levels of damage 51 -> 100 (the WZ endpoints).
func _imgs() -> Dictionary:
	var imgs := RF.skill_imgs()
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 6.0, "damage": float(roundi(lerpf(51.0, 100.0, float(lv - 1) / 29.0)))}
	imgs["312"] = {"skill": {"3121004": {"icon": RF._canvas(32, 32), "ball": RF._anim(10, 30.0, 68, 19),
		"hit": {"0": RF._anim(3, 100.0, 56, 58)}, "level": levels}}}
	return imgs


func _world(p_seed := 342) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["212"]["starting_skill"] = ""
	data.jobs_survivor.jobs["212"]["mobility_skill"] = ""
	data.jobs_survivor.jobs["312"]["playable"] = true
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.skill_imgs = _imgs()
	setup.equipment_info.merge({BOW: {"incPAD": 28, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["shoot1", "shoot2"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	var w := RunWorld.new(setup)
	assert_eq(w.wear_new_item(BOW), "")
	RF.place_player(w, 400)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-2, -10, 4, 10)
		mk.move_speed = 0
	w.player.facing = 1
	w.god = true
	w.pending_cards = []
	w.state = RunWorld.PLAYING
	RF.change_job_bare(w, 312)
	w.loadout.ranks.clear()
	w.loadout.order.clear()
	w.learn_skill(KEY)
	w.drain_events()
	return w


func _mob(w: RunWorld, x: float, hp := 100000000.0) -> int:
	var m := RF.put_mob(w, 1110100, x, 195, hp)
	w.swarm.hp[m] = int(hp)
	w.swarm.max_hp[m] = int(hp)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _shots(w: RunWorld) -> int:
	return w.projectiles.active.count(1)


func _ticks(w: RunWorld, n: int) -> void:
	for i in n:
		w.runner.step(DT, w)


# --- the definition ------------------------------------------------------------------------------------------------

func test_definition_follows_the_spec_row() -> void:
	var w := _world()
	var d := w.book.def(KEY)
	assert_eq(int(d.skill_id), 3121004)
	assert_eq(int(d.job), 312)
	assert_eq(String(d.kind), "projectile")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "physical")
	assert_false(d.has("weapon_families"), "skills have no weapon gate")
	assert_eq(d.cast, {"rule": "burst"})
	assert_eq(d.burst, {"interval": 0.1, "wind_up": 0.4, "retarget": true})
	assert_eq(int(d.count), 12)
	assert_eq(float(d.cooldown), 6.0)
	assert_eq(float(d.range), 450.0)
	assert_eq(float(d.speed), 900.0)
	assert_eq(float(d.radius), 6.0)
	assert_eq(int(d.pierce), 0)
	assert_eq(String(d.ball), "Skill.wz/312.img/skill/3121004/ball", "its own ball, not the ammo's sprite")
	assert_eq(String(d.hit), "Skill.wz/312.img/skill/3121004/hit/0")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/3121004/Use")
	assert_eq(String(d.sounds.hit), "Sound.wz/Skill.img/3121004/Hit")
	assert_eq(w.book.max_rank(KEY), 8)
	assert_eq(w.book.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), RANK_LEVELS)


# --- the cast ------------------------------------------------------------------------------------------------------

func test_twelve_arrows_at_the_wind_up_then_every_tenth_of_a_second() -> void:
	var w := _world()
	_mob(w, 700)
	_ticks(w, 1)
	assert_eq(w.runner.casts, 1)
	assert_true(float(w.runner.cooldowns[KEY]) > 5.9)
	assert_eq(_shots(w), 0, "nothing flies during the wind-up")
	_ticks(w, 23)
	assert_eq(_shots(w), 0)
	_ticks(w, 1)
	assert_eq(_shots(w), 1, "0.4 s after admission")
	for k in range(2, 13):
		_ticks(w, 5)
		assert_eq(_shots(w), k - 1, "arrow %d is not due yet" % k)
		_ticks(w, 1)
		assert_eq(_shots(w), k, "arrow %d is due at 0.4 s + %d x 0.1 s" % [k, k - 1])
	_ticks(w, 60)
	assert_eq(_shots(w), 12, "twelve arrows, no thirteenth")
	assert_eq(w.runner.casts, 1)
	assert_false(w.runner.bursts.has_skill(KEY))


func test_the_stance_is_held_for_the_whole_stream() -> void:
	var w := _world()
	_mob(w, 400)
	_ticks(w, 1)
	assert_eq(w.upkeep.cast_action, "shoot1", "the bow's shooting stance")
	assert_true(w.upkeep.cast_left >= 1.49, "held until the twelfth arrow (1.5 s): %f" % w.upkeep.cast_left)
	var more := _world()
	more.loadout.add_skill_mod(KEY, "count", "add", 4)
	_mob(more, 400)
	_ticks(more, 1)
	assert_true(more.upkeep.cast_left >= 1.89, "sixteen arrows hold 1.9 s: %f" % more.upkeep.cast_left)


# --- damage by rank ------------------------------------------------------------------------------------------------

func test_damage_percent_follows_the_mapped_level_of_each_rank() -> void:
	var w := _world()
	var imgs := _imgs()
	var levels: Dictionary = imgs["312"].skill["3121004"].level
	var previous := 0.0
	for rank in range(1, 9):
		var pct := float(w.loadout.stats(KEY, rank).damage_pct)
		assert_near(pct, float(levels[str(RANK_LEVELS[rank - 1])].damage) / 100.0, 1e-6, "rank %d" % rank)
		assert_true(pct > previous, "damage rises with rank")
		previous = pct
	assert_near(float(w.loadout.stats(KEY, 8).damage_pct), 1.0, 1e-6, "rank 8 is 100% per arrow")


func test_every_arrow_hits_one_monster_and_a_higher_rank_hits_harder() -> void:
	var totals := []
	for rank in [1, 8]:
		var w := _world()
		w.loadout.set_rank(KEY, rank)
		var m := _mob(w, 380, 1.0e9)
		for tick in 150:
			w.step(DT, MoveInput.new())
		var hits := 0
		for e: Dictionary in w.drain_events():
			if e.type == "mob_hit" and String(e.get("skill", "")) == KEY:
				hits += 1
		assert_eq(hits, 12, "twelve arrows land on the one monster at rank %d" % rank)
		totals.append(int(w.swarm.max_hp[m]) - int(w.swarm.hp[m]))
	assert_true(totals[1] > totals[0] * 1.5, "rank 8 (100%%) out-damages rank 1 (about 56%%): %s" % str(totals))


# --- rarity bonuses ------------------------------------------------------------------------------------------------

func test_count_modifier_adds_four_arrows() -> void:
	var w := _world()
	w.loadout.add_skill_mod(KEY, "count", "add", 4)
	_mob(w, 700)
	_ticks(w, 1 + 24 + 15 * 6)
	assert_eq(_shots(w), 16, "the Final Attack bonus: sixteen arrows")
	_ticks(w, 60)
	assert_eq(_shots(w), 16)


func test_the_stream_follows_a_walking_character() -> void:
	var w := _world()
	_mob(w, 800)
	_ticks(w, 1 + 24)
	var first := w.projectiles.x[0]
	for step in 5:
		_ticks(w, 6)
		RF.place_player(w, 400 + 30 * (step + 1))
	_ticks(w, 6)
	assert_eq(_shots(w), 7)
	assert_true(w.projectiles.x[6] > first + 100.0, "the later arrows leave from where the character walked to")


func test_rarity_cards_apply_the_bonus_of_their_tier() -> void:
	for tier: String in TIERS:
		var w := _world()
		w.loadout.ranks.clear()
		w.loadout.order.clear()
		var before_cd := float(w.loadout.stats(KEY).cooldown)
		w.upgrades.apply(KEY + "_new", w, tier)
		var card := w.upgrades.choice_card(KEY + "_rank", w, tier)
		assert_false(card.get("rarity_bonus", {}).is_empty(), tier + " carries a bonus")
		var st := w.loadout.stats(KEY)
		match tier:
			"rare":
				assert_near(w.loadout.skill_stat(KEY, "damage", 1.0), 1.2)
				assert_eq(int(st.count), 12)
			"epic":
				assert_near(float(st.cooldown), before_cd * 0.88, 1e-6)
				assert_eq(int(st.count), 12)
			"unique":
				assert_eq(int(st.count), 16, "Final Attack: sixteen arrows")
				assert_near(w.loadout.skill_stat(KEY, "damage", 1.0), 1.0)
			"legendary":
				assert_eq(int(st.count), 16)
				assert_near(w.loadout.skill_stat(KEY, "damage", 1.0), 1.2)


func test_each_tier_changes_the_arrows_that_land() -> void:
	var base := _land(_world())
	var rare := _world()
	rare.loadout.add_skill_mod(KEY, "damage", "mul", 1.2)
	assert_true(_land(rare).damage > base.damage, "Bow Expert hits harder")
	var epic := _world()
	epic.loadout.add_skill_mod(KEY, "cooldown", "mul", 0.88)
	assert_near(float(epic.loadout.stats(KEY).cooldown), 6.0 * 0.88, 1e-6)
	var unique := _world()
	unique.loadout.add_skill_mod(KEY, "count", "add", 4)
	assert_eq(_land(unique).arrows, base.arrows + 4)
	var legendary := _world()
	legendary.loadout.add_skill_mod(KEY, "count", "add", 4)
	legendary.loadout.add_skill_mod(KEY, "damage", "mul", 1.2)
	var l := _land(legendary)
	assert_eq(l.arrows, base.arrows + 4)
	assert_true(l.damage > _land(unique).damage)


## One cast against a high-HP monster in reach: arrows landed and damage dealt after the stream has flown.
func _land(w: RunWorld) -> Dictionary:
	var m := _mob(w, 380)
	for tick in 210:
		w.step(DT, MoveInput.new())
		if w.runner.casts >= 1:
			w.runner.cooldowns[KEY] = 1.0e9
	var arrows := 0
	for e: Dictionary in w.drain_events():
		if e.type == "mob_hit" and String(e.get("skill", "")) == KEY:
			arrows += 1
	return {"arrows": arrows, "damage": int(w.swarm.max_hp[m]) - int(w.swarm.hp[m])}


# --- the real cache ------------------------------------------------------------------------------------------------

func test_real_cache_ranks_read_the_mapped_wz_levels_for_all_eight_ranks() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/312.img")
	assert_true(img != null, "the 312 book is imported")
	if img == null:
		library.free()
		return
	var imgs := {"312": img.root}
	var b := SkillBook.from_data(DataRepo.load_all().skills, imgs)
	var node: Dictionary = img.root.skill["3121004"]
	# The v83 values the spec quotes: 54 / 75 / 100 at ranks 1 / 4 / 8, endpoints 51 and 100 on levels 1 and 30.
	assert_eq(int(node.level["1"].damage), 51)
	assert_eq(int(node.level["30"].damage), 100)
	assert_eq(b.rank_table(KEY).map(func(v: Variant) -> int: return int(v)), RANK_LEVELS)
	var lo := Loadout.new(b)
	lo.add_skill(KEY)
	var previous := 0.0
	for rank in range(1, 9):
		var lv: int = RANK_LEVELS[rank - 1]
		assert_eq(b.canonical_level(KEY, rank), lv)
		var row: Dictionary = node.level[str(lv)]
		var st := lo.stats(KEY, rank)
		assert_near(float(st.damage_pct), float(row.damage) / 100.0, 1e-6, "rank %d" % rank)
		assert_true(float(st.damage_pct) > previous)
		previous = float(st.damage_pct)
		assert_eq(int(st.mob_count), 1, "one monster per arrow (the node has no mobCount)")
		assert_eq(int(st.attack_count), 1, "no attackCount")
		assert_eq(int(st.count), 12)
	assert_near(float(lo.stats(KEY, 1).damage_pct), 0.54, 1e-6)
	assert_near(float(lo.stats(KEY, 4).damage_pct), 0.75, 1e-6)
	assert_near(float(lo.stats(KEY, 8).damage_pct), 1.00, 1e-6)
	library.free()


func test_real_cache_has_the_art_and_sounds_the_definition_names() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var d: Dictionary = DataRepo.load_all().skills.skills[KEY]
	for path: String in [String(d.ball), String(d.hit), String(d.icon), "Skill.wz/312.img/skill/3121004/prepare",
			"Skill.wz/312.img/skill/3121004/keydown", "Skill.wz/312.img/skill/3121004/keydownend"]:
		var anim := library.anim(path)
		assert_true(anim != null and not anim.is_empty(), path)
	assert_eq(library.anim(String(d.ball)).frame_count(), 10, "the ten-frame ball")
	for sound: String in [String(d.sounds.use), String(d.sounds.hit)]:
		assert_true(library.find(sound) != null, sound)
	library.free()


# --- presentation events -------------------------------------------------------------------------------------------

func _stream_events(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return String(e.type).begins_with("burst_"))


func test_the_stream_announces_its_start_and_its_end() -> void:
	var w := _world()
	_mob(w, 700)
	_ticks(w, 1)
	var started := _stream_events(w)
	assert_eq(started.size(), 1)
	assert_eq(started[0].type, "burst_start")
	assert_eq(started[0].skill, KEY)
	assert_near(float(started[0].wind_up), 0.4)
	assert_near(float(started[0].span), 1.5)
	assert_eq(int(started[0].facing), 1)
	_ticks(w, 89)
	assert_eq(_stream_events(w).size(), 0, "no end while arrows are still to come")
	_ticks(w, 1)
	var ended := _stream_events(w)
	assert_eq(ended.size(), 1)
	assert_eq(ended[0].type, "burst_end")
	assert_eq(ended[0].skill, KEY)


func test_a_cancelled_stream_still_ends_once() -> void:
	for mode in ["dead", "clear"]:
		var w := _world()
		_mob(w, 700)
		_ticks(w, 10)
		w.drain_events()
		if mode == "dead":
			w.player_state.dead = true
		else:
			w.runner.clear_pending(w)
		_ticks(w, 3)
		var ended := _stream_events(w).filter(func(e: Dictionary) -> bool: return e.type == "burst_end")
		assert_eq(ended.size(), 1, mode)


class FxLog extends FxRenderer:
	var calls: Array = []
	var _next := 10
	func play(path: String, _pos: Vector2, flip: bool = false, _follow: Node2D = null,
			_offset: Vector2 = Vector2.ZERO, _hold: bool = false) -> int:
		_next += 1
		calls.append(["play", path.get_file(), _next, flip])
		return _next
	func play_repeating(path: String, _pos: Vector2, seconds: float, flip: bool = false,
			_follow: Node2D = null, _offset: Vector2 = Vector2.ZERO) -> int:
		_next += 1
		calls.append(["repeat", path.get_file(), _next, flip, is_inf(seconds)])
		return _next
	func fit(i: int, seconds: float) -> void:
		calls.append(["fit", i, seconds])
	func stop(i: int) -> void:
		calls.append(["stop", i])


class ArtScene extends RunScene:
	func handle_events(batch: Array) -> void:
		super.handle_events(batch.filter(func(e: Dictionary) -> bool: return String(e.type).begins_with("burst_")))


func test_the_scene_plays_prepare_then_keydown_then_keydownend() -> void:
	var s := ArtScene.new()
	var log := FxLog.new()
	s.fx = log
	s.world = _world()
	_mob(s.world, 700)
	for tick in 1:
		s.world.step(DT, MoveInput.new())
	s.handle_events(s.world.drain_events())
	assert_eq(log.calls, [["play", "prepare", 11, true], ["fit", 11, 0.4]], "the wind-up art, fitted to 0.4 s")
	for tick in 22:
		s.world.step(DT, MoveInput.new())
		s._after_tick()
	assert_eq(log.calls.size(), 2, "still preparing before the first arrow")
	for tick in 3:
		s.world.step(DT, MoveInput.new())
		s._after_tick()
	assert_eq(log.calls.slice(2), [["stop", 11], ["repeat", "keydown", 12, true, true]], "the loop starts with the first arrow")
	for tick in 90:
		s.world.step(DT, MoveInput.new())
		s._after_tick()
		s.handle_events(s.world.drain_events())
	assert_eq(log.calls.slice(4), [["stop", 12], ["play", "keydownend", 13, true]], "the end art when the stream is over")
	log.free()
	s.free()


func test_a_dropped_stream_stops_its_art() -> void:
	var s := ArtScene.new()
	var log := FxLog.new()
	s.fx = log
	s.world = _world()
	_mob(s.world, 700)
	s.world.step(DT, MoveInput.new())
	s.handle_events(s.world.drain_events())
	s.world.runner.step(DT, s.world) # the hidden / death / clear path drops the unfinished stream
	s.world.runner.clear_pending(s.world)
	s.handle_events(s.world.drain_events())
	assert_eq(log.calls.slice(2), [["stop", 11], ["play", "keydownend", 12, true]])
	log.free()
	s.free()


func test_real_cache_prepare_art_is_fitted_to_the_wind_up() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var fx := FxRenderer.new()
	fx.library = library
	var path := "Skill.wz/312.img/skill/3121004/prepare"
	var anim := library.anim(path)
	assert_near(anim.total, 0.98, 0.001, "14 frames at 70 ms")
	var slot := fx.play(path, Vector2.ZERO)
	fx.fit(slot, 0.4)
	assert_near(fx.rate_of(slot), anim.total / 0.4, 1e-4)
	fx.advance(0.39)
	assert_eq(fx.active_count(), 1, "still playing just before 0.4 s")
	fx.advance(0.02)
	assert_eq(fx.active_count(), 0, "one pass takes 0.4 s")
	fx.free()
	library.free()


func test_real_lethal_damage_ends_the_stream_once_and_stops_scene_art() -> void:
	var s := ArtScene.new()
	var log := FxLog.new()
	s.fx = log
	s.world = _world()
	_mob(s.world, 700)
	s.world.runner.step(DT, s.world)
	s.handle_events(s.world.drain_events())
	s.world.god = false
	s.world.take_hit(1e9, true, "", s.world.player.pos - Vector2(100, 0), {"accuracy": 1e9})
	for tick in 120:
		s.world.step(DT, MoveInput.new())
	var events := s.world.drain_events()
	assert_eq(s.world.state, RunWorld.DEAD)
	assert_false(s.world.runner.bursts.has_skill(KEY))
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "burst_end").size(), 1)
	s.handle_events(events)
	assert_eq(log.calls.slice(2), [["stop", 11], ["play", "keydownend", 12, true]])
	log.free()
	s.free()

func test_wind_up_art_without_a_loop_finishes_safely() -> void:
	var s := ArtScene.new()
	var log := FxLog.new()
	s.fx = log
	s.world = _world()
	s.world.book.defs[KEY].burst_art.erase("loop")
	_mob(s.world, 700)
	s.world.step(DT, MoveInput.new())
	s.handle_events(s.world.drain_events())
	for tick in 30:
		s.world.step(DT, MoveInput.new())
		s._after_tick()
	assert_eq(log.calls.size(), 3, "only prepare, fit and stop; no absent loop")
	log.free()
	s.free()
