extends RefCounted
## Harness-only camper movement. Henesys positions are placed once; the Tree uses ordinary portal/navigation inputs.
const STAGES := {"camper_henesys_top": "henesys_hg1", "camper_henesys_rope": "henesys_hg1", "camper_tree_top": "tree_that_grew_1"}


## tier C: the default 60 s warmup is a controlled camper measurement policy.
## Movement after a normal warmup, preserving normal potion decisions; no rescue teleport after a camper is displaced.


static func decide(world: RunWorld, policy: String, memo: Dictionary, after: float = 60.0) -> MoveInput:
	if not memo.has("bot"):
		memo.bot = {}
	var bot := BotInput.decide(world, memo.bot)
	if world.time < after or not STAGES.has(policy):
		return bot
	var input := MoveInput.new()
	input.drink_hp = bot.drink_hp
	input.drink_mp = bot.drink_mp
	if not memo.has("started_time"):
		memo.started_time = world.time
		memo.reached = false
		memo.reached_time = -1.0
		if policy.ends_with("rope"):
			var rope := -1
			for index in world.ladders.count():
				if world.ladders.is_ladder[index] == 0 and (rope<0 or world.ladders.y2[index]>world.ladders.y2[rope]):
					rope = index
			memo.target_rope = rope
			if rope>=0:
				world.player.place(Vector2(world.ladders.x[rope], world.ladders.y2[rope]), world.fhm)
		else:
			var floor := -1
			var height := INF
			for index in world.fhm.count():
				if world.fhm.is_floor(index) and minf(world.fhm.y1[index], world.fhm.y2[index])<height:
					floor = index
					height = minf(world.fhm.y1[index], world.fhm.y2[index])
			if policy == "camper_tree_top":
				# The highest local upward destination is the playable top branch; decorative floors are not goals.
				height = INF
				for link: Dictionary in world.portals.links:
					if String(link.name).begins_with("up") and link.target_pos.y<height:
						height = link.target_pos.y
						floor = world.fhm.find_below(link.target_pos.x, link.target_pos.y-float(world.portals.tuning.reach_above))
			memo.target_platform = world.fhm.platform_of(floor) if floor>=0 else -1
			if floor>=0 and policy == "camper_henesys_top":
				var x := (world.fhm.x1[floor]+world.fhm.x2[floor])*0.5
				world.player.place(Vector2(x, world.fhm.y_at(floor, x)), world.fhm)
		world.update_view()
	if bool(memo.reached):
		return input
	if policy.ends_with("rope"):
		if world.player.ladder == int(memo.target_rope) and world.player.ladder>=0:
			memo.reached = true
		else:
			input.up = true
	elif world.player.fh>=0 and world.player_platform() == int(memo.target_platform):
		memo.reached = true
	elif policy == "camper_tree_top":
		_approach_up_portal(world, memo, input)
	if bool(memo.reached):
		memo.reached_time = world.time
		memo.target_position = world.player.pos
	return input


static func _approach_up_portal(world: RunWorld, memo: Dictionary, input: MoveInput) -> void:
	if world.player.ladder>=0:
		input.up = true
		return
	var p := world.player.pos
	if world.player.fh<0 and memo.has("portal_x") and absf(p.x-float(memo.portal_x)) <= float(world.portals.tuning.reach_x):
		input.up = true
		return
	var platform := world.player_platform()
	var best := INF
	var chosen := {}
	for link: Dictionary in world.portals.links:
		if not String(link.name).begins_with("up") or link.target_pos.y>=link.pos.y:
			continue
		var source: Vector2 = link.pos
		var floor := world.fhm.find_below(source.x, source.y-float(world.portals.tuning.reach_above))
		if floor<0:
			continue
		var source_platform := world.fhm.platform_of(floor)
		var point := source
		var hop := false
		var direction := 0.0
		if platform != source_platform:
			var edge := world.nav_jump.route_near(platform, source_platform, p.x)
			if edge<0:
				continue
			var route := world.nav_jump.edge(edge)
			point = Vector2(clampf(source.x, float(route.lo), float(route.hi)), p.y)
			hop = String(route.kind) == "jump"
			direction = signf(float(route.vx))
		if world.fhm.walk_blocked(platform, p.x, point.x):
			continue
		var cost := absf(p.x-point.x) + absf(p.y-source.y)
		if cost<best:
			best = cost
			chosen = {"point": point, "source": source, "hop": hop, "direction": direction, "same_floor": platform==source_platform}
	if chosen.is_empty():
		return
	var dx: float = chosen.point.x-p.x
	input.up = bool(chosen.same_floor) and absf(dx)<=float(world.portals.tuning.reach_x)
	input.left = not input.up and dx<0
	input.right = not input.up and dx>0
	# tier C: 3 px jump takeoff tolerance, matching the navigation bot approach.
	if not bool(chosen.same_floor) and absf(dx)<3.0:
		input.jump_pressed = bool(chosen.hop)
		input.jump_held = input.jump_pressed
		input.left = float(chosen.direction)<0
		input.right = float(chosen.direction)>0
	memo.portal_x = chosen.source.x
