class_name Elements
extends RefCounted
## Element presentation metadata. Only elements with verified element-keyed art are admitted by Forms.
## tier A: art indices verified from Paladin pixels (P1 #309). No verified poison or mixed-element art row.
## tier C: weapon tint RGB values; a presentation cue independent of damage and WZ pixels.
const TABLE := {
	"": {"art": 0, "tint": Color.WHITE, "name": ""},
	"i": {"art": 1, "tint": Color(0.3, 0.7, 1.0), "name": "ice"},
	"f": {"art": 2, "tint": Color(1.0, 0.35, 0.2), "name": "fire"},
	"l": {"art": 3, "tint": Color(1.0, 0.85, 0.2), "name": "lightning"},
	"h": {"art": 5, "tint": Color(1.0, 0.8, 0.55), "name": "holy"},
	"s": {"tint": Color(0.6, 0.9, 0.35), "name": "poison"},
	"fs": {"name": "fire/poison"},
}

## Whether a verified art row exists, including the explicit no-element row.
static func has_art(code: String) -> bool:
	return TABLE.get(code, {}).has("art")

## Art index, falling back to the explicit no-element art for casts without a Form.
static func art_index(code: String) -> int:
	return int(TABLE.get(code, {}).get("art", 0))

## Weapon cue colour, white when no tint is defined.
static func tint(code: String) -> Color:
	return TABLE.get(code, {}).get("tint", Color.WHITE)

## Player-facing element name.
static func display_name(code: String) -> String:
	return String(TABLE.get(code, {}).get("name", code))

## Verified code-to-index rows for callers that preload every art variant.
static func art_indices() -> Dictionary:
	var out := {}
	for code: String in TABLE:
		if has_art(code):
			out[code] = art_index(code)
	return out
