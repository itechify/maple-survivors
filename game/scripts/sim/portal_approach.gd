class_name PortalApproach
extends RefCounted
## Pure entrance routing and movement shared by autoplay and harness campers; callers choose their own portal goals.


## Plans a walk or jump to the entrance's floor; an empty plan means the entrance cannot be approached.
static func plan(world: RunWorld, source: Vector2) -> Dictionary:
	var floor := world.fhm.find_below(source.x, source.y - float(world.portals.tuning.reach_above))
	if floor < 0:
		return {}
	var platform := world.player_platform()
	var source_platform := world.fhm.platform_of(floor)
	var approach := {"pos": source, "source": source, "same_floor": source_platform == platform,
		"hop": false, "hop_dir": 0.0, "floor_y": world.fhm.y_at(floor, source.x)}
	if source_platform != platform:
		var edge := world.nav_jump.route_near(platform, source_platform, world.player.pos.x)
		if edge < 0:
			return {}
		var route := world.nav_jump.edge(edge)
		approach.pos = Vector2(clampf(source.x, float(route.lo), float(route.hi)), world.player.pos.y)
		approach.hop = String(route.kind) == "jump"
		approach.hop_dir = signf(float(route.vx))
	if world.fhm.walk_blocked(platform, world.player.pos.x, approach.pos.x):
		return {}
	return approach


## Writes only entrance movement into the caller's input, preserving potion and other policy decisions.
static func steer(world: RunWorld, approach: Dictionary, input: MoveInput) -> void:
	var dx: float = approach.pos.x - world.player.pos.x
	input.up = bool(approach.same_floor) and absf(dx) <= float(world.portals.tuning.reach_x)
	input.left = not input.up and dx < 0.0
	input.right = not input.up and dx > 0.0
	# tier C: 3 px jump takeoff tolerance, shared by the navigation bot and camper harness.
	if not bool(approach.same_floor) and absf(dx) < 3.0:
		input.jump_pressed = bool(approach.hop)
		input.jump_held = input.jump_pressed
		input.left = float(approach.hop_dir) < 0.0
		input.right = float(approach.hop_dir) > 0.0
