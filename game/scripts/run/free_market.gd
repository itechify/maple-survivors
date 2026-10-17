class_name FreeMarket
extends Node2D
## Walkable round boundary. SceneFlow owns the saved character and the next tier.
## Uses PlayerMotion/PortalSet directly, without a RunWorld, swarm, casting or round timer.

const DT := 1.0 / 60.0 # tier C: same fixed tick as RunScene.
const MAX_TICKS := 4 # tier C: same catch-up cap as RunScene.

const NOTICE_TIME := 6.0 # tier C: seconds the arrival notice stays before fading.

var snapshot: Dictionary = {}
## One-time arrival notice text ("" = none) and its label while shown.
var notice := ""
var notice_label: MapleText
var flow: SceneFlow
var library: AssetLibrary
var motion: FreeMarketMotion
var map: MapRenderer
var avatar: AvatarRenderer
var camera: CameraRig
var pause_menu: PauseMenu
var status: HudStatusBar
var npcs: Array[Dictionary] = []
var _accumulator := 0.0
var _jump_latch := false
var _leaving := false


## Supplies the saved boundary and owning flow before entering the tree.
## An arrival notice (e.g. "You have gained 140 NX.") is shown once for NOTICE_TIME seconds.
func configure(p_snapshot: Dictionary, p_flow: SceneFlow, p_notice: String = "") -> void:
	snapshot = p_snapshot.duplicate(true)
	flow = p_flow
	notice = p_notice


func _ready() -> void:
	if library == null:
		library = AssetLibrary.get_default()
	map = MapRenderer.new()
	map.library = library
	add_child(map)
	if not map.load_map(FreeMarketMotion.MAP_ID):
		var layer := CanvasLayer.new()
		add_child(layer)
		layer.add_child(MapleText.new("Free Market assets are missing. Reimport your v83 data.", MapleText.SIZE, MapleText.WHITE))
		return
	var data := DataRepo.load_all()
	var physics := library.img(DataRepo.PHYSICS_IMG)
	motion = FreeMarketMotion.new(map.map_root, physics.root if physics != null else {}, data.balance)
	var character: Dictionary = snapshot.get("character", {})
	var loadout := _boundary_loadout(character, data)
	motion.player.speed_stat = roundi(loadout.player_stat("speed", 100.0))
	_build_npcs()
	avatar = AvatarRenderer.new()
	avatar.library = library
	# Configure before entering the tree, so _ready never loads a different default outfit first.
	avatar.set_look(character_look(character, data))
	map.actor_layer(_player_layer()).add_child(avatar)
	_add_name_tag(avatar, String(snapshot.get("name", "")))
	camera = CameraRig.new()
	camera.bounds = motion.bounds
	camera.target = avatar
	add_child(camera)
	camera.make_current()
	map.camera = camera
	_build_hud(character, data, loadout)
	_present(0.0)
	var sfx := get_node_or_null("/root/Sfx") as AudioService
	if sfx != null:
		sfx.play_bgm(String(map.map_root.get("info", {}).get("bgm", "")))


func _process(delta: float) -> void:
	if motion == null or _leaving or pause_menu.is_open():
		return
	_accumulator = minf(_accumulator + delta, DT * MAX_TICKS)
	while _accumulator >= DT and not _leaving:
		var input := MoveInput.make(Input.is_action_pressed("move_left"), Input.is_action_pressed("move_right"),
			Input.is_action_pressed("move_up"), Input.is_action_pressed("move_down"), _jump_latch,
			Input.is_action_pressed("jump"))
		_jump_latch = false
		_accumulator -= DT
		step_input(DT, input)
	if not _leaving:
		_present(delta)


## Advances one fixed tick with the same movement intent as a round; out00 enters the next map select.
func step_input(dt: float, input: MoveInput) -> void:
	if motion == null or _leaving or (pause_menu != null and pause_menu.is_open()):
		return
	for event: Dictionary in motion.step(dt, input):
		if event.type == "exit_requested" and flow != null:
			_leaving = true
			flow.goto_stage_select()
			return
		if event.type == "portal_used" and camera != null:
			camera.snap_to(motion.player.pos)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		_jump_latch = true
	if MapleWindow.is_cancel(event) and pause_menu != null and not pause_menu.is_open():
		open_pause()
		get_viewport().set_input_as_handled()


## Opens the boundary pause menu; motion holds until Resume or Save & quit.
func open_pause() -> void:
	_jump_latch = false
	_accumulator = 0.0
	pause_menu.open()


## All failed lookups used by the hub, including animations and audio, without duplicates.
func missing_paths() -> PackedStringArray:
	var out := PackedStringArray()
	var lists := [library.missing if library != null else PackedStringArray(),
		map.missing if map != null else PackedStringArray(), avatar.missing if avatar != null else PackedStringArray()]
	for list: PackedStringArray in lists:
		for path: String in list:
			if not path in out:
				out.append(path)
	return out


## Uses the shared character look and current job weapon without mutating the snapshot.
static func character_look(character: Dictionary, data: Dictionary) -> Dictionary:
	return DataRepo.character_look(character, data)


static func _boundary_loadout(character: Dictionary, data: Dictionary) -> Loadout:
	var loadout := Loadout.new(SkillBook.from_data(data.skills, {}))
	CharacterSnapshot.restore_loadout(character, loadout)
	return loadout


func _build_hud(character: Dictionary, data: Dictionary, loadout: Loadout) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	status = HudStatusBar.new()
	status.library = library
	layer.add_child(status)
	var hp := maxi(1, roundi(loadout.player_stat("max_hp", float(character.get("base_hp", 1)))))
	var mp := maxi(0, roundi(loadout.player_stat("max_mp", float(character.get("base_mp", 0))
		+ float(character.get("job_mp", 0))) * (1.0 + loadout.passive_total(Loadout.MAX_MP_PERCENT))))
	var level := int(character.get("level", 1))
	var curve := ExpCurve.from_data(data.balance.get("exp_curve", {}))
	status.update({"level": level, "exp": int(character.get("exp", 0)), "hp": hp, "mp": mp, "max_hp": hp, "max_mp": mp},
		{"name": snapshot.get("name", ""), "job_name": JobTree.from_data(data.jobs, {}).name_of(int(character.get("job_id", 0))),
		"exp_next": curve.exp_to_next(level)})
	var help := MapleText.new("Free Market  /  Up at the exit: next map  /  Esc: Save & quit", MapleText.SIZE, MapleText.WHITE, true)
	help.position = Vector2(12, 12) # tier C: hub instruction inset in logical pixels.
	var plate := StyleBoxFlat.new()
	plate.bg_color = NameTags.BOX_COLOR
	plate.content_margin_left = NameTags.PAD_X
	plate.content_margin_right = NameTags.PAD_X
	plate.content_margin_top = NameTags.GAP_Y
	plate.content_margin_bottom = NameTags.GAP_Y
	help.add_theme_stylebox_override("normal", plate)
	layer.add_child(help)
	if notice != "":
		notice_label = MapleText.new(notice, MapleText.SIZE, Color8(255, 255, 102), true)
		notice_label.position = Vector2(12, 38) # tier C: under the hub instruction line.
		notice_label.add_theme_stylebox_override("normal", plate)
		layer.add_child(notice_label)
		var fade := create_tween()
		fade.tween_interval(NOTICE_TIME)
		fade.tween_property(notice_label, "modulate:a", 0.0, 1.0)
		fade.tween_callback(notice_label.queue_free)
	pause_menu = PauseMenu.new()
	pause_menu.boundary_mode = true
	pause_menu.quit_requested.connect(func() -> void:
		if flow != null:
			_leaving = true
			flow.save_and_quit())
	layer.add_child(pause_menu)


func _build_npcs() -> void:
	# tier C: owner #71 draws all four NPCs, including the hidden Maple TV; none accepts interactions.
	for life: Dictionary in map.map_root.get("life", {}).values():
		if String(life.get("type", "")) != "n":
			continue
		var id := int(life.id)
		var pos := Vector2(float(life.x), float(life.get("cy", life.y)))
		var floor := motion.fhm.find_below(pos.x, pos.y - FootholdMap.EPS)
		var layer := int(motion.fhm.layer[floor]) if floor >= 0 else 0
		var sprite := MapDrawList.new()
		sprite.animated = true
		var anim := library.anim("Npc.wz/%07d.img/stand" % id)
		if anim.is_empty():
			sprite.free()
			continue
		sprite.position = pos.round()
		sprite.add(anim, Vector2.ZERO, int(life.get("f", 0)) != 0)
		map.actor_layer(layer).add_child(sprite)
		_add_name_tag(sprite, library.string_name("Npc", id))
		npcs.append({"id": id, "sprite": sprite})


func _add_name_tag(parent: Node2D, text: String) -> void:
	var tag := Node2D.new()
	var font := Hud.make_font()
	parent.add_child(tag)
	tag.draw.connect(func() -> void:
		var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, NameTags.FONT_SIZE).x
		var box := NameTags.box_rect(Vector2.ZERO, width)
		tag.draw_rect(box, NameTags.BOX_COLOR)
		tag.draw_string(font, box.position + Vector2(NameTags.PAD_X, font.get_ascent(NameTags.FONT_SIZE)), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, NameTags.FONT_SIZE, NameTags.TEXT_COLOR))


func _player_layer() -> int:
	var fh := motion.player.fh
	if fh < 0:
		fh = motion.fhm.find_below(motion.player.pos.x, motion.player.pos.y)
	return int(motion.fhm.layer[fh]) if fh >= 0 else 0


func _present(delta: float) -> void:
	var parent := map.actor_layer(_player_layer())
	if avatar.get_parent() != parent:
		avatar.reparent(parent, false)
	avatar.position = motion.player.pos.round()
	avatar.set_facing(motion.player.facing)
	avatar.play(motion.player.stance())
	avatar.advance(delta)
	for npc: Dictionary in npcs:
		(npc.sprite as MapDrawList).advance(delta)
