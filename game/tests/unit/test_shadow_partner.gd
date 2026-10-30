extends TestCase
## Night Lord's Shadow Partner (spec #383 NL10 #409, docs/GAME_DESIGN.md 7.94.7): the summon on the echo seam (`summon.echo`),
## the star skills it echoes at the right percent for their class and its rank, the zones and nova it leaves alone, the
## rarity bonuses, and the clone renderer's pure rules (the `special` action mapping and the throw timing). Fixed 1/60 s
## ticks, seeded RNG, a claw in hand. The behaviour tests run on synthetic Skill.wz levels shaped like the originals; the
## real-cache tests at the end call require_cache() and SKIP without the cache.
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MesoTest := preload("res://tests/unit/test_shadow_meso.gd")
const DT := 1.0 / 60.0
const CLAW := 1472000
const KEY := "shadow_partner"
const ATTACK_STARS := ["lucky_seven", "drain"]
const SKILL_STARS := ["avenger", "triple_throw", "shadow_meso"]
const LEVELS_30 := [4, 8, 12, 15, 19, 23, 27, 30]
## rank 1 / 4 / 8 -> the Shadow Partner's x (attack) and y (skill) percent and its lifetime (tier A, Skill.wz 4111002).
const RANKS := [1, 4, 8]
const X_AT := [31.0, 60.0, 80.0]
const Y_AT := [21.0, 29.0, 50.0]
const TIME_AT := [60.0, 120.0, 180.0]
## Tier -> the bonus (the spec's table; Legendary = Unique + damage x1.2).
const BONUSES := {"rare": ["shadow_power", "damage", "mul", 1.2], "epic": ["shadow_booster", "cooldown", "mul", 0.88],
	"unique": ["twin_shadow", "summon_count", "add", 1.0]}


## `x` / `y` / `time` of WZ level `lv` through the recorded points (Lv4 31/21/60, Lv15 60/29/120, Lv30 80/50/180), linear between.
static func _partner_level(lv: int) -> Dictionary:
	var pts_x := {1: 20.0, 4: 31.0, 15: 60.0, 30: 80.0}
	var pts_y := {1: 21.0, 4: 21.0, 15: 29.0, 30: 50.0}
	return {"hs": "h%d" % lv, "x": _along(pts_x, lv), "y": _along(pts_y, lv),
		"time": 60.0 if lv <= 10 else 120.0 if lv <= 20 else 180.0}


static func _along(points: Dictionary, lv: int) -> float:
	var keys: Array = points.keys()
	keys.sort()
	for i in range(1, keys.size()):
		if lv <= keys[i]:
			return roundf(lerpf(points[keys[i - 1]], points[keys[i]], float(lv - keys[i - 1]) / float(keys[i] - keys[i - 1])))
	return points[keys.back()]


func _avenger_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": roundf(lerpf(65.0, 180.0, (lv - 1) / 29.0)),
			"mobCount": 4.0 if lv <= 10 else 5.0 if lv <= 20 else 6.0}
	return levels


func _triple_levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": roundf(lerpf(102.0, 150.0, (lv - 1) / 29.0)), "bulletCount": 3.0}
	return levels


func _zone_levels(extent: float, lo_y: float, hi_y: float) -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = {"hs": "h%d" % lv, "damage": 60.0 + lv, "mobCount": 6.0, "time": 4.0, "prop": 100.0,
			"lt": {"$v": [-extent, lo_y]}, "rb": {"$v": [extent, hi_y]}}
	return levels


## A quiet round of a Night Lord holding a claw: Shadow Partner learned first (it casts alone on the first tick), then `stars`.
## God mode, frozen snail-sized mobs. `partner_rank` is set before the first cast, so the clone is spawned at that rank.
func _world(stars: Array, partner_rank := 1, p_seed := 409) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["412"]["playable"] = true # in this test's data only: NL12 ships the flip
	data.balance.player.hp = 500
	data.balance.regen.hp = 0
	data.balance.player.stats = {"str": 4, "dex": 30, "int": 4, "luk": 100}
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	setup.equipment_info.merge({CLAW: {"incPAD": 22, "attackSpeed": 6, "tuc": 7}}, true)
	for action: String in ["avenger", "swingO1", "alert", "ninjastorm", "alert3"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	var book_411: Dictionary = MesoTest.book_node()
	var levels := {}
	for lv in range(1, 31):
		levels[str(lv)] = _partner_level(lv)
	book_411.skill["4111002"] = {"icon": RF._canvas(32, 32), "level": levels}
	book_411.skill["4111005"] = {"level": _avenger_levels()}
	setup.skill_imgs["411"] = book_411
	setup.skill_imgs["412"] = {"skill": {"4121007": {"weapon": 47, "level": _triple_levels()},
		"4121008": {"weapon": 47, "level": _zone_levels(150.0, -70.0, 30.0)},
		"4121004": {"level": _zone_levels(150.0, -130.0, 70.0)}}}
	setup["job"] = 412
	var w := RunWorld.new(setup)
	RF.place_player(w, 300)
	if w.weapon_id() != CLAW:
		w.wear_new_item(CLAW)
	for mk: MobKind in w.mob_kinds:
		mk.hitbox = Rect2(-20, -60, 40, 60)
		mk.move_speed = 0
		mk.pdd = 0
	w.god = true
	w.loadout.ranks.clear() # not the start skill
	w.loadout.order.clear()
	assert_true(w.learn_skill(KEY), "Shadow Partner is learnable by a Night Lord")
	for star: String in stars:
		assert_true(w.learn_skill(star), "%s is learnable" % star)
	w.loadout.set_rank(KEY, partner_rank)
	w.refresh_player_stats()
	w.drain_events()
	return w


func _mob(w: RunWorld, dx: float, boss := false) -> int:
	var slot := RF.put_mob(w, 2220000 if boss else 1110100, w.player.pos.x + dx, 190.0, 100000.0)
	w.swarm.hp[slot] = 100000000
	w.swarm.max_hp[slot] = 100000000
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return slot


func _ticks(w: RunWorld, n: int) -> void:
	for t in n:
		w.step(DT, MoveInput.new())


func _events(w: RunWorld, type: String, skill := "") -> Array:
	return w.events.filter(func(e: Dictionary) -> bool: return e.type == type and (skill == "" or e.get("skill", "") == skill))


## dmg_max of every shot in flight, ascending.
func _flying(w: RunWorld) -> Array:
	var out := []
	for i in w.projectiles.capacity():
		if w.projectiles.active[i] != 0:
			out.append(w.projectiles.dmg_max[i])
	out.sort()
	return out


func _drop_flying(w: RunWorld) -> void:
	for i in w.projectiles.capacity():
		w.projectiles.active[i] = 0


## Spawns the clone (tick 1, no monster), settles it, adds a monster `at` px ahead and casts the star on the next tick.
## `at` keeps the monster in reach of a clone that trails the owner by 55 px (Lucky Seven's reach is 250 px).
func _cast_star(w: RunWorld, at := 150.0) -> int:
	_ticks(w, 40)
	var m := _mob(w, at)
	_ticks(w, 1)
	return m


# --- the definition ---------------------------------------------------------------------------------------------------

func test_the_definition_is_the_echo_summon_of_the_spec() -> void:
	var w := _world([])
	var d := w.book.def(KEY)
	assert_eq(int(d.skill_id), 4111002)
	assert_eq(String(d.book), "411")
	assert_eq(String(d.kind), "summon")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.cast.rule), "summon")
	assert_near(float(d.cooldown), 50.0, 0.0001)
	assert_eq(String(d.action), "alert")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4111002/Use")
	assert_eq(String(d.effect), "Skill.wz/411.img/skill/4111002/effect")
	assert_eq(d.cast_visuals.size(), 1)
	assert_eq(String(d.cast_visuals[0].path), "Skill.wz/411.img/skill/4111002/effect0")
	var s: Dictionary = d.summon
	assert_eq(s.echo, {"attack_field": "x", "skill_field": "y", "delay": 0.25,
		"path": "Skill.wz/411.img/skill/4111002/special"})
	assert_near(float(s.follow_speed), 200.0, 0.0001)
	assert_near(float(s.follow_distance), 55.0, 0.0001)
	assert_near(float(s.teleport_distance), 600.0, 0.0001)
	assert_near(float(s.ordinal_spread), 40.0, 0.0001)
	assert_false(s.has("attack"), "a clone has no attack node")
	assert_eq(String(d.text.h).count("{"), 3, "the level line names x, y and time")


func test_it_is_in_the_pool_a_night_lord_learns_and_only_the_stars_carry_the_echo_flag() -> void:
	var w := _world([])
	assert_true("shadow_partner" in w.jobs.skill_pool(412), "in the skill pool")
	var echoing := []
	for key: String in w.book.defs.keys():
		if w.book.def(key).has("echo") and String(w.book.def(key).get("book", "")) in ["400", "410", "411", "412"]:
			echoing.append(key)
	echoing.sort()
	assert_eq(echoing, ["avenger", "drain", "lucky_seven", "shadow_meso", "triple_throw"], "the zones and the nova never echo")
	for key: String in ATTACK_STARS:
		assert_eq(String(w.book.def(key).echo.class), "attack", key)
	for key: String in SKILL_STARS:
		assert_eq(String(w.book.def(key).echo.class), "skill", key)


func test_a_cast_summons_one_clone_that_lives_time_seconds_by_rank() -> void:
	for i in 3:
		var w := _world([], RANKS[i])
		_ticks(w, 2)
		var s := w.runner.summons
		assert_eq(s.clones().size(), 1, "rank %d" % RANKS[i])
		assert_near(s.left[s.clones()[0]], TIME_AT[i], 0.1, "rank %d lives %d s" % [RANKS[i], TIME_AT[i]])
		assert_eq(_events(w, "summon_spawn", KEY).size(), 1)
		var cast := _events(w, "cast", KEY)
		assert_eq(cast.size(), 1)
		assert_eq(String(cast[0].effect), "Skill.wz/411.img/skill/4111002/effect", "the spawn art plays on the owner")


func test_the_clone_never_strikes_and_a_recast_replaces_it() -> void:
	var w := _world([])
	_mob(w, 30) # inside any follower's box
	_ticks(w, 120)
	assert_eq(_events(w, "summon_attack").size(), 0)
	var s := w.runner.summons
	var first := s.uid[s.clones()[0]]
	s.spawn(w, w.loadout.stats(KEY))
	assert_eq(s.clones().size(), 1, "a recast replaces the clone")
	assert_true(s.uid[s.clones()[0]] != first)


func test_map_transfer_death_and_hidden_clear_or_ignore_the_clone_and_its_echoes() -> void:
	for mode in ["clear", "dead", "hidden"]:
		var w := _world(["lucky_seven"])
		_cast_star(w)
		assert_eq(w.runner.echoes.pending_count(), 2, "%s: two stars, two echoes pending" % mode)
		match mode:
			"clear": w.runner.clear_pending(w)
			"dead": w.player_state.dead = true
			"hidden": w.buffs.start("hidden_test", {"skill_id": 0, "level": 1, "icon": "", "duration": 10.0,
				"buff_stat": "", "buff_value": 0.0, "hidden": true, "pulse_interval": 0.0})
		w.runner.echoes.step(DT, w)
		assert_eq(w.runner.echoes.pending_count(), 0, mode)
		if mode == "clear":
			assert_eq(w.runner.summons.clones().size(), 0, "a map transfer clears the clone")
		_ticks(w, 30)
		assert_eq(_events(w, "echo_cast").size(), 0, mode)


# --- the echoes -------------------------------------------------------------------------------------------------------

func test_every_star_skill_echoes_once_per_shot_at_the_percent_of_its_class_and_the_partners_rank() -> void:
	var shots := {"lucky_seven": 2, "drain": 1, "avenger": 1, "triple_throw": 3, "shadow_meso": 1}
	for key: String in shots:
		for i in 3:
			var w := _world([key], RANKS[i])
			_cast_star(w)
			var owner_shots := _flying(w)
			assert_eq(owner_shots.size(), int(shots[key]), "%s rank %d: the owner's shots" % [key, RANKS[i]])
			assert_eq(w.runner.echoes.pending_count(), int(shots[key]), "%s: one echo per shot" % key)
			_drop_flying(w)
			_ticks(w, 16)
			var echoes := _events(w, "echo_cast", key)
			assert_eq(echoes.size(), int(shots[key]), "%s rank %d: one echo per shot" % [key, RANKS[i]])
			var flying := _flying(w)
			assert_eq(flying.size(), int(shots[key]))
			var pct: float = (X_AT[i] if key in ATTACK_STARS else Y_AT[i]) / 100.0
			assert_near(flying[0] / owner_shots[0], pct, 0.0001, "%s rank %d echoes %d%%" % [key, RANKS[i], roundi(pct * 100.0)])


func test_the_zones_and_the_nova_do_not_echo() -> void:
	for key in ["ninja_ambush", "ninja_storm"]:
		var w := _world([key])
		_cast_star(w, 60.0)
		_ticks(w, 40)
		assert_true(_events(w, "cast", key).size() >= 1, "%s cast" % key)
		assert_eq(_events(w, "echo_cast").size(), 0, key)
		assert_eq(w.runner.echoes.pending_count(), 0, key)


func test_drains_echo_does_not_heal_but_its_own_star_does() -> void:
	for echo_only in [false, true]:
		var w := _world(["drain"], 8)
		w.player_state.hp = 5
		w._hp = 5.0
		_cast_star(w)
		if echo_only:
			_drop_flying(w)
		_ticks(w, 60)
		var heals := _events(w, "player_restored").filter(func(e: Dictionary) -> bool: return e.get("skill", "") == "drain")
		assert_true(_events(w, "mob_hit", "drain").size() > 0, "a Drain star hit")
		assert_eq(heals.is_empty(), echo_only, "echo-only run: %s" % echo_only)


func test_twin_shadow_makes_two_clones_and_doubles_the_echoes() -> void:
	var w := _world(["lucky_seven"])
	w.upgrades.apply("shadow_partner_rank", w, "unique")
	_cast_star(w)
	var s := w.runner.summons
	assert_eq(s.clones().size(), 2, "two clones")
	assert_near(s.offsets[1] - s.offsets[0], 40.0, 0.001)
	assert_eq(w.runner.echoes.pending_count(), 4, "two stars, each echoed by both clones")
	_ticks(w, 16)
	assert_eq(_events(w, "echo_cast").size(), 4)
	var clones := {}
	for e in _events(w, "echo_cast"):
		clones[int(e.clone)] = true
	assert_eq(clones.size(), 2)


func test_the_damage_modifier_scales_the_echo_percent() -> void:
	var plain := _world(["avenger"], 4)
	_cast_star(plain)
	_drop_flying(plain)
	_ticks(plain, 16)
	var boosted := _world(["avenger"], 4)
	boosted.loadout.add_skill_mod(KEY, "damage", "mul", 1.2)
	_cast_star(boosted)
	var owner_max: float = _flying(boosted)[0]
	_drop_flying(boosted)
	_ticks(boosted, 16)
	assert_near(_flying(boosted)[0] / _flying(plain)[0], 1.2, 0.0001, "Shadow Power scales the echo")
	assert_near(_flying(boosted)[0] / owner_max, 0.29 * 1.2, 0.0001, "29% x 1.2 of the owner's star at rank 4")


func test_the_echo_leaves_the_clones_hand_and_never_earns_a_receipt() -> void:
	var w := _world(["shadow_meso"])
	_ticks(w, 40)
	var s := w.runner.summons
	var m := _mob(w, 150)
	_ticks(w, 1)
	_drop_flying(w)
	_ticks(w, 16)
	var e: Dictionary = _events(w, "echo_cast")[0]
	assert_eq(e.skill, "shadow_meso")
	assert_eq(e.clone, s.clones()[0])
	assert_eq(e.facing, 1)
	assert_near(e.pos.x, s.x[e.clone] + w.cast_forward, 0.01)
	assert_true(w.swarm.is_live(m))


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

func test_the_rarity_table_follows_the_spec() -> void:
	var bonuses: Dictionary = _world([]).book.def(KEY).rarity_bonuses
	assert_eq(bonuses.keys().size(), 4)
	for tier: String in BONUSES:
		assert_eq(bonuses[tier].size(), 1, tier)
		var row: Array = BONUSES[tier]
		assert_eq(String(bonuses[tier][0].id), String(row[0]), tier)
		assert_true(String(bonuses[tier][0].text) != "", "%s has card text" % tier)
		assert_eq(bonuses[tier][0].effects.size(), 1)
		assert_eq(String(bonuses[tier][0].effects[0].stat), String(row[1]))
		assert_eq(String(bonuses[tier][0].effects[0].op), String(row[2]))
		assert_near(float(bonuses[tier][0].effects[0].value), float(row[3]), 0.0001)
	assert_eq(String(bonuses.rare[0].text), "Shadow Power")
	assert_eq(String(bonuses.epic[0].text), "Shadow Booster")
	assert_eq(String(bonuses.unique[0].text), "Twin Shadow")
	var legendary: Dictionary = bonuses.legendary[0]
	assert_eq(String(legendary.id), "twin_shadow", "Legendary shares the Unique's id")
	assert_eq(legendary.effects.size(), 2)
	assert_eq(String(legendary.effects[0].stat), "summon_count")
	assert_eq(String(legendary.effects[1].stat), "damage")
	assert_near(float(legendary.effects[1].value), 1.2, 0.0001)


## What one cast of the Shadow Partner and a Lucky Seven did after a rank card of `tier` ("normal" = the bare rank card).
func _probe(tier: String) -> Dictionary:
	var w := _world(["lucky_seven"], 1)
	w.upgrades.apply(KEY + "_rank", w, tier)
	var st := w.loadout.stats(KEY)
	var out := {"cooldown": float(st.cooldown), "damage": w.loadout.skill_stat(KEY, "damage", 1.0),
		"summons": maxi(1, roundi(w.loadout.skill_stat(KEY, "summon_count", 1.0)))}
	_ticks(w, 40)
	out["clones"] = w.runner.summons.clones().size()
	_mob(w, 150)
	_ticks(w, 1)
	var owner_shots := _flying(w)
	_drop_flying(w)
	_ticks(w, 16)
	var echoes := _flying(w)
	out["echoes"] = echoes.size()
	out["echo_damage"] = (echoes[0] / owner_shots[0]) if not echoes.is_empty() and not owner_shots.is_empty() else 0.0
	return out


func test_every_bonus_changes_the_resolved_cast() -> void:
	var base := _probe("normal")
	assert_eq(int(base.clones), 1)
	assert_eq(int(base.echoes), 2)
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		var got := _probe(tier)
		var row: Array = BONUSES[tier] if tier != "legendary" else BONUSES.unique
		var label := "%s %s" % [tier, row[0]]
		match String(row[1]):
			"damage":
				assert_near(float(got.damage), 1.2, 0.0001, label)
				assert_near(float(got.echo_damage), float(base.echo_damage) * 1.2, 0.0001, label + ": the echo hits harder")
			"cooldown":
				assert_near(float(got.cooldown) / float(base.cooldown), 0.88, 0.0001, label)
			"summon_count":
				assert_eq(int(got.clones), 2, label)
				assert_eq(int(got.echoes), 4, label + ": every star is echoed twice")
		if tier == "legendary":
			assert_near(float(got.damage), 1.2, 0.0001, "Legendary adds damage x1.2")
			assert_near(float(got.echo_damage), float(base.echo_damage) * 1.2, 0.0001)


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		var w := _world([])
		var card := w.upgrades.choice_card(KEY + "_rank", w, tier)
		assert_false(card.get("rarity_bonus", {}).is_empty(), "%s carries a bonus" % tier)
		w.upgrades.apply(KEY + "_rank", w, tier)
		assert_eq(w.loadout.rank(KEY), 2, "%s: one rank, whatever the rarity" % tier)
		match tier:
			"rare": assert_near(w.loadout.skill_stat(KEY, "damage", 1.0), 1.2, 0.0001)
			"epic": assert_near(w.loadout.skill_stat(KEY, "cooldown", 1.0), 0.88, 0.0001)
			"unique": assert_near(w.loadout.skill_stat(KEY, "summon_count", 0.0), 1.0, 0.0001)
			"legendary":
				assert_near(w.loadout.skill_stat(KEY, "summon_count", 0.0), 1.0, 0.0001)
				assert_near(w.loadout.skill_stat(KEY, "damage", 1.0), 1.2, 0.0001)


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	var w := _world([])
	w.upgrades.apply(KEY + "_rank", w, "unique")
	w.upgrades.apply(KEY + "_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:twin_shadow" % KEY]), 2, "one shared counter")
	var m := _world([])
	m.loadout.set_rank(KEY, 8)
	assert_eq(m.upgrades.choice_card(KEY + "_rank", m, "rare").card_kind, "mastery", "rank 8 offers Mastery")
	m.upgrades.apply(KEY + "_rank", m, "rare")
	m.upgrades.apply(KEY + "_rank", m, "rare")
	assert_near(m.loadout.skill_stat(KEY, "damage", 1.0), 1.2 * (1.0 + 0.2 * 0.8), 0.00001, "the repeat is x0.8")
	assert_eq(m.loadout.rank(KEY), 8)


func test_the_bot_scores_new_and_rank_cards() -> void:
	var scores: Dictionary = DataRepo.load_all().balance.bot.card_scores
	assert_true(float(scores.shadow_partner_new) > 0.0)
	assert_true(float(scores.shadow_partner_rank) > 0.0)


# --- the clone renderer's pure rules ----------------------------------------------------------------------------------

func _special() -> Dictionary:
	var out := {}
	for k in ["stand1", "stand2", "walk1", "jump", "alert", "ladder", "rope", "swingO1", "shoot1"]:
		out[k] = {"0": {}}
	return out


func test_the_owners_stance_maps_to_a_special_set_with_a_stand_fallback() -> void:
	var sp := _special()
	for stance in ["stand1", "stand2", "walk1", "jump", "alert", "ladder", "rope", "swingO1", "shoot1"]:
		assert_eq(EchoCloneRenderer.special_action(sp, stance), stance, stance)
	for pair in [["alert2", "alert"], ["alert3", "alert"], ["alert4", "alert"], ["ladder2", "ladder"], ["rope2", "rope"]]:
		assert_eq(EchoCloneRenderer.special_action(sp, pair[0]), pair[1], pair[0])
	for stance in ["avenger", "ninjastorm", "walk2", "mystery"]:
		assert_eq(EchoCloneRenderer.special_action(sp, stance), "stand1", "%s falls back to stand1" % stance)
	assert_eq(EchoCloneRenderer.special_action({}, "walk1"), "stand1", "no special at all")


func test_a_throw_uses_the_skills_own_action_when_the_sets_have_it_else_shoot1() -> void:
	var sp := _special()
	assert_eq(EchoCloneRenderer.throw_action(sp, "swingO1"), "swingO1")
	assert_eq(EchoCloneRenderer.throw_action(sp, "avenger"), "shoot1")
	assert_eq(EchoCloneRenderer.throw_action(sp, ""), "shoot1")


func test_frames_follow_the_owners_position_along_the_set() -> void:
	assert_eq(EchoCloneRenderer.frame_for(3, 3, 0), 0)
	assert_eq(EchoCloneRenderer.frame_for(3, 3, 2), 2)
	assert_eq(EchoCloneRenderer.frame_for(4, 2, 1), 3, "a longer set plays through to its last frame")
	assert_eq(EchoCloneRenderer.frame_for(3, 6, 5), 2, "a shorter set ends on its last frame")
	assert_eq(EchoCloneRenderer.frame_for(1, 5, 4), 0)
	assert_eq(EchoCloneRenderer.frame_for(5, 0, 3), 0, "an unknown owner stance holds frame 0")


func test_a_throw_takes_its_frame_times_from_the_owners_body_action() -> void:
	var delays := PackedFloat32Array([0.1, 0.2, 0.3])
	assert_eq(EchoCloneRenderer.throw_frame(3, delays, 0.0), 0)
	assert_eq(EchoCloneRenderer.throw_frame(3, delays, 0.099), 0)
	assert_eq(EchoCloneRenderer.throw_frame(3, delays, 0.11), 1)
	assert_eq(EchoCloneRenderer.throw_frame(3, delays, 0.31), 2)
	assert_eq(EchoCloneRenderer.throw_frame(3, delays, 5.0), 2, "holds the last frame")
	assert_near(EchoCloneRenderer.throw_duration(3, delays), 0.6, 0.0001)
	assert_near(EchoCloneRenderer.throw_duration(3, PackedFloat32Array()), 0.3, 0.0001, "0.1 s a frame when the stance is unknown")
	assert_eq(EchoCloneRenderer.throw_frame(3, PackedFloat32Array(), 0.25), 2)
	assert_eq(EchoCloneRenderer.throw_frame(5, delays, 0.31), 4, "a 5-frame set over a 3-frame body ends on its last frame")


func test_a_throw_starts_on_the_event_ends_after_its_duration_and_does_not_outlive_its_clone() -> void:
	var w := _world([])
	_ticks(w, 2)
	var s := w.runner.summons
	var slot: int = s.clones()[0]
	var r := EchoCloneRenderer.new()
	var pose := {"stance": "stand1", "frame": 0, "frames": 3}
	r.update_from(s, pose, 0.0)
	assert_false(r.is_throwing(slot))
	r.start_throw(s, slot, "swingO1", PackedFloat32Array([0.1, 0.1, 0.1]), -1)
	assert_true(r.is_throwing(slot))
	r.update_from(s, pose, 0.1)
	r.update_from(s, pose, 0.1)
	assert_true(r.is_throwing(slot), "0.2 s of 0.3 s")
	r.update_from(s, pose, 0.2)
	assert_false(r.is_throwing(slot), "over")
	r.start_throw(s, slot, "swingO1", PackedFloat32Array([0.1, 0.1, 0.1]), 1)
	s.spawn(w, w.loadout.stats(KEY)) # a recast reuses the slot with a new spawn serial
	r.update_from(s, pose, 0.0)
	assert_false(r.is_throwing(slot), "the replaced clone does not inherit the throw")
	r.start_throw(s, 99, "swingO1", PackedFloat32Array(), 1) # a slot that does not exist is ignored
	r.free()


# --- real cache -------------------------------------------------------------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var img := lib.img("Skill.wz/411.img")
	assert_true(img != null, "Skill.wz/411.img is in the cache")
	if img == null:
		lib.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"411": img.root})
	var lo := Loadout.new(book)
	var node: Dictionary = img.root.skill["4111002"]
	assert_eq(book.max_level(KEY), 30)
	assert_eq(book.max_rank(KEY), 8)
	for rank_value in range(1, 9):
		var lv: int = LEVELS_30[rank_value - 1]
		var level: Dictionary = node.level[str(lv)]
		assert_eq(book.canonical_level(KEY, rank_value), lv, "rank %d" % rank_value)
		assert_eq(book.canonical(KEY, lv, "x"), float(level.x), "rank %d x" % rank_value)
		assert_eq(book.canonical(KEY, lv, "y"), float(level.y), "rank %d y" % rank_value)
		assert_eq(lo.stats(KEY, rank_value).duration, float(level.time), "rank %d time" % rank_value)
	for i in 3:
		var lv: int = LEVELS_30[[0, 3, 7][i]]
		assert_eq(book.canonical(KEY, lv, "x"), X_AT[i], "rank %d attack %%" % RANKS[i])
		assert_eq(book.canonical(KEY, lv, "y"), Y_AT[i], "rank %d skill %%" % RANKS[i])
		assert_eq(lo.stats(KEY, RANKS[i]).duration, TIME_AT[i], "rank %d lifetime" % RANKS[i])
	lib.free()


func test_real_cache_every_special_set_resolves_and_every_owner_stance_maps_to_one() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var base := "Skill.wz/411.img/skill/4111002/special"
	var special: Variant = lib.find(base)
	assert_true(special is Dictionary, "the node exists")
	if not (special is Dictionary):
		lib.free()
		return
	assert_eq((special as Dictionary).size(), 34, "34 action sets")
	var frames := 0
	for action: String in special:
		var anim := lib.find_anim(base + "/" + action)
		assert_true(anim != null and not anim.is_empty(), action)
		if anim != null:
			frames += anim.frame_count()
			for f in anim.frames:
				assert_true(f.page != null, "%s has pixels" % action)
	assert_eq(frames, 98, "98 canvases")
	# The owner's action stream: every stance the avatar body has maps to a set that exists.
	var body: Variant = lib.find("Character.wz/00002000.img")
	assert_true(body is Dictionary)
	var fallbacks := []
	for stance: String in body:
		if not (body[stance] is Dictionary) or not (body[stance] as Dictionary).has("0"):
			continue
		var mapped := EchoCloneRenderer.special_action(special, stance)
		assert_true((special as Dictionary).has(mapped), "%s -> %s" % [stance, mapped])
		if mapped == "stand1" and stance != "stand1":
			fallbacks.append(stance)
	# The claw user's own stances and the Night Lord skill stances (recorded in GAME_DESIGN 7.94.7).
	for stance in ["stand1", "walk1", "jump", "alert", "swingO1", "ladder", "rope", "prone", "sit"]:
		assert_eq(EchoCloneRenderer.special_action(special, stance), stance, stance)
	for stance in ["avenger", "ninjastorm", "alert3", "alert2"]:
		assert_eq(EchoCloneRenderer.special_action(special, stance), "alert" if stance.begins_with("alert") else "stand1", stance)
	assert_true("avenger" in fallbacks and "ninjastorm" in fallbacks, "the Night Lord skill stances fall back to stand1")
	for skill_action in ["swingO1", "avenger", "alert", "ninjastorm"]:
		assert_true((special as Dictionary).has(EchoCloneRenderer.throw_action(special, skill_action)), skill_action)
	lib.free()
