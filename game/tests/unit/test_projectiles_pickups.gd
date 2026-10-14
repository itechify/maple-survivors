extends TestCase
## ProjectileSystem (hits, pierce, already-hit list, range expiry, kills) and PickupSystem (pop, gravity onto
## footholds, magnet, collect, merge cap) on synthetic footholds, fixed 1/60 s ticks.

const WF := preload("res://tests/fixtures/world_fixtures.gd")
const RF := preload("res://tests/fixtures/run_fixtures.gd")
const DT := 1.0 / 60.0

var fhm: FootholdMap
var swarm: MobSwarm
var grid: SpatialHash


func before_each() -> void:
	fhm = FootholdMap.from_segments(WF.tiers_segments())
	var kinds: Array = [MobKind.from_wz(RF.mob_img(1110100), 1110100)]
	swarm = MobSwarm.new(16, kinds)
	swarm.fhm = fhm
	grid = SpatialHash.new(64.0)


## A tough mob standing on the ground (y = 0) at x, faded in.
func _mob(x: float, hp: int = 1000) -> int:
	var i := swarm.spawn(0, x, 0.0, fhm.find_below(x, -1.0), hp)
	swarm.alpha[i] = 1.0
	return i


func _shot(p: ProjectileSystem, x: float, vx: float, pierce: int, rng: float = 1000.0, dmg: float = 10.0) -> int:
	return p.spawn({"x": x, "y": -13.0, "vx": vx, "vy": 0.0, "range": rng, "radius": 10.0, "visual": 0,
		"hit_visual": 1, "dmg_min": dmg, "dmg_max": dmg, "pierce": pierce, "skill": "three_snails"})


func _run(p: ProjectileSystem, ticks: int, events: Array) -> void:
	for t in ticks:
		grid.rebuild(swarm.x, swarm.y, swarm.active, swarm.capacity())
		p.step(DT, swarm, grid, events)


func test_projectile_hits_and_expires_on_hit() -> void:
	var p := ProjectileSystem.new(4)
	p.paths = ["ball", "Skill.wz/000.img/skill/0001000/level/1/hit/0"]
	var m := _mob(300.0)
	var s := _shot(p, 100.0, 400.0, 0)
	var ev: Array = []
	_run(p, 60, ev)
	assert_eq(ev.size(), 1, "one hit")
	if ev.size() == 1:
		var e: Dictionary = ev[0]
		assert_eq(e.type, "mob_hit")
		assert_eq(e.mob, m)
		assert_eq(e.mob_id, 1110100)
		assert_eq(e.damage, 10)
		assert_false(e.crit)
		assert_eq(e.skill, "three_snails")
		assert_eq(e.hit_visual, "Skill.wz/000.img/skill/0001000/level/1/hit/0")
		assert_near(e.pos.y, swarm.y[m] + swarm.kinds[0].hitbox.position.y, 1e-3, "number at the mob's head")
	assert_eq(swarm.hp[m], 990)
	assert_eq(p.active[s], 0, "no pierce: gone after the hit")
	assert_eq(p.active_count(), 0)
	assert_eq(p.dealt, 10)


func test_projectile_pierces_in_order_and_never_hits_twice() -> void:
	var p := ProjectileSystem.new(4)
	p.paths = ["ball"]
	var a := _mob(250.0)
	var b := _mob(350.0)
	var c := _mob(450.0)
	_shot(p, 100.0, 400.0, 1)
	var ev: Array = []
	_run(p, 90, ev)
	assert_eq(ev.size(), 2, "pierce 1 = two mobs")
	if ev.size() == 2:
		assert_eq(ev[0].mob, a, "nearest first")
		assert_eq(ev[1].mob, b)
	assert_eq(swarm.hp[c], 1000, "the third is untouched")
	assert_eq(p.active_count(), 0)
	# A lone mob and a shot with pierce to spare: one hit only, the shot flies on until its range ends.
	before_each()
	var p2 := ProjectileSystem.new(4)
	p2.paths = ["ball"]
	var lone := _mob(300.0)
	var s2 := _shot(p2, 100.0, 400.0, 5, 500.0)
	var ev2: Array = []
	_run(p2, 30, ev2)
	assert_eq(ev2.size(), 1, "the already-hit list stops repeat hits")
	assert_eq(swarm.hp[lone], 990)
	assert_eq(p2.active[s2], 1, "still flying (pierce left)")
	_run(p2, 60, ev2)
	assert_eq(p2.active[s2], 0, "expired at 500 px")
	assert_eq(ev2.size(), 1)


func test_projectile_range_expiry_and_kills() -> void:
	var p := ProjectileSystem.new(2)
	p.paths = ["ball"]
	var m := _mob(400.0, 5)
	var short := _shot(p, 100.0, 400.0, 0, 150.0)
	var ev: Array = []
	_run(p, 30, ev)
	assert_eq(ev.size(), 0, "a 150 px shot never reaches a mob 300 px away")
	assert_eq(p.active[short], 0, "expired")
	_shot(p, 100.0, 400.0, 0, 1000.0, 10.0)
	_run(p, 1, ev)
	assert_eq(p.kills.size(), 0)
	var killed := false
	for t in 60:
		_run(p, 1, ev)
		if p.kills.size() > 0:
			killed = p.kills[0] == m
			break
	assert_true(killed, "the killing hit is reported in kills")
	assert_eq(swarm.state[m], MobSwarm.DIE)
	# Out of bounds.
	var p3 := ProjectileSystem.new(2)
	p3.bounds = Rect2(0, -200, 600, 400)
	var s3 := p3.spawn({"x": 500.0, "y": -100.0, "vx": 0.0, "vy": -3000.0, "range": 10000.0})
	_run(p3, 30, ev)
	assert_eq(p3.active[s3], 0, "left the bounds (+200 px)")


func test_segment_enter() -> void:
	var r := Rect2(10, -5, 10, 10)
	assert_near(ProjectileSystem.segment_enter(0, 0, 20, 0, r), 0.5, 1e-6)
	assert_near(ProjectileSystem.segment_enter(12, 0, 30, 0, r), 0.0, 1e-6, "starting inside")
	assert_eq(ProjectileSystem.segment_enter(0, 10, 20, 10, r), -1.0, "passes below")
	assert_eq(ProjectileSystem.segment_enter(0, 0, 5, 0, r), -1.0, "stops short")


func test_pickup_pops_and_lands_on_the_floor() -> void:
	var pk := PickupSystem.new(4, {"spread": 0.0})
	var ev: Array = []
	var i := pk.spawn(Vector2(500, 0), 7, 4000019)
	assert_false(pk.merged)
	assert_eq(pk.state[i], PickupSystem.AIR)
	var top := 0.0
	for t in 60:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev)
		top = minf(top, pk.y[i])
	assert_lt_check(top, -10.0, "pops up")
	assert_eq(pk.state[i], PickupSystem.REST, "landed")
	assert_near(pk.y[i], 0.0, 1e-3, "on the ground")
	assert_eq(ev.size(), 0, "player far away: nothing collected")
	# Dropped above a platform: lands on it, not on the ground below.
	var j := pk.spawn(Vector2(200, -100), 3, 4000000)
	for t in 90:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev)
	assert_near(pk.y[j], -60.0, 1e-3, "on M1 (y -60)")


func test_pickup_magnet_and_collect() -> void:
	var pk := PickupSystem.new(4, {"spread": 0.0})
	var ev: Array = []
	var i := pk.spawn(Vector2(500, 0), 7, 4000019)
	var far := pk.spawn(Vector2(800, 0), 5, 4000000)
	for t in 30:
		pk.step(DT, Vector2(2000, 0), 90.0, fhm, ev)
	var got := 0
	for t in 120:
		got += pk.step(DT, Vector2(570, 0), 90.0, fhm, ev)
		if pk.active[i] == 0:
			break
	assert_eq(pk.active[i], 0, "pulled in and collected")
	assert_eq(got, 7)
	assert_eq(ev.size(), 1)
	if ev.size() == 1:
		assert_eq(ev[0].type, "pickup_collected")
		assert_eq(ev[0].pickup, i)
		assert_eq(ev[0].item_id, 4000019)
		assert_eq(ev[0].exp, 7)
	assert_eq(pk.active[far], 1, "230 px away: outside the 90 px magnet")
	assert_eq(pk.state[far], PickupSystem.REST)
	got = 0
	for t in 300:
		got += pk.step(DT, Vector2(570, 0), 300.0, fhm, ev)
	assert_eq(got, 5, "a bigger magnet reaches it")
	assert_eq(pk.collected_exp, 12)


func test_pickup_cap_absorbs_farthest_at_new_position() -> void:
	var pk := PickupSystem.new(2, {"max_active": 2, "spread": 0.0})
	var a := pk.spawn(Vector2(100, 0), 3, 1)
	var b := pk.spawn(Vector2(900, 0), 4, 1)
	var c := pk.spawn(Vector2(850, 0), 10, 1)
	assert_true(pk.merged, "third drop merged")
	assert_eq(c, b, "reuses the slot farthest from the default player point (0, 0)")
	assert_eq(Vector2(pk.x[c], pk.y[c]), Vector2(850, 0), "new drop remains at the new kill")
	assert_eq(pk.exp[b], 14)
	assert_eq(pk.exp[a], 3)
	assert_eq(pk.active_count(), 2)


func test_pickup_lifetime_fades_and_expires() -> void:
	var pk := PickupSystem.new(4, {"spread": 0.0, "lifetime": 2.0, "fade": 0.5})
	var ev: Array = []
	var i := pk.spawn(Vector2(500, 0), 7, 4000019)
	var near := pk.spawn(Vector2(560, 0), 4, 4000019)
	assert_eq(pk.alpha(i), 1.0, "fresh drop fully drawn")
	var seen_fade := false
	for t in 150:
		# The player stands 100 px from `i` (outside the 90 px magnet) and 40 px from `near` (inside it).
		pk.step(DT, Vector2(600, 0), 90.0, fhm, ev)
		if pk.active[i] != 0 and pk.alpha(i) < 1.0 and pk.alpha(i) > 0.0:
			seen_fade = true
	assert_true(seen_fade, "fades out over its last 0.5 s")
	assert_eq(pk.active[i], 0, "expired after 2 s on the ground")
	assert_eq(pk.expired, 1)
	assert_eq(pk.expired_exp, 7, "its EXP is lost")
	assert_eq(pk.collected_exp, 4, "the drop inside the magnet was collected, never expired")
	for e: Dictionary in ev:
		assert_eq(int(e.exp), 4, "no event for the expired drop")
	# Merging restarts the age (the merged EXP is not lost at once).
	var q := PickupSystem.new(2, {"spread": 0.0, "lifetime": 2.0, "max_active": 1})
	var a := q.spawn(Vector2(100, 0), 3, 1)
	for t in 90:
		q.step(DT, Vector2(2000, 0), 90.0, fhm, ev)
	q.spawn(Vector2(120, 0), 5, 1)
	assert_true(q.merged)
	for t in 90:
		q.step(DT, Vector2(2000, 0), 90.0, fhm, ev)
	assert_eq(q.active[a], 1, "1.5 s after the merge it is still there")
	assert_eq(q.exp[a], 8)
	# lifetime 0 (the default): drops never expire.
	var forever := PickupSystem.new(1, {"spread": 0.0})
	var f := forever.spawn(Vector2(100, 0), 1, 1)
	for t in 600:
		forever.step(DT, Vector2(2000, 0), 90.0, fhm, ev)
	assert_eq(forever.active[f], 1, "no lifetime: kept")
	assert_eq(forever.alpha(f), 1.0)


func assert_lt_check(v: float, lim: float, msg: String) -> void:
	if not (v < lim):
		fail("%s: %s is not < %s" % [msg, v, lim])
