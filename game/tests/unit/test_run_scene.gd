extends TestCase
## RunScene (game/scripts/run/run_scene.gd) against the real asset cache (SKIP without it): the scene is added to the
## test's SceneTree with a private AssetLibrary and advanced by calling advance_frame(1/60) directly (one sim tick per
## call). Checks that sim events become visuals (damage numbers, hit effects, sounds, EXP messages, level-up/job
## effects, the wand look, tombstone, stage clear), that the renderers draw exactly the sim's live state, that the HUD
## shows player_state, that D2's windows (LevelUpWindow, JobAdvanceWindow, PauseMenu) open over the run and their
## answers (keys through handle_input, signals) drive the sim, that autopick resolves choices without windows, and that
## nothing is missing from the cache. The launcher's argument parsing needs no cache.

const STAGE_FIXTURES := preload("res://tests/fixtures/run_fixtures.gd")

const DT := 1.0 / 60.0


func test_map_clear_holds_then_reloads_art_music_camera_and_pooled_actors() -> void:
	if not require_cache():
		return
	for id: int in [104010001, 100030001]:
		if lib.img(AssetLibrary.map_img_path(id)) == null:
			skip("three-map cache is missing map %d" % id)
			return
	scene = _make("henesys_hg1", 246, {"autopick": true})
	# Adapt the real setup explicitly; this does not depend on the interim MAP_CHAINS fixture.
	var setup := scene.world.setup.duplicate(true)
	var stage: Dictionary = setup.data.stages.stages[scene.stage_key]
	var maps: Array = []
	setup.map_imgs = []
	for id: int in [104040000, 104010001, 100030001]:
		maps.append({"map_id": id, "pool": "curve", "boss": {"mob_id": 2220000, "time": 0.1,
			"rewards": {"bonus_choices": 0, "exp_mult": 0.0}}})
		setup.map_imgs.append(lib.img(AssetLibrary.map_img_path(id)).root)
	stage.maps = maps
	stage.map_seconds = 300.0
	scene.world = RunWorld.new(setup)
	scene.world.god = true
	_frames(8)
	var old_mobs: Array[WeakRef] = []
	for mr in scene.mob_renderers:
		old_mobs.append(weakref(mr))
	var old_shots: WeakRef = weakref(scene.shots)
	var old_drops: WeakRef = weakref(scene.drops)
	var sfx := scene.get_node("/root/Sfx") as AudioService
	var old_bgm := sfx.current_bgm
	var w := scene.world
	var slot := int(w.bosses.records[0].slot)
	assert_true(slot >= 0)
	w.hit_mob(slot, {"damage_min": 1e9, "damage_max": 1e9, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	_frames(2)
	assert_true(w.transfer_pending, "the clear notice holds the deterministic sim boundary")
	assert_eq(scene.map.map_id, 104040000, "the old map stays visible for the notice")
	var time := w.time
	_frames(190)
	var fade := scene.get_node("MapTransfer/Fade") as ColorRect
	assert_true(fade.color.a > 0.0 and fade.color.a < 1.0, "fade out is visible before the reload")
	scene.open_pause()
	var opacity := fade.color.a
	_frames(120)
	assert_eq(w.time, time, "pause holds both simulation and the fade")
	assert_eq(fade.color.a, opacity)
	assert_eq(scene.map.map_id, 104040000)
	scene.resume()
	_frames(14)
	assert_eq(fade.color.a, 1.0, "one fully black frame precedes the reload")
	_frames(1)
	assert_eq(w.time, time, "advance_map and reload admit no combat tick")
	assert_eq(scene.map.map_id, 104010001)
	assert_eq(fade.color.a, 1.0, "destination loads behind black")
	assert_true(scene.toggle_window("stat"), "in-run windows remain usable during transfer")
	_frames(120)
	assert_eq(w.time, time)
	assert_eq(fade.color.a, 1.0)
	scene.toggle_window("stat")
	_frames(90)
	assert_eq(w.map_index, 1)
	assert_eq(scene.map.map_id, 104010001)
	assert_eq(scene.map_id, 104010001)
	assert_eq(scene.cam.bounds, w.bounds)
	assert_true(scene.cam.is_current(), "the viewport keeps an active arrival camera")
	assert_true(scene.cam.view_rect().has_point(w.player.pos), "arrival is framed inside the new bounds")
	assert_eq(sfx.current_bgm, AssetLibrary.bgm_path(String(scene.map.map_root.info.bgm)))
	assert_true(sfx.current_bgm != old_bgm, "the destination's own music starts")
	for mr in old_mobs:
		assert_true(mr.get_ref() == null, "old mob canvas pools have been freed")
	assert_true(old_shots.get_ref() == null)
	assert_true(old_drops.get_ref() == null)
	assert_eq(scene.build_summary().map_name, "The Pig Beach")
	assert_eq(scene.build_summary().region, "Henesys")
	assert_eq(scene.build_summary().street_name, lib.string_name("Street", 104010001))
	assert_true(w.time >= time)
	assert_eq(scene._title, PackedStringArray(["Hidden Street", "The Pig Beach"]), "arrival uses the round title style")
	# A second transfer must release the replacement pools too, and report the third map if the round ends there.
	var second_mobs: Array[WeakRef] = []
	for mr in scene.mob_renderers:
		second_mobs.append(weakref(mr))
	w.hit_mob(int(w.bosses.records[1].slot), {"damage_min": 1e9, "damage_max": 1e9, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	_frames(300)
	assert_eq(scene.map.map_id, 100030001)
	assert_true(scene.cam.is_current())
	assert_true(scene.cam.view_rect().has_point(w.player.pos))
	assert_eq(scene.build_summary().map_id, 100030001)
	assert_eq(scene.build_summary().map_name, "The Blue Mushroom Forest")
	for mr in second_mobs:
		assert_true(mr.get_ref() == null, "the second transfer also frees the old mob pools")
	_assert_nothing_missing(scene, "map transfer")


func test_round_keeps_selected_appearance_when_job_weapon_changes() -> void:
	if not require_cache():
		return
	var original := RunWorld.new({"data": DataRepo.load_all()}).character_snapshot()
	original.look = {"skin": 3, "face": 21002, "hair": 31057}
	original.equipment.worn = Equipment.worn_from_ids([1041011, 1061008, 1072038, 1322005], {})
	scene = _make("henesys", 70, {"character": original})
	assert_eq(scene.avatar.look, {"skin": 3, "face": 21002, "hair": 31057,
		"equips": [1041011, 1061008, 1072038, 1322005]})
	scene.world.change_job(200)
	_frames(1)
	assert_eq(scene.avatar.look, {"skin": 3, "face": 21002, "hair": 31057,
		"equips": [1041011, 1061008, 1072038, 1372005]})
	_assert_nothing_missing(scene, "selected look and job weapon")


func test_initial_presentation_uses_the_map_reached_before_building() -> void:
	if not require_cache():
		return
	var destination := lib.img(AssetLibrary.map_img_path(104010001))
	if destination == null:
		skip("three-map cache is missing The Pig Beach")
		return
	var arrive := func(w: RunWorld) -> void:
		w.stage.maps = [{"map_id": 104040000, "boss": {"mob_id": 2220000, "time": 300.0}},
			{"map_id": 104010001, "boss": {"mob_id": 6130101, "time": 300.0}}]
		w.setup.map_imgs = [w.setup.map_img, destination.root]
		w.transfer_pending = true
		w.advance_map() # same boundary used by a headless warp, before any renderer exists
	scene = _make("henesys_hg1", 246, {"world_prepared": arrive})
	assert_eq(scene.map.map_id, 104010001)
	assert_eq(scene.cam.bounds, scene.world.bounds)
	assert_eq(scene.player_group.position, scene.world.player.pos.round())
	assert_eq(scene.build_summary().map_name, "The Pig Beach")
	assert_eq(scene._title, PackedStringArray(["Hidden Street", "The Pig Beach"]), "a warp into a later map shows its arrival name")
	_assert_nothing_missing(scene, "arrived before presentation")


func test_summary_reports_round_levels_bosses_and_nx() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 5, {})
	var w := scene.world
	var start := w.progression.level
	w.progression.add_exp(w.progression.exp_to_next())
	w.progression.queue.clear()
	var summary := scene.build_summary()
	assert_eq(int(summary.levels_gained), w.progression.level - start)
	assert_eq(int(summary.levels_gained), 1)
	assert_eq(int(summary.bosses_killed), 0)
	assert_eq(int(summary.nx_awarded), int(w.balance.nx_award.per_level), "alive at the end of an unfinished round: levels only, no clear bonus")
	assert_eq(int(summary.nx_awarded), w.nx_awarded())


func test_banner_and_summary_name_the_region_not_the_map() -> void:
	if not require_cache():
		return
	var want := {"henesys": ["Victoria Island", "Henesys"], "ellinia": ["Victoria Island", "Ellinia"],
		"sleepywood": ["Victoria Island", "Sleepywood"]}
	for key: String in want:
		scene = _make(key, 5, {})
		assert_eq(scene._title, PackedStringArray(want[key]), "%s: continent small above the region" % key)
		assert_true(scene._title_t > 0.0, "%s: the banner is showing" % key)
		var summary := scene.build_summary()
		assert_eq(String(summary.region), want[key][1], key)
		assert_eq(String(summary.continent), want[key][0], key)
		assert_true(String(summary.map_name) != "" and String(summary.map_name) != String(summary.region),
			"%s: the WZ map name stays in the summary for tools" % key)


func test_one_off_character_file_option_restores_character() -> void:
	if not require_cache():
		return
	var original := preload("res://tests/fixtures/run_fixtures.gd").quiet_world()
	original.change_job(210)
	var character := original.character_snapshot()
	character.level = 35
	character.exp = 17
	# A Lv 35 character holds the scheduled potions (a load would catch Red and Blue up to these).
	var path := ProjectSettings.globalize_path(test_dir("one off character.json"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(character))
	file.close()
	scene = _make("henesys", 1, {"character": path, "autoplay": true, "autopick": true})
	assert_eq(scene.world.character_snapshot(), character)
	assert_eq(int(scene.world.player_state.level), 35)
	_assert_nothing_missing(scene, "one-off character file")

func test_account_option_reaches_the_round_setup() -> void:
	if not require_cache():
		return
	var path := ProjectSettings.globalize_path(test_dir("run account.json"))
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"owned": [1002279, 5000001], "cash": {"hat": 1002279}, "pet": 5000001,
		"alert": {"hp": 0.4, "mp": 0.2}}))
	file.close()
	scene = _make("henesys", 1, {"account": path, "autoplay": true, "autopick": true})
	assert_eq(scene.world.player_state.fortune, 10.0, "the worn hat adds its slot's Fortune")
	assert_eq(scene.world.pet, 5000001)
	assert_eq(scene.world.alert, {"hp": 0.4, "mp": 0.2})
	assert_eq(scene.world.warnings.size(), 0)
	assert_eq(scene.perf_summary().account, "run account.json", "summary.json names the account file")
	_assert_nothing_missing(scene, "tool account file")
	var plain := _make("henesys", 1, {"autoplay": true, "autopick": true})
	assert_eq(plain.world.player_state.fortune, 0.0)
	assert_false(plain.perf_summary().has("account"))
	plain.free()


var lib: AssetLibrary
var scene: RunScene
var finished: Array = []


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open()
	finished = []


func after_each() -> void:
	if scene != null and is_instance_valid(scene):
		scene.free()
	scene = null
	lib.free()


func _make(stage: String, p_seed: int, options: Dictionary) -> RunScene:
	var s: RunScene = (load(RunScene.SCENE_PATH) as PackedScene).instantiate()
	s.library = lib
	var o := options.duplicate()
	o["use_flow"] = false
	s.configure(stage, p_seed, o)
	s.run_finished.connect(func(summary: Dictionary) -> void: finished.append(summary))
	# The runner executes tests inside its own _ready, while the root is still busy adding children: add the scene
	# under the runner (the current scene) instead.
	var tree := Engine.get_main_loop() as SceneTree
	(tree.current_scene if tree.current_scene != null else tree.root).add_child(s)
	return s


func _frames(n: int) -> void:
	for i in n:
		scene.advance_frame(DT)


## HUD/finale probes use an explicit legacy single-map schedule, including simultaneous bosses. Real region
## schedules require map_index/map_time and settle maps 0/1 as transfers, not as the round finale.
func _single_map_bosses(entries: Array, rules: Dictionary = {}) -> void:
	var w := scene.world
	w.stage = w.stage.duplicate(true)
	w.stage["map_id"] = w.current_map_id()
	w.stage.erase("maps")
	w.stage["bosses"] = entries.duplicate(true)
	w.bosses = BossDirector.new(entries, rules)
	assert_false(w.map_sequence_enabled(), "this probe deliberately uses the legacy single-map lifecycle")


## Live slots plus dying ones (MobRenderer draws STAND..DIE).
func _drawn_mob_slots(w: RunWorld) -> int:
	var n := 0
	for i in w.swarm.capacity():
		if w.swarm.state[i] <= MobRenderer.DIE:
			n += 1
	return n


func _mob_visible(s: RunScene) -> int:
	var n := 0
	for mr in s.mob_renderers:
		n += mr.visible_count()
	return n


func _assert_nothing_missing(s: RunScene, label: String) -> void:
	assert_eq(interim_missing(lib.missing, s.data, s.stage_key).size(), 0, "%s: library misses %s" % [label, lib.missing])
	assert_eq(s.map.missing.size(), 0, "%s: map misses %s" % [label, s.map.missing])
	assert_eq(s.avatar.missing.size(), 0, "%s: avatar misses %s" % [label, s.avatar.missing])
	for mr in s.mob_renderers:
		assert_eq(mr.missing.size(), 0, "%s: mob renderer misses %s" % [label, mr.missing])
	assert_eq(interim_missing(s.setup_missing, s.data, s.stage_key).size(), 0, "%s: setup misses %s" % [label, s.setup_missing])


## The skill icons show the run's skills (icon, rank, key) with the cooldown of the latest frame.
func _assert_skill_icons_match(s: RunScene) -> void:
	var expected: Array[Dictionary] = []
	for row: Dictionary in s.run_info().skills:
		expected.append({"icon": row.icon, "rank": row.rank, "key_label": row.key_label,
			"sweep_step": HudSkills.sweep_step(row.cooldown_left, row.cooldown_total), "mp_short": row.mp_short,
			"blocked": row.blocked})
	assert_eq(s.hud.skills.displayed(), expected, "skill widget fed by the run scene")


func _assert_hud_matches(s: RunScene) -> void:
	assert_eq(s.hud.status.player_state, s.world.player_state, "status widget fed by the run scene")
	assert_eq(s.hud.counters.run_info.kills, s.world.kills, "counter widget fed by the run scene")
	_assert_skill_icons_match(s)
	assert_eq(s.hud.quick_slot.get_parent(), s.hud, "quick slot has its own widget")
	assert_eq(s.hud.buff_row.get_parent(), s.hud, "buffs have their own widget")
	assert_eq(s.hud.boss_bar.get_parent(), s.hud, "boss bar has its own widget")
	var ps := s.world.player_state
	for k: String in ["hp", "mp", "max_hp", "max_mp", "exp", "level", "job_id"]:
		assert_eq(int(s.hud.player_state.get(k, -1)), int(ps[k]), "HUD %s" % k)
	assert_eq(int(s.hud.run_info.kills), s.world.kills, "HUD kills")
	assert_eq(int(s.hud.run_info.exp_next), int(ps.exp_next), "HUD exp_next")
	assert_eq(int(s.hud.run_info.time), int(s.run_time()), "HUD time (the run time snapped to 1 ms)")
	assert_eq((s.hud.run_info.skills as Array).size(), s.world.loadout.order.size(), "HUD skill icons")
	assert_eq(String(s.hud.run_info.job_name), s.world.jobs.name_of(int(ps.job_id)), "HUD job name")


func test_autoplay_two_minutes_draws_the_sim() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 7, {"autoplay": true, "autopick": true})
	assert_eq(scene.error, "", "scene started")
	assert_true(1302000 in scene.avatar.look.equips, "the first Beginner frame includes the Sword")
	var w := scene.world
	assert_true(w != null, "world built")
	# Include every map's life pool and canonical boss summons/revives, as build_setup does when preloading.
	var expected_ids := DataRepo.stage_mob_ids(scene.data, scene.stage_key, w.setup.mob_imgs,
		w.setup.mob_skill_img, w.setup.map_imgs)
	assert_eq(w.mob_kinds.size(), expected_ids.size(), "every region pool mob has an img")
	for id: int in expected_ids:
		assert_false(lib.mob_root(id).is_empty(), "mob %d exists in the real cache" % id)
		assert_true(w.setup.mob_imgs.has(id), "mob %d was preloaded" % id)
		assert_true(w.kind_of_id.has(id), "mob %d has a sim kind" % id)
	assert_true(scene.mob_renderers.size() >= 1, "a mob renderer per floor layer")
	var max_numbers := 0
	var max_fx := 0
	var max_shots := 0
	var mismatches := 0
	var stances := {}
	for i in 60 * 120:
		scene.advance_frame(DT)
		max_numbers = maxi(max_numbers, scene.numbers.active_count())
		max_fx = maxi(max_fx, scene.fx.active_count())
		max_shots = maxi(max_shots, scene.shots.visible_count())
		stances[scene.avatar.stance] = true
		if i % 30 == 0:
			if _mob_visible(scene) != _drawn_mob_slots(w):
				mismatches += 1
			assert_eq(scene.shots.visible_count(), w.projectiles.active_count(), "shots drawn == in flight")
			assert_eq(scene.drops.visible_count(), w.pickups.active_count(), "drops drawn == active")
		if w.state == RunWorld.DEAD:
			break
	print("run_scene autoplay: %.0f s %s Lv %d kills %d counters %s stances %s" % [w.time, w.state_name(),
		w.player_state.level, w.kills, scene.counters, stances.keys()])
	assert_eq(mismatches, 0, "mobs drawn == live + dying slots every check")
	assert_true(w.kills > 10, "Three Snails killed mobs (%d)" % w.kills)
	assert_true(int(scene.counters.numbers) >= w.kills, "a damage number per hit at least")
	assert_true(int(scene.counters.hit_fx) > 0, "hit effects played")
	assert_true(int(scene.counters.sounds) > 0, "sounds played")
	assert_true(int(scene.counters.exp_messages) > 0, "EXP messages shown")
	assert_true(max_numbers > 0 and max_fx > 0 and max_shots > 0, "numbers %d fx %d shots %d on screen" % [
		max_numbers, max_fx, max_shots])
	assert_true(int(w.player_state.level) >= 3, "levelled up (%d)" % int(w.player_state.level))
	assert_true(int(scene.counters.autopicks) >= int(w.player_state.level) - 1, "every level-up resolved")
	assert_true(stances.has("walk1") and stances.has("stand1"), "walk and stand shown (%s)" % [stances.keys()])
	assert_true(stances.has("swingO1"), "the cast stance was shown (%s)" % [stances.keys()])
	assert_true(scene.hud.messages().size() >= 0)
	_assert_hud_matches(scene)
	_assert_nothing_missing(scene, "autoplay")


func test_events_become_visuals() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 3, {})
	var w := scene.world
	_frames(2)
	var p := w.player.pos
	var f := w.fhm.find_below(p.x + 60.0, p.y - 5.0)
	var slot := w.spawn_mob(int(w.kind_of_id[100100]), Vector2(p.x + 60.0, w.fhm.y_at(f, p.x + 60.0)), f, 1.0, false)
	w.drain_events()
	var n0 := scene.numbers.active_count()
	var fx0 := scene.fx.active_count()
	scene.handle_events([{"type": "mob_hit", "mob": slot, "mob_id": 100100, "damage": 12, "crit": false,
		"pos": Vector2(p.x + 60.0, p.y - 30.0), "hit_visual": "Skill.wz/000.img/skill/0001000/level/1/hit/0",
		"skill": "three_snails"}])
	assert_eq(scene.numbers.active_count(), n0 + 1, "damage number")
	assert_eq(scene.fx.active_count(), fx0 + 1, "hit effect")
	scene.handle_events([{"type": "player_hit", "damage": 7, "mp_absorbed": 0, "miss": false, "dir": 1, "pos": p}])
	assert_eq(scene.numbers.active_count(), n0 + 2, "taken number")
	assert_eq(scene.avatar.current_expression(), "hit", "hit face")
	scene.handle_events([{"type": "level_up", "level": 2}])
	assert_eq(scene.fx.active_count(), fx0 + 2, "LevelUp effect")
	scene.world.drain_events()
	scene.world.change_job(200) # job_changed, then the Wooden Wand grant's equipment_changed
	scene.handle_events(scene.world.drain_events())
	assert_true(1372005 in scene.avatar.look.equips, "the Magician holds the granted Wooden Wand")
	assert_true(scene.fx_back.active_count() >= 1, "JobChanged (z < 0) plays behind the character")
	scene.handle_events([{"type": "pickup_collected", "pickup": 0, "item_id": 4000019, "exp": 5, "pos": p},
		{"type": "pickup_collected", "pickup": 1, "item_id": 4000019, "exp": 7, "pos": p}])
	scene.advance_frame(DT)
	var texts: Array = []
	for m: Dictionary in scene.hud.messages():
		texts.append(m.text)
	assert_true("+12 EXP" in texts, "one EXP message per frame (%s)" % [texts])
	_assert_nothing_missing(scene, "events")


func test_boss_warning_and_arrival_messages_survive_exp_message_pressure() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 2101, {})
	scene.handle_events([{"type": "boss_warning", "boss_index": 0, "mob_id": 2220000, "time": 297.0}])
	for i in 12:
		scene.hud.show_exp(i + 1)
	var texts := scene.hud.messages().map(func(m: Dictionary) -> String: return m.text)
	assert_true("Mano will appear in 3 seconds!" in texts, "EXP churn cannot evict the boss warning")
	var before := scene.fx.active_count()
	scene.handle_events([{"type": "boss_spawned", "boss_index": 0, "mob": 0, "mob_id": 2220000,
		"pos": scene.world.player.pos, "time": 300.0}])
	var appeared := false
	for message: Dictionary in scene.hud.messages():
		if message.text == "Mano has appeared!":
			appeared = true
			assert_eq(message.color, Hud.SYSTEM_YELLOW)
	assert_true(appeared, "yellow system arrival message")
	assert_eq(scene.fx.active_count(), before + 1, "canonical respawn effect plays at the boss")
	scene.hud.advance_messages(4.01)
	assert_eq(scene.hud.messages().size(), 0, "encounter notices expire after their visible lifetime")
	_assert_nothing_missing(scene, "boss messages")


func test_live_boss_bar_tracks_hp_and_hides_on_death() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 2102, {})
	_single_map_bosses([{"mob_id": 2220000, "time": 0.5, "hp_mult": 2.0}])
	scene.world.god = true
	scene.world.loadout.order.clear()
	scene.world.loadout.ranks.clear()
	var bar: Variant = scene.hud.boss_bar
	assert_eq(bar.displayed().size(), 0, "no boss bar before arrival")
	_frames(31)
	var rows: Array = bar.displayed()
	assert_eq(rows.size(), 1, "arrival creates its bar below the timer")
	if rows.is_empty():
		return
	assert_eq(rows[0].name, "Mano")
	assert_eq(rows[0].hp, 4000)
	assert_eq(rows[0].max_hp, 4000)
	assert_eq(rows[0].icon_path, "UI.wz/UIWindow.img/MobGage/Mob/2220000")
	assert_eq(rows[0].color_path, "UI.wz/UIWindow.img/MobGage/Gage/1/0")
	assert_eq(rows[0].background_path, "UI.wz/UIWindow.img/MobGage/Gage/5/1")
	var slot := int(scene.world.bosses.records[0].slot)
	scene.world.hit_mob(slot, {"damage_min": 2000.0, "damage_max": 2000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	_frames(1)
	assert_eq(bar.displayed()[0].hp, 2000, "fixed damage is visible in the bar on the next frame")
	assert_eq(bar.displayed()[0].ratio, 0.5)
	scene.world.hit_mob(slot, {"damage_min": 100000.0, "damage_max": 100000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	_frames(1)
	assert_eq(bar.displayed().size(), 0, "dead boss is hidden immediately")
	_assert_nothing_missing(scene, "boss bar")


func test_multiple_live_boss_bars_keep_their_own_icons_and_colour_overrides() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 2103, {})
	# Simultaneous bars remain a HUD contract; live region maps intentionally arm only one boss each.
	_single_map_bosses([
		{"mob_id": 2220000, "time": 0.5, "hp_mult": 2.0},
		{"mob_id": 9400205, "time": 0.7, "hp_mult": 0.25},
	])
	scene.world.god = true
	scene.world.loadout.order.clear()
	scene.world.loadout.ranks.clear()
	_frames(43)
	var rows := scene.hud.boss_bar.displayed()
	assert_eq(rows.size(), 2, "both surviving bosses remain visible")
	if rows.size() != 2:
		return
	assert_eq(rows[0].mob_id, 2220000)
	assert_eq(rows[1].name, "Blue Mushmom")
	assert_eq(rows[1].max_hp, 50000)
	assert_eq(rows[1].icon_path, "UI.wz/UIWindow.img/MobGage/Mob/6130101", "Blue Mushmom borrows Mushmom's icon")
	assert_eq(rows[1].color_path, "UI.wz/UIWindow.img/MobGage/Gage/1/0")
	assert_eq(rows[1].background_path, "UI.wz/UIWindow.img/MobGage/Gage/5/1")
	assert_true(rows[0].icon is SpriteFrame and rows[1].icon is SpriteFrame)
	_assert_nothing_missing(scene, "multiple boss bars")


func test_boss_slam_events_play_canonical_effect_and_sound() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 2303, {})
	var pos := scene.world.player.pos + Vector2(180, 0)
	var effect := "Mob.wz/6130101.img/attack1/info/effect"
	var sounds := int(scene.counters.sounds)
	var effects := scene.fx.active_count()
	scene.handle_events([{"type": "boss_attack", "phase": "start", "boss_index": 1,
		"sound": "Sound.wz/Mob.img/6130101/Attack1", "attack": "attack1", "time": 0.0, "impact_time": 1.05},
		{"type": "boss_attack", "phase": "effect", "boss_index": 1,
		"effect": effect, "pos": pos, "facing": -1}])
	assert_eq(scene.counters.sounds, sounds + 1)
	assert_eq(scene.fx.active_count(), effects + 1)
	_assert_nothing_missing(scene, "mushroom slam")


func test_cast_plays_the_action_stance_while_standing() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 5, {})
	var w := scene.world
	_frames(30)
	assert_eq(w.player.state, PlayerMotion.ST_STAND, "standing at the start")
	var p := w.player.pos
	var f := w.fhm.find_below(p.x - 150.0, p.y - 5.0)
	w.spawn_mob(int(w.kind_of_id[100100]), Vector2(p.x - 150.0, w.fhm.y_at(f, p.x - 150.0)), f, 50.0, false)
	var cast_seen := false
	for i in 120:
		scene.advance_frame(DT)
		if scene.avatar.stance == "swingO1":
			cast_seen = true
			break
	assert_true(cast_seen, "Three Snails' swingO1 shown while standing")
	assert_eq(scene.avatar.facing, -1, "turned toward the mob on the left")
	_assert_nothing_missing(scene, "cast")


func test_player_miss_uses_violet_art_without_hit_expression() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 616, {})
	_frames(2)
	var w := scene.world
	w.loadout.add_player_mod("avoid", "add", 1000.0)
	w.refresh_player_stats()
	w.drain_events()
	var numbers := scene.numbers.active_count()
	var expression := scene.avatar.current_expression()
	w.take_hit(82.0, false, "", w.player.pos + Vector2(10, 0), {"accuracy": 42})
	scene.handle_events(w.drain_events())
	assert_eq(scene.numbers.active_count(), numbers + 1, "a MISS is rendered")
	assert_eq(scene.avatar.current_expression(), expression, "a miss does not hurt the avatar")
	assert_true(lib.find("Effect.wz/BasicEff.img/NoViolet0/Miss") != null, "the violet MISS glyph is canonical")
	_assert_nothing_missing(scene, "player miss")


func test_level_up_opens_the_window() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 11, {})
	var w := scene.world
	_frames(2)
	# Exercise opening a choice, independently of the tuned first-level EXP cost.
	w.pickups.spawn(w.player.pos, w.progression.exp_to_next(), 4000019)
	var ticks := 0
	while int(w.player_state.level) < 2 and ticks < 120:
		scene.advance_frame(DT)
		ticks += 1
	assert_eq(int(w.player_state.level), 2, "the drop levelled the player up")
	assert_true(scene.window == null, "the window waits for the LevelUp effect")
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the sim waits for the choice")
	_frames(int(RunScene.WINDOW_DELAY / DT) + 2)
	var lw := scene.window as LevelUpWindow
	assert_true(lw != null, "the LevelUpWindow opened")
	assert_eq(int(scene.counters.autopicks), 0, "no autopick without the option")
	if lw != null:
		assert_eq(lw.get_parent(), scene.windows_layer, "hosted in the windows layer")
		assert_eq(scene.windows_layer.layer, 10)
		assert_eq(lw.cards.size(), w.pending_cards.size(), "the window shows the sim's cards")
		assert_eq(lw.level, 2, "for level 2")
		var t := w.time
		_frames(10)
		assert_eq(w.time, t, "no ticks while the window is open")
		# Key "2" picks the second card (the key path the player uses).
		# A choice the sim rejects reopens the same offer instead of leaving the run choosing with no window.
		var offered: Array = w.pending_cards.map(func(c: Dictionary) -> String: return String(c.id))
		lw.card_chosen.emit("not_offered")
		assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "a rejected choice keeps the sim choosing")
		lw = scene.window as LevelUpWindow
		assert_true(lw != null, "the offer reopened")
		if lw == null:
			return
		assert_eq(lw.cards.map(func(c: Dictionary) -> String: return String(c.id)), offered, "with the same cards")
		var second := String(w.pending_cards[1].id)
		var second_rank := int(w.pending_cards[1].rank)
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_2
		key.physical_keycode = KEY_2
		assert_true(lw.handle_input(key), "the window took the key")
		assert_true(scene.window == null, "closed after the choice")
		assert_eq(int(w.loadout.card_ranks.get(second, 0)), second_rank, "the second card (%s) was applied" % second)
	assert_eq(w.state, RunWorld.PLAYING, "playing again")
	var t_after := w.time
	_frames(2)
	assert_true(w.time > t_after, "ticking again")
	_assert_nothing_missing(scene, "level up")


func test_job_window_reaches_magician() -> void:
	if not require_cache():
		return
	# #199 expands the job pool: this presentation test specifically needs the Magician and its wand.
	scene = _make("henesys", 12, {"window_autopick": 0.05, "job": 200})
	var w := scene.world
	_frames(2)
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(10), 4000019)
	var guard := 0
	while (int(w.player_state.job_id) != 200 or w.state != RunWorld.PLAYING) and guard < 60 * 30:
		scene.advance_frame(DT)
		guard += 1
	assert_eq(int(w.player_state.job_id), 200, "the Magician advancement was taken (level %d)" % int(w.player_state.level))
	assert_true(1372005 in scene.avatar.look.equips, "wand look")
	assert_true(int(scene.counters.windows) >= int(w.player_state.level), "one window per level + the job window")
	assert_eq(int(scene.counters.autopicks), 0, "every choice went through a window")
	_assert_nothing_missing(scene, "job")


func test_job_window_select_and_decline() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 14, {})
	var w := scene.world
	_frames(2)
	# Exactly enough EXP for level 10 (the Magician advancement level).
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(10), 4000019)
	var guard := 0
	while scene.window == null and guard < 60 * 10:
		scene.advance_frame(DT)
		guard += 1
		var lw0 := scene.window as LevelUpWindow
		if lw0 != null:
			lw0.choose(0)
	var jw := scene.window as JobAdvanceWindow
	# Levels 2-9 were answered above; the job window comes first at level 10.
	guard = 0
	while jw == null and guard < 60 * 10:
		scene.advance_frame(DT)
		guard += 1
		var lw := scene.window as LevelUpWindow
		if lw != null:
			lw.choose(0)
		jw = scene.window as JobAdvanceWindow
	assert_true(jw != null, "the JobAdvanceWindow opened (level %d)" % int(w.player_state.level))
	if jw == null:
		return
	assert_eq(jw.level, 10, "at level 10")
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "the sim waits for the job choice")
	# "Not now." keeps the Beginner and continues to the level-10 upgrade window.
	assert_true(jw.any_available(), "Magician is available")
	jw.decline()
	assert_eq(int(w.player_state.job_id), 0, "still a Beginner")
	_frames(int(RunScene.WINDOW_DELAY / DT) + 2)
	assert_true(scene.window is LevelUpWindow, "the level-10 upgrade window follows the decline")
	_assert_nothing_missing(scene, "job decline")


func test_job_change_effect_plays_before_the_next_window() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 15, {})
	var w := scene.world
	_frames(2)
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(10), 4000019)
	var jw: JobAdvanceWindow = null
	var guard := 0
	while jw == null and guard < 60 * 20:
		scene.advance_frame(DT)
		guard += 1
		var lw := scene.window as LevelUpWindow
		if lw != null:
			lw.choose(0)
		jw = scene.window as JobAdvanceWindow
	assert_true(jw != null, "the JobAdvanceWindow opened (level %d)" % int(w.player_state.level))
	if jw == null:
		return
	var anim := lib.find_anim(RunScene.FX_JOB_CHANGED)
	assert_true(anim != null and anim.total > 0.5, "the JobChanged effect is in the cache")
	var total := anim.total if anim != null else RunScene.JOB_WINDOW_DELAY
	# The player takes Magician: the sim already waits in the level-10 card choice, but the window must not cover the
	# JobChanged pillar while it plays.
	jw.job_chosen.emit(200)
	assert_eq(int(w.player_state.job_id), 200, "Magician taken")
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the level-10 card choice is pending in the sim")
	var held := 0
	while scene.window == null and held < 600:
		scene.advance_frame(DT)
		held += 1
	assert_true(scene.window is LevelUpWindow, "the level-10 upgrade window follows")
	assert_between(held * DT, total - 2.0 * DT, total + 3.0 * DT,
		"the window waited for the %.2f s JobChanged effect (%d frames)" % [total, held])
	_assert_nothing_missing(scene, "job effect")


func test_low_mp_cue_tracks_the_waiting_skill_and_clears_after_restoration() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 9, {})
	var world := scene.world
	world.god = true
	world.change_job(200)
	world.spend_mp(int(world.player_state.mp))
	world.spawn_mob(int(world.kind_of_id[100100]), world.player.pos + Vector2(-80, 0), world.player.fh, 1000, false)
	_frames(4)
	assert_true(bool(world.player_state.mp_short), "a targeted skill waits for MP")
	assert_true(scene.hud.low_mp_visible(), "the scene displays the persistent low-MP cue")
	world.heal_fraction("mp", 1.0)
	_frames(1)
	assert_false(scene.hud.low_mp_visible(), "the cue disappears when the ready skill casts")
	_assert_nothing_missing(scene, "low MP cue")


func test_pause_holds_the_run() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 13, {"autoplay": true, "autopick": true})
	var w := scene.world
	_frames(30)
	var t := w.time
	scene.open_pause()
	assert_true(scene.paused)
	assert_eq(scene.world_root.process_mode, Node.PROCESS_MODE_DISABLED, "world animations frozen")
	_frames(30)
	assert_eq(w.time, t, "no ticks while paused")
	var pm := scene.window as PauseMenu
	assert_true(pm != null, "the PauseMenu opened")
	if pm == null:
		return
	# Esc in the menu resumes (the key path the player uses).
	var esc := InputEventKey.new()
	esc.pressed = true
	esc.keycode = KEY_ESCAPE
	esc.physical_keycode = KEY_ESCAPE
	assert_true(pm.handle_input(esc), "the menu took Esc")
	assert_false(scene.paused)
	_frames(30)
	assert_true(w.time > t, "running again")
	scene.open_pause()
	pm = scene.window as PauseMenu
	assert_true(pm != null and pm.activate(3), "Quit round asks for confirmation")
	assert_eq(finished.size(), 0, "the warning leaves the round paused")
	assert_true(scene.paused)
	assert_true(pm.activate(3), "confirm Quit round")
	assert_eq(finished.size(), 1, "confirmed quit without Flow emits run_finished")
	_assert_nothing_missing(scene, "pause")


func test_stage_clear_finishes_with_summary() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 4, {"autoplay": true, "autopick": true})
	var w := scene.world
	w.duration = 2.0
	w.bosses = BossDirector.new() # This fixture exercises the duration fallback and clear presentation.
	_frames(150)
	assert_eq(w.state, RunWorld.CLEARED, "cleared at the shortened duration")
	assert_true(scene.notice_fx.active_count() == 1, "the CLEAR field effect shows")
	assert_eq(finished.size(), 0, "the notice holds before the results")
	_frames(int(RunScene.CLEAR_HOLD / DT) + 5)
	assert_eq(finished.size(), 1, "run_finished emitted once")
	if finished.size() == 1:
		var s: Dictionary = finished[0]
		for k: String in ["stage", "map_id", "map_name", "street_name", "time", "duration", "cleared", "level", "job_id",
				"job_name", "kills", "damage_dealt", "skills", "seed"]:
			assert_true(s.has(k), "summary has %s" % k)
		assert_eq(bool(s.cleared), true)
		assert_eq(int(s.map_id), 104040000)
		assert_eq(String(s.map_name), lib.string_name("Map", 104040000))
		assert_eq(int(s.seed), 4)
		var sk: Array = s.skills
		assert_true(sk.size() >= 1 and String(sk[0].key) == "three_snails", "owned skills %s" % [sk])
	_assert_nothing_missing(scene, "clear")


func test_death_shows_tombstone_then_finishes() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 9, {})
	var w := scene.world
	_frames(2)
	var p := w.player.pos
	for dx: float in [-20.0, 0.0, 20.0, -40.0, 40.0]:
		var f := w.fhm.find_below(p.x + dx, p.y - 5.0)
		w.spawn_mob(int(w.kind_of_id[1110100]), Vector2(p.x + dx, w.fhm.y_at(f, p.x + dx)), f, 50.0, false)
	var ticks := 0
	while w.state != RunWorld.DEAD and ticks < 60 * 60:
		scene.advance_frame(DT)
		ticks += 1
	assert_eq(w.state, RunWorld.DEAD, "the Green Mushrooms killed the player")
	scene.advance_frame(DT)
	assert_eq(scene.avatar.stance, "dead", "dead stance")
	assert_true(scene.fx.active_count() >= 1, "tombstone playing")
	assert_eq(finished.size(), 0, "results wait for the tombstone")
	var fall := lib.find_anim(FxRenderer.TOMB_FALL)
	_frames(int((fall.total + RunScene.DEATH_HOLD) / DT) + 5)
	assert_eq(finished.size(), 1, "run_finished after the tombstone + hold")
	if finished.size() == 1:
		assert_eq(bool(finished[0].cleared), false)
	_assert_nothing_missing(scene, "death")


func test_climbing_animates_only_while_moving() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 21, {})
	var w := scene.world
	_frames(2)
	# The ladder/rope whose bottom is closest above a floor: stand under it and hold Up.
	var best := -1
	var feet := Vector2.ZERO
	for i in w.ladders.x.size():
		var f := w.fhm.find_below(w.ladders.x[i], w.ladders.y2[i] - 2.0)
		if f < 0:
			continue
		var fy := w.fhm.y_at(f, w.ladders.x[i])
		if fy - w.ladders.y2[i] < 40.0:
			best = i
			feet = Vector2(w.ladders.x[i], fy)
			break
	assert_true(best >= 0, "a ladder reachable from a floor")
	if best < 0:
		return
	w.player.place(feet, w.fhm)
	Input.action_press("move_up")
	_frames(20)
	Input.action_release("move_up")
	var climb := "ladder" if w.ladders.is_ladder[best] != 0 else "rope"
	assert_eq(w.player.state, PlayerMotion.ST_LADDER, "grabbed")
	assert_eq(scene.avatar.stance, climb, "climb stance")
	var t := scene.avatar.stance_time
	_frames(20)
	assert_eq(scene.avatar.stance_time, t, "the climb animation holds while not moving")
	_assert_nothing_missing(scene, "ladder")


func test_warp_fast_forwards_before_the_first_frame() -> void:
	if not require_cache():
		return
	# Fixed training seed1 reaches the requested warp; full-run regressions retain2026's valid early death.
	scene = _make("henesys", 1, {"autoplay": true, "autopick": true, "warp": 300.0, "shots_dir": "",
		"shot_every": 30.0, "job": 200}) # Keep the wand presentation test independent of the expanded job pool.
	var w := scene.world
	assert_true(w.time >= 300.0 - 1e-6, "the sim is at 5:00 before any frame (%.1f)" % w.time)
	assert_eq(w.state, RunWorld.PLAYING)
	assert_eq(int(w.player_state.job_id), 200, "the bot became a Magician on the way")
	assert_true(1372005 in scene.avatar.look.equips, "the presentation starts with the wand look")
	_frames(30)
	assert_eq(_mob_visible(scene), _drawn_mob_slots(w), "the renderers draw the warped swarm")
	assert_near(float(scene.perf_summary().get("warped_to")), w.time - 30.0 * DT, 1e-6, "perf_summary records the warp")
	_assert_hud_matches(scene)
	_assert_nothing_missing(scene, "warp")


## A warp whose round ends inside it (#143). `world_prepared` sets the round up before the warp: a clear after 2 s, or
## a crowd of unkillable Green Mushrooms on top of the Lv1 player.
func _prepare_clear(w: RunWorld) -> void:
	w.duration = 2.0
	w.bosses = BossDirector.new() # the duration fallback decides the clear


func _prepare_death(w: RunWorld) -> void:
	var p := w.player.pos
	for dx: float in [-20.0, 0.0, 20.0, -40.0, 40.0]:
		var f := w.fhm.find_below(p.x + dx, p.y - 5.0)
		w.spawn_mob(int(w.kind_of_id[1110100]), Vector2(p.x + dx, w.fhm.y_at(f, p.x + dx)), f, 1.0e9, false)


func _make_warped(prepare: Callable, options: Dictionary = {}) -> RunScene:
	var o := {"autoplay": true, "autopick": true, "warp": 60.0, "world_prepared": prepare}
	o.merge(options, true)
	return _make("henesys", 4, o)


func test_death_inside_the_warp_finishes_the_round() -> void:
	if not require_cache():
		return
	scene = _make_warped(_prepare_death)
	var w := scene.world
	assert_eq(w.state, RunWorld.DEAD, "the player died inside the warp")
	assert_true(w.time < 60.0 - 1e-6, "the warp stopped at the death (%.1f)" % w.time)
	var t := w.time
	assert_eq(finished.size(), 0, "results wait for the tombstone")
	scene.advance_frame(DT)
	assert_eq(scene.avatar.stance, "dead", "the dead stance is drawn")
	assert_true(scene.fx.active_count() >= 1, "the tombstone plays once the presentation exists")
	var fall := lib.find_anim(FxRenderer.TOMB_FALL)
	_frames(int((fall.total + RunScene.DEATH_HOLD) / DT) + 5)
	assert_eq(finished.size(), 1, "run_finished emitted exactly once")
	if finished.size() == 1:
		assert_eq(bool(finished[0].cleared), false)
	assert_eq(w.time, t, "no sim time was needed")
	_frames(30)
	assert_eq(finished.size(), 1, "still once")
	_assert_nothing_missing(scene, "warped death")


func test_clear_inside_the_warp_finishes_the_round() -> void:
	if not require_cache():
		return
	scene = _make_warped(_prepare_clear)
	var w := scene.world
	assert_eq(w.state, RunWorld.CLEARED, "the round cleared inside the warp")
	var t := w.time
	assert_eq(finished.size(), 0, "the clear notice holds before the results")
	scene.advance_frame(DT)
	assert_true(scene.notice_fx.active_count() == 1, "the CLEAR field effect shows")
	_frames(int(RunScene.CLEAR_HOLD / DT) + 5)
	assert_eq(finished.size(), 1, "run_finished emitted exactly once")
	if finished.size() == 1:
		assert_eq(bool(finished[0].cleared), true)
	assert_eq(w.time, t, "no sim time was needed")
	_assert_nothing_missing(scene, "warped clear")


func test_automated_death_and_clear_in_the_warp_reach_the_exit() -> void:
	if not require_cache():
		return
	for case: Array in [[_prepare_death, false], [_prepare_clear, true]]:
		var dir := ProjectSettings.globalize_path(test_dir("warp_end_%s" % ("clear" if case[1] else "death")))
		var exits: Array = []
		var sc := _make_warped(case[0], {"quit_after": 600.0, "shots_dir": dir})
		sc.exit_hook = func() -> void: exits.append(true)
		scene = sc
		for i in 60 * 30:
			if not exits.is_empty():
				break
			sc.advance_frame(DT)
		assert_eq(exits.size(), 1, "the automation exit was reached once (cleared=%s)" % case[1])
		assert_eq(finished.size(), 1)
		var f := FileAccess.open(dir.path_join("summary.json"), FileAccess.READ)
		assert_true(f != null, "summary.json is written")
		if f != null:
			var doc: Dictionary = JSON.parse_string(f.get_as_text())
			assert_eq(bool(doc.summary.cleared), case[1])
			assert_near(float(doc.warped_to), sc.world.time, 1e-6, "warped_to records where the warp stopped")
			f.close()
		sc.free()
		scene = null
		finished = []


func test_launcher_args() -> void:
	var args := RunLauncher.parse_args(PackedStringArray(["--run=henesys", "--seed=7", "--autoplay", "--autopick",
		"--speed=4", "--shots=C:\\tmp\\shots", "--shot-every=30", "--quit-after=900", "--perf", "ignored"]))
	assert_true(RunLauncher.has_run_args(args))
	assert_eq(RunLauncher.stage_from_args(args), "henesys")
	var o := RunLauncher.options_from_args(args)
	assert_eq(o.autoplay, true)
	assert_eq(o.autopick, true)
	assert_eq(int(o.speed), 4)
	assert_eq(String(o.shots_dir), "C:/tmp/shots")
	assert_near(float(o.shot_every), 30.0)
	assert_near(float(o.quit_after), 900.0)
	assert_eq(o.perf, true)
	assert_eq(int(args.seed), 7)
	var bare := RunLauncher.parse_args(PackedStringArray(["--run"]))
	assert_eq(RunLauncher.stage_from_args(bare), "henesys")
	assert_false(RunLauncher.has_run_args(RunLauncher.parse_args(PackedStringArray(["--map=1"]))))


func test_canonical_basic_swing_drives_afterimage_sparks_and_weapon_sound() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 83, {})
	var data := scene.data.duplicate(true)
	data.balance.player.skills = []
	data.balance.mob_motion.push_px = 0
	for keyframe: Dictionary in data.stages.stages.henesys.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	var setup := DataRepo.build_setup(data, "henesys", 83, Vector2(800, 600),
		func(path: String) -> Dictionary: return lib.img(path).root if lib.img(path) != null else {}, lib.mob_root)
	scene.world = RunWorld.new(setup)
	var w := scene.world
	w.god = true
	w.player.facing = 1
	var target := w.player.pos + Vector2(50, 0)
	w.mob_kinds[int(w.kind_of_id[100100])].move_speed = 0
	w.spawn_mob(int(w.kind_of_id[100100]), target, w.player.fh, 100, false)
	var before_sounds: int = scene.counters.sounds
	_frames(40)
	assert_true(String(scene.avatar.stance) in BasicAttack.ACTIONS, "the body plays the canonical swing/stab")
	assert_true(scene.fx.active_count() >= 2, "afterimage and hit sparks are pooled effects")
	assert_true(int(scene.counters.hit_fx) >= 1, "the swing hit emitted its spark")
	assert_true(int(scene.counters.sounds) > before_sounds, "swing and monster-hit audio played")
	_assert_nothing_missing(scene, "basic attack")


func test_same_map_portal_snaps_the_camera_without_sound_or_effects() -> void:
	if not require_cache():
		return
	scene = _make("ellinia", 17, {})
	var w := scene.world
	w.player.place(Vector2(-1355, 2021), w.fhm)
	scene.advance_frame(0.0)
	scene.cam.snap_to(w.player.pos)
	scene.cam.update_camera(DT)
	var sounds := int(scene.counters.sounds)
	var effects := scene.fx.active_count() + scene.fx_back.active_count()
	w.step(DT, MoveInput.make(false, false, true))
	scene.handle_events(w.drain_events())
	scene.advance_frame(0.0)
	scene.cam.update_camera(DT)
	assert_eq(scene.player_group.position, Vector2(-1338, 1592), "player drawn immediately at up01 minus 30 px")
	var view := scene.cam.view_rect()
	assert_near((scene.player_group.position.y - view.position.y) / view.size.y, 0.58, 1.0 / view.size.y,
		"camera immediately places arrival feet at the normal 58 percent anchor")
	assert_eq(int(scene.counters.sounds), sounds, "same-map warp is silent")
	assert_eq(scene.fx.active_count() + scene.fx_back.active_count(), effects, "no transition effect")
	_assert_nothing_missing(scene, "portal")


func test_potion_quickslot_shows_current_icons_without_stock_even_when_resources_are_full() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 10, {})
	var hp: Dictionary = scene.hud.quick_slot.displayed("hp")
	assert_eq(hp.item_id, 2000000)
	assert_false(hp.has("count"), "no stock number for the unlimited potion")
	assert_eq(hp.key_label, "Del", "the first bound key")
	assert_true(hp.icon != null, "canonical Red Potion icon is drawable")
	_frames(1)
	var mp: Dictionary = scene.hud.quick_slot.displayed("mp")
	assert_false(mp.has("count"), "MP also has no stock number")
	assert_eq(mp.item_id, 2000003)
	assert_eq(mp.key_label, "End", "E opens the Equip window (#108)")
	assert_true(mp.icon != null, "canonical Blue Potion icon is drawable")
	scene.world.drink_potion("hp")
	scene.advance_frame(0.0)
	assert_false(scene.hud.quick_slot.displayed("hp").has("count"), "a drink never creates stock")
	assert_eq(scene.hud.quick_slot.displayed("hp").sweep_step, 96, "the drink covers the HP icon immediately")
	_assert_nothing_missing(scene, "potions")
	var report := scene.perf_summary()
	assert_false(report.has("potions_collected"))
	assert_eq(report.get("potions_used", {}), {"hp": 1, "mp": 0})


func test_potion_sweeps_follow_live_timers_between_snapshot_changes_and_freeze_when_paused() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 10, {})
	var w := scene.world
	assert_true(w.drink_potion("hp"))
	assert_true(w.drink_potion("mp"))
	scene.advance_frame(0.0)
	assert_eq(scene.hud.quick_slot.displayed("hp").sweep_step, 96)
	assert_eq(scene.hud.quick_slot.displayed("mp").sweep_step, 96)
	_frames(18) # 0.3 s: no timer-second, resource, item or loadout change to refresh the snapshot.
	assert_eq(scene.hud.quick_slot.displayed("hp").sweep_step, 95)
	assert_eq(scene.hud.quick_slot.displayed("mp").sweep_step, 94, "MP clears twice as fast")
	scene.open_pause()
	var hp_left := float(w.potions.cooldown_left.hp)
	_frames(30)
	assert_eq(float(w.potions.cooldown_left.hp), hp_left)
	assert_eq(scene.hud.quick_slot.displayed("hp").sweep_step, 95, "pause holds the displayed wedge")
	scene.resume()
	w.apply_potion_schedule(10, true)
	scene.advance_frame(0.0)
	assert_eq(scene.hud.quick_slot.displayed("hp").item_id, 2000001, "tier upgrade replaces the icon")
	assert_eq(scene.hud.quick_slot.displayed("hp").sweep_step, 95, "tier upgrade preserves the wedge")
	w.potions.tick(20.0)
	scene.advance_frame(0.0)
	assert_eq(scene.hud.quick_slot.displayed("hp").sweep_step, 0, "reads the live timer even without another sim tick")
	assert_eq(scene.hud.quick_slot.displayed("mp").sweep_step, 0)
	_assert_nothing_missing(scene, "potion sweeps")


func test_potion_keyboard_press_consumes_once_even_with_multiple_ticks_per_frame() -> void:
	assert_true(InputMap.has_action("drink_hp"))
	assert_true(InputMap.has_action("drink_mp"))
	if not InputMap.has_action("drink_hp") or not InputMap.has_action("drink_mp") or not require_cache():
		return
	scene = _make("henesys", 10, {})
	for pair: Array in [["drink_hp", KEY_DELETE], ["drink_hp", KEY_Q], ["drink_mp", KEY_END]]:
		var event := InputEventKey.new()
		event.physical_keycode = pair[1]
		event.pressed = true
		assert_true(event.is_action_pressed(pair[0]), "%s binds %s" % [pair[0], OS.get_keycode_string(pair[1])])
		var kind := "hp" if pair[0] == "drink_hp" else "mp"
		scene.world.potions.tick(scene.world.potions.cooldown_total(kind))
		var before := int(scene.world.potions.used[kind])
		scene._unhandled_input(event)
		scene.advance_frame(DT * 4)
		assert_eq(scene.world.potions.used[kind], before + 1)


func test_drinking_hp_mp_and_upgraded_potions_plays_the_item_use_sound() -> void:
	if not require_cache():
		return
	var sfx := (Engine.get_main_loop() as SceneTree).root.get_node("Sfx") as AudioService
	var previous_library := sfx.library
	sfx.library = lib
	scene = _make("henesys", 35, {})
	var w := scene.world
	w.drain_events()
	for kind: String in ["hp", "mp"]:
		var sounds := int(scene.counters.sounds)
		assert_true(w.drink_potion(kind))
		scene.handle_events(w.drain_events())
		assert_eq(scene.counters.sounds, sounds + 1, "%s drink starts its sound" % kind)
	w.progression.level = 10
	w.apply_potion_schedule(10, true)
	assert_eq(w.player_state.potions.hp.item_id, 2000001)
	var sounds := int(scene.counters.sounds)
	w.potions.tick(w.potions.cooldown_total("hp"))
	assert_true(w.drink_potion("hp"))
	scene.handle_events(w.drain_events())
	assert_eq(scene.counters.sounds, sounds + 1, "Orange uses its own path even in the same presentation frame")
	_assert_nothing_missing(scene, "potion use sounds")
	sfx.library = previous_library


func test_missing_potion_sound_is_silent_and_reports_the_consumed_tier_path() -> void:
	if not require_cache():
		return
	var sfx := (Engine.get_main_loop() as SceneTree).root.get_node("Sfx") as AudioService
	var previous_library := sfx.library
	scene = _make("henesys", 35, {})
	# An empty cache tests misses without changing the player's installed assets.
	lib.open(TestCase.test_dir("missing_potion_sounds"))
	sfx.library = lib
	var w := scene.world
	w.drain_events()
	var sounds := int(scene.counters.sounds)
	assert_true(w.drink_potion("hp"))
	assert_true(w.drink_potion("mp"))
	w.progression.level = 10
	w.apply_potion_schedule(10, true)
	assert_eq(w.player_state.potions.hp.item_id, 2000001)
	w.potions.tick(w.potions.cooldown_total("hp"))
	assert_true(w.drink_potion("hp"))
	scene.handle_events(w.drain_events())
	assert_eq(scene.counters.sounds, sounds, "missing sounds start no voice")
	assert_eq(scene.perf_summary().missing, ["Sound.wz/Item.img/02000000/Use",
		"Sound.wz/Item.img/02000003/Use", "Sound.wz/Item.img/02000001/Use"])
	sfx.library = previous_library


func test_scheduled_potion_upgrades_change_the_quickslot_icon_and_show_the_v83_notice() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 11, {})
	var notices := {2000001: "Your Red Potions are now Orange Potions.", 2000002: "Your Orange Potions are now White Potions.",
		2000006: "Your Blue Potions are now Mana Elixirs."}
	for example: Array in [[10, "hp", 2000001], [20, "mp", 2000006], [25, "hp", 2000002]]:
		var before: Dictionary = scene.hud.quick_slot.displayed(example[1])
		scene.world.drain_events()
		scene.world.apply_potion_schedule(example[0], true)
		scene.handle_events(scene.world.drain_events())
		var lines: Array = scene.hud.messages().map(func(m: Dictionary) -> String: return String(m.text))
		assert_has(lines, notices[example[2]], "the level-up notice names the v83 items")
		scene.advance_frame(0.0)
		var after: Dictionary = scene.hud.quick_slot.displayed(example[1])
		assert_eq(after.item_id, example[2])
		assert_false(after.has("count"))
		assert_true(after.icon != null)
		assert_ne(after.icon.region, before.icon.region, "a new canonical icon is displayed")
	_assert_nothing_missing(scene, "potion tiers")


func test_levelup_window_adds_one_elixir_beside_its_available_job_cards() -> void:
	if not require_cache():
		return
	var height_one := 0.0
	for n in [1, 2]:
		scene = _make("henesys", 11, {})
		var w := scene.world
		w.change_job(200)
		w.progression.level = 20
		var ids: Array = ["energy_bolt_new", "magic_claw_new"].slice(0, n)
		var upgrades: Dictionary = scene.data.upgrades.duplicate(true)
		upgrades.cards = w.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.id in ids)
		w.upgrades = UpgradePool.from_data(upgrades)
		w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
		_frames(1 + ceili(RunScene.WINDOW_DELAY / DT) + 2)
		var lw := scene.window as LevelUpWindow
		assert_true(lw != null)
		if lw != null:
			assert_eq(lw.cards.size(), n + 1)
			assert_eq(lw.cards[n].id, "elixir")
			for i in n + 1:
				assert_true(lw.card_rect(i).has_area())
			assert_eq(lw.card_rect(n + 1), Rect2(), "no duplicate Elixir rows")
			assert_false(lw.choose(n + 1), "out-of-range choice cannot consume a card")
			if n == 1:
				height_one = lw.panel_size.y
			else:
				assert_true(lw.panel_size.y > height_one, "panel grows to hold the second card")
			assert_true(lw.choose(0))
			assert_eq(w.state, RunWorld.PLAYING)
		_assert_nothing_missing(scene, "%d job cards" % n)
		scene.free()
		scene = null

func test_mano_slow_uses_repeating_canonical_effect_and_shared_skill_stance() -> void:
	if not require_cache():
		return
	var sfx := (Engine.get_main_loop() as SceneTree).root.get_node("Sfx") as AudioService
	var previous_library := sfx.library
	sfx.library = lib
	scene = _make("henesys",22,{})
	var data := scene.data.duplicate(true)
	data.balance.player.skills = []
	data.balance.bosses.teleport_stall = 10000.0
	STAGE_FIXTURES.set_bosses(data.stages.stages.henesys, [{"mob_id":2220000,"time":0.0}])
	for keyframe: Dictionary in data.stages.stages.henesys.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	var setup := DataRepo.build_setup(data,"henesys",22,Vector2(800,600),func(p:String)->Dictionary:return lib.img(p).root if lib.img(p) != null else {},lib.mob_root)
	setup.mob_imgs[2220000] = setup.mob_imgs[2220000].duplicate(true)
	setup.mob_imgs[2220000].info.skill = {"0":{"skill":126.0,"level":7.0,"action":1.0,"effectAfter":0.0}}
	setup.mob_imgs[2220000].info.speed = -100.0
	scene.world = RunWorld.new(setup)
	var w := scene.world
	w.god = true
	_frames(901)
	var slot := int(w.bosses.records[0].slot)
	assert_eq(w.player.speed_stat,80)
	assert_eq(w.bosses.action_snapshot(w.swarm).actions[slot],"skill1","canonical boss skill stance")
	assert_true(scene.fx.active_count() >= 1,"slow affected animation plays")
	w.swarm.despawn(slot)
	_frames(60)
	scene.fx.advance(1.0)
	assert_true(scene.fx.active_count() >= 1,"repeat-marked slow art outlives its single 350ms cycle")
	_frames(840)
	assert_eq(scene.fx.active_count(),0,"the affected effect ends with canonical duration")
	_assert_nothing_missing(scene,"Mano slow")
	sfx.library = previous_library


func test_boss_reward_window_is_a_bonus_choice_before_the_clear_sequence() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 20, {})
	var w := scene.world
	w.god = true
	# This is a round-finale window test; an intermediate region boss must transfer instead of clearing.
	_single_map_bosses([{"time": 0.1, "mob_id": 2220000}], w.balance.bosses)
	_frames(6)
	var slot := int(w.bosses.records[0].slot)
	w.hit_mob(slot, {"damage_min": 1000000.0, "damage_max": 1000000.0, "magic": false,
		"crit": 0.0, "crit_mult": 1.5, "skill": "three_snails"}, -1)
	scene.handle_events(w.drain_events())
	_frames(1)
	var lw := scene.window as LevelUpWindow
	assert_true(lw != null, "reward choice is visible before clear")
	if lw != null:
		assert_eq(lw.get("bonus"), true, "bonus flag selects the reward header")
		assert_eq(w.state, RunWorld.CHOOSING_UPGRADE)
		assert_eq(w.player_state.level, 1, "bonus does not grant a level")
		assert_true(lw.choose(0))
	var t := w.time
	_frames(int(RunScene.WINDOW_DELAY / DT) + 2)
	lw = scene.window as LevelUpWindow
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the swept boss EXP must also be answered")
	assert_true(lw != null and not lw.bonus, "the normal gained-level window follows the boss reward")
	assert_eq(w.time, t, "combat stays frozen through settlement windows")
	scene._autopick = true
	if lw != null:
		assert_true(lw.choose(0)) # remaining queued settlement windows use the ordinary autopick service
	_frames(1)
	assert_eq(w.state, RunWorld.CLEARED, "clear begins only after boss and swept-EXP rewards are answered")
	assert_eq(w.time, t)
	_assert_nothing_missing(scene, "boss reward")


func test_timed_buff_row_and_rank_previews_use_canonical_guard_and_armor_data() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 12, {})
	var w := scene.world
	w.change_job(200)
	w.loadout.ranks.erase("energy_bolt")
	w.loadout.order.erase("energy_bolt")
	w.learn_skill("magic_guard")
	w.learn_skill("magic_armor")
	_frames(2)
	assert_eq((w.player_state.get("buffs", []) as Array).size(), 2)
	assert_true(scene.hud.buff_row.has_method("displayed"), "dedicated buff widget exposes its draw model")
	if scene.hud.buff_row.has_method("displayed"):
		for frame in [0, 90]:
			_frames(frame)
			var slots: Array = scene.hud.buff_row.call("displayed")
			assert_eq(slots.size(), 2)
			for i in slots.size():
				assert_eq(slots[i].skill_id, w.player_state.buffs[i].skill_id)
				assert_eq(slots[i].remaining_seconds, ceili(w.player_state.buffs[i].remaining))
				assert_true(slots[i].icon != null)
	assert_eq(w.upgrades.choice_card("magic_guard_rank", w).skill_changes,
		{"mpCon": {"before": 6, "after": 6}, "time": {"before": 111, "after": 132}, "x": {"before": 11, "after": 14}})
	assert_eq(w.upgrades.choice_card("magic_armor_rank", w).skill_changes,
		{"mpCon": {"before": 8, "after": 8}, "time": {"before": 54, "after": 68}, "pdd": {"before": 2, "after": 4}})
	_assert_nothing_missing(scene, "player buffs")

func test_stumpy_projectile_pool_is_drawn_and_heal_art_is_canonical() -> void:
	if not require_cache():
		return
	scene = _make("ellinia", 2406, {})
	var entry: Dictionary = scene.world.bosses.entries[0].duplicate(true)
	entry.time = 0.5
	entry.attacks = ["attack2"]
	scene.world.bosses = BossDirector.new([entry])
	scene.world.mob_skills = MobSkillRunner.new(scene.world.setup, {"enabled_ids": []})
	scene.world.mob_skills.resize(scene.world.swarm.capacity())
	scene.world.loadout.order.clear()
	scene.world.loadout.ranks.clear()
	scene.world.god = true
	var drawn := 0
	for tick in 900:
		scene.advance_frame(DT)
		drawn = maxi(drawn, scene.mob_shots.visible_count())
		if drawn > 0:
			break
	assert_true(drawn > 0, "monster pool is drawn by its own batched renderer")
	var effects := scene.fx.active_count()
	var slot := int(scene.world.bosses.records[0].slot)
	var pos := Vector2(scene.world.swarm.x[slot], scene.world.swarm.y[slot])
	scene.handle_events([{"type": "boss_skill", "mob": slot, "mob_id": 3220000, "skill_id": 114,
		"level": 15, "pos": pos, "facing": -1, "action": "skill1", "duration": 1.0,
		"effect": "Skill.wz/MobSkill.img/114/level/15/mob0", "player_effect": "", "targets": [], "summon_effect": "", "recipient_effect": ""},
		{"type": "mob_healed", "mob": slot, "mob_id": 3220000, "amount": 350, "pos": pos}])
	assert_eq(scene.fx.active_count(), effects + 1)
	assert_true(scene.hud.messages().any(func(m: Dictionary) -> bool: return m.text == "Stumpy recovered 350 HP"))
	_assert_nothing_missing(scene, "Stumpy presentation")



func _canonical_dyle_area_buff(skill_entry: String) -> Dictionary:
	scene = _make("ellinia", 2026, {})
	var data := scene.data.duplicate(true)
	data.balance.player.skills = []
	for keyframe: Dictionary in data.stages.stages.ellinia.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	data.stages.stages.ellinia.bursts = {}
	data.stages.stages.ellinia.elites = {}
	STAGE_FIXTURES.set_bosses(data.stages.stages.ellinia, [{"mob_id": 6220000, "time": 0.0}])
	var setup := DataRepo.build_setup(data, "ellinia", 2026, Vector2(800, 600),
		func(p: String) -> Dictionary: return lib.img(p).root if lib.img(p) != null else {}, lib.mob_root)
	setup.mob_imgs[6220000] = setup.mob_imgs[6220000].duplicate(true)
	setup.mob_imgs[6220000].info.skill = {skill_entry: setup.mob_imgs[6220000].info.skill[skill_entry]}
	scene.world = RunWorld.new(setup)
	var w := scene.world
	w.god = true
	w.step(DT, MoveInput.new())
	var source := int(w.bosses.records[0].slot)
	w.swarm.alpha[source] = 1.0
	w.spawn_mob(0, Vector2(w.swarm.x[source] + 20, w.swarm.y[source]), w.swarm.fh[source], 1.0, false)
	# Pass the canonical 30 s interval without spending a whole run moving the affected mobs apart.
	w.time = 40.1
	w.bosses.prepare_actions(w)
	w.drain_events()
	w.mob_skills.step(w)
	for event: Dictionary in w.drain_events():
		if event.type == "boss_skill":
			return event
	fail("canonical Dyle area buff should cast after its interval")
	return {}


func test_dyle_area_defense_without_optional_recipient_burst_keeps_art_complete() -> void:
	if not require_cache():
		return
	var event := _canonical_dyle_area_buff("2")
	if event.is_empty():
		return
	assert_eq(event.skill_id, 112)
	assert_eq(event.level, 4)
	assert_eq(event.targets.size(), 2, "caster and nearby ordinary mob receive the real area buff")
	for slot: int in event.targets:
		assert_near(scene.world.mob_skills.defense_bonus(slot, false, scene.world.time), 85.0, 0.001)
	assert_eq(event.get("recipient_effect", ""), "", "v83 112/L4 has no mob0 burst")
	assert_eq(event.effect, "Skill.wz/MobSkill.img/112/level/4/effect")
	var effects := scene.fx.active_count()
	scene.handle_events([event])
	assert_eq(scene.fx.active_count(), effects + 1, "the canonical caster effect still plays")
	_assert_nothing_missing(scene, "Dyle area defense without recipient art")


func test_dyle_area_magic_defense_plays_its_canonical_recipient_burst() -> void:
	if not require_cache():
		return
	var event := _canonical_dyle_area_buff("3")
	if event.is_empty():
		return
	assert_eq(event.skill_id, 113)
	assert_eq(event.level, 2)
	assert_eq(event.targets.size(), 2)
	for slot: int in event.targets:
		assert_near(scene.world.mob_skills.defense_bonus(slot, true, scene.world.time), 85.0, 0.001)
	assert_eq(event.get("recipient_effect", ""), "Skill.wz/MobSkill.img/113/level/2/mob0")
	var effects := scene.fx.active_count()
	scene.handle_events([event])
	assert_eq(scene.fx.active_count(), effects + 1, "v83 113/L2 plays its recipient burst")
	_assert_nothing_missing(scene, "Dyle area magic defense with recipient art")


func test_boss_skill_nonempty_missing_recipient_art_is_still_reported() -> void:
	if not require_cache():
		return
	var event := _canonical_dyle_area_buff("3")
	if event.is_empty():
		return
	# A nonempty event path is required art; only canonical absence may omit the optional burst.
	var missing := "Skill.wz/MobSkill.img/113/level/2/required_art_removed"
	event.recipient_effect = missing
	scene.handle_events([event])
	assert_eq(Array(interim_missing(lib.missing, scene.data, scene.stage_key)), [missing], "a broken required export remains visible to acceptance")


func test_dyle_immunity_icon_follows_live_boss_and_ends_with_status_and_death() -> void:
	if not require_cache():
		return
	scene = _make("ellinia", 25, {})
	var data := scene.data.duplicate(true)
	data.balance.player.skills = []
	data.balance.bosses.teleport_stall = 10000.0
	for keyframe: Dictionary in data.stages.stages.ellinia.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	data.stages.stages.ellinia.bursts = {}
	data.stages.stages.ellinia.elites = {}
	STAGE_FIXTURES.set_bosses(data.stages.stages.ellinia, [{"mob_id": 6220000, "time": 0.0}])
	var setup := DataRepo.build_setup(data, "ellinia", 25, Vector2(800,600), func(p:String)->Dictionary:return lib.img(p).root if lib.img(p) != null else {}, lib.mob_root)
	setup.mob_imgs[6220000] = setup.mob_imgs[6220000].duplicate(true)
	setup.mob_imgs[6220000].info.skill = {"0": {"skill":140,"level":8,"action":1,"effectAfter":0}}
	scene.world = RunWorld.new(setup)
	var w := scene.world
	w.god = true
	_frames(1)
	var slot := int(w.bosses.records[0].slot)
	w.hit_mob(slot, {"damage_min":10000.0,"damage_max":10000.0,"magic":false,"crit":0.0,"crit_mult":1.5,"skill":"three_snails"}, -1)
	_frames(1800)
	assert_true(scene.has_method("mob_status_effects"), "mob status art exposes its detached draw model")
	if not scene.has_method("mob_status_effects"):
		return
	var displayed: Array = scene.call("mob_status_effects")
	assert_eq(displayed.size(), 1)
	if displayed.size() == 1:
		assert_eq(displayed[0].visual, "Skill.wz/MobSkill.img/140/level/8/mob")
		assert_eq(displayed[0].mob, slot)
		assert_true(displayed[0].visible)
	var pos := Vector2(w.swarm.x[slot] + 100, w.swarm.y[slot])
	var moved := w.relocate_mob(slot, pos, w.swarm.fh[slot])
	_frames(1)
	displayed = scene.call("mob_status_effects")
	assert_eq(displayed[0].mob, moved)
	assert_near((displayed[0].pos as Vector2).x, w.swarm.x[moved], 0.01)
	_frames(300)
	assert_eq((scene.call("mob_status_effects") as Array).size(), 0)
	_frames(1500)
	assert_eq((scene.call("mob_status_effects") as Array).size(), 1, "second canonical interval recasts")
	w.hit_mob(moved, {"damage_min":100000.0,"damage_max":100000.0,"magic":true,"crit":0.0,"crit_mult":1.5,"skill":"energy_bolt"}, -1)
	_frames(1)
	assert_eq((scene.call("mob_status_effects") as Array).size(), 0, "death hides a still-timed icon")
	_assert_nothing_missing(scene, "Dyle immunity")


func test_tree_boss_bars_use_original_icons_and_split_removes_only_the_dead_bar() -> void:
	if not require_cache():
		return
	scene = _make("ellinia", 2521, {})
	var w := scene.world
	w.god = true
	w.loadout.order.clear()
	w.loadout.ranks.clear()
	# Keep both bosses alive on one map so King Slime's split must leave Dyle's independent bar intact.
	_single_map_bosses([{"mob_id":9300003,"time":0.0,"hp_mult":1.5}, {"mob_id":6220000,"time":0.0,"hp_mult":1.5}])
	_frames(1)
	var rows := scene.hud.boss_bar.displayed()
	assert_eq(rows.size(), 2)
	if rows.size() != 2:
		return
	assert_eq(rows[0].icon_path, "UI.wz/UIWindow.img/MobGage/Mob/9300003")
	assert_eq(rows[0].color_path, "UI.wz/UIWindow.img/MobGage/Gage/1/0")
	assert_eq(rows[0].background_path, "UI.wz/UIWindow.img/MobGage/Gage/5/1")
	assert_eq(rows[1].icon_path, "UI.wz/UIWindow.img/MobGage/Mob/6220000")
	assert_true(rows[0].icon != null and rows[1].icon != null)
	var slot := int(w.bosses.records[0].slot)
	w.hit_mob(slot, {"damage_min":100000.0,"damage_max":100000.0,"magic":true,"crit":0.0,"crit_mult":1.5,"skill":"energy_bolt"}, -1)
	_frames(1)
	assert_eq(scene.hud.boss_bar.displayed().size(), 1)
	assert_eq(w.mob_skills.summoned_alive(w, 0), 11)
	_assert_nothing_missing(scene, "Tree bosses and revive")


func test_recovery_cast_effect_buff_row_and_rank_preview_use_original_data() -> void:
	if not require_cache():
		return
	scene = _make("henesys", 13, {})
	var w := scene.world
	w.learn_skill("recovery")
	w.take_hit(40, false, "", w.player.pos + Vector2(10, 0))
	scene.handle_events(w.drain_events())
	var effects := scene.fx.active_count()
	var before_mp := int(w.player_state.mp)
	_frames(1)
	assert_eq(w.player_state.mp, before_mp - 5, "Recovery pays canonical level-one MP cost")
	assert_eq(w.player_state.buffs.size(), 1)
	var slots := scene.hud.buff_row.displayed()
	assert_eq(slots.size(), 1)
	assert_eq(slots[0].skill_id, 1001)
	assert_eq(slots[0].remaining_seconds, 30)
	assert_true(slots[0].icon != null)
	assert_true(scene.fx.active_count() > effects, "canonical Recovery cast animation is presented")
	var card := w.upgrades.choice_card("recovery_rank", w)
	assert_eq(card.skill_changes, {"mpCon": {"before": 5, "after": 10}, "time": {"before": 30, "after": 30},
		"x": {"before": 4, "after": 8}, "cooltime": {"before": 120, "after": 120}})
	assert_has(LevelUpWindow.change_lines(card), "HP / pulse: 4 → 8")
	_assert_nothing_missing(scene, "Recovery")


func test_setup_preloads_clear_art_and_sound_before_the_victory_event() -> void:
	if not require_cache():
		return
	assert_false((lib.get("_anims") as Dictionary).has(RunScene.FX_CLEAR), "fresh in-memory library")
	assert_false((lib.get("_sounds") as Dictionary).has(RunScene.SND_CLEAR))
	scene = _make("henesys", 7, {})
	assert_eq(scene.error, "")
	assert_true((lib.get("_anims") as Dictionary).has(RunScene.FX_CLEAR), "setup cached the victory animation")
	assert_true((lib.get("_sounds") as Dictionary).has(RunScene.SND_CLEAR), "setup cached the victory sound")
	var pages := lib.pages_loaded()
	var sounds := (lib.get("_sounds") as Dictionary).size()
	assert_true(lib.find_anim(RunScene.FX_CLEAR) != null, "the original clear art exists")
	assert_true(lib.sound(RunScene.SND_CLEAR) != null, "the original clear sound exists")
	scene._on_stage_cleared()
	assert_eq(lib.pages_loaded(), pages, "the clear event decodes no new atlas page")
	assert_eq((lib.get("_sounds") as Dictionary).size(), sounds, "the clear event decodes no new sound")
	_assert_nothing_missing(scene, "clear warmup")


func test_setup_preloads_boss_and_job_change_art_and_sounds() -> void:
	if not require_cache():
		return
	for stage: String in ["henesys", "ellinia"]:
		scene = _make(stage, 7, {"autoplay": true, "autopick": true})
		assert_eq(scene.error, "", "scene started")
		var pages := lib.pages_loaded()
		var sounds := (lib.get("_sounds") as Dictionary).size()
		var paths: Array[String] = ["Effect.wz/BasicEff.img/Summoned", RunScene.FX_JOB_CHANGED]
		if stage == "henesys":
			paths.append_array(["Skill.wz/MobSkill.img/112/level/1/effect", "Skill.wz/MobSkill.img/126/level/7/affected",
				"Effect.wz/Summon.img/1", "Mob.wz/6130101.img/attack1/info/effect"])
		else:
			paths.append_array(["Mob.wz/3220000.img/attack2/info/ball", "Skill.wz/MobSkill.img/140/level/8/mob",
				"Skill.wz/MobSkill.img/114/level/15/mob0"])
		for path in paths:
			assert_true(lib.find_anim(path) != null, "%s: %s exists" % [stage, path])
		for record: Dictionary in scene.world.bosses.records:
			lib.find_anim(lib.mob_anim_img_path(int(record.mob_id)) + "/skill1")
			lib.sound(RunScene.SND_MOB % [int(record.mob_id), "Damage"])
		lib.sound(RunScene.SND_JOB_CHANGED)
		assert_eq(lib.pages_loaded(), pages, "%s: no atlas page is first decoded at job change or boss time" % stage)
		assert_eq((lib.get("_sounds") as Dictionary).size(), sounds, "%s: their sounds are already loaded" % stage)
		assert_eq(interim_missing(lib.missing, scene.data).size(), 0, "%s: warming records nothing missing %s" % [stage, lib.missing])
		scene.free()
		scene = null
