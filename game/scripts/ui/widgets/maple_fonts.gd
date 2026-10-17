class_name MapleFonts
extends RefCounted
## The game's text fonts and the bundled fallback (docs/ARCHITECTURE.md 10 "Web profile"). The game asks for the system
## fonts Arial / Tahoma / Dotum (v83's UI font) through a SystemFont. A browser has no system fonts. Godot then draws
## a SystemFont with no match in its own built-in font and ignores the SystemFont's `fallbacks` (checked on desktop with
## a font name that does not exist: same size as ThemeDB.fallback_font), so make() hands out the bundled Arimo (SIL OFL
## 1.1, metric compatible with Arial, assets/fonts/arimo/) itself when none of the names exists on the system. When a
## system font is found, desktop is unchanged: the SystemFont, with Arimo behind it for glyphs it lacks.
## One variable font file; the bold face is its wght axis.
##
## Rendering matches the SystemFonts: no antialiasing, normal hinting, no subpixel positioning (set on the loaded
## FontFile here, because .import settings are not committed).

const ARIMO_PATH := "res://assets/fonts/arimo/Arimo-Variable.ttf"

static var _file: FontFile
static var _faces: Dictionary = {}


## The font for the first of `names` that exists on the system (a SystemFont), else the bundled Arimo.
static func make(names: PackedStringArray, weight: int = 400) -> Font:
	return make_with(names, weight, system_has_any(names, weight))


## make() with the "a system font exists" answer given (tests).
static func make_with(names: PackedStringArray, weight: int, system_found: bool) -> Font:
	var face := arimo(weight)
	if not system_found and face != null:
		return face
	var f := SystemFont.new()
	f.font_names = names
	f.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	f.hinting = TextServer.HINTING_NORMAL
	f.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	f.font_weight = weight
	f.fallbacks = fallbacks(weight)
	return f


## True when the OS has a font for at least one of `names`.
static func system_has_any(names: PackedStringArray, weight: int = 400) -> bool:
	for n in names:
		if OS.get_system_font_path(n, weight) != "":
			return true
	return false


## The Arimo face for a CSS-style weight (400 regular, 700 bold); null when the font file is missing.
static func arimo(weight: int = 400) -> Font:
	var key := 700 if weight >= 600 else 400
	if _faces.has(key):
		return _faces[key]
	if _file == null:
		_file = load(ARIMO_PATH) as FontFile
		if _file == null:
			return null
		_file.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		_file.hinting = TextServer.HINTING_NORMAL
		_file.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_DISABLED
	var face := FontVariation.new()
	face.base_font = _file
	face.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): key}
	_faces[key] = face
	return face


## The `fallbacks` array for a SystemFont of that weight (empty when the bundled font cannot be loaded).
static func fallbacks(weight: int = 400) -> Array[Font]:
	var out: Array[Font] = []
	var face := arimo(weight)
	if face != null:
		out.append(face)
	return out
