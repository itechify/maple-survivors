class_name RunScene
extends Node2D
## One playable survivor run (docs/ARCHITECTURE.md 4.1, 4.3, 4.4.1-4.4.3, 4.5): builds a RunWorld from the asset cache
## and res://data, advances it in fixed 1/60 s ticks, and draws it with the presentation layer.
##
##   var run: RunScene = preload("res://scenes/run/run_scene.tscn").instantiate()
##   run.configure("henesys_hg1", 7, {"autoplay": true, "autopick": true})
##   add_child(run)
##
## Options (configure()): autoplay (BotInput drives the player), autopick (BotInput's choices are taken at once and
## no window opens: the first available job and BotInput.pick_card_for's card; automated runs and benchmarks), speed
## (sim ticks per 60 Hz frame; implemented as Engine.time_scale so effects keep pace), shots_dir + shot_every (PNG
## every N s of run time, t<seconds>.png, plus final.png), quit_after (run seconds; writes shots_dir/summary.json and
## quits the app), perf (perf overlay on at start with autoplay), name (character name), use_flow (default true;
## false = only emit run_finished, e.g. in tests), window_autopick (s: an open level-up / job window answers itself
## with BotInput's choice after that long; demos and evidence runs), warp (run seconds: before the first frame the sim is
## fast-forwarded to that time by BotInput with autopick, nothing drawn; perf runs of the late game in real time).
##
## Loop: advance_frame(delta) (called from _process; tests call it directly) accumulates delta, runs at most
## MAX_TICKS_PER_FRAME x speed ticks of RunWorld.step() with the keyboard or BotInput, drains and maps the events after
## every tick (slot indices are only valid right after the step that emitted them), then updates the renderers from
## the sim state. The tick loop stops while the world is not PLAYING (level-up / job windows, death, clear) and while
## the pause menu is open.
##
## Windows (LevelUpWindow, JobAdvanceWindow, PauseMenu: game/scripts/ui/windows/) are hosted in a CanvasLayer (layer
## 10); while one is open the fixed-tick loop holds (the sim is also held by its CHOOSING_* state). The level-up window
## opens WINDOW_DELAY s after the LevelUp effect starts, and after a job advancement only once the JobChanged effect
## has played; several queued levels open their windows one after another. The windows' art is loaded during setup
## (_warm_ui) so the first window does not stall a frame.
## The run ends after the tombstone + DEATH_HOLD s, or CLEAR_HOLD s after the stage-clear notice:
## then run_finished(summary) is emitted and, when the "Flow" autoload exists, Flow.finish_run(summary) is called (with
## quit_after set the app writes summary.json and quits instead).

## Emitted when the run is over (always, before Flow.finish_run). See build_summary() for the fields.
signal run_finished(summary: Dictionary)

const DT := 1.0 / 60.0
## docs/ARCHITECTURE.md section 6: at most 4 catch-up ticks per frame (times the speed option).
const MAX_TICKS_PER_FRAME := 4
const SCENE_PATH := "res://scenes/run/run_scene.tscn"

const FX_LEVEL_UP := "Effect.wz/BasicEff.img/LevelUp"
const FX_JOB_CHANGED := "Effect.wz/BasicEff.img/JobChanged"
## The party-quest "CLEAR" field effect (anchored at the screen centre: its last frame's origin is its middle).
const FX_CLEAR := "Map.wz/Effect.img/quest/party/clear"
const SND_JUMP := "Sound.wz/Game.img/Jump"
const SND_DROP := "Sound.wz/Game.img/DropItem"
const SND_PICKUP := "Sound.wz/Game.img/PickUpItem"
const SND_LEVEL_UP := "Sound.wz/Game.img/LevelUp"
const SND_JOB_CHANGED := "Sound.wz/Game.img/JobChanged"
const SND_TOMB := "Sound.wz/Game.img/Tombstone"
const SND_CLEAR := "Sound.wz/Field.img/Party1/Clear"
const SND_MOB := "Sound.wz/Mob.img/%07d/%s"
const SND_SKILL_USE := "Sound.wz/Skill.img/%07d/Use"
## Cast stance used when the body lacks the skill's action (docs/GAME_DESIGN.md section 7).
const DEFAULT_ACTION := "swingO1"
## Weapon held per job branch (job id / 100): the Magician's Wooden Wand 1372005 (tier A: the item; GAME_DESIGN 11).
## Beginners hold nothing (GAME_DESIGN section 1, AvatarRenderer.DEFAULT_LOOK).
const DEFAULT_NAME := "MapleHero"

## tier C (ours): seconds of the LevelUp effect before the upgrade window opens (about the pillar's peak; the whole
## effect is ~2.1 s).
const WINDOW_DELAY := 1.2
## tier C (ours): seconds the JobChanged effect plays before the next window opens when its animation is missing
## (otherwise the animation's own length, ~1.3 s, is used).
const JOB_WINDOW_DELAY := 1.3
## Seconds a closed window is kept for its fade-out before it is freed (MapleWindow closes in 0.12 s).
const WINDOW_FREE_DELAY := 0.5
## tier C (ours): seconds after the tombstone has landed before the run ends.
const DEATH_HOLD := 2.0
## tier C (ours): seconds the stage-clear notice shows before the run ends.
const CLEAR_HOLD := 3.5
## tier C (ours): the face shows "hit" this long after a hit.
const HIT_FACE_TIME := 1.0
## tier C (ours): invincibility blink, alpha of the dim phase and the period (s) of one bright + dim cycle.
const BLINK_ALPHA := 0.4
const BLINK_PERIOD := 0.16
## tier C (ours): map/street name notice at run start: seconds shown (the last FADE of them fading).
const TITLE_TIME := 3.5
const TITLE_FADE := 1.0
## Damage-number stacking key of the player (mob slots use their slot index).
const PLAYER_KEY := 1 << 20
## Perf overlay window (s) and refresh interval (s); frames ignored at the start of the perf summary.
const PERF_WINDOW := 2.0
const PERF_REFRESH := 0.25
const PERF_WARMUP_FRAMES := 60

## Configuration (configure()).
var stage_key := "henesys_hg1"
var run_seed := -1
var options: Dictionary = {}
## Asset source for everything this scene draws; defaults to the "Assets" autoload.
var library: AssetLibrary

## The simulation and the data it was built from.
var world: RunWorld
var data: Dictionary = {}
var map_id := 0
## Cache imgs the setup could not find (DataRepo.build_setup).
var setup_missing := PackedStringArray()
## Why the run could not start ("" when it did).
var error := ""

## Presentation nodes.
var world_root: Node2D
var map: MapRenderer
var cam: CameraRig
var avatar: AvatarRenderer
## Holds the avatar (positioned at the player's feet); its self_modulate blinks while invincible.
var player_group: CanvasGroup
## The character name tag (NameTags style, like the elite tags).
var player_tag: NameTags
var mob_renderers: Array[MobRenderer] = []
## Foothold layer drawn by mob_renderers[i] (-1 = every slot).
var mob_layers := PackedInt32Array()
var shots: ProjectileRenderer
var mob_shots: ProjectileRenderer
var drops: PickupRenderer
var fx: FxRenderer
var fx_back: FxRenderer
var numbers: DamageNumbers
var tags: NameTags
var hud: Hud
var notice_layer: CanvasLayer
var notice_fx: FxRenderer
var windows_layer: CanvasLayer
var perf_layer: CanvasLayer
## The open window (LevelUpWindow / JobAdvanceWindow / PauseMenu), null when none.
var window: Node
## True while the pause menu (or the fallback pause) holds the run.
var paused := false
## Visual counters (tests and the perf summary): damage numbers, hit effects and sounds started.
var counters := {"numbers": 0, "hit_fx": 0, "sounds": 0, "exp_messages": 0, "windows": 0, "autopicks": 0}

var _autoplay := false
var _autopick := false
var _speed := 1
var _acc := 0.0
var _jump_latch := false
var _drink_hp_latch := false
var _drink_mp_latch := false
var _bot_memo := {}
var _kind_ids := PackedInt32Array()
var _kind_names := PackedStringArray()
var _slot_layers := PackedInt32Array()
var _base_layer := 0
var _player_layer := -1
var _top: Node2D
var _tag_source: _TagSource
## Waiting window request {"kind": "job"/"cards", ...} and the presentation delay before it opens.
var _pending_window: Dictionary = {}
var _window_delay := 0.0
var _window_kind := ""
var _window_req: Dictionary = {}
var _window_open_t := 0.0
var _window_auto := 0.0
var _restart_action := false
var _slow_fx := -1
var _shown_action := ""
var _blink_t := 0.0
var _frame_exp := 0
var _frame_sounds := {}
var _hud_sig := PackedInt32Array()
## "" while playing, "dead" or "cleared" once the end sequence started.
var _end_kind := ""
var _end_left := 0.0
var _finished := false
var _title_t := 0.0
var _title := PackedStringArray()
var _clear_text := false
var _saved_time_scale := 1.0

# Automation and perf.
var _shots_dir := ""
var _shot_every := 0.0
var _next_shot := 0.0
var _quit_after := 0.0
var _shot_queue := PackedStringArray()
var _quit_after_capture := false
var _timed_shots: Array = []
var _hit_shot_taken := false
var _miss_shot_taken := false
var _last_delta := 0.0
var _skip_perf_frames := 0
var _last_frame_us := 0
var _frame_count := 0
var _frame_ms := PackedFloat32Array()
## Run time and alive mobs of every recorded frame (perf_summary's per-minute and per-crowd breakdown).
var _frame_t := PackedFloat32Array()
var _frame_alive := PackedInt32Array()
var _warped := 0.0
var _recent_t := PackedFloat32Array()
var _recent_ms := PackedFloat32Array()
var _wall := 0.0
var _present_us := PackedFloat32Array()
var _sim_us := 0
var _sim_ticks := 0
var _max_alive := 0
var _level_by_minute := PackedInt32Array()
var _perf_on := false
var _perf_refresh := 0.0
var _perf_lines := PackedStringArray()
var _perf_canvas: Node2D


## Sets the stage, seed (-1 = random) and options; call before adding the scene to the tree.
func configure(p_stage_key: String, p_seed: int = -1, p_options: Dictionary = {}) -> void:
	stage_key = p_stage_key
	run_seed = p_seed
	options = p_options.duplicate()


func _ready() -> void:
	_autoplay = option_flag(options, "autoplay")
	_autopick = option_flag(options, "autopick")
	_speed = maxi(1, int(options.get("speed", 1)))
	_shots_dir = String(options.get("shots_dir", "")).replace("\\", "/")
	_shot_every = float(options.get("shot_every", 0.0))
	_next_shot = _shot_every
	_quit_after = float(options.get("quit_after", 0.0))
	_perf_on = _autoplay and option_flag(options, "perf")
	_window_auto = float(options.get("window_autopick", 0.0))
	if run_seed < 0:
		run_seed = randi() % 1000000
	if library == null:
		library = AssetLibrary.get_default()
	if library == null or not library.has_cache():
		_fail("the asset cache is missing (run scripts/import.sh)")
		return
	var errors := PackedStringArray()
	data = DataRepo.load_all(DataRepo.DATA_ROOT, errors)
	for e in errors:
		push_warning("RunScene: " + e)
	var stage: Dictionary = data.get("stages", {}).get("stages", {}).get(stage_key, {})
	if stage.is_empty():
		_fail("unknown stage '%s'" % stage_key)
		return
	map_id = int(stage.get("map_id", 0))
	var lib := library
	var setup := DataRepo.build_setup(data, stage_key, run_seed, _view_size(),
		func(p: String) -> Dictionary:
			var w := lib.img(p)
			return w.root if w != null else {},
		func(id: int) -> Dictionary: return lib.mob_root(id),
		setup_missing)
	for m in setup_missing:
		push_warning("RunScene: missing in the asset cache: " + m)
	world = RunWorld.new(setup)
	for w in world.warnings:
		push_warning("RunScene: " + w)
	var warp := float(options.get("warp", 0.0))
	if warp > 0.0:
		_warp(warp)
		if _shot_every > 0.0:
			_next_shot = (floorf(world.time / _shot_every + 1e-6) + 1.0) * _shot_every
	_build_presentation()
	_warm_ui()
	_apply_job_look(int(world.player_state.job_id))
	handle_events(world.drain_events())
	_start_title()
	_play_bgm()
	if _speed > 1:
		_saved_time_scale = Engine.time_scale
		Engine.time_scale = float(_speed)
	_last_frame_us = Time.get_ticks_usec()
	_present(0.0)


func _exit_tree() -> void:
	if _speed > 1:
		Engine.time_scale = _saved_time_scale


func _process(delta: float) -> void:
	if world == null:
		return
	if not _autoplay and Input.is_action_just_pressed("jump"):
		_jump_latch = true
	var now := Time.get_ticks_usec()
	var frame_us := now - _last_frame_us
	_last_frame_us = now
	advance_frame(delta)
	_record_frame(frame_us / 1000.0, Time.get_ticks_usec() - now)


func _unhandled_input(event: InputEvent) -> void:
	if world == null:
		return
	if not _autoplay and not event.is_echo():
		if event.is_action_pressed("drink_hp"):
			_drink_hp_latch = true
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("drink_mp"):
			_drink_mp_latch = true
			get_viewport().set_input_as_handled()
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F3:
		_perf_on = not _perf_on
		_perf_refresh = 0.0
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") and not event.is_echo():
		get_viewport().set_input_as_handled()
		if paused:
			resume()
		elif window == null and _end_kind == "":
			open_pause()


## One presentation frame of `delta` seconds (scaled by Engine.time_scale when called from _process): sim ticks,
## event mapping, windows, end sequence, renderer updates, shots.
func advance_frame(delta: float) -> void:
	if world == null:
		return
	_frame_sounds.clear()
	_last_delta = delta
	world.view_size = _view_size()
	if not paused and window == null and world.state == RunWorld.PLAYING:
		_acc += delta
		var budget := MAX_TICKS_PER_FRAME * _speed
		var first := true
		while _acc >= DT and budget > 0:
			_acc -= DT
			budget -= 1
			var input := _read_input(first)
			first = false
			var t0 := Time.get_ticks_usec()
			world.step(DT, input)
			_sim_us += Time.get_ticks_usec() - t0
			_sim_ticks += 1
			_after_tick()
			handle_events(world.drain_events())
			if world.state != RunWorld.PLAYING and _autopick:
				_service_windows()
			if world.state != RunWorld.PLAYING:
				break
		if budget == 0 or world.state != RunWorld.PLAYING:
			_acc = minf(_acc, DT) if world.state == RunWorld.PLAYING else 0.0
	else:
		_acc = 0.0
		_jump_latch = false
		_drink_hp_latch = false
		_drink_mp_latch = false
	if _window_delay > 0.0:
		_window_delay = maxf(0.0, _window_delay - delta)
	_auto_resolve_window(delta)
	if window == null and not paused:
		_service_windows()
	if _frame_exp > 0 and hud != null:
		hud.show_exp(_frame_exp)
		counters.exp_messages += 1
	_frame_exp = 0
	_advance_end(delta)
	if not paused:
		_present(delta)
	_automation()


# --- setup ---------------------------------------------------------------------------------------------------

func _build_presentation() -> void:
	world_root = Node2D.new()
	world_root.name = "World"
	add_child(world_root)
	map = MapRenderer.new()
	map.library = library
	world_root.add_child(map)
	if not map.load_map(map_id):
		push_warning("RunScene: map %d not in the cache" % map_id)
	cam = CameraRig.new()
	cam.bounds = world.bounds
	world_root.add_child(cam)
	cam.make_current()
	map.camera = cam
	var fhm := world.fhm
	var floor_layers := PackedInt32Array()
	for i in fhm.count():
		if fhm.is_floor(i) and not (fhm.layer[i] in floor_layers):
			floor_layers.append(fhm.layer[i])
	floor_layers.sort()
	_base_layer = _layer_at(world.player.pos)
	if floor_layers.is_empty():
		floor_layers.append(_base_layer)
	_kind_ids = MobRenderer.ids_from_kinds(world.mob_kinds)
	for layer in floor_layers:
		var mr := MobRenderer.new()
		mr.name = "Mobs%d" % layer
		mr.library = library
		map.actor_layer(layer).add_child(mr)
		mob_renderers.append(mr)
		mob_layers.append(layer if floor_layers.size() > 1 else -1)
	drops = PickupRenderer.new()
	drops.name = "Drops"
	drops.library = library
	fx_back = FxRenderer.new()
	fx_back.name = "FxBehind"
	fx_back.library = library
	# The character is drawn through a CanvasGroup so the invincibility blink fades it as one image (a plain modulate
	# would fade every part separately and show the body through the arm).
	player_group = CanvasGroup.new()
	player_group.name = "PlayerGroup"
	avatar = AvatarRenderer.new()
	avatar.name = "Player"
	avatar.library = library
	player_group.add_child(avatar)
	# The top container: drawn after every actor layer's content (projectiles, effects, numbers, tags).
	_top = Node2D.new()
	_top.name = "Top"
	map.actor_layer(MapRenderer.LAYER_COUNT - 1).add_child(_top)
	shots = ProjectileRenderer.new()
	shots.library = library
	_top.add_child(shots)
	mob_shots = ProjectileRenderer.new()
	mob_shots.library = library
	_top.add_child(mob_shots)
	fx = FxRenderer.new()
	fx.name = "Fx"
	fx.library = library
	fx.behind = fx_back
	_top.add_child(fx)
	numbers = DamageNumbers.new()
	numbers.library = library
	_top.add_child(numbers)
	tags = NameTags.new()
	_top.add_child(tags)
	player_tag = NameTags.new()
	player_tag.name = "PlayerTag"
	_top.add_child(player_tag)
	_tag_source = _TagSource.new()
	_kind_names = NameTags.names_for(world.mob_kinds, library)
	_place_player_layer(_base_layer)
	player_group.position = world.player.pos.round()
	cam.target = avatar
	hud = Hud.new()
	hud.library = library
	add_child(hud)
	notice_layer = CanvasLayer.new()
	notice_layer.name = "Notices"
	notice_layer.layer = 10
	add_child(notice_layer)
	var notice_canvas := Node2D.new()
	notice_canvas.name = "NoticeText"
	notice_layer.add_child(notice_canvas)
	notice_canvas.draw.connect(_draw_notices.bind(notice_canvas))
	notice_fx = FxRenderer.new()
	notice_fx.name = "NoticeFx"
	notice_fx.library = library
	notice_layer.add_child(notice_fx)
	windows_layer = CanvasLayer.new()
	windows_layer.name = "Windows"
	windows_layer.layer = 10
	add_child(windows_layer)
	perf_layer = CanvasLayer.new()
	perf_layer.name = "Perf"
	perf_layer.layer = 20
	add_child(perf_layer)
	_perf_canvas = Node2D.new()
	perf_layer.add_child(_perf_canvas)
	_perf_canvas.draw.connect(_draw_perf)


## Loads what the first level-up / job / pause window and the level-up effect draw (the UI imgs, the Magician
## instructor NPC and its name, the fonts), and what a job advancement swaps in at once (the job's weapon and the job
## skills' projectile / hit / effect art), so none of it is decoded in the middle of a run.
func _warm_ui() -> void:
	for path: String in [LevelUpWindow.ART, LevelUpWindow.ROW, LevelUpWindow.ROW_FOCUS, LevelUpWindow.LEVEL_DIGITS + "2",
			LevelUpWindow.KEY_DIGITS + "1", JobAdvanceWindow.DLG + "t", PauseMenu.BOX + "t"]:
		UiArt.frame(path)
	var npc := int(JobAdvanceWindow.INSTRUCTORS.get(200, 0))
	if npc > 0:
		UiArt.anim("Npc.wz/%07d.img/stand" % npc)
		UiArt.text("String.wz/Npc.img/%d/name" % npc)
	for path: String in [FX_LEVEL_UP, FX_JOB_CHANGED]:
		if library != null:
			library.find_anim(path)
	MapleText.width("Lv.", MapleText.SMALL, true)
	MapleText.width("Lv.", MapleText.SIZE, false)
	if library == null:
		return
	for wid: Variant in world.balance.player.get("weapon_by_job", {}).values():
		var wimg := library.img(AvatarRenderer.part_img_path(int(wid)))
		if wimg != null:
			for i in wimg.pages.size():
				wimg.page_texture(i)
	for key: String in world.book.defs:
		if int(world.book.def(key).get("job", 0)) == 0:
			continue
		for field: String in ["ball", "hit", "effect"]:
			for char_level: int in [1, 10]:
				var path := world.book.visual(key, field, world.book.canonical_level(key, 1), char_level)
				if path != "":
					library.find_anim(path)


func _play_bgm() -> void:
	var bgm := str(map.map_root.get("info", {}).get("bgm", "")) if map != null else ""
	var sfx := _sfx_service()
	if sfx != null and bgm != "":
		sfx.play_bgm(bgm)


func _start_title() -> void:
	if library == null:
		return
	var street := library.string_name("Street", map_id)
	var name_s := library.string_name("Map", map_id)
	_title = PackedStringArray([street, name_s])
	_title_t = TITLE_TIME if name_s != "" else 0.0


func _fail(msg: String) -> void:
	error = msg
	push_error("RunScene: " + msg)


# --- loop ----------------------------------------------------------------------------------------------------

## The MoveInput of the next tick: BotInput with autoplay, else the input actions (jump_pressed only on the first
## tick after the key went down).
func _read_input(first_tick: bool) -> MoveInput:
	if _autoplay:
		return BotInput.decide(world, _bot_memo)
	var mi := MoveInput.new()
	mi.left = Input.is_action_pressed("move_left")
	mi.right = Input.is_action_pressed("move_right")
	mi.up = Input.is_action_pressed("move_up")
	mi.down = Input.is_action_pressed("move_down")
	mi.jump_held = Input.is_action_pressed("jump")
	if first_tick and _jump_latch:
		mi.jump_pressed = true
		_jump_latch = false
	if first_tick:
		mi.drink_hp = _drink_hp_latch
		mi.drink_mp = _drink_mp_latch
		_drink_hp_latch = false
		_drink_mp_latch = false
	return mi


func _after_tick() -> void:
	_max_alive = maxi(_max_alive, world.swarm.alive_count())
	var minute := int(world.time / 60.0)
	while _level_by_minute.size() <= minute:
		_level_by_minute.append(int(world.player_state.level))


## Maps a batch of sim events to visuals, sounds and window requests (docs/ARCHITECTURE.md 4.4.3). The EXP of
## pickup_collected events is summed into one "+N EXP" message at the end of the frame.
func handle_events(events: Array) -> void:
	for e: Dictionary in events:
		match String(e.type):
			"boss_warning":
				var name := library.string_name("Mob", int(e.mob_id)).strip_edges()
				var lead := float(world.bosses.rules.warning_time)
				hud.push_notice("boss_%d" % int(e.boss_index), "%s will appear in %d seconds!" % [name, roundi(lead)], lead)
				_event_shot("boss_warning_%d.png" % int(e.boss_index), 0.1)
			"boss_spawned":
				var name := library.string_name("Mob", int(e.mob_id)).strip_edges()
				hud.push_notice("boss_%d" % int(e.boss_index), "%s has appeared!" % name)
				fx.play("Effect.wz/BasicEff.img/Summoned", e.pos)
				_event_shot("boss_arrival_%d.png" % int(e.boss_index), 0.1)
			"boss_attack":
				if e.phase == "start":
					_sound(String(e.sound))
					# tier C: evidence capture during the jump frame of the canonical mushroom windup.
					_event_shot("boss_windup_%d.png" % int(e.boss_index), 0.85)
				elif e.phase == "effect" and String(e.effect) != "":
					fx.play(String(e.effect), e.pos, int(e.facing) > 0)
				elif e.phase == "impact":
					# tier C: ground-wave art begins 50 ms after the canonical damage impact; capture its first frames.
					_event_shot("boss_shockwave_%d.png" % int(e.boss_index), 0.12)
			"cast":
				_on_cast(e)
			"boss_skill":
				_on_boss_skill(e)
			"mob_projectile_spawned":
				_event_shot("mob_projectile.png", 0.25) # tier C: capture the first part of the flight.
			"mob_projectile_hit":
				if String(e.hit) != "":
					fx.play(String(e.hit), e.pos, int(e.facing) > 0)
			"mob_healed":
				hud.push_notice("heal_%d" % int(e.mob), "%s recovered %d HP" % [library.string_name("Mob", int(e.mob_id)).strip_edges(), int(e.amount)])
				_event_shot("mob_heal.png", 0.15) # tier C: show the canonical mob0 effect while the bar reflects healing.
			"basic_attack":
				if e.phase == "start":
					_restart_action = true
					_sound(String(e.sound))
				else:
					fx.play(String(e.afterimage), Vector2.ZERO, int(e.facing) > 0, avatar)
			"mob_hit":
				_on_mob_hit(e)
			"mob_died":
				_sound(SND_MOB % [int(e.mob_id), "Die"])
			"player_hit":
				_on_player_hit(e)
			"player_jump":
				_sound(SND_JUMP)
			"portal_used":
				cam.snap_to(e.pos)
			"pickup_spawned":
				_sound(SND_DROP)
			"pickup_collected":
				_sound(SND_PICKUP)
				_frame_exp += int(e.exp)
			"level_up":
				fx.play(FX_LEVEL_UP, Vector2.ZERO, false, avatar)
				_sound(SND_LEVEL_UP)
				_window_delay = WINDOW_DELAY
				if int(e.level) <= 2 or int(e.level) % 10 == 0:
					_event_shot("levelup_%d.png" % int(e.level), 0.4)
			"job_advance_pending":
				_pending_window = {"kind": "job", "options": e.options}
			"job_changed":
				_on_job_changed(int(e.job_id))
			"choice_pending":
				_pending_window = {"kind": "cards", "cards": e.cards, "bonus": bool(e.bonus)}
			"player_died":
				_on_player_died(e.pos)
			"stage_cleared":
				_on_stage_cleared()


func _on_boss_skill(e: Dictionary) -> void:
	var source := int(e.mob)
	if String(e.effect) != "":
		# tier C: heal mob0 pos0 uses feet; MobSkill pos3 effect art uses the canonical body-box center.
		var effect_pos: Vector2 = e.pos if int(e.skill_id) == 114 else world.mob_center(source)
		fx.play(String(e.effect), effect_pos, int(e.facing) > 0)
	for slot: int in e.targets:
		if String(e.summon_effect) != "":
			fx.play(String(e.summon_effect),Vector2(world.swarm.x[slot],world.swarm.y[slot]))
		elif slot != source:
			fx.play("Skill.wz/MobSkill.img/%d/level/%d/mob0" % [int(e.skill_id),int(e.level)],world.mob_center(slot))
	if String(e.player_effect) != "":
		if _slow_fx >= 0:
			fx.stop(_slow_fx)
		# tier C: affected pos1 is anchored above the player's canonical body box; lifetime follows sim status.
		_slow_fx = fx.play_repeating(String(e.player_effect),Vector2.ZERO,INF,false,avatar,Vector2(0,world.body.position.y))
	_sound(SND_MOB % [int(e.mob_id),String(e.action).replace("skill", "Skill")])


func _on_cast(e: Dictionary) -> void:
	if world.player.state == PlayerMotion.ST_STAND and not bool(world.player_state.dead):
		_restart_action = true
	var effect := String(e.effect)
	if effect != "":
		fx.play(effect, Vector2.ZERO, int(e.facing) > 0, avatar)
	var key := String(e.skill)
	var use := String(world.book.def(key).get("sounds", {}).get("use", ""))
	if use == "":
		use = SND_SKILL_USE % int(e.skill_id)
	_sound(use)


func _on_mob_hit(e: Dictionary) -> void:
	var m := int(e.mob)
	numbers.spawn(int(e.damage), e.pos, DamageNumbers.CRIT if bool(e.crit) else DamageNumbers.DEALT, m)
	counters.numbers += 1
	var hv := String(e.hit_visual)
	if hv != "":
		var at: Vector2 = world.mob_center(m) if m >= 0 and m < world.swarm.capacity() else e.pos
		fx.play(hv, at.round(), at.x > world.player.pos.x)
		counters.hit_fx += 1
	_sound(SND_MOB % [int(e.mob_id), "Damage"])


func _on_player_hit(e: Dictionary) -> void:
	var head: Vector2 = e.pos + Vector2(0.0, world.body.position.y)
	if bool(e.get("miss", false)):
		numbers.spawn_miss(head, DamageNumbers.TAKEN, PLAYER_KEY)
		counters.numbers += 1
		if not _miss_shot_taken:
			_miss_shot_taken = true
			_event_shot("miss_first.png", 0.05) # tier C: capture the first visible MISS during playtests.
		return
	numbers.spawn(int(e.damage), head, DamageNumbers.TAKEN, PLAYER_KEY)
	counters.numbers += 1
	avatar.set_expression("hit", HIT_FACE_TIME)
	_blink_t = 0.0
	if not _hit_shot_taken:
		_hit_shot_taken = true
		_event_shot("hit_first.png", BLINK_PERIOD * 0.7)


func _on_job_changed(job_id: int) -> void:
	fx.play(FX_JOB_CHANGED, Vector2.ZERO, false, avatar)
	_sound(SND_JOB_CHANGED)
	# The level's upgrade window follows at once in the sim: hold it until the JobChanged pillar has played, or the
	# centred window hides the effect (autopick runs never wait).
	var a := library.find_anim(FX_JOB_CHANGED) if library != null else null
	_window_delay = maxf(_window_delay, a.total if a != null and a.total > 0.0 else JOB_WINDOW_DELAY)
	_apply_job_look(job_id)
	_event_shot("job_%d.png" % job_id, 0.8)
	_event_shot("job_%d_after.png" % job_id, 4.0)


## The character look for a job: the default clothes plus the configured canonical weapon.
func _apply_job_look(job_id: int) -> void:
	var weapons: Dictionary = world.balance.player.get("weapon_by_job", {})
	var weapon := int(weapons.get("0", 0))
	for ancestor in world.jobs.lineage(job_id):
		if weapons.has(str(ancestor)):
			weapon = int(weapons[str(ancestor)])
			break
	var equips: Array = AvatarRenderer.DEFAULT_LOOK.equips.duplicate()
	if weapon > 0:
		equips.append(weapon)
	avatar.set_look({"equips": equips})


## Fast-forwards the sim to run time `to` before anything is drawn (option warp): BotInput plays and chooses, the
## events are dropped. Stops early when the run ends.
func _warp(to: float) -> void:
	while world.time < to - 1e-6:
		BotInput.auto_choose(world)
		if world.state != RunWorld.PLAYING:
			break
		world.step(DT, BotInput.decide(world, _bot_memo))
		_after_tick()
		world.drain_events()
	_warped = world.time


func _on_player_died(pos: Vector2) -> void:
	_end_kind = "dead"
	avatar.play("dead", true, false)
	fx.play_tomb(pos.round())
	_sound(SND_TOMB)
	var fall := library.find_anim(FxRenderer.TOMB_FALL)
	_end_left = (fall.total if fall != null else 0.0) + DEATH_HOLD
	_event_shot("death_fall.png", 0.3)
	_event_shot("death_land.png", _end_left - 0.5)


func _on_stage_cleared() -> void:
	_end_kind = "cleared"
	_end_left = CLEAR_HOLD
	var a := library.find_anim(FX_CLEAR)
	if a != null:
		notice_fx.play_anim(a, (_view_size() * 0.5).floor(), false, null, Vector2.ZERO, true)
	else:
		_clear_text = true
	_sound(SND_CLEAR)
	_event_shot("clear.png", 1.0)


func _advance_end(delta: float) -> void:
	if _end_kind == "" or _finished:
		return
	_end_left -= delta
	if _end_left <= 0.0:
		_finish()


## Plays a sound once per frame per path (a swarm hit by a piercing shell is one sound, not twenty).
func _sound(path: String) -> void:
	if path == "" or _frame_sounds.has(path):
		return
	_frame_sounds[path] = true
	var sfx := _sfx_service()
	if sfx != null and sfx.play(path):
		counters.sounds += 1


# --- windows -------------------------------------------------------------------------------------------------

## Opens the waiting window request (JobAdvanceWindow / LevelUpWindow), or with autopick resolves it at once.
func _service_windows() -> void:
	var guard := 0
	while not _pending_window.is_empty() and window == null and guard < 64:
		guard += 1
		if not _autopick and _window_delay > 0.0:
			return
		var req := _pending_window
		_pending_window = {}
		var level := world.progression.front() if world.progression.has_pending() else int(world.player_state.level)
		if String(req.kind) == "job":
			if _autopick:
				counters.autopicks += 1
				var j := BotInput.pick_job(req.options)
				if j < 0 or not world.apply_job(j):
					world.decline_job()
				handle_events(world.drain_events())
				continue
			var jw := JobAdvanceWindow.new()
			_show_window(jw, "job", req, level)
			jw.job_chosen.connect(_on_job_chosen)
			jw.declined.connect(_on_job_declined)
			jw.open(req.options, level, int(world.player_state.job_id))
		else:
			if _autopick:
				counters.autopicks += 1
				world.apply_choice(BotInput.pick_card_for(world, req.cards))
				handle_events(world.drain_events())
				continue
			var lw := LevelUpWindow.new()
			_show_window(lw, "cards", req, level)
			lw.card_chosen.connect(_on_card_chosen)
			lw.open(req.cards, level, bool(req.get("bonus", false)))


## window_autopick: an open level-up / job window is answered with BotInput's choice after that many seconds (the
## card BotInput.pick_card_for prefers, the first available job; demos and evidence runs: the window is shown, then
## answered through the same handlers as its signals).
func _auto_resolve_window(delta: float) -> void:
	if _window_auto <= 0.0 or window == null or (_window_kind != "cards" and _window_kind != "job"):
		return
	_window_open_t += delta
	if _window_open_t < _window_auto:
		return
	# Answered from outside the window: hide it now (its own buttons would have started its fade-out).
	if window is CanvasItem:
		(window as CanvasItem).visible = false
	if _window_kind == "cards":
		_on_card_chosen(BotInput.pick_card_for(world, _window_req.get("cards", [])))
	else:
		var j := BotInput.pick_job(_window_req.get("options", []))
		if j < 0:
			_on_job_declined()
		else:
			_on_job_chosen(j)


func _show_window(w: Node, kind: String, req: Dictionary = {}, level: int = 0) -> void:
	window = w
	_window_kind = kind
	_window_req = req
	_window_open_t = 0.0
	counters.windows += 1
	if kind != "pause":
		_event_shot("window_%s_%d.png" % [kind, level], 0.6)
	windows_layer.add_child(w)


## Forgets the open window; it is freed once its own fade-out (MapleWindow transition) has had time to play.
func _close_window() -> void:
	if window != null and is_instance_valid(window):
		# Connected to the window itself: the connection goes away if the window is freed first (with the scene).
		get_tree().create_timer(WINDOW_FREE_DELAY, true, false, true).timeout.connect(window.queue_free)
	window = null
	_window_kind = ""


func _on_card_chosen(card_id: String) -> void:
	if _window_kind != "cards" or not world.apply_choice(card_id):
		return
	_close_window()
	handle_events(world.drain_events())
	_service_windows()


func _on_job_chosen(job_id: int) -> void:
	if _window_kind != "job" or not world.apply_job(job_id):
		return
	_close_window()
	handle_events(world.drain_events())
	_service_windows()


func _on_job_declined() -> void:
	if _window_kind != "job" or not world.decline_job():
		return
	_close_window()
	handle_events(world.drain_events())
	_service_windows()


## Pauses the run and opens the PauseMenu (Esc).
func open_pause() -> void:
	paused = true
	_freeze(true)
	var pm := PauseMenu.new()
	_show_window(pm, "pause")
	pm.resumed.connect(resume)
	pm.quit_requested.connect(_on_quit_requested)
	pm.open()


## Closes the pause menu and continues the run.
func resume() -> void:
	if _window_kind == "pause":
		_close_window()
	paused = false
	_freeze(false)


func _on_quit_requested() -> void:
	resume()
	var flow := get_node_or_null("/root/Flow")
	if flow != null and flow.has_method("goto_stage_select") and bool(options.get("use_flow", true)):
		flow.call("goto_stage_select")
	else:
		_finish()


## Stops (or restarts) every world animation and the HUD while the pause menu is open.
func _freeze(on: bool) -> void:
	var mode := Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	if world_root != null:
		world_root.process_mode = mode
	if hud != null:
		hud.process_mode = mode


## A boolean option given as a bool, a number (0 = off) or a command-line string ("1", "true"; "0"/"false" = off).
static func option_flag(opts: Dictionary, key: String) -> bool:
	var v: Variant = opts.get(key, false)
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		TYPE_STRING, TYPE_STRING_NAME:
			var t := String(v).to_lower()
			return t != "" and t != "0" and t != "false"
	return v != null


# --- presentation --------------------------------------------------------------------------------------------

func _present(delta: float) -> void:
	if _slow_fx >= 0 and (world.player_state.get("slow",{}).is_empty() or bool(world.player_state.dead)):
		fx.stop(_slow_fx)
		_slow_fx = -1
	_update_player(delta)
	_slot_layers = MobRenderer.update_slot_layers(world.swarm, world.fhm.layer, _slot_layers, _base_layer)
	var boss_actions := world.bosses.action_snapshot(world.swarm)
	for i in mob_renderers.size():
		mob_renderers[i].update_from(world.swarm, _kind_ids, mob_layers[i], _slot_layers, boss_actions)
	shots.update_from(world.projectiles, world.visual_paths, delta)
	mob_shots.update_from(world.mob_projectiles, world.visual_paths, delta)
	drops.update_from(world.pickups, delta)
	tags.update_from(world.swarm, world.mob_elite, _kind_names)
	_update_hud()
	if _title_t > 0.0:
		_title_t = maxf(0.0, _title_t - delta)
		notice_layer.get_node("NoticeText").queue_redraw()
	elif _clear_text:
		notice_layer.get_node("NoticeText").queue_redraw()


func _update_player(delta: float) -> void:
	var p := world.player
	player_group.position = p.pos.round()
	var dead := bool(world.player_state.dead)
	if not dead:
		avatar.set_facing(p.facing)
	var layer := _player_layer
	if p.fh >= 0:
		layer = world.fhm.layer[p.fh]
	elif p.ladder >= 0 and p.ladder < world.ladders.page.size():
		layer = world.ladders.page[p.ladder]
	if layer != _player_layer and layer >= 0:
		_place_player_layer(layer)
	var action := String(world.player_state.action)
	var motion := p.stance()
	if dead:
		if avatar.stance != "dead":
			avatar.play("dead", true, false)
	elif action != motion:
		# Skill stance while standing; basic swing stance while standing or airborne.
		var st := action if avatar.has_stance(action) else DEFAULT_ACTION
		avatar.play(st, _restart_action or _shown_action != st, false)
		_shown_action = st
	else:
		avatar.play(motion)
		_shown_action = motion
	_restart_action = false
	# Ladders and ropes animate only while climbing.
	if not (p.state == PlayerMotion.ST_LADDER and p.vel.y == 0.0):
		avatar.advance(delta)
	var inv := float(world.player_state.invincible_t)
	if inv > 0.0 and not dead:
		_blink_t += delta
		player_group.self_modulate.a = BLINK_ALPHA if fposmod(_blink_t, BLINK_PERIOD) >= BLINK_PERIOD * 0.5 else 1.0
	else:
		player_group.self_modulate.a = 1.0
	# The character name tag under the feet (hidden once dead, like the elite tags of dying mobs).
	_tag_source.x[0] = p.pos.x
	_tag_source.y[0] = p.pos.y
	_tag_source.state[0] = MobRenderer.DIE if dead else MobRenderer.STAND
	player_tag.update_from(_tag_source, PackedByteArray([1]), PackedStringArray([_player_name()]))


## Moves the player, its behind-effects and the drops into actor layer `layer` (drawn with that foothold layer):
## behind-effects first, then the layer's mobs, the player, the drops (tier C: drops over mobs and the player so EXP is
## never hidden in a crowd) and (layer 7) the top container last.
func _place_player_layer(layer: int) -> void:
	_player_layer = layer
	var c := map.actor_layer(layer)
	for n: Node in [fx_back, player_group, drops]:
		if n.get_parent() != c:
			if n.get_parent() != null:
				n.get_parent().remove_child(n)
			c.add_child(n)
	c.move_child(player_group, -1)
	c.move_child(drops, -1)
	if _top.get_parent() == c:
		c.move_child(_top, -1)
	c.move_child(fx_back, 0)


func _update_hud() -> void:
	var ps := world.player_state
	# The encounter widget tracks damage every frame, independently of the status/timer snapshot signature.
	hud.boss_bar.update(ps, {"bosses": boss_bars()})
	var sig := PackedInt32Array([int(ps.hp), int(ps.mp), int(ps.max_hp), int(ps.max_mp), int(ps.exp),
		int(ps.exp_next), int(ps.level), int(ps.job_id), int(run_time()), world.kills, world.loadout.version,
		int(ps.potions.hp.count), int(ps.potions.mp.count), int(ps.potions.hp.item_id), int(ps.potions.mp.item_id),
		int(bool(ps.get("mp_short", false)))])
	for buff: Dictionary in ps.buffs:
		sig.append(int(buff.skill_id))
		sig.append(ceili(float(buff.remaining)))
	if sig == _hud_sig:
		return
	_hud_sig = sig
	var info := run_info()
	hud.store_state(ps, info)
	hud.status.update(ps, info)
	hud.counters.update(ps, info)
	hud.skills.update(ps, info)
	hud.system_messages.update(ps, info)
	hud.potion_slot.update(ps, info)
	hud.buff_row.update(ps, info)


## Live encounter snapshots for the dedicated HUD bar; canonical hpTag values remain unchanged in the asset cache.
func boss_bars() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for record: Dictionary in world.bosses.records:
		var slot := int(record.slot)
		if float(record.spawn_time) < 0.0 or bool(record.dead) or slot < 0 or world.swarm.active[slot] == 0:
			continue
		var id := int(record.mob_id)
		var info: Dictionary = world.setup.mob_imgs[id].get("info", {})
		var override: Dictionary = data.mobs.mobs.get(str(id), {}).get("boss_ui", {})
		# tier C: standard 1/5 fallback for missing hpTag metadata; named exceptions live in survivor boss_ui data.
		rows.append({"boss_index": int(record.boss_index), "mob": slot, "mob_id": id,
			"name": library.string_name("Mob", id).strip_edges(), "hp": int(world.swarm.hp[slot]),
			"max_hp": int(world.swarm.max_hp[slot]), "icon_id": int(override.get("icon_id", id)),
			"hp_tag_color": int(override.get("hp_tag_color", info.get("hpTagColor", 1))),
			"hp_tag_bgcolor": int(override.get("hp_tag_bgcolor", info.get("hpTagBgcolor", 5)))})
	return rows


## Run time in seconds, snapped to 1 ms (900 ticks of 1/60 s sum to 899.9999...; the HUD and results show 15:00).
func run_time() -> float:
	return snappedf(world.time, 0.001)


## The HUD's run_info (Hud.update): time, kills, name, job name, exp_next and the owned skills with ranks.
func run_info() -> Dictionary:
	var skills: Array = []
	for key: String in world.loadout.order:
		skills.append({"icon": String(world.book.def(key).get("icon", "")), "rank": world.loadout.rank(key)})
	return {"time": run_time(), "kills": world.kills, "name": _player_name(),
		"job_name": world.jobs.name_of(int(world.player_state.job_id)),
		"exp_next": int(world.player_state.exp_next), "skills": skills}


func _draw_notices(canvas: Node2D) -> void:
	var view := _view_size()
	var font := hud.font if hud != null and hud.font != null else Hud.make_font()
	var bold := hud.bold_font if hud != null and hud.bold_font != null else Hud.make_font(700)
	if _title_t > 0.0 and _title.size() == 2:
		var a := clampf(_title_t / TITLE_FADE, 0.0, 1.0)
		_centered_text(canvas, font, _title[0], Vector2(view.x * 0.5, 74), 12, Color(1, 1, 1, a), a)
		_centered_text(canvas, bold, _title[1], Vector2(view.x * 0.5, 96), 20, Color(1, 1, 1, a), a)
	if _clear_text:
		_centered_text(canvas, bold, "STAGE CLEAR", view * 0.5, 32, Color(1, 0.86, 0.3), 1.0)


func _centered_text(canvas: Node2D, f: Font, s: String, at: Vector2, size: int, col: Color, alpha: float) -> void:
	if s == "":
		return
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := Vector2(floorf(at.x - w * 0.5), floorf(at.y))
	canvas.draw_string_outline(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, 0.9 * alpha))
	canvas.draw_string(f, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


# --- end, summary, automation --------------------------------------------------------------------------------

## The run summary given to run_finished / Flow.finish_run.
func build_summary() -> Dictionary:
	var skills: Array = []
	for key: String in world.loadout.order:
		var d := world.book.def(key)
		skills.append({"key": key, "name": String(d.get("name", key)), "icon": String(d.get("icon", "")),
			"rank": world.loadout.rank(key)})
	var job_id := int(world.player_state.job_id)
	return {
		"stage": stage_key, "map_id": map_id, "map_name": library.string_name("Map", map_id),
		"street_name": library.string_name("Street", map_id), "time": run_time(), "duration": world.duration,
		"cleared": world.state == RunWorld.CLEARED, "level": int(world.player_state.level), "job_id": job_id,
		"job_name": world.jobs.name_of(job_id), "kills": world.kills, "damage_dealt": world.damage_dealt,
		"skills": skills, "seed": run_seed,
	}


func _finish() -> void:
	if _finished:
		return
	_finished = true
	var summary := build_summary()
	run_finished.emit(summary)
	if _quit_after > 0.0:
		_automation_end(summary)
		return
	var flow := get_node_or_null("/root/Flow")
	if flow != null and flow.has_method("finish_run") and bool(options.get("use_flow", true)):
		flow.call("finish_run", summary)


## Screenshots every shot_every s of run time; quit_after ends an automated run (summary.json, final shot, quit).
func _automation() -> void:
	if _shots_dir != "" and _shot_every > 0.0 and world.time >= _next_shot - 1e-6:
		_request_shot("t%d.png" % roundi(_next_shot))
		while _next_shot <= world.time + 1e-6:
			_next_shot += _shot_every
	for i in range(_timed_shots.size() - 1, -1, -1):
		_timed_shots[i][0] = float(_timed_shots[i][0]) - _last_delta
		if float(_timed_shots[i][0]) <= 0.0:
			_request_shot(String(_timed_shots[i][1]))
			_timed_shots.remove_at(i)
	if _quit_after > 0.0 and not _finished and _end_kind == "" and world.time >= _quit_after - 1e-6:
		_finished = true
		_automation_end(build_summary())


func _automation_end(summary: Dictionary) -> void:
	if _shots_dir != "":
		DirAccess.make_dir_recursive_absolute(_shots_dir)
		var f := FileAccess.open(_shots_dir.path_join("summary.json"), FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(perf_summary(summary), "\t"))
			f.close()
	print("RunScene: %s" % JSON.stringify(perf_summary(summary)))
	if _shots_dir != "" and DisplayServer.get_name() != "headless":
		_quit_after_capture = true
		_request_shot("final.png")
	else:
		get_tree().quit()


## Frame-time and sim statistics of this run plus its summary (written to summary.json by automated runs).
func perf_summary(summary: Dictionary = {}) -> Dictionary:
	var s := _frame_ms.duplicate()
	s.sort()
	var pr := _present_us.duplicate()
	pr.sort()
	return {
		"summary": summary, "frames": s.size(), "frame_ms": {"p50": _pct(s, 0.5), "p95": _pct(s, 0.95),
			"p99": _pct(s, 0.99), "max": s[s.size() - 1] if not s.is_empty() else 0.0, "avg": _avg(s)},
		"frame_work_us": {"p50": _pct(pr, 0.5), "p95": _pct(pr, 0.95), "avg": _avg(pr)},
		"sim_us_per_tick": float(_sim_us) / maxf(1.0, _sim_ticks), "ticks": _sim_ticks, "max_alive": _max_alive,
		"level_by_minute": Array(_level_by_minute), "job_id": int(world.player_state.job_id), "kills": world.kills,
		"state": world.state_name(), "time": world.time, "speed": _speed, "counters": counters.duplicate(),
		"potions_collected": world.potions.collected.duplicate(), "potions_used": world.potions.used.duplicate(),
		"missing": Array(library.missing) if library != null else [], "warped_to": _warped,
		"frame_ms_by_minute": _perf_by_minute(), "frame_ms_100plus": _perf_where(100), "frame_ms_200plus": _perf_where(200),
	}


## Frame-time percentiles per run minute with the mean / max alive mobs of those frames.
func _perf_by_minute() -> Array:
	var groups := {}
	for i in _frame_ms.size():
		var m := int(_frame_t[i] / 60.0)
		if not groups.has(m):
			groups[m] = [PackedFloat32Array(), 0, 0]
		var g: Array = groups[m]
		var v0: PackedFloat32Array = g[0]
		v0.append(_frame_ms[i])
		g[0] = v0
		g[1] = int(g[1]) + _frame_alive[i]
		g[2] = maxi(int(g[2]), _frame_alive[i])
	var out: Array = []
	var keys := groups.keys()
	keys.sort()
	for m: int in keys:
		var v: PackedFloat32Array = groups[m][0]
		v.sort()
		out.append({"minute": m, "frames": v.size(), "p50": _pct(v, 0.5), "p95": _pct(v, 0.95), "p99": _pct(v, 0.99),
			"max": v[v.size() - 1], "alive_mean": roundi(float(groups[m][1]) / v.size()), "alive_max": groups[m][2]})
	return out


## Frame-time percentiles of the frames drawn with at least `min_alive` mobs alive.
func _perf_where(min_alive: int) -> Dictionary:
	var v := PackedFloat32Array()
	for i in _frame_ms.size():
		if _frame_alive[i] >= min_alive:
			v.append(_frame_ms[i])
	v.sort()
	return {"frames": v.size(), "p50": _pct(v, 0.5), "p95": _pct(v, 0.95), "p99": _pct(v, 0.99),
		"max": v[v.size() - 1] if not v.is_empty() else 0.0}


## Schedules a screenshot `delay` presentation seconds from now (automated runs with shots_dir only).
func _event_shot(file_name: String, delay: float) -> void:
	if _shots_dir != "":
		_timed_shots.append([delay, file_name])


func _request_shot(file_name: String) -> void:
	if _shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	_shot_queue.append(file_name)
	if not RenderingServer.frame_post_draw.is_connected(_capture):
		RenderingServer.frame_post_draw.connect(_capture, CONNECT_ONE_SHOT)


func _capture() -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shots_dir)
	if img != null and not img.is_empty():
		for n in _shot_queue:
			img.save_png(_shots_dir.path_join(n))
	_shot_queue.clear()
	_skip_perf_frames = 2
	if _quit_after_capture:
		get_tree().quit()


func _record_frame(frame_ms: float, work_us: int) -> void:
	_frame_count += 1
	_wall += frame_ms / 1000.0
	if _skip_perf_frames > 0:
		_skip_perf_frames -= 1
	elif _frame_count > PERF_WARMUP_FRAMES:
		_frame_ms.append(frame_ms)
		_present_us.append(float(work_us))
		_frame_t.append(world.time)
		_frame_alive.append(world.swarm.alive_count())
	_recent_t.append(_wall)
	_recent_ms.append(frame_ms)
	var cut := 0
	while cut < _recent_t.size() and _recent_t[cut] < _wall - PERF_WINDOW:
		cut += 1
	if cut > 0:
		_recent_t = _recent_t.slice(cut)
		_recent_ms = _recent_ms.slice(cut)
	_perf_refresh -= frame_ms / 1000.0
	if _perf_on and _perf_refresh <= 0.0:
		_perf_refresh = PERF_REFRESH
		_perf_lines = perf_lines()
		_perf_canvas.queue_redraw()
	elif not _perf_on and not _perf_lines.is_empty():
		_perf_lines = PackedStringArray()
		_perf_canvas.queue_redraw()


## The perf overlay text: FPS, frame ms avg/p95 over PERF_WINDOW s, sim ms per tick, counts and state.
func perf_lines() -> PackedStringArray:
	var s := _recent_ms.duplicate()
	s.sort()
	var avg := _avg(s)
	var tick_ms := float(_sim_us) / maxf(1.0, _sim_ticks) / 1000.0
	return PackedStringArray([
		"FPS %d   frame %.2f ms avg  %.2f p95 (%.0f s)" % [Engine.get_frames_per_second(), avg, _pct(s, 0.95),
			PERF_WINDOW],
		"sim %.3f ms/tick   x%d" % [tick_ms, _speed],
		"mobs %d   shots %d   drops %d" % [world.swarm.alive_count(), world.projectiles.active_count(),
			world.pickups.active_count()],
		"%s   %s   Lv %d   job %d" % [world.state_name(), Hud.format_time(world.time),
			int(world.player_state.level), int(world.player_state.job_id)],
	])


func _draw_perf() -> void:
	if _perf_lines.is_empty():
		return
	var f := hud.font if hud != null and hud.font != null else Hud.make_font()
	var box := Rect2(6, 48, 300, 8 + 14 * _perf_lines.size())
	_perf_canvas.draw_rect(box, Color(0, 0, 0, 0.6))
	for i in _perf_lines.size():
		_perf_canvas.draw_string(f, Vector2(box.position.x + 5, box.position.y + 15 + 14 * i), _perf_lines[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.75, 1.0, 0.75))


# --- helpers -------------------------------------------------------------------------------------------------

## One-slot MobSwarm-shaped arrays so NameTags can draw the player's tag.
class _TagSource:
	extends RefCounted
	var state := PackedInt32Array([0])
	var kind := PackedInt32Array([0])
	var x := PackedFloat32Array([0.0])
	var y := PackedFloat32Array([0.0])


func _player_name() -> String:
	return String(options.get("name", DEFAULT_NAME))


func _view_size() -> Vector2:
	return get_viewport().get_visible_rect().size if is_inside_tree() else RunWorld.DEFAULT_VIEW


func _layer_at(p: Vector2) -> int:
	var f := world.fhm.find_below(p.x, p.y - 2.0)
	return world.fhm.layer[f] if f >= 0 else 0


func _sfx_service() -> AudioService:
	return get_node_or_null("/root/Sfx") as AudioService


static func _pct(sorted: PackedFloat32Array, q: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[clampi(int(sorted.size() * q), 0, sorted.size() - 1)]


static func _avg(v: PackedFloat32Array) -> float:
	if v.is_empty():
		return 0.0
	var t := 0.0
	for x in v:
		t += x
	return t / v.size()
