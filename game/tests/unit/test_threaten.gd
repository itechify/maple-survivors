extends TestCase
## Page Threaten 1201006 and the threatened status (spec #165 ticket #183, docs/GAME_DESIGN.md 7.11): the crowd cast rule
## with a status parameter, a flat PAD and WDEF cut on up to mobCount ordinary mobs, refresh without stacking, coexistence
## with slow and poison, no boss, no RNG. Seeded, fixed ticks, Skill.wz-shaped synthetic level nodes (the real-cache test
## SKIPs without the asset cache and proves nothing then).

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const MF := preload("res://tests/fixtures/mob_attack_fixtures.gd")
const DT := 1.0 / 60.0
const MOB := 1110100 # PADamage 82, PDDamage 12, MDDamage 40
const THREATENED := "threatened"


## Twenty small Page levels in Skill.wz 120.img's shape (they replace the fixture's v83 endpoints so the tests stay short):
## x = -10 L, y = -5 L, time = 3 L s, MP 7, two targets, a 200 x 80 px box.
func _levels() -> Dictionary:
	var levels := {}
	for lv in range(1, 21):
		levels[str(lv)] = {"hs": "h%d" % lv, "mpCon": 7.0, "time": 3.0 * lv, "x": -10.0 * lv, "y": -5.0 * lv,
			"mobCount": 2.0, "lt": {"$v": [-100.0, -60.0]}, "rb": {"$v": [100.0, 20.0]}}
	return levels


func _world(p_seed := 183) -> RunWorld:
	var data := RF.quiet_data()
	data.balance.player.skills = []
	data.balance.player.hp = 100000
	data.balance.player.mp = 300
	data.balance.regen.hp = 0
	data.balance.regen.mp = 0
	data.balance.mob_attacks = {"default_interval": 5.0}
	data.balance.player.stats.dex = 0
	data.balance.player.stats.luk = 0
	var setup := RF.setup("quiet", p_seed, data)
	setup.skill_imgs["120"].skill["1201006"].level = _levels()
	var w := RunWorld.new(setup)
	for mk: MobKind in w.mob_kinds:
		mk.move_speed = 0.0
	RF.change_job_bare(w, 120)
	RF.place_player(w, 400)
	w.player.facing = -1
	w.learn_skill("threaten")
	w.drain_events()
	return w


func _put(w: RunWorld, x: float) -> int:
	var m := RF.put_mob(w, MOB, x)
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	return m


func _threaten(w: RunWorld, m: int, time := 60.0, x := -30.0, y := -20.0) -> bool:
	return w.swarm.apply_status(m, THREATENED, {"time": time, "x": x, "y": y}, w.events)


func _applied(events: Array, status: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return e.type == "mob_status_applied" and e.status == status)


# --- data -------------------------------------------------------------------------------------------------------------

func test_threaten_is_a_crowd_cast_page_skill_with_the_canonical_id_and_no_prop() -> void:
	var w := _world()
	assert_true(w.book.has("threaten"))
	assert_eq(w.book.skill_id("threaten"), 1201006)
	assert_eq(w.book.max_rank("threaten"), 20)
	var d := w.book.def("threaten")
	assert_eq(String(d.kind), "instant")
	assert_eq(String(d.slot), "active")
	assert_eq(String(d.damage), "none")
	assert_eq(String(d.cast.rule), "crowd")
	assert_eq(String(d.cast.status), THREATENED)
	assert_false(d.has("weapon_families") or d.has("weapon"), "Threaten needs no weapon")
	assert_eq(w.book.canonical("threaten", 1, "prop"), 0.0, "no prop: always succeeds (tier A absence)")


func test_the_page_cards_exist_for_job_120_only_and_are_not_power_cards() -> void:
	var w := _world()
	var cards := {}
	for c: Dictionary in w.upgrades.cards:
		if String(c.get("skill", "")) == "threaten":
			cards[String(c.id)] = c
	assert_eq(cards.keys().size(), 2)
	for id in ["threaten_new", "threaten_rank"]:
		assert_true(cards.has(id), id)
		assert_eq(Array(cards[id].requires.jobs).map(func(j: Variant) -> int: return int(j)), [120], id)
		assert_false(bool(cards[id].get("power", false)), "%s is not a power card" % id)
	assert_eq(String(cards.threaten_new.kind), "skill_new")
	assert_eq(String(cards.threaten_rank.kind), "skill_rank")
	assert_eq(int(cards.threaten_rank.max_rank), 20)


func test_threaten_cards_score_by_default_like_a_defensive_buff_not_an_attack() -> void:
	var w := _world()
	var scores: Dictionary = w.balance.bot.card_scores
	assert_false(scores.has("threaten_new") or scores.has("threaten_rank"), "no override: default scoring like Iron Body")
	assert_eq(BotInput.card_score(w, w.upgrades.card("threaten_new")), BotInput.SCORE_NEW_PASSIVE,
		"the crowd rule is never scored as an attack")
	w.learn_skill("threaten")
	assert_eq(BotInput.card_score(w, w.upgrades.card("threaten_rank")),
		BotInput.SCORE_RANK_PASSIVE + BotInput.SCORE_JOB_BONUS, "a current-job rank card")


func test_real_120_img_has_the_threaten_levels_and_no_success_chance() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var img := library.img("Skill.wz/120.img")
	if img == null:
		skip("the cache has no Skill.wz/120.img (import with the Warrior second-job manifest)")
		library.free()
		return
	var book := SkillBook.from_data(DataRepo.load_all().skills, {"120": img.root})
	assert_eq(book.max_level("threaten"), book.max_rank("threaten"), "ranks cover every canonical level")
	assert_eq(book.max_rank("threaten"), 20)
	for lv in range(1, 21):
		assert_eq(book.canonical("threaten", lv, "x"), -float(lv), "PAD change L%d" % lv)
		assert_eq(book.canonical("threaten", lv, "y"), -float(lv), "WDEF change L%d" % lv)
		assert_eq(book.canonical("threaten", lv, "time"), 44.0 + 4.0 * (lv - 1), "time L%d" % lv)
		assert_eq(book.canonical("threaten", lv, "mobCount"), 6.0)
		assert_false(book.level_node("threaten", lv).has("prop"), "the node has no success chance (L%d)" % lv)
	assert_eq(book.canonical("threaten", 1, "mpCon"), 12.0)
	assert_eq(book.canonical("threaten", 20, "mpCon"), 20.0)
	library.free()


func test_the_mob_overlay_and_cast_effect_art_load_from_the_cache() -> void:
	if not require_cache():
		return
	var library := AssetLibrary.new()
	library.open()
	var overlay := library.find_anim(MobRenderer.STATUS_PATHS[MobRenderer.THREATEN_CUE])
	if overlay == null:
		skip("the cache has no Skill.wz/120.img (import with the Warrior second-job manifest)")
		library.free()
		return
	assert_eq(overlay.frames.size(), 8, "the WZ mob node has eight overlay frames")
	assert_true(library.find_anim("Skill.wz/120.img/skill/1201006/effect") != null, "the cast effect")
	assert_true(library.sound("Sound.wz/Skill.img/1201006/Use") != null, "the cast sound")
	library.free()


# --- the status ------------------------------------------------------------------------------------------------------

func test_a_threatened_mob_loses_pad_and_wdef_but_never_below_zero() -> void:
	var w := _world()
	var m := _put(w, 380)
	assert_eq(w.swarm.threatened_pad(m, 82.0), 82.0, "untouched mobs keep their canonical PAD")
	assert_eq(w.mob_defense(m, false), 12.0)
	assert_true(_threaten(w, m, 60.0, -30.0, -5.0))
	assert_eq(w.swarm.threatened_pad(m, 82.0), 52.0)
	assert_eq(w.mob_defense(m, false), 7.0, "the level's flat WDEF cut")
	assert_eq(w.mob_defense(m, true), 40.0, "magic defence is not touched")
	assert_eq(w.swarm.threatened_pad(m, 20.0), 0.0, "PAD floors at 0")
	_threaten(w, m, 60.0, -30.0, -50.0)
	assert_eq(w.mob_defense(m, false), 0.0, "WDEF floors at 0")


func test_the_bulk_projectile_defence_matches_the_per_slot_one() -> void:
	var w := _world()
	var a := _put(w, 380)
	var b := _put(w, 360)
	_threaten(w, a, 60.0, -30.0, -5.0)
	w._fill_live_defense()
	assert_eq(w._live_pdd[a], w.mob_defense(a, false))
	assert_eq(w._live_pdd[a], 7.0)
	assert_eq(w._live_pdd[b], 12.0)
	assert_eq(w._live_pdd[b], w.mob_defense(b, false))


func test_a_threatened_mobs_contact_hits_for_less() -> void:
	var dmg := []
	for threatened in [false, true]:
		var w := _world(9)
		var m := _put(w, 400)
		w.mob_kinds[w.swarm.kind[m]].pad = 82
		if threatened:
			_threaten(w, m, 60.0, -30.0, -5.0)
		w.drain_events()
		w._player_hit(m, w.mob_kinds[w.swarm.kind[m]])
		var hits := w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "player_hit")
		assert_eq(hits.size(), 1)
		dmg.append(int(hits[0].damage))
	assert_true(dmg[1] < dmg[0], "threatened %d < normal %d" % [dmg[1], dmg[0]])
	assert_between(float(dmg[0] - dmg[1]), 25.0, 30.0, "the same seeded roll over 30 less PAD (85-100% of 30)")


func _attack_setup(type: int, magic: bool) -> Dictionary:
	var setup := MF.setup()
	var info: Dictionary = setup.mob_imgs[MF.TAURO].attack1.info
	info.magic = 1.0 if magic else 0.0
	if type != 0:
		info.type = float(type)
		info.range = {"r": 300.0, "sp": {"$v": [-20.0, -40.0]}}
	if type == 2:
		info["bulletSpeed"] = 300.0
		info["ball"] = RF._anim(2, 100.0, 20, 20)
	return setup


## The damage of the first ordinary-attack hit on the player from a Tauro, threatened by `x` PAD or not.
func _attack_damage(type: int, magic: bool, x: float) -> int:
	var w := RunWorld.new(_attack_setup(type, magic))
	RF.place_player(w, 400)
	var slot := RF.put_mob(w, MF.TAURO, 600)
	if x != 0.0:
		assert_true(w.swarm.apply_status(slot, THREATENED, {"time": 600.0, "x": x, "y": -5.0}, w.events))
	for tick in 900:
		w.step(DT, MoveInput.new())
		for e: Dictionary in w.drain_events():
			if e.type == "player_hit":
				assert_eq(e.source_kind, "mob_attack")
				return int(e.damage)
	fail("no attack landed (type %d)" % type)
	return -1


func test_a_threatened_mobs_physical_attacks_hit_for_less_whether_area_targeted_or_ball() -> void:
	for type in [0, 1, 2]:
		var normal := _attack_damage(type, false, 0.0)
		var cut := _attack_damage(type, false, -40.0)
		assert_true(normal > 0 and cut > 0 and cut < normal, "type %d: %d -> %d" % [type, normal, cut])
		# dmg_mult 0.5 x 85-100% of 40 PAD
		assert_between(float(normal - cut), 16.0, 20.0, "type %d" % type)


func test_a_threatened_mobs_magic_attack_is_unchanged() -> void:
	assert_eq(_attack_damage(0, true, -40.0), _attack_damage(0, true, 0.0), "Threaten lowers weapon attack only")


func test_the_status_ends_after_its_duration_and_restores_pad_and_wdef() -> void:
	var w := _world()
	var m := _put(w, 700)
	_threaten(w, m, 3.0, -30.0, -5.0)
	assert_true(w.swarm.has_statuses())
	for tick in 179:
		w.step(DT, MoveInput.new())
	assert_true(w.swarm.status_time(m, MobSwarm.THREATENED) > 0.0)
	assert_eq(w.swarm.threatened_pad(m, 82.0), 52.0)
	w.drain_events()
	for tick in 2:
		w.step(DT, MoveInput.new())
	assert_near(w.swarm.status_time(m, MobSwarm.THREATENED), 0.0)
	assert_eq(w.swarm.threatened_pad(m, 82.0), 82.0)
	assert_eq(w.mob_defense(m, false), 12.0)
	assert_false(w.swarm.has_statuses())
	var expired := w.drain_events().filter(func(e: Dictionary) -> bool:
		return e.type == "mob_status_expired" and e.status == THREATENED)
	assert_eq(expired.size(), 1)


func test_reapplying_refreshes_the_duration_and_replaces_the_cut_without_stacking() -> void:
	var w := _world()
	var m := _put(w, 700)
	_threaten(w, m, 3.0, -30.0, -5.0)
	for tick in 60:
		w.step(DT, MoveInput.new())
	_threaten(w, m, 3.0, -20.0, -4.0)
	assert_near(w.swarm.status_time(m, MobSwarm.THREATENED), 3.0, 1e-6, "the full duration again")
	assert_eq(w.swarm.threatened_pad(m, 82.0), 62.0, "the newest cut, not 30 + 20")
	assert_eq(w.mob_defense(m, false), 8.0)


func test_a_threatened_slowed_and_poisoned_mob_keeps_all_three() -> void:
	var w := _world()
	var m := _put(w, 700)
	assert_true(w.swarm.apply_status(m, "slow", {"time": 2.0, "x": -40.0}, w.events))
	assert_true(w.swarm.apply_status(m, "poison", {"time": 3.0, "level": 10, "skill": "poison_breath"}, w.events))
	_threaten(w, m, 4.0, -30.0, -5.0)
	for tick in 60:
		w.step(DT, MoveInput.new())
	for s in [MobSwarm.SLOW, MobSwarm.POISON, MobSwarm.THREATENED]:
		assert_true(w.swarm.status_time(m, s) > 0.0, "status %d still runs" % s)
	assert_eq(w.swarm.threatened_pad(m, 82.0), 52.0)
	assert_near(w.swarm.slow_factor[m], 0.6)
	for tick in 130: # the slow ended at 2 s, the poison at 3 s (190 ticks = 3.17 s): Threaten outlives both
		w.step(DT, MoveInput.new())
	assert_near(w.swarm.status_time(m, MobSwarm.SLOW), 0.0)
	assert_near(w.swarm.status_time(m, MobSwarm.POISON), 0.0)
	assert_true(w.swarm.status_time(m, MobSwarm.THREATENED) > 0.0)
	assert_eq(w.swarm.threatened_pad(m, 82.0), 52.0)
	assert_near(w.swarm.slow_factor[m], 1.0)


func test_threatened_leaves_with_the_mob_and_a_fresh_spawn_does_not_inherit_it() -> void:
	var w := _world()
	var m := _put(w, 380)
	_threaten(w, m)
	w.swarm.despawn(m)
	assert_false(w.swarm.has_statuses())
	var fresh := _put(w, 380)
	assert_eq(fresh, m, "the slot is reused")
	assert_eq(w.swarm.threatened_pad(fresh, 82.0), 82.0)
	assert_eq(w.mob_defense(fresh, false), 12.0)
	_threaten(w, fresh)
	var moved := w.relocate_mob(fresh, Vector2(500, 190), w.player.fh)
	assert_eq(w.swarm.threatened_pad(moved, 82.0), 82.0, "relocation resets statuses as on a fresh spawn")


func test_bosses_never_take_it() -> void:
	var w := _world()
	var boss := _put(w, 380)
	w.swarm.steady[boss] = 1
	assert_false(_threaten(w, boss))
	assert_eq(w.swarm.threatened_pad(boss, 82.0), 82.0)
	var kind_boss := RF.put_mob(w, 2220000, 360)
	assert_false(_threaten(w, kind_boss), "a boss-flagged kind rejects it too")


# --- the cast --------------------------------------------------------------------------------------------------------

func test_a_crowd_near_casts_threatens_up_to_mob_count_nearest_never_a_boss_and_pays_once() -> void:
	var w := _world()
	var a := _put(w, 380)
	var b := _put(w, 360)
	var boss := _put(w, 370)
	w.swarm.steady[boss] = 1
	_put(w, 700)
	var mp := int(w.player_state.mp)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 0, "two eligible mobs are not a crowd (bosses and far mobs do not count)")
	assert_eq(w.player_state.mp, mp)
	var c := _put(w, 340)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_eq(w.player_state.mp, mp - 7, "canonical MP, once")
	assert_near(w.swarm.status_time(a, MobSwarm.THREATENED), 3.0)
	assert_near(w.swarm.status_time(b, MobSwarm.THREATENED), 3.0)
	assert_near(w.swarm.status_time(c, MobSwarm.THREATENED), 0.0, 1e-6, "mobCount 2 caps it to the nearest two")
	assert_near(w.swarm.status_time(boss, MobSwarm.THREATENED), 0.0)
	assert_eq(w.swarm.threatened_pad(a, 82.0), 72.0, "level 1: x = -10")
	assert_eq(w.mob_defense(a, false), 7.0, "level 1: y = -5")
	var events := w.drain_events()
	assert_eq(_applied(events, THREATENED).size(), 2)
	assert_eq(_applied(events, "slow").size(), 0, "no Slow came with it")
	assert_eq(events.filter(func(e: Dictionary) -> bool: return e.type == "cast").size(), 1)
	w.runner.step(1.0, w)
	assert_eq(w.runner.casts, 1, "the third mob alone is no crowd; the threatened two do not count again")


func _tick(w: RunWorld) -> void:
	w.runner.step(DT, w)
	w.swarm.step(DT, {"fhm": w.fhm, "target": w.player.pos, "target_fh": w.player.fh, "bounds": w.bounds,
		"events": w.events, "speed_mult": 0.0})


func test_it_recasts_once_the_crowd_is_fresh_again_and_a_higher_rank_cuts_more() -> void:
	var w := _world()
	var mobs := [_put(w, 380), _put(w, 360), _put(w, 340)]
	w.loadout.set_rank("threaten", 3)
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1)
	assert_near(w.swarm.status_time(mobs[0], MobSwarm.THREATENED), 9.0)
	assert_eq(w.swarm.threatened_pad(mobs[0], 82.0), 52.0, "level 3: x = -30")
	assert_eq(w.mob_defense(mobs[0], false), 0.0, "level 3: y = -15 floors the mob's 12 WDEF at 0")
	for tick in 540: # 9 s less a tick: both threatened mobs still carry it and the third is no crowd on its own
		_tick(w)
	assert_eq(w.runner.casts, 1)
	for tick in 3: # the first two expire; with the never-threatened third that is a fresh crowd of three again
		_tick(w)
	assert_eq(w.runner.casts, 2, "a second cast once all three are eligible again")
	assert_near(w.swarm.status_time(mobs[0], MobSwarm.THREATENED), 9.0, 0.1, "the new cast starts a fresh duration")
	assert_true(w.swarm.status_time(mobs[2], MobSwarm.THREATENED) > 0.0 or w.swarm.status_time(mobs[1], MobSwarm.THREATENED) > 0.0)


func test_slow_and_threaten_eligibility_are_independent() -> void:
	var w := _world()
	var mobs := [_put(w, 380), _put(w, 360), _put(w, 340)]
	for m: int in mobs:
		assert_true(w.swarm.apply_status(m, "slow", {"time": 60.0, "x": -40.0}, w.events))
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "slowed mobs still satisfy Threaten's crowd")
	assert_true(w.swarm.status_time(mobs[0], MobSwarm.THREATENED) > 0.0)
	var only_threatened := _put(w, 300)
	_threaten(w, only_threatened)
	assert_true(w.swarm.can_crowd_cast(only_threatened, "slow", 0), "a threatened mob is still a Slow target")
	assert_false(w.swarm.can_crowd_cast(only_threatened, THREATENED, 0), "and no Threaten target until it ends")
	assert_false(w.swarm.can_crowd_cast(mobs[0], "slow", 0), "a slowed mob is no Slow target")
	assert_true(w.swarm.can_crowd_cast(_put(w, 290), THREATENED, 0))
	assert_false(w.swarm.can_crowd_cast(only_threatened, "no_such_status", 0))


func test_casting_threaten_draws_no_random_number() -> void:
	var before := {}
	var after := {}
	for cast in [false, true]:
		var w := _world(77)
		_put(w, 380)
		_put(w, 360)
		_put(w, 340)
		if cast:
			w.runner.step(DT, w)
			assert_eq(w.runner.casts, 1)
		var states := {}
		for prop: Dictionary in w.get_property_list():
			var v: Variant = w.get(prop.name)
			if v is RandomNumberGenerator:
				states[String(prop.name)] = (v as RandomNumberGenerator).state
		(after if cast else before).merge(states)
	assert_false(before.is_empty(), "fixture: the world exposes its streams")
	assert_eq(after, before, "every RNG stream is untouched by a Threaten cast (no prop: it always succeeds)")


func test_the_level_up_preview_labels_the_cut_not_slow() -> void:
	var w := _world()
	w.loadout.set_rank("threaten", 1)
	var shown := w.upgrades.choice_card("threaten_rank", w)
	assert_eq(String(shown.skill_effect_stat), THREATENED)


func test_the_level_line_and_description_use_the_survivor_text_with_no_party() -> void:
	var w := _world()
	var text := SkillText.new(w.book, {"1201006": {"name": "Threaten",
		"desc": "[Master Level : 20]\\nUse MP to temporarily threaten a monster.", "h2": "wz line"}})
	assert_eq(text.level_line("threaten", 2, w.loadout.stats("threaten", 2)),
		"MP -7; enemy weapon attack -20, weapon def. -10 for 6 sec., up to 2 monsters")
	assert_eq(text.desc("threaten"), "Use MP to threaten the monsters around you, lowering their weapon attack and weapon defence.")
	assert_false("party" in text.desc("threaten").to_lower())


func _img(path: String) -> Dictionary:
	var parsed: Variant = DataRepo.load_json(AssetCachePaths.resolve_cache_root().path_join(path + ".json"))
	return parsed if parsed is Dictionary else {}


## The whole real-data path: the Page on the real Henesys map with the real 120.img level 5 (x = y = -5, 60 s, 12 MP).
func test_real_cache_cast_threatens_a_crowd_with_the_v83_level() -> void:
	if not require_cache():
		return
	var data := DataRepo.load_all()
	data.balance.player.mp = 300
	data.balance.player.skills = []
	var setup := DataRepo.build_setup(data, "henesys_hg1", 183, Vector2(800, 600), _img,
		func(id: int) -> Dictionary: return _img("Mob.wz/%07d.img" % id))
	if not setup.skill_imgs.has("120"):
		skip("the cache has no Skill.wz/120.img (import with the Warrior second-job manifest)")
		return
	var w := RunWorld.new(setup)
	w.change_job(120)
	w.learn_skill("threaten")
	w.loadout.set_rank("threaten", 5)
	w.god = true
	var id: int = DataRepo.stage_mob_ids(data, "henesys_hg1")[0]
	var mobs: Array = []
	for dx in [-40.0, -80.0, -120.0, 50.0, 90.0, 130.0, 170.0]:
		mobs.append(RF.put_mob(w, id, w.player.pos.x + dx, w.player.pos.y))
	w.mob_grid.rebuild(w.swarm.x, w.swarm.y, w.swarm.active)
	var mp := int(w.player_state.mp)
	w.drain_events()
	w.runner.step(DT, w)
	assert_eq(w.runner.casts, 1, "seven monsters in the 250 x 150 box: a crowd")
	assert_eq(int(w.player_state.mp), mp - 12, "canonical mpCon of level 5")
	var threatened := mobs.filter(func(m: int) -> bool: return w.swarm.status_time(m, MobSwarm.THREATENED) > 0.0)
	assert_eq(threatened.size(), 6, "mobCount 6 of the seven")
	assert_near(w.swarm.status_time(threatened[0], MobSwarm.THREATENED), 60.0)
	assert_eq(w.swarm.threatened_pad(threatened[0], 20.0), 15.0)
	assert_eq(_applied(w.drain_events(), THREATENED).size(), 6)
