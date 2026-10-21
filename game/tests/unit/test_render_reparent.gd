extends TestCase
## Every pooled renderer keeps drawing after it leaves and re-enters the scene tree (remove_child/add_child or
## reparent()), as integration does when the player's actors move between MapRenderer.actor_layer(L) containers.
## Runs in the live tree: the containers are children of the test runner (the current scene).

const AF := preload("res://tests/fixtures/asset_fixtures.gd")

var lib: AssetLibrary
var a: Node2D
var b: Node2D


func before_each() -> void:
	lib = AssetLibrary.new()
	lib.open(AF.write_cache())
	# The runner's own _ready is running, so the root is busy; the runner (current scene) accepts children.
	var host := (Engine.get_main_loop() as SceneTree).current_scene
	a = Node2D.new()
	b = Node2D.new()
	host.add_child(a)
	host.add_child(b)


func after_each() -> void:
	a.free()
	b.free()
	lib.free()


func _move(n: Node, to: Node) -> void:
	n.get_parent().remove_child(n)
	to.add_child(n)


func _swarm(n: int) -> DebugSoA:
	var s := DebugSoA.make(n, {"kind": TYPE_PACKED_INT32_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "state": TYPE_PACKED_INT32_ARRAY, "state_t": TYPE_PACKED_FLOAT32_ARRAY,
		"anim_t": TYPE_PACKED_FLOAT32_ARRAY, "facing": TYPE_PACKED_INT32_ARRAY, "alpha": TYPE_PACKED_FLOAT32_ARRAY,
		"fh": TYPE_PACKED_INT32_ARRAY})
	s.fields.alpha.fill(1.0)
	return s


func test_fx_survives_reparent() -> void:
	var fx := FxRenderer.new()
	fx.library = lib
	a.add_child(fx)
	assert_true(fx.is_inside_tree(), "in the live tree")
	var held := fx.play("Mob.wz/0100100.img/hit1", Vector2.ZERO, false, null, Vector2.ZERO, true)
	fx.play("Mob.wz/0100100.img/move", Vector2(5, 5))
	fx.advance(0.37)
	assert_eq(fx.active_count(), 1, "the move animation ended, its slot is on the free list")
	_move(fx, b)
	fx.advance(0.01)
	assert_eq(fx.active_count(), 1, "the held effect is still playing")
	var pool: SpritePool = fx.get("_pool")
	assert_true(pool != null and pool.is_shown(held), "the held effect is still drawn")
	var again := fx.play("Mob.wz/0100100.img/move", Vector2(5, 5))
	assert_true(again >= 0 and pool.is_shown(again), "a new effect reuses the free slot and draws")
	fx.reparent(a)
	fx.advance(0.01)
	assert_eq(fx.active_count(), 2, "reparent() keeps both")
	assert_eq(pool.shown_count(), 2)


func test_fx_tomb_and_behind_survive_reparent() -> void:
	var front := FxRenderer.new()
	var back := FxRenderer.new()
	front.library = lib
	back.library = lib
	front.behind = back
	a.add_child(back)
	a.add_child(front)
	front.play("Test.wz/Sprite.img/behind", Vector2.ZERO, false, null, Vector2.ZERO, true)
	assert_eq(back.active_count(), 1)
	_move(back, b)
	b.move_child(back, 0)
	back.advance(0.5)
	front.play("Test.wz/Sprite.img/behind", Vector2.ZERO)
	assert_eq(back.active_count(), 2, "the behind renderer keeps its held effect and takes new ones")


func test_damage_numbers_survive_reparent() -> void:
	var dn := DamageNumbers.new()
	dn.library = lib
	a.add_child(dn)
	assert_true(dn.spawn(12, Vector2.ZERO) >= 0, "digits from the synthetic BasicEff.img")
	assert_true(dn.spawn(34, Vector2(50, 0), DamageNumbers.CRIT) >= 0)
	dn.advance(0.1)
	_move(dn, b)
	dn.advance(0.1)
	assert_eq(dn.active_count(), 2, "numbers in flight are kept across the reparent")
	assert_true(dn.spawn(5, Vector2.ZERO) >= 0, "and new ones still spawn")
	dn.advance(1.01)
	assert_eq(dn.active_count(), 0, "all finish on time")


func test_mob_projectile_pickup_survive_reparent() -> void:
	var mr := MobRenderer.new()
	mr.library = lib
	a.add_child(mr)
	var s := _swarm(2)
	s.fields.state = PackedInt32Array([MobRenderer.MOVE, MobRenderer.STAND])
	mr.update_from(s, PackedInt32Array([100100]))
	assert_eq(mr.visible_count(), 2)
	_move(mr, b)
	assert_eq(mr.visible_count(), 2, "still drawn right after the move")
	mr.update_from(s, PackedInt32Array([100100]))
	assert_eq(mr.visible_count(), 2)

	var pr := ProjectileRenderer.new()
	pr.library = lib
	a.add_child(pr)
	var p := DebugSoA.make(1, {"active": TYPE_PACKED_BYTE_ARRAY, "x": TYPE_PACKED_FLOAT32_ARRAY,
		"y": TYPE_PACKED_FLOAT32_ARRAY, "vx": TYPE_PACKED_FLOAT32_ARRAY, "vy": TYPE_PACKED_FLOAT32_ARRAY,
		"visual": TYPE_PACKED_INT32_ARRAY})
	p.fields.active = PackedByteArray([1])
	pr.update_from(p, ["Mob.wz/0100100.img/move"], 0.016)
	pr.reparent(b)
	assert_eq(pr.visible_count(), 1, "shot still drawn after reparent()")
	pr.update_from(p, ["Mob.wz/0100100.img/move"], 0.016)
	assert_eq(pr.visible_count(), 1)


func test_projectile_animation_restarts_when_slot_is_reused_between_draws() -> void:
	var shots := ProjectileSystem.new(1)
	var spec := {"visual": 0}
	var first := shots.spawn(spec)
	var renderer := ProjectileRenderer.new()
	renderer.library = lib
	a.add_child(renderer)
	var paths := ["Mob.wz/0100100.img/move"]
	renderer.update_from(shots, paths, 0.0)
	renderer.update_from(shots, paths, 0.2)
	assert_near(renderer._age[first], 0.2)
	shots.despawn(first)
	assert_eq(shots.spawn(spec), first, "same slot and visual, with no inactive draw")
	renderer.update_from(shots, paths, 0.01)
	assert_eq(renderer._age[first], 0.0, "a new projectile starts at animation frame zero")


func test_mob_projectile_animation_restarts_when_slot_is_reused_between_draws() -> void:
	var shots := MobProjectileSystem.new(1)
	var spec := {"pos": Vector2.ZERO, "velocity": Vector2.RIGHT, "range": 400.0, "visual": 0,
		"mob": 0, "mob_id": 100100, "damage": 1.0, "multiplier": 1.0, "accuracy": 1.0,
		"magic": false, "element": "", "hit": "", "source_pos": Vector2.ZERO}
	var first := shots.spawn(spec)
	var renderer := ProjectileRenderer.new()
	renderer.library = lib
	a.add_child(renderer)
	var paths := ["Mob.wz/0100100.img/move"]
	renderer.update_from(shots, paths, 0.0)
	renderer.update_from(shots, paths, 0.2)
	assert_near(renderer._age[first], 0.2)
	shots.despawn(first)
	assert_eq(shots.spawn(spec), first)
	renderer.update_from(shots, paths, 0.01)
	assert_eq(renderer._age[first], 0.0, "mob balls obey the same draw identity contract")
