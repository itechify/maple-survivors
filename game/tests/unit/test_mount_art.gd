extends TestCase
## Mount art (spec #384 M20, C12 #396): MountArt reads a taming-mob image's stances (two canvases per frame, `navel`, the
## frame's delay, link stances); MountLayers picks the mount stance from the avatar's request, aligns the navels and hides
## while climbing; AvatarRenderer draws rear / avatar / front, seats the rider and returns to the plain avatar when the
## mount goes; RunScene hands a form's `mount` to the avatar. Synthetic imgs first (every canvas carries a marker in its
## atlas x), then the real Battleship (Character.wz/TamingMob/01932000.img) when the cache exists (SKIP otherwise).

const BODY := 2000
const HEAD := 12000
const FACE := 20000
const HAIR := 30030
const MOUNT := 7777
const ZMAP := ["tamingMobFront", "hair", "face", "head", "body", "tamingMobRear"]
const SHIP := 1932000
## Atlas x markers: a front canvas of frame i is FRONT + i, a rear canvas REAR + i, the body BODY_MARK + stance index.
const FRONT := 100
const REAR := 200


class FakeLibrary:
	extends AssetLibrary
	var images := {}

	func img(path: String) -> WzImg:
		return images.get(path)


var lib: FakeLibrary
var avatar: AvatarRenderer


func before_each() -> void:
	lib = FakeLibrary.new()
	var zmap := {}
	for z in ZMAP:
		zmap[z] = null
	lib.images["Base.wz/zmap.img"] = WzImg.new("synthetic", zmap)
	lib.images["Base.wz/smap.img"] = WzImg.new("synthetic", {"body": "Bd", "head": "Hd", "face": "Fc", "hair": "H2"})
	var body := {}
	for s in ["stand1", "walk1", "jump", "prone", "alert", "shoot1", "cannon", "torpedo", "fireburner", "coolingeffect", "ladder", "swingO1"]:
		body[s] = {"0": {"body": _body(1, Vector2(-8, -21))}}
	body["sit"] = {"0": {"body": _body(2, Vector2(-2, -17)), "arm": _body(3, Vector2(-4, 2))}}
	body["ladder"]["0"]["face"] = 0
	lib.images[AvatarRenderer.part_img_path(BODY)] = WzImg.new("synthetic", body)
	lib.images[AvatarRenderer.part_img_path(HEAD)] = WzImg.new("synthetic", {"front": {"head": _c("head", 5)}})
	lib.images[AvatarRenderer.part_img_path(FACE)] = WzImg.new("synthetic", {"default": {"face": _c("face", 6)}})
	lib.images[AvatarRenderer.part_img_path(HAIR)] = WzImg.new("synthetic", {"default": {"hair": _c("hair", 7)}})
	lib.images[MountArt.img_path(MOUNT)] = WzImg.new("synthetic", _mount_tree())
	avatar = AvatarRenderer.new()
	avatar.library = lib
	avatar.set_look({"skin": 0, "face": FACE, "hair": HAIR, "equips": []})


func after_each() -> void:
	avatar.free()
	lib.free()


func _c(z: String, marker: int) -> Dictionary:
	return {"$canvas": [0, marker, 0, 4, 4], "origin": {"$v": [0, 0]}, "z": z}


func _body(marker: int, navel: Vector2) -> Dictionary:
	var c := _c("body", marker)
	c["map"] = {"navel": {"$v": [navel.x, navel.y]}}
	return c


## A mount frame: the front canvas (origin 30,48), the rear canvas (origin 36,116), each with a navel, and the frame delay.
func _frame(i: int, navel: Vector2, delay: int) -> Dictionary:
	var m := {"navel": {"$v": [navel.x, navel.y]}}
	return {
		"0": {"$canvas": [0, FRONT + i, 0, 67, 38], "origin": {"$v": [30, 48]}, "map": m, "z": "tamingMobFront"},
		"1": {"$canvas": [0, REAR + i, 0, 88, 113], "origin": {"$v": [36, 116]}, "map": m.duplicate(true), "z": "tamingMobRear"},
		"delay": delay}


func _stance(delays: Array, navel_y_drift: int = 1) -> Dictionary:
	var out := {}
	for i in delays.size():
		out[str(i)] = _frame(i, Vector2(6, -38 - i * navel_y_drift), int(delays[i]))
	return out


func _mount_tree() -> Dictionary:
	return {
		"info": {"tamingMob": 4, "icon": {"$canvas": [0, 1, 1, 4, 4], "origin": {"$v": [0, 0]}}},
		"stand1": _stance([200, 300, 200]), "walk1": _stance([100, 100]), "jump": _stance([100, 100], 0),
		"prone": _stance([150]), "alert2": _stance([100, 100]),
		"cannon": _stance([130, 130, 130]), "torpedo": _stance([80, 50, 60, 110]),
		"fireburner": _stance([100, 100]), "coolingeffect": _stance([100, 100]),
		"tired": {"$uol": "stand1"}}


func _drive(request: String, seconds: float = 0.0, restart: bool = true) -> void:
	avatar.play(request, restart, false)
	if seconds > 0.0:
		avatar.advance(seconds)


# --- MountArt --------------------------------------------------------------------------------------------------------

func test_mount_art_reads_both_canvases_navel_and_the_frame_delay() -> void:
	var art := MountArt.load_mount(lib, MOUNT)
	assert_false(art.is_empty())
	assert_true(art.has_stance("stand1"))
	assert_false(art.has_stance("info"), "`info` is metadata, not a stance")
	var frames := art.frames("stand1")
	assert_eq(frames.size(), 3)
	var f: MountArt.Frame = frames[1]
	assert_eq(int(f.front.region.position.x), FRONT + 1, "the front canvas is the tamingMobFront one")
	assert_eq(int(f.rear.region.position.x), REAR + 1, "the rear canvas is the tamingMobRear one")
	assert_eq(f.front.origin, Vector2(30, 48))
	assert_eq(f.rear.origin, Vector2(36, 116))
	assert_eq(MountArt.Frame.navel(f.front), Vector2(6, -39), "each canvas keeps its own navel")
	assert_eq(MountArt.Frame.navel(f.rear), Vector2(6, -39))
	assert_near(f.delay_s, 0.3, 1e-9, "the delay sits on the frame node, not on the canvases")
	assert_near(f.start, 0.2, 1e-9)
	assert_near((frames[2] as MountArt.Frame).start, 0.5, 1e-9)


func test_mount_art_durations_agree_with_weapon_info_frame_times() -> void:
	var art := MountArt.load_mount(lib, MOUNT)
	var w: WzImg = lib.images[MountArt.img_path(MOUNT)]
	for s in ["stand1", "walk1", "cannon", "torpedo", "fireburner"]:
		assert_near(art.duration(s), float(WeaponInfo.frame_times(w.root[s]).total), 1e-9, s)
	assert_near(art.duration("torpedo"), 0.3, 1e-9)


func test_mount_art_resolves_a_link_stance() -> void:
	var art := MountArt.load_mount(lib, MOUNT)
	assert_true(art.has_stance("tired"), "`tired` links to stand1")
	assert_eq(art.frames("tired").size(), 3)
	assert_near(art.duration("tired"), art.duration("stand1"), 1e-9)


func test_mount_art_frame_lookup_loops_or_holds() -> void:
	var art := MountArt.load_mount(lib, MOUNT)
	assert_eq(art.index_at("stand1", 0.0, true), 0)
	assert_eq(art.index_at("stand1", 0.25, true), 1)
	assert_eq(art.index_at("stand1", 0.55, true), 2)
	assert_eq(art.index_at("stand1", 0.75, true), 0, "wraps after 0.7 s")
	assert_eq(art.index_at("stand1", 5.0, false), 2, "a one-shot holds its last frame")
	assert_eq(art.index_at("nope", 1.0, true), 0)


func test_a_missing_mount_loads_empty_and_safe() -> void:
	var art := MountArt.load_mount(lib, 424242)
	assert_true(art.is_empty())
	assert_eq(art.frames("stand1"), [])
	assert_eq(art.duration("stand1"), 0.0)
	assert_eq(art.index_at("stand1", 1.0, true), 0)
	assert_true(MountArt.load_mount(null, MOUNT).is_empty())
	assert_true(MountArt.load_mount(lib, 0).is_empty())
	assert_eq(MountArt.img_path(1932000), "Character.wz/TamingMob/01932000.img")


# --- MountLayers: stance choice ---------------------------------------------------------------------------------------

func test_the_mount_stance_follows_motion_and_the_named_casts() -> void:
	for pair: Array in [["stand1", "stand1"], ["stand2", "stand1"], ["walk1", "walk1"], ["walk2", "walk1"], ["jump", "jump"],
			["prone", "prone"], ["cannon", "cannon"], ["torpedo", "torpedo"], ["fireburner", "fireburner"],
			["coolingeffect", "coolingeffect"], ["alert", "alert2"], ["shoot1", "alert2"], ["swingO1", "alert2"]]:
		assert_eq(MountLayers.mount_stance(pair[0]), pair[1], "request %s" % pair[0])
	for s in ["ladder", "rope", "ladder2", "rope2", "dead"]:
		assert_eq(MountLayers.mount_stance(s), "", "%s hides the mount" % s)


func test_the_rider_sits_except_in_the_named_casts() -> void:
	for s in ["stand1", "walk1", "jump", "prone", "alert", "shoot1", "swingO1", "doublefire"]:
		assert_eq(MountLayers.rider_stance(s), "sit", s)
	for s in ["cannon", "torpedo", "fireburner", "coolingeffect", "ladder", "rope", "dead"]:
		assert_eq(MountLayers.rider_stance(s), s, "%s keeps its own body action" % s)


func test_layers_play_loop_hold_and_rewind() -> void:
	var layers := MountLayers.new(MountArt.load_mount(lib, MOUNT))
	assert_false(layers.is_visible(), "nothing is drawn before a stance is asked")
	assert_true(layers.request("stand1"))
	assert_eq(layers.stance, "stand1")
	assert_eq(layers.index_of_frame(), 0)
	assert_true(layers.advance(0.25))
	assert_eq(layers.index_of_frame(), 1)
	layers.advance(0.5)
	assert_eq(layers.index_of_frame(), 0, "stand1 loops")
	assert_false(layers.request("stand1"), "the same stance keeps its clock")
	layers.request("cannon")
	layers.advance(10.0)
	assert_eq(layers.index_of_frame(), 2, "a cast holds its last frame")
	assert_true(layers.request("cannon", true), "the same cast begun again rewinds")
	assert_eq(layers.index_of_frame(), 0)
	assert_eq(layers.time, 0.0)


func test_layers_hide_while_climbing_and_for_a_stance_the_mount_lacks() -> void:
	var layers := MountLayers.new(MountArt.load_mount(lib, MOUNT))
	layers.request("stand1")
	assert_true(layers.is_visible())
	layers.request("ladder")
	assert_false(layers.is_visible())
	assert_false(layers.advance(1.0))
	layers.request("stand1")
	assert_true(layers.is_visible(), "back from the ladder")
	lib.images[MountArt.img_path(8888)] = WzImg.new("synthetic", {"stand1": _stance([100])})
	var small := MountLayers.new(MountArt.load_mount(lib, 8888))
	small.request("walk1")
	assert_false(small.is_visible(), "no walk1 art: hidden, not another stance")
	assert_false(MountLayers.new().is_visible(), "an empty mount draws nothing")


# --- MountLayers: alignment -------------------------------------------------------------------------------------------

func test_the_rider_origin_is_the_mount_navel_minus_the_body_navel() -> void:
	var layers := MountLayers.new(MountArt.load_mount(lib, MOUNT))
	layers.request("stand1")
	layers.layout(Vector2(-2, -17))
	assert_eq(layers.front_pos, Vector2.ZERO, "the front canvas sits on the mount's origin")
	assert_eq(layers.rider_offset, Vector2(8, -21), "(6, -38) - (-2, -17): the ship's stand1 numbers")
	layers.advance(0.25)
	layers.layout(Vector2(-2, -17))
	assert_eq(layers.rider_offset, Vector2(8, -22), "the navel drifts with the bobbing, read per frame")
	layers.layout(Vector2(-4, 2))
	assert_eq(layers.rider_offset, Vector2(10, -41))


func test_each_canvas_is_placed_by_its_own_navel() -> void:
	var tree := {"stand1": {"0": {
		"0": {"$canvas": [0, 1, 0, 10, 10], "origin": {"$v": [5, 5]}, "map": {"navel": {"$v": [6, -38]}}, "z": "tamingMobFront"},
		"1": {"$canvas": [0, 2, 0, 10, 10], "origin": {"$v": [5, 5]}, "map": {"navel": {"$v": [9, -36]}}, "z": "tamingMobRear"},
		"delay": 100}}}
	lib.images[MountArt.img_path(8889)] = WzImg.new("synthetic", tree)
	var layers := MountLayers.new(MountArt.load_mount(lib, 8889))
	layers.request("stand1")
	layers.layout(Vector2.ZERO)
	assert_eq(layers.front_pos, Vector2.ZERO)
	assert_eq(layers.rear_pos, Vector2(-3, -2), "front navel (6, -38) - rear navel (9, -36): the navels meet")
	assert_eq(layers.rider_offset, Vector2(6, -38))


func test_body_navel_is_the_body_canvas_anchor() -> void:
	avatar.play("sit", true)
	assert_eq(MountLayers.body_navel(avatar.current_parts()), Vector2(-2, -17))
	assert_eq(MountLayers.body_navel([]), Vector2.ZERO)


# --- AvatarRenderer: the mounted avatar -------------------------------------------------------------------------------

func _layers_of(list: Array) -> Array:
	var out: Array = []
	for item: Dictionary in list:
		if out.is_empty() or out.back() != item.layer:
			out.append(item.layer)
	return out


func test_the_mounted_draw_list_is_rear_then_avatar_then_front() -> void:
	avatar.set_mount(MOUNT)
	avatar.play("stand1", true)
	var layers := avatar.visible_mount()
	assert_true(layers != null)
	var list := avatar.mounted_draw_list(avatar.current_parts(), layers)
	assert_eq(_layers_of(list), ["mount_rear", "avatar", "mount_front"])
	assert_eq(int(list[0].frame.region.position.x), REAR)
	assert_eq(int(list.back().frame.region.position.x), FRONT)
	assert_eq(list.size(), avatar.current_parts().size() + 2)


func test_the_rider_is_seated_at_the_navel_offset() -> void:
	avatar.set_mount(MOUNT)
	avatar.play("stand1", true)
	assert_eq(avatar.stance, "sit", "the rider sits on the mount")
	var parts := avatar.current_parts()
	var list := avatar.mounted_draw_list(parts, avatar.visible_mount())
	var body_drawn := {}
	for item: Dictionary in list:
		if item.layer == "avatar" and int(item.frame.region.position.x) == 2:
			body_drawn = item
	assert_eq(body_drawn.pos, Vector2(8, -21), "body origin = ship navel (6, -38) - sit navel (-2, -17)")
	for i in parts.size():
		assert_eq(list[i + 1].pos, parts[i].pos + Vector2(8, -21), "every part keeps its place around the body")


func test_the_avatar_asks_the_mount_for_each_stance() -> void:
	avatar.set_mount(MOUNT)
	var layers := avatar.mount_layers()
	var expected := {"stand1": ["stand1", "sit"], "walk1": ["walk1", "sit"], "jump": ["jump", "sit"], "prone": ["prone", "sit"],
		"alert": ["alert2", "sit"], "shoot1": ["alert2", "sit"], "cannon": ["cannon", "cannon"], "torpedo": ["torpedo", "torpedo"],
		"fireburner": ["fireburner", "fireburner"], "coolingeffect": ["coolingeffect", "coolingeffect"]}
	for request: String in expected:
		avatar.play(request, true, false)
		assert_eq([layers.stance, avatar.stance], expected[request], request)
	avatar.play("ladder", true)
	assert_eq(avatar.stance, "ladder", "climbing is the plain avatar's")
	assert_true(avatar.visible_mount() == null, "the mount is hidden while climbing")
	avatar.play("stand1", true)
	assert_true(avatar.visible_mount() != null)


func test_a_stance_change_moves_the_mount_without_changing_the_rider() -> void:
	avatar.set_mount(MOUNT)
	avatar.play("stand1")
	assert_eq(avatar.mount_layers().stance, "stand1")
	avatar.play("walk1")
	assert_eq(avatar.stance, "sit", "the rider stays seated")
	assert_eq(avatar.mount_layers().stance, "walk1", "the ship walks")


func test_the_mount_advances_with_the_avatar() -> void:
	avatar.set_mount(MOUNT)
	avatar.play("stand1", true)
	assert_eq(avatar.mount_layers().index_of_frame(), 0)
	avatar.advance(0.25)
	assert_eq(avatar.mount_layers().index_of_frame(), 1)


func test_facing_mirrors_the_group_not_the_layout() -> void:
	avatar.set_mount(MOUNT)
	avatar.play("stand1", true)
	avatar.set_facing(-1)
	var left := avatar.mounted_draw_list(avatar.current_parts(), avatar.visible_mount())
	avatar.set_facing(1)
	var right := avatar.mounted_draw_list(avatar.current_parts(), avatar.visible_mount())
	assert_eq(left.size(), right.size())
	for i in left.size():
		assert_eq(left[i].pos, right[i].pos, "the same unflipped layout; _draw mirrors the whole list about x = 0")


func test_no_mount_leaves_the_avatar_exactly_as_it_was() -> void:
	avatar.play("stand1", true)
	var before := _snapshot(avatar)
	assert_true(avatar.visible_mount() == null)
	avatar.set_mount(MOUNT)
	avatar.set_mount(0)
	assert_eq(avatar.mount_id, 0)
	assert_true(avatar.visible_mount() == null)
	assert_eq(avatar.stance, "stand1", "the rider stands again")
	assert_eq(_snapshot(avatar), before)
	avatar.set_mount(0)
	assert_eq(_snapshot(avatar), before)


func test_a_mount_that_is_not_in_the_cache_keeps_the_plain_avatar() -> void:
	avatar.set_mount(424242)
	assert_eq(avatar.mount_id, 0)
	assert_true(avatar.visible_mount() == null)
	assert_true(MountArt.img_path(424242) in avatar.missing)
	avatar.play("stand1", true)
	assert_eq(avatar.stance, "stand1")


func test_a_morph_hides_the_mount() -> void:
	lib.images["Morph.wz/1002.img"] = WzImg.new("synthetic", {"stand": {"0": {"$canvas": [0, 9, 0, 5, 5], "origin": {"$v": [0, 0]}}}})
	avatar.set_mount(MOUNT)
	avatar.set_morph(1002)
	assert_true(avatar.visible_mount() == null)


func _snapshot(a: AvatarRenderer) -> Array:
	var out: Array = [a.stance, a.frame_index]
	for p: Dictionary in a.current_parts():
		out.append([p.name, p.pos, int(p.frame.region.position.x)])
	return out


# --- RunScene wiring --------------------------------------------------------------------------------------------------

func test_a_form_that_names_a_mount_takes_it_and_only_its_own_end_removes_it() -> void:
	var started := RunScene.mount_after_form_event({"type": "form_started", "skill": "battleship", "mount": SHIP}, "")
	assert_eq(started, {"mount": SHIP, "skill": "battleship"})
	var other_started := RunScene.mount_after_form_event({"type": "form_started", "skill": "elemental_form"}, "battleship")
	assert_eq(other_started.mount, -1, "a form with no mount leaves the ship")
	var other_ended := RunScene.mount_after_form_event({"type": "form_ended", "skill": "elemental_form", "reason": "expired"}, "battleship")
	assert_eq(other_ended.mount, -1, "another form's end leaves the ship")
	var ended := RunScene.mount_after_form_event({"type": "form_ended", "skill": "battleship", "reason": "broken"}, "battleship")
	assert_eq(ended, {"mount": 0, "skill": ""})
	var stray := RunScene.mount_after_form_event({"type": "form_ended", "skill": "battleship"}, "")
	assert_eq(stray.mount, -1, "an end with no ship out changes nothing")


# --- The real Battleship ----------------------------------------------------------------------------------------------

func test_the_real_ship_has_every_stance_with_both_layers_and_a_navel() -> void:
	if not require_cache():
		return
	var real := AssetLibrary.get_default()
	var art := MountArt.load_mount(real, SHIP)
	if art.is_empty():
		skip("the cache has no Battleship image (import with asset_manifest.d/corsair.json)")
		return
	for s in ["stand1", "walk1", "jump", "prone", "alert2", "cannon", "torpedo", "fireburner", "coolingeffect", "tired"]:
		assert_true(art.has_stance(s), "ship stance %s" % s)
		var frames := art.frames(s)
		assert_true(frames.size() > 0, s)
		for f: MountArt.Frame in frames:
			assert_true(f.front != null and f.rear != null, "%s: both canvases" % s)
			assert_true((f.front.extras.get("map") as Dictionary).has("navel"), "%s: front navel" % s)
			assert_true((f.rear.extras.get("map") as Dictionary).has("navel"), "%s: rear navel" % s)
			assert_true(f.front.page != null and f.rear.page != null, "%s: atlas pages load" % s)
	assert_eq(art.frames("cannon").size(), 6)
	assert_eq(art.frames("torpedo").size(), 12)
	assert_near(art.duration("cannon"), 0.78, 1e-6)
	assert_near(art.duration("torpedo"), 0.99, 1e-6)
	assert_eq(art.frames("tired").size(), art.frames("stand1").size(), "the importer expands the link")


func test_the_real_ship_seats_a_real_rider_at_the_known_offset() -> void:
	if not require_cache():
		return
	var real := AssetLibrary.get_default()
	var art := MountArt.load_mount(real, SHIP)
	if art.is_empty():
		skip("the cache has no Battleship image")
		return
	var rider := AvatarRenderer.new()
	rider.library = real
	rider.set_look({"skin": 0, "face": FACE, "hair": HAIR, "equips": [1040002, 1060002, 1072001, 1492000]})
	rider.set_mount(SHIP)
	rider.play("stand1", true)
	assert_eq(rider.stance, "sit")
	var layers := rider.visible_mount()
	assert_true(layers != null)
	rider.mounted_draw_list(rider.current_parts(), layers)
	assert_eq(layers.rider_offset, Vector2(8, -21), "C1: ship (6, -38) minus the sit body (-2, -17)")
	for cast in ["cannon", "torpedo", "fireburner", "coolingeffect"]:
		rider.play(cast, true, false)
		assert_true(rider.visible_mount() != null, cast)
		assert_eq(rider.stance, cast)
	assert_eq(rider.missing, PackedStringArray())
	rider.free()
