class_name EchoCloneRenderer
extends Node2D
## Draws the echo clones (docs/GAME_DESIGN.md 7.94.7): the `PlayerSummons` entries whose definition carries `summon.echo`
## (Night Lord's Shadow Partner). A clone is a shadow silhouette from the WZ `special/<action>/<frame>` sets (origins
## included); those sets have no `delay`, so timing comes from the owner's body stance of the same action. The clone mirrors
## the owner's stance and frame, mirrors its facing, and plays a throw stance of its own when `echo_cast` reports its star
## leaving its hand. A cache without the `special` node falls back to the owner's own sprite at half alpha (tier C).
##
## Presentation only: positions, lifetimes and the facing come from the fixed-tick `PlayerSummons`; the clone's
## stand/walk pose follows the owner's, never the simulation.

## tier A: Skill.wz/411.img/skill/4111002/special has 34 action sets (NL1 #400); every other action falls back to `stand1`.
const FALLBACK_ACTION := "stand1"
## The owner's stances the `special` sets spell differently: the alert variants share `alert`, the second ladder/rope stance
## is the same pose (tier C: our mapping, the owner's action stream was read in NL10 #409).
const ACTION_ALIASES := {"alert2": "alert", "alert3": "alert", "alert4": "alert", "ladder2": "ladder", "rope2": "rope"}
## tier C: the throw stance of a skill whose own action the `special` sets lack (Avenger's `avenger`, Ninja Storm's ...).
const THROW_FALLBACK := "shoot1"
## tier C: seconds per frame of a throw whose owner stance is unknown (SpriteAnim.DEFAULT_DELAY, the WZ default).
const DEFAULT_FRAME_TIME := 0.1
## tier C (ours): the avatar fallback is drawn at half alpha.
const GHOST_ALPHA := 0.5

var library: AssetLibrary
var _pool: SpritePool
var _ghost: SpritePool
var _anims := {}
var _has_special := {}
## Per clone slot: the spawn serial a throw belongs to, its action, clock, per-frame times and the side thrown toward.
var _throw_uid := PackedInt64Array()
var _throw_action: PackedStringArray = []
var _throw_t := PackedFloat64Array()
var _throw_delays: Array[PackedFloat32Array] = []
var _throw_facing := PackedInt32Array()


## The `special` action drawn for the owner's stance: the stance itself, its alias, else `stand1`.
static func special_action(special: Dictionary, stance: String) -> String:
	if special.get(stance) is Dictionary:
		return stance
	var alias := String(ACTION_ALIASES.get(stance, ""))
	if alias != "" and special.get(alias) is Dictionary:
		return alias
	return FALLBACK_ACTION


## The `special` action of a clone's throw: the echoed skill's own action when the sets have it, else `shoot1`.
static func throw_action(special: Dictionary, skill_action: String) -> String:
	return skill_action if special.get(skill_action) is Dictionary else THROW_FALLBACK


## The clone's frame for the owner's frame `owner_frame` of `owner_frames`: the same position along the set (first to first,
## last to last), so a set with another frame count than the owner's body action still plays through completely.
static func frame_for(frames: int, owner_frames: int, owner_frame: int) -> int:
	if frames <= 1 or owner_frames <= 1:
		return 0
	return clampi(roundi(float(owner_frame) * float(frames - 1) / float(owner_frames - 1)), 0, frames - 1)


## The index of the frame shown `t` seconds into a throw of `frames` frames timed by the owner's per-frame `delays`
## (holds the last frame once finished; the owner's own frame times, scaled onto the set when the counts differ).
static func throw_frame(frames: int, delays: PackedFloat32Array, t: float) -> int:
	if frames <= 1:
		return 0
	var owner_index := delays.size() - 1
	var acc := 0.0
	for i in delays.size():
		acc += delays[i]
		if t < acc:
			owner_index = i
			break
	return frame_for(frames, delays.size(), owner_index) if not delays.is_empty() \
		else clampi(floori(t / DEFAULT_FRAME_TIME), 0, frames - 1)


## Total seconds of a throw with these `delays` (DEFAULT_FRAME_TIME per frame when the owner's stance is unknown).
static func throw_duration(frames: int, delays: PackedFloat32Array) -> float:
	var total := 0.0
	for d in delays:
		total += d
	return total if not delays.is_empty() else DEFAULT_FRAME_TIME * frames


## Starts the throw stance of clone `slot` (an `echo_cast` event): `special` is the clone's sets, `skill_action` the echoed
## skill's body action, `delays` that body action's frame times, `facing` the side thrown toward.
func start_throw(summons: PlayerSummons, slot: int, skill_action: String, delays: PackedFloat32Array, facing: int) -> void:
	if slot < 0 or slot >= summons.active.size():
		return
	_ensure_throw(slot + 1)
	_throw_uid[slot] = summons.uid[slot]
	_throw_action[slot] = skill_action
	_throw_t[slot] = 0.0
	_throw_delays[slot] = delays
	_throw_facing[slot] = facing


## Whether clone `slot` is in a throw stance now.
func is_throwing(slot: int) -> bool:
	return slot < _throw_t.size() and _throw_t[slot] >= 0.0


## Presents every living clone. `pose` is the owner's: {stance, frame, frames} (its avatar stance, frame index and frame
## count) and {alpha}; `parts` is the owner's current sprite parts (the half-alpha fallback only).
func update_from(summons: PlayerSummons, pose: Dictionary, delta: float, parts: Array = []) -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())
		_ghost = SpritePool.new(get_canvas_item())
	_pool.ensure(summons.active.size())
	var ghosts := 0
	for i in summons.active.size():
		if summons.active[i] == 0 or not summons.definitions[i].has("echo"):
			_pool.hide(i)
			continue
		var base := String(summons.definitions[i].echo.get("path", ""))
		var special := _special_node(base)
		var pos := Vector2(roundf(summons.x[i]), roundf(summons.y[i]))
		var facing := int(summons.facing[i])
		var action := ""
		var frame := 0
		var timed := false
		_ensure_throw(i + 1)
		if _throw_t[i] >= 0.0 and _throw_uid[i] != summons.uid[i]:
			_throw_t[i] = -1.0 # a replaced clone does not inherit the previous one's throw
		if _throw_t[i] >= 0.0:
			action = throw_action(special, String(_throw_action[i]))
			var frames := _frames(base, action)
			var delays: PackedFloat32Array = _throw_delays[i]
			frame = throw_frame(frames, delays, _throw_t[i])
			facing = _throw_facing[i]
			timed = true
			_throw_t[i] += delta
			if _throw_t[i] >= throw_duration(frames, delays):
				_throw_t[i] = -1.0
		if not timed:
			action = special_action(special, String(pose.stance))
			frame = frame_for(_frames(base, action), int(pose.frames), int(pose.frame))
		var alpha := float(pose.get("alpha", 1.0))
		var anim := _anim(base, action)
		if anim != null and not anim.is_empty():
			_pool.show(i, anim.frames[mini(frame, anim.frame_count() - 1)], pos, facing > 0, alpha)
			continue
		_pool.hide(i)
		# tier C: no `special` in this cache: the owner's own sprite at half alpha.
		var mirror := -1.0 if facing > 0 else 1.0
		for part: Dictionary in parts:
			_ghost.ensure(ghosts + 1)
			var f: SpriteFrame = part.frame
			if f.page == null:
				continue
			var at := pos + Vector2(mirror * (part.pos as Vector2).x, (part.pos as Vector2).y)
			_ghost.show(ghosts, f, at, facing > 0, alpha * GHOST_ALPHA)
			ghosts += 1
	_pool.hide_from(summons.active.size())
	if _ghost != null:
		_ghost.hide_from(ghosts)


func _ensure_throw(n: int) -> void:
	while _throw_t.size() < n:
		_throw_uid.append(0)
		_throw_action.append("")
		_throw_t.append(-1.0)
		_throw_delays.append(PackedFloat32Array())
		_throw_facing.append(-1)


func _special_node(base: String) -> Dictionary:
	if base == "" or library == null:
		return {}
	if not _has_special.has(base):
		var node: Variant = library.find(base)
		_has_special[base] = node if node is Dictionary else {}
	return _has_special[base]


func _anim(base: String, action: String) -> SpriteAnim:
	var path := base + "/" + action
	if not _anims.has(path):
		_anims[path] = library.find_anim(path) if library != null and base != "" else null
	return _anims[path]


func _frames(base: String, action: String) -> int:
	var anim := _anim(base, action)
	return anim.frame_count() if anim != null else 0
