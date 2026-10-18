extends TestCase
## AvatarRenderer's morph path (#194 of spec #168): a morph (Oak Barrel's Morph.wz/1002.img) replaces the avatar parts
## with the morph's own frame for the matching action, feet on the character origin, and the avatar returns after it.
## Synthetic imgs first (every canvas carries a marker in its atlas x), then the real v83 barrel when the cache exists.

const BODY := 2000
const HEAD := 12000
const FACE := 20000
const HAIR := 30030
const ZMAP := ["hair", "face", "head", "body"]


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
	lib.images[AvatarRenderer.part_img_path(BODY)] = WzImg.new("synthetic", {
		"stand1": {"0": {"body": _c("body", 1)}}, "walk1": {"0": {"body": _c("body", 1)}},
		"jump": {"0": {"body": _c("body", 1)}}, "ladder": {"0": {"body": _c("body", 1), "face": 0}},
		"swingO1": {"0": {"body": _c("body", 1)}}})
	lib.images[AvatarRenderer.part_img_path(HEAD)] = WzImg.new("synthetic", {"front": {"head": _c("head", 2)}})
	lib.images[AvatarRenderer.part_img_path(FACE)] = WzImg.new("synthetic", {"default": {"face": _c("face", 3)}})
	lib.images[AvatarRenderer.part_img_path(HAIR)] = WzImg.new("synthetic", {"default": {"hair": _c("hair", 5)}})
	lib.images["Morph.wz/1002.img"] = WzImg.new("synthetic", {
		"info": {"hide": 1, "speed": 100},
		"stand": {"0": _m(10, 300), "1": _m(11, 150), "2": _m(12, 300)},
		"walk": {"0": _m(20, 150), "1": _m(21, 150)},
		"jump": {"0": _m(30, -1)},
		"prone": {"0": _m(40, 3000)},
		"ladder": {"0": _m(50, 250), "1": _m(51, 250)},
		"rope": {"0": _m(60, 250)},
	})
	avatar = AvatarRenderer.new()
	avatar.library = lib
	avatar.set_look({"skin": 0, "face": FACE, "hair": HAIR, "equips": []})


func after_each() -> void:
	avatar.free()
	lib.free()


func _c(z: String, marker: int) -> Dictionary:
	return {"$canvas": [0, marker, 0, 4, 4], "origin": {"$v": [0, 0]}, "z": z}


## A Morph.wz frame: no z and no map anchors, a 55 x 70 canvas with its origin on the feet.
func _m(marker: int, delay: int) -> Dictionary:
	var frame := {"$canvas": [0, marker, 0, 55, 70], "origin": {"$v": [32, 70]}}
	if delay >= 0:
		frame["delay"] = delay
	return frame


func _markers(parts: Array) -> Array:
	var out: Array = []
	for p: Dictionary in parts:
		out.append(int(p.frame.region.position.x))
	return out


func test_the_morph_action_for_each_avatar_stance() -> void:
	for pair: Array in [["stand1", "stand"], ["stand2", "stand"], ["alert", "stand"], ["swingO1", "stand"],
			["shoot1", "stand"], ["walk1", "walk"], ["walk2", "walk"], ["jump", "jump"], ["prone", "prone"],
			["ladder", "ladder"], ["rope", "rope"], ["sit", "sit"], ["fly", "fly"]]:
		assert_eq(AvatarRenderer.morph_action(pair[0]), pair[1], "avatar %s" % pair[0])


func test_a_morph_replaces_every_avatar_part_with_one_frame_on_the_feet() -> void:
	avatar.play("stand1", true)
	assert_true(avatar.current_parts().size() > 1, "the plain avatar has body, head, face and hair")
	avatar.set_morph(1002)
	assert_eq(avatar.morph_id, 1002)
	var parts := avatar.current_parts()
	assert_eq(parts.size(), 1, "one canvas")
	assert_eq(_markers(parts), [10], "the first stand frame")
	assert_eq(parts[0].pos, Vector2.ZERO)
	assert_eq(parts[0].frame.origin, Vector2(32, 70), "the origin is the feet")
	assert_eq(avatar.stance, "stand")
	assert_eq(avatar.stance_delays("stand"), PackedFloat32Array([0.3, 0.15, 0.3]))


func test_the_morph_plays_its_own_actions_for_walking_jumping_and_climbing() -> void:
	avatar.set_morph(1002)
	avatar.play("walk1")
	assert_eq(avatar.stance, "walk")
	assert_eq(_markers(avatar.current_parts()), [20])
	avatar.advance(0.16)
	assert_eq(_markers(avatar.current_parts()), [21], "the walk frames advance on their own delays")
	avatar.play("jump")
	assert_eq(_markers(avatar.current_parts()), [30])
	avatar.play("ladder")
	assert_eq(_markers(avatar.current_parts()), [50])
	avatar.play("swingO1")
	assert_eq(avatar.stance, "stand", "an attack or cast action shows the barrel standing")
	avatar.play("sit")
	assert_eq(avatar.stance, "stand", "an action the morph lacks falls back to standing")


func test_the_avatar_returns_when_the_morph_ends() -> void:
	avatar.play("walk1", true)
	avatar.set_morph(1002)
	avatar.set_morph(0)
	assert_eq(avatar.morph_id, 0)
	assert_eq(avatar.stance, "walk1")
	var markers := _markers(avatar.current_parts())
	markers.sort()
	assert_eq(markers, [1, 2, 3, 5], "body, head, face and hair again")


func test_a_morph_missing_from_the_cache_keeps_the_avatar_and_is_listed() -> void:
	avatar.play("stand1", true)
	avatar.set_morph(9999)
	assert_true("Morph.wz/9999.img" in avatar.missing)
	assert_eq(avatar.stance, "stand1")
	assert_true(avatar.current_parts().size() > 1)


func test_a_new_look_keeps_the_morph() -> void:
	avatar.set_morph(1002)
	avatar.set_look({"skin": 0, "face": FACE, "hair": HAIR, "equips": []})
	assert_eq(avatar.current_parts().size(), 1)
	assert_eq(avatar.stance, "stand")


func test_facing_mirrors_the_morph_like_the_avatar() -> void:
	avatar.set_morph(1002)
	avatar.set_facing(1)
	assert_eq(avatar.facing, 1)
	assert_eq(avatar.current_parts().size(), 1)


## The real barrel (SKIP without the cache): every action the sim can ask for resolves to a canvas on the feet.
func test_real_v83_barrel_draws_for_each_action() -> void:
	if not require_cache():
		return
	var real := AssetLibrary.new()
	assert_true(real.open(AssetCachePaths.resolve_cache_root()))
	var real_avatar := AvatarRenderer.new()
	real_avatar.library = real
	real_avatar.set_look(AvatarRenderer.DEFAULT_LOOK)
	var plain := real_avatar.compose("stand1", 0).size()
	assert_true(plain > 1)
	real_avatar.set_morph(1002)
	assert_eq(real_avatar.morph_id, 1002)
	for pair: Array in [["stand1", "stand", 14], ["walk1", "walk", 6], ["jump", "jump", 1], ["prone", "prone", 6],
			["ladder", "ladder", 2], ["rope", "rope", 2], ["sit", "sit", 6], ["swingO1", "stand", 14]]:
		real_avatar.play(pair[0], true)
		assert_eq(real_avatar.stance, pair[1], pair[0])
		assert_eq(real_avatar.stance_delays(pair[1]).size(), pair[2], "%s frames" % pair[1])
		var parts := real_avatar.compose(real_avatar.stance, 0)
		assert_eq(parts.size(), 1, pair[0])
		if parts.size() == 1:
			assert_true(parts[0].frame.page != null, "%s has its atlas page" % pair[0])
			assert_true(parts[0].frame.origin.y > 60.0, "feet-anchored")
	real_avatar.set_morph(0)
	assert_eq(real_avatar.compose("stand1", 0).size(), plain)
	assert_true(real_avatar.missing.is_empty(), str(real_avatar.missing))
	real_avatar.free()
	real.free()
