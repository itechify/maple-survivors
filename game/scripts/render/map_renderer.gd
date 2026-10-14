class_name MapRenderer
extends Node2D
## Draws a v83 map from the asset cache: backgrounds, layers 0-7 (objs, tiles, actors), portals, front backgrounds.
##
## Draw order (docs/ARCHITECTURE.md 4.5, docs/research/prior-art.md section 3, WzComparerR2 MapRender2):
##   non-front backs -> for layer 0..7: objs (by obj z, then index), tiles (by tile canvas z, then index), the layer's
##   actor container -> portals -> front backs.
## Obj sprites come from Map.wz/Obj/<oS>.img/<l0>/<l1>/<l2> (several frames animate with their delays, one canvas is
## static), tiles from Map.wz/Tile/<tS>.img/<u>/<no> with tS from the layer's info. Sprites are drawn at pos - origin,
## mirrored around pos when f = 1. Static runs are recorded once; only animated sprites and backgrounds redraw.
## Visible portals (pt 2) use MapHelper.img/portal/game/pv.
##
## The camera is read every frame from `camera` (any Camera2D) when set, else from set_view().

const LAYER_COUNT := 8
const PORTAL_ANIM := "Map.wz/MapHelper.img/portal/game/pv"
## Visible portal type.
const PT_VISIBLE := 2

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary
## Camera to follow for backgrounds (optional; see set_view()).
var camera: Camera2D
## Draw pt 2 portals.
var show_portals := true

## Loaded map.
var map_id := 0
var map_path := ""
var map_root: Dictionary = {}
## Footholds and camera bounds of the loaded map (sim classes, built here for convenience).
var footholds: FootholdMap
var bounds := Rect2()
## Lookups that failed while building (should be empty for a complete cache).
var missing: PackedStringArray = []
## Counts of what was built: backs, fronts, objs, tiles, animated, portals, runs.
var stats: Dictionary = {}
## Camera centre / view size in world pixels and seconds since load.
var cam_center := Vector2.ZERO
var view_size := Vector2(800, 600)
var time := 0.0

var _back: MapBackLayer
var _front: MapBackLayer
var _layers: Array[Node2D] = []
var _actors: Array[Node2D] = []
var _animated: Array[MapDrawList] = []


func _init() -> void:
	process_priority = 10


## Loads and builds a map by id. Returns false when the map img is not in the cache.
func load_map(id: int) -> bool:
	map_id = id
	return load_map_path(AssetLibrary.map_img_path(id))


## Loads and builds a map by WZ img path.
func load_map_path(path: String) -> bool:
	clear()
	map_path = path
	var w := _lib().img(path) if _lib() != null else null
	if w == null:
		missing.append(path)
		return false
	build(w.root)
	return true


## Builds every draw run from a map img root (cache JSON). Missing sprites are listed in `missing`.
func build(root: Dictionary) -> void:
	clear()
	map_root = root
	stats = {"backs": 0, "fronts": 0, "objs": 0, "tiles": 0, "animated": 0, "portals": 0, "runs": 0}
	footholds = FootholdMap.from_wz(root)
	bounds = MapBounds.from_map(root, footholds)
	var backs := resolve_backs(root)
	_back = MapBackLayer.new()
	_back.name = "Backs"
	_front = MapBackLayer.new()
	_front.name = "Fronts"
	for b: Dictionary in backs:
		if b.front:
			_front.backs.append(b)
		else:
			_back.backs.append(b)
	stats.backs = _back.backs.size()
	stats.fronts = _front.backs.size()
	add_child(_back)
	for layer in LAYER_COUNT:
		var node := Node2D.new()
		node.name = "Layer%d" % layer
		add_child(node)
		_layers.append(node)
		_emit_runs(node, layer_items(root, layer))
		var actors := Node2D.new()
		actors.name = "Actors%d" % layer
		node.add_child(actors)
		_actors.append(actors)
	if show_portals:
		var portals := Node2D.new()
		portals.name = "Portals"
		add_child(portals)
		_emit_runs(portals, portal_items(root))
	add_child(_front)
	_sync_backs()


## Removes everything built.
func clear() -> void:
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_layers.clear()
	_actors.clear()
	_animated.clear()
	_back = null
	_front = null
	missing = []
	time = 0.0


## The container drawn right after layer `layer`'s tiles: put actors standing on that layer's footholds here.
func actor_layer(layer: int) -> Node2D:
	if _actors.is_empty():
		return null
	return _actors[clampi(layer, 0, _actors.size() - 1)]


## Sets the camera centre and view size used by the backgrounds (when `camera` is not set).
func set_view(center: Vector2, size: Vector2) -> void:
	cam_center = center
	view_size = size
	_sync_backs()


func _process(delta: float) -> void:
	advance(delta)


## Advances animations and redraws backgrounds for the current camera.
func advance(delta: float) -> void:
	time += delta
	if camera != null:
		cam_center = camera.get_screen_center_position()
		view_size = camera.get_viewport_rect().size / camera.zoom
	for r in _animated:
		r.advance(delta)
	_sync_backs()


## The background entries of a map img: resolved animations plus their parameters (missing ones are listed).
func resolve_backs(root: Dictionary) -> Array:
	var out: Array = []
	var back: Variant = root.get("back", {})
	if not (back is Dictionary):
		return out
	for k in SpriteAnim.frame_keys(back):
		var b: Variant = back[k]
		if not (b is Dictionary):
			continue
		var bs := str(b.get("bS", ""))
		if bs == "":
			continue
		var ani := int(b.get("ani", 0)) == 1
		var path := "Map.wz/Back/%s.img/%s/%d" % [bs, "ani" if ani else "back", int(b.get("no", 0))]
		var a := _anim(path)
		if a == null:
			continue
		out.append({
			"anim": a, "path": path, "ani": ani,
			"pos": Vector2(float(b.get("x", 0)), float(b.get("y", 0))),
			"r": Vector2(float(b.get("rx", 0)), float(b.get("ry", 0))),
			"type": int(b.get("type", 0)),
			"c": Vector2(float(b.get("cx", 0)), float(b.get("cy", 0))),
			"alpha": clampf(float(b.get("a", 255)) / 255.0, 0.0, 1.0),
			"flip": int(b.get("f", 0)) == 1,
			"front": int(b.get("front", 0)) == 1,
		})
	return out


## The sprites of one layer in draw order: objs sorted by (z, index), then tiles sorted by (canvas z, index).
## Entries: {"anim", "pos", "flip", "kind", "z", "index", "path"}.
func layer_items(root: Dictionary, layer: int) -> Array:
	var objs: Array = []
	var tiles: Array = []
	var node: Variant = root.get(str(layer), {})
	if not (node is Dictionary):
		return []
	var obj: Variant = node.get("obj", {})
	if obj is Dictionary:
		for k in SpriteAnim.frame_keys(obj):
			var o: Variant = obj[k]
			if not (o is Dictionary):
				continue
			var path := "Map.wz/Obj/%s.img/%s/%s/%s" % [o.get("oS", ""), o.get("l0", ""), o.get("l1", ""), o.get("l2", "")]
			var a := _anim(path)
			if a == null:
				continue
			objs.append({"anim": a, "pos": Vector2(float(o.get("x", 0)), float(o.get("y", 0))),
				"flip": int(o.get("f", 0)) == 1, "kind": "obj", "z": int(o.get("z", 0)), "index": int(k), "path": path})
	var tile: Variant = node.get("tile", {})
	var info: Variant = node.get("info", {})
	var ts := str(info.get("tS", "")) if info is Dictionary else ""
	if tile is Dictionary and not (tile as Dictionary).is_empty():
		for k in SpriteAnim.frame_keys(tile):
			var t: Variant = tile[k]
			if not (t is Dictionary):
				continue
			var path := "Map.wz/Tile/%s.img/%s/%d" % [ts, t.get("u", ""), int(t.get("no", 0))]
			var a := _anim(path)
			if a == null:
				continue
			var z: Variant = a.frames[0].z
			tiles.append({"anim": a, "pos": Vector2(float(t.get("x", 0)), float(t.get("y", 0))), "flip": false,
				"kind": "tile", "z": int(z) if z != null else 0, "index": int(k), "path": path})
	objs.sort_custom(_by_z_index)
	tiles.sort_custom(_by_z_index)
	return objs + tiles


## Visible (pt 2) portals as animated sprites.
func portal_items(root: Dictionary) -> Array:
	var out: Array = []
	var portal: Variant = root.get("portal", {})
	if not (portal is Dictionary):
		return out
	for k in SpriteAnim.frame_keys(portal):
		var p: Variant = portal[k]
		if p is Dictionary and int(p.get("pt", -1)) == PT_VISIBLE:
			var a := _anim(PORTAL_ANIM)
			if a == null:
				break
			out.append({"anim": a, "pos": Vector2(float(p.get("x", 0)), float(p.get("y", 0))), "flip": false,
				"kind": "portal", "z": 0, "index": int(k), "path": PORTAL_ANIM})
	return out


## True when an entry must redraw over time (several frames or an alpha ramp).
static func is_animated(a: SpriteAnim) -> bool:
	return a.frame_count() > 1 or (a.frame_count() == 1 and a.frames[0].a0 != a.frames[0].a1)


func _emit_runs(parent: Node2D, items: Array) -> void:
	var run: MapDrawList = null
	for it: Dictionary in items:
		match it.kind:
			"obj":
				stats.objs += 1
			"tile":
				stats.tiles += 1
			"portal":
				stats.portals += 1
		if is_animated(it.anim):
			var single := MapDrawList.new()
			single.animated = true
			single.add(it.anim, it.pos, it.flip)
			parent.add_child(single)
			_animated.append(single)
			stats.animated += 1
			stats.runs += 1
			run = null
			continue
		if run == null:
			run = MapDrawList.new()
			parent.add_child(run)
			stats.runs += 1
		run.add(it.anim, it.pos, it.flip)


func _sync_backs() -> void:
	for layer: MapBackLayer in [_back, _front]:
		if layer == null:
			continue
		layer.cam_center = cam_center
		layer.view_size = view_size
		layer.time = time
		layer.queue_redraw()


func _anim(path: String) -> SpriteAnim:
	var lib := _lib()
	var a: SpriteAnim = lib.find_anim(path) if lib != null else null
	if a == null or a.frames[0].page == null:
		if not (path in missing):
			missing.append(path)
		return null
	return a


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library


static func _by_z_index(a: Dictionary, b: Dictionary) -> bool:
	if a.z != b.z:
		return a.z < b.z
	return a.index < b.index
