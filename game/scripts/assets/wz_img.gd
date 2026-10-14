class_name WzImg
extends RefCounted
## One exported WZ image from the asset cache: its JSON tree plus its atlas pages (docs/ASSET_PIPELINE.md section 5).
##
## `root` mirrors the WZ tree exactly (same names, order and nesting). Canvases are `{"$canvas": [page, x, y, w, h],
## ...children}`, vectors `{"$v": [x, y]}`. `node("move/0")` walks the tree and follows any `{"$uol": path}` left
## unresolved by the importer (path relative to the UOL's parent, ".." walks up). Page textures are loaded on first use
## from absolute paths (Image.load_from_file + ImageTexture), so nothing here needs `res://` or an import step.

## Hops allowed when following `$uol` links, to stop on cycles.
const MAX_UOL_HOPS := 16

## WZ path of the image, e.g. "Mob.wz/0100100.img".
var path := ""
## The parsed JSON tree (the image's children).
var root: Dictionary = {}
## Atlas page paths relative to the cache root (`$pages`).
var pages: PackedStringArray = []
## Absolute cache root the page paths are relative to.
var cache_root := ""

var _page_loader: Callable
var _page_tex: Array = []
var _atlas: Dictionary = {}


## `page_loader(abs_path) -> Texture2D` lets the AssetLibrary share page textures; default loads directly.
func _init(p_path: String = "", p_root: Dictionary = {}, p_cache_root: String = "", p_page_loader: Callable = Callable()) -> void:
	path = p_path
	root = p_root
	cache_root = p_cache_root
	_page_loader = p_page_loader
	var pg: Variant = root.get("$pages", [])
	if pg is Array:
		for p: Variant in pg:
			pages.append(String(p))
	_page_tex.resize(pages.size())


## The node at `rel_path` ("move/0/origin"), following `$uol` links; null when absent. "" returns the root.
func node(rel_path: String) -> Variant:
	return resolve(root, rel_path)


## Walks `rel_path` from `tree`, following `{"$uol": ...}` nodes met on the way (and at the end).
static func resolve(tree: Dictionary, rel_path: String) -> Variant:
	var segs := _split(rel_path)
	var hops := 0
	var i := 0
	var cur: Variant = tree
	var walked: PackedStringArray = []
	while true:
		if cur is Dictionary and (cur as Dictionary).has("$uol"):
			hops += 1
			if hops > MAX_UOL_HOPS:
				return null
			# The UOL is relative to its parent: drop the UOL's own name, apply the link, then the remaining segments.
			var parent := walked.slice(0, walked.size() - 1)
			var target := _join(parent, _split(String(cur["$uol"])))
			if target.is_empty() and String(cur["$uol"]) != "":
				return null
			var rest := segs.slice(i)
			segs = target
			segs.append_array(rest)
			i = 0
			walked = []
			cur = tree
			continue
		if i >= segs.size():
			return cur
		if not (cur is Dictionary):
			return null
		var d: Dictionary = cur
		var key := segs[i]
		if not d.has(key):
			return null
		cur = d[key]
		walked.append(key)
		i += 1
	return null


## Pixel region of a canvas inside its atlas page.
static func region(canvas: Dictionary) -> Rect2:
	var c: Variant = canvas.get("$canvas")
	if not (c is Array) or (c as Array).size() < 5:
		return Rect2()
	return Rect2(float(c[1]), float(c[2]), float(c[3]), float(c[4]))


## Page index of a canvas (-1 when the value is not a canvas).
static func page_of(canvas: Dictionary) -> int:
	var c: Variant = canvas.get("$canvas")
	if not (c is Array) or (c as Array).size() < 5:
		return -1
	return int(c[0])


## True for `{"$canvas": [...]}` values.
static func is_canvas(v: Variant) -> bool:
	return v is Dictionary and (v as Dictionary).has("$canvas")


## A `{"$v": [x, y]}` vector as Vector2 (`fallback` for anything else).
static func vec(v: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if v is Dictionary and (v as Dictionary).has("$v"):
		var a: Variant = v["$v"]
		if a is Array and (a as Array).size() >= 2:
			return Vector2(float(a[0]), float(a[1]))
	return fallback


## The atlas page texture holding a canvas (null when the page is missing).
func canvas_texture(canvas: Dictionary) -> Texture2D:
	return page_texture(page_of(canvas))


## Atlas page `i` as a texture, loaded on first use.
func page_texture(i: int) -> Texture2D:
	if i < 0 or i >= pages.size():
		return null
	if _page_tex[i] == null:
		var abs_path := cache_root.path_join(pages[i])
		var tex: Texture2D = null
		if _page_loader.is_valid():
			tex = _page_loader.call(abs_path)
		else:
			tex = load_page(abs_path)
		_page_tex[i] = tex
	return _page_tex[i]


## An AtlasTexture for a canvas (cached), for nodes that want a plain Texture2D. Batching renderers should instead
## draw `canvas_texture()` with `region()` so all canvases of a page share one texture.
func texture(canvas: Dictionary) -> AtlasTexture:
	var c: Variant = canvas.get("$canvas")
	if not (c is Array):
		return null
	var key := str(c)
	if _atlas.has(key):
		return _atlas[key]
	var page := canvas_texture(canvas)
	if page == null:
		return null
	var at := AtlasTexture.new()
	at.atlas = page
	at.region = region(canvas)
	at.filter_clip = true
	_atlas[key] = at
	return at


## Loads a PNG from an absolute path into an ImageTexture (null when it fails).
static func load_page(abs_path: String) -> Texture2D:
	if not FileAccess.file_exists(abs_path):
		push_warning("WzImg: missing atlas page %s" % abs_path)
		return null
	var img := Image.load_from_file(abs_path)
	if img == null or img.is_empty():
		push_warning("WzImg: cannot decode atlas page %s" % abs_path)
		return null
	return ImageTexture.create_from_image(img)


static func _split(p: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for s in p.split("/", false):
		out.append(s)
	return out


static func _join(base: PackedStringArray, rel: PackedStringArray) -> PackedStringArray:
	var out := base.duplicate()
	for s in rel:
		if s == "..":
			if out.is_empty():
				return PackedStringArray()
			out.resize(out.size() - 1)
		elif s != ".":
			out.append(s)
	return out
