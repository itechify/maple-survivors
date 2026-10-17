class_name FreeMarketMotion
extends RefCounted
## Hub-only player motion and portals. No combat systems or round clock exist here. With a pet out (set_pet), the hub
## runs the same PetSystem follow controller as a round (spec #34, #120), with no drops to pick up.

const MAP_ID := 910000000 # tier A: original v83 Free Market Entrance.
var player := PlayerMotion.new()
var fhm: FootholdMap
var ladders: LadderSet
var bounds: Rect2
var portals: PortalSet
## The pet following the player (PetSystem), null without one.
var pet: PetSystem

var _constants: PhysicsConstants
var _no_drops := PickupSystem.new(1)


func _init(map_img: Dictionary = {}, physics: Dictionary = {}, balance: Dictionary = {}) -> void:
	fhm = FootholdMap.from_wz(map_img)
	ladders = LadderSet.from_wz(map_img)
	bounds = MapBounds.from_map(map_img, fhm)
	_constants = PhysicsConstants.from_wz(physics)
	player = PlayerMotion.new(_constants)
	# tier C: owner #32/#71 enables only out00; rooms stay inert even if malformed data names a local target.
	var local := map_img.duplicate(true)
	var nodes: Dictionary = local.get("portal", {})
	for key: String in nodes.keys():
		var name := String(nodes[key].get("pn", ""))
		if name.begins_with("in") or name == "out00":
			nodes.erase(key)
	portals = PortalSet.from_wz(local, MAP_ID, balance.get("portals", {}))
	for p: Dictionary in map_img.get("portal", {}).values():
		if String(p.get("pn", "")) == "out00" and int(p.get("pt", -1)) == 7:
			var pos := Vector2(float(p.x), float(p.y))
			portals.links.append({"name": "out00", "target": "", "pos": pos, "target_pos": pos})
	var rng := RandomNumberGenerator.new()
	rng.seed = 0 # tier C: stable hub arrival; no gameplay randomness or saved hub position.
	player.place(PortalSet.start_point(map_img, fhm, bounds, rng), fhm)


## Puts the pet `species` out beside the player (`tuning`: the survivor "pet" block of cash_items.json). The hub pet has
## no upgrades: it only follows.
func set_pet(species: int, tuning: Dictionary) -> void:
	pet = PetSystem.new(species, {}, tuning, _constants)
	pet.place(player.pos, fhm)
	pet.motion.facing = player.facing


## What the pet looks like now ({} without one); same shape as RunWorld.pet_state().
func pet_state() -> Dictionary:
	return pet.view() if pet != null else {}


## Advances movement and returns portal_used, exit_requested or pet_teleported events.
func step(dt: float, input: MoveInput) -> Array[Dictionary]:
	var used := portals.step(dt, player.pos, input.up)
	if not used.is_empty():
		if used.portal == "out00":
			return [{"type": "exit_requested"}]
		player.place(used.pos, fhm)
		var events: Array[Dictionary] = [{"type": "portal_used", "portal": used.portal, "target": used.target,
			"pos": used.pos}]
		if pet != null:
			var from := pet.motion.pos
			pet.place(player.pos, fhm)
			pet.motion.facing = player.facing
			events.append({"type": "pet_teleported", "from": from, "pos": pet.motion.pos})
		return events
	player.step(dt, input, fhm, ladders, bounds)
	var out: Array[Dictionary] = []
	if pet != null:
		var pet_events := []
		pet.step(dt, player, fhm, bounds, _no_drops, pet_events)
		for e: Dictionary in pet_events:
			out.append(e)
	return out
