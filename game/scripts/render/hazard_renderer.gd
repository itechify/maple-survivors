class_name HazardRenderer
extends Node2D
## Draws the boss ground hazards (GroundHazards, the poison mist of MobSkill 131, #459) with the level's `tile` art on one
## SpritePool: a fixed grid of puffs per hazard slot, each a random-looking but deterministic pick of the level's tile
## animations, so a hazard costs no Nodes and a few canvas items however often it is cast.
##
## A hazard's puffs are laid over its box (about one per PUFF_W x PUFF_H of it, at most MAX_PUFFS), each shifted by a
## hash of the hazard's draw identity (`generation`) so two casts do not look alike, with its own animation phase. The
## whole mist fades in and out over FADE seconds at the ends of its life.

## tier C: the spacing of the puff grid (the tiles are 100-150 px wide, so they overlap into one cloud) and the cap per hazard.
const PUFF_W := 80.0
const PUFF_H := 56.0
const MAX_PUFFS := 24
## tier C: seconds the mist fades in at its start and out at its end.
const FADE := 0.5
## tier C: the most a puff is shifted from its grid cell centre, in pixels.
const JITTER := Vector2(14.0, 8.0)

## Asset source; defaults to the "Assets" autoload.
var library: AssetLibrary

var _pool: SpritePool
var _anims: Dictionary = {}


func _ready() -> void:
	_ensure_pool()


## Draws every live hazard of `hazards` at sim time `now`.
func update_from(hazards: GroundHazards, now: float) -> void:
	_ensure_pool()
	_pool.ensure(hazards.capacity() * MAX_PUFFS)
	for slot in hazards.capacity():
		var shown := 0
		if hazards.is_live(slot, now):
			shown = _draw_hazard(hazards, slot, now)
		for puff in range(shown, MAX_PUFFS):
			_pool.hide(slot * MAX_PUFFS + puff)


## Number of puffs drawn.
func visible_count() -> int:
	return _pool.shown_count() if _pool != null else 0


## World positions (puff centres) of the puffs of the hazard at `slot`, as drawn: the layout, kept apart from drawing.
static func puff_positions(rect: Rect2, generation: int) -> PackedVector2Array:
	var cols := clampi(roundi(rect.size.x / PUFF_W), 1, MAX_PUFFS)
	var rows := clampi(roundi(rect.size.y / PUFF_H), 1, maxi(1, MAX_PUFFS / cols))
	var out := PackedVector2Array()
	for row in rows:
		for col in cols:
			var mix := _mix(generation, row * cols + col)
			var jitter := Vector2(float(mix & 0xff) / 255.0 * 2.0 - 1.0, float((mix >> 8) & 0xff) / 255.0 * 2.0 - 1.0)
			out.append(rect.position + Vector2((col + 0.5) * rect.size.x / cols, (row + 0.5) * rect.size.y / rows)
				+ jitter * JITTER)
	return out


func _draw_hazard(hazards: GroundHazards, slot: int, now: float) -> int:
	var count := int(hazards.tile_count[slot])
	if count <= 0:
		return 0
	var generation := int(hazards.generation[slot])
	var age := now - float(hazards.born[slot])
	var fade := fade_at(age, float(hazards.until[slot]) - now)
	var positions := puff_positions(hazards.rect(slot), generation)
	var shown := 0
	for puff in positions.size():
		var mix := _mix(generation, puff)
		var anim := _anim("%s/%d" % [hazards.tile_path[slot], (mix >> 16) % count])
		if anim == null:
			continue
		var t := age + float((mix >> 4) & 0x3ff) / 1024.0 * anim.total
		_pool.show(slot * MAX_PUFFS + shown, anim.frame_at(t, true), positions[puff].round(), false,
			anim.alpha_at(t, true) * fade)
		shown += 1
	return shown


## Opacity factor of a mist `age` s after it was placed and `left` s before it ends: 0 at both ends, 1 between the fades.
static func fade_at(age: float, left: float) -> float:
	return minf(clampf(age / FADE, 0.0, 1.0), clampf(left / FADE, 0.0, 1.0))


static func _mix(generation: int, puff: int) -> int:
	return ((generation * 2654435761 + puff * 40503 + 12345) * 1103515245 + 12345) & 0x7fffffff


func _anim(path: String) -> SpriteAnim:
	if not _anims.has(path):
		var lib := _lib()
		_anims[path] = lib.anim(path) if lib != null else null
	var a: SpriteAnim = _anims[path]
	return null if a == null or a.is_empty() else a


func _ensure_pool() -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())


func _lib() -> AssetLibrary:
	if library == null:
		library = AssetLibrary.get_default()
	return library
