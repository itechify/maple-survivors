class_name PetRenderer
extends Node2D
## Draws the pet out (spec #34, ticket #120) from the simulation's pet state (RunWorld.pet_state() or the Free Market's):
## the Item.wz/Pet/<species>.img animation that matches its action, at its real frame delays and origins, mirrored to
## face its direction of travel. No name tag and no chat balloon. One SpritePool slot: the canvas item is re-recorded
## only when the frame changes, and moving the pet moves the node (an item transform), so a pet costs two cheap calls
## per frame.
##
## Item.wz/Pet frames face left (like every MapleStory sprite), so facing right mirrors around the frame origin.
## The origin is the pet's feet. The owner reparents this node into the actor layer of the pet's foothold layer, just
## behind the player's avatar (RunScene._place_pet_layer, FreeMarket._present).

## tier C: action (PetSystem.action) -> Item.wz/Pet animation. Item.wz/Pet has no speed/behaviour data, only frames.
const ANIM_BY_ACTION := {"stand": "stand0", "move": "move", "jump": "jump", "hang": "hang"}
## tier C (ours): px the hanging pet is drawn beside the climbing character (the sim keeps it on the player's position).
const HANG_SIDE := 22.0
## tier C: a pet running to a drop (Wing Boots) that is in the air flies (2 frames) instead of the one-frame jump.
const FLY_ANIM := "fly"

var library: AssetLibrary
## The animation shown now ("stand0", "move", ...; "" before the first state).
var shown_anim := ""

var _pool: SpritePool
var _species := 0
var _anim: SpriteAnim
var _time := 0.0


func _ready() -> void:
	_ensure_pool()


## The Item.wz/Pet animation name for a simulated action (`fetching`: the pet is running to a drop).
static func anim_name(action: String, fetching: bool) -> String:
	if fetching and action == "jump":
		return FLY_ANIM
	return String(ANIM_BY_ACTION.get(action, "stand0"))


## The asset path of one of a species' animations.
static func anim_path(species: int, anim: String) -> String:
	return "Item.wz/Pet/%07d.img/%s" % [species, anim]


## Where a hanging pet is drawn relative to its simulated position, which is the player's own while the player climbs:
## HANG_SIDE px to the side the player is not facing, so the pet is seen hanging on the rope beside the character
## instead of exactly behind it.
static func hang_offset(action: String, facing: int) -> Vector2:
	return Vector2(-float(facing) * HANG_SIDE, 0.0) if action == "hang" else Vector2.ZERO


## Whether a pet facing `facing` (-1 left, 1 right) is drawn mirrored (the art faces left).
static func flipped(facing: int) -> bool:
	return facing > 0


## Draws the pet described by `view` (PetSystem.view(); {} hides it) after `dt` seconds.
func show_state(view: Dictionary, dt: float) -> void:
	if view.is_empty():
		hide_pet()
		return
	_ensure_pool()
	var species := int(view.species)
	var name := anim_name(String(view.action), bool(view.get("fetching", false)))
	if name != shown_anim or species != _species or _anim == null:
		_load(species, name)
	else:
		_time += dt
	var pos: Vector2 = view.pos
	position = (pos + hang_offset(String(view.action), int(view.facing))).round()
	visible = true
	if _anim == null or _anim.is_empty():
		_pool.hide(0)
		return
	_pool.show(0, _anim.frame_at(_time, true), Vector2.ZERO, flipped(int(view.facing)), _anim.alpha_at(_time, true))


## Hides the pet (none out).
func hide_pet() -> void:
	visible = false


## Restarts the animation cycle (after a teleport the pet starts fresh where it lands).
func snap() -> void:
	_time = 0.0


## Number of frames of the animation shown now.
func frame_count() -> int:
	return _anim.frame_count() if _anim != null else 0


func _load(species: int, name: String) -> void:
	_species = species
	shown_anim = name
	_time = 0.0
	if library == null:
		library = AssetLibrary.get_default()
	_anim = library.anim(anim_path(species, name))


func _ensure_pool() -> void:
	if _pool == null:
		_pool = SpritePool.new(get_canvas_item())
		_pool.ensure(1)
