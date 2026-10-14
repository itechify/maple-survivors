extends Node2D
## Debug map viewer: renders a v83 map from the asset cache with the whole presentation layer on top, for visual checks
## and frame-time measurements (docs/IMPLEMENTATION_PLAN.md WP C).
##
##   bash scripts/godot.sh --path game res://scenes/debug/map_viewer.tscn -- --map=104040000 --cam=600,-200 \
##       --shot=C:/abs/path.png --frames=30
##
## Flags (all optional):
##   --map=<id>          map (104040000)
##   --cam=x,y           camera centre (free camera; arrow keys / WASD move it). Default: the first spawn point.
##   --char=x,y          character position (dropped onto the floor below); default near the camera centre
##   --stance=<name>     fix the character's stance (default: walk/stand cycling); --facing=1 faces right
##   --gallery           a row of characters, one per stance, and a grid of mobs (one per state) at the camera
##   --mobs=N            N animated mobs walking on the map's floors (performance check)
##   --perf=N            after a 60-frame warm-up, measure N frames and print frame-time stats, then quit
##   --vsync=off         disable vsync and the FPS cap
##   --hud=0 --demo=0 --bgm=0   hide the HUD / the sample mobs, numbers, FX, projectiles, pickups / mute the BGM
##   --shot=<png>        after --frames=N (default 30) save the logical viewport image and quit
##   --wshot=<png>       with --shot, also save the real window pixels (screen capture) for integer-scaling checks
##   --checker           draw a 1 px checkerboard (top-left) for the integer-scaling check
##   --window=max|full   maximise / fullscreen the window at start
##   --fill              use the opt-in fill-window view (Settings.fill_window, not saved) instead of the default
##   --messages          fixed sample of HUD "+N EXP" system messages (demo mode also shows elite name tags)
##   --quit=N            quit after N frames

const DEMO_MOBS := [100100, 100101, 130101, 120100, 210100, 1210100, 1210102, 1110100]
const GALLERY_STANCES := ["stand1", "walk1", "jump", "alert", "prone", "ladder", "rope", "swingO1", "shoot1", "dead"]
const DEMO_ITEMS := [4000019, 4000000, 4000016, 4000011, 4000010, 4000017, 4000001, 4000012]
const SNAIL_BALL := "Skill.wz/000.img/skill/0001000/level/%d/ball"
const SNAIL_HIT := "Skill.wz/000.img/skill/0001000/level/1/hit/0"
const BOLT_BALL := "Skill.wz/200.img/skill/2001004/ball"
## MobRenderer states.
const STAND := 0
const MOVE := 1
const HIT := 3
const DIE := 4

var args: Dictionary = {}
var map: MapRenderer
var cam: CameraRig
var avatar: AvatarRenderer
var mobs: MobRenderer
var fx: FxRenderer
var numbers: DamageNumbers
var shots: ProjectileRenderer
var drops: PickupRenderer
var hud: Hud
var tags: NameTags

var _swarm: DebugSoA
var _kind_ids := PackedInt32Array()
var _mob_home: PackedFloat32Array = []
var _mob_fh: PackedInt32Array = []
var _proj: DebugSoA
var _visuals: Array = []
var _picks: DebugSoA
var _frame := 0
var _time := 0.0
var _cam_speed := 600.0
var _char_home := Vector2.ZERO
var _demo_t := 0.0
var _rng := RandomNumberGenerator.new()
var _perf_samples: PackedFloat32Array = []
var _render_samples: PackedFloat32Array = []
var _last_us := 0
var _mob_us := 0
var _pan_origin := Vector2.ZERO
var _sync_frames := 0
var _sync_bad := 0
var _gallery: Array = []
var _gallery_mobs: DebugSoA
var _elite := PackedByteArray()
var _kind_names := PackedStringArray()


func _ready() -> void:
	args = parse_args(OS.get_cmdline_user_args())
	_rng.seed = 83
	if str(args.get("vsync", "on")) == "off":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
	if args.has("wshot"):
		# The screen capture needs the window unoccluded.
		DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	if args.has("fill"):
		var st := get_node_or_null("/root/Settings") as GameSettings
		if st != null:
			st.fill_window = true
			st.fit_viewport()
	match str(args.get("window", "")):
		"max":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
		"full":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	map = MapRenderer.new()
	add_child(map)
	var map_id := int(args.get("map", "104040000"))
	if not map.load_map(map_id):
		push_error("map_viewer: map %d not in the cache" % map_id)
	print("map_viewer: map %d '%s' stats=%s bounds=%s missing=%d %s" % [map_id,
		map.library.string_name("Map", map_id) if map.library != null else "", map.stats, map.bounds,
		map.missing.size(), map.missing])
	cam = CameraRig.new()
	cam.bounds = map.bounds
	cam.anchor_y = 0.5
	add_child(cam)
	cam.make_current()
	map.camera = cam
	var c := parse_vec(str(args.get("cam", "")), _spawn_point())
	cam.snap_to(c)
	_pan_origin = c
	var layer := _setup_character(parse_vec(str(args.get("char", "")), c + Vector2(-60, 0)))
	mobs = MobRenderer.new()
	map.actor_layer(layer).add_child(mobs)
	drops = PickupRenderer.new()
	map.actor_layer(layer).add_child(drops)
	shots = ProjectileRenderer.new()
	map.actor_layer(7).add_child(shots)
	fx = FxRenderer.new()
	map.actor_layer(7).add_child(fx)
	# Effects with a negative WZ z (JobChanged) draw behind the character.
	var fx_back := FxRenderer.new()
	fx_back.name = "FxBehind"
	map.actor_layer(layer).add_child(fx_back)
	map.actor_layer(layer).move_child(fx_back, 0)
	fx.behind = fx_back
	numbers = DamageNumbers.new()
	map.actor_layer(7).add_child(numbers)
	tags = NameTags.new()
	map.actor_layer(7).add_child(tags)
	var n_perf := int(args.get("mobs", "0"))
	if n_perf > 0:
		_setup_perf_mobs(n_perf)
	elif str(args.get("demo", "1")) != "0":
		_setup_demo()
	if args.has("gallery"):
		_setup_gallery(c)
	if str(args.get("hud", "1")) != "0":
		hud = Hud.new()
		add_child(hud)
		hud.update(_sample_player(), _sample_run())
	if str(args.get("bgm", "1")) != "0":
		var bgm := str(map.map_root.get("info", {}).get("bgm", ""))
		var sfx := get_node_or_null("/root/Sfx") as AudioService
		if sfx != null and bgm != "":
			print("map_viewer: bgm %s -> %s" % [bgm, sfx.play_bgm(bgm, 0.5)])
	if args.has("checker"):
		_add_checker()
	_last_us = Time.get_ticks_usec()
	if args.has("pan"):
		RenderingServer.frame_pre_draw.connect(_check_sync)


func _process(delta: float) -> void:
	_frame += 1
	_time += delta
	var now := Time.get_ticks_usec()
	var frame_us := now - _last_us
	_last_us = now
	var move := Vector2(Input.get_axis("move_left", "move_right"), Input.get_axis("move_up", "move_down"))
	if args.has("pan"):
		# Smoothed follow of a target that sweeps back and forth (camera/background sync check in motion).
		cam.anchor_y = CameraRig.ANCHOR_Y
		cam.target_pos = _pan_origin + Vector2(sin(_time * 1.3) * 500.0, cos(_time * 0.9) * 150.0)
	elif move != Vector2.ZERO:
		cam.target_pos = CameraRig.clamp_center(cam.target_pos + move * _cam_speed * delta, cam.bounds, cam.view_size())
		cam.snap_next = true
	var r0 := Time.get_ticks_usec()
	_animate_character(delta)
	if _swarm != null:
		_step_swarm(delta)
		var m0 := Time.get_ticks_usec()
		mobs.update_from(_swarm, _kind_ids)
		_mob_us += Time.get_ticks_usec() - m0
		if not _elite.is_empty():
			tags.update_from(_swarm, _elite, _kind_names)
	if _proj != null:
		_step_projectiles(delta)
		shots.update_from(_proj, _visuals, delta)
	if _picks != null:
		drops.update_from(_picks, delta)
	if _gallery_mobs != null:
		_step_gallery(delta)
	_demo_events(delta)
	if hud != null and _frame % 6 == 0:
		hud.update(_sample_player(), _sample_run())
	var r1 := Time.get_ticks_usec()
	_perf(frame_us, r1 - r0)
	var frames := int(args.get("frames", "30"))
	if args.has("shot") and _frame == frames:
		_take_shots()
	elif args.has("quit") and _frame >= int(args.quit):
		get_tree().quit()


# --- character -----------------------------------------------------------------------------------------------

func _setup_character(want: Vector2) -> int:
	var p := _floor_point(want)
	_char_home = p
	avatar = AvatarRenderer.new()
	var layer := _floor_layer(p)
	map.actor_layer(layer).add_child(avatar)
	avatar.position = p
	avatar.set_look({})
	if args.has("stance"):
		avatar.play(str(args.stance))
	avatar.set_facing(int(args.get("facing", "-1")))
	print("map_viewer: character at %s on layer %d stances missing=%s parts missing=%s" % [p, layer,
		avatar.missing, avatar.missing])
	return layer


func _animate_character(delta: float) -> void:
	avatar.advance(delta)
	for a: AvatarRenderer in _gallery:
		a.advance(delta)
	if args.has("stance") or args.has("char_static"):
		return
	# Walk 2 s one way, stand 1 s, walk back, stand: a simple loop around the start point.
	var t := fposmod(_time, 6.0)
	var dir := 0
	if t < 2.0:
		dir = 1
	elif t >= 3.0 and t < 5.0:
		dir = -1
	if dir != 0:
		avatar.play("walk1")
		avatar.set_facing(dir)
		var p := avatar.position + Vector2(dir * 60.0 * delta, 0)
		avatar.position = _floor_point(Vector2(p.x, avatar.position.y - 20))
	else:
		avatar.play("stand1")


# --- mobs ----------------------------------------------------------------------------------------------------

func _setup_demo() -> void:
	var c := cam.target_pos
	var n := DEMO_MOBS.size()
	_new_swarm(n)
	var xs: PackedFloat32Array = _swarm.fields.x
	var ys: PackedFloat32Array = _swarm.fields.y
	var kinds: PackedInt32Array = _swarm.fields.kind
	var facing: PackedInt32Array = _swarm.fields.facing
	var states: PackedInt32Array = _swarm.fields.state
	var alpha: PackedFloat32Array = _swarm.fields.alpha
	for i in n:
		_kind_ids.append(DEMO_MOBS[i])
		var p := _floor_point(c + Vector2(-200 + i * 55, -40))
		xs[i] = p.x
		ys[i] = p.y
		kinds[i] = i
		facing[i] = -1 if i % 2 == 0 else 1
		states[i] = [STAND, MOVE, HIT, DIE][i % 4]
		alpha[i] = 1.0
	_swarm.fields.x = xs
	_swarm.fields.y = ys
	_swarm.fields.kind = kinds
	_swarm.fields.facing = facing
	_swarm.fields.state = states
	_swarm.fields.alpha = alpha
	# Two elites (name tags): the Slime and the Pig.
	_elite.resize(n)
	_elite.fill(0)
	_elite[4] = 1
	_elite[5] = 1
	_kind_names = NameTags.names_for(Array(_kind_ids), map.library)
	# Projectiles: Three Snails shells (levels 1-3) and an Energy Bolt rotating with its velocity.
	_visuals = [SNAIL_BALL % 1, SNAIL_BALL % 2, SNAIL_BALL % 3, BOLT_BALL]
	_proj = DebugSoA.make(4, {"active": TYPE_PACKED_BYTE_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "vx": TYPE_PACKED_FLOAT32_ARRAY, "vy": TYPE_PACKED_FLOAT32_ARRAY,
		"visual": TYPE_PACKED_INT32_ARRAY, "rotate": TYPE_PACKED_BYTE_ARRAY})
	var pa: PackedByteArray = _proj.fields.active
	var pv: PackedInt32Array = _proj.fields.visual
	var pr: PackedByteArray = _proj.fields.rotate
	for i in 4:
		pa[i] = 1
		pv[i] = i
		pr[i] = 1 if i == 3 else 0
	_proj.fields.active = pa
	_proj.fields.visual = pv
	_proj.fields.rotate = pr
	# Pickups on the floor around the character.
	var m := DEMO_ITEMS.size()
	_picks = DebugSoA.make(m, {"active": TYPE_PACKED_BYTE_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "item_id": TYPE_PACKED_INT32_ARRAY})
	var ka: PackedByteArray = _picks.fields.active
	var kx: PackedFloat32Array = _picks.fields.x
	var ky: PackedFloat32Array = _picks.fields.y
	var ki: PackedInt32Array = _picks.fields.item_id
	for i in m:
		var p := _floor_point(_char_home + Vector2(-150 + i * 40, -30))
		ka[i] = 1
		kx[i] = p.x
		ky[i] = p.y
		ki[i] = DEMO_ITEMS[i]
	_picks.fields.active = ka
	_picks.fields.x = kx
	_picks.fields.y = ky
	_picks.fields.item_id = ki


func _setup_perf_mobs(n: int) -> void:
	_new_swarm(n)
	for id: int in DEMO_MOBS:
		_kind_ids.append(id)
	var fhm := map.footholds
	var floors: PackedInt32Array = []
	for i in fhm.count():
		if fhm.is_floor(i) and fhm.x2[i] - fhm.x1[i] > 20.0:
			floors.append(i)
	var xs: PackedFloat32Array = _swarm.fields.x
	var ys: PackedFloat32Array = _swarm.fields.y
	var kinds: PackedInt32Array = _swarm.fields.kind
	var facing: PackedInt32Array = _swarm.fields.facing
	var states: PackedInt32Array = _swarm.fields.state
	var alpha: PackedFloat32Array = _swarm.fields.alpha
	var an_t: PackedFloat32Array = _swarm.fields.anim_t
	_mob_home.resize(n)
	_mob_fh.resize(n)
	var view := Rect2(cam.target_pos - cam.view_size() * 0.5, cam.view_size())
	for i in n:
		# Half of them on floors inside the starting view so they are actually drawn.
		var f := floors[_rng.randi() % floors.size()]
		for attempt in 20:
			if i % 2 == 1 or view.has_point(Vector2(fhm.x1[f], fhm.y1[f])):
				break
			f = floors[_rng.randi() % floors.size()]
		var x := _rng.randf_range(fhm.x1[f], fhm.x2[f])
		_mob_fh[i] = f
		_mob_home[i] = x
		xs[i] = x
		ys[i] = fhm.y_at(f, x)
		kinds[i] = i % DEMO_MOBS.size()
		facing[i] = -1 if _rng.randf() < 0.5 else 1
		states[i] = MOVE
		alpha[i] = 1.0
		an_t[i] = _rng.randf() * 2.0
	_swarm.fields.x = xs
	_swarm.fields.y = ys
	_swarm.fields.kind = kinds
	_swarm.fields.facing = facing
	_swarm.fields.state = states
	_swarm.fields.alpha = alpha
	_swarm.fields.anim_t = an_t


func _new_swarm(n: int) -> void:
	_swarm = DebugSoA.make(n, {"kind": TYPE_PACKED_INT32_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "state": TYPE_PACKED_INT32_ARRAY, "state_t": TYPE_PACKED_FLOAT32_ARRAY,
		"anim_t": TYPE_PACKED_FLOAT32_ARRAY, "facing": TYPE_PACKED_INT32_ARRAY, "alpha": TYPE_PACKED_FLOAT32_ARRAY})


func _step_swarm(delta: float) -> void:
	var st: PackedFloat32Array = _swarm.fields.state_t
	var an: PackedFloat32Array = _swarm.fields.anim_t
	var states: PackedInt32Array = _swarm.fields.state
	var n := st.size()
	for i in n:
		st[i] += delta
		an[i] += delta
	if not _mob_home.is_empty():
		# Perf mode: walk back and forth on the foothold (35 px/s, turn at the ends).
		var xs: PackedFloat32Array = _swarm.fields.x
		var ys: PackedFloat32Array = _swarm.fields.y
		var facing: PackedInt32Array = _swarm.fields.facing
		var fhm := map.footholds
		for i in n:
			var f := _mob_fh[i]
			var x := xs[i] + facing[i] * 35.0 * delta
			if x < fhm.x1[f] or x > fhm.x2[f]:
				facing[i] = -facing[i]
				x = clampf(x, fhm.x1[f], fhm.x2[f])
			xs[i] = x
			ys[i] = fhm.y_at(f, x)
		_swarm.fields.x = xs
		_swarm.fields.y = ys
		_swarm.fields.facing = facing
	else:
		# Demo: every mob cycles stand -> move -> hit1 -> die1 (each state 1.6 s, die then respawns).
		for i in n:
			if st[i] >= 1.6:
				st[i] = 0.0
				an[i] = 0.0
				states[i] = [STAND, MOVE, HIT, DIE][([STAND, MOVE, HIT, DIE].find(states[i]) + 1) % 4]
		_swarm.fields.state = states
	_swarm.fields.state_t = st
	_swarm.fields.anim_t = an


func _setup_gallery(c: Vector2) -> void:
	var base := _floor_point(c + Vector2(0, 40))
	for i in GALLERY_STANCES.size():
		var a := AvatarRenderer.new()
		map.actor_layer(7).add_child(a)
		a.position = Vector2(c.x - 330 + i * 72, base.y)
		a.set_look({})
		a.play(GALLERY_STANCES[i])
		_gallery.append(a)
	# Mobs: one row per state (stand, move, hit1, die1), one column per mob, above the characters.
	var n := DEMO_MOBS.size()
	_gallery_mobs = DebugSoA.make(n * 4, {"kind": TYPE_PACKED_INT32_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "state": TYPE_PACKED_INT32_ARRAY, "state_t": TYPE_PACKED_FLOAT32_ARRAY,
		"anim_t": TYPE_PACKED_FLOAT32_ARRAY, "facing": TYPE_PACKED_INT32_ARRAY, "alpha": TYPE_PACKED_FLOAT32_ARRAY})
	var xs: PackedFloat32Array = _gallery_mobs.fields.x
	var ys: PackedFloat32Array = _gallery_mobs.fields.y
	var kinds: PackedInt32Array = _gallery_mobs.fields.kind
	var states: PackedInt32Array = _gallery_mobs.fields.state
	var alpha: PackedFloat32Array = _gallery_mobs.fields.alpha
	var facing: PackedInt32Array = _gallery_mobs.fields.facing
	for row in 4:
		for col in n:
			var i := row * n + col
			xs[i] = c.x - 330 + col * 80
			ys[i] = base.y - 110 - (3 - row) * 75
			kinds[i] = col
			states[i] = [STAND, MOVE, HIT, DIE][row]
			alpha[i] = 1.0
			facing[i] = -1
	_gallery_mobs.fields.x = xs
	_gallery_mobs.fields.y = ys
	_gallery_mobs.fields.kind = kinds
	_gallery_mobs.fields.state = states
	_gallery_mobs.fields.alpha = alpha
	_gallery_mobs.fields.facing = facing
	if _kind_ids.is_empty():
		for id: int in DEMO_MOBS:
			_kind_ids.append(id)
	var gm := MobRenderer.new()
	gm.name = "GalleryMobs"
	map.actor_layer(7).add_child(gm)
	set_meta("gallery_renderer", gm)


func _step_gallery(delta: float) -> void:
	var st: PackedFloat32Array = _gallery_mobs.fields.state_t
	var an: PackedFloat32Array = _gallery_mobs.fields.anim_t
	var states: PackedInt32Array = _gallery_mobs.fields.state
	for i in st.size():
		an[i] += delta
		# Freeze hit1/die1 at a representative moment (die1 mid-way) instead of letting them end.
		st[i] = 0.15 if states[i] == DIE else 0.0
	_gallery_mobs.fields.state_t = st
	_gallery_mobs.fields.anim_t = an
	(get_meta("gallery_renderer") as MobRenderer).update_from(_gallery_mobs, _kind_ids)


# --- projectiles, numbers, effects ---------------------------------------------------------------------------

func _step_projectiles(_delta: float) -> void:
	var xs: PackedFloat32Array = _proj.fields.x
	var ys: PackedFloat32Array = _proj.fields.y
	var vxs: PackedFloat32Array = _proj.fields.vx
	var vys: PackedFloat32Array = _proj.fields.vy
	for i in xs.size():
		# Shells fly left/right over the character; the bolt circles.
		var t := _time * 0.8 + i * 0.9
		if i < 3:
			var dir := 1.0 if fposmod(t, 2.0) < 1.0 else -1.0
			var k := fposmod(t, 1.0)
			xs[i] = _char_home.x + dir * (-160.0 + 320.0 * k)
			ys[i] = _char_home.y - 30.0 - i * 26.0
			vxs[i] = dir * 400.0
			vys[i] = 0.0
		else:
			xs[i] = _char_home.x + 120.0 + cos(t * 2.0) * 50.0
			ys[i] = _char_home.y - 90.0 + sin(t * 2.0) * 30.0
			vxs[i] = -sin(t * 2.0) * 100.0
			vys[i] = cos(t * 2.0) * 60.0
	_proj.fields.x = xs
	_proj.fields.y = ys
	_proj.fields.vx = vxs
	_proj.fields.vy = vys


func _demo_events(delta: float) -> void:
	if args.has("fx"):
		# Fixed sample (for evidence): LevelUp on the character, JobChanged (z -1, behind) on a second character,
		# a Three Snails hit, Energy Bolt hit and the tombstone, spawned once at frame 2.
		if _frame == 2:
			var c := _char_home
			fx.play("Effect.wz/BasicEff.img/LevelUp", Vector2.ZERO, false, avatar)
			var other := AvatarRenderer.new()
			avatar.get_parent().add_child(other)
			other.position = _floor_point(c + Vector2(170, -20))
			other.set_look({"equips": [1040002, 1060002, 1072001, 1372005]})
			fx.play("Effect.wz/BasicEff.img/JobChanged", Vector2.ZERO, false, other)
			fx.play(SNAIL_HIT, c + Vector2(-120, -20))
			fx.play("Skill.wz/200.img/skill/2001004/hit/0", c + Vector2(-200, -20), true)
			fx.play_tomb(c + Vector2(300, 0))
		return
	if args.has("messages"):
		if _frame == 2 and hud != null:
			hud.show_exp(15)
			hud.show_exp(42)
			hud.show_exp(7)
	if args.has("numbers"):
		# Fixed sample (for evidence): dealt, critical, taken, miss and a 3-line stack, spawned once at frame 2.
		if _frame == 2:
			var c := cam.target_pos
			numbers.spawn(1234, c + Vector2(-260, -120), DamageNumbers.DEALT)
			numbers.spawn(5678, c + Vector2(-60, -120), DamageNumbers.CRIT)
			numbers.spawn(56, c + Vector2(140, -120), DamageNumbers.TAKEN)
			numbers.spawn_miss(c + Vector2(290, -120), DamageNumbers.DEALT)
			for k in 3:
				numbers.spawn(17 + k * 101, c + Vector2(-160, 60), DamageNumbers.DEALT, 7)
			numbers.spawn(9, c + Vector2(60, 60), DamageNumbers.CRIT, 8)
			numbers.spawn(31, c + Vector2(60, 60), DamageNumbers.CRIT, 8)
			numbers.spawn_miss(c + Vector2(240, 60), DamageNumbers.TAKEN)
		return
	if _swarm == null or not _mob_home.is_empty():
		return
	_demo_t -= delta
	if _demo_t > 0.0:
		return
	_demo_t = 0.45
	var xs: PackedFloat32Array = _swarm.fields.x
	var ys: PackedFloat32Array = _swarm.fields.y
	var i := _rng.randi() % xs.size()
	var head := Vector2(xs[i], ys[i] - 45)
	var roll := _rng.randi() % 6
	if roll == 0:
		numbers.spawn(_rng.randi_range(100, 9999), head, DamageNumbers.CRIT, i)
	elif roll == 1:
		numbers.spawn_miss(head, DamageNumbers.DEALT, i)
	else:
		numbers.spawn(_rng.randi_range(1, 400), head, DamageNumbers.DEALT, i)
	if _rng.randi() % 3 == 0:
		fx.play(SNAIL_HIT, Vector2(xs[i], ys[i] - 15))
	if _frame % 7 == 0:
		numbers.spawn(_rng.randi_range(1, 60), avatar.position + Vector2(0, -60), DamageNumbers.TAKEN, 1000)
	if hud != null and _rng.randi() % 3 == 0:
		hud.show_exp(_rng.randi_range(3, 40))
	if fx.active_count() < 2 and _rng.randi() % 4 == 0:
		var eff := "Effect.wz/BasicEff.img/LevelUp" if _rng.randi() % 2 == 0 else "Effect.wz/BasicEff.img/JobChanged"
		fx.play(eff, Vector2.ZERO, false, avatar)
	if not has_meta("tomb"):
		set_meta("tomb", fx.play_tomb(_char_home + Vector2(90, 0)))


func _sample_player() -> Dictionary:
	return {"hp": 37, "max_hp": 50, "mp": 12, "max_mp": 25, "exp": 9, "level": 7, "job_id": 0}


func _sample_run() -> Dictionary:
	if not has_meta("job_name"):
		set_meta("job_name", _job_name(0))
	var skills: Array = [
		{"icon": "Skill.wz/000.img/skill/0001000/icon", "rank": 2},
		{"icon": "Skill.wz/200.img/skill/2001004/icon", "rank": 1},
		{"icon": "Skill.wz/200.img/skill/2001002/icon", "rank": 5},
	]
	return {"time": 123.0 + _time, "kills": 87 + int(_time), "name": "MapleHero", "job_name": get_meta("job_name"),
		"exp_next": 79, "skills": skills}


## Job name from res://data/canonical/jobs.json.
func _job_name(job_id: int) -> String:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/canonical/jobs.json"))
	if data is Dictionary:
		for j: Variant in data.get("jobs", []):
			if j is Dictionary and int(j.get("id", -1)) == job_id:
				return str(j.get("name", ""))
	return ""


# --- helpers -------------------------------------------------------------------------------------------------

func _spawn_point() -> Vector2:
	var portal: Variant = map.map_root.get("portal", {})
	if portal is Dictionary:
		for k in SpriteAnim.frame_keys(portal):
			var p: Dictionary = portal[k]
			if str(p.get("pn", "")) == "sp":
				return Vector2(float(p.x), float(p.y))
	return map.bounds.get_center()


func _floor_point(p: Vector2) -> Vector2:
	var fhm := map.footholds
	if fhm == null:
		return p
	var f := fhm.find_below(p.x, p.y - 5.0)
	if f < 0:
		f = fhm.find_below(p.x, map.bounds.position.y)
	if f < 0:
		return p
	return Vector2(roundf(p.x), roundf(fhm.y_at(f, p.x)))


func _floor_layer(p: Vector2) -> int:
	var fhm := map.footholds
	if fhm == null:
		return 0
	var f := fhm.find_below(p.x, p.y - 2.0)
	return fhm.layer[f] if f >= 0 else 0


func _add_checker() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	var n := Node2D.new()
	layer.add_child(n)
	n.draw.connect(func() -> void:
		for y in 64:
			for x in 64:
				n.draw_rect(Rect2(8 + x, 8 + y, 1, 1), Color.WHITE if (x + y) % 2 == 0 else Color.BLACK))
	n.queue_redraw()


func _perf(frame_us: int, render_us: int) -> void:
	if not args.has("perf"):
		return
	if _frame <= 60:
		return
	_perf_samples.append(frame_us / 1000.0)
	if _perf_samples.size() == 1:
		_mob_us = 0
	_render_samples.append(render_us / 1000.0)
	if _perf_samples.size() >= int(args.perf):
		var s := _perf_samples.duplicate()
		s.sort()
		var r := _render_samples.duplicate()
		r.sort()
		var avg := 0.0
		for v in s:
			avg += v
		avg /= s.size()
		var ravg := 0.0
		for v in r:
			ravg += v
		ravg /= r.size()
		print("map_viewer: perf mobs=%d visible=%d frames=%d frame avg %.2f ms p50 %.2f p95 %.2f p99 %.2f max %.2f (%.0f fps); presentation update avg %.3f ms p95 %.3f; MobRenderer.update_from avg %.3f ms; view %s" % [
			int(args.get("mobs", "0")), mobs.visible_count(), s.size(), avg, s[s.size() / 2],
			s[int(s.size() * 0.95)], s[int(s.size() * 0.99)], s[s.size() - 1], 1000.0 / avg, ravg,
			r[int(r.size() * 0.95)], _mob_us / 1000.0 / s.size(), cam.view_size()])
		get_tree().quit()


func _take_shots() -> void:
	await RenderingServer.frame_post_draw
	var path := str(args.shot)
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	var root := get_tree().root
	print("map_viewer: shot %s %dx%d err=%d cam=%s window=%s root.size=%s content_scale_size=%s stretch=%s" % [path,
		img.get_width(), img.get_height(), err, cam.global_position, DisplayServer.window_get_size(), root.size,
		root.content_scale_size, root.get_final_transform()])
	var sfx := get_node_or_null("/root/Sfx") as AudioService
	if sfx != null and sfx.current_bgm != "":
		print("map_viewer: bgm %s playing=%s position=%.2f s" % [sfx.current_bgm, sfx.bgm_playing(), sfx.bgm_position()])
	if args.has("wshot"):
		var wpos := DisplayServer.window_get_position()
		var wsize := DisplayServer.window_get_size()
		var wimg := DisplayServer.screen_get_image_rect(Rect2i(wpos, wsize))
		if wimg != null:
			wimg.save_png(str(args.wshot))
			print("map_viewer: window shot %s %dx%d at %s" % [args.wshot, wimg.get_width(), wimg.get_height(), wpos])
	get_tree().quit()


## Parses "--key=value" / "--flag" user args into a Dictionary.
static func parse_args(list: PackedStringArray) -> Dictionary:
	var out := {}
	for a in list:
		if not a.begins_with("--"):
			continue
		var s := a.substr(2)
		var i := s.find("=")
		if i < 0:
			out[s] = "1"
		else:
			out[s.substr(0, i)] = s.substr(i + 1)
	return out


## "x,y" -> Vector2 (fallback when empty or malformed).
static func parse_vec(s: String, fallback: Vector2) -> Vector2:
	var p := s.split(",")
	if p.size() != 2 or not p[0].strip_edges().is_valid_float() or not p[1].strip_edges().is_valid_float():
		return fallback
	return Vector2(float(p[0]), float(p[1]))


## --pan: right before drawing, the backgrounds must have been placed for the same camera the world is drawn with
## (MapRenderer runs after CameraRig and reads its centre; a mismatch would show as parallax jitter in motion).
func _check_sync() -> void:
	var view := get_viewport().get_visible_rect().size
	var canvas_center := -get_viewport().get_canvas_transform().origin + view * 0.5
	_sync_frames += 1
	if not map.cam_center.is_equal_approx(canvas_center) or not map.cam_center.is_equal_approx(cam.global_position):
		_sync_bad += 1
	if _sync_frames == int(args.get("pan", "300")):
		print("map_viewer: pan sync frames=%d mismatched=%d (last map centre %s, canvas centre %s)" % [_sync_frames,
			_sync_bad, map.cam_center, canvas_center])
		get_tree().quit()
