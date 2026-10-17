class_name FreeMarket
extends Node2D
## Walkable round boundary. SceneFlow owns the saved character and the next tier.
## Uses PlayerMotion/PortalSet directly, without a RunWorld, swarm, casting or round timer.
##
## In-run windows (#108): the hub hosts the same WindowStack as a round (`ui_windows`, CanvasLayer 11) with the Equip
## (E) and Item (I) windows. They read and change the carried character through `inventory`, a map-less RunWorld
## built from the saved snapshot (the one owner of equipment rules); every change is written back into the snapshot
## and the character's save slot at once, and the drawn look and the hub's speed / jump follow. Movement holds while a
## window is open; Esc closes the front window before it opens the pause menu (handle_hotkey).
##
## Scroll shops (#111): the four scroll NPCs of shops.json (survivor data) stand on the floor (`shop_npcs`, drawn from
## Npc.wz with their String.wz names). The NPC Chat action (Space, v83's default) next to one, or a double-click on one,
## opens its ShopWindow (open_shop) in the same stack; the shop trades through `inventory` like the other windows and
## every purchase or sale is saved at once.

const DT := 1.0 / 60.0 # tier C: same fixed tick as RunScene.
const MAX_TICKS := 4 # tier C: same catch-up cap as RunScene.
## Input action -> the window it toggles (the same keys as in a round; rebindable in Settings).
const WINDOW_HOTKEYS := {"equip_window": "equip", "item_window": "item"}

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
## The character's pet (spec #34, #120), null without an owned one; it follows with the round's PetSystem.
var pet_renderer: PetRenderer
var camera: CameraRig
var pause_menu: PauseMenu
var status: HudStatusBar
## The status bar SHOP button (StatusBar.img/BtShop) that opens the Cash Shop (#118).
var shop_button: WzButton
## Transient messages above the status bar (a refused equip).
var messages: HudMessages
## The Equip / Item windows' stack (above the pause menu) and the character they work on.
var ui_windows: WindowStack
var inventory: RunWorld
## The scroll result effect above the windows (#110).
var enchant: EnchantFx
var wiring: InventoryWiring
var npcs: Array[Dictionary] = []
## The scroll NPCs (shops.json): {"id", "pos" (feet), "rect" (the drawn sprite's box), "sprite"}.
var shop_npcs: Array[Dictionary] = []
## The run options the hub honours: `autoplay` makes the bot shop once on entry (spec #33 #112, the playtest autoplay).
var options: Dictionary = {}
## The record of the autoplay shop visit ({} when none ran), see BotShop.visit.
var shop_visit: Dictionary = {}
var _data: Dictionary = {}
var _accumulator := 0.0
var _jump_latch := false
var _leaving := false


## Supplies the saved boundary, owning flow and run options before entering the tree.
## An arrival notice (e.g. "You have gained 140 NX.") is shown once for NOTICE_TIME seconds.
func configure(p_snapshot: Dictionary, p_flow: SceneFlow, p_options: Dictionary = {}, p_notice: String = "") -> void:
	snapshot = p_snapshot.duplicate(true)
	flow = p_flow
	options = p_options.duplicate()
	notice = p_notice


## The seed of the hub's scroll rolls, a pure function of the saved boundary: the run's stored seed mixed with a hash of
## the character's equipment, scrolls and mesos. The same save always rolls the same, every scroll (or purchase, sale
## or pickup) changes the next seed, and quitting and continuing cannot reroll (tier C, review of spec #33).
static func scroll_seed(p_snapshot: Dictionary) -> int:
	var character: Dictionary = p_snapshot.get("character", {})
	var state := {"equipment": character.get("equipment", {}), "scrolls": character.get("scrolls", {}),
		"mesos": int(character.get("mesos", 0))}
	return (int(p_snapshot.get("round_seed", 0)) * 1000003 + hash(JSON.stringify(state, "", true))) & 0x7FFFFFFF


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
	_data = data
	var physics := library.img(DataRepo.PHYSICS_IMG)
	motion = FreeMarketMotion.new(map.map_root, physics.root if physics != null else {}, data.balance)
	var character: Dictionary = snapshot.get("character", {})
	var loadout := _boundary_loadout(character, data)
	_apply_movement_stats(character, loadout)
	_build_npcs()
	_build_shop_npcs()
	avatar = AvatarRenderer.new()
	avatar.library = library
	var owned: Array = flow.save_data().account.owned if flow != null else []
	# Configure before entering the tree, so _ready never loads a different default outfit first.
	avatar.set_look(character_look(character, data, owned))
	var species := owned_pet(character, data, owned)
	if species > 0:
		motion.set_pet(species, data.get("cash_items", {}).get("pet", {}))
		pet_renderer = PetRenderer.new()
		pet_renderer.name = "Pet"
		pet_renderer.library = library
	map.actor_layer(_player_layer()).add_child(avatar)
	_add_name_tag(avatar, String(snapshot.get("name", "")))
	camera = CameraRig.new()
	camera.bounds = motion.bounds
	camera.target = avatar
	add_child(camera)
	camera.make_current()
	map.camera = camera
	_build_hud(character, data, loadout)
	_build_windows(character, data)
	_present(0.0)
	if options.has("spawn_x"):
		# Tool-only `--hub`: stand on the floor beside the scroll NPCs instead of the canonical arrival point.
		var spawn := float(options.spawn_x)
		var floor_fh := motion.fhm.find_below(spawn, 0.0)
		if floor_fh >= 0:
			motion.player.place(Vector2(spawn, motion.fhm.y_at(floor_fh, spawn)), motion.fhm)
			camera.snap_to(motion.player.pos)
			_present(0.0)
	if RunScene.option_flag(options, "autoplay"):
		# The playtest autoplay shops once on entry, like the headless chains between tiers (#112).
		shop_visit = bot_shop("bot", int(snapshot.get("round_seed", 0)))
	var sfx := get_node_or_null("/root/Sfx") as AudioService
	if sfx != null:
		sfx.play_bgm(String(map.map_root.get("info", {}).get("bgm", "")))


## Worn equipment's speed / jump count in the hub too, under the same v83 caps as in a round.
func _apply_movement_stats(character: Dictionary, loadout: Loadout) -> void:
	var worn: Dictionary = character.get("equipment", {}).get("worn", {})
	motion.player.speed_stat = mini(Equipment.SPEED_CAP,
		roundi(loadout.player_stat("speed", 100.0) + Equipment.total(worn, "incSpeed")))
	motion.player.jump_stat = mini(Equipment.JUMP_CAP, 100 + roundi(Equipment.total(worn, "incJump")))


func _process(delta: float) -> void:
	if motion == null or _leaving or pause_menu.is_open() or windows_open():
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
	if motion == null or _leaving or (pause_menu != null and pause_menu.is_open()) or windows_open():
		return
	for event: Dictionary in motion.step(dt, input):
		if event.type == "exit_requested" and flow != null:
			_leaving = true
			flow.goto_stage_select()
			return
		if event.type == "portal_used" and camera != null:
			camera.snap_to(motion.player.pos)
		if event.type == "pet_teleported" and pet_renderer != null:
			pet_renderer.snap()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump") and not windows_open():
		_jump_latch = true
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
		var npc := shop_npc_at(make_canvas_position_local(mb.position))
		if not npc.is_empty() and open_shop(int(npc.id)):
			get_viewport().set_input_as_handled()
			return
	if handle_hotkey(event):
		get_viewport().set_input_as_handled()


## The hub's window keys: Esc closes the front in-run window, else opens the pause menu; the Equip / Item actions
## toggle their windows (not while the pause menu is open); any other key goes to the front window. True when used.
func handle_hotkey(event: InputEvent) -> bool:
	if pause_menu == null or event.is_echo():
		return false
	if MapleWindow.is_cancel(event):
		if ui_windows != null and ui_windows.close_top():
			return true
		if not pause_menu.is_open():
			open_pause()
			return true
		return false
	if not pause_menu.is_open() and ui_windows != null:
		if InputMap.has_action("npc_chat") and event.is_action_pressed("npc_chat", false, true):
			var npc := nearest_shop_npc()
			if not npc.is_empty() and open_shop(int(npc.id)):
				return true
		for action: String in WINDOW_HOTKEYS:
			if InputMap.has_action(action) and event.is_action_pressed(action, false, true):
				ui_windows.toggle(String(WINDOW_HOTKEYS[action]))
				return true
	var top := ui_windows.top() if ui_windows != null else null
	return top != null and top.handle_key(event)


## The scroll NPC the character stands next to (within shops.json talk_range), the nearest one; {} when none.
func nearest_shop_npc() -> Dictionary:
	if motion == null:
		return {}
	var reach: Dictionary = _data.shops.talk_range
	var best := {}
	var best_dx := INF
	for npc: Dictionary in shop_npcs:
		var d: Vector2 = (npc.pos as Vector2) - motion.player.pos
		if absf(d.x) <= float(reach.x) and absf(d.y) <= float(reach.y) and absf(d.x) < best_dx: # shops.json talk_range is required
			best = npc
			best_dx = absf(d.x)
	return best


## The scroll NPC whose drawn sprite covers world point `p` ({} when none).
func shop_npc_at(p: Vector2) -> Dictionary:
	for npc: Dictionary in shop_npcs:
		if (npc.rect as Rect2).has_point(p):
			return npc
	return {}


## Opens scroll NPC `npc_id`'s shop window (the hub holds like for any window); false while the pause menu or a shop
## is open, or without a window stack or character. Talking to an NPC through a double-click works from any distance
## (tier C).
func open_shop(npc_id: int) -> bool:
	if ui_windows == null or inventory == null or pause_menu == null or pause_menu.is_open() \
			or ui_windows.find_window("shop") != null:
		return false
	var shop := ShopWindow.new(inventory, npc_id)
	shop.player_name = String(snapshot.get("name", ""))
	ui_windows.open(wiring.wire(shop))
	return true


## True while an Equip / Item / shop window is open (movement holds).
func windows_open() -> bool:
	return ui_windows != null and ui_windows.has_windows()


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
## `owned` (account item ids) decides which worn cash equipment is drawn.
static func character_look(character: Dictionary, data: Dictionary, owned: Array = []) -> Dictionary:
	return DataRepo.character_look(character, data, DataRepo.worn_cash(character, data, owned))


## The pet species the character brings that the account owns (0 = none).
static func owned_pet(character: Dictionary, data: Dictionary, owned: Array) -> int:
	return CashCatalog.from_data(data).resolve({}, int(character.get("pet", 0)), owned).pet


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
	shop_button = WzButton.new(HudWidget.SB + "BtShop")
	shop_button.name = "ShopButton"
	shop_button.fallback_size = Vector2(54, 34)
	shop_button.label = "" if shop_button.has_art() else "SHOP"
	shop_button.pressed.connect(_open_shop)
	layer.add_child(shop_button)
	get_viewport().size_changed.connect(_place_shop_button)
	_place_shop_button()
	var hp := maxi(1, roundi(loadout.player_stat("max_hp", float(character.get("base_hp", 1)))))
	var mp := maxi(0, roundi(loadout.player_stat("max_mp", float(character.get("base_mp", 0))
		+ float(character.get("job_mp", 0))) * (1.0 + loadout.passive_total(Loadout.MAX_MP_PERCENT))))
	var level := int(character.get("level", 1))
	var curve := ExpCurve.from_data(data.balance.get("exp_curve", {}))
	status.update({"level": level, "exp": int(character.get("exp", 0)), "hp": hp, "mp": mp, "max_hp": hp, "max_mp": mp},
		{"name": snapshot.get("name", ""), "job_name": JobTree.from_data(data.jobs, {}).name_of(int(character.get("job_id", 0))),
		"exp_next": curve.exp_to_next(level)})
	var help := MapleText.new("Free Market  /  Up at the exit: next map  /  Space: talk to a scroll NPC  /  Esc: Save & quit",
		MapleText.SIZE, MapleText.WHITE, true)
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
	messages = HudMessages.new()
	messages.name = "Messages"
	layer.add_child(messages)
	pause_menu = PauseMenu.new()
	pause_menu.boundary_mode = true
	pause_menu.quit_requested.connect(func() -> void:
		if flow != null:
			_leaving = true
			flow.save_and_quit())
	layer.add_child(pause_menu)


## tier C: BtShop sits left of where the run HUD puts BtMenu (744, 20), in the 800 px status bar.
const SHOP_BUTTON_POS := Vector2(688, 20)


func _place_shop_button() -> void:
	if shop_button != null:
		shop_button.position = HudWidget.bar_origin(get_viewport().get_visible_rect().size) + SHOP_BUTTON_POS


## The status bar SHOP button: opens the Cash Shop as this character; Leave comes back here.
func _open_shop() -> void:
	if flow == null or _leaving or (pause_menu != null and pause_menu.is_open()):
		return
	_leaving = true
	flow.goto_cash_shop("free_market")


## The window stack (above the pause menu's layer) with the Equip and Item windows over `inventory`, a map-less
## RunWorld of the carried character with the info of every item it holds.
func _build_windows(character: Dictionary, data: Dictionary) -> void:
	var loader := SceneFlow.equipment_info_loader(library)
	var creation := library.img(CharacterCreation.IMG)
	var infos := DataRepo.equipment_info(DataRepo.starter_equipment_ids(data, creation.root if creation != null else {},
		character), loader)
	var scroll_infos := DataRepo.scroll_info(DataRepo.scroll_item_ids(data, character), loader)
	# The account's owned items let the Equip window's Cash tab and Pet page wear and bring them out (#122).
	var owned: Array = flow.save_data().account.owned if flow != null else []
	# The scroll rolls are seeded from the saved state (scroll_seed), so a save always rolls the same and every result,
	# being saved at once, changes the next seed.
	inventory = RunWorld.new({"data": data, "equipment_info": infos, "scroll_info": scroll_infos,
		"character": character, "seed": scroll_seed(snapshot), "account": {"owned": owned}})
	var layer := CanvasLayer.new()
	layer.name = "UiWindows"
	layer.layer = RunScene.UI_LAYER
	add_child(layer)
	ui_windows = WindowStack.new()
	layer.add_child(ui_windows)
	wiring = InventoryWiring.install(ui_windows, inventory, self, library, _on_item_action,
		func(text: String) -> void: messages.push_notice("inventory", text), _play_sound)
	enchant = wiring.enchant
	ui_windows.changed.connect(func() -> void:
		if windows_open():
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_jump_latch = false
			_accumulator = 0.0)


func _play_sound(path: String) -> void:
	var sfx := get_node_or_null("/root/Sfx") as AudioService
	if sfx != null:
		sfx.play(path)


## After an Equip / Item window changed the character: the snapshot and its save slot, the drawn look, the hub's
## speed / jump and the other window follow at once.
func _on_item_action(_action: String) -> void:
	for event: Dictionary in inventory.drain_events():
		if event.type == "scroll_used":
			wiring.scroll_used(String(event.result), avatar.get_global_transform_with_canvas().origin)
	snapshot.character = inventory.character_snapshot()
	inventory.scroll_rng.seed = scroll_seed(snapshot) # the next scroll rolls from the state this action left
	var owned: Array = flow.save_data().account.owned if flow != null else []
	avatar.set_look(character_look(snapshot.character, _data, owned))
	_sync_pet(owned)
	_apply_movement_stats(snapshot.character, _boundary_loadout(snapshot.character, _data))
	for id: String in ["equip", "item", "shop"]:
		var w := ui_windows.find_window(id)
		if w != null:
			w.queue_redraw()
	if flow != null and flow.active_slot >= 0 and flow.save_data().update_slot(flow.active_slot, snapshot) != OK:
		messages.push_notice("inventory", "Could not save the character.")


## Brings the pet the character now has out beside it, swaps it for another, or puts it away (the Pet page, #122).
func _sync_pet(owned: Array) -> void:
	var species := owned_pet(snapshot.character, _data, owned)
	if species == (motion.pet.species if motion.pet != null else 0):
		return
	if species == 0:
		motion.pet = null
		if pet_renderer != null:
			pet_renderer.queue_free()
			pet_renderer = null
		return
	motion.set_pet(species, _data.get("cash_items", {}).get("pet", {}))
	if pet_renderer == null:
		pet_renderer = PetRenderer.new()
		pet_renderer.name = "Pet"
		pet_renderer.library = library
	_present_pet(0.0)


## Bot hook (spec #33, #112; autoplay and driver scenes): the character visits the scroll shops as a bot would (BotShop.visit
## with balance card policy `policy`: "bot" sensible, "random" careless), changing `inventory` through the same RunWorld
## calls as the windows and saving it like them. `seed_value` seeds the careless plan and, from its own stream, the
## scroll rolls, so the same seed gives the same purchases and results. Returns the visit record.
func bot_shop(policy := "bot", seed_value := 0) -> Dictionary:
	if inventory == null:
		return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("careless-shop-hub-%d" % seed_value)
	inventory.scroll_rng.seed = hash("scrolls-shop-hub-%d" % seed_value)
	var record := BotShop.visit(inventory, policy, rng)
	_on_item_action("bot_shop")
	return record


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
		if npc_shows_name_tag(life):
			_add_name_tag(sprite, library.string_name("Npc", id))
		npcs.append({"id": id, "sprite": sprite})


## Whether an NPC `life` entry gets a name tag: not when the map marks it hidden (v83 `hide` = 1, e.g. Maple TV).
static func npc_shows_name_tag(life: Dictionary) -> bool:
	return int(life.get("hide", 0)) == 0 # tier A: `hide` field of the map's life entry.


## Draws the scroll NPCs of shops.json standing on the floor foothold below y 0 at their x.
func _build_shop_npcs() -> void:
	for entry: Dictionary in _data.get("shops", {}).get("npcs", []):
		var id := int(entry.id)
		var x := float(entry.x)
		var floor := motion.fhm.find_below(x, 0.0)
		if floor < 0:
			continue
		var anim := library.anim("Npc.wz/%07d.img/stand" % id)
		if anim.is_empty():
			continue
		var pos := Vector2(x, motion.fhm.y_at(floor, x)).round()
		var sprite := MapDrawList.new()
		sprite.animated = true
		sprite.position = pos
		sprite.add(anim, Vector2.ZERO, true) # tier C: faces right, toward the arrival point.
		map.actor_layer(int(motion.fhm.layer[floor])).add_child(sprite)
		_add_name_tag(sprite, library.string_name("Npc", id))
		var frame: SpriteFrame = anim.frames[0]
		shop_npcs.append({"id": id, "pos": pos, "sprite": sprite,
			"rect": Rect2(pos - frame.origin, frame.region.size)})


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


## Draws the pet in the layer of the foothold it stands on (the player's while it hangs or flies), behind the avatar.
func _present_pet(delta: float) -> void:
	if pet_renderer == null:
		return
	var fh := motion.pet.motion.fh
	var layer := int(motion.fhm.layer[fh]) if fh >= 0 and motion.pet.action != "hang" else _player_layer()
	pet_renderer.show_state(motion.pet_state(), delta)
	var parent := map.actor_layer(layer)
	if pet_renderer.get_parent() != parent:
		if pet_renderer.get_parent() != null:
			pet_renderer.get_parent().remove_child(pet_renderer)
		parent.add_child(pet_renderer)
	if avatar.get_parent() == parent:
		parent.move_child(pet_renderer, avatar.get_index())
	else:
		parent.move_child(pet_renderer, 0)


func _present(delta: float) -> void:
	var parent := map.actor_layer(_player_layer())
	if avatar.get_parent() != parent:
		avatar.reparent(parent, false)
	avatar.position = motion.player.pos.round()
	avatar.set_facing(motion.player.facing)
	avatar.play(motion.player.stance())
	avatar.advance(delta)
	_present_pet(delta)
	for npc: Dictionary in npcs + shop_npcs:
		(npc.sprite as MapDrawList).advance(delta)
