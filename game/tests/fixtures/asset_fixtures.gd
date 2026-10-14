extends RefCounted
## A tiny synthetic asset cache written at test time (no Nexon data): cache.json, img JSON trees shaped like
## docs/ASSET_PIPELINE.md 5.2, a generated PNG atlas page, a generated WAV and String.wz lookups.
##
## Page "Test.wz/Sprite.img.0.png" is 32x8: block k (k = 0..3) is a 4x4 square at x = 5k, y = 0 filled with COLORS[k];
## the rest is transparent.

const COLORS := [Color(1, 0, 0), Color(0, 1, 0), Color(0, 0, 1), Color(1, 1, 0)]
const ROOT := "user://_test_cache/assets"
const PAGE := "Test.wz/Sprite.img.0.png"
## A synthetic map (id 777) whose backs/tiles/objs live in testBack/testTile/testObj.
const MAP_ID := 777
const MAP_PATH := "Map.wz/Map/Map0/000000777.img"


## Map 777: two backs (a tiled one and a front animated one), layer 0 with three objs (an animated one, a flipped one,
## z 5 and z 1 statics) and two tiles (canvas z 2 and -4), layer 1 with an obj whose sprite is missing, one floor.
static func map_img() -> Dictionary:
	var img := {
		"info": {"bgm": "Bgm00/Test"},
		"back": {
			"0": {"bS": "testBack", "no": 0, "x": 0, "y": 0, "rx": 0, "ry": 0, "type": 3, "cx": 0, "cy": 0, "a": 255,
				"front": 0, "ani": 0, "f": 0},
			"1": {"bS": "testBack", "no": 1, "x": 5, "y": 6, "rx": -100, "ry": -100, "type": 0, "cx": 0, "cy": 0,
				"a": 128, "front": 1, "ani": 1, "f": 1},
		},
		"foothold": {"0": {"1": {"1": {"x1": -100, "y1": 0, "x2": 100, "y2": 0, "prev": 0, "next": 0}}}},
		"miniMap": {"width": 400, "height": 300, "centerX": 200, "centerY": 200, "mag": 4},
		"portal": {},
	}
	for layer in 8:
		img[str(layer)] = {"info": {}, "tile": {}, "obj": {}}
	img["0"] = {
		"info": {"tS": "testTile"},
		"tile": {"0": {"x": 0, "y": 0, "u": "bsc", "no": 0}, "1": {"x": 10, "y": 0, "u": "edU", "no": 0}},
		"obj": {
			"0": {"oS": "testObj", "l0": "a", "l1": "b", "l2": "static", "x": 0, "y": 0, "z": 5, "f": 0},
			"1": {"oS": "testObj", "l0": "a", "l1": "b", "l2": "anim", "x": 4, "y": 0, "z": 1, "f": 0},
			"2": {"oS": "testObj", "l0": "a", "l1": "b", "l2": "static", "x": 8, "y": 0, "z": 1, "f": 1},
		},
	}
	img["1"] = {"info": {}, "tile": {}, "obj": {
		"0": {"oS": "testObj", "l0": "a", "l1": "b", "l2": "missing", "x": 0, "y": 0, "z": 0, "f": 0}}}
	return img


## Mob 100100 with stand, move (2 frames), hit1 and a fading die1; no jump (falls back to move).
static func mob_img() -> Dictionary:
	return {
		"$pages": [PAGE],
		"info": {"speed": -65, "maxHP": 8},
		"stand": {"0": _canvas(0, Vector2(2, 4), {})},
		"move": {"0": _canvas(1, Vector2(2, 4), {"delay": 180}), "1": _canvas(2, Vector2(2, 4), {"delay": 180})},
		"hit1": {"0": _canvas(3, Vector2(2, 4), {"delay": 600})},
		"die1": {"0": _canvas(0, Vector2(2, 4), {"delay": 200, "a0": 255, "a1": 0})},
	}


## Writes the cache (idempotent) and returns its root path.
static func write_cache(root: String = ROOT) -> String:
	_mkdir(root.path_join("Test.wz"))
	_mkdir(root.path_join("String.wz"))
	_mkdir(root.path_join("Sound.wz/Test.img"))
	var page := Image.create(32, 8, false, Image.FORMAT_RGBA8)
	page.fill(Color(0, 0, 0, 0))
	for k in COLORS.size():
		page.fill_rect(Rect2i(5 * k, 0, 4, 4), COLORS[k])
	page.save_png(root.path_join("Test.wz/Sprite.img.0.png"))
	_write_json(root.path_join("Test.wz/Sprite.img.json"), sprite_img())
	_write_json(root.path_join("String.wz/Mob.img.json"), {"100100": {"name": "Snail"}, "210100": {"name": "Slime"}})
	_write_json(root.path_join("String.wz/Map.img.json"), {
		"maple": {"10000": {"streetName": "Maple Road", "mapName": "Mushroom Town"}},
		"victoria": {"104040000": {"streetName": "Victoria Road", "mapName": "Henesys Hunting Ground I"}},
	})
	_write_json(root.path_join("String.wz/Skill.img.json"), {
		"0001000": {"name": "Three Snails"}, "200": {"bookName": "Intro. to Magic"},
	})
	for d in ["Map.wz/Map/Map0", "Map.wz/Back", "Map.wz/Tile", "Map.wz/Obj", "Mob.wz"]:
		_mkdir(root.path_join(d))
	_write_json(root.path_join(MAP_PATH + ".json"), map_img())
	_write_json(root.path_join("Map.wz/Back/testBack.img.json"), {"$pages": [PAGE],
		"back": {"0": _canvas(0, Vector2(2, 2), {})}, "ani": {"1": {"0": _canvas(1, Vector2.ZERO, {"delay": 50}),
		"1": _canvas(2, Vector2.ZERO, {"delay": 50})}}})
	_write_json(root.path_join("Map.wz/Tile/testTile.img.json"), {"$pages": [PAGE],
		"bsc": {"0": _canvas(0, Vector2.ZERO, {"z": 2})}, "edU": {"0": _canvas(1, Vector2(2, 4), {"z": -4})}})
	_write_json(root.path_join("Map.wz/Obj/testObj.img.json"), {"$pages": [PAGE], "a": {"b": {
		"static": {"0": _canvas(2, Vector2(1, 1), {})},
		"anim": {"0": _canvas(0, Vector2.ZERO, {"delay": 100}), "1": _canvas(3, Vector2.ZERO, {"delay": 100})},
	}}})
	_write_json(root.path_join("Mob.wz/0100100.img.json"), mob_img())
	_mkdir(root.path_join("Effect.wz"))
	_write_json(root.path_join("Effect.wz/BasicEff.img.json"), basic_eff_img())
	# A linked mob: own info (stats), animations borrowed from 0100100 through info/link.
	_write_json(root.path_join("Mob.wz/0100101.img.json"), {"info": {"link": "0100100", "maxHP": 99, "speed": -50}})
	var f := FileAccess.open(root.path_join("Sound.wz/Test.img/beep.wav"), FileAccess.WRITE)
	f.store_buffer(wav_bytes(200))
	f.close()
	_write_json(root.path_join("Sound.wz/Test.img.json"), {
		"beep": {"$sound": "Sound.wz/Test.img/beep.wav", "$ms": 9},
	})
	_write_json(root.path_join("cache.json"), {
		"format": 1,
		"importer": "test",
		"imgs": {
			"Test.wz/Sprite.img": {"json": "Test.wz/Sprite.img.json", "pages": 1, "paths": null, "canvases": 5},
			"String.wz/Mob.img": {"json": "String.wz/Mob.img.json", "pages": 0},
			"String.wz/Map.img": {"json": "String.wz/Map.img.json", "pages": 0},
			"String.wz/Skill.img": {"json": "String.wz/Skill.img.json", "pages": 0},
			"Sound.wz/Test.img": {"json": "Sound.wz/Test.img.json", "pages": 0, "sounds": 1},
		},
	})
	return root


## The synthetic img tree: an animation with default delay and an alpha ramp, single-alpha frames, a single canvas,
## and UOL links (sibling, via "..", chained, and followed mid-path).
static func sprite_img() -> Dictionary:
	return {
		"$pages": ["Test.wz/Sprite.img.0.png"],
		"info": {"speed": -65, "name": "sprite"},
		"anim": {
			"0": _canvas(0, Vector2(2, 4), {"delay": 200, "head": {"$v": [0, -3]}}),
			"1": _canvas(1, Vector2(1, 1), {}),
			"2": _canvas(2, Vector2(0, 0), {"delay": 300, "a0": 255, "a1": 0}),
		},
		"fadeOut": {"0": _canvas(3, Vector2(0, 0), {"delay": 100, "a0": 100})},
		"fadeIn": {"0": _canvas(3, Vector2(0, 0), {"delay": 100, "a1": 55})},
		"negative": {"0": _canvas(0, Vector2.ZERO, {"delay": -900}), "1": _canvas(1, Vector2.ZERO, {"delay": 0})},
		"single": _canvas(3, Vector2(2, 2), {"z": 5}),
		"alias": {"$uol": "anim/1"},
		"group": {"ref": {"$uol": "../anim/2"}, "chain": {"$uol": "ref"}},
		"uolAnim": {"0": {"$uol": "../anim/0"}, "1": _canvas(1, Vector2.ZERO, {})},
		"broken": {"$uol": "../../nowhere"},
		"behind": {"0": _canvas(1, Vector2.ZERO, {"delay": 100}), "z": -1},
	}


## Effect.wz/BasicEff.img digit sets for DamageNumbers: NoRed0/1, NoCri0/1 and NoViolet0/1 with "0".."9" (4x4 blocks,
## origin (2, 4): the baseline is the bottom edge), "Miss" in NoRed0/NoViolet0 and the NoCri1 "effect" burst.
static func basic_eff_img() -> Dictionary:
	var img := {"$pages": [PAGE]}
	for set_name in ["NoRed0", "NoRed1", "NoCri0", "NoCri1", "NoViolet0", "NoViolet1"]:
		var s := {}
		for d in 10:
			s[str(d)] = _canvas(d % 4, Vector2(2, 4), {})
		img[set_name] = s
	img.NoRed0["Miss"] = _canvas(3, Vector2(2, 4), {})
	img.NoViolet0["Miss"] = _canvas(3, Vector2(2, 4), {})
	img.NoCri1["effect"] = _canvas(1, Vector2(2, 2), {})
	return img


## A mono 8-bit PCM WAV with `n` samples at 22050 Hz.
static func wav_bytes(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.append_array("RIFF".to_ascii_buffer())
	b.append_array(_u32(36 + n))
	b.append_array("WAVEfmt ".to_ascii_buffer())
	b.append_array(_u32(16))
	b.append_array(_u16(1))  # PCM
	b.append_array(_u16(1))  # mono
	b.append_array(_u32(22050))
	b.append_array(_u32(22050))
	b.append_array(_u16(1))
	b.append_array(_u16(8))
	b.append_array("data".to_ascii_buffer())
	b.append_array(_u32(n))
	for i in n:
		b.append(128 + (40 if (i / 10) % 2 == 0 else -40))
	return b


static func _canvas(block: int, origin: Vector2, extra: Dictionary) -> Dictionary:
	var c := {"$canvas": [0, 5 * block, 0, 4, 4], "origin": {"$v": [origin.x, origin.y]}}
	c.merge(extra)
	return c


static func _write_json(path: String, data: Variant) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()


static func _mkdir(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


static func _u32(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(4)
	b.encode_u32(0, v)
	return b


static func _u16(v: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(2)
	b.encode_u16(0, v)
	return b
