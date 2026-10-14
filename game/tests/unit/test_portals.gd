extends TestCase
## Same-map portals through RunWorld: instant warps, activation bounds, cooldown, ladder compatibility and the
## original Tree That Grew I's complete up/down chains. Real-map checks require the player's asset cache.

const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0
const MAP_ID := 101010100


func _world(portal_nodes: Dictionary = {}) -> RunWorld:
	var data := RF.quiet_data()
	data.stages.stages.quiet.map_id = MAP_ID
	var s := RF.setup("quiet", 17, data)
	s.map_img = RF.map_from_segments([
		{"x1": 0.0, "y1": 200.0, "x2": 1200.0, "y2": 200.0},
		{"x1": 600.0, "y1": -200.0, "x2": 1000.0, "y2": -200.0},
	])
	s.map_img.portal = portal_nodes if not portal_nodes.is_empty() else {
		"0": {"pn": "up00", "pt": 1.0, "x": 400.0, "y": 200.0, "tm": float(MAP_ID), "tn": "up01"},
		"1": {"pn": "up01", "pt": 1.0, "x": 800.0, "y": -200.0, "tm": 999999999.0, "tn": "up00"},
	}
	s.map_img.ladderRope = {"0": {"l": 1.0, "uf": 1.0, "x": 100.0, "y1": 0.0, "y2": 198.0}}
	var w := RunWorld.new(s)
	w.player.place(Vector2(400, 200), w.fhm)
	w.drain_events()
	return w


func _used(w: RunWorld) -> Array:
	return w.drain_events().filter(func(e: Dictionary) -> bool: return e.type == "portal_used")


func test_holding_up_warps_instantly_then_falls_to_the_floor() -> void:
	var w := _world()
	w.player.vel.x = 100.0
	w.step(DT, MoveInput.make(false, false, true))
	assert_eq(w.player.pos, Vector2(800, -230), "instant arrival 30 px above the target")
	assert_eq(w.player.vel, Vector2.ZERO, "old movement does not carry through the portal")
	assert_eq(w.player.state, PlayerMotion.ST_AIR, "arrival falls onto the target floor")
	assert_eq(_used(w), [{"type": "portal_used", "portal": "up00", "target": "up01", "pos": Vector2(800, -230)}])
	for i in 15:
		w.step(DT, MoveInput.new())
	assert_eq(w.player.state, PlayerMotion.ST_STAND)
	assert_eq(w.player.pos, Vector2(800, -200))


func test_held_up_cannot_warp_again_until_384_ms() -> void:
	var w := _world()
	var up := MoveInput.make(false, false, true)
	w.step(DT, up)
	assert_eq(_used(w).size(), 1)
	for i in 23:
		w.step(DT, up)
		assert_true(_used(w).is_empty(), "no second warp at %.3f s" % ((i + 1) * DT))
	assert_eq(w.player.pos, Vector2(800, -200))
	w.step(DT, up)
	assert_eq(_used(w), [{"type": "portal_used", "portal": "up01", "target": "up00", "pos": Vector2(400, 170)}],
		"sentinel target-map id resolves against local portal names")


func test_activation_box_uses_feet_and_requires_up() -> void:
	for offset: Vector2 in [Vector2(-25, 0), Vector2(25, 0), Vector2(0, -100), Vector2(0, 25),
			Vector2(-25.01, 0), Vector2(25.01, 0), Vector2(0, -100.01), Vector2(0, 25.01)]:
		var w := _world()
		w.player.place(Vector2(400, 200) + offset, w.fhm)
		w.step(DT, MoveInput.make(false, false, true))
		var inside := offset in [Vector2(-25, 0), Vector2(25, 0), Vector2(0, -100), Vector2(0, 25)]
		assert_eq(_used(w).size(), 1 if inside else 0, "activation at feet offset %s" % offset)
	var idle := _world()
	idle.step(DT, MoveInput.new())
	assert_true(_used(idle).is_empty(), "standing inside a portal does not activate it")
	assert_eq(idle.player.pos, Vector2(400, 200))


func test_other_map_and_unresolved_exits_are_inert_and_up_grabs_ladders() -> void:
	var w := _world({
		"0": {"pn": "exit", "pt": 2, "x": 100, "y": 200, "tm": 101010101, "tn": "same_name"},
		"1": {"pn": "same_name", "pt": 1, "x": 800, "y": -200, "tm": MAP_ID, "tn": "missing"},
	})
	w.player.place(Vector2(100, 200), w.fhm)
	w.step(DT, MoveInput.make(false, false, true))
	assert_true(_used(w).is_empty(), "exit to another map is inert even when its target name exists here")
	assert_eq(w.player.state, PlayerMotion.ST_LADDER, "Up still grabs a ladder beside an inert exit")
	assert_eq(w.player.ladder, 0)
	w.player.place(Vector2(800, -200), w.fhm)
	w.step(DT, MoveInput.make(false, false, true))
	assert_true(_used(w).is_empty(), "a missing destination is inert")
	assert_eq(w.player.pos, Vector2(800, -200))


func test_monsters_do_not_use_player_portals() -> void:
	var w := _world()
	var mob := RF.put_mob(w, 100100, 400, 200)
	w.step(DT, MoveInput.make(false, false, true))
	assert_eq(w.player.pos, Vector2(800, -230))
	assert_between(w.swarm.x[mob], 395, 405, "monster remains beside the source portal")
	assert_near(w.swarm.y[mob], 200.0)


func test_tree_real_portals_reach_top_and_return_to_ground() -> void:
	if not require_cache():
		return
	var lib := AssetLibrary.new()
	lib.open()
	var img := lib.img(DataRepo.map_img_path(MAP_ID))
	assert_true(img != null, "Tree I is imported")
	if img == null:
		lib.free()
		return
	var data := RF.quiet_data()
	data.stages.stages.quiet.map_id = MAP_ID
	var s := RF.setup("quiet", 17, data)
	s.map_img = img.root
	var w := RunWorld.new(s)
	var named := {}
	for p: Dictionary in img.root.portal.values():
		named[String(p.pn)] = p
	var p: Dictionary = named.up00
	w.player.place(Vector2(float(p.x), float(p.y) - 30), w.fhm)
	for i in 30:
		w.step(DT, MoveInput.new())
	assert_eq(w.player.state, PlayerMotion.ST_STAND, "starts beside up00 on the ground")
	assert_eq(w.fhm.platform_of(w.player.fh), 1, "up00 starts on the left ground chain")
	var upward := _chain(w, 180)
	assert_eq(upward.names, ["up00", "up01", "up02"], "held Up traverses every local upward link")
	assert_eq(upward.platforms, [3, 4, 7], "the portal chain first reaches floors P3, P4 and P7")
	assert_eq(w.fhm.platform_of(w.player.fh), 7, "top floor reached")
	assert_true(_used(w).is_empty(), "up03 exits to Tree II and remains inert")
	p = named.dw00
	w.player.place(Vector2(float(p.x), float(p.y)), w.fhm)
	var downward := _chain(w, 180)
	assert_eq(downward.names, ["dw00", "dw01", "dw02"])
	assert_eq(downward.platforms, [4, 3, 2], "down chain lands on each floor and returns to the right ground chain")
	assert_eq(w.fhm.platform_of(w.player.fh), 2)
	assert_between(w.player.pos.y, 2000, 2100, "back at ground height")
	print("  Tree I portals: up %s first reaches platforms %s; down %s reaches %s" %
		[upward.names, upward.platforms, downward.names, downward.platforms])
	lib.free()


func _chain(w: RunWorld, ticks: int) -> Dictionary:
	var names: Array = []
	var platforms: Array = []
	var landing_pending := false
	for i in ticks:
		w.step(DT, MoveInput.make(false, false, true))
		for e: Dictionary in _used(w):
			names.append(e.portal)
			landing_pending = true
		if landing_pending and w.player.fh >= 0:
			platforms.append(w.fhm.platform_of(w.player.fh))
			landing_pending = false
	return {"names": names, "platforms": platforms}
