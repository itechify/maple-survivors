extends TestCase
## Shadower's Smokescreen (spec #425, ticket SH12 #437, GAME_DESIGN 7.136): the first user of the safe zone (SH4). A cloud
## box read from the Skill.wz node by rank (+-120 x +-90 / (-150,-112)..(150,113) / +-200 x +-150), a 6 s life and a 24 s
## cooldown (the node's `time` 34 -> 60 and `cooltime` 600 are session values and are not read), admission at three
## monsters within 250 px, every hit source negated while the body is inside, and the four rarity bonuses. Fixed 1/60 s
## ticks, seeded RNG. The behaviour tests run on a synthetic book-422 level table shaped like the node (including its
## one-pixel y asymmetry); the real-cache tests at the end call require_cache() and SKIP without the cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const KEY := "smokescreen"
const SNAIL := 100100
const LEVELS := [4, 8, 12, 15, 19, 23, 27, 30]
## Skill.wz 4221006 levels 1..30: [half-width, top edge, bottom edge, time], read from the v83 data (SH1 scan). The y edges
## are one pixel off symmetric at some levels (rank 4: -112 / 113).
const BOX := [
	[110, -82, 83, 31], [110, -82, 83, 32], [110, -82, 83, 33], [120, -90, 90, 34], [120, -90, 90, 35], [120, -90, 90, 36],
	[130, -97, 98, 37], [130, -97, 98, 38], [130, -97, 98, 39], [140, -105, 105, 40], [140, -105, 105, 41], [140, -105, 105, 42],
	[150, -112, 113, 42], [150, -112, 113, 44], [150, -112, 113, 45], [160, -120, 120, 46], [160, -120, 120, 47], [160, -120, 120, 48],
	[170, -127, 128, 49], [170, -127, 128, 50], [170, -127, 128, 51], [180, -135, 135, 52], [180, -135, 135, 53], [180, -135, 135, 54],
	[190, -142, 143, 55], [190, -142, 143, 56], [190, -142, 143, 57], [200, -150, 150, 58], [200, -150, 150, 59], [200, -150, 150, 60]]
## The boxes the spec names at ranks 1 / 4 / 8, as Rect2(x, y, w, h).
const RANK_BOXES := {1: Rect2(-120, -90, 240, 180), 4: Rect2(-150, -112, 300, 225), 8: Rect2(-200, -150, 400, 300)}
const RARITY := {
	"rare": ["wide_smoke", "area", 1.2],
	"epic": ["haste", "cooldown", 0.88],
	"unique": ["thick_smoke", "zone_time", 1.5],
}


func _levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 31):
		var row: Array = BOX[lv - 1]
		levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 19.0, "time": float(row[3]), "cooltime": 600.0,
			"lt": {"$v": [-float(row[0]), float(row[1])]}, "rb": {"$v": [float(row[0]), float(row[2])]}}
	return levels


## A quiet round of a Shadower with Smokescreen learned at `rank_value`: 1000 HP, no regeneration, frozen harmless monsters.
func _world(rank_value := 1, p_seed := 437) -> RunWorld:
	var data := RF.quiet_data()
	data.jobs_survivor.jobs["422"]["playable"] = true # in this test's data only: SH14 ships the flip
	data.balance.player.hp = 1000
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	data.balance.magnet_radius = 0
	data.balance.mob_motion.push_px = 0
	var setup := RF.with_basic_attack(RF.setup("quiet", p_seed, data))
	for action: String in ["smokeshell", "alert", "swingO1"]:
		setup.body_img[action] = {"0": {"delay": 100.0}, "1": {"delay": 100.0}}
	setup.skill_imgs["422"] = {"skill": {"4221006": {"invisible": 1, "level": _levels()}}}
	setup["job"] = 422
	var w := RunWorld.new(setup)
	RF.place_player(w, 400)
	w.player.facing = 1
	for mk: MobKind in w.mob_kinds:
		mk.move_speed = 0.0
		mk.body_attack = false
	w.loadout.ranks.clear() # not the start skill: only Smokescreen casts
	w.loadout.order.clear()
	assert_true(w.learn_skill(KEY), "Smokescreen is learnable by a Shadower")
	w.loadout.set_rank(KEY, rank_value)
	w.refresh_player_stats()
	w.drain_events()
	return w


## A standing snail at `dx` from the character; the mob grid is refreshed.
func _snail(w: RunWorld, dx: float) -> int:
	var m := RF.put_mob(w, SNAIL, w.player.pos.x + dx, 190.0, 100000.0)
	w.swarm.alpha[m] = 1.0
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _crowd(w: RunWorld) -> void:
	for dx in [60.0, 90.0, 120.0]:
		_snail(w, dx)


func _run(w: RunWorld, ticks: int) -> Array:
	var out: Array = []
	for i in ticks:
		w.step(DT, MoveInput.new())
		out.append_array(w.drain_events())
	return out


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == type)


## One hit on the character from `source`, as the sim lands it.
func _hit(w: RunWorld, source: Dictionary) -> int:
	return w.take_hit(100.0, false, "", w.player.pos + Vector2(-30, 0), source)


# --- the definition ---------------------------------------------------------------------------------------------------

func test_smokescreen_is_a_damage_none_safe_zone_skill_with_the_shipped_art() -> void:
	var w := _world()
	var d := w.book.def(KEY)
	assert_eq(int(d.skill_id), 4221006)
	assert_eq(String(d.book), "422")
	assert_eq(int(d.job), 422)
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "none")
	assert_eq(String(d.cast.rule), "safe_zone")
	assert_eq(int(d.cast.min_mobs), 3)
	assert_eq(float(d.cast.mob_within), 250.0)
	assert_eq(float(d.safe_zone.duration), 6.0)
	assert_eq(float(d.cooldown), 24.0)
	assert_eq(String(d.action), "smokeshell")
	assert_eq(String(d.effect), "Skill.wz/422.img/skill/4221006/effect")
	assert_eq(String(d.tile), "Skill.wz/422.img/skill/4221006/tile", "the cloud art is a top-level `tile` path beside `effect`")
	assert_eq(String(d.icon), "Skill.wz/422.img/skill/4221006/icon")
	assert_eq(String(d.sounds.use), "Sound.wz/Skill.img/4221006/Use")
	assert_false(d.has("ranks"), "the default 30-level rank table")
	assert_false(d.has("weapon_families"), "weapons gate nothing")
	assert_eq(SafeZone.errors(w.book.defs).size(), 0, "the safe-zone data validator accepts it")


func test_the_resolved_stats_are_the_zone_rule_not_an_attack() -> void:
	var w := _world()
	var st := w.loadout.stats(KEY)
	assert_eq(String(st.cast_rule), "safe_zone")
	assert_false(SkillRunner.is_attack(st), "a placed place, not an attack: Hidden does not silence it")
	assert_near(float(st.cooldown), 24.0, 1e-9)
	assert_near(float(st.safe_zone_duration), 6.0, 1e-9)
	assert_near(float(st.zone_time), 1.0, 1e-9)


func test_the_node_s_time_and_cooltime_are_session_values_and_are_not_read() -> void:
	for rank_value in range(1, 9):
		var w := _world(rank_value)
		var st := w.loadout.stats(KEY)
		assert_near(float(st.cooldown), 24.0, 1e-9, "rank %d: not the node's cooltime 600" % rank_value)
		assert_near(float(st.safe_zone_duration), 6.0, 1e-9, "rank %d: not the node's time 34..60" % rank_value)


# --- the box by rank --------------------------------------------------------------------------------------------------

func test_the_box_by_rank_is_read_from_the_node_as_given() -> void:
	var w := _world()
	assert_eq(w.book.max_rank(KEY), 8)
	for rank_value in range(1, 9):
		var lv: int = LEVELS[rank_value - 1]
		assert_eq(w.book.canonical_level(KEY, rank_value), lv, "rank %d reads WZ level %d" % [rank_value, lv])
		var row: Array = BOX[lv - 1]
		var expected := Rect2(-float(row[0]), float(row[1]), float(row[0]) * 2.0, float(row[2]) - float(row[1]))
		assert_eq(w.loadout.stats(KEY, rank_value).box, expected, "rank %d" % rank_value)
	for rank_value: int in RANK_BOXES:
		assert_eq(w.loadout.stats(KEY, rank_value).box, RANK_BOXES[rank_value], "spec rank %d" % rank_value)
	# Rank 4 keeps the node's one-pixel asymmetry: the y edges are -112 and 113, not +-112.5.
	var rank4: Rect2 = w.loadout.stats(KEY, 4).box
	assert_eq(rank4.position.y, -112.0)
	assert_eq(rank4.end.y, 113.0)


func test_a_cast_places_that_box_anchored_where_the_cast_stood() -> void:
	for rank_value: int in RANK_BOXES:
		var w := _world(rank_value)
		_crowd(w)
		var origin := w.cast_origin()
		var events := _run(w, 3)
		var started := _of(events, "safe_zone_started")
		assert_eq(started.size(), 1, "rank %d" % rank_value)
		var box: Rect2 = RANK_BOXES[rank_value]
		assert_eq(started[0].pos, origin + box.position, "rank %d: the box's top-left" % rank_value)
		assert_eq(started[0].size, box.size, "rank %d" % rank_value)
		assert_near(float(started[0].duration), 6.0, 1e-9)
		assert_eq(started[0].skill, KEY)
		assert_eq(started[0].skill_id, 4221006)
		assert_eq(w.safe_zones.rect_of(KEY), Rect2(origin + box.position, box.size))
		assert_near(float(w.runner.cooldowns[KEY]), 24.0, 0.1, "the 24 s cooldown starts")


func test_the_cloud_stays_where_it_was_set_off() -> void:
	var w := _world(4)
	_crowd(w)
	_run(w, 3)
	var rect := w.safe_zones.rect_of(KEY)
	RF.place_player(w, 900)
	_run(w, 30)
	assert_eq(w.safe_zones.rect_of(KEY), rect, "it does not follow")


# --- admission --------------------------------------------------------------------------------------------------------

func test_it_waits_with_its_cooldown_at_zero_for_three_monsters_within_250_px() -> void:
	var w := _world()
	_snail(w, 60.0)
	_snail(w, 90.0)
	_snail(w, 400.0) # the third is out of the 250 px reach
	_run(w, 120)
	assert_eq(w.runner.casts, 0, "two near monsters are not enough")
	assert_true(float(w.runner.cooldowns[KEY]) <= 0.0, "nothing was spent: the cooldown is at 0 and waiting")
	assert_true(w.safe_zones.is_empty())
	_snail(w, 120.0)
	var events := _run(w, 3)
	assert_eq(w.runner.casts, 1, "the third near monster admits the cast")
	assert_eq(_of(events, "safe_zone_started").size(), 1)
	var cast: Dictionary = _of(events, "cast")[0]
	assert_eq(cast.skill, KEY)
	assert_eq(cast.action, "smokeshell")
	assert_eq(cast.effect, "Skill.wz/422.img/skill/4221006/effect", "the effect plays once at the cast")


func test_it_does_not_cast_again_inside_its_own_live_cloud_and_recasts_after_the_cooldown_outside_it() -> void:
	var w := _world()
	_crowd(w)
	_run(w, 3)
	assert_eq(w.runner.casts, 1)
	w.runner.cooldowns[KEY] = 0.0 # the cooldown is not what refuses a second cast
	_run(w, 5)
	assert_eq(w.runner.casts, 1, "inside its own live cloud it waits")
	var rect := w.safe_zones.rect_of(KEY)
	RF.place_player(w, rect.end.x + 200.0)
	_crowd(w)
	var events := _run(w, 3)
	assert_eq(w.runner.casts, 2)
	assert_eq(_of(events, "safe_zone_ended")[0].reason, "replaced", "a recast replaces the cloud")
	assert_eq(w.safe_zones.snapshot().size(), 1)


# --- negation ---------------------------------------------------------------------------------------------------------

func test_every_hit_source_is_negated_while_inside_and_lands_after_the_cloud() -> void:
	var sources := {
		"touch": {"mob": 3, "accuracy": 100000.0, "source_kind": "touch"},
		"mob_attack": {"mob": 3, "accuracy": 100000.0, "source_kind": "mob_attack"},
		"projectile": {"mob": 3, "accuracy": 100000.0, "boss": true, "source_kind": "projectile"},
		"attack": {"mob": 3, "accuracy": 100000.0, "boss": true, "boss_index": 0, "source_kind": "attack"},
	}
	for kind: String in sources:
		var w := _world(4)
		_crowd(w)
		_run(w, 3)
		var hp := float(w.player_state.hp)
		var pos := w.player.pos
		assert_eq(_hit(w, sources[kind]), 0, kind)
		var events := w.drain_events()
		assert_eq(float(w.player_state.hp), hp, "%s: HP unchanged" % kind)
		assert_eq(w.upkeep.invincible_t, 0.0, "%s: no hit window" % kind)
		assert_eq(w.player.pos, pos, "%s: no knock-back" % kind)
		assert_eq(events.size(), 1, "%s: exactly one event" % kind)
		assert_eq(events[0].type, "hit_negated")
		assert_eq(events[0].skill, KEY)
		assert_eq(events[0].source, kind)
		# Out of the box the same hit lands; after the six seconds it lands too.
		var edge := w.safe_zones.rect_of(KEY).end.x
		RF.place_player(w, edge + 20.0)
		assert_true(_hit(w, sources[kind]) > 0, "%s: outside the cloud it lands" % kind)
		w.drain_events()
		RF.place_player(w, 400.0)
		w.upkeep.invincible_t = 0.0
		_run(w, 360)
		assert_true(w.safe_zones.is_empty(), "%s: gone after 6.0 s" % kind)
		assert_true(_hit(w, sources[kind]) > 0, "%s: after expiry it lands" % kind)


func test_a_monster_touching_the_character_in_a_real_tick_does_no_damage_inside_the_cloud() -> void:
	var w := _world(8)
	_crowd(w)
	_run(w, 3)
	var m := _snail(w, 0.0)
	var kind: MobKind = w.mob_kinds[w.swarm.kind[m]]
	kind.body_attack = true
	kind.pad = 100000.0
	kind.acc = 100000.0
	var hp := float(w.player_state.hp)
	var events := _run(w, 20)
	assert_eq(float(w.player_state.hp), hp)
	assert_eq(_of(events, "player_hit").size(), 0)
	assert_eq(_of(events, "hit_negated").size(), 20, "no hit window, so a touching monster is negated every tick")
	assert_eq(_of(events, "hit_negated")[0].skill, KEY)
	assert_eq(_of(events, "hit_negated")[0].source, "touch")
	var after := _run(w, 360)
	assert_true(w.safe_zones.is_empty())
	assert_true(_of(after, "player_hit").size() >= 1, "from the tick the cloud ends the contact damages")
	assert_true(float(w.player_state.hp) < hp)


# --- rarity bonuses ---------------------------------------------------------------------------------------------------

func test_the_rarity_tables_follow_the_spec() -> void:
	var bonuses: Dictionary = _world().book.def(KEY).rarity_bonuses
	assert_eq(bonuses.keys().size(), 4, "exactly the four tiers")
	for tier: String in RARITY:
		var row: Array = RARITY[tier]
		assert_eq(bonuses[tier].size(), 1, tier)
		var bonus: Dictionary = bonuses[tier][0]
		assert_eq(String(bonus.id), String(row[0]), tier)
		assert_true(String(bonus.text) != "", "%s has card text" % tier)
		assert_eq(bonus.effects.size(), 1)
		assert_eq(String(bonus.effects[0].stat), String(row[1]), tier)
		assert_eq(String(bonus.effects[0].op), "mul")
		assert_near(float(bonus.effects[0].value), float(row[2]), 1e-9, tier)
	var legendary: Dictionary = bonuses.legendary[0]
	assert_eq(String(legendary.id), "thick_smoke", "Legendary shares the Unique's id (and its repeat counter)")
	assert_eq(legendary.effects.size(), 2)
	assert_eq(String(legendary.effects[0].stat), "zone_time")
	assert_near(float(legendary.effects[0].value), 1.5, 1e-9)
	assert_eq(String(legendary.effects[1].stat), "area", "no damage to raise: the Legendary adds area")
	assert_near(float(legendary.effects[1].value), 1.2, 1e-9)
	assert_eq(String(bonuses.rare[0].text), "Wide Smoke")
	assert_eq(String(bonuses.unique[0].text), "Thick Smoke")


## The cast of rank 4 with `effects` applied: the stats, the cooldown after the cast and the placed zone's size and life.
func _probe(effects: Array) -> Dictionary:
	var w := _world(4)
	for effect: Dictionary in effects:
		w.loadout.add_skill_mod(KEY, String(effect.stat), String(effect.op), float(effect.value))
	_crowd(w)
	var started := _of(_run(w, 3), "safe_zone_started")
	assert_eq(started.size(), 1)
	return {"width": float(started[0].size.x), "height": float(started[0].size.y), "life": float(started[0].duration),
		"cooldown": float(w.loadout.stats(KEY).cooldown), "spent": float(w.runner.cooldowns[KEY]),
		"left": float(w.safe_zones.snapshot()[0].left)}


func test_every_bonus_changes_the_resolved_cast_and_the_placed_zone() -> void:
	var bonuses: Dictionary = _world().book.def(KEY).rarity_bonuses
	var base := _probe([])
	assert_near(float(base.width), 300.0, 1e-3)
	assert_near(float(base.life), 6.0, 1e-9)
	assert_near(float(base.cooldown), 24.0, 1e-9)
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		for effect: Dictionary in bonuses[tier][0].effects:
			var with_effect := _probe([effect])
			var label := "%s %s" % [tier, String(effect.stat)]
			match String(effect.stat):
				"area":
					assert_near(float(with_effect.width), 300.0 * 1.2, 1e-3, label)
					assert_near(float(with_effect.height), 225.0 * 1.2, 1e-3, label)
					assert_near(float(with_effect.life), 6.0, 1e-9, label + ": the life is unchanged")
				"zone_time":
					assert_near(float(with_effect.life), 9.0, 1e-9, label + ": a 9 s cloud")
					assert_near(float(with_effect.left), 9.0, 0.05, label + ": the placed zone lives 9 s")
					assert_near(float(with_effect.width), 300.0, 1e-3, label)
				"cooldown":
					assert_near(float(with_effect.cooldown), 24.0 * 0.88, 1e-4, label)
					assert_true(float(with_effect.spent) < float(base.spent) - 2.0, label + ": the cast spends less")
				_:
					assert_true(false, label + ": unprobed stat")


func test_a_cloud_already_placed_keeps_its_life_when_thick_smoke_is_taken_later() -> void:
	var w := _world(4)
	_crowd(w)
	_run(w, 3)
	w.loadout.add_skill_mod(KEY, "zone_time", "mul", 1.5)
	assert_near(float(w.safe_zones.snapshot()[0].total), 6.0, 1e-9)
	assert_near(float(w.loadout.stats(KEY).safe_zone_duration), 9.0, 1e-9, "the next cast gets 9 s")


func test_a_rare_or_better_card_adds_one_rank_plus_its_bonus() -> void:
	for tier: String in ["rare", "epic", "unique", "legendary"]:
		var w := _world()
		var card := w.upgrades.choice_card(KEY + "_rank", w, tier)
		assert_false(card.get("rarity_bonus", {}).is_empty(), "%s carries a bonus" % tier)
		w.upgrades.apply(KEY + "_rank", w, tier)
		assert_eq(w.loadout.rank(KEY), 2, "%s: one rank, whatever the rarity" % tier)
		var st := w.loadout.stats(KEY)
		match tier:
			"rare":
				assert_near(float(st.area), 1.2, 1e-5)
				assert_near(float(st.box.size.x), 260.0 * 1.2, 1e-3, "rank 2 reads WZ level 8 (+-130), widened")
			"epic":
				assert_near(float(st.cooldown), 24.0 * 0.88, 1e-4)
			"unique":
				assert_near(float(st.safe_zone_duration), 9.0, 1e-9)
			"legendary":
				assert_near(float(st.safe_zone_duration), 9.0, 1e-9)
				assert_near(float(st.area), 1.2, 1e-5)
				assert_near(float(st.cooldown), 24.0, 1e-9, "the Legendary does not shorten the cooldown")


func test_legendary_shares_the_uniques_counter_and_mastery_repeats_shrink() -> void:
	var w := _world()
	w.upgrades.apply(KEY + "_rank", w, "unique")
	w.upgrades.apply(KEY + "_rank", w, "legendary")
	assert_eq(int(w.loadout.card_ranks["bonus:%s:thick_smoke" % KEY]), 2, "one shared counter")
	# Repeats of a Rare bonus shrink x0.8: area 1.2, then 1 + 0.2 x 0.8.
	var m := _world()
	m.loadout.set_rank(KEY, 8)
	m.upgrades.apply(KEY + "_rank", m, "rare")
	m.upgrades.apply(KEY + "_rank", m, "rare")
	assert_near(float(m.loadout.stats(KEY).area), 1.2 * (1.0 + 0.2 * 0.8), 1e-6, "the repeat is x0.8")
	assert_eq(m.loadout.rank(KEY), 8)


func test_normal_mastery_on_this_damage_none_skill_reduces_the_cooldown() -> void:
	var w := _world()
	w.loadout.set_rank(KEY, 8)
	assert_eq(w.upgrades.choice_card(KEY + "_rank", w, "normal").card_kind, "mastery", "at rank 8 the rank card is Mastery")
	assert_near(float(w.loadout.stats(KEY).cooldown), 24.0, 1e-9)
	w.upgrades.apply(KEY + "_rank", w, "normal")
	assert_near(float(w.loadout.stats(KEY).cooldown), 24.0 * 0.95, 1e-4, "#346: cooldown x0.95, there is no damage to raise")
	assert_near(float(w.loadout.skill_stat(KEY, "damage", 1.0)), 1.0, 1e-9, "and no damage was added")
	w.upgrades.apply(KEY + "_rank", w, "normal")
	assert_near(float(w.loadout.stats(KEY).cooldown), 24.0 * 0.95 * (1.0 - 0.05 * 0.8), 1e-6, "the repeat shrinks x0.8")
	# The shorter cooldown reaches the cast.
	_crowd(w)
	_run(w, 3)
	assert_true(float(w.runner.cooldowns[KEY]) < 24.0 * 0.95, "the cast spends the shortened cooldown")


# --- the bot and the windows ------------------------------------------------------------------------------------------

func test_the_bot_scores_the_learn_card_100_and_the_rank_card_74() -> void:
	var learn_world := _world()
	learn_world.loadout.ranks.erase(KEY) # a round that has not learned it yet
	var learn := learn_world.upgrades.choice_card(KEY + "_new", learn_world, "normal")
	assert_false(learn.is_empty(), "Smokescreen is offered as a new skill")
	assert_eq(BotInput.card_score(learn_world, learn), 100.0, "learn card")
	var w := _world()
	var rank := w.upgrades.choice_card(KEY + "_rank", w, "normal")
	assert_false(rank.is_empty())
	assert_eq(BotInput.card_score(w, rank), 74.0, "rank card")
	var passive := learn_world.upgrades.choice_card("passive_might_new", learn_world, "normal")
	if not passive.is_empty():
		assert_eq(BotInput.pick_card_for(learn_world, [passive, learn]), KEY + "_new", "taken over a passive")


func test_the_skill_window_names_the_cloud_s_life_and_admission() -> void:
	var w := _world(8)
	var text := SkillText.new(w.book)
	var line := MapleText.plain(text.level_line(KEY, 30, w.loadout.stats(KEY, 8)))
	assert_true(line.contains("smoke cloud for 6 s"), line)
	assert_true(line.contains("3 monsters within 250 px"), line)
	w.loadout.add_skill_mod(KEY, "zone_time", "mul", 1.5)
	var thick := MapleText.plain(text.level_line(KEY, 30, w.loadout.stats(KEY, 8)))
	assert_true(thick.contains("smoke cloud for 9 s"), thick)


# --- the view reads the real shape of `tile` --------------------------------------------------------------------------

func _frame(w: int, h: int) -> SpriteFrame:
	var f := SpriteFrame.new()
	f.region = Rect2(0, 0, w, h)
	f.origin = Vector2(w * 0.5, h * 0.5)
	f.delay_s = 0.9
	return f


func _puff(w: int, h: int) -> SpriteAnim:
	var anim := SpriteAnim.new()
	for k in 2:
		var f := _frame(w, h)
		f.start = 0.9 * k
		anim.frames.append(f)
	anim.total = 1.8
	return anim


func test_the_view_takes_one_animation_or_the_puff_variants_and_draws_a_different_puff_each() -> void:
	assert_eq(SafeZoneView.usable_anims(null).size(), 0)
	assert_eq(SafeZoneView.usable_anims(SpriteAnim.new()).size(), 0, "an empty animation is no art")
	assert_eq(SafeZoneView.usable_anims(_puff(40, 30)).size(), 1)
	var variants: Array = []
	for k in 11:
		variants.append(_puff(47 + k * 9, 40 + k * 5))
	variants.append(SpriteAnim.new())
	assert_eq(SafeZoneView.usable_anims(variants).size(), 11, "the empty one is dropped")
	var view := SafeZoneView.new()
	view.begin("cloud", Rect2(0, 0, 300, 100), 5.0, 90.0, variants)
	view.advance(1.0)
	assert_eq(view.puff_count(), 6, "300 px / 48 px of puffs, from the variants")
	view.free()


func test_no_library_or_no_path_is_no_art() -> void:
	assert_eq(SafeZoneView.load_art(null, "Skill.wz/422.img/skill/4221006/tile").size(), 0)
	assert_eq(SafeZoneView.load_art(AssetLibrary.new(), "").size(), 0)


# --- real cache: all eight ranks against Skill.wz and the real art ----------------------------------------------------

func test_real_cache_all_eight_ranks_map_to_the_skill_wz_levels_and_the_art_resolves() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	assert_true(lib.open())
	var img_422 := lib.img("Skill.wz/422.img")
	assert_true(img_422 != null, "Skill.wz/422.img is in the cache")
	if img_422 == null:
		lib.free()
		return
	var data := DataRepo.load_all()
	var book := SkillBook.from_data(data.skills, {"422": img_422.root})
	var lo := Loadout.new(book)
	lo.weapon_family = "dagger"
	var node: Dictionary = img_422.root.skill["4221006"]
	assert_eq(book.max_level(KEY), 30)
	assert_eq(book.max_rank(KEY), 8)
	var width_previous := 0.0
	for rank_value in range(1, 9):
		var lv: int = LEVELS[rank_value - 1]
		var label := "rank %d (level %d)" % [rank_value, lv]
		assert_eq(book.canonical_level(KEY, rank_value), lv, label)
		var level: Dictionary = node.level[str(lv)]
		var lt: Array = level.lt["$v"]
		var rb: Array = level.rb["$v"]
		var st := lo.stats(KEY, rank_value)
		assert_eq(st.box, Rect2(float(lt[0]), float(lt[1]), float(rb[0]) - float(lt[0]), float(rb[1]) - float(lt[1])), "box " + label)
		assert_true(st.box.size.x > width_previous, "the box widens with the rank: " + label)
		width_previous = st.box.size.x
		assert_eq(st.cooldown, 24.0, label)
		assert_eq(st.safe_zone_duration, 6.0, label)
		assert_eq(float(level.cooltime), 600.0, "the node's cooltime is the unread session value: " + label)
	# The spec's worked boxes at rank 1 / 4 / 8 as literals.
	for rank_value: int in RANK_BOXES:
		assert_eq(lo.stats(KEY, rank_value).box, RANK_BOXES[rank_value], "spec box, rank %d" % rank_value)
	# The art: the cast's effect is an 11-frame animation, the cloud is eleven two-frame puffs, the sound plays.
	var def := book.def(KEY)
	var effect := lib.anim(String(def.effect))
	assert_eq(effect.frame_count(), 11, "effect: 11 frames")
	assert_eq(lib.find_anim(String(def.tile)), null, "the tile node itself holds no frames: it is eleven puff nodes")
	var puffs := SafeZoneView.load_art(lib, String(def.tile))
	assert_eq(puffs.size(), 11, "tile: eleven puff variants")
	var widths := {}
	for puff: SpriteAnim in puffs:
		assert_eq(puff.frame_count(), 2, "each puff is two frames")
		assert_true(puff.alpha_at(0.0, true) < puff.alpha_at(puff.frames[0].delay_s * 0.999, true), "frame 0 fades in")
		widths[int(puff.frames[0].region.size.x)] = true
	assert_true(widths.size() >= 5, "the variants differ in size")
	assert_true(lib.sound(String(def.sounds.use)) != null, "the Use sound plays")
	assert_true(lib.frame(String(def.icon)) != null, "the icon resolves")
	assert_eq(lib.missing.size(), 0, "nothing missing")
	lib.free()
