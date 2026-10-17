class_name PickupSystem
extends RefCounted
## EXP, potion and meso drops as pooled struct-of-arrays (docs/ARCHITECTURE.md 4.4, docs/GAME_DESIGN.md section 5).
##
## A drop pops up (vy = -pop_speed, a small sideways drift from `rng`), falls with gravity up to fall_speed and lands
## on the first floor below it (FootholdMap.find_landing; a drop with nothing below stops where it is once it is below
## the foothold box). A drop within `magnet_r` of the player's body centre (feet - CENTER_UP) is attracted for good: it
## flies at the player, accelerating from magnet_speed by magnet_acc, and is collected within collect_radius, which
## appends a `pickup_collected` event; step() returns the EXP collected this tick. Past `max_active` live drops a new
## drop absorbs the EXP drop farthest from the player and replaces it at the new death position (`merged` reports
## absorption, while the new drop's pop and age restart). With `lifetime` > 0 an uncollected drop expires after fading
## out over its last `fade` seconds (alpha()) and is removed silently, its EXP lost (`expired`, `expired_exp`); a drop flying to
## the player never expires. Potions and mesos (spawn_meso, kind MESO) never expire, merge or count toward the EXP
## cap; a collected meso drop adds its amount to `step_mesos` (this step) and `collected_mesos` (total). All motion and lifetime constants are tier C (ours).

const AIR := 0
const REST := 1
const MAGNET := 2
## Pickup kinds: potion slots share motion and pooling but never enter the EXP cap or expiry policy.
const EXP := 0
const HP_POTION := 1
const MP_POTION := 2
const MESO := 3
## The player's body centre is this far above the feet. tier C: ours.
const CENTER_UP := 25.0

const TUNING_DEFAULTS := {
	"pop_speed": 260.0,  # tier C: initial upward speed of a drop (apex ~17 px)
	"spread": 40.0,  # tier C: max sideways speed of the pop
	"gravity": 2000.0,  # tier A: Physics.img gravityAcc
	"fall_speed": 670.0,  # tier A: Physics.img fallSpeed
	"magnet_speed": 220.0,  # tier C: start speed toward the player
	"magnet_acc": 1400.0,  # tier C: acceleration toward the player
	"collect_radius": 24.0,  # tier C: collected this close to the body centre
	"max_active": 600,  # tier C: absorb the farthest EXP drop into each new drop past this many
	"lifetime": 0.0,  # tier C: seconds an uncollected drop lies before it expires (0 = never)
	"fade": 1.5,  # tier C: the last seconds of the lifetime, fading out
}

var active := PackedByteArray()
var x := PackedFloat32Array()
var y := PackedFloat32Array()
var vx := PackedFloat32Array()
var vy := PackedFloat32Array()
var exp := PackedInt32Array()
var item_id := PackedInt32Array()
var kind := PackedByteArray()
var potion_count := PackedInt32Array()
## Meso amount of a MESO drop (0 for every other kind).
var meso := PackedInt32Array()
## Potion quantities collected in the most recent step(), read by RunWorld to update inventory.
var collected_potions := {"hp": 0, "mp": 0}
## AIR / REST / MAGNET.
var state := PackedByteArray()
## Seconds since the drop appeared (or last took merged EXP).
var age := PackedFloat32Array()

var tuning: Dictionary
var rng: RandomNumberGenerator
## True when the last spawn() absorbed an old drop; the returned slot still holds a fresh drop at the new position.
var merged := false
## Total EXP collected so far.
var collected_exp := 0
## Mesos collected in the most recent step() (read by RunWorld) and in total.
var step_mesos := 0
var collected_mesos := 0
## Drops expired so far and the EXP they held.
var expired := 0
var expired_exp := 0

var _free := PackedInt32Array()
var _hi := 0
var _count := 0
var _exp_count := 0


func _init(capacity: int = 64, p_tuning: Dictionary = {}, p_rng: RandomNumberGenerator = null) -> void:
	tuning = TUNING_DEFAULTS.duplicate()
	for k: String in p_tuning:
		if tuning.has(k):
			tuning[k] = p_tuning[k]
	rng = p_rng if p_rng != null else RandomNumberGenerator.new()
	_grow(maxi(1, capacity))


## Number of slots (iterate and skip inactive).
func capacity() -> int:
	return active.size()


## Number of live drops.
func active_count() -> int:
	return _count


## Live EXP drops, excluding the persistent potions that share this pool.
func exp_count() -> int:
	return _exp_count


## Drops EXP at pos, absorbing the farthest old drop relative to player_pos when capped; returns the fresh drop's slot.
func spawn(pos: Vector2, p_exp: int, p_item_id: int, player_pos: Vector2 = Vector2.ZERO) -> int:
	merged = false
	if _exp_count >= int(tuning.max_active):
		var best := -1
		var best_d := -1.0
		for i in _hi:
			if active[i] != 0 and kind[i] == EXP:
				var d := Vector2(x[i] - player_pos.x, y[i] - player_pos.y).length_squared()
				if d > best_d:
					best_d = d
					best = i
		if best >= 0:
			p_exp += exp[best]
			despawn(best)
			merged = true
	return _spawn(pos, p_exp, p_item_id, EXP, 0)


## Drops a persistent potion bundle (hp or mp) independently of the EXP cap; -1 for invalid kinds/counts.
func spawn_potion(pos: Vector2, count: int, p_item_id: int, potion_kind: String) -> int:
	if count <= 0 or not (potion_kind in ["hp", "mp"]):
		return -1
	merged = false
	return _spawn(pos, 0, p_item_id, HP_POTION if potion_kind == "hp" else MP_POTION, count)


## Drops `amount` mesos (the coin sprite follows the amount) independently of the EXP cap; -1 for amount <= 0.
func spawn_meso(pos: Vector2, amount: int) -> int:
	if amount <= 0:
		return -1
	merged = false
	var i := _spawn(pos, 0, MesoDrops.sprite_item(amount), MESO, 0)
	meso[i] = amount
	return i


func _spawn(pos: Vector2, p_exp: int, p_item_id: int, p_kind: int, count: int) -> int:
	if _free.is_empty():
		_grow(capacity() * 2)
	var i := _free[_free.size() - 1]
	_free.resize(_free.size() - 1)
	active[i] = 1
	x[i] = pos.x
	y[i] = pos.y
	var spread := float(tuning.spread)
	vx[i] = rng.randf_range(-spread, spread) if spread > 0.0 else 0.0
	vy[i] = -float(tuning.pop_speed)
	exp[i] = p_exp
	item_id[i] = p_item_id
	kind[i] = p_kind
	potion_count[i] = count
	meso[i] = 0
	state[i] = AIR
	age[i] = 0.0
	_count += 1
	if p_kind == EXP:
		_exp_count += 1
	_hi = maxi(_hi, i + 1)
	return i


## Removes drop i without collecting it.
func despawn(i: int) -> void:
	if i < 0 or i >= capacity() or active[i] == 0:
		return
	active[i] = 0
	_count -= 1
	if kind[i] == EXP:
		_exp_count -= 1
	_free.append(i)
	while _hi > 0 and active[_hi - 1] == 0:
		_hi -= 1


## Draw alpha of drop i: 1, fading to 0 over the last `fade` seconds of its lifetime.
func alpha(i: int) -> float:
	var life := float(tuning.lifetime)
	if life <= 0.0 or i < 0 or i >= capacity() or state[i] == MAGNET or kind[i] != EXP:
		return 1.0
	var f := float(tuning.fade)
	return clampf((life - age[i]) / f, 0.0, 1.0) if f > 0.0 else 1.0


## Moves every drop by dt (pop/fall/land, magnet, collect, expiry). Returns the EXP collected this tick.
func step(dt: float, player_pos: Vector2, magnet_r: float, fhm: FootholdMap, events: Array) -> int:
	var got := 0
	collected_potions = {"hp": 0, "mp": 0}
	step_mesos = 0
	var grav := float(tuning.gravity)
	var fall := float(tuning.fall_speed)
	var acc := float(tuning.magnet_acc)
	var cr := float(tuning.collect_radius)
	var cr2 := cr * cr
	var mr2 := magnet_r * magnet_r
	var life := float(tuning.lifetime)
	var cx := player_pos.x
	var cy := player_pos.y - CENTER_UP
	var floor_y := INF
	var lo_x := -INF
	var hi_x := INF
	if fhm != null and fhm.count() > 0:
		var fb := fhm.bounds()
		floor_y = fb.end.y
		lo_x = fb.position.x
		hi_x = fb.end.x
	for i in _hi:
		if active[i] == 0:
			continue
		var px := x[i]
		var py := y[i]
		var dx := cx - px
		var dy := cy - py
		var d2 := dx * dx + dy * dy
		var st := state[i]
		if st != MAGNET and life > 0.0 and kind[i] == EXP:
			age[i] += dt
			if age[i] >= life and d2 > mr2:
				expired += 1
				expired_exp += exp[i]
				despawn(i)
				continue
		if st != MAGNET and d2 <= mr2:
			st = MAGNET
			state[i] = MAGNET
			vx[i] = float(tuning.magnet_speed)  # vx holds the magnet speed while attracted
		if st == MAGNET:
			var spd := vx[i] + acc * dt
			vx[i] = spd
			var d := sqrt(d2)
			var s := spd * dt
			if d <= s + cr:
				px = cx
				py = cy
			else:
				px += dx / d * s
				py += dy / d * s
			x[i] = px
			y[i] = py
			d2 = (cx - px) * (cx - px) + (cy - py) * (cy - py)
		elif st == AIR:
			var vy0 := vy[i]
			var vy1 := minf(vy0 + grav * dt, fall)
			vy[i] = vy1
			var nx := clampf(px + vx[i] * dt, lo_x, hi_x)
			var ny := py + (vy0 + vy1) * 0.5 * dt
			if ny > py and fhm != null:
				var g := fhm.find_landing(px, py, nx, ny)
				if g >= 0:
					ny = fhm.y_at(g, nx)
					state[i] = REST
					vx[i] = 0.0
					vy[i] = 0.0
			if ny > floor_y + 100.0:
				state[i] = REST  # nothing below: stop rather than fall forever
				vx[i] = 0.0
				vy[i] = 0.0
			x[i] = nx
			y[i] = ny
			d2 = (cx - nx) * (cx - nx) + (cy - ny) * (cy - ny)
		if d2 <= cr2:
			got += exp[i]
			var potion_kind := "hp" if kind[i] == HP_POTION else ("mp" if kind[i] == MP_POTION else "")
			if potion_kind != "":
				collected_potions[potion_kind] = int(collected_potions[potion_kind]) + potion_count[i]
			var is_meso := kind[i] == MESO
			if is_meso:
				step_mesos += meso[i]
			# A meso event carries its amount in `count`.
			events.append({"type": "pickup_collected", "pickup": i, "item_id": item_id[i], "exp": exp[i],
				"pos": Vector2(x[i], y[i]), "kind": "exp" if kind[i] == EXP else ("meso" if is_meso else "potion"),
				"potion_kind": potion_kind, "count": meso[i] if is_meso else potion_count[i]})
			despawn(i)
	collected_exp += got
	collected_mesos += step_mesos
	return got


func _grow(n: int) -> void:
	var old := capacity()
	if n <= old:
		return
	for arr: Variant in [active, state, kind]:
		arr.resize(n)
	for arr: Variant in [x, y, vx, vy, age]:
		arr.resize(n)
	for arr: Variant in [exp, item_id, potion_count, meso]:
		arr.resize(n)
	for i in range(n - 1, old - 1, -1):
		active[i] = 0
		_free.append(i)
