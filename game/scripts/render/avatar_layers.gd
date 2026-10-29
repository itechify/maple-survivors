class_name AvatarLayers
extends RefCounted
## Pure helpers of the avatar renderer for equipment art that is not simply `<stance>/<frame>/<layer>` (spec #34 #117;
## reusable by regular equipment drawing): which frame of an equip img a stance or expression selects, weapon covers
## nested under a weapon-type key, `vslot` hiding through Base.wz/smap.img, and cash replacing the regular equipment of
## its slot. No nodes, files or RNG: everything takes WzImg trees or plain data.
##
## Frame lookups return `[node, path]`: the frame node (null when absent) and its path inside the img, which
## AvatarRenderer uses to follow `{"$uol": ...}` children the importer could not resolve (`WzImg.node` follows links).
##
## vslot hiding (tier C reading of smap.img and `info/vslot`; the codes themselves are tier A): smap.img gives every
## z layer a string of two-letter slot codes ("hair" = "H2", "mailChest" = "MaGw"), and an item's `info/vslot` lists the
## codes it occupies ("CpH1H5" for a hat). A layer is hidden when every code of its smap entry is occupied by one drawn
## item other than its own. Requiring all codes keeps a glove (GlGw) from hiding the coat sleeves (MaGw) and shoes
## (So) from hiding the pants (PnSo). Which regular equip a cash item replaces is decided by `suppressed_by_cash`: the
## same slot, or a regular item whose whole vslot the cash item occupies (a MaPn vest replaces the pants too).

## Weapon item categories (id / 10000) 130..169 give the weapon type category - 100 (30 one-handed sword, 37 wand, ...).
const WEAPON_CATEGORY_FIRST := 130
const WEAPON_CATEGORY_LAST := 169
const WEAPON_TYPE_OFFSET := 100
## Body stance -> the stance a weapon draws when it has no art for it, at the same frame index. tier C (#327): a one-handed
## stab pair; every imported staff has stabO1, 9 of the 14 lack stabO2 (Skill.wz/222.img chainlightning plays stabO2.1).
## tier C (#420): a knuckle has no swingTF (Barrage's `fist` frame 8 and Dragon Strike's `dragonstrike` frames 4-7 draw it)
## and would vanish; its two-handed swingT3 is the nearest hand pose.
const STANCE_FALLBACKS := {"stabO2": "stabO1", "swingTF": "swingT3"}


## The two-letter slot codes of a smap/vslot string ("CpH1H5" -> Cp, H1, H5).
static func codes(code: String) -> PackedStringArray:
	var out := PackedStringArray()
	var i := 0
	while i + 2 <= code.length():
		out.append(code.substr(i, 2))
		i += 2
	return out


## Weapon type (30..69) of a regular weapon item id; 0 for anything else (cash covers, clothes, 0).
@warning_ignore("integer_division")
static func weapon_type(item_id: int) -> int:
	var category := item_id / 10000
	if category < WEAPON_CATEGORY_FIRST or category > WEAPON_CATEGORY_LAST:
		return 0
	return category - WEAPON_TYPE_OFFSET


## z layer name -> smap code string from Base.wz/smap.img (entries without a string value, e.g. mount layers, are left out).
static func smap_codes(lib: AssetLibrary) -> Dictionary:
	var out := {}
	var w := lib.img("Base.wz/smap.img") if lib != null else null
	if w == null:
		return out
	for k: Variant in w.root.keys():
		var v: Variant = w.root[k]
		if v is String:
			out[String(k)] = v
	return out


## The codes (as a set {code: true}) an img occupies: its `info/vslot`.
static func vslot_set(w: WzImg) -> Dictionary:
	var out := {}
	var v: Variant = w.node("info/vslot") if w != null else null
	if v is String:
		for c in codes(v):
			out[c] = true
	return out


## True when a layer with smap `layer_code` is hidden by the occupied codes `hiding` ({code: true}): it has codes and
## every one of them is occupied.
static func is_hidden(layer_code: String, hiding: Dictionary) -> bool:
	var layer := codes(layer_code)
	if layer.is_empty():
		return false
	for c in layer:
		if not hiding.has(c):
			return false
	return true


## True when the code set `outer` ({code: true}) holds every code of the non-empty set `inner`.
static func covers(outer: Dictionary, inner: Dictionary) -> bool:
	if inner.is_empty():
		return false
	for c: Variant in inner:
		if not outer.has(c):
			return false
	return true


## Removes the parts hidden by the vslot of one other drawn item. `parts` carry `z` (layer name) and `owner` (item id);
## `vslots` is {owner id: {code: true}} for every drawn item; `smap` is smap_codes(). A part is never hidden by its own
## owner, and the items' codes are not pooled (shoes So plus a vest MaPn must not hide the pants PnSo).
static func hide_by_vslot(parts: Array, smap: Dictionary, vslots: Dictionary) -> Array:
	if vslots.is_empty() or smap.is_empty():
		return parts
	var out: Array = []
	for p: Dictionary in parts:
		var layer_code: String = smap.get(str(p.get("z")), "")
		var hidden := false
		for owner: Variant in vslots:
			if int(owner) != int(p.get("owner", 0)) and is_hidden(layer_code, vslots[owner]):
				hidden = true
				break
		if not hidden:
			out.append(p)
	return out


## Whether cash equipment `cash` ({slot: id}) replaces the regular equip `item_id` (same slot, as in v83: the cash item's
## art is shown instead). A regular overall sits in the coat slot. Weapons are decided per stance by the renderer, since
## a cover only replaces the real weapon where it has art.
@warning_ignore("integer_division")
static func suppressed_by_cash(item_id: int, cash: Dictionary) -> bool:
	var category := item_id / 10000
	if category == CashCatalog.OVERALL_CATEGORY:
		return cash.has("top")
	if category == CashCatalog.WEAPON_COVER_CATEGORY or not CashCatalog.CATEGORY_SLOT.has(category):
		return false
	return cash.has(CashCatalog.CATEGORY_SLOT[category])


## Whether a worn cash item with codes `cash_vslot` also replaces the regular equip `item_id` that occupies `vslot`:
## its whole vslot is inside the cash item's (a top with MaPn replaces the pants; a hat CpH1H5 a plain Cp cap).
## Weapons are left to the per-stance cover rule.
static func replaced_by_vslot(item_id: int, vslot: Dictionary, cash_vslot: Dictionary) -> bool:
	return weapon_type(item_id) == 0 and covers(cash_vslot, vslot)


## True when the animation at `base` exists in the img and has at least one canvas in its first frame (or itself).
static func has_art(w: WzImg, base: String) -> bool:
	var node: Variant = frame(w, base, 0)[0]
	if not (node is Dictionary):
		return false
	for k: Variant in (node as Dictionary).keys():
		var c: Variant = node[k]
		if WzImg.is_canvas(c) or (c is Dictionary and (c as Dictionary).has("$uol")):
			return true
	return false


## Frame `index` of the animation at `base` ("stand1", "37/stand1", "blink") as [node, path]. A node with numbered
## children is an animation (`index` wraps, or holds the last frame when `wrap` is false); any other node is a single frame.
static func frame(w: WzImg, base: String, index: int, wrap: bool = true) -> Array:
	var anim: Variant = w.node(base) if w != null else null
	if not (anim is Dictionary):
		return [null, base]
	var keys := SpriteAnim.frame_keys(anim)
	if keys.is_empty():
		return [anim, base]
	var i := posmod(index, keys.size()) if wrap else clampi(index, 0, keys.size() - 1)
	var rel := base.path_join(keys[i])
	return [w.node(rel), rel]


## A stance-keyed equip's frame: the stance, else `default` (`backDefault` from behind), else [null, ""]. Hats, eye
## accessories and earrings keep one `default` frame for stances they do not animate.
static func stance_frame(w: WzImg, stance: String, index: int, back: bool = false) -> Array:
	if has_art(w, stance):
		return frame(w, stance, index)
	var fallback := "backDefault" if back else "default"
	if has_art(w, fallback):
		return frame(w, fallback, index)
	return [null, ""]


## A weapon's frame for the body's stance: the stance itself, else the stance it borrows from (STANCE_FALLBACKS) at the
## same frame index, else what any stance-keyed equip does (stance_frame). Staves borrow stabO1 for missing stabO2;
## knuckles borrow swingT3 for missing swingTF, including frames reached by fist and dragonstrike.
static func weapon_stance_frame(w: WzImg, stance: String, index: int, back: bool = false) -> Array:
	if not has_art(w, stance) and STANCE_FALLBACKS.has(stance) and has_art(w, STANCE_FALLBACKS[stance]):
		return frame(w, STANCE_FALLBACKS[stance], index)
	return stance_frame(w, stance, index, back)


## A face accessory's frame for a face expression ("default", "blink", "smile", ...): the same expression, else `default`.
## `index` is the face's expression frame; an accessory with fewer frames holds its last one.
static func expression_frame(w: WzImg, expression: String, index: int) -> Array:
	var base := expression if has_art(w, expression) else "default"
	if not has_art(w, base):
		return [null, ""]
	return frame(w, base, index, false)


## A weapon cover's frame for the wearer's weapon type and the stance: [node, path], or [null, ""] when the cover has no
## art for that type or stance (the real weapon stays visible then).
static func cover_frame(w: WzImg, wtype: int, stance: String, index: int) -> Array:
	var base := "%d/%s" % [wtype, stance]
	if wtype <= 0 or not has_art(w, base):
		return [null, ""]
	return frame(w, base, index)
