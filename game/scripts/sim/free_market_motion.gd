class_name FreeMarketMotion
extends RefCounted
## Hub-only player motion and portals. No combat systems or round clock exist here.

const MAP_ID := 910000000 # tier A: original v83 Free Market Entrance.
var player := PlayerMotion.new()
var fhm: FootholdMap
var ladders: LadderSet
var bounds: Rect2
var portals: PortalSet


func _init(map_img: Dictionary = {}, physics: Dictionary = {}, balance: Dictionary = {}) -> void:
	fhm = FootholdMap.from_wz(map_img)
	ladders = LadderSet.from_wz(map_img)
	bounds = MapBounds.from_map(map_img, fhm)
	player = PlayerMotion.new(PhysicsConstants.from_wz(physics))
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


## Advances movement and returns portal_used or exit_requested events.
func step(dt: float, input: MoveInput) -> Array[Dictionary]:
	var used := portals.step(dt, player.pos, input.up)
	if not used.is_empty():
		if used.portal == "out00":
			return [{"type": "exit_requested"}]
		player.place(used.pos, fhm)
		return [{"type": "portal_used", "portal": used.portal, "target": used.target, "pos": used.pos}]
	player.step(dt, input, fhm, ladders, bounds)
	return []
