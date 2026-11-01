class_name DamageNumbers
extends Node2D
## Pooled MapleStory damage numbers from Effect.wz/BasicEff.img digit sets (docs/GAME_DESIGN.md 6.3).
##
## Sets: damage dealt = NoRed1 (first digit) + NoRed0 (rest); critical = NoCri1 + NoCri0 with the NoCri1/effect burst
## behind the first digit from CRIT_EFFECT_DELAY on; damage taken = NoViolet1 + NoViolet0; misses use the set's Miss.
## Digits are placed by origin with the v95 overlap rule (layout()); the number is centred on x with the digit
## baselines (origins) on y. Timing (tier B, v95 RE): HOLD s at full alpha, then FADE s of linear fade while rising
## RISE px. Several numbers on one key (e.g. a mob slot) within STACK_WINDOW s stack upward, one line per number: a line
## sits LINE_PX above a normal number and CRIT_LINE_PX above a critical one (its digits are taller; tier C, HeavenClient
## row heights 30/36). The v95 "+30 px leading space" of critical numbers is not applied (prior-art.md section 6 does not
## say whether it is horizontal or vertical; the burst sits behind the first digit instead).
## One RenderingServer canvas item per number, recorded once at spawn; per frame only its transform and alpha change.

const DEALT := 0
const CRIT := 1
const TAKEN := 2
const HP_GAIN := 3
## HP a skill paid (HpRisk's `hp_spent`: cost or recoil), shown at the player in the red damage digits. tier C: presentation
## assignment (NoRed is the v83 set for damage dealt, NoViolet is damage taken).
const HP_SPENT := 4
## tier A: complete NoBlue recovery-shaped digit sets in v83 BasicEff; tier C: HP presentation assignment.
const SETS := {DEALT: ["NoRed1", "NoRed0"], CRIT: ["NoCri1", "NoCri0"], TAKEN: ["NoViolet1", "NoViolet0"],
	HP_GAIN: ["NoBlue1", "NoBlue0"], HP_SPENT: ["NoRed1", "NoRed0"]}
## tier C: missing recovery art falls back to green-tinted Violet digits.
const GAIN_FALLBACK_TINT := Color(0.55, 1.0, 0.55)
const BASE := "Effect.wz/BasicEff.img/"
## tier B: 400 ms hold, 600 ms fade, 30 px rise (v95 RE via Harepacker docs).
const HOLD := 0.4
const FADE := 0.6
const RISE := 30.0
## tier B: the critical burst appears about 250 ms in.
const CRIT_EFFECT_DELAY := 0.25
## tier C: stacking line height above a normal / a critical number, and the window in which a new number on the same
## key goes one line up (MAX_LINES lines, then it starts again at the bottom).
const LINE_PX := 30.0
const CRIT_LINE_PX := 36.0
const STACK_WINDOW := 0.5
const MAX_LINES := 8

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary

var _now := 0.0
var _items: Array[RID] = []
var _effects: Array[RID] = []
var _born: PackedFloat32Array = []
var _base: PackedVector2Array = []
var _crit: PackedByteArray = []
var _tint := PackedColorArray()
var _active: PackedByteArray = []
var _free: PackedInt32Array = []
var _glyphs: Dictionary = {}
## key -> [time of the last number, its stack offset px, its line, whether it was critical].
var _keys: Dictionary = {}


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_free_items()


func _free_items() -> void:
	for ci in _effects:
		RenderingServer.free_rid(ci)
	for ci in _items:
		RenderingServer.free_rid(ci)
	_items.clear()
	_effects.clear()
	_born.clear()
	_base.clear()
	_crit.clear()
	_tint.clear()
	_active.clear()
	_free.clear()


## Anchor x of each digit for glyph metrics [Vector2(width, origin_x), ...], v95 overlap rule (tier B, Harepacker's
## reading of Effect_HP): relX = acc + width - prev; acc = acc - prev + origin_x; prev = 3 (origin_x - width) / 5.
## Our reading: relX is where the digit's origin goes.
static func layout(glyphs: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var acc := 0.0
	var prev := 0.0
	for g: Vector2 in glyphs:
		out.append(acc + g.x - prev)
		acc = acc - prev + g.y
		prev = 3.0 * (g.y - g.x) / 5.0
	return out


## Digit placements of a number centred on x = 0 with origins on y = 0: [{"frame": SpriteFrame, "pos": Vector2}].
## `large`/`small` map "0".."9" (and "Miss") to frames; the first character uses `large`.
static func layout_number(text: String, large: Dictionary, small: Dictionary) -> Array:
	var tokens: PackedStringArray = []
	if text.is_valid_int():
		for i in text.length():
			tokens.append(text[i])
	else:
		tokens.append(text)
	var frames: Array = []
	for i in tokens.size():
		var ch := tokens[i]
		var f: SpriteFrame = (large if i == 0 else small).get(ch, small.get(ch))
		if f == null:
			return []
		frames.append(f)
	var metrics: Array = []
	for f: SpriteFrame in frames:
		metrics.append(Vector2(f.region.size.x, f.origin.x))
	var xs := layout(metrics)
	var lo := INF
	var hi := -INF
	for i in frames.size():
		var f: SpriteFrame = frames[i]
		lo = minf(lo, xs[i] - f.origin.x)
		hi = maxf(hi, xs[i] - f.origin.x + f.region.size.x)
	var shift := -floorf((lo + hi) * 0.5)
	var out: Array = []
	for i in frames.size():
		out.append({"frame": frames[i], "pos": Vector2(xs[i] + shift, 0.0).floor()})
	return out


## Alpha and rise (px, >= 0) of a number `age` seconds old; alpha < 0 means finished.
static func fade_at(age: float) -> Vector2:
	if age <= HOLD:
		return Vector2(1.0, 0.0)
	var k := (age - HOLD) / FADE
	if k >= 1.0:
		return Vector2(-1.0, RISE)
	return Vector2(1.0 - k, RISE * k)


## Shows a number at `pos` (mob head / player head). `kind` DEALT, CRIT, TAKEN, HP_GAIN or HP_SPENT; same `key` >= 0
## spawned within STACK_WINDOW stack upward. Returns the slot, or -1 when the digit art is missing.
func spawn(value: int, pos: Vector2, kind: int = DEALT, key: int = -1) -> int:
	return _spawn(str(maxi(value, 0)), pos, kind, key)


## Shows "Miss" in the kind's small set (NoRed0/Miss, NoViolet0/Miss).
func spawn_miss(pos: Vector2, kind: int = DEALT, key: int = -1) -> int:
	return _spawn("Miss", pos, kind, key)


## Number of numbers on screen.
func active_count() -> int:
	var n := 0
	for a in _active:
		n += a
	return n


func _process(delta: float) -> void:
	advance(delta)


## Advances every number by `dt` seconds.
func advance(dt: float) -> void:
	_now += dt
	for i in _active.size():
		if _active[i] == 0:
			continue
		var age := _now - _born[i]
		var fr := fade_at(age)
		if fr.x < 0.0:
			_active[i] = 0
			RenderingServer.canvas_item_set_visible(_items[i], false)
			_free.append(i)
			continue
		RenderingServer.canvas_item_set_transform(_items[i], Transform2D(0.0, _base[i] - Vector2(0.0, roundf(fr.y))))
		var tint := _tint[i]
		tint.a = fr.x
		RenderingServer.canvas_item_set_modulate(_items[i], tint)
		if _crit[i] == 1:
			RenderingServer.canvas_item_set_visible(_effects[i], age >= CRIT_EFFECT_DELAY)


func _spawn(text: String, pos: Vector2, kind: int, key: int) -> int:
	var sets: Array = SETS.get(kind, SETS[DEALT])
	var large := _glyph_set(sets[0])
	var small := _glyph_set(sets[1])
	var tint := Color.WHITE
	if kind == HP_GAIN and (large.is_empty() or small.is_empty()):
		large = _glyph_set("NoViolet1")
		small = _glyph_set("NoViolet0")
		tint = GAIN_FALLBACK_TINT
	var placed := layout_number(text, large, small)
	if placed.is_empty():
		return -1
	var lift := 0.0
	if key >= 0:
		var line := 0
		var last: Variant = _keys.get(key)
		if last is Array and _now - float(last[0]) < STACK_WINDOW:
			line = (int(last[2]) + 1) % MAX_LINES
			if line > 0:
				lift = float(last[1]) + (CRIT_LINE_PX if bool(last[3]) else LINE_PX)
		_keys[key] = [_now, lift, line, kind == CRIT]
	var i := _alloc()
	var ci := _items[i]
	RenderingServer.canvas_item_clear(ci)
	for p: Dictionary in placed:
		var f: SpriteFrame = p.frame
		RenderingServer.canvas_item_add_texture_rect_region(ci, Rect2(p.pos - f.origin, f.region.size), f.page.get_rid(),
			f.region)
	var eff := _effects[i]
	RenderingServer.canvas_item_clear(eff)
	_crit[i] = 0
	if kind == CRIT and text != "Miss":
		var e := _glyph_set("NoCri1").get("effect") as SpriteFrame
		if e != null:
			var first: Dictionary = placed[0]
			RenderingServer.canvas_item_add_texture_rect_region(eff, Rect2(first.pos - e.origin, e.region.size),
				e.page.get_rid(), e.region)
			_crit[i] = 1
	RenderingServer.canvas_item_set_visible(eff, false)
	_base[i] = pos.round() - Vector2(0.0, lift)
	_born[i] = _now
	_active[i] = 1
	_tint[i] = tint
	RenderingServer.canvas_item_set_transform(ci, Transform2D(0.0, _base[i]))
	RenderingServer.canvas_item_set_modulate(ci, tint)
	RenderingServer.canvas_item_set_visible(ci, true)
	return i


func _alloc() -> int:
	if not _free.is_empty():
		var i := _free[_free.size() - 1]
		_free.resize(_free.size() - 1)
		return i
	var ci := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(ci, get_canvas_item())
	var eff := RenderingServer.canvas_item_create()
	RenderingServer.canvas_item_set_parent(eff, ci)
	RenderingServer.canvas_item_set_draw_behind_parent(eff, true)
	_items.append(ci)
	_effects.append(eff)
	_born.append(0.0)
	_base.append(Vector2.ZERO)
	_crit.append(0)
	_tint.append(Color.WHITE)
	_active.append(0)
	return _items.size() - 1


## "0".."9", "Miss" and "effect" frames of one BasicEff set (cached).
func _glyph_set(set_name: String) -> Dictionary:
	if _glyphs.has(set_name):
		return _glyphs[set_name]
	var out: Dictionary = {}
	var lib := _lib()
	var node: Variant = lib.find(BASE + set_name) if lib != null else null
	if node is Dictionary:
		var w := lib.img("Effect.wz/BasicEff.img")
		for k: Variant in (node as Dictionary).keys():
			var c: Variant = node[k]
			if WzImg.is_canvas(c):
				var f := SpriteAnim.make_frame(c, w, BASE + set_name + "/" + str(k))
				if f.page != null:
					out[String(k)] = f
	_glyphs[set_name] = out
	return out


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library
