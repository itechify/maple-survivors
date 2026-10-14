extends TestCase
## RunScene (game/scripts/run/run_scene.gd) against the real asset cache (SKIP without it): the scene is added to the
## test's SceneTree with a private AssetLibrary and advanced by calling advance_frame(1/60) directly (one sim tick per
## call). Checks that sim events become visuals (damage numbers, hit effects, sounds, EXP messages, level-up/job
## effects, the wand look, tombstone, stage clear), that the renderers draw exactly the sim's live state, that the HUD
## shows player_state, that D2's windows (LevelUpWindow, JobAdvanceWindow, PauseMenu) open over the run and their
## answers (keys through handle_input, signals) drive the sim, that autopick resolves choices without windows, and that
## nothing is missing from the cache. The launcher's argument parsing needs no cache.

const DT := 1.0 / 60.0

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
	assert_eq(lib.missing.size(), 0, "%s: library misses %s" % [label, lib.missing])
	assert_eq(s.map.missing.size(), 0, "%s: map misses %s" % [label, s.map.missing])
	assert_eq(s.avatar.missing.size(), 0, "%s: avatar misses %s" % [label, s.avatar.missing])
	for mr in s.mob_renderers:
		assert_eq(mr.missing.size(), 0, "%s: mob renderer misses %s" % [label, mr.missing])
	assert_eq(s.setup_missing.size(), 0, "%s: setup misses %s" % [label, s.setup_missing])


func _assert_hud_matches(s: RunScene) -> void:
	assert_eq(s.hud.status.player_state, s.world.player_state, "status widget fed by the run scene")
	assert_eq(s.hud.counters.run_info.kills, s.world.kills, "counter widget fed by the run scene")
	assert_eq(s.hud.skills.run_info.skills, s.run_info().skills, "skill widget fed by the run scene")
	assert_eq(s.hud.potion_slot.get_parent(), s.hud, "quickslot has its own widget")
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
	scene = _make("henesys_hg1", 7, {"autoplay": true, "autopick": true})
	assert_eq(scene.error, "", "scene started")
	assert_true(1302000 in scene.avatar.look.equips, "the first Beginner frame includes the Sword")
	var w := scene.world
	assert_true(w != null, "world built")
	assert_eq(w.mob_kinds.size(), DataRepo.stage_mob_ids(scene.data, "henesys_hg1").size(), "every pool mob has an img")
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
	scene = _make("henesys_hg1", 3, {})
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
	scene.handle_events([{"type": "job_changed", "job_id": 200, "name": "Magician"}])
	assert_true(1372005 in scene.avatar.look.equips, "the Magician holds the Wooden Wand")
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
	scene = _make("henesys_hg1", 2101, {})
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
	scene = _make("henesys_hg1", 2102, {})
	scene.world.bosses = BossDirector.new([{"mob_id": 2220000, "time": 0.5, "hp_mult": 2.0}])
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
	scene = _make("henesys_hg1", 2103, {})
	scene.world.bosses = BossDirector.new([
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
	scene = _make("henesys_hg1", 2303, {})
	var pos := scene.world.player.pos + Vector2(180, 0)
	var effect := "Mob.wz/6130101.img/attack1/info/effect"
	var sounds := int(scene.counters.sounds)
	var effects := scene.fx.active_count()
	scene.handle_events([{"type": "boss_attack", "phase": "start", "boss_index": 1,
		"sound": "Sound.wz/Mob.img/6130101/Attack1"},
		{"type": "boss_attack", "phase": "effect", "boss_index": 1,
		"effect": effect, "pos": pos, "facing": -1}])
	assert_eq(scene.counters.sounds, sounds + 1)
	assert_eq(scene.fx.active_count(), effects + 1)
	_assert_nothing_missing(scene, "mushroom slam")


func test_cast_plays_the_action_stance_while_standing() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 5, {})
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
	scene = _make("henesys_hg1", 616, {})
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
	scene = _make("henesys_hg1", 11, {})
	var w := scene.world
	_frames(2)
	w.pickups.spawn(w.player.pos, 20, 4000019)
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
		var second := String(w.pending_cards[1].id)
		var key := InputEventKey.new()
		key.pressed = true
		key.keycode = KEY_2
		key.physical_keycode = KEY_2
		assert_true(lw.handle_input(key), "the window took the key")
		assert_true(scene.window == null, "closed after the choice")
		assert_eq(int(w.loadout.card_ranks.get(second, 0)), 1, "the second card (%s) was applied" % second)
	assert_eq(w.state, RunWorld.PLAYING, "playing again")
	var t_after := w.time
	_frames(2)
	assert_true(w.time > t_after, "ticking again")
	_assert_nothing_missing(scene, "level up")


func test_job_window_reaches_magician() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 12, {"window_autopick": 0.05})
	var w := scene.world
	_frames(2)
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(8), 4000019)
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
	scene = _make("henesys_hg1", 14, {})
	var w := scene.world
	_frames(2)
	# Exactly enough EXP for level 8 (the Magician advancement level).
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(8), 4000019)
	var guard := 0
	while scene.window == null and guard < 60 * 10:
		scene.advance_frame(DT)
		guard += 1
		var lw0 := scene.window as LevelUpWindow
		if lw0 != null:
			lw0.choose(0)
	var jw := scene.window as JobAdvanceWindow
	# Levels 2-7 were answered above; the job window comes first at level 8.
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
	assert_eq(jw.level, 8, "at level 8")
	assert_eq(w.state, RunWorld.CHOOSING_JOB, "the sim waits for the job choice")
	# "Not now." keeps the Beginner and continues to the level-8 upgrade window.
	assert_true(jw.any_available(), "Magician is available")
	jw.decline()
	assert_eq(int(w.player_state.job_id), 0, "still a Beginner")
	_frames(int(RunScene.WINDOW_DELAY / DT) + 2)
	assert_true(scene.window is LevelUpWindow, "the level-8 upgrade window follows the decline")
	_assert_nothing_missing(scene, "job decline")


func test_job_change_effect_plays_before_the_next_window() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 15, {})
	var w := scene.world
	_frames(2)
	w.pickups.spawn(w.player.pos, w.progression.curve.total_to(8), 4000019)
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
	# The player takes Magician: the sim already waits in the level-8 card choice, but the window must not cover the
	# JobChanged pillar while it plays.
	jw.job_chosen.emit(200)
	assert_eq(int(w.player_state.job_id), 200, "Magician taken")
	assert_eq(w.state, RunWorld.CHOOSING_UPGRADE, "the level-8 card choice is pending in the sim")
	var held := 0
	while scene.window == null and held < 600:
		scene.advance_frame(DT)
		held += 1
	assert_true(scene.window is LevelUpWindow, "the level-8 upgrade window follows")
	assert_between(held * DT, total - 2.0 * DT, total + 3.0 * DT,
		"the window waited for the %.2f s JobChanged effect (%d frames)" % [total, held])
	_assert_nothing_missing(scene, "job effect")


func test_low_mp_cue_tracks_the_waiting_skill_and_clears_after_restoration() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 9, {})
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
	scene = _make("henesys_hg1", 13, {"autoplay": true, "autopick": true})
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
	assert_true(pm != null and pm.activate(1), "Quit to stage select")
	assert_eq(finished.size(), 1, "quitting ends the run (without Flow: run_finished)")
	_assert_nothing_missing(scene, "pause")


func test_stage_clear_finishes_with_summary() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 4, {"autoplay": true, "autopick": true})
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
	scene = _make("henesys_hg1", 9, {})
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
	scene = _make("henesys_hg1", 21, {})
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
	scene = _make("henesys_hg1", 2026, {"autoplay": true, "autopick": true, "warp": 200.0, "shots_dir": "",
		"shot_every": 30.0})
	var w := scene.world
	assert_true(w.time >= 200.0 - 1e-6, "the sim is at 3:20 before any frame (%.1f)" % w.time)
	assert_eq(w.state, RunWorld.PLAYING)
	assert_eq(int(w.player_state.job_id), 200, "the bot became a Magician on the way")
	assert_true(1372005 in scene.avatar.look.equips, "the presentation starts with the wand look")
	_frames(30)
	assert_eq(_mob_visible(scene), _drawn_mob_slots(w), "the renderers draw the warped swarm")
	assert_near(float(scene.perf_summary().get("warped_to")), w.time - 30.0 * DT, 1e-6, "perf_summary records the warp")
	_assert_hud_matches(scene)
	_assert_nothing_missing(scene, "warp")


func test_launcher_args() -> void:
	var args := RunLauncher.parse_args(PackedStringArray(["--run=henesys_hg1", "--seed=7", "--autoplay", "--autopick",
		"--speed=4", "--shots=C:\\tmp\\shots", "--shot-every=30", "--quit-after=900", "--perf", "ignored"]))
	assert_true(RunLauncher.has_run_args(args))
	assert_eq(RunLauncher.stage_from_args(args), "henesys_hg1")
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
	assert_eq(RunLauncher.stage_from_args(bare), "henesys_hg1")
	assert_false(RunLauncher.has_run_args(RunLauncher.parse_args(PackedStringArray(["--map=1"]))))


func test_canonical_basic_swing_drives_afterimage_sparks_and_weapon_sound() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 83, {})
	var data := scene.data.duplicate(true)
	data.balance.player.skills = []
	data.balance.mob_motion.push_px = 0
	for keyframe: Dictionary in data.stages.stages.henesys_hg1.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	var setup := DataRepo.build_setup(data, "henesys_hg1", 83, Vector2(800, 600),
		func(path: String) -> Dictionary: return lib.img(path).root, lib.mob_root)
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
	scene = _make("tree_that_grew_1", 17, {})
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


func test_potion_quickslot_shows_current_icons_and_counts_even_when_resources_are_full() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 10, {})
	var hp: Dictionary = scene.hud.potion_slot.displayed("hp")
	assert_eq(hp.item_id, 2000000)
	assert_eq(hp.count, 5)
	assert_eq(hp.key_label, "Del / Q")
	assert_true(hp.icon != null, "canonical Red Potion icon is drawable")
	scene.world.spawn_potion("mp", scene.world.player.pos - Vector2(0, 25), 2)
	_frames(1)
	var mp: Dictionary = scene.hud.potion_slot.displayed("mp")
	assert_eq(mp.count, 2)
	assert_eq(mp.item_id, 2000003)
	assert_eq(mp.key_label, "End / E")
	assert_true(mp.icon != null, "canonical Blue Potion icon is drawable")
	scene.world.drink_potion("hp")
	scene.advance_frame(0.0)
	assert_eq(scene.hud.potion_slot.displayed("hp").count, 4, "stock-only changes redraw the quickslot")
	_assert_nothing_missing(scene, "potions")
	var report := scene.perf_summary()
	assert_eq(report.get("potions_collected", {}), {"hp": 0, "mp": 2})
	assert_eq(report.get("potions_used", {}), {"hp": 1, "mp": 0})


func test_potion_keyboard_press_consumes_once_even_with_multiple_ticks_per_frame() -> void:
	assert_true(InputMap.has_action("drink_hp"))
	assert_true(InputMap.has_action("drink_mp"))
	if not InputMap.has_action("drink_hp") or not InputMap.has_action("drink_mp") or not require_cache():
		return
	scene = _make("henesys_hg1", 10, {})
	for pair: Array in [["drink_hp", KEY_DELETE], ["drink_hp", KEY_Q], ["drink_mp", KEY_END], ["drink_mp", KEY_E]]:
		var event := InputEventKey.new()
		event.physical_keycode = pair[1]
		event.pressed = true
		assert_true(event.is_action_pressed(pair[0]), "%s binds %s" % [pair[0], OS.get_keycode_string(pair[1])])
		if pair[0] == "drink_mp":
			scene.world.spawn_potion("mp", scene.world.player.pos - Vector2(0, 25), 2)
			_frames(1)
		var before: int = scene.world.player_state.potions["hp" if pair[0] == "drink_hp" else "mp"].count
		scene._unhandled_input(event)
		scene.advance_frame(DT * 4)
		assert_eq(scene.world.player_state.potions["hp" if pair[0] == "drink_hp" else "mp"].count, before - 1)


func test_potion_tier_cards_change_the_quickslot_icon_without_changing_stock() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 11, {})
	scene.world.progression.level = 25
	for example: Array in [["orange_potion", "hp", 2000001], ["white_potion", "hp", 2000002],
			["mana_elixir", "mp", 2000006]]:
		var before: Dictionary = scene.hud.potion_slot.displayed(example[1])
		scene.world.upgrades.apply(example[0], scene.world)
		scene.advance_frame(0.0)
		var after: Dictionary = scene.hud.potion_slot.displayed(example[1])
		assert_eq(after.item_id, example[2])
		assert_eq(after.count, before.count)
		assert_true(after.icon != null)
		assert_ne(after.icon.region, before.icon.region, "a new canonical icon is displayed")
	_assert_nothing_missing(scene, "potion tiers")


func test_levelup_window_has_only_its_one_or_two_available_potion_cards() -> void:
	if not require_cache():
		return
	var height_one := 0.0
	for n in [1, 2]:
		scene = _make("henesys_hg1", 11, {})
		var w := scene.world
		w.change_job(200)
		w.progression.level = 20
		var ids: Array = ["orange_potion", "mana_elixir"].slice(0, n)
		w.upgrades = UpgradePool.from_data({"cards": w.upgrades.cards.filter(func(c: Dictionary) -> bool: return c.id in ids)})
		w.pickups.spawn(w.player.pos - Vector2(0, 25), w.progression.exp_to_next(), 4000019)
		_frames(1 + ceili(RunScene.WINDOW_DELAY / DT) + 2)
		var lw := scene.window as LevelUpWindow
		assert_true(lw != null)
		if lw != null:
			assert_eq(lw.cards.size(), n)
			for i in n:
				assert_true(lw.card_rect(i).has_area())
			assert_eq(lw.card_rect(n), Rect2(), "no empty substitute row")
			assert_false(lw.choose(n), "out-of-range choice cannot consume a card")
			if n == 1:
				height_one = lw.panel_size.y
			else:
				assert_true(lw.panel_size.y > height_one, "panel grows to hold the second card")
			assert_true(lw.choose(0))
			assert_eq(w.state, RunWorld.PLAYING)
		_assert_nothing_missing(scene, "%d potion cards" % n)
		scene.free()
		scene = null

func test_mano_slow_uses_repeating_canonical_effect_and_shared_skill_stance() -> void:
	if not require_cache():
		return
	var sfx := (Engine.get_main_loop() as SceneTree).root.get_node("Sfx") as AudioService
	var previous_library := sfx.library
	sfx.library = lib
	scene = _make("henesys_hg1",22,{})
	var data := scene.data.duplicate(true)
	data.balance.player.skills = []
	data.balance.bosses.teleport_stall = 10000.0
	data.stages.stages.henesys_hg1.bosses = [{"mob_id":2220000,"time":0.0}]
	for keyframe: Dictionary in data.stages.stages.henesys_hg1.keyframes:
		keyframe.rate = 0
		keyframe.max_alive = 0
	var setup := DataRepo.build_setup(data,"henesys_hg1",22,Vector2(800,600),func(p:String)->Dictionary:return lib.img(p).root,lib.mob_root)
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
	scene = _make("henesys_hg1", 20, {})
	var w := scene.world
	w.god = true
	w.bosses = BossDirector.new([{"time": 0.1, "mob_id": 2220000}], w.balance.bosses)
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
	_frames(1)
	assert_eq(w.state, RunWorld.CLEARED, "clear begins only after the reward is answered")
	_assert_nothing_missing(scene, "boss reward")


func test_timed_buff_row_and_rank_previews_use_canonical_guard_and_armor_data() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 12, {})
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
		{"mpCon": {"before": 6, "after": 6}, "time": {"before": 111, "after": 195}, "x": {"before": 11, "after": 23}})
	assert_eq(w.upgrades.choice_card("magic_armor_rank", w).skill_changes,
		{"mpCon": {"before": 8, "after": 8}, "time": {"before": 54, "after": 110}, "pdd": {"before": 2, "after": 10}})
	_assert_nothing_missing(scene, "player buffs")


func test_recovery_cast_effect_buff_row_and_rank_preview_use_original_data() -> void:
	if not require_cache():
		return
	scene = _make("henesys_hg1", 13, {})
	var w := scene.world
	w.learn_skill("recovery")
	w.take_hit(40, false, "", w.player.pos + Vector2(10, 0))
	scene.handle_events(w.drain_events())
	var effects := scene.fx.active_count()
	_frames(1)
	assert_eq(w.player_state.mp, 0)
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
