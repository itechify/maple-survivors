extends TestCase
## MobRenderer/ProjectileRenderer/PickupRenderer/FxRenderer on fake struct-of-arrays state and the synthetic cache.

const AF := preload("res://tests/fixtures/asset_fixtures.gd")

var lib: AssetLibrary
var root: Node


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open(AF.write_cache())
	# Renderers work outside the scene tree (their canvas item exists from construction); the runner is mid-_ready.
	root = Node2D.new()


func after_each() -> void:
	root.free()
	lib.free()


func _swarm(n: int) -> DebugSoA:
	return DebugSoA.make(n, {"kind": TYPE_PACKED_INT32_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "state": TYPE_PACKED_INT32_ARRAY, "state_t": TYPE_PACKED_FLOAT32_ARRAY,
		"anim_t": TYPE_PACKED_FLOAT32_ARRAY, "facing": TYPE_PACKED_INT32_ARRAY, "alpha": TYPE_PACKED_FLOAT32_ARRAY})


func test_state_constants_mirror_mob_swarm() -> void:
	assert_eq(MobRenderer.STAND, MobSwarm.STAND)
	assert_eq(MobRenderer.MOVE, MobSwarm.MOVE)
	assert_eq(MobRenderer.JUMP, MobSwarm.JUMP)
	assert_eq(MobRenderer.HIT, MobSwarm.HIT)
	assert_eq(MobRenderer.DIE, MobSwarm.DIE)
	assert_eq(MobRenderer.FREE, MobSwarm.FREE)
	assert_true(MobRenderer.state_loops(MobRenderer.MOVE))
	assert_false(MobRenderer.state_loops(MobRenderer.DIE))


func test_stance_fallbacks() -> void:
	var r := MobRenderer.new()
	r.library = lib
	root.add_child(r)
	assert_eq(r.anim_for(100100, MobRenderer.STAND).path, "Mob.wz/0100100.img/stand")
	assert_eq(r.anim_for(100100, MobRenderer.JUMP).path, "Mob.wz/0100100.img/move", "no jump stance -> move")
	assert_eq(r.anim_for(100100, MobRenderer.HIT).path, "Mob.wz/0100100.img/hit1")
	assert_eq(r.anim_for(100100, MobRenderer.DIE).path, "Mob.wz/0100100.img/die1")
	assert_eq(r.anim_for(100101, MobRenderer.STAND).path, "Mob.wz/0100100.img/stand", "info/link followed")
	assert_eq(r.anim_for(999999, MobRenderer.STAND), null, "unknown mob")
	assert_has(r.missing, 999999)


func test_update_from_fake_swarm() -> void:
	var r := MobRenderer.new()
	r.library = lib
	root.add_child(r)
	var s := _swarm(4)
	s.fields.state = PackedInt32Array([MobRenderer.MOVE, MobRenderer.FREE, MobRenderer.DIE, MobRenderer.STAND])
	s.fields.kind = PackedInt32Array([0, 0, 0, 1])
	s.fields.alpha = PackedFloat32Array([1, 1, 1, 1])
	r.update_from(s, PackedInt32Array([100100, 999999]))
	assert_eq(r.visible_count(), 2, "FREE slot and the unknown mob are hidden")
	s.fields.state = PackedInt32Array([MobRenderer.FREE, MobRenderer.FREE, MobRenderer.FREE, MobRenderer.FREE])
	r.update_from(s, PackedInt32Array([100100, 999999]))
	assert_eq(r.visible_count(), 0)
	r.update_from(_swarm(0), PackedInt32Array([100100]))
	assert_eq(r.visible_count(), 0, "shrinking hides the rest")


func test_die_alpha_from_a0_a1_and_regen() -> void:
	var r := MobRenderer.new()
	r.library = lib
	root.add_child(r)
	var die := r.anim_for(100100, MobRenderer.DIE)
	assert_near(die.alpha_at(0.1, false), 0.5, 1e-5, "die1 a0 255 -> a1 0 over 200 ms")
	var move := r.anim_for(100100, MobRenderer.MOVE)
	assert_eq(move.index_at(0.2, true), 1, "move frames advance with anim_t")


func test_projectile_rotation_and_flip() -> void:
	assert_near(ProjectileRenderer.rotation_for(Vector2(1, 0)), 0.0, 1e-6, "right: mirrored art, no turn")
	assert_near(ProjectileRenderer.rotation_for(Vector2(-1, 0)), 0.0, 1e-6, "left: native art")
	assert_near(ProjectileRenderer.rotation_for(Vector2(1, 1)), PI / 4.0, 1e-6, "down-right")
	assert_near(ProjectileRenderer.rotation_for(Vector2(-1, 1)), -PI / 4.0, 1e-6, "down-left turns the nose down")
	var pr := ProjectileRenderer.new()
	pr.library = lib
	root.add_child(pr)
	var p := DebugSoA.make(2, {"active": TYPE_PACKED_BYTE_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "vx": TYPE_PACKED_FLOAT32_ARRAY, "vy": TYPE_PACKED_FLOAT32_ARRAY,
		"visual": TYPE_PACKED_INT32_ARRAY})
	p.fields.active = PackedByteArray([1, 0])
	pr.update_from(p, ["Mob.wz/0100100.img/move"], 0.016)
	assert_eq(pr.visible_count(), 1)


func test_pickup_anchor_and_bob() -> void:
	var f := SpriteFrame.new()
	f.region = Rect2(0, 0, 25, 25)
	f.origin = Vector2(-4, 27)
	var off := PickupRenderer.anchor_offset(f)
	var tl := Vector2(100, 50) + off - f.origin
	assert_eq(tl, Vector2(100 - 12, 50 - 25), "icon centred on x with its bottom on y")
	for i in 30:
		var b := PickupRenderer.bob_offset(i * 0.1, 3)
		assert_between(b, -PickupRenderer.BOB_PX, 0.0)
		assert_eq(b, roundf(b), "whole pixels")


func test_fx_one_shot_and_hold() -> void:
	var fx := FxRenderer.new()
	fx.library = lib
	root.add_child(fx)
	var a := fx.play("Mob.wz/0100100.img/move", Vector2(10, 10))
	assert_true(a >= 0)
	assert_eq(fx.play("Mob.wz/0100100.img/none", Vector2.ZERO), -1, "missing animation")
	var held := fx.play("Mob.wz/0100100.img/hit1", Vector2(0, 0), true, null, Vector2.ZERO, true)
	assert_eq(fx.active_count(), 2)
	fx.advance(0.37)
	assert_eq(fx.active_count(), 1, "the 360 ms move animation ended; the held one stays")
	fx.advance(5.0)
	assert_eq(fx.active_count(), 1)
	fx.stop(held)
	assert_eq(fx.active_count(), 0)
	var again := fx.play("Mob.wz/0100100.img/move", Vector2(10, 10))
	assert_true(again == a or again == held, "slots are reused")
	assert_eq(fx.get("_active").size(), 2, "the pool did not grow")


func test_fx_negative_z_goes_behind() -> void:
	var front := FxRenderer.new()
	var back := FxRenderer.new()
	front.library = lib
	back.library = lib
	front.behind = back
	root.add_child(back)
	root.add_child(front)
	var a := lib.anim("Test.wz/Sprite.img/behind")
	assert_eq(a.z, -1, "animation-level z")
	assert_eq(a.frame_count(), 1, "z is not a frame")
	front.play("Test.wz/Sprite.img/behind", Vector2.ZERO)
	front.play("Mob.wz/0100100.img/move", Vector2.ZERO)
	assert_eq(front.active_count(), 1)
	assert_eq(back.active_count(), 1, "z < 0 forwarded to the behind renderer")


func test_one_renderer_per_foothold_layer() -> void:
	var s := DebugSoA.make(4, {"kind": TYPE_PACKED_INT32_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "state": TYPE_PACKED_INT32_ARRAY, "state_t": TYPE_PACKED_FLOAT32_ARRAY,
		"anim_t": TYPE_PACKED_FLOAT32_ARRAY, "facing": TYPE_PACKED_INT32_ARRAY, "alpha": TYPE_PACKED_FLOAT32_ARRAY,
		"fh": TYPE_PACKED_INT32_ARRAY})
	s.fields.alpha.fill(1.0)
	s.fields.state = PackedInt32Array([MobRenderer.MOVE, MobRenderer.STAND, MobRenderer.FREE, MobRenderer.JUMP])
	# Footholds 0 and 1 are on layer 0, foothold 2 on layer 3; slot 3 is airborne (fh -1), never seen on a floor.
	var fh_layer := PackedInt32Array([0, 0, 3])
	s.fields.fh = PackedInt32Array([1, 2, -1, -1])
	var layers := MobRenderer.update_slot_layers(s, fh_layer, PackedInt32Array())
	assert_eq(layers, PackedInt32Array([0, 3, 0, 0]), "foothold layer, fallback 0 for unknown")
	var r0 := MobRenderer.new()
	var r3 := MobRenderer.new()
	r0.library = lib
	r3.library = lib
	root.add_child(r0)
	root.add_child(r3)
	var ids := PackedInt32Array([100100])
	r0.update_from(s, ids, 0, layers)
	r3.update_from(s, ids, 3, layers)
	assert_eq(r0.visible_count(), 2, "slots 0 and 3 on layer 0")
	assert_eq(r3.visible_count(), 1, "slot 1 on layer 3")
	var pool3: SpritePool = r3.get("_pool")
	assert_eq(pool3.size(), 2, "a filtered renderer allocates only up to its highest drawn slot")
	# Slot 1 jumps off its layer-3 floor (fh -1): it stays on layer 3 until it lands on layer 0.
	s.fields.fh = PackedInt32Array([1, -1, -1, 0])
	layers = MobRenderer.update_slot_layers(s, fh_layer, layers)
	assert_eq(layers, PackedInt32Array([0, 3, 0, 0]), "airborne keeps the last floor's layer")
	s.fields.fh = PackedInt32Array([1, 0, -1, 0])
	layers = MobRenderer.update_slot_layers(s, fh_layer, layers)
	r0.update_from(s, ids, 0, layers)
	r3.update_from(s, ids, 3, layers)
	assert_eq(r0.visible_count(), 3, "slot 1 landed on layer 0")
	assert_eq(r3.visible_count(), 0)
	r0.update_from(s, ids)
	assert_eq(r0.visible_count(), 3, "no filter: every live slot")


func test_delayed_fx_waits_then_plays_for_its_full_duration() -> void:
	var fx := FxRenderer.new()
	fx.library = lib
	root.add_child(fx)
	fx.set_process(false)
	var slot := fx.play_delayed("Mob.wz/0100100.img/move", 0.45, Vector2.ZERO)
	assert_true(slot >= 0)
	assert_eq(fx.get("_pool").get("_shown")[slot], 0, "hidden before body frame two")
	fx.advance(0.46)
	assert_eq(fx.get("_pool").get("_shown")[slot], 1, "visible after delay")
	fx.advance(0.34)
	assert_eq(fx.active_count(), 1, "delay does not consume animation time")
	fx.advance(0.02)
	assert_eq(fx.active_count(), 0)
	fx.queue_free()
