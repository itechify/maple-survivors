class_name MountLayers
extends RefCounted
## What an AvatarRenderer draws while a running form names a mount (spec #384 M20, the Corsair's Battleship): the mount's
## rear canvas under the avatar, its front canvas over it, the rider seated on it. No nodes, files or RNG: it holds a
## MountArt, a stance clock and the layout of the current frame, and AvatarRenderer draws what it lays out.
##
## Attachment (tier B/C, the standard Maple rule, C1 #385): every mount canvas and the rider body are placed so that
## their `map/navel` points meet. The front canvas sits on the mount's origin (the ground under the feet), the rear one
## on the same navel point, and the rider's origin goes to `mount navel - rider body navel` ((8, -21) on the ship's
## stand1 with the seated body). The navels are read per frame: they drift with the ship's bobbing. The whole group
## mirrors with the facing about the mount's origin, which is the avatar's origin.
##
## Stances (tier B/C, C1's contact sheets): the mount plays `stand1` standing, `walk1` walking, `jump` airborne, `prone`
## down, the named cast stance (`cannon`, `torpedo`, `fireburner`, `coolingeffect`) while that action plays and `alert2`
## for any other action or for the idle alert. The rider's body is `sit` except during those named casts (whose
## body actions exist); while climbing the mount is hidden and the rider climbs normally. A mount without a stance of the
## wanted name hides for that stance instead of drawing another.

## tier B/C: the actions the rider and the mount both play by name (Battleship Cannon, Torpedo, Flamethrower, Ice Splitter).
const CAST_STANCES := ["cannon", "torpedo", "fireburner", "coolingeffect"]
## tier B/C: the rider's body action on the mount whenever it is not one of CAST_STANCES.
const RIDER_STANCE := "sit"
## tier B/C: the mount stance for the idle alert and any action without a stance of its own.
const FALLBACK_STANCE := "alert2"
## Stances where the character climbs: no mount, the rider keeps its own stance.
const CLIMB_STANCES := ["ladder", "rope", "ladder2", "rope2"]
## Stances that end the ride visually (the character lies dead).
const DEAD_STANCES := ["dead"]
## avatar stance request -> mount stance for the movement stances.
const MOTION_STANCES := {"stand1": "stand1", "stand2": "stand1", "walk1": "walk1", "walk2": "walk1",
	"jump": "jump", "prone": "prone", "proneStab": "prone"}
## Mount stances that play once and hold their last frame; everything else loops.
const ONE_SHOT_STANCES := ["cannon", "torpedo", "fireburner", "coolingeffect", "jump"]

## The loaded art (never null).
var art: MountArt
## The mount stance playing ("" when hidden) and the seconds in it.
var stance := ""
var time := 0.0
## The frame of the current stance (null when hidden) and the layout of the last layout() call: where each canvas' origin
## goes (unflipped, relative to the avatar origin) and where the rider's origin goes.
var frame: MountArt.Frame
var rear_pos := Vector2.ZERO
var front_pos := Vector2.ZERO
var rider_offset := Vector2.ZERO
var _index := 0


func _init(p_art: MountArt = null) -> void:
	art = p_art if p_art != null else MountArt.new()


## The mount stance for the avatar stance requested (`stand1`, `walk1`, `cannon`, ...): "" while climbing or dead.
static func mount_stance(request: String) -> String:
	if request in CLIMB_STANCES or request in DEAD_STANCES:
		return ""
	if request in CAST_STANCES:
		return request
	return String(MOTION_STANCES.get(request, FALLBACK_STANCE))


## The rider's body stance for the avatar stance requested: the named cast, the climbing and dead stances as they are,
## `sit` for everything else.
static func rider_stance(request: String) -> String:
	if request in CAST_STANCES or request in CLIMB_STANCES or request in DEAD_STANCES:
		return request
	return RIDER_STANCE


## Names the avatar stance now requested. The mount stance changes (rewinding its clock) when the request maps to another
## one, and `restart` rewinds the same one (the same cast begun again). Returns true when the frame changed.
func request(avatar_stance: String, restart: bool = false) -> bool:
	var wanted := mount_stance(avatar_stance)
	if wanted != "" and not art.has_stance(wanted):
		wanted = ""
	if wanted == stance and not restart:
		return false
	stance = wanted
	time = 0.0
	return _refresh()


## Advances the stance clock; returns true when another frame is now shown.
func advance(dt: float) -> bool:
	if stance == "":
		return false
	time += dt
	return _refresh()


## True when the mount is drawn now.
func is_visible() -> bool:
	return frame != null


## Lays out the current frame around the avatar: `rider_navel` is the avatar body's `navel` anchor relative to its origin
## in the stance it plays (body_navel). Sets rear_pos, front_pos and rider_offset; the offsets are zero while hidden.
func layout(rider_navel: Vector2) -> void:
	rear_pos = Vector2.ZERO
	front_pos = Vector2.ZERO
	rider_offset = Vector2.ZERO
	if frame == null:
		return
	var anchor_canvas: SpriteFrame = frame.front if frame.front != null else frame.rear
	var anchor := MountArt.Frame.navel(anchor_canvas)
	if frame.front != null:
		front_pos = Vector2.ZERO
	if frame.rear != null:
		rear_pos = anchor - MountArt.Frame.navel(frame.rear) if frame.front != null else Vector2.ZERO
	rider_offset = anchor - rider_navel


## The avatar body's `navel` anchor (relative to the avatar origin) from the parts of AvatarRenderer.compose: the `body`
## canvas' position plus its `map/navel`; ZERO when no part is the body.
static func body_navel(parts: Array) -> Vector2:
	for p: Dictionary in parts:
		if String(p.get("name", "")) == "body":
			var m: Dictionary = p.get("map", {})
			return (p.pos as Vector2) + (m.get("navel", Vector2.ZERO) as Vector2)
	return Vector2.ZERO


## Index of the frame shown in the current stance (0 while hidden).
func index_of_frame() -> int:
	return _index


func _refresh() -> bool:
	if stance == "":
		var had := frame != null
		frame = null
		_index = 0
		return had
	var i := art.index_at(stance, time, not (stance in ONE_SHOT_STANCES))
	var list := art.frames(stance)
	var f: MountArt.Frame = list[i]
	var changed := f != frame
	frame = f
	_index = i
	return changed
