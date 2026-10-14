class_name SpriteAnim
extends RefCounted
## A WZ animation: the canvases "0", "1", ... under one node, with their delays, origins and alpha ramps.
##
## A node that is itself a canvas becomes a one-frame animation. Timing rules (docs/research/prior-art.md section 3):
## `delay` is in ms; a missing or zero delay is 100 ms (tier C: HeavenClient's default; WZ has no value); a negative
## delay (it occurs in v83, e.g. Character `magic1/0` = -900) is used by magnitude (tier C, our choice). `a0`/`a1` are
## the start/end alpha 0..255 of the frame; when only one is given the other is 255 minus it (tier C, HeavenClient).

## tier C: HeavenClient default frame delay when `delay` is missing.
const DEFAULT_DELAY := 0.1
## Canvas children that are frame properties rather than extras.
const FRAME_KEYS := ["$canvas", "origin", "delay", "a0", "a1", "z"]

var frames: Array[SpriteFrame] = []
## Sum of the frame delays in seconds.
var total := 0.0
## WZ path the animation was built from (diagnostics).
var path := ""
## Animation-level `z` child (e.g. BasicEff.img/JobChanged/z = -1: drawn behind the character); null when absent.
var z: Variant = null


## Builds an animation from a cache node (numbered canvas children, or a single canvas); empty when none.
## `rel` is the node's path inside `img`, used to follow `$uol` frames.
static func from_node(n: Variant, img: WzImg, p_path: String = "", rel: String = "") -> SpriteAnim:
	var anim := SpriteAnim.new()
	anim.path = p_path
	if not (n is Dictionary):
		return anim
	var d: Dictionary = n
	if WzImg.is_canvas(d):
		anim._add(d, img, p_path)
	else:
		var zv: Variant = d.get("z")
		if typeof(zv) == TYPE_INT or typeof(zv) == TYPE_FLOAT:
			anim.z = int(zv)
		for k in frame_keys(d):
			var child: Variant = d[k]
			if child is Dictionary and (child as Dictionary).has("$uol") and img != null:
				child = img.node(rel.path_join(k))
			if WzImg.is_canvas(child):
				anim._add(child, img, p_path + "/" + k)
	return anim


## The numbered child keys of a node ("0", "1", ...) in numeric order.
static func frame_keys(d: Dictionary) -> PackedStringArray:
	var nums: Array[int] = []
	for k: Variant in d.keys():
		var s := String(k)
		if s.is_valid_int():
			nums.append(int(s))
	nums.sort()
	var out: PackedStringArray = []
	for v in nums:
		out.append(str(v))
	return out


## Builds one frame from a canvas node (delay/alpha/extras rules above).
static func make_frame(c: Dictionary, img: WzImg, p_path: String = "") -> SpriteFrame:
	var f := SpriteFrame.new()
	f.path = p_path
	f.region = WzImg.region(c)
	if img != null:
		f.page = img.canvas_texture(c)
	f.origin = WzImg.vec(c.get("origin"))
	f.delay_s = delay_seconds(c.get("delay"))
	var has0 := _is_num(c.get("a0"))
	var has1 := _is_num(c.get("a1"))
	var v0 := float(c.get("a0")) if has0 else 255.0
	var v1 := float(c.get("a1")) if has1 else 255.0
	if has0 and not has1:
		v1 = 255.0 - v0
	elif has1 and not has0:
		v0 = 255.0 - v1
	f.a0 = clampf(v0 / 255.0, 0.0, 1.0)
	f.a1 = clampf(v1 / 255.0, 0.0, 1.0)
	f.z = c.get("z")
	for k: Variant in c.keys():
		if not (String(k) in FRAME_KEYS):
			f.extras[k] = c[k]
	return f


## WZ delay value (ms) -> seconds with the default/negative rules.
static func delay_seconds(v: Variant) -> float:
	if not _is_num(v):
		return DEFAULT_DELAY
	var ms := absf(float(v))
	if ms <= 0.0:
		return DEFAULT_DELAY
	return ms / 1000.0


## Number of frames.
func frame_count() -> int:
	return frames.size()


## True when the node had no canvases.
func is_empty() -> bool:
	return frames.is_empty()


## Total duration in seconds.
func duration() -> float:
	return total


## Index of the frame shown at time `t` (looping, or holding the last frame once finished).
func index_at(t: float, loop: bool) -> int:
	var n := frames.size()
	if n <= 1 or total <= 0.0:
		return 0
	if loop:
		t = fposmod(t, total)
	elif t >= total:
		return n - 1
	if t <= 0.0:
		return 0
	# Binary search on frame start times.
	var lo := 0
	var hi := n - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if frames[mid].start <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo


## The frame shown at time `t` (null for an empty animation).
func frame_at(t: float, loop: bool) -> SpriteFrame:
	if frames.is_empty():
		return null
	return frames[index_at(t, loop)]


## Alpha 0..1 at time `t` (the frame's a0 -> a1 ramp).
func alpha_at(t: float, loop: bool) -> float:
	if frames.is_empty():
		return 1.0
	var i := index_at(t, loop)
	var f := frames[i]
	var lt := t
	if loop and total > 0.0:
		lt = fposmod(t, total)
	return f.alpha_at(clampf(lt - f.start, 0.0, f.delay_s))


## True when a one-shot animation has played to the end at time `t`.
func finished(t: float) -> bool:
	return t >= total - 1e-6


func _add(c: Dictionary, img: WzImg, p_path: String) -> void:
	var f := make_frame(c, img, p_path)
	f.start = total
	total += f.delay_s
	frames.append(f)


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT
