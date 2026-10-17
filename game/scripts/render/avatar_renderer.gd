class_name AvatarRenderer
extends Node2D
## Composited MapleStory character: body, head, face, hair and equips from Character.wz, drawn per frame.
##
## Anchors (docs/research/prior-art.md section 4, "generic bones" reading): every part canvas has `map` vectors
## (navel, neck, hand, brow, ...) relative to its origin. The body is placed with its origin on the character origin
## (the feet) and its map vectors become anchors; every other part is placed so that its first map vector that already
## exists as an anchor lands on that anchor (arm/clothes by navel, head by neck, face/hair by brow, weapon by hand or
## navel), and adds its remaining vectors as new anchors. Parts are drawn back-to-front by Base.wz/zmap.img (which lists
## z names front-most first; unknown names go to the very back).
##
## Stance frames and delays come from the body image; head/hair/equips use the same stance and frame index. A part
## without the stance is skipped (equips), or falls back to `front`/`back` (head) and `default`/`backDefault` (hair,
## and hats, eye accessories and earrings, which keep one `default` frame). Frames with `face = 0` (ladder, rope) hide
## the face and the face accessory. The face plays `default` with an occasional `blink` (tier C: every 2-5 s); a face
## accessory follows the same expression and frame. Without a cap the hair's *BelowCap layers are not drawn (they
## replace hair under a cap); a cap whose `info/vslot` holds H1 (CpH1H5 half-cover, full covers) hides
## hairOverHead, a CpH5 headband keeps it drawn over the band (hair_layers_skipped, #126; the drawn cap decides, so a cash
## hat's vslot when one is worn).
## Cash equipment (`look.cash`, {slot: id} already filtered by account ownership, spec #34) draws instead of the regular
## equip of its slot (AvatarLayers.suppressed_by_cash); an overall is stored under top and bottom and drawn once. A
## weapon cover draws the art of the real weapon's type (AvatarLayers.weapon_type) for the current stance, and the real
## weapon stays when the cover has none (or the look has no weapon). Items hide the layers their `vslot` occupies
## through Base.wz/smap.img (hat over hair, full-head hats over head and accessories).
## WZ art faces left; facing = 1 mirrors around the character origin.

## tier C: random interval between blinks, seconds.
const BLINK_MIN := 2.0
const BLINK_MAX := 5.0
## Equip folders by id / 10000 (docs/ASSET_PIPELINE.md section 4).
const EQUIP_DIRS := {100: "Cap", 101: "Accessory", 102: "Accessory", 103: "Accessory", 104: "Coat", 105: "Longcoat",
	106: "Pants", 107: "Shoes", 108: "Glove", 109: "Shield", 110: "Cape", 111: "Ring"}
## Stances drawn from behind: the hair falls back to backDefault and the head to back.
const HAT_CATEGORY := 100
const FACE_ACCESSORY_CATEGORY := 101
const BACK_STANCES := ["ladder", "rope", "ladder2", "rope2"]
## MakeCharInfo male default look (docs/GAME_DESIGN.md section 1): no weapon; a job weapon (e.g. the Magician's Wooden
## Wand 1372005) is added to `equips` by whoever sets the look.
const DEFAULT_LOOK := {"skin": 0, "face": 20000, "hair": 30030, "equips": [1040002, 1060002, 1072001]}

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary
## Current look: {"skin": int, "face": int, "hair": int, "equips": [item ids], "cash": {slot: item id} (optional)}.
var look: Dictionary = DEFAULT_LOOK.duplicate(true)
## Current stance name, frame index and time inside the stance.
var stance := "stand1"
var frame_index := 0
var stance_time := 0.0
## Looping stance (false: hold the last frame).
var looping := true
## -1 faces left (WZ default), 1 faces right.
var facing := -1
## Lookups that failed (missing imgs or stances).
var missing: PackedStringArray = []

var _body: WzImg
var _head: WzImg
var _face: WzImg
var _hair: WzImg
## Worn items in draw order: {"id": int, "img": WzImg, "vslot": {code: true}, "cash": bool}.
var _sources: Array[Dictionary] = []
var _weapon_type := 0
var _smap: Dictionary = {}
var _has_cap := false
var _cap_vslot := ""
var _zorder: Dictionary = {}
var _delays: PackedFloat32Array = []
var _expression := "default"
var _expr_time := 0.0
var _expr_hold := 0.0
var _blink_in := 3.0
var _rng := RandomNumberGenerator.new()
var _parts: Array = []
var _dirty := true


func _ready() -> void:
	if _body == null:
		set_look(look)


## Sets the look (missing keys keep DEFAULT_LOOK values) and reloads the part images.
@warning_ignore("integer_division")
func set_look(d: Dictionary) -> void:
	look = DEFAULT_LOOK.duplicate(true)
	look.merge(d, true)
	var lib := _lib()
	if lib == null:
		return
	_rng.seed = hash(str(look))
	var skin := int(look.get("skin", 0))
	_body = _load(part_img_path(2000 + skin))
	_head = _load(part_img_path(12000 + skin))
	_face = _load(part_img_path(int(look.get("face", 20000))))
	_hair = _load(part_img_path(int(look.get("hair", 30030))))
	_sources.clear()
	_has_cap = false
	_cap_vslot = ""
	_weapon_type = 0
	var cash := _cash_slots()
	for id: Variant in look.get("equips", []):
		if AvatarLayers.suppressed_by_cash(int(id), cash):
			continue
		_add_source(int(id), false)
		if _weapon_type == 0:
			_weapon_type = AvatarLayers.weapon_type(int(id))
	var worn_cash: Array[int] = []
	for slot: String in CashCatalog.SLOTS:
		var cash_id: int = cash.get(slot, 0)
		if cash_id > 0 and not (cash_id in worn_cash):
			worn_cash.append(cash_id)
			_add_source(cash_id, true)
	_drop_regular_replaced_by_vslot()
	for src in _sources:
		if _category(src.id) == HAT_CATEGORY:
			_has_cap = true
			var info: Variant = (src.img as WzImg).root.get("info")
			_cap_vslot = String(info.get("vslot", "")) if info is Dictionary else ""
	_zorder = zmap_order(lib)
	_smap = AvatarLayers.smap_codes(lib)
	play(stance, true, looping)


## Plays a stance ("stand1", "walk1", "jump", "alert", "prone", "ladder", "rope", "swingO1", "shoot1", "dead", ...).
## Unknown stances fall back to stand1. `restart` rewinds an already playing stance; `loop` = false holds the last frame.
func play(p_stance: String, restart: bool = false, loop: bool = true) -> void:
	if p_stance == stance and not restart and not _delays.is_empty():
		looping = loop
		return
	if not has_stance(p_stance):
		if not (p_stance in missing):
			missing.append(p_stance)
		p_stance = "stand1"
	stance = p_stance
	looping = loop
	stance_time = 0.0
	frame_index = 0
	_delays = stance_delays(stance)
	_dirty = true
	queue_redraw()


## Shows face expression `expr` ("hit", "smile", ... in the face img) from its first frame for at least `seconds` (its
## own frame time when longer), then returns to default (with blinks). An expression the face lacks is ignored.
func set_expression(expr: String, seconds: float = 0.0) -> void:
	if _face == null or not (_face.root.get(expr) is Dictionary):
		return
	_expression = expr
	_expr_time = 0.0
	_expr_hold = seconds
	_dirty = true
	queue_redraw()


## The face expression shown now ("default", "blink", or one set by set_expression()).
func current_expression() -> String:
	return _expression


## Faces left (-1) or right (1).
func set_facing(dir: int) -> void:
	var f := 1 if dir > 0 else -1
	if f != facing:
		facing = f
		queue_redraw()


## Advances the stance and face animations by `dt` seconds (redraws only when a frame changes).
func advance(dt: float) -> void:
	stance_time += dt
	var i := frame_at(_delays, stance_time, looping)
	if i != frame_index:
		frame_index = i
		_dirty = true
	_expr_time += dt
	if _expression == "default":
		_blink_in -= dt
		if _blink_in <= 0.0:
			_expression = "blink"
			_expr_time = 0.0
			_dirty = true
	else:
		var total := 0.0
		for d in expression_delays(_expression):
			total += d
		if _expr_time >= maxf(total, _expr_hold):
			_expression = "default"
			_expr_time = 0.0
			_expr_hold = 0.0
			_blink_in = _rng.randf_range(BLINK_MIN, BLINK_MAX)
			_dirty = true
	if _dirty:
		queue_redraw()


## True when the body image has the stance.
func has_stance(s: String) -> bool:
	return _body != null and _body.root.get(s) is Dictionary


## Duration of a stance in seconds (sum of its frame delays).
func stance_duration(s: String) -> float:
	var t := 0.0
	for d in stance_delays(s):
		t += d
	return t


## True when a non-looping stance has played to its end.
func is_finished() -> bool:
	var t := 0.0
	for d in _delays:
		t += d
	return not looping and stance_time >= t


## Per-frame delays (s) of a body stance (missing delay -> 100 ms, tier C).
func stance_delays(s: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if _body == null:
		return out
	var node: Variant = _body.root.get(s)
	if not (node is Dictionary):
		return out
	for k in SpriteAnim.frame_keys(node):
		var fr: Variant = node[k]
		out.append(SpriteAnim.delay_seconds(fr.get("delay") if fr is Dictionary else null))
	return out


## Per-frame delays of a face expression (a single-frame expression has one 100 ms frame).
func expression_delays(expr: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var node: Variant = _face.root.get(expr) if _face != null else null
	if node is Dictionary:
		var keys := SpriteAnim.frame_keys(node)
		for k in keys:
			out.append(SpriteAnim.delay_seconds((node[k] as Dictionary).get("delay")))
		if keys.is_empty():
			out.append(SpriteAnim.DEFAULT_DELAY)
	return out


## Frame index at time `t` for a list of delays.
static func frame_at(delays: PackedFloat32Array, t: float, loop: bool) -> int:
	var n := delays.size()
	if n <= 1:
		return 0
	var total := 0.0
	for d in delays:
		total += d
	if total <= 0.0:
		return 0
	if loop:
		t = fposmod(t, total)
	elif t >= total:
		return n - 1
	var acc := 0.0
	for i in n:
		acc += delays[i]
		if t < acc:
			return i
	return n - 1


## The parts of the current frame in draw order: [{"name", "frame": SpriteFrame, "pos": Vector2, "z": String}].
func current_parts() -> Array:
	if _dirty:
		_parts = compose(stance, frame_index, _expression, _expr_time)
		_dirty = false
	return _parts


## Builds the draw list of one frame (positions relative to the character origin, unflipped).
func compose(s: String, index: int, expression: String = "default", expr_t: float = 0.0) -> Array:
	var parts: Array = []
	if _body == null:
		return parts
	var res := _resolve(s, index)
	var st: String = res[0]
	var fi: int = res[1]
	var body_frame: Variant = _frame_node(_body.root.get(st), fi)
	if not (body_frame is Dictionary):
		return parts
	_collect(parts, body_frame, _body)
	var back := st in BACK_STANCES
	var head_frame: Variant = _frame_node(_head.root.get(st), fi) if _head != null else null
	if head_frame == null and _head != null:
		head_frame = _head.root.get("back" if back else "front")
	_collect(parts, head_frame, _head)
	var face_visible := int(body_frame.get("face", 1)) != 0
	var expr_index := frame_at(expression_delays(expression), expr_t, false)
	if face_visible and _face != null:
		var expr_node: Variant = _face.root.get(expression, _face.root.get("default"))
		if expr_node is Dictionary and not SpriteAnim.frame_keys(expr_node).is_empty():
			expr_node = _frame_node(expr_node, expr_index)
		_collect(parts, expr_node, _face)
	if _hair != null:
		var hair_frame: Variant = _frame_node(_hair.root.get(st), fi)
		if hair_frame == null:
			hair_frame = _hair.root.get("backDefault" if back else "default")
		_collect(parts, hair_frame, _hair, hair_layers_skipped(_has_cap, _cap_vslot))
	var cover := _cover_frame(st, fi)
	var vslots := {}
	for src in _sources:
		var id: int = src.id
		var fr: Array
		if _category(id) == FACE_ACCESSORY_CATEGORY:
			fr = AvatarLayers.expression_frame(src.img, expression, expr_index) if face_visible else [null, ""]
		elif _category(id) == CashCatalog.WEAPON_COVER_CATEGORY:
			fr = cover
		elif cover[0] != null and AvatarLayers.weapon_type(id) > 0:
			continue # the cover replaces the real weapon only where it has art
		else:
			fr = AvatarLayers.stance_frame(src.img, st, fi, back)
		if fr[0] == null:
			continue
		vslots[id] = src.vslot
		_collect(parts, fr[0], src.img, PackedStringArray(), id, fr[1])
	var placed := layout_parts(parts)
	for i in parts.size():
		parts[i].pos = placed[i]
	parts = AvatarLayers.hide_by_vslot(parts, _smap, vslots)
	return sort_by_z(parts, _zorder)


## Substrings of the hair layer names that are not drawn: "BelowCap" without a cap (those layers replace hair under
## one); "OverHead" under a cap whose vslot holds H1, the smap code of hairOverHead (CpH1H5 half-cover, full covers). A
## CpH5 headband keeps the bangs over the band (tier A: Base.wz/smap.img + Cap `info/vslot`; the v83 clients agree, tier B:
## they draw the overhead hair layers for CpH5 and not for CpH1H5; #126). Base.wz smap hiding gives the same result.
static func hair_layers_skipped(has_cap: bool, vslot: String) -> PackedStringArray:
	if not has_cap:
		return PackedStringArray(["BelowCap"])
	if AvatarLayers.codes(vslot).has("H1"):
		return PackedStringArray(["OverHead"])
	return PackedStringArray()


## Anchor math: positions (where each part's origin goes) for parts [{"map": {name: Vector2}}]; part 0 is the body
## and sits at (0, 0). A part attaches by its first map vector that is already an anchor; parts with no map, or no
## anchor in common, stay at (0, 0).
static func layout_parts(parts: Array) -> PackedVector2Array:
	var n := parts.size()
	var pos := PackedVector2Array()
	pos.resize(n)
	if n == 0:
		return pos
	var placed := PackedByteArray()
	placed.resize(n)
	var anchors: Dictionary = {}
	_place(parts[0], Vector2.ZERO, anchors)
	placed[0] = 1
	var progress := true
	while progress:
		progress = false
		for i in range(1, n):
			if placed[i] == 1:
				continue
			var m: Dictionary = parts[i].get("map", {})
			if m.is_empty():
				placed[i] = 1
				progress = true
				continue
			for k: Variant in m.keys():
				if anchors.has(k):
					pos[i] = anchors[k] - (m[k] as Vector2)
					_place(parts[i], pos[i], anchors)
					placed[i] = 1
					progress = true
					break
	return pos


## Sorts parts back-to-front by zmap index (zmap lists front-most first; unknown z names go to the very back).
## Stable: equal z keeps composition order.
static func sort_by_z(parts: Array, zorder: Dictionary) -> Array:
	var back := zorder.size() + 1
	var keyed: Array = []
	for i in parts.size():
		var z: Variant = parts[i].get("z")
		var zi: int = zorder.get(str(z), back) if z != null else back
		keyed.append([zi, i])
	keyed.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] > b[0]
		return a[1] < b[1])
	var out: Array = []
	for k: Array in keyed:
		out.append(parts[k[1]])
	return out


## z name -> index from Base.wz/zmap.img (front-most first).
static func zmap_order(lib: AssetLibrary) -> Dictionary:
	var out: Dictionary = {}
	var w := lib.img("Base.wz/zmap.img") if lib != null else null
	if w == null:
		return out
	var i := 0
	for k: Variant in w.root.keys():
		if String(k).begins_with("$"):
			continue
		out[String(k)] = i
		i += 1
	return out


## WZ img path of a character part id (body 2000+skin, head 12000+skin, face 2xxxx, hair 3xxxx, equips by id/10000).
@warning_ignore("integer_division")
static func part_img_path(id: int) -> String:
	if id < 10000 or (id >= 12000 and id < 20000):
		return "Character.wz/%08d.img" % id
	if id < 30000:
		return "Character.wz/Face/%08d.img" % id
	if id < 50000:
		return "Character.wz/Hair/%08d.img" % id
	var cat := id / 10000
	if cat >= 130 and cat < 171:
		return "Character.wz/Weapon/%08d.img" % id
	return "Character.wz/%s/%08d.img" % [EQUIP_DIRS.get(cat, "Accessory"), id]


func _draw() -> void:
	var parts := current_parts()
	if facing > 0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(-1, 1))
	for p: Dictionary in parts:
		var f: SpriteFrame = p.frame
		if f.page == null:
			continue
		draw_texture_rect_region(f.page, Rect2(p.pos - f.origin, f.region.size), f.region)
	if facing > 0:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _resolve(s: String, index: int) -> Array:
	var node: Variant = _body.root.get(s) if _body != null else null
	var fr: Variant = _frame_node(node, index)
	if fr is Dictionary and (fr as Dictionary).get("action") is String:
		return [String(fr.action), int(fr.get("frame", 0))]
	return [s, index]


static func _frame_node(stance_node: Variant, index: int) -> Variant:
	if not (stance_node is Dictionary):
		return null
	var keys := SpriteAnim.frame_keys(stance_node)
	if keys.is_empty():
		return null
	return stance_node[keys[index % keys.size()]]


static func _place(part: Dictionary, p: Vector2, anchors: Dictionary) -> void:
	var m: Dictionary = part.get("map", {})
	for k: Variant in m.keys():
		if not anchors.has(k):
			anchors[k] = p + (m[k] as Vector2)


## The look's cash equipment as {slot: id} with whole, positive ids only.
func _cash_slots() -> Dictionary:
	var out := {}
	var raw: Variant = look.get("cash", {})
	if raw is Dictionary:
		for slot: Variant in raw:
			if int(raw[slot]) > 0:
				out[String(slot)] = int(raw[slot])
	return out


## Loads a worn item and appends it to the sources (set_look then finds the drawn cap).
func _add_source(id: int, is_cash: bool) -> void:
	var w := _load(part_img_path(id))
	if w == null:
		return
	_sources.append({"id": id, "img": w, "vslot": AvatarLayers.vslot_set(w), "cash": is_cash})


## Drops the regular equips a worn cash item covers with its vslot (the pants under a MaPn vest, a plain cap under a hat).
func _drop_regular_replaced_by_vslot() -> void:
	var kept: Array[Dictionary] = []
	for src in _sources:
		var replaced := false
		if not bool(src.cash):
			for other in _sources:
				if bool(other.cash) and AvatarLayers.replaced_by_vslot(src.id, src.vslot, other.vslot):
					replaced = true
					break
		if not replaced:
			kept.append(src)
	_sources = kept


## The worn weapon cover's frame ([node, path]) for the real weapon's type and this stance; [null, ""] without a cover
## or without art for that type/stance.
func _cover_frame(st: String, fi: int) -> Array:
	for src in _sources:
		if _category(src.id) == CashCatalog.WEAPON_COVER_CATEGORY:
			return AvatarLayers.cover_frame(src.img, _weapon_type, st, fi)
	return [null, ""]


@warning_ignore("integer_division")
static func _category(id: int) -> int:
	return id / 10000


## Collects the canvases of a frame node as parts, leaving out layers whose name contains one of `skipped`.
## `part_owner` is the worn item's id (0 for body, head, face and hair); `rel` is the frame node's path inside `w`, used
## to follow links the importer could not resolve.
func _collect(parts: Array, frame_node: Variant, w: WzImg, skipped: PackedStringArray = PackedStringArray(),
		part_owner: int = 0, rel: String = "") -> void:
	if not (frame_node is Dictionary) or w == null:
		return
	for k: Variant in (frame_node as Dictionary).keys():
		var c: Variant = frame_node[k]
		if c is Dictionary and (c as Dictionary).has("$uol") and rel != "":
			c = w.node(rel.path_join(String(k)))
		if not WzImg.is_canvas(c):
			continue
		var hidden := false
		for s in skipped:
			if String(k).contains(s):
				hidden = true
		if hidden:
			continue
		var f := SpriteAnim.make_frame(c, w)
		var m: Dictionary = {}
		var mv: Variant = c.get("map")
		if mv is Dictionary:
			for mk: Variant in (mv as Dictionary).keys():
				m[mk] = WzImg.vec(mv[mk])
		parts.append({"name": String(k), "frame": f, "map": m, "z": f.z, "pos": Vector2.ZERO, "owner": part_owner})


func _load(path: String) -> WzImg:
	var lib := _lib()
	var w := lib.img(path) if lib != null else null
	if w == null and not (path in missing):
		missing.append(path)
	return w


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library
