class_name SafeZoneView
extends Node2D
## The look of the safe zone (M18, SafeZone, spec #425 SH4, docs/GAME_DESIGN.md 7.132): for each live zone a faint tinted
## box, a faint outline at its edge and the skill's `tile` animation looped over the box's floor as a row of puffs (one
## pooled RenderingServer canvas item per puff, no Nodes), and for each negated hit a pale "Guard" word that rises over the
## character (GuardLabels, put in the top container so nothing covers it). The skill's `effect` plays once at the cast
## through the ordinary `cast` event, not here.
##
## Works from data only: `begin` takes the zone's world box, its life and the cloud's art: one SpriteAnim, an Array of
## them (the puff VARIANTS of Smokescreen's `tile`, eleven two-frame puffs that each fade in and out, SH1 correction 3), or
## null for a cloud without art. Tier C (ours): the whole look. Puff `k` is drawn with variant `(k * VARIANT_STRIDE) mod n`
## standing on the floor line, spread every PUFF_STEP px over the box, the second puff of each pair shifted up PUFF_LIFT px;
## which WZ node is the cloud is the reading of SH1's contact sheet, confirmed by SH12's screenshot.

## tier C: the box tint and outline colours (faint, so the cloud shows without hiding the fight), the outline width.
const FILL := Color(0.78, 0.8, 0.92, 0.10)
const OUTLINE := Color(0.88, 0.9, 1.0, 0.42)
const OUTLINE_WIDTH := 1.0
## tier C: horizontal distance between two puffs, the lift of every second puff, and the most puffs one zone draws.
const PUFF_STEP := 64.0
const PUFF_LIFT := 16.0
const MAX_PUFFS := 20
## tier C: seconds the cloud fades in at its start and out at its end (or when it is replaced or the map changes).
const FADE := 0.4
## tier C: the "Guard" word: its text, size, seconds it lives, px it rises, colour, and the least seconds between two words
## (a monster touching the cloud's owner is negated every tick; the sim keeps every event, the screen shows a few).
const GUARD_TEXT := "Guard"
const GUARD_SIZE := 14
const GUARD_LIFE := 0.8
const GUARD_RISE := 26.0
const GUARD_COLOR := Color(0.86, 0.93, 1.0)
const GUARD_GAP := 0.4

## tier C: puff `k` shows variant `(k * VARIANT_STRIDE) mod n`, so neighbouring puffs differ in size (the stride is coprime
## with Smokescreen's eleven variants); the part of a puff's height that sinks below the floor line.
const VARIANT_STRIDE := 5
const PUFF_SINK := 8.0

## Asset source (unused by the view itself; the scene resolves the tile animation).
var library: AssetLibrary

var _pool: SpritePool
## One {skill, rect, floor_y, age, left, anim, ending} per drawn zone, oldest first.
var _zones: Array[Dictionary] = []
var _labels: GuardLabels
var _clock := 0.0
var _last_guard := -INF


## The container the "Guard" words are drawn in (give it the top container so they sit over everything).
func attach_labels(top: Node) -> void:
	_labels = GuardLabels.new()
	_labels.name = "GuardLabels"
	top.add_child(_labels)


func _ready() -> void:
	_ensure_pool()


## Starts drawing a zone: `rect` its world box, `total` its life in seconds, `floor_y` the line the puffs stand on, `art` the
## tile animation (a SpriteAnim, an Array of puff-variant SpriteAnims, or null for no art). A zone of the same skill already
## drawn is dropped first.
func begin(skill: String, rect: Rect2, total: float, floor_y: float, art: Variant) -> void:
	_drop(skill)
	_zones.append({"skill": skill, "rect": rect, "floor_y": floor_y, "age": 0.0, "left": total,
		"anims": usable_anims(art), "ending": false})
	queue_redraw()


## Ends the zone of `skill`: it fades out over FADE seconds (at once when `immediate`).
func finish(skill: String, immediate := false) -> void:
	if immediate:
		_drop(skill)
		return
	for zone: Dictionary in _zones:
		if String(zone.skill) == skill and not bool(zone.ending):
			zone.ending = true
			zone.left = minf(float(zone.left), FADE)


## A hit was negated at world `pos` (the character's head): shows a "Guard" word unless one started GUARD_GAP s ago.
func guard(pos: Vector2) -> void:
	if _labels == null or not guard_allowed(_last_guard, _clock):
		return
	_last_guard = _clock
	_labels.add(pos)


## Moves time on by `dt` seconds: ages and fades the zones, draws their puffs and the words.
func advance(dt: float) -> void:
	_ensure_pool()
	_clock += dt
	var i := 0
	while i < _zones.size():
		var zone := _zones[i]
		zone.age = float(zone.age) + dt
		zone.left = float(zone.left) - dt
		if float(zone.left) <= 0.0:
			_zones.remove_at(i)
		else:
			i += 1
	_pool.ensure(maxi(_zones.size(), 1) * MAX_PUFFS)
	for zi in _zones.size():
		var shown := _draw_puffs(zi)
		for puff in range(shown, MAX_PUFFS):
			_pool.hide(zi * MAX_PUFFS + puff)
	for slot in range(_zones.size() * MAX_PUFFS, _pool.size()):
		_pool.hide(slot)
	if _labels != null:
		_labels.advance(dt)
	queue_redraw()


## Number of zones drawn.
func zone_count() -> int:
	return _zones.size()


## Number of puffs drawn.
func puff_count() -> int:
	return _pool.shown_count() if _pool != null else 0


## Number of "Guard" words alive.
func guard_count() -> int:
	return _labels.count() if _labels != null else 0


## The non-empty animations in `art` (a SpriteAnim, an Array of them, or null), in order.
static func usable_anims(art: Variant) -> Array[SpriteAnim]:
	var out: Array[SpriteAnim] = []
	var list: Array = art if art is Array else [art]
	for item: Variant in list:
		if item is SpriteAnim and not (item as SpriteAnim).is_empty():
			out.append(item)
	return out


## The puff animations under the WZ node `path`: the node itself when it holds frames (one looping animation), otherwise
## each numbered child that does (Smokescreen's `tile/0..10`, a two-frame puff each). Empty when neither exists.
static func load_art(lib: AssetLibrary, path: String) -> Array[SpriteAnim]:
	var out: Array[SpriteAnim] = []
	if lib == null or path == "":
		return out
	var whole := lib.find_anim(path)
	if whole != null:
		out.append(whole)
		return out
	var node: Variant = lib.find(path)
	if node is Dictionary:
		for key: String in SpriteAnim.frame_keys(node):
			var variant := lib.find_anim(path + "/" + key)
			if variant != null:
				out.append(variant)
	return out


## Puff anchor positions of a zone: a row on the floor line every PUFF_STEP px across the box, every second one lifted
## PUFF_LIFT px, at most MAX_PUFFS. The layout, kept apart from drawing.
static func puff_positions(rect: Rect2, floor_y: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var count := clampi(roundi(rect.size.x / PUFF_STEP), 1, MAX_PUFFS)
	for k in count:
		var x := rect.position.x + (float(k) + 0.5) * rect.size.x / float(count)
		out.append(Vector2(x, floor_y - (PUFF_LIFT if k % 2 == 1 else 0.0)))
	return out


## Opacity factor of a zone `age` s after it began and `left` s before it ends: 0 at both ends, 1 between the fades.
static func fade_at(age: float, left: float) -> float:
	return minf(clampf(age / FADE, 0.0, 1.0), clampf(left / FADE, 0.0, 1.0))


## Whether a "Guard" word may start at `now` when the last one started at `last`.
static func guard_allowed(last: float, now: float) -> bool:
	return now - last >= GUARD_GAP


func _draw() -> void:
	for zone: Dictionary in _zones:
		var fade := fade_at(float(zone.age), float(zone.left))
		var rect: Rect2 = zone.rect
		draw_rect(rect, Color(FILL, FILL.a * fade), true)
		draw_rect(rect, Color(OUTLINE, OUTLINE.a * fade), false, OUTLINE_WIDTH)


func _draw_puffs(zi: int) -> int:
	var zone := _zones[zi]
	var anims: Array = zone.anims
	if anims.is_empty():
		return 0
	var fade := fade_at(float(zone.age), float(zone.left))
	var positions := puff_positions(zone.rect, float(zone.floor_y))
	for puff in positions.size():
		var anim: SpriteAnim = anims[(puff * VARIANT_STRIDE) % anims.size()]
		# Each puff starts at its own phase of the loop so the row does not pulse in step.
		var t := float(zone.age) + anim.total * float(puff) / float(maxi(1, positions.size()))
		var frame := anim.frame_at(t, true)
		# The puff stands on the floor line: its bottom edge (origin-relative) sits PUFF_SINK px under it.
		var at := positions[puff] - Vector2(0.0, frame.region.size.y - frame.origin.y - PUFF_SINK)
		_pool.show(zi * MAX_PUFFS + puff, frame, at.round(), false, anim.alpha_at(t, true) * fade)
	return positions.size()


func _drop(skill: String) -> void:
	for i in _zones.size():
		if String(_zones[i].skill) == skill:
			_zones.remove_at(i)
			queue_redraw()
			return


func _ensure_pool() -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())


## The "Guard" words: each rises GUARD_RISE px over GUARD_LIFE seconds while it fades out.
class GuardLabels extends Node2D:
	var _items: Array[Dictionary] = []
	var _font: Font

	func add(pos: Vector2) -> void:
		_items.append({"pos": pos, "age": 0.0})
		queue_redraw()

	func advance(dt: float) -> void:
		var i := 0
		while i < _items.size():
			_items[i].age = float(_items[i].age) + dt
			if float(_items[i].age) >= GUARD_LIFE:
				_items.remove_at(i)
			else:
				i += 1
		queue_redraw()

	func count() -> int:
		return _items.size()

	func _draw() -> void:
		if _font == null:
			_font = HudWidget.make_font()
		for item: Dictionary in _items:
			var k := clampf(float(item.age) / GUARD_LIFE, 0.0, 1.0)
			var p: Vector2 = (item.pos as Vector2) + Vector2(0.0, -GUARD_RISE * k)
			var alpha := 1.0 - k
			var width := _font.get_string_size(GUARD_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, GUARD_SIZE).x
			var at := Vector2(roundf(p.x - width * 0.5), roundf(p.y))
			draw_string_outline(_font, at, GUARD_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, GUARD_SIZE, 3, Color(0, 0, 0, 0.85 * alpha))
			draw_string(_font, at, GUARD_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, GUARD_SIZE, Color(GUARD_COLOR, alpha))
