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
	assert_eq(d.weapon_families, ["bow"])
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
