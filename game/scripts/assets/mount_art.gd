class_name MountArt
extends RefCounted
## The art of one taming mob (`Character.wz/TamingMob/<id>.img`, the Corsair's Battleship 1932000, spec #384 M20): its
## stances, and per frame the two canvases it is drawn with, `tamingMobFront` (over every avatar layer) and
## `tamingMobRear` (under them), each with its own origin, `lt`/`rb` and `map/navel`, and the frame's delay.
##
## A mount stance is `<stance>/<frame>/{0, 1, delay}`: the delay sits on the frame node, not on the canvases, and the two
## canvases carry their layer in `z` (Base.wz/zmap.img sorts `tamingMobFront` in front of the avatar, `tamingMobRear`
## behind it: tier A). A stance that is a link to another one (`tired`) resolves through WzImg. A mount whose image is
## not in the cache loads as an empty MountArt (no stances), so a missing ship draws nothing instead of failing.

## Cache folder of the mount images.
const DIR := "Character.wz/TamingMob"
## The z names of the two canvases of a frame.
const FRONT_Z := "tamingMobFront"
const REAR_Z := "tamingMobRear"
## Image children that are not stances.
const NOT_STANCES := ["info", "$pages"]


## One frame of a mount stance: its two canvases (null when the frame lacks that layer) and its time.
class Frame:
	extends RefCounted
	var front: SpriteFrame
	var rear: SpriteFrame
	var delay_s := SpriteAnim.DEFAULT_DELAY
	## Time at which the frame starts inside its stance, seconds.
	var start := 0.0

	## The canvas' `map/navel` relative to its own origin (ZERO without one).
	static func navel(f: SpriteFrame) -> Vector2:
		if f == null:
			return Vector2.ZERO
		var m: Variant = f.extras.get("map")
		return WzImg.vec(m.get("navel")) if m is Dictionary else Vector2.ZERO

	## True when the frame draws something.
	func has_art() -> bool:
		return front != null or rear != null


## The taming mob id (0 for an empty result).
var id := 0
## Image path inside the cache.
var path := ""
## stance name -> Array[Frame].
var stances: Dictionary = {}
## stance name -> total seconds.
var durations: Dictionary = {}


## `Character.wz/TamingMob/<id as 8 digits>.img`.
static func img_path(mount_id: int) -> String:
	return "%s/%08d.img" % [DIR, mount_id]


## Loads mount `mount_id` through the library; empty (see is_empty) when the image is not in the cache.
static func load_mount(lib: AssetLibrary, mount_id: int) -> MountArt:
	var w := lib.img(img_path(mount_id)) if lib != null and mount_id > 0 else null
	return from_img(w, mount_id)


## Builds the art of an already loaded image (synthetic images in tests); empty for null.
static func from_img(w: WzImg, mount_id: int = 0) -> MountArt:
	var art := MountArt.new()
	art.id = mount_id
	art.path = img_path(mount_id) if w == null else w.path
	if w == null:
		return art
	for k: Variant in w.root.keys():
		var name := String(k)
		if name in NOT_STANCES:
			continue
		var node: Variant = w.node(name)
		if not (node is Dictionary):
			continue
		var frames := _frames(w, name, node)
		if frames.is_empty():
			continue
		art.stances[name] = frames
		art.durations[name] = (frames.back() as Frame).start + (frames.back() as Frame).delay_s
	return art


## True when the image had no usable stance.
func is_empty() -> bool:
	return stances.is_empty()


## True when the mount has art for the stance.
func has_stance(stance: String) -> bool:
	return stances.has(stance)


## The stance names, in image order.
func stance_names() -> PackedStringArray:
	return PackedStringArray(stances.keys())


## The frames of a stance (empty for an unknown one).
func frames(stance: String) -> Array:
	return stances.get(stance, [])


## Seconds a stance takes (0 for an unknown one). Agrees with WeaponInfo.frame_times on the same node.
func duration(stance: String) -> float:
	return float(durations.get(stance, 0.0))


## Index of the frame of `stance` shown `t` seconds in (looping, or holding the last frame once finished); 0 when unknown.
func index_at(stance: String, t: float, loop: bool) -> int:
	var list: Array = stances.get(stance, [])
	var n := list.size()
	var total := duration(stance)
	if n <= 1 or total <= 0.0:
		return 0
	if loop:
		t = fposmod(t, total)
	elif t >= total:
		return n - 1
	for i in range(n - 1, -1, -1):
		if (list[i] as Frame).start <= t:
			return i
	return 0


static func _frames(w: WzImg, stance: String, node: Dictionary) -> Array:
	var out: Array = []
	var t := 0.0
	for key in SpriteAnim.frame_keys(node):
		var fnode: Variant = w.node(stance.path_join(key))
		if not (fnode is Dictionary):
			continue
		var frame := Frame.new()
		for ck: Variant in (fnode as Dictionary).keys():
			var rel := stance.path_join(key).path_join(String(ck))
			var c: Variant = w.node(rel)
			if not WzImg.is_canvas(c):
				continue
			var sf := SpriteAnim.make_frame(c, w, "%s/%s" % [w.path, rel])
			if sf.z == FRONT_Z or (sf.z == null and String(ck) == "0"):
				frame.front = sf
			elif sf.z == REAR_Z or (sf.z == null and String(ck) == "1"):
				frame.rear = sf
		if not frame.has_art():
			continue
		frame.delay_s = SpriteAnim.delay_seconds((fnode as Dictionary).get("delay"))
		frame.start = t
		t += frame.delay_s
		out.append(frame)
	return out
