class_name AssetLibrary
extends Node
## Read access to the imported v83 asset cache (autoload "Assets"; docs/ASSET_PIPELINE.md section 6).
##
## Everything is addressed by WZ path, exactly as in the original data: `img("Mob.wz/0100100.img")`,
## `node("Mob.wz/0100100.img/move/0/origin")`, `anim("Mob.wz/0100100.img/move")`, `sound("Sound.wz/Mob.img/0100100/Die")`.
## Results are cached. Lookups that fail are recorded in `missing` (renderers and tests count them) and return null
## or an empty SpriteAnim, never crash.
##
## Tests and tools create their own instance (`AssetLibrary.new()` + `open(root)`) instead of using the autoload.

## Cache index format this reader understands (cache.json "format").
const FORMAT := 1
## Item.wz folder by id / 1000000 (docs/ASSET_PIPELINE.md section 4).
const ITEM_TYPES := {2: "Consume", 3: "Install", 4: "Etc", 5: "Cash", 9: "Special"}

## Absolute (or user://) cache root.
var root := ""
## Parsed cache.json ({} when absent).
var index: Dictionary = {}
## WZ paths that were requested but not found (each listed once).
var missing: PackedStringArray = []

var _opened := false
var _imgs: Dictionary = {}
var _anims: Dictionary = {}
var _frames: Dictionary = {}
var _sounds: Dictionary = {}
var _pages: Dictionary = {}
var _map_names: Dictionary = {}


## Points the library at a cache root ("" = AssetCachePaths.resolve_cache_root()) and drops every cached object.
## Returns has_cache().
func open(p_root: String = "") -> bool:
	root = p_root if p_root != "" else AssetCachePaths.resolve_cache_root()
	root = root.replace("\\", "/").rstrip("/")
	index = {}
	missing = []
	_imgs.clear()
	_anims.clear()
	_frames.clear()
	_sounds.clear()
	_pages.clear()
	_map_names.clear()
	_opened = true
	var idx_path := root.path_join("cache.json")
	if root != "" and FileAccess.file_exists(idx_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx_path))
		if parsed is Dictionary:
			index = parsed
	return has_cache()


## True when the cache exists and its format is supported.
func has_cache() -> bool:
	_ensure_open()
	return not index.is_empty() and int(index.get("format", 0)) == FORMAT


## The shared library: the "Assets" autoload when the scene tree has one, else null.
static func get_default() -> AssetLibrary:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("Assets") as AssetLibrary


## Splits "Mob.wz/0100100.img/move/0" into ["Mob.wz/0100100.img", "move/0"].
static func split_path(full_path: String) -> PackedStringArray:
	var i := full_path.find(".img/")
	if i >= 0:
		return PackedStringArray([full_path.substr(0, i + 4), full_path.substr(i + 5)])
	if full_path.ends_with(".img"):
		return PackedStringArray([full_path, ""])
	return PackedStringArray(["", full_path])


## The parsed image (cached); null when it is not in the cache.
func img(path: String) -> WzImg:
	_ensure_open()
	if _imgs.has(path):
		return _imgs[path]
	var rel := path + ".json"
	var imgs: Variant = index.get("imgs", {})
	if imgs is Dictionary and (imgs as Dictionary).has(path):
		var entry: Variant = imgs[path]
		if entry is Dictionary and (entry as Dictionary).has("json"):
			rel = String(entry["json"])
	var abs_path := root.path_join(rel)
	var w: WzImg = null
	if root != "" and FileAccess.file_exists(abs_path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(abs_path))
		if parsed is Dictionary:
			w = WzImg.new(path, parsed, root, _load_page)
	if w == null:
		_miss(path)
	_imgs[path] = w
	return w


## True when the image is in the cache (does not record a miss).
func has_img(path: String) -> bool:
	_ensure_open()
	if _imgs.has(path):
		return _imgs[path] != null
	var imgs: Variant = index.get("imgs", {})
	if imgs is Dictionary and (imgs as Dictionary).has(path):
		return true
	return root != "" and FileAccess.file_exists(root.path_join(path + ".json"))


## Any node by full WZ path ("Map.wz/Physics.img/walkSpeed"); null (and recorded as missing) when absent.
func node(full_path: String) -> Variant:
	var v: Variant = find(full_path)
	if v == null:
		_miss(full_path)
	return v


## Like node() but a miss is not recorded (for optional data).
func find(full_path: String) -> Variant:
	var parts := split_path(full_path)
	if parts[0] == "":
		return null
	var w: WzImg
	if has_img(parts[0]):
		w = img(parts[0])
	if w == null:
		return null
	return w.node(parts[1])


## The animation under a node (numbered canvases or a single canvas), cached; empty (and recorded) when absent.
func anim(full_path: String) -> SpriteAnim:
	if _anims.has(full_path):
		return _anims[full_path]
	var a := _build_anim(full_path)
	if a.is_empty():
		_miss(full_path)
	_anims[full_path] = a
	return a


## Like anim() but returns null without recording a miss when there is no such animation.
func find_anim(full_path: String) -> SpriteAnim:
	if _anims.has(full_path):
		var c: SpriteAnim = _anims[full_path]
		return null if c.is_empty() else c
	var a := _build_anim(full_path)
	if a.is_empty():
		return null
	_anims[full_path] = a
	return a


## A single canvas as a frame (icons, UI pieces), cached; null (and recorded) when absent.
func frame(full_path: String) -> SpriteFrame:
	if _frames.has(full_path):
		return _frames[full_path]
	var f: SpriteFrame = null
	var parts := split_path(full_path)
	var n: Variant = find(full_path)
	if WzImg.is_canvas(n):
		f = SpriteAnim.make_frame(n, img(parts[0]), full_path)
		if f.page == null:
			f = null
	if f == null:
		_miss(full_path)
	_frames[full_path] = f
	return f


## A sound node as an AudioStream (MP3 or WAV, cached); null (and recorded) when absent.
## `path` is the WZ path of the Sound_DX8 node, e.g. "Sound.wz/Bgm01.img/CavaBien".
func sound(path: String) -> AudioStream:
	_ensure_open()
	if _sounds.has(path):
		return _sounds[path]
	var file_rel := ""
	var n: Variant = find(path)
	if n is Dictionary and (n as Dictionary).get("$sound") is String:
		file_rel = String(n["$sound"])
	else:
		for ext in [".mp3", ".wav"]:
			if FileAccess.file_exists(root.path_join(path + ext)):
				file_rel = path + ext
				break
	var stream: AudioStream = null
	if file_rel != "":
		stream = load_audio(root.path_join(file_rel))
	if stream == null:
		_miss(path)
	_sounds[path] = stream
	return stream


## Loads an MP3 or WAV file from an absolute path (null on failure).
static func load_audio(abs_path: String) -> AudioStream:
	if not FileAccess.file_exists(abs_path):
		return null
	var bytes := FileAccess.get_file_as_bytes(abs_path)
	if bytes.is_empty():
		return null
	match abs_path.get_extension().to_lower():
		"mp3":
			return AudioStreamMP3.load_from_buffer(bytes)
		"wav":
			return AudioStreamWAV.load_from_buffer(bytes)
	return null


## An atlas page by path relative to the cache root (cached).
func page_texture(rel_path: String) -> Texture2D:
	return _load_page(root.path_join(rel_path))


## Number of atlas pages loaded so far.
func pages_loaded() -> int:
	return _pages.size()


## String.wz names. kind: "Mob" (unpadded id), "Skill" (7-digit), "Book" (job id -> skill book name), "Map",
## "Street", "Etc", "Eqp", "Npc" (unpadded id). Returns "" when unknown (not recorded as missing).
func string_name(kind: String, id: int) -> String:
	var v: Variant = null
	match kind:
		"Mob":
			v = find("String.wz/Mob.img/%d/name" % id)
		"Skill":
			v = find("String.wz/Skill.img/%07d/name" % id)
		"Book":
			v = find("String.wz/Skill.img/%03d/bookName" % id)
		"Map":
			v = map_strings(id).get("mapName", "")
		"Street":
			v = map_strings(id).get("streetName", "")
		"Etc":
			v = find("String.wz/Etc.img/Etc/%d/name" % id)
		"Npc":
			v = find("String.wz/Npc.img/%d/name" % id)
		"Eqp":
			var eqp: Variant = find("String.wz/Eqp.img/Eqp")
			if eqp is Dictionary:
				for cat: Variant in (eqp as Dictionary).values():
					if cat is Dictionary and (cat as Dictionary).has(str(id)):
						v = (cat[str(id)] as Dictionary).get("name", "")
						break
	return String(v) if v is String else ""


## {"mapName", "streetName"} of a map from String.wz/Map.img (regions searched in order); {} when unknown.
func map_strings(map_id: int) -> Dictionary:
	if _map_names.has(map_id):
		return _map_names[map_id]
	var out: Dictionary = {}
	var regions: Variant = find("String.wz/Map.img")
	if regions is Dictionary:
		var key := str(map_id)
		for r: Variant in (regions as Dictionary).values():
			if r is Dictionary and (r as Dictionary).has(key) and r[key] is Dictionary:
				out = r[key]
				break
	_map_names[map_id] = out
	return out


## "Map.wz/Map/Map1/104040000.img" for a map id.
static func map_img_path(map_id: int) -> String:
	var s := "%09d" % map_id
	return "Map.wz/Map/Map%s/%s.img" % [s[0], s]


## "Mob.wz/0100100.img" for a mob id.
static func mob_img_path(mob_id: int) -> String:
	return "Mob.wz/%07d.img" % mob_id


## The mob image holding a mob's animations: its `info/link` target when it has one, else its own image.
func mob_anim_img_path(mob_id: int) -> String:
	var p := mob_img_path(mob_id)
	var link: Variant = find(p + "/info/link")
	if link != null and str(link) != "":
		var lp := mob_img_path(int(str(link)))
		if has_img(lp):
			return lp
	return p


## The mob image root for RunWorld setup with `info/link` followed (docs/ARCHITECTURE.md 4.4.1): the mob's own tree
## (its own `info`: level, maxHP, exp, speed...) with every stance it lacks copied from the link target. `$pages` is
## dropped because copied canvases index the target's pages: draw mobs through anim() / MobRenderer, not this tree.
## {} when absent.
func mob_root(mob_id: int) -> Dictionary:
	var own := img(mob_img_path(mob_id))
	if own == null:
		return {}
	var out: Dictionary = own.root.duplicate()
	out.erase("$pages")
	var target_path := mob_anim_img_path(mob_id)
	if target_path != own.path:
		var target := img(target_path)
		if target != null:
			for k: Variant in target.root.keys():
				if not out.has(k) and not String(k).begins_with("$"):
					out[k] = target.root[k]
	return out


## "Item.wz/Etc/0400.img/04000019/info/iconRaw" for an item id.
@warning_ignore("integer_division")
static func item_icon_path(item_id: int, raw: bool = true) -> String:
	if item_id / 1000000 == 9:
		return meso_frame_path(item_id, 0)
	var t: String = ITEM_TYPES.get(item_id / 1000000, "Etc")
	return "Item.wz/%s/%04d.img/%08d/info/%s" % [t, item_id / 10000, item_id, "iconRaw" if raw else "icon"]


## "Item.wz/Special/0900.img/09000002/iconRaw/1": frame `frame` (0-3) of a Special item's (meso coin's) animation.
@warning_ignore("integer_division")
static func meso_frame_path(item_id: int, frame: int) -> String:
	return "Item.wz/Special/%04d.img/%08d/iconRaw/%d" % [item_id / 10000, item_id, frame]


## "Sound.wz/Bgm01.img/CavaBien" for a map's info/bgm value "Bgm01/CavaBien".
static func bgm_path(bgm: String) -> String:
	var i := bgm.find("/")
	if i < 0:
		return ""
	return "Sound.wz/%s.img/%s" % [bgm.substr(0, i), bgm.substr(i + 1)]


## Forgets the recorded misses.
func clear_missing() -> void:
	missing = []


func _build_anim(full_path: String) -> SpriteAnim:
	var parts := split_path(full_path)
	var n: Variant = find(full_path)
	var w: WzImg = img(parts[0]) if (n != null and parts[0] != "") else null
	return SpriteAnim.from_node(n, w, full_path, parts[1])


func _load_page(abs_path: String) -> Texture2D:
	if _pages.has(abs_path):
		return _pages[abs_path]
	var tex := WzImg.load_page(abs_path)
	if tex == null:
		_miss(abs_path)
	_pages[abs_path] = tex
	return tex


func _miss(p: String) -> void:
	if not (p in missing):
		missing.append(p)


func _ensure_open() -> void:
	if not _opened:
		open()
